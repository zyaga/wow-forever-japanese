# ADR-045: Player fix reports: from the game to data/ through a pasted report

- **Status:** Accepted. Implemented in `addon/WoWForeverJapanese/Core/RecentLines.lua`,
  `Core/Reports.lua`, `Core/ReportText.lua`, `UI/FixWindow.lua`, `UI/MinimapButton.lua`, `UI/Render.lua` (the
  `noteRecent` hook), `UI/OptionsWidgets.lua` (`W.scrollList` / `W.scrollText`, the one-language `W.pick` / `W.relabel`), `UI/OptionsText.lua`,
  `UI/Options.lua`, `UI/Slash.lua`, `Core/Settings.lua` (`minimapButton`), `Main.lua` (the addon-dropdown handlers),
  the TOC (`AddonCompartmentFunc` lines); `pipeline/wfj/core/fix_report.py`, `pipeline/wfj/cmd/fix_report.py`
  (`wfj report check|intake|apply`), `pipeline/wfj/core/model.py` (`report` / `model` provenance),
  `pipeline/wfj/dev/gen_attribution.py` (Correctors), `pipeline/wfj/dev/gen_report_vectors.py`,
  `vectors/report_vectors.{jsonl,lua}`,
  `.github/ISSUE_TEMPLATE/translation-report.yml`, `.github/workflows/report-check.yml`, `Makefile`
  (`report-intake`, `report-apply`).
- **Date:** 2026-09-28

## Context

A player who reads a wrong or awkward Japanese line needs a way to say so. A bare new-issue URL is not enough: the player has to describe the line in words, and nothing identifies which store entry they mean. On the pipeline
side, a correction needs its readings rewritten in the same step, and a player whose Japanese ships should be
credited in `ATTRIBUTION.md` like the predecessor translators.

Constraints:

- The client makes no network call, so anything a player sends leaves the game by copy and paste.
- The [principles](../architecture/principles.md): no English game text shown or stored by the addon; nothing added
  to the screen outside the allowed list; lines addressed by game id (or English hash), never by position; a `human`
  line is never replaced by machine output without a logged decision.
- The pipeline calls no model; drafting is a separate step, as for every batch
  ([ADR-023](023-server-only-text-drafted-in-measured-batches.md)).
- Players type Japanese poorly on many keyboards in game; typing must not be required.

## Decision

