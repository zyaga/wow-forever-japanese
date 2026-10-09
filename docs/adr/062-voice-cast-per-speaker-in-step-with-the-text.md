# ADR-062: Voice is cast per speaker, varies per line, and ships in step with the text

- **Status:** Accepted
- **Date:** 2026-10-08
- **Related:** [ADR-061](061-voice-over-from-a-separate-pack.md) (voice over from a separate pack) · [ADR-054](054-quest-text-keyed-by-its-english.md) (quest text keyed by its English) · [ADR-046](046-one-action-release.md) (one-action release) · [Voice over](../systems/voice.md) · [Voice over runbook](../operations/voice.md) · [Voice casting research](../research/2026-10-06-voice-casting.md)

## Context

The first voice pack read 48 lines with two voices chosen by gender. The whole game has about 2,500 speaking creatures of every playable race and many creature types, children to elders, humans to dragons, and gossip lines that several creatures say. One file per line and one voice per gender cannot carry that. The full audio is about 1.2 GB: too large for one CurseForge upload (the upload API refuses a request over 500 MB) and too large for the addon repository, which every working copy and every CI run checks out. And the Japanese keeps changing: batches, fix reports and corrections rewrite lines every week. A line whose audio was made from older Japanese must never play (ADR-061), and the maintainer wants that to hold every time without anyone remembering to remake the audio.

## Decision

1. **A speaker profile per creature** (race or family, gender, age band, archetype, role), built from the client's display tables and VMaNGOS, completed by a machine casting pass and ruled on by the maintainer. **A roster** of usable voices with their engine settings, and **a casting table** from kinds of speaker to ordered voices, with a stable pick per creature and an override table. The maintainer chose the voices by ear on audition pages before the full generation.
2. **Variants.** A line said by speakers who cast to different voices has one file per voice under the same key and Japanese hash (`<key>_<voice id>.mp3`). The pack carries creature to voice; the addon plays the file of the creature on screen (its id from `UnitGUID`), else the line's main voice. The pack table is format 2; format 1 still loads; several packs merge by folder.
3. **The audio record lives in this repository; the audio in a repository of its own.** `data/voice/audio.jsonl` records every made file (key, voice, Japanese hash, engine settings, length, provenance). The MP3s live in `zyaga/wow-forever-japanese-voice`, whose checkout is the audio store (`build/voice/` in the main checkout). A voice run commits and pushes what it made and writes that commit to `pipeline/voice-audio-commit.txt`, the pin that goes with the text. A CI test compares the record with the shipped Japanese and the casting: a voiced line with no audio, audio made from other Japanese, or audio in another voice fails the pull request.
4. **An entry and packs named for what they hold.** On CurseForge the voice is "WoW Forever Japanese Voice", a small addon with no audio whose file requires the main addon and every pack, so the CurseForge app installs everything from one click. The packs are split by quest level band (1-10, 11-20, 21-30, 31-40, 41-50, 51-60) plus Other (books and letters, the character's error lines, quests with no known level), each its own project, each under 420 MB with room to grow. The split is a committed table, `pipeline/voice-packs.toml`; a quest's level is Forever's own, from the client's quest cache, VMaNGOS second, committed as `pipeline/voice_quest_levels.txt`. A line's pack depends only on that line, so a fix re-releases one pack. The main addon never requires the voice; it names the entry as an optional relation so its page shows where the voice is. Every voice addon depends on the main addon, so the game never loads voice alone.
5. **One button releases everything that changed.** The Release workflow releases the main addon when the changelog has new lines, then a voice job checks out the audio at the pin (read-only deploy key) and uploads only the packs whose content changed, and the entry when what it requires changed. A pack's version is the date plus its content hash; "changed" is read from the latest `voice-v*` GitHub release's asset names, so no release state is committed. GitHub keeps every zip and one zip of everything for players who install by hand.

## Rationale

- Casting from a profile, not from a per-line list, keeps one voice per creature (an NPC never changes voice) and lets a casting change remake only the creatures it moved: each file's fingerprint carries its voice and that voice's settings.
- Variants are the smallest change that fixes shared lines: the key and hash stay the rule; only the file name gains a suffix the addon resolves from what is on screen.
- The committed record turns "remember to remake the voice" into a failing check, the same move that made readings travel with every translation.
- A repository of its own keeps every recording and every older take in the cloud, with history, while the addon repository, its worktrees and its CI stay small. The pin lets a release built on GitHub's servers use exactly the audio that goes with the text.
- Level bands give each pack room for new quests; a level from the client's own cache puts Forever's new quests in the band players meet them in.

## Consequences

### Positive
- Every speaker sounds like who they are; neighbours differ; a creature keeps its voice.
- A translation pull request cannot leave a voiced line silent by accident; the counts of stale and missing audio are always known.
- A recast or a fix releases only the packs it touches, from the same button as the addon.

### Negative
- A translation round needs the voice engine installed on the maintainer's computer (the voice step starts it for the run); a round that touches many lines waits for generation.
- A pull request from outside that changes a voiced line cannot pass CI until the maintainer remakes its audio on that branch.
- Two repositories must stay in step; the pin and the CI test hold them together.
- CurseForge reviews every file and accepts a relation only to an approved project. A new pack reaches the entry one release after its approval, and new lines can be silent until their pack's file passes review.

### Neutral
- Hash-keyed quest text (ADR-054) is voiced under its gossip key with the quest's speaker.
- Forever's trainer window has no greeting text; nothing is voiced there.
- Quest objectives are not voiced. The player's name, class and race are spoken as 冒険者.
- The AddOn List groups addons one level deep, so every voice addon sits under the main addon in that list.

## Alternatives considered

- **Two voices by gender for the whole game.** Rejected by the maintainer: a tauren elder, a human child and a dragon do not share a voice.
- **One file per line and creature.** Rejected: most lines have one speaker; per-voice files cover the shared ones with far fewer files.
- **The audio in the addon repository.** Rejected: every worktree and CI run would carry it, and the release packager would need to keep it out of the addon's zip.
- **The audio only on the maintainer's computer and a backup drive.** Rejected by the maintainer: every file must be in the cloud with history.
- **One file on CurseForge.** Not possible: the upload API refuses a request over 500 MB.
- **Fewer, larger packs.** Rejected: a pack at the cap has no room for new quests, and a full pack forces a re-split that moves lines and re-releases several packs.
- **The voice as a required dependency of the main addon.** Rejected by the maintainer: players may want everything but voice.
- **A separate release button for the voice.** Rejected: after a text change the addon and its packs would be released in two steps, and a forgotten step leaves new lines silent.
