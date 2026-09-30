-- UI/Errors.lua over a UIErrorsFrame whose TryDisplayMessage replays the Forever source
-- (blizzard_uierrorsframe/mainline/uierrorsframe.lua:118–157): a MessageFrame line per message id, the id's key from
-- GetGameMessageInfo. Also the Core/UIStrings error-key rules (argKinds / keyOnly, ADR-035).
local Stub = require("tests.lua.spec.wow_stub")
local X = require("tests.lua.spec.stub_framexml_hud")

local UI = {
  ERR_OUT_OF_RANGE = { "Out of range.", "範囲外です。" },
  ERR_OUT_OF_MANA = { "Not enough mana", "マナが足りません" },
  ERR_INV_FULL = { "Inventory is full.", "バッグがいっぱいです。" },
  ERR_QUEST_ADD_KILL_SII = { "%s slain: %d/%d", "%s を倒した: %d/%d" },
  ERR_SPELL_FAILED_S = { "%s", "%s" }, -- a pass-through wrapper (listed here only to prove it is never shown itself)
  SPELL_FAILED_UNIT_NOT_INFRONT = { "Target needs to be in front of you.", "ターゲットが正面にいる必要があります。" },
  ERR_CLUB_FINDER_ERROR_TYPE_FLAGGED_RENAME = { "Your %s has been flagged for a rename.", "あなたの%sは改名が必要です。" },
  CLUB_FINDER_GUILD = { "Guild", "ギルド" },
  ERR_TAME_FAILED = { "%s.", "%s。" }, -- almost no text of its own: never a wrapper's line
  ITEM_REQ_SKILL = { "Requires %s", "%sが必要" },
  ERR_USE_LOCKED_WITH_ITEM_S = { "Requires %s", "%sが必要" },
  -- a mechanic word is a dictionary word when it is an entry, kept as written otherwise
  ERR_ATTACK_PREVENTED_BY_MECHANIC_S = { "Can't attack while %s.", "%sの間は攻撃できません。" },
  LOSS_OF_CONTROL_DISPLAY_STUN = { "Stunned", "スタン" },
  -- lines Blizzard's Lua formats
  TOO_MANY_WATCHED_TOKENS = { "You may only watch %d currencies at a time", "通貨は同時に%dつまでしか表示できません" },
  ERROR_CLUB_ACTION_INVITE_MEMBER = { "Couldn't invite member. %s", "メンバーを招待できませんでした。%s" },
  ERROR_CLUB_ACTION_REDEEM_TICKET = { "Couldn't redeem invite link. %s", "招待リンクを使用できませんでした。%s" },
  ERROR_COMMUNITIES_IGNORED = { "Player is ignored.", "プレイヤーは無視されています。" },
}
-- the message ids the stub client sends: LE_GAME_ERR_* numbers → GlobalStrings keys
local IDS = { [1] = "ERR_OUT_OF_RANGE", [2] = "ERR_OUT_OF_MANA", [3] = "ERR_INV_FULL", [4] = "ERR_QUEST_ADD_KILL_SII",
  [5] = "ERR_SPELL_FAILED_S", [6] = "ERR_BADATTACKFACING", [8] = "ERR_ATTACK_PREVENTED_BY_MECHANIC_S" }
local NAMES = { "UIErrorsFrame", "GetGameMessageInfo", "ERR_BADATTACKFACING", "C_Timer" }

