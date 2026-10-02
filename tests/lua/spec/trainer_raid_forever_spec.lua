-- The trainer and the raid panel on the Forever client (camelot loads the mainline Blizzard_TrainerUI,
-- Blizzard_RaidFrame and Blizzard_RaidUI files). The replays follow the Forever source: trainer rows are pooled
-- ScrollBox buttons written by ClassTrainerFrame_InitServiceButton (mainline/blizzard_trainerui.lua:520–683); the raid
-- panel's description is a ScrollingFont, its info header a DialogHeader, its column labels Frames with .text, and a
-- saved-instance row's reset is `reset` (mainline/raidframe.xml / .lua).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Social = require("tests.lua.spec.stub_social")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Trainer.lua"
FILES[#FILES + 1] = "UI/Raid.lua"

local UI = {
  TRAIN = { "Train", "訓練" }, FILTER = { "Filter", "フィルター" }, APPRENTICE = { "Apprentice", "見習い" },
  PARENS_TEMPLATE = { "(%s)", "(%s)" },
  REQUIRES_LABEL = { "Requires:", "必要:" }, TRAINER_REQ_LEVEL = { "Level |cffffffff%d|r", "レベル |cffffffff%d|r" },
  ITEM_SPELL_KNOWN = { "Already known", "習得済み" },
  TRAINER_REQ_SKILL_RANK = { "%s (|cffffffff%d|r)", "%s (|cffffffff%d|r)" }, RANK = { "Rank", "ランク" },
  TOOLTIP_TALENT_RANK_CURRENT_ONLY = { "Rank %d", "ランク %d" },
  TRAINING_POINTS = { "Training Points: %d", "訓練ポイント: %d" }, TRAINING_POINTS_ABBREV = { "%s TP", "%s TP" },
  RAID_DESCRIPTION = { "Raids are groups of more than 5 people.", "レイドは6人以上のグループです。" },
  -- the all-assist check box's label carries the assistant icon, kept verbatim
  ALL_ASSIST_LABEL = { "All |TInterface\\GroupFrame\\UI-Group-AssistantIcon:20:20:0:1|t",
    "すべて |TInterface\\GroupFrame\\UI-Group-AssistantIcon:20:20:0:1|t" },
  CONVERT_TO_RAID = { "Convert To Raid", "レイドに変換" }, RAID_INFO = { "Raid Info", "レイド情報" },
  RAID_INFORMATION = { "Raid Information", "レイドの情報" }, INSTANCE = { "Instance", "インスタンス" },
  RAID_INSTANCE_EXPIRES_EXPIRED = { "Expired", "期限切れ" }, DAYS_ABBR = { "%d |4Day:Days;", "%d日" },
  RAID_INFO_WORLD_BOSS = { "World Boss", "ワールドボス" }, EXTENDED = { "Extended", "延長済み" },
  -- a saved instance's difficultyName (GetSavedInstanceInfo, raidframe.lua:157–158; client-table row, ADR-042)
  ["Difficulty:9"] = { "40 Player", "40人" },
  -- Forever GlobalStrings @1.60.1.69913
  TRAINER_CANNOT_EXCEED_MAX_PROFESSIONS = { "You can only learn two primary professions",
    "主要専門技能は2つまでしか習得できません" },
  TRAINING_POINTS_TUTORIAL = { "Increase your pets loyalty and level to gain Training Points.",
    "ペットの忠誠度とレベルを上げると訓練ポイントを獲得できます。" },
  LOCK_EXPIRE = { "Lock Expire", "ロック期限" }, CLOSE = { "Close", "閉じる" },
  RAID = { "Raid", "レイド" }, LOOKING_FOR_RAID = { "Other Raids", "他のレイド" },
  EXTEND_RAID_LOCK = { "Extend Raid Lock", "レイドロックを延長" },
  UNEXTEND_RAID_LOCK = { "Remove Raid Lock Extension", "レイドロック延長を解除" },
  REACTIVATE_RAID_LOCK = { "Reactivate Raid Lock", "レイドロックを再開" },
  -- Blizzard_RaidUI and the help tooltips
  GROUP = { "Group", "グループ" }, EMPTY = { "Empty", "空き" }, RAID_LEADER = { "Raid Leader", "レイドリーダー" },
  ALL_ASSIST_DESCRIPTION = { "If checked, all raid members will have the permissions of a Raid Assistant.",
    "チェックすると、レイドメンバー全員がレイドアシスタントの権限を持ちます。" },
  -- the class buttons' tooltip titles (blizzard_raidui.lua:119–142)
  MAINTANK = { "Main Tank", "メインタンク" }, PETS = { "Pets", "ペット" },
  WARRIOR = { "Warrior", "戦士" }, -- a class title is a name here: never matched
}
local function en(key) return UI[key][1] end
local function ja(key) return UI[key][2] end

describe("trainer and raid on the Forever client", function()
  local WFJ

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end)

  after_each(function() H.uiTeardown() end)

  describe("trainer", function()
    local frame, rows, dropdownCalls

    -- Blizzard_TrainerUI (mainline) loaded: the frame, the train button, and the writers.
    local function loadTrainerUI()
      frame = CreateFrame("Frame", "ClassTrainerFrame")
      frame.trainingPoints = { text = Stub.fontString("") }
      -- the filter dropdown (WowStyle1DropdownTemplate: DropdownSelectionTextMixin, MenuTemplates.lua:520–644; xml:231)
      dropdownCalls = { SetText = 0 }
      local dd = { Text = Stub.fontString(""), name = "FilterDropdown" }
      function dd.SetText(self, text) -- a Lua override that writes the field `text`; the addon must never call it
        dropdownCalls.SetText = dropdownCalls.SetText + 1
        self.text = text
        self:UpdateText()
      end
      function dd.UpdateText(self) self.Text.text = self.text or "" end
      function dd.SetSelectionText(self, fn) self.selectionFunc = fn end
      function dd.UpdateToMenuSelections(self) self:SetText(self.selectionFunc and self.selectionFunc({})) end
      frame.FilterDropdown = dd
      frame:SetScript("OnShow", function(self) -- ClassTrainerFrame_OnShow (lua:67–69): the filter's selection text
        self.FilterDropdown:SetSelectionText(function() return en("FILTER") end)
        self.FilterDropdown:UpdateToMenuSelections()
      end)
      Stub.button("ClassTrainerTrainButton", en("TRAIN"))
      rows = {}
      -- lua:520–606: requirements, then name / subText / nameSubText; pet cost (lua:626–644)
      _G.ClassTrainerFrame_InitServiceButton = function(button, data)
        button.name.text = data.name
        if data.used then
          button.subText.text = en("ITEM_SPELL_KNOWN")
        elseif data.level then
          local req = string.format(en("TRAINER_REQ_LEVEL"), data.level)
          if data.skill then req = req .. ", " .. string.format(en("TRAINER_REQ_SKILL_RANK"), data.skill, data.rank) end
          button.subText.text = en("REQUIRES_LABEL") .. " " .. req
        else
          button.subText.text = ""
        end
        button.nameSubText.text = data.sub and string.format(en("PARENS_TEMPLATE"), data.sub) or ""
        if data.tp then button.alternateCost.text = string.format(en("TRAINING_POINTS_ABBREV"), tostring(data.tp)) end
      end
      _G.ClassTrainerFrame_UpdateTrainingPoints = function() -- lua:505–518
        frame.trainingPoints.text.text = string.format(en("TRAINING_POINTS"), 12)
        for _, b in ipairs(rows) do
          if b.data.tp then b.alternateCost.text = string.format(en("TRAINING_POINTS_ABBREV"), tostring(b.data.tp)) end
        end
      end
      _G.ClassTrainerFrame_Update = function() end
      _G.ClassTrainer_SetSelection = function() end
      Stub.loadedAddons["Blizzard_TrainerUI"] = true
    end

    -- The ScrollBox acquiring (or re-initializing) a pooled service button.
    local function row(i, data)
      local b = rows[i] or { name = Stub.fontString(""), subText = Stub.fontString(""),
        nameSubText = Stub.fontString(""), alternateCost = Stub.fontString("") }
      rows[i], b.data = b, data
      _G.ClassTrainerFrame_InitServiceButton(b, data)
      return b
    end

    it("rows: subtext and requirements translate, names never; a reused row follows its new data", function()
      loadTrainerUI()
      WFJ.Trainer.init()
      assert.are.equal(ja("TRAIN"), _G.ClassTrainerTrainButton:GetText())
      local b1 = row(1, { name = "Tailoring", sub = en("APPRENTICE"), level = 5 })
      local b2 = row(2, { name = "Exit", used = true })
      assert.are.equal("(見習い)", b1.nameSubText:GetText())
      assert.are.equal("必要: レベル |cffffffff5|r", b1.subText:GetText())
      assert.are.equal("Tailoring", b1.name:GetText())
      assert.are.equal(ja("ITEM_SPELL_KNOWN"), b2.subText:GetText())
      assert.are.equal("Exit", b2.name:GetText()) -- a service named like a dictionary word
      row(1, { name = "First Aid", sub = "Journeyman" }) -- pooled: re-initialized for another service
      assert.are.equal("(Journeyman)", b1.nameSubText:GetText()) -- not a dictionary word: English
      assert.are.equal("", b1.subText:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal(en("ITEM_SPELL_KNOWN"), b2.subText:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      frame:Hide()
      assert.are.equal(en("ITEM_SPELL_KNOWN"), b2.subText:GetText()) -- released on hide
    end)

    it("'(Rank 2)' translates through the `entry` argument (a template inside the parentheses); a capture that is"
      .. " not an entry stays English; a requirement list translates per item, the skill name kept",
      function()
        loadTrainerUI()
        WFJ.Trainer.init()
        local b = row(1, { name = "Heroic Strike", sub = "Rank 2", level = 5, skill = "First Aid", rank = 50 })
        assert.are.equal("(ランク 2)", b.nameSubText:GetText())
        assert.are.equal("Heroic Strike", b.name:GetText())
        assert.are.equal("必要: レベル |cffffffff5|r, First Aid (|cffffffff50|r)", b.subText:GetText())
        Stub.keys.alt = true; WFJ.Modifier.refresh()
        assert.are.equal("(Rank 2)", b.nameSubText:GetText())
        assert.are.equal("Requires: Level |cffffffff5|r, First Aid (|cffffffff50|r)", b.subText:GetText())
        Stub.keys.alt = false; WFJ.Modifier.refresh()
        row(1, { name = "Heroic Strike", sub = "Grandmaster" }) -- not a dictionary entry: not this template
        assert.are.equal("(Grandmaster)", b.nameSubText:GetText())
      end)

    it("a pet trainer: the points label and each row's cost translate on UpdateTrainingPoints", function()
      loadTrainerUI()
      WFJ.Trainer.init()
      local b = row(1, { name = "Bite", tp = 7 })
      _G.ClassTrainerFrame_UpdateTrainingPoints()
      assert.are.equal("訓練ポイント: 12", frame.trainingPoints.text:GetText())
      assert.are.equal("7 TP", b.alternateCost:GetText())
    end)

    it("help tooltips: the train button's profession-cap reason and the points tutorial", function()
      loadTrainerUI()
      WFJ.Trainer.init()
      local tt = _G.GameTooltip
      local function left(i) return _G["GameTooltipTextLeft" .. i] end
      tt:SetOwner(_G.ClassTrainerTrainButton, "ANCHOR_RIGHT") -- lua:295–302
      tt:SetText(en("TRAINER_CANNOT_EXCEED_MAX_PROFESSIONS"))
      tt:Show()
      assert.are.equal(ja("TRAINER_CANNOT_EXCEED_MAX_PROFESSIONS"), left(1):GetText())
      tt:Hide()
      tt:SetOwner(frame.trainingPoints, "ANCHOR_RIGHT") -- xml:254–258
      tt:SetText(en("TRAINING_POINTS_TUTORIAL"))
      tt:Show()
      assert.are.equal(ja("TRAINING_POINTS_TUTORIAL"), left(1):GetText())
      tt:Hide()
      tt:SetOwner(_G.ClassTrainerTrainButton, "ANCHOR_RIGHT") -- restricted: another word on that owner stays English
      tt:SetText(en("TRAIN"))
      tt:Show()
      assert.are.equal(en("TRAIN"), left(1):GetText())
    end)

    it("an already-loaded trainer UI is set up at init without error", function()
      loadTrainerUI()
      assert.has_no.errors(function() assert.is_true(WFJ.Trainer.init()) end)
    end)

    it("the filter dropdown button shows Japanese after each UpdateText; the dropdown's SetText is never called by"
      .. " the addon", function()
      loadTrainerUI(); WFJ.Trainer.init()
      frame:Show()
      local dd = frame.FilterDropdown
      assert.are.equal("フィルター", dd.Text:GetText())
      assert.are.equal(WFJ.Font.PATH, (dd.Text:GetFont()))
      assert.are.equal(1, dropdownCalls.SetText) -- the client's own
      assert.are.equal("Filter", dd.text) -- the Blizzard field keeps the English
      dd:UpdateToMenuSelections() -- a pick in the menu rewrites the text
      assert.are.equal("フィルター", dd.Text:GetText())
      assert.are.equal(2, dropdownCalls.SetText)
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("Filter", dd.Text:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("フィルター", dd.Text:GetText())
      WFJ.Settings.set("area.interface", false)
      assert.are.equal("Filter", dd.Text:GetText())
      assert.are.equal(2, dropdownCalls.SetText)
      WFJ.Settings.set("area.interface", true)
    end)

    it("a writer bound to a table is never hooked", function()
      loadTrainerUI()
      _G.ClassTrainerFrame_InitServiceButton = {}
      _G.ClassTrainerFrame_UpdateTrainingPoints = {}
      assert.has_no.errors(function() WFJ.Trainer.init() end)
    end)
  end)

  describe("raid", function()
    local init

    -- Blizzard_RaidFrame (mainline): RaidFrame_OnLoad and the XML the camelot friends frame shows.
    local function installRaid()
      CreateFrame("Frame", "RaidFrame")
      local notInRaid = CreateFrame("Frame", "RaidFrameNotInRaid")
      local descFs = Stub.fontString(en("RAID_DESCRIPTION")) -- ScrollingDescription:SetText (lua:37)
      descFs.GetStringHeight = function() return 40 end
      local container = { FontString = descFs }
      function container:SetHeight(h) self.height = h end
      notInRaid.ScrollingDescription = { ScrollBox = { FontStringContainer = container } }
      Stub.button("RaidFrameConvertToRaidButton", en("CONVERT_TO_RAID"))
      Stub.button("RaidFrameRaidInfoButton", en("RAID_INFO"))
      local info = CreateFrame("Frame", "RaidInfoFrame")
      info.Header = { Text = Stub.fontString(en("RAID_INFORMATION")) } -- DialogHeaderMixin:Setup (textString)
      info.ScrollBox = Stub.scrollBox()
      CreateFrame("Frame", "RaidInfoInstanceLabel").text = Stub.fontString(en("INSTANCE")) -- OnLoad (xml:272)
      CreateFrame("Frame", "RaidInfoIDLabel").text = Stub.fontString(en("LOCK_EXPIRE")) -- OnLoad (xml:283)
      Stub.button("RaidInfoCancelButton", en("CLOSE"))
      Stub.button("RaidInfoExtendButton", en("EXTEND_RAID_LOCK")) -- text= (xml:309)
      Stub.button("RaidParentFrameTab1", en("RAID"))
      Stub.button("RaidParentFrameTab2", en("LOOKING_FOR_RAID"))
      _G.RaidInfoFrame_UpdateButtons = function() -- lua:247–268
        local s = _G.RaidInfoFrame.selected
        _G.RaidInfoExtendButton.fontString.text = not s and en("EXTEND_RAID_LOCK")
          or s.extended and en("UNEXTEND_RAID_LOCK") or s.locked and en("EXTEND_RAID_LOCK")
          or en("REACTIVATE_RAID_LOCK")
      end
      CreateFrame("CheckButton", "RaidFrameAllAssistCheckButton")
      Stub.namedFontString("RaidFrameAllAssistCheckButtonText", en("ALL_ASSIST_LABEL")) -- OnLoad (xml:155)
      init = function(button, data) -- RaidInfoFrame_InitButton (lua:142–165)
        button.name.text = data.name
        button.reset.text = data.reset or ("|cff808080" .. en("RAID_INSTANCE_EXPIRES_EXPIRED") .. "|r")
        button.difficulty.text = data.difficulty
        button.extended.text = en("EXTENDED")
      end
      return container
    end

    local function infoRow(r, data)
      r = r or { name = Stub.fontString(""), reset = Stub.fontString(""), difficulty = Stub.fontString(""),
        extended = Stub.fontString("") }
      _G.RaidInfoFrame.ScrollBox:initFrame(r, data, init)
      return r
    end

    it("static labels through their Forever widgets; the description's container is re-heighted", function()
      local container = installRaid()
      assert.is_true(WFJ.Raid.init())
      assert.are.equal(ja("RAID_DESCRIPTION"), container.FontString:GetText())
      assert.are.equal(40, container.height)
      assert.are.equal(ja("CONVERT_TO_RAID"), _G.RaidFrameConvertToRaidButton:GetText())
      assert.are.equal(ja("ALL_ASSIST_LABEL"), _G.RaidFrameAllAssistCheckButtonText:GetText()) -- icon unchanged
      assert.are.equal(ja("RAID_INFORMATION"), _G.RaidInfoFrame.Header.Text:GetText())
      assert.are.equal(ja("INSTANCE"), _G.RaidInfoInstanceLabel.text:GetText())
      assert.are.equal(ja("LOCK_EXPIRE"), _G.RaidInfoIDLabel.text:GetText())
      assert.are.equal(ja("CLOSE"), _G.RaidInfoCancelButton:GetText())
      assert.are.equal(ja("RAID"), _G.RaidParentFrameTab1:GetText())
      assert.are.equal(ja("LOOKING_FOR_RAID"), _G.RaidParentFrameTab2:GetText())
    end)

    it("the extend button follows RaidInfoFrame_UpdateButtons", function()
      installRaid()
      WFJ.Raid.init()
      assert.are.equal(ja("EXTEND_RAID_LOCK"), _G.RaidInfoExtendButton:GetText())
      _G.RaidInfoFrame.selected = { extended = true }
      _G.RaidInfoFrame_UpdateButtons()
      assert.are.equal(ja("UNEXTEND_RAID_LOCK"), _G.RaidInfoExtendButton:GetText())
      _G.RaidInfoFrame.selected = { locked = false }
      _G.RaidInfoFrame_UpdateButtons()
      assert.are.equal(ja("REACTIVATE_RAID_LOCK"), _G.RaidInfoExtendButton:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal(en("REACTIVATE_RAID_LOCK"), _G.RaidInfoExtendButton:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
    end)

    it("saved-instance rows: the lowercase reset, a world boss difficulty and Extended translate", function()
      installRaid()
      WFJ.Raid.init()
      local r = infoRow(nil, { name = "Onyxia", difficulty = en("RAID_INFO_WORLD_BOSS") })
      assert.are.equal("|cff808080期限切れ|r", r.reset:GetText())
      assert.are.equal(ja("RAID_INFO_WORLD_BOSS"), r.difficulty:GetText())
      assert.are.equal(ja("EXTENDED"), r.extended:GetText())
      assert.are.equal("Onyxia", r.name:GetText())
      infoRow(r, { name = "Molten Core", reset = "3 Days 4 Hr", difficulty = "Heroic" })
      assert.are.equal("3 Days 4 Hr", r.reset:GetText())
      assert.are.equal("Heroic", r.difficulty:GetText()) -- no Difficulty row: English
    end)

    it("a saved instance's difficulty is a Difficulty row's Japanese; Alt shows English; the name stays", function()
      installRaid()
      WFJ.Raid.init()
      local r = infoRow(nil, { name = "Molten Core", reset = "3 Days", difficulty = "40 Player" })
      assert.are.equal("40人", r.difficulty:GetText())
      assert.are.equal("Molten Core", r.name:GetText())
      Stub.keys.alt = true; WFJ.Modifier.refresh()
      assert.are.equal("40 Player", r.difficulty:GetText())
      Stub.keys.alt = false; WFJ.Modifier.refresh()
      assert.are.equal("40人", r.difficulty:GetText())
      infoRow(r, { name = "40 Player", reset = "3 Days", difficulty = en("RAID_INFO_WORLD_BOSS") })
      assert.are.equal("40 Player", r.name:GetText()) -- a name never matches, even a family row's English
      assert.are.equal(ja("RAID_INFO_WORLD_BOSS"), r.difficulty:GetText())
    end)

    it("a class button's UIParent-anchored tooltip: Main Tank / Pets with the count kept; a class "
      .. "title and the member list stay", function()
        installRaid()
        WFJ.Raid.init()
        local members = "Thrall, Jaina"
        _G.UIParent = CreateFrame("Frame", "UIParent")
        _G.RaidClassButton_OnEnter = function(self) -- lua:121–142
          local tt = _G.GameTooltip
          tt:SetOwner(_G.UIParent) -- GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
          tt:SetText(("%s%s (%d)%s"):format(self.class, "|cffffd200", self.count, "|r"))
          tt:AddLine(members)
          tt:Show()
        end
        WFJ.Raid.setupRaidUI()
        _G.RaidClassButton_OnEnter({ class = en("MAINTANK"), count = 3 })
        assert.are.equal("メインタンク|cffffd200 (3)|r", _G.GameTooltipTextLeft1:GetText())
        assert.are.equal(members, _G.GameTooltipTextLeft2:GetText())
        Stub.keys.alt = true; WFJ.Modifier.refresh()
        assert.are.equal("Main Tank|cffffd200 (3)|r", _G.GameTooltipTextLeft1:GetText())
        Stub.keys.alt = false; WFJ.Modifier.refresh()
        _G.RaidClassButton_OnEnter({ class = en("PETS"), count = 2 })
        assert.are.equal("ペット|cffffd200 (2)|r", _G.GameTooltipTextLeft1:GetText())
        _G.RaidClassButton_OnEnter({ class = en("WARRIOR"), count = 5 })
        assert.are.equal("Warrior|cffffd200 (5)|r", _G.GameTooltipTextLeft1:GetText())
        assert.is_false(WFJ.HelpTooltip.registered(_G.UIParent))
        _G.RaidClassButton_OnEnter, _G.UIParent = nil, nil
      end)

    it("Blizzard_RaidUI without loot icons: setup skips them", function()
      installRaid()
      WFJ.Raid.init()
      for g = 1, 8 do Stub.button("RaidGroup" .. g .. "Label", "Group " .. g) end
      assert.has_no.errors(function() WFJ.Raid.setupRaidUI() end)
    end)

    -- no record on any surface holds this widget
    local function unrecorded(widget)
      for _, bucket in pairs(WFJ.SurfaceState.surfaces()) do
        for _, rec in pairs(bucket) do
          if rec.fs == widget or (type(rec.fs) == "table" and rec.fs.button == widget) then return false end
        end
      end
      return true
    end

    it("an existing row is covered by the iterateExisting pass when the subscription starts late", function()
      installRaid()
      WFJ.Raid.init()
      local r = { name = Stub.fontString("Naxxramas"), reset = Stub.fontString("|cff808080Expired|r"),
        difficulty = Stub.fontString(""), extended = Stub.fontString("") }
      WFJ.Raid.onRow(r, {}) -- the client's ForEachFrame shape: (frame, elementData)
      assert.are.equal("|cff808080期限切れ|r", r.reset:GetText())
      assert.is_true(unrecorded(r.name))
    end)

    it("Blizzard_RaidUI: group labels and Empty slots translate after its ADDON_LOADED; classes never",
      function()
        installRaid()
        WFJ.Raid.init()
        Social.loadRaidUI()
        Social.raid = { { name = "Reyn", class = "Raid", level = 60 } }
        _G.RaidGroupFrame_Update()
        assert.are.equal(1, WFJ.LoadOnDemand.loaded("Blizzard_RaidUI"))
        assert.are.equal("グループ 1", _G.RaidGroup1Label:GetText())
        assert.are.equal("グループ 8", _G.RaidGroup8Label:GetText())
        assert.are.equal("空き", (_G.RaidGroup3Slot5:GetRegions()):GetText())
        assert.are.equal("Raid", _G.RaidGroupButton1Class:GetText())
        assert.is_true(unrecorded(_G.RaidGroupButton1Class))
        Social.hover(_G.RaidGroupButton1Rank, { "Raid Leader" })
        assert.are.equal("レイドリーダー", _G.GameTooltipTextLeft1:GetText())
        assert.are.equal(0, WFJ.LoadOnDemand.loaded("Blizzard_RaidUI")) -- once
      end)

    it("an already-loaded Blizzard_RaidUI is set up at init", function()
      installRaid()
      Social.loadRaidUI()
      _G.RaidGroup2Label.fontString.text = "Group 2"
      WFJ.Raid.init()
      assert.are.equal("グループ 2", _G.RaidGroup2Label:GetText())
    end)

    it("the all-assist checkbox tooltip translates", function()
      installRaid()
      WFJ.Raid.init()
      Social.hover(_G.RaidFrameAllAssistCheckButton, { en("ALL_ASSIST_DESCRIPTION") })
      assert.are.equal(ja("ALL_ASSIST_DESCRIPTION"), _G.GameTooltipTextLeft1:GetText())
    end)

    it("every NEVER_TOUCH roster widget stays unrecorded after every writer runs with dictionary words",
      function()
        installRaid()
        WFJ.Raid.init()
        Social.loadRaidUI()
        WFJ.LoadOnDemand.loaded("Blizzard_RaidUI")
        WFJ.Labels.forbidNames(WFJ.Raid.NEVER_TOUCH)
        local present = {}
        for _, name in ipairs(WFJ.Raid.NEVER_TOUCH) do
          local w = _G[name]
          if type(w) == "table" then
            if w.fontString then w.fontString.text = "Group" else w.text = "Group" end
            present[#present + 1] = name
          end
        end
        assert.is_true(#present > 20)
        WFJ.Raid.showStatic(); WFJ.Raid.setupRaidUI()
        Stub.keys.alt = true; WFJ.Modifier.refresh()
        Stub.keys.alt = false; WFJ.Modifier.refresh()
        for _, name in ipairs(present) do assert.is_true(unrecorded(_G[name]), name) end
      end)
  end)
end)
