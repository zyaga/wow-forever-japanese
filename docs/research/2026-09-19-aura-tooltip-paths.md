# How the clients show a buff or debuff tooltip

> 2026-09-19. Read from each client's own UI code: **Forever beta 1.60.1.69913** (the Forever client's own
> UI files, extracted with `dev/client_ui`, 4,042 files) and **Classic Era 1.15.9** (Gethe/wow-ui-source, branch
> `classic_era` at `33e177d`). A claim about how a Blizzard API behaves on the Forever client needs a source
> ([principle 9](../architecture/principles.md)); this note is that source for the aura tooltip surface in `UI/Tooltip.lua`.

## Question

The data carries an `aura` field for spells (the buff / debuff wording, a different string from the spell's tooltip
description under the same spell id), but no surface showed it. Where does the client put an aura tooltip, how does
the addon learn which spell it is, and is the answer the same on both clients?

## Options

| Option | Pros | Cons |
|---|---|---|
| Reuse the spell tooltip hook (`OnTooltipSetSpell` / the `Spell` post-call) | No new hook | The `Spell` post-call never fires for an aura on Forever; on Classic Era `OnTooltipSetSpell` is not expected to (below) |
| A `TooltipDataProcessor` post-call for `UnitAura` | One registration; fires on the first build **and on every rebuild** | Forever only: Classic Era has no processor |
| `hooksecurefunc` on `GameTooltip`'s six aura methods, spell id from `C_UnitAuras` | Works on Classic Era; what Blizzard's PTR reporter does on Forever | On Forever a rebuild rewrites the lines without calling any method, so the English comes back mid-hover |

Chosen: **two paths**, the `UnitAura` post-call on Forever, the six method hooks on Classic Era.

## Findings

### Forever 1.60.1.69913

