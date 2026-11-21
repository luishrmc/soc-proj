# Prompt Failure Modes & Remediation Taxonomy

This reference guide categorizes common failure modes observed in LLM prompts, their underlying mechanisms, and deterministic remediation patterns.

---

## 1. Ambiguity and Under-Specification

### Symptoms
- Responses vary wildly in depth, length, and technical rigor across runs.
- Model produces high-level summaries when detailed code/analysis was expected.
- Use of passive, weak verbs: *"make it better"*, *"write something about X"*, *"analyze this"*.

### Root Cause
Without explicit scope bounds and operational definitions, the model defaults to an ungrounded average probability distribution across its training corpus.

### Remediation Pattern
- **Scope Grounding:** Define exact boundary conditions (e.g., *"Focus exclusively on algorithm complexity and memory allocation"*).
- **Target Persona:** Specify domain expertise and viewpoint (e.g., *"Act as a principal distributed systems engineer"*).
- **Deliverable Specification:** Name the exact output artifacts required (e.g., *"A 3-step action plan followed by a Markdown summary table"*).

---

## 2. Format Drift & Schema Invalidation

### Symptoms
- JSON responses wrapped in markdown code fences (` ```json ... ``` `) when raw JSON is required by API callers.
- Hallucinated fields, varying dictionary key casing (`camelCase` vs `snake_case`), or missing mandatory properties.
- Inconsistent section headers that break automated regex or parsing scripts.

### Root Cause
Natural language instruction alone provides weak probabilistic guarantees for syntax-level compliance.

### Remediation Pattern
- **Type-Safe Schema Definition:** Provide an explicit schema (Pydantic model, JSON Schema, or TypeScript interface).
- **Key-by-Key Descriptions:** Annotate every field with exact semantic meaning and constraints (`min_length`, `ge`, `regex`).
- **Defensive Format Prompts:** Explicitly forbid extraneous text: *"Respond ONLY with valid JSON matching the schema. Do not include markdown fences, preambles, or commentary."*

---

## 3. Negative Constraint Collapse

### Symptoms
- Model violates instructions like *"Do NOT use Python"* or *"Do NOT mention competitor X"*.
- Model hallucinates justification for violating negative rules.

### Root Cause
Attention heads focus heavily on semantic tokens (e.g., "Python", "competitor X") even when preceded by negation ("do not"). Negation is easily lost during multi-token autoregressive generation.

### Remediation Pattern
- **Positive Framing:** Reframe negatives as positive constraints (e.g., instead of *"Do not use loops"*, specify *"Use purely vectorized NumPy operations"*).
- **Delimited Forbidden Lists:** Place negative rules inside a dedicated, highlighted section (`### STRICT CONSTRAINTS` or `### FORBIDDEN PATTERNS`).
- **Post-Generation Checklist:** Require the model to include a self-check verifying that zero forbidden patterns were used.

---

## 4. Token Inefficiency & Context Bloat

### Symptoms
- Prompts include conversational pleasantries (*"Could you please kindly help me..."*), repetitive context, or redundant examples.
- Reduced effective context window and higher latency/cost.

### Root Cause
Conflating conversational politeness with structural instruction tokens.

### Remediation Pattern
- **Token Pruning:** Strip all meta-commentary, conversational filler, and rhetorical questions.
- **Progressive Hierarchy:** Use standard markdown headings (`#`, `##`, `###`) and XML tags (`<context>`, `<rules>`, `<input>`) instead of lengthy explanatory paragraphs.

---

## 5. Unverified Reasoning & Hallucinated Arithmetic

### Symptoms
- Calculation errors in math, logic puzzles, or code trace evaluations.
- Confident but incorrect final conclusions where steps don't support the outcome.

### Root Cause
Standard autoregressive models predict the next token immediately without dedicated intermediate scratchpad computation.

### Remediation Pattern
- **Chain-of-Thought (CoT):** Enforce step-by-step intermediate calculation before producing the final answer.
- **Backward Self-Verification:** Instruct the model to re-evaluate its derived answer against the initial constraints before finalizing the output.
- **Separation of Scratchpad:** Require reasoning inside `<thinking>` or `<reasoning>` blocks, keeping the final deliverable clean and deterministic.
