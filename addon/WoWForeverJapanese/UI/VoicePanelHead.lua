-- UI/VoicePanelHead.lua: the voice panel's head (ADR-063): the speaking NPC's 3D model, its portrait ring or frame,
-- loading it, and its talk animation. UI/VoicePanel owns the panel and calls these with the head it built.
--   Head.build(parent) → head · Head.applyLook(head, look, parent) · Head.load(head, item, wanted, onShown)
--   Head.setShown(head, shown) · Head.setTalking(head, talking) · Head.reset(head)
-- The model comes from the unit on screen while that unit is still the speaker (the client is drawing it), else from
-- the creature id (the client's creature cache: loads after /reload and a restart, checked in game with creature 837;
-- a new client build empties the cache, so an NPC not seen since has no head). A speaker with no model (a book, the
-- narrator, an uncached creature) gets no head and onShown(false) lets the panel move the text left. The model frame
-- is never hidden before its load had its chance: a hidden PlayerModel does not keep the model it loads.
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

-- Loads `item`'s speaker. `wanted`: the head setting. `onShown(shown)` runs when it is known whether a head shows.
function Head.load(h, item, wanted, onShown)
  local who = item and item.speaker
  if h.settleTimer then h.settleTimer:Cancel(); h.settleTimer = nil end
  if not wanted or not who or not who.creature then
    h.loaded = nil
    Head.setShown(h, false)
    onShown(false)
    return
  end
  local unit = who.unit
  local guid = Compat.resolve("UnitGUID")
  if unit and (type(guid) ~= "function" or guid(unit) ~= who.guid) then unit = nil end
  local want = unit and who.guid or who.creature
  if h.loaded == want and hasModel(h.model) then
    Head.setShown(h, true)
    onShown(true)
    return
  end
  h.loaded = want
  Head.setShown(h, true)
  onShown(true)
  if unit then
    h.model:SetUnit(unit)
  else
    h.model:ClearModel()
    h.model:SetCreature(who.creature)
  end
  local timer = Compat.resolve("C_Timer")
  if type(timer) == "table" and type(timer.NewTimer) == "function" then
    h.settleTimer = timer.NewTimer(MODEL_SETTLE, function()
      h.settleTimer = nil
      local shown = hasModel(h.model)
      Head.setShown(h, shown)
      onShown(shown)
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
