-- Quick join: UI/QuickJoin.lua over QuickJoinFrame / QuickJoinToastButton replayed from camelot
-- blizzard_quickjoin (quickjoin.lua:182–203, 253–255, 650–655, quickjointoast.lua:377–400) and the tooltip writer
-- SocialQueueUtil_SetTooltip (blizzard_uipanels_game/shared/socialqueue.lua:106–175). Player and queue names stay
-- English.
local S = require("tests.lua.spec.stub_camelot_social")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = S.files("UI/QuickJoin.lua")

local UI = {
  JOIN_QUEUE = { "Request to Join", "参加をリクエスト" }, SIGN_UP = { "Sign Up", "申し込む" },
  QUICK_JOIN_ALREADY_IN_PARTY = { "You are already in a group. You must leave your group to join this queue.",
    "すでにグループに参加しています。このキューに参加するにはグループを抜けてください。" },
  SOCIAL_BUTTON = { "Social", "ソーシャル" }, SOCIAL_QUEUE_CLICK_TO_JOIN = { "<Click to Join>", "<クリックで参加>" },
  SOCIAL_QUEUE_QUEUED_FOR = { "queued for", "キュー待機中:" },
  SOCIAL_QUEUE_QUEUED_FOR_STANDALONE = { "Queued for", "キュー待機中:" },
  LFG_LIST_ENTRY_DELISTED = { "This group has been delisted.", "このグループの募集は取り下げられました。" },
  QUICK_JOIN_TOOLTIP_NO_AVAILABLE_ROLES = { "No Available Roles", "募集中のロールなし" },
  QUICK_JOIN_IS_AUTO_ACCEPT_TOOLTIP = { "Auto Accept", "自動承諾" },
  CLOSE = { "Close", "閉じる" },
  -- The dash and toast forms, the roles line
  SOCIAL_QUEUE_FORMAT_ARENA = { "Arena (%1$dv%1$d)", "アリーナ(%1$dv%1$d)" },
  SOCIAL_QUEUE_FORMAT_ARENA_SKIRMISH = { "Arena Skirmish", "アリーナ小競り合い" },
  SOCIAL_QUEUE_FORMAT_BATTLEGROUND = { "Battleground: %s", "戦場: %s" },
  QUICK_JOIN_TOAST_MESSAGE = { "%s queued for %s", "%sが%sの順番待ちに登録しました" },
  QUICK_JOIN_TOAST_LFGLIST_MESSAGE = { '%s joined "%s"', "%sが「%s」に参加しました" },
  QUICK_JOIN_TOOLTIP_AVAILABLE_ROLES = { "Available Roles:", "募集中のロール:" },
}

local C = {}

local function install(o)
  o = o or {}
  local friends = S.frame("FriendsFrame")
  if not o.untitled then function friends.SetTitle() end end
  local frame = S.frame("QuickJoinFrame")
  frame.JoinQueueButton = S.button(nil, S.en("JOIN_QUEUE"))
  function frame.UpdateJoinButtonState(self)
    S.write(self.JoinQueueButton, S.en(C.lfglist and "SIGN_UP" or "JOIN_QUEUE"))
  end
  local toast = S.frame("QuickJoinToastButton")
  toast.Toast, toast.Toast2 = S.frame(), S.frame()
  toast.Toast.Text, toast.Toast2.Text = S.fs("Close queued for Close"), S.fs("")
  function toast.ShowToast(self, text) self.Toast.Text.text = text end -- quickjointoast.lua:299–304
  -- socialqueue.lua:106–175: the title, "Queued for", the "- %s" queue lines, then Show
  _G.SocialQueueUtil_SetTooltip = function(tt, title, queues)
    tt:SetOwner(_G.QuickJoinToastButton.Toast)
    tt:ClearLines()
    tt:AddLine(title)
    tt:AddLine(S.en("SOCIAL_QUEUE_QUEUED_FOR_STANDALONE"))
    for _, q in ipairs(queues) do tt:AddLine("- " .. q) end
    tt:AddLine("Available Roles: |Ttank:0|t")
    tt:Show()
  end
  frame.ScrollBox = Stub.scrollBox()
  function C.row()
    local row = CreateFrame("Button")
    frame.ScrollBox:initFrame(row, {})
    return row
  end
end

