-- UI/MajorFactionToast.lua over the two banners as camelot blizzard_majorfactions builds and writes them
-- (blizzard_majorfactionrenowntoast.lua:90–158, blizzard_majorfactionunlocktoast.lua:40–48).
local Stub = require("tests.lua.spec.wow_stub")
local X = require("tests.lua.spec.stub_framexml_hud")

local UI = {
  MAJOR_FACTION_RENOWN_LEVEL_TOAST = { "Renown %d", "名声 %d" },
  JOURNEY_UNLOCKED_TOAST = { "Journey Unlocked", "ジャーニー解放" },
  RENOWN_REWARD_CAPSTONE_TOOLTIP_TITLE = { "Major Milestone", "大きな節目" },
  RENOWN_REWARD_MILESTONE_TOOLTIP_TITLE = { "Renown %d Rewards", "名声 %d の報酬" },
  RANK = { "Rank", "ランク" },
  ["RenownRewardToast:1832"] = { "Faction Tabard Unlocked", "陣営タバード解放" },
  ["RenownRewardToast:1833"] = { "Insignia Trinket Unlocked", "記章トリンケット解放" },
  ["RenownRewardName:1832"] = { "Rank 1 Rewards", "ランク1の報酬" },
  ["RenownRewardDescription:1832"] = { "Faction Tabard", "陣営タバード" },
}
local NAMES = { "MajorFactionsRenownToast", "MajorFactionUnlockToast" }

local function install()
  local r = CreateFrame("Frame", "MajorFactionsRenownToast")
  r.name = "MajorFactionsRenownToast"
  r.RenownLabel, r.RewardDescription = Stub.fontString(""), Stub.fontString("")
  r.RewardIconMouseOver = CreateFrame("Frame")
  function r.PlayBanner(self, data)
    self.RenownLabel.text = ("Renown %d"):format(data.renownLevel)
    self.RewardDescription.text = data.description or "Rank" -- toastDescriptions joined with "|n" (:70-81)
  end
  local u = CreateFrame("Frame", "MajorFactionUnlockToast")
  u.name = "MajorFactionUnlockToast"
  u.HeaderText, u.FactionName = Stub.fontString(""), Stub.fontString("")
  function u.PlayBanner(self, data)
    self.FactionName.text = data.name
    self.HeaderText.text = "Journey Unlocked"
  end
end

