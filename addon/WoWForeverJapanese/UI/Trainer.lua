-- UI/Trainer.lua: the class / profession trainer's fixed words (surface "trainer", area "ui",
-- ADR-016). Blizzard_TrainerUI is load-on-demand and loads its [Family] = mainline files on camelot [verified: Forever
-- blizzard_trainerui.toc:6–9], so everything here is set up through WFJ.LoadOnDemand.when("Blizzard_TrainerUI", …).
-- - Static (XML text=): ClassTrainerTrainButton TRAIN (xml:217). "trainer.static".
-- - The services are ScrollBox rows (ClassTrainerSkillButtonTemplate, no global names), each written by the global
--   ClassTrainerFrame_InitServiceButton(button, elementData): called by global name from the view's initializer,
--   ClassTrainerFrame_Update (the step button) and ClassTrainer_SetSelection [verified:
--   mainline/blizzard_trainerui.lua:158–170, 466, 520–683, 736, 750], so one post-hook sees every row:
--   button.nameSubText = PARENS_TEMPLATE:format(subtext) (lua:603), restricted to PARENS_TEMPLATE, whose argument must
--     be a dictionary word (ARGS);
--   button.subText = REQUIRES_LABEL .. " " .. <requirements> or ITEM_SPELL_KNOWN (lua:591–601): the `list` label form
--     (Core/UIStrings) shows "必要:" and each item that is a requirement template in Japanese;
--   button.alternateCost = TRAINING_POINTS_ABBREV:format(cost) on a pet trainer (lua:634), re-written by
--     ClassTrainerFrame_UpdateTrainingPoints (lua:505–518), which also writes trainingPoints.text = TRAINING_POINTS
--     (xml:244–253), post-hooked too.
-- - The filter dropdown's button text: SetSelectionText returns FILTER and the Menu system writes it into
--   FilterDropdown.Text in UpdateText (xml:231; Blizzard_Menu/MenuTemplates.lua:530–540, 612–644):
--   WFJ.Labels.dropdown; on 1.60.1.70009 also FilterDropdown:SetText(SETTINGS or FILTERS) (lua:464).
--   The menu's Available / Unavailable / Already Known entries are popup entries (the menu system's).
-- Help tooltips, walked by UI/HelpTooltip on registered owners:
--   ClassTrainerTrainButton, disabled for a third primary profession: SetOwner(ClassTrainerTrainButton),
--     GameTooltip_AddNormalLine(TRAINER_CANNOT_EXCEED_MAX_PROFESSIONS), Show (lua:288–304), restricted to that key;
--   the pet trainer's points frame: SetOwner(self), SetText(TRAINING_POINTS_TUTORIAL), Show (xml:254–262): an
--     ordinary tooltip, not a HelpTip callout, restricted to that key.
-- Not translated: row names (button.name) are never candidates; the client-built service tooltip.
-- Release on ClassTrainerFrame's OnHide (the static label stays).
local _, WFJ = ...
local Trainer = {}
WFJ.Trainer = Trainer

local SURFACE = "trainer"
local STATIC = "trainer.static"
Trainer.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_TrainerUI"

local SUBTEXT_KEYS = { PARENS_TEMPLATE = true }
local ROW_REQUIREMENT_KEYS = { REQUIRES_LABEL = true, ITEM_SPELL_KNOWN = true } -- (lua:591–598)
local COST_KEYS = { TRAINING_POINTS_ABBREV = true }
local POINTS_KEYS = { TRAINING_POINTS = true }
local TRAIN_HELP_KEYS = { "TRAINER_CANNOT_EXCEED_MAX_PROFESSIONS" }
local POINTS_HELP_KEYS = { "TRAINING_POINTS_TUTORIAL" }

-- Widgets this module must never record: none by name (row names are pooled `button.name`, never read).
Trainer.NEVER_TOUCH = {}

-- A stable record key per ScrollBox service button (buttons are pooled and re-initialized).
local rowKey = WFJ.Labels.keyer("svc") -- a pooled row's record key
local seen = setmetatable({}, { __mode = "k" }) -- every service button shown, for the points refresh

