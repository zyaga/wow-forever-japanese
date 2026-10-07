# Runbook: make and release the voice

## Goal

Make the Japanese voice from the Japanese the addon ships, copy it into the Forever client for a test, and release it. The voice ships as the **Voice entry**, `WoWForeverJapanese_Voice` (no audio; on CurseForge it requires every pack, so the app installs them all from one click), and seven **packs** named for what they hold: `WoWForeverJapanese_VoiceLevels1to10` through `…Levels51to60`, and `…Other`. How it works: [Voice over](../systems/voice.md); decisions: [ADR-061](../adr/061-voice-over-from-a-separate-pack.md), ADR-062. The audio and the packs are build output under `build/` and are never committed; only the audio record, `data/voice/audio.jsonl`, is.

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
   - `make voice-pack`: writes the entry and every pack under `build/voice-pack/`, split by `pipeline/voice-packs.toml` (below), and prints each pack's lines, files, size and room left under the 420 MB cap. Lines whose Japanese changed since their file was made are left out and counted. A pack past 315 MB is marked; a pack past 420 MB stops the build and nothing is written.
3. **Validate** the voice tables with the rest: `make validate`.

## Configuration

`pipeline/voice.toml`: the engine's address (`http://127.0.0.1:10101`), the pace (`speed_scale = 0.9`), and for each of `male`, `female` and `narrator` the model name and the engine's style id (from `GET /speakers`), plus the credits written into the pack's TOC and README. The pace is fixed when a file is made: the client has no playback rate, so changing it means making every file again.

The audio format is fixed in `wfj voice generate`: MP3, mono, 22.05 kHz, 32 kbps constant bitrate, with no Xing / Info header (`lame -t`).

## Which pack holds a line

`pipeline/voice-packs.toml` is the split: the entry, then one row per pack with its folder, CurseForge title, slug, project id (0 until the project exists) and the quest levels it holds.

| Line | Pack |
|---|---|
| A quest's offer, progress or turn-in text | The band holding the quest's level. The level is Forever's own, read from the pinned quest cache (`make voice-pack` passes it); VMaNGOS gives it for a quest the cache has not answered. |
| An NPC's talk (gossip, greetings) | The lowest band of the quests that NPC starts or ends; an NPC with none goes to Levels 1-10. |
| A line that shows another line's audio (a female wording, a repeated quest's text) | The pack of that line, where its file is. |
| Book and letter pages, the character's error lines, quests with no known level or above 60 | Other. |

A line's pack depends only on that line, so new lines never move old ones, and a fix re-releases only the pack it is in. When a pack nears the cap, it is split by a new row in the table, a new CurseForge project and a new entry file (see "Adding a pack"), never by moving lines silently.

## Test install

Copy the main addon as usual, then the entry and every pack beside it, as the CurseForge app would install them:

```bash
rsync -a --delete --exclude '.DS_Store' <worktree>/addon/WoWForeverJapanese/ \
  "<the Forever client's AddOns folder>/WoWForeverJapanese/"
for d in <worktree>/build/voice-pack/WoWForeverJapanese_Voice*/; do
  rsync -a --delete --exclude '.DS_Store' "$d" "<the Forever client's AddOns folder>/$(basename "$d")/"
done
```

A new addon folder is most likely only seen after a full client restart, not a `/reload` (unverified; it is on the checklist). After that, `/reload` picks up a new copy of either folder, new sound files included: a file added to the installed pack's `Sound` folder while the client ran played after a `/reload` (checked in game). The in-game steps: [Testing strategy → Voice over checklist](../testing/strategy.md#voice-over-checklist).

## Recovery

If the game's English NPC voices stay silent after a test (the dialog channel left off), the addon turns it back on at the next load. By hand:

```
/console Sound_EnableDialog 1
```

`/run print(GetCVar("Sound_EnableDialog"))` prints `1` when it is on. Removing the `WoWForeverJapanese_Voice` folders from AddOns removes all voice.

