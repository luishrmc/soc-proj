---
name: arch-survey
description: "Scan the codebase for shallow modules and deepening opportunities, render a visual HTML report in $TMPDIR, and grill through selected candidates."
disable-model-invocation: true
---

# Codebase Architecture Survey

Scan the repository for architectural friction and propose **deepening opportunities** that consolidate shallow modules into deep, testable ones.

## Process

### 1. Scope by Churn and Explore

1. Call the Skill tool with `arch-design` (or read `skills/arch-design/SKILL.md`) to load the canonical vocabulary (**module**, **interface**, **depth**, **seam**, **adapter**, **leverage**, **locality**) and the **deletion test**.
2. Read `GLOSSARY.md` and `docs/adr/` so proposals respect established domain terms and architectural decisions.
3. Focus on high-churn hotspots: if the user specifies a subsystem, inspect it directly; otherwise inspect recent commit history (`git log --oneline -n 50`) to identify frequently modified paths where deepening yields the highest payoff.
4. Dispatch an exploration subagent with a **fresh context window** to locate friction points:
   - Concepts scattered across many small pass-through files (poor **locality**).
   - **Shallow modules** whose interface is nearly as complex as their implementation.
   - Tightly coupled modules leaking internal state across their **seams**.
   - Subsystems that are difficult to test through their public interface.
5. Apply the **deletion test** to every candidate: keep candidates where consolidating wrappers concentrates complexity behind a simpler interface.

### 2. Render Visual HTML Report in `$TMPDIR`

1. Generate a self-contained HTML report at `${TMPDIR:-/tmp}/architecture-review-$(date +%s).html` following the scaffold and visual patterns in [assets/html-report.md](./assets/html-report.md). Keep generated report files out of the repository working tree.
2. Render each candidate as a visual card containing:
   - **Involved Files** and dependency category (`in-process`, `local-substitutable`, `ports & adapters`, `mock`)
   - **Side-by-Side Before / After Diagram** (using Mermaid CDN flowcharts and custom Tailwind/SVG mass or cross-section diagrams)
   - **Problem, Solution, and Locality/Leverage Wins** written strictly in `GLOSSARY.md` and `arch-design` terms
   - **Recommendation Badge** (`Strong`, `Worth exploring`, or `Speculative`) plus a **Top Recommendation** summary card
3. Open the HTML file for the user (`xdg-open` on Linux, `open` on macOS) and print the absolute file path. Ask: *"Which of these candidates would you like to explore?"*

### 3. Grill and Model the Chosen Candidate

Once the user selects a candidate:

1. Call `shape-grilling` and `shape-domain` to walk the design tree for the deepened module (constraints, seam placement, surviving tests, and inline `GLOSSARY.md` updates).
2. If the user wants to compare multiple interface shapes for the deepened module, execute the parallel subagent pattern in `skills/arch-design/assets/design-it-twice.md`.
3. If the user rejects a candidate for a non-obvious, permanent architectural reason, offer to record a concise ADR in `docs/adr/` so future surveys do not re-propose it.
