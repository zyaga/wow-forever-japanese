# ADR-049: Manual line breaks in tooltip text are joined when generated

- **Status:** Accepted. Code: `pipeline/wfj/core/tooltip_text.py`, applied by `generate` to item and spell lines.
- **Date:** 2026-10-01

## Context

The hand-written tooltip corpus breaks its lines by hand: `対象に$N1のNature属性ダメージを⏎与えます。`. The
translators wrote for the narrow tooltips of the original client, where a line break every twenty or so characters
was the only way to keep a tooltip readable. 849 shipped item and spell lines carry such breaks (1,281 breaks;
1,171 of them mid-sentence), and corrections written from those lines inherited them.

Today's client wraps a tooltip line itself (each line carries the client's own wrap flag), and the tooltip is wider.
So a manual break lands wherever the translator's width ran out, often one word before the end of a clause, and the
client's own wrap adds a second break before it. Wrath read "対象に14～16のNature属性ダメージを / 与えます。" with an
orphaned を.

The text in `data/` is the translator's; the project does not rewrite a person's line for presentation.

## Decision

`generate` drops a single line break from a hand-written (`human` or `correction`) item or spell line's Japanese
when the line's English template has no single line break of its own. A paragraph break (a blank line, `\n\n`) is
kept. A line whose English carries single breaks keeps every break, because nothing says which of the Japanese's
breaks are the template's. A machine line is never touched: its breaks mirror the template, included spells and
lists included. Carriage returns are dropped first, so a `\r\n` break counts as one and none is left behind. Two
Latin words a break kept apart get a space between them, so a name does not run into the next word. `data/` is not
changed; only the generated Lua is. The rule lives in `core/tooltip_text.py` (`shipped_ja`), runs before the branch
variants are split, so a branch line's variants are joined the same way, and is the text the fix-report intake
hashes, so a player's report on a joined line is found by the hash the addon sent.

## Consequences

- The 849 lines wrap at the client's width like every machine-drafted line, with no orphaned particles.
- The runtime checks are unaffected: the alignment gate reads names and numbers, not line breaks; tooltip lines
  carry no readings; the stale check compares English hashes. The fix-report hash is of the shipped text on both
  sides (the addon's report and the intake), which is why the join has one home.
- 25 lines whose English has its own single break (`…damage.⏎The powers…`) keep the translator's extra breaks too.
  They can be corrected by hand if they look wrong in game.
- Reverting is deleting the call in `generate` and regenerating.

## Alternatives considered

- **Rewrite the 849 lines in `data/`.** Edits a person's text for a presentation concern, and every correction
  variant would need the same edit. Rejected.
- **Join at render time in the addon.** The same effect with Lua string work on every tooltip show, and the shipped
  data would still carry the breaks. Rejected: the pipeline already owns what ships.
