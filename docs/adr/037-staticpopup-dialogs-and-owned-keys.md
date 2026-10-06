# ADR-037: StaticPopup dialogs and keys that own their Japanese

- **Status:** Accepted. Implemented in `addon/WoWForeverJapanese/UI/Popups.lua`,
  `Core/UIStringKeys.lua` (`OWN`), `Core/UIStrings.lua` (`Index:keyOf`, `Index:formatArgs`, the `owned` count), `Main.lua` (`Popups` in the
  `forever` list), `UI/Slash.lua` (`/wfj debug ui` prints `owned`), `pipeline/wfj/cmd/validate.py` (`ui_own`, rule 7),
  `pipeline/wfj/dev/ui_inventory.py` (`popup_keys`), `pipeline/wfj/dev/ui_windows.py` (`FOREVER_WINDOWS["popups"]`),
  `pipeline/forever_addon_dispositions.txt`, `tests/python/test_popups_static.py`. Supersedes
  [ADR-015](015-ui-text-surfaces.md) §5. The in-game checks are in the level-1 checklist
  ([testing strategy](../testing/strategy.md)).
- **Date:** 2026-09-25

## Context

[ADR-015](015-ui-text-surfaces.md) §5 excluded StaticPopup dialogs ("Delete this item?", "Leave the group?"): the
dialog was thought to size its buttons from the text width right after `SetText`, so a post-hook swap would clip the
Japanese. A dialog's buttons also run protected actions (`OnAccept`), so addon code on that path was a taint risk.
[ADR-030](030-every-window-the-forever-client-loads.md) recorded `blizzard_staticpopup` and
`blizzard_staticpopup_game` as `not-a-window` for that reason, and the StaticPopupSpecial frames (add friend, the
battle ready popups) with them.

Reading the Forever client's source changed both premises:

- `StaticPopup_Show(which, text_arg1, text_arg2, …)` looks up `StaticPopupDialogs[which]`, calls `dialog:Init`
  (which writes `Text` with `SetFormattedText(dialogInfo.text, text_arg1, text_arg2)`, `gamedialog.lua:120–128`, and each
  shown button with `SetText(dialogInfo.buttonN)`, `:302–320`), then shows the dialog, runs `dialog:Resize()` and
  returns it (`staticpopup.lua:309–433`).
- The dialog lays out from `dialogInfo`'s widths, not from the string (`gamedialog.lua:629–705`). A Japanese line wraps
  inside the English's width.
- The `OnAccept` handlers read (a sample of the definitions, not all 437) take their input from the dialog's Lua fields,
  `dialogInfo` and the edit box, not from the dialog's `Text` FontString. That the translated text never feeds a
  protected action is reasoning to confirm in game (the level-1 checklist), not a verified fact.

[ADR-030](030-every-window-the-forever-client-loads.md) §9 records a second, separate problem: one English, one Japanese.
Some English words need a different Japanese on one screen. "Back" is 背中 as the equipment slot and 戻る on the
auction house; "Available" is 在席 as a friends status and 習得可能 on the trainer filter. The PvP scoreboard's
five headers carry a line break the one-line English does not. Validate rule 7 and the addon index both refused two
keys that share one English with different Japanese, so those keys stayed English.

It also had to be confirmed that the secure-environment windows stay English.

## Decision