An aura tooltip is first built by one of six `GameTooltip` methods: `SetUnitAura`, `SetUnitBuff`, `SetUnitDebuff`,
`SetUnitAuraByAuraInstanceID`, `SetUnitBuffByAuraInstanceID`, `SetUnitDebuffByAuraInstanceID`. It is not always
rebuilt by one (see [Rebuilds](#rebuilds-forever)).

| caller | where |
|---|---|
| buff frame | `blizzard_buffframe/buffframe.lua:1145–1149`, `1220–1224`, `1338–1342` |
| target | `blizzard_unitframe/mainline/targetframe.xml:45` |
| party | `shared/partymemberframe.lua:202–206` |
| compact / raid | `shared/compactunitframe.lua:2147–2156`, `blizzard_raidui/mainline/blizzard_raidui.xml:319` |
| nameplates, cooldown viewer | through `GetAppropriateTooltip()`, which is `GameTooltip` in game (`blizzard_sharedxmlbase/frameutil.lua:318`) |
| arena frames | `blizzard_unitframe/mainline/compactarenaframe.lua:483`: `GameTooltip`, covered |
| maw buffs | `blizzard_mawbuffs/blizzard_mawbuffs.lua:287`: `GameTooltip`, covered |

The six are `TooltipDataHandlerMixin` accessors (`blizzard_sharedxmlgame/tooltip/tooltipdatahandler.lua:591–597`)
whose data type is `Enum.TooltipDataType.UnitAura` (**7**). `GameTooltip:GetSpell()` answers only for the `Spell`
type (`blizzard_sharedxmlgame/tooltip/tooltiputil.lua:25–31`), so the existing `Spell` post-call never sees an aura.
Each accessor records `{getterName, getterArgs}` as the tooltip's info (`tooltipdatahandler.lua:488–503`); the
`UnitAura` post-call reads them back with `GameTooltip:GetPrimaryTooltipInfo()`: `getterName` maps to the method
through `Tooltip.AURA_GETTERS`, and `getterArgs` are the same arguments a method hook would have seen. On Forever the
lines themselves are written in Lua, by `tooltipdatahandler.lua`, from the `C_TooltipInfo` data.

#### Rebuilds (Forever)

`TOOLTIP_DATA_UPDATE` → `RefreshData` → `RebuildFromTooltipInfo` → `ProcessInfo` rewrites every line from
`C_TooltipInfo` **without calling any of the six methods** (`gametooltip.lua:963–979`,
`tooltipdatahandler.lua:358–385`). A method hook alone would let such a rebuild put the English back mid-hover. The
`UnitAura` post-call fires on the first build and on every rebuild, so Forever uses it instead of the method hooks.
The target debuff button has no `UpdateTooltip`, so the rebuild is its only refresh.

### Classic Era 1.15.9 (`33e177d`)

The same six methods on `GameTooltip`: buff frame (`Blizzard_BuffFrame/BuffFrame.lua:933–937`), target
(`Blizzard_UnitFrame/Classic/TargetFrame.xml:45–133`), party, compact and raid frames. `TooltipDataHandler.lua` is
listed under `[ExcludeLoadGameType vanilla]` in `Blizzard_SharedXMLGame.toc:9`, so Classic Era loads no tooltip
data processor at all (the same finding the first Forever pass made in game), so the six methods are hooked with `hooksecurefunc`.
Here the C client writes the tooltip lines. That `OnTooltipSetSpell` does not also fire for these methods is
[likely], not verified: no UI file shows it either way. It is harmless if it does (the in-game checklist confirms it).

### The spell id

`C_UnitAuras` names the aura from the method's own arguments, on both clients:

| method | getter | arguments |
|---|---|---|
| `SetUnitAura` | `GetAuraDataByIndex` | `(unit, index, filter)` |
| `SetUnitBuff` | `GetBuffDataByIndex` | `(unit, index, filter)`, the helpful list |
| `SetUnitDebuff` | `GetDebuffDataByIndex` | `(unit, index, filter)`, the harmful list |
| `Set*ByAuraInstanceID` (three) | `GetAuraDataByAuraInstanceID` | `(unit, auraInstanceID)` |

The instance-id getter is called as `(unit, auraInstanceID)` only; the filter its method was called with is not
an argument. The result is an `AuraData` table; its `spellId` is the id. Present on Classic Era (its own
`Deprecated_1_15_8.lua` rebuilds `UnitAura` on top of these getters) and on Forever
(`unitauradocumentation.lua:189–357`).

**Blizzard's own Forever code resolves the id this way.** The PTR feedback reporter,
`blizzard_ptrfeedback/blizzard_ptrfeedback_tooltips.lua:22–32`, hooks `GameTooltip`'s `SetUnitAura`,
`SetUnitBuff` and `SetUnitDebuff` with `hooksecurefunc` and reads `auraData.spellId` from `GetAuraDataByIndex`.

### Secret values

Forever's documentation marks these reads `SecretWhenUnitAuraRestricted`: in a restricted context a returned value
can be secret, one an addon may not compare. The surface therefore treats a missing getter, a non-table result, an
error, or a `spellId` that is not a positive integer as "no aura", and leaves the tooltip untouched. Both the getter
call and the field read are `pcall`-protected.

The line texts can be secret too: Forever's `FontString:GetText` is `SecretReturnsForAspect Text`, and `type()` of a
secret is still `"string"`. When `issecretvalue` flags any line text, the surface leaves the tooltip untouched: no
compare and no forget. Nameplate and restricted-unit auras (`UnitTokenRestrictedForAddOns`) may therefore always
stay English; the in-game checklist records what happens.

### Guards

- The aura handler is `pcall`-wrapped as a whole. It runs from the buff frame's `OnUpdate`, so an error would repeat
  every frame; instead it is counted in `Tooltip.auraErrors`, `/wfj debug` prints `aura errors: N` after
  `aura hooks: N`, and the tooltip is left as the client wrote it.
- On Forever, line 2 is taken only when it is within the client's own line count (`tooltipData.lines`). A line
  another addon appended (an id line, the PTR reporter's hint) is past that count and is never the aura text. On
  Classic Era there is no such count, so an appended line 2 on a name-only aura remains a risk; the UI-dictionary
  refusal and the `Align` gate are the only guards there.
- The Collector records the aura line only for a spell whose `spell.aura` ships. Line 2 is a positional choice, and
  the Collector takes no positional guess as data.

### Refresh cost

Buff-frame buttons (every timed aura; `GetID()` is set only for temporary enchants) re-call `SetUnitAura*` from an
unthrottled `OnUpdate`. Party, compact and nameplate owners do it through `UpdateTooltip`, about 5 times a second.
Each call forgets and re-renders, as item tooltips do. The cost is to be measured in game (the in-game checklist,
`debugprofilestop`).

### Unverified: which line is the aura text

On Classic Era the C client writes the aura tooltip's lines; on Forever `tooltipdatahandler.lua` writes them from
`C_TooltipInfo` data, whose line order is the client's. Either way no UI file says which line carries the aura text. The observed shape is name / aura text / time remaining. The surface reads **line 2** [likely] and refuses
it when it is empty or matched by the UI dictionary (a duration or "remaining" line); the runtime `Align` gate then
refuses any line whose names and numbers do not fit the Japanese. Confirmed only by the in-game pass
([Testing strategy](../testing/strategy.md)).

### Not covered

- `BuffFrameTooltip`: the buff frame's own "next aura" helper tooltip, a separate frame.
- `PrivateAurasTooltip`: private auras are hidden from addons by design.

## Recommendation

On Forever, register one `TooltipDataProcessor` post-call for `UnitAura`, which sees the first build and every
rebuild, and read the method and arguments back from `GetPrimaryTooltipInfo()`. On Classic Era, hook the six methods
on `GameTooltip` with `hooksecurefunc`, once (only those that exist). On both, resolve the spell id through
`C_UnitAuras` with the call's own arguments, and render `spell.aura` on line 2 through the
existing spell-tooltip render path. See the `UI/Tooltip.lua` row of
[Addon modules](../architecture/addon-modules.md). No ADR: it is a new hook on an existing surface, not a change of
approach ([ADR-025](../adr/025-guarded-surface-init-and-runtime-tooltip-path.md) covers the item / spell hook paths).

## Related
- [Addon modules](../architecture/addon-modules.md) · [App capabilities: spell aura text](../app-capabilities.md#spell-aura-text-buff--debuff-tooltips) · [Testing strategy](../testing/strategy.md) · [Forever client differences](2026-09-17-forever-client-differences.md)
