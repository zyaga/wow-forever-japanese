-- UI/TextWatch.lua: follows a Blizzard FontString's text from this addon's own frame, for a surface whose writer runs
-- inside one of Blizzard's own passes (the spellbook's page fill). A post-hook on that writer would run this addon's
-- code, and its text and font writes, in the middle of the pass, and the rest of the pass would carry this addon's
-- taint (docs/architecture/client-limits.md, ADR-058). A watched FontString is read once a frame instead, while it
-- is visible, and its callback runs when the text or the font changed since the last look, after Blizzard's pass
-- has ended. The watch itself never writes; the callback is the surface's own show function.
local _, WFJ = ...
local TextWatch = {}
WFJ.TextWatch = TextWatch

local entries = {} -- { fs, fn, text, font }
local byFs = setmetatable({}, { __mode = "k" })
local driver

local function secret(value)
  local isSecret = WFJ.Compat.resolve("issecretvalue")
  return type(isSecret) == "function" and isSecret(value) and true or false
end

local function fontOf(fs)
  if type(fs.GetFont) ~= "function" then return nil end
  local path = fs:GetFont()
  return path
end

-- One entry: runs its callback when its text or font changed. → true when the callback ran
local function check(e)
  local fs = e.fs
  if type(fs.IsVisible) == "function" and not fs:IsVisible() then return false end
  local text = fs:GetText()
  if secret(text) then return false end
  local font = fontOf(fs)
  if text == e.text and font == e.font then return false end
  pcall(e.fn)
  e.text, e.font = fs:GetText(), fontOf(fs)
  return true
end

-- One pass over every entry. → the number of callbacks run
function TextWatch.tick()
  local n = 0
  for _, e in ipairs(entries) do
    if check(e) then n = n + 1 end
  end
  return n
end

-- Follows `fs`: `fn()` runs on the next frame it is visible with a text or font it has not been seen with.
-- A FontString is watched once; a second add replaces its callback. → true when added now
function TextWatch.add(fs, fn)
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" or type(fn) ~= "function" then return false end
  local e = byFs[fs]
  if e then
    e.fn = fn
    return false
  end
  e = { fs = fs, fn = fn }
  byFs[fs] = e
  entries[#entries + 1] = e
  if not driver then
    local create = WFJ.Compat.resolve("CreateFrame")
    if type(create) == "function" then
      driver = create("Frame")
      driver:SetScript("OnUpdate", TextWatch.tick)
    end
  end
  return true
end

function TextWatch.watching(fs)
  return byFs[fs] ~= nil
end

function TextWatch.count()
  return #entries
end
