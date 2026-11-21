# Advanced Reasoning & Verification Patterns

This reference document outlines patterns for eliciting rigorous, logically sound, and verifiable reasoning from LLMs.

---

## 1. Structured Chain-of-Thought (CoT)

Standard zero-shot CoT (*"Let's think step by step"*) is often too generic for complex engineering tasks. Structured CoT divides the reasoning phase into explicit cognitive stages:

```markdown
### Execution Steps:
1. **Deconstruct Requirements:** Identify all functional constraints, edge conditions, and input invariants.
2. **Formulate Approach:** Outline the architectural strategy before writing code or formulas.
3. **Execute & Derive:** Work through the implementation or calculations sequentially.
4. **Self-Audit:** Verify intermediate results against the constraints identified in Step 1.
```

---

## 2. Backward Self-Verification Pattern

Models frequently generate incorrect answers if they proceed linearly from start to finish without evaluating intermediate conclusions. The **Backward Verification Pattern** forces the model to test its own output against known invariants before committing to a final answer:

```markdown
### Verification Loop:
Before outputting the final result, perform these validation checks:
1. **Constraint Audit:** Does the derived solution satisfy every negative constraint?
2. **Boundary Testing:** What happens at extreme inputs ($n=0$, empty list, null values)?
3. **Consistency Check:** Recompute the primary metric using an alternative formulation or sanity check.
If any check fails, correct the reasoning in the scratchpad before emitting the final answer.
```

---

## 3. Delimited Scratchpad & Workspaces

Separating internal derivation tokens from user-facing deliverables prevents reasoning clutter and guarantees clean outputs:

```markdown
Use the following format:
<scratchpad>
- Break down the logic
- Perform arithmetic and token checks
- Verify edge cases
</scratchpad>

<final_response>
[Strictly only the validated deliverable requested by the user]
</final_response>
```

---

## 4. Few-Shot Demonstration Architecture

Few-shot examples are the most reliable mechanism to teach style, tone, and schema compliance. Follow these rules to avoid **Example Pollution**:

### Rules for Effective Few-Shot Demonstrations
1. **Input-Output Symmetry:** Every demonstration must adhere strictly to the target format expected in production.
2. **Diversity Sampling:** Include at least one nominal case, one boundary/edge case, and one adversarial/invalid input case.
3. **Example Neutrality:** Ensure examples do not introduce domain-specific bias that skews the model away from the user's actual prompt data.
4. **Token Parity:** Keep demonstration length proportional to the complexity of the task; prune redundant intermediate verbiage.
