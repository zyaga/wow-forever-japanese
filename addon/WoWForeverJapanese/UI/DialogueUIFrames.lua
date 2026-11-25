-- UI/DialogueUIFrames.lua: the Dialogue UI addon's other frames with game text, when the player has that addon
-- (ADR-073): its item tooltip, the chat panel in its window and its quest popups. Dialogue UI makes them with no name,
-- so they are told apart by their own members; a scan finds the ones made since the last scan. As in UI/DialogueUI,
-- no method of theirs is replaced: each is followed with hooksecurefunc, so Dialogue UI's own code runs first and
-- untouched, and the Japanese is written afterwards into the FontStrings it wrote (ADR-073). Anything that fails
-- leaves Dialogue UI's English (UI/DialogueUI's guard and error limit).
local _, WFJ = ...
local Frames = {}
WFJ.DialogueUIFrames = Frames

local Compat = WFJ.Compat
local patched = setmetatable({}, { __mode = "k" }) -- frames whose writers are followed
local function guarded(...) return WFJ.DialogueUI.guarded(...) end
local function hook(...) return Compat.resolve("hooksecurefunc")(...) end
local function write(fs, text) return WFJ.DialogueUI.write(fs, text) end

-- ── Dialogue UI's tooltip ──────────────────────────────────────────────────
-- Dialogue UI draws item and reward tooltips in a frame of its own, made at its load with no name; a scan finds it by
-- its members (its two line writers and its update) [read: Dialogue UI 1.0.7 b, Code/Tooltip/Tooltip_Base.lua]. A
-- line after the first (the first is the item's name, which stays English) that is one of the client's interface
-- strings ("Quest Item", "Item Level 14", "+3 Item Level") gets its Japanese in the bundled face. An item's effect
-- lines (Use:, Equip:, Chance on hit: and the flavour quote, the run UI/Tooltip finds) show the item's Japanese, as
-- the game's tooltip shows them: once Dialogue UI has added the client's tooltip data line by line
-- (ProcessTooltipDataLines), the run's first line gets the Japanese and its other lines are taken out of the layout.
-- Dialogue UI lays the tooltip out only when it shows it, after all of this.
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
  local own = S_ and S_.enabled and not S_.showsEnglish() and S_.areaEnabled("ui")
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

-- The English each line of a tooltip was added with, and its FontString: tooltip → { [row] = { text, fs } }
local added = setmetatable({}, { __mode = "k" })

-- After AddLeftLine / AddRightLine: the line Dialogue UI just added (the last row's column 1 or 2) gets its Japanese,
-- in the bundled face; a line it uses again that wore ours gets its own face back.
local function lineAdded(self, col, text)
  if type(text) ~= "string" or text == "" then return end
  local row = self.grid and self.numLines and self.grid[self.numLines]
  local fs = type(row) == "table" and row[col] or nil
  if type(fs) ~= "table" or type(fs.SetText) ~= "function" then return end
  if col == 1 then
    added[self] = added[self] or {}
    added[self][self.numLines] = { text = text, fs = fs }
  end
  local ja
  -- the first line is the item's name, which stays English
  if WFJ.DialogueUI.active() and (col == 2 or self.numLines > 1) then ja = tipText(text) end
  -- a line Dialogue UI uses again keeps the face it was last given (its own font object is set again only when
  -- the line's size changes [read: Tooltip_Base.lua, SetLineFont]), so taking ours off changes its face too
  local was = WFJ.Font.dressed(fs)
  WFJ.DialogueUI.face(fs, nil, ja ~= nil)
  if ja then fs:SetText(ja) end
  -- the tooltip sizes itself a frame later when told a line's face changed [read: Tooltip_Base.lua, Show]
  if ja or was then self.fontChanged = true end
end

-- An item's tooltip data → the first and last line of its effect run and that run's Japanese, or nil to leave the lines
-- as they are.
local function itemRun(data, lines)
  if type(data) ~= "table" or not data.isItem or type(lines) ~= "table" then return nil end
  local id = data.id
  if type(id) ~= "number" and type(data.hyperlink) == "string" then
    id = tonumber(data.hyperlink:match("item:(%d+)"))
  end
  local T = WFJ.Tooltip
  if type(id) ~= "number" or not T or type(T.itemRun) ~= "function" then return nil end
  local texts = {}
  for i, line in ipairs(lines) do
    local t = type(line) == "table" and line.leftText or nil
    if type(t) ~= "string" then return nil end -- a line the client may not let the addon read
    texts[i] = t
  end
  local first, last = T.itemRun(texts)
  if not first then return nil end
  local run = {}
  for i = first, last do run[#run + 1] = texts[i] end
  local ja, _, action = WFJ.Render.preview("dialogueui.rows", texts[first], nil, "items", "item.description", id,
    { lines = run })
  if action ~= "apply" or type(ja) ~= "string" or ja == "" then return nil end
  return texts, first, last, ja
end

-- After ProcessTooltipDataLines: the item's effect run shown as one Japanese line, as UI/Tooltip shows it on the
-- game's tooltip. The rows are found by the English they were added with, in order; any mismatch leaves them.
local function dataLines(self, lines, startingIndex)
  if not WFJ.DialogueUI.active() or (startingIndex ~= nil and startingIndex ~= 1) then return end
  local texts, first, last, ja = itemRun(self.tooltipData, lines)
  local rows = added[self]
  if not (texts and rows) then return end
  local grid = self.grid
  local function lineAt(r)
    local rec = rows[r]
    local row = grid[r]
    return rec and type(row) == "table" and row[1] == rec.fs and rec or nil
  end
  local at
  for r = 1, self.numLines do
    local rec = lineAt(r)
    if rec and rec.text == texts[first] then at = r; break end
  end
  if not at then return end
  local fold, r = {}, at
  for i = first + 1, last do
    if texts[i] ~= "" then -- an empty line adds no row [read: Tooltip_Base.lua, AddLeftLine]
      r = r + 1
      local rec = lineAt(r)
      if not (rec and rec.text == texts[i]) then return end
      fold[#fold + 1] = r
    end
  end
  local fs = rows[at].fs
  WFJ.DialogueUI.face(fs, nil, true)
  fs:SetText(ja)
  for _, k in ipairs(fold) do
    local other = grid[k][1]
    other:SetText(nil)
    other:Hide()
    grid[k] = nil -- its Layout passes over a row that has no entry
  end
  self.fontChanged = true
end

local tips = setmetatable({}, { __mode = "k" }) -- Dialogue UI's tooltips found
local popupTitle = setmetatable({}, { __mode = "k" }) -- popup → the English name it was last given

local function followTooltip(tip)
  tips[tip] = true
  hook(tip, "AddLeftLine", function(self, text) guarded(lineAdded, self, 1, text) end)
  hook(tip, "AddRightLine", function(self, text) guarded(lineAdded, self, 2, text) end) -- "Cloth", "Mail"
  if type(tip.ProcessTooltipDataLines) == "function" then
    hook(tip, "ProcessTooltipDataLines", function(self, lines, startingIndex)
      guarded(dataLines, self, lines, startingIndex)
    end)
  end
end

-- ── Dialogue UI's chat panel ───────────────────────────────────────────────
-- While its window is open Dialogue UI repeats what NPCs say, yell and emote in a chat panel of its own (an unnamed
-- frame [read: Dialogue UI 1.0.7 b, Code/Dialogue/ChatFrame.lua]). A line gets the Japanese the chat window shows
-- (UI/Speech; the panel has no target, so a line naming a party member is found by the party's names), in the
-- bundled face set on the panel's font object (the panel measures its lines through it). Dialogue UI keeps each line
-- it was given, its speaker's words before it, in the list of its scroll view [read: Dialogue UI 1.0.7 c,
-- ChatFrame.lua AddMessage, ScrollViewDataProvider]: after it added a line, that entry's English is swapped for the
-- Japanese and the list is measured again. Lines already in its history keep what they showed when they came in. The
-- face goes on when the panel is found, before it holds any line, so every line it measures is measured in it.
local function chatFont()
  local obj = Compat.resolve("DUIFont_ChatFont")
  if type(obj) ~= "table" or type(obj.GetFont) ~= "function" or type(obj.SetFont) ~= "function" then return end
  local path, size, flags = obj:GetFont()
  if path == WFJ.Font.PATH then return end
  obj:SetFont(WFJ.Font.PATH, WFJ.Font.size(size) or WFJ.Font.DEFAULT_SIZE, flags or "")
end

local function chatLine(text)
  local S_, Sp = WFJ.State, WFJ.Speech
  if not (S_ and S_.enabled and not S_.showsEnglish() and S_.areaEnabled("gossip")) then return nil end
  local translate = Sp and (Sp.translateNamed or Sp.translate)
  if type(translate) ~= "function" then return nil end
  local ja = translate(text)
  -- Dialogue UI fills an emote's speaker with format(): a `%` in the Japanese other than that `%s` would break it
  if type(ja) == "string" and ja:gsub("%%s", ""):find("%", 1, true) then return nil end
  return ja
end

-- The list of lines Dialogue UI keeps for the panel: its scroll view's data provider, a child frame of the panel.
local function chatList(panel)
  for _, child in ipairs(WFJ.Frames.children(panel)) do
    local p = type(child) == "table" and child.dataProvider or nil
    if type(p) == "table" and type(p.content) == "table" and type(p.CalculateAllExtent) == "function" then return p end
  end
  return nil
end

-- An emote's text as Dialogue UI stores it: its `%s` filled with the speaker's name, any other `%` dropped.
local function asStored(text, name, event)
  if event ~= "CHAT_MSG_MONSTER_EMOTE" then return text end
  if text:find("%%s") then return text:format(name) end
  return (text:gsub("%%", ""))
end

-- After AddMessage: the entry Dialogue UI just added (the last) shows the Japanese, measured again.
local function chatAdded(panel, text, name, event)
  if type(text) ~= "string" or not WFJ.DialogueUI.active() then return end
  local ja = chatLine(text)
  if not ja then return end
  chatFont()
  local list = chatList(panel)
  local entry = list and list.content[#list.content]
  local stored = type(entry) == "table" and entry[1]
  local en = asStored(text, name, event)
  if type(stored) ~= "string" or #stored < #en or stored:sub(-#en) ~= en then return end
  local shown = stored:sub(1, #stored - #en) .. asStored(ja, name, event)
  entry[1] = shown
  list:CalculateAllExtent()
  -- a line already drawn shows its text until another line takes its place: written here
  for _, obj in ipairs(type(list.objects) == "table" and list.objects or {}) do
    if obj.dataIndex == #list.content and type(obj.SetText) == "function" then obj:SetText(shown) end
  end
  if list.isVisible and type(list.UpdateView) == "function" then list:UpdateView() end
end

local function followChat(panel)
  guarded(chatFont)
  hook(panel, "AddMessage", function(self, text, name, event) guarded(chatAdded, self, text, name, event) end)
end

-- ── Dialogue UI's quest popups ─────────────────────────────────────────────
-- A quest the game starts or finishes on its own gets a small popup with its name, made when first needed [read:
-- Dialogue UI 1.0.7 c, Code/Widget/Widget_QuestPopup.lua]. Its name is the quest's Japanese title while titles are
-- switched on. SetTitle writes the name into its Title and then scales the text to fit, so the Japanese goes in right
-- after that write, through a hook on the Title's SetText, and is what gets scaled.
local function popupWritten(popup, fs, title)
  if WFJ.DialogueUI.writing() or type(title) ~= "string" or title == "" then return end
  popupTitle[popup] = title
  local ja
  if WFJ.DialogueUI.active() and type(popup.questID) == "number" then
    ja = WFJ.DialogueUI.questTitle({ questID = popup.questID, title = title })
  end
  WFJ.DialogueUI.face(fs, type(fs.GetFontObject) == "function" and fs:GetFontObject() or nil, ja ~= nil)
  if ja then write(fs, ja) end
end

local function followPopup(popup)
  local fs = popup.Title
  hook(fs, "SetText", function(x, title) guarded(popupWritten, popup, x, title) end)
  -- one already on screen shows its name again, written and scaled by its own SetTitle
  local title = type(fs.GetText) == "function" and fs:GetText()
  if type(title) == "string" and title ~= "" and type(popup.IsShown) == "function" and popup:IsShown() then
    popup:SetTitle(title)
  end
end

-- ── Dialogue UI's quest-complete flyout ────────────────────────────────────
-- A quest the game completes on its own may show a small flyout (off by default) with the quest's name and its turn-in
-- text, split into paragraphs [read: Dialogue UI 1.0.7 c, Code/Dialogue/QuestFlyout.lua, SetQuestText]. SetQuestText
-- writes the title first, then each paragraph into a text from its pool and measures it at once. The pool's texts are
-- followed as the pool hands them out: the title's write starts a pass with the quest's Japanese, and each paragraph's
-- write is given its share of it, in the bundled face, before it is measured. An error alert, a quest with no Japanese
-- or the reveal key held leaves the flyout's own English.
local pass = setmetatable({}, { __mode = "k" }) -- flyout → { slots, done } while SetQuestText writes Japanese
local flyTexts = setmetatable({}, { __mode = "k" }) -- the flyout's pooled texts that are followed

local function flyoutText(frame, title)
  local data = frame.questData
  local questID = type(data) == "table" and data.questID or nil
  if type(questID) ~= "number" or data.isError then return nil end
  local D = WFJ.DialogueUI
  local jaTitle = type(title) == "string" and title ~= "" and D.preview(title, "quests", "quest.title", questID, title)
    or nil
  local en, Q, slots = data.rawText, WFJ.QuestFrame, nil
  -- the English paragraphs SetQuestText lays out [read: QuestFlyout.lua SetQuestData, SetQuestText]
  local count = 0
  for _, p in ipairs(type(data.paragraphs) == "table" and data.paragraphs or {}) do
    if type(p) == "string" and p ~= "" and p ~= " " then count = count + 1 end
  end
  if type(en) == "string" and en ~= "" and count > 0 and Q and type(Q.fieldSource) == "function" then
    local kind, id = Q.fieldSource(questID, "completion", en)
    local ja = id ~= nil and D.preview(en, "quests", kind, id, en) or nil
    if type(ja) == "string" then
      local paras = {}
      for p in (ja:gsub("\r", "") .. "\n\n"):gmatch("(.-)\n\n+") do
        p = p:gsub("^%s+", ""):gsub("%s+$", "")
        if p ~= "" then paras[#paras + 1] = p end
      end
      -- as many as the English has: more go together into the first, fewer leave the last ones empty
      if #paras >= count then
        local extra = #paras - count
        slots = { table.concat(paras, "\n\n", 1, 1 + extra) }
        for i = 2, count do slots[i] = paras[i + extra] end
      elseif #paras > 0 then
        slots = {}
        for i = 1, count do slots[i] = paras[i] or "" end
      end
    end
  end
  return jaTitle, slots
end

-- The title's write: a new pass, and the title's Japanese.
local function flyTitle(fly, fs, title)
  if WFJ.DialogueUI.writing() then return end
  pass[fly] = nil
  if not WFJ.DialogueUI.active() then return end
  local jaTitle, slots = flyoutText(fly, title)
  WFJ.DialogueUI.face(fs, nil, jaTitle ~= nil)
  if jaTitle then write(fs, jaTitle) end
  if slots then pass[fly] = { slots = slots, done = 0 } end
end

-- A paragraph's write: its share of the Japanese, measured in the bundled face; Dialogue UI's own face otherwise.
local function flyParagraph(fly, fs, text)
  if WFJ.DialogueUI.writing() or type(text) ~= "string" then return end
  local p = pass[fly]
  local t
  if p and text ~= "" and text ~= " " then
    p.done = p.done + 1
    t = p.slots[p.done]
    if p.done >= #p.slots then pass[fly] = nil end
  end
  WFJ.DialogueUI.face(fs, nil, t ~= nil)
  if t then write(fs, t) end
end

-- After the pool's Acquire: the text it handed out (its newest) is followed, once.
local function flyAcquired(fly, pool)
  local fs
  for _, x in pool:EnumerateActive() do fs = x end
  if type(fs) ~= "table" or flyTexts[fs] then return end
  flyTexts[fs] = true
  hook(fs, "SetText", function(x, text) guarded(flyParagraph, fly, x, text) end)
end

local function followFlyout(fly)
  local pool = fly.fontStringPool
  if type(pool.EnumerateActive) == "function" then
    hook(pool, "Acquire", function(p) guarded(flyAcquired, fly, p) end)
    for _, fs in pool:EnumerateActive() do -- texts it holds already
      if type(fs) == "table" and not flyTexts[fs] then
        flyTexts[fs] = true
        hook(fs, "SetText", function(x, text) guarded(flyParagraph, fly, x, text) end)
      end
    end
  end
  if type(fly.Title) == "table" then
    hook(fly.Title, "SetText", function(x, title) guarded(flyTitle, fly, x, title) end)
  end
  -- Dialogue UI makes its flyout and writes it in the same call, so the first one of a session is on screen before a
  -- scan finds it: written again by its own SetQuestText and laid out by its own Layout [read: Dialogue UI 1.0.7 c,
  -- QuestFlyout.lua SetQuestData: SetQuestText then Layout]
  -- (on the next frame: the first scan runs while the window support is still being installed)
  local function rewrite()
    local data = fly.questData
    if type(data) == "table" and not data.isError and type(data.paragraphs) == "table"
        and type(fly.IsShown) == "function" and fly:IsShown() then
      guarded(fly.SetQuestText, fly, data.title, data.paragraphs)
      if type(fly.Layout) == "function" then guarded(fly.Layout, fly) end
    end
  end
  local timer = Compat.resolve("C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then timer.After(0, rewrite) else rewrite() end
end

-- Dialogue UI's frames this module works on but cannot reach by name, told apart by their own members.
local function classify(f)
  if type(f) ~= "table" or patched[f] then return end
  -- its line grid is made on first use, so the tooltip is told apart by its methods only
  if type(f.AddLeftLine) == "function" and type(f.AddRightLine) == "function" and type(f.ProcessInfo) == "function" then
    patched[f] = true
    followTooltip(f)
  elseif type(f.AddMessage) == "function" and type(f.SendContentToClipboard) == "function"
      and type(f.UpdateVisibility) == "function" then
    patched[f] = true
    followChat(f)
  elseif type(f.SetQuestDataByID) == "function" and type(f.SetTitle) == "function" and type(f.Title) == "table"
      and type(f.Title.SetText) == "function" then
    patched[f] = true
    followPopup(f)
  elseif type(f.SetQuestText) == "function" and type(f.SetQuestRewards) == "function"
      and type(f.fontStringPool) == "table" then
    patched[f] = true
    followFlyout(f)
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
  ev:SetScript("OnEvent", WFJ.Perf.wrap("idle.dialogueui.event",
    function() if WFJ.DialogueUI.active() then guarded(scanSoon) end end))
end


-- The reveal key or a switch changed: a tooltip on screen is built again by its own update (each line through the
-- hooks, as the switch now says), and a popup on screen is given its English name again by its own SetTitle.
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
-- Dialogue UI makes a popup on and whenever its window is seen open (from UI/DialogueUI's watching frame, never inside
-- Dialogue UI's own show).
function Frames.install(window)
  guarded(scanFrames)
  guarded(events)
  if type(window) == "table" then WFJ.DialogueUI.onOpen(window, scanSoon) end
  for _, event in ipairs({ "language", "enabled", "area" }) do
    WFJ.State.on(event, function() guarded(refresh) end)
  end
end
