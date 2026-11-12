-- UI/DialogueUI: the Dialogue UI addon's quest and gossip window, when the player has that addon. The window is
-- tests/lua/spec/stub_dialogueui.lua, a stand-in written from that addon's behaviour.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local DUI = require("tests.lua.spec.stub_dialogueui")

local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
for _, f in ipairs({ "UI/TimeLine.lua", "UI/TooltipUnit.lua", "UI/Tooltip.lua",
  "Core/Voice.lua", "Core/VoiceQueue.lua", "UI/VoicePlayer.lua", "UI/QuestFrame.lua",
  "UI/QuestMap.lua", "UI/ItemText.lua", "UI/DialogueUI.lua", "UI/DialogueUIFrames.lua", "UI/DialogueUIBook.lua" }) do
  FILES[#FILES + 1] = f
end

local PLAYER = { name = "Reyn", class = "Hunter", race = "Night Elf" }
local NPC = "Innkeeper Allison"

describe("UI/DialogueUI: Dialogue UI's quest and gossip window", function()
  local WFJ, data, frame, logs, shown, caught, collected

  local function key(en) return WFJ.Collector.key(en, PLAYER) end

  -- { [kind] = { [id] = ja | { ja, status } } }, gossip ids given by English
  local function ship(rows)
    data = {}
    for kind, byId in pairs(rows) do
      data[kind] = {}
      for id, v in pairs(byId) do
        local ja, status = v, "."
        if type(v) == "table" then ja, status = v[1], v[2] end
        if kind == "gossip" then id = key(id) end
        data[kind][id] = { ja = ja, status = status }
      end
    end
  end

  local function load(opts)
    opts = opts or {}
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    DUI.installGameAPI()
    Stub.units.npc = { name = NPC, guid = "Creature-0-4372-0-17-6740-0000A1B2C3" }
    if opts.present ~= false then
      frame = DUI.installQuestFrame({ without = opts.without })
      Stub.loadedAddons.DialogueUI = opts.loaded ~= false
    end
    WFJ = H.loadChunks(FILES)
    WFJ.QUEST_TITLES_JAPANESE = not opts.titlesOff
    WFJ.Compat.init(function(name) return _G[name] end)
    WFJ.Settings.load(nil, 1, {})
    collected = WFJ.Collector.load(nil, H.collectorDeps())
    data = {}
    WFJ.Render.init(WFJ.Translator.new({
      enabled = function() return WFJ.State.enabled end,
      areaEnabled = WFJ.State.areaEnabled,
      showsEnglish = WFJ.Modifier.english,
      kindOff = opts.titlesOff and function(kind) return kind == "quest.title" end or nil,
      lookup = function(kind, id)
        if opts.lookup then return opts.lookup(kind, id) end
        return data[kind] and data[kind][id]
      end,
      marker = function(n) return WFJ.Settings.get("marker." .. n) end,
    }))
    WFJ.LoadOnDemand.init(function(name) return C_AddOns.IsAddOnLoaded(name) end)
    logs = {}
    WFJ.Diag.log = function(kind, msg) logs[#logs + 1] = kind .. " " .. msg end
    caught = {}
    WFJ.ErrorLog = { recordCaught = function(msg) caught[#caught + 1] = msg end }
    shown = 0
    WFJ.State.on("lineShown", function() shown = shown + 1 end)
    WFJ.QuestMap.objectiveJapanese = function(en)
      if en == "Kobold Vermin slain: 3/10" then return "Kobold Verminを倒した: 3/10" end
      return nil
    end
    return WFJ.DialogueUI.init({ key = key })
  end

  local function open(event, page)
    for k, v in pairs(page) do DUI.page[k] = v end
    frame:ShowUI(event)
  end

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
    DUI.flush()
  end

  local QUEST = { questID = 2, title = "Sharptalon's Claw", description = "Greetings, Reyn. Go to Silverwind Refuge.",
    objectives = "Bring Sharptalon's Claw to Shandris.", progress = "Have you got it?", completion = "Well done." }
  local QUEST_JA = {
    ["quest.title"] = { [2] = "Sharptalonの鉤爪" },
    ["quest.description"] = { [2] = "ごきげんよう。Silverwind Refugeへ行け。" },
    ["quest.objectives"] = { [2] = "Sharptalonの鉤爪をShandrisに届けよ。" },
    ["quest.progress"] = { [2] = "手に入れたか？" },
    ["quest.completion"] = { [2] = "よくやった。" },
  }

  describe("finding Dialogue UI", function()
    it("does nothing at all when Dialogue UI is not installed", function()
      load({ present = false })
      local frames = #Stub.frames
      assert.is_false(WFJ.DialogueUI.installed())
      WFJ.LoadOnDemand.loaded("SomethingElse")
      assert.are.equal(frames, #Stub.frames)
      assert.are.same({}, logs)
    end)

    it("installs once when Dialogue UI was loaded first", function()
      assert.is_true(load())
      assert.is_true(WFJ.DialogueUI.installed())
      local wrapped = frame.FormatParagraph
      assert.is_false(WFJ.DialogueUI.install())
      assert.are.equal(wrapped, frame.FormatParagraph)
    end)

    it("installs when Dialogue UI loads after this addon", function()
      assert.is_false(load({ loaded = false }))
      assert.is_false(WFJ.DialogueUI.installed())
      Stub.loadedAddons.DialogueUI = true
      WFJ.LoadOnDemand.loaded("DialogueUI")
      assert.is_true(WFJ.DialogueUI.installed())
    end)

    it("installs nothing and logs one line when a member it relies on is missing", function()
      for _, member in ipairs(WFJ and WFJ.DialogueUI and WFJ.DialogueUI.MEMBERS or { "FormatParagraph" }) do
        load({ without = { member } })
        assert.is_false(WFJ.DialogueUI.installed(), member)
        assert.are.equal(1, #logs, member)
        assert.truthy(logs[1]:find(member, 1, true), member)
        ship({ gossip = { ["Hello, traveller."] = "ようこそ、旅の人。" } })
        if frame.HandleGossip and frame.ReleaseAllObjects and frame.FormatParagraph and frame.AcquireLeftFontString
            and frame.AcquireOptionButton then
          open("GOSSIP_SHOW", { gossip = "Hello, traveller." })
          assert.are.same({ "Hello, traveller." }, DUI.paragraphs(), member)
        end
      end
    end)

    it("lists the members it relies on", function()
      load()
      for _, m in ipairs({ "FormatParagraph", "FormatQuestText", "AcquireLeftFontString", "InsertText",
        "UpdateQuestTitle", "AcquireOptionButton", "ReleaseAllObjects", "OnSettingsChanged", "HandleGossip",
        "HandleQuestDetail", "HandleQuestProgress", "HandleQuestComplete", "HandleQuestGreeting" }) do
        local found = false
        for _, x in ipairs(WFJ.DialogueUI.MEMBERS) do if x == m then found = true end end
        assert.is_true(found, m)
      end
    end)
  end)

  describe("quest pages", function()
    before_each(function()
      load()
      ship(QUEST_JA)
    end)

    it("the offer shows the description and objectives in Japanese, in the bundled font when measured", function()
      open("QUEST_DETAIL", QUEST)
      assert.are.same({ "ごきげんよう。Silverwind Refugeへ行け。", "Sharptalonの鉤爪をShandrisに届けよ。" }, DUI.paragraphs())
      for _, fs in ipairs(frame.fontStringPool.active) do
        assert.are.equal(WFJ.Font.PATH, fs.measuredFont[1])
        assert.are.equal(14, fs.measuredFont[2])
      end
    end)

    it("a second quest on the same kind of page is laid out in the bundled font too", function()
      ship({ ["quest.progress"] = { [2] = "手に入れたか？", [3] = "二つ目のクエストの途中経過。" } })
      open("QUEST_PROGRESS", QUEST)
      open("QUEST_PROGRESS", { questID = 3, title = "Another", progress = "Second progress." })
      assert.are.same({ "二つ目のクエストの途中経過。" }, DUI.paragraphs())
      assert.are.equal(WFJ.Font.PATH, frame.fontStringPool.active[1].measuredFont[1])
    end)

    it("progress and turn-in pages show their text in Japanese", function()
      open("QUEST_PROGRESS", QUEST)
      assert.are.same({ "手に入れたか？" }, DUI.paragraphs())
      open("QUEST_COMPLETE", QUEST)
      assert.are.same({ "よくやった。" }, DUI.paragraphs())
    end)

    it("the title in the page header is the quest's Japanese title", function()
      open("QUEST_DETAIL", QUEST)
      assert.are.equal("Sharptalonの鉤爪", frame.FrontFrame.Header.Title:GetText())
      assert.are.equal(WFJ.Font.PATH, (frame.FrontFrame.Header.Title:GetFont()))
    end)

    it("with titles left to the client, the page header keeps the English title and the text is still Japanese",
    function()
      load({ titlesOff = true })
      ship(QUEST_JA)
      open("QUEST_DETAIL", QUEST)
      assert.are.equal(QUEST.title, frame.FrontFrame.Header.Title:GetText())
      assert.are_not.equal(WFJ.Font.PATH, (frame.FrontFrame.Header.Title:GetFont()))
      assert.is_truthy(#DUI.paragraphs() > 0)
      assert.are_not.equal(QUEST.description, DUI.paragraphs()[1])
    end)

    it("a description that is not the quest's own is looked up by its English", function()
      local other = "A different wording for Hunters."
      WFJ.ShippedGossipKey = function(en) return en == other and key(other) or nil end
      ship({ gossip = { [other] = "狩人向けの別の文面。" } })
      open("QUEST_DETAIL", { questID = 2, title = "Sharptalon's Claw", description = other, objectives = "" })
      assert.are.same({ "狩人向けの別の文面。" }, DUI.paragraphs())
    end)

    it("keeps Dialogue UI's English name prefix and looks the text up without it", function()
      open("QUEST_DETAIL", { questID = 2, description = QUEST.description, objectives = "", prefixName = true,
        npc = NPC, title = QUEST.title })
      assert.are.same({ NPC .. ": ごきげんよう。Silverwind Refugeへ行け。" }, DUI.paragraphs())
    end)

    it("objective lines on the progress page are Japanese where shipped, English otherwise", function()
      open("QUEST_PROGRESS", { questID = 2, title = QUEST.title, progress = QUEST.progress,
        progressLines = "- Kobold Vermin slain: 3/10\n- Kobold Workers slain: 0/10" })
      local p = DUI.paragraphs()
      assert.are.equal("- Kobold Verminを倒した: 3/10\n- Kobold Workers slain: 0/10", p[2])
      assert.are.equal(WFJ.Font.PATH, frame.fontStringPool.active[2].measuredFont[1])
    end)

    it("a quest with no Japanese shows the live English after the missing marker", function()
      ship({})
      open("QUEST_DETAIL", QUEST)
      local p = DUI.paragraphs()
      assert.truthy(p[1]:find(WFJ.MARKER.missing, 1, true))
      assert.are.equal(QUEST.description, p[2])
      assert.are.equal(QUEST.title, frame.FrontFrame.Header.Title:GetText()) -- a title carries no marker
    end)
  end)

  describe("gossip and greeting pages", function()
    before_each(function() load() end)

    it("the gossip text is Japanese, keeping a hint Dialogue UI put before it", function()
      ship({ gossip = { ["Greetings, Reyn. The spirits are restless."] = "ごきげんよう。精霊が騒がしい。" } })
      open("GOSSIP_SHOW", { gossip = "Greetings, Reyn. The spirits are restless.", hint = "Hint text." })
      assert.are.same({ "Hint text.", "ごきげんよう。精霊が騒がしい。" }, DUI.paragraphs())
    end)

    it("the quest greeting is Japanese", function()
      ship({ gossip = { ["Welcome to my farm."] = "我が農場へようこそ。" } })
      open("QUEST_GREETING", { greeting = "Welcome to my farm.", quests = {} })
      assert.are.same({ "我が農場へようこそ。" }, DUI.paragraphs())
    end)

    it("a stale gossip line shows the stale marker", function()
      ship({ gossip = { ["Hello."] = { "こんにちは。", "s" } } })
      open("GOSSIP_SHOW", { gossip = "Hello." })
      local p = DUI.paragraphs()
      assert.truthy(p[1]:find(WFJ.MARKER.stale, 1, true))
      assert.are.equal("こんにちは。", p[2])
    end)

    it("options and quest rows are Japanese with hotkeys and levels kept, in the bundled font", function()
      ship({ gossip = { ["Hello."] = "こんにちは。", ["Make this inn your home."] = "この宿を拠点にする。" },
        ["quest.title"] = { [5] = "狼退治" } })
      open("GOSSIP_SHOW", { gossip = "Hello.", options = { "Make this inn your home.", "Let me browse your goods." },
        quests = { { id = 5, title = "Wolves Across the Border", level = 4 }, { id = 6, title = "Untranslated" } } })
      assert.are.same({ "1. この宿を拠点にする。", "2. Let me browse your goods.", "[4] 狼退治", "Untranslated" },
        DUI.labels())
      assert.are.equal(WFJ.Font.PATH, frame.buttons[1].measuredFont[1])
      assert.are_not.equal(WFJ.Font.PATH, frame.buttons[2].measuredFont[1])
      assert.are_not.equal(WFJ.Font.PATH, frame.buttons[4].measuredFont[1])
      frame.buttons[3]:loadLater()
      assert.are.equal("[4] 狼退治", frame.buttons[3].Name:GetText())
    end)

    it("a Japanese option keeps the icon Dialogue UI picks by its English name", function()
      ship({ gossip = { ["Hello."] = "こんにちは。", ["Inn"] = "宿屋" } })
      open("GOSSIP_SHOW", { gossip = "Hello.", options = { "Inn" } })
      assert.are.equal("1. 宿屋", frame.buttons[1].Name:GetText())
      assert.are.equal("Inn", frame.buttons[1].iconFor)
    end)

    it("the English Collector hears Dialogue UI's lines as it hears the client's windows", function()
      ship({})
      open("GOSSIP_SHOW", { gossip = "Untranslated words.", options = { "Tell me more." } })
      assert.is_table(collected.entries["gossip:" .. key("Untranslated words.") .. ":text"])
      assert.is_table(collected.entries["gossip:" .. key("Tell me more.") .. ":text"])
      open("QUEST_DETAIL", QUEST)
      local found = false
      for k in pairs(collected.entries) do if k:find("^quest:2:") then found = true end end
      assert.is_true(found)
    end)

    it("a pooled row that showed Japanese gets Dialogue UI's font back for English", function()
      ship({ gossip = { ["Hello."] = "こんにちは。", ["Train me."] = "訓練してくれ。" } })
      open("GOSSIP_SHOW", { gossip = "Hello.", options = { "Train me." } })
      assert.are.equal(WFJ.Font.PATH, frame.buttons[1].measuredFont[1])
      open("GOSSIP_SHOW", { gossip = "Hello.", options = { "Goodbye." } })
      assert.are.equal("1. Goodbye.", frame.buttons[1].Name:GetText())
      assert.are_not.equal(WFJ.Font.PATH, frame.buttons[1].measuredFont[1])
    end)

    it("a paragraph FontString that showed Japanese gets Dialogue UI's font back for English", function()
      ship({ gossip = { ["Hello."] = "こんにちは。" } })
      open("GOSSIP_SHOW", { gossip = "Hello." })
      WFJ.Settings.set("marker.missing", false) -- the marker line itself is Japanese, in the bundled face
      open("GOSSIP_SHOW", { gossip = "Untranslated words." })
      local fs = frame.fontStringPool.active[1]
      assert.are.equal("Untranslated words.", fs.text)
      assert.are_not.equal(WFJ.Font.PATH, fs.measuredFont[1])
    end)
  end)

  describe("the reveal key and the switches", function()
    before_each(function()
      load()
      ship({ gossip = { ["Hello."] = "こんにちは。", ["Train me."] = "訓練してくれ。" } })
    end)

    it("holding the key redraws the page in the live English, letting go brings the Japanese back", function()
      open("GOSSIP_SHOW", { gossip = "Hello.", options = { "Train me." } })
      local lines = shown
      alt(true)
      assert.are.same({ "Hello." }, DUI.paragraphs())
      assert.are.same({ "1. Train me." }, DUI.labels())
      assert.are_not.equal(WFJ.Font.PATH, frame.fontStringPool.active[1].measuredFont[1])
      alt(false)
      assert.are.same({ "こんにちは。" }, DUI.paragraphs())
      assert.are.same({ "1. 訓練してくれ。" }, DUI.labels())
      assert.are.equal(lines, shown) -- no line was shown anew: no voice restarts
    end)

    it("the quest title follows the key too", function()
      ship(QUEST_JA)
      open("QUEST_DETAIL", QUEST)
      alt(true)
      assert.are.equal(QUEST.title, frame.FrontFrame.Header.Title:GetText())
      alt(false)
      assert.are.equal("Sharptalonの鉤爪", frame.FrontFrame.Header.Title:GetText())
    end)

    it("translation off or the gossip area off shows Dialogue UI's English; back on, Japanese", function()
      open("GOSSIP_SHOW", { gossip = "Hello.", options = { "Train me." } })
      WFJ.State.setEnabled(false)
      DUI.flush()
      assert.are.same({ "Hello." }, DUI.paragraphs())
      assert.are.same({ "1. Train me." }, DUI.labels())
      WFJ.State.setEnabled(true)
      DUI.flush()
      assert.are.same({ "こんにちは。" }, DUI.paragraphs())
      WFJ.State.setArea("gossip", false)
      DUI.flush()
      assert.are.same({ "Hello." }, DUI.paragraphs())
    end)

    it("keeps the reader's place when it redraws the page for the key", function()
      open("GOSSIP_SHOW", { gossip = "Hello.", options = { "Train me." } })
      frame.ScrollFrame.value = 120
      alt(true)
      assert.are.equal(120, frame.ScrollFrame.value)
      alt(false)
      assert.are.equal(120, frame.ScrollFrame.value)
      open("GOSSIP_SHOW", { gossip = "Hello." }) -- a page Dialogue UI draws itself starts at the top
      assert.are.equal(0, frame.ScrollFrame.value)
    end)

    it("a page of another kind in the same window shows its lines anew, as a new client window would", function()
      ship(QUEST_JA)
      ship({ gossip = { ["Hello."] = "こんにちは。" } })
      open("GOSSIP_SHOW", { gossip = "Hello." })
      local first = shown
      open("QUEST_DETAIL", QUEST)
      open("GOSSIP_SHOW", { gossip = "Hello." })
      assert.is_true(shown > first + 0)
      local again = shown
      frame:OnSettingsChanged() -- the same page drawn again: nothing shown anew
      DUI.flush()
      assert.are.equal(again, shown)
    end)

    it("a new page shows a line anew; closing the window lets the same line show anew next time", function()
      open("GOSSIP_SHOW", { gossip = "Hello." })
      local first = shown
      assert.is_true(first > 0)
      frame:Hide()
      open("GOSSIP_SHOW", { gossip = "Hello." })
      assert.is_true(shown > first)
    end)
  end)

  describe("word cards", function()
    local attached, detached
    before_each(function()
      load()
      attached, detached = {}, 0
      WFJ.ReadingView = {
        attach = function(rec) attached[#attached + 1] = rec; return true end,
        detach = function() detached = detached + 1 end,
      }
      WFJ.Readings = { lookup = function(kind, _, text)
        if kind ~= "gossip" then return nil end
        local at = text:find("精霊", 1, true)
        return at and { { first = at, last = at + 5, word = "精霊", reading = "せいれい" } } or nil
      end }
    end)

    it("each Japanese paragraph gets its share of the line's words", function()
      ship({ gossip = { ["Hello. The spirits wake."] = "こんにちは。\n\n精霊が目覚める。" } })
      open("GOSSIP_SHOW", { gossip = "Hello. The spirits wake." })
      local second = frame.fontStringPool.active[2]
      local rec
      for _, r in ipairs(attached) do if r.fs == second then rec = r end end
      assert.is_table(rec)
      assert.are.equal("精霊が目覚める。", rec.applied)
      assert.are.equal("dialogueui.gossip", rec.surface)
      assert.are.same({ { first = 1, last = 6, word = "精霊", reading = "せいれい" } }, rec.spans)
    end)

    it("the reading box and card go under Dialogue UI's window, which sits outside UIParent", function()
      local ui = CreateFrame("Frame", "UIParent")
      local function parented(f, p)
        f.parent = p
        function f:GetParent() return self.parent end
        return f
      end
      parented(frame, nil)
      local inDui = parented(CreateFrame("Frame"), frame)
      local inUi = parented(CreateFrame("Frame"), parented(CreateFrame("Frame"), ui))
      H.loadChunk("UI/Readings.lua", nil, WFJ)
      local View = WFJ.ReadingView
      assert.are.equal(frame, View.host(inDui))
      assert.are.equal(ui, View.host(inUi))
    end)

    it("no cards while English shows", function()
      ship({ gossip = { ["Hello. The spirits wake."] = "こんにちは。\n\n精霊が目覚める。" } })
      open("GOSSIP_SHOW", { gossip = "Hello. The spirits wake." })
      local n = #attached
      alt(true)
      assert.are.equal(n, #attached)
      assert.is_true(detached > 0)
    end)
  end)

  describe("the game's own words around the page", function()
    -- the client's interface strings this page shows, as the interface index the addon builds from them
    local function game(words)
      local function h1(text) return (WFJ.Hash.h32x2(WFJ.Normalize.v1(text))) end
      local rows = {}
      data.ui = data.ui or {}
      for k, pair in pairs(words) do
        _G[k] = pair[1]
        rows[k] = { pair[2], h1(pair[1]), "." }
        data.ui[k] = { ja = pair[2], status = "." }
      end
      WFJ.UIIndex = WFJ.UIStrings.build({ rows = rows, hash = h1, english = function(k) return _G[k] end })
    end
    local WORDS = { GOODBYE = { "Goodbye", "さようなら" }, TRACKER_HEADER_OBJECTIVE = { "Objectives", "目標" },
      REWARD_CHOICES = { "You will be able to choose one of these rewards:", "以下の報酬から1つ選択できます:" },
      REWARD_ITEMS = { "You will also receive:", "さらに以下を受け取ります:" },
      LFG_TYPE_DUNGEON = { "Dungeon", "ダンジョン" }, ITEM_BIND_QUEST = { "Quest Item", "クエストアイテム" },
      STAT_AVERAGE_ITEM_LEVEL = { "Item Level", "アイテムレベル" }, SELL_PRICE = { "Sell Price", "売値" } }

    before_each(function()
      load()
      ship(QUEST_JA)
      game(WORDS)
    end)
    after_each(function()
      for k in pairs(WORDS) do _G[k] = nil end
    end)

    it("a button whose label is a game word shows its Japanese, and the English while the key is held", function()
      ship({ gossip = { ["Hello."] = "こんにちは。" } })
      game(WORDS)
      open("GOSSIP_SHOW", { gossip = "Hello." })
      assert.are.equal("さようなら", frame.ExitButton.Name:GetText())
      assert.are.equal(WFJ.Font.PATH, frame.ExitButton.measuredFont[1])
      alt(true)
      assert.are.equal("Goodbye", frame.ExitButton.Name:GetText())
    end)

    it("headings: a game word in Japanese, Requirements in the addon's own word, each band sized again", function()
      open("QUEST_DETAIL", { questID = 2, title = QUEST.title, description = QUEST.description, objectives = "",
        headings = { "Objectives", "Requirements", "Costs" } })
      local h = frame.headings
      assert.are.equal("目標", h[1].fs:GetText())
      assert.are.equal(WFJ.Font.PATH, (h[1].fs:GetFont()))
      assert.are.equal(#"目標" * 4 + 16, h[1].width)
      assert.are.equal("必要なもの", h[2].fs:GetText())
      assert.are.equal("Costs", h[3].fs:GetText()) -- not a game word here: Dialogue UI's own, left as it is
    end)

    it("the reward lines and the reward list's heading show their Japanese", function()
      open("QUEST_DETAIL", { questID = 2, title = QUEST.title, description = QUEST.description, objectives = "",
        rewardLine = "You will be able to choose one of these rewards:", rewardsHeader = "You will also receive:" })
      local texts = DUI.paragraphs()
      assert.are.equal("以下の報酬から1つ選択できます:", texts[2])
      assert.are.equal("さらに以下を受け取ります:", texts[3])
      assert.are.equal(WFJ.Font.PATH, frame.fontStringPool.active[3].font.path)
    end)

    it("the tag over the title shows its Japanese", function()
      open("QUEST_DETAIL", { questID = 2, title = QUEST.title, description = QUEST.description, objectives = "",
        tag = "Dungeon" })
      assert.are.equal("ダンジョン", frame.tag.ButtonText:GetText())
    end)

    it("a tag Dialogue UI adds after the page drew (its quest data came late) shows its Japanese too", function()
      open("QUEST_DETAIL", { questID = 2, title = QUEST.title, description = QUEST.description, objectives = "" })
      assert.are.equal("", frame.tag.ButtonText:GetText())
      frame.tag:SetQuestTagNameAndIcon("Dungeon")
      assert.are.equal("ダンジョン", frame.tag.ButtonText:GetText())
      frame.tag:SetQuestTagNameAndIcon("Something Else") -- not a game word: as written
      assert.are.equal("Something Else", frame.tag.ButtonText:GetText())
    end)

    -- In game the tag's Japanese showed as empty boxes: drawn in Dialogue UI's own face, which has no Japanese letters
    it("the tag's Japanese wears the bundled face, also when Dialogue UI applies its font object after the text",
      function()
        open("QUEST_DETAIL", { questID = 2, title = QUEST.title, description = QUEST.description, objectives = "",
          tag = "Dungeon" })
        assert.are.equal(WFJ.Font.PATH, (frame.tag.ButtonText:GetFont()))
        frame.tag:SetQuestTagNameAndIcon("Dungeon")
        assert.are.equal("ダンジョン", frame.tag.ButtonText:GetText())
        assert.are.equal(WFJ.Font.PATH, (frame.tag.ButtonText:GetFont()))
      end)

    it("a tag whose face Dialogue UI puts back after it was laid out gets the bundled face again the next frame, " ..
      "and the log says what face it had", function()
        open("QUEST_DETAIL", { questID = 2, title = QUEST.title, description = QUEST.description, objectives = "",
          tag = "Dungeon" })
        local fs = frame.tag.ButtonText
        fs.font = { path = _G.DUIFont_Item.font.path, size = 10, flags = "" } -- the face lost after our pass
        DUI.flush()
        assert.are.equal("ダンジョン", fs:GetText())
        assert.are.equal(WFJ.Font.PATH, (fs:GetFont()))
        local found = false
        for _, l in ipairs(logs) do if l:find("dialogueui tag face", 1, true) then found = true end end
        assert.is_true(found)
      end)

    -- A tag button keeps its text when Dialogue UI is done with it, and every later page's pass walks it again: the
    -- text is then our Japanese, which is no game word, and the pass must not hand Dialogue UI's face back.
    it("a tag already showing our Japanese keeps the bundled face when a later pass walks it, before any timer runs",
      function()
        open("QUEST_DETAIL", { questID = 2, title = QUEST.title, description = QUEST.description, objectives = "" })
        frame.tag:SetQuestTagNameAndIcon("Dungeon")
        local fs = frame.tag.ButtonText
        assert.are.equal("ダンジョン", fs:GetText())
        DUI.timers = {} -- the next-frame check never runs: the pass itself has to leave the face alone
        open("GOSSIP_SHOW", { gossip = "Hello." })
        assert.are.equal("ダンジョン", fs:GetText())
        assert.are.equal(WFJ.Font.PATH, (fs:GetFont()))
      end)

    it("tooltip lines: game strings and Dialogue UI's own words in Japanese; the item's name never", function()
      load({ loaded = false })
      ship(QUEST_JA)
      game(WORDS)
      local tip = DUI.installTooltip() -- made at Dialogue UI's load, before this addon installs
      Stub.loadedAddons.DialogueUI = true
      WFJ.LoadOnDemand.loaded("DialogueUI")
      tip:AddLeftLine("Quest Item") -- an item named like a game string stays as it is: the first line is the name
      tip:AddLeftLine("Quest Item")
      tip:AddLeftLine("Sell Price  72c")
      tip:AddLeftLine("|cffffd100Replace|r |cff1eff00|Hitem:1|h[Cilice of Regret]|h|r")
      tip:AddLeftLine("Replace this belt when you find a better one.") -- a description, left alone
      tip:AddLeftLine("|cff20ff20+3|r Item Level")
      tip:AddLeftLine("Hide Comparison")
      tip:AddLeftLine("Something else")
      assert.are.same({ "Quest Item", "クエストアイテム", "売値  72c",
        "|cffffd100交換:|r |cff1eff00|Hitem:1|h[Cilice of Regret]|h|r",
        "Replace this belt when you find a better one.",
        "アイテムレベル |cff20ff20+3|r", "比較を隠す", "Something else" }, tip:texts())
    end)

    it("an item's effect lines show the item's Japanese as one run, as the game's tooltip shows them", function()
      load({ loaded = false })
      ship({ ["item.description"] = { [6948] = "使用：Hearthstoneの場所に戻ります。",
        [7000] = "装備：Staminaが5上昇します。\n使用：10秒間、移動速度が上がります。" } })
      game(WORDS)
      local tip = DUI.installTooltip()
      -- Dialogue UI's own reader of the client's tooltip data: one line per data line [read: Tooltip_Private.lua,
      -- ProcessTooltipDataLines]
      function tip:ProcessTooltipData(tipData)
        self.numLines, self.grid, self.tooltipData = 0, {}, tipData
        for _, line in ipairs(tipData.lines) do self:AddLeftLine(line.leftText) end
        return true
      end
      Stub.loadedAddons.DialogueUI = true
      WFJ.LoadOnDemand.loaded("DialogueUI")
      local item = { isItem = true, id = 6948, lines = { { leftText = "Hearthstone" },
        { leftText = "Use: Returns you to Darnassus. Speak to an Innkeeper in a different place to change your home"
          .. " location." }, { leftText = "Quest Item" } } }
      tip:ProcessTooltipData(item)
      assert.are.same({ "Hearthstone", "使用：Hearthstoneの場所に戻ります。", "クエストアイテム" }, tip:texts())
      -- the Japanese lines wear the bundled face (Dialogue UI's own has no Japanese letters); the name keeps its own
      local function ours(t)
        local out = {}
        for i = 1, t.numLines do out[i] = (t.grid[i][1]:GetFont()) == WFJ.Font.PATH end
        return out
      end
      assert.are.same({ false, true, true }, ours(tip))
      assert.is_true(tip.fontChanged)
      -- Dialogue UI's data is never changed: it reads it again on its own updates
      assert.are.equal("Use: Returns you to Darnassus. Speak to an Innkeeper in a different place to change your"
        .. " home location.", item.lines[2].leftText)
      -- a run of two effect lines: the Japanese on the first, the second gone, as on the game's tooltip
      tip:ProcessTooltipData({ isItem = true, id = 7000, lines = { { leftText = "Belt of Haste" },
        { leftText = "Equip: +5 Stamina." }, { leftText = "Use: Increases run speed for 10 sec." } } })
      assert.are.same({ "Belt of Haste", "装備：Staminaが5上昇します。\n使用：10秒間、移動速度が上がります。" },
        tip:texts())
      -- no Japanese for the item, the reveal key held, or not an item: the lines as the client wrote them
      tip:ProcessTooltipData({ isItem = true, id = 8000, lines = { { leftText = "Rock" },
        { leftText = "Use: Throw it." } } })
      assert.are.same({ "Rock", "Use: Throw it." }, tip:texts())
      assert.are.same({ false, false }, ours(tip))
      Stub.keys.alt = true
      WFJ.Modifier.refresh()
      tip:ProcessTooltipData(item)
      assert.are.equal("Use: Returns you to Darnassus. Speak to an Innkeeper in a different place to change your"
        .. " home location.", tip:texts()[2])
      assert.are.same({ false, false, false }, ours(tip))
      Stub.keys.alt = false
      WFJ.Modifier.refresh()
      tip:ProcessTooltipData({ isSpell = true, id = 6948, lines = { { leftText = "Hearth" },
        { leftText = "Use: Returns you home." } } })
      assert.are.equal("Use: Returns you home.", tip:texts()[2])
    end)

    it("the effect line's face: Dialogue UI's again on a reused line, and ours only inside the data pass", function()
      load({ loaded = false })
      ship({ ["item.description"] = { [6948] = "使用：Hearthstoneの場所に戻ります。" } })
      game(WORDS)
      local tip = DUI.installTooltip()
      local pool = {}
      -- Dialogue UI keeps its lines and uses them again [read: Tooltip_Base.lua, AcquireFontString]
      function tip:AddLeftLine(text)
        self.numLines = self.numLines + 1
        local fs = pool[self.numLines] or Stub.fontString("")
        pool[self.numLines] = fs
        fs:SetText(text)
        self.grid = self.grid or {}
        self.grid[self.numLines] = { fs }
        return fs
      end
      function tip:ProcessTooltipData(tipData)
        self.numLines, self.grid, self.tooltipData = 0, {}, tipData
        for _, line in ipairs(tipData.lines) do self:AddLeftLine(line.leftText) end
        return true
      end
      Stub.loadedAddons.DialogueUI = true
      WFJ.LoadOnDemand.loaded("DialogueUI")
      tip:ProcessTooltipData({ isItem = true, id = 6948, lines = { { leftText = "Hearthstone" },
        { leftText = "Use: Returns you home." } } })
      assert.are.equal("使用：Hearthstoneの場所に戻ります。", pool[2]:GetText())
      assert.are.equal(WFJ.Font.PATH, (pool[2]:GetFont()))
      -- the Japanese of a data pass is ours only during that pass: the same text written right after it is not
      tip:AddLeftLine("使用：Hearthstoneの場所に戻ります。")
      assert.are_not.equal(WFJ.Font.PATH, (pool[3]:GetFont()))
      -- Dialogue UI redraws from the data it kept, which is the copy it was given (its comparison toggle): the
      -- Japanese line and its face again, and the reveal key still reaches the client's English
      local kept = tip.tooltipData
      tip:ProcessTooltipData(kept)
      assert.are.equal("使用：Hearthstoneの場所に戻ります。", pool[2]:GetText())
      assert.are.equal(WFJ.Font.PATH, (pool[2]:GetFont()))
      Stub.keys.alt = true
      WFJ.Modifier.refresh()
      tip:ProcessTooltipData(kept)
      assert.are.equal("Use: Returns you home.", pool[2]:GetText())
      Stub.keys.alt = false
      WFJ.Modifier.refresh()
      tip:ProcessTooltipData(kept)
      assert.are.equal(WFJ.Font.PATH, (pool[2]:GetFont()))
      -- the same line, next for an item with no Japanese: Dialogue UI's face again, and the tooltip is told
      tip.fontChanged = false
      tip:ProcessTooltipData({ isItem = true, id = 8000, lines = { { leftText = "Rock" },
        { leftText = "Use: Throw it." } } })
      assert.are.equal("Use: Throw it.", pool[2]:GetText())
      assert.are_not.equal(WFJ.Font.PATH, (pool[2]:GetFont()))
      assert.is_true(tip.fontChanged)
      -- Dialogue UI's own error inside a pass is raised again, and the pass's Japanese is forgotten all the same
      local fail = true
      local add = tip.AddLeftLine
      function tip:AddLeftLine(text, ...)
        local fs = add(self, text, ...)
        if fail and self.numLines == 2 then error("Dialogue UI's own error") end
        return fs
      end
      assert.has_error(function()
        tip:ProcessTooltipData({ isItem = true, id = 6948, lines = { { leftText = "Hearthstone" },
          { leftText = "Use: Returns you home." } } })
      end)
      fail = false
      tip:AddLeftLine("使用：Hearthstoneの場所に戻ります。")
      assert.are_not.equal(WFJ.Font.PATH, (pool[3]:GetFont()))
    end)

    it("an open tooltip is built again by its own update when the key is held, and a popup is retitled", function()
      load({ loaded = false })
      ship(QUEST_JA)
      game(WORDS)
      local tip = DUI.installTooltip()
      tip.tooltipInfo = {}
      function tip:ProcessInfo() -- Dialogue UI's update: its lines again from the item's data
        self.numLines, self.grid = 0, {}
        self:AddLeftLine("Belt")
        self:AddLeftLine("Quest Item")
        self:AddRightLine("Mail")
      end
      DUI.questNames[2] = "Sharptalon's Claw"
      local popup = DUI.makePopup()
      Stub.loadedAddons.DialogueUI = true
      WFJ.LoadOnDemand.loaded("DialogueUI")
      tip:Show()
      tip:ProcessInfo()
      popup:SetQuestDataByID(2)
      assert.are.equal("クエストアイテム", tip:texts()[2])
      assert.are.equal("Sharptalonの鉤爪", popup.Title:GetText())
      Stub.keys.alt = true
      WFJ.Modifier.refresh()
      assert.are.equal("Quest Item", tip:texts()[2])
      assert.are.equal("Sharptalon's Claw", popup.Title:GetText())
      Stub.keys.alt = false
      WFJ.Modifier.refresh()
      assert.are.equal("クエストアイテム", tip:texts()[2])
    end)

    it("with titles left to the client, the flyout keeps the English title over the Japanese turn-in text", function()
      load({ loaded = false, titlesOff = true })
      ship({ ["quest.title"] = { [2] = "Sharptalonの鉤爪" },
        ["quest.completion"] = { [2] = "よくやった。\n\nこれで安心だ。" } })
      game(WORDS)
      local fly = DUI.makeFlyout()
      Stub.loadedAddons.DialogueUI = true
      WFJ.LoadOnDemand.loaded("DialogueUI")
      fly.questData = { questID = 2, rawText = "Well done, $N.$B$BNow we are safe." }
      fly:SetQuestText("Sharptalon's Claw", { "Well done, Reyn.", "Now we are safe." })
      assert.are.equal("Sharptalon's Claw", fly.Title:GetText())
      assert.are.same({ "よくやった。", "これで安心だ。" }, fly:paragraphs())
    end)

    it("the quest-complete flyout shows the quest's Japanese name and turn-in text, measured in the bundled face",
      function()
      load({ loaded = false })
      ship({ ["quest.title"] = { [2] = "Sharptalonの鉤爪" },
        ["quest.completion"] = { [2] = "よくやった。\n\nこれで安心だ。" } })
      game(WORDS)
      local fly = DUI.makeFlyout()
      Stub.loadedAddons.DialogueUI = true
      WFJ.LoadOnDemand.loaded("DialogueUI")
      local en = "Well done, $N.$B$BNow we are safe."
      fly.questData = { questID = 2, rawText = en }
      fly:SetQuestText("Sharptalon's Claw", { "Well done, Reyn.", "Now we are safe." })
      assert.are.equal("Sharptalonの鉤爪", fly.Title:GetText())
      assert.are.same({ "よくやった。", "これで安心だ。" }, fly:paragraphs())
      assert.are.same({ WFJ.Font.PATH, WFJ.Font.PATH }, fly.measuredIn)
      -- an error alert, no Japanese, or the key held: the flyout's own text
      fly.questData = { questID = 2, rawText = en, isError = true }
      fly:SetQuestText("Sharptalon's Claw", { "Quest failed." })
      assert.are.same({ "Quest failed." }, fly:paragraphs())
      fly.questData = { questID = 9, rawText = "Thanks." }
      fly:SetQuestText("Other Quest", { "Thanks." })
      assert.are.equal("Other Quest", fly.Title:GetText())
      assert.are.same({ "Thanks." }, fly:paragraphs())
      Stub.keys.alt = true
      WFJ.Modifier.refresh()
      fly.questData = { questID = 2, rawText = en }
      fly:SetQuestText("Sharptalon's Claw", { "Well done, Reyn.", "Now we are safe." })
      assert.are.equal("Sharptalon's Claw", fly.Title:GetText())
      assert.are.same({ "Well done, Reyn.", "Now we are safe." }, fly:paragraphs())
      Stub.keys.alt = false
      WFJ.Modifier.refresh()
    end)

    it("a flyout Dialogue UI made and wrote before it was found is written again in Japanese and laid out", function()
      load({ loaded = false })
      ship({ ["quest.title"] = { [2] = "Sharptalonの鉤爪" },
        ["quest.completion"] = { [2] = "よくやった。\n\nこれで安心だ。" } })
      game(WORDS)
      local fly, hidden = DUI.makeFlyout(), DUI.makeFlyout()
      local laidOut = 0
      fly.Layout = function() laidOut = laidOut + 1 end
      for _, f in ipairs({ fly, hidden }) do
        f.questData = { questID = 2, rawText = "Well done, $N.$B$BNow we are safe.", title = "Sharptalon's Claw",
          paragraphs = { "Well done, Reyn.", "Now we are safe." } }
        f:SetQuestText(f.questData.title, f.questData.paragraphs)
      end
      fly:Show()
      hidden:Hide()
      Stub.loadedAddons.DialogueUI = true
      WFJ.LoadOnDemand.loaded("DialogueUI")
      DUI.flush()
      assert.are.equal("Sharptalonの鉤爪", fly.Title:GetText())
      assert.are.same({ "よくやった。", "これで安心だ。" }, fly:paragraphs())
      assert.are.equal(1, laidOut)
      -- one not on screen is left as it is: it is written again when it next shows
      assert.are.equal("Sharptalon's Claw", hidden.Title:GetText())
    end)

    it("the chat panel shows an NPC's line in the chat window's Japanese, English while the key is held", function()
      load({ loaded = false })
      local panel = DUI.installChatPanel()
      Stub.loadedAddons.DialogueUI = true
      WFJ.LoadOnDemand.loaded("DialogueUI")
      WFJ.Speech = { translate = function(en) return en == "Stay alert!" and "油断するな！" or nil end }
      panel:AddMessage("Stay alert!", "Guard", "CHAT_MSG_MONSTER_SAY")
      assert.are.equal("油断するな！", panel.lines[1][1])
      assert.are.equal(WFJ.Font.PATH, (_G.DUIFont_ChatFont:GetFont()))
      Stub.keys.alt = true
      WFJ.Modifier.refresh()
      panel:AddMessage("Stay alert!", "Guard", "CHAT_MSG_MONSTER_SAY")
      assert.are.equal("Stay alert!", panel.lines[2][1])
      panel:AddMessage("Unknown words.", "Guard", "CHAT_MSG_MONSTER_SAY")
      assert.are.equal("Unknown words.", panel.lines[3][1])
    end)

    it("with titles left to the client, a quest popup keeps the English title", function()
      load({ titlesOff = true })
      ship({ ["quest.title"] = { [2] = "Sharptalonの鉤爪" } })
      DUI.questNames[2] = "Sharptalon's Claw"
      local popup = DUI.makePopup()
      Stub.fireAll("QUEST_ACCEPTED", 2)
      DUI.flush()
      popup:SetQuestDataByID(2)
      assert.are.equal("Sharptalon's Claw", popup.Title:GetText())
    end)

    it("a quest popup made after install is found after a quest event and shows the Japanese title", function()
      DUI.questNames[2] = "Sharptalon's Claw"
      local popup = DUI.makePopup()
      Stub.fireAll("QUEST_ACCEPTED", 2)
      DUI.flush()
      popup:SetQuestDataByID(2)
      assert.are.equal("Sharptalonの鉤爪", popup.Title:GetText())
    end)

    it("the voice panel is lifted out of the faded interface while a Dialogue UI window is open", function()
      local lifts = {}
      WFJ.VoicePanel = { lift = function(on) lifts[#lifts + 1] = on end }
      open("GOSSIP_SHOW", { gossip = "Hello." })
      frame:Hide()
      assert.are.same({ true, false }, { lifts[#lifts - 1], lifts[#lifts] })
    end)

    it("an option named like a game string keeps its own Japanese; Goodbye's face comes off for English", function()
      ship({ gossip = { ["Hello."] = "こんにちは。", ["Goodbye"] = "また会おう" } })
      game(WORDS)
      open("GOSSIP_SHOW", { gossip = "Hello.", options = { "Goodbye" } })
      assert.are.equal("1. また会おう", frame.buttons[1].Name:GetText())
      assert.are.equal("さようなら", frame.ExitButton.Name:GetText())
      alt(true)
      assert.are_not.equal(WFJ.Font.PATH, frame.ExitButton.measuredFont[1])
    end)

    it("an NPC emote whose Japanese holds another % stays English (Dialogue UI formats it)", function()
      load({ loaded = false })
      local panel = DUI.installChatPanel()
      Stub.loadedAddons.DialogueUI = true
      WFJ.LoadOnDemand.loaded("DialogueUI")
      WFJ.Speech = { translate = function() return "%sが50%の力で叫ぶ。" end }
      panel:AddMessage("%s shouts at half strength.", "Ogre", "CHAT_MSG_MONSTER_EMOTE")
      assert.are.equal("%s shouts at half strength.", panel.lines[1][1])
    end)

    it("a scan that fails on a frame starts again from the first frame next time", function()
      local calls = 0
      local real = _G.EnumerateFrames
      _G.EnumerateFrames = function(prev)
        calls = calls + 1
        if calls == 2 then error("forbidden") end
        return real(prev)
      end
      assert.has_no.errors(function()
        frame:Hide()
        frame:Show()
        DUI.flush()
      end)
      assert.is_true(WFJ.DialogueUI.active())
      _G.EnumerateFrames = real
    end)

    it("an install that fails half way leaves Dialogue UI's English and raises nothing", function()
      load({ loaded = false })
      _G.hooksecurefunc = function() error("boom") end
      Stub.loadedAddons.DialogueUI = true
      assert.has_no.errors(function() WFJ.LoadOnDemand.loaded("DialogueUI") end)
      assert.is_false(WFJ.DialogueUI.installed())
      assert.is_true(#caught >= 1)
    end)
  end)

  describe("fault isolation", function()
    it("a failing lookup leaves Dialogue UI's English and records the error", function()
      load({ lookup = function() error("boom") end })
      open("GOSSIP_SHOW", { gossip = "Hello." })
      assert.are.same({ "Hello." }, DUI.paragraphs())
      assert.is_true(#caught >= 1)
    end)

    it("after repeated errors it stops changing text for the session", function()
      local fail = true
      load({ lookup = function(kind)
        if fail then error("boom") end
        return kind == "gossip" and { ja = "こんにちは。", status = "." } or nil
      end })
      for _ = 1, 6 do open("GOSSIP_SHOW", { gossip = "Hello." }) end
      fail = false
      open("GOSSIP_SHOW", { gossip = "Hello." })
      assert.are.same({ "Hello." }, DUI.paragraphs())
      assert.is_false(WFJ.DialogueUI.active())
    end)
  end)

  describe("voice", function()
    local played
    before_each(function()
      load()
      ship(QUEST_JA)
      played = {}
      _G.PlaySoundFile = function(path) played[#played + 1] = path; return true, #played end
      _G.StopSound = function() end
      WFJ.Settings.set("voice.enabled", true)
    end)

    it("the offer, progress, turn-in, greeting and gossip lines of Dialogue UI are voice kinds", function()
      local K = WFJ.Voice.KINDS
      assert.are.equal("voice.offer", K["dialogueui.detail"].description)
      assert.are.equal("voice.progress", K["dialogueui.progress"].progress)
      assert.are.equal("voice.turnin", K["dialogueui.reward"].completion)
      assert.are.equal("voice.greeting", K["dialogueui.greeting"].greeting)
      assert.are.equal("voice.greeting", K["dialogueui.gossip"].greeting)
      assert.are.equal("voice.books", K["dialogueui.book"].page) -- each page's record: "page1", "page2", …
      assert.are_not.equal("kind", select(2, WFJ.Voice.decide("dialogueui.book", "page2", "book", "0123456789abcdef")))
      assert.are.equal("kind", select(2, WFJ.Voice.decide("gossip", "option.1", "gossip", "0123456789abcdef")))
      assert.is_nil(K["dialogueui.detail"].objectives)
      assert.is_nil(K["dialogueui.title"])
    end)

    it("the offer plays from Dialogue UI's window, shows its replay control, and stops when it hides", function()
      WFJ.Settings.set("voice.panel.size", "off") -- no queue: a closed window stops its line
      WFJ.Voice.init({
        lookup = function(kind, id) return data[kind] and data[kind][id] end,
        hash = WFJ.Hash.key,
        setting = WFJ.Settings.get,
        revealed = WFJ.Modifier.isDown,
        enabled = function() return WFJ.State.enabled end,
      })
      WFJ.Voice.register({ format = 1, folder = "WoWForeverJapanese_Voice", lines = {
        ["2-description"] = { "2-description.mp3", WFJ.Hash.key(QUEST_JA["quest.description"][2]), 4 } } })
      WFJ.VoiceQueue.init({})
      WFJ.VoicePlayer.init({})
      open("QUEST_DETAIL", QUEST)
      assert.are.same({ "Interface\\AddOns\\WoWForeverJapanese_Voice\\Sound\\2-description.mp3" }, played)
      assert.are.equal("2-description", WFJ.VoicePlayer.current())
      assert.is_true(WFJ.VoicePlayer.button("DUIQuestFrame"):IsShown())
      frame:Hide()
      assert.is_nil(WFJ.VoicePlayer.current())
      assert.is_false(WFJ.VoicePlayer.button("DUIQuestFrame"):IsShown())
    end)

    it("a line shown in Dialogue UI's window is voiced as the window's line, by the quest giver", function()
      WFJ.VoiceQueue.init({})
      WFJ.VoicePlayer.init({})
      assert.are.equal("DUIQuestFrame", WFJ.VoicePlayer.windowOf("dialogueui.detail"))
      assert.are.equal("DUIQuestFrame", WFJ.VoicePlayer.windowOf("dialogueui.gossip"))
      assert.are.equal("QuestFrame", WFJ.VoicePlayer.windowOf("questframe.detail"))
      assert.are.equal(6740, WFJ.VoicePlayer.speaker("DUIQuestFrame").creature)
    end)
  end)
end)
