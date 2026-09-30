# ADR-041: Word cards on plain-text window labels

- **Status:** Accepted. Implemented in `addon/WoWForeverJapanese/UI/Readings.lua`
  (`View.NON_WINDOW`, `View.nonWindow`, `View.tooltipSurface`, `inWindow`, `eligible`), `UI/TooltipLines.lua`
  (`follow` registers the exact surface it follows as non-window), `Core/Readings.lua` (the `ui` kind), `pipeline/wfj/core/readings.py`
  (`TYPES["ui"]`, the UI key check), `pipeline/wfj/cmd/readings.py`, `pipeline/wfj/cmd/generate.py` (`ui:<KEY>` rows),
  `data/reading/ui/`. Until a `ui` line has a word list, its label shows no card. The in-game checks are in the word
  card checklist in [Testing strategy](../testing/strategy.md).
- **Date:** 2026-09-25

## Context

The word card ([ADR-036](036-readings-hover-word-lists.md), [ADR-039](039-word-meanings-written-in-context.md)) showed
only on quest and gossip prose: the quest window panels, the quest map details and popup, and the gossip greeting.
The translated interface has short Japanese labels a learner reads just as often (the quest window's 報酬 and
以下の報酬から1つ選択できます, the character sheet's section labels, mail's 宛先:), and they had no card.

Word cards belong on plain-text labels in every window, not only the quest windows. Not on buttons, tabs, menus or dropdowns: those are clicked, and a cover
over them would take the click. Not on tooltips: a tooltip belongs to whatever the mouse is on, so it cannot be
hovered (ADR-036). Not on the HUD: the tracker, alerts, error and combat text, unit frames and zone text are not
windows a reader stops at.

Every translated label already reaches the screen through one path: `UI/Labels.show` → `UI/Render.show(surface, key,
fs, en, "ui", "ui", uiKey)` → `Render.sync` → `ReadingView.attach(rec)`. The addon registers more than 125 surface
names across its UI modules.

## Decision

1. **The UI dictionary gets readings.** Reading type `ui` (field `text`), keyed by the UI string key, records in
   `data/reading/ui/` sharded by the key's first character like `data/ui`, generated as `["ui:<KEY>"] = { text = "…" }`
   rows. `Core/Readings.words("ui", key)` reads them. Every UI line with something to annotate gets a word list; the
   addon decides at runtime where a card may show.
2. **The eligibility rule** (`UI/Readings.lua` `eligible`). A `ui` record takes a cover when all hold:
   - its widget has `CalculateScreenAreaFromCharacterSpan`. A Button's text reaches Labels as a ButtonText adapter
     and a menu entry as a `Labels.menuText` adapter; neither has the call, so buttons and menus are refused here;
   - its FontString's parent is not a Button (`IsObjectType("Button")`, which covers CheckButtons, tabs and list rows)
     and not protected (`IsProtected()`), so a cover of ours is never laid inside a secure frame;
   - its surface is not a non-window surface (decision 3);
   - `Readings.words("ui", key)` has words found in the applied text. The class / race token cards
     (`Readings.withTokenWords`, ADR-039 decision 7) are for prose only: a label whose text holds only such a word
     (ドルイド) gets no cover.
   Prose surfaces (`View.SURFACES`) behave exactly as before.
