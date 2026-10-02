-- UI/Menus.lua: dropdown and context-menu entries of the hooked windows (ADR-031).
-- The Menu system builds a menu from a generator, then runs every callback registered with Menu.ModifyMenu for the
-- description's tag (Menu.PopulateDescription → SecureModifyMenu; ModifyMenu also replays on a description already
-- generated) [verified: blizzard_menu/menu.lua:2708–2745]. The callback adds an initializer to each element
-- description, recursively into submenus [menu.lua:418–423, 443]; the compositor runs it on the element's frame after
-- the client's own initializers wrote the text into frame.fontString [menuvariants.lua:9–22; menuutil.lua:198–204 for
-- a title], and before the menu is laid out, so the menu is measured with the Japanese. A resetter drops the record
-- when the frame goes back to the pool [menu.lua:455]. UI/SpellBook keeps its own settings-menu hook (the second copy
-- of this pattern; a third would be extracted).
-- Each tag lists the keys its entries may show: a widget only ever takes one of them (`only`), so a rank name, a bag
-- the player named or a quest title in a menu is never read as a dictionary word (names stay in English). Tooltip
-- keys are shown through UI/HelpTooltip on the element's own owner (a disabled radio's reason, GUILD_RANK_UNAVAILABLE).
-- A tag whose menu title is a name (a unit's, a channel's) sets `titleIsName`: its first root element (the title the
-- generator creates first) never gets our initializer, and no element whose text is the menu's name
-- (contextData.name) is ever matched, so a player named "Duel" stays "Duel".
local _, WFJ = ...
local Menus = {}
WFJ.Menus = Menus

local SURFACE = "help.menus" -- a help-family record surface: the menus belong to the windows that open them
Menus.SURFACE = SURFACE

local Compat = WFJ.Compat

-- the unit right-click menus' keys are data in UI/MenusUnit.lua, so this file stays one mechanism
local UNIT = WFJ.MenusUnit
-- the chat shortcut entries (the slash command beside each is its own FontString, untouched; emote and language
-- submenu entries are slash commands and language names, never listed)
local CHAT_SHORTCUT_KEYS = { "SAY_MESSAGE", "PARTY_MESSAGE", "RAID_MESSAGE", "INSTANCE_CHAT_MESSAGE",
  "GUILD_MESSAGE", "YELL_MESSAGE", "WHISPER_MESSAGE", "REPLY_MESSAGE", "MACRO", "EMOTE_MESSAGE",
  "VOICEMACRO_LABEL", "LANGUAGE" }
local WORLD_MAP_FILTERS = { "SHOW_QUEST_OBJECTIVES_ON_MAP_TEXT", "SHOW_QUEST_LEVELS", "MAP_QUEST_DIFFICULTY_TEXT",
  "SHOW_INSTANCE_ENTRANCES_ON_MAP_TEXT", "CONTENT_TRACKING_MAP_TOGGLE", "MINIMAP_TRACKING_TRIVIAL_QUESTS" }

