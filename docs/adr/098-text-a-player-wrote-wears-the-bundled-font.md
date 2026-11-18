# ADR-098: Text a player wrote wears the bundled font

- **Status:** Accepted
- **Date:** 2026-11-18
- **Deciders:** the maintainer
- **Related:** [Addon modules](../architecture/addon-modules.md) · [Testing strategy](../testing/strategy.md) · [ADR-080](080-our-font-in-the-shared-font-registry.md)

## Context

The client's own fonts hold no kana or kanji. The addon gives its bundled Japanese face to every line it translates,
so those lines draw correctly. Text a player wrote was never the addon's to translate, so nothing gave it that face:
a guild's message of the day, the guild information, a member's or officer's note, a rank's name, a community's
description, a guild bank tab's notes. A Japanese player who typed Japanese there saw a row of empty boxes, and so did
everyone in the guild. The chat input box already wore the bundled face for the same reason.

## Decision

1. **A typing box always wears the bundled face**, at its own size and flags, now and each time it shows (the client
   may put its font object back). What will be typed is not known, so the box cannot wait for Japanese to appear.
2. **Shown text wears it only while it holds Japanese.** Text with no kana, kanji or full-width form has its own font
   back, so a window with no Japanese in it looks as the client draws it.
3. **Nothing is translated, and none of it depends on the addon's switches.** The text is the player's, whatever
   language the game's own text is shown in: it draws with translation off, with the area off, and while the reveal
   key is held.
4. **One module holds the rule** (`UI/PlayerText.lua`): `box` for a typing box, `shown` for text as it stands,
   `follow` for text the client rewrites (a post-hook on the widget's `SetText`). A window's own module names its
   widgets and calls it. A line that can be either the game's or a player's (a member's note with no note set, a
   news row that is the message of the day) is offered to the dictionary first and takes this rule when the
   dictionary has nothing for it.
5. **A value the client marks secret is left alone.** It can be neither read nor matched, so the widget keeps the
   font it has.

## Rationale

- Keying on the text keeps the client's look. Giving the bundled face to every player-text widget would change the
  English font of every guild window for players who never type Japanese.
- A typing box is the one place where the rule cannot wait: the boxes would show while the player types.
- One module, because the rule was first written per window and missed the places that were listed by widget name:
  the guild news row and the roster's rank column show the same text through other widgets. The rule is now applied
  by who reads the text (the message of the day, the guild information, a note, a rank's name), in every widget
  that shows it.

## Consequences

- The window test reads every text region, typing box and HTML box and fails on Japanese drawn in a face other than
  the bundled one, so a window that shows player text without this rule is found by a run, with the widget's name.
- A SimpleHTML box's font is read and set through its paragraph text type. That plain text in such a box draws with
  the paragraph font was checked in game on the guild's message of the day.
- Places not covered yet are listed in the module docs: the guild news row's tooltip and the calendar events players
  write.

## Alternatives considered

- **The bundled face on every guild window widget.** Rejected: it changes the client's English font for everyone.
- **Replacing the client's font objects with the bundled face.** Rejected for the same reason: every window that
  uses the object would change, with or without Japanese in it.
