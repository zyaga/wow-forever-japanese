-- UI/CombatText.lua: the floating combat text's fixed words on Forever (surface "combattext", area "ui",
-- ADR-016). Blizzard_CombatText is load-on-demand (CombatText_LoadUI, blizzard_combattext_bootstrap.lua:3–5; camelot
-- loads the mainline overrides, blizzard_combattext.toc). The frame is CombatText (shared/combattext.xml:3).
-- Writer: CombatTextMixin:OnEvent builds `message` and ends with self:AddMessage(message, …) (shared/combattext.lua:
-- 31–294); AddMessage acquires a pooled FontString, fontString:SetText(message), positions it and appends it to
-- self.activeFontStrings (lua:335–430). AddMessage is the frame's own method, called as self:AddMessage, so it is
-- post-hooked on the frame. The hook gets `message` itself as an argument, which settles what may be read:
--   a whole-message word (COMBAT_TEXT_MISS / _DODGE / _PARRY / _EVADE / _IMMUNE / _DEFLECT / _REFLECT / _MISFIRE
--     (lua:219–234), COMBAT_TEXT_BLOCK / _ABSORB / _RESIST when nothing was partly blocked (lua:235–255), and the
--     fall-through `_G["COMBAT_TEXT_"..messageType] or _G[messageType]` (lua:283–286): ENTERING_COMBAT,
--     LEAVING_COMBAT, HEALTH_LOW, MANA_LOW, INTERRUPT, EXTRA_ATTACKS) is shown in Japanese;
--   a template with numbers only (COMBAT_TEXT_HONOR_GAINED ("Honor %s", a signed number, lua:256–266) and
--     COMBAT_TEXT_COMBO_POINTS ("<%d Combo |4Point:Points;>", lua:270–271)) is shown in Japanese, numbers kept;
--   everything else is a number ("-152", "+40"), a NAME ("<Spell Name>", "[Healer]", a faction), or a
--     number joined to a fragment ("-5 (3 blocked)", "+40 Mana", lua:140–213): left as the client wrote it. Those
--     strings are never matched: the hook returns before any lookup when `message` is not a string, is a secret
--     value (`issecretvalue`, blizzard_sharedxmlbase/securetypes.lua:6; damage and healing amounts can be secret on
--     this client), or starts with "-", "+", "[" or "(".
-- A number joined to a trailer, such as "+40 (12 absorbed)" (ABSORB_TRAILER after a heal, lua:162–182), "-152
--   (40 blocked)" (BLOCK_TRAILER, lua:237) and "-152 (40 resisted)" (RESIST_TRAILER, lua:251), keeps the number as
--   written and shows the trailer in Japanese (the `affix` form: the text before the trailer copied, the trailer's own
--   number filled). A heal with a healer's name ("+40 [Healer] (12 absorbed)") is never read (the name). The block line
--   on this client is COMBAT_TEXT_BLOCK_REDUCED "%s (Block)" (CombatTextUtil.GetFormattedBlockMessage,
--   shared/combattextutil.lua:38–42), a whole message.
-- Two more shapes (ADR-038):
--   energize  "<3 Combo |4Point:Points;>" = "<" .. N .. " " .. _G[power] .. ">" (lua:184–211): N kept, the power word
--             COMBO_POINTS in Japanese (the only listed one; any other power word leaves the message as written);
--   AURA_END  "<%s> fades" (lua:153–154): the aura's name kept (`text`), through WORDS.
-- The FontString AddMessage used is the entry it just appended to activeFontStrings (lua:429); the hook takes that
-- entry only when its text is `message`, and keys the record by the widget (the pool reuses FontStrings). A reused
-- FontString whose new text is not a dictionary word has its record dropped at once, so a modifier press can never
-- put an old word back over a number.
-- The message is positioned before the hook runs and never measured (SetPoint "TOP" at a computed x / y, lua:424–
-- 427), so a Japanese word of another width needs no refit. Its font is re-set on every acquire
-- (InitializeFontString → SetFontObject(CombatTextFont), lua:454–458), before our write.
local _, WFJ = ...
local CombatText = {}
WFJ.CombatText = CombatText

local SURFACE = "combattext"
CombatText.SURFACE = SURFACE
local ADDON = "Blizzard_CombatText"
local Compat = WFJ.Compat

CombatText.NEVER_TOUCH = {} -- the FontStrings are pooled and unnamed; names are kept out by WORDS and the prefix test

