-- Party pose screens: UI/PartyPose.lua over the three PartyPoseFrameTemplate windows replayed from
-- camelot blizzard_partyposeui.lua:345–370 and each addon's SetLeaveButtonText. A table-driven title and a reward's
-- name stay English; both load orders.
local S = require("tests.lua.spec.stub_camelot_social")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = S.files("UI/PartyPose.lua")

local UI = {
  PARTY_POSE_VICTORY = { "VICTORY!", "勝利!" }, PARTY_POSE_DEFEAT = { "DEFEAT", "敗北" },
  INSTANCE_LEAVE = { "Leave Instance", "インスタンスを出る" }, ISLAND_LEAVE = { "Leave Island", "島を出る" },
  YOU_EARNED_LABEL = { "You Earned", "獲得" }, CLOSE = { "Close", "閉じる" },
}

local WINDOWS = { Blizzard_MatchCelebrationPartyPoseUI = { "MatchCelebrationPartyPoseFrame", "INSTANCE_LEAVE", true },
  Blizzard_IslandsPartyPoseUI = { "IslandsPartyPoseFrame", "ISLAND_LEAVE" } }

local function load(addon)
  local name, leaveKey, container = unpack(WINDOWS[addon])
  local frame = S.frame(name)
  frame.TitleText = S.fs("")
  S.put(frame, "RewardAnimations.RewardFrame.Label", S.fs(S.en("YOU_EARNED_LABEL")))
  frame.RewardAnimations.RewardFrame.Name = S.fs("Close")
  local holder = frame
  if container then
    frame.ButtonContainer = S.frame()
    holder = frame.ButtonContainer
    holder.ExtraButton = S.button(nil, "")
  end
  holder.LeaveButton = S.button(nil, "")
  function frame.LoadPartyPose(self, data)
    self.TitleText.text = data.title or S.en(data.won and "PARTY_POSE_VICTORY" or "PARTY_POSE_DEFEAT")
    S.write(holder.LeaveButton, S.en(leaveKey))
    if holder.ExtraButton then S.write(holder.ExtraButton, data.extra or S.en("CLOSE")) end
  end
  Stub.loadedAddons[addon] = true
  return frame
end

describe("the party pose screens on Forever", function()
  local WFJ
  before_each(function() WFJ = S.load(FILES, UI) end)
  after_each(function() S.teardown({ "MatchCelebrationPartyPoseFrame", "IslandsPartyPoseFrame" }) end)

  local function check()
    local match, island = _G.MatchCelebrationPartyPoseFrame, _G.IslandsPartyPoseFrame
    match:LoadPartyPose({ won = true })
    assert.are.equal("勝利!", match.TitleText:GetText())
    assert.are.equal("インスタンスを出る", match.ButtonContainer.LeaveButton:GetText())
    assert.are.equal("閉じる", match.ButtonContainer.ExtraButton:GetText())
    assert.are.equal("獲得", match.RewardAnimations.RewardFrame.Label:GetText())
    match:LoadPartyPose({ title = "Close", extra = "Queue Again" }) -- client-table text: never matched
    assert.are.equal("Close", match.TitleText:GetText())
    assert.are.equal("Queue Again", match.ButtonContainer.ExtraButton:GetText())
    assert.are.equal("Close", match.RewardAnimations.RewardFrame.Name:GetText())
    assert.is_true(S.unrecorded(WFJ, match.RewardAnimations.RewardFrame.Name))
    island:LoadPartyPose({ won = false })
    assert.are.equal("敗北", island.TitleText:GetText())
    assert.are.equal("島を出る", island.LeaveButton:GetText())
    S.alt(WFJ, true)
    assert.are.equal("DEFEAT", island.TitleText:GetText())
    S.alt(WFJ, false)
  end

  it("addons loaded before the surface starts", function()
    for addon in pairs(WINDOWS) do load(addon) end
    assert.is_true(WFJ.PartyPose.init())
    check()
  end)

  it("addons loaded on demand; hooks install once", function()
    assert.is_false(WFJ.PartyPose.init()) -- nothing loaded: nothing touched
    for addon in pairs(WINDOWS) do
      load(addon)
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(addon))
    end
    check()
    WFJ.PartyPose.setup("Blizzard_IslandsPartyPoseUI")
    assert.are.equal(1, #Stub.hooks["IslandsPartyPoseFrame:LoadPartyPose"])
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    local frame = load("Blizzard_IslandsPartyPoseUI")
    frame.LoadPartyPose, frame.LeaveButton, frame.RewardAnimations = true, 5, "?"
    frame.TitleText.text = "VICTORY!"
    Stub.loadedAddons.Blizzard_MatchCelebrationPartyPoseUI = true
    _G.MatchCelebrationPartyPoseFrame = "?"
    assert.has_no.errors(function() WFJ.PartyPose.init() end)
    assert.are.equal("勝利!", frame.TitleText:GetText())
  end)
end)
