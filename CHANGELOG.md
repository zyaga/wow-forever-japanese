# Changelog

What changed in each release of WoW Forever Japanese, written for players.

Every change that reaches the game adds a line under **Unreleased**, in one of these groups:
**Added** (something new), **Changed**, **Fixed**, **Removed**, **Breaking** (your settings are reset or
an old setting stops working). A release moves those lines under its version number. Versions follow
[Semantic Versioning](https://semver.org/); until the first full release they are alpha test builds.

## Unreleased

### Fixed
- Action bars that stopped working in combat, and a vendor that refused to sell, after the Professions window (or another window with popup dictionary text in it) had been open. The addon kept a note on its own popup dictionary frames that the game's layout code also reads, and the game then treated its own windows as changed by an addon until a reload. The addon now keeps all of its notes in its own tables.
- The red error text ("Out of range.") is handled without replacing a function of the game's error frame, which had the same effect on the game's own code.
- The game's currency transfer window and other text that sizes itself to fit are written without leaving a value on the game's text widget.
- When the game does refuse an action because of the addon, a line in chat now says so once, with what to do (`/reload` clears it), and `/wfj bug` includes what the addon found so the cause can be fixed.
- A Lua error raised dozens of times in a row from the mail window ("bad argument #1 to 'SetFont'") when the reveal key was pressed or a setting changed while a mail row's expiry text showed. The addon tried to put back a font it had never recorded for that text. The same mistake is guarded in the NPC talk window and the Dialogue UI book. And one text the game refuses a write on no longer stops the rest of the screen from switching language: each line is handled on its own, and the error goes into `/wfj bug`.
- The reputation, skill and currency descriptions and the calendar's event descriptions are written without running the game's own scroll code. The addon used to update the scroll box itself after writing a longer Japanese text, which left the box's state marked as changed by an addon, and the game then treated the next things on that page as changed too. A Japanese description longer than the room the game measured for the English is now drawn slightly smaller so all of it can be reached.
- With Japanese names on, the faction names and the standing on each bar in the Reputation list were blank the first time the list was opened after a login or reload, until it was scrolled or opened again. They show at once now.
- The guild and community chat's date lines and "Message of the Day" label are shown in Japanese without changing the chat's stored lines. Changing them left the chat's scroll bar marked as changed by an addon.

### Changed
- The addon now checks, in the background, for values it left on the game's tables: one pass after login in steps of at most 2 milliseconds, then nothing unless the game refuses an action.
- With Japanese names on, the Professions window shows each recipe's name in its list and each reagent's name in the crafting form in Japanese, the counts as the game writes them, and the tools a recipe requires ("Requires: Forge"). A name with no Japanese yet stays English.
- The bug report form asks whether the problem still happens with only this addon on, and `/wfj bug` fills in the names of the other addons you have loaded, so a problem that needs two addons together can be found.

## 0.15.0 - 2026-11-26

### Added
- Word status. Give any word a status: Unknown, Learning, Known or Ignored (point at it and Shift+click to step it, Shift+right-click to ignore it). Words you do not know yet are underlined in quest text, NPC dialogue, books, the voice panel and a frozen tooltip, a soft green highlight picks out the most common words you do not know yet, and a small tag says how much of a quest, an NPC line or a book page you already know. `/wfj known` (or the Words settings page) opens a window where you paste a word list from Anki or another tool to mark every word the game uses as Known, and get your statuses back as text. Saving a word makes it Learning, and a word studied in game until its card is stable for three weeks becomes Known. The Words settings page has a switch for the whole feature, one for the underline under unknown words and one for the underline under words you are learning, a choice of what to highlight (common words, the only new word in a sentence, both, or nothing), the score tags, and each place; marks on chat are off until you switch them on. In English first it works on English words.
- The colorblind settings in the options window (the colorblind mode, the filter, its strength and the three filter types) are in Japanese, with word cards. The tool that lists the game's interface text had missed the file they sit in.
- Word cards on chat. Point at a word in any chat line and its word card shows: a Japanese word's reading and meaning in Japanese first, an English word's pronunciation and Japanese in English first, chat shorthand such as LFM, WTS and OOM included. The save click saves the word with the message as its sentence. The line itself is never changed. A setting on the Words page, Word cards on chat lines, turns it off.
- A phrase book for talking across languages. A small 文 button by the chat window opens it (drag it anywhere; the minus collapses it, the X hides it, `/wfj phrases` opens it again). Click one of 132 phrases in 9 topics and it is typed into the chat box in English with a small dot in front; press Enter to send. Players without the addon read plain English. Players with it see a gold 文 and the phrase in their own language. Holding the reveal key shows the message as it was sent.
- Copy a chat line. A small icon on the chat line under the mouse opens a box with that line selected, ready for Ctrl+C (Cmd+C on a Mac): only the message for a line a player typed, the whole line otherwise.
- Your own chat words. Add a Japanese word with its reading and meaning, or an English word with its Japanese, and it takes a card in chat from then on (the Words settings page, or `/wfj chatwords`). They stay on your account.
- Names in Japanese. A new choice in the welcome window, and on the settings page, shows the names of people, places, creatures, items, spells, skills and factions in katakana in place of the English: on tooltips, the quest and NPC windows, the target frame and nameplates, the map, loot, vendors, chat, and inside quest text. You choose English names or Japanese names, and with Japanese names holding the reveal key shows the English name as it does for everything else. Pointing at a Japanese name shows its reading and its English name.
- With Japanese names, a creature's name over its head shows on its nameplate, so picking Japanese names turns on nameplates for friendly NPCs, enemies and neutral creatures, out of combat too. It also shows nameplates from farther away and turns off the game's English names over NPC heads, so a far-off NPC never shows its name in English. Picking English names puts your settings back. Turn some nameplates off yourself and the addon leaves them off, and says in chat that names over those heads are English.
- Freeze a tooltip to read it. While a tooltip shows, press the Freeze the tooltip key (Ctrl+F, set once when nothing else uses that key; change it under Keybindings) and a copy stays in the same place with the comparison tooltips beside it. Move the mouse onto it and point at a Japanese word for its word card, and save words from it with the save click. The key again or Esc closes it. A copy made in combat, with translation off or while English is showing has no word cards. The welcome window names the key after you choose Study Japanese.
- Item and spell text has word cards: item descriptions and spell description and aura lines ship their words' readings, dictionary forms and meanings, shown on a frozen tooltip (a line holding an icon or link code has none). The saved word list names an item or a spell as a word's source.
- With a voice pack installed, a translated line that has no voice yet says so on its window: `[音声なし / No Voice Yet]`. A setting on the Voice page, Mark lines with no voice yet, turns the message off.
- Japanese names for 2,668 more creatures, most of them Forever's own that the name list did not have yet, so with Japanese names on their nameplates and tooltips show katakana too.
- Japanese for what Forever 1.60.1.70959 and 1.60.1.71037 added and for what players sent with the English Collector in 28 sends: 265 NPC lines, 325 quest progress and turn-in texts, 129 new quest titles with their objectives and descriptions (with word cards), and 45 item and spell tooltips.
- An Anki add-on that makes your cards. In desktop Anki (23.10 or later), open Tools → Add-ons → Get Add-ons and paste the code 612475471, and every word you save becomes a card in the deck WoW Forever Japanese, with the sentence, furigana on the back, the screenshot and the sentence in its NPC's voice. Words saved earlier are added too. New words reach Anki after a /reload or a logout. Cards you edit keep your edits, your study progress is never changed, and your other cards are never touched. Each card is tagged with the game it came from. Sync Anki on all your devices before you install or update the add-on: a new version can change the card's fields, and Anki then asks you to pick one side to keep.
- The word list window has a line about the Anki add-on, with its address to copy. The export text and its copy steps are as before.

### Changed
- The welcome window is now a short tour. After you pick what you are here for, it shows a page for each feature that fits your choice (reading in Japanese and the hold key, word cards and the word list, word status, freezing a tooltip, the chat tools, and names, reporting a line and the voice), each with a picture and a few lines on how to use it. Next and Back move through it and the last page's button closes it. `/wfj intro` opens it again.
- The English Collector now finds game messages in chat that nobody has translated yet, such as "Rex seems to be sobering up." It keeps only the name of the game's own text template for that message (here `DRUNK_MESSAGE_OTHER1`), never the message, so no player's name is kept. Send it in as before and those messages can be put into Japanese.
- The addon's key bindings have their own section, WoW Forever Japanese, in the game's Keybindings instead of sitting under Other, and their names are Japanese or English like the settings pages.
- The word card and the reading box have a solid background, so text behind them no longer shows through.
- The English Collector also keeps three numbers for each quest window you open: the id, the sex and the model id of the NPC that shows it, also for quests already in Japanese. They let each line be read in that NPC's own voice. No text and nothing about your character is added, and nothing is sent unless you send it.
- Quest texts and item and spell tooltips the game reworded on 1.60.1.70959 and 1.60.1.71037 follow the new wording.

### Fixed
- Chat word cards and the copy icon no longer throw an error, and stop working, while the mouse is over chat that the game keeps from addons. Those lines are skipped, and the chat underlines skip them too.
- Hovering a creature in combat no longer fills the error list. In a fight the game locks the text of a creature's tooltip, and a quest objective line on it was read anyway, thousands of times a session. Every place the addon reads text the game can lock in combat (tooltips, chat, combat text, nameplates) now checks first and leaves the game's own text alone.
- With Japanese names chosen, the voice panel's list of lines waiting their turn and its whole-text window show each speaker's name in Japanese too. They showed it in English.
- Using an item from your bags (the Hearthstone, food, a scroll at a vendor) could be blocked by the game with this addon named, after a talk with an NPC in Dialogue UI's window or after the interface was hidden and shown again. The addon no longer replaces any of Dialogue UI's own functions or runs inside the interface's return, which was one way that could happen; its Japanese in Dialogue UI is added after Dialogue UI draws. A block that still happens is kept in the addon's log, where other entries can no longer push it out.
- 138 crafting spell tooltips (potions, scopes, bombs, fireworks and more) held Japanese that did not read as a sentence. They now use the same Japanese as the item each one makes. Three item lines that named the wrong stat or number and one aura line with an English word left in it are fixed too.
- NPCs no longer speak in the narrator's voice. A quest line whose speaker the addon could not name was read by one narrator, an old tauren man, whatever the NPC's race or sex. Each line is now read in the voice of the NPC who says it. A line whose NPC is not known yet, or whose voice is not made yet, stays silent instead of being read in the wrong voice, so some lines that had a voice are quiet until the next voice pack release.
- Japanese that players write in the guild and community windows showed as empty boxes. It now shows in the addon's font, with translation on or off: the message of the day, the guild information, member and officer notes, rank names, the guild news line that repeats the message of the day, community names and descriptions, the guild finder's text, a guild bank tab's notes, and the title and description of a calendar event a player made. The boxes you type them in show Japanese as you type. Text with no Japanese keeps the game's own font.
- The name-and-icon popup shows its labels in Japanese wherever the game uses it: equipment sets, macros, guild bank tabs, bank tabs and transmog outfits.
- In the guild window, the "Show Offline Members" box, an offline member's last-seen line, the names of the guild's own chat channels and the news pane's heading are Japanese.
- An item or spell tooltip no longer shows its numbers in the wrong places when the game has added or removed a number in that tooltip since the translation was made. Such a tooltip stays English until its translation follows.
- An item's flavour text no longer appears on its "Use:" line with the flavour line left empty. It happened on an item whose tooltip has more lines than its translation was written for.
- An item with several "Equip:", "Use:" or "Chance on hit:" lines shows each of them in Japanese, where it used to leave some English and put the Not Translated mark on the wrong one: mana and health per 5 seconds and spell power lines, a line printing another spell, and an item's own line with a cooldown after it.
- The quest log says `[音声なし / No Voice Yet]` for a quest whose offer has no voice yet, as the quest window does.
- A holiday's description on the calendar, the mount journal's search hint and the rank titles on the challenges page are Japanese.
- The role poll a group leader starts, the game's plain message box, the Cancel button of the cooldown settings' layout dialogs, and a recipe opened from a link in chat show their labels in Japanese.
- The "Press Tab" hint under the list of names that appears while you type a name is Japanese.
- The mail window's tooltip on the Cash on Delivery button, shown while Cash on Delivery is disabled, is Japanese. The line is new in this build.
- In an instance lock's tooltip, a boss not yet defeated reads 未討伐. It showed 在席, the friends list's word for "Available".
- The objectives of the quest A Humble Task no longer carry the English for "water well" in brackets after the Japanese word (a player's report).
- A mount's, a companion pet's and a macro's tooltip are Japanese, like a spell's own tooltip.
- A spell tooltip with a damage range of 1,000 or more ("1,350 to 1,650") no longer stays English.
- With Japanese names on, the names inside quest objective lines are Japanese on the tracker, in the quest log and on a creature's tooltip: the creature in "Wastewander Banditを倒す: 0/10", and the item in a count line, which now reads "ソリッド・シャープニング・ストーン: 0/8". So are the names the game fills into other lines, such as a pet's owner, an enchant on an item, a profession a socket needs and a faction on a reward, the currencies and item in a vendor's "exchange for" question, and a tracked recipe with its reagents. A failed quest's line on the tracker reads 失敗.
- A spell tooltip that includes another spell's text, such as Metamorphosis with Demon Charge and Demonic Howl, or Druidic Auras with its two auras, no longer stays English when your character has not loaded those spells. The game leaves their text empty until it has them, so the addon asks for them, and the tooltip shows Japanese from then on.
- A spell with a shortest and a longest range ("8-30 yd range") shows its range line in Japanese.
- The group finder's who list title, its Filter button, the playstyle prompt and the Back button are Japanese.
- The English Collector no longer counts spell tooltips that already have Japanese as untranslated, and its reminder no longer opens underneath the welcome window.
- Three spell tooltips that stayed English because of one word now show in Japanese.
- The chat lines that say how drunk you or a player nearby are ("You feel tipsy. Whee!") are Japanese.
- With Japanese names, the spell Blizzard shows its Japanese name. It stayed English because the word is also the company's name.
- The friends window is Japanese: its tabs, the friends and ignore lists' labels, the recent allies, quick join and recruit-a-friend pages, and the add-friend dialog.
- With Japanese names, an item set's heading over its set lines shows the set's name in katakana ("クロルドク・バトルギア (3/5)"), and so do the names inside its bonus lines. A bonus line the game shows before its text has loaded ("(4) Set: ") reads (4) セット:.
- An item whose text is a use or hit line and a flavour line shows each in Japanese on its own line. Where the durability line stood between them, both went onto the first line and the flavour line stayed English.
- The professions page shows each profession's rank (Apprentice, Journeyman) in Japanese, and with Japanese names its spells' names and the profession tabs' tooltips.
- The group finder's Post button says in Japanese why it cannot be pressed, the quest log's tooltip shows a quest's tag (Elite) in Japanese, and with Japanese names a quest's map pin shows its title in Japanese.
- Spell tooltips that stayed English now show in Japanese: the reagents and tools a spell needs, a recipe's name line ("Enchanting: Enchant Boots - Minor Speed"), the item a recipe makes, "Melee Range", "Crafting Reagent", the weapon a spell requires, the class an item is for and a reputation a spell requires.
- A spell description the game shows with "until canceled" in place of its duration, for a spell your character does not know, now shows in Japanese.
- A spell that grants an ability ("Gain the Wyvern Strike ability:") shows its heading in Japanese when the game leaves out the ability's own text.
- A spell or item tooltip whose number the game writes against a word ("for1.5 sec") or as a negative range now shows in Japanese.
- An item tooltip the game has reworded since its translation was made no longer shows the old Japanese, which could say something else entirely. It stays English until its translation follows.
- With Japanese names, the group finder's dungeon, raid and zone names, the calendar's holiday titles ("Call to Arms: Warsong Gulch"), a guild member's zone on the roster tooltip, the shapeshift forms, tools and races on tooltips, and the spellbook's spell names show in Japanese.
- Choosing a mount in the mount journal no longer turns its name back to English.
- The floating combat text no longer raises a Lua error when the game hides a number from addons.
- The chat line that says who won a duel, and a lockbox's "Locked" line, are Japanese.
- On a recipe's tooltip, the item it makes shows its flavour text in Japanese, and its equip line no longer carries a wrong not-translated marker.
- Calendar times read 午前 / 午後, and the challenges page's track box and a mount's riding requirement show their tooltips in Japanese.
- The character window's stat tooltips and model buttons, and the guild window's voice chat button, show their tooltips in Japanese.

## 0.14.0 - 2026-11-16

### Added
- The voice panel follows the voice word by word: the page turns as the speaker starts each sentence, and a soft tint marks the words as they are spoken (warm white on the dark looks, brown on parchment). A name of several English words lights up whole.
- Pausing a voiced line and playing it again picks up at the sentence you paused in, not from the start of the line. Two small gold arrows beside pause on the voice panel play the line from the sentence before or the next one, also while it is paused or after it ended. Play again starts from the first sentence, even after a pause.
- When a voice pack is out of date, a chat line at login names it and its version. A line that stays quiet because its voice pack is older than its Japanese names that pack too, and a voice pack too new for your addon says so at login.
- You can choose the voice of your character's own error lines ("out of range") on the Voice settings page: Automatic (your character's race and sex), or any player or NPC voice of the game, grouped by race, for example "Dwarf, female (guard)". The game's English error lines of your own race and sex stay silent whatever you choose.
- Japanese for what Forever 1.60.1.70938 added and for what twenty-three players sent with the English Collector: 124 NPC lines, 128 quest progress and turn-in texts, and new quest titles, objectives and descriptions (with word cards), and 33 item tooltips.
- The study card can say a saved word's sentence in the NPC's recorded voice: it plays when you show the answer (a setting on the Voice page turns that off), and a play button beside the answer plays it again. In the word list, Include audio adds those recordings to the Anki export and lists the sound files to copy into Anki's media folder.

### Changed
- A saved word now keeps its whole sentence, however long. A long sentence used to be cut at about 66 characters, so the study card and the export could miss its start. Words saved before keep the text they were saved with.
- The voice packs now hold each line as one file per sentence, timed to the words. Update all the voice packs once in the CurseForge app (Update All updates them together). Older voice packs still play, without the word marks.
- The voice is clearer: the packs now keep the voices' high end, which makes the download about twice as big (about 2.8 GB). Three new packs split the largest level bands (Levels 1-10 (part 2), Levels 51-60 (part 2) and (part 3)); the CurseForge app installs them with the next Update All, and a chat line at login names any voice pack that did not load.
- The voice panel no longer shows a stage direction, such as an emote in angle brackets, that the voice does not read. A line made only of such directions is still shown.
- A bug report now lists your voice packs with their versions.
- Quest texts and item and spell tooltips the game reworded on 1.60.1.70938 follow the new wording.
- The voice panel no longer goes faint in combat (the "Dim the panel in combat" setting is gone), and a paused line stays on screen, whole, on the sentence you paused in, until you play it or close it.

### Fixed
- Battleground announcements in chat are in Japanese: bases taken and assaulted in Arathi Basin, flag captures in Warsong Gulch, and Alterac Valley's mines and towers. A player named in the line keeps their name as the game wrote it. The "[You died.]" link in chat is Japanese in battlegrounds too.

## 0.13.1 - 2026-11-14

### Changed
- The right-click menus on the target, party and raid frames, and on a player's name or a friend, are in Japanese. Names stay in English.

### Fixed
- Picking from a menu the addon translates, such as Share Quest in the quest tracker's menu or an entry in an Options dropdown, no longer risks the game refusing the action with the addon named. The menus look the same as before.
- Opening some quest windows no longer throws a Lua error (BugSack showed it as `Collector.lua:220 ... a secret string value`). When the game keeps a quest giver's identity hidden from addons, the addon now skips it quietly; the quest text, its Japanese and its voice work as before.
- A Lua error ("Invalid font height") that could repeat each time a window such as the mailbox refreshed, when the game gave a line of text a size of 0 or below. That text now shows its Japanese at the standard size.
- Chat messages are no longer refused ("interface action failed", with the addon named) after you change your chat language from the chat bubble menu. The menu looks the same as before.
- With a controller, the cursor moves between the options in an NPC talk window again. It used to stay on the top option with an "interface action failed" message. In the first talk window after login or a reload, and while you hold the key to see the English, a line can now run into the one below it or leave a gap; talking to the NPC again puts it right.
- The quest log's play button shows the quest giver's head again after a reload, a restart or a game patch. It used to show no head until you met that NPC again. A head that takes a moment to load now appears instead of staying blank.
- An NPC line in chat or a speech bubble that names another player, such as an escort NPC thanking the party member who owns the quest, is now in Japanese with that player's name in it. It used to stay in English.

## 0.13.0 - 2026-11-12

### Added
- Japanese for what Forever 1.60.1.70888 added and for what twenty players sent with the English Collector: about 570 quest titles, 440 quest objectives and 450 quest descriptions (with word cards), 96 NPC lines, 59 quest progress and turn-in texts, 152 item tooltips, new spell tooltips, and objective and area texts. About 170 more progress and turn-in texts of quests the game serves again show in Japanese too.
- The group invite for a player on another shard shows in Japanese, like the cross-realm one.
- English first, for players studying English: set *Game text* to *English first* on the main settings page (or type `/wfj direction en`) and the game stays in its own English everywhere the addon translates. Hold the key and the Japanese shows instead; let go and the English is back. It is the same key and the exact mirror of how the addon worked before, which is still the default. The Japanese voice is heard only while the key is held.
- English word cards: in English first, point at an English word in quest text, NPC talk, a book or letter page or a window label to see how it is said, the Japanese word the translation uses for it in that line with its reading, and that word's dictionary form. About nine in ten words that can have a card do. Names, *a*, *the*, and bare words such as *is*, *have*, *of* and *to* have none, and neither do pages the game lays out with pictures or headings.
- Save and study English words: in English first the save click keeps the English word with how it is said, its Japanese word, the English sentence and the Japanese sentence. The study card then shows the English word and sentence first, and the Japanese on the back. The exported list holds them too.
- A welcome window that asks what you are here for: Study Japanese, Study English or Just play. Pick one and press Confirm, and it sets the game text, the word cards and the study tab to match; then it shows what to know to get started. Everyone sees it once, players who already have the addon too, and nothing changes until you press Confirm. Open it again any time from the top of the settings page, the About page or with `/wfj intro`.

### Changed
- Quest texts, item and spell tooltips the game reworded on 1.60.1.70888 follow the new wording. 43 hand-written lines were corrected against the new English, most of them item effects the game changed, and six hand-written quest descriptions that were cut off after their first paragraph are now whole.
- A quest line is read in the voice of the NPC the Spoken addon uses for it, so with both addons you hear the same character in Japanese and in English. About 100 quest lines the narrator used to read are now read by their NPC.
- The voice says a name that owns something the way it sounds: Light's Hope is ライツ・ホープ and Marduk's is マルドゥクス, where every such name used to end in ズ. The lines that say those names have been made again.
- The settings pages have more room: each page scrolls when it needs to, sections are spaced apart, and the explanations are shorter. Every page but About has a Defaults button (click it, then click again within five seconds) that resets that page's settings only. The version, memory and data counts moved to the About page.
- The voice settings and the voice panel's settings are on one page, *Voice*. There is no separate *Voice panel* page any more.
- The key setting is now called *Hold to show the other language*, since it shows English or Japanese depending on *Game text*.
- The English Collector page tells you how to send in one line; the send window shows the steps.
- Quest titles now stay in the game's English everywhere: the quest list, the tracker, the quest log, the quest window, the quest rows in an NPC's talk window, Dialogue UI's windows, tooltips and system messages. A title is a name, like a person's or a place's: it is what you search a guide for, link in chat and say to a party member. The quest's text, objectives and descriptions are Japanese as before.
- The voice now says every English name in Japanese sounds that match what you read on screen: Black Dragonflight is spoken ブラック・ドラゴンフライト, not translated, and Tiger is タイガー. Names on screen stay English, as before.
- Every voice line has been made again. Each NPC voice now sounds steadier from one line to the next, and words the voice often said wrong come out right: 冒険者, a few single-kanji words such as 金 (かね) and 獣 (けもの), and words that came right after a space.
- A new icon: the 字 is now a bold brush-style character in gold on a brighter red disc. The minimap button shows the red disc and the 字 without a second gold rim, and sits centred in its ring.

### Fixed
- With Dialogue UI, an item's Japanese effect line in its tooltip (Use, Equip, Chance on hit, the flavour quote) no longer shows as a row of empty boxes.
- The character's spoken error lines (out of range, not enough mana) now follow the game's own Error Speech setting. With it on you hear the Japanese line, with it off you hear nothing. The addon no longer switches that setting off itself; if an earlier version had switched yours off, it is switched back on once.
- With Ellesmere UI, the game's windows it restyles no longer have to show empty boxes where the Japanese should be: choose **WoW Forever Japanese** as the Global Font in Ellesmere UI's font settings (`/eui`, Fonts). English text in those windows is then drawn in the same font. Ellesmere UI's own windows stay English, and its chat window is not supported: turn its Chat module off in the addon list for Japanese chat.
- With Dialogue UI, a quest's tag over its title (Dungeon, Raid) no longer shows empty boxes: it keeps the addon's font when the page is gone over again, and if its Japanese ever loses that font, the font goes back on the next moment.
- The Legacy trees' talent tooltips show their Japanese lines (Click to learn, Requires all preceding talents, Spend 10 more points in the Professions Legacy Tree) even when the talent window has not been opened yet. The trees' names stay English.
- Sharing a quest from the quest tracker's right-click menu, and the world map's quest markers in combat, no longer give an "action blocked" message naming this addon. The quest log, the quest popup and the quest window had their scroll area re-measured by the addon after their text turned Japanese, and that carried the addon's taint into the quest map and the tracker. The game keeps that scroll area right on its own. Sharing a quest in combat is still something the game itself does not allow.
- Word cards now cover words that were missing on about 60 quest, NPC and book lines, so pointing at any word in those lines shows its reading.
- The word card for 大将軍 (warlord) now gives its reading as たいしょうぐん in the three quests that use it.
- Clicking a challenge on the Legacy board, or an achievement in the Achievement window, no longer turns its title and description English. They stay Japanese when the entry opens or closes, and when its progress updates.

## 0.12.0 - 2026-11-08

### Added
- Read NPC greetings aloud only the first time: a vendor or trainer greets you the same way at every visit, so a greeting you have heard stays quiet when its window opens. This is on by default (*NPC greetings: only the first time* on the Voice page). *Quest lines: only the first time* does the same for quest offers, progress and turn-ins, and is off by default. The window's play button still reads the line, and a line whose Japanese changed counts as new.
- Japanese for what Forever 1.60.1.70862 added: about 240 quests (titles, offers and objectives, with word cards), 287 item tooltips, new spell tooltips, 24 NPC lines, objective and area names.
- More NPC lines and quest texts in Japanese, with word cards, from players' English Collector sends: eighteen NPC lines from the Durotar Supply and Logistics quartermaster in Orgrimmar, Cairne Bloodhoof welcoming the Windshapers to Mulgore, the transmogrifier, three Orgrimmar shopkeepers and a trainer, and nine quest progress and turn-in texts (two library book turn-ins, two Orgrimmar herb quests and a camping quest); then about 75 more NPC lines, many on Zephras Isle and in the High Order's story, and 16 more quest progress and turn-in texts; then 45 more NPC lines and 9 more quest progress and turn-in texts from seven more sends. Two item tooltips have Japanese too.

### Changed
- When a window's line will be read aloud, the game's English voice is now silenced as the window opens, not when the Japanese starts. It comes back as soon as the line turns out not to play, or after a second and a half. An NPC that speaks the moment it turns to you can still be heard for a split second: the game starts that greeting before it opens the window.
- Item and spell tooltips and quest texts the game reworded on 1.60.1.70862 follow the new wording.
- Twelve quest progress and turn-in texts follow the game's current wording in Japanese and no longer show the stale marker.
- The profession window's recipe description and its Filter button are in Japanese. Profession, recipe and item names stay English.
- With Dialogue UI installed, an item's Use: and Equip: lines in its item tooltip, a quest tag that appears a moment after the page, and its quest-complete flyout are in Japanese.

### Removed
- The setting *The book button opens the quest in the quest log*. The voice panel's book button now always opens the small window with the line's whole Japanese.

### Fixed
- Opening the world map in combat is no longer blocked with this addon blamed. The quest list beside the map shows the game's English while you are in combat and its Japanese again when the fight ends, and the voice panel's book button no longer opens the quest log.
- No more "bad argument #2 to 'SetFont' ... Secret values" Lua errors in a busy trade channel: a line whose font size the game keeps secret now stays in English.
- The AddOns list's tooltip shows the Japanese in this addon's name and the voice pack's name instead of empty boxes.
- A talent's tooltip shows its next rank in Japanese too, and holding the English key no longer turns the current rank's text into empty boxes.
- An item with several Equip lines in a row keeps each line's own number: Gnarled Necromancer's Staff showed its movement speed as 26% (its spell damage) and lost the spell damage line.
- Right-clicking a quest in the quest log shows Track Quest, Share Quest and Abandon Quest in Japanese too (only Focus was before).
- Skyborne characters now see the Japanese of lines that name their race (they showed English before), and the race shows as "Skyborne".
- About 75 voice lines that ran on into nonsense partway through (the Deviate Eradication quest's offer among them) are made again.

## 0.11.0 - 2026-11-08

### Fixed
- Hovering items no longer stalls the game, most of all with comparison tooltips open: an item's tooltip took up to a tenth of a second each time it refreshed. Many windows' text is matched faster for the same reason.
- Menus that redraw when you click in them (the auction house filter menu, for one) keep their Japanese readable. Before, a checkbox click could turn a heading into empty boxes.
- No more "attempt to compare a secret value" Lua warnings from the addon's chat and tooltip text, which could repeat hundreds of times in a session.
- Clicking a search box (the auction house, your bags, the quest log, the spellbook and the other windows with one) works while its placeholder shows in Japanese. Before, the word card's hover area over the placeholder caught the click, and you had to hold the English key to click into the box.

### Added
- The addon's problem log now records how long its own work takes in each window and which of its parts ran just before the game blocked an action, and checks the bag windows for anything it touched by mistake. `/wfj perf` shows the slowest parts. Nothing changes on screen; this is so lag and blocked-action reports can be traced to their cause.

## 0.10.1 - 2026-11-07

### Changed
- Every voice line is new: NPCs speak in Japanese voices modelled on their own voices in the game (each NPC has the voice the game gives it, so a male NPC is never heard in a woman's voice), the narrator and book pages in one storyteller voice, and your character's error lines in voices modelled on your race's own. All lines play at one loudness.

## 0.10.0 - 2026-11-06

### Added
- Works with Dialogue UI: when you have it installed, its quest, NPC talk and book windows show the Japanese, with the same key for the English, markers, word cards and voice. Quest titles, NPC talk options and the objective lines on its progress page are Japanese too. Its buttons, headings and item tooltips use the game's Japanese words (a few words of its own stay English), and Dialogue UI is not needed.

## 0.9.0 - 2026-11-06

### Added
- Japanese for about twenty more NPC lines, four on Zephras Isle and sixteen in the Forsaken and Tauren starting lands, with word cards, and voice where the speaker is known, from two players' English Collector sends. Two quest progress texts that had no Japanese now have it.
- Study your saved words in game: a small tab at the right edge of the screen says how many words are due, and clicking it shows one card at a time, the word in the sentence it came from, then its reading and meaning; Again or Good decides when it comes back, on the same FSRS schedule Anki uses, with a short sound for each step and a green or red blink for the grade (a speaker button on the card mutes the sounds). The card collapses to the tab, moves anywhere, hides in combat, and comes back from `/wfj study`, the minimap button's menu, a key binding or the Words settings page, where you also set how many new words to start per day. Studying in the game and in Anki keep separate schedules.

### Changed
- Six quest progress and turn-in texts follow the game's current wording in Japanese and no longer show the stale marker.

### Fixed
- The English Collector recognises the player's name when the game prints it in capitals, so such a line matches its translation on every player's screen instead of being recorded with the name.
- The auction house no longer throws a Lua error when you open it or switch to a list you have not opened yet, and its Japanese labels, column headers and rows now show on every tab, including a list's first opening.

## 0.8.0 - 2026-11-05

### Added
- Save words to a word list: while the popup dictionary shows a word, Ctrl+click it to keep it with its reading, meaning and the sentence it came from. The list stays from one session to the next and is shared by your characters. `/wfj words`, the new Words settings page or the minimap button's menu shows the list as text to copy into a text file, a spreadsheet or Anki, with the word and its sentence also written with furigana for Anki cards. The click can be changed, and each save can also take a screenshot. Copy your words out before going back to an older version: it does not keep the list.
- Japanese for the quests, NPC lines and spells Forever build 1.60.1.70790 adds on Zephras Isle and elsewhere, with word readings and voice: the Camping 101 quests, The Ancient Hilt, the shen'dorei starting area's conversations, and the new spells and their auras.
- Japanese for about 190 more NPC lines on Zephras Isle (the Windshapers, the High Order and the shen'dorei start), with word cards, and voice where the speaker is known.

### Changed
- Quest text is read from Forever build 1.60.1.70790, the launch build.
- The unit right-click menus (on a portrait, a party or raid frame, a name in chat) and the Edit Mode window stay in English: Japanese there made the game block actions in combat.
- Seven Darkmoon Faire quest titles show their item name in English (Carnival Boots, Coarse Weightstone, Copper Modulator and others), as names do everywhere.
- The quest log's list keeps its rows at the game's own height; Japanese text that wraps differently is no longer resized.
- Thirteen quest turn-in and progress texts on Zephras Isle follow the game's own wording in Japanese.

### Fixed
- Right-clicking a party member in combat no longer fails to open the menu ("Interface action failed because of an AddOn").
- Leaving Edit Mode no longer shows an "AddOn action forbidden" error.
- Clicking a tracked quest's title in combat opens the quest log and map instead of being blocked.

## 0.7.1 - 2026-11-04

### Changed
- The game text is read from Forever build 1.60.1.70790 (quest text from 1.60.1.70532 until the new build's quests are read).
- The Mage's Improved Frostbolt, Winter's Chill and Arctic Reach, the Druid's Ferocious Bite and the Rogue's Poised follow their new text in Japanese.

## 0.7.0 - 2026-11-03

### Added
- Japanese for the text Forever build 1.60.1.70755 adds: the Violet Flames campfire spells and the Pouch of Violet Dust from the launch celebration, Camping, Emerald Stasis, Poised and Shank, and the new spell auras.

### Changed
- The game text is read from Forever build 1.60.1.70755 (quest text from 1.60.1.70532 until the new build's quests are read).
- The renamed and reworded talents and abilities follow their new text in Japanese: the Rogue's Efficient Strikes, Coup de Grace, Quick Getaway, Sap, Ghostly Strike and Death Mark, the Shaman's Lightning Mastery, Totemic Call and Riptide, the Warrior's Improved Whirlwind and Slam, the Mage's Missile Barrage, and the other lines the build reworded.
- The Edit Mode labels for buffs on top or on the right, the spell damage and spell healing tooltips on the character sheet, and the subscription window's second bullet follow their new text.

## 0.6.0 - 2026-11-01

### Added
- Japanese for the text Forever build 1.60.1.70707 adds or rewords: 31 new spells and 39 new items (the Paladin's Holy Shield, Turn Evil, Oath of Light and Seal echoes, the Druid's Lacerate, Ferocious Bite and Bloom, the new recipe scrolls), and the reworded Seals, Vigils, Leyline and Skysight lines and the Season of Discovery runes.
- Japanese for the text Forever build 1.60.1.70685 adds or rewords, with word readings: the Options window's new Classic / Enhanced preset page, the PvP match results' outcome line and honor column, and the reworded talents and spells.

### Changed
- The game text is read from Forever build 1.60.1.70707 (quest text from 1.60.1.70532 until the new build's quests are read).
- The Revenge tooltip follows its new wording, a damage range, in Japanese; the dual-spec tab's locked hint says to unlock at the class trainer.
- The spellbook's search box hint follows its new text.

### Fixed
- The English Collector's "where is my file" path names the Forever client's folder, `_forever_`.
- The community invite window's line under the text (which name to enter) shows in Japanese in each of its forms.

## 0.5.0 - 2026-10-23

### Added
- Japanese for the text Forever build 1.60.1.70532 adds or rewords, with word readings: the quests Forever now serves that no earlier build answered (the Hallow's End candy quests and the Sparklematic 5200 and Winter Veil quests are read aloud in Japanese; the Darkspear Islands quests so far have only their titles), and new and reworded items and spells.

### Changed
- The game text is read from Forever build 1.60.1.70532.

## 0.4.1 - 2026-10-20

### Fixed
- Making a new HUD layout in Edit Mode no longer raises a "stack overflow" Lua error.
- Opening a holiday or a raid lockout in the Calendar no longer raises a Lua error, and its description is in Japanese. The holiday's own text and the times stay as written.
- Clicking a Calendar event, holiday or raid lockout again while its window is open keeps it in Japanese; it used to turn back to English.
- Typing in the AddOn List's search box keeps its Okay button in Japanese.

## 0.4.0 - 2026-10-17

### Added
- The new player tutorial a new character sees on Forever is in Japanese: the keyboard and mouse window, the walk and camera prompts, the screen prompts and the pointer arrows. Keys, spell names and icons in them stay as the game shows them.
- Japanese for the text Forever build 1.60.1.70425 adds or rewords, with word readings: new and reworded quests (read aloud in Japanese), items and spells, the pet's combat stats, the stable's title and loyalty line, the rebuilt Combat text options, new statistics and scoreboard columns, dialog and chat lines, and the notice shown when your privacy settings turn friends off.
- The opening cinematic of every race shows its subtitles in Japanese: human, dwarf, gnome, night elf, orc, troll, tauren, undead and Skyborne.
- Japanese for the text Forever build 1.60.1.70450 adds, with word readings: the Winter Veil quests Forever brings back, a new Stranglethorn Vale quest (read aloud in Japanese), an item and new spells.
- Three camp lines a player sent with the English Collector are in Japanese, with word readings.

### Changed
- The game text is read from Forever build 1.60.1.70450.

### Fixed
- The scoreboard's rank tooltip ("Rank 7 - Knight-Lieutenant") is in Japanese; the rank title stays English.

### Removed
- The instance difficulty banner's tooltip: the game no longer shows that banner.

## 0.3.0 - 2026-10-13

### Added
- A first install shows a short welcome window at the first login, in Japanese and English: hold Alt to see the game's English, point at a word to see its reading, what the minimap button does, and, while the voice is not installed, where to get the free Japanese voice. It shows once, and never to players who update.
- Japanese for 200 more interface lines, with word readings: system chat lines that carry a link (a friend coming online, loot rolls, the level-up line) show Japanese around the link, which stays as the game wrote it; the "Made by" line on crafted items, cooldown and enchant time lines, the account bank, the quest log's story header, help callouts, cross-faction invite words and more.
- Forever's own item stat lines are in Japanese ("Equip: Improves your chance to hit by 1%.", spell damage and healing, weapon skills, attack power against a creature type).
- Item set bonus lines ("(2) Set: …", and "Set: …" once the bonus is active) are in Japanese.
- More spell and item tooltips are in Japanese: boss and raid debuffs whose text comes from another spell, the weapon skill tables (short and expanded), the Riding skills and the class ability lists (a Shaman's totems, a Paladin's or Hunter's abilities; the names in the list stay English), and talents with two wordings for the same numbers. The coverage page gives a plain reason for each tooltip line that stays English.

### Fixed
- Pointing at a quest's title in the quest log shows its tooltip in Japanese: the title, the objective summary, the objective lines and the click hint. On the beta, its bug-report line turned them back to English.
- The English Collector counts only lines the addon cannot show in Japanese: tooltips with your numbers filled in, quest lines that name your class or race, and NPC names no longer count, and lines a newer version covers are removed from the collector file at the next login or reload.
- Recipe tooltips show the crafted item's text and the recipe's "Use: Teaches you how to …" line in Japanese.
- An item's cooldown at the end of its line ("(1 Sec Cooldown)") no longer keeps a food's or potion's text in English.

## 0.2.0 - 2026-10-11

### Added
- Japanese for the quests Forever build 1.60.1.70338 opens (Jarl Needs a Blade, A Quick Craft, and the text of Rotgath Stonebeard: objectives and descriptions, with word readings), read aloud in Japanese.
- The Medal of Courage tooltip is in Japanese (lower hit chance of Fear effects against you).

### Changed
- The game text is read from Forever build 1.60.1.70338.
- Voice lines of quests a new build does not answer stay in their level's voice pack.

## 0.1.0 - 2026-10-10

### Added
- Japanese voice over: install "WoW Forever Japanese Voice" on CurseForge (after the addon) and quest offers, progress and turn-ins, NPC greetings and talk, and book and letter pages are read aloud in Japanese while the window shows the Japanese. Every NPC has a voice that fits who they are (race, gender, age, kind of being) and keeps it, and your character's own spoken error lines ("out of range") play in Japanese too, in a voice for your race and sex. With the voice panel on (the default), the voice goes on while you hold Alt or after you close the window. With the panel's size set to Off, holding Alt or closing the window stops the line, and a small button on the window stops it or plays it again. While a line plays, the game's English NPC voice is turned off and then put back. Without the voice nothing changes and no voice settings show; the Voice settings page turns it off, or one kind of line at a time.
- The voice panel: while a line is read aloud, a panel at the bottom of the screen shows the NPC's moving head, their name and title, and the line in Japanese one sentence at a time as the voice reads it, with word cards when you point at a word. A line that starts while another plays waits its turn, and an "Up next" list above the panel lets you click one to hear it now. Buttons on the panel pause and resume, play the line again, show the whole text (the quest in your quest log, or a small window with the whole line) and close it; two new key bindings pause and replay. The line keeps playing after you close the window, and holding Alt shows the line's English on the panel while the Japanese voice goes on. The quest log's quest details get a play button that reads the quest through the panel with the NPC who gave it, as long as the addon saw that NPC hand it out. The panel fades after the last line, dims in combat, can be dragged and locked (locked, clicks pass through it to the world; `/wfj panel reset` puts it back). Its own words are in Japanese, in English while you hold Alt. A new **Voice panel** settings page holds Panel size (Off, Full, Compact strip) and Panel style (Dark, Parchment) and the panel's other switches.
- The minimap button's tooltip shows the addon's version and, while the English Collector holds lines you have not sent yet, how many ("The collector has N lines we need. Right-click to send them.").
- The About & Help page says whether the Japanese voice is installed. Without it, it shows the address of "WoW Forever Japanese Voice" on CurseForge, ready to copy; with it, it names the voice packs that loaded. Its two report buttons now sit side by side.
- Japanese for the quests Forever build 1.60.1.70245 opens (their titles, objectives and descriptions, with word readings), the quest text it reworded, and its new item tooltips. Six item tooltips whose old Japanese had the wrong stat or a fixed number (for example a shield block chance written as parry) are newly translated.
- Japanese for the text Forever build 1.60.1.70291 added or reworded: its quests, item and spell tooltips and interface text, with word readings, including the beta's Legacy achievement and the subtitles of the gnome race introduction, and the lines the English Collector sent in. The quests whose wording changed are read aloud again in the new Japanese.
- The PvP scoreboard's stat names that come from a table of their own on this build, such as Alterac Valley's towers and graveyards, are in Japanese.
- New interface text is translated: the voice chat (Discord) settings, the voice chat join popup, the group finder's voice chat choice and its line in a listing's tooltip, the chat line when the group's voice service changes, Edit Mode's gamepad action bar and the gamepad's Collapse and Expand prompts.
- When the English Collector holds 10 or more lines you have not sent yet, a small window opens at login or reload with how many are waiting, a **Send English** button that opens the send window, and **Later**. It shows at most once a day and gives only the count. Its **Don't remind me again** box, the new setting on the English Collector page, or `/wfj collector remind off` turns it off; the collector keeps recording. The minimap button's menu also gets **Send collected English** with the count while any line is waiting.

### Fixed
- Quests that Forever served on an earlier build but did not answer on 1.60.1.70291 keep the English Forever showed (and their Japanese), instead of falling back to Classic Era's wording.
- The Inspect window is in Japanese again on build 1.60.1.70291 (it had stayed all English after the build removed its talents button), and its new PvP pane (season, rank, honorable kills) and side tab tooltips are translated. Rank titles stay English.
- The pet level line on the character pane, with the pet's loyalty rank, and the quest tracker titles of elite, dungeon, PvP and raid quests (the tag after the title) show Japanese again.
- An item tooltip's red note "Cannot change equip status while in combat" was shown as a jumbled half-Japanese line (combatのCannot change equip status while). A wardrobe pattern ("<boss> in <instance>") had taken it. That pattern and the death recap's "<spell> by <caster>" now apply only where a window asks for them: the death recap keeps its line, and the wardrobe's source line, two names around "in", stays English. Lines the addon has no Japanese for stay in English.
- The group invite popup is now fully in Japanese: "<name> invites you to a group." (and the note that accepting takes you out of your queues) and its **Decline** button, which had stayed English after its half-second lock. A cross-realm invite's line is translated as well. The inviter's name stays English. Other popups whose whole line comes from the game as one known sentence (the question when you leave an instance group, and the trainer's "unlearn all of your talents?" and the pet-skills one) are translated too.
- The "World refresh in 29 Seconds" notice above the chat (and its longer first wording) is now in Japanese, with the time unit in Japanese too (ワールド更新まで29秒). It had stayed English.
- Nine lines Forever's NPCs say or yell that the addon had no Japanese for (heard by the English collector, for example "Go with the blessings of Al'Akir…" and "For the High Order!") are now translated, with word readings. So are six lines from the Goldshire campfire and mining scenes (for example "Go on and have a seat near the fire and we can get started.").

### Changed
- The game text is read from Forever build 1.60.1.70291.
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
