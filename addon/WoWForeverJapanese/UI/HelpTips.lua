-- UI/HelpTips.lua: HelpTip callouts (ADR-031): the tutorial and alert boxes HelpTip:Show puts beside a window
-- or a micro button ("You have unspent talent points.", the reputation and world-map tutorials).
-- HelpTip:Show acquires a pooled frame, Init stores `info`, and the frame's Layout (from OnShow, which may be deferred,
-- and again on UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED) calls ApplyText (Text:SetText(info.text) and the justify)
-- then measures Text:GetHeight() for the box [verified: blizzard_sharedxml/helptip.lua:174–193, 396–413, 495–519,
-- 572–647]. So the text is rewritten by a post-hook on ApplyText: before Layout measures, so the box fits the Japanese,
-- and again on every layout. `info.text` itself is never written: HelpTip:IsShowing / Hide / Matches and the
-- restriction checks compare it with the client's English (helptip.lua:237–305, 717–731).
-- ApplyText is a HelpTipTemplateMixin method copied onto each frame when the pool creates it: the mixin is hooked for
-- frames made later, and every frame the pool already holds (active or inactive) is hooked on its own.
-- The help-plate tooltip (HelpPlateTooltip, one frame) is the world map's and the spellbook's "?" button
-- tooltip. HelpPlateTooltipMixin:Init writes Text:SetText(tooltipText), then SetHeight(Text:GetHeight() + 30), then
-- Show [verified: blizzard_helpplate/blizzard_helpplate.lua:214–216]; InitFromMainHelpPlateButton passes the button's
-- text or MAIN_HELP_BUTTON_TOOLTIP (:219–222). A post-hook on the frame's Init rewrites the text and re-sets the
-- height the same way, so the glow box fits the Japanese.
-- The tutorial manager's pointer arrows (Blizzard_TutorialManager, loaded at login on camelot). The class
-- tutorial points at the talents button and tab with TutorialPointerFrame:Show(content, …, overrideWidth)
-- (blizzard_tutorials_classes.lua:88, 297, 310). Show takes a pooled frame, writes Content.Text:SetText(content), sizes
-- Content from the text (width min(GetStringWidth(), overrideWidth or 200) + 40, height GetHeight() + 40), shows it,
-- stores it in InUseFrames[NextID] and increments NextID [verified: blizzard_tutorialpointerframe.lua:47–138]. A
-- post-hook on that table method finds the frame at InUseFrames[NextID - 1], rewrites the text and re-sizes the box
-- the same way. Camelot's new player experience (UI/NewPlayerTutorial for its screen prompts) points the same arrows
-- with text it first passes through TutorialHelper:FormatString, which turns `{$id}` into the spell's name in cyan,
-- `{KB|id}` into its key and `{Atlas|name:size}` into CreateAtlasMarkup(name, size, size), "|A:name:size:size:0:0|a"
-- [verified: blizzard_tutorialmanager/blizzard_tutorialhelper.lua:39–67, blizzard_sharedxmlbase/textureutil.lua:
-- 303–309]. So an arrow's text is read and written through an adapter that shows that atlas markup as the token the
-- client's English holds: the line matches its global string, and the token in the Japanese is drawn as the atlas.
-- The reward-choice arrow is two lines in one, the red-items line before the choice line
-- (blizzard_newplayerexperience/blizzard_tutorialtutorials.lua:740–762): shown as the two entries in order.
local _, WFJ = ...
local HelpTips = {}
WFJ.HelpTips = HelpTips

local SURFACE = "help.tips" -- a help-family record surface: the callouts belong to the windows they point at
HelpTips.SURFACE = SURFACE

local Compat = WFJ.Compat

