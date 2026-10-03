-- A quest's title inside a system line ("The Balance of Nature completed.") is shown as its Japanese title when one
-- quest translation answers it, through the resolver UI/TooltipUnit gives Core/UIStrings; anything else is kept.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local UI = {
  ERR_QUEST_COMPLETE_S = { "%s completed.", "%sを完了しました。" },
  ERR_QUEST_ACCEPTED_S = { "Quest accepted: %s", "クエスト受諾: %s" },
  QUEST_ACCEPT = { "%s is starting the quest \"%s\". Would you like to as well?",
    "%sがクエスト「%s」を開始します。あなたも開始しますか？" },
}

describe("quest titles inside system lines", function()
  local WFJ, index
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(H.UI_FILES)
    H.uiSetup(WFJ, UI)
    index = WFJ.UIIndex
  end)
  after_each(function()
    WFJ.UIStrings.questTitle = nil
    H.uiTeardown()
  end)

  local function japanese(line)
    local key, args = index:matchOnly(line, { "ERR_QUEST_COMPLETE_S", "ERR_QUEST_ACCEPTED_S" })
    assert.is_not_nil(key, line)
    return index:fill(index.rows[key][1], args)
  end

  it("a title one translation answers is Japanese; any other is kept as written", function()
    WFJ.UIStrings.questTitle = function(t) return t == "The Balance of Nature" and "自然界のバランス" or nil end
    assert.are.equal("自然界のバランスを完了しました。", japanese("The Balance of Nature completed."))
    assert.are.equal("クエスト受諾: 自然界のバランス", japanese("Quest accepted: The Balance of Nature"))
    assert.are.equal("Verdant Sigilを完了しました。", japanese("Verdant Sigil completed."))
  end)

  it("a dialog filled from its own arguments shows the title in Japanese too; the name stays", function()
    WFJ.UIStrings.questTitle = function(t) return t == "The Balance of Nature" and "自然界のバランス" or nil end
    local en = _G.QUEST_ACCEPT
    local args = index:formatArgs("QUEST_ACCEPT", en, "Reyn", "The Balance of Nature")
    assert.are.equal("Reynがクエスト「自然界のバランス」を開始します。あなたも開始しますか？",
      index:fill(index.rows.QUEST_ACCEPT[1], args))
    args = index:formatArgs("QUEST_ACCEPT", en, "Reyn", "Verdant Sigil")
    assert.are.equal("Reynがクエスト「Verdant Sigil」を開始します。あなたも開始しますか？",
      index:fill(index.rows.QUEST_ACCEPT[1], args))
  end)

  it("with no resolver the title is kept as written", function()
    WFJ.UIStrings.questTitle = nil
    assert.are.equal("The Balance of Natureを完了しました。", japanese("The Balance of Nature completed."))
  end)
end)
