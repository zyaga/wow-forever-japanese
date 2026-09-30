-- UI/ItemSocketing.lua over an ItemSocketingFrame replayed from
-- camelot blizzard_itemsocketingui/blizzard_itemsocketingui.xml (:128, :143–151, :406, :419) and .lua (:56–58,
-- :222–338), load-on-demand in both load orders. The socketed item's tooltip (its name) stays English.
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")

local UI = {
  ITEM_SOCKETING = { "Item Socketing", "ソケット装着" }, APPLY = { "Apply", "適用" },
  RED_GEM = { "Red", "赤" }, BLUE_GEM = { "Blue", "青" }, PRISMATIC_GEM = { "Prismatic", "プリズム" },
}

local function en(key) return _G[key] end

local function socket()
  local s = CreateFrame("Button")
  C.tree(s, { ["BracketFrame.ColorText"] = "" })
  return s
end

local function build()
  local frame = CreateFrame("Frame", "ItemSocketingFrame")
  frame:addRegion(Stub.fontString(en("ITEM_SOCKETING"))) -- the unnamed title FontString (xml:143–151)
  C.tree(frame, { ["SocketingContainer.ApplySocketsButton"] = { button = en("APPLY") } })
  local container = frame.SocketingContainer
  container.SocketFrames = { socket(), socket() }
  -- GenericItemSocketingFrameMixin:Update in colour-blind mode: _G[strupper(gemColor) .. "_GEM"] (lua:238–297)
  container.colors = { "Red", "Blue" }
  function container.Update(self)
    for i, s in ipairs(self.SocketFrames) do s.BracketFrame.ColorText.text = en(self.colors[i]:upper() .. "_GEM") end
  end
  Stub.namedFontString("ItemSocketingDescriptionTextLeft1", "Apply") -- the item tooltip: an item named "Apply"
  return frame
end

local function title(frame) return (frame:GetRegions()) end

C.suite(getfenv(1), {
  title = "the item socketing window on Forever", module = "ItemSocketing",
  file = "UI/ItemSocketing.lua", addon = "Blizzard_ItemSocketingUI", root = "ItemSocketingFrame", ui = UI,
  build = build, globals = { "ItemSocketingFrame", "ItemSocketingDescriptionTextLeft1" },
  cases = {
    { "the unnamed title and the apply button are Japanese; Alt shows English", function(frame, WFJ)
      frame:Show()
      assert.are.equal("ソケット装着", title(frame):GetText())
      assert.are.equal("適用", frame.SocketingContainer.ApplySocketsButton:GetText())
      C.alt(WFJ, true)
      assert.are.equal("Item Socketing", title(frame):GetText())
      C.alt(WFJ, false)
    end },
    { "the colour-blind socket words follow the container's Update, keyed by widget; hide releases them",
      function(frame)
        frame:Show()
        local container = frame.SocketingContainer
        container:Update()
        local a, b = container.SocketFrames[1].BracketFrame.ColorText, container.SocketFrames[2].BracketFrame.ColorText
        assert.are.equal("赤", a:GetText())
        assert.are.equal("青", b:GetText())
        container.colors = { "Prismatic", "Red" } -- another item: the same widgets, new words
        container:Update()
        assert.are.equal("プリズム", a:GetText())
        assert.are.equal("赤", b:GetText())
        frame:Hide()
        assert.are.equal("Prismatic", a:GetText())
      end },
  },
  name = function(frame, WFJ)
    frame:Show()
    local line = _G.ItemSocketingDescriptionTextLeft1
    assert.are.equal("Apply", line:GetText())
    assert.are.equal(0, WFJ.Labels.show("itemsocketing", "x", line))
    assert.is_true(C.unrecorded(WFJ, line))
  end,
  wrong = function(frame)
    frame.SocketingContainer.SocketFrames = "sockets"
    frame.SocketingContainer.ApplySocketsButton = 7
    return function(f) assert.are.equal("ソケット装着", title(f):GetText()) end
  end,
})
