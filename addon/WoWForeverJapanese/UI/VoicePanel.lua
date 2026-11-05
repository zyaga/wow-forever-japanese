-- UI/VoicePanel.lua: the voice panel (ADR-063). While a voiced line plays it shows the speaker's head
-- (UI/VoicePanelHead), the NPC's name and title as the client showed them, and the line's Japanese a sentence at a
-- time in step with the audio, with word cards (UI/VoicePanelText); the lines waiting their turn, each one clickable;
-- and pause / resume, play again, whole text and close.
--   * It draws only: UI/VoicePlayer decides what plays and fires State "voiceQueue" on every change; the panel reads
--     VoicePlayer.state().
--   * Its look is one of four (UI/VoicePanelLooks) from the Panel size and Panel style settings; Off hides it.
--   * Never while translation or voice is off. The reveal key does not hide it: it shows the line's English.
--   * Built on the first voiced line, so without a voice pack no frame exists.
--   * The panel follows forever-vo's talking-head panel in its design, and its faction parchment choice is adapted
--     from forever-vo's ForeverVO/UI/TalkingHead.lua (MIT License; see ATTRIBUTION.md).
local _, WFJ = ...
local Panel = {}
WFJ.VoicePanel = Panel

local Compat = WFJ.Compat
local Q = WFJ.VoiceQueue
local LOOKS = WFJ.VoicePanelLooks
local Head = WFJ.VoicePanelHead
local Text = WFJ.VoicePanelText

local FADE_DELAY = 3 -- seconds after the last line (or a pause) before the panel fades
local FADE_TIME = 0.6
local COMBAT_ALPHA = 0.4
local TICK = 0.1
local BUTTON = 28 -- the icons have wide transparent margins: smaller reads as a dot (the window button's size)
local CLOSE = 26 -- the client's close button at this size matches the row
local QUEUE_ROW = 15 -- a waiting-list row's height
local QUEUE_MAX = 6 -- rows the waiting list shows; the rest are counted in its header
local LABEL_SIZE = 11
-- the panel's own words, Japanese like the other tool windows, English while the reveal key is held or translation
-- is off (addon interface text, not game text)
local WORDS = {
  upNext = { "Up next (click to play)", "次に読む（クリックで再生）" },
  more = { "Up next (click to play), %d more", "次に読む（クリックで再生）ほか%d件" },
  pause = { "Pause", "一時停止" }, resume = { "Resume", "再開" },
  replay = { "Play again from the start", "最初から再生" }, whole = { "Show the whole text", "全文を表示" },
  ["questframe.detail"] = { "Quest", "クエスト" }, ["questframe.progress"] = { "Progress", "途中経過" },
  ["questframe.reward"] = { "Turn-in", "完了" }, ["questframe.greeting"] = { "Greeting", "あいさつ" },
  gossip = { "Greeting", "あいさつ" }, itemtext = { "Book", "本" },
}
local ICON = {
  pause = "Interface\\TimeManager\\PauseButton",
  play = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
  replay = "Interface\\TimeManager\\ResetButton",
  book = "Interface\\Spellbook\\Spellbook-Icon", -- the book icon of the client's book window (itemtextframe.xml)
  hilight = "Interface\\Buttons\\UI-Common-MouseHilight",
}

local f -- the panel frame
local displayed -- the queue item on screen
local pages, starts, segs = {}, {}, {} -- the displayed line's pages (UI/VoicePanelText.paginate)
local pageShown -- the page on screen
local english = false -- the panel shows the line's English (the reveal key is down)
local fadeAt, fadeFrom -- the idle fade: when it starts, and when it started
local fadeCount = 0 -- the timing trace numbers each fade it logs
local fadedPaused -- a paused line the panel faded on: it stays away until something plays or the queue changes
local redraw = false -- a look changed: lay the displayed line out again
local inCombat = false

local function now()
  local t = Compat.resolve("GetTime")
  return type(t) == "function" and t() or 0
end

local function look() return f and f.lookNow or LOOKS[Q.opt.look] or LOOKS[1] end

local function hidden()
  return not Q.opt.on or not WFJ.State.enabled or not WFJ.Settings.get("voice.enabled")
end

local function revealed()
  return WFJ.State.modifierHeld and true or false
end

local function word(key, ...)
  local w = WORDS[key]
  if not w then return "" end
  local text = (WFJ.State.enabled and not revealed()) and w[2] or w[1]
  return select("#", ...) > 0 and text:format(...) or text
end

-- ── Text ─────────────────────────────────────────────────────────────────

local function showPage(i)
  if not displayed then return end
  pageShown = i
  if revealed() then
    english = true
    return Text.showEnglish(f.text, displayed)
  end
  english = false
  local page = pages[i] or ""
  Text.showPage(f.text, displayed, page, Text.pageSpans(displayed, segs[i], page))
end

-- the page the audio is on now
local function audioPage(st)
  if not (st.playing and st.startedAt and st.seconds and st.seconds > 0) then return nil end
  local share = (now() - st.startedAt) / st.seconds
  local want = 1
  for i = 1, #starts do if share >= starts[i] then want = i end end
  return want
end

-- ── Layout ───────────────────────────────────────────────────────────────

-- name, title and text start right of the head, or at the edge without one
local function placeText(withHead)
  local L = look()
  f.name:ClearAllPoints()
  f.name:SetPoint("TOPLEFT", f, "TOPLEFT", withHead and L.textLeft or L.textLeftNoHead, L.nameTop)
  f.title:ClearAllPoints()
  f.title:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 1, -2)
  f.text:ClearAllPoints()
  local under = L.title and f.title or f.name
  -- width from two anchors, no bottom anchor: the box is as tall as its text. Word positions are measured from the
  -- bottom of the text (CalculateScreenAreaFromCharacterSpan), so a box stretched below the text put every word card
  -- and highlight under its word. The look's line limit keeps a long sentence inside the panel.
  f.text:SetPoint("TOPLEFT", under, "BOTTOMLEFT", L.title and -1 or 0, -5)
  f.text:SetPoint("RIGHT", f, "RIGHT", L.textRight, 0)
