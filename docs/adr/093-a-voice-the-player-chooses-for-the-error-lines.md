# ADR-093: A voice the player chooses for the error lines

- **Status:** Accepted
- **Date:** 2026-11-16
- **Deciders:** the maintainer
- **Related:** [ADR-074](074-voices-cloned-from-the-games-npc-voice-sets.md) (every voice cloned from a game voice set) · [ADR-079](079-error-lines-follow-the-games-setting.md) (the error lines follow Error Speech; the English recordings are muted) · [ADR-090](090-voice-in-sentences-with-real-timing.md) (Register.lua format 3) · [Voice over](../systems/voice.md#the-characters-error-lines-uivoiceerrorslua) · [Settings](../systems/settings.md)

## Context

The character's own spoken error lines ("out of range") play in Japanese in one voice: the player set cloned from the English error recordings of the character's race and sex. A player had no way to give their character another voice, such as a dwarf guard or a nerdy gnome.

The cast already has 56 NPC voices cloned from the game's own NPC voice sets ([ADR-074](074-voices-cloned-from-the-games-npc-voice-sets.md)). Each of them can read the same 50 error lines. The Skyborne have no player recordings, so their two player voices are two of the four Skyborne NPC sets.

## Decision

1. **One setting, `voice.errorVoice`.** A choice, default `auto`, listed only while a voice pack is loaded, on the *Voice* page's first section (*Japanese voice*), after `voice.button`. `auto` is the voice of the character's race and sex, as before.
2. **The menu.** A dropdown with *Automatic (your character's race and sex)* first, then one submenu per race (Human, Orc, Dwarf, Night Elf, Undead, Tauren, Gnome, Troll, Skyborne, Goblin). Each submenu lists that race's player voices (male, female; the Goblin has none), then the NPC voices of the cast for that race, each labelled by race, sex and type ("Dwarf, female (guard)"). 18 player voices and 54 NPC voices, 72 in all. The two Skyborne NPC sets the player voices use are listed once, as the player's.
3. **English menu text, Japanese name under it.** The menu entries are English: the dropdown's font has no Japanese glyphs. The chosen voice's name shows under the dropdown in the page's language ("ドワーフ・女性（衛兵）"), so a player reading the page in Japanese still sees which voice is set.
4. **Only voices the packs carry.** A voice no installed pack carries is left out of the menu, and a submenu with nothing in it is left out too. A saved choice the packs lack plays the character's own voice.
5. **The pipeline makes every NPC voice's error lines.** `--players npc` (and `all`, which `make voice-generate` passes) adds every NPC voice of the cast to the error jobs: `voice_make.npc_voices`, the cast's voices and female voices less those a player race speaks in. Each file's stem is `e-<line>-<voice id>`. `error_table` packs each voice's files under its voice id in Register.lua's `errors.voices`, beside the race-sex keys (`tauren-f`), only files in step with the shipped Japanese.
6. **The addon plays the chosen voice, and mutes the character's own.** `Voice.errorFile` plays the chosen voice's file for the message on screen, else for the voice id's kind. When the chosen voice lacks that line, or no pack carries the voice, it plays the character's own. It still needs the character's own race-sex lines (`Voice.hasErrors`), because the English recordings muted are always those of the character's race and sex, whatever voice is chosen. `Voice.hasErrorVoice(key)` answers whether a pack carries a voice.
7. **One list, kept equal to the pipeline's.** `Core/ErrorVoices.lua` holds the races, the NPC voices per race, the labels in both languages and the setting's definition. `tests/python/test_error_voices.py` fails when its NPC list differs from `voice_make.npc_voices` or its player races from `voice_make.PLAYER_RACES`.

## Consequences

- A player can give their character any voice the packs carry. The default is unchanged.
- The Other pack gains about 2,700 small files (50 lines in each of 54 voices), made and timed like every other voice file.
- A recast that adds or removes an NPC voice changes `voice_make.npc_voices`; the test then fails until `Core/ErrorVoices.lua` lists the same voices with a label.
- Rolling back is safe: an older addon reads `errors.voices` by the character's race-sex key only, so the voice id keys are never looked up.
- The settings page's choice row gains submenus (`choiceGroups`) and a caption in the page's language (`choiceTextJa`), which any later choice setting can use.

## Alternatives considered

- **A choice among the player voices only.** Smaller (18 voices, no new files), but it leaves out most of the voices the cast already has cloned, for about 2,700 small files.
- **A voice per error line.** Many more settings for a small gain. The game gives a character one voice for all its error lines.
- **Japanese menu text.** The dropdown's font has no Japanese glyphs, so Japanese entries would show as empty boxes. The chosen voice's Japanese name shows under the dropdown instead.
