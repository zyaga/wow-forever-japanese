-- Loads the addon exactly as the client does: TOC order, one chunk per file, vararg = (ADDON, WFJ).
local H = require("tests.lua.spec.helpers")
local Loader = {}

function Loader.tocFiles(tocPath)
  local files = {}
  local f = assert(io.open(tocPath))
  for line in f:lines() do
    local l = line:gsub("^\239\187\191", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if l ~= "" and not l:match("^##") and not l:match("^#") then
      files[#files + 1] = (l:gsub("\\", "/"))
    end
  end
  f:close()
  return files
end

function Loader.load(addonName)
  addonName = addonName or "WoWForeverJapanese"
  local WFJ = {}
  local toc = H.ADDON_DIR .. "/" .. addonName .. ".toc"
  for _, rel in ipairs(Loader.tocFiles(toc)) do
    H.loadChunk(rel, addonName, WFJ)
  end
  return WFJ, toc
end

return Loader
