local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

-- HelpTip callouts. A stub of blizzard_sharedxml/helptip.lua: a pool of frames made from
-- HelpTipTemplateMixin (Mixin copies the methods when the frame is created), Show → Init stores info → Layout →
-- ApplyText writes info.text, then measures Text:GetHeight() for the box (helptip.lua:174–193, 495–519, 572–647).
local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "UI/HelpTips.lua"

local UI = {
  TALENT_MICRO_BUTTON_UNSPENT_TALENTS = { "You have unspent talent points.", "未使用のタレントポイントがあります。" },
  WORLD_MAP_TUTORIAL2 = { "Click a quest to see its details.", "クエストをクリックすると詳細が表示されます。" },
  RAID = { "Raid", "レイド" }, -- a dictionary word that is no callout key
  MAIN_HELP_BUTTON_TOOLTIP = { "Click this to toggle on/off the help system for this frame.",
    "クリックすると、この画面のヘルプ表示をオン／オフします。" },
  -- the spellbook's plate sections, a level-1 tutorial
  SPELLBOOK_HELP_1 = { "Drag spells to your action bar from here.", "ここから呪文をアクションバーにドラッグします。" },
  TUTORIAL_SUPERTRACK_STEP_1 = { "Focus on a quest by clicking its icon", "アイコンをクリックしてクエストに注目します" },
}

