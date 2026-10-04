# Diagnostics log

> The addon's own record of problems seen in game, kept so they can be read after a reload or a crash.

## Purpose
Some failures only show in a long play session: a hooked method that stops working, a protected call the client blocks, a surface whose setup failed. A blocked call is the hardest: the block shows only the Blizzard code that tripped, often minutes after this addon's taint reached it. The taint watch (`UI/TaintWatch.lua`) records where the taint came from. The client's error window shows them once and loses them on exit. `Core/Diag.lua` writes them to the addon's third SavedVariables table, `WFJ_Log`, so they can be read afterwards, and any module can add its own entries.

## What is recorded
| Kind | When | Fields |
|---|---|---|
| `session` | each load (login or `/reload`) | client build, addon version, the surfaces whose setup failed |
| `init` | each surface whose setup failed, at load or later (a load-on-demand window) | the surface, the error (300 characters at most) |
| `blocked` | the client's `ADDON_ACTION_BLOCKED` or `ADDON_ACTION_FORBIDDEN` naming this addon | the event, the protected function (`fn`), the call stack at the block (`stack`; the client fires the event inside the blocked call), the first Blizzard Lua line in it (`site`, also in the message, so one function blocked from two paths makes two entries), whether combat was on (`combat`) |
| `context` | after each block | the last 60 game events before it (`events`) |
| `turned` | the taint watch: a watched bar field (or any field on the action bars, `reason = bar sweep`) reads as tainted for the first time since it was last clean | the field, the addon that tainted it (`by`), `reason`, `combat`, `events` |
| `write` | the taint watch: a watched field's writer left the value tainted | the field and the first stack line in the message, `by`, `stack` (the writer's whole path), `combat`, `events` |
| `taint` | after the first block of a session, once combat is over, and on `/wfj taint` | every field under the bar, Edit Mode, tracker, tooltip and spellbook frames that reads as tainted, with the addon that did it (`fields`), the globals this addon tainted (`globals`), `checked` |
| `hook` | a method the addon post-hooked on one frame (`Diag.watch`) no longer reads as a function, or is another function than the hook the addon left there (`seen = replaced`) | frame, method, what it reads as, its type on the frame's own table and on what the frame inherits |
| `memory` | every 5 minutes | the Lua memory |

Every entry also carries the local time (`at`), seconds since the client started (`up`) and the Lua memory in KB (`memKB`). The same kind and message again in one session adds to that entry's count (`n`) and last time (`last`) instead of a new entry, so something repeating every few seconds never pushes the rest out. The log keeps 500 entries: over that, the oldest memory sample goes first, then the oldest problem, then the oldest session, and it never keeps more than 50 sessions.

A `hook` or `blocked` entry also prints one chat line, once per session, ending in "/wfj log shows it".

## The addon's own Lua errors
Forever hides Lua errors by default, so a player never sees an error in this addon's code. `Core/ErrorLog.lua` keeps them in the same table, under `WFJ_Log.errors`, for a bug report ([fix reports](fix-reports.md), "Bug and idea reports"; [ADR-057](../adr/057-catching-the-addons-own-lua-errors.md)).

