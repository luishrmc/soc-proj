#!/usr/bin/env python3
"""loop-guard.py: deterministic loop termination (iteration cap and stagnation).

  loop-guard.py start TASK                 reset the counter for TASK
  loop-guard.py tick TASK GATE [ERRFILE]   record one failed iteration
  loop-guard.py status TASK
Exit codes: 0 keep going, 70 iteration cap exceeded, 71 stagnation (same error twice).
Each tick appends one line to utils/memory/episodes/<TASK>.md.
"""
import hashlib
import json
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / "out" / "loop_state.json"
EPISODES = ROOT / "utils" / "memory" / "episodes"
LIMITS = json.loads((ROOT / ".agents" / "manifest.json").read_text())["limits"]


def load():
    return json.loads(STATE.read_text()) if STATE.exists() else {}


def save(s):
    STATE.parent.mkdir(exist_ok=True)
    STATE.write_text(json.dumps(s, indent=2))


def normalize(text):
    # Strip timestamps, hex ids and line numbers so equal errors hash equally
    text = re.sub(r"\d{2}:\d{2}:\d{2}(\.\d+)?", "", text)
    text = re.sub(r"0x[0-9a-fA-F]+|[0-9a-f]{12,}", "", text)
    text = re.sub(r":\d+(:\d+)?", ":N", text)
    return text.strip()


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    action, task = sys.argv[1], sys.argv[2]
    state = load()

    if action == "start":
        state[task] = {"n": 0, "hashes": []}
        save(state)
        print(f"[OK][loop-guard] {task}: counter reset (max {LIMITS['max_iterations']}).")
        return 0

    t = state.setdefault(task, {"n": 0, "hashes": []})
    if action == "status":
        print(json.dumps(t))
        return 0

    if action == "tick":
        gate = sys.argv[3] if len(sys.argv) > 3 else "unknown"
        err = Path(sys.argv[4]).read_text(errors="replace") if len(sys.argv) > 4 else ""
        h = hashlib.sha256(normalize(err).encode()).hexdigest()[:12]
        t["n"] += 1
        t["hashes"].append(h)
        save(state)

        EPISODES.mkdir(parents=True, exist_ok=True)
        ep = EPISODES / f"{task}.md"
        if not ep.exists():
            ep.write_text(f"# Episodes for task {task}\n\n| iter | gate | error hash | time |\n|---|---|---|---|\n")
        with ep.open("a") as f:
            f.write(f"| {t['n']} | {gate} | {h} | {time.strftime('%Y-%m-%d %H:%M')} |\n")

        k = LIMITS["stagnation_cycles"]
        if len(t["hashes"]) >= k and len(set(t["hashes"][-k:])) == 1 and err:
            print(f"[STOP][loop-guard] {task}: same error {k}x in a row. Escalate to the human.", file=sys.stderr)
            return 71
        if t["n"] >= LIMITS["max_iterations"]:
            print(f"[STOP][loop-guard] {task}: reached {t['n']} failed iterations. Rollback and escalate.", file=sys.stderr)
            return 70
        print(f"[OK][loop-guard] {task}: iteration {t['n']}/{LIMITS['max_iterations']}.")
        return 0

    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
