# ADR-042: Client-table text as `ui` fingerprint families

- **Status:** Accepted. Implemented in `pipeline/wfj/io/client_tables.py` (`_TEXT_TABLES`), `pipeline/wfj/io/wago.py` (`TEXT_FAMILIES`, `FAMILY_TABLES`, `INTERNAL_TEXT`, `read_family`,
  `read_families`), `pipeline/wfj/core/model.py` (`UI_FAMILIES`, `UI_KEY_RE`), `pipeline/wfj/cmd/import_english.py`
  (`wago-ui --families`), `pipeline/wfj/cmd/served.py` (`UI_TABLES`), `Makefile` (`FAMILY_CLIENTS`, `FAMILY_TABLES`),
  the client-table blocks of `pipeline/ui_keys.txt`, `addon/WoWForeverJapanese/Core/UIStrings.lua` (fingerprint
  prefixes, synonyms, `isSlottedKey`, `matchSlots`, `familyArg`, `byRestricted`, `restrictedKeys`, `isNumberedKey`,
  `matchNumbers`), `Core/UIStringKeys.lua` (`FAMILY_KINDS`), `UI/Labels.lua` (`families`, `familiesWith`,
  `scrolling`), `pipeline/wfj/io/wago.py` (`read_item_subclass_names`), `pipeline/wfj/core/model.py`
  (`RESTRICTED_FAMILIES`, `ui_family`), `pipeline/wfj/core/numbered.py`, `pipeline/wfj/cmd/generate.py` /
  `validate.py`, `UI/Widgets.lua` and the surfaces listed in decisions 7 and 9. Evidence:
  [client-table text research](../research/2026-09-26-client-table-text.md) (and its [second round](../research/2026-09-26-client-table-text.md#second-round-other-client-table-and-server-text)).
- **Date:** 2026-09-26

## Context

A fully translated Forever client still showed English wherever the text comes from a client DB2 table the pipeline
never read: the reputation panel's faction description, achievement titles / descriptions / rewards and categories,
emote chat lines ("Bob waves at you."), holiday descriptions, skill and currency descriptions, and the category words:
the unit tooltip's creature type ("Level 10 Humanoid"), a debuff's type ("Curse"), quest-log sort headers, skill,
achievement and currency category headers.

The research measured every candidate table on both installed clients (Classic Era 1.15.9.69722, Forever
1.60.1.70009) and found each one's Forever display site. Twelve tables hold text a Forever player is shown and that is
not a name; the rest are names, internal, or never shown on Forever
([research](../research/2026-09-26-client-table-text.md#measurement)).

The `ui` type already carries text with no GlobalString: item subclasses, enchantment stat lines and spellbook
subtexts are *fingerprint* rows: the addon ships the Japanese and the h1 of the English, and matches the live line by
its hash ([ADR-014](014-machine-drafted-text-and-ui-dictionary.md), [ADR-016](016-whole-window-interface-coverage.md),
[ADR-032](032-level-1-gaps-subtexts-and-name-titles.md)).

Three shapes do not fit a plain fingerprint row:

- **The same English in two places.** "Epic" is a QuestSort word and a GlobalString (`ITEM_QUALITY4_DESC`); "Totem"
  is a CreatureType and an item subclass (`ItemSubClass:4:9`). A widget restricted to one family (`matchOnly`) must still find the word
  when the index filed its hash under the other key.
- **Emote lines carry names.** An emote's text is `%s waves at %s.`; the chat line has the sender, the player and
  the target filled in. No English may be shipped ([principle 4](../architecture/principles.md#4-the-addon-never-ships-stored-english)), so the line cannot be matched by a stored template.
- **Category words inside shipped templates.** The creature type sits in the unit level templates
  (`TOOLTIP_UNIT_LEVEL_TYPE`, `UNIT_TYPE_LEVEL_TEMPLATE`, …) and the holiday description in
  `CALENDAR_HOLIDAYFRAME_BEGINSENDS`. The same slots hold a race, a class, a spec or a pet-family name, which must stay
  English.

**More client-table text.** The auction house's category words, the barber shop's categories, options,
choices and lock text, the PvP scoreboard's stat columns, the group finder's categories and activity groups, the UI
widgets' status lines and the wardrobe's set variant words all come from client tables. Two more shapes turned up:

- **One English, two meanings.** In the barber shop "Close" is a tusk style and "Back" an option, where the same
  English on a button is the verb; fingerprint synonyms would force one Japanese per English across families and
  global strings.
- **Widget lines carry live numbers.** `UiWidgetStringSource` lines hold world-state tokens (`Towers Controlled:
  %2327w`) the client replaces with numbers, so neither the English nor its hash ever equals the line.

## Decision

1. **Fold client-table text into the `ui` type as fingerprint families**, not a new data type per table. Fourteen
   families keyed `<Family>:<row id>` (`io/wago.TEXT_FAMILIES`: family → table, text column; `core/model.UI_FAMILIES`
   repeats the names because core does not import io, and a test keeps them equal): `FactionDescription`,
   `AchievementTitle`, `AchievementDescription`, `AchievementReward`, `AchievementCategory`, `SkillLineDescription`,
   `SkillCategory`, `EmoteText`, `HolidayDescription`, `CurrencyDescription`, `CurrencyCategory`, `DispelType`,
   `CreatureType`, `QuestSort`. One reader (`read_family`) serves every family; developer text (`INTERNAL_TEXT`:
   `[DNT]`, `[PH]`, `REUSE`, `(hidden)`, `Do Not Display`, a bare `OLD` / `Unused` / `Hidden` / `x`, `OBSOLETE`, a bare
   `NewItem`; a bare `None` is read, as the barber shop's "None" choice) is never read. The curated client-table blocks
   of `pipeline/ui_keys.txt` list one key per distinct English per family (the fingerprint covers every id with that
   English). Names are never listed, nor developer rows, `Rank N` titles or dispel types the client never shows.
2. **Import from Forever only.** `wago-ui --families <client folder>` reads the family CSVs from a client folder; the
   Makefile passes it only for `FAMILY_CLIENTS := forever` ([ADR-034](034-forever-is-the-only-target.md)), and
   `client-preflight` stamp-checks the `FAMILY_TABLES` CSVs before any import step writes. `served.UI_TABLES`
   includes them, so a key no Forever table stamps is dropped as before.
3. **Column maps verified per build** ([ADR-027](027-column-maps-verified-per-build.md)). Every table is text-only (the
   row id and leading string fields; a name column is declared unwritten and never imported). Classic Era's layout
   against wago.tools 1.15.9.69722: 0 rows differ on the tables Era ships rows for; Forever against wago
   1.60.1.70009: 0 rows differ on all of them; `dev/verify_columns` Forever ↔ Era per table (figures in the research
   doc and each `Layout.verified`).
4. **A restricted index per family**, not fingerprint synonyms. Synonyms (keys that share one English, with each other
   or with a GlobalString, answered by one key) would give one English one Japanese everywhere. Instead the addon
   keeps a separate index of the restricted families' rows: `byRestricted[h1]` lists every restricted
   key with that hash, whatever its family, and `Index:restrictedKeys(text)` returns that list. `matchOnly` checks
   the restricted keys its set names before any other match, and `familyArg` takes the first key of the asked
   family. Each restricted family is therefore a vocabulary of its own: "Close" is 閉じる on a button and 寄せ as a
   barber tusk style; "Back" is 戻る on a button and 背中 as a barber option. Ambiguity (one English, two Japanese,
   shown by neither) is checked only within one family, both in the addon's build and in `validate`, which groups
   `ui` lines by family and English (`core/model.RESTRICTED_FAMILIES`, `ui_family`). Open keys, slotted and numbered
   rows keep `index.synonyms` as before.
5. **Slotted rows for emotes.** `EmoteText:<id>` rows keep the `%s` slots (positional `%N$s` in the Japanese when the
   order changes) and ship only the Japanese and the h1 of the English template. `index:matchSlots(text, names)`
   rebuilds the template from the live line: every whole-word occurrence of a known name (the sender, with a chat
   flag such as `<Away>` before it; the player; the target) becomes `%s`; if that skeleton's hash is not a slotted
   row, one more run of 1–4 words (`SLOT_WORDS`) not overlapping a known name becomes a slot too (a third player's
   target). A skeleton whose hash is a row's h1 is that row; the names fill the Japanese exactly as the line wrote them
   (the sender's link kept). No English is shipped; a line whose names cannot be isolated stays English.
6. **Family-restricted argument kinds.** New argument kinds `creatureType` and `holidayDescription`
   (`UIStrings.FAMILY_KINDS`) show a captured value in Japanese only when it is a row of that one family
   (`index:familyArg`, through the restricted index), else as written. The unit level templates' creature slot takes
   `creatureType`; a race slot (`TOOLTIP_UNIT_LEVEL_RACE`, `_RACE_TYPE`) stays `text`, because "Undead" is both a
   creature type and a race, and a player's unit tooltip never takes the `UNIT_TYPE_*` templates (`UI/TooltipUnit`
   asks `C_PlayerInfo.GUIDIsPlayer` of the tooltip data's guid), so an Undead player's race stays English; `CALENDAR_HOLIDAYFRAME_BEGINSENDS` argument 1 takes `holidayDescription`.
   The barber shop adds `customizationChoice` (`CHARACTER_CUSTOMIZATION_CHOICE_TOOLTIP` argument 2, "3: Brown") and
   `customizationSource` (`BARBERSHOP_CUSTOMIZATION_SOURCE_FORMAT` argument 1, "Source: See colors").
7. **Each surface is restricted to its families** (`Labels.families(...)` / `Labels.familiesWith(keys, ...)` build the
   `only` set from the shipped rows): Reputation, Skills and Currency description panes (`SetDescription` hooks; the
   panes left `NEVER_TOUCH`), Skills list headers, Currency headers and the entry tooltip's description, the
   achievement window (rows, categories, statistics, comparison, summary, meta criteria), the Legacy window's
   challenge cards, category list and shield reward tooltip, the Statistics tab (new `UI/Statistics.lua`), quest-log
   headers (`QuestSort` only, so a zone header is never touched), the tracker's achievement block header and the
   achievement toast (`AchievementTitle` only), and `CHAT_MSG_TEXT_EMOTE` lines. The aura tooltip's dispel word is
   asked for on the right side of line 1 (never a name there): `UI/Tooltip` matches it against `DispelType` only.

8. **The families are restricted** (`UIStrings.isRestrictedKey`, every client-table prefix): the open match
   (`index:match`, `exactKey`) never returns a family row; only `matchOnly` with a set that names the family, or a
   family argument kind, finds one (`Index:restrictedKeys`). A family's English can also be an item's or a spell's
   name ("Journeyman Engineer" is an achievement and a spell, "Poison" a dispel type and a spell), and an open match
   on a tooltip or label would replace that name ([principle 2](../architecture/principles.md#2-names-stay-in-english)). The collisions are listed and tested
   (`tests/python/test_ui_keys.py`). `SpellSubtext` ([ADR-032](032-level-1-gaps-subtexts-and-name-titles.md)) and
   the older families stay open.

9. **More families.** `ItemSubClassName:<classID>:<subClassID>`: the
   long name `GetItemSubClassInfo` returns, `ItemSubClass.VerboseName_lang`, else the short `DisplayName_lang`
   (`wago.read_item_subclass_names`; recipe / profession subclasses are skill names, never listed);
   `CustomizationCategory`, `CustomizationOption`, `CustomizationChoice` (choices that are only a name, such as
   "Alexstrasza", "Brewfest", "Samson", left out), `CustomizationSource`; `PvpColumn` / `PvpColumnTooltip`
   (`PVPScoreboardColumnHeader`, optional: Forever only); `LfgCategory`, `LfgActivityGroup`, `LfgActivity` ("Custom";
   dungeon, raid and zone names left out); `WidgetText` (numbered rows, decision 10); `ItemNameDescription` (the
   wardrobe set variant colours), plus three barber-shop GlobalStrings. Surfaces, each
   restricted to its families: the auction house's category buttons (its `CATEGORY` keys, the `INVTYPE_*` slot
   words and `ItemSubClassName`); the barber shop's option labels (`CustomizationOption`) and choice names
   (`CustomizationChoice` + "-Select-"), post-hooked on the `Blizzard_CustomizationUI` mixins before any pooled frame
   is made, and its tooltip (the category, option and choice families with the two argument kinds); the PvP
   scoreboard's column headers (`PvpColumn`) and their tooltips (`PvpColumn`, `PvpColumnTooltip`); the group finder's
   category buttons (`LfgCategory`), activity group and activity names (`LfgActivityGroup`, `LfgActivity`; the name
   button re-sized to the Japanese) and the browse row's activity name; the wardrobe's variant dropdown
   (`ItemNameDescription`, post-hooked on its `SetText`); and the UI widgets (`UI/Widgets.lua`, surface
   `widgets`: every `UIWidgetContainer`'s `ProcessWidget` post-hooked through
   `UIWidgetManager.OnWidgetContainerRegistered` and the already registered containers, the widget frame's
   FontStrings three levels down shown against `WidgetText` only). Dispositions: `blizzard_uiwidgets` → surface
   `widgets`; `blizzard_generictraitui` → `unreachable` (no Forever opener; `TraitTree` has no text column).
10. **Numbered rows** (`WidgetText`). No English ships, so both sides hash a skeleton: the pipeline replaces every
    world-state token (`%<id>w`) and every digit run of the English with `#` (`core/numbered.skeleton`), the addon
    every digit run of the live line after dropping colour codes and textures (`index:matchNumbers`). The skeleton's
    hash is the row's h1. The Japanese keeps the tokens in `data/`; `generate` writes each as `%<k>$s`, k the token's
    place among the English's number runs (a literal digit counts, so a token after it keeps its place), and refuses
    a token the English lacks. The addon fills slot k with the k-th number of the live line.

## Consequences

- More client tables go through `make tables-extract`, the preflight stamp check and `make import`; a new
  Forever build that changes one of their layouts stops the extract until its map is re-verified (ADR-027).
- Adding a family is a line in `TEXT_FAMILIES`, `UI_FAMILIES` and the addon's fingerprint prefix list: no new reader,
  data type, schema or generator.
- Emote matching costs a bounded search per emote line (known-name skeleton, then up to four words per start
  position, one hash each). A line with a target the addon cannot isolate (more than four words, or two unknown
  names) stays English.
- A creature type or holiday description reaches the screen in Japanese through templates that were verbatim before;
  every other value in those slots (a race, an Undead player's "Undead" included; a class; a pet family) renders
  exactly as before.
- Client behaviour not in the FrameXML dump (the aura tooltip's dispel line is drawn C-side; whether the achievement
  window and the calendar holiday frame ever open on Forever) is on the in-game checklist, not asserted.
- Other client-table text has nothing to translate on Forever: mount and pet journal source / lore text is empty on
  every row, Chromie Time, splash screen and party pose tables have 0 rows, the generic trait tree is unreachable,
  and Legacy reward names are names ([research](../research/2026-09-26-client-table-text.md#second-round-other-client-table-and-server-text)).
- A restricted family may translate an English differently from a button or another family; a mistake shows only
  where that family's widget shows it. Two keys of one family with one English and different Japanese are still
  `ambiguous` and dropped.
- A numbered row is found only when the live line has as many digit runs as the English has number runs; a line
  whose client text adds a number of its own stays English.

## Alternatives considered

- **A new data type per table (or one `table` type)**: a new schema, generator, emitter and addon index for text the
  `ui` fingerprint path already carries; every widget already reads `ui` through `Labels`. Rejected.
- **Shipping the English emote templates and compiling them like GlobalStrings**: ships stored game English
  (English is only ever the live client's). Rejected; the slotted fingerprint needs only the hash.
- **`entryOrText` for the creature-type and holiday slots**: `entryOrText` shows any
  dictionary entry, and the same slots carry class, spec and pet-family names that are also dictionary words
  elsewhere; those would turn Japanese, and names stay English. A kind bound to one family cannot.
- **Unrestricted matching on the new surfaces**: a pane or header that can also show a name would translate a name
  that happens to equal a dictionary word. Each surface is restricted to its families.
- **Synonyms for the restricted families**: forces one Japanese per English across families and
  buttons, so a barber style "Close" would read as the verb 閉じる. Replaced by the per-family index.
- **Shipping the widget English with its tokens**: stored game English. The skeleton hash needs none.
- **Importing the families for every client**: Classic Era is an input only (ADR-034); asking every client for the
  tables would make Era's missing ones (HolidayDescriptions, CurrencyTypes, CurrencyCategory have no rows there) a
  failure for no benefit.
