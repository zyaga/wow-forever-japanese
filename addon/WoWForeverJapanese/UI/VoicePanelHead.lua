-- UI/VoicePanelHead.lua: the voice panel's head (ADR-063): the speaking NPC's 3D model, its portrait ring or frame,
-- loading it, and its talk animation. UI/VoicePanel owns the panel and calls these with the head it built.
--   Head.build(parent) → head · Head.applyLook(head, look, parent) · Head.load(head, item, wanted, onShown)
--   Head.setShown(head, shown) · Head.setTalking(head, talking) · Head.reset(head)
-- The model comes from the unit on screen while that unit is still the speaker (the client is drawing it). Otherwise
-- it comes from a display id, which addresses the client's own model data and needs no creature cache (ADR-088): the
-- one this player's client drew for that NPC (the speaker's `display`, remembered by UI/VoiceQuestLog), else the one
-- shipped for it (WFJ.Data.displays). Only with neither is it asked for by creature id, which needs the creature cache
-- every client build empties. A unit's model, once loaded, reports its display id (State "speakerDisplay"). A speaker
-- with no model (a book, the narrator, an unknown creature) gets no head after the settle and onShown(false) lets the
-- panel move the text left; a model that arrives later still shows. The model frame is never hidden before its load
-- had its chance: a hidden PlayerModel does not keep the model it loads.
-- Adapted from forever-vo's ForeverVO/UI/TalkingHead.lua (MIT License; see ATTRIBUTION.md).
local _, WFJ = ...
local Head = {}
WFJ.VoicePanelHead = Head

local Compat = WFJ.Compat

local TALK_ANIMATION = 60 -- [likely: forever-vo's talk loop on Forever; in-game check: the head's mouth moves]
local MODEL_SETTLE = 0.6 -- seconds a model load gets before a speaker with no model is shown without a head
local ZOOM, CAMERA = 1, 1 -- PlayerModel:SetPortraitZoom, SetCamDistanceScale: the face fills the portrait

local function hasModel(m)
  local ok, id = pcall(m.GetModelFileID, m)
  return ok and id ~= nil and id ~= 0
end

local function animate(h)
  pcall(h.model.SetAnimation, h.model, h.talking and TALK_ANIMATION or 0)
end

-- A unit's model has loaded: its display id goes to whoever remembers it. A secret, missing or zero id is dropped.
local function report(h)
  local who = h.fromUnit
  h.fromUnit = nil
  if not who then return end
  local ok, display = pcall(h.model.GetDisplayInfo, h.model)
  local isSecret = Compat.resolve("issecretvalue")
  if not ok or (type(isSecret) == "function" and isSecret(display)) then return end
  if type(display) == "number" and display > 0 then pcall(WFJ.State.fire, "speakerDisplay", who.creature, display) end
end

-- A model that arrived after the settle hid the head: show it now.
local function arrived(h)
  report(h)
  local w = h.waiting
  if not w or w.key ~= h.loaded or not w.settled or not hasModel(h.model) then return end
  h.waiting = nil
  if w.entry then w.entry.late = true end
  Head.setShown(h, true)
  w.onShown(true)
end

-- → the head: { model, ring, portraitBg, frame } on `parent`
function Head.build(parent)
  local h = {}
  h.portraitBg = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
  h.model = CreateFrame("PlayerModel", nil, parent)
  h.model:SetScript("OnModelLoaded", function(m)
    pcall(m.SetPortraitZoom, m, ZOOM)
    pcall(m.SetCamDistanceScale, m, CAMERA)
    pcall(m.SetFacing, m, 0)
    animate(h)
    arrived(h)
  end)
  h.model:SetScript("OnAnimFinished", function() animate(h) end)
  h.ring = parent:CreateTexture(nil, "OVERLAY")
  -- a thin dark frame round the head, for a look without the client's portrait ring
  h.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  h.frame:SetPoint("TOPLEFT", h.model, "TOPLEFT", -3, 3)
  h.frame:SetPoint("BOTTOMRIGHT", h.model, "BOTTOMRIGHT", 3, -3)
  if h.frame.SetBackdrop then
    h.frame:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
    h.frame:SetBackdropBorderColor(0.2, 0.13, 0.06, 1)
  end
  h.frame:Hide()
  return h
