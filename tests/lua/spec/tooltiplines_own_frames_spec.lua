-- TooltipLines.follow over the two new tooltip frames of their own (EventTraceTooltip,
-- blizzard_eventtrace.lua:813–836; CustomizationNoHeaderTooltip, blizzard_customizationtemplates.lua:27–29) walked on
-- each Show, restricted to the watching module's keys, released on OnHide. GameTooltip's walk is unchanged
-- (helptooltip_spec and every surface spec that registers an owner still run against it).
local Stub = require("tests.lua.spec.wow_stub")
local X = require("tests.lua.spec.stub_framexml_hud")

local UI = {
  EVENTTRACE_TIMESTAMP = { "Timestamp:", "タイムスタンプ:" }, EVENTTRACE_ARG_FMT = { "Arg %d:", "引数%d:" },
  RESET_CAMERA = { "Reset Camera", "カメラをリセット" }, ACCEPT = { "Accept", "承諾" },
}
local NAMES = { "EventTraceTooltip", "EventTraceTooltipTextLeft1" }

local function text(tt, side, i) return _G[tt:GetName() .. "Text" .. side .. i]:GetText() end

describe("the Event Log tooltip through TooltipLines.follow", function()
  local WFJ, tt
  before_each(function()
    WFJ = X.load("UI/TooltipLines.lua", UI)
    tt = Stub.tooltipFrame("EventTraceTooltip")
    assert.is_true(WFJ.TooltipLines.follow("eventtrace.tooltip", tt,
      { only = { "EVENTTRACE_TIMESTAMP", "EVENTTRACE_ARG_FMT" } }))
  end)
  after_each(function() X.teardown(NAMES) end)

  local function rowTooltip()
    tt:SetOwner({})
    tt:ClearLines()
    tt:AddLine("PLAYER_LOGIN")
    tt:AddDoubleLine("Timestamp:", "1234.5")
    tt:AddDoubleLine("Arg 1:", "Accept") -- an argument value that is a dictionary word
    tt:Show()
  end

  it("each Show walks the lines, restricted to the module's keys; a value is never touched", function()
    rowTooltip()
    assert.are.equal("PLAYER_LOGIN", text(tt, "Left", 1))
    assert.are.equal("タイムスタンプ:", text(tt, "Left", 2))
    assert.are.equal("1234.5", text(tt, "Right", 2))
    assert.are.equal("引数1:", text(tt, "Left", 3))
    assert.are.equal("Accept", text(tt, "Right", 3))
    X.alt(WFJ, true)
    assert.are.equal("Timestamp:", text(tt, "Left", 2))
    X.alt(WFJ, false)
    assert.are.equal("タイムスタンプ:", text(tt, "Left", 2))
  end)

  it("OnHide releases the records; a second watch of the same frame is refused", function()
    rowTooltip()
    tt:Hide()
    assert.are.equal(0, (function()
      local n = 0
      for _ in pairs(WFJ.SurfaceState.records("eventtrace.tooltip")) do n = n + 1 end
      return n
    end)())
    assert.is_false(WFJ.TooltipLines.follow("eventtrace.tooltip", tt, { only = {} }))
    assert.is_false(WFJ.TooltipLines.follow("x", nil, { only = {} }))
  end)

  it("a GameTooltip help walk is unaffected by a watched frame", function()
    local owner = {}
    WFJ.HelpTooltip.register(owner)
    _G.GameTooltip:SetOwner(owner)
    _G.GameTooltip:SetText("Accept")
    assert.are.equal("承諾", _G.GameTooltipTextLeft1:GetText())
    rowTooltip()
    assert.are.equal("承諾", _G.GameTooltipTextLeft1:GetText())
  end)
end)
