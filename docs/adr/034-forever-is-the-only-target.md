# ADR-034: Forever is the only target; Classic Era is an input

- **Status:** Accepted. `UI/Guild.lua`, `UI/Honor.lua`, `UI/QuestLog.lua` and `UI/Camelot.lua` deleted; the Era-only
  names and branches removed from the shared surface files, and the client-detection guards removed (`Main.lua`, the
  TOC, `UI/*.lua`); `UI/Tooltip.lua` (one hook path), `UI/Trainer.lua`
  (no greeting), `UI/Bags.lua` (7 container frames), `UI/ItemText.lua` (Forever's book writer); `Core/Data.lua`,
  `Core/Lookup.lua` (no `trainer_greeting`); `pipeline/wfj/cmd/served.py`, `cmd/check.py` (baseline kept),
  `cmd/import_.py`, `cmd/import_english.py`, `io/vmangos.py`, `emit/schema.py`, `emit/lua_writer.py`,
  `dev/ui_inventory.py` (Forever only), the `Makefile` (`import-served`, `ui-inventory`); `pipeline/ui_inventory.txt`
  (the Forever inventory, renamed), `pipeline/ui_keys.txt`, `pipeline/ui_exclusions.txt`; `data/english/` pruned,
  `data/trainer_greeting/` and `data/english/trainer_greeting/` deleted, `addon/WoWForeverJapanese/Data/` regenerated;
  `tests/python/test_forever_only.py`, `tests/python/test_import_served.py`.
- **Date:** 2026-09-22
- **Supersedes in part:** [ADR-025](025-guarded-surface-init-and-runtime-tooltip-path.md) (the Classic tooltip path),
  [ADR-029](029-camelot-targets-the-mainline-family.md) (one surface file serving both clients) and
  [ADR-030](030-every-window-the-forever-client-loads.md) (the camelot marker and its gates).
  **Amends:** [ADR-022](022-book-and-trainer-greeting-surfaces.md) and
  [ADR-023](023-server-only-text-drafted-in-measured-batches.md) (the trainer greeting kind is removed).

## Context

Classic Era was the foundation. The addon was first written against the Classic Era client (1.15.9), and when the
Forever client arrived (game type `camelot`, a member of the mainline family, ADR-029) the surfaces were extended to
serve both: `Compat` candidate lists named the Era global first and the camelot name after, 33 surfaces checked a
"this is Forever" marker (`UI/Camelot.lua`, ADR-030), 11 files guarded on `GuildFrame`, 4 on `WorldMapConstants`, and
the tooltip carried two hook paths chosen at runtime (ADR-025). Four whole files served only Era (`UI/Guild.lua`,
`UI/Honor.lua`, `UI/QuestLog.lua`, and the marker itself).

The addon ships on Forever only. Its Era side was never published, is not tested in game, and doubles the code a
reader of each surface file has to hold, while the docs and checklists promised that Classic Era keeps working.

Classic Era is still the main **input**. Its quest cache, its client tables (the union import,
`CLIENTS := classic-era forever`, ADR-020 / ADR-021), pfQuest and VMaNGOS supply most of the English. Under the union
merge that also puts English into `data/english` for ids the Forever client does not have, and `generate` ships every
checked line whatever client its English came from, so the download carried Japanese for 629 quests, 263 items and
32 spells Forever never shows, plus 17 UI keys only Era's tables define.

Forever's trainer UI has no greeting widget and no `GetTrainerGreetingText`, so the `trainer_greeting` kind (24
machine lines, ADR-022 / ADR-023) had no consumer on the target client.

## Decision

1. **Forever is the only target; Classic Era is an input, never a target.** The Era quest cache, the Era client
   tables in the union import, `wago-fetch`, pfQuest and VMaNGOS all stay. Nothing in the addon, the tests, the
   inventory or the checklists exists to support Era as a client the addon runs on.
