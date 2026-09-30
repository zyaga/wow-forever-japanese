-- UI/SettingsTutorials.lua: the Options window's two "About …" windows on Forever (surface "settingstutorials", area
-- "ui", ADR-016). Blizzard_SettingsDefinitions_Frame (a login addon on camelot) defines them; each opens from
-- its category's tutorial button in the Options window (Settings.AssignTutorialToCategory):
--   NamePlatesTutorial (blizzard_settingsdefinitions_frame/nameplates.xml:35; opened at nameplates.lua:338): title
--     NAMEPLATES_LABEL (SetTitle in OnLoad, nameplates.lua:878), four XML FontStrings UNIT_NAMEPLATES_TUTORIAL_*
--     (nameplates.xml:54–87);
--   PingSystemTutorial (pingsystem.xml:6; opened at pingsystem.lua:9, 137): title PING_SYSTEM_TUTORIAL_LABEL
--     (SetTitle in OnLoad, pingsystem.lua:157), the Tutorial1–4 headers and bodies PING_SYSTEM_TUTORIAL_*
--     (pingsystem.xml:43–137).
-- Everything is written at load and never rewritten, so each frame is walked on its OnShow with UI/LabelTree.lua,
-- restricted to the Options window's keys (UI/SettingsKeys.lua). The title goes through Labels.title (a SetTitle
-- window); the walk skips TitleContainer so the title has one record. The macro line "/ping [@target] Ping Type" is
-- typed syntax and is not a key: it stays as written.
local _, WFJ = ...
local SettingsTutorials = {}
WFJ.SettingsTutorials = SettingsTutorials

local SURFACE = "settingstutorials"
SettingsTutorials.SURFACE = SURFACE
local Compat = WFJ.Compat

SettingsTutorials.NEVER_TOUCH = {}

local FRAMES = { "NamePlatesTutorial", "PingSystemTutorial" }
local CANDIDATES = {}
for _, name in ipairs(FRAMES) do CANDIDATES[name] = { name } end

local KEYS = WFJ.LabelTree.set(WFJ.SettingsKeys and WFJ.SettingsKeys.options)
local ONLY = { only = KEYS }

local function get(key) return Compat.get(SURFACE, key) end

local titleKey = setmetatable({}, { __mode = "k" }) -- frame → its title's record key ("title.<frame name>")

-- One tutorial window's title and labels. → the number of dictionary words found.
function SettingsTutorials.show(frame)
  if type(frame) ~= "table" then return 0 end
  local title = frame.TitleContainer
  local n = WFJ.Labels.title(SURFACE, frame, ONLY, titleKey[frame] or "title")
  return n + WFJ.LabelTree.show(SURFACE, frame, { only = KEYS, skip = function(f) return f == title end })
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init. → true when at least one window was found.
function SettingsTutorials.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  local found = false
  for _, name in ipairs(FRAMES) do
    local frame = get(name)
    if type(frame) == "table" and type(frame.HookScript) == "function" then
      found = true
      titleKey[frame] = "title." .. name
      frame:HookScript("OnShow", SettingsTutorials.show)
      SettingsTutorials.show(frame)
    end
  end
  hooked = found
  return found
end
