-- Core/UIStrings.lua: the UI string index (ADR-015). Pure: every dependency is injected, no global is read.
-- The shipped rows (WFJ.Data.ui: key → { ja, h1, status }) carry Japanese and the first 32 bits of the English hash
-- only, never English (ADR-002). The English a live line is matched against is the client's own global string,
-- read at build time through deps.english(key) and admitted only when its hash equals the row's h1: a client whose
-- English differs from the English the Japanese was drafted against leaves that line English.
-- A fixed word the client exposes no string for (an item subclass: the API returns the long "Staves" while the tooltip
-- shows "Staff") is matched by FINGERPRINT instead: a live line whose hash equals the row's
-- h1 is that word. Only rows whose Japanese takes no argument can be matched that way; a template needs its English.
--   UIStrings.build{ rows, english(key) → text|nil, hash(text) → h1 } → index
--   index:match(text)     → key, args | nil     exact string (by English, then by h1), then templates (most literal
--                                               text first), then labels
--   index:fill(ja, args)  → text                the Japanese with the captured values put back (verbatim)
--   index:matchOnly(text, keys) → key, args | nil   match, but only a key of the set (a widget that may hold a name)
--   index.counts          { shipped, indexed, hashed, mismatched, ambiguous, unresolved, unsupported } · index.problems
-- Plural grammar (`|4Day:Days;`) is matched in its singular, plural and raw forms (ADR-016). The label forms reach
-- only the keys whitelisted for them. Fingerprint rows (no global string): item subclasses, enchantment stat lines
-- (`SpellItemEnchantment:<id>`), spellbook subtexts (`SpellSubtext:<spellID>`, "Racial Passive") and the client-table
-- text families (ADR-042: `FactionDescription:<id>`, `CreatureType:<id>`, …). Open fingerprint keys that share one
-- English are synonyms of the key that answers it; a restricted family's rows sit in an index of their own, one per
-- family (index:restrictedKeys), so a family may word an English its own way ("Close": 寄せ in the barber shop).
-- A SLOTTED row (`EmoteText:<id>`, "%s waves at you.") keeps `%s` slots the live line fills with names; with no
-- English to read, it is matched by putting the slots back (index:matchSlots).
-- A TEMPLATED row (`SharedString:<id>`, `EventToastText:<id>`, `FriendshipGain:<id>` whose Japanese takes arguments)
-- is a format string the client fills before showing it ("You gain %d Rank Points."). Still restricted: it is found
-- only through matchOnly with its key, by the line's digits put back as `%d` (index:matchCounted), or against the
-- template the client hands the caller (index:matchTemplate: plural groups and text arguments too).
-- Format specifiers follow Blizzard's format(): %s %d %i %c %f %g with optional flags / width / precision, %N$ for a
-- positional argument, %% for a literal percent. A captured argument that is itself an exact entry's English is
-- shown as that entry's Japanese (school words, reputation standings); every other capture is shown as captured.
local _, WFJ = ...
local UIStrings = WFJ.UIStrings or {}
WFJ.UIStrings = UIStrings

-- Key families with no client string: the live line is matched by its fingerprint (h1). → bool
local FINGERPRINT_PREFIXES = { "^ItemSubClass:", "^SpellItemEnchantment:", "^SpellSubtext:",
  -- ADR-042: the client-table text families (pipeline io/wago.TEXT_FAMILIES)
  "^FactionDescription:", "^AchievementTitle:", "^AchievementDescription:", "^AchievementReward:",
  "^AchievementCategory:", "^SkillLineDescription:", "^SkillCategory:", "^EmoteText:", "^HolidayDescription:",
  "^CurrencyDescription:", "^CurrencyCategory:", "^DispelType:", "^CreatureType:", "^QuestSort:",
  -- the auction house's long subclass names, the barber shop, the PvP scoreboard, the group
  -- finder, the UI widgets' lines (numbered rows) and the wardrobe's variant words
  "^ItemSubClassName:", "^CustomizationCategory:", "^CustomizationOption:", "^CustomizationChoice:",
  "^CustomizationSource:", "^PvpColumn:", "^PvpColumnTooltip:", "^PvpStat:", "^LfgCategory:",
  "^LfgActivityGroup:", "^LfgActivity:", "^WidgetText:", "^ItemNameDescription:",
  -- the families the served-text inventory found shown on Forever (ADR-052)
  "^CriteriaText:", "^RenownRewardName:", "^RenownRewardDescription:", "^RenownRewardToast:", "^SharedString:",
  "^TradeSkillCategory:", "^MailBody:", "^QuestTag:", "^AreaPoiDescription:", "^AreaPoiState:", "^PetLoyalty:",
  "^PvpLongDescription:", "^Difficulty:", "^EventToastText:", "^BroadcastText:", "^PetFood:", "^RestState:",
  "^PlayerConditionFailure:", "^LockTypeName:", "^LockTypeResource:", "^LockTypeVerb:", "^FlyoutName:",
  "^FlyoutDescription:", "^ServerMessage:", "^TransmogSituation:", "^TransmogTrigger:",
  "^TransmogTriggerDescription:", "^TransmogSlotOption:",
  "^ItemSubClassMask:", "^RecentAllyType:", "^RecentAllyInteraction:", "^FriendshipGain:",
  "^InstanceEntryMessage:", "^InstanceEntryFailure:" }
function UIStrings.isFingerprintKey(key)
  if type(key) ~= "string" then return false end
  for _, p in ipairs(FINGERPRINT_PREFIXES) do
    if key:find(p) then return true end
  end
  return false
end

-- The client-table text families are RESTRICTED (ADR-042): found only where a widget names the family
-- (index:matchOnly with its keys, or a family argument kind), never by the unrestricted match. Their English can be
-- an item's or a spell's name too ("Journeyman Engineer" is an achievement and a spell), and names stay English.
-- → bool
local RESTRICTED_PREFIXES = { "^FactionDescription:", "^AchievementTitle:", "^AchievementDescription:",
  "^AchievementReward:", "^AchievementCategory:", "^SkillLineDescription:", "^SkillCategory:", "^EmoteText:",
  "^HolidayDescription:", "^CurrencyDescription:", "^CurrencyCategory:", "^DispelType:", "^CreatureType:",
  "^QuestSort:", "^ItemSubClassName:", "^CustomizationCategory:", "^CustomizationOption:", "^CustomizationChoice:",
  "^CustomizationSource:", "^PvpColumn:", "^PvpColumnTooltip:", "^PvpStat:", "^LfgCategory:",
  "^LfgActivityGroup:", "^LfgActivity:", "^WidgetText:", "^ItemNameDescription:",
  "^CriteriaText:", "^RenownRewardName:", "^RenownRewardDescription:", "^RenownRewardToast:", "^SharedString:",
  "^TradeSkillCategory:", "^MailBody:", "^QuestTag:", "^AreaPoiDescription:", "^AreaPoiState:", "^PetLoyalty:",
  "^PvpLongDescription:", "^Difficulty:", "^EventToastText:", "^BroadcastText:", "^PetFood:", "^RestState:",
  "^PlayerConditionFailure:", "^LockTypeName:", "^LockTypeResource:", "^LockTypeVerb:", "^FlyoutName:",
  "^FlyoutDescription:", "^ServerMessage:", "^TransmogSituation:", "^TransmogTrigger:",
  "^TransmogTriggerDescription:", "^TransmogSlotOption:",
  "^ItemSubClassMask:", "^RecentAllyType:", "^RecentAllyInteraction:", "^FriendshipGain:",
  "^InstanceEntryMessage:", "^InstanceEntryFailure:" }
function UIStrings.isRestrictedKey(key)
  if type(key) ~= "string" then return false end
  for _, p in ipairs(RESTRICTED_PREFIXES) do
    if key:find(p) then return true end
  end
  return false
end

-- fingerprint keys whose English holds `%s` slots a live line fills with names (index:matchSlots). → bool
function UIStrings.isSlottedKey(key)
  return type(key) == "string" and key:find("^EmoteText:") ~= nil
end

-- TEMPLATED rows: the restricted families whose English is a format string the client fills (talent requirement
-- lines, the rank toast, the friendship rank-points chat line). Only their rows whose Japanese takes an argument are
-- templated; a row with none stays a plain restricted fingerprint row. → bool
local TEMPLATED_PREFIXES = { "^SharedString:", "^EventToastText:", "^FriendshipGain:", "^ServerMessage:" }
function UIStrings.isTemplatedKey(key)
  if type(key) ~= "string" then return false end
  for _, p in ipairs(TEMPLATED_PREFIXES) do
    if key:find(p) then return true end
  end
  return false
end

