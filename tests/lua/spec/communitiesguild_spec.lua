-- UI/CommunitiesGuild's guild info texts over frames replayed from the camelot
-- blizzard_communities extract: the guild event log (a SimpleHTML rebuilt by CommunitiesGuildLogFrame_Update,
-- guildinfo.lua:163–194), a guild news event row (GUILD_EVENT_FORMAT via GuildNewsButton_SetText, guildnews.lua:
-- 120–136), the text-edit dialog's title (guildinfo.lua:127–146) and the guild reputation bar's standing word
-- (guildrewards.lua:201–226). Player names, ranks and event titles stay English; Alt shows the client's English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/CommunitiesKit.lua"
FILES[#FILES + 1] = "UI/CommunitiesGuild.lua"

local UI = {
  GUILDEVENT_TYPE_PROMOTE = { "%s promotes %s to %s", "%sが%sを%sに昇格させました" },
  GUILDEVENT_TYPE_JOIN = { "%s joins the guild", "%sがギルドに加入しました" },
  GUILD_BANK_LOG_TIME = { "|cff009999   ( %s ago )|r", "|cff009999   ( %s前 )|r" },
  LASTONLINE_HOURS = { "%d |4hour:hours;", "%d時間" }, LASTONLINE_DAYS = { "%d |4day:days;", "%d日" },
  GUILD_EVENT_FORMAT = { "%1$s %2$s: %3$s", "%1$s %2$s: %3$s" }, GUILD_EVENT_TODAY = { "TODAY", "今日" },
  WEEKDAY_MONDAY = { "Monday", "月曜日" },
  GUILD_MOTD_EDITLABEL = { "Guild Message Of The Day", "ギルドの今日のメッセージ" },
  GUILD_INFO_EDITLABEL = { "Guild Information", "ギルド情報" },
  FACTION_STANDING_LABEL5 = { "Friendly", "友好" }, FACTION_STANDING_LABEL6 = { "Honored", "尊敬" },
  GUILD = { "Guild", "ギルド" },
}
local GLOBALS = { "CommunitiesFrame", "CommunitiesGuildLogFrame", "CommunitiesGuildTextEditFrame",
  "GuildNewsButton_SetText", "CommunitiesGuildTextEditFrame_SetType" }

-- A SimpleHTML: SetText, and GetFont / SetFont per text type (no GetText).
local function simpleHTML()
  local html = CreateFrame("Frame")
  html.fonts = { P = { "Fonts\\FRIZQT__.TTF", 12, "" } }
  function html.SetText(self, text) self.shown = text end
  function html.GetFont(self, tag) local f = self.fonts[tag or "P"]; return f[1], f[2], f[3] end
  function html.SetFont(self, tag, path, size, flags) self.fonts[tag] = { path, size, flags } end
  return html
end

local EVENT_EN = "Thrall promotes Jaina to Officer|cff009999   ( 3 hours ago )|r|n"
  .. "Guild joins the guild|cff009999   ( 2 days ago )|r|n" -- a player named "Guild"
  .. "Thrall does something new|cff009999   ( 2 days ago )|r|n"

local function build()
  local CF = CreateFrame("Frame", "CommunitiesFrame")
  local ben = CreateFrame("Frame")
  CF.GuildBenefitsFrame = ben
  ben.FactionFrame = CreateFrame("Frame")
  local bar = CreateFrame("Frame")
  ben.FactionFrame.Bar = bar
  bar.Label = Stub.fontString("")
  bar.reaction = 6
  function bar.UpdateFaction(self) self.Label:SetText(_G["FACTION_STANDING_LABEL" .. self.reaction]) end
  local logFrame = CreateFrame("Frame", "CommunitiesGuildLogFrame")
  logFrame.Container = { ScrollFrame = { Child = { HTMLFrame = simpleHTML() } } }
  local edit = CreateFrame("Frame", "CommunitiesGuildTextEditFrame")
  edit.Title = Stub.fontString("")
  _G.CommunitiesGuildTextEditFrame_SetType = function(self, editType) -- guildinfo.lua:127–146
    self.Title:SetText(editType == "motd" and _G.GUILD_MOTD_EDITLABEL or _G.GUILD_INFO_EDITLABEL)
  end
  _G.GuildNewsButton_SetText = function(button, _, text, ...) -- guildutil.lua:41–44 (SetFormattedText; WoW's
    local args = { ... } -- format takes %N$s, Lua 5.1's does not)
    button.text:SetText((text:gsub("%%(%d)%$s", function(n) return args[tonumber(n)] end):gsub("%%s", args[1] or "")))
  end
  Stub.loadedAddons["Blizzard_Communities"] = true
end

describe("the guild info texts of the Communities window", function()
  local WFJ

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    build()
    assert.is_true(WFJ.CommunitiesGuild.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, g in ipairs(GLOBALS) do _G[g] = nil end
  end)

  local function html() return _G.CommunitiesGuildLogFrame.Container.ScrollFrame.Child.HTMLFrame end

  it("the rebuilt event log: each template in Japanese, names and rank kept, the time suffix; Alt English",
    function()
      html():SetText(EVENT_EN)
      assert.are.equal("ThrallがJainaをOfficerに昇格させました|cff009999   ( 3時間前 )|r|n"
        .. "Guildがギルドに加入しました|cff009999   ( 2日前 )|r|n"
        .. "Thrall does something new|cff009999   ( 2 days ago )|r|n", html().shown)
      assert.are.equal(WFJ.Font.PATH, (html():GetFont("P")))
      alt(true)
      assert.are.equal(EVENT_EN, html().shown)
      alt(false)
      assert.is_truthy(html().shown:find("昇格", 1, true))
      _G.CommunitiesGuildLogFrame:Hide()
      assert.are.equal(EVENT_EN, html().shown)
    end)

  it("a log with no event line the dictionary knows stays exactly as written", function()
    local text = "Thrall does something new|cff009999   ( 2 days ago )|r|n"
    html():SetText(text)
    assert.are.equal(text, html().shown)
  end)

  it("a news event row: the colour-wrapped TODAY and a weekday in Japanese, the event title kept", function()
    local button = { text = Stub.fontString("") }
    _G.GuildNewsButton_SetText(button, {}, _G.GUILD_EVENT_FORMAT, "|cffffd200TODAY|r", "8:00 PM", "Guild Meeting")
    assert.are.equal("|cffffd200今日|r 8:00 PM: Guild Meeting", button.text:GetText())
    _G.GuildNewsButton_SetText(button, {}, _G.GUILD_EVENT_FORMAT, "Monday", "8:00 PM", "Raid")
    assert.are.equal("月曜日 8:00 PM: Raid", button.text:GetText())
    alt(true)
    assert.are.equal("Monday 8:00 PM: Raid", button.text:GetText())
    alt(false)
    _G.GuildNewsButton_SetText(button, {}, "%s", "Guild") -- another news row: a name, never matched
    assert.are.equal("Guild", button.text:GetText())
  end)

  it("the text-edit dialog's title follows its type", function()
    local edit = _G.CommunitiesGuildTextEditFrame
    _G.CommunitiesGuildTextEditFrame_SetType(edit, "motd")
    assert.are.equal("ギルドの今日のメッセージ", edit.Title:GetText())
    _G.CommunitiesGuildTextEditFrame_SetType(edit, "info")
    assert.are.equal("ギルド情報", edit.Title:GetText())
  end)

  it("the guild reputation bar's standing word in Japanese after UpdateFaction and OnLeave; Alt English",
    function()
      local bar = _G.CommunitiesFrame.GuildBenefitsFrame.FactionFrame.Bar
      bar:UpdateFaction()
      assert.are.equal("尊敬", bar.Label:GetText())
      bar.reaction = 5
      bar:UpdateFaction()
      assert.are.equal("友好", bar.Label:GetText())
      alt(true)
      assert.are.equal("Friendly", bar.Label:GetText())
      alt(false)
      bar.Label:SetText("1,200 / 3,000") -- OnEnter's numbers are left alone
      bar:UpdateFaction()
      assert.are.equal("友好", bar.Label:GetText())
    end)

  it("frames bound to the wrong type degrade with no error", function()
    H.uiTeardown()
    for _, g in ipairs(GLOBALS) do _G[g] = nil end
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    build()
    _G.CommunitiesGuildLogFrame.Container = 3
    _G.CommunitiesFrame.GuildBenefitsFrame.FactionFrame = "x"
    _G.GuildNewsButton_SetText = 7
    assert.has_no.errors(function() assert.is_true(WFJ.CommunitiesGuild.init()) end)
  end)
end)
