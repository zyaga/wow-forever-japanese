local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

describe("UI/AddonListButton: Settings on this addon's AddOn List row", function()
  local WFJ

  local function load(withList)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    if withList then Stub.installAddonList() end
    Stub.addonNames = { "SomeOtherAddon", "WoWForeverJapanese" }
    WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
  end

  it("a pooled row shows the button for this addon and hides it for another", function()
    load(true)
    assert.is_true(WFJ.AddonListButton.installed)
    local entry = Stub.addonEntry()
    AddonList_InitAddon(entry, Stub.addonNode(2))
    local b = entry.wfjSettings
    assert.is_table(b)
    assert.is_true(b:IsShown())
    assert.are.equal("設定", b.caption:GetText()) -- one language: Japanese unless the reveal key is held
    assert.are.equal(WFJ.Font.PATH, (b.caption:GetFont()))
    assert.are.same({ "LEFT", entry.Title, "RIGHT", 70, 0 }, b.point)
    AddonList_InitAddon(entry, Stub.addonNode(1)) -- the same pooled entry, reused for another addon
    assert.is_false(b:IsShown())
    AddonList_InitAddon(entry, Stub.addonNode(2))
    assert.is_true(b:IsShown())
    assert.are.equal(b, entry.wfjSettings) -- created once per entry
  end)

  it("a click opens the settings (no HideUIPanel); pending AddOn changes disable it", function()
    load(true)
    local entry = Stub.addonEntry()
    AddonList_InitAddon(entry, Stub.addonNode(2))
    Stub.settingsCalls = {}
    entry.wfjSettings:click()
    assert.are.same({}, Stub.panelCalls) -- a forbidden call: the Settings panel manages the panels
    assert.are.same({ { "OpenToCategory", 42 } }, Stub.settingsCalls)
    Stub.addonListChanged = true
    AddonList_InitAddon(entry, Stub.addonNode(2)) -- the list re-inits rows after every enable toggle
    assert.is_false(entry.wfjSettings:IsEnabled())
    Stub.panelCalls, Stub.settingsCalls = {}, {}
    entry.wfjSettings:click()
    assert.are.same({}, Stub.panelCalls)
    assert.are.same({}, Stub.settingsCalls)
    entry.wfjSettings.scripts.OnEnter(entry.wfjSettings)
    assert.are.equal("先にアドオンの変更を適用またはキャンセルしてください。", WFJSettingsTooltip.text) -- one line, one language
    assert.are.equal(_G.UIParent, WFJSettingsTooltip.parent) -- not the clipping ScrollBox row
  end)

  it("installs only when the settings pages registered, and a failing row never breaks the list", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installAddonList()
    Stub.removeSettingsAPI()
    local ns = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    assert.is_false(ns.AddonListButton.installed)
    load(true)
    local entry = Stub.addonEntry()
    local broken = { GetData = function() error("boom: a row built differently") end }
    assert.has_no.errors(function() WFJ.AddonListButton.decorate(entry, broken) end)
    assert.is_string(WFJ.AddonListButton.error)
  end)

  it("absent at load → nothing hooked; the list's own ADDON_LOADED installs the hook once", function()
    load(false)
    assert.is_false(WFJ.AddonListButton.installed)
    assert.are.equal("addon list button: absent", (function()
      Stub.prints = {}
      SlashCmdList.WFJ("debug")
      for _, line in ipairs(Stub.prints) do if line:find("addon list button", 1, true) then return line:sub(6) end end
    end)())
    Stub.installAddonList()
    Stub.fireAll("ADDON_LOADED", "Blizzard_AddOnList")
    assert.is_true(WFJ.AddonListButton.installed)
    assert.are.equal(1, #Stub.hooks.AddonList_InitAddon)
    Stub.fireAll("ADDON_LOADED", "Blizzard_AddOnList")
    assert.are.equal(1, #Stub.hooks.AddonList_InitAddon)
  end)
end)
