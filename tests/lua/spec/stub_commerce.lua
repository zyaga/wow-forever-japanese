-- Shared builders for the NPC / commerce window specs (auction house, guild bank, guild control, currency,
-- transmog, item windows): camelot-shaped frames are parentKey trees, so a spec describes one as dotted paths.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local C = {}

-- A fresh addon namespace over `files` (appended to H.UI_FILES) with the `ui` dictionary. → WFJ
function C.fresh(files, ui)
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  Stub.installTooltipAPI()
  local list = {}
  for i, f in ipairs(H.UI_FILES) do list[i] = f end
  for _, f in ipairs(files) do list[#list + 1] = f end
  local WFJ = H.loadChunks(list)
  H.uiSetup(WFJ, ui)
  return WFJ
end

-- A PortraitFrame / ButtonFrame window: TitleContainer.TitleText written by SetTitle (portraitframe.lua:11–13).
function C.window(name)
  local frame = CreateFrame("Frame", name)
  frame.TitleContainer = CreateFrame("Frame")
  frame.TitleContainer.TitleText = Stub.fontString("")
  function frame.SetTitle(self, text)
    local container = self.TitleContainer
    local fs = type(container) == "table" and container.TitleText or nil
    if type(fs) == "table" then fs.text = text end -- a spec may bind the title to a wrong type
  end
  return frame
end

-- Walks / creates the frames of a dotted path under `root`. → the parent table and the last field name
local function parentOf(root, path)
  local node, last = root, nil
  for field in path:gmatch("[^.]+") do
    if last then
      if type(node[last]) ~= "table" then node[last] = CreateFrame("Frame") end
      node = node[last]
    end
    last = field
  end
  return node, last
end

-- Adds widgets to `root`: spec = { ["A.B.Label"] = "text" (a FontString) | { button = "text" } | { frame = true } }.
function C.tree(root, spec)
  for path, value in pairs(spec) do
    local parent, field = parentOf(root, path)
    if type(value) == "string" then
      parent[field] = Stub.fontString(value)
    elseif value.button ~= nil then
      parent[field] = Stub.button(nil, value.button)
    elseif type(parent[field]) ~= "table" then
      parent[field] = CreateFrame("Frame")
    end
  end
  return root
end

-- → the widget at a dotted path under `root` (nil when a step is missing).
function C.at(root, path)
  local node = root
  for field in path:gmatch("[^.]+") do node = type(node) == "table" and node[field] or nil end
  return node
end

-- A CreateFramePool-like pool: Acquire / ReleaseAll / EnumerateActive over frames made by `make`.
function C.pool(make)
  local p = { active = {}, inactive = {} }
  function p.Acquire(self)
    local frame = table.remove(self.inactive) or make()
    self.active[#self.active + 1] = frame
    return frame
  end
  function p.ReleaseAll(self)
    for _, f in ipairs(self.active) do self.inactive[#self.inactive + 1] = f end
    self.active = {}
  end
  function p.EnumerateActive(self)
    local i = 0
    return function()
      i = i + 1
      if self.active[i] then return self.active[i], true end
    end
  end
  return p
end

-- True when no surface holds a record on `widget`.
function C.unrecorded(WFJ, widget)
  for _, bucket in pairs(WFJ.SurfaceState.surfaces()) do
    for _, rec in pairs(bucket) do
      if rec.fs == widget then return false end
    end
  end
  return true
end

function C.alt(WFJ, down)
  Stub.keys.alt = down
  WFJ.Modifier.refresh()
end

-- The client building a Lua tooltip owned by `owner` (GameTooltip:SetOwner / SetText / AddLine / Show).
function C.tooltip(owner, lines)
  local tt = _G.GameTooltip
  tt:SetOwner(owner, "ANCHOR_RIGHT")
  for i, line in ipairs(lines) do
    if i == 1 then tt:SetText(line) else tt:AddLine(line) end
  end
  tt:Show()
  return tt
end

-- The assertions every window spec makes, generated once. `env` is the spec's busted environment
-- ({ describe, it, before_each, after_each, assert }); `o`:
--   title    the describe title            module  the WFJ field ("GuildBank")     file  "UI/GuildBank.lua"
--   addon    the load-on-demand Blizzard addon, or nil for one the client loads at login
--   root     the window's global name      globals every global `build` creates     ui    the test dictionary
--   build()  creates the camelot-shaped frames → the window
--   cases    { { "it title", function(frame, WFJ) … end }, … } run in every load order
--   name     function(frame, WFJ): asserts a name is left untouched
--   wrong    function(frame): binds client names to wrong types; → function(frame, WFJ) asserting what still works
function C.suite(env, o)
  local describe, it, before_each, after_each, assert = env.describe, env.it, env.before_each, env.after_each,
    env.assert
  describe(o.title, function()
    local WFJ

    local function load() WFJ = C.fresh({ o.file }, o.ui) end
    local function module() return WFJ[o.module] end
    local function build()
      local frame = o.build()
      if o.addon then Stub.loadedAddons[o.addon] = true end
      WFJ.Labels.forbidNames(module().NEVER_TOUCH)
      return frame
    end

    local function setup(loadedFirst)
      load()
      if loadedFirst or not o.addon then
        build()
        assert.is_true(module().init())
      else
        assert.is_false(module().init()) -- waits for the addon
        build()
        assert.are.equal(1, WFJ.LoadOnDemand.loaded(o.addon))
      end
    end

    after_each(function() C.teardown(o.globals) end)

    local orders = o.addon and { { true, o.addon .. " loaded before the addon" }, { false, o.addon .. " on demand" } }
      or { { true, "loaded at login" } }
    for _, order in ipairs(orders) do
      describe(order[2], function()
        before_each(function() setup(order[1]) end)
        for _, case in ipairs(o.cases) do
          it(case[1], function() case[2](_G[o.root], WFJ) end)
        end
        it("hooks install once", function()
          assert.is_false(module().init())
          if module().setup then assert.is_false(module().setup()) end
        end)
      end)
    end

    it("a name is left untouched", function()
      setup(true)
      o.name(_G[o.root], WFJ)
    end)

    it("client names bound to the wrong type degrade to English with no error", function()
      load()
      local frame = build()
      local after = o.wrong(frame)
      assert.has_no.errors(function()
        assert.is_true(module().init())
        if frame.Show then frame:Show() end
      end)
      after(frame, WFJ)
      load()
      _G[o.root] = 42
      if o.addon then Stub.loadedAddons[o.addon] = true end
      assert.has_no.errors(function() assert.is_false(module().init()) end)
    end)

    it("no such window: init is false and nothing is set up", function()
      load()
      assert.has_no.errors(function() assert.is_false(module().init()) end)
    end)
  end)
end

-- The Core/UIStrings ARGS kinds a template needs (`args`: { KEY = { [n] = "text" | "time" … } }), added when the core
-- does not declare them yet, and the dictionary index rebuilt from `ui` so they take effect (the index compiles its
-- patterns once). A no-op for a key the core already declares. Core/UIStrings carries these entries.
function C.args(WFJ, ui, args)
  local missing = false
  for key, kinds in pairs(args) do
    if WFJ.UIStrings.ARGS[key] == nil then WFJ.UIStrings.ARGS[key], missing = kinds, true end
  end
  if not missing then return end
  local function h1(text) return (WFJ.Hash.h32x2(WFJ.Normalize.v1(text))) end
  local rows = {}
  for key, pair in pairs(ui) do rows[key] = { pair[2], h1(pair[1]), "." } end
  WFJ.UIIndex = WFJ.UIStrings.build({ rows = rows, hash = h1, english = function(key) return _G[key] end })
end

function C.teardown(names)
  H.uiTeardown()
  Stub.keys.alt = false
  for _, name in ipairs(names) do _G[name] = nil end
end

return C
