-- The entries the client feeds the addon in combat, fed the client's secret values (H.secret: a stand-in that raises
-- on any use but holding it, asking issecretvalue about it and handing it back to a widget). Each entry must ask
-- before it compares, matches, indexes, joins or measures, and leave the client's text as it was. The unit tooltip,
-- the help tooltip walk, chat and NPC speech, combat text, nameplates and unit frames, the cast bar, UI error
-- messages, aura durations, the chat edit box header, the text watcher, fonts, the Collector and the voice speaker.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local S = H.secret

local function same(a, b) return rawequal(a, b) end

-- A fresh stub client with the UI files and `extra` loaded, `before()` run before the index is built, and the
-- client's secret test installed.
local function load(extra, ui, before)
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  Stub.installTooltipAPI()
  Stub.installScrollUtil()
  local files = {}
  for i, f in ipairs(H.UI_FILES) do files[i] = f end
  for _, f in ipairs(extra or {}) do files[#files + 1] = f end
  local WFJ = H.loadChunks(files)
  if before then before(WFJ) end
  H.uiSetup(WFJ, ui or {})
  _G.issecretvalue = H.issecretvalue
  return WFJ
end

local function teardown(names)
  H.uiTeardown()
  Stub.keys.alt = false
  _G.issecretvalue = nil
  for _, n in ipairs(names or {}) do _G[n] = nil end
end

describe("the secret stand-in", function()
  it("raises on every use but holding it and asking about it", function()
    local s, n = S(), S("number")
    assert.has_error(function() return s:find("x") end)
    assert.has_error(function() return string.find(s, "x") end)
    assert.has_error(function() return s .. "x" end)
    assert.has_error(function() return #s end)
    assert.has_error(function() return tostring(s) end)
    assert.has_error(function() return s < "x" end)
    assert.has_error(function() return s == S() end)
    assert.has_error(function() return n < 1 end)
    assert.has_error(function() return n + 1 end)
    assert.has_error(function() return s.field end)
    assert.is_true(H.issecretvalue(s))
    assert.is_false(H.issecretvalue("x"))
    assert.is_false(H.issecretvalue(nil))
    assert.are.equal("userdata", type(s))
    assert.are.equal("string", H.addonType(s))
    assert.are.equal("number", H.addonType(n))
    assert.are.equal("table", H.addonType({}))
  end)

  it("the addon's chunks see its kind as its type, and Compat.secret knows it", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    local WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua" })
    WFJ.Compat.init(function(name) return _G[name] end)
    local s = S()
    assert.are.equal("string", getfenv(WFJ.Compat.secret).type(s))
    _G.issecretvalue = H.issecretvalue
    assert.is_true(WFJ.Compat.secret(s))
    assert.is_false(WFJ.Compat.secret("x"))
    _G.issecretvalue = nil
    assert.is_false(WFJ.Compat.secret(s)) -- a client without secrets
  end)
end)

describe("the unit tooltip in combat", function()
  local UI = {
    QUEST_MONSTERS_KILLED = { "%2$d/%3$d %1$s slain", "%1$sを倒す: %2$d/%3$d" },
    TOOLTIP_UNIT_LEVEL = { "Level %s", "レベル %s" },
  }
  local LINE_TYPES = { None = 0, UnitName = 2, QuestObjective = 8, QuestTitle = 17 }
  local WFJ, tt

  local function left(i) return _G["GameTooltipTextLeft" .. i]:GetText() end
  local function kinds(list)
    local lines = {}
    for i, kind in ipairs(list) do lines[i] = { lineIndex = i, type = LINE_TYPES[kind] } end
    return { lines = lines }
  end
  local function hover(lines, data)
    tt:SetOwner(_G.UIParent, "ANCHOR_CURSOR")
    tt:SetText(lines[1])
    for i = 2, #lines do tt:AddLine(lines[i]) end
    for _, fn in ipairs(Stub.tooltipPostCalls[2] or {}) do fn(tt, data) end
    tt:Show()
  end

  before_each(function()
    WFJ = load({ "UI/QuestMap.lua", "UI/TimeLine.lua", "UI/Tooltip.lua", "UI/TooltipUnit.lua" }, UI, function(W)
      _G.Enum.TooltipDataLineType = LINE_TYPES
      _G.Enum.TooltipDataType.MinimapMouseover = 22
      _G.UIParent = _G.UIParent or CreateFrame("Frame", "UIParent")
      W.Data = { quest = {} }
      W.Lookup = { get = function() return nil end }
    end)
    WFJ.HelpTooltip.init()
    assert.is_true(WFJ.TooltipUnit.init())
    tt = _G.GameTooltip
  end)
  after_each(function()
    WFJ.State.names = false
    teardown()
  end)

  it("every line, the guid and the data's kind secret: each row stays the client's and keeps no record", function()
    hover({ "Murloc Warrior", "Level 40" }, kinds({ "UnitName", "None" })) -- a record on row 2 when combat starts
    assert.are.equal("レベル 40", left(2))
    local lines = { S(), S(), S(), S(), S() }
    local data = kinds({ "UnitName", "None", "QuestTitle", "QuestObjective", "None" })
    data.guid, data.type = S(), S("number")
    WFJ.State.names = true
    assert.has_no.errors(function() hover(lines, data) end)
    for i, l in ipairs(lines) do assert.is_true(same(l, left(i)), "row " .. i) end
    assert.are.equal(0, WFJ.SurfaceState.count(WFJ.TooltipUnit.SURFACE))
  end)

  it("a creature's tooltip with names on and every line secret: no name is looked up", function()
    local lines = { S(), S(), S() }
    local data = kinds({ "UnitName", "None", "None" })
    data.guid = "Creature-0-4372-0-17-3100-0000A1B2C3"
    WFJ.State.names = true
    assert.has_no.errors(function() hover(lines, data) end)
    for i, l in ipairs(lines) do assert.is_true(same(l, left(i)), "row " .. i) end
  end)

  it("a secret line index or kind is skipped, never used as a key", function()
    local data = { lines = { { lineIndex = S("number"), type = 2 }, { lineIndex = 2, type = S("number") } } }
    assert.are.same({}, WFJ.TooltipUnit.lineKinds(data))
  end)

  it("a one-line minimap tooltip whose line and kind are secret stays as written", function()
    local line = S()
    assert.has_no.errors(function() hover({ line }, { type = S("number") }) end)
    assert.is_true(same(line, left(1)))
    assert.are.same({ nil, "no readable title" }, { WFJ.TooltipUnit.questFor(S()) })
    assert.is_nil(WFJ.TooltipUnit.minimapBlock(S(), true))
  end)
end)

describe("the help tooltip walk in combat", function()
  local UI = {
    CHARACTER_BUTTON = { "Character Info", "キャラクター情報" },
    EQUIP_CONTAINER = { "Equip Container", "バッグを装備" },
  }
  local WFJ, tt, owner

  local function left(i) return _G["GameTooltipTextLeft" .. i]:GetText() end

  before_each(function()
    WFJ = load({}, UI)
    tt = _G.GameTooltip
    owner = Stub.button("CharacterMicroButton", "")
    WFJ.HelpTooltip.register(owner)
  end)
  after_each(function() teardown() end)

  it("a registered owner's tooltip written with secret lines: no line is read", function()
    local title, help = S(), S()
    assert.has_no.errors(function()
      tt:SetOwner(owner)
      tt:SetText(title)
      tt:AddLine(help)
      tt:Show()
    end)
    assert.is_true(same(title, left(1)))
    assert.is_true(same(help, left(2)))
  end)

  it("lines appended to an item tooltip in combat are left alone", function()
    local first, second = S(), S()
    tt:SetOwner(CreateFrame("Frame"))
    tt:SetText(first)
    tt:AddLine(second)
    assert.are.equal(0, WFJ.HelpTooltip.appended(tt, { only = { "EQUIP_CONTAINER" } }))
    assert.is_true(same(first, left(1)))
    assert.is_true(same(second, left(2)))
  end)

  it("a tooltip whose data kind is secret has no kind, and an adopted walk never compares it", function()
    tt:SetOwner(CreateFrame("Frame"))
    tt:SetText("Equip Container")
    tt.primaryInfo = { tooltipData = { type = S("number") } }
    assert.is_nil(WFJ.HelpTooltip.dataKind(tt))
    assert.has_no.errors(function()
      WFJ.HelpTooltip.adopt(tt, { from = 2 })
      tt:Show()
    end)
  end)
end)

describe("labels, names and fonts in combat", function()
  local WFJ

  before_each(function()
    WFJ = load({}, { CANCEL = { "Cancel", "キャンセル" } })
    WFJ.State.setNames(true)
  end)
  after_each(function()
    _G.UnitIsPlayer, _G.UnitPlayerControlled = nil, nil
    teardown()
  end)

  it("Labels.show and showArgs leave a secret line as it is, with no record", function()
    local s = S()
    local fs = Stub.fontString(s)
    assert.are.equal(0, WFJ.Labels.show("spec", "k", fs))
    assert.are.equal(0, WFJ.Labels.showArgs("spec", "k2", fs, "CANCEL", nil))
    assert.is_true(same(s, fs:GetText()))
    assert.are.equal(0, WFJ.SurfaceState.count("spec"))
  end)

  it("a secret name, and a unit whose player or pet answer is secret, stay as written", function()
    local s = S()
    local fs = Stub.fontString(s)
    for _, show in ipairs({ "show", "lead", "wrapped", "joined" }) do
      assert.are.equal(0, WFJ.NameLabels[show]("spec", "n." .. show, fs))
    end
    assert.is_true(same(s, fs:GetText()))
    local plain = Stub.fontString("Thrall")
    _G.UnitIsPlayer = function() return S("boolean") end
    assert.are.equal(0, WFJ.NameLabels.unit("spec", "unit", plain, "target"))
    _G.UnitIsPlayer = function() return false end
    _G.UnitPlayerControlled = function() return S("boolean") end
    assert.are.equal(0, WFJ.NameLabels.unit("spec", "unit", plain, "target"))
    assert.are.equal("Thrall", plain:GetText())
  end)

  it("Font.bundle leaves a FontString whose font is secret as it is", function()
    local path, size = S(), S("number")
    local fs = Stub.fontString("x")
    fs.font = { path = path, size = size, flags = "" }
    assert.is_nil(WFJ.Font.bundle(fs))
    assert.is_false(WFJ.Font.dressed(fs))
    assert.is_true(same(path, fs.font.path))
  end)
end)

describe("the text watcher in combat", function()
  local WFJ, TW

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "UI/TextWatch.lua" })
    WFJ.Compat.init(function(name) return _G[name] end)
    _G.issecretvalue = H.issecretvalue
    TW = WFJ.TextWatch
  end)
  after_each(function() _G.issecretvalue = nil end)

  it("a secret text or font is never compared, and one a callback leaves is not kept", function()
    local fs = Stub.fontString("Say:")
    fs.shown = true
    local runs = 0
    TW.add(fs, function() runs = runs + 1 end)
    TW.tick()
    assert.are.equal(1, runs)
    fs.text = S()
    assert.has_no.errors(function() TW.tick() end)
    fs.text = "Say:"
    fs.font.path = S()
    assert.has_no.errors(function() TW.tick() end)
    assert.are.equal(1, runs)
    local other = Stub.fontString("a")
    other.shown = true
    TW.add(other, function() other.text = S() end)
    assert.has_no.errors(function()
      TW.tick()
      TW.tick()
      other.text = "b"
      TW.tick()
    end)
  end)
