# Specification Template

Use the exact section structure below when generating a specification in `shape-spec`:

```markdown
## Problem Statement

The problem the user or system is facing, framed from the user's perspective.

## Solution

The agreed solution from the user's perspective, written using canonical `GLOSSARY.md` terms.

## User Stories

An exhaustive, numbered list of user stories covering primary flows and edge cases:

1. As a <domain actor>, I want <capability>, so that <observable benefit>.
2. As a <domain actor>, I want <edge-case handling>, so that <observable benefit>.

## Implementation Decisions

Key architectural and interface decisions settled during shaping:

- Modules and public interfaces to be created or modified
- Data model or schema contracts
- State transitions, invariants, and error boundaries
- Relevant ADR references

(Omit specific file paths and implementation code snippets unless capturing a compact type shape or state machine from a validated prototype.)

## Testing Decisions

Agreed verification strategy for `dev-tdd`:

- **Confirmed Seams**: The public interfaces where tests will attach (testing external behavior only, never internal implementation details)
- **Prior Art**: Existing test suites or patterns in the repository to mirror
- **Boundary Scenarios**: Critical edge cases that must be covered at the seam

## Out of Scope

Capabilities and adjacent ideas explicitly excluded from this specification.

## Further Notes

Additional context, operational considerations, or migration notes.
```
