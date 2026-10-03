-- UI/Popups.lua: the StaticPopup / GameDialog dialogs ("Delete this item?", "Leave the group?") on Forever (surface
-- "popups", area "ui", ADR-037; supersedes ADR-015 §5). Blizzard_StaticPopup_Game loads at login on camelot.
-- StaticPopup_Show(which, text_arg1, text_arg2, …) looks up StaticPopupDialogs[which], calls dialog:Init (which
-- writes Text with SetFormattedText(dialogInfo.text, text_arg1, text_arg2) (gamedialog.lua:120–128) and each shown
-- button with SetText(dialogInfo.buttonN) (:302–320)), then shows the dialog, runs dialog:Resize() and returns it
-- (staticpopup.lua:309–433). A post-hook on that GLOBAL runs after all of it; hooksecurefunc hands it the call's
-- arguments, not the dialog, so the dialog is the shown one of StaticPopup1–4 (gamedialog.xml:339–358) whose
-- `which` is the call's (read only; StaticPopup_FindVisible is not called).
-- The dialog's own definition names the text: its English template is dialogInfo.text, so the key is the one whose
-- client English is exactly that template (Index:keyOf), and the Japanese is filled from the dialog's own arguments
-- (Index:formatArgs, string.format of each specifier). A player, item or zone name is copied as the English showed
-- it (names stay in English), never matched out of the text. The line is only rewritten while it still reads
-- exactly the English the definition and those arguments give; a dialog whose text is computed (dialogInfo.text ==
-- "", a GetExpirationText) or whose text no longer matches stays as written.
-- Buttons, the SubText and the extra button: their English is the definition's string; each takes the one key whose
-- English that is.
-- The timed dialogs re-write their text from StaticPopup_OnUpdate, every frame (staticpopup.lua:490–535): the start
-- delay's re-format from text_arg1 / text_arg2, and GetExpirationText. A post-hook on that GLOBAL shows the line
-- again when it changed. Of the expiration texts only the shared one is rebuilt: GameDialogDefsUtil.
-- GetDefaultExpirationText formats dialogInfo.text with (seconds, SECONDS) under a minute, else (minutes, MINUTES)
-- (gamedialogdefsutil.lua:53–61): the death dialog's "%d %s until release", the logout and quit timers. The unit
-- word is a dictionary word: it is put in as its own Japanese, never left English inside a Japanese line. A dialog
-- with its own expiration function stays as written.
-- The StaticPopupSpecial dialogs own their text (StaticPopupSpecial_Show(frame) only positions and shows the frame,
-- staticpopup.lua:941): the add-friend dialogs (blizzard_addfriend, addfriendtemplates.lua:54, 88) and the battle
-- popups (blizzard_lfgutil: PVPReadyPopup pvppopup.lua:89, PVPFramePopup / PVPRoleCheckPopup / PVPReadyDialog
-- pvphelper.lua:106, 180, 287, 436; PlunderstormFramePopup; LFGInvitePopup). A post-hook on StaticPopupSpecial_Show
-- walks one of those frames' FontStrings and button labels, each restricted to the words those files name
-- (SPECIAL_ONLY); the name widgets are never touched (NEVER_TOUCH). The dressing room's custom-set
-- rename dialog, WardrobeCustomSetEditFrame (blizzard_framexml/wardrobecustomsets.lua:291). Other StaticPopupSpecial
-- frames belong to their own surfaces (the group finder, the guild invite, Edit Mode …); Party Sync's never show on
-- Forever. Taint (ADR-037): apart from secure post-hooks (hooksecurefunc on the three globals and on the
-- recruitment frame's writer), every write is a widget method (FontString:SetText through Render, Button text
-- through Labels). No other Lua field of a dialog, of its dialogInfo or of StaticPopupDialogs is written, and Resize /
-- Layout are never called: nothing an OnAccept handler reads comes from addon code. The dialog lays out from
-- dialogInfo's widths, not from the string (gamedialog.lua:629–705), so a Japanese line wraps inside the English's
-- width. Whether the layout grows with a taller line is an in-game check.
local _, WFJ = ...
local Popups = {}
WFJ.Popups = Popups

local SURFACE = "popups"
Popups.SURFACE = SURFACE
local Compat = WFJ.Compat

-- the edit boxes (a name the player types) are never read; the add-friend dialogs' invitee name
Popups.NEVER_TOUCH = { "BattleNetInviteFrame.InviteeName" }