end)

describe("combat text, cast bar, unit frames, nameplates and aura durations in combat", function()
  local WFJ

  before_each(function()
    WFJ = load({ "UI/CombatText.lua", "UI/CastingBar.lua", "UI/UnitFrames.lua", "UI/HudLabels.lua" },
      { COMBAT_TEXT_MISS = { "Miss", "ミス" } })
    WFJ.State.setNames(true)
    _G.UnitIsPlayer = function() return false end
    _G.UnitPlayerControlled = function() return false end
  end)
  after_each(function()
    Stub.units.target = nil
    teardown({ "UnitIsPlayer", "UnitPlayerControlled" })
  end)

  it("a secret combat text message, or a pooled string holding one, is never matched", function()
    local s = S()
    local fs = Stub.fontString(s)
    assert.are.equal(0, WFJ.CombatText.onAddMessage({ activeFontStrings = { fs } }, s))
    assert.is_true(same(s, fs:GetText()))
    local held = S()
    local pooled = Stub.fontString(held)
    assert.are.equal(0, WFJ.CombatText.onAddMessage({ activeFontStrings = { pooled } }, "Miss"))
    assert.is_true(same(held, pooled:GetText()))
  end)

  it("a cast bar whose spell or target name is secret stays as written", function()
    local spell = S()
    local bar = { Text = Stub.fontString(spell), CastTargetNameText = Stub.fontString("") }
    assert.are.equal(0, WFJ.CastingBar.onEvent(bar))
    assert.is_true(same(spell, bar.Text:GetText()))
    local target = S()
    Stub.units.target = { name = S() }
    bar = { Text = Stub.fontString("Frostbolt"), CastTargetNameText = Stub.fontString(target) }
    assert.has_no.errors(function() WFJ.CastingBar.onEvent(bar) end)
    assert.is_true(same(target, bar.CastTargetNameText:GetText()))
  end)

  it("a nameplate or unit frame whose name, or whose player answer, is secret stays as written", function()
    local name = S()
    local plate = { name = Stub.fontString(name), unit = "nameplate1" }
    assert.are.equal(0, WFJ.UnitFrames.onCompactName(plate))
    assert.is_true(same(name, plate.name:GetText()))
    _G.UnitIsPlayer = function() return S("boolean") end
    local frame = { name = Stub.fontString("Thrall"), unit = "target" }
    assert.are.equal(0, WFJ.UnitFrames.onCompactName(frame))
    assert.are.equal(0, WFJ.UnitFrames.onUnitUpdate(frame))
    assert.are.equal("Thrall", frame.name:GetText())
    local status = S()
    local compact = { statusText = Stub.fontString(status) }
    assert.are.equal(0, WFJ.UnitFrames.onStatusText(compact))
    assert.is_true(same(status, compact.statusText:GetText()))
  end)

  it("a secret aura duration or frame rate line is never compared", function()
    local left = S()
    local button = { Duration = Stub.fontString(left) }
    assert.are.equal(0, WFJ.HudLabels.onDuration(button))
    assert.is_true(same(left, button.Duration:GetText()))
    local rate = Stub.fontString(S())
    assert.are.equal(0, WFJ.HudLabels.onFramerate(rate))
  end)
end)

