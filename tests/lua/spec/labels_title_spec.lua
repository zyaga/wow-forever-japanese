-- Labels.title: a window title written with frame:SetTitle(text). The mainline PortraitFrame /
-- ButtonFrame templates write frame.TitleContainer.TitleText (blizzard_sharedxml/portraitframe.lua:11–13); the
-- helper shows it now and again after every SetTitle (one hook per frame). A frame may have neither.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  MERCHANT_BUYBACK = { "Buyback", "買い戻し" }, INBOX = { "Inbox", "受信箱" }, SENDMAIL = { "Send Mail", "メール送信" },
  RAID = { "Raid", "レイド" }, -- a word a name may happen to be
}

describe("Labels.title", function()
  local WFJ, SS, frame

  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end
  local function text() return frame.TitleContainer.TitleText:GetText() end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(H.UI_FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, UI)
    frame = CreateFrame("Frame")
    frame.name = "TitledFrame"
    frame.TitleContainer = { TitleText = Stub.fontString("") }
    function frame.SetTitle(self, t) self.TitleContainer.TitleText.text = t end
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
  end)

  it("shows the title already written, and again after each SetTitle; a second SetTitle keeps the Japanese",
    function()
      frame:SetTitle("Inbox")
      assert.are.equal(1, WFJ.Labels.title("t", frame))
      assert.are.equal("受信箱", text())
      assert.are.equal(WFJ.Font.PATH, (frame.TitleContainer.TitleText:GetFont()))
      frame:SetTitle("Send Mail")
      assert.are.equal("メール送信", text())
      frame:SetTitle("Send Mail") -- the client rewrites the same title
      assert.are.equal("メール送信", text())
      assert.is_table(SS.get("t", "title")) -- the default record key
      alt(true)
      assert.are.equal("Send Mail", text())
      alt(false)
      assert.are.equal("メール送信", text())
    end)

  it("hooks a frame once, however often it is asked, and returns the current title's 1 | 0", function()
    assert.are.equal(0, WFJ.Labels.title("t", frame)) -- an empty title
    frame:SetTitle("Inbox")
    assert.are.equal(1, WFJ.Labels.title("t", frame))
    assert.are.equal(1, WFJ.Labels.title("t", frame)) -- already ours
    assert.are.equal(1, #Stub.hooks["TitledFrame:SetTitle"])
  end)

  it("`only` keeps a title that can also be a name English, and drops the earlier record; `recKey` names it",
    function()
      local opts = { only = { "MERCHANT_BUYBACK" } }
      frame:SetTitle("Buyback")
      assert.are.equal(1, WFJ.Labels.title("t", frame, opts, "ui.title"))
      assert.are.equal("買い戻し", text())
      assert.is_table(SS.get("t", "ui.title"))
      frame:SetTitle("Raid") -- an NPC, a guild or a bag called "Raid": a dictionary word, not this title's
      assert.are.equal("Raid", text())
      assert.is_nil(SS.get("t", "ui.title"))
      frame:SetTitle("Buyback")
      assert.are.equal("買い戻し", text())
    end)

  it("a title that is no dictionary word stays as written", function()
    frame:SetTitle("Grimtooth")
    assert.are.equal(0, WFJ.Labels.title("t", frame))
    assert.are.equal("Grimtooth", text())
    assert.are.equal(0, frame.TitleContainer.TitleText.calls.SetText)
  end)

  it("a forbidden title widget is never written", function()
    WFJ.Labels.forbid(frame.TitleContainer.TitleText)
    frame:SetTitle("Inbox")
    assert.are.equal(0, WFJ.Labels.title("t", frame))
    frame:SetTitle("Send Mail")
    assert.are.equal("Send Mail", text())
  end)

  it("no TitleContainer: 0, and nothing is hooked", function()
    frame.TitleContainer = nil
    assert.are.equal(0, WFJ.Labels.title("t", frame))
    assert.is_nil(Stub.hooks["TitledFrame:SetTitle"])
    frame.TitleContainer = { TitleText = nil }
    assert.are.equal(0, WFJ.Labels.title("t", frame))
    assert.is_nil(Stub.hooks["TitledFrame:SetTitle"])
  end)

  it("a title widget without SetTitle is shown once and not hooked", function()
    frame.TitleContainer.TitleText.text = "Inbox"
    frame.SetTitle = nil
    assert.are.equal(1, WFJ.Labels.title("t", frame))
    assert.are.equal("受信箱", text())
    assert.is_nil(Stub.hooks["TitledFrame:SetTitle"])
  end)

  it("wrong types degrade to 0 with no error and no hook", function()
    assert.has_no.errors(function()
      assert.are.equal(0, WFJ.Labels.title("t", nil))
      assert.are.equal(0, WFJ.Labels.title("t", "moved"))
      assert.are.equal(0, WFJ.Labels.title("t", 7))
      frame.TitleContainer = "moved"
      assert.are.equal(0, WFJ.Labels.title("t", frame))
      frame.TitleContainer = { TitleText = "moved" }
      assert.are.equal(0, WFJ.Labels.title("t", frame))
      frame.TitleContainer = { TitleText = {} } -- a table that is no text widget
      frame.SetTitle = "moved"
      assert.are.equal(0, WFJ.Labels.title("t", frame))
    end)
    assert.is_nil(Stub.hooks["TitledFrame:SetTitle"])
    assert.are.equal(0, SS.count("t"))
  end)
end)
