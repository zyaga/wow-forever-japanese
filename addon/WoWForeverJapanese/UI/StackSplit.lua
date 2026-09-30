-- UI/StackSplit.lua: the stack split box (shift-click a stack) on Forever (surface "stacksplit", area "ui",
-- ADR-016). Blizzard_FrameXML loads camelot/stacksplitframe.xml with mainline/stacksplitframe.lua on camelot.
-- Every widget is a parentKey of StackSplitFrame (camelot/stacksplitframe.xml:15–65):
--   OkayButton / CancelButton   static XML text OKAY / CANCEL (:56, 65), shown on OnShow
--   StackSplitText              a bare count (stacksplitframe.lua:19, 76, 97: never a dictionary word), or for a
--                               merchant multi-stack purchase STACKS "%d |4Stack:Stacks;" (:52, 94)
--   StackItemCountText          TOTAL_STACKS "%d Total" (:53, 95)
-- Writers, both the frame's own mixin methods (`self:…()`), post-hooked on the frame: ChooseFrameType (:29–62) and
-- UpdateStackText (:92–99). The count Blizzard works with is `self.split`; the text is never read back
-- (OnChar / OnKeyDown, :101–180, use self.split only).
local _, WFJ = ...
local StackSplit = {}
WFJ.StackSplit = StackSplit

local SURFACE = "stacksplit"
StackSplit.SURFACE = SURFACE
local Compat = WFJ.Compat

StackSplit.NEVER_TOUCH = {}

local CANDIDATES = {
  frame = { "StackSplitFrame" },
  okay = { "StackSplitFrame.OkayButton" }, cancel = { "StackSplitFrame.CancelButton" },
  split = { "StackSplitFrame.StackSplitText" }, total = { "StackSplitFrame.StackItemCountText" },
}
local OKAY, CANCEL = { only = { "OKAY" } }, { only = { "CANCEL" } }
local SPLIT, TOTAL = { only = { "STACKS" } }, { only = { "TOTAL_STACKS" } }

local function get(key) return Compat.get(SURFACE, key) end

-- hooksecurefunc target (StackSplitFrame:ChooseFrameType / :UpdateStackText). → the number of words found.
function StackSplit.onText()
  return WFJ.Labels.show(SURFACE, "split", get("split"), nil, SPLIT)
    + WFJ.Labels.show(SURFACE, "total", get("total"), nil, TOTAL)
end

-- HookScript target (StackSplitFrame OnShow). → the number of words found.
function StackSplit.onShow()
  return WFJ.Labels.showAll(SURFACE, { { "okay", get("okay"), OKAY }, { "cancel", get("cancel"), CANCEL } })
    + StackSplit.onText()
end

local hooked = false

-- Called by Main after Compat.init and ButtonText.init.
function StackSplit.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  local frame = get("frame")
  if type(frame) ~= "table" then return false end
  hooked = true
  for _, method in ipairs({ "ChooseFrameType", "UpdateStackText" }) do
    if type(frame[method]) == "function" then hooksecurefunc(frame, method, StackSplit.onText) end
  end
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", StackSplit.onShow) end
  StackSplit.onShow()
  return true
end
