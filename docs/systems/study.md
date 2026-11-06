# Study

> Studying the saved word list in game: a small tab at the screen edge says how many words wait, and the card it opens asks one word at a time, graded Again or Good, on an FSRS-6 schedule. Code: `Core/Fsrs.lua` (the memory model), `Core/Study.lua` (the queue and the saved table), `UI/StudyWindow.lua` (the tab and the card), the `study` surface in `UI/Readings.lua`, `Words.has`, `Words.lineSpans`, `Words.source` and the `words` change event in `Core/Words.lua`, the three `study.*` settings in `Core/Settings.lua`, the Study section of the Words page in `UI/Options.lua`, the strings in `UI/OptionsText.lua`, `UI/MinimapButton.lua`, `UI/Slash.lua`, `Bindings.xml` and `Core/Const.lua` (the key binding), the `study` and `studywindow` load steps in `Main.lua`. Decision: [ADR-071](../adr/071-study-the-word-list-in-game.md).

## Purpose
A learner who saved words with the save click ([Word list](word-list.md)) can review them without leaving the game, in the quiet moments the game has anyway. The card shows the word in the sentence it was saved from, asks for its reading and meaning, and the two grades decide when it comes back; when nothing is due the learner is done. The scheduler is FSRS-6 as the published libraries ship it, so the intervals are the ones Anki gives. The addon keeps the schedule in its own SavedVariables table and never talks to Anki: a player who also imports the list there keeps two schedules.

## How it works
```mermaid
sequenceDiagram
  participant U as Player
  participant T as UI/StudyWindow (tab, card)
  participant Q as Core/Study
  participant F as Core/Fsrs
  participant S as WFJ_Study
  participant V as UI/Readings (cover)
  T->>Q: counts(entries, now, today, cap) every 15 s while in use
  Q-->>T: due, new left, next due
  T->>U: tab "N due" while something waits
  U->>T: click the tab, /wfj study, the minimap menu, the key binding, the Words page
  T->>Q: next(entries, now, today, cap)
  Q-->>T: the earliest due word, else a new word under the cap, else nothing
  T->>V: attach(sentence, spans minus the tested word); the card draws the mark itself
  T->>U: the word, the sentence (word in gold), Show answer
  U->>T: Show answer
  T->>U: reading, dictionary form, meaning, Again, Good
  U->>T: Again or Good
  T->>Q: answer(key, rating, now, today)
  Q->>F: review(s, d, elapsed days, rating)
  F-->>Q: stability, difficulty
  Q->>S: the card's state and its due time
  T->>Q: next(...)
```

### The scheduler
`Core/Fsrs.lua` is the FSRS-6 memory model, ported from the published library sources (py-fsrs 6.3.2 and fsrs-rs 6.6.2, which agree) with their 21 default parameters; nothing is tuned and no parameter is per player. It is pure: no globals, no frames, no notion of cards or time. It knows two things:

- **Retrievability**, the chance of recalling a word `t` days after its last review given its stability `S`: it falls with time along the curve the parameters set, and equals 0.9 exactly when `t = S`. That is what "stability" means: the number of days until the chance of recall has dropped to 90%.
- **A review**: from the current stability and difficulty, the days since the last review and the grade, the next stability and difficulty. A never-graded word gets the initial stability and difficulty of its first grade. A review on the same day as the last (under one whole day) uses the short-term formula; a later one uses the recall formula on Good and the forgetting formula on Again. Difficulty moves toward a fixed mean and stays within 1 and 10. The elapsed days are rounded to whole days, half away from zero, as fsrs-rs does (Anki works in calendar days).

`Core/Study.lua` turns that into a schedule, with a desired retention of 90%:

