# ADR-067: Interface lines with links, colour-wrapped names and plural groups; a line stays English only on a proven reason

- **Status:** Accepted
- **Date:** 2026-10-12
- **Amends:** [ADR-016](016-whole-window-interface-coverage.md) §10 (links barred from the dictionary), [ADR-031](031-objective-lines-menus-and-helptips.md) §4 (the curation test forbids `|H`), [ADR-035](035-ui-errors-frame-surface.md) (a chat line whose English carries a link stays English).
- **Related:** [ADR-014](014-machine-drafted-text-and-ui-dictionary.md) (the UI dictionary) · [ADR-015](015-ui-text-surfaces.md) (one dictionary, targeted hooks) · [ADR-037](037-staticpopup-dialogs-and-owned-keys.md) (dialogs whose caller formats the line) · [ADR-066](066-recipe-and-set-bonus-lines-from-the-tooltip-data.md) (the set bonus lines) · [ADR-052](052-coverage-by-served-data.md) (coverage from served data) · [Addon modules](../architecture/addon-modules.md) · [Coverage](../operations/coverage.md)

## Context

`pipeline/ui_exclusions.txt` is the list of interface strings the addon leaves English, each with a reason. Four hundred and two of those reasons were weak: "a retail-era system, unverified in game", "colour / link / texture markup (curation rule)", "not matched in v1", "messages are not covered", or a reason that was simply wrong (the set bonus lines were called "not a single tooltip line"; they are one line each, shown since by ADR-066). Nothing checked those reasons against the Forever client, so a line the client does show on Forever (the account bank's title, the quest log's story header, the newcomer chat hint, the cross-faction invite words) stayed English for no reason a reader could verify.

Three of the old reasons were rules, not facts:

- **Links.** The dictionary never carried a `|H…|h…|h` link except one static URL. Every system chat line with a player or loot-history link (a friend coming online, a loot roll, the level-up line) and every dialog with a store link stayed English, even though the words outside the link are ordinary prose.
- **Colour codes around a name.** A template like `|cff00ff00<Made by %s>|r` was refused as markup. The client sometimes prints the same line without the colour code, with the colour set on the line instead, so one shipped form could not match both.
- **Plural groups.** `%d |4day:days;` was admitted in principle, but the keys that carried one had been left out on the markup reason.

## Decision

1. **A line stays English only on a proven reason.** Each of the 402 reasons re-judged here names a proof: a Forever client file and line (`<path>.lua:N`, `.xml:N`, `.toc:N`), a client table row count or absence on the current build (`make forever-table-counts`; a table the archive does not carry is the same proof as zero rows), a spell id checked against `SpellName`, a disposition file, another key that ships the same English, or the line being a name, a link label or wordless markup. `tests/python/test_ui_worklist.py` requires each of the 402 re-judged keys to be translated, or kept with a proof pattern in its reason, and `tests/python/test_ui_exclusions.py` fails on the old phrases (`[unverified in game]`, `curation rule`, `not matched in v1`, `messages are not covered`, `not a single tooltip line`, `ADR-015 §5`). `pipeline/wfj/dev/ui_reach.py` lists, for a key, every reference to it in a file the Forever client loads, with the addon and its load state, so a reason can cite the file and line that keeps the string off the screen, or be found to rest on nothing. Of the 402, 201 now ship Japanese and 201 stay English with a proof; one line outside them, the game menu's event error dialog, ships too, so 202 lines in all. The other reasons in the file were not re-judged here, and some still rest on a likely or in-game-check note.

2. **Links ship, kept byte for byte, label included.** A listed English may hold a `|H…|h<label>|h` link when the link's content is literal text plus plain `%s` / `%d` specifiers (a player link, a loot-history link, a store link, a static support URL). `core/markup.link_refused(en)` is the one gate: it refuses a positional specifier inside a link (the Japanese could not keep the English order), `|K` key markup anywhere, a `$` token inside a link, and any other escape inside a link (`|T`, `|A`, `|4`). The Japanese keeps the whole link exactly, the label too, translates only the words outside it, and keeps the arguments in the English order (no `%1$s` inside a link). A line that is nothing but a link and its label (`CENSORED_MESSAGE_REPORT`, `LOOT_ROLL_STARTED`) has no words to translate and stays English with the reason "no words outside the link". The level-up line, the countdown lines, the newcomer welcome, the censored-message prompts and the trial restriction notices join `UIStrings.CHAT_FAMILIES`, so they are matched as system chat.