- **How it catches them.** `Core/ErrorLog.lua` is the first file in the TOC, so it catches load errors in every other file. At load it reads the client's current error handler (`geterrorhandler`) and sets a wrapper (`seterrorhandler`). The wrapper records the error inside `pcall` and then always calls the previous handler with the same arguments, so the game's Lua error window, BugSack and other addons see every error as before. An error raised while recording is never recorded again.
- **Errors a setup step catches.** A setup step in `Main.lua` runs inside its own `pcall` (the step guard), so its error never reaches the handler. The guard hands it to `ErrorLog.recordCaught`, which keeps it the same way, from the message alone (no stack is left to read).
- **The stack.** `ErrorLog.stack` reads it the way the client's own handler (`Blizzard_ScriptErrors.lua`) does: the current callstack height less the error's. Because that level comes from the error's own height, the extra wrapper frame does not change what the client prints. A handler called directly, outside an error, has no error height and uses offset 0, as the client does. On a client without the height functions there is no stack, and the message alone decides. The wrapper's own `Core/ErrorLog.lua` frames are left out of the stored stack.
- **Only errors raised in this addon's files.** An error is kept only when it was raised in a file under `WoWForeverJapanese/`. The file that decides is the one the message names at its start (`path:line:` or `[string "..."]:line:`). For a message without one, it is the top Lua frame of the stack, skipping `[C]` frames, `(tail call)` and the wrapper's own frames. A path counts as ours when `ForeverJapanese/` (or `\`) follows `WoW` after a `/`, `\`, `@` or the start, or follows the client's front-truncated form, as in `...rface/AddOns/WoWForeverJapanese/UI/MinimapButton.lua:144:`. An error whose message names another addon's or Blizzard's file is not ours, even when this addon's code is lower in the stack. A `/run error("x")` typed in chat names `[string "..."]` and is not kept. A value the client marks as secret (`canaccessvalue`) is not read.
- **What is stored.** Each entry holds `msg` (500 bytes at most, cut on a UTF-8 boundary), `stack` (12 lines and 1,000 bytes at most), `n` (how often), `first` and `last` (local time) and `sent`. No local variables. The same error again adds to `n` and moves `last`. For matching, table, function, userdata and thread addresses in the message are blanked, so the same error raised on another table is one entry. A repeat of an error already sent starts over as a new one: `sent` is cleared, `n` is 1 and `first` restarts.
- **Cap.** 30 errors. Over that, the oldest sent error goes first. With none sent, the newest is dropped, so the first errors (most often the cause of the rest) are kept.
- **The player's name.** Written as `<name>` wherever it appears as a whole word in a message or stack, before the message is cut to length. A name that is a file name in a path (`/Main.lua`) is left alone, since the report needs the file. The scrub runs again at `PLAYER_ENTERING_WORLD` for an error caught before the name was known.
- **Before the log loads.** Errors caught before `WFJ_Log` loads are held in memory and merged when it loads: a repeat adds its count and keeps the later time, and an entry caught before the clock was set up gets the load time (the clock reads the time once the `compat` step has run; a time it still cannot read shows as `?` in a bug report). A saved entry that is not a table with a string message is dropped at load.
- **Chat line.** The first error stored in a session prints one line: `WFJ: the addon hit a Lua error. /wfj bug reports it.`
- **No setting.** Nothing turns capture on or off.

**Another error addon.** BugGrabber (the part of BugSack that catches errors) sets its own handler, never calls the one before it, and then makes `seterrorhandler` do nothing. `!BugGrabber` loads before this addon. With it present this addon's wrapper sees no errors. At `PLAYER_ENTERING_WORLD`, once every addon has loaded, `ErrorLog.checkOurs` compares the active handler with the wrapper. When they differ (and none of this addon's errors reached the wrapper this session), the report window's bug summary says another addon catches Lua errors and asks the player to paste this addon's errors from it. The addon never reads BugGrabber's store: that would be a dependency on another addon.

## The taint watch
`UI/TaintWatch.lua`, always on, read-only ([ADR-058](../adr/058-text-blizzard-measures-on-a-protected-path-stays-untouched.md)). The client's `issecurevariable(table, key)` tells whether a field was last written by tainted code, and by which addon; the watch asks it about the fields Blizzard's bar layout reads:

- **Watched fields:** `showAllButtons` on the twelve action bars, `snappedToFrame` on the bars and the XP bar containers, the totem bar's `inMainActionBarState`, the quest tracker's `topModulePadding`, and the globals `ON_BAR_HIGHLIGHT_MARKS` and `PET_ACTION_HIGHLIGHT_MARKS`. Checked every 2 seconds; the first time one turns tainted it is a `turned` entry.
- **Their writers:** a post-hook on `SetShowGrid`, `SetSnappedToFrame` / `ClearFrameSnap`, `MainActionBarStateOverridden`, `UpdateTopPadding`, the highlight-mark functions and `PetActionBar`'s mark methods. The hook only reads; when the value comes out tainted it is a `write` entry with the stack.
- **Bar sweep:** every 10 seconds out of combat, any field on the action bars that newly reads as tainted, for fields not on the list.
- **Events:** the last 60 game events (with `ShowUIPanel` / `HideUIPanel`), frequent ones left out, saved with every entry above and every block.
- **Scan:** after the first block of a session, once combat is over (it walks every global, too heavy for a fight; a tainted value stays tainted until it is rewritten), and on `/wfj taint`.

Its cost is a few dozen `issecurevariable` calls every 2 seconds and one table write per game event. Nothing turns it off.

## Tracing a blocked action
1. **Read the block.** `/reload`, then read `WFJ_Log` (or `/wfj log 30`). The `blocked` entry's stack is the Blizzard path that tripped: the reader, never the cause.
2. **Find the first taint.** The earliest `turned` and `write` entries of that session, before the block, name the field and the writer's stack. A `write` stack that runs through this addon's file names the line to fix.
3. **If the stack is all Blizzard code,** the taint came in through something that code read just before writing. The `taint` scan lists what was tainted; add a probe on the writer of that value (a post-hook that logs `debugstack()` when the value comes out tainted, as `TaintWatch.wrote` does) and repeat one level up. A field that is clean at one line and tainted a few lines later points at what the code read in between (the spellbook case: FontString measurements, [ADR-058](../adr/058-text-blizzard-measures-on-a-protected-path-stays-untouched.md)).
4. **Prove the fix in game** with the same steps that blocked, and read the log: no `turned`, no `write`, no `blocked`.

Never turn on the client's `taintLog` on Forever: it makes every post-hooked method fail when Blizzard calls it ([Client limits](../architecture/client-limits.md)).

## Adding to it
`WFJ.Diag.log(kind, message, fields)` from any module. `fields` holds strings, numbers and booleans; anything else is stored as its type name. `WFJ.Diag.watch(frame, method, label)` after a `hooksecurefunc` on a single frame adds that hook to the checks (every 5 seconds).

Watched now: chat frames' `AddMessage` (`UI/Speech`), chat edit boxes' `UpdateHeader` (`UI/ChatTabs`), the XP bars' `UpdateCurrentText` (`UI/MicroMenu`), gamepad prompts' `SetPromptText` (`UI/Gamepad`).

## Reading it
- In game: `/wfj log` prints the last 10 entries, `/wfj log 30` the last 30 (at most 50), then one line with the Lua errors: `errors: N recorded, M not sent (/wfj bug)`. `/wfj taint` runs the taint scan now and says how many tainted fields and globals it found.
- After the session: `WTF/Account/<ACCOUNT>/SavedVariables/WoWForeverJapanese.lua`, the `WFJ_Log` table. The client writes it on logout, `/reload` and exit, not on a crash.

## Privacy
No game text, no character, realm or account name, no chat, no location. Frame and function names, counts and times only. The taint watch's event ring keeps an event's first argument only when it is a number, a unit token (`player`, `party2`, `nameplate14`, `targettarget`) or the addon name of `ADDON_LOADED`, never other text (another event's first argument may be a player's name), never a secret value, and leaves every chat event out. A `write` entry names the first line of its stack outside this addon, the Blizzard writer. A stored Lua error holds the error's own message and stack, with the player's name written as `<name>`; stack paths start at `Interface/AddOns/`, never the account folder.

## Key files
`addon/WoWForeverJapanese/Core/Diag.lua` · `Core/ErrorLog.lua` · `UI/TaintWatch.lua` · `Main.lua` (load, session, start, the error and stack deps) · `UI/Slash.lua` (`log`, `taint`) · `tests/lua/spec/diag_spec.lua` · `tests/lua/spec/errorlog_spec.lua` · `tests/lua/spec/taintwatch_spec.lua`
