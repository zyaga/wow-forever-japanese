# Research: cinematic subtitles on Forever: can the addon reach them?

> A bounded spike. It corrects an earlier reading, made from the Classic Era tree, that subtitles are not hookable, and says what one in-game check decides.

- **Date:** 2026-09-26
- **Question:** Does the Forever client draw cinematic subtitles through Lua an addon can post-hook, where does their English come from, and is a subtitle surface worth building?
- **Source:** the Forever client's UI extract, build **1.60.1.70009** (`interface/addons/…`, lowercased paths, as `wfj.dev.client_ui` writes them) and its `GlobalStrings.csv`. Anything not settled by those files is marked **[unverified]**.

## Options
| Option | Pros | Cons |
|---|---|---|
| A subtitle surface: post-hook the subtitle writer, key each line by its English hash | the same shape as gossip and NPC speech (ADR-022, ADR-035) | the English is server text: it has to be collected before it can be drafted |
| No surface | nothing to build | the competitor shows Japanese subtitles |
| A timed overlay of our own (the earlier plan) | works without a hook | our own transcripts and timings, synced to playback we cannot query; not needed if the hook exists |

## Findings

### (a) The path: `SHOW_SUBTITLE` → `SubtitlesFrame` → `SetText` [verified in the source]
- `blizzard_subtitles` loads in game on every game type, camelot included: its TOC has `## AllowLoad: Both` and no `AllowLoadGameType` (`blizzard_subtitles/blizzard_subtitles.toc:3`).
- `SubtitlesFrame` (`blizzard_subtitles.xml:4`, mixin `SubtitlesFrameMixin`) registers `SHOW_SUBTITLE` and `HIDE_SUBTITLE` (`blizzard_subtitles.lua:9–10`).
- `OnEvent` (`:85–100`) takes `message, sender`. With a sender it builds `format(SUBTITLE_FORMAT, sender, message)`, where `SUBTITLE_FORMAT` is `%s: %s` in the Forever GlobalStrings; without one it uses the message as it is. It calls `AddSubtitle(body)`.
- `AddSubtitle` (`:37–74`) writes a pooled FontString with `fontString:SetText(body)` (`:54`). When all of them are in use it first scrolls every line up with `SetText(next:GetText())` (`:48–50`), then sizes the background from `GetStringWidth` / `GetStringHeight` (`:62–63`).
- `HideSubtitles` (`:76–83`) clears every line with `SetText("")`.
- The frame is shown by `Subtitles.OnMovieCinematicPlay` (`:23–30`). That fires for in-engine cinematics (`CINEMATIC_START`, `blizzard_framexml/shared/cinematicframe.lua:82–93`) and for movies (`blizzard_framexml/movieframe.lua:47`). The frame shows lines only while the `movieSubtitle` setting is on (`:28, 87`).

So in-engine cinematic subtitles are written by Lua, one line at a time, through a method on a named frame. A post-hook on `SubtitlesFrame.AddSubtitle` (or on its FontStrings' writes) can reach them, the ADR-015 shape.

### (b) The earlier claim is corrected
The earlier mechanism research said subtitles are "not hookable": "no Lua `SetText` to post-hook and no FontString to reach". That was read from the Classic Era tree's `MovieFrame.lua`:
- For **pre-rendered movies** it still holds. `MovieFrameMixin:OnShow` calls `self:EnableSubtitles(GetCVarBool("movieSubtitle"))` (`blizzard_framexml/movieframe.lua:63`), a method of the movie frame itself [unverified: whether the engine also sends `SHOW_SUBTITLE` for movie lines].
- For **in-engine cinematics** it is wrong on the Forever client (a). That is the kind a race intro is [unverified: that the Forever race intro is an in-engine cinematic; the Classic intros are camera fly-bys].

### (c) What the source cannot settle
| Fact | State |
|---|---|
| Forever fires `SHOW_SUBTITLE` with text during a cinematic a level-1 character sees (the race intro), with subtitles on | **[unverified]**: the in-game check below |
| Where the English comes from | **[unverified]**. The event carries the text; nothing in the UI source holds it. Likely server-sent or a client table such as BroadcastText; the NPC speech import already reads VMaNGOS `broadcast_text`, which may hold intro narration |
| How a line would be keyed | a hash of the English message, the precedent of gossip and NPC speech (text the server owns with no game ID of its own, [principle 5](../architecture/principles.md)), **not** of `body`, which carries the sender |
| `sender` | a speaker's name. It stays English ([principle 2](../architecture/principles.md)); a surface would translate `message` only and rebuild `%s: %s` around the live sender |
| Movies (`EnableSubtitles`) | **[unverified]** whether they go through `SHOW_SUBTITLE` at all |

### (d) The in-game check (level 1)
A new character's race intro plays straight after the first login, before any `/run` line can be typed, so the check is visual.

1. On any character, turn subtitles on and confirm it (the setting is the `movieSubtitle` console variable, `blizzard_subtitles.lua:1, 28`):

   ```
   /run SetCVar("movieSubtitle", 1) print("movieSubtitle", GetCVar("movieSubtitle"))
   ```
   It prints `movieSubtitle 1`.
2. Log out, create a new character, and watch its intro. Note whether any subtitle lines appear at the bottom of the screen.

For any later in-game cinematic (not the intro), this line prints each subtitle event to chat. Paste it before the cinematic starts; the chat window is hidden while it plays, so read the chat afterwards:

```
/run local f=CreateFrame("Frame")for _,e in ipairs({"CINEMATIC_START","SHOW_SUBTITLE","HIDE_SUBTITLE","CINEMATIC_STOP"})do f:RegisterEvent(e)end f:SetScript("OnEvent",function(_,...)print("WFJ trace:",...)end)WFJTrace=f print("WFJ trace: on")
```

It prints `WFJ trace: on` at once (the line is under the 255-character chat limit). Then, during a cinematic:
- `CINEMATIC_START` with its two arguments (`cinematicframe.lua:82–83`);
- one `SHOW_SUBTITLE <message> <sender>` per line (`blizzard_subtitles.lua:88`);
- `HIDE_SUBTITLE`;
- `CINEMATIC_STOP`.

`/reload` removes it.

### (e) The verdict rule
- **Subtitle lines appear during the intro (check d.2): build** a subtitle surface. Its first step runs the trace above on an in-game cinematic, to confirm the lines arrive through `SHOW_SUBTITLE`, and finds their English source.
- **No subtitle lines appear with subtitles on: no surface.** `blizzard_subtitles` stays `not-a-window` in `pipeline/forever_addon_dispositions.txt`, and its reason gains "no subtitle lines on the Forever intro (in game, \<date>)".

## Result (in game, 2026-09-26)
With subtitles on, a new Orc character's intro played with the narrator speaking and **no subtitle lines** on screen. By (e): **no surface.** `blizzard_subtitles` stays `not-a-window`, its reason records this check, and no subtitle surface is planned.

## Recommendation
No subtitle surface. The hook exists (a), but the Forever intro draws no subtitles to hook. If a later Forever cinematic ever shows subtitle lines, run the trace in (d) on it and reopen this with its output: the surface would be small (the ADR-015 shape plus gossip-style hashed keys), and the work would be collecting the English.
