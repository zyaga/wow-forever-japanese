# ADR-036: Readings: word lists keyed to the Japanese, shown on hover

- **Status:** Accepted. Implemented in `pipeline/wfj/core/readings.py`, `pipeline/wfj/cmd/readings.py`,
  `pipeline/wfj/cmd/validate.py` (`rule_readings`, rule 8), `pipeline/wfj/cmd/generate.py`,
  `pipeline/wfj/emit/lua_writer.py` (`reading_text`), `pipeline/wfj/emit/schema.py` (`reading_relpath`, `TOC_ORDER`),
  `addon/WoWForeverJapanese/Core/Readings.lua`, `UI/Readings.lua`, `UI/Render.lua`, `Core/Settings.lua`
  (`readings.enabled`), `UI/Options.lua`, `UI/Slash.lua`, `data/reading/`. The word-reading box is one of the allowed
  on-screen additions ([principle 3](../architecture/principles.md#3-japanese-by-default-english-one-key-away)). The
  in-game checks of the shipped build are in the readings checklist in [Testing strategy](../testing/strategy.md).
- **Date:** 2026-09-25

## Context

A learner wants the reading of a kanji word without it cluttering the text. The toggle contract allowed only two
on-screen additions, the stale and missing markers, and inline `漢字(かんじ)` clutters every line, so it was ruled out.

The client has the primitive for drawing over a word: `FontString:CalculateScreenAreaFromCharacterSpan(left, right)`
returns one rectangle per line a span covers, relative to the FontString's `BOTTOMLEFT`
(`blizzard_sharedxml/scrollingmessageframe.lua:496–503`). An in-game demo on quest 456 (Forever 1.60.1) showed:

- The call works on the quest window's FontStrings while they show our Japanese.
- Its indices are **UTF-8 bytes with the right end exclusive**: Blizzard passes `#text + 1` for "to the end of the line"
  (`scrollingmessageframe.lua:451, :459, :467`).
- **A span that splits a UTF-8 character makes the client exit.** It is not a Lua error, so `pcall` cannot catch
  it.
- A small box above the hovered word, with the word tinted, reads well, including a word wrapped onto the next line,
  and while the text scrolls.
- Readings drawn above **every** word while a key is held overlap the line above at the game's line spacing.

## Decision

1. **Readings are their own data type**, `data/reading/<type>/` (types `quest`, `gossip`, `ui` and the others
   [ADR-044](044-area-text-and-book-word-cards.md) adds; the translation store's sharding), one record per shipped
   Japanese line: `{id, field, ja_hash, words, provenance}`. `words` is an ordered list of `[word, whole reading]`;
   `ja_hash` is the addon's hash primitive over the Japanese as stored. The Japanese is never copied or edited.
2. **Whole words only** (少し → すこし, 生き物 → いきもの). No per-kanji readings: only a show-everything mode would
   need them.
3. **Word checks** at import and in `validate`: each word sits in the Japanese in order after the previous one, holds a
   kanji, holds no ASCII character (names stay English, [principle 2](../architecture/principles.md#2-names-stay-in-english);
   and the generated row packs pairs with ` ` and `=`), and has a kana-only reading (hiragana, katakana, ー). A word
   entry that carries a meaning may be a kana word ([ADR-039](039-word-meanings-written-in-context.md)).
4. **A reading whose Japanese changed, or whose line no longer ships, is stale**: `validate` prints it (not a failure)
   and `generate` leaves it out, so a rejected or withdrawn line never stops a build. A malformed record or a duplicate
   fails `validate` and `generate`.
5. **Provenance** `machine` (with `model`, source `readings@<batch>`) or `correction`. Machine output never replaces a
   `correction` reading (kept and reported by `wfj readings import`).
6. **The model writes readings** through `wfj readings export` → words → `wfj readings import`. No morphological
   analyser in the pipeline. Every translation batch also writes its lines' readings. The export leaves out a line
   with nothing to annotate (no kanji and no kana run beyond a bare particle or copula: names joined by a particle, an
   English-only title); `validate` counts a kana-only line as owed.
7. **Generated rows pack one string per field**: `["<type>:<id>"] = { <field> = "word=reading word=reading …" }` in
   `Data/Reading/Reading_<type>_<shard>.lua`, loaded last in the TOC's generated block. A Lua string per word and per
   reading cost more than the Japanese itself, in file size and client memory.
8. **Hover only**, on quest and gossip prose: the quest window's detail / reward / progress / greeting panels, the quest
   map's details pane and its popup, and the gossip window's greeting row; and plain-text labels in every window
   ([ADR-041](041-word-cards-on-window-labels.md)): a `ui` record whose FontString has the span call, whose parent is
   not a Button or a protected frame, and whose surface is not a non-window surface (`View.NON_WINDOW`: tracker, HUD
   labels, alerts, error / combat text, tooltips, …). `Render.sync` attaches after an apply and detaches on every
   restore, release, forget and stale drop, so the box can never show while English shows. One mouse-motion-only
   cover frame per FontString; on mouse enter it re-checks that the FontString still shows the attached text, then
   measures the word rectangles fresh.
9. **One guarded call site.** `UI/Readings.lua`'s `spanAreas` is the only caller of
   `CalculateScreenAreaFromCharacterSpan` in the addon (a pytest enforces it). It refuses any index not on a UTF-8
   character boundary, an out-of-range span, and any text containing `|`.
10. **One setting**, `readings.enabled`, default on ("Show readings when hovering a word" /
    「単語にカーソルを合わせると読み方を表示」).

## Consequences

- Translations and readings change independently. A corrected translation drops its reading until it is written again.
- Readings cannot carry a name: a name is English, and a word with no kanji or with an ASCII character is refused.
- Tooltips get no readings: a tooltip belongs to whatever the mouse is on, so it cannot be hovered. A plain-text book
  page showing Japanese is drawn in a FontString of the addon's and takes readings; an HTML page (a SimpleHTML, not a
  FontString) gets none ([ADR-044](044-area-text-and-book-word-cards.md)).
- Text containing `|` gets no readings until the client's byte counting around escape sequences is measured.
- `Render`, the path every surface goes through, gains two calls; both are no-ops outside the listed surfaces.
- **Size.** Packed rows are about 0.94× the Japanese they annotate on disk. Readings for every shipped quest and gossip
  line add about 9.7 MB of addon memory in game, within the 10 MB budget. Trimming (a leaner row, load-on-demand) is
  revisited once every surface is translated.
- A word entry may also carry the word's dictionary form and its meaning in the sentence
  (`[word, reading, dictionary form, its reading, meaning]`), shown in a word card instead of the box
  ([ADR-039](039-word-meanings-written-in-context.md)).

## Alternatives considered

- **Markup inside the translation** (`{少|すこ}し`): collides with the `{name}` placeholders and with the `[`, `]` and `|`
  already in the Japanese, and would make every translation edit a reading edit.
- **Readings above every word while a key is held**: overlaps the line above at the game's line spacing (seen in
  game). Dropped.
- **Inline `漢字(かんじ)`**: rejected; it clutters every line.
- **A morphological analyser** (MeCab / UniDic, with JmdictFurigana): a pipeline dependency with licence obligations
  (JmdictFurigana is share-alike), word-level only, and weaker on game vocabulary than the model with the sentence in
  hand.
- **A JLPT / kanji-grade cutoff**: with hover, the reader picks the word.
- **Character indices** for the span call: what crashed the trial build.
