-- Honor → PvP rank on Forever: UI/PvPRank.lua over a PVPRankFrame replayed from camelot
-- blizzard_uipanels_game/camelot/pvprankframe.lua (Update :90–122, UpdateSeasonCountdownTimer :78–88,
-- DetailFrame:Refresh :132–217 through CharacterFrameSidePaneMixin, characterframe.lua:850–951). Rank titles stay
-- English. Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/PvPRank.lua"

-- Forever GlobalStrings (build 1.60.1.69913) → a test Japanese
local UI = {
  PVP_RANK_CURRENT_PROGRESS = { "Rank Points: |cnHIGHLIGHT_FONT_COLOR:%d / %d|r",
    "ランクポイント: |cnHIGHLIGHT_FONT_COLOR:%d / %d|r" },
  PVP_RANK_NUMBER = { "Rank %d", "ランク %d" },
  PVP_RANK_DETAIL_UNAVAILABLE = { "PvP Rank's are currently unavailable.", "PvPランクは現在利用できません。" },
  PVP_RANK_SEASON_RANKUP_DESCRIPTION = { "Each week, the Rank Points cap is increased, up to a maximum of "
    .. "|cnHIGHLIGHT_FONT_COLOR:%d|r for |cnHIGHLIGHT_FONT_COLOR:Rank %d|r.",
    "毎週ランクポイントの上限が上がり、最大|cnHIGHLIGHT_FONT_COLOR:%d|r（|cnHIGHLIGHT_FONT_COLOR:ランク%d|r）になります。" },
  PVP_RANK_SEASON_PROGRESS = { "Total Rank Progress: |cnHIGHLIGHT_FONT_COLOR:%d / %d|r",
    "ランク進行度合計: |cnHIGHLIGHT_FONT_COLOR:%d / %d|r" },
  PVP_RANK_SEASON_PROGRESS_NO_MAX = { "Total Rank Progress: |cnHIGHLIGHT_FONT_COLOR:%d|r",
    "ランク進行度合計: |cnHIGHLIGHT_FONT_COLOR:%d|r" },
  PVP_RANK_WEEKLY_CAP_INCREASE = { "Cap increase this week: |cnHIGHLIGHT_FONT_COLOR:%d|r",
    "今週の上限増加: |cnHIGHLIGHT_FONT_COLOR:%d|r" },
  PVP_RANK_NEXT_REWARD = { "|cFFFFFFFFNext Rewards at Rank %d|r", "|cFFFFFFFFランク%dの次の報酬|r" },
  PVP_RANK_REWARDS_VENDOR_HORDE = { "|cFFFFFFFFRewards may be purchased at the Hall of Legends in Orgrimmar.|r",
    "|cFFFFFFFF報酬はOrgrimmarのHall of Legendsで購入できます。|r" },
  -- the real Core/UIStrings ARGS carry these: the rank title a `text` argument, the empty season prefix a `text`
  -- argument, the countdown a `time` argument over the unabbreviated D_* units
  PVP_RANK_NUMBER_AND_TITLE = { "Rank %d - %s", "ランク%d - %s" },
  EXPANSION_SEASON_NAME = { "%s Season %d", "%sシーズン%d" },
  SEASON_ENDS_IN_TIME = { "Season ends in: %s", "シーズン終了まで: %s" },
  D_DAYS = { "%d |4Day:Days;", "%d日" }, D_HOURS = { "%d |4Hour:Hours;", "%d時間" },
  D_MINUTES = { "%d |4Minute:Minutes;", "%d分" }, D_SECONDS = { "%d |4Second:Seconds;", "%d秒" },
  -- rank titles: in the dictionary, and never shown in Japanese on this surface
  PVP_RANK_0_NAME = { "Civilian", "民間人" }, PVP_RANK_1_NAME = { "Combatant I", "コンバタントI" },
  RANK = { "Rank", "ランク" },
  -- renown reward rows (C_MajorFactions.GetRenownRewardsForLevel description / name / toastDescription)
  ["RenownRewardDescription:1832"] = { "Faction Tabard", "陣営タバード" },
  ["RenownRewardName:1832"] = { "Rank 1 Rewards", "ランク1の報酬" },
  ["RenownRewardToast:1832"] = { "Faction Tabard Unlocked", "陣営タバード解放" },
}

