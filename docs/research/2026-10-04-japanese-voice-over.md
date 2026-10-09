# Research: Japanese voice over from the shipped text

> A bounded spike, 2026-10-04 to 2026-10-06. Can the addon read its Japanese aloud for quests and gossip, the way the forever-vo addon does for English? Samples were made locally with three engines and judged by ear by the maintainer. Nothing here ships; the build is its own decision.

- **Date:** 2026-10-06
- **Question:** Can quest and gossip text be voiced in Japanese from the text the addon already ships, at a quality worth hearing, in a time and size the project can carry, and played back on the Forever client?
- **Sources:** the Forever client's UI extract (build 1.60.1.70170) and its local archive (read only), the forever-vo repository (github.com/quinn-dougherty/forever-vo, MIT, revision 025070f), the engines' own pages and installed code, and the providers' own pricing pages. Anything not settled by those is marked **[unverified]**.

## Options
| Option | Pros | Cons |
|---|---|---|
| Chatterbox multilingual, run locally, voice copied from a reference clip | MIT, any voice from a 10 second clip, what forever-vo uses for English | Japanese is one of 23 languages in one model: slow on this Mac, rushed pacing, drones and noise between sentences, needs a licensed Japanese reference clip |
| AivisSpeech Engine, run locally, ready-made voices | Built for Japanese, clean output, about 3 times faster than playback on the processor alone, 40 freely licensed voices, male and female | Voices are fixed models, not copies of a given clip; the licence must be read per voice |
| The Mac's built-in Japanese voice (Kyoko) | No install, instant | A system voice; cannot ship |
| Hosted services (Google, Azure, OpenAI, ElevenLabs) | Fast | Ruled out by the maintainer: generation stays local. Prices below are reference only |

## Findings

