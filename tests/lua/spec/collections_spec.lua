-- UI/Collections.lua, UI/MountJournal.lua, UI/PetJournal.lua and
-- UI/Wardrobe.lua over the CollectionsJournal of stub_collections.lua (camelot blizzard_collections). Mount, pet, toy,
-- heirloom and set names, class names and the search boxes stay as the client wrote them; every module waits for
-- Blizzard_Collections in either load order and does nothing on a client without the window.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_collections")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
for _, f in ipairs({ "UI/Collections.lua", "UI/MountJournal.lua", "UI/PetJournal.lua", "UI/Wardrobe.lua",
  "UI/Errors.lua" }) do -- the mount button's usability line is an error line (UI/Errors' set)
  FILES[#FILES + 1] = f
end
local MODULES = { "Collections", "MountJournal", "PetJournal", "Wardrobe" }

describe("the Collections window on Forever", function()
  local WFJ, SS

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do
        if rec.fs == widget or (type(rec.fs) == "table" and rec.fs.button == widget) then return false end
      end
    end
    return true
  end

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    H.uiSetup(WFJ, C.UI)
  end

  local function setup(loadedFirst)
    load()
    if loadedFirst then
      C.load()
      for _, m in ipairs(MODULES) do assert.is_true(WFJ[m].init(), m) end
    else
      for _, m in ipairs(MODULES) do assert.is_false(WFJ[m].init(), m) end -- each waits for the addon
      C.load()
      assert.are.equal(4, WFJ.LoadOnDemand.loaded(C.ADDON))
    end
  end

  local function title() return _G.CollectionsJournal.TitleContainer.TitleText:GetText() end
  local function tip(i) return _G["GameTooltipTextLeft" .. (i or 1)]:GetText() end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    C.unload()
  end)

  for _, order in ipairs({ { true, "loaded before the addon" }, { false, "loaded on demand" } }) do
    describe("Blizzard_Collections " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("collections: the title follows each tab's SetTitle and keeps it after a second SetTitle", function()
        assert.are.equal("アカウントコレクション", title())
        C.selectTab(1)
        assert.are.equal("マウント", title())
        C.selectTab(1)
        assert.are.equal("マウント", title())
        C.selectTab(3)
        assert.are.equal("おもちゃ箱", title())
        C.selectTab(4) -- the global HEIRLOOM does not exist: the client writes ""
        assert.are.equal("", title())
        C.selectTab(5)
        assert.are.equal("外見", title())
        alt(true)
        assert.are.equal("Appearances", title())
        alt(false)
        _G.CollectionsJournal:SetTitle("Close") -- not a collections title: left alone
        assert.are.equal("Close", title())
      end)

      it("collections: side tab tooltips, the Toy Box labels, paging and filter buttons are Japanese", function()
        local tabs = _G.CollectionsJournal.TabContainer
        tabs.PetsTab.scripts.OnEnter(tabs.PetsTab)
        assert.are.equal("ペットジャーナル", tip())
        tabs.HeirloomsTab.scripts.OnEnter(tabs.HeirloomsTab)
        assert.are.equal("家宝", tip())
        assert.are.equal("おもちゃ総数", _G.ToyBox.ProgressTracker.Label:GetText())
        assert.are.equal("新規", _G.ToyBox.iconsFrame.spellButton7.new:GetText())
        assert.are.equal("フィルター", _G.ToyBox.FilterDropdown.Text:GetText())
        assert.are.equal("ページ 1 / 1", _G.ToyBox.PagingFrame.PageText:GetText())
        _G.ToyBox.PagingFrame.currentPage, _G.ToyBox.PagingFrame.maxPages = 2, 5
        _G.ToyBox.PagingFrame:Update()
        assert.are.equal("ページ 2 / 5", _G.ToyBox.PagingFrame.PageText:GetText())
        _G.ToyBox.iconsFrame.spellButton1.name.text = "Close" -- a toy's name
        alt(true); alt(false)
        assert.are.equal("Close", _G.ToyBox.iconsFrame.spellButton1.name:GetText())
        assert.is_true(unrecorded(_G.ToyBox.iconsFrame.spellButton1.name))
      end)

      it("collections: heirloom headers and the PvP tag translate on reused frames; names and the class do not",
        function()
          local h = _G.HeirloomsJournal
          C.heirloomPage = { "HEIRLOOMS_CATEGORY_HEAD", { name = "Close", pvp = true }, "HEIRLOOMS_CATEGORY_WEAPON",
            { name = "Bloodied Arcanite Reaper" } }
          h:LayoutCurrentPage()
          assert.are.equal("頭", h.heirloomHeaderFrames[1].text:GetText())
          assert.are.equal("武器", h.heirloomHeaderFrames[2].text:GetText())
          assert.are.equal("PvP戦", h.heirloomEntryFrames[1].special:GetText())
          assert.are.equal("Close", h.heirloomEntryFrames[1].name:GetText())
          C.heirloomPage = { "HEIRLOOMS_CATEGORY_WEAPON", { name = "Close" } }
          h:LayoutCurrentPage()
          assert.are.equal("武器", h.heirloomHeaderFrames[1].text:GetText())
          assert.are.equal("", h.heirloomEntryFrames[1].special:GetText())
          assert.is_true(unrecorded(h.heirloomEntryFrames[1].name))
          assert.are.equal("Hunter", h.ClassDropdown.Text:GetText())
          h.ClassDropdown:UpdateText()
          assert.is_true(unrecorded(h.ClassDropdown.Text))
        end)

      it("mountjournal: labels, the mount button and its tooltip follow their writers; mount text is untouched",
        function()
          local m = _G.MountJournal
          assert.are.equal("マウント総数", m.MountCount.Label:GetText())
          assert.are.equal("検索", m.searchBox.Instructions:GetText()) -- the search box's placeholder
          assert.are.equal("キャラクターを表示", m.MountDisplay.ModelScene.TogglePlayer.TogglePlayerText:GetText())
          assert.are.equal("マウント装備はレベル20で解放", m.BottomLeftInset.SlotRequirementLabel:GetText())
          assert.are.equal("マウント装備でマウントを強化しよう", m.BottomLeftInset.SlotLabel:GetText())
          C.equipmentName = "Close" -- an item's name in the same FontString
          _G.MountJournal_UpdateEquipment()
          assert.are.equal("Close", m.BottomLeftInset.SlotLabel:GetText())
          assert.are.equal("騎乗", m.MountButton:GetText())
          C.mount = { name = "Close", source = "Close", lore = "Close", active = true }
          _G.MountJournal_UpdateMountDisplay()
          assert.are.equal("降りる", m.MountButton:GetText())
          for _, w in ipairs({ m.MountDisplay.InfoButton.Name, m.MountDisplay.InfoButton.Source,
            m.MountDisplay.InfoButton.Lore }) do
            assert.are.equal("Close", w:GetText())
            assert.is_true(unrecorded(w))
          end
          local row = C.mountRow(1, { name = "Close" })
          assert.are.equal("新規", row.new:GetText())
          assert.are.equal("安定飛行のみ", row.SteadyFlightLabel:GetText())
          assert.are.equal("Close", row.name:GetText())
          assert.is_true(unrecorded(row.name))
          _G.GameTooltip:SetOwner(m.MountButton)
          _G.GameTooltip:SetText(_G.MOUNT_SUMMON_TOOLTIP)
          assert.are.equal("選択したマウントを召喚または解除します。", tip())
        end)

      -- MountJournalMountButton_OnEnter: the button's text, the summon or unwrap line, then the mount's usability
      -- error from C_MountJournal.GetMountUsabilityByID as an error line (blizzard_mountcollection.lua:843-863)
      it("mountjournal: the mount button's usability line is Japanese; the reveal key shows English; off writes "
        .. "nothing", function()
          local m, tt = _G.MountJournal, _G.GameTooltip
          local function enter(errorText)
            tt:SetOwner(m.MountButton)
            tt:SetText(_G.MOUNT)
            tt:AddLine(_G.MOUNT_SUMMON_TOOLTIP)
            if errorText then tt:AddLine(errorText) end
            tt:Show()
          end
          enter(_G.SPELL_FAILED_JOURNEYMAN_RIDING_REQUIREMENT)
          assert.are.equal("騎乗", tip(1))
          assert.are.equal("選択したマウントを召喚または解除します。", tip(2))
          assert.are.equal("Journeyman Ridingのスキルが必要です", tip(3))
          alt(true)
          assert.are.equal("Requires Journeyman Riding skill", tip(3))
          alt(false)
          assert.are.equal("Journeyman Ridingのスキルが必要です", tip(3))
          enter("Close") -- no error line: as written
          assert.are.equal("Close", tip(3))
          WFJ.State.setEnabled(false)
          enter(_G.SPELL_FAILED_JOURNEYMAN_RIDING_REQUIREMENT)
          assert.are.equal("Requires Journeyman Riding skill", tip(3))
          WFJ.State.setEnabled(true)
        end)

      it("mountjournal with Japanese names on: the shown mount's Name is its Japanese; source and lore stay",
        function()
          WFJ.Data.add("name", { [WFJ.Names.key("Swift Brown Steed")] = "スウィフト・ブラウン・スティード\tすうぃふと" })
          local m, info = _G.MountJournal, _G.MountJournal.MountDisplay.InfoButton
          C.mount = { name = "Swift Brown Steed", source = "Vendor: Katie Hunter", lore = "Fast." }
          _G.MountJournal_UpdateMountDisplay()
          assert.are.equal("スウィフト・ブラウン・スティード", info.Name:GetText())
          assert.are.equal("Vendor: Katie Hunter", info.Source:GetText())
          alt(true)
          assert.are.equal("Swift Brown Steed", info.Name:GetText())
          alt(false)
          C.mount = { name = "Nobody Known Steed", source = "", lore = "" }
          _G.MountJournal_UpdateMountDisplay()
          assert.are.equal("Nobody Known Steed", info.Name:GetText())
          assert.are.equal("騎乗", m.MountButton:GetText())
        end)

      it("mountjournal with Japanese names on: a list row's name is its Japanese, on a reused row too", function()
        WFJ.Data.add("name", {
          [WFJ.Names.key("Swift Brown Steed")] = "スウィフト・ブラウン・スティード\tすうぃふと",
          [WFJ.Names.key("Cerulean Prideclaw")] = "セルリアン・プライドクロー\tせるりあん",
        })
        local row = C.mountRow(1, { name = "Swift Brown Steed" })
        assert.are.equal("スウィフト・ブラウン・スティード", row.name:GetText())
        alt(true)
        assert.are.equal("Swift Brown Steed", row.name:GetText())
        alt(false)
        assert.are.equal("スウィフト・ブラウン・スティード", row.name:GetText())
        C.mountRow(1, { name = "Cerulean Prideclaw" }) -- the pool hands the row to another mount
        assert.are.equal("セルリアン・プライドクロー", row.name:GetText())
        C.mountRow(1, { name = "Nobody Known Steed" })
        assert.are.equal("Nobody Known Steed", row.name:GetText())
        WFJ.State.setNames(false)
        C.mountRow(1, { name = "Swift Brown Steed" })
        assert.are.equal("Swift Brown Steed", row.name:GetText())
        WFJ.State.setNames(true)
      end)

      it("mountjournal with Japanese names on: a selected row keeps its Japanese name", function()
        WFJ.Data.add("name", { [WFJ.Names.key("Swift Brown Steed")] = "スウィフト・ブラウン・スティード\tすうぃふと" })
        local row = C.mountRow(1, { name = "Swift Brown Steed" })
        assert.are.equal("スウィフト・ブラウン・スティード", row.name:GetText())
        -- selecting it fills the row again through the initializer alone, with no callback from the list
        C.mountSelect(1, { name = "Swift Brown Steed" })
        assert.are.equal("スウィフト・ブラウン・スティード", row.name:GetText())
        alt(true)
        assert.are.equal("Swift Brown Steed", row.name:GetText())
        alt(false)
      end)

      it("petjournal: labels, the summon button and the empty card translate; pet names do not", function()
        local p = _G.PetJournal
        assert.are.equal("ペット総数", p.PetCount.Label:GetText())
        assert.are.equal("お気に入りのペットを\nランダムに召喚", p.SummonRandomPetSpellFrame.Label:GetText())
        p.SummonRandomPetSpellFrame:UpdateDisplay()
        assert.are.equal("お気に入りのペットを\nランダムに召喚", p.SummonRandomPetSpellFrame.Label:GetText())
        assert.are.equal("左のリストからペットを選択してください。", p.PetCard.PetInfo.name:GetText())
        C.pet = { name = "Close", summoned = true }
        _G.PetJournal_UpdatePetCard()
        _G.PetJournal_UpdateSummonButtonState()
        assert.are.equal("Close", p.PetCard.PetInfo.name:GetText())
        assert.is_true(unrecorded(p.PetCard.PetInfo.name))
        assert.are.equal("帰還", p.SummonButton:GetText())
        local row = C.petRow(1, { name = "Close" })
        assert.are.equal("新規", row.new:GetText())
        assert.are.equal("Close", row.name:GetText())
        _G.GameTooltip:SetOwner(p.PetCount)
        _G.GameTooltip:SetText(_G.BATTLE_PETS_TOTAL_PETS_TOOLTIP)
        assert.are.equal("所有しているペットの総数。", tip())
      end)

      it("wardrobe: tabs, search progress, paging and slot tooltips translate; set and class names do not",
        function()
          local w = _G.WardrobeCollectionFrame
          assert.are.equal("アイテム", w.ItemsTab:GetText())
          assert.are.equal("セット", w.SetsTab:GetText())
          assert.are.equal("読み込み中...", w.SearchBox.ProgressFrame.LoadingFrame.Text:GetText())
          assert.are.equal("期間限定セット", w.SetsCollectionFrame.DetailsFrame.LimitedSet.Text:GetText())
          -- the shortcuts HelpTip's appended frame; its colour-carrying English matched whole
          local shortcuts = _G.TrackingInterfaceShortcutsFrame
          assert.are.equal("|cFFFFD200[Shiftクリック]|r", shortcuts.HeaderText:GetText())
          assert.are.equal("外見の入手元の追跡を設定します。", shortcuts.Text:GetText())
          alt(true)
          assert.are.equal("|cFFFFD200[Shift Click]|r", shortcuts.HeaderText:GetText())
          alt(false)
          assert.are.equal("新規", w.ItemsCollectionFrame.Models[2].NewString:GetText())
          assert.are.equal("ページ 1 / 1", w.ItemsCollectionFrame.PagingFrame.PageText:GetText())
          assert.are.equal("フィルター", w.FilterButton.Text:GetText())
          local details = w.SetsCollectionFrame.DetailsFrame
          details.Name.text, details.Label.text = "Close", "Close"
          alt(true); alt(false)
          assert.are.equal("Close", details.Name:GetText())
          assert.is_true(unrecorded(details.Name))
          assert.is_true(unrecorded(details.Label))
          assert.are.equal("Hunter", w.ClassDropdown.Text:GetText())
          _G.GameTooltip:SetOwner(w.ItemsCollectionFrame.SlotsFrame.Buttons[1])
          _G.GameTooltip:SetText(_G.HEADSLOT)
          assert.are.equal("頭", tip())
          _G.GameTooltip:SetOwner(w.SearchBox)
          _G.GameTooltip:SetText(_G.WARDROBE_NO_SEARCH)
          assert.are.equal("このカテゴリーでは検索できません。", tip())
        end)
    end)
  end

  it("hooks install once", function()
    setup(true)
    for _, m in ipairs(MODULES) do assert.is_false(WFJ[m].setup(), m) end
    assert.are.equal(1, #Stub.hooks["CollectionsJournal:SetTitle"])
    assert.are.equal(1, #Stub.hooks["HeirloomsJournal:LayoutCurrentPage"])
    assert.are.equal(1, #Stub.hooks["MountJournal_UpdateMountDisplay"])
    assert.are.equal(1, #Stub.hooks["PetJournal_UpdatePetCard"])
    assert.are.equal(1, #Stub.hooks["WardrobePagingFrame:Update"])
  end)

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    load()
    local j = C.load()
    j.TitleContainer = "nope"
    j.TabContainer.PetsTab = 42
    _G.ToyBox.iconsFrame = true
    _G.ToyBox.PagingFrame = "x"
    _G.HeirloomsJournal.heirloomHeaderFrames = 7
    _G.HeirloomsJournal.UpdateButton = "nope"
    _G.MountJournal.ScrollBox = false
    _G.MountJournal.MountButton = "nope"
    _G.MountJournal_UpdateEquipment = 5
    _G.PetJournal.SummonRandomPetSpellFrame = "nope"
    _G.PetJournal_UpdatePetCard = {}
    _G.WardrobeCollectionFrame.ItemsCollectionFrame.Models = "nope"
    _G.WardrobeCollectionFrame.ItemsCollectionFrame.SlotsFrame.Buttons = 3
    assert.has_no.errors(function()
      for _, m in ipairs(MODULES) do assert.is_true(WFJ[m].init(), m) end
    end)
    assert.are.equal("マウント総数", _G.MountJournal.MountCount.Label:GetText()) -- the rest still works
    assert.is_nil(Stub.hooks["MountJournal_UpdateEquipment"]) -- a non-function is never hooked
  end)

  it("a client without the window: every init returns false and hooks nothing", function()
    load()
    local before = 0
    for _ in pairs(Stub.hooks) do before = before + 1 end
    for _, m in ipairs(MODULES) do assert.is_false(WFJ[m].init(), m) end
    Stub.loadedAddons[C.ADDON] = true -- the addon name loaded, but no CollectionsJournal
    for _, m in ipairs(MODULES) do
      assert.is_false(WFJ[m].init(), m)
      assert.is_false(WFJ[m].setup(), m)
    end
    local after = 0
    for _ in pairs(Stub.hooks) do after = after + 1 end
    assert.are.equal(before, after)
  end)
end)