end

-- The player's faction kit (TalkingHeads-Alliance / -Horde), else Neutral. → kit, or nil when the client has none
local function factionKit()
  local T = Compat.resolve("C_Texture")
  local exists = type(T) == "table" and T.GetAtlasExists
  if type(exists) ~= "function" then return nil end
  local factionOf = Compat.resolve("UnitFactionGroup")
  local faction = type(factionOf) == "function" and factionOf("player") or nil
  for _, kit in ipairs({ faction and ("TalkingHeads-" .. faction), "TalkingHeads-Neutral" }) do
    if kit and exists(kit .. "-TextBackground") then return kit end
  end
  return nil
end

-- The chosen look with its faction kit filled in; look 1 when the client has no kit.
local function resolveLook()
  local L = LOOKS[Q.opt.look] or LOOKS[1]
  if not L.kit then return L end
  local kit = factionKit()
  if not kit then return LOOKS[1] end
  return setmetatable({
    bg = { atlas = L.bg.atlas:format(kit), atlasSize = L.bg.atlasSize, crop = L.bg.crop },
    ring = L.ring and { atlas = L.ring.atlas:format(kit), x = L.ring.x, y = L.ring.y } or nil,
    portraitBg = L.portraitBg and { atlas = L.portraitBg.atlas:format(kit) } or nil,
    nameColor = L.kitNameColor[kit] or L.nameColor,
  }, { __index = L })
end

-- An atlas's part only (`crop`: left, right, top, bottom as shares of the atlas), stretched to the panel: the strip
-- takes the parchment's plain middle so its decorated edges are not squashed. → true when cropped
local function cropAtlas(tex, atlas, crop)
  local T = Compat.resolve("C_Texture")
  local info = type(T) == "table" and type(T.GetAtlasInfo) == "function" and T.GetAtlasInfo(atlas) or nil
  local file = info and (info.file or info.filename)
  if not file then return false end
  local du, dv = info.rightTexCoord - info.leftTexCoord, info.bottomTexCoord - info.topTexCoord
  tex:SetTexture(file)
  tex:SetTexCoord(info.leftTexCoord + du * crop[1], info.leftTexCoord + du * crop[2],
    info.topTexCoord + dv * crop[3], info.topTexCoord + dv * crop[4])
  return true
end

