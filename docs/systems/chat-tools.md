# Chat tools

> Study and play tools on the chat window: word cards on chat lines, a copy icon on the line under the mouse, a phrase book that types a short English phrase any player can read and that players with the addon read in their own language, and a window for the player's own chat words. Code: `Core/ChatWords.lua` (the word lists and where a word sits in a line), `Core/ChatPhrases.lua` (the phrases and the phrase mark), `UI/ChatLines.lua` (the timer that finds the chat line under the mouse; load step `chatlines`), `UI/ChatCards.lua` (the tint, the card and the save click on chat lines), `UI/ChatCopy.lua` (the copy icon and the copy box), `UI/ChatPhraseLines.lua` (the message filter and the reveal key on phrase lines), `UI/PhraseBook.lua` (the 文 button and the phrase card), `UI/ChatWordsWindow.lua` (the own words window), `View.chatSpanAreas` in `UI/Readings.lua`, the `chat.*` settings in `Core/Settings.lua`, the Chat section of the Words page in `UI/Options.lua`, the strings in `UI/OptionsText.lua`, `/wfj phrases` and `/wfj chatwords` in `UI/Slash.lua`, the `chatwords`, `chatcards`, `chatcopy`, `chatphraselines` and `phrasebook` load steps in `Main.lua`; in the pipeline `wfj/core/chat_words.py` and the chat step of `wfj/cmd/generate.py`. Decision: [ADR-109](../adr/109-chat-tools.md).

## Purpose
Chat is where a learner meets Japanese and English that nobody translated: what other players type. The addon never rewrites that text. It helps the reader instead: pointing at a word shows its card, as on quest text; a line can be copied out to a dictionary or a translator; and a small book of fixed phrases lets two players who share no language say the common things (greetings, group, loot, trade) and each read them in their own language. A player without the addon sees nothing new: a phrase reaches them as a middle dot and plain English.

## How it works
```mermaid
sequenceDiagram
  participant U as Player
  participant L as UI/ChatLines (timer)
  participant C as UI/ChatCards
  participant W as Core/ChatWords
  participant V as UI/Readings (chatSpanAreas)
  participant B as UI/PhraseBook
  participant P as Core/ChatPhrases
  participant F as UI/ChatPhraseLines (filter)
  L->>C: every 0.04 s: the visible chat line under the mouse
  C->>C: FindCharacterIndexAtCoordinate on that line's FontString
  C->>W: japaneseAt / englishAt(text, byte)
  W-->>C: the word's span and its card (own words, chat list, general list)
  C->>V: chatSpanAreas(line, text, first, last)
  V-->>C: the word's rectangles
  C->>U: gold tint and word card
  U->>B: click the 文 button, then a phrase
  B->>P: typed(phrase)
  B->>U: "· Hello!" in the chat box; the player presses Enter
  F->>P: translate(arriving message, direction)
  P-->>F: "文 こんにちは！" (a marked phrase in the reader's language), or nothing
  F->>U: the changed message; the message as sent kept in memory
```

### Word cards on chat lines
Nothing is hooked and no chat line is changed. `UI/ChatLines` runs a timer every 0.04 seconds, only while word cards or the copy icon are on and translation is on. While the mouse is over a visible chat frame (the frames listed in `CHAT_FRAMES`), it finds the visible line under the mouse and tells its listeners. `UI/ChatCards` asks that line's own FontString which byte is under the cursor, with `FindCharacterIndexAtCoordinate`, the call the client's own text selection uses. `Core/ChatWords` finds the word at that byte, and `UI/Readings` draws it as on every word-card surface: the gold tint, then the word card (`UI/ReadingPopup`) or, with meanings off (`readings.glosses`), the reading box, with the save click's hint until the player has saved a word once. While the mouse rests on the word that is showing, nothing is looked up again.

- **Japanese first:** Japanese words take cards. **English first:** English words take cards, with how the word is said, the Japanese word used for it and that word's reading, as on an English word card ([Readings → English word cards](readings.md#english-word-cards)).
- **No card** while the reveal key is held, with translation off, with `readings.enabled` off, with `chat.cards` off, on a line that has faded out (alpha 0.2 or less), or on a line whose text the client keeps secret (`issecretvalue`, the chat lockdown). A secret index from the client is refused the same way. A line that holds secret text also answers whether it is visible, how faint it is and whether the mouse is on it with secret values, and testing one is an error: `ChatLines.showing` and the look check each answer with `issecretvalue` before using it, and a secret answer means the line is not read.
- **A link's label** (a player, an item, a quest) never takes a card, and neither does any escape sequence: `ChatWords.runs` lists the stretches of a line drawn as typed, outside every `|c…`, `|r`, `|T…|t`, `|A…|a`, `|K…|k` and the whole of a `|H…|h<label>|h` link.
- **The word's place on screen** comes from `View.chatSpanAreas`, the chat line's entry point to the one guarded call that may ask the client for a span's rectangles ([Readings → The guard](readings.md#the-guard)). A chat line's byte indices count its escape sequences, as the client's own text selection counts them there, so this entry point alone lets text holding `|` through. Every other check stays, and no caller can switch one off.

