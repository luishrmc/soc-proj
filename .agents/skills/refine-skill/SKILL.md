---
name: refine-skill
description: "Audit, prune, and calibrate existing SKILL.md specifications using unified diffs and writing-for-agents mechanics."
disable-model-invocation: true
---

# Skill Optimizer & Pruner

Diagnose, prune, and calibrate operational `SKILL.md` files against runtime traces, user feedback, and the architectural rules in [references/skill-mechanics.md](./references/skill-mechanics.md).

## 5-Phase Calibration Workflow

### Phase 1: Telemetry & Load Audit

Ingest the target `SKILL.md` (and any failure trace or user report) and classify defects across six levers:

1. **Invocation & Context Load**: Is a human-only workflow missing `disable-model-invocation: true`, or is a model-invoked skill carrying a weak/bloated `description` pointer?
2. **In-File Sprawl (>150 Lines)**: Are templates, JSON schemas, or bash scripts buried inside `SKILL.md` instead of disclosed in `references/`, `assets/`, or `scripts/`?
3. **Premature Completion**: Do steps lack checkable, high-demand completion criteria (`Done when...`)?
4. **Negative Constraint Collapse**: Does the skill rely on long `"Do not / Never"` lists instead of positive framing and compact **leading words**?
5. **Duplication & No-Op Sediment**: Does the body repeat the YAML `description` in a `## When to Use` block, cache environment facts, or state default behaviors?
6. **Dangling Cross-References**: Does the skill attempt to invoke a user-invoked skill or reference outdated skill slugs?

### Phase 2: Root-Cause Mapping

Consult [references/skill-mechanics.md](./references/skill-mechanics.md) and map each defect to a concrete structural transformation:

- **Pointer Sharpening**: Front-load leading words and keep exactly one trigger per distinct branch in model-invoked `description` fields.
- **Progressive Disclosure**: Move large reference blocks, schemas, and shell logic to sibling `references/`, `assets/`, or `scripts/` files behind explicit pointers.
- **Positive Reframing**: Rewrite prohibitions into positive target directives and co-locate rules with the step they govern.

### Phase 3: Unified Diff & Rationale Delivery

1. Present proposed modifications as a clean Unified Diff (or side-by-side before/after line count summary when extracting `scripts/` and `references/`).
2. Cite the specific lever from [references/skill-mechanics.md](./references/skill-mechanics.md) justifying each change.
3. Verify `skills.json` synchronization if the skill's `description` or path changed.

### Phase 4: Verification Audit

Confirm the refactored skill passes every check before writing:

- [ ] Root `SKILL.md` is strictly under 150 lines.
- [ ] Invocation mode (`disable-model-invocation: true` vs. model-invoked pointer) is explicit and accurate.
- [ ] Redundant trigger blocks and no-op sentences are removed.
- [ ] Zero em-dashes or en-dashes appear in any modified file.
