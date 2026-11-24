-- UI/ChatTrial.lua: TRIAL. The copy box, the phrase book and the /wfjchat command of the chat tools trial.
--   Copy box: an addon cannot write the clipboard, so the line is put in a box with its text selected.
--   Phrase book: each phrase has one fixed English line and one fixed Japanese line. A click types one of them into
--     the chat box; the player sends it. A player with the addon who receives either line reads it in their own
--     direction's language (a message filter, exact match only); everyone else reads what was typed.
local _, WFJ = ...

-- ── The copy box ────────────────────────────────────────────────────────────
local Copy = {}
WFJ.ChatCopy = Copy
local copyFrame, copyBox

function Copy.show(text)
  local W = WFJ.OptionsWidgets
  if not copyFrame then
    -- the same window frame as the addon's other tool windows (UI/OptionsWidgets W.toolWindow)
    copyFrame = W.toolWindow("WFJChatCopyFrame", 600, 220)
    copyFrame.title:SetText("コピー ・ Copy")
    WFJ.Font.set(copyFrame.title, WFJ.Font.PATH, 13, "")
    copyBox = CreateFrame("EditBox", nil, copyFrame)
    copyBox:SetMultiLine(true)
    copyBox:SetAutoFocus(false)
    copyBox:SetFont(WFJ.Font.PATH, 14, "")
    copyBox:SetPoint("TOPLEFT", copyFrame.Inset, "TOPLEFT", 12, -12)
    copyBox:SetPoint("BOTTOMRIGHT", copyFrame.Inset, "BOTTOMRIGHT", -12, 12)
    copyBox:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
    local foot = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    WFJ.Font.set(foot, WFJ.Font.PATH, 11, "")
    foot:SetPoint("BOTTOMLEFT", copyFrame, "BOTTOMLEFT", 16, 8)
    foot:SetTextColor(0.75, 0.75, 0.75)
    foot:SetText("Ctrl+C（Mac: Cmd+C）でコピー、Esc で閉じる ・ Ctrl+C (Cmd+C) copies, Esc closes")
  end
  copyFrame:Show()
  copyBox:SetText(text or "")
  copyBox:SetFocus()
  copyBox:HighlightText()
end


-- ── The phrase book ─────────────────────────────────────────────────────────
local Phrases = {}
WFJ.ChatPhrases = Phrases
local book, rows, tabs, category = nil, {}, {}, nil

-- The mark: a phrase from the book is typed with a middle dot in front of it ("· Hello!", "・こんにちは！"). To a
-- player without the addon it reads as a bullet. With the addon, a dot followed by exactly one of the book's phrases
-- is that phrase: the dot is drawn as a gold 文 and the phrase is shown in the reader's own language. A dot followed
-- by anything else, and a phrase with no dot, are left as typed.
local DOT_EN, DOT_JA = "\194\183", "\227\131\187" -- U+00B7, U+30FB
local MARK = "|cffffd200文|r "

