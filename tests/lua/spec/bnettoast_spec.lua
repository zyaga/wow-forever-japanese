-- UI/BNetToast.lua over BNToastFrame and TimeAlertFrame replayed from
-- camelot blizzard_bnet (mainline/bnet.lua:193–298, 361–363; bnet.xml:3–40, 83–87). Friends' names and a broadcast
-- message stay as written.
local S = require("tests.lua.spec.stub_camelot_social")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = S.files("UI/BNetToast.lua")

local UI = {
  BN_TOAST_NEW_INVITE = { "You have received a new friend request.", "新しいフレンドリクエストが届きました。" },
  BN_TOAST_PENDING_INVITES = { "You have |cff82c5ff%d|r friend |4request:requests;.",
    "フレンドリクエストが|cff82c5ff%d|r件あります。" },
  BN_TOAST_NEW_CLUB_INVITATION = { "You've been invited to|n%s", "招待が届きました:|n%s" },
  BN_TOAST_OFFLINE = { "has gone |cffff0000offline|r.", "|cffff0000オフライン|rになりました。" },
  BN_TOAST_ONLINE = { "has come |cff00ff00online|r.", "|cff00ff00オンライン|rになりました。" },
  TIME_PLAYED_ALERT = { "You have been playing for %s. Excessive gameplay can interfere with your daily life.",
    "プレイ時間が%sになりました。長時間のプレイは日常生活に支障をきたすおそれがあります。" },
  CLOSE = { "Close", "閉じる" },
  -- the shard-transfer toast (blizzard_socialtoast/socialtoast.lua:63-85)
  SHARD_TRANSFER_COUNTDOWN_MESSAGE = { "The world around you will refresh in %s %s. Make sure you are out of combat "
    .. "and in a safe area, or click here to refresh now.", "%s%s後に周囲のワールドが更新されます。" },
  SHARD_TRANSFER_REFRESH_MESSAGE = { "World refresh in %s %s", "ワールド更新まで%s%s" },
  SHARD_TRANSFER_ANYTIME = { "Refreshing your world at any time. Characters and creatures around you may change.",
    "いつでもワールドを更新できます。周囲のキャラクターやクリーチャーが変わることがあります。" },
  SECONDS = { "|4Second:Seconds;", "秒" }, MINUTES = { "|4Minute:Minutes;", "分" },
}

-- Core/UIStrings: the community's name is a `text` argument; the session length is SecondsToTime output
local NEEDS = { ARGS = { BN_TOAST_NEW_CLUB_INVITATION = { [1] = "text" }, TIME_PLAYED_ALERT = { [1] = "time" },
  SHARD_TRANSFER_COUNTDOWN_MESSAGE = { [1] = "text", [2] = "entry" },
  SHARD_TRANSFER_REFRESH_MESSAGE = { [1] = "text", [2] = "entry" } } }

local C = {}

local function install()
  local toast = S.frame("BNToastFrame")
  toast.TopLine, toast.MiddleLine, toast.BottomLine, toast.DoubleLine = S.fs(""), S.fs(""), S.fs(""), S.fs("")
  -- BNToastMixin:ShowToast (bnet.lua:193–298), one branch per toast type
  function toast.ShowToast(self)
    local t = C.toast
    if t.kind == "invite" then
      self.DoubleLine.text = S.en("BN_TOAST_NEW_INVITE")
    elseif t.kind == "pending" then
      self.DoubleLine.text = S.en("BN_TOAST_PENDING_INVITES"):gsub("%%d", tostring(t.count)):gsub("|4request:requests;",
        t.count == 1 and "request" or "requests")
    elseif t.kind == "club" then
      self.DoubleLine.text = S.en("BN_TOAST_NEW_CLUB_INVITATION"):format("|cffffd200" .. t.name .. "|r")
    elseif t.kind == "online" then -- bnet.lua:237: grey-wrapped
      self.TopLine.text = t.name
      self.BottomLine.text = "|cff808080" .. S.en("BN_TOAST_ONLINE") .. "|r"
    elseif t.kind == "offline" then
      self.TopLine.text = t.name
      self.BottomLine.text = S.en("BN_TOAST_OFFLINE")
    elseif t.kind == "online" then -- FRIENDS_GRAY_COLOR:WrapTextInColorCode(BN_TOAST_ONLINE) (:237)
      self.TopLine.text = t.name
      self.BottomLine.text = "|cff808080" .. S.en("BN_TOAST_ONLINE") .. "|r"
    elseif t.kind == "broadcast" then
      self.TopLine.text = t.name
      self.BottomLine.text = t.message
    end
  end
  local alert = S.frame("TimeAlertFrame")
  alert.Text = S.fs("")
  function alert.Start() end
  -- BNetTimeAlertMixin:OnUpdate (bnet.lua:350–364): the line is rewritten on every frame while shown
  alert:SetScript("OnUpdate", function(self) self.Text.text = S.en("TIME_PLAYED_ALERT"):format(C.played) end)
  local shard = S.frame("ShardTransferImminentFrame")
  shard.Text = S.fs("")
  function shard.Start() end
  -- ShardTransferImminentMixin:OnUpdate (socialtoast.lua:63-85): the plural group resolved by the client
  shard:SetScript("OnUpdate", function(self)
    local unit = C.left < 60 and (C.left == 1 and "Second" or "Seconds") or "Minutes"
    local n = C.left < 60 and C.left or math.ceil(C.left / 60)
    if C.left <= 0 then self.Text.text = S.en("SHARD_TRANSFER_ANYTIME")
    elseif C.minimized then self.Text.text = S.en("SHARD_TRANSFER_REFRESH_MESSAGE"):format(n, unit)
    else self.Text.text = S.en("SHARD_TRANSFER_COUNTDOWN_MESSAGE"):format(n, unit) end
  end)
