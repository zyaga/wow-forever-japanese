-- UI/AddonList.lua over an AddonList replayed from camelot
-- blizzard_addonlist/addonlist.lua (OnLoad SetTitle :232, AddonList_InitAddon :352–438, AddonList_Update :540–545,
-- UpdatePerformance :760–773, AddonTooltip_Update :851–893, the character dropdown :642–667) and addonlist.xml.
-- Addon names, notes and categories stay as written. Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/AddonList.lua"

local UI = {
  ADDON_DEPENDENCIES = { "Dependencies: ", "依存関係: " }, -- AddonTooltip_BuildDeps, lua:832–843
  ADDON_LIST = { "AddOn List", "アドオン一覧" }, CANCEL = { "Cancel", "キャンセル" }, OKAY = { "Okay", "OK" },
  RELOADUI = { "Reload UI", "UIを再読み込み" }, ENABLE_ALL_ADDONS = { "Enable All", "すべて有効" },
  DISABLE_ALL_ADDONS = { "Disable All", "すべて無効" }, ADDON_FORCE_LOAD = { "Load out of date AddOns", "古いアドオンを読み込む" },
  ADDON_LIST_PERFORMANCE_HEADER = { "AddOn Usage", "アドオン使用状況" },
  ADDON_LIST_PERFORMANCE_CURRENT_CPU = { "Current CPU: %s", "現在のCPU: %s" },
  ADDON_LIST_PERFORMANCE_AVERAGE_CPU = { "Average CPU: %s", "平均CPU: %s" },
  ADDON_LIST_PERFORMANCE_PEAK_CPU = { "Peak CPU: %s", "最大CPU: %s" },
  ADDON_LIST_PERFORMANCE_MEMORY_KB = { "Memory Usage: %d KB", "メモリ使用量: %d KB" },
  ADDON_DISABLED = { "Disabled", "無効" }, ADDON_DEP_MISSING = { "Dependency missing", "依存アドオンがありません" },
  REQUIRES_RELOAD = { "Requires Reload", "再読み込みが必要" }, LOAD_ADDON = { "Load AddOn", "アドオンを読み込む" },
  ENABLED_FOR_SOME = { "This addon is only enabled for some characters.", "このアドオンは一部のキャラクターでのみ有効です。" },
  ALL = { "All", "すべて" },
}

local A = {} -- replayed client state
local function en(key) return _G[key] end

local function entry()
  local e = CreateFrame("Button")
  e.Title, e.Status, e.Reload = Stub.fontString(""), Stub.fontString(""), Stub.fontString(en("REQUIRES_RELOAD"))
  e.LoadAddonButton = Stub.button(nil, en("LOAD_ADDON"))
  e.Enabled = CreateFrame("CheckButton")
  return e
end

local function installAddonList()
  local list = CreateFrame("Frame", "AddonList")
  list.TitleContainer = { TitleText = Stub.fontString("") }
  function list.SetTitle(self, t) self.TitleContainer.TitleText.text = t end
  list:SetTitle(en("ADDON_LIST"))
  list.OkayButton, list.CancelButton = Stub.button(nil, en("OKAY")), Stub.button(nil, en("CANCEL"))
  list.EnableAllButton = Stub.button(nil, en("ENABLE_ALL_ADDONS"))
  list.DisableAllButton = Stub.button(nil, en("DISABLE_ALL_ADDONS"))
  list.ForceLoad = CreateFrame("CheckButton")
  list.ForceLoad:addRegion(Stub.fontString(en("ADDON_FORCE_LOAD")))
  list.SearchBox = CreateFrame("EditBox")
  list.SearchBox.text = "All"
  list.Performance = { Header = Stub.fontString(en("ADDON_LIST_PERFORMANCE_HEADER")), Current = Stub.fontString(""),
    Average = Stub.fontString(""), Peak = Stub.fontString("") }
  function list.UpdatePerformance(self)
    self.Performance.Current.text = en("ADDON_LIST_PERFORMANCE_CURRENT_CPU"):format(A.cpu)
    self.Performance.Average.text = en("ADDON_LIST_PERFORMANCE_AVERAGE_CPU"):format("0.5%")
    self.Performance.Peak.text = en("ADDON_LIST_PERFORMANCE_PEAK_CPU"):format("12%")
  end
  list.Dropdown = CreateFrame("Button")
  list.Dropdown.name = "Dropdown"
  list.Dropdown.Text = Stub.fontString("")
  function list.Dropdown.UpdateText(self) self.Text.text = A.selection end
  _G.AddonList_InitAddon = function(e, node)
    local data = node:GetData()
    e.Title.text = data.title
    e.Status.text = data.reason and en("ADDON_" .. data.reason) or ""
  end
  _G.AddonList_Update = function() list.OkayButton:SetText(A.changed and en("RELOADUI") or en("OKAY")) end
  return list
