local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

-- The tutorial popup on Forever. A stub of the mainline
-- blizzard_framexml/mainline/tutorialframe.lua|xml:
-- TutorialFrame with its title and body FontStrings, the Okay button (CLOSE) and the Prev / Next buttons with their
-- unnamed PREV / NEXT FontStrings (xml:110, 126–140, 180–240); TutorialFrame_Update clears the body
-- (TutorialFrame_ClearTextures: SetFontObject(GameFontNormal), SetText("")), draws only a DISPLAY_DATA id, looks up
-- TUTORIAL<id>[_<RACE>][_<CLASS>] / TUTORIAL_TITLE<id>… and writes them, then shows the frame (:359–606).
local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "UI/Tutorial.lua"

local UI = {
  TUTORIAL_TITLE17 = { "Replying to Whispers", "ささやきへの返信" },
  TUTORIAL17 = { "You can reply to that player by hitting the R key and then typing a message.",
    "Rキーを押してからメッセージを入力すると、そのプレイヤーに返信できます。" },
  TUTORIAL_TITLE27 = { "Fatigue", "疲労" },
  TUTORIAL27 = { "If you stray into deep and uncharted waters, you will see a Fatigue bar.",
    "深い未知の海域に迷い込むと、疲労バーが表示されます。" },
  TUTORIAL_TITLE28 = { "Swimming", "水泳" }, -- also a spell's name: an owned key (UIStrings.OWN)
  TUTORIAL46 = { "You have joined a raid group: a group with an increased limit of 40 members, though usually 10 or "
    .. "25. Raid groups are necessary to enter the most challenging dungeons.",
    "レイドグループに参加しました。レイドグループは人数の上限が引き上げられたグループで、上限は40人ですが、通常は10人か"
    .. "25人です。最も手ごわいダンジョンに入るにはレイドグループが必要です。" },
  TUTORIAL_TITLE46 = { "Raid Groups", "レイドグループ" },
  CLOSE = { "Close", "閉じる" }, PREV = { "Prev", "前へ" }, NEXT = { "Next", "次へ" },
  RAID = { "Raid", "レイド" }, -- a dictionary word that is no tutorial key
}
-- English with no dictionary row (a live tutorial the batch has not drafted)
local UNTRANSLATED = { TUTORIAL28 = "Swimming is much like walking." }

local LIVE = { [17] = true, [18] = true, [22] = true, [27] = true, [28] = true, [37] = true, [46] = true, [52] = true }
local GAME_FONT_NORMAL = { font = { path = "Fonts\\FRIZQT__.TTF", size = 12, flags = "" } }

local function build()
  local frame = CreateFrame("Frame", "TutorialFrame")
  Stub.namedFontString("TutorialFrameTitle", "")
  Stub.namedFontString("TutorialFrameText", "")
  _G.TutorialFrameTextScrollFrame = CreateFrame("ScrollFrame", "TutorialFrameTextScrollFrame")
  local child = CreateFrame("Frame", "TutorialFrameTextScrollChildFrame") -- <Size x="1" y="1"/> (xml:135–136)
  child.height = 1
  function child:SetHeight(h) self.height = h end
  function child:GetHeight() return self.height end
  _G.TutorialFrameTextScrollChildFrame = child
  _G.TutorialFrameOkayButton = Stub.button("TutorialFrameOkayButton", _G.CLOSE)
  local prev = CreateFrame("Button", "TutorialFramePrevButton")
  prev:addRegion(Stub.fontString(_G.PREV))
  _G.TutorialFramePrevButton = prev
  local nxt = CreateFrame("Button", "TutorialFrameNextButton")
  nxt:addRegion(Stub.fontString(_G.NEXT))
  _G.TutorialFrameNextButton = nxt
  _G.TutorialFrame = frame
  -- the client's update (tutorialframe.lua:359–606), text part
  _G.TutorialFrame_Update = function(id)
    if not LIVE[id] then return end
    _G.TutorialFrameText:SetFontObject(GAME_FONT_NORMAL)
    _G.TutorialFrameText:SetText("")
    frame.id = id
    local text = _G["TUTORIAL" .. id .. "_HUMAN_WARRIOR"] or _G["TUTORIAL" .. id .. "_HUMAN"]
      or _G["TUTORIAL" .. id .. "_WARRIOR"] or _G["TUTORIAL" .. id]
    local title = _G["TUTORIAL_TITLE" .. id .. "_HUMAN_WARRIOR"] or _G["TUTORIAL_TITLE" .. id .. "_HUMAN"]
      or _G["TUTORIAL_TITLE" .. id .. "_WARRIOR"] or _G["TUTORIAL_TITLE" .. id]
    if text then _G.TutorialFrameText:SetText(text) end
    if title then _G.TutorialFrameTitle:SetText(title) end
    frame:Show()
  end
  return frame
