# ADR-078: Our font in the shared font registry

- **Status:** Accepted
- **Date:** 2026-11-11
- **Deciders:** the maintainer
- **Related:** [ADR-004](004-zero-runtime-dependencies.md) (zero runtime dependencies, narrowed here) · [ADR-073](073-dialogue-ui-windows-get-our-japanese.md) (Dialogue UI's windows) · [Addon modules](../architecture/addon-modules.md) · [App capabilities → Ellesmere UI](../app-capabilities.md#ellesmere-ui)

## Context

Ellesmere UI is a full interface replacement addon. It restyles the game's windows and sets its own font directly on the text in them, on every window show and every tab update. That happens after this addon has put the Japanese in. The fonts Ellesmere UI brings have no Japanese letters, so the Japanese shows as empty boxes: the settings window's tabs and title, the character window's headers, the mailbox and Auction House tabs, and an NPC window opened a second time.

Ellesmere UI lets the player choose the font it uses, from the fonts registered in the shared font registry, LibSharedMedia-3.0. This addon's bundled font has the Japanese letters and Latin letters, but it was not in that registry, so the player could not choose it.

[ADR-004](004-zero-runtime-dependencies.md) says the addon depends on no other addon and embeds no library. Using a registry another addon has loaded needs a written exception, as Dialogue UI's windows did ([ADR-073](073-dialogue-ui-windows-get-our-japanese.md)). The maintainer approved it on 2026-11-11.

## Decision

- `UI/Font.lua` gets `Font.share()`, run once at load from `Main.lua` (load step `fontshare`).
- It looks up the global `LibStub`, asks it silently for `LibSharedMedia-3.0`, and calls `Register("font", "WoW Forever Japanese", <the bundled font's path>, <the library's western bit>)`. It runs once per session.
- With no `LibStub`, no such library, or a registry that raises or refuses, nothing happens and nothing errors.
- Nothing of the library is shipped, embedded or copied. No dependency field names it. The addon reads nothing back from it.
- The player does the rest: in Ellesmere UI's options (`/eui`), on the Fonts page, Global Font is set to "WoW Forever Japanese".
- The addon does not watch or re-apply fonts on text another addon restyles.

## Rationale

- The other addon owns the font of the windows it restyles, and it already has a setting for it. Giving that setting a font that can draw Japanese fixes every window it restyles at once, including ones not reported yet.
- The registry is the shared way addons offer fonts to each other. Registering is one guarded call at load and costs a player without such an addon nothing.
- The font is registered with the library's western bit, since Forever is played on a western-locale client.

## Consequences

- With the font picked, the windows Ellesmere UI restyles show the Japanese. The maintainer confirmed this in game on 2026-11-11 for the character window and the other reported windows.
- English text in those windows is then drawn in this font's Latin letters, since Ellesmere UI uses one font for the whole window.
- The player has to pick the font once. Until then the empty boxes stay. The README and the CurseForge page say what to pick.
- Any other addon that reads the same registry lists the font too, and a player may pick it there.
- The font is offered once, at this addon's load, with the registry's western flag. A registry brought only by an addon that loads after this one is not offered it, and the registry itself turns the font down on a Korean, Chinese or Russian client. Ellesmere UI loads first, and Forever's client is English, so neither case arises there.
- Ellesmere UI's own windows and options stay English. Translating them is out of scope.
- Ellesmere UI's chat window is not supported. Its Chat module hides the game's chat text and shows its own window, fed with the game's English lines, so the Japanese this addon writes into the game's chat frames is not seen while that module is on. Global Font also applies to that chat window. A player who wants Japanese chat turns the Chat module off in the addon list.
- The no-dependencies principle has a second written exception. It is narrower than the first: one call into a library that is already loaded, and nothing read back.
- If the registry's `Register` changes its arguments, the call is refused or raises inside the guard, the font is not listed, and nothing else breaks.

## Alternatives considered
- **Watch the text and put the Japanese font back each time another addon changes it.** Rejected by the maintainer: it would add work and risk for every player, including the ones without such an addon, and the two addons would keep writing over each other.
- **Hook Ellesmere UI's skinning so it uses the bundled font on Japanese text.** Not possible: the helper that sets its font is private to that addon, so there is nothing to hook.
