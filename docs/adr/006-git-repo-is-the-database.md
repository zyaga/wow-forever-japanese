# ADR-006: No cloud side: the git repo is the database, a tag is the release

- **Status:** Proposed. Release flow superseded in part by [ADR-046](046-one-action-release.md) (a workflow run, not a hand-pushed tag, is the release)
- **Date:** 2026-09-13

## Context
One option was a cloud database with an API holding the text, so clients could upload collected text and check in for updates. WoW addons cannot use the network at all; they can only read shipped files and write SavedVariables at logout/reload. The maintenance target is: review a PR, merge, release, even if the maintainer stops playing.

## Decision
The public GitHub repo holds the ID-keyed JSON (`data/`) and the English source snapshots; contributions arrive as PRs (data corrections) and issue attachments (collector files). CI validates every PR (schema, alignment, regenerated Lua identical to committed). A version tag triggers the standard packager action to build the zip and publish to CurseForge (CurseForge is where the audience is; a second host such as Wago can be added to the packager later at no design cost). No server, no API, no companion app.

## Consequences
- Maintainer effort is review + merge + tag; anyone with repo access can release.
- Collector hand-off is manual (attach a file). If that proves too painful, a Cloudflare drop-zone (Worker + R2) is a possible add-on that still requires a manual drag, since the game forbids anything else.
- Data is reviewable, diffable, and forkable; the project outlives its maintainer the way Questie and pfQuest have.

## Alternatives considered
- **Cloud DB + API + client check-in**: impossible from inside the game; would require a companion desktop app (second product).
- **Private data + manual releases**: hides the corpus, makes handoff a chore.
