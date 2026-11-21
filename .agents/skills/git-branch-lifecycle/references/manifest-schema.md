# Lifecycle State Manifest & Recovery Matrix

## Output Contract (`.agent/lifecycle-state.json`)

```json
{
  "status": "READY",
  "stage": "git-branch-lifecycle",
  "branch_name": "feat/proj-102-fix-memory-leak-in-websocket",
  "base_branch": "main",
  "base_commit_sha": "e2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1",
  "head_commit_sha": "e2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1",
  "clean_state_verified": true,
  "remote_synced": true,
  "collision_resolved": false,
  "worktree_path": "/workspace/repository",
  "timestamp_utc": "2026-11-06T20:50:00Z"
}
```

## Error Handling & Failure Recovery Matrix

| Exit Code | Failure Condition | Diagnostic Signal | Remediation Action |
| :---: | :--- | :--- | :--- |
| `1` | **Missing Input or Non-Git Dir** | Empty task string or `git rev-parse` non-zero | Pass explicit task description inside the Git repository root. |
| `2` | **Dirty Working Tree** | `git status --porcelain=v1` non-empty | Halt immediately. Report modified files to the user for manual commit or stash. |
| `3` | **Pending Rebase or Merge** | `.git/MERGE_HEAD` or `.git/rebase-merge` exists | Abort pending operation or ask operator before re-initializing branch. |
| `4` | **Unresolved Base Branch** | Neither `origin/HEAD` nor standard trunk names exist | Ask the user to specify the repository's canonical base branch. |
| `5` | **Base Divergence** | Local base branch has unpushed commits ahead of `origin` | Halt immediately to avoid overwriting unpushed local commits on base. |
| `6` | **Fast-Forward Failure** | `git merge --ff-only` fails | Alert operator to diverged base history. |
| `7-8` | **Ref Format or Checkout Error** | `git check-ref-format` or `git checkout -b` fails | Inspect sanitized slug and filesystem permissions. |
