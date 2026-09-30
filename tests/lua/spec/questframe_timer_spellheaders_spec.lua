-- UI/QuestFrame's QuestInfo additions on Forever's mainline QuestInfo: the quest timer line
-- ("Time Remaining: <SecondsToTime>", rewritten by QuestInfo_ShowTimer and every frame by the timer frame's OnUpdate,
-- mainline/questinfo.lua:5–10, 327–340) and the rewards' spell-group headers (QuestInfo_ShowRewards: a FontString
-- pool, rewardsFrame.spellHeaderPool, written with QUEST_INFO_SPELL_REWARD_TO_HEADER[type], :471–483, 813–828), in
-- the quest window and the map's rewards frame alike. The live time is kept as written; Alt shows the English.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "UI/QuestFrame.lua"

local UI = {
  TIME_REMAINING = { "Time Remaining:", "残り時間:" },
  -- one English, one Japanese (the shipped rows): the Ability header is the Spell header's words
  REWARD_SPELL = { "You will learn the following:", "以下を習得します:" },
  REWARD_ABILITY = { "You will learn the following:", "以下を習得します:" },
  REWARD_AURA = { "You will be affected by:", "以下の効果を受けます:" },
  COMPLETE = { "Complete", "完了" }, -- a dictionary word a header never shows here
}

-- A FontString pool (CreateFontStringPool): Acquire / ReleaseAll / EnumerateActive.
local function headerPool()
  local p = { active = {}, free = {} }
  function p.Acquire(self)
    local fs = table.remove(self.free) or Stub.fontString("")
    self.active[#self.active + 1] = fs
    return fs
  end
  function p.ReleaseAll(self)
    for _, fs in ipairs(self.active) do self.free[#self.free + 1] = fs end
    self.active = {}
  end
  function p.EnumerateActive(self)
    local i = 0
    return function()
      i = i + 1
      return self.active[i]
    end
  end
  return p
end

describe("UI/QuestFrame's timer and spell-group headers", function()
  local WFJ

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI()
    _G.QuestInfoRewardsFrame.spellHeaderPool = headerPool()
    _G.MapQuestInfoRewardsFrame.spellHeaderPool = headerPool()
    _G.QuestInfo_ShowTimer = function() -- questinfo.lua:327–333
      _G.QuestInfoTimerText:SetText(_G.TIME_REMAINING .. " " .. _G.QuestInfoTimerFrame.left)
    end
    _G.QuestInfoTimerFrame:SetScript("OnUpdate", function(self) -- QuestInfoTimerFrame_OnUpdate (:5–10), XML-bound
      _G.QuestInfoTimerText:SetText(_G.TIME_REMAINING .. " " .. self.left)
    end)
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI)
    assert.is_true(WFJ.QuestFrame.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
  end)

  it("the timer line: Japanese label, the live time kept, after ShowTimer and on every OnUpdate; Alt English",
    function()
      local timer, text = _G.QuestInfoTimerFrame, _G.QuestInfoTimerText
      timer.left = "4 Min 59 Sec"
      _G.QuestInfo_ShowTimer()
      assert.are.equal("残り時間: 4 Min 59 Sec", text:GetText())
      timer.left = "4 Min 58 Sec"
      timer.scripts.OnUpdate(timer, 1)
      assert.are.equal("残り時間: 4 Min 58 Sec", text:GetText())
      alt(true)
      assert.are.equal("Time Remaining: 4 Min 58 Sec", text:GetText())
      alt(false)
      assert.are.equal("残り時間: 4 Min 58 Sec", text:GetText())
      text:SetText("Something else: 3") -- another writer: never matched
      timer.scripts.OnUpdate({ left = "x" }, 1)
      assert.are.equal("残り時間: x", text:GetText())
    end)

  it("the spell-group headers of the quest window's and the map's rewards: REWARD_ABILITY shares REWARD_SPELL's "
    .. "Japanese; a reused pooled header follows its new text", function()
      local pool, mapPool = _G.QuestInfoRewardsFrame.spellHeaderPool, _G.MapQuestInfoRewardsFrame.spellHeaderPool
      local a, b = pool:Acquire(), pool:Acquire()
      a.text, b.text = _G.REWARD_ABILITY, _G.REWARD_AURA
      local m = mapPool:Acquire()
      m.text = "Complete" -- not a header key
      WFJ.QuestFrame.onDisplay(_G.QUEST_TEMPLATE_LOG, nil)
      assert.are.equal("以下を習得します:", a:GetText())
      assert.are.equal("以下の効果を受けます:", b:GetText())
      assert.are.equal("Complete", m:GetText())
      alt(true)
      assert.are.equal("You will learn the following:", a:GetText())
      alt(false)
      pool:ReleaseAll()
      local again = pool:Acquire() -- the same FontString, a new header
      again.text = _G.REWARD_AURA
      WFJ.QuestFrame.onDisplay(_G.QUEST_TEMPLATE_LOG, nil)
      assert.are.equal("以下の効果を受けます:", again:GetText())
      assert.are.equal(1, WFJ.SurfaceState.count(WFJ.QuestFrame.SPELL_HEADERS))
    end)
end)
