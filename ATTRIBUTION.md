# Attribution

## Translators (69 tags, as recorded in the corpus)

- Abau
- Abau　改訂:Tammy
- alkhali
- Az
- buco
- Cherry
- CraftJapanizer
- Dazz
- Domonis
- Domonis, kei_koyama
- Forsaken
- fuuie
- Ganimede
- Gukkenn
- Gunzee
- hobgob
- Inomata
- K.A.B.U.
- Katty
- Katty 改訂:Tammy
- Kaz
- Kaz, Tammy
- kei_koyama
- lalha
- LoLcoil
- Mimipyon
- mizop
- mogax
- Nagurumon
- Narks
- Nenbutun
- Ohiya
- Ohiya 改訂:Tammy
- Ohiya　改訂:Tammy
- ouki
- ouki　改訂: Tammy
- ouki　改訂:Tammy
- Pendülum
- Pepper Pot
- petenshi
- petenshi 改訂:Tammy
- petenshi, Tammy
- petenshi,Tammy
- pita
- questjapanizer-wiki
- Raizin@Ysondre
- Roririn
- Roririn   Roririn
- ruwind  ruwind
- Ryoosuke
- Ryox
- Ryox　改訂:Tammy
- Sillabub
- Tammy
- Teel
- Towayve
- Towayve  改訂:Art
- Towayve 改訂:Tammy
- Towayve 追補訳:Tammy
- Towayve, Tammy
- Towayve　改訂:Tammy
- Towayve　改訂翻訳:Tammy
- Tsuki
- Tsukinowa
- WoWJapanizer
- Yumiko
- Zheik
- Zheik 改訂:Tammy
- Zyugem

`CraftJapanizer`, `WoWJapanizer` and `questjapanizer-wiki` are not people: they mark lines those projects
published with no translator's tag of their own.

## Lineage

The hand-written Japanese translations were made for **WoWJapanizer**, **QuestJapanizer** and
**CraftJapanizer_Quest** (milai and the translators listed above), 2012. They reached this project through:

1. **WoWpoPolsku-Quests** (Platine, wowpopolsku.pl): the addon architecture the later forks used (GPLv2).
2. **Classic Quest Chinese Translator** (luckycat_tv) and **Tooltips Translator - Chinese** (qqytqqyt): the
   merge of the Japanese text into the WoWpoPolsku runtime (GPLv2).
3. **Classic Quest Japanese Translator** (Crynok / Zyaga) and **Classic Tooltip Japanese Translator** (Zyaga):
   earlier addons for WoW Classic (GPLv2).

QuestJapanizer's and CraftJapanizer_Quest's own releases were read directly for the lines the chain above had
cut short.

## License of the Japanese translations

WoWJapanizer, QuestJapanizer and CraftJapanizer_Quest are published on CurseForge under the BSD License, using
the three-clause template with its year and owner left blank. Its text, as the license requires:

> Copyright (c) \<YEAR>, \<OWNER>
> All rights reserved.
>
> Redistribution and use in source and binary forms, with or without modification, are permitted provided that
> the following conditions are met:
>
> 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the
>    following disclaimer.
> 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the
>    following disclaimer in the documentation and/or other materials provided with the distribution.
> 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or
>    promote products derived from this software without specific prior written permission.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
> WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
> PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY
> DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
> LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
> INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
> TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
> ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The translators are credited by the tags they used. Their credit here does not mean they endorse this project.

## Upstream notices

The earlier addons for WoW Classic (GPLv2, CurseForge), as declared in their own files:

- Classic Quest Japanese Translator: `## Author: Crynok / Zyaga` · `-- Author: Crynok and Zyaga` ·
  `-- Credit to: qytqqyt and Platine https://wowpopolsku.pl` · Notes: "Data gathered from mod
  "WoWJapanizer" and merged with "Classic Quest Chinese Translator" by luckycat_tv which was based
  upon WoWpoPolsku-Quests (https://wowpopolsku.pl)."
- Classic Tooltip Japanese Translator: `## Author: Zyaga` · `-- Credit to: qytqqyt` · Notes: "This is
  a modified version of "Tooltips Translator - Chinese" by qytqqyt."

## English source text

The English text in `data/english/` is Blizzard Entertainment's. It is kept to align and hash the
translations and is never shipped in the addon. It was read from the Forever client's own tables and quest
cache, the Classic Era quest cache, wago.tools DB2 exports (`ItemSparse`, `SpellName`), and:

- pfQuest (`db/enUS/quests.lua`, https://github.com/shagu/pfQuest), under the MIT License (below);
- the VMaNGOS world database (https://github.com/vmangos/core, release `db_latest`, snapshot `db-13b49dc`),
  GPL-2.0: quest progress and completion text, gossip and book pages.
- forever-vo (https://github.com/quinn-dougherty/forever-vo), under the MIT License (below): quest progress
  and turn-in text and NPC greetings that players of the Forever client recorded with its addon and sent in.

## pfQuest license

> MIT License
>
> Copyright (c) 2017-2021 Eric Mauser (Shagu)
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
> associated documentation files (the "Software"), to deal in the Software without restriction, including
> without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
> following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial
> portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
> LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
> EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
> AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
> OR OTHER DEALINGS IN THE SOFTWARE.

## forever-vo license

> MIT License
>
> Copyright (c) 2026 Quinn Dougherty
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
> associated documentation files (the "Software"), to deal in the Software without restriction, including
> without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
> following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial
> portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
> LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
> EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
> AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
> OR OTHER DEALINGS IN THE SOFTWARE.

## This project

WoW Forever Japanese ships its own code and translations under GPL-2.0-or-later (see `LICENSE`); every
translated line keeps its provenance in `data/` (`provenance.translator`). The English text in `data/english/`
is Blizzard Entertainment's and is not licensed by this project. The bundled font is IPA UI Gothic under the
IPA Font License v1.0 (see `addon/WoWForeverJapanese/Fonts/`). Details: `docs/legal/licensing.md`.
