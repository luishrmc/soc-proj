# Skill Mechanics & Writing for Agents

Reference for authoring and pruning agent documents (`SKILL.md`, `GEMINI.md`, `AGENTS.md`, `CLAUDE.md`, and disclosed reference files).

## 1. The Two Loads & Invocation Choice

Every skill trades off two budgets:

- **Context Load**: Permanent token and attention cost on the agent's context window every turn.
- **Cognitive Load**: Human memory cost of knowing which slash commands exist and when to invoke them.

Split skills cleanly by invocation:

- **User-Invoked Orchestrators (`disable-model-invocation: true`)**: Reachable only when the human types `/skill-name`. Zero context load. Write a concise 1-line human-facing `description` and strip trigger lists. A user-invoked skill can invoke model-invoked skills, but never another user-invoked skill.
- **Model-Invoked Disciplines (Omit `disable-model-invocation`)**: Reachable autonomously by the agent or called by other skills via the Skill tool. The `description` is an always-loaded **context pointer**: front-load the leading word, list one trigger per distinct branch, and collapse synonyms.

## 2. Information Hierarchy & Progressive Disclosure

Rank content across three tiers:

1. **In-File Steps**: Ordered actions the agent performs on every run (top of `SKILL.md`).
2. **In-File Reference**: Compact rules consulted on every run (co-located under one heading).
3. **Disclosed Reference (`references/`, `assets/`, `scripts/`)**: Templates, schemas, smell baselines, and bash scripts reached via a context pointer only when needed.

Branching is the cleanest disclosure test: inline what every run needs, and push behind a pointer in `references/`, `assets/`, or `scripts/` what only specific branches or steps consume. Keep root `SKILL.md` files strictly under 150 lines.

## 3. Steps & Completion Criteria (`Clarity` + `Demand`)

Every procedural step needs a completion criterion with two properties:

- **Clarity**: Can the agent distinguish done from not-done? Vague bounds ("understand the repo") invite premature completion as the agent rushes toward later visible steps. Sharpen the bound first ("Done when every modified module and its public seam are listed").
- **Demand**: How much legwork the wording requires ("Every modified model accounted for" vs. "Produce a change list"). High-demand criteria drive thorough investigation without extra procedural steps.

## 4. Leading Words & Positive Framing Over Negation

- **Leading Words**: Recruit concepts already rich in the model's pretraining (*design tree*, *frontier*, *tracer bullets*, *seam*, *deep module*, *tight loop*, *fog of war*). Repeat the exact token rather than re-explaining the concept in different words.
- **Positive Framing Over Negation**: Steering by prohibition ("Do not write horizontal tests", "Never use vague names") activates the forbidden concept in attention (*Negative Constraint Collapse*). State the positive target directly ("Write vertical tracer-bullet slices", "Use canonical `GLOSSARY.md` identifiers"). Reserve negative phrasing exclusively for hard security or safety boundaries, and always pair it with the positive action.

## 5. Pruning Sediment & No-Ops

- **Single Source of Truth**: Eliminate duplication between YAML `description` fields and body sections (`## When to Use`).
- **Environment as Source of Truth**: Leave one-command lookups (`package.json` scripts, directory trees) in the environment rather than caching them in prose where they go stale.
- **Delete No-Ops**: If a sentence instructs the model to do something it already does by default, delete the entire sentence.