3. **A colour-wrapped template matches with or without its colour code.** `Core/UIStrings.build` indexes the templates the compiled client prints without their codes (`UIStrings.BARE`: `ITEM_CREATED_BY`, `ITEM_WRAPPED_BY`; a tooltip data line carries its colour as the line's) in a second, bare form with the codes taken out, so a player's own text in the shape of another coloured template ("Raid night (Inactive)") never matches, and `Index:fill` strips the Japanese's colour codes when the bare form matched, so `|cff00ff00<Made by %s>|r` and `<Made by %s>` both show `<製作者: Reyn>` the way the client wrote it. Bare forms are added after every key's own English is in, only where no key has that English itself, so a bare form never takes another key's line or makes it ambiguous; two keys whose bare forms meet with different Japanese get none. A bare form is never a dialog's template name, and a never-touch widget never takes one (a player's own "(Locked)" title stays as typed). A tooltip line the client coloured end to end ("|cffff2020Requires Level 60|r") is matched without its codes and shows its Japanese in the same colour. The sell price range keeps the client's four-space indent before "Minimum" and "Maximum" (gametooltip.lua:325-333). A new capture kind `hex` takes a colour's eight hex digits after a bare `|c` (the dual-wield comparison line, `(With |c%s%s|r equipped in your main-hand)`), kept verbatim.

4. **A plural group is English-only.** The Japanese drops the `|4singular:plural;` group and keeps the specifier (`%d |4day:days;` is `%d日`); the addon matches the English in its singular and plural forms as before (ADR-016 §10). The plural keys left out on the markup reason are listed.

5. **Set bonus lines are ADR-066's.** The set bonus keys were among the 402; their lines are shown by the tooltip-data path [ADR-066](066-recipe-and-set-bonus-lines-from-the-tooltip-data.md) decides (the client's own set spells, matched to the line's text), not here. `ITEM_SET_BONUS_NO_VALID_SPEC` stays English: every ItemSetSpell row on 1.60.1.70338 has ChrSpecID 0.

6. **Coverage reports why the rest is English.** `make coverage` adds "Interface lines left English, by reason" to `docs/operations/coverage.md`: every exclusion counted under one reason category, and a reason no category recognises is listed, never dropped (`tests/python/test_coverage.py`).

### Keys and the surfaces that show them

The translated keys needed hooks on the surfaces that write them. Each hook has a Lua spec.

| Surface (module) | Keys | Where the client writes them |
|---|---|---|
| Quest frame (`UI/QuestFrame`) | `QUEST_REPUTATION_REWARD_TITLE`, `QUEST_REPUTATION_REWARD_TOOLTIP` | the reputation reward row's name and hover (`questinfo.lua:1367–1393`) |
| Quest log (`UI/QuestMap`) | `QUEST_STORY_STATUS`, `STORY_PROGRESS`, `STORY_CHAPTERS`, `EVENT_SCHEDULER_FRAME_LABEL` | the story header's progress line, the story tooltip (the story header's `ShowTooltip`, StoryHeaderMixin, on its own surface `questmap.storytip`), the events tab's hover |
| Click bindings (`UI/ClickBinding`) | `CLICK_BINDING_UNBOUND_OUTPUT` | `SetUnboundText`, the spell's name kept |
| Chat edit box (`UI/ChatTabs`) | `NPEV2_CHAT_HELP_HINT_HERE`, `NPEV2_CHAT_HELP_HINT_DIFFERENT` | `UpdateNewcomerEditBoxHint`, the slash command kept |
| Bank (`UI/Bank`) | `ACCOUNT_BANK_PANEL_TITLE`, `ACCOUNT_BANK_PAGE_NUMBER`, `ACCOUNT_BANK_ERROR_NO_LOCK`, `BANK_LOCKED_REASON_NO_ACCOUNT_INVENTORY_LOCK`, `BAG_CLEANUP_ACCOUNT_BANK`, `ACCOUNT_BANK_CONFIRM_CLEANUP_PROMPT` | the account bank's title (matched by key; the `BankFrameTitleText` FontString stays never-touch), page tabs, money-button reasons, lock prompt, sort confirmation |
| Calendar (`UI/Calendar`) | `CALENDAR_VIEW_EVENTTITLE_LOCKED` | a locked event's title around the title the player typed; the title FontString is shown only in that form |
| Spellbook (`UI/SpellBook`) | `ASSISTED_COMBAT_ROTATION_SPELLBOOK_LABEL` | the assisted combat button's label |
| Transmog (`UI/Transmog`) | `TRANSMOG_COST_MODIFIER_TOOLTIP_*`, `TRANSMOG_PURCHASE_OUTFIT_SLOT_TOOLTIP_DISABLED`, `TRANSMOG_SHOW_EQUIPPED_GEAR` | the outfit cost hover, the purchase button's disabled reason, the show-equipped label |
| Micro menu (`UI/MicroMenu`) | `PET_ACTION_SUBTEXT`, `PET_MODE_SUBTEXT` | the pet command tooltip's second line |
| Unit menus (`UI/MenusUnit`) | `LOOT_SPECIALIZATION_DEFAULT`, `VEHICLE_LEAVE`, `REPORT_PVP_SCOREBOARD` and the vehicle menu's entries | the loot specialization submenu, the vehicle frame's menu, the PvP scoreboard's row menus |
| Achievements (`UI/Achievement`) | `ACHIEVEMENT_COMPLETED_BY`, `ACHIEVEMENT_NOT_COMPLETED_BY`, `ACHIEVEMENT_REQUIRES_GUILD_REPUTATION` | the shield tooltip around the player's name, the reputation criterion |
| Help tips (`UI/HelpTips`) | the micro-button alerts, bag tutorials, map bounty and events callouts, the Pandaren faction choice, the friends list and spellbook callouts | `HelpTipTemplateMixin.ApplyText` |
| Friends (`UI/MenusTags`) | `TRAVEL_PASS_INVITE_CROSS_FACTION`, `SUGGEST_INVITE_CROSS_FACTION`, `REQUEST_INVITE_CROSS_FACTION` | the travel pass menu |
| Communities, guild, petition, raid, talents, report frame, PvP match | the cross-faction member lines, the challenge reward hover, the arena petition instructions, the story raid lock reason, the refund error, the housing report categories, the matchmaking value line | each module's existing `only` lists |
| Popups (`UI/Popups`) | `REMOVE_FRIEND_CONFIRMATION`, `BATTLETAG_REMOVE_FRIEND_CONFIRMATION`, `REMOVE_TITLE_FRIEND_CONFIRMATION` | the `CONFIRM_REMOVE_BN_FRIEND` dialog, whose caller formats the line (pass-through, ADR-037) |
| Item tooltips (`UI/Tooltip`) | `ITEM_CREATED_BY`, `ITEM_WRAPPED_BY`, `MINIMUM`, `MAXIMUM`, the dual-wield comparison lines, the cooldown, enchant time-left and charges lines | the structural pass; a whole-line colour is matched without its codes first |
| System chat (`UI/ChatSystem`) | the loot roll lines, `ERR_FRIEND_ONLINE_SS`, the invite lines, `LEVEL_UP`, `COUNTDOWN_SET` / `_CLEAR`, the newcomer welcome, the trial restriction notices | `CHAT_FAMILIES` |

## Consequences

- 202 more interface lines ship Japanese, with word readings and meanings; 201 stay English, each with a reason a reader can check in the client's files or tables. The coverage report says how many stay English and why.
- A chat line with a link shows Japanese around the English link; the link, its label and its arguments are exactly as the client wrote them. Holding the reveal key shows the English line.
- A new build that moves a cited line number does not break anything by itself; the proof goes stale and the next re-judging updates it. A new build that adds content behind a table counted at zero (an item upgrade, a bonus roll) is caught by re-running `make forever-table-counts`.
- A positional specifier inside a link stays refused by design (`link_refused`). A line that is only a link and its label stays English for another reason: it has no words to translate, and the UI lint fails a draft with no Japanese in it.
- Rollback is a PR revert; the dictionary rows it leaves behind are harmless.

## Alternatives considered

- **Keep links out of the dictionary and translate the words around a link at run time, from a second template with the link cut out.** Two templates per line, and the addon would have to rebuild the link's arguments from a line it did not match whole. Keeping the link in the English and in the Japanese is one template and one byte-for-byte check.
- **Allow positional specifiers inside a link.** The Japanese would have to keep the link's argument order while reordering the sentence's; `format` cannot mix numbered and plain specifiers, so the whole line would need numbering and the link would no longer be byte for byte. Refused; the one line that needed it is not in the client's loaded files.
- **Hand-check the 402 keys in game.** Nobody can reach every surface on one character, and a check proves presence, not absence. A client file and line, or a table row count, proves either and can be re-run per build.
