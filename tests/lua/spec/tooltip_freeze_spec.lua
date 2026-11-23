-- The frozen tooltip: a key press draws a copy of the tooltip showing now, in its place, and the copy's Japanese
-- lines take word cards from the records the addon kept for the tooltip's lines.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Data.lua", "Core/UIStringKeys.lua", "Core/UIStrings.lua",
  "Core/Readings.lua", "Core/State.lua", "Core/Normalize.lua", "Core/Hash.lua", "Core/Names.lua", "Core/Settings.lua",
  "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Compat.lua", "Core/Words.lua",
  "UI/Font.lua", "UI/Readings.lua", "UI/Render.lua", "UI/OptionsText.lua", "UI/OptionsWidgets.lua",
  "UI/KeyCapture.lua", "UI/TooltipFreeze.lua" }

local HEARTH = "ホームに設定した場所へ戻ります。"
local FROST = "対象に|cffffffff12|rのFrostダメージを与えます。"
local FROST_PLAIN = "対象に12のFrostダメージを与えます。"

local function isBoundary(text, i)
  if i == #text + 1 then return true end
  local c = text:byte(i)
  return c ~= nil and (c < 0x80 or c >= 0xC0)
end

-- the span call as the client's: an escape sequence or a split character is fatal
local function spans(fs)
  function fs:CalculateScreenAreaFromCharacterSpan(a, b)
    local t = self.text
    if t:find("|", 1, true) then error("CRASH: escape sequence") end
    if not isBoundary(t, a) or not isBoundary(t, b) or b <= a then error(("CRASH: span %d..%d"):format(a, b)) end
    return { { left = a, bottom = 0, width = b - a, height = 14 } }
  end
end

local function extendFrames()
  local create = _G.CreateFrame
  _G.CreateFrame = function(...)
    local f = create(...)
    function f:SetAllPoints(target) self.allPoints = target or true end
    function f:GetParent() return self.parent end
    function f:SetParent(p) self.parent = p end
    function f:IsMouseOver() return self.mouseOver == true end
    function f:SetMouseMotionEnabled(v) self.motion = v end
    function f:SetPropagateMouseMotion(v) self.propagate = v end
    function f:SetMouseClickEnabled(v) self.clicks = v end
    function f:SetPropagateMouseClicks(v) self.propagateClicks = v end
    function f:SetFrameStrata(s) self.strata = s end
    function f:SetClampedToScreen(v) self.clamped = v end
    function f:EnableMouse(v) self.mouse = v end
    function f:SetScale(s) self.scale = s end
    function f:ClearAllPoints() self.point = nil end
    function f:SetShown(v) if v then self:Show() else self:Hide() end end
    function f:GetLeft() return self.left or 100 end
    function f:GetBottom() return self.bottom or 200 end
    function f:GetTop() return self.top or 500 end
    function f:GetWidth() return self.size and self.size[1] or 240 end
    function f:GetHeight() return self.size and self.size[2] or 300 end
    function f.GetEffectiveScale() return 1 end
    local createTexture = f.CreateTexture
    function f:CreateTexture(...)
      local t = createTexture(self, ...)
      function t.SetAllPoints() end
      function t.ClearAllPoints(tx) tx.point = nil end
      function t.Show(tx) tx.shown = true end
      function t.Hide(tx) tx.shown = false end
      return t
    end
    local createFontString = f.CreateFontString
    function f:CreateFontString(...)
      local fs = createFontString(self, ...)
      fs.parentFrame = self
      function fs.GetParent(line) return line.parentFrame end
      function fs.SetAlpha(line, a) line.alpha = a end
      function fs.GetStringWidth() return 40 end
      function fs.GetStringHeight() return 12 end
      spans(fs)
      return fs
    end
    return f
  end
end

-- a tooltip line as the client lays it out: a place, a width, a justification
local function place(fs, i)
  fs.shown = fs.text ~= ""
  function fs.GetLeft() return 110 end
  function fs.GetTop() return 490 - 16 * i end
  function fs.GetWidth() return 220 end
  function fs.GetJustifyH() return "LEFT" end