end

-- The look's ring, frame, background and model box. `look` is a resolved look (its faction kit filled in).
function Head.applyLook(h, L, parent)
  if L.ring then
    h.ring:SetAtlas(L.ring.atlas, true)
    h.ring:ClearAllPoints()
    h.ring:SetPoint("TOPLEFT", parent, "TOPLEFT", L.ring.x, L.ring.y)
  end
  h.model:ClearAllPoints()
  h.model:SetPoint("TOPLEFT", parent, "TOPLEFT", L.model.x, L.model.y)
  h.model:SetSize(L.model.size, L.model.size)
  if L.portraitBg then h.portraitBg:SetAtlas(L.portraitBg.atlas) end
  h.portraitBg:ClearAllPoints()
  h.portraitBg:SetAllPoints(h.model)
  h.look = L
  Head.setShown(h, h.shown ~= false)
end

-- Shows or hides the head's pieces for the current look (the model by alpha: see the file's header).
function Head.setShown(h, shown)
  h.shown = shown
  local L = h.look or {}
  h.model:SetAlpha(shown and 1 or 0)
  h.ring:SetShown(shown and L.ring and true or false)
  h.portraitBg:SetShown(shown and L.portraitBg and true or false)
  h.frame:SetShown(shown and L.headFrame and true or false)
end

-- Loads `item`'s speaker. `wanted`: the head setting. `onShown(shown)` runs when it is known whether a head shows,
-- and again with true when a model arrives after the settle.
function Head.load(h, item, wanted, onShown)
  local who = item and item.speaker
  if h.settleTimer then h.settleTimer:Cancel(); h.settleTimer = nil end
  h.waiting, h.fromUnit = nil, nil
  if not wanted or not who or not who.creature then
    h.loaded = nil
    Head.setShown(h, false)
    onShown(false)
    return
  end
  local unit = who.unit
  -- the live unit only while it is still this speaker; a secret GUID cannot be compared, so the creature id stands in
  local guid, isSecret = Compat.resolve("UnitGUID"), Compat.resolve("issecretvalue")
  local now = unit and type(guid) == "function" and guid(unit) or nil
  if now ~= nil and type(isSecret) == "function" and isSecret(now) then now = nil end
  if unit and (now == nil or now ~= who.guid) then unit = nil end
  local display, source = nil, "unit"
  if not unit then
    local shipped = WFJ.Data and WFJ.Data.displays
    display, source = who.display, who.displaySource or "saved"
    if not display then
      display = type(shipped) == "table" and shipped[who.creature] or nil
      source = display and "shipped" or "creature"
    end
  end
  local want = unit and ("unit " .. tostring(who.guid)) or display and ("display " .. display)
    or ("creature " .. who.creature)
  if h.loaded == want and hasModel(h.model) then
    Head.setShown(h, true)
    onShown(true)
    return
  end
  h.loaded = want
  Head.setShown(h, true)
  onShown(true)
  local w = { key = want, onShown = onShown }
  h.waiting = w
  if unit then
    h.fromUnit = who
    h.model:SetUnit(unit)
  else
    h.model:ClearModel()
    if display then h.model:SetDisplayInfo(display) else h.model:SetCreature(who.creature) end
  end
  local timer = Compat.resolve("C_Timer")
  if type(timer) == "table" and type(timer.NewTimer) == "function" then
    h.settleTimer = timer.NewTimer(MODEL_SETTLE, function()
      h.settleTimer = nil
      local loaded = hasModel(h.model)
      w.settled = true
      if not unit then
        local ok, entry = pcall(WFJ.Diag.log, "voicehead", source .. " " .. who.creature,
          { display = display, model = loaded })
        w.entry = ok and entry or nil
      end
      if loaded then
        h.waiting = nil
        report(h)
      end
      Head.setShown(h, loaded)
      onShown(loaded)
    end)
  end
end

function Head.setTalking(h, talking)
  if h.talking == talking then return end
  h.talking = talking
  animate(h)
end

-- Forgets the loaded model, so the next load starts again (a look change).
function Head.reset(h)
  h.loaded = nil
end
