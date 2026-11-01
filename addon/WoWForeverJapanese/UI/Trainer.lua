-- UI/Trainer.lua: the class / profession trainer's fixed words (surface "trainer", area "ui",
-- ADR-016). Blizzard_TrainerUI is load-on-demand and loads its [Family] = mainline files on camelot, plus camelot's own
-- Blizzard_TrainerUI_Camelot.lua [verified: Forever blizzard_trainerui.toc:6–9], so everything here is set up through
-- WFJ.LoadOnDemand.when("Blizzard_TrainerUI", …).
-- - Static (XML text=): ClassTrainerTrainButton TRAIN (xml:231). "trainer.static".
-- - The services are ScrollBox rows (ClassTrainerSkillButtonTemplate, no global names), each written by the global
--   ClassTrainerFrame_InitServiceButton(button, elementData) (lua:602–769): called by global name from the view's
--   initializer, ClassTrainerFrame_Update (the step button) and ClassTrainer_SetSelection [verified:
--   mainline/blizzard_trainerui.lua:165, 512, 823, 838], so one post-hook sees every row:
--   button.nameSubText = PARENS_TEMPLATE:format(subtext) (lua:686), restricted to PARENS_TEMPLATE, whose argument must
--     be a dictionary word (ARGS);
--   button.subText = REQUIRES_LABEL .. " " .. <requirements> or ITEM_SPELL_KNOWN (lua:674–684): the `list` label form
--     (Core/UIStrings) shows "必要:" and each item that is a requirement template in Japanese;
--   button.alternateCost = TRAINING_POINTS_ABBREV:format(cost) on a pet trainer (lua:717), re-written by
--     ClassTrainerFrame_UpdateTrainingPoints (lua:587–600), which also writes trainingPoints.text = TRAINING_POINTS
--     (xml:244–253), post-hooked too.
--   The writer ends with button:UpdateNameWidth() (lua:732), before the post-hook runs. camelot's version
--     (blizzard_trainerui_camelot.lua:13–36) sizes nameSubText to the width of the text it holds then, word wrap off,
--     or hides it when it does not fit beside the name and the cost (the cost's width counts). So after the subtext
--     or the cost changes language it is called again (the records' refit), on apply and on restore.
-- - The filter dropdown's button text: SetSelectionText returns FILTER and the Menu system writes it into
--   FilterDropdown.Text in UpdateText (xml:217; Blizzard_Menu/MenuTemplates.lua:530–540, 612–644):
--   WFJ.Labels.dropdown; on 1.60.1.70009 also FilterDropdown:SetText(SETTINGS or FILTERS) (lua:451).
--   The menu's Available / Unavailable / Already Known entries are popup entries (the menu system's).
-- Help tooltips, walked by UI/HelpTooltip on registered owners:
--   ClassTrainerTrainButton, disabled for a third primary profession: SetOwner(ClassTrainerTrainButton),
--     GameTooltip_AddNormalLine(TRAINER_CANNOT_EXCEED_MAX_PROFESSIONS), Show (lua:300–318), restricted to that key;
--   the pet trainer's points frame: SetOwner(self), SetText(TRAINING_POINTS_TUTORIAL), Show (xml:255–259): an
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
local ROW_REQUIREMENT_KEYS = { REQUIRES_LABEL = true, ITEM_SPELL_KNOWN = true } -- (lua:674–677)
local COST_KEYS = { TRAINING_POINTS_ABBREV = true }
local POINTS_KEYS = { TRAINING_POINTS = true }
local TRAIN_HELP_KEYS = { "TRAINER_CANNOT_EXCEED_MAX_PROFESSIONS" }
local POINTS_HELP_KEYS = { "TRAINING_POINTS_TUTORIAL" }

-- Widgets this module must never record: none by name (row names are pooled `button.name`, never read).
Trainer.NEVER_TOUCH = {}

-- A stable record key per ScrollBox service button (buttons are pooled and re-initialized).
local rowKey = WFJ.Labels.keyer("svc") -- a pooled row's record key
local seen = setmetatable({}, { __mode = "k" }) -- every service button shown, for the points refresh
local refits = setmetatable({}, { __mode = "k" }) -- button → its UpdateNameWidth refit (one per button)

-- The refit of a button's subtext and cost records: camelot's UpdateNameWidth again, for the text now shown. nil on a
-- client without it.
local function refitOf(button)
  if type(button.UpdateNameWidth) ~= "function" then return nil end
  local fn = refits[button]
  if not fn then
    fn = function() pcall(button.UpdateNameWidth, button) end
    refits[button] = fn
  end
  return fn
end

-- hooksecurefunc target for ClassTrainerFrame_InitServiceButton: one service button's subtext,
-- requirements and pet cost. → the number of words found
function Trainer.onService(button)
  if type(button) ~= "table" then return 0 end
  local k = rowKey(button)
  seen[button] = true
  local refit = refitOf(button)
  local n = WFJ.Labels.show(SURFACE, k .. ".sub", button.nameSubText, refit, { only = SUBTEXT_KEYS })
    + WFJ.Labels.show(SURFACE, k .. ".req", button.subText, nil, { only = ROW_REQUIREMENT_KEYS })
    + WFJ.Labels.show(SURFACE, k .. ".cost", button.alternateCost, refit, { only = COST_KEYS })
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target for ClassTrainerFrame_UpdateTrainingPoints: the pet trainer's points label, then
-- every service button seen so far (their pet costs were re-written). → the number of words found
function Trainer.onTrainingPoints()
  local frame = Compat.get(SURFACE, "frame")
  local points = type(frame) == "table" and type(frame.trainingPoints) == "table" and frame.trainingPoints.text or nil
  local n = WFJ.Labels.show(SURFACE, "trainingPoints", points, nil, { only = POINTS_KEYS })
  for button in pairs(seen) do
    n = n + WFJ.Labels.show(SURFACE, rowKey(button) .. ".cost", button.alternateCost, refitOf(button),
      { only = COST_KEYS })
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

function Trainer.showStatic()
  return WFJ.Labels.showAll(STATIC, { { "train", Compat.get(SURFACE, "train") } })
end

-- The filter dropdown's button text (a record on its .Text, re-shown after each UpdateText). 1.60.1.70009
-- also writes it directly, FilterDropdown:SetText(SETTINGS or FILTERS) on each update (mainline/blizzard_trainerui.lua:
-- 451), so SetText is post-hooked on the instance too (once). → 1 | 0
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