- **Good**: the word comes back after its stability in whole days, at least one (`now + max(1, round(S)) days`). A new word graded Good first comes back in two days (the default initial stability for Good rounds to 2).
- **Again**: one relearn step of 10 minutes (Anki's default) and one lapse counted. There is no list of learning steps, and a word graded Again a second time just gets another 10 minutes.
- **The daily cap**: `study.newPerDay` (5, 10, 20 or 50, default 20) is how many never-graded words may be started per day. The day is the client's local `date("%Y-%m-%d")`, so the cap rolls at midnight (Anki rolls at 4 am). A word's first grade, whichever it is, counts toward the day it was given.
- **Time** is `time()`, epoch seconds, never `GetTime()`; both `now` and `today` are passed in from the window, so the queue reads no global.

There are no Hard and Easy grades, no fuzz, no interval cap and no leech handling.

### The queue
`Study.next(entries, now, today, newPerDay)` walks the word list in saved order and picks, in this order:

1. the graded word with the earliest due time that has passed (`kind = "due"`); a word in its relearn step is due like any other once its 10 minutes are up;
2. else, while today's new count is under the cap, the never-graded word saved earliest (`kind = "new"`);
3. else nothing: the card shows the done state.

`Study.counts(entries, now, today, newPerDay)` gives `due` (graded words whose time has passed), `fresh` (never graded), `newLeft` (the fresh words still allowed today: the smaller of `fresh` and the cap minus today's count) and `nextDue` (the earliest due time still ahead). The tab shows `due + newLeft`; the card's footer and the settings page show `due` and `newLeft`; the minimap menu shows `due`.

### The saved table
```lua
WFJ_Study = {
  schema = 1,
  cards = { [key] = { s, d, due, last, reps, lapses } }, -- the word list key; stability (days), difficulty, due and last review (epoch seconds)
  days = { ["YYYY-MM-DD"] = n },                         -- new words started on that day
}
```

- Account-wide, like the list, and keyed by the same key ([Word list → The key](word-list.md#the-key)). It holds keys and numbers only: no word, no sentence, no English.
- `Main.lua` loads it right after the list: `WFJ_Study = step("study", function() return WFJ.Study.load(WFJ_Study, WFJ.Words.entries()) end) or WFJ_Study`. A load that fails keeps the saved table, so the client never writes an empty one over it; the failure is listed in `WFJ.initErrors` under `study`.
- `Study.load(saved, keys)` rebuilds the table: it keeps a card only when its key is in the list and its numbers are there (`reps` and `lapses` default to 0 when missing), keeps `days` entries whose key is a date, and starts empty from a missing or garbled table without an error.
- **Pruning.** A word that leaves the list loses its card: at load (above), and after **Remove last** and **Clear all** in the word list window, which fire the list's change event, `words`; `Core/Study` prunes on it and the window refreshes. A word saved again later starts as new. Only a key in the list is graded; `Study.answer` returns nil for any other.
- **Versions.** A table saved by a newer addon version (a higher `schema`) is kept exactly as it is and never written: the queue is empty, the card opens on the done state, and a grade is refused with the word list's chat line (the list cannot be changed here). An older addon version does not list `WFJ_Study` in its TOC, so the client drops it at that version's first logout; the word list itself is untouched.
- The client writes SavedVariables on `/reload`, logout and a normal exit. Grades given since the last of those are lost in a crash.

### The card
The card (`WFJStudyCard`, 320 × 214, movable) shows one word at a time.

**The front**: the word, large, in the bundled font; the saved sentence below it, wrapped (Japanese has no spaces, so the FontString wraps at any character); the **Show answer** button; a footer `N due, N new`. The tested word is marked in the sentence by the gold tint of a hovered word, kept over its byte span (`wf`..`wl` of the entry) for as long as the card shows it. A FontString cannot bold part of a line, so the mark is a texture the card draws itself over the word's rectangles, measured through `UI/Readings`' guarded span call (`View.spanAreas`, the one place that may ask the client for a span's screen areas); it is drawn when the card shows the word and once more a frame later, when a FontString shown this frame has its layout.

The sentence is a word-card surface, `study`: the card attaches a reading record to the sentence FontString with `surface = "study"`, the entry's `kind` and `id`, and its own `spans`: the sentence's words from the line's reading list (`Readings.words` and `Readings.locate`, as the export's furigana uses them) **minus any span over the tested word**. So pointing at any other word shows its card or reading as in quest text, and the tested word is never a hover target on the front, because its reading is the answer. A save click on one of those words saves it, with `Words.source("study", kind)` giving the same source the voice panel would (`quest` for a quest kind, `book` for a page, else `gossip`). A sentence with no reading list (a line no longer shipped, or an entry with no `kind`) gets its mark and no cover, with nothing to hover.

**The back** (Show answer): the reading, when it differs from the word; `Dictionary form: X（reading）`, when the dictionary form differs from the word or its reading differs from the word's; the meaning, when the word has one. The cover stays, so the sentence's readings stay hoverable. Then the **Again** (red) and **Good** (green) buttons. A grade asks `Study.answer`, then the next card shows, or the done state. A refused grade (a read-only table, a word no longer listed) prints the word list's chat line and leaves the card.

**The done state**: the title **Study** in place of the word, and two lines: `Nothing due.` and one of, in this order:

| when | the second line |
|---|---|
| a graded word is due within the hour | `The next word comes in N min.` (at least 1) |
| new words remain but today's cap is used | `Today's new words are done. Come back tomorrow.` |
| no graded word is ahead | `Save more words to study them here.` |
| the next due word is later today | `The next word comes at HH:MM.` |
| otherwise | `The next word comes on YYYY-MM-DD.` |

Every string is in English and Japanese, in the language the addon's windows use. No English game text appears on the card: the meaning is the model-written one the word card already shows, and the sentence is the Japanese the player saw ([Word list → An entry](word-list.md#an-entry)).

### The tab and where it lives
**The tab** (`WFJStudyTab`, 84 × 24, with its own close button) reads `N due` / `N語`, the count of due words plus new words under the cap. It shows only while that count is above zero, the setting `study.tab` is on (the default), the card is not open and nothing hides it; with nothing to study the player sees nothing, and the tab's frame is not even built until it is first needed. Clicking it opens the card at the same spot.

**Entry points.** These open the card whatever `study.tab` says and whether or not it was closed, on the next word or, with nothing due, the done state:

| way in | where |
|---|---|
| the tab | click |
| `/wfj study` | chat; `/wfj help` lists it |
| **Study words (N due)** | the minimap button's right-click menu, after Export words |
| **Study words: open / collapse the card** | the key binding `WFJ_STUDY` (unbound by default; it toggles: the card collapses when it is showing, else opens) |
| **Open the study card** | the Words settings page's Study section |

**Collapse** (the card's button) returns to the tab. **Close** (the card's X, or the tab's) hides both the card and the tab until something opens the card again; the next login or `/reload` shows the tab as before. `study.tab` off never blocks the ways in above; it only stops the tab showing on its own.

**Position.** Both frames are movable by dragging, clamped to the screen, and share one saved spot, `WFJ_DB.study.point` (`{ point, relativePoint, x, y }` against UIParent); the default is the right edge, middle (`RIGHT`, `-4, 0`). `/wfj study reset` clears the spot and puts both back.

**Combat.** With `study.combatHide` on (the default), `PLAYER_REGEN_DISABLED` hides the tab and the card and `PLAYER_REGEN_ENABLED` shows again whatever was showing; with it off nothing changes in combat. Only `Show` and `Hide` on the addon's own frames; no protected call is made. The state at login is read from `InCombatLockdown()`.

**The tick.** While the tab or the card is on screen a 15-second ticker (`C_Timer.NewTicker`) refreshes the counts, so a word that comes due shows on the tab, and a card in the done state asks for it; with both off screen (closed, collapsed with nothing waiting, hidden in combat) the ticker is cancelled. A save, a removal, a grade or a setting change refreshes at once: Core/Words fires the State event `words` on every change, the settings fire `study`, and the reveal key's `modifier` and `enabled` events only re-label what is on screen.

**Settings.** The Words page's second section, **Study** / 学習: an explanation, `study.tab` ("Show the study tab when words are due"), `study.newPerDay` ("New words per day"), `study.combatHide` ("Hide the study window in combat"), a status line `N due, N new words left today`, and the Open button ([Settings → Settings pages](settings.md#settings-pages)). The About page's readings line names `/wfj study`.

## Key files
- `addon/WoWForeverJapanese/Core/Fsrs.lua`: the FSRS-6 model: `W()` (a fresh copy of the 21 defaults), `retrievability`, `review` (pure)
- `addon/WoWForeverJapanese/Core/Study.lua`: `load`, `prune`, `next`, `counts`, `answer`, `card`, `readonly`; the relearn step and the day length (pure)
- `addon/WoWForeverJapanese/UI/StudyWindow.lua`: the tab and the card, the done state, the position, combat, the tick, `open` / `collapse` / `close` / `toggle`, `resetPosition` (`/wfj study reset`), `setCombat` (from Main's combat events), `WFJ_StudyToggle` (the binding)
- `addon/WoWForeverJapanese/UI/Readings.lua`: `study` in `SURFACES`; `View.spanAreas`, the guarded span call the card measures its mark with
- `addon/WoWForeverJapanese/Core/Words.lua`: `has(key)`, `lineSpans(entry)`, `source(surface, kind)`, and the `words` State event fired on every change
- `addon/WoWForeverJapanese/UI/WordsWindow.lua`: the export window, refreshed by the `words` event
- `addon/WoWForeverJapanese/Core/Settings.lua`: `study.tab`, `study.newPerDay`, `study.combatHide` (State `study`)
- `addon/WoWForeverJapanese/UI/Options.lua`, `UI/OptionsText.lua`: the Study section, the card's and the tab's strings, in English and Japanese
- `addon/WoWForeverJapanese/UI/MinimapButton.lua`, `UI/Slash.lua`, `Bindings.xml`, `Core/Const.lua`: the other ways in
- `addon/WoWForeverJapanese/Main.lua`: the `study` and `studywindow` load steps; `WoWForeverJapanese.toc`: `WFJ_Study` in `## SavedVariables`
- `tests/lua/spec/fsrs_spec.lua`, `tests/lua/spec/study_spec.lua`, `tests/lua/spec/study_window_spec.lua`, `tests/lua/spec/readings_spec.lua`, `tests/lua/spec/words_spec.lua`, `tests/lua/spec/words_window_spec.lua`

## Invariants
- No English game text is stored or shown: the card shows the saved Japanese, the reading and the model-written meaning; `WFJ_Study` holds keys and numbers only. [Principle 3](../architecture/principles.md#3-japanese-by-default-english-one-key-away).
- Study state is keyed by the word list key, never by position, and exists only for a listed word. [Principle 5](../architecture/principles.md#5-every-translation-is-keyed-by-the-game).
- The scheduler is the published FSRS-6, unchanged: `Fsrs.W()` hands out a copy, so nothing can change the model every player uses.
- The window never computes a schedule and the queue never reads a global: `now`, `today` and the cap are passed in.
- Nothing in the window is a protected call; combat only shows and hides the addon's own frames, and no cover is made in combat.
- The card is always recoverable: no setting and no close can keep `/wfj study`, the minimap menu, the binding or the Words page from opening it, and `/wfj study reset` always brings it back on screen.
- The export is unchanged: studying adds no column and changes no line.

## Edge cases
- **A word removed while on the card.** The list's change event moves on at once to the next word; its state is gone, so saving it again starts as new.
- **An empty or missing sentence** (an old or garbled entry): the word alone, with nothing to mark or hover.
- **A word with no meaning**: the back shows the reading only (and the dictionary form when it differs).
- **A reading equal to the word** (a kana word): the back skips the reading line.
- **A line no longer shipped**: the sentence keeps its mark, but no other word is hoverable, because the line has no reading list.
- **Opened in combat with the combat setting off**: the sentence shows with its mark but no hover readings, because no cover can be made in combat; the readings come when the card next shows out of combat (the card attaches again whenever it comes back on screen with a word waiting).
- **The list from a newer version**: the queue is empty and a grade is refused; the card shows the done state.
- **Midnight.** The daily cap resets at the client's local midnight; a word graded at 23:59 counts for that day.
- **A short gap.** Two grades of one word within the same day use the short-term formula, so Again then Good ten minutes later gives a small stability and a one-day interval.
- **`/wfj study <setting> <value>`** falls through to the settings grammar (only `reset` is the window's own word), so `/wfj study tab off` and `/wfj study newPerDay 10` set the settings.

## Related
- [Word list](word-list.md) · [Readings](readings.md) · [Settings](settings.md) · [ADR-071](../adr/071-study-the-word-list-in-game.md) · [ADR-069](../adr/069-saved-word-list.md) · [Testing → Study checklist](../testing/strategy.md#study-checklist) · [App capabilities → Study](../app-capabilities.md#study) · [Glossary](../glossary.md)
