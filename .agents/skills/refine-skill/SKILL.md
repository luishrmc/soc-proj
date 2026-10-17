---
name: refine-skill
description: Audit, troubleshoot, and fine-tune existing agent skills and SKILL.md specifications. Activate when users report instruction drift, false triggers, formatting inconsistencies, or tool failures in an existing skill, or when updating a skill based on conversation logs.
---
# Skill Optimizer

System engine for evaluating, debugging, and iteratively calibrating operational agent skills. Converts runtime execution traces, failure logs, and user feedback into deterministic skill improvements.

## When to Use

Activate this skill when:

- A user requests a revision, bug fix, or optimization for an existing skill.
- An existing skill triggers on unrelated queries or fails to trigger on valid tasks.
- A skill produces invalid output structures, schema violations, or hallucinated fields.
- Runtime logs show missed negative constraints or tool parameter errors.
- A skill requires token pruning or structural reorganization to meet context budgets.

Do not activate when:

- Generating a new skill from scratch without an existing baseline file.
- Executing an operational skill during routine agent workflows.
- Authoring standard application code or general system documentation.

## Multi-Environment Target Support

### Gemini CLI

- Consumes file paths to target SKILL.md files and associated runtime execution logs.
- Outputs standard unified diff patches and CLI test command strings.

### Gemini Web and Workspace

- Consumes pasted SKILL.md text blocks and conversation transcript excerpts.
- Outputs formatted Markdown diff blocks, rationale explanations, and copyable validation prompts.

## Operational Workflow

Execute the following five phases sequentially:

### Phase 1: Context and Telemetry Audit

1. Ingest baseline materials:
   - Target SKILL.md file.
   - User issue descriptions, failure logs, or desired behavioral shifts.
2. Classify observed defects into primary failure categories:
   - Trigger Calibration: False positive activations or false negative omissions.
   - Constraint Leakage: Failure to enforce negative boundaries and explicit bans.
   - Format Drift: Structural deviations, missing schemas, or markdown syntax errors.
   - Instruction Ambiguity: Vague directives causing variable agent interpretation.
   - Tool Call Misuse: Malformed tool arguments or incorrect tool sequencing.
   - Token Bloat: Redundant instructions, conversational filler, or excessive examples.
3. Establish a baseline problem statement defining observed behavior versus required behavior.

### Phase 2: Knowledge Retrieval and Research

1. Formulate 2 to 3 targeted technical queries addressing the identified failure mode. Focus on:
   - Structural boundary patterns for complex system instructions.
   - Standardized input and output schemas for specific domains.
   - Negative constraint syntax that minimizes model hallucination.
2. Filter findings to extract actionable implementation patterns. Discard broad generalizations.

### Phase 3: Root Cause Analysis and Optimization Hypothesis

1. Map the gap between current skill performance and verified prompt engineering patterns.
2. Formulate explicit optimization hypotheses:
   - Instruction Clarification: Convert descriptive guidance into sequential imperative steps.
   - Trigger Calibration: Refine YAML description fields with positive and negative boundaries.
   - Negative Guardrails: Draft deterministic negative rules targeting observed error modes.
   - Few-Shot Calibration: Replace outdated examples with targeted edge cases.

### Phase 4: Structured Diff and Rationale Delivery

1. Present all proposed changes exclusively in Unified Diff format using standard diff syntax markers.
2. Provide a technical rationale for each modification hunk, connecting it directly to user feedback.
3. Update the semantic version according to standard SemVer rules:
   - Patch increment (0.0.+1) for constraint additions, bug fixes, and phrasing adjustments.
   - Minor increment (0.+1.0) for new operational phases, new tools, or expanded scopes.
   - Major increment (+1.0.0) for breaking changes to trigger contracts or I/O formats.
4. Record an entry in the skill changelog detailing modified sections.

### Phase 5: Interactive Validation and Human-in-the-Loop Refinement

1. Produce 2 to 3 targeted verification test prompts designed to trigger the previous failure mode.
2. Define the exact expected behavior and pass criteria for each test prompt.
3. Request explicit user confirmation before applying the patch to storage.
4. Apply iterative refinements if the user identifies remaining edge cases.

## Negative Constraints

- Never rewrite an entire skill without providing a unified diff showing specific alterations.
- Never alter the primary domain purpose of a skill without explicit user direction.
- Never remove safety boundaries or negative constraints during optimization.
- Never use placeholder text, incomplete logic blocks, or unverified instructions.
- Never use em-dashes or en-dashes in modified skills.
- Never use semicolons in modified skills.