# Issue Tracker: GitLab

Issues, specs, and tickets for this repository live as GitLab Issues. Use the `glab` CLI for all operations.

## Conventions

- **Create an issue**: `glab issue create --title "..." --description "..."` (use a heredoc for multi-line descriptions).
- **Read an issue**: `glab issue view <number> --comments` (add `-F json` for structured output).
- **List issues**: `glab issue list -O json` with `--label` filters as needed.
- **Comment on an issue**: `glab issue note <number> --message "..."`.
- **Apply or remove labels**: `glab issue update <number> --label "..."` / `--unlabel "..."`.
- **Blocking edges**: Post a quick-action note `glab issue note <child> --message "/blocked_by #<blocker>"` or include `Blocked by: #<n>, #<n>` at the top of the issue description. A ticket is unblocked when every blocker is closed.
- **Close an issue**: Post the closing note via `glab issue note <number> --message "..."`, then run `glab issue close <number>`.
- **Merge requests**: Use `glab mr create`, `glab mr view`, and `glab mr note`.

## Skill Operations

- **"Publish to the issue tracker"**: Create a GitLab issue and apply the `ready-for-agent` label.
- **"Fetch the relevant ticket"**: Run `glab issue view <number> --comments`.
