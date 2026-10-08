-- UI/VoicePanel.lua: the voice panel (trial build for choosing its form; not the final panel). While a voiced line
-- plays it shows the speaker's 3D head, the NPC's name and title as the client showed them, and the line's Japanese,
-- paged by sentence in step with the audio, with word cards on it. Every look and behaviour is switched with
-- /wfj panel (VoicePanel.command) and kept in WFJ_DB.voicePanel (Core/VoiceQueue.opt).
--   * It draws only: UI/VoicePlayer decides what plays and fires State "voiceQueue" on every change.
--   * Never while English is showing (the reveal key, translation off, voice off); never without a voice pack (no
--     line ever plays then, so it is never built).
--   * Name and title are the client's live text, kept with the queued line in memory for the session.
local _, WFJ = ...
local Panel = {}
WFJ.VoicePanel = Panel

local Compat = WFJ.Compat
local Q = WFJ.VoiceQueue
local LOOKS = WFJ.VoicePanelLooks

local TALK_ANIMATION = 60 -- [likely: the talk loop forever-vo uses on Forever; in-game check: the head's mouth moves]
local MODEL_SETTLE = 0.6 -- seconds a model load gets before a speaker with no model is shown without a head
local FADE_TIME = 0.6
local TICK = 0.1
local BUTTON = 28 -- the icons have wide transparent margins: smaller reads as a dot (the window button's size)
local RUBY_SIZE = 9
local SHORT_PAGE = 12 -- characters: a shorter sentence joins the next page
local KIND_LABEL = {
  ["questframe.detail"] = "Quest", ["questframe.progress"] = "Progress", ["questframe.reward"] = "Turn-in",
  ["questframe.greeting"] = "Greeting", gossip = "Greeting", itemtext = "Book",
}
local ICON = {
  pause = "Interface\\TimeManager\\PauseButton",
  play = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
  replay = "Interface\\TimeManager\\ResetButton",
  text = "Interface\\Spellbook\\Spellbook-Icon", -- the book icon of the client's book window (itemtextframe.xml)
  hilight = "Interface\\Buttons\\UI-Common-MouseHilight",
}

local f -- the panel frame, built on the first line
local displayed -- the queue item on screen
local pages, starts = {}, {} -- the displayed line's pages and where each starts, as a share of the line
local offsets = {} -- the byte where each page starts in the line's Japanese (nil when the page is not a plain slice)
local lineSpans, lineSpansFor -- the displayed line's words, located in the whole line (and the item they are for)
local pageShown -- index of the page on screen
local rec = { surface = "voicepanel", key = "text" } -- the record UI/Readings attaches word cards to
local fullRec = { surface = "voicepanel", key = "full" } -- the full-text window's record
local full -- the full-text window: the whole line being heard, for a sentence the player missed
local rubies = {} -- pooled reading FontStrings for ruby "above"
local fadeAt, fadeFrom -- idle fade: when it starts, and the GetTime it started at
local redraw = false -- a look or text choice changed: lay the displayed line out again
local fadedPaused -- a paused line the panel faded out on: it stays away until something plays or the queue changes
local inCombat = false

local function call(name, ...)
  local fn = Compat.resolve(name)
  if type(fn) == "function" then return fn(...) end
  return nil
end

local function now() return call("GetTime") or 0 end

-- the look in use: the chosen one with its faction kit filled in once applied
local function look() return (f and f.lookNow) or LOOKS[Q.opt.look] or LOOKS[1] end

-- translation or voice off: the panel goes. The reveal key does not hide it: it shows the line's English instead.
local function englishShowing()
  return not WFJ.State.enabled or not WFJ.Settings.get("voice.enabled")
end

local function revealed()
  return WFJ.State.modifierHeld and true or false
end

-- ── Text: pages and readings ───────────────────────────────────────────────

local function chars(s)
  return (s:gsub("[\128-\191]", "")):len()
end

-- The line split after 。！？ and line breaks (a closing bracket stays with its sentence); a short sentence joins
-- the next. "all" keeps the line whole.
local function paginate(ja)
  pages, starts, offsets = {}, {}, {}
  if type(ja) ~= "string" or ja == "" then
    pages[1], starts[1] = "", 0
    return
  end
  if Q.opt.page == "all" then
    pages[1], starts[1], offsets[1] = ja, 0, 1
    return
  end
  local s = ja
  for _, p in ipairs({ "。", "！", "？", "\n" }) do s = s:gsub(p, p .. "\1") end
  for _, close in ipairs({ "」", "』", "）" }) do s = s:gsub("\1" .. close, close .. "\1") end
  local parts, carry = {}, ""
  for raw in (s .. "\1"):gmatch("(.-)\1") do
    local piece = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if piece ~= "" then
      carry = carry == "" and piece or (carry .. piece)
      if chars(carry) >= SHORT_PAGE then
        parts[#parts + 1] = carry
        carry = ""
      end
    end
  end
  if carry ~= "" then
    if #parts > 0 then parts[#parts] = parts[#parts] .. carry else parts[1] = carry end
  end
  local total = 0
  for _, p in ipairs(parts) do total = total + chars(p) end
  local at, from = 0, 1
  for i, p in ipairs(parts) do
    pages[i], starts[i] = p, total > 0 and at / total or 0
    at = at + chars(p)
    local s = ja:find(p, from, true)
    offsets[i] = s
    if s then from = s + #p end
  end
end

-- The words of page `i` (its text `text`): located in the whole line, because a line's word list is in the order of
-- the whole line and a sentence alone can match an earlier sentence's word late and miss its own; then shifted to the
-- page. A page that is not a plain slice of the line (trimmed pieces joined) is looked up on its own.
local function pageSpans(i, text)
  local item = displayed
  if lineSpansFor ~= item then
    lineSpansFor = item
    lineSpans = item and type(item.ja) == "string" and WFJ.Readings.lookup(item.kind, item.id, item.ja) or nil
  end
  local off = offsets[i]
  if not off or not lineSpans then return WFJ.Readings.lookup(item.kind, item.id, text) end
  local last = off + #text - 1
  local out = {}
  for _, sp in ipairs(lineSpans) do
    if sp.first >= off and sp.last <= last then
      out[#out + 1] = { first = sp.first - off + 1, last = sp.last - off + 1, word = sp.word, reading = sp.reading,
        gloss = sp.gloss }
    end
  end
  return out
end

-- The page with each word's reading in brackets after it (少し(すこし)); kana words are left as they are.
-- → the new text and its words, shifted past the inserted readings
local function withInlineRuby(text, spans)
  if not spans or not spans[1] then return text, spans end
  local out, from, shift, moved = {}, 1, 0, {}
  for _, sp in ipairs(spans) do
    out[#out + 1] = text:sub(from, sp.last)
    moved[#moved + 1] = { first = sp.first + shift, last = sp.last + shift, word = sp.word, reading = sp.reading,
      gloss = sp.gloss }
    if sp.reading ~= sp.word then
      local r = "(" .. sp.reading .. ")"
      out[#out + 1] = r
      shift = shift + #r
    end
    from = sp.last + 1
  end
  out[#out + 1] = text:sub(from)
  return table.concat(out), moved
end

local function clearRuby()
  for _, r in ipairs(rubies) do r:Hide() end
end

-- A small reading over each word, placed from the word's rectangle once the text is laid out.
local function layoutRuby(text, spans)
  clearRuby()
  if Q.opt.ruby ~= "above" or not f or f.text:GetText() ~= text then return end
  if not spans then return end
  local n = 0
  for _, sp in ipairs(spans) do
    if sp.reading ~= sp.word then
      local areas = WFJ.ReadingView.spanAreas(f.text, text, sp.first, sp.last, "voicepanel")
      local a = areas and areas[1]
      if a then
        n = n + 1
        local r = rubies[n]
        if not r then
          r = f.rubyLayer:CreateFontString(nil, "OVERLAY")
          WFJ.Font.set(r, WFJ.Font.PATH, RUBY_SIZE, "")
          rubies[n] = r
        end
        local c = look().textColor
        r:SetTextColor(c[1], c[2], c[3], 0.9)
        r:SetText(sp.reading)
        r:ClearAllPoints()
        r:SetPoint("BOTTOM", f.text, "BOTTOMLEFT", a.left + a.width / 2, a.bottom + a.height - 1)
        r:Show()
      end
    end
  end
end

local function detachCards()
  if WFJ.ReadingView and rec.fs then pcall(WFJ.ReadingView.detach, rec) end
end

-- The line's English as the client wrote it into the window, whole (its sentences do not line up with the Japanese
-- pages). No word cards and no readings on it.
local function showEnglish()
  if not displayed then return end
  detachCards()
  clearRuby()
  pageShown = nil
  f.english = true
  f.text:SetText(displayed.en or displayed.ja or "")
end

local function showPage(i)
  if not displayed then return end
  if revealed() then return showEnglish() end
  f.english = false
  pageShown = i
  local text = pages[i] or ""
  local spans = pageSpans(i, text)
  if Q.opt.ruby == "inline" then text, spans = withInlineRuby(text, spans) end
  f.text:SetText(text)
  rec.fs, rec.applied, rec.meta, rec.spans = f.text, text, { kind = displayed.kind, id = displayed.id }, spans
  rec.attachOk, rec.attachErr = nil, nil
  if WFJ.ReadingView then rec.attachOk, rec.attachErr = pcall(WFJ.ReadingView.attach, rec) end
  clearRuby()
  if Q.opt.ruby == "above" then
    local timer = Compat.resolve("C_Timer")
    if type(timer) == "table" then timer.After(0, function() layoutRuby(text, spans) end) end
  end
end

-- ── The head ───────────────────────────────────────────────────────────────

local function hasModel(m)
  local ok, id = pcall(m.GetModelFileID, m)
  return ok and id ~= nil and id ~= 0
end

local function placeText(withHead)
  local L = look()
  local left = withHead and L.textLeft or L.textLeftNoHead
  f.name:ClearAllPoints()
  f.name:SetPoint("TOPLEFT", f, "TOPLEFT", left, L.nameTop)
  f.title:ClearAllPoints()
  f.title:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 1, -2)
  f.text:ClearAllPoints()
  local under = L.title and f.title or f.name
  -- width from two anchors, no bottom anchor: the box is as tall as its text. Word positions are measured from the
  -- bottom of the text (CalculateScreenAreaFromCharacterSpan), so a box stretched below the text put every word card
  -- and highlight under its word. The look's line limit keeps a long sentence inside the panel.
  f.text:SetPoint("TOPLEFT", under, "BOTTOMLEFT", L.title and -1 or 0, -5)
  f.text:SetPoint("RIGHT", f, "RIGHT", L.textRight, 0)
  if f.ring then f.ring:SetShown(withHead and L.ring and true or false) end
  f.portraitBg:SetShown(withHead and L.portraitBg and true or false)
end

local function setHeadShown(shown)
  f.headShown = shown
  if not shown then f.model:SetAlpha(0) else f.model:SetAlpha(1) end
  placeText(shown)
end

local function settle()
  f.settleTimer = nil
  setHeadShown(hasModel(f.model))
end

-- Loads the speaker's model: the unit on screen while it is still the speaker (the client is drawing it), else the
-- creature id. A speaker with no model (a book, the narrator) gets no head and the text moves left. The model frame
-- is never hidden before its load had its chance: a hidden PlayerModel does not keep the model it loads.
local function loadHead(item)
  local who = item.speaker
  if f.settleTimer then f.settleTimer:Cancel(); f.settleTimer = nil end
  if not Q.opt.head or not who or not who.creature then
    f.loaded = nil
    setHeadShown(false)
    return
  end
  local unit = who.unit
  if unit and call("UnitGUID", unit) ~= who.guid then unit = nil end
  local want = unit and who.guid or who.creature
  if f.loaded == want and hasModel(f.model) then
    setHeadShown(true)
    return
  end
  f.loaded = want
  f.model:SetAlpha(1)
  placeText(true)
  if unit then
    f.model:SetUnit(unit)
  else
    f.model:ClearModel()
    f.model:SetCreature(who.creature)
  end
  local timer = Compat.resolve("C_Timer")
  if type(timer) == "table" and type(timer.NewTimer) == "function" then
    f.settleTimer = timer.NewTimer(MODEL_SETTLE, settle)
  end
end

local function setTalking(talking)
  if f.talking == talking then return end
  f.talking = talking
  pcall(f.model.SetAnimation, f.model, talking and TALK_ANIMATION or 0)
end

-- ── Layout (a look) ────────────────────────────────────────────────────────

-- The player's faction kit for a look with `kit` (TalkingHeads-Alliance / -Horde), else Neutral. → kit, or nil when
-- the client has none of them (the look then falls back to look 1's atlases)
local function factionKit()
  local T = Compat.resolve("C_Texture")
  local exists = type(T) == "table" and T.GetAtlasExists
  if type(exists) ~= "function" then return nil end
  local faction = call("UnitFactionGroup", "player")
  for _, kit in ipairs({ faction and ("TalkingHeads-" .. faction), "TalkingHeads-Neutral" }) do
    if kit and exists(kit .. "-TextBackground") then return kit end
  end
  return nil
end

local function applyLook()
  local L = LOOKS[Q.opt.look] or LOOKS[1] -- the chosen look, never the one on screen (that is what changes)
  if L.kit then
    local kit = factionKit()
    if not kit then
      L = LOOKS[1]
    else
      L = setmetatable({
        bg = { atlas = L.bg.atlas:format(kit), atlasSize = L.bg.atlasSize },
        ring = L.ring and { atlas = L.ring.atlas:format(kit), x = L.ring.x, y = L.ring.y } or false,
        portraitBg = L.portraitBg and { atlas = L.portraitBg.atlas:format(kit) } or false,
        nameColor = L.kitNameColor[kit] or L.nameColor,
      }, { __index = L })
    end
  end
  f.lookNow = L
  f:SetSize(L.width, L.height)
  local bg = f.bg
  bg:ClearAllPoints()
  bg:SetTexCoord(0, 1, 0, 1)
  if L.bg.atlas then
    bg:SetAtlas(L.bg.atlas, L.bg.atlasSize and true or false)
    if L.bg.atlasSize then bg:SetPoint("CENTER") else bg:SetAllPoints(f) end
    bg:SetVertexColor(1, 1, 1, 1)
  else
    bg:SetColorTexture(L.bg.color[1], L.bg.color[2], L.bg.color[3], L.bg.color[4])
    bg:SetAllPoints(f)
  end
  f.border:SetShown(L.bg.border and true or false)
  if L.ring then
    f.ring:SetAtlas(L.ring.atlas, true)
    f.ring:ClearAllPoints()
    f.ring:SetPoint("TOPLEFT", f, "TOPLEFT", L.ring.x, L.ring.y)
  end
  f.ring:SetShown(L.ring and true or false)
  f.model:ClearAllPoints()
  f.model:SetPoint("TOPLEFT", f, "TOPLEFT", L.model.x, L.model.y)
  f.model:SetSize(L.model.size, L.model.size)
  if L.portraitBg then f.portraitBg:SetAtlas(L.portraitBg.atlas) end
  f.portraitBg:ClearAllPoints()
  f.portraitBg:SetAllPoints(f.model)
  f.name:SetFontObject(L.nameFont)
  f.name:SetTextColor(L.nameColor[1], L.nameColor[2], L.nameColor[3])
  f.title:SetFontObject(L.titleFont)
  f.title:SetTextColor(L.titleColor[1], L.titleColor[2], L.titleColor[3])
  f.title:SetShown(L.title)
  WFJ.Font.set(f.text, WFJ.Font.PATH, Q.opt.textSize or L.textSize, "")
  f.text:SetTextColor(L.textColor[1], L.textColor[2], L.textColor[3])
  for _, fs in ipairs({ f.name, f.title, f.text, f.count }) do
    if L.shadow then fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
  end
  f.text:SetMaxLines(L.maxLines or 4)
  f.text:SetSpacing(Q.opt.ruby == "above" and (RUBY_SIZE + 1) or 2)
  f.count:SetTextColor(L.titleColor[1], L.titleColor[2], L.titleColor[3])
  placeText(f.headShown ~= false and Q.opt.head)
  f:SetScale(Q.opt.scale or 1)
end

local function place()
  f:ClearAllPoints()
  local p = Q.opt.point
  if type(p) == "table" and p[1] then
    f:SetPoint(p[1], Compat.resolve("UIParent"), p[2], p[3], p[4])
  else
    f:SetPoint("BOTTOM", Compat.resolve("UIParent"), "BOTTOM", 0, 96) -- where the client puts its talking head
  end
end

-- ── Controls and the queue display ─────────────────────────────────────────

local function tip(owner, text)
  local GT = Compat.resolve("GameTooltip")
  if type(GT) ~= "table" then return end
  GT:SetOwner(owner, "ANCHOR_TOP")
  GT:SetText(text)
  GT:Show()
end

local function hideTip()
  local GT = Compat.resolve("GameTooltip")
  if type(GT) == "table" then GT:Hide() end
end

local function control(texture, tooltip, onClick)
  local b = CreateFrame("Button", nil, f)
  b:SetSize(BUTTON, BUTTON)
  b:SetNormalTexture(texture)
  b:SetHighlightTexture(ICON.hilight, "ADD")
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self) tip(self, type(tooltip) == "function" and tooltip() or tooltip) end)
  b:SetScript("OnLeave", hideTip)
  return b
end

local function lineLabel(item)
  return ("%s  ·  %s"):format(item.name or "?", KIND_LABEL[item.surface] or "")
end

local function showWaitingTip(owner)
  local st = WFJ.VoicePlayer.state()
  local GT = Compat.resolve("GameTooltip")
  if type(GT) ~= "table" or #st.waiting == 0 then return end
  GT:SetOwner(owner, "ANCHOR_TOP")
  GT:SetText("Up next")
  for _, it in ipairs(st.waiting) do GT:AddLine(lineLabel(it), 1, 1, 1) end
  GT:Show()
end

local function updateQueue(st)
  local n = #st.waiting
  local count = Q.opt.queue == "count" and n > 0
  f.count:SetText(count and ("+" .. n) or "")
  f.countHit:SetShown(count)
  local box = f.box
  if Q.opt.queue ~= "box" or n == 0 then
    box:Hide()
    return
  end
  for i = 1, math.max(#box.rows, n) do
    local row = box.rows[i]
    if not row and i <= n then
      row = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      row:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -26 - (i - 1) * 16)
      row:SetJustifyH("LEFT")
      box.rows[i] = row
    end
    if row then
      row:SetText(i <= n and lineLabel(st.waiting[i]) or "")
      row:SetShown(i <= n)
    end
  end
  box:SetHeight(34 + n * 16)
  box:Show()
end

local function updateButtons(st)
  local paused = st.paused or (st.item ~= nil and not st.playing)
  f.pause:SetNormalTexture(paused and ICON.play or ICON.pause)
  f.skip:SetEnabled(st.item ~= nil) -- dimmed by the tick, never here: an alpha set here flashed a hidden button
end

local function controlsAlpha()
  if Q.opt.buttons == "always" then return 1 end
  return f:IsMouseOver() and 1 or 0
end

-- every control's alpha in one place (on show and on each tick), so no other call flashes a hidden button
local function applyControls()
  local a = controlsAlpha()
  for _, b in ipairs(f.controls) do b:SetAlpha(b == f.skip and not b:IsEnabled() and a * 0.4 or a) end
end

-- ── Show / hide / tick ─────────────────────────────────────────────────────

local function baseAlpha()
  return (Q.opt.combat and inCombat) and (Q.opt.combatAlpha or 0.4) or 1
end

-- ── The full text ──────────────────────────────────────────────────────────

local FULL_WIDTH, FULL_HEIGHT = 480, 300

local function fillFull()
  if not full or not displayed then return end
  local L = look()
  local parchment = L.textColor[1] < 0.5
  full.bg:SetShown(parchment)
  if parchment then
    full.bg:SetAtlas("QuestBG-Parchment")
    full.title:SetTextColor(L.nameColor[1], L.nameColor[2], L.nameColor[3])
    full.text:SetTextColor(0.12, 0.08, 0.03)
    full.text:SetShadowOffset(0, 0)
  else
    full.title:SetTextColor(1, 0.82, 0.02)
    full.text:SetTextColor(1, 1, 1)
    full.text:SetShadowOffset(1, -1)
  end
  full.title:SetText(displayed.name or "")
  local ja = displayed.ja or ""
  full.text:SetText(ja)
  full.child:SetHeight(math.max(full.text:GetStringHeight() + 8, 10))
  fullRec.fs, fullRec.applied, fullRec.meta = full.text, ja, { kind = displayed.kind, id = displayed.id }
  if WFJ.ReadingView then fullRec.attachOk, fullRec.attachErr = pcall(WFJ.ReadingView.attach, fullRec) end
end

local function buildFull()
  full = CreateFrame("Frame", "WFJVoicePanelText", Compat.resolve("UIParent"), "TooltipBackdropTemplate")
  full:SetSize(FULL_WIDTH, FULL_HEIGHT)
  full:SetFrameStrata("HIGH")
  full:SetClampedToScreen(true)
  full:EnableMouse(true)
  full:SetPoint("BOTTOM", f, "TOP", 0, 6)
  full.bg = full:CreateTexture(nil, "BACKGROUND", nil, 1)
  full.bg:SetPoint("TOPLEFT", 4, -4)
  full.bg:SetPoint("BOTTOMRIGHT", -4, 4)
  full.title = full:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  full.title:SetPoint("TOPLEFT", full, "TOPLEFT", 14, -12)
  local close = CreateFrame("Button", nil, full, "UIPanelCloseButton")
  close:SetSize(26, 26)
  close:SetPoint("TOPRIGHT", full, "TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() full:Hide() end)
  local sf = CreateFrame("ScrollFrame", nil, full, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", full, "TOPLEFT", 14, -36)
  sf:SetPoint("BOTTOMRIGHT", full, "BOTTOMRIGHT", -32, 12)
  full.child = CreateFrame("Frame", nil, sf)
  full.child:SetSize(FULL_WIDTH - 50, 10)
  sf:SetScrollChild(full.child)
  full.text = full.child:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  full.text:SetPoint("TOPLEFT", full.child, "TOPLEFT", 0, 0)
  full.text:SetWidth(FULL_WIDTH - 50)
  full.text:SetJustifyH("LEFT")
  full.text:SetJustifyV("TOP")
  full.text:SetWordWrap(true)
  if full.text.SetNonSpaceWrap then full.text:SetNonSpaceWrap(true) end
  full.text:SetSpacing(3)
  WFJ.Font.set(full.text, WFJ.Font.PATH, 15, "")
  full:SetScript("OnHide", function()
    if WFJ.ReadingView and fullRec.fs then pcall(WFJ.ReadingView.detach, fullRec) end
  end)
  full:Hide()
end

-- A quest line whose quest is in the player's log: the quest log opened at it (the world map's quest pane, which
-- shows it in Japanese). [verified: forever 1.60.1.70245 mainline/questmapframe.lua:1175–1179
-- (QuestMapFrame_OpenToQuestDetails); questlogdocumentation.lua:206 (GetLogIndexForQuestID)] → true when opened
-- → true when opened, else false and why (said in chat in the trial, so a fallback is never a mystery)
local function openQuest(item)
  if type(item.kind) ~= "string" or not item.kind:match("^quest%.") or type(item.id) ~= "number" then
    return false, "this line is not a quest's (an NPC greeting or a book)"
  end
  local QL = Compat.resolve("C_QuestLog")
  local open = Compat.resolve("QuestMapFrame_OpenToQuestDetails")
  if type(QL) ~= "table" or type(QL.GetLogIndexForQuestID) ~= "function" or type(open) ~= "function" then
    return false, "the quest log cannot be opened from here on this client"
  end
  if not QL.GetLogIndexForQuestID(item.id) then return false, "the quest is not in your quest log yet" end
  local ok, err = pcall(open, item.id)
  if not ok then return false, "opening the quest log failed: " .. tostring(err) end
  return true
end

-- Opens the whole text of the line being heard: the quest in the quest log when that is the choice and it is there,
-- else the panel's own window (a second press closes it).
function Panel.toggleText()
  if not f or not displayed then return false end
  if Q.opt.textOpens == "quest" and not (full and full:IsShown()) then
    local opened, why = openQuest(displayed)
    if opened then return true end
    print(("WFJ: whole text in the window: %s"):format(why))
  end
  if not full then buildFull() end
  if full:IsShown() then
    full:Hide()
    return false
  end
  full:Show()
  fillFull()
  return true
end

-- the window buttons follow the panel's visibility (UI/VoicePlayer shows them only while it is away)
local function buttonsFollow()
  local P = WFJ.VoicePlayer
  if P and P.refreshButtons then pcall(P.refreshButtons) end
end

local function hidePanel()
  if not f then return end
  if full then full:Hide() end
  detachCards()
  clearRuby()
  setTalking(false)
  local was = f:IsShown()
  f:Hide()
  f.box:Hide()
  displayed, fadeAt, fadeFrom = nil, nil, nil
  if was then buttonsFollow() end
end

local function onTick(self, elapsed)
  self.since = (self.since or 0) + elapsed
  if self.since < TICK then return end
  self.since = 0
  applyControls()
  local st = WFJ.VoicePlayer.state()
  if revealed() ~= (f.english == true) then -- the reveal key went down or up: English, or back to the page playing
    if revealed() then showEnglish() else showPage(pageShown or 1) end
  end
  if not revealed() and st.playing and st.startedAt and st.seconds and st.seconds > 0 and #pages > 1 then
    local share = (now() - st.startedAt) / st.seconds
    local want = 1
    for i = 1, #starts do if share >= starts[i] then want = i end end
    if want ~= pageShown then showPage(want) end
  end
  local alpha = baseAlpha()
  -- the mouse on the panel or its full-text window open holds it: the fade waits until the player has left both for
  -- the idle delay, and coming back mid-fade brings it back whole. The line's own window does not hold it: while the
  -- panel is away, that window's play button is back (UI/VoicePlayer).
  if fadeAt and (self:IsMouseOver() or (full and full:IsShown())) then
    fadeAt, fadeFrom = now() + (Q.opt.idleDelay or 3), nil
  end
  if fadeAt and now() >= fadeAt then
    fadeFrom = fadeFrom or now()
    local left = 1 - (now() - fadeFrom) / FADE_TIME
    if left <= 0 then
      local st2 = WFJ.VoicePlayer.state()
      fadedPaused = (st2.item and not st2.playing) and st2.item or nil
      return hidePanel()
    end
    alpha = alpha * left
  end
  self:SetAlpha(alpha)
end

-- → whether the panel is on screen (UI/VoicePlayer shows the window's own button only while it is not)
function Panel.visible()
  return f ~= nil and f:IsShown()
end

function Panel.update()
  if not f then return end
  if not Q.opt.on then return hidePanel() end
  local st = WFJ.VoicePlayer.state()
  local item = st.item or (displayed and st.last == displayed and displayed) or nil
  if englishShowing() or not item then return hidePanel() end
  if not displayed and st.item and st.item == fadedPaused and not st.playing then return end -- faded while paused
  if item ~= displayed or redraw then
    redraw = false
    displayed = item
    f.name:SetText(item.name or "")
    f.title:SetText(item.title and ("<" .. item.title:gsub("^<", ""):gsub(">$", "") .. ">") or "")
    paginate(item.ja)
    loadHead(item)
    showPage(1)
    if full and full:IsShown() then fillFull() end
  end
  if st.playing then
    fadeAt, fadeFrom, fadedPaused = nil, nil, nil
  elseif not fadeAt and Q.opt.idle == "fade" then
    -- nothing playing (the line ended, or is paused: the reveal key pauses it) fades like the end of a line
    fadeAt = now() + (Q.opt.idleDelay or 3)
    if st.item then showPage(1) elseif #pages > 1 then showPage(#pages) end -- paused: a resume starts it again
  elseif st.item then
    showPage(1)
  end
  setTalking(st.playing)
  updateQueue(st)
  updateButtons(st)
  if not fadeFrom then f:SetAlpha(baseAlpha()) end -- mid-fade, the tick owns the alpha
  applyControls()
  local was = f:IsShown()
  f:Show()
  if not was then buttonsFollow() end
end

-- ── Build ──────────────────────────────────────────────────────────────────

local function build()
  local UIParent = Compat.resolve("UIParent")
  f = CreateFrame("Button", "WFJVoicePanel", UIParent)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:RegisterForClicks("RightButtonUp")
  f:SetScript("OnClick", function(_, button) if button == "RightButton" then WFJ.VoicePlayer.skip() end end)
  f:SetScript("OnDragStart", function(self) if not Q.opt.locked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint(1)
    Q.opt.point = { p, rp, x, y }
  end)
  f:SetScript("OnUpdate", onTick)
  f:Hide()

  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.border = CreateFrame("Frame", nil, f, "BackdropTemplate")
  f.border:SetAllPoints(f)
  if f.border.SetBackdrop then
    f.border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
    f.border:SetBackdropBorderColor(0.45, 0.32, 0.18, 1)
  end
  f.portraitBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.model = CreateFrame("PlayerModel", nil, f)
  f.model:SetScript("OnModelLoaded", function(m)
    pcall(m.SetPortraitZoom, m, Q.opt.zoom or 1)
    pcall(m.SetCamDistanceScale, m, Q.opt.cam or 1)
    pcall(m.SetFacing, m, 0)
    pcall(m.SetAnimation, m, f.talking and TALK_ANIMATION or 0)
  end)
  f.model:SetScript("OnAnimFinished", function(m) pcall(m.SetAnimation, m, f.talking and TALK_ANIMATION or 0) end)
  f.ring = f:CreateTexture(nil, "OVERLAY")

  f.name = f:CreateFontString(nil, "ARTWORK")
  f.name:SetJustifyH("LEFT")
  f.name:SetMaxLines(1)
  f.title = f:CreateFontString(nil, "ARTWORK")
  f.title:SetJustifyH("LEFT")
  f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight") -- a template font first, then the bundled face
  f.text:SetJustifyH("LEFT")
  f.text:SetJustifyV("TOP")
  f.text:SetWordWrap(true)
  if f.text.SetNonSpaceWrap then f.text:SetNonSpaceWrap(true) end -- Japanese has no spaces to wrap at
  f.rubyLayer = CreateFrame("Frame", nil, f)
  f.rubyLayer:SetAllPoints(f)
  f.rubyLayer:SetFrameLevel(f:GetFrameLevel() + 2)

  f.count = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  f.count:SetPoint("LEFT", f.name, "RIGHT", 8, 0)
  f.countHit = CreateFrame("Frame", nil, f)
  f.countHit:SetAllPoints(f.count)
  f.countHit:EnableMouse(true)
  f.countHit:SetScript("OnEnter", showWaitingTip)
  f.countHit:SetScript("OnLeave", hideTip)

  f.box = CreateFrame("Frame", nil, f, "TooltipBackdropTemplate")
  f.box:SetWidth(300)
  f.box:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
  f.box.rows = {}
  local header = f.box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header:SetPoint("TOPLEFT", f.box, "TOPLEFT", 12, -9)
  header:SetText("Up next")
  f.box:Hide()

  local P = WFJ.VoicePlayer
  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetSize(26, 26) -- the client's close button at this size matched the row (in game)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
  f.close:SetScript("OnClick", function() P.clear() end)
  f.replay = control(ICON.replay, "Play again from the start", function() P.replay() end)
  -- the book sits inside the replay button's gold frame (the frame's dark inside hides the icon's own black square
  -- and its centre dot), so it matches the other controls
  f.textButton = control(ICON.replay, "Show the whole text", function() Panel.toggleText() end)
  local book = f.textButton:CreateTexture(nil, "OVERLAY")
  book:SetTexture(ICON.text)
  book:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  book:SetSize(BUTTON * 0.5, BUTTON * 0.5)
  book:SetPoint("CENTER", f.textButton, "CENTER", 0, 0)
  f.textButton:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
  f.replay:SetPoint("RIGHT", f.textButton, "LEFT", -2, 0)
  f.skip = control(ICON.play, "Next line", function() P.skip() end)
  -- the skip arrow is the play arrow doubled
  local second = f.skip:CreateTexture(nil, "ARTWORK")
  second:SetTexture(ICON.play)
  second:SetAllPoints(f.skip)
  second:SetPoint("TOPLEFT", f.skip, "TOPLEFT", 8, 0)
  second:SetPoint("BOTTOMRIGHT", f.skip, "BOTTOMRIGHT", 8, 0)
  f.skip:SetPoint("RIGHT", f.replay, "LEFT", -8, 0)
  f.pause = control(ICON.pause, function()
    local st = P.state()
    return (st.paused or not st.playing) and "Resume" or "Pause"
  end, function() P.togglePause() end)
  f.pause:SetPoint("RIGHT", f.skip, "LEFT", -2, 0)
  f.controls = { f.pause, f.skip, f.replay, f.textButton, f.close }

  local ev = CreateFrame("Frame", nil, f)
  ev:RegisterEvent("PLAYER_REGEN_DISABLED")
  ev:RegisterEvent("PLAYER_REGEN_ENABLED")
  ev:SetScript("OnEvent", function(_, event)
    inCombat = event == "PLAYER_REGEN_DISABLED"
    if f:IsShown() and not fadeAt then f:SetAlpha(baseAlpha()) end
  end)

  applyLook()
  place()
end

local function ensure()
  if not f then build() end
  return f
end

-- ── /wfj panel ─────────────────────────────────────────────────────────────

local function onOff(v)
  if v == "on" or v == "true" or v == "1" then return true end
  if v == "off" or v == "false" or v == "0" then return false end
  return nil
end

function Panel.status()
  local o = Q.opt
  local p = o.point and ("%s %.0f,%.0f"):format(o.point[1], o.point[3] or 0, o.point[4] or 0) or "default"
  return ("panel %s · look %d · buttons %s · queue %s · idle %s %ss · combat %s %.2f · head %s zoom %.2f cam %.2f"
    .. " · ruby %s · page %s · text %s · size %s · keep %s · scale %.2f · %s · at %s"):format(
    o.on and "on" or "off", o.look, o.buttons, o.queue, o.idle, tostring(o.idleDelay), o.combat and "on" or "off",
    o.combatAlpha or 0.4, o.head and "on" or "off", o.zoom or 1, o.cam or 1, o.ruby, o.page, o.textOpens or "quest",
    tostring(o.textSize or look().textSize), o.keepPlaying and "on" or "off", o.scale or 1,
    o.locked and "locked" or "unlocked", p)
end

local function relayout()
  if not f then return end
  applyLook()
  if displayed then
    f.loaded = nil
    redraw = true
    Panel.update()
  end
end

-- `words`: the command's words after "panel". `say(fmt, ...)` prints. → nothing
function Panel.command(words, say)
  local o = Q.opt
  local sub = words[1] and words[1]:lower()
  local v = words[2] and words[2]:lower()
  local n = tonumber(words[2])
  if sub == nil or sub == "status" then return say("%s", Panel.status()) end
  if sub == "on" or sub == "off" then
    o.on = sub == "on"
    if not o.on then WFJ.VoicePlayer.stop(); hidePanel() end
  elseif sub == "look" and LOOKS[n] and n ~= 2 then -- look 2 is not offered: the settings choose among 1, 3, 4, 5
    o.look = n
    relayout()
  elseif sub == "buttons" and (v == "always" or v == "hover") then
    o.buttons = v
  elseif sub == "queue" and (v == "box" or v == "count") then
    o.queue = v
  elseif sub == "idle" and (v == "fade" or v == "stay") then
    o.idle = v
    if tonumber(words[3]) then o.idleDelay = tonumber(words[3]) end
  elseif sub == "combat" and onOff(v) ~= nil then
    o.combat = onOff(v)
    if tonumber(words[3]) then o.combatAlpha = tonumber(words[3]) end
  elseif sub == "head" and onOff(v) ~= nil then
    o.head = onOff(v)
    relayout()
  elseif (sub == "zoom" or sub == "cam") and n then
    o[sub] = n
    if f then
      pcall(f.model.SetPortraitZoom, f.model, o.zoom)
      pcall(f.model.SetCamDistanceScale, f.model, o.cam)
    end
  elseif sub == "ruby" and (v == "off" or v == "inline" or v == "above") then
    o.ruby = v
    relayout()
  elseif sub == "page" and (v == "sentence" or v == "all") then
    o.page = v
    relayout()
  elseif sub == "size" and n then
    o.textSize = n
    relayout()
  elseif sub == "keep" and onOff(v) ~= nil then
    o.keepPlaying = onOff(v)
  elseif sub == "scale" and n and n >= 0.5 and n <= 1.5 then
    o.scale = n
    if f then f:SetScale(n) end
  elseif sub == "lock" or sub == "unlock" then
    o.locked = sub == "lock"
  elseif sub == "reset" then
    o.point, o.scale = nil, 1
    if f then f:SetScale(1); place() end
  elseif sub == "demo" or sub == "replay" then
    if not WFJ.VoicePlayer.replay() then return say("panel: no line to play again yet (talk to an NPC first)") end
  elseif sub == "text" and (v == "quest" or v == "window") then
    o.textOpens = v
  elseif sub == "text" then
    if not Panel.toggleText() and not (full and full:IsShown()) then
      return say("panel: no line on the panel")
    end
  elseif sub == "cards" then -- why word cards do or do not show on the panel and the whole-text window
    local V = WFJ.ReadingView
    say("cards: readings setting %s · glosses %s · view on %s · attached this session %d · refused %d%s",
      tostring(WFJ.Settings.get("readings.enabled")), tostring(V and V.glossesOn), tostring(V and V.enabled),
      V and V.attached or -1, V and V.refused or -1, V and V.refusedAt and (" (" .. V.refusedAt .. ")") or "")
    for _, r in ipairs({ { "panel", rec }, { "whole text", fullRec } }) do
      local name, x = r[1], r[2]
      local text = x.applied
      if not x.fs or type(text) ~= "string" then
        say("cards %s: nothing attached yet", name)
      else
        local m = x.meta or {}
        local listed = x.spans or WFJ.Readings.lookup(m.kind, m.id, text)
        local ci = V and V.coverInfo and V.coverInfo(x.fs)
        say("cards %s: kind %s · id %s · %d bytes · has | %s · shows it %s · words found %d · attach %s %s",
          name, tostring(m.kind), tostring(m.id), #text, tostring(text:find("|", 1, true) ~= nil),
          tostring(x.fs:GetText() == text), listed and #listed or -1, tostring(x.attachOk), tostring(x.attachErr))
        if ci then
          say("cards %s cover: shown %s · visible %s · %dx%d · %s level %d (text's frame level %d) · motion %s · "
            .. "mouse over it %s · spans %d · same text %s · measuring %s · words measured %d", name,
            tostring(ci.shown), tostring(ci.visible), ci.w or 0, ci.h or 0, tostring(ci.strata), ci.level or -1,
            x.fs:GetParent():GetFrameLevel(), tostring(ci.motion), tostring(ci.over), ci.spans, tostring(ci.sameText),
            tostring(ci.hasUpdate), ci.words)
        else
          say("cards %s cover: none", name)
        end
      end
    end
    local foci = Compat.resolve("GetMouseFoci")
    local list = type(foci) == "function" and foci() or {}
    local names = {}
    for i, fr in ipairs(list) do
      if i > 4 then break end
      local ok, n = pcall(fr.GetDebugName, fr)
      names[#names + 1] = ok and n or tostring(fr)
    end
    return say("cards mouse is over: %s", #names > 0 and table.concat(names, " > ") or "nothing")
  elseif sub == "why" then -- why the panel is up (or not): every input the fade reads
    local st = WFJ.VoicePlayer.state()
    local source = displayed and Compat.resolve(displayed.window)
    return say("panel why: shown %s · line %s · playing %s · paused %s · waiting %d · fade setting %s · fade at %s"
      .. " (now %.1f) · mouse on it %s · whole text open %s · its window %s open %s · English showing %s",
      tostring(f and f:IsShown()), tostring(st.item and st.item.key or (displayed and displayed.key)),
      tostring(st.playing), tostring(st.paused), #st.waiting, tostring(Q.opt.idle),
      fadeAt and ("%.1f"):format(fadeAt) or "none", now(), tostring(f and f:IsMouseOver()),
      tostring(full and full:IsShown()), tostring(displayed and displayed.window),
      tostring(type(source) == "table" and source:IsShown()), tostring(englishShowing()))
  elseif sub == "pause" then
    WFJ.VoicePlayer.togglePause()
  elseif sub == "skip" then
    WFJ.VoicePlayer.skip()
  else
    return say("panel: on|off · look 1|3|4|5 · buttons always|hover · queue box|count · idle fade|stay [s] · "
      .. "combat on|off [alpha] · head on|off · zoom <n> · cam <n> · ruby off|inline|above · page sentence|all · "
      .. "size <px> · keep on|off · scale <0.5-1.5> · lock|unlock|reset · demo · text [quest|window] · why · pause · skip · status")
  end
  if f then Panel.update() end
  say("%s", Panel.status())
end

-- ── Key bindings (Bindings.xml) ────────────────────────────────────────────

function WFJ_VoicePause() WFJ.VoicePlayer.togglePause() end
function WFJ_VoiceSkip() WFJ.VoicePlayer.skip() end
function WFJ_VoiceReplay() WFJ.VoicePlayer.replay() end

-- Called by Main after VoicePlayer. The frame is built on the first line, so without a pack nothing is made.
function Panel.init()
  WFJ.State.on("voiceQueue", function()
    if not Q.opt.on then return end
    if WFJ.VoicePlayer.state().item then ensure() end
    Panel.update()
  end)
  WFJ.State.on("enabled", function() Panel.update() end)
  WFJ.State.on("modifier", function() Panel.update() end)
  -- a choice on the settings page (Core/Settings voice.panel.*): redraw; switching the panel off ends it
  WFJ.State.on("voicePanel", function()
    if not Q.opt.on then
      WFJ.VoicePlayer.stop()
      hidePanel()
      return
    end
    if f then relayout(); Panel.update() end
  end)
  WFJ.State.on("voice", function() Panel.update() end)
  return true
end
