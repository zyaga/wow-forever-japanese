-- The "ui" area on its surfaces: tooltip structural lines, quest window labels and
-- buttons, button fonts across state changes, the game menu, and the toggle contract.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Align.lua", "Core/State.lua", "Core/Settings.lua",
  "Core/Modifier.lua", "Core/Translator.lua", "Core/UIStringKeys.lua",
  "Core/UIStrings.lua", "Core/SurfaceState.lua", "Core/Normalize.lua",
  "Core/Hash.lua", "Core/Collector.lua", "UI/Font.lua", "UI/Render.lua", "UI/ButtonText.lua", "UI/Labels.lua",
  "UI/TimeLine.lua", "UI/Tooltip.lua", "UI/QuestFrame.lua", "UI/GameMenu.lua" }

-- key → { English the client holds, Japanese }
local UI = {
  ITEM_BIND_ON_EQUIP = { "Binds when equipped", "装備時にソウルバウンド" },
  INVTYPE_WEAPON = { "One-Hand", "片手" }, INVTYPE_CLOAK = { "Back", "背中" },
  ["ItemSubClass:2:7"] = { "Sword", "剣" }, DAMAGE_TEMPLATE = { "%s - %s Damage", "%s - %s ダメージ" },
  SPEED = { "Speed", "速度" }, DPS_TEMPLATE = { "(%s damage per second)", "(秒間ダメージ %s)" },
  ITEM_MOD_STAMINA = { "%c%d Stamina", "スタミナ %c%d" }, DURABILITY_TEMPLATE = { "Durability %d / %d", "耐久度 %d / %d" },
  ITEM_MIN_LEVEL = { "Requires Level %d", "必要レベル %d" }, SELL_PRICE = { "Sell Price", "売値" },
  MANA_COST = { "%s Mana", "マナ %s" }, SPELL_RANGE = { "%s yd range", "射程 %sヤード" },
  SPELL_CAST_TIME_SEC = { "%.3g sec cast", "詠唱 %.3g秒" },
  QUEST_DESCRIPTION = { "Description", "説明" }, QUEST_OBJECTIVES = { "Quest Objectives", "クエスト目標" },
  QUEST_REWARDS = { "Rewards", "報酬" }, REWARD_CHOICES = { "You will be able to choose one of these rewards:",
    "以下の報酬から1つ選択できます:" }, REWARD_ITEMS = { "You will also receive:", "さらに以下を受け取ります:" },
  REWARD_ITEMS_ONLY = { "You will receive:", "以下を受け取ります:" }, REWARD_SPELL = { "You will learn:", "以下を習得します:" },
  LEARN_SPELL_OBJECTIVE = { "Learn Spell:", "習得する呪文:" }, TURN_IN_ITEMS = { "Required items:", "必要なアイテム:" },
  REQUIRED_MONEY = { "Required Money:", "必要な金額:" }, ACCEPT = { "Accept", "受注" }, DECLINE = { "Decline", "辞退" },
  COMPLETE_QUEST = { "Complete Quest", "クエスト完了" }, CONTINUE = { "Continue", "次へ" }, CANCEL = { "Cancel", "キャンセル" },
  GOODBYE = { "Goodbye", "さようなら" }, CURRENT_QUESTS = { "Current Quests", "進行中のクエスト" },
  AVAILABLE_QUESTS = { "Available Quests", "受注可能なクエスト" }, QUEST_LOG = { "Quest Log", "クエストログ" },
  ABANDON_QUEST = { "Abandon Quest", "クエスト放棄" }, SHARE_QUEST = { "Share Quest", "クエスト共有" },
  EXIT = { "Exit", "閉じる" }, TRACK_QUEST = { "Track Quest", "追跡" },
  QUESTLOG_NO_QUESTS_TEXT = { "No Active Quests", "進行中のクエストはありません" },
  GAMEMENU_OPTIONS = { "Options", "オプション" }, ADDONS = { "AddOns", "アドオン" }, GAMEMENU_SUPPORT = { "Support", "サポート" },
  MACROS = { "Macros", "マクロ" }, LOGOUT = { "Logout", "ログアウト" }, EXIT_GAME = { "Exit Game", "ゲーム終了" },
  RETURN_TO_GAME = { "Return to Game", "ゲームに戻る" }, RANK = { "Rank", "ランク" },
  CURRENTLY_EQUIPPED = { "Currently Equipped", "装備中" }, MAINMENU_BUTTON = { "Main Menu", "メインメニュー" },
  CHANCE_TO_DODGE = { "%.2f%% chance to dodge", "回避率 %.2f%%" },
  EXPERIENCE_COLON = { "Experience:", "経験値:" }, QUEST_SUGGESTED_GROUP_NUM = { "Suggested Players [%d]", "推奨人数 [%d]" },
  ALL = { "All", "すべて" },
}
local ITEM_JA = "【使用】Hearthstoneの場所に戻ります。"

