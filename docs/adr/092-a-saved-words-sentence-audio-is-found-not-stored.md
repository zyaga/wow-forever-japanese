# ADR-092: A saved word's sentence audio is found, not stored

- **Status:** Accepted
- **Date:** 2026-11-15
- **Deciders:** the maintainer
- **Related:** [ADR-069](069-saved-word-list.md) (the word list) · [ADR-071](071-study-the-word-list-in-game.md) (the study card) · [ADR-090](090-voice-in-sentences-with-real-timing.md) (voice in sentences, the timing) · [ADR-061](061-voice-over-from-a-separate-pack.md) (voice from separate packs) · [Study](../systems/study.md) · [Word list](../systems/word-list.md) · [Voice over](../systems/voice.md)

## Context

A saved word keeps the Japanese sentence it was shown in, its kind and its id ([ADR-069](069-saved-word-list.md)). The study card shows that sentence, and the word list window exports it for Anki. Neither could play it.

Since [ADR-090](090-voice-in-sentences-with-real-timing.md) the voice packs ship each voiced line as sentence files, with a timing string that says when each part of the Japanese is spoken. That is enough to play one sentence of a line on its own: the study card can speak the saved sentence in its NPC's recorded voice, and the export can hand the same files to Anki.

Two things had to be settled. Where the link from a word to its audio lives: stored with the word when it is saved, or found when it is needed. And how the card plays it: through the voice queue that plays window lines, or on its own.

Constraints:

- The word list is account-wide SavedVariables. Its shape is `schema = 1`; a change of shape needs a migration, and an older addon version drops the table it does not know.
- Words saved before this feature should get audio too.
- A line whose Japanese changed after its audio was made must stay silent, as everywhere else in the addon.
- An addon cannot copy files, and Anki reads sounds only from its own media folder.

## Decision

1. **Nothing about audio is stored with a word.** `WFJ_Words` keeps its fields and `schema = 1`. When the study card or the export asks, `UI/StudyVoice.find(entry)` works it out from the entry's `kind`, `id` and sentence (an English word's `jaSentence`):
   - only quest offer, progress and turn-in, gossip (greetings among them) and book pages are voiced; any other kind has no audio;
   - `Voice.packKey(kind, id)` and `Voice.record(key)` give the line's main recording: its sentence files with their lengths, its timing, its Japanese hash and its pack folder (`Voice.record` is read only);
   - the recording's hash must equal the shipped line's hash;
   - the saved sentence is found in the line as this character's window shows it, and `VoicePanelText.timedParts` maps the timing onto it;
   - the files played run from the one holding the sentence's first spoken part to the one holding its last, with a stop time when the next sentence starts inside that last file. A sentence that starts partway through a file plays that file from its start, since the client can start a sound only at its start. A pack with no timing plays a sentence only when it is the whole line.

   When nothing is found the answer says why: `kind`, `nopack`, `missing`, `stale`, `notfound` or `untimed`. The card hides its button for the first two and greys it with that reason for the rest.
2. **The card plays alone.** `PlaySoundFile` on the Master channel, each file started by the pack's lengths with `C_Timer.After`, cut with `StopSound` at the stop time. No voice queue, no voice panel, no dialog mute, no lowered volumes, and the line's main voice only. One voice at a time: starting it stops the voice line playing, and a voice line starting stops it. It plays on the card's back only: on the front it would say the word's reading before the answer. A setting, `voice.study` (on by default, on the Voice settings page), plays it as the answer shows; the button plays it whatever the setting says.
3. **The export names the same files.** With Include audio ticked (offered only with a voice pack), `Words.export` adds an `Audio` column of Anki sound tags, `[sound:wfj-<file>]`, one per file, and the word list window shows copy lines for the player's system (Mac `cp`, Windows `copy /Y`), one per distinct file, to paste in a terminal opened in the client's `_forever_` folder. They copy each file into Anki's media folder under `wfj-<file>`. `Core/Words` takes the cell as a callback and stays pure.
4. The project's principles ([principle 3](../architecture/principles.md#3-japanese-by-default-english-one-key-away)) name the study card's playback and the export's file names among the allowed additions: they play and name only pack audio whose Japanese hash equals the shipped line's, and carry pack folder and file names, never English.

## Rationale

- Finding the files at use costs a hash, a plain-text search and a walk over one line's timing: nothing a player notices on a card. Storing them would make every word carry data that goes stale when a pack is rebuilt or a line retranslated.
- The shipped line and the loaded packs are already the source of truth for every other voice line. Checking the hash at use gives the card the same guarantee: audio made from other Japanese never plays.
- Words saved before the feature, and words saved with no pack installed, get their sentence as soon as a pack is there.
- The voice queue serves window lines: it holds a speaker, a panel page and the English for the reveal key, and it mutes the game's dialog. A study card in a quiet moment needs none of that, and putting it in the queue would make the panel show a line no window opened.

## Consequences

- No migration, and nothing changes for an older addon version reading the list.
- The card's answer can change under a word: a pack update or a retranslation that keeps the sentence keeps the audio; one that changes the sentence makes it `notfound`, and a pack older than the Japanese makes it `stale` until the packs are updated.
- **A sentence that names another of the player's characters** is not found: the line is filled in for the character playing now, so the button is greyed with `notfound` on another character. Rare, and the card says why.
- A saved sentence that starts partway through a sentence file is heard with the end of the sentence before it.
- **In Anki, a sentence that shares its last file with the next sentence plays the whole file there.** Anki cannot stop a sound partway; the card in game stops at the sentence's end.
- A line said by differently cast NPCs plays its main voice on the card, which may not be the voice the player heard. The speaker is not saved with the word.
- The player copies the sound files by hand, as for the screenshots. The `wfj-` prefix keeps them clear of other decks' media, and copying again overwrites the same names.
- The clip chain is a second small timer chain beside the voice player's; the voice player's is tied to its queue state.

## Alternatives considered

- **Store a voice link with each word** (pack key, file offset, Japanese hash, speaker) at save time. A new `WFJ_Words` field and a schema change for every entry; words saved earlier or without a pack get nothing; the link goes stale with every pack rebuild or retranslation and needs the same checks at use anyway. The speaker alone would serve one rare case (a line several voices say).
- **Play through the voice queue.** The panel would show a line no window opened, the game's dialog would be muted for a study card, and the card's sound would wait behind window lines or interrupt the panel's state.
- **Anki file names as the pack has them, unprefixed.** Short names like `4641-description-2.mp3` could clash with another deck's media in the same folder. The prefix costs nothing, since the copy lines name the target anyway.
