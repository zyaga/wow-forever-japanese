-- UI/GuildRename.lua over a GuildRenameFrame replayed from
-- blizzard_guildrename/blizzard_guildrename.xml (:54–147) and .lua (:99, :323–358, :439–453, :496–583). Loaded at
-- login. The NPC's name (the title) and the typed guild name stay English. The option buttons' `%s` is a live
-- duration (`time`, C.args; the core entry is in Core/UIStrings).
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")

local UI = {
  GUILD_RENAME_OPTIONS_DESCRIPTION = { "Here are your guild rename options:", "ギルド名変更のオプションです:" },
  GUILD_RENAME_OPTIONS_RENAME_AVAILABLE = { "I want to rename my guild", "ギルド名を変更したい" },
  GUILD_RENAME_OPTIONS_REFUND = { "I would like to refund my guild rename purchase|n(Time remaining to refund: %s)",
    "ギルド名変更の購入を払い戻したい|n(払い戻し期限まで残り: %s)" },
  GUILD_RENAME_DESCRIPTION = { "Please tell me the desired name for your guild.", "希望するギルド名を教えてください。" },
  GUILD_RENAME_EDITBOX_INSTRUCTIONS = { "Enter New Guild Name", "新しいギルド名を入力" },
  GUILD_RENAME_COSTS_LABEL = { "Cost:", "費用:" }, GUILD_RENAME_COMMAND_DO_RENAME = { "Rename", "名前を変更" },
  GOODBYE = { "Goodbye", "さようなら" }, GUILD_RENAME_ERROR_NAME_INVALID = { "Invalid name", "無効な名前です" },
  GUILD_RENAME_COSTS_TOOLTIP = { "The costs will be deducted from your guild bank",
    "費用はギルド銀行から差し引かれます" },
}
local ARGS = { GUILD_RENAME_OPTIONS_REFUND = { [1] = "time" } }

local function en(key) return _G[key] end

local function build()
  local frame = C.window("GuildRenameFrame")
  frame:SetTitle("Goodbye") -- UnitName("npc") (lua:99): an NPC named like a dictionary word
  C.tree(frame, { ["TitleFlow.Description"] = "", ["TitleFlow.RenameOption"] = { button = "" },
    ["TitleFlow.RefundOption"] = { button = "" }, ["RenameFlow.Description"] = en("GUILD_RENAME_DESCRIPTION"),
    ["RenameFlow.NameBox.Instructions"] = en("GUILD_RENAME_EDITBOX_INSTRUCTIONS"), ["RenameFlow.StatusText"] = " ",
    ["RenameFlow.CostLabel"] = en("GUILD_RENAME_COSTS_LABEL"), ContextButton = { button = "" },
    MoneyFrame = { frame = 1 }, GuildIcon = { frame = 1 } })
  frame.RenameFlow.NameBox.text = "Rename" -- the typed guild name (an EditBox)
  function frame.UpdateInteractionMode(self)
    self.TitleFlow.Description.text = en("GUILD_RENAME_OPTIONS_DESCRIPTION")
  end
  function frame.UpdateFromMode(self) self.ContextButton:SetText(en("GUILD_RENAME_COMMAND_DO_RENAME")) end
  function frame.TitleFlow.UpdateOptions(self)
    self.RenameOption:SetText(en("GUILD_RENAME_OPTIONS_RENAME_AVAILABLE"))
    self.RefundOption:SetText(en("GUILD_RENAME_OPTIONS_REFUND"):format("6 Days"))
  end
  function frame.RenameFlow.UpdateFlowNameStatus(self) self.StatusText.text = en("GUILD_RENAME_ERROR_NAME_INVALID") end
  function frame.RenameFlow.ClearRenameStatus(self) self.StatusText.text = " " end
  return frame
end

C.suite(getfenv(1), {
  title = "the guild rename window on Forever", module = "GuildRename", file = "UI/GuildRename.lua",
  root = "GuildRenameFrame", ui = UI, build = build, globals = { "GuildRenameFrame" },
  cases = {
    { "the static labels and the writers' words are Japanese; Alt shows English; hide releases", function(frame, WFJ)
      C.args(WFJ, UI, ARGS)
      frame:Show()
      assert.are.equal("希望するギルド名を教えてください。", frame.RenameFlow.Description:GetText())
      assert.are.equal("新しいギルド名を入力", frame.RenameFlow.NameBox.Instructions:GetText())
      assert.are.equal("費用:", frame.RenameFlow.CostLabel:GetText())
      frame:UpdateInteractionMode()
      assert.are.equal("ギルド名変更のオプションです:", frame.TitleFlow.Description:GetText())
      frame:UpdateFromMode()
      assert.are.equal("名前を変更", frame.ContextButton:GetText())
      frame.TitleFlow:UpdateOptions()
      assert.are.equal("ギルド名を変更したい", frame.TitleFlow.RenameOption:GetText())
      assert.are.equal("ギルド名変更の購入を払い戻したい|n(払い戻し期限まで残り: 6 Days)",
        frame.TitleFlow.RefundOption:GetText())
      frame.RenameFlow:UpdateFlowNameStatus()
      assert.are.equal("無効な名前です", frame.RenameFlow.StatusText:GetText())
      frame.RenameFlow:ClearRenameStatus()
      assert.are.equal(" ", frame.RenameFlow.StatusText:GetText())
      C.alt(WFJ, true)
      assert.are.equal("Rename", frame.ContextButton:GetText())
      C.alt(WFJ, false)
      frame:Hide()
      assert.are.equal("Enter New Guild Name", frame.RenameFlow.NameBox.Instructions:GetText())
    end },
    { "tooltips: the guild icon and the disabled context button", function(frame)
      C.tooltip(frame.GuildIcon, { en("GUILD_RENAME_COSTS_TOOLTIP") })
      assert.are.equal("費用はギルド銀行から差し引かれます", _G.GameTooltipTextLeft1:GetText())
      C.tooltip(frame.ContextButton, { en("GUILD_RENAME_ERROR_NAME_INVALID") })
      assert.are.equal("無効な名前です", _G.GameTooltipTextLeft1:GetText())
    end },
  },
  name = function(frame, WFJ)
    frame:Show()
    local title = frame.TitleContainer.TitleText
    assert.are.equal("Goodbye", title:GetText())
    assert.are.equal(0, WFJ.Labels.show("guildrename", "x", title))
    assert.is_true(C.unrecorded(WFJ, title))
    assert.are.equal(0, WFJ.Labels.show("guildrename", "y", frame.RenameFlow.NameBox))
  end,
  wrong = function(frame)
    frame.TitleFlow, frame.ContextButton, frame.MoneyFrame = "flow", 5, true
    frame.RenameFlow.StatusText = Stub
    return function(f) assert.are.equal("費用:", f.RenameFlow.CostLabel:GetText()) end
  end,
})
