# ADR-061: Japanese voice over comes from a separate pack addon

- **Status:** Accepted
- **Date:** 2026-10-06
- **Related:** [ADR-002](002-live-english-only.md) (no stored English) · [ADR-005](005-gossip-key-fingerprint.md) (gossip keys) · [ADR-019](019-quest-english-per-field-and-live-check.md) (VMaNGOS as an input) · [Voice over](../systems/voice.md) · [Voice over runbook](../operations/voice.md) · [Research](../research/2026-10-04-japanese-voice-over.md)

## Context

The research found local generation with the AivisSpeech Engine good enough to listen to and fast enough to voice the whole game in a few days of machine time. The full audio is far too large for the main addon (gigabytes, against a main addon players download with every release). The client has no playback rate, so the reading pace is fixed when a file is made. And the Japanese keeps changing: batches, corrections and fix reports rewrite lines every week. A player must never hear audio for a line whose Japanese has since changed.

## Decision

1. **Audio is made locally from the shipped Japanese.** `wfj voice generate` reads each line through the AivisSpeech Engine on the same machine, in the voice of the creature that says it (male, female, or a narrator for a quest an item or object starts), and writes one MP3 per line.
2. **Each file is keyed like its Japanese, plus a hash.** A quest field's file is `<quest id>-<field>`, a gossip line's `g-<gossip key>`. The pack records the hash of the Japanese it was made from (`Hash.key` over the shipped text, tokens unfilled).
3. **The audio ships in a separate pack addon**, `WoWForeverJapanese_Voice`, which depends on the main addon and hands it one table through a single global, `WoWForeverJapanese_RegisterVoice`.
4. **The main addon holds the player.** It plays a line only when the quest or gossip window has just shown that line's Japanese and the pack's hash equals the hash of the Japanese the addon ships for that key. A missing or stale line stays silent.
5. **Japanese voice only while Japanese shows.** Holding the reveal key, switching translation off or closing the window stops the line. While a line plays the addon turns the client's dialog channel (`Sound_EnableDialog`) off, so the game's English voice does not talk over it, and always puts it back.

## Rationale

- A separate pack keeps the main addon small and lets players skip voice entirely. The two release on their own schedules.
- Keying by the text key plus a hash reuses the rule that every translation is addressed by its game id or text hash, and turns staleness into a comparison made in game, not a release-ordering problem between two addons.
- Local generation has no running cost. The voices used (阿井田 茂 and morioki) are under the Aivis Common Model License 1.0, which allows this use with credit; the pack's TOC notes and README carry it.

## Consequences

### Positive
- Main addon releases and pack releases are independent. A pack older than the addon goes silent line by line, never wrong.
- Without the pack the main addon does nothing new: no frame, no sound, no voice settings.

### Negative
- Every change to a voiced line's Japanese silences that line until the pack is made again.
- The addon writes one client setting (`Sound_EnableDialog`) while a line plays. It records that in `WFJ_DB.voiceDialogMuted` and restores the setting when the line ends, when it stops, at logout and on the next load. A player who had the dialog channel off keeps it off.

### Neutral
- The player's name, class and race are spoken as 冒険者: the pack is made before anyone plays. Audio per class or race is a size question for the packing work.
- A `<…>` stage direction written in Japanese is left out of the speech; any other markup stops generation with the line's key.
- One pack entry may point at another key's file: the female wording of a gendered gossip line plays the same file.

### Rollout
- The first pack covers the night elf starting quests in Shadowglen (16 quests, 48 lines) and is tested in game. Generating everything, splitting the pack, hosting it and choosing its bitrate are their own decision.

## Alternatives considered

- **Audio inside the main addon.** Rejected on size.
- **Keying audio by file order or a manifest index.** Rejected: every translation is addressed by id or hash, never by position.
- **Hosted text-to-speech services.** Rejected by the maintainer: generation stays local.
- **forever-vo's player and talking-head frame.** Not used: the quest and gossip windows already show the text, so the addon adds no frame beyond a small play / stop button.
