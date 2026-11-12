# ADR-072: The release announces itself in Discord, with its media from the repo

- **Status:** Accepted
- **Date:** 2026-11-06
- **Deciders:** the maintainer
- **Related:** [ADR-046](046-one-action-release.md) (one-action release) · [Release](../operations/release.md) (the runbook) · [Release media](../releases/README.md) (the media folder) · [ADR-084](084-every-changelog-line-carries-its-japanese.md) (`ja.md` written with each changelog line, and required by the release)

## Context

Releases go out from one workflow run ([ADR-046](046-one-action-release.md)): the changelog is cut, the zip built, checked, pushed and published to CurseForge and GitHub. The project's Discord server hears nothing unless someone posts by hand, and a hand-written post drifts from the notes. The maintainer wants every release to post itself, with the feature pictures and a short clip when the release has them, shown compactly, and a way to see the post before the first real one.

Two things needed deciding: where the media lives so a GitHub run can attach it, and how the post is shaped so Discord does not fill the page with it.

## Decision

Release media lives in the public repo, in `docs/releases/next/` while a release is being prepared; the release commit renames it to `docs/releases/<version>/`. An announce step at the end of the release run posts the clips and pictures as attachments, which Discord shows as tiles at the top of the post, with the English card and the release's own changelog lines, and then a second message with a Japanese card holding the text of `ja.md` from the same folder. The Japanese card has its own message because Discord allows 6000 characters of cards in one message and each card may hold 4096; one message with both was refused once the notes grew long. The step runs after the zip is live and a failure in it is a warning, never a failed release. A separate preview workflow posts the same shape to a private test channel, from `## Unreleased` and `next/`, without releasing anything.

## Rationale

- The media on the site and in the CurseForge gallery is already public; keeping copies in the repo costs nothing in secrecy and lets the workflow attach them without a host.
- `next/` means nobody has to know the version number the release rule will pick; the rename rides in the commit the release already makes, so the history shows which media went with which release.
- The maintainer chose the media on top, in one post, from two previews in the private channel: Discord's tiles above the text, the clip with its player, over the alternatives of a picture inside the card or a second message for the clip. The preview run is where the look is judged before anyone sees a real post.
- The post is both languages, like every player-facing text of the project: the Japanese card's text is in `ja.md`, since the changelog is English (written with each changelog line since [ADR-084](084-every-changelog-line-carries-its-japanese.md)).
- The post is built from `.release-notes.md`, the same notes as the GitHub release and the CurseForge file, so the three never disagree.
- The webhook URL is a secret: the command reads it from the environment only, never from an argument, and never prints it. Only the announce step sees it, and it checks for itself whether it is set.

## Consequences

### Positive
- No step for the maintainer at release time; the post cannot be forgotten or mistyped.
- The repo records which media each release carried.
- A release with no media folder still posts; a release with no webhook still releases.

### Negative
- Clips add a megabyte or so per release to the repo.
- Two secrets to keep (the live and the test webhook).
- Discord's limits bound the post: at most ten files of 20 MiB each, and notes over 4096 characters are cut at an entry with a link to the full notes.

## Alternatives considered

- **A picture inside the card, or the clip in a second message.** Both put the media under or beside the text; the maintainer wants it on top, in one post, and Discord's tiles do that.
- **Media hosted elsewhere (the site, a CDN) and linked.** It would need a second upload, a URL per release, and a host to keep up; the repo already holds the release and the run already checks it out.
- **Posting by hand after a release.** The current state. It is forgotten, and the words drift from the notes players read on CurseForge and GitHub.
- **Failing the release when the post fails.** The zip is already live by then; failing would leave a resumed release with nothing to redo. A warning in the run is enough.
