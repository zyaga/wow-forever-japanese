from pathlib import Path

from wfj.cmd import toc_check

TOC = "addon/WoWForeverJapanese/WoWForeverJapanese.toc"
CLIENTS = "pipeline/clients.toml"


def test_real_toc_fields_and_load_order(root):
    meta, files = toc_check.parse_toc(root / TOC)
    assert meta["Version"] == "@project-version@"
    assert meta["SavedVariables"] == "WFJ_DB, WFJ_Collector, WFJ_Log"
    assert meta["Interface"].isdigit()
    # An icon for the AddOn List (a client icon Blizzard's own Vanilla/QuestInfo.xml references) and Notes
    # that say where the settings are.
    assert meta["IconTexture"] == "Interface\\AddOns\\WoWForeverJapanese\\Media\\icon"
    assert "Esc > Options > AddOns" in meta["Notes"]
    assert "Hold Alt to see" not in meta["Notes"]
    # Dependency order as shipped: Core, then Data, the generated block, the Lookup slot, then the UI modules.
    head = ["Core/ErrorLog.lua", "Core/Const.lua", "Core/Compat.lua", "Core/Normalize.lua", "Core/Hash.lua", "Core/Data.lua"]
    tail = [
        "Core/Lookup.lua", "Core/Readings.lua", "Core/Glosses.lua",
        "Core/Align.lua", "Core/State.lua", "Core/Settings.lua", "Core/Modifier.lua",
        "Core/Placeholders.lua", "Core/Translator.lua", "Core/UIStringKeys.lua", "Core/UIStrings.lua",
        "Core/Objectives.lua",  # objective lines
        "Core/SurfaceState.lua",
        "Core/Collector.lua", "Core/CollectorSend.lua",  # the collector and its send
        "Core/RecentLines.lua", "Core/Reports.lua", "Core/ReportText.lua",  # fix reports
        "Core/Diag.lua", "Core/BugReport.lua",  # the problem log, the bug report link
        "UI/Font.lua", "UI/ReadingPopup.lua", "UI/Readings.lua", "UI/Render.lua", "UI/ButtonText.lua", "UI/Labels.lua",
        "UI/HtmlText.lua", "UI/LoadOnDemand.lua",
        "UI/HelpTooltip.lua", "UI/TooltipData.lua",
        # ADR-030: shared helpers
        "UI/SettingsKeys.lua", "UI/LabelTree.lua", "UI/TooltipLines.lua",
        "UI/Character.lua", "UI/Reputation.lua", "UI/Skills.lua",
        "UI/PvPRank.lua",  # camelot's PvP rank panel
        "UI/SpellBook.lua", "UI/Talents.lua", "UI/Trainer.lua", "UI/GossipChrome.lua", "UI/Merchant.lua", "UI/Bank.lua",
        "UI/Bags.lua", "UI/Mail.lua", "UI/Friends.lua",
        "UI/FriendsTooltip.lua",  # the friends list's own tooltip
        "UI/Communities.lua",
        # the rest of the Communities window
        "UI/CommunitiesKit.lua", "UI/CommunitiesFrame.lua", "UI/CommunitiesGuild.lua", "UI/ClubFinder.lua",
        "UI/ClubFinderApplicants.lua", "UI/CommunitiesDialogs.lua", "UI/Raid.lua",
        "UI/MicroMenu.lua",
        "UI/MenusUnit.lua", "UI/Gamepad.lua", "UI/Menus.lua", "UI/MenusTags.lua", "UI/MenusUntagged.lua",  # menu entries; Gamepad loads before MenusUntagged
        "UI/HelpTips.lua",  # HelpTip callouts
        "UI/QuestFrame.lua", "UI/QuestMap.lua",
        "UI/TimeLine.lua",  # the cooldown countdown, before the tooltips that write it
        "UI/Tooltip.lua",
        "UI/TooltipUnit.lua",  # the unit mouseover lines
        "UI/GameMenu.lua", "UI/Gossip.lua",
        "UI/ItemText.lua",  # the book window
        # ADR-030: every other Forever window
        "UI/Professions.lua", "UI/Crafting.lua", "UI/CustomerOrders.lua", "UI/QuestTimer.lua", "UI/Trade.lua",
        "UI/Loot.lua", "UI/GroupLoot.lua", "UI/Taxi.lua", "UI/Tabard.lua", "UI/Petition.lua",
        "UI/GuildRegistrar.lua", "UI/DressUp.lua", "UI/CastingBar.lua", "UI/MapLegend.lua", "UI/WorldMap.lua",
        "UI/MapPins.lua", "UI/FlightMap.lua", "UI/BattlefieldMap.lua", "UI/Tracker.lua", "UI/AuctionHouse.lua",
        "UI/BarberShop.lua", "UI/BlackMarket.lua", "UI/Currency.lua", "UI/CurrencyTransfer.lua",
        "UI/GuildBank.lua", "UI/GuildControl.lua", "UI/GuildRename.lua", "UI/ItemInteraction.lua",
        "UI/ItemSocketing.lua", "UI/ItemUpgrade.lua", "UI/ObliterumForge.lua", "UI/ScrappingMachine.lua",
        "UI/Stable.lua", "UI/SubscriptionInterstitial.lua", "UI/Transmog.lua", "UI/Achievement.lua",
        "UI/Calendar.lua", "UI/ClickBinding.lua", "UI/Collections.lua", "UI/MountJournal.lua", "UI/PetJournal.lua",
        "UI/Wardrobe.lua", "UI/Inspect.lua", "UI/Legacy.lua", "UI/Statistics.lua", "UI/Widgets.lua", "UI/Macro.lua", "UI/SpellSearch.lua",
        "UI/TimeManager.lua", "UI/CombatText.lua", "UI/CooldownViewer.lua", "UI/DamageMeter.lua",
        "UI/DeathRecap.lua", "UI/GamepadEdit.lua", "UI/HudLabels.lua", "UI/HudTips.lua", "UI/Minimap.lua",
        "UI/PvPMatch.lua", "UI/QueueStatus.lua", "UI/RaidManager.lua", "UI/UnitFrames.lua", "UI/GroupFinder.lua",
        "UI/Channels.lua", "UI/QuickJoin.lua", "UI/RecentAllies.lua", "UI/RecruitAFriend.lua",
        "UI/ReportFrame.lua", "UI/HelpFrame.lua", "UI/StatusNotices.lua", "UI/BNetToast.lua",
        "UI/SettingsPanel.lua", "UI/SettingsTutorials.lua", "UI/EditMode.lua", "UI/QuickKeybind.lua",
        "UI/ColorPicker.lua", "UI/ChatConfig.lua", "UI/TextToSpeech.lua", "UI/ChatTabs.lua", "UI/CombatLog.lua",
        "UI/AddonList.lua", "UI/ScriptErrors.lua", "UI/Splash.lua", "UI/EventTrace.lua", "UI/ChromieTime.lua",
        "UI/Alerts.lua", "UI/Errors.lua", "UI/ChatSystem.lua", "UI/ChatInput.lua", "UI/Speech.lua", "UI/BossBanner.lua", "UI/Cinematic.lua",
        "UI/Subtitles.lua", "UI/CoinPickup.lua", "UI/CombatFeedback.lua",
        "UI/EquipmentFlyout.lua", "UI/GhostFrame.lua", "UI/GuildInvite.lua", "UI/InstanceAbandon.lua",
        "UI/InstanceDifficulty.lua", "UI/LootHistory.lua", "UI/LossOfControl.lua", "UI/MajorFactionToast.lua",
        "UI/PartyPose.lua", "UI/PetHappiness.lua", "UI/PlayerChoice.lua", "UI/ReadyCheck.lua", "UI/StackSplit.lua",
        "UI/StreamingIcon.lua", "UI/ZoneText.lua",
        "UI/Tutorial.lua",  # the tutorial popup
        "UI/Popups.lua",
        "UI/Scan.lua",
        # the settings pages' copy, widgets, key capture, the modifier's override binding, the AddOn List button
        "UI/OptionsText.lua", "UI/OptionsWidgets.lua", "UI/KeyCapture.lua",
            "UI/FixWindow.lua", "UI/CollectorSendWindow.lua", "UI/ReportWindow.lua",  # the tool windows
            "UI/MinimapButton.lua",  # the minimap button
            "UI/RevealBinding.lua",
        "UI/AddonListButton.lua", "UI/Options.lua", "UI/Slash.lua", "Main.lua",
    ]
    assert files[: len(head)] == head and files[-len(tail) :] == tail
    generated = files[len(head) : -len(tail)]
    assert generated[:2] == ["Data/Meta.lua", "Data/Vectors.lua"]
    assert all(f.startswith("Data/") and (root / "addon/WoWForeverJapanese" / f).is_file() for f in generated)
    assert generated == sorted(
        generated,
        key=lambda f: (
            ["Meta", "Vectors", "Quest", "Item", "Spell", "Objective", "Area", "Gossip", "Book", "UI", "Reading", "Gloss"].index(
                f.split("/")[1].split("_")[0].replace(".lua", "")
            ),
            f,
        ),
    )


def test_real_toc_passes(root):
    assert toc_check.check(root / TOC, root / CLIENTS) == []
    assert toc_check.run([str(root / TOC), str(root / CLIENTS)]) == 0


def test_interface_mismatch_fails(root, tmp_path: Path):
    bad = tmp_path / "clients.toml"
    bad.write_text('[forever]\ninterface = 99999\ntested = "x"\n', encoding="utf-8")
    problems = toc_check.check(root / TOC, bad)
    assert any("Interface" in p for p in problems)
    assert toc_check.run([str(root / TOC), str(bad)]) == 1


def test_missing_required_field_fails(root, tmp_path: Path):
    toc = tmp_path / "x.toc"
    toc.write_text("## Interface: 11509\n## Title: x\nMain.lua\n", encoding="utf-8")
    problems = toc_check.check(toc, root / CLIENTS)
    assert "missing ## Version" in problems and "missing ## SavedVariables" in problems


def test_usage_error():
    assert toc_check.run(["only-one-arg"]) == 1
