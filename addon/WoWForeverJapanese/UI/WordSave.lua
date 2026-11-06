-- UI/WordSave.lua: saving the highlighted word to the word list (Core/Words, ADR-069, docs/systems/word-list.md).
-- UI/Readings reads the click on its covers and calls release(cover, word); this module checks the save click's
-- modifiers, builds the entry from what the word card shows, takes the optional screenshot and says what happened.
local _, WFJ = ...
local WordSave = {}
WFJ.WordSave = WordSave

local Compat = WFJ.Compat

-- the save click (setting words.saveClick), kept current by its State event: UI/Readings asks every frame
local choice
WFJ.State.on("saveClick", function(v) choice = v end)

function WordSave.choice()
  if choice == nil then choice = WFJ.Settings.get("words.saveClick") end
  return choice
end

local function choiceLabel(c)
  local d = WFJ.Settings.definition("words.saveClick")
  return d and d.choiceText and d.choiceText[c] or c
end

-- Both languages on one line: the player has not necessarily learned to read the Japanese yet.
local function both(key, ...)
  local T = WFJ.OptionsText
  if not T then return nil end
  local en, ja = T.get(key, ...)
  return en .. " ・ " .. ja
end

local function say(key, ...)
  local line = both(key, ...)
  if line then print("WFJ: " .. line) end
end

-- The card's hint until the player has saved a word once; nothing while saving is off.
function WordSave.hint()
  local c = WordSave.choice()
  if c == "off" or WFJ.Words.everSaved() then return nil end
  return both("words.hint", choiceLabel(c))
end

-- ── Screenshot ──────────────────────────────────────────────────────────────

local pending -- the save waiting for its screenshot: { entry, cover, at }
local shotEvents

local function onShot(_, event)
  local p = pending
  if not p then return end -- the player's own screenshot
  pending = nil
  if event == "SCREENSHOT_SUCCEEDED" then
    -- named after the time of the capture: the client names the file then, and this event can come in a later second
    -- [unverified: the screenshot step of the word list checklist, docs/testing/strategy.md]
    local name = WFJ.Words.shotName(p.at, Compat.call("GetCVar", "screenshotFormat"), Compat.resolve("date"))
    WFJ.Words.setShot(p.entry, name)
  end
  say("words.saved", p.entry.word, WFJ.Words.count())
  WFJ.ReadingView.reshow(p.cover)
end

-- Only the card hides: the gold tint stays, so the screenshot shows which word was saved. The chat line waits for
-- the client's answer so it is not in the image.
-- → true when a screenshot was asked for. Not while one is still pending (one name per answer from the client), and
-- not on a client without the call.
local function screenshot(cover, entry)
  if pending or type(Compat.resolve("Screenshot")) ~= "function" then return false end
  if not shotEvents then
    shotEvents = CreateFrame("Frame")
    shotEvents:RegisterEvent("SCREENSHOT_SUCCEEDED")
    shotEvents:RegisterEvent("SCREENSHOT_FAILED")
    shotEvents:SetScript("OnEvent", onShot)
  end
  WFJ.ReadingView.hideCard(cover)
  local p = { entry = entry, cover = cover, at = Compat.call("time") }
  pending = p
  Compat.call("Screenshot")
  -- a client that never answers must not hold the card hidden and block every later screenshot
  local after = Compat.resolve("C_Timer.After")
  if type(after) == "function" then
    after(5, function() if pending == p then onShot(nil, "SCREENSHOT_FAILED") end end)
  end
  return true
end

-- ── Save ────────────────────────────────────────────────────────────────────

-- `cover`: a UI/Readings cover (its text, the record's kind, id and surface); `word`: its hovered word.
function WordSave.save(cover, word)
  local Words = WFJ.Words
  local g = WFJ.Glosses and WFJ.Glosses.get(word.gloss) or word.card
  local title
  if Words.isQuestKind(cover.kind) and WFJ.Lookup then
    local t = WFJ.Lookup.get("quest.title", cover.id)
    title = t and type(t.ja) == "string" and t.ja or nil
  end
  local status, entry = Words.add({
    kind = cover.kind, id = cover.id, surface = cover.surface, text = cover.text, first = word.first,
    last = word.last, word = word.word, reading = word.reading, lemma = g and g.lemma,
    lemmaReading = g and g.lemmaReading, meaning = g and g.meaning, questTitle = title,
  }, Compat.call("time"))
  if status == "added" then
    WFJ.ReadingView.flash(cover) -- the windows and the study queue follow the list's own change event
    if not (WFJ.Settings.get("words.screenshot") and screenshot(cover, entry)) then
      say("words.saved", entry.word, Words.count())
    end
  elseif status == "exists" then
    say("words.exists", entry.word)
  else
    say("words.refused")
  end
  return status
end

-- A click released on the word it started on: saved when the held modifiers are the save click's.
function WordSave.release(cover, word)
  local ok = WFJ.Words.matches(WordSave.choice(), Compat.call("IsControlKeyDown") == true,
    Compat.call("IsShiftKeyDown") == true, Compat.call("IsMetaKeyDown") == true)
  if ok then return WordSave.save(cover, word) end
  return nil
end

-- The reveal key moved onto the save click's modifier, so the save click moved on (Core/Settings).
WFJ.State.on("saveClickMoved", function(c) say("words.moved", choiceLabel(c)) end)
