-- UI/Inspect.lua over an InspectFrame replayed from camelot blizzard_inspectui (build 1.60.1.70291:
-- camelot/blizzard_inspectui.xml:54–76, camelot/inspectpaperdollframe.xml:56–76 (no Talents button),
-- mainline/inspectpaperdollframe.lua:28–55 + 223–233, camelot/inspectpvpframe.lua:105–133,
-- camelot/inspectguildframe.lua:17–34). The title is the inspected player's name, the guild's name is a name and the
-- PvP rank title is a name: all stay as written. Either load order.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Inspect.lua"

local ADDON = "Blizzard_InspectUI"

-- Forever GlobalStrings → a test Japanese
local UI = {
  PLAYER_LEVEL = { "Level %s |c%s%s %s|r", "レベル %s |c%s%s %s|r" },
  PLAYER_LEVEL_NO_SPEC = { "Level %s |c%s%s|r", "レベル %s |c%s%s|r" },
  INSPECT_GUILD_FACTION = { "%s Guild", "%sのギルド" },
  INSPECT_GUILD_NUM_MEMBERS = { "%d Guild Members", "ギルドメンバー %d人" },
  HEADSLOT = { "Head", "頭" },
  CHARACTER_INFO = { "Character Info", "キャラクター情報" },
  PLAYER_V_PLAYER = { "Player vs. Player", "PvP" },
  GUILD = { "Guild", "ギルド" },
  EXPANSION_SEASON_NAME = { "%s Season %d", "%sシーズン%d" },
  PVP_RANK_NUMBER_AND_TITLE = { "Rank %d - %s", "ランク%d - %s" },
  PVP_RANK_CURRENT_PROGRESS = { "Rank Points: |cnHIGHLIGHT_FONT_COLOR:%d / %d|r",
    "ランクポイント: |cnHIGHLIGHT_FONT_COLOR:%d / %d|r" },
  HONORABLE_KILLS = { "Honorable Kills", "名誉キル" },
  HONOR_LIFETIME = { "Lifetime", "通算" },
  HONOR_TODAY = { "Today", "今日" },
  -- rank titles: in the dictionary, and never shown in Japanese on this surface
  PVP_RANK_0_NAME = { "Civilian", "民間人" }, PVP_RANK_5_0 = { "Scout", "斥候" },
  CLOSE = { "Close", "閉じる" }, -- a word a player or a guild may happen to be called
}

local C = {}

local function en(key) return _G[key] end
local function fs(text) return Stub.fontString(text or "") end

-- shape: nil (the 70291 window), "bare" (no InspectPaperDollFrame), "noPvP" (no InspectPVPFrame)
local function loadInspect(shape)
  local frame = CreateFrame("Frame", "InspectFrame")
  frame.name = "InspectFrame"
  frame.TitleContainer = { TitleText = fs() }
  function frame.SetTitle(self, text) self.TitleContainer.TitleText.text = text end
  if shape ~= "bare" then
    local doll = CreateFrame("Frame", "InspectPaperDollFrame")
    doll.name = "InspectPaperDollFrame"
    function doll.SetLevel(_) -- mainline/inspectpaperdollframe.lua:50–54
      if type(_G.InspectLevelText) ~= "table" then return end -- (a test binds the name to a number)
      _G.InspectLevelText.text = C.spec
        and string.format(en("PLAYER_LEVEL"), C.level, "ffc79c6e", C.spec, C.class)
        or string.format(en("PLAYER_LEVEL_NO_SPEC"), C.level, "ffc79c6e", C.class)
    end
  end
  Stub.namedFontString("InspectLevelText", "")
  CreateFrame("Button", "InspectHeadSlot")
  for i = 1, 3 do CreateFrame("Frame", "InspectFrameModeTab" .. i) end
  if shape ~= "noPvP" then
    local pvp = CreateFrame("Frame", "InspectPVPFrame")
    pvp.name = "InspectPVPFrame"
    local main = { CurrentSeasonField = fs(), CurrentRankField = fs(), CurrentRankProgressField = fs(),
      HonorableKillsField = fs(), LifetimeHKsField = fs(), TodayHKsField = fs(),
      RankProgressBarDisplay = { NextRewardLevel = { LevelLabel = fs() } } }
    pvp.MainInfoFrame = main
    function pvp.Update(self) -- camelot/inspectpvpframe.lua:116–132
      local m = self.MainInfoFrame
      m.CurrentSeasonField.text = string.format(en("EXPANSION_SEASON_NAME"), "", C.season)
      if C.rank > 0 then
        m.CurrentRankField.text = en("PVP_RANK_NUMBER_AND_TITLE"):format(C.rank, C.rankTitle)
      else
        m.CurrentRankField.text = en("PVP_RANK_0_NAME")
      end
      m.CurrentRankProgressField.text = string.format(en("PVP_RANK_CURRENT_PROGRESS"), C.points, C.next)
      m.RankProgressBarDisplay.NextRewardLevel.LevelLabel.text = tostring(C.rank)
      m.HonorableKillsField.text = en("HONORABLE_KILLS")
      m.LifetimeHKsField.text = string.format("%s: %d", en("HONOR_LIFETIME"), C.lifetime)
      m.TodayHKsField.text = string.format("%s: %d", en("HONOR_TODAY"), C.today)
    end
  end
  local guild = CreateFrame("Frame", "InspectGuildFrame")
  guild.guildName, guild.guildLevel, guild.guildNumMembers = fs(), fs(), fs()
  _G.InspectGuildFrame_Update = function() -- camelot/inspectguildframe.lua:26–31
    guild.guildName.text = C.guild
    if type(guild.guildLevel) == "table" then
      guild.guildLevel.text = string.format(en("INSPECT_GUILD_FACTION"), C.faction)
    end
    guild.guildNumMembers.text = string.format(en("INSPECT_GUILD_NUM_MEMBERS"), C.members)
  end
  Stub.loadedAddons[ADDON] = true
  return frame
