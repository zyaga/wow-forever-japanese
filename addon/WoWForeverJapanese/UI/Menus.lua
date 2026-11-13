-- UI/Menus.lua: dropdown and context-menu entries of the hooked windows (ADR-031, ADR-088).
-- Every menu is written once the client has built it, never while it builds it. The client runs an element's
-- initializers and then sets the element's click and hover scripts in the same function (InitializeFrame,
-- blizzard_menu/menu.lua:1117-1131); code of this addon run there leaves those scripts set tainted, and every pick
-- from the menu then runs tainted [traced in game for the chat menu, ADR-087]. So no menu gets an initializer.
-- The client fires "MenuProxy.OnShow" as it shows each menu frame, after the frame's scripts are set
-- (menu.lua:2506, 2531, 1845-1849), and "Menu.OpenMenuTag" after that for a menu whose description has a tag
-- (:2453-2459, 2566); a submenu gets the first only. Registry callbacks run under securecallfunction
-- (blizzard_sharedxmlbase/callbackregistry.lua:198-214), so nothing written here reaches the client's code after them.
-- - A tagged menu is written on "Menu.OpenMenuTag" and becomes the open menu; a menu frame shown while it is open (a
--   submenu) is written with its keys. An untagged menu (UI/MenusUntagged) is recognised on "MenuProxy.OnShow" by
--   the owner region its opener recorded.
-- - A pick that keeps the menu open (a checkbox) has the client run its own initializers again, which write the
--   English back (menu.lua:2353-2367, 1682-1700). Each written text widget is followed by UI/TextWatch, which reads it
--   from this addon's own frame once a frame and writes the Japanese again after the client's pass has ended.
-- - The client laid the menu out for the English. A label whose Japanese is wider is widened, and the entries and the
--   menu frame with it (Menus.fit), with SetWidth alone: running the client's layout here would run it tainted.
-- - On "MenuProxy.OnHide", before the client hands the text widgets back to the pool every menu shares
--   (compositor.lua:367-390; menu.lua:1751-1764, 1851-1853), the records and watches on them are dropped.
-- Each tag lists the keys its entries may show: a widget only ever takes one of them (`only`), so a rank name, a bag
-- the player named or a quest title in a menu is never read as a dictionary word (names stay in English). Tooltip
-- keys are shown through UI/HelpTooltip on the element's own owner (a disabled radio's reason, GUILD_RANK_UNAVAILABLE).
-- A tag whose menu title is a name (a channel's, a unit's, a tracked block's) sets `titleIsName`: the root menu's
-- title (its top entry) is never written, nor any entry whose text is the menu's name (contextData.name, or the unit's
-- name), so a channel named "Trade" stays "Trade". Edit Mode stays as the client writes it (ADR-069).
local _, WFJ = ...
local Menus = {}
WFJ.Menus = Menus

local SURFACE = "help.menus" -- a help-family record surface: the menus belong to the windows that open them
Menus.SURFACE = SURFACE

local Compat = WFJ.Compat

-- the chat shortcut entries (the slash command beside each is its own FontString, untouched; emote and language
-- submenu entries are slash commands and language names, never listed)
local CHAT_SHORTCUT_KEYS = { "SAY_MESSAGE", "PARTY_MESSAGE", "RAID_MESSAGE", "INSTANCE_CHAT_MESSAGE",
  "GUILD_MESSAGE", "YELL_MESSAGE", "WHISPER_MESSAGE", "REPLY_MESSAGE", "MACRO", "EMOTE_MESSAGE",
  "VOICEMACRO_LABEL", "LANGUAGE" }
local WORLD_MAP_FILTERS = { "SHOW_QUEST_OBJECTIVES_ON_MAP_TEXT", "SHOW_QUEST_LEVELS", "MAP_QUEST_DIFFICULTY_TEXT",
  "SHOW_INSTANCE_ENTRANCES_ON_MAP_TEXT", "CONTENT_TRACKING_MAP_TOGGLE", "MINIMAP_TRACKING_TRIVIAL_QUESTS" }

