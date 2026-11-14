# ADR-091: Voice at 64 kbps, pack parts and a new audio store

- **Status:** Accepted
- **Date:** 2026-11-14
- **Deciders:** the maintainer
- **Related:** [ADR-062](062-voice-cast-per-speaker-in-step-with-the-text.md) (the audio record, the audio repository, the entry and its packs) · [ADR-090](090-voice-in-sentences-with-real-timing.md) (voice in sentences, the MP3 lead, the timing step) · [Voice over](../systems/voice.md) · [Voice runbook](../operations/voice.md)

## Context

A player said on CurseForge that our voice sounds worse than the Spoken addon's. Our files were MP3, mono, 22.05 kHz, 32 kbps, the format forever-vo ships. At that bit rate the encoder cuts everything above about 8.3 kHz, so the voices sound dull. Spoken ships Vorbis at 44.1 kHz and about 46 kbps. The voice engine itself writes 24 kHz.

The distance from each encode to the master WAV, measured on the same lines (higher is closer):

| Encode (24 kHz, mono, CBR) | Distance to the master |
|---|---|
| 32 kbps | 15.4 dB |
| 48 kbps | 19.7 dB |
| 64 kbps | 25.9 dB |
| 80 kbps | 30.4 dB |

A better encode doubles the download, and that runs into three limits:

- **CurseForge** refuses an upload over 500 MB, and the pack build keeps every pack under 420 MB. At 64 kbps, Levels 1-10 and Levels 51-60 no longer fit.
- **GitHub** refuses a release asset of 2 GiB or more. The all-in-one download for players who install by hand would be about 2.8 GB.
- **The audio repository** (`zyaga/wow-forever-japanese-voice`) already held 4.4 GB of history. Pushing every file again in a new encode would double it, and GitHub refuses a push over 2 GB.

## Decision

1. **The encode is MP3 MPEG-2 layer III, 24 kHz, 64 kbps CBR, mono.** Levelled as before (one gain per take, peaks limited), with no Xing / Info frame. `voice_make.LAME` says so, and every new file is made that way. 24 kHz is the engine's own rate, so nothing is resampled; 64 kbps keeps its top end.
2. **Each record names its encode.** `data/voice/audio.jsonl` gains `encode` (`"mp3 24000 64"`). `tests/python/test_voice.py` fails a record in another encode.
3. **A re-encode from the masters.** `wfj voice reencode` (`make voice-reencode`) makes every file not in the current encode again from its archived WAV: CPU only, no model, no WAV written, resumable. The files are made first; the records (`bytes`, `sha256`, `encode`) are written under the voice run lock. A record with no archived WAV is listed and left alone: that line is voiced again. The timing does not change, because it is on the recording's clock, not the file's.
4. **The MP3 lead is read per file.** A decoded MP3 runs behind its WAV by LAME's encoder and decoder delay (1,105 samples) plus the levelling limiter's 5 ms look-ahead: 55 ms at 22.05 kHz and 51 ms at 24 kHz, measured by cross-correlating the decoded levelled MP3 against its WAV (`mp3_frames.LEAD`). The pack build and the timing step read each file's sample rate from its first frame and use that rate's lead, so files in both encodes are handled correctly during the change.
5. **A band may be split into parts by quest id.** A `pipeline/voice-packs.toml` row may take part of a level band with `quests = [first, last]`. The parts of one band together take every quest id, 1 to 99999, and keep the first pack's name with "(part N)". A quest is put in its band's part by its id; an NPC's talk goes with the lowest band of the NPC's quests, then the lowest quest id. New packs, each its own CurseForge project and folder:
   - **Levels 1-10 (part 2):** levels 6 to 10. Levels 1-10 now holds 1 to 5.
   - **Levels 51-60 (part 2):** level 60, quests 1 to 8509.
   - **Levels 51-60 (part 3):** level 60, quests 8510 on. Levels 51-60 now holds 51 to 59.
   The existing packs keep their folders, titles, slugs and projects. The entry requires the new packs, so the CurseForge app installs them with it.
6. **The all-in-one download comes in parts.** The GitHub release's zip of everything is written as numbered parts of whole pack folders, each under 1.9 GB (`<entry>-all-<date>-part<N>.zip`), or as one `-all-<date>.zip` when everything fits. The release notes say to unzip every part.
7. **The entry names its packs, and the addon names the ones missing.** The entry ships `Packs.lua`, which passes the list of its pack folders to the addon (`WoWForeverJapanese_ExpectVoicePacks`). Once per session at login, while voice is on and at least one pack loaded, the addon names in one chat line each listed pack that did not load (not installed, or turned off) and points to Update all in the CurseForge app or the AddOn List. An older entry with no list prints nothing.
8. **A new audio store.** A new private repository, `zyaga/wow-forever-japanese-voice-2`, holds only the current files. Its first push went up in batches under GitHub's 2 GB push limit. The main checkout's `build/voice/` is its checkout, and `pipeline/voice-audio-commit.txt` pins its commit. The Release workflow checks it out with its own read-only deploy key, in the secret `VOICE_REPO_2_KEY` (GitHub refuses one deploy key on two repositories). The old repository is left as it is, with its own key, `VOICE_REPO_KEY`; nothing writes to it any more.
9. **The rule for the store.** The store holds the current files and nothing else matters about its history. The record of the audio is the WAV masters (the archive) and the release zips. When the store's history grows too large again, a fresh repository starts the same way.

## Rationale

- 64 kbps is the step that closes most of the gap: 10.5 dB closer to the master than 32 kbps, where 80 kbps adds only 4.5 dB more for 25% more download.
- Re-encoding from the WAV masters keeps the audio one generation from the engine. Re-encoding the old MP3s would carry their lost top end into the new files.
- Splitting by quest id inside a band keeps every quest in one place without moving a player's existing packs: the old folders stay, they just hold less.
- A new store costs one clone and one secret. Rewriting the old repository's history would break every pin a past release points to; leaving it untouched keeps them valid and keeps a rollback simple.

## Consequences

- The voice sounds clearer. Every player downloads every pack again once, and the voice is about 2.8 GB in all instead of about 1.4 GB.
- Sizes at 64 kbps, under the 420 MB cap (the build warns at 315 MB): Levels 1-10 243 MB, Levels 1-10 (part 2) 260 MB, Levels 11-20 325 MB, Levels 21-30 264 MB, Levels 31-40 298 MB, Levels 41-50 300 MB, Levels 51-60 357 MB, Levels 51-60 (part 2) 236 MB, Levels 51-60 (part 3) 234 MB, Other 306 MB. Levels 11-20 and Levels 51-60 are past the warning mark.
- The three new packs need CurseForge projects before their first release; until then their rows carry `project_id = 0`.
- A player who updates the entry but not the new packs is told which packs did not load.
- Rolling back the store is reverting the change: the workflow then checks out the old repository with its old key at its old pin.
- A second machine sets up the store with `git clone` of the new repository into `build/voice`.

## Alternatives considered

- **48 kbps.** Smaller, but 6 dB further from the master than 64 kbps; the dull top end is still audible.
- **80 kbps.** Closer still, but more packs past the cap and a bigger download for a smaller step.
- **Vorbis, as Spoken ships.** The frame-exact snipping of ADR-090 is built on MP3 frames, and the timing tools and tests read MP3.
- **Re-encode into the old repository.** Its history would roughly double, and every clone would carry it.
- **Rewrite the old repository's history.** Breaks the pins of past releases.
