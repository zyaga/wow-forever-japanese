# Lesson: The bundled font is refused on a fresh client launch

> Post-mortem from an in-game check on Classic Era 1.15.9.69722.

- **Date:** 2026-09-14

## What happened
On a fresh client launch (Exit Game, then start the client again, not `/reload`), the labels the addon translates at load showed Japanese text in the client's font instead of the bundled `ipagui.ttf`. This covers the window modules' `*.static` surfaces, the settings pages and the marker banner. They stayed that way for the whole session.

The client refused the font 237 times in all:
- **194 on the load-time labels:** friends.guild 55, mail 32, character 29, friends 28, honor 16, raid 6, bank 5, merchant 5, reputation 5, …
- **43 on settings-page and banner widgets.**

The sizes and flags passed to `SetFont` were valid. After `/reload` the count was 0, so a pass that starts from `/reload` does not show the problem.

## Timeline
1. Fresh launch. `FontString:SetFont(<bundled ipagui.ttf>, size, flags)` returns `false` for every widget touched during `ADDON_LOADED`.
2. `SurfaceState.apply` records the refused font as `appliedFont` anyway. Later syncs see "already applied" and never ask again.
3. First fix attempt: retry the refused fonts on a timer. With no window opened, 236 were still refused after 60 s.
4. Opening any window whose visible text asks for the bundled font made every pending font apply within ~15 s. On another launch the file took over 30 s.
5. With one visible, nearly transparent `あ` asking for the bundled font, every pending font applied on the first retry, 1 s after `PLAYER_ENTERING_WORLD`.

## Root cause
Two faults combined:
- **The client loads an addon font file lazily.** On a fresh launch it loads the file only when a visible FontString asks for it (verified in-game, step 5). Until then `SetFont` with that path returns `false`. The load-time labels sit on windows that are not open yet, so nothing visible asked for the file.
- **A refused `SetFont` was recorded as applied.** `SurfaceState.apply` set `appliedFont` without checking the result, so a transient refusal became permanent for the session. `Render.fontFailures` counted it, but nothing acted on the count.

## Fix
Details in [Addon modules](../architecture/addon-modules.md):
- **`SurfaceState.apply`** records no `appliedFont` when `SetFont` returns `false`. The new `SurfaceState.applyFont` retries only the font of an applied record whose widget still shows our text.
- **`Render`** keeps refused records in a weak `pendingFonts` table. `Render.retryFonts()` retries the font only: no policy resolve, no text write.
- **`Render` diagnostics:** `Render.pendingFonts()` and `Render.fontFailureSurfaces` for `/wfj debug`.
- **`UI/Font.lua`:** `Font.set` / `Font.retryPending` do the same for the addon's own widgets (settings pages, marker banner).
- **The probe:** `Font.startProbe` / `Font.stopProbe` show one visible, nearly transparent character that asks for the bundled font, which makes the client load the file.
- **`Main.lua` on `PLAYER_ENTERING_WORLD`:** retries once. If anything is still refused, it starts the probe and a 1 s `C_Timer.NewTicker` that retries until nothing is pending, then stops the probe. A 600-try safety stop ends it after 10 minutes.
- **`/wfj debug`** prints `font failures: N (M pending)` with per-surface detail. `/wfj debug fonts` shows the retry state and retries now.
- **Tests:** `surfacestate_spec`, `render_spec`, `addon_load_spec`, `slash_spec` ([Testing](../testing/strategy.md)).

## Prevention
- **Test a fresh launch, not only `/reload`.** After a `/reload` the same code saw 0 refusals, so load-time font behaviour can only be checked from a fresh launch. The in-game checklist now has a fresh-launch step: [Testing → checklist 15](../testing/strategy.md), where `/wfj debug fonts` must show `retry stopped · … 0 left` without opening any window.
- **Never record a refused `SetFont` as applied.** A widget call that returns a status is checked before state is updated; a `false` leaves the record retryable (`surfacestate_spec`).
- **Treat a non-zero failure counter as a bug to act on.** `/wfj debug` now names the surfaces and whether anything is still pending, so a count can be traced to widgets.

## Later observations
- **Forever, the tracker's "Quests" header.** On a Forever session `/wfj debug` reported one font failure on `questmap.trackerlabels` (`ui.trackerQuests`, size 14) with **0 pending**. This is the same fresh-launch refusal, not a new fault: the header is written in the tracker module's `OnLoad`, before the bundled font file is ready, so the load-time `SetFont` is refused; `Render.retryFonts` then applied it. The failure counter keeps counting a refusal the retry healed, so read it together with "pending". A busted spec pins this case: a refused `SetFont` on `ui.trackerQuests` at load, applied by `Render.retryFonts` (`questmap_objectives_spec.lua`).