local function install()
  _G.ERR_BADATTACKFACING = "You are facing the wrong way!" -- a key the client has and the addon does not list
  _G.GetGameMessageInfo = function(id) return IDS[id], nil, nil end
  local frame = { lines = {}, order = {} }
  -- MessageFrame:AddMessage(text, r, g, b, a, messageID); a line per id, replaced when the id is sent again
  function frame:AddMessage(text, _, _, _, _, id)
    local fs = id and self.lines[id]
    if not fs then
      fs = Stub.fontString("")
      self.order[#self.order + 1] = fs
      if id then self.lines[id] = fs end
    end
    fs:SetText(text)
  end
  function frame:GetFontStringByID(id) return self.lines[id] end
  function frame:GetRegions() return unpack(self.order) end -- the Lua-added lines are found among the regions
  -- uierrorsframe.lua:106–157: flash an existing line that shows this message (throttled types), else add it and
  -- play the error sound
  frame.flashingFontStrings, frame.sounds, frame.flashed = {}, 0, 0
  local THROTTLED = { [1] = true, [5] = true }
  function frame:FlashFontString(fs)
    fs.origMsg = fs:GetText()
    self.flashingFontStrings[fs] = true
  end
  function frame.ResetMessageFadeByID() end
  function frame:TryFlashingExistingMessage(messageType, message)
    local existing = self:GetFontStringByID(messageType)
    if existing and existing:GetText() == message then
      self.flashed = self.flashed + 1
      self:FlashFontString(existing)
      self:ResetMessageFadeByID(messageType)
      return true
    end
    return false
  end
  function frame:ShouldDisplayMessageType(messageType, message)
    if THROTTLED[messageType] and self:TryFlashingExistingMessage(messageType, message) then return false end
    return true
  end
  function frame:TryDisplayMessage(messageType, message)
    if self:ShouldDisplayMessageType(messageType, message) then
      self:AddMessage(message, 1, 0.1, 0.1, 1.0, messageType)
      self.sounds = self.sounds + 1
    end
  end
  _G.UIErrorsFrame = frame
end

describe("the UI errors frame", function()
  local WFJ
  before_each(function()
    WFJ = X.load("UI/Errors.lua", UI, { before = install })
    assert.is_true(WFJ.Errors.init())
  end)
  after_each(function() X.teardown(NAMES) end)

  it("a listed id's line shows its Japanese", function()
    _G.UIErrorsFrame:TryDisplayMessage(1, "Out of range.")
    _G.UIErrorsFrame:TryDisplayMessage(2, "Not enough mana")
    _G.UIErrorsFrame:TryDisplayMessage(3, "Inventory is full.")
    assert.are.equal("範囲外です。", _G.UIErrorsFrame.lines[1]:GetText())
    assert.are.equal("マナが足りません", _G.UIErrorsFrame.lines[2]:GetText())
    assert.are.equal("バッグがいっぱいです。", _G.UIErrorsFrame.lines[3]:GetText())
  end)

  it("in game: a line is found on the next frame; a first line and a quick repeat each get their own Japanese",
    function()
      -- Forever: a non-throttled repeat adds a new line, and GetFontStringByID(id) right after
      -- AddMessage still names the previous line of that id; the new line is the id's only on the next frame
      local f, queue, next = _G.UIErrorsFrame, {}, {}
      _G.C_Timer = { After = function(_, fn) queue[#queue + 1] = fn end }
      WFJ.Compat.declare(WFJ.Errors.SURFACE, "timer", { "C_Timer" }) -- resolved again, now with the timer
      function f:AddMessage(text, _, _, _, _, id)
        local fs = Stub.fontString(text)
        self.order[#self.order + 1] = fs
        if id then next[id] = fs end
      end
      hooksecurefunc(f, "AddMessage", WFJ.Errors.onAddMessage) -- this frame's AddMessage, hooked as init does
      local function frame()
        for id, fs in pairs(next) do f.lines[id] = fs end
        next = {}
        local fns = queue
        queue = {}
        for _, fn in ipairs(fns) do fn() end
      end
      f:TryDisplayMessage(3, "Inventory is full.")
      assert.are.equal("Inventory is full.", f.order[1]:GetText()) -- nothing yet: the line is not the id's yet
      frame()
      assert.are.equal("バッグがいっぱいです。", f.order[1]:GetText()) -- the first line
      f:TryDisplayMessage(3, "Inventory is full.")
      f:TryDisplayMessage(3, "Inventory is full.")
      frame()
      assert.are.equal("バッグがいっぱいです。", f.order[2]:GetText())
      assert.are.equal("バッグがいっぱいです。", f.order[3]:GetText())
      Stub.keys.alt = true
      WFJ.Modifier.refresh()
      for i = 1, 3 do assert.are.equal("Inventory is full.", f.order[i]:GetText()) end -- a record per line
      Stub.keys.alt = false
      WFJ.Modifier.refresh()
    end)

  it("text that is neither the key's English nor an exact dictionary English stays as written",
    function()
      local f = _G.UIErrorsFrame
      f:TryDisplayMessage(6, "You are facing the wrong way!") -- a key with no Japanese, and no entry has that English
      assert.are.equal("You are facing the wrong way!", f.lines[6]:GetText())
      assert.is_true(X.unrecorded(WFJ, f.lines[6]))
      f:TryDisplayMessage(99, "Some other addon's line") -- GetGameMessageInfo → nil, not an entry
      assert.are.equal("Some other addon's line", f.lines[99]:GetText())
      f:TryDisplayMessage(1, "Out of range for real") -- under the range id, not its English, not an entry
      assert.are.equal("Out of range for real", f.lines[1]:GetText())
      f:TryDisplayMessage(4, "Kobold Vermin slain") -- a template's prefix is not an exact English
      assert.are.equal("Kobold Vermin slain", f.lines[4]:GetText())
    end)

  it("a line with no id, an unresolved id or LE_GAME_ERR_SYSTEM shows an exact dictionary English's Japanese",
    function()
      local f = _G.UIErrorsFrame
      f:AddMessage("Inventory is full.", 1, 0.1, 0.1, 1) -- Blizzard's Lua: UIErrorsFrame:AddMessage(KEY, r, g, b, a)
      assert.are.equal("バッグがいっぱいです。", f.order[#f.order]:GetText())
      f:TryDisplayMessage(99, "Not enough mana") -- an id GetGameMessageInfo does not name
      assert.are.equal("マナが足りません", f.lines[99]:GetText())
      f:TryDisplayMessage(1, "Not enough mana") -- the range id carrying another key's exact English
      assert.are.equal("マナが足りません", f.lines[1]:GetText())
      f:AddMessage("Some other addon's line", 1, 0.1, 0.1, 1)
      assert.are.equal("Some other addon's line", f.order[#f.order]:GetText())
      f:AddMessage("Kobold Vermin slain: 1/2", 1, 1, 0, 1) -- an error template, not a Lua one: never tried here
      assert.are.equal("Kobold Vermin slain: 1/2", f.order[#f.order]:GetText())
      X.alt(WFJ, true)
      assert.are.equal("Inventory is full.", f.order[1]:GetText())
      X.alt(WFJ, false)
      assert.are.equal("バッグがいっぱいです。", f.order[1]:GetText())
    end)

  it("a line Lua formats fills its template; a community action's error is its own entry", function()
    local f = _G.UIErrorsFrame
    f:AddMessage("You may only watch 3 currencies at a time", 1, 0.1, 0.1, 1)
    assert.are.equal("通貨は同時に3つまでしか表示できません", f.order[#f.order]:GetText())
    f:AddMessage("Couldn't invite member. Player is ignored.", 1, 0.1, 0.1, 1)
    assert.are.equal("メンバーを招待できませんでした。プレイヤーは無視されています。", f.order[#f.order]:GetText())
    f:AddMessage("Couldn't invite member. Something else.", 1, 0.1, 0.1, 1) -- the error is no entry
    assert.are.equal("Couldn't invite member. Something else.", f.order[#f.order]:GetText())
    f:AddMessage("Couldn't redeem invite link. ", 1, 0.1, 0.1, 1) -- :format(""), communitieshyperlink.lua:16
    assert.are.equal("Couldn't redeem invite link. ", f.order[#f.order]:GetText())
  end)

  it("a pass-through wrapper's line is resolved against the listed error keys", function()
    _G.UIErrorsFrame:TryDisplayMessage(5, "Target needs to be in front of you.")
    assert.are.equal("ターゲットが正面にいる必要があります。", _G.UIErrorsFrame.lines[5]:GetText())
    _G.UIErrorsFrame:TryDisplayMessage(5, "Some other addon's line")
    assert.are.equal("Some other addon's line", _G.UIErrorsFrame.lines[5]:GetText())
    _G.UIErrorsFrame:TryDisplayMessage(5, "Guild") -- no error key, but an exact dictionary English
    assert.are.equal("ギルド", _G.UIErrorsFrame.lines[5]:GetText())
    _G.UIErrorsFrame:TryDisplayMessage(5, "Some other addon's line.") -- not taken for "%s." (ERR_TAME_FAILED)
    assert.are.equal("Some other addon's line.", _G.UIErrorsFrame.lines[5]:GetText())
  end)

  it("a formatted error keeps its name and numbers as written", function()
    _G.UIErrorsFrame:TryDisplayMessage(4, "Kobold Vermin slain: 3/10")
    assert.are.equal("Kobold Vermin を倒した: 3/10", _G.UIErrorsFrame.lines[4]:GetText())
    _G.UIErrorsFrame:TryDisplayMessage(4, "Guild slain: 1/2") -- a dictionary word as the name is still kept
    assert.are.equal("Guild を倒した: 1/2", _G.UIErrorsFrame.lines[4]:GetText())
  end)

  it("the modifier shows the live English; releasing it shows the Japanese", function()
    _G.UIErrorsFrame:TryDisplayMessage(1, "Out of range.")
    X.alt(WFJ, true)
    assert.are.equal("Out of range.", _G.UIErrorsFrame.lines[1]:GetText())
    X.alt(WFJ, false)
    assert.are.equal("範囲外です。", _G.UIErrorsFrame.lines[1]:GetText())
  end)

  it("a repeated throttled error flashes its Japanese line, silently, as the client does for English",
    function()
      local f = _G.UIErrorsFrame
      f:TryDisplayMessage(1, "Out of range.")
      f:TryDisplayMessage(1, "Out of range.")
      f:TryDisplayMessage(1, "Out of range.")
      assert.are.equal("範囲外です。", f.lines[1]:GetText())
      assert.are.equal(1, f.sounds) -- the first line only; the repeats flash
      assert.are.equal(2, f.flashed)
      assert.are.equal("範囲外です。", f.lines[1].origMsg) -- the flash runs on the text that shows
      -- a type the client never throttles is added again (and sounds) exactly as without the addon
      f:TryDisplayMessage(2, "Not enough mana")
      f:TryDisplayMessage(2, "Not enough mana")
      assert.are.equal(3, f.sounds)
      assert.are.equal("マナが足りません", f.lines[2]:GetText())
      -- with the modifier held the line is English, and the client's own comparison already holds
      X.alt(WFJ, true)
      f:TryDisplayMessage(1, "Out of range.")
      assert.are.equal("Out of range.", f.lines[1]:GetText())
      assert.are.equal(3, f.flashed)
    end)


  it("an argument that is a dictionary word is shown in Japanese; any other as written", function()
    _G.UIErrorsFrame:TryDisplayMessage(8, "Can't attack while Stunned.")
    assert.are.equal("スタンの間は攻撃できません。", _G.UIErrorsFrame.lines[8]:GetText())
    _G.UIErrorsFrame:TryDisplayMessage(8, "Can't attack while Polymorphed.")
    assert.are.equal("Polymorphedの間は攻撃できません。", _G.UIErrorsFrame.lines[8]:GetText())
  end)

  it("an id GetGameMessageInfo raises on is taken as an unresolved id", function()
    _G.GetGameMessageInfo = function(id) if id == 9 then error("bad id") end return IDS[id] end
    WFJ.Compat.init(function(name) return _G[name] end)
    assert.has_no.errors(function() _G.UIErrorsFrame:AddMessage("Some other addon's line", 1, 0, 0, 1, 9) end)
    assert.are.equal("Some other addon's line", _G.UIErrorsFrame.lines[9]:GetText())
    _G.UIErrorsFrame:AddMessage("Out of range.", 1, 0, 0, 1, 9)
    assert.are.equal("範囲外です。", _G.UIErrorsFrame.lines[9]:GetText()) -- the exact-English rule still applies
  end)

  it("init hooks once; no frame or no GetGameMessageInfo → false", function()
    assert.is_false(WFJ.Errors.init())
    _G.UIErrorsFrame:TryDisplayMessage(1, "Out of range.")
    assert.are.equal(1, _G.UIErrorsFrame.lines[1].calls.addonSetText) -- one hook, one write
    X.teardown(NAMES)
    WFJ = X.load("UI/Errors.lua", UI)
    assert.is_false(WFJ.Errors.init())
    _G.UIErrorsFrame = { AddMessage = function() end }
    WFJ = X.load("UI/Errors.lua", UI, { before = function() _G.UIErrorsFrame = { AddMessage = function() end } end })
    assert.is_false(WFJ.Errors.init()) -- GetGameMessageInfo missing
  end)

  it("a wrong-typed call raises nothing", function()
    assert.has_no.errors(function()
      WFJ.Errors.onAddMessage(nil)
      WFJ.Errors.onAddMessage(_G.UIErrorsFrame, "x", 1, 1, 1, 1, "id")
      WFJ.Errors.onAddMessage({}, "x", 1, 1, 1, 1, 1)
    end)
  end)
end)

describe("the error keys in the UI index", function()
  local WFJ
  before_each(function() WFJ = X.load("UI/Errors.lua", UI, { before = install }) end)
  after_each(function() X.teardown(NAMES) end)

  it("an undeclared error template is matched only by key, its %s as text", function()
    assert.is_nil((WFJ.UIIndex:match("Kobold Vermin slain: 3/10")))
    local key, args = WFJ.UIIndex:matchOnly("Kobold Vermin slain: 3/10", { "ERR_QUEST_ADD_KILL_SII" })
    assert.are.equal("ERR_QUEST_ADD_KILL_SII", key)
    assert.are.equal("Kobold Vermin", args[1])
    assert.are.equal("text", WFJ.UIStrings.argKinds("SPELL_FAILED_ANYTHING")[1])
    assert.is_nil(WFJ.UIStrings.argKinds("QUEST_MONSTERS_KILLED_ANYTHING"))
  end)

  it("a declared error key is still matched only by key, unless it is one of the shared ones", function()
    assert.is_nil((WFJ.UIIndex:match("Can't attack while Stunned.")))
    assert.is_true(WFJ.UIStrings.keyOnly("ERR_ATTACK_PREVENTED_BY_MECHANIC_S"))
    assert.is_false(WFJ.UIStrings.keyOnly("ERR_USE_LOCKED_WITH_ITEM_S"))
  end)

  it("a declared error key keeps its kinds and its unrestricted match", function()
    local key, args = WFJ.UIIndex:match("Your Guild has been flagged for a rename.")
    assert.are.equal("ERR_CLUB_FINDER_ERROR_TYPE_FLAGGED_RENAME", key)
    assert.are.equal("あなたのギルドは改名が必要です。", WFJ.UIIndex:fill(WFJ.UIIndex.rows[key][1], args))
    assert.is_nil((WFJ.UIIndex:match("Your Kobold has been flagged for a rename."))) -- `word`: an entry only
    -- "Requires %s" sorts under ERR_USE_LOCKED_WITH_ITEM_S now; it carries ITEM_REQ_SKILL's `skill`, unrestricted
    key, args = WFJ.UIIndex:match("Requires Herbalism")
    assert.is_not_nil(key)
    assert.are.equal("Herbalismが必要", WFJ.UIIndex:fill(WFJ.UIIndex.rows[key][1], args))
    assert.is_nil((WFJ.UIIndex:match("Requires Level 40")))
  end)
end)
