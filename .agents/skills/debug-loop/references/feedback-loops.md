# 10-Tier Bug Reproduction Hierarchy

Construct the Phase 1 **red feedback loop** in `debug-loop` by selecting the highest-leverage mechanism that reaches the bug:

| Rank | Mechanism | Best Used When |
| :---: | :--- | :--- |
| **1** | **Failing Seam Test** | Bug is reachable through a unit, integration, or e2e test at a public module interface. |
| **2** | **Curl / HTTP Script** | Bug manifests in an API endpoint or server route on a local dev server. |
| **3** | **CLI Fixture Invocation** | Bug occurs in a command-line tool, compiler, or batch pipeline; diff stdout/stderr against expected output. |
| **4** | **Headless Browser Script** | Bug requires real DOM layout, client-side state, or network interception (Playwright / Puppeteer). |
| **5** | **Captured Trace Replay** | Bug depends on a specific webhook payload, event sequence, or production request; save fixture to disk and replay in isolation. |
| **6** | **Minimal Throwaway Harness** | Full app boot is slow; spin up a tiny script importing only the target module with stubbed boundary adapters. |
| **7** | **Property / Fuzz Loop** | Bug is an intermittent edge case ("sometimes returns NaN"); feed 1,000 seeded random inputs until invariant breaks. |
| **8** | **Automated Bisection (`git bisect run`)** | Regression appeared between two known-good and known-bad commits, versions, or dataset snapshots. |
| **9** | **Differential Harness** | Output diverged from a reference implementation or prior version; feed identical inputs to both and assert on diff. |
| **10** | **Structured HITL Script (`scripts/hitl-loop.template.sh`)** | Last resort when a human must click through an external OAuth/hardware step; script prompts the human and captures structured `KEY=VALUE` output. |
