-- Core/UIStringKeys.lua: which UI string keys take which arguments, which are matched only by key, and the other
-- per-key lists the UI string index reads (Core/UIStrings.lua). Adding or adjusting a key happens here; how a line is
-- matched and filled happens there. Loaded before Core/UIStrings.lua.
local _, WFJ = ...
local UIStrings = WFJ.UIStrings or {}
WFJ.UIStrings = UIStrings

-- What a `%s` may capture. By default a `%s` is a NUMBER ("%s Armor" must not
-- take "Blackened Defias" from a set-piece line). The keys below take other text, per argument index:
--   word  ONE word that must itself be a dictionary word (a school, a reputation standing), shown in Japanese; a
--         line whose word is not an entry is not this template ("+3 Fire Spell Damage", "+5 Spell Damage": a
--         random-suffix spell-power line never becomes a weapon-damage line);
--   words one or more words (a bag type: "Soul Bag"), shown in Japanese when it is an entry, verbatim otherwise;
--   text  shown verbatim (a name, a profession, a class list), never translated, and never containing a period (so a
--         prose sentence is never taken for a template argument);
--   skill what follows "Requires" when it is a skill or an equipment list ("Herbalism", "Bows, Crossbows, Guns"):
--         letters, spaces, apostrophes, hyphens and commas only; never "Level 40" or "Engineering (225)"
--         (`ITEM_REQ_SKILL`, which shares its English with SPELL_EQUIPPED_ITEM); shown verbatim;
--   time  a live duration ("30 sec", "1 hr 30 min"): shown in Japanese when it is one or two duration entries
--         (UIStrings.DURATIONS), verbatim otherwise;
--   verbatim  any text, periods included, shown exactly as captured (a gossip option's server text after
--         its prepend); only for templates in UIStrings.ONLY, which are matched only where a widget asks by key;
--   entry text that must itself be a dictionary entry or template ("(Rank 2)", "(Buyout)"): shown as that entry's
--         filled Japanese; a line whose text is not an entry is not this template.
--   percent  a percentage with an optional sign ("+5.00%", "-0.40%", "40%"), shown verbatim.
-- In the windows, every name-carrying template is `text` (race / class in "Level %d %s %s", a quest title, a talent
-- tree, a skill, an item stack, a pet family).
UIStrings.ARGS = {
  ITEM_RESIST_SINGLE = { [3] = "word" }, DAMAGE_TEMPLATE_WITH_SCHOOL = { [3] = "word" },
  PLUS_DAMAGE_TEMPLATE_WITH_SCHOOL = { [3] = "word" }, SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL = { [2] = "word" },
  PLUS_SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL = { [2] = "word" }, AMMO_SCHOOL_DAMAGE_TEMPLATE = { [2] = "word" },
  PLUS_AMMO_SCHOOL_DAMAGE_TEMPLATE = { [2] = "word" }, CONTAINER_SLOTS = { [2] = "words" },
  ITEM_REQ_REPUTATION = { [1] = "text", [2] = "word" },
  ITEM_REQ_SKILL = { [1] = "skill" }, ITEM_MIN_SKILL = { [1] = "text" },
  SPELL_EQUIPPED_ITEM = { [1] = "text" }, SPELL_EQUIPPED_ITEM_NOSPACE = { [1] = "text" },
  SPELL_REQUIRED_FORM = { [1] = "text" }, SPELL_REQUIRED_FORM_NOSPACE = { [1] = "text" },
  ITEM_CLASSES_ALLOWED = { [1] = "text" }, ITEM_RACES_ALLOWED = { [1] = "text" }, ITEM_SPELL_EFFECT = { [1] = "text" },
  ITEM_WRITTEN_BY = { [1] = "text" }, ITEM_LIMIT_CATEGORY = { [1] = "text" },
  ITEM_LIMIT_CATEGORY_MULTIPLE = { [1] = "text" }, TOOLTIP_TALENT_TIER_POINTS = { [2] = "text" },
  ITEM_COOLDOWN_TIME = { [1] = "time" }, ITEM_COOLDOWN_TOTAL = { [1] = "time" },
  -- the owner line under a pet, minion or guardian: the owner's name, as written
  UNITNAME_SUMMON_TITLE1 = { [1] = "text" }, UNITNAME_SUMMON_TITLE2 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE3 = { [1] = "text" }, UNITNAME_SUMMON_TITLE4 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE5 = { [1] = "text" }, UNITNAME_SUMMON_TITLE6 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE7 = { [1] = "text" }, UNITNAME_SUMMON_TITLE8 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE9 = { [1] = "text" }, UNITNAME_SUMMON_TITLE10 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE11 = { [1] = "text" }, UNITNAME_SUMMON_TITLE12 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE13 = { [1] = "text" }, UNITNAME_SUMMON_TITLE14 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE15 = { [1] = "text" }, UNITNAME_SUMMON_TITLE16 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE17 = { [1] = "text" }, UNITNAME_SUMMON_TITLE18 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE19 = { [1] = "text" }, UNITNAME_SUMMON_TITLE20 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE21 = { [1] = "text" }, UNITNAME_SUMMON_TITLE22 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE23 = { [1] = "text" }, UNITNAME_SUMMON_TITLE24 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE25 = { [1] = "text" }, UNITNAME_SUMMON_TITLE26 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE28 = { [1] = "text" }, UNITNAME_SUMMON_TITLE29 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE31 = { [1] = "text" }, UNITNAME_SUMMON_TITLE32 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE33 = { [1] = "text" }, UNITNAME_SUMMON_TITLE34 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE35 = { [1] = "text" }, UNITNAME_SUMMON_TITLE36 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE37 = { [1] = "text" }, UNITNAME_SUMMON_TITLE38 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE39 = { [1] = "text" }, UNITNAME_SUMMON_TITLE40 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE41 = { [1] = "text" }, UNITNAME_SUMMON_TITLE42 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE43 = { [1] = "text" }, UNITNAME_SUMMON_TITLE44 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE45 = { [1] = "text" }, UNITNAME_SUMMON_TITLE46 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE47 = { [1] = "text" }, UNITNAME_SUMMON_TITLE48 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE49 = { [1] = "text" }, UNITNAME_SUMMON_TITLE50 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE51 = { [1] = "text" }, UNITNAME_SUMMON_TITLE53 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE54 = { [1] = "text" }, UNITNAME_SUMMON_TITLE55 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE56 = { [1] = "text" }, UNITNAME_SUMMON_TITLE57 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE58 = { [1] = "text" }, UNITNAME_SUMMON_TITLE59 = { [1] = "text" },
  UNITNAME_SUMMON_TITLE60 = { [1] = "text" }, UNITNAME_SUMMON_TITLE61 = { [1] = "text" },
  UNITNAME_TITLE_CHARM = { [1] = "text" }, UNITNAME_TITLE_COMPANION = { [1] = "text" },
  UNITNAME_TITLE_CREATION = { [1] = "text" }, UNITNAME_TITLE_GUARDIAN = { [1] = "text" },
  UNITNAME_TITLE_MINION = { [1] = "text" }, UNITNAME_TITLE_OPPONENT = { [1] = "text" },
  UNITNAME_TITLE_PET = { [1] = "text" }, UNITNAME_TITLE_SQUIRE = { [1] = "text" },
  -- the loot-trade window line's time text, the socket requirement's skill name, a skull-level creature type
  BIND_TRADE_TIME_REMAINING = { [1] = "text" }, SOCKET_ITEM_MIN_SKILL = { [1] = "text" },
  SOCKET_ITEM_REQ_SKILL = { [1] = "text" }, UNIT_TYPE_LETHAL_LEVEL_TEMPLATE = { [1] = "creatureType" },
  -- the always-visible windows
  -- Forever's English is "Level %s |c%s%s %s|r" (level, colour, spec, class); each is a verbatim capture
  PLAYER_LEVEL = { [1] = "text", [2] = "text", [3] = "text", [4] = "text" },
  -- shares "Level %d %s" with UNIT_TYPE_LEVEL_TEMPLATE, so the same kind; a guild member's class is never a
  -- CreatureType row and stays as written (UI/Communities)
  FRIENDS_LEVEL_TEMPLATE = { [2] = "creatureType" },
  TRIVIAL_QUEST_DISPLAY = { [1] = "text" }, IGNORED_QUEST_DISPLAY = { [1] = "text" },
  MASTERY_POINTS_SPENT = { [1] = "text", [2] = "text" }, TRAINER_REQ_SKILL_RANK = { [1] = "skill" },
  TRAINER_REQ_SKILL_RANK_RED = { [1] = "skill" }, AUCTION_MAIL_ITEM_STACK = { [1] = "text" },
  LEARN_SKILL_TEMPLATE = { [1] = "text" }, UNIT_LEVEL_TEMPLATE = {},
  UNSPENT_TALENT_POINTS = { [1] = "text" }, -- the count arrives colour-wrapped (TalentFrameBase.lua:304)
  RESISTANCE_TOOLTIP_SUBTEXT = { [1] = "words", [3] = "words" }, PET_DIET_TEMPLATE = { [1] = "text" },
  PARENS_TEMPLATE = { [1] = "entry" }, AUCTION_INVOICE_FUNDS_DELAY = { [1] = "text" },
  MAIL_COD_ERROR_COLORBLIND = { [2] = "text" }, EXHAUST_TOOLTIP1 = { [1] = "text" },
  MAINMENUBAR_PROTOCOLS_LABEL = { [1] = "text", [2] = "text" },
  MAINMENUBAR_COMMUNICATION_PROTOCOL_LABEL = { [1] = "text", [2] = "text" },
  -- a CPU share is a percentage ("0.04%"), which a `text` capture refuses for its period
  ADDON_LIST_PERFORMANCE_AVERAGE_CPU = { [1] = "percent" }, ADDON_LIST_PERFORMANCE_PEAK_CPU = { [1] = "percent" },
  BNET_LAST_ONLINE_TIME = { [1] = "time" }, FRIENDS_LIST_STATUS_TOOLTIP = { [1] = "word" },
  -- the talent tooltip's rank arrives colour-wrapped (blizzard_talentbuttonspend.lua:84–92); a
  -- replacing spell, a player and an item are names; the weapon-skill pane's values are FormatSignedPercent /
  -- FormatPercent output ("+5.00%", "40%": camelot/skillsframe.lua:86–101, 297–315)
  TALENT_BUTTON_TOOLTIP_RANK_FORMAT = { [1] = "text" }, TALENT_BUTTON_TOOLTIP_RANK_NO_MAX_FORMAT = { [1] = "text" },
  TALENT_BUTTON_TOOLTIP_REPLACED_BY_FORMAT = { [1] = "text" }, TALENT_FRAME_INCREASED_RANKS_TEXT = { [2] = "text" },
  TALENTS_INSPECT_FORMAT = { [1] = "text" },
  -- the chat header's whisper target, a corpse's name, the Edit Mode "new layout" atlas, the
  -- interact key's binding, a unit tooltip's level ("??" too) / race / class / creature type: all kept as shown;
  -- the loot opt-out's Yes / No and a settings category's names are dictionary words
  CHAT_WHISPER_SEND = { [1] = "text" }, CHAT_BN_WHISPER_SEND = { [1] = "text" }, CORPSE_TOOLTIP = { [1] = "text" },
  HUD_EDIT_MODE_NEW_LAYOUT = { [1] = "text" }, HUD_EDIT_MODE_NEW_LAYOUT_DISABLED = { [1] = "text" },
  INTERACT_KEY_TUTORIAL = { [1] = "text" }, OPT_OUT_LOOT_TITLE = { [1] = "word" },
  -- the creature-type slot shows a CreatureType row's Japanese ("Humanoid" → its row), anything else (a class,
  -- a spec, a pet family) as written. A race slot is `text`: "Undead" is a race name too, and names stay English
  TOOLTIP_UNIT_LEVEL = { [1] = "text" }, TOOLTIP_UNIT_LEVEL_TYPE = { [1] = "text", [2] = "creatureType" },
  TOOLTIP_UNIT_LEVEL_RACE = { [1] = "text", [2] = "text" },
  TOOLTIP_UNIT_LEVEL_RACE_TYPE = { [1] = "text", [2] = "text", [3] = "creatureType" },
  UNIT_TYPE_PLUS_LEVEL_TEMPLATE = { [2] = "creatureType" },
  -- these two share their English ("%s (%s)") with PVP_LEAVE_BUTTON_TIME, and one template is
  -- compiled per distinct English under the first key of the group, so the three MUST declare the same kinds, or
  -- whichever key sorts first decides how the others capture (uistrings_spec pins this). `entry` keeps the PvP
  -- countdown's "Leave Match (30)" matching; a settings subcategory or a key name that is no dictionary entry keeps
  -- the whole line English, and the second half is shown as the client wrote it.
  KEY_BINDING_NAME_AND_KEY = { [1] = "entry", [2] = "text" },
  SETTINGS_SUBCATEGORY_FMT = { [1] = "entry", [2] = "text" },
  -- the gossip option's quest prepend: "|cnPURE_BLUE_COLOR:(Quest)|r <option>"; the prepend is QUEST_PREPEND,
  -- the option the server's text (gossipframeshared.lua:71–82)
  GOSSIP_OPTION_PREPEND = { [1] = "entry", [2] = "verbatim" },
  WEAPON_SKILL_DETAIL_SAME_LEVEL = { [1] = "percent", [2] = "percent" },
  WEAPON_SKILL_DETAIL_SAME_LEVEL_RANGED = { [1] = "percent", [2] = "percent" },
  WEAPON_SKILL_DETAIL_BOSS = { [1] = "percent", [2] = "percent", [3] = "percent", [4] = "percent" },
  WEAPON_SKILL_DETAIL_BOSS_RANGED = { [1] = "percent", [2] = "percent" },
  -- the PvP rank panel: the rank title is a name; the season name's expansion part is filled with ""
  -- (" Season 1"); the season countdown is an unabbreviated duration (D_DAYS … below)
  PVP_RANK_NUMBER_AND_TITLE = { [2] = "text" }, EXPANSION_SEASON_NAME = { [1] = "text" },
  SEASON_ENDS_IN_TIME = { [1] = "time" },
  QUEST_LOG_COUNT_TEMPLATE = { [1] = "text" }, -- quest list count: the first argument is a colour code
  -- the character level line: the colour, spec and class are kept as written
  PLAYER_LEVEL_NO_SPEC = { [1] = "text", [2] = "text", [3] = "text" },
  UNIT_TYPE_LEVEL_TEMPLATE = { [2] = "creatureType" },
  -- friends / Communities: the location after a Recruit-A-Friend label, and a member's race and
  -- class in the roster tooltip, are names, kept as written
  RAF_RECRUIT_FRIEND = { [1] = "text" }, RAF_RECRUITER_FRIEND = { [1] = "text" },
  COMMUNITY_MEMBER_CHARACTER_INFO_FORMAT = { [2] = "text", [3] = "text" },
  -- objective lines ("3/10 Kobold Vermin slain", "Neutral / Friendly Darnassus"): the mob, the faction
  -- and the player group are names, kept as written; a standing is a dictionary word, shown in Japanese
  QUEST_MONSTERS_KILLED = { [1] = "text" }, QUEST_PLAYERS_KILLED = { [3] = "text" },
  QUEST_PLAYERS_KILLED_NOPROGRESS = { [2] = "text" },
  QUEST_FACTION_NEEDED = { [1] = "text", [2] = "standing", [3] = "standing" },
  QUEST_FACTION_NEEDED_NOPROGRESS = { [1] = "text", [2] = "standing" },
  -- a spell's dual range ("Melee: 5 yd range") and a season currency requirement (the currency's name)
  SPELL_RANGE_DUAL = { [1] = "words" }, ITEM_REQ_AMOUNT_EARNED = { [2] = "text" },
  -- Communities: club, community, leader, inviter, realm, spec and class names and a name-check
  -- error are kept as written; "Guild" / "Community" / "Guilds" / "Communities", a reputation standing and a weekday
  -- are dictionary words shown in Japanese; a finder focus ("Social & Leveling") is a whole entry
  CLUB_FINDER_BANNED_POSTING_WARNING = { [1] = "word" }, ERR_CLUB_FINDER_ERROR_TYPE_FLAGGED_RENAME = { [1] = "word" },
  CLUB_FINDER_ROLE_TOOLTIP = { [1] = "word" }, CLUB_FINDER_FOCUS_STRING = { [1] = "entry" },
  CLUB_FINDER_LEADER = { [1] = "text" }, COMMUNITIES_INVIVATION_FRAME_LEADER_FORMAT = { [1] = "text" },
  CLUB_FINDER_REALM_NAME = { [1] = "text" },
  CLUB_FINDER_RECRUITING_ONE_SPEC = { [1] = "text", [2] = "text" },
  CLUB_FINDER_RECRUITING_TWO_SPECS = { [1] = "text", [2] = "text", [3] = "text" },
  CLUB_FINDER_RECRUITING_THREE_SPECS = { [1] = "text", [2] = "text", [3] = "text", [4] = "text" },
  CLUB_FINDER_RECRUITING_FOUR_SPECS = { [1] = "text", [2] = "text", [3] = "text", [4] = "text", [5] = "text" },
  COMMUNITIES_CALENDAR_EVENT_FORMAT = { [1] = "word", [2] = "text" },
  -- the name-check result is the client's sentence (C_Club.GetCommunityNameResultText, red-wrapped,
  -- communitiessettings.lua:350–366), periods included: `verbatim`, so these three are key-only (ONLY below)
  COMMUNITIES_CREATE_DIALOG_NAME_ERROR = { [1] = "verbatim" },
  COMMUNITIES_CREATE_DIALOG_SHORT_NAME_ERROR = { [1] = "verbatim" },
  COMMUNITIES_CREATE_DIALOG_NAME_AND_SHORT_NAME_ERROR = { [1] = "verbatim", [2] = "verbatim" },
  COMMUNITIES_INVITE_MANAGER_LABEL = { [1] = "text" }, COMMUNITIES_LIST_INVITATION_DISPLAY = { [1] = "text" },
  COMMUNITY_INVITATION_FRAME_INVITATION_TEXT = { [1] = "text" },
  REQUIRES_GUILD_FACTION = { [1] = "word" }, REQUIRES_GUILD_FACTION_TOOLTIP = { [1] = "word" },
  UNIT_TYPE_LEVEL_FACTION_TEMPLATE = { [2] = "text", [3] = "text" },
  -- the friends tooltip's zone and realm (or region) are names (camelot friendsframe.lua:1964–1967)
  BNET_FRIEND_TOOLTIP_ZONE_AND_REALM = { [1] = "text", [2] = "text" },
  BNET_FRIEND_TOOLTIP_ZONE_AND_REGION = { [1] = "text", [2] = "text" },
  -- ADR-030: the Forever windows' templates whose %s is a name, a word or a duration (per family needs)
  ADDON_LIST_PERFORMANCE_CURRENT_CPU = { [1] = "text" }, ADDON_LIST_PERFORMANCE_ENCOUNTER_CPU = { [1] = "text" },
  CHARACTER_SPECIFIC_MACROS = { [1] = "text" }, CHATCONFIG_HEADER = { [1] = "text" }, CHAT_TAB_NAME = { [1] = "text" },
  CLICK_BINDING_INTERACTION_TITLE = { [1] = "entry" }, INSPECT_GUILD_FACTION = { [1] = "text" },
  LOOTUPGRADEFRAME_TITLE = { [1] = "text" },
  PROFESSIONS_CREATE_ALL_FORMAT = { [1] = "words" }, TRADE_WARNING_CHANGED_OFFER = { [1] = "text" },
  GUILD_CHARTER_TEMPLATE = { [1] = "text" }, SPELL_INTERRUPTED_BY = { [1] = "text" },
  WORLD_MAP_PLAYER_COORDS_MAP_NAME = { [3] = "text" }, WORLD_MAP_PLAYER_COORDS_MAP_NAME_INTEGER = { [3] = "text" },
  UNDISCOVERED_FACTION_FLIGHTPOINT = { [1] = "text" }, CURRENCY_TRANSFER_MENU_TITLE = { [1] = "text" },
  CURRENCY_TRANSFER_NEW_BALANCE_PREVIEW = { [1] = "text" }, GUILD_RENAME_OPTIONS_REFUND = { [1] = "time" },
  GUILD_RENAME_OPTIONS_RENAME_COOLDOWN = { [1] = "time" }, SL_SET_CONVERSION_RECHARGE_TIME = { [1] = "time" },
  BLACK_MARKET_HOT_ITEM_TIME_LEFT = { [1] = "words" }, FACTION_CONTROLLED_TERRITORY = { [1] = "text" },
  TIME_IN_QUEUE = { [1] = "time" }, LFG_STATISTIC_AVERAGE_WAIT = { [1] = "time" },
  PVP_LEAVE_BUTTON_TIME = { [1] = "entry", [2] = "text" }, DEATH_RECAP_CAST_BY_TT = { [1] = "text", [2] = "text" },
  PVP_RATING_PREVIOUS = { [1] = "text" }, PVP_RATING_GAINED = { [1] = "text" }, PVP_RATING_NEW = { [1] = "text" },
  PVP_RATING_CURRENT = { [1] = "text" }, BATTLEGROUND_YOUR_PERSONAL_RATING = { [1] = "text" },
  BATTLEGROUND_ROLE_AVERAGE_MMV = { [1] = "text" }, COMBAT_TEXT_HONOR_GAINED = { [1] = "signed" },
  PVP_HONOR_CHANGE = { [1] = "signed" }, PVP_CONQUEST_CHANGE = { [1] = "signed" },
  PVP_RATING_CHANGE = { [1] = "signed" }, VOICE_CHAT_PROMPT_CHANNEL_ACTIVATE_PARTY = { [1] = "text" },
  VOICE_CHAT_PROMPT_CHANNEL_ACTIVATE_INSTANCE = { [1] = "text" },
  VOICE_CHAT_PROMPT_CHANNEL_ACTIVATE_RAID = { [1] = "text" },
  VOICE_CHAT_NOTIFICATION_CHANNEL_ACTIVATED_PARTY = { [1] = "text" },
  VOICE_CHAT_NOTIFICATION_CHANNEL_ACTIVATED_INSTANCE = { [1] = "text" },
  VOICE_CHAT_NOTIFICATION_CHANNEL_ACTIVATED_RAID = { [1] = "text" },
  VOICE_CHAT_NOTIFICATION_COMMS_MODE_PTT = { [1] = "text" }, RECENT_ALLY_INTERACTION_TIME_FORMAT = { [1] = "time" },
  RECENT_ALLY_PIN_EXPIRING_TOOLTIP = { [1] = "time" }, RAF_REWARD_TITLE = { [1] = "text" },
  REPORTING_REPORT_PLAYER = { [1] = "text" }, GM_TICKET_WAIT_TIME = { [1] = "time" },
  BN_TOAST_NEW_CLUB_INVITATION = { [1] = "text" }, TIME_PLAYED_ALERT = { [1] = "time" },
  HUD_EDIT_MODE_RENAME_LAYOUT_DIALOG_TITLE = { [1] = "text" },
  HUD_EDIT_MODE_DELETE_LAYOUT_DIALOG_TITLE = { [1] = "text" }, KEY_UNBOUND_ERROR = { [1] = "text" },
  PRIMARY_KEY_UNBOUND_ERROR = { [1] = "text" },
  SETTINGS_BIND_KEY_TO_COMMAND_OR_CANCEL = { [1] = "text", [2] = "text" },
  MAC_MIC_PREMISSIONS_NOTIFICATION = { [1] = "text" }, CAA_DEBUFF_SELF_ALERT_FORMAT_DEBUFF_TYPE = { [1] = "word" },
  PREFERRED_PLAY_SETTINGS_LOCKED_REASON_FORMAT = { [1] = "time" }, GUILD_REPUTATION_WARNING = { [1] = "text" },
  GUILD_ACHIEVEMENTS_ELIGIBLE = { [3] = "text" }, GUILD_ACHIEVEMENTS_ELIGIBLE_MINXP = { [3] = "text" },
  GUILD_ACHIEVEMENTS_ELIGIBLE_MAXXP = { [1] = "text" }, BOSS_BANNER_LOOT_SET = { [1] = "text" },
  LOSS_OF_CONTROL_DISPLAY_INTERRUPT_SCHOOL = { [1] = "word" }, AUTOFOLLOWSTART = { [1] = "text" },
  AUTOFOLLOWSTOP = { [1] = "text" }, READY_CHECK_MESSAGE = { [1] = "text" },
  -- error keys whose English is another surface's template. One template is compiled per distinct English
  -- under the first key of the group, and these sort first, so they carry the kinds the group already had ("Requires
  -- %s" is ITEM_REQ_SKILL's `skill`; the ready check is READY_CHECK_MESSAGE's `text`), and, declared, they are not
  -- key-only (below), so the tooltip and ready-check lines still match unrestricted.
  ERR_USE_LOCKED_WITH_ITEM_S = { [1] = "skill" }, ERR_USE_LOCKED_WITH_SPELL_S = { [1] = "skill" },
  SPELL_FAILED_REQUIRES_SPELL_FOCUS = { [1] = "skill" }, SPELL_FAILED_TOTEMS = { [1] = "skill" },
  SPELL_FAILED_TOTEM_CATEGORY = { [1] = "skill" },
  ERR_RAID_LEADER_READY_CHECK_START_S = { [1] = "text" },
  -- error arguments that are words, not names (a mechanic ("stunned"), a power ("mana"), an item
  -- class ("Shield"), a difficulty), shown in Japanese when they are a dictionary entry, as written otherwise; and the
  -- cooldowns the client prints as a duration. [unverified: the exact words the client passes]
  ERR_ATTACK_PREVENTED_BY_MECHANIC_S = { [1] = "words" }, ERR_USE_PREVENTED_BY_MECHANIC_S = { [1] = "words" },
  SPELL_FAILED_PREVENTED_BY_MECHANIC = { [1] = "words" }, ERR_SPELL_FAILED_ALREADY_AT_FULL_POWER_S = { [1] = "words" },
  SPELL_FAILED_EQUIPPED_ITEM_CLASS = { [1] = "words" }, SPELL_FAILED_EQUIPPED_ITEM_CLASS_MAINHAND = { [1] = "words" },
  SPELL_FAILED_EQUIPPED_ITEM_CLASS_OFFHAND = { [1] = "words" },
  ERR_DUNGEON_DIFFICULTY_CHANGED_S = { [1] = "words" }, ERR_RAID_DIFFICULTY_CHANGED_S = { [1] = "words" },
  ERR_PLAYER_DIFFICULTY_CHANGED_S = { [1] = "words" }, ERR_LEGACY_RAID_DIFFICULTY_CHANGED_S = { [1] = "words" },
  ERR_PARTY_LFG_BOOT_COOLDOWN_S = { [1] = "time" }, ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S = { [1] = "time" },
  ERR_PARTY_LFG_BOOT_INPATIENT_TIMER_S = { [1] = "time" }, ERR_DIFFICULTY_CHANGE_COOLDOWN_S = { [1] = "time" },
  ERR_DIFFICULTY_CHANGE_COMBAT_COOLDOWN_S = { [1] = "time" }, ERR_CHALLENGE_MODE_RESET_COOLDOWN_S = { [1] = "time" },
  -- removed from a community, :format(clubName) (communitieserrors.lua:126–132), the name as written
  CLUB_REMOVED_REASON_BANNED = { [1] = "text" }, CLUB_REMOVED_REASON_CLUB_DESTROYED = { [1] = "text" },
  CLUB_REMOVED_REASON_REMOVED = { [1] = "text" },
  -- system chat: words, not names: a stat ("Your Strength increases by 1."); the player's own away /
  -- busy message and the guild message of the day as typed (periods included); time played is a duration line
  LEVEL_UP_STAT = { [1] = "words" }, MARKED_AFK_MESSAGE = { [1] = "verbatim" }, MARKED_DND = { [1] = "verbatim" },
  GUILD_MOTD_TEMPLATE = { [1] = "verbatim" }, TIME_PLAYED_TOTAL = { [1] = "entry" },
  TIME_PLAYED_LEVEL = { [1] = "entry" },
  -- the add-alert disabled tooltip, "Cannot add cooldown alert: %s" around a status key
  -- (cooldownviewersettings.lua:291–292, 1793–1798)
  COOLDOWN_VIEWER_SETTINGS_ACTION_ADD_ALERT = { [1] = "entry" },
  -- a declared entry replaces a chat key's all-`text` default: every argument named
  ROLE_CHANGED_INFORM = { [1] = "text", [2] = "words" }, -- the role: Tank / Healer / Damage
  ROLE_CHANGED_INFORM_WITH_SOURCE = { [1] = "text", [2] = "words", [3] = "text" },
  EVENT_SCHEDULER_CHAT_REMINDER_SOON = { [1] = "text", [2] = "time" },
  COMMUNITIES_CHANNEL_ADDED_TO_CHAT_WINDOW = { [2] = "text" },
  COMMUNITIES_CHANNEL_REMOVED_FROM_CHAT_WINDOW = { [2] = "text" }, -- "[2. Trade]": the channel's name as written
  -- the chat line prefixes ("%s says: "): the name as written; UI/ChatSystem swaps their words by key only
  CHAT_SAY_GET = { [1] = "text" }, CHAT_YELL_GET = { [1] = "text" }, CHAT_WHISPER_GET = { [1] = "text" },
  CHAT_WHISPER_INFORM_GET = { [1] = "text" }, CHAT_BN_WHISPER_GET = { [1] = "text" },
  CHAT_BN_WHISPER_INFORM_GET = { [1] = "text" }, CHAT_AFK_GET = { [1] = "text" }, CHAT_DND_GET = { [1] = "text" },
  CHAT_CHANNEL_JOIN_GET = { [1] = "text" }, CHAT_CHANNEL_LEAVE_GET = { [1] = "text" },
  CHAT_RAID_WARNING_GET = { [1] = "text" }, CHAT_MONSTER_SAY_GET = { [1] = "text" },
  CHAT_MONSTER_YELL_GET = { [1] = "text" }, CHAT_MONSTER_WHISPER_GET = { [1] = "text" },
  -- a community action's error line is the action's sentence and a community error sentence
  -- (actionString:format(errorString), blizzard_communities/communitieserrors.lua:120–132): the second is an entry
  ERROR_CLUB_ACTION_ADD_BAN = { [1] = "entry" }, ERROR_CLUB_ACTION_CREATE = { [1] = "entry" },
  ERROR_CLUB_ACTION_CREATE_COMMUNITY = { [1] = "entry" }, ERROR_CLUB_ACTION_CREATE_MESSAGE = { [1] = "entry" },
  ERROR_CLUB_ACTION_CREATE_STREAM = { [1] = "entry" }, ERROR_CLUB_ACTION_CREATE_TICKET = { [1] = "entry" },
  ERROR_CLUB_ACTION_DECLINE_INVITATION = { [1] = "entry" }, ERROR_CLUB_ACTION_DESTROY = { [1] = "entry" },
  ERROR_CLUB_ACTION_DESTROY_COMMUNITY = { [1] = "entry" }, ERROR_CLUB_ACTION_DESTROY_MESSAGE = { [1] = "entry" },
  ERROR_CLUB_ACTION_DESTROY_STREAM = { [1] = "entry" }, ERROR_CLUB_ACTION_DESTROY_TICKET = { [1] = "entry" },
  ERROR_CLUB_ACTION_EDIT = { [1] = "entry" }, ERROR_CLUB_ACTION_EDIT_COMMUNITY = { [1] = "entry" },
  ERROR_CLUB_ACTION_EDIT_MEMBER = { [1] = "entry" }, ERROR_CLUB_ACTION_EDIT_MEMBER_NOTE = { [1] = "entry" },
  ERROR_CLUB_ACTION_EDIT_MESSAGE = { [1] = "entry" }, ERROR_CLUB_ACTION_EDIT_STREAM = { [1] = "entry" },
  ERROR_CLUB_ACTION_GET_BANS = { [1] = "entry" }, ERROR_CLUB_ACTION_GET_INVITATIONS = { [1] = "entry" },
  ERROR_CLUB_ACTION_GET_TICKET = { [1] = "entry" }, ERROR_CLUB_ACTION_GET_TICKETS = { [1] = "entry" },
  ERROR_CLUB_ACTION_INVITE_MEMBER = { [1] = "entry" }, ERROR_CLUB_ACTION_KICK_MEMBER = { [1] = "entry" },
  ERROR_CLUB_ACTION_LEAVE = { [1] = "entry" }, ERROR_CLUB_ACTION_LEAVE_COMMUNITY = { [1] = "entry" },
  ERROR_CLUB_ACTION_REDEEM_TICKET = { [1] = "entry" }, ERROR_CLUB_ACTION_REMOVE_BAN = { [1] = "entry" },
  ERROR_CLUB_ACTION_REVOKE_INVITATION = { [1] = "entry" }, ERROR_CLUB_ACTION_SUBSCRIBE = { [1] = "entry" },
  ERROR_CLUB_ACTION_SUBSCRIBE_COMMUNITY = { [1] = "entry" },
  -- ADR-038: names, tabs, channels, spells,
  -- layouts, categories, adapters, recipes and currencies are `text`; a shared English declares the same kinds under
  -- every key of its group ("%s Specific", "Created by %s", "%s deposited %s", "%s |cffff2020withdrew|r %s", "%s %s")
  BLIZZARD_COMBAT_LOG_MENU_BOTH = { [1] = "text" }, BLIZZARD_COMBAT_LOG_MENU_INCOMING = { [1] = "text" },
  BLIZZARD_COMBAT_LOG_MENU_OUTGOING = { [1] = "text" }, BLIZZARD_COMBAT_LOG_MENU_OUTGOING_ME = { [1] = "text" },
  BLIZZARD_COMBAT_LOG_MENU_SPELL_LINK = { [1] = "text" },
  COOLDOWN_VIEWER_SETTINGS_ASSIGN_TO_CATEGORY = { [1] = "text" },
  COOLDOWN_VIEWER_SETTINGS_CHARACTER_LAYOUTS_HEADER = { [1] = "text" },
  HUD_EDIT_MODE_CHARACTER_LAYOUTS_HEADER = { [1] = "text" },
  COOLDOWN_VIEWER_SETTINGS_ERROR_CANNOT_SWITCH_TO_LAYOUT_TOOLTIP_LINE = { [1] = "text", [2] = "text" },
  GUILDCONTROL_DISCORD_SETTINGS = { [1] = "text" }, SOCIAL_ENABLE_DISCORD_FUNCTIONALITY = { [1] = "text" }, -- |A…|a
  LEAVE_ZONE = { [1] = "text" }, TRANSMOG_SETS_FAVORITE_WITH_DESCRIPTION = { [1] = "text" },
  TRANSMOG_SETS_UNFAVORITE_WITH_DESCRIPTION = { [1] = "text" }, VOTE_TO_ABANDON_ON_COOLDOWN = { [1] = "time" },
  GX_ADAPTER_EXTERNAL = { [1] = "text" }, GX_ADAPTER_LOW_POWER = { [1] = "text" },
  ALREADY_FRIEND_FMT = { [1] = "text" },
  RAF_RECRUIT_ACTIVITY_DESCRIPTION = { [1] = "text" },
  DUNGEON_DIFFICULTY_BANNER_TOOLTIP = { [1] = "words" }, LOOT_HISTORY_CURRENT_WINNER = { [1] = "words" },
  RECENT_ALLY_TOOLTIP_LEVEL_RACE_FORMAT = { [2] = "text", [3] = "text" }, TOKEN_TRY_AGAIN_LATER = { [1] = "time" },
  TRADESKILL_RECIPE_LEVEL_RECIPE_FORMAT = { [1] = "text" },
  TRADESKILL_RECIPE_LEVEL_DROPDOWN_OPTION_FORMAT = { [1] = "text" }, -- "Rank %s": TALENT_BUTTON_…_NO_MAX_FORMAT's kinds
  TUTORIAL_TOKEN_GAME_TIME_STEP_2_BALANCE = { [1] = "verbatim" },
  AUCTION_HOUSE_BUYER_FORMAT = { [1] = "text" }, AUCTION_HOUSE_HIGH_BIDDER_FORMAT = { [1] = "text" },
  AUCTION_HOUSE_TIME_LEFT_FORMAT_ACTIVE = { [1] = "text" }, -- a colour-wrapped SecondsFormatter duration, as written
  AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT = { [1] = "entry" },
  AUCTION_HOUSE_TOOLTIP_MULTIPLE_SELLERS_FORMAT = { [1] = "text" },
  AUCTION_HOUSE_TOOLTIP_OVERFLOW_SELLERS_FORMAT = { [1] = "text" },
  AUCTION_HOUSE_TOOLTIP_SELLER_FORMAT = { [1] = "text" },
  PROFESSIONS_REQUIRED_TOOLS = { [1] = "text" }, OPTIONAL_QUEST_OBJECTIVE_DESCRIPTION = { [1] = "verbatim" },
  TOOLTIP_VIGNETTE_OBJECTIVE_DEFEAT = { [1] = "text" },
  TOOLTIP_VIGNETTE_OBJECTIVE_DEFEAT_SHOW_HEALTH = { [1] = "text", [2] = "percent" },
  ACHIEVEMENTS_COMPLETED_CATEGORY = { [1] = "text" }, ACHIEVEMENT_META_COMPLETED_DATE = { [1] = "text" },
  AURA_END = { [1] = "text" }, CALENDAR_ANNOUNCEMENT_CREATEDBY_PLAYER = { [1] = "text" },
  CALENDAR_EVENT_CREATORNAME = { [1] = "text" }, CALENDAR_EVENTNAME_FORMAT_END = { [1] = "text" },
  CALENDAR_EVENTNAME_FORMAT_RAID_LOCKOUT = { [1] = "text" }, CALENDAR_EVENTNAME_FORMAT_RAID_RESET = { [1] = "text" },
  CALENDAR_EVENTNAME_FORMAT_START = { [1] = "text" }, CALENDAR_EVENT_INVITEDBY_PLAYER = { [1] = "text" },
  -- the barber shop's choice line ("3: Brown") and a locked choice's source ("Source: See colors")
  CHARACTER_CUSTOMIZATION_CHOICE_TOOLTIP = { [2] = "customizationChoice" },
  BARBERSHOP_CUSTOMIZATION_SOURCE_FORMAT = { [1] = "customizationSource" },
  -- the holiday's description is a HolidayDescription row's Japanese when it is one, else as written
  CALENDAR_HOLIDAYFRAME_BEGINSENDS = { [1] = "holidayDescription", [2] = "text", [3] = "text", [4] = "text",
    [5] = "text" },
  CALENDAR_RAID_LOCKOUT_DESCRIPTION = { [1] = "text", [2] = "text" },
  CALENDAR_RAID_RESET_DESCRIPTION = { [1] = "text", [2] = "text" },
  CALENDAR_SIGNEDUP_FOR_GUILDEVENT_WITH_STATUS = { [1] = "entry" },
  CALENDAR_VIEW_EVENTTYPE = { [1] = "entry", [2] = "text" },
  CLICK_BINDING_MACRO_TITLE = { [1] = "text" }, -- CLICK_BINDINGS_BINDING_TEXT_FORMAT's kinds below
  CRAFTING_ORDER_RECIPE_PROFESSION_FMT = { [1] = "text" }, CRAFTING_ORDER_TIME_PENDING_FMT = { [1] = "time" },
  CURRENCY_TRANSFER_DESTINATION = { [1] = "text" },
  DEATH_RECAP_DAMAGE_TT = { [1] = "text", [2] = "words" }, TEXT_MODE_A_STRING_VALUE_SCHOOL = { [1] = "text",
  [2] = "words" },
  TEXT_MODE_A_STRING_RESULT_ABSORB = { [1] = "text" }, TEXT_MODE_A_STRING_RESULT_BLOCK = { [1] = "text" },
  TEXT_MODE_A_STRING_RESULT_OVERKILLING = { [1] = "text" }, TEXT_MODE_A_STRING_RESULT_RESIST = { [1] = "text" },
  DISCORD_GUILD_LINKED_CHANNEL = { [1] = "text" }, DISCORD_GUILD_LINKED_SERVER = { [1] = "text" },
  DISCORD_VALID_SERVER_CHANNEL_LIST = { [1] = "text" }, ENCHANTED_TOOLTIP_LINE = { [1] = "text" },
  ENCOUNTER_JOURNAL_SEARCH_RESULTS = { [1] = "verbatim" },
  FULLDATE = { [1] = "word", [2] = "word" }, -- the weekday and the month (a Japanese date)
  GUILDBANK_BUYTAB_MONEY_FORMAT = { [1] = "text", [2] = "verbatim" },
  GUILDBANK_DEPOSIT_FORMAT = { [1] = "text", [2] = "verbatim" }, GUILDBANK_DEPOSIT_MONEY_FORMAT = { [1] = "text",
  [2] = "verbatim" },
  GUILDBANK_WITHDRAW_FORMAT = { [1] = "text", [2] = "verbatim" },
  GUILDBANK_WITHDRAW_MONEY_FORMAT = { [1] = "text", [2] = "verbatim" },
  GUILDBANK_GUILD_RENAME_PURCHASE = { [1] = "text", [2] = "verbatim" },
  GUILDBANK_GUILD_RENAME_REFUND = { [1] = "text", [2] = "verbatim" },
  GUILDBANK_REPAIR_MONEY_FORMAT = { [1] = "text", [2] = "verbatim" },
  GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT = { [1] = "text", [2] = "verbatim" },
  GUILDBANK_MOVE_FORMAT = { [1] = "text", [2] = "verbatim", [4] = "text", [5] = "text" },
  GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT = { [1] = "verbatim" }, GUILDBANK_UNLOCKTAB_FORMAT = { [1] = "text" },
  GUILDBANK_INFO_TITLE_FORMAT = { [1] = "text" }, GUILDBANK_LOG_TITLE_FORMAT = { [1] = "text" },
  GUILDBANK_REMAINING_MONEY = { [1] = "text", [2] = "entry" }, GUILD_BANK_LOG_TIME = { [1] = "time" },
  GUILD_TRADE_SKILL_TITLE = { [1] = "text" }, NOT_ENOUGH_CURRENCY = { [1] = "text" },
  QUICK_JOIN_TOAST_LFGLIST_MESSAGE = { [1] = "text", [2] = "verbatim" },
  QUICK_JOIN_TOAST_MESSAGE = { [1] = "text", [2] = "entryOrText" }, SOCIAL_QUEUE_FORMAT_BATTLEGROUND = { [1] = "text" },
  TRANSMOGRIFIED_ENCHANT = { [1] = "text" },
  VOICE_CHAT_CHANNEL_ANNOUNCE = { [1] = "verbatim", [2] = "verbatim", [3] = "verbatim" }, -- the voiceParts label form
  VOICE_CHAT_CHANNEL_MANAGEMENT_TIP = { [1] = "text", [2] = "text" },
  BAG_FILTER_ASSIGNED_TO = { [1] = "entryList" }, BANK_TAB_DEPOSIT_ASSIGNMENTS = { [1] = "entryList" },
  BANK_TAB_EXPANSION_ASSIGNMENT = { [1] = "entry" },
  GUILDEVENT_TYPE_DEMOTE = { [1] = "text", [2] = "text", [3] = "text" }, GUILDEVENT_TYPE_INVITE = { [1] = "text",
  [2] = "text" },
  GUILDEVENT_TYPE_JOIN = { [1] = "text" }, GUILDEVENT_TYPE_PROMOTE = { [1] = "text", [2] = "text", [3] = "text" },
  GUILDEVENT_TYPE_QUIT = { [1] = "text" }, GUILDEVENT_TYPE_REMOVE = { [1] = "text", [2] = "text" },
  GUILD_EVENT_FORMAT = { [1] = "entry", [2] = "text", [3] = "verbatim" }, -- [1] TODAY (colour-wrapped) or a weekday
  ITEM_COMPARISON_SWAP_ITEM_MAINHAND_DESCRIPTION = { [1] = "text" },
  ITEM_COMPARISON_SWAP_ITEM_OFFHAND_DESCRIPTION = { [1] = "text" },
  TALENTS_LINK_FORMAT = { [1] = "text", [2] = "text" }, COMMUNITIES_MESSAGE_OF_THE_DAY_FORMAT = { [1] = "verbatim" },
  RESTRICT_CHAT_TOOLTIP_FORMAT = { [1] = "entry", [2] = "entry" },
  -- the battle popups (blizzard_lfgutil/mainline/pvphelper.lua): a battle's name and a group's leader are
  -- copied as written; the closing countdown is a duration
  QUEUED_FOR = { [1] = "verbatim" }, INVITATION = { [1] = "verbatim" },
  WARGAME_CHALLENGED = { [1] = "verbatim", [2] = "verbatim" }, ARENA_COMPLETE_MESSAGE = { [1] = "time" },
  BATTLEGROUND_COMPLETE_MESSAGE = { [1] = "time" }, INSTANCE_SHUTDOWN_MESSAGE = { [1] = "time" },
  -- the recruitment dialog: a faction and a realm name, a date the client formats
  RAF_RECRUITS_FACTION_AND_REALM = { [1] = "verbatim", [2] = "verbatim" },
  RAF_ACTIVE_LINK_EXPIRE_DATE = { [1] = "verbatim" }, RAF_EXPENDED_LINK_EXPIRE_DATE = { [1] = "verbatim" },
  -- the Click Cast Bindings row: the modifier keys ("SHIFT-ALT", the key names as the keyboard shows them) and a mouse
  -- button word (blizzard_clickbindingui.lua:224–231)
  CLICK_BINDINGS_BINDING_TEXT_FORMAT = { [1] = "modifiers", [2] = "entry" },
  -- the audio assist resource options: the player's power word (the global named by the power token: a dictionary
  -- word)
  CAA_SAY_PLAYER_RESOURCE_LABEL = { [1] = "entry" }, CAA_SAY_PLAYER_RESOURCE_TOOLTIP = { [1] = "entry" },
  CAA_SAY_PLAYER_RESOURCE_FORMAT_TOOLTIP = { [1] = "entry" },
  CAA_SAY_PLAYER_RESOURCE_THROTTLE_TOOLTIP = { [1] = "entry" },
  CAA_SAY_PLAYER_RESOURCE_VOICE_TOOLTIP = { [1] = "entry" }, CAA_SAY_PLAYER_RESOURCE_VOLUME_TOOLTIP = { [1] = "entry" },
  -- the dialog templates (UI/Popups fills them from the dialog's own arguments, Index:formatArgs; a %s is a
  -- name, an amount or a sentence the client passes, copied as written) and the special dialogs' templates
  ABANDON_QUEST_CONFIRM = { [1] = "verbatim" },
  ABANDON_QUEST_CONFIRM_WITH_ITEMS = { [1] = "verbatim", [2] = "verbatim" },
  ADDON_ACTION_FORBIDDEN = { [1] = "verbatim" }, ADDON_PERFORMANCE_SPECIFIC_ERROR_TEXT = { [1] = "verbatim" },
  ANIMA_DIVERSION_CONFIRM_CHANNEL = { [1] = "verbatim", [2] = "verbatim" },
  ANIMA_DIVERSION_CONFIRM_REINFORCE = { [1] = "verbatim" }, AREA_SPIRIT_HEAL = { [2] = "verbatim" },
  ARTIFACT_RESPEC = { [1] = "verbatim" }, ARTIFACT_RESPEC_NOT_ENOUGH_POWER = { [1] = "verbatim" },
  BILLING_NAG_DIALOG = { [2] = "verbatim" }, BLACK_MARKET_AUCTION_CONFIRMATION = { [1] = "verbatim" },
  BLOCK_INVITES_CONFIRMATION = { [1] = "verbatim" }, BROWSER_EXTERNAL_LINK_DIALOG = { [1] = "verbatim" },
  CALENDAR_ERROR_CREATEDATE_AFTER_MAX = { [2] = "verbatim" }, CAMP_TIMER = { [2] = "verbatim" },
  CHANNEL_INVITE = { [1] = "verbatim" }, CHANNEL_PASSWORD = { [1] = "verbatim" },
  CHAT_INVITE_NOTICE_POPUP = { [1] = "verbatim", [2] = "verbatim" },
  CHAT_PASSWORD_NOTICE_POPUP = { [1] = "verbatim" }, CONFIRM_AZERITE_EMPOWERED_ITEM_RESPEC = { [1] = "verbatim" },
  CONFIRM_AZERITE_EMPOWERED_ITEM_RESPEC_EXPENSIVE = { [1] = "verbatim", [2] = "verbatim", [3] = "verbatim" },
  CONFIRM_BATTLEFIELD_ENTRY = { [1] = "verbatim" }, CONFIRM_BINDER = { [1] = "verbatim" },
  CONFIRM_DELETE_EQUIPMENT_SET = { [1] = "verbatim" }, CONFIRM_DESTROY_COMMUNITY_STREAM_LABEL = { [1] = "verbatim" },
  CONFIRM_GARRISON_FOLLOWER_TEMPORARY_ABILITY = { [1] = "verbatim" }, CONFIRM_GUILD_LEAVE = { [1] = "verbatim" },
  CONFIRM_GUILD_PROMOTE = { [1] = "verbatim" }, CONFIRM_HIGH_COST_ITEM = { [1] = "verbatim" },
  CONFIRM_LEAVE_COMMUNITY_SUBTEXT = { [1] = "verbatim" },
  CONFIRM_LOOT_DISTRIBUTION = { [1] = "verbatim", [2] = "verbatim" },
  CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL = { [1] = "verbatim" }, CONFIRM_OVERWRITE_EQUIPMENT_SET = { [1] = "verbatim" },
  CONFIRM_PURCHASE_NONREFUNDABLE_ITEM = { [1] = "verbatim", [2] = "verbatim" },
  CONFIRM_PURCHASE_TOKEN_ITEM = { [1] = "verbatim", [2] = "verbatim" },
  CONFIRM_REFUND_TOKEN_ITEM = { [1] = "verbatim", [2] = "verbatim" },
  CONFIRM_REMOVE_COMMUNITY_MEMBER_LABEL = { [1] = "verbatim" }, CONFIRM_SAVE_EQUIPMENT_SET = { [1] = "verbatim" },
  CONFIRM_SUMMON = { [1] = "verbatim", [2] = "verbatim", [4] = "verbatim" },
  CONFIRM_SUMMON_SCENARIO = { [1] = "verbatim", [2] = "verbatim", [4] = "verbatim" },
  CONFIRM_SUMMON_STARTING_AREA = { [1] = "verbatim", [2] = "verbatim", [4] = "verbatim" },
  COOLDOWN_VIEWER_SETTINGS_DELETE_LAYOUT_DIALOG_TITLE = { [1] = "text" },
  COOLDOWN_VIEWER_SETTINGS_RENAME_LAYOUT_DIALOG_TITLE = { [1] = "text" },
  CRAFTING_ORDERS_IGNORE_CONFIRMATION = { [1] = "verbatim" }, DEATH_RELEASE_TIMER = { [2] = "verbatim" },
  DELETE_GOOD_ITEM = { [1] = "verbatim" }, DELETE_GOOD_ITEM_GAMEPAD = { [1] = "verbatim" },
  DELETE_GOOD_QUEST_ITEM = { [1] = "verbatim" }, DELETE_GOOD_QUEST_ITEM_GAMEPAD = { [1] = "verbatim" },
  DELETE_ITEM = { [1] = "verbatim" }, DELETE_MAIL_CONFIRMATION = { [1] = "verbatim" },
  DELETE_QUEST_ITEM = { [1] = "verbatim" }, DUEL_OUTOFBOUNDS_TIMER = { [2] = "verbatim" },
  DUEL_REQUESTED = { [1] = "verbatim" }, DUEL_TO_THE_DEATH_CHALLENGE_CONFIRM = { [1] = "verbatim" },
  GARRISON_BOOT_TIMER = { [2] = "verbatim" },
  GROUP_FINDER_DELIST_WARNING_SUBTEXT = { [1] = "verbatim" },
  GROUP_FINDER_DELIST_WARNING_TITLE = { [1] = "verbatim" },
  GUILD_RENAME_DIALOG_TEXT = { [1] = "verbatim", [2] = "verbatim" },
  GUILD_RENAME_REFUND_DIALOG_SUBTEXT = { [1] = "verbatim" },
  GUILD_RENAME_REFUND_DIALOG_TEXT = { [1] = "verbatim", [2] = "verbatim", [3] = "verbatim" },
  HARDCORE_GUILDLEADER_DEATH = { [1] = "verbatim" }, INSTANCE_BOOT_TIMER = { [2] = "verbatim" },
  INSTANCE_LOCK_TIMER = { [1] = "verbatim", [2] = "verbatim" }, LFG_OFFER_CONTINUE = { [1] = "verbatim" },
  LIMITED_CURRENCY_PURCHASE = { [1] = "verbatim", [3] = "verbatim", [4] = "verbatim" },
  LIMITED_CURRENCY_PURCHASE_FINAL = { [1] = "verbatim", [2] = "verbatim", [3] = "verbatim" },
  LOOT_NO_DROP = { [1] = "verbatim" }, MAC_INPUT_MONITORING1014 = { [1] = "verbatim" },
  MAC_INPUT_MONITORING1015 = { [1] = "verbatim" }, MAC_OPEN_UNIVERSAL_ACCESS1090 = { [1] = "verbatim" },
  PET_BATTLE_PVP_DUEL_REQUESTED = { [1] = "verbatim" }, PET_RENAME_CONFIRMATION = { [1] = "verbatim" },
  PREMADE_GROUP_INSECURE_SEARCH = { [1] = "verbatim" },
  PROFESSIONS_RECRAFTING_REPLACE_OPTIONAL = { [1] = "verbatim" }, PROFESSION_CONFIRMATION1 = { [1] = "verbatim" },
  PROFESSION_CONFIRMATION2 = { [1] = "verbatim" }, PROFESSION_RESPEC_CONFIRMATION = { [1] = "verbatim" },
  PURCHASE_UNIQUE_AUCTION_CONFIRMATION = { [1] = "verbatim" }, QUEST_ACCEPT = { [1] = "verbatim", [2] = "verbatim" },
  QUEST_ACCEPT_LOG_FULL = { [1] = "verbatim", [2] = "verbatim" }, QUIT_TIMER = { [2] = "verbatim" },
  RAF_REMOVE_RECRUIT_CONFIRM = { [1] = "verbatim" }, REMOVE_AUTHENTICATOR_FROM_RANK = { [1] = "verbatim" },
  REPLACE_ENCHANT = { [1] = "verbatim", [2] = "verbatim" }, REPORT_BATTLEPET_NAME_CONFIRMATION = { [1] = "verbatim" },
  REPORT_PET_NAME_CONFIRMATION = { [1] = "verbatim" }, REPORT_SPAM_CONFIRMATION = { [1] = "verbatim" },
  RESURRECT_REQUEST = { [1] = "verbatim" }, RESURRECT_REQUEST_NO_SICKNESS = { [1] = "verbatim" },
  SAVED_VARIABLES_TOO_LARGE = { [1] = "verbatim" }, SET_FRIENDNOTE_LABEL = { [1] = "verbatim" },
  SL_SET_CONVERSION_ONE_CHARGE_REMAINING = { [1] = "verbatim" },
  TRADE_POTENTIAL_REMOVE_TRANSMOG = { [1] = "verbatim" }, TRADE_WITH_QUESTION = { [1] = "verbatim" },
  TRANSMOG_CUSTOM_SET_CONFIRM_DELETE = { [1] = "verbatim" },
  TRANSMOG_CUSTOM_SET_CONFIRM_OVERWRITE = { [1] = "verbatim" }, UNLEARN_SKILL = { [1] = "verbatim" },
  UNLEARN_SKILL_GAMEPAD = { [1] = "verbatim" }, VOTE_BOOT_PLAYER = { [1] = "verbatim", [2] = "verbatim" },
  VOTE_BOOT_REASON_REQUIRED = { [1] = "verbatim" }, WORLD_PVP_DESERTER = { [1] = "verbatim" },
  WORLD_PVP_ENTER = { [1] = "verbatim", [3] = "verbatim" }, WORLD_PVP_EXITED_BATTLE = { [1] = "verbatim" },
  WORLD_PVP_FAIL = { [1] = "verbatim" }, WORLD_PVP_INVITED = { [1] = "verbatim" },
  WORLD_PVP_INVITED_WARMUP = { [1] = "verbatim" }, WORLD_PVP_LOW_LEVEL = { [1] = "verbatim" },
  WORLD_PVP_NOT_WHILE_IN_RAID = { [1] = "verbatim" }, WORLD_PVP_PENDING = { [1] = "verbatim" },
  WORLD_PVP_PENDING_REMOTE = { [1] = "verbatim" }, WORLD_PVP_QUEUED = { [1] = "verbatim" },
  WORLD_PVP_QUEUED_WARMUP = { [1] = "verbatim" },
}