3. **A denylist of non-window surfaces**, `View.NON_WINDOW`: alerts, the Battle.net toast, the boss banner, the
   casting bar, chat tabs, combat feedback, combat text, the cooldown viewer, the damage meter, the errors frame, the
   ghost frame, `help` (UI/HelpTooltip and MicroMenu's records on it), HUD labels, loss of control, the major faction
   toast, the quest map's tracker headers (`questmap.trackerlabels`) and tracker objectives, the quest timer, queue
   status, status notices, the tracker, unit frames, zone text, the gamepad HUD (`gamepad`, [ADR-040](040-gamepad-hud.md)), the spellbook's
   menu (`spellbook.menu`), and the surfaces whose labels are GameTooltip lines under a name without `tooltip`
   (`auctionhouse.token`, `communities.benefits.rewardtip`, `deathrecap.tip`, `quickjoin.tip`). A name covers every
   surface under it (`alerts` covers `alerts.<anything>`). Any surface whose name holds `tooltip` is a tooltip
   (UI/Tooltip's `tooltip.<frame>`, the windows' `<window>.tooltip`), and `UI/TooltipLines.follow` marks each surface it
   follows at run time (`View.tooltipSurface`): that exact surface only, not the surfaces under its name. Every other
   surface is a window.
4. **One shared path, no per-window hooks.** The rule lives in `UI/Readings.lua` only; `Labels` and `Render` are not
   changed. A window added later gets cards on its labels with no code, unless its surface is non-window.
5. **What the card may cover** ([principle 3](../architecture/principles.md#3-japanese-by-default-english-one-key-away)). The word card covers a Japanese word in quest or gossip
   prose, or in a plain-text label in a window, never a button, tab, menu, tooltip or the HUD. Everything else about the card is unchanged: nothing drawn until the mouse is on a word, never while English
   shows, `readings.enabled` / `readings.glosses` turn it off.

## Consequences

- Every annotatable UI string needs a word list with meanings, and every UI translation batch writes readings with
  meanings ([Translation batches](../operations/translation-batches.md#readings-for-a-batch)). A UI line
  shown only on a button, a menu or the HUD carries a word list that never shows; the addon, not the data, decides.
- Pooled list rows reuse their FontStrings: the existing guard (on mouse enter the cover re-checks that the FontString
  still shows the attached text) keeps a stale cover from drawing, unchanged.
- A label holding `|` (a colour code) gets no card, as for prose (ADR-036 decision 9).
- `attach` stays inside Render's `pcall`; a failure is counted, never raised.
- A cover sets `ignoreInLayout = true`, so it never counts toward the size of a Blizzard `ResizeLayout` frame the
  label sits in.
- The denylist must follow new surfaces. One pytest checks that every `NON_WINDOW` entry names a surface some UI
  module registers, so the list cannot rot into names that match nothing; `test_every_registered_surface_is_classified`
  resolves every surface name a module hands to `Labels` / `LabelTree` / the Communities kit / `Render` /
  `TooltipLines` (by literal, constant or the `local show = WFJ.Labels.show` alias) and fails on one that is neither in
  its `WINDOW_SURFACES` set nor non-window; `test_no_new_surface_named_by_a_variable` pins the reviewed call sites whose
  surface is a variable (pane fields, a module's `surface` parameter), so a new one fails too. A new surface (a
  HUD-like module included) fails the tests until someone classifies it. Edit Mode's HUD selection overlays have
  their own surface, `editmode.selection`, listed non-window; the Edit Mode manager and its dialogs stay windows.
- **Known limit: composite labels.** In a label built from a pattern and filled-in arguments (`Labels.showArgs`, a
  popup with filled args), the word search runs over the whole line on screen, so a listed word that also appears
  inside an argument filled in earlier in the line (a name, an item) is found there first. The reading is still right
  for those characters; only the spot is not the pattern's own word.
- The meanings on these labels follow the same rule as elsewhere: model-written word meanings, which may use the game's own word for a word where it matches, never a
  whole English line or sentence of the game's text ([ADR-039](039-word-meanings-written-in-context.md)).
- More UI data ships: the `ui` word lists add to `Data/Reading/` and `Data/Gloss/`; memory is reviewed once every
  surface is translated ([ADR-039](039-word-meanings-written-in-context.md)).

## Alternatives considered

- **Quest windows only** (the reward and objective headers beside the prose): rejected; labels in every window are
  read just as often.
- **An allowlist of window surfaces**: 125+ surface names to list and keep current, and every new window would need
  an entry before its labels got cards. The non-window set is small and stable.
- **Per-window hooks** (each window module attaching its own covers): duplicates the attach path in every module and
  bypasses Render's sync / detach guarantees; one shared path through `ReadingView.attach` keeps "never while English
  shows" in one place.
