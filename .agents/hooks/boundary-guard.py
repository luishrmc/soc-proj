#!/usr/bin/env python3
"""boundary-guard.py: enforce per-agent write globs from .agents/manifest.json.

  boundary-guard.py snapshot                 record hashes of all changed/untracked files
  boundary-guard.py check --agent NAME       fail if NAME changed anything outside its globs
Protected files (manifest "protected") may only change with ALLOW_PROTECTED=1.
Exit codes: 0 ok, 1 violation, 2 usage error.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SNAP = ROOT / "out" / "boundary_snapshot.json"
MANIFEST = ROOT / ".agents" / "manifest.json"


def glob_to_regex(pat):
    out, i = "", 0
    while i < len(pat):
        c = pat[i]
        if pat[i:i + 3] == "**/":
            out += "(?:.*/)?"
            i += 3
        elif pat[i:i + 2] == "**":
            out += ".*"
            i += 2
        elif c == "*":
            out += "[^/]*"
            i += 1
        elif c == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(c)
            i += 1
    return re.compile("^" + out + "$")


def matches(path, globs):
    return any(glob_to_regex(g).match(path) for g in globs)


def changed_files():
    res = subprocess.run(
        ["git", "status", "--porcelain", "-uall"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    )
    files = {}
    for line in res.stdout.splitlines():
        path = line[3:].split(" -> ")[-1].strip().strip('"')
        p = ROOT / path
        files[path] = hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "DELETED"
    return files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["snapshot", "check"])
    ap.add_argument("--agent")
    a = ap.parse_args()

    if a.action == "snapshot":
        SNAP.parent.mkdir(exist_ok=True)
        SNAP.write_text(json.dumps(changed_files(), indent=2))
        print(f"[OK][boundary-guard] Snapshot saved ({SNAP.relative_to(ROOT)}).")
        return 0

    if not a.agent:
        print("[ERROR][boundary-guard] --agent is required for check", file=sys.stderr)
        return 2
    manifest = json.loads(MANIFEST.read_text())
    agent = next((x for x in manifest["agents"] if x["name"] == a.agent), None)
    if agent is None:
        print(f"[ERROR][boundary-guard] Unknown agent {a.agent}", file=sys.stderr)
        return 2

    base = json.loads(SNAP.read_text()) if SNAP.exists() else {}
    now = changed_files()
    delta = [p for p, h in now.items() if base.get(p) != h]
    delta += [p for p in base if p not in now]  # reverted files count as touched

    protected_ok = os.environ.get("ALLOW_PROTECTED") == "1"
    bad = []
    for p in sorted(set(delta)):
        if matches(p, manifest["protected"]):
            if not protected_ok:
                bad.append((p, "protected file"))
        elif not matches(p, agent["write"]):
            bad.append((p, "outside agent write globs"))
    if bad:
        for p, why in bad:
            print(f"[ERROR][boundary-guard] {a.agent}: {p} ({why})", file=sys.stderr)
        return 1
    print(f"[OK][boundary-guard] {a.agent}: {len(delta)} changed file(s), all within bounds.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