-- The callouts the hooked windows show; nothing else is ever read off a HelpTip (a callout may quote a name).
HelpTips.KEYS = { "ACCOUNT_WIDE_REPUTATION_TUTORIAL", "REPUTATION_EXALTED_PLUS_HELP", "RAF_REWARD_TUTORIAL_TEXT",
  "TALENT_MICRO_BUTTON_TALENT_TUTORIAL", "TALENT_MICRO_BUTTON_UNSPENT_TALENTS", "TUTORIAL_HUD_REVAMP_BAG_CHANGES",
  "WORLD_MAP_TUTORIAL2", "WORLD_MAP_TUTORIAL5", "CLUB_FINDER_NEW_COMMUNITY_JOINED",
  -- the Communities window's tutorials (blizzard_communities/communitiesframe.lua:1230–1330)
  "CLUB_FINDER_TUTORIAL_ROSTER", "CLUB_FINDER_TUTORIAL_APPLICANT_LIST", "CLUB_FINDER_TUTORIAL_POSTING",
  "CROSS_FACTION_COMMUNITIES_HELPTIP", "CLUB_FINDER_TUTORIAL_LANGUAGE_FILTER", "CLUB_FINDER_TUTORIAL_GUILD_LINK",
  -- the level-1 tutorials of Blizzard_Tutorials: the interact key (its binding and a count filled in,
  -- blizzard_tutorials_frame_tutorials.lua:32, 104) and super-tracking (blizzard_tutorialsupertrack.lua:57); shown only
  -- while the tutorials are on (in-game check)
  "INTERACT_KEY_TUTORIAL", "INTERACT_KEY_TUTORIAL_NO_INTERACT_KEY_ASSIGNED", "TUTORIAL_SUPERTRACK_STEP_1",
  -- every other Forever window's HelpTip:Show callouts: Edit Mode (editmodemanager.lua:2961–2987), the auction
  -- house (…auctionhousesellframe.lua:509), the
  -- world map's completed-quests filter (blizzard_worldmaptemplates.lua:404–425; camelot's
  -- CanShowRefreshAccountCompletedQuestFilterTutorial returns false, blizzard_worldmap/camelot/
  -- blizzard_worldmaptemplates.lua:10–12, so Forever never shows it), currencies (camelot
  -- blizzard_tokenui.lua:425–445), the assisted-combat button (actionbutton.lua:1986–2025), loot history
  -- (loothistory.lua:552–563), the chat language button (chatframemenubutton.lua:3), voice (channelframe.lua:460–476;
  -- voicechattranscriptionbutton.lua:210–220), the queue eye (queuestatusframe.lua:333–345)
  "EDIT_MODE_HELPTIPS_LAYOUTS", "EDIT_MODE_HELPTIPS_SELECT_FRAMES", "EDIT_MODE_HELPTIPS_SHOW_HIDDEN_FRAMES",
  "EDIT_MODE_HELPTIPS_ADVANCED_OPTIONS", "AUCTION_HOUSE_UNDERCUT_TUTORIAL", "ACCOUNT_COMPLETED_QUESTS_FILTER_TUTORIAL",
  "ACCOUNT_TRANSFERABLE_CURRENCIES_TUTORIAL", "ASSISTED_COMBAT_ROTATION_ACTION_BUTTON_HELPTIP",
  "LOOT_HISTORY_ROLL_TUTORIAL", "NEW_SPOKEN_LANGUAGE_HELPTIP", "TUTORIAL_VOICE", "SPEECH_TO_TEXT_TUTORIAL",
  "TUTORIAL_HUD_REVAMP_LFG_QUEUE_CHANGES",
  -- collections and the wardrobe (blizzard_toybox.lua:34, 183, 378; blizzard_heirloomcollection.lua:644;
  -- blizzard_wardrobe.lua:575–590, 1150–1172, 1554)
  "TOYBOX_FAVORITE_HELP", "TOYBOX_MOUSEWHEEL_PAGING_HELP", "HEIRLOOMS_JOURNAL_TUTORIAL_UPGRADE",
  "TRANSMOG_SETS_TAB_TUTORIAL", "WARDROBE_TRACKING_TUTORIAL", "WARDROBE_SHORTCUTS_TUTORIAL_1",
  -- the transmogrifier (blizzard_transmog.lua:556, 569, 1041, 1715–1751)
  "TRANSMOG_OUTFITS_HELPTIP", "TRANSMOG_SETS_HELPTIP", "TRANSMOG_CUSTOM_SETS_HELPTIP",
  "TRANSMOG_CUSTOM_SETS_MIGRATION_HELPTIP", "TRANSMOG_SITUATIONS_HELPTIP", "TRANSMOG_WEAPON_OPTIONS_HELPTIP",
  "TRANSMOG_TRIAL_OF_STYLE_HELPTIP",
  -- professions and crafting orders (blizzard_professionscrafting.lua:1433–1563; blizzard_professions_bootstrap.lua:
  -- 24–35; …customerordersform.lua:680–700, 1292; …customerordersmyorders.lua:290)
  "PROFESSIONS_TUTORIAL_REAGENT_QUALITY", "PROFESSIONS_TUTORIAL_QUALITY_BAR", "PROFESSIONS_TUTORIAL_OPTIONAL_REAGENT",
  "OPTIONAL_REAGENT_TUTORIAL_SLOT", "PROFESSIONS_TUTORIAL_FINISHING_REAGENT", "PROFESSIONS_TUTORIAL_RECRAFT",
  "PROFESSIONS_CRAFTING_CONCENTRATION_HELPTIP", "PROFESSION_EQUIPMENT_LOCATION_HELPTIP",
  "CRAFTING_ORDER_TUTORIAL_REAGENTS", "CRAFTING_ORDER_TUTORIAL_OPTIONAL_REAGENTS", "CRAFTING_ORDER_TUTORIAL_RECRAFT",
  "CRAFTING_ORDER_PLACED_TUTORIAL",
  -- callouts outside any window's list: the dressing room's custom-set link
  -- (blizzard_sharedxmlgame/dressupmodelframemixin.lua:23–30), a new profession (blizzard_tutorials_professions.lua),
  -- the text-to-speech button (blizzard_chatframe/shared/texttospeech.lua)
  "LINK_TRANSMOG_CUSTOM_SET_HELPTIP", "PROFESSIONS_NEW_TUTORIAL", "PROFESSIONS_NEW_TUTORIAL_ICON",
  "TEXT_TO_SPEECH_TUTORIAL",
  -- callouts the Forever client shows: the micro-button alerts (mainmenubarmicrobuttons.lua:17–21,
  -- 1554–1607), the bag tutorials (containerframe.lua:496–498; blizzard_tutorialreagentbag.lua:8–18), the map's
  -- bounty board and events tab (worldmapbountyboard.lua:516–637; questmapframe.lua:260–274), skyriding and
  -- lorewalking widgets, the Pandaren faction choice (destinyframe.lua:9–17), the friends list
  -- (friendslisttemplates.lua:285; camelot/friendsframe.lua:1328) and the spellbook's assisted combat
  -- (blizzard_spellbookframetutorials.lua:142)
  "COLLECTION_UNOPENED_PLURAL", "COLLECTION_UNOPENED_SINGULAR", "HEIRLOOMS_MICRO_BUTTON_SPEC_TUTORIAL",
  "TOYBOX_MICRO_BUTTON_SPEC_TUTORIAL", "SPEC_CHANGED_HAS_NEW_ABILITIES", "TALENT_MICRO_BUTTON_NO_SPEC",
  "TUTORIAL_REAGENT_BAG_STEP_1", "TUTORIAL_REAGENT_BAG_STEP_2", "DRAGON_RIDING_ACTIONBAR_TUTORIAL",
  "LOREWALKING_QUESTS_HIDDEN_HELP_TIP", "BOUNTY_TUTORIAL_INTRO", "BOUNTY_TUTORIAL_BOUNTY_FINISHED",
  "WORLD_MAP_ACTIVITY_TRACKER_LIST_INTRO", "RECRUIT_A_FRIEND_FACTION_PANDAREN_ALLIANCE",
  "RECRUIT_A_FRIEND_FACTION_PANDAREN_HORDE", "BIND_TO_ACCOUNT_UNTIL_EQUIP_TUTORIAL", "CROSS_FACTION_INVITE_HELPTIP",
  "SOCIAL_QUICK_JOIN_TAB_HELP_TIP", "EVENT_SCHEDULER_WORLD_MAP_HELP_TEXT", "WORLD_MAP_TUTORIAL6",
  "ASSISTED_COMBAT_ROTATION_DRAG_HELPTIP" }

