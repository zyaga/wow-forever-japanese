-- UI/Alerts.lua: the alert toasts ("You Won!", "New Recipe Learned!", "Achievement Earned") on Forever (surface
-- "alerts", area "ui", ADR-016). Blizzard_FrameXML loads mainline/alertframes.lua|xml,
-- mainline/alertframesystems.lua|xml and camelot/alertframesystemsoverride.lua on camelot. Every alert (queued or
-- simple) is a pooled frame set up by its sub-system's setUpFunction and then handed to
-- AlertContainerMixin:AddAlertFrame, which calls the GLOBAL AlertFrame_ShowNewAlert(frame) by name
-- (alertframes.lua:173–198, 461–468, 890–893). The set-up functions are captured by reference when the sub-systems
-- are created (alertframesystems.lua:7–30, 429 …), so they cannot be hooked; the one global every alert passes through
-- after its text is written can. The hook walks the alert's fixed label fields (parentKeys from
-- alertframesystems.xml) and nothing else:
--   Label           YOU_WON_LABEL / YOU_RECEIVED_LABEL / YOU_EARNED_LABEL / YOU_RECEIVED and the other loot-toast
--                   labelText words (alertframesystems.lua:464–476, 541; xml:883, 938, 1004, 2671)
--   Unlocked        ACHIEVEMENT_UNLOCKED / GUILD_ACHIEVEMENT_UNLOCKED (lua:347, 371), ACHIEVEMENT_PROGRESSED,
--                   MONTHLY_ACTIVITIES_PROGRESSED (xml:358, 2857)
--   Title           NEW_RECIPE_LEARNED_TITLE / UPGRADED_RECIPE_LEARNED_TITLE (lua:1011), LEVEL_UP_FEATURE2 (:1052), the
--                   garrison / store / digsite titles (xml:1297, 1434, 1537, 1756, 1970, 2162; lua:905–907, 951)
--   TitleText       LOOTUPGRADEFRAME_TITLE "%s Upgrade!" (lua:613; %s is an item-quality word)
--   completionText  DUNGEON_COMPLETED (xml:97) · ToastText WORLD_QUEST_COMPLETE / TOAST_OBJECTIVE_COMPLETE (lua:1114)
--   HeaderLabel GUILD_RENAME_TOAST_LABEL · CollectedLabel YOU_COLLECTED_LABEL · CompletedLabel
--   ENDEAVOR_TASK_COMPLETED · Description YOU_EARNED_LABEL / BLIZZARD_STORE_PURCHASE_COMPLETE_DESC · Rare
--   GARRISON_MISSION_RARE · Amount MERCHANT_HONOR_POINTS "%d Honor" (lua:655)
-- Never walked: Name / ItemName / any other field. An alert's Name holds an item, an achievement, a recipe or a
-- follower; the three dictionary forms Blizzard also writes there ("%s Completed", "%s Specializations", "Research
-- Complete": lua:767, 1053; xml:2167) are name-shaped and could rewrite a real name ending in the same words, so
-- they stay English (names stay in English).
-- Not rendered: GARRISON_CACHE / TRADERS_CACHE, the Label of a currency loot toast (lua:468, 476), which name the
-- cache the currency came from ("Garrison Cache", "Trader's Cache": names stay in English); the six labels with no
-- parentKey (GUILD_CHALLENGE_LABEL, SCENARIO_INVASION_COMPLETE, SCENARIO_COMPLETED, LEGENDARY_ITEM_LOOT_LABEL,
-- GARRISON_MISSION_ADDED_TOAST1 / 2: xml:497, 708, 770, 2553, 1643, 1655). They could only be found by matching
-- text across all of an alert's regions, and those regions include the name fields: a name that reads the same
-- would be rewritten, and names stay in English.
-- Which of these Forever ever raises is the server's business (loot rolls, recipes and achievements are the likely
-- ones); a label that never appears costs nothing. Records are keyed by widget (pooled frames), never by position.
-- The loot toast's ITEM_UPGRADED_LABEL (its "Upgraded" labelText, alertframesystems.lua:466) joins Label;
-- the one key-only exception to "Name is never walked": a recipe toast (the alert carries tradeSkillID) writes Name
-- as TRADESKILL_RECIPE_LEVEL_RECIPE_FORMAT "%s (Rank %i)" when the recipe has a level, optionally followed by " " and
-- a star texture (lua:1000–1016). Only that template (ONLY: asked by key), the recipe's name kept as `text`, the
-- texture kept; a plain recipe name matches nothing and stays as written.
-- The achievement toast (ADR-042) (AchievementAlertFrame_SetUp, alertframesystems.lua:315–325: the frame with
-- a Shield and an Unlocked label): its Name is the achievement's title, matched against the AchievementTitle
-- family only, so an item, recipe or follower name on any other alert is never read.
-- The event toasts (the level-up banner). EventToastManagerFrame:DisplayToast takes the next toastInfo from
-- C_EventToastManager, acquires a pooled toast and calls toast:Setup(toastInfo), which writes Title / SubTitle
-- (Contents.Title / Contents.SubTitle on the weekly-reward kinds) from the client's own text, and a scenario toast's
-- Description (EVENT_TOAST_*_DESCRIPTION) (blizzard_framexml/eventtoastmanager.lua:327–365, 490–492, 623–626,
-- 658–661). A post-hook on the frame's DisplayToast walks the displayed toast's title fields, each restricted to the
-- level-up words [unverified: that the client's level-up toast is LEVEL_GAINED "Level %d" / LEVEL_UP_YOU_REACHED;
-- the in-game checklist]; any other toast's title (a scenario, a zone) matches none of them and stays as written.
local _, WFJ = ...
local Alerts = {}
WFJ.Alerts = Alerts