-- hooksecurefunc target for ClassTrainerFrame_InitServiceButton: one service button's subtext,
-- requirements and pet cost. → the number of words found
function Trainer.onService(button)
  if type(button) ~= "table" then return 0 end
  local k = rowKey(button)
  seen[button] = true
  local n = WFJ.Labels.showAll(SURFACE, {
    { k .. ".sub", button.nameSubText, { only = SUBTEXT_KEYS } },
    { k .. ".req", button.subText, { only = ROW_REQUIREMENT_KEYS } },
    { k .. ".cost", button.alternateCost, { only = COST_KEYS } },
  })
  return n
end

-- hooksecurefunc target for ClassTrainerFrame_UpdateTrainingPoints: the pet trainer's points label, then
-- every service button seen so far (their pet costs were re-written). → the number of words found
function Trainer.onTrainingPoints()
  local frame = Compat.get(SURFACE, "frame")
  local points = type(frame) == "table" and type(frame.trainingPoints) == "table" and frame.trainingPoints.text or nil
  local n = WFJ.Labels.show(SURFACE, "trainingPoints", points, nil, { only = POINTS_KEYS })
  for button in pairs(seen) do
    n = n + WFJ.Labels.show(SURFACE, rowKey(button) .. ".cost", button.alternateCost, nil, { only = COST_KEYS })
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

function Trainer.showStatic()
  return WFJ.Labels.showAll(STATIC, { { "train", Compat.get(SURFACE, "train") } })
end

-- The filter dropdown's button text (a record on its .Text, re-shown after each UpdateText). 1.60.1.70009
-- also writes it directly, FilterDropdown:SetText(SETTINGS or FILTERS) on each update (mainline/blizzard_trainerui.lua:
-- 464), so SetText is post-hooked on the instance too (once). → 1 | 0
local setTextHooked = setmetatable({}, { __mode = "k" })
function Trainer.showFilter()
  local frame = Compat.get(SURFACE, "frame")
  local dropdown = type(frame) == "table" and frame.FilterDropdown or nil
  if type(dropdown) == "table" and not setTextHooked[dropdown] and type(dropdown.SetText) == "function" then
    setTextHooked[dropdown] = true
    hooksecurefunc(dropdown, "SetText", function(self)
      if type(self.Text) == "table" then WFJ.Labels.show(SURFACE, "filter", self.Text) end
    end)
  end
  return WFJ.Labels.dropdown(SURFACE, "filter", dropdown)
end

function Trainer.release()
  return WFJ.Render.release(SURFACE)
end

-- Client names. Declared again at setup: a declare clears Compat's memo, which may hold `false` for a load-on-demand
-- name looked up before the addon loaded.
local function declare()
  Compat.declare(SURFACE, "frame", { "ClassTrainerFrame" })
  Compat.declare(SURFACE, "train", { "ClassTrainerTrainButton" })
  Compat.declare(SURFACE, "initService", { "ClassTrainerFrame_InitServiceButton" })
  Compat.declare(SURFACE, "updatePoints", { "ClassTrainerFrame_UpdateTrainingPoints" })
end

local hooked = false

-- The Blizzard_TrainerUI part: runs once the addon is loaded (now, or on its ADDON_LOADED).
function Trainer.setup()
  declare()
  Trainer.showStatic()
  if hooked then return false end
  local frame = Compat.get(SURFACE, "frame")
  if type(frame) ~= "table" then return false end
  hooked = true
  local function fn(key) return type(Compat.get(SURFACE, key)) == "function" end
  if fn("initService") then hooksecurefunc("ClassTrainerFrame_InitServiceButton", Trainer.onService) end
  if fn("updatePoints") then
    hooksecurefunc("ClassTrainerFrame_UpdateTrainingPoints", Trainer.onTrainingPoints)
  end
  if type(frame.HookScript) == "function" then frame:HookScript("OnHide", Trainer.release) end
  local train = Compat.get(SURFACE, "train")
  if type(train) == "table" then WFJ.HelpTooltip.register(train, { only = TRAIN_HELP_KEYS }) end
  if type(frame.trainingPoints) == "table" then
    WFJ.HelpTooltip.register(frame.trainingPoints, { only = POINTS_HELP_KEYS })
  end
  Trainer.showFilter()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init.
function Trainer.init()
  declare()
  return WFJ.LoadOnDemand.when(ADDON, Trainer.setup)
end
