-- UI/Labels.lua: Blizzard's fixed interface words on a named widget (area "ui", ADR-015): a header or a
-- button whose current text is exactly one of the client's own global strings in the UI dictionary. Shared by every
-- window surface (UI/QuestFrame, UI/QuestMap, UI/GameMenu and the other windows, ADR-016), each of which decides
-- which widgets and when (after the client wrote them). A label is matched like a tooltip line (exact word, template
-- such as "Suggested Players [%d]", whitelisted label forms) and anchored, so a composite such as
-- "Learn Spell: (Complete)" is left alone.
-- `opts.only` restricts a widget that may also hold a name (a guild called "Raid" on the friends title) to
-- the keys it can legitimately show; Labels.region finds an unnamed label by the client's English; Labels.dropdown
-- follows a dropdown button's own text writer.
-- The dictionary index (Core/UIStrings) is WFJ.UIIndex, built by Main; without it nothing is shown.
local _, WFJ = ...
local Labels = {}
WFJ.Labels = Labels

local Compat = WFJ.Compat

-- A Button becomes its ButtonText adapter; a FontString is used as is.
function Labels.widget(w)
  if type(w) ~= "table" then return nil end
  local fs = type(w.GetFontString) == "function" and WFJ.ButtonText.of(w) or w
  -- A name can resolve to something that is not a text widget at all (a raid roster name does on Forever), and
  -- calling its GetText would raise and cost the whole surface. Nothing we can read is nothing we can write: treat it
  -- as no widget, which `show` already handles by dropping the record.
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" then return nil end
  return fs
end

-- Widgets no record may ever take (ADR-016): EditBoxes, name widgets and text Blizzard reads back. Each window
-- module lists them by global name in NEVER_TOUCH (a dotted path for a child: "OpenMailSender.Name"); Main registers
-- every list once (Labels.forbidNames), and show() refuses those widgets whatever surface asks.
local forbidden = setmetatable({}, { __mode = "k" })

function Labels.forbid(widget)
  if type(widget) == "table" then forbidden[widget] = true end
end

-- A record key for a pooled widget, which has no id of its own: → a function(widget) → prefix .. n, where n
-- is stable for that widget object for as long as it lives (weak-keyed, so a released frame takes its id with it).
-- Never an index into the pool: a reused row keeps its key and its record follows the new text.
function Labels.keyer(prefix)
  local ids, last = setmetatable({}, { __mode = "k" }), 0
  return function(widget)
    local id = ids[widget]
    if not id then
      last = last + 1
      id = last
      ids[widget] = id
    end
    return prefix .. id
  end
end

-- → the number of names that resolved to a widget.
function Labels.forbidNames(names)
  local n = 0
  for _, name in ipairs(names or {}) do
    local head, rest = name:match("^([^.]+)%.?(.*)$")
    local w = head and Compat.resolve(head)
    for field in rest:gmatch("[^.]+") do w = type(w) == "table" and w[field] or nil end
    if type(w) == "table" then
      Labels.forbid(w)
      n = n + 1
    end
  end
  return n
end

function Labels.forbidden(widget)
  return forbidden[widget] == true
end

-- ADR-042: the `opts` a widget restricted to client-table text families takes: { only = the shipped keys
-- of those families ("FactionDescription", "AchievementTitle", …) }, built from the index's rows once per index.
local familyOpts, familyIndex = {}, nil
-- `extra` (optional): a list of other keys the widget may also show (Labels.familiesWith). → { only = set }
local function familySet(extra, families)
  local index = WFJ.UIIndex
  if familyIndex ~= index then familyOpts, familyIndex = {}, index end
  local id = table.concat(extra or {}, ",") .. "|" .. table.concat(families, "+")
  local opts = familyOpts[id]
  if not opts then
    local set = {}
    for _, key in ipairs(extra or {}) do set[key] = true end
    for _, family in ipairs(families) do
      for key in pairs(WFJ.UIStrings.familyKeys(index and index.rows, family)) do set[key] = true end
    end
    opts = { only = set }
    familyOpts[id] = opts
  end
  return opts
end

function Labels.families(...)
  return familySet(nil, { ... })
end

-- the families' keys and the listed keys (a widget that shows a global string or a table word)
function Labels.familiesWith(extra, ...)
  return familySet(extra, { ... })
end

