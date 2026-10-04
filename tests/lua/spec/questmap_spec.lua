local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local QStub = require("tests.lua.spec.stub_questmap")

-- The camelot quest map's details pane, the tracker popup, the quest list and tracker titles, and
-- their fixed words, on a Forever-shaped stub. UI/QuestFrame keeps the one QuestInfo_Display hook.
local FILES = {}
for _, f in ipairs(H.UI_FILES) do FILES[#FILES + 1] = f end
FILES[#FILES + 1] = "UI/QuestFrame.lua"
FILES[#FILES + 1] = "UI/QuestMap.lua"

local DATA = {
  ["quest.title"] = { [2] = { ja = "Sharptalonの鉤爪", status = "." }, [5] = { ja = "狼の毛皮", status = "." },
    [6] = { ja = "失われた書物", status = "." } },
  ["quest.objectives"] = { [5] = { ja = "狼の毛皮を8枚集めよ。", status = "." } },
  ["quest.description"] = { [5] = { ja = "森の狼が増えている。", status = "." },
    [2] = { ja = "Silverwind Refugeの説明文", status = "." } },
}

local UI = {
  -- BACK is excluded (its English is INVTYPE_CLOAK's); the cloak slot is in the dictionary
  INVTYPE_CLOAK = { "Back", "背中" }, ACCEPT = { "Accept", "受ける" }, REWARDS = { "Rewards", "報酬" },
  ABANDON_QUEST_ABBREV = { "Abandon", "放棄" },
  SHARE_QUEST_ABBREV = { "Share", "共有" }, TRACK_QUEST_ABBREV = { "Track", "追跡" },
  UNTRACK_QUEST_ABBREV = { "Untrack", "追跡解除" }, QUEST_DESCRIPTION = { "Description", "説明" },
  QUEST_OBJECTIVES = { "Quest Objectives", "クエストの目的" }, SHOW_MAP = { "Show Map", "地図を表示" },
  -- the empty list's text carries the available-quest icon, kept verbatim in the Japanese
  QUEST_LOG_NO_QUESTS = { "No quests available|n|nAccept quests by talking to characters with a "
    .. "|TInterface\\GossipFrame\\AvailableQuestIcon:16:16|t above their head.", "受注中のクエストはありません|n|n頭上に"
    .. "|TInterface\\GossipFrame\\AvailableQuestIcon:16:16|tが表示されているキャラクターに話しかけると、クエストを受注できます。" },
  QUEST_WAYPOINT_FINAL = { "Show Final Destination", "最終目的地を表示" },
  QUEST_WAYPOINT_ROUTE = { "Show Travel Route", "移動経路を表示" },
  TRACKER_HEADER_QUESTS = { "Quests", "クエスト" }, TRACKER_ALL_OBJECTIVES = { "All Objectives", "すべての目標" },
  QUEST_LOG_NO_RESULTS = { "No results found", "見つかりません" },
  SEARCH_QUEST_LOG = { "Search Quest Log", "クエストログを検索" },
  QUEST_LOG_COUNT_TEMPLATE = { "Quests: %s%d|r|cffffffff/%d|r", "クエスト: %s%d|r|cffffffff/%d|r" },
  REWARD_CHOICES = { "You will be able to choose one of these rewards:", "次の報酬から1つ選べる:" },
  REWARD_ITEMS_ONLY = { "You will receive:", "受け取る報酬:" },
  REWARD_TITLE = { "You shall be granted the title:", "次の称号を授かる:" },
}

local QUEST5 = { title = "Wolf Pelts", description = "The wolves of the forest grow bold.",
  objectives = "Collect 8 Wolf Pelts.", level = 10 }
local QUEST6 = { title = "The Lost Tome", description = "A book is missing.", objectives = "Find the tome.",
  level = 12, elite = true }
local QUEST7 = { title = "Untranslated Errand", description = "Nobody wrote this.", objectives = "Run.", level = 3 }

describe("UI/QuestMap: the camelot quest log", function()
  local WFJ, SS, QM, Q

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    Q = QStub.install()
    local function copy(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end
    Q.quests[5], Q.quests[6], Q.quests[7] = copy(QUEST5), copy(QUEST6), copy(QUEST7)
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI, { lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end })
    SS, QM = WFJ.SurfaceState, WFJ.QuestMap
    assert.is_true(WFJ.QuestFrame.init())
    assert.is_true(QM.init())
  end)

  after_each(function() H.uiTeardown() end)

  describe("the details pane and the popup", function()
    it("renders the selected quest's title, objectives and description on the map's details pane", function()
      Q.showDetails(5)
      assert.are.equal("狼の毛皮", QuestInfoTitleHeader:GetText())
      assert.are.equal("狼の毛皮を8枚集めよ。", QuestInfoObjectivesText:GetText())
      assert.are.equal("森の狼が増えている。", QuestInfoDescriptionText:GetText())
      assert.is_table(SS.get(QM.INFO, "title"))
      assert.are.equal(0, SS.count(QM.POPUP_INFO))
      assert.is_true(_G.QuestMapDetailsScrollFrame.calls.UpdateScrollChildRect > 0) -- the pane's refit
    end)

    it("waits for the rewards before refitting, and an error in the client's scroll callback is not raised",
      function()
        -- QuestInfo_GetNumRewardRows reads rewardsFrame.numRows, nil until the client has shown the rewards
        _G.QuestInfoFrame = _G.QuestInfoFrame or CreateFrame("Frame", "QuestInfoFrame")
        _G.QuestInfoFrame.rewardsFrame = {}
        local scroll = _G.QuestMapDetailsScrollFrame
        local before = scroll.calls.UpdateScrollChildRect
        Q.showDetails(5)
        assert.are.equal("狼の毛皮", QuestInfoTitleHeader:GetText())
        assert.are.equal(before, scroll.calls.UpdateScrollChildRect) -- no refit yet
        _G.QuestInfoFrame.rewardsFrame.numRows = 0
        local update = scroll.UpdateScrollChildRect
        scroll.UpdateScrollChildRect = function() error("the client's callback raised") end
        assert.has_no.errors(function() Q.showDetails(6) end)
        scroll.UpdateScrollChildRect = update
        _G.QuestInfoFrame.rewardsFrame = nil
      end)

    it("shows the details pane's markers right of its back button, not inline; hiding the pane hides them", function()
      local back = _G.QuestMapFrame.QuestsFrame.DetailsFrame.BackFrame.BackButton
      local parent = CreateFrame("Frame")
      back.GetParent = function() return parent end
      assert.is_true(QM.makeBanner())
      assert.is_false(QM.makeBanner()) -- once
      Q.showDetails(7)
      assert.are.equal("Untranslated Errand", QuestInfoTitleHeader:GetText())
      assert.are.equal(WFJ.MARKER.missing, QM.banner:GetText())
      assert.are.equal("\n", QM.banner.markerSep) -- both markers do not fit on one line beside the button
      assert.is_true(QM.banner:IsShown())
      assert.are.same({ "LEFT", back, "RIGHT", QM.BANNER_GAP, 0 }, QM.bannerFrame.point)
      QM.releaseDetails()
      assert.is_false(QM.banner:IsShown())
    end)

    it("renders the popup's quest on the same widgets, on its own surface", function()
      Q.showPopup(5)
      assert.are.equal("狼の毛皮", QuestInfoTitleHeader:GetText())
      assert.are.equal("森の狼が増えている。", QuestInfoDescriptionText:GetText())
      assert.is_table(SS.get(QM.POPUP_INFO, "description"))
      assert.are.equal(0, SS.count(QM.INFO))
    end)

    it("leaves a decorated or failed title English; the other fields still translate", function()
      Q.quests[5].failed = true
      Q.showDetails(5)
      assert.are.equal("Wolf Pelts - |cffff2020(Failed)|r", QuestInfoTitleHeader:GetText())
      assert.is_nil(SS.get(QM.INFO, "title"))
      assert.are.equal("森の狼が増えている。", QuestInfoDescriptionText:GetText())
      Q.quests[5].failed, Q.quests[5].decorated = nil, true
      Q.showDetails(5)
      assert.is_truthy(QuestInfoTitleHeader:GetText():find("Wolf Pelts", 1, true))
      assert.is_nil(SS.get(QM.INFO, "title"))
    end)

    it("an untranslated quest shows the client's English; no selection records nothing", function()
      WFJ.Settings.set("marker.missing", false) -- on by default; this test reads the text, not the marker
      Q.showDetails(5)
      Q.showDetails(7)
      assert.are.equal("Untranslated Errand", QuestInfoTitleHeader:GetText())
      assert.are.equal("Nobody wrote this.", QuestInfoDescriptionText:GetText())
      Q.selected = 0
      assert.are.equal(0, QM.showPane("map"))
      assert.are.equal(0, SS.count(QM.INFO))
    end)

    it("releases on the details frame's OnHide and the popup's, restoring the client's English", function()
      Q.showDetails(5)
      Q.closeDetails()
      assert.are.equal("Wolf Pelts", QuestInfoTitleHeader:GetText())
      assert.are.equal(QUEST5.description, QuestInfoDescriptionText:GetText())
      assert.are.equal(0, SS.count(QM.INFO))
      Q.showPopup(5)
      Q.hidePopup()
      assert.are.equal("Wolf Pelts", QuestInfoTitleHeader:GetText())
      assert.are.equal(0, SS.count(QM.POPUP_INFO))
    end)

    it("the modifier shows the English and lets go back to the Japanese", function()
      Q.showDetails(5)
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("Wolf Pelts", QuestInfoTitleHeader:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("狼の毛皮", QuestInfoTitleHeader:GetText())
    end)

    it("feeds the Collector the API English of every field", function()
      local seen = {}
      WFJ.Collector.record = function(kind, id, field, en) seen[#seen + 1] = { kind, id, field, en } end
      Q.showDetails(5)
      assert.are.same({ "quest", 5, "title", "Wolf Pelts" }, seen[1])
      assert.are.same({ "quest", 5, "description", QUEST5.description }, seen[3])
    end)
  end)

  describe("the three QuestInfo surfaces never restore over each other", function()
    local function questWindow()
      Stub.quest = { id = 2, title = "Sharptalon's Claw", description = "Kill Sharptalon at Silverwind Refuge.",
        objectives = "Bring the claw.", progress = "", completion = "" }
      Stub.showDetail()
    end

    it("quest window, then the map: closing the quest window writes nothing onto the map's text", function()
      questWindow()
      assert.are.equal("Sharptalonの鉤爪", QuestInfoTitleHeader:GetText())
      Q.showDetails(5)
      assert.is_nil(SS.get("questframe.detail", "title")) -- the shared records, forgotten before the map showed
      local writes = QuestInfoTitleHeader.calls.addonSetText
      QuestFrame:Hide()
      assert.are.equal(writes, QuestInfoTitleHeader.calls.addonSetText)
      assert.are.equal("狼の毛皮", QuestInfoTitleHeader:GetText())
      assert.are.equal("森の狼が増えている。", QuestInfoDescriptionText:GetText())
    end)

    it("the map, then the quest window: closing the map's details writes nothing onto the window's text", function()
      Q.showDetails(5)
      questWindow()
      assert.are.equal(0, SS.count(QM.INFO))
      assert.are.equal("Sharptalonの鉤爪", QuestInfoTitleHeader:GetText())
      Q.closeDetails()
      assert.are.equal("Sharptalonの鉤爪", QuestInfoTitleHeader:GetText())
      assert.are.equal("Silverwind Refugeの説明文", QuestInfoDescriptionText:GetText())
    end)

    it("the map, then the popup: hiding the map writes nothing onto the popup's text, and back", function()
      Q.showDetails(5)
      Q.showPopup(6)
      assert.are.equal(0, SS.count(QM.INFO))
      Q.closeDetails()
      assert.are.equal("失われた書物", QuestInfoTitleHeader:GetText())
      Q.showDetails(5)
      assert.are.equal(0, SS.count(QM.POPUP_INFO))
      Q.hidePopup()
      assert.are.equal("狼の毛皮", QuestInfoTitleHeader:GetText())
    end)

    it("the quest window opening while the map pane is shown leaves the map's own buttons Japanese", function()
      Q.showDetails(5)
      local d = _G.QuestMapFrame.QuestsFrame.DetailsFrame
      assert.are.equal("放棄", d.AbandonButton:GetText())
      questWindow()
      assert.are.equal("Sharptalonの鉤爪", _G.QuestInfoTitleHeader:GetText())
      assert.are.equal(0, SS.count(QM.INFO)) -- the shared records went
      assert.are.equal("放棄", d.AbandonButton:GetText())
      assert.are.equal("共有", d.ShareButton:GetText())
      assert.are.equal("追跡", d.TrackButton:GetText())
      assert.are.equal("報酬", d.RewardsFrameContainer.RewardsFrame.Label:GetText())
      assert.is_table(SS.get(QM.SURFACE, "ui.abandon"))
    end)

    it("the map showing while the quest window is open leaves the window's own buttons alone", function()
      questWindow()
      local before = SS.get("questframe.detail", "ui.accept")
      assert.is_table(before)
      assert.are.equal("受ける", _G.QuestFrameAcceptButton:GetText())
      Q.showDetails(5)
      assert.are.equal("受ける", _G.QuestFrameAcceptButton:GetText())
      assert.is_nil(SS.get("questframe.detail", "title"))
      assert.are.equal(before, SS.get("questframe.detail", "ui.accept"))
    end)

    it("a forgotten surface whose widget still shows its Japanese gets its English back (never a stale one)",
    function()
      Q.showPopup(6)
      QM.showPane("map") -- same widgets, selection 6: the popup's records are dropped first
      assert.are.equal(0, SS.count(QM.POPUP_INFO))
      assert.are.equal("失われた書物", QuestInfoTitleHeader:GetText())
    end)
  end)

  describe("list rows and tracker headers", function()
    before_each(function()
      Q.log = { 5, 6, 7 }
    end)

    it("keeps camelot's level prefix verbatim and replaces only the title after it", function()
      Q.updateList()
      local rows = Q.rows()
      assert.are.equal("[10] 狼の毛皮", rows[5].Text:GetText())
      assert.are.equal("[12+] 失われた書物", rows[6].Text:GetText())
      assert.are.equal("[3] Untranslated Errand", rows[7].Text:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("[10] Wolf Pelts", rows[5].Text:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("[10] 狼の毛皮", rows[5].Text:GetText())
    end)

    it("any other decoration leaves the row English (party count, atlas link)", function()
      Q.party[5] = 2
      Q.quests[6].decorated = true
      Q.updateList()
      local rows = Q.rows()
      assert.are.equal("[2] [10] Wolf Pelts", rows[5].Text:GetText())
      assert.is_truthy(rows[6].Text:GetText():find("The Lost Tome", 1, true))
      assert.is_nil(SS.get(QM.LIST, "title.5"))
    end)

    it("rows are keyed by questID: pooled rows that change quest show their own quest's title", function()
      Q.updateList()
      Q.log = { 7, 6, 5 } -- the pool hands the rows back in another order
      Q.updateList()
      local rows = Q.rows()
      assert.are.equal("[10] 狼の毛皮", rows[5].Text:GetText())
      assert.are.equal("[12+] 失われた書物", rows[6].Text:GetText())
      assert.are.equal("[3] Untranslated Errand", rows[7].Text:GetText())
      assert.are.equal(3, SS.count(QM.LIST)) -- one record per row, by quest id (7 has no Japanese: English)
    end)

    it("releases the list on the map's OnHide", function()
      Q.updateList()
      local row = Q.rows()[5]
      Q.hideMap()
      assert.are.equal("[10] Wolf Pelts", row.Text:GetText())
      assert.are.equal(0, SS.count(QM.LIST))
    end)

    it("tracker headers: the API English alone, after the level prefix, or inside the difficulty colour",
    function()
      Q.watched = { [5] = true, [6] = true }
      Q.updateTracker()
      local blocks = _G.QuestObjectiveTracker.usedBlocks
      assert.are.equal("狼の毛皮", blocks[5].HeaderText:GetText())
      Q.trackerLevel = true
      Q.updateTracker()
      assert.are.equal("[12] 失われた書物", blocks[6].HeaderText:GetText())
      Q.trackerColor = true
      Q.updateTracker()
      assert.are.equal("|cffffff00[10] 狼の毛皮|r", blocks[5].HeaderText:GetText())
      Q.trackerLevel = false
      Q.updateTracker()
      assert.are.equal("|cffffff00狼の毛皮|r", blocks[5].HeaderText:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("|cffffff00Wolf Pelts|r", blocks[5].HeaderText:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("|cffffff00狼の毛皮|r", blocks[5].HeaderText:GetText())
    end)

    it("the decoration reader: level prefix and colour wrap kept verbatim; anything else is not ours", function()
      assert.are.same({ "", "" }, { QM.decoration("Wolf Pelts", "Wolf Pelts") })
      assert.are.same({ "[10] ", "" }, { QM.decoration("[10] Wolf Pelts", "Wolf Pelts") })
      assert.are.same({ "|cff40c040", "|r" }, { QM.decoration("|cff40c040Wolf Pelts|r", "Wolf Pelts") })
      assert.are.same({ "|cff40c040[10] ", "|r" }, { QM.decoration("|cff40c040[10] Wolf Pelts|r", "Wolf Pelts") })
      assert.is_nil(QM.decoration("[2] [10] Wolf Pelts", "Wolf Pelts"))
      assert.is_nil(QM.decoration("|cff40c040Wolf Pelts", "Wolf Pelts")) -- no closing |r
      assert.is_nil(QM.decoration("Wolf Pelts - (Failed)", "Wolf Pelts"))
    end)

    it("the block's frame is laid out on the Japanese header's height, and again after the modifier; block.height, " ..
      "which the module adds into its contentsHeight, is never written by the addon", function()
      Q.watched = { [5] = true }
      Q.updateTracker()
      local block = _G.QuestObjectiveTracker.usedBlocks[5]
      local ja = block.HeaderText:GetHeight()
      assert.are.equal("狼の毛皮", block.HeaderText:GetText())
      assert.are.equal(ja + Q.OBJECTIVE_HEIGHT, block.laidOut)
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      local en = block.HeaderText:GetHeight()
      assert.are_not.equal(ja, en) -- the bundled font measures differently
      assert.are.equal(en + Q.OBJECTIVE_HEIGHT, block.laidOut)
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal(ja + Q.OBJECTIVE_HEIGHT, block.laidOut)
    end)

    it("the module's frame grows by its blocks' Japanese extra; its contentsHeight stays the client's", function()
      Q.watched = { [5] = true }
      Q.updateTracker()
      local tracker, block = _G.QuestObjectiveTracker, _G.QuestObjectiveTracker.usedBlocks[5]
      assert.are.equal(block.height, tracker.contentsHeight)
      assert.are.equal(block.laidOut, tracker.frameHeight)
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal(block.laidOut, tracker.frameHeight)
      Stub.keys.alt = false; WFJ.Modifier.refresh()
    end)

    it("the addon never assigns a tracker block's height field (the client's own layout writes it)", function()
      local src = assert(io.open(H.ADDON_DIR .. "/UI/QuestMap.lua")):read("*a")
      assert.is_nil(src:find("%.height%s*=[^=]"))
    end)

    it("a block built before the addon hooked is translated after the layout, its height corrected", function()
      Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
      Stub.installQuestAPI(); Stub.installTooltipAPI()
      Q = QStub.install()
      Q.quests[5] = { title = "Wolf Pelts", description = "d", objectives = "o", level = 10 }
      Q.log, Q.watched = { 5 }, { [5] = true }
      Q.updateTracker() -- the client built the block in English before we loaded
      WFJ = H.loadChunks(FILES)
      H.uiSetup(WFJ, UI, { lookup = function(kind, id) return DATA[kind] and DATA[kind][id] end })
      WFJ.QuestFrame.init(); WFJ.QuestMap.init()
      Q.updateTracker() -- no GetBlock hook fired for this block's SetHeader: UpdateSingle's late path
      local block = _G.QuestObjectiveTracker.usedBlocks[5]
      assert.are.equal("狼の毛皮", block.HeaderText:GetText())
      assert.are.equal(block.HeaderText:GetHeight() + Q.OBJECTIVE_HEIGHT, block.laidOut)
      Q.updateTracker() -- hooked from now on: the SetHeader path
      assert.are.equal("狼の毛皮", block.HeaderText:GetText())
      assert.are.equal(block.HeaderText:GetHeight() + Q.OBJECTIVE_HEIGHT, block.laidOut)
    end)

    it("a reused block that now shows an untranslatable header keeps no old record", function()
      Q.watched = { [5] = true }
      Q.updateTracker()
      local block = _G.QuestObjectiveTracker.usedBlocks[5]
      assert.is_table(SS.get(QM.TRACKER, "title.5"))
      -- the pool hands the block to quest 7 with a decoration the surface does not take (an atlas link)
      _G.QuestObjectiveTracker.usedBlocks[5], _G.QuestObjectiveTracker.usedBlocks[7] = nil, block
      block.id = 7
      block:SetHeader("|A:questlog-questtypeicon-dungeon:16:16|aUntranslated Errand")
      assert.are.equal(0, SS.count(QM.TRACKER))
      assert.are.same({ "Fonts\\FRIZQT__.TTF", 13, "" }, { block.HeaderText:GetFont() }) -- the old font is gone
    end)

    it("the tracker hook is installed once, on the module instance", function()
      assert.are.equal(1, #Stub.hooks["QuestObjectiveTracker:UpdateSingle"])
      assert.are.equal(0, QM.hookTrackers())
    end)

    it("the level prefix reader takes only [n] or [n+] followed by a space", function()
      assert.are.same({ "[60+] ", "Title" }, { QM.splitPrefix("[60+] Title") })
      assert.is_nil(QM.splitPrefix("[x] Title"))
      assert.is_nil(QM.splitPrefix("Title"))
    end)
  end)

  describe("the pane's and the list's fixed words", function()
    it("the details pane's buttons, strip, headers and map rewards words", function()
      Q.showDetails(5)
      local d = _G.QuestMapFrame.QuestsFrame.DetailsFrame
      assert.are.equal("Back", d.BackFrame.BackButton:GetText()) -- never the cloak slot's 背中
      assert.are.equal("報酬", d.RewardsFrameContainer.RewardsFrame.Label:GetText())
      assert.are.equal("放棄", d.AbandonButton:GetText())
      assert.are.equal("共有", d.ShareButton:GetText())
      assert.are.equal("追跡", d.TrackButton:GetText())
      assert.are.equal("説明", QuestInfoDescriptionHeader:GetText())
      assert.are.equal("クエストの目的", QuestInfoObjectivesHeader:GetText())
      assert.are.equal("次の報酬から1つ選べる:", _G.MapQuestInfoRewardsFrame.ItemChooseText:GetText())
      assert.are.equal("受け取る報酬:", _G.MapQuestInfoRewardsFrame.ItemReceiveText:GetText())
      assert.are.equal("次の称号を授かる:", _G.MapQuestInfoRewardsFrame.PlayerTitleText:GetText())
    end)

    it("the Track button is shown again after every rewrite (Track ↔ Untrack), on the live pane only", function()
      Q.showDetails(5)
      local track = _G.QuestMapFrame.QuestsFrame.DetailsFrame.TrackButton
      Q.setWatched(5, true)
      assert.are.equal("追跡解除", track:GetText())
      Q.setWatched(5, false)
      assert.are.equal("追跡", track:GetText())
      -- the popup is not live: its Track button keeps the client's word
      assert.are.equal("Track", _G.QuestLogPopupDetailFrameTrackButton:GetText())
      Q.closeDetails()
      Q.setWatched(5, true)
      assert.are.equal("Untrack", track:GetText())
    end)

    it("the popup's buttons and rewards words", function()
      Q.watched[5] = true
      Q.showPopup(5)
      assert.are.equal("放棄", _G.QuestLogPopupDetailFrameAbandonButton:GetText())
      assert.are.equal("追跡解除", _G.QuestLogPopupDetailFrameTrackButton:GetText())
      assert.are.equal("共有", _G.QuestLogPopupDetailFrameShareButton:GetText())
      assert.are.equal("地図を表示", _G.QuestLogPopupDetailFrame.ShowMapButton.Text:GetText())
      assert.are.equal("報酬", QuestInfoRewardsFrame.Header:GetText())
    end)

    it("the list's empty, no-results, search and count words", function()
      Q.log = {}
      Q.updateList()
      assert.are.equal(UI.QUEST_LOG_NO_QUESTS[2], _G.QuestScrollFrame.EmptyText:GetText())
      assert.are.equal("見つかりません", _G.QuestScrollFrame.NoSearchResultsText:GetText())
      assert.are.equal("クエストログを検索", _G.QuestScrollFrame.SearchBox.Instructions:GetText())
      assert.are.equal("クエスト: |cffffffff0|r|cffffffff/20|r", _G.QuestLogQuestCount:GetText())
    end)

    it("the Back button takes BACK only: a dictionary with the cloak slot's \"Back\" never reaches it", function()
      local back = _G.QuestMapFrame.QuestsFrame.DetailsFrame.BackFrame.BackButton
      assert.are.equal("INVTYPE_CLOAK", (WFJ.UIIndex:match("Back"))) -- the collision is real in this dictionary
      Q.showDetails(5)
      Q.setWatched(5, true)
      Q.showDetails(5)
      assert.are.equal("Back", back:GetText())
      assert.are.equal(0, back.fontString.calls.addonSetText)
      assert.is_nil(SS.get(QM.SURFACE, "ui.back"))
    end)

    it("the tracker's two headers, shown at hook time and after each writer", function()
      assert.are.equal("クエスト", _G.QuestObjectiveTracker.Header.Text:GetText())
      Q.initTrackerContainer() -- the container writes its header after we hooked
      assert.are.equal("すべての目標", _G.ObjectiveTrackerFrame.Header.Text:GetText())
      _G.QuestObjectiveTracker:SetHeader("Quests")
      assert.are.equal("クエスト", _G.QuestObjectiveTracker.Header.Text:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("All Objectives", _G.ObjectiveTrackerFrame.Header.Text:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("すべての目標", _G.ObjectiveTrackerFrame.Header.Text:GetText())
    end)

    it("the waypoint buttons' tooltips (help surface, each its own key); released on the tooltip's OnHide", function()
      local d = _G.QuestMapFrame.QuestsFrame.DetailsFrame
      assert.is_true(WFJ.HelpTooltip.registered(d.DestinationMapButton))
      Q.hoverPath(d.DestinationMapButton)
      assert.are.equal("最終目的地を表示", _G.GameTooltipTextLeft1:GetText())
      Q.hoverPath(d.WaypointMapButton)
      assert.are.equal("移動経路を表示", _G.GameTooltipTextLeft1:GetText())
      _G.GameTooltip:Hide()
      assert.are.equal("Show Travel Route", _G.GameTooltipTextLeft1:GetText())
    end)

    it("the search box itself is never ours", function()
      assert.is_true(WFJ.Labels.forbidden(_G.QuestScrollFrame.SearchBox))
    end)
  end)
end)

-- The quest map has no title of its own: the window is WorldMapFrame, whose BorderFrame is titled with
-- SetTitle(MAP_AND_QUEST_LOG) from OnLoad and after every minimize, and SetTitle(WORLD_MAP) when maximized
-- [blizzard_worldmap/blizzard_worldmap.lua:26–27, 34–42].
describe("UI/QuestMap: the window title", function()
  local WFJ, SS, QM, border

  local TITLES = {
    MAP_AND_QUEST_LOG = { "Map & Quest Log", "マップ＆クエストログ" }, WORLD_MAP = { "Map", "マップ" },
    QUEST_LOG = { "Quest Log", "クエストログ" }, REWARDS = { "Rewards", "報酬" },
  }
  local function title() return border.TitleContainer.TitleText end
  local function alt(down) Stub.keys.alt = down; WFJ.Modifier.refresh() end

  -- `shape` builds the map before the addon loads: a camelot-shaped one by default.
  local function setup(shape)
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    QStub.install()
    local map = CreateFrame("Frame", "WorldMapFrame")
    border = CreateFrame("Frame", nil, map)
    border.TitleContainer = { TitleText = Stub.fontString("") }
    function border.SetTitle(self, t) self.TitleContainer.TitleText.text = t end
    map.BorderFrame = border
    if shape then shape(map) end
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, TITLES)
    border:SetTitle(_G.MAP_AND_QUEST_LOG) -- WorldMapMixin:SetupTitle, from OnLoad
    SS, QM = WFJ.SurfaceState, WFJ.QuestMap
    WFJ.QuestFrame.init()
    QM.init()
  end

  after_each(function()
    _G.WorldMapFrame = nil
    H.uiTeardown()
  end)

  it("renders the title written before the addon loaded, and again after every SetTitle (minimize / maximize)",
    function()
      setup()
      assert.are.equal("マップ＆クエストログ", title():GetText())
      assert.are.equal(WFJ.Font.PATH, (title():GetFont()))
      border:SetTitle(_G.WORLD_MAP) -- SynchronizeDisplayState, maximized
      assert.are.equal("マップ", title():GetText())
      border:SetTitle(_G.MAP_AND_QUEST_LOG) -- minimized again: a second SetTitle keeps the Japanese
      assert.are.equal("マップ＆クエストログ", title():GetText())
      border:SetTitle(_G.QUEST_LOG) -- a build that titles the window "Quest Log"
      assert.are.equal("クエストログ", title():GetText())
      alt(true)
      assert.are.equal("Quest Log", title():GetText())
      alt(false)
      assert.are.equal("クエストログ", title():GetText())
      assert.are.equal(1, #Stub.hooks["?:SetTitle"]) -- hooked once, however often the title is shown
    end)

  it("is released when the map hides and rendered again when it is re-shown (no SetTitle runs on a re-show)",
    function()
      setup()
      _G.WorldMapFrame:Show()
      assert.are.equal("マップ＆クエストログ", title():GetText())
      _G.WorldMapFrame:Hide()
      assert.are.equal("Map & Quest Log", title():GetText())
      assert.are.equal(0, SS.count(QM.MAP_TITLE))
      _G.WorldMapFrame:Show()
      assert.are.equal("マップ＆クエストログ", title():GetText())
    end)

  it("a title that is none of the map's words stays English even when it is a dictionary word", function()
    setup()
    border:SetTitle("Rewards")
    assert.are.equal("Rewards", title():GetText())
    assert.are.equal(0, SS.count(QM.MAP_TITLE))
  end)

  it("a border frame or a title bound to the wrong type degrades to English with no error", function()
    assert.has_no.errors(function() setup(function(map) map.BorderFrame = "moved" end) end)
    assert.are.equal(0, QM.showMapTitle())
    assert.has_no.errors(function()
      setup(function(map)
        map.BorderFrame.TitleContainer = { TitleText = "moved" } -- a title that is no text widget
        map.BorderFrame.SetTitle = function() end
      end)
    end)
    assert.are.equal(0, QM.showMapTitle())
    assert.is_nil(Stub.hooks["?:SetTitle"])
    assert.has_no.errors(function() _G.WorldMapFrame:Show(); _G.WorldMapFrame:Hide() end)
  end)

  it("without a world map nothing is hooked or shown", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    _G.WorldMapFrame = nil
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, TITLES)
    assert.has_no.errors(function() WFJ.QuestFrame.init(); WFJ.QuestMap.init() end)
    assert.are.equal(0, WFJ.QuestMap.showMapTitle())
    assert.is_nil(Stub.hooks["?:SetTitle"])
  end)
end)
