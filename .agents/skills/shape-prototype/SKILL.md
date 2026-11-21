---
name: shape-prototype
description: Build a throwaway prototype to answer a state/logic question or compare radically different UI variations. Use when sanity-checking whether a state machine or data model feels right, exploring what a UI page should look like, or when invoked during shape-grill or shape-wayfinder.
---

# Rapid Design Question Prototyping

Build **throwaway code that answers a specific design question**. The nature of the question determines which of the two prototype branches to execute.

## 1. Select the Prototype Branch

Identify which question is being asked before writing any code:

- **Branch A: "Does this state model or business logic feel right?"** -> Read and follow [references/logic.md](./references/logic.md). Build a single, zero-dependency, self-contained HTML file with free-play action buttons and tabbed guided scenario walkthroughs over a pure, liftable JS state module.
- **Branch B: "What should this UI page or flow look like?"** -> Read and follow [references/ui.md](./references/ui.md). Render 3 to 5 structurally distinct UI variations (`VariantA`, `VariantB`, `VariantC`) on the target route, switchable live via a `?variant=` URL parameter and a floating bottom bar.

If the prompt is ambiguous and the user is unavailable, match the surrounding context (backend/domain logic -> Branch A; component/route -> Branch B) and state the assumption at the top of the artifact.

## 2. Universal Prototype Invariants

1. **Explicitly Marked Throwaway**: Name files or routes clearly (`prototype-<slug>.html` or `?variant=`) so prototype code is never mistaken for production code.
2. **One-Action Startup**: A logic prototype opens directly by double-clicking a single `.html` file; a UI prototype renders inside the existing dev server route.
3. **In-Memory State Only**: Hold all state in memory. Avoid real database writes or external mutations unless the prototype specifically tests a local scratch store.
4. **Visible State Inspection**: After every action (Logic) or variant switch (UI), display the active state clearly so the human can immediately spot edge-case flaws in the underlying idea.
5. **Skip Production Ceremony**: Omit unit tests, defensive boilerplate, and premature abstractions so the prototype lands in minutes.

## 3. Capture the Decision & Preserve Primary Source

Once the user evaluates the prototype and settles the design question:

1. Fold the validated decision (or pure reducer/state machine from Branch A, or winning layout from Branch B) cleanly into the specification (`/shape-spec`) or production module.
2. Commit the raw prototype onto an isolated `prototype/<slug>` branch outside `main` and link it as a **context pointer** on the spec or ticket so the primary source stays inspectable without polluting `main`.
