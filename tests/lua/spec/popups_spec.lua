-- UI/Popups.lua over StaticPopup1–4, as Forever's StaticPopup_Show (staticpopup.lua:309–433) sets them up:
-- dialog:Init writes Text with SetFormattedText(dialogInfo.text, text_arg1, text_arg2) and keeps the arguments on the
-- FontString (gamedialog.lua:120–128), and each button's SetText(dialogInfo.buttonN) (:302–320). The death dialog's
-- countdown is GameDialogDefsUtil.GetDefaultExpirationText (gamedialogdefsutil.lua:53–61), written each frame from
-- StaticPopup_OnUpdate (staticpopup.lua:490–500).
local Stub = require("tests.lua.spec.wow_stub")
local X = require("tests.lua.spec.stub_framexml_hud")

local UI = {
  DELETE_ITEM = { "Do you want to destroy %s?", "%sを破棄しますか？" },
  CONFIRM_BINDER = { "Do you want to make %s your new home?", "%sを新しいホームにしますか？" },
  CONFIRM_RESET_INSTANCES = { "Do you really want to reset all of your instances?",
    "すべてのインスタンスをリセットしますか？" },
  DEATH_RELEASE_TIMER = { "%d %s until release", "解放まで%d%s" },
  SECONDS = { "|4Second:Seconds;", "秒" }, MINUTES = { "|4Minute:Minutes;", "分" },
  YES = { "Yes", "はい" }, NO = { "No", "いいえ" }, DEATH_RELEASE = { "Release Spirit", "霊体になる" },
  -- The age-verification dialogs (blizzard_staticpopup_game/gamedialogdefs.lua:3304–3318)
  SOCIAL_FEATURES_UNAVAILABLE = { "Social Features Unavailable", "ソーシャル機能は利用できません" },
  SOCIAL_FEATURES_UNAVAILABLE_DESCRIPTION = { "World of Warcraft includes social features that allow players to "
    .. "communicate and interact with one another.|n|nThis account belongs to a minor.",
    "World of Warcraftには、プレイヤー同士が交流し、やり取りできるソーシャル機能があります。|n|nこのアカウントは未成年者のものです。" },
  OKAY = { "Okay", "OK" },
  -- the party invite (gamedialogdefs.lua:1303-1328, eventimplementation.lua:61-72)
  INVITATION = { "%s invites you to a group.", "%sがあなたをグループに招待しています。" },
  ACCEPTING_INVITE_WILL_REMOVE_QUEUE = { "Accepting this invite will remove you from all queues.",
    "このグループに参加すると、現在のキューからすべて外れます。" },
  ACCEPT = { "Accept", "承諾" }, DECLINE = { "Decline", "辞退" },
  CONFIRM_LEAVE_INSTANCE_PARTY = { "Are you sure you want to leave the instance group?",
    "インスタンスグループから離れますか？" },
}
local NAMES = { "StaticPopup_Show", "StaticPopup_OnUpdate", "StaticPopupDialogs", "GameDialogDefsUtil",
  "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4" }

local function dialog(i)
  local d = { Text = Stub.fontString(""), SubText = Stub.fontString(""), shown = false,
    ButtonContainer = { Buttons = { Stub.button(nil, ""), Stub.button(nil, "") } } }
  function d:IsShown() return self.shown end
  _G["StaticPopup" .. i] = d
  return d
end