-- A CreateFramePoolCollection-like pool of side-pane rows (characterframe.lua:840–845).
local function rowPool()
  local p = { active = {}, inactive = {} }
  function p.Acquire(self)
    local row = table.remove(self.inactive) or { Label = Stub.fontString("") }
    function row.SetHeight(r, h) r.height = h end
    self.active[#self.active + 1] = row
    return row
  end
  function p.ReleaseAll(self)
    for _, r in ipairs(self.active) do self.inactive[#self.inactive + 1] = r end
    self.active = {}
  end
  function p.EnumerateActive(self)
    local i = 0
    return function()
      i = i + 1
      if self.active[i] then return self.active[i], true end
    end
  end
  return p
end

local P = {} -- the replayed client state: P.info = { rank, points, threshold, seasonMax, weekMax, weekCap } | nil

local function en(key) return _G[key] end

local function installPvPRank()
  local frame = CreateFrame("Frame", "PVPRankFrame")
  frame.SeasonTimerField = Stub.fontString("")
  local main = CreateFrame("Frame")
  frame.MainInfoFrame = main
  main.CurrentSeasonField = Stub.fontString("")
  main.CurrentRankField = Stub.fontString("")
  main.CurrentRankProgressField = Stub.fontString("")
  main.RankProgressBarDisplay = { NextRewardLevel = { LevelLabel = Stub.fontString("") } }
  local detail = CreateFrame("Frame")
  frame.DetailFrame = detail
  detail.Title = Stub.fontString("")
  detail.Subtitle = Stub.fontString("")
  detail.EmptyText = Stub.fontString("")
  local descText = Stub.fontString("")
  detail.Description = CreateFrame("Frame")
  function detail.Description.GetFontString() return descText end
  function detail.Description.SetText(_, t) descText.text = t end
  detail.rowPools = rowPool()
  detail.layouts = 0
  function detail.LayoutRows(self) self.layouts = self.layouts + 1 end -- Content:Layout (characterframe.lua:946)

  local function row(text) detail.rowPools:Acquire().Label.text = text end
  function frame.UpdateSeasonCountdownTimer(self)
    self.SeasonTimerField.text = string.format("Season ends in: %s", "5 Days 3 Hours")
  end
  function frame.Update(self)
    local info = P.info
    if not info then return end
    self:UpdateSeasonCountdownTimer()
    self.MainInfoFrame.CurrentSeasonField.text = string.format("%s Season %d", "", 1)
    if info.rank == 0 then
      self.MainInfoFrame.CurrentRankField.text = en("PVP_RANK_0_NAME")
    else
      self.MainInfoFrame.CurrentRankField.text = string.format("Rank %d - %s", info.rank, en("PVP_RANK_1_NAME"))
    end
    self.MainInfoFrame.CurrentRankProgressField.text = string.format(en("PVP_RANK_CURRENT_PROGRESS"), info.points,
      info.threshold)
    self.MainInfoFrame.RankProgressBarDisplay.NextRewardLevel.LevelLabel.text = tostring(info.rank)
    self.DetailFrame:Refresh()
  end
  function detail.Refresh(self)
    local info = P.info
    if not info then -- SetEmpty (characterframe.lua:939–948)
      self.rowPools:ReleaseAll()
      self.Title.text, self.Subtitle.text = "", ""
      self.EmptyText.text = en("PVP_RANK_DETAIL_UNAVAILABLE")
      return
    end
    self.Title.text = info.rank > 0 and en("PVP_RANK_1_NAME") or en("PVP_RANK_0_NAME")
    self.Subtitle.text = info.rank > 0 and string.format(en("PVP_RANK_NUMBER"), info.rank) or ""
    self.Description:SetText(string.format(en("PVP_RANK_SEASON_RANKUP_DESCRIPTION"), info.seasonMaxRep, 8))
    self.rowPools:ReleaseAll()
    if info.weekMax == 0 then
      row(string.format(en("PVP_RANK_SEASON_PROGRESS_NO_MAX"), info.points))
    else
      row(string.format(en("PVP_RANK_SEASON_PROGRESS"), info.points, info.weekMax))
    end
    if info.weekCap > 0 then
      row("") -- AddSpacer
      row(string.format(en("PVP_RANK_WEEKLY_CAP_INCREASE"), info.weekCap))
    end
    row(string.format(en("PVP_RANK_NEXT_REWARD"), info.rank + 1))
    -- the next rewards' descriptions (AddIconRow, :198-211): by default one that is also a dictionary word
    for _, description in ipairs(info.rewards or { "Rank" }) do row(description) end
    row(en("PVP_RANK_REWARDS_VENDOR_HORDE"))
  end
  return frame
end

describe("the PvP rank panel on Forever", function()
  local WFJ, SS

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function labels()
    local out = {}
    for r in _G.PVPRankFrame.DetailFrame.rowPools:EnumerateActive() do out[#out + 1] = r.Label:GetText() end
    return out
  end

  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do
        if rec.fs == widget then return false end
      end
    end
    return true
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    installPvPRank()
    P.info = { rank = 1, points = 120, threshold = 500, seasonMaxRep = 1500, weekMax = 900, weekCap = 300 }
    WFJ.Labels.forbidNames(WFJ.PvPRank.NEVER_TOUCH)
    assert.is_true(WFJ.PvPRank.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.PVPRankFrame = nil
  end)

  it("Update: season, rank and progress translate; the rank title inside them and the level number stay English",
    function()
    _G.PVPRankFrame:Update()
    local main = _G.PVPRankFrame.MainInfoFrame
    assert.are.equal("ランクポイント: |cnHIGHLIGHT_FONT_COLOR:120 / 500|r", main.CurrentRankProgressField:GetText())
    assert.are.equal("ランク1 - Combatant I", main.CurrentRankField:GetText()) -- the title is kept as written
    assert.are.equal("シーズン1", main.CurrentSeasonField:GetText()) -- the empty prefix stays empty
    assert.are.equal("1", main.RankProgressBarDisplay.NextRewardLevel.LevelLabel:GetText())
    P.info.rank = 0
    _G.PVPRankFrame:Update()
    assert.are.equal("Civilian", main.CurrentRankField:GetText()) -- PVP_RANK_0_NAME is a rank title
    assert.is_true(unrecorded(main.CurrentRankField))
    alt(true)
    assert.are.equal("Rank Points: |cnHIGHLIGHT_FONT_COLOR:120 / 500|r", main.CurrentRankProgressField:GetText())
    alt(false)
  end)

  it("Refresh: subtitle, description and the pooled rows translate; the title and a reward description do not",
    function()
      _G.PVPRankFrame:Update()
      local detail = _G.PVPRankFrame.DetailFrame
      assert.are.equal("Combatant I", detail.Title:GetText())
      assert.is_true(unrecorded(detail.Title))
      assert.are.equal("ランク 1", detail.Subtitle:GetText())
      assert.are.equal(UI.PVP_RANK_SEASON_RANKUP_DESCRIPTION[2]:format(1500, 8),
        detail.Description:GetFontString():GetText())
      assert.are.same({ "ランク進行度合計: |cnHIGHLIGHT_FONT_COLOR:120 / 900|r", "",
        "今週の上限増加: |cnHIGHLIGHT_FONT_COLOR:300|r", "|cFFFFFFFFランク2の次の報酬|r", "Rank",
        "|cFFFFFFFF報酬はOrgrimmarのHall of Legendsで購入できます。|r" }, labels())
      -- the pool reshuffles on the next refresh (rows reused for other lines): each shows its new line
      P.info.weekCap, P.info.weekMax = 0, 0
      detail:Refresh()
      assert.are.same({ "ランク進行度合計: |cnHIGHLIGHT_FONT_COLOR:120|r", "|cFFFFFFFFランク2の次の報酬|r", "Rank",
        "|cFFFFFFFF報酬はOrgrimmarのHall of Legendsで購入できます。|r" }, labels())
      alt(true)
      assert.are.same({ "Total Rank Progress: |cnHIGHLIGHT_FONT_COLOR:120|r", "|cFFFFFFFFNext Rewards at Rank 2|r",
        "Rank", "|cFFFFFFFFRewards may be purchased at the Hall of Legends in Orgrimmar.|r" }, labels())
      alt(false)
    end)

  it("no rank data: the empty text translates", function()
    P.info = nil
    _G.PVPRankFrame.DetailFrame:Refresh()
    assert.are.equal("PvPランクは現在利用できません。", _G.PVPRankFrame.DetailFrame.EmptyText:GetText())
  end)

  it("the countdown ticker's hook translates the duration each tick; Alt shows the client's English", function()
    _G.PVPRankFrame:UpdateSeasonCountdownTimer()
    assert.are.equal("シーズン終了まで: 5日3時間", _G.PVPRankFrame.SeasonTimerField:GetText())
    alt(true)
    assert.are.equal("Season ends in: 5 Days 3 Hours", _G.PVPRankFrame.SeasonTimerField:GetText())
    alt(false)
    _G.PVPRankFrame.SeasonTimerField.text = "Season ends in: 5 Days 2 Hours" -- the next tick's client write
    WFJ.PvPRank.onTimer()
    assert.are.equal("シーズン終了まで: 5日2時間", _G.PVPRankFrame.SeasonTimerField:GetText())
    assert.are.equal(1, #Stub.hooks["PVPRankFrame:UpdateSeasonCountdownTimer"])
  end)

  it("hooks install once; a client without PVPRankFrame is skipped without error", function()
    assert.is_false(WFJ.PvPRank.init())
    assert.are.equal(1, #Stub.hooks["PVPRankFrame:Update"])
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    _G.PVPRankFrame = nil
    local bare = H.loadChunks(FILES)
    H.uiSetup(bare, UI)
    assert.has_no.errors(function() assert.is_false(bare.PvPRank.init()) end)
  end)

  it("a reward row's RenownRewardDescription row is Japanese and the pane is laid out again; Alt shows English;"
    .. " a description with no row and another family's row stay", function()
    P.info.rewards = { "Faction Tabard", "Gryphon Rider's Lance", "Rank 1 Rewards", "Faction Tabard Unlocked" }
    local detail = _G.PVPRankFrame.DetailFrame
    local before = detail.layouts
    detail:Refresh()
    local l = labels()
    assert.are.equal("陣営タバード", l[5])
    assert.are.equal("Gryphon Rider's Lance", l[6]) -- an item's name: no row
    assert.are.equal("Rank 1 Rewards", l[7]) -- a RenownRewardName row: not this widget's family
    assert.are.equal("Faction Tabard Unlocked", l[8]) -- a RenownRewardToast row: not this widget's family
    assert.is_true(detail.layouts > before)
    alt(true)
    assert.are.equal("Faction Tabard", labels()[5])
    alt(false)
    assert.are.equal("陣営タバード", labels()[5])
  end)
end)
