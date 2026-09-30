# ADR-031: Objective lines by template and fingerprint; menus and HelpTip callouts translated

- **Status:** Accepted. Implemented in `addon/WoWForeverJapanese/Core/Objectives.lua`,
  `Core/Const.lua` / `Core/Data.lua` (the `objective` slot), `Core/UIStrings.lua` (`affix` fill form, the last-break
  `paragraphs` split), `Core/UIStringKeys.lua` (objective `ARGS`), `UI/QuestMap.lua` (tracker `AddObjective`, list objective rows, map
  details objectives, the list title tooltip), `UI/Menus.lua`, `UI/HelpTips.lua`, `UI/FriendsTooltip.lua`,
  `UI/MicroMenu.lua` (stable pet XP bar), `UI/Slash.lua` (`/wfj debug objective`), `Main.lua` and the TOC;
  `pipeline/wfj/core/model.py`, `emit/schema.py`, `cmd/check.py`, `cmd/validate.py` (`rule_objective`),
  `core/status.py` (`PROSE_KINDS`), `core/markup.py` (textures and `|n`), `dev/translate_batch.py`,
  `dev/translate_lint.py`; `data/objective/`, `pipeline/objective_names.txt`. Not yet verified in game on Forever
  (the re-target checklist in [Testing strategy](../testing/strategy.md)).
- **Date:** 2026-09-19

## Context

The re-targeted Forever surfaces ([ADR-029](029-camelot-targets-the-mainline-family.md)) left some interface text
English for want of a mechanism. Three of those gaps needed a design decision:

- **Objective progress lines** ("3/10 Kobold Vermin slain", "Archive Burned: 0/1") in the tracker, the quest list and
  the map details. About 88 % are built by the client from its own templates (`QUEST_MONSTERS_KILLED`
  `%2$d/%3$d %1$s slain`, `QUEST_OBJECTS_FOUND`, `QUEST_FACTION_NEEDED`, `QUEST_PLAYERS_KILLED` and their
  `_NOPROGRESS` forms), none listed. The rest are 394 server-written objective texts ("Rescue Drull"), which
  `data/english/objective` holds keyed by QuestObjective id, with no Japanese store. On camelot no API
  returns an objective id at the writer: the tracker's `block:AddObjective(objectiveKey, text, …)`, the list's
  `objectiveFramePool` rows (`objectiveFrame.questID` only) and `QuestInfoObjective<n>` see a quest id, a position
  and the text. A translation is never addressed by position ([principle 5](../architecture/principles.md#5-every-translation-is-keyed-by-the-game)).
- **Menus.** Dropdown and context-menu entries were left English at first (ADR-016); they should be Japanese too.
  The mainline Menu system runs every callback registered with
  `Menu.ModifyMenu(tag, cb)` for a generated description with that tag (`blizzard_menu/menu.lua:2708–2745`);
  `UI/SpellBook.lua` already used it for its settings menu, top level only.
- **HelpTip callouts** (tutorials and alerts such as "You have unspent talent points."). `HelpTip:Show` stores
  `info`, and the frame's `Layout` calls `ApplyText` (`Text:SetText(info.text)`) and then measures the text for the
  box (`blizzard_sharedxml/helptip.lua:572–647`); it re-applies on every layout. `info.text` is also the tip's
  identity: `HelpTip:IsShowing`, `Hide` and `Matches` compare it with the client's English
  (`helptip.lua:237–305, 717–731`). A plain post-write would overflow the measured box or be overwritten.

A fourth, smaller one: strings with `|T…|t` file-texture markup ("No quests available|n|nAccept quests by talking to
characters with a |T…AvailableQuestIcon:16:16|t above their head.") were kept out of the dictionary by curation.

## Decision

1. **Objective lines: the client's templates first, then an `objective` data type matched by fingerprint.**
   - The objective templates with words of their own join the dictionary (`QUEST_MONSTERS_KILLED`,
     `QUEST_PLAYERS_KILLED[_NOPROGRESS]`, `QUEST_FACTION_NEEDED[_NOPROGRESS]`). Their name arguments (the mob, the
     player group, the faction) are `text` captures kept as written; a faction standing is a `word` argument, shown in
     Japanese. A collect line (`%2$d/%3$d %1$s`) is counts and an item name only and stays as written.
   - The server texts get a Japanese store: data type `objective`, `data/objective/*.jsonl` keyed by QuestObjective id,
     generated to `Data/Objective/Objective_NNNN.lua` rows `{ text, h1, status }`.
   - The addon (`Core/Objectives.lua`, pure) finds a row by the **fingerprint** of the live line: it sets the count
     aside (`"3/10 "` before the text, or `": 3/10"` after it), hashes the rest (`Normalize.v1` + `Hash`, the same
     `h1` the row carries) and looks it up in an `h1 → id` index built once at load. The count is put back where the
     client wrote it, verbatim. This is the ItemSubClass / enchantment precedent of ADR-015: data keyed by id,
     matched by the English's hash where the client exposes no id.
   - Two objectives with one English and different Japanese are **ambiguous**: the addon never shows either, and
     `validate` refuses to ship them (`rule_objective`).
   - An objective whose whole text is a name ("Flame of Azel") gets no Japanese line; it is recorded in
     `pipeline/objective_names.txt` and stays English ([principle 2](../architecture/principles.md#2-names-stay-in-english)).
   - One hook per writer: the tracker block's `AddObjective` (the block's height follows the line's), the quest
     list's `objectiveFramePool` rows after `QuestLogQuests_Update`, and the map details'
     `QuestInfoObjectivesFrame.Objectives`. The details pane's " (Complete)" tag is rendered through
     `PARENS_TEMPLATE` / `COMPLETE`.

2. **Menus through `Menu.ModifyMenu` initializers, one tag at a time, each with its own key set.** `UI/Menus.lua`
   registers one callback per tag in `Menus.TAGS` (each tag with the source line of its generator). The callback walks
   the description's elements, submenus included, adding an initializer that shows the element's `fontString`
   through `Labels.show` with `only` = the tag's keys, and a resetter that drops the record when the frame returns to
   the pool. A rank name, a bag the player named or a quest title in a menu is never read as a dictionary word.
   Tooltip keys (a disabled radio's reason, `GUILD_RANK_UNAVAILABLE`) go through `UI/HelpTooltip` on the element.
   `UI/SpellBook.lua` keeps its own settings-menu hook (the second copy; a third would be extracted).

3. **HelpTip callouts by a post-hook on `ApplyText`.** `UI/HelpTips.lua` hooks `HelpTipTemplateMixin.ApplyText` for
   frames the pool makes later, and every frame the pool already holds (active or inactive) on its own. The hook
   rewrites `Text` through `Labels.show` with `only` = `HelpTips.KEYS`. It runs before `Layout` measures, so the box
   fits the Japanese, and again on every layout. **`info.text` is never written**, so Blizzard's identity checks keep
   comparing English with English.
   **Pointer arrows.** The tutorial manager's pointer arrows go through the same module and record
   surface (`help.tips`). `TutorialPointerFrame:Show(content, direction, anchorFrame, ofsX, ofsY, relativePoint,
   backupDirection, overrideWidth)` takes a pooled frame, writes `Content.Text:SetText(content)`, sizes `Content` from
   the text (width `min(GetStringWidth(), overrideWidth or 200) + 40`, height `GetHeight() + 40`), shows it, stores it
   in `InUseFrames[NextID]` and increments `NextID` (`blizzard_tutorialmanager/blizzard_tutorialpointerframe.lua:47–138`).
   `UI/HelpTips.lua` post-hooks that table method, reads the frame the call just stored (`InUseFrames[NextID - 1]`),
   rewrites its text through `Labels.show` with `only` = `HelpTips.POINTER_KEYS` (record key `pointer.<n>` per pooled
   frame, never a position) and re-applies the client's sizing rule to the Japanese, with the call's `overrideWidth`;
   the reveal key re-renders through the same refit. The keys are the class tutorial's
   (`NPEV2_SPEC_TUTORIAL_GOSSIP_CLOSED`, `TALENT_MICRO_BUTTON_UNSPENT_TALENTS`, `NPEV2_SELECT_TALENTS_TAB`;
   `blizzard_tutorials_classes.lua:88, 297, 310`), the only caller reachable on Forever; the new player experience,
   boost and Remix tutorials also use the pointer but never run there, and their text is never read. Whether the class
   tutorial's gates (`CanUseClassTalents`, `IsPlayerInitialSpec`) ever open on Forever is [unverified in game].

4. **`|T…|t` is markup, not a label form.** `core/markup.TOKEN` counts each file texture verbatim (path and size) and
   the `|n` break escape, like colour codes and `\n`; a Japanese that drops, adds or alters one is `rejected`
   (`markup_changed`). The curation test forbids `|H`, `|K` and `$`.
   An atlas `|A…|a` is counted verbatim like a file texture and a named colour opener `|cnNAME:` like a hex one, and
   `|A` may be listed; menus also have utility-button tooltips, an optional per-tag `show`, per-`which` unit lists and
   an untagged context-menu hook ([ADR-038](038-menus-callouts-and-composite-forms.md)).

## Consequences

- Objective lines show Japanese on Forever without an objective id and without a position. The fingerprint is a match,
  not a key: `data/` stays keyed by QuestObjective id, and a translator edits one id's line.
- Shared English is a hard constraint on objective drafts: every id with the same English ships the same Japanese,
  or none of them shows. `validate` catches it before release; `/wfj debug objective` counts it in game.
- An objective whose English the server changes stops matching and shows the live English (the same behaviour as a
  moved UI string).
- Menus run the addon's code inside Blizzard's menu initializers. `AddInitializer` is Blizzard's own extension point,
  but a protected menu (the raid pullout) could still taint; that is an in-game check, not a proven property.
- Every tag is a hand-kept list of keys. A menu entry Blizzard adds under an existing tag stays English until its key
  is added to the tag.
- HelpTip hooks a mixin method copied onto pooled frames; a frame that bypassed both the mixin and the pool would be
  missed. Sizing is only verified on the stub.
- Composite exclusions now say which they are: `permanent:` (why no form can reach them) or `follow-up:` (a named new
  form that is not built yet). The exclusions test forbids any other composite reason.

## Alternatives considered

- **Ship a quest → objective-order map and address the line by (quest id, index)**: rejected. The order in which the
  client lists a quest's objectives is not verified against the QuestObjective order in the cache, and the tracker
  and list give an index, not an id. A wrong order would show another objective's Japanese, silently.
- **Key objective data by the hash of its English, like gossip**: rejected. Data is keyed by game ID where one
  exists, and objectives have one. Only the addon's lookup uses the fingerprint.
- **A texture label form** (translate the words around `|T…|t` and splice the texture back): rejected. The three keys
  with words carry the texture inside their own English, so treating the texture as verbatim markup is enough; a new
  form would be one more matcher path for three strings.
- **Write the Japanese into `info.text` before `HelpTip:Show`**: rejected. `IsShowing`, `Hide` and `Matches` compare
  `info.text` with the English; the client's own code would stop finding its tips.
- **One global menu hook for every tag**: rejected. It would read every menu's text as a dictionary candidate,
  including player, rank and bag names.

## Related

- [ADR-015: UI text surfaces](015-ui-text-surfaces.md): fingerprint-matched rows (ItemSubClass, enchantments)
- [ADR-016: whole-window interface coverage](016-whole-window-interface-coverage.md): the markup rules extended here
- [ADR-029: camelot targets the mainline family](029-camelot-targets-the-mainline-family.md)
- [Data model](../architecture/data-model.md) · [Addon modules](../architecture/addon-modules.md) ·
  [Pipeline](../systems/pipeline.md)
