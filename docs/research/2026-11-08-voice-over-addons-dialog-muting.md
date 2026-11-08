# Research: how other voice-over addons silence the NPC's English voice

> Three voice-over addons for World of Warcraft, read from their source on 2026-11-08, compared on one question: how and when each turns the game's own NPC voice off while its line plays. Only Spoken mutes as the window opens, before the line starts, and so is the only one that keeps the NPC's English greeting from being heard at all. None uses `MuteSoundFile`. The addon now does what Spoken does ([ADR-075](../adr/075-mute-the-english-voice-as-the-window-opens.md)).

- **Date:** 2026-11-08
- **Question:** Our Japanese line cut the NPC's English greeting mid-word, or started after it had played. Which moment and which mechanism should the addon use to silence the game's NPC voice, and what else from these addons is worth taking?
- **Sources:** the source of each addon, read at a fixed commit:
  - Spoken, github.com/rusty-key/spoken-wow, MIT, commit `94048c5`: `addons/Spoken/SoundQueue.lua`, `addons/Spoken/SoundUtils.lua`, `addons/Spoken/API.lua`, `addons/Spoken_Quests/VoiceOver.lua`.
  - VoiceOver, the AI_VoiceOver addon, commit `5cf7627`: `AI_VoiceOver/SoundQueue.lua`, `AI_VoiceOver/Utils.lua`, `AI_VoiceOver/Version.lua`.
  - forever-vo, github.com/quinn-dougherty/forever-vo, MIT, commit `d562be6`: `ForeverVO/Core/Audio.lua`, `ForeverVO/Core/Events.lua`. The addon's dialog-sound handling was already adapted from it (ATTRIBUTION.md).

## Options
| Option | Pros | Cons |
|---|---|---|
| Mute when our line starts (forever-vo, VoiceOver, this addon before) | Simple; nothing is muted for a line that never plays | The client starts the NPC's greeting as the window opens, so the mute lands mid-word or after the greeting is over |
| Wait for the greeting, then start our line (forever-vo's lead-in) | The greeting is never cut | The player hears English first, then Japanese; a fixed wait is too long for short greetings and too short for long ones |
| Mute as the window opens, when a line will play (Spoken) | The greeting is never heard; NPCs with no Japanese line keep their voice | Needs the window's line worked out from the event alone, and a deadline in case no line comes |
| `MuteSoundFile` on the greeting's file | Silences one sound only | No addon of the three uses it; the greeting's file id is not known in the window's event; not tried here |

## Findings

### The moment the mute is taken
| Addon | When | What |
|---|---|---|
| Spoken | In the window's own event (`GOSSIP_SHOW`, the quest events), in the frame the window opens, before its line is read off the window (`Addon:MuteGreetingAhead`, `Spoken_Quests/VoiceOver.lua`). Its comment: "An NPC's own greeting starts the moment its dialog opens", and its line is read "0.1s for gossip, 0.4s of stable globals for a quest" later. | Only when a pack has a line for that window (`ExpectedLine(event)`); a quest whose id is not known yet is muted too. `SoundQueue:MuteGameDialogueAhead` cuts the Dialog channel at once instead of fading it ("a fade lets its first half-second through"). |
| VoiceOver | Right after it calls `PlaySoundFile` (`SoundQueue:PlaySound`). | `SetCVar("Sound_EnableDialog", 0)`, only with its *AutoToggleDialog* option, a sound channel other than Dialog, and a client that is retail or has interface 60100 or higher (`Version:IsRetailOrAboveLegacyVersion`). Whether Forever's interface number passes that check was not looked up. |
| forever-vo | When its line starts: `Audio.Play` turns the channel off after `PlaySoundFile` says it will play. | The first line of an open dialog waits a lead-in of 1.2 s (`BARK_DELAY`, "the game's own greeting bark ... is usually under a second"), once per speaker while a quest or gossip window stays open, so the greeting finishes before the mute. |

### Giving the channel back
| Addon | When | Robustness |
|---|---|---|
| Spoken | When its queue empties. A mute taken ahead goes back after 1.5 s (`MUTE_AHEAD_SECONDS`) when no line is speaking, and at once when the read finds text but no line (`EndMuteGameDialogueAhead`). | Does not mute a channel the player had off (`SoundUtils:MuteChannel`), so lifting it never turns their NPC voices on. Restores on `PLAYER_LOGOUT`, which also fires on `/reload`. The record of the mute is not saved, so a crash mid-line leaves the channel off. |
| VoiceOver | When its queue empties: `SetCVar("Sound_EnableDialog", 1)`. | Sets it to 1 whatever it was before the mute, so a player who had NPC voices off gets them back. No saved record of the mute in these files. |
| forever-vo | When the queue drains or pauses (`Audio.Idle`). | Mutes only when the channel was on, and keeps the record in its saved variables (`ns.db.dialogMuted`), so a reload or crash mid-line is undone at the next load and at logout. This addon already worked this way. |

### Other ideas in these addons
- **Re-reading an empty greeting** (Spoken): on a first talk to an NPC the client has not shown before, the window's text can arrive after the event. Spoken reads it again every 0.2 s, up to 5 times, while its mute holds (`GREETING_TEXT_WAIT`, `GREETING_TEXT_TRIES`). This addon works out the line from the event's text; a greeting with no text yet takes no mute, and the greeting plays as before. Not adopted.
- **Once per greeting** (forever-vo): the lead-in is taken once per speaker per open dialog, so a quest picked from gossip does not wait again. The mute ahead needs no such rule: `onWindowEvent` does nothing while a line plays, and a second event's mute just takes over the first.
- **A game greeting first option** (Spoken's *Game Greeting First*): the line waits for the greeting instead of cutting it. Not adopted; a player who wants the English greeting can turn *Silence the game's English voices while a line plays* off.
- **Cut detection** (Spoken, `WatchForCut`): every 0.5 s, `C_Sound.IsPlaying(handle)` is asked whether the line still plays; when the client stopped it unannounced (alt-tab without sound in the background, a cinematic), the queue pauses instead of running on in silence until the timer ends. Whether `C_Sound.IsPlaying` exists on the Forever client was not checked. Not adopted in this change.
- **Fading** (Spoken): its normal mute fades the dialog volume down over a short time so an NPC is not cut mid-word, and cuts only for a mute taken ahead. This addon always cuts.
- **`MuteSoundFile`**: not used by any of the three.

## Recommendation
Do what Spoken does: in the event that opens the NPC window, work out the window's line and, when it will be read aloud, turn the dialog channel off at once. Give it back as soon as the line turns out not to play, and after 1.5 s when no line started; a line that starts holds the mute until it ends. Keep this addon's existing rules from forever-vo: mute only a channel the player had on, keep the record in saved variables, restore at logout and the next load. Recorded in [ADR-075](../adr/075-mute-the-english-voice-as-the-window-opens.md); described in [Voice over](../systems/voice.md#playing-uivoiceplayerlua). Cut detection with `C_Sound.IsPlaying` is worth a look once its presence on Forever is checked.

## Related
- [Voice over](../systems/voice.md) · [ADR-075](../adr/075-mute-the-english-voice-as-the-window-opens.md) · [ADR-061](../adr/061-voice-over-from-a-separate-pack.md) · [Japanese voice over research](2026-10-04-japanese-voice-over.md)
