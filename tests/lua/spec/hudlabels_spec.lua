-- UI/HudLabels.lua over the HUD's small bars replayed from Forever blizzard_mirrortimer/mainline/
-- mirrortimer.lua:50–57, 146–158, blizzard_swingtimer/blizzard_swingtimer.lua:161–163, blizzard_statustrackingbar/
-- mainline/honorbar.lua:14–23 and blizzard_actionstatus/mainline/actionstatus.lua:50–55. A spell-named mirror timer
-- stays English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/HudLabels.lua"

local UI = {
  BREATH_LABEL = { "Breath", "息" },
  EXHAUSTION_LABEL = { "Fatigue", "疲労" },
  SWING_TIMER_MAIN_HAND = { "Main Hand", "メインハンド" },
  SWING_TIMER_OFF_HAND = { "Off Hand", "オフハンド" },
  SWING_TIMER_RANGED = { "Ranged", "遠隔" },
  HONOR_BAR = { "Honor %d / %d", "名誉 %d / %d" },
  SCREENSHOT_SUCCESS = { "Screen Captured", "スクリーンショットを保存しました" },
  PING_TARGET_TOGGLED_ALL = { "Ping Target: Show All Enabled", "ピン対象: すべて表示" },
  CANCEL = { "Cancel", "キャンセル" }, -- a dictionary word a mirror timer could be named after a spell
  -- the buff durations (SecondsToTimeAbbrev)
  MINUTE_ONELETTER_ABBR = { "%d m", "%d分" }, SECOND_ONELETTER_ABBR = { "%d s", "%d秒" },
  HOUR_ONELETTER_ABBR = { "%d h", "%d時間" },
  -- the FPS counter's bound form
  FPS_COUNTER_CPU_BOUND = { "%.1f CPU Bound", "%.1f CPU律速" },
  FPS_COUNTER_GPU_BOUND = { "%.1f GPU Bound", "%.1f GPU律速" },
}
local function en(key) return UI[key][1] end
local function ja(key) return UI[key][2] end

local function installHud()
  local container = CreateFrame("Frame", "MirrorTimerContainer")
  container.mirrorTimers = {}
  for i = 1, 3 do
    local timer = CreateFrame("Frame")
    timer.Text = Stub.fontString("")
    function timer.Setup(self, _, _, _, _, label) self.Text.text = label end
    container.mirrorTimers[i] = timer
  end
  for name, key in pairs({ SwingTimerMainHandFrame = "SWING_TIMER_MAIN_HAND",
    SwingTimerOffHandFrame = "SWING_TIMER_OFF_HAND", SwingTimerRangedFrame = "SWING_TIMER_RANGED" }) do
    local f = CreateFrame("Frame", name)
    f.StatusBar = { TypeLabel = Stub.fontString(""), TimeLabel = Stub.fontString("0.0") }
    f.typeText = en(key)
    function f.InitializeBarPresentation(self) self.StatusBar.TypeLabel.text = self.typeText end
    f:InitializeBarPresentation() -- OnLoad
  end
  _G.StatusTrackingBarInfo = { BarsEnum = { Reputation = 1, Honor = 2, Experience = 4 } }
  local bars = CreateFrame("Frame", "MainStatusTrackingBarContainer")
  local honor = CreateFrame("Frame")
  honor.OverlayFrame = { Text = Stub.fontString("") }
  function honor.UpdateOverlayFrameText(self) self.OverlayFrame.Text.text = string.format("Honor %d / %d", 120, 900) end
  bars.bars = { [2] = honor }
  -- the aura frames, their buttons made at OnLoad from AuraButtonMixin; UpdateDuration writes the time
  _G.AuraButtonMixin = { UpdateDuration = function(self, fmt, v) self.Duration.text = string.format(fmt, v) end }
  for _, name in ipairs({ "BuffFrame", "DebuffFrame" }) do
    local frame = CreateFrame("Frame", name)
    frame.auraFrames = {}
    for i = 1, 2 do
      local b = CreateFrame("Button")
      b.Duration = Stub.fontString("")
      b.UpdateDuration = _G.AuraButtonMixin.UpdateDuration -- Mixin copies the method at frame creation
      frame.auraFrames[i] = b
    end
    frame.auraFrames[3] = { isAuraAnchor = true } -- a private aura anchor: no duration of its own
  end
  local status = CreateFrame("Frame", "ActionStatus")
  status.Text = Stub.fontString("")
  function status.DisplayMessage(self, text) self.Text.text = text end
  -- the FPS counter (blizzard_framerateframe/mainline/framerateframe.lua:9–24)
  local fps = CreateFrame("Frame", "FramerateFrame")
  fps.FramerateText = Stub.fontString("")
  function fps.FramerateText.SetFormattedText(self, fmt, ...) self.text = string.format(fmt, ...) end