end

describe("the inspect window on Forever", function()
  local WFJ, SS

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do if rec.fs == widget then return false end end
    end
    return true
  end

  local function boot()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    C.level, C.spec, C.class, C.guild, C.faction, C.members = 42, nil, "Warrior", "Close", "Horde", 12
    C.season, C.rank, C.rankTitle, C.points, C.next, C.lifetime, C.today = 1, 1, "Scout", 150, 500, 37, 4
  end

  local function setup(loadedFirst)
    boot()
    if loadedFirst then
      loadInspect()
      assert.is_true(WFJ.Inspect.init())
    else
      assert.is_false(WFJ.Inspect.init()) -- waits for the addon
      loadInspect()
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, n in ipairs({ "InspectFrame", "InspectPaperDollFrame", "InspectLevelText", "InspectHeadSlot",
      "InspectPVPFrame", "InspectGuildFrame", "InspectGuildFrame_Update", "InspectFrameModeTab1",
      "InspectFrameModeTab2", "InspectFrameModeTab3" }) do _G[n] = nil end
  end)

  for _, order in ipairs({ { true, "loaded at login" }, { false, "loaded on demand" } }) do
    describe("Blizzard_InspectUI " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("sets up with no Talents button; the level line is Japanese; Alt shows English", function()
        local doll = _G.InspectPaperDollFrame
        assert.is_nil(doll.InspectTalents)
        doll:SetLevel()
        assert.are.equal("レベル 42 |cffc79c6eWarrior|r", _G.InspectLevelText:GetText())
        C.spec = "Arms"
        doll:SetLevel()
        assert.are.equal("レベル 42 |cffc79c6eArms Warrior|r", _G.InspectLevelText:GetText())
        alt(true)
        assert.are.equal("Level 42 |cffc79c6eArms Warrior|r", _G.InspectLevelText:GetText())
        alt(false)
        assert.are.equal("レベル 42 |cffc79c6eArms Warrior|r", _G.InspectLevelText:GetText())
      end)

      it("the PvP pane is Japanese, the rank title stays English; Alt shows English", function()
        local pvp = _G.InspectPVPFrame
        pvp:Update()
        local m = pvp.MainInfoFrame
        assert.are.equal("シーズン1", m.CurrentSeasonField:GetText())
        assert.are.equal("ランク1 - Scout", m.CurrentRankField:GetText())
        assert.are.equal("ランクポイント: |cnHIGHLIGHT_FONT_COLOR:150 / 500|r", m.CurrentRankProgressField:GetText())
        assert.are.equal("名誉キル", m.HonorableKillsField:GetText())
        assert.are.equal("通算: 37", m.LifetimeHKsField:GetText())
        assert.are.equal("今日: 4", m.TodayHKsField:GetText())
        assert.are.equal("1", m.RankProgressBarDisplay.NextRewardLevel.LevelLabel:GetText())
        assert.is_true(WFJ.Labels.forbidden(m.RankProgressBarDisplay.NextRewardLevel.LevelLabel))
        alt(true)
        assert.are.equal(" Season 1", m.CurrentSeasonField:GetText())
        assert.are.equal("Rank 1 - Scout", m.CurrentRankField:GetText())
        assert.are.equal("Honorable Kills", m.HonorableKillsField:GetText())
        assert.are.equal("Lifetime: 37", m.LifetimeHKsField:GetText())
        assert.are.equal("Today: 4", m.TodayHKsField:GetText())
        alt(false)
        assert.are.equal("通算: 37", m.LifetimeHKsField:GetText())
        -- a new count from the client is followed
        C.today = 9
        pvp:Update()
        assert.are.equal("今日: 9", m.TodayHKsField:GetText())
      end)

      it("rank 0 shows the Civilian title in English, never its dictionary Japanese", function()
        C.rank = 0
        _G.InspectPVPFrame:Update()
        local m = _G.InspectPVPFrame.MainInfoFrame
        assert.are.equal("Civilian", m.CurrentRankField:GetText())
        assert.is_true(unrecorded(m.CurrentRankField))
      end)

      it("a count line whose word is not its own key stays as written", function()
        local m = _G.InspectPVPFrame.MainInfoFrame
        m.TodayHKsField.text = "Lifetime: 3"
        m.LifetimeHKsField.text = "Close"
        WFJ.Inspect.onPvP()
        assert.are.equal("Lifetime: 3", m.TodayHKsField:GetText())
        assert.are.equal("Close", m.LifetimeHKsField:GetText())
      end)

      it("the guild page's faction and member lines translate; the guild's name does not", function()
        _G.InspectGuildFrame_Update()
        local guild = _G.InspectGuildFrame
        assert.are.equal("Hordeのギルド", guild.guildLevel:GetText())
        assert.are.equal("ギルドメンバー 12人", guild.guildNumMembers:GetText())
        assert.are.equal("Close", guild.guildName:GetText())
        assert.is_true(unrecorded(guild.guildName))
        alt(true)
        assert.are.equal("Horde Guild", guild.guildLevel:GetText())
        alt(false)
      end)

      it("the title is the player's name: never touched, whatever it says", function()
        _G.InspectFrame:SetTitle("Close")
        assert.are.equal("Close", _G.InspectFrame.TitleContainer.TitleText:GetText())
        assert.is_true(WFJ.Labels.forbidden(_G.InspectFrame.TitleContainer.TitleText))
        assert.are.equal(0, WFJ.Labels.show("inspect", "x", _G.InspectFrame.TitleContainer.TitleText))
        assert.are.equal("Close", _G.InspectFrame.TitleContainer.TitleText:GetText())
      end)

      it("help tooltips: an empty slot's name and each side tab's own tooltip word", function()
        local tt = _G.GameTooltip
        tt:SetOwner(_G.InspectHeadSlot)
        tt:SetText(en("HEADSLOT"))
        assert.are.equal("頭", _G.GameTooltipTextLeft1:GetText())
        tt:SetOwner(_G.InspectHeadSlot)
        tt:SetText("Close") -- not a slot word: left alone on a slot's tooltip
        assert.are.equal("Close", _G.GameTooltipTextLeft1:GetText())
        for i, key in ipairs({ "CHARACTER_INFO", "PLAYER_V_PLAYER", "GUILD" }) do
          tt:SetOwner(_G["InspectFrameModeTab" .. i])
          tt:SetText(en(key))
          assert.are.equal(UI[key][2], _G.GameTooltipTextLeft1:GetText())
        end
        tt:SetOwner(_G.InspectFrameModeTab1)
        tt:SetText(en("GUILD")) -- another tab's word: left alone
        assert.are.equal("Guild", _G.GameTooltipTextLeft1:GetText())
      end)
    end)
  end

  it("hooks install once", function()
    setup(true)
    assert.is_false(WFJ.Inspect.setup())
    assert.are.equal(1, #Stub.hooks["InspectPaperDollFrame:SetLevel"])
    assert.are.equal(1, #Stub.hooks["InspectPVPFrame:Update"])
    assert.are.equal(1, #Stub.hooks["InspectGuildFrame_Update"])
  end)

  it("without InspectPVPFrame the rest still sets up", function()
    boot()
    loadInspect("noPvP")
    assert.is_true(WFJ.Inspect.init())
    assert.is_nil(Stub.hooks["InspectPVPFrame:Update"])
    _G.InspectGuildFrame_Update()
    assert.are.equal("ギルドメンバー 12人", _G.InspectGuildFrame.guildNumMembers:GetText())
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    boot()
    loadInspect()
    _G.InspectLevelText = 7
    _G.InspectGuildFrame.guildLevel = "x"
    _G.InspectPVPFrame.MainInfoFrame.TodayHKsField = "x"
    _G.InspectPVPFrame.MainInfoFrame.CurrentRankField = 3
    assert.has_no.errors(function() WFJ.Inspect.init() end)
    assert.has_no.errors(function() _G.InspectPaperDollFrame:SetLevel() end)
    assert.has_no.errors(function() WFJ.Inspect.onPvP() end)
    assert.has_no.errors(function() _G.InspectGuildFrame_Update() end)
    assert.are.equal("ギルドメンバー 12人", _G.InspectGuildFrame.guildNumMembers:GetText())
    boot()
    loadInspect()
    _G.InspectPaperDollFrame = "InspectPaperDollFrame"
    assert.has_no.errors(function() WFJ.Inspect.init() end)
    assert.is_nil(Stub.hooks["InspectPaperDollFrame:SetLevel"])
  end)

  it("without the Forever inspect frame nothing is set up (no InspectPaperDollFrame, or no frame at all)", function()
    boot()
    assert.is_false(WFJ.Inspect.init()) -- not loaded
    assert.is_false(WFJ.Inspect.setup()) -- no InspectFrame
    loadInspect("bare")
    assert.is_false(WFJ.Inspect.setup())
    assert.is_nil(Stub.hooks["InspectPVPFrame:Update"])
    assert.is_nil(Stub.hooks["InspectGuildFrame_Update"])
  end)
end)
