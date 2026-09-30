# ADR-046: One-action release: a workflow run is the release

- **Status:** Accepted. Supersedes in part [ADR-006](006-git-repo-is-the-database.md) (a workflow run, not a hand-pushed tag, is the release). Runbook: [Release](../operations/release.md).
- **Date:** 2026-09-28

## Context

[ADR-006](006-git-repo-is-the-database.md) made a pushed version tag the release: the maintainer merges, writes an annotated tag with the notes, pushes it, and CI builds and publishes. That has costs:

- **More than one action, and local tools.** A tag push needs a local clone, the right commit checked out, a version chosen by hand and notes written by hand in the tag message. A release should be one action that works from the GitHub website with no local setup.
- **A public repo.** The repo is public and takes pull requests from forks. The release path must not give untrusted code a write token or the CurseForge token, and third-party actions must not change under it.
- **Notes drift.** Notes typed at tag time are written from memory after the fact. Players read them on CurseForge.
- **The alternatives cost a second step.** A release pull request (a bot keeps a "release X.Y.Z" pull request open and merging it releases) makes every release two merges and needs a bot with write access to pull requests.
- **Verified facts about the tooling** (BigWigsMods packager v2.6.1, pinned at commit `e50a250f`): it builds from `.pkgmeta` and the TOC, turns `## Version: @project-version@` into the tag name, maps a TOC `## Interface` of 16xxx to the Forever game type on its own, and copies the working tree (dotfiles pruned). Run a second time with `-c -o` (skip the copy, keep the package folder), it zips the folder the first pass made and uploads it; the second zip has the same entries and CRCs as the first.

## Decision

1. **The release is one `workflow_dispatch` run** of `.github/workflows/release.yml` on `main`, with one optional input, `version`. Its jobs: **plan** (on `main` only; the `CF_API_KEY` secret must be set; `wfj release next-version` picks the version) → **validate** (the whole pull-request workflow, reused through `workflow_call`) → **release**: cut the changelog, commit as `github-actions[bot]`, make an annotated tag `vX.Y.Z` (all on the runner), build with the packager (`-d`), check the zip with `wfj package-check`, push the commit and tag together (`git push --atomic`; if `main` moved, the push fails and nothing is published), then run the packager again with `-c -o` to upload the same checked folder to CurseForge and a GitHub release. Only one run at a time (`concurrency: release`; a waiting run is cancelled only if a third is started). `make release [VERSION=…]` starts the same run from a terminal with the GitHub CLI and follows it.
2. **Nothing leaves the runner until the zip passes the package check.** `wfj package-check` fails on any top-level entry other than `WoWForeverJapanese/`, any file that is not a tracked file of `addon/WoWForeverJapanese/` (dotfiles such as `.gitkeep` never ship) or `LICENSE` / `ATTRIBUTION.md` (or a missing one), a TOC-listed file missing, a TOC `## Version` other than `vX.Y.Z`, a non-numeric `## X-Curse-Project-ID`, or any dependency field. The publish step zips the folder that was checked, not a fresh copy.
3. **`CHANGELOG.md` is the only source of release notes**, in Keep a Changelog groups (Added, Changed, Fixed, Removed, Breaking) under `## Unreleased`. The run moves that section under `## X.Y.Z - YYYY-MM-DD` and publishes it as the CurseForge changelog and the GitHub release text. The version follows from it: no tags → `0.1.0-alpha.1`; after a pre-release, the same base with N + 1; after a release, a Breaking line → next major, an Added line → next minor, else next patch. Leaving alpha or beta is done by typing a version. An empty Unreleased section, a changelog out of shape (one `## Unreleased`, dated version headings, only the five groups, `- ` entries), and released sections that differ from those at the latest release tag (a pull request merged across a release) all refuse to release.
4. **A pull-request changelog gate** (`wfj release changelog-gate`): a pull request that changes `addon/` or `data/` adds a line under Unreleased; released sections may not change (compared at the merge-base; renames out of `addon/` or `data/` count as changes); an added line may not carry a ticket id or a local path; the changelog's shape is checked as above.
5. **Resume.** When a run fails after its push (CurseForge down, no Forever game version yet), running it again with the same version typed sees that tag on `main`'s tip, skips the cut, commit, tag and push, rebuilds from the tagged commit and publishes. CurseForge never replaces a file, so a resume is refused when the GitHub release (the packager's last upload) already holds the zip; if CurseForge has the file but GitHub does not, the maintainer attaches it by hand instead of resuming.
6. **Least privilege.** Every workflow's default token is read-only; the release job alone gets `contents: write`. The CurseForge token is passed only to the publish step; the plan job sees only whether it is set. The checkout keeps no credentials: the write token is given to the push step and the publish step only, never to the build. Every third-party action is pinned to a full commit SHA. No workflow uses `pull_request_target` or `workflow_run`, none splices a `${{ }}` expression into a `run:` script, and none releases on a tag push. `tests/python/test_workflows.py` asserts all of this.
7. **The data delta goes to the job summary**, not a pull-request comment: when a pull request changes `data/`, `wfj stats --delta` is written to the run's summary. A summary needs no write token; a comment would, and fork pull requests get none.
8. **The release bot pushes to `main`.** When `main` is protected by a ruleset, that ruleset needs a bypass that lets the Release workflow push; without it the run fails at the push, before anything is published.

## Consequences

- A release is one click (or `make release`) and needs no local tools. The maintainer reviews the Unreleased section on `main` instead of writing notes.
- Every pull request that changes what players get carries its own player-facing line, so the notes are written when the change is fresh. Contributors have one more thing to write; the gate tells them.
- Releases always ship the tip of `main`. There is no release of an older commit: a rollback is a revert pull request followed by a release.
- `main` gets a `Release X.Y.Z` commit from the bot on every release. Pushes made with the workflow token start no other workflow, so the commit does not trigger a second run of the checks.
- A failed publish after the push leaves a tag with no published file until the run is resumed. Resume works only while the release commit is still `main`'s tip; otherwise the next version carries the changes.
- Until the CurseForge project id is in the TOC and the `CF_API_KEY` secret exists, every release run stops before pushing.

## Alternatives considered

- **Tag push releases (ADR-006 as written)**: needs a local clone, a hand-picked version and hand-written notes in the tag message; the tag is public before anything is checked.
- **A release pull request kept open by a bot ("release-please" style)**: two merges per release, and a bot with write access to pull requests.
- **Every merge to `main` releases**: players would get a new file for each docs or tooling merge unless every merge is filtered, and the maintainer loses the choice of when to ship.
- **Our own CurseForge uploader**: more code to own for what the packager already does, including the Forever game-type mapping it reads from the TOC.