-- The help-plate tooltip's texts; nothing else is ever read off it. A plate tile's hover is the same Init
-- with the section's ToolTipText (blizzard_helpplate.lua:141–146, 243): the spellbook's two sections
-- (blizzard_playerspells/spellbook/blizzard_spellbookframetutorials.lua:83, 93).
HelpTips.PLATE_KEYS = { "MAIN_HELP_BUTTON_TOOLTIP", "SPELLBOOK_HELP_1", "PLAYER_SPELLS_FRAME_MINIMIZE_TIP",
  -- the professions window's plate (a tile only when its widget shows, blizzard_professionscrafting.lua:
  -- 1205–1364) and the transmogrifier's (blizzard_transmog.lua:106–108)
  "PROFESSIONS_CRAFTING_HELP_FILTERS", "PROFESSIONS_CRAFTING_HELP_BAR", "PROFESSIONS_CRAFTING_HELP_BASIC_REAGENTS",
  "PROFESSIONS_CRAFTING_HELP_BEST_QUALITY", "PROFESSIONS_CRAFTING_HELP_FINISHING_REAGENTS",
  "PROFESSIONS_CRAFTING_HELP_GEAR", "PROFESSIONS_CRAFTING_HELP_OPTIONAL_REAGENTS", "PROFESSIONS_CRAFTING_HELP_STATS",
  "PROFESSIONS_GATHERING_JOURNAL_LIST_HELP", "PROFESSIONS_GATHERING_JOURNAL_STATS_HELP", "TRANSMOG_HELP_1",
  "TRANSMOG_HELP_2", "TRANSMOG_HELP_3" }