local function applyLook()
  local L = resolveLook()
  f.lookNow = L
  f:SetSize(L.width, L.height)
  local bg = f.bg
  bg:ClearAllPoints()
  bg:SetTexCoord(0, 1, 0, 1)
  if L.bg.atlas and L.bg.crop and cropAtlas(bg, L.bg.atlas, L.bg.crop) then
    bg:SetAllPoints(f)
  elseif L.bg.atlas then
    bg:SetAtlas(L.bg.atlas, L.bg.atlasSize and true or false)
    if L.bg.atlasSize then bg:SetPoint("CENTER") else bg:SetAllPoints(f) end
  else
    bg:SetColorTexture(L.bg.color[1], L.bg.color[2], L.bg.color[3], L.bg.color[4])
    bg:SetAllPoints(f)
  end
  f.border:SetShown(L.bg.border and true or false)
  Head.applyLook(f.head, L, f)
  f.name:SetFontObject(L.nameFont)
  f.name:SetTextColor(L.nameColor[1], L.nameColor[2], L.nameColor[3])
  f.title:SetFontObject(L.titleFont)
  f.title:SetTextColor(L.titleColor[1], L.titleColor[2], L.titleColor[3])
  f.title:SetShown(L.title)
  WFJ.Font.set(f.text, WFJ.Font.PATH, L.textSize, "")
  f.text:SetTextColor(L.textColor[1], L.textColor[2], L.textColor[3])
  for _, fs in ipairs({ f.name, f.title, f.text }) do
    if L.shadow then fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1) else fs:SetShadowOffset(0, 0) end
  end
  f.text:SetMaxLines(L.maxLines or 4)
  f.text:SetSpacing(2)
  placeText(f.head.shown ~= false and Q.opt.head)
end

-- bottom centre, where the client puts its own talking head, until the player drags it
local function place()
  f:ClearAllPoints()
  local p = Q.opt.point
  if type(p) == "table" and p[1] then
    f:SetPoint(p[1], Compat.resolve("UIParent"), p[2], p[3], p[4])
  else
    f:SetPoint("BOTTOM", Compat.resolve("UIParent"), "BOTTOM", 0, 96)
  end
end

-- ── Controls and the waiting list ────────────────────────────────────────

local tipFrame -- the panel's own tooltip, so its line can take the bundled face (the game's has no Japanese glyphs)
local function tip(owner, text)
  tipFrame = tipFrame or CreateFrame("GameTooltip", "WFJVoicePanelTip", Compat.resolve("UIParent"),
    "GameTooltipTemplate")
  tipFrame:SetOwner(owner, "ANCHOR_TOP")
  tipFrame:SetText(text, 1, 1, 1)
  local line = Compat.resolve("WFJVoicePanelTipTextLeft1")
  if type(line) == "table" then WFJ.Font.set(line, WFJ.Font.PATH, 13, "") end
  tipFrame:Show()
end

local function hideTip()
  if tipFrame then tipFrame:Hide() end
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

-- every control's alpha in one place (on show and on each tick), so no other call flashes a hidden button
local function applyControls()
  local a = (Q.opt.buttons == "always" or f:IsMouseOver()) and 1 or 0
  for _, b in ipairs(f.controls) do b:SetAlpha(a) end
end

local function lineLabel(item)
  return ("%s  ·  %s"):format(item.name or "?", word(item.surface))
end

-- The lines waiting their turn, above the panel, while there are any: each row plays its line now.
local function updateQueue(st)
  local box, n = f.box, #st.waiting
  if n == 0 then
    box:Hide()
    return
  end
  box.header:SetText(n > QUEUE_MAX and word("more", n - QUEUE_MAX) or word("upNext"))
  local shown = math.min(n, QUEUE_MAX)
  local widest = box.header:GetStringWidth()
  for i = 1, math.max(#box.rows, shown) do
    local row = box.rows[i]
    if not row and i <= shown then
      row = CreateFrame("Button", nil, box)
      row:SetHeight(QUEUE_ROW)
      row:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -20 - (i - 1) * QUEUE_ROW)
      row:SetPoint("RIGHT", box, "RIGHT", -6, 0)
      row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      WFJ.Font.set(row.text, WFJ.Font.PATH, LABEL_SIZE, "")
      row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
      row.text:SetJustifyH("LEFT")
      -- a faint gold band under the mouse, like the word cards' tint (the buttons' round glow smears across a row)
      local band = row:CreateTexture(nil, "HIGHLIGHT")
      band:SetAllPoints(row)
      band:SetColorTexture(1, 0.82, 0, 0.15)
      row:SetScript("OnClick", function(self) if self.key then WFJ.VoicePlayer.playWaiting(self.key) end end)
      box.rows[i] = row
    end
    if row then
      local it = i <= shown and st.waiting[i] or nil
      row.key = it and it.key or nil
      row.text:SetText(it and lineLabel(it) or "")
      row:SetShown(it ~= nil)
      if it then widest = math.max(widest, row.text:GetStringWidth()) end
    end
  end
  box:SetSize(math.ceil(widest) + 22, 26 + shown * QUEUE_ROW)
  box:Show()
