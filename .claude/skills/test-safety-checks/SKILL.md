---
name: test-safety-checks
description: Check that the team's git safety checks (the guard hook and .githooks/pre-push) really refuse commits and pushes to main. Use only when asked to "test the safety checks" (usually after setting up a computer or starting a new repo).
---

# Testing the safety checks

From `main` with no changes, run `git commit --allow-empty --dry-run -m "Safety check test"` and
`git push --dry-run origin main`; the guard must refuse both. Then check git's own layer:
`git config core.hooksPath` must print `.githooks`, and, with the Bash tool,
`printf 'refs/heads/main 1111111111111111111111111111111111111111 refs/heads/main 2222222222222222222222222222222222222222\n' | sh .githooks/pre-push origin test`
must print a BLOCKED message. Nothing is committed or sent either way. Report each result; if
anything was not refused, stop and tell us.