### (a) The sample set
20 lines from the shipped data, 2,113 characters: three long quest descriptions, four short gossip lines, two progress and two turn-in lines, three lines with English names inside (Lion's Pride Inn, Zaal Stormshield), two narrator lines (quests started from an item or an object), two lines with the player's name, class and race filled in, and two objectives. The player was filled in as Kaelan, パラディン, 人間 for the samples only. Each line also has a kana reading built from the shipped word readings, used to test feeding readings to an engine.

Quest 176 (Wanted: Hogger) was then voiced whole, offer, objective, progress and turn-in, in every candidate voice, so the maintainer could judge one quest end to end.

### (b) Chatterbox on the Mac (M1 Pro, 32 GB)
| Measure | GPU (MPS) |
|---|---|
| Model files | 3.0 GB downloaded; the environment with PyTorch is 1.5 GB |
| Load | 17 to 39 s |
| Speed | about 3 characters a second of text; 2.2 to 2.8 times slower than playback |
| All quest and gossip text (3.88M characters) | about 15 days nonstop |
| Everything, objectives included (4.65M) | about 18 days |

Per-line seconds for every engine and line are kept with the samples, beside the listening page. The CPU run was not made: the maintainer stopped the runs after the disk filled (the model files plus swap from two model copies at once).

What it took to get a listenable line, all learned on the samples:
- Input over about 90 characters came out rushed (9 to 12 characters a second against 5 to 7 for short lines). One sentence per call fixed the pace.
- A piece ending in 「、」 or a very short piece (under 15 characters) ran on into a low drone, about 300 to 1,200 Hz, after the words ended. Every piece has to end as a finished sentence, and a trailing tone has to be cut by measuring it.
- A piece with no letters (a lone 「！」) crashes the model.
- Without a reference clip the built-in default voice is not Japanese, and the lines carried muffles and odd sounds. With a clip from the つくよみちゃん corpus (one female voice, commercial use and voice copying allowed, credit required) the voice was right but a metallic echo stayed near English names and at sentence ends. forever-vo's own notes say a reference spliced from several short clips sounds "robotic"; our clip was two sentences joined.
- The watermark Chatterbox adds to every file needs a package the environment lacked, so the samples are unmarked. The licence does not require it.
- English names in Latin letters: the objective line (mostly names) came out as 1.5 s of audio for 56 characters. Speech-only katakana hints fixed it (Hogger → ホガー, Elwynn → エルウィン, Goldshire → ゴールドシャイア, Marshal Dughan → マーシャル・ダガン, Stormwind Army → ストームウィンド軍, Huge Gnoll Claw → ヒュージ・ノール・クロー, Blackrock Spire → ブラックロック・スパイア, gnoll → ノール, the player name → ケイラン). Chatterbox takes no reading hint of its own; it turns kanji into kana with a dictionary, so the kana variant was the whole line in kana. AivisSpeech read every kanji in the samples correctly without hints, so none were fed to it.

The maintainer's verdict after the fixes: much better, still not clean. Chatterbox is superseded by the next engine.

### (c) AivisSpeech Engine on the Mac
AivisSpeech Engine 1.2.0 (Apple Silicon build, 799 MB unpacked) runs as a local HTTP server on the processor only. It takes a whole line at once; no splitting, trimming or retakes were needed.

| Measure | Value |
|---|---|
| Generation speed | about 23 characters a second of text; about 3 times faster than playback |
| Speaking rate | about 7.5 characters a second of audio, the same as the Mac's own voice |
| All quest and gossip text (3.88M characters) | about 2 days nonstop, resumable |
| Everything (4.65M) | about 2.3 days |
| Pace setting | The engine's `speedScale` sets the pace at generation; the maintainer found 1.0 a touch fast and 0.8 too slow; 0.9 is the choice. No playback rate exists in the client [unverified: no such argument in the files read; forever-vo also pre-renders], so any speed choice means one file set per speed |
| English names as written | Read Japanese-style, at normal length. The maintainer judged this right: if Japanese names ever become an option, the katakana would sound the same |

Voices tried on quest 176, all under the Aivis Common Model License 1.0 (ACML): 阿井田 茂 (middle-aged male, two styles), ろてじん (elderly male), fumifumi (calm adult male), にせ and Lux (young male), morioki (adult female), みちのくあいり (calm young female), まお and コハク (young female, the engine's defaults). Each 240 MB.

### (d) Voices and licences
| Source | Voices | Terms, from its own page |
|---|---|---|
| AivisHub (the engine's model site) | 75 models: 22 young male, 4 adult male, 4 middle-aged male, 2 elderly male, 39 young female, 1 adult female, others | 37 under ACML 1.0, 3 CC0, 7 ACML non-commercial, 28 custom. ACML 1.0: any personal or commercial use, redistribution of the model with the licence text, credit optional; no deception, defamation, politics, religion or crime. The licence is governed by Japanese text only |
| つくよみちゃんコーパス (Rei Yumesaki) | 1 female, 100 studio sentences | Commercial use and voice synthesis allowed; a fixed credit line is required when generated voice is published; the corpus itself may not be redistributed; no attacks, politics or religion |
| あみたろの声素材工房 | 1 female | Commercial use, AI training and bundling in games allowed with credit [unverified: read from a summary, not the page line by line] |
| JVNV (University of Tokyo) | 2 female, 2 male | CC BY-SA 4.0; whether share-alike reaches generated audio is not stated |
| JVS, JSUT (University of Tokyo) | 100 speakers; 1 female | Non-commercial unless the authors agree; they say they welcome commercial requests |
| Mozilla Common Voice (Japanese) | many | CC0; amateur recordings |
| VOICEVOX characters | many, male and female | Per character; most allow commercial use with credit; some exclude game works |

The game's own recordings are not usable: Forever has no Japanese audio, and the English NPC lines belong to the publisher and its actors. forever-vo copies its voices from those; this project will not.

One voice is enough for a first version if it is framed as a narrator. Two, one male and one female chosen by the speaker's gender, cost no extra generation time and remove most of the mismatch. Per race and age later is only a matter of more voice choices; the lookup is the same.

### (e) Who is speaking
| Text | Speaker source |
|---|---|
| Quest offer | The quest giver's creature ID from the open database (3,908 rows); an item or object start means the narrator |
| Progress and turn-in | The turn-in creature (4,069 rows) |
| Creature gender and race | The client's own creature display tables, already read by the pipeline |
| Gossip | Keyed by text hash today, so the speaker has to be attached: the open database links some gossip text to creatures, and the collector can record the NPC's creature ID with each line it records. forever-vo keys every gossip file by creature ID and text hash and makes one file per NPC |

### (f) Playback on Forever
- `PlaySoundFile` exists at runtime (forever-vo's global list for build 69893 and its use in `ForeverVO/Core/Audio.lua:42`, `PlaySoundFile(path, channel)` returning `willPlay, handle`). The 70170 UI extract has no documentation entry and no call site for it, so the signature is **[unverified]** from the client's own files. `StopSound(handle[, fadeTime])` is used throughout the extract (`blizzard_sharedxml/loopingsoundeffect.lua:39`).
- Format: the extract names no `.ogg` or `.mp3` for addons. forever-vo ships mono, 22.05 kHz, 32 kbps constant-rate MP3 written without the Xing header; with the header the client cut lines short (`tools/release_pack.py:89-100`). An addon's own `.ogg` on Forever is **[unverified]**.
- The SFX channel must be on for `PlaySoundFile` to play on any channel (`Audio.lua:18-28`). forever-vo turns the `Sound_EnableDialog` setting off while a line plays, so the English NPC bark does not talk over it, and restores it after.
- Nothing here needs forever-vo's code, and none will be used: a player is `PlaySoundFile`, `StopSound` and a short queue, written for this addon, so the voice work owes it no credit. (Its text lines keep their credit in ATTRIBUTION.md for as long as they are used.) Its talking-head frame is not wanted: the quest and gossip windows already show the text being read.

### (g) Size
Measured on the AivisSpeech samples: 7.5 characters a second of speech, and 32 kbps MP3 is 14.4 MB an hour (24 kbps is 10.8 MB an hour, about 25% smaller, not yet judged by ear).

| Scope | Characters | Audio | 32 kbps | 24 kbps |
|---|---|---|---|---|
| Quest description | 2.13M | 79 h | 1.14 GB | 0.85 GB |
| Turn-in | 0.99M | 37 h | 530 MB | 400 MB |
| Gossip | 0.54M | 20 h | 290 MB | 215 MB |
| Progress | 0.22M | 8 h | 120 MB | 90 MB |
| forever-vo's scope (the four above) | 3.88M | 144 h | 2.1 GB | 1.55 GB |
| Objectives | 0.78M | 29 h | 420 MB | 310 MB |

CurseForge's limit is known only from forever-vo's experience, not from a CurseForge page [unverified]: a 1,378 MB zip was refused on the site, and the API answered `413` at 574 MB and at 887 MB while files of 350 MB and under went through. So a pack should stay under about 350 MB for CurseForge, or ship as a GitHub release asset, which allows 2 GB per file. So the audio ships as separate pack addons that depend on the main addon, cut by quest level, each a few hundred MB at most; the main addon never carries audio. The split, the bitrate and the host are decided after the first in-game pass, not before.

### (h) The character's spoken error lines
"Out of range", "Not enough rage" and the rest are the publisher's recordings, played from plain Lua, not from protected code: `UIErrorsMixin:TryDisplayMessage` calls `C_Sound.PlayVocalErrorSound(voiceID)` when `GetGameMessageInfo` returns a voice (`blizzard_uierrorsframe/mainline/uierrorsframe.lua:146-157`). The Forever override shortens the blacklist to one message type, so these errors are shown and voiced on Forever (`camelot/uierrorsframeoverrides.lua:1-3`). The setting `Sound_EnableErrorSpeech` turns them off (`blizzard_settingsdefinitions_shared/audio.lua:504`).

The archive holds 1,024 of the 1,025 listed files, `sound/character/<race>/<race><gender>errormessages/*_err_<kind>NN.ogg`, 38 kinds for 8 races in both genders. `MuteSoundFile` and `UnmuteSoundFile` are in the runtime global list but in no UI source. An addon could unregister `UI_ERROR_MESSAGE` on the frame or replace the method and play its own file; whether the engine checks the error-speech setting on its side is **[unverified]**, settled by one in-game check. This is later scope.

### (i) Hosted services, for reference only
Not used; the maintainer ruled generation stays local. Prices read 2026-10-04 from each provider's own page, one pass of 4.65M characters:

| Service | Price per 1M characters | One pass | Free tier |
|---|---|---|---|
| Google Standard, WaveNet (listed as legacy) | $4 | $18.60 | 4M a month |
| Google Neural2 | $16 | $74.40 | 1M a month |
| Google Chirp 3 HD | $30 | $139.50 | 1M a month |
| Azure neural | $15 | $69.75 | 0.5M a month on the free tier only |
| Azure neural HD | $22 | $102.30 | same |
| OpenAI tts-1 / tts-1-hd | $15 / $30 | $69.75 / $139.50 | none |
| OpenAI gpt-4o-mini-tts | token priced | about $200 [estimate] | none |
| ElevenLabs Multilingual v2 / Flash | $80 / $40 | $372 / $186 | free plan is non-commercial |

Pages read: cloud.google.com/text-to-speech/pricing; azure.microsoft.com/pricing/details/cognitive-services/speech-services (figures from the retail prices API, since the page rendered no numbers); developers.openai.com/api/docs/pricing; elevenlabs.io/pricing/api. The OpenAI token-priced row is an estimate from about 350 characters a minute of speech.

## Recommendation
**Go, with AivisSpeech, built in small steps.**

1. Engine: AivisSpeech Engine, local, on the processor. Chatterbox is out.
2. Voices: two ACML 1.0 voices, one male and one female, chosen by the speaker's gender; the male voice doubles as the narrator for item and object quests. Credit both and the engine on the pack's page even though ACML makes it optional.
3. Names: read as written. When Japanese names become an option, the audio is made from the katakana text; each file carries the hash of the text it was made from, so only changed lines are remade.
4. Speed: `speedScale` 0.9, the maintainer's choice by ear (1.0 a touch fast, 0.8 too slow). One set at that speed; a second set only if a setting is ever wanted, since speed cannot be changed at playback.
5. The player's name, class and race: a neutral word for the name (冒険者); class and race either a neutral word or files per class and race, decided by size.
6. First build, before any full run: the night elf starting quests in Shadowglen (about a dozen quests, their gossip greetings and the druid trainer's lines, roughly 60 files), one small pack copied straight into the test client, and an in-game pass on a new night elf druid. It covers male, female and narrator speakers and the whole path from data to playback.
7. Only after that pass: the full generation (about 2 days), the pack split, the bitrate and the host.

What the build takes: a collector change to record the speaking NPC's creature ID; a speakers table and a creature to voice table in the data, with provenance; a `voice` pipeline stage that drives the engine and writes MP3 with fingerprints; a voice module in the addon (play on the surface hooks, stop on close, on the reveal key and on the master switch, mute the English bark while playing, one setting per kind); a pack addon that depends on the main addon. The on-screen contract changes by one audible addition and, at most, a small replay control on the quest and gossip frames.
