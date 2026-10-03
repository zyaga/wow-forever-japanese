-- TEMPLATED rows: the restricted client-table families whose English is a format string the client fills before
-- showing it (SharedString talent requirement lines, EventToastText's rank toast, FriendshipGain's rank points).
-- No English ships, so a row is found by its live line's digits put back as `%d` (index:matchCounted, through
-- matchOnly) or against the template the client hands the caller (index:matchTemplate). Both stay restricted: only
-- a set naming the family's key finds them.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local REQUIRE = "Spend %d more |4point:points; in %s |4Talent:Talents;"
local LEGACY = "Spend %d more |4point:points; in the %s Legacy Tree"
local UI = {
  ["SharedString:911"] = { REQUIRE, "%2$sのタレントにあと%1$dポイント使う" },
  ["SharedString:1318"] = { LEGACY, "%2$sレガシーツリーにあと%1$dポイント使う" },
  ["SharedString:992"] = { "Tab 1", "タブ1" },
  ["EventToastText:513"] = { "You have reached Rank %d.", "ランク%dに到達した。" },
  ["EventToastText:479"] = { "Your Lotus Claw enchant allows you to carefully extract a Death Lotus!",
    "Lotus Clawのエンチャントで慎重にDeath Lotusを採取できる！" },
  ["FriendshipGain:513"] = { "You gain %d Rank Points.", "ランクポイントを%d獲得した。" },
  ["ServerMessage:1"] = { "[SERVER] Shutdown in %s", "[サーバー] %s後にシャットダウン" },
  -- a restricted family outside the templated ones: a row with an argument stays unresolved, as before
  ["CriteriaText:7"] = { "%d kills", "%d体撃破" },
  -- a global-string template with the same shape: the open match keeps finding it
  RANK_POINTS_GAINED = { "You earn %d Honor Points.", "名誉ポイントを%d獲得した。" },
}

