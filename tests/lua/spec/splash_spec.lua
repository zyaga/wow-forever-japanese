-- What's New splash on Forever: UI/Splash.lua over a SplashFrame replayed from camelot
-- blizzard_splashframe/mainline/splashframe.lua (SetupFrame :50–86) and splashframe.xml:70, 147. The splash screen's
-- own text (client-table data) is never touched.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Splash.lua"

local UI = { SPLASH_BASE_HEADER = { "What's New", "新着情報" }, SPLASH_NEW_HEADER_SEASON = { "New Season!", "新シーズン！" },
  SPLASH_START_QUEST_NOW = { "Start Quest Now", "今すぐクエストを開始" }, CLOSE = { "Close", "閉じる" } }

local function en(key) return _G[key] end

local function installFrame()
  local f = CreateFrame("Frame", "SplashFrame")
  f.Header, f.Label = Stub.fontString(""), Stub.fontString("")
  f.BottomCloseButton = Stub.button(nil, en("CLOSE"))
  for _, k in ipairs({ "TopLeftFeature", "BottomLeftFeature", "RightFeature" }) do
    f[k] = { Title = Stub.fontString(""), Description = Stub.fontString("") }
  end
  f.RightFeature.StartQuestButton = { Text = Stub.fontString(en("SPLASH_START_QUEST_NOW")) }
  function f.SetupFrame(self, info)
    self.Header.text = info.season and en("SPLASH_NEW_HEADER_SEASON") or en("SPLASH_BASE_HEADER")
    self.Label.text = info.header
    self.TopLeftFeature.Title.text = info.title
    self:Show()
  end
  return f
end

describe("the What's New splash on Forever", function()
  local WFJ

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end

  after_each(function()
    H.uiTeardown()
    _G.SplashFrame = nil
  end)

  it("the header follows the screen type, the buttons are Japanese, the screen's own text is never touched", function()
    load()
    local f = installFrame()
    WFJ.Labels.forbidNames(WFJ.Splash.NEVER_TOUCH)
    assert.is_true(WFJ.Splash.init())
    assert.are.equal("閉じる", f.BottomCloseButton:GetText())
    assert.are.equal("今すぐクエストを開始", f.RightFeature.StartQuestButton.Text:GetText())
    f:SetupFrame({ header = "Close", title = "Close" }) -- splash text that is a dictionary word
    assert.are.equal("新着情報", f.Header:GetText())
    assert.are.equal("Close", f.Label:GetText())
    assert.are.equal("Close", f.TopLeftFeature.Title:GetText())
    assert.are.equal(0, WFJ.Labels.show("splash", "x", f.Label))
    f:SetupFrame({ season = true, header = "Season 2", title = "Arena" })
    assert.are.equal("新シーズン！", f.Header:GetText())
    assert.is_false(WFJ.Splash.init())
    assert.are.equal(1, #Stub.hooks["SplashFrame:SetupFrame"])
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    load()
    local f = installFrame()
    f.Header, f.RightFeature, f.SetupFrame = 1, "right", 2
    assert.has_no.errors(function() assert.is_true(WFJ.Splash.init()) end)
    assert.has_no.errors(function() f:Show() end)
    assert.are.equal("閉じる", f.BottomCloseButton:GetText())
  end)

  it("no SplashFrame: init is false with no error", function()
    load()
    assert.has_no.errors(function() assert.is_false(WFJ.Splash.init()) end)
  end)
end)
