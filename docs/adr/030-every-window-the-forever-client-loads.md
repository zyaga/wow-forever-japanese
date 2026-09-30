# ADR-030: The window list is read from the Forever client's TOCs, and every window it loads has a recorded disposition

- **Status:** Accepted. Implemented in `pipeline/wfj/dev/client_addons.py`, `pipeline/forever_addons.txt`,
  `pipeline/forever_addon_dispositions.txt`, `pipeline/forever_titles.txt` (committed data),
  `tests/python/test_client_addons.py`, `tests/python/test_forever_windows.py`; `pipeline/wfj/dev/ui_windows.py`
  (`FOREVER_WINDOWS`); one surface module per window in `addon/WoWForeverJapanese/UI/` and three shared helpers
  (`UI/LabelTree.lua`, `UI/TooltipLines.lua`, `UI/SettingsKeys.lua`); `Labels.title` in `UI/Labels.lua`; `Main.lua`,
  the TOC; `Core/UIStringKeys.lua` (ARGS, LABELS) and `Core/UIStrings.lua` (the `signed` capture). Not yet verified
  in game on Forever (the Forever window checklist in [Testing strategy](../testing/strategy.md)).
- **Date:** 2026-09-19

> Superseded in part by [ADR-034](034-forever-is-the-only-target.md): Classic Era is not a target; the camelot marker (`UI/Camelot.lua`, decision 5) and every gate on it are removed, and those surfaces take their Forever path unconditionally.

## Context

ADR-029 re-targeted the windows the addon already hooked. Its file map, `FOREVER_WINDOWS`, listed the files of
those 21 surfaces only. A window that exists only on Forever was in no surface and in no inventory, so nothing flagged
it. The first in-game pass found four of them: the Professions window, the Skills and Quest Log titles, and two Skills
headers.

The rest was measured from the client's own TOCs. Forever carries 347 Blizzard addons, and 283 of them load in
game on `camelot`. Scanned whole, they hold a ceiling of 7,573 names the inventory had never seen. Much of that is the
retail UI Forever ships (camelot is a member of the mainline family, ADR-029): garrisons, covenants, azerite, housing,
the shop. Some of those addons are gated away by their TOC, and some load but can never open on Forever. The rest are
real windows. A candidate list cannot tell these apart. Every judgement needs evidence, and the next client build will
add addons nobody has read.

Four facts about the client shaped the design:

- Many windows' titles are written by `frame:SetTitle(text)` into `TitleContainer.TitleText`. The window can re-title
  itself at any time: per tab, per mode, per selection.
- Several of the new windows use the same global names on Classic Era (`TradeFrame`, `TaxiFrame`, `TabardFrame`,
  `PetitionFrame`, `GuildRegistrarFrame`, `DressUpFrame`, `PlayerCastingBarFrame`, `GroupLootFrame1–4`). Checking
  whether a frame exists cannot tell the two clients apart, and the client exposes no game-type API to addons.
- The Options window and Edit Mode are built from data. Every row, section and dialog is a template filled from a
  definitions table, with its labels several frames deep and no global names.
- The shop, WoW Token redemption, secure transfer and the authenticator run in Blizzard's separate secure Lua state
  (`## UseSecureEnvironment: 1`). Addon code cannot read, hook or write their frames, even though a player can open
  them.

## Decision

1. **The window list is mechanical.** `wfj.dev.client_addons` resolves every addon from its TOC under ADR-029's rule,
   plus three more facts from the TOC headers: `standard` and `classic` do not include `camelot` (thirteen headers write
   `standard, camelot` where both are meant), `## AllowLoad: Glue` is the login screen, and `_Mainline.toc` is
   preferred. XML includes are followed. Its addon-level output, `pipeline/forever_addons.txt`, is committed.
   `pipeline/forever_addon_dispositions.txt` gives each `login` / `lod` addon one disposition with a reason.
   `tests/python/test_forever_windows.py` holds the two files together: nothing missing, nothing twice, nothing the
   resolver does not report. A new client build is re-resolved with `make forever-addons`, and any new addon fails the
   test until someone reads it. The per-file load set is reproducible from the tool (`--files`) and is not committed.

