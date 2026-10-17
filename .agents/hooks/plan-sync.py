#!/usr/bin/env python3
"""plan-sync.py: project management over utils/plan/*.csv (single writer: orchestrator).

  plan-sync.py sync                       validate, then regenerate STATUS.md / CHANGELOG.md / .state.json
  plan-sync.py check                      validate only (no writes)
  plan-sync.py set TASK STATUS [--evidence gate:TASK|file:PATH] [--notes TEXT]
                                          change a task safely (applies rules, then syncs)
  plan-sync.py next                       list tasks whose dependencies are all done

Rules enforced:
  * statuses: Pendente, Em andamento, Pendente de validação, Concluída, Bloqueada
  * legal transitions only (see TRANSITIONS)
  * "Em andamento" needs every dependency Concluída (override: Notas contains "waiver:")
  * "Concluída" needs evidence:
      gate:<task>  -> out/gates/<task>.json with every required gate PASS (no SKIPPED/FAIL)
      file:<path>  -> existing file; allowed only when the phase has no required gates
  * IDs unique, dependencies exist, no dependency cycles
Exit codes: 0 ok, 1 validation error.
"""
import argparse
import csv
import io
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = ROOT / "utils" / "plan"
SCHED = PLAN / "Cronograma_e_Tarefas.csv"
RISKS = PLAN / "Riscos_e_Bloqueios.csv"
STATE = PLAN / ".state.json"
STATUS_MD = PLAN / "STATUS.md"
CHANGELOG = PLAN / "CHANGELOG.md"
MANIFEST = json.loads((ROOT / ".agents" / "manifest.json").read_text())

STATUSES = ["Pendente", "Em andamento", "Pendente de validação", "Concluída", "Bloqueada"]
TRANSITIONS = {
    "Pendente": {"Em andamento", "Bloqueada"},
    "Em andamento": {"Pendente", "Pendente de validação", "Concluída", "Bloqueada"},
    "Pendente de validação": {"Em andamento", "Concluída", "Bloqueada"},
    "Concluída": {"Em andamento"},
    "Bloqueada": {"Pendente", "Em andamento"},
}
BASE_COLS = ["ID da Tarefa", "Fase", "Atividade Detalhada", "Entregável Associado",
             "Duração Estimada (dias)", "Dependências", "Status", "Prioridade"]
NEW_COLS = ["Início", "Fim", "Evidência", "Atualizado em", "Notas"]
RISK_COLS = ["ID", "Tarefa", "Descrição", "Impacto", "Mitigação", "Status", "Aberto em", "Resolvido em"]


def today():
    return time.strftime("%Y-%m-%d")


def read_csv(path):
    raw = path.read_bytes().decode("utf-8")
    eol = "\r\n" if "\r\n" in raw else "\n"
    rows = list(csv.DictReader(io.StringIO(raw, newline="")))
    return rows, eol


def write_csv(path, cols, rows, eol):
    buf = io.StringIO(newline="")
    w = csv.DictWriter(buf, fieldnames=cols, lineterminator=eol, extrasaction="ignore")
    w.writeheader()
    for r in rows:
        w.writerow({c: r.get(c, "") for c in cols})
    path.write_bytes(buf.getvalue().encode("utf-8"))


def deps(row):
    d = (row.get("Dependências") or "").strip()
    return [] if d in ("", "-") else [x.strip() for x in d.split(",") if x.strip()]


def required_gates(row):
    tid = row["ID da Tarefa"]
    by_task = MANIFEST["gates_by_task"]
    return by_task.get(tid, MANIFEST["gates_by_phase"].get(row["Fase"], []))


def evidence_ok(row):
    ev = (row.get("Evidência") or "").strip()
    need = required_gates(row)
    if ev.startswith("gate:"):
        f = ROOT / "out" / "gates" / f"{ev[5:]}.json"
        if not f.is_file():
            return f"evidence file missing: {f.relative_to(ROOT)}"
        gates = json.loads(f.read_text()).get("gates", {})
        bad = [g for g in need if gates.get(g, {}).get("status") != "PASS"]
        if bad:
            return "required gates not PASS: " + ", ".join(
                f"{g}={gates.get(g, {}).get('status', 'absent')}" for g in bad)
        return None
    if ev.startswith("file:"):
        if need:
            return f"phase {row['Fase']} requires gate evidence ({', '.join(need)}), not a file"
        return None if (ROOT / ev[5:]).is_file() else f"evidence file missing: {ev[5:]}"
    return "Concluída requires Evidência (gate:<task> or file:<path>)"


