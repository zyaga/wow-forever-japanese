# Research: the interface text read against where it appears

> Measurement. Every shipped interface string (the UI dictionary, Forever build 1.60.1.70009) read once against its
> English and the windows that show it, under the style guide's
> [Interface text](../content/translation-style-guide.md#interface-text-ui-strings) rules. The lines were
> machine-written in batches and had not been read against their context before. A quality pass, not a rewrite:
> a line that works was left alone. Tooling: `wfj.dev.audit_batch --type ui` (`wfj.dev.audit_ui`),
> `wfj.dev.ui_lint`.

- **Date:** 2026-09-30
- **Question:** how much of the shipped interface text reads wrong in its window, too long, in the wrong register
  or with a term that disagrees with the rest, and what does fixing it take?

## Scope

| | Count |
|---|---|
| Shipped UI lines | 13,392 |
| (English, Japanese) pairs audited (`cut` printed this count) | 12,124 |
| Pairs whose keys have a window in `pipeline/ui_inventory.txt` (judged by screen) | 7,641 |
| Pairs with no known window (judged by key name and English) | 4,483 |
| Parts of 400 pairs, one reviewing model each | 31 |

A pair is one English and its Japanese; keys that share both are read once and fixed together. 37% of the pairs
have no window in the inventory: their keys are built at run time (emotes, barber choices, enchant stat lines,
achievement text), so no window in the client's UI source names them. A search of that source for 80 random such
keys found 3, so the audit judged these from the key name, its neighbours and the English instead.

## Verdicts

| Verdict | Pairs |
|---|---|
| match | 11,914 |
| correct | 209 |
| split | 1 |
| redraft | 0 |

98.3% of the pairs read right as they were.

By window (the ten with the most pairs; a pair shown in two windows counts in both):

| Window | Pairs | Match | Correct | Split |
|---|---|---|---|---|
| (no known window) | 4,483 | 4,424 | 59 | 0 |
| errors | 2,483 | 2,439 | 44 | 0 |
| chatsystem | 2,481 | 2,447 | 34 | 0 |
| settingspanel | 1,509 | 1,482 | 27 | 0 |
| popups | 335 | 323 | 12 | 0 |
| communities | 300 | 292 | 8 | 0 |
| help | 288 | 283 | 5 | 0 |
| tooltip | 260 | 244 | 16 | 0 |
| editmode | 244 | 241 | 3 | 0 |
| character | 215 | 214 | 1 | 0 |

The split is in `chatconfig` and `friends` (186 and 103 pairs). No window stands out: corrections run from 0 to
about 6% of a window's pairs, highest in `tooltip` (item class and quality words) and `popups`.

| Kind | Corrections |
|---|---|
| inconsistent (a term that disagrees with its siblings or the settled table) | 135 |
| name (a name translated; put back in English letters) | 20 |
| register (a polite label, a plain message) | 17 |
| other (`...` for `……`, a broken phrase) | 15 |
| context_sense (the wrong sense of the English) | 10 + 1 split |
| too_long (a phrase for a one-word label) | 5 |
| meaning | 5 |
| particle | 1 |
| format | 1 |

Examples (English → before → after):

- **context_sense**: `Declined` (a community application's status) 辞退 → 却下; `Blunt` (a horn style) 鈍角 → 丸み.
- **too_long**: `Outbid` 入札額を超えられた → 競り負け; `Available` (a cooldown alert option) 使用可能になったとき → 使用可能時.
- **register**: `Age Verification Required` (a dialog title) 年齢確認が必要です → 年齢確認が必要; `You stop following %s.`
  %sの追従をやめた。 → %sの追従をやめました。
- **name**: `Increases alchemy skill by %s.` 錬金術スキル → Alchemyスキル (the profession keeps its English name).
- **meaning**: `Scruffy` (hair) 無精 → ぼさぼさ.

Three pairs were kept as `unsure`: their English has two senses and no window says which (`Button` and `Top` as
barber choices, `Opening` as a skill or a status). Each keeps a Japanese that reads right in the likelier sense.

## Settled terms

Where the windows used two words for one game term, the parts first fixed each line to its siblings; terms that
recurred across parts were then settled once and a sweep brought every line in line (45 lines). The table is in
the style guide (rule 4) and a test holds every shipped UI line to it.

| English | Japanese | Lines checked | Replaced spellings |
|---|---|---|---|
| achievement | アチーブメント | 38 | 実績 |
| profession, tradeskill | 専門技能 | 42 | 職業, 専門スキル, 専門職 |
| world map | ワールドマップ | 46 | 世界地図 |
| bank | バンク | 61 | 銀行 (a banker, the NPC, stays 銀行員) |
| battleground | 戦場 | 58 | バトルグラウンド |
| specialization | 専門化 | 50 | スペシャライゼーション |
| crafting order | 製作依頼 | 8 | 製作注文 |

**Battleground** was first settled on バトルグラウンド, the more common spelling (31 lines against 24). Applying it
doubled the width of `Leave Battleground` and its siblings, so the rule that a label fits its widget won and the
term became 戦場, the shorter word, with `レート制戦場` for a rated battleground.

These stay prose-only in `pipeline/translation_glossary.tsv`, which records what the human quest translators used:
the quest text says 銀行 for the bank building, which is right there.

Left as they are, each consistent within its own set: the emote lines (plain past, narration: `あなたは%sに手を振った。`),
spell reagents (触媒), health (体力 and HP, both common; two lines moved between them to match their siblings), and short settings rows that read as messages
(`Requires DirectX 12` → `…が必要です`).

## Splits

A split is one English that needs two Japanese on two screens. The addon finds a string by its English, so the
second sense ships only through `UIStrings.OWN` and a widget that asks for the key by name
([ADR-037](../adr/037-staticpopup-dialogs-and-owned-keys.md)).

| Key | English | Here | Elsewhere | Widget |
|---|---|---|---|---|
| `COMBATLOG_FILTER_STRING_FRIENDLY_UNITS` | Friends | 味方 (friendly units) | フレンド (the friends list) | the chat settings' combat log unit rows now ask for the unit filter keys by name |
| `PROFESSIONS_REAGENT_CONTAINER_LABEL` | Reagents: | 素材: (crafting materials) | 触媒: (a spell's reagents) | the recipe form already asked for the key by name |

The second was found by `make validate`, not by a part: `Reagents:` and `Reagents: |n` are one English to the
addon but two rows in the audit. The audit rows now carry `siblings` (keys the addon finds by the same English) and
`ui_lint` fails a draft that would ship two Japanese for one English (`ambiguous:`), so the same slip is caught
before an import.

## Length

`ui_lint`'s width warning (a short label wider than its English × 1.25, at least three full-width characters):

| | Too wide | Polite label |
|---|---|---|
| Before | 876 | 9 |
| After | 866 | 3 |

The warning is a reading aid, not a rule: most warned labels are katakana loanwords that are wide by nature
(`Legendary` → レジェンダリー). Of the 274 shipped lines that changed, 107 got wider (mostly a settled term longer than
the word it replaced, and パーティ → パーティー) and 125 narrower.

## Cost

| | Tokens |
|---|---|
| Pilot part (400 pairs) | 111,450 |
| All 31 parts | 3,277,443 |

About 270 tokens a pair, one read each. The pilot's match rate (390 of 400) held across the run.

## Result

274 shipped lines changed. They were imported as one machine draft (`draft-ui-review`), and their word lists were
written in the same round; 7 of them hold a colour code or `|n` and take none. The draft had one more row, whose
term was changed and then changed back, so its Japanese stayed the same. Every other line keeps its Japanese.
