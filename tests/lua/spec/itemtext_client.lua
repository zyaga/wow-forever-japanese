-- The book / letter / plaque window as the Forever client builds it, replaying the writes of
-- blizzard_uipanels_game/mainline/itemtextframe.lua (ITEM_TEXT_FONTS :18–31, ItemTextFrameMixin:OnLoad :3–10,
-- ItemTextFrameMixin:OnEvent :33–175) over itemtextframe.xml (ItemTextPageText, a SimpleHTML :71–77; OnEvent bound by
-- method= :165) [verified: forever 1.60.1.69913]. The stub SimpleHTML keeps a font object or a font per text type
-- (P, H1, H2, H3) and a colour per text type; SetFont and SetFontObject both reset that type's colour (the worst case
-- the adapter must survive; the real client's behaviour is a checklist item).
local M = {}

local TAGS = { "P", "H1", "H2", "H3" }
M.TAGS = TAGS
M.CLIENT_FONT = { path = "Fonts\\FRIZQT__.TTF", size = 13, flags = "", color = { 0.18, 0.12, 0.06, 1 } }
M.PARCHMENT = { 0.18, 0.12, 0.06 } -- GetMaterialTextColors(material) text colour (stub value)
M.TITLE = { 0.5, 0.3, 0.1 } -- GetMaterialTextColors(material) title colour (stub value)

