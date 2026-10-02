-- UI/Alerts.lua over pooled alert frames passed to the global AlertFrame_ShowNewAlert, as camelot
-- blizzard_framexml/mainline/alertframes.lua:173–198, 461–468, 890–893 does after a sub-system's set-up function
-- wrote the texts (alertframesystems.lua:347–371, 541, 1011; alertframesystems.xml:200, 497, 1004).
local Stub = require("tests.lua.spec.wow_stub")
local X = require("tests.lua.spec.stub_framexml_hud")

local UI = {
  YOU_WON_LABEL = { "You Won!", "獲得！" }, YOU_RECEIVED_LABEL = { "You received", "入手" },
  ACHIEVEMENT_UNLOCKED = { "Achievement Earned", "アチーブメント達成" },
  NEW_RECIPE_LEARNED_TITLE = { "New Recipe Learned!", "新しいレシピを習得！" },
  GUILD_CHALLENGE_LABEL = { "Guild Challenge", "ギルドチャレンジ" },
  MERCHANT_HONOR_POINTS = { "%d Honor", "名誉 %d" },
  -- the level-up toast
  LEVEL_GAINED = { "Level %d", "レベル%d" }, LEVEL_UP_YOU_REACHED = { "You've Reached", "到達" },
  -- the recipe toast's rank line and the upgraded loot label
  TRADESKILL_RECIPE_LEVEL_RECIPE_FORMAT = { "%s (Rank %i)", "%s(ランク%i)" },
  ITEM_UPGRADED_LABEL = { "Item Upgraded!", "アイテムがアップグレードされた！" },
  -- an achievement title (a client-table fingerprint row)
  ["AchievementTitle:6"] = { "Explore Elwynn Forest", "エルウィンの森を探検" },
  -- the event toast's own text (UiEventToast): a format string the client fills, and a plain sentence
  ["EventToastText:513"] = { "You have reached Rank %d.", "ランク%dに到達した。" },
  ["EventToastText:479"] = { "Your Lotus Claw enchant allows you to carefully extract a Death Lotus!",
    "Lotus Clawのエンチャントで慎重にDeath Lotusを採取できる！" },
}
local NAMES = { "AlertFrame_ShowNewAlert", "EventToastManagerFrame" }

local function install()
  _G.AlertFrame_ShowNewAlert = function(frame) frame.shown = true end
  -- DisplayToast acquires a toast and Setup writes its title / subtitle (eventtoastmanager.lua:327–365)
  local manager = {}
  function manager:DisplayToast()
    local toast = { Title = Stub.fontString(""), SubTitle = Stub.fontString("") }
    toast.Title:SetText(self.next.title)
    toast.SubTitle:SetText(self.next.subtitle)
    self.currentDisplayingToast = toast
  end
  _G.EventToastManagerFrame = manager
end

local function regions(frame, list)
  function frame.GetRegions() return unpack(list) end
  return frame
end

