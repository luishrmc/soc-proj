---
name: gen-skill
description: "Architect, validate, and generate modular SKILL.md specifications and disclosed reference files."
disable-model-invocation: true
---

# Modular Skill Builder

Design and generate portable, low-context-load agent skills (`SKILL.md` plus disclosed `references/`, `assets/`, and `scripts/`) grounded in the mechanics in [references/skill-mechanics.md](./references/skill-mechanics.md).

## Architectural Standards

Every generated skill must satisfy four structural invariants:

1. **Invocation Alignment**: Explicitly choose **User-Invoked** (`disable-model-invocation: true` with a 1-line human summary) for slash-command orchestrators, or **Model-Invoked** (front-loaded trigger branches in `description`) for reusable disciplines ([references/skill-mechanics.md](./references/skill-mechanics.md)).
2. **Progressive Disclosure (<150 Lines)**: Keep the root `SKILL.md` strictly under 150 lines containing ordered steps, leading words, and completion criteria. Push templates, schemas, and shell helpers into `references/`, `assets/`, or `scripts/`.
3. **Positive Framing & Leading Words**: Recruit pretrained model priors with compact **leading words** (*design tree*, *frontier*, *tracer bullets*, *seam*) and positive directives rather than long lists of `"Do not..."` negations.
4. **Checkable Completion Criteria**: End every operational step on a clear, exhaustive completion criterion (`Done when...`) so the agent never rushes to premature completion.

## 4-Phase Authoring Workflow

### Phase 1: Requirement & Load Analysis

1. Determine the skill's functional prefix (`shape-*`, `dev-*`, `review-*`, `arch-*`, `debug-*`, `env-*`, `setup-*`, `plan-*`, `refine-*`, `git-*`, `router-*`).
2. Decide whether the skill is **User-Invoked** (zero context load, human-triggered orchestrator) or **Model-Invoked** (always-loaded description pointer, autonomous or skill-called discipline).
3. Separate **in-file steps** (what the agent does every run) from **disclosed reference** (templates, edge-case tables, or bash scripts reached on demand).

### Phase 2: Context Pointer & Hierarchy Design

1. If Model-Invoked, write a sharp `description` that front-loads the leading word and lists one trigger per distinct branch (collapsing synonymous triggers).
2. If User-Invoked, set `disable-model-invocation: true` and write a clean one-line `description` without trigger lists.
3. Omit redundant `## When to Use` body sections that repeat the YAML `description`.

### Phase 3: Precision Authoring

1. Write imperative steps using active verbs and co-located rules.
2. State positive target behaviors ("Write one-line comments", "Stage files by explicit pathspec") and prune no-op instructions that models already obey by default.
3. Use standard hyphens, commas, colons, or periods in place of em-dashes or en-dashes.

### Phase 4: Verification Checklist

Verify every generated file before finishing:

- [ ] Root `SKILL.md` is strictly under 150 lines.
- [ ] `name` uses lowercase alphanumeric characters and hyphens (`[a-z0-9-]+`).
- [ ] Invocation mode (`disable-model-invocation: true` vs. model-facing trigger pointer) matches [references/skill-mechanics.md](./references/skill-mechanics.md).
- [ ] Inter-skill calls target only **model-invoked** skills via explicit Skill tool instructions.
- [ ] Zero em-dashes, en-dashes, or placeholder `TODO` blocks exist.
