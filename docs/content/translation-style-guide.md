# Translation style guide: server-only text, client tooltips and interface text

version: sg11

> What a drafting model is given, with `pipeline/translation_glossary.tsv` and one batch file, to write the Japanese for quest progress text, quest completion (turn-in) text and NPC gossip, for book, letter and plaque pages, and for item and spell tooltip descriptions (the **Tooltips** section: a different register and different placeholder rules; read it instead of **Voice**). The rules come from the project's name policy ([principle 2](../architecture/principles.md#2-names-stay-in-english)) and from how the human quest corpus (WoWJapanizer / QuestJapanizer translators) writes these lines. Changing a rule or an example is a new version: bump `version:` (to the next `sg` number), and draft names end in the new `-sg<N>`. The **Interface text** section is the exception: it governs the UI dictionary drafts, which carry no version, so changing it bumps nothing.

## The task

- Each batch row is `{"ref", "kind", "en", "targets"}`, and quest rows (`progress`, `completion`) also carry `"items"`: the item names in that quest's objectives (`["Sack of Barley", "Sack of Rye", "Sack of Corn"]`, often empty). `kind` is `progress` (the NPC asks whether the task is done, shown before hand-in), `completion` (the NPC thanks the player and hands over the reward), `gossip` (what an NPC says when spoken to), `book` (one page of a book, letter, note or plaque the player reads), one of the **quest** kinds `quest_title` / `quest_objectives` / `quest_description` (see **Quests**), or one of the **tooltip** kinds `item_description`, `spell_description` and `spell_aura`, whose rows also carry `"slots"` (see **Tooltips**).
- Write one output row per batch row: `{"ref": "<the row's ref>", "ja": "<Japanese>"}`, one JSON object per line, nothing else. Every ref exactly once.
- Translate the meaning of the whole English text. Do not add sentences, drop sentences, summarise or explain.

## Names stay in English letters

