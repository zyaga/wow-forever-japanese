-- UI/GuildInvite.lua over a GuildInviteFrame replayed from camelot
-- blizzard_framexml/guildinviteframe.xml (:34–125) and .lua (:1–38). The inviter's and the guild's names stay English.
local Stub = require("tests.lua.spec.wow_stub")
local R = require("tests.lua.spec.stub_retail")

local UI = {
  GUILD_INVITATION = { "invites you to join the guild:", "がギルドに招待しています:" },
  ACHIEVEMENTS = { "Achievements", "アチーブメント" },
  GUILD_INVITE_JOIN = { "Join Guild", "ギルドに参加" }, GUILD_INVITE_DECLINE = { "Decline Invitation", "招待を断る" },
  GUILD_REPUTATION_WARNING_GENERIC = { "You will lose one rank of guild reputation with your previous guild.",
    "以前のギルドでのギルド評判が1段階下がります。" },
  GUILD_REPUTATION_WARNING = { "You will lose one rank of guild reputation with %s", "%sでのギルド評判が1段階下がります" },
}
local GLOBALS = { "GuildInviteFrame", "GuildInviteFrameInviterName", "GuildInviteFrameInviteText",
  "GuildInviteFrameGuildName", "GuildInviteFrameWarningText", "GuildInviteFrameJoinButton",
  "GuildInviteFrameDeclineButton" }

local function build()
  local frame = CreateFrame("Frame", "GuildInviteFrame")
  R.tree(frame, { ["Points.Title"] = _G.ACHIEVEMENTS, ["Points.Text"] = "25" })
  Stub.namedFontString("GuildInviteFrameInviterName", "")
  Stub.namedFontString("GuildInviteFrameInviteText", _G.GUILD_INVITATION)
  Stub.namedFontString("GuildInviteFrameGuildName", "")
  Stub.namedFontString("GuildInviteFrameWarningText", "")
  _G.GuildInviteFrameJoinButton = Stub.button(nil, _G.GUILD_INVITE_JOIN)
  _G.GuildInviteFrameDeclineButton = Stub.button(nil, _G.GUILD_INVITE_DECLINE)
  -- GuildInviteFrame_OnEvent (lua:8–30) then StaticPopupSpecial_Show
  function frame.invite(self, inviter, guild, warning)
    _G.GuildInviteFrameInviterName.text = inviter
    _G.GuildInviteFrameGuildName.text = guild
    _G.GuildInviteFrameWarningText.text = warning or ""
    self:Show()
  end
  return frame
end

R.suite(getfenv(1), {
  title = "the guild invitation window on Forever", module = "GuildInvite", file = "UI/GuildInvite.lua",
  root = "GuildInviteFrame", globals = GLOBALS, ui = UI, build = build,
  args = { GUILD_REPUTATION_WARNING = { [1] = "text" } },
  cases = {
    { "the labels and buttons are Japanese on an invite; Alt shows English", function(frame, WFJ)
      frame:invite("Thrall", "Horde Guild", _G.GUILD_REPUTATION_WARNING_GENERIC)
      assert.are.equal("がギルドに招待しています:", _G.GuildInviteFrameInviteText:GetText())
      assert.are.equal("アチーブメント", frame.Points.Title:GetText())
      assert.are.equal("ギルドに参加", _G.GuildInviteFrameJoinButton:GetText())
      assert.are.equal("招待を断る", _G.GuildInviteFrameDeclineButton:GetText())
      assert.are.equal("以前のギルドでのギルド評判が1段階下がります。", _G.GuildInviteFrameWarningText:GetText())
      R.alt(WFJ, true)
      assert.are.equal("Join Guild", _G.GuildInviteFrameJoinButton:GetText())
      R.alt(WFJ, false)
    end },
    { "the named warning keeps the old guild's name in English inside the Japanese", function(frame)
      frame:invite("Thrall", "Horde Guild", string.format(_G.GUILD_REPUTATION_WARNING, "Old Friends"))
      assert.are.equal("Old Friendsでのギルド評判が1段階下がります", _G.GuildInviteFrameWarningText:GetText())
      frame:invite("Thrall", "Horde Guild", "")
      assert.are.equal("", _G.GuildInviteFrameWarningText:GetText())
    end },
  },
  name = function(frame, WFJ)
    frame:invite("Achievements", "Join Guild") -- names spelled like dictionary words
    assert.are.equal("Achievements", _G.GuildInviteFrameInviterName:GetText())
    assert.are.equal("Join Guild", _G.GuildInviteFrameGuildName:GetText())
    assert.is_true(R.unrecorded(WFJ, _G.GuildInviteFrameInviterName))
    assert.is_true(R.unrecorded(WFJ, _G.GuildInviteFrameGuildName))
  end,
  wrong = function(frame)
    _G.GuildInviteFrameInviteText = "x"
    frame.Points = 7
    return function(_, WFJ)
      assert.are.equal("ギルドに参加", _G.GuildInviteFrameJoinButton:GetText())
      assert.is_true(R.unrecorded(WFJ, _G.GuildInviteFrameWarningText))
    end
  end,
})
