# Research: Which strings do the always-visible windows show on Classic Era 1.15.9, and where can the addon hook them safely?

> Decisions are in [ADR-016](../adr/016-whole-window-interface-coverage.md). It builds on [whole-UI text mechanism](2026-09-14-whole-ui-text-mechanism.md), which chose targeted post-hooks (ADR-015).

- **Date:** 2026-09-14
- **Question:** For each window a player keeps open, answer four things so every string is translated or excluded with a reason:
  - which files load on Classic Era;
  - which global strings each window shows, on which widget and from which writer;
  - where a post-hook sees each write;
  - which hazards (taint, width, font, read-back, names) constrain it.
- **Sources:**
  - Blizzard UI source, Gethe/wow-ui-source `classic_era` at `33e177d9bf38d76d5c6c6e05d5da78db1899659a` ("1.15.9 (69722)"), pinned by `make ui-source` into `predecessors/wow-ui-source`;
  - wago.tools `GlobalStrings` and `SpellItemEnchantment` @1.15.9.69722.

  Paths are relative to `Interface/AddOns`. Tags: **[verified: file:line]**, **[likely: reason]**, **[unknown]**. Nothing was run in game; the [likely] / [unknown] items went to the in-game checklist in the [testing strategy](../testing/strategy.md).

## Options
| Option | Pros | Cons |
|---|---|---|
| **A. Hook each window's `OnShow` global** (`CharacterFrame_OnShow`, `MerchantFrame_OnShow`) | One hook per window | `function=` XML bindings hold the function value from load time. The global hook never fires from the script [likely: XML binding] (CharacterFrame.xml:255, PaperDollFrame.xml:742, BankFrame.xml:248, MerchantFrame.xml:526) |
| **B. Post-hook the leaf writers by name, show static labels at init, walk help tooltips by owner** | Every write is seen: the leaves are looked up at call time. Tabs measure the Japanese | One module per window; needs load-on-demand handling, plural / markup / composite matching, and never-touch lists |
| **C. Translate, then re-measure** (`PanelTemplates_TabResize`, `SetWidth`) | Correct widths after any toggle | Calls Blizzard layout code from addon code. `PanelTemplates_SetTab` / `UpdateTabs` write `frame.selectedTab`, read by secure item use [verified: ContainerFrame_Shared.lua:1341, 1449] |
| **D. `Menu.ModifyMenu` for dropdown popups** | The selection text would follow | Runs inside `securecallfunction` in Blizzard's initializers (Blizzard_Menu/Menu.lua:2598–2627); `AddInitializer` is a grey area under the no-field-writes rule |

## Findings