describe("UI error messages in combat", function()
  local WFJ

  local UI = { ERR_OUT_OF_RANGE = { "Out of range.", "範囲外です。" } }
  before_each(function() WFJ = load({ "UI/Errors.lua" }, UI) end)
  after_each(function() teardown() end)

  it("a secret message, message id or line is never compared or matched", function()
    local s = S()
    assert.are.equal(0, WFJ.Errors.onAddMessage({}, s, 1, 0, 0, 1, 5))
    assert.are.equal(0, WFJ.Errors.render({}, s))
    local held = S()
    local frame = {
      GetFontStringByID = function() return nil end,
      GetRegions = function() return Stub.fontString(held) end,
    }
    assert.are.equal(0, WFJ.Errors.render(frame, "Out of range.", S("number")))
    assert.are.equal(1, WFJ.Errors.onAddMessage(frame, "Out of range.", 1, 0, 0, 1, S("number")))
    local wrapped = WFJ.Errors.wrapShould(function() return true end)
    assert.is_true(wrapped(frame, 5, s))
    assert.is_true(wrapped(frame, S("number"), "Out of range."))
  end)
end)

describe("the chat edit box header in combat", function()
  local WFJ

  before_each(function() WFJ = load({ "UI/ChatTabs.lua" }, { CHAT_SAY_SEND = { "Say: ", "発言： " } }) end)
  after_each(function() teardown({ "ChatFrame1EditBoxHeader" }) end)

  it("a header written with a secret is neither kept nor measured", function()
    local text = S()
    local header = Stub.fontString(text)
    function header.GetStringWidth() return S("number") end
    _G.ChatFrame1EditBoxHeader = header
    local box = {}
    function box.GetName() return "ChatFrame1EditBox" end
    function box.GetTextInsets() return S("number"), 13, 0, 0 end
    function box:SetTextInsets(l) self.inset = l end
    assert.are.equal(0, WFJ.ChatTabs.onHeader(box))
    assert.is_true(same(text, header:GetText()))
    assert.is_nil(box.inset)
  end)
end)

