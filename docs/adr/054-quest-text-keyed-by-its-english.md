# ADR-054: Quest text with no readable id is keyed by its English

- **Status:** Accepted. Implemented in `pipeline/wfj/cmd/import_english.py` (`run_wdb`, `_wdb_keyed_lines`, `_add_keyed`), `addon/WoWForeverJapanese/Main.lua` (`WFJ.IsQuestFieldEnglish`, `WFJ.ShippedGossipKey`), `UI/QuestFrame.lua` and `UI/QuestMap.lua` (`showField`, `completionLogKey`).
- **Date:** 2026-10-03
- **Amends:** [ADR-020](020-quest-cache-harvest.md) decision 11 (conditional quest text was read and reported, never imported)

## Context

The quest cache holds two kinds of quest text the addon could not show in Japanese.

- **Conditional descriptions.** Forever serves another wording of a quest's description for some classes or
  races, chosen per `PlayerCondition`. The cache carries every variant (`WdbQuest.conditional`). The quest window
  shows the variant in place of the default description, and nothing on screen says which variant it is: the
  addon would have to evaluate the condition to know.
- **The completion log line.** `GetQuestLogCompletionText` is the line the objective tracker and the quest log
  show once a quest is ready ("Speak with Deathguard Billmuth at Tyr's Watch."). The cache carries it as one of
  the record's strings; it is not a field of the quest model, and the tracker line carries no quest id the addon
  can tie it to.

ADR-020 imported neither. Players saw the English variant or completion line even when every other line of the
quest was in Japanese.

The data model keys a translation by game id. Text the server owns with no game id of its own (NPC dialogue,
trainer greetings, book pages) is keyed by the hash of its English ([ADR-005](005-gossip-key-fingerprint.md),
[principle 5](../architecture/principles.md#5-every-translation-is-keyed-by-the-game)). These two texts do belong
to a quest id, but that id is not readable where they show, or (for a variant) not enough to pick the text.

## Decision

1. **Keyed like NPC dialogue.** `import english wdb` (`run_wdb`) writes each cached quest's conditional
   descriptions and its completion log line as English type `gossip`, field `text`, keyed by the hash of the
   English (`_wdb_keyed_lines`), `src wdb@<build>`. The translation is a `gossip` line under the same key.
2. **Additive.** `_add_keyed` adds only keys that are new. A key another source already has (VMaNGOS, the
   collector, an earlier cache) keeps its line. A key whose existing line holds other English ends the run
   (`wdb: gossip hash K names two texts: …`), so a collision is never resolved silently.
3. **The addon finds the line by its live text.**
   - `WFJ.ShippedGossipKey(text)` (`Main.lua`) returns the first of `Collector.keys(text, player)` that has a
     shipped `gossip` row, or nil. It is memoized per text, because the tracker asks every frame.
   - `WFJ.IsQuestFieldEnglish(id, field, text)` (`Main.lua`) is true when a fingerprint of the live text equals
     the quest entry's `h1` or `h1f` for that field.
   - In the quest window (`UI/QuestFrame.lua`) and the quest map's details pane and popup (`UI/QuestMap.lua`,
     `showField`), a description is shown from its keyed row only when the live text is not the quest's own
     description and a keyed row exists. The quest's own description keeps its quest-id row and live check.
   - A variant is never recorded by the collector as the quest's description: other characters see the quest's
     own wording, and recording the variant would make the quest's English look changed.
   - A tracker or quest log line that no objective or area row answers falls back to its keyed text
     (`completionLogKey` in `UI/QuestMap.lua`), before the UI objective templates.
4. **A logged exception.** This is an exception to the rule that only text with no game id is keyed by the hash of
   its English, approved by the maintainer on 2026-10-03. It covers these two texts from the quest cache only.

## Consequences

- A character that gets a class or race wording of a quest sees it in Japanese, and the tracker and quest log
  show the completion line in Japanese once the quest is ready.
- The `gossip` type now holds quest-cache text beside NPC dialogue. Such a line has no `npcs` and its `src` is
  `wdb@<build>`; the quest cache's served-text disposition (`wdb-questcache.*`) names it.
- A keyed line has no quest id, so it gets no quest stale marker. When Forever rewords a variant, the new English
  is a new key with no Japanese; the old line stays in the data and never matches again.
- Two quests whose variant or completion line is the same English share one line and one translation. That is
  the same trade NPC dialogue already makes.
- The description check costs one fingerprint pass per shown description, and the keyed lookup is memoized, so
  the tracker's per-frame calls do not repeat the work.

## Alternatives considered

- **Key a variant by `(quest, condition)`.** Rejected: the addon cannot evaluate a `PlayerCondition`, so it could
  not tell which variant it is looking at.
- **Add a completion-log field to the quest model.** Rejected: the tracker line carries no quest id the addon can
  read reliably, so a quest-id field would still need a text lookup to find.
- **Leave both in English.** Rejected: every other line of the quest is in Japanese, and the English line stands
  out in the window players read most.

## Related

- [ADR-005: One text primitive for gossip keys](005-gossip-key-fingerprint.md) · [ADR-020: Blizzard's cached quest text](020-quest-cache-harvest.md) · [ADR-029: camelot targets the mainline family](029-camelot-targets-the-mainline-family.md)
- [Pipeline](../systems/pipeline.md): `import english wdb` · [Data model](../architecture/data-model.md): gossip · [Addon modules](../architecture/addon-modules.md): `Main`, `UI/QuestFrame`, `UI/QuestMap`