local PLATE_PAD = 30 -- the client's own padding (blizzard_helpplate.lua:215)

-- The pointer arrows' texts: the class tutorial's (blizzard_tutorials_classes.lua:88, 297, 310) and the new player
-- experience's, which runs below level 10 (blizzard_newplayerexperience/blizzard_tutorialtutorials.lua:1133, 1173,
-- 1218, 1266, 2394, 2448, 3096, 3173, 3369, 3549, 3666; the vendor arrow on camelot,
-- camelot/blizzard_tutoriallogicoverrides.lua:105). Nothing else is ever read off a pointer (the boost and Remix
-- tutorials, which never run on Forever, use it too).
HelpTips.POINTER_KEYS = { "NPEV2_SPEC_TUTORIAL_GOSSIP_CLOSED", "TALENT_MICRO_BUTTON_UNSPENT_TALENTS",
  "NPEV2_SELECT_TALENTS_TAB", "NPEV2_RELEASESPIRIT", "NPEV2_RETURN_TO_CORPSE", "NPEV2_DRAG_TO_EQUIP",
  "NPEV2_SUCCESSFULLY_EQUIPPED", "NPEV2_SELL_GREY_ITEMS", "NPE_CLICKLOOT", "NPEV2_CHATFRAME3", "NPE_QUESTREWARDCHOICE",
  "NPEV2_SHOW_BAGS", "NPEV2_OPENCHARACTERSHEET", "NPEV2_PRESS_KEY_TO_USE_ABILITY", "NPEV2_BUY_ITEMS_FROM_VENDOR" }
