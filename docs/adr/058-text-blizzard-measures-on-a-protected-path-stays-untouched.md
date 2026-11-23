# ADR-058: Text that Blizzard measures on the way to a protected call stays untouched

- **Status:** Accepted
- **Date:** 2026-10-04
- **Related:** [Client limits](../architecture/client-limits.md) · [Diagnostics log](../systems/diagnostics.md) · [Lesson: the spellbook blocked the action bars](../lessons/2026-10-04-spellbook-text-blocked-the-action-bars.md) · [ADR-016](016-whole-window-interface-coverage.md) (whole-window interface text) · [ADR-029](029-camelot-targets-the-mainline-family.md)

## Context

On Forever 1.60.1.70205 the game blocked Blizzard's own action bars under this addon's name in combat
("Interface action failed because of an AddOn"; `ADDON_ACTION_BLOCKED` on `MainActionBar:SetPointBase()`,
`StanceBar:ClearAllPointsBase()`, `PetActionBar:SetShownBase()`, `MultiBar*:HideBase()` and more). The bars stopped
moving or vanished until combat ended. It showed after a bar page change in combat: a rogue breaking stealth, a
warrior changing stance.

The research for ADR-016 assumed that text written into a Blizzard FontString does not carry taint, because the
taint documentation lists variables, table keys, script slots and closures, not widget properties. That was marked
as likely, never verified.

The addon's problem log traced the path in game, step by step (the probes are described in
[Diagnostics](../systems/diagnostics.md)):

1. The blocked layout read flags on the bars (`showAllButtons`, `snappedToFrame`) that the client reported, with
   `issecurevariable`, as written by code tainted by this addon.
2. Probes on those flags' writers recorded the stacks. Hovering a spell in the spellbook ran Blizzard's hover code
   (`SpellBookItemMixin:OnIconEnter`) tainted. That code then wrote the bars' highlight marks, and on leaving the
   spell it re-ran the bar layout (`PetActionBar:Update`), which stamped the bars' flags.
3. The hover was tainted because it read the spell button's `actionBarStatus`, which was tainted.
4. A probe on that field's writer caught the first tainted write. It happened while a tab click refilled a spell
   button the addon had already translated (`UpdateVisuals`, line 279). In the same entry every data field on the
   button was still clean. The fill was clean up to line 107 and tainted by line 279.
5. In those lines the only thing the fill reads that this addon changed is the button's three FontStrings:
   `TrimTextSpace` (lines 163 to 178) calls `GetText`, `GetStringHeight` and `GetLineHeight` on the spell name,
   subtext and level line. The addon wrote Japanese and its bundled font into the subtext and level line. A second
   entry showed the page layout (`ApplyLayout`) running tainted right after it measured the search-result headers
   the addon had translated.

Removing every write into the spell buttons and the page's headers removed the block. The same session that had
blocked every time (new rogue, learn Stealth, open the spellbook, switch tab, hover, stealth, attack) then logged no
tainted write, no tainted field and no block.

A second finding came on the way: with the client setting `taintLog` at 1, every method this addon (or a one-line
`/run`) post-hooks with `hooksecurefunc` fails with "attempt to call a nil value" when Blizzard's own code calls
it. Flipped live, five times, with and without the addon: 1 errors, 0 does not. The client never wrote a
`taint.log`. So `taintLog` is no tool on Forever and was never the cause of the blocked bars.

## Decision

1. **Nothing of this addon writes into a FontString that Blizzard measures on a path that ends in a protected
   call.** On such a FontString, text and font written by this addon come back tainted to the code that measures
   them (`GetText`, `GetStringHeight`, `GetLineHeight`, a layout frame's `Layout`). Whatever that code writes next
   carries the taint until a protected call refuses it, often much later and in combat.
2. **The spellbook's page is left as the client writes it.** No spell subtext ("Rank 1", "Passive", profession
   ranks), no level line ("Level 20", "Learn from trainer"), no flyout group name and no search-result header is
   written, and neither is the page number: the paging controls' `Layout` measures it in the same pass that refills
   the items on a page turn or a new spell (`blizzard_pagingcontrols.lua:110-127`, `blizzard_pagedcontentframe.lua:
   88-96, 156-160`). The spellbook's search preview stays English too. The window title, search placeholder and
   settings menu stay translated; none of them is measured on that path.
