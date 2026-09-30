-- Lua-built GameTooltip lines on registered owners: title and help sentence, the refresh
-- path through a writer Blizzard captured before we loaded, unregistered owners, item tooltips never walked, one
-- Show() per pass, release on hide, the toggle contract.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  CHARACTER_BUTTON = { "Character Info", "キャラクター情報" },
  NEWBIE_TOOLTIP_CHARACTER = { "Information about your character.", "キャラクターの情報です。" },
  EQUIP_CONTAINER = { "Equip Container", "バッグを装備" },
}

describe("UI/HelpTooltip", function()
  local WFJ, tt, owner, S

  local function left(i) return _G["GameTooltipTextLeft" .. i] end

  -- MicroButton_OnEnter → GameTooltip_AddNewbieTip, replayed: SetOwner, SetText, AddLine, Show
  local function hover(o, title, help)
    tt:SetOwner(o)
    tt:SetText(title)
    if help then tt:AddLine(help) end
    tt:Show()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    WFJ = H.loadChunks(H.UI_FILES)
    H.uiSetup(WFJ, UI)
    S = WFJ.Settings
    tt = _G.GameTooltip
    owner = Stub.button("CharacterMicroButton", "")
    WFJ.HelpTooltip.register(owner)
  end)

  after_each(H.uiTeardown)

  it("translates the title (key binding kept) and the help sentence, in the bundled font", function()
    hover(owner, "Character Info |cffffd200(C)|r", "Information about your character.")
    assert.are.equal("キャラクター情報 |cffffd200(C)|r", left(1):GetText())
    assert.are.equal("キャラクターの情報です。", left(2):GetText())
    assert.are.equal(WFJ.Font.PATH, (left(1):GetFont()))
  end)

  it("refits with one Show() only when a pass changed a line", function()
    hover(owner, "Character Info", "Information about your character.")
    local before = tt.calls.Show
    tt:Show() -- the client shows the finished tooltip again: nothing changes, no refit of ours
    assert.are.equal(before + 1, tt.calls.Show)
    tt:AddLine("Information about your character.") -- a new English line: one pass, one refit
    tt:Show()
    assert.are.equal(before + 3, tt.calls.Show)
  end)

  it("a refresh that re-runs a captured writer (English again) is Japanese again", function()
    local slot = Stub.button("CharacterBag0Slot", "")
    WFJ.HelpTooltip.register(slot)
    local captured = function(self) tt:SetOwner(self); tt:SetText("Equip Container") end -- UpdateTooltip
    captured(slot)
    assert.are.equal("バッグを装備", left(1):GetText())
    captured(slot) -- GameTooltip_OnUpdate calls owner:UpdateTooltip() again
    assert.are.equal("バッグを装備", left(1):GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Equip Container", left(1):GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("バッグを装備", left(1):GetText())
  end)

  it("leaves a tooltip owned by an unregistered frame untouched", function()
    hover(Stub.button("SomeAddonButton", ""), "Character Info", "Information about your character.")
    assert.are.equal("Character Info", left(1):GetText())
    assert.are.equal(0, left(1).calls.SetText)
  end)

  it("never walks an item or spell tooltip, and forgets its own records when the tooltip is reused", function()
    hover(owner, "Character Info")
    assert.are.equal("キャラクター情報", left(1):GetText())
    tt.owner = owner -- same owner, now showing an item (a bag slot holding a bag)
    Stub.setItemTooltip(tt, "|Hitem:4500:0:0:0|h[Traveler's Backpack]|h", { "Traveler's Backpack", "Character Info" })
    tt.owner = owner
    tt:Show()
    assert.is_nil(WFJ.SurfaceState.get("help", "L2"))
    assert.are.equal("Traveler's Backpack", left(1):GetText())
  end)

  it("area.interface off restores English; release on hide drops the records", function()
    hover(owner, "Character Info", "Information about your character.")
    S.set("area.interface", false)
    assert.are.equal("Character Info", left(1):GetText())
    S.set("area.interface", true)
    assert.are.equal("キャラクター情報", left(1):GetText())
    tt:Hide()
    assert.are.equal(0, WFJ.SurfaceState.count("help"))
    assert.are.equal("Character Info", left(1):GetText())
  end)

  it("a modifier change re-lays the tooltip out for the new text (refit on toggle)", function()
    hover(owner, "Character Info", "Information about your character.")
    local shows = tt.calls.Show
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Character Info", left(1):GetText())
    assert.are.equal(shows + 1, tt.calls.Show) -- one Show for the refresh, not one per line
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal(shows + 2, tt.calls.Show)
  end)

  it("a title Blizzard copies from the owner's translated label is matched as its English", function()
    local tab = Stub.button("SpellBookFrameTabButton1", "Character Info")
    WFJ.Labels.show("test.static", "tab", tab) -- the tab now reads キャラクター情報
    WFJ.HelpTooltip.register(tab)
    tt:SetOwner(tab)
    tt:SetText(tab:GetText() .. " |cFFFFD200(P)|r") -- MicroButtonTooltipText(self:GetText(), …)
    tt:Show()
    assert.are.equal("キャラクター情報 |cFFFFD200(P)|r", left(1):GetText())
    assert.are.equal(WFJ.Font.PATH, (left(1):GetFont()))
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("Character Info |cFFFFD200(P)|r", left(1):GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
  end)

  it("walks after a client setter a module names", function()
    local talent = Stub.button("PlayerTalentFrameTalent1", "")
    WFJ.HelpTooltip.register(talent, { only = { EQUIP_CONTAINER = true } })
    function tt.SetTalent(self) self:SetText("Equip Container"); self:AddLine("Character Info") end
    assert.is_true(WFJ.HelpTooltip.after("SetTalent"))
    tt:SetOwner(talent)
    tt:SetTalent(1, 1)
    assert.are.equal("バッグを装備", left(1):GetText())
    assert.are.equal("Character Info", left(2):GetText()) -- outside `only`
  end)
end)
