# ADR-075: Mute the English voice as the window opens

- **Status:** Accepted
- **Date:** 2026-11-08
- **Deciders:** the maintainer
- **Related:** [ADR-061](061-voice-over-from-a-separate-pack.md) (the voice packs) · [ADR-063](063-the-voice-panel.md) (the voice panel) · [Voice over](../systems/voice.md) · [Research](../research/2026-11-08-voice-over-addons-dialog-muting.md)

## Context

With *Silence the game's English voices while a line plays* on, the addon turned the client's dialog channel (`Sound_EnableDialog`) off when its Japanese line started, and put it back when the line ended. The line starts only after the client has written the window's English and the addon has shown the Japanese in its place. The client starts the NPC's English greeting as the window opens, before that. So the greeting was cut off mid-word, or had already played by the time the Japanese began.

Three other voice-over addons were read ([research](../research/2026-11-08-voice-over-addons-dialog-muting.md)). forever-vo and VoiceOver mute when their line starts, as this addon did; forever-vo waits 1.2 s first so the greeting can finish. Spoken mutes in the window's own event, before its line is read, and only when it has a line for that window; the greeting is never heard. None uses `MuteSoundFile`. The maintainer chose Spoken's way on 2026-11-08.

## Decision

- `UI/VoicePlayer` listens to the events that open an NPC window: `GOSSIP_SHOW`, `QUEST_GREETING`, `QUEST_DETAIL`, `QUEST_PROGRESS` and `QUEST_COMPLETE`.
- In the event it works out the line the window will show from the client's English (the gossip key of the greeting text, or the quest id and field) and asks `Voice.decide` whether that line will play (`peek = "ahead"`: nothing is counted or recorded).
- When it will, the dialog channel goes off at once, under the existing rules: only with `voice.muteDialog` on, only when the player had the channel on, recorded in `WFJ_DB.voiceDialogMuted` so a reload or crash is undone at the next load.
- The mute is given back as soon as the window's line turns out not to play, and after 1.5 s when no line started. A line that starts holds it until it ends, as before.
- Nothing is muted ahead for a line with no file, a kind switched off, a line heard before (the first time only settings), the window's area (quests or gossip) switched off, while English shows, or while another line plays.

## Rationale

- Muting before the greeting is the only way it is never heard. Waiting for it (forever-vo) has the player hear English, then Japanese, on every window.
- Deciding with the same `Voice.decide` the line itself uses keeps the two in step: an NPC whose line has no Japanese audio keeps its English voice.
- The 1.5 s deadline is Spoken's: past it no line is coming, and the next NPC's greeting should be heard.

## Consequences

- The greeting of an NPC whose line is read aloud is not heard at all, not cut.
- If the line worked out in the event differs from the one the window then shows (a quest text the client changes after the event, a greeting whose text is not there yet), the mute is given back when that line does not play, or after 1.5 s. A greeting with no text yet in the event takes no mute, so it plays as before.
- The addon now changes a client setting the player owns before its own sound starts, for at most 1.5 s when no line follows. The rule that every change to `Sound_EnableDialog` is recorded and undone still holds.
- Not verified on Forever: that the greeting starts at the window's event and that a mute taken there silences it from its start. This is taken from Spoken's code and listed in the voice-over checklist.

## Alternatives considered
- **Keep muting when the line starts** (forever-vo, VoiceOver, this addon before). Rejected: it is what cut the greeting.
- **A lead-in before the line** (forever-vo's 1.2 s). Rejected: English then Japanese on every window, and a fixed wait does not fit every greeting.
- **`MuteSoundFile` on the greeting's file.** Rejected: the file is not known in the event, and no addon has shown it works for this.
- **Re-read an empty greeting several times while muted** (Spoken, every 0.2 s up to 5 times). Left out: the line comes from the event's text, and a greeting with no text takes no mute.
