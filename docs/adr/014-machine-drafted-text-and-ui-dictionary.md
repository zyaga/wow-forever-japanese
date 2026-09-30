# ADR-014: Machine-drafted text: traceable provenance, hand-written always wins, and a UI dictionary keyed by global-string name

- **Status:** Accepted. Implemented in `pipeline/wfj/core/model.py`, `core/status.py`, `core/decisions.py`, `core/specifiers.py`, `cmd/import_.py` (`draft`, `english wago-ui`), `cmd/validate.py` (rules 2 and 7), `core/report.py`, `io/wago.py`, `io/jsonl_store.py`, `emit/schema.py`, `emit/lua_writer.py`, `cmd/generate.py`, `pipeline/ui_keys.txt`, `data/ui/`, `data/english/ui/`. In-game verification is checklist 12.
- **Date:** 2026-09-14

## Context
The imported corpus is `human` (an imported, named translator) or `correction` (a hand fix here, ADR-012). `machine` was a valid `provenance.class`, but nothing required it to say which model wrote the text, nothing ranked it, nothing carried it across `make data`, and no importer produced it. The first plan shipped human entries only.

The goal changed to the whole game UI in Japanese, except names of things, without per-screen work. That needs machine-drafted text, under three conditions: machine provenance must be traceable for **every** text area; a hand-written replacement always wins and is recorded as hand-written; and bulk drafting runs in batches.

No human corpus exists for Blizzard's interface words (buttons, headers, tooltip structural lines such as "Binds when picked up", "Requires Level %d"). They have no game id, so the id-keyed shape of ADR-001 needs a key for them. The client ships most of them as named global strings (`ACCEPT`, `ITEM_MIN_LEVEL`); item subclass names ("Cloth", "Staff") come from the `ItemSubClass` table; and many are `format()` templates whose Japanese must take the same arguments.

