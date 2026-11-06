---
name: sync-rules
description: Copy the template's team rules out to every True South Surveyors repo, or give an existing repo the template for the first time. Use when asked to "push the new rules to all our repos" or to bring a repo onto the template. Not for changing one repo's own rules. Run only from a session in True-South-Surveyors/repo-template.
---

# Pushing the team rules to our repos

Run this only from a Claude Code session in `True-South-Surveyors/repo-template`. If this session
is in another repo, stop and ask us to open the template instead. The workflow, review levels and
step numbers below are the ones in the template's own CLAUDE.md (not a clone's, which may be older).

When asked to "push the new rules to all our repos", for each repo in
`gh repo list True-South-Surveyors` other than the template:

- **Work in a fresh clone** in a new folder under `$env:TEMP` (never inside the template, never in
  someone's working folder, which may hold their unfinished work), from this template session.
  Find that folder's full path once (for example `C:\Users\<name>\AppData\Local\Temp\rules-sync\<repo>`)
  and write it out in every command, since the shell goes back to the template folder after each
  one and the guard can't follow variables: `git -C "<clone>" ...` for git, and
  `cd "<clone>" && ...` (Bash) or `Set-Location "<clone>"; ...` (PowerShell) for `gh` and anything
  else. The merge is `cd "<clone>" && gh pr merge ...` (Bash) or
  `Set-Location "<clone>"; gh pr merge ...` (PowerShell), with nothing else in the command. Right after
  cloning, run `git -C "<clone>" config core.hooksPath .githooks`: that only happens automatically
  when a Claude Code session starts in a folder, so without it no hooks run in the clone.
- Follow the workflow in the template's CLAUDE.md: one PR per repo, titled "Update team rules from template". These PRs
  touch safety checks, so the review is **Thorough**. Before reviewing, run the tests in the clone
  (`powershell -NoProfile -ExecutionPolicy Bypass -File "<clone>\.claude\hooks\guard-tests.ps1"`);
  they must pass, which also checks the hand-merged `.claude/settings.json`.
- **Someone may be working in the repo.** Run the overlap check (step 2) in each clone. If someone's
  open PR touches files the update changes, tell us who and what, and leave that repo until we
  agree. Their folder and branch are never touched; once the update is merged, their PR must catch
  up with `main` (step 7) before it can merge, keeping both sides of any conflict.
- **Copied as-is:** `.claude/hooks/guard.ps1`, `.claude/hooks/guard-tests.ps1`, `.githooks/pre-push`,
  `.claude/skills/sync-rules/SKILL.md`, `.claude/skills/test-safety-checks/SKILL.md`.
- **Merged, keeping the repo's own additions:**
  - `.claude/settings.json`: the template's entries, plus any the repo added.
  - `.gitattributes`: the template's lines, plus any the repo added.
  - `.gitignore`: add template lines it lacks; never remove the repo's lines, except that the old
    template line `.vscode/` is replaced by the template's `.vscode/*` lines (git can't let shared
    VS Code settings through while the whole folder is ignored).
  - `CLAUDE.md`: everything above `## About this project` comes from the template; everything from
    that heading to the end of the file belongs to the repo and stays exactly as it is.
  - `README.md`: it is about the project. The only template part is the short "How we work on this
    repo" section at the end of the template's README, which goes at the end of the repo's
    README, replacing any older copy. Remove older copies of the template's team sections
    ("Starting another project" through "How thorough the review is", and lines such as "This repo
    was created from our team template"); the team guide lives only in the template's README. Keep
    everything about the project. If the repo has no README, write a short one (what it is, where
    its own notes are, how to run it), then that section.
- **Never removed:** extra hooks in a repo's `.githooks/` and anything else project-specific.

**First time a repo gets the template** (it has no `.claude/settings.json` from us yet), also:

- **Keep its own git hooks running.** The template makes git run hooks only from `.githooks/`.
  Before adding the template's settings, look for hooks the repo already uses: folders such as
  `tools/hooks/` or `.husky/`, mentions in its notes or README, and `git -C "<working copy>" config
  --get core.hooksPath` in the person's own working copy if there is one (read-only; a fresh clone
  never has it).
  Add a `.githooks/<hook name>` for each that calls the existing script, keep the script's Unix line
  endings (add a `.gitattributes` line for it if needed), update any notes that say to set
  `core.hooksPath`, and prove each hook still works in the clone, with `git -C "<clone>"` (for example a test commit it
  should refuse, then throw that commit away; for a check that reads a private, git-ignored list,
  put a throwaway fake list in the clone for the test). Example: pdf-viewer's job-info check in
  `tools/hooks/`, which reads job names from the ignored `testfiles/ALIASES.md`.
- **Keep its CLAUDE.md.** If it has no `## About this project` section, put the template part on
  top and move the entire existing file, unchanged, under `## About this project`, with its
  headings pushed down two levels (`#` becomes `###`) so they all sit inside that section. If there
  is no CLAUDE.md, write a short About section pointing at the repo's own notes (for example
  PROGRESS.md).
- **Check its rules and notes against the template.** Read its CLAUDE.md and the notes its About
  section points to (for example SPEC.md, NOTES.md, TODO.md, PROGRESS.md) for steps the template's
  rules would now block or contradict (for example pm-folder-icons' release steps push straight to
  `main`: rewrite as version bump through a PR, merge, `git switch main`, `git pull`, then
  `git tag vX <hash of the version-bump commit>` (by its hash, in case the other person merged
  something after it) and `git push origin vX`). Show us each conflict and the proposed rewrite before
  committing.
- **Its client data rules cover GitHub text too.** If the repo handles client or job data (written
  rules, or signs such as ignore-file comments or notes about real job folders), write into its
  About section that branch names, PR titles, PR descriptions and review comments must not contain
  it, and how to check each one before it is pushed or posted. For pdf-viewer: use the Bash tool (Git Bash; `sh` isn't available in
  PowerShell) from inside the person's own working copy of pdf-viewer (read-only, since only that
  copy has the real `testfiles/ALIASES.md`) to run `tools/hooks/job-info-guard.sh message <file>`
  on a copy of each text with leading `#` removed (`sed 's/^#*//'`), since the script skips `#`
  lines; pass the file path in quotes with forward slashes. Use hyphens, not underscores, in branch
  names so whole-word matching works. It counts as checked only if it exits 0 and prints nothing at
  all; any output or a non-zero exit means it found job information or did not really check, so
  fix the text or keep it generic (no job names, client file names or sheet titles) and say so.
- If `.gitattributes` would change line endings of files already in the repo, say so before
  committing.

