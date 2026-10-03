-- UI/Subtitles.lua over a SubtitlesFrame replayed from Forever blizzard_subtitles/blizzard_subtitles.lua:
-- OnEvent SHOW_SUBTITLE (:85–97) → AddSubtitle (:37–54: the first hidden line, or every line scrolled up one and the
-- last one written), HideSubtitles (:72–79). The message is a BroadcastText row; the speaker's name stays English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Subtitles.lua"

local UI = {
  -- client-table rows (fingerprints: no global; ADR-042)
  ["BroadcastText:1001"] = { "The Horde will prevail.", "ホードは勝利する。" },
  ["BroadcastText:1002"] = { "For the Alliance!", "アライアンスのために！" },
  ["BroadcastText:1003"] = { "Close", "近い" }, -- a row whose English a speaker may be named
  CLOSE = { "Close", "閉じる" }, -- a dictionary word that is no BroadcastText row
}
local LINES = 3 -- Subtitle1 … (blizzard_subtitles.xml:12, parentArray "Subtitles")

local function installSubtitles()
  _G.SUBTITLE_FORMAT = "%s: %s"
  local frame = CreateFrame("Frame", "SubtitlesFrame")
  frame.Subtitles = {}
  for i = 1, LINES do
    local fs = Stub.fontString("")
    fs.shown = false
    frame.Subtitles[i] = fs
  end
  function frame.AddSubtitle(self, body) -- lua:37–54
    local fs
    for i = 1, #self.Subtitles do
      if not self.Subtitles[i]:IsShown() then
        fs = self.Subtitles[i]
        break
      end
    end
    if not fs then
      for i = 1, #self.Subtitles - 1 do self.Subtitles[i]:SetText(self.Subtitles[i + 1]:GetText()) end
      fs = self.Subtitles[#self.Subtitles]
    end
    fs:SetText(body)
    fs:Show()
  end
  function frame.HideSubtitles(self) -- lua:72–79
    for i = 1, #self.Subtitles do
      self.Subtitles[i]:SetText("")
      self.Subtitles[i]:Hide()
    end
  end
  function frame.OnEvent(self, message, sender) -- SHOW_SUBTITLE, lua:85–97
    self:AddSubtitle(sender and _G.SUBTITLE_FORMAT:format(sender, message) or message)
  end
  Stub.loadedAddons.Blizzard_Subtitles = true
  return frame
end

describe("cinematic subtitles on Forever", function()
  local WFJ

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function line(i) return _G.SubtitlesFrame.Subtitles[i]:GetText() end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    installSubtitles()
    assert.is_true(WFJ.Subtitles.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.SubtitlesFrame, _G.SUBTITLE_FORMAT = nil, nil
  end)

  it("a message alone and a message after its speaker's name are BroadcastText rows' Japanese; the name stays;"
    .. " Alt shows English", function()
    local f = _G.SubtitlesFrame
    f:OnEvent("The Horde will prevail.")
    f:OnEvent("For the Alliance!", "Varian Wrynn")
    assert.are.equal("ホードは勝利する。", line(1))
    assert.are.equal("Varian Wrynn: アライアンスのために！", line(2))
    alt(true)
    assert.are.equal("The Horde will prevail.", line(1))
    assert.are.equal("Varian Wrynn: For the Alliance!", line(2))
    alt(false)
    assert.are.equal("Varian Wrynn: アライアンスのために！", line(2))
  end)

  it("a line that is no BroadcastText row stays English, a dictionary word too; a speaker named like a row keeps"
    .. " the name", function()
    local f = _G.SubtitlesFrame
    f:OnEvent("Something nobody translated.")
    assert.are.equal("Something nobody translated.", line(1))
    f:OnEvent("Something nobody translated.", "Close")
    assert.are.equal("Close: Something nobody translated.", line(2))
    f:AddSubtitle("Close") -- CLOSE is a dictionary word; only its BroadcastText row may match here
    assert.are.equal("近い", line(3))
  end)

  it("lines scrolled up keep Japanese with their own English under Alt", function()
    local f = _G.SubtitlesFrame
    f:OnEvent("The Horde will prevail.")
    f:OnEvent("For the Alliance!", "Varian Wrynn")
    f:OnEvent("Something nobody translated.")
    f:OnEvent("The Horde will prevail.", "Thrall") -- all three lines shown: every line scrolls up one
    assert.are.equal("Varian Wrynn: アライアンスのために！", line(1))
    assert.are.equal("Something nobody translated.", line(2))
    assert.are.equal("Thrall: ホードは勝利する。", line(3))
    alt(true)
    assert.are.equal("Varian Wrynn: For the Alliance!", line(1))
    assert.are.equal("Something nobody translated.", line(2))
    assert.are.equal("Thrall: The Horde will prevail.", line(3))
    alt(false)
    assert.are.equal("Varian Wrynn: アライアンスのために！", line(1))
  end)

  it("HideSubtitles empties the lines and forgets the records: Alt writes nothing back", function()
    local f = _G.SubtitlesFrame
    f:OnEvent("The Horde will prevail.")
    f:HideSubtitles()
    assert.are.equal("", line(1))
    alt(true)
    assert.are.equal("", line(1))
    alt(false)
    f:OnEvent("For the Alliance!")
    assert.are.equal("アライアンスのために！", line(1))
  end)

  it("hooks install once; no frame or a frame of the wrong shape sets nothing up with no error", function()
    assert.is_false(WFJ.Subtitles.init())
    assert.are.equal(1, #Stub.hooks["SubtitlesFrame:AddSubtitle"])
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    _G.SubtitlesFrame = nil
    assert.has_no.errors(function() assert.is_false(WFJ.Subtitles.init()) end)
    _G.SubtitlesFrame = { AddSubtitle = "text" }
    assert.has_no.errors(function() assert.is_false(WFJ.Subtitles.init()) end)
    _G.SubtitlesFrame = CreateFrame("Frame", "SubtitlesFrame")
    _G.SubtitlesFrame.AddSubtitle = function() end
    _G.SubtitlesFrame.Subtitles = "lines"
    assert.has_no.errors(function()
      assert.is_true(WFJ.Subtitles.setup())
      _G.SubtitlesFrame:AddSubtitle("The Horde will prevail.")
    end)
  end)
end)
