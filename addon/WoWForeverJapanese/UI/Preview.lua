-- UI/Preview.lua: look-only samples of screens that are not built yet, opened with /wfj preview <name>, so their
-- look can be judged in the game before the real ones are written. Temporary: this file and its slash entry are
-- removed once the real screens exist. Every text here is a made-up sample or the addon's own copy, never game text.
--   /wfj preview card    an English word card over a sample sentence (the pronunciation in the client's font)
--   /wfj preview card2   the same, the pronunciation in the bundled font
--   /wfj preview study   an English study card, its front beside its back
local _, WFJ = ...
local Preview = {}
WFJ.Preview = Preview

local W = WFJ.OptionsWidgets
local CLIENT_FONT = "Fonts\\ARIALN.TTF" -- the client's narrow face: the bundled one lacks some pronunciation letters

local SAMPLE = {
  sentence = "Defeat the wolves near the river and bring back their pelts.",
  word = "defeat", ipa = "/dɪˈfiːt/", ja = "倒して", reading = "たおして", lemma = "倒す", lemmaReading = "たおす",
  jaSentence = "川の近くにいる狼を倒して、毛皮を持ち帰ってくれ。",
}

local function text(parent, size, r, g, b, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  if font then fs:SetFont(font, size, "") else WFJ.Font.set(fs, WFJ.Font.PATH, size, "") end
  fs:SetTextColor(r, g, b)
  fs:SetJustifyH("LEFT")
  return fs
end

local function backdrop(f)
  if not f.SetBackdrop then return end
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  f:SetBackdropColor(0.06, 0.05, 0.04, 0.92)
  f:SetBackdropBorderColor(0.45, 0.32, 0.18, 1)
end

-- ── The English word card ───────────────────────────────────────────────────

local cardWindow
local function buildCard()
  local f = W.toolWindow("WFJPreviewCard", 520, 250)
  W.put(f.title, "Preview: English word card", 13)
  f.sentence = text(f, 15, 1, 1, 1, CLIENT_FONT)
  f.sentence:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 26, 46)
  f.sentence:SetText(SAMPLE.sentence)
  -- the tint a highlighted word gets, over the sample's first word
  f.tint = f:CreateTexture(nil, "ARTWORK")
  f.tint:SetColorTexture(1, 0.82, 0, 0.25)
  f.tint:SetPoint("BOTTOMLEFT", f.sentence, "BOTTOMLEFT", -1, -2)
  f.tint:SetSize(46, 20)
  -- the card, in the word card's own frame and colours
  local c = CreateFrame("Frame", nil, f, "TooltipBackdropTemplate")
  c:SetPoint("BOTTOMLEFT", f.sentence, "TOPLEFT", -8, 10)
  c.word = text(c, 16, 1, 1, 1)
  c.word:SetPoint("TOPLEFT", 10, -10)
  c.word:SetText(SAMPLE.word)
  c.ipa = text(c, 13, 1, 0.82, 0, CLIENT_FONT)
  c.ipa:SetPoint("LEFT", c.word, "RIGHT", 8, 0)
  c.ja = text(c, 15, 0.75, 0.83, 0.95)
  c.ja:SetPoint("TOPLEFT", c.word, "BOTTOMLEFT", 0, -6)
  c.ja:SetText(SAMPLE.ja .. "　|cffc9a65a" .. SAMPLE.reading .. "|r")
  c.lemma = text(c, 12, 0.72, 0.72, 0.72)
  c.lemma:SetPoint("TOPLEFT", c.ja, "BOTTOMLEFT", 0, -5)
  c.lemma:SetText(("辞書形：%s（%s）"):format(SAMPLE.lemma, SAMPLE.lemmaReading))
  c.hint = text(c, 11, 0.6, 0.6, 0.6)
  c.hint:SetPoint("TOPLEFT", c.lemma, "BOTTOMLEFT", 0, -6)
  c.hint:SetText("Ctrl+clickで単語を保存")
  c:SetSize(280, 108)
  f.card = c
  cardWindow = f
  return f
end

local function openCard(bundled)
  local f = cardWindow or buildCard()
  if bundled then WFJ.Font.set(f.card.ipa, WFJ.Font.PATH, 13, "") else f.card.ipa:SetFont(CLIENT_FONT, 13, "") end
  f.card.ipa:SetText(SAMPLE.ipa)
  f:Show()
end

-- ── The English study card ──────────────────────────────────────────────────

local studyWindow
local function side(parent, answered)
  local PAD, WIDTH = 12, 320
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetSize(WIDTH, answered and 250 or 190)
  backdrop(f)
  local inner = WIDTH - 2 * PAD
  local word = text(f, 20, 1, 0.82, 0)
  word:SetPoint("TOPLEFT", PAD, -PAD)
  word:SetText(SAMPLE.word)
  local sentence = text(f, 14, 1, 1, 1, CLIENT_FONT)
  sentence:SetPoint("TOPLEFT", word, "BOTTOMLEFT", 0, -12)
  sentence:SetWidth(inner)
  sentence:SetText(SAMPLE.sentence)
  local last = sentence
  if answered then
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 0.82, 0, 0.45)
    rule:SetPoint("TOPLEFT", sentence, "BOTTOMLEFT", 0, -9)
    rule:SetSize(inner, 1)
    local ipa = text(f, 14, 1, 0.82, 0, CLIENT_FONT)
    ipa:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -9)
    ipa:SetText(SAMPLE.ipa)
    local ja = text(f, 16, 1, 1, 1)
    ja:SetPoint("TOPLEFT", ipa, "BOTTOMLEFT", 0, -8)
    ja:SetText(SAMPLE.ja .. "　|cffc9a65a" .. SAMPLE.reading .. "|r")
    local lemma = text(f, 12, 0.72, 0.72, 0.72)
    lemma:SetPoint("TOPLEFT", ja, "BOTTOMLEFT", 0, -6)
    lemma:SetText(("辞書形：%s（%s）"):format(SAMPLE.lemma, SAMPLE.lemmaReading))
    local jaSentence = text(f, 13, 0.92, 0.92, 0.92)
    jaSentence:SetPoint("TOPLEFT", lemma, "BOTTOMLEFT", 0, -8)
    jaSentence:SetWidth(inner)
    jaSentence:SetText(SAMPLE.jaSentence)
    last = jaSentence
    local again = W.button(f, "Again", "もう一度", 96)
    again:SetPoint("BOTTOMLEFT", PAD, PAD)
    again.caption:SetTextColor(1, 0.35, 0.35)
    local good = W.button(f, "Good", "正解", 96)
    good:SetPoint("LEFT", again, "RIGHT", 8, 0)
    good.caption:SetTextColor(0.45, 1, 0.45)
  else
    local show = W.button(f, "Show answer", "答えを見る", 120)
    show:SetPoint("BOTTOMLEFT", PAD, PAD)
  end
  local footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMRIGHT", -PAD, PAD + 4)
  W.put(footer, "復習3・新規12", 10)
  return f, last
end

local function buildStudy()
  local f = W.toolWindow("WFJPreviewStudy", 700, 330)
  W.put(f.title, "Preview: English study card (front, then back)", 13)
  local front = side(f, false)
  front:SetPoint("TOPLEFT", 20, -44)
  local back = side(f, true)
  back:SetPoint("TOPLEFT", front, "TOPRIGHT", 16, 0)
  studyWindow = f
  return f
end

-- ── Entry point ─────────────────────────────────────────────────────────────

function Preview.open(name, say)
  if name == "card" or name == "card2" then return openCard(name == "card2") end
  if name == "study" then return (studyWindow or buildStudy()):Show() end
  say("preview: card | card2 | study")
end