2. **The disposition set is closed:** `surface <names>`, `library`, `no-text`, `unreachable`, `no-content`,
   `planned` (the text is not handled yet and is left as the client shows it), `not-a-window`. The test enforces the
   evidence each one needs. An `unreachable` line cites a `path:line`, or says "no reference in the load set". A
   `no-content` line cites the entry point **and** the table evidence. An addon whose files a surface scans must be `surface`, and each
   surface name must be a `FOREVER_WINDOWS` key.
   - **`no-content` is separate from `unreachable`.** Covenant, garrison, azerite, archaeology, pet battle, solo-dungeon and
     Great Vault windows have live entry points on camelot: mainline event handlers (every one is registered on
     camelot, `blizzard_game/camelot/eventrouting.lua:22–26`), player interaction types, paper doll calls. What they
     lack is content. The Forever tables carry none of it: no Heart of Azeroth, no covenant ability, no quest between
     10,000 and 49,999. `unreachable` says the client has no way in. `no-content` says the server has nothing to show.
     They are proved from different sources, and a server change can break a `no-content` line but not an
     `unreachable` one. Each gets its own in-game question.
   - **`unreachable` and `no-content` are never used for size.** A big window with an entry point and content is a
     surface: every text is in scope on Forever.

3. **One surface module per window**, as in ADR-009 and ADR-029. An addon with several windows (`Blizzard_UIPanels_Game`:
   trade, loot, group loot, taxi, tabard, petition, guild registrar, dress-up, casting bar, map legend) has one module
   per window. One window spread over several addons (the professions family, the Options window) is one surface. Each
   module follows ADR-029's patterns: `Compat` candidates with dotted paths, post-hooks on the writers,
   pool walks keyed by widget, the load-on-demand wait, type guards, `only` restrictions and a `NEVER_TOUCH` list.

4. **`Labels.title(surface, frame, opts, recKey)` renders `SetTitle` titles.** It resolves
   `frame.TitleContainer.TitleText`, post-hooks `SetTitle` on the instance once, and re-shows through `Labels.show`
   with the surface's `only` list after every call. A frame with no `TitleContainer` is not hooked.
   Friends and Merchant moved onto it. Bags did not: its title needs a per-bag `only` set that `Labels.title`'s single
   `opts` does not carry. `make forever-titles` lists every `SetTitle(` site in the surface addons' load sets, and
   `pipeline/forever_titles.txt` gives each one a disposition: `key <KEY> <surface>`, `name`, `ruled` (`BANK`) or
   `dynamic`. The test fails on an unlisted site.

5. **A camelot marker for windows whose names exist on both clients** (removed by ADR-034). `WFJ.Camelot.present()`
   was true only when `PVPRankFrame` exists. That frame is created at login only by camelot
   (`blizzard_uipanels_game.toc:213–214` `[AllowLoadGameType camelot]`), in the same Blizzard addon as the
   shared-name windows, and that addon loads before any third-party addon. The windows whose frames Classic Era also
   ships (trade, taxi, tabard, petition, guild registrar, dress-up, casting bar, group loot, the Options window, Edit
   Mode, quick keybind mode, the minimap cluster and others) checked it before any `Compat` lookup, so their inits
   returned false on Classic Era.

6. **Data-built windows are walked with a required `only` list.** `UI/LabelTree.lua` walks a frame the client just
   filled and shows each FontString, Button and dropdown button through `Labels.show`. Records are keyed by widget,
   never by position. `opts.only` is required, so a walk only matches the keys its window shows (from
   `UI/SettingsKeys.lua`) and never the whole dictionary. The walk never enters an EditBox (its text is read back),
   never enters a `NEVER_TOUCH` widget or a frame `opts.skip` refuses (key buttons, previews, layout names), and stops
   at a fixed depth. It runs after the list's own initializer (`ScrollUtil.AddInitializedFrameCallback`), so the client's
   layout runs first. Non-GameTooltip tooltips (`SettingsTooltip`, `QuickKeybindTooltip`) go through
   `UI/TooltipLines.lua` the same way.

7. **Never-touch lists register before any window init.** Every module's `NEVER_TOUCH` list joins the registration
   pass in `Main.lua` (ADR-016 §15), before any window's `init`. So no surface can render a name another surface
   declared, whatever the init order. Their inits run after the ADR-029 windows, each under its own guard (ADR-025). A
   broken surface is disabled by removing its name from Main's `forever` list.

8. **A draft batch may record two models.** The batch that drafted these windows lists both drafting models in its
   provenance, joined by `+`. The drafting switched models part-way, and which model wrote which
   line was not tracked. A joined string is honest where one name would be false. `test_ui_keys.py`'s rule became "one
   model per draft batch" (the batch is still uniform), and every line is `machine`: a human review replaces it the same way
   whichever model wrote it.

