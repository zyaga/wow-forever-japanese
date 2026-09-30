-- UI/Tutorial.lua: the tutorial popup on Forever (surface "tutorial", area "ui", ADR-016).
-- Blizzard_FrameXML loads the mainline tutorialframe.lua|xml at login on camelot (blizzard_framexml.toc:32–33).
-- TUTORIAL_TRIGGER → TutorialFrame_NewTutorial → TutorialFrame_Update(id) (tutorialframe.lua:227–229, 359–606).
-- Only the ids DISPLAY_DATA lists draw (17 whispers, 18 grouping, 22 friends, 27 fatigue, 28 swimming, 37 broken items,
-- 46 raids, 52 companions; :119–182); any other id is flagged and returns (:365–368).
-- Update clears the body (TutorialFrame_ClearTextures: SetFontObject(GameFontNormal), SetText("")), then writes
-- TutorialFrameText:SetText(TUTORIAL<id>[_<RACE>][_<CLASS>]) (:446–455, 494) and
-- TutorialFrameTitle:SetText(TUTORIAL_TITLE<id>…) (:481–487, 498), and shows the frame. It is post-hooked by global
-- name, so our write follows the client's on every update (a new tutorial, Prev / Next, DISPLAY_SIZE_CHANGED).
-- The frame's height is fixed per tutorial (tileHeight, :440–441), sized for the English. The body sits in a
-- ScrollFrame whose scroll child is a fixed 1×1 frame (tutorialframe.xml:126–140), so the client's text never
-- scrolls: a Japanese body taller than the box would be clipped. The refit gives the scroll child the body's height,
-- so a longer body scrolls; the client's 1 is put back before each update and on release [the scroll bar's
-- appearance is an in-game check].
-- The Okay button's text is CLOSE (ButtonText, xml:180–191); the Prev / Next buttons carry unnamed FontStrings PREV /
-- NEXT (xml:202, 227), found by their English. Release on TutorialFrame's OnHide.
-- The popup takes the keyboard while shown (OnKeyDown, tutorialframe.xml:267; TutorialFrame_OnKeyDown returns true,
-- :273–302), and then MODIFIER_STATE_CHANGED does not arrive: in game, Alt did nothing until the popup
-- closed. So while it is shown its OnUpdate re-polls the modifier (Modifier.refresh: one poll, a change only on a
-- change), the way UI/RevealBinding watches a bound key.
local _, WFJ = ...
local Tutorial = {}
WFJ.Tutorial = Tutorial

local SURFACE = "tutorial"
Tutorial.SURFACE = SURFACE
local Compat = WFJ.Compat

Tutorial.NEVER_TOUCH = {}

-- The live tutorial ids (tutorialframe.lua:119–182); nothing else is ever read off the popup.
-- Named in full: six of the titles are owned keys (UIStrings.OWN), which answer only a list that names them.
local TITLES = { "TUTORIAL_TITLE17", "TUTORIAL_TITLE18", "TUTORIAL_TITLE22", "TUTORIAL_TITLE27", "TUTORIAL_TITLE28",
  "TUTORIAL_TITLE37", "TUTORIAL_TITLE46", "TUTORIAL_TITLE52" }
local BODIES = { "TUTORIAL17", "TUTORIAL18", "TUTORIAL22", "TUTORIAL27", "TUTORIAL28", "TUTORIAL37", "TUTORIAL46",
  "TUTORIAL52" }
local ONLY_TITLE = { only = TITLES }
local ONLY_BODY = { only = BODIES }
local ONLY_CLOSE = { only = { "CLOSE" } }

local CANDIDATES = {
  frame = { "TutorialFrame" },
  title = { "TutorialFrameTitle" },
  text = { "TutorialFrameText" },
  okay = { "TutorialFrameOkayButton" },
  prev = { "TutorialFramePrevButton" },
  next = { "TutorialFrameNextButton" },
  scroll = { "TutorialFrameTextScrollFrame" },
  child = { "TutorialFrameTextScrollChildFrame" },
  update = { "TutorialFrame_Update" },
}

local function get(key) return Compat.get(SURFACE, key) end

-- The scroll child's height: the body's (a longer Japanese body scrolls), or the client's 1.
local function setChildHeight(h)
  local child, scroll = get("child"), get("scroll")
  if type(child) ~= "table" or type(child.SetHeight) ~= "function" then return end
  child:SetHeight(h)
  if type(scroll) == "table" and type(scroll.UpdateScrollChildRect) == "function" then
    scroll:UpdateScrollChildRect()
  end
end

local function refit()
  local text = get("text")
  if type(text) ~= "table" then return end
  local measure = text.GetStringHeight or text.GetHeight
  if type(measure) ~= "function" then return end
  setChildHeight(math.max(1, measure(text) or 0))
end
Tutorial.refit = refit

-- The TutorialFrame_Update post-hook: the client has written this tutorial. → the number of dictionary words found.
function Tutorial.onUpdate()
  WFJ.Render.forget(SURFACE)
  setChildHeight(1) -- the client's own (xml:135–136); a body with a record re-sizes it in the refit
  local n = WFJ.Labels.show(SURFACE, "text", get("text"), refit, ONLY_BODY) -- only the body re-sizes the child
  local items = {
    { "title", get("title"), ONLY_TITLE },
    { "okay", get("okay"), ONLY_CLOSE },
  }
  local prev = WFJ.Labels.region(get("prev"), "PREV")
  if prev then items[#items + 1] = { "prev", prev, { only = { "PREV" } } } end
  local nxt = WFJ.Labels.region(get("next"), "NEXT")
  if nxt then items[#items + 1] = { "next", nxt, { only = { "NEXT" } } } end
  return n + WFJ.Labels.showAll(SURFACE, items)
end

function Tutorial.release()
  local n = WFJ.Render.release(SURFACE)
  setChildHeight(1)
  return n
end

-- The popup's OnUpdate (runs only while it is shown): the reveal key, which no event reports while it has the keyboard.
function Tutorial.poll()
  return WFJ.Modifier.refresh()
end

local hooked = false

-- Called by Main after Compat.init. → true when the popup was hooked now; false when it is missing or already hooked.
function Tutorial.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  local frame = get("frame")
  if type(frame) ~= "table" or type(get("update")) ~= "function" then return false end
  hooked = true
  hooksecurefunc("TutorialFrame_Update", Tutorial.onUpdate)
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnHide", Tutorial.release)
    frame:HookScript("OnUpdate", Tutorial.poll)
  end
  return true
end