describe("the major faction banners on Forever", function()
  local WFJ
  before_each(function()
    WFJ = X.load("UI/MajorFactionToast.lua", UI, { before = install })
    WFJ.Labels.forbidNames(WFJ.MajorFactionToast.NEVER_TOUCH)
    assert.is_true(WFJ.MajorFactionToast.init())
  end)
  after_each(function() X.teardown(NAMES) end)

  it("the renown label and the unlock header translate; a faction name and server text stay as written", function()
    _G.MajorFactionsRenownToast:PlayBanner({ renownLevel = 4 })
    assert.are.equal("名声 4", _G.MajorFactionsRenownToast.RenownLabel:GetText())
    assert.are.equal("Rank", _G.MajorFactionsRenownToast.RewardDescription:GetText())
    _G.MajorFactionUnlockToast:PlayBanner({ name = "Journey Unlocked" }) -- a faction named like the header
    assert.are.equal("ジャーニー解放", _G.MajorFactionUnlockToast.HeaderText:GetText())
    assert.are.equal("Journey Unlocked", _G.MajorFactionUnlockToast.FactionName:GetText())
    assert.is_true(X.unrecorded(WFJ, _G.MajorFactionUnlockToast.FactionName))
    X.alt(WFJ, true)
    assert.are.equal("Renown 4", _G.MajorFactionsRenownToast.RenownLabel:GetText())
    X.alt(WFJ, false)
  end)

  it("the reward tooltip's fixed lines translate; a reward's name as the title does not", function()
    local owner = _G.MajorFactionsRenownToast.RewardIconMouseOver
    assert.is_true(WFJ.HelpTooltip.registered(owner))
    _G.GameTooltip:SetOwner(owner)
    _G.GameTooltip:SetText("Renown 4 Rewards")
    assert.are.equal("名声 4 の報酬", _G.GameTooltipTextLeft1:GetText())
    _G.GameTooltip:SetOwner(owner)
    _G.GameTooltip:SetText("Rank") -- a single reward: its name
    assert.are.equal("Rank", _G.GameTooltipTextLeft1:GetText())
  end)

  it("hooks once; wrong types raise nothing; with neither frame init returns false", function()
    assert.is_false(WFJ.MajorFactionToast.init())
    assert.are.equal(1, #Stub.hooks["MajorFactionsRenownToast:PlayBanner"])
    X.teardown(NAMES)
    local wrong = X.load("UI/MajorFactionToast.lua", UI, { before = function()
      install()
      _G.MajorFactionsRenownToast.PlayBanner = 1
      _G.MajorFactionsRenownToast.RewardIconMouseOver = "x"
      _G.MajorFactionUnlockToast = "y"
    end })
    assert.has_no.errors(function() assert.is_true(wrong.MajorFactionToast.init()) end)
    X.teardown(NAMES)
    local bare = X.load("UI/MajorFactionToast.lua", UI)
    assert.has_no.errors(function() assert.is_false(bare.MajorFactionToast.init()) end)
  end)

  it("the reward description's RenownRewardToast rows are Japanese, joined pieces too; Alt shows English", function()
    local toast = _G.MajorFactionsRenownToast
    toast:PlayBanner({ renownLevel = 1, description = "Faction Tabard Unlocked" })
    assert.are.equal("陣営タバード解放", toast.RewardDescription:GetText())
    toast:PlayBanner({ renownLevel = 2, description = "Faction Tabard Unlocked|nInsignia Trinket Unlocked" })
    assert.are.equal("陣営タバード解放|n記章トリンケット解放", toast.RewardDescription:GetText())
    X.alt(WFJ, true)
    assert.are.equal("Faction Tabard Unlocked|nInsignia Trinket Unlocked", toast.RewardDescription:GetText())
    X.alt(WFJ, false)
    assert.are.equal("陣営タバード解放|n記章トリンケット解放", toast.RewardDescription:GetText())
  end)

  it("a reward description with a piece no row has, or another family's row, stays as the client wrote it", function()
    local toast = _G.MajorFactionsRenownToast
    toast:PlayBanner({ renownLevel = 1, description = "Faction Tabard Unlocked|nGryphon Rider's Lance" })
    assert.are.equal("Faction Tabard Unlocked|nGryphon Rider's Lance", toast.RewardDescription:GetText())
    toast:PlayBanner({ renownLevel = 1, description = "Faction Tabard" }) -- a RenownRewardDescription row
    assert.are.equal("Faction Tabard", toast.RewardDescription:GetText())
    toast:PlayBanner({ renownLevel = 1, description = "" })
    assert.are.equal("", toast.RewardDescription:GetText())
  end)

  it("the reward tooltip shows a single reward's RenownRewardName / RenownRewardDescription rows in Japanese",
    function()
      local owner = _G.MajorFactionsRenownToast.RewardIconMouseOver
      _G.GameTooltip:SetOwner(owner)
      _G.GameTooltip:SetText("Rank 1 Rewards")
      _G.GameTooltip:AddLine("Faction Tabard")
      _G.GameTooltip:Show()
      assert.are.equal("ランク1の報酬", _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("陣営タバード", _G.GameTooltipTextLeft2:GetText())
      _G.GameTooltip:SetOwner(owner)
      _G.GameTooltip:SetText("Faction Tabard Unlocked") -- a RenownRewardToast row: not this tooltip's family
      _G.GameTooltip:Show()
      assert.are.equal("Faction Tabard Unlocked", _G.GameTooltipTextLeft1:GetText())
    end)
end)
