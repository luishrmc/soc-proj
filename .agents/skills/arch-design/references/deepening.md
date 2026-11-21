# Deepening Shallow Modules

Guide for consolidating a cluster of shallow modules into a single **deep module** based on its dependency profile. Uses the canonical vocabulary in [SKILL.md](../SKILL.md).

## 1. Four Dependency Categories

Classify the candidate cluster's dependencies to determine how the deepened module will be tested across its seam:

### Category 1: In-Process
Pure computation or in-memory state with zero I/O. Merge the shallow modules behind one small interface and test directly through that interface without adapters.

### Category 2: Local-Substitutable
Dependencies with deterministic in-process stand-ins (e.g., SQLite/PGLite for Postgres, in-memory virtual filesystems). Keep the storage seam internal to the module and run seam tests against the fast local stand-in.

### Category 3: Remote But Owned (Ports & Adapters)
Internal microservices or network boundaries owned by your team. Define a typed **port** (interface) at the seam; inject an HTTP/RPC **adapter** in production and a stateful in-memory **adapter** in tests so domain logic stays inside one deep module.

### Category 4: True External (Boundary Mock)
Third-party APIs (Stripe, Twilio, OAuth providers) outside your control. Inject the external boundary as a narrow port and supply a fake or mock adapter in `dev-tdd` tests.

## 2. Seam Discipline

- **One adapter = hypothetical seam; two adapters = real seam.** Introduce an injected port only when at least two concrete adapters are used.
- **Internal vs. External Seams**: Keep internal helper seams private to the module implementation; expose only the primary external seam to callers.

## 3. Replace-Don't-Layer Testing Strategy

1. Write comprehensive behavioral tests at the deepened module's new public **interface**.
2. Delete obsolete unit tests that were coupled to the deleted shallow internal wrappers.
3. Verify that all surviving tests assert exclusively on observable outcomes across the public seam.
