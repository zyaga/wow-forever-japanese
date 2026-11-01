# ADR-068: The Forever quest cache is pinned apart from the tables

- **Status:** Accepted
- **Date:** 2026-10-29
- **Related:** [ADR-020](020-quest-cache-harvest.md) (the quest cache harvest) · [ADR-021](021-client-tables-from-the-local-archive.md) (the client tables from the local archive) · [ADR-050](050-english-is-additive.md) (English is additive) · [Pipeline](../systems/pipeline.md)

## Context

A Forever re-pull has two halves with different needs. The client tables (ItemSparse, SpellName, QuestV2, GlobalStrings and the rest) come from the installed client and its hotfix cache: they need only the install. The quest cache (`questcache.wdb`, ADR-020) needs the quest scan, which needs the maintainer logged in to the game.

Until now one pin, `forever_BUILD`, named both. A build's folder under `predecessors/clients/` held its tables and its quest cache, and every step that read the cache read it from `forever_BUILD`'s folder. A build could not ship until its scan had run.

A pre-launch Forever build, 1.60.1.70685, could be installed but not played. Its tables reword spells, items and interface lines players would see on the first day; holding them until the scan meant shipping that text after launch.

## Decision

1. **A second pin for the quest cache.** The Makefile has `forever_QUEST_BUILD`, the build whose quest cache `data/` holds when it is older than the tables. `quest_build` gives the quest pin of a client (its `_QUEST_BUILD`, else its `_BUILD`) and `quest_dir` that build's folder. Classic Era has no quest pin, so its cache stays with its tables.

2. **Every reader of the quest cache follows the quest pin.**
   - The wdb import and its preflight (`WDB_QUEST`, `WDB_BUILD`).
   - `wdb-copy`: it copies into the quest pin's folder, and its build guard compares the cache's header with the quest pin.
   - The served step: `--cache-build` names the cache's build. It accepts a cache that matches that pin and is not newer than the tables. With an older cache, only QuestV2 counts as served by the tables' build; the ids only that cache answered were recorded when their own build was pulled (ADR-050).
   - The voice speaker and level steps (`voice-speakers`, `voice-levels`).
   - `scan-install`: the scan plan is the quest pin's build, so WFJScan starts by itself on every newer build.
   - The private build alert: it compares the installed build with the quest pin, so tables pulled before the scan still wait for it.

3. **A build's tables ship before its scan.** On a new build whose tables ship before its scan, `forever_BUILD` moves and `forever_QUEST_BUILD` is set to the last scanned build; otherwise the line is absent and the quest pin is `forever_BUILD`. After the scan, the quest re-pull deletes the `forever_QUEST_BUILD` line before `wdb-copy`, and the tables are pulled again with the play session's hotfix cache.

## Consequences

- A build's table text (items, spells, interface lines) can reach players as soon as the client is installed. Quest text follows when the scan has run.
- Between the two halves, `make import-english` must not run. It runs Classic Era's import first and lets Forever's override it, and the hotfix cache a client writes at the login screen lacks the rows only a play session's hotfixes carry. On 1.60.1.70685 a full import replaced the previous build's Forever English of 185 item descriptions with Classic Era's, and 182 shipped lines went stale; it was not kept. Only Forever's table steps run until the scan (`make import-tables CLIENT=forever`: `wago-ids`, `client-text` and `wago-ui`, with Forever's tables). `make import`, `make import-english`, `make rebuild-check` and Forever's `make import-client` refuse while `forever_QUEST_BUILD` is set, so the full import cannot run by mistake between the two halves.
- When the two pins differ, a quest the new build stopped serving keeps its English, as ADR-050 already decides; the served record does not mark the new build as serving quests only the older cache answered.
- One more pin to move on each re-pull. A quest pin left behind is visible: the build alert keeps asking for the scan.

## Alternatives considered

- **Hold the PR until the scan.** The build's text would have missed launch, since the scan could not run before it.
- **Run `scan-install` by hand from an older checkout each time.** It works once, but it depends on someone remembering which checkout holds the older pin, and the build alert would still compare against the tables' build.
