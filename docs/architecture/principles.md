# Principles

These are the rules the addon and the pipeline never break. Tests and CI gates enforce most of them; the rest are
checked in review. A change that needs to bend one of them is a decision, recorded in an [ADR](../adr/).

## 1. Blizzard API only

The addon depends on no other addon and embeds no library (no Ace3, LibStub, LibDataBroker and so on). When it
needs a helper, it has its own. The pipeline uses the Python standard library; a new dependency needs an ADR.
See [ADR-004](../adr/004-zero-runtime-dependencies.md). One addon's windows get the Japanese when the player
already has that addon: Dialogue UI's ([ADR-073](../adr/073-dialogue-ui-windows-get-our-japanese.md)). Nothing of it
is shipped or required, and without it that code does nothing.

## 2. Names stay in English

The English names of people, places, creatures, items, spells, zones and factions are never replaced, hidden or
transliterated: not in quest text, tooltips, nameplates or titles. Japanese is for prose. A Japanese name could
only ever be an extra line that the player turns on, never a replacement and never on by default.

Race and class words are the one exception, and only inside translated prose: there they are written in katakana
(`Druid` → ドルイド, `Night Elf` → ナイトエルフ), as the [translation style guide](../content/translation-style-guide.md) describes, because
they are ordinary words in the sentence. On interface labels they stay English.

## 3. Japanese by default, English one key away

A translated line shows in Japanese. Holding the reveal key (Alt by default, any key can be set) shows the game's
English instead. One switch turns the whole addon off. There is no "show both" mode for game text; the one window
that shows both languages is the welcome window below, which holds only the addon's own words.

The contract has a **direction**, one setting ([ADR-081](../adr/081-english-first-and-english-word-cards.md)).
**Japanese first** is the default and is the paragraph above. **English first** is its exact mirror, for a Japanese
player studying English: the client's English stays untouched on every surface the addon translates, and holding
the reveal key shows the Japanese. It is still one language at a time and the same key. One predicate decides which
language shows (the direction crossed with the held key), and every surface asks it; no code but the key's own
modules reads the key.

The only other things the addon adds to the screen, each of which a player can turn off or which shows only once:

- the **stale marker**, on a line whose English changed since it was translated;
- the **missing-translation marker**, on a line with no Japanese yet (not on compact rows such as the quest
  tracker);
- the **word card**: pointing at a Japanese word in quest or NPC prose, a plain-text window label or a plain-text
  book page shows its reading and, where there is one, its dictionary form and a short English meaning. Nothing is
  drawn until the pointer is on a word, and never while English is showing. In English first its mirror is the
  **English word card**: pointing at an English word in the same places shows how it is said and the Japanese word
  the translation uses for it in that line, with its reading;
- the **minimap button** that opens the fix-report window;
- the **welcome window**, shown once to every player (a first install at its first login, a player who already had
  the addon the first time a version with the question loads): it asks what the player is here for (study Japanese,
  study English or just play), writes three ordinary settings on Confirm and nothing before, and then names the
  reveal key, the word cards, the minimap button and, while the voice is not installed, where to get it. It is the
  one window in both languages, each Japanese line with its English, since the player has not learned the reveal
  key yet. It never shows by itself twice; the settings pages and `/wfj intro` open it again.

A line without a translation shows the untouched English the client wrote.

## 4. The addon never ships stored English

English on screen is always what the client is showing at that moment. The addon ships Japanese and hashes of the
English it was translated from, never the English text itself. The exceptions are the word card's short meaning
of a single word, which may use the game's own word where it matches, but never a whole line of the game's text,
and a link's label inside a Japanese interface line ("[Loot]", "[Click To Upgrade]"), kept byte for byte as part of
the link the client draws and the player clicks ([ADR-067](../adr/067-ui-lines-with-links-colour-wrapped-names-and-plural-groups.md)).
The English word card adds one more, with the same limit
([ADR-081](../adr/081-english-first-and-english-word-cards.md)): per line, the single English words that found a
Japanese word, lower-cased and sorted by word, each with the place of its Japanese word; a list of everyday words;
and how each such word is said. Never a sentence, never the words in their order, so the game's text cannot be read
back from the addon's files. An English word a player saves in English first is kept with the English sentence the
client showed them, in their own saved word list on their machine, which is never shipped.
`lint-no-english-in-addon` and a data test check this. See [ADR-002](../adr/002-live-english-only.md).

## 5. Every translation is keyed by the game

A translation is addressed by a game ID (quest, item, spell, creature, objective) or, for text the server sends
without an ID of its own (NPC gossip, book pages as the client shows them), by a hash of the English text. Never
by array position, insertion order or a parallel index. Duplicate keys are reported and resolved by a stated rule,
never silently. See [ADR-001](../adr/001-id-keyed-data-with-per-field-provenance.md) and
[ADR-005](../adr/005-gossip-key-fingerprint.md).

## 6. Provenance on every line, people over machines

Every entry in `data/` records where it came from: its class (`human`, `correction`, `machine`), who or what
produced it, and which English it was made from. Machine output fills gaps and replaces machine output. It
replaces a human translation only through an explicit, recorded ruling on that line; `wfj validate --base` fails a
change that would do otherwise. See [ADR-011](../adr/011-provenance-layers-and-completeness.md) and
[ADR-012](../adr/012-human-decisions-survive-regeneration.md).

## 7. Generated files are never edited by hand

The Lua data under `addon/WoWForeverJapanese/Data/` is built from `data/` by `make generate`. Edit `data/` and
regenerate; `wfj validate` regenerates and fails on any difference. See
[ADR-008](../adr/008-generated-data-layout.md).

## 8. Rendering apart from data

`Core/` holds lookup, data and state and never touches a frame (`lint-core-gate`). `UI/` does the drawing and
reaches data only through a lookup call.

## 9. Claims about the client need a source

How a Blizzard API, event or frame behaves on the Forever client is stated only with a source: Blizzard's own UI
code from the client, its API documentation, or an in-game check. Code comments cite the file and line.