-- The only keys a message may be (a set: the hook runs for every combat text message).
CombatText.WORDS = { only = {
  COMBAT_TEXT_MISS = true, COMBAT_TEXT_DODGE = true, COMBAT_TEXT_PARRY = true, COMBAT_TEXT_EVADE = true,
  COMBAT_TEXT_IMMUNE = true, COMBAT_TEXT_DEFLECT = true, COMBAT_TEXT_REFLECT = true, COMBAT_TEXT_MISFIRE = true,
  COMBAT_TEXT_BLOCK = true, COMBAT_TEXT_ABSORB = true, COMBAT_TEXT_RESIST = true,
  ENTERING_COMBAT = true, LEAVING_COMBAT = true, HEALTH_LOW = true, MANA_LOW = true, INTERRUPT = true,
  EXTRA_ATTACKS = true, COMBAT_TEXT_HONOR_GAINED = true, COMBAT_TEXT_COMBO_POINTS = true, AURA_END = true,
  COMBAT_TEXT_BLOCK_REDUCED = true, -- a number and its trailer
} }
CombatText.TRAILERS = { only = { ABSORB_TRAILER = true, BLOCK_TRAILER = true, RESIST_TRAILER = true } }
local POWERS = { "COMBO_POINTS" }

local SKIP = { ["-"] = true, ["+"] = true, ["["] = true, ["("] = true }

local function get(key) return Compat.get(SURFACE, key) end

local fsKey = WFJ.Labels.keyer("msg.")

-- → true when `message` is not ours to read at all: not a string, or a secret value.
local function secret(message)
  local isSecret = get("isSecret")
  if type(isSecret) == "function" and isSecret(message) == true then return true end
  return type(message) ~= "string" or message == ""
end

-- "+40  (12 absorbed)" → the number and its space, and the trailer (whose English starts with its own space,
-- " (%d absorbed)"). → prefix, trailer | nil
local function trailer(message)
  return message:match("^([%+%-][%d,%.]+ )( %(.+%))$")
end

-- The energize form. → key, `seq` args | nil
function CombatText.composite(message)
  local n, word = message:match("^<(%d+) (.+)>$")
  -- the whole-message COMBAT_TEXT_COMBO_POINTS (lua:270–271) keeps its own template
  if n and WFJ.Labels.part(message, { "COMBAT_TEXT_COMBO_POINTS" }) then return nil end
  local part = n and WFJ.Labels.part(word, POWERS)
  if part then return part.key, { form = "seq", parts = { "<" .. n .. " ", part, ">" } } end
  return nil
end

-- hooksecurefunc target (CombatText:AddMessage). → 1 when the message is a dictionary word, else 0.
function CombatText.onAddMessage(frame, message)
  local active = type(frame) == "table" and frame.activeFontStrings or nil
  local fs = type(active) == "table" and active[#active] or nil
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" then return 0 end
  local recKey = fsKey(fs)
  local prefix, tail
  if not secret(message) then prefix, tail = trailer(message) end
  if prefix and fs:GetText() == message and WFJ.UIIndex then
    local key, args = WFJ.UIIndex:matchOnly(tail, CombatText.TRAILERS.only)
    if key then
      WFJ.Render.show(SURFACE, recKey, fs, message, "ui", "ui", key,
        { args = { form = "affix", before = prefix, after = "", inner = args } })
      return 1
    end
  end
  if secret(message) then
    WFJ.SurfaceState.drop(SURFACE, recKey) -- a reused FontString: forget the word it held
    return 0
  end
  if fs:GetText() ~= message then return 0 end -- not the FontString this call wrote
  local key, args = CombatText.composite(message)
  if key then return WFJ.Labels.showArgs(SURFACE, recKey, fs, key, args) end
  if SKIP[message:sub(1, 1)] then
    WFJ.SurfaceState.drop(SURFACE, recKey) -- a number / name form
    return 0
  end
  return WFJ.Labels.show(SURFACE, recKey, fs, nil, CombatText.WORDS)
end

local hooked = false

-- Runs once Blizzard_CombatText is present. → true when the hook went in.
function CombatText.setup()
  local frame = get("frame")
  if hooked or type(frame) ~= "table" or type(frame.AddMessage) ~= "function"
      or type(frame.activeFontStrings) ~= "table" then
    return false
  end
  hooked = true
  hooksecurefunc(frame, "AddMessage", CombatText.onAddMessage)
  return true
end

-- Called by Main after Compat.init and LoadOnDemand.init. → true when hooked now, false when waiting for the addon
-- or when the client has no CombatText_LoadUI at all (then nothing waits either).
function CombatText.init()
  Compat.declare(SURFACE, "frame", { "CombatText" })
  Compat.declare(SURFACE, "loader", { "CombatText_LoadUI" })
  Compat.declare(SURFACE, "isSecret", { "issecretvalue" })
  if hooked then return false end
  if type(get("loader")) ~= "function" and type(get("frame")) ~= "table" then return false end
  local ran = WFJ.LoadOnDemand.when(ADDON, function()
    Compat.declare(SURFACE, "frame", { "CombatText" }) -- re-resolve: the frame did not exist before the load
    CombatText.setup()
  end)
  return ran and hooked
end
