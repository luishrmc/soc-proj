# Issue Tracker: Local Markdown

Issues, specs, and tickets for this repository live as local Markdown files under `.scratch/`.

## Conventions

- **One feature per directory**: `.scratch/<feature-slug>/`
- **Specification file**: `.scratch/<feature-slug>/spec.md`
- **Ticket files**: One file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered sequentially from `01` in dependency order (blockers first). Never combine multiple tickets into a single file.
- **Blocking edges**: Recorded via a `**Blocked by:**` line near the top of each ticket file listing blocking ticket numbers/titles, or `None (can start immediately)`.
- **Triage and execution state**: Recorded via a `**Status:**` line (`ready-for-agent`, `claimed`, `resolved`, etc.).
- **Comments and notes**: Appended to the bottom of the ticket file under a `## Comments` heading.

## Skill Operations

- **"Publish to the issue tracker"**: Create `.scratch/<feature-slug>/spec.md` for specifications, or `.scratch/<feature-slug>/issues/<NN>-<slug>.md` for tickets.
- **"Fetch the relevant ticket"**: Read the markdown file at the referenced `.scratch/` path.
- **"Frontier query"**: Scan `.scratch/<feature-slug>/issues/` for tickets with `**Status:** ready-for-agent` whose listed blockers are all marked `resolved`.
