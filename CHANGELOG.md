# Changelog

What changed in each release of WoW Forever Japanese, written for players.

Every change that reaches the game adds a line under **Unreleased**, in one of these groups:
**Added** (something new), **Changed**, **Fixed**, **Removed**, **Breaking** (your settings are reset or
an old setting stops working). A release moves those lines under its version number. Versions follow
[Semantic Versioning](https://semver.org/); until the first full release they are alpha test builds.

## Unreleased

### Added
- When the English Collector holds 10 or more lines you have not sent yet, a line in chat at login or reload says how many are waiting and how to send them (`/wfj collector send`). It shows at most once a day, gives only the count, and a new setting on the English Collector page turns it off (`/wfj collector remind off`). The minimap button's menu also gets **Send collected English** with the count while any line is waiting.

### Fixed
- An item tooltip's red note "Cannot change equip status while in combat" was shown as a jumbled half-Japanese line (combatのCannot change equip status while). A wardrobe pattern ("<boss> in <instance>") had taken it. That pattern and the death recap's "<spell> by <caster>" now apply only where a window asks for them: the death recap keeps its line, and the wardrobe's source line, two names around "in", stays English. Lines the addon has no Japanese for stay in English.
- The group invite popup is now fully in Japanese: "<name> invites you to a group." (and the note that accepting takes you out of your queues) and its **Decline** button, which had stayed English after its half-second lock. A cross-realm invite's line is translated as well. The inviter's name stays English. Other popups whose whole line comes from the game as one known sentence (the question when you leave an instance group, and the trainer's "unlearn all of your talents?" and the pet-skills one) are translated too.
- The "World refresh in 29 Seconds" notice above the chat (and its longer first wording) is now in Japanese, with the time unit in Japanese too (ワールド更新まで29秒). It had stayed English.
- Nine lines Forever's NPCs say or yell that the addon had no Japanese for (heard by the English collector, for example "Go with the blessings of Al'Akir…" and "For the High Order!") are now translated, with word readings. So are six lines from the Goldshire campfire and mining scenes (for example "Go on and have a seat near the fire and we can get started.").

### Changed
- The problem log (`/wfj log`) now notes, for each NPC chat line, whether it was said to you and what the English collector did with it (yes/no flags only, never a name or the line's text), and it keeps the latest NPC lines even when the log is full.

## 0.1.0-alpha.8 - 2026-10-05

### Fixed
- What NPCs say, yell and emote in chat (for example "Gnarlpine Warrior attempts to run away in fear!") now shows in Japanese. It had stayed English in every build so far.
- The quest tracker's right-click menu is now fully in Japanese (Focus, Open Quest Map, Untrack, Share, Abandon). Only the quest's name stays English.
- The turn-in text of "Coldridge Valley Mail Delivery" is now translated in full; Forever's text is longer than the one the old translation covered.

### Changed
- The problem log (`/wfj log`) now records how every NPC chat line came out, translated or not, and says when NPC speech could not be set up, so a bug report can name why a line stayed English. It holds keys and yes/no flags only, never the line's text or the NPC's name.

## 0.1.0-alpha.7 - 2026-10-04

### Added
- Report a bug or send an idea from the game: `/wfj bug` (or **Report a bug or idea** in the 字 minimap button's menu) opens a window: pick **Bug** or **Idea** and open its link to the GitHub issue form. A bug report comes with the game build, the addon version and the addon's own Lua errors already filled in. Click **I sent it** afterwards, and the next report holds only new errors.
- The addon now keeps its own Lua errors (only errors raised in its own files, with your character's name left out), since the game hides Lua errors by default. The first one in a session prints one line in chat, and `/wfj log` ends with how many it holds. The game's Lua error window and addons such as BugSack still see every error.

### Changed
- The About page's issue link is now a **Report a bug or idea** button, and the bug report form says how to fill it in from the game.
- Inside the spellbook, the line under each spell ("Rank 1", "Passive", "Level 20"), flyout group names, search-result headers, the page number and the search suggestions now stay English. Writing Japanese into them is what made the action bars stop working in combat. The spellbook's title, search box and settings menu stay Japanese, and spell tooltips are unchanged.
- The 字 minimap button's right-click menu is now the addon's own small menu, with the same entries.
- The problem log now records where a blocked action came from: the call path at the block, the first action-bar setting the addon's taint reached, the code that wrote it and the game events before it. `/wfj taint` checks for it at any time.
- In the quest log, the `[要更新 / English Changed]` and `[未翻訳 / Not Translated]` markers now sit to the right of the 戻る button instead of above the description.

### Fixed
- The action bars no longer stop moving or disappear in combat ("Interface action failed because of an AddOn") after you hover spells in the spellbook. It showed when a rogue broke stealth or a warrior changed stance in a fight.
- Hovering a unit in combat no longer causes a Lua error in the addon.
- About 100 quest and NPC lines that address you as lad or lass, sir or ma'am no longer show English Changed, or show English, when the text has not changed. The Coldridge Valley mail delivery is one.
- Japanese for the profession guide in the starting areas (what professions are, the two kinds, where each trainer is), and for the cactus apple surprise turn-in text as Forever words it.

## 0.1.0-alpha.6 - 2026-10-03

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