-- tag → { keys = entries it may show, tooltips = tooltip keys (optional), source = where the generator is,
--         titleIsName = the menu's title is a name (optional) }
Menus.TAGS = {
  -- the bag portrait menus (blizzard_uipanels_game/mainline/containerframe.lua:625–700, 761–770, 2749–2771): the
  -- bag submenus, filters and cleanup; BAG_NAME_BACKPACK shares its English with BACKPACK_TOOLTIP (excluded)
  MENU_CONTAINER_FRAME = { source = "containerframe.lua:761", keys = { "BAG_FILTER_ASSIGN_TO", "BAG_FILTER_IGNORE",
    "BAG_FILTER_CLEANUP", "BAG_FILTER_EQUIPMENT", "BAG_FILTER_CONSUMABLES", "BAG_FILTER_PROFESSION_GOODS",
    "BAG_FILTER_JUNK", "BAG_FILTER_QUEST_ITEMS", "BAG_FILTER_REAGENTS", "SELL_ALL_JUNK_ITEMS_EXCLUDE_FLAG",
    "BAG_COMMAND_CONVERT_TO_COMBINED", "BAG_COMMAND_CONVERT_TO_INDIVIDUAL" } },
  MENU_CONTAINER_FRAME_COMBINED = { source = "containerframe.lua:2749", keys = { "BAG_FILTER_TITLE_SORTING",
    "BAG_NAME_BAG_1", "BAG_NAME_BAG_2", "BAG_NAME_BAG_3", "BAG_NAME_BAG_4", "BAG_FILTER_ASSIGN_TO",
    "BAG_FILTER_IGNORE", "BAG_FILTER_CLEANUP", "BAG_FILTER_EQUIPMENT", "BAG_FILTER_CONSUMABLES",
    "BAG_FILTER_PROFESSION_GOODS", "BAG_FILTER_JUNK", "BAG_FILTER_QUEST_ITEMS", "BAG_FILTER_REAGENTS",
    "SELL_ALL_JUNK_ITEMS_EXCLUDE_FLAG", "BAG_COMMAND_CONVERT_TO_COMBINED", "BAG_COMMAND_CONVERT_TO_INDIVIDUAL" } },
  -- the bank's expansion filter (bankframetemplates.lua:1678, 1719–1720)
  MENU_BANK_EXPANSION_FILTER = { source = "bankframetemplates.lua:1719", keys = { "BANK_TAB_EXPANSION_FILTER_ALL",
    "BANK_TAB_EXPANSION_FILTER_CURRENT", "BANK_TAB_EXPANSION_FILTER_LEGACY" } },
  -- talents: the search options and the reset button (camelot classtalents/blizzard_classtalentsframe.lua:237–245;
  -- classtalents/blizzard_classtalentsframe.lua:81–87)
  MENU_CLASS_TALENTS_SEARCH_OPTIONS = { source = "camelot blizzard_classtalentsframe.lua:237",
    keys = { "CLASS_TALENT_SEARCH_OPTION_HIDE_PASSIVES", "CLASS_TALENT_SEARCH_OPTION_SHOW_RANKS" } },
  MENU_CLASS_TALENT_FRAME_RESET = { source = "blizzard_classtalentsframe.lua:81",
    keys = { "TALENT_FRAME_RESET_BUTTON_DROPDOWN_TITLE", "TALENT_FRAME_RESET_BUTTON_DROPDOWN_LEFT",
      "TALENT_FRAME_RESET_BUTTON_DROPDOWN_RIGHT", "TALENT_FRAME_RESET_BUTTON_DROPDOWN_ALL" } },
  -- Communities: the roster's column dropdowns, the rank dropdown's disabled reasons, the news context menu
  -- (communitiesmemberlist.lua:151–160, 1568–1570, 1671–1701; guildroster.lua:27–56; guildnews.lua:246–271)
  MENU_COMMUNITIES_GUILD_MEMBER_LIST = { source = "communitiesmemberlist.lua:1570",
    keys = { "GUILD_ROSTER_DROPDOWN_ACHIEVEMENT_POINTS", "GUILD_ROSTER_DROPDOWN_PROFESSION" } },
  MENU_COMMUNITIES_MEMBER_LIST = { source = "communitiesmemberlist.lua:1673",
    keys = { "CLUB_FINDER_COMMUNITY_ROSTER_DROPDOWN" } },
  MENU_GUILD_RANKS = { source = "guildroster.lua:27", keys = {},
    tooltips = { "GUILD_RANK_UNAVAILABLE", "GUILD_RANK_UNAVAILABLE_AUTHENTICATOR" } },
  MENU_GUILD_NEWS = { source = "guildnews.lua:248", keys = { "GUILD_CREATION", "GUILD_NEWS_VIEW_ACHIEVEMENT",
    "GUILD_NEWS_MAKE_STICKY", "GUILD_NEWS_REMOVE_STICKY" } },
  -- the guild rewards' context menu: the title is the item's name (guildrewards.lua:150–160)
  MENU_GUILD_REWARDS = { source = "guildrewards.lua:150",
    keys = { "GUILD_NEWS_LINK_ITEM", "GUILD_NEWS_VIEW_ACHIEVEMENT" } },
  -- ClubFinder (blizzard_communities/clubfinder.lua): focus, looking-for roles (their submenus are spec names plus
  -- check / uncheck all), the search filter, the size options, the sort order, a card's context menu (the reapply
  -- notice red-wrapped, the `wrapped` label form)
  MENU_CLUB_FOCUS = { source = "clubfinder.lua:474", keys = { "CLUB_FINDER_FOCUS_SOCIAL_LEVELING",
    "GUILD_INTEREST_DUNGEON", "GUILD_INTEREST_RAID", "PVP_ENABLED", "GUILD_INTEREST_RP" } },
  MENU_CLUB_LOOKING_FOR = { source = "clubfinder.lua:520", keys = { "CLUB_FINDER_TANK", "CLUB_FINDER_HEALER",
    "CLUB_FINDER_DAMAGE", "CHECK_ALL", "UNCHECK_ALL" } },
  MENU_CLUB_FILTER = { source = "clubfinder.lua:696", keys = { "CROSS_FACTION_CLUB_FINDER_SEARCH_OPTION",
    "CLUB_FINDER_FOCUS", "CLUB_FINDER_FOCUS_SOCIAL_LEVELING", "GUILD_INTEREST_DUNGEON", "GUILD_INTEREST_RAID",
    "PVP_ENABLED", "GUILD_INTEREST_RP", "LANGUAGE" } },
  MENU_CLUB_FINDER_OPTIONS = { source = "clubfinder.lua:905",
    keys = { "CLUB_FINDER_ANY_FLAG", "SMALL", "CLUB_FINDER_MEDIUM", "LARGE" } },
  MENU_CLUB_SORT_BY = { source = "clubfinder.lua:967", keys = { "CLUB_FINDER_SORT_BY_RELEVANCE",
    "CLUB_FINDER_SORT_BY_MOST_MEMBERS", "CLUB_FINDER_SORT_BY_NEWEST" } },
  MENU_CLUB_FINDER_CARD = { source = "clubfinder.lua:1091", keys = { "CLUB_FINDER_REAPPLY",
    "CLUB_FINDER_REQUEST_TO_JOIN", "CLUB_FINDER_CANCEL_APPLICATION", "CLUB_FINDER_REPORT_POSTING" } },
  -- the applicant list's context menu: the title is the applicant's name; the re-invite is green-wrapped
  -- (clubfinderapplicantlist.lua:64–79)
  MENU_CLUB_FINDER_APPLICANT = { source = "clubfinderapplicantlist.lua:64",
    keys = { "CLUB_FINDER_INVITE_APPLICANT_REDO", "WHISPER", "CLUB_FINDER_REPORT_APPLICANT" } },
  -- Communities streams: the channel dropdown (channel names stay English; create is green-wrapped) and the
  -- add-to-chat menu (chat window names stay English) (communitiesstreams.lua:37, 89–106, 363–455)
  MENU_COMMUNITIES_STREAM = { source = "communitiesstreams.lua:37",
    keys = { "COMMUNITIES_CREATE_CHANNEL", "COMMUNITIES_NOTIFICATION_SETTINGS" } },
  MENU_COMMUNITIES_ADD_TO_CHAT = { source = "communitiesstreams.lua:363",
    keys = { "COMMUNITIES_ADD_TO_CHAT_DROP_DOWN_TITLE", "COMMUNITIES_ADD_TO_CHAT_DROP_DOWN_NEW_CHAT_WINDOW",
      "COMMUNITIES_ADD_TO_CHAT_DROP_DOWN_CHAT_SETTINGS" } },
  -- the invite ticket dialog's uses / expiry dropdowns (communitiesticketmanagerdialog.lua:224–247)
  MENU_COMMUNITIES_DIALOG_USES = { source = "communitiesticketmanagerdialog.lua:224",
    keys = { "COMMUNITIES_INVITE_MANAGER_USES_UNLIMITED", "COMMUNITIES_INVITE_MANAGER_USES" } },
  MENU_COMMUNITIES_DIALOG_EXPIRES = { source = "communitiesticketmanagerdialog.lua:243",
    keys = { "COMMUNITIES_INVITE_MANAGER_EXPIRES_NEVER" } },
  -- the character sheet's equipment set menu (camelot paperdollframe.lua:2542–2545)
  MENU_PAPERDOLL_FRAME = { source = "camelot paperdollframe.lua:2542", keys = { "EQUIPMENT_SET_EDIT" } },
  -- quests: the tracker's block menu, the list's settings, a quest's and a header's context menus
  -- (blizzard_questobjectivetracker.lua:72–89; mainline/questmapframe.lua:501–504, 2370–2399, 2465–2473)
  MENU_QUEST_OBJECTIVE_TRACKER = { source = "blizzard_questobjectivetracker.lua:72",
    keys = { "OBJECTIVES_VIEW_IN_QUESTLOG", "OBJECTIVES_HIDE_VIEW_IN_QUESTLOG" } },
  MENU_QUEST_MAP_FRAME_SETTINGS = { source = "questmapframe.lua:501", keys = { "QUEST_LOG_SHOW_OBJECTIVES" } },
  MENU_QUEST_MAP_LOG_TITLE = { source = "questmapframe.lua:2370", keys = { "SHARE_IN_CHAT", "SUPER_TRACK_QUEST",
    "STOP_SUPER_TRACK_QUEST", "UNTRACK_QUEST" } },
  MENU_QUEST_MAP_FRAME = { source = "questmapframe.lua:2465",
    keys = { "QUEST_LOG_TRACK_ALL", "QUEST_LOG_UNTRACK_ALL" } },
  -- the trainer's filter: colour-wrapped entries (the `wrapped` label form) (mainline/blizzard_trainerui.lua:249–255)
  -- AVAILABLE shares "Available" with the friends status: it owns its Japanese (UIStrings.OWN).
  -- The "Categorize" checkbox shows when the trainer uses categories; "Filters" is a submenu (lua:269, 274).
  MENU_TRAINER_FILTER = { source = "blizzard_trainerui.lua:250", keys = { "AVAILABLE", "UNAVAILABLE", "USED",
    "CATEGORIZE", "FILTERS" } },
  -- the dressing room's custom-set menu: its green "New Custom Set" entry and the gear's tooltip; a saved
  -- set's name is the player's own and matches no key (blizzard_framexml/wardrobecustomsets.lua:101–150)
  MENU_WARDROBE_CUSTOM_SETS = { source = "wardrobecustomsets.lua:102", keys = { "TRANSMOG_CUSTOM_SET_NEW" },
    tooltips = { "TRANSMOG_CUSTOM_SET_EDIT" } },
  -- friends: the invite decline menu, the friends-of-friends view, the contacts menu
  -- (camelot friendsframe.lua:721–739, 2485–2495; mainline/friendsfriendsframe.lua:154–159)
  MENU_FRIENDS_INVITE_DECLINE = { source = "camelot friendsframe.lua:721",
    keys = { "REPORT_PLAYER", "BLOCK_INVITES" } },
  MENU_FRIENDS_FRIENDS = { source = "friendsfriendsframe.lua:154", keys = { "FRIENDS_FRIENDS_CHOICE_EVERYONE",
    "FRIENDS_FRIENDS_CHOICE_POTENTIAL", "FRIENDS_FRIENDS_CHOICE_MUTUAL" } },
  CONTACTS_MENU = { source = "camelot friendsframe.lua:2485",
    keys = { "CONTACTS_MENU_BROADCAST_BUTTON_NAME", "CONTACTS_MENU_IGNORE_BUTTON_NAME" } },
  -- the world map's filter menu; each filter's hover is its text + a description, owned by the
  -- element (blizzard_worldmap/blizzard_worldmaptemplates.lua:229–250, 336–344; camelot filters camelot/…:1–3)
  MENU_WORLD_MAP_TRACKING = { source = "blizzard_worldmaptemplates.lua:229",
    keys = { "WORLD_MAP_FILTER_LABEL_SHOW", unpack(WORLD_MAP_FILTERS) },
    tooltips = { "QUEST_OBJECTIVES_FILTER_DESCRIPTION", "QUEST_LEVEL_FILTER_DESCRIPTION",
      "QUEST_DIFFICULTY_FILTER_DESCRIPTION", "INSTANCE_ENTRANCES_FILTER_DESCRIPTION",
      "TRACKED_ITEMS_FILTER_DESCRIPTION",
      "TRIVIAL_QUESTS_FILTER_DESCRIPTION", unpack(WORLD_MAP_FILTERS) } },
  -- the minimap tracking menu: entries are C_Minimap.GetTrackingInfo(i).name, which on Forever is the
  -- MINIMAP_TRACKING_* text [unverified in game: the name equals the global string]; tracking spells ("Find Herbs")
  -- are names and match nothing (blizzard_minimap/mainline/minimap.lua:645–760; camelot/minimapconstants.lua:12–25)
  MENU_MINIMAP_TRACKING = { source = "mainline/minimap.lua:645", keys = { "UNCHECK_ALL", "MINIMAP_TRACKING_REPAIR",
    "MINIMAP_TRACKING_INNKEEPER", "MINIMAP_TRACKING_FLIGHTMASTER", "MINIMAP_TRACKING_STABLEMASTER",
    "MINIMAP_TRACKING_BATTLEMASTER", "MINIMAP_TRACKING_TRAINER_CLASS", "MINIMAP_TRACKING_TRAINER_PROFESSION",
    "MINIMAP_TRACKING_AUCTIONEER", "MINIMAP_TRACKING_BANKER", "MINIMAP_TRACKING_MAILBOX", "MINIMAP_TRACKING_TARGET",
    "MINIMAP_TRACKING_TRIVIAL_QUESTS", "HUNTER_TRACKING_TEXT", "TOWNSFOLK_TRACKING_TEXT" } },
  -- chat: a tab's context menu (window names are on the tab, never in it; Font Size's radios are "%d pt"), the chat
  -- menu button's shortcuts, and a channel's context menu (its title is the channel name). The gamepad channel menu
  -- (CHAT_WINDOW_CHAT_CHANNEL_MENU, floatingchatframe.lua:243–300) is not tagged: it lists player-named custom
  -- channels beside the shortcut words, and a channel named "Say" would be translated (names stay in English)
  -- (blizzard_chatframebase/mainline/floatingchatframe.lua:243, 641–784; mainline/chatframemenubutton.lua:56–126;
  -- shared/chatframeutil.lua:697–722)
  MENU_FCF_TAB = { source = "mainline/floatingchatframe.lua:641", keys = { "HUD_EDIT_MODE_MENU", "UNLOCK_WINDOW",
    "LOCK_WINDOW", "UNDOCK_WINDOW", "MAKE_INTERACTABLE", "MAKE_UNINTERACTABLE", "RENAME_CHAT_WINDOW",
    "NEW_CHAT_WINDOW", "CLOSE_CHAT_WINDOW", "CLOSE_CHAT_WHISPER_WINDOW", "DISPLAY", "FONT_SIZE", "FONT_SIZE_TEMPLATE",
    "BACKGROUND", "FILTERS", "CHAT_CONFIGURATION" } },
  MENU_CHAT_SHORTCUTS = { source = "mainline/chatframemenubutton.lua:56", keys = CHAT_SHORTCUT_KEYS },
  MENU_CHAT_FRAME_CHANNEL = { source = "shared/chatframeutil.lua:697", titleIsName = true,
    keys = { "CHAT_CHANNEL_DROP_DOWN_OPEN_COMMUNITIES_FRAME", "MOVE_TO_NEW_WINDOW" } },
  -- Edit Mode's layout menu: a layout's name (preset or the player's) is no key; the new-layout
  -- entry carries an atlas in front; the copy / rename / delete hovers (editmodemanager.lua:1340–1455;
  -- editmodelayoutmanagerutil.lua:3–33)
  MENU_EDIT_MODE_MANAGER = { source = "editmodemanager.lua:1340", keys = { "HUD_EDIT_MODE_NEW_LAYOUT",
    "HUD_EDIT_MODE_NEW_LAYOUT_DISABLED", "HUD_EDIT_MODE_IMPORT_LAYOUT", "HUD_EDIT_MODE_SHARE_LAYOUT",
    "HUD_EDIT_MODE_COPY_TO_CLIPBOARD", "HUD_EDIT_MODE_COPY_LAYOUT", "HUD_EDIT_MODE_RENAME_LAYOUT" },
    tooltips = { "HUD_EDIT_MODE_COPY_LAYOUT", "HUD_EDIT_MODE_ERROR_COPY", "HUD_EDIT_MODE_ERROR_COPY_MAX_LAYOUTS",
      "HUD_EDIT_MODE_RENAME_OR_COPY_LAYOUT", "HUD_EDIT_MODE_DELETE_LAYOUT" } },
  -- the AddOn list: the character filter, and an entry's context menu whose title is the addon's title
  -- (blizzard_addonlist/addonlist.lua:643–660, 938–965)
  MENU_ADDON_LIST = { source = "addonlist.lua:643", keys = { "ALL" } },
  MENU_ADDON_LIST_ENTRY = { source = "addonlist.lua:938", titleIsName = true, keys = {
    "ADDON_LIST_ENABLE_DEPENDENCIES", "ADDON_LIST_ENABLE_GROUP", "ADDON_LIST_ENABLE_CATEGORY",
    "ADDON_LIST_DISABLE_GROUP", "ADDON_LIST_DISABLE_CATEGORY", "ADDON_LIST_RESET_TO_DEFAULT",
    "ADDON_LIST_RESET_ALL_TO_DEFAULT" } },
  -- the queue eye's menu: queue titles are dungeon / battleground / activity names and match nothing
  -- (blizzard_queuestatusframe/mainline/queuestatusframe.lua:224, 1276–1507)
  MENU_QUEUE_STATUS_FRAME = { source = "queuestatusframe.lua:224", keys = { "CANCEL_SIGN_UP", "ENTER_LFG",
    "LEAVE_ALL_QUEUES", "LEAVE_BATTLEGROUND", "LEAVE_LFD_BATTLEFIELD", "LFG_LIST_VIEW_GROUP",
    "TOGGLE_BATTLEFIELD_MAP", "TOGGLE_SCOREBOARD", "UNLIST_ME", "UNLIST_MY_GROUP" } },
  -- the Group Finder: the role radios, the options checkbox, the category filter (categories are client-table
  -- names) (blizzard_groupfinder_vanillastyle/blizzard_lfgvanilla_listing.lua:513–523, 662–670;
  -- blizzard_lfgvanilla_browse.lua:999–1025, 1219–1227)
  MENU_LFG_LISTING_ROLE = { source = "blizzard_lfgvanilla_listing.lua:513", keys = { "TANK", "HEALER", "DAMAGER" } },
  MENU_LFG_LISTING_SETTINGS = { source = "blizzard_lfgvanilla_listing.lua:662",
    keys = { "LFG_LIST_IGNORE_SUGGESTED_LEVEL" } },
  MENU_LFG_BROWSE_CATEGORY = { source = "blizzard_lfgvanilla_browse.lua:999",
    keys = { "LFG_TYPE_NONE", "LFG_SELF_LISTING" } },
  MENU_LFG_FRAME_GROUP_PLAYSTYLE = { source = "blizzard_lfgvanilla_listing.lua:870",
    keys = { "GROUP_FINDER_GENERAL_PLAYSTYLE1", "GROUP_FINDER_GENERAL_PLAYSTYLE2", "GROUP_FINDER_GENERAL_PLAYSTYLE3",
      "GROUP_FINDER_GENERAL_PLAYSTYLE4" } },
  -- the friends list's status: "|T<texture>|t Available" (the `icon` label form) (camelot friendsframe.lua:565–576)
  MENU_FRIENDS_STATUS = { source = "camelot friendsframe.lua:565",
    keys = { "FRIENDS_LIST_AVAILABLE", "FRIENDS_LIST_AWAY", "FRIENDS_LIST_BUSY" } },
  -- the merchant's filter: specialization names are names (mainline/merchantframe.lua:44–64)
  MENU_MERCHANT_FRAME = { source = "merchantframe.lua:44", keys = { "ALL_SPECS", "ITEM_BIND_ON_EQUIP", "ALL" } },
  -- the clock's alarm AM / PM (mainline/blizzard_timemanager.lua:216–220)
  MENU_TIME_MANAGER_AMPM = { source = "blizzard_timemanager.lua:216", keys = { "TIMEMANAGER_AM", "TIMEMANAGER_PM" } },
}