3. **Nothing of this addon runs inside the spellbook's own passes.** The title is followed by `UI/TextWatch` (read
   once a frame from the addon's own frame), not by a post-hook on `UpdateFrameTitle`. The search preview's hooks
   are placed on the talent and Legacy trees only, never on the spellbook's.
4. **A taint watch is always on** (`UI/TaintWatch`, [Diagnostics](../systems/diagnostics.md)): a check every 2
   seconds on the fields the bar layout reads, a stack from each of their writers when the value comes out tainted,
   a sweep of the bars' other fields, the last 60 game events with every finding, a stack on every block and a
   tainted-field scan after the first block of a session, once combat is over (also `/wfj taint`). It only reads; its cost is a few dozen
   checks every 2 seconds.
5. **`taintLog` is never used on Forever.** Not in the in-game checklists, not to debug. The taint watch replaces it.

## Consequences

- The spellbook's spell subtexts, level lines, flyout names and search-result headers stay English. Spell names
  were always English; spell tooltips are a separate path and stay Japanese.
- Getting those lines back would mean drawing the addon's own FontStrings over Blizzard's instead of writing into
  them. That needs its own in-game proof with the taint watch before it ships.
- Any other surface may hide the same trap: a FontString the addon writes that Blizzard measures on the way to a
  protected call. The taint watch shows it the first time a block happens: the stack of the tainted write and
  the field it went through. The fix is the same: stop writing into that FontString.
- A block is now traced, not guessed: the problem log holds the block's stack, the first field that turned
  tainted, its writer's stack and the events before it ([Diagnostics → Tracing a blocked action](../systems/diagnostics.md#tracing-a-blocked-action)).

## Update: the quest list beside the world map

The same trap was found in the quest list beside the world map (Forever 1.60.1.70862). Every map update, opening the
map with its key included, runs `QuestLogQuests_Update`, which measures the list's rows, and in the same pass places
the map's quest pins (`AcquirePin` → `SetPassThroughButtons`, protected in combat). With the list's titles in
Japanese, opening the map in combat was blocked under this addon's name every time. The maintainer narrowed it in
game by leaving one surface at a time untouched in combat: with only the list (`questmap.list`, `questmap.listlabels`)
left alone, the map opened in combat with no block every time, tracker title clicks before the fight included.

The list now writes nothing while the player is in combat: `QuestMap.onListUpdate` forgets the list's records and
returns, so the rows keep the client's English and font. When combat ends (`PLAYER_REGEN_ENABLED`) and the map is
still open, `QuestMap.onCombatEnded` runs the list pass again and the Japanese comes back. Out of combat the list is
Japanese as before; the protected call is only refused in combat. The details pane, the window title, the legend, the
map pins' tooltips and the tracker were left translated in combat during that narrowing and caused no block.

## Update: spell names drawn over the spellbook's own (an experiment, to be confirmed by a combat run)

With Japanese names on, the spellbook shows each spell's name in Japanese again, the way the Consequences above
describe: the addon draws its own FontString over the game's name instead of writing into it (`UI/SpellBookNames`).
The names were the first thing the addon drew on the spellbook's page; the words around them follow in the next
section. It is believed not to touch what the game measures,
for these reasons, each read from the client's code (1.60.1.71037). It is not proven in game yet.

- **The label is the addon's.** It is a FontString on a frame the addon creates. That frame is a child of
  `PlayerSpellsFrame.SpellBookFrame` so that it is shown and hidden with the book, and it is anchored to the game's
  name. It is no child or region of a spell item or of the item's `TextContainer`, whose layout walks every child
  and region (`blizzard_sharedxml/layoutframe.lua:58-62, 468-470, 488-511`).