-- NUMBERED rows (`WidgetText:<id>`, a UI widget's line): the English holds world-state tokens the client
-- replaces with live numbers; the row's h1 is its skeleton's (every number run `#`, pipeline core/numbered) and its
-- Japanese takes the k-th number of the live line as `%k$s` (index:matchNumbers). → bool
function UIStrings.isNumberedKey(key)
  return type(key) == "string" and key:find("^WidgetText:") ~= nil
end

-- The keys of one fingerprint family ("CurrencyCategory") the rows ship, as a set (a widget's `only` list). → set
function UIStrings.familyKeys(rows, family)
  local set, prefix = {}, "^" .. family .. ":"
  for key in pairs(rows or {}) do
    if key:find(prefix) then set[key] = true end
  end
  return set
end

-- Splits a Blizzard template into parts: { lit = "…" } | { arg = n, conv = "d" }. Plain specifiers take arguments in
-- order; %N$ names argument N. → parts, argCount
local function parse(template)
  local parts, n, i, len = {}, 0, 1, #template
  local lit = {}
  local function flush()
    if #lit > 0 then parts[#parts + 1] = { lit = table.concat(lit) }; lit = {} end
  end
  while i <= len do
    local ch = template:sub(i, i)
    if ch ~= "%" then
      lit[#lit + 1] = ch
      i = i + 1
    elseif template:sub(i + 1, i + 1) == "%" then
      lit[#lit + 1] = "%"
      i = i + 2
    else
      local pos, flags, conv = template:match("^%%(%d*)%$?([-+ #0]*%d*%.?%d*)([sdicfg])", i)
      -- a lone space flag whose conversion runs straight into a letter ("above 100% is for") is prose, not a
      -- specifier, positional or not (the Python twin, core/specifiers.SPEC, agrees)
      if conv and flags == " " then
        local spec = template:match("^%%%d*%$?[-+ #0]*%d*%.?%d*[sdicfg]", i)
        if template:sub(i + #spec, i + #spec):match("%a") then conv = nil end
      end
      if not conv then
        lit[#lit + 1] = ch -- a lone % that is not a specifier renders as itself
        i = i + 1
      else
        local whole = template:match("^%%%d*%$?[-+ #0]*%d*%.?%d*[sdicfg]", i)
        flush()
        local index
        if pos ~= "" and template:sub(i + #pos + 1, i + #pos + 1) == "$" then
          index = tonumber(pos)
        else
          n = n + 1
          index = n
        end
        parts[#parts + 1] = { arg = index, conv = conv, flags = flags }
        i = i + #whole
      end
    end
  end
  flush()
  local count = 0
  for _, p in ipairs(parts) do
    if p.arg and p.arg > count then count = p.arg end
  end
  return parts, count
end
UIStrings.parse = parse

local MAGIC = "([%^%$%(%)%%%.%[%]%*%+%-%?])"
local NUMBER = "(%-?%d[%d%.,]*)"
local CAPTURE = { s = NUMBER, d = "(%-?[%d,]+)", i = "(%-?[%d,]+)", c = "([%+%-])", f = "(%-?[%d%.,]+)",
  g = "(%-?[%d%.,]+)" }

local ALL_TEXT = setmetatable({}, { __index = function() return "text" end })
local function isErrorKey(key)
  return key:sub(1, 4) == "ERR_" or key:sub(1, 13) == "SPELL_FAILED_"
end
UIStrings.isErrorKey = isErrorKey
local function isChatKey(key)
  for _, family in ipairs(UIStrings.CHAT_FAMILIES) do
    if key:find(family) then return true end
  end
  return false
end
UIStrings.isChatKey = isChatKey

local function argKinds(key)
  local kinds = UIStrings.ARGS[key]
  if kinds then return kinds end
  -- a templated row's `%s` is a name or a word the client put in (a talent tree's name), kept as written
  if isErrorKey(key) or isChatKey(key) or UIStrings.isTemplatedKey(key) then return ALL_TEXT end
  return nil
end
UIStrings.argKinds = argKinds

-- The community lines Blizzard's Lua formats (UI/Errors' Lua templates) are asked for by key too.
local function luaFormatted(key)
  return key:sub(1, 18) == "ERROR_CLUB_ACTION_" or key:sub(1, 20) == "CLUB_REMOVED_REASON_"
end
-- The short stat names ("Avoidance", "Spell Power") are item and spell names too: only the comparison's stat change
-- lines ask for them (UI/Tooltip matchStatChange).
function UIStrings.isStatNameKey(key)
  return type(key) == "string" and key:sub(1, 9) == "ITEM_MOD_" and key:sub(-6) == "_SHORT"
end
local function keyOnly(key)
  return UIStrings.ONLY[key] or UIStrings.isStatNameKey(key)
    or ((isErrorKey(key) or luaFormatted(key) or isChatKey(key)) and not UIStrings.ERROR_UNRESTRICTED[key])
end
UIStrings.keyOnly = keyOnly

local KIND_CAPTURE = { word = "(%a+)", standing = "(%a+)", words = "(%a[%a ]-)", text = "([^%.]-)",
  time = "([%d<][^%(%)]-)", -- "< 1 minute" too
  -- `entryList`: a LIST_DELIMITER-joined list whose every piece is an entry (BAG_FILTER_ASSIGNED_TO), each
  -- shown in Japanese, the delimiter kept; `entryOrText`: an entry's Japanese when it is one, else as written
  entryList = "(.-)", entryOrText = "(.-)",
  skill = "(%a[%a' ,%-]-)", entry = "(.-)", verbatim = "(.-)",
  percent = "([%+%-]?%d[%d%.,]*%%)", -- a signed or plain percentage, shown verbatim
  signed = "([%+%-]%d[%d,]*)", -- a signed count ("+25" honor, rating change), shown verbatim
  modifiers = "([%u%-]+)", -- modifier key names joined by "-" ("SHIFT-ALT"), key names kept as written
  -- ADR-042: a client-table word of ONE family, shown in Japanese when it is that family's row, else as
  -- written (UIStrings.FAMILY_KINDS), never any other entry, so a class, spec or pet-family name stays English
  creatureType = "([^%.]-)", holidayDescription = "(.-)", customizationChoice = "(.-)",
  customizationSource = "(.-)", restState = "([^%.]-)", itemSubClassMask = "([^%.]-)",
  petFoodList = "([^%.]-)", questTitle = "(.-)" }
-- a template with more `|4` groups is not indexed (counted `unsupported`). 4 for TIME_DAYHOURMINUTESECOND
-- (the /played duration, the only listed key with 4): the chat line holds its raw form, which is always matched
local MAX_PLURAL_GROUPS = 4

-- The stat pane (camelot/paperdollframe.lua): every stat row's label is "<name>:", and the
-- resistance hovers are "|cffffffffFire 5|r". Merged into the forms above so no key loses one it already had.
do
  local function grant(key, forms)
    local v = UIStrings.LABELS[key]
    local list = type(v) == "table" and v or (v and { v } or {})
    for _, form in ipairs(forms) do
      local present = false
      for _, f in ipairs(list) do if f == form then present = true end end
      if not present then list[#list + 1] = form end
    end
    UIStrings.LABELS[key] = list
  end
  for _, key in ipairs({ "HEALTH", "MANA", "RAGE", "ENERGY", "FOCUS", "RUNIC_POWER", "STAT_MOVEMENT_SPEED",
    "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_RANGED", "DAMAGE", "WEAPON_SPEED",
    "STAT_ATTACK_POWER", "RANGED_ATTACK_POWER", "STAT_HIT_CHANCE", "STAT_CRITICAL_STRIKE", "STAT_HASTE",
    "STAT_EXPERTISE", "STAT_ARMOR_PENETRATION", "STAT_SPELLPOWER", "STAT_SPELLHEALING", "STAT_SPELL_PENETRATION",
    "MANA_REGEN", "STAT_ENERGY_REGEN", "STAT_FOCUS_REGEN", "DEFENSE", "STAT_DODGE", "STAT_BLOCK",
    "STAT_PARRY", "STAT_ARMOR", "STAT_SPEED", "RESISTANCE0_NAME", "RESISTANCE1_NAME",
    "RESISTANCE2_NAME", "RESISTANCE3_NAME", "RESISTANCE4_NAME", "RESISTANCE5_NAME", "RESISTANCE6_NAME" }) do
    grant(key, { "bareColon" })
  end
  for i = 2, 7 do grant("DAMAGE_SCHOOL" .. i, { "bareColon", "number", "wrapped" }) end
  -- the role radios (unit menus, the Group Finder) and the friends status radios carry an icon in front
  -- the gamepad tooltip lines the client writes as "<atlas>text" with no space: the input-icon line helper,
  -- blizzard_sharedxml/sharedtooltiptemplates.lua:174–177 (map pins, the quest log title's hover)
  for _, key in ipairs({ "TANK", "HEALER", "DAMAGER", "FRIENDS_LIST_AVAILABLE", "FRIENDS_LIST_AWAY",
    "FRIENDS_LIST_BUSY", "MAP_PIN_TOGGLE_FOCUS", "MAP_PIN_TOGGLE_QUEST_FOCUS", "MAP_PIN_TOGGLE_QUEST_DETAILS",
    "SHARE_IN_CHAT", "OBJECTIVES_VIEW_IN_QUESTLOG",
    "CONTEXT_ACTION_LABEL_MORE_ACTIONS" }) do
    grant(key, { "icon" })
  end
  -- ADR-038: the existing forms for the keys it lists with them, and the new label forms
  --   colonPrefixEntry "<colonPrefix entry> <entry>": the rest is itself this entry ("Sold By: Multiple Buyers")
  --   countLabel      "<entry> (<n>)" (mailframe.lua:494)          durationSuffix "<entry> [01:23]" (damage meter)
  --   iconAfter       "<entry> |A…|a" (the undo button)             headerLines    "<entry>\n<name>\n…" (unread mail)
  --   voiceParts      "[|A…|a]<sentence>. <sentence>. <n sentence>.": each sentence an entry
  --                   (channelframe.lua:502–513)
  -- and `paragraphs` parts may be colour-wrapped (social.lua:21–29).
  local MORE_LABEL_FORMS = {
    binding = { "MAINTANK", "MAINASSIST", "PETS", "VOICE_TOOLTIP_PARENTAL_MUTE_MIC",
    "VOICE_TOOLTIP_PARENTAL_UNMUTE_MIC",
      "VOICE_TOOLTIP_SILENCED_MUTE_MIC", "VOICE_TOOLTIP_SILENCED_UNMUTE_MIC", "TRANSMOG_SHEATHE_WEAPON_TOOLTIP" },
    wrapped = { "COOLDOWN_VIEWER_SETTINGS_CHARACTER_LAYOUTS_HEADER", -- BN_TOAST_ONLINE is granted above
      "HUD_EDIT_MODE_CHARACTER_LAYOUTS_HEADER", "COOLDOWN_VIEWER_SETTINGS_USE_STARTER_LAYOUT",
      "TRANSMOG_CUSTOM_SET_DELETE",
      "PROFESSIONS_TRACK_RECIPE", "PROFESSIONS_INSUFFICIENT_REAGENTS", "PROFESSIONS_MISSING_REQUIREMENT",
      "PROFESSIONS_RECIPE_COOLDOWN", "PROFESSIONS_ORDERS_NOT_ENOUGH_REAGENTS", "TRANSMOG_SITUATIONS_NO_VALID_OPTIONS",
      "CLICK_BINDING_MACRO_TITLE",
      -- the auction house quality filter's entries, each in its quality colour
      "ITEM_QUALITY0_DESC", "ITEM_QUALITY1_DESC", "ITEM_QUALITY2_DESC", "ITEM_QUALITY3_DESC", "ITEM_QUALITY4_DESC",
      "ITEM_QUALITY5_DESC" },
    icon = { "DEATH_RECAP_AVOIDABLE_SPELL", "DEATH_RECAP_DEADLY_SPELL" },
    colonPrefix = { "QUICK_JOIN_TOOLTIP_AVAILABLE_ROLES", "COOLDOWN_REMAINING", "TIME_REMAINING" },
    colon = { "VIDEO_OPTIONS_RECOMMENDED" },
    paragraphs = { "OPTION_TOOLTIP_DISABLE_CHAT", "OPTION_TOOLTIP_DISABLE_CHAT_ACCOUNT_MUTE",
      -- the same slot's age-restriction paragraphs on 1.60.1.70009 (social.lua:27)
      "OPTION_TOOLTIP_DISABLE_CHAT_AGE_RESTRICTED_MINOR", "OPTION_TOOLTIP_DISABLE_CHAT_AGE_RESTRICTED_UNVERIFIED" },
    colonPrefixEntry = { "AUCTION_HOUSE_MAIL_MULTIPLE_BUYERS", "AUCTION_HOUSE_MAIL_MULTIPLE_SELLERS" },
    countLabel = { "MAIL_MULTIPLE_ITEMS" }, durationSuffix = { "DAMAGE_METER_COMBAT_NUMBER" },
    iconAfter = { "COOLDOWN_VIEWER_SETTINGS_BUTTON_REVERT_CHANGES" }, headerLines = { "HAVE_MAIL_FROM" },
    voiceParts = { "VOICE_CHAT_CHANNEL_ANNOUNCE" },
  }
  for form, keys in pairs(MORE_LABEL_FORMS) do
    for _, key in ipairs(keys) do grant(key, { form }) end
  end
end

local EQUIP_KEY = "ITEM_SPELL_TRIGGER_ONEQUIP"

local function hasForm(key, form)
  local v = UIStrings.LABELS[key]
  if v == form then return true end
  if type(v) == "table" then
    for _, f in ipairs(v) do if f == form then return true end end
  end
  for _, pat in ipairs(UIStrings.FORM_PATTERNS[form] or {}) do
    if key:find(pat) then return true end
  end
  return false
end
UIStrings.hasForm = hasForm

-- A template's plural groups resolved: every group singular, every group plural, and the raw text (whether the
-- client's GetText returns the resolved or the raw form is not known; both are matched). → list of texts | nil when
-- there are more than MAX_PLURAL_GROUPS groups.
local PLURAL = "|4([^:;|]*):([^;|]*);"
local function pluralForms(en)
  local _, groups = en:gsub(PLURAL, "")
  if groups == 0 then return { en } end
  if groups > MAX_PLURAL_GROUPS then return nil end
  return { (en:gsub(PLURAL, "%1")), (en:gsub(PLURAL, "%2")), en }
end
UIStrings.pluralForms = pluralForms

-- An anchored Lua pattern for a template, the capture → argument index order, the number of literal bytes, and the
-- longest literal word (a plain-find prefilter).
local function compile(template, key)
  local parts = parse(template)
  local kinds = argKinds(key) or {}
  local pat, order, literal, word = { "^" }, {}, 0, ""
  for _, p in ipairs(parts) do
    if p.lit then
      pat[#pat + 1] = (p.lit:gsub(MAGIC, "%%%1"))
      literal = literal + #p.lit
      for w in p.lit:gmatch("[%a][%a']+") do
        if #w > #word then word = w end
      end
    else
      local kind = p.conv == "s" and kinds[p.arg] or nil
      pat[#pat + 1] = kind and KIND_CAPTURE[kind] or CAPTURE[p.conv] or NUMBER
      order[#order + 1] = p.arg
    end
  end
  pat[#pat + 1] = "$"
  return table.concat(pat), order, literal, word
end

local Index = {}
Index.__index = Index

-- The key of an exact word: by the client's English, else by the fingerprint of the live text; never a restricted
-- family's (only a widget that names the family finds those, Index:restrictedKeys). → key | nil
function Index:exactKey(text)
  local key = self.exact[text]
  if key or self.hashCount == 0 then return key end
  key = self.byHash[self.hash(text)]
  if key and UIStrings.isRestrictedKey(key) then return nil end
  return key
end

-- the restricted families' keys a live text's fingerprint names (any family). → list (maybe empty)
local NONE = {}
function Index:restrictedKeys(text)
  if type(text) ~= "string" or text == "" or next(self.byRestricted) == nil then return NONE end
  return self.byRestricted[self.hash(text)] or NONE
end

local MEMO_LIMIT = 512 -- distinct line texts remembered between resets (a hover re-reads the same lines)

-- → key, args | nil. args is { [argIndex] = capture } for a template, or { form = "prefix"|"colon"|"number", rest }.
-- Results (hits and misses) are memoised per text; the table is dropped when it reaches MEMO_LIMIT entries.
function Index:match(text)
  if type(text) ~= "string" or text == "" then return nil end
  local m = self.memo[text]
  if m then return m[1] or nil, m[2] end
  local key, args = self:matchUncached(text)
  if self.memoCount >= MEMO_LIMIT then self.memo, self.memoCount = {}, 0 end
  self.memo[text] = { key or false, args }
  self.memoCount = self.memoCount + 1
  return key, args
end

-- A form granted to `key` or to any key sharing its English (the index names the first of them).
function Index:has(key, form)
  for _, k in ipairs(self.synonyms[key] or { key }) do
    if hasForm(k, form) then return true end
  end
  return false
end

-- Exact string, then templates. → key, args | nil. `allow` (optional): a function(key) → bool that limits the
-- template scan to some keys; every caller but matchOnly's fallback passes none.
-- Whether every key answering an exact word is asked for by key only (the short stat names), so the open match
-- never takes it. → bool
function Index:keyOnlyWord(key)
  for _, k in ipairs(self.synonyms[key] or { key }) do
    if not UIStrings.isStatNameKey(k) then return false end
  end
  return true
end

function Index:core(text, allow)
  local key = self:exactKey(text)
  if key and (allow and allow(key) or (not allow and not self:keyOnlyWord(key))) then return key, nil end
  for _, t in ipairs(self.templates) do
    if (allow and allow(t.key) or (not allow and not t.only))
        and (t.word == "" or text:find(t.word, 1, true)) then
      local caps = { text:match(t.pattern) }
      if caps[1] ~= nil then
        local args, ok = { key = t.key }, true
        local kinds = argKinds(t.key) or {}
        for i, argIndex in ipairs(t.order) do
          args[argIndex] = caps[i]
          if kinds[argIndex] == "word" and not self:exactKey(caps[i]) then ok = false end
          if kinds[argIndex] == "standing" then -- a reputation standing, nothing else
            local k = self:exactKey(caps[i])
            if not (k and k:find("^FACTION_STANDING_LABEL")) then ok = false end
          end
          if kinds[argIndex] == "skill" and caps[i]:find("[%s,%-']$") then ok = false end
          if kinds[argIndex] == "entry" then
            args[argIndex] = self:entryArg(caps[i], t.key)
            if not args[argIndex] then ok = false end
          elseif kinds[argIndex] == "entryOrText" then
            args[argIndex] = self:entryArg(caps[i], t.key) or caps[i]
          elseif UIStrings.FAMILY_KINDS[kinds[argIndex]] then
            args[argIndex] = self:familyArg(caps[i], UIStrings.FAMILY_KINDS[kinds[argIndex]]) or caps[i]
          elseif kinds[argIndex] == "questTitle" then
            local resolve = UIStrings.questTitle
            args[argIndex] = type(resolve) == "function" and resolve(caps[i]) or caps[i]
          elseif UIStrings.FAMILY_LIST_KINDS[kinds[argIndex]] then
            args[argIndex] = self:familyList(caps[i], UIStrings.FAMILY_LIST_KINDS[kinds[argIndex]])
          elseif kinds[argIndex] == "entryList" then
            args[argIndex] = self:entryList(caps[i], t.key)
            if not args[argIndex] then ok = false end
          end
        end
        if ok then return t.key, args end
      end
    end
  end
  return nil
end

-- The argument kinds that hold free text (a name, a title, a sentence): a template with one of them is no `entry`
-- unless the enclosing key opts in (ENTRY_TEXT).
local TEXT_KINDS = { text = true, words = true, skill = true, entry = true, entryOrText = true, entryList = true,
  verbatim = true, creatureType = true, holidayDescription = true, customizationChoice = true,
  customizationSource = true, restState = true, itemSubClassMask = true, petFoodList = true, questTitle = true }
  -- a family argument is free text too
-- The enclosing keys whose `entry` argument may itself be a template that carries text (none yet): every other
-- `entry` is an exact entry or a template whose arguments are numbers, times, percentages or dictionary words, so
-- "- Defeat Hogger (Current Health: 50%)" is never PVP_LEAVE_BUTTON_TIME's "%s (%s)" around a vignette line.
UIStrings.ENTRY_TEXT = {}

-- true when core's (key, args) may stand as an `entry` of `outer`.
local function entryAdmits(key, args, outer)
  if args == nil or UIStrings.ENTRY_TEXT[outer] then return true end
  local kinds = argKinds(key)
  if not kinds then return true end
  for i in pairs(args) do
    if type(i) == "number" and TEXT_KINDS[kinds[i]] then return false end
  end
  return true
end

-- An `entry` argument: the text is itself an entry or template, or such an entry wrapped in one
-- colour ("|cffffd200TODAY|r", guildnews.lua:121), the colour kept around its Japanese. `outer`: the enclosing
-- template's key (entryAdmits). → { entry, args[, open, close] } | nil
-- A `FAMILY_KINDS` argument: `value` as an entry of `family` (by its English or its fingerprint), or nil.
-- → { entry = key } | nil
function Index:familyArg(value, family)
  local prefix = "^" .. family .. ":"
  for _, k in ipairs(self:restrictedKeys(value)) do
    if k:find(prefix) then return { entry = k } end
  end
  return nil
end

-- A `FAMILY_LIST_KINDS` argument: `value` split at its ", " separators, each piece that family's entry or kept as
-- written. → { list = { piece, sep, piece, … } } (a piece is { entry = key } or a string)
function Index:familyList(value, family)
  local list, at = {}, 1
  while true do
    local s, e = value:find(", ", at, true)
    local piece = value:sub(at, (s or 0) - 1)
    list[#list + 1] = self:familyArg(piece, family) or piece
    if not s then break end
    list[#list + 1] = value:sub(s, e)
    at = e + 1
  end
  return { list = list }
end

function Index:entryArg(value, outer)
  local k, a = self:core(value)
  if k and entryAdmits(k, a, outer) then return { entry = k, args = a } end
  local open, inner, close = value:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
  if not open then return nil end
  k, a = self:core(inner)
  return k and entryAdmits(k, a, outer) and { entry = k, args = a, open = open, close = close } or nil
end

-- An `entryList` argument: LIST_DELIMITER-joined pieces ("Equipment, Consumables";
-- containerframe.lua:2319–2335), every piece an entry, each delimiter kept as written. → { list = { item | sep … } }
-- | nil when any piece is not an entry.
function Index:entryList(value, outer)
  local items, pos = {}, 1
  while true do
    local s, e = value:find(",%s*", pos)
    local item = self:entryArg(value:sub(pos, (s or 0) - 1), outer)
    if not item then return nil end
    items[#items + 1] = item
    if not s then break end
    items[#items + 1] = value:sub(s, e)
    pos = e + 1
  end
  return { list = items }
end

-- The filled Japanese of an entryArg / entryList value, or the value itself when it is a string. → text | nil
function Index:fillArg(v)
  if type(v) ~= "table" then return v end
  if v.list then
    local out = {}
    for i, item in ipairs(v.list) do
      out[i] = self:fillArg(item)
      if out[i] == nil then return nil end
    end
    return table.concat(out)
  end
  local body = self:fill(self.rows[v.entry][1], v.args)
  if body == nil then return nil end
  return (v.open or "") .. body .. (v.close or "")
end

-- voiceParts: the voice-channel announce line, "%1$s %2$s %3$s" with no literal of its own
-- (channelframe.lua:502–513): an optional leading atlas, then three sentences (the channel notification, the
-- communication mode, the member count), each an entry. → a `seq` args | nil
function Index:voiceParts(text)
  local atlas, body = text:match("^(|A[^|]*|a)(.*)$")
  local s1, s2, s3 = (body or text):match("^(.-%.) (.-%.) (%d.-%.)$")
  if not s1 then return nil end
  local parts = { atlas or "" }
  for _, sentence in ipairs({ s1, s2, s3 }) do
    local k, a = self:core(sentence)
    if not k then return nil end
    if #parts > 1 then parts[#parts + 1] = " " end
    parts[#parts + 1] = { key = k, args = a }
  end
  return { form = "seq", parts = parts }
end

function Index:matchUncached(text)
  local key, cargs = self:core(text)
  if key then return key, cargs end
  for _, p in ipairs(self.prefixes) do -- "Reagents: Linen Cloth"
    if #text > #p.en and text:sub(1, #p.en) == p.en then
      return p.key, { form = "prefix", rest = text:sub(#p.en + 1) }
    end
  end
  local icon, after = text:match("^(|[TA][^|]*|[ta] ?)(.+)$") -- "|T…|t Available", a role radio
  if icon then
    local k, a = self:core(after)
    if k and self:has(k, "icon") then return k, { form = "affix", before = icon, after = "", inner = a } end
  end
  local left, rest = text:match("^(.-): (.+)$") -- "Sell Price: 5c"
  key = left and self:exactKey(left)
  if key and self:has(key, "colon") then return key, { form = "colon", rest = rest } end
  left, rest = text:match("^(.-) ([%d%.,/]+)$") -- "Speed 2.60", "Rank 3"
  key = left and self:exactKey(left)
  if key and self:has(key, "number") then return key, { form = "number", rest = rest } end
  left = text:match("^(.-):$") -- "Strength:"
  key = left and self:exactKey(left)
  if key and self:has(key, "bareColon") then return key, { form = "bareColon" } end
  left, rest = text:match("^(.-:) (.+)$") -- "Item Sold: Linen Cloth"
  key = left and self:exactKey(left)
  if key and self:has(key, "colonPrefix") then
    local restKey = self:exactKey(rest) -- colonPrefixEntry: "Sold By: Multiple Buyers" (mailframe.lua:787)
    if restKey and self:has(restKey, "colonPrefixEntry") then
      return key, { form = "colonPrefix", rest = rest, restKey = restKey }
    end
    return key, { form = "colonPrefix", rest = rest }
  end
  if key and self:has(key, "list") then -- "Requires: Level |cffffffff5|r, First Aid (|cffffffff50|r)"
    local items = {}
    -- an item is read as a list item only: "Level |cffff20204|r" is also a spell's subtext row ("Level 4"),
    -- which the open match would take first and leave the item in English
    local isItem = function(k) return self:has(k, "listItem") end
    for item in (rest .. ", "):gmatch("(.-), ") do
      local k, a = self:core(item, isItem)
      if k and self:has(k, "listItem") then items[#items + 1] = { key = k, args = a }
      else items[#items + 1] = { text = item } end
    end
    return key, { form = "list", items = items }
  end
  local open, inner, close = text:match("^(|c%x%x%x%x%x%x%x%x)(.-)(%s*|r%s*)$") -- "|cff20ff203 Days |r"
  if open then
    local k, a = self:core(inner)
    if not k then -- "|cffffffffArmor 150|r": a number-form label inside the colour (the paperdoll hovers)
      local l, r = inner:match("^(.-) ([%d%.,/]+)$")
      k = l and self:exactKey(l)
      if k and self:has(k, "number") then a = { form = "number", rest = r } else k = nil end
    end
    if k and self:has(k, "wrapped") then return k, { form = "wrapped", open = open, close = close, inner = a } end
    -- two duration terms ("5 Hrs 30 Mins"): the record is the first term's key; fill shows the whole duration
    local first = inner:match("^(.-[%a;]) %d")
    k = first and self:core(first)
    if k and self:has(k, "wrapped") and self:duration(inner) then
      return k, { form = "wrapped", open = open, close = close, duration = inner }
    end
  end
  -- "Character Info |cffffd200(C)|r", and the pet bar's "Attack|cffffd200 (Ctrl-1)|r"
  -- the colour code is the client's (C_ColorUtil output; its hex case is not ours to assume), so any colour is taken
  inner, rest = text:match("^(.-)( ?|c%x%x%x%x%x%x%x%x ?%(.-%)|r)$")
  if inner then
    local k, a = self:core(inner)
    if k and self:has(k, "binding") then return k, { form = "binding", rest = rest, inner = a } end
  end
  if text:find("\n\n", 1, true) then -- "<XP bar help sentence>\n\n<rest state>" (one tooltip line)
    local parts, ok = {}, true
    for part in (text .. "\n\n"):gmatch("(.-)\n\n") do
      local k, a = self:core(part)
      local wrapOpen, wrapClose
      if not k then -- a colour-wrapped paragraph (RED_FONT_COLOR:WrapTextInColorCode, social.lua:21–29)
        local o, body, c = part:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
        if o then
          k, a = self:core(body)
          wrapOpen, wrapClose = o, c
        end
      end
      if k and self:has(k, "paragraphs") then
        parts[#parts + 1] = { key = k, args = a, open = wrapOpen, close = wrapClose }
      else
        ok = false
        break
      end
    end
    if ok and #parts > 1 then return parts[1].key, { form = "paragraphs", parts = parts } end
    -- a paragraph appended to a template that itself holds "\n\n" (the Spirit tooltip + its sitting
    -- warning, camelot paperdollframestats.lua:283): the last break splits it in two
    local head, last = text:match("^(.*)\n\n(.-)$")
    if head then
      local k1, a1 = self:core(head)
      local k2, a2 = self:core(last)
      if k1 and k2 and self:has(k1, "paragraphs") and self:has(k2, "paragraphs") then
        return k1, { form = "paragraphs", parts = { { key = k1, args = a1 }, { key = k2, args = a2 } } }
      end
    end
  end
  left, rest = text:match("^(.-)  (.*)$") -- "5 People Found  (50 displayed)" (the who list's totals)
  if left then
    local k, a = self:core(left)
    if k and self:has(k, "joined") then
      local k2, a2
      if rest ~= "" then k2, a2 = self:core(rest) end
      if rest == "" or (k2 and self:has(k2, "joined")) then
        return k, { form = "joined", inner = a, restKey = k2, restArgs = a2, rest = rest }
      end
    end
  end
  local trigger = self.rows[EQUIP_KEY] and self.exact[self.equipEnglish or ""] == EQUIP_KEY and self.equipEnglish
  if trigger and #text > #trigger + 1 and text:sub(1, #trigger + 1) == trigger .. " " then -- "Equip: Increases…"
    local k, a = self:core(text:sub(#trigger + 2))
    if k and self:has(k, "equip") then return k, { form = "equip", inner = a } end
  end
  return self:suffixForms(text)
end

-- ADR-038: label forms whose entry is followed by something kept as written, each only for the keys
-- granted it (LABELS). → key, args | nil
local AFTER_FORMS = {
  { "durationSuffix", "^(.-) (%[[%d:]+%])$" }, -- "Combat 3 [01:23]" (damagemetersessionwindow.lua:418–428)
  { "countLabel", "^(.-) (%(%d+%))$" }, -- "Multiple items (3)" (mailframe.lua:494)
  { "iconAfter", "^(.-) (|A[^|]*|a)$" }, -- "Revert |A…|a" (cooldownviewersettings.lua:1208–1210)
}
function Index:suffixForms(text)
  for _, f in ipairs(AFTER_FORMS) do
    local left, rest = text:match(f[2])
    if left then
      local k, a = self:core(left)
      if k and self:has(k, f[1]) then return k, { form = "affix", before = "", after = " " .. rest, inner = a } end
    end
  end
  local first, others = text:match("^([^\n]-)(\n.+)$") -- "Unread mail from:\n<name>…" (formattingutil.lua:181–187)
  if first then
    local k, a = self:core(first)
    if k and self:has(k, "headerLines") then return k, { form = "affix", before = "", after = others, inner = a } end
  end
  return nil
end

-- the key whose client English is exactly `en`: a plain word or a template's own text, as a dialog's
-- definition holds it (StaticPopupDialogs[which].text). → key | nil
function Index:keyOf(en)
  if type(en) ~= "string" or en == "" then return nil end
  return self.exact[en] or self.templateKeys[en]
end

-- a template's captures as the client formats them from its own arguments (string.format of each specifier
-- on its argument), so the Japanese carries exactly the text the English showed (a name verbatim). → args | nil (an
-- argument missing or not formattable)
function Index.formatArgs(_, key, en, ...) -- called as index:formatArgs; the index itself is not needed
  local argv = { ... }
  local args = { key = key }
  for _, p in ipairs((parse(en))) do
    if p.arg then
      local v = argv[p.arg]
      if v == nil then return nil end
      local ok, text = pcall(string.format, "%" .. p.flags .. p.conv, v)
      if not ok then return nil end
      args[p.arg] = text
    end
  end
  -- a quest's title shows in Japanese here too, as on the chat line the same template writes
  local kinds = argKinds(key)
  for i, kind in pairs(kinds or {}) do
    if kind == "questTitle" and type(args[i]) == "string" and type(UIStrings.questTitle) == "function" then
      args[i] = UIStrings.questTitle(args[i]) or args[i]
    end
  end
  return args
end

-- A list-shaped `only` as a set, built once per list table: the lists are module constants (filled at file load,
-- never changed after their first use), and matchOnly runs per tooltip line, every frame on the clock and the unit
-- frames.
local onlySets = setmetatable({}, { __mode = "k" })
local setNames = setmetatable({}, { __mode = "k" }) -- a key set → does it name a restricted / numbered key
-- Lines matchOnly found no key for, per `only` set: the per-frame tooltips repeat the same unmatched lines (a time,
-- a unit's name), which would each rescan every template. Pure given the text, the set and this index, so it is
-- kept on the index (a rebuilt index starts empty) and dropped whole when it grows past MISS_LIMIT.
local MISS_LIMIT = 512

-- `keys` as a set: a set as given, a list through onlySets. → set
local function asSet(keys)
  if keys[1] == nil then return keys end
  local set = onlySets[keys]
  if not set then
    set = {}
    for _, k in ipairs(keys) do set[k] = true end
    onlySets[keys] = set
  end
  return set
end

-- a Settings option's "<label>: <tooltip>" line (blizzard_settings.lua:441–457), each half wrapped in its
-- own colour. Only a RESTRICTED lookup reaches this form (the Options window walks its tooltip with `only` =
-- UI/SettingsKeys' list): both halves must be dictionary entries AND the label must be one of the caller's keys, so a
-- coloured "<word>: <word>" line on any other surface is never taken for an option line. → key, args | nil
function Index:optionTip(text, allow)
  local open, lab, close, tail = text:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r):(.*)$")
  if not open then return nil end
  local kl, al = self:core(lab)
  if not kl or not allow(kl) then return nil end
  if tail == "" then return kl, { form = "optionTip", open = open, close = close, inner = al } end
  local open2, tip, close2 = tail:match("^ (|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
  if not open2 then return nil end
  local kt, at = self:core(tip)
  if not kt then return nil end
  return kl, { form = "optionTip", open = open, close = close, inner = al,
    tip = { key = kt, args = at, open = open2, close = close2 } }
end

-- ADR-042: a slotted row's English ("%s waves at %s.") is never shipped, only its h1, so a live line is
-- matched by putting the slots back. `text` is the line as plain text (no links or colour codes); `names` the names
-- it may hold (the sender, the player, the target). First every whole-word occurrence of a known name is a slot
-- (with a chat flag ("<Away>") right before it); then, when that is not a row, also one run of 1..SLOT_WORDS words
-- (a name the caller could not know: a third player's target), trailing punctuation and "'s" left out. A skeleton
-- whose fingerprint is a slotted row's h1 is that row. → key, { [slot] = { first, last } } in slot order | nil
local SLOT_WORDS = 4
UIStrings.SLOT_WORDS = SLOT_WORDS

local function spanText(text, spans)
  local out, at = {}, 1
  for _, sp in ipairs(spans) do
    out[#out + 1] = text:sub(at, sp[1] - 1)
    out[#out + 1] = "%s"
    at = sp[2] + 1
  end
  out[#out + 1] = text:sub(at)
  return table.concat(out)
end

local function wordChar(ch)
  return ch ~= "" and ch:find("[%w\128-\255']") ~= nil
end

function Index:matchSlots(text, names)
  if type(text) ~= "string" or text == "" or next(self.bySlots) == nil then return nil end
  local known = {}
  for _, name in ipairs(names or {}) do
    if type(name) == "string" and name ~= "" then
      local from = 1
      while true do
        local a, b = text:find(name, from, true)
        if not a then break end
        local after = text:sub(b + 1, b + 1)
        if not wordChar(text:sub(a - 1, a - 1)) and (not wordChar(after) or text:sub(b + 1, b + 2) == "'s") then
          local flagStart = a > 1 and text:sub(1, a - 1):match("()<[^<>]*>$") or nil
          known[#known + 1] = { flagStart or a, b }
        end
        from = b + 1
      end
    end
  end
  table.sort(known, function(x, y) return x[1] < y[1] end)
  local clean = {}
  for _, sp in ipairs(known) do -- overlapping occurrences (one name inside another): the first wins
    if #clean == 0 or sp[1] > clean[#clean][2] then clean[#clean + 1] = sp end
  end
  local function try(spans)
    local key = self.bySlots[self.hash(spanText(text, spans))]
    if key then return key, spans end
  end
  do -- the known names as slots (none: the line itself, "You wave.")
    local key, spans = try(clean)
    if key then return key, spans end
  end
  -- one more slot: every run of 1..SLOT_WORDS whole words that overlaps no known name
  local starts = {}
  for i = 1, #text do
    if text:sub(i, i) ~= " " and (i == 1 or text:sub(i - 1, i - 1) == " ") then starts[#starts + 1] = i end
  end
  for si, a in ipairs(starts) do
    for n = 1, SLOT_WORDS do
      local nextStart = starts[si + n]
      if n > 1 and not starts[si + n - 1] then break end
      local b = (nextStart and nextStart - 2) or #text
      local seg = text:sub(a, b)
      seg = seg:gsub("%s+$", ""):gsub("[%.!?,:;]+$", ""):gsub("'s$", "")
      if seg ~= "" then
        local e = a + #seg - 1
        local free = true
        for _, sp in ipairs(clean) do
          if a <= sp[2] and e >= sp[1] then free = false end
        end
        if free then
          local spans = { { a, e } }
          for _, sp in ipairs(clean) do spans[#spans + 1] = sp end
          table.sort(spans, function(x, y) return x[1] < y[1] end)
          local key, got = try(spans)
          if key then return key, got end
        end
      end
      if not nextStart then break end
    end
  end
  return nil
end

-- ADR-042: a numbered row's line: every digit run of the live text (colour codes and textures left out
-- first, as the hash does) becomes `#`; a skeleton whose fingerprint is a numbered row's h1 is that row, and its
-- Japanese takes the numbers in the order the line has them. → key, { [k] = number text } | nil
function Index:matchNumbers(text)
  if type(text) ~= "string" or text == "" or next(self.byNumbers) == nil then return nil end
  local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", "")
  local numbers = {}
  local skeleton = plain:gsub("%d+", function(d)
    numbers[#numbers + 1] = d
    return "#"
  end)
  local key = self.byNumbers[self.hash(skeleton)]
  if key then return key, numbers end
  return nil
end

-- A templated row's line whose every argument is a number ("You gain 25 Rank Points."): each digit run of the
-- live text (colour codes and textures left out first, as the hash does) is put back as `%d`, a literal "%" as
-- "%%"; a result whose fingerprint is a templated row's h1 is that row's English, and the numbers are its arguments
-- in order. A template with a text argument, a plural group or another conversion never fingerprints this way;
-- those are matched against the client's own template (index:matchTemplate). → key, args | nil
function Index:matchCounted(text)
  if type(text) ~= "string" or text == "" or next(self.byTemplate) == nil then return nil end
  local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", "")
  if not plain:find("%d") then return nil end
  local args = {}
  local template = plain:gsub("%%", "%%%%"):gsub("%d+", function(d)
    args[#args + 1] = d
    return "%d"
  end)
  local key = self.byTemplate[self.hash(template)]
  if not key then return nil end
  args.key = key
  return key, args
end

-- A server notice among `keys`: a plain row ("[SERVER] Shutdown cancelled") by its whole fingerprint, else a row whose
-- template ends in one text argument ("[SERVER] Shutdown in %s"), when the client hands the caller no template: each
-- prefix of the line that ends at one of its first TAIL_SPACES spaces, followed by `%s`, is fingerprinted, and one
-- that is a templated row's h1 among `keys` is that row, the rest of the line its argument. The English is never
-- shipped. → key, args | nil
UIStrings.TAIL_SPACES = 8 -- the longest shipped prefix has 5 (test_ui_strings checks every row against this)
function Index:matchTail(text, keys)
  if type(text) ~= "string" or text == "" or type(keys) ~= "table" then return nil end
  local set = asSet(keys)
  if next(set) == nil then return nil end
  for _, k in ipairs(self:restrictedKeys(text)) do
    if set[k] then return k, nil end
  end
  if next(self.byTemplate) == nil then return nil end
  local spaces, pos = 0, 0
  while spaces < UIStrings.TAIL_SPACES do
    pos = text:find(" ", pos + 1, true)
    if not pos or pos >= #text then return nil end
    spaces = spaces + 1
    local template = (text:sub(1, pos):gsub("%%", "%%%%")) .. "%s"
    local key = self.byTemplate[self.hash(template)]
    if key and set[key] then return key, { text:sub(pos + 1), key = key } end
  end
  return nil
end

-- A live line against a template English the client itself hands the caller (a talent condition's tooltipFormat):
-- the English is never shipped, only compared by its fingerprint, as a global string is. When its fingerprint is
-- one of `keys`' templated rows, the line is matched against it (its plural groups in every form, `%s` as text);
-- when it is one of `keys`' plain restricted rows, the line must be that English. Either may be wrapped in one
-- colour (an unmet condition is shown red), kept around the Japanese. → key, args | nil
local compiledTemplates, compiledCount = {}, 0
function Index:matchTemplate(text, en, keys)
  if type(text) ~= "string" or text == "" or type(en) ~= "string" or en == "" or type(keys) ~= "table" then
    return nil
  end
  local set = asSet(keys)
  local function allowed(key)
    for _, k in ipairs(self.synonyms[key] or { key }) do
      if set[k] then return true end
    end
    return false
  end
  local open, inner, close = text:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
  local body = inner or text
  local h = self.hash(en)
  local key, args = self.byTemplate[h], nil
  if key and allowed(key) then
    local forms = compiledTemplates[en]
    if not forms then
      forms = {}
      for _, form in ipairs(pluralForms(en) or {}) do
        local pattern, order = compile(form, key)
        forms[#forms + 1] = { pattern = pattern, order = order }
      end
      if compiledCount >= MEMO_LIMIT then compiledTemplates, compiledCount = {}, 0 end
      compiledTemplates[en], compiledCount = forms, compiledCount + 1
    end
    for _, f in ipairs(forms) do
      local caps = { body:match(f.pattern) }
      if caps[1] ~= nil then
        args = { key = key }
        for i, argIndex in ipairs(f.order) do args[argIndex] = caps[i] end
        break
      end
    end
    if not args then return nil end
  else
    key = nil
    if body == en then
      for _, k in ipairs(self:restrictedKeys(en)) do
        if set[k] then key = k; break end
      end
    end
    if not key then return nil end
  end
  if open then return key, { form = "wrapped", open = open, close = close, inner = args } end
  return key, args
end

-- match, restricted to a set of keys ({ [key] = true } or a list): a widget that may also hold a name.
function Index:matchOnly(text, keys)
  local set = asSet(keys)
  self.onlyMisses = self.onlyMisses or setmetatable({}, { __mode = "k" })
  local misses = self.onlyMisses[set]
  if misses and misses.lines[text] then return nil end
  local function allowed(key)
    for _, k in ipairs(self.synonyms[key] or { key }) do
      if set[k] then return true end
    end
    return false
  end
  for _, k in ipairs(self.own[text] or {}) do -- a key that owns its Japanese, named by this widget
    if set[k] then return k, nil end
  end
  local open, inner, close = text:match("^(|c%x%x%x%x%x%x%x%x)(.-)(%s*|r%s*)$") -- an owned word, colour-wrapped
  for _, k in ipairs(open and self.own[inner] or {}) do
    if set[k] and hasForm(k, "wrapped") then return k, { form = "wrapped", open = open, close = close } end
  end
  local names = setNames[set] -- only a set naming a family key pays for the family lookups
  if not names then
    names = { restricted = false, numbered = false, templated = false }
    for k in pairs(set) do
      if type(k) == "string" then
        if UIStrings.isRestrictedKey(k) then names.restricted = true end
        if UIStrings.isNumberedKey(k) then names.numbered = true end
        if UIStrings.isTemplatedKey(k) then names.templated = true end
      end
    end
    setNames[set] = names
  end
  if names.restricted then
    for _, fk in ipairs(self:restrictedKeys(text)) do -- a restricted family's row, when the widget names it
      if set[fk] then return fk, nil end
    end
  end
  if names.templated then
    local tk, targs = self:matchCounted(text) -- a templated row whose arguments are all numbers
    if tk and allowed(tk) then return tk, targs end
  end
  if names.numbered then
    local nk, numbers = self:matchNumbers(text) -- a numbered row (a widget's line with live numbers)
    if nk and allowed(nk) then return nk, numbers end
  end
  local key, args = self:match(text)
  if key and allowed(key) then return key, args end
  -- the voice announce parts only where a caller asks for the key: three sentences that are
  -- each an entry ("Party Sync is already active. … 3 votes needed to abandon the instance.") are no voice line.
  -- Before the key's own "%1$s %2$s %3$s" template, which would take the line verbatim.
  if self.voiceKey and allowed(self.voiceKey) and text:find("%. %d") then
    args = self:voiceParts(text)
    if args then return self.voiceKey, args end
  end
  -- the first template to match can be a longer one outside the set ("Level 60 Wind Serpent" is
  -- COMMUNITY_MEMBER_CHARACTER_INFO_FORMAT "Level %d %s %s" before UNIT_TYPE_LEVEL_TEMPLATE "Level %d %s"), which
  -- would shadow the allowed key. Retry the templates of the allowed keys only.
  key, args = self:core(text, allowed)
  if key and allowed(key) then return key, args end
  -- a key-only template granted `wrapped` ("|cff808080Macros (Macro)|r", clickbindings.lua
  -- :199–211; "%s Specific" in the layout menus); the unrestricted match above never sees it
  open, inner, close = text:match("^(|c%x%x%x%x%x%x%x%x)(.-)(%s*|r%s*)$")
  if open then
    key, args = self:core(inner, allowed)
    if key and allowed(key) and self:has(key, "wrapped") then
      return key, { form = "wrapped", open = open, close = close, inner = args }
    end
  end
  key, args = self:optionTip(text, allowed) -- the Settings option line, restricted lookups only
  if key then return key, args end
  if not misses or misses.count >= MISS_LIMIT then
    misses = { count = 0, lines = {} }
    self.onlyMisses[set] = misses
  end
  misses.lines[text] = true
  misses.count = misses.count + 1
  return nil
end

-- A live duration ("30 sec", "1 hr 30 min") in Japanese when it is one or two DURATIONS entries, else nil.
-- `spellOnly`: only the SPELL_DURATIONS entries, the forms a spell's `$d` prints (`Align`'s renderer).
function Index:duration(value, spellOnly)
  local set = spellOnly and self.spellDurations or self.durations
  local function one(v)
    local k, a = self:core(v)
    if not k then return nil end
    for _, syn in ipairs(self.synonyms[k] or { k }) do
      if set[syn] then return self:fill(self.rows[k][1], a) end
    end
    return nil
  end
  local whole = one(value)
  if whole then return whole end
  local a, b = value:match("^(.-[%a;]) (%d.*)$") -- ";" ends a raw plural group ("5 |4Hr:Hrs; 30 |4Min:Mins;")
  if a then
    local ja, jb = one(a), one(b)
    if ja and jb then return ja .. jb end
  end
  return nil
end

-- A captured `word` argument that is itself an exact entry's English → that entry's Japanese; anything else as
-- captured. Only `word` arguments are ever passed here (a name in a `text` argument is never translated).
function Index:nested(value)
  local key = self:exactKey(value)
  if key then return self.rows[key][1] end
  return value
end

function Index:fill(ja, args)
  if type(args) ~= "table" then return ja end
  -- text kept verbatim around the Japanese ("3/10 " before an objective, " (完了)" after it); `inner` is the
  -- template's own captures, if any
  if args.form == "affix" then
    local body = ja
    if args.inner then body = self:fill(ja, args.inner) end
    if body == nil then return nil end
    return (args.before or "") .. body .. (args.after or "")
  end
  if args.form == "optionTip" then -- "<label>:" or "<label>: <tooltip>", each in its own colour
    local label = args.inner and self:fill(ja, args.inner) or ja
    if label == nil then return nil end
    local out = args.open .. label .. args.close .. ":"
    if not args.tip then return out end
    local tip = self:fill(self.rows[args.tip.key][1], args.tip.args)
    if tip == nil then return nil end
    return out .. " " .. args.tip.open .. tip .. args.tip.close
  end
  if args.form == "prefix" then return ja .. args.rest end
  if args.form == "colon" then return ja .. ": " .. args.rest end
  if args.form == "number" then return ja .. " " .. args.rest end
  if args.form == "bareColon" then return ja .. ":" end
  if args.form == "colonPrefix" then
    return ja .. " " .. (args.restKey and self.rows[args.restKey][1] or args.rest)
  end
  if args.form == "seq" then -- parts in order: text kept as written, { key, args[, open, close] } filled
    local out = {}
    for i, part in ipairs(args.parts) do
      if type(part) == "table" then
        out[i] = self:fillArg({ entry = part.key, args = part.args, open = part.open, close = part.close })
        if out[i] == nil then return nil end
      else
        out[i] = part
      end
    end
    return table.concat(out)
  end
  if args.form == "list" then
    local parts = {}
    for i, item in ipairs(args.items) do
      if item.key then
        parts[i] = self:fill(self.rows[item.key][1], item.args)
        if parts[i] == nil then return nil end -- fail closed: never an unfilled template
      else
        parts[i] = item.text
      end
    end
    return ja .. " " .. table.concat(parts, ", ")
  end
  if args.form == "paragraphs" then
    local out = {}
    for i, part in ipairs(args.parts) do
      out[i] = self:fill(self.rows[part.key][1], part.args)
      if out[i] == nil then return nil end
      if part.open then out[i] = part.open .. out[i] .. part.close end
    end
    return table.concat(out, "\n\n")
  end
  if args.form == "joined" then
    local body = ja
    if args.inner then body = self:fill(ja, args.inner) end
    local tail = args.rest
    if args.restKey then tail = self:fill(self.rows[args.restKey][1], args.restArgs) end
    if body == nil or tail == nil then return nil end
    return body .. "  " .. tail
  end
  if args.form == "wrapped" and args.duration then
    local body = self:duration(args.duration)
    return body and (args.open .. body .. args.close) or nil
  end
  if args.form == "wrapped" or args.form == "binding" or args.form == "equip" then
    local body = ja
    if args.inner then body = self:fill(ja, args.inner) end
    if body == nil then return nil end
    if args.form == "wrapped" then return args.open .. body .. args.close end
    if args.form == "binding" then return body .. args.rest end
    return self.rows[EQUIP_KEY][1] .. " " .. body
  end
  local out = {}
  for _, p in ipairs(parse(ja)) do
    if p.lit then
      out[#out + 1] = p.lit
    else
      local v = args[p.arg]
      if v == nil then return nil end -- the Japanese asks for an argument the line did not have: fail closed
      local kinds = args.key and argKinds(args.key)
      local kind = kinds and kinds[p.arg]
      if kind == "word" or kind == "words" or kind == "standing" then
        v = self:nested(v)
      elseif (kind == "entry" or kind == "entryOrText" or kind == "entryList" or UIStrings.FAMILY_KINDS[kind]
          or UIStrings.FAMILY_LIST_KINDS[kind]) and type(v) == "table" then
        v = self:fillArg(v)
        if v == nil then return nil end
      elseif kind == "time" then
        v = self:duration(v) or v
      end
      out[#out + 1] = v
    end
  end
  return table.concat(out)
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

function UIStrings.build(deps)
  local rows = deps.rows or {}
  local index = setmetatable({ rows = rows, exact = {}, templates = {}, prefixes = {}, byHash = {}, hashCount = 0,
    memo = {}, memoCount = 0, durations = {}, spellDurations = {}, synonyms = {}, own = {}, templateKeys = {},
    bySlots = {}, byNumbers = {}, byRestricted = {}, byTemplate = {},
    hash = deps.hash,
    counts = { shipped = 0, indexed = 0, hashed = 0, mismatched = 0, ambiguous = 0, unresolved = 0, unsupported = 0,
      owned = 0 },
    problems = { mismatched = {}, ambiguous = {}, unresolved = {}, unsupported = {} } }, Index)
  local c, byText, templateByText, byH1, bySlots, byNumbers, byRestricted = index.counts, {}, {}, {}, {}, {}, {}
  local byTemplate = {}
  for _, key in ipairs(sortedKeys(rows)) do
    local row = rows[key]
    c.shipped = c.shipped + 1
    local en = deps.english(key)
    local _, jaArgs = parse(row[1])
    -- Only an item subclass has no client string by design; a global string missing on this client is `unresolved`
    -- (a drift /wfj debug ui must show), never silently fingerprinted.
    if (type(en) ~= "string" or en == "") and UIStrings.isNumberedKey(key) and type(row[2]) == "number" then
      local seen = byNumbers[row[2]] -- found by its skeleton (index:matchNumbers)
      if not seen then
        byNumbers[row[2]] = { key = key, ja = row[1], keys = { key } }
      else
        seen.keys[#seen.keys + 1] = key
        if seen.ja ~= row[1] then seen.conflict = true end
      end
    elseif (type(en) ~= "string" or en == "") and UIStrings.isSlottedKey(key) and type(row[2]) == "number" then
      local seen = bySlots[row[2]] -- matched by putting its slots back (index:matchSlots)
      if not seen then
        bySlots[row[2]] = { key = key, ja = row[1], keys = { key } }
      else
        seen.keys[#seen.keys + 1] = key
        if seen.ja ~= row[1] then seen.conflict = true end
      end
    elseif (type(en) ~= "string" or en == "") and UIStrings.isTemplatedKey(key)
        and jaArgs > 0 and type(row[2]) == "number" then
      local seen = byTemplate[row[2]] -- a format string: matched by index:matchCounted / index:matchTemplate
      if not seen then
        byTemplate[row[2]] = { key = key, ja = row[1], keys = { key } }
      else
        seen.keys[#seen.keys + 1] = key
        if seen.ja ~= row[1] then seen.conflict = true end
      end
    elseif (type(en) ~= "string" or en == "") and UIStrings.isRestrictedKey(key)
        and jaArgs == 0 and type(row[2]) == "number" then
      -- a restricted family's row: a vocabulary of its own, found only where a widget names the family
      local family = key:match("^(%a+):")
      local byFamily = byRestricted[row[2]] or {}
      byRestricted[row[2]] = byFamily
      local seen = byFamily[family]
      if not seen then
        byFamily[family] = { key = key, ja = row[1], keys = { key } }
      else
        seen.keys[#seen.keys + 1] = key
        if seen.ja ~= row[1] then seen.conflict = true end
      end
    elseif (type(en) ~= "string" or en == "") and UIStrings.isFingerprintKey(key)
        and jaArgs == 0 and type(row[2]) == "number" then
      local seen = byH1[row[2]] -- no English to read: match the live line by its fingerprint
      if not seen then
        byH1[row[2]] = { key = key, ja = row[1], keys = { key } }
      else
        seen.keys[#seen.keys + 1] = key
        if seen.ja ~= row[1] then seen.conflict = true end
      end
    elseif type(en) ~= "string" or en == "" then
      c.unresolved = c.unresolved + 1
      index.problems.unresolved[#index.problems.unresolved + 1] = key
    elseif deps.hash(en) ~= row[2] then
      c.mismatched = c.mismatched + 1
      index.problems.mismatched[#index.problems.mismatched + 1] = key
    elseif UIStrings.OWN[key] then
      local _, argc = parse(en)
      if argc > 0 or en:find("%%", 1, true) then
        c.unsupported = c.unsupported + 1
        index.problems.unsupported[#index.problems.unsupported + 1] = key
      else
        local list = index.own[en] or {}
        list[#list + 1] = key
        index.own[en] = list
        c.owned = c.owned + 1
      end
    else
      local forms = pluralForms(en)
      if not forms then
        c.unsupported = c.unsupported + 1
        index.problems.unsupported[#index.problems.unsupported + 1] = key
      else
        local _, argc = parse(en)
        -- an English holding "%%" is a format string even with no specifier: the client prints it through
        -- format() ("100%" in the crit hovers, camelot paperdollframestats.lua:477, 539–545), so it is matched as a
        -- template (its "%%" a literal "%") and its Japanese filled the same way
        local bucket = (argc == 0 and not en:find("%%", 1, true)) and byText or templateByText
        for _, form in ipairs(forms) do
          local seen = bucket[form]
          if not seen then
            bucket[form] = { key = key, ja = row[1], keys = { key } }
          elseif seen.keys[#seen.keys] ~= key then
            seen.keys[#seen.keys + 1] = key
            if seen.ja ~= row[1] then seen.conflict = true end
          end
        end
        if key == EQUIP_KEY then index.equipEnglish = en end
      end
    end
  end
  -- A key is counted once however many plural forms it has: indexed when every form is admitted, ambiguous when any
  -- form conflicts (then none of its forms is indexed).
  local function admit(bucket, add)
    local conflicted, admitted = {}, {}
    for _, en in ipairs(sortedKeys(bucket)) do
      local e = bucket[en]
      if e.conflict then for _, k in ipairs(e.keys) do conflicted[k] = true end end
    end
    for _, en in ipairs(sortedKeys(bucket)) do
      local e = bucket[en]
      local clean = true
      for _, k in ipairs(e.keys) do if conflicted[k] then clean = false end end
      if clean then
        add(en, e.key)
        for _, k in ipairs(e.keys) do admitted[k] = true end
        if #e.keys > 1 then index.synonyms[e.key] = e.keys end
      end
    end
    for _, k in ipairs(sortedKeys(conflicted)) do
      c.ambiguous = c.ambiguous + 1
      index.problems.ambiguous[#index.problems.ambiguous + 1] = k
    end
    for _ in pairs(admitted) do c.indexed = c.indexed + 1 end
  end
  admit(byText, function(en, key)
    index.exact[en] = key
    if en:sub(-2) == ": " then index.prefixes[#index.prefixes + 1] = { en = en, key = key } end -- "Reagents: "
  end)
  -- Fingerprint entries: one per h1; an h1 an English entry already answers with other Japanese is ambiguous.
  local englishJa, englishKey = {}, {}
  for en, key in pairs(index.exact) do englishJa[deps.hash(en)], englishKey[deps.hash(en)] = rows[key][1], key end
  -- `extra` keys answered by `key` (same English, same Japanese) become its synonyms, so matchOnly finds them
  local function addSynonyms(key, extra)
    local list = index.synonyms[key] or { key }
    for _, k in ipairs(extra) do
      local dup = false
      for _, have in ipairs(list) do if have == k then dup = true end end
      if not dup then list[#list + 1] = k end
    end
    if #list > 1 then index.synonyms[key] = list end
  end
  local h1s = {}
  for h in pairs(byH1) do h1s[#h1s + 1] = h end
  table.sort(h1s)
  for _, h in ipairs(h1s) do
    local e = byH1[h]
    if e.conflict or (englishJa[h] ~= nil and englishJa[h] ~= e.ja) then
      c.ambiguous = c.ambiguous + #e.keys
      for _, k in ipairs(e.keys) do index.problems.ambiguous[#index.problems.ambiguous + 1] = k end
    elseif englishJa[h] ~= nil then
      -- the client's own English already answers this line with the same Japanese ("Epic",
      -- ITEM_QUALITY4_DESC): the fingerprint keys are that key's synonyms
      c.hashed = c.hashed + #e.keys
      index.byHash[h] = englishKey[h]
      index.hashCount = index.hashCount + 1
      addSynonyms(englishKey[h], e.keys)
    else
      c.hashed = c.hashed + #e.keys
      index.byHash[h] = e.key
      index.hashCount = index.hashCount + 1
      addSynonyms(e.key, e.keys)
    end
  end
  -- the restricted families' rows, per fingerprint the keys of every family that has one (a conflict only
  -- within one family: two of its keys with one English and different Japanese)
  for h, byFamily in pairs(byRestricted) do
    local list = {}
    for _, e in pairs(byFamily) do
      if e.conflict then
        c.ambiguous = c.ambiguous + #e.keys
        for _, k in ipairs(e.keys) do index.problems.ambiguous[#index.problems.ambiguous + 1] = k end
      else
        c.hashed = c.hashed + #e.keys
        for _, k in ipairs(e.keys) do list[#list + 1] = k end
      end
    end
    table.sort(list)
    if #list > 0 then index.byRestricted[h] = list end
  end
  for _, pair in ipairs({ { bySlots, index.bySlots }, { byNumbers, index.byNumbers },
    { byTemplate, index.byTemplate } }) do
    local from, into = pair[1], pair[2]
    local keys = {}
    for h in pairs(from) do keys[#keys + 1] = h end
    table.sort(keys)
    for _, h in ipairs(keys) do
      local e = from[h]
      if e.conflict then
        c.ambiguous = c.ambiguous + #e.keys
        for _, k in ipairs(e.keys) do index.problems.ambiguous[#index.problems.ambiguous + 1] = k end
      else
        c.hashed = c.hashed + #e.keys
        into[h] = e.key
        if #e.keys > 1 then index.synonyms[e.key] = e.keys end
      end
    end
  end
  admit(templateByText, function(en, key)
    index.templateKeys[en] = key -- a dialog names its template by its English (Index:keyOf)
    local pattern, order, literal, word = compile(en, key)
    index.templates[#index.templates + 1] = { key = key, pattern = pattern, order = order, literal = literal,
      word = word, only = keyOnly(key) }
  end)
  table.sort(index.templates, function(a, b)
    if a.literal ~= b.literal then return a.literal > b.literal end
    return a.key < b.key
  end)
  for _, k in ipairs(UIStrings.DURATIONS) do index.durations[k] = true end
  -- the voiceParts key, when its English is indexed on this client
  for _, t in ipairs(index.templates) do
    if hasForm(t.key, "voiceParts") then index.voiceKey = t.key end
  end
  for _, k in ipairs(UIStrings.SPELL_DURATIONS) do index.spellDurations[k] = true end
  for _, list in pairs(index.problems) do table.sort(list) end
  return index
end
