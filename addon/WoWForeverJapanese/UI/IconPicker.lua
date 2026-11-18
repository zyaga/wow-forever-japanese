-- UI/IconPicker.lua: the labels every name-and-icon popup shares (IconSelectorPopupFrameTemplate,
-- blizzard_sharedxml/mainline/shareduipaneltemplates.xml:1722–1850): the equipment set, macro, guild bank tab, bank
-- tab and transmog outfit popups are that one template. Each window's own module keeps its header line and the
-- popup's edit box; the labels below are the template's, the same on every popup:
--   BorderBox.IconSelectionText MACRO_POPUP_CHOOSE_ICON (xml:1745), the drag area's IconDragText ICON_SELECTION_DRAG
--   (xml:1834), SelectedIconHeader ICON_SELECTION_TITLE_CURRENT (xml:1796), OkayButton / CancelButton, and
--   BorderBox.IconTypeDropdown's own text, one of ICON_FILTER_<kind> (shareduipaneltemplates.lua:1922–1930).
-- All but the dropdown are written once, so they are shown each time the popup shows.
local _, WFJ = ...
local IconPicker = {}
WFJ.IconPicker = IconPicker

local FILTER = { only = { "ICON_FILTER_ALL", "ICON_FILTER_SPELL", "ICON_FILTER_ITEM" } }
-- { recKey, the fields under BorderBox, keys, whether a module that shows it itself leaves it out }
local LABELS = {
  { "iconPicker.choose", { "IconSelectionText" }, { only = { "MACRO_POPUP_CHOOSE_ICON" } } },
  { "iconPicker.drag", { "IconDragArea", "IconDragAreaContent", "IconDragText" },
    { only = { "ICON_SELECTION_DRAG" } } },
  { "iconPicker.current", { "SelectedIconArea", "SelectedIconText", "SelectedIconHeader" },
    { only = { "ICON_SELECTION_TITLE_CURRENT" } }, true },
  { "iconPicker.okay", { "OkayButton" }, { only = { "OKAY" } }, true },
  { "iconPicker.cancel", { "CancelButton" }, { only = { "CANCEL" } }, true },
}

local function under(box, fields)
  local w = box
  for _, field in ipairs(fields) do w = type(w) == "table" and w[field] or nil end
  return type(w) == "table" and w or nil
end

local hooked = setmetatable({}, { __mode = "k" }) -- popup → { surface, own }

-- The popup's shared labels as they stand now. → the number of dictionary words shown
function IconPicker.show(popup)
  local how = hooked[popup]
  local box = how and popup.BorderBox
  if type(box) ~= "table" then return 0 end
  local n = 0
  for _, l in ipairs(LABELS) do
    local widget = under(box, l[2])
    if widget and not (l[4] and how.own) then n = n + WFJ.Labels.show(how.surface, l[1], widget, nil, l[3]) end
  end
  WFJ.Render.updateBanner(how.surface)
  return n
end

-- One popup of `surface`: its labels now and whenever it shows, and its filter dropdown's text. `own` is true for
-- a module that shows the selected-icon header and the two buttons itself. → true when the popup was hooked now
function IconPicker.setup(surface, popup, own)
  if type(popup) ~= "table" or type(popup.BorderBox) ~= "table" or hooked[popup] then return false end
  hooked[popup] = { surface = surface, own = own == true }
  if type(popup.HookScript) == "function" then popup:HookScript("OnShow", IconPicker.show) end
  WFJ.Labels.dropdown(surface, "iconPicker.filter", popup.BorderBox.IconTypeDropdown, FILTER)
  IconPicker.show(popup)
  return true
end
