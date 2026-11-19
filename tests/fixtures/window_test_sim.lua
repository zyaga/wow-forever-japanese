
-- A stand-in client for the window test's sweep (tests/python/test_window_test.py runs the generated sweep
-- between this file's two halves): one window with an achievement-style category list (a few rows reused for many entries, one
-- category open at a time, more entries than fit), three tabs, a Delete button and a checkbox; and Japanese text
-- in the client's own face (a label, a typing box, an HTML box) beside Japanese in the addon's bundled face.
local frames, created, log = {}, {}, {}
UIParent, WorldFrame = { name = "UIParent" }, { name = "WorldFrame" }
local function region(owner, text)
  return { GetObjectType = function() return "FontString" end, GetText = function() return text() end,
    IsVisible = function() return owner:IsVisible() end, GetDebugName = function() return owner.name .. ".Label" end,
    GetFont = function() return owner.font or "Fonts\\FRIZQT__.TTF", 12, "" end }
end
local function frame(name, parent, kind)
  local f = { name = name, parent = parent, kind = kind or "Frame", shown = true, enabled = true, top = 0, left = 0 }
  function f:IsForbidden() return false end
  function f:IsProtected() return false end
  function f:IsShown() return self.shown end
  function f:IsVisible() local n = self; while n and n ~= UIParent do if not n.shown then return false end n = n.parent end return true end
  function f:IsEnabled() return self.enabled end
  function f:GetObjectType() return self.kind end
  function f:GetDebugName() return self.name end
  function f:GetParent() return self.parent end
  function f:GetRegions() if self.label then return region(self, self.label) end end
  function f:GetText() return self.text end
  function f:GetFont(textType) return self.font or "Fonts\\FRIZQT__.TTF", 12, textType end
  function f:GetTextData() return self.paragraphs end
  function f:GetScript(which) return which == "OnClick" and self.click or nil end
  function f:GetTop() return self.top end
  function f:GetLeft() return self.left end
  function f:Click() log[#log + 1] = self.name:gsub("b%x+", "*") .. "=" .. tostring(self.label and self.label() or self.text or ""); self.click(self) end
  function f:Hide() self.shown = false end
  frames[#frames + 1] = f
  return f
end
function EnumerateFrames(prev)
  if not prev then return frames[1] end
  for i, f in ipairs(frames) do if f == prev then return frames[i + 1] end end
end
function CreateFrame() local f = { SetScript = function(self, _, fn) self.update = fn end, RegisterEvent = function() end,
  UnregisterAllEvents = function() end }; created[#created + 1] = f; return f end
function InCombatLockdown() return false end
function GetBuildInfo() return "12.1.5", "70961" end
SlashCmdList = {}
local saved = {}
local function probeDb() return saved end

-- the window
local window = frame("FakeFrame", UIParent); window.shown = false
local entries = { { "Summary" }, { "Characters" }, { "Quests", { "Eastern Kingdoms", "Kalimdor", "Outland" } }, { "Exploration", { "Azeroth", "Draenor" } },
  { "Housing" }, { "Delves" }, { "Player vs. Player", { "Arena", "Battlegrounds" } }, { "Dungeons & Raids" }, { "Professions" }, { "Reputation" } }
local open, offset, ROWS = nil, 0, 6
local function flat()
  local out = {}
  for _, e in ipairs(entries) do
    out[#out + 1] = { e[1], e }
    if open == e and e[2] then for _, c in ipairs(e[2]) do out[#out + 1] = { c } end end
  end
  return out
end
local box = frame("FakeFrameCategories.ScrollBox", window)
function box:SetScrollPercentage(p) offset = math.floor(p * math.max(0, #flat() - ROWS) + 0.5) end
function box:GetScrollPercentage() local extra = #flat() - ROWS; return extra <= 0 and 0 or offset / extra end
function box:HasScrollableExtent() return #flat() > ROWS end
-- the pool hands rows out in an order of its own, as the client's does
local order = { 4, 1, 6, 2, 5, 3 }
for slot = 1, ROWS do
  local row = frame("FakeFrameCategories.ScrollBox.ScrollTarget.9910000" .. slot .. "0", box)
  local button = frame(row.name .. ".Button", row, "Button")
  local function entry() return flat()[offset + order[slot]] end
  button.label = function() local e = entry(); return e and e[1] or "" end
  function button:IsVisible() return window.shown and entry() ~= nil end
  function button:GetTop() return 500 - order[slot] * 20 end
  button.click = function() local e = entry(); if e and e[2] then open = (open ~= e[2]) and e[2] or nil; offset = math.min(offset, math.max(0, #flat() - ROWS)) end end
end
for i = 1, 3 do local tab = frame("FakeFrameTab" .. i, window, "Button"); tab.text = "Tab " .. i; tab.top = 0; tab.left = i * 80; tab.click = function() end; tab.enabled = i ~= 1 end
local delete = frame("FakeFrame.DeleteButton", window, "Button"); delete.text = "Delete"; delete.click = function() error("the Delete button was clicked") end
local check = frame("FakeFrame.ShowAll", window, "CheckButton"); check.click = function() error("a checkbox was clicked") end
local hud = frame("ActionButton1", UIParent, "Button"); hud.click = function() error("a button outside the window was clicked") end
local CLIENT_FACE, BUNDLED_FACE = "Fonts\\FRIZQT__.TTF", "Interface\\AddOns\\WoWForeverJapanese\\Fonts\\ipagui.ttf"
local motd = frame("FakeFrame.Motd", window); motd.label = function() return "ギルドへようこそ" end; motd.font = CLIENT_FACE
local ours = frame("FakeFrame.Ours", window); ours.label = function() return "ギルド情報" end; ours.font = BUNDLED_FACE
local plain = frame("FakeFrame.Plain", window); plain.label = function() return "Welcome to the guild" end; plain.font = CLIENT_FACE
local note = frame("FakeFrame.NoteBox", window, "EditBox"); note.text = "よろしく"; note.font = CLIENT_FACE
local typed = frame("FakeFrame.ChatBox", window, "EditBox"); typed.text = "こんにちは"; typed.font = BUNDLED_FACE
local html = frame("FakeFrame.Html", window, "SimpleHTML"); html.font = CLIENT_FACE
html.paragraphs = { { text = "Raid at nine", type = "P" }, { text = "九時に集合", type = "P" } }
function ToggleAchievementFrame() window.shown = true end
function CloseAllWindows() window.shown = false end

--[[SWEEP]]
SlashCmdList.WFJLIVE()
for _ = 1, 20000 do
  local busy = false
  for _, f in ipairs(created) do if f.update then busy = true; f.update() end end
  if not busy then break end
end
local seenEntry, twice = {}, {}
for _, line in ipairs(log) do
  local what = line:match("=(.*)$")
  if seenEntry[what] then twice[#twice + 1] = what end
  seenEntry[what] = true
  print(line)
end
local missed = {}
for _, e in ipairs(entries) do
  if not seenEntry[e[1]] then missed[#missed + 1] = e[1] end
  for _, c in ipairs(e[2] or {}) do if not seenEntry[c] then missed[#missed + 1] = c end end
end
local boxes = {}
for name, font in pairs(saved.live and saved.live.achievements and saved.live.achievements.boxes or {}) do
  boxes[#boxes + 1] = "boxed " .. name .. " | " .. font
end
table.sort(boxes)
for _, line in ipairs(boxes) do print(line) end
print("list left at " .. offset)
print("clicked " .. #log .. " | twice: " .. table.concat(twice, ", ") .. " | missed: " .. table.concat(missed, ", "))
