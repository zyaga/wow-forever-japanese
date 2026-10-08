local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local Loader = require("tests.lua.spec.loader")

local FILES = { "Core/Const.lua", "Core/Compat.lua", "Core/Data.lua", "Data/Meta.lua", "Core/State.lua",
  "Core/Settings.lua", "Core/Modifier.lua", "Core/Collector.lua", "UI/Font.lua", "UI/OptionsText.lua",
  "UI/OptionsWidgets.lua", "UI/KeyCapture.lua", "UI/RevealBinding.lua", "UI/Options.lua" }

-- Every widget the stub created, per page frame (FontStrings and textures live in `children`; frames in Stub.frames).
local function pageFrames(page)
  local out = {}
  for _, f in ipairs(Stub.frames) do if f.parent == page then out[#out + 1] = f end end
  return out
end

-- the shipped quest count as the header prints it (thousands separated), read from the generated data
local function shippedQuests(WFJ)
  local s = tostring(WFJ.Data.meta.counts.quest)
  while true do
    local t, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
    s = t
    if k == 0 then return s end
  end
end

describe("Settings pages from the registry and PAGES", function()
  local WFJ, S, O, list

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    WFJ = H.loadChunks(FILES)
    S, O = WFJ.Settings, WFJ.Options
    WFJ.Compat.init(function(name) return _G[name] end)
    S.load(nil, 1, {})
    WFJ.Collector.load(nil, H.collectorDeps())
    list = O.build()
  end)

  -- the Japanese of a copy key: what the pages show unless the reveal key is held
  local function ja(key, ...) return select(2, WFJ.OptionsText.get(key, ...)) end

  local function control(id)
    for _, c in ipairs(O.controls) do if c.id == id then return c end end
  end

  it("registers main, collector, about as one category and two subcategories; opens a page by id", function()
    assert.are.same({ "main", "collector", "about" }, { list[1].id, list[2].id, list[3].id })
    assert.are.equal(42, WFJ.Compat.registerOptions(list))
    local names = {}
    for _, c in ipairs(Stub.settingsCalls) do names[#names + 1] = c[1] end
    assert.are.same({ "RegisterCanvasLayoutCategory", "RegisterCanvasLayoutSubcategory",
      "RegisterCanvasLayoutSubcategory", "RegisterAddOnCategory" }, names) -- the AddOns category last (the guide)
    assert.are.equal(O.pages.main, Stub.settingsCalls[1][2])
    assert.are.equal("WoW Forever Japanese", Stub.settingsCalls[1][3])
    assert.are.equal(O.pages.collector, Stub.settingsCalls[2][3])
    assert.are.equal("English Collector", Stub.settingsCalls[2][4])
    assert.is_true(WFJ.Compat.openOptions("collector"))
    assert.are.same({ "OpenToCategory", 43 }, Stub.settingsCalls[#Stub.settingsCalls])
    -- no links on the pages: the category list switches pages
    for id, page in pairs(O.pages) do assert.is_nil(page.links, id) end -- no link buttons on any page
    assert.is_nil(WFJ.OptionsText.T["nav.main"]) -- and no copy left for them
  end)

  it("the voice page exists only with a voice pack: built with the others, or added when the pack registers", function()
    H.loadChunk("Core/Voice.lua", nil, WFJ)
    assert.is_nil(O.pages.voice) -- no pack when the pages were built
    WFJ.Compat.registerOptions(list)
    assert.is_false(O.addPage("voice")) -- still no pack
    WFJ.Voice.register({ format = 1, folder = "WoWForeverJapanese_Voice", lines = {} })
    assert.is_true(O.addPage("voice"))
    local last = Stub.settingsCalls[#Stub.settingsCalls]
    assert.are.equal("RegisterCanvasLayoutSubcategory", last[1])
    assert.are.equal(O.pages.voice, last[3])
    assert.are.equal("Voice", last[4])
    assert.is_truthy(control("voice.enabled"))
    assert.is_truthy(control("voice.greeting"))
    assert.is_truthy(control("voice.books"))
    assert.is_false(O.addPage("voice")) -- once
    assert.is_true(O.addPage("voicepanel"))
    assert.are.equal("Voice panel", Stub.settingsCalls[#Stub.settingsCalls][4])
    local again = O.build() -- a pack present at build time: the pages are built with the others, after About
    assert.are.same({ "main", "collector", "about", "voice", "voicepanel" },
      { again[1].id, again[2].id, again[3].id, again[4].id, again[5].id })
  end)

  it("the voice panel page: Panel size and Panel style as dropdowns, then its switches", function()
    H.loadChunk("Core/Voice.lua", nil, WFJ)
    WFJ.Voice.register({ format = 1, folder = "WoWForeverJapanese_Voice", lines = {} })
    O.build()
    local size, style = control("voice.panel.size"), control("voice.panel.style")
    assert.are.equal("choice", size.kind)
    local items = size.dropdown:menuItems()
    assert.are.same({ "Off", "Full", "Compact strip" }, { items[1].text, items[2].text, items[3].text })
    assert.is_true(items[2].isSelected()) -- Full by default
    items[3].setSelected()
    assert.are.equal("strip", S.get("voice.panel.size"))
    local styles = style.dropdown:menuItems()
    assert.are.same({ "Dark", "Parchment" }, { styles[1].text, styles[2].text })
    assert.is_true(styles[2].isSelected()) -- Parchment by default
    for _, id in ipairs({ "voice.panel.keep", "voice.panel.head", "voice.panel.hoverButtons", "voice.panel.fade",
      "voice.panel.combatDim", "voice.panel.questLog", "voice.panel.lock" }) do
      assert.are.equal("boolean", control(id).kind, id)
    end
    assert.is_nil(control("voice.panel.queueBox"))
  end)

  it("our category starts expanded, so its sub-pages show in the list without a click", function()
    local expanded
    local real = _G.Settings.RegisterCanvasLayoutCategory
    _G.Settings.RegisterCanvasLayoutCategory = function(frame, name)
      local c = real(frame, name)
      function c.SetExpanded(_, v) expanded = v end
      return c
    end
    WFJ.Compat.registerOptions(list)
    assert.is_true(expanded)
    _G.Settings.RegisterCanvasLayoutCategory = real
  end)

  it("the collector page: the reminder switch sits right under the collector switch", function()
    local rows
    for _, page in ipairs(O.PAGES) do if page.id == "collector" then rows = page.sections[1].rows end end
    assert.are.same({ "collectorExplain", "collector.enabled", "collector.remind", "collectorStatus",
      "collectorClear" }, rows)
  end)

  it("every non-hidden setting appears exactly once; every row is a setting or a named action", function()
    local seen = {}
    for _, page in ipairs(O.PAGES) do
      for _, section in ipairs(page.sections) do
        for _, id in ipairs(section.rows) do
          local isSetting = S.find(id) == id
          assert.is_true(isSetting or O.ACTIONS[id] ~= nil, "unknown row " .. id)
          assert.is_false(isSetting and O.ACTIONS[id] ~= nil, "row is both " .. id)
          if isSetting then seen[id] = (seen[id] or 0) + 1 end
        end
      end
    end
    for _, d in ipairs(S.list()) do
      if not d.hidden then assert.are.equal(1, seen[d.id], d.id) end
    end
  end)

  it("setting rows read in one language: Japanese, English with the reveal key or translation off",
    function()
    local function each(fn)
      for _, c in ipairs(O.controls) do
        if c.kind == "boolean" then
          local d
          for _, def in ipairs(S.list()) do if def.id == c.id then d = def end end
          fn(c, d)
        end
      end
    end
    each(function(c, d)
      assert.are.equal(d.ja, c.widget.label.en:GetText()) -- the shown line
      assert.are.equal("", c.widget.label.ja:GetText())
      assert.are.equal(WFJ.Font.PATH, (c.widget.label.en:GetFont()))
    end)
    Stub.keys.alt = true
    WFJ.Modifier.refresh()
    WFJ.OptionsWidgets.relabel(true)
    each(function(c, d) assert.are.equal(d.label, c.widget.label.en:GetText()) end)
    Stub.keys.alt = false
    WFJ.Modifier.refresh()
    WFJ.OptionsWidgets.relabel(true)
    each(function(c, d) assert.are.equal(d.ja, c.widget.label.en:GetText()) end)
    WFJ.State.setEnabled(false) -- translation off: English, like the game
    WFJ.OptionsWidgets.relabel(true)
    each(function(c, d) assert.are.equal(d.label, c.widget.label.en:GetText()) end)
    WFJ.State.setEnabled(true)
    WFJ.OptionsWidgets.relabelIfStale() -- the pages are hidden: the flip waits for one to show
    each(function(c, d) assert.are.equal(d.ja, c.widget.label.en:GetText()) end)
    local checked = 0
    for _, fs in ipairs(Stub.fontStrings) do
      if WFJ.OptionsWidgets.hasJapanese(fs:GetText()) then
        checked = checked + 1
        assert.are.equal(WFJ.Font.PATH, (fs:GetFont()), fs:GetText())
      end
    end
    assert.is_true(checked > 30)
  end)

  it("every page fits 640 × 560 without scrolling", function()
    for id, page in pairs(O.pages) do
      assert.is_true(page.bottom <= 560, id .. " bottom " .. page.bottom)
      for _, f in ipairs(pageFrames(page)) do
        local p = f.point
        if p and p[1] == "TOPLEFT" and type(p[2]) == "number" then
          local w, h = f.size and f.size[1] or 0, f.size and f.size[2] or 0
          assert.is_true(-p[3] + h <= 560, id .. " frame bottom")
          assert.is_true(p[2] + w <= 640, id .. " frame right " .. (p[2] + w))
        end
      end
      for _, fs in ipairs(page.children) do
        local p = fs.point
        if p and p[1] == "TOPLEFT" and type(p[2]) == "number" then
          assert.is_true(-p[3] <= 546, id .. " text top")
          assert.is_true(p[2] + (fs.width or 0) <= 640, id .. " text right " .. (p[2] + (fs.width or 0)))
        end
      end
    end
  end)

  it("reflects values, a click sets the setting, and OnShow re-reads a slash-side change", function()
    assert.is_true(control("enabled").widget:GetChecked())
    assert.is_true(control("marker.missing").widget:GetChecked()) -- on by default
    control("enabled").widget:click()
    assert.is_false(S.get("enabled"))
    assert.is_false(WFJ.State.enabled)
    assert.is_true(control("area.books").widget:GetChecked()) -- in the area grid
    S.set("area.gossip", false)
    assert.is_true(control("area.gossip").widget:GetChecked()) -- stale until shown
    O.pages.main:Show()
    assert.is_false(control("area.gossip").widget:GetChecked())
    assert.is_truthy(O.frame.subtitle.en:GetText():find("1.2 MB", 1, true))
    -- translation is off here: English
    assert.is_truthy(O.frame.subtitle.en:GetText():find(shippedQuests(WFJ) .. " quests", 1, true))
  end)

  it("the page title is the addon's name, the same in both languages", function()
    local t = WFJ.OptionsText.T["page.main"]
    assert.are.equal("WoW Forever Japanese (日本語化)", t.en)
    assert.are.equal(t.en, t.ja)
  end)

  it("the header shows the TOC version as written (a release version already starts with v)", function()
    WFJ.VERSION = "v0.1.0-alpha.1"
    O.pages.main:Show()
    local text = O.frame.subtitle.en:GetText()
    assert.are.equal(1, text:find("v0.1.0-alpha.1 · ", 1, true))
    assert.is_nil(text:find("vv", 1, true))
  end)

  it("the meanings checkbox sits in the translation section and turns the meanings off and on", function()
    local rows = O.PAGES[1].sections[1].rows
    assert.are.same({ "enabled", "readings.enabled", "readings.glosses", "minimapButton" }, rows)
    -- the areas moved to three columns to make room (the markers keep one column and their samples)
    assert.are.equal(3, O.PAGES[1].sections[3].columns)
    assert.is_nil(O.PAGES[1].sections[4].columns)
    local fired = {}
    WFJ.State.on("glosses", function(v) fired[#fired + 1] = v end)
    local c = control("readings.glosses")
    assert.is_true(c.widget:GetChecked())
    c.widget:click()
    assert.is_false(S.get("readings.glosses"))
    c.widget:click()
    assert.is_true(S.get("readings.glosses"))
    assert.are.same({ false, true }, fired)
  end)

  it("the modifier dropdown lists the presets, sets a side, lists a bound key only while set", function()
    local ctl = control("modifier")
    local items = ctl.dropdown:menuItems()
    assert.are.equal(9, #items)
    assert.are.equal("Right Shift", items[9].text)
    items[9].setSelected(items[9].data)
    assert.are.equal("rshift", S.get("modifier"))
    assert.is_true(items[9].isSelected())
    assert.is_true(O.setModifier("Q"))
    items = ctl.dropdown:menuItems()
    assert.are.equal(10, #items)
    assert.are.equal("Q", items[10].text)
    assert.is_true(items[10].isSelected())
  end)

  it("on the page: the takeover warning, the toggle conflict, the combat note", function()
    local ctl = control("modifier")
    Stub.bindings.Q = "ACTIONBUTTON5"
    ctl.capture.button:click()
    ctl.capture.button:keyDown("Q")
    assert.are.equal("Q", S.get("modifier"))
    assert.are.equal(ja("warn.takeover", "Q", "Action Button 5", "Q"), ctl.warning.en:GetText())
    assert.is_truthy(ctl.warning.en:GetText():find("「Action Button 5」", 1, true))
    Stub.bindings.J = "WFJ_TOGGLE"
    assert.is_false(O.setModifier("J"))
    assert.are.equal(ja("warn.toggleConflict", "J"), ctl.warning.en:GetText())
    O.pages.main:Show()
    O.setCombat(true) -- the lockdown query still reads false inside PLAYER_REGEN_DISABLED
    assert.are.equal(ja("warn.combat"), ctl.warning.en:GetText())
    assert.is_false(ctl.capture.button:IsEnabled())
    assert.is_false(ctl.dropdown:IsEnabled())
    assert.is_false(O.setModifier("lalt"))
    assert.are.equal("Q", S.get("modifier"))
    O.setCombat(false)
    assert.is_true(ctl.dropdown:IsEnabled())
    assert.is_true(ctl.capture.button:IsEnabled())
  end)

  it("no refresh and no memory reading while the pages are off screen; the header reads memory on show", function()
    local before = Stub.memoryUpdates
    local refreshes = 0
    local real = O.refresh
    O.refresh = function() refreshes = refreshes + 1; return real() end
    S.set("enabled", false)
    S.set("marker.missing", true)
    O.setCombat(true); O.setCombat(false)
    assert.are.equal(0, refreshes)
    assert.are.equal(before, Stub.memoryUpdates)
    O.pages.main:Show()
    assert.are.equal(before + 1, Stub.memoryUpdates)
    S.set("enabled", true)
    assert.are.equal(before + 1, Stub.memoryUpdates) -- refreshes while shown never read memory
    assert.is_true(refreshes >= 2)
    O.refresh = real
  end)

  it("one capture listens at a time", function()
    local reveal, toggle = O.captures[1], O.captures[2]
    reveal.button:click()
    toggle.button:click()
    assert.is_false(reveal.active)
    assert.is_true(toggle.active)
    assert.is_nil(reveal.button.scripts.OnKeyDown)
    toggle.button:keyDown("ESCAPE")
  end)

  it("a stale Replace cannot give the toggle the modifier's key", function()
    Stub.bindings.G = "MOVEFORWARD"
    O.proposeToggle("G")
    assert.are.equal("G", O.toggle.pending)
    assert.is_true(O.setModifier("G")) -- the modifier moves onto the pending key meanwhile
    Stub.bindingCalls = {}
    O.toggle.unbind:click() -- Replace
    assert.are.same({}, Stub.bindingCalls)
    assert.are.equal(ja("warn.revealConflict", "G"), O.toggle.warning.en:GetText())
    O.proposeToggle("F7"); O.pages.main:Show(); O.pages.main:Hide()
    assert.is_nil(O.toggle.pending)
    assert.is_nil(O.toggle.note)
  end)

  it("toggle row: Unbind sits beside Set key on one line; the key text keeps the bundled face", function()
    local t = O.toggle
    assert.are.same({ "LEFT", t.capture.button, "RIGHT", 6, 0 }, t.unbind.point)
    assert.are.equal("UIMenuButtonStretchTemplate", t.capture.button.template) -- the key-binding button art
    assert.are.equal(105, t.capture.button.size[1])
    assert.are.equal(95, t.unbind.size[1])
    assert.are.equal(WFJ.Font.PATH, (t.keyText:GetFont()))
    assert.are.equal(12, select(2, t.keyText:GetFont()))
    O.proposeToggle("F7")
    assert.are.equal("F7", t.keyText:GetText())
    assert.are.equal(WFJ.Font.PATH, (t.keyText:GetFont())) -- one face on the page (W.put), whatever the text
  end)

  it("on the page: toggle key set, a conflict asks to Replace, Unbind clears", function()
    local t = O.toggle
    assert.are.equal("未設定", t.keyText:GetText())
    assert.is_false(t.unbind:IsEnabled())
    O.proposeToggle("F7")
    assert.are.equal("F7", t.keyText:GetText())
    Stub.bindings.G = "MOVEFORWARD"
    Stub.bindingCalls = {}
    O.proposeToggle("G")
    assert.are.same({}, Stub.bindingCalls)
    assert.are.equal(ja("warn.bindReplace", "G", "Move Forward"), t.warning.en:GetText())
    assert.are.equal("置き換える", t.unbind.caption:GetText())
    t.unbind:click()
    assert.are.equal("G", GetBindingKey("WFJ_TOGGLE"))
    assert.are.equal("解除", t.unbind.caption:GetText())
    t.unbind:click()
    assert.is_nil(GetBindingKey("WFJ_TOGGLE"))
    S.set("modifier", "q")
    O.proposeToggle("Q")
    assert.are.equal(ja("warn.revealConflict", "Q"), t.warning.en:GetText())
    assert.is_nil(GetBindingKey("WFJ_TOGGLE"))
  end)

  it("collector status, copy boxes that snap back, and clear-after-a-second-click within 5s", function()
    WFJ.Collector.record("quest", 999999, "title", "A Test Quest")
    O.refresh()
    -- the status line in the page's language (the slash command keeps Collector.describe's English)
    local s, fb = WFJ.Collector.status(), WFJ.Collector.formatBytes
    local line = ("%s・%s件・%s / %s"):format(s.enabled and "オン" or "オフ", s.entries, fb(s.bytes), fb(s.cap))
    if s.errors > 0 then line = line .. " · " .. ja("collector.errors", s.errors) end
    assert.are.equal("状態: " .. line, O.collectorStatus:GetText())
    local box = O.copyBoxes["collector.path"]
    assert.are.equal(WFJ.Collector.PATH, box:GetText())
    box:SetText("edited")
    box.scripts.OnTextChanged(box, true)
    assert.are.equal(WFJ.Collector.PATH, box:GetText())
    local n = WFJ.Collector.status().entries
    local clears = 0
    local realClear = WFJ.Collector.clear
    WFJ.Collector.clear = function() clears = clears + 1; return realClear() end
    local now = 100
    _G.GetTime = function() return now end
    O.collectorClear:click()
    assert.are.equal(0, clears)
    assert.are.equal(ja("collector.confirm", n), O.collectorClear.caption:GetText())
    now = 106 -- too late: re-arms only
    O.collectorClear:click()
    assert.are.equal(0, clears)
    now = 108
    O.collectorClear:click()
    assert.are.equal(1, clears)
    assert.are.equal(0, WFJ.Collector.status().entries)
    O.collectorClear:click() -- armed again, then the window passes: a refresh puts the label back
    now = 200
    O.refresh()
    assert.are.equal(ja("collector.clear"), O.collectorClear.caption:GetText())
  end)

  it("the send section: numbered steps, Send English opens the send window, the file's path", function()
    local opened = {}
    WFJ.CollectorSendWindow = { open = function(all) opened[#opened + 1] = all end }
    assert.are.equal(ja("collector.send"), O.collectorSend.caption:GetText())
    O.collectorSend.scripts.OnClick(O.collectorSend, "LeftButton")
    assert.are.same({ false }, opened)
    local steps = select(2, WFJ.OptionsText.get("collector.steps"))
    for n = 1, 4 do assert.is_truthy(steps:find(n .. ".", 1, true), n) end
    assert.are.equal(WFJ.Collector.path(), O.copyBoxes["collector.path"]:GetText())
    assert.is_nil(O.copyBoxes["collector.issue"])
  end)

  it("the about page has the header, how to open settings, the slash list and the bug or idea button", function()
    local about = O.pages.about
    about:Show()
    -- the shipped quest count
    assert.is_truthy(about.subtitle.en:GetText():find("クエスト " .. shippedQuests(WFJ), 1, true))
    local texts = {}
    for _, fs in ipairs(about.children) do if fs.GetText then texts[#texts + 1] = fs:GetText() end end
    local all = table.concat(texts, "\n")
    assert.is_truthy(all:find(WFJ.OptionsText.T["about.open"].ja, 1, true))
    -- the reveal key by name, and both markers as they show
    assert.is_truthy(all:find("Altを押している間は", 1, true))
    assert.is_truthy(all:find(WFJ.MARKER.stale .. "　翻訳後に", 1, true))
    assert.is_truthy(all:find(WFJ.MARKER.missing .. "　まだ翻訳", 1, true))
    assert.is_truthy(all:find("/wfj config [collector | about]", 1, true))
    assert.is_truthy(all:find("/wfj bug", 1, true))
    assert.is_truthy(all:find(WFJ.OptionsText.T["about.bug"].ja, 1, true))
    -- one way in: the button opens the report window; the bare new-issue link is gone
    assert.is_nil(O.copyBoxes["about.report"])
    local opened = false
    WFJ.ReportWindow = { open = function() opened = true end }
    assert.are.equal(select(2, WFJ.OptionsText.get("button.reportBug")), O.reportBug.caption:GetText())
    O.reportBug.scripts.OnClick(O.reportBug, "LeftButton")
    assert.is_true(opened)
  end)

  it("the about page's voice line: not installed with the Voice entry's address, else the packs that loaded", function()
    local about = O.pages.about
    about:Show()
    -- no pack (Core/Voice not even loaded): the line and the copyable address
    assert.are.equal(WFJ.OptionsText.T["about.voice.none"].ja, O.aboutVoice.en:GetText())
    local box = O.copyBoxes["about.voice"]
    assert.are.equal("https://www.curseforge.com/wow/addons/wow-forever-japanese-voice", box:GetText())
    assert.is_true(box:IsShown())
    box:SetText("edited")
    box.scripts.OnTextChanged(box, true)
    assert.are.equal(O.VOICE_URL, box:GetText()) -- snaps back
    H.loadChunk("Core/Voice.lua", nil, WFJ)
    O.refresh()
    assert.is_true(box:IsShown()) -- Voice loaded, still no pack
    for _, folder in ipairs({ "WoWForeverJapanese_VoiceOther", "WoWForeverJapanese_VoiceLevels11to20",
      "WoWForeverJapanese_VoiceLevels1to10" }) do
      WFJ.Voice.register({ format = 2, folder = folder, lines = {} })
    end
    O.refresh()
    assert.are.equal("日本語音声：レベル1-10、レベル11-20、その他", O.aboutVoice.en:GetText())
    assert.are.equal("Japanese voice: Levels 1-10, Levels 11-20, Other", O.aboutVoice.pair[1])
    assert.is_false(box:IsShown())
    -- no voice setting on the About page: those stay on the voice page
    for _, c in ipairs(O.controls) do assert.is_nil(c.id:match("^voice%."), c.id) end
    assert.are.same({ "Levels 51-60", "レベル51-60", 51 }, { O.voicePackName("WoWForeverJapanese_VoiceLevels51to60") })
    assert.are.same({ "Voice", "音声" }, { O.voicePackName("WoWForeverJapanese_Voice") })
  end)

  it("never takes keyboard input outside a capture: pages built hidden, no OnKeyDown until a capture starts", function()
    -- Capture buttons with a standing OnKeyDown on visible parentless pages swallowed
    -- Escape, so the game menu would not open.
    for id, page in pairs(O.pages) do assert.is_false(page:IsShown(), id) end
    local function listeners()
      local n = 0
      for _, f in ipairs(Stub.frames) do
        if f.scripts.OnKeyDown or f.scripts.OnMouseDown or f.keyboard then n = n + 1 end
      end
      return n
    end
    assert.are.equal(0, listeners())
    local cap = O.captures[1]
    cap.button:click()
    assert.are.equal(1, listeners())
    cap.button:keyDown("ESCAPE")
    assert.are.equal(0, listeners())
    cap.button:click(); cap.button:keyDown("F6")
    assert.are.equal(0, listeners())
  end)

  it("a help row is as tall as its wrapped text (GetStringHeight), never less than its minimum", function()
    local page = CreateFrame("Frame")
    local l = WFJ.OptionsWidgets.label(page, "en", "日本語", 16, -10, 620)
    assert.are.equal(40, WFJ.OptionsWidgets.labelHeight(l, 40)) -- no measurement available: the minimum
    l.en.GetStringHeight = function() return 52 end -- the one shown line, wrapped (one language)
    assert.are.equal(64, WFJ.OptionsWidgets.labelHeight(l, 40)) -- its height + 12
    assert.are.equal(40, WFJ.OptionsWidgets.labelHeight(l, 40) - 24) -- (sanity: 52 + 12)
  end)

  it("uses no legacy InterfaceOptions API and creates no font object", function()
    for _, f in ipairs({ "UI/Options.lua", "UI/OptionsWidgets.lua", "UI/KeyCapture.lua", "UI/AddonListButton.lua" }) do
      local src = H.readFile("addon/WoWForeverJapanese/" .. f)
      assert.is_nil(src:find("InterfaceOptions", 1, true), f)
      local _, n = src:gsub("CreateFont%(", "")
      assert.are.equal(0, n, f)
    end
  end)
end)

describe("Options panel build failure does not take /wfj down", function()
  it("registers the slash command and reports the error in /wfj debug", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    _G.Settings.RegisterCanvasLayoutCategory = function() error("boom: template renamed") end
    Loader.load("WoWForeverJapanese")
    assert.has_no.errors(function() Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese") end)
    assert.is_function(SlashCmdList.WFJ)
    Stub.prints = {}
    SlashCmdList.WFJ("debug")
    local found = false
    for _, line in ipairs(Stub.prints) do
      if line:find("settings panel failed to build", 1, true) and line:find("boom", 1, true) then found = true end
    end
    assert.is_true(found)
    SlashCmdList.WFJ("off")
    assert.is_false(WFJ_DB.settings.enabled)
  end)
end)

describe("Options panel when the Settings API is absent (degrades)", function()
  it("loads without error and /wfj config says so", function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.removeSettingsAPI()
    Loader.load("WoWForeverJapanese")
    assert.has_no.errors(function() Stub.fireAll("ADDON_LOADED", "WoWForeverJapanese") end)
    Stub.prints = {}
    SlashCmdList.WFJ("config")
    assert.are.equal(1, #Stub.prints)
    assert.is_truthy(Stub.prints[1]:find("not available", 1, true))
  end)
end)