1. **A minimap button** is one of the allowed on-screen additions ([principle 3](../architecture/principles.md#3-japanese-by-default-english-one-key-away)): a small button on the minimap edge, draggable around it; left-click opens the fix window; right-click
   opens a menu with Translation on / off (the master switch), Report a line, Settings, Hide this button. It is on by
   default and hidden by the `minimapButton` setting. The addon also has an entry in Blizzard's addon dropdown on the
   minimap (the TOC's `AddonCompartmentFunc`), with the same two clicks, so hiding the button never locks the player
   out. Nothing is added to Blizzard's game frames; the fix window is a tool window the player opens.
2. **Clicks only; typing optional.** Opening the window, picking a line, picking a reason, saving and copying are
   all clicks. The optional note and the optional Japanese are the only boxes that take typing. `/wfj fix` and an
   About-page button are further ways in, never the only one.
3. **One language at a time.** The fix window, the button's tooltip and its menu, the settings pages and the AddOn
   List tooltip show the addon's own copy (`UI/OptionsText`) in Japanese; when translation is off or while the reveal key (default Alt) is held
   they show the English copy, the rule the game text follows. The fix window and the settings pages re-label live on
   the State `modifier` and `enabled` events, except while a text box has focus (the client sends no modifier event
   then); the tooltip and the menu take the language when they open. Showing both languages at once was tried in game and
   rejected: too hard to read.

   **The client's own widgets.** The fix window is built from
   the templates Forever's windows use (`ButtonFrameTemplate`, `TabSystemTemplate` tabs, `WowScrollBoxList` lists
   with `MinimalScrollBar`, `ScrollingEditBoxTemplate` fields in a `TooltipBackdropTemplate`, `UIRadialButtonTemplate`
   radios for the filter and the reasons), so it reads as part of the game. One **Save** button: a changed line goes
   with the report, an untouched one sends the reason only. The player-facing copy says "report" (報告), never "fix". The Send report page lists the steps in the
   order the player does them: open the form, copy the report, paste and submit, clear the reports sent.
4. **No English game text in the fix window.** The window shows the Japanese the addon shipped for a line, never
   the English the client showed ([principle 4](../architecture/principles.md#4-the-addon-never-ships-stored-english)); showing this session's English from memory would widen
   that principle. Saved fixes and the report carry no English either.
5. **Addressing.** A fix names the store address the addon rendered (`type`, `id`, `field`; gossip / book: the
   16-hex English hash the addon keys the line by) and `ja_hash`, the addon hash of the Japanese as stored. The
   pipeline applies a fix only when that hash still matches the Japanese that ships; otherwise the fix is skipped as
   already changed. The addon records only lines the store holds as one entry; a branch-variant line
   ([ADR-043](043-included-text-icons-and-branch-variants.md)) records nothing. The fix window lists each line as
   the player saw it (values filled in, player tokens expanded, markers and colour codes removed), but the report
   carries the hash of the **stored** line, so the pipeline has the before. The edit panel is one large editable
   box pre-filled with the stored line; only a changed line travels as the after. There is no in-game diff
   highlight: colour codes in an EditBox would become text the player edits, and a separate change strip adds little.

   **Recent lines are grouped:** story (quest, gossip, book, objective, area) · tooltips (item, spell) · windows
   (ui), each capped at 100 on its own, so a window full of labels never pushes quest lines out; the list filters by
   group (All first and the default, then Quests & NPCs, Tooltips, Windows). Lines one surface writes within 1 second of each other are one burst; the list
   shows the newest burst first and each burst in written order, the on-screen order.
6. **Report grammar, version 1.** A plain-text block framed so a cut paste is detectable: `WFJ-REPORT 1`, an
   `addon … client …` line, one `fix <type> <id> <field> <ja_hash> <reason>` line per fix with optional `note` and
   `ja` lines, and `end <count>`. A report holds at most 25 fixes, the number the addon keeps; the parser refuses
   more. The grammar is in [Fix reports](../systems/fix-reports.md); the Lua serializer and
   the Python parser share one vector file (`vectors/report_vectors.*`, `make vectors`). **`|` is written as
   `\x7c`**, not as a doubled `||`: `|` starts an escape sequence in WoW text, so rather than
   depend on how the client's EditBox shows or copies a doubled bar, the report never holds a `|` at all and both
   sides escape and unescape one fixed sequence (`\\`, `\n`, `\x7c`; any other escape is an error).
7. **GitHub side.** An issue form (`translation-report`) takes the report (required), an optional "Credit me as" and
   a required licence consent. The `report-check` workflow (read-only by default; its one job gets `contents: read`,
   `issues: write`, the one exception to [ADR-046](046-one-action-release.md) §6's "the release job alone writes",
   limited to the issue it reads, never contents; its actions pinned to commits like every workflow's) runs `wfj report
   check` on the body when an issue with that label is opened or edited, writes a summary as its one comment on the
   issue (an edit of the issue rewrites that comment) and labels `report-ok` or `report-broken`. **It only checks the paste** (that it reads, that each fix names a real line, and whether a line
   changed since), never whether a translation is right. The body reaches the parser through an env var and a file,
   never the script text.
8. **Intake → drafting → apply, when the maintainer takes a report.** `make report-intake ISSUE=N` writes the triage
   and the skipped rows to the report's local working folder; a drafting pass writes `decisions.jsonl` under the
   report drafting rules: `use` (the player's Japanese, edited as little as needed), `rewrite` (the model's own line)
   or `keep` (with a reason a player would accept), plus `words` for every changed quest / gossip / ui / plain-book
   line; `make report-apply ISSUE=N MODEL=…` checks every row (writes
   nothing if one fails), writes the lines, imports their readings, updates the Correctors, writes `reply.md`, then
   runs `check generate validate coverage`. Apply's own gate is the pipeline's status rules (`check_type`: Japanese,
   names kept, numbers, tokens) on every changed line: a line that would not ship is refused; `translate_lint` is
   not run. The PR with `Fixes #N`, merged by the maintainer, is the logged decision.
9. **Provenance written by apply.**

   | Shipped line | Decision | Written |
   |---|---|---|
   | any | `use` | a `correction` variant: `translator` = the credit name, `corrects` = the corrected variant's source, `report` = N, `note` = the reason and what the model changed; no `model` |
   | `human` / `correction` | `rewrite` | a `correction` variant: `translator` = the corrected variant's translator (as `apply_review` does), `model`, `report` = N, `note` |
   | `machine` still guarded by a live hand-written variant (an `accept` ruling) | `rewrite` | a `correction` variant as above, `translator` = "the maintainer" (the ruling's owner), `model`, `report` = N |
   | `machine` (unguarded) | `rewrite` | the shipped machine variant rewritten **in place** (machine replaces machine, [ADR-014](014-machine-drafted-text-and-ui-dictionary.md)): `source` = `report-N@<date>`, or `report-N-sg<style guide version>@<date>` for a styled field, `model`, `report` = N |
   | any | `keep` | nothing in `data/`; the note goes into `reply.md` |

   A corrected `correction` variant moves to `conflicts` under a `reject` ruling ("superseded by the correction from
   fix report #N"); its `corrects` carries over. No machine output ever lands as a machine variant over a
   `human` or `correction` line.
10. **Readings in the same apply.** Each changed line's `words` are imported as machine reading records (`source`
    `readings@report-N`) whose `ja_hash` is the new Japanese. A line holding `|` (a colour code or other escape), an
    HTML book page, and `item` / `spell` / `objective` / `area` lines take none.
11. **Credit.** The credit name is the issue form's "Credit me as", else the issue author's GitHub login, else "a
    player"; it keeps only letters of any script, digits, spaces and `._-`, at most 40 characters (no markdown, HTML,
    `@` or invisible format character), since it ships in `ATTRIBUTION.md`. The addon never takes a credit from the
    character's name. It reads that name for one thing only: to take it out of what the player typed. A saved fix
    holds the `{name}` placeholder wherever the note or the Japanese held the name, in any letter case
    (`Reports.withoutName`), and holds no time.
    The form's Permission box is read again at intake; a player's Japanese never ships without it.
    `ATTRIBUTION.md` gains a **Correctors** section (before Lineage) listing each translator of a `correction`
    variant that carries `report` and no `model` (the players whose own Japanese ships), with their issue numbers.
    Apply edits that section in place; `gen_attribution.py` keeps it on a regeneration; every other section is
    unchanged.
12. **Schema.** Provenance gains optional `report` (a positive int, on `correction` and `machine` only) and, on
    `correction`, optional `model` (a non-empty string). `data/SCHEMA` stays `1`.

## Consequences

- A report names the exact line the player saw; a line changed since the player's build is skipped, not
  misapplied. A cut paste is caught by the workflow within a minute, before the maintainer looks.
- From issue to PR is one intake command, one drafting pass and one apply command; readings and meanings of the
  changed lines never go stale.
- The addon writes `WFJ_DB.reports` (at most 25 pending fixes) and `WFJ_DB.minimap.angle`, both created only when
  first used; older versions ignore both.
- A player's poor or hostile Japanese never ships unjudged: the drafting pass reads each against the English and the
  style guide, `keep` / `rewrite` are allowed, and nothing ships before the maintainer's merge.
- The provenance validator has two optional keys; removing this feature after a report was applied fails
  validation until those report PRs are reverted first.
- The workflow runs repo code on issue text; it treats the body as data (no eval, no shell interpolation). It can be
  disabled from the Actions tab without a release.

## Alternatives considered

- **A button on the quest / NPC window.** Rejected: adds to Blizzard's game frames; the minimap button is one
  element the player can hide.
- **One capped list for every line.** Rejected: opening a few windows of labels pushed the quest lines out.
- **Show the English the client showed this session in the fix window.** Rejected for now: the addon never shows
  stored English.
- **`||` for `|`** (the chat EditBox convention). Rejected: depends on client behaviour in the copy box; `\x7c`
  keeps the report free of the character.
- **Judge translation quality in the workflow.** Rejected: the workflow has no model; judging is the drafting pass's
  job.
- **Call a model API from the pipeline for drafting.** Rejected: the pipeline calls no model; drafting is its own step.
- **Credit the character name from the game.** Rejected: the addon would read personal data into a public report;
  the issue form asks instead.
- **Both languages at once in the fix window.** Tried in game and rejected: too hard to read.
- **A read-only copy of the shipped line above the edit box, or a diff highlight.** Rejected: one box is enough (the
  report's hash is the before); colour codes in an EditBox would become editable text.
- **A StaticPopup to confirm a replace or clear.** Not used: the Japanese in Blizzard's popup font is unverified; the
  window uses the settings pages' click-again-within-5-seconds pattern.
