# Lesson: Japanese in the spellbook blocked the action bars in combat

> Post-mortem from a playtest on Forever 1.60.1.70205. Decision: [ADR-058](../adr/058-text-blizzard-measures-on-a-protected-path-stays-untouched.md).

- **Date:** 2026-10-04

## What happened
In combat the game refused to move or show the action bars under this addon's name ("Interface action failed because of an AddOn", `ADDON_ACTION_BLOCKED` on `MainActionBar:SetPointBase()`, `StanceBar:ClearAllPointsBase()`, `MultiBar*:HideBase()` and more). Bars disappeared until combat ended. It came after a bar page change in a fight: a rogue breaking stealth, a warrior changing stance. It did not happen in every session, which made it look random.

## The detour: `taintLog`
To trace the first error, the client setting `taintLog` was turned on (`/console taintLog 1`). From then on the game threw dozens of "attempt to call a nil value" errors at Blizzard lines (chat box, XP bar, gamepad legend, tooltips), blocked the bars more often, and closed twice. Every failing call was a method this addon post-hooks with `hooksecurefunc`. That looked like a client bug that breaks every hook, and a large migration off hooks was planned on that basis.

The test that settled it: flip the setting live, with the addon disabled and one empty `/run hooksecurefunc(...)` hook. At 1, Blizzard's next call to the hooked method failed. At 0 it ran, and a printing hook printed. Five flips, the same each time. **With `taintLog` at 1 on Forever, every post-hooked method fails when Blizzard calls it.** The client never wrote a `taint.log` either. The hooks were fine all along. A whole evening went into a cause the debugging tool itself created.

## Root cause
With `taintLog` at 0 the block still happened, rarely. The addon's own log traced it, one probe at a time:

1. The blocked layout read flags on the bars that the client reported as tainted by this addon.
2. Their writer's stack: a hover over a spell in the spellbook. Blizzard's hover code ran tainted, wrote the bars' highlight marks, then re-ran the bar layout on leaving the spell.
3. The hover read the spell button's `actionBarStatus`, which was tainted.
4. Its writer's stack: a tab click refilling a spell button the addon had translated. Every data field on the button was clean. The fill turned tainted between line 107 and line 279.
5. In between, Blizzard measures the button's text (`TrimTextSpace`: `GetText`, `GetStringHeight`, `GetLineHeight`). The addon had written Japanese and its font into those FontStrings.

**Text and font this addon writes into a Blizzard FontString come back tainted to the Blizzard code that measures that FontString.** The research for ADR-016 had marked the opposite as "likely". It was never verified, and it is wrong on Forever.

It looked random because it needs, in one session: a translated spellbook page, a refill (tab switch, page flip, learning a spell), a hover, and then a bar change in combat.

## Fix
- The spellbook's spell subtexts, level lines, flyout names, search-result headers, page number and search preview are no longer written ([UI/SpellBook.lua](../architecture/addon-modules.md)). They stay English. The page number is measured by the paging controls' layout in the same pass that refills the items.
- The title is followed by `UI/TextWatch` from the addon's own frame instead of a hook that runs inside the spellbook's passes.
- A permanent taint watch (`UI/TaintWatch`) and a fuller block record in the problem log ([Diagnostics](../systems/diagnostics.md)).
- Unrelated, found on the way: unit tooltips in combat hand over secret text, and `Labels.show` compared it. It now leaves a secret line alone.

## How it was found, and how to find the next one
Guessing failed several times; probing at the right place worked. In order:

1. **Block stack.** The block entry shows what was blocked and the Blizzard path that tripped. That is the reader, never the cause.
2. **Which value carried the taint.** `issecurevariable(table, key)` answers whether a field was last written by tainted code, and by which addon. Scan the frames the blocked code reads (`/wfj taint`).
3. **Who wrote it.** A post-hook on that field's writer that logs `debugstack()` when the value comes out tainted. Its stack names the path. If the stack is all Blizzard code, scan what that code read just before the write, and repeat one level up.
4. **Never stop at the first plausible culprit.** Remove the suspect, run the same steps, read the probes again. The first fix here (moving spellbook hooks) was right about the place and wrong about the mechanism. The probes showed it at once.
5. **Probe every writer at once, not one per test.** Every test costs the maintainer a session. The taint watch now covers the bar fields from the start.

## Prevention
- **Never write into a Blizzard FontString that Blizzard measures on the way to a protected call** ([Client limits](../architecture/client-limits.md)). Spellbook items and anything laid out with them are the known case.
- **Never use `taintLog` on Forever.** The taint watch replaces it.
- **Check the debug settings before blaming the client.** When an error floods only after a setting changed, flip that setting back first.
- **A "likely" in research is not a fact.** Mark it, and verify it in game before building on it.
- The in-game checklist has a combat step for this exact path: [Testing → checklist 12](../testing/strategy.md).
