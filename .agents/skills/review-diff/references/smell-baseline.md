# Fowler Code Smell Baseline

The **Standards** subagent in `review-diff` applies this 12-smell baseline (adapted from Martin Fowler, *Refactoring*, Chapter 3) alongside the repository's documented standards.

## Binding Rules

1. **Repo Standards Override**: Wherever a documented repository standard (`CODING_STANDARDS.md`, `GEMINI.md`, `AGENTS.md`, `docs/adr/`) endorses a pattern this baseline would flag, suppress the baseline smell.
2. **Judgment Calls Only**: Every baseline smell is a labeled design heuristic (`Possible Feature Envy`), never an automatic blocker.
3. **Skip Tool-Enforced Checks**: Do not flag formatting, import sorting, or syntax rules already enforced by the project's linter or typechecker.

## The 12 Baseline Smells (`What It Is -> How to Fix`)

1. **Mysterious Name**: A function, variable, or type whose identifier fails to reveal its intent or diverges from `GLOSSARY.md`. -> Rename to match the ubiquitous language.
2. **Duplicated Code**: Identical logic structure repeated across multiple hunks or files in the diff. -> Extract the shared behavior behind a single function or module seam.
3. **Feature Envy**: A function or method that accesses another module's internal data more than its own. -> Move the behavior into the module that owns the data.
4. **Data Clumps**: The same group of 3+ parameters or fields traveling together across multiple signatures. -> Consolidate them into a dedicated domain value object or type.
5. **Primitive Obsession**: Raw strings, numbers, or booleans standing in for a domain concept with invariants (such as currency, status codes, or validated IDs). -> Introduce a small domain type.
6. **Repeated Switches**: The same `switch` or `if/else` chain dispatching on the same type tag in multiple places. -> Consolidate into polymorphism or a single shared dispatch map.
7. **Shotgun Surgery**: A single logical behavior change requiring scattered small edits across many unrelated files. -> Co-locate the responsibilities that change together into one deep module.
8. **Divergent Change**: A single module or file modified for multiple orthogonal reasons. -> Split the module so each part changes for a single reason.
9. **Speculative Generality**: Unused parameters, premature hooks, or abstract interfaces with only a single adapter added for hypothetical future needs. -> Inline and delete until a second real requirement appears.
10. **Message Chains**: Deep `a.getB().getC().getD()` navigation coupling the caller to intermediate structure. -> Hide the traversal behind a direct method on the boundary module.
11. **Middle Man**: A shallow wrapper class or function that delegates nearly all work straight through without adding policy or abstraction depth. -> Delete the pass-through and invoke the target directly.
12. **Refused Bequest**: An implementation or subclass that ignores, stubs out, or throws on most of the interface it claims to satisfy. -> Replace inheritance or broad interface conformance with narrower composition.
