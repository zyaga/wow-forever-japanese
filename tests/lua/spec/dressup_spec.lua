-- UI/DressUp.lua over DressUpFrame / SideDressUpFrame replayed from
-- camelot blizzard_uipanels_game/mainline/dressupframes.xml (:100, :304, :383–387, :434, :444) and
-- blizzard_sharedxmlgame/dressupmodelframemixin.lua:155–158 (SetTitle(DRESSUP_FRAME)).
local Stub = require("tests.lua.spec.wow_stub")
local G = require("tests.lua.spec.stub_gamepanels")

local FILES = G.files("UI/DressUp.lua")
local UI = { DRESSUP_FRAME = { "Dressing Room", "試着室" }, CLOSE = { "Close", "閉じる" }, RESET = { "Reset", "リセット" },
  LINK_TRANSMOG_CUSTOM_SET = { "Link Custom Set", "カスタムセットをリンク" },
  DRESSING_ROOM_APPEARANCE_LIST = { "Appearance List", "外観リスト" },
  TRANSMOG_CUSTOM_SET_NONE = { "No Custom Set", "カスタムセットなし" }, SAVE = { "Save", "保存" },
  PARENS_TEMPLATE = { "(%s)", "(%s)" }, HEADSLOT = { "Head", "頭" },
  TRANSMOGRIFIED_ENCHANT = { "Illusion: %s", "幻影: %s" } }
local NAMES = { "DressUpFrame", "SideDressUpFrame", "DressUpFrameCancelButton" }

local function install()
  local frame = G.titled("DressUpFrame")
  frame:SetTitle(_G.DRESSUP_FRAME) -- DressUpModelFrameMixin:OnLoad
  Stub.button("DressUpFrameCancelButton", _G.CLOSE)
  frame.ResetButton = Stub.button(nil, _G.RESET)
  frame.LinkButton = Stub.button(nil, _G.LINK_TRANSMOG_CUSTOM_SET)
  frame.ToggleCustomSetDetailsButton = CreateFrame("Button")
  frame.CustomSetDropdown = { Text = Stub.fontString("Reset"), -- a saved set the player named "Reset"
    SaveButton = Stub.button(nil, _G.SAVE) }
  -- WardrobeCustomSetDropdownMixin: UpdateText writes the selection, or the grey default text
  -- (wardrobecustomsets.lua:22)
  function frame.CustomSetDropdown:UpdateText()
    self.Text:SetText(self.selection or ("|cff808080" .. _G.TRANSMOG_CUSTOM_SET_NONE .. "|r"))
  end
  local side = CreateFrame("Frame", "SideDressUpFrame")
  side.ResetButton = Stub.button(nil, _G.RESET)
  return frame, side
end