end

describe("the AddOn List on Forever", function()
  local WFJ, SS

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do
        if rec.fs == widget then return false end
      end
    end
    return true
  end

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    -- Core/UIStrings: FormatProfilerPercent output ("12%", "0.5%", addonlist.lua:692–702) is a `percent` argument; the
    -- `text` kind AVERAGE / PEAK carry today refuses a period, so "0.5%" stays English
    for _, key in ipairs({ "CURRENT", "AVERAGE", "PEAK", "ENCOUNTER" }) do
      WFJ.UIStrings.ARGS["ADDON_LIST_PERFORMANCE_" .. key .. "_CPU"] = { [1] = "percent" }
    end
    H.uiSetup(WFJ, UI)
    A.cpu, A.changed, A.selection = "3%", false, "All"
  end

  before_each(function()
    load()
    installAddonList()
    WFJ.Labels.forbidNames(WFJ.AddonList.NEVER_TOUCH)
    assert.is_true(WFJ.AddonList.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.AddonList, _G.AddonList_InitAddon, _G.AddonList_Update = nil, nil, nil
  end)

  it("the SetTitle title is Japanese and stays Japanese after a second SetTitle", function()
    local title = _G.AddonList.TitleContainer.TitleText
    assert.are.equal("アドオン一覧", title:GetText())
    _G.AddonList:SetTitle(en("ADDON_LIST"))
    assert.are.equal("アドオン一覧", title:GetText())
    alt(true)
    assert.are.equal("AddOn List", title:GetText())
    alt(false)
  end)

  it("static labels and the unnamed force-load label are Japanese; the search box is never touched", function()
    local list = _G.AddonList
    assert.are.equal("キャンセル", list.CancelButton:GetText())
    assert.are.equal("すべて有効", list.EnableAllButton:GetText())
    assert.are.equal("すべて無効", list.DisableAllButton:GetText())
    assert.are.equal("アドオン使用状況", list.Performance.Header:GetText())
    assert.are.equal("古いアドオンを読み込む", (list.ForceLoad:GetRegions()):GetText())
    assert.are.equal("All", list.SearchBox:GetText())
    assert.are.equal(0, WFJ.Labels.show("addonlist", "x", list.SearchBox))
  end)

  it("the Okay button follows AddonList_Update; the CPU lines follow UpdatePerformance every frame", function()
    local list = _G.AddonList
    A.changed = true
    _G.AddonList_Update()
    assert.are.equal("UIを再読み込み", list.OkayButton:GetText())
    A.changed = false
    _G.AddonList_Update()
    assert.are.equal("OK", list.OkayButton:GetText())
    list:UpdatePerformance()
    assert.are.equal("現在のCPU: 3%", list.Performance.Current:GetText())
    assert.are.equal("平均CPU: 0.5%", list.Performance.Average:GetText())
    A.cpu = "4%"
    list:UpdatePerformance()
    assert.are.equal("現在のCPU: 4%", list.Performance.Current:GetText())
    assert.are.equal("最大CPU: 12%", list.Performance.Peak:GetText())
  end)

  it("a pooled row: status, reload and load labels translate; the addon's name does not, even a dictionary word",
    function()
      local e = entry()
      _G.AddonList_InitAddon(e, { GetData = function() return { title = "Disabled", reason = "DEP_MISSING" } end })
      assert.are.equal("依存アドオンがありません", e.Status:GetText())
      assert.are.equal("再読み込みが必要", e.Reload:GetText())
      assert.are.equal("アドオンを読み込む", e.LoadAddonButton:GetText())
      assert.are.equal("Disabled", e.Title:GetText())
      assert.is_true(unrecorded(e.Title))
      -- the row is reused for another addon
      _G.AddonList_InitAddon(e, { GetData = function() return { title = "Questie", reason = "DISABLED" } end })
      assert.are.equal("無効", e.Status:GetText())
      _G.AddonList_InitAddon(e, { GetData = function() return { title = "Questie" } end })
      assert.are.equal("", e.Status:GetText())
    end)

  it("the row tooltip: the fixed lines translate; the addon's title and notes do not", function()
    local e = entry()
    _G.AddonList_InitAddon(e, { GetData = function() return { title = "All" } end })
    local tt = _G.GameTooltip
    tt:SetOwner(e)
    tt:ClearLines()
    tt:AddDoubleLine("All", "1.0") -- the addon's title: a dictionary word here
    tt:AddLine("Disabled") -- the addon's own notes
    tt:AddLine(en("ADDON_LIST_PERFORMANCE_AVERAGE_CPU"):format("0.5%"))
    tt:AddLine(en("ADDON_LIST_PERFORMANCE_MEMORY_KB"):format(512))
    tt:AddLine(en("ADDON_DEPENDENCIES") .. "Blizzard_AuctionHouseUI, Cancel")
    tt:Show()
    assert.are.equal("依存関係: Blizzard_AuctionHouseUI, Cancel", _G.GameTooltipTextLeft5:GetText()) -- names kept
    assert.are.equal("All", _G.GameTooltipTextLeft1:GetText())
    assert.are.equal("Disabled", _G.GameTooltipTextLeft2:GetText())
    assert.are.equal("平均CPU: 0.5%", _G.GameTooltipTextLeft3:GetText())
    assert.are.equal("メモリ使用量: 512 KB", _G.GameTooltipTextLeft4:GetText())
    tt:SetOwner(e.Enabled)
    tt:SetText(en("ENABLED_FOR_SOME"))
    assert.are.equal("このアドオンは一部のキャラクターでのみ有効です。", _G.GameTooltipTextLeft1:GetText())
  end)

  it("the dropdown shows ALL in Japanese, the player's name as written, even a player called All", function()
    local dropdown = _G.AddonList.Dropdown
    dropdown:UpdateText()
    assert.are.equal("すべて", dropdown.Text:GetText())
    A.selection = "Reyn"
    dropdown:UpdateText()
    assert.are.equal("Reyn", dropdown.Text:GetText())
    load() -- a player called All: both entries read "All", so the text is left as written
    _G.UnitName = function() return "All" end
    dropdown = installAddonList().Dropdown
    assert.is_true(WFJ.AddonList.init())
    dropdown:UpdateText()
    assert.are.equal("All", dropdown.Text:GetText())
    assert.is_true(unrecorded(dropdown.Text))
  end)

  it("hooks install once", function()
    assert.is_false(WFJ.AddonList.init())
    assert.are.equal(1, #Stub.hooks["AddonList_InitAddon"])
    assert.are.equal(1, #Stub.hooks["AddonList:UpdatePerformance"])
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    load()
    local list = installAddonList()
    list.TitleContainer, list.Performance, list.Dropdown, list.ForceLoad = 5, "perf", true, "force"
    list.OkayButton = 3
    _G.AddonList_Update = "nope"
    assert.has_no.errors(function() assert.is_true(WFJ.AddonList.init()) end)
    assert.has_no.errors(function()
      WFJ.AddonList.onRow(nil); WFJ.AddonList.onRow({ Status = 1, Reload = "x", Enabled = 2 })
      WFJ.AddonList.onPerformance(); WFJ.AddonList.onDropdown(); WFJ.AddonList.onShow()
    end)
    assert.are.equal("すべて有効", list.EnableAllButton:GetText()) -- the rest still works
  end)

  it("no AddonList → init is false and nothing is touched", function()
    load()
    _G.AddonList = nil
    assert.has_no.errors(function() assert.is_false(WFJ.AddonList.init()) end)
  end)
end)
