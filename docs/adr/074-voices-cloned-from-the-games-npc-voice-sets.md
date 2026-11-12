# ADR-074: Voices cloned from the game's own NPC voice sets

- **Status:** Accepted
- **Date:** 2026-11-06
- **Deciders:** the maintainer
- **Related:** [ADR-061](061-voice-over-from-a-separate-pack.md) (the voice packs) · [ADR-062](062-voice-cast-per-speaker-in-step-with-the-text.md) (casting) · [Voice over](../systems/voice.md) · [Voice runbook](../operations/voice.md) · [Research](../research/2026-10-04-japanese-voice-over.md)

## Context

The voice packs used 40 ready-made AivisSpeech voices, cast by race, gender and age. They are clean but generic: two NPCs the game voices differently can share a voice, and none sounds like the NPC players know. The game gives most humanoid NPCs one of its NPC voice sets: each playable race and gender has two or three, recorded by different actors, with their barks in `sound/creature/<set>/` of the client archive. Forever adds four sets of its own for the Skyborne elves, with no folder name. Other voice-over addons for this client (forever-vo, Spoken) clone those sets.

A listening test on 2026-11-06 compared Qwen3-TTS and Irodori-TTS cloning six sets into Japanese. The maintainer preferred Qwen3-TTS, with the speaker-embedding-only copy for male sets and the full copy for female sets. Making the whole game this way takes about 8 to 10 days on the maintainer's Mac, so waiting for all of it before shipping anything was rejected.

A male Skyborne elf on Zephras Isle was heard in a female voice. The cause was the gender this project had judged from the NPC's text, which was wrong for him.

## Decision

