-- The Raid tab of the newer social window: UI/Raid.lua over SocialUIFrame.RaidFrame and SocialUIFrame.RaidInfoFrame
-- replayed from blizzard_raidframe/mainline/raidframesocialview.lua (:34–40, 46–56, 97–150, 226–294) and
-- raidinfoframesocialview.lua (:43–68, 86–116) with their XML. A roster button's name, level and class are never
-- written: it is a secure unit button.
local S = require("tests.lua.spec.stub_camelot_social")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = S.files("UI/Raid.lua")

local UI = {
  RAID_DESCRIPTION = { "Raids are groups of more than 5 people.", "レイドは6人以上のグループです。" },
  RAID_INFO = { "Raid Info", "レイド情報" }, CONVERT_TO_RAID = { "Convert To Raid", "レイドに変換" },
  ALL_ASSIST_LABEL_SHORT = { "All", "すべて" },
  ALL_ASSIST_DESCRIPTION = { "If checked, all raid members will have assistant permissions.",
    "チェックすると、レイドメンバー全員がアシスタント権限を持ちます。" },
  ALL_ASSIST_NOT_LEADER_ERROR = { "Only the Raid Leader may change this option.",
    "この設定を変更できるのはレイドリーダーだけです。" },
  GROUP_NUMBER = { "Group %d", "グループ%d" },
  RAID_ASSISTANT = { "Raid Assistant", "レイドアシスタント" }, RAID_LEADER = { "Raid Leader", "レイドリーダー" },
  MAIN_TANK = { "Main Tank", "メインタンク" }, MAIN_ASSIST = { "Main Assist", "メインアシスト" },
  INSTANCE = { "Instance", "インスタンス" }, LOCK_EXPIRE = { "Lock Expire", "ロック期限" },
  EXTEND_RAID_LOCK = { "Extend Raid Lock", "レイドロックを延長" },
  UNEXTEND_RAID_LOCK = { "Remove Raid Lock Extension", "レイドロックの延長を解除" },
  RAID_INSTANCE_EXPIRES_EXPIRED = { "Expired", "期限切れ" }, DAYS_ABBR = { "%d |4Day:Days;", "%d日" },
  RAID_INFO_WORLD_BOSS = { "World Boss", "ワールドボス" }, EXTENDED = { "Extended", "延長済み" },
  ["Difficulty:9"] = { "40 Player", "40人" },
  CLOSE = { "Close", "閉じる" },
}

local GREY = "|cff808080"
local C = {}

local function install()
  local en = S.en
  local frame = S.frame("SocialUIFrame")
  local view = S.put(frame, "RaidFrame", S.frame(nil, "RaidFrame"))
  view.RaidDescription = S.fs(en("RAID_DESCRIPTION"))
  view.RaidInfoButton, view.ConvertToRaidButton = S.button(nil, en("RAID_INFO")), S.button(nil, en("CONVERT_TO_RAID"))
  local all = S.put(view, "AllAssistCheckButton", S.frame(nil, "AllAssistCheckButton"))
  all.AllText = S.fs(en("ALL_ASSIST_LABEL_SHORT"))
  function all.UpdateAvailable(self) -- raidframesocialview.lua:34–40
    self.AllText.text = (C.leader and "|cffffd200" or GREY) .. en("ALL_ASSIST_LABEL_SHORT") .. "|r"
  end
  view.groups, view.players = {}, {}
  function view.UpdateContents(self) -- :244–294: the groups and their roster buttons, built again
    self.groups, self.players = {}, {}
    for i = 1, C.raid and 2 or 0 do
      C.groupFrames[i] = C.groupFrames[i] or { GroupNumberText = S.fs("") }
      C.groupFrames[i].GroupNumberText.text = en("GROUP_NUMBER"):format(i)
      self.groups[i] = C.groupFrames[i]
    end
    if C.raid then
      self.players[1] = { LeaderIcon = S.frame(), RoleIcon = S.frame(), CharacterName = S.fs("Close"),
        CharacterLevel = S.fs("60"), CharacterClass = S.fs("Warrior") }
    end
  end
  local info = S.put(frame, "RaidInfoFrame", S.frame(nil, "RaidInfoFrame"))
  info.children = { S.fs(en("INSTANCE")), S.fs(en("LOCK_EXPIRE")) } -- the two unnamed column labels (xml:91, 97)
  info.ExtendButton = S.button(nil, en("EXTEND_RAID_LOCK"))
  info.ExtendButton.fits = 0
  function info.ExtendButton.FitToText(self) self.fits = self.fits + 1 end
  function info.UpdateButtons(self) -- raidinfoframesocialview.lua:43–68
    S.write(self.ExtendButton, en(C.extended and "UNEXTEND_RAID_LOCK" or "EXTEND_RAID_LOCK"))
  end
  info.ScrollBox = Stub.scrollBox()
  function C.row(existing, data) -- InitButton (:86–116)
    local row = existing or { name = S.fs(""), reset = S.fs(""), difficulty = S.fs(""), extended = S.fs("") }
    info.ScrollBox:initFrame(row, data, function()
      row.reset.text = data.reset or (GREY .. en("RAID_INSTANCE_EXPIRES_EXPIRED") .. "|r")
      row.name.text = data.reset and data.name or (GREY .. data.name .. "|r")
      row.difficulty.text = data.difficulty
      row.extended.text = en("EXTENDED")
    end)
    return row
  end
  return view, info
end

