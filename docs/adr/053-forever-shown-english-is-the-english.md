# ADR-053: The English the Forever client shows is the English

- **Status:** Accepted
- **Date:** 2026-10-02
- **Amends:** [ADR-013](013-collector-english.md) decision 3 (additive import, not yet consulted)

## Context

[ADR-013](013-collector-english.md) made the collector import additive: a dump added English where none existed,
replaced only earlier `collector@` lines, and listed every disagreement with pfQuest, VMaNGOS or the client tables
for a person to decide. `check`, `validate` and `stats` skipped collector English entirely
(`UNCONSULTED_SOURCES`), so a dump earned nothing until a re-check policy existed.

That was written when the only English for most quest text was a stand-in: pfQuest, the VMaNGOS world database,
or an older client such as Classic Era. Forever is the only target ([ADR-034](034-forever-is-the-only-target.md)),
and Forever rewords some of its quests. A quest's turn-in (completion) and progress text exist only in what the
server sends at the NPC: no client table or quest cache holds them, so a stand-in is the only offline English and
the collector is the only source of Forever's own version. Left as it was, a quest whose turn-in Forever reworded
kept the stand-in's hash forever, and every disagreement waited on a person who had no better source than the
client itself.

The collector records the player's class and race as `$C` / `$R` wherever the words occur. A druid recording
"young $R, a wise druid" writes "young $R, a wise $C": the text alone cannot tell a literal class word from a
token, and the saved file is shared by every character on the account.

## Decision

1. **A recorded line replaces a stand-in.** `wfj import english collector` (`run_collector` in
   `pipeline/wfj/cmd/import_english.py`) compares, per `(type, id, field)`, the dump's hash with the stored line.
   Absent → added; same hash → unchanged; another hash → replaced, when the stored line is an earlier collector
   line or a stand-in (VMaNGOS, pfQuest, a client of another game version).
2. **The same client's own files are kept.** A stored line read from the same client as the dump (its client
   tables, its quest cache: a `src` whose version shares major.minor with the dump's build, `_same_client`) is
   kept and listed as `differs from the client's own files (kept)`. The client's files carry the templates the
   recorded text was rendered from, so they stay the reference.
3. **Literal class and race words are put back, only the recorder's own.** A line holding `$C` / `$R` carries
   the recording character's class and race (`p = "Class|Race"`). When a recorded line replaces a stand-in, a
   `$C` (or `$c`) in the recorded text that lines up, word by word, with the recorder's own class in the stand-in
   takes that word back, and a `$R` the recorder's own race (`_restore_literals`). A different word there
   ("warrior" where a mage recorded `$C`) means the line follows the reader's class, so the token stays; an entry
   with no `p` gets nothing back. Re-importing compares the restored text, and a line an earlier import already
   gave a literal back is kept as it is, so a restored word survives re-imports.
4. **An older client's item or spell template is kept.** A stored item or spell line from another game version
   that holds `$` codes (`$o1`, `$d`) is never replaced by a recorded line, which has one player's numbers filled
   in; it is listed under differs.
5. **`check` consults collector English for quest and gossip.** `CONSULTED_COLLECTOR_TYPES = ("quest", "gossip")`
   in `pipeline/wfj/cmd/check.py`: for these types collector lines build scopes like any other source, so their
   hashes become the lines' English. Item and spell collector English stays unconsulted: it is recorded with the
   numbers filled in, while the client tables hold the templates the alignment check needs.
6. **The live check tries race-only and class-only candidates.** `candidates` in `Core/Collector.lua` adds a
   fingerprint with only the race replaced and one with only the class replaced, so a line that says one literally
   and the other as a token is known.

## Consequences

- Quests whose turn-in or progress text Forever reworded show the stale marker until someone sees the text in
  game and the dump is imported; after that the shipped hash is Forever's and the translation is checked against
  it.
- Importing a dump now changes what `check`, `validate` and `stats` see for quest and gossip lines. A dump is no
  longer a no-op for status: it is reviewed like any English import (`wfj stats --delta`).
- A transient or per-player variant of a line can replace a stand-in. The same player seeing the line again, or
  another dump, replaces it again; the client's own files are never replaced.
- `_restore_literals` puts back only one-for-one or one-for-two word swaps of alphabetic words, so a token the
  stand-in has as a token, or a reworded phrase around it, stays as recorded.
- Item and spell English still has no collector path into `check`; their reference stays the client tables.

## Alternatives considered

- **Keep the additive import and decide each disagreement by hand.** The person deciding has nothing better than
  the client's text; on Forever, the client is the truth.
- **Let collector English replace the client's own tables and quest cache too.** The tables hold templates and the
  cache holds Blizzard's text for the same build; a rendered line is a worse reference than either.
- **Consult collector item and spell English.** Those lines carry filled-in numbers, so the alignment check would
  compare against one player's values rather than the template.
- **Leave `$C` / `$R` as recorded.** A quest line with a literal class word would then mismatch for every player
  of another class.

## Related

- [ADR-013: Collector English](013-collector-english.md) · [ADR-017: Gossip surface](017-gossip-surface.md) ·
  [ADR-019: Quest English per field and the live check](019-quest-english-per-field-and-live-check.md) ·
  [ADR-034: Forever is the only target](034-forever-is-the-only-target.md) ·
  [ADR-050: English is additive](050-english-is-additive.md)
- [Collector](../systems/collector.md) · [Pipeline](../systems/pipeline.md) · [Data model](../architecture/data-model.md)