-- the reward-choice arrow's two lines, in the order the client joins them
local REWARD_RED, REWARD_CHOICE = { "NPE_QUESTREWARDCHOCIEREDITEMS" }, { "NPE_QUESTREWARDCHOICE" }
-- the client's default width and padding (blizzard_tutorialpointerframe.lua:100–108)
local POINTER_WIDTH, POINTER_PAD = 200, 40
local pointerKey = WFJ.Labels.keyer("pointer.") -- a pooled frame's record key, never a position

-- The atlas markup FormatString writes, as the `{Atlas|name:size}` token it came from (size 0: `{Atlas|name}`); a
-- markup of another shape is left as it is.
local function atlasToken(s)
  return (s:gsub("|A:([%w_%-]+):(%d+):(%d+):0:0|a", function(name, h, w)
    if h ~= w then return nil end
    if h == "0" then return "{Atlas|" .. name .. "}" end
    return "{Atlas|" .. name .. ":" .. h .. "}"
  end))
end

local function atlasMarkup(s)
  return (s:gsub("{Atlas|([%w_%-]+):?(%d*)}", function(name, size)
    size = tonumber(size) or 0
    return ("|A:%s:%d:%d:0:0|a"):format(name, size, size)
  end))
end

-- An arrow's FontString as Labels and the records see it: its text with the atlas markup read back as tokens, and
-- tokens written as markup. One adapter per FontString (weak), so a record keeps its widget identity.
local adapters = setmetatable({}, { __mode = "k" })
local function pointerText(fs)
  local a = adapters[fs]
  if a then return a end
  a = {}
  function a.GetText()
    local t = fs:GetText()
    return type(t) == "string" and atlasToken(t) or t
  end
  function a.SetText(_, t) fs:SetText(type(t) == "string" and atlasMarkup(t) or t) end
  function a.GetFont() return fs:GetFont() end
  function a.SetFont(_, path, size, flags) return fs:SetFont(path, size, flags) end
  adapters[fs] = a
  return a
end

-- The reward-choice arrow's two lines (as the adapter reads them) → the choice key and its `seq` args | nil
local function rewardParts(text)
  if type(text) ~= "string" then return nil end
  local red, choice = text:match("^(.-\n\n)(.+)$")
  local p1 = red and WFJ.Labels.part(red, REWARD_RED)
  local p2 = p1 and WFJ.Labels.part(choice, REWARD_CHOICE)
  if not p2 then return nil end
  return p2.key, { form = "seq", parts = { p1, p2 } }
end

local tipKey = WFJ.Labels.keyer("tip.") -- a pooled frame's record key, never a position

-- The ApplyText post-hook. → 1 | 0
function HelpTips.onApplyText(frame)
  if type(frame) ~= "table" then return 0 end
  return WFJ.Labels.show(SURFACE, tipKey(frame), frame.Text, nil, { only = HelpTips.KEYS })
end

-- The HelpPlateTooltip Init post-hook. → 1 | 0
function HelpTips.onPlateInit(frame)
  if type(frame) ~= "table" or type(frame.Text) ~= "table" then return 0 end
  local function refit()
    if type(frame.SetHeight) == "function" and type(frame.Text.GetHeight) == "function" then
      frame:SetHeight(frame.Text:GetHeight() + PLATE_PAD)
    end
  end
  local n = WFJ.Labels.show(SURFACE, "plate", frame.Text, refit, { only = HelpTips.PLATE_KEYS })
  refit() -- Alt held or released later re-renders through the record's refit
  return n
end