end

-- ── Show, hide, fade ─────────────────────────────────────────────────────

local function baseAlpha()
  return (Q.opt.combat and inCombat) and COMBAT_ALPHA or 1
end

-- the window buttons follow the panel's visibility (UI/VoicePlayer shows them only while it is away)
local function buttonsFollow()
  local P = WFJ.VoicePlayer
  if P and P.refreshButtons then pcall(P.refreshButtons) end
end

local function hidePanel()
  if not f then return end
  Text.hideWhole()
  Text.detach()
  Head.setTalking(f.head, false)
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
  if revealed() ~= english then -- the reveal key went down or up: the panel and the whole text follow
    showPage(audioPage(st) or pageShown or 1)
    Text.refreshWhole(displayed, look(), english)
  end
  local want = not english and #pages > 1 and audioPage(st)
  if want and want ~= pageShown then showPage(want) end
  local alpha = baseAlpha()
  -- the mouse on the panel or its whole-text window open holds it: the fade waits until the player has left both
  -- for the delay, and coming back mid-fade brings it back whole
  if fadeAt and (self:IsMouseOver() or Text.wholeShown()) then
    fadeAt, fadeFrom = now() + FADE_DELAY, nil
  end
  if fadeAt and now() >= fadeAt then
    fadeFrom = fadeFrom or now()
    local left = 1 - (now() - fadeFrom) / FADE_TIME
    if left <= 0 then
      fadedPaused = (st.item and not st.playing) and st.item or nil
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
  local st = WFJ.VoicePlayer.state()
  local item = st.item or (displayed and st.last == displayed and displayed) or nil
  if hidden() or not item then return hidePanel() end
  if not displayed and st.item and st.item == fadedPaused and not st.playing then return end -- faded while paused
  if item ~= displayed or redraw then
    redraw = false
    displayed = item
    f.name:SetText(item.name or "")
    f.title:SetText(item.title and ("<" .. item.title:gsub("^<", ""):gsub(">$", "") .. ">") or "")
    pages, starts, segs = Text.paginate(item.ja, look().pageChars)
    Head.load(f.head, item, Q.opt.head, placeText)
    showPage(1)
    Text.refreshWhole(item, look(), revealed())
  end
  if st.playing then
    fadeAt, fadeFrom, fadedPaused = nil, nil, nil
  elseif not fadeAt and Q.opt.idle == "fade" then
    -- nothing playing (the line ended, or is paused) fades like the end of a line
    fadeAt = now() + FADE_DELAY
    if WFJ.Diag then
      fadeCount = fadeCount + 1
      pcall(WFJ.Diag.log, "voicetime", ("fade armed %s #%d"):format(tostring(item.key), fadeCount),
        { paused = st.paused == true, queued = st.item ~= nil, at = now() })
    end
    showPage(st.item and 1 or #pages) -- paused: a resume starts the line again; ended: its last sentence
  elseif st.item then
    showPage(1)
  end
  Head.setTalking(f.head, st.playing)
  updateQueue(st)
  f.pause:SetNormalTexture((st.paused or (st.item ~= nil and not st.playing)) and ICON.play or ICON.pause)
  if not fadeFrom then f:SetAlpha(baseAlpha()) end -- mid-fade, the tick owns the alpha
  applyControls()
  local was = f:IsShown()
  f:Show()
  if not was then buttonsFollow() end
end

-- Locked, the panel lets clicks through to the world under it (it still senses the mouse for its controls and the
-- fade); unlocked, a left-drag moves it. [verified: forever 1.60.1.70245 simplescriptregionapidocumentation.lua:631
-- (SetMouseClickEnabled)]
local function applyLock()
  if f.SetMouseClickEnabled then f:SetMouseClickEnabled(not Q.opt.locked) end
end

local function relayout()
  if not f then return end
  applyLook()
  applyLock()
  if displayed then
    Head.reset(f.head)
    redraw = true
    Panel.update()
  end
end

-- ── Build ────────────────────────────────────────────────────────────────

local function build()
  f = CreateFrame("Button", "WFJVoicePanel", Compat.resolve("UIParent"))
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
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
  f.head = Head.build(f)

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

  f.box = CreateFrame("Frame", nil, f, "TooltipBackdropTemplate")
  f.box:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
  f.box.rows = {}
  f.box.header = f.box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  WFJ.Font.set(f.box.header, WFJ.Font.PATH, LABEL_SIZE, "")
  f.box.header:SetPoint("TOPLEFT", f.box, "TOPLEFT", 10, -7)
  f.box:Hide()

  local P = WFJ.VoicePlayer
  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetSize(CLOSE, CLOSE)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
  f.close:SetScript("OnClick", function() P.clear() end)
  -- the book sits inside the replay button's gold frame (the frame's dark inside hides the icon's own black square
  -- and its centre dot), so it matches the other controls
  f.textButton = control(ICON.replay, function() return word("whole") end, function()
    Text.openWhole(f, displayed, look(), Q.opt.textOpens == "quest", revealed())
  end)
  local book = f.textButton:CreateTexture(nil, "OVERLAY")
  book:SetTexture(ICON.book)
  book:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  book:SetSize(BUTTON * 0.5, BUTTON * 0.5)
  book:SetPoint("CENTER", f.textButton, "CENTER", 0, 0)
  f.textButton:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
  f.replay = control(ICON.replay, function() return word("replay") end, function() P.replay() end)
  f.replay:SetPoint("RIGHT", f.textButton, "LEFT", -2, 0)
  f.pause = control(ICON.pause, function()
    local st = P.state()
    return word((st.paused or not st.playing) and "resume" or "pause")
  end, function() P.togglePause() end)
  f.pause:SetPoint("RIGHT", f.replay, "LEFT", -2, 0)
  f.controls = { f.pause, f.replay, f.textButton, f.close }

  local lockdown = Compat.resolve("InCombatLockdown") -- built mid-combat: dimmed from the start
  inCombat = type(lockdown) == "function" and lockdown() and true or false
  local ev = CreateFrame("Frame", nil, f)
  ev:RegisterEvent("PLAYER_REGEN_DISABLED")
  ev:RegisterEvent("PLAYER_REGEN_ENABLED")
  ev:SetScript("OnEvent", function(_, event)
    inCombat = event == "PLAYER_REGEN_DISABLED"
    if f:IsShown() and not fadeFrom then f:SetAlpha(baseAlpha()) end
  end)

  applyLook()
  applyLock()
  place()