- Every name stays exactly as written in the English, in English letters, inside the Japanese sentence: people (`Renee`), places and zones (`Stormwind`, `the Barrens` → `Barrens`), creatures and creature kinds (`quilboar`, `murloc`; but `goblin` follows the glossary, `ゴブリン`; the capitalised `Goblin Engineering` stays English like other profession names). WoW's own creature kinds stay in English letters (`kobold`, `gnoll`, `murloc`, `harpy`, `centaur`, `furbolg`, `ogre`, `raptor`, `wyvern`, `gryphon`, `worgen`, `quilboar`, `scorpid`, `crocolisk`), while real animals and common fantasy monsters are ordinary Japanese words (`wolf` → `狼`, `spider` → `クモ`, `tiger` → `虎`, `bear` → `熊`, `boar` → `猪`, `zombie` → `ゾンビ`, `skeleton` → `スケルトン`, `ghost` → `幽霊`, `dragon` → `ドラゴン`, `ooze` → `スライム` / `ウーズ`, `yeti` → `イエティ`). Items stay English too, also when the English writes them in lower case (`fang-ratchet`, `copper bars`, `lean wolf steak`), but only when the word names an item the quest asks for or hands over; the row's `items` list the objective items (`one sack of each: barley, rye and corn` for `Sack of Barley`, `Sack of Rye`, `Sack of Corn`), and an everyday word that is not such an item is translated (`candles`, `pie`, `tools`). So do spells, profession (skill) names as the interface shows them (`Skinning`, `Herbalism`, `First Aid`), factions and organisations (`Horde`, `Alliance`, `Scourge`, `Forsaken`, `Cenarion Circle`), events (`Winter Veil`).
- Never write a name in katakana or kanji, and never add a Japanese reading next to it (no `ストームウィンド`, no `嘆きの洞窟(Wailing Caverns)`).
- A title that is part of a name stays with the name (`Lord Kazzak`, `Commander Althea`, `King Magni`, `the Dark Lady`, `Lion's Pride Inn`): a title directly in front of or after a name word stays in English letters with it.
- A title or common noun used on its own is translated, even when the English capitalises it: `the Captain` → `隊長`, `the Kingdom` → `王国`, `His Majesty` → `陛下`, `the Guard` → `衛兵`, `Master` → `師匠` (`主人` when a servant or pet speaks to its owner), `the Warchief` → `大族長`, `the Inn` → `宿屋`, `the Lady` → `奥方`, `the Arch Druid` → `大ドルイド` (but `Arch Druid Hamuul`), `the Creators` → `創造主`, `the Queen` → `女王`, `the Commander` → `司令官`, `Private` → `二等兵`, `a Commendation Officer` → `表彰官`, `the Temple` → `神殿`, `the Bank` → `銀行`, `the Holy Light` (the faith) → `聖なる光`, `the Ambassador` → `大使`, `Father` (a priest) → `神父`, `the Templar` → `テンプル騎士`, `the Grunt` → `兵卒`, `the Blacksmith` → `鍛冶屋`, `the Tradesman` → `商人`, `the Earthshaper` → `大地の形成者`, `the Auction House` → `オークションハウス`. A day of the week is not a name either: `this Sunday` → `今度の日曜日`. The glossary lists these.
- A place or group joined by `of` is one name and stays in English letters: `Temple of the Moon`, `Bank of Orgrimmar`, `Brotherhood of the Light`, `Duke of Shards`. A person title with `of` is translated: `the King of Stormwind` → `Stormwindの王`.
- A profession trainer keeps the skill name in English letters and translates the role: `Skinning Trainer` → `Skinningのトレーナー`, `a Mining Trainer in Thunder Bluff` → `Thunder BluffのMiningのトレーナー`.
- A hyphen ends a word, so only the name part stays in English letters: `Scourge-driven` → `Scourgeに駆られた`, `A-number-one fisherman` → `一流の釣り人`.
- A `*cough*` or `<Sob>` stage direction is not read as prose, and the word after it starts a sentence.
- A word is not a name just because it starts a sentence: `Say Captain... I overheard you!` is the Captain (`隊長`), `Our Alchemist's name is Carolai Anise.` is the alchemist (`錬金術師`), `Six Lieutenants control the front line.` are lieutenants (`副官`). A skill name there still stays in English letters: `Tailoring you say?` → `Tailoringだって？`.
- A mob name stays in English letters even when it contains a class or race word (`Skeletal Warrior`, `Murloc Warrior`, `7 Warriors` naming a murloc kind): the word is part of the name.
- Japanese particles attach directly: `Stormwindへ`, `Hordeの力`.
- **Races and classes are the exception: write them in katakana** when they mean the player race or class (`Tauren` → `トーレン`, `Druid` → `ドルイド`, `Night Elf` → `ナイトエルフ`), with the glossary's spellings. They are the same words the addon puts in for `{race}` and `{class}`, and the human translators write them this way. "Dwarven", "orcish" and other adjective forms use the same word (`ドワーフの`).
- A capitalised word that is not a name (`the Light`) is translated; the glossary lists those.

## Tokens, paragraphs and numbers

- `{name}`, `{class}` and `{race}` are filled with the player's name, class and race in game. Keep each token exactly as written, as many times as the English has it (`ありがとう、{name}。`).
- `$G<male>:<female>;` means the English changes with the player's gender. Write one Japanese wording that fits both; never write both forms, a slash pair or the `$G` code. When it is a way of addressing the player (`$Glad:lass;`), keep an address that fits both (`若いの`, `君`); do not drop it.
- `$` followed by digits and `w` (`$1997w`) is a number the game fills in. Keep it exactly as written, every one of them.
- The English separates paragraphs with a blank line. The Japanese has the same number of paragraphs, separated by one blank line.
- Numbers stay the same values, written in digits (`three` → `3`). Write a digit only for a number the English writes as a digit or a number word. "A", "an", "both", "another", "once" and the like are not number words: use kanji or words (`an hour ago` → `一時間前`, `both parts` → `両方の部分`, `the other way` → `もう一つの方法`).
- `...` is `……`. Use `。` and `、`; `!` and `?` may be half- or full-width but keep one width within a line.

## Voice

Infer the speaker from the text (who talks this way, to whom) and keep the voice through the whole line.

| Speaker | Voice | Seen in the corpus |
|---|---|---|
| priests, druids, healers, gentle scholars | です・ます, あなた | 759, 4904, 6393 |
| elders, nobles, ancient or regal beings | archaic: そなた, 我, ～ぞ, ～であろう | 1489, 8765 |
| soldiers, orcs, Forsaken, hard or military speakers | plain だ, 君 or お前, ～ぞ | 848, 871, 3981 |
| cheerful, informal, merchants, goblins | casual: ～よ, ～ね, ～だろう | 423, 8282 |
| a speaker who is clearly a woman in the English (a name, "she", a female title) | may use ～わ, ～の; never guess a gender the English does not show | 8937, 8951 |
| unclear | plain だ, あなた; no strong character | |

