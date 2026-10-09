# ADR-063: The voice panel: who is speaking, what is said, and a line that outlives its window

- **Status:** Accepted
- **Date:** 2026-10-08
- **Related:** [ADR-061](061-voice-over-from-a-separate-pack.md) (voice over from a separate pack) · [ADR-062](062-voice-cast-per-speaker-in-step-with-the-text.md) (voice cast per speaker) · [ADR-036](036-readings-hover-word-lists.md) (word readings) · [Voice over](../systems/voice.md) · [Settings](../systems/settings.md)

## Context

The voice over played a line only while its quest, NPC talk or book window was open, with a small play / stop button on the window. Players walk and fight while an NPC talks; closing the window cut the line, and once the window was gone nothing showed who was speaking or what was said. forever-vo's talking-head panel (MIT) showed what such a panel holds; the panel follows its design, and parts of its code (loading the head, the talk animation, the faction parchment, the quest log's play button) are adapted from forever-vo's addon, credited in `ATTRIBUTION.md`. This supersedes ADR-061's note that forever-vo's player and talking-head frame were not used. The look, the controls and what the panel keeps were chosen in game, copy by copy, from switchable variants built for that trial.

## Decision

1. **A panel draws, the player plays.** `UI/VoicePlayer` keeps every sound and client-setting call and drives an ordered list of lines (`Core/VoiceQueue`); the panel (`UI/VoicePanel`, `UI/VoicePanelText`, `UI/VoicePanelHead`, `UI/VoicePanelLooks`) only draws what `VoicePlayer.state()` reports.
2. **Lines wait their turn.** A voiced line shown while another plays waits; a compact "Up next (click to play)" list shows while any wait, and a click plays one now. A line the player asks for (a play button, a list row) replaces the line playing, and the interrupted line is dropped. No next-line control and no count.
3. **The line can outlive its window** (a setting, on by default), and the panel fades after the last line unless the mouse is on it or its whole-text window is open.
4. **Holding the reveal key shows English without stopping the voice** while the panel is on: the panel switches to that line's English as the client wrote it into its window when the line started, held in memory for that line only.
5. **Who is speaking comes from the game, not from shipped data.** The speaker on screen gives the head, name and title. For replays from the quest log, the addon remembers each quest line's NPC when the quest window shows it (creature id, sex, name, title, saved account-wide in `WFJ_DB.voiceSpeakers`); the head loads by creature id. A quest seen before this existed shows its title and no head.
6. **Four looks from two choices:** Panel size Off / Full / Compact strip and Panel style Dark / Parchment, all client art (the talking-head kits and their faction parchment); Full Parchment by default. Off turns the panel off and brings back the voice over as it was without it.
7. **Readings only in the word card.** Readings drawn above or after the words were tried and dropped.

## Rationale

- Keeping sound and drawing apart lets the panel be switched off with the earlier voice over behaviour intact.
- Remembering the speaker in game is right for Forever by construction and keeps itself current; a shipped speaker table or shipped names would copy vanilla data and go stale. Measured before deciding: forever-vo's Forever captures against VMaNGOS quest givers and enders, 1,983 quest lines: 1,074 the same NPC, 908 unknown to VMaNGOS, 1 different, and that one with the same cast.
- `SetCreature(id)` loads a model from the client's creature cache, which survives `/reload` and a restart (checked in game with creature 837); a new build wipes it, so the name and title are saved by the addon itself.
- Every variant the maintainer rejected in game is gone from the code.

## Consequences

### Positive
- Players can walk away from an NPC and still hear and read the line; a quest replays from the log with its NPC.
- The panel adds no shipped data and no dependency.

### Negative
- Quests taken before installing replay without a head until their NPC is seen again.
- After a new client build, heads load only for NPCs seen since (the cache is wiped); names and titles stay.
- The toggle contract ([Principles](../architecture/principles.md)) gains four amendments: the reveal key with the panel, the panel itself, the quest log control, and names and English kept locally from what the client showed.

## Alternatives considered

- **A shipped speaker table, names from VMaNGOS or the client's creature cache:** more pipeline, stale after renames, vanilla speakers; not needed by the measurement above.
- **A "+N" count, a floating list without clicks, a next-line control:** tried and rejected in game.
- **Readings above or in brackets after the words:** tried; collided with the name line; rejected.
- **The reveal key stopping the voice (the earlier rule):** kept only for players who turn the panel off.
