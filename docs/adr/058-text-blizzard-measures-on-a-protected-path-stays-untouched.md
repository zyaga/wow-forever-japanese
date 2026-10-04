# ADR-058: Text that Blizzard measures on the way to a protected call stays untouched

- **Status:** Accepted
- **Date:** 2026-10-04
- **Related:** [Client limits](../architecture/client-limits.md) · [Diagnostics log](../systems/diagnostics.md) · [Lesson: the spellbook blocked the action bars](../lessons/2026-10-04-spellbook-text-blocked-the-action-bars.md) · [ADR-016](016-whole-window-interface-coverage.md) (whole-window interface text) · [ADR-029](029-camelot-targets-the-mainline-family.md)

## Context

On Forever 1.60.1.70205 the game blocked Blizzard's own action bars under this addon's name in combat
("Interface action failed because of an AddOn"; `ADDON_ACTION_BLOCKED` on `MainActionBar:SetPointBase()`,
`StanceBar:ClearAllPointsBase()`, `PetActionBar:SetShownBase()`, `MultiBar*:HideBase()` and more). The bars stopped
moving or vanished until combat ended. It showed after a bar page change in combat: a rogue breaking stealth, a
warrior changing stance.

The research for ADR-016 assumed that text written into a Blizzard FontString does not carry taint, because the
taint documentation lists variables, table keys, script slots and closures, not widget properties. That was marked
as likely, never verified.

The addon's problem log traced the path in game, step by step (the probes are described in
[Diagnostics](../systems/diagnostics.md)):

1. The blocked layout read flags on the bars (`showAllButtons`, `snappedToFrame`) that the client reported, with
   `issecurevariable`, as written by code tainted by this addon.
2. Probes on those flags' writers recorded the stacks. Hovering a spell in the spellbook ran Blizzard's hover code
   (`SpellBookItemMixin:OnIconEnter`) tainted. That code then wrote the bars' highlight marks, and on leaving the
   spell it re-ran the bar layout (`PetActionBar:Update`), which stamped the bars' flags.
3. The hover was tainted because it read the spell button's `actionBarStatus`, which was tainted.
4. A probe on that field's writer caught the first tainted write. It happened while a tab click refilled a spell
   button the addon had already translated (`UpdateVisuals`, line 279). In the same entry every data field on the
   button was still clean. The fill was clean up to line 107 and tainted by line 279.
5. In those lines the only thing the fill reads that this addon changed is the button's three FontStrings:
   `TrimTextSpace` (lines 163 to 178) calls `GetText`, `GetStringHeight` and `GetLineHeight` on the spell name,
   subtext and level line. The addon wrote Japanese and its bundled font into the subtext and level line. A second
   entry showed the page layout (`ApplyLayout`) running tainted right after it measured the search-result headers
   the addon had translated.

Removing every write into the spell buttons and the page's headers removed the block. The same session that had
blocked every time (new rogue, learn Stealth, open the spellbook, switch tab, hover, stealth, attack) then logged no
tainted write, no tainted field and no block.

A second finding came on the way: with the client setting `taintLog` at 1, every method this addon (or a one-line
`/run`) post-hooks with `hooksecurefunc` fails with "attempt to call a nil value" when Blizzard's own code calls
it. Flipped live, five times, with and without the addon: 1 errors, 0 does not. The client never wrote a
`taint.log`. So `taintLog` is no tool on Forever and was never the cause of the blocked bars.

## Decision

1. **Nothing of this addon writes into a FontString that Blizzard measures on a path that ends in a protected
   call.** On such a FontString, text and font written by this addon come back tainted to the code that measures
   them (`GetText`, `GetStringHeight`, `GetLineHeight`, a layout frame's `Layout`). Whatever that code writes next
   carries the taint until a protected call refuses it, often much later and in combat.
2. **The spellbook's page is left as the client writes it.** No spell subtext ("Rank 1", "Passive", profession
   ranks), no level line ("Level 20", "Learn from trainer"), no flyout group name and no search-result header is
   written. The window title, page number, search placeholder and settings menu stay translated; none of them is
   measured on that path, and the session that proved the fix had them translated.
3. **Nothing of this addon runs inside the spellbook's own passes.** The title and the page number are followed by
   `UI/TextWatch` (read once a frame from the addon's own frame), not by post-hooks on `UpdateFrameTitle` and
   `UpdateControls`.
4. **A taint watch is always on** (`UI/TaintWatch`, [Diagnostics](../systems/diagnostics.md)): a check every 2
   seconds on the fields the bar layout reads, a stack from each of their writers when the value comes out tainted,
   a sweep of the bars' other fields, the last 60 game events with every finding, a stack on every block and a
   tainted-field scan at the first block of a session (also `/wfj taint`). It only reads; its cost is a few dozen
   checks every 2 seconds.
5. **`taintLog` is never used on Forever.** Not in the in-game checklists, not to debug. The taint watch replaces it.

## Consequences

- The spellbook's spell subtexts, level lines, flyout names and search-result headers stay English. Spell names
  were always English; spell tooltips are a separate path and stay Japanese.
- Getting those lines back would mean drawing the addon's own FontStrings over Blizzard's instead of writing into
  them. That needs its own in-game proof with the taint watch before it ships.
- Any other surface may hide the same trap: a FontString the addon writes that Blizzard measures on the way to a
  protected call. The taint watch shows it the first time a block happens: the stack of the tainted write and
  the field it went through. The fix is the same: stop writing into that FontString.
- A block is now traced, not guessed: the problem log holds the block's stack, the first field that turned
  tainted, its writer's stack and the events before it ([Diagnostics → Tracing a blocked action](../systems/diagnostics.md#tracing-a-blocked-action)).