def load():
    rows, eol = read_csv(SCHED)
    for r in rows:
        for c in NEW_COLS:
            r.setdefault(c, "")
    return rows, eol


def validate(rows, prev, enforce_evidence=True):
    errs = []
    ids = [r["ID da Tarefa"] for r in rows]
    if len(set(ids)) != len(ids):
        errs.append("duplicate task IDs")
    by_id = {r["ID da Tarefa"]: r for r in rows}
    for r in rows:
        tid, st = r["ID da Tarefa"], r["Status"]
        if st not in STATUSES:
            errs.append(f"{tid}: invalid status '{st}'")
            continue
        for d in deps(r):
            if d not in by_id:
                errs.append(f"{tid}: unknown dependency {d}")
        old = prev.get(tid)
        if old is not None and old != st:
            if st not in TRANSITIONS.get(old, set()):
                errs.append(f"{tid}: illegal transition {old} -> {st}")
            if old == "Concluída" and not (r.get("Notas") or "").strip():
                errs.append(f"{tid}: reopening a Concluída task needs a note")
        if st == "Em andamento" and "waiver:" not in (r.get("Notas") or ""):
            open_deps = [d for d in deps(r) if d in by_id and by_id[d]["Status"] != "Concluída"]
            if open_deps:
                errs.append(f"{tid}: dependencies not Concluída: {', '.join(open_deps)}")
        if st == "Concluída" and enforce_evidence and (old != "Concluída"):
            msg = evidence_ok(r)
            if msg:
                errs.append(f"{tid}: {msg}")
    # cycle check (DFS)
    seen, stack = set(), set()

    def dfs(n):
        if n in stack:
            return True
        if n in seen or n not in by_id:
            return False
        seen.add(n)
        stack.add(n)
        cyc = any(dfs(d) for d in deps(by_id[n]))
        stack.discard(n)
        return cyc

    if any(dfs(i) for i in ids):
        errs.append("dependency cycle detected")
    return errs


def critical_path(rows):
    by_id = {r["ID da Tarefa"]: r for r in rows}
    memo = {}

    def cost(n):
        if n in memo:
            return memo[n]
        r = by_id[n]
        own = 0 if r["Status"] == "Concluída" else float(r["Duração Estimada (dias)"] or 0)
        best = max([cost(d)[0] for d in deps(r)], default=0)
        prev = max(deps(r), key=lambda d: cost(d)[0], default=None)
        memo[n] = (best + own, prev)
        return memo[n]

    end = max(by_id, key=lambda n: cost(n)[0])
    path, n = [], end
    while n:
        path.append(n)
        n = cost(n)[1]
    return list(reversed(path)), cost(end)[0]