- **The game's name keeps what the game measures.** Its text, font, size, colour, anchors and shown state are never
  written, so `TrimTextSpace` (`blizzard_spellbookitem.lua:163-171`) reads back exactly what the game wrote.
- **One property is changed: the name's alpha, set to 0** so the English does not show through. The item's own
  code writes that alpha at each refill (`blizzard_spellbookitem.lua:227` for a spell not learned, 0.6 from
  `blizzard_spellbookitem.xml:48`; `:254` otherwise, 1). Nothing reads it back: there is no `GetAlpha` call in
  `blizzard_playerspells/spellbook`, `blizzard_playerspells/camelot/spellbook` or `blizzard_pagedcontent`, and the
  layout frames read a child's `IsShown` and rect only (`layoutframe.lua:38, 455-466`). Because the game writes it
  again at each refill, the addon reads it once a frame, remembers the value the game wrote, sets 0 again and gives
  its own label the game's value, so a spell not learned is dimmed as before.
- **Nothing runs inside the spellbook's passes.** No hook on a spellbook method, no script on a spellbook frame.
  The addon's frame reads `PagedSpellsFrame.frames` and each name's text from its own `OnUpdate`, after the game's
  pass has ended, as `UI/TextWatch` does. The findings above put the cause in writes of text and font; reading
  `GetText` from the addon's frame (the window title, since then) has caused no block.
- **Everything is put back.** With names off, translation off, the reveal key held, a spell with no Japanese, an
  item that left the page, or the book closed (the addon's frame's own `OnHide`), the label is hidden and the name
  gets the alpha the game last wrote.
- **In combat.** No frame of the spellbook, the paged content or the flyout button is protected, and a region's
  `SetAlpha` is not a protected function (`simpleregionapidocumentation.lua:122-131`), so the same pass runs in
  combat. Should an item or its text container report itself protected in combat, nothing is written on it until
  combat ends.

What the code cannot show is whether a property this addon set on a FontString leaves the FontString's other
answers (`GetText`, `GetStringHeight`) clean for the game. Text and font did not; alpha is expected to, because
nothing the game reads depends on it. One play session decides: the problem log gets a `spellbooknames` entry the
first time the labels show, the taint watch's event list gets a line for each alpha write, and any block naming this
addon is recorded as before ([Testing](../testing/strategy.md), the spellbook names check). If a block shows up,
the experiment is removed (the list is at the end of the next section).

### The words around the names: subtext, level line, headers, page number

The maintainer ran the names in game: they show in Japanese in the right place and colour, and the problem log held
no blocked action under the addon's name. The same module now covers the other English on that page the same way:
the addon's own label over the game's text, alpha 0 on the game's text and nothing else, from the addon's own frame.
These are the texts whose Japanese, written into them, caused the block this record is about. Each was read in the
client's code (1.60.1.71037) before it was built.