## Decision
1. **Machine provenance names its model.** `{"class": "machine", "model": "<model id>", "critic": "<model id>"?, "source": "draft-<name>@<YYYY-MM-DD>", "imported": <date>}`. `validate_line` requires a non-empty `model` for `machine`, on the line and inside `conflicts`; `critic` is optional and non-empty when present; no `translator`. A critic pass (a second model reviewing the draft) is a per-batch choice, not a requirement; `critic` is recorded only when one actually ran.
2. **Hand-written ranks first.** "Hand-written" is `human` or `correction`. `status._rank` = (class: `correction` 0 · `human` 1 · `machine` 2, then paragraph coverage, then, between machine drafts, style guide version (higher first) and `imported` date (newer first), then source priority, then named translator). Extends ADR-011 §4 and ADR-012 §2.
3. **The people-over-machines guard** ([principle 6](../architecture/principles.md#6-provenance-on-every-line-people-over-machines)). A `machine` variant on a line that has a `human` or `correction` variant cannot win unless it carries `ruling: accept`, or unless every hand-written variant on the line carries `ruling: reject`. A barred variant is not a candidate at all, so a lone failing hand-written variant is rejected with its own reasons exactly as before any draft existed.
4. **Machine drafts are carried.** A draft is not reproducible from any pinned input, so `decisions.carried` lists every machine variant and `import predecessor` puts it back (as its own variant; one identical by `ja_identity` to a variant already present is counted redundant). No importer ever collapses imported text into a machine variant. It prints `carried machine drafts (kept / redundant)` when non-zero.
5. **Protection in `validate --base`.** `validate` rule 2 flags a line whose class was `human` **or** `correction` at REF and is `machine` now. `machine → correction` passes. A hand-written → machine change passes when the line carries `ruling: accept`, or when every hand-written variant on it carries `ruling: reject` (`core.decisions.hand_written_all_rejected`) **and** the line shipped nothing at REF (its REF `status` not `trusted` / `stale` / `unaligned`). A line that shipped hand-written text at REF passes only with `ruling: accept` on the machine line. Both rulings are explicit, logged decisions with a `by` and a `date`, carried across rebuilds.
6. **`wfj import draft <type> <draft.jsonl> --model M [--critic C] --date D --name N`** (`make import-draft`). Each row is exactly `{"id", "field", "ja"}`; `--name` is lowercase letters, digits and dashes. Per (id, field):
   - absent → a new `pending` line with machine provenance (**added**);
   - a variant with the same text (`ja_identity`) → **unchanged**;
   - a machine variant from the same draft name → its text and provenance **replaced** (machine replaces machine);
   - otherwise → **appended** as a conflict variant.

   A `human` / `correction` variant is never edited. A duplicate row, an invalid row, an unknown type or a non-integer id for a numeric type fails with nothing written.
7. **Replacing a machine line by hand** is the ADR-012 flow: add a `correction` variant with `corrects: "<the machine variant's source>"` (for example `draft-ui@2026-09-14`) and run `make check`. Decisions 2 and 3 make it win and keep it winning.
8. **The `ui` type.**
   - **Id:** a global-string name (`^[A-Z][A-Z0-9_]*$`), `ItemSubClass:<classID>:<subClassID>`, or `SpellItemEnchantment:<id>` (an enchantment's stat line, "+3 Fire Spell Damage", matched by fingerprint like `ItemSubClass:` rows); field `text`. `ui_keys.txt` may list a family (`ItemSubClass:1:*`, `SpellItemEnchantment:*`) that `import english wago-ui` expands ([ADR-016](016-whole-window-interface-coverage.md)).
   - **Shards:** by the key's first character, upper-cased: `data/ui/ui-A.jsonl`, `data/english/ui/ui-A.jsonl`, `Data/UI/UI_A.lua`. Upper-casing avoids case-only twins on case-insensitive filesystems.
   - **English:** `wfj import english wago-ui <GlobalStrings.csv> <ItemSubClass.csv> --keys pipeline/ui_keys.txt --build <build>`, src `wago@<build>`. Only the keys in the curated `pipeline/ui_keys.txt` are imported; a listed key absent or empty in the tables fails the import. The list is the name-policy guard: no key whose English is a name. Colour codes (`|c…|r`) and plural grammar (`|4…;`) are allowed in a key's English; `|H`, `|T`, `|A`, `|K` and `$` tokens are barred (tested).
   - **check rules:** `no_english_id`, `not_japanese`, `specifiers_changed:<detail>` (the Japanese must take exactly the English template's arguments: same count, same conversions; `%N$` positionals may reorder; `core/specifiers.py`), `markup_changed:<detail>`, otherwise `trusted`, or `stale` when the prior English hash differs. No name / number / length checks.
   - **generate:** `WFJ.Data.add("ui", { ["ACCEPT"] = { text, h1, status }, … })` and `Meta.counts.ui`.
   - **`validate` rule 7:** a shipped `ui` line's specifiers and markup match its English, captures that sit next to each other are not reordered (`adjacent_captures_reordered`, ADR-016), and no two shipped keys share one normalized English with different Japanese (the addon could not tell them apart).
9. **Machine-drafted text ships.** Machine-drafted text that passes the rules ships as `trusted`; `provenance` records who wrote it, and `wfj stats` / `check --report` print shipped lines per type by class (`human · correction · machine`).
10. **Fixed UI terminology** (later drafts follow it):
    - ソウルバウンド; 取得時にソウルバウンド / 装備時にソウルバウンド / 使用時にソウルバウンド
    - クロス / レザー / メイル / プレート; 片手 / 両手 / オフハンド (`INVTYPE_HOLDABLE` オフハンド用); トリンケット
    - スタミナ (kept over 体力, which reads as HP in Japanese games); 敏捷性 / 筋力 / 知力 / 精神
    - 怒り (kept over レイジ, for consistency with the shipped spell text); マナ / エネルギー; `FOCUS_COST*` use フォーカス
    - 即時発動 / 詠唱 N秒 / チャネリング; クールダウン; 射程 Nヤード; 触媒
    - 承諾 (`ACCEPT`; not 受注, because it also labels social and guild buttons) / 辞退 / クエスト完了 / 次へ; 耐久度; 必要レベル; 売値
    - Reputation standings: 憎悪・敵対・非友好・中立・友好・尊敬・崇敬・崇拝
    - Half-width ASCII punctuation, with `: ` after a label.
    - 毎秒マナ / 毎秒怒り … for cost-per-second lines (one label, then the number); a sign attaches to its number (`秒間ダメージ +%s`, `ダメージ +%s`); damage templates put the label before the numbers (`DAMAGE_TEMPLATE` `ダメージ %s - %s`); エンチャント (not 付呪); level ranges `%d-%d`; ユニーク装備 (Unique-Equipped, also `ITEM_UNIQUE_EQUIPPABLE` for consistency); クリティカル率 / 回避率 / 受け流し率 / ブロック率 `%.2f%%`; 装備中; 編集モード; メインメニュー; skills `<武器・職業>スキルが%s上昇。`, school damage `<属性>ダメージが最大%s増加。`; shapeshift form names (Cat, Bear, Dire Bear, Moonkin), Alliance / Horde and talent-tree names stay English.

### Held-back hand-written lines
Some hand-written lines **ship nothing**: every hand-written variant on them is rejected by the rules (for quest completions: `truncated`, `alignment_failed`, `duplicate_conflict`, `numbers_changed`, `not_japanese`), so the addon shows the live English. For such a line the model translates the whole line and replaces the rejected text. A hand-written variant that **does** ship is never touched.

- **How the decision is recorded.** The ADR-012 shape, on the text being set aside rather than on the text let in: `ruling: {ruling: reject, by: "maintainer", date: …, note: …}` on **every** hand-written variant of the line (`wfj.dev.rule_held_back`, dry-run by default). Decision 3's guard stops barring a machine variant once no unruled hand-written variant is left, and `decisions.carried` puts each ruling back on every `make data`.
- **Why not `ruling: accept` on the machine line instead.** `accept` wins outright: it would ship a draft that *fails* the checks, turning the quality gate off for every such line, and re-importing under the same name drops the ruling (see Consequences), so a re-draft would silently lose it. Recording `reject` keeps every rule in force: the draft still has to pass `check` on its own merits.
- **The batch path.** `translate_batch cut --held-back` selects a line whose hand-written variants are all ruled `reject`; without the flag selection is unchanged. Writing the rulings changes no status, reason or provenance; only the `ruling` key is added. A held-back line with no passing draft still shows the live English. The batch tooling: [ADR-023](023-server-only-text-drafted-in-measured-batches.md).

## Consequences
- Every shipped line says who wrote it. "How much is machine-drafted" is one command (`make stats`).
- A person can always take a line back from the model with a `correction`, and no later draft, rebuild or ranking change can silently undo that (decisions 2 and 3, `validate` rule 2).
- The draft importer and the carry serve every type, so a later batch for any area uses the same path. A draft line competing with a hand-written one only wins with an `accept` ruling on it, or with a `reject` ruling on every hand-written variant beside it, both written by a person. Re-importing a draft with the same name replaces that variant's text **and drops its ruling** (counted `rulings dropped`), because the ruling judged the old text. A hand-written variant ruled `reject` no longer protects the line.
- Between two machine drafts the higher style guide version (`-sg<N>` in `provenance.source`; no `-sg<N>` counts as 0) ranks first, then the newer `imported` date. A re-draft under a newer style guide, or a later batch under another name, replaces the earlier one instead of tying into `duplicate_conflict`, even when both were imported the same day.
- An edit to a machine line's `ja` that is not marked `correction` is overwritten by the next draft with the same name. Nothing detects it (the same limit ADR-012 records for imported text).
- Adding a UI key is: list it in `ui_keys.txt` (or, for an inventoried string, move it out of `ui_exclusions.txt`, ADR-015 §6), `make import-english`, draft it, `make import-draft`, `make check`. A key whose English equals another key's with different Japanese fails `validate` until the drafts agree.
- Machine text has no review-status field. Every machine line is reviewed by the `check` rules; a critic pass, a pre-import lint (`translate_lint`) and an in-game checklist are per-batch choices ([ADR-023](023-server-only-text-drafted-in-measured-batches.md)).

## Alternatives considered
- **Human text only**: no human corpus exists for interface text; the whole-UI goal would never ship.
- **`translator: "<model id>"` on a `human`-shaped provenance**: hides that a model wrote it and breaks the hand-written-wins rule; rejected.
- **A machine line may replace a human one when it passes more rules**: breaks [principle 6](../architecture/principles.md#6-provenance-on-every-line-people-over-machines) (machine output never replaces a human translation without an explicit, logged decision); a ruling is that decision.
- **Key UI strings by a hash of the English** (the gossip scheme, ADR-005): the client already names each string; a name survives an English wording change (which then shows as `stale`), a hash does not.
- **Import every GlobalStrings row** (19,624 strings): most are names, markup, or text no surface shows; the curated list keeps the name policy checkable.
- **Store drafts outside `data/`** (an overlay file): a second source of truth; `data/` is the database (ADR-006).

## Related
- [ADR-015: UI text surfaces](015-ui-text-surfaces.md) · [ADR-001: Id-keyed data with per-field provenance](001-id-keyed-data-with-per-field-provenance.md) · [ADR-006: The git repo is the database](006-git-repo-is-the-database.md) · [ADR-011: Provenance layers and completeness](011-provenance-layers-and-completeness.md) · [ADR-012: Human decisions survive regeneration](012-human-decisions-survive-regeneration.md)
- [Research: whole-UI text mechanism](../research/2026-09-14-whole-ui-text-mechanism.md)
- [Data model](../architecture/data-model.md) · [Pipeline](../systems/pipeline.md) · [Glossary](../glossary.md)
