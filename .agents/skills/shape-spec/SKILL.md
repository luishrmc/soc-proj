---
name: shape-spec
description: "Synthesize the current conversation into a formal specification with confirmed public test seams and publish it to the project issue tracker."
disable-model-invocation: true
---

# Conversation-to-Specification Synthesis

Synthesize the current conversation context and codebase understanding into a formal, durable specification document. Do not interview the user all over again; synthesize the decisions already reached during `/shape-grill`.

## Preconditions

Verify that `docs/agents/issue-tracker.md` and `docs/agents/domain.md` exist in the repository. If neither exists and no tracker preference is known, ask the user whether to publish to GitHub Issues, GitLab Issues, or `.scratch/<feature-slug>/spec.md` (or suggest running `/setup-workspace`).

## Execution Process

### 1. Align with Codebase and Ubiquitous Language

1. Inspect the relevant modules if not already explored in this session.
2. Enforce the exact domain terminology from `GLOSSARY.md` throughout the specification and verify alignment with existing ADRs in `docs/adr/`.

### 2. Propose and Confirm Public Test Seams

1. Identify the **seams** (public module interfaces) where the feature will be tested during `/dev-implement`.
2. Prefer existing high-level seams over introducing new low-level seams. Aim for the smallest number of seams that cover the behavior (the ideal number of seams is one).
3. Present the proposed test seams to the user and confirm agreement before writing the specification.

### 3. Author and Publish the Specification

1. Draft the specification strictly following [assets/spec-template.md](./assets/spec-template.md).
2. Exclude brittle file paths and raw implementation code snippets from the specification so the document does not go stale before implementation.
   - *Exception*: If a throwaway prototype produced a concise state machine, reducer signature, schema, or type definition that encodes a decision more accurately than prose, inline only that decision-critical excerpt and note its prototype origin.
3. Publish the completed specification to the configured issue tracker (or write to `.scratch/<feature-slug>/spec.md`) and apply the `ready-for-agent` triage status/label.