-- The StaticPopupSpecial frames this surface walks, and the words they may show (their XML / Lua).
local SPECIAL = { "AddFriendFrame", "BattleNetInviteFrame", "PVPReadyPopup", "PVPFramePopup", "PVPRoleCheckPopup",
  "PVPReadyDialog", "PlunderstormFramePopup", "LFGInvitePopup", "QuickJoinRoleSelectionFrame",
  "RecruitAFriendRecruitmentFrame", "ReportCheatingDialog", "WardrobeCustomSetEditFrame" }
-- A special frame that re-writes its text after it is shown: its writer method is post-hooked on first show.
local WRITERS = { RecruitAFriendRecruitmentFrame = "UpdateRecruitmentInfo" } -- recruitafriendframe.lua:1522–1573
local SPECIAL_ONLY = { only = {
  -- blizzard_addfriend/addfriendtemplates.xml|lua
  "ADD_NEW_FRIEND", "BATTLENET_UNAVAILABLE", "BATTLETAG_AND_REAL_ID_DESCRIPTION", "BATTLETAG_FRIEND_LABEL",
  "BATTLE_TAG_REQUEST", "BATTLE_TAG_REQUEST_INFO", "CANCEL", "CHARACTER_FRIEND_INFO", "CHARACTER_FRIEND_LABEL",
  "ENTER_NAME_OR_BATTLETAG", "ENTER_NAME_OR_BATTLETAG_OR_EMAIL", "ENTER_NAME_OR_EMAIL", "ERR_SYSTEM_DISABLED",
  "OKAY", "OR_CAPS", "REALID_BATTLETAG_FRIEND_LABEL", "REALID_FRIEND_LABEL", "SEND_REQUEST", "TITLE_FRIEND_REQUEST",
  "WOW_FRIEND_DESCRIPTION",
  -- blizzard_lfgutil (pvppopup, pvphelper, lfginvitepopup)
  "READY_CHECK", "ACCEPT", "ARENA_COMPLETE_MESSAGE", "ARENA_IS_READY", "BATTLEGROUND_COMPLETE_MESSAGE",
  "BATTLEGROUND_IS_READY", "CONFIRM_YOUR_ROLE", "DECLINE", "ENTER_LFG", "HEALER", "INSTANCE_SHUTDOWN_MESSAGE",
  "LEAVE_QUEUE", "QUEUED_FOR", "RATED_BATTLEGROUND_IS_READY", "WARGAME_CHALLENGED", "WARGAME_IS_READY",
  "WOW_LABS_PLUNDERSTORM_FORMED", "YOUR_ROLE", "ACCEPTING_INVITE_WILL_REMOVE_QUEUE", "INVITATION",
  "LFG_ROLE_UNAVAILABLE",
  -- the quick-join role select (roleselectiontemplate.xml), the recruitment dialog (recruitafriendframe.lua:
  -- 1522–1630), the cheating report (helpframe.xml:345)
  "SELECT_YOUR_ROLE", "RAF_RECRUITMENT_DESC", "RAF_RECRUITS_FACTION_AND_REALM", "RAF_NO_ACTIVE_LINK",
  "RAF_FULL_RECRUITS", "RAF_ACTIVE_LINK_EXPIRE_DATE", "RAF_EXPENDED_LINK_EXPIRE_DATE", "RAF_LINK_REMAINING_USES",
  "RAF_COPY_LINK", "RAF_GENERATE_LINK", "RAF_RECRUITMENT", "REPORT_CHEATING_TITLE", "REPORT_CHEATING_TEXT1",
  "REPORT_CHEATING_EDITBOX_INFO", "REPORT_PLAYER",
  -- the custom-set rename dialog (blizzard_framexml/wardrobecustomsets.xml:45–140, shown at lua:291)
  "TRANSMOG_CUSTOM_SET_NAME", "TRANSMOG_CUSTOM_SET_EDIT_DELETE", "SAVE",
} }

local CANDIDATES = { show = { "StaticPopup_Show" }, update = { "StaticPopup_OnUpdate" },
  dialogs = { "StaticPopupDialogs" }, special = { "StaticPopupSpecial_Show" } }

local widgetKey = WFJ.Labels.keyer("popup.") -- one record per dialog widget (the dialogs are pooled)

-- The definition's English for one text field, and its key. → key, english | nil
-- (Index:keyOf answers by English: a dialog whose text is an owned key's English would get the other key's Japanese.
-- No dialog definition names an owned key; test_ui_own.py pins it.)
local function keyFor(english)
  local index = WFJ.UIIndex
  if not index or type(english) ~= "string" or english == "" then return nil end
  local key = index:keyOf(english)
  if key then return key, english end
  return nil
end

