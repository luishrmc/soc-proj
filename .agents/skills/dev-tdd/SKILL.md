---
name: dev-tdd
description: Execute test-driven development with a strict red-green vertical slice loop at public seams. Use when building features or fixing bugs test-first, when the user mentions "TDD" or "red-green-refactor", or when invoked by dev-implement or dev-parallel.
---

# Test-Driven Development at Public Seams

Drive implementation through a tight **red -> green** feedback loop, building features and fixing bugs one **tracer-bullet** vertical slice at a time.

Read `GLOSSARY.md` (if present) before writing tests so test descriptions, fixtures, and public interface names use canonical domain vocabulary, and respect any ADRs in `docs/adr/`.

## What Makes a Good Test

Tests verify observable behavior through **public interfaces**, never internal implementation details. Internal structure can be refactored completely while good tests remain untouched and green.

Consult [references/tests.md](./references/tests.md) for behavioral test patterns and [references/mocking.md](./references/mocking.md) for system-boundary mocking rules.

## Seams: Where Tests Attach

A **seam** is the public boundary where callers and tests exercise a module's behavior without reaching into its internals.

1. **Test exclusively at pre-agreed seams.** If the active spec or ticket already defines the test seams, use them. If no seams have been agreed upon yet, propose the public interface seams (noting in one line what each catches and what it misses) and confirm with the user before writing tests.
2. **Prefer deep modules.** Design modules with a small public interface hiding substantial internal logic so a single seam test exercises high behavioral leverage.

## Three Anti-Patterns to Reject

- **Implementation-Coupled Tests**: Mocking internal collaborators, asserting on private methods or call counts, or verifying state through a side channel (e.g., querying raw database tables instead of calling the public read interface).
- **Tautological Tests**: Recomputing the expected value in the test using the same formula as the production code (`expect(calc(a, b)).toBe(a + b)`). Expected values must come from an independent source of truth: concrete literals, worked examples, or the specification.
- **Horizontal Bulk Testing**: Writing all test cases upfront before writing any implementation. Work strictly in **vertical slices**: one failing test -> one minimal implementation -> repeat.

## Rules of the Red-Green Loop

Execute each vertical slice sequentially:

1. **Red First**: Write a single failing test at the agreed seam that captures the next slice of observable behavior. Run the targeted test file and verify it fails for the expected reason.
2. **Minimal Green**: Write only the production code required to make that failing test pass. Avoid speculative abstractions or untested branches.
3. **Fast Incremental Checks**: Run the single test file and static typechecker on every slice; run the full test suite once all slices for the ticket are green.
4. **Defer Structural Refactoring to Review**: Keep the red-green loop focused on behavioral correctness; structural smell cleanup is evaluated in `review-diff`.