end

-- ── /wfj panel, key bindings, init ───────────────────────────────────────

-- `/wfj panel reset`: back to the bottom centre. `words`: the command's words after "panel"; `say(fmt, ...)` prints.
function Panel.command(words, say)
  local sub = words[1] and words[1]:lower()
  if sub ~= "reset" then return say("panel: /wfj panel reset puts the voice panel back at the bottom centre") end
  Q.opt.point = nil
  if f then place() end
  say("voice panel: back at the bottom centre")
end

function WFJ_VoicePause() WFJ.VoicePlayer.togglePause() end
function WFJ_VoiceReplay() WFJ.VoicePlayer.replay() end

local function update() pcall(Panel.update) end -- a panel error never stops the other listeners of an event

-- Called by Main after VoicePlayer. Every listener is guarded: they share events ("enabled", "modifier", "voice")
-- with UI/Render, which must run whatever happens here.
function Panel.init()
  local wasOn = Q.opt.on
  WFJ.State.on("voiceQueue", function()
    if not Q.opt.on then return end
    if not f and WFJ.VoicePlayer.state().item then pcall(build) end
    update()
  end)
  WFJ.State.on("enabled", update)
  WFJ.State.on("modifier", update)
  WFJ.State.on("voice", update)
  -- a choice on the settings page (voice.panel.*): redraw; switching Panel size to Off ends the line and hides the
  -- panel (only that change: other settings changed while it is Off leave a line playing alone)
  WFJ.State.on("voicePanel", function()
    local on = Q.opt.on
    if not on then
      if wasOn then pcall(WFJ.VoicePlayer.stop) end
      wasOn = false
      return pcall(hidePanel)
    end
    wasOn = true
    pcall(relayout)
  end)
  return true
end