-- A ScrollingFontTemplate frame's FontString and the refit its own SetText does after writing (the container
-- re-heighted to the text, the scroll box updated; ScrollingFontMixin:SetText, scrolltemplates.lua:347–358), so a
-- longer Japanese scrolls instead of spilling. → fs, refit | nil
function Labels.scrolling(sf)
  if type(sf) ~= "table" or type(sf.GetFontString) ~= "function" then return nil end
  local ok, fs = pcall(sf.GetFontString, sf)
  if not ok or type(fs) ~= "table" then return nil end
  local function refit()
    local okC, container = pcall(sf.GetFontStringContainer, sf)
    if okC and type(container) == "table" and type(container.SetHeight) == "function"
        and type(fs.GetStringHeight) == "function" then
      container:SetHeight(fs:GetStringHeight())
    end
    local okB, box = pcall(sf.GetScrollBox, sf)
    if okB and type(box) == "table" and type(box.FullUpdate) == "function" then pcall(box.FullUpdate, box, true) end
  end
  return fs, refit
end

-- Shows one label as record `recKey` on `surface`. `opts` (optional): { only = { KEY = true, … } | { "KEY", … } }.
-- → 1 when the widget holds a dictionary word (shown or already ours), else 0; and a record from an earlier text on
-- that key is dropped, never restored over the client's text.
function Labels.show(surface, recKey, widget, refit, opts)
  local fs = Labels.widget(widget)
  local index = WFJ.UIIndex
  if not fs or not index or forbidden[widget] or forbidden[fs] then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  local en = fs:GetText()
  -- a secret value (a unit tooltip line in combat) can be neither compared nor matched: the client's line stays
  local isSecret = WFJ.Compat.resolve("issecretvalue")
  if type(isSecret) == "function" and isSecret(en) then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  local rec = WFJ.SurfaceState.get(surface, recKey)
  if rec and rec.fs == fs and rec.applied ~= nil and en == rec.applied then return 1 end -- still our Japanese
  local key, args
  if type(en) == "string" and en ~= "" then
    if opts and opts.only then key, args = index:matchOnly(en, opts.only) else key, args = index:match(en) end
  end
  if not key then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  local ctx = (refit or args) and { refit = refit, args = args } or nil
  WFJ.Render.show(surface, recKey, fs, en, "ui", "ui", key, ctx)
  return 1
end

-- ADR-038: a composite line a surface split itself: a log line with a time suffix, a combat-text trailer, a
-- ready-check line, a list of `|n`-joined permissions. `key` is the record's key (the line's stale / missing state),
-- `args` UIStrings fill args the surface built from index lookups of the pieces (`seq`, `affix`, or the key's own
-- template captures); nil `key` drops the record. Alt, the master switch and the area toggle show the live English
-- exactly as Labels.show does. → 1 when shown (or already ours), else 0
function Labels.showArgs(surface, recKey, widget, key, args, refit)
  local fs = Labels.widget(widget)
  local en = fs and fs:GetText()
  local rec = fs and WFJ.SurfaceState.get(surface, recKey)
  -- still our Japanese: a caller that re-splits it finds no key, which must not turn the line back to English
  if rec and rec.fs == fs and rec.applied ~= nil and en == rec.applied then return 1 end
  if not key or not fs or not WFJ.UIIndex or forbidden[widget] or forbidden[fs] or type(en) ~= "string" or en == "" then
    WFJ.SurfaceState.drop(surface, recKey)
    return 0
  end
  WFJ.Render.show(surface, recKey, fs, en, "ui", "ui", key, { refit = refit, args = args })
  return 1
end

-- One piece of a composite line → { key = , args = } for a `seq` part, or nil when the piece is no entry of
-- `only` (a list or a set of keys).
function Labels.part(text, only)
  local index = WFJ.UIIndex
  if not index or type(text) ~= "string" or text == "" then return nil end
  local key, args = index:matchOnly(text, only)
  return key and { key = key, args = args } or nil
end

-- Shows every { recKey, widget [, opts] } of a list; → the number of dictionary words found.
function Labels.showAll(surface, list, refit)
  local n = 0
  for _, item in ipairs(list) do n = n + Labels.show(surface, item[1], item[2], refit, item[3]) end
  WFJ.Render.updateBanner(surface)
  return n
end