local SURFACE = "alerts"
Alerts.SURFACE = SURFACE
local Compat = WFJ.Compat

Alerts.NEVER_TOUCH = {}

local CANDIDATES = { show = { "AlertFrame_ShowNewAlert" }, toasts = { "EventToastManagerFrame" } }

local FIELDS = {
  Label = { only = { "YOU_WON_LABEL", "YOU_RECEIVED_LABEL", "YOU_EARNED_LABEL", "YOU_RECEIVED", "ITEM_UPGRADED_LABEL",
    "AZERITE_EMPOWERED_ITEM_LOOT_LABEL", "CONDUIT_ITEM_LOOT_LABEL", "CORRUPTED_ITEM_LOOT_LABEL" } },
  Unlocked = { only = { "ACHIEVEMENT_UNLOCKED", "GUILD_ACHIEVEMENT_UNLOCKED", "ACHIEVEMENT_PROGRESSED",
    "MONTHLY_ACTIVITIES_PROGRESSED" } },
  Title = { only = { "NEW_RECIPE_LEARNED_TITLE", "UPGRADED_RECIPE_LEARNED_TITLE", "LEVEL_UP_FEATURE2",
    "ARCHAEOLOGY_DIGSITE_COMPLETE_TOAST_FRAME_TITLE", "BLIZZARD_STORE_PURCHASE_COMPLETE", "GARRISON_UPDATE",
    "GARRISON_MISSION_COMPLETE", "GARRISON_FOLLOWER_ADDED_TOAST", "GARRISON_SHIPYARD_FOLLOWER_ADDED_TOAST",
    "GARRISON_SHIPYARD_FOLLOWER_ADDED_UPGRADED_TOAST", "GARRISON_TALENT_ORDER_ADVANCEMENT",
    "CYPHER_RESEARCH_TOAST" } },
  TitleText = { only = { "LOOTUPGRADEFRAME_TITLE" } },
  completionText = { only = { "DUNGEON_COMPLETED" } },
  ToastText = { only = { "WORLD_QUEST_COMPLETE", "TOAST_OBJECTIVE_COMPLETE" } },
  HeaderLabel = { only = { "GUILD_RENAME_TOAST_LABEL" } },
  CollectedLabel = { only = { "YOU_COLLECTED_LABEL" } },
  CompletedLabel = { only = { "ENDEAVOR_TASK_COMPLETED" } },
  Description = { only = { "YOU_EARNED_LABEL", "BLIZZARD_STORE_PURCHASE_COMPLETE_DESC" } },
  Rare = { only = { "GARRISON_MISSION_RARE" } },
  Amount = { only = { "MERCHANT_HONOR_POINTS" } },
}

