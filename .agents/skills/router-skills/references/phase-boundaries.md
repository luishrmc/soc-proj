# Phase Boundaries Decision Tree

A **phase** is a cohesive unit of work inside a session (shaping, ticket implementation, QA, or retrospective). Make context transition decisions strictly **at the boundary between phases**, never mid-phase.

## The Five Boundary Options (Ordered Decision Tree)

Evaluate these five options from top to bottom at every phase boundary. The **first "yes" wins**:

| Priority | Action | Condition (`First YES Wins`) | Trade-Off |
| :---: | :--- | :--- | :--- |
| **1** | **Continue** | Does the next phase need this session as a **primary source** (e.g., `/shape-grill` -> `/shape-spec` -> `/shape-tickets`), AND are you still inside the ~150k token **smart zone**? | Zero loss, zero overhead. |
| **2** | **`/clear`** | Is the current context disposable for what comes next (e.g., finished Ticket 01 and moving to self-contained Ticket 02)? | Instant full window recovery; prior session remains in logs. |
| **3** | **`/env-handoff`** | Is the work **traveling** across harnesses, into a new directory (`/shape-prototype`), to a colleague, or forking a mid-phase side task? | Writes a portable pointer file to `$TMPDIR`. |
| **4** | **Subagent** | Can the next task run unattended (AFK) with a tightly scoped brief (e.g., `review-diff`, `research-topic`, or `dev-parallel` tickets)? | Runs in a fresh context window and returns a compact report. |
| **5** | **`/compact`** | Relevant context, same harness, same directory, human in the loop, and approaching the edge of the smart zone. | Summarizes primary source into a secondary source; pass a focus hint (`/compact focus on X`). |
