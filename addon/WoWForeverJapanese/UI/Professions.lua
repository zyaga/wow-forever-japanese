-- UI/Professions.lua: the professions window's overview ("book") page on Forever (surfaces "professions": the window
-- title, and "professions.book": the page's words; area "ui", ADR-016, ADR-029).
-- Entry points on camelot: the Professions micro button and the TOGGLEPROFESSIONBOOK binding call
-- ToggleProfessionsBook() (blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:669;
-- blizzard_framexml/bindings_camelot.xml:1215). camelot does NOT build the standalone ProfessionsBookFrame:
-- Blizzard_ProfessionsBook.xml is [ExcludeLoadGameType camelot] (blizzard_professionsbook.toc), so the toggle falls
-- through to ShowProfessionsFrame() + ProfessionsFrame:SelectBookPage() (blizzard_professionsbook_bootstrap.lua:
-- 7–20): the book is ProfessionsFrame.BookPage, a ProfessionsBookPageTemplate inheriting the camelot
-- ProfessionsBookFrameTemplate (blizzard_professions/camelot/blizzard_professionsframe.xml:79;
-- blizzard_professionscrafting.xml:397; blizzard_professionsbook/camelot/blizzard_professionsbooktemplates.xml:189).
-- Both addons are load-on-demand (Blizzard_Professions depends on Blizzard_ProfessionsBook): each is waited for
-- through WFJ.LoadOnDemand.when, in either load order.
-- Title: ProfessionsMixin:SelectBookPage writes ProfessionsFrame:SetTitleFormatted(TRADE_SKILL_TITLE "%s",
--   TRADE_SKILLS "Professions") (camelot/blizzard_professionsframe.lua:91–99). SetTitleFormatted writes
--   TitleContainer.TitleText directly; it does not go through SetTitle (blizzard_sharedxml/portraitframe.lua:11–17),
--   so it is post-hooked on the frame beside Labels.title's SetTitle hook. The crafting page titles the same
--   frame with the profession's name (SetTitle(professionName), blizzard_professionscrafting.lua:1379–1387;
--   blizzard_professionsframe.lua:246, 278): a name, so the title takes TRADE_SKILLS only. The standalone book
--   (ProfessionsBookFrameStandaloneMixin:OnLoad → SetTitle(TRADE_SKILLS), blizzard_professionsbook.lua:216–228) is
--   handled the same way where a client builds it.
-- Static labels (written once by the XML / its inline OnLoad, only shown and hidden afterwards by
--   ProfessionsBookFrameMixin:FormatProfession, camelot/blizzard_professionsbook.lua:45–143): each primary slot's
--   missingHeader (PROFESSIONS_FIRST_PROFESSION / _SECOND_PROFESSION) and missingText
--   (PROFESSIONS_MISSING_PROFESSION), each secondary slot's missingText (PROFESSIONS_COOKING_MISSING /
--   _FISHING_MISSING / _FIRST_AID_MISSING) (camelot templates xml:26, 32, 197–246). Shown on setup and on the
--   page's OnShow; released on its OnHide.
-- Help tooltips: a slot's UnlearnButton (GameTooltip:SetText(UNLEARN_SKILL_TOOLTIP), camelot/
--   blizzard_professionsbook.lua:3–8) and the overview side tab (tooltipText TRADE_SKILLS, SidePanelTabButtonMixin:
--   OnEnter → SetText; camelot/blizzard_professionsframe.xml:13–17; shareduipaneltemplates.lua:406–420), each
--   restricted to its one key. The profession side tabs' tooltipText is the profession's name (camelot/
--   blizzard_professionsframe.lua:64): never registered.
-- Never touched: a slot's ProfessionName (GetProfessionInfo's name) and specialization, a secondary slot's
--   missingHeader (PROFESSIONS_COOKING / _FISHING / _FIRST_AID are profession names; `only` keeps them English),
--   the rank bar's text (TRADESKILL_NAME_RANK "%s %d/%d" joins the profession name, blizzard_professionsrankbar.lua:
--   6–21). The unlearn confirmation is a StaticPopup (ADR-015 §5).
local _, WFJ = ...
local Professions = {}
WFJ.Professions = Professions

local SURFACE = "professions" -- the window title, and the Compat namespace
local BOOK = SURFACE .. ".book" -- a book page's words (released with the page; the title goes with the window)
Professions.SURFACE, Professions.BOOK = SURFACE, BOOK
local Compat = WFJ.Compat

local FRAME_ADDON, BOOK_ADDON = "Blizzard_Professions", "Blizzard_ProfessionsBook"

-- hosts of a ProfessionsBookFrameTemplate: camelot's page, and the standalone book where a client builds one
local CANDIDATES = {
  frame = { "ProfessionsFrame" }, bookPage = { "ProfessionsFrame.BookPage" },
  overviewTab = { "ProfessionsFrame.ProfessionsOverviewTab" }, standalone = { "ProfessionsBookFrame" },
}
local SLOTS = { "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1", "SecondaryProfession2",
  "SecondaryProfession3" }

