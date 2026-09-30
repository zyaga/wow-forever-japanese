# Verdicts, run 2: the probe asked with the window open

> Build 1.60.1.69893, interface 16001. 294 names asked. Inputs beside this file:
> `probe-answers-run2.lua` (the client's own SavedVariables, **as written, never edited**),
> `surface-manifest-run2.json`, `verdicts-run2.json`.

## Two readings, and why they differ

`verdicts-run2.json` is generated from the raw probe file and reads **rework 99 · unknown 79 · works 172**.
Ten surfaces were marked with `/wfjprobe <surface>`, but **guild and talents are gated at
character level 10** ("This feature becomes available at level 10."), so those two windows could not
have been open and their marks are **withdrawn**. Reading the same answers with those two marks removed
gives **rework 37 · unknown 141 · works 172**, the figure the research doc uses.

The raw file is committed unedited on purpose: the withdrawal is a judgement about the session, not a
correction to what the client answered, and doctoring evidence to match a conclusion is how a survey
stops being one.

Reproducing both readings from the committed files:

```python
from wfj.dev import client_surface as cs
manifest = json.load(open("surface-manifest-run2.json"))
raw      = open("probe-answers-run2.lua", encoding="utf-8").read()
answers  = cs.read_saved_variables(raw)
asked    = cs.asked_surfaces(raw)
cs.report(manifest, answers, None, asked)                    # as measured: rework 99
for s in ("guild", "talents"): asked.pop(s, None)            # the two level-10 windows
cs.report(manifest, answers, None, asked)                    # withdrawn:   rework 37
```

**Withdrawn:** guild (62 rework → unknown), talents (already unknown under the load-on-demand rule).

## Confirmed broken: every name asked with its window open and still absent

| surface | rework | works | unknown |
|---|---|---|---|
| questlog | 23 | 3 | 0 |
| spellbook | 7 | 1 | 4 |
| mail | 3 | 19 | 3 |
| honor | 2 | 0 | 2 |
| friends | 1 | 3 | 0 |
| skills | 1 | 0 | 2 |

**Totals (withdrawn reading):** rework 37 · unknown 141 · works 172

## Still unknown, and why

- **trainer, talents, raid**: their load-on-demand Blizzard addon never loaded in the session, so
  absence proves nothing (`loaded` in the probe file lists only Blizzard_TimeManager,
  Blizzard_GroupFinder_VanillaStyle, Blizzard_CombatLog, WoWForeverJapanese and WFJProbe).
- **guild**: level 10, as above.
- **tooltip**: scored unknown here because the surface was never marked, but it needs no probe: the
  live client took the data-processor path (`hook path: dataprocessor`), which is the answer.

## What it means

The per-name verdicts are not the real answer. Forever's game type is **camelot**, and
`Blizzard_UIPanels_Game.toc` gates each file with `[AllowLoadGameType …]`: the surfaces above point at
frames that never load on this client, rather than at frames that were renamed. See
[the camelot section](../2026-09-17-forever-client-differences.md) and
[the camelot re-target research](../2026-09-19-camelot-surface-retarget.md).
