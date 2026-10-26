# How we work in this repo

We are not software developers. Claude writes nearly all of the code **and** is the code reviewer;
we don't read diffs. Explain what you did in plain language, and stop to ask before anything risky
or hard to undo.

Two people share this repo from three Windows machines. GitHub is the source of truth.

## Guardrails (enforced, don't work around them)

`.claude/hooks/guard.ps1` and `.githooks/pre-push` block: committing or pushing to `main`,
force pushes, skipping the git hooks (`--no-verify`, `git commit -n`), and merging a pull request
that has not been reviewed or is missing newer changes from `main`. The guard checks the folder a
command really runs in (`git -C <folder>`, or a `cd <folder>` before it), so that folder must be
written out in full, with no variables such as `$env:TEMP`. If one of them
blocks you, follow its message. Never edit or disable them unless a person explicitly asks.

**When asked to "test the safety checks"** (after setting up a computer, or in a new repo): from
`main` with no changes, run `git commit --allow-empty --dry-run -m "Safety check test"` and
`git push --dry-run origin main`; the guard must refuse both. Then check git's own layer:
`git config core.hooksPath` must print `.githooks`, and, with the Bash tool,
`printf 'refs/heads/main 1111111111111111111111111111111111111111 refs/heads/main 2222222222222222222222222222222222222222\n' | sh .githooks/pre-push origin test`
must print a BLOCKED message. Nothing is committed or sent either way. Report each result; if
anything was not refused, stop and tell us.

## Workflow for every change

1. **Start fresh:** `git switch main`, then `git pull`.
2. **Check for overlap:** we often work at the same time. Run
   `gh pr list --json number,title,body,author,headRefName,files`. If someone else's open PR touches,
   or plans to touch, the files or area this change will touch, tell us who and what before
   starting, so we can agree who goes first. A `WIP:` PR may list no files yet: judge it by the
   planned files in its body.
3. **Branch and announce it:** run `git switch -c <short-description>` (for example
   `fix-report-totals`) as a command on its own, then `git commit --allow-empty -m "Start: <what this
   change is>" -m "Planned files: <files or area this will touch>"`, `git push -u origin <branch>`
   and `gh pr create --title "WIP: <what this change is>" --body "Planned files: <files or area this
   will touch>"`. This early PR is how the other person's
   overlap check sees the work while it is being built. (Draft PRs aren't available for private
   repos on our free plan, hence `WIP:`.)
4. **Build** the change. Run it or test it the way this README says, and show us it works.
5. **Commit** with a plain-English message, then `git push`. Push after every commit, not just at
   the end, so the work stays visible.
6. **Finish the PR:** write the description to a file in the temp folder (`$env:TEMP`, never inside
   the repo) with the Write tool, so it is plain UTF-8 (PowerShell's `>`, `Out-File` and
   `Set-Content` garble it or add an invisible byte-order mark), then `gh pr edit --title "<final plain-English title>" --body-file <that file>`. The
   description says what changed, why, and how it was checked, for a non-programmer. The title
   becomes the commit message on `main`, and the guard refuses to merge a `WIP:` title.
7. **Catch up with the PR's base branch** (usually `main`): `git fetch origin`, then
   `git merge --no-edit origin/<base>` (not `git pull`, which rebases on some machines and rewrites
   pushed commits). If it reports conflicts, resolve them so both people's changes survive (never
   just keep one side), tell us what overlapped, and finish with `git commit --no-edit`. Re-test,
   push.