local function install()
  local util = {}
  function util.GetDefaultExpirationText(d, _, timeleft)
    local fmt = d.dialogInfo.text
    if timeleft < 60 then return string.format(fmt, timeleft, _G.SECONDS) end
    return string.format(fmt, math.ceil(timeleft / 60), _G.MINUTES)
  end
  _G.GameDialogDefsUtil = util
  _G.StaticPopupDialogs = {}
  for i = 1, 4 do dialog(i) end
  _G.StaticPopup_Show = function(which, a1, a2, data)
    local info = _G.StaticPopupDialogs[which]
    local d = _G.StaticPopup1.shown and _G.StaticPopup2 or _G.StaticPopup1
    d.which, d.dialogInfo, d.data = which, info, data
    if info.text == "" then d.Text:SetText(a1) -- gamedialog.lua:121–122
    else
      local ok, text = pcall(string.format, info.text, a1, a2)
      d.Text:SetText(ok and text or " ") -- the countdown dialogs write their text on the first update
    end
    d.Text.text_arg1, d.Text.text_arg2 = a1, a2
    for n, b in ipairs(d.ButtonContainer.Buttons) do b:SetText(info["button" .. n] or "") end
    d.SubText:SetText(info.subText or "") -- gamedialog.lua's SubText from dialogInfo.subText
    d.shown = true
    if info.timeout then d.timeleft = info.timeout end
    return d
  end
  _G.StaticPopup_OnUpdate = function(d, elapsed)
    local info = d.dialogInfo
    if d.startDelay then -- staticpopup.lua:518–525: the start delay ends and the text is formatted again
      d.startDelay = nil
      d.Text:SetText(string.format(info.text, d.Text.text_arg1, d.Text.text_arg2))
      return
    end
    if d.timeleft and info.GetExpirationText then
      d.timeleft = d.timeleft - elapsed
      d.Text:SetText(info.GetExpirationText(d, nil, math.ceil(d.timeleft)))
    end
  end
end

