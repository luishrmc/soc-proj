#!/usr/bin/env python3
"""memory-check.py: keep utils/memory consistent and bounded.

Checks:
  * every module digest lists `sources` with sha256 and the hashes match the files
    (mismatch -> STALE, exit 1 so the iteration cannot end with outdated memory)
  * size limits from the manifest (digests, handoffs, index, lessons)
  * `--update MODULE` rewrites the hashes of a digest after the agent refreshed its body
Digest frontmatter format:
  ---
  module: spi_slave
  status: draft|verified
  sources:
    - cora7z/app/hw/src/spi_slave.vhdl sha256=<hex>
  gates_passed: [vhdl-lint, vhdl-sim]
  ---
Exit codes: 0 ok, 1 stale or over limit.
"""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MEM = ROOT / "utils" / "memory"
LIM = json.loads((ROOT / ".agents" / "manifest.json").read_text())["limits"]
SRC_RE = re.compile(r"^\s+-\s+(\S+)\s+sha256=(\S*)\s*$")


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def lines(p):
    return len(p.read_text().splitlines())


def update(module):
    f = MEM / "modules" / f"{module}.md"
    out = []
    for line in f.read_text().splitlines():
        m = SRC_RE.match(line)
        if m and (ROOT / m.group(1)).is_file():
            line = f"  - {m.group(1)} sha256={sha(m.group(1))}"
        out.append(line)
    f.write_text("\n".join(out) + "\n")
    print(f"[OK][memory-check] Updated hashes in {f.relative_to(ROOT)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--update")
    a = ap.parse_args()
    if a.update:
        update(a.update)

    problems = []
    for d in sorted((MEM / "modules").glob("*.md")):
        if lines(d) > LIM["digest_max_lines"]:
            problems.append(f"{d.name}: over {LIM['digest_max_lines']} lines")
        for line in d.read_text().splitlines():
            m = SRC_RE.match(line)
            if not m:
                continue
            path, want = m.groups()
            if not (ROOT / path).is_file():
                problems.append(f"{d.name}: source missing {path}")
            elif want != sha(path):
                problems.append(f"{d.name}: STALE {path}")
    for h in sorted((MEM / "handoff").glob("*.md")):
        if lines(h) > LIM["handoff_max_lines"]:
            problems.append(f"{h.name}: handoff over {LIM['handoff_max_lines']} lines")
    for name, key in (("INDEX.md", "index_max_lines"), ("lessons.md", "lessons_max_lines")):
        f = MEM / name
        if f.exists() and lines(f) > LIM[key]:
            problems.append(f"{name}: over {LIM[key]} lines (compact it)")

    if problems:
        for p in problems:
            print(f"[ERROR][memory-check] {p}", file=sys.stderr)
        return 1
    print("[OK][memory-check] Memory is fresh and within limits.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
