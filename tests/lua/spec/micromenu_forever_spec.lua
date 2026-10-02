-- The always-visible chrome on the Forever client: the mainline micro menu (every button it has, titles and
-- disabled reasons Japanese, MainMenuMicroButton as the latency owner) and the game menu's Forever-only words
-- (LOG_OUT, GAMEMENU_EXTERNALEVENT, GAME_MENU_SHOW_REWARDS); the pet and possess bars' help tooltips and the
-- HelpTooltip walk rules they pin. Replays: stub_micromenu.installForever, Stub.installGameMenu.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local MM = require("tests.lua.spec.stub_micromenu")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/TimeLine.lua" -- the tooltip surface reads its time lines
FILES[#FILES + 1] = "UI/Tooltip.lua" -- only to prove the item tooltip's records survive a help pass
FILES[#FILES + 1] = "UI/MicroMenu.lua"
FILES[#FILES + 1] = "UI/GameMenu.lua"

-- key → { English (Forever GlobalStrings), Japanese (fixture) }
local UI = {
  CHARACTER_BUTTON = { "Character Info", "キャラクター情報" },
  PROFESSIONS_BUTTON = { "Professions", "専門技能" },
  PLAYERSPELLS_BUTTON = { "Talents & Spellbook", "才能と呪文書" },
  SPELLBOOK_ABILITIES_BUTTON = { "Spellbook & Abilities", "呪文書&アビリティ" },
  ACHIEVEMENT_BUTTON = { "Achievements", "アチーブメント" },
  LEGACY_BUTTON = { "Legacy", "レガシー" },
  QUESTLOG_BUTTON = { "Quest Log", "クエストログ" },
  HOUSING_MICRO_BUTTON = { "Housing Dashboard", "ハウジングダッシュボード" },
  GUILD = { "Guild", "ギルド" },
  DUNGEONS_BUTTON = { "Group Finder", "グループ検索" },
  COLLECTIONS = { "Collections", "コレクション" },
  ADVENTURE_JOURNAL = { "Adventure Guide", "冒険ガイド" },
  BLIZZARD_STORE = { "Shop", "ショップ" },
  MAINMENU_BUTTON = { "Game Menu", "ゲームメニュー" },
  ERR_RESTRICTED_ACCOUNT_TRIAL = { "Free Trial accounts cannot perform that action",
    "無料トライアルアカウントではその操作はできません" },
  MAINMENUBAR_FPS_LABEL = { "Framerate: %.0f fps", "フレームレート: %.0f fps" },
  -- the rest of the performance tooltip's labels the replay formats (Forever English)
  MAINMENUBAR_LATENCY_LABEL = { "Latency:\n%.0f ms (home)\n%.0f ms (world)",
    "レイテンシ:\n%.0f ms (ホーム)\n%.0f ms (ワールド)" },
  -- the latency help line, Forever English and the shipped Japanese
  NEWBIE_TOOLTIP_LATENCY = { "The time it takes to talk with the game server. Consistently high (red) latencies may "
    .. "indicate a problem with your Internet connection.", "ゲームサーバーとの通信にかかる時間です。レイテンシが常に高い"
    .. "(赤色の)場合は、インターネット接続に問題がある可能性があります。" },
  MAINMENUBAR_COMMUNICATION_PROTOCOL_LABEL = { "Communication Protocol:\nHome: %s\nWorld: %s",
    "通信プロトコル:\nホーム: %s\nワールド: %s" },
  MAINMENUBAR_BANDWIDTH_LABEL = { "Bandwidth %d Mbps", "帯域幅 %d Mbps" },
  MAINMENUBAR_DOWNLOAD_PERCENT_LABEL = { "Download %d %% complete", "ダウンロード済み %d %%" },
  TOTAL_MEM_MB_ABBR = { "AddOn Memory: %.2f MB", "アドオンメモリ: %.2f MB" },
  -- the XP bar's own text and disabled reasons (Forever GlobalStrings @1.60.1.69913)
  XP_STATUS_BAR_TEXT = { "XP: %d/%d", "経験値: %d/%d" },
  FEATURE_NOT_YET_AVAILABLE = { "This feature is not yet available.", "この機能はまだ利用できません。" },
  LEGACY_MICRO_BUTTON_LOCKED_TOOLTIP = { "Legacy is locked.", "レガシーはロックされています。" },
  -- the exhaustion tick tooltip (mainline/expbaroverrides.lua:20–55)
  EXHAUST_TOOLTIP1 = { "|cffffd200%s|r\n|cffffffff%d%% of normal experience\ngained from monsters.|r",
    "|cffffd200%s|r\n|cffffffff通常の%d%%の経験値を\nモンスターから獲得|r" },
  EXHAUST_TOOLTIP2 = { "\n|cffff0000You should rest at an Inn.|r", "\n|cffff0000宿屋で休息しましょう。|r" },
  XP_TEXT_BANKED_XP_HEADER = { "Banked XP", "蓄積経験値" },
  TRIAL_CAP_BANKED_XP_TOOLTIP = { "You have earned XP that exceeds your level cap.  Buy the game to apply your banked "
    .. "XP.", "レベル上限を超える経験値を獲得しました。ゲームを購入すると蓄積した経験値が反映されます。" },
  -- the game menu (Forever blizzard_gamemenu/shared/gamemenuframe.lua:181, 192, 225, 268–271, 284–286)
  GAMEMENU_EXTERNALEVENT = { "Activities", "アクティビティ" },
  GAMEMENU_OPTIONS = { "Options", "オプション" },
  GAME_MENU_SHOW_REWARDS = { "Rewards", "報酬" },
  LOG_OUT = { "Log Out", "ログアウト" },
  EXIT_GAME = { "Exit Game", "ゲーム終了" },
  RETURN_TO_GAME = { "Return to Game", "ゲームに戻る" },
  -- the pet and possess bars
  PET_ACTION_ATTACK = { "Attack", "攻撃" }, PET_ACTION_FOLLOW = { "Follow", "追従" }, PET_ACTION_WAIT = { "Stay", "待機" },
  PET_MODE_AGGRESSIVE = { "Aggressive", "積極的" }, PET_MODE_DEFENSIVE = { "Defensive", "防御的" },
  PET_MODE_PASSIVE = { "Passive", "消極的" },
  CANCEL = { "Cancel", "キャンセル" },
  NEWBIE_TOOLTIP_QUESTLOG = { "A list of all the active quests you currently have.", "現在受注しているクエストの一覧です。" },
  ITEM_BIND_ON_EQUIP = { "Binds when equipped", "装備時にソウルバウンド" },
}
local function ja(key) return UI[key][2] end
local function en(key) return UI[key][1] end

describe("the Forever micro menu and game menu", function()
  local WFJ, tt

  local function left(i) return _G["GameTooltipTextLeft" .. i] end
  local function tipLines()
    local out = {}
    for i = 1, tt:NumLines() do out[i] = left(i):GetText() end
    return out
  end
  local function records() return WFJ.SurfaceState.count("help") end
  local function lineOf(text)
    for i = 1, tt:NumLines() do if left(i):GetText() == text then return i end end
    return nil
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    MM.installForever()
    WFJ.Tooltip.init()
    WFJ.MicroMenu.init()
    tt = _G.GameTooltip
  end)

  after_each(function() H.uiTeardown() end)

  it("registers every Forever micro button that exists, and MainMenuMicroButton as the latency owner", function()
    for _, spec in ipairs(MM.FOREVER_MICRO) do
      assert.is_true(WFJ.HelpTooltip.registered(_G[spec[1]]), spec[1])
    end
    local latency = {}
    for _, name in ipairs(WFJ.MicroMenu.LATENCY_OWNERS) do latency[name] = true end
    assert.is_true(latency.MainMenuMicroButton)
  end)

  it("MainMenuMicroButton, a micro button and the latency owner, is registered once", function()
    local W = H.loadChunks(FILES)
    H.uiSetup(W, UI)
    local calls, register = {}, W.HelpTooltip.register
    W.HelpTooltip.register = function(owner, opts)
      calls[owner] = (calls[owner] or 0) + 1
      return register(owner, opts)
    end
    local n = W.MicroMenu.init()
    assert.are.equal(1, calls[_G.MainMenuMicroButton])
    local total = 0
    for _, c in pairs(calls) do total = total + c end
    assert.are.equal(total, n)
  end)

  local function hoverAll(check)
    for _, spec in ipairs(MM.FOREVER_MICRO) do
      local name, titleKey, action = spec[1], spec[2], spec[3]
      if name ~= "MainMenuMicroButton" then -- its tooltip is the performance rebuild (below)
        local key = action and MM.bindings[action]
        if check(titleKey, key) then
          MM.hover(_G[name])
          local suffix = key and (" |cffffd200(" .. key .. ")|r") or ""
          assert.are.equal(ja(titleKey) .. suffix, left(1):GetText(), name)
          assert.are.equal(WFJ.Font.PATH, (left(1):GetFont()))
          MM.leave(_G[name])
          assert.are.equal(en(titleKey) .. suffix, left(1):GetText(), name) -- released on hide
        end
      end
    end
  end

  it("every Forever micro button's title translates (no key bound)", function()
    hoverAll(function() return true end)
  end)

  it("a bound title keeps its binding suffix (keys the binding form whitelists)", function()
    MM.bindings = { TOGGLECHARACTER0 = "C", TOGGLEPROFESSIONBOOK = "K", TOGGLETALENTS = "N", TOGGLESPELLBOOK = "P",
      TOGGLEACHIEVEMENT = "Y", TOGGLEQUESTLOG = "L", TOGGLEGUILDTAB = "J", TOGGLEGROUPFINDER = "I",
      TOGGLECOLLECTIONS = "SHIFT-P", TOGGLEENCOUNTERJOURNAL = "SHIFT-J" }
    MM.updateBindings()
    local checked = 0
    -- the binding form is a per-key whitelist in Core/UIStrings; the Forever-only title keys are checked here
    -- once they join it
    hoverAll(function(titleKey, key)
      local ok = key ~= nil and WFJ.UIIndex:has(titleKey, "binding")
      if ok then checked = checked + 1 end
      return ok
    end)
    assert.is_true(checked >= 4) -- CHARACTER_BUTTON, SPELLBOOK_ABILITIES_BUTTON, QUESTLOG_BUTTON, GUILD at least
  end)

  it("a Forever-only title with a key bound keeps its suffix (PROFESSIONS_BUTTON, the binding form)", function()
    MM.bindings = { TOGGLEPROFESSIONBOOK = "K" }
    MM.updateBindings()
    MM.hover(MM.buttons.ProfessionMicroButton)
    assert.are.equal(ja("PROFESSIONS_BUTTON") .. " |cffffd200(K)|r", left(1):GetText())
  end)

  it("a disabled button's reason line translates with its title", function()
    local g = MM.buttons.GuildMicroButton
    g.enabled, g.disabledTooltip = false, en("ERR_RESTRICTED_ACCOUNT_TRIAL")
    MM.hover(g)
    assert.are.equal(ja("GUILD"), left(1):GetText())
    assert.are.equal(ja("ERR_RESTRICTED_ACCOUNT_TRIAL"), left(2):GetText())
  end)

  it("every disabled reason is walked with its title, including a function reason", function()
    local ej, legacy = MM.buttons.EJMicroButton, MM.buttons.LegacyMicroButton
    ej.enabled, ej.disabledTooltip = false, en("FEATURE_NOT_YET_AVAILABLE") -- lua:1753
    MM.hover(ej)
    assert.are.equal(ja("FEATURE_NOT_YET_AVAILABLE"), left(2):GetText())
    MM.leave(ej)
    legacy.enabled, legacy.disabledTooltip = false, en("LEGACY_MICRO_BUTTON_LOCKED_TOOLTIP") -- lua:1071
    MM.hover(legacy)
    assert.are.equal(ja("LEGACY_MICRO_BUTTON_LOCKED_TOOLTIP"), left(2):GetText())
  end)

  it("the XP bar's own text translates on each UpdateCurrentText; Alt shows English", function()
    -- shared/expbar.lua:40, 75 + mainline/expbaroverrides.lua:10–12: SetBarText into OverlayFrame.Text
    local bar = _G.MainStatusTrackingBarContainer.bars[4]
    bar.OverlayFrame = { Text = Stub.fontString("") }
    bar.currXP, bar.maxBar = 10, 200
    function bar:UpdateCurrentText()
      self.OverlayFrame.Text.text = string.format(en("XP_STATUS_BAR_TEXT"), self.currXP, self.maxBar)
    end
    bar:UpdateCurrentText()
    local W = H.loadChunks(FILES)
    H.uiSetup(W, UI)
    W.MicroMenu.init()
    assert.are.equal("経験値: 10/200", bar.OverlayFrame.Text:GetText())
    bar.currXP = 55
    bar:UpdateCurrentText()
    assert.are.equal("経験値: 55/200", bar.OverlayFrame.Text:GetText())
    Stub.keys.alt = true; W.Modifier.refresh()
    assert.are.equal("XP: 55/200", bar.OverlayFrame.Text:GetText())
    Stub.keys.alt = false; W.Modifier.refresh()
    assert.are.equal(W.Font.PATH, (bar.OverlayFrame.Text:GetFont()))
  end)

  it("a Classic-style XP text (numbers only) is left as the client wrote it", function()
    local bar = _G.MainStatusTrackingBarContainer.bars[4]
    bar.OverlayFrame = { Text = Stub.fontString("") }
    -- Classic/ExpBarOverrides.lua:2–5
    function bar:UpdateCurrentText() self.OverlayFrame.Text.text = "(5%) 10 / 200" end
    bar:UpdateCurrentText()
    local W = H.loadChunks(FILES)
    H.uiSetup(W, UI)
    W.MicroMenu.init()
    assert.are.equal("(5%) 10 / 200", bar.OverlayFrame.Text:GetText())
    assert.are.equal(0, bar.OverlayFrame.Text.calls.addonSetText)
  end)

  describe("the exhaustion tick tooltip, anchored to UIParent", function()
    local function linesOf()
      local out = {}
      for i = 1, tt:NumLines() do out[i] = left(i):GetText() end
      return out
    end

    it("its rest line, the rest hint and the banked-XP lines translate; XP numbers stay; Alt and hide restore",
      function()
        MM.rest = { id = 4, name = "Tired", multiplier = 0.5 }
        MM.banked = "header"
        local tick = MM.ticks[1]
        MM.hover(tick)
        assert.are.equal(_G.UIParent, tt:GetOwner())
        local lines = linesOf()
        assert.are.equal("|cffffffff1500 / 2000  ( 75% )|r\n\n", lines[1])
        assert.are.equal("|cffffd200Tired|r\n|cffffffff通常の50%の経験値を\nモンスターから獲得|r", lines[2])
        assert.are.equal(ja("XP_TEXT_BANKED_XP_HEADER"), lines[5])
        assert.are.equal(ja("TRIAL_CAP_BANKED_XP_TOOLTIP"), lines[6])
        assert.are.equal(WFJ.Font.PATH, (left(2):GetFont()))
        assert.is_false(WFJ.HelpTooltip.registered(_G.UIParent)) -- walked once, never registered
        Stub.keys.alt = true; WFJ.Modifier.refresh()
        assert.are.equal(en("XP_TEXT_BANKED_XP_HEADER"), left(5):GetText())
        Stub.keys.alt = false; WFJ.Modifier.refresh()
        assert.are.equal(ja("XP_TEXT_BANKED_XP_HEADER"), left(5):GetText())
        MM.leave(tick)
        assert.are.equal(en("XP_TEXT_BANKED_XP_HEADER"), left(5):GetText()) -- released on OnHide
        assert.are.equal(0, WFJ.SurfaceState.count("help"))
      end)

    it("the rest hint (EXHAUST_TOOLTIP2) is its own line on Forever", function()
      MM.rest = { id = 5, name = "Exhausted", multiplier = 0.5 }
      MM.hover(MM.ticks[1])
      assert.are.equal(ja("EXHAUST_TOOLTIP2"), left(3):GetText())
    end)

    it("the bar's own OnEnter path (the tick's method called by the bar) is walked the same way", function()
      MM.ticks[1]:ExhaustionToolTipText() -- shared/expbar.lua:87
      assert.are.equal("|cffffd200Rested|r\n|cffffffff通常の200%の経験値を\nモンスターから獲得|r", left(2):GetText())
    end)

    it("an unrelated UIParent-anchored tooltip is never walked, before or after the exhaustion tooltip", function()
      local function unrelated()
        tt:SetOwner(_G.UIParent, "ANCHOR_NONE") -- e.g. a world unit tooltip
        tt:SetText(en("XP_TEXT_BANKED_XP_HEADER")) -- even a word the exhaustion walk translates
        tt:AddLine(en("MAINMENU_BUTTON"))
        tt:Show()
      end
      unrelated()
      assert.are.same({ en("XP_TEXT_BANKED_XP_HEADER"), en("MAINMENU_BUTTON") }, linesOf())
      tt:Hide()
      MM.banked = "header"
      MM.hover(MM.ticks[1])
      assert.are.equal(ja("XP_TEXT_BANKED_XP_HEADER"), left(4):GetText()) -- Rested: no rest hint line
      MM.leave(MM.ticks[1])
      unrelated()
      assert.are.same({ en("XP_TEXT_BANKED_XP_HEADER"), en("MAINMENU_BUTTON") }, linesOf())
      assert.are.equal(0, WFJ.SurfaceState.count("help"))
    end)

    it("a tooltip the writer did not anchor to UIParent is left to the usual walk", function()
      tt:SetOwner(_G.CharacterMicroButton, "ANCHOR_RIGHT")
      tt:SetText(en("EXHAUST_TOOLTIP2"))
      assert.are.equal(0, WFJ.MicroMenu.onExhaustionTooltip())
    end)
  end)

  describe("HelpTooltip.walkAs", function()
    it("walks once with the given restriction and puts a registered owner's options back", function()
      local b = _G.CharacterMicroButton -- registered, unrestricted
      tt:SetOwner(b, "ANCHOR_RIGHT")
      tt:SetText(en("CHARACTER_BUTTON"))
      tt:AddLine(en("MAINMENU_BUTTON"))
      tt:Show()
      assert.are.equal(ja("MAINMENU_BUTTON"), left(2):GetText())
      tt:Hide()
      tt:SetOwner(b, "ANCHOR_RIGHT")
      tt:SetText(en("CHARACTER_BUTTON"))
      tt:AddLine(en("MAINMENU_BUTTON"))
      assert.are.equal(1, WFJ.HelpTooltip.walkAs(tt, { only = { "CHARACTER_BUTTON" } }))
      tt:Hide()
      tt:SetOwner(b, "ANCHOR_RIGHT") -- unrestricted again
      tt:SetText(en("CHARACTER_BUTTON"))
      tt:AddLine(en("MAINMENU_BUTTON"))
      tt:Show()
      assert.are.equal(ja("MAINMENU_BUTTON"), left(2):GetText())
    end)

    it("no tooltip or no owner: 0, nothing registered", function()
      assert.are.equal(0, WFJ.HelpTooltip.walkAs({}, { only = { "CHARACTER_BUTTON" } }))
      tt:Hide(); tt:ClearLines()
      if tt.owner then tt.owner = nil end
      assert.has_no.errors(function() WFJ.HelpTooltip.walkAs(nil, nil) end)
    end)
  end)

  it("the performance tooltip, owned by MainMenuMicroButton, translates on each rebuild", function()
    local mm = MM.buttons.MainMenuMicroButton
    MM.hover(mm)
    MM.update(mm, 0)
    assert.are.equal(mm, tt:GetOwner())
    assert.are.equal(ja("MAINMENU_BUTTON"), left(1):GetText())
    assert.is_not_nil(lineOf("フレームレート: 60 fps"))
    MM.perf.fps = 30.2
    MM.update(mm, 1); MM.update(mm, 0)
    assert.is_not_nil(lineOf("フレームレート: 30 fps"))
    MM.leave(mm)
  end)

  it("the stable's pet XP bar (PetStableFrame.expBar) translates like the main bars", function()
    -- camelot Blizzard_StableUI.xml:190 (parentKey expBar), camelot/petexpbar.lua:24–26
    local stable = CreateFrame("Frame", "PetStableFrame")
    local bar = { OverlayFrame = { Text = Stub.fontString("") }, currXP = 300, maxBar = 1200 }
    function bar:UpdateCurrentText()
      self.OverlayFrame.Text.text = string.format(en("XP_STATUS_BAR_TEXT"), self.currXP, self.maxBar)
    end
    stable.expBar = bar
    bar:UpdateCurrentText()
    Stub.loadedAddons.Blizzard_StableUI = true
    local W = H.loadChunks(FILES)
    H.uiSetup(W, UI)
    W.MicroMenu.init()
    assert.are.equal("経験値: 300/1200", bar.OverlayFrame.Text:GetText())
    bar.currXP = 450
    bar:UpdateCurrentText()
    assert.are.equal("経験値: 450/1200", bar.OverlayFrame.Text:GetText())
    _G.PetStableFrame = nil
  end)

  it("the latency label (three lines, both numbers kept) and its help line translate", function()
    local getCVar = _G.GetCVar
    _G.GetCVar = function(name)
      if name == "showNewbieTips" then return "1" end
      return getCVar and getCVar(name)
    end
    local mm = MM.buttons.MainMenuMicroButton
    MM.hover(mm)
    MM.update(mm, 0)
    _G.GetCVar = getCVar
    assert.is_not_nil(lineOf("レイテンシ:\n45 ms (ホーム)\n60 ms (ワールド)"))
    assert.is_not_nil(lineOf(ja("NEWBIE_TOOLTIP_LATENCY")))
    MM.leave(mm)
  end)

  describe("the pet and possess bars", function()
    it("pet action tooltips: command and stance titles translate; a spell-named action is never touched", function()
      MM.cvars.UberTooltips = "0"
      MM.setPetAction(1, { token = "PET_ACTION_ATTACK" })
      MM.setPetAction(5, { token = "PET_MODE_PASSIVE" })
      MM.setPetAction(4, { name = "Cancel" }) -- a pet spell whose name equals a dictionary word
      MM.hover(MM.pets[1])
      assert.are.same({ "攻撃" }, tipLines())
      MM.leave(MM.pets[1])
      MM.hover(MM.pets[5])
      assert.are.same({ "消極的" }, tipLines())
      MM.leave(MM.pets[5])
      local writes = left(1).calls.SetText
      MM.hover(MM.pets[4])
      assert.are.same({ "Cancel" }, tipLines())
      assert.are.equal(writes, left(1).calls.SetText)
      assert.are.equal(0, records())
    end)

    it("pet action tooltips through the C setter (UberTooltips on) translate after SetPetAction", function()
      MM.setPetAction(2, { token = "PET_ACTION_FOLLOW" })
      MM.hover(MM.pets[2])
      assert.are.same({ "追従" }, tipLines())
      assert.are.equal(MM.pets[2].scripts.OnEnter, MM.pets[2].UpdateTooltip)
    end)

    it("a pet title with a key binding translates the command and keeps the binding as shown", function()
      MM.cvars.UberTooltips = "0"
      MM.bindings.BONUSACTIONBUTTON1 = "Ctrl-1" -- the default pet bar binding
      MM.setPetAction(1, { token = "PET_ACTION_ATTACK" })
      MM.hover(MM.pets[1]) -- tooltipName .. NORMAL_FONT_COLOR_CODE .. " (" .. key .. ")" .. "|r"
      assert.are.same({ "攻撃|cffffd200 (Ctrl-1)|r" }, tipLines())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.same({ "Attack|cffffd200 (Ctrl-1)|r" }, tipLines())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.same({ "攻撃|cffffd200 (Ctrl-1)|r" }, tipLines())
      MM.leave(MM.pets[1])
      MM.bindings.BONUSACTIONBUTTON4 = "Ctrl-4"
      MM.setPetAction(4, { name = "Cancel" }) -- a pet spell named like a dictionary word: never touched
      MM.hover(MM.pets[4])
      assert.are.same({ "Cancel|cffffd200 (Ctrl-4)|r" }, tipLines())
    end)

    it("an UpdateTooltip refresh calls the client's captured function: English is written, then Japanese is back",
      function()
      MM.setPetAction(3, { token = "PET_ACTION_WAIT" })
      MM.hover(MM.pets[3])
      assert.are.equal("待機", left(1):GetText())
      local writes = left(1).calls.SetText
      tt.calls.Show = 0
      MM.tooltipUpdate() -- GameTooltip_OnUpdate → owner:UpdateTooltip() → SetPetAction writes "Stay"
      assert.are.equal("待機", left(1):GetText())
      assert.are.equal(writes + 1, left(1).calls.SetText) -- the client's English was replaced again
      assert.are.equal(1, tt.calls.Show) -- one refit
      assert.are.equal("Stay", WFJ.SurfaceState.get("help", "L1").en)
    end)

    it("the possess bar's cancel button translates; the possessed spell does not", function()
      MM.hover(MM.possess[2])
      assert.are.same({ "キャンセル" }, tipLines())
      MM.leave(MM.possess[2])
      MM.hover(MM.possess[1])
      assert.are.same({ "Mind Control" }, tipLines())
      assert.are.equal(0, records())
    end)

    it("a tooltip owned by an unregistered frame is untouched", function()
      local other = _G.CreateFrame("Button", "SomeAddonButton")
      tt:SetOwner(other, "ANCHOR_RIGHT")
      tt:SetText("Quest Log")
      tt:AddLine(en("NEWBIE_TOOLTIP_QUESTLOG"))
      tt:Show()
      assert.are.same({ "Quest Log", en("NEWBIE_TOOLTIP_QUESTLOG") }, tipLines())
      assert.are.equal(0, left(1).calls.SetText)
      assert.are.equal(0, records())
    end)

    it("an item tooltip on a registered owner is never walked, and its item records survive the pass",
      function()
        tt:SetOwner(MM.pets[1], "ANCHOR_RIGHT")
        Stub.setItemTooltip(tt, "|Hitem:2488:0:0:0|h[Worn Shortsword]|h", { "Worn Shortsword", "Binds when equipped" })
        assert.are.equal("装備時にソウルバウンド", left(2):GetText())
        tt:Show()
        assert.are.equal(0, records())
        assert.are.equal("Worn Shortsword", left(1):GetText())
        assert.are.equal("装備時にソウルバウンド", left(2):GetText())
        assert.is_not_nil(WFJ.SurfaceState.get("tooltip.GameTooltip", "ui.L2"))
      end)
  end)

  it("no micro menu frames at all: init registers nothing and never errors", function()
    for _, spec in ipairs(MM.FOREVER_MICRO) do _G[spec[1]] = nil end
    local W = H.loadChunks(FILES)
    H.uiSetup(W, UI)
    assert.has_no.errors(function() W.MicroMenu.init() end)
    assert.is_false(W.HelpTooltip.registered(MM.buttons.CharacterMicroButton))
  end)

  it("the game menu renders LOG_OUT, GAMEMENU_EXTERNALEVENT and GAME_MENU_SHOW_REWARDS", function()
    assert.is_true(WFJ.GameMenu.init())
    Stub.gameMenuLabels = { en("GAMEMENU_EXTERNALEVENT"), en("GAMEMENU_OPTIONS"), en("GAME_MENU_SHOW_REWARDS"),
      en("LOG_OUT"), en("EXIT_GAME"), en("RETURN_TO_GAME") }
    GameMenuFrame:Show()
    local byIndex = {}
    for b in GameMenuFrame.buttonPool:EnumerateActive() do byIndex[b.layoutIndex] = b end
    assert.are.equal(ja("GAMEMENU_EXTERNALEVENT"), byIndex[1]:GetText())
    assert.are.equal(ja("GAME_MENU_SHOW_REWARDS"), byIndex[3]:GetText())
    assert.are.equal(ja("LOG_OUT"), byIndex[4]:GetText())
    assert.are.equal(ja("RETURN_TO_GAME"), byIndex[6]:GetText())
    GameMenuFrame:Hide()
    assert.are.equal(en("LOG_OUT"), byIndex[4]:GetText())
  end)

  it("a game menu without InitButtons or HookScript is skipped without error", function()
    _G.GameMenuFrame = { buttonPool = {} }
    local W = H.loadChunks(FILES)
    H.uiSetup(W, UI)
    assert.has_no.errors(function() assert.is_false(W.GameMenu.init()) end)
    _G.GameMenuFrame = { InitButtons = function() end, HookScript = true }
    W = H.loadChunks(FILES)
    H.uiSetup(W, UI)
    assert.has_no.errors(function() W.GameMenu.init() end)
  end)
end)