-- The UI errors frame's keys (ADR-035). An ERR_* / SPELL_FAILED_* key with no ARGS entry takes every `%s` as
-- `text` (a name, an item, a zone: shown as the client wrote it), and every error template is matched only by key:
-- the errors surface asks for the line's own key (UI/Errors.lua); no other surface's unrestricted match sees "%s
-- slain: %d/%d". Declaring kinds does not change that; only the keys below, whose English another
-- surface's template shares or which a window matches unrestricted, keep their unrestricted matching.
UIStrings.ERROR_UNRESTRICTED = { ERR_CLUB_FINDER_ERROR_TYPE_FLAGGED_RENAME = true, ERR_USE_LOCKED_WITH_ITEM_S = true,
  ERR_USE_LOCKED_WITH_SPELL_S = true, SPELL_FAILED_REQUIRES_SPELL_FOCUS = true, SPELL_FAILED_TOTEMS = true,
  SPELL_FAILED_TOTEM_CATEGORY = true, ERR_RAID_LEADER_READY_CHECK_START_S = true }

-- System chat: the lines the game sends as SYSTEM / LOOT / MONEY / COMBAT_* / SKILL … chat, named by GlobalStrings
-- family (no Lua names them; pipeline/wfj/dev/ui_inventory.py DYNAMIC["chatsystem"] lists the same families, and a
-- Python test fails when a listed chat template with `%s` is in neither this list nor ONLY). Like an error key: a
-- `%s` is shown as written unless declared, and the template is asked for by key (UI/ChatSystem), never matched
-- unrestricted.
UIStrings.CHAT_FAMILIES = { "^LOOT_ITEM$", "^LOOT_ITEM_", "^LOOT_ROLL_", "^CREATED_ITEM$", "^CREATED_ITEM_MULTIPLE$",
  "^LOOT_MONEY", "^YOU_LOOT_MONEY", "^LOOT_CURRENCY_REFUND$", "^CURRENCY_GAINED", "^COMBATLOG_XPGAIN_",
  "^COMBATLOG_HONOR", "^COMBATLOG_DISHONOR", "^COMBATLOG_ARENAPOINTS", "^FACTION_STANDING_INCREASED",
  "^FACTION_STANDING_DECREASED", "^SKILL_RANK_UP$", "^TRADESKILL_LOG_", "^OPEN_LOCK_", "^MARKED_AFK", "^MARKED_DND",
  "^CLEARED_AFK", "^CLEARED_DND", "^LEVEL_UP_NO_LINK$", "^LEVEL_UP_HEALTH", "^LEVEL_UP_STAT$",
  "^LEVEL_UP_SKILL_POINTS$", "^DURABILITYDAMAGE_DEATH$", "^INSTANCE_RESET_", "^RANDOM_ROLL_RESULT$",
  "^ACHIEVEMENT_BROADCAST",
  -- the lines Blizzard's Lua prints into chat (ui_inventory chat_call_keys), each by name
  "^EVENT_SCHEDULER_CHAT_REMINDER_", "^GENERIC_MONEY_GAINED_RECEIPT$", "^QUEST_SESSION_REPLAY_QUEST_REMOVED$",
  "^ROLE_CHANGED_INFORM", "^ROLE_REMOVED_INFORM", "^SLASH_COMMENTATOR", "^BN_UNABLE_TO_RESOLVE_NAME$",
  "^CALENDAR_EVENT_ALARM_MESSAGE$", "^CHAT_LEAVE_CHANNEL_PREVENTED$",
  "^COOLDOWN_VIEWER_SETTINGS_COPY_TO_CLIPBOARD_NOTICE$", "^HUD_EDIT_MODE_COPY_TO_CLIPBOARD_NOTICE$",
  "^HUD_EDIT_MODE_LAYOUT_APPLIED$", "^VOICE_CHAT_CHANNEL_ANNOUNCE_MEMBER_",
  "^VOICE_CHAT_CHANNEL_MANAGEMENT_TIP$" } -- printed into chat (channelframe.lua)