describe("the ui area on its surfaces", function()
  local WFJ, S, SS, tt, rows

  local function left(i) return _G["GameTooltipTextLeft" .. i] end
  local function right(i) return _G["GameTooltipTextRight" .. i] end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    S, SS = WFJ.Settings, WFJ.SurfaceState
    WFJ.Compat.init(function(name) return _G[name] end)
    S.load(nil, 1, {})
    rows = {}
    local function h1(text) return (WFJ.Hash.h32x2(WFJ.Normalize.v1(text))) end
    for key, pair in pairs(UI) do
      rows[key] = { pair[2], h1(pair[1]), "." }
      if not key:find(":") then _G[key] = pair[1] end
    end
    Stub.subclasses["2:7"] = "One-Handed Swords" -- what the API returns; never consulted
    -- as Main.lua does: globals by name; an item subclass has no string the tooltip uses (fingerprint path)
    WFJ.UIIndex = WFJ.UIStrings.build({ rows = rows, hash = h1, english = function(key)
      if key:find("^ItemSubClass:") then return nil end
      return _G[key]
    end })
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      modifierHeld = WFJ.Modifier.isDown,
      lookup = function(kind, id)
        if kind == "ui" then local r = rows[id]; return r and { ja = r[1], status = r[3] } end
        if kind == "item.description" and id == 6948 then return { ja = ITEM_JA, status = "u" } end
        return nil
      end,
      marker = function(n) return S.get("marker." .. n) end,
      align = WFJ.Align.check,
      fill = function(ja, args) return WFJ.UIIndex:fill(ja, args) end,
    }))
    WFJ.Tooltip.init(); WFJ.QuestFrame.init(); WFJ.GameMenu.init()
    tt = _G.GameTooltip
  end)

  after_each(function()
    for key in pairs(UI) do if not key:find(":") then _G[key] = nil end end
  end)

  local SWORD = { "Worn Shortsword", "Binds when equipped", { "One-Hand", "Sword" }, { "1 - 3 Damage", "Speed 1.90" },
    "(1.0 damage per second)", "+1 Stamina", "Durability 20 / 20", "Requires Level 5", "Sell Price: 12c" }

  it("item structural lines translate in place, left and right, with the live numbers", function()
    Stub.setItemTooltip(tt, "|Hitem:2488:0:0:0|h[Worn Shortsword]|h", SWORD)
    assert.are.equal("Worn Shortsword", left(1):GetText())
    assert.are.equal(0, left(1).calls.SetText) -- the name is never a candidate
    assert.are.equal("装備時にソウルバウンド", left(2):GetText())
    assert.are.equal("片手", left(3):GetText())
    assert.are.equal("剣", right(3):GetText())
    assert.are.equal("1 - 3 ダメージ", left(4):GetText())
    assert.are.equal("速度 1.90", right(4):GetText())
    assert.are.equal("(秒間ダメージ 1.0)", left(5):GetText())
    assert.are.equal("スタミナ +1", left(6):GetText())
    assert.are.equal("耐久度 20 / 20", left(7):GetText())
    assert.are.equal("必要レベル 5", left(8):GetText())
    assert.are.equal("売値: 12c", left(9):GetText())
    assert.are.equal(WFJ.Font.PATH, (left(2):GetFont()))
    assert.are.equal(WFJ.Font.PATH, (right(3):GetFont()))
    assert.are.equal(2, tt.calls.Show) -- one refit for the hover (two Shows)
  end)

  it("the description run keeps the item description path and its lines are never ui records", function()
    Stub.setItemTooltip(tt, "|Hitem:6948:0:0:0|h[Hearthstone]|h", { "Hearthstone", "Soulbound", "Unique",
      "Use: Returns you to Goldshire. Speak to an Innkeeper in a different place to change your home location.",
      "Sell Price: 12c" })
    assert.are.equal(ITEM_JA, left(4):GetText())
    assert.is_nil(SS.get("tooltip.GameTooltip", "ui.L4"))
    assert.are.equal("売値: 12c", left(5):GetText())
    assert.are.equal(2, tt.calls.Show) -- one refit (two Shows)
  end)

  it("a spell tooltip's cost / range / cast lines translate; the description line is left alone", function()
    WFJ.Settings.set("marker.missing", false) -- on by default; this test reads the text, not the marker
    Stub.spellDescriptions[133] = "Hurls a fiery ball that causes 14 to 22 Fire damage."
    Stub.setSpellTooltip(tt, 133, { "Fireball", { "30 Mana", "35 yd range" }, "1.5 sec cast",
      "Hurls a fiery ball that causes 14 to 22 Fire damage." })
    assert.are.equal("マナ 30", left(2):GetText())
    assert.are.equal("射程 35ヤード", right(2):GetText())
    assert.are.equal("詠唱 1.5秒", left(3):GetText())
    assert.are.equal("Hurls a fiery ball that causes 14 to 22 Fire damage.", left(4):GetText())
    assert.are.equal("Fireball", left(1):GetText())
  end)

  it("a spell's 'Rank 1' beside the name translates; the name does not; a percent template fills (in-game pass)",
    function()
      Stub.setSpellTooltip(tt, 81, { { "Dodge", "Rank 1" }, "6.86% chance to dodge" })
      assert.are.equal("Dodge", left(1):GetText())
      assert.are.equal("ランク 1", right(1):GetText())
      assert.are.equal("回避率 6.86%", left(2):GetText())
    end)

  it("a comparison tooltip: the 'Currently Equipped' header translates, the name on line 2 never does", function()
    local shop = _G.ShoppingTooltip1
    Stub.setItemTooltip(shop, "|Hitem:99998:0:0:0|h[Back]|h", { "Currently Equipped", "Back", { "Back", "Sword" } })
    assert.are.equal("装備中", _G.ShoppingTooltip1TextLeft1:GetText())
    assert.are.equal("Back", _G.ShoppingTooltip1TextLeft2:GetText()) -- the item's name, although "Back" is a word
    assert.are.equal("Back", _G.ShoppingTooltip1TextLeft3:GetText()) -- any left line reading as the name is left alone
    assert.are.equal("剣", _G.ShoppingTooltip1TextRight3:GetText())
  end)

  it("a frame reused for another link without a hook firing: refresh drops the stale records",
    function()
      local ref = _G.ItemRefTooltip
      Stub.setItemTooltip(ref, "|Hitem:2488:0:0:0|h[Worn Shortsword]|h", SWORD)
      assert.are.equal("装備時にソウルバウンド", _G.ItemRefTooltipTextLeft2:GetText())
      -- the client shows a quest link on the same frame: no OnTooltipSetItem, no OnHide
      ref:writeLines({ "The Balance of Nature", "Kill 7 Young Nightsabers.", "Rewards" })
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("Kill 7 Young Nightsabers.", _G.ItemRefTooltipTextLeft2:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("Kill 7 Young Nightsabers.", _G.ItemRefTooltipTextLeft2:GetText())
      assert.are.equal("Rewards", _G.ItemRefTooltipTextLeft3:GetText())
      assert.are.equal(0, SS.count("tooltip.ItemRefTooltip"))
    end)

  it("a comparison tooltip whose item name is not cached yet still protects the name line", function()
    local shop = _G.ShoppingTooltip1
    Stub.setItemTooltip(shop, "|Hitem:99998:0:0:0|h[Back]|h", { "Currently Equipped", "Back", "Binds when equipped" })
    shop.item.name = nil -- GetItem() returns no name for an uncached item
    shop:writeLines({ "Currently Equipped", "Back", "Binds when equipped" })
    Stub.fireTooltipSet(shop, "Item") -- the Item post-call, as the client runs it
    assert.are.equal("Back", _G.ShoppingTooltip1TextLeft2:GetText())
    assert.are.equal("装備時にソウルバウンド", _G.ShoppingTooltip1TextLeft3:GetText())
  end)

  it("a name equal to a dictionary word is never replaced: line 1 is not walked", function()
    Stub.setItemTooltip(tt, "|Hitem:99999:0:0:0|h[Back]|h", { "Back", "Binds when equipped", "Back" })
    assert.are.equal("Back", left(1):GetText())
    assert.are.equal(0, left(1).calls.SetText)
    assert.are.equal("Back", left(3):GetText()) -- a left line reading exactly as the name is treated as the name
    Stub.setItemTooltip(tt, "|Hitem:2488:0:0:0|h[Worn Shortsword]|h", { "Worn Shortsword", "Back" })
    assert.are.equal("背中", left(2):GetText()) -- the same word on another item is a slot line
  end)

  it("modifier / area.interface / area.itemTooltips / master switch", function()
    Stub.setItemTooltip(tt, "|Hitem:6948:0:0:0|h[Hearthstone]|h", { "Hearthstone", "Binds when equipped",
      "Use: Returns you to Goldshire. Speak to an Innkeeper in a different place to change your home location.",
      "+1 Stamina" })
    local use =
      "Use: Returns you to Goldshire. Speak to an Innkeeper in a different place to change your home location."
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Binds when equipped", left(2):GetText())
    assert.are.equal("Fonts\\FRIZQT__.TTF", (left(2):GetFont()))
    assert.are.equal(use, left(3):GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("装備時にソウルバウンド", left(2):GetText())

    S.set("area.interface", false)
    assert.are.equal("Binds when equipped", left(2):GetText())
    assert.are.equal("+1 Stamina", left(4):GetText())
    assert.are.equal(ITEM_JA, left(3):GetText()) -- the item description stays Japanese
    S.set("area.interface", true)
    S.set("area.itemTooltips", false)
    assert.are.equal(use, left(3):GetText())
    assert.are.equal("スタミナ +1", left(4):GetText()) -- structural lines are their own area
    S.set("area.itemTooltips", true)
    S.set("enabled", false)
    assert.are.equal("Binds when equipped", left(2):GetText())
    assert.are.equal(use, left(3):GetText())
  end)

  it("quest window labels and buttons translate after the panel writer; a composite label is left alone",
    function()
      QuestInfoSpellObjectiveLearnLabel:SetText("Learn Spell: (Complete)")
      Stub.quest = { id = 2, title = "T", description = "D", objectives = "O", progress = "P", completion = "C" }
      Stub.showDetail()
      assert.are.equal("説明", QuestInfoDescriptionHeader:GetText())
      assert.are.equal("クエスト目標", QuestInfoObjectivesHeader:GetText())
      assert.are.equal("報酬", QuestInfoRewardsFrame.Header:GetText())
      assert.are.equal("以下の報酬から1つ選択できます:", QuestInfoRewardsFrame.ItemChooseText:GetText())
      assert.are.equal("受注", QuestFrameAcceptButton:GetText())
      assert.are.equal("辞退", QuestFrameDeclineButton:GetText())
      assert.are.equal(WFJ.Font.PATH, (QuestFrameAcceptButton:GetFontString():GetFont()))
      assert.are.equal("Learn Spell: (Complete)", QuestInfoSpellObjectiveLearnLabel:GetText())
      assert.are.equal("推奨人数 [3]", QuestInfoGroupSize:GetText()) -- a template label gets its live value
      assert.are.equal("経験値:", QuestInfoRewardsFrame.XPFrame.ReceiveText:GetText())
      assert.is_nil(SS.get("questframe.detail", "ui.learnLabel"))
      -- a reward item's data arrives: the client redraws the rewards in English (QuestInfo_ShowRewards)
      QuestInfoRewardsFrame.ItemChooseText:SetText(_G.REWARD_CHOICES)
      WFJ.QuestFrame.onShowRewards()
      assert.are.equal("以下の報酬から1つ選択できます:", QuestInfoRewardsFrame.ItemChooseText:GetText())

      Stub.showProgress()
      assert.are.equal("必要なアイテム:", QuestProgressRequiredItemsText:GetText())
      assert.are.equal("次へ", QuestFrameCompleteButton:GetText())
      assert.are.equal("キャンセル", QuestFrameGoodbyeButton:GetText())
      Stub.showReward()
      assert.are.equal("クエスト完了", QuestFrameCompleteQuestButton:GetText())

      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("Complete Quest", QuestFrameCompleteQuestButton:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      QuestFrame:Hide()
      assert.are.equal("Complete Quest", QuestFrameCompleteQuestButton:GetText())
      assert.are.equal(0, SS.count("questframe.reward"))
    end)

  it("the greeting panel translates its headers and Goodbye; its NPC text is gossip, not ui", function()
    QuestFrameGreetingPanel:Show()
    assert.are.equal("進行中のクエスト", CurrentQuestsText:GetText())
    assert.are.equal("受注可能なクエスト", AvailableQuestsText:GetText())
    assert.are.equal("さようなら", QuestFrameGreetingGoodbyeButton:GetText())
    assert.are.equal("Well met, traveller.", GreetingText:GetText())
    assert.are.equal(0, GreetingText.calls.addonSetText) -- no gossip data here; greeting prose is gossip
    QuestFrame:Hide()
    assert.are.equal("Current Quests", CurrentQuestsText:GetText())
  end)

  it("a button keeps the bundled font across the client's state changes while Japanese is shown", function()
    Stub.quest = { id = 2, title = "T", description = "D", objectives = "O", progress = "", completion = "" }
    Stub.showDetail()
    local b = QuestFrameAcceptButton
    for _, state in ipairs({ "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnDisable", "OnEnable", "OnShow" }) do
      b:state(state)
      assert.are.equal(WFJ.Font.PATH, (b:GetFontString():GetFont()), state)
    end
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Accept", b:GetText())
    b:state("OnEnter")
    assert.are.equal("Fonts\\FRIZQT__.TTF", (b:GetFontString():GetFont())) -- English: the client's font stands
  end)

  it("the game menu's pooled buttons translate on every InitButtons and restore on hide", function()
    GameMenuFrame:Show()
    local byLabel = {}
    for b in GameMenuFrame.buttonPool:EnumerateActive() do byLabel[b.layoutIndex] = b end
    assert.are.equal("オプション", byLabel[1]:GetText())
    assert.are.equal("メインメニュー", GameMenuFrame.Header.Text:GetText())
    assert.are.equal("ゲームに戻る", byLabel[7]:GetText())
    assert.are.equal(8, SS.count("gamemenu")) -- seven buttons + the title plate

    -- a second show reuses the pool in another order; OnEnter / OnLeave were replaced by the client
    Stub.gameMenuLabels = { "Options", "Macros", "Logout", "Exit Game", "Return to Game" }
    GameMenuFrame:Show()
    byLabel = {}
    for b in GameMenuFrame.buttonPool:EnumerateActive() do byLabel[b.layoutIndex] = b end
    assert.are.equal("マクロ", byLabel[2]:GetText())
    assert.are.equal("ゲームに戻る", byLabel[5]:GetText())
    assert.are.equal(6, SS.count("gamemenu"))
    byLabel[2]:state("OnEnter")
    assert.are.equal(WFJ.Font.PATH, (byLabel[2]:GetFontString():GetFont()))

    GameMenuFrame:Hide()
    assert.are.equal("Macros", byLabel[2]:GetText())
    assert.are.equal(0, SS.count("gamemenu"))
  end)

  it("without an index nothing is shown and nothing breaks", function()
    WFJ.UIIndex = nil
    Stub.setItemTooltip(tt, "|Hitem:2488:0:0:0|h[Worn Shortsword]|h", SWORD)
    assert.are.equal("Binds when equipped", left(2):GetText())
    GameMenuFrame:Show()
    assert.are.equal(0, SS.count("gamemenu"))
  end)
end)
