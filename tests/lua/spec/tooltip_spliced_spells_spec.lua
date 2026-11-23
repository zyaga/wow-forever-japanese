-- A spell whose description splices in other spells' text: the client prints a spliced-in spell's text only once
-- that spell's data is loaded, so the line holds fewer numbers than its Japanese and stays English until then. The
-- addon asks for the spliced-in spells the client has not loaded (Data/SpellIncludes.lua), and only those.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

describe("UI/Tooltip: the spells a spell's description splices in", function()
  local WFJ, cached, asked

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    -- Metamorphosis splices in Menace, Demon Charge and Demonic Howl; this character has Menace loaded only
    cached, asked = { [403828] = true }, {}
    _G.C_Spell = _G.C_Spell or {}
    _G.C_Spell.IsSpellDataCached = function(id) return cached[id] == true end
    _G.C_Spell.RequestLoadSpellData = function(id) asked[#asked + 1] = id end
    local files = {}
    for i, f in ipairs(H.UI_FILES) do files[i] = f end
    files[#files + 1] = "UI/TimeLine.lua"
    files[#files + 1] = "UI/Tooltip.lua"
    WFJ = H.loadChunks(files)
    WFJ.Data.spellIncludes = { [403789] = { 403828, 412788, 412789 } }
    WFJ.Tooltip.init()
  end)

  after_each(function()
    _G.C_Spell.IsSpellDataCached, _G.C_Spell.RequestLoadSpellData = nil, nil
  end)

  it("asks for each spliced-in spell the client has not loaded, and no other", function()
    assert.equals(2, WFJ.Tooltip.loadIncluded(403789))
    assert.same({ 412788, 412789 }, asked)
  end)

  it("asks for nothing once they are loaded, or for a spell that splices in none", function()
    cached[412788], cached[412789] = true, true
    assert.equals(0, WFJ.Tooltip.loadIncluded(403789))
    assert.equals(0, WFJ.Tooltip.loadIncluded(1459))
    assert.same({}, asked)
  end)

  it("does nothing on a client without the spell loading calls", function()
    -- nothing resolved them yet: the first ask finds them missing
    _G.C_Spell.IsSpellDataCached, _G.C_Spell.RequestLoadSpellData = nil, nil
    assert.equals(0, WFJ.Tooltip.loadIncluded(403789))
    assert.same({}, asked)
  end)
end)
