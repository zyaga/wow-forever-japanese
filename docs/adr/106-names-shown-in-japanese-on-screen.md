# ADR-106: Names shown in Japanese on screen, when the player chooses

- **Status:** Accepted
- **Date:** 2026-11-22
- **Deciders:** the maintainer
- **Related:** [Principle 2: names stay in English](../architecture/principles.md#2-names-stay-in-english) · [ADR-078](078-japanese-names-keyed-by-english-and-kana-voice-lines.md) (name data) · [ADR-082](082-names-spelled-from-the-english-and-the-voice-reads-its-own-text.md) (names spelled from the English) · [ADR-083](083-quest-titles-are-names.md) (quest titles are names) · [Settings](../systems/settings.md) · [Addon modules](../architecture/addon-modules.md) · [Client limits](../architecture/client-limits.md)

## Context

Names of people, places, creatures, items, spells, zones, skills and factions stayed the client's English on screen,
and so did quest titles. Japanese was for prose. A learner reading a Japanese quest text still met every name in
Latin letters, and a Japanese player using the addon to play in Japanese saw a screen half in English.

The Japanese for every name already existed. The voice needed it: every English name the game shows has a line in
`data/name/`, keyed by the hash of its normalized English and spelled in katakana from the English word by word,
never translated ([ADR-078](078-japanese-names-keyed-by-english-and-kana-voice-lines.md),
[ADR-082](082-names-spelled-from-the-english-and-the-voice-reads-its-own-text.md)). The voice says those names in
every line. What the screen showed and what the voice said differed only because nothing put the names on screen.

ADR-083 left the setting as later work and gave the reason: names inside the addon's own text are cheap to change,
but nameplates, unit frames and the game's own frames are not, and changing only the cheap half leaves a quest's
text and the name over a creature's head disagreeing.

## Decision

1. **One setting, off until the player chooses.** `names.japanese` (boolean, default false), held in
   `WFJ.State.names` (`State.setNames` fires `"names"`). One row on the settings pages. The constant
   `WFJ.QUEST_TITLES_JAPANESE` is gone: quest titles follow this setting.
2. **Chosen in the welcome window.** Its first page asks "How should names show?" under the three purpose cards,
   with two choices, English names and Japanese names, each with an example (Marshal McBride / マーシャル・マクブライド).
   Nothing is written until Confirm. A player who already had the addon sees the window once more (saved flag
   `askedNames`).
3. **One list, shared with the voice.** The addon ships the `data/name/` lines as generated
   `Data/Names/Names_<nn>.lua` (`[hash] = "Japanese<TAB>reading"`, no English), listed last in the main TOC, inside
   the main addon and always in memory, so the setting switches at once with no reload. `Core/Names.lua` looks them
   up. A name with no Japanese stays the client's English.
4. **Words kept as written.** Abbreviations and the game's and company's own names (`pipeline/names_kept_as_written.txt`:
   AFK, Battle.net, Blizzard, PvP, XP, World of Warcraft and so on) are left out of the addon's tables, so the screen
   keeps them. Single letters and Roman numerals are kept without a line. The voice still says their Japanese.
5. **Names inside text.** The policy layer has a names step before placeholders are expanded: names inside quest,
   NPC talk, book, item and spell text and inside interface lines' Japanese are replaced by `Names.inText`, with
   markup protected (colour codes, links, textures, atlas icons, Battle.net name codes, plural codes, placeholders).
   The pipeline's `wfj.core.names.replace_runs` is the reference, and shared vectors hold the two together.
6. **Names as values.** An interface line's value can be a name, a list of skills or text with names in it; the
   line's key declares which (`Core/UIStringKeys.lua`).
7. **Names on widgets.** `UI/NameLabels.lua` writes a name onto a label, a unit's name, a title, or a name followed by
   a tail the client wrote. Every widget or text slot that holds a name is a line of `pipeline/name_surfaces.txt`,
   marked `japanese` or `english` with a reason, and a test fails while one is `todo` or a module's untouched widget
   has no line.
8. **What stays English, and why.** A player's, guild's or pet's name, and anything a player typed: the names
   step reads a line's stored text before the client's values are filled in, so a player called like a game name
   is never changed inside a line, and only a value declared as a game name is looked up. A value the
   client marks secret, such as a unit's name it hides in combat. Places where writing text taints a path the client
   measures on the way to a protected action: spellbook rows, the professions page's cast buttons, the world map's
   navigation bar. The name the client draws over a creature's head when it has no nameplate: no widget exists.
9. **Names over heads use nameplates.** When the player chooses Japanese names, the addon turns on the client's
   `nameplateShowFriendlyNpcs`, saves the earlier value (`namePlatesWas`) and puts it back when the player chooses
   English names. A value the player sets by hand afterwards is left alone, and one chat line says names over heads
   show in English while those nameplates are off. In combat the write waits for the fight to end. Creature
   nameplates and the target, focus, target-of-target, boss and party frames show the Japanese name. A nameplate
   measures its name and anchors its clickable area to it with a restricted call, so the nameplate name is kept
   only while a run in combat records no blocked action ([Client limits](../architecture/client-limits.md)).
10. **Name cards.** Pointing at a Japanese name on a word-card surface shows its reading and its English name. A name
    card is never saved to the word list.
11. **Race, class and faction** on a player's tooltip follow the setting, with the words prose already uses.

## Rationale

- The voice already says every name in Japanese. Showing the same spelling closes the gap between what the player
  reads and hears, at the cost of shipping a table the pipeline already builds.
- Doing every surface at once, nameplates and unit frames included, is what ADR-083 asked for before the setting was
  built: a half-done setting shows the same creature under two names.
- Listing every name widget in one file makes "every surface" checkable. A widget nobody decided about fails a test.

## Consequences

- Names on screen can match the voice. A learner can read names in kana and point at them for their reading.
- Every new surface that shows a name needs a line in `pipeline/name_surfaces.txt`.
- The names tables are in memory for every player, whether the setting is on or not.
- The addon writes one client setting (friendly NPC nameplates) on the player's choice, and puts it back.
- A name stays English wherever the client draws it or where writing it would taint a protected action. These are
  listed in [Client limits](../architecture/client-limits.md).
- The window test with Japanese names on, in and out of combat, is still owed; unit frames in combat are not yet
  seen in game.

## Alternatives considered

- **A separate load-on-demand folder, like the voice packs.** Rejected: the tables are a few megabytes, and switching
  names would have needed a reload.
- **Japanese names by default.** Rejected: names stay English until the player chooses; the welcome window asks.
- **A second audio version of each line with English names, for players who keep names English.** Never: there is
  one audio version of a line per voice, and it says names in Japanese.
- **Names only inside the addon's own text.** Rejected: the name over a creature's head and in its quest text would
  disagree (ADR-083).
