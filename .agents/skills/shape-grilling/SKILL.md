---
name: shape-grilling
description: Grill the user relentlessly about a plan, architecture, decision, or feature idea. Use when the user wants to stress-test their thinking, clarify requirements before coding, or uses any "grill" trigger phrases.
---

# Design Tree Grilling

Interview the user relentlessly until you reach a shared understanding of the feature or decision. Model the problem space as a **design tree**: every high-level decision branches into downstream decisions that depend on it.

## Working the Frontier in Rounds

Work the design tree in **rounds**. The **frontier** consists of every open decision whose prerequisites are already settled: the questions you can ask *now* without guessing at answers you have not heard yet.

1. Ask the entire current frontier in a single round. Number each question and pair it with your recommended answer.
2. Phrase every question and recommendation so a simple "yes" from the user accepts your recommended answer.
3. Wait for the user's responses before advancing to the next round.

Format every round using this exact structure:

```markdown
❓ **Q1** - **<question title>**: <question body, context, and trade-offs>

➡️ **Recommended**: <your concrete recommended answer>

---

❓ **Q2** - **<question title>**: <question body, context, and trade-offs>

➡️ **Recommended**: <your concrete recommended answer>
```

## Advancing the Tree

Each round of user answers reshapes the design tree: settled decisions push the frontier outward and unlock downstream questions that depended on them.

- Recompute the frontier after each reply and present the next round.
- Hold back any question whose framing depends on an unsettled question in the current round; it belongs to a later round.

## Fact Discovery vs. Human Decisions

Finding *facts* is your job, never the user's. Making *decisions* is the user's job.

- When a frontier question requires a fact from the repository (file paths, existing schemas, framework versions, test runners), inspect the codebase or dispatch a read-only exploration subagent with a fresh context window to retrieve it. Never ask the user a question you can answer by reading the workspace.
- Do not block the entire interview on background exploration: treat an in-flight investigation as an unsettled prerequisite, hold only the questions downstream of it, and ask the rest of the ready frontier immediately.

## Completion Criterion

The grilling session is complete when the **frontier is empty**: every branch of the design tree has been visited and zero edge cases remain silently assumed. Summarize the agreed decisions and wait for explicit user confirmation before taking implementation actions.
