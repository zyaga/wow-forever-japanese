-- Core/VoiceQueue.lua: the order voice lines play in while the voice panel is on, and the panel's choices (ADR-063).
-- Pure tables: no frames, no sound calls. UI/VoicePlayer plays the head; UI/VoicePanel draws it.
--   * The head (items[1]) is the line playing, or paused; the rest wait their turn.
--   * A line already queued (same pack key) is not added again.
--   * `opt` reads the player's choices from Core/Settings (voice.panel.*), read-only: the settings page and
--     `/wfj voice.panel.*` change them. It keeps one thing of its own: where the panel was dragged to,
--     WFJ_DB.voicePanel.point, created the first time it is set.
local _, WFJ = ...
local Q = {}
WFJ.VoiceQueue = Q

Q.items = {}
Q.paused = false

local S = function() return WFJ.Settings end
local saved = {} -- WFJ_DB.voicePanel, once it exists
local savedDb -- WFJ_DB

-- `opt` key → how it reads its setting
local function flag(id) return function() return S().get(id) end end
local function word(id, yes, no) return function() return S().get(id) and yes or no end end
Q.MAPPED = {
  on = function() return S().get("voice.panel.size") ~= "off" end, -- Panel size Off switches the panel off
  keepPlaying = flag("voice.panel.keep"),
  head = flag("voice.panel.head"),
  combat = flag("voice.panel.combatDim"),
  locked = flag("voice.panel.lock"),
  buttons = word("voice.panel.hoverButtons", "hover", "always"),
  idle = word("voice.panel.fade", "fade", "stay"),
  textOpens = word("voice.panel.questLog", "quest", "window"),
  -- 1 Full Dark, 3 Strip Dark, 4 Full Parchment, 5 Strip Parchment (UI/VoicePanelLooks)
  look = function()
    local strip, parchment = S().get("voice.panel.size") == "strip", S().get("voice.panel.style") == "parchment"
    return strip and (parchment and 5 or 3) or (parchment and 4 or 1)
  end,
}

Q.opt = setmetatable({}, {
  __index = function(_, k)
    local m = Q.MAPPED[k]
    if m then return m() end
    return saved[k]
  end,
  __newindex = function(_, k, v)
    assert(not Q.MAPPED[k], "VoiceQueue.opt." .. tostring(k) .. " is a setting: set voice.panel.* instead")
    if v == nil and saved[k] == nil then return end -- nothing to clear: no saved table for nothing
    saved[k] = v
    if savedDb and savedDb.voicePanel ~= saved then savedDb.voicePanel = saved end
  end,
})

-- The earlier panel builds' choices, carried into the settings once and then dropped: their switches for on / off,
-- strip and parchment became the two dropdowns; the waiting-list and readings switches and the tuning values are gone.
local RETIRED_SETTINGS = { "voice.panel", "voice.panel.strip", "voice.panel.parchment", "voice.panel.queueBox",
  "voice.panel.ruby" }
local RETIRED_SAVED = { "on", "keepPlaying", "look", "buttons", "queue", "idle", "idleDelay", "combat", "combatAlpha",
  "head", "zoom", "cam", "page", "textOpens", "scale", "locked", "textSize", "rubyInline", "lastSize" }

local function carryOver(db)
  local st = type(db.settings) == "table" and db.settings or {}
  if st["voice.panel.strip"] ~= nil or st["voice.panel.parchment"] ~= nil or st["voice.panel"] ~= nil then
    local size = st["voice.panel"] == false and "off" or (st["voice.panel.strip"] and "strip" or "full")
    pcall(S().set, "voice.panel.size", size)
    if st["voice.panel.parchment"] ~= nil then
      pcall(S().set, "voice.panel.style", st["voice.panel.parchment"] and "parchment" or "dark")
    end
  end
  for _, id in ipairs(RETIRED_SETTINGS) do st[id] = nil end
  for _, k in ipairs(RETIRED_SAVED) do saved[k] = nil end
end

-- `db` is WFJ_DB (after Settings.load).
function Q.init(db)
  if type(db) ~= "table" then return end
  savedDb = db
  saved = type(db.voicePanel) == "table" and db.voicePanel or {}
  carryOver(db)
end

function Q.size() return #Q.items end
function Q.current() return Q.items[1] end
function Q.waiting() return math.max(#Q.items - 1, 0) end

function Q.has(key)
  for _, it in ipairs(Q.items) do
    if it.key == key then return true end
  end
  return false
end

-- → true when added at the end
function Q.push(item)
  if Q.has(item.key) then return false end
  Q.items[#Q.items + 1] = item
  return true
end

-- Puts `item` at the head (a replay), dropping any other copy of it.
function Q.front(item)
  for i = #Q.items, 1, -1 do
    if Q.items[i].key == item.key then table.remove(Q.items, i) end
  end
  table.insert(Q.items, 1, item)
end

-- → the head, removed
function Q.pop()
  return table.remove(Q.items, 1)
end

-- Drops every line shown in `window`. → whether the head was one of them
function Q.dropWindow(window)
  local head = Q.items[1]
  for i = #Q.items, 1, -1 do
    if Q.items[i].window == window then table.remove(Q.items, i) end
  end
  return head ~= nil and head.window == window
end

function Q.clear()
  Q.items = {}
  Q.paused = false
end
