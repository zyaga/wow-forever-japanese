# ADR-050: English for anything Forever served is never removed

- **Status:** Accepted
- **Date:** 2026-10-02
- **Amends:** [ADR-034](034-forever-is-the-only-target.md) decision 4

## Context

ADR-034 added `wfj import english served`, which runs last in every English import and prunes `data/english` to
the ids the current Forever build serves: QuestV2 or the quest cache for quests, ItemSparse and SpellName for items
and spells, the Forever tables' stamp and `ui_keys.txt` for UI keys. Its purpose was to keep Classic Era-only
content out of the addon, and the Japanese in `data/` was never touched.

Applied on every re-pull, the same rule also removed English for ids an earlier Forever build had served and the
current one did not answer. A Japanese line without English is `no_english_id` and is not generated, so working
Japanese stopped shipping. Across the re-pulls from 1.60.1.69913 to 1.60.1.70170 this happened to 373 lines
(159 UI keys, 192 spell lines, 19 item lines, 2 quest titles, 1 objective).

The evidence behind each removal was weak. The quest scan is not proof that a quest is gone: on 1.60.1.70170 the
first all-ids sweep left about 150 quests below 10,000 unanswered that a later pass answered, and a slow recheck
answered 2 more. A quest, item or key can also come back in a later build.

## Decision

1. **Additive.** The served step never removes a line for an id any Forever build has served, and never removes a
   line whose English came from Forever itself (`wdb@1.60…`, `db2@1.60…`). It still drops English that only
   another client provides for an id Forever has never served, so Classic Era-only content stays out.
2. **A record of what Forever served.** `pipeline/served/<kind>.tsv` (quest, item, spell, ui; area and objective
   follow their quest) lists every id a Forever build served, with the first and the last build that did. Each
   import adds the current build's ids and moves their last build forward. An id the current build did not serve
   keeps its line and its older last build, and the import prints how many there are. Nothing acts on that list:
   it is the record for a later cleanup, if one is ever wanted.
3. **Restored.** The 373 lines removed before this decision were restored from git history with their original
   source stamps, and the record was seeded from every Forever build's inputs and from every Forever-sourced line
   in history.
4. **A slow recheck before calling a quest unanswered.** The quest scan asks again, slowly, for every quest an
   earlier build answered and the new cache has not (three passes two seconds apart), so the record's
   "last build" reflects more than one fast attempt.

## Consequences

- A re-pull can add English but never takes away Japanese that shipped. A quest that returns shows Japanese at
  once; if its English changed, the live English check shows the stale marker instead of wrong Japanese.
- The addon carries lines for things the current build does not serve. Players never see them; the cost is a few
  hundred rows.
- `pipeline/served/` is about 2.7 MB of committed text and grows with each build's new ids.
- A real cleanup needs a decision and the record, never a side effect of an import.

## Alternatives considered

- **Keep pruning to the current build (ADR-034 as written).** Rejected: a scan miss or a build that temporarily
  drops content removes working Japanese, and the scans are not proof.
- **Never prune at all.** Rejected: Classic Era-only quests, items and spells would ship Japanese for content
  Forever does not have, which ADR-034 removed on purpose.
- **Keep removed English in a separate archive file.** Rejected: the line belongs in `data/english`, where `check`
  and `generate` already read it; a second place would need its own merge rules.
