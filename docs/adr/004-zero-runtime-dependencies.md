# ADR-004: Zero runtime dependencies, Blizzard API only

- **Status:** Proposed
- **Date:** 2026-09-13

## Context
The predecessor tooltip addon required Plater for nameplates and injected a Plater script; WoWJapanizer embedded Ace3. Each dependency is a moving target across client patches and a second thing to break on Forever's launch day. The addon's needs (a settings panel, a slash command, an event bus, SavedVariables, a hash function) are all small.

## Decision
The addon depends on nothing but the Blizzard API. No `## Dependencies` / `## OptionalDeps`, no embedded libraries (Ace3, LibStub, CallbackHandler, LibDataBroker…), no Plater or ElvUI integration. Small helpers (event bus, settings registry, hash) are written in-repo. The Python pipeline is stdlib-only at runtime; any new dependency needs its own ADR.

## Consequences
- Nothing upstream can break the addon on a patch; the only compatibility surface is Blizzard's, which every addon shares.
- Some conveniences are re-implemented (a few hundred lines total). Accepted.
- Dev-time tooling (pytest, luacheck, a Lua test runner) is not a runtime dependency and is allowed.

## Alternatives considered
- **Ace3**: brings config UI and profiles for free; also brings 10+ files, a global registry, and version skew.
- **Plater / nameplate integration**: moot, names are never replaced ([principle 2](../architecture/principles.md#2-names-stay-in-english)).
