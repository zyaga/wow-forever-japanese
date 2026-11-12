# ADR-085: The release post is a short summary

- **Status:** Accepted
- **Date:** 2026-11-12
- **Deciders:** the maintainer
- **Related:** [ADR-072](072-the-release-announces-itself-in-discord.md) (the Discord post) · [ADR-084](084-every-changelog-line-carries-its-japanese.md) (superseded in part) · [Release](../operations/release.md) · [Release media](../releases/README.md)

## Context

The Discord post printed every changelog line of the release, in English and in Japanese. A release that gathers several pull requests has about thirty lines, each written in full for the changelog. The preview of such a release was first refused by Discord for its size, and once it fit, the maintainer judged it far too long and too detailed for an announcement.

## Decision

- The post's text is a short summary of the release in each language: `docs/releases/next/en.md` and `docs/releases/next/ja.md`, four to six lines, the most important first. Each card ends with a link to the full notes.
- A summary is at most 1500 characters; the announce command refuses a longer one.
- The release's plan step refuses an addon release while either file is missing or empty. The preview still runs without them: with no `en.md` the English card shows the changelog lines, with no `ja.md` there is no Japanese card.
- The pull-request Changelog check no longer asks for Japanese with each changelog line. The changelog stays English, written for players, and is what CurseForge and GitHub show in full.
- Pictures follow [ADR-084](084-every-changelog-line-carries-its-japanese.md) as before.

## Rationale

- An announcement is read in a chat channel: a few lines say what is new, and a link serves whoever wants the rest.
- Choosing the highlights and their order is a judgment about the whole release, which no single pull request can make.
- A limit in code keeps the summary short without anyone having to remember it.

## Consequences

- The summaries are written once per release, before it starts. Forgetting them stops the release at its first step, before anything is built or published.
- The Japanese of each changelog line is no longer written. The post is still both languages.
- The folder for a released version keeps its two summaries beside its media.

## Alternatives considered

- **Keep every line and cut at a length.** Rejected: the cut falls wherever the limit lands, not after the important lines.
- **Build the summary from the first lines of the changelog.** Rejected: the changelog is ordered by kind (added, changed, fixed), not by importance, and its lines are long.
