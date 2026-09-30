-- UI/MenusTags.lua: the menu tags of every other Forever window (data; loaded after UI/Menus, it adds them to
-- Menus.TAGS before Menus.init registers one Menu.ModifyMenu callback per tag, so Menus.lua stays one mechanism).
-- Paths under the Forever UI extract's interface/addons. Each tag lists the keys its entries may show (`only`: a
-- player's layout, a creature's, an item's or a channel's name in the same menu is never read as a dictionary word,
-- names stay in English); `tooltips` are the keys an element's own hover may show: a disabled entry's reason (its
-- title is the entry's English again, MenuUtil.GetElementText) and the gear / cancel / play-sample utility buttons'
-- hovers (UI/Menus registers the element's attached buttons too, blizzard_menu/menutemplates.lua:586–649).
-- `titleIsName`: the generator's first element is a name (an achievement's, a tracked block's). `show`: a line the
-- `only` match cannot take whole (UI/DamageMeter's session name with its duration).
-- A template entry ("%s Specific") matches through its Core/UIStrings ARGS kinds; names inside stay as written.
local _, WFJ = ...

local FAVORITE = { "BATTLE_PET_FAVORITE", "BATTLE_PET_UNFAVORITE" }
local SET_FAVORITE = { "TRANSMOG_ITEM_SET_FAVORITE", "TRANSMOG_ITEM_UNSET_FAVORITE" }
local FILTER_ALL = { "CHECK_ALL", "UNCHECK_ALL", "SOURCES" }
-- the alert entry's utility buttons (blizzard_cooldownviewer/cooldownviewersettingsalerts.lua:193–245)
local ALERT_BUTTONS = { "COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_TOOLTIP_EDIT",
  "COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_BUTTON_TOOLTIP_DELETE", "COOLDOWN_VIEWER_SETTINGS_ALERT_MENU_PLAY_SAMPLE" }

local function join(...)
  local out = {}
  for _, list in ipairs({ ... }) do for _, key in ipairs(list) do out[#out + 1] = key end end
  return out
end

local TAGS = {
  -- the Cooldown Manager settings (blizzard_cooldownviewer/cooldownviewersettings.lua): the gear menu (:943), an
  -- item's context menu (alerts, category moves: the category's title is a `text` argument, :346, :100–105), the
  -- layout dropdown (a layout's name is no key; the character header is class-coloured around the character's name,
  -- :1086–1200); the group buff filter's item menu (groupbufffilter.lua:426)
  COOLDOWN_VIEWER_SETTINGS_MENU = { source = "cooldownviewersettings.lua:943", keys = {
    "COOLDOWN_VIEWER_SETTINGS_SHOW_UNLEARNED", "COOLDOWN_VIEWER_SETTINGS_RESET_LAYOUT_TO_DEFAULT",
    "COOLDOWN_VIEWER_SETTINGS_SHOW_OPTIONS", "HUD_EDIT_MODE_MENU" } },
  MENU_COOLDOWN_SETTINGS_ITEM = { source = "cooldownviewersettings.lua:346", keys = {
    "COOLDOWN_VIEWER_SETTINGS_ADD_NEW_ALERT", "COOLDOWN_VIEWER_SETTINGS_ADD_ALERT",
    "COOLDOWN_VIEWER_SETTINGS_CLEAR_ALL_ALERTS", "COOLDOWN_VIEWER_SETTINGS_ASSIGN_TO_CATEGORY",
    "COOLDOWN_VIEWER_SETTINGS_ASSIGN_TO_EMPTY_CATEGORY" },
    tooltips = join({ "COOLDOWN_VIEWER_SETTINGS_ADD_ALERT", "COOLDOWN_VIEWER_SETTINGS_ASSIGN_TO_CATEGORY",
      "COOLDOWN_VIEWER_SETTINGS_ASSIGN_TO_EMPTY_CATEGORY",
      "COOLDOWN_VIEWER_SETTINGS_ADD_ALERT_TOOLTIP_DISABLED_TOO_MANY", "COOLDOWN_VIEWER_SETTINGS_ACTION_ADD_ALERT",
      "COOLDOWN_VIEWER_SETTINGS_ADD_ALERT_TOOLTIP_DISABLED_NO_VALID" },
      ALERT_BUTTONS) },
  MENU_COOLDOWN_SETTINGS_LAYOUTS = { source = "cooldownviewersettings.lua:1086", keys = {
    "COOLDOWN_VIEWER_SETTINGS_CHARACTER_LAYOUTS_HEADER", "COOLDOWN_VIEWER_SETTINGS_COPY_LAYOUT",
    "COOLDOWN_VIEWER_SETTINGS_RENAME_LAYOUT", "COOLDOWN_VIEWER_SETTINGS_USE_STARTER_LAYOUT",
    "HUD_EDIT_MODE_NEW_LAYOUT", "HUD_EDIT_MODE_NEW_LAYOUT_DISABLED", "COOLDOWN_VIEWER_SETTINGS_COPY_TO_CLIPBOARD" },
    tooltips = { "COOLDOWN_VIEWER_SETTINGS_ERROR_CANNOT_SWITCH_TO_LAYOUT",
      "COOLDOWN_VIEWER_SETTINGS_ERROR_CANNOT_SWITCH_TO_LAYOUT_TOOLTIP_LINE",
      "COOLDOWN_VIEWER_SETTINGS_COPY_TO_CLIPBOARD",
      "COOLDOWN_VIEWER_SETTINGS_ERROR_CANNOT_COPY_DEFAULT_LAYOUT",
      "COOLDOWN_VIEWER_SETTINGS_ERROR_CANNOT_COPY_DEFAULT_LAYOUT_LINE", "COOLDOWN_VIEWER_SETTINGS_COPY_LAYOUT",
      "HUD_EDIT_MODE_NEW_LAYOUT_DISABLED", "HUD_EDIT_MODE_UNSAVED_CHANGES", "HUD_EDIT_MODE_ERROR_COPY_MAX_LAYOUTS",
      "COOLDOWN_VIEWER_SETTINGS_RENAME_OR_COPY_LAYOUT", "COOLDOWN_VIEWER_SETTINGS_DELETE_LAYOUT" } },
  MENU_GROUP_BUFF_FILTER_ITEM = { source = "groupbufffilter.lua:426", keys = { "GROUP_BUFF_FILTER_NEW_VISUAL_ALERT",
    "GROUP_BUFF_FILTER_MOVE_TO_HIDDEN", "GROUP_BUFF_FILTER_MOVE_TO_SHOWN" }, tooltips = ALERT_BUTTONS },
  -- achievements: the filter (each radio's hover is a title + its explanation, mainline/blizzard_achievementui.lua:
  -- 277–285, 56–57, 2006–2010) and the tracker's block menu, titled with the achievement's name
  -- (blizzard_objectivetracker/blizzard_achievementobjectivetracker.lua:75–85)
  MENU_ACHIEVEMENT_FILTER = { source = "blizzard_achievementui.lua:277", keys = { "ACHIEVEMENTFRAME_FILTER_ALL",
    "ACHIEVEMENTFRAME_FILTER_COMPLETED", "ACHIEVEMENTFRAME_FILTER_INCOMPLETE" },
    tooltips = { "ACHIEVEMENT_FILTER_TITLE", "ACHIEVEMENT_FILTER_ALL_EXPLANATION",
      "ACHIEVEMENT_FILTER_COMPLETE_EXPLANATION", "ACHIEVEMENT_FILTER_INCOMPLETE_EXPLANATION" } },
  MENU_ACHIEVEMENT_TRACKER = { source = "blizzard_achievementobjectivetracker.lua:75", titleIsName = true,
    keys = { "OBJECTIVES_VIEW_ACHIEVEMENT" } },
  -- the content-tracking block menu, titled with the tracked thing's name (blizzard_adventureobjectivetracker.lua:70)
  MENU_OBJECTIVE_TRACKER = { source = "blizzard_adventureobjectivetracker.lua:70", titleIsName = true,
    keys = { "CONTENT_TRACKING_OPEN_JOURNAL_OPTION" } },
  -- the auction house: an item's favourite menu (shared/blizzard_auctionhousesharedtemplates.lua:3) and the search
  -- filter (shared/blizzard_auctionhousesearchbar.lua:141–175; the quality entries are colour-wrapped
  -- ITEM_QUALITY<n>_DESC, classic/blizzard_auctionhouseutil.lua:1–16)
  MENU_AUCTION_HOUSE_FAVORITE = { source = "blizzard_auctionhousesharedtemplates.lua:3",
    keys = { "AUCTION_HOUSE_DROPDOWN_SET_FAVORITE", "AUCTION_HOUSE_DROPDOWN_REMOVE_FAVORITE" } },
  MENU_AUCTION_HOUSE_SEARCH_FILTER = { source = "blizzard_auctionhousesearchbar.lua:141", keys = {
    "AUCTION_HOUSE_FILTER_DROP_DOWN_LEVEL_RANGE", "AUCTION_HOUSE_FILTER_CATEGORY_EQUIPMENT",
    "AUCTION_HOUSE_FILTER_CATEGORY_RARITY", "AUCTION_HOUSE_FILTER_UNCOLLECTED_ONLY",
    "AUCTION_HOUSE_FILTER_USABLE_ONLY", "AUCTION_HOUSE_FILTER_UPGRADES_ONLY",
    "AUCTION_HOUSE_FILTER_CURRENTEXPANSION_ONLY", "AUCTION_HOUSE_FILTER_RUNECARVING", "ITEM_QUALITY0_DESC",
    "ITEM_QUALITY1_DESC", "ITEM_QUALITY2_DESC", "ITEM_QUALITY3_DESC", "ITEM_QUALITY4_DESC", "ITEM_QUALITY5_DESC" } },
  -- the battlefield map's options (mainline/blizzard_battlefieldmap.lua:49–80)
  MENU_BATTLEFIELD_MAP = { source = "blizzard_battlefieldmap.lua:49", keys = { "SHOW_BATTLEFIELDMINIMAP_PLAYERS",
    "LOCK_BATTLEFIELDMINIMAP", "BATTLEFIELDMINIMAP_OPACITY_LABEL" } },
  -- the calendar: a day's context menu and an invitee's (mainline/blizzard_calendar.lua:2199–2290, 3890–3920)
  MENU_CALENDAR_DAY = { source = "blizzard_calendar.lua:2199", keys = { "CALENDAR_CREATE_EVENT",
    "CALENDAR_CREATE_GUILD_EVENT", "CALENDAR_CREATE_GUILD_ANNOUNCEMENT", "CALENDAR_CREATE_COMMUNITY_EVENT",
    "CALENDAR_COPY_EVENT", "CALENDAR_PASTE_EVENT", "CALENDAR_SIGNUP", "CALENDAR_ACCEPT_INVITATION",
    "CALENDAR_TENTATIVE_INVITATION", "CALENDAR_DECLINE_INVITATION", "CALENDAR_REMOVE_INVITATION", "REPORT_CALENDAR" } },
  MENU_CALENDAR_CREATE_INVITE = { source = "blizzard_calendar.lua:3890", keys = { "REMOVE",
    "CALENDAR_INVITELIST_CLEARMODERATOR", "CALENDAR_INVITELIST_SETMODERATOR", "CALENDAR_INVITELIST_SETINVITESTATUS",
    "CALENDAR_INVITELIST_INVITETORAID" } },
  -- the combat log's unit / spell context menu: the unit or spell name is a `text` argument
  -- (mainline/blizzard_combatlog.lua:1491–1507, 470–520, 1100–1145)
  MENU_COMBAT_LOG = { source = "blizzard_combatlog.lua:1493", keys = { "BLIZZARD_COMBAT_LOG_MENU_BOTH",
    "BLIZZARD_COMBAT_LOG_MENU_INCOMING", "BLIZZARD_COMBAT_LOG_MENU_OUTGOING", "BLIZZARD_COMBAT_LOG_MENU_OUTGOING_ME",
    "BLIZZARD_COMBAT_LOG_MENU_EVERYTHING", "BLIZZARD_COMBAT_LOG_MENU_SAVE", "BLIZZARD_COMBAT_LOG_MENU_RESET",
    "BLIZZARD_COMBAT_LOG_MENU_SPELL_LINK", "BLIZZARD_COMBAT_LOG_MENU_SPELL_HIDE" } },
  -- the damage meter's session, settings and tracked-type menus (blizzard_damagemeter/damagemetersessionwindow.lua:
  -- 384–393, 415–436, 468–520); a combat session is "Combat 3 [01:23]" (or an encounter's name + duration)
  MENU_DAMAGE_METER_SESSIONS = { source = "damagemetersessionwindow.lua:415", keys = { "DAMAGE_METER_COMBAT_NUMBER",
    "DAMAGE_METER_CURRENT_SESSION", "DAMAGE_METER_OVERALL_SESSION" },
    show = function(...) return WFJ.DamageMeter and WFJ.DamageMeter.showSession(...) or 0 end },
  MENU_DAMAGE_METER_WINDOW_SETTINGS = { source = "damagemetersessionwindow.lua:468", keys = {
    "DAMAGE_METER_OPEN_SETTINGS", "DAMAGE_METER_OPEN_EDIT_MODE", "DAMAGE_METER_LOCK_WINDOW",
    "DAMAGE_METER_UNLOCK_WINDOW", "DAMAGE_METER_MAKE_UNINTERACTABLE", "DAMAGE_METER_MAKE_INTERACTABLE",
    "DAMAGE_METER_RESET_ALL_SESSIONS", "DAMAGE_METER_HIDE_WINDOW", "DAMAGE_METER_SHOW_NEW_WINDOW" } },
  MENU_DAMAGE_METER_WINDOW_TRACKED_TYPE = { source = "damagemetersessionwindow.lua:384", keys = {
    "DAMAGE_METER_CATEGORY_DAMAGE", "DAMAGE_METER_CATEGORY_HEALING", "DAMAGE_METER_CATEGORY_ACTIONS",
    "DAMAGE_METER_TYPE_DAMAGE_DONE", "DAMAGE_METER_TYPE_HEALING_DONE", "DAMAGE_METER_TYPE_ABSORBS",
    "DAMAGE_METER_TYPE_INTERRUPTS", "DAMAGE_METER_TYPE_DISPELS", "DAMAGE_METER_TYPE_DAMAGE_TAKEN",
    "DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN", "DAMAGE_METER_TYPE_DEATHS", "DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN" } },
  -- Event Trace's filter menu (blizzard_eventtrace/blizzard_eventtrace.lua:464–534)
  MENU_EVENT_TRACE_FILTER = { source = "blizzard_eventtrace.lua:464", keys = { "EVENTTRACE_APPLY_DEFAULT_FILTER",
    "EVENTTRACE_LOG_WHEN_HIDDEN", "EVENTTRACE_SHOW_ARGUMENTS", "EVENTTRACE_SHOW_TIMESTAMP",
    "EVENTTRACE_SHOW_SECRET_VALUES", "EVENTTRACE_LOG_CR_EVENTS" } },
  -- master loot: the title, the assign submenu (class and player names are no keys), the roll request
  -- (mainline/grouplootframe.lua:202–256)
  MENU_GROUP_LOOT = { source = "grouplootframe.lua:202", keys = { "MASTER_LOOTER", "ASSIGN_LOOT", "REQUEST_ROLL" } },
  -- the battleground map's AFK report menu: player names between the title and the "all" entry
  -- (blizzard_sharedmapdataproviders/groupmembersdataprovider.lua:167–184)
  MENU_GROUP_MEMBERS_PIN = { source = "groupmembersdataprovider.lua:167", keys = { "PVP_REPORT_AFK",
    "PVP_REPORT_AFK_ALL" } },
  -- guild control's page dropdown; the Discord page's `%s` is CreateAtlasMarkup(…), a `text` argument kept verbatim
  -- (blizzard_guildcontrolui/blizzard_guildcontrolui.lua:62–74)
  MENU_GUILD_PERMISSIONS = { source = "blizzard_guildcontrolui.lua:62", keys = { "GUILDCONTROL_GUILDRANKS",
    "GUILDCONTROL_RANK_PERMISSIONS", "GUILDCONTROL_BANK_PERMISSIONS", "GUILDCONTROL_DISCORD_SETTINGS" } },
  -- collections: filters (source / expansion names are client-table names, no keys) and favourite menus
  -- (blizzard_collections/mainline/blizzard_heirloomcollection.lua:127; mainline/blizzard_mountcollection.lua:192,
  -- 982; classic/blizzard_petcollection.lua:100, 350; mainline/blizzard_toybox.lua:116, 265)
  MENU_HEIRLOOMS_FILTER = { source = "blizzard_heirloomcollection.lua:127",
    keys = join({ "COLLECTED", "NOT_COLLECTED" }, FILTER_ALL) },
  MENU_MOUNT_COLLECTION_FILTER = { source = "blizzard_mountcollection.lua:982", keys = join({ "COLLECTED",
    "NOT_COLLECTED", "MOUNT_JOURNAL_FILTER_UNUSABLE", "MOUNT_JOURNAL_FILTER_TYPE", "MOUNT_JOURNAL_FILTER_FLYING",
    "MOUNT_JOURNAL_FILTER_AQUATIC", "MOUNT_JOURNAL_FILTER_DRAGONRIDING", "MOUNT_JOURNAL_FILTER_RIDEALONG",
    "MOUNT_JOURNAL_FILTER_GROUND" },
    FILTER_ALL) },
  MENU_MOUNT_COLLECTION_MOUNT = { source = "blizzard_mountcollection.lua:192",
    keys = join({ "UNWRAP", "BINDING_NAME_DISMOUNT", "MOUNT" }, FAVORITE) },
  MENU_PET_COLLECTION_FILTER = { source = "classic/blizzard_petcollection.lua:100",
    keys = { "COLLECTED", "NOT_COLLECTED" } },
  MENU_PET_COLLECTION_PET = { source = "classic/blizzard_petcollection.lua:350",
    keys = join({ "UNWRAP", "PET_DISMISS", "BATTLE_PET_SUMMON" }, FAVORITE) },
  MENU_TOYBOX_FILTER = { source = "blizzard_toybox.lua:116", keys = join({ "COLLECTED", "NOT_COLLECTED",
    "PET_JOURNAL_FILTER_USABLE_ONLY", "EXPANSION_FILTER_TEXT" }, FILTER_ALL) },
  MENU_TOYBOX_FAVORITE = { source = "blizzard_toybox.lua:265", keys = FAVORITE },
  -- warband scenes: camelot never runs this generator; kept so the favourite keys' tag list is whole
  -- (blizzard_sharedxml/mainline/sharedcollectiontemplates.lua:7)
  MENU_WARBANDSCENE_FAVORITE = { source = "sharedcollectiontemplates.lua:7", keys = FAVORITE },
  -- professions: the camelot filter (the skill-up and makeable checkboxes; "Slots" stays English;
  -- blizzard_professionstemplates/camelot/blizzard_professions.lua:1–14), the recipe list's favourite menu
  -- (blizzard_professionsrecipelist.lua:65), the recipe level radios ("Level %d", blizzard_professionsrecipelevel.lua:
  -- 90), the link button's channel menu (only its title: player-named channels are listed beside Guild / Party / Raid,
  -- blizzard_professionscrafting.lua:367–395), the crafter orders page (camelot has none, :76) and the tracker
  -- (blizzard_objectivetracker/blizzard_professionsrecipetracker.lua:59)
  MENU_PROFESSIONS_FILTER = { source = "camelot/blizzard_professions.lua:2",
    keys = { "TRADESKILL_FILTER_HAS_SKILL_UP", "CRAFT_IS_MAKEABLE", "TRADESKILL_FILTER_SLOTS" } },
  MENU_PROFESSIONS_RECIPE_LIST_FAVORITE = { source = "blizzard_professionsrecipelist.lua:65", keys = FAVORITE },
  MENU_PROFESSIONS_RECIPE_LEVEL = { source = "blizzard_professionsrecipelevel.lua:90",
    keys = { "TRADESKILL_RECIPE_LEVEL_DROPDOWN_OPTION_FORMAT" } },
  MENU_PROFESSIONS_CRAFTING_PAGE = { source = "blizzard_professionscrafting.lua:367", keys = { "TRADESKILL_POST" } },
  MENU_PROFESSIONS_CRAFTER_ORDER = { source = "blizzard_professionscrafterorderpage.lua:76", keys = FAVORITE },
  MENU_PROFESSIONS_RECIPE_TRACKER = { source = "blizzard_professionsrecipetracker.lua:59",
    keys = { "PROFESSIONS_TRACKING_VIEW_RECIPE", "PROFESSIONS_UNTRACK_RECIPE" } },
  -- crafting orders (blizzard_professionscustomerorders): the browse filter (…browseorders.lua:100–130), the
  -- listing duration (…ordersform.lua:592) and the crafter's social menu (no title); a disabled entry's hover says
  -- why, the crafter's name a `text` argument of ALREADY_FRIEND_FMT (…ordersform.lua:243–325)
  MENU_PROFESSIONS_CUSTOMER_ORDER_BROWSE = { source = "blizzard_professionscustomerordersbrowseorders.lua:100",
    keys = { "AUCTION_HOUSE_FILTER_DROP_DOWN_LEVEL_RANGE", "AUCTION_HOUSE_FILTER_CATEGORY_EQUIPMENT",
      "AUCTION_HOUSE_FILTER_CATEGORY_RARITY", "AUCTION_HOUSE_FILTER_UNCOLLECTED_ONLY",
      "AUCTION_HOUSE_FILTER_USABLE_ONLY", "AUCTION_HOUSE_FILTER_UPGRADES_ONLY",
      "AUCTION_HOUSE_FILTER_CURRENTEXPANSION_ONLY" } },
  MENU_PROFESSIONS_CUSTOMER_ORDER_DURATION = { source = "blizzard_professionscustomerordersform.lua:592", keys = {
    "PROFESSIONS_LISTING_DURATION_ONE", "PROFESSIONS_LISTING_DURATION_TWO", "PROFESSIONS_LISTING_DURATION_THREE" } },
  MENU_PROFESSIONS_CUSTOMER_ORDER_FORM = { source = "blizzard_professionscustomerordersform.lua:245",
    keys = { "WHISPER_MESSAGE", "ADD_CHARACTER_FRIEND", "IGNORE" },
    tooltips = { "PROF_ORDER_CANT_WHISPER_OFFLINE", "PROF_ORDER_CANT_WHISPER_WRONG_FACTION", "ALREADY_FRIEND_FMT",
      "PROF_ORDER_CANT_ADD_FRIEND_OFFLINE", "PROF_ORDER_CANT_ADD_FRIEND_WRONG_FACTION",
      "PROF_ORDER_CANT_IGNORE_ALREADY_IGNORED" } },
  -- the compact raid frame manager's difficulty radios (mainline/blizzard_compactraidframemanager.lua:215–256)
  MENU_RAID_FRAME_DIFFICULTY = { source = "blizzard_compactraidframemanager.lua:215",
    keys = { "PLAYER_DIFFICULTY1", "PLAYER_DIFFICULTY2", "PLAYER_DIFFICULTY6" } },
  -- the transmogrifier (blizzard_transmog/blizzard_transmogtemplates.lua:32, 488, 1503, 1706; blizzard_transmog.lua:
  -- 2676): option names are client-table names; a custom set's delete is red-wrapped
  MENU_TRANSMOG_OUTFIT_ENTRY = { source = "blizzard_transmogtemplates.lua:32", keys = { "TRANSMOG_EDIT_OUTFIT_SLOT" } },
  MENU_TRANSMOG_OPTIONS = { source = "blizzard_transmogtemplates.lua:488",
    keys = { "TRANSMOG_ARTIFACT_OPTIONS_HEADER" } },
  MENU_TRANSMOG_SETS_MODEL_FILTER = { source = "blizzard_transmogtemplates.lua:1503",
    keys = join(SET_FAVORITE, { "TRANSMOG_SET_OPEN_COLLECTION" }) },
  MENU_TRANSMOG_CUSTOM_SETS_MODEL_FILTER = { source = "blizzard_transmogtemplates.lua:1706", keys = {
    "TRANSMOG_CUSTOM_SET_DRESSING_ROOM", "TRANSMOG_CUSTOM_SET_RENAME", "TRANSMOG_CUSTOM_SET_REPLACE",
    "TRANSMOG_CUSTOM_SET_DELETE" } },
  MENU_TRANSMOG_SETS_FILTER = { source = "blizzard_transmog.lua:2676", keys = { "COLLECTED", "NOT_COLLECTED",
    "TRANSMOG_SET_PVE", "TRANSMOG_SET_PVP" } },
  -- the wardrobe (blizzard_collections/mainline/blizzard_wardrobe.lua:101; shared/blizzard_wardrobe_sets.lua:566,
  -- 938; blizzard_transmogshared/blizzard_transmogshared.lua:695); a set's description is a `text` argument
  MENU_WARDROBE_BASE_SETS_FILTER = { source = "blizzard_wardrobe.lua:101", keys = { "COLLECTED", "NOT_COLLECTED",
    "TRANSMOG_SET_PVE", "TRANSMOG_SET_PVP" } },
  MENU_WARDROBE_SETS_SET = { source = "blizzard_wardrobe_sets.lua:566", keys = join(SET_FAVORITE, {
    "TRANSMOG_SETS_FAVORITE_WITH_DESCRIPTION", "TRANSMOG_SETS_UNFAVORITE_WITH_DESCRIPTION" }) },
  MENU_WARDROBE_SETS_SET_DETAIL = { source = "blizzard_wardrobe_sets.lua:938", keys = SET_FAVORITE },
  MENU_WARDROBE_ITEMS_MODEL_FILTER = { source = "blizzard_transmogshared.lua:695", keys = SET_FAVORITE },
  -- the gamepad "more actions" menu: each entry a prompted binding's label (blizzard_gamepadsharedutility/
  -- promptedbindings/promptedbinding.lua:43–58, 126–181, 205–238; the generator tags it, :140); plus the
  -- gamepad CONTEXT_ACTION_LABEL_* / ACTION_LABEL_*_SET words (UI/Gamepad.MENU_KEYS, appended below)
  MORE_CONTEXT_ACTIONS = { source = "promptedbinding.lua:212", keys = { "ADD_FAVORITE_STATUS", "REMOVE_FAVORITE_STATUS",
    "BUTTON_LAG_AUCTIONHOUSE", "CONTEXT_ACTION_LABEL_SEE_IN_BAG", "SOCIAL_SHARE_TEXT", "PROFESSIONS_TRACK_RECIPE",
    "PROFESSIONS_UNTRACK_RECIPE" } },
}
for _, key in ipairs(WFJ.Gamepad and WFJ.Gamepad.MENU_KEYS or {}) do
  table.insert(TAGS.MORE_CONTEXT_ACTIONS.keys, key)
end

-- Keys added to tags UI/Menus already declares (appended below)
local EXTRA = {
  -- the character-layouts header, class-coloured around the character's name (editmodemanager.lua:8)
  MENU_EDIT_MODE_MANAGER = { keys = { "HUD_EDIT_MODE_CHARACTER_LAYOUTS_HEADER" } },
  -- queues the camelot client may show (queuestatusframe.lua:1276–1507) [in game: runtime-gated]
  MENU_QUEUE_STATUS_FRAME = { keys = { "ENTER_PET_BATTLE", "LEAVE_ARENA", "SURRENDER_ARENA", "WOW_LABS_LEAVE_QUEUE",
    "LEAVE_ZONE" } },
  -- the world-quest filters (blizzard_worldmaptemplates.lua:277, 293, 339–341) [in game: world-quest filters]
  MENU_WORLD_MAP_TRACKING = { keys = { "SHOW_WORLD_QUESTS_ON_MAP_TEXT", "SHOW_PRIMARY_PROFESSION_ON_MAP_TEXT",
    "SHOW_SECONDARY_PROFESSION_ON_MAP_TEXT", "WORLD_MAP_FILTER_LABEL_WORLD_QUESTS_SUBMENU_TYPE",
    "WORLD_QUEST_REWARD_FILTERS_TITLE" },
    tooltips = { "WORLD_QUESTS_FILTER_DESCRIPTION", "SHOW_WORLD_QUESTS_ON_MAP_TEXT",
      "SHOW_PRIMARY_PROFESSION_ON_MAP_TEXT", "SHOW_SECONDARY_PROFESSION_ON_MAP_TEXT" } },
}

local menus = WFJ.Menus.TAGS
for tag, spec in pairs(TAGS) do menus[tag] = spec end
for tag, extra in pairs(EXTRA) do
  local spec = menus[tag]
  for _, field in ipairs({ "keys", "tooltips" }) do
    if spec and extra[field] then spec[field] = join(spec[field] or {}, extra[field]) end
  end
end