end

local function toast(t)
  C.toast = t
  _G.BNToastFrame:ShowToast()
  return _G.BNToastFrame
end

local function tick()
  local alert = _G.TimeAlertFrame
  alert:GetScript("OnUpdate")(alert, 0.1)
  return alert.Text:GetText()
end

local function shardTick()
  local shard = _G.ShardTransferImminentFrame
  shard:GetScript("OnUpdate")(shard, 0.1)
  return shard.Text:GetText()
end

local GLOBALS = { "BNToastFrame", "TimeAlertFrame", "ShardTransferImminentFrame" }

describe("the Battle.net toast and the play-time alert on Forever", function()
  local WFJ
  before_each(function() WFJ = S.load(FILES, UI, NEEDS) end)
  after_each(function() S.teardown(GLOBALS) end)

  it("the online line keeps both colours around the Japanese; the name is untouched", function()
    install()
    assert.is_true(WFJ.BNetToast.init())
    local frame = toast({ kind = "online", name = "Jaina" })
    assert.are.equal("|cff808080|cff00ff00オンライン|rになりました。|r", frame.BottomLine:GetText())
    assert.are.equal("Jaina", frame.TopLine:GetText())
  end)

  it("each toast's fixed line renders Japanese after ShowToast; Alt shows English", function()
    install()
    assert.is_true(WFJ.BNetToast.init())
    local frame = toast({ kind = "invite" })
    assert.are.equal("新しいフレンドリクエストが届きました。", frame.DoubleLine:GetText())
    toast({ kind = "pending", count = 3 })
    assert.are.equal("フレンドリクエストが|cff82c5ff3|r件あります。", frame.DoubleLine:GetText())
    toast({ kind = "club", name = "Close" }) -- a community's name stays as written inside the line
    assert.are.equal("招待が届きました:|n|cffffd200Close|r", frame.DoubleLine:GetText())
    toast({ kind = "offline", name = "Close" })
    assert.are.equal("|cffff0000オフライン|rになりました。", frame.BottomLine:GetText())
    S.alt(WFJ, true)
    assert.are.equal("has gone |cffff0000offline|r.", frame.BottomLine:GetText())
    S.alt(WFJ, false)
  end)

  it("the online line, wrapped a second time in grey: the grey kept around the Japanese; Alt English",
    function()
      install()
      WFJ.BNetToast.init()
      local frame = toast({ kind = "online", name = "Jaina" })
      assert.are.equal("|cff808080|cff00ff00オンライン|rになりました。|r", frame.BottomLine:GetText())
      assert.are.equal("Jaina", frame.TopLine:GetText())
      S.alt(WFJ, true)
      assert.are.equal("|cff808080has come |cff00ff00online|r.|r", frame.BottomLine:GetText())
      S.alt(WFJ, false)
    end)

  it("names and a friend's broadcast are never taken", function()
    install()
    WFJ.BNetToast.init()
    WFJ.Labels.forbidNames(WFJ.BNetToast.NEVER_TOUCH)
    local frame = toast({ kind = "broadcast", name = "Close", message = "Close" })
    assert.are.equal("Close", frame.TopLine:GetText())
    assert.are.equal("Close", frame.BottomLine:GetText())
    assert.is_true(S.unrecorded(WFJ, frame.TopLine))
  end)

  it("the play-time alert stays Japanese across its per-frame rewrites", function()
    install()
    WFJ.BNetToast.init()
    C.played = "2 hours"
    assert.are.equal("プレイ時間が2 hoursになりました。長時間のプレイは日常生活に支障をきたすおそれがあります。", tick())
    C.played = "3 hours"
    assert.are.equal("プレイ時間が3 hoursになりました。長時間のプレイは日常生活に支障をきたすおそれがあります。", tick())
  end)

  it("the shard-transfer toast stays Japanese across its per-frame rewrites, its unit word in Japanese", function()
    install()
    WFJ.BNetToast.init()
    C.left, C.minimized = 120, false
    assert.are.equal("2分後に周囲のワールドが更新されます。", shardTick())
    C.left, C.minimized = 29, true
    assert.are.equal("ワールド更新まで29秒", shardTick())
    C.left = 1
    assert.are.equal("ワールド更新まで1秒", shardTick())
    S.alt(WFJ, true)
    assert.are.equal("World refresh in 1 Second", shardTick())
    S.alt(WFJ, false)
    C.left = 0
    assert.are.equal("いつでもワールドを更新できます。周囲のキャラクターやクリーチャーが変わることがあります。", shardTick())
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    install()
    _G.BNToastFrame.DoubleLine = 3
    _G.TimeAlertFrame = "?"
    assert.has_no.errors(function() assert.is_true(WFJ.BNetToast.init()) end)
    assert.has_no.errors(function() WFJ.BNetToast.onToast() end)
    assert.has_no.errors(function() WFJ.BNetToast.onAlert() end)
    assert.are.equal(3, _G.BNToastFrame.DoubleLine)
  end)

  it("hooks install once; without the frames init returns false and touches nothing", function()
    assert.is_false(WFJ.BNetToast.init())
    install()
    assert.is_true(WFJ.BNetToast.init())
    assert.is_false(WFJ.BNetToast.init())
    assert.are.equal(1, #Stub.hooks["BNToastFrame:ShowToast"])
  end)
end)
