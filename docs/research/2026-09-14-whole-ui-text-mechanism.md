# Research: How should the addon put Japanese on the whole game UI?

> Research done before the whole-UI work was built. The goal is the entire UI in Japanese except names, through one mechanism plus a dictionary rather than a hook per screen. This doc asks whether that mechanism is sound on Classic Era 1.15.9, and what must still be proven in-game before it is built.

- **Outcome:** the addon builds on the proven mechanism it already uses: targeted post-hooks on the client's own writers, one per surface (Option B's shape without its taint mistakes), over one UI dictionary. Code volume was not judged a cost worth trading proof for. Option C below stays the documented alternative for a later whole-UI step; it would need the in-game probe (P1 to P5) first. Recorded in [ADR-015](../adr/015-ui-text-surfaces.md).
- **Date:** 2026-09-14
- **Question:** Which mechanism translates Blizzard UI text (buttons, headers, labels, menus, tooltip structural lines) on the Classic client, keeping hold-the-modifier-for-live-English, the name policy and zero taint, and what is still unverified?
- **Sources:** Blizzard UI source for 1.15.9.69722 (Gethe/wow-ui-source `classic_era`, 2026-09-12). The Classic Era load set was resolved from the TOCs: 174 addons, 1,452 Lua files and 484 XML files. Counts below are over that set. Other sources: warcraft.wiki.gg API and taint pages; Townlong Yak's taint-log notes; wago.tools `GlobalStrings` @1.15.9.69722 (19,624 strings); and the source of the prior-art addons listed under Findings §5. Evidence tags: **[verified: source]**, **[likely: reason]**, **[unknown]**.

