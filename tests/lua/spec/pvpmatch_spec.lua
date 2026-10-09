-- The battleground scoreboard and match results on Forever: UI/PvPMatch.lua over PVPMatchResults /
-- PVPMatchScoreboard replayed from blizzard_pvpmatch/pvpmatchresults.lua (OnLoad :40–106, Init :108–186, OnUpdate
-- :378–387, DisplayRewards :257–368, the rating tooltip :529–557), pvpmatchscoreboard.lua (OnLoad :9–38) and
-- pvpmatchtable.lua (ConstructPVPMatchTable :340–481, PVPHeaderMixin:OnEnter :44–58, the honor-level cell :115–122).
-- Player, faction, spec and class names stay English. Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/PvPMatch.lua"

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local UI = {
  PVP_MATCH_VICTORY = { "VICTORY", "勝利" }, PVP_MATCH_DEFEAT = { "DEFEAT", "敗北" },
  PVP_MATCH_DRAW = { "DRAW", "引き分け" }, PVP_SCOREBOARD_MATCH_COMPLETE = { "Match Complete", "マッチ終了" },
  PVP_MATCH_LEAVE_BUTTON = { "Leave Match", "マッチから退出" },
  PVP_LEAVE_BUTTON_TIME = { "%s (%s)", "%s (%s)" },
  PVP_QUEUE_AGAIN = { "Queue As Team", "チームで再参加" },
  PVP_PROGRESS_REWARDS_HEADER = { "Progress", "進行状況" }, PVP_ITEM_REWARDS_HEADER = { "You earned", "獲得報酬" },
  PVP_RATING_UNCHANGED = { "Rating Unchanged", "レーティング変動なし" },
  PVP_RATING_HEADER = { "Rating", "レーティング" },
  BATTLEGROUND_YOUR_AVERAGE_RATING = { "Your Team's Matchmaking Value: |cffffffff%d|r",
    "自チームのマッチメイキング値: |cffffffff%d|r" },
  ALL = { "All", "すべて" }, NAME = { "Name", "名前" }, DEATHS = { "Deaths", "死亡回数" },
  SCORE_KILLING_BLOWS = { "Killing\nBlows", "キリング\nブロー" },
  SCORE_DAMAGE_DONE = { "Damage\nDone", "与\nダメージ" },
  KILLING_BLOW_TOOLTIP_TITLE = { "Killing Blows", "キリングブロー" },
  KILLING_BLOW_TOOLTIP = { "Enemy players to whom you have personally delivered the killing blow",
    "自分でとどめを刺した敵プレイヤーの数" },
  HONOR_LEVEL_TOOLTIP = { "Honor Level %d", "名誉レベル %d" },
  -- dictionary words that are names on this surface
  GUILD = { "Guild", "ギルド" }, PALADIN_WORD = { "Paladin", "パラディン" },
  -- A stat column's name and tooltip (C_PvP.GetMatchPVPStatColumns, client-table text)
  ["PvpColumn:1"] = { "Flag Captures", "旗の奪取" },
  ["PvpColumnTooltip:1"] = { "Number of times you have captured the flag", "旗を奪った回数" },
  -- a stat the column-header table does not name (PVPStat, Alterac Valley)
  ["PvpStat:61"] = { "Towers Assaulted", "塔への攻撃" },
}

local function en(key) return _G[key] end

local P = {} -- the replayed client state