describe("the raid view of the social window", function()
  local WFJ, view, info
  before_each(function()
    WFJ = S.load(FILES, UI)
    C.leader, C.raid, C.extended, C.groupFrames = false, false, false, {}
    view, info = install()
  end)
  after_each(function()
    WFJ.State.setNames(false)
    S.teardown({ "SocialUIFrame" })
  end)

  it("is set up with no older panel: its description, its buttons and the saved-instance columns translate; the"
    .. " reveal key shows the English", function()
    assert.is_true(WFJ.Raid.init())
    assert.is_false(WFJ.Raid.init()) -- once
    assert.are.equal("レイドは6人以上のグループです。", view.RaidDescription:GetText())
    assert.are.equal("レイド情報", view.RaidInfoButton:GetText())
    assert.are.equal("レイドに変換", view.ConvertToRaidButton:GetText())
    assert.are.equal("インスタンス", info.children[1]:GetText())
    assert.are.equal("ロック期限", info.children[2]:GetText())
    assert.are.equal("レイドロックを延長", info.ExtendButton:GetText())
    S.alt(WFJ, true)
    assert.are.equal("Raid Info", view.RaidInfoButton:GetText())
    assert.are.equal("Instance", info.children[1]:GetText())
    S.alt(WFJ, false)
    assert.are.equal("レイド情報", view.RaidInfoButton:GetText())
  end)

  it("the All label follows UpdateAvailable inside its colour, and its tooltip translates", function()
    WFJ.Raid.init()
    local all = view.AllAssistCheckButton
    assert.are.equal("すべて", all.AllText:GetText())
    all:UpdateAvailable()
    assert.are.equal(GREY .. "すべて|r", all.AllText:GetText())
    C.leader = true
    all:UpdateAvailable()
    assert.are.equal("|cffffd200すべて|r", all.AllText:GetText())
    assert.are.same({ "チェックすると、レイドメンバー全員がアシスタント権限を持ちます。",
      "この設定を変更できるのはレイドリーダーだけです。" }, S.tooltip(all, {
      "If checked, all raid members will have assistant permissions.",
      "Only the Raid Leader may change this option." }))
  end)

  it("after each UpdateContents the group headers translate and the roster icons' tooltips do; a roster button's"
    .. " name, level and class are never written", function()
    WFJ.Raid.init()
    C.raid = true
    view:UpdateContents()
    assert.are.equal("グループ1", view.groups[1].GroupNumberText:GetText())
    assert.are.equal("グループ2", view.groups[2].GroupNumberText:GetText())
    local player = view.players[1]
    assert.are.same({ "レイドリーダー" }, S.tooltip(player.LeaderIcon, { "Raid Leader" }))
    assert.are.same({ "メインタンク" }, S.tooltip(player.RoleIcon, { "Main Tank" }))
    assert.are.same({ "Raid Leader" }, S.tooltip(player.RoleIcon, { "Raid Leader" })) -- each icon its own words
    WFJ.State.setNames(true)
    view:UpdateContents() -- the pooled group frames come back with the client's text
    assert.are.equal("グループ1", view.groups[1].GroupNumberText:GetText())
    for _, key in ipairs({ "CharacterName", "CharacterLevel", "CharacterClass" }) do
      assert.is_true(S.unrecorded(WFJ, view.players[1][key]))
    end
    assert.are.equal("Warrior", view.players[1].CharacterClass:GetText())
    S.alt(WFJ, true)
    assert.are.equal("Group 1", view.groups[1].GroupNumberText:GetText())
    S.alt(WFJ, false)
  end)

  it("the extend button follows UpdateButtons and is fitted to its text again", function()
    WFJ.Raid.init()
    local fits = info.ExtendButton.fits
    C.extended = true
    info:UpdateButtons()
    assert.are.equal("レイドロックの延長を解除", info.ExtendButton:GetText())
    assert.is_true(info.ExtendButton.fits > fits)
  end)

  it("a saved-instance row: the reset, the difficulty and the extended label translate, Expired inside its grey;"
    .. " with Japanese names on the instance's name shows its Japanese", function()
    WFJ.Data.add("name", { [WFJ.Names.key("Molten Core")] = "モルテン・コア\tもるてん・こあ" })
    WFJ.Raid.init()
    WFJ.State.setNames(false)
    local row = C.row(nil, { name = "Molten Core", reset = "3 Days", difficulty = "40 Player" })
    assert.are.equal("3日", row.reset:GetText())
    assert.are.equal("40人", row.difficulty:GetText())
    assert.are.equal("延長済み", row.extended:GetText())
    assert.are.equal("Molten Core", row.name:GetText()) -- names are off
    WFJ.State.setNames(true)
    C.row(row, { name = "Molten Core", difficulty = "World Boss" })
    assert.are.equal(GREY .. "期限切れ|r", row.reset:GetText())
    assert.are.equal("ワールドボス", row.difficulty:GetText())
    assert.are.equal(GREY .. "モルテン・コア|r", row.name:GetText())
    S.alt(WFJ, true)
    assert.are.equal(GREY .. "Expired|r", row.reset:GetText())
    assert.are.equal(GREY .. "Molten Core|r", row.name:GetText())
    S.alt(WFJ, false)
    C.row(row, { name = "Nobody Known Place", reset = "3 Days", difficulty = "Close" })
    assert.are.equal("Nobody Known Place", row.name:GetText())
    assert.are.equal("Close", row.difficulty:GetText()) -- a dictionary word that is no difficulty
  end)

  it("wrong shapes raise nothing", function()
    view.groups, view.players, view.AllAssistCheckButton, info.ScrollBox, info.ExtendButton = 3, "?", 7, true, false
    assert.has_no.errors(function()
      assert.is_true(WFJ.Raid.init())
      view:UpdateContents()
      WFJ.Raid.onViewRow({ reset = 4 })
      WFJ.Raid.onViewRow(9)
    end)
  end)
end)
