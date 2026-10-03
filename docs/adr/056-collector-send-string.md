# ADR-056: Collected English is sent as a string in an issue link

- **Status:** Accepted
- **Date:** 2026-10-03
- **Related:** [ADR-013](013-collector-english.md) (what the collector records) · [ADR-006](006-git-repo-is-the-database.md) (the git repo is the database) · [ADR-045](045-player-fix-reports.md) (player fix reports, the same issue, check and intake pattern) · [ADR-046](046-one-action-release.md) (read-only workflow permissions)

## Context

The collector writes English the addon cannot recognise to `WFJ_Collector` in the player's SavedVariables
([ADR-013](013-collector-english.md)). Handing it off meant finding that file under the client folder, zipping it
and attaching it to an issue form. Few players finish that. An addon cannot reach the network or the clipboard,
but it can show text the player copies, and GitHub's new-issue link can prefill an issue form field. The Forever
client exposes `C_EncodingUtil` (JSON, zlib, Base64) to addons.

## Decision

1. **A string, packed by the client.** The addon packs the entries not sent before into `WFJC1:` + URL-safe
   Base64 of zlib-compressed JSON `{v, a, b, e}`: the format version (1), the addon version, the builds those
   entries were recorded on, and the entries in the dump's own fields (`t, i, f, h, e, b, n, p`; `b` indexes the
   string's own build list). It uses only the client's `C_EncodingUtil` (`SerializeJSON`, `CompressString` with
   zlib, `EncodeBase64` with the URL-safe alphabet). A client without them gets the file hand-off.
2. **One send is one issue.** When the whole new-issue URL (the form link plus `&dump=` and the percent-encoded
   string) is at most 6,000 characters, the string rides in the link. Measured against this repository's form
   while logged out, 6,590 characters redirect to the login page, 7,090 get a server error and 8,290 a 414, so
   6,000 leaves room for the browser and the login redirect. Otherwise the link opens the form and the string goes
   in the form's box by paste, at most 60,000 characters (the issue body holds 65,536). A string too long even for
   that becomes the SavedVariables file, zipped and attached to that same issue. Nothing is split across issues.
3. **A sent marker the player sets.** A top-level `sent = { [entry key] = h }` in `WFJ_Collector` records what was
   sent. The player sets it with an **I sent it** button, clicked after submitting the issue, because an addon
   cannot tell that a copy or a submit happened. A line replaced since it was sent has a new hash and is unsent
   again. There is no file version bump: an older addon keeps a top-level field it does not know.
   When the file itself is sent, I sent it marks only what that file holds: the client writes SavedVariables only
   at logout or `/reload`, so the addon remembers each entry's hash as it loaded the file and marks only entries
   still stored with it. The window counts the lines recorded since and asks for a `/reload` first.
4. **Lines that ship now are left out.** At pack time each entry gets the same "does Japanese ship for this
   English" check the recorder uses; a line a release has translated since it was recorded is left out and counted,
   and I sent it marks it too, so it never counts as unsent.
5. **A file from a newer version is not sent.** The window says the addon must be updated and offers nothing to
   click; this addon neither reads nor writes that file.
6. **Checked on the issue, imported by the maintainer.** The `collector-check` workflow decodes the string (or
   reads the attached file) and labels the issue `collector-ok` or `collector-broken`, with a comment of counts
   only, never the English. The maintainer imports it with `make collector-intake ISSUE=N`, through the same
   validation and merge as a file import.

## Consequences

- Sending takes clicks only, and the build and addon version travel inside the string.
- The string format is a contract between addon versions and the pipeline; a new shape needs a new prefix
  (`WFJC2:`), and the decoder refuses a `v` it does not read.
- The client's zlib output must decode in Python; zlib's checksum turns a mismatch into a broken label, not bad
  data. Every decoded entry goes through the same `check_entry` as a dump file, so a string carries nothing a file
  could not. Sizes are capped before decompressing (text 70,000 characters, JSON 4 MB, attachment 25 MB, the file inside
  a zip 8 MB), and only GitHub `user-attachments` links are downloaded.
- **Unverified until tried with a real send:** that a zip dragged into the form's text box becomes a
  `user-attachments` link the Actions runner can download without signing in, and that a link near 6,000
  characters opens the form for a player who is signed in to GitHub (the limits above were measured logged out).
- A pack marked sent but never submitted is recovered with `/wfj collector send all`.
- The `sent` map is part of the saved file: each row counts toward the 4 MB cap estimate (`#key + 30` bytes).

## Alternatives considered

- **Keep the file hand-off only:** the drop-off rate is the problem.
- **Several issues per large dump (forever-vo's parts):** one send must be one issue, so a reviewer reads one
  check and imports once.
- **Mark as sent when the window opens:** loses lines when the player closes the window without sending.
- **Our own Lua compressor:** more code than the client's built-in encoder, for no gain.
- **A sent flag on each entry:** an older addon's loader drops entries with unknown fields, so a downgrade would
  lose data.