-- The duration templates a `time` argument may be: which of them the C client prints inside a cooldown line
-- is not in the UI source, so every candidate is listed.
UIStrings.DURATIONS = { "INT_SPELL_DURATION_DAYS", "INT_SPELL_DURATION_HOURS", "INT_SPELL_DURATION_MIN",
  "INT_SPELL_DURATION_SEC", "SPELL_DURATION_DAYS", "SPELL_DURATION_HOURS", "SPELL_DURATION_MIN", "SPELL_DURATION_SEC",
  "DAYS_ABBR", "HOURS_ABBR", "MINUTES_ABBR", "SECONDS_ABBR", "SECONDS_FLOAT_ABBR",
  -- the friends list's "last online %s ago" (BNET_LAST_ONLINE_TIME, FriendsFrame.lua:1510)
  "LASTONLINE_MINUTES", "LASTONLINE_HOURS", "LASTONLINE_DAYS", "LASTONLINE_MONTHS", "LASTONLINE_YEARS",
  -- the PvP rank season countdown's unabbreviated units (Forever timeutil.lua:84–87)
  "D_DAYS", "D_HOURS", "D_MINUTES", "D_SECONDS",
  -- the queue's "< 1 minute" (queuestatusframe.lua:1083–1086) and a log line's "< an hour"
  -- (TimeUtil.GetRecentTimeDate, timeutil.lua:24–44, in GUILD_BANK_LOG_TIME): the `time` capture admits a leading "<"
  "LESS_THAN_ONE_MINUTE", "LASTONLINE_MINS" }

