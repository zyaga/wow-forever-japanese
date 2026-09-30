# ADR-026: A blank archive-entry header is unwritten, not wrong: verify the content by its content key

- **Status:** Accepted. Implemented in `pipeline/wfj/io/casc.py` (`LocalArchive.read_blob`, `LocalArchive.read_file`, `self._unverified`), with tests in `tests/python/test_casc_local.py` and `tests/python/casc_fixture.py` (`build(…, blank_headers=…)`).
- **Date:** 2026-09-17

## Context

Every `data.NNN` entry in a local CASC archive begins with a 30-byte header whose first 16 bytes repeat the entry's encoded key, reversed. Since [ADR-021](021-client-tables-from-the-local-archive.md), `io/casc.py` has checked it: the index says "this ekey is at this offset for this many bytes", and the header check asserted that the bytes there really are that ekey's. On Classic Era 1.15.9.69722 it always held.

On the Forever beta client (1.60.1.69893) it does not. The client **leaves the header zeroed** and writes the BLTE payload at +30 as normal. Read byte for byte, `data.054@724649371`:

```
00000000: 0000 0000 0000 0000 0000 0000 0000 0000
00000010: 0000 0000 0000 0000 0000 0000 0000 424c   ← BLTE at +30, exactly where it belongs
00000020: 5445 0000 26c4 0f00 ...
```

The data is present and correct. The reader refused it.

What that cost was not a failed read; it was a wrong conclusion. The first survey of the Forever client took `data.019@…: header names key 0000…` for an install-on-demand client that had not finished downloading, and concluded that most interface files were not downloaded yet. That was false, and the download it was waiting for was never coming. The real "not downloaded" condition is a different one: an ekey absent from the local index, and it was never raised here.

The forces:

- **No guessing at the bytes** ([principle 9](../architecture/principles.md#9-claims-about-the-client-need-a-source)). Dropping the check and reading whatever the index points at is not acceptable on its own; something has to prove the bytes are the right ones.
- **A blank field and a wrong field are not the same claim.** Zeros are what an *unwritten* field looks like. A header naming a *different* key is a real contradiction between the index and the archive.
- **There is a stronger check available.** A content key **is** the MD5 of the file's content. Hashing the decoded bytes and comparing proves what the header field was only ever standing in for.
- **It cannot be applied everywhere.** An encrypted BLTE frame is returned zero-filled (so the offsets of everything after it hold), and zero-filled bytes cannot hash to the original. `ItemSparse` and `Spell` carry 9 and 11 encrypted frames on this build.

## Decision

**1. A blank entry header is trusted; a header naming a different key still raises.**

`read_blob` reads the 16-byte field, and only checks it when it is non-zero:

- **all zero** → the client did not write it. Trust the index, take the payload at +30, and record the ekey in `self._unverified`.
- **non-zero and not this ekey** → unchanged: `CascError` naming both keys.

**2. For an entry read that way, the decoded bytes are verified against their content key.**

`read_file` hashes the assembled content and compares it to the `ckey` the root gave for that FileDataID. A mismatch is `CascError`: *"FileDataID N: content hashes to X, but its content key is Y: the index pointed at the wrong bytes"*.

**3. The content check is skipped for a file with encrypted frames, and only for those.** `read_file` already returns the zero-filled ranges; when that list is non-empty the hash cannot match and is not taken. Verified on the live client: `md5 == ckey` holds for `QuestLogFrame.lua` (0 gaps) and cannot for `ItemSparse` / `Spell`.

**4. The change is a strict widening.** Every consumer was checked: `io/client_tables.py`, `dev/client_tables.py`, `dev/client_ui.py`, `dev/cut_db2_fixture.py`, and the tests `test_casc_local.py`, `test_client_tables.py`, `test_client_tables_install.py`, `test_dbcache.py`, `casc_fixture.py`. Every one reaches `read_blob` through `read_ekey` / `read_file`. An entry that read before reads identically (`_unverified` stays empty, no hash is taken); an entry that raised before may now succeed. No signature changed. `casc_fixture.build()` gained `blank_headers=False`, which leaves every existing caller untouched.

## Consequences

- **The Forever client's data was on disk all along, and now reads.** 4,042 files extract from a 7,706-path candidate list; `Spell` 31,767 rows, `SpellName` 31,767, `GlobalStrings` 27,262 (+3 from the hotfix cache), `ItemSubClass` 100 on that build. The client's own TOCs became readable, which is how the `camelot` game type was found (see [the research doc](../research/2026-09-17-forever-client-differences.md#the-headline-finding-forevers-game-type-is-camelot)).
- **The check got stronger where it is applied.** A content key covers the whole file; the header field covered 9 bytes of a key. `test_a_blank_header_over_the_wrong_bytes_is_caught_by_the_content_key` pins that: one byte of stored content changed, same length so every index offset still holds, and the read fails.
- **`ItemSparse`, `QuestV2`, `SpellItemEnchantment` and `ItemEffect` now stop at a different, correct gate.** Their DB2 layout hash changed on this build, so `client_tables` refuses to apply a column map verified against another layout rather than guess column positions (ADR-021). Re-verifying those maps is [ADR-027](027-column-maps-verified-per-build.md). This is the failure that should have been visible from the start.
- **A small number of `Spell` / `SpellName` rows stay unreadable**: 5 encrypted sections of 16–275 records, keys we do not hold. A real limit, and nothing in them can show in game before release.
- **A file with encrypted frames is read on the index's word alone** on a blank-header client. That is the one place this ADR relaxes without replacing. The frame checksums BLTE carries per chunk still apply to every unencrypted chunk in it.
- **Cost: one MD5 per blank-header file read.** Not taken at all on a client that writes its headers.
- **The lesson generalises past CASC.** An error message from our own reader is not a measurement of the client. A survey's worth of conclusions rested on one until the bytes behind it were checked.

## Alternatives considered

- **Keep failing and wait for the client to finish downloading.** Rejected because there was nothing to wait for: the bytes were already on disk, so the wait would never have ended and the beta-day harvest would have been blocked on a fiction.
- **Drop the header check entirely, with no replacement.** Rejected: that reads whatever the index points at and asserts nothing about it. The check is worth keeping; it just needed a better instrument than a field the client may not write.
- **Verify every read's MD5 unconditionally.** Tempting, and rejected twice over. A file with encrypted frames is zero-filled in those ranges and *cannot* hash to its content key, so the check would fail on exactly the tables we most need (`ItemSparse`, `Spell`); and it would pay an MD5 per read on Classic Era, where the header is written and the condition it guards has never once occurred.
- **Detect the client and branch on the build.** Rejected for the same reason [ADR-025](025-guarded-surface-init-and-runtime-tooltip-path.md) rejected it on the addon side: it asserts a fact about a build rather than asking the data a question, and it goes stale on the next one. A blank header is a property of the entry in front of us, and that is what the code reads.
- **Treat a blank header as "not downloaded" but keep going.** Rejected as the worst of both: it would keep the false conclusion while silently returning bytes anyway.

## Related

- [ADR-021: Client tables from the local archive](021-client-tables-from-the-local-archive.md): the reader this corrects, and the layout-hash gate the newly-readable tables now hit
- [ADR-025: Guarded surface init and a runtime-chosen tooltip hook path](025-guarded-surface-init-and-runtime-tooltip-path.md): the same rule about not branching on a build number
- [What the Forever client changed under the addon's surfaces](../research/2026-09-17-forever-client-differences.md): [C5](../research/2026-09-17-forever-client-differences.md#c5-the-client-archive-was-never-sparse), the survey claim this withdrew
- [Pipeline](../systems/pipeline.md) · [Local setup](../operations/local-setup.md) · [Testing strategy](../testing/strategy.md)
- Implementation: `pipeline/wfj/io/casc.py`
