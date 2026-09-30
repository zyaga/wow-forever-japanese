-- UI/InstanceAbandon.lua: the vote-to-abandon status panel on Forever (surface "instanceabandon", area "ui",
-- ADR-016). Blizzard_FrameXML loads mainline/instanceabandon.xml|lua at login on `camelot`; InstanceAbandonFrame
-- registers INSTANCE_ABANDON_VOTE_STARTED / _UPDATED / _FINISHED itself (instanceabandon.lua:63–72) and is shown
-- inside the vote StaticPopup (CheckShowVoteDialog, :190–206). The popups' own text is StaticPopup text (ADR-015 §5,
-- not here); the panel inserted into them is a real frame with two labels:
--   VoteText: InstanceAbandonMixin:OnShow writes VOTE_TO_ABANDON_VOTES_NEEDED "%d votes needed …" or, for the
--     keystone holder, VOTE_TO_ABANDON_VOTES_NEEDED_KEYHOLDER (:74–84); an OnShow pass (HookScript, after the
--     frame's own script) sees it;
--   ResponseText: InstanceAbandonMixin:Refresh writes VOTE_TO_ABANDON_VOTED_YES / _NO (:139–146), called as
--     self:Refresh (:120, :83), post-hooked on the instance.
-- Whether Forever's dungeons offer the vote is an in-game check.
local _, WFJ = ...
local InstanceAbandon = {}
WFJ.InstanceAbandon = InstanceAbandon

local SURFACE = "instanceabandon"
InstanceAbandon.SURFACE = SURFACE
local Compat = WFJ.Compat

InstanceAbandon.NEVER_TOUCH = {}

local CANDIDATES = { frame = { "InstanceAbandonFrame" }, vote = { "InstanceAbandonFrame.VoteText" },
  response = { "InstanceAbandonFrame.ResponseText" } }
local VOTE = { only = { "VOTE_TO_ABANDON_VOTES_NEEDED", "VOTE_TO_ABANDON_VOTES_NEEDED_KEYHOLDER" } }
local RESPONSE = { only = { "VOTE_TO_ABANDON_VOTED_YES", "VOTE_TO_ABANDON_VOTED_NO" } }

local function get(key) return Compat.get(SURFACE, key) end

-- The panel's two labels. → the number of dictionary words found.
function InstanceAbandon.show()
  return WFJ.Labels.showAll(SURFACE, { { "vote", get("vote"), VOTE }, { "response", get("response"), RESPONSE } })
end

local hooked = false

-- Called by Main after Compat.init. → true when the panel was hooked now; false on a second call.
function InstanceAbandon.init()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
  if hooked then return false end
  local frame = get("frame")
  if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return false end
  hooked = true
  frame:HookScript("OnShow", InstanceAbandon.show)
  if type(frame.Refresh) == "function" then hooksecurefunc(frame, "Refresh", InstanceAbandon.show) end
  InstanceAbandon.show()
  return true
end
