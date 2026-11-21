---
name: refine-prompt
description: Optimize, diagnose, and reconstruct prompts into deterministic Markdown instructions or type-safe Pydantic application code. Use when the user asks to "optimize a prompt", "refine prompt", "structure prompt", "pydantic prompt", or convert a raw task draft into a high-adherence prompt.
---

# Dual-Mode Prompt Optimizer

Diagnose failure modes in draft prompts and reconstruct them into deterministic, high-signal instructions for interactive agent sessions or type-safe application pipelines. Focus exclusively on optimizing and outputting the prompt artifact rather than executing the underlying task.

## Dual-Mode Selection

Select the output mode matching the user's target environment:

### Mode 1: Interactive Markdown (Default)

Use for human-in-the-loop chat, CLI agent sessions, and pair-programming prompts:

```markdown
## 🔍 Original Prompt Analysis
- **Goal:** <Extracted primary objective>
- **Issues Identified:** <Diagnosed weaknesses from references/failure-modes.md>

## 🚀 Optimized Prompt
<Copy-pasteable, delimited prompt specification>

## 🧠 Improvements Applied
- <Structural improvement 1 and rationale>
- <Structural improvement 2 and rationale>
```

### Mode 2: Application & Pydantic (Code-Ready)

Use when the user targets API integration, automated agent pipelines, JSON extraction, or Pydantic models:

1. **Pydantic Schema**: Validated `BaseModel` with explicit `Field` descriptions and literal types ([references/structured-outputs.md](./references/structured-outputs.md)).
2. **Parameterized Prompt Template**: Decoupled prompt text with `{variable}` interpolation slots.
3. **Execution Snippet**: Clean Python invocation using structured outputs.

## 5-Stage Optimization Pipeline

1. **Intent Extraction**: Pin down the single primary outcome, operating mode (Interactive vs. Pydantic), domain context, and target model capabilities.
2. **Failure Mode Diagnosis**: Audit the input against [references/failure-modes.md](./references/failure-modes.md) for boundary ambiguity, Negative Constraint Collapse, format drift, and context bloat.
3. **Reconstruction**:
   - Assign a grounded domain persona and evaluation perspective.
   - Separate instructions from variable inputs using XML tags (`<context>`, `<input>`) or Markdown headers.
   - Apply structured reasoning and self-verification patterns from [references/reasoning-patterns.md](./references/reasoning-patterns.md).
   - Consult [assets/prompt-template-library.md](./assets/prompt-template-library.md) for domain archetypes.
4. **Output Rendering**: Emit the reconstructed prompt strictly following **Mode 1** or **Mode 2**.
5. **Completion Check**: Confirm all constraints are positively framed, variable slots are delimited, and the output is immediately copy-pasteable without placeholders.
