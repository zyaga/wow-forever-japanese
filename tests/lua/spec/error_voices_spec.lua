local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

describe("Core/ErrorVoices: the voices the character's error lines may speak in", function()
  local WFJ, S, EV

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "Core/State.lua", "Core/Settings.lua", "Core/Voice.lua",
      "Core/ErrorVoices.lua", "Core/Modifier.lua" })
    S, EV = WFJ.Settings, WFJ.ErrorVoices
    S.load(nil, 1, {})
  end)

  it("offers Automatic, the 18 player voices and the cast's 54 other NPC voices, a submenu per race", function()
    assert.are.equal("auto", EV.CHOICES[1])
    assert.are.equal(1 + 18 + 54, #EV.CHOICES)
    local races = {}
    for i, g in ipairs(EV.GROUPS) do races[i] = g.en end
    assert.are.same(
      { "Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll", "Skyborne", "Goblin" }, races)
    -- the player voices first in each race's submenu, then its NPC voices
    assert.are.same({ "dwarf-m", "dwarf-f", "qdwarfmalegrim" },
      { EV.GROUPS[3].choices[1], EV.GROUPS[3].choices[2], EV.GROUPS[3].choices[3] })
    assert.are.same({ "scourge-m", "scourge-f" }, { EV.GROUPS[5].choices[1], EV.GROUPS[5].choices[2] })
    local seen = {}
    for _, c in ipairs(EV.CHOICES) do
      assert.is_nil(seen[c], c)
      seen[c] = true
    end
  end)

  it("names every voice by race, sex and type in English and Japanese, the race words as the addon spells them",
  function()
    for _, c in ipairs(EV.CHOICES) do
      local t = EV.TEXT[c]
      assert.is_string(t.en, c)
      assert.is_string(t.ja, c)
      if c ~= "auto" then
        assert.is_truthy(t.en:find("^[%a ]+, [fm]%a+ %(.+%)$"), c)
        assert.is_truthy(t.ja:find("・", 1, true) and t.ja:find("（", 1, true), c)
      end
    end
    assert.are.same({ en = "Dwarf, female (guard)", ja = "ドワーフ・女性（衛兵）" }, EV.TEXT.qdwarffemaleguard)
    assert.are.same({ en = "Undead, male (player)", ja = "アンデッド・男性（プレイヤー）" }, EV.TEXT["scourge-m"])
    assert.are.same({ en = "Human, female (player)", ja = "人間・女性（プレイヤー）" }, EV.TEXT["human-f"])
    assert.are.same({ en = "Skyborne, male (NPC)", ja = "スカイボーン・男性（NPC）" }, EV.TEXT.qskybourneelfmale3775)
    local P = H.loadChunks({ "Core/Placeholders.lua" }).Placeholders.RACE
    assert.are.same({ P.Human, P.Orc, P.Dwarf, P.NightElf, P.Scourge, P.Tauren, P.Gnome, P.Troll },
      { EV.RACES[1].ja, EV.RACES[2].ja, EV.RACES[3].ja, EV.RACES[4].ja, EV.RACES[5].ja, EV.RACES[6].ja,
        EV.RACES[7].ja, EV.RACES[8].ja })
  end)

  it("voice.errorVoice: Automatic by default, listed only with a pack, a voice no pack carries not offered", function()
    local d = S.definition("voice.errorVoice")
    assert.are.equal("choice", d.kind)
    assert.are.equal("auto", S.get("voice.errorVoice"))
    assert.is_true(S.isHidden(d))
    WFJ.Voice.register({ format = 2, folder = "WoWForeverJapanese_Voice", lines = {}, errors = { kinds = {},
      voices = { qdwarffemaleguard = { outofrange = { "e-o-qdwarffemaleguard.mp3", 1 } } } } })
    assert.is_false(S.isHidden(d))
    assert.is_false(d.choiceHidden("auto"))
    assert.is_false(d.choiceHidden("qdwarffemaleguard"))
    assert.is_true(d.choiceHidden("qorcmaleguard"))
    assert.is_true(S.set("voice.errorVoice", "qorcmaleguard")) -- kept: it plays once a pack carries it
    assert.is_false((S.set("voice.errorVoice", "elf-m")))
  end)
end)
