-- Core/WordScore: how much of a line, a quest and the whole game the player knows.
local Env = require("tests.lua.spec.word_env")

describe("Core/WordScore", function()
  it("counts a line's words: ignored in neither sum, learning as not known", function()
    local WFJ = Env.load()
    local S, Score = WFJ.WordStatus, WFJ.WordScore
    -- 敵, 倒して (倒す) and だろう (a grammar word, ignored from the start)
    assert.are.same({ 0, 2 }, { Score.line("ja", "quest.description", 7) })
    S.set("ja", "敵\tてき", "known")
    S.set("ja", "倒す\tたおす", "learning")
    assert.are.same({ 1, 2 }, { Score.line("ja", "quest.description", 7) })
    S.set("ja", "倒す\tたおす", "ignored")
    assert.are.same({ 1, 1 }, { Score.line("ja", "quest.description", 7) })
    assert.are.same({ 0, 0 }, { Score.line("ja", "quest.description", 999) })
  end)

  it("reads a quest as one text: description, objectives, progress and turn-in, never the title", function()
    local WFJ = Env.load()
    local S, Score = WFJ.WordStatus, WFJ.WordScore
    S.set("ja", "敵\tてき", "known")
    -- description 敵 倒す, objectives 谷, progress 敵
    assert.are.same({ 2, 4 }, { Score.text("ja", "quest.progress", 7) })
    assert.are.same({ 2, 4 }, { Score.text("ja", "quest.description", 7) })
    assert.are.same({ 1, 2 }, { Score.text("ja", "gossip", "ab") })
  end)

  it("scores English words from the line's own row", function()
    local WFJ = Env.load()
    WFJ.WordStatus.set("en", "enemy", "known")
    assert.are.same({ 1, 2 }, { WFJ.WordScore.text("en", "quest.description", 7) })
    assert.are.same({ 0, 1 }, { WFJ.WordScore.line("en", "gossip", "ab") })
  end)

  it("weights the whole game by how often each word is used, with a figure per kind of text", function()
    local WFJ = Env.load()
    local S, Score = WFJ.WordStatus, WFJ.WordScore
    S.set("ja", "敵\tてき", "known")
    S.set("ja", "増加\tぞうか", "known") -- 増加する follows it
    local game = Score.game("ja")
    -- every use but the grammar word's 7: quest 9+8+3+2+2+1+1+4 = 30, gossip 1, spell 2+6+5 = 13
    assert.are.equal(44, game.counted)
    assert.are.equal(8 + 2 + 6 + 5, game.known)
    assert.are.same({ known = 8, counted = 30 }, game.kinds.quest)
    assert.are.same({ known = 13, counted = 13 }, game.kinds.spell)
    assert.are.same({ known = 0, counted = 1 }, game.kinds.gossip)
    assert.are.equal(game, Score.game("ja")) -- kept until a status changes
    S.set("ja", "倒す\tたおす", "known")
    assert.are.equal(31, Score.game("ja").known)
  end)

  it("gives a whole percent, and none for a text with nothing counted", function()
    local Score = Env.load().WordScore
    assert.are.equal(67, Score.percent(2, 3))
    assert.are.equal(100, Score.percent(5, 5))
    assert.is_nil(Score.percent(0, 0))
  end)
end)
