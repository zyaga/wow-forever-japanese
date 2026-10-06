# Runbook: make the voice pack

## Goal

Make the Japanese voice pack, `WoWForeverJapanese_Voice`, from the Japanese the addon ships, and copy it into the Forever client for a test. How it works: [Voice over](../systems/voice.md); decision: [ADR-061](../adr/061-voice-over-from-a-separate-pack.md). The pack is build output under `build/` and is never committed. It is not published yet.

## Prerequisites

- **AivisSpeech Engine 1.2.0** (the Apple Silicon build), unpacked into `build/aivis/` (gitignored), with the two voice models installed in it: 阿井田 茂 (male and narrator, style *Calm*) and morioki (female). Both are under the Aivis Common Model License 1.0.
- **`lame`** on the `PATH` (WAV to MP3).
- The pinned VMaNGOS database (`VMANGOS_DB`, commit `VMANGOS_SHA` in the Makefile), as for `make import-english`.
- The repo venv (`.venv`); `make` uses it when it exists, or pass `PY=<repo>/.venv/bin/python`.

## Steps

1. **Start the engine** and leave it running in its own terminal:
   ```bash
   build/aivis/macOS-arm64/run
   ```
   It listens on `http://localhost:10101`. Check it answers: `curl -s http://127.0.0.1:10101/version` prints `"1.2.0"`.
2. **Make everything:**
   ```bash
   make voice
   ```
   This runs the three steps below in order. Each can be run alone.
   - `make voice-speakers`: writes `data/voice/speakers.jsonl` and `data/voice/voices.jsonl` from VMaNGOS and the collector's NPC ids. Read its report: narrator lines, conflicts (two creatures for one line), scoped English with no Japanese, creatures with no known gender. The two files are data: commit them with the ticket, after `make validate` passes.
   - `make voice-generate`: makes `build/voice/<pack key>.mp3` and `build/voice/manifest.json`. Only lines whose Japanese, voice, style, pace or engine version changed are made again. It prints the numbers below.
   - `make voice-pack`: writes `build/voice-pack/WoWForeverJapanese_Voice/`. Lines whose Japanese changed since their file was made are left out and listed.
3. **Validate** the voice tables with the rest: `make validate`.

## Configuration

`pipeline/voice.toml`: the engine's address (`http://127.0.0.1:10101`), the pace (`speed_scale = 0.9`), and for each of `male`, `female` and `narrator` the model name and the engine's style id (from `GET /speakers`), plus the credits written into the pack's TOC and README. The pace is fixed when a file is made: the client has no playback rate, so changing it means making every file again.

The audio format is fixed in `wfj voice generate`: MP3, mono, 22.05 kHz, 32 kbps constant bitrate, with no Xing / Info header (`lame -t`).

## Test install

Copy both folders into the Forever client's AddOns folder, the main addon as usual and the pack beside it:

```bash
rsync -a --delete --exclude '.DS_Store' <worktree>/addon/WoWForeverJapanese/ \
  "<the Forever client's AddOns folder>/WoWForeverJapanese/"
rsync -a --delete --exclude '.DS_Store' <worktree>/build/voice-pack/WoWForeverJapanese_Voice/ \
  "<the Forever client's AddOns folder>/WoWForeverJapanese_Voice/"
```

A new addon folder is most likely only seen after a full client restart, not a `/reload` (unverified; it is on the checklist). After that, `/reload` picks up a new copy of either folder. The in-game steps: [Testing strategy → Voice over checklist](../testing/strategy.md#voice-over-checklist).

## Recovery

If the game's English NPC voices stay silent after a test (the dialog channel left off), the addon turns it back on at the next load. By hand:

```
/console Sound_EnableDialog 1
```

`/run print(GetCVar("Sound_EnableDialog"))` prints `1` when it is on. Removing the `WoWForeverJapanese_Voice` folder from AddOns removes all voice.

## Numbers

Measured on the first pack (Shadowglen, 2026-10-06), as `make voice-generate` prints them:

| Measure | Value |
|---|---|
| Lines | 48 (5,963 characters) |
| Time to make | 301.8 s: 19.8 characters a second, 2.85 times faster than playback |
| Audio | 860.3 s: 6.93 characters a second of speech |
| Size | 4,014 bytes a second of audio; the pack is 3,453,491 bytes |

Projected from those rates:

| Scope | Characters | Time to make | Audio | Size |
|---|---|---|---|---|
| Quest and gossip text | 3.88 million | about 54.5 h | about 155 h | about 2.25 GB |
| Everything | 4.65 million | about 65 h | about 186 h | about 2.7 GB |

The maintainer heard the 22.05 kHz, 32 kbps files as a little different from the 44.1 kHz, 64 kbps research samples. The sample rate and bitrate are chosen in the packing ticket; doubling the bitrate brings the whole game to about 4.5 GB.

## Open work

- Generating every line, splitting the pack, hosting it, and its sample rate and bitrate (the packing ticket).
- Not voiced: quest objectives, audio per class or race (the player's name, class and race are spoken as 冒険者), the trainer window's text, the character's own spoken error lines.

## Related

- [Voice over](../systems/voice.md) · [ADR-061](../adr/061-voice-over-from-a-separate-pack.md) · [Local setup](local-setup.md) · [Testing strategy](../testing/strategy.md#voice-over-checklist) · [Research](../research/2026-10-04-japanese-voice-over.md)
