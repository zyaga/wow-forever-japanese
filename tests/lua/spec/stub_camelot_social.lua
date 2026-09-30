-- Camelot-shaped building blocks for the social / group windows' specs (group finder, channels, quick join,
-- recent allies, recruit-a-friend, report, help, support notices, party pose, toasts). Each spec replays its own
-- window from the Forever client source; this file only holds what they share: loading the addon with a dictionary,
-- nested parentKey frames, a Menu-style dropdown button, a frame pool, and the tooltip / record helpers.
-- The client's own writes go to `fs.text` (or `button.fontString.text`), so a spec can tell them from the addon's.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local S = {}

-- The UI files plus a spec's own module(s), in TOC order.
function S.files(...)
  local files = {}
  for i, f in ipairs(H.UI_FILES) do files[i] = f end
  for _, f in ipairs({ ... }) do files[#files + 1] = f end
  return files
end

-- Installs the stub and loads the addon over `ui` = { KEY = { English, Japanese } }. `args` (optional) are
-- Core/UIStrings ARGS / LABELS entries the spec needs: they are set only where the shared file does not have
-- them, so the spec exercises the real entry where there is one. → WFJ
function S.load(files, ui, args)
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  Stub.installTooltipAPI()
  local WFJ = H.loadChunks(files)
  for key, kinds in pairs(args and args.ARGS or {}) do
    if WFJ.UIStrings.ARGS[key] == nil then WFJ.UIStrings.ARGS[key] = kinds end
  end
  for key, form in pairs(args and args.LABELS or {}) do
    if WFJ.UIStrings.LABELS[key] == nil then WFJ.UIStrings.LABELS[key] = form end
  end
  H.uiSetup(WFJ, ui)
  return WFJ
end

function S.teardown(names)
  H.uiTeardown()
  Stub.keys.alt = false
  for _, name in ipairs(names or {}) do _G[name] = nil end
end

function S.alt(WFJ, down)
  Stub.keys.alt = down
  WFJ.Modifier.refresh()
end

-- → true when no surface holds a record on `widget` (a name the addon must never take).
function S.unrecorded(WFJ, widget)
  for _, bucket in pairs(WFJ.SurfaceState.surfaces()) do
    for _, rec in pairs(bucket) do
      if rec.fs == widget or (type(rec.fs) == "table" and rec.fs.button == widget) then return false end
    end
  end
  return true
end

function S.en(key) return _G[key] end
function S.fs(text) return Stub.fontString(text or "") end
function S.button(name, text) return Stub.button(name, text or "") end

-- The client's own write to a FontString or a Stub.button.
function S.write(widget, text)
  if widget.fontString then widget.fontString.text = text else widget.text = text end
end

-- A frame (global when `name` is given) whose `.name` labels its hooks in Stub.hooks ("<name>:<Method>").
function S.frame(name, label)
  local f = CreateFrame("Frame", name)
  f.name = name or label
  return f
end

-- Sets `value` at a dotted parentKey path under `root`, creating the frames in between. → value
function S.put(root, path, value)
  local node = root
  local keys = {}
  for key in path:gmatch("[^.]+") do keys[#keys + 1] = key end
  for i = 1, #keys - 1 do
    if node[keys[i]] == nil then node[keys[i]] = S.frame(nil, keys[i]) end
    node = node[keys[i]]
  end
  node[keys[#keys]] = value
  return value
end

-- A Menu-system dropdown button (DropdownSelectionTextMixin, blizzard_menu/menutemplates.lua:703–782): SetText /
-- SetDefaultText / OverrideText all end in UpdateText, which writes `.Text`.
function S.dropdown(label)
  local d = S.frame(nil, label)
  d.Text = S.fs("")
  function d.UpdateText(self) self.Text.text = self.text or self.defaultText or "" end
  function d.SetDefaultText(self, text) self.defaultText = text; self:UpdateText() end
  function d.OverrideText(self, text) self.text = text; self:UpdateText() end
  function d.SetSelectionText(self, text) self.text = text; self:UpdateText() end
  return d
end

-- A CreateFramePool-like pool: Acquire / ReleaseAll / EnumerateActive.
function S.pool(create)
  local p = { active = {}, inactive = {} }
  function p.Acquire(self)
    local f = table.remove(self.inactive) or create()
    self.active[#self.active + 1] = f
    return f
  end
  function p.ReleaseAll(self)
    for _, f in ipairs(self.active) do self.inactive[#self.inactive + 1] = f end
    self.active = {}
  end
  function p.EnumerateActive(self)
    local i = 0
    return function()
      i = i + 1
      if self.active[i] then return self.active[i], true end
    end
  end
  return p
end

-- Builds GameTooltip the way a Blizzard OnEnter does: SetOwner, the lines ({ left [, right] } or a string), Show.
-- → the left texts after the addon's walk
function S.tooltip(owner, lines)
  local tt = _G.GameTooltip
  tt:SetOwner(owner)
  tt:ClearLines()
  for _, line in ipairs(lines) do
    if type(line) == "table" then tt:AddDoubleLine(line[1], line[2]) else tt:AddLine(line) end
  end
  tt:Show()
  local out = {}
  for i = 1, #lines do out[i] = _G["GameTooltipTextLeft" .. i]:GetText() end
  return out
end

function S.tooltipRight(i) return _G["GameTooltipTextRight" .. i]:GetText() end

return S
