# What the Forever client changed under the addon's surfaces

> 2026-09-17, the first day of the beta. Client: **World of Warcraft: Forever (Beta), 1.60.1.69893** (`wow_classic_beta`), the first client the addon was run against. At the time the addon targeted Classic Era 1.15.x. This doc records what was measured, how, and what stayed unknown.
>
> Several first readings of this survey did not hold when re-checked the same day and two days later. The text below states the corrected findings; the [Corrections](#corrections) section keeps what was wrong and why, because the mistakes are instructive. The deeper evidence for the game-type findings is [the camelot re-target research](2026-09-19-camelot-surface-retarget.md).

## Summary

Forever is **not one new UI**. Its interface ships several flavours side by side and picks per system:

```
interface/addons/blizzard_uipanels_game/vanilla/questframe.lua
interface/addons/blizzard_uipanels_game/cata/questlogframe.lua
interface/addons/blizzard_uipanels_game/mainline/itemtextframe.lua
interface/addons/blizzard_gametooltip/mainline/…
interface/addons/blizzard_uipanels_game/shared/gossipframeshared.lua
```

So the question is never "does the addon work on Forever" but "which flavour did this surface get". Underneath the flavours is a harder gate: [the game type](#the-headline-finding-forevers-game-type-is-camelot).

- The quest window **renders Japanese correctly in game**. It runs the mainline `questframe.lua` / `questinfo.lua`, not the vanilla code: `Blizzard_UIPanels_Game.toc:88–100` loads `[Family]\QuestFrame.lua` (no conditional), `[Family]\QuestFrame.xml [AllowLoadGameType mainline]` and `[Family]\QuestInfo.lua [AllowLoadGameType mainline]`, while `Vanilla\QuestFrame.lua` is `[AllowLoadGameType vanilla]` only. The addon's hooks land because the mainline `QuestInfo_Display` kept its name and signature (`mainline/questinfo.lua:28`).
- The tooltip runs the mainline code, and its `OnTooltipSetItem` hook is gone. The addon carries a second hook path for it ([ADR-025](../adr/025-guarded-surface-init-and-runtime-tooltip-path.md)).

## The headline finding: Forever's game type is `camelot`

Forever's Blizzard addons gate each file on a **game type**, and Forever's is `camelot`. From the client's own `Interface/AddOns/Blizzard_UIPanels_Game/Blizzard_UIPanels_Game.toc`:

```
[Game]\QuestLogFrame.lua   [AllowLoadGameType vanilla, tbc, wrath]
Cata\QuestLogFrame.lua     [AllowLoadGameType cata, mists]
[Game]\SkillsFrame.lua     [AllowLoadGameType camelot]
[Family]\QuestFrame.lua    (no conditional, loads on every game type)
```

`camelot` is a **member of the `mainline` family**. A line gated `[AllowLoadGameType mainline]` loads on Forever unless it also carries `[ExcludeLoadGameType camelot]`. The same TOC's lines 44–45, `[Family]\CharacterFrame.lua [AllowLoadGameType mainline] [ExcludeLoadGameType camelot]` beside `[Game]\CharacterFrame.lua [AllowLoadGameType camelot]`, only mean something if so. `[Family]` expands to `Mainline\` and `[Game]` to `Camelot\`. What does not load is anything gated only `classic`, `vanilla`, `tbc` and so on. Forever runs the retail UI with camelot overrides. The rule and its evidence: [the camelot re-target research](2026-09-19-camelot-surface-retarget.md), finding 1.

So a whole surface can be absent while the client still ships its source. That is exactly what the probe measured, and no per-name reasoning could explain it. It accounts for the sharpest split in the verdict table: the quest **window** works (`questframe`, 47 names present, `[Family]\QuestFrame.lua`, no conditional) while the quest **log** is 23 absent names (`[Game]\QuestLogFrame.lua`, `vanilla, tbc, wrath` only).

**The surfaces were not renamed. Their frames do not exist.** Forever ships a `camelot` replacement for each, present in the extracted source:

| our surface | what Forever loads instead |
|---|---|
| questlog | `QuestMapFrame` + `Blizzard_ObjectiveTracker` (`camelot/questmapframeoverrides.lua`, `camelot/questmapframeutils.lua`) |
| skills | `blizzard_uipanels_game/camelot/skillsframe.lua` |
| spellbook | `Blizzard_PlayerSpells` (`camelot/blizzard_playerspellsframe.lua`), observed loading in the live session |
| guild | `blizzard_communities/camelot/` |
| talents | `camelot/blizzard_classtalentsframe.lua` |

`character`, `paperdoll` and `reputation` carry `[AllowLoadGameType camelot]` overrides too, but they scored `works`. A camelot override is not by itself a break; it is a break where the file the addon depends on is gated *away*. How much of each replacement the addon could reuse is the question of [the camelot re-target research](2026-09-19-camelot-surface-retarget.md).

## Method

Three evidence paths, because any one alone misleads:

1. **The client's own UI source.** `wfj.dev.client_ui` resolves interface paths through the install's archive (`io/casc.py`, read-only, ADR-021) and extracts them: **4,042 files** from a 7,706-path candidate list. (A first run read only 995 files because of a reader bug; see [C5](#c5-the-client-archive-was-never-sparse).)
2. **A dependency manifest from the addon itself.** `wfj.dev.client_surface build` parses `addon/**/*.lua` for every `Compat.declare` candidate, `Compat.resolve`, `hooksecurefunc` target, `HookScript` type **and direct client API call**. No `Compat.declare` covers the last, so they would otherwise go unchecked. The result: **316 names across 36 surfaces** (225 globals, 40 direct API calls, 22 script types, 20 hooked writers, 9 mixin-method hooks), plus 31 dynamic names built at runtime that no static scan can resolve and 7 `api` matches flagged `suspect`: 354 entries in all. Comments are blanked before matching and generated data shards are skipped, so prose is not read as code.
3. **A live probe.** `WFJProbe` is generated by `client_surface probe --addon-out` and stamped with the manifest it was built from, so answers from another manifest are dropped rather than merged. Installed into the beta client, it asks the running client about each manifest name and saves the answers to SavedVariables. Run on build 1.60.1.69893, interface **16001**: 320 names answered. Its first run reported every namespaced API missing (a bug in the probe's dotted-name split), which was fixed and re-run before the numbers below. The probe sweeps on `PLAYER_LOGIN`, on every `ADDON_LOADED` and on `/wfjprobe <surface>`, and records per surface how many sweeps ran with its window open ([C4](#c4-the-first-probe-ran-once-at-login)).

## Findings

### 1. The tooltip surface is gone, and its replacement is named

`UI/Tooltip.lua` called `frame:HookScript("OnTooltipSetItem", …)`. On Forever that raises `bad argument #2`.

- In game: `type(TooltipDataProcessor) == "table"`, `GameTooltip:HasScript("OnTooltipSetItem") == false`, `type(C_TooltipInfo) == "table"`.
- In the client's source (`blizzard_sharedxmlgame/tooltip/tooltipdatahandler.lua`): `TooltipDataProcessor.AddTooltipPostCall(tooltipType, func)`, with `AddTooltipPreCall`, `AddLinePreCall` and `AddLinePostCall` beside it. Tooltip types come from `Enum.TooltipDataType`.

### 2. One unguarded error disabled almost the whole addon (our bug, not Forever's)

`Main.lua` ran every surface's `init` in one sequence. `Tooltip.init` was the sixth of some twenty, so when it threw, **everything after it never ran**: game menu, gossip, item text (books), trainer, every window surface, the collector scan and `Slash.register`. That is why `/wfj` did not answer on Forever. Surfaces must fail independently ([ADR-025](../adr/025-guarded-surface-init-and-runtime-tooltip-path.md)).

### 3. Quest text works, and the stale marker does its job

The quest window shows Japanese title, description, objectives, rewards and the 承諾 / 辞退 buttons. `hooksecurefunc("QuestInfo_Display", …)` still lands on the mainline `QuestInfo_Display`.

The window also shows `[要更新 / English Changed]`. Forever's English for that quest differs from the Vanilla (VMaNGOS) text the translation was checked against, so the addon withholds the Japanese as designed (ADR-019). This was the first confirmation that the Forever English had to be harvested again from the new client.

### 4. Gossip is modern, and the addon already matched it

Forever's gossip is mixin- and scrollbox-based (`GossipOptionButtonMixin:Setup`, `GossipGreetingTextMixin:Setup`, `GossipFrameSharedMixin:UpdateScrollBox`). The addon hooks `GossipFrame:Update`, the greeting's `SetText` and the option's `Setup`, and declares `ScrollUtil` and `C_GossipInfo`: the same shape. All 4 gossip names and all 5 gossip-chrome names are present in the source.

### 5. The verdict: 24 surfaces intact, 12 with something missing

The evidence files are committed beside this doc in `2026-09-17-forever-client-surface/`: the manifest, the client's raw answers, the verdicts and the summary, for both runs.

**Run 1, login only** (`summary.md`, `verdicts.json`, `probe-answers.lua`), over the 347 counted entries (the 7 `suspect` matches held back): **works 169 · needs rework 83 · resolves under another name 28 · unknown 67.** Re-running `report` on those files alone reproduces every number except the `rework` / `names only` split, which needs `--source <the extracted client UI>`. That directory is not committed; without it the two collapse into `rework 111`.

**Run 2, with the windows open** (`summary-run2.md`, `verdicts-run2.json`, `probe-answers-run2.lua`, `surface-manifest-run2.json`): each window was opened, `/wfjprobe <surface>` run at it, and the UI reloaded. Over 350 counted entries: **works 172 · rework 37 · unknown 141.** This is the measurement that stands. `verdicts-run2.json` reproduces byte-identically from the manifest plus the probe answers; the headline `rework 37` is that same output read with guild's and talents' marks withdrawn, and `summary-run2.md` shows the arithmetic. The probe file is committed exactly as the client wrote it. `uipanels-game-toc-gating.md` holds the client TOC excerpt the `camelot` finding rests on.

- **Guild and talents were withdrawn, not cleared.** Both windows are level-10 gated on the character used, so neither could have been open. Their marks were never evidence either way.
- **Trainer, talents and raid stayed `unknown`**: their load-on-demand Blizzard addons never loaded.
- **Confirmed broken, with the window open:** questlog 23, spellbook 7, skills 1. [The game type](#the-headline-finding-forevers-game-type-is-camelot) says why and names each replacement.
- **Also confirmed broken:** mail 3 (`InboxTitleText`, `OpenMailTitleText`, `SendMailTitleText`), honor 2 (`HonorFrame_Update`, `HonorFrame_SetLevel`), friends 1 (`WhoList_Update`). The game type explains all three. Their classic files are gated `classic` (`MailFrame` and `FriendsFrame`, `Blizzard_UIPanels_Game.toc:151–152, 207–208`) or `vanilla, tbc, wrath` / `classic` (`HonorFrame`, :75–80), so none load. Each has a replacement:
  - mail is its own addon, `Blizzard_MailFrame` (`## AllowLoadGameType: mainline`), which titles with `SetTitle`;
  - honor is replaced by `PVPRankFrame` (`[Game]\PVPRankFrame.lua [AllowLoadGameType camelot]`, :213), a different feature;
  - the who list moved to the load-on-demand `Blizzard_GroupFinder_VanillaStyle` (`LFGWhoListFrame`).

  Evidence: [the camelot re-target research](2026-09-19-camelot-surface-retarget.md), findings 6–8.

The run 1 table, kept as the record of the first measurement.

**Intact, no name missing** (for trainer, talents and raid this means "nothing was proven missing", since their load-on-demand addon never loaded; `compat` and `labels` have no measured name at all, only dynamic ones): addonlistbutton, bags, buttontext, character, compat, const, gamemenu, gossip, gossipchrome, helptooltip, itemtext, keycapture, labels, main, micromenu, modifier, options, raid, revealbinding, scan, settings, slash, talents, trainer.

| surface | works | needs rework | renamed | unknown |
|---|---|---|---|---|
| guild | 0 | 59 | 3 | 1 |
| questlog | 3 | 14 | 9 | 0 |
| mail | 19 | 3 | 0 | 3 |
| honor | 0 | 2 | 0 | 2 |
| tooltip | 1 | 2 | 1 | 3 |
| friends | 3 | 1 | 0 | 0 |
| skills | 0 | 1 | 0 | 2 |
| spellbook | 1 | 1 | 6 | 4 |
| bank | 1 | 0 | 4 | 0 |
| merchant | 13 | 0 | 2 | 0 |
| questframe | 47 | 0 | 1 | 0 |
| reputation | 2 | 0 | 2 | 2 |

`unknown` is an honest answer, not a gap in the client. 27 of them are the load-on-demand surfaces (trainer 12, talents 11, raid 4) whose Blizzard addon never loaded in the probed session: their frames cannot exist until the window is opened, so absence proves nothing. The rest are `method` hooks (`hooksecurefunc(frame, "Update")`), which are judged by whether their frame resolves, and names the addon builds at runtime.

Guild's 59 in run 1 is an upper bound, not a count. The probe's own `loaded` table shows `Blizzard_GuildUI` never loaded, so nobody opened the guild window. On Classic Era `GuildFrame` lives in always-loaded FrameXML, so the addon gave guild no `lod` tag and its absences were scored as proven, while trainer's identical absences were scored `unknown`. The difference is a property of our tagging, not of the client.

Every piece of text is in scope on Forever, so whatever is broken is rebuilt, scheduled by size rather than dropped for it.

### 6. Per-surface source comparison

53 of 189 declared names found, 136 absent, 29 dynamic. This comparison ran against the first, partial extraction and **was not re-run against the full one**: read it as a shortlist, not a verdict. The real reason a name can be absent from a client that ships its file is [the game type](#the-headline-finding-forevers-game-type-is-camelot).

| Every name found | Some found | None found |
|---|---|---|
| gamemenu (2), gossip (4), gossipchrome (5), helptooltip (2), keycapture (1), main (1), merchant (3), options (1), questframe (4), reputation (4), scan (1), settings (1) | spellbook (7/8), guild (3/62), itemtext (2/7), mail (1/22), questlog (2/3), raid (2/12), talents (2/14), tooltip (2/4), trainer (2/14), buttontext (1/4) | addonlistbutton, bags, character, friends, honor, micromenu, skills |

Only the tooltip row is corroborated by the live client; every other absence is provisional.

### 7. Forever's Vanilla-flavour files are almost exactly Classic Era's

Extracting the same interface set from the **Classic Era** install (2,674 files) and comparing the 950 files both clients carry:

- **853 are byte-identical** (90%).
- **97 differ**, and **not one of them removes a writer the addon post-hooks**. The two that touch our surfaces are cosmetic for us: `shared/gossipframeshared.lua` keeps every mixin method (`GossipOptionButtonMixin:Setup`, `GossipGreetingTextMixin:Setup`, `GossipFrameSharedMixin:UpdateScrollBox`) with only line offsets moved, and `vanilla/merchantframe.lua` still defines `MerchantFrame_UpdateMerchantInfo` and `MerchantFrame_UpdateBuybackInfo`.
- Of the 20 global writers the addon hooks by name, the ones checked are **still globals** (`QuestInfo_Display`, `MerchantFrame_*`, `ReputationFrame_Update`). Two surfaces moved to mixins and lost their global (`AddonListMixin`, `ContainerFrameMixin`), so those need method hooks.

This comparison says the shared files barely moved. It does not say which files load: the game type decides that, and on Forever it selects the mainline family, so the quest window, for one, runs mainline code whose writers kept their names.

### 8. The APIs the addon calls directly, and the two that are gone

40 client APIs are called outside `Compat`. The probe answered every one on the live client: **38 resolve, 2 are absent**, both in the quest log surface and both unguarded globals:

- `GetQuestLogTitle`
- `GetQuestLogSelection`

Modern clients moved this family to `C_QuestLog`. Because both calls were bare, `QuestLog.onUpdate` threw on Forever rather than degrading to English. `GetQuestLogQuestText` is present and `GetQuestLogSelectedID` absent. The `C_QuestLog` equivalents take a **quest id** where these take a **log index**, so they are not drop-ins.

The other 38 are unguarded but present. Declared through `Compat`, a later removal would degrade instead of throwing.

### 9. Name lookup needs a listfile

The root carries no file names. `Interface/FrameXML/QuestFrame.lua` resolves to nothing through `casc.file_data_id`, because this build's root has no usable name hashes. Names were resolved through the community listfile (`wowdev/wow-listfile`, 153 MB, `id;path`) instead, which worked: `vanilla/questframe.lua` → 5612659, and so on. (An earlier claim that most content was not on disk was a reader bug; see [C5](#c5-the-client-archive-was-never-sparse) and [ADR-026](../adr/026-blank-archive-header-is-unwritten.md).)

### 10. The UI strings: 87% of the translated interface text still matches

`GlobalStrings` reads 27,262 rows (+3 replaced from the hotfix cache), so the UI dictionary can be measured. Of the 700 UI keys the addon translates that come from it, comparing Forever's English with the English the translations were written against:

- **608 identical** (87%).
- **79 changed wording**, e.g. `CHAT_FLAG_AFK` `<AFK>` → `<Away>`, `CHAT_FLAG_DND` `<DND>` → `<Busy>`, `GUILD_MOTD_LABEL` "Guild Message Of The Day:" → "Message of the Day", `GUILD_STATUS` "Show Guild Status" → "Guild Status", and the stat tooltips rewritten around colour codes (`DEFAULT_STAMINA_TOOLTIP` "Increases health points." → "Increases |cFFFFFFFFHealth|r by %s").
- **13 absent**, mostly the `*_COLON` labels and the per-class intellect tooltips.

The other 978 UI keys come from `SpellItemEnchantment` and similar tables. They read from the archive but stop at the layout-hash gate (below).

So the UI dictionary mostly survives; about 92 strings need a re-pull and a re-draft. That is translation work, not addon work, and it belongs with the Forever English harvest.

**Nothing shows wrong Japanese in the meantime.** `Core/UIStrings.lua` admits a shipped row only when the hash of the client's own global string equals the row's `h1` (ADR-002 / ADR-015), so a string Forever reworded stays English: the same guarantee the quest stale marker gives, applied at build time.

### 11. The TOC interface number

The TOC said `## Interface: 11509` (Classic Era 1.15.9), so the addon loaded only with "Load out of date AddOns" ticked. The probe read the client's own number, **16001** (build 1.60.1.69893), and the TOC carries it.

## The addon on Forever, in game

Build 1.60.1.69893, interface 16001, with guarded surface init and the second tooltip path installed ([ADR-025](../adr/025-guarded-surface-init-and-runtime-tooltip-path.md)).

**It loads, and a broken surface costs only itself.** `/wfj debug` printed:

```
surface errors: raid: Interface/AddOns/WoWForeverJapanese/UI/Labels.lua:62: attempt to call a nil value
tooltip frames: 6/6 · hook path: dataprocessor · spell description API: present
```

One surface failed. Without the guard, that same error would have killed every surface after it and `Slash.register` with them (finding 2). With it, the failure is a *report* rather than a symptom. (The cause: a client name resolved to an object that is not a text widget, so `Labels.show` called `GetText` on it. `Labels.widget` now refuses anything it cannot read.)

**The tooltip took the modern path** (`hook path: dataprocessor`, all six declared frames hooked), and `C_Spell.GetSpellDescription` resolved as a dotted candidate. Both of ADR-025's decisions held on the client they were written for.

**Japanese rendered on Forever** for the micro-menu buttons (タレント, バックパック), item tooltip structural lines (売値) and spell tooltip structural lines (即時).

**Item and spell *description* runs stayed English, correctly.** The data was Vanilla-keyed and this was the beta client:

- item 4536's Japanese bakes the number `61` where the live client says `58`, so `Align.check` refuses it (ADR-007) and the tooltip is left untouched;
- Shadowmeld's Japanese is keyed to the modern spell id 58984, which the Vanilla English corpus rejected as `no_english_id`.

About **72% of item and spell descriptions were withheld for `no_english_id`**. That is a data gap (the Forever English harvest and the re-translation after it), not a bug in the surface: the addon refuses to show text it cannot prove matches what the player is looking at, which is the whole of [ADR-002](../adr/002-live-english-only.md) and [ADR-007](../adr/007-unaligned-ships-with-runtime-gate.md).

## What the client's source said the addon had to change

1. **Isolate surface init.** Each `init` call needs its own guard, and the failures need to be listed (`/wfj debug`), which also gives a compatibility report on any future client.
2. **Hook tooltips through the data processor.** On a client where `TooltipDataProcessor` exists:
   - `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)` and the same for `Enum.TooltipDataType.Spell` (`Unit` also exists) replace the two `HookScript` calls.
   - The handler receives the tooltip itself, and the client's own helpers filter with `tooltip:IsTooltipType(Enum.TooltipDataType.Item)` (`blizzard_sharedxmlgame/tooltip/tooltiputil.lua`).
   - One registration covers every tooltip that uses the system, so the six-frame loop (`GameTooltip`, `ItemRefTooltip`, `ShoppingTooltip1/2`, `ItemRefShoppingTooltip1/2`) is not needed there. The `HookScript` path stays for clients without `TooltipDataProcessor`.
   - `OnHide` is a plain widget script and is unaffected.
3. **Hook mixin methods where the global writer is gone.** Confirmed in the source: `AddonList_InitAddon` → `AddonListMixin`, `ContainerFrame_GenerateFrame` → `ContainerFrameMixin`. `hooksecurefunc(frameOrMixin, "Method", fn)` is the same shape the gossip surface already uses.
4. **Set the TOC interface number** from the probe's `select(4, GetBuildInfo())`.
5. **Route the direct API calls through `Compat`.** The two quest-log calls were already broken, not merely unguarded. All four quest-log APIs are declared through `Compat`, and the surface returns early when any is missing. No `C_QuestLog` candidate is named, since naming one would be a guess (finding 8). Declaring the rest is hardening, so that a future removal degrades instead of throwing.

## Corrections

Five of this survey's first claims did not survive being re-checked: C1 to C4 against the addon's own source, C5 against the client's. Three more came from reading the TOC, and the [headline finding](#the-headline-finding-forevers-game-type-is-camelot) now states them correctly: `camelot` is a mainline-family type (a file not naming `camelot` can still load), the quest window runs mainline code, and the game type does explain mail, honor and friends.

### C1. There was no unguarded client-object use in `GossipChrome.lua`

The first reading named `UI/GossipChrome.lua` as using `ScrollUtil` without a guard. The line in question is the assignment `local util = Compat.get(SURFACE, "scrollUtil")`; the call sits inside `if type(panel.ScrollBox) == "table" and type(util) == "table" and type(util.AddInitializedFrameCallback) == "function" then`. The addon's other two `ScrollUtil` users (`UI/Gossip.lua`, `UI/Raid.lua`) guard the same way. No guard was added; tests instead init each of the three surfaces against a stub client where `scrollUtil` is absent.

### C2. There was no bare `IsAddOnLoaded` call in `UI/LoadOnDemand.lua`

`LoadOnDemand` takes its loaded-check by injection (`function LoadOnDemand.init(loadedFn) if type(loadedFn) == "function" then isLoaded = loadedFn end`), and `Main.lua` passes `function(name) return type(C_AddOns) == "table" and type(C_AddOns.IsAddOnLoaded) == "function" and C_AddOns.IsAddOnLoaded(name) end`. The namespaced form was already preferred and guarded.

### C3. "Guild → Communities" was unevidenced when made, and is now evidenced

The first reading said the guild UI was replaced by the Communities frame. The evidence cited was `probe: absent · source: absent`, on a run where most interface files appeared not downloaded (C5) and where `GuildFrame` itself came back `names only`: absent to the probe but present in the extracted source. That is the signature of a frame not yet created, not of one removed, so the claim was withdrawn as unsupported.

Once the whole interface was readable, `blizzard_communities/camelot/` turned up in the client's own source, gated to the `camelot` game type like every other camelot override. The guess was right, and it was still a guess when made. The claim now stands **on the client's TOC, not on that probe row**. The second probe did not settle it either: guild's marks were withdrawn there too (level-10 gate).

### C4. The first probe ran once, at login

`WFJProbe` first swept its 386 names on `PLAYER_LOGIN` and only then. Any frame the client builds on demand does not exist at that moment, so it answers "absent", which is indistinguishable from "Forever removed it".

The addon names three of these itself: `UI/Talents`, `UI/Trainer` and `UI/Raid` set up through `LoadOnDemand.when("Blizzard_TalentUI" | "Blizzard_TrainerUI" | "Blizzard_RaidUI", …)`, so their 22 `rework` names were **unanswerable at login on any client**, including Classic Era where those surfaces work. The same reading explains the `names only` verdicts on `ClassTrainerFrame`, `PlayerTalentFrame`, `GuildFrame`, `SpellBookFrame`, `SpellBookFrameTabButton1/2` and `SpellBookPageText`.

The fix was a measurement one: the probe now also sweeps on every `ADDON_LOADED` and on `/wfjprobe <surface>`, and `client_surface report` will not call a name `rework` on a surface that was never asked with its window open; it says `unknown (window never opened)` instead ([Pipeline → the client-surface probe](../systems/pipeline.md)). The recount moved in the expected direction: `rework` fell from 83 to 37 and `unknown` rose from 67 to 141.

### C5. The client archive was never sparse

The first reading said most content was not on disk: 3,049 of 4,044 named interface files, every DB2 table, and with them the source path for trainer, guild and talents. **None of that was true, and the cause was ours.**

`io/casc.py` rejected any archive entry whose 30-byte header did not repeat the encoded key. The Forever beta client (1.60.1.69893) leaves that header **zeroed** and writes the BLTE payload at +30 as normal. Evidence, `data.054@724649371`, the file the client says is there, read byte for byte:

```
00000000: 0000 0000 0000 0000 0000 0000 0000 0000
00000010: 0000 0000 0000 0000 0000 0000 0000 424c   ← BLTE at +30, exactly where it belongs
00000020: 5445 0000 26c4 0f00 ...
```

A blank header is *unwritten*, not *wrong*. `read_blob` now trusts the index when the header is blank (a header naming a **different** key still raises), and `read_file` verifies the decoded bytes against their **content key** instead. A content key is the MD5 of the content, which proves the index pointed at the right bytes far better than the header field did. The reasoning and the alternatives are [ADR-026](../adr/026-blank-archive-header-is-unwritten.md).

Measured on the live client after the fix:

| | |
|---|---|
| interface files extracted | **4,042 of 7,706 candidate paths** (before: 995 of a narrower 4,044-path list) |
| `DBFilesClient/Spell.db2` | 31,767 rows |
| `DBFilesClient/SpellName.db2` | 31,767 rows |
| `DBFilesClient/GlobalStrings.db2` | 27,262 rows (+3 replaced from the hotfix cache) |
| `DBFilesClient/ItemSubClass.db2` | 100 rows |

`ItemSparse`, `QuestV2`, `SpellItemEnchantment` and `ItemEffect` read from the archive and stop at a **different and correct** gate: their DB2 layout hash changed on this build, so `client_tables` refuses to apply a column map verified against another layout rather than guess column positions ([ADR-021](../adr/021-client-tables-from-the-local-archive.md), [principle 9](../architecture/principles.md)). Parts of `Spell` and `SpellName` are genuinely **encrypted** (5 sections, 16 to 275 records each, keys we do not hold): a real limit, and a small one.

The lesson: the error that means "not downloaded" is a different one (an ekey absent from the local index). The survey built its central limitation on an error message from our own reader and never checked the bytes behind it. **An error message from our own code is not a measurement of the client.**

## What stayed unknown

- **How much of each camelot replacement the addon can reuse.** Answered by [the camelot re-target research](2026-09-19-camelot-surface-retarget.md).
- **Whether a surface that resolves still *behaves* the same.** A frame can exist under its old name and be written by different code. Confirmed only for the quest window (visually) and gossip (by reading the mixins).
- **The 29 dynamic names** (`RaidGroup1Slot2`, tooltip line widgets, …). They are built at runtime and need the live client.
- **Whether SavedVariables carry across**, and whether the never-touch widget list changed.
- **The quest English delta.** The beta's `Cache/WDB` was empty: WoW writes the caches on a clean logout, and the first sessions ended in client crashes. The archive side was no longer a blocker (C5); `ItemSparse`, `QuestV2`, `SpellItemEnchantment` and `ItemEffect` needed their column maps re-verified for this build's layout hash ([the DB2 column research](2026-09-18-forever-db2-columns.md)).

One question this survey did answer: Classic Era 1.15 and Forever could share one addon build. The addon took either tooltip path by capability, with no TOC split and no per-client data ([ADR-025](../adr/025-guarded-surface-init-and-runtime-tooltip-path.md)). The project later made Forever its only target ([ADR-034](../adr/034-forever-is-the-only-target.md)).

## Related

- [ADR-026: A blank archive-entry header is unwritten, not wrong](../adr/026-blank-archive-header-is-unwritten.md) (what C5 decided)
- [ADR-025: Guarded surface init and a runtime-chosen tooltip hook path](../adr/025-guarded-surface-init-and-runtime-tooltip-path.md) (from findings 1 and 2)
- [ADR-021: Client tables from the local archive](../adr/021-client-tables-from-the-local-archive.md) (the read-only archive path this reuses)
- [ADR-009: Surfaces post-hook the writer](../adr/009-surfaces-post-hook-the-writer.md) · [ADR-019: Quest English per field and live check](../adr/019-quest-english-per-field-and-live-check.md) (the stale marker in finding 3)
- [The camelot re-target research](2026-09-19-camelot-surface-retarget.md)