-- The untagged menus are UI/MenusUntagged's: Menus.UNTAGGED is set there (loaded next).
Menus.UNTAGGED = {}
local function specOf(tag) return Menus.TAGS[tag] or Menus.UNTAGGED[tag] end
-- the unit right-click menus, one tag per `which` (UI/MenusUnit; the other windows' tags: UI/MenusTags, loaded next)
for tag, spec in pairs(UNIT.tags()) do Menus.TAGS[tag] = spec end

-- The element frame's text widget: frame.fontString for a button, checkbox, radio or title.
-- (through Labels.menuText: the compositor forbids SetFont on it)
local function textOf(frame)
  local fs = type(frame) == "table" and frame.fontString or nil
  if type(fs) == "table" and type(fs.GetText) == "function" then return WFJ.Labels.menuText(fs) end
  return nil
end

local menuKey = WFJ.Labels.keyer("menu.") -- a pooled frame's text widget, never its English or position

-- One element, after the client's initializer wrote its English. `name` (optional): the menu's name (a unit's), never
-- matched. → 1 | 0
function Menus.showElement(tag, frame, name)
  local spec = specOf(tag)
  if not spec then return 0 end
  if spec.tooltips and #spec.tooltips > 0 then
    local opts = { only = spec.tooltips }
    WFJ.HelpTooltip.register(frame, opts)
    -- the utility buttons (gear, cancel, play-sample) the client's earlier initializers attached (parented to
    -- the element, compositor.lua:34–46) own their hovers (SetUtilityButtonTooltipText, menutemplates.lua:645–649)
    if type(frame) == "table" and type(frame.GetChildren) == "function" then
      for _, child in ipairs({ frame:GetChildren() }) do WFJ.HelpTooltip.register(child, opts) end
    end
  end
  local fs = textOf(frame)
  local en = fs and fs:GetText() or nil
  if #spec.keys == 0 or type(en) ~= "string" or en == "" then return 0 end
  if name ~= nil and en == name then return 0 end
  -- one record per text widget: frames are pooled, and two entries may share one English
  local n = WFJ.Labels.show(SURFACE, menuKey(fs), fs, nil, { only = spec.keys })
  if n == 0 and spec.show then n = spec.show(SURFACE, menuKey(fs), fs) end -- a tag's own line form
  return n
end

-- The resetter: the frame is going back to the pool. → the number of records dropped
function Menus.resetElement(frame)
  local fs = textOf(frame)
  if fs == nil then return 0 end
  local gone = {}
  for key, rec in pairs(WFJ.SurfaceState.records(SURFACE)) do
    if rec.fs == fs then gone[#gone + 1] = key end
  end
  for _, key in ipairs(gone) do WFJ.SurfaceState.drop(SURFACE, key) end
  return #gone
end

-- Adds the initializer and the resetter to every element description under `desc`, submenus included; with
-- `skipTitle`, the first element of `desc` (a name title) is left alone. → count
local function walk(tag, desc, depth, name, skipTitle)
  if depth > 8 or type(desc) ~= "table" or type(desc.EnumerateElementDescriptions) ~= "function" then return 0 end
  local n, first = 0, true
  for _, child in desc:EnumerateElementDescriptions() do
    if type(child) == "table" and type(child.AddInitializer) == "function" and not (skipTitle and first) then
      child:AddInitializer(function(frame) Menus.showElement(tag, frame, name) end)
      if type(child.AddResetter) == "function" then child:AddResetter(Menus.resetElement) end
      n = n + 1 + walk(tag, child, depth + 1, name, false)
    end
    first = false
  end
  return n
end

-- The Menu.ModifyMenu callback for `tag` (owner, rootDescription, contextData). → the number of elements given ours
function Menus.onMenu(tag, root, contextData)
  local spec = specOf(tag)
  local titleIsName = spec and spec.titleIsName or false
  local name
  if titleIsName and type(contextData) == "table" then
    name = type(contextData.name) == "string" and contextData.name or nil
    -- a target / focus / pet menu carries only the unit: its title is UnitName (unitpopupshared.lua:112–116)
    if not name and contextData.unit ~= nil and type(_G.UnitName) == "function" then
      name = _G.UnitName(contextData.unit)
    end
  end
  return walk(tag, root, 0, name, titleIsName)
end

local hooked = {}

-- Called by Main after Compat.init. Registers one ModifyMenu callback per tag; Menu is loaded at login (Blizzard_Menu
-- is not load-on-demand), and a tag whose generator never runs on this client simply never fires. → true when the
-- Menu API was found
function Menus.init()
  Compat.declare(SURFACE, "modifyMenu", { "Menu.ModifyMenu" })
  local modify = Compat.get(SURFACE, "modifyMenu")
  if type(modify) ~= "function" then return false end
  for tag in pairs(Menus.TAGS) do
    if not hooked[tag] then
      hooked[tag] = true
      modify(tag, function(_, root, contextData) Menus.onMenu(tag, root, contextData) end)
    end
  end
  return true
end
