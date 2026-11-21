# Safety Guard Manifest & Remediation Matrix

## Output Contract (`.agent/safety-guard-manifest.json`)

```json
{
  "status": "COMPLETED",
  "stage": "git-safety-guard",
  "commit_status": "COMMITTED",
  "commit_sha": "d7a45e98b0a12f34c56789e0123456789abcdef0",
  "branch_name": "feat/proj-102-user-phone-validation",
  "verification_summary": {
    "secrets_scanned": true,
    "secrets_detected": false,
    "file_size_checked": true,
    "binary_guard_passed": true,
    "linter_passed": true,
    "tests_passed": true
  },
  "failure_reasons": [],
  "timestamp_utc": "2026-11-06T20:55:00Z"
}
```

## Failure & Remediation Matrix

| Exit Code | Failure Mode | Root Cause | Agent Remediation Action |
| :---: | :--- | :--- | :--- |
| `1-2` | **Missing Manifest or Empty Index** | `git-commit-stager` did not run or staged 0 files | Run `git-commit-stager` first. |
| `10-14` | **Secret or Sensitive File Detected** | Private key, cloud/API token, hardcoded password, or `.env`/`.pem` staged | Unstage offending file (`git reset HEAD -- <path>`), replace with env variable lookup, and re-stage. |
| `20-22` | **Oversized or Binary Artifact** | Blob >5 MB, build/dependency folder, or binary file staged | Unstage offending artifact and add pattern to `.gitignore`. |
| `31` | **Linter Failure** | Static analysis or style check returned non-zero | Fix reported lint errors in source, re-stage via `git-commit-stager`, and re-run safety guard. |
| `32` | **Test Suite Failure** | Automated test suite failed under stash isolation | Fix regression using `dev-tdd`, re-stage, and re-run safety guard. |
| `40-41` | **Commit Execution Rejected** | Empty commit message or repository `.git/hooks` rejection | Inspect hook output and remediate before retrying without `--no-verify`. |