9. **One English, one Japanese; homographs get per-surface Japanese.** The dictionary gives one English one Japanese
   (ADR-014). Five PvP scoreboard headers (`SCORE_DAMAGE_DONE` and four siblings) carry a line break in their English,
   so their Japanese must carry one too, while the same English without the break ships with a Japanese of its own.
   Other homographs (the auction house's Back, "Available", "Deposit"; the vehicle's "Exit") need a different
   Japanese per surface too. Per-surface Japanese is `UIStrings.OWN`, a key that owns its Japanese and answers only
   where a widget's `only` set names it ([ADR-037](037-staticpopup-dialogs-and-owned-keys.md)). The client-table
   families extend it: each restricted family is indexed on its own, so its Japanese may differ from a global
   string's or another family's of the same English (the barber shop's "Close" tusk style is 寄せ where the button is
   閉じる; [ADR-042](042-client-table-text-families.md) decision 4).

10. **Secure-environment windows are `not-a-window`.** The Store, the catalog shop and its refund / top-up flows, the
    embedded checkout, WoW Token redemption, secure transfer and the authenticator challenge are reachable, but addon
    code cannot hook them. They are recorded with their `UseSecureEnvironment` line and stay English. The same goes for
    the ping wheel (a `forbidden` scoped modifier). Addon code cannot run in the secure environment, so there is no
    route ([ADR-037](037-staticpopup-dialogs-and-owned-keys.md)).

## Consequences

- The window list cannot drift silently. A new Blizzard addon, or a changed TOC header, fails
  `test_forever_windows.py` until someone gives it a disposition with evidence.
- Every "no" is a checkable claim. Each `unreachable` and `no-content` addon has a "does this ever open?" line on the
  in-game checklist. If one opens, fixing it is a data edit plus one module.
- The addon carries about a hundred more surface modules. Init takes longer, but each module is guarded.
- `FOREVER_WINDOWS`, `ui_keys.txt` and `ui_exclusions.txt` grow with the windows; every excluded key has a reason.
- Titles have one code path, rather than a fourth copy of the per-surface title lookup.
- Mechanisms the source cannot prove stay unverified until the in-game pass: whether pool callbacks reach rows created
  later, whether Options rows keep their width, which flight map opens. Each degrades to English on a miss.
- Text these window surfaces do not cover is handled elsewhere: menu popup entries and HelpTips
  ([ADR-031](031-objective-lines-menus-and-helptips.md), [ADR-038](038-menus-callouts-and-composite-forms.md)),
  StaticPopups ([ADR-037](037-staticpopup-dialogs-and-owned-keys.md)), error and chat lines
  ([ADR-035](035-ui-errors-frame-surface.md)), the tutorial popup (ADR-016), and client-table text
  ([ADR-042](042-client-table-text-families.md): descriptions, achievement text, emote lines, category words, the
  Statistics tab, auction house categories, barber shop customization text, PvP stat columns, group finder categories,
  wardrobe set variant words and the UI widgets' lines). Mount / pet journal source and lore, Chromie Time, splash
  screens and party pose titles have no text on Forever; the generic trait tree is `unreachable`; set names and the
  group finder's dungeon, raid and zone names are names. The new player experience, the boost tutorial and the guide
  window never run on Forever. The secure-environment windows are out of reach.

## Alternatives considered

- **A candidate list of windows.** This is what ADR-029 had. It missed every window nobody named.
- **Scan every file in the extract.** It counts gated and login-screen files, and it cannot tell a reachable window
  from dead retail code.
- **Fold `no-content` into `unreachable`.** That would make the covenant and garrison lines false claims ("no entry
  point"), and it hides the one condition that could change: the server adding content.
- **A generic window-surface engine** driven by the dispositions file. That is a plugin system with one kind of
  plugin. Surfaces stay plain files; only the title code (fourth use) and the data-built walk (two windows) were
  extracted.
- **Tell the clients apart by `WOW_PROJECT_ID` or a build check.** The camelot load set reads no game-type API, so no
  source proves what either would return. A camelot-only frame in the same addon as the windows is a fact the TOC
  shows.
- **Name a two-model batch after one model.** That would be false for some lines.

## Related

- [Research: the Forever window sweep](../research/2026-09-19-forever-window-sweep.md)
- [ADR-029: camelot targets the mainline family](029-camelot-targets-the-mainline-family.md) ·
  [ADR-025: guarded surface init](025-guarded-surface-init-and-runtime-tooltip-path.md) ·
  [ADR-016: whole-window interface coverage](016-whole-window-interface-coverage.md) ·
  [ADR-015: UI text surfaces](015-ui-text-surfaces.md) ·
  [ADR-037: StaticPopup dialogs and owned keys](037-staticpopup-dialogs-and-owned-keys.md) ·
  [ADR-014: machine-drafted text and the UI dictionary](014-machine-drafted-text-and-ui-dictionary.md) ·
  [ADR-009: surfaces post-hook the writer](009-surfaces-post-hook-the-writer.md)
- [Addon modules](../architecture/addon-modules.md) · [Pipeline](../systems/pipeline.md) ·
  [Translation batches](../operations/translation-batches.md)