def render_status(rows):
    by_id = {r["ID da Tarefa"]: r for r in rows}
    out = ["# Project Status", "",
           f"_Generated by `.agents/hooks/plan-sync.py` on {today()}. Do not edit by hand._", ""]
    out += ["## Progress by phase", "", "| Phase | Done | Validation | In progress | Blocked | Pending | Total |",
            "|---|---|---|---|---|---|---|"]
    for ph in sorted({r["Fase"] for r in rows}, key=int):
        rs = [r for r in rows if r["Fase"] == ph]
        c = lambda s: sum(1 for r in rs if r["Status"] == s)
        out.append(f"| {ph} | {c('Concluída')} | {c('Pendente de validação')} | {c('Em andamento')} | "
                   f"{c('Bloqueada')} | {c('Pendente')} | {len(rs)} |")
    total_days = sum(float(r["Duração Estimada (dias)"] or 0) for r in rows)
    done_days = sum(float(r["Duração Estimada (dias)"] or 0) for r in rows if r["Status"] == "Concluída")
    out += ["", f"Estimated effort completed: {done_days:g} of {total_days:g} days "
                f"({100 * done_days / total_days:.0f}%)." if total_days else "", ""]

    def listing(title, sel):
        out.append(f"## {title}")
        out.append("")
        items = [r for r in rows if sel(r)]
        if not items:
            out.extend(["None.", ""])
            return
        for r in items:
            extra = f" ({r['Notas']})" if r.get("Notas") else ""
            out.append(f"- **{r['ID da Tarefa']}** {r['Atividade Detalhada']}{extra}")
        out.append("")

    listing("In progress", lambda r: r["Status"] == "Em andamento")
    listing("Waiting for validation", lambda r: r["Status"] == "Pendente de validação")
    listing("Blocked", lambda r: r["Status"] == "Bloqueada")
    listing("Next eligible tasks", lambda r: r["Status"] == "Pendente" and
            all(by_id[d]["Status"] == "Concluída" for d in deps(r)))
    path, days = critical_path(rows)
    out += ["## Remaining critical path", "", " -> ".join(path) + f"  ({days:g} days)", ""]
    if RISKS.exists():
        rrows, _ = read_csv(RISKS)
        openr = [r for r in rrows if r.get("Status", "").strip().lower() not in ("resolvido", "fechado")]
        out += ["## Open risks", ""]
        out += [f"- **{r['ID']}** (task {r['Tarefa']}): {r['Descrição']}" for r in openr] or ["None."]
        out.append("")
    return "\n".join(out) + "\n"


def sync(rows, eol, prev):
    for r in rows:
        tid, st = r["ID da Tarefa"], r["Status"]
        old = prev.get(tid)
        if old != st and old is not None:
            r["Atualizado em"] = today()
            if st == "Em andamento" and not r["Início"]:
                r["Início"] = today()
            if st == "Concluída":
                r["Fim"] = today()
            if old == "Concluída":
                r["Fim"] = ""
    write_csv(SCHED, BASE_COLS + NEW_COLS, rows, eol)

    if not CHANGELOG.exists():
        CHANGELOG.write_text("# Plan changelog\n\nAppend-only. One line per status change.\n\n"
                             "| date | task | change | evidence |\n|---|---|---|---|\n")
    with CHANGELOG.open("a") as f:
        for r in rows:
            old = prev.get(r["ID da Tarefa"])
            if old is not None and old != r["Status"]:
                f.write(f"| {today()} | {r['ID da Tarefa']} | {old} -> {r['Status']} | "
                        f"{r.get('Evidência') or '-'} |\n")
    STATE.write_text(json.dumps({r["ID da Tarefa"]: r["Status"] for r in rows}, indent=2, ensure_ascii=False) + "\n")
    STATUS_MD.write_text(render_status(rows))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["sync", "check", "set", "next"])
    ap.add_argument("task", nargs="?")
    ap.add_argument("status", nargs="?")
    ap.add_argument("--evidence")
    ap.add_argument("--notes")
    a = ap.parse_args()

    rows, eol = load()
    prev = json.loads(STATE.read_text()) if STATE.exists() else {}

    if a.action == "next":
        by_id = {r["ID da Tarefa"]: r for r in rows}
        for r in rows:
            if r["Status"] == "Pendente" and all(by_id[d]["Status"] == "Concluída" for d in deps(r)):
                print(f"{r['ID da Tarefa']}\tphase {r['Fase']}\t{r['Atividade Detalhada']}")
        return 0

    if a.action == "set":
        if not a.task or not a.status:
            print("usage: set TASK STATUS [--evidence ...] [--notes ...]", file=sys.stderr)
            return 1
        row = next((r for r in rows if r["ID da Tarefa"] == a.task), None)
        if row is None:
            print(f"[ERROR][plan-sync] unknown task {a.task}", file=sys.stderr)
            return 1
        row["Status"] = a.status
        if a.evidence is not None:
            row["Evidência"] = a.evidence
        if a.notes is not None:
            row["Notas"] = a.notes

    errs = validate(rows, prev)
    if errs:
        for e in errs:
            print(f"[ERROR][plan-sync] {e}", file=sys.stderr)
        return 1
    if a.action == "check":
        print("[OK][plan-sync] Plan is valid.")
        return 0
    sync(rows, eol, prev)
    print("[OK][plan-sync] Plan synced (STATUS.md, CHANGELOG.md, .state.json).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
