# Diagnostics log

> The addon's own record of problems seen in game, kept so they can be read after a reload or a crash.

## Purpose
Some failures only show in a long play session: a hooked method that stops working, a protected call the client blocks, a surface whose setup failed. The client's error window shows them once and loses them on exit. `Core/Diag.lua` writes them to the addon's third SavedVariables table, `WFJ_Log`, so they can be read afterwards, and any module can add its own entries.

## What is recorded
| Kind | When | Fields |
|---|---|---|
| `session` | each load (login or `/reload`) | client build, addon version, the surfaces whose setup failed |
| `init` | each surface whose setup failed at load | the surface, the error (300 characters at most) |
| `blocked` | the client's `ADDON_ACTION_BLOCKED` or `ADDON_ACTION_FORBIDDEN` naming this addon | the event, the protected function |
| `hook` | a method the addon post-hooked on one frame (`Diag.watch`) no longer reads as a function | frame, method, what it reads as, its type on the frame's own table and on what the frame inherits |
| `memory` | every 5 minutes | the Lua memory |

Every entry also carries the local time (`at`), seconds since the client started (`up`) and the Lua memory in KB (`memKB`). The same kind and message again in one session adds to that entry's count (`n`) and last time (`last`) instead of a new entry, so something repeating every few seconds never pushes the rest out. The log keeps the newest 500 entries; session entries are dropped last.

A `hook` or `blocked` entry also prints one chat line, once per session, ending in "/wfj log shows it".

## Adding to it
`WFJ.Diag.log(kind, message, fields)` from any module. `fields` holds strings, numbers and booleans; anything else is stored as its type name. `WFJ.Diag.watch(frame, method, label)` after a `hooksecurefunc` on a single frame adds that hook to the checks (every 5 seconds).

Watched now: chat frames' `AddMessage` (`UI/Speech`), chat edit boxes' `UpdateHeader` (`UI/ChatTabs`), the XP bars' `UpdateCurrentText` (`UI/MicroMenu`), gamepad prompts' `SetPromptText` (`UI/Gamepad`).

## Reading it
- In game: `/wfj log` prints the last 10 entries, `/wfj log 30` the last 30.
- After the session: `WTF/Account/<ACCOUNT>/SavedVariables/WoWForeverJapanese.lua`, the `WFJ_Log` table. The client writes it on logout, `/reload` and exit, not on a crash.

## Privacy
No game text, no character, realm or account name, no chat, no location. Frame and function names, counts and times only.

## Key files
`addon/WoWForeverJapanese/Core/Diag.lua` · `Main.lua` (load, session, start) · `UI/Slash.lua` (`log`) · `tests/lua/spec/diag_spec.lua`