function M.simpleHTML(Stub, name)
  local html = { name = name, text = "", tags = {}, writes = {},
    calls = { SetText = 0, SetFont = 0, SetFontObject = 0 } }
  for _, tag in ipairs(TAGS) do
    html.tags[tag] = { object = nil, font = { path = "Fonts\\FRIZQT__.TTF", size = 12, flags = "" },
      color = { 1, 1, 1, 1 } }
  end
  function html:SetText(t)
    self.calls.SetText = self.calls.SetText + 1
    self.text = t
    self.writes[#self.writes + 1] = t
  end
  function html:GetFont(tag)
    local t = self.tags[tag]
    local f = (t.object and not t.override) and t.object or t.font
    return f.path, f.size, f.flags
  end
  function html:SetFont(tag, path, size, flags)
    self.calls.SetFont = self.calls.SetFont + 1
    if Stub.fontSetFails then return end -- SimpleHTML SetFont returns nothing; a refusal leaves the font as it was
    local t = self.tags[tag]
    t.font, t.color = { path = path, size = size, flags = flags }, { 1, 1, 1, 1 }
    t.override = true
    if not M.stickyObjects then t.object = nil end
  end
  function html:GetFontObject(tag) return self.tags[tag].object end
  -- M.stickyObjects: the engine keeps the assigned object under an explicit SetFont and ignores re-assigning it (the
  -- restore worst case)
  function html:SetFontObject(tag, obj)
    self.calls.SetFontObject = self.calls.SetFontObject + 1
    local t = self.tags[tag]
    if M.stickyObjects and t.object == obj then return end
    t.object, t.override, t.color = obj, false, { obj.color[1], obj.color[2], obj.color[3], obj.color[4] }
  end
  function html:GetTextColor(tag)
    local c = self.tags[tag].color
    return c[1], c[2], c[3], c[4]
  end
  function html:SetTextColor(tag, r, g, b, a) self.tags[tag].color = { r, g, b, a or 1 } end
  _G[name] = html
  return html
end

local function fontObject(path, size)
  return { path = path, size = size, flags = "", color = { 0, 0, 0, 1 } }
end

-- Stub.itemText = { title, pages = { text, … }, page, creator, range, material }: the item the client is showing.
function M.install(Stub)
  Stub.itemText = { title = "", pages = {}, page = 1, creator = nil, range = 0, material = nil }
  local it = Stub.itemText
  _G.QuestFont = { path = M.CLIENT_FONT.path, size = M.CLIENT_FONT.size, flags = M.CLIENT_FONT.flags,
    color = M.CLIENT_FONT.color }
  _G.Fancy48Font = fontObject("Fonts\\MORPHEUS.TTF", 48)
  _G.Game20Font = fontObject("Fonts\\FRIZQT__.TTF", 20)
  _G.Fancy32Font = fontObject("Fonts\\MORPHEUS.TTF", 32)
  -- ITEM_TEXT_FONTS (lua:18–31)
  local FONTS = {
    ParchmentLarge = { P = _G.QuestFont, H1 = _G.Fancy48Font, H2 = _G.Game20Font, H3 = _G.Fancy32Font },
    default = { P = _G.QuestFont, H1 = _G.QuestFont, H2 = _G.QuestFont, H3 = _G.QuestFont },
  }
  M.FONTS = FONTS
  _G.ITEM_TEXT_FROM = "From"
  _G.ItemTextGetText = function() return it.pages[it.page] end
  _G.ItemTextGetCreator = function() return it.creator end
  _G.ItemTextGetItem = function() return it.title end
  _G.ItemTextGetMaterial = function() return it.material end
  _G.ItemTextGetPage = function() return it.page end
  _G.ItemTextHasNextPage = function() return it.page < #it.pages end
  local function colors() return M.PARCHMENT, M.TITLE end -- GetMaterialTextColors; UseLightText() = false

  local frame = CreateFrame("Frame", "ItemTextFrame")
  local current = Stub.namedFontString("ItemTextCurrentPage", "")
  local scroll = CreateFrame("ScrollFrame", "ItemTextScrollFrame", frame)
  local child = CreateFrame("Frame", "ItemTextPageScrollChild", scroll)
  child.heights = {}
  function child:SetHeight(h) self.height = h; self.heights[#self.heights + 1] = h end
  function scroll.GetScrollChild() return child end
  function scroll.GetHeight() return 355 end
  function scroll.GetVerticalScrollRange() return it.range end
  local html = M.simpleHTML(Stub, "ItemTextPageText")
  -- the SimpleHTML sits in the scroll child at the default material's place and width (xml:66–77, lua:111–115)
  function html.GetParent() return child end
  function html.GetWidth() return 270 end
  function html.GetPoint() return "TOPLEFT", child, "TOPLEFT", 18, -15 end
  -- a FontString the addon makes on the scroll child reports its wrapped height
  local createFontString = child.CreateFontString
  function child:CreateFontString(...)
    local fs = createFontString(self, ...)
    function fs.GetStringHeight(f) return f:GetHeight() end
    return fs
  end

  -- ItemTextFrameMixin:OnLoad (lua:3–10)
  for _, e in ipairs({ "ITEM_TEXT_BEGIN", "ITEM_TEXT_TRANSLATION", "ITEM_TEXT_READY", "ITEM_TEXT_CLOSED" }) do
    frame:RegisterEvent(e)
  end
  -- ItemTextFrameMixin:OnEvent (lua:33–175), bound in XML by method= (xml:165)
  local function onEvent(self, event)
    if event == "ITEM_TEXT_BEGIN" then
      self.title = _G.ItemTextGetItem() -- self:SetTitle (lua:35)
      local material = _G.ItemTextGetMaterial() or "Parchment"
      local fontTable = FONTS[material] or FONTS.default
      for _, tag in ipairs(TAGS) do html:SetFontObject(tag, fontTable[tag]) end
      local text, title = colors()
      for _, tag in ipairs(TAGS) do
        local c = (material == "ParchmentLarge" and tag ~= "P") and title or text
        html:SetTextColor(tag, c[1], c[2], c[3])
      end
    elseif event == "ITEM_TEXT_READY" then
      local creator = _G.ItemTextGetCreator()
      if creator then
        creator = "\n\n" .. _G.ITEM_TEXT_FROM .. "\n" .. creator .. "\n"
        html:SetText(_G.ItemTextGetText() .. creator)
      else
        html:SetText(_G.ItemTextGetText())
      end
      child:SetHeight(1)
      scroll:UpdateScrollChildRect()
      if math.floor(scroll:GetVerticalScrollRange()) > 0 then
        child:SetHeight(scroll:GetHeight() + scroll:GetVerticalScrollRange() + 30)
      end
      local page = _G.ItemTextGetPage()
      if page > 1 or _G.ItemTextHasNextPage() then current.text = tostring(page) end -- HandlePagingDisplay
      if not self:IsShown() then self:Show() end -- ShowUIPanel
    elseif event == "ITEM_TEXT_CLOSED" then
      self:Hide() -- HideUIPanel
    end
  end
  frame:SetScript("OnEvent", onEvent)

  -- Opens an item: pages = { English, … } (1-based), creator = a player's name for a letter, material = the
  -- ItemTextGetMaterial() answer (nil → "Parchment").
  function Stub.openItemText(pages, creator, material)
    it.pages, it.page, it.creator, it.material = pages, 1, creator, material
    frame:fire("ITEM_TEXT_BEGIN")
    frame:fire("ITEM_TEXT_READY")
  end
  function Stub.itemTextPage(n) -- ItemTextNextPage / ItemTextPrevPage → ITEM_TEXT_READY
    it.page = n
    frame:fire("ITEM_TEXT_READY")
  end
  function Stub.closeItemText() frame:fire("ITEM_TEXT_CLOSED") end
  return frame, html
end

return M
