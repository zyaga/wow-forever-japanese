# ADR-051: A hidden tooltip pass translates the client's own data, and remembers nothing

- **Status:** Accepted
- **Date:** 2026-10-02
- **Relates to:** [ADR-010](010-tooltip-in-place-run-replacement.md) (the readable pass), [Client limits](../architecture/client-limits.md)

## Context

In combat the Forever client writes an action button's tooltip from secret values: every row's text and colour
is sealed, and so are the cooldown's numbers. The readable pass (ADR-010) reads the rows to find the description
and to check the live English against the shipped hash, so it cannot run. What stays readable is the spell or
item id (the tooltip data's id, else the owner's action slot), each row's kind, and the client's own tooltip data
for that id (`C_TooltipInfo.GetSpellByID`, whose rows are plain except its cooldown row). A buff tooltip in
combat has nothing readable at all: its aura id, spell, icon and rows are secret, and the aura APIs refuse a
secret id from an addon.

Two earlier answers were tried and rejected: remembering what a readable pass had written and writing it back on
the next hidden pass (wrong the moment the rows move, blind to a buff first hovered in combat), and modelling the
buff bar to guess which buff a button holds from the player's casts (a guess, confirmed or not, shown as fact).
Both also learnt the client's time rounding from readable lines and stored it.

## Decision

1. **The client's data by position.** A hidden pass asks the client for the spell's or item's own tooltip data,
   matches the frame's rows to the data's one to one from the top (rows the frame has past the data, other addons'
   appended lines, are left alone; when both sides type a description row and the frame's sits lower, the rows
   between are the frame's own), translates each readable data row exactly as a readable pass would, and writes the
   Japanese onto the frame's rows. A data row the client hides is the cooldown countdown.
2. **The client formats the countdown.** The countdown row is written by the client from its own hidden duration
   through a numeric rule formatter carrying one fixed rule, Blizzard's one-term `SecondsToTime` with rounding up,
   and the UI dictionary's Japanese. Nothing is measured or learnt.
3. **Nothing is remembered.** A hidden pass keeps no record and nothing between passes; a row that cannot be
   placed is left as the client wrote it. The frame's records from the last readable pass are let go without
   reading the rows (`Render.discard`).
4. **A buff tooltip in combat stays English.** No addon can identify the buff, so nothing is guessed; the ordinary
   path renders it again the moment its rows are readable. The limit is written down for players and developers.
5. **The trace is exhaustive.** A hidden pass's trace entry names every data row with its kind and whether it is
   hidden, the row map, and the countdown's duration object, so a wrong assumption shows in one paste.

## Consequences

- A spell on the action bar stays Japanese in combat, countdown included; a buff icon's tooltip does not.
- The rounding of a boundary second may differ from the client's compiled tooltip; a readable countdown never
  comes through this path, so the rule only ever writes a line the addon could not read anyway.
- The hidden pass depends on the client's data rows lining up with the frame's; a client change that breaks the
  line-up leaves rows English and says so in the trace, never a wrong row.

## Alternatives considered

- **Write back the last readable pass** (rejected: wrong rows after a layout change, nothing for a first hover in
  combat, and a memory the toggle contract cannot see through).
- **Model the buff bar from the player's casts** (rejected: a guess; the maintainer ruled out any learning or
  remembering across combat).
- **A rule formatter keyed by spell id as a lookup table** (not possible: the formatter takes no secret number
  from an addon, and no client object carries a spell id to a formatter).
