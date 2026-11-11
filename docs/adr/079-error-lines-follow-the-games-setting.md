# ADR-079: The character's error lines follow the game's Error Speech setting

- **Status:** Accepted
- **Date:** 2026-11-11
- **Deciders:** the maintainer
- **Related:** [ADR-061](061-voice-over-from-a-separate-pack.md) (the voice packs) · [ADR-062](062-voice-cast-per-speaker-in-step-with-the-text.md) (the voice cast) · [ADR-075](075-mute-the-english-voice-as-the-window-opens.md) (the dialog channel) · [Voice over](../systems/voice.md#the-characters-error-lines-uivoiceerrorslua) · [Data model](../architecture/data-model.md#voice-over-tables)

## Context

The character speaks a short line when an action fails ("Out of range"). The voice pack has those lines in Japanese. The client plays its English line through `C_Sound.PlayVocalErrorSound`, and checks its own Error Speech setting (`Sound_EnableErrorSpeech`) inside that call.

To keep the English line from playing under the Japanese one, the addon turned that setting off itself while a pack had lines for the character, and noted it in `WFJ_DB.voiceErrorSpeechMuted` so it could put it back. It then played the Japanese line without reading the setting.

Two things were wrong with that. A player who turned Error Speech off still heard the Japanese line. And the checkbox in the game's sound options no longer showed the player's choice, because the addon had moved it.

## Decision

- `UI/VoiceErrors.lua` never writes `Sound_EnableErrorSpeech`. It reads it before each line: on means the Japanese line plays, off means silence.
- While Japanese error lines can play for the character (translation on, voice on, error lines on, a voice pack with lines for the character's race and sex), the English recordings of that race and sex are muted with `MuteSoundFile`. They are unmuted with `UnmuteSoundFile` when any of those turns off, and at logout. A mute lasts until the client closes and is saved nowhere.
- The list of English recordings is generated data. `python -m wfj.dev.vocal_errors … --sounds-out data/voice/error-sounds.jsonl` reads the client's VocalUISounds and SoundKitEntry tables from the local install (read only, the same reader that writes `error-kinds.jsonl`) and writes one row per race id and sex with its file ids: 20 rows, 1,252 recordings. `wfj generate` turns it into `Data/ErrorSounds.lua` (`WFJ.Data.errorSounds[<race id>] = { m = {…}, f = {…} }`). The addon picks the list by the character's race id and sex.
- A setting an earlier version turned off (`WFJ_DB.voiceErrorSpeechMuted` set) is given back once at load, and the flag is cleared. That is the only write to the setting left.
- `/wfj debug` prints `voice errors: English recordings muted N`, and gives `setting` as the reason when a line stayed silent because Error Speech is off.

## Rationale

- The setting is the player's. Reading it gives the player one switch that means the same thing with or without the addon: error lines are spoken, or they are not.
- Muting the recordings by file silences only the English line, only for the character's race and sex, and only while a Japanese line can take its place. Nothing the player owns is changed, so nothing has to be recorded and put back after a crash.
- The list comes from the client's own tables, so it holds exactly the recordings the client can play for an error, and it holds file ids only, no text.

## Consequences

- The addon writes one fewer client setting. The dialog channel is now the only client sound setting it turns off and puts back ([ADR-075](075-mute-the-english-voice-as-the-window-opens.md)).
- A player with Error Speech off hears no error line in either language. A player with it on hears the Japanese line only.
- The addon ships a new generated file, and the list needs a refresh when a client build adds recordings: a new recording would play in English, under the Japanese line, until `wfj.dev.vocal_errors` is run again with `--sounds-out` and `make generate` rebuilds the file.
- A player coming from an earlier version, whose setting that version had turned off, gets it back once at the first load.
- Not verified yet: that a muted file silences `C_Sound.PlayVocalErrorSound` on Forever. It is an in-game check ([Testing → Voice over checklist](../testing/strategy.md#voice-over-checklist), step 15). If it does not, the English line plays under the Japanese one and this decision is looked at again.

## Alternatives considered
- **Keep turning the setting off** (the addon before). Rejected: the checkbox stopped showing the player's choice, and the Japanese line played for a player who had asked for no error speech.
