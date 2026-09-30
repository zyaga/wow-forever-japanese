-- Guild charter on Forever: UI/Petition.lua over a PetitionFrame replayed from camelot
-- blizzard_uipanels_game/mainline/petitionframe.lua (PetitionFrame_Update :2–63) and petitionframe.xml.
local Stub = require("tests.lua.spec.wow_stub")
local G = require("tests.lua.spec.stub_gamepanels")

local FILES = G.files("UI/Petition.lua")
local UI = {
  MEMBERS = { "Members", "メンバー" }, CLOSE = { "Close", "閉じる" }, SIGN_CHARTER = { "Sign Charter", "設立許可証に署名" },
  REQUEST_SIGNATURE = { "Request Signature", "署名を依頼" }, RENAME_GUILD = { "Rename guild", "ギルド名を変更" },
  GUILD_NAME = { "Guild Name", "ギルド名" }, NOT_YET_SIGNED = { "<not yet signed>", "<未署名>" },
  GUILD_CHARTER_TEMPLATE = { "%s Guild Charter", "%s ギルド設立許可証" },
  GUILD_PETITION_LEADER_INSTRUCTIONS = { "Select a player you wish to invite and click <request signature>.",
    "招待したいプレイヤーを選択して<署名を依頼>をクリックしてください。" },
  GUILD_PETITION_MEMBER_INSTRUCTIONS = { "Click the <Sign Charter> button to become a charter member of this guild.",
    "<設立許可証に署名>ボタンをクリックすると、このギルドの設立メンバーになります。" },
  GUILD_RANK0_DESC = { "Guild Master", "ギルドマスター" }, -- a rank name: in the dictionary, never shown here
}
local FONTSTRINGS = { "PetitionFrameCharterTitle", "PetitionFrameCharterName", "PetitionFrameMasterTitle",
  "PetitionFrameMasterName", "PetitionFrameMemberTitle", "PetitionFrameInstructions", "PetitionFrameNpcNameText" }
local NAMES = { "PetitionFrame", "PetitionFrame_Update", "PetitionFrameCancelButton", "PetitionFrameSignButton",
  "PetitionFrameRequestButton", "PetitionFrameRenameButton" }

local P = {}

local function patch(WFJ) -- the Core/UIStrings entry this surface needs
  WFJ.UIStrings.ARGS.GUILD_CHARTER_TEMPLATE = { [1] = "text" }
end

local function install()
  local frame = G.titled("PetitionFrame")
  for _, name in ipairs(FONTSTRINGS) do Stub.namedFontString(name, ""); NAMES[#NAMES + 1] = name end
  _G.PetitionFrameMemberTitle.text = _G.MEMBERS
  for i = 1, 9 do
    Stub.namedFontString("PetitionFrameMemberName" .. i, "")
    NAMES[#NAMES + 1] = "PetitionFrameMemberName" .. i
  end
  Stub.button("PetitionFrameCancelButton", _G.CLOSE)
  Stub.button("PetitionFrameSignButton", _G.SIGN_CHARTER)
  Stub.button("PetitionFrameRequestButton", _G.REQUEST_SIGNATURE)
  Stub.button("PetitionFrameRenameButton", _G.RENAME_GUILD)
  _G.PetitionFrame_Update = function()
    _G.PetitionFrameInstructions.text = P.originator and _G.GUILD_PETITION_LEADER_INSTRUCTIONS
      or _G.GUILD_PETITION_MEMBER_INSTRUCTIONS
    _G.PetitionFrameNpcNameText.text = _G.GUILD_CHARTER_TEMPLATE:format(P.guild)
    _G.PetitionFrameCharterTitle.text = _G.GUILD_NAME
    _G.PetitionFrameCharterName.text = P.guild
    _G.PetitionFrameMasterTitle.text = _G.GUILD_RANK0_DESC
    _G.PetitionFrameMasterName.text = "Thrall"
    _G.PetitionFrameRenameButton:SetText(_G.RENAME_GUILD)
    for i = 1, 9 do
      _G["PetitionFrameMemberName" .. i].text = P.signers[i] or _G.NOT_YET_SIGNED
    end
  end
  return frame
end

describe("the guild charter window on Forever", function()
  local WFJ

  before_each(function()
    WFJ = G.load(FILES, UI, patch)
    P.originator, P.guild, P.signers = true, "Members", { "Jaina", "Close" } -- a guild and a signer named like words
  end)
  after_each(function() G.clear(NAMES) end)

  it("labels, instructions and unsigned lines translate; guild, founder, signers and the rank name stay English",
    function()
      local frame = install()
      WFJ.Labels.forbidNames(WFJ.Petition.NEVER_TOUCH)
      assert.is_true(WFJ.Petition.init())
      frame:Show()
      _G.PetitionFrame_Update(frame)
      assert.are.equal("メンバー", _G.PetitionFrameMemberTitle:GetText())
      assert.are.equal("閉じる", _G.PetitionFrameCancelButton:GetText())
      assert.are.equal("署名を依頼", _G.PetitionFrameRequestButton:GetText())
      assert.are.equal("ギルド名を変更", _G.PetitionFrameRenameButton:GetText())
      assert.are.equal(UI.GUILD_PETITION_LEADER_INSTRUCTIONS[2], _G.PetitionFrameInstructions:GetText())
      assert.are.equal("ギルド名", _G.PetitionFrameCharterTitle:GetText())
      assert.are.equal("Members ギルド設立許可証", _G.PetitionFrameNpcNameText:GetText())
      assert.are.equal("Members", _G.PetitionFrameCharterName:GetText())
      assert.are.equal("Guild Master", _G.PetitionFrameMasterTitle:GetText())
      assert.are.equal("Thrall", _G.PetitionFrameMasterName:GetText())
      assert.are.equal("Jaina", _G.PetitionFrameMemberName1:GetText())
      assert.are.equal("Close", _G.PetitionFrameMemberName2:GetText()) -- a signer called "Close"
      assert.is_true(G.unrecorded(WFJ, _G.PetitionFrameMemberName2))
      assert.are.equal("<未署名>", _G.PetitionFrameMemberName3:GetText())
      P.signers[3] = "Sylvanas" -- a signature arrives: the line follows the client's new text
      _G.PetitionFrame_Update(frame)
      assert.are.equal("Sylvanas", _G.PetitionFrameMemberName3:GetText())
      G.alt(WFJ, true)
      assert.are.equal("<not yet signed>", _G.PetitionFrameMemberName4:GetText())
      assert.are.equal("Members Guild Charter", _G.PetitionFrameNpcNameText:GetText())
    end)

  it("wrong-typed names degrade without error; hooks install once", function()
    local frame = install()
    _G.PetitionFrameInstructions = 1
    _G.PetitionFrameMemberName5 = "x"
    assert.has_no.errors(function() assert.is_true(WFJ.Petition.init()) end)
    _G.PetitionFrameInstructions = Stub.fontString("") -- the client's writer still needs its widget
    _G.PetitionFrameMemberName5 = Stub.fontString("")
    assert.has_no.errors(function() frame:Show(); _G.PetitionFrame_Update(frame) end)
    assert.are.equal("メンバー", _G.PetitionFrameMemberTitle:GetText())
    assert.is_false(WFJ.Petition.init())
    assert.are.equal(1, #Stub.hooks["PetitionFrame_Update"])
  end)

  it("no PetitionFrame: init is false and nothing is touched", function()
    assert.has_no.errors(function() assert.is_false(WFJ.Petition.init()) end)
  end)
end)
