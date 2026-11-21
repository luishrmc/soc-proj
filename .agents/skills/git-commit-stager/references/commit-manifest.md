# Commit Staging Manifest & Edge Cases

## Output Contract (`.agent/commit-staging-manifest.json`)

```json
{
  "status": "STAGED",
  "stage": "git-commit-stager",
  "branch_name": "feat/proj-102-user-phone-validation",
  "staged_files": [
    "src/auth/validator.ts",
    "src/auth/types.ts",
    "tests/auth/validator.test.ts"
  ],
  "unstaged_files": [
    ".env.test.local",
    "debug.log"
  ],
  "commit_type": "feat",
  "commit_scope": "auth",
  "is_breaking": false,
  "commit_subject": "feat(auth): add user phone validation",
  "commit_body": "- Modify src/auth/validator.ts\n- Modify src/auth/types.ts\n- Modify tests/auth/validator.test.ts",
  "full_commit_message": "feat(auth): add user phone validation\n\n- Modify src/auth/validator.ts\n- Modify src/auth/types.ts\n- Modify tests/auth/validator.test.ts",
  "diff_stat": "3 files changed, 84 insertions(+), 6 deletions(-)",
  "lines_added": 84,
  "lines_deleted": 6,
  "execution_authority": "DELEGATED_TO_GIT_SAFETY_GUARD",
  "timestamp_utc": "2026-11-06T20:52:00Z"
}
```

## Edge Case Handling

1. **Clean Working Tree (`Exit Code 1`)**: `git status --porcelain=v1` returns zero lines. Halt immediately and report that no file modifications were produced.
2. **Large Diffs (>64 KB)**: Summarize changes using `git diff --staged --stat` and path structure rather than loading the entire raw patch into context.
3. **Mixed Unrelated Changes**: Stage only paths aligned with the active ticket scope; record unrelated modified paths in `unstaged_files`.
4. **Excluded Artifacts (`Exit Code 3` if all excluded)**: `.env*`, `*.pem`, `*.key`, `*id_rsa*`, `*token*`, `*credential*`, `*.log`, `*.tmp`, and `.agent/*` are automatically filtered into `unstaged_files`.
