# Wayfinder Map & Ticket Schemas

Reference for structuring the `wayfinder:map` parent artifact and its child decision tickets across GitHub, GitLab, or Local Markdown trackers (`docs/agents/issue-tracker.md`).

## 1. The Map Body (`wayfinder:map` Issue or `.scratch/<effort>/map.md`)

The map is a compact **index** loaded once per session. Open tickets are queried via child links rather than duplicated in the map body:

```markdown
## Destination

<1 to 2 sentences defining what reaching the end of this map produces: e.g., a complete architecture spec ready for /shape-spec.>

## Notes

<Domain context, standing constraints, and skills every session should consult.>

## Decisions so far

<!-- One-line context pointer per resolved ticket; click through to the ticket for full detail -->
- [<Closed Ticket Title>](link): <One-line summary of the settled decision>

## Not yet specified

<!-- In-scope fog of war: suspected questions that depend on open frontier tickets before they can be phrased sharply -->

## Out of scope

<!-- Work ruled beyond the destination; links closed tickets with a 1-line rationale -->
```

## 2. Child Decision Ticket Body

Each child ticket is sized to resolve within a single 100k-token session and carries one label (`wayfinder:grilling`, `wayfinder:research`, `wayfinder:prototype`, or `wayfinder:task`):

```markdown
## Question

<The exact architectural decision, trade-off, or factual investigation this ticket must settle.>
```

## 3. Tracker-Specific Operations

| Operation | GitHub / GitLab Tracker | Local Markdown (`.scratch/<effort>/`) |
| :--- | :--- | :--- |
| **Create Map** | Create issue with label `wayfinder:map` | Write `.scratch/<effort>/map.md` |
| **Create Child Ticket** | Create sub-issue (`--parent <map>`) with `wayfinder:<type>` label | Write `.scratch/<effort>/issues/<NN>-<slug>.md` with `Type:` and `Status: open` |
| **Wire Blocking Edges** | Native `blocked_by` dependency link (second pass after IDs exist) | `Blocked by: <NN>, <NN>` line at top of file |
| **Query Ready Frontier** | Open child issues with 0 open blockers and no assignee | Open child files whose listed blockers are all `Status: resolved` |
| **Claim Ticket** | Assign issue to `@me` before starting work | Set `Status: claimed` and save file |
| **Resolve Ticket** | Post resolution comment, close issue, append pointer to `map` | Append `## Answer`, set `Status: resolved`, append pointer to `map.md` |
