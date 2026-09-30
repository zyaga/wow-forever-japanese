# ADR-002: The addon never ships or shows stored English

- **Status:** Proposed
- **Date:** 2026-09-13

## Context
A translation addon has two English texts available: the one it was translated from (frozen at translation time) and the one the game client is displaying right now. When Blizzard edits a quest, they diverge. The predecessors kept no English at all and simply overwrote frames, so a player could not see the current English without disabling the addon.

## Decision
**Live English is the only English.** The addon ships Japanese values and source hashes, never English text. Holding the modifier key reveals the text the client itself rendered into the frame (captured at hook time from the frame, in memory, for that display only). A `missing` or `rejected` entry leaves the frame untouched. One mechanism ("put back what the client wrote") serves both the modifier and the fallback.

## Consequences
- The kobold case (English changed from 10 to 8, Japanese still says 10) is self-correcting for the player: stale marker, hold the modifier, read the truth.
- The addon's data files shrink (no English), and there is nothing to keep in sync with Blizzard's text.
- Every UI surface must be built as *capture original → apply Japanese → restore original*, so the restore path exists for every translated element. This constrains the UI design (see `architecture/addon-modules.md`, the Surface mechanism).
- Tooltips, which the client re-renders rather than the addon editing in place, need a re-render trigger on modifier change rather than a restore.

## Alternatives considered
- **Ship stored English and toggle between the two stored texts**: shows outdated English after a patch; doubles data size.
- **"Show both" mode**: rejected for screen space.
