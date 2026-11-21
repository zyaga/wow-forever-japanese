# ADR-103: NPC lines are never read in the narrator's voice

- **Status:** Accepted
- **Date:** 2026-11-21
- **Deciders:** the maintainer
- **Related:** [ADR-062](062-voice-cast-per-speaker-in-step-with-the-text.md) (a voice per speaker, audio in step with the text) · [ADR-074](074-voices-cloned-from-the-games-npc-voice-sets.md) (every voice cloned from a game voice set) · [ADR-055](055-forever-vo-captures-as-an-english-source.md) (forever-vo's captures) · [ADR-089](089-the-head-is-drawn-from-a-display-id.md) (display ids) · [ADR-065](065-collector-keeps-only-what-the-addon-cannot-show.md) (what the Collector keeps) · [ADR-003](003-ship-stale-with-marker.md) (markers) · [Voice over](../systems/voice.md) · [Collector](../systems/collector.md) · [Voice over runbook](../operations/voice.md)

## Context

A voiced line whose speaker no source could name was read by the narrator, one voice (the tauren male elder). 3,062 of 16,108 voiced lines were the narrator's. 1,320 of those were quest lines said by an NPC nobody had named, mostly quests the Forever client added, so a human priestess spoke as an old tauren man.

Casting had the same fault one step later. An NPC whose race or gender nobody knew was cast on a catch-all voice (a human man).

Both are guesses a player hears as wrong. A line with no voice is better than a line in the wrong voice.

## Decision

1. **The narrator reads only what no creature says.** A quest's offer is the narrator's only when a source says an object or item starts the quest. Its progress and turn-in text are the narrator's only when a source says an object ends it (the VMaNGOS table `gameobject_involvedrelation`, read by `io/vmangos.read_object_ends`). Book and letter pages are unchanged.
2. **A quest line nobody names is not voiced.** It has no row in `data/voice/speakers.jsonl`. The speakers report lists it as `<key>: nobody named, not voiced`.
3. **The order of the sources for a quest line's speaker.** The Collector's quest NPCs (what a player's own quest window showed) win over everything. Then Spoken's corpus, then the VMaNGOS database, then forever-vo's captures, then DonData.
4. **DonData is a speaker source** (approved by the maintainer, 2026-11-21). DonData (github.com/WoW-Forever-Addons/dondata) publishes two quest files, read by `pipeline/wfj/io/dondata.py`:
   - `Data/ATT_Quests.lua`, derived from AllTheThings' Forever database (MIT licence, copyright AllTheThings WoW Addon): quest givers, and the quests an item starts.
   - `Data/Extra_Quests.lua`, DonData's own (GPL-3.0): the NPC a quest is turned in to (a row with no NPC id, or the id 0, is a turn-in at an object), more givers, and more item starts.

   Only quest ids and creature ids are read. No text of either file is stored. It is used only for a quest line no other source names. `make voice-dondata-fetch` downloads both files at DonData's newest commit into `build/dondata/<commit>/` and records the commit in `pipeline/dondata-commit.txt`, which is committed. When DonData cannot be reached, the recorded commit is used again. A row's provenance source is `dondata@<first 7 of the commit>`. Both projects are credited in `ATTRIBUTION.md`.
5. **A creature nobody can cast gets no voice.** A creature the VMaNGOS database lacks takes its race and gender from its display id in `data/voice/displays.jsonl` (read from the client's creature cache) through the client's display tables. A creature that still has no known race or no known gender, no voice set from Spoken and no ruling gets no row in `data/voice/voices.jsonl`. A line whose main speaker has no voice row makes no audio file. `wfj voice cast` prints how many such creatures there are, and `validate` reports them without failing.
6. **Audio that is owed is listed, and the change merges before it is remade.** `pipeline/voice-owed.txt` (written by `make voice-owed`) lists one file stem per line for every voice file that is missing or was made in another voice or from other Japanese. The audio gate (`test_audio_in_step`) holds the committed data to that list: every file out of step must be listed, and a listed file that is in step fails, so the list empties itself when the audio is remade. The pack build leaves a file that is not in step out of every pack, so no line plays audio made in another voice. A recording of a line that is silent now is kept on the record, never packed, and never remade until its speaker has a voice. The maintainer decided to merge this change first: one remote voice run later covers these lines together with other pending lines.
7. **The Collector keeps who gives and takes each quest.** A new entry kind, `questnpc`, stores for every quest offer, progress or turn-in panel shown, under `questnpc:<quest id>:<field>`, the text `<creature id>:<sex>:<display id>`: the NPC's creature id, its sex as the client's `UnitSex` gives it (2 male, 3 female, 0 not known) and the display id this client drew it with when the voice panel has seen it (0 not known). Numbers only, no English, never the GUID. It is stored whether or not the line ships Japanese or was voiced. Like NPC names, these entries hold no line to translate: they are never counted as unsent lines and ride along with a send that carries at least one line. The collector import writes them to `data/voice/quest-npcs.jsonl`, which the speakers step reads first.
8. **The window says when a translated line has no voice yet** (approved by the maintainer, 2026-11-21, as an allowed on-screen addition). A new marker, `[音声なし / No Voice Yet]`, shows on the window's banner like the stale and missing markers. It shows only when a voice pack is loaded, voice and that line's kind are on, Japanese is showing, the line ships Japanese, the voice entry lists the line as having no voice, and no loaded pack carries it. One setting, `voice.mark` ("Mark lines with no voice yet"), on by default, turns it off. The voice entry's `Packs.lua` gains a guarded second call, `WoWForeverJapanese_VoiceNotMade({ … })`, with the pack keys of the lines that ship Japanese and that no pack carries.

## Consequences

- On the committed data, 806 quest lines moved from the narrator to a named NPC, 100 more are confirmed as the narrator's (an item or object), and 514 quest lines are left with nobody named.
- Of 2,823 speaking creatures, 2,654 have a voice and 169 have none; their 402 lines are not voiced. 48 creatures gained a voice, 4 lost a guessed one, and 1 was recast to its real race and gender.
- 406 files are owed a remake. Until the next voice run, those lines are silent in a newly built pack, and 916 recordings of lines that are silent now stay on the record unused.
- Fewer lines are voiced than before, on purpose. A player with a voice pack sees the message on those lines and can turn it off.
- The entry's `Packs.lua` grows by the list (1,320 keys today, about 33 KB). An entry with nothing to list is byte for byte what it was. An addon without the function skips the list, and an older entry with no list shows no message.
- An older addon version that loads a saved Collector file with `questnpc` entries drops the unknown kind without an error.
- Every send from a player now improves the cast: the Collector's quest NPCs name speakers no public data has, and they win over every other source.
- The repository gains one more outside source to credit and one more pinned commit to keep (`pipeline/dondata-commit.txt`).
- Rolling back is reverting the change. No audio is deleted by it.

## Alternatives considered

- **Keep the narrator for unnamed lines.** It keeps every line voiced, but an NPC is heard in a voice that is plainly not theirs. That was the fault to fix.
- **Keep the catch-all voice for creatures of unknown race or gender.** The same fault, one step later.
- **Questie's data as a speaker source.** Considered and not used: its licence text is unclear for older contributions.
- **Hold the change until its audio is remade.** A remote voice run for these lines alone costs a second run. Listing the owed files lets the change merge with the gate still exact, and one later run covers them with other pending lines.
- **Say nothing on screen for a silent line.** A player with a voice pack could not tell a line with no voice yet from a fault. The message says so, and one setting hides it.
