# Licensing

What this repository is licensed under, where its text came from, and what is not ours. This is a documented
judgment, not legal advice.

This addon is made by fans. It is not affiliated with or endorsed by Blizzard Entertainment. Game text and
screenshots: ©2004 Blizzard Entertainment, Inc. All rights reserved. World of Warcraft, Warcraft and Blizzard
Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc. in the U.S. and/or other
countries.

## Project license: GPL-2.0-or-later

Everything written for this project (the addon's Lua, the Python pipeline, tests, CI, and the generated data) is
**GPL-2.0-or-later**. The earlier Classic addons and the Chinese intermediates the Japanese passed through were
GPLv2, so one GPL-compatible license for the whole repository is the simple choice. `LICENSE` is the verbatim GNU
GPL v2 text; the "or later" grant is the declaration in `pipeline/pyproject.toml`, the TOC
(`## X-License: GPL-2.0-or-later`) and `README.md`.

Contributions come in under the same license (inbound = outbound). There is no CLA.

The bundled font is the one exception (below).

## English game text

All English text in `data/english/` (139,877 lines) is Blizzard Entertainment's, whichever copy it was read
from. It is kept to align translations with their source and to hash it; the addon never ships it (the player
always sees the live English the client writes; see [principles](../architecture/principles.md#4-the-addon-never-ships-stored-english)).
Publishing it in the repository follows the long-standing practice of open WoW data projects such as pfQuest,
Questie and VMaNGOS. The licenses of the copies below set only the credit owed for the copy, not the text's
ownership.

| Source | Lines | What | License of the copy |
|---|---:|---|---|
| Forever client tables (the installed client's local archive and hotfix cache, read with `make tables-extract`) | 104,981 | item, spell and UI text | Blizzard game data |
| Forever quest cache (`questcache.wdb`, read-only) | 6,883 | quest titles, objectives and descriptions, objective lines, area text | Blizzard game data |
| Classic Era quest cache (`questcache.wdb`, read-only) | 6,535 | the same, for quests Forever lists but has not answered yet | Blizzard game data |
| VMaNGOS world database | 18,221 | gossip, book pages, quest progress and completion (server-sent text that is in no client file) | GPL-2.0 |
| wago.tools DB2 exports | 2,015 | item and spell text | Blizzard game data |
| pfQuest | 357 | quest text | MIT |
| forever-vo player captures ([ADR-055](../adr/055-forever-vo-captures-as-an-english-source.md)) | 855 | quest progress and turn-in text, and NPC greetings, that no other source has, recorded by Forever players with forever-vo's addon | MIT |
| The addon's own collector | 30 | text the maintainer's client recorded in game | Blizzard game data |

Sources whose terms forbid it are never used; nothing is scraped from Wowhead or similar sites. The Forever beta
carries no confidentiality terms: Blizzard's license makes a beta test confidential only when Blizzard announces it
as such, and this one was announced open to press and fan sites.

## How the English was read

The English text was read from a licensed, installed copy of the game: its data tables and its quest cache. The
repository holds text lines only, plus four small test files cut from the client (`tests/fixtures/db2`,
`tests/fixtures/wdb`, `tests/fixtures/wdb-forever`). No game program, art, sound or archive is redistributed, and
the addon itself ships no English game text.

## Japanese translations

The human translations were written for **WoWJapanizer**, **QuestJapanizer** and **CraftJapanizer_Quest**. All
three are published on CurseForge under the BSD License (the three-clause template); their notice is reproduced in
[`ATTRIBUTION.md`](../../ATTRIBUTION.md) as the license requires. The text reached this project through the
predecessor addons and their Chinese intermediates (**Classic Quest Chinese Translator** and **Tooltips
Translator - Chinese**, GPLv2), and through QuestJapanizer's own release. This repository holds no code from any
of those addons; only the Japanese text passed through them, under the BSD notice. The label `questjapanizer-wiki`
marks lines the QuestJapanizer and CraftJapanizer_Quest releases carried with no translator's tag of their own;
they come from those same releases. The QuestJapanizer wiki site itself was never fetched.

Every line in `data/` records who wrote it (`provenance.translator`), so credit follows each line. Translators
are credited by the tags they used, with no suggestion that they endorse this project. `ATTRIBUTION.md` lists
every tag in `data/`, shipped or not (`python -m wfj.dev.gen_attribution` writes the list, and a test fails when
a tag is missing).

Machine-drafted lines are marked `machine` in their provenance, with the model that drafted them.

Players whose corrections ship through a fix report are credited by the name they chose in `ATTRIBUTION.md`; the
report form says so before they send it.

## Font: IPA UI Gothic

`addon/WoWForeverJapanese/Fonts/ipagui.ttf` is **IPA UI Gothic**, redistributed **unmodified under the IPA Font
License Agreement v1.0**. The license requires its text to travel with the font and the original file name to be
kept, which is why the file is `ipagui.ttf`. The official Japanese text is
`Fonts/IPA_Font_License_Agreement_v1.0.txt`; `Fonts/README.txt` points to the English translation at
<https://moji.or.jp/ipafont/license/>. The font is the one part of the shipped folder outside GPL-2.0-or-later.
Subsetting it would make a "derived program" under the IPA terms and would need its own decision.

## References

These projects were read to understand the client's files. None of their code or data is in the repository,
apart from the facts named here.

| Project | What it was read for | Its license |
|---|---|---|
| [WoWDBDefs](https://github.com/wowdev/WoWDBDefs) | the declared types of the columns of three client tables (`ItemSubClass`, `QuestV2`, `ItemEffect`), copied by hand into `pipeline/wfj/io/client_tables.py` and `io/dbcache.py` | definitions CC BY-SA 4.0, code BSD-3-Clause |
| [wowdev.wiki](https://wowdev.wiki) | the descriptions of the archive and table formats the readers under `pipeline/wfj/io/` follow | see the site |
| [wow-listfile](https://github.com/wowdev/wow-listfile) | the file ids of interface files, to find them in an installed client | none stated |
| [wow-ui-source](https://github.com/Gethe/wow-ui-source) | a public mirror of the client's interface code, read for the citations in the docs and comments | the code is Blizzard Entertainment's |

## Related

[Overview](../overview.md) · [Principles](../architecture/principles.md) · [Pipeline](../systems/pipeline.md) ·
[`ATTRIBUTION.md`](../../ATTRIBUTION.md) · [`LICENSE`](../../LICENSE)
