#!/usr/bin/env python3
"""orchestrator_dispatch.py: Supervisor-worker dispatch and adversarial review engine.

Functions:
  1. Inspect and list configured multi-agent topologies (.agents/manifest.json, .agents/agents/*.md).
  2. Synthesize structured PTCF (Persona, Task, Context, Format) dispatch prompts for worker agents.
  3. Validate agent write scopes and tool boundaries.
  4. Generate and validate adversarial Technical Critic review gates (JSON APPROVE/REJECT).

Usage:
  python3 .agents/hooks/orchestrator_dispatch.py --list
  python3 .agents/hooks/orchestrator_dispatch.py --dispatch <agent> --task <task-id> [--goal "..."]
  python3 .agents/hooks/orchestrator_dispatch.py --review --task <task-id> [--verdict-file <json-file>]
"""
import argparse
import csv
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = ROOT / ".agents" / "manifest.json"
AGENTS_DIR = ROOT / ".agents" / "agents"
PLAN_CSV = ROOT / "utils" / "plan" / "Cronograma_e_Tarefas.csv"
MEMORY_DIR = ROOT / "utils" / "memory"
OUT_DIR = ROOT / "out"


def load_manifest():
    if not MANIFEST_PATH.is_file():
        raise FileNotFoundError(f"Manifest not found: {MANIFEST_PATH}")
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def load_agent_metadata(agent_name):
    manifest = load_manifest()
    for ag in manifest.get("agents", []):
        if ag["name"] == agent_name:
            return ag
    return None