-- An unnamed FontString region of `frame` whose text is the client's English for `key` (or our Japanese for it, once
-- shown), cached per frame and key. → FontString | nil (bank "Item Slots", mail "To:", Prev / Next).
local regionCache = setmetatable({}, { __mode = "k" })
function Labels.region(frame, key)
  if type(frame) ~= "table" or type(frame.GetRegions) ~= "function" then return nil end
  local cache = regionCache[frame]
  if cache and cache[key] then return cache[key] end
  local en = Compat.resolve(key)
  if type(en) ~= "string" or en == "" then return nil end
  for _, region in ipairs({ frame:GetRegions() }) do
    if type(region) == "table" and region.GetObjectType and region:GetObjectType() == "FontString"
        and region:GetText() == en then
      cache = cache or {}
      cache[key] = region
      regionCache[frame] = cache
      return region
    end
  end
  return nil
end

-- A menu element's text: the Menu compositor wraps the FontStrings it attaches and
-- refuses SetFont when it is looked up through that wrapper ("Use of function 'SetFont' is disallowed",
-- blizzard_menu/compositor.lua:166–169, 254–256); it sets them with SetFontObject itself, also on every reuse
-- (:66–74). The adapter calls the client's own FontString SetFont, the method of a plain FontString of ours, on
-- the element, so no global font object is created (CreateFont is never called). One adapter per FontString (weak), so
-- a record keeps its widget identity. → adapter | nil
local menuAdapters = setmetatable({}, { __mode = "k" })
local rawSetFont
local function fontStringSetFont()
  if rawSetFont then return rawSetFont end
  local holder = type(CreateFrame) == "function" and CreateFrame("Frame") or nil
  local sample = holder and holder.CreateFontString and holder:CreateFontString() or nil
  if type(sample) ~= "table" then return nil end
  local mt = getmetatable(sample)
  local index = type(mt) == "table" and mt.__index or nil
  rawSetFont = type(index) == "table" and index.SetFont or sample.SetFont
  return rawSetFont
end
function Labels.menuText(fs)
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" then return nil end
  local a = menuAdapters[fs]
  if a then return a end
  a = {}
  function a.GetText() return fs:GetText() end
  function a.SetText(_, text) fs:SetText(text) end
  function a.GetFont() return fs:GetFont() end
  function a.SetFont(_, path, size, flags)
    local set = fontStringSetFont()
    if type(set) ~= "function" then return false end
    return set(fs, path, size, flags)
  end
  menuAdapters[fs] = a
  return a
end

-- A dropdown button's selection text: the Menu system rewrites `dropdown.Text` in UpdateText on every
-- selection and assignment, so the label is re-shown after each (hooksecurefunc on the instance; dropdown:SetText is
-- a Lua override that writes a Blizzard field and is never called). → 1 | 0 for the current text.
-- `opts` (optional): Labels.show's { only = … } for a dropdown whose selection may be a name (ClubFinder's
-- spec / class selection); Trainer and Friends pass none.
local dropdownHooked = setmetatable({}, { __mode = "k" })
function Labels.dropdown(surface, recKey, dropdown, opts)
  if type(dropdown) ~= "table" or type(dropdown.Text) ~= "table" then return 0 end
  if not dropdownHooked[dropdown] and type(dropdown.UpdateText) == "function" then
    dropdownHooked[dropdown] = true
    hooksecurefunc(dropdown, "UpdateText", function(self) Labels.show(surface, recKey, self.Text, nil, opts) end)
  end
  return Labels.show(surface, recKey, dropdown.Text, nil, opts)
end

-- A window title written with `frame:SetTitle(text)`: the mainline PortraitFrame / ButtonFrame templates
-- write `frame.TitleContainer.TitleText` (blizzard_sharedxml/portraitframe.lua:11–13), and a window re-titles itself
-- whenever it likes, so the title is re-shown after each SetTitle (hooksecurefunc on the instance, once). `opts` is
-- Labels.show's (`only` for a window whose title can also be a name). A frame without TitleContainer or SetTitle:
-- nothing is hooked and 0 is returned. → 1 | 0 for the current title.
-- One surface owns a frame's title: the SetTitle hook is installed once, with the first caller's surface, `opts` and
-- record key; a later caller for the same frame only re-shows the current title under its own arguments.
local titleHooked = setmetatable({}, { __mode = "k" })
function Labels.title(surface, frame, opts, recKey)
  if type(frame) ~= "table" then return 0 end
  local container = frame.TitleContainer
  local text = type(container) == "table" and container.TitleText or nil
  if type(text) ~= "table" then return 0 end
  recKey = recKey or "title"
  if not titleHooked[frame] and type(frame.SetTitle) == "function" then
    titleHooked[frame] = true
    hooksecurefunc(frame, "SetTitle", function() Labels.show(surface, recKey, text, nil, opts) end)
  end
  return Labels.show(surface, recKey, text, nil, opts)
end