describe("chat and NPC speech in combat", function()
  local SYSTEM, PLAYER_SAY, MONSTER_SAY, EMOTE = 99, 1, 11, 15
  local NAMES = { "CHAT_FRAMES", "ChatTypeInfo", "ChatFrame1", "C_ChatBubbles", "C_Timer" }
  local WFJ, f, diag

  local function chatFrame()
    local frame = { history = {}, visibleLines = { Stub.fontString("") }, callbacks = {},
      fontObject = Stub.fontObject("Fonts\\ARIALN.TTF", 14) }
    function frame:AddMessage(message, r, g, b, ...)
      self.history[#self.history + 1] = { message = message, r = r, g = g, b = b,
        extra = { n = select("#", ...), ... } }
    end
    function frame:TransformMessages(predicate, transform)
      for i, e in ipairs(self.history) do
        if predicate(e.message, e.r, e.g, e.b, unpack(e.extra, 1, e.extra.n)) then
          local message = transform(e.message, e.r, e.g, e.b, unpack(e.extra, 1, e.extra.n))
          self.history[i] = { message = message, r = e.r, g = e.g, b = e.b, extra = e.extra }
        end
      end
    end
    function frame:GetNumMessages() return #self.history end
    function frame:GetMessageInfo(i)
      local e = self.history[#self.history - i + 1]
      if e then return e.message, e.r, e.g, e.b end
    end
    function frame:GetFontObject() return self.fontObject end
    function frame:AddOnDisplayRefreshedCallback(cb) self.callbacks[#self.callbacks + 1] = cb end
    function frame:Refresh()
      local line, e = self.visibleLines[1], self.history[#self.history]
      line.messageInfo = e
      line:SetFontObject(self.fontObject)
      line:SetText(e and e.message or "")
      for _, cb in ipairs(self.callbacks) do cb(self) end
    end
    function frame:Last() return self.history[#self.history].message end
    return frame
  end

  -- the chat event handler for a monster line: the formatter and the AddMessage call it makes
  local function npc(line, args)
    f:AddMessage(line, 1, 1, 0.6, MONSTER_SAY, nil, nil, "CHAT_MSG_MONSTER_SAY", args,
      function(m) return "Ralph says: " .. m end)
  end

  before_each(function()
    WFJ = load({ "Core/Lookup.lua", "UI/Errors.lua", "UI/ChatSystem.lua", "UI/ChatUnlisted.lua", "UI/Speech.lua" }, {},
      function()
        _G.ChatTypeInfo = { SYSTEM = { id = SYSTEM }, SAY = { id = PLAYER_SAY }, MONSTER_SAY = { id = MONSTER_SAY },
          TEXT_EMOTE = { id = EMOTE } }
        _G.ChatFrame1 = chatFrame()
        _G.CHAT_FRAMES = { "ChatFrame1" }
        _G.C_ChatBubbles = { GetAllChatBubbles = function() return {} end }
        _G.C_Timer = { After = function() end }
      end)
    WFJ.Data = WFJ.Data or {}
    WFJ.Data.gossip = {}
    diag = WFJ.Diag.load(nil)
    WFJ.State.setArea("gossip", true)
    assert.is_true(WFJ.ChatSystem.init())
    assert.is_true(WFJ.Speech.init({ key = function(t) return ("%016x"):format(#t) end,
      expand = function(ja) return ja end }))
    f = _G.ChatFrame1
  end)
  after_each(function()
    -- nothing the problem log kept may be a secret: it is saved, and a later report compares it
    for _, e in ipairs(diag.entries) do
      for k, v in pairs(e) do assert.is_false(H.issecretvalue(v), "log field " .. tostring(k)) end
    end
    teardown(NAMES)
  end)

  it("a secret system line stays in the history and on the visible line as the client wrote it", function()
    local s = S()
    assert.has_no.errors(function()
      f:AddMessage(s, 1, 1, 0, SYSTEM)
      f:Refresh()
      WFJ.ChatSystem.sweep()
    end)
    assert.is_true(same(s, f:Last()))
    assert.is_true(same(s, f.visibleLines[1]:GetText()))
  end)

  it("a player's line or an emote with a secret line id or sender is left as written", function()
    f:AddMessage("Bob says: Hi", 1, 1, 1, PLAYER_SAY, nil, nil, "CHAT_MSG_SAY", { "Hi", "Bob", n = 12,
      [11] = S("number") })
    assert.are.equal("Bob says: Hi", f:Last())
    f:AddMessage("Bob waves.", 1, 0.5, 0.25, EMOTE, 1, 1, "CHAT_MSG_TEXT_EMOTE", { "waves", "Bob", n = 12,
      [11] = S("number") })
    assert.are.equal("Bob waves.", f:Last())
    f:AddMessage("Bob cheers.", 1, 0.5, 0.25, EMOTE, 1, 1, "CHAT_MSG_TEXT_EMOTE", { "cheers", S(), n = 12,
      [11] = 7 })
    assert.are.equal("Bob cheers.", f:Last())
  end)

  it("a keyed frame's secret line, a secret line height and an unlisted secret line are never read", function()
    local keyed = chatFrame()
    WFJ.ChatSystem.hookKeyed(keyed, { "COMMUNITIES_CHAT_FRAME_TODAY_NOTIFICATION" })
    local s = S()
    assert.has_no.errors(function() keyed:AddMessage(s) end)
    assert.is_true(same(s, keyed:Last()))
    local line = Stub.fontString("テスト")
    function line.GetHeight() return S("number") end
    function line.GetStringHeight() return 40 end
    assert.is_number(WFJ.ChatSystem.fit(line))
    local tall = Stub.fontString("テスト")
    function tall.GetHeight() return 14 end
    function tall.GetStringHeight() return S("number") end
    assert.is_number(WFJ.ChatSystem.fit(tall))
    assert.is_false(WFJ.ChatUnlisted.seen(S()))
  end)

  it("an NPC line whose text is secret is never read", function()
    local line = S()
    assert.has_no.errors(function()
      npc(line, { S(), "Ralph", "", n = 12, [11] = 1, [12] = "Creature-0-1-2-3-1234-00002" })
    end)
    assert.is_true(same(line, f:Last()))
  end)

  it("an NPC line whose speaker, target, language, GUID, line id and this character's name are secret", function()
    _G.UnitName = function() return S() end
    local plain = "Ralph says: Something no one translated!"
    assert.has_no.errors(function()
      npc(plain, { "Something no one translated!", S(), S(), n = 12, [5] = S(), [11] = 2, [12] = S() })
      npc(plain, { "Something no one translated!", "Ralph", "", n = 12, [11] = 3,
        [12] = "Creature-0-1-2-3-1234-00002" }) -- no target: the party's secret names are asked about
      npc(plain, { "Something no one translated!", "Ralph", "", n = 12, [11] = S("number") })
    end)
    assert.are.equal(plain, f:Last())
    assert.is_false(WFJ.Speech.knownLanguage(S()))
    assert.is_nil(WFJ.Speech.translate(S()))
    assert.is_nil(WFJ.Speech.translateNamed(S()))
    assert.are.equal(0, WFJ.Speech.onRaidWarning({}, "RAID_BOSS_EMOTE", S(), "Bob"))
    assert.are.equal(0, WFJ.Speech.onRaidWarning({}, "RAID_BOSS_EMOTE", "%s goes into a frenzy!", S()))
  end)
end)

describe("the Collector in combat", function()
  local WFJ, C
  local GUID = "Creature-0-4372-0-17-3100-0000A1B2C3"

  before_each(function()
    H.coreStub()
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "Core/Normalize.lua", "Core/Hash.lua",
      "Core/State.lua", "Core/Settings.lua" })
    H.loadPure("Core/Collector.lua", nil, WFJ)
    WFJ.Compat.init(function(name) return _G[name] end)
    _G.issecretvalue = H.issecretvalue
    C = WFJ.Collector
    C.load(nil, {
      enabled = function() return true end,
      lookup = function() return nil end,
      player = function() return { name = "Reyn", class = "Hunter", race = "Night Elf" } end,
      build = function() return "1.15.9.69722" end,
      print = function() end,
    })
  end)
  after_each(function() _G.issecretvalue = nil end)

  it("a secret GUID, text, name, sex or display id is refused or left out, never raised on", function()
    assert.is_nil(C.creatureId(S()))
    assert.are.same({ "refused", "secret" }, { C.record("quest", 5, "title", S()) })
    assert.are.same({ "refused", "secret" }, { C.recordGossip(S(), S()) })
    assert.are.same({ "refused", "no_creature" }, { C.recordNpc(S(), "Ralph") })
    assert.are.same({ "refused", "secret" }, { C.recordNpc(GUID, S()) })
    assert.are.equal("recorded", (C.recordQuestNpc(95603, "description", GUID, S("number"), S("number"))))
    assert.are.equal(0, C.status().errors)
  end)
end)

describe("the voice player's speaker in combat", function()
  local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua", "Core/Voice.lua",
    "Core/Modifier.lua", "Core/Translator.lua", "Core/SurfaceState.lua", "Core/Normalize.lua", "Core/Hash.lua",
    "Core/Collector.lua", "Core/UIStringKeys.lua", "Core/UIStrings.lua", "UI/Font.lua", "UI/Frames.lua",
    "UI/Render.lua", "Core/VoiceQueue.lua", "UI/VoicePlayer.lua", "UI/ButtonText.lua", "UI/Labels.lua",
    "UI/NameLabels.lua", "UI/QuestFrame.lua" }
  local WFJ

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    WFJ.Compat.init(function(name) return _G[name] end)
    _G.issecretvalue = H.issecretvalue
  end)
  after_each(function()
    Stub.units.questnpc = nil
    _G.issecretvalue, _G.C_TooltipInfo = nil, nil
  end)

  it("a secret GUID gives no speaker; a secret sex is not known; a secret title line is no title", function()
    Stub.units.questnpc = { name = S(), guid = S() }
    assert.is_nil(WFJ.VoicePlayer.speaker("QuestFrame"))
    Stub.units.questnpc = { name = "Ralph", guid = "Creature-0-1-0-1-1992-0000ABCD" }
    _G.UnitSex = function() return S("number") end
    local who = WFJ.VoicePlayer.speaker("QuestFrame")
    assert.are.equal(1992, who.creature)
    assert.is_nil(who.sex)
    _G.C_TooltipInfo = { GetUnit = function() return { lines = { { leftText = S() }, { leftText = S() } } } end }
    assert.is_nil(WFJ.VoicePlayer.titleOf("questnpc"))
  end)
end)
