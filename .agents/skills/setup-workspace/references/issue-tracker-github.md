# Issue Tracker: GitHub

Issues, specs, and tickets for this repository live as GitHub Issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."` (use a heredoc for multi-line bodies).
- **Read an issue**: `gh issue view <number> --json number,title,body,labels,comments`.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments` with `--label` filters as needed.
- **Make an issue a sub-issue of a parent**: `gh issue create --parent <parent> ...` or `gh issue edit <parent> --add-sub-issue <child>` (`gh` 2.94+). Fallback: place `Part of #<parent>` at the top of the child issue body.
- **Blocking edges**: Use GitHub native issue dependencies via `gh issue create --blocked-by <n>,<n>` or `gh issue edit <child> --add-blocked-by <blocker>`. Fallback when native dependencies are unavailable: place `Blocked by: #<n>, #<n>` at the top of the child body. A ticket is unblocked when all its blockers are closed.
- **Count open blockers**: `gh issue view <n> --json blockedBy --jq '[.blockedBy.nodes[] | select(.state == "OPEN")] | length'`. Zero open blockers means the ticket is on the ready frontier.
- **Comment on an issue**: `gh issue comment <number> --body "..."`.
- **Apply or remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`.
- **Close an issue**: post the resolution comment via `gh issue comment <number> --body "..."`, then run `gh issue close <number>`.

Before running the first `gh issue create` in a session, verify the target repository with `gh repo view --json nameWithOwner` so issues are never filed against an upstream fork parent by mistake.

## Skill Operations

- **"Publish to the issue tracker"**: Create a GitHub issue and apply the `ready-for-agent` label (or mapped equivalent from `docs/agents/triage-labels.md`).
- **"Fetch the relevant ticket"**: Run `gh issue view <number> --json number,title,body,labels,comments`.
