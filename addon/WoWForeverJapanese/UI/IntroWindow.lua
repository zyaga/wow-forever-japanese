-- UI/IntroWindow.lua: the window a first install shows once, at its first login (docs/systems/settings.md).
-- Core/Intro decides when; Main hands it IntroWindow.request, which opens it. It is the one addon window that shows
-- both languages at once, a Japanese block above an English one: the player has not learned the reveal key yet, so
-- a one-language window could be unreadable to them. The reveal key and the translation switch change nothing here.
-- Lines: what the addon does,
-- the reveal key (named as set), the word readings, the minimap button and, while no voice pack has loaded, the
-- voice download with its address to copy. Only the addon's own copy (UI/OptionsText), never game text.
local _, WFJ = ...
local IntroWindow = {}
WFJ.IntroWindow = IntroWindow

local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText
local WIDTH, LEFT = 520, 26
local TEXT_WIDTH = WIDTH - 2 * LEFT
-- the inset panel moved up under the title bar and down to the bottom edge, as in UI/CollectorReminder
local INSET_TOP, INSET_BOTTOM = 24, 4
local TOP, BOTTOM, PAD = INSET_TOP + 4, INSET_BOTTOM + 4, 12
local LINE, BLOCK = 7, 14 -- between lines in a block; above and below the rule between the two blocks
local HEAD = 10 -- under a block's opening line
local KEY = "|cffffd200%s|r" -- the reveal key's name, in the gold the client uses for key names
local BULLETS = { ja = "・", en = "• " }
local BOX, BUTTON = 20, 22

IntroWindow.frame = nil
IntroWindow.closedByPlayer = false -- Close, Esc or any hide outside a cinematic: it stays closed
IntroWindow.waiting = false -- a cinematic is playing: open when it ends
local watcher -- the frame that hears the cinematic events, made by the first request

-- Two font strings per line, not W.label: a W.label re-shows one language whenever the reveal key flips.
local function line(p)
  local r = {}
  r.ja = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  r.en = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  for _, fs in ipairs({ r.ja, r.en }) do
    fs:SetWidth(TEXT_WIDTH)
    fs:SetJustifyH("LEFT")
  end
  r.en:SetTextColor(W.JA_COLOR[1], W.JA_COLOR[2], W.JA_COLOR[3])
  return r
end

-- A point's two texts, each with its block's bullet; the opening line has none and is a size up.
local function fill(r, en, ja, lead)
  if lead then
    W.put(r.ja, ja, 13)
    W.put(r.en, en, 12)
  else
    W.put(r.ja, BULLETS.ja .. ja, 12)
    W.put(r.en, BULLETS.en .. en, 11)
  end
end

-- The wrapped height of a line [likely: FontString:GetStringHeight with a set width; in-game check: the intro window
-- checklist in docs/testing/strategy.md]; the specs' stub has none.
local function height(fs)
  return math.max(14, fs.GetStringHeight and math.ceil(fs:GetStringHeight()) or 0)
end