end

describe("UI/TooltipFreeze", function()
  local WFJ, F, tip

  local function write(frame, lines)
    frame:writeLines(lines)
    frame.shown = true
    local name = frame:GetName()
    for i = 1, #lines do
      place(_G[name .. "TextLeft" .. i], i)
      place(_G[name .. "TextRight" .. i], i)
    end
  end

  -- the addon's write of one line: the record the copy reads
  local function japanese(frame, i, key, kind, id, area)
    local fs = _G[frame:GetName() .. "TextLeft" .. i]
    WFJ.Render.show("tooltip." .. frame:GetName(), key, fs, fs:GetText(), area, kind, id)
    return fs
  end

  local function copy(n) return F.copies[n or 1] end
  local function line(n, i) return copy(n).lines[i] end
  local function coverOf(fs)
    for _, f in ipairs(Stub.frames) do if f.allPoints == fs then return f end end
    return nil
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    extendFrames()
    _G.UIParent = CreateFrame("Frame", "UIParent")
    _G.UISpecialFrames = {}
    _G.GetCursorPosition = function() return Stub.cursor[1], Stub.cursor[2] end
    Stub.cursor = { 0, 0 }
    for _, n in ipairs(Stub.TOOLTIP_FRAMES) do _G[n] = nil; Stub.tooltipFrame(n) end
    for _, n in ipairs(Stub.TOOLTIP_FRAMES) do _G[n].shown = false end
    WFJ = H.loadChunks(FILES)
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Data.add("reading", {
      ["item:6948"] = { description = "場所=ばしょ=7 戻ります=もどります=8" },
      ["spell:10"] = { description = "対象=たいしょう=1 与えます=あたえます=2" },
      ["ui:ITEM_SOULBOUND"] = { text = "魂=たましい=3" },
      ["item:7000"] = { description = "使います=つかいます=9" },
    })
    WFJ.Settings.load(nil, 1, {})
    local DATA = {
      ["spell.description"] = { [10] = { ja = FROST, status = "." } },
      ui = { ITEM_SOULBOUND = { ja = "魂に結びついている", status = "." } },
      ["item.description"] = {
        [6948] = { ja = HEARTH, status = "." },
        [7000] = { ja = "Hearthstoneを使います。", status = "." },
      },
    }

    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      showsEnglish = WFJ.Modifier.english,
      lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end,
      marker = function() return false end,
      -- Japanese names as Main wires them
      kindOff = function(kind) return kind == "name" and not WFJ.State.names end,
      names = function(ja, kind)
        if not WFJ.State.names or type(kind) ~= "string" then return ja end
        return WFJ.Names.inText(ja, false)
      end,
      name = WFJ.Names.shown,
    }))
    F, tip = WFJ.TooltipFreeze, _G.GameTooltip
  end)

  after_each(function() _G.UIParent, _G.GetCursorPosition, _G.UISpecialFrames = nil, nil, nil end)

  describe("the copy", function()
    it("stands where the tooltip stands, with its lines as they showed", function()
      write(tip, { "Hearthstone", { "Soulbound", "Misc" }, "Use: returns you." })
      _G.GameTooltipTextLeft1.color = { 1, 0.82, 0, 1 }
      WFJ_FreezeTooltip()
      local c = copy()
      assert.is_true(c.frame:IsShown())
      assert.are.same({ 240, 300 }, c.frame.size)
      assert.are.same({ "BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 100, 200 }, c.frame.point)
      assert.are.equal("Hearthstone", line(1, 1).fs:GetText())
      assert.are.same({ 1, 0.82, 0, 1 }, line(1, 1).fs.color)
      assert.are.equal(220, line(1, 1).fs.width)
      assert.are.same({ "TOPLEFT", c.frame, "TOPLEFT", 10, -26 }, line(1, 1).fs.point)
      -- a right-hand line is a line of its own
      local texts = {}
      for _, l in ipairs(c.lines) do texts[#texts + 1] = l.fs:GetText() end
      assert.are.same({ "Hearthstone", "Soulbound", "Misc", "Use: returns you." }, texts)
    end)

    it("copies a line with a texture or a link as written (a sell price's coins)", function()
      local price = "Sell Price: 1|TInterface\\MoneyFrame\\UI-SilverIcon:0|t"
      write(tip, { "Linen Cloth", price })
      F.toggle()
      assert.are.equal(price, line(1, 2).fs:GetText())
      assert.is_nil(line(1, 2).twin)
    end)

    it("does nothing with no tooltip showing", function()
      F.toggle()
      assert.is_nil(copy())
    end)

    it("closes on the key when no other tooltip shows, and on Esc", function()
      write(tip, { "Hearthstone" })
      F.toggle()
      assert.is_true(copy().frame:IsShown())
      F.toggle() -- the same tooltip still showing
      assert.is_nil(copy())
      F.toggle()
      tip.shown = false
      F.toggle() -- none showing
      assert.is_nil(copy())
      -- Esc: the client hides every frame named in UISpecialFrames
      F.toggle()
      tip.shown = true
      F.toggle()
      local frame = copy().frame
      assert.are.equal(frame:GetName(), _G.UISpecialFrames[1])
      frame:Hide()
      assert.is_nil(copy())
    end)

    it("becomes another tooltip's copy when the key is pressed over that one", function()
      write(tip, { "Hearthstone" })
      F.toggle()
      write(tip, { "Linen Cloth", "Trade Goods" })
      F.toggle()
      assert.are.equal("Linen Cloth", line(1, 1).fs:GetText())
      assert.are.equal(2, #copy().lines)
    end)

    it("closes on the key over the same tooltip even when its other lines have changed", function()
      write(tip, { "Frostbolt", "Cooldown remaining: 5 sec" })
      F.toggle()
      _G.GameTooltipTextLeft2.text = "Cooldown remaining: 4 sec" -- the client rewrites it under the mouse
      F.toggle()
      assert.is_nil(copy())
    end)

    it("copies a text the client will not let it read, and never reads it", function()
      write(tip, { "Frostbolt", "PROTECTED" })
      japanese(tip, 2, "desc", "spell.description", 10, "spells")
      _G.GameTooltipTextLeft2.text = "PROTECTED"
      local saved = WFJ.SurfaceState.secret
      WFJ.SurfaceState.secret = function(v) return v == "PROTECTED" end
      F.toggle()
      WFJ.SurfaceState.secret = saved
      assert.are.equal("PROTECTED", line(1, 2).fs:GetText()) -- passed on as it is
      assert.is_nil(line(1, 2).twin) -- and no words are looked for in it
      F.toggle()
      assert.is_nil(copy())
    end)

    it("takes its frames down again when drawing it fails", function()
      write(tip, { "Hearthstone", "Use: returns you." })
      local real = _G.GameTooltipTextLeft2.GetTextColor
      _G.GameTooltipTextLeft2.GetTextColor = function() error("boom") end
      assert.has_error(function() F.toggle() end)
      _G.GameTooltipTextLeft2.GetTextColor = real
      assert.is_nil(copy())
      assert.is_false(_G.WFJFrozenTooltip1:IsShown())
      F.toggle() -- and the key works again
      assert.is_true(copy().frame:IsShown())
    end)

    it("copies the comparison tooltips beside it, and they close with it", function()
      write(tip, { "New Sword" })
      write(_G.ShoppingTooltip1, { "Currently Equipped", "Old Sword" })
      _G.ShoppingTooltip1.left = 360
      F.toggle()
      assert.are.equal(2, #F.copies)
      assert.are.equal("Old Sword", line(2, 2).fs:GetText())
      assert.are.equal(360, copy(2).frame.point[4])
      copy(1).frame:Hide()
      assert.are.equal(0, #F.copies)
    end)
  end)

  describe("word cards", function()
    it("come from the line's own record: an item's description", function()
      write(tip, { "Hearthstone", "Use: returns you." })
      japanese(tip, 2, "desc", "item.description", 6948, "items")
      assert.are.equal(HEARTH, _G.GameTooltipTextLeft2:GetText())
      F.toggle()
      local l = line(1, 2)
      assert.are.equal(HEARTH, l.fs:GetText())
      local cover = coverOf(l.twin)
      assert.is_truthy(cover)
      assert.are.equal(2, #cover.spans)
      assert.are.equal("ばしょ", cover.spans[1].reading)
      assert.are.equal("item.description", cover.kind)
      assert.are.equal(6948, cover.id)
      assert.are.equal("tooltip.frozen", cover.surface)
      -- the name line has no record: no card
      assert.is_nil(line(1, 1).twin)
    end)

    it("a name line takes its name card: the reading and the English name", function()
      WFJ.Data.add("name", { [WFJ.Names.key("Hearthstone")] = "ハースストーン\tはーすすとーん" })
      WFJ.State.setNames(true)
      write(tip, { "Hearthstone", "Use: returns you." })
      japanese(tip, 1, "name.L1", "name", "Hearthstone", "items")
      assert.are.equal("ハースストーン", _G.GameTooltipTextLeft1:GetText())
      F.toggle()
      local cover = coverOf(line(1, 1).twin)
      assert.is_truthy(cover)
      assert.are.equal(1, #cover.spans)
      local sp = cover.spans[1]
      assert.is_true(sp.name)
      assert.are.equal("はーすすとーん", sp.reading)
      assert.are.equal("Hearthstone", sp.card.meaning)
    end)

    it("a name written into a line in Japanese takes its name card beside the line's words", function()
      WFJ.Data.add("name", { [WFJ.Names.key("Hearthstone")] = "ハースストーン\tはーすすとーん" })
      WFJ.State.setNames(true)
      write(tip, { "Hearthstone", "Use: Hearthstone." })
      japanese(tip, 2, "desc", "item.description", 7000, "items")
      assert.are.equal("ハースストーンを使います。", _G.GameTooltipTextLeft2:GetText())
      F.toggle()
      local cover = coverOf(line(1, 2).twin)
      assert.is_truthy(cover)
      assert.are.equal(2, #cover.spans)
      assert.is_true(cover.spans[1].name)
      assert.are.equal("Hearthstone", cover.spans[1].card.meaning)
      assert.are.equal("つかいます", cover.spans[2].reading)
    end)

    it("a window word (a ui line) takes its card too", function()
      write(tip, { "Hearthstone", "Soulbound" })
      japanese(tip, 2, "ui.L2", "ui", "ITEM_SOULBOUND", "ui")
      F.toggle()
      local cover = coverOf(line(1, 2).twin)
      assert.is_truthy(cover)
      assert.are.equal("たましい", cover.spans[1].reading)
    end)

    it("a line coloured in parts is measured without its colour codes and shown with them", function()
      write(tip, { "Frostbolt", "Deals damage." })
      japanese(tip, 2, "desc", "spell.description", 10, "spells")
      F.toggle()
      local l = line(1, 2)
      assert.are.equal(FROST, l.fs:GetText())
      assert.are.equal(FROST_PLAIN, l.twin:GetText())
      assert.are.equal(0, l.twin.alpha)
      local cover = coverOf(l.twin)
      assert.are.equal(2, #cover.spans)
      assert.are.equal("与えます", FROST_PLAIN:sub(cover.spans[2].first, cover.spans[2].last))
      -- measuring never touches the coloured text (the stub's span call is fatal on an escape)
      cover.scripts.OnEnter(cover)
      assert.are.equal(2, #cover.words)
    end)

    it("a line whose text the client has rewritten since takes none", function()
      write(tip, { "Hearthstone", "Use: returns you." })
      japanese(tip, 2, "desc", "item.description", 6948, "items")
      _G.GameTooltipTextLeft2.text = "Use: something else."
      F.toggle()
      assert.is_nil(line(1, 2).twin)
    end)

    it("none while English is showing or translation is off", function()
      write(tip, { "Hearthstone", "Use: returns you." })
      japanese(tip, 2, "desc", "item.description", 6948, "items")
      WFJ.State.setEnabled(false)
      F.toggle()
      assert.is_nil(line(1, 2).twin)
    end)

    it("a copy drops its cards when translation goes off or English shows, and takes them back", function()
      write(tip, { "Hearthstone", "Use: returns you." })
      japanese(tip, 2, "desc", "item.description", 6948, "items")
      F.toggle()
      local cover = coverOf(line(1, 2).twin)
      assert.is_table(cover.spans)
      WFJ.State.setEnabled(false)
      assert.is_nil(cover.spans)
      WFJ.State.setEnabled(true)
      assert.is_table(coverOf(line(1, 2).twin).spans)
      Stub.keys.alt = true
      WFJ.Modifier.refresh()
      assert.is_nil(coverOf(line(1, 2).twin).spans)
      Stub.keys.alt = false
      WFJ.Modifier.refresh()
      assert.is_table(coverOf(line(1, 2).twin).spans)
      assert.is_table(F.copies[1]) -- the copy itself stays
    end)

    it("the cards go when the copy closes", function()
      write(tip, { "Hearthstone", "Use: returns you." })
      japanese(tip, 2, "desc", "item.description", 6948, "items")
      F.toggle()
      local cover = coverOf(line(1, 2).twin)
      F.toggle()
      assert.is_nil(cover.spans)
      assert.is_false(cover:IsShown())
    end)

    it("in combat the copy freezes and closes, with no new cover and no error", function()
      write(tip, { "Hearthstone", "Use: returns you." })
      japanese(tip, 2, "desc", "item.description", 6948, "items")
      Stub.combat = true
      _G.InCombatLockdown = function() return true end
      local before = #Stub.frames
      F.toggle()
      assert.is_true(copy().frame:IsShown())
      assert.are.equal(HEARTH, line(1, 2).fs:GetText())
      for i = before + 1, #Stub.frames do assert.is_nil(Stub.frames[i].motion) end -- no cover made
      F.toggle()
      assert.is_nil(copy())
    end)
  end)

  describe("the first key", function()
    it("is not offered before the client says its bindings are in", function()
      local db = {}
      F.offerKey(db) -- a key reads as free until the saved bindings arrive
      assert.are.same({}, Stub.bindingCalls)
      assert.is_nil(db.freezeKeyOffered)
      F.bindingsLoaded(db)
      assert.is_true(db.freezeKeyOffered)
    end)

    it("is offered once: bound when free, and never asked again", function()
      local db = {}
      F.bindingsLoaded(db)
      assert.are.same({ { "SetBinding", "CTRL-F", "WFJ_FREEZE_TOOLTIP" }, { "SaveBindings", 2 } }, Stub.bindingCalls)
      assert.is_true(db.freezeKeyOffered)
      Stub.bindingCalls, Stub.bindings = {}, {}
      F.offerKey(db)
      assert.are.same({}, Stub.bindingCalls)
    end)

    it("is not bound over another action, and that is the one offer", function()
      local db = {}
      Stub.bindings["CTRL-F"] = "ACTIONBUTTON5"
      F.bindingsLoaded(db)
      assert.are.same({}, Stub.bindingCalls)
      assert.is_true(db.freezeKeyOffered)
    end)

    it("is not offered while Ctrl is the reveal key: Ctrl held would show the English", function()
      local db = {}
      WFJ.Settings.set("modifier", "lctrl")
      F.bindingsLoaded(db)
      assert.are.same({}, Stub.bindingCalls)
      assert.is_nil(db.freezeKeyOffered) -- asked again once the reveal key is another one
      WFJ.Settings.set("modifier", "alt")
      Stub.bindingCalls = {}
      F.offerKey(db)
      assert.is_true(db.freezeKeyOffered)
    end)

    it("waits for the end of combat", function()
      local db = {}
      Stub.combat = true
      F.bindingsLoaded(db)
      assert.is_nil(db.freezeKeyOffered)
      Stub.combat = false
      F.offerKey(db)
      assert.is_true(db.freezeKeyOffered)
    end)
  end)
end)
