---
name: shape-wayfinder
description: "Chart a multi-session epic wrapped in fog-of-war as a shared map of decision tickets on the issue tracker, and resolve them one session at a time."
disable-model-invocation: true
---

# Multi-Session Fog-of-War Wayfinder

Chart and navigate large, ambiguous efforts (too big for a single session's ~150k token smart zone) as a **shared map** of **decision tickets** on the repository's issue tracker.

## Core Principles

1. **Plan Decisions, Not Code Deliverables**: Each wayfinder ticket resolves an open question or architectural uncertainty until the route to the **destination** is clear, then hands off to `/shape-spec` and `/shape-tickets`.
2. **Respect the Fog of War**: Chart only the questions you can state sharply right now. Record dimly visible downstream questions in the map's `## Not yet specified` section until resolving frontier tickets clears the fog ahead of them.
3. **Refer by Title Name**: Always refer to maps and tickets by their human-readable title wrapped around their link (`[Ticket Title](link)`), never by bare `#42` numbers.
4. **One Ticket Per Session**: Charting the map is one session; resolving a single HITL decision ticket is one session. (Background `research` tickets are the sole exception and run in parallel subagents.)

## Four Decision Ticket Types

Every child ticket carries a `wayfinder:<type>` label (`research`, `prototype`, `grilling`, or `task`). Consult [references/wayfinder-map.md](./references/wayfinder-map.md) for the map schema and tracker operations:

- **`wayfinder:grilling` (HITL - Default)**: Interactive decision tree resolved by calling `shape-grilling` and `shape-domain`.
- **`wayfinder:research` (AFK)**: External doc or codebase fact-finding resolved in parallel by a fresh-context background subagent calling `research-topic`.
- **`wayfinder:prototype` (HITL)**: Throwaway logic or UI experiment resolved by calling `shape-prototype` and linking the prototype branch.
- **`wayfinder:task` (HITL or AFK)**: Prerequisite manual action (provisioning a sandbox account, migrating sample data) required before a decision can be evaluated.

## Two Invocation Modes

### Mode A: Chart the Map (Invoked with a Loose Epic Idea)

1. **Name the Destination**: Call `shape-grilling` and `shape-domain` to pin down the exact destination (what reaching the end of the map looks like).
2. **Survey the Frontier Breadth-First**: Grill across the problem space to surface the initial sharp questions and identify what sits in the fog. If zero fog exists and the whole effort fits in one session, stop and route directly to `/shape-grill` -> `/shape-spec`.
3. **Publish Map and Initial Tickets**: Create the `wayfinder:map` issue (or `.scratch/<effort>/map.md`) following [references/wayfinder-map.md](./references/wayfinder-map.md). Create child tickets for the sharp questions in a first pass, then wire blocking edges with real IDs in a second pass.
4. **Dispatch Research Subagents**: For every unblocked `wayfinder:research` ticket, launch a fresh-context background subagent calling `research-topic` on a `research/<slug>` branch. Stop after charting.

### Mode B: Work Through the Map (Invoked with an Existing Map Reference)

1. **Load Map & Claim One Frontier Ticket**: Read the low-resolution map body, select the user-specified ticket or the first unclaimed, unblocked **frontier** ticket, and claim it immediately (`@me` assignee or `Status: claimed`).
2. **Resolve by Type**: Execute the skill corresponding to its `wayfinder:<type>` label (`shape-grilling` + `shape-domain`, `shape-prototype`, `research-topic`, or `task`).
3. **Record Resolution & Advance Frontier**: Post the answer on the ticket, close/resolve it, append a one-line context pointer (`- [Ticket Title](link): <one-line gist>`) to `## Decisions so far` on the map, graduate any newly clarified patches from `## Not yet specified` into fresh child tickets, and move any out-of-bounds tickets to `## Out of scope`.