## Options
| Option | Pros | Cons |
|---|---|---|
| **A. Overwrite the global strings** (`_G.ACCEPT = "受諾"` at load) | Tiny code | **Taints secure readers.** `ChatFrameUtil.lua:720–735` reads `_G["SLASH_"..]` inside `secureexecuterange`, and `ActionButton.lua:626` compares against `RANGE_INDICATOR` in combat code [verified]. "When code sets global values, the resulting value has the taint of the execution path" [verified: wiki, Secure Execution and Tainting]. **Misses most text:** XML `text=` labels are set before any addon loads, and 645 StaticPopup fields plus 1,073 other table fields copy globals at file load [verified: grep]. **No live toggle.** The one production addon that shipped it (WoWeuCN-Interface v0) labelled it "blocks combat/tooltip functions" and removed it [verified: commit 8fcd019] |
| **B. A hook per Blizzard function / frame** (WowUkrainizer, the WoWLang family, our predecessors) | Each hook is precise; layout can be handled per frame | One hook per screen, which is the per-screen work this research set out to avoid. Coverage is limited to the frames someone wrote code for. Prior art shows these hooks drifting into taint when they touch Blizzard tables or replace functions (WowUkrainizer PRs #60, #103) [verified] |
| **C. Layered: widget-method post-hooks + static-label pass + tooltip hooks, over one dictionary** | One mechanism for every screen: new coverage is dictionary rows, not code. The live English passes through our hands, so hold-modifier restore is natural. Shipping today on 1.15.9 (WoWeuCN-Interface, zhCN, 2026-08) [verified] | Needs a curated dictionary and per-element exceptions. Three things are unverified in-game: fonts, per-call cost, and whether C-side writes reach the hooks (see Open questions) |

## Findings

### 1. How text reaches the screen on 1.15.9
| Path | Count | Reached by a method post-hook? |
|---|---|---|
| XML `text="GLOBAL"` on FontString / Button (957 attributes; 719 on concrete frames, 240 in templates) | 868 name a global | **No.** The XML loader applies them before addons run. About 73% of concrete labels never get a later Lua `SetText` [verified: script count; likely: at most 195 of 719 have one] |
| Lua `:SetText(` (1,932, plus 280 in XML scripts); `:SetText(GLOBAL)` 369 | | Yes [likely: method lookup is through the shared `__index` at call time] |
| `:SetFormattedText(` (144; 101 with a global template) | | Yes. The hook receives the template itself, so the lookup is exact |
| Pre-formatted (`SetText(format(GLOBAL, …))`, `GLOBAL:format(`), about 100; concatenated about 72 | | Seen, but only reverse template matching recovers the key |
| `:SetTextToFit(` (14; every entry in the new Menu system) | | Only if `SetTextToFit` is hooked too |
| `Button:SetText` / `SetFormattedText`: native, separate from FontString's (about 129 call sites) | | Only through the Button metatable. Whether the FontString hook sees it is [unknown] |
| Tooltip lines from C setters (`SetBagItem`, `SetHyperlink`, `SetSpellByID` …); `MessageFrame:AddMessage` (chat, UI errors); chat bubbles | | **No** [likely: C paths]. Tooltips keep `OnTooltipSet*` (ADR-009/010). `TooltipDataProcessor` is excluded on Vanilla [verified: `Blizzard_SharedXMLGame.toc:9`] |

- All FontStrings share one method table (`GetFontStringMetatable()`, on Classic Era since 1.14.4). The same is true of Buttons (`GetButtonMetatable`) [verified: wiki]. Blizzard itself calls `GetFontStringMetatable().__index.SetText(self, text)` (`SecureUtil.lua:33–61`), and its menu Compositor re-reads `originalMetatable.__index[key]` per call (`Compositor.lua:283`). A hook on that table is therefore seen by Blizzard-, XML- and addon-created FontStrings alike [likely]. Secure templates snapshot the *Frame* method table at load (`SecureTemplates.lua:4`); there is no FontString snapshot [verified].
- No jaJP locale exists anywhere: 11 locales, and `jaJP` does not appear in the Classic Era FrameXML [verified]. Blizzard's `SetupLocalization` is keyed to `UI_LOCALE` [verified: `LocalizationMachinery.lua`]. There is no supported route.

### 2. Taint
- `FontString:SetText` / `Button:SetText` are not protected (`AllowedWhenTainted`). The protected methods are layout ones: `SetPoint`, `SetSize`, `SetWidth` / `SetHeight`, `Button:Enable` / `Disable` [verified: 1.15.9 API docs].
- Taint lives in "global variables, local variables, table keys, widget script handler slots, and function closures", and the taint log does not trace widget properties [verified: Townlong Yak]. Text written to a region is therefore not a taint carrier [likely; no source says so outright]. **Corrected 2026-10-04:** wrong on Forever. Text and font written into a FontString come back tainted to the Blizzard code that measures it ([ADR-058](../adr/058-text-blizzard-measures-on-a-protected-path-stays-untouched.md)).
- `hooksecurefunc` runs the original untainted, then the hook [verified: wiki]. The real risks are Lua-side, and prior art shows both:
  - **Writing fields on Blizzard tables:** WowUkrainizer PR #103 wrote `SearchBox.instructionText`, and casting from the spellbook and action bars broke.
  - **Calling a Lua override of `SetText`:** `UIPanelButtonNoTooltipResizeToFitMixin:SetText` calls `self:MarkDirty()` (`SecureUIPanelTemplates.lua:231–234`), which writes a Blizzard field from tainted code [verified].
- **Rules that follow:**
  - Capture the raw C methods *before* hooking, and write only through them.
  - Keep all state (English, applied Japanese, font) in the addon's own weak-keyed table, never on a Blizzard object.
  - Replace no Blizzard function, and write no Blizzard field.
- Our hook runs *inside* secure updates of action buttons and unit frames (`ActionButton.lua:493–809`, `CompactUnitFrame.lua:857, 1095–1113`) [verified]. Macro names reach `ActionButton.Name` through `GetActionText`, so a macro named like a global string would be translated [verified]. Those regions go on a skip list.

### 3. What breaks when on-screen text stops being English
- **`GetText()` compared with English:**
  - Dropdown checkmarks: `Classic/UIDropDownMenu.lua:571, 791, 924`; line 822 copies the text back.
  - `CommunitiesList.lua:362` (`COMMUNITY_FINDER_FIND_COMMUNITY`).
  - `Blizzard_EngravingUI.lua:267` (`SEARCH`).
  - `ActionButton.lua:626, 1274` (`RANGE_INDICATOR` = "●", not a translation target).
  - The clock: `Blizzard_TimeManager.lua:367–372` sets text only when `GetText() ~= new`, so a translated clock re-sets its text every frame.
  - [verified] Each becomes a skip-list entry (dropdown list buttons, those widgets, the clock).
- **Width measured from text:** `GameDialog.lua:349, 572, 613` (size after `SetText`); `PanelTemplates_TabResize` on each tab's `OnShow` (`Classic/SharedUIPanelTemplates.lua:357–416, 266–268`); `SecureUIPanelTemplates.lua:213–220`; `NavigationBar.lua`; `FriendsFrame.xml:92` [verified].
  - A swap **inside the post-hook** lands before the caller measures, so layout fits the Japanese [likely].
  - A swap **after** layout (a deferred queue as WoWeuCN does, or a sweep on an already-shown frame) clips.
  - Hence: swap synchronously in the hook, and run the static-label pass *before* a frame's first show.
- **Other addons' text** goes through the same method table, and the hook cannot see the caller [verified: C_AddOnProfiler attributes by caller]. Only strings that exactly equal a curated dictionary entry change.

### 4. Cost
- Hot paths (29 `SetText` calls inside OnUpdate functions):
  - **Buff durations:** `BuffFrame.lua:1152` `SetFormattedText(SecondsToTimeAbbrev(t))`, every frame, per aura, up to 48 auras. This is the worst.
  - **Cast bar:** `CastingBarFrame.lua:852`, every frame while casting.
  - **StaticPopup timers:** `StaticPopup.lua:468–515`.
  - **FPS text:** every 0.25 s.
  - [verified]
- No measurement of a global `SetText` hook exists anywhere we could find [unknown]. The design target is a fast path of one interned-string table lookup that returns on a miss, with no `GetText()` (it allocates) and no pattern work on the hot path.
- Measure in-client with `debugprofilestop()` deltas and call counts inside the hook. `scriptProfile` + `GetFunctionCPUUsage` is also available on Classic Era [verified]. `C_AddOnProfiler` does not bill Blizzard-initiated calls to us [verified], so its numbers under-report the hook.

### 5. Prior art (source read at pinned commits)
| Project | Mechanism | Live toggle | Lessons |
|---|---|---|---|
| **WoWeuCN-Interface** (zhCN; **Classic Era 1.15.9**, no dependencies; qqytqqyt, 2026-08) | Post-hook FontString `SetText` / `SetFormattedText` on the shared metatable → queue; OnUpdate drains ≤ 200 per frame; 0.4 s region sweep out of combat; hooks `ShowUIPanel` / `StaticPopup_Show`. 18,340 official zhCN strings inverted English → Chinese; `%s` / `%d` templates compiled to anchored patterns bucketed by longest word (≤ 40 tries, ≤ 300 chars); skips forbidden / protected frames, EditBoxes, tooltips, the objective tracker, cast bars, item / spell / merchant name regions | None (`/reload`) | Global override removed. "Never translate item, gear and spell names" enforced with a region skip list. The deferred queue gives up layout for safety |
| **WowUkrainizer** (retail) | Per-frame hooks; hash of normalized English with numbers pulled out and restored in order | Quest panel only | Taint fixes all moved *away from writing Blizzard state*: PRs #60, #103, commit 07a41dd. AI-translated quests labelled in-game |
| **WoWLang family** (Arabic / Polish / Japanese …) | Per-frame `OnShow` hooks plus tickers; NBSP "already translated" marker | Quest panel only | Most commits are font and compatibility fixes (ElvUI `GetFont` nil, CraftSim) |
| **Our predecessors** (CTJT / CQJT) | Per-frame `SetFont` + `SetText`, no restore; replaced `GameTooltip.SetUnitAura` outright | Quest button only | Replacing tooltip methods is a known taint pattern; not carried forward |
No prior art restores the general UI live. Hold-modifier-for-English on every UI element would be new [verified: absent from all of the above].

### 6. Fonts: the largest unknown
- The enUS font family resolves to `FRIZQT__.TTF`, and FontFamily has no Japanese member, only roman, korean, simplifiedchinese, traditionalchinese and russian [verified: `Classic/GameFonts.xml:4–19`]. This project already had to `SetFont` the bundled IPA UI Gothic for kanji to render for the stale and missing markers [verified in-game].
- **Per-widget `SetFont` on apply** is what the addon does today, and it keeps English untouched. But buttons switch font objects on state (normal / highlight / disabled) in C [likely]. A Japanese button label could then fall back to FRIZQT and render as missing glyphs on hover [unknown].
- **Changing shared FontObjects** (`GameFontNormal`, `SystemFont_*`) survives state changes, and WowUkrainizer does it [verified]. But it re-renders every English string in the Japanese face too. The three font globals need a relog [verified: ElvUI source].
- WoWeuCN claims the client falls back to built-in CJK glyphs [unknown for enUS and for kana]. `Fonts\ARKai_T.ttf` loading on an enUS install is [unknown].
- Japanese has no spaces, so wrapping labels may need `SetNonSpaceWrap(true)` [verified: wiki].

## Recommendation
**Option C is the right mechanism.** A is ruled out by evidence, and B is the per-screen route with worse coverage. The shape:

1. **Dictionary.** Keyed by Blizzard global-string name (plus the few non-GlobalStrings sources such as `ItemSubClass`), with English from wago.tools @build and per-entry provenance. At load it builds `english → key` for exact strings and `template → key` for `%` strings. Curation is the name-policy guard: a name is never a row. A key whose English is shared ("Back") gets a context rule or stays out.
2. **Method post-hooks, synchronous.** Hook FontString `SetText` / `SetFormattedText` / `SetTextToFit` and Button `SetText` / `SetFormattedText` (CheckButton if its table differs):
   - Look up `english → key` (for `SetFormattedText`, the template → re-format the Japanese template with the same arguments). On a miss, return; that is the fast path.
   - On a hit: write through the raw captured C method, set the bundled font, and record `{english, font}` in a weak table.
   - Recursion guard. No Blizzard fields, no Lua overrides. A skip list covers the §2–§3 regions (action / unit frame names and hotkeys, dropdown list buttons, EditBoxes, the clock, the engraving and communities search widgets, cast bars, name regions).
3. **Static-label pass.** Walk regions once at `PLAYER_LOGIN` and on each Blizzard load-on-demand addon's `ADDON_LOADED`, i.e. before first show, so `OnShow` sizing measures the Japanese. Same write rules. Template-created frames are re-walked when their parent panel shows.
4. **Tooltips.** Structural lines are matched in the existing `OnTooltipSet*` hooks against the same dictionary (templates such as `ITEM_MIN_LEVEL`, `DURABILITY_TEMPLATE`, `ITEM_MOD_*`), as records on the tooltip surfaces (ADR-010). Numbers and names are passed through verbatim.
5. **Live English.** On modifier / area / master change, walk the weak table: restore English and font, or re-apply. Widths stay as last measured while the modifier is held; accept this, since it is what the translated tooltips already do.

**Gate before building the general hooks: a read-only in-game probe (about 10 minutes, Classic Era).** Everything above the fonts line is well-evidenced. These decide the rest:
| # | Check | Settles |
|---|---|---|
| P1 | `SetText("テスト漢字 受諾")` on a stock `GameFontNormal` FontString, no `SetFont`; then on a button, hover it and disable it | Whether per-widget fonts survive button state changes (§6) |
| P2 | `SetFont("Fonts\\ARKai_T.ttf", 14)` return value | Whether the client carries a CJK face on enUS |
| P3 | Count-only hooks (no replacement) on the five methods for 5 minutes of play: calls per second overall and on the worst path (buffs up, casting), and ms per 10k calls with a dictionary lookup | Per-call cost (§4) |
| P4 | Whether `Button:SetText` fires the FontString hook; whether C tooltip lines fire it; whether `getmetatable(CreateFrame("CheckButton")).__index == GetButtonMetatable().__index` | Which methods to hook (§1) |
| P5 | `/console taintLog 1`; hooks writing a harmless swap on one test string; then combat with action bars, a `/cast` macro and a dropdown; read `Logs/taint.log` | The taint claims in §2 |

If P1 shows missing glyphs on button states, the font plan falls back to (a) re-applying the font after the client's state change (hooking `OnEnter` / `OnLeave` / `OnDisable` per affected button template), or (b) a CJK-capable face set on the handful of shared button FontObjects, accepting English in that face on those buttons. Which fallback applies is recorded in the ADR.

**Feeds:** ADR-014 (dictionary keying + provenance for machine-drafted text) and ADR-015 (whole-UI text mechanism).