local function installHelpTip()
  local mixin = {}
  function mixin:ApplyText() self.Text:SetText(self.info.text) end
  function mixin:Layout()
    self:ApplyText()
    self.boxHeight = self.Text:GetHeight() + 20
  end
  _G.HelpTipTemplateMixin = mixin
  local pool = { activeObjects = {}, inactiveObjects = {} }
  function pool:Acquire()
    local f = table.remove(self.inactiveObjects)
    if not f then
      f = CreateFrame("Frame")
      f.Text = Stub.fontString("")
      for k, v in pairs(_G.HelpTipTemplateMixin) do f[k] = v end -- Mixin: copied when the frame is made
    end
    self.activeObjects[f] = true
    return f
  end
  function pool:Release(f) self.activeObjects[f] = nil; self.inactiveObjects[#self.inactiveObjects + 1] = f end
  function pool:EnumerateActive() return pairs(self.activeObjects) end
  local HelpTip = { framePool = pool }
  function HelpTip:Show(_, info)
    local f = self.framePool:Acquire()
    f.info = info
    f:Layout()
    return f
  end
  function HelpTip:IsShowing(_, text)
    for f in self.framePool:EnumerateActive() do if f.info.text == text then return true end end
    return false
  end
  _G.HelpTip = HelpTip
  return HelpTip
end

describe("UI/HelpTips: HelpTip callouts", function()
  local WFJ, tip

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    tip = installHelpTip()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end)

  after_each(function() H.uiTeardown(); _G.HelpTip, _G.HelpTipTemplateMixin = nil, nil end)

  it("rewrites the callout inside ApplyText, so the box is measured with the Japanese; info.text is untouched",
    function()
      assert.is_true(WFJ.HelpTips.init())
      local en = UI.TALENT_MICRO_BUTTON_UNSPENT_TALENTS[1]
      local f = tip:Show(nil, { text = en })
      assert.are.equal("未使用のタレントポイントがあります。", f.Text:GetText())
      assert.are.equal(f.Text:GetHeight() + 20, f.boxHeight)
      assert.are.equal(en, f.info.text)
      assert.is_true(tip:IsShowing(nil, en)) -- Blizzard's identity checks still see the English
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal(en, f.Text:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      f:Layout() -- a UI_SCALE_CHANGED relayout re-applies info.text, and the hook again
      assert.are.equal("未使用のタレントポイントがあります。", f.Text:GetText())
    end)

  it("hooks the frames the pool already holds, active and inactive, once each", function()
    local active = tip:Show(nil, { text = UI.WORLD_MAP_TUTORIAL2[1] })
    local spare = tip:Show(nil, { text = "Other" })
    tip.framePool:Release(spare)
    assert.is_true(WFJ.HelpTips.init())
    assert.are.equal("クエストをクリックすると詳細が表示されます。", active.Text:GetText()) -- shown now
    local again = tip:Show(nil, { text = UI.TALENT_MICRO_BUTTON_UNSPENT_TALENTS[1] }) -- the inactive frame reused
    assert.are.equal(spare, again)
    assert.are.equal("未使用のタレントポイントがあります。", again.Text:GetText())
    local calls = 0
    local set = again.Text.SetText
    again.Text.SetText = function(fs, t) calls = calls + 1; return set(fs, t) end
    again:Layout()
    assert.are.equal(2, calls) -- the client's write, then ours: hooked once, not twice
    assert.is_true(WFJ.HelpTips.init()) -- a second init hooks nothing more
  end)

  it("a callout that is no callout key stays the client's English", function()
    WFJ.HelpTips.init()
    local f = tip:Show(nil, { text = UI.RAID[1] })
    assert.are.equal("Raid", f.Text:GetText())
  end)

  it("no HelpTip (a client without it): init returns false", function()
    _G.HelpTip = nil
    local W = H.loadChunks(FILES)
    H.uiSetup(W, UI)
    assert.is_false(W.HelpTips.init())
  end)

  -- the help-plate tooltip (the world map's "?" button), blizzard_helpplate.lua:214–222
  it("the help-plate tooltip is Japanese and its glow box is re-measured for it", function()
    local plate = CreateFrame("Frame", "HelpPlateTooltip")
    plate.Text = Stub.fontString("")
    function plate:SetHeight(h) self.height = h end
    function plate:GetHeight() return self.height end
    function plate:Init(_, text)
      self.Text:SetText(text)
      self:SetHeight(self.Text:GetHeight() + 30)
    end
    function plate:InitFromMainHelpPlateButton(button)
      self:Init(button, button.mainHelpPlateButtonTooltipText or _G.MAIN_HELP_BUTTON_TOOLTIP, "RIGHT")
    end
    _G.HelpPlateTooltip = plate
    local W = H.loadChunks(FILES)
    H.uiSetup(W, UI)
    W.HelpTips.init()
    plate:InitFromMainHelpPlateButton({})
    assert.are.equal("クリックすると、この画面のヘルプ表示をオン／オフします。", plate.Text:GetText())
    assert.are.equal(plate.Text:GetHeight() + 30, plate:GetHeight())
    Stub.keys.alt = true; W.Modifier.refresh() -- Alt: the English, and the box refit for it
    assert.are.equal(_G.MAIN_HELP_BUTTON_TOOLTIP, plate.Text:GetText())
    assert.are.equal(plate.Text:GetHeight() + 30, plate:GetHeight())
    Stub.keys.alt = false; W.Modifier.refresh()
    plate:Init({}, "Some other plate text")
    assert.are.equal("Some other plate text", plate.Text:GetText())
    _G.HelpPlateTooltip = nil
  end)
  it("a spellbook plate tile's hover (the same Init) is Japanese and re-measured", function()
    local plate = CreateFrame("Frame", "HelpPlateTooltip")
    plate.Text = Stub.fontString("")
    function plate:SetHeight(h) self.height = h end
    function plate:GetHeight() return self.height end
    function plate:Init(_, text)
      self.Text:SetText(text)
      self:SetHeight(self.Text:GetHeight() + 30)
    end
    _G.HelpPlateTooltip = plate
    local W = H.loadChunks(FILES)
    H.uiSetup(W, UI)
    W.HelpTips.init()
    plate:Init({}, UI.SPELLBOOK_HELP_1[1], "DOWN") -- HelpPlateTileMixin:OnEnter → Init(tile.Button, ToolTipText)
    assert.are.equal("ここから呪文をアクションバーにドラッグします。", plate.Text:GetText())
    assert.are.equal(plate.Text:GetHeight() + 30, plate:GetHeight())
    _G.HelpPlateTooltip = nil
  end)

  it("the super-tracking tutorial callout is Japanese", function()
    WFJ.HelpTips.init()
    local f = tip:Show(nil, { text = UI.TUTORIAL_SUPERTRACK_STEP_1[1] })
    assert.are.equal("アイコンをクリックしてクエストに注目します", f.Text:GetText())
    assert.are.equal(UI.TUTORIAL_SUPERTRACK_STEP_1[1], f.info.text)
  end)
end)

-- every other Forever window's HelpTip callouts and help-plate tiles (the toy box's paging tip,
-- blizzard_toybox.lua:34, 378; the transmogrifier's plate, blizzard_transmog.lua:106–108).
describe("UI/HelpTips: the other windows' callouts and plate tiles", function()
  local W, tip
  local UI45 = {
    TOYBOX_MOUSEWHEEL_PAGING_HELP = { "Tip: You can use your mouse wheel to quickly page through the Toy Box.",
      "ヒント：マウスホイールでおもちゃ箱のページを素早くめくれます。" },
    TUTORIAL_VOICE = { "You can join or leave voice chat here.", "ここでボイスチャットに参加・退出できます。" },
    TRANSMOG_HELP_2 = { "Assign appearances to any gear slot in an outfit to override the look of the equipment in "
      .. "that slot.\n\nAssigning or updating appearances costs gold, but once saved, you can switch to that outfit "
      .. "anytime for free.", "衣装の各装備スロットに外見を割り当てると、そのスロットの装備の見た目を上書きします。"
      .. "\n\n外見の割り当てや更新にはゴールドがかかりますが、一度保存すればいつでも無料でその衣装に切り替えられます。" },
    RAID = { "Raid", "レイド" },
  }

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    tip = installHelpTip()
  end)

  after_each(function()
    H.uiTeardown(); _G.HelpTip, _G.HelpTipTemplateMixin, _G.HelpPlateTooltip = nil, nil, nil
  end)

  it("a new HelpTips.KEYS callout renders Japanese; info.text keeps the English", function()
    W = H.loadChunks(FILES)
    H.uiSetup(W, UI45)
    assert.is_true(W.HelpTips.init())
    for _, key in ipairs({ "TOYBOX_MOUSEWHEEL_PAGING_HELP", "TUTORIAL_VOICE" }) do
      local f = tip:Show(nil, { text = UI45[key][1] })
      assert.are.equal(UI45[key][2], f.Text:GetText())
      assert.are.equal(UI45[key][1], f.info.text)
      tip.framePool:Release(f)
    end
  end)

  it("a new PLATE_KEYS tile renders Japanese and the glow box is re-measured; a plate word outside the list stays",
    function()
      local plate = CreateFrame("Frame", "HelpPlateTooltip")
      plate.Text = Stub.fontString("")
      function plate:SetHeight(h) self.height = h end
      function plate:GetHeight() return self.height end
      function plate:Init(_, text)
        self.Text:SetText(text)
        self:SetHeight(self.Text:GetHeight() + 30)
      end
      _G.HelpPlateTooltip = plate
      W = H.loadChunks(FILES)
      H.uiSetup(W, UI45)
      W.HelpTips.init()
      plate:Init({}, UI45.TRANSMOG_HELP_2[1], "DOWN") -- HelpPlateTileMixin:OnEnter
      assert.are.equal(UI45.TRANSMOG_HELP_2[2], plate.Text:GetText())
      assert.are.equal(plate.Text:GetHeight() + 30, plate:GetHeight())
      plate:Init({}, UI45.TOYBOX_MOUSEWHEEL_PAGING_HELP[1]) -- a callout key, not a plate key
      assert.are.equal(UI45.TOYBOX_MOUSEWHEEL_PAGING_HELP[1], plate.Text:GetText())
    end)
end)

-- the tutorial manager's pointer arrows
-- (blizzard_tutorialmanager/blizzard_tutorialpointerframe.lua:47–138).
-- Show takes a pooled frame, writes Content.Text:SetText(content), sizes Content from the text (width
-- min(GetStringWidth(), overrideWidth or 200) + 40, height GetHeight() + 40), stores it in InUseFrames[NextID] and
-- increments NextID.
describe("UI/HelpTips: the tutorial pointer arrows", function()
  local W, pointers
  local UI30 = {
    NPEV2_SELECT_TALENTS_TAB = { "Select the |cFF00FFFFTalents|r Tab", "|cFF00FFFFタレント|rタブを選択しましょう" },
    TALENT_MICRO_BUTTON_UNSPENT_TALENTS = { "You have unspent Talent points.", "未使用のタレントポイントがあります。" },
    RAID = { "Raid", "レイド" }, -- a dictionary word that is no pointer key
  }

  local function stringWidth(fs)
    local w = 0
    for ch in (fs.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      w = w + (#ch == 1 and 6 or 13)
    end
    return w
  end

  local function installPointers()
    local p = { NextID = 1, InUseFrames = {}, FramePool = {}, FrameCount = 0 }
    function p:Show(content, _direction, anchorFrame, _x, _y, _rel, _backup, overrideWidth)
      assert(anchorFrame, "TutorialPointerFrame:Show - Invalid Anchor Frame")
      local frame = table.remove(self.FramePool)
      if not frame then
        self.FrameCount = self.FrameCount + 1
        frame = CreateFrame("Frame", "TutorialPointerFrame_" .. self.FrameCount)
        frame.Content = CreateFrame("Frame")
        frame.Content.Text = Stub.fontString("")
        frame.Content.Text.GetStringWidth = stringWidth
        frame.Content.SetHeight = function(box, h) box.height = h end
        frame.Content.SetWidth = function(box, w) box.width = w end
      end
      frame.Content.Text:SetText(content)
      local maxWidth = overrideWidth or 200
      frame.Content.Text:SetWidth(maxWidth)
      local contentWidth = frame.Content.Text:GetStringWidth()
      if contentWidth > maxWidth then contentWidth = maxWidth end
      frame.Content:SetHeight(frame.Content.Text:GetHeight() + 40)
      frame.Content:SetWidth(contentWidth + 40)
      frame:Show()
      local id = self.NextID
      self.InUseFrames[id] = frame
      self.NextID = self.NextID + 1
      return id
    end
    function p:Hide(id)
      local frame = self.InUseFrames[id]
      if frame then self.InUseFrames[id] = nil; frame:Hide(); self.FramePool[#self.FramePool + 1] = frame end
    end
    _G.TutorialPointerFrame = p
    return p
  end

  local function sized(frame, maxWidth)
    local text = frame.Content.Text
    local w = text:GetStringWidth()
    if w > maxWidth then w = maxWidth end
    assert.are.equal(w + 40, frame.Content.width)
    assert.are.equal(text:GetHeight() + 40, frame.Content.height)
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    installHelpTip()
    pointers = installPointers()
    W = H.loadChunks(FILES)
    H.uiSetup(W, UI30)
  end)

  after_each(function()
    H.uiTeardown(); _G.HelpTip, _G.HelpTipTemplateMixin, _G.TutorialPointerFrame = nil, nil, nil
  end)

  it("a pointer key is Japanese and its box is sized to the Japanese; Alt restores the English and its size",
    function()
      assert.is_true(W.HelpTips.init())
      local id = pointers:Show(_G.NPEV2_SELECT_TALENTS_TAB, "DOWN", {}, 0, -10, nil, "DOWN")
      local frame = pointers.InUseFrames[id]
      assert.are.equal(UI30.NPEV2_SELECT_TALENTS_TAB[2], frame.Content.Text:GetText())
      assert.are.equal(W.Font.PATH, (frame.Content.Text:GetFont()))
      sized(frame, 200)
      Stub.keys.alt = true; W.Modifier.refresh()
      assert.are.equal(UI30.NPEV2_SELECT_TALENTS_TAB[1], frame.Content.Text:GetText())
      sized(frame, 200)
      Stub.keys.alt = false; W.Modifier.refresh()
      assert.are.equal(UI30.NPEV2_SELECT_TALENTS_TAB[2], frame.Content.Text:GetText())
    end)

  it("the call's overrideWidth is the width the Japanese is measured against", function()
    W.HelpTips.init()
    local id = pointers:Show(_G.TALENT_MICRO_BUTTON_UNSPENT_TALENTS, "DOWN", {}, 0, 10, nil, "DOWN", 120)
    local frame = pointers.InUseFrames[id]
    assert.are.equal(UI30.TALENT_MICRO_BUTTON_UNSPENT_TALENTS[2], frame.Content.Text:GetText())
    sized(frame, 120)
  end)

  it("a pooled frame reused for other text keeps the client's text; a dictionary word outside the list too",
    function()
      W.HelpTips.init()
      local id = pointers:Show(_G.NPEV2_SELECT_TALENTS_TAB, "DOWN", {}, 0, 0)
      local frame = pointers.InUseFrames[id]
      pointers:Hide(id)
      local id2 = pointers:Show("Some NPE text", "UP", {}, 0, 0)
      assert.are.equal(frame, pointers.InUseFrames[id2])
      assert.are.equal("Some NPE text", frame.Content.Text:GetText())
      assert.are_not.equal(W.Font.PATH, (frame.Content.Text:GetFont()))
      local id3 = pointers:Show(_G.RAID, "UP", {}, 0, 0)
      assert.are.equal("Raid", pointers.InUseFrames[id3].Content.Text:GetText())
    end)

  it("a frame whose text is not this call's content is left alone (a Show that stored nothing)", function()
    W.HelpTips.init()
    local id = pointers:Show(_G.RAID, "DOWN", {}, 0, 0)
    local frame = pointers.InUseFrames[id]
    frame.Content.Text:SetText(_G.NPEV2_SELECT_TALENTS_TAB) -- as if a key had been shown on it earlier
    assert.are.equal(0, W.HelpTips.onPointer(pointers, "Some other content"))
    assert.are.equal(_G.NPEV2_SELECT_TALENTS_TAB, frame.Content.Text:GetText())
  end)

  it("no TutorialPointerFrame: the pointer part is a no-op, HelpTips.init still hooks HelpTip", function()
    _G.TutorialPointerFrame = nil
    local W2 = H.loadChunks(FILES)
    H.uiSetup(W2, UI30)
    assert.is_true(W2.HelpTips.init())
    assert.are.equal(0, W2.HelpTips.onPointer(nil))
    assert.are.equal(0, W2.HelpTips.onPointer({ NextID = 2, InUseFrames = {} }))
  end)
end)
