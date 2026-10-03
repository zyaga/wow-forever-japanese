# WoW Forever Japanese: Glossary

> The project's domain vocabulary: the words this project's world uses, defined once.
>
> Read this first to speak the project's language. One entry per concept, the canonical term in bold. Definitions say what a thing **is**, not how it works; link the `systems/` doc for the *how*.

## Data

**Entry**:
One translatable unit addressed by a game ID and a field, e.g. quest `2` / `description`, item `117` / `description`, spell `17` / `description`. Trust, [[Provenance]], and [[Status]] are tracked **per field**, not per quest or item: a quest may ship a trusted Japanese description and an English completion text.
_Avoid_: record, row, translation (a translation is one *value* an entry may hold)
→ [Data model](architecture/data-model.md)

**Provenance**:
Who or what produced an entry's Japanese value and from which English it was made: `human` (a named translator from the WoWJapanizer / CraftJapanizer_Quest / QuestJapanizer lineage, or the community label `questjapanizer-wiki` for uncredited wiki text), `machine` ([[Machine-drafted text]]: the `model` that wrote it, optionally its [[Critic]], and the draft date), or `correction` (a [[Correction]] a person wrote). A [[Hand-written]] value is never overwritten by `machine` output. The `source` names which release the value came from (`cqjt@…`, `ctjt@…`, `qjp@0.5.8`, `cjq@2012031300`), `correction@<YYYY-MM-DD>` for a correction, or `draft-<name>@<YYYY-MM-DD>` for a machine draft. "CraftJapanizer" was never a translator: it was a label on uncredited wiki text.
_Avoid_: source (that's the English side; see [[English source]]), author
→ [Data model](architecture/data-model.md)

**Hand-written**:
A value a person wrote: [[Provenance]] `human` (an imported, named translator) or `correction` (a person wrote or replaced it here, or a review the maintainer ruled on). Hand-written always ranks ahead of [[Machine-drafted text]], and a machine variant cannot win a line that has a hand-written variant without an `accept` [[Ruling]] ([Principles §6](architecture/principles.md#6-provenance-on-every-line-people-over-machines)). A person replacing a machine line writes a [[Correction]], so the replacement is recorded as hand-written.
_Avoid_: human (one of the two classes), manual, curated
→ [Data model](architecture/data-model.md) · [ADR-014](adr/014-machine-drafted-text-and-ui-dictionary.md)

**Machine-drafted text**:
Japanese a model wrote, recorded with [[Provenance]] `machine`, the `model` id (required), an optional [[Critic]], and `source: draft-<name>@<date>`. Enters `data/` only through `wfj import draft`; carried across `make data`; ships as trusted when it passes the rules like any other value. The [[UI dictionary]] and most [[Server-only text]] are machine-drafted.
_Avoid_: AI translation, MT, auto-translation, generated text (generated means the Lua build output)
→ [Data model](architecture/data-model.md) · [ADR-014](adr/014-machine-drafted-text-and-ui-dictionary.md)

**Critic**:
The model that reviewed a [[Machine-drafted text]] before import (terminology, naturalness in a game UI, length, format specifiers, names untouched), recorded as `provenance.critic`. The critique's accepted changes are applied to the draft; the critic is not an author and not a person's review. A critique pass is chosen per batch, not required: `critic` is recorded only when a second model actually reviewed the draft.
_Avoid_: reviewer, judge, verifier
→ [ADR-014](adr/014-machine-drafted-text-and-ui-dictionary.md)

**Trusted entry**:
An entry that ships without a runtime gate. All five hold (an entry with no names and no numbers to check still passes, with `checks: []` recorded): [[Provenance]] is `human` or `correction`, or `machine` for [[Machine-drafted text]] that passes the rules; its ID exists in the [[English source]] for the same type; it passes the [[Alignment check]]; it is **complete** (not `truncated`: a first-paragraph-only translation of a multi-paragraph English text never ships); it is not in an unresolved [[Duplicate conflict]]. Distinct from a merely *present* entry in the predecessor data: presence is not trust.
_Avoid_: clean entry, good entry, verified
→ [Pipeline](systems/pipeline.md)

**Unaligned entry**:
An item or spell entry, Japanese and ID-present, that the pipeline has **no rendered English to align against offline**. The client tables hold only the [[Tooltip text]] template, without the numbers, so an item or spell entry is never trusted offline: it is checked against that template and stays unaligned while the template is unchanged (once it changes, the entry is [[Stale]]). Unaligned entries ship and are **gated at display time**: the addon runs the same name and number check (`Core/Align.lua`) against the live tooltip lines of the [[Description run]] it is about to replace, after filling any [[Value placeholder]], and leaves the English on failure. The [[Collector]] records those live lines, but that English is stored, not consulted.
_Avoid_: untrusted, unverified
→ [Addon modules](architecture/addon-modules.md) · [ADR-007](adr/007-unaligned-ships-with-runtime-gate.md)

**Value placeholder**:
A `$N<k>` or `$D<k>` token in an entry's Japanese standing for a value the game fills in at render time. `$N<k>` (`$N1`, `$N2` …) is filled with the k-th number of the [[Live English]] line in reading order. `$D<k>` is filled with the k-th **duration** phrase of that line, number and unit together, rendered in Japanese through the interface duration strings (`18秒`, `2分`): the client chooses the unit by the length, so a translation never names one ([ADR-028](adr/028-a-duration-is-copied-not-named.md)). A number the English writes before a unit word (`every 5 sec`) is a duration too. Used in item and spell tooltip text, and in quest text for a count the server substitutes (`Collect $1oa Lady's Tear Moss.` → `$N1`). On an item or spell tooltip the placeholders are filled before the [[Alignment check]] runs; on quest, gossip, book and interface lines, which were checked offline, they are filled with **no** gate (`Align.fillValues`). Either way a placeholder with no value to take leaves the English. The numbering follows the English line's reading order, so an entry numbered out of order would show correct values in the wrong slots; the gate cannot see that, and the drafting lint (`slot_missing`, `duration_as_value`, `duration_missing`) catches it. A bare `$N` or `$D` is not a placeholder. An [[Inline icon]]'s `$I<k>` is filled the same way, from the live line's icons.
_Avoid_: variable, template value, `$s1` / `$d` / `$1oa` (Blizzard's own template codes in the English, which the Japanese never carries)
→ [Addon modules](architecture/addon-modules.md) · [ADR-010](adr/010-tooltip-in-place-run-replacement.md) · [ADR-028](adr/028-a-duration-is-copied-not-named.md)

**Inline icon**:
A spell's icon the client prints inside a tooltip line where the English template says `$@spellicon<id>` (the rune and feast lines: "\<icon> Deadly Brew"). In the drafted English and the Japanese it is the placeholder **`$I<k>`**, k its order in the line; the addon fills it with the k-th texture escape (`|T…|t`) of the [[Live English]] line, byte for byte, and reads no value, name or number from an icon. That the client prints it as such an escape is not yet verified in game: a line whose live text has no escape stays English.
_Avoid_: `$I` marker, spell icon code, texture placeholder
→ [Addon modules](architecture/addon-modules.md) · [ADR-043](adr/043-included-text-icons-and-branch-variants.md)

**Player placeholder**:
A token in an entry's Japanese standing for the reader's own character: `{name}`, `{class}`, `{race}`, or an English gender word pair `<male/female>` (`<lad/lass>`). Kept literally in `data/` and the generated Lua; expanded per player when the Japanese is applied: the character name as the client returns it, class and race as the corpus's katakana words, the pair by the character's sex. Any other `{word}` is unknown: left literal in-game, counted by `/wfj debug`, and a shipped line carrying one fails `wfj validate`. Case-sensitive (`{Name}` is unknown). An emote in angle brackets (`<Sirraは…>`) is not a pair. Distinct from a [[Value placeholder]] (a number filled from the [[Live English]]) and from the placeholders `normalize_v1` puts in English before hashing.
_Avoid_: variable, macro, template tag, "placeholder" on its own (three kinds exist)
→ [Addon modules](architecture/addon-modules.md) · [Pipeline](systems/pipeline.md)

**Rejected entry**:
An entry kept in `data/` with `status: rejected` and one or more [[Reason code]]s. Never deleted: the translation phase reads rejections to know what to replace and why.
_Avoid_: dropped, deleted, filtered out

**Pending**:
An entry as `wfj import` writes it: imported, not yet checked: `status: pending`, `checks: []`, `english: null`. The only status the import writes; `wfj check` assigns every other status. A pending entry never ships.
_Avoid_: unchecked, raw, provisional
→ [Data model](architecture/data-model.md)

**Alignment check**:
The no-model test that an entry is filed under the right ID: every Latin-script name embedded in the Japanese value must occur in the [[English source]] text for the same quest (any field), and every number must occur in that same quest-wide English (numbers are checked only for fields that have their own pfQuest English). Relies on the corpus convention that names stay English (see [[Name policy]]). Runs offline for quests only; items and spells are checked at display time ([[Unaligned entry]]).
_Avoid_: validation (too broad), fuzzy match
→ [Pipeline](systems/pipeline.md)

**Reason code**:
The machine-readable reason(s) `wfj check` writes on a [[Rejected entry]]: `no_english_id` (no [[English source]] for the ID: no source has it, or the [[Served step]] dropped it because no Forever build has served the ID; the line keeps the English it was last checked against, so English that returns reworded makes it [[Stale]]), `not_japanese`, `duplicate_conflict`, `alignment_failed:<name>`, `numbers_changed:<n>`, `truncated:<ja paragraphs>/<en paragraphs>`, `specifiers_changed:<detail>` (a [[UI string]] whose Japanese does not take its English template's arguments), `ruled_reject` (the only candidate is a variant a person ruled `reject`, which would otherwise pass), `markup_changed:<detail>` (a [[UI string]] whose Japanese does not keep its English colour codes and line breaks, or carries a malformed [[Plural grammar]] group). One entry can carry several.
_Avoid_: error, failure reason
→ [Data model](architecture/data-model.md)

**Ruling**:
A person's `accept` or `reject` on one variant of a [[Duplicate conflict]], recorded on the variant as `ruling: {ruling, by, date}` and honoured by `wfj check`: a single `accept` wins the conflict, a `reject` excludes the variant; a `machine` variant wins a line that has a [[Hand-written]] variant only with an `accept`, or when every hand-written variant is ruled `reject`. It picks the variant only: the rules still decide the line's status. A `reject` is permanent: the ruled variant never ships again, even alone on its line and even when it later passes the rules. Carried across `make data` (ADR-012). With a [[Correction]], the only human input the check reads.
_Avoid_: override, manual fix
→ [Local setup → Ruling on conflicts](operations/local-setup.md)

**Correction**:
A variant of an entry written by a person, or in a review the maintainer ordered and ruled on. Typically a complete translation whose only fault is a misspelled name (quest 456: `Thistle bore` for `Thistle Boar`), a title word translated inside a name ("Marshal Haggard"), or a name written in katakana where the English keeps it in English letters (`Westfallシチュー` → `Westfall Stew`). Recorded as a variant in the line's `conflicts` with `provenance.class: correction`, a `translator` (who wrote the Japanese), `source: correction@<date>`, `corrects` (the source of the variant it fixes) and a `note`; `translator` and `corrects` are required. One per line: a second passing correction ties with the first. It still has to pass every rule, and is judged by the layer it corrects; when it passes it ranks first and ships. Carried across `make data`; a hand edit not marked `correction` is not. A candidate listed by `dev/list_name_typos` is not a correction until a person has read it against the English. A correction written from a [[Fix report]] also carries `report` (the issue number) and, when the model wrote it rather than the player, `model`.
_Avoid_: patch, override, fix-up
→ [Local setup → Hand corrections](operations/local-setup.md#hand-corrections) · [ADR-012](adr/012-human-decisions-survive-regeneration.md)

**Audit verdict**:
The judgement written on one shipped [[Hand-written]] line when it is read against its English: `match` (it says what the English says; it ships as it is), `correct` (a small defect such as a typo, a wrong particle or kanji, a translated name or a wrong number, fixed by the smallest edit and shipped as a [[Correction]]) or `redraft` (a wrong meaning, garbled text, another quest's text, or cut off: every hand-written variant is ruled `reject` and the model drafts the whole line). A `correct` or `redraft` names its problem kind. Verdicts are applied only once the maintainer approves the list.
_Avoid_: review result, grade, score
→ [Translation batches → The audit of the hand-written lines](operations/translation-batches.md#the-audit-of-the-hand-written-lines)

**Duplicate conflict**:
Two predecessor entries for the same ID and field with different Japanese text. At import, identical duplicates collapse (all `origins` kept), and differing ones keep the first occurrence as the line's `ja` (status `pending`) with the others in `conflicts`. `check` then decides, the rules first and a [[Ruling]] second: exactly one variant passing the rules becomes the line; zero or several passing leaves the line a [[Rejected entry]] (`duplicate_conflict`) until a person adds a ruling. The corpus carried 2,143 conflicting and 548 identical duplicate ids.

**English source**:
The English text an entry is translated from and checked against: pfQuest and the VMaNGOS world database (open data; VMaNGOS for quest progress, completion, gossip, NPC speech and book pages); Blizzard's own text from the client's [[Quest cache]] for quest title, objectives, description, [[Area text]] and [[Objective text]] (it replaces pfQuest's wherever cached); the client's [[DB2 table]]s for client-side text, read from the [[Local archive]] of an installed client (`db2@<build>`) or from wago.tools CSV exports of the same tables (`wago@<build>`, a cross-check); forever-vo's player captures for quest progress, turn-in text and NPC greetings no other source has (`forever-vo@<commit>`, ADR-055); and the addon's own [[Collector]] for text only the server sends. Never Wowhead.
_Avoid_: original, base text

**Quest cache**:
The game client's `Cache/WDB/enUS/questcache.wdb`: the title, objectives and description (plus text we do not use) the server sent for every quest the client asked about, written when the client exits (Exit Game, not logout). After the [[Scan lines]] run, it is the English source `wdb@<build>` for those three fields, the [[Area text]] and each quest's [[Objective text]]. Local tooling only reads and copies it; the addon never does. Holds no progress / completion text.
_Avoid_: WDB (the folder holds other caches too), harvest file, quest DB
→ [ADR-020](adr/020-quest-cache-harvest.md)

**Local archive**:
The installed game's own data store under `World of Warcraft/Data/` (with `.build.info`), shared by every client flavour on the machine. Local tooling reads the [[DB2 table]]s out of it with `make tables-extract`, read-only and offline; the addon never reads it. The beta-day source of client-side English, so the harvest needs no external site.
_Avoid_: CASC (the format's name, not the thing), game files, MPQ (the old format)
→ [ADR-021](adr/021-client-tables-from-the-local-archive.md)

**DB2 table**:
One of the client's data tables (ItemSparse, SpellName, Spell, GlobalStrings, ItemSubClass, SpellItemEnchantment, QuestV2, ItemEffect, and on builds that ship it ItemXItemEffect), stored in the [[Local archive]] as a WDC5 file under `DBFilesClient\`. The pipeline reads them as wago.tools-shaped CSVs, whichever way they were obtained. A table only some builds ship is `optional`: its absence from the client's root is reported, not a failed run.
_Avoid_: DBC (the older format), database, wago table
→ [ADR-021](adr/021-client-tables-from-the-local-archive.md) · [Pipeline](systems/pipeline.md)

**FileDataID**:
The number the [[Local archive]] files a game file under, stable across builds. The reader finds a [[DB2 table]] by its path's name hash and keeps each table's FileDataID only as a fallback.
_Avoid_: file id, fdid (in prose)
→ [ADR-021](adr/021-client-tables-from-the-local-archive.md)

**Layout hash**:
The fingerprint in a [[DB2 table]]'s header of its field layout. A table's column map is pinned **per build**, to each layout hash it has been verified on (Classic Era 1.15.9.69722 and every Forever build since 1.60.1.69913, 1.60.1.70124 and 1.60.1.70170 included), each pin carrying the citation that verified it; a hash nobody has verified stops that table, naming every layout that has been, so a moved field never becomes wrong English. Re-verifying is `wfj.dev.verify_columns` against a second installed client, not a hash bump.
_Avoid_: schema version, table hash (a different header value, which names the table)
→ [ADR-021](adr/021-client-tables-from-the-local-archive.md) · [ADR-027](adr/027-column-maps-verified-per-build.md)

**Hotfix cache**:
The client's `Cache/ADB/enUS/DBCache.bin`: [[DB2 table]] rows the server changed after the build shipped, which the [[Local archive]] never holds. `make tables-extract` applies it over the archive rows by default (`HOTFIXES=` to skip it); it must be of the same build as the archive. For each row the last entry, in (push id, file order) order, decides: a valid row with data replaces it, anything else removes it. Every table takes hotfixes: ItemSubClass, QuestV2, ItemEffect and ItemXItemEffect read a hotfix record by their pinned field types; if that decode stops the run, `HOTFIXES=` writes the archive rows only. A cache of another build is refused; logging into the client again writes a current one. Read only.
_Avoid_: ADB, DBCache (in prose), patch
→ [ADR-021](adr/021-client-tables-from-the-local-archive.md)

**Source stamp**:
The file `tables-source.txt` beside the [[DB2 table]] CSVs, one line per table: `<table> <src>@<build>` (`db2` read from the [[Local archive]], `wago` downloaded from wago.tools). Only `make tables-extract` and `make wago-fetch` write it: they clear the fetched tables' lines before moving the CSVs in and write them after, so an interrupted run leaves the tables unstamped, never under an old stamp. The import preflight and the client-table imports refuse a CSV with no stamp or with a stamp other than the source and build they were told, so the `src` on every English line names where its text really came from. Not used for pfQuest, VMaNGOS or the [[Quest cache]].
_Avoid_: manifest, build file, provenance (that is the per-entry record on Japanese lines)
→ [ADR-021](adr/021-client-tables-from-the-local-archive.md) · [Local setup](operations/local-setup.md)

**Served record**:
The committed files `pipeline/served/<kind>.tsv` (kinds quest, item, spell, ui; area and objective lines follow their quest): every id any Forever build has served, one `id<TAB>first build<TAB>last build` row per id under a `#` header line. The [[Served step]] adds the current build's ids and moves their last build forward. An id the current build did not serve keeps its row and its older last build, and keeps its English. Nothing acts on an old last build; the record is there for a possible later cleanup.
_Avoid_: gone list, removed list, served cache (nothing in it is removed or expires)
→ [ADR-050](adr/050-english-is-additive.md) · [Pipeline](systems/pipeline.md)

**Served step**:
The last step of `make import` / `make import-english` (`wfj import english served`, `make import-served`). It is additive: it drops English only for ids Forever has never served, and never removes a line whose English came from Forever itself. What a build serves: quest ids in Forever's QuestV2 or its [[Quest cache]] (placeholders included), item ids in ItemSparse, spell ids in SpellName, and [[UI string]] keys whose English carries the Forever tables' [[Source stamp]] and that are in `ui_keys.txt`. It adds those ids to the [[Served record]], and keeps every line whose id is in the record, from this build or an earlier one. [[Objective text]] follows its quest (mapped through Forever's cache, then Classic Era's; an objective no cache maps is kept). Book and gossip English is untouched. Forever's own tables decide, not where the English came from: a quest Forever lists but the server has not answered yet keeps its Classic Era English and ships. An id an earlier build served and this one did not keeps its English; the import prints how many. Japanese in `data/` is never touched; a line whose English was dropped becomes `no_english_id` and ships again when a later harvest lists the id.
_Avoid_: served filter (it narrows the English store, not the build), Forever filter, target filter, "gone" (for an id the current build did not serve; its English is kept)
→ [ADR-034](adr/034-forever-is-the-only-target.md) · [ADR-050](adr/050-english-is-additive.md) · [Pipeline](systems/pipeline.md) · [Data model](architecture/data-model.md)

**Served-text inventory**:
Every text column of every [[DB2 table]] the Forever install ships, plus each server cache (`Cache/WDB/enUS/*.wdb`), with row and text counts: the generated, committed `pipeline/served_columns.txt` (`make served-columns`, once per build), paired with the hand-written `pipeline/served_dispositions.txt` that gives each column a [[Disposition]]. It is what coverage and translation scope are measured against. Its delta against the previous build lists the columns a patch added, dropped or changed. Not the [[Served record]], which lists ids, not columns.
_Avoid_: player-visible set, visible spells, what a player is likely to see (the scope it replaced)
→ [ADR-052](adr/052-coverage-by-served-data.md) · [Data model](architecture/data-model.md) · [Pipeline](systems/pipeline.md)

**Disposition**:
What one served column of the [[Served-text inventory]] is, from a closed set: `surface:<type>.<field>`, `surface:<type>.*` (every field of that type) or `surface:ui:<Family>` (the addon ships it in Japanese), `names` (names stay English), `internal` (developer text the client never prints), `no-display` (prose the Forever client has no place for), `covered-by:<column>` (the same text reaches the screen through another column) or `empty`. `internal`, `no-display` and `covered-by` carry evidence. Every served column has exactly one.
_Avoid_: exclusion (that is a UI key in `ui_exclusions.txt`), status (that is per [[Entry]]), skip
→ [ADR-052](adr/052-coverage-by-served-data.md) · [Data model](architecture/data-model.md)

**Gap**:
In coverage: a served line of a surface that has neither shipped Japanese nor a stated reason (a names list, nothing to translate, English still waiting on the Forever tables, an exclusion with its reason). Gaps are the build's translation list; `tests/python/test_coverage.py` fails while any remain, and [Coverage](operations/coverage.md) counts them.
_Avoid_: missing (a missing line can have a reason), untranslated, to-do
→ [ADR-052](adr/052-coverage-by-served-data.md) · [Coverage](operations/coverage.md)

**Tooltip text**:
The English prose of an item or spell tooltip below its name, as the client tables hold it: a spell's `Description_lang`; for an item, the descriptions of its effect spells the tooltip prints (trigger types Use, Equip, Chance on hit, Use without delay) then its flavour text, so an item's "Use:" line is a **spell's** `Description_lang` reached through the item→effect join, never `ItemSparse.Description_lang`, which holds only the flavour line and is often empty. A raw template (`Restores $o1 health over $d.`): the numbers are filled in only when the client renders it, so offline it catches rewording (the entry goes [[Stale]]) but never a changed number. Stored as the `description` field.
_Avoid_: description (the field name, also used for quests), name (a separate field), rendered tooltip (what the [[Collector]] records, with numbers)
→ [Data model](architecture/data-model.md) · [ADR-007](adr/007-unaligned-ships-with-runtime-gate.md)

**Buff text**:
A spell's `AuraDescription_lang`: the text shown on the buff or debuff the spell puts on a character, distinct from its [[Tooltip text]]. Stored as the spell field `aura`, translated like [[Tooltip text]] and shown on buff and debuff tooltips.
_Avoid_: aura description (in prose), debuff tooltip
→ [Data model](architecture/data-model.md)

**Stat word**:
One of ten stat and resource words in [[Tooltip text]] and [[Buff text]]: armor, health, mana, stamina, strength, agility, intellect, spirit, rage, energy. Every shipped tooltip line writes each as the interface does on the character sheet (アーマー, 体力, マナ, スタミナ, 筋力, 敏捷性, 知力, 精神, 怒り, エネルギー), never in English letters and never as ヘルス; lint reason `stat_word:<word>`. [[Hand-written]] lines carry a correction that does the same. The words stay on the name-check allowlist, because some lines still hold one inside a name or phrase. A stat word inside a name stays English with it (`Mana Shield`, `Elixir of Agility`).
_Avoid_: attribute, resource word (energy and rage are stat words here too), stat name
→ [Pipeline](systems/pipeline.md) · [ADR-048](adr/048-stat-words-in-tooltips.md)

**Area text**:
A quest's area description in the [[Quest cache]]: the text of an exploration or event objective ("Scout the gazebo on Mystral Lake…", "Kernobee Rescue"). Its own translation type `area` (field `text`, keyed by the quest id). Checked as prose against its own English like [[Objective text]], and found in the addon the same way (by the text the client writes as an objective line, in one index with objective text), so the Japanese appears wherever the client writes it. It takes no word readings.
_Avoid_: exploration text, zone text, quest area field. Not a translation *area* (the `quests` / `books` / … groups
a setting turns on and off, `State.areaEnabled`): the type is named after the quest cache's field; say "area text" for
the type and "translation area" for the setting group.
→ [Data model](architecture/data-model.md) · [ADR-044](adr/044-area-text-and-book-word-cards.md)

**Objective text**:
The short line of one quest objective that has its own text ("Rescue Drull"), keyed by its QuestObjective id from the [[Quest cache]]. Kill and collect objectives have none; the client builds their [[Objective line]] from its own templates. Translation type `objective`; an objective text that is only a name ("Flame of Azel") is never translated ([[Name policy]]). Distinct from a quest's `objectives` field, the log summary.
_Avoid_: objectives (the quest field), goal, task
→ [Data model](architecture/data-model.md) · [ADR-031](adr/031-objective-lines-menus-and-helptips.md)

**Book page**:
One page of an in-game book, letter or plaque, from the VMaNGOS `page_text` table (a book's pages chain through `next_page`). Translation type `book`: in `data/` keyed by its page entry (the game id); in the generated Lua keyed by the hash of the English its Japanese was checked against, because the client exposes no page id and the addon finds a page by its [[Live English]]. Pages sharing one English share one row and must share one Japanese. Shown in the [[Item text window]]. A plain-text page (not HTML) takes [[Reading]]s and the [[Word card]]; its readings are stored by page id and shipped under the same English-hash key.
_Avoid_: book (a book is several pages), letter (a letter is one kind of item text), item text (the window's name)
→ [Data model](architecture/data-model.md) · [ADR-022](adr/022-book-and-trainer-greeting-surfaces.md)

**Quest scan**:
The maintainer's step that fills the [[Quest cache]] before an import. Its tooling is kept outside this repository; the import reads the cache file. Not part of the addon.
_Avoid_: scan lines, scan macro, scan script, harvester
→ [Pipeline](systems/pipeline.md) · [ADR-020](adr/020-quest-cache-harvest.md)

**English delta**:
What `data/english/` gained, lost or changed since a git ref, per type: ids new, ids removed, lines changed per field (`wfj stats --delta REF`, which first prints the status shift: translation lines whose status moved). The review view after an English import such as the beta-day harvest.
_Avoid_: diff (that is git's), changelog
→ [Pipeline](systems/pipeline.md)

**Capture list**:
The quests from an [[English delta]] that are new or whose title / objectives / description English changed, written as JSONL by `wfj stats --delta REF --capture PATH`, each with the source of its progress / completion English (`null` = none). They name the quests whose turn-in windows a player must see in-game so the [[Collector]] records that text.
_Avoid_: todo list, stale report (that is `--stale`), missing list (the import's unanswered ids)
→ [Pipeline](systems/pipeline.md) · [Collector](systems/collector.md)

**Stale**:
A trusted or [[Unaligned entry]] whose stored [[Source hash]] no longer matches the current [[English source]] for that field: the English changed after the translation was checked (for items and spells, when their [[Tooltip text]] changes). Stale entries **ship**, shown with a [[Stale marker]], and are first in line for re-audit (`wfj stats --stale` lists the quest ones). A stale item or spell entry is still gated at display time like an unaligned one: Japanese with the marker when names and numbers match the live tooltip, the English otherwise. On quest surfaces the marker follows the [[Live check]] when one is possible, not the build-time status. A numeric change (a count, a level) fails the [[Alignment check]] outright and is rejected instead. A [[UI string]] whose live English no longer matches its shipped hash shows the English with **no** marker (a marker on a one-word label would break the layout; [ADR-015](adr/015-ui-text-surfaces.md)).
_Avoid_: outdated, expired, invalid

**Source hash**:
The hash of the normalized English text an entry was checked or translated against, stored per field. Rebuilding against a new English dump compares hashes to detect [[Stale]] entries.

**Female variant**:
The English of a line with each `$G<male>:<female>;` resolved to its female branch, where `normalize_v1` resolves it to the male one. Its key, and the `h1` taken from that key, are what a female character's [[Live English]] hashes to. Derived by the pipeline at generate time from the stored English, never stored in `data/`; a line without a gender code, or whose female text normalizes to the same key, has none. On a quest row the per-field `h1f` slots carry it.
_Avoid_: female hash (on its own; say the female variant's key or `h1f`), gender key
→ [Data model](architecture/data-model.md) · [ADR-024](adr/024-gender-variants-and-short-name-candidates.md)

**Gender alias**:
A generated keyed row (gossip, book page) repeated under its English's [[Female variant]] key, so a female character's live English finds the same Japanese. The line's word list ([[Reading]]) is shipped under the alias key too, so the female line has word cards. Exists only in the generated Lua. A real row under that key wins; aliases on one key with different Japanese are all dropped, and that key shows the live English. `generate` reports the counts and the dropped keys.
_Avoid_: gender key, female row, duplicate row
→ [Pipeline](systems/pipeline.md) · [ADR-024](adr/024-gender-variants-and-short-name-candidates.md)

**Paragraph break**:
The one encoding of a paragraph boundary inside a Japanese value: `\n\n`. The lineage sources wrote it as two spaces (WoWJapanizer / CraftJapanizer) or four (QuestJapanizer); import canonicalises it, the generated Lua escapes it, the client renders it as a blank line. English paragraphs are pfQuest's `$B` runs. Counted by the completeness rule.
_Avoid_: line break (a single `\n` inside a paragraph is not one), double space
→ [Pipeline → Rules](systems/pipeline.md#rules)

**Shard**:
One file holding every [[Entry]] whose game ID falls in one 1,000-id range (`NNNN = id // 1000`: ids 7000–7999 are shard `0007`). The same boundaries apply in `data/` (`quest-0007.jsonl`) and in the generated addon Lua (`Data/Quest/Quest_0007.lua`), so a data change touches the same shard in both trees; a range with no entries has no file. Gossip shards by the first two hex characters of the [[Gossip key]] instead; [[UI string]]s by the [[UI key]]'s first character, upper-cased (`ui-A.jsonl`, `Data/UI/UI_A.lua`).
_Avoid_: chunk, page, batch, data file (a shard is one of many, by id range)
→ [Data model](architecture/data-model.md)

**Slot**:
A fixed position inside one generated Lua row (a field's Japanese, that field's 32-bit source-hash prefix, or the row's status string), defined once by the slot map (`WFJ.SLOTS` in `Core/Const.lua`, `SLOTS` in `emit/schema.py`, kept in parity by tests). Slots are positional *within* a row only: the row itself is always keyed by the game ID, never by position, and a slot never moves without a data-schema bump. An empty slot (`nil`) means the field is not shipped.
_Avoid_: index, column, array position (the thing the ID rule forbids for *entries*)
→ [Data model](architecture/data-model.md) · [Addon modules](architecture/addon-modules.md)

**Server-only text**:
Quest progress text, quest completion (turn-in) text, NPC [[Gossip]], [[NPC speech]] and [[Book page]]s: text whose English reaches the project only from the server side (VMaNGOS, and the in-game [[Collector]]), never from the client's own files. It is drafted as [[Machine-drafted text]] in [[Translation batch]]es, because no client pull will ever supply it.
_Avoid_: server text, dynamic text, client text (the opposite: text the client's own files hold)
→ [Translation batches](operations/translation-batches.md)

**Translation batch**:
One cut of untranslated text of one kind (`progress`, `completion`, `gossip`, `book`, the quest title, objectives and description kinds, `objective`, `area`, and the tooltip kinds) for a drafting model: one row per unique English text as the drafter sees it (for `book`, per English hash, so pages differing only in whitespace share a row), with tokens mapped to [[Player placeholder]]s and `$B` as a [[Paragraph break]], each row listing every `(id, field)` that shares that English as its targets. Lines that have a [[Hand-written]] variant are never cut, except with `--held-back` for lines whose hand-written variants all carry a `reject` [[Ruling]]. Lines with a draft of the current [[Style version]] are cut only to fix them in place (`--ids --redraft`), and lines with an older-version draft only when asked (`--redraft-older`). A batch is a working file in `pipeline/batches/` (ignored by git); only its imported result lands in `data/`.
_Avoid_: shard (an id range of committed data), chunk, draft (the drafter's output for a batch)
→ [Translation batches](operations/translation-batches.md) · [Pipeline](systems/pipeline.md)

**Style version**:
The version of the translation style guide a machine draft was written under: `version: sg<N>` in `docs/content/translation-style-guide.md`. It is recorded in every machine line through the draft name, which must end in `-sg<N>` (`progress-sg1`), so [[Provenance]] `source` reads `draft-<kind>-sg<N>@<date>` with no schema change. A change to the guide's rules or examples bumps the version when the maintainer decides it does ([ADR-023](adr/023-server-only-text-drafted-in-measured-batches.md)). Lines already drafted under an older version stay drafted; they return to a [[Translation batch]] only when the cut is asked to redraft older versions (`--redraft-older`).
_Avoid_: prompt version, guide revision, model version
→ [Translation style guide](content/translation-style-guide.md)

**Translation glossary**:
`pipeline/translation_glossary.tsv`: recurring English words a drafter translates rather than keeps in English letters (`adventurer` → `冒険者`, `Light` → `光`), each the rendering the human corpus uses most, plus the race and class words in katakana spelled exactly as the addon fills `{race}` / `{class}` (`tauren` → `トーレン`), marked `required` so `translate_lint` fails a draft that renders them differently. Never a name: names stay in English letters under the [[Name policy]].
_Avoid_: allowlist (Latin words allowed to stay in the Japanese), dictionary, [[UI dictionary]], term list
→ [Translation style guide](content/translation-style-guide.md)

**Not-names list**:
`pipeline/translation_not_names.tsv`: capitalised English words that are not names on one [[Translation batch]] row (a heading, letter greeting or plaque word such as `Package` in `An Overdue Package`), so `translate_lint`'s `name_missing` lets that row translate them. One `<ref>\t<word>\t<English context>` entry per row and word, each reviewed by a model on the rule "a name when in doubt". An entry whose word is a `required` glossary term also exempts it from `glossary:<term>` on that row ("a rogue spark" is not the class). A word recurring on many rows belongs in the [[Translation glossary]] instead.
_Avoid_: allowlist (Latin words allowed to stay in the Japanese), exemption list, [[Translation glossary]] (translated words on every row)
→ [Translation batches → Not-names list](operations/translation-batches.md#not-names-list)

**Reading**:
The kana pronunciation of a Japanese [[Word]] as a whole (少し → すこし, 生き物 → いきもの), stored in `data/reading/` as its own record per shipped Japanese line of a quest field, a gossip line, a [[UI string]] or a plain-text [[Book page]]: the line's words in order, each with its reading, plus the hash of the Japanese it was written for and its own [[Provenance]] (`machine` or `correction`). A reading never edits or copies the Japanese; the addon shows it in the [[Word-reading box]] and the [[Word card]].
_Avoid_: furigana layer, ruby, readings layer, kana annotation, yomigana
→ [Readings](systems/readings.md) · [ADR-036](adr/036-readings-hover-word-lists.md)

**Word**:
In a [[Reading]] record, a run of the Japanese that holds at least one kanji and no ASCII character (so never a name: names stay English), found in the line in order after the previous word. Always a whole word, never a single kanji of it: 少し, not 少. An entry that carries a [[Meaning]] takes the **whole inflected unit** as one word: a verb or adjective with all its endings and helper verbs (減らしてやって欲しい), noun + する, a noun with a plural or honorific suffix; never a noun with its particle. Such an entry may be a [[Kana word]].
_Avoid_: token, kanji run, segment, term (that's the [[Translation glossary]])
→ [Readings](systems/readings.md)

**Kana word**:
A [[Word]] written all in kana (まだ, いる, しまった). Its reading is itself, so it is listed only as an entry that carries a [[Meaning]], for the [[Word card]]; with no meaning, or with meanings off, it is not a hover target.
_Avoid_: hiragana word, kana token
→ [Readings](systems/readings.md)

**Dictionary form**:
The plain form of a [[Word]]'s head, as a dictionary lists it: 食べている → 食べる, 強くなかった → 強い, 調査された → 調査する, 生き物たち → 生き物. It keeps the text's spelling (a word written in kana stays in kana: いる, not 居る) and is stored with its own kana reading. Shown on the [[Word card]] only when it differs from the word.
_Avoid_: lemma (in docs prose; `lemma` is the code's field name), base form, root, stem
→ [Readings](systems/readings.md) · [ADR-039](adr/039-word-meanings-written-in-context.md)

**Meaning**:
A short English meaning (at most 60 characters) of a whole [[Word]] as its sentence uses it, the inflection translated too: 食べている → "is eating", 倒して in 「…を倒して」 → "defeat". Written by the model with the sentence in front of it, as part of the word's [[Reading]] entry, and shown on the [[Word card]]. Not a dictionary list: one sense, the one this sentence uses. A class or race word the addon fills in gets its English name ("Druid (a class)"). Generated into `Data/Gloss/`, each distinct (dictionary form, reading, meaning) stored once.
_Avoid_: gloss, definition, translation (in player-facing text; `gloss` is the code's name: `Core/Glosses`, `readings.glosses`, `Data/Gloss`)
→ [Readings](systems/readings.md) · [ADR-039](adr/039-word-meanings-written-in-context.md)

**Stale reading**:
A [[Reading]] whose stored hash no longer matches the Japanese it annotates: the translation changed after the words were written. `wfj validate` reports it (not a failure) and `wfj generate` leaves it out, so it never ships, unlike a [[Stale]] entry, which ships with a marker. It is written again from a fresh export.
_Avoid_: outdated reading, [[Stale]] (that's the English side of a translation)
→ [Readings](systems/readings.md)

## Addon

**Name policy**:
Names of people, places, mobs, items, spells, and zones stay in English everywhere; Japanese is for prose. Race and class words are katakana, following the human corpus, including the reader's own, filled from a [[Player placeholder]]; the reader's character name is shown as the client returns it.
_Avoid_: localized names, transliteration

**UI string**:
One of Blizzard's own interface words or templates, such as a button ("Accept"), a header ("Quest Objectives") or a tooltip [[Structural line]] ("Binds when picked up", "Requires Level %d"), stored as an [[Entry]] of type `ui`, field `text`, addressed by its [[UI key]]. Never a name ([[Name policy]]). The addon matches it against the client's [[Live English]] for that key, admitted only when the hash equals the shipped `h1` (an item subclass word, an [[Enchantment stat line]], a [[Spell subtext]] or a [[Text family]] row, which have no client string the addon can read, are matched by the live text's fingerprint instead), and fills a template's values from the live line. Its English may carry colour codes, [[Plural grammar]], file textures (`|T…|t`, an icon inside the text; the Japanese keeps each exactly) and the `|n` break, never links, `|K` or `$` tokens.
_Avoid_: global string (that is the client's variable), locale string, UI text (the whole screen)
→ [Data model](architecture/data-model.md) · [ADR-014](adr/014-machine-drafted-text-and-ui-dictionary.md)

**UI key**:
The id of a [[UI string]]: the client's global-string name (`ACCEPT`, `ITEM_MIN_LEVEL`), `ItemSubClass:<classID>:<subClassID>` for an item subclass name ("Cloth", "Axe", "Soul Bag": the short name the tooltip shows), `SpellItemEnchantment:<id>` for an [[Enchantment stat line]], `SpellSubtext:<spellID>` for a [[Spell subtext]], `<Family>:<id>` for a [[Text family]] row (`FactionDescription:<id>`, `CreatureType:<id>`, …), or `ItemSubClassName:<classID>:<subClassID>` for an item subclass's long name ("Staves", "One-Handed Axes": the auction house's category word). Only the keys curated in `pipeline/ui_keys.txt` are imported and translated; a line ending in `:*` there (`ItemSubClass:1:*`, `SpellItemEnchantment:*`) is a key family the import expands to every id with that prefix.
_Avoid_: tag, string id, hash key (UI strings are keyed by name, not by a [[Gossip key]]-style fingerprint)
→ [Pipeline](systems/pipeline.md)

**Plural grammar**:
Blizzard's singular/plural markup inside a [[UI string]] template, `|4singular:plural;` (`%d |4Day:Days;`): the client picks one form from the number before it. The addon matches a template in its all-singular, all-plural and raw forms; the Japanese may drop the group (Japanese has no plural) but keeps the specifier. A template with more than four groups is not matched (counted `unsupported`).
_Avoid_: pluralization token, `|4` code (fine in code, not as the term)
→ [Pipeline → Rules](systems/pipeline.md#rules) · [ADR-016](adr/016-whole-window-interface-coverage.md)

**Enchantment stat line**:
A tooltip line an enchantment or random suffix prints as a signed amount and words ("+3 Fire Spell Damage", "+5 Stamina"): a [[UI string]] keyed `SpellItemEnchantment:<id>` whose English is that enchantment's display text. Matched by fingerprint. An enchantment's *name* ("Crusader") is a name, never one of these.
_Avoid_: random suffix (the "of the Eagle" part of an item name), enchant name, stat mod, `ITEM_MOD_*_SHORT` (a different, unused key family)
→ [Data model](architecture/data-model.md) · [ADR-016](adr/016-whole-window-interface-coverage.md)

**Spell subtext**:
The short word under a spell's name in the spellbook ("Racial Passive", "Summon", "Tier 2"): the Spell table's `NameSubtext_lang`, not a global string. A prose subtext is a [[UI string]] keyed `SpellSubtext:<spellID>` with one representative spell per distinct English, shown on every spell with that subtext by [[Fingerprint match]]. A subtext that is a name (a pet family "Cat", a form) is never listed ([[Name policy]]). Not "Passive" or "Rank 3": those the client writes from global strings (`SPELL_PASSIVE`, `RANK`).
_Avoid_: subname (the widget, `item.SubName`), rank text, spell subtitle
→ [Data model](architecture/data-model.md) · [ADR-032](adr/032-level-1-gaps-subtexts-and-name-titles.md)

**Text family**:
A set of [[UI string]]s that come from one text column of one client [[DB2 table]] rather than from a global string: the reputation panel's faction description (`FactionDescription`), achievement titles, descriptions, rewards and categories, skill descriptions and skill categories, emote lines (`EmoteText`), holiday descriptions, currency descriptions and categories, debuff types (`DispelType`: "Curse"), creature types (`CreatureType`: "Humanoid") and quest-log sort headers (`QuestSort`); also the barber shop's customization categories, options, choices and lock text, the PvP scoreboard's stat columns and their tooltips, the group finder's categories, activity groups and "Custom" activity, the UI widgets' status lines (`WidgetText`) and the wardrobe's set variant words (`ItemNameDescription`). Keyed `<Family>:<row id>`; one key per distinct English; matched by [[Fingerprint match]] (an `EmoteText` row as a [[Slotted row]], a `WidgetText` row as a [[Numbered row]]). A column that holds names (faction, skill, currency or holiday names) is never a family ([[Name policy]]). Every family is **restricted**: the addon finds its rows only where a widget names the family, and each family is indexed on its own, so its Japanese may differ from a button's or another family's for the same English (the barber shop's "Close" style 寄せ, the button 閉じる). Twenty-five families from twenty-two tables, plus the restricted `ItemSubClassName` keys.
_Avoid_: client-table string, DB2 string, table text (as the term), key family (that is a `:*` line in `ui_keys.txt`)
→ [Pipeline](systems/pipeline.md) · [Data model](architecture/data-model.md) · [ADR-042](adr/042-client-table-text-families.md)

**Slotted row**:
A [[Text family]] row whose English is a template with `%s` slots the client fills with names (an emote line, "%s waves at %s."), and which, like every family row, ships only its Japanese and the English's `h1`. The addon finds it by putting the slots back: in the live chat line, the names it knows (the sender, the player, the target) and, failing that, one more run of one to four words become `%s`, and the skeleton whose hash is the row's `h1` is the row. The names fill the Japanese exactly as the line wrote them. Only `EmoteText` rows are slotted.
_Avoid_: template fingerprint, emote template, slot match
→ [Addon modules](architecture/addon-modules.md) · [ADR-042](adr/042-client-table-text-families.md)

**Numbered row**:
A [[Text family]] row whose English holds world-state tokens the client replaces with live numbers, such as a UI widget's status line, "Towers Controlled: %2327w" shown as "Towers Controlled: 3". No English ships, so both sides hash a skeleton with every number run as `#`: the pipeline replaces the tokens and digit runs of the English, the addon the digit runs of the live line, and the skeleton whose hash is the row's `h1` is the row. `data/` keeps the tokens in the Japanese; the generated row writes each as `%<k>$s`, and the addon fills it with the k-th number of the live line. Only `WidgetText` rows are numbered.
_Avoid_: widget template, token row, `$N` token (that is a [[Value placeholder]])
→ [Pipeline](systems/pipeline.md) · [Addon modules](architecture/addon-modules.md) · [ADR-042](adr/042-client-table-text-families.md)

**Name-list tail**:
The end of a spell description that lists names rather than prose: a chain of `$?s<id>[<line break>$@spellname<id>][]`, one line per spell the character knows, each that spell's name (Languages: "Common", "Dwarvish"; Armor Proficiency: "Mail"). The Japanese translates only the text before it and ends in the placeholder **`$T`**; the addon appends the client's live lines from the first line break on, so the names stay [[Live English]] ([[Name policy]]). Only a chain that is the description's trailing run counts.
_Avoid_: spell list, name list, `$@spellname` chain (fine in code, not as the term), tail flag (the shipped data has none; `$T` carries it)
→ [Data model](architecture/data-model.md) · [Pipeline](systems/pipeline.md) · [ADR-033](adr/033-level-1-gaps-name-list-tails-and-untagged-menus.md)

**Included text**:
Another spell's text that a tooltip template prints in place: `$@spelldesc<id>` (that spell's description), `$@spelltooltip<id>` (its buff text), `$@spellname<id>` (its name, which stays English: [[Name policy]]). The pipeline splices the included spell's English into the English the drafter reads (nested inclusions too, up to four deep), so the entry's Japanese translates the whole line as one sentence and its [[Value placeholder]]s count the included values where they stand. The entry records the included spells' English hashes (`english.includes`); a change to any of them makes it [[Stale]]. A missing spell, a cycle or any other `$@` code leaves the entry English.
_Avoid_: inclusion (fine in code, not as the term), embedded spell, spell reference, sub-description
→ [Pipeline](systems/pipeline.md) · [Data model](architecture/data-model.md) · [ADR-043](adr/043-included-text-icons-and-branch-variants.md)

**Branch variant**:
One branch combination of a tooltip template with `$?<cond>[A][B]` conditionals: the client picks a branch by a talent, an aura, a faction or the player's level, and prints only that one. The entry's Japanese keeps the conditionals (same conditions, branches and order) with its [[Value placeholder]]s numbered over the whole template; the pipeline splits it into one Japanese per combination, renumbered to that combination's reading order, and ships them together (a table slot, at most 16). The addon shows the one variant that passes the [[Alignment check]] on the [[Live English]] line (never by evaluating the condition), and the English when none or several pass.
_Avoid_: branch, conditional (the English code, not the Japanese), case, alternative
→ [Addon modules](architecture/addon-modules.md) · [Data model](architecture/data-model.md) · [ADR-043](adr/043-included-text-icons-and-branch-variants.md)

**Variant shape**:
A [[Branch variant]]'s count of values and durations, written `"<values>/<durations>"` (`"3/1"`): what the addon reads off a live line showing that variant. Shipped beside each variant; compared with the live line only when the variants' shapes differ, which is how a line with an extra clause is told from one without (Fire Ward with and without its talent's reflect clause).
_Avoid_: signature, arity, slot count (that is the whole template's)
→ [Addon modules](architecture/addon-modules.md) · [ADR-043](adr/043-included-text-icons-and-branch-variants.md)

**Shadowed variant**:
A [[Branch variant]] that another variant of the same entry also passes on. On the line where it is shown, a second variant's Japanese passes the [[Alignment check]] too (no shape, name or number tells them apart), so the addon shows the English there. It still ships: dropping it would let the other variant pass alone on that line and show the wrong branch. An entry is refused only when **every** variant is shadowed, so nothing could ever show (`branches_indistinguishable`; Tiger's Fury's white / red "Requires Cat Form" is shadowed on one line, not refused).
_Avoid_: indistinguishable variant (the refusal is for the whole entry), duplicate, dead branch
→ [Pipeline](systems/pipeline.md) · [ADR-043](adr/043-included-text-icons-and-branch-variants.md)

**UI dictionary**:
The set of shipped [[UI string]]s, and the addon's index over them (`Core/UIStrings`, `WFJ.UIIndex`) built once at load: exact strings, templates, and labels, from which every interface surface looks up the line or widget it just saw. One dictionary for every surface; new coverage on a hooked surface is dictionary rows, not code.
_Avoid_: glossary (this document), translation table, locale file
→ [Addon modules](architecture/addon-modules.md) · [ADR-015](adr/015-ui-text-surfaces.md)

**Owned key**:
A [[UI key]] whose Japanese belongs to that key alone, listed in `UIStrings.OWN`: one English that needs a different Japanese on one screen ("Back" is 戻る on the auction house's button, 背中 as the equipment slot; "Available" is 習得可能 on the trainer filter, 在席 as a friends status). It is kept out of the [[UI dictionary]]'s by-English index, so it never makes the other key ambiguous and shows only where a widget asks for it by key. A plain word, not a template.
_Avoid_: homograph (the English words, not the key), override, per-surface Japanese (the problem, not the mechanism), special key
→ [Addon modules](architecture/addon-modules.md) · [ADR-037](adr/037-staticpopup-dialogs-and-owned-keys.md)

**Structural line**:
A tooltip line that is interface text rather than a description or a name: binding, slot and armor type, armor, stats, durability, "Requires Level 10", mana cost, range, cast time, "Sell Price:". Walked on both sides of every line, excluding the [[Description run]] and the name (the line whose text is the item / spell name, and left line 1 except on a comparison tooltip, whose line 1 is the "Currently Equipped" header, itself a structural line). Shown from the [[UI dictionary]] with the captured numbers verbatim.
_Avoid_: stat line, tooltip body, metadata line
→ [Addon modules](architecture/addon-modules.md)

**Label**:
A fixed header or button on a named widget whose whole current text is exactly one [[UI string]] (quest frame headers and buttons, the quest log title and buttons, game-menu buttons). A composite ("Learn Spell: (Complete)") is not a label and is left English. In the index, a label also names the whitelisted [[Label form]]s (`"<entry>: <rest>"`, `"<entry> <number>"`, `"Strength:"` …), where only the entry part is translated.
_Avoid_: caption, title (a quest's title is an entry field)
→ [Addon modules](architecture/addon-modules.md)

**Label form**:
A whitelisted shape in which a [[Label]] entry appears inside a longer live text, with only the entry part translated and the rest kept as shown: `colon` ("Sell Price: 5c"), `number` ("Speed 2.60"), `bareColon` ("Strength:"), `wrapped` (a colour code around the entry), `binding` ("Character Info (C)"), `equip` ("Equip: Increases…"), `colonPrefix` ("Item Sold: Linen Cloth"), `joined` (two templates joined by two spaces), `list` ("Requires: Level 5, First Aid (50)", each list item that is itself a whitelisted entry translated), `icon` (an icon before the entry, "\<icon> Tank"), `optionTip` (a Settings option's "\<label>: \<tooltip>", both halves entries), `colonPrefixEntry` ("Sold By: Multiple Buyers", the rest itself an entry), [[Count label]], `durationSuffix` ("Combat 3 [01:23]"), `iconAfter` ("Revert \<icon>"), `headerLines` ("Unread mail from:" then names) and `voiceParts` (three sentences, each an entry). A form reaches only the [[UI key]]s listed for it in `UIStrings.LABELS`, so "Libram: Cleanse" is never read as a label.
_Avoid_: pattern, composite (a composite with no form stays English), format
→ [Addon modules](architecture/addon-modules.md) · [ADR-016](adr/016-whole-window-interface-coverage.md) · [ADR-038](adr/038-menus-callouts-and-composite-forms.md)

**Count label**:
A [[Label form]] `"<entry> (<n>)"`: an interface word followed by a count the client adds in parentheses ("Multiple items (3)", `MAIL_MULTIPLE_ITEMS`): the word is translated, the count kept as written. Granted per key.
_Avoid_: counter, number label (that is the `number` form, "Speed 2.60"), plural
→ [ADR-038](adr/038-menus-callouts-and-composite-forms.md)

**Entry list**:
A template argument that is a list of interface words joined by the client's list delimiter (", "), such as a bag's or bank tab's filters, "Equipment, Consumables" in `BAG_FILTER_ASSIGNED_TO`. Every piece must be an interface word (else the line stays English); each is shown in Japanese and each delimiter kept as written. Argument kind `entryList`. Contrast the `list` [[Label form]], whose items may be anything and only the whitelisted ones translate.
_Avoid_: list argument, filter list, joined words
→ [Addon modules](architecture/addon-modules.md) · [ADR-038](adr/038-menus-callouts-and-composite-forms.md)

**Composite line**:
A line the client builds from several strings (a template around another template's text, a log line with a time suffix, a combat-text number with its trailer) that no single dictionary match covers. A surface splits it into pieces, matches each against its own keys and shows the rejoined Japanese, pieces that are names or numbers kept as written (`Labels.part` / `Labels.showArgs`, the `seq` fill). A composite with no form stays English.
_Avoid_: compound string, concatenation, formatted line
→ [Addon modules](architecture/addon-modules.md) · [ADR-038](adr/038-menus-callouts-and-composite-forms.md)

**Follow-up exclusion**:
An entry in `pipeline/ui_exclusions.txt` for a composite whose reason starts `follow-up:`: it names the [[Label form]] or surface that would render it and that is not built yet. Its opposite is a **permanent exclusion** (`permanent:`), which says why no form can reach the text (a literal that is not an interface string, a name the text is made of) and cites its source file and line. Every composite exclusion is one of the two; none is a follow-up today.
_Avoid_: deferred key, TODO key, "later"
→ [Pipeline](systems/pipeline.md) · [ADR-031](adr/031-objective-lines-menus-and-helptips.md)

**Synonym keys**:
Two or more [[UI key]]s whose English is identical and whose Japanese is identical (`NONE` / `RESISTANCE_NONE`, "None"). The [[UI dictionary]] indexes them as one entry named after the first key, and a [[Label form]], a [[Key-restricted match]] or a duration naming any of them accepts the match. Same English with different Japanese is not synonyms but `ambiguous`: neither key is shown. The same holds across [[Fingerprint match]] rows and an English entry: a [[Text family]] row whose English a global string or another family row already answers with the same Japanese ("Epic") is a synonym of that key, so a widget restricted to one family still finds it.
_Avoid_: duplicates, aliases
→ [Addon modules](architecture/addon-modules.md)

**Key-restricted match**:
A dictionary match accepted only when the matched [[UI key]] (or one of its [[Synonym keys]]) is in a list the caller gives, used on a widget that can hold either an interface word or a name: the friends-window title (a guild may be named "Raid"), a bag title, a reputation header, the merchant title, a help tooltip owner.
_Avoid_: whitelist match, filtered match, `only` (the option's name in code)
→ [Addon modules](architecture/addon-modules.md)

**Pass-through wrapper**:
An error [[UI key]] whose English is exactly `%s` (`ERR_SPELL_FAILED_S`): the client uses it to carry another message's text in the UI errors frame, so the key names no text of its own. Never translated (excluded); its line is resolved by a [[Key-restricted match]] against the listed error keys with at least four letters of their own.
_Avoid_: wrapper key, `%s` key, generic error
→ [ADR-035](adr/035-ui-errors-frame-surface.md)

**System chat line**:
A chat line the game adds as bare text with no sender: the chat types `SYSTEM`, `LOOT`, `MONEY`, `CURRENCY`, `COMBAT_XP_GAIN`, `COMBAT_FACTION_CHANGE`, `SKILL` and the rest of `ChatSystem.PLAIN_TYPES`: "You receive loot: …", "You are now Away: …", "Total time played: …", an error key echoed to chat. Matched by exact English or by a [[Key-restricted match]] over the error keys and the **chat key families** (`UIStrings.CHAT_FAMILIES`, GlobalStrings key patterns such as `^LOOT_ITEM_`), and rewritten once in the chat history. The combat log is not a system chat line.
_Avoid_: system message (ambiguous with the errors frame), chat event
→ [ADR-035](adr/035-ui-errors-frame-surface.md) §7–§8

**Chat prefix**:
The words the chat frame puts around the sender's name before a player's or an NPC's line: a `CHAT_<type>_GET` [[UI key]] ("%s says: ", "To %s: ", "[Raid Warning] %s: "). Only its words are translated ("%sの発言: "); the name, its link and the message itself are left as written: what a player types is never touched. A prefix with a channel link ("[Party]") or no words stays English.
_Avoid_: chat header (that is the edit box's "Say:" label, `CHAT_<type>_SEND`), sender label
→ [ADR-035](adr/035-ui-errors-frame-surface.md) §9

**Key-restricted chat path**:
The [[System chat line]] rewrite applied to a message frame outside the chat windows whose client lines can only be a few [[UI key]]s: the Communities chat's date and unread separators and its message-of-the-day label. A line is rewritten only when it is wholly one of those keys; members' messages never are (`ChatSystem.hookKeyed`).
_Avoid_: communities chat hook, keyed frame, chat filter
→ [Addon modules](architecture/addon-modules.md) · [ADR-038](adr/038-menus-callouts-and-composite-forms.md) §16

**Objective line**:
One progress line under a quest in the objective tracker, the quest list or the map details: either a line the client builds from its own template ("3/10 Kobold Vermin slain", a [[UI string]] whose mob, faction or player-group name stays as written) or an [[Objective text]] with its count ("0/1 Archive Burned", "Archive Burned: 0/1"). The count and a " (Complete)" tag are kept where the client wrote them.
_Avoid_: objective (the data type or the quest field), progress text (the quest's progress field), tracker line
→ [Addon modules](architecture/addon-modules.md) · [ADR-031](adr/031-objective-lines-menus-and-helptips.md)

**Fingerprint match**:
Finding a shipped row by the hash of the [[Live English]] where the client exposes no id at the place the text is shown: the row stays keyed by its game id in `data/`, and the addon indexes rows by their `h1` and looks the live text's hash up. Used for item subclass words, [[Enchantment stat line]]s, [[Spell subtext]]s, [[Text family]] rows (a [[Slotted row]] after its names are put back) and [[Objective text]] on an [[Objective line]], with the count set aside first. Two rows with one English and different Japanese are ambiguous: neither is shown. A match, never a key; contrast the [[Gossip key]], which *is* the hash.
_Avoid_: hash key, hash lookup (as a keying scheme), fuzzy match
→ [Addon modules](architecture/addon-modules.md) · [ADR-031](adr/031-objective-lines-menus-and-helptips.md)

**Menu tag**:
The name Blizzard's Menu system gives one generated dropdown or context menu (`MENU_CONTAINER_FRAME`, `MENU_QUEST_MAP_LOG_TITLE`). The addon translates a menu's entries by tag, each tag with its own list of [[UI key]]s its entries may show (a [[Key-restricted match]]), so a rank, bag, channel or player name in the same menu stays English. Submenus belong to their menu's tag. A tag whose menu is titled by a name (a unit's right-click menu, a chat channel's menu) is marked `titleIsName`: its title and any entry equal to that name are never matched, so a player named "Duel" stays "Duel".
_Avoid_: dropdown id, menu name, context menu (the thing, not its tag)
→ [Addon modules](architecture/addon-modules.md) · [ADR-031](adr/031-objective-lines-menus-and-helptips.md) · [ADR-032](adr/032-level-1-gaps-subtexts-and-name-titles.md)

**Untagged menu**:
A dropdown menu whose generator sets no [[Menu tag]] (the Options window's dropdowns and Edit Mode's setting dropdowns), so Blizzard's menu-modify hook never reaches it. The addon reaches each one through its own dropdown button when the menu is built, under a pseudo-tag (`SETTINGS_DROPDOWN`, `EDIT_MODE_DROPDOWN`) whose [[Key-restricted match]] is its window's keys: a font, locale or layout name stays English.
_Avoid_: untagged dropdown (fine), settings menu (a tagged menu may be one too), pseudo-tag (the addon's name for it, not the thing)
→ [Addon modules](architecture/addon-modules.md) · [ADR-033](adr/033-level-1-gaps-name-list-tails-and-untagged-menus.md)

**Untagged context menu**:
A right-click menu built and opened in one call (`MenuUtil.CreateContextMenu`) with no [[Menu tag]] and no dropdown button, such as the Group Finder's listing menu or the crafting-orders recipe menu. The addon reaches it in the menu system's populate step (a post-hook on `Menu.PopulateDescription`), before any entry frame exists, and recognises each by its content or its owner; the Group Finder menu's title, the leader's name, stays English.
_Avoid_: context menu (any right-click menu, tagged or not), popup menu, unnamed menu
→ [Addon modules](architecture/addon-modules.md) · [ADR-038](adr/038-menus-callouts-and-composite-forms.md)

**Utility-button tooltip**:
The hover of a small icon button attached to a menu entry: the gear, cancel (X) or play-sample button (Edit Mode's delete / rename-or-copy layout, Cooldown Settings' alert buttons). The button owns its own tooltip, so the addon registers each of the entry's child buttons as a [[Help tooltip]] owner with the tag's tooltip keys, besides the entry itself.
_Avoid_: gear tooltip, menu tooltip (a disabled entry's reason is the entry's own tooltip), icon hover
→ [Addon modules](architecture/addon-modules.md) · [ADR-038](adr/038-menus-callouts-and-composite-forms.md)

**HelpTip callout**:
A tutorial or alert box with an arrow that Blizzard's `HelpTip` shows beside a window or a micro button ("You have unspent talent points."), sized to its text. Not a [[Help tooltip]]: a callout is a frame of its own, shown by the game rather than on hover. Translated in the box before it is measured; the callout's own record of its English is never changed, because the game identifies its callouts by it.
_Avoid_: help tip (ambiguous with help tooltip), tutorial popup (a [[Tutorial popup]] is a different frame), alert
→ [Addon modules](architecture/addon-modules.md) · [ADR-031](adr/031-objective-lines-menus-and-helptips.md)

**Tutorial popup**:
The small parchment window Blizzard opens with a short tip the first time something happens (a whisper, a group invite, swimming, fatigue, a broken item), with a title, a body and Close / Prev / Next buttons (`TutorialFrame`). Forever draws only 8 of them (whispers, grouping, friends, fatigue, swimming, broken items, raids, companions); the addon shows each one's title and body in Japanese. Not a [[HelpTip callout]] or a [[Pointer arrow]]: those are arrow boxes beside the thing they explain.
_Avoid_: tutorial (too broad: also the callouts and arrows), tutorial frame, tip window, new player experience (a retail tutorial Forever never runs)
→ [Addon modules](architecture/addon-modules.md) · [ADR-016](adr/016-whole-window-interface-coverage.md)

**Pointer arrow**:
A box with an arrow that Blizzard's tutorial manager points at a button or tab (`TutorialPointerFrame`), sized to its text. On Forever only the class tutorial uses one, pointing at the talents button and the Talents tab when the character has an unspent talent point [unverified in game]. Same idea as a [[HelpTip callout]] but a different frame: the addon translates the text after the game draws it and re-sizes the box the way the game does.
_Avoid_: pointer, tutorial pointer, callout (that is the HelpTip one), arrow tip
→ [Addon modules](architecture/addon-modules.md) · [ADR-031](adr/031-objective-lines-menus-and-helptips.md)

**Gamepad HUD**:
The interface the Forever client shows only in gamepad input mode (Options → Gamepad, or a connected controller): the button prompts along the bottom of every window, the persistent controller legend, the radial main menu, the "More Actions" context menus and the cinematic skip button. One [[Surface]], `gamepad`. Not the gamepad action bar editor, which is its own surface (`gamepadedit`).
_Avoid_: controller UI, console UI, gamepad mode (the input mode, not its interface), prompt bar
→ [Addon modules](architecture/addon-modules.md) · [ADR-040](adr/040-gamepad-hud.md)

**Static label**:
A [[Label]] Blizzard writes once when the UI loads (an XML `text=` or an OnLoad call) and never rewrites: tabs, column headers, fixed buttons. The addon shows it in Japanese when it initialises, before the window is first shown, so the window's own layout (a tab's width) is measured from the Japanese. Never released; the toggle restores and re-applies it like every record.
_Avoid_: load-time text, fixed text, XML label
→ [Addon modules](architecture/addon-modules.md) · [ADR-016](adr/016-whole-window-interface-coverage.md)

**Help tooltip**:
A GameTooltip built line by line in Lua for a frame the player hovers (a micro button, a character-sheet stat, an empty equipment or bag slot, a repair button), as opposed to an item or spell tooltip the client fills from game data. Its line 1 is a title, not a name. Translated only when its owner frame is registered by a window module, and never while the tooltip shows an item or a spell.
_Avoid_: newbie tip (one kind of help-tooltip line), UI tooltip, hover text
→ [Addon modules](architecture/addon-modules.md) · [ADR-016](adr/016-whole-window-interface-coverage.md)

**Appended lines**:
Interface lines Blizzard's Lua adds to the end of a tooltip that shows an **item**: the auction house's seller and time-left lines, an enchant slot's replace hint, an order reagent's provider line, a bag's assigned filters. A [[Help tooltip]] walk never reads an item tooltip, so the owning surface translates these right after the writer ran, matching every line only against its own keys: the item's own lines are no key of that set and stay with the item surface, never translated twice (`HelpTooltip.appended`).
_Avoid_: extra lines, tooltip tail, item lines (those are the item's own)
→ [Addon modules](architecture/addon-modules.md) · [ADR-038](adr/038-menus-callouts-and-composite-forms.md)

**Never-touch widget**:
A widget no record may ever be written on, whichever surface asks: an EditBox, a name widget, or text Blizzard reads back (`OpenMailSender.Name`, copied into a reply) or sends to the server (`GuildInfoEditBox`). Declared per window module (`NEVER_TOUCH`) and refused by the shared label step.
_Avoid_: protected widget (protected means secure / taint in WoW), excluded widget, skip list
→ [Addon modules](architecture/addon-modules.md)

**Collector**:
The addon module (`Core/Collector.lua`) that records the [[Live English]] the addon has no [[Known English]] for (quest text, NPC gossip with the ids of the NPCs that said it, item and spell descriptions, quest-giver NPC names) into the [[Collector dump]], in Blizzard's own tokens: the player's name as `$N`, and in quest and gossip text the class and race as `$C` / `$R`. Text naming the player anywhere else is refused. It lets the [[English source]] grow with text only clients see, and measures the untranslated gap. On by default (`collector.enabled`), disclosed once in chat.
_Avoid_: scraper, dump mode, logger, tracker
→ [Collector](systems/collector.md) · [ADR-013](adr/013-collector-english.md)

**Collector dump**:
The `WFJ_Collector` SavedVariables table, and the player's `WoWForeverJapanese.lua` file that carries it: the [[Collector]]'s entries keyed `<kind>:<id>:<field>`, each only normalized text in Blizzard's tokens (`$N`, `$C` / `$R` in quest and gossip text, paragraphs joined with `$B$B` as pfQuest writes them), its hash and a client-build index; no character, account, realm, location or time. Handed off manually as a GitHub issue attachment and read by `wfj import english collector`, which takes what the Forever client showed as the English: it replaces stand-in English (pfQuest, VMaNGOS, an older client) and keeps the same client's own tables and quest cache. `check`, `validate` and `stats` consult imported quest and gossip English; item and spell English is stored, not consulted.
_Avoid_: upload, telemetry, log file, export, `WFJ_DB` (that is the settings table)
→ [Collector](systems/collector.md) · [ADR-053](adr/053-forever-shown-english-is-the-english.md)

**Known English**:
Live English whose hash matches the 32-bit source-hash prefix (`h1`) shipped for that field, so the addon recognises it and the [[Collector]] does not record it. Anything else (never shipped, changed since the check, or a field whose shipped hash belongs to another field: quest progress/completion, item/spell descriptions today) is unknown and recorded.
_Avoid_: seen (the collector's word for a text already in the dump), translated, trusted
→ [Collector](systems/collector.md)

**Surface**:
One Blizzard window or tooltip family the addon translates: the quest windows (with their greeting panel), the quest map (`questmap`, `questmap.popup`, `questmap.list`, `questmap.tracker`), the gossip window, the item and spell tooltips, the [[Item text window]], the game menu, the character sheet and its panes, spellbook, talents, trainer, merchant, bank, bags, mail, friends, raid, the Communities window, the [[Help tooltip]]s, the [[Gamepad HUD]] (`gamepad`), and one surface for every other window a [[Disposition]] `surface` names, from `professions` to `zonetext`. Each surface resolves the Forever client's names through [[Candidate name]]s. The same names are the inventory's surfaces in `pipeline/ui_inventory.txt`; a window may add a `<surface>.static` surface for its [[Static label]]s. Each surface is owned by exactly one `UI/` file, which calls Render on the surface's show event and releases its records on its close event; a surface holds no policy of its own.
_Avoid_: screen, frame (a frame is a widget), hook
→ [Addon modules](architecture/addon-modules.md)

**Item text window**:
The client window (`ItemTextFrame`) that shows a readable item's or object's pages (books, letters, plaques), one [[Book page]] at a time with Prev / Next. Its page text is a SimpleHTML (`ItemTextPageText`: per-tag fonts, no `GetText`), not a FontString. Surface `itemtext`, area `books`: the page text is translated; the title (the item or object name), the page number and a player-written letter are never touched. A plain-text page showing Japanese is drawn in a FontString of the addon's, laid over the SimpleHTML's place, so the [[Word card]] can find its words; English and HTML pages stay in the SimpleHTML.
_Avoid_: book window (it also shows letters and plaques), reading frame, letter window
→ [Addon modules](architecture/addon-modules.md) · [ADR-022](adr/022-book-and-trainer-greeting-surfaces.md)

**Render record**:
The addon's in-memory note of one translated element: the target FontString, the English the client's API returned for it, the font it had, and what we applied. Created when a surface renders, released when the surface closes, keyed by the *logical* element (quest field, option index, tooltip line number), never by FontString identity; pooled widgets are reused. Holding this long enough to put the English back *is* the feature, and is not "stored English".
_Avoid_: cache, original text store

**Description run**:
The contiguous tooltip lines that one Japanese block replaces. For an item: the maximal run, starting from line 2, of lines that begin with a trigger string (`Use:`, `Equip:`, `Chance on hit:`) or form a flavour quote; for a spell: the single line whose text equals the client's `GetSpellDescription(id)` (matched by content, so a line another addon appended is never taken; without that API, the line above `Next rank:`, else the last non-empty line, talent hints skipped). Blank lines inside an item run belong to it. The name line is never part of a run. The run's first line is the **primary** [[Render record]] and carries the Japanese; the run's other lines are **companions** that show one space while the primary is applied and their own [[Live English]] otherwise; the whole run restores and re-applies together. A tooltip with no run is left untouched.
_Avoid_: effect lines, tooltip body, block (the *Japanese* is the block; the run is the English it replaces)
→ [Addon modules](architecture/addon-modules.md) · [ADR-010](adr/010-tooltip-in-place-run-replacement.md)

**Live English**:
The English text the game client is displaying right now. The addon never ships or shows stored English: holding the modifier reveals live English, and a missing or rejected entry simply leaves the frame untouched. One mechanism serves both.
_Avoid_: original text, our English, fallback text (there is no separate fallback text)

**Modifier**:
The key the player holds to see the [[Live English]]; releasing it returns the Japanese. Alt by default. It is one of three classes: **either** (`alt` / `ctrl` / `shift`: either side of the key), **side** (`lalt` … `rshift`: one side only), or **bound** (any other single key or mouse button 3–5, taken over by an [[Override binding]] while the addon is loaded). Set by pressing it on the settings page or with `/wfj modifier <key>`. Never the same key as the toggle binding. Key names stay English.
_Avoid_: reveal key, hotkey, hold key
→ [Settings](systems/settings.md) · [ADR-018](adr/018-reveal-key-override-binding.md)

**Override binding**:
A session-only, addon-owned binding that takes a **bound** [[Modifier]] key over while the addon is loaded, so the key reveals English instead of doing its own action. Never saved into the player's binding set: changing the modifier or disabling the addon gives the key its action back. Distinct from the toggle key, which is an ordinary saved binding.
_Avoid_: rebind, keybind override
→ [Settings](systems/settings.md) · [ADR-018](adr/018-reveal-key-override-binding.md)

**Action**:
The Translator's verdict for one element: `apply` (write the Japanese), `leave` (the frame stays untouched, no marker: master or area off, or the modifier held), or `none` (no usable translation; the missing marker may be added to the [[Live English]]). The only three outcomes a surface can receive.
_Avoid_: mode, decision, result
→ [Addon modules](architecture/addon-modules.md)

**Stale marker**:
A short message, `[要更新 / English Changed]`, shown for a translated element whose entry is [[Stale]], telling the player to hold the modifier and read the [[Live English]]. With the missing-translation message (`[未翻訳 / Not Translated]`), the [[Word-reading box]] and [[Word card]], and the [[Minimap button]], it is one of the few additions the addon makes to the screen ([Principles §3](architecture/principles.md#3-japanese-by-default-english-one-key-away)). In the quest window both markers appear on one banner line beside the portrait; elsewhere they are inline above the text.

**Word-reading box**:
The small box above a Japanese [[Word]] (the game's own tooltip frame) in quest or gossip prose, in a [[Window label]] or on a plain-text [[Book page]], showing that word's whole [[Reading]] while the mouse is on it; the word is tinted gold at the same time. Nothing is drawn until the mouse is on a word, it never shows while English shows, and the `readings.enabled` setting turns it off. One of the on-screen additions [Principles §3](architecture/principles.md#3-japanese-by-default-english-one-key-away) allows.
_Avoid_: furigana, ruby, reading tooltip (it is not a GameTooltip), popup
→ [Readings](systems/readings.md) · [ADR-036](adr/036-readings-hover-word-lists.md)

**Word card**:
The [[Word-reading box]]'s larger form (`UI/ReadingPopup`): for a [[Word]] that carries a [[Meaning]], the word and its reading (a [[Kana word]] shown once), the [[Dictionary form]] and its reading when it differs (laid out like the head line, in pale blue and muted gold), then the meaning, in a 280 px card above the word, kept on screen. Shown instead of the reading-only box while `readings.glosses` is on (default on; the *Show word meanings in the reading box* checkbox on the main settings page, or `/wfj glosses on|off`); a word with no meaning still gets the reading-only box. Same rules as the box: nothing drawn until the mouse is on a word, never while English shows. Shown on quest and gossip prose, [[Window label]]s and plain-text [[Book page]]s ([Principles §3](architecture/principles.md#3-japanese-by-default-english-one-key-away)).
Player-facing text (the README, the listing) calls it the popup dictionary.
_Avoid_: gloss box, dictionary popup, tooltip (it is not a GameTooltip)
→ [Readings](systems/readings.md) · [ADR-039](adr/039-word-meanings-written-in-context.md)

**Window label**:
A plain-text label in a window: a FontString showing one [[UI string]] (the quest window's 報酬 and 以下の報酬から1つ選択できます, the character sheet's section labels, mail's 宛先:) whose parent is not a Button or a protected frame, on a [[Surface]] that is a window: not a button, tab, menu, dropdown or tooltip, and not the HUD (tracker, alerts, error and combat text, unit frames, zone text; `View.NON_WINDOW`). The only interface text that takes a [[Word card]]. Narrower than [[Label]], which also covers buttons.
_Avoid_: UI label (too wide: buttons are labels too), window text, header, static text
→ [Readings](systems/readings.md) · [ADR-041](adr/041-word-cards-on-window-labels.md)

**Cover frame**:
The invisible frame of the addon's own laid over one prose FontString that has [[Reading]]s (`UI/Readings`): it takes mouse motion only (clicks and scrolling go through), and on mouse enter checks that the FontString still shows the text it was attached for before measuring any word. Attached after an apply, detached on every restore, release and forget.
_Avoid_: overlay, hit frame, hover frame, mask
→ [Readings](systems/readings.md)

**Live check**:
The addon's comparison, on a quest surface, of a quest field's [[Live English]] fingerprints (the `h1` of each [[Gossip key]]-style candidate: full, race only, class only, name only, nothing replaced) with the field's shipped `h1`, or its [[Female variant]]'s `h1f`. It decides the [[Stale marker]]: no fingerprint equal → the Japanese shows with the marker; one equal → no marker, whatever the build-time status. No equal fingerprint while a name under 3 code points occurs in the text (the fingerprints include short-name candidates), no fingerprints (the player's name, class or race not known yet) or no shipped `h1` (a field checked against another field's English) → the build-time status decides. It never withholds a translation.
_Avoid_: runtime stale check, live gate (the align gate is a different thing)
→ [Addon modules](architecture/addon-modules.md) · [ADR-019](adr/019-quest-english-per-field-and-live-check.md)

**Gossip**:
The NPC talk window: the greeting paragraph and the clickable option lines shown when you click an NPC. Server-sent and ID-less, so gossip entries are addressed by a [[Gossip key]] instead of a game ID. Quest titles listed in the same window are quests, not gossip. Distinct from [[NPC speech]] (the predecessor's "ScriptData" file is NPC speech, not gossip). The gossip *kind* in `data/` also holds NPC speech lines (same keying), but they are not gossip.
_Avoid_: dialogue, script data, NPC text

**NPC speech**:
What NPCs say, yell, whisper and emote outside the talk window: scripted lines delivered as `CHAT_MSG_MONSTER_SAY` / `_YELL` / `_WHISPER` / `_EMOTE` / `_PARTY` and `RAID_BOSS_EMOTE` / `_WHISPER`, shown in the chat window, in speech bubbles and (boss emotes) in the middle of the screen. Its English is VMaNGOS `broadcast_text`, imported as gossip-kind lines keyed by a [[Gossip key]]; switched with NPC talk (`area.gossip`). A `%s` in it is the speaker's name, which the client fills in. Translated like gossip ([ADR-035](adr/035-ui-errors-frame-surface.md) §10). The predecessor's 11,965 machine-translated lines are this kind.
_Avoid_: NPC chat, gossip, dialogue, ambient chatter

**Gossip key**:
The fingerprint of a gossip line's [[Live English]]: `normalize_v1` over the text in Blizzard's tokens, with the player's name, class and race (capitalized or lowercase) replaced. It is computed in the addon by `Collector.key` and equal to the hash the [[Collector]] stores for the line, and identically by the pipeline over that stored English. A translation may be shipped under any of the line's candidate keys (full: name, class and race replaced; name only; or nothing replaced), because a line that says a class or race word literally is keyed either way; for a name under 3 code points, then full and name only with that name also replaced. The addon uses the first candidate with a shipped row. A female character's text also finds a [[Gender alias]]. Every candidate is a hash of the same English. Identical English lines share one key and therefore one Japanese line, by design. A gossip window row's record key (`greeting`, `option.<orderIndex>`) is not a gossip key: it names where the text is shown, never which translation.
_Avoid_: hash code, text id, option index
→ [ADR-005](adr/005-gossip-key-fingerprint.md) · [ADR-017](adr/017-gossip-surface.md)

**Blast radius**:
The [[Gossip key]]s with English (the [[Collector]]'s, and VMaNGOS's with no NPC ids), ranked by how many different NPCs the Collector saw say the line: the lines whose Japanese would change the most places at once ("Goodbye.", "I would like to buy from you."), so they are reviewed first. Printed by `wfj stats` (top 20, with each key's status). A review list, not a scope: it changes no status and no yield.
_Avoid_: occurrence count, frequency, top keys
→ [Collector](systems/collector.md) · [Pipeline](systems/pipeline.md)

**Fix report**:
The block of text a player copies out of the fix window and pastes into a GitHub issue (label `translation-report`) to report wrong or awkward Japanese: a `WFJ-REPORT 1` header, the addon and client versions, one `fix` line per [[Pending fix]] with its optional note and Japanese, and an `end <count>` trailer that shows whether the paste was cut. Every fix names a line by its store address and the hash of the stored Japanese behind what the player saw (the before); it carries the player's Japanese only when they changed the line (the after), and no English. Read by `wfj report check` (the issue workflow), `intake` and `apply`; a fix the pipeline applies is written with provenance `report` = the issue number.
_Avoid_: bug report, feedback, translation issue (the issue is the container; the report is the pasted block), correction (a [[Correction]] is the data variant a report may produce)
→ [Fix reports](systems/fix-reports.md) · [ADR-045](adr/045-player-fix-reports.md)

**Recent lines**:
The addon's in-memory list of the Japanese lines it wrote on screen this session, one per store address (`Core/RecentLines`): each with its address, the hash of its stored Japanese, the stored Japanese and the text as shown (values and player tokens filled in, markers and colour codes removed). Lines fall into three groups, story (quest, NPC talk, book, objective, area), tooltips (item, spell) and windows (interface text), each keeping its last 100; lines one [[Surface]] writes within a second form a burst, listed newest burst first and in on-screen order within it. Listed on the fix window's **Translations** tab (翻訳), filtered by group (All by default) and redrawn while the window is open; the player picks the line to report from it. Only lines the store holds as one entry are listed (not a line a [[Branch variant]] built). Never saved, and never holds English.
_Avoid_: history, log, recent translations, chat log
→ [Fix reports](systems/fix-reports.md)

**Pending fix**:
One fix the player saved in the fix window and has not sent yet, listed on its **Pending** tab (送信待ち); the window's own copy calls it a saved report (報告): a line's address and the hash of the Japanese they saw, a reason (`wrong`, `awkward`, `typo`, `name`, `other`), an optional note and optionally their own Japanese. Kept in `WFJ_DB.reports` across `/reload` and logout, at most 25, one per line, until the player clears them after pasting the [[Fix report]].
_Avoid_: draft, queued report, saved report (the report is the copied text of all pending fixes)
→ [Fix reports](systems/fix-reports.md)

**Minimap button**:
The addon's small button on the minimap edge (`UI/MinimapButton`): left-click opens the fix window, right-click opens a menu (Translation on / off, Report a line, Settings, Hide this button); drag moves it around the rim. On by default, hidden by the `minimapButton` setting; the same two clicks are also on the addon's entry in Blizzard's addon dropdown on the minimap. One of the on-screen additions [Principles §3](architecture/principles.md#3-japanese-by-default-english-one-key-away) allows.
_Avoid_: minimap icon, LDB button, launcher, addon compartment (that is Blizzard's dropdown)
→ [Fix reports](systems/fix-reports.md) · [ADR-045](adr/045-player-fix-reports.md)

## Client

**Game type**:
The client-side label that decides which interface files a WoW client loads. Each line of a Blizzard TOC may carry `[AllowLoadGameType …]` / `[ExcludeLoadGameType …]`, and a whole addon may carry `## AllowLoadGameType:`. Classic Era loads the lines gated `classic` or `vanilla`; Forever's game type is [[camelot]]. A line loads when its allow list is absent or names the client's game type or family, and its exclude list names neither.
_Avoid_: flavor, client version, build (a build is a number such as 1.60.1.69913)
→ [ADR-029](adr/029-camelot-targets-the-mainline-family.md) · [camelot surface re-target](research/2026-09-19-camelot-surface-retarget.md)

**camelot**:
World of Warcraft: Forever's [[Game type]]. A member of the [[Mainline family]]: Forever runs the retail interface with camelot overrides, not the Classic Era interface. In TOC paths `[Game]` expands to `Camelot\`. Written lowercase, as the client writes it.
_Avoid_: Forever UI, the Forever flavor, Classic (Forever is not a classic-family client)
→ [ADR-029](adr/029-camelot-targets-the-mainline-family.md)

**Mainline family**:
The group of [[Game type]]s that load the retail interface files: `mainline` itself and [[camelot]]. In TOC paths `[Family]` expands to `Mainline\` for them. A line gated `[AllowLoadGameType mainline]` loads on Forever unless it also says `[ExcludeLoadGameType camelot]`; a line gated only `classic`, `vanilla`, `tbc` and so on does not. Neither does `standard`: the client's TOCs write `standard, camelot` where both are meant, so a `standard`-only addon (Housing, the Encounter Journal's `standard, classic`) is gated away from Forever.
_Avoid_: retail (retail is the live product; the family is a load rule), modern client
→ [ADR-029](adr/029-camelot-targets-the-mainline-family.md) · [ADR-030](adr/030-every-window-the-forever-client-loads.md)

**Load set**:
The client files a Blizzard addon loads on [[camelot]], in load order: its TOC's lines that pass the [[Game type]] rule, with XML `<Include>` / `<Script>` followed. Resolved by `wfj.dev.client_addons` (`--files <addon>` prints one). An addon's state is `gated` (its header keeps camelot out), `glue` (login screen only), `login` or `lod` (load-on-demand); only `login` and `lod` addons are in game. "In the load set" means some camelot-loaded file of some addon; an entry point outside it does not count.
_Avoid_: file list (the inventory's `FOREVER_WINDOWS` is a per-surface subset), TOC contents (a TOC also lists gated lines)
→ [ADR-030](adr/030-every-window-the-forever-client-loads.md) · [Pipeline](systems/pipeline.md)

**Disposition**:
What the addon does about one Blizzard addon [[camelot]] loads in game, recorded with its evidence in `pipeline/forever_addon_dispositions.txt`. The set is closed: `surface <names>` (its files feed those [[Surface]]s), `library` (templates or utilities whose text reaches the screen only through a consumer surface), `no-text` (nothing player-facing), `unreachable` (no entry point in the [[Load set]]; cites a `path:line` or "no reference in the load set"), `no-content` (an entry point exists, but the Forever client's own tables hold none of the content the window opens on (covenants, garrisons, azerite, the Great Vault); cites the entry point and the table evidence), `planned` (not handled yet; left as the client shows it) or `not-a-window` (chat / error lines, slash words, StaticPopups, spoken text, secure-environment windows). `unreachable` is a claim about the client's code and `no-content` a claim about the server's content; neither is ever used because a window is big. `tests/python/test_forever_windows.py` enforces completeness and the evidence rules. `forever_titles.txt` uses the same word for its per-`SetTitle`-site kinds (`key`, `name`, `ruled`, `dynamic`).
_Avoid_: status (a translation line's status is a different thing), triage (the process, not the result), skip
→ [ADR-030](adr/030-every-window-the-forever-client-loads.md) · [the Forever window sweep](research/2026-09-19-forever-window-sweep.md)

**Window title**:
The text in a mainline window's `TitleContainer.TitleText`, written by `frame:SetTitle(text)` (or `SetTitleFormatted`). A window may re-title itself at any time (per tab, mode or selection), so `Labels.title` re-shows it after every call. Every `SetTitle(` site in the surface addons is listed in `pipeline/forever_titles.txt` as `key` (a dictionary word, Japanese), `name` (English: [[Name policy]]), `ruled` (`BANK`, kept English by decision) or `dynamic` (built text). The character window's title is a pane word on a sub-pane and the player's name on the paperdoll.
_Avoid_: header (a DialogHeader is a different widget), caption, frame name
→ [Addon modules](architecture/addon-modules.md) · [ADR-030](adr/030-every-window-the-forever-client-loads.md)

**Candidate name**:
One of the names a surface declares through `Compat` for a client thing it needs: a global, a function, or a **dotted path** through `parentKey`s (`PlayerSpellsFrame.TitleContainer.TitleText`). Candidates are the [[camelot]] names; a declaration stays a list even when it holds one name. The first one that resolves is used, and a hook is installed only for a writer that resolves. A name that does not resolve shows in `/wfj debug` as unresolved.
_Avoid_: fallback, alias
→ [Addon modules](architecture/addon-modules.md)

**Pooled row**:
A list row, header or item button the client reuses from a frame pool or ScrollBox (spell items, skill-detail rows, who rows, roster rows, trainer services, quest-list rows). It has no stable index, so the addon walks the active pool after the writer runs and keys the row's [[Render record]] by a game id the row carries (`questID`, the spell slot) or by the row widget itself, never by its position.
_Avoid_: row N, list index

**Forget**:
To drop a surface's [[Render record]]s without writing English back over text the client has since rewritten (`Render.forget`). Distinct from **release**, which restores every applied record when the surface's frame closes. The quest window, the quest map details pane and the tracker popup write the same `QuestInfo*` FontStrings, so each forgets the other two before it shows.
_Avoid_: clear, reset
→ [ADR-029](adr/029-camelot-targets-the-mainline-family.md)

**UI inventory**:
The list, per [[Surface]], of every UI key a hooked client file can put on screen, enumerated from source by `wfj.dev.ui_inventory`. There is one, the Forever client's: `pipeline/ui_inventory.txt`, built by `make ui-inventory` from a client UI extract and its GlobalStrings (its file map `FOREVER_WINDOWS` covers every `surface` [[Disposition]]). Every inventoried key is in `pipeline/ui_keys.txt` or excluded with a reason in `pipeline/ui_exclusions.txt`; the coverage test holds the inventory to that.
_Avoid_: key list (that is `ui_keys.txt`), string dump
→ [Pipeline](systems/pipeline.md)

**Secret value**:
A value the Forever client hands an addon sealed: it can be held, passed on and written to the screen (`SetText`), but any read, comparison, concatenation, table index or arithmetic on it raises an error. `issecretvalue` tells one apart; `type()` still answers. In combat an action button's tooltip rows and the cooldown numbers are secret; a buff tooltip's aura id, spell and rows too.
_Avoid_: hidden string, restricted value, tainted value (taint is a different mechanism)
→ [Client limits](architecture/client-limits.md)

**Hidden pass**:
A pass of the tooltip surface over a tooltip whose rows are [[Secret value]]s. It translates the client's own tooltip data for the spell or item id by row position and has the client write the cooldown countdown from its hidden duration; it keeps no record and remembers nothing between passes (`UI/Tooltip.lua`). The opposite is a readable pass, which renders through [[Render record]]s.
_Avoid_: secret pass (the trace's event names say "secret spell" / "secret item" / "secret aura" for the pass's kind), write-back, memory pass
→ [Client limits](architecture/client-limits.md)

**Client limit**:
Something the Forever client keeps from addons by design, with the addon's response written down beside it: a buff tooltip in combat stays English, a cooldown's number is formatted by the client, a combat log line is sealed. Each entry cites the client's own files or an in-game trace. A limit is never worked around by guessing or by remembering across passes.
_Avoid_: known issue, bug, workaround
→ [Client limits](architecture/client-limits.md)

**Tooltip trace**:
The row-by-row record of every pass over a tooltip, kept in memory while `/wfj debug tooltip on` and shown by `/wfj debug tooltip` in a window whose text can be copied. Each entry names the pass's kind, the spell or item id, the owner, each row's kind, text and colour (a [[Secret value]] as `<secret>`), what was written and why; a hidden pass's entry adds every data row, the row map and the countdown's duration. It is the evidence a client-side fix is made from.
_Avoid_: debug log, dump
→ [Testing strategy](testing/strategy.md)

## Release

**Release run**:
One run of the Release workflow on `main`, started from the Actions tab or with `make release`. It is the whole release: it picks the version, moves the [[Unreleased]] lines under it in `CHANGELOG.md`, commits and tags, builds the zip, passes the [[Package check]], and only then pushes and publishes the same zip to CurseForge and a GitHub release. A run that fails after its push is finished by running it again with the same version (it resumes).
_Avoid_: tag push, deploy, publish (publishing is its last step), release (alone: in the addon, `Render.release` restores a surface's English; see [[Forget]])
→ [Release](operations/release.md) · [ADR-046](adr/046-one-action-release.md)

**Unreleased**:
The `## Unreleased` section at the top of `CHANGELOG.md`: the player-facing lines of every merged change that reaches the game and has not shipped yet, under Added / Changed / Fixed / Removed / Breaking. A pull request that changes `addon/` or `data/` adds a line here; a [[Release run]] moves the section under the new version and leaves it empty. Empty means there is nothing to release.
_Avoid_: next release notes, draft changelog
→ [Release → Writing changelog lines](operations/release.md#writing-changelog-lines)

**Pre-release version**:
A version with an `-alpha.N` or `-beta.N` suffix (`0.1.0-alpha.1`). It is published to CurseForge as an alpha or beta file and to GitHub as a pre-release; the next run counts N up. The project leaves alpha or beta only when the maintainer types a version for a [[Release run]].
_Avoid_: test build, nightly, snapshot
→ [Release → Versioning](operations/release.md#versioning)

**Package check**:
`wfj package-check`: the gate between building the release zip and publishing it. The zip must hold exactly the addon folder's tracked files (dotfiles such as `.gitkeep` excepted) plus `LICENSE` and `ATTRIBUTION.md` under one `WoWForeverJapanese/` folder, every file the TOC lists, the TOC version of this release, a numeric CurseForge project id, and no dependency field. Nothing leaves the runner until it passes.
_Avoid_: zip test, smoke test, `toc-check` (that compares the TOC's `## Interface` with `clients.toml`)
→ [Release](operations/release.md)