- Address the player as the English does (`{name}`, `{class}`, "friend" → `友よ`).
- Progress text is short and a little impatient or hopeful; completion text is warm or matter-of-fact; gossip is ambient and can be flavourful, but still only what the English says.

## NPC speech (gossip lines an NPC says, yells, whispers or emotes)

The gossip kind also carries what NPCs say in the chat window, in speech bubbles and on screen: says, yells, whispers, emotes and boss emotes. The rules above apply; three more:

- `%s` is the speaking NPC's name, which the game puts in (`%s goes into a frenzy!`). Keep every `%s`, exactly as many as the English has, and write the sentence so an English name fits there: `%sは狂乱状態になった！`. Never write any other `%`.
- A yell is short and loud: keep the English's exclamation marks and do not soften it. A battle cry stays a battle cry (`For the Horde!` → `Hordeのために！`).
- An emote describes the NPC in the third person (`%s laughs.` → `%sは笑った。`), in plain past tense.

## Books, letters and plaques (`book`)

One row is one page. A long book is split over many pages, and each is drafted as its own row: translate the page as it stands, never carry a sentence over from another page, and never add a title or a page number.

- **Register by document kind.** Read what the page is and keep that voice through the page:
  - a lore book, history, chronicle, field guide or report: written prose, だ・である (`Kalimdorと呼ばれたその大地には…`), no です・ます;
  - a letter, note, diary or order: the writer's own voice, as for a speaker (a polite letter です・ます, a soldier's order だ, a noble archaic); the greeting (`Dear Morgan,`) and the closing (`Warm regards,`) become natural Japanese letter phrases (`Morganへ`, `敬具`), with the names kept in English letters;
  - a plaque, epitaph, memorial or inscription: formal and short, だ・である or an archaic voice, no casual endings.
- **Headings and signatures.** A heading is translated unless it is a name (`In Memory` → `追悼`; `Kurdran Wildhammer` stays). A signature or attribution line keeps the name in English letters and translates the role around it (`- Thrall, Warchief of the Horde` → `- Hordeの大族長、Thrall`).
- **Line layout.** Keep every paragraph break, and keep a single line break where the English has one (a poem line, a list item, a signature on its own line).
- **Codes and numbers the page shows as they are.** A date, a code or a Latin phrase that is not English prose (`50 BTFT - 25 ATFT`, `M.D.`, `PhD`) is kept exactly.
- **HTML pages.** A page that starts with `<HTML>` is markup the game renders. Keep every tag exactly as written, with its attributes, in the same order, each on the same line as in the English (`<HTML>`, `<BODY>`, `<BR/>`, `<P>`, `<H1 align="center">`, `</P>`, …), and translate only the text between the tags. Never add, drop, merge or reorder a tag, and never change `<BR/>` into `<BR></BR>` or the reverse.
- **Bracketed prose on a plain page** (`<illegible text>`, `<The rest of the page is torn away.>`) is text the reader sees: translate the words inside and keep the angle brackets (`<判読できない文字>`).

## Tooltips (`item_description`, `spell_description`, `spell_aura`)

These rows are **not** dialogue. Nobody is speaking: the text is what the game prints inside an item's or a spell's tooltip. Ignore the **Voice** section for them and follow this one.

- **Register.** Plain, informative `です・ます`: `体力を回復します。`, `ダメージを与えます。` No speaker, no address to the player, no `よ`/`ね`/`ぞ`, no archaic forms. One sentence per English sentence.
- **The English is a template, not finished text.** `Restores $o1 health over $d.` is what the *data* holds; the player sees `Restores 61 health over 18 sec.` The numbers and the duration are filled in by the game, differently per item, rank, level and talent, so the Japanese must carry placeholders where they go, never the values themselves.

### `$N<k>`: a number

`$N<k>` is replaced with the **k-th number of the line the player is actually shown**, counting every number in reading order. The row's `"slots"` says how many there will be.

```
EN   Restores $s1 health.                     slots 1
JA   healthを$N1回復します。
```

A number written out instead (`61`) is refused (`numbers_changed`): the template holds `$s1`, not the value, and a written number stops the whole line from shipping as soon as the game shows a different one. This is why 919 of the 927 item descriptions the predecessor corpus shipped no longer display.

