# Game-type gating in the Forever client's own TOC

> Six lines from the client's own `Interface/AddOns/Blizzard_UIPanels_Game/Blizzard_UIPanels_Game.toc` (build
> 1.60.1.69893), each carrying an `[AllowLoadGameType]` or `[ExcludeLoadGameType]` conditional, the mechanism in
> question. The line numbers are the file's own.

This is the evidence for the `camelot` claim in
[the research doc](../2026-09-17-forever-client-differences.md). Note what it does and does not prove: it
shows the client **gates files by game type** and that `camelot` is one of those types, and that the files
our missing surfaces live in are gated away from it. It is **not** a direct read of the running client's
active game type (no API was called for that). The inference rests on this gating plus the observed
works/absent split; see the caveat in the research doc.

> **Read these lines with `camelot` as a mainline-family type.** A line gated
> `[AllowLoadGameType mainline]` loads on Forever unless it also carries `[ExcludeLoadGameType camelot]`; lines 44–45
> (`[Family]\CharacterFrame.lua [AllowLoadGameType mainline] [ExcludeLoadGameType camelot]` beside
> `[Game]\CharacterFrame.lua [AllowLoadGameType camelot]`) only make sense that way. `[Family]` expands to `Mainline\`
> and `[Game]` to `Camelot\`. What never loads is a line gated only `classic`, `vanilla`, `tbc`, `wrath`, `cata` or
> `mists`. The same lines read identically at the same line numbers in build 1.60.1.69913. Evidence and the per-surface
> consequences: [the camelot re-target research](../2026-09-19-camelot-surface-retarget.md), finding 1.


```
6:## Dep: Blizzard_CharacterFrame [AllowLoadGameType classic]
27:[Family]\DressUpFrames.lua [AllowLoadGameType mainline]
28:[Game]\DressUpFramesOverrides.lua [AllowLoadGameType camelot]
32:[Family]\SpellBookFrame.lua [AllowLoadGameType classic]
44:[Family]\CharacterFrame.lua [AllowLoadGameType mainline] [ExcludeLoadGameType camelot]
45:[Game]\CharacterFrame.lua [AllowLoadGameType camelot]
```