Professions.NEVER_TOUCH = {}
for _, host in ipairs({ "ProfessionsFrame.BookPage", "ProfessionsBookFrame" }) do
  for _, slot in ipairs(SLOTS) do
    for _, field in ipairs({ "ProfessionName", "specialization" }) do
      local path = host .. ".ProfessionsContentFrame." .. slot .. "." .. field
      Professions.NEVER_TOUCH[#Professions.NEVER_TOUCH + 1] = path
    end
  end
end

-- A guild's profession view titles the frame SetTitleFormatted(GUILD_TRADE_SKILL_TITLE, skillLineName)
-- (blizzard_professionsframe.lua:246–253): "Guild <profession>", the name kept (`text`, a key-only template)
local TITLE = { only = { "TRADE_SKILLS", "GUILD_TRADE_SKILL_TITLE" } }
local HEADER = { only = { "PROFESSIONS_FIRST_PROFESSION", "PROFESSIONS_SECOND_PROFESSION" } }
local MISSING = { only = { "PROFESSIONS_MISSING_PROFESSION", "PROFESSIONS_COOKING_MISSING",
  "PROFESSIONS_FISHING_MISSING", "PROFESSIONS_FIRST_AID_MISSING" } }
local UNLEARN = { only = { "UNLEARN_SKILL_TOOLTIP" } }
Professions.KEYS = { title = TITLE.only, header = HEADER.only, missing = MISSING.only, unlearn = UNLEARN.only }

local function get(key) return Compat.get(SURFACE, key) end
local function declare()
  for key, names in pairs(CANDIDATES) do Compat.declare(SURFACE, key, names) end
end

-- → the slot frames of one host (only those that are tables)
local function slotsOf(hostKey)
  local host = get(hostKey)
  local content = type(host) == "table" and host.ProfessionsContentFrame or nil
  local out = {}
  if type(content) ~= "table" then return out end
  for _, name in ipairs(SLOTS) do
    if type(content[name]) == "table" then out[#out + 1] = { name = name, frame = content[name] } end
  end
  return out
end

-- The "no profession here" words of every slot of one host. → the number of dictionary words found.
function Professions.showStatic(hostKey)
  local items = {}
  for _, slot in ipairs(slotsOf(hostKey)) do
    local prefix = hostKey .. "." .. slot.name
    items[#items + 1] = { prefix .. ".header", slot.frame.missingHeader, HEADER }
    items[#items + 1] = { prefix .. ".missing", slot.frame.missingText, MISSING }
  end
  return WFJ.Labels.showAll(BOOK, items)
end

-- A window title: after SetTitle (Labels.title's hook), SetTitleFormatted (ours) and the window's OnShow. → 1 | 0
local function showTitle(frameKey, recKey)
  local n = WFJ.Labels.title(SURFACE, get(frameKey), TITLE, recKey)
  WFJ.Render.updateBanner(SURFACE)
  return n
end
function Professions.showFrameTitle() return showTitle("frame", "title") end
function Professions.showStandaloneTitle() return showTitle("standalone", "standalone.title") end

function Professions.onFrameShow()
  Professions.showFrameTitle()
  local page = get("bookPage")
  if type(page) == "table" and type(page.IsShown) == "function" and page:IsShown() then
    Professions.showStatic("bookPage")
  end
end
function Professions.onPageShow() return Professions.showStatic("bookPage") end
function Professions.onStandaloneShow()
  Professions.showStandaloneTitle()
  return Professions.showStatic("standalone")
end

-- The page's OnHide drops its words; the title outlives a page and goes with the window.
function Professions.releasePage() return WFJ.Render.release(BOOK) end
function Professions.release() return WFJ.Render.release(BOOK) + WFJ.Render.release(SURFACE) end

local function registerTooltips(hostKey)
  for _, slot in ipairs(slotsOf(hostKey)) do
    if type(slot.frame.UnlearnButton) == "table" then WFJ.HelpTooltip.register(slot.frame.UnlearnButton, UNLEARN) end
  end
end

local function hookScript(frame, script, fn)
  if type(frame) == "table" and type(frame.HookScript) == "function" then frame:HookScript(script, fn) end
end

local frameHooked, bookHooked = false, false

-- Blizzard_Professions' part: runs once the addon is loaded (now, or on its ADDON_LOADED). → true when set up.
function Professions.setupFrame()
  declare() -- its frames exist only now: forget what Compat memoized before
  local frame = get("frame")
  if frameHooked or type(frame) ~= "table" then return false end
  frameHooked = true
  WFJ.Labels.forbidNames(Professions.NEVER_TOUCH) -- its widgets exist only now (Main's registration found none)
  if type(frame.SetTitleFormatted) == "function" then
    hooksecurefunc(frame, "SetTitleFormatted", Professions.showFrameTitle)
  end
  hookScript(frame, "OnShow", Professions.onFrameShow)
  hookScript(frame, "OnHide", Professions.release)
  local page = get("bookPage")
  hookScript(page, "OnShow", Professions.onPageShow)
  hookScript(page, "OnHide", Professions.releasePage)
  registerTooltips("bookPage")
  local tab = get("overviewTab")
  if type(tab) == "table" then WFJ.HelpTooltip.register(tab, TITLE) end
  Professions.onFrameShow()
  return true
end

-- Blizzard_ProfessionsBook's part: the standalone book, where a client builds it (camelot does not). → true when
-- set up.
function Professions.setupBook()
  declare()
  local book = get("standalone")
  if bookHooked or type(book) ~= "table" then return false end
  bookHooked = true
  WFJ.Labels.forbidNames(Professions.NEVER_TOUCH)
  if type(book.SetTitleFormatted) == "function" then
    hooksecurefunc(book, "SetTitleFormatted", Professions.showStandaloneTitle)
  end
  hookScript(book, "OnShow", Professions.onStandaloneShow)
  hookScript(book, "OnHide", Professions.release)
  registerTooltips("standalone")
  Professions.onStandaloneShow()
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when either
-- addon was already loaded and set up; false while both are waited for.
function Professions.init()
  declare()
  local LOD = WFJ.LoadOnDemand
  if type(LOD) ~= "table" or type(LOD.when) ~= "function" then return false end
  local book = LOD.when(BOOK_ADDON, Professions.setupBook)
  local frame = LOD.when(FRAME_ADDON, Professions.setupFrame)
  return book or frame
end