### `$D<k>`: a duration

A duration is the one value whose **unit** the game chooses: `$d` prints through `%d秒` / `%d分` / `%d時間` / `%d日` depending on its length, so the same template is seconds on one item and minutes on another. **Never write a unit yourself.** `$D<k>` is replaced with the whole duration phrase (number and unit together), exactly as the player sees it.

`$D` counts **durations only**: `$D1` is the first duration in the line, whatever `$N` index its number happens to have.

```
EN   Restores $o1 health over $d.  Must remain seated while eating.    slots 2
JA   $D1かけてhealthを$N1回復します。回復中は坐っている必要があります。

EN   Stuns for $d and slows for $d1.
JA   $D1スタンさせ、$D2の間スローにします。
```

**A number the English writes in front of a unit is a duration too.** The game shows `every 5 sec for 15 sec`, and the addon reads both phrases, in reading order, so `$D1` is `5 sec` and the `$d` is `$D2`. The batch row's `"durations"` gives the range.

```
EN   Regenerate $s1 health every 5 sec for $d.    slots 3 · durations 2
JA   $D2の間、5秒ごとにhealthを$N1回復します。
```

The written `5 sec` may be written out (`5秒`) or taken as `$D1`; the `$d` must be `$D2`. Each code slot needs the placeholder that points at **it**: `$N2` for the `$d`'s number is refused (`duration_as_value`), and a `$N<k>` that points at another slot does not carry a dropped one (`slot_missing`).

Writing `$N2秒` instead is refused (`duration_as_value` / `duration_missing`), even though it looks right: it is right only while the game happens to print seconds. The runtime gate cannot catch that mistake, because the number matches and the unit is Japanese text it never reads, so the check here is the only one.

### Counting the slots

`"slots"` counts every number the client will print, in reading order:

