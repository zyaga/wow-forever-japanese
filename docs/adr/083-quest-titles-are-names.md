# ADR-083: Quest titles are names

- **Status:** Accepted
- **Date:** 2026-11-12
- **Deciders:** the maintainer
- **Related:** [ADR-009](009-surfaces-post-hook-the-writer.md) (the equality gate) · [ADR-029](029-camelot-targets-the-mainline-family.md) (the quest log) · [ADR-073](073-dialogue-ui-windows-get-our-japanese.md) (Dialogue UI's windows) · [Addon modules](../architecture/addon-modules.md)

## Context

Names of people, places, creatures, items and spells stay English on screen. Japanese is for prose. A quest's title was treated as prose and shown in Japanese: in the quest list, the tracker, the quest log, the quest window, the quest rows of an NPC's talk window, Dialogue UI's windows, tooltips and system messages.

A title is used like a name. It is what a player types into a guide site, what the game's own chat link shows, and what a party member reads on their own screen. A Japanese title in the list works against the sharing and finding the names rule exists for, and it made quest titles the one kind of name the addon changed.

The reveal key already gave the English back, so nothing was blocked. The default was the wrong way round.

## Decision

- A quest's title stays the client's English on every surface. No marker is written on it: it is not a missing translation.
- The quest's objectives, description, progress and completion text stay Japanese.
- Nothing is removed. The Japanese titles still ship in the data, and every surface keeps its code for showing one. One constant, `WFJ.QUEST_TITLES_JAPANESE` (`Core/Const.lua`), is false as shipped; true shows the Japanese titles again.
- The switch sits in the policy layer: `Translator.resolve` takes an optional `kindOff(kind)` and answers `leave` for a kind that is off. `Main` passes it for kind `quest.title`. Every surface asks the policy layer with that kind, so every surface follows.
- Two places read a title without the policy layer and check the constant themselves: `TooltipUnit.titleJapanese` (a quest title inside a system line) and the quest log's details, where a quest with no Japanese carries its one missing marker on its description instead of its title.
- There is no player setting. A setting that shows names in Japanese is not built.

## Rationale

- One rule for every name is easier to explain and to rely on than a rule with an exception.
- A constant keeps the work without adding a setting to support. The surfaces' title code stays covered by the specs, which run with the switch on.
- A names setting was weighed and left out. Names inside text the addon writes are cheap to change, but nameplates, unit frames, item and spell names on the game's own frames are not: each is a hook on protected or shared interface, and Japanese item and spell names cannot be typed into macros, the auction house or chat. Changing only the cheap half would leave a quest's text and the nameplate over the same character's head disagreeing.

## Consequences

- A learner no longer reads quest titles in Japanese by default.
- The word list still records a saved word's Japanese quest title: it is the player's own study data, and the list shows no English game text.
- What the title code reads in front of and around a title (the party count, the level, the quest's id, the failed wording) matters only with the switch on.
- Screenshots and store images taken before this change show Japanese quest titles.

## Alternatives considered

- **Keep Japanese titles.** Rejected: the one name the addon changed, against the reason names stay English.
- **A player setting for titles.** Rejected for now: nobody has asked, and each setting doubles what every surface has to be checked in.
- **Remove the Japanese titles and their code.** Rejected: the maintainer wants to be able to bring them back.