2. **Era-only code is deleted, not flagged.** `UI/Guild.lua`, `UI/Honor.lua`, `UI/QuestLog.lua` and `UI/Camelot.lua`
   are removed. Every Era-only candidate name, hook and branch in the 18 shared surface files is removed, and the 50
   client-detection guards (the Camelot gate, `classicGuild`, `WorldMapConstants` as a gate, Macro's
   `ToggleClickBindingFrame` gate, Loot's ScrollBox check) go with them: each surface takes its Forever path
   unconditionally. A candidate list that shrinks to one name stays a list (`Compat.declare`). There is no "era mode"
   switch. Names the survey could not place on either client stay until an in-game check or the Forever dump proves
   them absent.
3. **One tooltip path.** `Tooltip.path` is `"dataprocessor"` or `"none"`. The `OnTooltipSetItem` / `OnTooltipSetSpell`
   `HookScript` path and the aura method-hook fallback are removed. The guarded init of ADR-025 stays.
4. **The download is defined by Forever's own tables, not by where the English came from.** A new step,
   `wfj import english served \<QuestV2.csv> \<questcache.wdb> \<ItemSparse.csv> \<SpellName.csv> [--map-cache WDB]...
   [--dry-run]` (`make import-served`), runs last in `make import` and `make import-english`, after every client, with
   Forever's client folder (named, not "the last client"). It prunes `data/english`:
   - quest: kept when the id is in QuestV2 or in the Forever quest cache;
   - objective (keyed by QuestObjective id): mapped to its quest through the Forever cache, then each `--map-cache`
     (Classic Era's), and kept when that quest is kept; an objective no cache maps is kept;
   - item: kept when the id is in ItemSparse; spell: kept when the id is in SpellName;
   - ui: kept when the line's English `src` is the Forever tables' stamp (`tables-source.txt`) and the key is still
     in `ui_keys.txt` (`--keys`). Under the union merge Forever wins wherever it has the key, so another stamp means
     no Forever table provides it, and a key that has left the curated list would otherwise keep English no import
     writes any more.

   Book and gossip are server text with no client table and are untouched. It refuses, before writing, on a missing
   input, CSVs with missing or mixed stamps, a cache whose build is not the tables' build, or a kind that would lose
   every line. It is idempotent.

   Filtering on "the English carries a Forever stamp" was not enough: 2,409 quests are in Forever's QuestV2 but the
   server had not answered them in the harvest yet, so their English still comes from Classic Era. They are real
   Forever quests and keep shipping.
5. **The Japanese stays in `data/`.** Only the English store is narrowed. A Japanese line whose English was pruned is
   rejected as `no_english_id` at the next `wfj check` and is not generated; when a later harvest lists the id, its
   English returns and the line ships again with no data edit. Some of these lines are irreplaceable human
   translations.
6. **`check` keeps the last English baseline of a `no_english_id` line.** Before, the line's `english` (hash + src)
   was nulled when its English disappeared, so English that came back reworded made the line look freshly checked.
   Now the baseline is kept, and reworded English makes it `stale`.
   Its variants also go in one stored order (hand-written first, the canonical `conflicts` order of ADR-012 §5), since no rule
   picks a winner without English: an incremental `check` and a full rebuild then store the same line. Readers of
   `english` on such a line, all unaffected in what ships (a rejected line never ships): `status.decide` (stale
   derivation, the intended effect), `core/report`, `import_draft --reverify`, `validate`, `lua_writer`,
   `generate`.
7. **The trainer greeting kind is removed end to end.** No addon kind or Trainer greeting code (`Trainer.init()` takes
   no arguments), no VMaNGOS greeting import, no emit / schema / check / stats entry, no `data/trainer_greeting/` or
   `data/english/trainer_greeting/`. All 24 deleted lines were `machine` provenance. The trainer window's Forever
   parts (services, training points, the train button) are unchanged.
8. **One UI inventory, Forever's.** `make ui-inventory` builds `pipeline/ui_inventory.txt` from a Forever UI extract
   and its GlobalStrings. The Era chain (`make ui-source`, the Era `ui-inventory`, `UI_SOURCE*` /
   `UI_GLOBALSTRINGS`, `ui_inventory.py --client`), `pipeline/ui_classic_only.txt`, 65 Era-only exclusions and the
   `ui_keys.txt` keys no Forever inventory has are removed, and the exclusion reasons that judged a key by the Classic Era UI source
   are re-judged against the Forever UI extract: a key no Forever file writes keeps the exclusion with a Forever
   reason, and one some Forever file does name is triaged with the menus and composites work
   ([ADR-038](038-menus-callouts-and-composite-forms.md)).

## Consequences

- Each surface file has one hook shape. `/wfj debug`'s unresolved list carries no Era names as expected misses.
- The download shrinks (about 630 quests, 260 items, 30 spells and 100 UI keys Forever never shows, and the trainer
  greetings). On Forever nothing a player sees changes.
- **Books translate on Forever.** Removing the Era shapes showed that `UI/ItemText.lua` still matched the Classic
  Era book writer, which prefixes the page with `"\n"`. Forever's `ItemTextFrameMixin:OnEvent`
  writes `ItemTextPageText:SetText(ItemTextGetText())` with no leading newline (a letter's creator suffix is
  unchanged), and sets each HTML tag's font from `ITEM_TEXT_FONTS[material]` [verified: forever 1.60.1.69913
  `blizzard_uipanels_game/mainline/itemtextframe.lua:18–31, 33–175`; `itemtextframe.xml:57–81, 163–173`]. The
  equality guard therefore never matched on Forever, and no book page was translated there. The surface guards on
  `received == ItemTextGetText()`, writes without an added newline, and applies the Japanese face per tag at its
  captured size, so headings keep their scale.
- A Forever quest the harvest has not answered still ships, on Era English. Its stale check is against that English
  until Forever's own cache answers it.
- The served sets are read from the pinned Forever client folder at import time; there is no new data artifact. A
  reimport against a folder without Forever's tables stops before writing.
- Classic Era is unsupported. The addon may still load there, but nothing checks that and no doc promises it.
- `test_forever_only.py` guards the line: Era-only names and client gates in addon code, the removed modules, the
  trainer greeting, shipped ids Forever lists (skipped without the client folder), and the target docs naming one
  client.
- Rollback: revert the PR. The pruned English returns with `make import-english` (inputs unchanged) and the trainer
  greeting data from git history. No SavedVariables change.

## Alternatives considered

- **Filter at `generate` instead of pruning the English.** Rejected: the English store would keep describing ids the
  target does not have, `check`, `stats` and the translation batches would keep counting and cutting them, and every
  consumer would need the same filter.
- **Keep only English carrying a Forever stamp.** Rejected: it drops the 2,409 QuestV2 quests the server has not
  answered yet, which are real Forever quests with good Japanese.
- **Keep Classic Era as a second target.** Rejected: never published, not tested in game, and it doubled every
  surface file, the inventory and the checklists for a client no player of this addon uses.
- **Delete the Japanese for unserved ids.** Rejected: some are human translations that cannot be regenerated, and a
  later harvest may list the id.

## Related

- [ADR-020: quest cache harvest](020-quest-cache-harvest.md) · [ADR-021: client tables from the local
  archive](021-client-tables-from-the-local-archive.md): the inputs that stay
- [Data model](../architecture/data-model.md) · [Pipeline](../systems/pipeline.md) ·
  [Addon modules](../architecture/addon-modules.md)