describe("templated client-table rows", function()
  local WFJ, index
  local function fam(name) return WFJ.UIStrings.familyKeys(index.rows, name) end
  local function japanese(key, args) return index:fill(index.rows[key][1], args) end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(H.UI_FILES)
    H.uiSetup(WFJ, UI)
    index = WFJ.UIIndex
  end)
  after_each(function() H.uiTeardown() end)

  it("are templated only in the four families, and only when the Japanese takes an argument", function()
    local U = WFJ.UIStrings
    assert.is_true(U.isTemplatedKey("SharedString:911"))
    assert.is_true(U.isTemplatedKey("EventToastText:1"))
    assert.is_true(U.isTemplatedKey("FriendshipGain:1"))
    assert.is_true(U.isTemplatedKey("ServerMessage:1"))
    assert.is_false(U.isTemplatedKey("CriteriaText:7"))
    assert.is_false(U.isTemplatedKey("EmoteText:1"))
    assert.is_false(U.isTemplatedKey("LEVEL_GAINED"))
    assert.is_false(U.isTemplatedKey(nil))
    -- counted: five templated and two plain restricted rows hashed, the criteria template unresolved
    assert.are.same({ "CriteriaText:7" }, index.problems.unresolved)
    assert.are.equal(1, index.counts.indexed)
    assert.are.equal(7, index.counts.hashed)
  end)

  it("a rank-points chat line is the FriendshipGain row with the live number", function()
    local key, args = index:matchOnly("You gain 25 Rank Points.", fam("FriendshipGain"))
    assert.are.equal("FriendshipGain:513", key)
    assert.are.equal("ランクポイントを25獲得した。", japanese(key, args))
    key, args = index:matchOnly("You gain 1 Rank Points.", fam("FriendshipGain"))
    assert.are.equal("ランクポイントを1獲得した。", japanese(key, args))
    -- coloured: the codes are left out before the digits are put back (their hex digits are no number)
    key, args = index:matchOnly("|cff8080ffYou gain 250 Rank Points.|r", fam("FriendshipGain"))
    assert.are.equal("ランクポイントを250獲得した。", japanese(key, args))
  end)

  it("the rank toast's text is the EventToastText row; the family's plain sentence still by its fingerprint", function()
    local key, args = index:matchOnly("You have reached Rank 3.", fam("EventToastText"))
    assert.are.equal("EventToastText:513", key)
    assert.are.equal("ランク3に到達した。", japanese(key, args))
    key = index:matchOnly("Your Lotus Claw enchant allows you to carefully extract a Death Lotus!",
      fam("EventToastText"))
    assert.are.equal("EventToastText:479", key)
  end)

  it("stays restricted: the open match and another family's set never take a templated row", function()
    assert.is_nil(index:match("You gain 25 Rank Points."))
    assert.is_nil(index:match("You have reached Rank 3."))
    assert.is_nil(index:matchOnly("You gain 25 Rank Points.", fam("EventToastText")))
    assert.is_nil(index:matchOnly("You gain 25 Rank Points.", { "RANK_POINTS_GAINED" }))
    assert.is_nil(index:matchCounted("no digits here"))
    -- a line that is not the template's shape
    assert.is_nil(index:matchOnly("You gain 25 Rank Points today.", fam("FriendshipGain")))
    -- the global-string template is matched as before, and a set naming it still finds it
    local key, args = index:match("You earn 40 Honor Points.")
    assert.are.equal("RANK_POINTS_GAINED", key)
    assert.are.equal("名誉ポイントを40獲得した。", japanese(key, args))
    assert.are.equal("RANK_POINTS_GAINED",
      (index:matchOnly("You earn 40 Honor Points.", { RANK_POINTS_GAINED = true, ["FriendshipGain:513"] = true })))
  end)

  it("a talent requirement line matches its condition's own template: plural forms, text kept, colour kept",
    function()
      local only = fam("SharedString")
      local key, args = index:matchTemplate("Spend 5 more points in Arms Talents", REQUIRE, only)
      assert.are.equal("SharedString:911", key)
      assert.are.equal("Armsのタレントにあと5ポイント使う", japanese(key, args))
      key, args = index:matchTemplate("Spend 1 more point in Beast Mastery Talent", REQUIRE, only)
      assert.are.equal("Beast Masteryのタレントにあと1ポイント使う", japanese(key, args))
      key, args = index:matchTemplate("|cffff2020Spend 10 more points in Fury Talents|r", REQUIRE, only)
      assert.are.equal("|cffff2020Furyのタレントにあと10ポイント使う|r", japanese(key, args))
      key, args = index:matchTemplate("Spend 8 more points in the Warrior Legacy Tree", LEGACY, only)
      assert.are.equal("Warriorレガシーツリーにあと8ポイント使う", japanese(key, args))
      -- a plain SharedString row: the line must be that English
      key, args = index:matchTemplate("Tab 1", "Tab 1", only)
      assert.are.equal("SharedString:992", key)
      assert.are.equal("タブ1", japanese(key, args))
      assert.is_nil(index:matchTemplate("Tab 2", "Tab 1", only))
    end)

  it("matchTemplate refuses a template no row of the set has, or a line that is not its formatting", function()
    local only = fam("SharedString")
    assert.is_nil(index:matchTemplate("Spend 5 more points in Arms Talents", REQUIRE, fam("EventToastText")))
    assert.is_nil(index:matchTemplate("Spend 5 more points in Arms", "Spend %d more points in %s", only))
    assert.is_nil(index:matchTemplate("Learn 5 talents", REQUIRE, only))
    assert.is_nil(index:matchTemplate("", REQUIRE, only))
    assert.is_nil(index:matchTemplate("Spend 5 more points in Arms Talents", nil, only))
    assert.is_nil(index:matchTemplate("Spend 5 more points in Arms Talents", REQUIRE, nil))
    -- never through the digits alone: the plural groups and the name are not in the line's skeleton
    assert.is_nil(index:matchOnly("Spend 5 more points in Arms Talents", only))
  end)

  it("two templated rows of one English with different Japanese are ambiguous and match nothing", function()
    H.uiTeardown()
    H.uiSetup(WFJ, { ["FriendshipGain:1"] = { "You gain %d Rank Points.", "ランクポイントを%d獲得した。" },
      ["FriendshipGain:2"] = { "You gain %d Rank Points.", "%dランクポイント獲得。" } })
    index = WFJ.UIIndex
    assert.are.same({ "FriendshipGain:1", "FriendshipGain:2" }, index.problems.ambiguous)
    assert.is_nil(index:matchOnly("You gain 25 Rank Points.", fam("FriendshipGain")))
  end)

  it("a server notice is found by its text before the trailing argument, only in the asked-for family", function()
    local key, args = index:matchTail("[SERVER] Shutdown in 15 Minutes", fam("ServerMessage"))
    assert.are.equal("ServerMessage:1", key)
    assert.are.equal("15 Minutes", args[1])
    assert.are.equal("[サーバー] 15 Minutes後にシャットダウン", japanese(key, args))
    assert.is_nil(index:matchTail("[SERVER] Shutdown in 15 Minutes", fam("FriendshipGain"))) -- another family
    assert.is_nil(index:matchTail("Something else entirely", fam("ServerMessage")))
    assert.is_nil(index:matchTail("[SERVER] Shutdown in 15 Minutes", {})) -- no family asked for: nothing hashed
  end)
end)
