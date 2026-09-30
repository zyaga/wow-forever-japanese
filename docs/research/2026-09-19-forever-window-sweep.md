# Research: every window the Forever (`camelot`) client loads, and what the addon does about each

- **Date:** 2026-09-19
- **Question:** Which Blizzard addons does the Forever client load in game, which of them open a window a player can
  reach, and for each window: where is its entry point, who writes its text, and what does the addon do with it?
- **Client:** World of Warcraft: Forever beta, build **1.60.1.69913**. UI extracted read-only with `wfj.dev.client_ui`
  (the read-only ADR-021 path), with the addons' `.toc` files in its path list. Content evidence from the
  client's own tables (`db2@1.60.1.69913`).
- **Citations:** `path:line`, relative to `Interface/AddOns`, lowercased as extracted. The extract is not committed.
  Short quotations from it are.
- **Authoritative data:** [`pipeline/forever_addons.txt`](../../pipeline/forever_addons.txt) (the resolver's output),
  [`pipeline/forever_addon_dispositions.txt`](../../pipeline/forever_addon_dispositions.txt) (one line per in-game addon,
  with the full evidence) and [`pipeline/forever_titles.txt`](../../pipeline/forever_titles.txt) (every `SetTitle` site).
  This document is the index and the method. Where it and a data file differ, the data file wins. Every surface
  module's header comment has the full list of widgets and writers.

The [camelot surface re-target](2026-09-19-camelot-surface-retarget.md) (ADR-029) moved the windows the addon already
had. Its file map listed only those surfaces, so a window that exists only on Forever was never inventoried. The
first in-game pass found four of them (the Professions window, the Skills and Quest Log titles, two
Skills headers). This sweep lists every other one.

## Options

| Option | Pros | Cons |
|---|---|---|
| A. Work from a candidate list (~26 named windows) | Small, quick | The list is a sample. A window nobody named stays English with nothing to flag it: the failure that prompted this sweep |
| B. Resolve every addon from the client's TOCs; give each in-game addon one recorded disposition with evidence; a test holds the list to the resolver | Mechanical and complete; a new build's new addon fails the test; every "no" carries its reason | Every addon must be read, including ~90 retail-era ones |
| C. Scan every file in the extract, loaded or not | No resolver needed | Counts login-screen and gated files; about 7,500 names of noise with no way to tell reachable from dead |

B was taken ([ADR-030](../adr/030-every-window-the-forever-client-loads.md)).

## Findings

### 1. Method

**The resolver** (`pipeline/wfj/dev/client_addons.py`, pinned by `tests/python/test_client_addons.py`) reads each
addon's TOC under ADR-029's rule:

- `[Family]` in a path is `Mainline`, `[Game]` is `Camelot`.
- A TOC line, or a `## AllowLoadGameType:` header, loads when it names `camelot` or `mainline`. An
  `ExcludeLoadGameType` naming either drops it. `[AllowLoadTextLocale …]` without `enUS` drops the line.
- `## AllowLoad: Glue` (header) and `[AllowLoad glue]` (line) mark the login screens, where no addon runs.
- `<Addon>_Mainline.toc` is read in preference to `<Addon>.toc`.
- An XML file's `<Include file>` and `<Script file>` are followed, relative to that XML. Paths resolve through a
  casefold index, because the extract is lowercased.

Each addon gets a state: `gated` (the header keeps camelot out), `glue`, `login`, or `lod` (`LoadOnDemand`).

**`standard` and `classic` do not include `camelot`.** Where Blizzard means "retail and Forever" it names both, and a
`standard`-only addon is a retail-only system. The TOC headers, verbatim:

```
blizzard_cooldownviewer/blizzard_cooldownviewer.toc      2:## AllowLoadGameType: standard, camelot
blizzard_damagemeter/blizzard_damagemeter.toc            2:## AllowLoadGameType: standard, camelot
blizzard_pvpmatch/blizzard_pvpmatch.toc                  4:## AllowLoadGameType: standard, camelot
blizzard_stableui/blizzard_stableui.toc                  2:## AllowLoadGameType: standard, camelot
blizzard_guildrename/blizzard_guildrename.toc            5:## AllowLoadGameType: standard, camelot
blizzard_restrictedaddonenvironment/….toc                3:## AllowLoadGameType: classic, standard, camelot
blizzard_questtimer/blizzard_questtimer.toc              6:## AllowLoadGameType: classic, camelot
blizzard_groupfinder_vanillastyle/….toc                  5:## AllowLoadGameType: classic, camelot
blizzard_encounterjournal/blizzard_encounterjournal.toc  7:## AllowLoadGameType: standard, classic
blizzard_housingdashboard/blizzard_housingdashboard.toc  5:## AllowLoadGameType: standard
blizzard_expansionlandingpage/….toc                      5:## AllowLoadGameType: standard
blizzard_delvesdifficultypicker/….toc                    6:## AllowLoadGameType: standard
```

Thirteen headers read `standard, camelot`. If `standard` covered camelot, `camelot` in those lists would be redundant
thirteen times over. The quest timer and the Vanilla-style group finder name `classic, camelot` for the same reason.
So the Encounter Journal (`standard, classic`), every Housing addon, the expansion landing page and the difficulty picker (`delvesdifficultypicker`)
(`standard`) are `gated`.

**Entry points.** For every `login` / `lod` addon, the sweep looked for a way in that exists in the camelot load set:

- A load-on-demand addon's `[Bootstrap]` file loads at login even when the addon does not. Every global it defines,
  and the addon's name, was searched for across every file of every camelot load set. A bootstrap nothing calls is no
  entry point.
- The event hub `blizzard_game` loads `Shared\`, `[Family]\` and `[Game]\` event files, and `GameEvent.InitEvents`
  registers all three handler tables (`blizzard_game/camelot/eventrouting.lua:22–26`). Every mainline event handler
  is therefore live on camelot unless camelot overrides it.
- NPC windows: `RegisterPlayerInteraction(Enum.PlayerInteractionType.*)` in the bootstraps.
- Key bindings: `blizzard_framexml/bindings_camelot.xml` (no archaeology, garrison, landing page, covenant or vault
  binding). Micro buttons: `blizzard_micromenu/camelot/micromenucontaineroverrides.lua` (no achievement button, no
  expansion landing page button; Collections, Legacy and Store are placed, `:8`, `:13`, `:16`).
- Slash commands (`blizzard_chatframebase/shared/slashcommands.lua`, `mainline/slashcommandsoverrides.lua`), the game
  menu (`blizzard_gamemenu/shared/gamemenuframe.lua`) and unit menus.

**Content.** A retail system can have a live entry point and still never open, because the window needs content it
has none of. The Forever tables settle that from source (§5).

### 2. Counts

| | count |
|---|---|
| Blizzard addon TOCs in the Forever extract | 347 |
| `gated` away from camelot by their header | 47 |
| `glue` (login screen only) | 16 |
| load in game on camelot | **283**: 191 at login, 92 load-on-demand |
| … with a window the addon renders (`surface`) | 106 addons, 120 `FOREVER_WINDOWS` surfaces (100 new in this sweep) over 724 files |
| `SetTitle(` call sites in the surface addons' load sets | 83 (41 `key`, 25 `dynamic`, 16 `name`, 1 `ruled`) |

A first scan measured a ceiling of 7,573 uninventoried names over 190 addons. That scan also caught slash words, error
lines, popups, menu entries, retail-era systems and regex noise. The triage kept 3,346 as new dictionary keys and
excluded 1,437 with a reason (33 older exclusions were lifted, so the file grows by 1,404: 990 → 2,394).

### 3. The disposition set

Every `login` / `lod` addon has exactly one of these (`tests/python/test_forever_windows.py` checks the set,
completeness and the evidence rules):

| disposition | count | meaning | evidence the test requires |
|---|---|---|---|
| `surface <names>` | 106 | the addon's files are scanned for those `FOREVER_WINDOWS` surfaces | each name is a `FOREVER_WINDOWS` key, and every scanned file belongs to a `surface` addon |
| `library` | 21 | templates or utilities whose text reaches the screen only through a consumer surface | a reason |
| `no-text` | 73 | no player-facing text: logic, shims, textures, numbers, developer tools with literal English | a reason |
| `unreachable` | 9 | no entry point in the camelot load set | `<path>:<line>` or "no reference in the load set" |
| `no-content` | 23 | an entry point exists on camelot, but the Forever tables hold none of the content the window opens on | the entry point `path:line` **and** the table evidence |
| owned elsewhere | 19 | text another piece of work covered (tutorials, client-table text, menus and social); see §8 | the owning work |
| `not-a-window` | 32 | chat / error lines, slash words, StaticPopups, spoken text, and secure-environment windows addon code cannot reach | a reason |

The counts above are the sweep's. The data file has moved on since: seven `not-a-window` lines became `surface popups`
(`staticpopup`, `staticpopup_game`, `addfriend`, `addonperformance`, `hardcoreui`, `kiosk`, `lfgutil`;
[ADR-037](../adr/037-staticpopup-dialogs-and-owned-keys.md)), `customizationui` moved from `library` to
`surface barbershop`, `framerateframe` from `no-text` to `surface hudlabels`, and the lines owned elsewhere were
resolved or recorded as `planned` (text not handled yet, left as the client shows it).

`no-content` was added during the sweep. The first pass put the covenant, garrison, azerite and Great Vault addons
under `unreachable`, but their entry points exist: an event handler in `blizzard_game`, a player interaction type, a
paper doll call. "No entry point" would have been false. What stops them is data. Keeping the two apart means an
`unreachable` line is a claim about the client's code, and a `no-content` line is a claim about the server's content.
They fail in different ways, and they are checked in game differently.

### 4. Surfaces, by family

Entry points only. Writers are in each module's header and the disposition line.

**The four in-game gaps**

| addon (state) | surface · module | entry point |
|---|---|---|
| blizzard_professionsbook (lod) | professions · UI/Professions.lua | Professions micro button (`blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:669`), `TOGGLEPROFESSIONBOOK` (`blizzard_framexml/bindings_camelot.xml:1215`) → `blizzard_professionsbook_bootstrap.lua:7–20`. The standalone book XML is `[ExcludeLoadGameType camelot]`; camelot shows `ProfessionsFrame.BookPage` |
| blizzard_professions (lod) | professions, crafting · UI/Professions.lua, UI/Crafting.lua | `TRADE_SKILL_SHOW` (`blizzard_game/mainline/eventrouting.lua:107`, `eventimplementation.lua:475–477`). Camelot builds CraftingPage + BookPage only (`camelot/blizzard_professionsframe.xml:66–79`); specializations and crafter orders are never instantiated |
| blizzard_professionstemplates (lod) | crafting, customerorders | templates of the professions family |
| blizzard_professionscustomerorders (lod) | customerorders · UI/CustomerOrders.lua | `CRAFTINGORDERS_SHOW_CUSTOMER` (`eventrouting.lua:30`, `eventimplementation.lua:483–489`). Whether a Forever NPC sends it is an in-game check |
| blizzard_questtimer (login) | questtimer · UI/QuestTimer.lua | `QuestTimerFrame`, a child of the objective tracker (`blizzard_questtimer.lua:25–31`) |

The professions title is written by `SetTitleFormatted(TRADE_SKILL_TITLE, TRADE_SKILLS)`
(`blizzard_professions/camelot/blizzard_professionsframe.lua:91–99`), which writes `TitleText` directly
(`blizzard_sharedxml/portraitframe.lua:11–17`), so UI/Professions hooks it beside `Labels.title`. The other three gaps
are titles on existing surfaces:

- **Skills:** `SKILLS` title, and the `STAT_CATEGORY_WEAPON_SKILLS` / `LANGUAGES_LABEL` headers in
  `SkillsFrame.ScrollBox` (`blizzard_uipanels_game/camelot/skillsframe.lua:127–141, 197–213, 321–325`).
- **Character sub-panes:** `CharacterFrame`'s title (`camelot/characterframe.lua:254–258`;
  `characterframeconstants.lua:9–34`) is `REPUTATION` / `SKILLS` / `PVP` / `CURRENCY` / `STATISTICS` on a sub-pane and
  the player's name on the paperdoll. UI/Character releases the record on the paperdoll, so a player named "Skills"
  is never translated.
- **Quest map:** `WorldMapFrame.BorderFrame:SetTitle(MAP_AND_QUEST_LOG | WORLD_MAP)` (`blizzard_worldmap.lua:26–27,
  34–42`). No camelot file writes `QUEST_LOG` to a title. It stays in `only` in case the in-game pass shows otherwise.
- **Communities:** `CommunitiesFrame:SetTitle(COMMUNITIES_FRAME_TITLE)` (`blizzard_communities/communitiesframe.lua:103`).

**Blizzard_UIPanels_Game, maps and the tracker**

| addon (state) | surface · module | entry point |
|---|---|---|
| blizzard_uipanels_game (login) | trade · UI/Trade.lua | `TRADE_SHOW` (`mainline/tradeframe.lua:7, 32–38`) |
| | loot · UI/Loot.lua | `LOOT_OPENED` (`mainline/lootframe.lua:59, 131–150`) |
| | grouploot · UI/GroupLoot.lua | `START_LOOT_ROLL` → GroupLootFrame1–4 (`mainline/grouplootframe.xml:641–644`), MasterLooterFrame (`:707`) |
| | taxi · UI/Taxi.lua | `TAXIMAP_OPENED` for `Enum.UIMapSystem.Taxi` (`blizzard_game/mainline/eventimplementation.lua:725–731`) |
| | tabard · UI/Tabard.lua | `TabardFrame_Open` (`mainline/tabardframe.lua:21–27`) |
| | petition · UI/Petition.lua | `PETITION_SHOW` (`mainline/petitionframe.xml:186–198`) |
| | guildregistrar · UI/GuildRegistrar.lua | `PlayerInteractionType.Registrar` (`mainline/guildregistrarframe.lua:14–21`) |
| | dressup · UI/DressUp.lua | `DressUpItemLink` / `DressUpVisual` (`mainline/dressupframes.lua:10–24, 88–108`) |
| | castingbar · UI/CastingBar.lua | `PlayerCastingBarFrame` (`mainline/castingbarframe.xml:482`) |
| | maplegend · UI/MapLegend.lua | `QuestMapFrame.MapLegend`; the tab camelot hides returns after a gamepad session (`blizzard_worldmap/blizzard_worldmap.lua:1188`) |
| blizzard_worldmap (login) | worldmap · UI/WorldMap.lua | the map key / micro menu; nav home, filter and pin button tooltips, coordinates, zone timer (`blizzard_worldmaptemplates.lua:357–361, 435–447, 553–676`) |
| blizzard_sharedmapdataproviders (lod, RequiredDep of the world map) | mappins · UI/MapPins.lua; flightmap | pin tooltips: every pin carries `pinTemplate` (`blizzard_mapcanvas/blizzard_mapcanvas.lua:280–288`) |
| blizzard_flightmap (lod) | flightmap · UI/FlightMap.lua | `TAXIMAP_OPENED` for any other map system (`eventimplementation.lua:726–732`; bootstrap `:3–11`) |
| blizzard_battlefieldmap (lod) | battlefieldmap · UI/BattlefieldMap.lua | `TOGGLEBATTLEFIELDMINIMAP` (`bindings_camelot.xml:1239–1241`), the queue menu (`blizzard_queuestatusframe/mainline/queuestatusframe.lua:1348–1352`) |
| blizzard_objectivetracker (login) | questmap, tracker · UI/Tracker.lua | `ObjectiveTrackerManager:Init` adds eleven modules (`blizzard_objectivetrackermanager.lua:192–215`) |

Trade, taxi, tabard, petition, guild registrar, dress-up, casting bar and group loot have frames of the same name on
Classic Era. Each of those modules first checks `WFJ.Camelot.present()` (or a camelot-only widget: the loot
`ScrollBox`, `LootButtonContainer`), so Classic Era is unchanged.

**Commerce and NPC windows**

| addon (state) | surface · module | entry point |
|---|---|---|
| blizzard_auctionhouseui (lod) | auctionhouse · UI/AuctionHouse.lua | `PlayerInteractionType.Auctioneer` (`shared/blizzard_auctionhouseui_bootstrap.lua:7–27, 44`) |
| blizzard_barbershopui (lod) | barbershop · UI/BarberShop.lua | `BARBER_SHOP_OPEN` (`blizzard_game/shared/eventrouting.lua:48`; bootstrap `:3–11`) |
| blizzard_blackmarketui (lod) | blackmarket · UI/BlackMarket.lua | `PlayerInteractionType.BlackMarketAuctioneer` (bootstrap `:20–31`) |
| blizzard_tokenui (login) | currency, currencytransfer · UI/Currency.lua, UI/CurrencyTransfer.lua | the character window's Currency tab (`blizzard_uipanels_game/camelot/characterframe.lua:72, 110–116`); transfer from the detail pane (`blizzard_currencytransfer.lua:49–55, 169–187`) |
| blizzard_guildbankui (lod) | guildbank · UI/GuildBank.lua | `PlayerInteractionType.GuildBanker` (bootstrap `:7–33`) |
| blizzard_guildcontrolui (lod) | guildcontrol · UI/GuildControl.lua | the Communities `GuildControlButton` (`blizzard_communities/communitiesframe.xml:258–264`), the guild unit menu (`blizzard_unitpopup/mainline/unitpopupbuttons.lua:237–239`) |
| blizzard_guildrename (login) | guildrename · UI/GuildRename.lua | `PlayerInteractionType.GuildRename` (`blizzard_guildrename.lua:40–54`) |
| blizzard_iteminteractionui (lod) | iteminteraction · UI/ItemInteraction.lua | `PlayerInteractionType.ItemInteraction` (bootstrap `:7–17`) |
| blizzard_itemsocketingui (lod) | itemsocketing · UI/ItemSocketing.lua | `SOCKET_INFO_UPDATE` (`blizzard_game/mainline/eventimplementation.lua:507–509`) |
| blizzard_itemupgradeui (lod) | itemupgrade · UI/ItemUpgrade.lua | `PlayerInteractionType.ItemUpgrade` (bootstrap `:7–33`) |
| blizzard_obliterumui (lod) | obliterumforge · UI/ObliterumForge.lua | `PlayerInteractionType.ObliterumForge` (bootstrap `:7–17`) |
| blizzard_scrappingmachineui (lod) | scrappingmachine · UI/ScrappingMachine.lua | `PlayerInteractionType.ScrappingMachine` (bootstrap `:7–17`) |
| blizzard_stableui (login, `standard, camelot`) | stable · UI/Stable.lua | `PET_STABLE_SHOW` (`camelot/blizzard_stableui.lua:7, 41–42`) |
| blizzard_subscriptioninterstitialui (lod) | subscriptioninterstitial · UI/SubscriptionInterstitial.lua | trial accounts on entering the world (`eventimplementation.lua:829–831`) |
| blizzard_transmog (lod) | transmog · UI/Transmog.lua | `PlayerInteractionType.Transmogrifier` (`blizzard_transmog_bootstrap.lua:3–17`) |

Whether Forever places a black market, item upgrade, item interaction, obliterum, scrapping, transmog or guild vault
NPC is server content, so it is an in-game question. The windows have live entry points and no table evidence
against them, so they were built. Mail, bags and trainer (from the camelot re-target) had their unlisted files triaged: no new key.

**Character-adjacent**

| addon (state) | surface · module | entry point |
|---|---|---|
| blizzard_achievementui (lod) | achievement · UI/Achievement.lua | `/achievements` (`blizzard_chatframebase/shared/slashcommands.lua:1310–1320`), toast click (`blizzard_framexml/mainline/alertframesystems.lua:400–417`), tracker header, Compare Achievements. No micro button on camelot. Game rule `AchievementsPanelDisabled` (`blizzard_achievementui.lua:217`) is an in-game check |
| blizzard_calendar (lod) | calendar · UI/Calendar.lua | `/calendar` (`mainline/slashcommandsoverrides.lua:200–206`), the minimap clock, guild news |
| blizzard_clickbindingui (lod) | clickbinding · UI/ClickBinding.lua | `/click` (`slashcommandsoverrides.lua:361`), the key bindings panel (`blizzard_settingsdefinitions_frame/mainline/keybindingsoverrides.lua:45`) |
| blizzard_collections (lod) | collections, mountjournal, petjournal, wardrobe · four modules | Collections micro button (`micromenucontaineroverrides.lua:13`); five side tabs (`camelot/blizzard_collectionstabs.xml:20–46`); the pet tab is the classic companion journal |
| blizzard_inspectui (lod) | inspect · UI/Inspect.lua | unit menu Inspect (`blizzard_unitpopupshared/unitpopupsharedbuttonmixins.lua:289`), `/inspect`; camelot shows the paper doll and guild panes only |
| blizzard_legacysystem (lod, Forever-only) | legacy, spellsearch · UI/Legacy.lua | Legacy micro button (`mainmenubarmicrobuttons.lua:1043–1046`; placed `micromenucontaineroverrides.lua:8`), `TOGGLELEGACYSYSTEM` (`bindings_camelot.xml:1218`) |
| blizzard_macroui (lod) | macro · UI/Macro.lua | game menu Macros (`gamemenuframe.lua:261`), `/macro` (`slashcommands.lua:1218`) |
| blizzard_spellsearch (lod), blizzard_sharedtalentui (login) | spellsearch · UI/SpellSearch.lua | hosted by the talent tree, spellbook and Legacy tree (`camelot/classtalents/blizzard_classtalentsframe.xml:401, 416`) |
| blizzard_timemanager (lod, loaded at login) | timemanager · UI/TimeManager.lua | `PLAYER_LOGIN` → `TimeManager_LoadUI` (`blizzard_game/shared/eventimplementation.lua:175–178`); the clock; `/stopwatch` |
| blizzard_playerspells (lod) | spellbook, talents (camelot re-target) | 29 unlisted load-set files triaged: loadout dialogs and import/export are behind the LoadSystem camelot hides (`camelot/classtalents/blizzard_classtalentsframe.lua:222–223`); PvP talents are stubbed ("No PvP talents in Camelot", `:205–211`); hero talents container (`camelot xml:376`) is an in-game check |

**HUD**

| addon (state) | surface · module | entry point |
|---|---|---|
| blizzard_combattext (lod) | combattext · UI/CombatText.lua | `CombatText_LoadUI` (bootstrap `:3–5`); post-hook `CombatText:AddMessage` (`shared/combattext.lua:335–430`) |
| blizzard_cooldownviewer (login, `standard, camelot`) | cooldownviewer · UI/CooldownViewer.lua | `/cdm` (`slashcommandregistration.lua:1–3`), edit mode (`blizzard_editmode/shared/editmodesystemtemplates.lua:1244, 3015`) |
| blizzard_damagemeter (login, `standard, camelot`) | damagemeter · UI/DamageMeter.lua | shown while `damageMeterEnabled` is on (`damagemeter.lua:166–199`) |
| blizzard_deathrecap (lod) | deathrecap · UI/DeathRecap.lua | the death dialog (`blizzard_staticpopup_game/mainline/gamedialogdefs.lua:189, 247`), `death:` links |
| blizzard_gamepadactionbars (login, camelot-only) | gamepadedit · UI/GamepadEdit.lua | gamepad prompts of the spellbook, bags, paper doll, macro window, tracker |
| blizzard_gamepad, blizzard_gamepadsharedutility, blizzard_gamepadtargeting (login, camelot), added later | gamepad · UI/Gamepad.lua | gamepad input mode (`InputUtil.IsGamepadUIEnabled`): window footer prompts (`InputPromptMixin:SetPromptText`), the persistent controller legend, the radial main menu (`GamepadRadial:ActivateRadial`), the cinematic skip button, the "More Actions" menus (`promptedbinding.lua:126–181`, via UI/MenusUntagged) ([ADR-040](../adr/040-gamepad-hud.md)) |
| blizzard_mirrortimer, blizzard_swingtimer, blizzard_actionstatus, blizzard_statustrackingbar (login) | hudlabels · UI/HudLabels.lua | breath / fatigue bars (`mirrortimer.lua:50–57`), swing timers (`blizzard_swingtimer.lua:161–163`), screenshot message (`mainline/actionstatus.lua:50–55`), honor bar (`mainline/honorbar.lua:14–23`) |
| blizzard_actionbar, blizzard_overrideactionbar, blizzard_durabilityframe (login) | help · UI/HudTips.lua | vehicle leave (`shared/vehicleleavebutton.lua:12–23`), override pitch / leave (`overrideactionbar.xml:171–206, 262–275`), durability (`durabilityframe.lua:31–43`), totem flyout (`shared/multicastactionbarframe.lua:527–537`) |
| blizzard_minimap (login) | help · UI/Minimap.lua | zone button, tracking, mail, clock, addon compartment, zoom (`mainline/minimap.lua:84–103, 288–317, 485–490, 826–831`) |
| blizzard_pvpmatch (login, `standard, camelot`) | pvpmatch · UI/PvPMatch.lua | `PVP_MATCH_COMPLETE` (`pvpmatchresults.lua:205–207`), the queue eye (`queuestatusframe.lua:1573–1593`) |
| blizzard_queuestatusframe (login) | queuestatus · UI/QueueStatus.lua | the eye's hover panel (`mainline/queuestatusframe.lua:192–196`) |
| blizzard_compactraidframes (login) | raidmanager · UI/RaidManager.lua | shown in a group (`mainline/blizzard_compactraidframemanager.lua:295–306`) |
| blizzard_unitframe (login) | unitframes · UI/UnitFrames.lua | dead / offline words, group titles, unit tooltip line (`mainline/targetframe.xml:182, 187`; `shared/compactunitframe.lua:1085–1115`) |

Combat text renders only whole-message words and two number-only templates. Messages that start with `-`, `+`, `[`
or `(`, and number-plus-fragment composites, are left alone: on this client the amounts can be secret values
(`blizzard_sharedxmlbase/securetypes.lua:6`).

**Social and group**

| addon (state) | surface · module | entry point |
|---|---|---|
| blizzard_groupfinder_vanillastyle (lod, `classic, camelot`) | groupfinder, friends · UI/GroupFinder.lua | `ToggleLFGParentFrame` (`blizzard_game/shared/game.lua:81–85`), `TOGGLELFGTAB` (`bindings_camelot.xml:1256`), the queue eye |
| blizzard_channels, blizzard_voicetogglebutton (login) | channels · UI/Channels.lua | the chat frame's channel button (`blizzard_chatframebase/mainline/channelframebuttonmixin.lua`) |
| blizzard_quickjoin (login) | quickjoin · UI/QuickJoin.lua | the Friends Quick Join tab (`blizzard_friendsframe/camelot/friendsframe.lua:472`) |
| blizzard_recentallies (login) | recentallies · UI/RecentAllies.lua | Recent Allies tab (`camelot/friendsframe.lua:456, 622`) |
| blizzard_recruitafriend (login) | recruitafriend · UI/RecruitAFriend.lua | Recruit A Friend tab (`camelot/friendsframe.lua:458, 624`) |
| blizzard_reportframe, blizzard_reportframeshared (login) | reportframe · UI/ReportFrame.lua | unit menus, mail (`blizzard_mailframe/mailframe.lua:1137`), the group finder |
| blizzard_helpframe (login) | helpframe · UI/HelpFrame.lua | game menu Support (`gamemenuframe.lua:253`) |
| blizzard_gmchatui, blizzard_wowsurveyui, blizzard_behavioralmessaging (lod) | statusnotices · UI/StatusNotices.lua | loaded by server events (`blizzard_game/shared/eventimplementation.lua:43, 297, 302`) |
| blizzard_bnet (login) | bnettoast · UI/BNetToast.lua | `BNToastFrame`, `TimeAlertFrame` (`mainline/bnet.lua:193–298, 350–364`) |
| blizzard_islandspartyposeui, blizzard_matchcelebrationpartyposeui, blizzard_warfrontspartyposeui, blizzard_partyposeui | partypose · UI/PartyPose.lua | `SHOW_PARTY_POSE_UI` (`blizzard_game/mainline/eventimplementation.lua:163–165`) |

Friends and Communities (camelot re-target) keep their surfaces; their SocialUI card views were left to the menus and social work.

**Settings and system windows**

| addon (state) | surface · module | entry point |
|---|---|---|
| blizzard_settings_shared, blizzard_settingsdefinitions_frame, blizzard_settingsdefinitions_shared, blizzard_settings, blizzard_accessibilitytemplates | settingspanel · UI/SettingsPanel.lua | Esc → Options (`blizzard_settingspanel.xml:4`) |
| blizzard_settingsdefinitions_frame | settingstutorials · UI/SettingsTutorials.lua | "About Nameplates" / "About the Ping System" (`nameplates.lua:338`, `pingsystem.lua:9, 137`) |
| blizzard_editmode (login) | editmode · UI/EditMode.lua | game menu Edit Mode (`gamemenuframe.lua:237–238`) |
| blizzard_quickkeybind (login) | quickkeybind · UI/QuickKeybind.lua | key bindings page; edit mode (`editmodesystemtemplates.lua:1219`) |
| blizzard_colorpickerframe (login) | colorpicker · UI/ColorPicker.lua | every colour swatch |
| blizzard_chatframe (login) | chatconfig, texttospeech · UI/ChatConfig.lua, UI/TextToSpeech.lua | a chat tab's menu (`blizzard_chatframebase/mainline/floatingchatframe.lua:782`), `/tts` (`shared/texttospeechframe.lua:526`) |
| blizzard_chatframebase (login) | chattabs · UI/ChatTabs.lua | tab hover (`mainline/floatingchatframe.xml:357–372`), overflow count (`floatingchatframe.lua:2766–2770`) |
| blizzard_combatlog (lod, loaded at login) | combatlog · UI/CombatLog.lua | `CombatLog_LoadUI` at `PLAYER_LOGIN` (`eventimplementation.lua:175–178`) |
| blizzard_addonlist (login) | addonlist · UI/AddonList.lua | game menu AddOns (`gamemenuframe.lua:230`) |
| blizzard_scripterrorsframe (login) | scripterrors · UI/ScriptErrors.lua | a displayed Lua error (`blizzard_scripterrorsframe.lua:130`) |
| blizzard_splashframe (login) | splash · UI/Splash.lua | `OPEN_SPLASH_SCREEN`; game menu What's New (`gamemenuframe.lua:233–235`) |
| blizzard_eventtrace (lod) | eventtrace · UI/EventTrace.lua | `/etrace` (`slashcommands.lua:1334–1336`) |
| blizzard_chromietimeui (lod) | chromietime · UI/ChromieTime.lua | `PlayerInteractionType.ChromieTime` (bootstrap `:3–17`) |

The Options window and Edit Mode are built from data (initializers, `ScrollBox` rows). They render through
`UI/LabelTree.lua` walks keyed by widget with a required `only` list, after the list's own layout callback. Nothing
on an addon's own Options page is touched (`blizzard_categorylist.lua:316–326`).

**Blizzard_FrameXML and retail-era systems with an entry point and plausible content**

| addon | surface · module | entry point |
|---|---|---|
| blizzard_framexml (login) | alerts, bossbanner, cinematic, coinpickup, combatfeedback, equipmentflyout, ghostframe, guildinvite, instanceabandon, instancedifficulty, lossofcontrol, loothistory, pethappiness, readycheck, stacksplit, streamingicon, zonetext | per frame, e.g. `AlertFrame_ShowNewAlert` (`mainline/alertframes.lua:173–198`), `BOSS_KILL` (`bossbannertoast.lua:177–205`), `GUILD_INVITE_REQUEST` (`guildinviteframe.xml:140`), `LossOfControlMixin:SetUpDisplay` (`lossofcontrolframe.lua:142–207`), `EquipmentFlyout_Show` (`camelot/equipmentflyout.lua:229`) |
| blizzard_majorfactions (login) | majorfactiontoast · UI/MajorFactionToast.lua | renown / unlock toasts (`blizzard_majorfactionrenowntoast.lua:39`). Camelot's PvP rank and reputation windows read `C_MajorFactions` (`blizzard_uipanels_game/camelot/pvprankframe.lua:91, 134`), so the system is live |
| blizzard_playerchoice (lod) | playerchoice · UI/PlayerChoice.lua | `PLAYER_CHOICE_UPDATE` (`eventimplementation.lua:637–639, 777`), a generic server-driven window |
| blizzard_pagedcontent | spellbook | its paging controls write the spellbook's page text |

FrameXML frames with no surface: the achievement display template (only consumer allied races), archaeology /
artifact / azerite toasts and battle pet tooltips (no content, §5), `DestinyFrame` (Pandaren only), reward-track
templates (covenant / major-faction renown pages), the retail honor-level system (camelot's PvP is the rank frame;
in-game check), Party Sync (`questsession`: off on Forever, since `camelot/questmapframeutils.lua:3–5`
`IsPartySyncEnabled()` returns false, so the quest map hides its Party Sync button, `mainline/questmapframe.lua:687`,
and no session can start; its keys are excluded with that reason), the battleground countdown (`TIMER_MINUTES_DISPLAY` is `%d:%02d`), talking heads (server
text), the Korean ratings frame, and helpers with no dictionary text. (Event toasts, first listed here as not built,
were built later: `UI/Alerts`.)

### 5. `no-content`: live entry point, no content on Forever (23)

**Table evidence (`db2@1.60.1.69913`):** the item, spell and quest tables hold no retail-only content: no Azerite, Covenant, Renown, Torghast, Battle Pet, Garrison or Delver's Bounty rows, no retail-era spells, and no quest between 10,000 and 49,999 (every Wrath to Legion range).

| addon | entry point on camelot | content the window needs, absent |
|---|---|---|
| alliedracesui | `ALLIED_RACE_OPEN` (`blizzard_game/mainline/eventimplementation.lua:189–191`); `AlliedRaceDetailsGiver` (bootstrap `:8`) | allied racials |
| animadiversionui | `ANIMA_DIVERSION_OPEN` (`:205–207`) | covenant abilities / items |
| archaeologyui | `ARCHAEOLOGY_TOGGLE`, `_SURVEY_CAST` (`:588–595`); no camelot binding | Archaeology, Survey |
| artifactui | `ARTIFACT_*` (`:526–546`) | a Legion artifact weapon |
| azeriteessenceui | `AzeriteForge` (bootstrap `:27`); camelot paper doll (`camelot/paperdollframe.lua:2101`) | Heart of Azeroth |
| azeriterespecui | `AzeriteRespec` (bootstrap `:14`) | Azerite items |
| azeriteui | paper doll / bags / item links (`camelot/paperdollframe.lua:2092`, `mainline/containerframe.lua:1760`, `blizzard_itembutton/mainline/itembuttontemplate.lua:388`) | Azerite items |
| contribution | `ContributionCollector` (`blizzard_azeriterespecui_bootstrap.lua:14`) | Legion / BfA buildings |
| covenantpreviewui | `COVENANT_PREVIEW_OPEN` (`:201–203`) | covenants |
| covenantrenown | `PlayerInteractionType.Renown` (bootstrap `:20`) | covenants |
| covenantsanctum | `PlayerInteractionType.CovenantSanctum` (bootstrap `:19`) | covenants |
| covenanttoasts | `COVENANT_CHOSEN` / `COVENANT_SANCTUM_RENOWN_LEVEL_CHANGED` (`blizzard_covenantchoicetoast.lua:4`, `blizzard_covenantrenowntoast.lua:4`) | covenants |
| delvescompanionconfiguration | `TRAIT_SYSTEM_INTERACTION_STARTED` (`blizzard_framexmlutil/mainline/traitutil.lua:37–45`); `delvecompanionconfig` link (`blizzard_uipanels_game/mainline/itemrefhandlers.lua:76–79`) | `DelvesSeason` content |
| garrisonbase | follower tooltips (`blizzard_framexml/mainline/alertframesystems.lua:918`; `blizzard_uipanels_game/mainline/questinfo.xml:124`) | garrisons |
| islandsqueueui | `PlayerInteractionType.IslandQueue` (`blizzard_azeriterespecui_bootstrap.lua:14`) | BfA islands |
| mawbuffs | the scenario tracker's `MawBuffsBlock` (`blizzard_objectivetracker/blizzard_scenarioobjectivetracker.xml:357`) | the Maw / Torghast |
| orderhallui | `GARRISON_TALENT_NPC_OPENED` (`:669–671`) | Legion–Shadowlands class halls |
| petbattleui | `PET_BATTLE_OPENING_START` (`shared/blizzard_petbattleui.lua:79, 101`) | battle pets |
| runeforgeui | `RUNEFORGE_LEGENDARY_CRAFTING_OPENED` (`:209–211`) | Shadowlands legendaries |
| soulbinds | `PlayerInteractionType.Soulbind` (bootstrap `:19`) | soulbinds |
| tieredentrancetraits | the tracker's `TieredEntranceTraitsBlock` (`blizzard_scenarioobjectivetracker.xml:364–370`, `.lua:275`) | `DelvesSeason` content |
| torghastlevelpicker | custom gossip texture kits (`blizzard_uipanels_game/mainline/customgossipframebase.lua:15–32`) | Torghast |
| weeklyrewards | `PlayerInteractionType.WeeklyRewards` (bootstrap `:22`); the Great Vault pin (`blizzard_sharedmapdataproviders/areapoidataprovider.lua:76`) | Mythic+ keystones, `DelvesSeason` content, rated PvP |

The Great Vault is the weakest line: a server could place a vault object, and Forever has one keystone item. It has
its own checklist question.

#### The systems' own tables
The content check above rests on items, spells and quests. Each system's own client tables were then read from the
installed Forever client (1.60.1.69913, local archive, read-only), and the hotfix cache
(`Cache/ADB/enUS/DBCache.bin`, build 69913) was checked for rows in the same tables:

| system | tables (rows on Forever) |
|---|---|
| Great Vault | WeeklyRewardChestThreshold 0, WeeklyRewardChestActivityTier 0 |
| garrison / order hall / adventure map | GarrType 0, GarrFollower 0, GarrMission 0, GarrBuilding 0, GarrPlot 0, GarrClassSpec 0, GarrTalentTree 0, AdventureMapPOI 0 |
| covenants / soulbinds / anima | Covenant 2, Soulbind 0, AnimaCable 0. The 2 rows are placeholder rows for the PvP rank and Legacy systems: Forever reuses the covenant and renown plumbing for its own PvP rank and Legacy systems, which already have surfaces (`pvprank`, `legacy`). |
| renown | RenownRewards 22: the PvP rank's rewards ("Faction Tabard" … "Black War Mounts"), shown by the `pvprank` surface |
| azerite / artifact | AzeriteEssence 0, AzeritePower 0, AzeriteItem 0, AzeriteEmpoweredItem 0, Artifact 0, ArtifactPower 0 |
| pet battles | BattlePetSpecies 114 (companion pets, the `petjournal` surface), BattlePetBreedState 0; BattlePetAbility is not in the client |
| archaeology | ResearchBranch 0, ResearchProject 0, ResearchSite 0, ResearchField 0 |
| allied races | AlliedRace 0; AlliedRaceRacialAbility is not in the client |
| runeforge / contribution / `DelvesSeason` | RuneforgeLegendaryAbility 0, Contribution 0, DelvesSeason 0 |
| control | SpellName 17,887, ItemSparse 19,185 |

The hotfix cache carries no row for any of these tables. So every `no-content` window has an empty data source on
this build, and none can show anything. A later build that fills one of these tables flips its addon to `surface`
(the table check is the regression signal: re-run it per build).

#### Re-run on build 1.60.1.70009 (2026-09-25)
The check above was done by hand. It is now a committed tool: `make forever-table-counts WOW_DIR=\<client folder>
[HOTFIXES=\<Cache/ADB/enUS/DBCache.bin>]` (`python -m wfj.dev.table_counts`) prints each table's record count in the
local archive and its valid hotfix rows, flags a table with rows, and exits non-zero when a table cannot be read. It
reads `.build.info`, the archive and the hotfix cache only, read-only ([ADR-021](../adr/021-client-tables-from-the-local-archive.md)). The tables are looked up
by FileDataID, pinned in the tool: the Forever root carries no name hashes for them (ids from the community listfile).
It adds `TraitSubTree`, which holds a class's hero talents.

The installed client had moved to **1.60.1.70009** (the repo's tables and GlobalStrings are still pinned to 69913).
Output on that build:

| system | tables (rows on Forever, 70009) |
|---|---|
| Great Vault | WeeklyRewardChestThreshold 0, WeeklyRewardChestActivityTier 0 |
| garrison / order hall / adventure map | GarrType 0, GarrFollower 0, GarrMission 0, GarrBuilding 0, GarrPlot 0, GarrClassSpec 0, GarrTalentTree 0, AdventureMapPOI 0 |
| covenants / soulbinds / anima | Covenant 2 (PvP rank and Legacy, as on 69913), Soulbind 0, AnimaCable 0 |
| renown | RenownRewards 22 (the PvP rank's rewards, as on 69913) |
| azerite / artifact | AzeriteEssence 0, AzeritePower 0, AzeriteItem 0, AzeriteEmpoweredItem 0, Artifact 0, ArtifactPower 0 |
| pet battles | BattlePetSpecies 115 (companion pets; 114 on 69913), BattlePetBreedState 0 |
| archaeology | ResearchBranch 0, ResearchProject 0, ResearchSite 0, ResearchField 0 |
| allied races | AlliedRace 0 |
| runeforge / contribution / `DelvesSeason` | RuneforgeLegendaryAbility 0, Contribution 0, DelvesSeason 0 |
| hero talents | TraitSubTree 0 |

The hotfix cache adds no row to any of them. Every `no-content` disposition still holds on 70009. `TraitSubTree` has 0
rows, so no Forever class has hero talents: the hero-talent keys are excluded with that count.

**Re-run with the repo pinned to 70009 (2026-09-25).** With the repo's tables and GlobalStrings moved to
1.60.1.70009, a re-run of `make forever-table-counts WOW_DIR=\<client folder> HOTFIXES=<client
folder>/Cache/ADB/enUS/DBCache.bin` with the build's own hotfix cache (build 70009) gave output identical to
the table above, and every table has 0 valid hotfix rows: nothing differs, and every `no-content` disposition holds.

### 6. `unreachable`: no entry point in the camelot load set (9)

| addon | evidence |
|---|---|
| adventuremap | its opener `ShowAdventureMapFrameForFollowerType` (`ADVENTURE_MAP_OPEN`, `blizzard_game/mainline/eventimplementation.lua:548–550`) is defined only in `blizzard_garrisonui/mainline/blizzard_garrisonui_bootstrap.lua`, which is gated |
| ardenwealdgardening | loader called only from `blizzard_garrisonui/mainline/blizzard_garrisonlandingpage.lua:197` (gated) |
| covenantcallings | loader called only from `blizzard_garrisonlandingpage.lua:169` (gated) |
| landingsoulbinds | loader called only from `blizzard_garrisonlandingpage.lua:183` (gated) |
| garrisontemplates | no reference in the load set; its only dependent is `blizzard_garrisonui` (gated) |
| plunderstormbasics | no reference in the load set (LOD, nothing loads it) |
| autocompletepopuplist | no reference in the load set (LOD, no bootstrap) |
| commentator | loads only when `C_Commentator.IsSpectating()` (`blizzard_game/shared/eventimplementation.lua:314–316`); the `/commentator…` words need it loaded (`slashcommands.lua:1446–1514`) |
| declensionframe | every file is `[AllowLoadTextLocale ruRU]` (`blizzard_declensionframe.toc:4–9`): the enUS load set is empty |

### 7. `not-a-window` (32)

- **Secure environment** (`## UseSecureEnvironment: 1`): `storeui` (toc:10), `catalogshop` (toc:8),
  `catalogshoprefundflow` (toc:9), `catalogshoptopupflow` (toc:8), `simplecheckout` (toc:4), `securetransferui`
  (toc:4), `wowtokenui` (toc:3), `authchallengeui` (toc:3, `fullLockdown`, `.xml:5`). Their frames live in Blizzard's
  separate secure Lua state, which addon code cannot read, hook or write. The shop is reachable
  (`StoreMicroButton` → `ToggleStoreUI`, `blizzard_micromenu/mainline/mainmenubarmicrobuttons.lua:1837–1868`; camelot
  places the button behind `Enum.GameRule.StoreDisabled`), and it stays English: addon code cannot run there, so
  there is no route ([ADR-037](../adr/037-staticpopup-dialogs-and-owned-keys.md)). The ping wheel is in a
  `<ScopedModifier forbidden="true">` (`blizzard_pingui.xml:3–5`).
- **Chat, combat-log, error and system lines:** `chatbubble`, `chatframeutil`, `combatlogbase`, `combatlogprocessor`,
  `codeofconduct`, `moneyreceipt`, `raidwarning`, `uierrorsframe`, `questnavigation`, `subtitles`, `game` (the event
  hub itself), `apidocumentation` (`/api` output).
- **StaticPopups (ADR-015):** `staticpopup`, `staticpopup_game`, `addfriend`, `addonperformance`, `hardcoreui`,
  `lfgutil` (all its frames are `StaticPopupSpecial` dialogs), `kiosk` (demo stations only). *These later became
  `surface popups`, no longer `not-a-window` ([ADR-037](../adr/037-staticpopup-dialogs-and-owned-keys.md)).*
- **Spoken, not drawn:** `combataudioalerts` (`C_CombatAudioAlert.SpeakText`), `narration` (`C_VoiceChat.SpeakText`).
- **Gamepad-mode HUD:** `gamepad`, `gamepadtargeting`. Prompt text is measured from its English inside the writer
  (`blizzard_gamepadsharedutility/inputprompts/inputprompts.lua:34–42`). *Both later became `surface gamepad`
  (`UI/Gamepad`), with `gamepadsharedutility`: the prompt is re-sized and its legend re-laid out after a label
  changes ([ADR-040](../adr/040-gamepad-hud.md)).*

### 8. Owned by other work (19)

At the time of the sweep these 19 addons were left to three other pieces of work. Where each stands now (the data
file is authoritative):

| work | addons | outcome |
|---|---|---|
| tutorials, new player experience | `boosttutorial`, `helpplate`, `newplayerexperience`, `newplayerexperienceguide`, `tutorialmanager`, `tutorials`, `tutorialtemplates` | `newplayerexperience`, `boosttutorial` and `newplayerexperienceguide` are `unreachable` (loaded only for Exile's Reach, the boost scenario and the retail guide NPC's `npe-guide` gossip); `tutorialtemplates` is `no-text`; `tutorialmanager` (the pointer arrows, `UI/HelpTips`), `tutorials` and `helpplate` are `surface help`. The tutorial popup itself is in `blizzard_framexml` (surface `tutorial`, `UI/Tutorial`) |
| client-table and server text | `generictraitui` (tree titles are `C_Traits` data), `statistics` (every row is an achievement-table name), `uiwidgets` (server-supplied widget text) | `generictraitui` is `unreachable`; `statistics` and `uiwidgets` are surfaces ([ADR-042](../adr/042-client-table-text-families.md)) |
| menus and social | `autocomplete` (composites around names), `communitiessecure` (the rest of Communities), `socialui`, `socialuishared`, `menu`, `unitpopup`, `unitpopupshared`, `socialtoast`, `movepad` | `unitpopup` and `unitpopupshared` are `surface help` (the unit menus, `UI/Menus`); `menu` is `library`; the rest are `planned` |

### 9. `library` (21) and `no-text` (73)

- **library:** framexmlbase, sharedxmlbase, sharedxmlgame, uipaneltemplates, statusui, mapcanvas,
  mapcanvassecureutil, contenttracking, itembutton, moneyframe, transmogshared, catalogshopsharedtemplates,
  catalogshopsharedutil, charactercustomize and customizationui (text only inside the barber shop; customizationui later
  became `surface barbershop`, for its camera tooltips), classmenu, flyout,
  textstatusbar, gamepadsharedutility (later `surface gamepad`: its prompt / legend templates and the
  "More Actions" menus), matchmakingqueuedisplay, scripterrors.
- **no-text:** the deprecated-API shims, UIParent and panel managers, fonts, colours, constants, the dispatcher,
  print handler, object API, developer tools whose words are Lua literals (console, debugtools, framestack), the IME
  window (operating-system text), nameplates, buff frames, aura containers, the personal resource display, the
  hybrid minimap, POI buttons, the FPS counter (later `surface hudlabels`, for its "CPU Bound" line), and three
  addons whose camelot load set is empty
  (`clientsavedvariables`, `fullscreenbrowser`, `selectorui`).

Some addons were first recorded as `library` and became `surface` because a surface scans their files (the test
requires it): `framexmlutil` (timemanager), `partyposeui` (partypose), `visualalerts` (cooldownviewer),
`accessibilitytemplates` and `settings` (settingspanel), `sharedxml` (gamemenu).

### 10. File-level triage inside `Blizzard_UIPanels_Game`

Its camelot load set is 109 files. The camelot re-target's surfaces listed 40, and this sweep's new surfaces list 28 more. The other
41 have no surface:

- **libraries / managers:** the player-interaction manager, the character tab API, gossip API, bank registration,
  POI quantizer, unit position templates (`PLAYER_IS_PVP_AFK` is a name composite), custom gossip base (only consumer
  the retail `delvesdifficultypicker`), role selection and `SocialQueueUtil` (consumer: quickjoin).
- **no-text:** extra ability container, azerite paper-doll overlay, friendship status bar (its tooltip is the
  reputation surface's), fog of war, world map action button, PvP banner (server data), vehicle seat indicator
  (`EJECT_PASSENGER` is a menu entry), localization layout.
- **no content on Forever:** the bounty board (Legion / BfA emissaries), calling POI tooltips, campaign headers
  (`C_CampaignInfo`).
- **unreachable:** the quest map's Events tab. Camelot sets `eventsTabHidden`
  (`camelot/questmapframeoverrides.lua:5`, read at `mainline/questmapframe.lua:231–238`).
- **already covered:** the book window (itemtext) and `ItemRefTooltip` (tooltip).

### 11. `SetTitle` titles

`make forever-titles` lists every `SetTitle(` call site in the surface addons' load sets. There are 83.
`pipeline/forever_titles.txt` gives each one a disposition:

- `key <KEY> <surface>` (41): a dictionary word, rendered by `Labels.title` on that surface.
- `dynamic` (25): built text or a choice of keys, handled by the surface's `only` list or left as built.
- `name` (16): the title is a name (a player, a guild, an object), English by [principle 2](../architecture/principles.md).
- `ruled` (1): `BANK`, kept English by a standing decision.

Friends and Merchant moved onto `Labels.title`. Bags did not, because its titles need a per-bag `only` set.

### 12. What source cannot settle

These are in-game questions, listed in the
Forever window checklist in the [testing strategy](../testing/strategy.md):

- Which retail-era NPC windows Forever places (black market, transmog, item upgrade, guild vault, crafting orders,
  Chromie).
- Whether each `unreachable` and `no-content` window really stays closed.
- Whether the Options window's rows keep their width in Japanese.
- Which flight map a flight master opens (TaxiFrame or FlightMapFrame; both are covered).
- Whether hero talents, Party Sync, event toasts, the honor-level bar or `AchievementsPanelDisabled` apply on Forever.
  *(The client files later settled two: Party Sync is off, since `IsPartySyncEnabled()` returns false, and there
  are no hero talents, since `TraitSubTree` has 0 rows on 70009, §5.)*

## Recommendation

Adopt B as the standing method ([ADR-030](../adr/030-every-window-the-forever-client-loads.md)). The resolver's
output, the dispositions and the titles are committed data, and `test_forever_windows.py` ties them to
`FOREVER_WINDOWS`. On a new client build, `make forever-addons` is re-run: a new addon fails the test until it has a
disposition. Flipping an `unreachable` or `no-content` line that the in-game pass finds open is a data edit plus one
surface module.

## Related

- [ADR-030: every window the Forever client loads](../adr/030-every-window-the-forever-client-loads.md) ·
  [ADR-029: camelot targets the mainline family](../adr/029-camelot-targets-the-mainline-family.md) ·
  [ADR-015: UI text surfaces](../adr/015-ui-text-surfaces.md) ·
  [ADR-037: StaticPopup dialogs and owned keys](../adr/037-staticpopup-dialogs-and-owned-keys.md)
- [Research: camelot surface re-target](2026-09-19-camelot-surface-retarget.md) ·
  [Forever client differences](2026-09-17-forever-client-differences.md)
- [Addon modules](../architecture/addon-modules.md) · [Pipeline](../systems/pipeline.md) ·
  [Testing strategy](../testing/strategy.md)