-- One button (or the SubText): its English is exactly the definition's string. → 1 | 0
local function showWord(widget, english)
  local key = keyFor(english)
  if not key or type(widget) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, widgetKey(widget), widget, nil, { only = { key } })
end

local UNITS = { "SECONDS", "MINUTES" } -- the countdown's unit words (GetDefaultExpirationText)

-- The arguments that gave the line now shown: the dialog's own (text_arg1, text_arg2), else the shared countdown's.
-- → a1, a2 | nil
local function argumentsOf(dialog, info, fs, english, shown)
  local a1, a2 = fs.text_arg1, fs.text_arg2
  local ok, text = pcall(string.format, english, a1, a2)
  if ok and text == shown then return a1, a2 end
  if info.text_arg1 ~= nil or info.text_arg2 ~= nil then -- a generic confirmation's own arguments
    a1, a2 = info.text_arg1, info.text_arg2
    ok, text = pcall(string.format, english, a1, a2)
    if ok and text == shown then return a1, a2 end
  end
  local util = _G.GameDialogDefsUtil
  if type(util) ~= "table" or info.GetExpirationText == nil
      or info.GetExpirationText ~= util.GetDefaultExpirationText or type(dialog.timeleft) ~= "number" then
    return nil
  end
  local left = math.ceil(dialog.timeleft)
  if left < 60 then
    a1, a2 = left, Compat.resolve("SECONDS")
  else
    a1, a2 = math.ceil(left / 60), Compat.resolve("MINUTES")
  end
  ok, text = pcall(string.format, english, a1, a2)
  if ok and text == shown then return a1, a2 end
  return nil
end

-- A unit word argument as its Japanese. → args | nil (a unit word with no Japanese: the line stays English)
local function unitWords(args)
  local index = WFJ.UIIndex
  for i, v in pairs(args) do
    for _, unit in ipairs(UNITS) do
      if i ~= "key" and v == Compat.resolve(unit) then
        local row = index.rows[unit]
        -- only a row the index admitted (its h1 matches this client's English), as any other lookup
        if not row or not index:keyOf(v) then return nil end
        args[i] = row[1]
      end
    end
  end
  return args
end

-- The dialog's main line, filled from its own arguments. → 1 | 0
local function showText(dialog, info)
  local fs = type(dialog) == "table" and dialog.Text or nil
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" then return 0 end
  local key, english = keyFor(info.text)
  if not key then return 0 end
  local shown = fs:GetText()
  local a1, a2 = argumentsOf(dialog, info, fs, english, shown)
  if a1 == nil and a2 == nil and english:find("%", 1, true) then return 0 end -- computed or changed: never guessed
  if english:find("%", 1, true) == nil and shown ~= english then return 0 end
  local args = WFJ.UIIndex:formatArgs(key, english, a1, a2)
  args = args and unitWords(args)
  if not args then return 0 end
  WFJ.Render.show(SURFACE, widgetKey(fs), fs, shown, "ui", "ui", key, { args = args })
  return 1
end

-- GENERIC_CONFIRMATION's definition is empty: its OnShow writes the caller's text and arguments, and its buttons
-- are the caller's accept / cancel text or YES / NO [verified: blizzard_staticpopup/shareddialogdefs.lua:1-8,
-- blizzard_staticpopup_game/gamedialogdefs.lua:168-175]. → the strings the dialog shows, as a definition
local function shownInfo(dialog, info)
  local data = dialog.data
  if dialog.which ~= "GENERIC_CONFIRMATION" or type(data) ~= "table" then return info end
  return setmetatable({ text = data.text, text_arg1 = data.text_arg1, text_arg2 = data.text_arg2,
    button1 = data.acceptText or Compat.resolve("YES"), button2 = data.cancelText or Compat.resolve("NO") },
    { __index = info })
end

-- One shown dialog, its text already written. → words found
function Popups.onShow(dialog)
  if type(dialog) ~= "table" then return 0 end
  local info = dialog.dialogInfo
  if type(info) ~= "table" then return 0 end
  info = shownInfo(dialog, info)
  local n = showText(dialog, info)
  n = n + showWord(dialog.SubText, info.subText)
  local container = dialog.ButtonContainer
  local buttons = type(container) == "table" and container.Buttons or nil
  if type(buttons) == "table" then
    for i, button in ipairs(buttons) do n = n + showWord(button, info["button" .. i]) end
  end
  n = n + showWord(dialog.ExtraButton, info.extraButton)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- The shown dialog a StaticPopup_Show(which, a1, a2, data) call set up (see the header). A `multiple` dialog type can
