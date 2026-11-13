# ADR-088: The voice panel's head is drawn from a display id

- **Status:** Accepted
- **Date:** 2026-11-13
- **Deciders:** the maintainer
- **Related:** [ADR-063](063-the-voice-panel.md) (the voice panel and the remembered speaker) · [ADR-020](020-quest-cache-harvest.md) (the quest cache, read only by local tooling) · [ADR-068](068-quest-cache-pinned-apart-from-the-tables.md) · [Voice over](../systems/voice.md) · [Data model](../architecture/data-model.md#voice-over-tables)

## Context

A quest played from the quest log has no NPC on screen. The voice panel drew its speaker with `SetCreature(creature id)`, which needs the client's creature cache: the record the server sent about that creature. The client empties that cache on every new build. After a patch and a restart, the quest log's replays showed no head until the player met each NPC again. The maintainer reported it after a reload and a restart: the remembered speakers were all saved, with their creature ids, but the patch had emptied the cache (it held 32 of the 192 remembered quest givers).

A second fault made it worse. The head waits 0.6 s for its model and hides when none has loaded. A model that arrived after that stayed hidden.

The maintainer's requirement: heads keep working across client patches and never depend on the client's cache being filled again.

What the client source shows (build 1.60.1.70888):

- `SetDisplayInfo(displayID)` draws from the client's own model data, which ships with every patch. It needs no creature record and no server query.
- Blizzard draws NPCs who are not present this way: the talking head (`blizzard_framexml/talkingheadui.lua:173`, `model:SetDisplayInfo(displayInfo)`) and the quest frame's portrait (`blizzard_uipanels_game/vanilla/questframe.lua:25`).
- `GetDisplayInfo()`, `SetDisplayInfo(displayID, mountDisplayID)` and `SetCreature(creatureID, displayID)` are in the model frame's API docs (`frameapicharactermodelbasedocumentation.lua:43, 153, 164`).

What the creature cache holds (build 1.60.1.70938): framed like the quest cache (header magic `BOMW`, build, locale, then `[creature id][length][payload]` records). Each payload carries the creature's display list. All 469 records read with one layout and every display list adds up. For the 421 creatures VMaNGOS also has, 410 first displays are one of VMaNGOS's and 11 differ: Forever draws those with newer models.

## Decision

1. **A speaker with no unit on screen is drawn with `SetDisplayInfo(display id)`.** The id is the one this player's client drew for that NPC, else the one the addon ships. Only with neither is it asked for with `SetCreature(creature id)`.
2. **The player's client remembers the display ids it drew.** When the head draws a speaker from the unit on screen and the client says the model has loaded (`OnModelLoaded`, never earlier: until then the frame answers with the model it held before), `UI/VoicePanelHead` reads `GetDisplayInfo()` and fires State `speakerDisplay(creature id, display id)`. While a voice pack is installed, `UI/VoiceQuestLog` saves it in `WFJ_DB.voiceDisplays[creature id]`, account-wide, numbers only, refreshed every time. A secret, missing or zero id is dropped. It is kept per creature, not per quest line: one NPC gives many lines, and the head keys on the creature everywhere else.
3. **The addon ships a display id for every speaking creature.** `wfj voice displays` writes `data/voice/displays.jsonl`, one row per creature `data/voice/speakers.jsonl` names, from the newest copied Forever creature cache that holds the creature (`creaturecache@<build>`), else VMaNGOS's first display (`vmangos@<commit>`). Rows are additive. `wfj generate` turns it into `Data/Displays.lua` (`WFJ.Data.displays`), loaded from the TOC after `Data/ErrorSounds.lua`.
4. **The creature cache is copied at every re-pull.** `make creature-copy` copies it (read only on the game folder) to `$(INPUTS)/creatures/<build>.wdb`, and `make wdb-copy` runs it for Forever. Its payload layout is pinned per build, like the quest cache's. The copy reads only the cache's header, so a new build's cache is always kept; `make voice-displays` leaves a cache whose build is not pinned yet out of the table, with a message, and a row a creature cache gave is never replaced by VMaNGOS. It is not backed up: playing fills it again.
5. **A model that loads late still shows.** When the model the head is waiting for loads after the 0.6 s, the head shows and the panel is told again. Nothing shows when the head moved on to another speaker or was turned off meanwhile.
6. **Each head drawn without a unit leaves a `voicehead` log entry** naming the source (`saved`, `shipped` or `creature`), the creature id and whether the model had loaded at 0.6 s (`model` or `no model`), with the display id; a model that arrives later adds a `late` entry. The log counts repeats of the same entry. The in-game check is read from it.

## Rationale

- A display id addresses data the client always has. A creature id needs data the client throws away on every patch.
- The client's own cache is the truth for which model Forever uses for a creature, so it wins over VMaNGOS. VMaNGOS fills in for creatures no copied cache holds, and agrees with the cache for almost all of them.
- What this player's client drew comes first, so a patch that renumbers a model is put right the next time the player sees the NPC.
- The table and the saved values are numbers keyed by creature id: no English, nothing a player typed.

## Consequences

- A quest log replay shows the giver's head after a reload, a restart and a patch, with no need to meet the NPC again.
- A re-pull has one more input to copy (`$(INPUTS)/creatures/<build>.wdb`) and one more command (`make voice-displays`). A new build's creature layout must be pinned before it is read.
- `WFJ_DB` gains `voiceDisplays`, bounded by the NPCs the player has met with the head showing. Older versions ignore it.
- At its first run, 2,321 of 2,585 speakers have a shipped display id, 131 of them from the 70938 cache.
- A model the client renumbers draws wrong until the player sees that NPC again.

## Not known

- **That `SetDisplayInfo` draws a creature the cache does not hold, after a full restart.** The source says it reads only the client's model data; it has not been seen in game yet. The `voicehead` log entries answer it ([Testing strategy → Voice panel checklist](../testing/strategy.md#voice-panel-checklist)).
- **Forever-only NPCs.** An NPC Forever added that no copied cache holds, and that VMaNGOS does not know, has no shipped display id. A quest the player took from them before the head remembered their display shows no head after a patch, until the player meets them again or a later re-pull copies a cache that holds them. The maintainer accepted this gap.

## Alternatives considered

- **Keep `SetCreature` and wait longer.** Still blank after every patch: the cache is empty, not slow.
- **A scan that asks the server about every speaking creature to fill the cache.** More in-game work for the maintainer, only to cover the Forever-only NPCs; players already remember a display as soon as they meet the NPC.
