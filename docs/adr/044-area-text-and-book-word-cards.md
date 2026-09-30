# ADR-044: Area text as its own type, and word cards on plain-text book pages

- **Status:** Accepted. Implemented in `pipeline/wfj/core/model.py` (`FIELDS` /
  `ENGLISH_FIELDS` `area`), `pipeline/wfj/emit/schema.py` (`SLOTS` / `TYPES` / `FILE_PREFIX` `area`),
  `pipeline/wfj/cmd/import_english.py` (`run_wdb` writes `area`), `pipeline/wfj/cmd/check.py` (`NOT_IN_SCOPE`
  removed; `Scope.dotted`), `pipeline/wfj/core/status.py` (`DOTS`, `PROSE_KINDS`), `pipeline/wfj/cmd/validate.py`
  (`rule_objective` over `OBJECTIVE_INDEX_TYPES`; book lines owed), `pipeline/wfj/core/readings.py` (`TYPES["book"]`,
  `html_page`, `addon_keyed`), `pipeline/wfj/cmd/generate.py`, `pipeline/wfj/cmd/readings.py`,
  `pipeline/wfj/dev/translate_batch.py` (kind `area`), `pipeline/wfj/cmd/served.py`, `stats.py`, `import_draft.py`
  (`REVERIFY_TYPES`), `addon/WoWForeverJapanese/Core/Const.lua` / `Core/Data.lua` (`area`), `Core/Objectives.lua`
  (several sources), `Main.lua` (`BuildObjectiveIndex`), `UI/QuestMap.lua`, `Core/Readings.lua` (`split("book")`),
  `UI/ItemText.lua` (the page FontString, `page:spanRegion`), `UI/Readings.lua` (`itemtext` surface), `UI/Slash.lua`.
- **Date:** 2026-09-27

## Context

Two kinds of text had no path to Japanese or to a word card:

- **Area text.** The quest cache gives each quest an "area description": the text of an exploration or event
  objective ("Scout through the Fargodeep Mine", "Kernobee Rescue"). It was stored as English field `quest.area`
  but kept out of every check scope: the quest type has no Japanese `area` field, and folding it into the quest's
  scope would loosen the name / number checks and move the joined hash. So about 200 lines had English and no way to
  get Japanese.
- **Book pages.** Book, letter and plaque pages ship Japanese ([ADR-022](022-book-and-trainer-greeting-surfaces.md)),
  but took no word card
  ([ADR-036](036-readings-hover-word-lists.md)): the client draws a page in a SimpleHTML, and the word card needs
  `FontString:CalculateScreenAreaFromCharacterSpan` to find where a word sits. A SimpleHTML has no span API
  [verified: Forever 1.60.1.70009 `SimpleHTMLAPIDocumentation`: `GetTextData` gives `{ text, type, align }` only].
  Book and letter pages are read like prose, so they should take word cards.

The client gives no quest id with an objective line and no page id with a page: the addon finds both by the English
it is showing.

## Decision