def get_task_info(task_id):
    if not PLAN_CSV.is_file():
        return None
    with open(PLAN_CSV, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("ID da Tarefa") == str(task_id):
                return row
    return None


def list_agents():
    manifest = load_manifest()
    print("=" * 80)
    print(f"{'AGENT':<25} {'MODEL':<8} {'ROLE'}")
    print("=" * 80)
    for ag in manifest.get("agents", []):
        name = ag["name"]
        model = ag.get("model", "pro")
        role = ag.get("role", "")
        print(f"{name:<25} {model:<8} {role}")
        write_globs = ", ".join(ag.get("write", []))
        print(f"  Write scope: {write_globs}")
        tools = ", ".join(ag.get("tools_allowed", []))
        print(f"  Tools:       {tools}")
        print("-" * 80)


def generate_ptcf_prompt(agent_meta, task_row, goal=None, iteration=1, feedback=None):
    agent_name = agent_meta["name"]
    task_id = task_row.get("ID da Tarefa", "N/A")
    task_desc = task_row.get("Descrição da Tarefa", "")
    phase = task_row.get("Fase", "")
    manifest = load_manifest()
    gates = manifest.get("gates_by_task", {}).get(task_id, manifest.get("gates_by_phase", {}).get(str(phase), []))

    # Collect relevant digests
    digests = [str(p.relative_to(ROOT)) for p in (MEMORY_DIR / "modules").glob("*.md")]

    # Dispatch contract JSON
    contract = {
        "task": task_id,
        "agent": agent_name,
        "goal": goal or task_desc,
        "iteration": iteration,
        "handoff": f"utils/memory/handoff/{task_id}.md",
        "digests": digests,
        "required_gates": gates,
        "feedback": feedback or [],
    }

    # Structured PTCF Prompt for Gemini 3.8 Flash
    prompt_lines = [
        f"# SYSTEM CONTEXT: AUTONOMOUS SUBAGENT DISPATCH ({agent_name})",
        "",
        "## 1. PERSONA & SCOPE",
        f"You are `{agent_name}`, operating under the following designated role:",
        f"> {agent_meta.get('role')}",
        f"Your model tier is `{agent_meta.get('model')}`. You must execute strictly within your assigned tool and write boundaries.",
        f"Allowed write paths: {json.dumps(agent_meta.get('write', []))}",
        "",
        "## 2. TASK OBJECTIVE",
        f"- **Task ID**: {task_id}",
        f"- **Phase**: {phase}",
        f"- **Goal**: {goal or task_desc}",
        f"- **Iteration**: {iteration}",
        f"- **Required Verification Gates**: {gates}",
        "",
        "## 3. CONTEXT & ENVIRONMENT REFERENCES",
        "- Hardware: Digilent Cora Z7-10 (XC7Z010-1CLG400C, ARM Cortex-A9 @ 667 MHz, Artix-7 fabric)",
        "- Workspace Invariants: `GEMINI.md`, `INTERFACES.md`, `utils/memory/INDEX.md`",
        f"- Active Module Digests: {', '.join(digests)}",
        f"- Handoff State: `utils/memory/handoff/{task_id}.md`",
        "",
        "## 4. EXECUTION INSTRUCTIONS",
        "1. Inspect existing interfaces and tests before editing files.",
        "2. Implement synthesizable, deterministic code adhering strictly to zero-dynamic-allocation rules.",
        "3. Run designated verification gates to confirm correctness.",
        "4. Record handoff state and update digest hashes upon completion.",
        "",
        "## 5. RESPONSE FORMAT",
        "Conclude your execution turn with a structured JSON completion payload:",
        "```json",
        json.dumps(
            {
                "task": task_id,
                "status": "ready_for_gates",
                "files_changed": [],
                "handoff_updated": True,
                "digests_updated": digests,
            },
            indent=2,
        ),
        "```",
        "",
        "---",
        "### Raw Dispatch Contract",
        "```json",
        json.dumps(contract, indent=2),
        "```",
    ]

    return "\n".join(prompt_lines), contract


def dispatch_agent(agent_name, task_id, goal=None, iteration=1):
    agent_meta = load_agent_metadata(agent_name)
    if not agent_meta:
        print(f"[ERROR][dispatch] Unknown agent: {agent_name}", file=sys.stderr)
        return 1

    task_row = get_task_info(task_id)
    if not task_row:
        print(f"[ERROR][dispatch] Task {task_id} not found in {PLAN_CSV.relative_to(ROOT)}", file=sys.stderr)
        return 1

    prompt, contract = generate_ptcf_prompt(agent_meta, task_row, goal, iteration)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_file = OUT_DIR / f"dispatch_{task_id}.md"
    out_file.write_text(prompt, encoding="utf-8")
    contract_file = OUT_DIR / f"dispatch_{task_id}.json"
    contract_file.write_text(json.dumps(contract, indent=2), encoding="utf-8")

    print(f"[OK][dispatch] Dispatched task {task_id} to {agent_name}.")
    print(f"[OK][dispatch] Dispatch specification written to: {out_file.relative_to(ROOT)}")
    print(f"[OK][dispatch] Dispatch contract written to:      {contract_file.relative_to(ROOT)}")
    print("\n--- PROMPT PREVIEW ---")
    print(prompt[:600] + "\n... [truncated] ...\n")
    return 0


def generate_critic_review(task_id, verdict_file=None):
    if verdict_file:
        vpath = Path(verdict_file)
        if not vpath.is_file():
            print(f"[ERROR][critic] Verdict file not found: {verdict_file}", file=sys.stderr)
            return 1
        try:
            data = json.loads(vpath.read_text(encoding="utf-8"))
        except Exception as e:
            print(f"[ERROR][critic] Invalid JSON in verdict file: {e}", file=sys.stderr)
            return 1

        verdict = data.get("verdict")
        blockers = data.get("blockers", [])
        optimizations = data.get("optimizations", [])

        print("=" * 80)
        print(f"TECHNICAL CRITIC REVIEW RESULT FOR TASK {task_id}")
        print("=" * 80)
        print(f"VERDICT: {verdict}")
        print(f"BLOCKERS: {len(blockers)}")
        for b in blockers:
            sev = b.get("severity", "CRITICAL")
            loc = b.get("location", "unknown")
            desc = b.get("description", "")
            rem = b.get("remediation", "")
            print(f"  - [{sev}] {loc}: {desc}")
            if rem:
                print(f"    Remediation: {rem}")

        print(f"OPTIMIZATIONS: {len(optimizations)}")
        for o in optimizations:
            loc = o.get("location", "unknown")
            desc = o.get("description", "")
            print(f"  - {loc}: {desc}")

        if verdict == "APPROVE" and len(blockers) == 0:
            print("\n[OK][critic] Task approved by Technical Critic.")
            return 0
        else:
            print("\n[REJECT][critic] Task rejected by Technical Critic due to blockers.")
            return 1

    # Otherwise generate the prompt for technical-critic-agent
    task_row = get_task_info(task_id) or {"Descrição da Tarefa": f"Task {task_id}"}
    git_diff = subprocess.run(["git", "diff", "HEAD~1"], capture_output=True, text=True).stdout
    if not git_diff:
        git_diff = subprocess.run(["git", "diff"], capture_output=True, text=True).stdout

    critic_prompt = [
        "# TECHNICAL CRITIC REVIEW REQUEST",
        f"Target Task: {task_id} ({task_row.get('Descrição da Tarefa')})",
        "",
        "## Review Mission",
        "Perform an adversarial, read-only audit of the code changes, gate results, and architectural conformance.",
        "Check against:",
        "1. Spec conformance with utils/TEMA.md and cora7z/app/hw/src/INTERFACES.md.",
        "2. RTL correctness: CDC synchronizers, no combinational loops, synchronous resets.",
        "3. Firmware invariants: zero dynamic allocation, ARM PMU calibration, cache coherence.",
        "4. Reproducibility: no uncommitted transient artifacts, build repeatability.",
        "",
        "## Recent Code Diff",
        "```diff",
        git_diff[:15000] if git_diff else "(No diff detected)",
        "```",
        "",
        "## Output Schema",
        "Output strictly and exclusively the JSON payload format (no markdown fences, no greetings):",
        json.dumps(
            {
                "verdict": "APPROVE",
                "gate_id": str(task_id),
                "blockers": [],
                "optimizations": [],
            },
            indent=2,
        ),
    ]

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_file = OUT_DIR / f"critic_review_{task_id}.md"
    out_file.write_text("\n".join(critic_prompt), encoding="utf-8")
    print(f"[OK][critic] Generated Technical Critic audit prompt: {out_file.relative_to(ROOT)}")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Orchestrator worker dispatch and review tool")
    parser.add_argument("--list", action="store_true", help="List all defined agents")
    parser.add_argument("--dispatch", metavar="AGENT", help="Agent name to dispatch")
    parser.add_argument("--task", metavar="TASK_ID", help="Task ID from Cronograma_e_Tarefas.csv")
    parser.add_argument("--goal", metavar="GOAL", help="Optional specific goal")
    parser.add_argument("--iteration", type=int, default=1, help="Iteration number (default: 1)")
    parser.add_argument("--review", action="store_true", help="Generate or evaluate Technical Critic review")
    parser.add_argument("--verdict-file", metavar="PATH", help="Path to critic JSON verdict to evaluate")

    args = parser.parse_args()

    if args.list:
        list_agents()
        return 0

    if args.dispatch:
        if not args.task:
            print("[ERROR] --dispatch requires --task <task-id>", file=sys.stderr)
            return 2
        return dispatch_agent(args.dispatch, args.task, args.goal, args.iteration)

    if args.review:
        if not args.task:
            print("[ERROR] --review requires --task <task-id>", file=sys.stderr)
            return 2
        return generate_critic_review(args.task, args.verdict_file)

    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
