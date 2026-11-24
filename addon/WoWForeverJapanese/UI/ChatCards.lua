-- UI/ChatCards.lua: TRIAL. Word cards on chat lines, and the copy button on the line under the mouse.
-- Nothing is hooked and no chat line is changed. A timer looks at the mouse while it is over a chat frame, asks the
-- line's own FontString which character is under it (FindCharacterIndexAtCoordinate, as the client's own text
-- selection does: blizzard_sharedxml/scrollingmessageframe.lua:552–570), and Core/ChatWords finds the word there.
-- Japanese first: Japanese words take cards. English first: English words take cards. Never while the reveal key
-- is held, and never on a line whose text the client keeps secret.
local _, WFJ = ...
local Cards = {}
WFJ.ChatCards = Cards

local EVERY = 0.04
local TINT = { 1, 0.82, 0, 0.22 }

local anchor, button
local shown -- { line, text, first, last }
local wasDown, pressed = false, nil

local function secret(v)
  local f = _G.issecretvalue
  return type(f) == "function" and f(v) and true or false
end

local function boundary(text, i)
  if i == #text + 1 then return true end
  local c = text:byte(i)
  return c ~= nil and (c < 0x80 or c >= 0xC0)
end

local function ensureAnchor()
  if anchor then return anchor end
  anchor = CreateFrame("Frame", nil, UIParent)
  anchor:SetFrameStrata("MEDIUM")
  anchor.tints = {}
  anchor:Hide()
  return anchor
end

local function clear()
  if anchor then
    for _, t in ipairs(anchor.tints) do t:Hide() end
    anchor:Hide()
    if WFJ.ReadingPopup then WFJ.ReadingPopup.hide(anchor) end
  end
  shown = nil
end

local function hideButton()
  if button and not button:IsMouseOver() then button:Hide() end
end

local function ensureButton()
  if button then return button end
  button = CreateFrame("Button", nil, UIParent)
  button:SetFrameStrata("HIGH")
  button:SetSize(14, 14)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(button)
  icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
  button:SetHighlightTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up", "ADD")
  button:SetScript("OnClick", function(self)
    if Cards.probing and self.line and self.raw then pcall(Cards.probe, self.line, self.raw) end
    if WFJ.ChatCopy and self.text then WFJ.ChatCopy.show(self.text) end
  end)
  -- a label of our own: the game's tooltip font has no Japanese
  local tip = CreateFrame("Frame", nil, button, "TooltipBackdropTemplate")
  tip:SetFrameStrata("TOOLTIP")
  WFJ.ReadingView.solid(tip)
  local tipText = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  WFJ.Font.set(tipText, WFJ.Font.PATH, 12, "")
  tipText:SetPoint("CENTER", tip, "CENTER", 0, 0)
  tipText:SetText("コピー ・ Copy this line")
  tip:SetPoint("BOTTOMLEFT", button, "TOPRIGHT", 2, 2)
  tip:Hide()
  button:SetScript("OnEnter", function()
    tip:SetSize(tipText:GetStringWidth() + 18, tipText:GetStringHeight() + 12)
    tip:Show()
  end)
  button:SetScript("OnLeave", function() tip:Hide() end)
  button:SetScript("OnHide", function() tip:Hide() end)
  button:Hide()
  return button
end

-- The chat types a player types into. Only their lines are cut down to the message; every other line (system,
-- loot, emotes, achievements, NPC talk) is copied whole.
local TYPED = { SAY = true, YELL = true, PARTY = true, PARTY_LEADER = true, RAID = true, RAID_LEADER = true,
  RAID_WARNING = true, GUILD = true, OFFICER = true, WHISPER = true, WHISPER_INFORM = true, INSTANCE_CHAT = true,
  INSTANCE_CHAT_LEADER = true, BN_WHISPER = true, BN_WHISPER_INFORM = true, COMMUNITIES_CHANNEL = true }
