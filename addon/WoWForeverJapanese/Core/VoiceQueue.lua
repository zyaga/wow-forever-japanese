-- Core/VoiceQueue.lua: the order voice lines play in while the voice panel is on, and the panel's choices (ADR-063).
-- Pure tables: no frames, no sound calls. UI/VoicePlayer plays the head; UI/VoicePanel draws it.
--   * The head (items[1]) is the line playing, or paused; the rest wait their turn.
--   * A line already queued (same pack key) is not added again.
--   * `opt` reads the player's choices from Core/Settings (voice.panel.*) and keeps the panel's position, and the
--     size it had before Off, in WFJ_DB.voicePanel.
local _, WFJ = ...
local Q = {}
WFJ.VoiceQueue = Q

Q.items = {}
Q.paused = false

local S = function() return WFJ.Settings end
local saved = {} -- WFJ_DB.voicePanel: { point = { point, relativePoint, x, y } once dragged, lastSize }

local function flag(id)
  return { get = function() return S().get(id) end, set = function(v) S().set(id, v and true or false) end }
end
local function word(id, yes, no)
  return { get = function() return S().get(id) and yes or no end, set = function(v) S().set(id, v == yes) end }
end
-- look number → { strip, parchment }: 1 Full Dark, 3 Strip Dark, 4 Full Parchment, 5 Strip Parchment
local LOOK_OF = { [1] = { false, false }, [3] = { true, false }, [4] = { false, true }, [5] = { true, true } }

-- `opt` key → its setting
Q.MAPPED = {
  -- Panel size Off switches the panel off; switching it on again brings back the size it had
  on = {
    get = function() return S().get("voice.panel.size") ~= "off" end,
    set = function(v)
      local size = S().get("voice.panel.size")
      if not v then
        if size ~= "off" then saved.lastSize = size end
        S().set("voice.panel.size", "off")
      elseif size == "off" then
        S().set("voice.panel.size", saved.lastSize or "full")
      end
    end,
  },
  keepPlaying = flag("voice.panel.keep"),
  head = flag("voice.panel.head"),
  combat = flag("voice.panel.combatDim"),
  locked = flag("voice.panel.lock"),
  buttons = word("voice.panel.hoverButtons", "hover", "always"),
  idle = word("voice.panel.fade", "fade", "stay"),
  textOpens = word("voice.panel.questLog", "quest", "window"),
  look = {
    get = function()
      local strip, parchment = S().get("voice.panel.size") == "strip", S().get("voice.panel.style") == "parchment"
      return strip and (parchment and 5 or 3) or (parchment and 4 or 1)
    end,
    set = function(n)
      local pair = LOOK_OF[n]
      if not pair then return end
      if S().get("voice.panel.size") ~= "off" then S().set("voice.panel.size", pair[1] and "strip" or "full") end
      S().set("voice.panel.style", pair[2] and "parchment" or "dark")
    end,
  },
}

Q.opt = setmetatable({}, {
  __index = function(_, k)
    local m = Q.MAPPED[k]
    if m then return m.get() end
    return saved[k]
  end,
  __newindex = function(_, k, v)
    local m = Q.MAPPED[k]
    if m then m.set(v) else saved[k] = v end
  end,
})

-- The earlier panel builds' choices, carried into the settings once and then dropped: their switches for on / off,
-- strip and parchment became the two dropdowns; the waiting-list and readings switches and the tuning values are gone.
local RETIRED_SETTINGS = { "voice.panel", "voice.panel.strip", "voice.panel.parchment", "voice.panel.queueBox",
  "voice.panel.ruby" }
local RETIRED_SAVED = { "on", "keepPlaying", "look", "buttons", "queue", "idle", "idleDelay", "combat", "combatAlpha",
  "head", "zoom", "cam", "page", "textOpens", "scale", "locked", "textSize", "rubyInline" }

local function carryOver(db)
  local st = type(db.settings) == "table" and db.settings or {}
  if st["voice.panel.strip"] ~= nil or st["voice.panel.parchment"] ~= nil or st["voice.panel"] ~= nil then
    local size = st["voice.panel.strip"] and "strip" or "full"
    if st["voice.panel"] == false then saved.lastSize, size = size, "off" end
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
  if type(db.voicePanel) ~= "table" then db.voicePanel = {} end
  saved = db.voicePanel
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
