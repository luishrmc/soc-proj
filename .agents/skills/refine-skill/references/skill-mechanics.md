# Skill Mechanics & Diagnostic Rubric

Reference for auditing and refactoring `SKILL.md` files in `refine-skill`.

## 1. Invocation & Context Load Rubric

| Symptom | Root Cause | Refactoring Fix |
| :--- | :--- | :--- |
| Orchestrator skill triggers unexpectedly mid-conversation | Missing `disable-model-invocation: true` | Add `disable-model-invocation: true` and replace trigger list in `description` with a 1-line summary. |
| Model-invoked skill fails to fire when needed | Weak context pointer in `description` | Front-load the leading word and state one clear trigger per branch. |
| Skill `SKILL.md` wastes 15+ lines on `## When to Use` | Duplication of YAML `description` | Delete the redundant body section; trigger matching happens in frontmatter. |
| Skill attempts to call another user-invoked skill | Violation of invocation boundary | Extract shared discipline into a model-invoked skill and call the Skill tool on that discipline. |

## 2. Information Hierarchy & Sprawl Rubric

- **In-File Steps (Tier 1)**: Keep ordered actions at the top of `SKILL.md`.
- **In-File Reference (Tier 2)**: Co-locate compact rules directly under the step or concept they govern.
- **Disclosed Reference (Tier 3)**: Extract code templates (`assets/`), schemas and edge-case matrices (`references/`), and shell automation (`scripts/`) out of `SKILL.md` so the root file stays under 150 lines.

## 3. Completion Criteria & Leading Words

- **Sharpen Fuzzy Bounds**: Replace vague transitions ("Once you understand the code...") with checkable criteria ("Done when the target seam and its callers are listed").
- **Replace Explanations with Leading Words**: Collapse multi-sentence restatements into pretrained leading words (*design tree*, *frontier*, *tracer bullets*, *seam*, *deep module*, *tight loop*).
- **Prompt the Positive**: Convert `"Never do X"` lists into positive instructions stating the exact behavior wanted.
- **Prune No-Ops**: Delete any instruction that does not change the model's behavior relative to its baseline default.