8. **Review:** this replaces a human reviewer. Match its depth to the risk of the change, and when
   unsure pick the higher level:
   - **Light** (wording in a README or notes, code comments, colours, labels or layout):
     `/code-review low`, one pass. Never for CLAUDE.md, for notes that hold the repo's rules or that
     its data rules mention (for example pdf-viewer's NOTES.md and SPEC.md), or for anything listed
     under Thorough. In a repo with client-data rules, every level also checks the diff and the PR's
     GitHub text (branch name, title, description, review comment) against those rules, using the
     check its About section describes.
   - **Standard** (the default for code changes): `/code-review medium`, or hand the diff to a fresh
     subagent that did not write the code. Fix real problems, then check just those fixes once;
     no repeated full rounds.
   - **Thorough** (CLAUDE.md or any file holding the repo's rules; `.claude/`, `.githooks/` or other
     safety checks; anything touching client or job data, passwords, logins, user data, file uploads
     or anything internet-facing; code or settings that decide which files are saved or changed): `/code-review high`, plus `/security-review` where relevant. Fix every
     real problem and review again until no real problems are left, for at most three rounds in
     all (the first review plus two re-reviews). If the third round still finds a new real problem,
     stop and ask us instead of continuing.
   - **What counts as a real problem:** something that would actually go wrong in how we use the
     repo, such as a wrong result, lost or overwritten work, client data getting out, or a safety
     check misbehaving on the commands we really type. Not real problems: style preferences, and,
     for our own team guardrails only (`.claude/hooks/`, `.githooks/` and these rules, which exist
     so we don't overwrite each other, not to stop attackers), theoretical edge cases, unusual ways
     of typing a command and deliberate attempts to get around them. List those in the approval
     comment instead of fixing them, described in general terms with no client or job details.
     Anything internet-facing, logins, passwords, file uploads and client-data checks are
     different: there, a way an outsider could get in or client data could slip through is a real
     problem even if it is unlikely.
   - **Re-reviews** after fixing review findings check only the fixes and what they could break,
     not the whole change again. New work, or a merge from `main`, after a review is not a
     re-review: it gets a fresh review of everything new.
   - Post the approval as a PR comment (`gh pr comment --body-file <file>`, written to `$env:TEMP` with the Write tool as in step 6). The
     first line must be exactly
     `Claude review: APPROVED for <full commit sha of the PR head>`, followed by a short
     plain-English summary of what was checked (including which review level) and anything we
     should know.
     New commits after approval need a fresh review and a fresh comment.
9. **Merge:** `gh pr merge --squash --delete-branch --match-head-commit <approved full sha>`, as a
   command on its own with no quoted text (the one exception is the rules sync below, where it
   follows a single `cd "<clone>" &&` in Bash or `Set-Location "<clone>";` in PowerShell). The sha makes GitHub refuse the merge if anything was
   pushed after the review. A person will be asked to approve it. If the guard says the base branch
   has moved on (the other person merged first), go back to step 7.
10. **Tidy up:** `git switch main`, then `git pull`.

Before ending a session, commit and push any work in progress to its branch, even if it is unfinished,
so the other person and the other machines can see it.

## Secrets

Never put passwords, API keys, tokens, or client data in code or commits, and never put client or job
details (their names, addresses, the names of their files, or sheet titles) in branch names, PR
titles, PR descriptions or review comments: those reach GitHub without passing any commit check, and
GitHub keeps their edit history. In a repo with a client-data check, run it on each of these before
it is pushed or posted (steps 3, 6 and 8), not only at review. Use a `.env` file
(git-ignored) and keep a `.env.example` with the variable names and fake values. If a secret is ever
committed, tell us immediately so we can change it. Removing it from the code is not enough.

## Team rules come from the template

`True-South-Surveyors/repo-template` is the source of the shared rules. Change rules there first,
never only in one repo. When asked to "push the new rules to all our repos", for each repo in
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
- Follow the workflow above: one PR per repo, titled "Update team rules from template". These PRs
  touch safety checks, so the review is **Thorough**.
- **Copied as-is:** `.claude/hooks/guard.ps1`, `.githooks/pre-push`.
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

**A new repo made from the template** (any repo other than `True-South-Surveyors/repo-template`
whose README is still the template's team guide and whose `## About this project` is empty; the
template's own README stays the team guide): on its first branch, rewrite the README to be about the project,
ending with the "How we work on this repo" section, and fill in the About section here.

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

## About this project

### VRS Control Check

This repo hosts **VRS Control Check**, a single-page browser tool the crew uses to check surveyed VRS/GPS points against an engineer's control points and record which adjustment was applied. It is served on GitHub Pages from `index.html` on `main`, so anyone with the link can use it without a GitHub account. A merge to `main` goes live within a minute or two.

#### Who uses it and why

- The owner is Dakota, a surveyor. Field crews shoot the engineer's control monuments with VRS (network RTK). Those shots are stored as `V1`, `V2`, ... points.
- The tool inverses each VRS point to its control point (bearing, horizontal distance, vertical difference = control − VRS). It then tests adjustments that bring the VRS points onto the engineer's control and prints a record sheet modeled on the crew's hand-written "Field Adjustments" sheet.
- **The tool only reports adjustment parameters.** Crews apply the adjustment manually in Carlson Survey / AutoCAD. Never assume the tool writes coordinates back to a job.
- A Carlson/AutoCAD add-in may come later, but the decision (Oct 2026) was a standalone web page.

#### Client and job data rules

- **This repo and its website are public.** Dakota chose this (Oct 2026) as an exception to the team's Private rule, because GitHub Pages on the free plan needs a public repo. Anyone can read every file and every commit. Never commit real job data: no `.crd` files, control `.txt`/`.csv` files, field sheets, client or project names, or real coordinates. The sample job `samples/example-job.vrscheck.json` uses real relative geometry moved to made-up base coordinates. Keep it that way. (The page used to load it on its own as a built-in example; Dakota had that removed in Oct 2026 so the page opens blank.) The file carries `"sample": true`, which stamps EXAMPLE DATA on the sheet and makes loading or pasting real points replace it instead of mixing with it.
- The same goes for GitHub text: branch names, PR titles, PR descriptions and review comments must not name a client, job, job number, file name or sheet title. This repo has no automated client-data check, so before each push or post (steps 3, 6 and 8), read the diff and that text yourself and keep it generic (for example "fix rotation on record sheet", not a job name). Say in the approval comment that you checked.
- `index.html` is internet-facing, so changes to it get the **Thorough** review. Changes to README wording only can be Light.

#### Hard rules for the code

- **Keep it one self-contained file.** Everything (HTML, CSS, JS) lives in `index.html`. The only external loads are Google Fonts (IBM Plex) and, only when a SQLite-style `.crd` is opened, `sql.js` 1.8.0 from jsDelivr, pinned with an SRI hash (if you change the version, update the hash too). Don't add a build step, framework, or backend.
- **Nothing leaves the browser.** Files are read locally. State is saved to `sessionStorage` (not `localStorage`) under the key `vrs-control-check-v1`, so it survives a refresh but is cleared when the tab closes (a browser that reopens closed tabs or restores the last session can bring it back). Dakota chose this (Oct 2026) so a job isn't left behind on a shared computer. If older versions left a job in `localStorage`, `restore()` loads it into the tab once (unless the tab already has a job) and deletes the `localStorage` copy, so work in progress isn't lost at the changeover. If you change the shape of the saved state, keep `restore()` tolerant of older saves, or bump the key.
- **Naming:** Dakota wants the adjustment terms **Translation / Rotation / Scale** used everywhere in the UI and on the printed sheet. Don't write "shift", "rotate", or "transform" in user-facing text.
- The company name on the sheet defaults to "True South Surveyors" (`DEFAULT_COMPANY`).

#### What the tool does

Page sections: **1 Points**, **2 Pairs**, **3 Adjustment**, **Results**, **Record details**, **Compare adjustments**, and a printable record sheet (print → Save as PDF).

**Inputs**
- PNEZD text/CSV (point, northing, easting, elevation, description). Other column orders can be selected.
- Carlson `.crd` binary. The alphanumeric "New CRD Format2" layout (signature at byte 72) is decoded and verified against a real job: 104-byte header, then 66-byte records of N, E, Z (little-endian doubles), a 32-byte description, and a 10-byte NUL-padded point ID. Z = 0 means no elevation. Numeric-only and SQLite `.crd` variants use a best-guess reader (`parseBinaryCRD`, `parseSQLiteCRD`). If one fails on a real file, ask for a sample, and don't commit it.
- Pairs are suggested automatically by nearest control point within 5 ft (`SUGGEST_FT`).

**Horizontal adjustments** (`S.adj.hm`, solved in `solve()`)
- Translation to one pair (hold a pair).
- Translation (average of the pairs ticked Fit).
- Translation + Rotation (translate onto one pair, then rotate about that control point so a second pair's bearing matches the control bearing).
- Least-squares best fit, with optional Scale.
- Manual by points: translation base point → translate-to point; an optional separate rotation base point (blank = same as the translation base); a reference bearing from the rotation base to a V#, and a new bearing to a control point; optional scale.

**Vertical adjustments** (`S.adj.vm`): hold a pair, average, split the difference (`mid`), or manual.

The UI help text for each mode lives in `MODE_HELP`.

**Output:** residuals per pair before and after, a plot, a scenario comparison table, CSV download, and the record sheet. The sheet holds project, sub, date, by, point range, notes on the check hub and base pole, and the decision or reason the adjustment was chosen.

#### Field conventions worth knowing

- `V#` = raw VRS shots. `A#` = adjusted copies of `V#` made in Carlson. `D#` = temporary intermediate points.
- Descriptions containing `BP` mark the base pole, and `HUB` (e.g. "CHK HUB") marks the check hub.
- Hand sheets usually round translations to 0.01 ft before applying them. Older sheets truncate distances to 0.01. Some pairs get extra weight ("counted twice") or are ignored. Vertical differences are control − VRS (one older job wrote VRS − control).
- Accuracy check (Oct 2026): the tool was compared against 111 of Dakota's past adjusted jobs. 491 of 499 bearings matched exactly, and every difference traced to the hand sheet or later file edits, not to the tool's math. **Treat the geometry in `solve()` as verified, and don't change the math casually.** If you must change it, re-check that Translation + Rotation still reproduces a known job exactly (use a job from Dakota's own files, never committed).

#### How to run and test it

- Open `index.html` directly in a browser (double-click it). There is nothing to install or build.
- After a change: check the browser console for errors, check the page opens blank, load `samples/example-job.vrscheck.json` with Open job, and confirm Results, the plot, Compare adjustments and the record sheet all render. Check Print Preview. Check a phone-width window too, since crews may open it in the field.
- Dakota is a surveyor, not a developer. Explain changes in plain surveying terms.
