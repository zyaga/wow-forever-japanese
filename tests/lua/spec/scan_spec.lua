-- /wfj debug ui scan: the English still showing on visible frames, split into "the dictionary knows it" (a
-- hook is missing) and "it does not" (a key is missing); text we already replaced is not listed.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua",
  "Core/Translator.lua", "Core/UIStringKeys.lua",
  "Core/UIStrings.lua", "Core/SurfaceState.lua", "Core/Normalize.lua", "Core/Hash.lua",
  "UI/Font.lua", "UI/Render.lua", "UI/Scan.lua" }

local function region(text, shown)
  local fs = Stub.fontString(text)
  fs.shown = shown ~= false
  fs.GetObjectType = function() return "FontString" end
  function fs:IsVisible() return self.shown end
  return fs
end

local function frame(name, visible, regions)
  return { GetName = function() return name end, IsVisible = function() return visible end,
    GetRegions = function() return unpack(regions) end }
end

describe("UI/Scan", function()
  local WFJ, frames, applied

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(FILES)
    applied = region("受注")
    frames = {
      frame("CharacterFrame", true, { region("Strength:"), region("Melee Attack"), region("Accept"),
        region("Hidden label", false), region("18"), region("受注") }),
      frame("HiddenFrame", false, { region("Should not show") }),
      frame("QuestFrame", true, { applied, region("Accept") }),
    }
    local function enumerate(prev)
      local i = 0
      for j, f in ipairs(frames) do if f == prev then i = j end end
      return frames[i + 1]
    end
    WFJ.Compat.init(function(name) if name == "EnumerateFrames" then return enumerate end end)
    WFJ.Scan.init()
    local function h1(t) return (WFJ.Hash.h32x2(WFJ.Normalize.v1(t))) end
    WFJ.UIIndex = WFJ.UIStrings.build({ rows = { ACCEPT = { "受注", h1("Accept"), "." } }, hash = h1,
      english = function(k) return k == "ACCEPT" and "Accept" or nil end })
  end)

  it("lists distinct English on visible frames, known vs unknown, sorted", function()
    local list, n = WFJ.Scan.collect()
    assert.are.equal(3, n)
    assert.are.same({ "Accept", "CharacterFrame", true }, list[1])
    assert.are.same({ "Melee Attack", "CharacterFrame", false }, list[2])
    assert.are.same({ "Strength:", "CharacterFrame", false }, list[3])
  end)

  it("prints a capped report", function()
    local out = {}
    WFJ.Scan.LIMIT = 2
    assert.are.equal(3, WFJ.Scan.run(function(line) out[#out + 1] = line end))
    assert.are.equal("WFJ: ui scan: 3 English texts on visible frames (first 2)", out[1])
    assert.are.equal('  hook? "Accept"  [CharacterFrame]', out[2])
    assert.are.equal('  key?  "Melee Attack"  [CharacterFrame]', out[3])
    assert.is_nil(out[4])
  end)

  it("reports nothing when the client has no EnumerateFrames", function()
    WFJ.Compat.init(function() return nil end)
    local list, n = WFJ.Scan.collect()
    assert.are.equal(0, n)
    assert.are.same({}, list)
  end)
end)
