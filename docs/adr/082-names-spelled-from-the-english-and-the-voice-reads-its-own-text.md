# ADR-082: Names spelled from the English, and the voice reads its own text

- **Status:** Accepted. Supersedes in part [ADR-078](078-japanese-names-keyed-by-english-and-kana-voice-lines.md): how a name's Japanese is written, and what the voice is made from.
- **Date:** 2026-11-11
- **Deciders:** the maintainer
- **Related:** [Principle 2: names stay in English](../architecture/principles.md#2-names-stay-in-english) · [ADR-074](074-voices-cloned-from-the-games-npc-voice-sets.md) (cloned voices) · [ADR-062](062-voice-cast-per-speaker-in-step-with-the-text.md) (audio in step with the text) · [Data model](../architecture/data-model.md) · [Translation batches](../operations/translation-batches.md) · [Voice runbook](../operations/voice.md) · [Voice over](../systems/voice.md)

## Context

Names stay in English on screen. The voice still has to say them, and it reads Japanese only. ADR-078 gave every English name a Japanese form, following Hearthstone's official Japanese where Hearthstone had the name or its words, and drafting the rest in the same style. Many of those names were translated rather than spelled: "Black Dragonflight" was 黒いドラゴンフライト, "Tiger" was トラ. A player reads "Black Dragonflight" on screen and hears "kuroi doragonfuraito", which is not what the screen says.

Listening tests on the cloned voices found four other ways a line came out wrong, none of them in the shipped Japanese itself:

- The engine reads Latin letters in a Japanese line by guessing, so an English name with no Japanese form is mangled.
- A space right before a kanji makes the engine's text splitter break that kanji into pieces it has no sound for (素晴らしい came out three different wrong ways).
- The player stand-in 冒険者 was sometimes misread in kanji.
- A few single kanji that stand alone as a word (金, 獣, 証 and some others) were read with the reading they have inside compounds (金 as きん, not かね).

Each reading also started from fresh random draws at the engine's default temperature, so nothing held a voice set's sound the same from one line to the next.

## Decision

- **A name is spelled, never translated.** Every English word has one katakana spelling in `data/name/words.jsonl`, and every name's Japanese is put together from the spellings of its words by code (`wfj.core.respell`), with its reading in hiragana. The rules: a leading "The" is left out; a plural s is dropped in the word's spelling; "of" is オブ and the other small words are spelled too; a possessive keeps its sound (Hallow's End is ハロウズ・エンド); words are joined with ・; a tag in brackets is left out; a roman numeral becomes a digit, except as the first word; a single letter is read by its letter name (2P is 2ピー); digits stay digits; `&` is アンド. No name is `free` any more.
- **Hearthstone's Japanese is respelled too.** A name or word taken from Hearthstone is written from the English like every other one: the voice must say what the screen shows in English, in Japanese sounds (Tiger is タイガー, not トラ). A Hearthstone katakana spelling of a word that matches stays as that word's spelling. This is the maintainer's explicit decision to let machine output replace wording marked `human`. A player's own correction (`correction` provenance) is never respelled.
- **New names spell themselves.** `make names` runs `collect`, `learn-spellings` (a word with no spelling takes it from a katakana name with as many parts as words), `respell`, then the kana lines. A new English name whose words all have a spelling is written with no drafting. A name with a word nobody has spelled stays unfinished, and the names tests fail, until that word is drafted (`wfj names export-respell` / `import-respell`). `wfj names check` reports every name that is not the spelling of its words.
- **The voice reads its own text.** What the engine reads is built by `wfj.core.voice_text` from the spoken line (`voice.speech_text`): each English name replaced by its katakana, a half-width or full-width space before a kanji removed, the player stand-in written ぼうけんしゃ, and the single kanji listed in `pipeline/voice.toml` `[text] kana_words` written in kana where the line's reading record lists them as a word on their own with that reading. The rest of the line stays in kanji. The on-screen Japanese, the shipped keys and the Japanese hashes the addon checks do not change.
- **The fingerprint follows the engine text.** A cloned file's fingerprint also holds the hash of the engine text when it differs from the spoken line, so a respelled name remakes exactly the lines that say it, and a line the fixes leave alone keeps its fingerprint. A test fails when any voiced line would hand the engine Latin letters.
- **Steadier clones.** `pipeline/voice.toml` `[clone]` reads every cloned voice at `temperature = 0.5` (the engine's own value is 0.9) and, with `seed = true`, starts every reading of a voice set from one number made from the set's name (its crc32). Both are part of the fingerprint. Every cloned file was remade with these settings.

## Rationale

- Spelling from the English is the only rule under which the voice says the name the player is reading. A translated name, however good, is a different name to the ear.
- Building names from words in code, rather than drafting whole names, makes "one spelling per word" a property of the data, and a bad spelling is one line to fix.
- Fixing the engine's input, not the shipped Japanese, keeps the screen and the readings as they are and keeps every fix out of the player's way.
- Putting the engine text in the fingerprint remakes only the lines a change touches, so a respelled word costs the lines that say it, not the game.
- A lower temperature and one seed per voice set were heard against the defaults on the same lines and held a voice together from line to line without making it flat.

## Consequences

- Nothing on screen changes. Names stay English; the names setting, when it is built, will show these spellings.
- Some names that read naturally in Japanese as a translation are now in katakana (タイガー). That is the intent.
- Every cloned voice file was remade once, for the respelling, the engine text fixes and the new clone settings.
- A remade line on Modal is not byte for byte the same as an earlier take of it, because a paragraph's random draws depend on the other paragraphs in its batch. Read one paragraph at a time on the maintainer's machine, a line read twice came out identical in the one check made; that is not tested beyond it.
- Changing `[clone]` remakes every cloned file. Changing `[text] kana_words` remakes the lines that hold the word.
- `data/voice/kana.jsonl` stays and is rebuilt from the respelled names, but the audio is not made from it.
- Every names round now has one more drafting step for new words, and a new word fails the data tests until it has a spelling.

## Alternatives considered

- **Keep following Hearthstone's Japanese.** Rejected: where Hearthstone translates (トラ for Tiger) the voice says a word the player does not see. Its katakana spellings are kept where they match.
- **A second, kana-only version of each audio file, alongside the current one.** Rejected: one version per line per voice is the rule, two versions double the cost and the packs, and the player would have to pick between them.
- **Hand the engine an all-kana line** (the kana lines of ADR-078). Rejected: the listening tests found the engine reads kanji words right apart from the few listed in `kana_words`, so only the words proved to come out wrong are written in kana and the rest of the line is left as the engine reads it.
- **Keep the engine's default temperature and no seed.** Rejected: heard on the same lines in five voices, the lower temperature with one seed per voice set sounded as lively and more like one speaker from line to line.
