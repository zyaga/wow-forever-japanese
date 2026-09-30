# WoW Forever Japanese: Overview

**What it is:** A World of Warcraft: Forever addon that shows quest text, NPC dialogue, books, letters and plaques, item and spell tooltips and the game's interface in Japanese, with the original English one key-hold away (Alt by default). Pointing at a Japanese word shows its reading and a short meaning. The Python pipeline that builds its translation data ships in the same repository. The hand-written translations reached it through earlier addons for WoW Classic, credited in [`ATTRIBUTION.md`](../ATTRIBUTION.md).
**Status:** Quest text, NPC dialogue, book pages and the interface ship in Japanese almost in full; item and spell tooltips are mostly done, and the rest waits for the Forever client's own English ([Coverage](operations/coverage.md) has the current numbers). The addon targets the Forever client only. The Forever beta opened on 2026-09-17 and the game launches on 2026-11-04.
**Stack:** Lua (WoW addon, Blizzard API only, no dependencies) · Python 3 pipeline · ID-keyed JSON data with provenance on every line · human translations from the Japanizer projects, plus machine-drafted text with recorded provenance.
**License:** GPL-2.0-or-later; the font IPA UI Gothic under the IPA Font License.

## Doc map
- [Principles](architecture/principles.md): the rules every change keeps (start here)
- [App capabilities](app-capabilities.md): feature inventory
- [Glossary](glossary.md): the project's vocabulary
- [Roadmap](roadmap.md): what is done and what is next
- [Decisions](adr/): why things are the way they are
- [Architecture](architecture/) · [Systems](systems/): how it works ([Readings](systems/readings.md): the word card; [Fix reports](systems/fix-reports.md): reporting a line from the game)
- [Content](content/translation-style-guide.md): the translation style guide
- [Research](research/): client surveys and mechanisms behind the decisions
- [Testing](testing/strategy.md)
- [Operations](operations/): [local setup](operations/local-setup.md), [translation batches](operations/translation-batches.md), [release](operations/release.md), [taking a fix report](operations/fix-reports.md), [coverage](operations/coverage.md)
- [Lessons](lessons/)
- [Legal](legal/licensing.md): licensing (GPL-2.0-or-later, corpus provenance, font, game text)
- [CurseForge description](curseforge.md): the listing text
