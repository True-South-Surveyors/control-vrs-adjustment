# Team repo template

The starting point and the rule book for every True South Surveyors project. New repos are made
from it, and the team rules (how Claude works with us, and the safety checks) are changed here
first, then copied into every repo.

## Starting another project

Every True South Surveyors project starts from the `True-South-Surveyors/repo-template` repo.
On github.com: **New repository**, pick that repo under **Repository template**, keep it
**Private**, and create it. Or ask Claude: "make a new repo for <project> from our template".
Then open the new repo in Claude Code and describe the project. Claude rewrites its README to be
about the project (keeping only the short "How we work on this repo" section from this one) and
fills in the "About this project" section of its `CLAUDE.md`.

## Setting up a computer (once per person, per computer)

1. Install [Git](https://git-scm.com/download/win), the [GitHub CLI](https://cli.github.com/) and
   Claude Code.
2. Run `gh auth login` and sign in with your own GitHub account (it must be in True South Surveyors).
   Then tell git who you are, so your changes are labelled with your name:
   `git config --global user.name "Your Name"` and `git config --global user.email you@dlspllc.com`
   (the email on your GitHub account).
3. The first time you open a repo in Claude Code it asks whether to trust the folder. Say **yes**,
   otherwise the safety checks don't turn on. Then check that they work (next section).

## Checking the safety checks work

After setting up a computer, or starting a new repo, open the repo in Claude Code and say
**"test the safety checks"**. Claude tries a commit straight on `main` and a push to `main` (a dry
run, so nothing is sent), and checks the second safety layer that git runs by itself. Each one must
be refused. Nothing is changed either way. If anything goes through, stop and sort it out before
making changes from that computer.

## Day to day

Open the repo folder in Claude Code and say what you want in plain words. Claude makes a branch,
builds and tests the change, opens a pull request, reviews it, and asks you to approve the merge.

We often work at the same time, so:

- Claude checks open pull requests before starting and warns you if the other person is already
  changing the same files. Agree who goes first.
- Every change lives on its own branch and pull request, so nobody's work gets overwritten.
- If the other person merges first, Claude is blocked from merging until it has pulled their changes
  in, re-tested and re-reviewed.
- When Claude asks you to approve a merge, answer straight away. If you leave it and the other
  person merges in the meantime, say no and ask Claude to merge again, so it re-checks first.
- Before you stop for the day, say "save and push my work" so it's visible from the other computers.
- Make changes through Claude, not by editing files or merging on github.com. The website doesn't
  enforce these checks on our free plan.

## What every repo includes

- **`CLAUDE.md`**: the workflow Claude follows (feature branches, pull requests, Claude review, then
  merge), with the project's own notes at the end.
- **`.claude/`**: shared Claude Code settings, plus a guard that blocks risky git commands.
- **`.githooks/pre-push`**: blocks pushes straight to `main` and force pushes, whichever tool does the push.
  Claude Code turns it on automatically. If you push without Claude, run once per clone:
  `git config core.hooksPath .githooks`

## Changing the rules

The team rules live here, in `True-South-Surveyors/repo-template`, and every repo keeps its own copy.
To add or change a rule:

1. Open this template repo in Claude Code and describe the change. It goes through a normal pull
   request like any other change.
2. Once it's merged, stay in the template's window and say **"push the new rules to all our
   repos"**. Claude makes a fresh copy of each repo in a temporary folder (your own working copies
   aren't touched), opens one pull request per repo with the update, reviews it, and asks you to
   approve each merge.
3. Afterwards, in each repo you work on, say "pull the latest main" before anything else, then
   close and reopen that Claude Code window so the new settings load.

Each repo keeps its own project-specific parts (its "About this project" notes, its own safety
checks, its README). Claude moves those into place the first time a repo gets the rules, so an
update never wipes or switches them off.

## How thorough the review is

Claude matches the review to the risk of the change. Wording and layout changes get a quick check,
normal code changes get one review pass, and changes to safety checks, client data, logins or
anything that saves files get a full review, repeated for up to three rounds. Only real problems
get fixed; minor or far-fetched points are listed in the approval comment instead. If problems are
still turning up after three rounds, Claude stops and asks. Every PR's approval comment says which
level was used.

<!-- The section below is copied to the end of every project's README. Keep it short. -->

## How we work on this repo

Changes go through Claude Code, following our team rules: each change gets its own branch and pull
request, Claude reviews it, and a person approves the merge. Setting up a computer, day-to-day tips
and how to change the rules are in the
[team template's README](https://github.com/True-South-Surveyors/repo-template#readme).