1. **Keys that own their Japanese (`UIStrings.OWN`).** `Core/UIStringKeys.lua` holds `OWN`, a set of keys whose
   Japanese belongs to that key alone.
   - `build()` keeps an owned key out of the shared by-English index: it goes into `index.own[english]`, is counted
     `owned`, never makes another key `ambiguous` and never answers an unrestricted `match()`.
   - `matchOnly(text, only)` answers from `index.own` first, with a key the widget's `only` set names. Plain strings
     only (an owned key whose English has an argument or a `%` is counted `unsupported`); of the label forms, only
     `wrapped` (the colour-wrapped trainer filter entry).
   - Validate reads `OWN` from the addon's UI string tables (`validate.ui_own`, the one table both sides use) and leaves owned
     keys out of rule 7's one-Japanese-per-English comparison.
   - Owned keys include the five `SCORE_*` PvP headers (the Japanese keeps the `\n`), `AUCTION_HOUSE_BACK_BUTTON`,
     `BACK`, `PROFESSIONS_CRAFTING_FORM_BACK`, `AUCTION_HOUSE_BROWSE_HEADER_QUANTITY`, `AVAILABLE`,
     `COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_AVAILABLE`, `AUCTION_HOUSE_DEPOSIT_LABEL`,
     `LOSS_OF_CONTROL_DISPLAY_PACIFYSILENCE` and `LEAVE_VEHICLE`. The trainer filter's `AVAILABLE` ships 習得可能.
     `COMBATLOG_FILTER_STRING_FRIENDLY_UNITS` ("Friends" in the combat log's unit filters) ships 味方 where the friends
     list says フレンド; the chat settings' unit rows ask for the unit filter keys by name. The recipe form's
     `PROFESSIONS_REAGENT_CONTAINER_LABEL` ("Reagents:") ships 素材: where a spell tooltip's reagents are 触媒.
   - `/wfj debug ui` prints the `owned` count.

2. **The dialogs are a surface, `popups` (`UI/Popups.lua`).** Three post-hooks on globals:
   - **`StaticPopup_Show`.** `hooksecurefunc` hands the hook the call's arguments, not the dialog, so the dialog is the
     shown one of `StaticPopup1`–`4` (`gamedialog.xml:339–358`) whose `which` is the call's (read only).
     - The key is the one whose client English is exactly the definition's template, `dialogInfo.text`
       (`Index:keyOf`). The Japanese is filled from the dialog's own arguments (`Index:formatArgs`: `string.format` of
       each specifier on its argument), so a player, item or zone name is copied as the English showed it
       ([principle 2](../architecture/principles.md#2-names-stay-in-english)), never matched out of the text.
     - The line is rewritten only while it still reads exactly the English the definition and those arguments give.
       A computed text (`dialogInfo.text == ""`, a dialog-specific `GetExpirationText`) or a changed one stays as
       written.
     - A definition whose text is `"%s"` shows its caller's line as written (the party invite, the talent wipe, the
       leave-instance question). That line is translated when it is exactly one key's English. The party invite's
       caller formats `INVITATION` with the inviter's name and may append `ACCEPTING_INVITE_WILL_REMOVE_QUEUE` after
       `"\n\n"` (`blizzard_game/mainline/eventimplementation.lua:757–779`, the camelot family's file): the line is matched against those keys only
       (`PASS_THROUGH`), the name taken as the template's `verbatim` argument, as a label surface does. A cross-realm invite
       is `INVITATION_XREALM`, whose own English holds a `"\n\n"`: the whole line is matched before the last paragraph is
       split off. The talent wipe's caller line (`CONFIRM_TALENT_WIPE_<n>`) is an exact key's English.
     - The `SubText`, the buttons and the extra button each take the one key whose English is the definition's
       string.
   - **`StaticPopup_OnUpdate`** (`staticpopup.lua:490–535`, every frame while a dialog is shown). The line is shown
     again when it changed. So is any button whose label the client wrote back to its English after the dialog was
     shown: an accept delay's end, or the party invite's Decline, which `SetupLockOnDeclineButtonAndEscape` locks for
     half a second with a countdown label and then gives its saved English back (`gamedialogdefs.lua:19–52`). The
     countdown label itself ("Decline (1s)") stays as the client wrote it. Of the expiration texts, only the shared one
     is rebuilt:
     `GameDialogDefsUtil.GetDefaultExpirationText` formats the template with `(seconds, SECONDS)` under a minute, else
     `(minutes, MINUTES)` (`gamedialogdefsutil.lua:53–61`): the death dialog's "%d %s until release", the logout and
     quit timers. The unit word is put in as its own Japanese, never left English inside a Japanese line.
   - **`StaticPopupSpecial_Show`** (`staticpopup.lua:941`). These frames own their text. The hook walks one of
     `AddFriendFrame`, `BattleNetInviteFrame`, `PVPReadyPopup`, `PVPFramePopup`, `PVPRoleCheckPopup`,
     `PVPReadyDialog`, `PlunderstormFramePopup`, `LFGInvitePopup`, `QuickJoinRoleSelectionFrame`,
     `RecruitAFriendRecruitmentFrame` (and its `UpdateRecruitmentInfo` rewrite), `ReportCheatingDialog` and
     `WardrobeCustomSetEditFrame`: their FontStrings and button labels, restricted to the words those frames' files
     name. The invitee name is `NEVER_TOUCH`. Other StaticPopupSpecial frames belong to their own surfaces.
   - The battle popups' arguments are declared in `UIStrings.ARGS`: a battle's name and a group leader are
     `verbatim`, the closing countdown is `time`.

3. **Taint reasoning.** Apart from secure post-hooks (`hooksecurefunc` on `StaticPopup_Show`, `StaticPopup_OnUpdate`,
   `StaticPopupSpecial_Show` and the recruitment frame's `UpdateRecruitmentInfo`, the sanctioned hook path), every
   write is a widget method (`FontString:SetText` through `Render`, a button's text through
   `Labels`). No Lua field of a dialog, of its `dialogInfo` or of `StaticPopupDialogs` is written, and `Resize` /
   `Layout` are never called, so nothing an `OnAccept` handler reads comes from addon code.
   `tests/python/test_popups_static.py` scans `UI/Popups.lua` for those writes and calls. This is reasoning from the
   source, not a verified fact ([principle 9](../architecture/principles.md#9-claims-about-the-client-need-a-source)): the in-game check accepts a dialog that runs its action.
   One more addition the static test does not see: a button's label goes through `UI/ButtonText`, which the first time
   installs `HookScript` handlers on that button (OnEnter / OnLeave / OnMouseDown / OnMouseUp / OnEnable / OnDisable /
   OnShow, to re-apply the font on a state change). Those are post-hooks the client runs after its own handler; they
   read and re-write the label only. The same in-game step (press the dialog's accept button) covers them.

4. **The inventory reads every dialog definition.** `popup_keys` reads each `StaticPopupDialogs["X"] = { … }`
   definition's top-level `text`, `subText`, `button1`–`button4` and `extraButton` fields, and any later
   `StaticPopupDialogs["X"].text = NAME` line, in every Lua file of the camelot load set. The dialog keys are listed, or
   excluded with reasons: the typed confirmation words (`BUYOUT_AUCTION_CONFIRMATION_STRING`,
   `CONFIRM_AZERITE_EMPOWERED_RESPEC_STRING`, the "FATE" confirmation string: the player must type the English),
   product names, pass-through templates, and the two dialog lines whose English carries a link (`CONFIRM_XP_LOSS`,
   `DUEL_TO_THE_DEATH_REQUESTED`: a listed English carries no link; their buttons are still Japanese). Every
   listed dialog template is `ONLY` in `Core/UIStringKeys.lua` (no unrestricted match takes a line) and
   declares its argument kinds (`verbatim` by default: UI/Popups copies the dialog's own arguments).

5. **The secure-environment windows stay English (confirmed).** The Store, the catalog shop and its refund / top-up
   flows, the embedded checkout, WoW Token redemption, secure transfer and the authenticator challenge carry
   `UseSecureEnvironment: 1` in their TOCs. Our reading of that flag (no other source) is that they run in a
   separate secure Lua state that addon code cannot see, hook or write to; nothing in the load set gives an addon a
   handle on their frames. There is no route; their dispositions stay `not-a-window`.

### Known limits
- A dialog whose template takes three or more arguments (`CONFIRM_SUMMON*`, `WORLD_PVP_ENTER`, …) stays English:
  the dialog keeps only `text_arg1` / `text_arg2`, so the line cannot be rebuilt. Its buttons are Japanese.
- A dialog text holding a raw `|4` plural group, a computed text (`dialogInfo.text == ""`) or a dialog-specific
  `GetExpirationText` stays English. The shared countdown (`GetDefaultExpirationText`) is rebuilt with SECONDS /
  MINUTES as their Japanese. Whether the client's `GetText` returns the raw `|4Minute:Minutes;` (which the rebuild
  compares against) is an in-game check (the death dialog with more than a minute left).
- `StaticPopup_OnUpdate` runs every frame while a dialog is shown. A frame where nothing changed costs one `GetText`
  call for the line and one per button; a countdown that the client rewrites each frame is translated again each frame.

## Consequences

- Most dialogs a player meets show Japanese, with names as written and the buttons in Japanese. Alt shows the live
  English, as on every surface.
- A dialog whose text the client computes (its own `GetExpirationText`, an empty template) stays English. So does a
  dialog whose text changed after `Init` in a way the definition cannot explain.
- The pipeline keeps finding new dialogs on its own: a new `StaticPopupDialogs` definition in the extract shows as a
  changed inventory and must be listed or excluded (the existing coverage test).
- Owned keys are routing, not a new data shape: the rows are ordinary `ui` rows. A surface that wants one names it in
  its `only` set. An owned key never shows on a widget that did not ask for it.
- Items to confirm in game (the level-1 checklist): the layout grows for a Japanese line taller than the English (the
  dialog lays out from `dialogInfo` widths, so a wrapped line might overflow); accepting a dialog that runs a protected
  action gives no "blocked action" error; a timed dialog's countdown keeps its Japanese; the Alt swap on a dialog.
- Rollback: if a dialog taint shows up in game, drop `Popups` from the `forever` list in `Main.lua` (the guarded init
  leaves the client untouched).

## Alternatives considered

- **Match the shown text against the whole dictionary** (as `Labels` does). A dialog's text is a template around
  names; matching it back out risks reading a name as a word. The definition names its own template, so the key is
  known and the arguments are the dialog's own.
- **Write the Japanese into `dialogInfo.text` or `StaticPopupDialogs`.** That puts addon values where secure code reads
  them (taint). Rejected.
- **Call `Resize` after the swap.** A call into the dialog's layout from addon code; not needed while the dialog lays
  out from `dialogInfo` widths. Revisit only if the in-game check shows clipping.
- **A per-surface Japanese table** (one English → a Japanese per surface). The surface is already chosen by `only`; a
  set of owned keys is enough.
- **Keep the homographs English**: that leaves visible
  English on the auction house, the trainer and the PvP scoreboard for no reason the player can see.

## Related

- Supersedes [ADR-015](015-ui-text-surfaces.md) §5 · closes [ADR-030](030-every-window-the-forever-client-loads.md) §9
  and confirms its §10
- [ADR-014: machine-drafted text and the UI dictionary](014-machine-drafted-text-and-ui-dictionary.md) ·
  [ADR-009: surfaces post-hook the writer](009-surfaces-post-hook-the-writer.md) ·
  [ADR-025: guarded surface init](025-guarded-surface-init-and-runtime-tooltip-path.md)
- [Addon modules](../architecture/addon-modules.md) · [Pipeline](../systems/pipeline.md) ·
  [Research: the Forever window sweep](../research/2026-09-19-forever-window-sweep.md)