describe("the StaticPopup dialogs on Forever", function()
  local WFJ
  before_each(function()
    WFJ = X.load("UI/Popups.lua", UI, { before = install })
    local D = _G.StaticPopupDialogs
    D.DELETE_ITEM = { text = _G.DELETE_ITEM, button1 = _G.YES, button2 = _G.NO }
    D.CONFIRM_BINDER = { text = _G.CONFIRM_BINDER, button1 = _G.YES, button2 = _G.NO }
    D.CONFIRM_RESET_INSTANCES = { text = _G.CONFIRM_RESET_INSTANCES, button1 = _G.YES, button2 = _G.NO }
    D.DEATH = { text = _G.DEATH_RELEASE_TIMER, button1 = _G.DEATH_RELEASE, timeout = 90,
      GetExpirationText = _G.GameDialogDefsUtil.GetDefaultExpirationText }
    D.SERVER = { text = "", button1 = _G.YES }
    D.GENERIC_CONFIRMATION = { text = "" } -- its OnShow writes the caller's text and buttons
    D.PARTY_INVITE = { text = "%s", button1 = _G.ACCEPT, button2 = _G.DECLINE }
    D.CONFIRM_LEAVE_INSTANCE_PARTY = { text = "%s", button1 = _G.YES, button2 = _G.NO }
    D.AGE_VERIFICATION_RESTRICTED_MINOR = { text = _G.SOCIAL_FEATURES_UNAVAILABLE,
      subText = _G.SOCIAL_FEATURES_UNAVAILABLE_DESCRIPTION, button1 = _G.OKAY }
    assert.is_true(WFJ.Popups.init())
  end)
  after_each(function() X.teardown(NAMES) end)

  it("a plain dialog and its buttons translate; Alt shows the live English", function()
    local d = _G.StaticPopup_Show("CONFIRM_RESET_INSTANCES")
    assert.are.equal("すべてのインスタンスをリセットしますか？", d.Text:GetText())
    assert.are.equal("はい", d.ButtonContainer.Buttons[1]:GetText())
    assert.are.equal("いいえ", d.ButtonContainer.Buttons[2]:GetText())
    X.alt(WFJ, true)
    assert.are.equal("Do you really want to reset all of your instances?", d.Text:GetText())
    assert.are.equal("Yes", d.ButtonContainer.Buttons[1]:GetText())
    X.alt(WFJ, false)
    assert.are.equal("すべてのインスタンスをリセットしますか？", d.Text:GetText())
  end)

  it("an age-verification dialog's text and subText translate from its definition; Alt shows English",
    function()
      local d = _G.StaticPopup_Show("AGE_VERIFICATION_RESTRICTED_MINOR")
      assert.are.equal("ソーシャル機能は利用できません", d.Text:GetText())
      assert.are.equal(UI.SOCIAL_FEATURES_UNAVAILABLE_DESCRIPTION[2], d.SubText:GetText())
      X.alt(WFJ, true)
      assert.are.equal("Social Features Unavailable", d.Text:GetText())
      assert.are.equal(UI.SOCIAL_FEATURES_UNAVAILABLE_DESCRIPTION[1], d.SubText:GetText())
      X.alt(WFJ, false)
    end)

  it("a name inside the dialog is copied as the English showed it, even a dictionary word", function()
    local d = _G.StaticPopup_Show("DELETE_ITEM", "|cffffffff[Linen Cloth]|r")
    assert.are.equal("|cffffffff[Linen Cloth]|rを破棄しますか？", d.Text:GetText())
    _G.StaticPopup1.shown = false
    local e = _G.StaticPopup_Show("CONFIRM_BINDER", "Yes") -- an inn named like a dictionary word
    assert.are.equal("Yesを新しいホームにしますか？", e.Text:GetText())
  end)

  it("a dialog whose text is not its definition's (computed, server text) stays as written", function()
    local d = _G.StaticPopup_Show("SERVER", "Something the server said.")
    assert.are.equal("Something the server said.", d.Text:GetText())
    assert.is_true(X.unrecorded(WFJ, d.Text))
    assert.are.equal("はい", d.ButtonContainer.Buttons[1]:GetText())
    _G.StaticPopup1.shown = false
    local e = _G.StaticPopup_Show("CONFIRM_RESET_INSTANCES")
    e.Text:SetText("Do you really want to reset all of your instances? (2 left)") -- rewritten by the client
    WFJ.Popups.onUpdate(e)
    assert.are.equal("Do you really want to reset all of your instances? (2 left)", e.Text:GetText())
  end)

  it("the death countdown is rebuilt each time the client re-writes it, with its unit word in Japanese", function()
    local d = _G.StaticPopup_Show("DEATH")
    _G.StaticPopup_OnUpdate(d, 0.5) -- 89.5 s left: "2 Minutes"
    assert.are.equal("解放まで2分", d.Text:GetText())
    d.timeleft = 30.2
    _G.StaticPopup_OnUpdate(d, 0.1) -- 30.1 → "31 Seconds"
    assert.are.equal("解放まで31秒", d.Text:GetText())
    assert.are.equal("霊体になる", d.ButtonContainer.Buttons[1]:GetText())
  end)

  it("the start delay's re-format of the English is shown in Japanese again", function()
    local d = _G.StaticPopup_Show("DELETE_ITEM", "Linen Cloth")
    assert.are.equal("Linen Clothを破棄しますか？", d.Text:GetText())
    d.startDelay = 1
    _G.StaticPopup_OnUpdate(d, 1)
    assert.are.equal("Linen Clothを破棄しますか？", d.Text:GetText())
  end)

  it("an accept delay's end puts button1's English back; it is shown in Japanese again", function()
    local d = _G.StaticPopup_Show("CONFIRM_RESET_INSTANCES")
    local b1 = d.ButtonContainer.Buttons[1]
    d.acceptDelay = 2
    b1:SetText("2") -- staticpopup.lua:535–540: the countdown number on the button
    _G.StaticPopup_OnUpdate(d, 0.1)
    assert.are.equal("2", b1:GetText())
    d.acceptDelay = nil
    b1:SetText("Yes") -- :541–547: the delay ended, the English label back
    _G.StaticPopup_OnUpdate(d, 0.1)
    assert.are.equal("はい", b1:GetText())
  end)

  it("a generic confirmation keeps the caller's text and buttons Japanese when the client rewrites them", function()
    local data = { text = _G.CONFIRM_RESET_INSTANCES }
    local d = _G.StaticPopup_Show("GENERIC_CONFIRMATION", nil, nil, data)
    d.Text:SetText(data.text) -- shareddialogdefs.lua:1-8: OnShow writes the caller's text and YES / NO
    d.ButtonContainer.Buttons[1]:SetText("Yes")
    WFJ.Popups.onShow(d)
    assert.are.equal("すべてのインスタンスをリセットしますか？", d.Text:GetText())
    assert.are.equal("はい", d.ButtonContainer.Buttons[1]:GetText())
    d.ButtonContainer.Buttons[1]:SetText("Yes") -- an accept delay ended: the English label back
    _G.StaticPopup_OnUpdate(d, 0.1)
    assert.are.equal("はい", d.ButtonContainer.Buttons[1]:GetText())
  end)

  it("the party invite: the caller's line with the inviter's name, and the queue paragraph", function()
    local d = _G.StaticPopup_Show("PARTY_INVITE", string.format(_G.INVITATION, "Wind Mami"))
    assert.are.equal("Wind Mamiがあなたをグループに招待しています。", d.Text:GetText())
    X.alt(WFJ, true)
    assert.are.equal("Wind Mami invites you to a group.", d.Text:GetText())
    X.alt(WFJ, false)
    _G.StaticPopup1.shown = false
    local e = _G.StaticPopup_Show("PARTY_INVITE",
      string.format(_G.INVITATION, "Yes") .. "\n\n" .. _G.ACCEPTING_INVITE_WILL_REMOVE_QUEUE)
    assert.are.equal("Yesがあなたをグループに招待しています。\n\nこのグループに参加すると、現在のキューからすべて外れます。",
      e.Text:GetText())
    _G.StaticPopup_OnUpdate(e, 0.1)
    assert.are.equal("Yesがあなたをグループに招待しています。\n\nこのグループに参加すると、現在のキューからすべて外れます。",
      e.Text:GetText())
  end)

  it("a %s dialog whose line is exactly one key's English translates; any other line stays", function()
    local d = _G.StaticPopup_Show("CONFIRM_LEAVE_INSTANCE_PARTY", _G.CONFIRM_LEAVE_INSTANCE_PARTY)
    assert.are.equal("インスタンスグループから離れますか？", d.Text:GetText())
    _G.StaticPopup1.shown = false
    local e = _G.StaticPopup_Show("CONFIRM_LEAVE_INSTANCE_PARTY", "Leave the battlefield?")
    assert.are.equal("Leave the battlefield?", e.Text:GetText())
    assert.is_true(X.unrecorded(WFJ, e.Text))
  end)

  it("the invite's Decline, locked with a countdown, is Japanese once its English is back", function()
    local d = _G.StaticPopup_Show("PARTY_INVITE", string.format(_G.INVITATION, "Wind Mami"))
    local b2 = d.ButtonContainer.Buttons[2]
    b2:SetText("Decline (1s)") -- gamedialogdefs.lua:13-16, 33: the lock's countdown, written in OnShow
    _G.StaticPopup_OnUpdate(d, 0.1)
    assert.are.equal("Decline (1s)", b2:GetText())
    b2:SetText("Decline") -- :38-41: the ticker unlocks it with the English it saved
    _G.StaticPopup_OnUpdate(d, 0.1)
    assert.are.equal("辞退", b2:GetText())
    assert.are.equal("承諾", d.ButtonContainer.Buttons[1]:GetText())
    X.alt(WFJ, true)
    assert.are.equal("Decline", b2:GetText())
    X.alt(WFJ, false)
    assert.are.equal("辞退", b2:GetText())
  end)

  it("two shown dialogs of one type: the call's own (by data) gets its buttons", function()
    local first = _G.StaticPopup_Show("CONFIRM_RESET_INSTANCES", nil, nil, "one")
    first.ButtonContainer.Buttons[1]:SetText("Yes") -- the client re-set the first's buttons meanwhile
    local second = _G.StaticPopup_Show("CONFIRM_RESET_INSTANCES", nil, nil, "two")
    assert.are_not.equal(first, second)
    assert.are.equal("はい", second.ButtonContainer.Buttons[1]:GetText())
  end)

  it("hooks once; a missing StaticPopup_Show is no surface; wrong-typed input raises nothing", function()
    assert.is_false(WFJ.Popups.init())
    assert.has_no.errors(function()
      WFJ.Popups.onShow(nil)
      WFJ.Popups.onShow({ dialogInfo = 3 })
      WFJ.Popups.onShowCall("NOPE")
      WFJ.Popups.onUpdate({ Text = 1 })
    end)
  end)
end)
