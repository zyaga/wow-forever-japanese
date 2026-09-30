-- UI/LabelTree.lua: every label under one frame, found by walking it (area "ui", ADR-016 / ADR-029 §4).
-- The Options window and Edit Mode are built from data: a list row, a settings dialog or a graphics section is a
-- template whose labels are parentKeys or unnamed regions several frames deep, filled from a definitions table
-- (blizzard_settings_shared/blizzard_settingcontrols.lua:311–356, blizzard_settingsdefinitions_shared/graphics.xml:
-- 140–240, blizzard_editmode/shared/editmodetemplates.lua:24–140). Naming each widget would be per-option code, so a
-- surface hands the frame the client just filled to LabelTree.show, which walks its regions and children and shows
-- each FontString, Button and dropdown button through Labels.show. Records are keyed by the widget (Labels.keyer),
-- never by position: a pooled row keeps its keys and its records follow the new text.
-- What keeps a walk safe:
--   * `opts.only` is required: a walk never matches against the whole dictionary, only the keys its window shows;
--   * an EditBox is never entered (its text is read back), nor a widget in a NEVER_TOUCH list (Labels.forbidden),
--     nor a frame `opts.skip(frame)` refuses (key-binding buttons, unit-frame previews, a layout-name dropdown);
--   * a dropdown button is followed, not just shown: the Menu system rewrites `dropdown.Text` in UpdateText on every
--     selection (blizzard_menu/menutemplates.lua:712), so the label is re-shown after each (hooksecurefunc on the
--     instance, once). The popup's entries are UI/Menus'.
--   * depth is bounded, and every value is type-checked before use: a wrong-typed child ends that branch only.
local _, WFJ = ...
local LabelTree = {}
WFJ.LabelTree = LabelTree

LabelTree.MAX_DEPTH = 10

local keyOf = WFJ.Labels.keyer("tree.") -- one id per widget, whichever surface walks it

local function objectType(obj)
  if type(obj) ~= "table" or type(obj.GetObjectType) ~= "function" then return nil end
  local ok, kind = pcall(obj.GetObjectType, obj)
  return ok and kind or nil
end

-- A dropdown button as the Menu system builds one: a `Text` FontString and an UpdateText writer.
local function isDropdown(frame)
  return type(frame.UpdateText) == "function" and type(frame.Text) == "table"
end

local followed = setmetatable({}, { __mode = "k" }) -- dropdown → { surface, opts } of its first walk

-- Shows a dropdown button's selection text and follows its writer. → 1 | 0 for the current text.
function LabelTree.dropdown(surface, dropdown, opts)
  if type(dropdown) ~= "table" or not isDropdown(dropdown) then return 0 end
  if not followed[dropdown] then
    followed[dropdown] = { surface = surface, opts = opts }
    hooksecurefunc(dropdown, "UpdateText", function(self)
      local f = followed[self]
      if f and type(self.Text) == "table" then WFJ.Labels.show(f.surface, keyOf(self.Text), self.Text, nil, f.opts) end
    end)
  end
  return WFJ.Labels.show(surface, keyOf(dropdown.Text), dropdown.Text, nil, opts)
end

-- The button's own text region, when it has one (a template button); nil for a button whose label is a layer
-- FontString (SettingsExpandableSectionTemplate's Button.Text).
local function buttonText(frame)
  if type(frame.GetFontString) ~= "function" then return nil end
  local ok, fs = pcall(frame.GetFontString, frame)
  return ok and type(fs) == "table" and fs or nil
end

-- Walks `root` and shows every label under it on `surface`. `opts`: { only = { KEY = true, … } (required),
-- skip = function(frame) → true to leave that frame and everything under it alone }.
-- → the number of dictionary words found.
function LabelTree.show(surface, root, opts)
  if type(root) ~= "table" or type(opts) ~= "table" or type(opts.only) ~= "table" then return 0 end
  local show, forbidden = WFJ.Labels.show, WFJ.Labels.forbidden
  local labelOpts = { only = opts.only }
  local n = 0
  local function visit(frame, depth)
    if type(frame) ~= "table" or depth > LabelTree.MAX_DEPTH or forbidden(frame) then return end
    if objectType(frame) == "EditBox" or (opts.skip and opts.skip(frame)) then return end
    local own
    if isDropdown(frame) then
      own = frame.Text
      n = n + LabelTree.dropdown(surface, frame, labelOpts)
    else
      own = buttonText(frame)
      if own then n = n + show(surface, keyOf(frame), frame, nil, labelOpts) end
    end
    if type(frame.GetRegions) == "function" then
      for _, region in ipairs({ frame:GetRegions() }) do
        if region ~= own and objectType(region) == "FontString" then
          n = n + show(surface, keyOf(region), region, nil, labelOpts)
        end
      end
    end
    if type(frame.GetChildren) == "function" then
      for _, child in ipairs({ frame:GetChildren() }) do visit(child, depth + 1) end
    end
  end
  visit(root, 1)
  WFJ.Render.updateBanner(surface)
  return n
end

-- A key set from a list of keys: { "A", "B" } → { A = true, B = true } (what `opts.only` takes without a rebuild
-- on every label).
function LabelTree.set(list)
  local set = {}
  for _, key in ipairs(list or {}) do set[key] = true end
  return set
end