- **Engine.** Every Japanese voice line is made with Qwen3-TTS 1.7B Base (Apache-2.0), cloned from a game voice set's own greeting, farewell and vendor barks read out of the local client archive. Runs go to rented GPUs on Modal (L40S) by default; `VOICE_LOCAL=1` runs the same engine on the maintainer's Mac instead. The cut barks and the joined set references stay under `build/voice-sets/` on the machine. For a remote run the joined references are sent to the rented GPU containers for that run only: they sit in the container's `/tmp` and are not kept there. They are never archived, never committed, never pushed to the audio repository and never shipped. A test fails if any `.ogg` or `.wav` file is tracked outside `tests/`.
- **Dependency.** The pipeline itself gains no dependency. For local runs, Qwen3-TTS and its PyTorch stack live in their own virtual environment (`build/qwen/venv`, `qwen-tts` pinned to 0.1.1, `make voice-qwen-setup`), run as a separate worker process the pipeline talks to over a pipe. Only one local run may use it at a time; its speed can be changed while it runs (`make voice-speed SPEED=slow|fast`: one engine in the background tier while the machine is in use, three at full speed while it is free). For remote runs, the `modal` client lives in its own environment (`build/modal/venv`, `make voice-modal-setup`) and runs `pipeline/wfj/io/qwen_modal.py`, which the pipeline never imports; the containers install the same pinned `qwen-tts`. The `whisper` command-line tool is a dev-only dependency: it wrote the clip transcripts (`wfj voice sets catalogue`).
- **Which set each NPC speaks with.** Taken exactly as the Spoken voice addon (github.com/rusty-key/spoken-wow) assigns it, from Spoken's committed line corpus, fetched into `build/spoken/` and never committed. Every run that makes audio takes Spoken's newest corpus first and records its commit in `pipeline/spoken-commit.txt`; when Spoken cannot be reached, the recorded commit is used again and the run says so. `data/voice/creature-sets.jsonl` records it per creature and gender, with provenance `spoken@<commit>`. Spoken's gender for those NPCs wins over the gender this project judged from text.
- **Who speaks each quest line.** Spoken's corpus also names the NPC that says each quest line it voices (accept, progress, complete). Where it names one creature for a line, that creature speaks the line here too, ahead of the VMaNGOS database and the players' captures, so a player with both addons hears one NPC, not two. `data/voice/speakers.jsonl` records such a line with provenance `spoken@<commit>`. A line Spoken gives to an object or an item, to two creatures, or does not have, is left to the other sources, and the narrator reads it when they name nobody.
- **The 72 sets.** 56 NPC sets: the 52 race, gender and flavour sets with folders in Forever's archive, plus the four Skyborne sets Forever adds, each named after its NPCSounds row and cut from that row's greeting and farewell kits. 16 player sets (`<race><sex>playernpc`) for the character's own error lines (below). `data/voice/sets.jsonl` has one row per set (72 rows) and lists each set's clips with an English transcript made with the `whisper` speech-to-text tool, hand-fixed where a lore word was misheard.
- **Picks.** Each set has a pick in `pipeline/voice.toml`: voice-only (the speaker embedding), or full copy (the voice and the way it speaks). The starting picks are voice-only for male sets and full for female sets. The maintainer makes and changes picks on a local listening page; a pick marked decided records a verdict by ear.
- **Packs switch** through `cloned_packs` in `voice.toml`. A creature follows its home pack (the lowest level band of the quests it starts or ends), so each creature has one voice in every pack. Levels 1-10 was switched first, then Levels 11-20 as a test, then every other pack, Other included. Every pack (Levels 1-10 through Levels 51-60, and Other) is cloned now: all 16,180 voice files.
- **No other voice.** Every voice file is a cloned game voice (the maintainer, 2026-11-06: no AivisSpeech for any line). The AivisSpeech code is still in the pipeline, but nothing is cast to it, and `test_no_committed_speaker_is_cast_to_anything_but_a_game_voice_set` fails if anything is. Speakers Spoken gives no set take one from `[[set_cast]]` rules in `voice.toml` on their race, gender and archetype (ogres an orc guard, dragons and elementals the tauren elder, robots the zany gnome, and so on; a creature shown as both genders gets a set for each). The narrator and the book reader speak with a named set (`narrator_set`, `book_narrator_set`: the tauren male elder). The character's own error lines are cloned from the player character's own English error recordings for each race and sex (sets `<race><sex>playernpc`, the first 16 clips of `sound/character/<race>/…errormessages/`); Skyborne characters use the Skyborne NPC sets.
- **One loudness.** Every take is levelled to the same loudness (EBU R128, -20 LUFS, one linear gain measured with ffmpeg's `ebur128` filter, peaks limited to -2 dBFS) when it is encoded, so no NPC is louder than another. A silent take, or one shorter than 400 ms, is too short to measure and is left as it is. `wfj voice relevel <run>` re-encodes recorded files from a run's kept WAVs.
- **Where it runs.** `make voice-generate` reads the cloned lines on rented GPUs (Modal, L40S) in batches and archives every run's uncompressed WAVs, with a `SHA256SUMS` file, to the archive folder set privately in `VOICE_WAV_ARCHIVE`; the references are not archived. If archiving fails, the run still imports, and `wfj voice generate --prepared <run> --archive <dir>` archives it later. `VOICE_LOCAL=1` reads the lines on the maintainer's Mac. A line the engine cannot read is left for the next run instead of ending the run.
- **Credit.** Each pack's README credits "Speech engine", "Voices" and "Licences". For cloned voices the licence line is "speech engine Apache-2.0; the game's NPC recordings the voices are modelled on belong to Blizzard Entertainment". The README also says the maintainer ran the engine on their own computer and on rented GPUs, and that no hosted speech service was used. No actor is named.
- **Rights.** The voices are modelled on the publisher's recordings, which no licence covers. The maintainer decided on 2026-11-06 to ship them as forever-vo and Spoken do: non-commercial, credited, no actor named. During a remote run the joined references, cut from those recordings, are sent to the rented GPU containers for that run only and are not kept there. On a takedown request, the affected voice packs are withdrawn (removed, or not released) until the maintainer decides what follows.

## Rationale

- Players know these NPCs by their English voices. A Japanese voice cloned from the same set sounds like the same NPC, and NPCs the game voices differently sound different.
- Spoken already maps NPCs to sets for this client. Deriving the mapping again from the client's display tables would give a second answer to keep in step with the first, and the project's own text-judged gender was the cause of the Skyborne error. Using Spoken's assignment as data, pinned and with provenance, keeps one answer.
- A separate environment keeps PyTorch out of the pipeline, which stays on the standard library.
- Switching pack by pack ships the starting zones in about two days of generation instead of waiting for the whole game.

## Consequences

### Positive
- NPCs sound like their English selves, and a male NPC is never heard in a woman's voice: a cloned NPC takes the set's gender, and `validate` fails when a creature is cast to a voice of the other gender.
- The fingerprint of a cloned file names the engine, set, mode and reference, so a new pick, new clips or a fixed transcript remakes only that set's lines.
- A whole-game run (`--scope all --players all`, what `make voice-generate` runs) drops record rows for files no line uses, so `data/voice/audio.jsonl` lists exactly the shipped files; `test_audio_in_step` fails on an unused record.

### Negative
- Each run costs money on the rented GPUs. On the maintainer's M1 Pro, the local fallback is about 2 to 3 times slower than real time, so a local run of a whole pack is a long background run.
- An engine to keep working, with its own environments (local and remote) and model download.
- The game's audio leaves the machine during a remote run: the joined references go to the rented GPU containers for that run.
- The mapping follows Spoken's corpus: a new pin can move NPCs between sets, and their lines are remade.
- The rights position rests on the publisher's tolerance, not a licence. On a takedown request the affected packs are withdrawn.

## Alternatives considered

- **Keep AivisSpeech only.** Generic voices; the maintainer wanted better.
- **Derive each NPC's set from the client's display tables** (`CreatureDisplayInfo.NPCSoundID` through `NPCSounds` to the set folder). Planned first and dropped by the maintainer during implementation: Spoken's assignment already exists, and a second derivation would disagree with it in places with no way to say which is right.
- **Irodori-TTS (Japanese only).** Less accent from English barks, but judged worse by ear and still accented on the human male set.
- **Hosted TTS.** Ruled out: no hosted speech service is used.
- **A rented GPU.** Chosen: Modal L40S is the default for runs, with the maintainer's Mac as the fallback (`VOICE_LOCAL=1`). The engine, model and worker code are the same on both.
- **Japanese recordings from other Blizzard games (Hearthstone).** Named heroes only, not the generic voice sets most quest givers use.
