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

- **Engine.** Japanese voice for NPCs with a game voice set is made locally with Qwen3-TTS 1.7B Base (Apache-2.0), cloned from that set's own greeting, farewell and vendor barks read out of the local client archive. The barks stay on the machine (`build/voice-sets/`); they are never committed, never pushed to the audio repository and never shipped. A test fails if any `.ogg` or `.wav` file is tracked outside `tests/`.
- **Dependency.** Qwen3-TTS and its PyTorch stack live in their own virtual environment (`build/qwen/venv`, `qwen-tts` pinned to 0.1.1), run as a separate worker process the pipeline talks to over a pipe. The pipeline itself gains no dependency. Only one run may use it at a time; its speed can be changed while it runs (one engine in the background tier while the machine is in use, three at full speed while it is free).
- **Which set each NPC speaks with.** Taken exactly as the Spoken voice addon (github.com/rusty-key/spoken-wow) assigns it, from Spoken's committed line corpus at a pinned commit (`SPOKEN_COMMIT` in the Makefile), fetched into `build/spoken/` and never committed. `data/voice/creature-sets.jsonl` records it per creature and gender, with provenance `spoken@<commit>`. Spoken's gender for those NPCs wins over the gender this project judged from text.
- **The 56 sets.** The 52 race, gender and flavour sets with folders in Forever's archive, plus the four Skyborne sets Forever adds, each named after its NPCSounds row and cut from that row's greeting and farewell kits. `data/voice/sets.jsonl` lists each set's clips with an English transcript from a local speech-to-text model, hand-fixed where a lore word was misheard.
- **Picks.** Each set has a pick in `pipeline/voice.toml`: voice-only (the speaker embedding), or full copy (the voice and the way it speaks). The starting picks are voice-only for male sets and full for female sets. The maintainer makes and changes picks on a local listening page; a pick marked decided records a verdict by ear.
- **Packs switch** through `cloned_packs` in `voice.toml`. A creature follows its home pack (the lowest level band of the quests it starts or ends), so each creature has one voice in every pack. Levels 1-10 was switched first, then Levels 11-20 as a test, then every other pack, Other included.
- **No other voice.** Every voice file is a cloned game voice (the maintainer, 2026-11-06: no AivisSpeech for any line). Speakers Spoken gives no set take one from `[[set_cast]]` rules in `voice.toml` on their race, gender and archetype (ogres an orc guard, dragons and elementals the tauren elder, robots the zany gnome, and so on; a creature shown as both genders gets a set for each). The narrator and the book reader speak with a named set (`narrator_set`, `book_narrator_set`: the tauren male elder). The character's own error lines are cloned from the player character's own English error recordings for each race and sex (sets `<race><sex>playernpc`, the first 16 clips of `sound/character/<race>/…errormessages/`); Skyborne characters use the Skyborne NPC sets.
- **One loudness.** Every take is levelled to the same loudness (EBU R128, -20 LUFS, one linear gain, peaks limited to -2 dBFS) when it is encoded, so no NPC is louder than another; `wfj voice relevel <run>` re-encodes recorded files from a run's kept WAVs.
- **Where it runs.** `make voice-generate` reads the cloned lines on rented GPUs (Modal, L40S) in batches and keeps every run's uncompressed WAVs on the maintainer's archive drive; `VOICE_LOCAL=1` reads them on this machine.
- **Credit.** Each pack's README names every engine its files were made with (AivisSpeech, Qwen3-TTS or both) and, for cloned voices, "voices modelled on the game's own NPC voice sets". No actor is named.
- **Rights.** The voices are modelled on the publisher's recordings, which no licence covers. The maintainer decided on 2026-11-06 to ship them as forever-vo and Spoken do: non-commercial, credited, no actor named. If asked to take them down, the packs go back to the AivisSpeech audio kept at the previous audio pin.

## Rationale

- Players know these NPCs by their English voices. A Japanese voice cloned from the same set sounds like the same NPC, and NPCs the game voices differently sound different.
- Spoken already maps NPCs to sets for this client. Deriving the mapping again from the client's display tables would give a second answer to keep in step with the first, and the project's own text-judged gender was the cause of the Skyborne error. Using Spoken's assignment as data, pinned and with provenance, keeps one answer.
- A separate environment keeps PyTorch out of the pipeline, which stays on the standard library.
- Switching pack by pack ships the starting zones in about two days of generation instead of waiting for the whole game.

## Consequences

### Positive
- NPCs sound like their English selves, and a male NPC is never heard in a woman's voice: a cloned NPC takes the set's gender, and `validate` fails when an NPC on the AivisSpeech cast has a voice of the other gender.
- The fingerprint of a cloned file names the engine, set, mode and reference, so every AivisSpeech file is untouched, and a new pick, new clips or a fixed transcript remakes only that set's lines.
- Switching the next pack is one line in `voice.toml`, a recast and a generation run.

### Negative
- Generation is about 2 to 3 times slower than real time on the maintainer's M1 Pro, so each pack is a long background run.
- A second engine to keep working, with its own environment and model download.
- The mapping follows Spoken's corpus: a new pin can move NPCs between sets, and their lines are remade.
- The rights position rests on the publisher's tolerance, not a licence. The fallback is kept ready.

## Alternatives considered

- **Keep AivisSpeech only.** Generic voices; the maintainer wanted better.
- **Derive each NPC's set from the client's display tables** (`CreatureDisplayInfo.NPCSoundID` through `NPCSounds` to the set folder). Planned first and dropped by the maintainer during implementation: Spoken's assignment already exists, and a second derivation would disagree with it in places with no way to say which is right.
- **Irodori-TTS (Japanese only).** Less accent from English barks, but judged worse by ear and still accented on the human male set.
- **Hosted TTS or a rented GPU.** Hosted services are ruled out (local generation only). A rented GPU stays possible later; it does not change this decision.
- **Japanese recordings from other Blizzard games (Hearthstone).** Named heroes only, not the generic voice sets most quest givers use.
