# Lesson: three combat blocks on launch day, each from the addon running inside Blizzard's pass

> Post-mortem from launch day on Forever 1.60.1.70790. Decision: [ADR-069](../adr/069-unit-menus-and-edit-mode-stay-english.md). The pattern is [ADR-058](../adr/058-text-blizzard-measures-on-a-protected-path-stays-untouched.md)'s, met in three new places.

- **Date:** 2026-11-05

## What happened
The problem log held three blocks under this addon's name: a party frame right-click in combat (`CheckInteractDistance()`), leaving Edit Mode (`ClearTarget()`, out of combat) and a click on a tracked quest title in combat (`Button:SetPassThroughButtons()` on the map's quest pins). Each looked unrelated to translation: none of them is a line of text.

## Root cause
All three are one mechanism. Once addon code runs inside a Blizzard pass, the rest of that pass is tainted, and a protected call at its end is refused.

1. **Unit menus.** The menu runs an element's initializers and then its own final initializer in one pass. The addon added an initializer to every tagged menu. In a unit menu the final step asks each entry `IsEnabled`, and that calls `CheckInteractDistance`, protected in combat. No text was involved: running in the pass was enough.
2. **Edit Mode.** The addon wrote Japanese into Edit Mode's windows. Edit Mode lays those windows out by measuring their text, then moves the action bars and resets the target on exit.
3. **The quest list.** The addon resized the list's rows to fit Japanese and laid the list out again itself. The next list update measured those rows, ran tainted and stored the selected quest tainted. A later click on a tracked title read that value and focused the map, whose quest pins are protected in combat.

## How it was found
- The block stack names the reader, never the writer. The first guess for the third block (the tracker) was wrong.
- Probes, all in one build, settled it in four short sessions: a writer check on the tracker's `MarkDirty`, the clicked block's keys, the quest log's stored quest id, and a block-time scan deep enough to reach the tracker's blocks, the quest log and the quest cache. The tracker stayed clean; the quest log's stored id came out tainted on the first click.
- One experiment build with only the list relayout removed logged nothing on the same two-click test.

## Prevention
- **Never add code to a Blizzard pass that ends in a protected call**: a menu initializer, a hook that runs inside the pass, or text or a size that Blizzard measures in it. Menus whose entries ask a protected predicate (unit menus) stay English.
- **Never lay out a Blizzard list or window yourself.** Writing text into a row is one thing; resizing the row or calling the container's `Layout` puts the addon inside the next layout.
- **Probe every candidate at once.** Each in-game test costs the maintainer a session; one build that logs every writer on the path beats one probe per retest.
- `tests/python/test_protected_paths.py` keeps any Edit Mode frame, Edit Mode callout and unit menu tag out of the addon's code.
