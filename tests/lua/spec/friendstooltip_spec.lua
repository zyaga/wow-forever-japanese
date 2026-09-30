local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

-- the friends list's own tooltip on Forever. A stub of camelot friendsframe.lua's writer:
-- FriendsFrameTooltip_SetLine sums line heights into tooltip.height and widths into maxWidth, then OnEnter sizes the
-- tooltip and Shows it (friendsframe.lua:1879–1902, 1955–1967, 2098–2102).
local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "UI/FriendsTooltip.lua"

local ZONE = "|cffffd200Zone: |r%1$s|n|cffffd200Realm: |r%2$s"
local UI = {
  BNET_FRIEND_TOOLTIP_ZONE_AND_REALM = { ZONE, "|cffffd200ゾーン: |r%1$s|n|cffffd200サーバー: |r%2$s" },
  FRIENDS_TOOLTIP_TOO_MANY_CHARACTERS = { "(%d more |4character:characters;)", "(ほか%d人のキャラクター)" },
}

local function install()
  _G.FRIENDS_TOOLTIP_MARGIN_WIDTH, _G.FRIENDS_TOOLTIP_MAX_WIDTH, _G.FRIENDS_TOOLTIP_MAX_GAME_ACCOUNTS = 12, 200, 5
  local tip = CreateFrame("Frame", "FriendsTooltip")
  function tip:SetHeight(h) self.h = h end
  function tip:SetWidth(w) self.w = w end
  function tip:GetWidth() return self.w end
  for i = 1, 5 do
    local fs = Stub.namedFontString("FriendsTooltipGameAccount" .. i .. "Info", "")
    fs.width = 80
    function fs:GetStringWidth() return #self.text * 5 end
  end
  local many = Stub.namedFontString("FriendsTooltipGameAccountMany", "")
  function many:GetStringWidth() return #self.text * 5 end
  -- OnEnter: one line, sized the way the client sizes it
  return function(zone, realm)
    tip.height, tip.maxWidth = 10, 50
    local line = _G.FriendsTooltipGameAccount1Info
    line:SetText("|cffffd200Zone: |r" .. zone .. "|n|cffffd200Realm: |r" .. realm) -- ZONE:format (positional)
    tip.height = tip.height + line:GetHeight()
    tip.maxWidth = math.max(tip.maxWidth, line:GetStringWidth())
    tip:SetHeight(tip.height + 12)
    tip:SetWidth(math.min(200, tip.maxWidth + 12))
    tip:Show()
    return tip, line
  end
end

describe("UI/FriendsTooltip: the friends list's zone / realm line", function()
  local WFJ, enter

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    enter = install()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    assert.is_true(WFJ.FriendsTooltip.init())
  end)

  after_each(function() H.uiTeardown() end)

  it("the line shows Japanese with the zone and realm as written, and the tooltip is re-sized to it", function()
    local tip, line = enter("Elwynn Forest", "Nightslayer")
    assert.are.equal("|cffffd200ゾーン: |rElwynn Forest|n|cffffd200サーバー: |rNightslayer", line:GetText())
    assert.are.equal(tip.height + 12, tip.h) -- the height follows the line's new height
    assert.is_true(tip.w <= 200)
    enter("Durotar", "Nightslayer") -- the next hover: the client writes English again, we follow
    assert.is_truthy(line:GetText():find("Durotar", 1, true))
    assert.is_truthy(line:GetText():find("ゾーン", 1, true))
    tip:Hide()
    assert.are.equal(0, WFJ.SurfaceState.count(WFJ.FriendsTooltip.SURFACE))
  end)

  it("a line that is not the zone / realm line (a character's rich presence) stays as written", function()
    local tip = _G.FriendsTooltip
    _G.FriendsTooltipGameAccount1Info:SetText("In a battleground")
    tip:Show()
    assert.are.equal("In a battleground", _G.FriendsTooltipGameAccount1Info:GetText())
  end)

  it("the more-characters line shows Japanese with its count, and the tooltip is re-sized to it", function()
    local tip = _G.FriendsTooltip
    local many = _G.FriendsTooltipGameAccountMany
    tip.height, tip.maxWidth = 10, 50
    many:SetText("(3 more characters)") -- string.format(FRIENDS_TOOLTIP_TOO_MANY_CHARACTERS, 8 - 5)
    tip.height = tip.height + many:GetHeight()
    tip:SetHeight(tip.height + 12)
    tip:SetWidth(math.min(200, math.max(tip.maxWidth, many:GetStringWidth()) + 12))
    tip:Show()
    assert.are.equal("(ほか3人のキャラクター)", many:GetText())
    assert.are.equal(tip.height + 12, tip.h)
    many:SetText("(1 more character)") -- the singular
    tip:Show()
    assert.are.equal("(ほか1人のキャラクター)", many:GetText())
    -- the zone line's keys never reach the more-characters line, nor the reverse
    _G.FriendsTooltipGameAccount1Info:SetText("(2 more characters)")
    tip:Show()
    assert.are.equal("(2 more characters)", _G.FriendsTooltipGameAccount1Info:GetText())
  end)
end)