## Releasing the voice

The voice is released from the maintainer's Mac, by one command, because the audio is not in git. It is a separate step from the main addon's [release](release.md), and a separate explicit ask.

### One-time setup

| # | Step | Notes |
|---|---|---|
| 1 | Create the eight CurseForge projects, as World of Warcraft addons: "WoW Forever Japanese Voice (日本語音声)" (the entry) and the seven packs, "WoW Forever Japanese Voice: Levels 1-10" … "… : Levels 51-60", "… : Other". | Do it early: a new project waits for CurseForge's approval. Description text: [CurseForge voice description](../curseforge-voice.md), pasted on each. |
| 2 | Put each project's id and slug in `pipeline/voice-packs.toml`. | A normal pull request. A pack with `project_id = 0` is built and put on GitHub, but not uploaded to CurseForge, and the entry does not name it. |
| 3 | Make a CurseForge API token for the upload and keep it where `make voice-release` can read it. | `CF_API_KEY` in the environment for the one run, or a local, untracked `VOICE_TOKEN_CMD` setting that prints it. It is never written into the repository or to disk by the release. |

### Cutting a voice release

1. The main addon that reads the pack format must already be released (on the first voice release, and whenever the format changes).
2. Dry run first, which builds, checks every zip and prints what would go up, and sends nothing:
   ```bash
   make voice-release DRY=1
   ```
3. Then the release:
   ```bash
   make voice-release
   ```

### What it does

| Step | What happens |
|---|---|
| Build | As `make voice-pack`: the split, the size table, the cap. |
| Versions | Each pack's version is the date and the first eight characters of its content hash (the audio records of its files, its `Register.lua` and the client interface). A pack whose hash equals the one in the latest `voice-v*` GitHub release's asset names is unchanged and keeps its released version. The entry changes only when the set of packs with a project changes. No release state is committed. |
| Check | Every zip holds only its folder's TOC, README, `Register.lua` and the recorded Sound files, and every recorded file is there. |
| CurseForge | Each changed pack with a project id is uploaded to its project, then the entry if it changed, naming every pack as a required dependency. The game version is chosen as the main addon's packager chooses it; the release type (alpha, beta or release) follows the main addon's latest release tag. |
| GitHub | One release, `voice-vYYYY.MM.DD`, never marked latest (the main addon's release stays the latest): every zip, plus `WoWForeverJapanese_Voice-all-<date>.zip` holding the entry and every pack, for players who install by hand. |

When nothing changed since the last voice release, it says so and stops.

### Adding a pack

When a pack nears the cap (the build marks it past 315 MB), split its band: a new row in `pipeline/voice-packs.toml`, a new CurseForge project with its id, then `make voice-release`. The entry's set of packs changed, so a new entry file goes up naming the new pack, and players who have the entry get it on their next update.

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

Sizes of the seven packs, projected on 2026-10-07 from the files made so far plus the rest at 618 bytes a character:

| Pack | Size | Room under 420 MB |
|---|---|---|
| Levels 1-10 | about 220 MB | about 200 MB |
| Levels 11-20 | about 143 MB | about 277 MB |
| Levels 21-30 | about 112 MB | about 308 MB |
| Levels 31-40 | about 104 MB | about 316 MB |
| Levels 41-50 | about 111 MB | about 309 MB |
| Levels 51-60 | about 311 MB | about 109 MB |
| Other | about 137 MB | about 283 MB |

## Open work

- Not voiced: quest objectives, audio per class or race (the player's name, class and race are spoken as 冒険者), the trainer window's text.

## Related

- [Voice over](../systems/voice.md) · [ADR-061](../adr/061-voice-over-from-a-separate-pack.md) · [Local setup](local-setup.md) · [Testing strategy](../testing/strategy.md#voice-over-checklist) · [Research](../research/2026-10-04-japanese-voice-over.md)
