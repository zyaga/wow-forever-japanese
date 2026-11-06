# Runbook: make and release the voice

## Goal

Make the Japanese voice from the Japanese the addon ships, copy it into the Forever client for a test, and release it. The voice ships as the **Voice entry**, `WoWForeverJapanese_Voice` (no audio; on CurseForge it requires every pack, so the app installs them all from one click), and seven **packs** named for what they hold: `WoWForeverJapanese_VoiceLevels1to10` through `…Levels51to60`, and `…Other`. How it works: [Voice over](../systems/voice.md); decisions: [ADR-061](../adr/061-voice-over-from-a-separate-pack.md), ADR-062, [ADR-074](../adr/074-voices-cloned-from-the-games-npc-voice-sets.md) (voices cloned from the game's NPC voice sets). The audio lives in its own repository, `zyaga/wow-forever-japanese-voice` (private for now), whose checkout is the audio store, `build/voice/` in the main checkout: every recording, with every older one in its history. This repository commits the audio record, `data/voice/audio.jsonl`, and the audio commit that goes with its text, `pipeline/voice-audio-commit.txt`. The packs are build output under `build/voice-pack/`.

## Prerequisites

- **No AivisSpeech.** Every voice line is a cloned game voice (ADR-074); the AivisSpeech Engine in `build/aivis/` is no longer started by any voice run. The Modal client (`make voice-modal-setup`, then one `modal token new`) and, for local runs, the Qwen3-TTS environment (`make voice-qwen-setup`) are what a run needs.
- **`lame`** on the `PATH` (WAV to MP3).
- The pinned VMaNGOS database (`VMANGOS_DB`, commit `VMANGOS_SHA` in the Makefile), as for `make import-english`.
- The repo venv (`.venv`); `make` uses it when it exists, or pass `PY=<repo>/.venv/bin/python`.
- For the cloned voices of a switched pack, the Qwen3-TTS environment and the set clips ([Cloned game voice sets](#cloned-game-voice-sets)).

## Steps

1. **Make everything:**
   ```bash
   make voice
   ```
   This runs the three steps below in order. Each can be run alone.
   - `make voice-speakers`: writes `data/voice/speakers.jsonl` (who says each voiced line) from VMaNGOS, the quest cache's conditional descriptions, forever-vo's player captures and the collector's NPC ids; a signed book page is read by its writer. It runs `make voice-levels` first (the committed quest level table). Read its report: narrator lines, conflicts (two creatures for one line), lines with no Japanese. A gossip line that ships as the English it is (a made-up language, a name alone) gets no speaker and is never voiced: the engine reads Japanese. The report lists such a line under missing. Who each creature is (`data/voice/profiles.jsonl`) and the voice it is cast in (`data/voice/voices.jsonl`, written by `wfj voice cast` from `pipeline/voice.toml`) are separate steps (`wfj voice profiles`, `wfj voice cast`). The files are data: commit them with the ticket, after `make validate` passes.
   - `make voice-generate`: makes the missing and changed files in the audio store (`build/voice/audio/<key>.mp3`, `<key>_<voice>.mp3` for a variant; the store keeps its README and license at the top) and records each in `data/voice/audio.jsonl`. A file is made again only when its fingerprint changed: the hash of its Japanese, its roster voice and that voice's engine settings (style, speed, pitch, intonation). With nothing to make it needs no engine. When it made files it then commits and pushes the store and writes the audio pin (`store-sync --if-changed`); when it made nothing, the store, the remote and the pin are left alone. `wfj voice plan` shows what it would make, without making anything.
   - `make voice-pack`: writes the entry and every pack under `build/voice-pack/`, split by `pipeline/voice-packs.toml` (below), and prints each pack's lines, files, size and room left under the 420 MB cap. Lines whose Japanese changed since their file was made are left out and counted. A pack past 315 MB is marked; a pack past 420 MB stops the build and nothing is written, as does a missing audio store or a store file that is not the recorded take (its SHA-256 differs from the audio record's). `wfj voice record-hashes` fills the SHA-256 of rows made before the field existed, reading the store only.
2. **Validate** the voice tables with the rest: `make validate`.

There is no engine to start by hand. When `wfj voice generate` (behind `make voice-generate`, `make voice-run`, `make import-draft` and `make report-apply`) has files to make and no engine answers at the address in `pipeline/voice.toml`, it starts `build/aivis/macOS-arm64/run` of the main checkout on that address, waits until it answers (up to 120 s; the 1.2.0 engine takes about 16 s), and stops it when the run ends: finished, failed, stopped with `make voice-stop`, or its terminal closed. An engine already answering when the run starts is used and left running. When two runs overlap (a `make voice-run` in the background and an import, say), the one that started the engine waits for the other to end before stopping it, and says so. A file a stopped run was encoding is never left half written. Start one by hand (`build/aivis/macOS-arm64/run`) for `wfj voice audition`, or to keep it warm across runs; check it answers with `curl -s http://127.0.0.1:10101/version`, which prints `"1.2.0"`. `--engine-run PATH` points `wfj voice generate` at another engine. With no engine answering and no engine at that path, the run stops and says to start one or unpack it into `build/aivis/`.

## Configuration

`pipeline/voice.toml`: the engine's address (`http://127.0.0.1:10101`), the pace (`speed_scale = 0.9`), the `narrator` and `book_narrator` voices, the **roster** (one table per usable voice: its model on AivisHub, the engine's style id from `GET /speakers`, its licence, what it fits, and optional pitch, intonation and speed) and the **cast rows** (which roster voices read each kind of speaker: race or creature family, gender, age, archetype), plus the credits written into the packs' READMEs (`engine` for AivisSpeech, `clone_engine` for Qwen3-TTS). For the cloned voices it also holds `qwen` (the Qwen3-TTS environment's Python, relative to the main checkout), `cloned_packs` (the pack folders whose NPCs speak in their game voice set) and one `[sets.<set>]` table per game voice set with `pick` (`voice`, `full` or `keep`) and `decided`. `data/voice/overrides.jsonl` pins a voice for a single creature. The pace is fixed when a file is made: the client has no playback rate, so changing it means making every file again. Recasting one cast row remakes only the lines of the creatures it casts.