1. **`area` is a translation type.** Field `text`, id = the quest id (a game id, [principle 5](../architecture/principles.md#5-every-translation-is-keyed-by-the-game)), row shape
   `{ text, h1, status }` like `objective`, numeric shards `Data/Area/Area_NNNN.lua`. English moves from
   `quest.area` to `data/english/area/` (same ids, hashes and sources); the WDB import writes it there. It is prose
   checked against its own English (`status.PROSE_KINDS`), drafted by the objective kind's rules (`translate_batch
   cut --kind area`, title-case like objective; a placeholder quest's area text is never drafted), re-verified on a
   client rewording (`REVERIFY_TYPES`), and kept by `served` exactly when its quest is.
2. **One objective index over objective and area rows.** `Objectives.build{ sources = { {type, rows}, … } }` indexes
   both by the 32-bit fingerprint (h1) of the English; an entry is its type and id, so equal ids across the types
   never collide. One fingerprint with different Japanese anywhere in the sources is ambiguous and never shown;
   `validate` (`rule_objective`) groups both types by h1 and refuses it, and prints each type's shipped count.
   `index:match` returns the row's type, and `QuestMap.showObjective` renders from that type.
3. **No claim about which screen shows area text.** Matching is by the English the client writes as an objective
   line, so the Japanese appears wherever that happens. The in-game checklist records where it appeared.
4. **Area text takes no readings.** No word cards on objective tracker or quest-log objective lines: the Alt key
   covers them.
5. **A plain-text book page showing Japanese is drawn in a FontString of the addon's.** `UI/ItemText` makes one
   FontString on the scroll child (first use), anchors it at the SimpleHTML's `TOPLEFT`, as wide as it, in the `P`
   text type's font and colour, and gives the SimpleHTML `""` while it shows. `refit` sizes the scroll child from the
   FontString (the SimpleHTML's offset + the string height + the client's 30 of padding, when taller than the
   frame). A client write (page turn, new item) hides it until Render draws the Japanese again. English (Alt, off,
   missing, release) and every HTML page (`<HTML`) go through the SimpleHTML exactly as before.
6. **The word card covers that FontString.** `page:spanRegion()` exposes it; `UI/Readings` resolves a record's
   region through it only while it holds exactly the text the record applied; `itemtext` joins `View.SURFACES`;
   `Core/Readings.split("book")` → `"book", "text"`.
7. **Book readings are stored by page id and shipped by English hash.** `readings.TYPES` gains `book`; records live
   in `data/reading/book/` keyed by page id (the id the Japanese store uses). `readings.addon_keyed` rewrites them to
   the key the addon looks a page up by, `book:<16-hex English hash>`, in `Data/Reading/Reading_book_<hh>.lua`. Pages
   sharing one English ship one Japanese row (the lowest page id's, as `lua_writer.keyed_rows` writes it; a stale
   page gives way to a current one), so only that page's reading ships.
8. **HTML pages never take readings.** `readings.html_page` excludes them from `readings export` and from the lines
   `validate` counts as owed: they keep the client's SimpleHTML, which cannot place a card.

## Consequences

- Area lines ship Japanese (name-only lines stay English). `/wfj debug objective` prints `shipped N (objective n · area n)`.
- An objective and an area row with one English must ship one Japanese; a drafted pair that disagrees is refused at
  `validate`, not discovered in game.
- There is no `quest.area`; anything that read it reads `data/english/area/`. The quest type's joined hash is
  unchanged (area was never in its scope).
- The book page is now laid out by the addon while Japanese shows: font, colour and width follow the `P` text type,
  and a long page scrolls by the addon's refit. A client layout the adapter does not mirror (another text type's
  font inside a plain-text page) is not reproduced; HTML pages are untouched.
- Book readings add a reading shard family; plain-text pages carry a word list with meanings. A
  translation change to a page makes its reading stale, as for any reading.
- Book translation batches write readings with meanings in the same round, as quest, gossip and UI batches do.

## Alternatives considered

- **Keep area text as `quest.area` and add a Japanese quest field.** Rejected: the quest's check scope and joined
  hash would change for every quest with area text, and the addon would need a quest id the objective line does not
  give.
- **A separate area index in the addon.** Rejected: the live line does not say whether it is an objective or area
  text; two indexes would each claim a line the other also matches. One index, one ambiguity rule.
- **Word cards on HTML pages** by measuring text in a hidden FontString. Rejected: the SimpleHTML's own layout
  (headers, alignment, images) cannot be reproduced faithfully, and a card over the wrong word is worse than none.
- **Replace the SimpleHTML on every page.** Rejected: HTML pages carry markup the FontString cannot draw.
- **Readings on area / objective lines.** Rejected (decision 4).

## Addendum: gossip leftovers (2026-09-27)

- **Every gossip key ships.** No gossip line is left showing the missing marker. A label with ordinary words is
  translated; a label that is only a name, a class or profession name, an internal string or a line in a made-up
  language ships as its English under `ruling: accept`, the mechanism UI lines such as "NEW" use, which `check`
  honours for gossip too.
- **Names inside a `$G` branch.** A gender-branched line is drafted as one neutral form; the names in either branch
  count as English the draft may keep, so a branch's names are never dropped ([principle 2](../architecture/principles.md#2-names-stay-in-english)).