local typeNames
local function typedLine(line)
  local info = line.messageInfo
  local id = type(info) == "table" and type(info.extraData) == "table" and info.extraData[1] or nil
  if id == nil or secret(id) or type(ChatTypeInfo) ~= "table" then return false end
  if not typeNames then
    typeNames = {}
    -- looked up by name: walking ChatTypeInfo with pairs() finds no entries on this client
    local names = { "CHANNEL" }
    for name in pairs(TYPED) do names[#names + 1] = name end
    for i = 1, 20 do names[#names + 1] = "CHANNEL" .. i end
    for _, name in ipairs(names) do
      local t = ChatTypeInfo[name]
      if type(t) == "table" and t.id ~= nil then typeNames[t.id] = name end
    end
  end
  local name = typeNames[id]
  return name ~= nil and (TYPED[name] or name:find("^CHANNEL") ~= nil)
end

-- What a player typed, out of a typed line: everything after the sender's link and the ": " that closes the
-- line's opening words ("[Name] says: ", "[ギルド] [Name]: "). → that text, or nil when the line is not shaped so
local function typedPart(text)
  local _, linkEnd = text:find("|HBNplayer:.-|h.-|h")
  if not linkEnd then _, linkEnd = text:find("|Hplayer:.-|h.-|h") end
  if not linkEnd then return nil end
  local colon = text:find(": ", linkEnd + 1, true)
  -- the opening words after the name are short and hold no link of their own
  if not colon or colon - linkEnd > 40 or text:sub(linkEnd + 1, colon):find("|H", 1, true) then return nil end
  local rest = text:sub(colon + 2)
  return rest ~= "" and rest or nil
end

-- /wfjchat probe: the next copy click also prints what the chat frame holds for that line.
function Cards.probe(line, text)
  local info = line.messageInfo
  local extra = type(info) == "table" and info.extraData or nil
  local id = type(extra) == "table" and extra[1] or nil
  local out = { "messageInfo=" .. type(info), "extraData=" .. type(extra),
    "n=" .. tostring(type(extra) == "table" and extra.n or nil), "id=" .. (secret(id) and "secret" or tostring(id)) }
  if type(extra) == "table" then
    for i = 1, math.min(extra.n or #extra, 8) do
      out[#out + 1] = i .. ":" .. (secret(extra[i]) and "secret" or type(extra[i]))
    end
  end
  local name
  if typeNames and id ~= nil and not secret(id) then name = typeNames[id] end
  out[#out + 1] = "type=" .. tostring(name)
  out[#out + 1] = "typed=" .. tostring(typedLine(line))
  out[#out + 1] = "part=" .. tostring(typedPart(text) ~= nil)
  print("WFJ probe " .. table.concat(out, " "))
  print("WFJ probe text " .. text:gsub("|", "||"))
  WFJ_ChatWords.probe = { table.concat(out, " "), text }
end

local function showButton(line, text)
  local b = ensureButton()
  b.line, b.raw = line, text
  local part = typedLine(line) and typedPart(text) or nil
  b.text = WFJ.ChatWords.plain(part or text)
  b:ClearAllPoints()
  b:SetPoint("TOPRIGHT", line, "TOPRIGHT", 0, 0)
  b:Show()
end

local function showWord(line, text, w)
  if shown and shown.line == line and shown.text == text and shown.first == w.first then return end
  if not boundary(text, w.first) or not boundary(text, w.last + 1) then return end
  local ok, areas = pcall(line.CalculateScreenAreaFromCharacterSpan, line, w.first, w.last + 1)
  if not ok or type(areas) ~= "table" or secret(areas) or not areas[1] then return end
  clear()
  local a = ensureAnchor()
  a:ClearAllPoints()
  a:SetAllPoints(line)
  a:Show()
  for i, r in ipairs(areas) do
    local t = a.tints[i]
    if not t then
      t = a:CreateTexture(nil, "BACKGROUND")
      a.tints[i] = t
    end
    t:SetColorTexture(TINT[1], TINT[2], TINT[3], TINT[4])
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", r.left, r.bottom)
    t:SetSize(math.max(r.width, 1), math.max(r.height, 1))
    t:Show()
  end
  local _, size = line:GetFont()
  local r = areas[1]
  local card = w.card or w.gloss
  local hint = WFJ.ReadingView and WFJ.ReadingView.hint and WFJ.ReadingView.hint() or nil
  WFJ.ReadingPopup.show(a, r.left + r.width / 2, r.bottom + r.height + 2, w, card, size, hint)
  shown = { line = line, text = text, first = w.first, last = w.last, word = w }
end

-- The save click: a press and a release on the same word, with the save click's modifiers held.
local function save()
  local s = shown
  if not s or not WFJ.WordSave then return end
  local run
  for _, r in ipairs(WFJ.ChatWords.runs(s.text)) do
    if s.first >= r.first and s.last <= r.last then run = r end
  end
  if not run then return end
  local a, w = anchor, s.word
  a.kind, a.id, a.surface, a.fs = "chat", "chat", "chat", s.line
  a.text = s.text:sub(run.first, run.last)
  local word = { word = w.word, reading = w.reading, first = w.first - run.first + 1,
    last = w.last - run.first + 1, card = w.card or w.gloss }
  pcall(WFJ.WordSave.release, a, word)
end

local function poll()
  local down = IsMouseButtonDown("LeftButton") == true
  if down and not wasDown then
    pressed = shown and shown.first or nil
  elseif not down and wasDown then
    if pressed and shown and shown.first == pressed then save() end
    pressed = nil
  end
  wasDown = down
end

local function active()
  local S = WFJ.State
  return S and S.enabled and not S.modifierHeld
end

local function wordAt(text, i)
  if WFJ.State.direction == "en" then return WFJ.ChatWords.englishAt(text, i) end
  return WFJ.ChatWords.japaneseAt(text, i)
end

local function look()
  if not active() or type(CHAT_FRAMES) ~= "table" then
    clear()
    hideButton()
    return
  end
  local cx, cy = GetCursorPosition()
  for _, name in ipairs(CHAT_FRAMES) do
    local f = _G[name]
    if f and f.visibleLines and f:IsVisible() and f:IsMouseOver() then
      local scale = f:GetEffectiveScale()
      local x, y = cx / scale, cy / scale
      for _, line in ipairs(f.visibleLines) do
        if line:IsVisible() and line:GetAlpha() > 0.2 and line:IsMouseOver() then
          local text = line:GetText()
          if type(text) == "string" and not secret(text) and text ~= "" then
            showButton(line, text)
            local ok, i, inside = pcall(line.FindCharacterIndexAtCoordinate, line, x, y)
            if ok and inside and type(i) == "number" and not secret(i) then
              local w = WFJ.ReadingView.enabled and wordAt(text, i) or nil
              if w then
                showWord(line, text, w)
                poll()
                return
              end
            end
            clear()
            return
          end
        end
      end
    end
  end
  clear()
  hideButton()
end

local driver = CreateFrame("Frame")
local since = 0
driver:SetScript("OnUpdate", function(_, elapsed)
  since = since + elapsed
  if since < EVERY then return end
  since = 0
  local ok, err = pcall(look)
  if not ok and not Cards.failed then
    Cards.failed = err
    print("WFJ chat trial: " .. tostring(err))
  end
end)
