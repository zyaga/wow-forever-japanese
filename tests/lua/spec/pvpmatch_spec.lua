-- The battleground scoreboard and match results on Forever: UI/PvPMatch.lua over PVPMatchResults /
-- PVPMatchScoreboard replayed from camelot's own windows, blizzard_pvpmatch/camelot/pvpmatchresults.lua (OnLoad
-- :15–46, Init :48–99, OnUpdate :132–141; DisplayRewards and the reward frames are empty, :124–126, 151–165) and
-- camelot/pvpmatchscoreboard.lua (OnLoad :9–36, Init :38–51, UpdateMapName :53–59), and pvpmatchtable.lua
-- (ConstructPVPMatchTable :377–520 with camelot's KILLS header and Honor Gained column,
-- camelot/pvpmatchtableoverrides.lua:34–43; PVPHeaderMixin:OnEnter :44–58, the honor-level cell :139–146).
-- Player, faction, zone, spec and class names stay English. Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/PvPMatch.lua"

-- Forever GlobalStrings (build 1.60.1.70685) → a test Japanese
local UI = {
  VICTORY_TEXT0 = { "Horde Wins", "Horde の勝利" }, VICTORY_TEXT1 = { "Alliance Wins", "Alliance の勝利" },
  PVP_MATCH_DRAW = { "DRAW", "引き分け" },
  PVP_MATCH_LEAVE_BUTTON = { "Leave Match", "マッチから退出" },
  PVP_LEAVE_BUTTON_TIME = { "%s (%s)", "%s (%s)" },
  ALL = { "All", "すべて" }, NAME = { "Name", "名前" }, DEATHS = { "Deaths", "死亡回数" },
  SCORE_KILLING_BLOWS = { "Killing\nBlows", "キリング\nブロー" },
  KILLS = { "Kills", "キル" }, SCORE_HONOR_GAINED = { "Honor\nGained", "獲得\n名誉" },
  SCORE_DAMAGE_DONE = { "Damage\nDone", "与\nダメージ" },
  KILLING_BLOW_TOOLTIP_TITLE = { "Killing Blows", "キリングブロー" },
  KILLING_BLOW_TOOLTIP = { "Enemy players to whom you have personally delivered the killing blow",
    "自分でとどめを刺した敵プレイヤーの数" },
  HONOR_LEVEL_TOOLTIP = { "Honor Level %d", "名誉レベル %d" },
  PVP_RANK_NUMBER_AND_TITLE = { "Rank %d - %s", "ランク %d - %s" },
  -- dictionary words that are names on this surface
  GUILD = { "Guild", "ギルド" }, PALADIN_WORD = { "Paladin", "パラディン" },
  -- a zone name that is also a dictionary word here: the scoreboard's header holds the map's name
  ZONE_WORD = { "Arena", "アリーナ" },
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
      -- camelot's override writes the PvP rank and its title instead (camelot/pvpmatchtableoverrides.lua:25–32)
      local line = row.rowData.rankTitle and en("PVP_RANK_NUMBER_AND_TITLE"):format(row.rowData.honorLevel,
        row.rowData.rankTitle) or en("HONOR_LEVEL_TOOLTIP"):format(row.rowData.honorLevel)
      _G.GameTooltip:AddLine(line)
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
  -- camelot/pvpmatchresults.xml:5–150: a HeaderContainer.Text outcome line, the leave button, three tabs, the table
  local results = CreateFrame("Frame", "PVPMatchResults")
  results.HeaderContainer = { Text = Stub.fontString("") }
  results.buttonContainer = { leaveButton = Stub.button(nil, "") }
  local tabs = { tab1 = Stub.button("PVPScoreFrameTab1", ""), tab2 = Stub.button("PVPScoreFrameTab2", ""),
    tab3 = Stub.button("PVPScoreFrameTab3", "") }
  results.content = { tabContainer = { tabGroup = tabs } }
  -- OnLoad (:15–46)
  results.header = results.HeaderContainer.Text
  results.leaveButton = results.buttonContainer.leaveButton
  results.tableBuilder = tableBuilder()
  tabs.tab1.fontString.text = en("ALL")
  function results.Init(self) -- :48–99
    if self.isInitialized then return end
    self.isInitialized = true
    if P.winner == "draw" then
      self.header.text = en("PVP_MATCH_DRAW")
    else -- the winner's line in its team colour (:54–63)
      local colour = P.winner == "alliance" and "|cff0060ff" or "|cffff0000"
      self.header.text = colour .. en(P.winner == "alliance" and "VICTORY_TEXT1" or "VICTORY_TEXT0") .. "|r"
    end
    self.leaveButton.fontString.text = en("PVP_MATCH_LEAVE_BUTTON")
    tabs.tab2.fontString.text = string.format("%s (%s)", "Guild", 10) -- a faction name in the client; a word here
    tabs.tab3.fontString.text = string.format("%s (%s)", "Horde", 9)
    _G.ConstructPVPMatchTable(self.tableBuilder, false)
  end
  function results.Shutdown(self) self.isInitialized = false end -- :101–105
  function results.DisplayRewards() end -- :124–126
  results:SetScript("OnUpdate", function(self) -- UpdateLeaveButton (:75–83, from OnUpdate :132–135)
    local button = self.leaveButton
    if P.shutdown then
      button.fontString.text = string.format("%s (%s)", en("PVP_MATCH_LEAVE_BUTTON"), P.shutdown)
    else
      button.fontString.text = en("PVP_MATCH_LEAVE_BUTTON")
    end
  end)

  -- camelot/pvpmatchscoreboard.xml:5–122: a HeaderContainer.Text map name, three tabs, the table
  local scoreboard = CreateFrame("Frame", "PVPMatchScoreboard")
  scoreboard.HeaderContainer = { Text = Stub.fontString("") }
  local sTabs = { Tab1 = Stub.button("PVPScoreboardTab1", en("ALL")), Tab2 = Stub.button("PVPScoreboardTab2", ""),
    Tab3 = Stub.button("PVPScoreboardTab3", "") }
  scoreboard.Content = { TabContainer = { TabGroup = sTabs } }
  scoreboard.tableBuilder = tableBuilder()
  scoreboard:SetScript("OnShow", function(self) -- UpdateMapName (:53–59, from OnShow :98–101)
    self.HeaderContainer.Text.text = "Arena"
  end)

  _G.ConstructPVPMatchTable = function(tb)
    tb:Reset()
    tb:iconHeader()
    tb:header(en("NAME"))
    tb:header("Guild") -- a stat column's name is client-table text; here one that is also a dictionary word
    tb:header(en("SCORE_KILLING_BLOWS"), en("KILLING_BLOW_TOOLTIP_TITLE"), en("KILLING_BLOW_TOOLTIP"))
    tb:header(en("KILLS")) -- camelot's GetHonorableKillsHeaderTextID (camelot/pvpmatchtableoverrides.lua:34–36)
    if P.deaths then tb:header(en("DEATHS")) end
    tb:header(en("SCORE_DAMAGE_DONE"))
    if P.flag then -- a stat column (pvpmatchtable.lua:408–423): its name, title and tooltip text
      tb:header("Flag Captures", "Flag Captures", "Number of times you have captured the flag")
      tb:header("Flag Returns", "Flag Returns", "Number of times you have returned the flag") -- no row
      tb:header("Towers Assaulted") -- a PVPStat name
    end
    tb:header(en("SCORE_HONOR_GAINED")) -- camelot's TryAddHonorColumn (camelot/pvpmatchtableoverrides.lua:38–43)
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
    P.winner, P.shutdown, P.deaths, P.flag = "draw", nil, true, false
  end

  -- a new match: the window's Shutdown clears the Init guard (camelot/pvpmatchresults.lua:49–52, 101–105)
  local function nextMatch(r)
    r:Shutdown()
    r:Init()
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

  it("the labels written at load are Japanese on both windows; the scoreboard's map name is never touched", function()
    assert.are.equal("すべて", _G.PVPScoreFrameTab1:GetText())
    assert.are.equal("すべて", _G.PVPScoreboardTab1:GetText())
    local s = _G.PVPMatchScoreboard
    s.scripts.OnShow(s)
    assert.are.equal("Arena", s.HeaderContainer.Text:GetText()) -- a zone name, though a dictionary word here
    assert.is_true(unrecorded(s.HeaderContainer.Text))
    assert.is_true(WFJ.Labels.forbidden(s.HeaderContainer.Text))
  end)

  it("Init: the outcome, the leave button and the column headers translate; faction tabs and a stat column do not",
    function()
      local r = _G.PVPMatchResults
      r:Init()
      assert.are.equal("引き分け", r.header:GetText())
      assert.are.equal("マッチから退出", r.leaveButton:GetText())
      assert.are.same({ "<icon>", "名前", "Guild", "キリング\nブロー", "キル", "死亡回数", "与\nダメージ",
        "獲得\n名誉" }, headers(r.tableBuilder))
      assert.are.equal("Guild (10)", _G.PVPScoreFrameTab2:GetText())
      assert.is_true(unrecorded(_G.PVPScoreFrameTab2))
      assert.is_true(WFJ.Labels.forbidden(_G.PVPScoreFrameTab2))
      alt(true)
      assert.are.equal("DRAW", r.header:GetText())
      assert.are.same({ "<icon>", "Name", "Guild", "Killing\nBlows", "Kills", "Deaths", "Damage\nDone",
        "Honor\nGained" }, headers(r.tableBuilder))
      alt(false)
      -- the next match rebuilds the table with fewer columns: pooled headers show their new words
      P.deaths = false
      nextMatch(r)
      for _, text in ipairs(headers(r.tableBuilder)) do assert.are_not.equal("Deaths", text) end
      assert.are.equal("名前", headers(r.tableBuilder)[2])
      assert.are.equal("獲得\n名誉", headers(r.tableBuilder)[7])
    end)

  it("Init: the winner's line keeps its team colour around the Japanese, the faction name kept English", function()
    local r = _G.PVPMatchResults
    -- a colour-wrapped line renders once Core/UIStrings grants these keys the `wrapped` label form
    local wrapped = WFJ.UIStrings.hasForm("VICTORY_TEXT1", "wrapped")
      and WFJ.UIStrings.hasForm("VICTORY_TEXT0", "wrapped")
    P.winner = "alliance"
    r:Init()
    assert.are.equal(wrapped and "|cff0060ffAlliance の勝利|r" or "|cff0060ffAlliance Wins|r", r.header:GetText())
    alt(true)
    assert.are.equal("|cff0060ffAlliance Wins|r", r.header:GetText())
    alt(false)
    P.winner = "horde"
    nextMatch(r)
    assert.are.equal(wrapped and "|cffff0000Horde の勝利|r" or "|cffff0000Horde Wins|r", r.header:GetText())
    -- the window shown again (BeginShow → Init returns at its guard, :49–52): the line stays Japanese
    r:Init()
    assert.are.equal(wrapped and "|cffff0000Horde の勝利|r" or "|cffff0000Horde Wins|r", r.header:GetText())
  end)

  it("the scoreboard's table is followed through the same global writer", function()
    local s = _G.PVPMatchScoreboard
    _G.ConstructPVPMatchTable(s.tableBuilder, false)
    assert.are.same({ "<icon>", "名前", "Guild", "キリング\nブロー", "キル", "死亡回数", "与\nダメージ",
      "獲得\n名誉" }, headers(s.tableBuilder))
  end)

  it("OnUpdate: the leave button is re-shown after each client rewrite", function()
    local r = _G.PVPMatchResults
    r:Init()
    r.scripts.OnUpdate(r)
    assert.are.equal("マッチから退出", r.leaveButton:GetText())
    P.shutdown = "59s"
    r.scripts.OnUpdate(r)
    -- "%s (%s)" renders only once Core/UIStrings.ARGS carries its `entry` / `text` arguments
    if WFJ.UIStrings.ARGS.PVP_LEAVE_BUTTON_TIME then
      assert.are.equal("マッチから退出 (59s)", r.leaveButton:GetText())
    else
      assert.are.equal("Leave Match (59s)", r.leaveButton:GetText())
    end
  end)

  it("Forever's results window has no rewards: DisplayRewards is not hooked", function()
    assert.is_nil(Stub.hooks["PVPMatchResults:DisplayRewards"])
    assert.is_nil(WFJ.PvPMatch.onRewards)
  end)

  it("tooltips: a column header's and the honor-level cell's translate; a class name does not", function()
    local r = _G.PVPMatchResults
    r:Init()
    local kills
    for h in r.tableBuilder:EnumerateHeaders() do
      if h.tooltipTitle then kills = h end
    end
    kills.scripts.OnEnter(kills)
    assert.are.equal("キリングブロー", _G.GameTooltipTextLeft1:GetText())
    assert.are.equal("自分でとどめを刺した敵プレイヤーの数", _G.GameTooltipTextLeft2:GetText())
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

  it("the honor-level cell's Forever tooltip (the PvP rank and its title) is Japanese, the title kept English",
    function()
      local r = _G.PVPMatchResults
      r:Init()
      local row = { rowData = { name = "Guild", className = "Paladin", honorLevel = 7,
        rankTitle = "Knight-Lieutenant" } }
      r.tableBuilder:AddRow(row, 1)
      r.tableBuilder:AddRow(row, 1) -- a pooled cell is registered once
      local honor = row.cells[1]
      honor.scripts.OnEnter(honor)
      assert.are.equal("ランク 7 - Knight-Lieutenant", _G.GameTooltipTextLeft1:GetText())
      alt(true)
      assert.are.equal("Rank 7 - Knight-Lieutenant", _G.GameTooltipTextLeft1:GetText())
      alt(false)
      assert.are.equal("ランク 7 - Knight-Lieutenant", _G.GameTooltipTextLeft1:GetText())
      row.rowData.rankTitle = "Paladin" -- a title that is also a dictionary word stays as the client wrote it
      honor.scripts.OnEnter(honor)
      assert.are.equal("ランク 7 - Paladin", _G.GameTooltipTextLeft1:GetText())
      WFJ.State.setEnabled(false)
      honor.scripts.OnEnter(honor)
      assert.are.equal("Rank 7 - Paladin", _G.GameTooltipTextLeft1:GetText())
      WFJ.State.setEnabled(true)
    end)

  it("a stat column's header (either table) and its tooltip are Japanese; a column with no row stays; Alt English",
    function()
      P.flag = true
      local r = _G.PVPMatchResults
      r:Init()
      assert.are.same({ "<icon>", "名前", "Guild", "キリング\nブロー", "キル", "死亡回数", "与\nダメージ", "旗の奪取",
        "Flag Returns", "塔への攻撃", "獲得\n名誉" }, headers(r.tableBuilder))
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
      assert.are.equal("Flag Captures", headers(r.tableBuilder)[8])
      alt(false)
      assert.are.equal("旗の奪取", headers(r.tableBuilder)[8])
      assert.is_nil(WFJ.UIIndex:match("Flag Captures")) -- the family only where the headers name it
      assert.is_nil(WFJ.UIIndex:match("Towers Assaulted"))
    end)

  it("client names bound to the wrong type degrade to English with no error", function()
    fresh()
    local results, scoreboard = installPvPMatch()
    results.header, results.buttonContainer, results.tableBuilder, results.Init = 7, "x", true, "no"
    results.HeaderContainer = false
    scoreboard.Content, scoreboard.tableBuilder = 3, { EnumerateHeaders = 1, AddRow = 2 }
    _G.ConstructPVPMatchTable = "not a function"
    assert.has_no.errors(function() assert.is_true(WFJ.PvPMatch.init()) end)
    assert.has_no.errors(function()
      WFJ.PvPMatch.onTable(nil)
      WFJ.PvPMatch.onTable({ EnumerateHeaders = function() return function() end end })
      WFJ.PvPMatch.onRow(nil, { cells = { 1, "x", { icon = 1 } } })
      WFJ.PvPMatch.onRow(nil, nil)
      WFJ.PvPMatch.onLeaveButton()
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
