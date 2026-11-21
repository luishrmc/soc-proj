---
name: arch-design
description: Design deep modules with high-leverage interfaces, clean seams, and strong locality. Use when designing or refactoring a module interface, evaluating deepening candidates, deciding where a test seam belongs, or when invoked by arch-survey or dev-tdd.
---

# Deep Module Architecture & Seam Design

Design **deep modules**: substantial internal behavior hidden behind a small, high-leverage public interface placed at a clean **seam**.

## Canonical Architecture Glossary

Use these eight terms consistently whenever discussing or designing codebase structure:

- **Module**: Any unit with an interface and an implementation (a function, class, package, or cross-tier slice). *Preferred over*: component, service, unit.
- **Interface**: Everything a caller must know to use the module (type signatures, invariants, ordering rules, error modes, and performance contracts). *Preferred over*: API, signature.
- **Implementation**: The internal code hidden behind the module's interface.
- **Depth**: Behavioral leverage at the interface. A **deep module** hides rich functionality behind a simple interface; a **shallow module** exposes an interface nearly as complex as its body.
- **Seam**: The exact location where a module's interface lives and where behavior can be substituted or tested without editing internals. *Preferred over*: boundary.
- **Adapter**: A concrete implementation satisfying an interface at a seam (such as a Postgres adapter in production and an in-memory adapter in tests).
- **Leverage**: What callers gain from depth (maximum capability per unit of interface learned, amortized across $N$ callers and $M$ tests).
- **Locality**: What maintainers gain from depth (changes, invariants, and bugs concentrate inside one module rather than scattering across callers).

## Core Principles

1. **The Deletion Test**: Imagine deleting the module and inlining its body into callers. If complexity disappears, the module was a shallow pass-through; if complexity explodes across $N$ call sites, the module is deep and earning its keep.
2. **The Interface Is the Test Surface**: Callers and `dev-tdd` tests cross the exact same public seam. Wanting to reach past the interface to test private helpers signals a misshapen module.
3. **Two Adapters Justify a Seam**: Introduce an abstract port/seam only when at least two concrete adapters exist (e.g., production transport + fast test stand-in). A single-adapter interface is unnecessary indirection.
4. **Testable Interface Shape**: Accept boundary dependencies as parameters (dependency injection), return explicit value results over hidden side effects, and minimize method and parameter counts.

## Disclosed Reference Guides

- **Deepening Shallow Clusters & Dependency Categories**: Read [references/deepening.md](./references/deepening.md) for the 4-tier dependency classification (*In-process*, *Local-substitutable*, *Ports & Adapters*, *True External Mock*) and replace-don't-layer test migration.
- **Exploring Alternative Interfaces ("Design It Twice")**: Read [assets/design-it-twice.md](./assets/design-it-twice.md) to dispatch 3+ parallel fresh-context subagents proposing radically different interfaces for comparison on depth, locality, and seam placement.