-- CreateTableBuilder-like: a header pool, EnumerateHeaders (tablebuilder.lua:278–280), AddRow (:323–342).
local function tableBuilder()
  local tb = { name = "tableBuilder", active = {}, inactive = {} }
  function tb.Reset(self)
    for _, h in ipairs(self.active) do self.inactive[#self.inactive + 1] = h end
    self.active = {}
  end
  function tb.header(self, text, title, body)
    local h = table.remove(self.inactive) or CreateFrame("Button")
    h.text = h.text or Stub.fontString("")
    h.text.text, h.tooltipTitle, h.tooltipText = text, title, body
    h:SetScript("OnEnter", function(owner) -- PVPHeaderMixin:OnEnter
      if not (owner.tooltipTitle or owner.tooltipText) then return end
      _G.GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
      _G.GameTooltip:SetText(owner.tooltipTitle)
      if owner.tooltipText then _G.GameTooltip:AddLine(owner.tooltipText) end
      _G.GameTooltip:Show()
    end)
    self.active[#self.active + 1] = h
    return h
  end
  function tb.iconHeader(self)
    local h = CreateFrame("Button")
    h.icon = {}
    self.active[#self.active + 1] = h
    return h
  end
  function tb.EnumerateHeaders(self)
    local i = 0
    return function()
      i = i + 1
      return self.active[i]
    end
  end
  function tb.AddRow(_, row)
    local honor, class, name = CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Button")
    honor.icon, class.icon, name.text = {}, {}, Stub.fontString(row.rowData.name)
    honor:SetScript("OnEnter", function(owner) -- PVPCellHonorLevelMixin:OnEnter
      _G.GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
      _G.GameTooltip:ClearLines()
      _G.GameTooltip:AddLine(en("HONOR_LEVEL_TOOLTIP"):format(row.rowData.honorLevel))
      _G.GameTooltip:Show()
    end)
    class:SetScript("OnEnter", function(owner) -- PVPCellClassMixin:OnEnter: a class name
      _G.GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
      _G.GameTooltip:ClearLines()
      _G.GameTooltip:AddLine(row.rowData.className)
      _G.GameTooltip:Show()
    end)
    row.cells = { honor, class, name }
  end
  return tb
end

local function installPvPMatch()
  local results = CreateFrame("Frame", "PVPMatchResults")
  results.header = Stub.fontString("")
  results.buttonContainer = { leaveButton = Stub.button(nil, ""), requeueButton = Stub.button(nil, "") }
  local tabs = { tab1 = Stub.button("PVPScoreFrameTab1", ""), tab2 = Stub.button("PVPScoreFrameTab2", ""),
    tab3 = Stub.button("PVPScoreFrameTab3", "") }
  local function progress() return { text = Stub.fontString(""), button = CreateFrame("Button") } end
  results.content = {
    tabContainer = { tabGroup = tabs, matchmakingText = Stub.fontString("") },
    earningsContainer = {
      rewardsContainer = { header = Stub.fontString("") },
      progressContainer = { header = Stub.fontString(""), honor = progress(), conquest = progress(),
        rating = progress() },
    },
  }
  results.tableBuilder = tableBuilder()
  local earnings = results.content.earningsContainer
  -- OnLoad (:81–90)
  earnings.progressContainer.header.text = en("PVP_PROGRESS_REWARDS_HEADER")
  earnings.rewardsContainer.header.text = en("PVP_ITEM_REWARDS_HEADER")
  results.buttonContainer.requeueButton.fontString.text = en("PVP_QUEUE_AGAIN")
  tabs.tab1.fontString.text = en("ALL")
  function results.Init(self)
    self.header.text = en(P.outcome)
    self.buttonContainer.leaveButton.fontString.text = en("PVP_MATCH_LEAVE_BUTTON")
    tabs.tab2.fontString.text = string.format("%s (%s)", "Guild", 10) -- a faction name in the client; a word here
    tabs.tab3.fontString.text = string.format("%s (%s)", "Horde", 9)
    _G.ConstructPVPMatchTable(self.tableBuilder, false)
  end
  function results.DisplayRewards(self)
    local rating = self.content.earningsContainer.progressContainer.rating
    rating.text.text = en("PVP_RATING_UNCHANGED")
  end
  results:SetScript("OnUpdate", function(self) -- UpdateLeaveButton (:142–150)
    local button = self.buttonContainer.leaveButton
    if P.shutdown then
      button.fontString.text = string.format("%s (%s)", en("PVP_MATCH_LEAVE_BUTTON"), P.shutdown)
    else
      button.fontString.text = en("PVP_MATCH_LEAVE_BUTTON")
    end
  end)
  earnings.progressContainer.rating.button:SetScript("OnEnter", function(owner) -- :529–557
    _G.GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    _G.GameTooltip:SetText(en("PVP_RATING_HEADER"))
    _G.GameTooltip:AddLine(en("BATTLEGROUND_YOUR_AVERAGE_RATING"):format(1500))
    _G.GameTooltip:Show()
  end)

  local scoreboard = CreateFrame("Frame", "PVPMatchScoreboard")
  local sTabs = { Tab1 = Stub.button("PVPScoreboardTab1", en("ALL")), Tab2 = Stub.button("PVPScoreboardTab2", ""),
    Tab3 = Stub.button("PVPScoreboardTab3", "") }
  scoreboard.Content = { TabContainer = { TabGroup = sTabs, MatchmakingText = Stub.fontString("") } }
  scoreboard.tableBuilder = tableBuilder()

  _G.ConstructPVPMatchTable = function(tb)
    tb:Reset()
    tb:iconHeader()
    tb:header(en("NAME"))
    tb:header("Guild") -- a stat column's name is client-table text; here one that is also a dictionary word
    tb:header(en("SCORE_KILLING_BLOWS"), en("KILLING_BLOW_TOOLTIP_TITLE"), en("KILLING_BLOW_TOOLTIP"))
    if P.deaths then tb:header(en("DEATHS")) end
    tb:header(en("SCORE_DAMAGE_DONE"))
    if P.flag then -- a stat column (pvpmatchtable.lua:371–386): its name, title and tooltip text
      tb:header("Flag Captures", "Flag Captures", "Number of times you have captured the flag")
      tb:header("Flag Returns", "Flag Returns", "Number of times you have returned the flag") -- no row
      tb:header("Towers Assaulted") -- a PVPStat name
    end
  end
  return results, scoreboard
end

describe("the PvP scoreboard and match results on Forever", function()
  local WFJ, SS

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do
        if rec.fs == widget or (type(rec.fs) == "table" and rec.fs.button == widget) then return false end
      end
    end
    return true
  end

  local function headers(tb)
    local out = {}
    for h in tb:EnumerateHeaders() do out[#out + 1] = h.text and h.text:GetText() or "<icon>" end
    return out
  end

  local function fresh()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    P.outcome, P.shutdown, P.deaths, P.flag = "PVP_MATCH_VICTORY", nil, true, false
  end

  before_each(function()
    fresh()
    installPvPMatch()
    WFJ.Labels.forbidNames(WFJ.PvPMatch.NEVER_TOUCH)
    assert.is_true(WFJ.PvPMatch.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.PVPMatchResults, _G.PVPMatchScoreboard, _G.ConstructPVPMatchTable = nil, nil, nil
  end)

  it("the labels written at load are Japanese on both windows", function()
    local r = _G.PVPMatchResults
    assert.are.equal("チームで再参加", r.buttonContainer.requeueButton:GetText())
    assert.are.equal("進行状況", r.content.earningsContainer.progressContainer.header:GetText())
    assert.are.equal("獲得報酬", r.content.earningsContainer.rewardsContainer.header:GetText())
    assert.are.equal("すべて", _G.PVPScoreFrameTab1:GetText())
    assert.are.equal("すべて", _G.PVPScoreboardTab1:GetText())
  end)

  it("Init: the outcome, the leave button and the column headers translate; faction tabs and a stat column do not",
    function()
      local r = _G.PVPMatchResults
      r:Init()
      assert.are.equal("勝利", r.header:GetText())
      assert.are.equal("マッチから退出", r.buttonContainer.leaveButton:GetText())
      assert.are.same({ "<icon>", "名前", "Guild", "キリング\nブロー", "死亡回数", "与\nダメージ" },
        headers(r.tableBuilder))
      assert.are.equal("Guild (10)", _G.PVPScoreFrameTab2:GetText())
      assert.is_true(unrecorded(_G.PVPScoreFrameTab2))
      assert.is_true(WFJ.Labels.forbidden(_G.PVPScoreFrameTab2))
      alt(true)
      assert.are.equal("VICTORY", r.header:GetText())
      assert.are.same({ "<icon>", "Name", "Guild", "Killing\nBlows", "Deaths", "Damage\nDone" },
        headers(r.tableBuilder))
      alt(false)
      -- the next match rebuilds the table with fewer columns: pooled headers show their new words
      P.outcome, P.deaths = "PVP_MATCH_DEFEAT", false
      r:Init()
      assert.are.equal("敗北", r.header:GetText())
      for _, text in ipairs(headers(r.tableBuilder)) do assert.are_not.equal("Deaths", text) end
      assert.are.equal("名前", headers(r.tableBuilder)[2])
    end)

  it("the scoreboard's table is followed through the same global writer", function()
    local s = _G.PVPMatchScoreboard
    _G.ConstructPVPMatchTable(s.tableBuilder, false)
    assert.are.same({ "<icon>", "名前", "Guild", "キリング\nブロー", "死亡回数", "与\nダメージ" },
      headers(s.tableBuilder))
  end)

  it("OnUpdate: the leave button is re-shown after each client rewrite", function()
    local r = _G.PVPMatchResults
    r:Init()
    r.scripts.OnUpdate(r)
    assert.are.equal("マッチから退出", r.buttonContainer.leaveButton:GetText())
    P.shutdown = "59s"
    r.scripts.OnUpdate(r)
    -- "%s (%s)" renders only once Core/UIStrings.ARGS carries its `entry` / `text` arguments
    if WFJ.UIStrings.ARGS.PVP_LEAVE_BUTTON_TIME then
      assert.are.equal("マッチから退出 (59s)", r.buttonContainer.leaveButton:GetText())
    else
      assert.are.equal("Leave Match (59s)", r.buttonContainer.leaveButton:GetText())
    end
  end)

  it("DisplayRewards: the rating line translates", function()
    local r = _G.PVPMatchResults
    r:DisplayRewards()
    assert.are.equal("レーティング変動なし", r.content.earningsContainer.progressContainer.rating.text:GetText())
  end)

  it("tooltips: a column header's, the rating button's and the honor-level cell's translate; a class name does not",
    function()
      local r = _G.PVPMatchResults
      r:Init()
      local kills
      for h in r.tableBuilder:EnumerateHeaders() do
        if h.tooltipTitle then kills = h end
      end
      kills.scripts.OnEnter(kills)
      assert.are.equal("キリングブロー", _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("自分でとどめを刺した敵プレイヤーの数", _G.GameTooltipTextLeft2:GetText())
      local ratingButton = r.content.earningsContainer.progressContainer.rating.button
      ratingButton.scripts.OnEnter(ratingButton)
      assert.are.equal("レーティング", _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("自チームのマッチメイキング値: |cffffffff1500|r", _G.GameTooltipTextLeft2:GetText())
      local row = { rowData = { name = "Guild", className = "Paladin", honorLevel = 7 } }
      r.tableBuilder:AddRow(row, 1)
      local honor, class, name = row.cells[1], row.cells[2], row.cells[3]
      honor.scripts.OnEnter(honor)
      assert.are.equal("名誉レベル 7", _G.GameTooltipTextLeft1:GetText())
      class.scripts.OnEnter(class)
      assert.are.equal("Paladin", _G.GameTooltipTextLeft1:GetText()) -- a class name, though a dictionary word here
      assert.are.equal("Guild", name.text:GetText()) -- a player's name
      assert.is_true(unrecorded(name.text))
    end)

  it("a stat column's header (either table) and its tooltip are Japanese; a column with no row stays; Alt English",
    function()
      P.flag = true
      local r = _G.PVPMatchResults
      r:Init()
      assert.are.same({ "<icon>", "名前", "Guild", "キリング\nブロー", "死亡回数", "与\nダメージ", "旗の奪取",
        "Flag Returns", "塔への攻撃" }, headers(r.tableBuilder))
      local flag, returns
      for h in r.tableBuilder:EnumerateHeaders() do
        if h.tooltipTitle == "Flag Captures" then flag = h end
        if h.tooltipTitle == "Flag Returns" then returns = h end
      end
      flag.scripts.OnEnter(flag)
      assert.are.equal("旗の奪取", _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("旗を奪った回数", _G.GameTooltipTextLeft2:GetText())
      returns.scripts.OnEnter(returns)
      assert.are.equal("Flag Returns", _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("Number of times you have returned the flag", _G.GameTooltipTextLeft2:GetText())
      alt(true)
      assert.are.equal("Flag Captures", headers(r.tableBuilder)[7])
      alt(false)
      assert.are.equal("旗の奪取", headers(r.tableBuilder)[7])
      assert.is_nil(WFJ.UIIndex:match("Flag Captures")) -- the family only where the headers name it
      assert.is_nil(WFJ.UIIndex:match("Towers Assaulted"))
    end)

  it("client names bound to the wrong type degrade to English with no error", function()
    fresh()
    local results, scoreboard = installPvPMatch()
    results.header, results.buttonContainer, results.tableBuilder, results.Init = 7, "x", true, "no"
    results.content.earningsContainer = false
    scoreboard.Content, scoreboard.tableBuilder = 3, { EnumerateHeaders = 1, AddRow = 2 }
    _G.ConstructPVPMatchTable = "not a function"
    assert.has_no.errors(function() assert.is_true(WFJ.PvPMatch.init()) end)
    assert.has_no.errors(function()
      WFJ.PvPMatch.onTable(nil)
      WFJ.PvPMatch.onTable({ EnumerateHeaders = function() return function() end end })
      WFJ.PvPMatch.onRow(nil, { cells = { 1, "x", { icon = 1 } } })
      WFJ.PvPMatch.onRow(nil, nil)
      WFJ.PvPMatch.onLeaveButton()
      WFJ.PvPMatch.onRewards()
    end)
  end)

  it("hooks install once; a client with neither window is skipped without error", function()
    assert.is_false(WFJ.PvPMatch.init())
    assert.are.equal(1, #Stub.hooks["PVPMatchResults:Init"])
    assert.are.equal(1, #Stub.hooks["ConstructPVPMatchTable"])
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    _G.PVPMatchResults, _G.PVPMatchScoreboard, _G.ConstructPVPMatchTable = nil, nil, nil
    local bare = H.loadChunks(FILES)
    H.uiSetup(bare, UI)
    assert.has_no.errors(function() assert.is_false(bare.PvPMatch.init()) end)
  end)
end)
