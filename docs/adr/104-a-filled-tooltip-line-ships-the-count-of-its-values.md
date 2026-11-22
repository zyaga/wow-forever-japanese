# ADR-104: A filled tooltip line ships the count of its values

- **Status:** Accepted
- **Date:** 2026-11-21
- **Deciders:** the maintainer
- **Related:** [ADR-007](007-unaligned-ships-with-runtime-gate.md) (the names and numbers gate) · [ADR-043](043-included-text-icons-and-branch-variants.md) (branch lines and their shapes) · [Data model](../architecture/data-model.md) · [Addon modules](../architecture/addon-modules.md)

## Context

An item or spell line's Japanese carries `$N<k>` placeholders, numbered to the values of the English template it was written against. The addon fills them from the live tooltip line in reading order. The gate then checks that every name and number of the filled Japanese is in the live line.

That check cannot fail on a wrong order: every number it fills in came from the live line. A player reported a spell whose template had gained a number in front (a chance). The Japanese they had was numbered for the earlier template, so the reduction showed the chance and the stack count showed the reduction. The same happens to any filled line between a client build that changes a template and the addon release that follows it, and to a stale line shipped before it is drafted again.

## Decision

1. **Each filled item or spell line ships how many values its English prints** (`align.value_slots` of the template, inclusions spliced in), as one number per field after the row's status string. A line with nothing to fill, a branch line (it has its shapes) and a template whose values cannot be counted ship none.
2. **The addon shows such a line only while the live line holds exactly that many values**, read the way it reads them for filling (`Align.values`: a range is one value, an icon's path and a digit glued to a letter are none, a name-list tail is not counted). More or fewer: the tooltip keeps its English, with the missing marker, and the Collector records the line as one the addon does not cover.
3. **A stale line whose placeholders no longer fit its English ships a count no line has.** It stays English until it is drafted again. A stale line that still fits ships the count of the English as it stands.
4. The check is in the one gate (`Align.check`, `Align.fillValues`), so the tooltip, set bonus lines and the Collector's covered check all follow it. Lines of other types are unchanged.

## Rationale

- The count is the cheapest fact that tells a moved value: one small number per line, no English shipped.
- Showing English is the contract for any doubt. Wrong numbers in a tooltip are worse than an untranslated one: a player acts on them.
- The count is of values only. A duration is also a value, so a change in durations changes the count, and the unit corner cases of counting durations apart stay out of the check.

## Consequences

- 19,616 of the shipped item and spell lines carry a count on this build.
- After a client build that changes a template, its tooltip is English until the next release. The Collector sends it, so the change is seen.
- A change that keeps the count and reorders the values is still not caught at run time. The re-pull marks such a line stale, and the lint holds a draft's placeholders to its English.

## Alternatives considered

- **A key of the live wording with its values masked** (as keyed branch lines have). It would also catch a rewording that keeps the count, but the addon would have to reproduce every way the client prints a template (plural forms, gender forms, durations), and a miss turns a good line English. Rejected for every line; kept where branch lines need it.
- **Leaving it to the names and numbers gate.** That is what let the report through.
