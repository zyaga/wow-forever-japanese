-- UI/Character.lua: the character window's paperdoll and pet panes (surfaces "character", "character.static" and
-- "character.title", area "ui", ADR-016). Nothing here is load-on-demand: the TOC loads
-- [Game]\CharacterFrame.*, [Game]\PaperDollFrame.* and the Vanilla, Cata and [Game] PaperDollFrameStats.lua on camelot
-- [verified: forever blizzard_uipanels_game.toc:44–60]. What is translated:
--   the level lines, both writers called by name [verified: camelot/paperdollframe.lua:492–515, 522–543, 448, 460;
--     characterframe.lua:813, 837]: CharacterLevelText, the player's line from PaperDollFrame_SetLevel (PLAYER_LEVEL /
--     PLAYER_LEVEL_NO_SPEC: level, class colour, spec, class: `text` captures); and PetCharacterLevelText
--     (paperdollframe.xml:599), the pet's line from PaperDollFrame_SetPetLevel: UNIT_TYPE_LEVEL_TEMPLATE (level, pet
--     family), then, when the pet has a loyalty rank, " " .. HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(
--     PARENS_TEMPLATE:format(C_PetInfo.GetPetLoyalty())) (lua:535–539). The rank is a PetLoyalty row's English. The
--     pet's line is split there: the level part through UNIT_TYPE_LEVEL_TEMPLATE, the rank through PARENS_TEMPLATE
--     around its PetLoyalty row, the colour kept. A rank that is no PetLoyalty row stays as written; a level part
--     that is no UNIT_TYPE_LEVEL_TEMPLATE line leaves the whole line English.
--   the stat pane: CharacterStatsPaneScrollBox / CharacterStatsPanePetScrollBox, a ScrollBox of pooled rows
--     (characterframe.lua:1049–1077, 1107–1226, 1233–1298; characterframe.xml:170–234, 463–484). A header row's Title
--     is a PAPERDOLL_STATCATEGORIES categoryName or STAT_CATEGORY_RESISTANCE (paperdollframeconstants.lua:30–100,
--     characterframe.lua:1200); a stat row's Label is format(STAT_FORMAT "%s:", <stat word>) written by its Init or
--     by PaperDollFrame_SetLabelAndText from the stat's updateFunc (paperdollframe.lua:2428–2437). Followed with
--     ScrollUtil.AddInitializedFrameCallback (after the element initializer), keyed by the row widget itself; a stat
--     row is also a help-tooltip owner (PaperDollStatTooltip or its onEnterFunc, paperdollframe.lua:2208–2221).
--     A stat Label is restricted (`only`) to the stat words: PaperDollFrame_SetWeaponSkill labels a row with a skill
--     name (paperdollframe.lua:723–735). CharacterStatsPane (the older category frames) is never shown.
--   help tooltips: the six icon mode tabs (tooltipText CHARACTER_FRAME_TAB_*, SidePanelTabButtonMixin:OnEnter →
--     SetText, shareduipaneltemplates.lua:406–420; characterframe.xml:574–603), the three paperdoll sidebar tabs
--     (paperdollframe.lua:3578–3586), the right-pane toggle (characterframe.lua:337–363), and the equipment slots:
--     the same CharacterHeadSlot … CharacterAmmoSlot names; an empty slot's SetText(<SLOT>SLOT / RELICSLOT) comes from
--     ItemUtil.DisplayEquipSlotTooltip (blizzard_framexmlutil/itemutil.lua:395–414).
--   the equipment manager (sidebar 2, PaperDollFrame.EquipmentManagerPane, paperdollframe.xml:525–585): the Equip /
--     Save buttons (text= EQUIPSET_EQUIP / SAVE) and the New Set button's unnamed FontString (text=
--     PAPERDOLL_NEWEQUIPMENTSET, xml:16–27), all static; each pooled set row (GearSetButtonTemplate, xml:232–360,
--     followed with ScrollUtil.AddInitializedFrameCallback) has its set name in `.text` (a name, forbidden) and two
--     help-tooltip owners, DeleteButton (SetText(DELETE)) and EditButton (SetText(EQUIPMENT_SET_SETTINGS)), each
--     restricted to its one key. The row's own hover is GameTooltip:SetEquipmentSet (client data, not walked).
--   the set's name-and-icon popup (GearManagerPopupFrame, IconSelectorPopupFrameTemplate, xml:940–947): the edit
--     box header (editBoxHeaderText GEARSETS_POPUP_TEXT, written at OnLoad, shareduipaneltemplates.lua:1844) and
--     the selected-icon description (ICON_SELECTION_CLICK / ICON_SELECTION_NOTINLIST), written by SetSelectedIconText
--     (a method call, lua:1967–1975) and by the popup's selection callback, which SelectorMixin:OnSelection runs just
--     before self:SetSelectedIndex (blizzard_selectorui.lua:3–15; paperdollframe.lua:2680–2689): both are hooked on
--     their instances. The name EditBox is forbidden.
--   the window title: CharacterFrameMixin:UpdateTitle writes SetTitle(characterFrameDisplayInfo[
--     activeSubframe].title): the player's name (UnitPVPName, the "Default" entry, shown on the paperdoll) or one of
--     REPUTATION / CURRENCY / PVP / SKILLS / STATISTICS for the other panes (characterframe.lua:254–258, the only
--     SetTitle on this frame; characterframeconstants.lua:9–34). Shown through Labels.title with `only` those five
--     pane keys, on its own surface "character.title"; and because a player may be named "Skills" or "Currency",
--     UpdateTitle is post-hooked too: when the active pane is not one of the five, the title is the name and its
--     record is released (the client's English, the name, is put back).
--   the title pane (PaperDollFrame.TitleManagerPane, the third of PAPERDOLL_SIDEBARS, paperdollframeconstants.lua:23):
--     a pooled row's text is written by PaperDollTitlesPane_InitButton (paperdollframe.lua:3243–3246). The first row is
--     PLAYER_TITLE_NONE (:3304); every other row is a title the character earned, a name, left as written. Rows are
--     walked from the ScrollBox's initialized-frame callback, restricted to that one key.
-- Not translated: the XP / pet XP bars.
local _, WFJ = ...
local Character = {}
WFJ.Character = Character

local SURFACE = "character"
Character.SURFACE = SURFACE
local STATIC = SURFACE .. ".static"
Character.STATIC = STATIC
local TITLE = SURFACE .. ".title" -- camelot: the window title on a pane other than the paperdoll
Character.TITLE = TITLE
local PANE_TITLE = { only = { "REPUTATION", "CURRENCY", "PVP", "SKILLS", "STATISTICS" } }
-- the panes whose title is a dictionary word (characterframeconstants.lua:14–33); any other title is the player's name
local TITLED_PANES = { ReputationFrame = true, TokenFrame = true, PVPRankFrame = true, SkillsFrame = true,
  StatisticsFrame = true }
Character.PANE_TITLE_KEYS = PANE_TITLE.only
local Compat = WFJ.Compat

-- Widgets this module must never record.
Character.NEVER_TOUCH = {
  "GearManagerPopupFrame.BorderBox.IconSelectorEditBox" } -- the equipment set's name

-- (the window title is not here: a pane title renders under `only`, and the name title is released; see the header)
local WRITERS = { "PaperDollFrame_SetLevel", "PaperDollFrame_SetPetLevel" }
local LEVEL_ONLY = { only = { "PLAYER_LEVEL", "PLAYER_LEVEL_NO_SPEC" } } -- the player's line
local PET_LEVEL_ONLY = { only = { "UNIT_TYPE_LEVEL_TEMPLATE" } } -- the pet's line, before its rank

-- Frames whose tooltips are Lua-built help lines: the equipment slots, the icon mode tabs, the paperdoll sidebar
-- tabs, the right-pane toggle.
local OWNERS = {}
for _, slot in ipairs({ "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist",
  "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged", "Ammo" }) do
  OWNERS[#OWNERS + 1] = "Character" .. slot .. "Slot"
end
for i = 1, 6 do OWNERS[#OWNERS + 1] = "CharacterFrameModeTab" .. i end
for i = 1, 4 do OWNERS[#OWNERS + 1] = "PaperDollSidebarTab" .. i end
OWNERS[#OWNERS + 1] = "CharacterFrameRightPaneToggleButton"

-- camelot stat pane: the category headers and the stat words a row's Label can hold
local CATEGORY_ONLY = { only = { "STAT_CATEGORY_GENERAL", "STAT_CATEGORY_PRIMARY_ATTRIBUTES", "STAT_CATEGORY_WEAPONS",
  "STAT_CATEGORY_MODIFIERS", "STAT_CATEGORY_DEFENSE", "STAT_CATEGORY_RESISTANCE" } }
local STAT_ONLY = { only = { "HEALTH", "MANA", "RAGE", "ENERGY", "FOCUS", "RUNIC_POWER", "STAT_MOVEMENT_SPEED",
  "SPELL_STAT1_NAME", "SPELL_STAT2_NAME", "SPELL_STAT3_NAME", "SPELL_STAT4_NAME", "SPELL_STAT5_NAME",
  "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_RANGED", "DAMAGE", "WEAPON_SPEED",
  "STAT_ATTACK_POWER", "RANGED_ATTACK_POWER", "STAT_HIT_CHANCE", "STAT_CRITICAL_STRIKE", "STAT_HASTE",
  "STAT_EXPERTISE", "STAT_ARMOR_PENETRATION", "STAT_SPELLPOWER", "STAT_SPELLHEALING", "STAT_SPELL_PENETRATION",
  "MANA_REGEN", "STAT_ENERGY_REGEN", "STAT_FOCUS_REGEN", "DEFENSE", "STAT_DODGE", "STAT_BLOCK",
  "STAT_PARRY", "STAT_ARMOR", "STAT_SPEED",
  "RESISTANCE0_NAME", "RESISTANCE1_NAME", "RESISTANCE2_NAME", "RESISTANCE3_NAME", "RESISTANCE4_NAME",
  "RESISTANCE5_NAME", "RESISTANCE6_NAME",
  "DAMAGE_SCHOOL2", "DAMAGE_SCHOOL3", "DAMAGE_SCHOOL4", "DAMAGE_SCHOOL5", "DAMAGE_SCHOOL6", "DAMAGE_SCHOOL7" } }
-- camelot equipment manager and its popup: each widget to its own key(s)
local EQUIP_ONLY = { only = { "EQUIPSET_EQUIP" } }
local SAVE_ONLY = { only = { "SAVE" } }
local NEWSET_ONLY = { only = { "PAPERDOLL_NEWEQUIPMENTSET" } }
local POPUP_HEADER_ONLY = { only = { "GEARSETS_POPUP_TEXT" } }
local ICON_TEXT_ONLY = { only = { "ICON_SELECTION_CLICK", "ICON_SELECTION_NOTINLIST" } }
local DELETE_ONLY = { only = { "DELETE" } }
local SETTINGS_ONLY = { only = { "EQUIPMENT_SET_SETTINGS" } }
local TITLE_NONE_ONLY = { only = { "PLAYER_TITLE_NONE" } }
Character.CAMELOT_KEYS = { category = CATEGORY_ONLY.only, stat = STAT_ONLY.only, level = LEVEL_ONLY.only,
  petLevel = { "UNIT_TYPE_LEVEL_TEMPLATE", "PARENS_TEMPLATE" },
  equipmentManager = { "EQUIPSET_EQUIP", "SAVE", "PAPERDOLL_NEWEQUIPMENTSET", "GEARSETS_POPUP_TEXT",
    "ICON_SELECTION_CLICK", "ICON_SELECTION_NOTINLIST", "DELETE", "EQUIPMENT_SET_SETTINGS" } }

local function get(name) return Compat.get(SURFACE, name) end

local function declareAll()
  for _, list in ipairs({ OWNERS, WRITERS, Character.NEVER_TOUCH }) do
    for _, name in ipairs(list) do Compat.declare(SURFACE, name, { name }) end
  end
  Compat.declare(SURFACE, "CharacterLevelText", { "CharacterLevelText" })
  Compat.declare(SURFACE, "PetCharacterLevelText", { "PetCharacterLevelText" })
  Compat.declare(SURFACE, "statsBox", { "CharacterStatsPaneScrollBox.ScrollBox" })
  Compat.declare(SURFACE, "petStatsBox", { "CharacterStatsPanePetScrollBox.ScrollBox" })
  Compat.declare(SURFACE, "scrollUtil", { "ScrollUtil" })
  Compat.declare(SURFACE, "equipPane", { "PaperDollFrame.EquipmentManagerPane" })
  Compat.declare(SURFACE, "titleBox", { "PaperDollFrame.TitleManagerPane.ScrollBox" })
  Compat.declare(SURFACE, "gearPopup", { "GearManagerPopupFrame" })
  Compat.declare(SURFACE, "frame", { "CharacterFrame" })
end

local titleRowKey = WFJ.Labels.keyer("title.") -- a pooled title row's record key

-- The title pane's ScrollUtil callback: (owner, frame, elementData) on initialization, (frame, elementData) on the
-- existing-frames pass. Only the "No Title" row is a dictionary word. Returns nothing (ForEachFrame stops at the first
-- truthy return).
function Character.onTitleRow(a, b)
  local row = a
  if a == Character then row = b end
  if type(row) ~= "table" or type(row.text) ~= "table" then return end
  WFJ.Labels.show(SURFACE, titleRowKey(row), row.text, nil, TITLE_NONE_ONLY)
end

-- The pet's level line with a loyalty rank after it: → level text, colour open, rank, colour close | nil. The
-- parentheses are the client's own PARENS_TEMPLATE around its "%s".
local function splitRank(text)
  local parens = Compat.resolve("PARENS_TEMPLATE")
  if type(text) ~= "string" or type(parens) ~= "string" then return nil end
  local pre, post = parens:match("^(.-)%%s(.*)$")
  if not pre then return nil end
  local function lit(x) return (x:gsub("%W", "%%%0")) end
  return text:match("^(.-) (|c%x%x%x%x%x%x%x%x)" .. lit(pre) .. "(.-)" .. lit(post) .. "(|r)$")
end

-- The pet's level line on PetCharacterLevelText. → 1 when shown (or still ours), else 0
local function showPetLevel()
  local fs = get("PetCharacterLevelText")
  local text = type(fs) == "table" and type(fs.GetText) == "function" and fs:GetText() or nil
  local head, open, rank, close = splitRank(text)
  if not head then return WFJ.Labels.show(SURFACE, "ui.petLevel", fs, nil, PET_LEVEL_ONLY) end
  local level = WFJ.Labels.part(head, PET_LEVEL_ONLY.only)
  if not level then return WFJ.Labels.showArgs(SURFACE, "ui.petLevel", fs, nil) end
  local loyalty = WFJ.Labels.part(rank, WFJ.Labels.families("PetLoyalty").only)
  local index = WFJ.UIIndex
  local parts = { level, text:sub(#head + 1) } -- a rank that is no PetLoyalty row, as the client wrote it
  if loyalty and index and index.rows.PARENS_TEMPLATE then
    parts = { level, " ", { key = "PARENS_TEMPLATE", args = { key = "PARENS_TEMPLATE", { entry = loyalty.key } },
      open = open, close = close } }
  end
  return WFJ.Labels.showArgs(SURFACE, "ui.petLevel", fs, level.key, { form = "seq", parts = parts })
end

-- hooksecurefunc target for PaperDollFrame_SetLevel and PaperDollFrame_SetPetLevel.
function Character.onLevel()
  local n = WFJ.Labels.show(SURFACE, "ui.level", get("CharacterLevelText"), nil, LEVEL_ONLY) + showPetLevel()
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- camelot: a stable record key per pooled stat-pane row (never its position)
local rowKey = WFJ.Labels.keyer("stat.") -- a pooled row's record key

-- The help-tooltip options that walk nothing (an empty `only` set).
local NO_WALK = { only = {} }

-- Whether a stat row's label, as the client just wrote it, is format(STAT_FORMAT, <stat word>), compared with the
-- client's own English for each STAT_ONLY key, so it holds whether or not the dictionary ships that word.
local function isStatLabel(fs)
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" then return false end
  local text = fs:GetText()
  if type(text) ~= "string" or text:sub(-1) ~= ":" then return false end
  local word = text:sub(1, -2)
  for _, k in ipairs(STAT_ONLY.only) do
    if Compat.resolve(k) == word then return true end
  end
  return false
end

-- camelot ScrollUtil callback: (owner, frame, elementData) on initialization, (frame, elementData) on the
-- existing-frames pass. Returns nothing (ForEachFrame stops at the first truthy return).
function Character.onStatRow(a, b)
  local frame = a
  if a == Character then frame = b end
  if type(frame) ~= "table" then return end
  local key = rowKey(frame)
  if type(frame.Title) == "table" then -- a category header
    WFJ.Labels.show(SURFACE, key, frame.Title, nil, CATEGORY_ONLY)
  elseif type(frame.Label) == "table" then
    local stat = isStatLabel(frame.Label) -- read before our write: the client's English
    WFJ.Labels.show(SURFACE, key, frame.Label, nil, STAT_ONLY)
    -- The row's tooltip is walked only while its label is a stat word: a weapon-skill row is labelled with a skill
    -- name (paperdollframe.lua:723–735) and its tooltip carries that name, so it is never walked; a pooled row that
    -- held a stat earlier is re-registered with an empty key set, which matches nothing.
    WFJ.HelpTooltip.register(frame, stat and true or NO_WALK)
  end
  WFJ.Render.updateBanner(SURFACE)
end

-- camelot ScrollUtil callback for an equipment-set row (same argument shapes as onStatRow; returns nothing).
function Character.onGearSetRow(a, b)
  local row = a
  if a == Character then row = b end
  if type(row) ~= "table" then return end
  WFJ.Labels.forbid(row.text) -- the set's name
  if type(row.DeleteButton) == "table" then WFJ.HelpTooltip.register(row.DeleteButton, DELETE_ONLY) end
  if type(row.EditButton) == "table" then WFJ.HelpTooltip.register(row.EditButton, SETTINGS_ONLY) end
end

local function field(t, ...)
  for _, k in ipairs({ ... }) do
    if type(t) ~= "table" then return nil end
    t = t[k]
  end
  return t
end

-- camelot: the equipment manager's buttons and the popup's header (static). → the number of dictionary words found.
function Character.showEquipmentManager()
  local pane, popup = get("equipPane"), get("gearPopup")
  local newSet = field(pane, "NewSet")
  return WFJ.Labels.showAll(STATIC, {
    { "ui.equipSet", field(pane, "EquipSet"), EQUIP_ONLY },
    { "ui.saveSet", field(pane, "SaveSet"), SAVE_ONLY },
    { "ui.newSet", newSet and WFJ.Labels.region(newSet, "PAPERDOLL_NEWEQUIPMENTSET"), NEWSET_ONLY },
    { "ui.gearPopupHeader", field(popup, "BorderBox", "EditBoxHeaderText"), POPUP_HEADER_ONLY },
  })
end

-- camelot: the popup's selected-icon description, after SetSelectedIconText / the selector's SetSelectedIndex. → 1 | 0
function Character.onIconText()
  local fs = field(get("gearPopup"), "BorderBox", "SelectedIconArea", "SelectedIconText", "SelectedIconDescription")
  local n = WFJ.Labels.show(SURFACE, "ui.gearIconText", fs, nil, ICON_TEXT_ONLY)
  WFJ.Render.updateBanner(SURFACE)
  return n
end

-- camelot: the window title after SetTitle (Labels.title's hook) and at init; → 1 | 0
function Character.showTitle()
  local frame = get("frame")
  if type(frame) ~= "table" then return 0 end
  local n = WFJ.Labels.title(TITLE, frame, PANE_TITLE) -- also installs the SetTitle hook, once
  if not TITLED_PANES[frame.activeSubframe] then return Character.onUpdateTitle() end
  WFJ.Render.updateBanner(TITLE)
  return n
end

-- hooksecurefunc target (CharacterFrame:UpdateTitle, after its SetTitle): the paperdoll's title is the player's
-- name; whatever it reads, it is never ours. → 0
function Character.onUpdateTitle()
  local frame = get("frame")
  if type(frame) == "table" and not TITLED_PANES[frame.activeSubframe] then WFJ.Render.release(TITLE) end
  return 0
end

local HOOKS = { PaperDollFrame_SetLevel = Character.onLevel, PaperDollFrame_SetPetLevel = Character.onLevel }

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Character.init()
  declareAll()
  if hooked then return false end
  hooked = true
  for _, name in ipairs(WRITERS) do
    if type(get(name)) == "function" then hooksecurefunc(name, HOOKS[name]) end
  end
  for _, name in ipairs(OWNERS) do
    local owner = get(name)
    if owner then WFJ.HelpTooltip.register(owner) end
  end
  -- the stat pane (at login, no load-on-demand wait)
  local util = get("scrollUtil")
  if type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then
    for _, name in ipairs({ "statsBox", "petStatsBox" }) do
      local box = get(name)
      if type(box) == "table" then util.AddInitializedFrameCallback(box, Character.onStatRow, Character, true) end
    end
    local setBox = field(get("equipPane"), "ScrollBox")
    if type(setBox) == "table" then
      util.AddInitializedFrameCallback(setBox, Character.onGearSetRow, Character, true)
    end
    local titleBox = get("titleBox")
    if type(titleBox) == "table" then
      util.AddInitializedFrameCallback(titleBox, Character.onTitleRow, Character, true)
    end
  end
  Character.showEquipmentManager()
  local frame = get("frame") -- the window title (a frame without a TitleContainer: nothing happens)
  if type(frame) == "table" and type(frame.TitleContainer) == "table" then
    Character.showTitle()
    if type(frame.UpdateTitle) == "function" then hooksecurefunc(frame, "UpdateTitle", Character.onUpdateTitle) end
  end
  local popup = get("gearPopup")
  if type(popup) == "table" then
    if type(popup.SetSelectedIconText) == "function" then
      hooksecurefunc(popup, "SetSelectedIconText", Character.onIconText)
    end
    local selector = popup.IconSelector
    if type(selector) == "table" and type(selector.SetSelectedIndex) == "function" then
      hooksecurefunc(selector, "SetSelectedIndex", Character.onIconText)
    end
  end
  return true
end
