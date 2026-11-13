# Runbook: make and release the voice

## Goal

Make the Japanese voice from the Japanese the addon ships, copy it into the Forever client for a test, and release it. The voice ships as the **Voice entry**, `WoWForeverJapanese_Voice` (no audio; on CurseForge it requires every pack, so the app installs them all from one click), and seven **packs** named for what they hold: `WoWForeverJapanese_VoiceLevels1to10` through `…Levels51to60`, and `…Other`. How it works: [Voice over](../systems/voice.md); decisions: [ADR-061](../adr/061-voice-over-from-a-separate-pack.md), ADR-062, [ADR-074](../adr/074-voices-cloned-from-the-games-npc-voice-sets.md) (voices cloned from the game's NPC voice sets). The audio lives in its own repository, `zyaga/wow-forever-japanese-voice` (private for now), whose checkout is the audio store, `build/voice/` in the main checkout: every recording, with every older one in its history. This repository commits the audio record, `data/voice/audio.jsonl`, and the audio commit that goes with its text, `pipeline/voice-audio-commit.txt`. The packs are build output under `build/voice-pack/`.

## Prerequisites

- **No AivisSpeech.** Every voice line is a cloned game voice (ADR-074); the AivisSpeech Engine in `build/aivis/` is no longer started by any voice run. The Modal client (`make voice-modal-setup`, then one `modal token new`) and, for local runs, the Qwen3-TTS environment (`make voice-qwen-setup`) are what a run needs.
- **`lame`** on the `PATH` (WAV to MP3).
- The pinned VMaNGOS database (`VMANGOS_DB`, commit `VMANGOS_SHA` in the Makefile), as for `make import-english`.
- The repo venv (`.venv`); `make` uses it when it exists, or pass `PY=<repo>/.venv/bin/python`.
- The set clips under `build/voice-sets/` ([Cloned game voice sets](#cloned-game-voice-sets)): every line is read from a reference joined from them.

## Steps

1. **Make everything:**
   ```bash
   make voice
   ```
   This runs the three steps below in order. Each can be run alone.
   - `make voice-speakers`: writes `data/voice/speakers.jsonl` (who says each voiced line): for a quest line, the creature Spoken's newest corpus names for it (`make voice-spoken-fetch` runs first); otherwise VMaNGOS, the quest cache's conditional descriptions, forever-vo's player captures and the collector's NPC ids; a signed book page is read by its writer. It runs `make voice-levels` first (the committed quest level table). Read its report: narrator lines, conflicts (two creatures for one line), lines with no Japanese. A gossip line that ships as the English it is (a made-up language, a name alone) gets no speaker and is never voiced: the engine reads Japanese. The report lists such a line under missing. Who each creature is (`data/voice/profiles.jsonl`) and the voice it is cast in (`data/voice/voices.jsonl`, written by `wfj voice cast` from `pipeline/voice.toml`) are separate steps (`wfj voice profiles`, `wfj voice cast`). The files are data: commit them with the ticket, after `make validate` passes.
   - `make voice-generate`: first runs `make voice-match` (Spoken's newest corpus, then speakers, voice sets and the cast), so run `make voice-match` yourself before counting a run: the count then already follows the newest Spoken. Then it makes the missing and changed files in the audio store (`build/voice/audio/<key>.mp3`, `<key>_<voice>.mp3` for a variant; the store keeps its README and license at the top) and records each in `data/voice/audio.jsonl`. A file is made again only when its fingerprint changed: the hash of its Japanese, its roster voice, its set, mode (voice-only or full copy) and reference hash, the `[clone]` temperature and seed, and the hash of its [engine text](#what-the-engine-reads) when that differs from the spoken line. With nothing to make it needs no engine. A line the engine cannot read is logged and left for the next run; the run goes on. Because it runs over the whole game (`--scope all --players all`), it also drops the record rows of files no line uses any more, so `data/voice/audio.jsonl` lists exactly the shipped files (`test_audio_in_step` fails on an unused row). When it made files it then commits and pushes the store and writes the audio pin (`store-sync --if-changed`); when it made nothing, the store, the remote and the pin are left alone. `wfj voice plan` shows what it would make, without making anything.
   - `make voice-pack`: writes the entry and every pack under `build/voice-pack/`, split by `pipeline/voice-packs.toml` (below), and prints each pack's lines, files, size and room left under the 420 MB cap. Lines whose Japanese changed since their file was made are left out and counted. A pack past 315 MB is marked; a pack past 420 MB stops the build and nothing is written, as does a missing audio store or a store file that is not the recorded take (its SHA-256 differs from the audio record's). `wfj voice record-hashes` fills the SHA-256 of rows made before the field existed, reading the store only.
2. **Validate** the voice tables with the rest: `make validate`.

There is no engine to start by hand. `make voice-generate` (also behind `make import-draft` and `make report-apply`) sends the lines to Modal ([Reading the cloned voices on Modal](#reading-the-cloned-voices-on-modal-the-default)); with `VOICE_LOCAL=1` it starts the local Qwen3-TTS worker for the run instead ([Timing and load](#timing-and-load)). `make voice-run` always reads locally: the whole game in the background, the Mac kept awake. A file a stopped run was encoding is never left half written, and the files a run finishes are written to the audio record as it goes (at most once a second, and when it ends), so a run stopped at any point (`make voice-stop`, Ctrl-C) keeps all but its last second's finished work and the next run reads only what is left. The code that starts the AivisSpeech Engine (`build/aivis/`, `--engine-run`) is still in the pipeline, but no speaker is cast to an AivisSpeech voice, so no run starts it.

## Display ids for the panel's head

The voice panel draws a speaker who is not on screen (a quest played from the quest log) from a display id, the number of the model the client draws that NPC with ([ADR-088](../adr/088-the-head-is-drawn-from-a-display-id.md)). The addon ships one per speaking creature: `data/voice/displays.jsonl`, generated into `Data/Displays.lua`. After every re-pull, and whenever `make voice-speakers` adds speakers:

```bash
make creature-copy WOW_DIR="<Forever client folder>"   # make wdb-copy runs it when CLIENT=forever
make voice-displays
make generate
```

- `make creature-copy` copies the client's creature cache (`Cache/WDB/enUS/creaturecache.wdb`, read only on the game folder) to `$(INPUTS)/creatures/<build>.wdb`, named by the build in the cache's header. The client writes the cache on a full Exit Game, not on a logout. The copy reads only the header, so a new build is always copied before the next build empties it. `make voice-displays` leaves out, with a message, a cache whose build has no pinned creature layout: check that every record of the new cache reads with a pinned layout and that its displays agree with VMaNGOS, then pin it in `io/creature_cache.LAYOUTS` (a code change and a PR).
- `make voice-displays` takes each speaker's display from the newest copied cache that holds it, else from VMaNGOS. Rows are additive: a creature only an older cache held keeps its row. Its last line says how many speakers have a display id and how many came from a cache.
- Commit `data/voice/displays.jsonl` with the generated `Data/Displays.lua` (and the TOC when it changed).
- The creature caches are not backed up, unlike the quest caches: playing the client fills them again.
- A Forever NPC that no copied cache holds and VMaNGOS does not know has no row. A quest from them shows no head after a client patch until the player meets them again, or until a later re-pull copies a cache that holds them.

## Configuration

`pipeline/voice.toml`: the engine's address (`http://127.0.0.1:10101`), the pace (`speed_scale = 0.9`), the `narrator` and `book_narrator` voices, the **roster** (one table per usable voice: its model on AivisHub, the engine's style id from `GET /speakers`, its licence, what it fits, and optional pitch, intonation and speed) and the **cast rows** (which roster voices read each kind of speaker: race or creature family, gender, age, archetype), plus the engine names credited in the packs' READMEs (`engine` for AivisSpeech, `clone_engine` for Qwen3-TTS). The roster and cast rows are the AivisSpeech cast; they still run first, but every speaker then moves to a game voice set, and `test_no_committed_speaker_is_cast_to_anything_but_a_game_voice_set` fails if a committed speaker is left on an AivisSpeech voice. For the cloned voices it also holds `qwen` (the Qwen3-TTS environment's Python, relative to the main checkout), `cloned_packs` (the pack folders whose NPCs speak in their game voice set: every pack), `narrator_set` and `book_narrator_set`, one `[sets.<set>]` table per game voice set with `pick` (`voice` or `full`) and `decided`, and the `[[set_cast]]` rules that give a set to every speaker Spoken gives none. `data/voice/overrides.jsonl` pins a voice for a single creature. The pace is fixed when a file is made: the client has no playback rate, so changing it means making every file again. Recasting one cast row remakes only the lines of the creatures it casts.

Two more tables shape how a cloned voice reads ([ADR-082](../adr/082-names-spelled-from-the-english-and-the-voice-reads-its-own-text.md)):

| Table | Setting | What it does | Changing it remakes |
|---|---|---|---|
| `[clone]` | `temperature = 0.5` | How far a reading may stray from the likeliest one. The engine's own value is 0.9; lower keeps a voice steadier from line to line. | Every cloned file |
| `[clone]` | `seed = true` | Every reading of a voice set starts its random draws from one number made from the set's name (its crc32), the same on every machine. | Every cloned file |
| `[text]` | `kana_words` | Pairs of [kanji, its reading as a word]: 金 かね, 獣 けもの, 証 あかし, 心 こころ, 民 たみ, 間 あいだ, 魂 たましい, 友 とも, 人 ひと. Each is written in kana in the [engine text](#what-the-engine-reads) where it stands alone as a word. A word that sounds worse in kana comes off the list. | The lines that hold the word alone |

## What the engine reads

The engine does not read the shipped Japanese as it stands. `wfj.core.voice_text` builds its text from the spoken line (`voice.speech_text`: player tokens filled, numbers filled, stage directions dropped) with four changes, each one for a misread found by listening:

| Change | Why |
|---|---|
| Every English name is replaced by its katakana from `data/name/` | The engine guesses at Latin letters. |
| A half-width or full-width space right before a kanji is removed | The engine's text splitter breaks a kanji after a space into pieces it has no sound for, and the word comes out wrong. |
| The player stand-in is written ぼうけんしゃ | The kanji 冒険者 was sometimes misread. |
| A `[text] kana_words` kanji is written in kana where the line's reading record lists it as a word on its own with that reading | Alone it is read one way (金 かね), inside a compound another (金貨 きんか), and the engine reached for the compound's reading. 金貨 and 大金 stay kanji. |

The rest of the line stays in kanji. Nothing the player sees changes: the on-screen Japanese, the keys and the Japanese hashes the addon checks stay as they are.

The engine text goes into the fingerprint only when it differs from the spoken line, so a respelled name remakes exactly the lines that say it, and a line none of the changes touch keeps the fingerprint it had. `tests/python/test_voice.py::test_no_voiced_line_hands_the_engine_latin_letters` fails while any voiced line would hand the engine Latin letters: a new English name whose words have no spelling yet. Run `make names` and spell the new words ([Names for a batch](translation-batches.md#names-for-a-batch)). `voice plan` and `voice generate` stop as well, naming the lines and the names they lack.

**A remake is not byte for byte the same take.** On Modal a call reads several paragraphs of one voice set together, started from that set's seed, so a paragraph's draws depend on the other paragraphs in its batch: a line read again on Modal is a new take of the same voice. Read one paragraph at a time on this machine (`VOICE_LOCAL=1`), the same text, voice, temperature and seed gave the same take in the one check made (one line, read twice); nothing tests it beyond that.

The audio format is fixed in `wfj voice generate`: MP3, mono, 22.05 kHz, 32 kbps constant bitrate, with no Xing / Info header (`lame -t`).

## Cloned game voice sets

Every voice line, in every pack, is read in a voice cloned with Qwen3-TTS 1.7B Base from one of the game's own voice sets ([Voice over → Cloned game voice sets](../systems/voice.md#cloned-game-voice-sets)): 16,571 files. The set clips are cut and kept on the maintainer's machine, under `build/` of the main checkout. The game's audio leaves that machine only during a remote run: the joined set references are sent to the rented GPU containers for that run, sit in each container's `/tmp`, and are not kept there. They are never archived, committed or packed.

### One-time setup

Run these from the main checkout. Each writes under `build/` (gitignored) except the two data files, which are committed.

| # | Command | What it does |
|---|---|---|
| 1 | `make voice-qwen-setup` | Makes `build/qwen/venv` (Python 3.12, with `uv`) and installs `qwen-tts` 0.1.1 and PyTorch into it. The model downloads on its first run. The pipeline's own venv gains nothing. |
| 2 | `make voice-sets` | Fetches Spoken's newest line corpus into `build/spoken/` and writes its commit to `pipeline/spoken-commit.txt` (`make voice-spoken-fetch`; with no network it uses the recorded commit and says so), then writes `data/voice/creature-sets.jsonl`: the set each speaking NPC speaks with, as Spoken assigns it. Rerun after `make voice-speakers`. `make voice-match` runs speakers, sets and the cast in that order, and `make voice-generate` runs it first, so audio is always made against the newest Spoken. Commit `pipeline/spoken-commit.txt` with the voice tables. |
| 3 | `make voice-sets-clips WOW_DIR=<the World of Warcraft folder>` | Cuts every set's greeting, farewell and vendor barks from the Forever install's local archive (read only) into `build/voice-sets/` as 24 kHz WAV, with `manifest.json`. Needs `ffmpeg` and the community listfile at `$(INPUTS)/community-listfile.csv` (`LISTFILE_VOICE=` for another). A clip already cut is skipped. |
| 4 | `make voice-sets-catalogue BUILD=<client build>` | Writes `data/voice/sets.jsonl`: each set's gender and clips, with an English transcript of each new clip from the local `whisper` command (model small; `WHISPER=<path>` for another) and whether the clip may join a full-copy reference. Read the transcripts and fix a misheard lore word by hand in the file; fixes are kept on the next run, and a fixed transcript remakes that set's full-copy lines. |

Commit `data/voice/creature-sets.jsonl` and `data/voice/sets.jsonl` with the ticket after `make validate` passes.

### The listening page

```bash
make voice-sets-page
```

It makes, for each set, the voice-only take and the full take of one fixed line (a male or a female wording by the set's gender), and joins the set's game barks into one clip. Only missing takes are made, in one low-priority Qwen3-TTS run on this machine. Then it serves the page at http://127.0.0.1:8767/ (Ctrl-C stops it). Each row has the game clips, the voice-only take, the full take, the pick (`voice` or `full`; an undecided set shows the default: `voice` for a male set, `full` for a female one) and a decided tick; each change is saved at once to `build/voice-sets/page/picks.json`. Everything on the page stays in `build/voice-sets/page/`: it carries game audio.

To ship the picks:

```bash
make voice-sets-apply                     # the saved picks into pipeline/voice.toml [sets]
cd pipeline && ../.venv/bin/python -m wfj voice cast
cd .. && make voice-generate              # remakes only the changed sets' lines
```

Commit `pipeline/voice.toml`, `data/voice/voices.jsonl`, `data/voice/audio.jsonl` and the audio pin together.

### Which packs are cloned

Every pack is in `cloned_packs`. `wfj voice cast` moves every NPC whose home pack is listed there, and whose set is picked `voice` or `full`, to its set's voice. An NPC's home pack is the lowest band of the quests it starts or ends, so all its lines, in any pack, follow it. A new pack row in `pipeline/voice-packs.toml` (see "Adding a pack") needs its folder added to `cloned_packs` too, then `wfj voice cast` and `make voice-generate`.

### Timing and load

This applies to local runs (`VOICE_LOCAL=1`, `build/qwen/venv`, `make voice-qwen-setup`). Locally, Qwen3-TTS is slower than real time: about 2 to 3 times slower per engine on the maintainer's M1 Pro, so a whole pack is a run of a day or more. That is why runs go to Modal by default.

A local run's speed can be changed while it goes, without stopping it:

| Command | Speed |
|---|---|
| `make voice-speed SPEED=slow` | One engine in macOS's background tier (efficiency cores, throttled disk). The default, for while the machine is in use |
| `make voice-speed SPEED=fast` | Three engines side by side at normal priority, for while the machine is free (overnight, away) |
| `make voice-speed` | Prints the speed set now |

The setting is a file, `build/voice-speed` in the main checkout. The run reads it before each line: going fast starts the extra engines (each holds the model, about 5 GB of memory), going slow stops them once their line is done and moves the remaining one into the background tier. Only one run may use the engines: a second `make voice-generate` or `make voice-sets-page` that needs them stops with "another voice run is making cloned voices; one runs at a time". The engines write their own output to `build/voice/qwen.log` (generation) or `build/voice-sets/page/qwen.log` (the page, which always runs one engine under `nice`). A run stopped partway resumes where it left off, like any `voice-generate`.

### Reading the cloned voices on Modal (the default)

`make voice-generate` reads every line on rented GPUs (Modal, L40S). One command does the whole round:

1. `wfj voice export` writes the cloned lines still to make to `build/voice-remote/<time>/`: `jobs.jsonl` (one line per file: its key, its engine text, reference and mode, and the `[clone]` seed and temperature), `refs/` (the joined set references) and `refs.json` (their transcripts). The references are game audio: they are sent to the Modal containers for this run only, each container writes them to its `/tmp`, and nothing is kept there.
2. `pipeline/wfj/io/qwen_modal.py` reads them on Modal with the same model, the same pinned `qwen-tts` and the same worker code (`qwen_worker.load` and `speak_many`) as the local engine, on one card per 60 lines (at most 10), 24 paragraphs per model call. A call holds the paragraphs of one voice set only and starts from that set's seed. The WAVs come back to the run's `wav/` folder; a line that failed is read again once.
3. The run's WAVs, jobs, reference transcripts and manifest are copied to `VOICE_WAV_ARCHIVE` (set privately in `local.mk`) and checked against a `SHA256SUMS` written there. These are the uncompressed masters: they are never deleted, here or there. The references (`refs/`) and the game's clips are not copied. If archiving fails, the run still imports and says so; archive it later with `cd pipeline && ../.venv/bin/python -m wfj voice generate --prepared <run folder> --archive <archive folder>`.
4. `voice generate --prepared` encodes and records them like any other take.

Setup, once: `make voice-modal-setup`, then log in with `build/modal/venv/bin/modal token new` (the login stays in `~/.modal.toml`). `VOICE_LOCAL=1 make voice-generate` reads the cloned voices on this machine instead (see "Timing and load").

Each model call holds at most 24 paragraphs and at most 3,000 padded characters (count times the longest), longest lines first, 15 lines per card call; a call that runs out of GPU memory is split in half until it fits. Every reading is capped at twice its text's expected length plus 3 s: a line the model does not end by itself is cut there and reported as "ran on" instead of holding its whole call (without the cap a call can reach Modal's 3,600 s limit). Each paragraph is held to its own length, not only the call's: a call's cap is its longest paragraph's, and a short paragraph that babbles on can stay under it (one quest offer kept 20 s of babble that way). A take that runs on is not kept and is read again on the next run. The model often ends a Japanese line before its last syllable has faded out (upstream issue [QwenLM/Qwen3-TTS#55](https://github.com/QwenLM/Qwen3-TTS/issues/55), open, no fix): trailing silence, a trailing ellipsis, a minimum length and other sampling settings do not change it, so lines are not remade for it. A run that returns with lines still missing is imported as far as it got; the missing lines stay to make and the next run reads only them. A line the engine cannot read is left for the next run in the same way instead of ending the run.

**Estimating time and money.** Characters C come from `wfj voice export` ("N lines to read (C characters)"); the picked voices speak 5.88 characters a second. A card (L40S, $1.95 an hour) reads R characters per card-second: 48.5 on clean batches (measured on 60 lines), 11.4 on the first full run (Levels 1-10, 404,046 characters, $19.25 including tests, about 72 minutes, held back by out-of-memory batches, an idle tail and one call that hit the time limit). Card time = C / R + cards x start-up (2 to 4 minutes each); cost = card time x $1.95 an hour; wall time is about card time / cards. Update R in this paragraph after each run. A collector send or fix report of 20 to 100 lines costs a few cents, mostly the card's start-up.

### If the publisher asks for a takedown

The cloned voices are modelled on the publisher's recordings, shipped non-commercially and credited, with no actor named ([ADR-074](../adr/074-voices-cloned-from-the-games-npc-voice-sets.md)). On a takedown request, the affected voice packs are withdrawn (removed from CurseForge and GitHub, or not released) until the maintainer decides what follows. No AivisSpeech audio is made or shipped as a stand-in.

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

## Kana lines

Every voiced line (each line a voice file is made for, and the character's error lines) has a **kana line** in `data/voice/kana.jsonl`: the line written in kana only ([ADR-078](../adr/078-japanese-names-keyed-by-english-and-kana-voice-lines.md)). It is built from the spoken line (`voice.speech_text`: player tokens as 冒険者, `$N<k>` numbers filled) with:

- every kanji word replaced by its reading from `data/reading/` (the line's current reading record),
- every English name replaced by its katakana from `data/name/` (Black Dragonflight is ブラック・ドラゴンフライト),
- every comma written as 、 (an English comma left between names or in the prose),
- every number spelled out with its counter and sound change (3匹 さんびき, 1本 いっぽん, 2週間 にしゅうかん).

Each row is `{"key", "ja_hash", "kana", "provenance"}`. `ja_hash` is `voice.text_hash` of the shipped Japanese and its filled numbers, the same hash an audio file's fingerprint starts with, so a kana line and a file made from it always describe the same words.

**Keeping them current.** `make names` ends with `wfj voice kana`, and every flow that brings English or changes shipped Japanese runs `make names`: `make import-english`, `make import-collector`, `make collector-intake`, `make import-draft` (before `voice-generate`) and `make report-apply`. A line the builder can read is rebuilt on every run. A line it cannot finish (a kanji word with no reading, an English name with no Japanese yet, a number it cannot read) is listed with its key and why. Fix the cause (a readings round, a names round) or draft the line by hand:

```bash
cd pipeline
python3 -m wfj voice kana --export batches/kana-<round>.jsonl   # {"key", "ja_hash", "ja", "problems"} per unfinished line
# the model writes "kana" onto each row (kana only: no kanji, Latin letter or digit)
python3 -m wfj voice kana-import batches/kana-<round>.jsonl --model <model id> --batch <name>
```

The batch files are working files in `pipeline/batches/`, as for every [translation batch](translation-batches.md); what is kept is `data/voice/kana.jsonl`.

`kana-import` refuses a row for a key that is not voiced, a row written for other Japanese (its `ja_hash` is not the current one) and a row that is not all kana. A drafted row is kept while its `ja_hash` matches; when the line's Japanese changes it has to be drafted again. `tests/python/test_kana.py` fails while any voiced line has no kana line made from its current Japanese.

**The audio is not made from them.** `make voice-generate` reads the [engine text](#what-the-engine-reads), which keeps kanji and fixes only the words proved to come out wrong ([ADR-082](../adr/082-names-spelled-from-the-english-and-the-voice-reads-its-own-text.md)). The kana lines are kept and rebuilt by every `make names`, and their test still holds.

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

The cloned voices, as `make voice-pack` printed them for the current audio: 16,571 files, about 1.32 GB.

| Pack | Size | Room under 420 MB |
|---|---|---|
| Levels 1-10 | 247.3 MB | 172.7 MB |
| Levels 11-20 | 161.3 MB | 258.7 MB |
| Levels 21-30 | 130.9 MB | 289.1 MB |
| Levels 31-40 | 146.0 MB | 274.0 MB |
| Levels 41-50 | 138.9 MB | 281.1 MB |
| Levels 51-60 | 337.6 MB | 82.4 MB |
| Other | 154.0 MB | 266.0 MB |

Levels 51-60 is past the 315 MB mark: when it grows near the cap, split its band (see "Adding a pack"). Every take is levelled to -20 LUFS (one gain measured with ffmpeg's `ebur128`, peaks limited to -2 dBFS); a silent take or one shorter than 400 ms is left as it is. Time and money for a run: "Estimating time and money" above.

## Open work

- Not voiced: quest objectives, audio per class or race (the player's name, class and race are spoken as 冒険者), the trainer window's text.

## Related

- [Voice over](../systems/voice.md) · [ADR-061](../adr/061-voice-over-from-a-separate-pack.md) · [ADR-074](../adr/074-voices-cloned-from-the-games-npc-voice-sets.md) · [ADR-078](../adr/078-japanese-names-keyed-by-english-and-kana-voice-lines.md) · [ADR-082](../adr/082-names-spelled-from-the-english-and-the-voice-reads-its-own-text.md) · [Local setup](local-setup.md) · [Testing strategy](../testing/strategy.md#voice-over-checklist) · [Research](../research/2026-10-04-japanese-voice-over.md)
