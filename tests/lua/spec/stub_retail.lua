-- Shared harness for the retail_lib window specs (guild invite, pet happiness, instance difficulty, boss banner,
-- cinematic close dialog, streaming icon, loss of control, equipment flyout, player choice, instance abandon): the
-- UI files and one surface on a fresh stub, and the assertions every surface makes, generated once. Frame builders
-- (window / tree / at / tooltip / unrecorded / alt) are the commerce specs' (stub_commerce.lua).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")
local R = setmetatable({}, { __index = C })

-- → WFJ. `opts`: { args = { KEY = { [n] = kind } } → UIStrings.ARGS
-- entries the surface needs (Core/UIStrings carries them; a key already there is kept),
-- before = function() … end → builds client frames before the index is built }.
function R.load(file, ui, opts)
  opts = opts or {}
  Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
  Stub.installTooltipAPI()
  local files = {}
  for i, f in ipairs(H.UI_FILES) do files[i] = f end
  files[#files + 1] = file
  local WFJ = H.loadChunks(files)
  for key, kinds in pairs(opts.args or {}) do
    if WFJ.UIStrings.ARGS[key] == nil then WFJ.UIStrings.ARGS[key] = kinds end
  end
  if opts.before then opts.before() end
  H.uiSetup(WFJ, ui)
  return WFJ
end

function R.teardown(names)
  C.teardown(names)
end

-- The shared assertions. `o` is stub_commerce's C.suite options plus `args` (UIStrings.ARGS the surface needs).
--   title, module, file, addon (nil for a login frame), root, globals, ui, build(), cases, name(frame, WFJ),
--   wrong(frame) → function(frame, WFJ)
function R.suite(env, o)
  local describe, it, before_each, after_each, assert = env.describe, env.it, env.before_each, env.after_each,
    env.assert
  describe(o.title, function()
    local WFJ

    local function load() WFJ = R.load(o.file, o.ui, { args = o.args }) end
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

    after_each(function() R.teardown(o.globals) end)

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
      R.teardown(o.globals)
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

return R
