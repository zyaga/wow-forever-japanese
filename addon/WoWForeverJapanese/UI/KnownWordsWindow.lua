-- UI/KnownWordsWindow.lua: the known words window (docs/systems/word-status.md). A tool window the player opens
-- (/wfj known, the Words settings page): paste a list of words and mark them known or ignored (Core/WordImport),
-- see the counts and how much of the game's text is known (Core/WordScore), and get the statuses back as text.
-- After an import the box holds the pieces the game's text does not use. It shows no game text.
local _, WFJ = ...
local Window = {}
WFJ.KnownWordsWindow = Window

local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText

local WIDTH, HEIGHT, LEFT = 580, 540, 16
local INNER = WIDTH - 2 * LEFT
local frame
local lang -- the language of the words being pasted: nil until the window opens (then the one being studied)
local as = "known" -- what an import marks its matches
local box = "paste" -- what the box holds: "paste", "missing" (after an import) or "exported"

-- the language a player studies: English in English first, Japanese otherwise
function Window.studied()
  return WFJ.State.direction == "en" and "en" or "ja"
end

local function put(fs, key, size, ...)
  W.put(fs, W.pick(Text.get(key, ...)), size)
end

-- → the whole-game score line and the per-kind line for `language`, each as an English and Japanese pair
function Window.scoreText(language)
  local score = WFJ.WordScore.game(language)
  local whole = score.counted > 0 and ("%.1f"):format(100 * score.known / score.counted) or "0"
  local en, ja = {}, {}
  for _, kind in ipairs(WFJ.WordFrequency.KINDS) do
    local share = (WFJ.WordScore.percent(score.kinds[kind].known, score.kinds[kind].counted) or 0) .. "%"
    local kindEn, kindJa = Text.get("marks.kind." .. kind)
    en[#en + 1] = kindEn .. " " .. share
    ja[#ja + 1] = kindJa .. " " .. share
  end
  local gameEn, gameJa = Text.get("marks.game", whole)
  return gameEn .. "\n" .. table.concat(en, "   "), gameJa .. "\n" .. table.concat(ja, "   ")
end

-- → the counts line for `language` as an English and Japanese pair
function Window.countsText(language)
  local known, learning, ignored = WFJ.WordStatus.counts(language)
  return Text.get("marks.status", known, learning, ignored, WFJ.WordFrequency.count(language))
end

local function relabel()
  if not frame then return end
  put(frame.title, "known.title", 13)
  put(frame.explain, "known.explain", 12)
  local label = box == "missing" and "known.missing" or box == "exported" and "known.exported" or "known.paste"
  put(frame.boxLabel, label, 11)
  local langEn, langJa = Text.get("known.language")
  local nameEn, nameJa = Text.get("known.language." .. lang)
  frame.language:setLabel(langEn .. ": " .. nameEn, langJa .. "：" .. nameJa)
  local asEn, asJa = Text.get("known.as")
  local statusEn, statusJa = Text.get("marks." .. as)
  frame.as:setLabel(asEn .. ": " .. statusEn, asJa .. "：" .. statusJa)
  frame.import:setLabel(Text.get("known.import"))
  frame.export:setLabel(Text.get("known.export"))
  local last = WFJ.WordStatus.lastImport(lang)
  if last then
    put(frame.last, "known.last", 12, last.marked or 0, last.already or 0, last.kept or 0, last.missing or 0)
  else
    W.put(frame.last, "", 12)
  end
  W.put(frame.counts, W.pick(Window.countsText(lang)), 12)
  W.put(frame.score, W.pick(Window.scoreText(lang)), 12)
end

-- Marks the box's words and leaves the pieces it could not find in the box. → the import's result
function Window.import()
  -- statuses saved by a newer version cannot be changed here: the pasted words stay in the box, with why
  if WFJ.WordStatus.readonly() then
    W.put(frame.last, W.pick(Text.get("marks.refused")), 12)
    return nil
  end
  local result = WFJ.WordImport.apply(lang, frame.text.getText(), as)
  box = #result.missing > 0 and "missing" or "paste"
  frame.text.editor:SetText(table.concat(result.missing, "\n"))
  relabel()
  return result
end

-- Fills the box with the player's statuses, selected for the player's own copy.
function Window.export()
  box = "exported"
  frame.text.editor:SetText(WFJ.WordImport.export(lang))
  frame.text.focusAll()
  relabel()
end

local function build()
  local f = W.toolWindow("WFJKnownWordsWindow", WIDTH, HEIGHT)
  frame = f
  local function line(y, r, g, b)
    local fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", LEFT, y)
    fs:SetWidth(INNER)
    fs:SetJustifyH("LEFT")
    if r then fs:SetTextColor(r, g, b) end
    return fs
  end
  f.explain = line(-68)
  f.language = W.button(f, "", nil, 170, function()
    lang = lang == "ja" and "en" or "ja"
    relabel()
  end)
  f.language:SetPoint("TOPLEFT", LEFT, -92)
  f.as = W.button(f, "", nil, 170, function()
    as = as == "known" and "ignored" or "known"
    relabel()
  end)
  f.as:SetPoint("TOPLEFT", LEFT + 180, -92)
  f.boxLabel = line(-124)
  f.text = W.scrollText(f, LEFT, -140, INNER, 236, { editable = true })
  -- a word list is thousands of words: no letter limit
  if f.text.box.SetMaxLetters then f.text.box:SetMaxLetters(0) end
  f.import = W.button(f, "", nil, 140, function() Window.import() end)
  f.import:SetPoint("TOPLEFT", LEFT, -384)
  f.export = W.button(f, "", nil, 140, function() Window.export() end)
  f.export:SetPoint("TOPLEFT", LEFT + 150, -384)
  f.last = line(-416, 0.5, 1, 0.5)
  f.counts = line(-436)
  f.score = line(-458, 1, 0.82, 0)
  return f
end

function Window.open()
  if not frame then build() end
  lang = lang or Window.studied()
  relabel()
  frame:Show()
  return frame
end

WFJ.State.on("language", function() if frame and frame:IsShown() then pcall(relabel) end end)
WFJ.State.on("wordStatus", function() if frame and frame:IsShown() then pcall(relabel) end end)
