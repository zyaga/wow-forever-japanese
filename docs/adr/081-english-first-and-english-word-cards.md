# ADR-081: English first, and English word cards from the readings

- **Status:** Accepted
- **Date:** 2026-11-11
- **Deciders:** the maintainer
- **Related:** [Principle 3: Japanese by default, English one key away](../architecture/principles.md#3-japanese-by-default-english-one-key-away) · [Principle 4: the addon never ships stored English](../architecture/principles.md#4-the-addon-never-ships-stored-english) · [ADR-002](002-live-english-only.md) (live English) · [ADR-018](018-reveal-key-override-binding.md) (the reveal key) · [ADR-036](036-readings-hover-word-lists.md) and [ADR-039](039-word-meanings-written-in-context.md) (readings and meanings) · [ADR-069](069-saved-word-list.md) and [ADR-071](071-study-the-word-list-in-game.md) (the word list and studying it) · [Settings](../systems/settings.md) · [Readings](../systems/readings.md#english-word-cards) · [Data model](../architecture/data-model.md)

## Context

The addon was built for people who want the game in Japanese: players who read it, and learners of Japanese. Japanese players already use it the other way too, to study English. They play with the reveal key held, or with translation off, and switch to check a line. Neither fits. Holding a key for a whole session is tiring, and with translation off there is no Japanese to check against and no word card.

Everything such a player needs is already in the addon. The Japanese of each line ships. The readings give, for each Japanese word, the meaning of that word as the sentence uses it (倒して: "defeat"). The word list and the study card exist. What was missing is a way to put the English first and still reach the Japanese, and a card for an English word.

Three limits shaped the answer:

- The addon never ships the game's English text. English on screen is what the client shows.
- The toggle contract is one language at a time, one key, no dual display.
- The settings pages had grown to fill one fixed screen each, with a separate page for the voice panel only because the voice page was full. One more row on the main page did not fit.

## Decision

- **A direction, as the exact mirror.** One setting, `direction`: `ja` (Japanese first, the default, the addon as it was) or `en` (English first). English first leaves the client's live English untouched on every surface the addon translates and shows the Japanese while the reveal key is held. Same key, one language at a time, every surface.
- **One predicate, one event.** Whether English is what shows is the direction crossed with the held key: `State.showsEnglish()`, and `Modifier.english()` for the polled key. State fires `language(english)` whenever that flips, by key or by direction; `modifier` stays the key alone. The translator answers `leave` with `{ english = true }` when English shows. Only the key's own modules (`Core/Modifier`, `Core/State`, `UI/RevealBinding`, `UI/KeyCapture`, `UI/Slash`, `Main.lua`) may read the held key, and a test enforces it, so no surface can follow the key and miss the direction.
- **The voice does not change.** A Japanese line never starts while English shows. In English first it is heard only while the key is held.
- **English word cards from the readings, with no model pass.** A reading entry holds the meaning of its Japanese word in that sentence. Turned around, that says which English word of the line the Japanese word stands for. `generate` pairs each line's English words with its Japanese words from those meanings (by a crude stem, the meaning as written first, then its bracketed plainer sense; a word goes to the first Japanese word that claims it). The card shows the English word, how it is said, the Japanese word with its reading, and that word's dictionary form when it differs.
- **A row shape that keeps the game's sentences out of the addon.** Per line, the addon is handed only the set of single English words that found a Japanese word: lower-cased, sorted by word, each with the 1-based place of its Japanese word in the same line's reading row (`kill=2`). Never the sentence, never its order, no word the Japanese has no word for, no name and no code. Tests hold every shipped row to that shape and check that no shipped file holds a line of the game's English.
- **A common word list.** Some everyday words (you, after, again) often have no single Japanese word in a given sentence. `data/english/common-words.jsonl` gives 161 of them one Japanese word and reading each, machine-drafted, with provenance on every line. A card falls back to it when the line's own row has no pair.
- **Words that take no card.** The articles, the bare forms of be, have and do, and to, of, in, on, at, for, as, by, than, off, upon. Japanese has no word for an article, and the others only mean something with the words around them. Names take none: a capitalised word inside a sentence is a name, and names stay English.
- **Pronunciation from the CMU Pronouncing Dictionary, as a pipeline input.** The dictionary (cmusphinx/cmudict, pinned at commit `74790861f652b15e4ac49015a90074ad62a27690`) is fetched into `build/` and read on the maintainer's machine only. Only derived spellings, for words a card can show, are committed (`data/english/pronunciation.tsv`) and shipped (`Data/English/English_Pron.lua`). `generate` reads no network. The dictionary's notice is in `ATTRIBUTION.md`.
- **Dictionary-style spelling.** The pronunciations are respelled the way Japanese-English dictionaries write them: i for the vowel of "sit", e for "bed", əːr for "bird". That is the spelling the card's readers learned, and every letter of it is in the bundled font; a test holds the letter set to the font.
- **English entries in the word list.** In English first the save click saves the English word: its pronunciation, the Japanese word, the English sentence the client showed and the Japanese sentence that holds the Japanese word, keyed `<kind>:<id>:en:<word>`. It stays in the player's own saved word list and is never shipped. The study card asks it English first.
- **Book pages.** The client draws a page itself, in a widget with no way to measure a word. In English first the addon draws the client's own plain-text page, word for word, in its own text widget in the page's font and colour, so its words can take cards, as it already does for the Japanese page.
- **The welcome window asks once.** The first-login window becomes two pages. Page one asks what the player is here for: Study Japanese, Study English or Just play. Confirm writes three ordinary settings (the direction, the word cards, the study tab) and nothing is written before it. It is asked once of every player, existing ones included, since nobody has answered it; showing it changes no setting. It can be opened again from the settings pages or with `/wfj intro`.
- **Settings pages scroll.** Each page's rows sit in the client's scroll frame, with more room between sections and shorter explanations. The voice panel's settings join the voice page. Every page but About has a Defaults button that resets that page's own settings only. The side-by-side rows stay.

## Consequences

- A Japanese player studying English gets the whole tool turned around: live English, Japanese one key away, a card on English words, and saving and studying English words.
- Japanese first is unchanged. A player who never touches the setting sees one thing only: the welcome window's question, once.
- About 91.2% of the English words that can take a card get one (644,987 word occurrences across quest, gossip, interface and book lines; 42,663 lines carry a row). [Coverage](../operations/coverage.md) has the numbers per surface, regenerated with the data.
- The pairs are not checked by a person. A hand-judged random sample of 300 pairs found about 4% loosely wrong, most often a phrase's head word standing for the whole phrase. A wrong pair shows a related Japanese word of the same line, not a word from elsewhere.
- `Data/English/` adds about 6.7 MB on disk to the download, and the memory to hold it in game.
- The addon's files now hold English words, which they did not before: single words per line, sorted, a common list and a pronunciation table. The game's text cannot be read back from them, and the tests keep it so.
- A player's saved word list can hold English sentences the client showed that player. They stay on the player's machine.
- A page the client marks up as HTML takes no English cards, the same as for the Japanese cards. Neither does a letter a player wrote, text holding a `|` escape, or any page while translation or the books area is off. The voice panel's English view and Dialogue UI's windows take none.
- In English first the Japanese voice is silent unless the key is held. A player who wants to hear Japanese while reading English has no setting for it.
- A word the dictionary does not have shows its card without a pronunciation. The dictionary gives North American pronunciations only.
- After a batch or re-pull that changes English or readings, `make pronunciation` is one more step before `make generate`.
- Existing players are interrupted once by the welcome window. Defaults on a page is two clicks away from resetting that page, so it asks for the second click within five seconds.

## Alternatives considered
- **A model pass per line, pairing English and Japanese words.** Rejected: it costs a pass over every line and again on every change, and the meanings already written for the Japanese cards say the same thing. It would give no better pairs than reading them off the meanings.
- **A direction per surface** (English quests, Japanese tooltips). Rejected: one rule is what makes the key predictable, and every surface would need its own setting and its own tests.
- **A "show both" display.** Rejected: the contract is one language at a time, and it stays.
- **International phonetic letters.** Rejected: the bundled font and the client's fonts cannot draw three of them (the vowels of "sit", "bed" and "bird"), and the dictionary-style spelling is the one the readers know.
- **Shipping the dictionary, or looking words up at run time.** Rejected: only the words a card can show are needed, and the addon has no network.
- **Shipping each line's English with its word pairs.** Rejected: the addon never ships the game's text. The sorted set of single words is enough for the card, because the sentence is already on screen.
- **The client's generated one-column settings layout.** Rejected: the side-by-side rows (the areas in three columns, the checkbox pairs) are easier to scan and stay; only the fixed height had to go.
- **Asking the question only of new installs.** Rejected: players who already have the addon include the ones studying English, and they would never learn the setting exists.
