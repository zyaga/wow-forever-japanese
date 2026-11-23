-- UI/NameLabels.lua: a widget that holds only a game name shows the name's Japanese while names are on, through the
-- same records as every other line (the reveal key, the master switch and a release all give the English back).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local SECRET = {}

describe("name widgets", function()
  local WFJ, fs, players
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(H.UI_FILES)
    H.uiSetup(WFJ, {})
    WFJ.Data.add("name", {
      [WFJ.Names.key("Thrall")] = "スロール\tすろーる",
      [WFJ.Names.key("Bandit Cloak")] = "バンディット・クローク\tばんでぃっと・くろーく",
      [WFJ.Names.key("of the Owl")] = "オブ・ザ・アウル\tおぶ・ざ・あうる",
      [WFJ.Names.key("Blacksmithing")] = "ブラックスミシング\tぶらっくすみしんぐ",
      [WFJ.Names.key("Elwynn Forest")] = "エルウィン・フォレスト\tえるうぃん・ふぉれすと",
    })
    players = {}
    _G.UnitIsPlayer = function(unit) return players[unit] == true end
    _G.issecretvalue = function(v) return v == SECRET end
    WFJ.State.setNames(true)
    fs = Stub.fontString("Thrall", "Fonts\\FRIZQT__.TTF", 12, "")
  end)
  after_each(function()
    _G.UnitIsPlayer, _G.issecretvalue = nil, nil
    Stub.keys.alt = false
    H.uiTeardown()
  end)

  -- the reveal key as the client reports it, then the addon's poll
  local function hold(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  it("shows a known name in Japanese and gives the English back on release", function()
    assert.are.equal(1, WFJ.NameLabels.show("spec", "name", fs))
    assert.are.equal("スロール", fs:GetText())
    WFJ.Render.release("spec")
    assert.are.equal("Thrall", fs:GetText())
  end)

  it("joins an item's name and its suffix", function()
    fs.text = "Bandit Cloak of the Owl"
    assert.are.equal(1, WFJ.NameLabels.show("spec", "name", fs))
    assert.are.equal("バンディット・クローク・オブ・ザ・アウル", fs:GetText())
  end)

  it("leaves a name with no Japanese exactly as the client wrote it, with no marker and no record", function()
    fs.text = "Nobody Known"
    assert.are.equal(0, WFJ.NameLabels.show("spec", "name", fs))
    assert.are.equal("Nobody Known", fs:GetText())
    assert.are.equal(0, fs.calls.addonSetText)
    assert.is_nil(WFJ.SurfaceState.get("spec", "name"))
  end)

  it("does nothing while names are off, and never asks for the name", function()
    WFJ.State.setNames(false)
    local asked, of = 0, WFJ.Names.of
    WFJ.Names.of = function(...) asked = asked + 1; return of(...) end
    assert.are.equal(0, WFJ.NameLabels.show("spec", "name", fs))
    assert.are.equal(0, WFJ.NameLabels.unit("spec", "name", fs, "target"))
    assert.are.equal("Thrall", fs:GetText())
    assert.are.equal(0, asked)
  end)

  it("a name shown turns back to English when names are switched off, and to Japanese when on again", function()
    WFJ.NameLabels.show("spec", "name", fs)
    WFJ.State.setNames(false)
    assert.are.equal("Thrall", fs:GetText())
    WFJ.State.setNames(true)
    assert.are.equal("スロール", fs:GetText())
  end)

  it("the reveal key shows the client's English, and Japanese again on release", function()
    WFJ.NameLabels.show("spec", "name", fs)
    hold(true)
    assert.are.equal("Thrall", fs:GetText())
    hold(false)
    assert.are.equal("スロール", fs:GetText())
  end)

  it("English first mirrors it: English until the key is held", function()
    WFJ.State.setDirection("en")
    WFJ.NameLabels.show("spec", "name", fs)
    assert.are.equal("Thrall", fs:GetText())
    hold(true)
    assert.are.equal("スロール", fs:GetText())
    hold(false)
    WFJ.State.setDirection("ja")
  end)

  it("translation off leaves the English", function()
    WFJ.NameLabels.show("spec", "name", fs)
    WFJ.State.setEnabled(false)
    assert.are.equal("Thrall", fs:GetText())
    WFJ.State.setEnabled(true)
  end)

  it("keeps its Japanese when asked again while it still shows", function()
    WFJ.NameLabels.show("spec", "name", fs)
    local writes = fs.calls.addonSetText
    assert.are.equal(1, WFJ.NameLabels.show("spec", "name", fs))
    assert.are.equal(writes, fs.calls.addonSetText)
  end)

  it("follows the client when it writes another name into the widget", function()
    WFJ.NameLabels.show("spec", "name", fs)
    fs.text = "Nobody Known" -- the client's own write
    assert.are.equal(0, WFJ.NameLabels.show("spec", "name", fs))
    assert.are.equal("Nobody Known", fs:GetText())
  end)

  it("never touches a player's name, even one an NPC shares", function()
    players.target = true
    assert.are.equal(0, WFJ.NameLabels.unit("spec", "name", fs, "target"))
    assert.are.equal("Thrall", fs:GetText())
    players.target = false
    assert.are.equal(1, WFJ.NameLabels.unit("spec", "name", fs, "target"))
    assert.are.equal("スロール", fs:GetText())
  end)

  it("never touches a unit a player controls: a pet's name is the player's own", function()
    _G.UnitPlayerControlled = function(unit) return unit == "pet" end
    finally(function() _G.UnitPlayerControlled = nil end)
    assert.are.equal(0, WFJ.NameLabels.unit("spec", "name", fs, "pet"))
    assert.are.equal("Thrall", fs:GetText())
    assert.are.equal(1, WFJ.NameLabels.unit("spec", "name", fs, "target"))
    assert.are.equal("スロール", fs:GetText())
    WFJ.Render.release("spec")
    _G.UnitPlayerControlled = function() return SECRET end -- an answer the client hides: the name stays
    assert.are.equal(0, WFJ.NameLabels.unit("spec", "name", fs, "target"))
    assert.are.equal("Thrall", fs:GetText())
  end)

  it("never reads, hashes or writes a name the client hides", function()
    fs.text = SECRET
    local hashed, key = 0, WFJ.Hash.key
    WFJ.Hash.key = function(...) hashed = hashed + 1; return key(...) end
    assert.has_no.errors(function()
      assert.are.equal(0, WFJ.NameLabels.show("spec", "name", fs))
      assert.are.equal(0, WFJ.NameLabels.unit("spec", "name", fs, "target"))
    end)
    assert.are.equal(SECRET, fs.text)
    assert.are.equal(0, hashed)
    assert.are.equal(0, fs.calls.addonSetText)
  end)

  describe("a window whose title is its NPC's name", function()
    local frame
    before_each(function()
      frame = { TitleContainer = { TitleText = Stub.fontString("", "Fonts\\FRIZQT__.TTF", 12, "") } }
      function frame:SetTitle(text) self.TitleContainer.TitleText.text = text end
    end)

    it("shows the name in Japanese now and after every later SetTitle, hooking the window once", function()
      frame:SetTitle("Thrall")
      assert.are.equal(1, WFJ.NameLabels.title("spec", frame))
      assert.are.equal("スロール", frame.TitleContainer.TitleText:GetText())
      frame:SetTitle("Nobody Known")
      assert.are.equal("Nobody Known", frame.TitleContainer.TitleText:GetText())
      frame:SetTitle("Thrall")
      assert.are.equal("スロール", frame.TitleContainer.TitleText:GetText())
      local writes = frame.TitleContainer.TitleText.calls.addonSetText
      WFJ.NameLabels.title("spec", frame) -- asked again: no second hook, so one write per SetTitle
      frame:SetTitle("Nobody Known")
      frame:SetTitle("Thrall")
      assert.are.equal(writes + 1, frame.TitleContainer.TitleText.calls.addonSetText)
    end)

    it("leaves a title another record already shows in Japanese (a dictionary title on the same widget)", function()
      local text = frame.TitleContainer.TitleText
      frame:SetTitle("Thrall")
      WFJ.Render.show("spec", "title", text, "Thrall", "ui", "name", "Thrall")
      local writes = text.calls.addonSetText
      assert.are.equal(1, WFJ.NameLabels.title("spec", frame))
      assert.are.equal(writes, text.calls.addonSetText)
    end)

    it("a player's window (a trade partner, an inspected player) keeps the name", function()
      players.npc = true
      frame:SetTitle("Thrall")
      assert.are.equal(0, WFJ.NameLabels.title("spec", frame))
      assert.are.equal("Thrall", frame.TitleContainer.TitleText:GetText())
    end)

    it("a window named after an object, with no unit behind it, shows the name with no player check", function()
      _G.UnitIsPlayer = function() error("no unit is asked about for an object's window") end
      frame:SetTitle("Thrall")
      assert.are.equal(1, WFJ.NameLabels.title("spec", frame, "title", false))
      assert.are.equal("スロール", frame.TitleContainer.TitleText:GetText())
      frame:SetTitle("Nobody Known")
      assert.are.equal("Nobody Known", frame.TitleContainer.TitleText:GetText())
      frame:SetTitle("Thrall")
      assert.are.equal("スロール", frame.TitleContainer.TitleText:GetText())
    end)

    it("takes a window with no title text, or no window, without an error", function()
      assert.are.equal(0, WFJ.NameLabels.title("spec", {}))
      assert.are.equal(0, WFJ.NameLabels.title("spec", nil))
    end)
  end)

  it("carries a refit when given: a tooltip line is laid out again after each write and on the reveal key", function()
    local refits = 0
    local function refit() refits = refits + 1 end
    assert.are.equal(1, WFJ.NameLabels.show("spec", "L1", fs, nil, refit))
    assert.are.equal(1, refits)
    hold(true)
    assert.are.equal(2, refits)
    hold(false)
    assert.are.equal(3, refits)
    local rank = Stub.fontString("Blacksmithing 135/150", "Fonts\\FRIZQT__.TTF", 12, "")
    assert.are.equal(1, WFJ.NameLabels.lead("spec", "L2", rank, nil, refit))
    assert.are.equal(4, refits)
  end)

  it("without a refit the record carries no ctx, as before", function()
    WFJ.NameLabels.show("spec", "name", fs)
    assert.is_nil(WFJ.SurfaceState.get("spec", "name").meta.ctx)
  end)

  describe("a name followed by what the client wrote after it", function()
    it("keeps a count after the name byte for byte, and gives the whole English back", function()
      fs.text = "Blacksmithing 135/150"
      assert.are.equal(1, WFJ.NameLabels.lead("spec", "rank", fs))
      assert.are.equal("ブラックスミシング 135/150", fs:GetText())
      hold(true)
      assert.are.equal("Blacksmithing 135/150", fs:GetText())
      hold(false)
      assert.are.equal("ブラックスミシング 135/150", fs:GetText())
      WFJ.Render.release("spec")
      assert.are.equal("Blacksmithing 135/150", fs:GetText())
    end)

    it("keeps a coloured level range, with the space inside or outside the colour", function()
      fs.text = "Elwynn Forest|cff40c040 (1-10)|r"
      assert.are.equal(1, WFJ.NameLabels.lead("spec", "area", fs))
      assert.are.equal("エルウィン・フォレスト|cff40c040 (1-10)|r", fs:GetText())
      fs.text = "Elwynn Forest |cffffffff(10)|r"
      assert.are.equal(1, WFJ.NameLabels.lead("spec", "area", fs))
      assert.are.equal("エルウィン・フォレスト |cffffffff(10)|r", fs:GetText())
      fs.text = "Blacksmithing 135|cnGREEN_FONT_COLOR:(+5)|r/150"
      assert.are.equal(1, WFJ.NameLabels.lead("spec", "area", fs))
      assert.are.equal("ブラックスミシング 135|cnGREEN_FONT_COLOR:(+5)|r/150", fs:GetText())
    end)

    it("shows a whole name with nothing after it", function()
      assert.are.equal(1, WFJ.NameLabels.lead("spec", "area", fs))
      assert.are.equal("スロール", fs:GetText())
    end)

    it("follows the client when it writes the next count, and keeps its Japanese when asked again", function()
      fs.text = "Blacksmithing 135/150"
      WFJ.NameLabels.lead("spec", "rank", fs)
      local writes = fs.calls.addonSetText
      assert.are.equal(1, WFJ.NameLabels.lead("spec", "rank", fs))
      assert.are.equal(writes, fs.calls.addonSetText)
      fs.text = "Blacksmithing 136/150" -- the client's own write
      assert.are.equal(1, WFJ.NameLabels.lead("spec", "rank", fs))
      assert.are.equal("ブラックスミシング 136/150", fs:GetText())
    end)

    it("leaves the line English when words follow the name, or the name has no Japanese", function()
      for _, text in ipairs({ "Blacksmithing 135/150 |cffff2020Trial cap reached|r", "Nobody Known 1/2",
        "Thrall the Warchief" }) do
        fs.text = text
        assert.are.equal(0, WFJ.NameLabels.lead("spec", "rank", fs))
        assert.are.equal(text, fs:GetText())
      end
      assert.are.equal(0, fs.calls.addonSetText)
      assert.is_nil(WFJ.SurfaceState.get("spec", "rank"))
    end)

    it("does nothing while names are off, never reads a hidden value, and takes no widget", function()
      fs.text = "Blacksmithing 135/150"
      WFJ.State.setNames(false)
      assert.are.equal(0, WFJ.NameLabels.lead("spec", "rank", fs))
      assert.are.equal("Blacksmithing 135/150", fs:GetText())
      WFJ.State.setNames(true)
      fs.text = SECRET
      assert.has_no.errors(function() assert.are.equal(0, WFJ.NameLabels.lead("spec", "rank", fs)) end)
      assert.are.equal(SECRET, fs.text)
      assert.are.equal(0, WFJ.NameLabels.lead("spec", "rank", nil))
    end)
  end)

  it("takes no widget, an empty widget and a hidden unit without an error", function()
    assert.are.equal(0, WFJ.NameLabels.show("spec", "name", nil))
    fs.text = ""
    assert.are.equal(0, WFJ.NameLabels.show("spec", "name", fs))
    _G.UnitIsPlayer = function() return SECRET end
    fs.text = "Thrall"
    assert.are.equal(0, WFJ.NameLabels.unit("spec", "name", fs, "nameplate3"))
    assert.are.equal("Thrall", fs:GetText())
  end)
end)
