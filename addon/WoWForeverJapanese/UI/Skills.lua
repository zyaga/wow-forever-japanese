-- UI/Skills.lua: the character window's skills panel (surface "skills", area "ui", ADR-016,
-- ADR-029). Camelot loads [Game]\SkillsFrame.lua|xml at login [verified: TOC blizzard_uipanels_game.toc:38–39,
-- 71–72]; it has no LEARN_SKILL_TEMPLATE, collapse-all, cancel or unlearn button (camelot/skillsframe.lua|xml). The
-- global SkillsFrame (skillsframe.xml:121) has a parentKey-only detail side pane, SkillsFrame.SkillDetailFrame (:169,
-- CharacterFrameSidePaneTemplate). Its Refresh is registered BY REFERENCE (skillsframe.lua:226), so it is not hooked;
-- the two methods it calls by method lookup are, on the instance (CharacterFrameSidePaneMixin is shared with other
-- panes):
-- - SetEmpty(SKILL_DETAIL_SELECT_PROMPT) writes EmptyText (skillsframe.lua:255; camelot/characterframe.lua:942–951).
-- - LayoutRows runs after the weapon-skill rows were added (skillsframe.lua:283–316): category rows
--   WEAPON_SKILL_DETAIL_SAME_LEVEL_HEADER / _BOSS_HEADER and wrapped rows WEAPON_SKILL_DETAIL_SAME_LEVEL[_RANGED] /
--   _BOSS[_RANGED] (percent values verbatim). Rows come from detail.rowPools (characterframe.lua:841–845, 882–929);
--   the active pool objects are walked after each layout, each row's record keyed by the row widget itself (a pooled
--   row has no id of its own; never by its position). A wrapped row was sized from the English
--   (characterframe.lua:901–907), so a longer Japanese grows it and lays the pane out again (grow only).
-- - The list's category headers: SkillsFrame.ScrollBox builds a SkillsHeaderTemplate row for each
--   top-level header and SkillsHeaderMixin:Initialize writes its `.Name` with the header's name from
--   C_SkillInfo.GetSkillLineInfo (skillsframe.lua:127–141, 197–213, 321–325; skillsframe.xml:3–25). The name is
--   client data: two of them read exactly as a GlobalString ("Weapon Skills" (STAT_CATEGORY_WEAPON_SKILLS) and
--   "Languages" (LANGUAGES_LABEL)), and every header is a SkillLineCategory name ("Armor Proficiencies", "Class
--   Skills", "Professions", "Secondary Skills": the SkillCategory:* family, ADR-042); only those are shown.
--   Followed with ScrollUtil.AddInitializedFrameCallback (after the element initializer), keyed by the row widget.
--   A skill's row and a sub-header (SkillsEntryTemplate: the name is `.Content.Name`, skillsframe.lua:372, 477–478)
--   hold a skill name: that FontString is forbidden when the row is first seen.
-- - The window title "Skills" is NOT this frame's: SkillsFrame is a child of CharacterFrame (skillsframe.xml:121) and
--   CharacterFrameMixin:UpdateTitle writes CharacterFrame:SetTitle(characterFrameDisplayInfo[activeSubframe].title);
--   SKILLS, REPUTATION, CURRENCY, PVP, STATISTICS, or the player's name (characterframe.lua:254–258;
--   characterframeconstants.lua:9–34). That one widget belongs to UI/Character, which renders the pane titles (SKILLS
--   among them) and keeps the name title English.
-- - The detail pane's description: SetDescription(description) writes the Description ScrollingFont
--   (skillsframe.lua:273; characterframe.lua:873–885) with the SkillLine table's text: the SkillLineDescription:*
--   family only.
-- Untouched: the pane title (the skill name, skillsframe.lua:270) and subtitle, the list rows (skill names, :325,
-- :372). Release on SkillsFrame's OnHide.
local _, WFJ = ...
local Skills = {}
WFJ.Skills = Skills

local SURFACE = "skills"
Skills.SURFACE = SURFACE
local Compat = WFJ.Compat

-- the detail pane's title (the skill name) and subtitle
Skills.NEVER_TOUCH = { "SkillsFrame.SkillDetailFrame.Title", "SkillsFrame.SkillDetailFrame.Subtitle" }

local EMPTY_ONLY = { only = { "SKILL_DETAIL_SELECT_PROMPT" } }
local DETAIL_ONLY = { only = { "WEAPON_SKILL_DETAIL_SAME_LEVEL_HEADER", "WEAPON_SKILL_DETAIL_BOSS_HEADER",
  "WEAPON_SKILL_DETAIL_SAME_LEVEL", "WEAPON_SKILL_DETAIL_SAME_LEVEL_RANGED", "WEAPON_SKILL_DETAIL_BOSS",
  "WEAPON_SKILL_DETAIL_BOSS_RANGED" } }
local HEADER_ONLY = { only = { "STAT_CATEGORY_WEAPON_SKILLS", "LANGUAGES_LABEL" } }
Skills.CAMELOT_KEYS = { empty = EMPTY_ONLY.only, detail = DETAIL_ONLY.only, header = HEADER_ONLY.only }

