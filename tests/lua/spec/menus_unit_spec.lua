local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local M = require("tests.lua.spec.menu_stub")

-- The unit right-click menus (UI/MenusUnit): written once the client has built and shown them, after the pass that
-- checks each entry's IsEnabled (CheckInteractDistance, protected in combat; unitpopupsharedutils.lua:195–205), so no
-- code of the addon runs in that pass. The title is the unit's name (unitpopupshared.lua:110–116): never written.
local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
for _, f in ipairs({ "UI/Menus.lua", "UI/MenusTags.lua", "UI/MenusUnit.lua" }) do FILES[#FILES + 1] = f end

local UI = {
  SET_FOCUS = { "Set Focus", "フォーカスに設定" }, INSPECT = { "Inspect", "調べる" },
  TRADE = { "Trade", "取引" }, DUEL = { "Duel", "決闘" }, WHISPER = { "Whisper", "ささやく" },
  RAID_TARGET_ICON = { "Target Marker Icon", "ターゲットマーカー" }, RAID_TARGET_1 = { "Star", "スター" },
  SET_MAIN_TANK = { "Set Main Tank", "メインタンクに設定" },
  UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_OTHER = { "Other Options", "その他のオプション" },
  REMOVE_FRIEND = { "Remove Friend", "フレンドから削除" },
}

describe("UI/MenusUnit: the unit right-click menus", function()
  local WFJ, registry

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    registry = M.registry()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    assert.is_true(WFJ.Menus.init())
  end)

  after_each(function()
    H.uiTeardown(); _G.EventRegistry = nil; _G.UnitName = nil; _G.issecretvalue = nil
  end)

  local function text(frames, e) return frames[e].fontString:GetText() end

  it("one tag per `which`, each with its keys and a name title", function()
    for _, which in ipairs({ "SELF", "TARGET", "PLAYER", "ENEMY_PLAYER", "PARTY", "PET", "FOCUS", "FRIEND", "RAID",
      "RAID_PLAYER", "BN_FRIEND", "COMMUNITIES_GUILD_MEMBER", "CHAT_ROSTER", "VEHICLE", "PVP_SCOREBOARD" }) do
      local spec = WFJ.Menus.TAGS["MENU_UNIT_" .. which]
      assert.is_table(spec, which)
      assert.is_true(spec.titleIsName, which)
      assert.is_true(#spec.keys > 0, which)
      assert.truthy(spec.source:match("%.lua:%d+"), which)
    end
  end)

  it("a target menu: entries and a submenu in Japanese; the unit's name stays even when it is a dictionary word",
    function()
      _G.UnitName = function(unit) return unit == "target" and "Trade" or nil end -- a player named "Trade"
      WFJ.Compat.init(function(name) return _G[name] end)
      local root = M.element(nil)
      root:CreateButton("Trade") -- the title: the unit's name
      local marker = root:CreateButton(UI.RAID_TARGET_ICON[1])
      marker:CreateButton(UI.RAID_TARGET_1[1])
      root:CreateButton(UI.SET_FOCUS[1])
      root:CreateButton(UI.INSPECT[1])
      root:CreateButton(UI.TRADE[1]) -- the Trade entry: the same English as the name
      local frames, menus = M.open(registry, "MENU_UNIT_TARGET", root, { unit = "target" })
      local e = root.children
      assert.are.equal("Trade", text(frames, e[1]))
      assert.are.equal("ターゲットマーカー", text(frames, e[2]))
      assert.are.equal("スター", text(frames, marker.children[1]))
      assert.are.equal("フォーカスに設定", text(frames, e[3]))
      assert.are.equal("調べる", text(frames, e[4]))
      assert.are.equal("Trade", text(frames, e[5])) -- matching the unit's name: never written
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("Set Focus", text(frames, e[3]))
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      M.close(registry, menus)
      assert.are.equal(0, WFJ.SurfaceState.count(WFJ.Menus.SURFACE))
    end)

  it("a unit whose name the client keeps secret: the title is still never written, nothing raises", function()
    local SECRET = "Jaina" -- stands for a secret string value
    _G.UnitName = function() return SECRET end
    _G.issecretvalue = function(v) return v == SECRET end
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.initErrors = nil
    local root = M.element(nil)
    root:CreateButton(SECRET)
    root:CreateButton(UI.DUEL[1])
    local frames = M.open(registry, "MENU_UNIT_PLAYER", root, { unit = "target" })
    assert.are.equal(SECRET, text(frames, root.children[1]))
    assert.are.equal("決闘", text(frames, root.children[2]))
    assert.is_nil(WFJ.initErrors)
  end)

  it("the raid and friend menus take their own lists; an entry another list holds stays English", function()
    local root = M.element(nil)
    root:CreateButton("Thrall")
    root:CreateButton(UI.SET_MAIN_TANK[1])
    root:CreateButton(UI.REMOVE_FRIEND[1]) -- not in the raid list
    local frames, menus = M.open(registry, "MENU_UNIT_RAID", root, { name = "Thrall" })
    assert.are.equal("Thrall", text(frames, root.children[1]))
    assert.are.equal("メインタンクに設定", text(frames, root.children[2]))
    assert.are.equal("Remove Friend", text(frames, root.children[3]))
    M.close(registry, menus)
    local friend = M.element(nil)
    friend:CreateButton("Jaina")
    friend:CreateButton(UI.REMOVE_FRIEND[1])
    local ff = M.open(registry, "MENU_UNIT_BN_FRIEND", friend, { name = "Jaina" })
    assert.are.equal("フレンドから削除", text(ff, friend.children[2]))
  end)
end)
