-- UI/Professions.lua: the professions window's overview ("book") page on Forever (surfaces "professions": the window
-- title, and "professions.book": the page's words; area "ui", ADR-016, ADR-029).
-- Entry points on camelot: the Professions micro button and the TOGGLEPROFESSIONBOOK binding call
-- ToggleProfessionsBook() (blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:669;
-- blizzard_framexml/bindings_camelot.xml:1211). camelot does NOT build the standalone ProfessionsBookFrame:
-- Blizzard_ProfessionsBook.xml is [ExcludeLoadGameType camelot] (blizzard_professionsbook.toc), so the toggle falls
-- through to ShowProfessionsFrame() + ProfessionsFrame:SelectBookPage() (blizzard_professionsbook_bootstrap.lua:
-- 7–20): the book is ProfessionsFrame.BookPage, a ProfessionsBookPageTemplate inheriting the camelot
-- ProfessionsBookFrameTemplate (blizzard_professions/camelot/blizzard_professionsframe.xml:79;
-- blizzard_professionscrafting.xml:397; blizzard_professionsbook/camelot/blizzard_professionsbooktemplates.xml:221).
-- Both addons are load-on-demand (Blizzard_Professions depends on Blizzard_ProfessionsBook): each is waited for
-- through WFJ.LoadOnDemand.when, in either load order.
-- Title: ProfessionsMixin:SelectBookPage writes ProfessionsFrame:SetTitleFormatted(TRADE_SKILL_TITLE "%s",
--   TRADE_SKILLS "Professions") (camelot/blizzard_professionsframe.lua:110–118). SetTitleFormatted writes
--   TitleContainer.TitleText directly; it does not go through SetTitle (blizzard_sharedxml/portraitframe.lua:11–17),
--   so it is post-hooked on the frame beside Labels.title's SetTitle hook. The crafting page titles the same
--   frame with the profession's name (SetTitle(professionName), blizzard_professionscrafting.lua:1369–1377;
--   blizzard_professionsframe.lua:258–273, 290): a name, so the title takes TRADE_SKILLS only. The standalone book
--   (ProfessionsBookFrameStandaloneMixin:OnLoad → SetTitle(TRADE_SKILLS), blizzard_professionsbook.lua:218–228) is
--   handled the same way where a client builds it.
-- Static labels (written once by the XML / its inline OnLoad, only shown and hidden afterwards by
--   ProfessionsBookFrameMixin:FormatProfession, camelot/blizzard_professionsbook.lua:43–137): each primary slot's
--   missingHeader (PROFESSIONS_FIRST_PROFESSION / _SECOND_PROFESSION) and missingText
--   (PROFESSIONS_MISSING_PROFESSION), each secondary slot's missingText (PROFESSIONS_COOKING_MISSING /
--   _FISHING_MISSING / _FIRST_AID_MISSING) (camelot templates xml:26, 32, 227–276). Shown on setup and on the
--   page's OnShow; released on its OnHide.
-- Help tooltips: a slot's UnlearnButton (GameTooltip:SetText(UNLEARN_SKILL_TOOLTIP), camelot/
--   blizzard_professionsbook.lua:3–8) and the overview side tab (tooltipText TRADE_SKILLS, SidePanelTabButtonMixin:
--   OnEnter → SetText; camelot/blizzard_professionsframe.xml:13–17; shareduipaneltemplates.lua:408–422), each
--   restricted to its one key. The profession side tabs' tooltipText is the profession's name (camelot/
--   blizzard_professionsframe.lua:50): registered with no key and a name line, so it shows the name's Japanese
--   while names are on.
-- Names, while Japanese names are on (UI/NameLabels): a slot's ProfessionName (GetProfessionInfo's name, written by
--   FormatProfession from the page's Update, camelot/blizzard_professionsbook.lua:22–28, 75), after each Update
--   (post-hooked on the page, which OnShow and the skill events call by method, blizzard_professionsbook.lua:23–33),
--   on surface "professions.book"; and the crafting page's title, SetTitle(professionName), under the title's own
--   record. Nothing reads or measures ProfessionName.
-- The rank bars' text, TRADESKILL_NAME_RANK "%s %d/%d" (ProfessionsRankBarMixin:Update writes Rank.Text, a plain
--   label nothing measures, blizzard_professionsrankbar.lua:6–21, 141–143): the name in Japanese and the numbers as
--   written (NameLabels.lead). A slot's StatusBar is updated by FormatProfession (camelot/
--   blizzard_professionsbook.lua:38), so it is shown with the slot's name; the crafting page's RankBar after each of
--   its own Update calls (blizzard_professionscrafting.lua:1038–1039), on the window's surface. Forever's frame has
--   no orders page (camelot/blizzard_professionsframe.xml:68–79). A trial's cap note after the numbers is words:
--   that line stays English whole.
-- A secondary slot's missingHeader is the profession's name (PROFESSIONS_COOKING / _FISHING / _FIRST_AID, written
--   once by the slot's inline OnLoad, camelot templates xml:137, 251, 263, 275, then only shown and hidden,
--   blizzard_professionsbook.lua:52, 118): no dictionary word (`only` keeps it out of the header's keys). While
--   names are on it shows the name's Japanese, under a record of its own, with the page's other words. It is a
--   plain label on the slot's frame like the missingText under it; nothing reads or measures it.
-- Never written: a slot's specialization, and the spell buttons' spellString and subSpellString (the spell's name
--   and its rank word, "Journeyman"): each button is secure and its click casts (ProfessionButtonTemplate inherits
--   SecureFrameTemplate, blizzard_professionsbooktemplates.xml:4, 26–37; OnClick → C_SpellBook.CastSpellBookItem,
--   blizzard_professionsbook.lua:317–352), and the client writes both in UpdateButton (:491–497). Their Japanese is
--   drawn over them instead (the spell buttons' section below). The unlearn confirmation is a StaticPopup
--   (ADR-015 §5).
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
  rankBar = { "ProfessionsFrame.CraftingPage.RankBar" },
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
-- (blizzard_professionsframe.lua:264–265): "Guild <profession>", the name kept (`text`, a key-only template)
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
  local n = WFJ.Labels.showAll(BOOK, items)
  -- an unlearned secondary slot's header is the profession's name
  for _, slot in ipairs(slotsOf(hostKey)) do
    n = n + WFJ.NameLabels.show(BOOK, hostKey .. "." .. slot.name .. ".headerName", slot.frame.missingHeader)
  end
  return n
end

-- A window title: after SetTitle (Labels.title's hook), SetTitleFormatted (ours) and the window's OnShow. → 1 | 0
local function showTitle(frameKey, recKey)
  local n = WFJ.Labels.title(SURFACE, get(frameKey), TITLE, recKey)
  WFJ.Render.updateBanner(SURFACE)
  return n
end
function Professions.showFrameTitle() return showTitle("frame", "title") end
function Professions.showStandaloneTitle() return showTitle("standalone", "standalone.title") end

-- A rank bar's text: the name, then the numbers as the client wrote them. → 1 | 0
local function showRank(surface, recKey, bar)
  local rank = type(bar) == "table" and bar.Rank or nil
  return WFJ.NameLabels.lead(surface, recKey, type(rank) == "table" and rank.Text or nil)
end

-- Each slot's profession name and its rank bar, after the page's Update. → the number of names shown
local function showNames(hostKey)
  local n = 0
  for _, slot in ipairs(slotsOf(hostKey)) do
    local prefix = hostKey .. "." .. slot.name
    n = n + WFJ.NameLabels.show(BOOK, prefix .. ".name", slot.frame.ProfessionName)
    n = n + showRank(BOOK, prefix .. ".rank", slot.frame.StatusBar)
  end
  return n
end

-- The crafting page's rank bar, after its Update. → 1 | 0
function Professions.onRankUpdate() return showRank(SURFACE, "crafting.rank", get("rankBar")) end
function Professions.onPageUpdate() return showNames("bookPage") end
function Professions.onStandaloneUpdate() return showNames("standalone") end

local function hookUpdate(host, fn)
  if type(host) == "table" and type(host.Update) == "function" then hooksecurefunc(host, "Update", fn) end
end

function Professions.onFrameShow()
  Professions.showFrameTitle()
  local page = get("bookPage")
  if type(page) == "table" and type(page.IsShown) == "function" and page:IsShown() then
    Professions.showStatic("bookPage")
    showNames("bookPage")
  end
end
function Professions.onPageShow() return Professions.showStatic("bookPage") end
function Professions.onStandaloneShow()
  Professions.showStandaloneTitle()
  showNames("standalone")
  return Professions.showStatic("standalone")
end

-- The page's OnHide drops its words; the title outlives a page and goes with the window.
function Professions.releasePage() return WFJ.Render.release(BOOK) end
function Professions.release() return WFJ.Render.release(BOOK) + WFJ.Render.release(SURFACE) end

-- a profession side tab's tooltip is the profession's name alone (tooltipText = GetProfessionInfo's name,
-- camelot/blizzard_professionsframe.lua:42-50; SidePanelTabButtonMixin:OnEnter, shareduipaneltemplates.lua:408-418)
local TAB_NAME = { only = {}, nameLine = "ui" }

local function registerTooltips(hostKey)
  for _, slot in ipairs(slotsOf(hostKey)) do
    if type(slot.frame.UnlearnButton) == "table" then WFJ.HelpTooltip.register(slot.frame.UnlearnButton, UNLEARN) end
  end
end

-- ───────────────────────── the spell buttons' words, drawn over them ─────────────────────────
-- A slot's SpellButton1 and SpellButton2 are secure and their click casts, so the addon writes nothing into them.
-- The client writes their spellString (the spell's name) and subSpellString (its rank word, GetSpellSubtext:
-- "Journeyman", on Forever "Apprentice " with a space after it) in ProfessionSpellButtonMixin:UpdateButton, and
-- sets the name's colour there; nothing of the client reads, measures or fades either text
-- [verified: blizzard_professionsbook.lua:458-497]. So, as UI/SpellBookNames does for the spellbook (ADR-058),
-- the Japanese is this addon's own FontString on this addon's own frame (a child of the page, shown and hidden
-- with it) placed over the client's text, and the client's text keeps everything but its alpha, set to 0 and put
-- back when the label goes. A region's SetAlpha is not protected; in combat a text not covered yet is left as it is.
-- The rank word is a dictionary word and shows whenever the page is Japanese; the spell's name needs names on.
local BUTTONS = { "Spell" .. "Button1", "Spell" .. "Button2" } -- a slot's keys, never the old spellbook's globals
local overlay -- this addon's frame over the page
local covers = setmetatable({}, { __mode = "k" }) -- the client's FontString → { label, alpha, hidden, ... }

local function inCombat()
  local f = Compat.resolve("InCombatLockdown")
  return type(f) == "function" and f() and true or false
end

local function rankJa(en)
  local index, words = WFJ.UIIndex, WFJ.SpellBookNames and WFJ.SpellBookNames.WORD_KEYS
  if not index or not words then return nil end
  local key, args = index:matchOnly(en:match("^%s*(.-)%s*$"),
    WFJ.Labels.familiesWith(words.subtext, "SpellSubtext").only)
  local row = key and index.rows[key]
  return row and index:fill(row[1], args) or nil
end
local function spellJa(en)
  if not WFJ.State.names then return nil end
  return (WFJ.Names.item(en))
end

-- The client's text visible again, as the client left it.
local function uncover(fs, e)
  if e.label then e.label:Hide() end
  if not e.hidden then return end
  if fs:GetAlpha() ~= 0 then -- written by the client since: its own value stays
    e.hidden = false
    return
  end
  if inCombat() then return end
  fs:SetAlpha(e.alpha)
  e.hidden = false
end

-- One text of a button: its Japanese label over it, or the client's text shown. → 1 when the label shows
local function cover(fs, find, on)
  if type(fs) ~= "table" or type(fs.GetText) ~= "function" or type(fs.GetAlpha) ~= "function" then return 0 end
  local e = covers[fs]
  if not e then
    e = { alpha = 1, hidden = false }
    covers[fs] = e
  end
  local en = fs:GetText()
  local ja
  if on and type(en) == "string" and en ~= "" and not WFJ.SurfaceState.secret(en) and fs:IsShown() then
    local names = WFJ.State.names and true or false
    if e.src ~= en or e.names ~= names then e.src, e.names, e.ja = en, names, find(en) or false end
    ja = e.ja or nil
  end
  if not ja or (not e.hidden and inCombat()) then
    uncover(fs, e)
    return 0
  end
  local label = e.label
  if not label then
    label = overlay:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOPLEFT", fs, "TOPLEFT", 0, 0)
    label:SetPoint("TOPRIGHT", fs, "TOPRIGHT", 0, 0)
    label:SetWordWrap(true)
    label:SetFont(WFJ.Font.CLIENT, WFJ.Font.DEFAULT_SIZE, "") -- a face the client has: the bundled one may not be yet
    e.label = label
  end
  if e.shown ~= ja then
    local _, size, flags = fs:GetFont()
    if WFJ.Font.set(label, WFJ.Font.PATH, WFJ.Font.size(size) or WFJ.Font.DEFAULT_SIZE, flags or "") == false then
      uncover(fs, e)
      return 0
    end
    label:SetJustifyH(fs:GetJustifyH() or "LEFT")
    label:SetShadowColor(fs:GetShadowColor())
    label:SetShadowOffset(fs:GetShadowOffset())
    label:SetText(ja)
    e.shown = ja
  end
  label:SetTextColor(fs:GetTextColor()) -- a passive spell's colour follows the client at every look
  label:Show()
  if not e.hidden then
    local alpha = fs:GetAlpha()
    if alpha ~= 0 then e.alpha = alpha end
    fs:SetAlpha(0)
    e.hidden = true
  end
  return 1
end

-- One pass over the page's buttons, once a frame while the page shows. → the number of labels showing
function Professions.coverButtons()
  if not overlay then return 0 end
  local State = WFJ.State
  local on = State.enabled and State.areaEnabled("ui") and not WFJ.Modifier.english()
  local n = 0
  for _, slot in ipairs(slotsOf("bookPage")) do
    for _, b in ipairs(BUTTONS) do
      local button = slot.frame[b]
      if type(button) == "table" then
        local shown = on and type(button.IsVisible) == "function" and button:IsVisible()
        n = n + cover(button.spellString, spellJa, shown) + cover(button.subSpellString, rankJa, shown)
      end
    end
  end
  return n
end

-- Every covered text shown again (the page hid). → nothing
function Professions.uncoverAll()
  for fs, e in pairs(covers) do uncover(fs, e) end
end

local function setupOverlay(page)
  local create = Compat.resolve("CreateFrame")
  if overlay or type(page) ~= "table" or type(create) ~= "function" then return end
  -- a child of the page runs no OnUpdate while the page is hidden
  local made = create("Frame", nil, page)
  if type(made) ~= "table" or type(made.SetScript) ~= "function" or type(made.CreateFontString) ~= "function" then
    return
  end
  overlay = made
  if type(overlay.SetAllPoints) == "function" then overlay:SetAllPoints(page) end
  if type(page.GetFrameLevel) == "function" and type(overlay.SetFrameLevel) == "function" then
    overlay:SetFrameLevel(page:GetFrameLevel() + 10)
  end
  overlay:SetScript("OnUpdate", WFJ.Perf.wrap("idle.professionbuttons", Professions.coverButtons))
  overlay:SetScript("OnHide", Professions.uncoverAll)
  Professions.overlay = overlay
end
-- ──────────────────────────────────── end of the spell buttons ────────────────────────────────────

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
  hookUpdate(page, Professions.onPageUpdate)
  hookUpdate(get("rankBar"), Professions.onRankUpdate)
  registerTooltips("bookPage")
  setupOverlay(page)
  local tab = get("overviewTab")
  if type(tab) == "table" then WFJ.HelpTooltip.register(tab, TITLE) end
  for _, side in ipairs(type(frame.rightProfessionTabs) == "table" and frame.rightProfessionTabs or {}) do
    WFJ.HelpTooltip.register(side, TAB_NAME)
  end
  Professions.onFrameShow()
  -- the crafting page's title, the profession's name: after Labels.title's own SetTitle hook (set up just above), so
  -- a dictionary title keeps its record
  WFJ.NameLabels.title(SURFACE, frame, "title", false)
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
  hookUpdate(book, Professions.onStandaloneUpdate)
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