end

local GLOBALS = { "TutorialFrame", "TutorialFrameTitle", "TutorialFrameText", "TutorialFrameOkayButton",
  "TutorialFramePrevButton", "TutorialFrameNextButton", "TutorialFrame_Update", "TutorialFrameTextScrollFrame",
  "TutorialFrameTextScrollChildFrame" }

local function records(WFJ)
  local n = 0
  for _ in pairs(WFJ.SurfaceState.records("tutorial")) do n = n + 1 end
  return n
end

describe("UI/Tutorial: the tutorial popup on Forever", function()
  local WFJ, frame

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    for k, v in pairs(UNTRANSLATED) do _G[k] = v end
    frame = build()
  end)

  after_each(function()
    H.uiTeardown()
    for _, g in ipairs(GLOBALS) do _G[g] = nil end
    for k in pairs(UNTRANSLATED) do _G[k] = nil end
  end)

  it("a live tutorial with shipped rows shows its title and body in Japanese, in the bundled font", function()
    assert.is_true(WFJ.Tutorial.init())
    _G.TutorialFrame_Update(17)
    assert.are.equal("ささやきへの返信", _G.TutorialFrameTitle:GetText())
    assert.are.equal(UI.TUTORIAL17[2], _G.TutorialFrameText:GetText())
    assert.are.equal(WFJ.Font.PATH, (_G.TutorialFrameTitle:GetFont()))
    assert.are.equal(WFJ.Font.PATH, (_G.TutorialFrameText:GetFont()))
  end)

  it("a tutorial with no row keeps the client's text and font: no write", function()
    WFJ.Tutorial.init()
    _G.TUTORIAL_TITLE28 = "Swimming (no row)" -- English neither line has a row for
    _G.TutorialFrame_Update(28)
    assert.are.equal("Swimming (no row)", _G.TutorialFrameTitle:GetText())
    assert.are.equal("Swimming is much like walking.", _G.TutorialFrameText:GetText())
    assert.are.equal(0, _G.TutorialFrameTitle.calls.addonSetText + _G.TutorialFrameText.calls.addonSetText)
    assert.are.equal(0, _G.TutorialFrameTitle.calls.addonSetFont + _G.TutorialFrameText.calls.addonSetFont)
  end)

  it("the Close button and the Prev / Next labels are Japanese; hiding the popup releases the surface",
    function()
      WFJ.Tutorial.init()
      _G.TutorialFrame_Update(17)
      assert.are.equal("閉じる", _G.TutorialFrameOkayButton:GetText())
      assert.are.equal("前へ", (select(1, _G.TutorialFramePrevButton:GetRegions())):GetText())
      assert.are.equal("次へ", (select(1, _G.TutorialFrameNextButton:GetRegions())):GetText())
      assert.is_true(records(WFJ) > 0)
      frame:Hide()
      assert.are.equal(0, records(WFJ))
      assert.are.equal("Close", _G.TutorialFrameOkayButton:GetText())
      assert.are.equal("Prev", (select(1, _G.TutorialFramePrevButton:GetRegions())):GetText())
    end)

  it("Alt, the interface area and the master switch each restore the client's text and font", function()
    WFJ.Tutorial.init()
    _G.TutorialFrame_Update(17)
    local function english()
      assert.are.equal("Replying to Whispers", _G.TutorialFrameTitle:GetText())
      assert.are.equal(UI.TUTORIAL17[1], _G.TutorialFrameText:GetText())
      assert.are.equal("Close", _G.TutorialFrameOkayButton:GetText())
      assert.are_not.equal(WFJ.Font.PATH, (_G.TutorialFrameText:GetFont()))
    end
    local function japanese()
      assert.are.equal("ささやきへの返信", _G.TutorialFrameTitle:GetText())
      assert.are.equal(UI.TUTORIAL17[2], _G.TutorialFrameText:GetText())
      assert.are.equal("閉じる", _G.TutorialFrameOkayButton:GetText())
      assert.are.equal(WFJ.Font.PATH, (_G.TutorialFrameText:GetFont()))
    end
    Stub.keys.alt = true; WFJ.Modifier.refresh(); english()
    Stub.keys.alt = false; WFJ.Modifier.refresh(); japanese()
    WFJ.State.setArea("ui", false); english()
    WFJ.State.setArea("ui", true); japanese()
    WFJ.State.setEnabled(false); english()
    WFJ.State.setEnabled(true); japanese()
  end)

  it("in game: with the popup holding the keyboard no modifier event arrives; its OnUpdate re-polls Alt", function()
    WFJ.Tutorial.init()
    _G.TutorialFrame_Update(17)
    assert.is_function(frame.scripts.OnUpdate)
    Stub.keys.alt = true -- no Modifier.refresh(): MODIFIER_STATE_CHANGED never came
    assert.are.equal("ささやきへの返信", _G.TutorialFrameTitle:GetText())
    frame.scripts.OnUpdate(frame, 0.016)
    assert.are.equal("Replying to Whispers", _G.TutorialFrameTitle:GetText())
    Stub.keys.alt = false
    frame.scripts.OnUpdate(frame, 0.016)
    assert.are.equal("ささやきへの返信", _G.TutorialFrameTitle:GetText())
  end)

  it("a second tutorial while shown leaves no record from the first", function()
    WFJ.Tutorial.init()
    _G.TutorialFrame_Update(17)
    _G.TutorialFrame_Update(28) -- Next: a tutorial whose body has no row
    assert.are.equal("水泳", _G.TutorialFrameTitle:GetText())
    assert.are.equal("Swimming is much like walking.", _G.TutorialFrameText:GetText())
    assert.are_not.equal(WFJ.Font.PATH, (_G.TutorialFrameText:GetFont())) -- the first tutorial's font is undone
    for key, rec in pairs(WFJ.SurfaceState.records("tutorial")) do
      assert.are_not.equal(_G.TutorialFrameText, rec.fs, key) -- no body record: 28's body is English
      if key == "title" then assert.are.equal("水泳", rec.applied) end -- the title record is 28's own
    end
    assert.are.equal("閉じる", _G.TutorialFrameOkayButton:GetText()) -- the buttons stay Japanese
    assert.are.equal("前へ", (select(1, _G.TutorialFramePrevButton:GetRegions())):GetText())
    assert.are.equal("次へ", (select(1, _G.TutorialFrameNextButton:GetRegions())):GetText())
    _G.TutorialFrame_Update(27) -- and on to one with rows
    assert.are.equal("疲労", _G.TutorialFrameTitle:GetText())
    assert.are.equal(UI.TUTORIAL27[2], _G.TutorialFrameText:GetText())
  end)

  it("the scroll child takes the Japanese body's height, so a long body scrolls; the client's 1 comes back",
    function()
      WFJ.Tutorial.init()
      local child = _G.TutorialFrameTextScrollChildFrame
      _G.TutorialFrame_Update(46)
      assert.are.equal(UI.TUTORIAL46[2], _G.TutorialFrameText:GetText())
      assert.are.equal(_G.TutorialFrameText:GetHeight(), child:GetHeight())
      assert.is_true(child:GetHeight() > 1)
      Stub.keys.alt = true; WFJ.Modifier.refresh() -- the English: the child follows it
      assert.are.equal(_G.TutorialFrameText:GetHeight(), child:GetHeight())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      _G.TUTORIAL28 = "Swimming is much like walking."
      _G.TutorialFrame_Update(28) -- a body with no row: the client's own scroll child
      assert.are.equal(1, child:GetHeight())
      _G.TutorialFrame_Update(46)
      frame:Hide()
      assert.are.equal(1, child:GetHeight())
    end)

  it("an owned title answers only the popup: an unrestricted match of \"Swimming\" finds nothing", function()
    assert.is_nil((WFJ.UIIndex:match("Swimming")))
    assert.are.equal("TUTORIAL_TITLE28", (WFJ.UIIndex:matchOnly("Swimming", { "TUTORIAL_TITLE28" })))
  end)

  it("a body that is some other dictionary word is left alone (only the tutorial keys)", function()
    WFJ.Tutorial.init()
    _G.TUTORIAL17 = UI.RAID[1]
    _G.TutorialFrame_Update(17)
    assert.are.equal("Raid", _G.TutorialFrameText:GetText())
  end)

  it("no TutorialFrame_Update or no TutorialFrame: init returns false, no error, and Compat lists them",
    function()
      _G.TutorialFrame_Update = nil
      local W = H.loadChunks(FILES)
      H.uiSetup(W, UI)
      assert.is_false(W.Tutorial.init())
      local missing = table.concat(W.Compat.unresolved(), " ")
      assert.truthy(missing:find("tutorial.update", 1, true))
      _G.TutorialFrame = nil
      local W2 = H.loadChunks(FILES)
      H.uiSetup(W2, UI)
      assert.is_false(W2.Tutorial.init())
      assert.truthy(table.concat(W2.Compat.unresolved(), " "):find("tutorial.frame", 1, true))
    end)

  it("init hooks once", function()
    assert.is_true(WFJ.Tutorial.init())
    assert.is_false(WFJ.Tutorial.init())
    assert.are.equal(1, #Stub.hooks.TutorialFrame_Update)
  end)
end)
