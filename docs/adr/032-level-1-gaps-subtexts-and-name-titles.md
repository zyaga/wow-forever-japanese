# ADR-032: Spellbook subtexts as fingerprint rows; menus whose title is a name

- **Status:** Accepted. Implemented in `pipeline/wfj/io/client_tables.py` (Spell
  `NameSubtext_lang`), `io/wago.py` (`read_subtexts`), `cmd/import_.py` / `cmd/import_english.py` (`wago-ui
  --subtexts`), `core/model.py` (`UI_KEY_RE`), `emit/schema.py`, the `Makefile` (`import-client`),
  `pipeline/ui_keys.txt`; `addon/WoWForeverJapanese/Core/UIStrings.lua` (`isFingerprintKey`), `Main.lua`,
  `UI/SpellBook.lua`, `UI/Menus.lua` (`titleIsName`). Partly checked in game on Forever: the spellbook subtexts show
  Japanese, and `C_Minimap.GetTrackingInfo(1).name` = "Auctioneer", the `MINIMAP_TRACKING_AUCTIONEER` English; the
  rest of the level-1 checklist in [Testing strategy](../testing/strategy.md) is pending.
- **Date:** 2026-09-19

## Context

An in-game pass on Forever with a fresh level-1 character found English in two places that need a design decision:

- **Spellbook subtexts.** "Racial", "Racial Passive", "Summon", "Tier 1" are not GlobalStrings. They are the Spell
  DB2's `NameSubtext_lang` (field 0), which the pipeline never extracted. The spellbook reads them from
  `C_SpellBook.GetSpellBookItemInfo` / `spell:GetSpellSubtext()` and writes `item.SubName`
  (`blizzard_playerspells/spellbook/blizzard_spellbookitem.lua:87, 187–199, 295–301`). On visible spells there are
  2,718 non-empty subtexts but only 36 distinct strings; many are names (pet families "Cat", "Bear", "Turtle"; forms)
  and 59 are test rows (`QASpell`).
- **Menus titled by a name.** A unit's right-click menu (`MENU_UNIT_<which>`) and a chat channel's context menu
  (`MENU_CHAT_FRAME_CHANNEL`) put the unit's or the channel's name first, as a title
  (`blizzard_unitpopupshared/unitpopupshared.lua:110–116`, `blizzard_chatframebase/shared/chatframeutil.lua:697–722`).
  `UI/Menus.lua` matches every element's text against the tag's `only` keys (ADR-031). A player named "Duel" or a
  channel named "Trade" would match `DUEL` / `TRADE` and show Japanese: a name replaced ([principle 2](../architecture/principles.md#2-names-stay-in-english)).

## Decision

1. **`SpellSubtext:<spellID>` is a UI fingerprint key family**, the pattern of `ItemSubClass:` and
   `SpellItemEnchantment:` (ADR-015, ADR-016).
   - `client_tables` extracts Spell `NameSubtext_lang` (field 0); `wago.read_subtexts` turns `Spell.csv` into
     `{ "SpellSubtext:<ID>": subtext }`; `wfj import english wago-ui --subtexts Spell.csv` adds it to the table the key
     list is resolved against. `make import-client` passes `$(CLIENT_SPELL)`.
   - `pipeline/ui_keys.txt` lists **one representative spell id per distinct prose subtext**: 12 keys (Racial, Racial
     Passive, Summon, Shapeshift, Tier 1–4, Level 1–4). Pet families, form names and `QASpell` are never listed; a
     pytest (`test_ui_spell_subtexts.py`) asserts the listed English is exactly those 12.
   - The addon has no client string for these keys, so it matches the live subtext by its `h1`
     (`UIStrings.isFingerprintKey`, used by `UIStrings.build` and `Main.lua`'s `uiEnglish`). Every spell whose subtext
     is "Racial Passive" shows the one Japanese. `UI/SpellBook.lua` adds the 12 keys to its subtext `only` set.
2. **A `Menus.TAGS` entry can set `titleIsName`.** For such a tag, `Menus.onMenu` leaves the root description's first
   element (the title the generator creates first) without our initializer, and `Menus.showElement` never matches an
   element whose text equals `contextData.name`. The eight level-1 unit tags and `MENU_CHAT_FRAME_CHANNEL` set it; it
   defaults off, so every earlier tag behaves as before.

## Consequences

- One key per English, not per spell: 12 dictionary rows cover every spell with those subtexts, on every class. A new
  prose subtext Blizzard adds stays English until one of its spell ids is listed.
- The key is still a game id: a translator edits `SpellSubtext:5227`, and the `h1` match is a lookup, not a
  key. If the spell a key names is removed from a build, its English goes missing and the import fails loudly
  (a listed key the tables do not have fails `wago-ui`); the fix is to pick another spell with the same subtext.
- The Spell table read gains a column; every other extracted table is byte-identical. `Spell.csv` for Forever is
  re-extracted.
- `titleIsName` relies on the generator creating the title first and on `contextData.name` being the name shown. A
  unit menu whose title is created later, or whose name differs from `contextData.name`, would fall back to the
  `only` match; the in-game check covers self, an NPC target and another player.
- Unit menus run our initializer next to the protected Set Focus. `AddInitializer` only writes text; no
  `ADDON_ACTION_BLOCKED` is an in-game check, not a proven property.
- The minimap tracking tag matches `C_Minimap.GetTrackingInfo(i).name` against `MINIMAP_TRACKING_*` by English. That
  the API name equals the GlobalStrings text held in game for the first tracking type ("Auctioneer"); an unequal name
  stays English.

## Alternatives considered

- **A per-spell `subtext` field on spell rows**: rejected. About 160 rows for 12 distinct strings, a second lookup
  path in the spell data, and shared-English consistency to police across spells. The fingerprint family reuses
  `ItemSubClass:`'s path.
- **List every non-empty subtext and let `only` filter**: rejected. The name subtexts would enter the dictionary; the
  key list is where the name policy is decided.
- **Skip the title by matching it against `contextData.name` only**: rejected as the sole guard. A title whose text
  differs from `contextData.name` but equals a dictionary word would slip through; skipping the first root element
  does not depend on the text. Both guards run.
- **Skip every title element**: rejected. The unit menus' section headers (`UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_*`)
  are prose and must translate.

## Decided separately

Two more level-1 gaps are decided in [ADR-033](033-level-1-gaps-name-list-tails-and-untagged-menus.md):

- **Name-list tails** (Languages, Armor Proficiency): a trailing `$?sNNN[\r\n$@spellnameNNN][]` chain is peeled as
  live names and the head aligned (the `$T` placeholder).
- **The untagged-menu hook** for Settings and Edit Mode dropdowns: a post-hook on each dropdown's `RegisterMenu`.

## Related

- [ADR-015: UI text surfaces](015-ui-text-surfaces.md): fingerprint-matched rows
- [ADR-016: whole-window interface coverage](016-whole-window-interface-coverage.md): `SpellItemEnchantment:`
- [ADR-021: client tables from the local archive](021-client-tables-from-the-local-archive.md)
- [ADR-031: objective lines, menus and HelpTips](031-objective-lines-menus-and-helptips.md): `Menus.TAGS`
- [Data model](../architecture/data-model.md) ·
  [Addon modules](../architecture/addon-modules.md) · [Pipeline](../systems/pipeline.md)
