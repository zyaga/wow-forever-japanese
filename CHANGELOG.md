# Changelog

What changed in each release of WoW Forever Japanese, written for players.

Every change that reaches the game adds a line under **Unreleased**, in one of these groups:
**Added** (something new), **Changed**, **Fixed**, **Removed**, **Breaking** (your settings are reset or
an old setting stops working). A release moves those lines under its version number. Versions follow
[Semantic Versioning](https://semver.org/); until the first full release they are alpha test builds.

## Unreleased

### Added
- A problem log for the addon (`/wfj log`). It notes when the game blocks the addon or a hooked part of the game stops answering, and keeps it across reloads so a problem can be traced afterwards.
- Japanese for the progress and turn-in text of 421 quests (630 lines), mostly ones new in Forever, from text Forever players recorded with the forever-vo addon. Its NPC greetings are read too.
- What NPCs say in chat is now recorded by the addon's collector, so Forever's own NPC speech can be translated.
- Send the English the addon recorded straight from the game: the **Send English** button on the English Collector page (or `/wfj collector send`) gives you one link that opens a filled-in GitHub issue. Click **I sent it** afterwards, and the next send holds only new lines. Lines that have a translation by then are left out.
- Japanese for 31 NPC lines on Zephras Isle, the Skyborne starting area, recorded by the addon's collector.

### Changed
- The collector's issue form is now *Collected English*, filled in from the game's send window. The saved file is only needed for a send too long to paste, and the settings page shows where it is (the beta's own folder on the beta).

### Fixed
- A quest window opened for the first time after logging in no longer turns back to English when its reward items finish loading.
- The stat changes in an item comparison ("+0.7 damage per second") show the stat in Japanese, the number as the game writes it.
- Long Japanese tooltip text no longer jumps between two line breaks while you hover a bag item.
- An item's quoted flavour text keeps its gold colour in Japanese instead of taking the colour of the line above it.
- NPC lines that use your class or race in the plural ("druids like yourself") now show their Japanese.
- A quest Forever repeats under several ids (such as Camping 101) shows the progress and turn-in text already translated for another copy, when its own text is the same.
- An error when hovering a creature whose quest title the game keeps hidden from addons.
- The Camp Benefits buff shows in Japanese, whichever camp items you have.
- A stat gain in an item comparison ("+17 Armor") keeps its green number in Japanese.
- "Interface action failed because of an AddOn" in combat, when a Japanese line appeared for the first time.
- Lua errors and blocked action bars when the game rearranged the screen (a level up, Edit Mode): the quest tracker no longer changes a value the game's own layout reads.
- The death recap link in chat ("[You died.]") shows in Japanese.
- In the quest log list, a finished quest with no counted objectives shows its objective line in Japanese, as the tracker already did.

## 0.1.0-alpha.5 - 2026-10-03

### Added
- Japanese for about 16,900 more spell and buff tooltip lines, so nearly every spell the Forever client serves has Japanese, and for 1,998 more interface strings, with word cards.
- Japanese for the quest, item, spell and interface text the Forever build 1.60.1.70170 added or reworded.
- Item flavour lines such as "Made With Love" are translated.
- The character window's new Titles tab is in Japanese, and so is the "No Title" row of its title list. The titles you earn are names and stay English.
- The group finder's playstyle, on a listing and on each search result, is in Japanese.
- Quest titles are Japanese in the NPC talk window's quest rows and on the quest greeting panel's buttons.
- A creature's tooltip shows its type on its own line and, for a quest it counts toward, the kill count in Japanese; the quest's title under a creature or on the minimap's quest block is Japanese too.
- The owner line under a pet, minion or guardian ("Bob's Pet") is Japanese.
- Chat uses the addon's Japanese font for every line and the input box, so Japanese you type and Japanese other players write are visible.
- Currency, mount, companion, equipment set, raid lock, totem and party quest-progress tooltips show their interface lines in Japanese; the name on the first line stays English.
- A quest's other wording for your class or race, and the line the tracker shows once some quests are ready, are read from the quest cache so they can be translated.
- Server notices in chat, spellbook flyouts, the transmog window's situation options and lock and requirement lines on objects can show Japanese.

### Changed
- The game text is read from Forever build 1.60.1.70170.
- The settings page title no longer wraps, the help page names your reveal key and both markers, and settings text has more space between lines.
- Next to a line that names your class or race, the English collector also notes that class and race, so a word that belongs to the line can be told apart from a word that changes with each player.

### Fixed
- A spell on your action bar keeps its Japanese tooltip in combat, the cooldown countdown included. A buff icon's tooltip stays English during a fight, because the game hides which buff it is from addons, and is Japanese again when the fight ends.
- The README and the CurseForge page explain that a buff on the target frame always shows English: the game draws that tooltip in a window addons cannot touch.
- The Legacy window's available points and the stable's pet diet tooltip are in Japanese again on the new build.
- Chat lines keep the right size after you change the chat font size.
- The quest window's reward headings ("You will be able to choose one of these rewards:", "You will also receive:") stay Japanese when the game loads a reward item's details after the window opens.
- Lines that stopped being translated because a game update did not list them for a while are translated again. A later update no longer takes Japanese away from something the game has shown before.

## 0.1.0-alpha.4 - 2026-10-01

### Fixed
- The settings page header reads WoW Forever Japanese (日本語化) in both languages, the addon's name as the addon list shows it.

## 0.1.0-alpha.3 - 2026-10-01

### Added
- Japanese for the quests, items and objectives the Forever build 1.60.1.70124 added or unlocked, including the holiday and reputation quests the client's own list leaves out.

### Changed
- The game text is read from Forever build 1.60.1.70124.
- The gamepad crosshair coordinates on the world map are translated on their own label, where the new build puts them.

### Fixed
- Chat lines that followed a Japanese system message no longer keep the Japanese font: once a line shows English again it gets the chat font back. The guild bank log had the same fault.
- Wrath's tooltip shows its damage range in Japanese; it fell back to English because the translation expected two numbers where the game prints one range.
- The Darkmoon Faire fortune quest's objective line for Mulgore no longer names Elwynn Forest.
- Tooltips from the hand-written corpus no longer break mid-sentence: the translators' manual line breaks, written for the narrow tooltips of the original client, are joined and the tooltip wraps at its own width.

## 0.1.0-alpha.2 - 2026-09-30

### Changed
- Stat words in item and spell tooltips read like the character sheet: 体力, マナ, アーマー, スタミナ, 筋力 and the rest, where tooltips used the English words.

## 0.1.0-alpha.1 - 2026-09-30

### Added
- Quest text in Japanese: the quest window, the quest log and quest objectives.
- NPC dialogue in Japanese: the talk window, speech bubbles, NPC chat and boss emotes.
- Books, letters and plaques in Japanese.
- Item and spell tooltips, and buff and debuff text, in Japanese, with the game's live numbers filled in.
- The game's interface in Japanese: windows, labels, menus, popups and messages.
- Hold Alt (changeable) to see the game's own English wherever Japanese is showing.
- Point at a Japanese word to see its reading and a short English meaning.
- Names of people, places, creatures, items and spells stay in English everywhere.
- Settings in Esc > Options > AddOns, or type /wfj config.
- Report a wrong or awkward translation without typing: the 字 minimap button (or /wfj fix) lists the lines you just read. Pick one, choose what is wrong, rewrite it if you like, and paste the report into the issue form.
- A 字 minimap button: left-click to report a line; right-click to turn translation on or off, open the settings or hide the button.
- The addon's own windows and settings read in Japanese; hold Alt, or turn translation off, to read them in English.

### Changed
- Linked the addon to its CurseForge project.
- Interface text reviewed against where each string appears: some labels shortened, some words changed to the sense the window uses, and the same game term now reads the same everywhere.
