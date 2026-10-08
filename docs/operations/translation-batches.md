# Runbook: translation batches

> How machine-drafted Japanese enters `data/`: cut a batch of untranslated English, have a model draft it, lint the draft, expand it into import files, import, check and regenerate. The same flow covers quest text (title, objectives, description, progress, completion), NPC gossip and speech, book pages, objective and area text, item and spell tooltips, and, with small differences, the UI dictionary. Tools: [Pipeline → Translation batches](../systems/pipeline.md#translation-batches).

## Goal

One batch goes from untranslated English to imported, checked, generated `machine` lines, with their word lists where the type takes them. The pipeline never calls a model: a drafting model writes the Japanese between `cut` and `translate_lint`, and everything else is deterministic tooling.

## Prerequisites

- A checkout where `make check` passes on the current `data/` ([Local setup](local-setup.md)).
- The [Translation style guide](../content/translation-style-guide.md) (its `version: sg<N>` line is the current style version) and `pipeline/translation_glossary.tsv`.
- A drafting model, given one batch at a time. Its model id goes into every line's provenance, so read it from the model you actually used; never type it from memory.
- **Where batch files live.** All tool commands below run from `pipeline/` and write to `pipeline/batches/`, a scratch folder ignored by git. `make` targets run from the repository root. A batch's files (the cut, the draft, the lint-passed rows, the expanded import files) are working files: what ships is the result in `data/`, with provenance on every line.

## What `cut` selects

- **Kinds.** `progress`, `completion` (quest progress and turn-in text), `gossip` (NPC greetings and speech), `book` (a book, letter, note or plaque page), the client's quest text `quest_title` / `quest_objectives` / `quest_description`, `objective` (a quest objective's own text, keyed by QuestObjective id), `area` (a quest's exploration or event objective, keyed by quest id), and the tooltip kinds `item_description`, `spell_description`, `spell_aura`. A book page written as HTML (`<HTML>…`) reaches the row with its tags and line breaks unchanged. The addon finds area and objective text in one index, so an area and an objective line with the same English must be drafted to the same Japanese (`validate` refuses otherwise).
- **Tooltip English is a template** (`Restores $o1 health over $d.`): the client fills the values per item, rank, level and talent, so a draft never writes a number the client supplies. It writes `$N<k>` for the k-th value of the line the player sees and `$D<k>` for the k-th duration, whose unit the client chooses ([ADR-028](../adr/028-a-duration-is-copied-not-named.md)). A number the English writes before a unit word (`every 5 sec`) is a duration too. Quest title, objectives and description rows take `$N<k>` for a count the server fills in (`Collect $1oa Lady's Tear Moss.`). In tooltip English, `$n` / `$c` / `$r` are values (`within $r yards`), not player tokens, and a `$b<k>` is a value; only a `$b` with no digit is a break. Quest text keeps every `$B` run as a paragraph break.
- **`--src PREFIX`** keeps only English whose `src` starts with the prefix (`--src db2@`, or one build: `--src db2@1.60.1.70170`), so tooltip lines are drafted from the Forever client's own English. Spell kinds take every served spell: the scope is what the client serves, and the coverage gaps list what is left ([ADR-052](../adr/052-coverage-by-served-data.md)).
- **Quest text from Classic Era English.** Quest title, objectives and description that the Forever server has not answered yet are drafted from the Classic Era English the import carries (no `--src`). Forever changed the English of about 2 % of the quests both clients hold; a later Forever rewording shows the stale marker ([ADR-003](../adr/003-ship-stale-with-marker.md)) until the line is redrafted.
- **Skipped.** A bare label: English with no lower-case word, no `{name}` / `{class}` / `{race}` token and no `.` `?` `!` `…` (`Stratholme`, `Auction House`). It ships as the English. The title-case kinds (`quest_title`, `objective`, `area`) are never skipped this way, because title case makes a real title look like a label. Nor are the tooltip kinds: item flavour text is written in title case too (`Made With Love`, `Soft Like Pudding`), so a tooltip row with no prose is cut, marked `title_case` and checked by its `names` like a quest title. One whose whole English is an item, spell or creature name (`Lightning Shield`, `Warlord`) is also marked `name_only`; its draft may be exactly that English, and an item or spell **description** kept in English letters ships only with `ruling: accept` on the line (the aura field takes it as it is). An objective or area line that is only a name is listed in `pipeline/objective_names.txt` / `pipeline/area_names.txt` instead of being drafted; a quest title that is only a name is drafted and ships that name in English letters. Also skipped: every field of a placeholder quest (`<UNUSED>`, `<NYI>`, `REUSE`; `io/wdb.PLACEHOLDER_TITLE`), a line already `trusted`, a line that already has a `machine` variant, and a line with any `human` or `correction` variant (machine output never competes with hand-written text; see [Principles §6](../architecture/principles.md#6-provenance-on-every-line-people-over-machines)) unless `--held-back` applies.
- **Grouped by unique English.** Lines whose English is identical after the token mapping become one row, `{"ref", "kind", "en", "targets": [[id, field], …]}`, so each text is drafted once and fans out to every target at `expand`. Quest `progress` / `completion` rows also carry `"items"`: the item names found in the quest's objectives, so the drafter can tell which lower-case words are items. Rows of the slot kinds (tooltips and the three quest kinds) carry `"slots"` (the `$N<k>` range) and, when the English prints any, `"durations"` (the `$D<k>` range). `quest_title`, `objective` and `area` rows carry `"names"`: the words the Japanese must keep in English letters. Book rows are grouped by the English hash (the addon's key for a page, [ADR-022](../adr/022-book-and-trainer-greeting-surfaces.md)). The same store always gives a byte-identical batch.
- **Token mapping** (the English as the drafter sees it): `$N`/`$n` → `{name}`, `$C`/`$c` → `{class}`, `$R`/`$r` → `{race}` (the tokens the addon fills in); a run of `$B` → a blank line; space runs collapsed. `$G<male>:<female>;` stays literal, and the drafter writes one gender-neutral wording instead.
- **Style version.** Bumping the guide's `version:` does not re-queue lines drafted under an older version. `cut --redraft-older` selects them again, including `trusted` machine lines. A redraft under a new name is imported as a second machine variant; when both pass the rules, the variant covering more English paragraphs wins, then the higher style version (`-sg<N>`), then the newer `imported` date. Two drafts of the same version imported the same day under different names tie, and the line becomes a duplicate conflict until a ruling picks one ([Local setup → Ruling on conflicts](local-setup.md#ruling-on-conflicts)).
- **Fix a drafted line in place.** `cut --ids FILE --redraft` selects the listed lines, and only those, even when they already have a machine draft (never a line with a hand-written variant). A book page brings every page with the same English hash along, because the addon shows those pages one Japanese. Import the redraft under the same draft name as the line's current machine variant, so the import replaces that variant instead of adding a second one.

## Steps

1. **Cut the batch** (from `pipeline/`):
   ```sh
   python3 -m wfj.dev.translate_batch cut --kind progress --size 100 --out batches/progress-01.jsonl
   # --ids FILE            one id per line, `#` comments (integers for quest and book, 16-hex keys for gossip)
   # --redraft-older       also lines whose drafts are all from an older style version
   # --ids FILE --redraft  the listed lines even when drafted: fix them in place, same draft name
   # --held-back           also the lines whose hand-written variants are all ruled reject (below)
   # --src PREFIX          only English from one source, e.g. db2@1.60.1.70170
   ```
   It prints `in scope (<kind>, sg<N>): L lines · U unique · C English chars` (everything still to draft) and the same for the batch. With `--ids`, a further line lists the ids it could not take and why (a hand-written variant without `--held-back`, no English, or no prose); nothing listed is dropped silently. A slot kind may also print `left out (<kind>): N rows whose value count the template cannot give`.
2. **Draft.** Give the drafting model the style guide, the glossary and the batch file, with the [drafting prompt](#drafting-prompt). It writes `batches/<batch>.draft.jsonl`. For a quest, gossip, UI or plain-text book batch it also writes the lines' `words` ([Readings for a batch](#readings-for-a-batch)).
3. **Lint** the draft:
   ```sh
   python3 -m wfj.dev.translate_lint batches/progress-01.jsonl batches/progress-01.draft.jsonl
   ```
   Each failing row prints as `<ref>: <reason>; <reason>` ([Lint reasons](#lint-reasons)), then any `warn <ref>: no words; its readings are still owed`, then `lint: N ok · M failed · K without words → <draft stem>.ok.jsonl` (exit 1 when a row failed). The passing rows are always written to `<batch>.draft.ok.jsonl`. Have the model redraft the failing refs once, in the same draft file, and lint again; rows that still fail are left out. A left-out line gets no machine variant, so a later batch can take it.
4. **Expand** the passing rows into import files:
   ```sh
   python3 -m wfj.dev.translate_batch expand batches/progress-01.draft.ok.jsonl --name progress-sg11 --out batches
   ```
   It writes one `{id, field, ja}` row per target into `<name>.quest.jsonl`, `.item.jsonl`, `.spell.jsonl`, `.gossip.jsonl`, `.book.jsonl`, `.objective.jsonl` or `.area.jsonl`, and `<name>.words.jsonl` when rows carried `words`. The name must end in `-sg<N>` for the current style version and may use lower-case letters, digits and `-` (31 characters at most). Later batches of the same kind can reuse a name, but the file is overwritten, so import it before expanding the next batch.
5. **Import and rebuild** (repository root):
   ```sh
   make import-draft DRAFT=pipeline/batches/progress-sg11.quest.jsonl TYPE=quest NAME=progress-sg11 MODEL=<model id> DATE=<YYYY-MM-DD>
   make check
   make generate
   make validate
   ```
   `TYPE` is `quest`, `gossip`, `book`, `objective`, `area`, `item` or `spell`. The import refuses a name whose `-sg<N>` is not the style guide's current version, and refuses to run without a style guide. It prints `added · unchanged · replaced · appended`. Provenance becomes `{class: machine, model, source: draft-<name>@<date>, imported}`. Pass `CRITIC=<model id>` only when a second model actually reviewed the draft.
6. **Import the readings**, when the batch wrote `words` ([Readings for a batch](#readings-for-a-batch)), then `make generate` and `make validate` again.
7. **Coverage.** `make coverage` rewrites [Coverage](coverage.md); a test fails while the committed file is out of date.
8. **Voice.** The import already remade the voice of the changed lines ([Voice for a batch](#voice-for-a-batch)); commit the audio record and the pin with the batch.
8. **Look in the game.** Copy the addon into the Forever client's `Interface/AddOns/WoWForeverJapanese/` and read the lines ([Testing strategy](../testing/strategy.md)).
9. **The pull request** states, under its Data table:
   - lines added / changed / removed by provenance class (`human` / `correction` / `machine`), and that no hand-written line was overwritten by machine output;
   - that the generated Lua was regenerated in the same PR, never hand-patched;
   - that `make validate VALIDATE_FLAGS="--base origin/main"` passes (the human-never-overwritten check).

## Held-back lines (`--held-back`)

Some lines carry hand-written Japanese that ships nothing, or ships something wrong. By default a machine draft never touches a line with a hand-written variant. `--held-back` lets `cut` take a line when **every** hand-written variant on it carries a `reject` ruling. The ruling is a logged human decision in the [ADR-012](../adr/012-human-decisions-survive-regeneration.md) shape (`ruling: {ruling: reject, by, date, note}`); it is carried across `make data`, and the rejected text stays in `conflicts`. `--held-back` takes `completion`, the three quest client kinds and the three tooltip kinds (`HELD_BACK_KINDS`).

The cases that have been ruled so far, each with its tool:

| Case | What is wrong | How the ruling is written |
|---|---|---|
| Hand-written completion text rejected by the rules | Every hand-written variant fails (`truncated`, `alignment_failed`, `numbers_changed`, `duplicate_conflict`, `not_japanese`), so the addon shows English | `python3 -m wfj.dev.rule_held_back --date <YYYY-MM-DD> [--apply]` |
| Truncated quest descriptions and objectives | The older predecessor layer kept only the first paragraph ([ADR-011](../adr/011-provenance-layers-and-completeness.md)). The model translates the whole line; it never splices onto the hand-written first paragraph, which would mix two translators' voices ([ADR-023](../adr/023-server-only-text-drafted-in-measured-batches.md)) | `rule_held_back --field description` or `--field objectives`; only lines with a `truncated` reason are selected |
| Tooltip lines with a baked number | A hand-written tooltip holds a number the template cannot produce (`18秒間でhealthを61回復。` for `Restores $o1 health over $d.`): right for one rank, refused by the in-game check on the next | `python3 -m wfj.dev.rule_baked_numbers --date <YYYY-MM-DD> [--field description] [--match REGEX] [--apply]` |
| Tooltip lines that name a duration's unit | `$N3秒間`, `18秒`: wrong whenever the client prints minutes, and invisible to the in-game check | `rule_baked_numbers --durations` |
| Lines found wrong by review | Values on the wrong words, another quest's text, garbled Japanese | A reviewer's decision list applied with `dev/apply_review` (below) |

`rule_held_back` and `rule_baked_numbers` print a count and three real examples without `--apply`. `--date` is required: it is the date of the ruling on this set of lines. A line whose hand-written text already carries a ruling is skipped and reported, so an earlier decision is never overwritten. Writing rulings changes no status: run `make check` afterwards and expect `git status` to show only the `ruling` keys.

Then cut with the flag, adding `--ids` to limit the batch to the ruled lines:
```sh
python3 -m wfj.dev.translate_batch cut --kind quest_description --size 100 --held-back --ids batches/ruled.ids --out batches/held-01.jsonl
```

Draft, lint, expand and import as usual. At `check` the machine draft wins because no unruled hand-written variant is left. **Replacing a line that shipped** also needs `ruling: accept` on the machine winner; `validate --base` enforces it. `rule_baked_numbers --accept [--apply]` writes it for the baked-number lines once the redraft has landed (`make check` first, so the winner is known). The data PR states the change as `human` → `machine` on the ruling, with 0 shipping hand-written lines touched otherwise.

A line whose English branches in words (Tiger's Fury: "Requires Cat Form" turns white or red by form) cannot be drafted as one Japanese text, and a ruling there ships the English.

## Reviewing hand-written lines

The rules catch a changed number, a missing name, a cut-off paragraph, never a wrong meaning. A review reads shipped hand-written lines against their English and decides each one. The shipped hand-written quest, item and spell lines with English have all been read this way once.

### The audit of the hand-written lines

1. **Cut** the lines to read, in parts:
   ```sh
   python -m wfj.dev.audit_batch cut --type quest --size 250 --out-dir batches/audit --prefix q [--words <existing .words.jsonl>]
   ```
   It takes every shipped line (`trusted` / `stale` / `unaligned`) whose winner is hand-written and that has English, as `{type, id, field, class, ja, ja_hash, en}` rows. An item or spell English that includes another spell's text carries that text in `included`, so the line is judged whole. `--words` reuses a word list already written for the same Japanese.
2. **Read.** A reviewing model writes `<part>.verdicts.jsonl`, one row per part row, in order, and checks it with `python -m wfj.dev.audit_batch check batches/audit/<part>.jsonl`:

   | verdict | when | the row carries |
   |---|---|---|
   | **match** | the Japanese says what the English says (a free rendering is fine) | quest: `words` for that Japanese |
   | **correct** | a small defect (a typo, a wrong particle or kanji, a mangled or translated name, a wrong number), fixed by the smallest edit to the translator's text | `kind`, `problem`, the corrected `ja`; quest: `words` for it |
   | **redraft** | the meaning is wrong, garbled, another quest's text, or cut off | `kind`, `problem`; no `ja`, no `words` |

   Names stay English: a translated name is a `correct`.
3. **Report.** `python -m wfj.dev.audit_batch report batches/audit --out <report.md>` checks every part (a missing, extra, duplicate or re-ordered row, a changed `ja_hash`, an unknown verdict, a `correct` with no new `ja`, words missing or refused) and, with no problem, writes `audit.decisions.jsonl` (the `correct` / `redraft` rows), `audit.words.jsonl` (the `match` rows' words) and `audit.correct-words.jsonl`. With any problem it writes nothing. `--partial` gives a progress view over finished parts. Nothing in `data/` is written.
4. **Approval.** Nothing is applied until the maintainer approves the decision list. Machine output never replaces a human translation without a logged decision ([Principles §6](../architecture/principles.md#6-provenance-on-every-line-people-over-machines)).
5. **Apply**, dry run first, then `make check`:
   ```sh
   python -m wfj.dev.apply_review batches/audit/audit.decisions.jsonl --scope audit --date <YYYY-MM-DD> --by maintainer --model <model id> --dry-run
   python -m wfj.dev.apply_review batches/audit/audit.decisions.jsonl --scope audit --date <YYYY-MM-DD> --by maintainer --model <model id>
   make check
   ```
   A `correct` becomes a `correction` variant (`translator` = the corrected variant's translator, `source: correction@<date>`, `corrects` = its source, a note saying the model drafted the edit and the maintainer ruled it); an earlier correction on the line is ruled `reject` as superseded. A `redraft` puts `ruling: reject` on every hand-written variant of the line, so it ships nothing until the redraft lands.
6. **Word lists.** `wfj readings import` of `audit.words.jsonl`, and, once the corrections are applied and generated, `audit.correct-words.jsonl`, dry run first each time.
7. **Redrafts.** Cut the ruled lines per kind with `--held-back --ids`, draft (quest rows with `words`), lint, expand, import.
8. **Accept rulings** on each machine winner that replaced a shipping hand-written line; `validate --base` requires them.

`apply_review` has three more scopes. `--scope stale` (the default) reviews stale hand-written lines after a client build moved their English: `keep` re-stamps the English baseline and leaves the Japanese alone; `correct` edits the person's Japanese as little as the new English needs, never retranslating it. `--scope templates` rewrites a hand-written tooltip line with `$N` / `$D` / `$I` placeholders (and the branch skeleton where the English has one) as a correction. `--scope stat-words` takes the rows `draft_stat_words --corrections` writes (below).

## Included text and branches

Some tooltip English includes another spell's text (`$@spelldesc<id>`, `$@spelltooltip<id>`, `$@spellname<id>`, `$@spellicon<id>`) or branches on a condition (`$?<cond>[A][B]`) ([ADR-043](../adr/043-included-text-icons-and-branch-variants.md); the style guide's **Included text and inline icons** and **Branches** sections).

- **Cut** splices each included spell's English into the row's `en`, so the drafter translates the line the client shows. It writes `$I<k>` where an inline icon goes (the row carries `"icons"`) and keeps a branch row with `"branches"` (its variant count) and the whole-template `"slots"` / `"durations"`. Every line it cannot take is written with its reason to `<batch>.dropped.jsonl`: `missing_included_spell:<id>`, `unsupported_code:<code>` (`$@auracaster`, `$@spellaura`, `$@null`), `inclusion_cycle:<id>`, `inclusion_depth` (a chain deeper than four), `too_many_variants` (more than 16), `unclosed_branch`, `branch_slots_unclear`, `branches_indistinguishable` or `uncountable`.
- **Draft** with no `words` (tooltips take no readings), then have a second model read a random 100 lines against the English before import.
- **Lint** checks a branch row per variant and an icon row for its `$I<k>`.

A lint pass does not prove the addon will show a branch line: it shows a variant only when exactly one variant passes on the live line (`Align.checkVariants`). A variant that another variant also passes on its line shows English there; it still ships, because dropping it would let the other variant pass alone on the wrong line. Inline icons rest on an unverified claim (that `$@spellicon` prints as a `|T…|t` escape in the tooltip line), so until the in-game check in [Testing](../testing/strategy.md) passes, an icon line may show English; it never shows wrong text.

## Re-verifying reworded lines (`REVERIFY=1`)

When a client build rewords a string, `make check` marks its line `stale` (the English moved) or `rejected` (for UI, `specifiers_changed` / `markup_changed`; for a quest, `numbers_changed`). Stale is sticky: the line keeps the English hash it was checked against ([ADR-003](../adr/003-ship-stale-with-marker.md)), and a machine variant records no hash of its own, so a redraft alone does not clear it. `REVERIFY=1` takes `TYPE=ui`, `quest`, `objective`, `area`, `item` and `spell`. Gossip is keyed by its English hash, so a reworded greeting is a new key; book pages do not move with a client build.

- **Quest, objective, area, item and spell lines** are cut and drafted from the current English (`cut --ids <file> --redraft`), then imported with `REVERIFY=1` added, then `make check`.
- **UI lines** are not cut: write `{"id", "field": "text", "ja"}` rows against the current English in `data/english/ui`. If the Japanese still fits (only punctuation or casing changed), keep it unchanged in the draft; otherwise write a new one. Keep one Japanese per shared English.
   ```sh
   make import-draft DRAFT=pipeline/batches/<batch>.ui.jsonl TYPE=ui NAME=<draft name> MODEL=<model id> DATE=<YYYY-MM-DD> REVERIFY=1
   make check && make generate && make validate VALIDATE_FLAGS="--base origin/main"
   ```

`--reverify` records on every line the draft names exactly the baseline a fresh `make check` would record for the current English, because the draft was written against it. A redraft whose Japanese equals a variant the line already holds imports as `unchanged`: that older variant keeps its own date and can still lose the machine-versus-machine tiebreak to the stale winner, which then ships re-stamped. Check the winner after `make check`; if the stale text still wins, rule it `reject` (a ruling on the variant, as for a hand-written line) and check again. The summary ends `re-verified N`. It refuses, writing nothing, a row with no English, a line with a hand-written variant not ruled `reject` (that needs a ruling first), and a row whose Japanese loses to a variant ruled `accept` (move the ruling to the redraft first). `make test-py` includes a test that fails while any shipped UI line is mismatched or ambiguous against Forever's English.

## Scripted redraft (a word swap)

When a style rule changes only which word the Japanese uses (a stat word in tooltips: `health` → 体力), the lines already drafted are not sent back to a model. A tool swaps the words, and each line keeps the model that wrote the rest of it. The stat-word tool is `dev/draft_stat_words.py` ([ADR-048](../adr/048-stat-words-in-tooltips.md)). It takes every shipped machine item and spell line that keeps a stat word in English letters on its own.

1. **Draft** (from `pipeline/`):
   ```sh
   python -m wfj.dev.draft_stat_words ../batches/<folder> --tag <model id>=<tag> [--tag …] [--skip <file>]
   ```
   `--tag` gives each drafting model a short tag for its file and draft name. It writes one draft file per drafting model and type (`<tag>.item.jsonl`, `<tag>.spell.jsonl`), `contexts.txt` (every distinct stretch of text around a swapped word, with its count) and `lint.txt` (lines where the swap brought a lint problem the old line did not have; exit 1 when there is one). It stops if a line's model has no draft tag, or if a row differs from its line by more than the swapped words.
2. **Read `contexts.txt`** for a stat word that is really part of a name. List any such line in the skip file (`<type> <id> <field>` per line, `#` comments) and run step 1 again.
3. **Read `lint.txt`.** Review each new problem by hand. Keep the swap only when the Japanese is right (a new `name_missing:Mana` on `マナコスト` for "Mana cost" is right).
4. **Import each file under its own model**, one draft name per model, ending in the current style version (repository root):
   ```sh
   make import-draft DRAFT=batches/<folder>/<tag>.item.jsonl TYPE=item NAME=stat-words-<tag>-sg<N> MODEL=<model id> DATE=<YYYY-MM-DD>
   ```
   The old variants stay in `conflicts`. The new ones win on the style-version tiebreak.
5. **Move the accept rulings.** A machine line the maintainer accepted in place of rejected hand-written text keeps winning over its redraft, because an accept beats every tiebreak. This moves each accept onto the redraft of the same text. The ruling keeps who made it, its date and its reason, and its note adds the move (the hand-written variants stay ruled `reject`):
   ```sh
   cd pipeline && python -m wfj.dev.draft_stat_words --move-accepts <YYYY-MM-DD>
   ```
6. **Hand-written lines, on the maintainer's ruling.** The swap never touches a `human` or `correction` line. When the maintainer rules that the settled words apply to them too, write one correction row per shipped hand-written line that keeps a stat word (or ヘルス), read `corrections.contexts.txt` the same way, and apply them (the translator's text stays beside each correction; an earlier correction is ruled superseded):
   ```sh
   cd pipeline && python -m wfj.dev.draft_stat_words --corrections ../batches/<folder>/corrections.jsonl [--skip <file>]
   python -m wfj.dev.apply_review ../batches/<folder>/corrections.jsonl --scope stat-words --date <YYYY-MM-DD> --by maintainer --model "the stat-word script"
   ```
7. **Check**: `make check`, `make generate`, `make validate VALIDATE_FLAGS="--base origin/main"`, `make coverage`. No line should change status, and no translator's text should be lost. `test_style_guide.py` fails while any shipped tooltip line keeps a stat word in English letters.

## Drafting prompt

```text
Translate a batch of World of Warcraft text into Japanese.

Read, in this order:
- docs/content/translation-style-guide.md  (the rules and examples; follow them exactly)
- pipeline/translation_glossary.tsv       (recurring words and their Japanese)
- pipeline/batches/<batch>.jsonl          (the rows: {"ref", "kind", "en", "targets"}; quest rows also "items", the quest's objective item names; tooltip and quest title / objectives / description rows also "slots" (write $N1..$N<slots> for the values the game fills in, never the number) and, when present, "durations" (write $D1..$D<durations> for each duration, never a unit); quest_title, objective and area rows also "names", which stay in English letters; book rows are one page each, HTML pages keep every tag)

Task: translate every row's "en" per the style guide and the glossary.
Write pipeline/batches/<batch>.draft.jsonl: one JSON object per line, {"ref": "<the row's ref>", "ja": "<Japanese>"}.
Every ref exactly once. Nothing else in the file. Do not print the translations back; reply only with the row count written.
```

For a quest, gossip, UI or plain-text book batch, add the word-list rules ([Readings for a batch](#readings-for-a-batch)) and ask for `{"ref", "ja", "words"}` rows. For a redraft after lint, give the failing refs with their reasons and ask for only those rows to be replaced in the same draft file.

## Lint reasons

A draft row fails with one reason per problem (`translate_lint.py`; the name rules are in `lint_names.py`, the glossary reader in `glossary.py`):

- `missing` / `duplicate` / `unknown_ref`: the draft does not cover the batch one to one.
- `not_japanese`: no kana or kanji, or a simplified-only character. An English line that is only dots (`...`) may stay only dots (`……`).
- `tokens:<english>→<japanese>`: the `{name}` / `{class}` / `{race}` tokens differ in kind or count.
- `leftover:<token>`: a `$` code, an unknown `{word}` or any `<a/b>` pair (drafts are gender-neutral).
- `paragraphs:<ja>/<en>`: a different number of paragraphs.
- `alignment_failed:<word>`: a Latin word in the Japanese that the English does not have. The words of a `$G<male>:<female>;` code do not count as English: the draft writes one neutral form (`閣下`, `お前`), so `Sir` kept in the Japanese fails.
- `numbers_changed:<n>`: a number in the Japanese that the English does not have.
- `name_missing:<word>`: a capitalised word inside an English sentence (a name) that the Japanese does not keep in English letters. Glossary terms (titles and common nouns such as `the Captain`, races, classes), their plurals and hyphenated words led by one are translated, except directly before a capitalised name (`Captain Althea`, `King Magni`) or directly after one (`Dark Lady`, `Lion's Pride Inn`), where the title is part of the name. A profession name (`Skinning`) stays in English letters but does not make the title after it a name: `Skinning Trainer` → `Skinningのトレーナー`. A place or group word (`Temple`, `Bank`, `Council`, `Brotherhood`, …: `PLACES` in `lint_names.py`) joined to a capitalised word by `of` / `of the` makes one name (`Temple of the Moon`); a person title with `of` stays translatable (`the King of Stormwind` → `Stormwindの王`). A word after a quote, a dash, `<`, `>`, `)` or a line break starts a sentence and is not read as a name, unless it is a glossary word or a profession. A capitalised common noun used for emphasis (`for the Love of the Light`) cannot be told from a name: the row fails and ships English unless the word is reviewed onto the [not-names list](#not-names-list). Do not keep the word in English letters just to pass.
- `name_missing:<word>` on a title-case row: a word from the row's `names` that the Japanese does not keep in English letters. It also covers a glossary title word directly before a listed name (`Baron Aquanis`): `男爵Aquanis` fails `name_missing:Baron`. The title used on its own ("The Baron's Demise" → `男爵の最期`) is still translated.
- `markup_changed:<difference>`: an HTML book page whose Japanese does not carry the English's tags, with their attributes, in the same order.
- `stat_word:<word>`: on an item or spell row, a stat word (`health`, `Stamina`, …) kept in English letters on its own, or another spelling (`ヘルス`). Tooltips use the interface's Japanese (体力, スタミナ, …; the style guide's settled interface terms, `core/stat_words.py`). A stat word inside a name (`Mana Shield`, `Elixir of Agility`) is not read. On these rows a stat word the English uses on its own (`Increases Stamina by $s1`) is no name to keep, while one inside a name in the English still is.
- `slash:<a>/<b>`: a `/` between two Japanese words (`師匠/主人`): two renderings where one must be chosen.
- `counters:<english>→<japanese>`: the server counters (`$1997w`) differ.
- `placeholder_run:<text>`: a `$N<k>`, `$D<k>` or `$I<k>` with letters glued to its end (`$N1c1`).
- `value_index:<k>><slots>` / `duration_index:<k>><n>`: a `$N<k>` or `$D<k>` past the row's count.
- `slot_missing:N<k>`: the k-th value comes from a code the client fills in (`$s1`, `$1oa`, `${…}`) and the Japanese has no `$N<k>` for it.
- `duration_as_value:N<k>`: `$N<k>` on a duration (a bare number whose unit the Japanese would have to name).
- `duration_missing:D<j>`: a duration whose `$D<j>` is absent.
- `icon_missing:<k>` / `icon_index:<k>`: an inline icon `$I<k>` of the English is absent from the Japanese, or the Japanese has one the English does not (or writes it twice).
- Branch rows: `branch_skeleton` (the Japanese does not keep the English's `$?<cond>[…][…]` conditionals), `branch_index:<N|D><k>` (a placeholder in a branch that does not print that value), `v<i>:<reason>` (variant i fails a reason above against its own English), `branches_indistinguishable` (no variant could ever show).
- `speaker:<english>→<japanese>`: on NPC speech, the count of `%s` (the speaker's name, filled in by the client) differs, or the Japanese carries a `%` the English does not.
- `words:<problem>` / `words_unexpected`: the row's `words` fail the readings import's rules, or `words` sit on a kind that takes no readings.
- `glossary:<term>`: the English has a `required` glossary term (a race or class word) and the Japanese neither uses the glossary's rendering nor keeps the word in English letters as part of a name (`Murloc Warrior`).

## Not-names list

`pipeline/translation_not_names.tsv`. Book headings, letter greetings and title-case lines capitalise ordinary words (`An Overdue Package`), which `name_missing` reads as names. The list exempts a word on one batch row only:
```text
<ref>\t<word>\t<the English around it, for the reader>
0465fa9e36	Package	An Overdue Package -
```
The ref is the batch row's ref (the first 10 hex of the hash of the English as the drafter sees it), so an entry holds only while that English does. `#` lines are comments; a malformed line stops the lint.

How entries are made: after a lint pass, a reviewing model classifies each flagged word as a name or not, and when in doubt, a name, so the line ships English ([Principles §2](../architecture/principles.md#2-names-stay-in-english)). Only words classified as not a name are listed, one row and word at a time; then the failing rows are redrafted once and linted again. A word that recurs on many rows belongs in the glossary instead.

An entry whose word is a `required` glossary term, listed exactly as the lower-case term, also exempts that term from `glossary:<term>` on that row, for a word used in another sense ("a rogue apothecary" is a renegade, not the class). When in doubt, the class word.

## UI dictionary batches

Interface strings (`ui` type) are not a `cut` kind. The keys come from the curated `pipeline/ui_keys.txt`, their English from `make import-english`, and the draft is `{id, field, ja}` rows imported with `make import-draft TYPE=ui` ([ADR-014](../adr/014-machine-drafted-text-and-ui-dictionary.md)). How the Japanese should read (meaning in context, length, register, consistency, format, names) is the style guide's [Interface text](../content/translation-style-guide.md#interface-text-ui-strings) section; give it to the drafting model. Rules for a UI draft:
- one model per draft batch (a test lists each UI draft source and checks it);
- keep every format specifier (`%s`, `%d`, positional `%1$s` when the word order moves), colour code, `|A` atlas, `|cn` named colour and line break;
- one English, one Japanese: a key whose English another key already ships takes that Japanese, unless the key owns its Japanese on one screen (`UIStrings.OWN`, [ADR-037](../adr/037-staticpopup-dialogs-and-owned-keys.md));
- a word in a restricted family (a barber shop option, an auction category) gets the Japanese it means on its own screen;
- no human line is replaced.

Before the import, check the draft with `ui_lint` (from `pipeline/`):

```sh
python -m wfj.dev.ui_lint batches/<batch>.ui.jsonl
```

It fails a row whose key has no English, a key drafted twice, a line that is not Japanese, a line whose specifiers or markup differ from the English, and a key that would ship a different Japanese from another key the addon finds by the same English (`ambiguous:`; the rules `make check` and `make validate` apply, run early so the row is fixed in the draft). On a short label it also warns `too_wide:<width>/<limit>` and `register:<ending>`; a warning does not fail, it asks for a second look against the style guide. `python -m wfj.dev.ui_lint --shipped` runs the same checks over every shipped UI line.

**Reviewing UI lines.** To read the shipped interface text against the style guide (a quality pass, not a redraft):

1. `python -m wfj.dev.audit_batch cut --type ui --size 400 --out-dir batches/<dir> --prefix u` writes one row per (English, Japanese) pair with its keys, windows, widths, `ui_lint` warnings and `siblings`.
2. A reviewing model writes `<part>.verdicts.jsonl` per part (`match`, `correct`, `redraft`, `split`; `context` `screen` or `key`) and checks it with `audit_batch check`. Run one part first and read its corrections before the rest.
3. `audit_batch report batches/<dir> --out <report>` writes `audit.ui-draft.jsonl`, `audit.ui-base.jsonl`, `audit.ui-redraft.ids` and `audit.ui-split.jsonl`. Settle any term the parts spelled two ways (the style guide's settled-terms table), bring every line to it, and draft the redraft keys into the same batch.
4. A split key needs `UIStrings.OWN` and a widget that asks for it by name ([ADR-037](../adr/037-staticpopup-dialogs-and-owned-keys.md)) before its Japanese can differ.
5. `ui_lint` the batch with `--base batches/<dir>/audit.ui-base.jsonl` (it fails a key changed since the cut), `make import-draft … TYPE=ui REVERIFY=1`, `make check generate validate`, then the changed lines' word lists (below) and `make coverage`.

Counts from the first full pass: [the interface text audit](../research/2026-09-30-ui-string-audit.md).

## NPC speech

NPC speech (says, yells, whispers, emotes and boss emotes) is gossip-kind text keyed by the hash of its English ([ADR-035](../adr/035-ui-errors-frame-surface.md)). It is cut, drafted, linted and imported like any gossip batch, following the style guide's NPC speech section: keep every `%s` (the speaker's name) and no other `%`.

## Readings for a batch

Every batch that adds or changes shipped quest, gossip, UI or plain-text book Japanese also writes those lines' word lists with meanings: the word card a player sees when pointing at a word ([Readings](../systems/readings.md), [ADR-036](../adr/036-readings-hover-word-lists.md), [ADR-039](../adr/039-word-meanings-written-in-context.md), [ADR-041](../adr/041-word-cards-on-window-labels.md), [ADR-044](../adr/044-area-text-and-book-word-cards.md)). Item, spell, objective and area text take none, and neither does an HTML book page (it keeps the client's layout).

**The entry.** Each word is a 5-item entry: `[word as written, its reading, dictionary form, reading of the dictionary form, meaning in this sentence]`. A word is the whole inflected unit; kana words that carry meaning are listed too; names are English and get nothing; no ASCII in a word; a kanji numeral and its counter are one word; a `$N<k>` inside a name is a placeholder. The meaning uses the game's own word where the Japanese translates it (倒して for "Kill …" → "kill (defeat)"), but never repeats the whole English line of two or more words ([Principles §4](../architecture/principles.md#4-the-addon-never-ships-stored-english)); a test checks this across the store. The import still accepts a 2-item entry (word, reading); `validate` then counts a word without a meaning.

**Something to annotate.** A line needs a word list when its Japanese holds a kanji, or kana beyond a bare particle or copula (は が を に で と の へ も や か よ ね な から まで だ です ー; `readings.annotatable`). A line holding a `|` escape (a colour code, `|n`) takes none; the reading box refuses such text.

**Readings in the draft row** (the default). The drafting model writes `words` beside `ja`: `{"ref", "ja", "words": [["少し", "すこし", "少し", "すこし", "a little"], …]}`.

1. **Lint** checks the `words` with the import's own rules: `words:<problem>` (a word not found after the previous one, no kanji, an ASCII character, a non-kana reading) and `words_unexpected` fail the row. A row with something to annotate and no `words` passes with a warning. `"words": []` on a row with nothing to annotate counts as no `words`.
2. **Expand** also writes `<name>.words.jsonl`, one `{type, id, field, ja_hash, words}` row per target.
3. **Import the lines first** (`make import-draft`, `make check`, `make generate`): readings are pinned to the Japanese as it ships.
4. **Import the readings.** `wfj readings import batches/<name>.words.jsonl --model <model id> --batch <name> --dry-run` lists every rejected row with its reason (for example `written for Japanese that has since changed; export it again`, or `written for a variant that does not ship`, when a hand-written line still wins). Fix the rows, then run it without `--dry-run`. A `correction` reading is never replaced.
5. **Generate and validate.** `make validate` checks every reading, prints stale ones, the lines still owed one (`validate: readings: N <type> lines with words to annotate have none: …`) and, per type, the words without a meaning.

**The meaning numbers file.** `make generate` gives each new meaning the next free number and appends it to `data/reading/meaning-numbers.tsv` (`generate: N meanings numbered for the first time`). Commit that file with the batch, beside the generated Lua. A meaning keeps its number, so a batch changes only the Reading files that use its words and the last Gloss file ([ADR-060](../adr/060-stable-meaning-numbers.md)). `make validate` fails when the file is missing or is not what `generate` would write; run `make generate`, never edit it by hand.

**Lines that got Japanese without words** (a line whose Japanese changed, a row lint warned about) take a separate flow after the lines are imported and generated:

1. **Ids**: one per line (quest ids, 16-hex gossip keys, UI string keys, or book page ids).
2. **Export**: `wfj readings export --type quest|gossip|ui|book --ids <file> --out <file>`, one row `{type, id, field, ja, ja_hash, en}` per shipped line with something to annotate and no current reading (a line holding a `|` escape is left out: it takes no readings). `--all` takes every such line; `--class machine|human|correction` keeps only lines whose shipped variant has that class. `en` is batch input only: the import ignores it and it is never stored or shipped.
3. **Words**: the model adds 5-item `words` to each row, keeping `ja_hash`, and saves `<name>.words.jsonl`.
4. **Import, generate, validate** as above. For a large pass, have a second model check a random 100 words per round against a pass bar before importing.

**Fixing a wrong reading: `--correction`.** Write the line's whole fixed `words` list with its current `ja_hash` and import it as a correction:
```sh
wfj readings import batches/fixes/<name>.words.jsonl --correction --by <who wrote the fix> --date YYYY-MM-DD [--note "<what was fixed>"] --dry-run
```
Each row becomes a `correction` record (`translator` = `--by`, source `correction@<date>`, `corrects` = the record it replaces). A line with no reading yet is rejected (`no reading to correct`) and takes the normal import. A later machine import never replaces a correction; a translation change still makes it stale.

**A translation change makes its reading stale.** `validate` prints it and `generate` stops shipping it; export the line again and re-import.

### Resolving a readings merge conflict

Two branches that both import readings conflict only in generated or reading files: `data/reading/*.jsonl`, `data/reading/meaning-numbers.tsv` (both branches added meanings at its end), the addon's `Data/Reading/*.lua` and `Data/Gloss/*.lua` (most often the last Gloss file), `Data/Meta.lua` and the TOC's generated block. Never hand-merge them:

1. Take `origin/main`'s side of those files.
2. Re-run `wfj readings import` on this branch's `.words.jsonl` files. A row written for Japanese that has since changed, or for a variant that does not ship, is rejected: export that line again and write its words anew.
3. `make generate`, then `make validate`. `generate` numbers this branch's new meanings after main's, so they take new numbers.

## Voice for a batch

Every batch that changes shipped Japanese the voice reads (quest offers, progress and turn-ins, greetings, gossip, plain-text book pages) also remakes that audio, the way it writes readings ([Voice over](voice.md), ADR-062). `make import-draft` ends with `make check` and `make voice-generate`: it makes exactly the files whose Japanese changed or that are missing, commits and pushes them to the audio repository and writes the audio pin. Commit `data/voice/audio.jsonl` and `pipeline/voice-audio-commit.txt` with the batch. With nothing voiced in the batch (items, spells, interface text), the step makes nothing and needs no engine. With voiced lines and no engine running it stops and says how to start it; start the engine and run `make voice-generate`. `test_audio_in_step` fails a pull request whose voiced lines have no audio, or audio made from other Japanese.

## Fix-report batches

A player's fix report is a small batch of its own: `make report-intake ISSUE=N` writes the triage, a drafting model writes the decisions (the style guide and the readings rules above apply to every line it writes), and `make report-apply ISSUE=N MODEL=…` imports them. Apply runs the status rules (`check_type`: Japanese, names, numbers, tokens) on each changed line and refuses one that would not ship; `translate_lint` is not run. Runbook: [Fix reports](fix-reports.md).

## Verify

- `translate_lint` ends `lint: N ok · 0 failed`, or the failures left out are the ones listed.
- `make import-draft` prints `added` + `appended` equal to the expanded line count (`replaced` when re-importing lines under the same name).
- `make check`, `make generate` and `make validate` pass; `make stats` shows `shipped by provenance: … machine N` higher by the lines that passed `check`.
- `make validate` lists no line owed a reading from this batch.

## Rollback / troubleshooting

- **Undo an uncommitted batch:** discard the working-tree changes under `data/` and `addon/WoWForeverJapanese/` (`git restore`, and remove new files there). After a merge, revert the PR and regenerate.
- **`draft: --name must be lowercase letters, digits and dashes`**: also raised for a name over 31 characters; shorten it.
- **`draft name '…' must end in -sg<N>`**: the name's version differs from the style guide's `version:`; use the current one, or re-cut if the guide was bumped after the batch was cut.
- **`no 'version: sg<N>' line`**: the style guide lost its version line; restore it (a test guards it).
- **`ref collision`**: two different English texts share a ref prefix. Stop and report it; do not edit the batch file.
- **`cannot find data/SCHEMA`**: run the tool from inside the repository (`pipeline/`).
- **`make import-draft` refuses** (unknown type, bad name, non-integer id, duplicate or invalid row): nothing was written; fix the import file and rerun.
- **`draft: --reverify: no English for N row(s)`**: the row names an (id, field) with no English. For UI, add the key to `pipeline/ui_keys.txt` and run `make import-english` first, or drop the row.
- **`draft: --reverify: N row(s) have a hand-written variant not ruled reject`**: the line needs a ruling before a redraft can take it over, or drop the row.
- **`draft: --reverify: N row(s) lose to a variant ruled accept`**: move the `accept` ruling onto the redraft, then re-verify.
- **`--reverify is for ui, quest, objective, area, item, spell only`**: the flag was passed with another `TYPE`.

## Re-pull records

What each Forever build changed in the shipped text, measured by `make import-english` and `make check` against the
previous build, with what was drafted for it. The round's batches follow the steps above.

### 1.60.1.70170 → 1.60.1.70245 (2026-10-07)

Quest cache: 3,003 records, 2,927 quests (the WFJScan known-list scan of 15,850 ids and its slow recheck); 605
quests are answered for the first time, most of them vanilla quests already carried from Classic Era, and 12 quests
70170 answered are not answered on 70245 (they keep their English and Japanese,
[ADR-050](../adr/050-english-is-additive.md)). Client tables: 58, with the build's own hotfixes (ItemSparse 4,666
rows added; SpellName and Spell 14 replaced, 7 added, 1 removed; QuestV2 477 replaced; BroadcastText 12 added). The
wago.tools cross-check: 0 rows differ on all eight tables; ours has only the hotfix rows, and the one ItemEffect row
wago has and ours lacks (234068) is a row the hotfix cache removes. QuestV2's highest id is 99,411. The UI extract:
4,419 files; two changed from 70170 (the whisper target pattern in the chat edit box, a closure in the talent
tooltip), both in paths the addon uses (the edit box header, the talent tooltip event), neither needing a change. The served-text inventory: no column added or dropped.

| Type | Reworded (shipped line now stale) | New English lines (to draft) | Not served on this build (English kept) | Drafted |
|---|---|---|---|---|
| quest | 12 machine (4 titles, 5 objectives, 3 descriptions); 5 more machine lines rejected because a name in the English changed (Proudmore, Dragonmaws, Potion, Magus Voidglare); 4 hand-written | 120 titles, 113 objectives, 113 descriptions | 6 (the served record: it compares with every earlier build and counts a quest the build's QuestV2 still lists as served, so it differs from the 12 the cache comparison gives) | 120 titles, 113 objectives, 113 descriptions, the 17 machine lines redrafted, all with word lists; the 4 hand-written lines reviewed: 2 kept (a full stop, `WANTED:`), 2 corrected (`Incendia Powder` now capitalised) |
| item | 0 | 29 tooltips; 8 hand-written lines that start shipping because the item is served now | 12 | 29 new; of the 8 hand-written lines, 6 ruled out and redrafted (3 with numbers the template fills in, one fixed value, and 2 that named the wrong stat: parry for a shield block chance, critical strike for bonus healing), 2 (10769, 10770) held back: no tooltip English names their stat yet, so they ship nothing until a build gives it; one redraft from the 1.60.1.70170 round (7747) also got its `accept` ruling |
| spell | 0 | 0 | 108 | none |
| objective, area | 0 | 18 objectives, 5 areas | 0 | 17 objectives (one is only an item name, listed in `objective_names.txt`), 5 areas |
| gossip | 0 | 5 (a quest's other wordings and completion log lines) | 0 | 5, with word lists |
| ui | 0 | 0 | 160 keys no longer used | none |
| book | 0 | 24 pages (11 unique), left over from earlier builds | 0 | none: picture-only pages and one name-and-dates page |

Left out with a reason: two item tooltips whose template the pipeline cannot render yet (279976 `too_many_variants`,
286405 `branches_indistinguishable`), the spell templates already listed for a follow-up, and the two riding skills.
Not-names entries were added for ordinary capitalised words the name check flagged (`Attack Power`, `Neutral` as a
reputation standing, the title words `On the Lam`, `Highway Robbery`, `Sentiments`, and `rogue` for stray elementals).

### 1.60.1.70124 → 1.60.1.70170 (2026-10-02)

Quest cache: 2,406 records (the all-ids sweep, cut by a logout near the top of the range, a catch-up scan of
10,156 ids, then a slow recheck of 26 quests an earlier build answered, 3 passes at 2 s, which got 2); 24 quests an earlier build answered are not answered on 70170; they keep their English and Japanese ([ADR-050](../adr/050-english-is-additive.md)). Client tables: 31, with
the build's own hotfixes (4,496 ItemSparse rows added). The wago.tools cross-check: 0 rows differ on all eight
tables; every row count difference is a hotfix wago's export does not carry (ItemSparse 4,496, SpellName 8, Spell
16, GlobalStrings 1), and wago has no row ours lacks. The UI extract: 4,412 files, 121 changed from 70124.

| Type | Reworded (shipped line now stale) | New English lines (to draft) | Not served on this build (English kept) | Drafted |
|---|---|---|---|---|
| quest | 111 machine (87 descriptions, 23 objectives, 1 title); 14 more machine lines rejected because a name or number in the English changed | 70 titles, 63 objectives, 67 descriptions | 2 (titles of 1005, 1006, not answered on 70170) | 71 titles, 96 objectives, 154 descriptions (the 125 reworded or rejected lines redrafted), all with word lists |
| item | 255 tooltips (213 machine, 42 hand corrections) | 41 tooltips (26 flavour lines the bare-label rule used to skip) | 3 | 41 new (6 lines that are only a name ship it, ruled `accept`); 213 redrafted; 11 hand-written lines ruled out earlier redrafted; the 42 hand corrections reviewed: the buff's duration moved from `$D2` to `$D3` because the English now writes "10 sec", a duration the client reads |
| spell | 383 (324 descriptions, 58 auras machine, 1 description hand correction) | 16 descriptions, 17 auras (visible spells; 19 flavour lines) | 16 | 24 new descriptions (5 only a name), 324 redrafted; 23 new auras, 58 redrafted; the hand correction kept (a typo fix in the English) |
| objective, area | 8 objectives | 10 objectives | 0 | 10 new, 8 redrafted |
| ui | 34 machine; 2 rejected (`STAT_SPELLHEALING_TOOLTIP`, `STAT_SPELLPOWER_TOOLTIP`: the English gained line breaks) | 32 keys the 70170 windows newly use (combat text options, free bag slots, quest fading, tip of the day, group finder playstyle, stable buttons) | 1 key no longer used | 42 new keys (with the titles tab and pane keys, which the 70170 window now shows); 36 reworded keys (27 kept as they were, 9 new Japanese); word lists for every changed UI line |
| book | 0 | 24 pages (11 unique), left over from earlier builds | 0 | none: picture-only pages and one name-and-dates page |
| gossip | 0 | 0 | 0 | none |

Left out with a reason: placeholder or test quest text (four descriptions: `[PH] Collect …`, `$Tpunk;! …`), a spell
description that is only `???`, three spell descriptions whose branches differ only in prose
(`branches_indistinguishable`), and 171 tooltip lines whose template the pipeline cannot render yet (included
`$@spellaura`, `$@spelldesc` and `$@expandkey` text, an included spell this build does not have, branches that differ
only in prose, too many variants), listed for a follow-up. The two riding skills (33388, 33391) are among them: their
English lists every riding ability the character knows. Not-names entries were added for ordinary capitalised words
the name check flagged (flavour text, `Right Click`, `Maximum Health`, terrain words).

### 1.60.1.70009 → 1.60.1.70124 (2026-10-01)

| Type | Reworded | New English lines | Gone | Drafted |
|---|---|---|---|---|
| quest | 2 (5638: Laurena → Rohan) | 84 on 36 quests (22 quests new to Forever; 13 found only by the all-ids sweep) | 18 (7 `<UNUSED>` stubs the placeholder filter now drops) | 23 titles, 13 objectives, 12 descriptions; 2 redrafts; 1 hand-written line ruled and redrafted (7945) |
| item | 0 | 66 (11 tooltip texts) | 0 | 13 tooltips; 4 range rows redrafted to one slot (1447, 5631, 5633, 16252) |
| spell | 1 (1309410 aura) | 0 | 0 | the earlier variant that matches the new English promoted |
| objective, area | 0 | 3, 1 | 0 | 4 |
| ui, gossip, book, unit | 0 | 0 | 0 | none |

Left out with a reason: test or stub English (quests 1, 9065, 7682, 94559, 94901, 94902; the title markers of 93173,
94898, 97583; spell 457021), name-only text (items 14625, 278051), picture-only or name-and-dates book pages (11), and
three belt-tinker / expertise tooltips whose branches differ only by prose (1226210, 1226211, 1234040 / 1234805:
`branches_indistinguishable`). Readings and meanings were written for every drafted quest line and for the 25
holiday and reputation quest lines that started shipping on this build.

## Related

- [Pipeline → Translation batches](../systems/pipeline.md#translation-batches) · [Translation style guide](../content/translation-style-guide.md) · [Readings](../systems/readings.md) · [Fix reports](fix-reports.md) · [Coverage](coverage.md)
- [Local setup → Machine drafts](local-setup.md#machine-drafts) · [Testing strategy](../testing/strategy.md) · [Release](release.md) · [Glossary](../glossary.md)
- [ADR-014](../adr/014-machine-drafted-text-and-ui-dictionary.md) · [ADR-023](../adr/023-server-only-text-drafted-in-measured-batches.md) · [ADR-028](../adr/028-a-duration-is-copied-not-named.md) · [ADR-043](../adr/043-included-text-icons-and-branch-variants.md) · [ADR-048](../adr/048-stat-words-in-tooltips.md)
