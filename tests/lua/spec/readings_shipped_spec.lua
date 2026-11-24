-- The word-reading box's crash guard over every shipped reading line (ADR-036). It walks the whole data set, so
-- it is a file of its own: under coverage it runs without the line hook (tests/lua/whole-data-specs.txt).
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")

local function isBoundary(text, i)
  if i == #text + 1 then return true end
  local c = text:byte(i)
  return c ~= nil and (c < 0x80 or c >= 0xC0)
end

-- A FontString whose span call behaves like the client's: a split character or an escape sequence is fatal (the
-- client exits; here: error), anything else returns one area per call.
local function spanFontString(text)
  local fs = Stub.fontString(text, "F.ttf", 14, "")
  function fs:CalculateScreenAreaFromCharacterSpan(a, b)
    local t = self.text
    if t:find("|", 1, true) then error("CRASH: escape sequence") end
    if not isBoundary(t, a) or not isBoundary(t, b) or b <= a then error(("CRASH: span %d..%d"):format(a, b)) end
    return { { left = a, bottom = 0, width = b - a, height = 14 } }
  end
  return fs
end

describe("the shipped sample through the crash guard", function()
  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    _G.UIParent = CreateFrame("Frame", "UIParent")
  end)

  after_each(function() _G.UIParent = nil end)

  it("every generated reading row finds all its words in its line on screen, and no span is refused", function()
    local Loader = require("tests.lua.spec.loader")
    local ns = H.loadChunks({ "Core/Const.lua", "Core/Compat.lua", "Core/Data.lua", "Core/Lookup.lua",
      "Core/Readings.lua", "Core/State.lua", "UI/Font.lua", "UI/Readings.lua" })
    local rows = 0
    for _, f in ipairs(Loader.tocFiles(H.ADDON_DIR .. "/WoWForeverJapanese.toc")) do
      local wanted = f:find("^Data/Reading/") or f:find("^Data/Quest/") or f:find("^Data/Gossip/")
        or f:find("^Data/UI/") or f == "Data/Meta.lua" -- UI rows
        or f:find("^Data/Book/") -- book pages, keyed by their English hash
        or f:find("^Data/Item/") or f:find("^Data/Spell/") -- tooltip text, shown with its words on a frozen copy
      if wanted then H.loadChunk(f, nil, ns) end
    end
    local fs = spanFontString("")
    for key, fields in pairs(ns.Data.reading) do
      local type_, id = key:match("^(%a+):(.+)$")
      local tooltip = type_ == "item" or type_ == "spell"
      if type_ == "quest" or tooltip then id = tonumber(id) end
      for field in pairs(fields) do
        local kind = (type_ == "gossip" or type_ == "ui" or type_ == "book") and type_
          or tooltip and (type_ .. "." .. field) or ("quest." .. field)
        local row
        if type_ == "book" then
          row = ns.Lookup.keyed("book", id)
        elseif type_ == "ui" then -- the UI dictionary row { ja, h1, status }; Lookup has no ui slot map
          local r = ns.Data.ui and ns.Data.ui[id]
          row = r and { ja = r[1] } or nil
        else
          row = ns.Lookup.get(kind, id)
        end
        assert.is_table(row, key .. " " .. field)
        -- a tooltip line kept as variants or sections: its words are read over all of them, in order
        local ja = row.ja
        if not ja then
          local parts = {}
          for _, v in ipairs(row.variants or row.sections or {}) do
            parts[#parts + 1] = type(v) == "table" and (v.ja or v[1]) or v
          end
          ja = table.concat(parts, "\n")
        end
        -- the line as a player sees it: the addon's tokens filled in
        local text = ja:gsub("{name}", "Reyn"):gsub("{class}", "ドルイド"):gsub("{race}", "ナイトエルフ")
        -- a line holding colour codes or a line break escape takes its cards on a frozen tooltip's copy, which
        -- measures it without them (UI/TooltipFreeze)
        -- (a colour the client fills in, "|c%s", is a code too)
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|c%%s", ""):gsub("|r", ""):gsub("|n", "\n")
        fs.text = text
        local words = ns.Readings.words(kind, id)
        local spans = ns.Readings.locate(words, text)
        if row.ja then
          assert.are.equal(#words / 3, #spans, key .. " " .. field) -- word, reading, meaning number
        else -- the game shows one variant, so only its words are found; none may be found twice
          assert.is_true(#spans <= #words / 3, key .. " " .. field)
        end
        for _, sp in ipairs(spans) do
          local RV = ns.ReadingView
          assert.is_table((RV.spanAreas(fs, text, sp.first, sp.last)),
            key .. " " .. field .. " " .. text:sub(sp.first, sp.last))
        end
        rows = rows + 1
      end
    end
    -- every shipped reading line, the whole corpus
    assert.are.equal(ns.Data.meta.counts.reading, rows)
    assert.is_true(rows > 27000)
    assert.are.equal(0, ns.ReadingView.refused)
  end)
end)
