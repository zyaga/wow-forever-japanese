-- The reputation frame on the Forever (camelot) client: the list's pooled headers and standing bars (the
-- entry's own hover writes the progress numbers and then the English standing back), the detail pane's empty prompt,
-- standing subtitle and account-wide row, its checkbox labels and their tooltips, and the View Renown button.
-- Faction names and descriptions stay English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local RC = require("tests.lua.spec.stub_camelot_character")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Reputation.lua"

local UI = {
  FACTION_INACTIVE = { "Inactive", "非アクティブ" },
  FACTION_STANDING_LABEL5 = { "Friendly", "友好" }, FACTION_STANDING_LABEL5_FEMALE = { "Friendly", "友好" },
  FACTION_STANDING_LABEL6 = { "Honored", "尊敬" }, FACTION_STANDING_LABEL6_FEMALE = { "Honored", "尊敬" },
  REPUTATION_DETAIL_SELECT_PROMPT = { RC.EN.REPUTATION_DETAIL_SELECT_PROMPT, "勢力を選ぶと詳細が表示されます。" },
  REPUTATION_TOOLTIP_ACCOUNT_WIDE_LABEL = { RC.EN.REPUTATION_TOOLTIP_ACCOUNT_WIDE_LABEL,
    "この評判はウォーバンド全体で共有されます。共有される評判は同じアカウントのすべてのキャラクターに反映され、"
      .. "日本語の方が長くなって行数が増える場合の試験用の長い文章です。" },
  AT_WAR = { "At War", "交戦中" }, MOVE_TO_INACTIVE = { "Move to Inactive", "非アクティブに移動" },
  SHOW_FACTION_ON_MAINSCREEN = { "Show as Experience Bar", "経験値バーに表示" },
  VIEW_RENOWN_BUTTON_LABEL = { "View Renown", "高名を見る" },
  REPUTATION_AT_WAR_DESCRIPTION = { RC.EN.REPUTATION_AT_WAR_DESCRIPTION, "オンにするとこの勢力を攻撃できます。" },
  REPUTATION_SHOW_AS_XP = { RC.EN.REPUTATION_SHOW_AS_XP, "この勢力をアクションバーの下にバーで表示します。" },
  OTHER_WORD = { "Honor Hold", "名誉の砦" }, -- a faction name that is also a dictionary word
}

