local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

describe("/wfj covers every setting", function()
  local meta, WFJ, S
  before_each(function()
    meta = Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    -- the surfaces (quest, tooltip, gossip) declare their client names on load
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
    WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    S = WFJ.Settings
    Stub.prints = {}
  end)

  local function wfj(line) SlashCmdList.WFJ(line) end

  it("every non-hidden setting is settable through the slash grammar", function()
    for _, d in ipairs(S.list()) do
      if not d.hidden then
        local before = S.get(d.id)
        if d.id == "enabled" then
          wfj("off"); assert.is_false(S.get("enabled"))
          wfj("on"); assert.is_true(S.get("enabled"))
          wfj("toggle"); assert.is_false(S.get("enabled"))
          wfj("toggle"); assert.is_true(S.get("enabled"))
        elseif d.kind == "boolean" and not d.id:find(".", 1, true) then -- top-level boolean: "<id> <value>"
          wfj(("%s %s"):format(d.id, before and "off" or "on"))
          assert.are.equal(not before, S.get(d.id), d.id)
          wfj(("%s %s"):format(d.id:lower(), before and "on" or "off")) -- the id is matched case-insensitively
          assert.are.equal(before, S.get(d.id), d.id)
        elseif d.kind == "boolean" then
          local group, name = d.id:match("^(.-)%.(.+)$")
          wfj(("%s %s %s"):format(group, name, before and "off" or "on"))
          assert.are.equal(not before, S.get(d.id), d.id)
          wfj(("%s %s"):format(d.id, before and "on" or "off"))
          assert.are.equal(before, S.get(d.id), d.id)
        else
          local other
          if d.kind == "key" then other = before == "ctrl" and "alt" or "ctrl" end
          for _, c in ipairs(d.choices or {}) do if c ~= before then other = c end end
          wfj(("%s %s"):format(d.id, other))
          assert.are.equal(other, S.get(d.id), d.id)
        end
      end
    end
  end)

  it("bare /wfj prints one line per non-hidden setting with its value", function()
    wfj("")
    local n = 0
    for _, d in ipairs(S.list()) do
      if not d.hidden then
        n = n + 1
        local found = false
        for _, line in ipairs(Stub.prints) do
          if line:find("  " .. d.id .. " = ", 1, true) then found = true end
        end
        assert.is_true(found, d.id)
      end
    end
    -- the original eight + collector.enabled + area.interface + area.books + readings.enabled + readings.glosses
    -- + minimapButton
    assert.are.equal(14, n)
  end)

  it("/wfj bug opens the report window on Bug; /wfj log ends with the Lua error count", function()
    local opened, real = 0, WFJ.ReportWindow.open
    WFJ.ReportWindow.open = function() opened = opened + 1 end
    wfj("bug")
    wfj("BUG")
    WFJ.ReportWindow.open = real
    assert.are.equal(2, opened)
    Stub.prints = {}
    wfj("log")
    assert.are.equal("WFJ: errors: 0 recorded, 0 not sent (/wfj bug)", Stub.prints[#Stub.prints])
  end)

  it("reads a setting when no value is given; rejects a bad value with the reason", function()
    wfj("modifier")
    assert.is_truthy(Stub.prints[#Stub.prints]:find("modifier = alt", 1, true))
    wfj("modifier meta")
    assert.is_truthy(Stub.prints[#Stub.prints]:find("expected a key", 1, true))
    assert.are.equal("alt", S.get("modifier"))
  end)

  it("accepts values case-insensitively", function()
    wfj("modifier ALT")
    assert.are.equal("alt", S.get("modifier"))
    wfj("Area.Quests OFF")
    assert.is_false(S.get("area.quests"))
  end)

  it("matches setting ids case-insensitively", function()
    wfj("area itemtooltips off")
    assert.is_false(S.get("area.itemTooltips"))
    wfj("AREA.ITEMTOOLTIPS on")
    assert.is_true(S.get("area.itemTooltips"))
  end)

  it("keeps the version and unknown-command lines", function()
    wfj("version")
    assert.is_truthy(Stub.prints[1]:find(meta.Version, 1, true))
    Stub.prints = {}
    wfj("bogus")
    assert.is_truthy(Stub.prints[1]:find("unknown command 'bogus'", 1, true))
  end)

  it("debug tooltip turns the trace on and off and shows it in a window, colour codes as text", function()
    local F = require("tests.lua.spec.stub_fixwindow")
    F.install() -- the window templates (ButtonFrameTemplate, ScrollingEditBoxTemplate)
    F.scrollUtil()
    wfj("debug tooltip on")
    assert.are.same({}, WFJ.Tooltip.trace)
    WFJ.Tooltip.trace[1] = "[12:00:00] GameTooltip secret spell id=<secret> |cffffd100gold|r"
    wfj("debug tooltip")
    local window = _G.WFJTooltipTrace
    assert.is_truthy(window and window:IsShown())
    assert.are.equal("[12:00:00] GameTooltip secret spell id=<secret> ||cffffd100gold||r", window.text.value)
    assert.is_truthy(Stub.prints[#Stub.prints]:find("1 passes shown", 1, true))
    wfj("debug tooltip off")
    assert.is_nil(WFJ.Tooltip.trace)
  end)

  it("debug sub-verbs read the shipped data", function()
    wfj("debug hash")
    local n = #H.vectors().cases
    assert.is_truthy(Stub.prints[#Stub.prints]:find(("hash vectors: %d/%d ok"):format(n, n), 1, true))
    Stub.prints = {}
    wfj("debug quest 2")
    local out = table.concat(Stub.prints, "\n")
    assert.is_truthy(out:find("quest.title: trusted (h1 d311f9a5)", 1, true))
    assert.is_truthy(out:find("Sharptalon's Claw", 1, true)) -- the item name, in English letters
    assert.is_truthy(out:find("quest.progress:", 1, true))
    Stub.prints = {}
    wfj("debug quest 5")
    out = table.concat(Stub.prints, "\n")
    assert.is_truthy(out:find("quest.progress: -", 1, true)) -- an unshipped field prints a dash
    Stub.prints = {}
    wfj("debug quest 999999")
    assert.is_truthy(Stub.prints[#Stub.prints]:find("quest 999999: not shipped", 1, true))
    Stub.prints = {}
    wfj("debug item " .. tostring((next(WFJ.Data.item))))
    assert.is_truthy(Stub.prints[1]:find("item.description: unaligned", 1, true))
    Stub.prints = {}
    wfj("debug spell " .. tostring((next(WFJ.Data.spell))))
    assert.is_truthy(Stub.prints[1]:find("spell.description: unaligned", 1, true))
    Stub.prints = {}
    -- a sectioned line (a heading with optional paragraphs) has no single Japanese text to print
    local get = WFJ.Lookup.get
    WFJ.Lookup.get = function(kind) -- luacheck: ignore 212
      if kind == "spell.aura" then return { status = "t", h1 = 1, sections = { head = "見出し", {}, {} } } end
    end
    wfj("debug spell 1229741")
    WFJ.Lookup.get = get
    assert.is_truthy(table.concat(Stub.prints, "\n"):find("spell.aura: t (h1 00000001) 2 sections", 1, true))
    Stub.prints = {}
    wfj("debug gossip")
    assert.is_truthy(Stub.prints[1]:find(("gossip entries: %d"):format(WFJ.Data.count("gossip")), 1, true))
    Stub.prints = {}
    wfj("debug bogus")
    assert.is_truthy(Stub.prints[1]:find("unknown command 'debug bogus'", 1, true))
    Stub.prints = {}
    wfj("debug quest")
    assert.is_truthy(Stub.prints[1]:find("usage: /wfj debug quest <id>", 1, true))
    Stub.prints = {}
    wfj("debug quest 2.5")
    assert.is_truthy(Stub.prints[1]:find("usage: /wfj debug quest <id>", 1, true))
    Stub.prints = {}
    wfj("debug")
    assert.is_truthy(table.concat(Stub.prints, "\n"):find("data: quests %d+")) -- the shipped quest count
    assert.is_truthy(table.concat(Stub.prints, "\n"):find("placeholders: 0 unknown tokens seen", 1, true))
  end)

  it("debug prints font failures with pending and per-surface detail; debug fonts retries now", function()
    wfj("debug")
    assert.is_truthy(table.concat(Stub.prints, "\n"):find("font failures: 0 (0 pending)", 1, true))
    Stub.prints = {}
    wfj("debug fonts")
    local out = table.concat(Stub.prints, "\n")
    assert.is_truthy(out:find("fonts: no retry started", 1, true))
    assert.is_truthy(out:find("fonts: records pending 0 → 0 after a retry now · own widgets pending 0", 1, true))
  end)

  it("debug objective prints the objective index counts, area rows included", function()
    wfj("debug objective")
    local c = WFJ.ObjectiveIndex.counts
    assert.are.equal(WFJ.Data.count("objective") + WFJ.Data.count("area"), c.shipped)
    assert.are.equal(WFJ.Data.count("objective"), c.byType.objective)
    assert.are.equal(WFJ.Data.count("area"), c.byType.area)
    assert.are.equal(c.shipped, c.indexed + c.ambiguous)
    assert.is_truthy(table.concat(Stub.prints, "\n"):find(
      ("objectives: shipped %d (objective %d · area %d) · indexed %d · ambiguous %d")
      :format(c.shipped, c.byType.objective, c.byType.area, c.indexed, c.ambiguous), 1, true))
  end)

  it("debug ui prints the UI index counts and the unresolved keys", function()
    wfj("debug ui")
    local out = table.concat(Stub.prints, "\n")
    local n = WFJ.Data.count("ui")
    -- the stub client defines almost no UI globals: fingerprint rows are hashed, the rest unresolved (the tooltip
    -- stub's ITEM_SPELL_TRIGGER_ONEQUIP is the one global-string key it holds)
    local c = WFJ.UIIndex.counts
    -- `ambiguous` is part of the accounting, not assumed zero. Two shipped rows whose English the Forever import
    -- made identical land there, and the index shows neither rather than guess between them, so the total only
    -- balances when they are counted. `mismatched` stays a real number for the same reason.
    assert.is_true(c.hashed > 0 and c.unresolved > 0)
    assert.are.equal(n, c.indexed + c.hashed + c.unresolved + c.ambiguous + c.mismatched)
    assert.is_truthy(out:find(("ui: shipped %d · indexed %d · hashed %d · mismatched %d · ambiguous %d · unresolved %d")
      :format(n, c.indexed, c.hashed, c.mismatched, c.ambiguous, c.unresolved), 1, true))
    assert.is_truthy(out:find(" · unsupported 0", 1, true))
    assert.is_truthy(out:find("  unresolved: ", 1, true))
    assert.is_truthy(out:find(" … +" .. (c.unresolved - 10), 1, true))
    Stub.prints = {}
    wfj("debug")
    assert.is_truthy(table.concat(Stub.prints, "\n"):find("ui: shipped " .. n, 1, true))
  end)

  it("config opens the panel through Compat; debug prints without error", function()
    wfj("config")
    assert.are.same({ "OpenToCategory", 42 }, Stub.settingsCalls[#Stub.settingsCalls])
    -- the subpages by name; an unknown page opens the main one
    wfj("config collector")
    assert.are.same({ "OpenToCategory", 43 }, Stub.settingsCalls[#Stub.settingsCalls])
    wfj("config ABOUT")
    assert.are.same({ "OpenToCategory", 44 }, Stub.settingsCalls[#Stub.settingsCalls])
    wfj("config nope")
    assert.are.same({ "OpenToCategory", 42 }, Stub.settingsCalls[#Stub.settingsCalls])
    Stub.prints = {}
    assert.has_no.errors(function() wfj("debug") end)
    -- this stub builds no window the window modules declare; the quest, tooltip and game menu names all resolve
    assert.is_truthy(Stub.prints[1]:find("unresolved widgets:", 1, true))
    -- a surface's own names, at the start of a list entry ("friends.tooltip.…" is another surface's)
    for _, ns in ipairs({ "questframe%.", "tooltip%.", "gamemenu%.", "scan%." }) do
      assert.is_nil(Stub.prints[1]:find("[ ,]" .. ns), ns)
    end
    local out = table.concat(Stub.prints, "\n")
    assert.is_truthy(out:find("modifier: alt (either)", 1, true))
    assert.is_truthy(out:find("addon list button: absent", 1, true))
  end)

  it("/wfj modifier takes any key, refuses the main mouse button, and status names the key", function()
    wfj("modifier q")
    assert.are.equal("Q", S.get("modifier"))
    assert.is_truthy(Stub.prints[#Stub.prints]:find("modifier = Q", 1, true))
    wfj("modifier button1")
    assert.is_truthy(Stub.prints[#Stub.prints]:find("expected a key", 1, true))
    assert.are.equal("Q", S.get("modifier"))
    Stub.prints = {}
    wfj("")
    assert.is_truthy(Stub.prints[1]:find("hold Q for English", 1, true))
    Stub.prints = {}
    wfj("debug")
    assert.is_truthy(table.concat(Stub.prints, "\n"):find("modifier: Q (bound · override applied)", 1, true))
  end)

  it("/wfj modifier on a key with an action says it is taken over; a polled key in combat applies now", function()
    Stub.bindings.W = "MOVEFORWARD"
    wfj("modifier w")
    assert.is_truthy(Stub.prints[#Stub.prints - 1]:find("modifier = W", 1, true))
    assert.is_truthy(Stub.prints[#Stub.prints]:find('W was used for "Move Forward"', 1, true))
    Stub.combat = true
    wfj("modifier lalt")
    assert.is_truthy(Stub.prints[#Stub.prints]:find("modifier = lalt", 1, true))
    assert.is_nil(Stub.prints[#Stub.prints]:find("after combat", 1, true))
  end)

  it("a modifier set in combat says it takes effect after combat", function()
    Stub.combat = true
    Stub.bindingCalls = {}
    wfj("modifier f5")
    assert.is_truthy(Stub.prints[#Stub.prints]:find("modifier = F5: takes effect after combat", 1, true))
    assert.are.same({}, Stub.bindingCalls)
  end)
end)

describe("/wfj debug gossip", function()
  it("prints the entry count and each open gossip line's record, key and status", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
    local WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    local player = { name = "Reyn", class = "Hunter", race = "Night Elf" }
    local key = WFJ.Collector.key("Hello there.", player)
    WFJ.Data.add("gossip", { [key] = { "やあ。", "." } })
    local count = ("WFJ: gossip entries: %d"):format(WFJ.Data.count("gossip"))
    Stub.prints = {}
    SlashCmdList.WFJ("debug gossip")
    assert.are.same({ count, "  no gossip window open" }, Stub.prints)

    Stub.showGossip({ text = "Hello there.", options = { "Goodbye." } })
    assert.are.equal("やあ。", GossipFrame.GreetingPanel.ScrollBox.frames[1].GreetingText:GetText())
    Stub.prints = {}
    SlashCmdList.WFJ("debug gossip")
    assert.are.same({
      count,
      "  gossip greeting " .. key .. " trusted",
      "  gossip option.0 " .. WFJ.Collector.key("Goodbye.", player) .. " none",
    }, Stub.prints)
  end)
end)

describe("/wfj debug book", function()
  it("prints the entry count, then the open page's keys, the shipped key and its record", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
    Stub.installItemTextAPI()
    local WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    local player = { name = "Reyn", class = "Hunter", race = "Night Elf" }
    local en = "Greetings, Reyn. This page names you."
    local key = WFJ.Hash.key(WFJ.Normalize.v1("Greetings, $N. This page names you."))
    WFJ.Data.add("book", { [key] = { "ようこそ、{name}。このページはあなたの名を記す。", "." } })
    local count = ("WFJ: book entries: %d"):format(WFJ.Data.count("book"))
    Stub.prints = {}
    SlashCmdList.WFJ("debug book")
    assert.are.same({ count, "  no book open" }, Stub.prints)

    Stub.openItemText({ en }) -- through Main: the book key function and the player's name token
    assert.are.equal("ようこそ、Reyn。このページはあなたの名を記す。", WFJ.ItemText.page.fs.text)
    Stub.prints = {}
    SlashCmdList.WFJ("debug book")
    assert.are.same({
      count,
      "  keys: " .. table.concat(WFJ.Collector.keys(en, player), " "),
      "  shipped: " .. key .. " · record: Japanese",
    }, Stub.prints)
  end)
end)

describe("/wfj collector", function()
  local WFJ, S
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
    WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    S = WFJ.Settings
    Stub.prints = {}
  end)

  local function wfj(line) SlashCmdList.WFJ(line) end
  local function last() return Stub.prints[#Stub.prints] end

  it("prints the status line bare and with status", function()
    WFJ.Collector.record("quest", 9999, "title", "A Forever Quest")
    wfj("collector")
    assert.is_truthy(last():find("WFJ: collector on · 1 entry (1 unsent) · ", 1, true))
    assert.is_truthy(last():find(" of 4.0 MB", 1, true))
    wfj("collector status")
    assert.is_truthy(last():find("WFJ: collector on · 1 entry", 1, true))
  end)

  it("on / off set collector.enabled; other words fall through to the registry", function()
    wfj("collector off")
    assert.is_false(S.get("collector.enabled"))
    assert.is_truthy(last():find("collector off", 1, true))
    wfj("collector on")
    assert.is_true(S.get("collector.enabled"))
    wfj("collector enabled off")
    assert.is_false(S.get("collector.enabled"))
    assert.is_truthy(last():find("collector.enabled = off", 1, true))
  end)

  it("path prints <ACCOUNT> as a literal placeholder, the counts and how to send", function()
    WFJ.Collector.record("quest", 9999, "title", "A Forever Quest")
    wfj("collector path")
    local text = table.concat(Stub.prints, "\n")
    assert.is_truthy(text:find("<ACCOUNT>", 1, true))
    assert.is_truthy(text:find("SavedVariables\\WoWForeverJapanese.lua", 1, true))
    assert.is_truthy(text:find("log out or /reload", 1, true))
    assert.is_truthy(text:find("1 entry", 1, true))
    assert.is_truthy(text:find("/wfj collector send", 1, true))
    assert.is_truthy(text:find("<client folder>", 1, true)) -- the stub client is no beta
  end)

  it("send opens the send window; send all packs every line again", function()
    local opened = {}
    local real = WFJ.CollectorSendWindow.open
    WFJ.CollectorSendWindow.open = function(all) opened[#opened + 1] = all end
    wfj("collector send")
    wfj("collector send all")
    wfj("collector SEND ALL")
    WFJ.CollectorSendWindow.open = real
    assert.are.same({ false, true, true }, opened)
  end)

  it("clear empties the dump, keeps the disclosure flag and prints the count", function()
    Stub.fireAll("PLAYER_ENTERING_WORLD")
    WFJ.Collector.record("quest", 9999, "title", "A Forever Quest")
    WFJ.Collector.record("quest", 9999, "description", "New text.")
    wfj("collector clear")
    wfj("collector clear") -- the second within 5 s clears
    assert.is_truthy(last():find("collector cleared (2)", 1, true))
    assert.are.same({}, WFJ_Collector.entries)
    assert.is_true(WFJ_Collector.disclosed)
  end)

  it("/wfj debug includes the collector line", function()
    wfj("debug")
    local found = false
    for _, line in ipairs(Stub.prints) do
      if line:find("WFJ: collector: on · 0 entries", 1, true) then found = true end
    end
    assert.is_true(found)
  end)
end)

describe("slash / options parity", function()
  local WFJ, S, now
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
    WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    S = WFJ.Settings
    now = 100
    _G.GetTime = function() return now end
    Stub.prints, Stub.bindingCalls = {}, {}
  end)

  local function wfj(line) SlashCmdList.WFJ(line) end
  local function last() return Stub.prints[#Stub.prints] end
  local function sets()
    local n = 0
    for _, c in ipairs(Stub.bindingCalls) do if c[1] == "SetBinding" then n = n + 1 end end
    return n
  end

  it("togglekey binds the parsed chord, case-insensitively, meta keys in the client's order", function()
    for _, typed in ipairs({ "ctrl-j", "CTRL-J", "Ctrl-J" }) do
      wfj("togglekey " .. typed)
      assert.are.equal("WFJ_TOGGLE", Stub.bindings["CTRL-J"], typed)
      assert.are.equal("WFJ: togglekey = CTRL-J", last())
    end
    wfj("togglekey shift-ctrl-q")
    assert.are.equal("WFJ_TOGGLE", Stub.bindings["CTRL-SHIFT-Q"])
    assert.is_nil(Stub.bindings["CTRL-J"]) -- the old key is replaced, like the page
    wfj("togglekey f5")
    assert.are.equal("WFJ_TOGGLE", Stub.bindings.F5)
    assert.are.same({ "SaveBindings", 2 }, Stub.bindingCalls[#Stub.bindingCalls])
  end)

  it("bare togglekey reads the key; none unbinds it; status lists it", function()
    wfj("togglekey")
    assert.are.equal("WFJ: togglekey = not set", last())
    Stub.bindings.BUTTON4 = "WFJ_TOGGLE"
    wfj("togglekey")
    assert.are.equal("WFJ: togglekey = Mouse Button 4", last())
    Stub.prints = {}
    wfj("")
    assert.is_truthy(table.concat(Stub.prints, "\n"):find("  togglekey = Mouse Button 4", 1, true))
    wfj("togglekey none")
    assert.is_nil(Stub.bindings.BUTTON4)
    assert.are.equal("WFJ: togglekey = not set", last())
  end)

  it("refuses malformed chords, lone modifiers, the main buttons, Escape and the modifier's key", function()
    wfj("modifier q")
    Stub.bindingCalls = {}
    for _, typed in ipairs({ "ctrl-", "ctrl-ctrl-j", "foo-j", "alt", "lshift", "ctrl-alt", "button1", "button2",
        "escape", "q" }) do
      wfj("togglekey " .. typed)
      assert.is_truthy(last():find("^WFJ: togglekey: "), typed .. " → " .. last())
    end
    assert.is_truthy(last():find("the key you hold for English", 1, true))
    assert.are.equal(0, sets())
  end)

  it("in combat nothing is written", function()
    Stub.bindings.F5 = "WFJ_TOGGLE"
    Stub.combat = true
    wfj("togglekey f6")
    assert.is_truthy(last():find("cannot change in combat", 1, true))
    wfj("togglekey none")
    assert.is_truthy(last():find("cannot change in combat", 1, true))
    assert.are.equal(0, sets())
    assert.are.equal("WFJ_TOGGLE", Stub.bindings.F5)
  end)

  it("a key bound elsewhere is replaced only when the command is repeated within 5 s", function()
    Stub.bindings.W = "MOVEFORWARD"
    wfj("togglekey w")
    assert.are.equal('WFJ: W is used for "Move Forward"; type the same command again within 5 seconds to replace it',
      last())
    assert.are.equal(0, sets())
    now = now + 6
    wfj("togglekey w") -- too late: asks again
    assert.are.equal("MOVEFORWARD", Stub.bindings.W)
    wfj("togglekey")   -- another command in between forgets it
    now = now + 1
    wfj("togglekey w")
    assert.are.equal("MOVEFORWARD", Stub.bindings.W)
    now = now + 4
    wfj("togglekey W") -- same command (case-insensitive), within 5 s
    assert.are.equal("WFJ_TOGGLE", Stub.bindings.W)
    assert.are.equal("WFJ: togglekey = W", last())
  end)

  it("/wfj readings on|off sets readings.enabled; the long forms still work", function()
    wfj("readings off")
    assert.is_false(S.get("readings.enabled"))
    assert.are.equal("WFJ: readings off", last())
    wfj("readings")
    assert.are.equal("WFJ: readings off", last())
    wfj("readings ON")
    assert.is_true(S.get("readings.enabled"))
    wfj("readings enabled off")
    assert.is_false(S.get("readings.enabled"))
    wfj("readings glosses off")
    assert.is_false(S.get("readings.glosses"))
  end)

  it("collector clear asks first and clears on the repeat within 5 s", function()
    WFJ.Collector.record("quest", 9999, "title", "A Forever Quest")
    wfj("collector clear")
    assert.are.equal("WFJ: type /wfj collector clear again within 5 seconds to clear 1 entry", last())
    assert.are.equal(1, WFJ.Collector.status().entries)
    now = now + 3
    wfj("collector clear")
    assert.are.equal("WFJ: collector cleared (1)", last())
    WFJ.Collector.record("quest", 9999, "title", "A Forever Quest")
    wfj("collector clear")
    now = now + 6
    wfj("collector clear")
    assert.is_truthy(last():find("again within 5 seconds", 1, true))
    assert.are.equal(1, WFJ.Collector.status().entries)
  end)

  it("an empty dump clears without asking; a newer version's file is never cleared and never asks", function()
    wfj("collector clear")
    assert.are.equal("WFJ: collector cleared (0)", last())
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installQuestAPI(); Stub.installTooltipAPI(); Stub.installGossipAPI()
    _G.WFJ_Collector = { version = 2, entries = { anything = { kept = true } } }
    WFJ = Loader.load("WoWForeverJapanese")
    Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese")
    assert.is_true(WFJ.Collector.status().readOnly)
    Stub.prints = {}
    wfj("collector clear")
    assert.are.same({ "WFJ: collector file is from a newer version; not cleared" }, Stub.prints)
    assert.are.same({ kept = true }, WFJ_Collector.entries.anything)
  end)

  it("togglekey refuses + chords, made-up names, the wheel, a second word; readings names its own error", function()
    for _, typed in ipairs({ "ctrl+j", "foo", "ctrl-foo", "mousewheelup", "-j", "f25" }) do
      wfj("togglekey " .. typed)
      assert.is_truthy(last():find("^WFJ: togglekey: "), typed .. " → " .. last())
    end
    assert.is_truthy(Stub.prints[1]:find("use - between keys", 1, true))
    wfj("togglekey ctrl j")
    assert.are.equal("WFJ: togglekey: one key, with - between its parts (ctrl-j)", last())
    assert.are.equal(0, sets())
    wfj("readings bogus")
    assert.are.equal("WFJ: readings: expected on|off", last())
  end)

  it("togglekey writes nothing when the client cannot report combat, and says so", function()
    Stub.bindings.F5 = "WFJ_TOGGLE"
    _G.InCombatLockdown = nil
    wfj("togglekey f6")
    assert.are.equal("WFJ: togglekey: key bindings are not available on this client", last())
    wfj("togglekey none")
    assert.are.equal("WFJ: togglekey: key bindings are not available on this client", last())
    assert.are.equal(0, sets())
    assert.are.equal("WFJ_TOGGLE", Stub.bindings.F5)
  end)
end)