local function get(name) return Compat.get(SURFACE, name) end

local function declareAll()
  for _, name in ipairs(Skills.NEVER_TOUCH) do Compat.declare(SURFACE, name, { name }) end
  Compat.declare(SURFACE, "frame", { "SkillsFrame" })
  Compat.declare(SURFACE, "detail", { "SkillsFrame.SkillDetailFrame" })
  Compat.declare(SURFACE, "emptyText", { "SkillsFrame.SkillDetailFrame.EmptyText" })
  Compat.declare(SURFACE, "listBox", { "SkillsFrame.ScrollBox" })
  Compat.declare(SURFACE, "scrollUtil", { "ScrollUtil" })
end

-- The detail pane's empty prompt, after SetEmpty. → 1 | 0
function Skills.onSetEmpty()
  local n = WFJ.Labels.show(SURFACE, "empty", get("emptyText"), nil, EMPTY_ONLY)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The detail pane's description, after SetDescription. → 1 | 0
function Skills.onDescription()
  local detail = get("detail")
  local fs, refit = WFJ.Labels.scrolling(type(detail) == "table" and detail.Description or nil)
  local n = WFJ.Labels.show(SURFACE, "description", fs, refit, WFJ.Labels.families("SkillLineDescription"))
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local rowKey = WFJ.Labels.keyer("detail.") -- a pooled detail row's record key

-- A wrapped row's refit: the client sized it from the English; a taller Japanese grows it and the pane is laid out
-- again (never shrunk: the English comes back at its own height on the next Refresh).
local refits = setmetatable({}, { __mode = "k" })
local function refitOf(row)
  local fn = refits[row]
  if fn then return fn end
  fn = function()
    local label, detail = row.Label, get("detail")
    if type(label) ~= "table" or type(label.GetStringHeight) ~= "function" or type(row.GetHeight) ~= "function"
        or type(row.SetHeight) ~= "function" then
      return
    end
    local h, now = label:GetStringHeight(), row:GetHeight()
    if type(h) ~= "number" or type(now) ~= "number" or h <= now then return end
    row:SetHeight(h)
    local content = type(detail) == "table" and detail.Content or nil
    if type(content) == "table" and type(content.Layout) == "function" then content:Layout() end
  end
  refits[row] = fn
  return fn
end

-- Every active detail row after LayoutRows. → the number of dictionary words
function Skills.onLayoutRows()
  local detail = get("detail")
  local pools = type(detail) == "table" and detail.rowPools or nil
  if type(pools) ~= "table" or type(pools.EnumerateActive) ~= "function" then return 0 end
  local seen, n = {}, 0
  for row in pools:EnumerateActive() do
    if type(row) == "table" and row.Label ~= nil then
      local key = rowKey(row)
      seen[key] = true
      n = n + WFJ.Labels.show(SURFACE, key, row.Label, refitOf(row), DETAIL_ONLY)
    end
  end
  local gone = {}
  for key in pairs(WFJ.SurfaceState.records(SURFACE)) do
    if key:find("^detail%.") and not seen[key] then gone[#gone + 1] = key end
  end
  for _, key in ipairs(gone) do WFJ.SurfaceState.drop(SURFACE, key) end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local headerKey = WFJ.Labels.keyer("header.") -- a pooled header row's record key

-- ScrollUtil callback for a list row: (owner, frame, elementData) on initialization, (frame, elementData) on
-- the existing-frames pass. Returns nothing (ForEachFrame stops at the first truthy return).
function Skills.onListRow(a, b, c)
  local row, data = a, b
  if a == Skills then row, data = b, c end
  if type(row) ~= "table" then return end
  local content = row.Content
  if type(content) == "table" then -- a skill or a sub-header: its name is never ours
    WFJ.Labels.forbid(content.Name)
    return
  end
  if type(data) == "table" and data.isHeader == false then return end
  WFJ.Labels.show(SURFACE, headerKey(row), row.Name, nil, WFJ.Labels.familiesWith(HEADER_ONLY.only, "SkillCategory"))
  WFJ.Render.updateBanner(SURFACE)
end

function Skills.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Skills.init()
  declareAll()
  if hooked then return false end
  hooked = true
  -- at login, no load-on-demand wait
  local frame, detail = get("frame"), get("detail")
  if type(detail) == "table" then
    if type(detail.SetEmpty) == "function" then hooksecurefunc(detail, "SetEmpty", Skills.onSetEmpty) end
    if type(detail.LayoutRows) == "function" then hooksecurefunc(detail, "LayoutRows", Skills.onLayoutRows) end
    if type(detail.SetDescription) == "function" then
      hooksecurefunc(detail, "SetDescription", Skills.onDescription)
    end
    Skills.onSetEmpty()
    Skills.onLayoutRows()
    Skills.onDescription()
  end
  local util, box = get("scrollUtil"), get("listBox")
  if type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" and type(box) == "table" then
    util.AddInitializedFrameCallback(box, Skills.onListRow, Skills, true)
  end
  if type(frame) == "table" and type(frame.HookScript) == "function" then frame:HookScript("OnHide", Skills.release) end
  return true
end
