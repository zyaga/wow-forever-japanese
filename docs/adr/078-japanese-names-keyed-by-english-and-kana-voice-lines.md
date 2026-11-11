# ADR-078: Japanese names keyed by their English, and kana lines for the voice

- **Status:** Accepted
- **Date:** 2026-11-10
- **Deciders:** the maintainer
- **Related:** [Principle 2: names stay in English](../architecture/principles.md#2-names-stay-in-english) · [ADR-036](036-readings-hover-word-lists.md) (readings) · [ADR-061](061-voice-over-from-a-separate-pack.md) and [ADR-074](074-voices-cloned-from-the-games-npc-voice-sets.md) (the voice) · [Data model](../architecture/data-model.md) · [Translation batches](../operations/translation-batches.md) · [Voice runbook](../operations/voice.md)

## Context

Names stay in English on screen, and that does not change here. Two other needs call for a Japanese form of every name:

- **The voice.** The engine reads the line the addon ships, with player tokens as 冒険者 and numbers filled in (`voice.speech_text`). It guesses the reading of kanji and gets some wrong, and it reads an English name inside a Japanese line as Latin letters. The readings in `data/reading/` already give the reading of every kanji word of almost every voiced line; nothing gives a name's.
- **A later names setting**, off by default, that shows a Japanese name for a player who wants one. All of its data should exist before that setting is built, so that work is only screen work.

A name is shared. "Ashenvale" is a zone, a faction's word, part of creature and item names, and a run of Latin letters in dozens of quest lines. Some names have no game id the addon could key them by: a name inside prose is only text. Blizzard has an official Japanese for many of these names in Hearthstone (its card names), which a Japanese player may already know.

## Decision

- **One line per distinct English name**, in `data/name/name-NN.jsonl`, keyed by the 16-hex hash of the normalized English (the same hash primitive as the rest of `data/`). Each line holds the English, the game ids that carry the name per kind (`unit`, `item`, `spell`, `object`, `area`, `faction`, `map`), whether it was seen in shipped prose, the Japanese, its reading in hiragana, `free` (translated rather than spelled word by word), `status` (`missing` or `trusted`) and provenance. One line per English name makes one Japanese per name everywhere by construction.
- **Collected, never pruned.** `wfj names collect` gathers every English name from `data/english` (item, spell and unit names), the VMaNGOS database (creature, game object, area, faction and map names) and the runs of Latin letters in shipped Japanese prose and the voiced error lines. It adds lines and ids; it never removes a line or changes a Japanese name.
- **Hearthstone first.** A name that is exactly a Hearthstone card's English name, with katakana Japanese, takes that Japanese (provenance `human`, `hearthstone@<build>`). Hearthstone's card files are a build-time input (HearthstoneJSON, a pinned build, kept under `build/`), never committed; only the names derived from them are.
- **The model drafts the rest, with a glossary.** `data/name/words.jsonl` holds English proper-noun words with one Japanese spelling each, seeded from Hearthstone's card names and then drafted before the names (`wfj names export-words` / `import-words`). The names are drafted in batches (`wfj names export` / `import`) with the glossary words as hints. `wfj names check` reports any name that spells a checked word another way, unless the name is `free` or a Hearthstone whole name. Machine output never replaces a `human` or `correction` name.
- **Kana lines as voice input.** `data/voice/kana.jsonl` holds, for every voiced line, the line as the voice should read it in kana only: `speech_text` with each reading word replaced by its reading, each English name by its Japanese (its katakana kept as written, the rest from its reading, so a word is spelled one way wherever it is said), each English comma by 、, and each number spelled out with its counter. Each row carries the hash of the Japanese it was made from (`voice.text_hash`, the hash an audio fingerprint starts with). A line the builder cannot finish keeps a model-written kana line for the same hash. Nothing reads the kana lines yet; a later remake of the audio will.
- **Tables generated, not loaded.** `make generate` writes `addon/WoWForeverJapanese/Data/Names/Names_<NN>.lua` (`{ Japanese, reading, English }` per hash, `trusted` names only). They are not in the TOC, so the client never loads them until the names setting does.
- **Always current.** Every flow that brings English or changes shipped Japanese runs `make names` (collect, then kana). Data tests fail while a name has no Japanese, while an English name from `data/english` or shipped prose has no line, and while a voiced line has no kana line made from its current Japanese.

## Rationale

- Keying by the English is the only key that covers every place a name appears, including prose, and it makes "one Japanese per name" a property of the store rather than a check.
- Hearthstone's Japanese is Blizzard's own and the spelling a Japanese player is most likely to recognise. Taking it whole only where the English matches exactly keeps a guess out; the glossary carries its spelling into the names Hearthstone does not have.
- Drafting the glossary words before the names means every batch spells a shared word the same way, and the check holds later batches to it.
- Writing the kana lines now, from the readings and names already in the repository, lets the audio remake be a pure audio change.

## Consequences

- Nothing a player sees or hears changes: every screen, every voice file, `data/voice/audio.jsonl`, the pack keys, the Japanese hashes the addon checks and the TOC stay as they were.
- The addon folder carries name tables nothing loads. They cost disk space in the download, not memory in game.
- The generated `Data/Names/` tables hold each name's English. Names stay English on screen, so this is the text the client already shows; the tables are the one place generated Lua carries English.
- Every data flow has one more step, and a new English name (a re-pull, a collector send, a translation that leaves a name in prose) fails the data tests until a names round drafts it.
- An English name used for several things gets one Japanese for all of them ("Orgrimmar" is a zone, a faction and several game objects). That is the intent; two things can only have different Japanese names when their English names differ.
- A kana line goes stale with its Japanese, like a reading: the next `make names` rebuilds it, and a drafted one has to be drafted again.

## Alternatives considered
- **Keying by game id per kind** (a creature's name under its creature id, an item's under its item id). Rejected: the same name would be stored once per id and kind, its Japanese duplicated and free to drift apart, and a name inside prose has no id to key it by.
- **No Japanese name data until the names setting.** Rejected: the voice needs the names now, and the setting should need no data work of its own.
- **Leaving kanji and names to the engine.** Rejected: it misreads some kanji and spells English names letter by letter; the readings and names in the repository already know better.
- **Hearthstone for every name, by word.** Rejected: Hearthstone translates some descriptive names and spells others out, so a word-by-word assembly would mix styles. Its whole names are taken where they match exactly, and its words guide the drafts.
