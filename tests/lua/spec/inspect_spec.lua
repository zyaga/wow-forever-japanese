-- UI/Inspect.lua over an InspectFrame replayed from camelot
-- blizzard_inspectui (camelot/blizzard_inspectui.xml, camelot/inspectpaperdollframe.xml:56–98, mainline/
-- inspectpaperdollframe.lua:28–55 + 223–233 + 285–293, mainline/inspectguildframe.lua:20–37). The title is the
-- inspected player's name and the guild's name is a name: both stay as written. Either load order.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/Inspect.lua"

local ADDON = "Blizzard_InspectUI"

local UI = {
  INSPECT_TALENTS_BUTTON = { "Talents", "タレント" },
  PLAYER_LEVEL = { "Level %s |c%s%s %s|r", "レベル %s |c%s%s %s|r" },
  PLAYER_LEVEL_NO_SPEC = { "Level %s |c%s%s|r", "レベル %s |c%s%s|r" },
  INSPECT_GUILD_FACTION = { "%s Guild", "%sのギルド" },
  INSPECT_GUILD_NUM_MEMBERS = { "%d Guild Members", "ギルドメンバー %d人" },
  UNAVAILABLE = { "Unavailable", "利用不可" }, HEADSLOT = { "Head", "頭" },
  CLOSE = { "Close", "閉じる" }, -- a word a player or a guild may happen to be called
}

local C = {}

local function en(key) return _G[key] end
local function fs(text) return Stub.fontString(text or "") end

local function loadInspect(shape)
  local frame = CreateFrame("Frame", "InspectFrame")
  frame.name = "InspectFrame"
  frame.TitleContainer = { TitleText = fs() }
  function frame.SetTitle(self, text) self.TitleContainer.TitleText.text = text end
  local doll = CreateFrame("Frame", "InspectPaperDollFrame")
  doll.name = "InspectPaperDollFrame"
  if shape ~= "bare" then doll.InspectTalents = Stub.button(nil, en("INSPECT_TALENTS_BUTTON")) end
  if shape == "wrongType" then doll.InspectTalents = "Talents" end
  Stub.namedFontString("InspectLevelText", "")
  function doll.SetLevel(_) -- inspectpaperdollframe.lua:50–54
    if type(_G.InspectLevelText) ~= "table" then return end -- (a test binds the name to a number)
    _G.InspectLevelText.text = C.spec
      and string.format(en("PLAYER_LEVEL"), C.level, "ffc79c6e", C.spec, C.class)
      or string.format(en("PLAYER_LEVEL_NO_SPEC"), C.level, "ffc79c6e", C.class)
  end
  CreateFrame("Button", "InspectHeadSlot")
  local guild = CreateFrame("Frame", "InspectGuildFrame")
  guild.guildName, guild.guildRealmName, guild.guildLevel, guild.guildNumMembers = fs(), fs(), fs(), fs()
  _G.InspectGuildFrame_Update = function() -- inspectguildframe.lua:20–30
    guild.guildName.text = C.guild
    if type(guild.guildLevel) == "table" then
      guild.guildLevel.text = string.format(en("INSPECT_GUILD_FACTION"), C.faction)
    end
    guild.guildNumMembers.text = string.format(en("INSPECT_GUILD_NUM_MEMBERS"), C.members)
  end
  Stub.loadedAddons[ADDON] = true
  return frame
end