| Text | The FontString and who writes it | Who writes or reads its alpha | Protected |
|---|---|---|---|
| The line under a name ("Rank 1", "Passive", "Racial") and the level line ("Level 20", "See your trainer") | `TextContainer.SubName` and `TextContainer.RequiredLevel` (`blizzard_spellbookitem.xml:81, 88`), written by `UpdateVisuals` and `UpdateSubName` (`blizzard_spellbookitem.lua:190, 252, 262, 295-300`) and measured by `TrimTextSpace` (`:163-171`), which also hides an empty one | The item writes it at each refill, like the name's (`:228-229`, `:255-256`), so the addon reads it every frame and sets 0 again. Nothing reads it | No: the same item and container as the name |
| A section header | `Text` of a `SpellBookHeaderTemplate` frame (`spellbook/blizzard_spellbooktemplates.xml:5-17`), written by `SpellBookHeaderMixin:Init` (`blizzard_spellbooktemplates.lua:3-7`). The header's backplate is anchored to it (`.xml:30`), and the page's grid lays the header frame out by its size | Nobody writes it, nobody reads it | No: the template has no `protected` and inherits only a size template (`camelot/spellbook/blizzard_spellbooktemplates.xml:14-16`) |
| The page number | `PagingControls.PageText` (`blizzard_pagedcontent/blizzard_pagingcontrols.xml:20-25, 54-66`; the spellbook's controls, `spellbook/blizzard_spellbookframe.xml:143-154`), written by `UpdateControls`, which then runs the controls' `Layout` over the text's rect (`blizzard_pagingcontrols.lua:110-127`) | The game writes the controls frame's alpha (`:116`), never the text's. Nothing reads either | No: `PagingControlsHorizontalTemplate` has no `protected` and no secure template |

For all three, the searches behind the names hold: no `GetAlpha` or `GetEffectiveAlpha` call in
`blizzard_playerspells/spellbook`, `blizzard_playerspells/camelot/spellbook`, `blizzard_pagedcontent` or
`blizzard_sharedxml/layoutframe.lua`; the layout frames take a child by `IsShown` and its rect
(`layoutframe.lua:38`); and a region's `SetAlpha` is not a protected function
(`simpleregionapidocumentation.lua:122-131`).

Where the Japanese comes from:

- **Subtext and level line** are interface words, from the dictionary, restricted to the lines a spellbook shows
  (`SPELL_PASSIVE`, `TOOLTIP_TALENT_RANK_CURRENT_ONLY`, `RANK`, the profession ranks, `BATTLE_PET_SUMMON` and the
  `SpellSubtext:` rows; `SPELLBOOK_AVAILABLE_AT`, `SPELLBOOK_TRAINABLE`, `BOOSTED_CHAR_SPELL_TEMPLOCK`). They show
  whenever translation is on, whatever the names setting says. A subtext with no line (a pet family, a form's name)
  keeps the game's text, visible.
- **Headers.** On Forever each skill line is a tab with one header, the skill line's name
  (`blizzard_spellbookcategory.lua:76-80, 377`); the pet book's is "Pet" (`:324`), the outfits' "Transmogrify"
  (`:487`), and a search groups its results under the `SPELLBOOK_SEARCH_HEADER_*` words
  (`blizzard_spellbooksearch.lua:5-32, 251`). "General", "Pet", "Transmogrify" and the search groups are dictionary
  words ("General" takes the word of `STAT_CATEGORY_GENERAL`). Any other header is a skill line's name: it shows
  the name list's Japanese while Japanese names are on, and a name with no line there stays English.
- **Page number.** The dictionary's `PAGE_NUMBER_WITH_MAX` (or `PAGE_NUMBER`), the templates the controls format
  with (`blizzard_pagingcontrols.xml:41-42`), with the numbers taken from the game's live text. Its label keeps the
  right edge and middle line of the game's text, which sits against the arrows.

The cost stays bounded: nothing runs while the book is closed, and a pass over an unchanged page compares each
text with the one its label was made from and looks nothing up.

The first-pass problem log entry now counts the labels of each kind (`names`, `subtexts`, `levels`, `headers`,
`pages`). The same play session decides, with one more thing to watch: the subtext and level line are what the
block was traced to, so a block after this change and none before it points at them.

Taking it out:

- **Only the words** (names stay): in `UI/SpellBookNames.lua`, delete the block between the two ruled comment
  lines ("the words around the names" to "end of the words") and, in `SpellBookNames.tick`, the two `words(...)`
  lines with the `elseif` between them and the `pageNumber(paged)` line; in its spec, delete the second `describe`;
  in `pipeline/name_surfaces.txt`, delete its header line and its subtext line.
- **The whole experiment:** `UI/SpellBookNames.lua`, its spec, its line in the TOC, in `tests/python/test_toc_check.py`,
  in `tests/python/test_forbidden_calls.py` and in `tests/lua/spec/addon_load_spec.lua`, its step in `Main.lua`, and
  its line in `pipeline/name_surfaces.txt`.