-- be shown more than once with different data (StaticPopup_FindVisible, staticpopup.lua:156–166): the one holding
-- this call's `data` is it. → dialog | nil
local DIALOGS = 4 -- StaticPopup1–4 (gamedialog.xml:339–358)
local function findDialog(which, data)
  local found
  for i = 1, DIALOGS do
    local d = _G["StaticPopup" .. i]
    if type(d) == "table" and d.which == which and type(d.IsShown) == "function" and d:IsShown() then
      if d.data == data then return d end
      found = found or d
    end
  end
  return found
end

-- hooksecurefunc target (StaticPopup_Show): (which, text_arg1, text_arg2, data, …). → words found
function Popups.onShowCall(which, _, _, data)
  return Popups.onShow(findDialog(which, data))
end

-- What StaticPopup_OnUpdate left on screen last frame, per dialog: a frame where nothing changed costs two GetText
-- calls (a held Alt, or a line that is not ours, would otherwise be looked at again every frame).
local seen = setmetatable({}, { __mode = "k" })

-- hooksecurefunc target (StaticPopup_OnUpdate): a timed dialog re-wrote its line (the countdown, the start delay), or
-- its accept delay ended and button1 got its English back (staticpopup.lua:535–547).
function Popups.onUpdate(dialog)
  if type(dialog) ~= "table" or type(dialog.Text) ~= "table" or type(dialog.dialogInfo) ~= "table"
      or type(dialog.Text.GetText) ~= "function" then
    return
  end
  local container = dialog.ButtonContainer
  local first = type(container) == "table" and type(container.Buttons) == "table" and container.Buttons[1] or nil
  if type(first) ~= "table" or type(first.GetText) ~= "function" then first = nil end
  local last = seen[dialog]
  if last and last.text == dialog.Text:GetText() and last.label == (first and first:GetText()) then return end
  local info = shownInfo(dialog, dialog.dialogInfo) -- GENERIC_CONFIRMATION: the caller's text and buttons
  showText(dialog, info)
  if first and dialog.acceptDelay == nil then showWord(first, info.button1) end
  seen[dialog] = { text = dialog.Text:GetText(), label = first and first:GetText() or nil }
end

-- Every FontString and button label under `frame` (depth-first), restricted to SPECIAL_ONLY. An EditBox (a name the
-- player types, a prefilled set name) and a never-touch subtree are not entered. → words found
local function walk(frame, depth)
  if type(frame) ~= "table" or depth > 8 or WFJ.Labels.forbidden(frame) then return 0 end
  if type(frame.GetObjectType) == "function" and frame:GetObjectType() == "EditBox" then return 0 end
  local n = 0
  if type(frame.GetRegions) == "function" then
    for _, region in ipairs({ frame:GetRegions() }) do
      if type(region) == "table" and type(region.GetObjectType) == "function"
          and region:GetObjectType() == "FontString" then
        n = n + WFJ.Labels.show(SURFACE, widgetKey(region), region, nil, SPECIAL_ONLY)
      end
    end
  end
  if type(frame.GetChildren) == "function" then
    for _, child in ipairs({ frame:GetChildren() }) do
      if type(child) == "table" and type(child.GetFontString) == "function" then
        n = n + WFJ.Labels.show(SURFACE, widgetKey(child), child, nil, SPECIAL_ONLY)
      end
      n = n + walk(child, depth + 1)
    end
  end
  return n
end

local writerHooked = {}

-- hooksecurefunc target (StaticPopupSpecial_Show): one of SPECIAL is walked; any other frame is another surface's.
function Popups.onSpecial(frame)
  if type(frame) ~= "table" then return 0 end
  for _, name in ipairs(SPECIAL) do
    if frame == Compat.resolve(name) then
      local writer = WRITERS[name]
      if writer and not writerHooked[name] and type(frame[writer]) == "function" then
        writerHooked[name] = true
        hooksecurefunc(frame, writer, function(self) walk(self, 0) end)
      end
      local n = walk(frame, 0)
      WFJ.Render.updateBanner(SURFACE)
      return n
    end
  end
  return 0
end

local hooked = false

-- Called by Main after Compat.init.
function Popups.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  if type(Compat.get(SURFACE, "show")) ~= "function" then return false end
  hooked = true
  hooksecurefunc("StaticPopup_Show", Popups.onShowCall)
  if type(Compat.get(SURFACE, "update")) == "function" then
    hooksecurefunc("StaticPopup_OnUpdate", Popups.onUpdate)
  end
  if type(Compat.get(SURFACE, "special")) == "function" then
    hooksecurefunc("StaticPopupSpecial_Show", Popups.onSpecial)
  end
  return true
end