describe("the alert toasts on Forever", function()
  local WFJ
  before_each(function()
    WFJ = X.load("UI/Alerts.lua", UI, { before = install })
    assert.is_true(WFJ.Alerts.init())
  end)
  after_each(function() X.teardown(NAMES) end)

  it("a loot alert's label translates; the item name (even a dictionary word) is never touched", function()
    local alert = { Label = Stub.fontString("You Won!"), ItemName = Stub.fontString("You Won!"),
      Name = Stub.fontString("Achievement Earned") }
    _G.AlertFrame_ShowNewAlert(alert)
    assert.are.equal("獲得！", alert.Label:GetText())
    assert.are.equal("You Won!", alert.ItemName:GetText())
    assert.are.equal("Achievement Earned", alert.Name:GetText())
    assert.is_true(X.unrecorded(WFJ, alert.ItemName))
    X.alt(WFJ, true)
    assert.are.equal("You Won!", alert.Label:GetText())
    X.alt(WFJ, false)
    -- the pooled frame is reused for another result
    alert.Label.text = "You received"
    _G.AlertFrame_ShowNewAlert(alert)
    assert.are.equal("入手", alert.Label:GetText())
  end)

  it("fields are restricted to their own keys; a template translates; an unnamed region is never searched", function()
    local unnamed = Stub.fontString("Guild Challenge") -- could as well be an achievement's name
    local alert = regions({ Unlocked = Stub.fontString("Achievement Earned"), Title = Stub.fontString("You Won!"),
      Amount = Stub.fontString("25 Honor") }, { unnamed })
    _G.AlertFrame_ShowNewAlert(alert)
    assert.are.equal("アチーブメント達成", alert.Unlocked:GetText())
    assert.are.equal("You Won!", alert.Title:GetText()) -- not a Title key
    assert.are.equal("名誉 25", alert.Amount:GetText())
    assert.are.equal("Guild Challenge", unnamed:GetText())
    local recipe = { Title = Stub.fontString("New Recipe Learned!"), Name = Stub.fontString("Minor Healing Potion") }
    _G.AlertFrame_ShowNewAlert(recipe)
    assert.are.equal("新しいレシピを習得！", recipe.Title:GetText())
    assert.are.equal("Minor Healing Potion", recipe.Name:GetText())
  end)

  it("a recipe toast's rank line translates with the recipe name and star kept; the upgraded label", function()
    local star = " |TInterface\\star:0|t"
    local recipe = { tradeSkillID = 171, Title = Stub.fontString("New Recipe Learned!"),
      Name = Stub.fontString("Minor Healing Potion (Rank 2)" .. star) }
    _G.AlertFrame_ShowNewAlert(recipe)
    assert.are.equal("Minor Healing Potion(ランク2)" .. star, recipe.Name:GetText())
    X.alt(WFJ, true)
    assert.are.equal("Minor Healing Potion (Rank 2)" .. star, recipe.Name:GetText())
    X.alt(WFJ, false)
    _G.AlertFrame_ShowNewAlert(recipe) -- shown again: still ours
    assert.are.equal("Minor Healing Potion(ランク2)" .. star, recipe.Name:GetText())
    -- another alert's Name holding the same shape is never walked
    local loot = { Name = Stub.fontString("Minor Healing Potion (Rank 2)"), Label = Stub.fontString("Item Upgraded!") }
    _G.AlertFrame_ShowNewAlert(loot)
    assert.are.equal("Minor Healing Potion (Rank 2)", loot.Name:GetText())
    assert.are.equal("アイテムがアップグレードされた！", loot.Label:GetText())
  end)

  it("an achievement toast's Name is an AchievementTitle row's Japanese; another alert's Name never is",
    function()
      local toast = { Shield = { Points = Stub.fontString("10") }, Unlocked = Stub.fontString("Achievement Earned"),
        Name = Stub.fontString("Explore Elwynn Forest") } -- AchievementAlertFrame_SetUp (alertframesystems.lua:315)
      _G.AlertFrame_ShowNewAlert(toast)
      assert.are.equal("エルウィンの森を探検", toast.Name:GetText())
      assert.are.equal("アチーブメント達成", toast.Unlocked:GetText())
      assert.are.equal("10", toast.Shield.Points:GetText())
      X.alt(WFJ, true)
      assert.are.equal("Explore Elwynn Forest", toast.Name:GetText())
      X.alt(WFJ, false)
      assert.are.equal("エルウィンの森を探検", toast.Name:GetText())
      -- the pooled toast reused for an achievement no row has, named like a dictionary word
      toast.Name.text = "Achievement Earned"
      _G.AlertFrame_ShowNewAlert(toast)
      assert.are.equal("Achievement Earned", toast.Name:GetText())
      -- a loot alert (no Shield) and a Shield without the Unlocked label: the Name is never read
      local loot = { Label = Stub.fontString("You Won!"), Name = Stub.fontString("Explore Elwynn Forest") }
      _G.AlertFrame_ShowNewAlert(loot)
      assert.are.equal("Explore Elwynn Forest", loot.Name:GetText())
      assert.is_true(X.unrecorded(WFJ, loot.Name))
      local shieldOnly = { Shield = {}, Name = Stub.fontString("Explore Elwynn Forest") }
      _G.AlertFrame_ShowNewAlert(shieldOnly)
      assert.are.equal("Explore Elwynn Forest", shieldOnly.Name:GetText())
    end)

  it("a wrong-typed alert or field raises nothing", function()
    assert.has_no.errors(function()
      _G.AlertFrame_ShowNewAlert({ Label = "text", Title = 4, GetRegions = "x" })
      WFJ.Alerts.onShowAlert(nil)
      WFJ.Alerts.onShowAlert("x")
    end)
  end)

  it("hooks once; a wrong-typed global and no global return false", function()
    assert.is_false(WFJ.Alerts.init())
    assert.are.equal(1, #Stub.hooks["AlertFrame_ShowNewAlert"])
    X.teardown(NAMES)
    local wrong = X.load("UI/Alerts.lua", UI, { before = function() _G.AlertFrame_ShowNewAlert = {} end })
    assert.has_no.errors(function() assert.is_false(wrong.Alerts.init()) end)
    X.teardown(NAMES)
    assert.is_false(X.load("UI/Alerts.lua", UI).Alerts.init())
  end)

  it("the level-up toast's title and subtitle translate, the level kept; another toast stays", function()
    local manager = _G.EventToastManagerFrame
    manager.next = { title = "You've Reached", subtitle = "Level 2" }
    manager:DisplayToast()
    local toast = manager.currentDisplayingToast
    assert.are.equal("到達", toast.Title:GetText())
    assert.are.equal("レベル2", toast.SubTitle:GetText())
    X.alt(WFJ, true)
    assert.are.equal("Level 2", toast.SubTitle:GetText())
    X.alt(WFJ, false)
    manager.next = { title = "Achievement Earned", subtitle = "Elwynn Forest" } -- not a level-up word
    manager:DisplayToast()
    assert.are.equal("Achievement Earned", manager.currentDisplayingToast.Title:GetText())
    assert.are.equal("Elwynn Forest", manager.currentDisplayingToast.SubTitle:GetText())
  end)

  it("an event toast's EventToastText line translates with the live number; Alt shows English", function()
    local manager = _G.EventToastManagerFrame
    manager.next = { title = "Rank Up!", subtitle = "You have reached Rank 4." }
    manager:DisplayToast()
    local toast = manager.currentDisplayingToast
    assert.are.equal("Rank Up!", toast.Title:GetText()) -- no row: left as written
    assert.are.equal("ランク4に到達した。", toast.SubTitle:GetText())
    X.alt(WFJ, true)
    assert.are.equal("You have reached Rank 4.", toast.SubTitle:GetText())
    X.alt(WFJ, false)
    assert.are.equal("ランク4に到達した。", toast.SubTitle:GetText())
    manager.next = { title = "Your Lotus Claw enchant allows you to carefully extract a Death Lotus!", subtitle = "" }
    manager:DisplayToast()
    assert.are.equal("Lotus Clawのエンチャントで慎重にDeath Lotusを採取できる！",
      manager.currentDisplayingToast.Title:GetText())
    -- an alert's field never takes the family
    local alert = { Title = Stub.fontString("You have reached Rank 4.") }
    _G.AlertFrame_ShowNewAlert(alert)
    assert.are.equal("You have reached Rank 4.", alert.Title:GetText())
  end)
end)
