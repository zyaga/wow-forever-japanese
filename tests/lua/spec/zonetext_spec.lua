-- UI/ZoneText.lua over the zone banner replayed from camelot blizzard_framexml/mainline/zonetext.lua
-- (SetZoneText :7–69, AutoFollowStatus_OnEvent :142–158). Client writes go to `fs.text`.
local Stub = require("tests.lua.spec.wow_stub")
local X = require("tests.lua.spec.stub_framexml_hud")

local UI = {
  SANCTUARY_TERRITORY = { "(Sanctuary)", "（聖域）" },
  CONTESTED_TERRITORY = { "(Contested Territory)", "（紛争地域）" },
  FACTION_CONTROLLED_TERRITORY = { "(%s Territory)", "（%s領）" },
  AUTOFOLLOWSTART = { "Following %s.", "%sを追従中。" },
  AUTOFOLLOWSTOP = { "You stop following %s.", "%sの追従をやめた。" },
  SANCTUARY = { "Sanctuary", "聖域" }, -- a dictionary word that is also a place name
}
local ARGS = { FACTION_CONTROLLED_TERRITORY = { [1] = "text" }, AUTOFOLLOWSTART = { [1] = "text" },
  AUTOFOLLOWSTOP = { [1] = "text" } }
local NAMES = { "ZoneTextString", "SubZoneTextString", "PVPInfoTextString", "PVPArenaTextString",
  "AutoFollowStatus", "AutoFollowStatusText", "SetZoneText" }

local P = {}

local function install()
  for _, n in ipairs({ "ZoneTextString", "SubZoneTextString", "PVPInfoTextString", "PVPArenaTextString",
    "AutoFollowStatusText" }) do Stub.namedFontString(n, "") end
  _G.SetZoneText = function()
    _G.PVPInfoTextString.text, _G.PVPArenaTextString.text = "", ""
    _G.ZoneTextString.text = P.zone
    if P.pvp == "sanctuary" then _G.PVPInfoTextString.text = _G.SANCTUARY_TERRITORY
    elseif P.pvp == "contested" then _G.PVPInfoTextString.text = _G.CONTESTED_TERRITORY
    elseif P.pvp == "friendly" then _G.PVPArenaTextString.text = _G.FACTION_CONTROLLED_TERRITORY:format(P.faction) end
  end
  local follow = CreateFrame("Frame", "AutoFollowStatus")
  follow:SetScript("OnEvent", function(_, event, unit)
    _G.AutoFollowStatusText.text = (event == "AUTOFOLLOW_BEGIN" and _G.AUTOFOLLOWSTART or _G.AUTOFOLLOWSTOP)
      :format(unit)
  end)
end

describe("the zone banner's PvP line on Forever", function()
  local WFJ
  before_each(function()
    P = { zone = "Sanctuary", pvp = "sanctuary" }
    WFJ = X.load("UI/ZoneText.lua", UI, { args = ARGS, before = install })
    WFJ.Labels.forbidNames(WFJ.ZoneText.NEVER_TOUCH)
    assert.is_true(WFJ.ZoneText.init())
  end)
  after_each(function() X.teardown(NAMES) end)

  it("the PvP line translates after SetZoneText; the zone name (even a dictionary word) stays English", function()
    _G.SetZoneText(true)
    assert.are.equal("（聖域）", _G.PVPInfoTextString:GetText())
    assert.are.equal("Sanctuary", _G.ZoneTextString:GetText())
    assert.is_true(X.unrecorded(WFJ, _G.ZoneTextString))
    assert.are.equal(0, WFJ.Labels.show("zonetext", "x", _G.ZoneTextString)) -- forbidden whoever asks
    X.alt(WFJ, true)
    assert.are.equal("(Sanctuary)", _G.PVPInfoTextString:GetText())
    X.alt(WFJ, false)
    P.pvp = "contested"
    _G.SetZoneText(true)
    assert.are.equal("（紛争地域）", _G.PVPInfoTextString:GetText())
    P.pvp = nil
    _G.SetZoneText(true)
    assert.are.equal("", _G.PVPInfoTextString:GetText()) -- the client's own "" is what SetZoneText reads back
  end)

  it("a faction's territory keeps the faction name as written", function()
    P.pvp, P.faction = "friendly", "Darnassus"
    _G.SetZoneText(true)
    assert.are.equal("（Darnassus領）", _G.PVPArenaTextString:GetText())
  end)

  it("the follow status translates through the frame's OnEvent; the unit name is kept", function()
    _G.AutoFollowStatus.scripts.OnEvent(_G.AutoFollowStatus, "AUTOFOLLOW_BEGIN", "Reyn")
    assert.are.equal("Reynを追従中。", _G.AutoFollowStatusText:GetText())
    _G.AutoFollowStatus.scripts.OnEvent(_G.AutoFollowStatus, "AUTOFOLLOW_END", "Reyn")
    assert.are.equal("Reynの追従をやめた。", _G.AutoFollowStatusText:GetText())
  end)

  it("hooks once; a wrong-typed name and a missing frame both leave English and raise nothing", function()
    assert.is_false(WFJ.ZoneText.init())
    assert.are.equal(1, #Stub.hooks["SetZoneText"])
    X.teardown(NAMES)
    local wrong = X.load("UI/ZoneText.lua", UI, { args = ARGS, before = function()
      install()
      _G.PVPInfoTextString = "not a widget"
    end })
    assert.has_no.errors(function() assert.is_false(wrong.ZoneText.init()) end)
    X.teardown(NAMES)
    local none = X.load("UI/ZoneText.lua", UI, { args = ARGS })
    assert.has_no.errors(function() assert.is_false(none.ZoneText.init()) end)
  end)
end)
