# Runbook: take a player's collector send

## Goal

Turn a player's collector send (a GitHub issue labelled `collector-send`) into English in `data/english/` and a pull request. The send is the English the player's game recorded and the addon could not recognise, packed by the game into one string, or, when that is too long to paste, the player's SavedVariables file attached to the same issue. How it works: [Collector](../systems/collector.md#send-corecollectorsendlua-uicollectorsendwindowlua); decision: [ADR-056](../adr/056-collector-send-string.md).

## Prerequisites

- The GitHub CLI signed in to the repo (`gh issue view` reads the issue).
- The repo venv (`.venv`); `make` uses it when it exists, or pass `PY=<repo>/.venv/bin/python`.
- A branch for the import (`data/<slug>`); the pull request carries `Fixes #N`.
- Network access when the send is an attached file: intake downloads it from the issue.

## Labels

| Label | Set by | Meaning |
|---|---|---|
| `collector-send` | the issue form | a player's collector send; the `collector-check` workflow runs on it |
| `collector-ok` | `collector-check` | the send reads; the comment counts its entries by kind, its builds, the addon version, how it was sent and the entries left out by reason |
| `collector-broken` | `collector-check` | the send does not read (cut, edited, nothing found, a format the pipeline does not read, or no line that can be imported); the comment says why and asks the player to copy it again with `/wfj collector send all`. The check runs again when the player edits the issue. |

Take only issues labelled `collector-ok`. The comment never shows the English: read it in the diff after the import.

## Steps

1. **Intake.** `make collector-intake ISSUE=N`
   - Reads the issue with `gh issue view`, refuses it unless the form's **Permission** box is ticked, reads the send (the `WFJC1:` string, or the attached zip or `.lua`), and merges it into `data/english/` with the same rules as `make import-collector` ([Local setup → Collector dumps](local-setup.md#collector-dumps)).
   - Offline, from a saved issue body: `make collector-intake ISSUE=N BODY=<file>`.
   - It prints `english collector: issue #N · <entries> entries · builds …`, the per-type table (added, unchanged, replaced, differs), the rejected counts, then a `replaced:` list (`  <type> <id> <field> (was <src>)`) and the `differs` list.
2. **Review, then check.** Read the `replaced:` list first: each line there is English the send put in place of another source's, and it is what the data diff should be checked against. Then `make check`. Collector quest and gossip English is consulted, so the import can move a quest line's hash and make it `stale`. Review the delta (`git diff data/`) before going on.
3. **Generate and validate.** `make generate validate VALIDATE_FLAGS="--base origin/main"`.
4. **Coverage.** `make coverage`, committed in the same branch.
5. **Ship.** Open a pull request with `Fixes #N` in the body. Fill the Data table: the English lines added and replaced, by source (`collector@<build>`); no translation changes provenance.

## Verify

- Running `make collector-intake ISSUE=N` again prints every line as unchanged and leaves `git status` clean.
- `make validate` passes and `docs/operations/coverage.md` is regenerated in the branch.
- The quests the send newly made `stale` are the ones whose English Forever changed: they get translated in a later batch, with readings.

## Rollback / troubleshooting

| Problem | Fix |
|---|---|
| `collector-check` failed with no comment | An internal error (exit 3), not a broken send: read the run's log. Re-run the workflow, or edit the issue to trigger it. |
| `collector intake: issue #N: the Permission box is not ticked; nothing imported` | Ask the player to tick it (editing the issue is enough). |
| `collector intake: could not read issue #N` | `gh` failed (not signed in, no network, no such issue); the message says which. |
| `collector intake: issue #N: the text is not complete …` | The string was cut or edited; the workflow will have labelled `collector-broken`. Wait for the player to edit the issue. |
| `the attachment could not be downloaded` or `… is not a zip file that opens` | No network, or GitHub refused; run intake again later. Only `github.com/user-attachments` links are ever downloaded. |
| `the text is in a format this pipeline does not read (v = …)` | A newer addon packed it; update the pipeline first. |
| Undo an import | Revert the pull request, or `git checkout -- data/english` before committing. |
| Stop the workflow | Disable `collector-check` from the Actions tab; no release needed. |

## Related
- [Collector (system)](../systems/collector.md) · [ADR-056](../adr/056-collector-send-string.md) · [ADR-013](../adr/013-collector-english.md) · [Local setup → Collector dumps](local-setup.md#collector-dumps) · [Fix reports](fix-reports.md) · [Coverage](coverage.md)