describe("the dressing room on Forever", function()
  local WFJ

  before_each(function() WFJ = G.load(FILES, UI) end)
  after_each(function() G.clear(NAMES) end)

  it("the title renders Japanese after SetTitle and keeps it after a second SetTitle", function()
    local frame = install()
    assert.is_true(WFJ.DressUp.init())
    local title = frame.TitleContainer.TitleText
    assert.are.equal("試着室", title:GetText())
    frame:SetTitle(_G.DRESSUP_FRAME)
    assert.are.equal("試着室", title:GetText())
    frame:SetTitle("Reset") -- not the title's key
    assert.are.equal("Reset", title:GetText())
  end)

  it("buttons and the appearance-list tooltip translate; the player's set name stays as written", function()
    local frame, side = install()
    WFJ.Labels.forbidNames(WFJ.DressUp.NEVER_TOUCH)
    assert.is_true(WFJ.DressUp.init())
    frame:Show()
    side:Show()
    assert.are.equal("閉じる", _G.DressUpFrameCancelButton:GetText())
    assert.are.equal("リセット", frame.ResetButton:GetText())
    assert.are.equal("カスタムセットをリンク", frame.LinkButton:GetText())
    assert.are.equal("リセット", side.ResetButton:GetText())
    assert.are.equal("Reset", frame.CustomSetDropdown.Text:GetText())
    assert.is_true(G.unrecorded(WFJ, frame.CustomSetDropdown.Text))
    G.tooltip(frame.ToggleCustomSetDetailsButton, { "Appearance List" })
    assert.are.equal("外観リスト", G.line(1))
    G.alt(WFJ, true)
    assert.are.equal("Reset", side.ResetButton:GetText())
    G.alt(WFJ, false)
    side:Hide()
    assert.are.equal("Reset", side.ResetButton:GetText())
    assert.are.equal("リセット", frame.ResetButton:GetText()) -- the main window is still open
  end)

  it("the details panel's illusion row after Refresh: the illusion's name kept; an item row "
    .. "stays", function()
      local frame = install()
      -- CustomSetDetailsPanel (dressupframes.xml:397): Refresh re-acquires the slot rows from slotPool (lua:570–640)
      local rows = {}
      local pool = { active = {} }
      function pool.EnumerateActive(p) return pairs(p.active) end
      local panel = { slotPool = pool }
      function panel.Refresh(p)
        p.slotPool.active = {}
        for i, name in ipairs(p.names) do
          rows[i] = rows[i] or { Name = Stub.fontString("") }
          rows[i].Name.text = name -- SetDetails (:948)
          p.slotPool.active[rows[i]] = true
        end
      end
      frame.CustomSetDetailsPanel = panel
      assert.is_true(WFJ.DressUp.init())
      panel.names = { "Illusion: Crusader", "Illusion: Maybe" }
      panel:Refresh()
      assert.are.equal("幻影: Crusader", rows[1].Name:GetText())
      panel.names = { "Arcanite Reaper", "Illusion: Fiery Weapon" } -- the pool reused: row 1 is an item now
      panel:Refresh()
      assert.are.equal("Arcanite Reaper", rows[1].Name:GetText())
      assert.are.equal("幻影: Fiery Weapon", rows[2].Name:GetText())
      G.alt(WFJ, true)
      assert.are.equal("Illusion: Fiery Weapon", rows[2].Name:GetText())
      G.alt(WFJ, false)
      frame:Hide()
      assert.are.equal("Illusion: Fiery Weapon", rows[2].Name:GetText())
    end)

  it("the custom-set dropdown's empty text and Save are Japanese; a set named like the empty text is not",
    function()
      local frame = install()
      assert.is_true(WFJ.DressUp.init())
      local dd = frame.CustomSetDropdown
      dd:UpdateText()
      assert.are.equal("|cff808080カスタムセットなし|r", dd.Text:GetText())
      assert.are.equal("保存", dd.SaveButton:GetText())
      dd.selection = "No Custom Set" -- a saved set the player named exactly like the empty text
      dd:UpdateText()
      assert.are.equal("No Custom Set", dd.Text:GetText())
      assert.is_true(G.unrecorded(WFJ, dd.Text))
      dd.selection = nil
      dd:UpdateText()
      G.alt(WFJ, true)
      assert.are.equal("|cff808080No Custom Set|r", dd.Text:GetText())
      G.alt(WFJ, false)
    end)

  it("the appearance list's empty slot rows show the slot word in Japanese; an item name stays",
    function()
      local frame = install()
      local rows = { { Name = Stub.fontString("(Head)") }, { Name = Stub.fontString("Novice's Robe") } }
      local panel = { slotPool = { EnumerateActive = function() local i = 0
        return function() i = i + 1; return rows[i] end end } }
      function panel.Refresh() end
      frame.CustomSetDetailsPanel = panel
      WFJ.UIStrings.ARGS.PARENS_TEMPLATE = WFJ.UIStrings.ARGS.PARENS_TEMPLATE or { [1] = "entry" }
      assert.is_true(WFJ.DressUp.init())
      panel:Refresh()
      assert.are.equal("(頭)", rows[1].Name:GetText())
      assert.are.equal("Novice's Robe", rows[2].Name:GetText())
    end)

  it("wrong-typed names degrade without error", function()
    local frame = install()
    frame.ResetButton, frame.LinkButton, frame.ToggleCustomSetDetailsButton = 1, "x", false
    _G.SideDressUpFrame = 2
    _G.DressUpFrameCancelButton = true
    assert.has_no.errors(function() assert.is_true(WFJ.DressUp.init()) end)
    assert.has_no.errors(function() frame:Show() end)
    assert.are.equal("試着室", frame.TitleContainer.TitleText:GetText())
    assert.is_false(WFJ.DressUp.init())
  end)

  it("no DressUpFrame: init is false and nothing is touched", function()
    assert.has_no.errors(function() assert.is_false(WFJ.DressUp.init()) end)
  end)
end)
