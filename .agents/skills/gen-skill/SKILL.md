---
name: gen-skill
description: End-to-end meta-skill engine for architecting, validating, and generating production-ready modular agent skills across CLI and Web environments. Integrates prompt-optimization and precision-writing principles to produce deterministic SKILL.md specifications.
---
# Skill Builder

System engine for designing, testing, and generating modular agent skills compatible with both Gemini CLI and Gemini Web/Workspace interfaces.

## When to Use

Activate this skill when:

- Creating a new agent skill from scratch or translating an existing workflow into a reusable module.
- Structuring prompt engineering logic, tools, and execution steps into a standard `SKILL.md`.
- Refactoring loose prompt templates into deterministic, portable agent specifications.

Do not activate when:

- Executing an existing operational skill.
- Generating one-off responses that require no persistent skill architecture.

---

## Operational Architecture

Every generated skill must satisfy four architectural constraints:

1. **Context Efficiency:** Zero boilerplate. Target strict signal-to-noise ratio.
2. **Deterministic Control:** Concrete imperative steps with clear state transitions.
3. **Environment Portability:** Operational in headless CLI environments (tool-driven) and conversational Web interfaces (prompt-driven).
4. **Integration Hooks:** Defined inputs, outputs, validation checkpoints, and dependencies.

---

## Execution Workflow

Follow this 4-phase lifecycle sequentially:

```
[Phase 1: Ingestion & Clarification]
                 │
                 ▼
[Phase 2: Architectural Specification]
                 │
                 ▼
[Phase 3: Precision Authoring]
                 │
                 ▼
[Phase 4: Verification & Packaging]
```

### Phase 1: Ingestion & Intent Optimization

1. Deconstruct the user's raw requirement into:
   - **Goal:** Primary task and expected deliverable.
   - **Triggers:** Exact keywords, intent patterns, and file contexts.
   - **Environment Targets:** CLI flags/tools vs. Web conversational interaction.
   - **Constraints:** Format requirements, token budgets, safety boundaries.
2. If critical parameters are missing, halt and request clarification on:
   - Scope boundaries (what the skill must NOT do).
   - Expected I/O interface.

### Phase 2: Architectural Specification

Structure the module around the standard Skill Schema:

- **Metadata:** Unique hyphenated name, clear description (under 1024 characters), semantic version.
- **Trigger Surface:** Positive triggers and negative anti-triggers.
- **Workflow Pipeline:** Ordered, numbered execution phases.
- **Negative Constraints:** Explicit behavioral boundaries.

### Phase 3: Precision Authoring

Draft the `SKILL.md` file applying these rules:

- Use imperative active voice ("Parse input", "Validate schema", never "The agent should parse").
- Exclude introductory fluff, corporate buzzwords, and redundant pleasantries.
- Eliminate all em-dashes and en-dashes; use standard hyphens or colons.
- Use explicit markdown headers and blank lines before all lists.
- Keep the complete body focused and under 500 lines.

### Phase 4: Verification Checklist

Verify each artifact against these criteria prior to finalization:

- [ ] Name contains only lowercase alphanumeric characters and hyphens (`[a-z0-9-]+`).
- [ ] Frontmatter description states both *what* the skill does and *when* it triggers.
- [ ] All procedures have verifiable outputs.
- [ ] No placeholder blocks (e.g., `<insert code here>` or `TODO`).
- [ ] Cross-environment compatibility documented (CLI flags / Web prompt equivalents).

---

## Negative Constraints

- Never include conversational preamble, generic apologies, or sign-offs in generated skills.
- Never use em-dashes (`—`) or en-dashes (`–`).
- Never generate abstract or placeholder logic without working examples.
- Never omit negative constraints from generated skill definitions.