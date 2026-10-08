# Voice over

> Japanese audio for quest and NPC talk, book and letter pages and the character's own error lines, read aloud from the Japanese the addon ships. The audio lives in separate voice addons (the Voice entry, `WoWForeverJapanese_Voice`, and the packs `WoWForeverJapanese_Voice<Name>`); the main addon holds the player and plays nothing without them. Code: `Core/Voice.lua`, `Core/VoiceQueue.lua`, `UI/VoicePlayer.lua`, `UI/VoicePanel.lua` (and `VoicePanelText.lua`, `VoicePanelHead.lua`, `VoicePanelLooks.lua`), `UI/VoiceErrors.lua`, the `WoWForeverJapanese_RegisterVoice` global in `Main.lua`, the `voice.*` settings, `pipeline/wfj/cmd/voice.py` (and `voice_cast.py`, `voice_audition.py`, `voice_make.py`, `voice_ship.py`, `voice_store.py`), `pipeline/wfj/core/voice.py`, `pipeline/wfj/core/casting.py`, `pipeline/wfj/io/aivis.py`, `pipeline/wfj/emit/voice_pack.py`, `pipeline/wfj/core/voice_packs.py`, `pipeline/wfj/io/curseforge.py`, the voice readers in `pipeline/wfj/io/vmangos.py`, `pipeline/voice.toml`, `pipeline/voice-packs.toml`, `data/voice/`. Decisions: [ADR-061](../adr/061-voice-over-from-a-separate-pack.md), [ADR-062](../adr/062-voice-cast-per-speaker-in-step-with-the-text.md), [ADR-063](../adr/063-the-voice-panel.md). Runbook: [Voice over](../operations/voice.md).

## Purpose
When the quest window, the NPC talk window or the book window shows a line in Japanese, a player with the voice installed hears it read aloud in Japanese, in the voice cast for whoever says it: a voice per kind of speaker (race or creature family, gender, age, archetype), the same voice for an NPC every time, a narrator for lines no creature says, and for book and letter pages the writer when the page is signed by a creature the game has, else a book narrator. While a line plays, the **voice panel** shows who is speaking and what is said, a sentence at a time, and the line goes on after its window closes. The character's own spoken error lines ("out of range") play in Japanese too, in a voice for the character's race and sex. The audio is made on the maintainer's computer with the AivisSpeech Engine, from the Japanese the addon ships, for every voiced line in the game: about 16,000 files, 1.2 GB, in the voice addons on CurseForge.

## How it works
```mermaid
sequenceDiagram
  participant C as Client (quest / gossip / book window)
  participant R as UI/Render
  participant S as Core/State
  participant P as UI/VoicePlayer
  participant V as Core/Voice
  participant VP as UI/VoicePanel
  C->>R: writes a line (Render.show)
  R->>R: shows the Japanese
  R->>S: fire "lineShown"(surface, record key, kind, id)
  S->>P: onShown
  P->>P: speaker(): creature id from UnitGUID (none for a book)
  P->>V: decide(surface, record key, kind, id, speaker)
  V-->>P: file path and length, or why not
  P->>P: panel on: queue the line (it waits while another plays)
  P->>C: PlaySoundFile(path, "Master"), dialog channel off
  P->>S: fire "voiceQueue"
  S->>VP: UI/VoicePanel draws VoicePlayer.state()
  Note over P: line ends (length + 0.5 s): the next waiting line starts
  Note over P: stops: setting off, loading screen, logout; panel Off also Alt and the window closing
  P->>C: StopSound, dialog channel back on
```

### What is voiced
| Window | Record | Pack key | Setting |
|---|---|---|---|
| Quest window, offer | `description` | `<quest id>-description` | `voice.offer` |
| Quest window, progress | `progress` | `<quest id>-progress` | `voice.progress` |
| Quest window, turn-in | `completion` | `<quest id>-completion` | `voice.turnin` |
| Quest window, NPC greeting panel | `greeting` | `g-<gossip key>` | `voice.greeting` |
| NPC talk window, greeting | `greeting` | `g-<gossip key>` | `voice.greeting` |
| Book window, a page | `page` | `b-<page key>` | `voice.books` |