The audio format is fixed in `wfj voice generate`: MP3, mono, 22.05 kHz, 32 kbps constant bitrate, with no Xing / Info header (`lame -t`).

## Cloned game voice sets

NPCs of a switched pack speak in a voice cloned with Qwen3-TTS from their own voice set in the game ([Voice over → Cloned game voice sets](../systems/voice.md#cloned-game-voice-sets)). Levels 1-10 is the first pack switched. All of this runs on the maintainer's computer, and the game's audio never leaves it.

### One-time setup

Run these from the main checkout. Each writes under `build/` (gitignored) except the two data files, which are committed.

| # | Command | What it does |
|---|---|---|
| 1 | `make voice-qwen-setup` | Makes `build/qwen/venv` (Python 3.12, with `uv`) and installs `qwen-tts` 0.1.1 and PyTorch into it. The model downloads on its first run. The pipeline's own venv gains nothing. |
| 2 | `make voice-sets` | Fetches Spoken's line corpus at the pinned commit into `build/spoken/` (`make voice-spoken-fetch`, skipped when the file is there), then writes `data/voice/creature-sets.jsonl`: the set each speaking NPC speaks with, as Spoken assigns it. Rerun after `make voice-speakers`. To follow a newer Spoken, change `SPOKEN_COMMIT` in the Makefile and rerun. |
| 3 | `make voice-sets-clips WOW_DIR=<the World of Warcraft folder>` | Cuts every set's greeting, farewell and vendor barks from the Forever install's local archive (read only) into `build/voice-sets/` as 24 kHz WAV, with `manifest.json`. Needs `ffmpeg` and the community listfile at `$(INPUTS)/community-listfile.csv` (`LISTFILE_VOICE=` for another). A clip already cut is skipped. |
| 4 | `make voice-sets-catalogue BUILD=<client build>` | Writes `data/voice/sets.jsonl`: each set's gender and clips, with an English transcript of each new clip from the local `whisper` command (model small; `WHISPER=<path>` for another) and whether the clip may join a full-copy reference. Read the transcripts and fix a misheard lore word by hand in the file; fixes are kept on the next run, and a fixed transcript remakes that set's full-copy lines. |

Commit `data/voice/creature-sets.jsonl` and `data/voice/sets.jsonl` with the ticket after `make validate` passes.

### The listening page

```bash
make voice-sets-page
```

It makes, for each set, the voice-only take and the full take of one fixed line (a male or a female wording by the set's gender), joins the set's game barks into one clip, and copies today's AivisSpeech take of one of its NPCs' lines. Only missing takes are made, in one low-priority Qwen3-TTS run. Then it serves the page at http://127.0.0.1:8767/ (Ctrl-C stops it). Each row has the game clips, the voice-only take, the full take, today's take, the pick (`voice`, `full`, `keep`) and a decided tick; each change is saved at once to `build/voice-sets/page/picks.json`. Everything on the page stays in `build/voice-sets/page/`: it carries game audio.

To ship the picks:

```bash
make voice-sets-apply                     # the saved picks into pipeline/voice.toml [sets]
cd pipeline && ../.venv/bin/python -m wfj voice cast
cd .. && make voice-generate              # remakes only the changed sets' lines
```

Commit `pipeline/voice.toml`, `data/voice/voices.jsonl`, `data/voice/audio.jsonl` and the audio pin together.

### Switching the next pack

1. Add the pack's folder to `cloned_packs` in `pipeline/voice.toml` (for example `"WoWForeverJapanese_VoiceLevels11to20"`).
2. `wfj voice cast` (as above): every NPC whose home pack is that one, and whose set is picked `voice` or `full`, moves to its set's voice. An NPC's home pack is the lowest band of the quests it starts or ends, so all its lines, in any pack, follow it.
3. `wfj voice plan` shows what will be made; `make voice-generate` makes it, in the background. The run commits and pushes the audio and writes the pin as usual.
4. `make voice-pack` for the size table, `make validate`, then a pull request with `voice.toml`, `voices.jsonl`, `audio.jsonl` and the pin. The release sends only the packs whose audio changed.

### Timing and load

Qwen3-TTS is slower than real time: about 2 to 3 times slower per engine on the maintainer's M1 Pro, against AivisSpeech's 2.85 times faster. A pack is a run of a day or more; Levels 1-10 was projected at 1.5 to 2 days at the slow speed.

A run's speed can be changed while it goes, without stopping it:

| Command | Speed |
|---|---|
| `make voice-speed SPEED=slow` | One engine in macOS's background tier (efficiency cores, throttled disk). The default, for while the machine is in use |
| `make voice-speed SPEED=fast` | Three engines side by side at normal priority, for while the machine is free (overnight, away) |
| `make voice-speed` | Prints the speed set now |

The setting is a file, `build/voice-speed` in the main checkout. The run reads it before each line: going fast starts the extra engines (each holds the model, about 5 GB of memory), going slow stops them once their line is done and moves the remaining one into the background tier. Only one run may use the engines: a second `make voice-generate` or `make voice-sets-page` that needs them stops with "another voice run is making cloned voices; one runs at a time". A run with only AivisSpeech files to make never starts them. The engines write their own output to `build/voice/qwen.log` (generation) or `build/voice-sets/page/qwen.log` (the page, which always runs one engine under `nice`). A run stopped partway resumes where it left off, like any `voice-generate`.

### Reading the cloned voices on Modal (the default)

`make voice-generate` reads the cloned voices on rented GPUs (Modal) and only the AivisSpeech lines on this machine. One command does the whole round:

1. `wfj voice export` writes the cloned lines still to make to `build/voice-remote/<time>/`: `jobs.jsonl` (one line per file: its key, text, reference and mode), `refs/` (the joined set references) and `refs.json` (their transcripts).
2. `pipeline/wfj/io/qwen_modal.py` reads them on Modal with the same model, the same pinned `qwen-tts` and the same worker code (`qwen_worker.load` and `speak_many`) as the local engine, on one card per 60 lines (at most 10), 24 paragraphs per model call. The WAVs come back to the run's `wav/` folder; a line that failed is read again once.
3. The run's WAVs, jobs and manifest are copied to `VOICE_WAV_ARCHIVE` (set in `local.mk`) and checked against a `SHA256SUMS` written there. These are the uncompressed masters: they are never deleted, here or there. The game's clips are not copied.
4. `voice generate --prepared` encodes and records them like any other take.

Setup, once: `make voice-modal-setup`, then log in with `build/modal/venv/bin/modal token new` (the login stays in `~/.modal.toml`). `VOICE_LOCAL=1 make voice-generate` reads the cloned voices on this machine instead (see "Timing and load").

Each model call holds at most 24 paragraphs and at most 3,000 padded characters (count times the longest), longest lines first, 15 lines per card call; a call that runs out of GPU memory is split in half until it fits. Every reading is capped at twice its text's expected length plus 3 s: a line the model does not end by itself is cut there and reported as "ran on" instead of holding its whole call (without the cap a call can reach Modal's 3,600 s limit). A run that returns with lines still missing is imported as far as it got; the missing lines stay to make and the next run reads only them.

**Estimating time and money.** Characters C come from `wfj voice export` ("N lines to read (C characters)"); the picked voices speak 5.88 characters a second. A card (L40S, $1.95 an hour) reads R characters per card-second: 48.5 on clean batches (measured on 60 lines), 11.4 on the first full run (Levels 1-10, 404,046 characters, $19.25 including tests, about 72 minutes, held back by out-of-memory batches, an idle tail and one call that hit the time limit). Card time = C / R + cards x start-up (2 to 4 minutes each); cost = card time x $1.95 an hour; wall time is about card time / cards. Update R in this paragraph after each run. A collector send or fix report of 20 to 100 lines costs a few cents, mostly the card's start-up.

### If the publisher asks for a takedown

The cloned voices are modelled on the publisher's recordings, shipped non-commercially and credited, with no actor named ([ADR-074](../adr/074-voices-cloned-from-the-games-npc-voice-sets.md)). If asked to take them down, go back to the AivisSpeech audio:

1. Set `pipeline/voice-audio-commit.txt` back to the audio pin before the first switched pack, and revert `pipeline/voice.toml`, `data/voice/voices.jsonl` and `data/voice/audio.jsonl` to the same commit (or set `cloned_packs = []`, run `wfj voice cast` and `make voice-generate` to remake them).
2. Release. The old files are in the audio repository's history, so nothing needs making again when the pin goes back.

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

## The audio store and the pin

| What | Where |
|---|---|
| The MP3s | `build/voice/` in the main checkout, a checkout of `zyaga/wow-forever-japanese-voice`. Set it up once on a new machine: `git clone git@github.com:zyaga/wow-forever-japanese-voice.git build/voice` from the main checkout. |
| Which audio goes with this text | `pipeline/voice-audio-commit.txt`: one commit of the audio repository |
| Each quest's level, for the packs | `pipeline/voice_quest_levels.txt`, written by `make voice-levels` (the quest cache and VMaNGOS, which only the maintainer's computer has; a quest neither gives a level keeps the one the table had, so a quest the new cache does not answer stays in its pack). `make voice-speakers` runs it first; rerun both after a re-pull. |

`make voice-run` and `make voice-generate` end with `store-sync --if-changed`: when the run made files, or an earlier sync committed but could not push, it commits them to the audio repository, pushes them, and writes that commit to the pin; when there is nothing new, nothing moves. Commit the pin with the audio record in the same pull request. A release builds the packs from exactly the pinned commit, so a line never plays audio made from other words. `make voice-sync` alone does the same after a run that was stopped.

## Releasing the voice

The voice is released by the main [Release](release.md) workflow, one run for everything: the addon when `## Unreleased` has lines, then the voice packs whose audio changed, built from the pinned audio commit. A voice-only change (a recast) releases only its packs; nothing is released for voice when no pack changed. `make voice-release` stays for dry runs and rehearsals from the maintainer's computer.

### One-time setup

| # | Step | Notes |
|---|---|---|
| 1 | Create the eight CurseForge projects, as World of Warcraft addons: "WoW Forever Japanese Voice (日本語音声)" (the entry) and the seven packs, "WoW Forever Japanese Voice: Levels 1-10" … "… : Levels 51-60", "… : Other". | Do it early: a new project waits for CurseForge's approval. Description text: [CurseForge voice description](../curseforge-voice.md), pasted on each. |
| 2 | Put each project's id and slug in `pipeline/voice-packs.toml`. | A normal pull request. A pack with `project_id = 0` is built and put on GitHub, but not uploaded to CurseForge, and the entry does not name it. Once its id is set, the next release uploads it (the id is part of its content hash). |
| 3 | Give the Release workflow read access to the audio repository: a read-only deploy key on `zyaga/wow-forever-japanese-voice`, its private half as the repository secret **`VOICE_REPO_KEY`** of the addon repository. | The workflow's CurseForge token is the addon's `CF_API_KEY`, which already reaches the voice projects. |
| 4 | For local dry runs and rehearsals: a CurseForge API token where `make voice-release` can read it. | `CF_API_KEY` in the environment for the one run, or a local, untracked `VOICE_TOKEN_CMD` setting that prints it. It is never written into the repository or to disk by the release. |

### Cutting a voice release

Merge the pull request that carries the audio record and the pin, then start the Release workflow (**Actions → Release → Run workflow**, or `make release`). The addon goes first when it has changelog lines; a pack never reaches players before the text it was made from.

To see what would go up without sending anything, from the maintainer's computer:

```bash
make voice-release DRY=1
```

It refuses unless the audio store sits at the pinned commit with nothing uncommitted (`make voice-sync` first).

### What it does

| Step | What happens |
|---|---|
| Build | As `make voice-pack`: the split, the size table, the cap. |
| Versions | Each pack's version is the date and the first eight characters of its content hash (the audio records of its files, its `Register.lua`, the client interface and its CurseForge project id, so a pack released before its project existed goes up once it has one). A pack whose hash equals the one in the latest `voice-v*` GitHub release's asset names is unchanged and keeps its released version. The entry changes only when the set of packs with a project changes. No release state is committed. |
| Check | Every zip holds only its folder's TOC, README, `Register.lua` and the recorded Sound files, and every recorded file is there. |
| CurseForge | Each changed pack with a project id is uploaded to its project, then the entry if it changed, naming the main addon (`addon_slug`) and every pack as required dependencies, so the app never installs voice without the addon. The game version is chosen as the main addon's packager chooses it; the release type (alpha, beta or release) follows the main addon's latest release tag. |
| GitHub | One release, `voice-vYYYY.MM.DD`, never marked latest (the main addon's release stays the latest). It starts as a draft before the first upload, and each zip is added to it the moment CurseForge accepts it, so a run that fails partway is resumed from its draft and uploads nothing twice. At the end it gets every zip, `WoWForeverJapanese_Voice-all-<date>.zip` holding the entry and every pack (for players who install by hand), and a small `voice-inputs-…txt` naming what the packs were built from (left off when the entry went up without some packs, so the next release runs the voice job and retries it), then it is published. A zip of 2 GiB or more (GitHub's limit) stops the run before any upload. |

When no pack changed since the last voice release, it uploads nothing; if only the pack code changed, it records the new `voice-inputs-…txt` on the last voice release instead, so later addon releases skip the voice job. `CF_ONLY=1` uploads to CurseForge and makes no GitHub release (a rehearsal); with no voice release on GitHub, the next run counts every pack as changed again. `ONLY=<folder>,…` uploads just those projects, and only with `CF_ONLY=1` (a GitHub release would otherwise record packs that never went up). `ENTRY_WITHOUT_PACKS=1` makes the entry's file require the main addon alone; the release records that entry as incomplete, so a later release uploads the entry naming every pack. A run that stopped partway leaves a draft voice release on GitHub; run the release again and it carries on from there: a pending draft always runs the voice job, an entry the draft already holds is not sent to CurseForge again, and a draft that holds nothing the published release lacks is deleted instead of published. A real release refuses uncommitted voice inputs (the release records the inputs as of the commit); a dry run only warns.

### Adding a pack

When a pack nears the cap (the build marks it past 315 MB), split its band: a new row in `pipeline/voice-packs.toml`, a new CurseForge project with its id, then a release. CurseForge accepts a project as a dependency only once it has approved it, and it reviews a project only after its first file. The release handles that by itself: it uploads the new pack's first file, and when CurseForge refuses that pack in the entry's list (error 1018), it uploads the entry without it, says so, and records the entry as incomplete. The next release after the approval uploads the entry naming every pack, and players who have the entry get the new pack on their next update.

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

- [Voice over](../systems/voice.md) · [ADR-061](../adr/061-voice-over-from-a-separate-pack.md) · [ADR-074](../adr/074-voices-cloned-from-the-games-npc-voice-sets.md) · [Local setup](local-setup.md) · [Testing strategy](../testing/strategy.md#voice-over-checklist) · [Research](../research/2026-10-04-japanese-voice-over.md)