describe("the reputation frame on the Forever client", function()
  local WFJ, SS

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function left(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
  local function detail() return _G.ReputationFrame.ReputationDetailFrame end
  local function bar(row) return row.Content.ReputationBar.Text end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    RC.install()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    WFJ.Labels.forbidNames(WFJ.Reputation.NEVER_TOUCH) -- Main registers every list before any init
    WFJ.Reputation.init()
  end)

  after_each(function() H.uiTeardown() end)

  it("the detail pane hooks are placed once", function()
    assert.are.equal(1, #Stub.hooks["?:SetEmpty"])
    assert.are.equal(1, #Stub.hooks["?:SetPaneTitle"])
    assert.are.equal(1, #Stub.hooks["?:LayoutRows"])
    assert.is_false(WFJ.Reputation.init())
    assert.are.equal(1, #_G.ReputationFrame.ScrollBox.initCallbacks)
    assert.is_true(WFJ.Labels.forbidden(detail().Title))
    -- The description is the Faction table's text (FactionDescription rows), so the addon may translate it
    assert.is_false(WFJ.Labels.forbidden(detail().Description))
  end)

  it("the detail pane's static labels translate at init, and the checkboxes' tooltips on hover", function()
    assert.are.equal("交戦中", detail().AtWarCheckbox.Label:GetText())
    assert.are.equal("非アクティブに移動", detail().MakeInactiveCheckbox.Label:GetText())
    assert.are.equal("経験値バーに表示", detail().WatchFactionCheckbox.Label:GetText())
    assert.are.equal("高名を見る", detail().ViewRenownButton:GetText())
    RC.hover(detail().AtWarCheckbox)
    assert.are.equal("オンにするとこの勢力を攻撃できます。", left(1))
    RC.hover(detail().WatchFactionCheckbox)
    assert.are.equal("この勢力をアクションバーの下にバーで表示します。", left(1))
    RC.hover(detail().MakeInactiveCheckbox) -- no dictionary entry: English
    assert.are.equal(RC.EN.REPUTATION_MOVE_TO_INACTIVE, left(1))
    alt(true)
    assert.are.equal("At War", detail().AtWarCheckbox.Label:GetText())
  end)

  it("the list: the Inactive header and the standings translate; faction names and other headers stay English",
    function()
    local rows = RC.setFactions({ { header = "Classic" }, { name = "Stormwind", standing = "Friendly",
      progress = "1200 / 6000" }, { header = "Inactive" }, { name = "Honor Hold", standing = "Honored" } })
    assert.are.equal("Classic", rows[1].Name:GetText())
    assert.are.equal("友好", bar(rows[2]):GetText())
    assert.are.equal("Stormwind", rows[2].Content.Name:GetText())
    assert.are.equal("非アクティブ", rows[3].Name:GetText())
    assert.are.equal("Honor Hold", rows[4].Content.Name:GetText())
    assert.is_true(WFJ.Labels.forbidden(rows[4].Content.Name))
    assert.are.equal("尊敬", bar(rows[4]):GetText())
    alt(true)
    assert.are.equal("Friendly", bar(rows[2]):GetText())
    alt(false)
  end)

  it("an entry's hover shows the numbers, its leave the Japanese standing again; the modifier never puts English"
    .. " over the numbers", function()
    local rows = RC.setFactions({ { name = "Stormwind", standing = "Friendly", progress = "1200 / 6000" } })
    local row = rows[1]
    RC.hover(row)
    assert.are.equal("|cffffffff1200 / 6000|r", bar(row):GetText())
    alt(true); alt(false)
    assert.are.equal("|cffffffff1200 / 6000|r", bar(row):GetText())
    RC.leave(row)
    assert.are.equal("友好", bar(row):GetText())
    RC.hover(row)
    RC.leave(row.Content.AccountWideIcon) -- the icon's OnLeave calls the entry's OnLeave
    assert.are.equal("友好", bar(row):GetText())
    assert.is_true(WFJ.HelpTooltip.registered(row.Content.AccountWideIcon))
    assert.is_true(WFJ.HelpTooltip.registered(row.Content.ReputationBar.BonusIcon))
    RC.hover(row.Content.AccountWideIcon)
    assert.is_truthy(left(1):find("^この評判はウォーバンド全体で共有されます。"))
  end)

  it("pooled rows reused for other factions: the records follow the widgets", function()
    RC.setFactions({ { header = "Inactive" }, { name = "Stormwind", standing = "Friendly" } })
    local rows = RC.setFactions({ { header = "Classic" }, { name = "Darnassus", standing = "Exalted" } })
    assert.are.equal("Classic", rows[1].Name:GetText())
    assert.are.equal("Exalted", bar(rows[2]):GetText())
    alt(true); alt(false)
    assert.are.equal("Classic", rows[1].Name:GetText())
    assert.are.equal("Exalted", bar(rows[2]):GetText())
  end)

  it("the detail pane: the empty prompt, then a faction's standing and account-wide row; name and description"
    .. " stay English", function()
    RC.select(nil)
    assert.are.equal("勢力を選ぶと詳細が表示されます。", detail().EmptyText:GetText())
    RC.select({ name = "Honor Hold", description = "Friendly to the Alliance.", standing = "Honored",
      accountWide = true })
    assert.are.equal("Honor Hold", detail().Title:GetText())
    assert.are.equal(0, detail().Title.calls.SetText)
    assert.are.equal("尊敬", detail().Subtitle:GetText())
    assert.are.equal("Friendly to the Alliance.", detail().Description:GetText())
    local row = RC.paneRows.active[1]
    assert.is_truthy(row.Label:GetText():find("^この評判はウォーバンド全体で共有されます。"))
    assert.are.equal(row.Label:GetStringHeight(), row:GetHeight()) -- grown to the taller Japanese
    alt(true)
    assert.are.equal("Honored", detail().Subtitle:GetText())
    assert.are.equal(RC.EN.REPUTATION_TOOLTIP_ACCOUNT_WIDE_LABEL, row.Label:GetText())
    alt(false)
    RC.select({ name = "Stormwind", standing = "Friendly" })
    assert.are.equal(0, #RC.paneRows.active)
    local n = 0
    for key in pairs(SS.records("reputation")) do if key:find("^detail%.row%.") then n = n + 1 end end
    assert.are.equal(0, n)
    assert.are.equal("友好", detail().Subtitle:GetText())
  end)

  it("a moved pane, pool or list degrades to English with no error (type guards)", function()
    detail().rowPools = { EnumerateActive = "moved" }
    assert.are.equal(0, WFJ.Reputation.onLayoutRows())
    assert.has_no.errors(function() WFJ.Reputation.onRow(WFJ.Reputation, "moved") end)
    assert.has_no.errors(function() WFJ.Reputation.onRow({ Content = "moved" }) end)
    _G.ReputationFrame.ReputationDetailFrame = "moved"
    WFJ.Compat.declare("reputation", "detail", { "ReputationFrame.ReputationDetailFrame" })
    assert.are.equal(0, WFJ.Reputation.onLayoutRows())
    assert.are.equal(0, WFJ.Reputation.onSetEmpty())
    assert.are.equal(0, WFJ.Reputation.onPaneTitle())
  end)
end)

-- ADR-042: the detail pane's description is the Faction table's text. SetDescription writes the Description
-- ScrollingFont (reputationframe.lua:758, 771; characterframe.lua:873–885); only FactionDescription:* rows match it,
-- and a FactionDescription text on any other widget (the faction name title) is never changed.
describe("the reputation frame's faction description", function()
  local WFJ

  local DESC = "The Stormwind army and its citizens defend the human capital."
  local ROWS = {
    ["FactionDescription:72"] = { DESC, "ストームウィンドの軍と市民は人間の首都を守っている。" },
    ["FactionDescription:47"] = { "Honor Hold", "名誉の砦の説明" }, -- a description whose English is a faction name
    OTHER_WORD = { "A plain dictionary word.", "ただの辞書の言葉。" }, -- not a FactionDescription row
  }

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function detail() return _G.ReputationFrame.ReputationDetailFrame end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    RC.install()
    local d = _G.ReputationFrame.ReputationDetailFrame
    d.Description = Stub.scrollingFont("") -- ScrollingFontTemplate (reputationframe.xml)
    function d.SetDescription(self, text) self.Description:SetText(text) end -- CharacterFrameSidePaneMixin
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, ROWS)
    WFJ.Labels.forbidNames(WFJ.Reputation.NEVER_TOUCH)
    WFJ.Reputation.init()
  end)

  after_each(function() H.uiTeardown(); Stub.keys.alt = false end)

  it("a FactionDescription row is shown in Japanese after SetDescription, refitted; Alt shows the English", function()
    assert.are.equal(1, #Stub.hooks["?:SetDescription"])
    local sf = detail().Description
    detail():SetDescription(DESC)
    assert.are.equal("ストームウィンドの軍と市民は人間の首都を守っている。", sf:GetText())
    assert.are.equal(sf.fs:GetStringHeight(), sf.container.height) -- the container re-heighted to the Japanese
    assert.is_true(sf.box.fullUpdates >= 2) -- the client's own SetText, then our refit
    alt(true)
    assert.are.equal(DESC, sf:GetText())
    alt(false)
    assert.are.equal("ストームウィンドの軍と市民は人間の首都を守っている。", sf:GetText())
  end)

  it("a description no row has stays English; a dictionary word that is no FactionDescription row too", function()
    local sf = detail().Description
    detail():SetDescription("A faction nobody translated.")
    assert.are.equal("A faction nobody translated.", sf:GetText())
    detail():SetDescription("A plain dictionary word.")
    assert.are.equal("A plain dictionary word.", sf:GetText())
    detail():SetDescription(DESC) -- then another faction: the record follows the new text
    detail():SetDescription("A faction nobody translated.")
    assert.are.equal("A faction nobody translated.", sf:GetText())
    assert.is_nil(WFJ.SurfaceState.get("reputation", "detail.description"))
  end)

  it("a FactionDescription English on the Title (a faction name) is never changed", function()
    RC.select({ name = "Honor Hold", standing = "Honored" })
    assert.are.equal("Honor Hold", detail().Title:GetText())
    assert.are.equal(0, detail().Title.calls.SetText)
    assert.is_true(WFJ.Labels.forbidden(detail().Title))
  end)
end)
