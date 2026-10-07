# WoW Forever Japanese: Roadmap

> What is done, what is open, and what waits on a decision. How much of the game ships in Japanese right now: [Coverage](operations/coverage.md). The Forever beta opened on 2026-09-17; the game launches on 2026-11-04.

## Phase 1: Trusted data (done)
- **Goal:** `data/` seeded from the predecessor addons with only human translations that pass the rules: ID-aligned against the English, complete (never a first-paragraph-only translation), duplicates resolved by a stated rule ([ADR-001](adr/001-id-keyed-data-with-per-field-provenance.md), [ADR-011](adr/011-provenance-layers-and-completeness.md)).
- **Result:** the hand-written corpus, with corrections carried across every rebuild ([ADR-012](adr/012-human-decisions-survive-regeneration.md)). Every shipped hand-written line with English has since been read against it, and corrected or redrafted where it did not say what the English says ([Translation batches → The audit of the hand-written lines](operations/translation-batches.md#the-audit-of-the-hand-written-lines)).

## Phase 2: Addon (done)
- **Goal:** a clean rewrite with no dependencies: quest windows and log, gossip, books, item and spell tooltips, hold-a-key-for-English, the master switch and per-area toggles, settings pages, the bundled font, the English collector.
- **Result:** every surface in [App capabilities](app-capabilities.md). The whole game interface is in scope except names ([ADR-015](adr/015-ui-text-surfaces.md), [ADR-016](adr/016-whole-window-interface-coverage.md)): every window the Forever client loads has a recorded disposition, and a test fails when a new client build adds one nobody has read ([ADR-030](adr/030-every-window-the-forever-client-loads.md)). Word readings and the word card ship on quest and NPC-talk prose, window labels and plain-text book pages ([Readings](systems/readings.md)). Players can report a line from the game ([Fix reports](systems/fix-reports.md)).

## Phase 3: Beta (in progress)
- **Goal:** verify the addon on the Forever client, harvest its English, and measure what changed.
- **Done:** the addon runs on the Forever beta and targets it alone ([ADR-034](adr/034-forever-is-the-only-target.md)). The client tables and the quest cache are read from the installed client ([ADR-020](adr/020-quest-cache-harvest.md), [ADR-021](adr/021-client-tables-from-the-local-archive.md)), currently at build 1.60.1.70245. The English the collector records in game replaces stand-in English for quest and gossip text and is checked like any source ([ADR-053](adr/053-forever-shown-english-is-the-english.md)).
- **Open:** the in-game checks listed in [Testing strategy](testing/strategy.md). Most surfaces pass their stub-client tests and await a look in game on Forever.

## Phase 4: Translation (in progress)
- **Goal:** Japanese for every line a player can see, with readings and meanings where the type takes them, and a community corrections flow.
- **Done:** quest text, NPC dialogue and speech, book pages and the interface ship in Japanese almost in full; hand-written lines were audited; every shipped quest, gossip, interface and plain-text book line with a word to annotate carries its word list with meanings. The corrections flow is in place: in-game fix reports, checked on GitHub and turned into data by the maintainer ([runbook](operations/fix-reports.md)).
- **Open:**
  - **Item and spell descriptions whose English source is still the Classic Era input.** They wait for the Forever client's own English, then go through a [translation batch](operations/translation-batches.md).
  - **Each new Forever build.** Re-pull the English, redraft machine lines whose English moved, and review stale hand-written lines against their new English ([Release → Forever patch day](operations/release.md#forever-patch-day)).
  - **Quest turn-in and progress text Forever reworded.** Only the server sends it, at the NPC, so those quests show the stale marker until the text is seen in game and the collector dump is imported ([Collector](systems/collector.md)).
  - **Player reports** as they arrive.

## Voice over (in progress)
- **Goal:** quest and NPC talk read aloud in Japanese from the shipped Japanese, generated locally with AivisSpeech and shipped as a separate pack addon ([ADR-061](adr/061-voice-over-from-a-separate-pack.md), [research](research/2026-10-04-japanese-voice-over.md)).
- **Done:** the addon plays a pack's line when the quest or gossip window shows its Japanese, and stays silent for a line whose Japanese changed since the audio was made. The pipeline builds the speaker tables, the audio and the pack. The first pack covers the 16 night elf starting quests in Shadowglen and their NPCs' greetings: 48 lines ([Voice over](systems/voice.md), [runbook](operations/voice.md)). It passed its in-game check on a new night elf druid, play / stop button included ([Testing strategy → Voice over checklist](testing/strategy.md#voice-over-checklist)).
- **Open:**
  - **The packing ticket:** generating every line, splitting the pack, where it is hosted, and its sample rate and bitrate. The first pack's 22.05 kHz, 32 kbps audio sounds a little different from the 44.1 kHz, 64 kbps research samples; doubling it would bring the whole game to about 4.5 GB ([Voice over → Numbers](operations/voice.md#numbers)).
  - **Not voiced yet:** quest objectives, audio per class or race (the player's name, class and race are spoken as 冒険者 today), the trainer window's text, and the character's own spoken error lines.

## Release
- **Done:** one-action releases to CurseForge and GitHub ([Release](operations/release.md), [ADR-046](adr/046-one-action-release.md)); the CurseForge project exists and its id (1717928) is in the TOC.
- **Open:** the rest of the one-time setup (the `CF_API_KEY` secret on the public repository, the `main` ruleset bypass), then the first alpha.

## Each its own decision
- **Japanese names as an on/off option.** Today a Japanese name may only ever be an additional line, never on by default ([Principles §2](architecture/principles.md#2-names-stay-in-english)); an option would change that principle first.
- **Interface text still in English** by recorded exclusion: the trainer's "- Pet Spell" suffix, the pet XP bar, the "\<rank> of \<guild>" line, raid pullout labels and multi-unit reset times, the friends list's broadcast "(… ago)" tail, the XP bar help body. Each needs a composite form the dictionary does not have (`pipeline/ui_exclusions.txt`).
- **Two menu words with a different Japanese elsewhere** ("Slots" in the professions filter, "Ground" in the mount filter), not yet given their own Japanese.
- **The combat log** stays English: Forever hands addons a sealed string with no readable English ([ADR-035](adr/035-ui-errors-frame-surface.md)).
- **Inline icons in tooltips**: whether the client prints `$@spellicon` as a texture escape the addon can copy is an in-game check; until it passes, those lines may show English ([ADR-043](adr/043-included-text-icons-and-branch-variants.md)).
- **The QuestJapanizer wiki**: some complete hand-written quest descriptions exist only there, and its terms leave reuse to its administrator ([ADR-011](adr/011-provenance-layers-and-completeness.md)).
- **Memory**: the generated data with readings and meanings is large; its size is revisited once the translation work is done.