-- tag → { keys = entries it may show, tooltips = tooltip keys (optional), source = where the generator is,
--         titleIsName = the menu's title is a name (optional) }. UI/MenusTags, UI/MenusUnit and UI/Gamepad add to it.
Menus.TAGS = {
  -- the bag portrait menus (blizzard_uipanels_game/mainline/containerframe.lua:643–730, 766–775, 2830–2850): the
  -- bag submenus, filters and cleanup; BAG_NAME_BACKPACK shares its English with BACKPACK_TOOLTIP (excluded). In
  -- gamepad UI mode the combined bag's menu also lists the reagent bag, BAG_NAME_BAG_REAGENT (:35–43, 14–19)
  MENU_CONTAINER_FRAME = { source = "containerframe.lua:766", keys = { "BAG_FILTER_ASSIGN_TO", "BAG_FILTER_IGNORE",
    "BAG_FILTER_CLEANUP", "BAG_FILTER_EQUIPMENT", "BAG_FILTER_CONSUMABLES", "BAG_FILTER_PROFESSION_GOODS",
    "BAG_FILTER_JUNK", "BAG_FILTER_QUEST_ITEMS", "BAG_FILTER_REAGENTS", "SELL_ALL_JUNK_ITEMS_EXCLUDE_FLAG",
    "BAG_COMMAND_CONVERT_TO_COMBINED", "BAG_COMMAND_CONVERT_TO_INDIVIDUAL" } },
  MENU_CONTAINER_FRAME_COMBINED = { source = "containerframe.lua:2830", keys = { "BAG_FILTER_TITLE_SORTING",
    "BAG_NAME_BAG_1", "BAG_NAME_BAG_2", "BAG_NAME_BAG_3", "BAG_NAME_BAG_4", "BAG_NAME_BAG_REAGENT",
    "BAG_FILTER_ASSIGN_TO", "BAG_FILTER_IGNORE", "BAG_FILTER_CLEANUP", "BAG_FILTER_EQUIPMENT", "BAG_FILTER_CONSUMABLES",
    "BAG_FILTER_PROFESSION_GOODS", "BAG_FILTER_JUNK", "BAG_FILTER_QUEST_ITEMS", "BAG_FILTER_REAGENTS",
    "SELL_ALL_JUNK_ITEMS_EXCLUDE_FLAG", "BAG_COMMAND_CONVERT_TO_COMBINED", "BAG_COMMAND_CONVERT_TO_INDIVIDUAL" } },
  -- the bank's expansion filter (bankframetemplates.lua:1678, 1719–1720)
  MENU_BANK_EXPANSION_FILTER = { source = "bankframetemplates.lua:1734", keys = { "BANK_TAB_EXPANSION_FILTER_ALL",
    "BANK_TAB_EXPANSION_FILTER_CURRENT", "BANK_TAB_EXPANSION_FILTER_LEGACY" } },
  -- talents: the search options and the reset button (camelot classtalents/blizzard_classtalentsframe.lua:258–266;
  -- classtalents/blizzard_classtalentsframe.lua:81–87)
  MENU_CLASS_TALENTS_SEARCH_OPTIONS = { source = "camelot blizzard_classtalentsframe.lua:258",
    keys = { "CLASS_TALENT_SEARCH_OPTION_HIDE_PASSIVES", "CLASS_TALENT_SEARCH_OPTION_SHOW_RANKS" } },
  MENU_CLASS_TALENT_FRAME_RESET = { source = "blizzard_classtalentsframe.lua:81",
    keys = { "TALENT_FRAME_RESET_BUTTON_DROPDOWN_TITLE", "TALENT_FRAME_RESET_BUTTON_DROPDOWN_LEFT",
      "TALENT_FRAME_RESET_BUTTON_DROPDOWN_RIGHT", "TALENT_FRAME_RESET_BUTTON_DROPDOWN_ALL" } },
  -- Communities: the roster's column dropdowns, the rank dropdown's disabled reasons, the news context menu
  -- (communitiesmemberlist.lua:151–160, 1575–1577, 1678–1708; guildroster.lua:49–78; guildnews.lua:246–271)
  MENU_COMMUNITIES_GUILD_MEMBER_LIST = { source = "communitiesmemberlist.lua:1577",
    keys = { "GUILD_ROSTER_DROPDOWN_ACHIEVEMENT_POINTS", "GUILD_ROSTER_DROPDOWN_PROFESSION" } },
  MENU_COMMUNITIES_MEMBER_LIST = { source = "communitiesmemberlist.lua:1680",
    keys = { "CLUB_FINDER_COMMUNITY_ROSTER_DROPDOWN" } },
  MENU_GUILD_RANKS = { source = "guildroster.lua:49", keys = {},
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
  -- add-to-chat menu (chat window names stay English) (communitiesstreams.lua:37, 90–107, 374–466)
  MENU_COMMUNITIES_STREAM = { source = "communitiesstreams.lua:37",
    keys = { "COMMUNITIES_CREATE_CHANNEL", "COMMUNITIES_NOTIFICATION_SETTINGS" } },
  MENU_COMMUNITIES_ADD_TO_CHAT = { source = "communitiesstreams.lua:374",
    keys = { "COMMUNITIES_ADD_TO_CHAT_DROP_DOWN_TITLE", "COMMUNITIES_ADD_TO_CHAT_DROP_DOWN_NEW_CHAT_WINDOW",
      "COMMUNITIES_ADD_TO_CHAT_DROP_DOWN_CHAT_SETTINGS" } },
  -- the invite ticket dialog's uses / expiry dropdowns (communitiesticketmanagerdialog.lua:278–301)
  MENU_COMMUNITIES_DIALOG_USES = { source = "communitiesticketmanagerdialog.lua:278",
    keys = { "COMMUNITIES_INVITE_MANAGER_USES_UNLIMITED", "COMMUNITIES_INVITE_MANAGER_USES" } },
  MENU_COMMUNITIES_DIALOG_EXPIRES = { source = "communitiesticketmanagerdialog.lua:297",
    keys = { "COMMUNITIES_INVITE_MANAGER_EXPIRES_NEVER" } },
  -- the character sheet's equipment set menu (camelot paperdollframe.lua:2618–2622)
  MENU_PAPERDOLL_FRAME = { source = "camelot paperdollframe.lua:2619", keys = { "EQUIPMENT_SET_EDIT" } },
  -- quests: the tracker's block menu, the list's settings, a quest's and a header's context menus, and the quest
  -- detail popup's options menu (gamepad UI mode only: its one opener is a gamepad prompt, questmapframe.lua:2550)
  -- (blizzard_questobjectivetracker.lua:72–131; mainline/questmapframe.lua:501–504, 2367–2416, 2463–2471, 2642–2689)
  -- the tracker menu's title is the quest's name (blizzard_questobjectivetracker.lua:77)
  MENU_QUEST_OBJECTIVE_TRACKER = { source = "blizzard_questobjectivetracker.lua:72", titleIsName = true,
    keys = { "SUPER_TRACK_QUEST", "STOP_SUPER_TRACK_QUEST", "OBJECTIVES_VIEW_IN_QUESTLOG",
      "OBJECTIVES_HIDE_VIEW_IN_QUESTLOG", "OBJECTIVES_SHOW_QUEST_MAP", "OBJECTIVES_STOP_TRACKING", "SHARE_QUEST",
      "SHARE_IN_CHAT", "ABANDON_QUEST_ABBREV" } },
  MENU_QUEST_MAP_FRAME_SETTINGS = { source = "questmapframe.lua:501", keys = { "QUEST_LOG_SHOW_OBJECTIVES" } },
  MENU_QUEST_MAP_LOG_TITLE = { source = "questmapframe.lua:2374", keys = { "TRACK_QUEST", "UNTRACK_QUEST",
    "SUPER_TRACK_QUEST", "STOP_SUPER_TRACK_QUEST", "SHARE_QUEST", "SHARE_IN_CHAT", "ABANDON_QUEST" } },
  MENU_QUEST_LOG_POPUP_DETAIL_FRAME = { source = "questmapframe.lua:2644", keys = { "TRACK_QUEST", "UNTRACK_QUEST",
    "SUPER_TRACK_QUEST", "STOP_SUPER_TRACK_QUEST", "SHOW_MAP", "SHARE_QUEST", "SHARE_IN_CHAT", "ABANDON_QUEST" } },
  MENU_QUEST_MAP_FRAME = { source = "questmapframe.lua:2471",
    keys = { "QUEST_LOG_TRACK_ALL", "QUEST_LOG_UNTRACK_ALL" } },
  -- the trainer's filter: colour-wrapped entries (the `wrapped` label form) (mainline/blizzard_trainerui.lua:249–255)
  -- AVAILABLE shares "Available" with the friends status: it owns its Japanese (UIStrings.OWN).
  -- The "Categorize" checkbox shows when the trainer uses categories; "Filters" is a submenu (lua:269, 274).
  MENU_TRAINER_FILTER = { source = "blizzard_trainerui.lua:266", keys = { "AVAILABLE", "UNAVAILABLE", "USED",
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
  -- element (blizzard_worldmap/blizzard_worldmaptemplates.lua:229–251, 360–368; camelot filters camelot/…:1–3).
  -- In gamepad UI mode the menu also carries the quest log's part: the map and quest log titles and the objectives
  -- checkbox (:234, 325–339; ShouldCombineMapAndQuestMenu, blizzard_worldmap.lua:1062–1064)
  MENU_WORLD_MAP_TRACKING = { source = "blizzard_worldmaptemplates.lua:229",
    keys = { "WORLD_MAP_FILTER_LABEL_SHOW", "WORLD_MAP_FILTER_TITLE_SHOW_MAP", "WORLD_MAP_FILTER_TITLE_SHOW_QUEST_LOG",
      "QUEST_LOG_SHOW_OBJECTIVES", unpack(WORLD_MAP_FILTERS) },
    tooltips = { "QUEST_OBJECTIVES_FILTER_DESCRIPTION", "QUEST_LEVEL_FILTER_DESCRIPTION",
      "QUEST_DIFFICULTY_FILTER_DESCRIPTION", "INSTANCE_ENTRANCES_FILTER_DESCRIPTION",
      "TRACKED_ITEMS_FILTER_DESCRIPTION",
      "TRIVIAL_QUESTS_FILTER_DESCRIPTION", unpack(WORLD_MAP_FILTERS) } },
  -- the minimap tracking menu: entries are C_Minimap.GetTrackingInfo(i).name, which on Forever is the
  -- MINIMAP_TRACKING_* text [unverified in game: the name equals the global string]; tracking spells ("Find Herbs")
  -- are names and match nothing (blizzard_minimap/mainline/minimap.lua:730–845; camelot/minimapconstants.lua:12–25)
  MENU_MINIMAP_TRACKING = { source = "mainline/minimap.lua:730", keys = { "UNCHECK_ALL", "MINIMAP_TRACKING_REPAIR",
    "MINIMAP_TRACKING_INNKEEPER", "MINIMAP_TRACKING_FLIGHTMASTER", "MINIMAP_TRACKING_STABLEMASTER",
    "MINIMAP_TRACKING_BATTLEMASTER", "MINIMAP_TRACKING_TRAINER_CLASS", "MINIMAP_TRACKING_TRAINER_PROFESSION",
    "MINIMAP_TRACKING_AUCTIONEER", "MINIMAP_TRACKING_BANKER", "MINIMAP_TRACKING_MAILBOX", "MINIMAP_TRACKING_TARGET",
    "MINIMAP_TRACKING_TRIVIAL_QUESTS", "HUNTER_TRACKING_TEXT", "TOWNSFOLK_TRACKING_TEXT" } },
  -- chat: a tab's context menu (window names are on the tab, never in it; Font Size's radios are "%d pt"), the chat
  -- menu button's shortcuts, and a channel's context menu (its title is the channel name)
  -- (blizzard_chatframebase/mainline/floatingchatframe.lua:546–689; mainline/chatframemenubutton.lua:56–126;
  -- shared/chatframeutil.lua:712–737)
  MENU_FCF_TAB = { source = "mainline/floatingchatframe.lua:546", keys = { "HUD_EDIT_MODE_MENU", "UNLOCK_WINDOW",
    "LOCK_WINDOW", "UNDOCK_WINDOW", "MAKE_INTERACTABLE", "MAKE_UNINTERACTABLE", "RENAME_CHAT_WINDOW",
    "NEW_CHAT_WINDOW", "CLOSE_CHAT_WINDOW", "CLOSE_CHAT_WHISPER_WINDOW", "DISPLAY", "FONT_SIZE", "FONT_SIZE_TEMPLATE",
    "BACKGROUND", "FILTERS", "CHAT_CONFIGURATION" } },
  MENU_CHAT_FRAME_CHANNEL = { source = "shared/chatframeutil.lua:712", titleIsName = true,
    keys = { "CHAT_CHANNEL_DROP_DOWN_OPEN_COMMUNITIES_FRAME", "MOVE_TO_NEW_WINDOW" } },
  -- the AddOn list: the character filter, and an entry's context menu whose title is the addon's title
  -- (blizzard_addonlist/addonlist.lua:643–660, 938–965)
  MENU_ADDON_LIST = { source = "addonlist.lua:643", keys = { "ALL" } },
  MENU_ADDON_LIST_ENTRY = { source = "addonlist.lua:938", titleIsName = true, keys = {
    "ADDON_LIST_ENABLE_DEPENDENCIES", "ADDON_LIST_ENABLE_GROUP", "ADDON_LIST_ENABLE_CATEGORY",
    "ADDON_LIST_DISABLE_GROUP", "ADDON_LIST_DISABLE_CATEGORY", "ADDON_LIST_RESET_TO_DEFAULT",
    "ADDON_LIST_RESET_ALL_TO_DEFAULT" } },
  -- the queue eye's menu: queue titles are dungeon / battleground / activity names and match nothing
  -- (blizzard_queuestatusframe/mainline/queuestatusframe.lua:224, 1276–1507)
  MENU_QUEUE_STATUS_FRAME = { source = "queuestatusframe.lua:35", keys = { "CANCEL_SIGN_UP", "ENTER_LFG",
    "LEAVE_ALL_QUEUES", "LEAVE_BATTLEGROUND", "LEAVE_LFD_BATTLEFIELD", "LFG_LIST_VIEW_GROUP",
    "TOGGLE_BATTLEFIELD_MAP", "TOGGLE_SCOREBOARD", "UNLIST_ME", "UNLIST_MY_GROUP" } },
  -- the Group Finder: the role radios, the options checkbox, the category filter (categories are client-table
  -- names) (blizzard_groupfinder_vanillastyle/blizzard_lfgvanilla_listing.lua:579–595, 729–741;
  -- blizzard_lfgvanilla_browse.lua:1056–1087, 1276–1288)
  MENU_LFG_LISTING_ROLE = { source = "blizzard_lfgvanilla_listing.lua:582", keys = { "TANK", "HEALER", "DAMAGER" } },
  MENU_LFG_LISTING_SETTINGS = { source = "blizzard_lfgvanilla_listing.lua:731",
    keys = { "LFG_LIST_IGNORE_SUGGESTED_LEVEL" } },
  MENU_LFG_BROWSE_CATEGORY = { source = "blizzard_lfgvanilla_browse.lua:1058",
    keys = { "LFG_TYPE_NONE", "LFG_SELF_LISTING" } },
  MENU_LFG_FRAME_GROUP_PLAYSTYLE = { source = "blizzard_lfgvanilla_listing.lua:943",
    keys = { "GROUP_FINDER_GENERAL_PLAYSTYLE1", "GROUP_FINDER_GENERAL_PLAYSTYLE2", "GROUP_FINDER_GENERAL_PLAYSTYLE3",
      "GROUP_FINDER_GENERAL_PLAYSTYLE4" } },
  -- the friends list's status: "|T<texture>|t Available" (the `icon` label form) (camelot friendsframe.lua:565–576)
  MENU_FRIENDS_STATUS = { source = "camelot friendsframe.lua:565",
    keys = { "FRIENDS_LIST_AVAILABLE", "FRIENDS_LIST_AWAY", "FRIENDS_LIST_BUSY" } },
  -- the merchant's filter: specialization names are names (mainline/merchantframe.lua:44–64)
  MENU_MERCHANT_FRAME = { source = "merchantframe.lua:44", keys = { "ALL_SPECS", "ITEM_BIND_ON_EQUIP", "ALL" } },
  -- the clock's alarm AM / PM (mainline/blizzard_timemanager.lua:216–220)
  MENU_TIME_MANAGER_AMPM = { source = "blizzard_timemanager.lua:216", keys = { "TIMEMANAGER_AM", "TIMEMANAGER_PM" } },
  -- the chat menu button's shortcuts; its submenus hold slash commands and language names, never listed
  -- (mainline/chatframemenubutton.lua:56–126)
  MENU_CHAT_SHORTCUTS = { source = "mainline/chatframemenubutton.lua:56", keys = CHAT_SHORTCUT_KEYS },
}

-- The untagged menus are UI/MenusUntagged's: Menus.UNTAGGED is set there (loaded next).
Menus.UNTAGGED = {}
local function specOf(tag) return Menus.TAGS[tag] or Menus.UNTAGGED[tag] end

local function secret(value) return WFJ.SurfaceState.secret(value) end

-- The element frame's text widget: frame.fontString for a button, checkbox, radio or title.
-- (through Labels.menuText: the compositor forbids SetFont on it)
local function textOf(frame)
  local fs = type(frame) == "table" and frame.fontString or nil
  if type(fs) == "table" and type(fs.GetText) == "function" then return WFJ.Labels.menuText(fs) end
  return nil
end

local menuKey = WFJ.Labels.keyer("menu.") -- a pooled frame's text widget, never its English or position

-- One element, the client's English in it. `name` (optional): the menu's name (a unit's), never matched. → 1 | 0
function Menus.showElement(tag, frame, name)
  local spec = specOf(tag)
  if not spec then return 0 end
  if spec.tooltips and #spec.tooltips > 0 then
    local opts = { only = spec.tooltips }
    WFJ.HelpTooltip.register(frame, opts)
    -- the utility buttons (gear, cancel, play-sample) the client's initializers attached (parented to the element,
    -- compositor.lua:34–46) own their hovers (SetUtilityButtonTooltipText, menutemplates.lua:645–649)
    for _, child in ipairs(WFJ.Frames.children(frame)) do WFJ.HelpTooltip.register(child, opts) end
  end
  local fs = textOf(frame)
  local en = fs and fs:GetText() or nil
  if #spec.keys == 0 or secret(en) or type(en) ~= "string" or en == "" then return 0 end
  if name ~= nil and en == name then return 0 end
  -- one record per text widget: frames are pooled, and two entries may share one English
  local n = WFJ.Labels.show(SURFACE, menuKey(fs), fs, nil, { only = spec.keys })
  if n == 0 and spec.show then n = spec.show(SURFACE, menuKey(fs), fs) end -- a tag's own line form
  return n
end

-- The menu's name for a tag whose title is a name: contextData.name, or the name of contextData.unit (a target,
-- focus or pet menu carries only the unit, unitpopupshared.lua:110–116). A name the client keeps secret is no name.
-- → string | nil
function Menus.nameOf(spec, contextData)
  if not (spec and spec.titleIsName) or type(contextData) ~= "table" then return nil end
  local name = contextData.name
  if name == nil and contextData.unit ~= nil and not secret(contextData.unit) then
    local unitName = Compat.get(SURFACE, "unitName")
    if type(unitName) == "function" then name = unitName(contextData.unit) end
  end
  if secret(name) or type(name) ~= "string" or name == "" then return nil end
  return name
end

-- The menu being shown: { tag, name, root = its first menu frame }; nil when none of ours is open.
local open
local lastShown -- the menu frame "MenuProxy.OnShow" reported last: the root when "Menu.OpenMenuTag" follows
-- menu frame → { widgets = the text widgets written (Labels adapters), raw = their FontStrings, frames = element
-- frames }. A widget belongs to the pool every menu shares; the widgets are kept, not their element frames: a rebuild
-- of the open menu hands the same widgets to other frames.
local written = setmetatable({}, { __mode = "k" })

local function shownFrame(frame)
  return type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() and true or false
end

-- The element frames directly under a menu frame (each holds a text widget). → list
local function entriesOf(menuFrame)
  local out = {}
  for _, child in ipairs(WFJ.Frames.children(menuFrame)) do
    if type(child) == "table" and type(child.fontString) == "table" then out[#out + 1] = child end
  end
  return out
end

local function num(v) return type(v) == "number" and not secret(v) and v or nil end
local function call(obj, method)
  if type(obj) ~= "table" or type(obj[method]) ~= "function" then return nil end
  return num(obj[method](obj))
end

-- Widens what the Japanese needs, with SetWidth alone (no client layout runs). A label's widget is set to its whole
-- width (the client sized it to the English, one line, menutemplates.lua:298; compositor.lua:71–72); when a label
-- then passes its entry's right edge less the margin the client left after the widest English label, every entry and
-- the menu frame widen by the largest overflow (the entries share one width, menu.lua:1430–1480). A scrolling menu
-- keeps its fixed size (menu.lua:1860–1874). → the width added to the menu frame
function Menus.fit(menuFrame, frames)
  if type(menuFrame) ~= "table" or type(menuFrame.SetWidth) ~= "function" then return 0 end
  if shownFrame(menuFrame.ScrollBox) then return 0 end
  local margin, rows = nil, {}
  for _, frame in ipairs(frames) do
    local fs = frame.fontString
    local left, width, right = call(fs, "GetLeft"), call(fs, "GetWidth"), call(frame, "GetRight")
    if left and width and right then
      local m = right - (left + width)
      if margin == nil or m < margin then margin = m end
      rows[#rows + 1] = { fs = fs, left = left, width = width, right = right }
    end
  end
  local over = 0
  for _, r in ipairs(rows) do
    local need = call(r.fs, "GetUnboundedStringWidth")
    if need and need > r.width then
      r.fs:SetWidth(need)
      over = math.max(over, r.left + need + math.max(margin or 0, 0) - r.right)
    end
  end
  if over <= 0 then return 0 end
  over = math.ceil(over)
  for _, frame in ipairs(frames) do
    local w = call(frame, "GetWidth")
    if w and type(frame.SetWidth) == "function" then frame:SetWidth(w + over) end
  end
  local w = call(menuFrame, "GetWidth")
  if not w then return 0 end
  menuFrame:SetWidth(w + over)
  return over
end

-- The title of a root menu whose title is a name: the generator creates it first, so it is laid out at the top
-- (the entries stack downwards, menu.lua:1500–1540). → element frame | nil
local function titleOf(frames)
  local top, best
  for _, frame in ipairs(frames) do
    local t = call(frame, "GetTop")
    if t and (top == nil or t > top) then top, best = t, frame end
  end
  return best
end

-- Writes every entry of `menuFrame` with the open menu's keys, watches each written widget, fits. → count shown
local function write(menuFrame)
  if not open or type(menuFrame) ~= "table" then return 0 end
  local rec = written[menuFrame] or { widgets = {}, raw = {}, frames = {} }
  written[menuFrame] = rec
  local tag, name = open.tag, open.name
  local n = 0
  local frames = entriesOf(menuFrame)
  local spec = specOf(tag)
  local title = spec and spec.titleIsName and menuFrame == open.root and titleOf(frames) or nil
  if title then
    local kept = {}
    for _, frame in ipairs(frames) do if frame ~= title then kept[#kept + 1] = frame end end
    frames = kept
  end
  for _, frame in ipairs(frames) do
    local raw = frame.fontString
    if not rec.raw[raw] then
      rec.raw[raw] = true
      rec.widgets[#rec.widgets + 1] = textOf(frame)
      -- the client writes the English again on a pick that keeps the menu open: shown again once its pass is over
      WFJ.TextWatch.add(raw, function()
        if Menus.showElement(tag, frame, name) > 0 then Menus.fit(menuFrame, entriesOf(menuFrame)) end
      end)
    end
    n = n + Menus.showElement(tag, frame, name)
  end
  rec.frames = frames
  Menus.fit(menuFrame, frames)
  return n
end

-- The records and watches on `rec`'s widgets, dropped (the client's text and font go back on a widget still showing
-- ours). → records dropped
local function letGo(rec)
  local mine, gone = {}, {}
  for _, fs in ipairs(rec.widgets) do mine[fs] = true end
  for raw in pairs(rec.raw) do WFJ.TextWatch.remove(raw) end
  for key, r in pairs(WFJ.SurfaceState.records(SURFACE)) do
    if mine[r.fs] then gone[#gone + 1] = key end
  end
  for _, key in ipairs(gone) do WFJ.SurfaceState.drop(SURFACE, key) end
  return #gone
end

local reported = {} -- error text → true: each distinct error is recorded once, not on every menu opened

-- The callbacks run inside the client's own menu code for every menu it opens or hides, so they never raise: an
-- error is recorded where the load errors are (WFJ.initErrors, surface "menus.afteropen", printed by /wfj debug).
local function guarded(fn, ...)
  local ok, n = pcall(fn, ...)
  if ok then return n end
  local err = tostring(n)
  if not reported[err] then
    reported[err] = true
    WFJ.initErrors = WFJ.initErrors or {}
    WFJ.initErrors[#WFJ.initErrors + 1] = { surface = "menus.afteropen", err = err }
  end
  return 0
end

local function shown(menuFrame)
  lastShown = menuFrame
  if open and open.root ~= menuFrame and shownFrame(open.root) then return write(menuFrame) end -- a submenu
  local untagged = WFJ.MenusUntagged and WFJ.MenusUntagged.specFor
  local owner = type(menuFrame.GetOwnerRegion) == "function" and menuFrame:GetOwnerRegion() or nil
  local tag, name
  if type(untagged) == "function" and owner ~= nil then tag, name = untagged(owner) end
  if not tag then return 0 end
  open = { tag = tag, name = name, root = menuFrame }
  return write(menuFrame)
end

-- "MenuProxy.OnShow" (owner, menuFrame): a submenu of the open menu, or an untagged menu its opener recorded, is
-- written now; a tagged menu waits for "Menu.OpenMenuTag". → count shown
function Menus.onMenuShown(_, menuFrame)
  if type(menuFrame) ~= "table" then return 0 end
  return guarded(shown, menuFrame)
end

local function opened(tag, contextData)
  local spec = Menus.TAGS[tag]
  if not spec or not shownFrame(lastShown) then return 0 end
  open = { tag = tag, name = Menus.nameOf(spec, contextData), root = lastShown }
  return write(lastShown)
end

-- "Menu.OpenMenuTag" (owner, tag, contextData): the client has built a tagged menu and shown it. → count shown
function Menus.onMenuOpened(_, tag, contextData)
  if not Menus.TAGS[tag] then return 0 end
  return guarded(opened, tag, contextData)
end

local function hidden(menuFrame)
  if open and open.root == menuFrame then open = nil end
  local rec = written[menuFrame]
  if not rec then return 0 end
  written[menuFrame] = nil
  return letGo(rec)
end

-- "MenuProxy.OnHide" (owner, menuFrame): fired as the menu hides, before the client hands its text widgets back to
-- the pool. → records dropped
function Menus.onMenuHidden(_, menuFrame)
  if type(menuFrame) ~= "table" then return 0 end
  return guarded(hidden, menuFrame)
end

-- The open menu's tag, for the specs and /wfj debug. → tag | nil
function Menus.openTag() return open and open.tag or nil end

local hooked = false

-- Called by Main after Compat.init. Registers the three registry callbacks once. → true when EventRegistry was found
function Menus.init()
  Compat.declare(SURFACE, "eventRegistry", { "EventRegistry" })
  Compat.declare(SURFACE, "unitName", { "UnitName" })
  local registry = Compat.get(SURFACE, "eventRegistry")
  if type(registry) ~= "table" or type(registry.RegisterCallback) ~= "function" then return false end
  if not hooked then
    hooked = true
    registry:RegisterCallback("MenuProxy.OnShow", Menus.onMenuShown, Menus)
    registry:RegisterCallback("Menu.OpenMenuTag", Menus.onMenuOpened, Menus)
    registry:RegisterCallback("MenuProxy.OnHide", Menus.onMenuHidden, Menus)
  end
  return true
end
