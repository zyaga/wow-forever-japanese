# ADR-084: Every changelog line carries its Japanese, and pictures only for features worth showing

- **Status:** Superseded in part by [ADR-085](085-the-release-post-is-a-short-summary.md): the post is a short summary written for the release, so a changelog line no longer carries its Japanese. The picture rule stands.
- **Date:** 2026-11-12
- **Deciders:** the maintainer
- **Related:** [ADR-046](046-one-action-release.md) (one-action release, the changelog gate) · [ADR-072](072-the-release-announces-itself-in-discord.md) (the Discord post and its media folder) · [Release](../operations/release.md) · [Release media](../releases/README.md)

## Context

The release post has an English card built from the changelog and a Japanese card built from `docs/releases/next/ja.md`, with the pictures in the same folder ([ADR-072](072-the-release-announces-itself-in-discord.md)). Nothing made anyone write `ja.md` or put a picture there. A release with neither still went out green, with a notice: an English-only post, the opposite of the project's rule that player-facing text is in both languages. Before the release after 0.10.1, several pull requests had merged with changelog lines and a gallery card had been made, and `next/` did not exist.

Pictures are a different question. Most changes (data, fixes, wording) have nothing worth a picture, so a rule that every new feature line needs one would be wrong more often than right.

## Decision

- The pull-request Changelog check fails when a pull request adds or rewords a line under `## Unreleased` and does not change `docs/releases/next/ja.md`. The Japanese is written in the same pull request as the English.
- The release's plan step (`wfj release next-version`) refuses an addon release while `ja.md` is missing or empty, before anything is built or published. The Discord preview still runs without it, so the gap can be seen.
- Whether a change gets a picture is decided when the work is planned, not by CI. A feature worth showing off adds its CurseForge gallery card to `next/` in the same pull request; review treats a missing one as a blocker. Everything else adds no picture.

## Rationale

- A check in code holds for every pull request, from any author; a habit holds only when someone remembers it.
- Writing the Japanese next to the English line is cheaper than writing a whole release's worth at release time, and it is reviewed with the change it describes.
- A picture is a judgment about what players will want to see, which a pattern on changelog lines cannot make.

## Consequences

- A pull request with a changelog line touches two files for its release note. An outside contributor who cannot write Japanese says so in the pull request and the maintainer adds it on the branch.
- Taking a line out of `## Unreleased` needs no Japanese change; its Japanese is taken out of `ja.md` by hand.
- A release can still post without pictures; it can no longer post without Japanese.

## Alternatives considered

- **A picture for every `### Added` line.** Rejected: most added lines are data or small things with nothing to show.
- **Write `ja.md` at release time.** Rejected: that is what was being forgotten.