local function build()
  local f = W.toolWindow("WFJIntro", WIDTH, 300)
  -- where the client opens its own popups, clear of the character [verified: forever-ui-1.60.1.70425
  -- blizzard_staticpopup_game/gamedialog.xml:350, TOP 0,-135]; it grows down, so the voice section moves nothing
  f:ClearAllPoints()
  f:SetPoint("TOP", 0, -135)
  if f.Inset then
    f.Inset:ClearAllPoints()
    f.Inset:SetPoint("TOPLEFT", 4, -INSET_TOP)
    f.Inset:SetPoint("BOTTOMRIGHT", -6, INSET_BOTTOM)
  end
  local p = CreateFrame("Frame", nil, f)
  p:SetPoint("TOPLEFT", 0, -TOP)
  p:SetPoint("TOPRIGHT", 0, -TOP)
  p:SetHeight(1)
  f.page = p
  f.lead, f.hold, f.readings, f.minimap, f.voice = line(p), line(p), line(p), line(p), line(p)
  f.lines = { f.lead, f.hold, f.readings, f.minimap } -- always shown; the voice line is not
  f.box = W.copyBox(p, LEFT, 0, TEXT_WIDTH - 12, WFJ.Options.VOICE_URL)
  W.put(f.title, WFJ.Options.TITLE, 13)
  local en, ja = Text.get("intro.lead")
  fill(f.lead, en, ja, true)
  for _, fs in ipairs({ f.lead.ja, f.lead.en }) do fs:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3]) end
  fill(f.readings, Text.get("intro.readings"))
  fill(f.minimap, Text.get("intro.minimap"))
  en, ja = Text.get("intro.voice")
  W.put(f.voice.ja, ja, 12)
  W.put(f.voice.en, en, 11)
  f.voiceTitle = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  en, ja = Text.get("intro.voiceTitle")
  W.put(f.voiceTitle, ja .. " / " .. en, 13)
  f.voiceTitle:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  -- the gold rule between the blocks, as under the settings pages' section titles
  f.rule = p:CreateTexture(nil, "ARTWORK")
  f.rule:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.45)
  f.rule:SetSize(TEXT_WIDTH, 1)
  f.voiceRule = p:CreateTexture(nil, "ARTWORK")
  f.voiceRule:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.45)
  f.voiceRule:SetSize(TEXT_WIDTH, 1)
  en, ja = Text.get("intro.close")
  -- one caption with both words, so W.pick has nothing to switch
  f.close = W.button(p, ja .. " / " .. en, nil, 140, function() IntroWindow.close() end)
  f:HookScript("OnHide", function() IntroWindow.hidden() end)
  IntroWindow.frame = f
  return f
end

-- Runs fn after `seconds` (1 by default), or now where the client timer is missing (the specs).
local function later(fn, seconds)
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then C_Timer.After(seconds or 1, fn) else fn() end
end

-- The Japanese lines as one block, a gold rule, their English as another; while no voice pack has loaded, another
-- rule and the voice section (its title, one sentence in each language, the address to copy); then the button.
-- Each line hangs from the one above it, so the gaps never depend on a measured height; only the window's does.
local function layout(f, voice)
  local rows = { f.lead, f.hold, f.readings, f.minimap }
  local prev, used
  local function chain(region, gap, x)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", x or 0, -gap)
    used = used + gap + (region.GetObjectType and region:GetObjectType() == "FontString" and height(region) or 0)
    prev = region
  end
  f.lead.ja:ClearAllPoints()
  f.lead.ja:SetPoint("TOPLEFT", f.page, "TOPLEFT", LEFT, -PAD)
  prev, used = f.lead.ja, height(f.lead.ja)
  for i = 2, #rows do chain(rows[i].ja, i == 2 and HEAD or LINE) end
  chain(f.rule, BLOCK)
  chain(f.lead.en, BLOCK)
  for i = 2, #rows do chain(rows[i].en, i == 2 and HEAD or LINE) end
  if voice then
    chain(f.voiceRule, BLOCK)
    chain(f.voiceTitle, BLOCK)
    chain(f.voice.ja, HEAD)
    chain(f.voice.en, LINE)
    chain(f.box, LINE + 2, 6) -- InputBoxTemplate's left cap sits outside the frame
    used = used + BOX
  end
  f.close:ClearAllPoints()
  f.close:SetPoint("BOTTOM", f, "BOTTOM", 0, BOTTOM + PAD)
  f:SetHeight(TOP + PAD + used + BLOCK + BUTTON + PAD + BOTTOM)
end

local function refused(f)
  for _, r in ipairs({ f.lead, f.hold, f.readings, f.minimap, f.voice }) do
    if WFJ.Font.isPending(r.ja) or WFJ.Font.isPending(r.en) then return true end
  end
  return false
end

