# ADR-005: One text primitive (normalize_v1 + Hash32x2) for gossip keys, source hashes, and collector fingerprints

- **Status:** Accepted
- **Date:** 2026-09-13

## Context
Gossip text (the NPC talk window) exposes no ID to addons; source hashes must detect changed English; the collector must decide "known / changed / unknown" without shipped English. All three need the same thing: a fingerprint of normalized English computed identically in Python (pipeline) and Lua 5.1 (client). FNV-1a-32 was considered and fails on three counts: (a) 32 bits gives a ~1.7–5 % birthday-collision chance at 12–20 k gossip lines, and a collision silently shows the wrong sentence, (b) FNV's multiplier (16777619) pushes intermediates past 2⁵³ so a double-based Lua twin diverges, and (c) although WoW's Lua has shipped the `bit` library since 1.9, a primitive this load-bearing should not depend on it.

## Decision
**One primitive, one spec, two implementations, one vector file.**
- `normalize_v1(text)`: Unicode NFC **on the repo side only**; the client cannot compose, so the contract is "identical output for NFC input" (WoW enUS text is NFC; a decomposed live line would miss its key and fall back to English, which the collector will surface); strip WoW markup (`|cXXXXXXXX…|r`, `|T…|t`, `|H…|h<label>|h` → label, `|n` → newline); `$B`/`$b` → newline; fold full-width digits to ASCII; map Blizzard placeholders `$N/$n`→`{name}`, `$C/$c`→`{class}`, `$R/$r`→`{race}`, `$G…:…;`→ first branch; **client side only**, replace the player's actual name/class/race by the same placeholders using whole-word (ASCII-letter boundaries), exact-case matching, tokens of at least 3 **code points**; collapse all runs of **ASCII** whitespace (incl. newlines) to one space; strip ASCII spaces at both ends (Unicode whitespace such as U+3000/U+00A0 is preserved, so both implementations agree byte for byte).
- `Hash32x2(bytes)`: two polynomial rolls over the UTF-8 bytes, `h1 = (h1*131 + b) mod 4294967291`, `h2 = (h2*8161 + b) mod 4294967279`; key = `"%08x%08x"`. Every intermediate < 2⁴⁵, exact in IEEE doubles; Lua's floor-`%` equals Python's for non-negative operands; no bitwise ops.
- Gossip key = `Hash32x2(normalize_v1(live English line))`. Source hash (per field) = same over the field's English. Collector fingerprint = same. The generated Lua carries the first 32 bits per field (`h1`), enough to detect change; `data/` keeps all 64.
- `vectors/hash_vectors.jsonl` (NFC input only) covers ASCII, Japanese, colour/texture/link markup, `|n`, `$B`, the three placeholders in both cases, a `$G` gender branch, full-width digits, ASCII and Unicode whitespace at edges and interior, empty string, a 4 KB string, and client-side name/class/race substitution including substring, short-token, and non-ASCII names. A generated Lua twin (`hash_vectors.lua`) is drift-guarded against the JSONL. Both suites assert every case; `wfj validate` additionally fails the build on any two distinct normalized strings sharing a key.
- Identical English lines share one key and one Japanese line, by design. The NPC ID, where available, is stored alongside for review tooling but is never part of the key.

## Consequences
- Same English ⇒ same Japanese everywhere; short generic options ("Continue") collide across NPCs on purpose; `wfj stats` lists the highest-occurrence keys so they are reviewed first.
- Player-name substitution happens only where a player name exists (the client); the pipeline sees placeholders.
- 64-bit keys as Lua string table keys cost ~0.5 MB at 12 k lines; accepted for one key type across both languages.
- **In the addon**, the gossip key is `Collector.key`: the collector's normalization in Blizzard's tokens, which also replaces the lowercase class and race, so the render key and the stored hash are one value. NPC ids are stored as `n` in the collector dump and as `npcs` on `data/english/gossip` lines, and the `wfj stats` blast radius lists collected keys by NPC count (top 20). See [ADR-017](017-gossip-surface.md). Gender alias rows and short-name candidates: [ADR-024](024-gender-variants-and-short-name-candidates.md).

## Alternatives considered
- **FNV-1a-32**: collision risk and double-precision divergence (above).
- **`bit.bxor`-based hashes**: available, but the arithmetic form is exact without it and one fewer assumption about the Forever client.
- **Key by raw English string**: ships the corpus as table keys (ADR-002) and is fragile to whitespace/substitutions.
- **Key by NPC ID + option index**: options reorder with quest state; greetings vary by NPC state.
