# ADR-007: Item and spell descriptions ship as *unaligned* and are gated at display time

- **Status:** Accepted. The gate is `Core/Align.lua`, wired as the Translator's `align` dependency and driven by the tooltip surface (ADR-010).
- **Date:** 2026-09-13

## Context
The 9,405 item and 3,543 spell descriptions in the predecessor corpus are human translations of **rendered tooltip lines** ("Use: Restores 61 health over 18 sec" with values substituted), not of any DB2 string (`ItemSparse.Description` is the flavour quote; `Spell.Description` is a `$s1`/`$d` template). No offline English exists to run the alignment check against, so under the trust rule (nothing is trusted until it has been aligned against its English) they could not become trusted until the collector had recorded those rendered lines. Items and spells would ship weeks after quests, and only as far as players' hovering reaches.

## Decision
Add a status **`unaligned`**: `human` provenance, Japanese, ID present in the client-side ID list (wago `ItemSparse` / `SpellName`), but no English to align against. Unaligned entries **ship**, and the addon runs the **same name + number check at display time** against the live tooltip lines it is about to replace; on failure it leaves the English. The collector records the rendered lines, so the pipeline later promotes `unaligned` → `trusted` (or `rejected`) offline, exactly as for quests. Quests are unaffected: pfQuest English exists, they are gated offline as decided.

## Consequences
- Items and spells are usable on day one, with a per-render guard that is *stronger* than the offline one (it checks the exact text about to be replaced, values included).
- The trust rule keeps its intent (nothing ships that contradicts the English), but the check runs in Lua for one entry kind. `Core/Align.lua` mirrors `align.py`; the shared vectors (`vectors/align_vectors.{jsonl,lua}`, 29 cases) cover it, and the Lua allowlist is parity-tested against `pipeline/allowlist.txt`.
- The gate checks names and numbers, not slot order: a spell entry whose `$N<k>` placeholders are numbered out of the English line's reading order fills correct numbers into the wrong slots, and every number is still present, so the gate passes it. Flagged for the audit pass; the collector's rendered lines make it visible offline.
- A few hundred bytes of Lua per hover; negligible.

## Addendum: offline tooltip English (2026-09-15)
Offline tooltip English now exists: `wfj import english client-text` stores each spell's `Description_lang` and each item's Use / Equip spell descriptions plus its flavour text as the `description` English ([ADR-021](021-client-tables-from-the-local-archive.md)). `check` now compares item / spell `description` lines against that text instead of the name, so their stored `english.hash` (and the shipped `h1`) is the tooltip-text hash. A line checked against the name (no tooltip English yet) records `english.of: name`, and a baseline taken from the name never makes the line stale (`check.fallback_baseline`): a rename re-baselines it, and when the line's own tooltip English arrives it is judged fresh against it (also for older data without `of`, when the stored hash equals the current name hash). On 1.15.9.69722 the move changed no status.

**Item / spell lines can be `stale`.** A line that passes the rules is `stale` when its stored `english.hash` differs from the current English hash (its tooltip English changed; a changed name never counts), else `unaligned`. Stale is sticky, as for quests (ADR-003). Item / spell lines are still never `trusted`: offline alignment stays off for them. In the addon a stale item / spell entry is **still gated**: the Translator runs the same align gate as for `unaligned` (names and numbers checked, live `$N` values filled). On a pass the Japanese applies with the stale marker (when the marker is on); on a fail the English stays, with no marker. That English is a template (`Restores $o1 health over $d`), so a changed number (61 → 80 health) is invisible offline and checking numbers remains the runtime gate's job: reworded wording with the same names and numbers → Japanese with the stale marker; changed numbers → English. The collector's known check now matches a spell description with no `$` variable, so that text is no longer re-recorded; templates with variables still differ from the rendered line.

## Alternatives considered
- **Strict offline only**: coverage 0 for items/spells until collector data exists.
- **Ship items/spells ungated**: violates the trust rule's intent; wrong-ID/changed-value text would show.
- **Reconstruct rendered English offline from wago tables**: requires re-implementing Blizzard's spell-effect value formatting; not worth it when the client renders it for free.
