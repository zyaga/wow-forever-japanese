-- UI/Raid.lua: the social window's raid panel, the saved-instance list and the raid roster (surface "raid", area
-- "ui", ADR-016).
-- Blizzard_RaidFrame and Blizzard_RaidUI load their [Family] = mainline files on camelot [verified: Forever
-- blizzard_raidframe.toc:7–8, blizzard_raidui.toc:6–7], and the camelot friends frame keeps the RaidFrame tab
-- (blizzard_friendsframe/camelot/friendsframe.lua:55, 74–89; the mainline social view is not used there). The
-- RaidFrame toc has no LoadOnDemand, so its frames exist before this addon loads [verified: blizzard_raidframe/
-- mainline/raidframe.xml / .lua]:
--   static labels (XML text=): Convert To Raid / Raid Info; the description is a ScrollingFont
--     (RaidFrameNotInRaid.ScrollingDescription, xml:182–194, lua:37): its FontString is
--     ScrollBox.FontStringContainer.FontString (blizzard_sharedxml/shared/scroll/scrolltemplates.lua:337–345); after
--     our write the container is re-heighted like ScrollingFontMixin:SetText does (lua:347–358);
--   the raid-info title is RaidInfoFrame.Header (DialogHeaderTemplate, textString RAID_INFORMATION, xml:260–264);
--   the column labels are Frames with a .text FontString (INSTANCE, LOCK_EXPIRE; xml:3–37, 265–286);
--   "All <assistant icon>" carries texture markup and stays English (curation rule).
-- Saved-instance rows are ScrollBox rows (RaidInfoFrame.ScrollBox) built by an element initializer: a row's reset is
-- `button.reset` (lowercase; xml:56, lua:142–165), SecondsToTime(reset, true, nil, 3) or "|cff808080Expired|r"; its
-- difficulty RAID_INFO_WORLD_BOSS for a world boss (lua:164) or, for a saved instance, GetSavedInstanceInfo's
-- difficultyName (lua:157–158), a Difficulty row's English (restricted to that family), and the EXTENDED label
-- (xml:62). They are followed with
-- ScrollUtil.AddInitializedFrameCallback, Blizzard's own subscriber API; its iterateExisting pass calls the callback
-- as (frame, elementData) while later initializations call it as (owner, frame, elementData), so both shapes are
-- accepted. A reset of one unit matches its duration template; a two- or three-unit reset ("3 Days 4 Hr") matches no
-- single key and stays English. The row's name (an instance name) is never a candidate.
-- Tabs and buttons:
--   RaidParentFrameTab1 / Tab2 (RAID, LOOKING_FOR_RAID; mainline raidframe.xml:95–120 PanelTabButtonTemplate):
--     static, shown at init so each tab's OnShow → PanelTemplates_TabResize measures the Japanese
--     (shareduipaneltemplates.lua:264–266);
--   RaidInfoCancelButton (CLOSE, xml:321);
--   RaidInfoExtendButton (xml:309): RaidInfoFrame_UpdateButtons rewrites it with EXTEND_RAID_LOCK /
--     UNEXTEND_RAID_LOCK / REACTIVATE_RAID_LOCK (lua:247–268), called by global name (lua:193, 230): post-hooked,
--     restricted to those keys.
-- Blizzard_RaidUI is load-on-demand; its labels are shown through WFJ.LoadOnDemand.when: "Group N" (GROUP .. " " ..
-- id at the group frame's OnLoad, the `number` label form), the unnamed "Empty" region of every slot, and the
-- leader / assistant / main tank / main assist tooltips on each RaidGroupButtonN's Rank / Role icons
-- (blizzard_raidui.xml:100–153, 213–276); a Loot icon name resolves to nothing there and is skipped.
-- A class button's tooltip (RaidClassButton_OnEnter, blizzard_raidui.lua:121–142) is anchored to UIParent, so
-- it is walked once right after the client wrote it (post-hook → HelpTooltip.walkAs), restricted to the three buttons
-- whose title is a word: "Main Tank|cffffd200 (3)|r" (MAINTANK / MAINASSIST / PETS in the `binding` form, the count
-- kept). A class title ("Warrior (5)") and the member list (names) are no key of that set.
-- Never touched: RaidGroupButtonNClass (Blizzard passes self:GetText() back as the class of a pullout), nor the
-- roster's names and levels.
--
-- The Raid tab of the newer social window: SocialUIFrame.RaidFrame (RaidFrameSocialTemplate) and its side window
-- SocialUIFrame.RaidInfoFrame (SocialUIRaidInfoFrameTemplate; blizzard_socialui/mainline/socialui.lua:267–290,
-- 132–141). Set up whenever SocialUIFrame.RaidFrame exists, with or without the older panel:
--   static (XML text=, raidframesocialview.xml:129, 201, 224): RaidDescription, RaidInfoButton, ConvertToRaidButton;
--   AllAssistCheckButton.AllText: ALL_ASSIST_LABEL_SHORT inside the enabled or the grey colour, written again by
--     the button's own UpdateAvailable (raidframesocialview.lua:34–40), post-hooked; its tooltip's description and
--     not-leader error (:46–56);
--   after each UpdateContents (the view's own method, :244–294, post-hooked): every group's GroupNumberText
--     "Group %d" (:226–231; pooled, keyed by widget), and each roster button's LeaderIcon and RoleIcon as help
--     owners of their one-word tooltip (:106–114, 405–413). Nothing of a roster button is written: it is a secure
--     unit button from a secure pool, released and acquired again on every roster event, in combat too (:233,
--     244–249), so its name, level and class stay as the client writes them;
--   the saved-instance window: its two unnamed column labels INSTANCE and LOCK_EXPIRE
--     (raidinfoframesocialview.xml:91, 97), found by their English; ExtendButton after each UpdateButtons
--     (raidinfoframesocialview.lua:43–68), fitted to its text again as SetTextToFit does (blizzard_sharedxml/
--     secureuipaneltemplates.lua:83–92); its rows (SocialUIRaidInfoContentFrameTemplate, the same lowercase
--     parentKeys as the panel's rows, xml:7–25): the reset, "Expired" inside the grey the client wraps it in
--     (lua:88–98), the difficulty and the EXTENDED label as on the panel, and, while names are Japanese, the
--     instance's name. Nothing measures a row's text (each is one line with no wrap).
-- The role counts are numbers; the tab's disabled reason is UI/SocialUI's.
local _, WFJ = ...
local Raid = {}
WFJ.Raid = Raid

local SURFACE = "raid"
Raid.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
local Compat = WFJ.Compat

-- NUM_RAID_GROUPS, MEMBERS_PER_RAID_GROUP, MAX_RAID_MEMBERS [verified: Blizzard_FrameXMLBase/Shared/Constants.lua:1–3]
local GROUPS, SLOTS, MEMBERS = 8, 5, 40
local RESET_KEYS = { "RAID_INSTANCE_EXPIRES_EXPIRED", "DAYS_ABBR", "HOURS_ABBR", "MINUTES_ABBR" }
local DIFFICULTY_KEYS = { "RAID_INFO_WORLD_BOSS" } -- and the Difficulty family (difficultyOpts)
local EXTEND_KEYS = { "EXTEND_RAID_LOCK", "UNEXTEND_RAID_LOCK", "REACTIVATE_RAID_LOCK" }
local EXTENDED_KEYS = { "EXTENDED" }

-- key → candidate names.
local STATIC_NAMES = {
  description = { "RaidFrameNotInRaid.ScrollingDescription.ScrollBox.FontStringContainer.FontString" },
  convert = { "RaidFrameConvertToRaidButton" },
  allAssistLabel = { "RaidFrameAllAssistCheckButtonText" }, -- "All <assistant icon>" (raidframe.xml:155)
  info = { "RaidFrameRaidInfoButton" },
  infoHeader = { "RaidInfoFrame.Header" },
  instanceLabel = { "RaidInfoInstanceLabel" },
  idLabel = { "RaidInfoIDLabel" },
  cancel = { "RaidInfoCancelButton" },
  parentTab1 = { "RaidParentFrameTab1" },
  parentTab2 = { "RaidParentFrameTab2" },
}

-- The social window's view: key → candidate name and the keys it shows.
local VIEW, VIEW_INFO = "SocialUIFrame.RaidFrame", "SocialUIFrame.RaidInfoFrame"
local VIEW_LABELS = {
  description = { VIEW .. ".RaidDescription", { "RAID_DESCRIPTION" } },
  info = { VIEW .. ".RaidInfoButton", { "RAID_INFO" } },
  convert = { VIEW .. ".ConvertToRaidButton", { "CONVERT_TO_RAID" } },
}
local ALL_ASSIST = { wrapped = true, only = { "ALL_ASSIST_LABEL_SHORT" } }
local ALL_ASSIST_TIP = { only = { "ALL_ASSIST_DESCRIPTION", "ALL_ASSIST_NOT_LEADER_ERROR" } }
local GROUP_NUMBER = { only = { "GROUP_NUMBER" } }
local LEADER_TIP = { only = { "RAID_ASSISTANT", "RAID_LEADER" } }
local ROLE_TIP = { only = { "MAIN_TANK", "MAIN_ASSIST" } }
local VIEW_COLUMNS = { "INSTANCE", "LOCK_EXPIRE" }

local NEVER = {}
for i = 1, MEMBERS do
  for _, part in ipairs({ "Class", "Name", "Level" }) do NEVER[#NEVER + 1] = "RaidGroupButton" .. i .. part end
end
Raid.NEVER_TOUCH = NEVER

local function get(key) return Compat.get(SURFACE, key) end

-- A stable record key per ScrollBox row (rows are pooled and re-initialized).
local rowIds, nextRow = setmetatable({}, { __mode = "k" }), 0
local function rowKey(frame)
  local id = rowIds[frame]
  if not id then
    nextRow = nextRow + 1
    id = nextRow
    rowIds[frame] = id
  end
  return "ui.reset." .. id
end

-- The text widget of a declared name: a button as itself (Labels makes it a ButtonText), a frame holding a `.text` /
-- `.Text` FontString (the header frames) as that FontString, else itself when it has text. → widget | nil
local function textOf(w)
  if type(w) ~= "table" then return nil end
  if type(w.GetFontString) == "function" then return w end
  for _, field in ipairs({ "text", "Text" }) do
    local child = w[field]
    if type(child) == "table" and type(child.GetText) == "function" then return child end
  end
  if type(w.GetText) == "function" then return w end
  return nil
end

-- The scrolling description: re-height its container after our write, as ScrollingFontMixin:SetText does.
local function refitDescription()
  local notInRaid = Compat.resolve("RaidFrameNotInRaid")
  local sf = type(notInRaid) == "table" and notInRaid.ScrollingDescription or nil
  local box = type(sf) == "table" and sf.ScrollBox or nil
  local container = type(box) == "table" and box.FontStringContainer or nil
  local fs = type(container) == "table" and container.FontString or nil
  if type(fs) ~= "table" or type(fs.GetStringHeight) ~= "function" or type(container.SetHeight) ~= "function" then
    return
  end
  container:SetHeight(fs:GetStringHeight())
end

function Raid.showStatic()
  local items = {}
  for key in pairs(STATIC_NAMES) do items[#items + 1] = { "ui." .. key, textOf(get(key)) } end
  table.sort(items, function(a, b) return a[1] < b[1] end)
  local n = 0
  for _, item in ipairs(items) do
    local refit = item[1] == "ui.description" and refitDescription or nil
    n = n + WFJ.Labels.show(STATIC, item[1], item[2], refit)
  end
  WFJ.Render.updateBanner(STATIC)
  return n
end

-- hooksecurefunc target for RaidInfoFrame_UpdateButtons: the extend button's text. → 1 | 0
function Raid.showExtend()
  return WFJ.Labels.show(STATIC, "ui.extend", get("extend"), nil, { only = EXTEND_KEYS })
end

-- ScrollUtil callback: (owner, frame, elementData) on initialization, (frame, elementData) on the existing-frames pass.
-- Returns nothing: ScrollBoxListViewMixin:ForEachFrame stops at the first truthy return, so a count here would end the
-- existing-frames pass after one row (ScrollBoxListView.lua).
function Raid.onRow(a, b)
  local frame = a
  if a == Raid then frame = b end
  if type(frame) ~= "table" then return end
  local reset = frame.reset -- lowercase parentKey (mainline raidframe.xml:56)
  if type(reset) ~= "table" then return end
  local key = rowKey(frame)
  WFJ.Labels.show(SURFACE, key, reset, nil, { only = RESET_KEYS })
  if type(frame.difficulty) == "table" then
    WFJ.Labels.show(SURFACE, key .. ".difficulty", frame.difficulty, nil,
      WFJ.Labels.familiesWith(DIFFICULTY_KEYS, "Difficulty"))
  end
  if type(frame.extended) == "table" then
    WFJ.Labels.show(SURFACE, key .. ".extended", frame.extended, nil, { only = EXTENDED_KEYS })
  end
end

local groupKey, viewRowKey = WFJ.Labels.keyer("view.group."), WFJ.Labels.keyer("view.row.")

-- The view's fixed labels and the saved-instance window's column labels. → the number of dictionary words found
function Raid.showView()
  local items = {}
  for key, label in pairs(VIEW_LABELS) do
    items[#items + 1] = { "view." .. key, get("view." .. key), { only = label[2] } }
  end
  table.sort(items, function(a, b) return a[1] < b[1] end)
  for _, key in ipairs(VIEW_COLUMNS) do
    items[#items + 1] = { "view.column." .. key, WFJ.Labels.region(get("viewInfo"), key), { only = { key } } }
  end
  return WFJ.Labels.showAll(STATIC, items)
end

-- hooksecurefunc target (the view's AllAssistCheckButton:UpdateAvailable). → 1 | 0
function Raid.onViewAllAssist()
  return WFJ.Labels.show(STATIC, "view.allAssist", get("viewAllText"), nil, ALL_ASSIST)
end

-- hooksecurefunc target (the view's UpdateContents): the group headers, and the roster icons' tooltips. Only the
-- header's text is written; a roster button is read for its two icon frames and nothing else. → groups shown
function Raid.onViewContents()
  local view = get("view")
  if type(view) ~= "table" then return 0 end
  local n = 0
  for _, group in ipairs(type(view.groups) == "table" and view.groups or {}) do
    local fs = type(group) == "table" and group.GroupNumberText or nil
    if type(fs) == "table" then n = n + WFJ.Labels.show(SURFACE, groupKey(fs), fs, nil, GROUP_NUMBER) end
  end
  for _, player in ipairs(type(view.players) == "table" and view.players or {}) do
    if type(player) == "table" then
      if type(player.LeaderIcon) == "table" then WFJ.HelpTooltip.register(player.LeaderIcon, LEADER_TIP) end
      if type(player.RoleIcon) == "table" then WFJ.HelpTooltip.register(player.RoleIcon, ROLE_TIP) end
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- hooksecurefunc target (the saved-instance window's UpdateButtons): the extend button, fitted to its text again.
-- → 1 | 0
function Raid.onViewExtend()
  local button = get("viewExtend")
  local function refit()
    if type(button) == "table" and type(button.FitToText) == "function" then button:FitToText() end
  end
  return WFJ.Labels.show(STATIC, "view.extend", button, refit, { only = EXTEND_KEYS })
end

-- One pooled row of the view's saved-instance list: (owner, frame, elementData) on initialization, (frame,
-- elementData) on the existing-frames pass. Returns nothing (ForEachFrame stops on a truthy return).
function Raid.onViewRow(a, b)
  local frame = a
  if a == Raid then frame = b end
  if type(frame) ~= "table" or type(frame.reset) ~= "table" then return end
  local key = viewRowKey(frame)
  WFJ.Labels.show(SURFACE, key, frame.reset, nil, { wrapped = true, only = RESET_KEYS })
  if type(frame.difficulty) == "table" then
    WFJ.Labels.show(SURFACE, key .. ".difficulty", frame.difficulty, nil,
      WFJ.Labels.familiesWith(DIFFICULTY_KEYS, "Difficulty"))
  end
  if type(frame.extended) == "table" then
    WFJ.Labels.show(SURFACE, key .. ".extended", frame.extended, nil, { only = EXTENDED_KEYS })
  end
  -- an instance's or a world boss's name, maybe inside the grey of an expired lock
  if type(frame.name) == "table" then WFJ.NameLabels.wrapped(SURFACE, key .. ".name", frame.name) end
end

local CLASS_TIP = { only = { "MAINTANK", "MAINASSIST", "PETS" } }

-- hooksecurefunc target (RaidClassButton_OnEnter). → the number of dictionary lines
function Raid.onClassTooltip()
  return WFJ.HelpTooltip.walkAs(nil, CLASS_TIP)
end

local classHooked = false

-- Blizzard_RaidUI's labels, once the addon is present. → the number of dictionary words found.
function Raid.setupRaidUI()
  if not classHooked and type(Compat.resolve("RaidClassButton_OnEnter")) == "function" then
    classHooked = true
    hooksecurefunc("RaidClassButton_OnEnter", Raid.onClassTooltip)
  end
  WFJ.Labels.forbidNames(Raid.NEVER_TOUCH) -- the roster's widgets exist only now (Main's registration found none)
  local items = {}
  for g = 1, GROUPS do
    items[#items + 1] = { "ui.group" .. g, Compat.resolve("RaidGroup" .. g .. "Label"), { only = { "GROUP" } } }
    for s = 1, SLOTS do
      local slot = Compat.resolve("RaidGroup" .. g .. "Slot" .. s)
      items[#items + 1] = { "ui.empty" .. g .. "." .. s, WFJ.Labels.region(slot, "EMPTY") }
    end
  end
  for i = 1, MEMBERS do
    for _, part in ipairs({ "Rank", "Role", "Loot" }) do
      local owner = Compat.resolve("RaidGroupButton" .. i .. part)
      if type(owner) == "table" then WFJ.HelpTooltip.register(owner) end
    end
  end
  return WFJ.Labels.showAll(STATIC, items)
end

local hooked, viewHooked = false, false

-- The social window's view. → true when it was set up now
local function initView()
  Compat.declare(SURFACE, "view", { VIEW })
  Compat.declare(SURFACE, "viewInfo", { VIEW_INFO })
  Compat.declare(SURFACE, "viewAllAssist", { VIEW .. ".AllAssistCheckButton" })
  Compat.declare(SURFACE, "viewAllText", { VIEW .. ".AllAssistCheckButton.AllText" })
  Compat.declare(SURFACE, "viewExtend", { VIEW_INFO .. ".ExtendButton" })
  for key, label in pairs(VIEW_LABELS) do Compat.declare(SURFACE, "view." .. key, { label[1] }) end
  local view, info = get("view"), get("viewInfo")
  if viewHooked or type(view) ~= "table" then return false end
  viewHooked = true
  Raid.showView()
  local allAssist = get("viewAllAssist")
  if type(allAssist) == "table" then
    WFJ.HelpTooltip.register(allAssist, ALL_ASSIST_TIP)
    if type(allAssist.UpdateAvailable) == "function" then
      hooksecurefunc(allAssist, "UpdateAvailable", Raid.onViewAllAssist)
    end
  end
  Raid.onViewAllAssist()
  if type(view.UpdateContents) == "function" then hooksecurefunc(view, "UpdateContents", Raid.onViewContents) end
  Raid.onViewContents()
  if type(info) == "table" then
    if type(info.UpdateButtons) == "function" then hooksecurefunc(info, "UpdateButtons", Raid.onViewExtend) end
    Raid.onViewExtend()
    local util = get("scrollUtil")
    if type(info.ScrollBox) == "table" and type(util) == "table"
        and type(util.AddInitializedFrameCallback) == "function" then
      util.AddInitializedFrameCallback(info.ScrollBox, Raid.onViewRow, Raid, true)
    end
  end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init. → true when a panel was set up now
function Raid.init()
  Compat.declare(SURFACE, "frame", { "RaidFrame" })
  Compat.declare(SURFACE, "infoFrame", { "RaidInfoFrame" })
  Compat.declare(SURFACE, "allAssist", { "RaidFrameAllAssistCheckButton" })
  Compat.declare(SURFACE, "scrollUtil", { "ScrollUtil" })
  Compat.declare(SURFACE, "extend", { "RaidInfoExtendButton" })
  Compat.declare(SURFACE, "updateButtons", { "RaidInfoFrame_UpdateButtons" })
  for key, cands in pairs(STATIC_NAMES) do Compat.declare(SURFACE, key, cands) end
  local view = initView()
  if hooked or type(get("frame")) ~= "table" then return view end
  hooked = true
  Raid.showStatic()
  local allAssist = get("allAssist")
  if type(allAssist) == "table" then WFJ.HelpTooltip.register(allAssist) end
  local box = type(get("infoFrame")) == "table" and get("infoFrame").ScrollBox or nil
  local util = get("scrollUtil")
  if type(box) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    util.AddInitializedFrameCallback(box, Raid.onRow, Raid, true)
  end
  if type(get("updateButtons")) == "function" then
    hooksecurefunc("RaidInfoFrame_UpdateButtons", Raid.showExtend)
    Raid.showExtend()
  end
  WFJ.LoadOnDemand.when("Blizzard_RaidUI", Raid.setupRaidUI)
  return true
end
