# ADR-057: The addon catches its own Lua errors by wrapping the error handler

- **Status:** Accepted
- **Date:** 2026-10-03
- **Related:** [ADR-045](045-player-fix-reports.md) (player fix reports, an issue form filled from the game) · [ADR-056](056-collector-send-string.md) (collected English sent in an issue link, the same 6,000-character link budget and I sent it button) · [Diagnostics log](../systems/diagnostics.md) · [Fix reports](../systems/fix-reports.md)

## Context

Forever hides Lua errors by default. When this addon's code fails, the player sees a window that does nothing or
text that stays English, and has no error to report. The bug-report issue form asked for a Lua error the player
had never seen. The addon already keeps a problem log (`WFJ_Log`) and already fills issue forms through a link
([ADR-045](045-player-fix-reports.md), [ADR-056](056-collector-send-string.md)).

The client gives addons `geterrorhandler` and `seterrorhandler`. The handler Blizzard installs
(`Blizzard_ScriptErrors.lua`) works out the stack level to print from the error's own callstack height, not from a
fixed depth. BugGrabber, the part of BugSack that catches errors, sets its own handler, never calls the one before
it, and then replaces `seterrorhandler` with a function that does nothing. `!BugGrabber` loads before this addon.

## Decision

1. **Wrap, never replace.** At file load (the first file in the TOC, so load errors in every other file are
   caught) `Core/ErrorLog.lua` reads the current handler and sets a wrapper. The wrapper records the error
   inside `pcall` and always calls the previous handler with the same arguments. The game's error window and any
   other error addon behave as before. Because Blizzard's handler reads the stack level from the error's own
   callstack height, the extra frame does not shift what it prints. The recorder reads the stack with the same
   formula; with no error height (a handler called directly) it uses offset 0, as the client does, and a client
   without the height functions gives no stack, so the message alone decides. Errors a setup step catches with its
   own `pcall` never reach the handler, so the step guard records them too, from the message.
2. **Only errors raised in this addon's files.** An error is kept when it was raised in a file under
   `WoWForeverJapanese/` (including the client's front-truncated `...rface/AddOns/WoWForeverJapanese/...` form).
   The file that decides is the one the message names at its start; for a message without one, the top Lua frame
   of the stack, skipping `[C]` frames, `(tail call)` and the wrapper's own frames. An error whose message names
   another addon's or Blizzard's file is not ours, even when this addon's code is lower in the stack: that error
   is for the other addon's author, and "anywhere in the stack" would catch every error raised from a hook.
3. **Kept in the problem log.** `WFJ_Log.errors` holds the message (500 bytes), a trimmed stack (12 lines,
   1,000 bytes), a count, first and last time and a sent flag. No local variables. The player's name is written
   as `<name>`. Addresses in the message are blanked for matching, so the same error on another table is one
   entry. Over 30 errors the oldest sent one goes; with none sent the newest is dropped, so the first errors
   (usually the cause) are kept. `Diag.VERSION` is unchanged: an older log simply gains the field.
4. **Sent through a filled-in issue form.** The report window builds a link to `bug-report.yml` with the client
   build, the addon version and the unsent errors as readable text. Over 6,000 characters (the limit measured for
   [ADR-056](056-collector-send-string.md)) the link carries build and version only and the window shows the
   error text to paste. I sent it marks exactly the errors the shown report held, matched by message, last time
   and count.
5. **Another error addon is detected, not read.** At `PLAYER_ENTERING_WORLD` the addon checks whether the active
   handler is still its wrapper. When it is not, the report window says another addon catches Lua errors and asks
   the player to paste this addon's errors from it.
6. **No setting.** Capture is always on; there is nothing for a player to configure.

## Consequences

- A player can report a failure they never saw, with the error attached, in a few clicks.
- With BugSack installed the log stays empty and the player copies the error from BugSack by hand.
- The wrapper sits on the client's error path for every addon. It only reads strings and writes one table, inside
  `pcall`, and an error raised while recording is never recorded again. This is the same pattern BugGrabber uses.
- One chat line per session tells the player an error happened, since the client shows nothing by default.
- The issue is read by a person; no workflow checks bug or idea issues.
- **Unverified:** the client's handler skips `addframetext` and `C_Log.LogErrorMessage` when `canaccessvalue`
  fails under taint. With this addon's insecure wrapper in the path, an error whose message is a secret value
  may no longer reach the client's own log. The in-game checklist looks at it.

## Alternatives considered

- **Replace the handler (as BugGrabber does):** the game's Lua error window and every other error addon would stop
  seeing errors. Rejected.
- **`AddLuaErrorHandler`:** the client's list of extra handlers asserts `issecure()`, so it is not open to addon
  code [verified: forever-ui Blizzard_ScriptErrors/Blizzard_ScriptErrors.lua:66-69].
- **Read BugGrabber's store when it is present:** a dependency on another addon, which the project does not allow.
- **Keep every addon's errors:** a report would carry other addons' failures, which this project cannot fix, and
  more text that could hold personal details.
