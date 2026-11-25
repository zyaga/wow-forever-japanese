# ADR-111: Word status marks, a frequency list of the game's own words, and a comprehension score

- **Status:** Accepted
- **Date:** 2026-11-25

## Context
A learner reading quest text cannot see at a glance which words of a line they know, which ones are worth learning next, or how much of a text they understand. Reading tools for video and web pages answer this by keeping a status per word, underlining the words not known yet and scoring each text. The addon already knows every word of its shipped Japanese: each line carries readings with the dictionary form and its reading (ADR-036, ADR-041), and in English first each line lists its English words (ADR-081). It also knows what the player saves (the word list, ADR-069) and studies (the study card, ADR-071).

Three facts shape the design. The word-card covers (`UI/Readings`) already lie over every reading surface, measure each word's rectangles through one guarded call, and read the mouse by polling. The client's chat lines cannot take a cover, but the chat tools (ADR-109) already find the words on a visible chat line without hooking anything. And the shipped readings hold about 790,000 words of text over about 30,500 distinct dictionary forms; the 2,000 most used are about 79% of the text, so a short list of words to learn next pays back quickly.

## Decision
1. **A status per dictionary form and its reading.** A Japanese word's key is its dictionary form, a tab and that form's reading (a word with no dictionary form is itself with its reading), so 倒して and 倒した share 倒す's status on every line, and two words written alike but read differently are two words. An English word's key is its lower-cased form after the English word card rule (a contraction takes its first word, a plural with no row of its own its singular). The two languages are kept apart.
2. **Four statuses: Unknown, Learning, Known, Ignored.** No fifth status for "tracked" words: the word list and the study card already do that job.
3. **Two marks with two jobs, kept apart.** An underline shows status: red under Unknown, blue under Learning, nothing under Known or Ignored. A soft green highlight behind an Unknown word picks out a word worth stopping for, by one four-way setting (off, the common words, the common words that are the only new word of their sentence, the only new word of a sentence). Status and "stop here" never share one colour.
4. **Frequency from the game's own shipped text.** `make generate` counts every word of the shipped readings per kind of text (quest, NPC talk, book, window, item, spell) and every English word by the lines that list it. The files hold counts, not ranks; the addon sorts them once (most used first, equal totals by key), so a new word changes one file.
5. **The words to learn next are a moving set of 300.** They are the 300 most used words whose status is Unknown. Marking one Learning, Known or Ignored lets the next one in.
6. **Defaults that keep the marks on vocabulary.** A shipped grammar list (`pipeline/grammar_words.txt`, sentence endings, particles and set patterns the readings list as words) starts as Ignored. A する verb whose noun is Known is Known. A status the player sets always wins, an explicit Unknown included.
7. **The score counts what a reader has to know.** A text's score is known words over counted words: Ignored words are in neither, a Learning word counts as not known, and names and words with no card are not words here. A quest is scored as one text (description, objectives, progress and turn-in). A text of fewer than 5 counted words takes no tag. The whole game's score weights every word by how often the game uses it, with one figure per kind of text.
8. **The import is a paste, with a stated matching order.** The player pastes words from any tool. A piece is matched as a dictionary form (in every reading the game has for it), then as a form the game's text uses, then with a polite or past ending removed, then, when it is all kana, as the reading of exactly one dictionary form. A kana piece that is the reading of several is reported, not guessed. A status the player set by hand is never changed by an import. Export gives the same text back, so a list moves between machines.
9. **Saving and studying move a status up, never down.** A saved word with no status becomes Learning; a study card stable for 21 days makes its word Known unless it is Ignored.
10. **Marks are textures on what is already there.** On reading surfaces they are textures on the existing word-card covers, so they scroll and clip with the text and are never made in combat on their own. On chat they are textures on an overlay per visible line, placed by a timer, with no hook and no change to the line. The underline sits in the measured gap between text lines, snapped to the pixel grid.
11. **One switch per place.** Quests and NPC talk, books and letters, the voice panel and the frozen tooltip are on by default; chat is off by default, because a chat window is busy and other players' text is not study material for everyone.

## Consequences
- Every reading surface shows at a glance what the player does not know yet, and a learner who turns the marks off sees nothing new.
- The frequency lists add about 30,500 Japanese and 19,000 English rows always in memory (about 2.1 MB of Lua on disk). A test fails above 3 MB.
- The grammar list is a judgement call kept by hand. `generate` refuses a line that is not a word of the list or is listed twice, so it cannot drift silently.
- The rank is only as good as the game's own text: a word common in Japanese but rare in the game ranks low, which is what a player of this game wants.
- A pasted list with words the game never uses leaves them in the box, so the player sees what did not match.
- The window test gains a read of the known words window and of every frame carrying marks. It cannot check which word takes which mark, since another addon cannot ask the addon's plan; the Lua specs hold that.

## Alternatives considered
- **A status per inflected form**: 倒して, 倒した and 倒す would each need marking, and the score would punish a reader for a conjugation.
- **A fifth "tracking" status**: overlaps the word list and the study card, and adds a colour to learn.
- **One colour for status and for "stop here"**: a reader cannot tell a word they are learning from a word worth stopping for.
- **An outside frequency list**: other words, other weights, and its own licence. The game's own text ranks the words a player of this game meets.
- **Ranks written into the files**: a new word would shift every row after it and change every file.
- **Fixed bands (top 1,000, top 2,000)**: a band stays the same while the player learns; a moving 300 always holds the next words to learn.
- **Counting Learning as half known, or Ignored as known**: Ignored as known inflates the score with words the player chose not to study, and half credit makes the figure harder to read.
- **A sync with another program**: no addon can reach one. A paste works with any tool.
- **Hooking the chat frame to underline words in the line's own text**: rewrites what the client draws and every escape sequence would need care. An overlay leaves the line untouched.
