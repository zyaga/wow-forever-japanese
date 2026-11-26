# WoW Forever Japanese: Overview

**What it is:** A World of Warcraft: Forever addon that shows quest text, NPC dialogue, books, letters and plaques, item and spell tooltips and the game's interface in Japanese, with the original English one key-hold away (Alt by default). Pointing at a Japanese word shows its reading and a short meaning, and a click saves it to a word list the player can study in game or export to Anki. A small Anki add-on, built in the same repository, turns the saved words into Anki cards by itself, with the screenshot and the sentence's audio. Each word carries a status the player sets (Unknown, Learning, Known, Ignored): words not known yet are underlined where the player reads, the most useful ones to learn next are highlighted, and a tag shows how much of a text the player knows. A key freezes a tooltip in place, so its Japanese words can be pointed at too. In chat, a word under the mouse shows its card as well, a small icon opens a line to copy, and a phrase book types short phrases that every player can read and players with the addon read in their own language. One setting turns it around for a Japanese player studying English: the game stays in English, the Japanese is one key-hold away, and pointing at an English word shows how it is said and its Japanese word. A welcome window asks each player once which of the two they want, or neither. The Python pipeline that builds its translation data ships in the same repository. The hand-written translations reached it through earlier addons for WoW Classic, credited in [`ATTRIBUTION.md`](../ATTRIBUTION.md).
**Status:** Quest text, NPC dialogue, book pages and the interface ship in Japanese almost in full; item and spell tooltips are mostly done, and the rest waits for the Forever client's own English ([Coverage](operations/coverage.md) has the current numbers). Japanese voice over is built for the whole game (quests, NPC talk, book and letter pages, the character's error lines) as separate voice addons, not published yet ([Voice over](systems/voice.md)). The addon targets the Forever client only. The Forever beta ran from 2026-09-17; the game launches on 2026-11-04.
**Stack:** Lua (WoW addon, Blizzard API only, no dependencies) · Python 3 pipeline · ID-keyed JSON data with provenance on every line · human translations from the Japanizer projects, plus machine-drafted text with recorded provenance.
**License:** GPL-2.0-or-later; the font IPA UI Gothic under the IPA Font License.

## Doc map
- [Principles](architecture/principles.md): the rules every change keeps (start here)
- [Client limits](architecture/client-limits.md): what the Forever client keeps from addons (buff tooltips in combat, cooldown numbers, sealed chat lines) and what the addon does there
- [App capabilities](app-capabilities.md): feature inventory
- [Glossary](glossary.md): the project's vocabulary
- [Roadmap](roadmap.md): what is done and what is next
- [Decisions](adr/): why things are the way they are
- [Architecture](architecture/) · [Systems](systems/): how it works ([Settings](systems/settings.md): the direction, the settings pages and the welcome window with its tour of the features; [Readings](systems/readings.md): the word card and the English word card; [Word list](systems/word-list.md): saving words and exporting them; [Anki add-on](systems/anki-add-on.md): the saved words as Anki cards, made by an add-on in Anki; [Study](systems/study.md): studying the saved words in game; [Word status](systems/word-status.md): what the player knows of each word, the marks, the comprehension score and the known words window; [Chat tools](systems/chat-tools.md): word cards on chat, copying a line, the phrase book and the player's own chat words; [Fix reports](systems/fix-reports.md): reporting a line from the game; [Diagnostics](systems/diagnostics.md): the addon's problem log; [Voice over](systems/voice.md): Japanese audio from a separate pack)
- [Content](content/translation-style-guide.md): the translation style guide
- [Research](research/): client surveys and mechanisms behind the decisions
- [Testing](testing/strategy.md)
- [Operations](operations/): [local setup](operations/local-setup.md), [translation batches](operations/translation-batches.md), [release](operations/release.md), [taking a fix report](operations/fix-reports.md), [coverage](operations/coverage.md), [voice over](operations/voice.md)
- [Release media](releases/README.md): the pictures and clip each release's Discord post carries, one folder per version
- [Lessons](lessons/)
- [Legal](legal/licensing.md): licensing (GPL-2.0-or-later, corpus provenance, font, game text)
- [CurseForge description](curseforge.md): the listing text
- [AnkiWeb listing](ankiweb.md): the Anki add-on's page on AnkiWeb