describe("the quick join panel on Forever", function()
  local WFJ
  before_each(function() WFJ = S.load(FILES, UI); C.lfglist = false end)
  after_each(function()
    S.teardown({ "FriendsFrame", "QuickJoinFrame", "QuickJoinToastButton", "SocialQueueUtil_SetTooltip" })
  end)

  it("the join button follows UpdateJoinButtonState; Alt shows English", function()
    install()
    assert.is_true(WFJ.QuickJoin.init())
    local button = _G.QuickJoinFrame.JoinQueueButton
    assert.are.equal("参加をリクエスト", button:GetText())
    C.lfglist = true
    _G.QuickJoinFrame:UpdateJoinButtonState()
    assert.are.equal("申し込む", button:GetText())
    S.alt(WFJ, true)
    assert.are.equal("Sign Up", button:GetText())
    S.alt(WFJ, false)
    assert.are.equal("申し込む", button:GetText())
  end)

  it("tooltips: the fixed lines translate; names do not translate; the toast text is untouched", function()
    install()
    WFJ.QuickJoin.init()
    assert.are.same({ "すでにグループに参加しています。このキューに参加するにはグループを抜けてください。" },
      S.tooltip(_G.QuickJoinFrame.JoinQueueButton, { S.en("QUICK_JOIN_ALREADY_IN_PARTY") }))
    assert.are.same({ "ソーシャル |cffffd200(O)|r" }, S.tooltip(_G.QuickJoinToastButton, { "Social |cffffd200(O)|r" }))
    assert.are.same({ "Close", "Close", " ", "<クリックで参加>" },
      S.tooltip(_G.QuickJoinToastButton.Toast, { "Close", "Close", " ", "<Click to Join>" }))
    assert.are.same({ "Close", "キュー待機中:", "- Close", " ", "自動承諾", " ", "<クリックで参加>" },
      S.tooltip(_G.QuickJoinToastButton.Toast, { "Close", "queued for", "- Close", " ", "Auto Accept", " ",
        "<Click to Join>" }))
    assert.are.equal("Close queued for Close", _G.QuickJoinToastButton.Toast.Text:GetText())
    assert.is_true(S.unrecorded(WFJ, _G.QuickJoinToastButton.Toast.Text))
  end)

  it("a pooled row's tooltip: the queue tooltip's fixed lines translate, its title and queues do not", function()
    install()
    WFJ.QuickJoin.init()
    local row = C.row()
    assert.are.same({ "Close", "このグループの募集は取り下げられました。" },
      S.tooltip(row, { "Close", "This group has been delisted." }))
    assert.are.same({ "Close", "キュー待機中:", "- Close", " ", "募集中のロールなし" },
      S.tooltip(row, { "Close", "Queued for", "- Close", " ", "No Available Roles" }))
    assert.are.same({ "Social" }, S.tooltip(row, { "Social" })) -- a row never takes the social button's title
  end)

  it("dash: queue lines show the dash and the queue in Japanese, map and player names kept", function()
    install()
    WFJ.QuickJoin.init()
    _G.SocialQueueUtil_SetTooltip(_G.GameTooltip, "Thrall", { "Arena (2v2)", "Arena Skirmish",
      "Battleground: Warsong Gulch", "Molten Core" })
    local function left(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
    assert.are.equal("Thrall", left(1))
    assert.are.equal("キュー待機中:", left(2))
    assert.are.equal("- アリーナ(2v2)", left(3))
    assert.are.equal("- アリーナ小競り合い", left(4))
    assert.are.equal("- 戦場: Warsong Gulch", left(5))
    assert.are.equal("- Molten Core", left(6))
    assert.are.equal("募集中のロール: |Ttank:0|t", left(7))
    S.alt(WFJ, true)
    assert.are.equal("- Arena Skirmish", left(4))
    S.alt(WFJ, false)
  end)

  it("toast: the player's name kept, a queue that is an entry in Japanese, a listing title kept", function()
    install()
    WFJ.QuickJoin.init()
    local text = _G.QuickJoinToastButton.Toast.Text
    _G.QuickJoinToastButton:ShowToast("Thrall queued for Arena Skirmish")
    assert.are.equal("Thrallがアリーナ小競り合いの順番待ちに登録しました", text:GetText())
    _G.QuickJoinToastButton:ShowToast("Thrall queued for Molten Core")
    assert.are.equal("ThrallがMolten Coreの順番待ちに登録しました", text:GetText())
    _G.QuickJoinToastButton:ShowToast('Jaina joined "Arena Skirmish."')
    assert.are.equal("Jainaが「Arena Skirmish.」に参加しました", text:GetText())
    S.alt(WFJ, true)
    assert.are.equal('Jaina joined "Arena Skirmish."', text:GetText())
    S.alt(WFJ, false)
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    install()
    _G.QuickJoinFrame.JoinQueueButton = 3
    _G.QuickJoinFrame.UpdateJoinButtonState = "?"
    _G.QuickJoinToastButton = true
    _G.QuickJoinFrame.ScrollBox = "?"
    assert.has_no.errors(function() assert.is_true(WFJ.QuickJoin.init()) end)
  end)

  it("hooks install once; without the mainline social window init returns false and touches nothing", function()
    assert.is_false(WFJ.QuickJoin.init())
    install({ untitled = true })
    assert.is_false(WFJ.QuickJoin.init())
    assert.are.equal("Request to Join", _G.QuickJoinFrame.JoinQueueButton:GetText())
    install()
    assert.is_true(WFJ.QuickJoin.init())
    assert.is_false(WFJ.QuickJoin.init())
    assert.are.equal(1, #Stub.hooks["QuickJoinFrame:UpdateJoinButtonState"])
  end)
end)