end

local GLOBALS = { "MirrorTimerContainer", "SwingTimerMainHandFrame", "SwingTimerOffHandFrame",
  "SwingTimerRangedFrame", "StatusTrackingBarInfo", "MainStatusTrackingBarContainer", "ActionStatus", "BuffFrame",
  "FramerateFrame",
  "DebuffFrame", "ExternalDefensivesFrame", "AuraButtonMixin" }

describe("the HUD's small bars and messages on Forever", function()
  local WFJ

  local function load()
    local ns = H.loadChunks(FILES)
    H.uiSetup(ns, UI)
    return ns
  end

  local function fresh()
    H.uiTeardown()
    for _, n in ipairs(GLOBALS) do _G[n] = nil end
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
  end

  before_each(function()
    fresh()
    WFJ = load()
    installHud()
    assert.is_true(WFJ.HudLabels.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, n in ipairs(GLOBALS) do _G[n] = nil end
  end)

  it("mirror timers: Breath and Fatigue translate; a spell-named timer stays English", function()
    local timers = _G.MirrorTimerContainer.mirrorTimers
    timers[1]:Setup("BREATH", 60000, 60000, 0, en("BREATH_LABEL"))
    assert.are.equal(ja("BREATH_LABEL"), timers[1].Text:GetText())
    timers[2]:Setup("EXHAUSTION", 1, 1, 0, en("EXHAUSTION_LABEL"))
    assert.are.equal(ja("EXHAUSTION_LABEL"), timers[2].Text:GetText())
    timers[1]:Setup("FEIGNDEATH", 1, 1, 0, "Cancel") -- the same frame reused for a spell-named timer
    assert.are.equal("Cancel", timers[1].Text:GetText())
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal(en("EXHAUSTION_LABEL"), timers[2].Text:GetText())
    assert.are.equal("Cancel", timers[1].Text:GetText())
  end)

  it("swing timers: the type label translates at init and after a re-initialize; the time stays", function()
    assert.are.equal(ja("SWING_TIMER_MAIN_HAND"), _G.SwingTimerMainHandFrame.StatusBar.TypeLabel:GetText())
    assert.are.equal(ja("SWING_TIMER_OFF_HAND"), _G.SwingTimerOffHandFrame.StatusBar.TypeLabel:GetText())
    assert.are.equal(ja("SWING_TIMER_RANGED"), _G.SwingTimerRangedFrame.StatusBar.TypeLabel:GetText())
    _G.SwingTimerRangedFrame:InitializeBarPresentation()
    assert.are.equal(ja("SWING_TIMER_RANGED"), _G.SwingTimerRangedFrame.StatusBar.TypeLabel:GetText())
    assert.are.equal("0.0", _G.SwingTimerRangedFrame.StatusBar.TimeLabel:GetText())
  end)

  it("the honor bar's text and the screen message translate", function()
    local honor = _G.MainStatusTrackingBarContainer.bars[2]
    honor:UpdateOverlayFrameText()
    assert.are.equal("名誉 120 / 900", honor.OverlayFrame.Text:GetText())
    _G.ActionStatus:DisplayMessage(en("SCREENSHOT_SUCCESS"))
    assert.are.equal(ja("SCREENSHOT_SUCCESS"), _G.ActionStatus.Text:GetText())
    _G.ActionStatus:DisplayMessage(en("PING_TARGET_TOGGLED_ALL"))
    assert.are.equal(ja("PING_TARGET_TOGGLED_ALL"), _G.ActionStatus.Text:GetText())
    _G.ActionStatus:DisplayMessage("Thrall's message") -- another addon's text
    assert.are.equal("Thrall's message", _G.ActionStatus.Text:GetText())
  end)

  it("an aura's duration is Japanese with its number; every frame's rewrite of the same value keeps it;"
    .. " Alt shows the English", function()
    local b = _G.BuffFrame.auraFrames[1]
    b:UpdateDuration(en("MINUTE_ONELETTER_ABBR"), 5)
    assert.are.equal("5分", b.Duration:GetText())
    b:UpdateDuration(en("MINUTE_ONELETTER_ABBR"), 5) -- the next frame writes the same English again
    assert.are.equal("5分", b.Duration:GetText())
    b:UpdateDuration(en("SECOND_ONELETTER_ABBR"), 30)
    assert.are.equal("30秒", b.Duration:GetText())
    local d = _G.DebuffFrame.auraFrames[2]
    d:UpdateDuration(en("HOUR_ONELETTER_ABBR"), 1)
    assert.are.equal("1時間", d.Duration:GetText())
    Stub.keys.alt = true; WFJ.Modifier.refresh()
    assert.are.equal("30 s", b.Duration:GetText())
    b:UpdateDuration(en("SECOND_ONELETTER_ABBR"), 30) -- held: the client's English stays
    assert.are.equal("30 s", b.Duration:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    assert.are.equal("30秒", b.Duration:GetText())
    -- a button made later carries the hooked mixin, and is never hooked twice (its own hook is not added)
    local later = CreateFrame("Button")
    later.Duration = Stub.fontString("")
    for k, v in pairs(_G.AuraButtonMixin) do later[k] = v end
    later:UpdateDuration(en("SECOND_ONELETTER_ABBR"), 9)
    assert.are.equal("9秒", later.Duration:GetText())
  end)

  it("an aura's duration that is a secret value is left as the client wrote it, unread", function()
    local b = _G.BuffFrame.auraFrames[1]
    b:UpdateDuration(en("MINUTE_ONELETTER_ABBR"), 5)
    assert.are.equal("5分", b.Duration:GetText())
    -- in combat: the client's line can be a value the addon may write but not compare
    local secret = { ["4 m"] = true }
    _G.issecretvalue = function(v) return secret[v] == true end
    WFJ.HudLabels.init() -- the name resolves again now the client has it
    local records = WFJ.SurfaceState.count(WFJ.HudLabels.SURFACE)
    b.Duration.text = "4 m"
    assert.are.equal(0, WFJ.HudLabels.onDuration(b))
    assert.are.equal("4 m", b.Duration:GetText())
    assert.has_no.errors(function() b:UpdateDuration(en("MINUTE_ONELETTER_ABBR"), 4) end)
    assert.are.equal("4 m", b.Duration:GetText())
    assert.are.equal(records, WFJ.SurfaceState.count(WFJ.HudLabels.SURFACE))
    -- Alt while the line is secret: the record is dropped without comparing the secret, no error
    Stub.keys.alt = true
    assert.has_no.errors(function() WFJ.Modifier.refresh() end)
    assert.are.equal("4 m", b.Duration:GetText())
    Stub.keys.alt = false; WFJ.Modifier.refresh()
    -- readable again: Japanese again
    _G.issecretvalue = nil
    WFJ.HudLabels.init()
    b:UpdateDuration(en("MINUTE_ONELETTER_ABBR"), 3)
    assert.are.equal("3分", b.Duration:GetText())
  end)

  it("the FPS counter's bound form is Japanese with its number; the bare number stays", function()
    local fs = _G.FramerateFrame.FramerateText
    fs:SetFormattedText(en("FPS_COUNTER_CPU_BOUND"), 59.94)
    assert.are.equal("59.9 CPU律速", fs:GetText())
    fs:SetFormattedText(en("FPS_COUNTER_GPU_BOUND"), 120)
    assert.are.equal("120.0 GPU律速", fs:GetText())
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    assert.are.equal("120.0 GPU Bound", fs:GetText())
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    fs:SetFormattedText("%.1f", 60)
    assert.are.equal("60.0", fs:GetText())
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    fresh()
    local ns = load()
    installHud()
    _G.MirrorTimerContainer.mirrorTimers = { 1, "x", { Setup = true }, _G.MirrorTimerContainer.mirrorTimers[1] }
    _G.SwingTimerMainHandFrame = 5
    _G.SwingTimerOffHandFrame.StatusBar = "moved"
    _G.StatusTrackingBarInfo.BarsEnum = "gone"
    _G.ActionStatus.Text = false
    assert.has_no.errors(function() assert.is_true(ns.HudLabels.init()) end)
    assert.are.equal(ja("SWING_TIMER_RANGED"), _G.SwingTimerRangedFrame.StatusBar.TypeLabel:GetText())
    assert.are.equal("", _G.SwingTimerOffHandFrame.StatusBar == "moved" and "" or "x")
    assert.has_no.errors(function()
      ns.HudLabels.onMirrorSetup(7)
      ns.HudLabels.showHonor("x", "k")
      ns.HudLabels.onActionStatus()
    end)
  end)

  it("hooks install once; a client with none of the widgets is skipped without error", function()
    assert.is_false(WFJ.HudLabels.init())
    assert.are.equal(1, #Stub.hooks["ActionStatus:DisplayMessage"])
    fresh()
    local bare = load()
    assert.has_no.errors(function() assert.is_false(bare.HudLabels.init()) end)
  end)
end)
