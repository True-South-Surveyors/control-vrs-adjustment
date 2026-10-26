# VRS Control Check

A browser tool for checking surveyed VRS points against an engineer's control points.

**Open it here:** https://true-south-surveyors.github.io/control-vrs-adjustment/

## What it does

- Loads VRS points and control points from Carlson `.crd` files or PNEZD `.txt`/`.csv` files.
- Shows the horizontal and vertical difference for each VRS-to-control pair.
- Tries Translation, Rotation and Scale adjustments (one pair, average, translation + rotation, least-squares best fit, or manual by points) plus vertical options.
- Prints a record sheet with notes on the check hub, base pole, and why the adjustment was chosen. Use your browser's Print and pick "Save as PDF".

The tool only reports adjustment parameters. Apply the adjustment yourself in Carlson.

## Privacy

Everything runs in your browser. Files you load are never uploaded anywhere. The job you're working on survives a page refresh, but it's erased when you close the tab. Use Save job if you want to keep it.

## Updating

Ask Claude for the change (see below). Once the pull request is merged into `main`, GitHub Pages republishes the site in a minute or two.

## How we work on this repo

Changes go through Claude Code, following our team rules: each change gets its own branch and pull
request, Claude reviews it, and a person approves the merge. Setting up a computer, day-to-day tips
and how to change the rules are in the
[team template's README](https://github.com/True-South-Surveyors/repo-template#readme).