-- A first install's first login is a fresh launch, when the client refuses the bundled face until its file loads
-- (UI/Font, Main's font retry): the lines were measured in another face and wrap differently once it lands. Checks
-- once a second and lays the window out again when Font's retry has applied it, for as long as Main keeps retrying.
local function relayoutWhenFonts(f, voice)
  if f.fontTicker or not refused(f) or type(C_Timer) ~= "table" then return end
  local tries = 0
  f.fontTicker = C_Timer.NewTicker(1, function(ticker)
    tries = tries + 1
    local waiting = refused(f)
    if not waiting and f:IsShown() then layout(f, voice) end
    if not waiting or tries >= 600 then
      ticker:Cancel()
      f.fontTicker = nil
    end
  end)
end

-- Names the reveal key as it is set now, shows the voice line only without a pack, and shows the window. → the frame
-- noVoice: draws the voice line as if no pack had loaded (`/wfj debug intro novoice`).
function IntroWindow.open(noVoice)
  local f = IntroWindow.frame or build()
  fill(f.hold, Text.get("intro.hold", KEY:format(WFJ.Options.keyName())))
  local voice = noVoice == true or not (WFJ.Voice and WFJ.Voice.hasPack())
  for _, region in ipairs({ f.voiceRule, f.voiceTitle, f.voice.ja, f.voice.en, f.box }) do W.setShown(region, voice) end
  layout(f, voice)
  -- a FontString given new text may report its old height until the client has drawn it once [likely; in-game
  -- check: the intro window checklist in docs/testing/strategy.md]: the height is taken again on the next frame
  later(function() if f:IsShown() then layout(f, voice) end end, 0)
  relayoutWhenFonts(f, voice)
  f:Show()
  return f
end

function IntroWindow.close()
  if IntroWindow.frame then IntroWindow.frame:Hide() end
end

-- ── When it opens ───────────────────────────────────────────────────────────
-- The client closes every window in UISpecialFrames (which is how Esc reaches this one) on its own
-- PLAYER_ENTERING_WORLD [verified: forever-ui-1.60.1.70425 blizzard_game/shared/eventimplementation.lua:306], when a
-- cinematic starts, such as a new character's race intro (CinematicFrame is a full-area panel, so showing it closes
-- the other windows [verified: blizzard_framexml/shared/cinematicframe.lua:89,
-- blizzard_uiparentpanelmanager/shared/uiparentpanelmanager.lua:281]), and again when the interface comes back after
-- it [verified: blizzard_game/shared/game.lua:91]. So the window opens a moment after it is asked for, waits out a
-- cinematic, and comes back after one that hid it. A hide outside a cinematic is the player's.

local function inCinematic()
  local playing = WFJ.Compat.resolve("InCinematic")
  return type(playing) == "function" and playing() == true
end

local function openNow()
  if IntroWindow.closedByPlayer then return end
  if inCinematic() then
    IntroWindow.waiting = true
    return
  end
  -- cleared only now, not at CINEMATIC_STOP: a hide's check a second later must still see a cinematic the player
  -- skipped within that second
  IntroWindow.waiting = false
  -- later than the login step, so the load guard is called again here: a failure is recorded as `intro`
  if WFJ.step then WFJ.step("intro", IntroWindow.open) else IntroWindow.open() end
end

local function onEvent(_, event)
  if IntroWindow.closedByPlayer then return end
  if event == "CINEMATIC_START" then
    IntroWindow.waiting = true
  elseif IntroWindow.waiting then
    later(openNow)
  end
end

-- Core/Intro's show: opens it a moment later, through any cinematic.
function IntroWindow.request()
  if not watcher then
    watcher = CreateFrame("Frame")
    watcher:RegisterEvent("CINEMATIC_START")
    watcher:RegisterEvent("CINEMATIC_STOP")
    watcher:SetScript("OnEvent", onEvent)
  end
  later(openNow)
end

-- A hide during a cinematic is the client's sweep. The cinematic's start may reach this addon after the sweep in the
-- same event, so the call is made a moment later, once CINEMATIC_START has been heard.
function IntroWindow.hidden()
  later(function()
    if IntroWindow.waiting or inCinematic() then return end
    IntroWindow.closedByPlayer = true
    if watcher then
      watcher:UnregisterEvent("CINEMATIC_START")
      watcher:UnregisterEvent("CINEMATIC_STOP")
    end
  end)
end