-- The ones a spell's `$d` renders through: what `$D<k>` copies. The friends-list forms are left out on
-- purpose: "lasts for 30 minutes" in a tooltip is text the English wrote, not a duration the client chose, and
-- counting it would shift every `$D` after it (Deadly Poison would show 30分 where the poison lasts 12秒).
-- `core/align.DURATION_UNITS` is these strings' unit words; `test_align` holds the two together.
UIStrings.SPELL_DURATIONS = { "INT_SPELL_DURATION_DAYS", "INT_SPELL_DURATION_HOURS", "INT_SPELL_DURATION_MIN",
  "INT_SPELL_DURATION_SEC", "SPELL_DURATION_DAYS", "SPELL_DURATION_HOURS", "SPELL_DURATION_MIN", "SPELL_DURATION_SEC",
  "DAYS_ABBR", "HOURS_ABBR", "MINUTES_ABBR", "SECONDS_ABBR", "SECONDS_FLOAT_ABBR" }

-- Templates with almost no literal text of their own ("%2$s %1$s", "%s at %s") would take any
-- line that starts with a dictionary word ("Return to Verner", "Frost Resistance increased by 30"). They are matched
-- only where a widget asks for them by key (matchOnly), never by an unrestricted match.
UIStrings.ONLY = { COOLDOWN_VIEWER_SETTINGS_ACTION_ADD_ALERT = true,
  QUEST_MONSTERS_KILLED = true, QUEST_PLAYERS_KILLED = true, QUEST_PLAYERS_KILLED_NOPROGRESS = true,
  QUEST_FACTION_NEEDED = true, QUEST_FACTION_NEEDED_NOPROGRESS = true, COMMUNITIES_CALENDAR_EVENT_FORMAT = true,
  -- "%s (%s)" and "Level %s" take almost any line: only where a widget asks for them
  KEY_BINDING_NAME_AND_KEY = true, SETTINGS_SUBCATEGORY_FMT = true, TOOLTIP_UNIT_LEVEL = true,
  TOOLTIP_UNIT_LEVEL_TYPE = true, TOOLTIP_UNIT_LEVEL_RACE = true, TOOLTIP_UNIT_LEVEL_RACE_TYPE = true,
  CORPSE_TOOLTIP = true, GOSSIP_OPTION_PREPEND = true,
  -- "%d: %s" and "Source: %s" would take "3: Kill Hogger…" or "Source: Dropped by …" anywhere;
  -- only the barber shop's tooltip asks for them (UI/BarberShop)
  CHARACTER_CUSTOMIZATION_CHOICE_TOOLTIP = true, BARBERSHOP_CUSTOMIZATION_SOURCE_FORMAT = true,
  -- system chat lines outside the chat families, asked for by UI/ChatSystem only
  GUILD_MOTD_TEMPLATE = true, TIME_PLAYED_TOTAL = true, TIME_PLAYED_LEVEL = true,
  CHAT_SAY_GET = true, CHAT_YELL_GET = true, CHAT_WHISPER_GET = true, CHAT_WHISPER_INFORM_GET = true,
  CHAT_BN_WHISPER_GET = true, CHAT_BN_WHISPER_INFORM_GET = true, CHAT_AFK_GET = true, CHAT_DND_GET = true,
  CHAT_CHANNEL_JOIN_GET = true, CHAT_CHANNEL_LEAVE_GET = true, CHAT_RAID_WARNING_GET = true,
  CHAT_MONSTER_SAY_GET = true, CHAT_MONSTER_YELL_GET = true, CHAT_MONSTER_WHISPER_GET = true,
  COMMUNITIES_CHANNEL_ADDED_TO_CHAT_WINDOW = true, COMMUNITIES_CHANNEL_REMOVED_FROM_CHAT_WINDOW = true,
  -- templates with little literal text, a `verbatim` / `entryOrText` argument, or a writer that asks by key
  -- (a log line, a menu entry, a composite a surface splits itself). "%s is already your friend." shares its English
  -- with ERR_FRIEND_ALREADY_S, which sorts after it: listing it here keeps the group key-only (UI/Errors asks by key)
  ALREADY_FRIEND_FMT = true, BLIZZARD_COMBAT_LOG_MENU_SPELL_LINK = true, LEAVE_ZONE = true,
  COOLDOWN_VIEWER_SETTINGS_ERROR_CANNOT_SWITCH_TO_LAYOUT_TOOLTIP_LINE = true,
  COOLDOWN_VIEWER_SETTINGS_ASSIGN_TO_CATEGORY = true,
  GX_ADAPTER_EXTERNAL = true, GX_ADAPTER_LOW_POWER = true, LOOT_HISTORY_CURRENT_WINNER = true,
  TRADESKILL_RECIPE_LEVEL_RECIPE_FORMAT = true, TUTORIAL_TOKEN_GAME_TIME_STEP_2_BALANCE = true,
  OPTIONAL_QUEST_OBJECTIVE_DESCRIPTION = true, CALENDAR_HOLIDAYFRAME_BEGINSENDS = true, CALENDAR_VIEW_EVENTTYPE = true,
  CURRENCY_TRANSFER_DESTINATION = true, DEATH_RECAP_DAMAGE_TT = true,
  TEXT_MODE_A_STRING_VALUE_SCHOOL = true, DISCORD_GUILD_LINKED_CHANNEL = true, DISCORD_GUILD_LINKED_SERVER = true,
  ENCOUNTER_JOURNAL_SEARCH_RESULTS = true, GUILDBANK_BUYTAB_MONEY_FORMAT = true, GUILDBANK_DEPOSIT_FORMAT = true,
  GUILDBANK_DEPOSIT_MONEY_FORMAT = true, GUILDBANK_WITHDRAW_FORMAT = true, GUILDBANK_WITHDRAW_MONEY_FORMAT = true,
  GUILDBANK_GUILD_RENAME_PURCHASE = true, GUILDBANK_GUILD_RENAME_REFUND = true, GUILDBANK_REPAIR_MONEY_FORMAT = true,
  GUILDBANK_WITHDRAWFORTAB_MONEY_FORMAT = true, GUILDBANK_MOVE_FORMAT = true,
  GUILDBANK_AWARD_MONEY_SUMMARY_FORMAT = true,
  GUILDBANK_UNLOCKTAB_FORMAT = true, GUILDBANK_INFO_TITLE_FORMAT = true, GUILDBANK_LOG_TITLE_FORMAT = true,
  GUILD_TRADE_SKILL_TITLE = true, QUICK_JOIN_TOAST_LFGLIST_MESSAGE = true, QUICK_JOIN_TOAST_MESSAGE = true,
  VOICE_CHAT_CHANNEL_ANNOUNCE = true, GUILDEVENT_TYPE_DEMOTE = true, GUILDEVENT_TYPE_INVITE = true,
  GUILDEVENT_TYPE_JOIN = true, GUILDEVENT_TYPE_PROMOTE = true, GUILDEVENT_TYPE_QUIT = true,
  GUILDEVENT_TYPE_REMOVE = true,
  GUILD_EVENT_FORMAT = true, COMMUNITIES_MESSAGE_OF_THE_DAY_FORMAT = true, RESTRICT_CHAT_TOOLTIP_FORMAT = true,
  COMMUNITIES_CREATE_DIALOG_NAME_ERROR = true, COMMUNITIES_CREATE_DIALOG_SHORT_NAME_ERROR = true,
  COMMUNITIES_CREATE_DIALOG_NAME_AND_SHORT_NAME_ERROR = true,
  -- templates whose argument holds text (a name, a tab, a recipe, a currency, an event title) are asked for by key
  -- on their surface only (each surface's `only` lists them); matched unrestricted, "%s Recipe" / "%s Begins" /
  -- "Illusion: %s" would take item, quest and spell names (a Lua spec runs every name through the unrestricted match)
  ACHIEVEMENTS_COMPLETED_CATEGORY = true, ACHIEVEMENT_META_COMPLETED_DATE = true, AUCTION_HOUSE_BUYER_FORMAT = true,
  AUCTION_HOUSE_HIGH_BIDDER_FORMAT = true, AUCTION_HOUSE_TIME_LEFT_FORMAT_ACTIVE = true,
  AUCTION_HOUSE_TOOLTIP_DURATION_FORMAT = true, AUCTION_HOUSE_TOOLTIP_MULTIPLE_SELLERS_FORMAT = true,
  AUCTION_HOUSE_TOOLTIP_OVERFLOW_SELLERS_FORMAT = true, AUCTION_HOUSE_TOOLTIP_SELLER_FORMAT = true, AURA_END = true,
  BAG_FILTER_ASSIGNED_TO = true, BANK_TAB_DEPOSIT_ASSIGNMENTS = true, BANK_TAB_EXPANSION_ASSIGNMENT = true,
  BLIZZARD_COMBAT_LOG_MENU_BOTH = true, BLIZZARD_COMBAT_LOG_MENU_INCOMING = true,
  BLIZZARD_COMBAT_LOG_MENU_OUTGOING = true, BLIZZARD_COMBAT_LOG_MENU_OUTGOING_ME = true,
  CALENDAR_ANNOUNCEMENT_CREATEDBY_PLAYER = true, CALENDAR_EVENTNAME_FORMAT_END = true,
  CALENDAR_EVENTNAME_FORMAT_RAID_LOCKOUT = true, CALENDAR_EVENTNAME_FORMAT_RAID_RESET = true,
  CALENDAR_EVENTNAME_FORMAT_START = true, CALENDAR_EVENT_CREATORNAME = true, CALENDAR_EVENT_INVITEDBY_PLAYER = true,
  CALENDAR_RAID_LOCKOUT_DESCRIPTION = true, CALENDAR_RAID_RESET_DESCRIPTION = true,
  CALENDAR_SIGNEDUP_FOR_GUILDEVENT_WITH_STATUS = true, CLICK_BINDING_MACRO_TITLE = true,
  COOLDOWN_VIEWER_SETTINGS_CHARACTER_LAYOUTS_HEADER = true, CRAFTING_ORDER_RECIPE_PROFESSION_FMT = true,
  DISCORD_VALID_SERVER_CHANNEL_LIST = true, DUNGEON_DIFFICULTY_BANNER_TOOLTIP = true, ENCHANTED_TOOLTIP_LINE = true,
  GUILDBANK_REMAINING_MONEY = true, GUILDCONTROL_DISCORD_SETTINGS = true,
  HUD_EDIT_MODE_CHARACTER_LAYOUTS_HEADER = true, ITEM_COMPARISON_SWAP_ITEM_MAINHAND_DESCRIPTION = true,
  ITEM_COMPARISON_SWAP_ITEM_OFFHAND_DESCRIPTION = true, NOT_ENOUGH_CURRENCY = true,
  PROFESSIONS_REQUIRED_TOOLS = true, RAF_RECRUIT_ACTIVITY_DESCRIPTION = true,
  RECENT_ALLY_TOOLTIP_LEVEL_RACE_FORMAT = true, SOCIAL_ENABLE_DISCORD_FUNCTIONALITY = true,
  SOCIAL_QUEUE_FORMAT_BATTLEGROUND = true, TALENTS_LINK_FORMAT = true, TEXT_MODE_A_STRING_RESULT_ABSORB = true,
  TEXT_MODE_A_STRING_RESULT_BLOCK = true, TEXT_MODE_A_STRING_RESULT_OVERKILLING = true,
  TEXT_MODE_A_STRING_RESULT_RESIST = true, TOOLTIP_VIGNETTE_OBJECTIVE_DEFEAT = true,
  TOOLTIP_VIGNETTE_OBJECTIVE_DEFEAT_SHOW_HEALTH = true, TRADESKILL_RECIPE_LEVEL_DROPDOWN_OPTION_FORMAT = true,
  TRANSMOGRIFIED_ENCHANT = true, TRANSMOG_SETS_FAVORITE_WITH_DESCRIPTION = true,
  TRANSMOG_SETS_UNFAVORITE_WITH_DESCRIPTION = true,
  -- combat text trailers (a fragment after a number, asked for by UI/CombatText) are in the list below
  -- the dialogs and the other windows' templates: each surface asks for its own
  -- keys (UI/Popups formats them from the dialog's arguments), so none takes a line by an unrestricted match
  ABANDON_QUEST_CONFIRM = true, ABANDON_QUEST_CONFIRM_WITH_ITEMS = true, ABSORB_TRAILER = true,
  ADDON_ACTION_FORBIDDEN = true, ADDON_PERFORMANCE_SPECIFIC_ERROR_TEXT = true, ANIMA_DIVERSION_CONFIRM_CHANNEL = true,
  ANIMA_DIVERSION_CONFIRM_REINFORCE = true, AREA_SPIRIT_HEAL = true, ARENA_COMPLETE_MESSAGE = true,
  ARTIFACT_RESPEC = true, ARTIFACT_RESPEC_NOT_ENOUGH_POWER = true, BATTLEGROUND_COMPLETE_MESSAGE = true,
  BILLING_NAG_DIALOG = true, BLACK_MARKET_AUCTION_CONFIRMATION = true, BLOCK_INVITES_CONFIRMATION = true,
  BLOCK_TRAILER = true, BROWSER_EXTERNAL_LINK_DIALOG = true, CAA_SAY_PLAYER_RESOURCE_FORMAT_TOOLTIP = true,
  CAA_SAY_PLAYER_RESOURCE_LABEL = true, CAA_SAY_PLAYER_RESOURCE_THROTTLE_TOOLTIP = true,
  CAA_SAY_PLAYER_RESOURCE_TOOLTIP = true, CAA_SAY_PLAYER_RESOURCE_VOICE_TOOLTIP = true,
  CAA_SAY_PLAYER_RESOURCE_VOLUME_TOOLTIP = true, CALENDAR_ERROR_CREATEDATE_AFTER_MAX = true, CAMP_TIMER = true,
  CHANNEL_INVITE = true, CHANNEL_PASSWORD = true, CHAT_INVITE_NOTICE_POPUP = true, CHAT_PASSWORD_NOTICE_POPUP = true,
  CLICK_BINDINGS_BINDING_TEXT_FORMAT = true, CONFIRM_AZERITE_EMPOWERED_ITEM_RESPEC = true,
  CONFIRM_AZERITE_EMPOWERED_ITEM_RESPEC_EXPENSIVE = true, CONFIRM_BATTLEFIELD_ENTRY = true, CONFIRM_BINDER = true,
  CONFIRM_DELETE_EQUIPMENT_SET = true, CONFIRM_DESTROY_COMMUNITY_STREAM_LABEL = true,
  CONFIRM_GARRISON_FOLLOWER_TEMPORARY_ABILITY = true, CONFIRM_GUILD_LEAVE = true, CONFIRM_GUILD_PROMOTE = true,
  CONFIRM_HIGH_COST_ITEM = true, CONFIRM_LEAVE_COMMUNITY_SUBTEXT = true, CONFIRM_LOOT_DISTRIBUTION = true,
  CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL = true, CONFIRM_OVERWRITE_EQUIPMENT_SET = true,
  CONFIRM_PURCHASE_NONREFUNDABLE_ITEM = true, CONFIRM_PURCHASE_TOKEN_ITEM = true,
  CONFIRM_REFUND_MAX_ARENA_POINTS = true, CONFIRM_REFUND_MAX_HONOR = true, CONFIRM_REFUND_MAX_HONOR_AND_ARENA = true,
  CONFIRM_REFUND_TOKEN_ITEM = true, CONFIRM_REMOVE_COMMUNITY_MEMBER_LABEL = true, CONFIRM_SAVE_EQUIPMENT_SET = true,
  CONFIRM_SUMMON = true, CONFIRM_SUMMON_SCENARIO = true, CONFIRM_SUMMON_STARTING_AREA = true,
  COOLDOWN_VIEWER_SETTINGS_DELETE_LAYOUT_DIALOG_TITLE = true,
  COOLDOWN_VIEWER_SETTINGS_ERROR_MAX_ACCOUNT_LAYOUTS = true, COOLDOWN_VIEWER_SETTINGS_ERROR_MAX_CHAR_LAYOUTS = true,
  COOLDOWN_VIEWER_SETTINGS_ERROR_MAX_LAYOUTS = true, COOLDOWN_VIEWER_SETTINGS_RENAME_LAYOUT_DIALOG_TITLE = true,
  CRAFTING_ORDERS_IGNORE_CONFIRMATION = true, DEATH_RELEASE_TIMER = true, DELETE_GOOD_ITEM = true,
  DELETE_GOOD_ITEM_GAMEPAD = true, DELETE_GOOD_QUEST_ITEM = true, DELETE_GOOD_QUEST_ITEM_GAMEPAD = true,
  DELETE_ITEM = true, DELETE_MAIL_CONFIRMATION = true, DELETE_QUEST_ITEM = true, DUEL_OUTOFBOUNDS_TIMER = true,
  DUEL_REQUESTED = true, DUEL_TO_THE_DEATH_CHALLENGE_CONFIRM = true,
  EVENTTRACE_ARG_FMT = true, FPS_COUNTER_CPU_BOUND = true, FPS_COUNTER_GPU_BOUND = true, GARRISON_BOOT_TIMER = true,
  GROUP_FINDER_DELIST_WARNING_SUBTEXT = true, GROUP_FINDER_DELIST_WARNING_TITLE = true,
  GUILD_RENAME_DIALOG_TEXT = true, GUILD_RENAME_REFUND_DIALOG_SUBTEXT = true, GUILD_RENAME_REFUND_DIALOG_TEXT = true,
  HARDCORE_GUILDLEADER_DEATH = true, INSTANCE_BOOT_TIMER = true, INSTANCE_LOCK_TIMER = true,
  INSTANCE_SHUTDOWN_MESSAGE = true, INVITATION = true, LFG_OFFER_CONTINUE = true, LIMITED_CURRENCY_PURCHASE = true,
  LIMITED_CURRENCY_PURCHASE_FINAL = true, LOOT_NO_DROP = true, MAC_INPUT_MONITORING1014 = true,
  MAC_INPUT_MONITORING1015 = true, MAC_OPEN_UNIVERSAL_ACCESS1090 = true, PET_BATTLE_FORFEIT_CONFIRMATION = true,
  PET_BATTLE_PVP_DUEL_REQUESTED = true, PET_RENAME_CONFIRMATION = true, PLUNDERSTORM_LOGOUT_TEXT = true,
  PREMADE_GROUP_INSECURE_SEARCH = true, PROFESSIONS_RECRAFTING_REPLACE_OPTIONAL = true,
  PROFESSION_CONFIRMATION1 = true, PROFESSION_CONFIRMATION2 = true, PROFESSION_RESPEC_CONFIRMATION = true,
  PURCHASE_UNIQUE_AUCTION_CONFIRMATION = true, QUEST_ACCEPT = true, QUEST_ACCEPT_LOG_FULL = true, QUEUED_FOR = true,
  QUIT_TIMER = true, RAF_ACTIVE_LINK_EXPIRE_DATE = true, RAF_EXPENDED_LINK_EXPIRE_DATE = true,
  RAF_FULL_RECRUITS = true, RAF_LINK_REMAINING_USES = true, RAF_NO_ACTIVE_LINK = true, RAF_RECRUITMENT_DESC = true,
  RAF_RECRUITS_FACTION_AND_REALM = true, RAF_REMOVE_RECRUIT_CONFIRM = true, REMOVE_AUTHENTICATOR_FROM_RANK = true,
  REPLACE_ENCHANT = true, REPORT_BATTLEPET_NAME_CONFIRMATION = true, REPORT_PET_NAME_CONFIRMATION = true,
  REPORT_SPAM_CONFIRMATION = true, RESIST_TRAILER = true, RESURRECT_REQUEST = true,
  RESURRECT_REQUEST_NO_SICKNESS = true, SAVED_VARIABLES_TOO_LARGE = true, SETTINGS_TIMED_CONFIRMATION = true,
  SET_FRIENDNOTE_LABEL = true, SL_SET_CONVERSION_MULTIPLE_CHARGES_REMAINING = true,
  SL_SET_CONVERSION_ONE_CHARGE_REMAINING = true, TRADE_POTENTIAL_REMOVE_TRANSMOG = true, TRADE_WITH_QUESTION = true,
  TRANSMOG_CUSTOM_SET_CONFIRM_DELETE = true, TRANSMOG_CUSTOM_SET_CONFIRM_OVERWRITE = true, UNLEARN_SKILL = true,
  UNLEARN_SKILL_GAMEPAD = true, VOTE_BOOT_PLAYER = true, VOTE_BOOT_REASON_REQUIRED = true, WARGAME_CHALLENGED = true,
  WARN_LEAVE_RESTRICTED_CHALLENGE_MODE = true, WEB_ERROR = true, WORLD_PVP_DESERTER = true, WORLD_PVP_ENTER = true,
  WORLD_PVP_EXITED_BATTLE = true, WORLD_PVP_FAIL = true, WORLD_PVP_INVITED = true, WORLD_PVP_INVITED_WARMUP = true,
  WORLD_PVP_LOW_LEVEL = true, WORLD_PVP_NOT_WHILE_IN_RAID = true, WORLD_PVP_PENDING = true,
  WORLD_PVP_PENDING_REMOTE = true, WORLD_PVP_QUEUED = true, WORLD_PVP_QUEUED_WARMUP = true,
}

-- keys whose Japanese belongs to the key alone: one English with its own Japanese on one screen ("Back" on
-- the auction house is 戻る while the Back slot is 背中). An owned key stays out of the by-English index, so it never
-- makes the other key ambiguous and never answers an unrestricted match; it answers matchOnly when the widget's
-- `only` set names it. Plain strings only (no template); of the forms, only `wrapped`. Validate reads this table
-- (validate.ui_own) and leaves owned keys out of its one-Japanese-per-English rule.
UIStrings.OWN = {
  -- the tutorial popup's titles whose English no other key has; "Swimming" is also a spell's name. Only the
  -- popup's title (UI/Tutorial.lua, `only` TUTORIAL_TITLE<n>) may show them, never an unrestricted match
  TUTORIAL_TITLE17 = true, TUTORIAL_TITLE18 = true, TUTORIAL_TITLE28 = true, TUTORIAL_TITLE37 = true,
  TUTORIAL_TITLE46 = true, TUTORIAL_TITLE52 = true,
  -- the PvP scoreboard's two-line column headers ("Damage\nDone"; the one-line English is the header tooltips' title)
  SCORE_DAMAGE_DONE = true, SCORE_HEALING_DONE = true, SCORE_HONORABLE_KILLS = true, SCORE_KILLING_BLOWS = true,
  SCORE_RATING_CHANGE = true,
  -- "Back" (the equipment slot is 背中): the auction house, the quest map, the crafting order form
  AUCTION_HOUSE_BACK_BUTTON = true, BACK = true, PROFESSIONS_CRAFTING_FORM_BACK = true,
  -- "Available" (the friends status is 在席): the auction house column, the trainer filter, a cooldown alert event
  AUCTION_HOUSE_BROWSE_HEADER_QUANTITY = true, AVAILABLE = true, COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_AVAILABLE = true,
  -- "Deposit" (the bank button), "Disabled" (無効 is a turned-off setting), "Exit" (EXIT closes a window)
  AUCTION_HOUSE_DEPOSIT_LABEL = true, LOSS_OF_CONTROL_DISPLAY_PACIFYSILENCE = true, LEAVE_VEHICLE = true,
  -- "Slots" (the bag slot count is スロット数) on the professions filter, "Ground" (the world marker is 地面) on
  -- the mount journal filter
  TRADESKILL_FILTER_SLOTS = true, MOUNT_JOURNAL_FILTER_GROUND = true,
  -- UI/Gamepad: the gamepad footer's "Back" (戻る, not the 背中 slot), the radial's "Point" and "Train" emotes
  -- (the resample-quality option is ポイント, the trainer's button 訓練)
  FRAME_ACTION_BACK = true, RADIAL_LABEL_POINT = true, RADIAL_LABEL_TRAIN = true,
  -- UI/ChatConfig: the combat log's unit filter "Friends" is friendly units (味方), not the friends list (フレンド)
  COMBATLOG_FILTER_STRING_FRIENDLY_UNITS = true,
  -- UI/Crafting: the recipe form's "Reagents:" is crafting materials (素材); in a spell tooltip it is 触媒
  PROFESSIONS_REAGENT_CONTAINER_LABEL = true,
}

-- argument kind → the one fingerprint family it may be shown as
UIStrings.FAMILY_KINDS = { creatureType = "CreatureType", holidayDescription = "HolidayDescription",
  customizationChoice = "CustomizationChoice", customizationSource = "CustomizationSource" }

-- Label forms: only these entries take a value after them ("Sell Price: 5c", "Speed 2.60", "Rank 3"); a line such as
-- "Libram: Cleanse" (a spell name) is never read as "<Libram>: <rest>". A `"<English>: "` prefix entry (Reagents: ,
-- Tools: ) is a label by construction.
-- A value is one form or a list of forms. Forms:
--   colon      "<entry>: <rest>"           number   "<entry> <number>"
--   bareColon  "<entry>:" and nothing more (the paperdoll stat labels are SPELL_STAT1_NAME .. ":")
--   wrapped    "|cAARRGGBB<entry or template>|r" (+ trailing spaces): the same colour around the Japanese
--   binding    "<entry or template> |cffffd200(<key>)|r" (MicroButtonTooltipText): the key binding kept as shown
--   equip      "<ITEM_SPELL_TRIGGER_ONEQUIP> <template>" (a description-run "Equip:" stat line; FORM_PATTERNS)
--   colonPrefix "<entry ending in ':'> <rest>" ("Item Sold: Linen Cloth", "Latency: 45ms"): the rest kept as shown
--   joined     "<template>  <template>" or "<template>  " (the who list's two-space join): both halves filled
--   paragraphs "<entry or template>\n\n<entry or template>…" (the XP bar tooltip joins its help sentence and the rest
--              state): every part must be a `paragraphs` key; any part that is not leaves the whole line English
--   list       "<entry ending in ':'> <item>, <item>…" (the trainer's requirements line): every item that is a
--              `listItem` key is shown in Japanese, every other item (an ability name) as shown
--   icon       "|T…|t <entry>" / "|A…|a <entry>" (a role radio's INLINE_TANK_ICON .. " " .. TANK, the friends
--              status radios): the icon markup kept verbatim in front of the Japanese
--   optionTip  "|cAARRGGBB<entry>|r: |cAARRGGBB<entry>|r" / "|cAARRGGBB<entry>|r:" (a Settings option's
--              "<label>: <tooltip>" line, blizzard_settings.lua:441–457): both halves in Japanese, each colour kept
-- `wrapped` also takes a `number`-form label inside the colour ("|cffffffffStrength 18|r", the paperdoll hovers), and
-- `binding` also takes the pet bar's "|cffffd200 (Ctrl-1)|r" variant with the space inside the colour.
UIStrings.LABELS = { SELL_PRICE = "colon", SPEED = "number", RANK = "number",
  -- paperdoll / pet stat labels ("Strength:")
  SPELL_STAT1_NAME = { "bareColon", "number", "wrapped" }, SPELL_STAT2_NAME = { "bareColon", "number", "wrapped" },
  SPELL_STAT3_NAME = { "bareColon", "number", "wrapped" }, SPELL_STAT4_NAME = { "bareColon", "number", "wrapped" },
  SPELL_STAT5_NAME = { "bareColon", "number", "wrapped" },
  -- inbox expiry ("|cff20ff203 Days |r")
  DAYS_ABBR = "wrapped", HOURS_ABBR = "wrapped", MINUTES_ABBR = "wrapped", SECONDS_ABBR = "wrapped",
  -- tooltip titles built by MicroButtonTooltipText ("Character Info |cffffd200(C)|r")
  CHARACTER_BUTTON = "binding", SPELLBOOK_ABILITIES_BUTTON = "binding", TALENTS = "binding",
  QUESTLOG_BUTTON = "binding", SOCIAL_BUTTON = "binding", GUILD = "binding", WORLDMAP_BUTTON = "binding",
  MAINMENU_BUTTON = "binding", HELP_BUTTON = "binding", BACKPACK_TOOLTIP = "binding", CHARACTER_INFO = "binding",
  PET = "binding", REPUTATION = "binding", SKILLS = "binding", HONOR = "binding", LOOKINGFORGUILD = "binding",
  GUILD_AND_COMMUNITIES = "binding", KEYRING = "binding", LFG_BUTTON = "binding", FRIENDS = "binding",
  WHO = "binding", RAID = "binding",
  PET_ACTION_ATTACK = "binding", PET_ACTION_FOLLOW = "binding", PET_ACTION_WAIT = "binding",
  PET_ACTION_DISMISS = "binding", PET_MODE_AGGRESSIVE = "binding", PET_MODE_DEFENSIVE = "binding",
  PET_MODE_PASSIVE = "binding", PET_MODE_ASSIST = "binding",
  -- stat hover titles ("|cffffffffStrength 18|r") and resistance hovers ("Fire Resistance 5")
  ARMOR = { "number", "wrapped" }, MELEE_ATTACK_POWER = { "number", "wrapped" },
  RANGED_ATTACK_POWER = { "number", "wrapped" }, RESISTANCE2_NAME = "number", RESISTANCE3_NAME = "number",
  RESISTANCE4_NAME = "number", RESISTANCE5_NAME = "number", RESISTANCE6_NAME = "number",
  GROUP = "number", RAID_INSTANCE_EXPIRES_EXPIRED = "wrapped", MAINMENUBAR_LATENCY_LABEL = "colonPrefix",
  WHO_FRAME_TOTAL_TEMPLATE = "joined", WHO_FRAME_SHOWN_TEMPLATE = "joined",
  NEWBIE_TOOLTIP_XPBAR = "paragraphs", EXHAUST_TOOLTIP1 = "paragraphs", -- ExpBarOverrides.lua:23–27
  -- the camelot Spirit tooltip and the sitting warning joined after it (paperdollframestats.lua:283)
  DEFAULT_SPIRIT_TOOLTIP = "paragraphs", SPIRIT_STANDING_WARNING = "paragraphs",
  SPELLBOOK = "binding", PET_TYPE_PET = "binding", PET_TYPE_DEMON = "binding", -- spellbook tab tooltips (xml:43–45)
  -- Forever's (mainline family) micro-button titles via MicroButtonTooltipText ("Professions |cffffd200(K)|r")
  PROFESSIONS_BUTTON = "binding", PLAYERSPELLS_BUTTON = "binding", SPELLBOOK_BUTTON = "binding",
  ACHIEVEMENT_BUTTON = "binding", LEGACY_BUTTON = "binding", HOUSING_MICRO_BUTTON = "binding",
  DUNGEONS_BUTTON = "binding", COLLECTIONS = "binding", ENCOUNTER_JOURNAL = "binding", ADVENTURE_JOURNAL = "binding",
  REQUIRES_LABEL = "list", TRAINER_REQ_LEVEL = "listItem", TRAINER_REQ_LEVEL_RED = "listItem",
  TRAINER_REQ_SKILL_RANK = "listItem", TRAINER_REQ_SKILL_RANK_RED = "listItem",
  -- mail invoice labels joined to an item or player name ("Item Sold: Linen Cloth")
  ITEM_SOLD_COLON = "colonPrefix", ITEM_PURCHASED_COLON = "colonPrefix", SOLD_BY_COLON = "colonPrefix",
  PURCHASED_BY_COLON = "colonPrefix",
  -- the club finder's disabled notice, red-wrapped (camelot blizzard_communities/clubfinder.xml:1249–1251)
  COMMUNITY_FEATURE_UNAVAILABLE_MUTED = "wrapped", COMMUNITY_FEATURE_UNAVAILABLE_SILENCED = "wrapped",
  -- the trainer filter menu's colour-wrapped checkboxes (mainline/blizzard_trainerui.lua:252–254); AVAILABLE
  -- owns its Japanese (OWN: it shares "Available" with the friends status)
  AVAILABLE = "wrapped", UNAVAILABLE = "wrapped", USED = "wrapped",
  -- the dressing room's custom-set dropdown: its grey empty text and its green menu entry
  -- (blizzard_framexml/wardrobecustomsets.lua:22, 144)
  TRANSMOG_CUSTOM_SET_NONE = "wrapped", TRANSMOG_CUSTOM_SET_NEW = "wrapped",
  -- the Click Cast Bindings prompts, green- or red-wrapped (blizzard_clickbindingui.lua:216–222)
  CLICK_BINDINGS_NEW_EMPTY_PROMPT = "wrapped", CLICK_BINDINGS_SET_BINDING_PROMPT = "wrapped",
  CLICK_BINDINGS_UNBOUND_TEXT = "wrapped",
  -- the Battle.net toast's online line, grey-wrapped around its own green word
  -- (blizzard_bnet/mainline/bnet.lua:237)
  BN_TOAST_ONLINE = "wrapped",
  -- an empty key slot on the key bindings page, grey-wrapped (blizzard_sharedxml/bindingutil.lua:228)
  NOT_BOUND = "wrapped",
  -- colour-wrapped Communities menu entries (clubfinder.lua:1101–1102; clubfinderapplicantlist.lua:69–70;
  -- communitiesstreams.lua:89–90)
  CLUB_FINDER_REAPPLY = "wrapped", CLUB_FINDER_INVITE_APPLICANT_REDO = "wrapped",
  COMMUNITIES_CREATE_CHANNEL = "wrapped",
  -- ADR-030
  TRADEFRAME_NOT_MODIFIED_TEXT = "wrapped", TRIAL_RESTRICTED = "wrapped",
  VIDEO_OPTIONS_COMBAT_CUES_DISABLED_WARNING = "wrapped", VOICE_TOOLTIP_DEAFEN = "binding",
  VOICE_TOOLTIP_UNDEAFEN = "binding", VOICE_TOOLTIP_MUTE_MIC = "binding", VOICE_TOOLTIP_UNMUTE_MIC = "binding",
  -- UI/Gamepad: the persistent controller legend's white-wrapped headers
  -- (gamepadpersistentinputlegend.lua:341, 369, 389, 429) and the skip button's held countdown, "Skip 2"
  -- (consoletemplates.lua:143)
  PROMPT_FRIENDLY_TARGETING_ACTIONS = "wrapped", PROMPT_HOSTILE_TARGETING_ACTIONS = "wrapped",
  PROMPT_SHORTCUT_ACTIONS = "wrapped", PROMPT_INSPECT_HUD = "wrapped", SKIP = "number",
}

-- Forms granted by key pattern rather than one by one.
UIStrings.FORM_PATTERNS = { equip = { "^ITEM_MOD_" } }
