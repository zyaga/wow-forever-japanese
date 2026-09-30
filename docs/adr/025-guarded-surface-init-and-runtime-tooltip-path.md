# ADR-025: Every surface init is guarded and its failure reported, and the tooltip carries two hook paths chosen at runtime by capability

- **Status:** Accepted. In-game checklist 19 ran on Forever build 1.60.1.69893: the addon loaded and reached `PLAYER_ENTERING_WORLD`, `/wfj debug` reported `hook path: dataprocessor` with 6/6 tooltip frames and the spell-description API present, and `surface errors:` listed exactly one failure (`raid`, in `UI/Labels.lua`), which cost that surface and nothing else.
- **Date:** 2026-09-17

> Superseded in part by [ADR-034](034-forever-is-the-only-target.md): Classic Era is not a target; the tooltip's Classic path (`OnTooltipSetItem` / `OnTooltipSetSpell` `HookScript`) and the aura method-hook fallback are removed, and `Tooltip.path` is `"dataprocessor"` or `"none"`. The guarded init stands.

## Context

Two findings from the survey of the Forever client ([What the Forever client changed under the addon's surfaces](../research/2026-09-17-forever-client-differences.md), findings 1 and 2) forced one design question each, and the two answers belong together: both are about *what an addon does on a client it was not written for*.

**The composition root was a single point of failure.** `Main.lua`'s `OnLoad` ran roughly twenty surface `init` calls as one unguarded sequence. `Tooltip.init` is the third. On the Forever client it raised `bad argument #2` from its `HookScript("OnTooltipSetItem", …)`, so the other seventeen surfaces, the options registration, the AddOn List button and `WFJ.Slash.register()` never ran, and `/wfj` did not answer at all. One removed API in one surface cost the entire addon, including the command a player would use to diagnose it. Nothing about that is specific to the tooltip: any surface can be the third one on the next client.

**The tooltip's hook genuinely moved.** `OnTooltipSetItem` / `OnTooltipSetSpell` are not scripts on Forever's tooltips (`GameTooltip:HasScript("OnTooltipSetItem") == false`, checked in-game), because Forever runs the `mainline` flavour of the tooltip code. The replacement is named in the client's own extracted source: `blizzard_sharedxmlgame/tooltip/tooltipdatahandler.lua` registers handlers through `TooltipDataProcessor.AddTooltipPostCall(tooltipType, func)`, with tooltip types from `Enum.TooltipDataType`, and `blizzard_sharedxmlgame/tooltip/tooltiputil.lua` filters with `tooltip:IsTooltipType(…)`. (The source is read through the read-only local-archive path of [ADR-021](021-client-tables-from-the-local-archive.md).) Classic Era 1.15.x has neither global and its `HookScript` path was the only one known to work there.

Both sit under the constraint the addon has had since [ADR-009](009-surfaces-post-hook-the-writer.md): a surface post-hooks the client's writer, and an unresolved client name is a `/wfj debug` line, never an error. The survey showed that rule held *within* a surface and not *between* surfaces.

## Decision

**1. Every step of `OnLoad` runs through one guard, and failures are reported rather than fatal.**

`Main.lua` declares a single local `step(name, fn)` that `pcall`s `fn`, and on failure appends `{ surface = name, err = tostring(err) }` to `WFJ.initErrors` and returns `nil`. Every call in `OnLoad` goes through it: `Compat.init`, `Settings.load`, `Collector.load`, `BuildUIIndex`, `Render.init`, `Modifier.refresh`, each `Labels.forbidNames`, each surface `init`, `Scan.init`, `Slash.register` and `AddonListButton.install`.

- **The order is unchanged and stays load-bearing.** The guard wraps calls; it does not reorder them. `ButtonText` / `HelpTooltip` / `LoadOnDemand` still precede the surfaces, and `Labels.forbidNames` still precedes every window's `init`. `init_guard_spec.lua` asserts the order explicitly.
- **The guard is one function in the composition root, not a `pcall` inside each surface.** A surface does not get to decide whether its own failure matters.
- **`/wfj debug` is the report.** It prints `surface errors: <surface>: <err> · …`, and `none` on a clean load. With `unresolved widgets:` beside it, that pair is the compatibility check on any future client without re-running the survey.
- The `pcall` around `Compat.registerOptions(Options.build())` keeps its own `WFJ.Options.buildError` field, which the settings surface reads, **and** records into `WFJ.initErrors` like every other step.

**2. The tooltip surface chooses its hook path at runtime, from whether the capability resolves, never from the client version.**

`Tooltip.modern()` reads the two capability names through **`Compat.resolve`**, deliberately **not** through `Compat.declare` / `Compat.get`. A declared candidate that does not resolve is reported by `Compat.unresolved()` and printed by `/wfj debug` as a problem, and on a client without the system the *correct* answer is that neither `TooltipDataProcessor` nor `Enum.TooltipDataType` exists. These are a question about which client this is, not a widget the surface needs. `Tooltip.modern()` returns the pair only when the processor is a table with an `AddTooltipPostCall` function *and* the type table carries both `Item` and `Spell`. `Tooltip.path` records which path was taken and `/wfj debug` prints it; `Tooltip.resolved()` returns it as a fourth value.

- **Data-processor path:** one `AddTooltipPostCall` per data type for the whole client. One registration covers every tooltip that uses the system, so no per-frame loop is used for item and spell.
- **`OnHide`** is hooked per frame, a plain widget script on every client, and the handler calls `Tooltip.onItem` / `Tooltip.onSpell`, so the rendered output is the same as ADR-010's.
- **The post-call is handed tooltips the addon never declared.** A shared registration fires for anonymous and third-party tooltips too, so the handler filters: `tt:IsTooltipType(want)` where the method exists (the client's own helper), then the frame's name against `Tooltip.IS_SURFACE` (the six declared frames), then the presence of the reader `onItem` / `onSpell` needs (`GetItem` / `GetSpell`). A frame missing it is counted in `Tooltip.dataMisses` and never called. Anything else is ignored.

**3. `Compat` resolves dotted candidate names.** Modern clients moved APIs into namespace tables, and a surface has to be able to *name* the moved form. A candidate containing a dot (`"C_Spell.GetSpellDescription"`, `"Enum.TooltipDataType"`) is walked segment by segment from the first segment's global. This is strictly additive: no candidate contained a dot before, so a dotted name always resolved to `nil`, and `declare` / `get` / `resolve` keep their signatures and their results for every existing candidate. `Core/Compat.lua` has many consumers, so that was checked for each.

## Consequences

- **A broken surface costs that surface and nothing else.** `/wfj` answers on a client where half the addon cannot initialise, which is the difference between a diagnosable client and an opaque one.
- **The failure is visible instead of silent.** The risk a blanket `pcall` carries is that a surface quietly stops working; `surface errors:` is the countermeasure, and it is also the first thing to read on any future client.
- **The guard cannot save a surface that fails *after* `init`.** A hook installed successfully at load and raising later on a client call is still a Lua error in that call path; this ADR covers the load sequence only.
- **The data-processor handler runs for every tooltip in the client**, not just six. The filter chain above is therefore load-bearing, and `tooltip_forever_spec.lua` pins it (wrong type ignored, undeclared frame ignored, missing reader counted not called).
- **Capability detection stays honest about what it proves.** `Tooltip.path` says which path the addon took, not which client it is on; nothing in the addon reads `GetBuildInfo()` to decide behaviour.
- **`Compat` grew by one resolution rule that every surface inherits.** A surface can name a namespaced API as a fallback candidate with no new function, which is what the tooltip's `spellDescription` list does (the bare `GetSpellDescription` is absent from the Forever client).

## Alternatives considered

- **One `pcall` per surface, inside each surface's own `init`.** Rejected: a surface that knows it might fail is a surface that hides its failure, and the fix would have to be repeated in about 20 files and remembered in every new one. The composition root is the one place that already owns the load sequence, and it is where the failure list belongs.
- **Wrap the whole `OnLoad` in one `pcall`.** Rejected: that is effectively what the addon had. It converts "one surface broken" into "everything after it broken" and reports nothing.
- **Branch on `select(4, GetBuildInfo())` (the interface number) or on the client flavour.** Rejected: it asserts a fact about a client build rather than asking it a question, and it goes stale on every build. The addon already resolves every client-specific name by candidate list; a capability check is the same discipline applied to a system instead of a name. It would also have been *wrong* here: Forever ships several interface flavours side by side and picks per system (research doc, Summary), so one version number does not predict one tooltip implementation.
- **Register the post-call per declared frame** (a six-frame loop). Rejected: `AddTooltipPostCall` is client-wide by design, so six registrations would fire the handler six times per tooltip. One registration per data type plus a name filter is the shape the client's own code uses.
- **Add a `C_QuestLog` candidate beside `GetQuestLogTitle` / `GetQuestLogQuestText` / `GetQuestLogSelection`.** Rejected as a guess: the modern `C_QuestLog` functions take a **quest id** where these take a **log index**, so they are not drop-ins. The three are declared with their bare names only, and `QuestLog.onUpdate` returns `0` and leaves the pane English when any is missing.

## Related

- [What the Forever client changed under the addon's surfaces](../research/2026-09-17-forever-client-differences.md): findings 1 and 2
- [ADR-009: Surfaces post-hook the writer](009-surfaces-post-hook-the-writer.md): the rule this extends from "within a surface" to "between surfaces"
- [ADR-021: Client tables from the local archive](021-client-tables-from-the-local-archive.md): the read-only path the replacement hook was read from
- [ADR-010: Tooltip in-place run replacement](010-tooltip-in-place-run-replacement.md): what `onItem` / `onSpell` do
- [Addon Modules](../architecture/addon-modules.md) · [Testing Strategy](../testing/strategy.md) (in-game checklist 19)
- Implementation: `addon/WoWForeverJapanese/Main.lua`, `addon/WoWForeverJapanese/UI/Tooltip.lua`, `addon/WoWForeverJapanese/Core/Compat.lua`, `addon/WoWForeverJapanese/UI/Slash.lua`
