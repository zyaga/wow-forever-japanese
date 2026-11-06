-- UI/DialogueUIFrames.lua: the Dialogue UI addon's other frames with game text, when the player has that addon
-- (ADR-073): its item tooltip, the chat panel in its window and its quest popups. Dialogue UI makes them with no name,
-- so they are told apart by their own members; a scan finds the ones made since the last scan. Each wrapper calls the
-- original every time, and anything that fails leaves Dialogue UI's English (UI/DialogueUI's guard and error limit).
local _, WFJ = ...
local Frames = {}
WFJ.DialogueUIFrames = Frames

local Compat = WFJ.Compat
local patched = setmetatable({}, { __mode = "k" }) -- frames whose writers are wrapped
local function guarded(...) return WFJ.DialogueUI.guarded(...) end

-- ── Dialogue UI's tooltip ──────────────────────────────────────────────────
-- Dialogue UI draws item and reward tooltips in a frame of its own, made at its load with no name; a scan finds it by
-- its members (its two line writers and its update) [read: Dialogue UI 1.0.7 b, Code/Tooltip/Tooltip_Base.lua]. A
-- line after the first (the first is the item's name, which stays English) that is one of the client's interface
-- strings ("Quest Item", "Item Level 14", "+3 Item Level") gets its Japanese in the bundled face. An item's effect
-- lines (Use:, Equip:) stay English here.
-- Dialogue UI's own tooltip words (its comparison toggle and the line naming the item a reward would replace), in the
-- addon's own Japanese, as UI/DialogueUI gives the headings Dialogue UI writes itself.
local OWN_TIP_WORDS = { ["Show Comparison"] = "比較を表示", ["Hide Comparison"] = "比較を隠す" }
local REPLACE, REPLACE_JA = "Replace", "交換:"

-- One tooltip line the client wrote (or Dialogue UI built from the client's strings) → its Japanese | nil, matched the
-- way the addon's own tooltip lines are (UI/Tooltip: a template with its values, a coloured stat change).
local function tipText(text)
  local index, T = WFJ.UIIndex, WFJ.Tooltip
  if not index or type(text) ~= "string" or text == "" then return nil end
  local S_ = WFJ.State
  local own = S_ and S_.enabled and not S_.modifierHeld and S_.areaEnabled("ui")
  if OWN_TIP_WORDS[text] then return own and OWN_TIP_WORDS[text] or nil end
  -- "Replace <item link>", the word possibly in its own colour
  local at, stop = text:find(REPLACE, 1, true)
  if at then
    local before, rest = text:sub(1, at - 1), text:sub(stop + 1)
    local coloured = before == "" or before:match("^|c%x%x%x%x%x%x%x%x$")
    -- only before an item link: a description that starts with the word is left alone
    if coloured and (rest:sub(1, 1) == " " or rest:sub(1, 3) == "|r ") and rest:find("|Hitem:", 1, true) then
      return own and (before .. REPLACE_JA .. rest) or nil
    end
  end
  -- the sell price: the client's word, two spaces, then the coins
  local sell = Compat.resolve("SELL_PRICE")
  if type(sell) == "string" and text:sub(1, #sell + 2) == sell .. "  " then
    local ja = WFJ.DialogueUI.preview(sell, "ui", "ui", "SELL_PRICE")
    return ja and (ja .. text:sub(#sell + 1)) or nil
  end
  local key, args, runs
  if T and type(T.matchColoured) == "function" then key, args, runs = T.matchColoured(index, text) end
  if not key and T and type(T.matchStatChange) == "function" then key, args = T.matchStatChange(index, text) end
  if not key then
    local exact = WFJ.DialogueUI.gameWord(text) -- the plain match, even without UI/Tooltip's matchers
    if exact then return exact end
    -- a change Dialogue UI writes itself ("+3 Item Level", the number in its colour): "<Japanese> +3", as the client's
    -- own stat changes show
    local bare = WFJ.UIStrings.stripColour(text)
    local name = bare:match("^[%+%-][%d%.,]+ (.+)$")
    if not name or text:sub(-#name - 1) ~= " " .. name then return nil end
    local ja = WFJ.DialogueUI.gameWord(name)
    return ja and (ja .. " " .. text:sub(1, #text - #name - 1)) or nil
  end
  local ja, _, action = WFJ.Render.preview("dialogueui.rows", text, nil, "ui", "ui", key,
    { args = args, runColours = runs, compact = true })
  if action == "apply" and type(ja) == "string" then return ja end
  return nil
end

local function tooltipLine(self, text)
  if (self.numLines or 0) < 1 or type(text) ~= "string" then return nil end -- the first line is the item's name
  return tipText(text)
end

local function wrapAdd(tip, method, translate)
  local add = tip[method]
  if type(add) ~= "function" then return end
  tip[method] = function(self, text, ...)
    local ja
    if WFJ.DialogueUI.active() then
      local ok, t = guarded(translate, self, text)
      ja = ok and t or nil
    end
    local fs = add(self, ja or text, ...)
    if type(fs) == "table" then
      guarded(WFJ.DialogueUI.face, fs, nil, ja ~= nil)
      -- the tooltip sizes itself again a frame later when told a line's face changed [read: Tooltip_Base.lua, Show]
      if ja then self.fontChanged = true end
    end
    return fs
  end
end

local tips = setmetatable({}, { __mode = "k" }) -- Dialogue UI's tooltips found
local popupTitle = setmetatable({}, { __mode = "k" }) -- popup → the English name it was last given

local function wrapTooltip(tip)
  tips[tip] = true
  wrapAdd(tip, "AddLeftLine", tooltipLine)
  wrapAdd(tip, "AddRightLine", function(_, text) return tipText(text) end) -- "Cloth", "Mail"
end

-- ── Dialogue UI's chat panel ───────────────────────────────────────────────
-- While its window is open Dialogue UI repeats what NPCs say, yell and emote in a chat panel of its own (an unnamed
-- frame [read: Dialogue UI 1.0.7 b, Code/Dialogue/ChatFrame.lua]). A line gets the Japanese the chat window shows
-- (UI/Speech), in the bundled face set on the panel's font object (the panel measures its lines through it). Lines
-- already in its history keep what they showed when they came in: the panel keeps them in a list of its own. The face
-- goes on when the panel is found, before it holds any line, so every line it measures is measured in it.
local function chatFont()
  local obj = Compat.resolve("DUIFont_ChatFont")
  if type(obj) ~= "table" or type(obj.GetFont) ~= "function" or type(obj.SetFont) ~= "function" then return end
  local path, size, flags = obj:GetFont()
  if path == WFJ.Font.PATH then return end
  obj:SetFont(WFJ.Font.PATH, size, flags or "")
end

local function chatLine(text)
  local S_, Sp = WFJ.State, WFJ.Speech
  if not (S_ and S_.enabled and not S_.modifierHeld and S_.areaEnabled("gossip")) then return nil end
  if not (Sp and type(Sp.translate) == "function") then return nil end
  local ja = Sp.translate(text)
  -- Dialogue UI fills an emote's speaker with format(): a `%` in the Japanese other than that `%s` would break it
  if type(ja) == "string" and ja:gsub("%%s", ""):find("%", 1, true) then return nil end
  return ja
end

local function wrapChat(panel)
  guarded(chatFont)
  local add = panel.AddMessage
  panel.AddMessage = function(self, text, ...)
    local ja
    if WFJ.DialogueUI.active() and type(text) == "string" then
      local ok, t = guarded(chatLine, text)
      ja = ok and t or nil
      if ja then guarded(chatFont) end
    end
    return add(self, ja or text, ...)
  end
end

-- ── Dialogue UI's quest popups ─────────────────────────────────────────────
-- A quest the game starts or finishes on its own gets a small popup with its name, made when first needed [read:
-- Dialogue UI 1.0.7 b, Code/Widget/Widget_QuestPopup.lua]. Its name is the quest's Japanese title.
local function wrapPopup(popup)
  local setTitle = popup.SetTitle
  popup.SetTitle = function(self, title, ...)
    if type(title) == "string" then popupTitle[self] = title end
    local ja
    if WFJ.DialogueUI.active() and type(title) == "string" and type(self.questID) == "number" then
      local ok, t = guarded(WFJ.DialogueUI.questTitle, { questID = self.questID, title = title })
      ja = ok and t or nil
    end
    local fs = self.Title
    if type(fs) == "table" and type(fs.GetFont) == "function" then
      guarded(WFJ.DialogueUI.face, fs, type(fs.GetFontObject) == "function" and fs:GetFontObject() or nil, ja ~= nil)
    end
    return setTitle(self, ja or title, ...)
  end
  -- one already on screen shows its name again through the wrapper
  local title = type(popup.Title) == "table" and type(popup.Title.GetText) == "function" and popup.Title:GetText()
  if type(title) == "string" and title ~= "" and type(popup.IsShown) == "function" and popup:IsShown() then
    popup:SetTitle(title)
  end
end

-- Dialogue UI's frames this module works on but cannot reach by name, told apart by their own members.
local function classify(f)
  if type(f) ~= "table" or patched[f] then return end
  -- its line grid is made on first use, so the tooltip is told apart by its methods only
  if type(f.AddLeftLine) == "function" and type(f.AddRightLine) == "function" and type(f.ProcessInfo) == "function" then
    patched[f] = true
    wrapTooltip(f)
  elseif type(f.AddMessage) == "function" and type(f.SendContentToClipboard) == "function"
      and type(f.UpdateVisibility) == "function" then
    patched[f] = true
    wrapChat(f)
  elseif type(f.SetQuestDataByID) == "function" and type(f.SetTitle) == "function" and type(f.Title) == "table" then
    patched[f] = true
    wrapPopup(f)
  end
end

-- Frames are enumerated in the order they were made, so a scan goes on from the last frame the previous one saw.
local lastScanned
local function scanFrames()
  local enumerate = Compat.resolve("EnumerateFrames")
  if type(enumerate) ~= "function" then return end
  local ok, f = pcall(enumerate, lastScanned)
  local n = 0
  while ok and f and n < 50000 do
    n = n + 1
    lastScanned = f
    pcall(classify, f) -- a frame the client forbids reading is passed over
    ok, f = pcall(enumerate, f)
  end
  if not ok then lastScanned = nil end -- the walk failed on a frame: the next scan starts again from the first
end

-- after the events Dialogue UI makes a popup on, once it has made it
local scanPending = false
local function scanSoon()
  if scanPending then return end
  local timer = Compat.resolve("C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" then return guarded(scanFrames) end
  scanPending = true
  timer.After(0.2, function()
    scanPending = false
    guarded(scanFrames)
  end)
end

local function events()
  local createFrame = Compat.resolve("CreateFrame")
  if type(createFrame) ~= "function" then return end
  local ev = createFrame("Frame")
  for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_AUTOCOMPLETE", "QUEST_TURNED_IN", "QUEST_DETAIL" }) do
    pcall(ev.RegisterEvent, ev, e) -- an event this client does not have is passed over
  end
  ev:SetScript("OnEvent", function() if WFJ.DialogueUI.active() then guarded(scanSoon) end end)
end


-- The reveal key or a switch changed: a tooltip on screen is built again by its own update (each line through the
-- wrappers, as the switch now says), and a popup on screen is given its English name again through the wrapper.
local function refresh()
  if not WFJ.DialogueUI.healthy() then return end
  for tip in pairs(tips) do
    if type(tip.IsShown) == "function" and tip:IsShown() and type(tip.tooltipInfo) == "table" then
      guarded(tip.ProcessInfo, tip, tip.tooltipInfo)
    end
  end
  for popup, en in pairs(popupTitle) do
    if type(popup.IsShown) == "function" and popup:IsShown() then guarded(popup.SetTitle, popup, en) end
  end
end

-- Called by UI/DialogueUI once Dialogue UI's window is set up: the frames made so far, and a scan after the events
-- Dialogue UI makes a popup on and whenever its window opens.
function Frames.install(window)
  guarded(scanFrames)
  guarded(events)
  if type(window) == "table" and type(window.HookScript) == "function" then
    window:HookScript("OnShow", function() guarded(scanSoon) end)
  end
  for _, event in ipairs({ "modifier", "enabled", "area" }) do
    WFJ.State.on(event, function() guarded(refresh) end)
  end
end
