-- Every window module declares the widgets no record may take, and Labels refuses them on any surface:
-- a declared widget holding a dictionary English is never recorded and its text never changes. Each window's own spec
-- also drives its writers with its never-touch widgets holding dictionary words.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local MODULES = { "Character", "Reputation", "Skills", "SpellBook", "Talents", "Trainer", "GossipChrome",
  "Merchant", "Bank", "Bags", "Mail", "Friends", "Raid", "MicroMenu" }

describe("never-touch widgets", function()
  local WFJ

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    local files = {}
    for i, f in ipairs(H.UI_FILES) do files[i] = f end
    for _, m in ipairs(MODULES) do files[#files + 1] = "UI/" .. m .. ".lua" end
    WFJ = H.loadChunks(files)
    H.uiSetup(WFJ, { ACCEPT = { "Accept", "承諾" }, SEND_LABEL = { "Send", "送信" } })
  end)

  after_each(H.uiTeardown)

  it("every window module declares a NEVER_TOUCH list of global names or dotted paths", function()
    for _, m in ipairs(MODULES) do
      local list = WFJ[m].NEVER_TOUCH
      assert.is_table(list, m)
      for _, name in ipairs(list) do
        assert.is_truthy(type(name) == "string" and name:find("^[%a_][%w_]*[%w_.]*$"), m .. ": " .. tostring(name))
      end
    end
  end)

  it("a declared widget, a button or a dotted child, is refused on any surface and its text never changes", function()
    local edit = Stub.namedFontString("SendMailNameEditBox", "Accept")
    local button = Stub.button("PlayerTalentFrameTab1", "Send")
    _G.OpenMailSender = { Name = Stub.fontString("Accept") }
    assert.are.equal(3, WFJ.Labels.forbidNames({ "SendMailNameEditBox", "PlayerTalentFrameTab1", "OpenMailSender.Name",
      "NotAWidgetOnThisClient" }))
    for i, w in ipairs({ edit, button, _G.OpenMailSender.Name }) do
      assert.are.equal(0, WFJ.Labels.show("any.surface", "k" .. i, w))
      assert.are.equal(0, WFJ.Labels.show("help", "L" .. i, w))
    end
    assert.are.equal(0, WFJ.SurfaceState.count("any.surface"))
    assert.are.equal("Accept", edit:GetText())
    assert.are.equal("Send", button:GetText())
    assert.are.equal("Accept", _G.OpenMailSender.Name:GetText())
    _G.OpenMailSender = nil
  end)

  it("every list a module declares resolves through the same path Main uses", function()
    for _, m in ipairs(MODULES) do
      assert.has_no.errors(function() WFJ.Labels.forbidNames(WFJ[m].NEVER_TOUCH) end, m)
    end
  end)
end)
