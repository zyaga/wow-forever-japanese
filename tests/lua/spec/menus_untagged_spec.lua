local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local M = require("tests.lua.spec.menu_stub")

-- the untagged context menus, through a post-hook on Menu.PopulateDescription (the generator runs, then
-- SecureModifyMenu returns on no tag, then MenuUtil.CreateContextMenu opens the menu; blizzard_menu/menuutil.lua:
-- 151–161; menu.lua:2708–2722): the Group Finder's search-entry menu (blizzard_lfgvanilla_browse.lua:948–980) and
-- the crafting-orders recipe list's (…customerordersrecipelist.lua:96–97; …browseorders.lua:139–155).
local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
for _, f in ipairs({ "UI/SettingsKeys.lua", "UI/MenusUnit.lua", "UI/Menus.lua", "UI/MenusTags.lua",
  "UI/MenusUntagged.lua" }) do FILES[#FILES + 1] = f end

local UI = {
  SEND_MESSAGE = { "Send Message", "メッセージを送信" },
  GROUP_INVITE = { "Group Invite", "グループに招待" },
  LFG_LIST_REPORT_GROUP_FOR = { "Report Group", "グループを報告" },
  REPORT_GROUP_FINDER_ADVERTISEMENT = { "Report Advertisement", "広告を報告" },
  BATTLE_PET_FAVORITE = { "Set Favorite", "お気に入りに設定" },
  BATTLE_PET_UNFAVORITE = { "Remove Favorite", "お気に入りから外す" },
  RAID = { "Raid", "レイド" },
}

describe("UI/MenusUntagged: untagged context menus", function()
  local WFJ, menu, modified

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    modified = {}
    -- the client's Menu: PopulateDescription runs the generator, then SecureModifyMenu (a ModifyMenu callback only
    -- for a tagged description)
    menu = { ModifyMenu = function(tag, fn) modified[tag] = fn end }
    function menu.PopulateDescription(generator, owner, desc, ...)
      generator(owner, desc, ...)
      local tag = desc:GetTag()
      if tag and modified[tag] then modified[tag](owner, desc, nil) end
    end
    _G.Menu = menu
    _G.MenuUtil = {
      GetElementText = function(desc) return desc.text end,
      -- menuutil.lua:151–161: looks Menu.PopulateDescription up at call time, then opens
      CreateContextMenu = function(owner, generator, ...)
        local root = M.element(nil)
        _G.Menu.PopulateDescription(generator, owner, root, ...)
        return root, M.open(root)
      end,
    }
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    WFJ.Menus.init()
    assert.are.equal(1, WFJ.MenusUntagged.init()) -- the PopulateDescription hook (no Settings / Edit Mode here)
  end)

  after_each(function() H.uiTeardown(); _G.Menu, _G.MenuUtil = nil, nil end)

  it("the LFG search-entry menu: entries in Japanese, the leader's name title never touched", function()
    -- LFGBrowseMixin:CreateSearchEntryMenu: an anonymous generator on an undefined owner
    local root, frames = _G.MenuUtil.CreateContextMenu(nil, function(_, r)
      r:CreateButton("Jaina") -- the title: the leader's name
      r:CreateButton(UI.SEND_MESSAGE[1])
      r:CreateButton(UI.GROUP_INVITE[1])
      r:CreateButton(UI.LFG_LIST_REPORT_GROUP_FOR[1])
      r:CreateButton(UI.REPORT_GROUP_FINDER_ADVERTISEMENT[1])
    end)
    local e = root.children
    assert.are.equal("Jaina", frames[e[1]].fontString:GetText())
    assert.are.equal("メッセージを送信", frames[e[2]].fontString:GetText())
    assert.are.equal("グループに招待", frames[e[3]].fontString:GetText())
    assert.are.equal("グループを報告", frames[e[4]].fontString:GetText())
    assert.are.equal("広告を報告", frames[e[5]].fontString:GetText())
    -- a leader whose name is a dictionary word ("Raid") keeps it: the first element is the title
    local leader, lf = _G.MenuUtil.CreateContextMenu(nil, function(_, r)
      r:CreateButton(UI.RAID[1])
      r:CreateButton(UI.SEND_MESSAGE[1])
      r:CreateButton(UI.REPORT_GROUP_FINDER_ADVERTISEMENT[1])
    end)
    assert.are.equal("Raid", lf[leader.children[1]].fontString:GetText())
    assert.are.equal("メッセージを送信", lf[leader.children[2]].fontString:GetText())
  end)

  it("the crafting-orders recipe menu: recognised by its owner's contextMenuGenerator", function()
    local generator = function(_, r, spellID)
      assert.are.equal(2259, spellID)
      r:CreateButton(UI.BATTLE_PET_UNFAVORITE[1])
    end
    local element = { contextMenuGenerator = generator } -- ProfessionsCustomerOrdersRecipeListElementMixin
    local root, frames = _G.MenuUtil.CreateContextMenu(element, element.contextMenuGenerator, 2259)
    assert.are.equal("お気に入りから外す", frames[root.children[1]].fontString:GetText())
  end)

  it("any other untagged context menu is left alone", function()
    local root, frames = _G.MenuUtil.CreateContextMenu({}, function(_, r)
      r:CreateButton(UI.SEND_MESSAGE[1])
      r:CreateButton(UI.BATTLE_PET_FAVORITE[1])
    end)
    assert.are.equal("Send Message", frames[root.children[1]].fontString:GetText())
    assert.are.equal("Set Favorite", frames[root.children[2]].fontString:GetText())
  end)

  it("a tagged menu goes through its ModifyMenu callback only (no second walk)", function()
    local root = M.element(nil)
    root.tag = "MENU_TOYBOX_FAVORITE"
    local n = 0
    local wrap = WFJ.Menus.onMenu
    WFJ.Menus.onMenu = function(...) n = n + 1; return wrap(...) end
    _G.Menu.PopulateDescription(function(_, r) r:CreateButton(UI.BATTLE_PET_FAVORITE[1]) end, nil, root)
    WFJ.Menus.onMenu = wrap
    assert.are.equal(1, n) -- Menus.init's callback; the PopulateDescription hook returned at once
    assert.are.equal("お気に入りに設定", M.open(root)[root.children[1]].fontString:GetText())
    assert.are.equal(0, WFJ.MenusUntagged.onPopulate(nil, nil, root))
  end)

  it("malformed arguments never error", function()
    assert.are.equal(0, WFJ.MenusUntagged.onPopulate(nil, nil, nil))
    assert.are.equal(0, WFJ.MenusUntagged.onPopulate(nil, nil, {}))
    assert.are.equal(0, WFJ.MenusUntagged.onPopulate(nil, nil, { GetTag = function() return nil end }))
  end)

  it("a walk that throws never reaches the client's menu: recorded once for /wfj debug, the menu opens", function()
    WFJ.initErrors = {}
    local root = { GetTag = function() return nil end,
      EnumerateElementDescriptions = function() error("walk broke") end }
    assert.has_no.errors(function() assert.are.equal(0, WFJ.MenusUntagged.onPopulate(nil, nil, root)) end)
    assert.has_no.errors(function() WFJ.MenusUntagged.onPopulate(nil, nil, root) end)
    assert.are.equal(1, #WFJ.initErrors)
    assert.are.equal("menus.untagged", WFJ.initErrors[1].surface)
    assert.is_truthy(WFJ.initErrors[1].err:find("walk broke", 1, true))
    -- through the client's own PopulateDescription (the post-hook runs after the generator)
    local opened = false
    assert.has_no.errors(function()
      _G.Menu.PopulateDescription(function() opened = true end, nil, root)
    end)
    assert.is_true(opened)
  end)
end)