-- The TutorialPointerFrame:Show post-hook (its arguments; the frame is the one the call just stored). → 1 | 0
function HelpTips.onPointer(pointers, content0, _direction, _anchor, _x, _y, _relative, _backup, overrideWidth)
  if type(pointers) ~= "table" or type(pointers.InUseFrames) ~= "table" or type(pointers.NextID) ~= "number" then
    return 0
  end
  local frame = pointers.InUseFrames[pointers.NextID - 1]
  local content = type(frame) == "table" and frame.Content or nil
  local text = type(content) == "table" and content.Text or nil
  if type(text) ~= "table" or type(text.GetText) ~= "function" then return 0 end
  if text:GetText() ~= content0 then return 0 end -- not the frame this call wrote (a Show that stored nothing)
  local maxWidth = overrideWidth or POINTER_WIDTH
  local function refit()
    if type(text.GetStringWidth) ~= "function" or type(content.SetWidth) ~= "function" then return end
    text:SetWidth(maxWidth)
    local width = text:GetStringWidth()
    if width > maxWidth then width = maxWidth end
    content:SetHeight(text:GetHeight() + POINTER_PAD)
    content:SetWidth(width + POINTER_PAD)
  end
  local shown = pointerText(text)
  local key, args = rewardParts(shown:GetText())
  local n
  if key then
    n = WFJ.Labels.showArgs(SURFACE, pointerKey(frame), shown, key, args, refit)
  else
    n = WFJ.Labels.show(SURFACE, pointerKey(frame), shown, refit, { only = HelpTips.POINTER_KEYS })
  end
  if n > 0 then refit() end -- Alt held or released later re-renders through the record's refit
  return n
end

local pointerHooked = false
-- → true when the tutorial manager's pointer frame was hooked
local function hookPointer()
  Compat.declare(SURFACE, "pointerFrame", { "TutorialPointerFrame" })
  local pointers = Compat.get(SURFACE, "pointerFrame")
  if pointerHooked or type(pointers) ~= "table" or type(pointers.Show) ~= "function" then return pointerHooked end
  pointerHooked = true
  hooksecurefunc(pointers, "Show", HelpTips.onPointer)
  return true
end

local plateHooked = false
-- → true when the help-plate tooltip was hooked
local function hookPlate()
  Compat.declare(SURFACE, "plateTooltip", { "HelpPlateTooltip" })
  local plate = Compat.get(SURFACE, "plateTooltip")
  if plateHooked or type(plate) ~= "table" or type(plate.Init) ~= "function" then return plateHooked end
  plateHooked = true
  hooksecurefunc(plate, "Init", HelpTips.onPlateInit)
  return true
end

local hooked = setmetatable({}, { __mode = "k" })

local function hookFrame(frame, mixinApply)
  if type(frame) ~= "table" or hooked[frame] or type(frame.ApplyText) ~= "function" then return false end
  hooked[frame] = true
  -- a frame made after the mixin hook already carries the hooked ApplyText
  if frame.ApplyText ~= mixinApply then hooksecurefunc(frame, "ApplyText", HelpTips.onApplyText) end
  return true
end

local done = false

-- Called by Main after Compat.init. → true when HelpTip was found
function HelpTips.init()
  hookPlate()
  hookPointer()
  Compat.declare(SURFACE, "helpTip", { "HelpTip" })
  Compat.declare(SURFACE, "mixin", { "HelpTipTemplateMixin" })
  local helpTip, mixin = Compat.get(SURFACE, "helpTip"), Compat.get(SURFACE, "mixin")
  if type(helpTip) ~= "table" or type(mixin) ~= "table" or type(mixin.ApplyText) ~= "function" then return false end
  if done then return true end
  done = true
  hooksecurefunc(mixin, "ApplyText", HelpTips.onApplyText)
  local pool = helpTip.framePool
  if type(pool) == "table" then
    if type(pool.EnumerateActive) == "function" then
      for frame in pool:EnumerateActive() do
        if hookFrame(frame, mixin.ApplyText) then HelpTips.onApplyText(frame) end -- already laid out: text only
      end
    end
    for _, frame in ipairs(type(pool.inactiveObjects) == "table" and pool.inactiveObjects or {}) do
      hookFrame(frame, mixin.ApplyText)
    end
  end
  return true
end
