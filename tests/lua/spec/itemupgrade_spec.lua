-- UI/ItemUpgrade.lua over an ItemUpgradeFrame replayed from
-- camelot blizzard_itemupgradeui/mainline/blizzard_itemupgradeui.xml (:144–365) and .lua (:22, :238, :831–860),
-- load-on-demand in both load orders. The item's name stays English.
local C = require("tests.lua.spec.stub_commerce")

local UI = {
  ITEM_UPGRADE = { "Item Upgrade", "アイテム強化" }, UPGRADE = { "Upgrade", "強化" },
  UPGRADE_MISSING_ITEM = { "Drag an item here to upgrade it.", "強化するアイテムをここにドラッグしてください。" },
  ITEM_UPGRADE_FRAME_UPGRADE_TO = { "Upgrade To:", "強化先:" },
  PVP_ITEM_LEVEL_TOOLTIP = { "Equip: Increases item level to a minimum of %d in Arenas and Battlegrounds.",
    "装備: ArenaとBattlegroundでアイテムレベルが最低%dになる。" },
  ITEM_UPGRADE_NO_MORE_UPGRADES = { "This item cannot be upgraded anymore.", "このアイテムはこれ以上強化できません。" },
}

local function en(key) return _G[key] end

local function build()
  local frame = C.window("ItemUpgradeFrame")
  C.tree(frame, { ["ItemInfo.MissingItemText"] = en("UPGRADE_MISSING_ITEM"), ["ItemInfo.ItemName"] = "Upgrade",
    ["ItemInfo.UpgradeTo"] = en("ITEM_UPGRADE_FRAME_UPGRADE_TO"), UpgradeButton = { button = en("UPGRADE") },
    LeftPreviewBigText = "", RightPreviewBigText = "", FrameErrorText = "" })
  frame:SetTitle(en("ITEM_UPGRADE")) -- OnLoad (lua:22), before any hook
  function frame.PopulatePreviewFrames(self, effect, failure)
    self.RightPreviewBigText.text = effect or string.format(en("PVP_ITEM_LEVEL_TOOLTIP"), 213)
    self.FrameErrorText.text = failure or "" -- a maxed item: ITEM_UPGRADE_NO_MORE_UPGRADES (lua:238–262)
  end
  return frame
end

C.suite(getfenv(1), {
  title = "the item upgrade window on Forever", module = "ItemUpgrade", file = "UI/ItemUpgrade.lua",
  addon = "Blizzard_ItemUpgradeUI", root = "ItemUpgradeFrame", ui = UI, build = build,
  globals = { "ItemUpgradeFrame" },
  cases = {
    { "the title is Japanese on show and again after a second SetTitle; labels translate; hide releases",
      function(frame, WFJ)
        frame:Show()
        local title = frame.TitleContainer.TitleText
        assert.are.equal("アイテム強化", title:GetText())
        frame:SetTitle(en("ITEM_UPGRADE"))
        assert.are.equal("アイテム強化", title:GetText())
        assert.are.equal("強化", frame.UpgradeButton:GetText())
        assert.are.equal("強化先:", frame.ItemInfo.UpgradeTo:GetText())
        C.alt(WFJ, true)
        assert.are.equal("Item Upgrade", title:GetText())
        C.alt(WFJ, false)
        frame:Hide()
        assert.are.equal("Upgrade", frame.UpgradeButton:GetText())
      end },
    { "a maxed item's error text and the Upgrade button's disabled tooltip; a server failure message stays",
      function(frame, WFJ)
        frame:Show()
        frame:PopulatePreviewFrames(nil, en("ITEM_UPGRADE_NO_MORE_UPGRADES"))
        assert.are.equal("このアイテムはこれ以上強化できません。", frame.FrameErrorText:GetText())
        C.tooltip(frame.UpgradeButton, { en("ITEM_UPGRADE_NO_MORE_UPGRADES") })
        assert.are.equal("このアイテムはこれ以上強化できません。", _G.GameTooltipTextLeft1:GetText())
        C.alt(WFJ, true)
        assert.are.equal("This item cannot be upgraded anymore.", frame.FrameErrorText:GetText())
        C.alt(WFJ, false)
        frame:PopulatePreviewFrames(nil, "You need a higher item level.")
        assert.are.equal("You need a higher item level.", frame.FrameErrorText:GetText())
      end },
    { "the PvP item level preview follows PopulatePreviewFrames; an item effect's text does not", function(frame)
      frame:Show()
      frame:PopulatePreviewFrames()
      assert.are.equal("装備: ArenaとBattlegroundでアイテムレベルが最低213になる。", frame.RightPreviewBigText:GetText())
      frame:PopulatePreviewFrames("Upgrade") -- an effect text that is a dictionary word
      assert.are.equal("Upgrade", frame.RightPreviewBigText:GetText())
    end },
  },
  name = function(frame, WFJ)
    frame:Show()
    assert.are.equal("Upgrade", frame.ItemInfo.ItemName:GetText()) -- an item named "Upgrade"
    assert.are.equal(0, WFJ.Labels.show("itemupgrade", "x", frame.ItemInfo.ItemName))
    assert.is_true(C.unrecorded(WFJ, frame.ItemInfo.ItemName))
  end,
  wrong = function(frame)
    frame.ItemInfo, frame.RightPreviewBigText, frame.TitleContainer = 7, "text", true
    return function() assert.are.equal("強化", frame.UpgradeButton:GetText()) end
  end,
})
