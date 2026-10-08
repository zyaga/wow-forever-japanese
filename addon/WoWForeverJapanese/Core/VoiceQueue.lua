-- Core/VoiceQueue.lua: the order voice lines play in while the voice panel is on, and the panel's choices.
-- Pure tables: no frames, no sound calls. UI/VoicePlayer plays the head; UI/VoicePanel draws it.
--   * The head (items[1]) is the line playing, or paused; the rest wait their turn.
--   * A line already queued (same pack key) is not added again.
--   * `opt` is the panel's saved choices, WFJ_DB.voicePanel. Every choice is switched with /wfj panel.
local _, WFJ = ...
local Q = {}
WFJ.VoiceQueue = Q

Q.items = {}
Q.paused = false

-- The panel's choices and where it sits. Defaults are the starting recommendation; missing keys are filled at load.
Q.DEFAULTS = {
  on = true, -- the panel and the queue; off = one line at a time, stopped with its window
  keepPlaying = true, -- a line keeps playing after its window closes
  look = 1, -- 1 the client's talking-head art · 2 parchment · 3 a strip
  buttons = "hover", -- "hover" | "always"
  queue = "count", -- "count" (+N beside the name, the list on hover) | "box" (an up-next box above the panel)
  idle = "fade", -- "fade" (out after the last line) | "stay"
  idleDelay = 3, -- seconds before the fade starts
  combat = true, -- lower the panel's alpha in combat
  combatAlpha = 0.4,
  head = true, -- the speaker's 3D head
  zoom = 1, -- PlayerModel:SetPortraitZoom
  cam = 1, -- PlayerModel:SetCamDistanceScale
  ruby = "off", -- "off" | "inline" (reading in brackets after the word) | "above" (a small row over the word)
  page = "sentence", -- "sentence" (paged in step with the audio) | "all" (the whole line at once)
  textOpens = "quest", -- the text button: "quest" (the quest in the quest log when it is there, else the window)
                       -- | "window" (always the panel's own full-text window)
  scale = 1,
  locked = false,
  point = nil, -- { point, relativePoint, x, y } once dragged; nil = bottom centre
}

Q.opt = {}
for k, v in pairs(Q.DEFAULTS) do Q.opt[k] = v end

-- The choices players set on the Voice settings page live in Core/Settings (voice.panel.*): each maps a key of
-- `opt` to its setting. get/set translate between the two; the rest stay in db.voicePanel (tuning, position).
local S = function() return WFJ.Settings end
local function flag(id)
  return { get = function() return S().get(id) end, set = function(v) S().set(id, v and true or false) end }
end
local function word(id, yes, no)
  return { get = function() return S().get(id) and yes or no end, set = function(v) S().set(id, v == yes) end }
end
local LOOK_OF = { [1] = { false, false }, [3] = { true, false }, [4] = { false, true }, [5] = { true, true } }
local saved = {}
Q.MAPPED = {
  -- the size dropdown: off switches the panel off; switching it on again brings back the last size
  on = {
    get = function() return S().get("voice.panel.size") ~= "off" end,
    set = function(v)
      if not v then
        local size = S().get("voice.panel.size")
        if size ~= "off" then saved.lastSize = size end
        S().set("voice.panel.size", "off")
      elseif S().get("voice.panel.size") == "off" then
        S().set("voice.panel.size", saved.lastSize or "full")
      end
    end,
  },
  keepPlaying = flag("voice.panel.keep"),
  head = flag("voice.panel.head"),
  combat = flag("voice.panel.combatDim"),
  locked = flag("voice.panel.lock"),
  buttons = word("voice.panel.hoverButtons", "hover", "always"),
  queue = word("voice.panel.queueBox", "box", "count"),
  idle = word("voice.panel.fade", "fade", "stay"),
  textOpens = word("voice.panel.questLog", "quest", "window"),
  -- readings above the words is on the page; readings in brackets after them stays a /wfj panel choice
  ruby = {
    get = function() return S().get("voice.panel.ruby") and "above" or (saved.rubyInline and "inline" or "off") end,
    set = function(v) saved.rubyInline = v == "inline" or nil; S().set("voice.panel.ruby", v == "above") end,
  },
  -- full / strip × dark / parchment
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

-- `db` is WFJ_DB: the unmapped choices live in db.voicePanel and survive /reload. A choice the trial kept there
-- before it moved to the settings page is carried over once.
function Q.init(db)
  if type(db) ~= "table" then return end
  if type(db.voicePanel) ~= "table" then db.voicePanel = {} end
  saved = db.voicePanel
  for k, v in pairs(Q.DEFAULTS) do
    if saved[k] == nil and not Q.MAPPED[k] then saved[k] = v end
  end
  local carry = {}
  for k in pairs(Q.MAPPED) do
    if saved[k] ~= nil then carry[k], saved[k] = saved[k], nil end
  end
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
  for k, v in pairs(carry) do pcall(Q.MAPPED[k].set, v) end
  -- the on / off, strip and parchment switches of an earlier trial build became the two dropdowns: carried over once
  local st = type(db.settings) == "table" and db.settings or {}
  if st["voice.panel.strip"] ~= nil or st["voice.panel.parchment"] ~= nil or st["voice.panel"] ~= nil then
    local size = st["voice.panel.strip"] and "strip" or "full"
    if st["voice.panel"] == false then saved.lastSize, size = size, "off" end
    pcall(S().set, "voice.panel.size", size)
    if st["voice.panel.parchment"] ~= nil then
      pcall(S().set, "voice.panel.style", st["voice.panel.parchment"] and "parchment" or "dark")
    end
    st["voice.panel.strip"], st["voice.panel.parchment"], st["voice.panel"] = nil, nil, nil
  end
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