local list -- every phrase in both languages, longest first, so a phrase that starts another never wins
local function phraseList()
  if list then return list end
  list = {}
  for _, p in ipairs(WFJ.ChatData.phrases) do
    list[#list + 1] = { text = p.en:lower(), phrase = p }
    list[#list + 1] = { text = p.ja, phrase = p }
  end
  table.sort(list, function(x, y) return #x.text > #y.text end)
  return list
end

-- The phrase that starts at byte `i` of the message (spaces after the dot skipped). → phrase, its last byte
local function phraseAt(lower, i)
  while lower:byte(i) == 32 do i = i + 1 end
  for _, e in ipairs(phraseList()) do
    if lower:sub(i, i + #e.text - 1) == e.text then return e.phrase, i + #e.text - 1 end
  end
  return nil
end

-- → the message with each marked phrase in `direction`'s language, or nil when it holds none
function Phrases.translate(msg, direction)
  local lower = msg:lower() -- ASCII letters only; every other byte, and so every position, is unchanged
  local out, pos, changed = {}, 1, false
  while true do
    local a1, a2 = msg:find(DOT_EN, pos, true)
    local b1, b2 = msg:find(DOT_JA, pos, true)
    local s, e
    if a1 and (not b1 or a1 < b1) then s, e = a1, a2 else s, e = b1, b2 end
    if not s then break end
    local p, last = phraseAt(lower, e + 1)
    if p then
      out[#out + 1] = msg:sub(pos, s - 1)
      out[#out + 1] = MARK .. (direction == "en" and p.en or p.ja)
      pos, changed = last + 1, true
    else
      out[#out + 1] = msg:sub(pos, e)
      pos = e + 1
    end
  end
  if not changed then return nil end
  out[#out + 1] = msg:sub(pos)
  return table.concat(out)
end

local function put(text)
  local util = _G.ChatFrameUtil
  local box = util and util.GetActiveWindow and util.GetActiveWindow()
  if box then
    box:Insert(text)
  elseif util and util.OpenChat then
    util.OpenChat(text)
  elseif _G.ChatFrame_OpenChat then
    _G.ChatFrame_OpenChat(text)
  end
end

local function categories()
  local out, seen = {}, {}
  for _, p in ipairs(WFJ.ChatData.phrases) do
    if not seen[p.cat] then
      seen[p.cat] = true
      out[#out + 1] = p.cat
    end
  end
  return out
end

-- The phrase book, built the way the study tab and card are (UI/StudyWindow): two small frames of the addon's own
-- that share one saved spot. The BUTTON is the client's chat button with a gold 文. A click swaps it for the CARD
-- at the same spot; the card's minus puts the button back (collapse), its X hides both until /wfjchat button or
-- /phrases, and either frame can be dragged (the other follows). One fixed card size whatever the tab: two columns,
-- as many rows as the fullest tab needs.
local COLS, COL_W, ROW_H, PAD, HEAD, TABS_H, FOOT = 2, 284, 38, 12, 34, 36, 24
local PAGE_TOP = HEAD + TABS_H + 6
local opener, cardOpen = nil, false

local function saved() return _G.WFJ_ChatWords end

local function mostRows()
  local count, most = {}, 0
  for _, p in ipairs(WFJ.ChatData.phrases) do
    count[p.cat] = (count[p.cat] or 0) + 1
    if count[p.cat] > most then most = count[p.cat] end
  end
  return math.ceil(most / COLS)
end

-- the shared spot: where the player dragged either frame, else by the chat frame's own buttons
local function place(f)
  if not f then return end
  f:ClearAllPoints()
  local p = saved().spot
  if type(p) == "table" and type(p[1]) == "string" and type(p[2]) == "string" and type(p[3]) == "number"
      and type(p[4]) == "number" then
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    return
  end
  local chat = _G.ChatFrame1
  local left, bottom = chat and chat:GetLeft(), chat and chat:GetBottom()
  if left and bottom then
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", math.max(left - 31, 0), bottom + 34)
  else
    f:SetPoint("LEFT", UIParent, "LEFT", 4, 0)
  end
end

local function movable(f)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint(1)
    saved().spot = { p, rp, x, y }
    place(self == book and opener or book) -- the other frame follows
  end)
end

-- the tab strip puts the client's own (Latin-only) font back on a tab when it is selected: ours goes back on
local function fontTabs()
  if not book then return end
  for _, tab in ipairs(tabs) do
    tab.Text:SetText(tab.tabText)
    WFJ.Font.set(tab.Text, WFJ.Font.PATH, 12, "")
    -- a tab made with no text was given a text area of almost no width, and the tab's own sizing reads that
    -- width back: cleared, so it measures the words (a cut-off tab is blank and shows the client's tooltip)
    tab.Text:SetWidth(0)
    if tab.UpdateTabWidth then tab:UpdateTabWidth() end
  end
  if book.tabSystem.MarkDirty then book.tabSystem:MarkDirty() end
end

local function fill()
  local n = 0
  for _, p in ipairs(WFJ.ChatData.phrases) do
    if p.cat == category then
      n = n + 1
      local row = rows[n]
      if not row then
        row = CreateFrame("Button", nil, book)
        row:SetSize(COL_W - 6, ROW_H - 4)
        row:SetPoint("TOPLEFT", book, "TOPLEFT", PAD + ((n - 1) % COLS) * COL_W,
          -PAGE_TOP - math.floor((n - 1) / COLS) * ROW_H)
        row:RegisterForClicks("LeftButtonUp")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(row)
        hl:SetColorTexture(1, 0.82, 0, 0.12)
        row.ja = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        WFJ.Font.set(row.ja, WFJ.Font.PATH, 14, "")
        row.ja:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -2)
        row.ja:SetWidth(COL_W - 18)
        row.ja:SetJustifyH("LEFT")
        row.ja:SetWordWrap(false)
        row.en = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.en:SetPoint("TOPLEFT", row.ja, "BOTTOMLEFT", 0, -2)
        row.en:SetWidth(COL_W - 18)
        row.en:SetJustifyH("LEFT")
        row.en:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
          -- one click types the phrase and gets out of the way: the card goes back to the button
          -- always the English: a reader with the addon gets their own language whatever was sent, and a
          -- reader without it can only read what the game's chat font can draw, which is not Japanese
          put(DOT_EN .. " " .. self.phrase.en)
          Phrases.collapse()
        end)
        rows[n] = row
      end
      row.phrase = p
      row.ja:SetText(p.ja)
      row.en:SetText(p.en)
      row:Show()
    end
  end
  for i = n + 1, #rows do rows[i]:Hide() end
end

local function pick(cat)
  category = cat
  for _, tab in ipairs(tabs) do
    if tab.cat == cat then book.tabSystem:SetTabVisuallySelected(tab.tabID) end
  end
  fontTabs()
  fill()
end

local function buildCard()
  -- the study card's own frame: the same backdrop, border and header buttons [UI/StudyWindow backdrop, buildCard]
  book = CreateFrame("Frame", "WFJChatPhraseCard", UIParent, "BackdropTemplate")
  book:SetSize(2 * PAD + COLS * COL_W, PAGE_TOP + mostRows() * ROW_H + FOOT + PAD)
  book:SetFrameStrata("HIGH")
  book:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  book:SetBackdropColor(0.06, 0.05, 0.04, 0.92)
  book:SetBackdropBorderColor(0.45, 0.32, 0.18, 1)
  movable(book)
  local title = book:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  WFJ.Font.set(title, WFJ.Font.PATH, 15, "")
  title:SetPoint("TOPLEFT", book, "TOPLEFT", PAD, -PAD)
  title:SetText("定型文 ・ Phrase book")
  local close = CreateFrame("Button", nil, book, "UIPanelCloseButton")
  close:SetSize(24, 24)
  close:SetPoint("TOPRIGHT", book, "TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() Phrases.close() end)
  local collapse = CreateFrame("Button", nil, book, "UIPanelHideButtonNoScripts")
  collapse:SetSize(24, 24)
  collapse:SetPoint("RIGHT", close, "LEFT", -2, 0)
  collapse:SetScript("OnClick", function() Phrases.collapse() end)
  -- the client's own tab strip under the header, on a thin line
  local ts = CreateFrame("Frame", nil, book, "TabSystemTemplate")
  ts.tabTemplate = "TabSystemTopButtonTemplate"
  ts.tabPool = CreateFramePool("BUTTON", ts, "TabSystemTopButtonTemplate")
  ts.minTabWidth = 100
  ts:SetPoint("BOTTOMLEFT", book, "TOPLEFT", PAD, -(HEAD + TABS_H))
  book.tabSystem = ts
  local rule = book:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(0.45, 0.32, 0.18, 1)
  rule:SetPoint("TOPLEFT", book, "TOPLEFT", PAD, -(HEAD + TABS_H))
  rule:SetSize(COLS * COL_W, 1)
  local byID = {}
  for i, cat in ipairs(categories()) do
    local tabID = ts:AddTab("")
    local tab = ts:GetTabButton(tabID)
    tab.cat, tab.tabID, tab.tabText = cat, tabID, cat:match("^(.-) /") or cat
    tabs[i], byID[tabID] = tab, cat
  end
  ts:SetTabSelectedCallback(function(tabID)
    pick(byID[tabID])
    return true
  end)
  hooksecurefunc(ts, "SetTabVisuallySelected", fontTabs)
  local foot = book:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  WFJ.Font.set(foot, WFJ.Font.PATH, 11, "")
  foot:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", PAD, PAD)
  foot:SetTextColor(0.6, 0.6, 0.6)
  foot:SetText("クリックで入力、Enter で送信 ・ Click a phrase, then press Enter to send.")
  book:Hide()
end

local function buildButton()
  -- the client's own chat button: its size and its three pictures [verified: VoiceToggleButtonTemplate,
  -- blizzard_voicetogglebutton/voicetogglebutton.xml:3–19 (27 x 26, chatframe-button-up / -down / -highlight)],
  -- with a gold 文 where the client's buttons carry their icon
  opener = CreateFrame("Button", "WFJChatPhraseButton", UIParent)
  opener:SetSize(27, 26)
  opener:SetFrameStrata("MEDIUM")
  movable(opener)
  opener:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  opener:SetNormalAtlas("chatframe-button-up")
  opener:SetPushedAtlas("chatframe-button-down")
  opener:SetHighlightAtlas("chatframe-button-highlight", "ADD")
  local glyph = opener:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  WFJ.Font.set(glyph, WFJ.Font.PATH, 14, "")
  glyph:SetTextColor(1, 0.82, 0)
  glyph:SetText("文")
  glyph:SetPoint("CENTER", opener, "CENTER", 0, 0)
  opener:SetScript("OnMouseDown", function() glyph:SetPoint("CENTER", opener, "CENTER", -1, -2) end)
  opener:SetScript("OnMouseUp", function() glyph:SetPoint("CENTER", opener, "CENTER", 0, 0) end)
  opener:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
      Phrases.button(false)
      print("|cffffd200WFJ chat|r /wfjchat button ・ ボタンを戻す / brings the phrase button back")
    else
      Phrases.open()
    end
  end)
  local tip = CreateFrame("Frame", nil, opener, "TooltipBackdropTemplate")
  tip:SetFrameStrata("TOOLTIP")
  WFJ.ReadingView.solid(tip)
  local tipText = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  WFJ.Font.set(tipText, WFJ.Font.PATH, 12, "")
  tipText:SetPoint("CENTER", tip, "CENTER", 0, 0)
  tipText:SetText("定型文 ・ Phrase book")
  tip:SetPoint("BOTTOMLEFT", opener, "TOPRIGHT", 2, 2)
  tip:Hide()
  opener:SetScript("OnEnter", function()
    tip:SetSize(tipText:GetStringWidth() + 18, tipText:GetStringHeight() + 12)
    tip:Show()
  end)
  opener:SetScript("OnLeave", function() tip:Hide() end)
  opener:SetScript("OnHide", function() tip:Hide() end)
  opener:Hide()
end

-- one place decides what is on screen: the card when open, else the button unless it is off or closed
local closed = false
local function apply()
  local off = saved().buttonOff
  if book then book:SetShown(cardOpen) end
  if opener then opener:SetShown(not cardOpen and not closed and not off) end
end

-- The button becomes the card, at the same spot.
function Phrases.open()
  if not book then buildCard() end
  closed, cardOpen = false, true
  place(book)
  apply()
  if not category then pick(tabs[1].cat) else pick(category) end
end

-- The card becomes the button again.
function Phrases.collapse()
  cardOpen = false
  if not opener and not saved().buttonOff then buildButton() end
  place(opener)
  apply()
end

-- Hides the card and the button until /phrases or /wfjchat button (the next login shows the button as before).
function Phrases.close()
  closed, cardOpen = true, false
  apply()
end

function Phrases.toggle()
  if cardOpen then Phrases.collapse() else Phrases.open() end
end

-- The button's own switch (/wfjchat button, or a right click on it): kept across sessions.
function Phrases.button(show)
  if show ~= nil then saved().buttonOff = not show or nil end
  if not saved().buttonOff then
    closed = false
    if not opener then buildButton() end
    place(opener)
  end
  apply()
end

-- A received phrase, shown in the reader's own language: marked phrases only (Phrases.translate).
local function filter(_, _, msg, ...)
  local S = WFJ.State
  if not S or not S.enabled then return false end
  local isSecret = _G.issecretvalue
  if type(isSecret) == "function" and isSecret(msg) then return false end
  if type(msg) ~= "string" then return false end
  local want = Phrases.translate(msg, S.direction)
  if not want then return false end
  Phrases.keep(want, msg)
  return false, want, ...
end

-- The reveal key shows what was really sent. Each changed message is kept with the message as it arrived (the last
-- KEPT of them); while English is showing in Japanese first, a visible line holding one shows the sent text in its
-- place, and gets its own text back on release. Run after UI/ChatSystem's own pass over the visible lines, which
-- has by then put a line's remembered English or Japanese on it.
local KEPT = 200
local kept, keptAt = {}, 0
function Phrases.keep(shown, raw)
  for _, k in ipairs(kept) do
    if k.shown == shown and k.raw == raw then return end
  end
  keptAt = keptAt % KEPT + 1
  kept[keptAt] = { shown = shown, raw = raw }
end

local revealed = setmetatable({}, { __mode = "k" }) -- the visible lines now showing the sent text
function Phrases.reveal(frame)
  local lines = type(frame) == "table" and type(frame.visibleLines) == "table" and frame.visibleLines or {}
  local S = WFJ.State
  local raw = S.direction == "ja" and S.showsEnglish()
  local isSecret = _G.issecretvalue
  for _, line in ipairs(lines) do
    local text = line:GetText()
    if type(text) == "string" and not (type(isSecret) == "function" and isSecret(text)) then
      if raw and text:find(MARK, 1, true) then
        for _, k in ipairs(kept) do
          local a, b = text:find(k.shown, 1, true)
          if a then
            line:SetText(text:sub(1, a - 1) .. k.raw .. text:sub(b + 1))
            revealed[line] = true
            break
          end
        end
      elseif not raw and revealed[line] then
        revealed[line] = nil
        -- a line UI/ChatSystem does not rewrite still holds the sent text: its own text goes back
        local info = line.messageInfo
        local own = type(info) == "table" and info.message or nil
        if type(own) == "string" and not (type(isSecret) == "function" and isSecret(own))
            and own:find(MARK, 1, true) and not text:find(MARK, 1, true) then
          line:SetText(own)
        end
      end
    end
  end
end

local function revealAll()
  if type(CHAT_FRAMES) ~= "table" then return end
  for _, name in ipairs(CHAT_FRAMES) do
    local f = _G[name]
    if f then pcall(Phrases.reveal, f) end
  end
end

local EVENTS = { "SAY", "YELL", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "GUILD", "OFFICER",
  "WHISPER", "WHISPER_INFORM", "CHANNEL", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" }

-- ── Start and the command ─────────────────────────────────────────────────────
local function say(text) print("|cffffd200WFJ chat|r " .. text) end

local function command(input)
  local verb, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  verb = (verb or ""):lower()
  local W = WFJ.ChatWords
  if verb == "phrases" or verb == "p" then
    Phrases.toggle()
  elseif verb == "add" then
    local word, reading, meaning = rest:match("^(%S+)%s+(%S+)%s*(.*)$")
    if word and W.add("ja", word, reading, meaning) then
      say(word .. "（" .. reading .. "）" .. meaning .. " : added ・ 追加しました")
    else
      say("/wfjchat add <word> <reading> <meaning>")
    end
  elseif verb == "adden" then
    local word, ja, reading = rest:match("^(%S+)%s+(%S+)%s*(%S*)$")
    if word and W.add("en", word, ja, reading) then
      say(word .. " = " .. ja .. " : added ・ 追加しました")
    else
      say("/wfjchat adden <english word> <japanese> [reading]")
    end
  elseif verb == "remove" then
    say(rest .. (W.remove(rest) and " : removed ・ 削除しました" or " : not in your list ・ リストにありません"))
  elseif verb == "button" then
    Phrases.button(_G.WFJ_ChatWords.buttonOff and true or false)
    say(_G.WFJ_ChatWords.buttonOff and "phrase button off ・ ボタン非表示" or "phrase button on ・ ボタン表示")
  elseif verb == "probe" then
    WFJ.ChatCards.probing = not WFJ.ChatCards.probing
    say("probe " .. (WFJ.ChatCards.probing and "on: click a line's copy icon" or "off"))
  elseif verb == "list" then
    local own, n = W.own(), 0
    for word, e in pairs(own.ja) do
      n = n + 1
      say(word .. "（" .. e.reading .. "）" .. (e.meaning or ""))
    end
    for word, e in pairs(own.en) do
      n = n + 1
      say(word .. " = " .. e.ja)
    end
    if n == 0 then say("no words of your own yet ・ 自分の単語はまだありません") end
  else
    say("/wfjchat phrases ・ add <word> <reading> <meaning> ・ adden <word> <japanese> [reading] ・ remove <word> ・ list")
  end
end

local starter = CreateFrame("Frame")
starter:RegisterEvent("PLAYER_LOGIN")
starter:SetScript("OnEvent", function()
  _G.WFJ_ChatWords = WFJ.ChatWords.load(_G.WFJ_ChatWords)
  local add = (_G.ChatFrameUtil and _G.ChatFrameUtil.AddMessageEventFilter) or _G.ChatFrame_AddMessageEventFilter
  if type(add) == "function" then
    for _, e in ipairs(EVENTS) do add("CHAT_MSG_" .. e, filter) end
  end
  _G.SLASH_WFJCHAT1 = "/wfjchat"
  _G.SlashCmdList.WFJCHAT = command
  -- after UI/ChatSystem has hooked the chat frames, so this pass runs after its own
  C_Timer.After(1, function()
    if type(CHAT_FRAMES) ~= "table" then return end
    for _, name in ipairs(CHAT_FRAMES) do
      local f = _G[name]
      if f and type(f.AddOnDisplayRefreshedCallback) == "function" then
        f:AddOnDisplayRefreshedCallback(function(self) pcall(Phrases.reveal, self) end)
      end
    end
    WFJ.State.on("language", revealAll)
  end)
  Phrases.button()
  _G.SLASH_WFJPHRASES1 = "/phrases"
  _G.SlashCmdList.WFJPHRASES = Phrases.toggle
end)