**The save click** ([Word list](word-list.md)) works on a chat word as on any word-card surface: a press and a release on the same word, with the save click's modifiers held. The entry's sentence is the stretch of the line the word sits in, and on a line a player typed it starts where their message starts, so the sender and the line's opening words ("[Name] says: ") are no part of it. The entry's kind and id are both `chat`.

### The word lists
`Core/ChatWords` looks a word up in three layers, in this order, and the first that has it wins:

| layer | where it lives | what a row holds |
|---|---|---|
| the player's own words | `WFJ_ChatWords`, the account's saved variable (never shipped) | Japanese: reading, meaning. English: its Japanese, that Japanese's reading |
| the chat list | `data/chat/words-ja.jsonl` (341 words), `words-en.jsonl` (361 words); shipped as `Data/Chat/Chat_list.lua` (`chatword`, `chatwordEn`) | Japanese: reading, meaning. English: its Japanese |
| the general lists | generated from the shipped readings: `Data/Chat/Chat_ja_NN.lua` (`chatja`, about 65,500 words), `Chat_en_NN.lua` (`chaten`, about 18,600 words) | Japanese: the reading and meaning number used most. English: the Japanese dictionary form used most, its reading and meaning number |

An English word found in none of them falls back to the common word list (`English_Common.lua`), and a contraction takes its first word's card (`you're` takes `you`'s). A plural with no row of its own takes its singular's when the singular has four letters or more (`golds` takes `gold`'s); a shorter word never borrows a card, so `is` does not take `i`'s.

**Cutting Japanese into words.** Chat has no reading rows, so `ChatWords` cuts the Japanese stretch around the mouse itself: at each place, the longest listed word (up to 12 characters), else one character, which takes no card. A listed word that ends in hiragana (a stem: 行き, 食べ, 倒し) takes any run of verb and adjective endings right after it into the same target (ます, ません, ませんか, ました, ましょう, たい, ない, て, た, ている, …), so 行きませんか is one word with 行き's card. A word that ends in a kanji or katakana takes none (私たち stays 私 and たち).

**An English word's Japanese** is the dictionary form of the Japanese word used for it most in the shipped lines (kill is 倒す, not the 倒し of one sentence). A chat card shows a word's most used meaning in the game text, not a meaning picked for the chat sentence.

### Copy
An addon cannot write the clipboard. `UI/ChatCopy` puts a small icon (the guild roster's note icon) at the top right of the chat line under the mouse; a click opens a tool window holding that line with its text selected, for the player's own Ctrl+C (Cmd+C on a Mac). Esc closes it.

- A line a player typed (say, yell, party, raid, guild, officer, whisper, Battle.net whisper, community and numbered channels) gives only the message: everything after the sender's link and the `: ` that closes the opening words.
- Any other line (system, loot, an emote) is given whole.
- Escape codes are taken out; a link keeps its label.

The icon follows the line `UI/ChatLines` reports (`ChatLines.onLine`), so it never shows on a secret line. It is placed once for a line, and the line's text is read out only on the click. It shows with translation on and `chat.copy` on, whatever the reveal key or `chat.cards` say. The box is a read-only field: it selects all of itself, and typing in it changes nothing.

### The phrase book
**The button** (`WFJPhraseButton`, 27 × 26) is the client's own chat button art (`chatframe-button-up`, `-down`, `-highlight`) with a gold 文 where the client's buttons carry their icon. Until the player drags it, it sits centred right above the chat frame's own menu button (the speech bubble), or beside the main chat frame when that button is not shown (on the side the client keeps the chat buttons). The card opens by the chat frame on that same side. Its tooltip is a label of the addon's own (the client's tooltip font has no Japanese).

**The card** (`WFJPhraseCard`, 704 × 416) is built the way the study card is ([Study → The tab and where it lives](study.md#the-tab-and-where-it-lives)): the same backdrop, a minus and an X in the header, the topics as the client's own tabs under it (the strip drawn smaller when nine tabs are wider than the card), the phrases in two columns of up to eight rows (Japanese above, English below in grey), and a footer, "Click a phrase, then press Enter to send it." Every topic shows at one fixed size, so the card never moves under the mouse.

| action | what happens |
|---|---|
| click the button | the button becomes the card, at the same spot |
| click a phrase | `· ` and the phrase's English go into the chat box (the open one with its own `Insert`, else a new one); the card collapses to the button; the player presses Enter |
| the card's minus | back to the button |
| the card's X | both hidden until something opens the card again; the next login or `/reload` shows the button as before |
| drag either | both move: they share one saved spot, `WFJ_DB.phrases.point` |
| `/wfj phrases` | opens the card, or collapses it when it is open, whatever `chat.phraseButton` says |
| **Open the phrase book** on the Words page | opens the card |

The button shows with `chat.phraseButton` on, the card closed, and a chat frame to sit by, with translation on or off, like the study tab. The minimap menu has a **Phrase book** line that opens the card after the X hid both. Nothing in the book is a protected call, and nothing it does sends a message: the player always presses Enter.

**The phrases** (`data/chat/phrases.jsonl`): 132 phrases in 9 topics (greetings, group, combat, dungeon, loot, trade, guild, travel, answers), at most 16 per topic, the most the card has room for. Each has an id, a topic, its English and its Japanese.

### The phrase mark and received phrases
A phrase is sent as a middle dot, a space and its English (`· Hello!`). To a player without the addon that reads as a bullet and plain English.

With the addon, `UI/ChatPhraseLines` adds a message filter (`ChatFrameUtil.AddMessageEventFilter`, the client's own way to change a chat message before it is drawn) on the chat events a player types into: say, yell, party, raid, raid warning, guild, officer, whispers, channels and instance chat. `Core/ChatPhrases.translate` looks for a dot (`·` U+00B7 or `・` U+30FB) followed, after any spaces, by exactly one of the book's phrases, in either language (English compared without case). Each such phrase becomes a gold 文 and the phrase in the reader's direction's language: Japanese in Japanese first, English in English first. Two marked phrases in one message are both changed. Phrases are matched longest first, so a phrase that starts another never wins over it.

What stays as typed:

- a dot before anything that is not a phrase, and a dot inside a name (ジョン・スミス);
- a phrase with no dot in front;
- every message with `chat.phrases` off or translation off, and a message the client keeps secret.

**The reveal key.** The filter keeps the last 200 changed messages in memory, each with the message as it arrived. After `UI/ChatSystem`'s own pass over the visible lines (the chat frame's display refresh callback), a line holding a changed phrase shows, while the reveal key is held:

- in Japanese first, the message as it was sent;
- in English first, the Japanese phrase.

On release the line's own text goes back. The chat history is never rewritten.

**Following the switches.** The same pass keeps the visible lines in step with translation and `chat.phrases`: a marked message that arrived while either was off shows its phrase once both are on, and a changed line shows the message as it was sent once either goes off. Only the lines on screen change, and only lines a player typed: of such a line only the message is looked at, never the sender or a link's label. A line already changed keeps the language it was changed into when the direction is switched, until it is drawn again. After a reload the kept messages are gone, so older lines stay as they were drawn.

### Own chat words
`UI/ChatWordsWindow` (`WFJChatWordsWindow`, from **My chat words** on the Words settings page or `/wfj chatwords`) is a tool window with two rows of boxes:

- **A Japanese word:** the word, its reading, its meaning, and **Add**.
- **An English word:** the word and its Japanese, and **Add**.

Below them is the list of the player's words, Japanese words first, each group by word, and **Remove** for the row picked. A word added takes a card in chat at once and wins over every shipped list; Remove takes it out of the window and out of chat. The words live in `WFJ_ChatWords`, account-wide, and are never shipped:

```lua
WFJ_ChatWords = {
  ja = { [word] = { reading = "…", meaning = "…" } },
  en = { [lower-cased word] = { ja = "…", reading = "…" } },
}
```

`Main.lua` loads it in the `chatwords` step; a load that fails keeps the saved table, so the client never writes an empty one over it.

### The pipeline
`make generate` writes the three chat files beside the reading data ([Pipeline → Generate + validate](pipeline.md#generate--validate)):

- **`Chat_ja_NN.lua`** (12 files): every Japanese word of the shipped reading rows with the reading and meaning number it carries most, a pair with a meaning before a pair without one. Left out: a single kana, a word with anything but Japanese characters, a word longer than 12 characters, and a kana word with no meaning (its card would show nothing).
- **`Chat_en_NN.lua`** (4 files): every English word of the shipped English word card rows with the dictionary form of the Japanese word used for it most. A row with no meaning is skipped.
- **`Chat_list.lua`**: `data/chat/` as it is.

A word's file is the CRC-32 of the word modulo the file count, so a new word changes one file. The chat files load last in the TOC: a row is only read with the mouse on a chat line. The English chat words are added to the words the pronunciation table keeps, so an English chat card can show how its word is said. The generated chat files total under 6 MB (a test holds them to it).

`data/chat/` is checked as it is read, and `generate` (and so `validate`) refuses it when:

- a row has no `provenance`, a field is missing or empty, or a field holds a tab or a line break;
- a word or a phrase is listed twice, or an English word is not lower case;
- a phrase holds a middle dot, or a phrase's English or Japanese starts with another phrase's (the addon reads a marked phrase from its first character);
- a phrase's English, or an English chat word of several words, is word for word a line of the game's own English in `data/english/` (compared without case or outer spaces). One English word is never a clash: single English words may ship.

### Word status marks on chat
With `marks.chat` on (off by default, in the Word status section of the Words page), `UI/ChatMarks` puts the [word status](word-status.md) marks on chat lines: a red or blue underline by each word's status and the soft green highlight the highlight setting picks. A timer looks at the visible lines every 0.25 seconds; each line that shows new text gets an overlay of its own, and the words `Core/ChatWords` finds there are placed through `View.chatSpanAreas`. Nothing is hooked and no chat line is changed. A faded line, a secret line (`ChatLines.showing` decides both, so a secret answer about the line is never tested), a link's label and an escape sequence take no marks, and chat lines take no score tag. The chat word card shows the word's status line and takes the status clicks (Shift+click, Shift+right-click) while `marks.chat` is on.

### Settings
The Words page's third section, **Chat** / チャット: an explanation, four switches, all on by default, and two buttons ([Settings → Settings pages](settings.md#settings-pages)). A change is followed at once (the State event `chat`).

| setting | what it turns off |
|---|---|
| `chat.cards` | word cards on chat lines |
| `chat.copy` | the copy icon |
| `chat.phraseButton` | the 文 button (the card still opens from `/wfj phrases` and the Words page) |
| `chat.phrases` | received phrases shown in the reader's language |

The buttons: **My chat words** (the own words window) and **Open the phrase book**.

### The window test
The in-game window test reads the chat tools after the names read and before the frozen tooltip read ([Testing → Window test](../testing/strategy.md)). It opens the phrase card with `/wfj phrases`, reads every topic tab and phrase row, checks the card keeps one size and closes on the same command, then opens the chat words window with `/wfj chatwords` and reads it. A card the player had open is left open. It never clicks a phrase. The copy box is opened through the copy icon's own click handler on a line of the test's own, and the test checks that the box holds that line without its colour codes and that its heading and footer are Japanese. Another addon cannot reach the addon's own functions or put the mouse on a word, so a word card on a real chat line is not read by the test: the specs hold where a word's span may sit, and a hover in game is the check.

## Key files
- `addon/WoWForeverJapanese/Core/ChatWords.lua`: `load`, `add`, `remove`, `own` (the player's words); `japaneseAt`, `englishAt` (the word at a byte and its card); `runs`, `plain`, `typedPart`; the verb endings (pure)
- `addon/WoWForeverJapanese/Core/ChatPhrases.lua`: `list`, `topics`, `typed`, `translate`, `keep`, `sent`; the mark `MARK` and the 200 kept messages (pure)
- `addon/WoWForeverJapanese/UI/ChatLines.lua`: the timer, `look`, `onLine`, `typedPart`, `secret`, `showing`; `TYPED`, the chat types a player types into
- `addon/WoWForeverJapanese/UI/ChatCards.lua`: `follow` (the listener), `sentence`, `shown`, `clear`; the cover `UI/Readings` draws on and `UI/WordSave` saves from
- `addon/WoWForeverJapanese/UI/ChatCopy.lua`: `textOf`, `show`, `follow`; the icon and the copy box
- `addon/WoWForeverJapanese/UI/ChatPhraseLines.lua`: `filter`, `reveal`, `revealAll`; `EVENTS`, the chat events the filter is on
- `addon/WoWForeverJapanese/UI/PhraseBook.lua`: the button and the card, `open`, `collapse`, `close`, `toggle`, `type`, `pick`, the shared spot
- `addon/WoWForeverJapanese/UI/ChatWordsWindow.lua`: `open`, `items`, `add`, `remove`
- `addon/WoWForeverJapanese/UI/ChatMarks.lua`: the word status marks on chat lines, `words`, `look` ([Word status](word-status.md#chat))
- `addon/WoWForeverJapanese/UI/Readings.lua`: `View.chatSpanAreas`, `View.showHover`, `View.clearHover`, `View.poll` (the save click)
- `addon/WoWForeverJapanese/Core/Data.lua`: the `chatja`, `chaten`, `chatword`, `chatwordEn` and `phrase` kinds
- `addon/WoWForeverJapanese/Core/Settings.lua`, `UI/Options.lua`, `UI/OptionsText.lua`, `UI/Slash.lua`, `Main.lua`; `WoWForeverJapanese.toc`: `WFJ_ChatWords` in `## SavedVariables`
- `pipeline/wfj/core/chat_words.py`: `japanese_rows`, `english_rows`, `shards`, `load` (the `data/chat/` checks), `game_english_clashes`
- `pipeline/wfj/cmd/generate.py` (`_plan_chat`), `pipeline/wfj/emit/lua_writer.py` (`chat_list_text`), `pipeline/wfj/emit/schema.py` (`CHAT_LIST`, `chat_relpath`)
- `data/chat/words-ja.jsonl`, `data/chat/words-en.jsonl`, `data/chat/phrases.jsonl`
- `pipeline/wfj/dev/client_surface.py`: `WFJScanChatRead`, `read_chat`, `chat_problems`
- `tests/lua/spec/chat_words_spec.lua`, `chat_lines_spec.lua`, `chat_phrases_spec.lua`, `chat_cards_spec.lua`, `chat_copy_spec.lua`, `chat_phrase_lines_spec.lua`, `phrase_book_spec.lua`, `chat_words_window_spec.lua`; `tests/python/test_chat_words.py`, `test_chat_data.py`, `test_window_test.py`

