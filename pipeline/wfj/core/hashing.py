"""Hash32x2: two 32-bit polynomial rolls, exact in IEEE doubles (ADR-005).

    h1 = (h1 * 131  + b) mod 4294967291   (2^32 - 5,  prime)
    h2 = (h2 * 8161 + b) mod 4294967279   (2^32 - 17, prime)

Largest intermediate: h2*8161 + 255 < 2^32 * 2^13 = 2^45 < 2^53, so the Lua 5.1 twin
(addon/WoWForeverJapanese/Core/Hash.lua) computes identical values with plain arithmetic
and no bitwise operators. key = "%08x%08x" % (h1, h2).
"""

from __future__ import annotations

M1, P1 = 131, 4294967291
M2, P2 = 8161, 4294967279
MAX_INTERMEDIATE = 2**45


def hash32x2(norm: str) -> tuple[int, int]:
    h1 = h2 = 0
    for b in norm.encode("utf-8"):
        h1 = (h1 * M1 + b) % P1
        h2 = (h2 * M2 + b) % P2
    return h1, h2


def key(norm: str) -> str:
    h1, h2 = hash32x2(norm)
    return f"{h1:08x}{h2:08x}"


def key_from_pair(h1: int, h2: int) -> str:
    return f"{h1:08x}{h2:08x}"
