-- UI/Petition.lua: the guild charter (petition) window on Forever (surface "petition", area "ui", ADR-016 /
-- ADR-029). camelot loads blizzard_uipanels_game/mainline/petitionframe.lua|xml; the frame shows itself on
-- PETITION_SHOW and then calls PetitionFrame_Update(self) by name (petitionframe.xml:186–198).
-- - Static (XML text, shown on OnShow): PetitionFrameMemberTitle MEMBERS (xml:46), PetitionFrameCancelButton CLOSE
--   (:139), PetitionFrameSignButton SIGN_CHARTER (:148), PetitionFrameRequestButton REQUEST_SIGNATURE (:157),
--   PetitionFrameRenameButton RENAME_GUILD (:166; rewritten with the same word at petitionframe.lua:34).
-- - Writer PetitionFrame_Update (petitionframe.lua:2–63), post-hooked by name:
--     PetitionFrameInstructions   GUILD_PETITION_LEADER_INSTRUCTIONS / GUILD_PETITION_MEMBER_INSTRUCTIONS (:13, :22)
--     PetitionFrameCharterTitle   GUILD_NAME (:30)
--     PetitionFrameNpcNameText    GUILD_CHARTER_TEMPLATE "%s Guild Charter": %s is the guild's name, kept as written
--                                 (:29; a `text` argument in Core/UIStrings.ARGS)
--     PetitionFrameMemberName1–9  NOT_YET_SIGNED for an empty line, else a signer's name (:46–52): restricted to
--                                 that one key, so a name is never matched.
-- Never touched: PetitionFrameCharterName (the guild's name, :31), PetitionFrameMasterName (the founder, :33) and
-- PetitionFrameMasterTitle (GUILD_RANK0_DESC "Guild Master": a guild rank name stays English).
-- The arena-team branch (:15, :24) needs an arena registrar, which Vanilla content does not have, so its two strings
-- are left out.
-- Release on PetitionFrame's OnHide.
local _, WFJ = ...
local Petition = {}
WFJ.Petition = Petition

local SURFACE = "petition"
Petition.SURFACE = SURFACE
local Compat = WFJ.Compat

local MAX_MEMBERS = 9 -- PetitionFrameMemberName1–9 (petitionframe.xml:52–100)

Petition.NEVER_TOUCH = { "PetitionFrameCharterName", "PetitionFrameMasterName", "PetitionFrameMasterTitle" }

local CANDIDATES = {
  frame = { "PetitionFrame" }, memberTitle = { "PetitionFrameMemberTitle" }, close = { "PetitionFrameCancelButton" },
  sign = { "PetitionFrameSignButton" }, request = { "PetitionFrameRequestButton" },
  rename = { "PetitionFrameRenameButton" }, instructions = { "PetitionFrameInstructions" },
  charterTitle = { "PetitionFrameCharterTitle" }, npcName = { "PetitionFrameNpcNameText" },
}
for i = 1, MAX_MEMBERS do CANDIDATES["member" .. i] = { "PetitionFrameMemberName" .. i } end

local INSTRUCTIONS = { only = { "GUILD_PETITION_LEADER_INSTRUCTIONS", "GUILD_PETITION_MEMBER_INSTRUCTIONS" } }
local UNSIGNED = { only = { "NOT_YET_SIGNED" } }

local function get(key) return Compat.get(SURFACE, key) end

-- hooksecurefunc target (PetitionFrame_Update), also run on OnShow. → the number of dictionary words found.
function Petition.onUpdate()
  local list = {
    { "memberTitle", get("memberTitle"), { only = { "MEMBERS" } } },
    { "close", get("close"), { only = { "CLOSE" } } },
    { "sign", get("sign"), { only = { "SIGN_CHARTER" } } },
    { "request", get("request"), { only = { "REQUEST_SIGNATURE" } } },
    { "rename", get("rename"), { only = { "RENAME_GUILD" } } },
    { "instructions", get("instructions"), INSTRUCTIONS },
    { "charterTitle", get("charterTitle"), { only = { "GUILD_NAME" } } },
    { "npcName", get("npcName"), { only = { "GUILD_CHARTER_TEMPLATE" } } },
  }
  for i = 1, MAX_MEMBERS do list[#list + 1] = { "member" .. i, get("member" .. i), UNSIGNED } end
  return WFJ.Labels.showAll(SURFACE, list)
end

function Petition.release()
  return WFJ.Render.release(SURFACE)
end

local hooked = false

-- Called by Main after Compat.init, HelpTooltip.init and ButtonText.init.
function Petition.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  Compat.declare(SURFACE, "update", { "PetitionFrame_Update" })
  local frame = get("frame")
  if hooked or type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  hooked = true
  frame:HookScript("OnShow", Petition.onUpdate)
  frame:HookScript("OnHide", Petition.release)
  if type(get("update")) == "function" then hooksecurefunc("PetitionFrame_Update", Petition.onUpdate) end
  return true
end