- a value code (`$s1`, `$o2`, `$d`, `$7922d`, `$/10;s2`, `$b1`, which is points per combo point, not a line break): one;
- **arithmetic** (`${$m1/60}`, `${$1279976m1*$d*$<frostdamage>}`): one, however many codes are inside it: the client works it out and prints the number it comes to;
- a literal the template already shows (`Teaches Frost Ward (Rank 5).`): one;
- **a range**, two values joined by ` to ` (`$s1 to $s2`, `${…} to ${…}`, `20 to 40`), and a single code the game prints as one (Fireball's `$s1` shows `14 to 22`): one. The addon fills `$N<k>` with the whole range as `14～22`, so write `$N1のダメージ`, never `$N1～$N2`;
- **pluralisation** (`$lsecond:seconds;`): none, it prints a word.

A row you are given always has a number in `"slots"`. A conditional whose two branches differ only in their numbers (`absorbing $?a14748[${…}][$s1] damage`, `reduces the damage by $?a415096[20%][30%]`) prints the same values either way: write the sentence once, with a placeholder for the value, never a number from either branch. Rows with **included text** or **branches** (below) are given to you too since sg11.

### Included text and inline icons (sg11)

Some templates splice another spell's text into the line (`$@spelldesc434 If you spend…`). The batch row already shows you the **spliced** English (what the player reads), so translate it as one line, counting its slots like any other. Nothing tells you where the included part starts; it does not matter, the addon reads the whole line.

An inline spell icon is shown as `$I1`, `$I2`… Carry each **exactly once**, where the icon belongs in the Japanese sentence (usually right before the spell's name, as in the English). The addon puts the icon back there; a missing or doubled `$I<k>` is refused (`icon_missing` / `icon_index`).

```
EN   Engrave your chest with the Dual Wield Specialization rune: $I1 Dual Wield Specialization: Increases …
JA   胸部か法衣にDual Wield Specializationのルーンを刻みます：$I1 Dual Wield Specialization：…
```

### Branches (sg11)

A row with `"branches"` holds `$?<condition>[A][B]` (or a chain `$?c1[A]?c2[B][C]`): the game prints **one** of the bracketed texts, chosen by talent, form, faction or level. Keep the conditional in the Japanese, **same condition, same number of branches, same order**, and translate each branch so the whole sentence reads right with any one of them in place (an empty branch stays empty: `[]`).

- `$N<k>` / `$D<k>` number the values of the **whole template in reading order, every branch included**: the row's `"slots"` / `"durations"`. A value inside a branch keeps its whole-template number, and must sit inside the same branch in the Japanese. The addon renumbers each branch combination itself.
- Names inside branches stay in English letters, exactly as the English writes them; often they are what tells the branches apart on screen (`Orcish Tradeskill Sign` / `Dwarven Tradeskill Sign`).
- Colour codes (`|cFFFFFFFF…|r`) are carried as they are.

```
EN   Absorbs $s1 Fire damage$?s11094[ and grants a $s2% chance to reflect Fire spells and effects][]. Lasts $d.
     slots 3 · durations 1 · branches 2
JA   $N1のFireダメージを吸収します$?s11094[。さらに$N2%の確率でFireの呪文と効果を反射します][]。効果時間は$D1です。
```

A row whose branches could not be told apart on screen (Tiger's Fury: the same "Requires Cat Form" in white or red) is never handed to you. If the Japanese of two branches would read identically where the English differs, say so rather than guessing.

### Names and fixed words in tooltips

- Spell, item, zone and creature names stay in English letters, as everywhere (see **Names stay in English letters**). `Teaches Frost Ward (Rank 5).` → `Frost Ward（Rank 5）を習得します。`
- **`Rank` stays in English letters for now.** It reads as part of the spell's name beside one, and whether words like it become Japanese belongs with the names and titles work, not here. The same goes for any capitalised word inside an English sentence that the glossary does not list.
- A stat word the allowlist carries (`health`, `mana`, `armor`, `rage`) is kept as the corpus keeps it, in English letters: `healthを$N1回復`.
- **Say exactly what the English says, no wider.** `while drinking` is drinking, not `飲食中` ("eating and drinking"); `one ally` has no number to write, because the English writes none; a digit the English does not have is refused (`numbers_changed`).
- `%` stays `%`. A percentage reads `$N1%`.

## Quests (`quest_title`, `quest_objectives`, `quest_description`)

The quest window's three parts. `progress` and `completion` above are the same quest's later text and follow **Voice** as they always did; these three are new to the guide, and each has its own register.

### `quest_description`: the quest-giver speaking

This is the NPC talking to the player, so **Voice** applies in full: infer the speaker, keep that voice through the whole text, address the player as the English does. Same paragraph rules as every other prose field.

### `quest_objectives`: an instruction to the player

The line under "Quest Objectives": what the player has to do. Not dialogue, and **not a command**. Write it the way the corpus already writes its 8,894 hand-written objective lines: plain `〜する` or polite `〜してください` / `〜して下さい`:

```
EN   Bring Bartleby's Mug to Burlguard.
JA   Bartleby's MugをBurlguardのところへ持って行って下さい。

EN   Kill 6 Rockjaw Troggs.
JA   Rockjaw Troggを6体倒す。
```

Never the imperative (`〜せよ`, `〜を倒せ`). Where the English says "X wants you to…", say so rather than turning it into an order: `〜してほしいとXは言っています`.

### `quest_title`: a short heading

A noun phrase, not a sentence, and usually no final `。`: `自然界のバランス`, `人民軍`.

**The name check does not run on a title row**, because a quest title is written in title case ("The Alliance Needs Copper Bars", "Keeper of the Flame"), so capitalisation says nothing about which word is a name, and the check flagged 157 of 256 rows on the first batch, none of them names. That means **the name rule is yours to keep here, with no safety net**: a name of a person, place, mob, item or spell stays in English letters, and nothing else does. `Grove of the Ancients` → `Ancientsの木立`, not `古代の木立`; `The Price of Shoes` → `靴の代償`, because none of those is a name.

### Numbers in quests

A number written out in the English (`Bring 10 Linen Cloth`) is written out the same in the Japanese. A server code that stands for a number the client fills in (`$1oa`, `$2oa`) takes `$N<k>` like a tooltip: `$N1` for the first number of the live line, counted in reading order (see **Counting the slots**). The batch row's `value_slots` says how many; the lint fails a row that drops one. No `$D<k>` in quests. Keep `{name}`, `{class}` and `{race}` exactly as they appear, and keep a `$<n>w` server counter exactly as written, as everywhere else.

## Interface text (UI strings)

Interface strings are the client's own labels, buttons, headers, dialogs and messages: the UI dictionary, one Japanese per string key (`data/ui`). They are not cut into batches; a draft is `{"id", "field": "text", "ja"}` rows written against each key's current English ([Translation batches, UI dictionary batches](../operations/translation-batches.md#ui-dictionary-batches)). The player holds the reveal key to see the English, so a label never explains itself. Six rules:

### 1. Meaning in context

Translate the sense the screen uses where the string appears, not the dictionary's first sense. Judge it from the key name, the windows that show it (`pipeline/ui_inventory.txt`) and the keys around it. `Close` on a window button is `閉じる`; the same English as a barber shop style, listed among horn and tusk shapes (`Gougers`, `Stubs`, `Backswept`), is `寄せ` (set close together). When nothing says where a string appears, take the sense a player could meet with that key name, and when the English has two senses, prefer a Japanese that reads right in both.

### 2. Length that fits

A label is as short as its English and never longer in kind: a one-word English label is one Japanese word, not a phrase. `Accept` is `承諾`, never `このクエストを受け入れる`. `Abandon Quest` is `クエスト放棄`. For a short label (at most three English words, no `%` argument or markup, no sentence ending) the display width of the Japanese, counting a full-width character as 2, should stay within the English's width × 1.25, and any label may take three full-width characters. `ui_lint` warns past that limit. The warning asks for a second look, not a rewrite: a katakana loanword (`Legendary`, `レジェンダリー`) is often wider and still the right word. Messages, errors and dialog text have no limit, but add nothing the English does not say.

### 3. Register

Labels, buttons, tabs and headers are bare nouns or verb stems, with no `です`, `ます` or `してください`. Dialog questions and messages are full sentences in the polite form, the same form everywhere: `Inventory is full.` is `バッグがいっぱいです。`, and `Abandon "%s"?` is `「%s」を放棄しますか？`. Emote lines, what the chat prints when a player uses an emote, are narration and take the plain past form: `You wave at %s.` is `あなたは%sに手を振った。`. Strings of the same kind read the same way in every window.

### 4. Consistency

One English, one Japanese: every key whose English another key already ships takes that Japanese (`Accept` is `承諾` on all four of its keys), unless the key owns its Japanese on one screen (`UIStrings.OWN`, [ADR-037](../adr/037-staticpopup-dialogs-and-owned-keys.md)). Game terms follow `pipeline/translation_glossary.tsv`, and the interface's own terms follow the table below (the glossary is the quest translators' usage; these are the words the windows use). A tab and the window it opens agree, and so do a button and the dialog it raises.

Settled interface terms (a test holds every shipped UI line whose English has the term to the Japanese, never the other spellings):

| English | Japanese | Not |
|---|---|---|
| achievement | アチーブメント | 実績 |
| profession, tradeskill | 専門技能 | 職業, 専門スキル, 専門職 |
| world map | ワールドマップ | 世界地図 |
| bank | バンク | 銀行 |
| battleground | 戦場 | バトルグラウンド |
| specialization | 専門化 | スペシャライゼーション |
| crafting order | 製作依頼 | 製作注文 |
| role | ロール | 役割 |

A banker, the NPC, is `銀行員`: a person, not the bank window. `戦場` is shorter than `バトルグラウンド` and fits a button (`Leave Battleground` is `戦場から離脱`).

### 5. Format intact

Keep every `%s` / `%d` specifier, colour code (`|cff…` to `|r`), texture (`|T…|t`), atlas, link and line break. When Japanese word order moves the arguments, number them (`%1$s`, `%2$s`). `Requires Level %d` is `必要レベル %d`. `ui_lint` and `make check` refuse a line that drops or changes one.

### 6. Names stay English

A name of a person, place, item, spell, faction or zone inside a UI string stays in English letters, as everywhere else ([principle 2](../architecture/principles.md#2-names-stay-in-english)). Race and class words take the glossary's katakana in a sentence; a race or class shown as a label on its own stays English.

## Glossary

Use `pipeline/translation_glossary.tsv` for recurring words that are translated (`adventurer` → `冒険者`, `the Light` → `光`) and for the race and class words. A term marked `required` must be written exactly as the glossary gives it (`warrior` → `ウォリアー`, never `戦士`), unless it is part of a name and so stays in English letters (`Skeletal Warrior`); the others are the preferred rendering. Titles and common nouns (`captain`, `kingdom`, `his majesty`) are translated when used on their own and stay in English with a name that follows them. Never write two renderings joined by `/` (`師匠/主人`): choose one. A word not in the glossary and not a name: translate naturally.

## Examples

Real human translations from the shipped corpus (quest id and field; the English is shown the way a batch row shows it). A test keeps these equal to `data/`.

```example quest=6393 field=completion
EN:
The water spirits within me bubble with the excitement. {name}, you have given me a glorious victory to report to the Tribunal of the Tides.
JA:
私の中の水が興奮に沸き立っています。{name}、あなたは私にTribunal of the Tidesへ報告する輝かしい勝利を与えてくれました。
```

```example quest=759 field=completion
EN:
Very good, {name}. I can feel the sacrifice of the land in this offering, and my spirit swells with sadness, and pride.
JA:
とても良いですよ、{name}。この捧げ物には、この地が払った犠牲を感じ取れます。それで私の魂は悲しみと誇りとで溢れているのです。
```

```example quest=4904 field=completion
EN:
Thank you, {name}. Deep in my bones I knew that she would find her way back to me. She told me of your bravery and how you helped her escape. These items belonged to her brother. I know she would want you to have them.
JA:
ありがとう、{name}。Lakotaが私のところへたどり着くであろうことは、身に沁みるほどよく分かっていました。あなたの勇敢さ、あなたがいかに逃亡の手助けをしてくれたか、彼女は話してくれました。この品は彼女の兄弟のものです。これをあなたに持っていて欲しいと望んでいるはずですよ。
```

```example quest=8282 field=completion
EN:
Yes! You brought my satchel back. And my rare reagents are all here! I'll be in your debt for a long time.
JA:
やったぞ! 鞄を取り戻してくれたね。それに、貴重な試薬も全部ここに揃ってる! ずっと恩に着るよ。
```

```example quest=8937 field=completion
EN:
You've kept your end of the bargain, I shall keep mine.

Just remember that I'm holding on to the best pieces until your work is finished.
JA:
あなたはきちんと責任を果たしてくれたわ。私も約束を守ることにしましょう。

あなたの仕事が終わるまでは、一番いい部分は私が持っているということを覚えておいてね。
```

```example quest=848 field=completion
EN:
Ah, yes. These are good specimens. Potent.

I am Forsaken, and we honor our contracts. Here is your reward, {name}.
JA:
ああ、いいね。良い標本だな。効力が強い。

私はForsakenだ。我々Forsakenは契約を重んじる。これは君への報酬だ、{name}。
```

```example quest=871 field=completion
EN:
You have done well, {name}. Those insolent quilboars will finally learn that the might of the Horde is not to be ignored.
JA:
よくやったぞ、{name}。生意気なquilboarどもめ、Hordeの力を無視するべきでないとこれでようやく思い知ったろう。
```

```example quest=8765 field=completion
EN:
Be well, {name}. If you change your mind, I shall be here to assist you.
JA:
{name} よ、達者でな。そなたの気が変わったとしても、我はそなたを支えるためにここにいる。
```

```example quest=1489 field=completion
EN:
I bid you greetings, {name}. You are welcome here, and I suggest you gather all your strength. For the task we now set before you ... is a dire one.
JA:
ごきげんよう、{name}。歓迎しているぞ。そなたの持てる力をすべて集結させるよう、勧める。我々が今そなたに頼もうとしている仕事は……恐ろしく危険なものだからな。
```

```example quest=423 field=completion
EN:
I hope I can acquire enough energy from such a limited sample. Perhaps I should have had you get more shackles.

Nonetheless, you showed great skill in collecting these, {class}.
JA:
この数で十分なエネルギーを得られるだろうかな？もっと取ってきてもらえばよかったよ。

とはいえ、十分な働きだったよ、{class}。
```

```example quest=3981 field=completion
EN:
We haven't got much time. Listen carefully, {race}. What I have to tell you is classified and for your ears only.
JA:
あまり時間がない。よく聞いてくれ、{race}。お前に言うことは極秘だ、お前だけに話す。
```

```example quest=8951 field=completion
EN:
I can't believe our lives are all but forfeit all because of a stupid medallion! And you're sure Anthion mentioned Bodley?

Well, you've done your job so let's get your reward out of the way.
JA:
私たちの命がこの馬鹿げたメダルのせいですっかり犠牲になっているだなんて、信じられないわ! それで、AnthionがBodleyについて話したことは確かなの?

じゃ、あなたは仕事を終えたのだから、忘れないうちに報酬を渡しましょう。
```
