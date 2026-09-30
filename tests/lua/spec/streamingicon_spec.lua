-- The download icon's tooltip on Forever: UI/StreamingIcon.lua over a StreamingIcon replayed from camelot
-- blizzard_framexml/mainline/streamingframe.xml (:3, OnEnter :50–55) and .lua (:20–46).
local R = require("tests.lua.spec.stub_retail")

local UI = {
  STATUS_CORE_FILE_TOOLTIP = { "Core game data is currently being downloaded.", "コアゲームデータをダウンロード中です。" },
  STATUS_ADDL_FILE_TOOLTIP = { "Game data is currently being downloaded.", "ゲームデータをダウンロード中です。" },
  NONE = { "None", "なし" },
}
local GLOBALS = { "StreamingIcon" }

local function build() return CreateFrame("Frame", "StreamingIcon") end

R.suite(getfenv(1), {
  title = "the download icon's tooltip on Forever", module = "StreamingIcon",
  file = "UI/StreamingIcon.lua", root = "StreamingIcon", globals = GLOBALS, ui = UI, build = build,
  cases = {
    { "the tooltip line is Japanese; Alt shows English", function(frame, WFJ)
      R.tooltip(frame, { _G.STATUS_CORE_FILE_TOOLTIP })
      assert.are.equal("コアゲームデータをダウンロード中です。", _G.GameTooltipTextLeft1:GetText())
      R.alt(WFJ, true)
      assert.are.equal("Core game data is currently being downloaded.", _G.GameTooltipTextLeft1:GetText())
      R.alt(WFJ, false)
    end },
  },
  name = function(frame)
    R.tooltip(frame, { "None" }) -- only the three download words belong to this owner
    assert.are.equal("None", _G.GameTooltipTextLeft1:GetText())
  end,
  wrong = function()
    return function(_, WFJ) assert.is_true(WFJ.HelpTooltip.registered(_G.StreamingIcon)) end
  end,
})