## Invariants
- A player's text is never rewritten word by word. The only change to a typed message is a dot followed by exactly one of the book's phrases, shown in the reader's language; everything else stays as typed. [Principle 3](../architecture/principles.md#3-japanese-by-default-english-one-key-away).
- The chat history is never rewritten: the filter changes a message on its way to the screen, and the reveal key changes only the visible line, putting its own text back on release.
- No phrase and no English chat word of several words is a line of the game's own English; the generated English list ships single lower-cased words only. No English game text is stored.
- A line the client keeps secret is never read: no card, no icon, no change.
- Nothing hooks the chat frame's methods or writes a Blizzard frame's fields. The card reads the line's FontString; the filter and the display refresh callback are the client's own ways in; the phrase goes into the chat box with its own `Insert`. Nothing here is a protected call, and the addon never sends a message.
- Every span asked of the client goes through the one guarded call in `UI/Readings`; a chat line's goes through `View.chatSpanAreas`, and `View.spanAreas` takes no argument that lets escape sequences through.
- `WFJ_ChatWords` and the kept messages are the player's own: never shipped, and the kept messages are never saved.

## Edge cases
- **A dot inside a name** (ジョン・スミス), or before ordinary text: left as typed.
- **A phrase typed without the dot**: left as typed, so a sentence that happens to match a phrase is never changed.
- **A reload**: the kept messages are gone, so a phrase line from before it stays as it was drawn and no longer switches on the reveal key.
- **A Japanese word inside a link's label** (a player named in Japanese, a linked item): no card.
- **A particle after a word that ends in hiragana**: the endings a verb takes (て, た, か, よ, ね and the rest) are joined to any word ending in hiragana, so a word in no list can be cut oddly (それから gives それか with それ's card).
- **A word saved from chat twice**: a chat word is kept once for its dictionary form, with the sentence of the first save.
- **Two lines showing the same phrase**: the reveal key shows the longest kept message that fits the line, and of equals the one that arrived last, so a line sent as `· Hello!` can show `・こんにちは！` when both were received.
- **An own word no chat line could give** (an English word with a space, a Japanese word with Latin letters or more than 12 characters): refused, with a note in the window.
- **A typed line not shaped as expected** (no sender link, or a link in the opening words): the copy box takes the whole line, and the save click uses the stretch the word sits in.
- **An English chat word saved with the save click**: there is no shipped line behind a chat sentence, so the entry has no Japanese sentence for the back of its study card.
- **`/wfj phrases` with the button turned off**: the card still opens; collapsing it shows no button.
- **The X**: hides both frames for the session only; the button is back after the next login or reload.

## Related
- [Readings](readings.md) · [Word list](word-list.md) · [Study](study.md) · [Word status](word-status.md) · [Settings](settings.md) · [Pipeline](pipeline.md) · [ADR-109](../adr/109-chat-tools.md) · [ADR-081](../adr/081-english-first-and-english-word-cards.md) · [Architecture → Addon modules](../architecture/addon-modules.md) · [App capabilities → Chat tools](../app-capabilities.md#chat-tools) · [Glossary](../glossary.md)