describe("the inspect window on Forever", function()
  local WFJ, SS

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function unrecorded(widget)
    for _, bucket in pairs(SS.surfaces()) do
      for _, rec in pairs(bucket) do if rec.fs == widget then return false end end
    end
    return true
  end

  local function boot()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    WFJ = H.loadChunks(FILES)
    SS = WFJ.SurfaceState
    -- the faction's name is a `text` capture (Core/UIStrings ARGS; granted here until the shared table carries it)
    WFJ.UIStrings.ARGS.INSPECT_GUILD_FACTION = WFJ.UIStrings.ARGS.INSPECT_GUILD_FACTION or { [1] = "text" }
    H.uiSetup(WFJ, UI)
    C.level, C.spec, C.class, C.guild, C.faction, C.members = 42, nil, "Warrior", "Close", "Horde", 12
  end

  local function setup(loadedFirst)
    boot()
    if loadedFirst then
      loadInspect()
      assert.is_true(WFJ.Inspect.init())
    else
      assert.is_false(WFJ.Inspect.init()) -- waits for the addon
      loadInspect()
      assert.are.equal(1, WFJ.LoadOnDemand.loaded(ADDON))
    end
  end

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
    for _, n in ipairs({ "InspectFrame", "InspectPaperDollFrame", "InspectLevelText", "InspectHeadSlot",
      "InspectGuildFrame", "InspectGuildFrame_Update" }) do _G[n] = nil end
  end)

  for _, order in ipairs({ { true, "loaded at login" }, { false, "loaded on demand" } }) do
    describe("Blizzard_InspectUI " .. order[2], function()
      before_each(function() setup(order[1]) end)

      it("the Talents button and the level line are Japanese; Alt shows English", function()
        local doll = _G.InspectPaperDollFrame
        assert.are.equal("タレント", doll.InspectTalents:GetText())
        doll:SetLevel()
        assert.are.equal("レベル 42 |cffc79c6eWarrior|r", _G.InspectLevelText:GetText())
        C.spec = "Arms"
        doll:SetLevel()
        assert.are.equal("レベル 42 |cffc79c6eArms Warrior|r", _G.InspectLevelText:GetText())
        alt(true)
        assert.are.equal("Talents", doll.InspectTalents:GetText())
        assert.are.equal("Level 42 |cffc79c6eArms Warrior|r", _G.InspectLevelText:GetText())
        alt(false)
        assert.are.equal("タレント", doll.InspectTalents:GetText())
      end)

      it("the guild page's faction and member lines translate; the guild's name does not", function()
        _G.InspectGuildFrame_Update()
        local guild = _G.InspectGuildFrame
        assert.are.equal("Hordeのギルド", guild.guildLevel:GetText())
        assert.are.equal("ギルドメンバー 12人", guild.guildNumMembers:GetText())
        assert.are.equal("Close", guild.guildName:GetText())
        assert.is_true(unrecorded(guild.guildName))
      end)

      it("the title is the player's name: never touched, whatever it says", function()
        _G.InspectFrame:SetTitle("Close")
        assert.are.equal("Close", _G.InspectFrame.TitleContainer.TitleText:GetText())
        assert.is_true(WFJ.Labels.forbidden(_G.InspectFrame.TitleContainer.TitleText))
        assert.are.equal(0, WFJ.Labels.show("inspect", "x", _G.InspectFrame.TitleContainer.TitleText))
        assert.are.equal("Close", _G.InspectFrame.TitleContainer.TitleText:GetText())
      end)

      it("help tooltips: the Talents button's Unavailable line and an empty slot's name", function()
        local tt = _G.GameTooltip
        tt:SetOwner(_G.InspectPaperDollFrame.InspectTalents)
        tt:AddLine(en("UNAVAILABLE"))
        tt:Show()
        assert.are.equal("利用不可", _G.GameTooltipTextLeft1:GetText())
        tt:SetOwner(_G.InspectHeadSlot)
        tt:SetText(en("HEADSLOT"))
        assert.are.equal("頭", _G.GameTooltipTextLeft1:GetText())
        tt:SetOwner(_G.InspectHeadSlot)
        tt:SetText("Close") -- not a slot word: left alone on a slot's tooltip
        assert.are.equal("Close", _G.GameTooltipTextLeft1:GetText())
      end)
    end)
  end

  it("hooks install once", function()
    setup(true)
    assert.is_false(WFJ.Inspect.setup())
    assert.are.equal(1, #Stub.hooks["InspectPaperDollFrame:SetLevel"])
    assert.are.equal(1, #Stub.hooks["InspectGuildFrame_Update"])
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    boot()
    loadInspect("wrongType")
    assert.has_no.errors(function() WFJ.Inspect.init() end)
    assert.is_nil(Stub.hooks["InspectPaperDollFrame:SetLevel"])
    boot()
    loadInspect()
    _G.InspectLevelText = 7
    _G.InspectGuildFrame.guildLevel = "x"
    assert.has_no.errors(function() WFJ.Inspect.init() end)
    assert.has_no.errors(function() _G.InspectPaperDollFrame:SetLevel() end)
    assert.has_no.errors(function() _G.InspectGuildFrame_Update() end)
    assert.are.equal("ギルドメンバー 12人", _G.InspectGuildFrame.guildNumMembers:GetText())
  end)

  it("without the Forever inspect frame nothing is set up (no InspectTalents, or no frame at all)", function()
    boot()
    assert.is_false(WFJ.Inspect.init()) -- not loaded
    assert.is_false(WFJ.Inspect.setup()) -- no InspectFrame
    loadInspect("bare")
    assert.is_false(WFJ.Inspect.setup())
    assert.is_nil(Stub.hooks["InspectPaperDollFrame:SetLevel"])
    assert.is_nil(Stub.hooks["InspectGuildFrame_Update"])
  end)
end)
