-- UI/ChromieTime.lua over a ChromieTimeFrame replayed from camelot
-- blizzard_chromietimeui (xml:37–41, 105, 124, 134–176; SetupExpansionButtons lua:41–51, card lua:90–101, button
-- SetupButton lua:105–126, OnEnter lua:144–153), in both load orders. A campaign's name and description stay English.
-- Client writes go to `fs.text`.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/ChromieTime.lua"

local ADDON = "Blizzard_ChromieTimeUI"
local UI = {
  CHROMIE_TIME_TITLE_TEXT = { "With time on our side, we can do anything!", "時間は味方、何でもできる！" },
  CHROMIE_TIME_SELECT_EXAPANSION_BUTTON = { "Select", "選択" },
  CHROMIE_TIME_PREVIEW_CARD_DEFAULT_TITLE = { "Timewalking Campaigns", "タイムウォーク・キャンペーン" },
  CHROMIE_TIME_PREVIEW_CARD_DEFAULT_DESCRIPTION = { "Journey back.|n|nPick a campaign!", "過去へ。|n|nキャンペーンを選ぼう！" },
  RECOMMENDED = { "Recommended", "おすすめ" },
  CHROMIE_TIME_CAMPAIGN_COMPLETE = { "Campaign completed", "キャンペーン完了" },
  CHROMIE_TIME_CAMPAIGN_ALREADY_ON = { "You're already on this campaign", "このキャンペーンに参加中です" },
}

local function en(key) return _G[key] end

local OPTIONS = { -- C_ChromieTime.GetChromieTimeExpansionOptions; one campaign is named like a dictionary word
  { name = "Recommended", description = "Select", recommended = true },
  { name = "Northrend", description = "Frozen.", completed = true },
}

local function newButton()
  local b = CreateFrame("Button")
  b.Name = Stub.fontString("")
  b.RecommendLabel = { Label = Stub.fontString(en("RECOMMENDED")), BGLabel = Stub.fontString(en("RECOMMENDED")) }
  return b
end

local function installChromieTime()
  local f = CreateFrame("Frame", "ChromieTimeFrame")
  f.Title = { Text = Stub.fontString(en("CHROMIE_TIME_TITLE_TEXT")) }
  f.SelectButton = Stub.button(nil, en("CHROMIE_TIME_SELECT_EXAPANSION_BUTTON"))
  local card = CreateFrame("Frame")
  card.Name, card.Description = Stub.fontString(""), Stub.fontString("")
  function card.ResetSelection(self)
    self.Name.text = en("CHROMIE_TIME_PREVIEW_CARD_DEFAULT_TITLE")
    self.Description.text = en("CHROMIE_TIME_PREVIEW_CARD_DEFAULT_DESCRIPTION")
  end
  function card.SetCurrentlySelectedExpansion(self, button)
    self.Name.text, self.Description.text = button.buttonInfo.name, button.buttonInfo.description
  end
  card:ResetSelection()
  f.CurrentlySelectedExpansionInfoFrame = card
  local active, free = {}, {}
  f.ExpansionOptionsPool = {
    Acquire = function() local b = table.remove(free) or newButton(); active[b] = true; return b end,
    ReleaseAll = function() for b in pairs(active) do free[#free + 1] = b end; active = {} end,
    EnumerateActive = function() return pairs(active) end,
  }
  function f.SetupExpansionButtons(self)
    self.ExpansionOptionsPool:ReleaseAll()
    for _, info in ipairs(OPTIONS) do
      local b = self.ExpansionOptionsPool:Acquire()
      b.Name.text, b.buttonInfo = info.name, info
    end
  end
  f:HookScript("OnShow", f.SetupExpansionButtons) -- the XML OnShow, before ours
  Stub.loadedAddons[ADDON] = true
  return f
end

local function buttonNamed(f, name)
  for b in f.ExpansionOptionsPool:EnumerateActive() do
    if b.buttonInfo.name == name then return b end
  end
end

describe("the Timewalking campaign window on Forever", function()
  local WFJ

  local function load()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    _G.ChromieTimeFrame = nil
  end)

  for _, order in ipairs({ { true, "loaded before init" }, { false, "loaded on demand" } }) do
    it("Blizzard_ChromieTimeUI " .. order[2] .. ": fixed words are Japanese; campaign names stay English", function()
      load()
      local f
      if order[1] then
        f = installChromieTime()
        assert.is_true(WFJ.ChromieTime.init())
      else
        assert.is_false(WFJ.ChromieTime.init())
        f = installChromieTime()
        assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
      end
      f:Show()
      assert.are.equal("時間は味方、何でもできる！", f.Title.Text:GetText())
      assert.are.equal("選択", f.SelectButton:GetText())
      local card = f.CurrentlySelectedExpansionInfoFrame
      assert.are.equal("タイムウォーク・キャンペーン", card.Name:GetText())
      assert.are.equal("過去へ。|n|nキャンペーンを選ぼう！", card.Description:GetText())
      local named = buttonNamed(f, "Recommended")
      assert.are.equal("Recommended", named.Name:GetText()) -- a campaign's name, never touched
      assert.are.equal("おすすめ", named.RecommendLabel.Label:GetText())
      assert.are.equal("おすすめ", named.RecommendLabel.BGLabel:GetText())
      assert.is_true(WFJ.HelpTooltip.registered(named))
      card:SetCurrentlySelectedExpansion(named) -- a campaign whose description is a dictionary word
      assert.are.equal("Recommended", card.Name:GetText())
      assert.are.equal("Select", card.Description:GetText())
      card:ResetSelection()
      assert.are.equal("タイムウォーク・キャンペーン", card.Name:GetText())
      local tt = _G.GameTooltip
      tt:SetOwner(buttonNamed(f, "Northrend"))
      tt:SetText(en("CHROMIE_TIME_CAMPAIGN_COMPLETE"))
      assert.are.equal("キャンペーン完了", _G.GameTooltipTextLeft1:GetText())
      Stub.keys.alt = true
      WFJ.Modifier.refresh()
      assert.are.equal("Recommended", named.RecommendLabel.Label:GetText())
      assert.is_false(WFJ.ChromieTime.setup()) -- once
    end)
  end

  it("client names bound to the wrong type degrade to untouched English with no error", function()
    load()
    local f = installChromieTime()
    f.Title, f.CurrentlySelectedExpansionInfoFrame, f.SetupExpansionButtons = 4, "card", "not a function"
    assert.has_no.errors(function() assert.is_true(WFJ.ChromieTime.init()) end)
    assert.are.equal("選択", f.SelectButton:GetText())
    load()
    f = installChromieTime()
    f.ExpansionOptionsPool.EnumerateActive = true -- the client itself only acquires and releases
    function f.SetupExpansionButtons() end
    assert.has_no.errors(function() assert.is_true(WFJ.ChromieTime.init()) end)
    assert.has_no.errors(function() f:Show() end)
  end)

  it("no ChromieTimeFrame → init is false, nothing touched", function()
    load()
    Stub.loadedAddons[ADDON] = true
    assert.has_no.errors(function() assert.is_false(WFJ.ChromieTime.init()) end)
  end)
end)
