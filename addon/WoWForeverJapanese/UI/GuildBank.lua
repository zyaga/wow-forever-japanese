-- UI/GuildBank.lua: the guild bank on Forever (surface "guildbank", area "ui", ADR-016, ADR-029).
-- Load-on-demand Blizzard_GuildBankUI (Mainline\Blizzard_GuildBankUI.lua|xml on `camelot`); its [Bootstrap] file
-- registers Enum.PlayerInteractionType.GuildBanker at login → ShowGuildBankFrame → LoadAddOn + ShowUIPanel
-- (blizzard_guildbankui_bootstrap.lua:7–33). Set up through WFJ.LoadOnDemand.when. Whether Forever has a guild vault
-- is an in-game question.
-- Static labels (XML text=, mainline/blizzard_guildbankui.xml), each restricted to its own key:
--   GuildBankFrameTab1–4 GUILD_BANK / GUILD_BANK_LOG / GUILD_BANK_MONEY_LOG / GUILD_BANK_TAB_INFO (:570–577),
--   DepositButton DEPOSIT (:552), WithdrawButton WITHDRAW (:561), GuildBankMoneyLimitLabel GUILDBANK_AVAILABLE_MONEY
--   (:517), BuyInfo.TabText PURCHASE_TAB_TEXT (:625), GuildBankFrameTabCost COSTS_LABEL (:635), BuyInfo.PurchaseButton
--   BANKSLOTPURCHASE (:655), GuildBankInfoSaveButton SAVE_CHANGES (:712), and the tab-name popup's header
--   GuildBankPopupFrame.BorderBox.EditBoxHeaderText GUILDBANK_POPUP_TEXT (KeyValue :804, written by the icon
--   selector's OnLoad, blizzard_sharedxml/mainline/shareduipaneltemplates.lua:1844).
-- Writers, each the frame's own method called as `self:…()`, post-hooked on the instance:
--   GuildBankFrame:Update (lua:146–229) → ErrorMessage: NO_VIEWABLE_GUILDBANK_TABS (:156), NO_GUILDBANK_TABS (:167),
--     NO_VIEWABLE_GUILDBANK_LOGS (:213);
--   GuildBankFrame:UpdateTabBuyingInfo (:251–269) → BuyInfo.PurchasedText NUM_GUILDBANK_TABS_PURCHASED (:254);
--   GuildBankFrame:UpdateTabs (:271–442) → TabTitle: the two whole-key forms GUILD_BANK_MONEY_LOG (:371) and
--     BUY_GUILDBANK_TAB (:317); every other title is "<head>  <access>" (guildBankTab, :373–398): split at the
--     LAST double space (GUILDBANK_LOG_TITLE_FORMAT "%s  Log" holds one itself), the access word a GUILDBANK_TAB_*
--     entry (colour in the English), the head GUILDBANK_LOG_TITLE_FORMAT / GUILDBANK_INFO_TITLE_FORMAT around the
--     tab's name, or the bare tab name, kept as written. No access word: the whole title stays English.
--     → LimitLabel (:412–421): GUILDBANK_REMAINING_MONEY "for <tab name>: <STACKS | NONE | UNLIMITED>", only
--     that key: a tab name is a `text` argument, never matched alone.
-- guildBankLog: GuildBankMessageFrame (a ScrollingMessageFrame) gets one AddMessage per transaction from
--   GuildBankFrame_UpdateLog / _UpdateMoneyLog (:750–816) after a Clear(): "<template>[ x <n>]<GUILD_BANK_LOG_TIME>".
--   Its AddMessage is post-hooked on the instance; the time suffix (the last colour group) and a GUILDBANK_LOG_QUANTITY
--   " x %d" are peeled, the head is matched by key (the GUILDBANK_* log templates: player names, item links, money and
--   tab names kept as written), and the entry is rewritten in the frame's history with TransformMessages, as
--   UI/ChatSystem does for chat (scrollingmessageframe.lua:95–107). The Japanese ↔ English pairs of the current log
--   are remembered until the next Clear(); Alt / the switch / the area put the English (and the frame's own font) back
--   on the visible lines and releasing puts the Japanese back (AddOnDisplayRefreshedCallback + State changes). A line
--   that arrives while the addon or the area is off, or whose row is not trusted, stays English.
-- Tooltip: the buy-tab button's BUY_GUILDBANK_TAB (tabButton.tooltip, :300; GuildBankTabButtonMixin:OnEnter
--   :564–567). The same buttons show a tab's name otherwise, so every tab button is an owner restricted to that key.
-- Never touched: tab names (alone or as template arguments), player and item names in the log, the info EditBox,
-- the money.
-- Release on GuildBankFrame's OnHide.
local _, WFJ = ...
local GuildBank = {}
WFJ.GuildBank = GuildBank

local SURFACE = "guildbank"
GuildBank.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_GuildBankUI"
local F = "GuildBankFrame"
local MAX_TABS = 8 -- MAX_GUILDBANK_TABS (blizzard_guildbankui.lua:1); a missing button is skipped

GuildBank.NEVER_TOUCH = { "GuildBankTabInfoEditBox",
  "GuildBankPopupFrame.BorderBox.IconSelectorEditBox" }

-- record key → { candidate, the key(s) the widget may show }
local LABELS = {
  tab1 = { "GuildBankFrameTab1", { "GUILD_BANK" } }, tab2 = { "GuildBankFrameTab2", { "GUILD_BANK_LOG" } },
  tab3 = { "GuildBankFrameTab3", { "GUILD_BANK_MONEY_LOG" } },
  tab4 = { "GuildBankFrameTab4", { "GUILD_BANK_TAB_INFO" } },
  deposit = { F .. ".DepositButton", { "DEPOSIT" } }, withdraw = { F .. ".WithdrawButton", { "WITHDRAW" } },
  available = { "GuildBankMoneyLimitLabel", { "GUILDBANK_AVAILABLE_MONEY" } },
  buyText = { F .. ".BuyInfo.TabText", { "PURCHASE_TAB_TEXT" } },
  buyCost = { "GuildBankFrameTabCost", { "COSTS_LABEL" } },
  buyButton = { F .. ".BuyInfo.PurchaseButton", { "BANKSLOTPURCHASE" } },
  purchased = { F .. ".BuyInfo.PurchasedText", { "NUM_GUILDBANK_TABS_PURCHASED" } },
  save = { "GuildBankInfoSaveButton", { "SAVE_CHANGES" } },
  popupHeader = { "GuildBankPopupFrame.BorderBox.EditBoxHeaderText", { "GUILDBANK_POPUP_TEXT" } },
  error = { F .. ".ErrorMessage", { "NO_VIEWABLE_GUILDBANK_TABS", "NO_GUILDBANK_TABS", "NO_VIEWABLE_GUILDBANK_LOGS" } },
  limit = { F .. ".LimitLabel", { "GUILDBANK_REMAINING_MONEY" } },
}
local ORDER = {}
for key in pairs(LABELS) do ORDER[#ORDER + 1] = key end
table.sort(ORDER)
local OPTS = {}
for key, l in pairs(LABELS) do OPTS[key] = { only = l[2] } end
local BUY_TOOLTIP = { only = { "BUY_GUILDBANK_TAB" } }
local TITLE_WHOLE = { "GUILD_BANK_MONEY_LOG", "BUY_GUILDBANK_TAB" }
local TITLE_HEAD = { "GUILDBANK_INFO_TITLE_FORMAT", "GUILDBANK_LOG_TITLE_FORMAT" }
local TITLE_ACCESS = { "GUILDBANK_TAB_DEPOSIT_ONLY", "GUILDBANK_TAB_FULL_ACCESS", "GUILDBANK_TAB_LOCKED",
  "GUILDBANK_TAB_WITHDRAW_ONLY" }
local LOG_KEYS = { "GUILDBANK_DEPOSIT_FORMAT", "GUILDBANK_WITHDRAW_FORMAT", "GUILDBANK_MOVE_FORMAT",
  "GUILDBANK_DEPOSIT_MONEY_FORMAT", "GUILDBANK_WITHDRAW_MONEY_FORMAT", "GUILDBANK_REPAIR_MONEY_FORMAT",
  "GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT", "GUILDBANK_BUYTAB_MONEY_FORMAT", "GUILDBANK_UNLOCKTAB_FORMAT",
  "GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT", "GUILDBANK_GUILD_RENAME_PURCHASE", "GUILDBANK_GUILD_RENAME_REFUND" }
local LOG_TIME = { "GUILD_BANK_LOG_TIME" }

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  Compat.declare(SURFACE, "frame", { F })
  Compat.declare(SURFACE, "tabTitle", { F .. ".TabTitle" })
  Compat.declare(SURFACE, "log", { "GuildBankMessageFrame" })
  Compat.declare(SURFACE, "isSecret", { "issecretvalue" })
  for key, l in pairs(LABELS) do Compat.declare(SURFACE, key, { l[1] }) end
end

-- True when `fs` still shows the Japanese of record `recKey` (a re-run pass keeps it, never re-splits it).
local function ours(recKey, fs)
  local rec = WFJ.SurfaceState.get(SURFACE, recKey)
  return rec ~= nil and rec.fs == fs and rec.applied ~= nil and fs:GetText() == rec.applied
end

-- The tab title (guildBankTab). → 1 | 0
function GuildBank.showTitle()
  local fs = WFJ.Labels.widget(get("tabTitle"))
  if not fs then return 0 end
  if ours("tabTitle", fs) then return 1 end
  local text = fs:GetText()
  if WFJ.Labels.part(text, TITLE_WHOLE) then
    return WFJ.Labels.show(SURFACE, "tabTitle", fs, nil, { only = TITLE_WHOLE })
  end
  local head, tail
  if type(text) == "string" then head, tail = text:match("^(.*)  (.-)$") end
  local access = head and WFJ.Labels.part(tail, TITLE_ACCESS)
  if not access then return WFJ.Labels.showArgs(SURFACE, "tabTitle", fs, nil) end
  local parts = { WFJ.Labels.part(head, TITLE_HEAD) or head, "  ", access }
  return WFJ.Labels.showArgs(SURFACE, "tabTitle", fs, access.key, { form = "seq", parts = parts })
end

-- OnShow and hooksecurefunc target (Update / UpdateTabs / UpdateTabBuyingInfo). → the number of dictionary words
function GuildBank.show()
  local list = {}
  for _, key in ipairs(ORDER) do list[#list + 1] = { key, get(key), OPTS[key] } end
  local n = GuildBank.showTitle()
  return n + WFJ.Labels.showAll(SURFACE, list)
end

-- ── The log (guildBankLog) ──────────────────────────────────────────────────
local logJa = {} -- Japanese → the English it stands for, for the lines of the current log

local function on() return WFJ.State.enabled and WFJ.State.areaEnabled("ui") end
local function secret(v)
  local isSecret = get("isSecret")
  return type(isSecret) == "function" and isSecret(v) and true or false
end

-- The Japanese of one log line, or nil (not a log template, an untrusted row, a failed fill). → ja | nil
function GuildBank.logLine(message)
  local index = WFJ.UIIndex
  if not index or type(message) ~= "string" then return nil end
  local head, suffix = message:match("^(.*)(|c%x%x%x%x%x%x%x%x[^|]*|r)$")
  local time = head and WFJ.Labels.part(suffix, LOG_TIME)
  if not time then return nil end
  local body, quantity = head:match("^(.-)( x %d+)$")
  local line = WFJ.Labels.part(body or head, LOG_KEYS)
  if not line then return nil end
  for _, p in ipairs({ line, time }) do
    local row = index.rows[p.key]
    if type(row) ~= "table" or row[3] ~= "." then return nil end -- trusted rows only
  end
  local ja = index:fill("", { form = "seq", parts = { line, quantity or "", time } })
  if type(ja) ~= "string" or ja == "" or ja == message then return nil end
  return ja
end

-- hooksecurefunc target (GuildBankMessageFrame:AddMessage). → 1 | 0
function GuildBank.onLogMessage(frame, message)
  if type(frame) ~= "table" or type(message) ~= "string" or secret(message) or not on()
      or type(frame.TransformMessages) ~= "function" then return 0 end
  local ja = GuildBank.logLine(message)
  if not ja or (logJa[ja] ~= nil and logJa[ja] ~= message) then return 0 end -- one Japanese, one English
  logJa[ja] = message
  frame:TransformMessages(function(text) return not secret(text) and text == message end,
    function(_, ...) return ja, ... end)
  return 1
end

local fonted = setmetatable({}, { __mode = "k" }) -- log rows showing the bundled face

-- The visible lines showing one of our Japanese strings: the Japanese in the bundled face, or (Alt held, the addon
-- or its UI area off) the remembered English in the frame's own font. → lines set
function GuildBank.showLog(frame)
  frame = frame or get("log")
  local lines = type(frame) == "table" and type(frame.visibleLines) == "table" and frame.visibleLines or {}
  local fontObject = type(frame) == "table" and type(frame.GetFontObject) == "function" and frame:GetFontObject() or nil
  local wanted, n = on() and not WFJ.Modifier.isDown(), 0
  for _, line in ipairs(lines) do
    local info = type(line) == "table" and line.messageInfo or nil
    local ja = type(info) == "table" and info.message or nil
    local translated = type(ja) == "string" and logJa[ja] ~= nil
    if translated and wanted then
      line:SetText(ja)
      local _, size, flags = line:GetFont()
      if type(fontObject) == "table" and type(fontObject.GetFont) == "function" then
        local _, objSize, objFlags = fontObject:GetFont()
        size, flags = objSize or size, objFlags or flags
      end
      line:SetFont(WFJ.Font.PATH, size or WFJ.Font.DEFAULT_SIZE, flags or "")
      fonted[line] = true
    else
      if translated then line:SetText(logJa[ja]) end
      -- the log's rows are fixed and the refresh's SetFontObject does not undo our SetFont (UI/ChatSystem.lua)
      if fonted[line] and WFJ.Font.restore(line, fontObject) then fonted[line] = nil end
    end
    if translated then n = n + 1 end
  end
  return n
end

local function hookLog()
  local log = get("log")
  if type(log) ~= "table" or type(log.AddMessage) ~= "function" then return false end
  hooksecurefunc(log, "AddMessage", GuildBank.onLogMessage)
  if type(log.Clear) == "function" then hooksecurefunc(log, "Clear", function() logJa = {} end) end
  if type(log.AddOnDisplayRefreshedCallback) == "function" then log:AddOnDisplayRefreshedCallback(GuildBank.showLog) end
  for _, change in ipairs({ "enabled", "area", "modifier" }) do
    WFJ.State.on(change, function() GuildBank.showLog() end)
  end
  return true
end

function GuildBank.release()
  return WFJ.Render.release(SURFACE)
end

-- The side tab buttons (frame.BankTabs[i].Button, xml:102–157) own the buy-tab tooltip. → the number registered
local function registerTabs(frame)
  local tabs, n = frame.BankTabs, 0
  if type(tabs) ~= "table" then return 0 end
  for i = 1, MAX_TABS do
    local tab = tabs[i]
    local button = type(tab) == "table" and tab.Button or nil
    if type(button) == "table" then
      WFJ.HelpTooltip.register(button, BUY_TOOLTIP)
      n = n + 1
    end
  end
  return n
end

local hooked, waiting = false, false

-- Runs once Blizzard_GuildBankUI is loaded (now, or on its ADDON_LOADED). Declared again here: a declare clears
-- Compat's memo, which holds `false` for a name looked up before the addon loaded.
function GuildBank.setup()
  declare()
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  WFJ.Labels.forbidNames(GuildBank.NEVER_TOUCH) -- its widgets exist only now
  for _, method in ipairs({ "Update", "UpdateTabs", "UpdateTabBuyingInfo" }) do
    if type(frame[method]) == "function" then hooksecurefunc(frame, method, GuildBank.show) end
  end
  if type(frame.HookScript) == "function" then
    frame:HookScript("OnShow", GuildBank.show)
    frame:HookScript("OnHide", GuildBank.release)
  end
  registerTabs(frame)
  hookLog()
  if type(frame.IsShown) == "function" and frame:IsShown() then GuildBank.show() end
  return true
end

-- Called by Main after Compat.init, HelpTooltip.init, ButtonText.init and LoadOnDemand.init. → true when the window
-- exists now, false while it waits for Blizzard_GuildBankUI.
function GuildBank.init()
  declare()
  if hooked then return false end
  if not waiting then
    waiting = true
    return WFJ.LoadOnDemand.when(ADDON, GuildBank.setup) and hooked
  end
  return false
end
