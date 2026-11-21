---
name: shape-grill
description: "Conduct a stateful design grilling interview that resolves every branch of the design tree while updating GLOSSARY.md and ADRs inline."
disable-model-invocation: true
---

# Stateful Design Grilling with Domain Grounding

Conduct a rigorous, stateful design interrogation that sharpens a feature idea or architectural plan while maintaining the repository's ubiquitous language (`GLOSSARY.md`) and Architecture Decision Records (`docs/adr/`).

## Orchestration Directive

Call the Skill tool twice, for `shape-grilling` and `shape-domain` (or read and execute both `skills/shape-grilling/SKILL.md` and `skills/shape-domain/SKILL.md` simultaneously in harnesses without a native Skill tool):

1. **`shape-grilling`**: Map the user's request as a **design tree**. Compute the unblocked **frontier** of questions in each round, dispatch fresh-context subagents to look up codebase facts, and present numbered questions (`❓ **Q1**`) paired with concrete recommendations (`➡️ **Recommended**`) until the frontier is empty.
2. **`shape-domain`**: Cross-reference every term and assumption against `GLOSSARY.md`, `docs/adr/`, and existing source code. Challenge overloaded vocabulary, update `GLOSSARY.md` inline the moment terms crystallize, and offer ADRs for hard-to-reverse, non-obvious trade-offs.

## Context Hygiene

Keep `/shape-grill`, `/shape-spec`, and `/shape-tickets` within **one unbroken context window** (staying inside the ~150k token smart zone) so specification synthesis and ticket decomposition inherit the exact reasoning and domain vocabulary established during the interview.