`Voice.KINDS` holds this table. Objectives, titles, option rows and every other surface are never voiced. The character's error lines are not a window's line: `UI/VoiceErrors` follows the game's own vocal error call (below). Forever's trainer window has no greeting text (the UI extract's `blizzard_trainerui` holds no greeting string), so there is nothing to voice there.

### The packs
The voice ships as several addon folders, split by `pipeline/voice-packs.toml` ([Voice over → Which pack holds a line](../operations/voice.md#which-pack-holds-a-line)): the **entry**, which holds no audio and on CurseForge requires the main addon and every pack, and one folder per **pack**, named for what it holds (`…VoiceLevels1to10` to `…VoiceLevels51to60`, `…VoiceOther`). Each is under 420 MB, the most one upload can carry.

```
WoWForeverJapanese_Voice/                 the entry
  WoWForeverJapanese_Voice.toc            ## Dependencies: WoWForeverJapanese; no files to load; the main addon's icon
  README.txt                              the packs it installs
WoWForeverJapanese_VoiceLevels1to10/      a pack (and so on for the others)
  WoWForeverJapanese_VoiceLevels1to10.toc ## Dependencies: WoWForeverJapanese; the main addon's icon; English-only notes
  Register.lua                            one call: WoWForeverJapanese_RegisterVoice({ format = 2, folder = "<its folder>", lines = { … }, creatures = { … } })
  Sound/<file>.mp3                        one file per line, and per voice for a line several voices say
  README.txt                              what it holds, the line count, the credits
```

Each `lines` entry is `[<pack key>] = { <file name>, <Japanese hash>, <seconds>, v = { [<voice id>] = { <file name>, <seconds> } } }`, the `v` table only for a line said by differently cast creatures; `creatures` maps each speaker of such a line to its voice. The Other pack also carries the character's own error lines (`errors`: the game's voice id → kind, and per race and sex the file of each message and kind). Every voice addon depends on the main addon, so the AddOn List shows them all under it (the list groups one level deep). The Japanese hash is `Hash.key` (the same function as the gossip key, `hashing.key` in the pipeline) over the shipped Japanese with its tokens unfilled (`{name}` stays `{name}`). One entry may point at another key's file: the female wording of a gendered gossip line is its own gossip key and plays the same file.

### Registration (`Core/Voice.lua`, `Main.lua`)
- The pack's `Register.lua` runs in its own addon and cannot see the main addon's namespace, so it calls the global `WoWForeverJapanese_RegisterVoice(tbl)`. It forwards to `Voice.register(tbl) → registered, invalid`.
- A table with the wrong `format`, the wrong `folder` or no `lines` is refused whole (`invalid = 1`). A pack's folder must start with `WoWForeverJapanese_Voice`. An entry is kept only when its file name matches `^[%w%-_]+%.mp3$`, its hash is 16 hex digits and its length is a number or absent; anything else is dropped and counted. A file name outside the pack's `Sound` folder is never built, so a pack cannot play another addon's file. Packs merge by folder: a second pack adds its lines, and a second registration of the same folder replaces only that folder's lines.
- The pack loads after the main addon (it depends on it), usually after the settings pages are built. When the registration brings the first pack, `Options.addPage("voice")` builds the *Voice* page and adds it under the addon's category ([Settings](settings.md)); a failure is recorded in `WFJ.initErrors` (surface `options.voice`).

### The decision (`Voice.decide`)
`Voice.decide(surface, recKey, kind, id, who)` returns the file's path (`Interface\AddOns\<its pack folder>\Sound\<file>`) and its length, or nil and a reason, checked in this order:

| Reason | When |
|---|---|
| `kind` | the surface and record are not in `Voice.KINDS` |
| `off` | `voice.enabled` or the kind's setting is off |
| `english` | translation is off, or the reveal key is held |
| `nopack` | no pack registered |
| `missing` | the pack has no entry for the line's pack key |
| `notext` | the addon ships no Japanese for the line |
| `stale` | the pack's hash differs from the hash of the shipped Japanese |

A line with variants plays the file of the speaker on screen (`who`: its creature id and, for a creature shown as both genders, `UnitSex`), else the line's main voice. `missing`, `stale` and a played line (`matched`) are counted in `Voice.counts`, shown by `/wfj debug`. Core/Voice has no frames and no sound calls; its dependencies (lookup, hash, settings, reveal key, translation state) are passed in by `Main` at load.

### When a line starts
- `Render.show` fires State event `lineShown(surface, recordKey, kind, id)` only when the client has just written a line and the addon now shows it in Japanese (a write with the `apply` action). A refresh (the reveal key released, a setting switched) goes through `Render.refresh` and never fires it, so releasing Alt never restarts a line the player already heard. The event is fired under `pcall` after the write and the banner, so a failing listener cannot leave the window half translated. `UI/VoicePlayer` is its only listener.
- **With the voice panel on** (Panel size Full or Compact strip, the default): a line shown while another plays waits its turn in `Core/VoiceQueue` and plays when that one ends. A line already playing or waiting (same pack key) is not added again. A paused line gives way to the new one (the player has moved on). Each queued line carries what the panel shows: its Japanese as the window shows it (tokens filled in, an inline marker line removed), the English the client wrote into the window for it (memory only, never saved), the speaker's name and title as the client shows them now, and the speaker (creature id, sex, unit and GUID).
- **With Panel size Off:** one line at a time, as before the panel: a new line stops the one playing.
- Either way, the same line shown again while it plays is not restarted (the NPC talk window lays its first view out twice).
- A new line of a window that will not play (no file, `missing`, `stale`, `notext`; its kind switched off, `off`; or English showing, `english`) hides that window's button, so the button never replays the previous line. With the panel Off it also stops that window's line; with the panel on the line playing goes on (it may be another NPC's, kept after its window closed).

### Playing (`UI/VoicePlayer.lua`)
- `PlaySoundFile(path, "Master")` returns whether it will play and a handle; `StopSound(handle)` stops it. The `Master` channel keeps the line audible while the dialog channel is off. The client reports no end of a sound, so the line counts as playing for the pack's length plus 0.5 s (30 s when an entry has no length), timed with `C_Timer.After`; a timer from a line stopped early finds a newer token and does nothing.
- **Stops (always):** translation is switched off, any voice setting changes, a loading screen (`PLAYER_ENTERING_WORLD` ends the line and empties the queue), the player logs out (`PLAYER_LOGOUT`), the panel's close button, Panel size set to Off. `VoicePlayer.stop()` stops the sound and empties the queue.
- **Stops only with the panel Off:** the quest, NPC talk or book window hides (an `OnHide` hook on `QuestFrame`, `GossipFrame` and `ItemTextFrame`; a book's next page is a new line), and the reveal key going down. With the panel on, a closed window's lines keep playing and waiting while *Keep reading after the window closes* (`voice.panel.keep`) is on; with it off, the window's lines are dropped from the queue and, when the one playing was among them, the next waiting line starts. With the panel on, the reveal key never stops the voice: the panel shows the line's English instead (below).
- **A line the player asks for** (a window's or the quest log's play button, a row of the panel's waiting list) replaces the line playing: the interrupted line is dropped, never resumed after it. Lines waiting stay waiting.
- **Pause** stops the sound and keeps the line at the head of the queue; resume plays it again from the start (the client can only start and stop a sound file). Play again puts the panel's line (the head, or the last line once nothing is queued) at the front and plays it from the start. Key bindings: *Voice: pause / resume* (`WFJ_VoicePause`) and *Voice: play the line again* (`WFJ_VoiceReplay`), under the addon's header in the client's key bindings.
- **The game's English voice.** With `voice.muteDialog` on, while a line plays the addon sets `Sound_EnableDialog` to `0` if it was `1`, and records that in `WFJ_DB.voiceDialogMuted`. The client saves that setting, so a reload or a crash in between would otherwise leave the player's NPC voices off. It is put back to `1` when the line ends, on stop, at logout and on the next load (`VoicePlayer.init` restores it first). A player who had the dialog channel off keeps it off. Recovery by hand: `/console Sound_EnableDialog 1`.
- **The window button.** A 28 px button at the window's top right (`TOPRIGHT`, -8, -31), on the band below the title, raised 10 levels above the window's art. It shows only while the voice panel is not on screen (Panel size Off, or the panel faded after the line): the panel has its own controls. It shows once a line of that window has started and hides when the window closes or its new line will not play (no file, its kind off, or English showing). While the line plays it shows the client's stopwatch pause icon (`Interface\TimeManager\PauseButton`) and a click pauses the line (with the panel Off, stops it); otherwise it shows the play arrow (`Interface\Buttons\UI-SpellbookIcon-NextPage-Up`) and a click resumes a paused line of that window or plays the window's line again from the start, replacing the line playing. The client can only start and stop a sound file, so a line cannot resume where it stopped. A click never plays while English is showing or `voice.enabled` is off. No text on it; `voice.button` hides it.
- **The quest log button.** The same button at the right end of the quest log details' top bar (the world map's quest pane, `QuestMapFrame.DetailsFrame.BackFrame`), created on the first `QuestMapFrame_ShowQuestDetails`. Opening the log plays nothing (it is browsing). A click plays that quest's description as the pane shows it, voiced like its offer, through the queue and the panel like any other line, replacing the line playing; on the line playing it pauses (stops with the panel Off). It shows only when the line has audio, and `voice.button` hides it too.
- **The remembered speaker.** Every time the quest window shows its detail, progress or reward panel, translation on or off, `UI/QuestFrame` fires State `questShown(quest id, panel)` and `UI/VoicePlayer` saves the quest NPC in `WFJ_DB.voiceSpeakers["<quest id>-description|progress|completion"] = { c = creature id, s = UnitSex, n = name, t = title }`, account-wide, as the client showed them; seeing the NPC again refreshes it ([Data model](../architecture/data-model.md)). A replay from the quest log takes the head (by creature id), the name, the title and the voice variant from it. A quest taken before the addon saw it, or one a player, an item or an object gave, has none: the panel shows the quest's title and no head. Nothing about it ships. Measured before deciding against a shipped speaker table: forever-vo's Forever captures against VMaNGOS quest givers and enders, 1,983 lines, 1,074 the same NPC, 908 unknown to VMaNGOS, 1 different (with the same cast).
- **The title** is the second line of the client's unit tooltip (`C_TooltipInfo.GetUnit`), skipped when it holds a digit ("Level 12 Humanoid"). Live text, kept with the queued line for the session only, and in the remembered speaker.
- `VoicePlayer.counts` keeps `played` and `refused` (no `PlaySoundFile`, or the client would not play the file).

### The voice panel (`UI/VoicePanel.lua`)
While a voiced line plays, a panel shows it. `UI/VoicePlayer` decides what plays and fires State `voiceQueue` on every change; the panel only draws what `VoicePlayer.state()` reports (`item`, `playing`, `paused`, `startedAt`, `seconds`, `waiting`, `last`). It is built on the first voiced line, so without a pack no frame exists. It never shows while translation or `voice.enabled` is off.

- **Where:** bottom centre (`BOTTOM`, 0, 96, where the client puts its own talking head), strata `HIGH`, clamped to the screen. A left-drag moves it unless *Lock the panel where it is* is on; the position is saved in `WFJ_DB.voicePanel.point`. `/wfj panel reset` puts it back at the bottom centre.
- **What it shows:** the speaker's 3D head (`UI/VoicePanelHead`), the NPC's name and title as the client showed them (`<Innkeeper>`; a book shows its own name), and the line's Japanese a sentence at a time in step with the audio, with word cards on hover (surface `voicepanel`, [Readings](readings.md)).
- **Paging** (`UI/VoicePanelText`): the line splits after 。！？ and line breaks (a closing 」』） stays with its sentence); a sentence under 12 characters joins the next. Each page starts at its share of the line's characters, and the page shown is the one the audio's elapsed share has reached, checked every 0.1 s. There is no going back by sentence: the audio cannot jump, so the text does not either. After the line ends the last sentence stays; a paused line shows its first.
- **The head:** the unit on screen while it is still the speaker (`SetUnit`), else `SetCreature(creature id)` from the client's creature cache, which loads after `/reload` and a restart. A new client build empties the cache, so an NPC not seen since has no head. A speaker with no model (a book, the narrator, an uncached creature) gets no head after 0.6 s and the text moves left. It plays the talk animation while the line plays. *Show the speaker's head* turns it off.
- **Looks** (`UI/VoicePanelLooks`, data only): two dropdowns choose one of four. Panel size Full / Compact strip and Panel style Dark / Parchment give look 1 Full Dark (the client's talking-head art: dark translucent backdrop, square portrait ring, gold name, white text, 570 × 155), look 4 Full Parchment (the default: the same frame on the player's faction talking-head kit, `TalkingHeads-Alliance` / `-Horde`, else `-Neutral`, dark name, black text), look 3 Strip Dark (520 × 62: a small head, the name, one or two lines on a plain dark band) and look 5 Strip Parchment (look 3 on the plain middle of the faction parchment, a larger name in the faction colour, a thin dark frame round the head). All art is the client's own; the addon ships no image. A client without the kit atlases gets look 1.
- **Controls** (top right, one row, 28 px; the client's close button at 26 px): pause / resume, play again, whole text, close. With *Show the controls only while the mouse is on the panel* on they show only under the mouse. Whole text opens the quest in the world map's quest log when the line is a quest's, the quest is in the log and *The book button opens the quest in the quest log* is on; otherwise a small scrollable window above the panel (`WFJVoicePanelText`, 480 × 300) with the line's whole Japanese and word cards, on parchment when the panel's look is parchment. A second click closes it. Close stops the line and empties the queue.
- **The waiting list:** while any line waits, a compact list "Up next (click to play)" shows above the panel, as wide as its rows, one row per waiting line (`<name>  ·  Quest | Progress | Turn-in | Greeting | Book`), a faint gold band under the mouse. Clicking a row plays that line now and drops the line it interrupts. There is no next-line control and no count.
- **The reveal key:** holding it (default Alt) does not stop the voice. The panel shows that line's English as the client wrote it into its window when the line started, whole, with no word cards; releasing it goes back to the Japanese page the audio is on. The English is held in memory with that queued line only, never saved.
- **Fading:** with nothing playing (the line ended, or it is paused) and *Fade out after the last line* on, the panel fades over 0.6 s starting 3 s later. The mouse on the panel or the whole-text window being open holds it, and coming back during the wait or the fade brings it back whole. A panel that faded on a paused line stays away until something plays or the queue changes. With the fade off it stays until closed.
- **Combat:** with *Dim the panel in combat* on, its alpha is 0.4 between `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED`.
- **Settings changes** redraw the panel (State `voicePanel`) and never stop the line, except Panel size Off, which stops it and hides the panel. Switching back on brings the size it had before Off (`WFJ_DB.voicePanel.lastSize`).

### The character's error lines (`UI/VoiceErrors.lua`)
- The error frame's `TryDisplayMessage` plays the game's English line through `C_Sound.PlayVocalErrorSound(voiceID)`. A hook after that call notes the voice id; a hook after `TryDisplayMessage` reads which message it showed (`GetGameMessageInfo`) and plays that message's Japanese recording, so the voice says the words on screen; a call from anywhere else plays the voice id's kind line. Both hooks follow the client's code, never replace it.
- While a pack has lines for the character's race and sex, the client's error speech (`Sound_EnableErrorSpeech`) is turned off and the change kept in `WFJ_DB.voiceErrorSpeechMuted`; it is put back when switched off, at logout and on the next load. A player who had it off keeps it off. The same line is not started again within 2 seconds.

### Settings
`voice.enabled`, `voice.offer`, `voice.progress`, `voice.turnin`, `voice.greeting`, `voice.books`, `voice.errors`, `voice.muteDialog`, `voice.button` (label "Show the play / pause button on the window when the voice panel is not showing"), all on by default, on the *Voice* page. The panel's settings are on their own page, *Voice panel* (the settings pages do not scroll and the Voice page was full):

| Setting | Label | Default |
|---|---|---|
| `voice.panel.size` | Panel size: Off / Full / Compact strip (a dropdown) | Full |
| `voice.panel.style` | Panel style: Dark / Parchment (a dropdown) | Parchment |
| `voice.panel.keep` | Keep reading after the window closes | on |
| `voice.panel.head` | Show the speaker's head | on |
| `voice.panel.hoverButtons` | Show the controls only while the mouse is on the panel | on |
| `voice.panel.fade` | Fade out after the last line | on |
| `voice.panel.combatDim` | Dim the panel in combat | on |
| `voice.panel.questLog` | The book button opens the quest in the quest log | on |
| `voice.panel.lock` | Lock the panel where it is | off |

`Core/VoiceQueue.opt` maps the panel's choices onto these settings. Settings from earlier panel builds (`voice.panel`, `voice.panel.strip`, `voice.panel.parchment`, `voice.panel.queueBox`, `voice.panel.ruby`) are carried into Panel size and Panel style once and dropped. All voice settings are hidden (`Settings.isHidden`) until a pack registers: a player without the pack sees no setting that does nothing, in the settings pages or in `/wfj`'s status. Both pages sit under the addon's category ([Settings](settings.md)); the registration that brings the first pack adds both (`Options.addPage("voice")` and `("voicepanel")`, failures recorded as `options.voice` and `options.voicepanel`).

### `/wfj debug`
`voice: N lines (N invalid) · matched N · missing N · stale N · played N · refused N`, then `voice packs:` with each pack folder and its line count, a `voice panel: look N · N waiting · playing <pack key or none> · paused yes/no` line, and the error lines' counts (`voice errors: game asked N · message known N · played N · repeats skipped N · refused N`, and the last silent one). Without a pack: `voice: no pack`, with `(a pack registered an invalid table)` when one was refused. The About page names the packs that loaded, or shows the Voice entry's CurseForge address.

### The pipeline (`wfj voice`)
- **`speakers`** (`make voice-speakers`) writes `data/voice/speakers.jsonl` (pack key → its main speaker, a creature id or `narrator`, and `others` who say it too) for every voiced line ([Data model](../architecture/data-model.md#voice-over-tables)). From the pinned VMaNGOS database: a quest's offer is read by the creature that starts it, its progress and turn-in by the creature that ends it; a quest an object or item starts has the narrator; gossip menu greetings and quest greetings become gossip lines. The quest cache's conditional descriptions and forever-vo's player captures fill speakers the database lacks; a creature id the collector recorded (`npcs` in `data/english/gossip`) wins over the database ([Collector](collector.md)). A book or letter page is read by its writer when its last line is a signature naming exactly one cast creature, else by the book narrator. A signature is a name after one or two hyphens, an en or em dash or a tilde, maybe followed by a title after a comma or " - " ("- Windan Shay", "--VanCleef", "-Thrall, Warchief of the Horde"), or an undashed name that does not read as a title ("The End" does not count; a single word only under a closing line such as "Your friend,"). It also runs `levels`.
- **`profiles`** (`wfj voice profiles`) builds `data/voice/profiles.jsonl`: per speaking creature its race (or family), gender, age, archetype and role, from the client's display tables first, VMaNGOS second, and a machine casting pass for what only judgement gives, each field with its own provenance; a maintainer value is never overwritten.
- **`cast`** writes `data/voice/voices.jsonl` (creature → roster voice, and the cast row that chose it; a creature shown as both genders gets both) from the profiles, `voice.toml`'s cast rows and the overrides. A creature keeps its voice; neighbours spread over a row's voices.
- **`plan`** prints what `generate` would make now, by cast row and voice, with characters and hours.
- **`generate`** (`make voice-generate`, `make voice-run` for the whole game in the background) reads every voiced line's shipped Japanese through the local AivisSpeech Engine ([`pipeline/voice.toml`](../operations/voice.md#configuration): roster voices and their settings, pace) into the audio store (`build/voice/<key>[_<voice>].mp3`) and records each file in `data/voice/audio.jsonl`, with its size and SHA-256. The text read is the shipped Japanese with `{name}`, `{class}` and `{race}` spoken as 冒険者 and a `<…>` stage direction holding non-ASCII text dropped; any other markup stops the run with the line's key. A file is made again only when its fingerprint (Japanese hash, roster voice, style, speed, pitch, intonation) changed, so recasting one kind of speaker remakes only its lines; the engine version is recorded beside the fingerprint, not in it.
- **`pack`** (`make voice-pack`) writes the entry and every pack under `build/voice-pack/` from the audio record's files whose Japanese hash still equals the shipped Japanese (the rest are counted as left out), split by quest level as `pipeline/voice-packs.toml` says. A quest's level is Forever's own, from the committed `pipeline/voice_quest_levels.txt` (the quest cache's level at payload offset 8, else VMaNGOS). It prints each pack's size and room under the cap, marks a pack past 315 MB, and writes nothing when one is past 420 MB, when there is no audio store, or when a store file is not the recorded take (its SHA-256 differs from the audio record's: the one shared store may hold another branch's remake). The TOCs' `## Interface` is copied from the main addon's TOC.
- **`release`** (run by the voice job of the Release workflow; `make voice-release DRY=1` locally) refuses unless the audio store sits at the pinned commit, then builds, zips and checks every folder, uploads the packs whose content changed since the latest `voice-v*` GitHub release to their CurseForge projects (the entry when the set of packs changed), and makes one GitHub release with every zip and one zip of everything ([Voice over → Releasing the voice](../operations/voice.md#releasing-the-voice)).
- **`store-sync`** (`make voice-sync`; `voice-run` and `voice-generate` end with `store-sync --if-changed`, which does nothing when the run made no file) commits the audio store's new files to the audio repository (`zyaga/wow-forever-japanese-voice`, checked out at `build/voice/`), pushes, and writes that commit to `pipeline/voice-audio-commit.txt`: the audio that goes with this text.
- **`levels`** (`make voice-levels`, run by `voice-speakers`) writes `pipeline/voice_quest_levels.txt`, each quest's level from the quest cache and VMaNGOS, so `pack` and `release` split the packs without the client files.
- **`make voice`** runs speakers, generate and pack. `build/` is gitignored in this repository: the MP3s are committed only to the audio repository, the packs never.
- **`wfj validate`** checks `data/voice/` (`rule_voice`): well formed rows, provenance on each, no duplicate key or creature, a voice row for every creature that speaks, the casting in step with `voice.toml`, and prints how many files are in step, stale or not made.
- **The CI gate:** `tests/python/test_voice.py::test_audio_in_step` fails a pull request when a voiced line has no recorded audio, or audio made from other Japanese or in another voice. Remake with `make voice-generate`.

## Key files
- `addon/WoWForeverJapanese/Core/Voice.lua`: the registry, `decide`, `packKey`, counts. Pure.
- `addon/WoWForeverJapanese/Core/VoiceQueue.lua`: the order lines play in while the panel is on, and the panel's choices mapped onto the `voice.panel.*` settings. No frames, no sound calls.
- `addon/WoWForeverJapanese/UI/VoicePlayer.lua`: every sound and client-setting call for window lines, the queue's driver, the speaker and the remembered speaker, the window and quest log buttons, the window hooks, `state()` for the panel.
- `addon/WoWForeverJapanese/UI/VoicePanel.lua`: the panel's frame, layout, fade, controls, waiting list and `/wfj panel reset`. `UI/VoicePanelText.lua`: paging, each page's words, the English view, the whole-text window. `UI/VoicePanelHead.lua`: the model. `UI/VoicePanelLooks.lua`: the four looks as data.
- `addon/WoWForeverJapanese/UI/QuestFrame.lua`: fires `questShown` for the remembered speaker.
- `addon/WoWForeverJapanese/UI/VoiceErrors.lua`: the character's error lines.
- `addon/WoWForeverJapanese/Main.lua`: `WoWForeverJapanese_RegisterVoice`, the load steps `voice`, `voicequeue`, `voiceplayer` and `voicepanel`, `PLAYER_LOGOUT`.
- `addon/WoWForeverJapanese/UI/Render.lua`: fires `lineShown`.
- `pipeline/wfj/core/voice.py`: the scope, who speaks, the text read, the fingerprint, the in-step comparison, the validate checks. Pure. `pipeline/wfj/core/casting.py`: profiles and casting. Pure.
- `pipeline/wfj/cmd/voice.py`, `pipeline/wfj/io/aivis.py`, `pipeline/wfj/emit/voice_pack.py`, `pipeline/wfj/io/vmangos.py`.
- `pipeline/wfj/core/voice_packs.py`: which pack holds a line, content hashes and versions. Pure. `pipeline/wfj/cmd/voice_ship.py`: `pack` and `release`. `pipeline/wfj/io/curseforge.py`: the upload API.
- `pipeline/voice.toml`, `pipeline/voice-packs.toml`, `pipeline/voice_quest_levels.txt`, `pipeline/voice-audio-commit.txt`, `data/voice/` (profiles, speakers, voices, audio record, error tables).

## Invariants
- Japanese voice starts only while Japanese shows. The master switch stops it. With the panel Off, the reveal key and closing the window stop it, and nothing restarts it on release. With the panel on, the voice goes on while the reveal key is held (the panel shows the English the client wrote for that line, from memory) and, while *Keep reading* is on, after the window closes.
- The panel draws only; `UI/VoicePlayer` keeps every sound and client-setting call. Turning the panel off leaves the voice over as it was without it.
- The panel shows no shipped English. Names and titles on it, and in `WFJ_DB.voiceSpeakers`, are what the client showed this player, kept on the player's machine, never shipped.
- A line plays only when the pack's hash equals the hash of the Japanese the addon ships for that key. A stale or missing line stays silent; it never voices other words.
- The pack holds Japanese audio only; the speakers table holds keys and creature ids, never English. Names in the Japanese stay English and are read as written.
- The main addon never depends on the packs and reads them only through the registered tables. Without a pack nothing plays and no voice setting shows; the About page says the voice is not installed and shows the Voice entry's CurseForge address to copy, and with packs it names the ones that loaded.
- Every change to `Sound_EnableDialog` and `Sound_EnableErrorSpeech` is recorded in `WFJ_DB` and undone.
- An NPC always has the same voice; a line said by differently cast NPCs plays the voice of the one on screen.

## Edge cases
- A line whose Japanese changed after the pack was made: `stale`, silent, counted. `make voice` remakes only the changed files.
- A gendered gossip line: the female wording has its own key and plays the male wording's file.
- The player's name, class or race in a line: spoken as 冒険者.
- A reload or crash while a line plays: the next load turns the dialog channel back on.
- The pack loads before the settings pages exist: the *Voice* and *Voice panel* pages are built with the others (`requires`).
- Two NPCs talked to in a row: the second line waits in the list and plays when the first ends; a click on its row plays it now and drops the first.
- A quest replayed from the log that the addon never saw handed out: the quest's title stands in for the name, no head. After a new client build, heads come back as the NPCs are seen again; names and titles stay.
- The panel faded on a paused line: it stays away until something plays or the queue changes; the window button is back meanwhile.

## Not in this build
- Quest objectives (not voiced), audio per class or race (spoken as 冒険者).

## Unverified in game
Listed with their steps in [Testing strategy → Voice over checklist](../testing/strategy.md#voice-over-checklist): `PlaySoundFile(path, channel)` and playing an MP3 from an addon folder; setting `Sound_EnableDialog` from an addon; whether a new pack folder needs a full client restart; whether the Settings panel lists a subcategory added after `RegisterAddOnCategory`; whether the pack loads after the main addon's `ADDON_LOADED`. The panel's own steps are in [Testing strategy → Voice panel checklist](../testing/strategy.md#voice-panel-checklist); still unverified there: the talk animation id (60, the head's mouth moves) and the title being the unit tooltip's second line.

## Related
- [ADR-061](../adr/061-voice-over-from-a-separate-pack.md) · [ADR-062](../adr/062-voice-cast-per-speaker-in-step-with-the-text.md) · [ADR-063](../adr/063-the-voice-panel.md) · [Readings](readings.md) · [Voice over runbook](../operations/voice.md) · [Settings](settings.md) · [Collector](collector.md) · [Pipeline](pipeline.md) · [Addon modules](../architecture/addon-modules.md) · [Data model](../architecture/data-model.md) · [Research](../research/2026-10-04-japanese-voice-over.md)