### 1. Cross-cutting
- **Load timing.** Blizzard_CharacterFrame and Blizzard_UIPanels_Game_Classic load first (`LoadFirst: 1`, no `LoadOnDemand`), so XML text and OnLoad writes have run before the addon [verified: both TOCs]. `Blizzard_TalentUI` and `Blizzard_TrainerUI` are load-on-demand [verified: Blizzard_TalentUI_Vanilla.toc:2, Blizzard_TrainerUI.toc:2; Blizzard_UIParent/Vanilla/UIParent.lua:209–250, Shared/UIParent.lua:265]. So is `Blizzard_RaidUI`: `RaidFrame_LoadUI` runs on `PLAYER_LOGIN` in a raid and on `GROUP_ROSTER_UPDATE` [verified: Blizzard_RaidFrame/Classic/RaidFrame.lua:180–189; Shared/UIParent.lua:296]. File choice follows `AllowLoadGameType`: `[Family]` → `Classic\`, `[Game]` → `Vanilla\`.
- **Hook binding.**
  - `<OnShow function="X"/>` keeps X's value, so hook the leaves X calls by name, or use `HookScript`.
  - `method="X"` and `self:X()` look the method up at call time.
  - Mixins are copied onto frames at creation, so hook the frame (`SpellBookFrame`, `OpenAllMail`), not the mixin.
  - `PlayerTalentFrame.updateFunction` is captured at load (Blizzard_TalentUI.lua:157); `TalentFrame_Update` is the hookable global.
- **Captured tooltip refreshes.** `GameTooltip_OnUpdate` calls `owner:UpdateTooltip()` every 0.2 s [verified: Blizzard_GameTooltip/Classic/GameTooltip.lua:440–465]. The owners' `UpdateTooltip` values were captured before any addon loaded:
  - `PaperDollItemSlotButton_OnEnter` (Vanilla/PaperDollFrame.lua:717);
  - `BagSlotButton_OnEnter` (MainMenuBarBagButtons.lua:240);
  - `BankFrameItemButton_OnEnter` (BankFrame.lua:13).

  A post-hook on `GameTooltip:SetText` filtered by `GetOwner()` sees these rewrites; a global hook does not.
- **Lua-built tooltips.** Help tooltips use `SetText` / `AddLine` / `GameTooltip_AddNewbieTip` [verified: GameTooltip.lua:468–484]. No `OnTooltipSet*` fires, and line 1 is a title, not a name. `GameTooltip_AddNewbieTip` shows the help sentence only with `showNewbieTips` = 1 (default [unknown]). With `noNormalText` = 1 it shows nothing otherwise. `TooltipDataProcessor` is excluded on Vanilla.
- **Tabs.**
  - `CharacterFrameTabButtonTemplate` (Character, Merchant, Mail, Friends tabs) runs `PanelTemplates_TabResize(self, 0, nil, 36, maxTabWidth or 88)` on `OnShow` and `DISPLAY_SIZE_CHANGED` [verified: Blizzard_FrameXML/Classic/CharacterFrameTemplates.xml:74–87].
  - `CharacterFrame_TabBoundsCheck` shrinks the widest Character tab (Vanilla/CharacterFrame.lua:135–163).
  - `FriendsTabHeaderTab1/2` (TabButtonTemplate) size only at OnLoad (FriendsFrame.xml:1160–1163), and `FriendsTabHeader_ResizeTabs` only when truncated (FriendsFrame.lua:603–605).
  - `PanelTemplates_SelectTab` calls `tab:Disable()` then `SetDisabledFontObject`, after an `OnDisable` re-apply. `DeselectTab` / `SetDisabledTabState` / `UpdateTabs` swap font objects the same way [verified: Blizzard_SharedXML/Classic/SharedUIPanelTemplates.lua:458–546].
- **Taint.**
  - `SetText` / `SetFormattedText` / `SetFont` on a FontString are not protected. `SetPoint` / `SetSize` / `SetWidth` and `Button:Enable` / `Disable` are [verified: 1.15.9 API docs].
  - The carriers are Lua field writes on Blizzard tables: `frame.selectedTab` (read inside `C_Container.UseContainerItem` paths, ContainerFrame_Shared.lua:1341, 1449), `SpellBookFrame.bookType` (read before `CastSpell`, Vanilla/SpellBookFrame.lua:186–191), a dropdown's `self.text` (Blizzard_Menu/MenuTemplates.lua:526–540), and `UIPanelWindows`.
  - `SpellBookFrame:Update()` and `SpellButton:UpdateButton()` call `Enable` / `Disable` on protected buttons (Vanilla/SpellBookFrame.lua:246, 252).
  - `hooksecurefunc(frame, "Method")` stores a wrapper on the frame. It writes no field Blizzard reads.
- **Scroll boxes.** `ScrollUtil.AddInitializedFrameCallback(box, cb, owner, true)` fires after each row initializer, including rows acquired while scrolling [verified: Blizzard_SharedXML/Shared/Scroll/ScrollUtil.lua:21–30, ScrollBoxListView.lua:383–396]. The iterate-existing pass calls `cb(frame, elementData)`; later events call `cb(owner, frame, elementData)` [verified: ScrollBoxListView.lua:136–145].
- **Dropdowns.** Scoped windows use the Menu-system `DropdownButton`, never `UIDropDownMenu`. The button text is rewritten in `UpdateText` on every selection and assignment [verified: MenuTemplates.lua:530–540, 612–644].
- **Composites and names.**
  - `MicroButtonTooltipText` returns `text .. " |cffffd200(KEY)|r"` [verified: Blizzard_MicroMenu/Classic/MainMenuBarMicroButtons.lua:41–48].
  - Paperdoll stat labels are `SPELL_STATi_NAME .. ":"`.
  - `PLAYER_LEVEL` "Level %d %s %s" carries race (possibly two words) and class.
  - `GUILD_TITLE_TEMPLATE` "%s of %s" joins two free-text names.
  - `WhoFrameTotals` is two templates joined by two spaces.
  - Mail expiry is `SecondsToTime` with up to two terms (Blizzard_SharedXML/TimeUtil.lua:309–371).

### 2. Per window

#### Character sheet, pet (surfaces `character`, `character.static`)
- **Load:** Vanilla/CharacterFrame.*, PaperDollFrame.*, PetPaperDollFrame.*, Blizzard_FrameXML/Classic/CharacterFrameTemplates.xml.
- **Static:**
  - `CharacterFrameTab1..5` (CharacterFrame.xml:192–240);
  - `CharacterStatFrame1..5Label` `SPELL_STATi_NAME:` and the armor / attack / power / damage / ranged labels (PaperDollFrame.xml:316–437);
  - pet stat and attack labels, `PetTrainingPointLabel`, `PetPaperDollCloseButton` (PetPaperDollFrame.xml:96, 278, 347–492).
- **Writers:**
  - `PaperDollFrame_SetLevel` → `CharacterLevelText` `PLAYER_LEVEL` (PaperDollFrame.lua:90–92);
  - `PaperDollFrame_UpdateStats` → ranged `NOT_APPLICABLE` (lua:472, 508, 538);
  - `PetPaperDollFrame_Update` → pet stat labels, rewritten every update (PetPaperDollFrame.lua:145).
- **Help:**
  - `PaperDollStatTooltip` (lua:670–681): line 1 `|cffffffff<NAME> <n>|r`, line 2 `<CLASS>_<STAT>_TOOLTIP` / `DEFAULT_*`;
  - resistances `RESISTANCE_TOOLTIP_SUBTEXT` with nested type and rating words (lua:202–233);
  - damage hovers (lua:432–448, 601–611);
  - empty slots `<SLOT>SLOT` (lua:868–886);
  - tab hovers via `MicroButtonTooltipText`.
- **Hazards:** tab widths (≤ 88 px, bounds check); stat rows 104 px with the value anchored right (PaperDollFrame.xml:41–68); the pet XP bar "XP a / b" (TextStatusBar.lua:172, 199); `PetLevelText` = `UNIT_LEVEL_TEMPLATE .. " " .. family` (PetPaperDollFrame.lua:63).
- **Chosen:** static + leaf hooks + help owners. Guild line, names, loyalty and pet level are never-touch. Stat hover line 1 uses `wrapped` around a `number` label.

#### Reputation, skills, honor (`reputation`, `skills`, `honor`)
- **Reputation** (Vanilla/ReputationFrame.*, not Classic/ReputationFrame.lua).
  - Static: Faction / Standing labels and three checkbox texts (xml:264, 269, 736, 787, 817).
  - `ReputationFrame_Update` writes `ReputationBar1..15FactionStanding` from `GetText("FACTION_STANDING_LABEL"..id, gender)` (lua:54–57). Header rows are faction names except possibly "Inactive" / "Other" [unknown].
  - Hazard: the bar's `OnEnter` writes numbers and `OnLeave` writes back its cached English (xml:186–199).
  - Chosen: `HookScript` on both, headers restricted to `FACTION_INACTIVE` / `FACTION_OTHER`.
- **Skills** (Classic/SkillFrame.*).
  - Static: All, Close (xml:264, 289).
  - `SkillFrame_UpdateSkills` writes `LEARN_SKILL_TEMPLATE` rows (lua:121); every other row is a skill name.
  - `LEVEL_GAINED` never shows: lua:129 formats the undefined `skillLevel`.
  - Width hazard: `SkillFrameExpandButtonFrame` is sized from the English "All" at OnLoad (xml:284–286).
- **Honor** (Vanilla/HonorFrame.* + Classic/HonorFrame_Shared.lua + HonorFrameTemplates.xml).
  - Static: period titles and row texts (HonorFrame.xml:79–99, Templates.xml:22–126).
  - `HonorFrame_SetLevel` (`PLAYER_LEVEL`); `HonorFrame_Update` (`NONE` fallback), which runs on events only, never on OnShow (Shared.lua:15–25, 63–74).
  - Hazard: `HonorFrameCurrentPVPRank` "(" .. RANK .. " " .. n .. ")" is concatenated, and the title is re-anchored from its width (Shared.lua:75, 95). Left English.

#### Spellbook, talents, trainer (`spellbook`, `talents`, `trainer`)
- **Spellbook** (Classic/SpellBookFrame.lua + Vanilla/SpellBookFrame.*, at login).
  - `SpellBookFrame:Update` writes the title (`SPELLBOOK` / `PET_TYPE_<token>`), tab text and `PAGE_NUMBER` (Vanilla lua:58–127, 161).
  - `ShowAllSpellRanksCheckbox` has its own mixin copy and calls `UpdatePages` (xml:256–276).
  - Two FontStrings are named `SpellBookPageText` (xml:180, 213); the global is the one written.
  - `UpdateButton` writes `SubSpellName` "" and then the subtext inside `ContinueOnSpellLoad`, now or later (lua:208–282).
  - **Chosen:** a `SetText` post-hook on each `SpellButtonNSubSpellName`, not our own `ContinueOnSpellLoad`. `AddCallback` writes Blizzard's shared `SpellEventListener.callbacks` (Blizzard_ObjectAPI/Classic/Spell.lua:51–57, 89–93), and a later secure `UpdateButton` reading it would [likely] run tainted. `SpellButtonTemplate` is `SecureFrameTemplate protected` (xml:69).
- **Talents** (load-on-demand).
  - Static: Close, Activate (width `GetTextWidth()+40` at OnLoad, Shared.lua:216–218), Reset, Learn, status (Blizzard_TalentUI.xml:71–218).
  - `TalentFrame_Update` is also run by `InspectTalentFrame`, so it is filtered to `PlayerTalentFrame`. It writes `UNSPENT_TALENT_POINTS` (TalentFrameBase.lua:304) and `MASTERY_POINTS_SPENT` (lua:528). Both arrive with a colour-wrapped number, so the `%s` must allow `|c`.
  - `PlayerTalentFrame_PostUpdateActiveSpec` is called by name (Shared.lua:120–122).
  - The talent tooltip is client-built through `GameTooltip:SetTalent` (lua:385, 390–404) and refreshed via `UpdateTooltip`. Its exact Era lines are [unknown].
  - Tree tabs are names.
- **Trainer** (load-on-demand).
  - Static: Train, Exit, All, Cost: (Blizzard_TrainerUI.xml:162, 388, 474, 491).
  - `ClassTrainer_SetSelection` / `ClassTrainerFrame_Update` write `PARENS_TEMPLATE` subtexts (lua:196–236, 323–371).
  - The filter dropdown writes `FILTER` in `UpdateText` (lua:67–69).
  - `ClassTrainerSkillRequirements` = `REQUIRES_LABEL .. " " ..` a `", "`-joined list of level, skill-rank and ability items (lua:376–427).
  - `TRAINER_PET_SPELL_LABEL` is appended to `ClassTrainerSkillName:GetText()` (lua:470).
  - **Chosen:** subtexts through the `entry` kind; the requirements line through the `list` label form (level and skill-rank items in Japanese, ability names as shown); the pet suffix left English.

#### Gossip chrome, merchant, bank, bags (`gossip`, `merchant`, `bank`, `bags`)
- **Gossip** (Shared/GossipFrameShared.* + Classic/GossipFrame.*).
  - The only chrome word is Goodbye (GossipFrame.xml:48–58, fixed 78×22). The title is the NPC name (GossipFrameShared.lua:286).
  - Quest rows are pooled ScrollBox buttons written with `IGNORED_` / `TRIVIAL_` / `NORMAL_QUEST_DISPLAY` around the title (lua:27–42).
  - Row height is measured in English (lua:124–140); the Japanese suffix is shorter.
  - **Chosen:** scroll-box subscription, suffix templates only, title a `text` capture.
- **Merchant** (Vanilla/MerchantFrame.*).
  - Static: tabs (xml:488, 505), `MerchantRepairText` (xml:118), unnamed Prev / Next regions (xml:432–487).
  - `MerchantFrame_UpdateMerchantInfo` writes `PAGE_NUMBER` and the NPC name; `_UpdateBuybackInfo` writes `MERCHANT_BUYBACK` into the same `MerchantNameText` (lua:184–190, 415–416).
  - Repair buttons build inline tooltips (xml:202–281).
  - `MerchantGuildBankRepairButton` is hidden and never shown on Era.
- **Bank** (Vanilla/BankFrame.*).
  - Static: unnamed "Item Slots" / "Bag Slots" / purchase question regions (xml:116–133, 187–220); `BankFrameSlotCost`; `BankFramePurchaseButton`.
  - The purchase button is nested with `virtual="true"` (xml:209), so whether the global exists is [unknown].
  - Bag-slot tooltips come from `button.tooltipText` via `BankFrameItemButton_OnEnter` (lua:39–68, 206–225).
  - The title is the NPC name.
- **Bags** (Vanilla/ContainerFrame.lua + Classic/ContainerFrame_Shared.lua + MainMenuBarBagButtons).
  - `ContainerFrame_GenerateFrame` writes the title: `KEYRING` for the keyring id, else `C_Container.GetBagName(id)` (ContainerFrame_Shared.lua:942–947). Only id 0 ("Backpack" [likely]) and the keyring are words.
  - Backpack and portrait buttons: `SetText(title)` + `AppendText(binding)` + `Show` (MainMenuBarBagButtons.xml:94–102, ContainerFrame_Shared.lua:1479–1510). Whether `AppendText` appends to the current or original text is [unknown].
  - `BagItemSearchBox` is an EditBox with an empty Vanilla updater.
  - `BagHelpBox` tutorials [likely] never show.

#### Mail (`mail`, `mail.static`)
- **Load:** Classic/MailFrame.* (LoadFirst).
- **Static:**
  - titles, tabs, inbox-full, Open All;
  - unnamed To: / Subject: / Postage: regions and inbox Prev / Next (xml:392–642);
  - radio labels, Cancel / Send, From:, Report Player, Close / Reply, invoice labels (xml:102–1257).
- **Writers:**
  - `InboxFrame_Update` → `MailItem1..7ExpireTime`: green `DAYS_ABBR` + space, or red `SecondsToTime` (lua:222–228);
  - `OpenMail_Update` → attachment text, Delete / Return, invoice (lua:513–618, 665–669, 736–738). Its item and player labels are `ITEM_SOLD_COLON .. " " .. name`;
  - `SendMailRadioButton_OnClick` → `SendMailMoneyText` (lua:1051–1062);
  - `SendMailFrame` inline `OnShow` → COD error (xml:808–815);
  - `OpenAllMail:StartOpening` / `StopOpening` on the frame (lua:1113–1129).
- **Read-back:** `OpenMail_Reply` copies `OpenMailSender.Name` and `OpenMailSubject` with `GetText` (lua:771–779); mail EditBoxes are compared and sent (lua:865, 914–922, 1021–1025).
- **Hazards:**
  - `OpenMailAttachmentText` is centred from its width right after `SetText` (lua:671);
  - `InboxTooMuchMail` is sized at OnLoad (xml:338–340);
  - the inbox row's `OnUpdate` re-runs its tooltip every frame (xml:151–155).

#### Friends, who, guild, raid (`friends`, `friends.guild`, `raid`)
- **Friends / who** (Classic/FriendsFrame.*).
  - Static: tabs (xml:3942–4005), header tabs (xml:1156–1179), buttons, ignore headers (IgnoreListFrame OnLoad), who column headers, and `WhoFrameEditBox.Instructions` ← `SEARCH` (InputBoxTemplates.xml:29–31).
  - `FriendsFrame_Update` writes the title; tab 3 writes the guild name (lua:450–499).
  - The scroll frame stores `FriendsFrame_UpdateFriends` (lua:289), so hook `FriendsFrame_UpdateFriendButton` (lua:1359–1578) for `button.info` (Offline, `BNET_LAST_ONLINE_TIME` with a nested `LASTONLINE_*`) and the pooled invite Accept buttons.
  - `WhoList_Update` → the two-space `WhoFrameTotals` (lua:911–915).
- **Guild** (the same files).
  - `GuildFrame` is always built. `useClassicGuildUI` only decides whether the tab is offered (lua:3303–3322); otherwise the guild UI is Blizzard_Communities.
  - `GuildStatus_Update` writes `GuildFrameTotals` from `GetText("GUILD_TOTAL", nil, n)` (a quoted name the scanner misses), the Online column and member detail (lua:2894–3286).
  - Never-touch: `GuildInfoEditBox` (saved to the server, xml:3433) and `GuildControlWithdrawGoldEditBox` (compared with `UNLIMITED`, xml:2873, lua:2682).
  - The rename alert takes `SetFontObject` (lua:3348, 3359).
- **Raid** (Classic/RaidFrame.* + load-on-demand Blizzard_RaidUI).
  - Static: labels (RaidFrame.xml:176–278).
  - Saved-instance rows: ScrollBox, `SecondsToTime(reset, true, nil, 3)` or `|cff808080Expired|r` (RaidFrame.lua:32–94).
  - RaidUI: `GROUP .. " " .. n` labels (Blizzard_RaidUI.xml:331), unnamed Empty regions (xml:252–265), Ready Check (xml:735).
  - `RaidGroupButtonNClass:GetText()` is passed back as a pullout's class (xml:177).
  - Pullout labels are built by `RaidPullout_GeneratePulloutFrame`, whose hook does not receive the frame.

#### Micro menu and bars (`help`)
- **Micro buttons.** The Vanilla menu places nine (Blizzard_MicroMenu/Vanilla/MicroMenuContainerOverrides.lua:3–13). The inline `MicroButton_OnEnter` calls `GameTooltip_AddNewbieTip` with a binding-suffixed title, and when disabled a reason line (MainMenuBarMicroButtons.lua:54–70). `FEATURE_BECOMES_AVAILABLE_AT_LEVEL` needs `minLevel`, which no Vanilla button has (lua:61–63).
- **Main Menu performance tooltip.** Rebuilt about once a second from `OnUpdate` (lua:1009–1027; Blizzard_PerformanceBar/PerformanceBar.lua:52–198). Owners are the button and the latency frame, whose `OnUpdate` passes the frame (Blizzard_ActionBar/Classic/MainMenuBar.xml:141–175).
- **XP exhaustion tick.** An unnamed button reached through the status-bar container's bars (ExpBarOverrides.lua:20–42). Its body is `NEWBIE_TOOLTIP_XPBAR .. "\n\n" .. EXHAUST_TOOLTIP1`, one line.
- **Pet bar.** With UberTooltips off: `SetText(_G[token])` + `" |cffffd200 (Ctrl-1)|r"`-style suffix (Shared/PetActionBar.lua:296–326). With it on, the C setter `SetPetAction` writes the tooltip [unknown].
- **Possess cancel** (Shared/PossessActionBar.lua:92–106).
- **LFG minimap button** (Blizzard_GroupFinder/Classic/LFGFrame_Minimap_Vanilla.lua:31–124).
- **Quest log help.** Abandon / Share / Track (Vanilla/QuestLogFrame.xml:315–512).

### 3. Tooltip lines left open by the mechanism research
- **`ITEM_MOD_*_SHORT`.** No Classic Era UI source writes them (grep), and "Fire Spell Damage" is not a GlobalStrings value. Random-suffix and enchant lines are the enchantment's own display text: `SpellItemEnchantment.Name_lang` [likely until checked in game]. The stat-shaped rows (`[+-]\d+ words`) became 944 `SpellItemEnchantment:<id>` keys, under the 1,500-string stop point. Names such as "Crusader" and composites such as "+2 Stamina +2 Spirit" do not match.
- **`REPAIR_COST`.** A tooltip `AddLine` after the item setter in repair mode (PaperDollFrame.lua:880, ContainerFrame_Shared.lua:1448).
- **`HONOR`.** It is `CharacterFrameTab5` (CharacterFrame.xml:240–251).
- **`MINIMUM` / `MAXIMUM`.** Money lines (GameTooltip.lua:303–304).
- **`ITEM_SOLD_COLON`.** A mail invoice label.
- **Cooldown durations.** Which duration template the C client prints inside `ITEM_COOLDOWN_TIME` / `_TOTAL` is not in the Lua source [unknown].

### 4. Inventory method
- `pipeline/wfj/dev/ui_inventory.py` scans each surface's files for `text="KEY"`, `value="KEY" type="global"`, bare upper-case identifiers and `..NAME..` concatenations. It adds `DYNAMIC` families for names built at run time (`_G["SPELL_STAT"..i.."_NAME"]`, `GetText("FACTION_STANDING_LABEL"..id)`, quoted `GetText("GUILD_TOTAL")`, the `SEARCH` template key).
- Result at the pinned commit: 19 surfaces, 1,185 distinct keys (`pipeline/ui_inventory.txt`, 1,259 lines). 499 exclusions carry reasons.
- Scanner gaps found and fixed: `..NAME..` (mail `BUYOUT` / `HIGH_BIDDER`), `GUILD_TOTAL`, `SEARCH`.
- Gap left: `TRAINER_PET_SPELL_LABEL` is appended through `GetText()` (excluded as a name composite). `LFG_BUTTON`'s Era writer is outside the listed files.

## Recommendation
Option B, recorded in [ADR-016](../adr/016-whole-window-interface-coverage.md):
- one module per window over `Labels` / `UIStrings`;
- static labels shown at init;
- leaf-writer post-hooks;
- `HelpTooltip` walking by registered owner, hooked on `GameTooltip:SetText` / `AppendText` / `Show`;
- `LoadOnDemand` for the three LoD addons;
- tab-font hooks;
- `Labels.dropdown`;
- scroll-box subscriptions;
- key-restricted matching and never-touch lists for name and read-back widgets;
- no layout calls and no Blizzard field writes, enforced by `tests/python/test_forbidden_calls.py`.

Options C and D stay rejected. Menu popups, StaticPopup dialogs, spell subtext from the client tables and the Communities guild UI were left out of this pass. Every [likely] / [unknown] above is an item on the in-game checklist ([testing strategy](../testing/strategy.md)).