local widgetKey = WFJ.Labels.keyer("label.") -- one record per pooled label widget
local RECIPE_LEVEL = { "TRADESKILL_RECIPE_LEVEL_RECIPE_FORMAT" }

-- A recipe toast's Name (see the header). → 1 | 0
local function showRecipeName(name)
  if type(name) ~= "table" or type(name.GetText) ~= "function" then return 0 end
  local recKey = widgetKey(name)
  local text = name:GetText()
  local rec = WFJ.SurfaceState.get(SURFACE, recKey)
  if rec and rec.fs == name and rec.applied ~= nil and rec.applied == text then return 1 end -- still ours
  local head, star = (type(text) == "string" and text or ""):match("^(.-)( |T[^|]*|t)$")
  local part = WFJ.Labels.part(head or text, RECIPE_LEVEL)
  return WFJ.Labels.showArgs(SURFACE, recKey, name, part and part.key,
    part and { form = "seq", parts = { part, star or "" } })
end

-- The event toast's text fields (see the header)
local TOAST_TITLE = { only = { "LEVEL_GAINED", "LEVEL_UP_YOU_REACHED" } }
local TOAST_FIELDS = { Title = TOAST_TITLE, SubTitle = TOAST_TITLE,
  Description = { only = { "EVENT_TOAST_EXPANDED_DESCRIPTION", "EVENT_TOAST_NOT_EXPANDED_DESCRIPTION" } } }

-- hooksecurefunc target (AlertFrame_ShowNewAlert): `alert` is the pooled alert frame, its text already written.
-- → the number of dictionary words found.
function Alerts.onShowAlert(alert)
  if type(alert) ~= "table" then return 0 end
  local n = 0
  for field, opts in pairs(FIELDS) do
    local widget = alert[field]
    if type(widget) == "table" then n = n + WFJ.Labels.show(SURFACE, widgetKey(widget), widget, nil, opts) end
  end
  if alert.tradeSkillID ~= nil then n = n + showRecipeName(alert.Name) end
  if type(alert.Shield) == "table" and alert.Unlocked ~= nil and type(alert.Name) == "table" then -- achievement
    n = n + WFJ.Labels.show(SURFACE, widgetKey(alert.Name), alert.Name, nil, WFJ.Labels.families("AchievementTitle"))
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (EventToastManagerFrame:DisplayToast): the toast now shown, its text written. → words found
function Alerts.onToast(manager)
  local toast = type(manager) == "table" and manager.currentDisplayingToast or nil
  if type(toast) ~= "table" then return 0 end
  local n = 0
  for _, host in ipairs({ toast, type(toast.Contents) == "table" and toast.Contents or nil }) do
    for field, opts in pairs(TOAST_FIELDS) do
      local widget = host[field]
      if type(widget) == "table" then n = n + WFJ.Labels.show(SURFACE, widgetKey(widget), widget, nil, opts) end
    end
  end
  return n
end

local hooked = false

-- Called by Main after Compat.init.
function Alerts.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  if type(Compat.get(SURFACE, "show")) ~= "function" then return false end
  hooked = true
  hooksecurefunc("AlertFrame_ShowNewAlert", Alerts.onShowAlert)
  local toasts = Compat.get(SURFACE, "toasts")
  if type(toasts) == "table" and type(toasts.DisplayToast) == "function" then
    hooksecurefunc(toasts, "DisplayToast", Alerts.onToast)
  end
  return true
end
