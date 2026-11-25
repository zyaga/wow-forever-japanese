# ADR-109: Chat tools: word cards on chat, a copy icon and a phrase book both languages read

- **Status:** Accepted
- **Date:** 2026-11-24

## Context
Players of both languages meet in chat, and chat was the one place the addon gave no help. A Japanese speaker reads English shorthand there (LFM, WTS, OOM); an English speaker in a Japanese guild reads Japanese chat. An addon cannot reach a translation service, so a typed sentence cannot be translated in game. Other chat addons swap known words inside what a player typed, which reads badly between English and Japanese (the word order is reversed) and changes a player's own text.

Three client facts shape what is possible. A chat line's own FontString says which character is under the mouse (`FindCharacterIndexAtCoordinate`), and the client's text selection uses it on chat lines with indices that count the line's escape sequences. A message filter may change a chat message before it is drawn. A chat message is drawn by each player's own client, so a player without the addon sees exactly what was typed.

## Decision
1. **Word cards on chat, the line left as typed.** While the mouse is on a visible chat line, the word under it takes the word card: Japanese words in Japanese first, English words in English first. Nothing is hooked and no line is changed; a timer reads the mouse, and nothing runs on a line the client keeps secret. The word's place on screen comes from the one guarded span call in `UI/Readings`, through an entry point for chat lines only, whose indices count their escape sequences; no caller can switch the guard's checks off.
2. **Three word lists, in this order:** the player's own words (saved, never shipped), a chat list written for chat (`data/chat/`, with provenance), and two general lists `make generate` builds from the shipped readings: every Japanese word with the reading and meaning it is used with most, and every English word with the dictionary form of the Japanese word used for it most. A chat card's meaning is therefore the word's most used one, not one picked for the chat sentence. A run of verb endings after a listed stem joins that word.
3. **A copy icon instead of translation.** A chat line cannot be selected, and an addon cannot write the clipboard, so an icon on the hovered line opens a box with the text selected. That is the way to a full translation: the player pastes it wherever they like.
4. **A phrase book with a mark.** The addon ships phrases in both languages. A click types a middle dot and the English into the chat box; the player sends it. English is always what is sent: the client's chat font has no Japanese, so a reader without the addon could not read a Japanese phrase at all. A reader with the addon sees a gold 文 in place of the dot and the phrase in their own language. Only a dot followed by exactly one shipped phrase is changed. The reveal key shows the message as it was sent.
5. **The phrase book opens the way the study tab does:** a button in the client's chat button art that becomes a card at the same spot, with one saved spot for both.
6. **A phrase is never a line of the game's own English.** `generate` refuses one that is, so the addon ships no stored game text through the phrase list.

## Consequences
- Chat becomes a word-card surface, and a typed line can be shown changed in one narrow case (a marked phrase).
- About 84,000 more rows are always in memory (4.2 MB of Lua on disk). A test fails if the generated lists pass 6 MB.
- The mark is visible to everyone as a bullet. It tells the addon where a phrase starts, so a line someone typed by hand that happens to match a phrase is left alone.
- Free sentences stay untranslated. Words in no list take no card. Conjugations outside the listed endings split.
- The window test gains a read that opens the phrase card and the chat words window and checks their tabs, rows, size and language.

## Alternatives considered
- **Swapping words inside a typed line**: reads as word salad between these two languages and rewrites a player's text.
- **Sending the Japanese phrase**: invisible to a reader without a Japanese font, which is every reader without the addon.
- **An invisible mark, or an addon message beside the chat line**: an invisible character may draw as a box in the client's font, and a side channel reaches only players in the same group or guild. A visible dot works on every channel.
- **A meaning chosen per chat sentence**: needs a model in game. Not possible.
- **A full dictionary as the word list**: wider coverage, at the cost of a share-alike licence on shipped data and several more megabytes. Left out; the three lists above cover game words and chat shorthand.
