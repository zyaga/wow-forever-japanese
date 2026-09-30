# Runbook: take a player's fix report

## Goal

Turn a player's fix report (a GitHub issue labelled `translation-report`) into data and a PR: the fixed lines ship their new Japanese with readings and meanings, the reporter is credited, and the issue gets a reply. The maintainer decides which reports to take and merges the PR. How it works: [Fix reports](../systems/fix-reports.md); decision: [ADR-045](../adr/045-player-fix-reports.md).

## Prerequisites

- The GitHub CLI signed in to the repo (`gh issue view` reads the issue).
- The repo venv (`.venv`); `make` uses it when it exists.
- A branch for the report (the PR carries `Fixes #N`).
- A drafting model to write the decisions (step 2).

**The working folder.** Intake writes to `batches/reports/issue-N/` at the repository root. `batches/` is a local working folder: it is ignored by git and never part of the repository. What ships is the result in `data/`, the readings and `ATTRIBUTION.md`.

## Labels

| Label | Set by | Meaning |
|---|---|---|
| `translation-report` | the issue form | a player's fix report; the `report-check` workflow runs on it |
| `report-ok` | `report-check` | the paste reads; the comment lists each fix as ready or skipped |
| `report-broken` | `report-check` | the paste does not read (cut, edited, no report); the comment says why and asks for a fresh copy. The check runs again when the player edits the issue. |

Take only issues labelled `report-ok`. The workflow never judges a translation; that is the drafting step.

## Steps

1. **Intake.** `make report-intake ISSUE=N`
   - Reads the issue with `gh issue view`, parses the report, resolves each fix against `data/`, and writes the working folder `batches/reports/issue-N/`: `report.txt`, `meta.json`, `triage.jsonl` (fixes to decide), `skipped.jsonl` (lines changed since, not shipped, or not in the data).
   - Offline, from a saved issue body: `make report-intake ISSUE=N REPORT=<file>`. Override the credit name: `CREDIT="<name>"`. Redo an existing triage: `FORCE=1`.
   - The credit name is the form's "Credit me as", else the author's GitHub login: letters, digits, spaces and `._-` only (it ships in `ATTRIBUTION.md`).
   - The form's **Permission** box is read again at intake: without it, intake says so and apply refuses any `use` (the player's own Japanese).
   - A report already applied can be taken in again (`FORCE=1`): the lines it rewrote still match.
   - A `gh` failure prints its message; nothing is half-written (the four files move into place together).
2. **Draft.** The drafting model writes `decisions.jsonl` in the working folder, one row per triage row: `use` (the player's Japanese, edited as little as needed), `rewrite` (a new line) or `keep` (with a reason a player would accept). Every changed quest, gossip, UI or plain-text book line also gets its `words` (the word list with readings and meanings, as in [Translation batches](translation-batches.md#readings-for-a-batch)). Check with the dry run until it prints no problem:

   ```bash
   cd pipeline && ../.venv/bin/python -m wfj report apply --issue N --model <model id> --dry-run
   ```
3. **Apply.** `make report-apply ISSUE=N MODEL=<model id>` (`DATE=YYYY-MM-DD` to pin the date)
   - Checks every decision first and writes nothing if one fails; refuses if a changed line would not ship under the pipeline's status rules (`check_type`: Japanese, names kept, numbers, tokens). `translate_lint` is not run; the drafting pass follows the style guide itself.
   - Writes the lines (provenance per ADR-045), imports their readings (`readings@report-N`), updates `ATTRIBUTION.md` → Correctors, writes `batches/reports/issue-N/reply.md`.
   - Then runs `make check generate validate coverage` (not `make data`).
4. **Reply.** Post `reply.md` on the issue (`gh issue comment N --body-file batches/reports/issue-N/reply.md`) once the maintainer has read it.
5. **Ship.** Open a pull request with `Fixes #N` in the body. State the provenance delta in the pull request's Data table: corrections from the player's Japanese, corrections the model wrote, machine rewrites. Run validate with `VALIDATE_FLAGS="--base origin/main"` before the PR.

## Verify

- `apply` prints `wrote n correction(s) · m machine rewrite(s) · kept k · already applied 0 · readings for r line(s)`.
- `make validate` passes, with no line owed a reading and no stale reading among the report's lines.
- `docs/operations/coverage.md` is regenerated in the same branch.
- `git diff ATTRIBUTION.md` shows only the Correctors section (when a player's own Japanese shipped).
- Running `make report-apply` again prints `already applied` for every changed line and changes nothing.

## Rollback / troubleshooting

| Problem | Fix |
|---|---|
| `report intake: … already has a triage` | Add `FORCE=1` to redo it (the triage is rebuilt from the issue). |
| `report-check` failed with no comment | An internal error (exit 3), not a broken paste: read the run's log. Re-run the workflow, or edit the issue to trigger it. |
| `report intake: could not read issue #N` | `gh` failed (not signed in, no network, no such issue); the message says which. |
| `report intake: the report does not read` | The paste is broken; the workflow will have labelled `report-broken`. Wait for the player to edit the issue. |
| `apply`: `the line's Japanese changed since intake; run intake again` | Another change landed on that line; re-run intake with `FORCE=1` and redraft that row. |
| `apply`: `the new Japanese would not ship (status …, reasons …)` | The line fails `check` (a name dropped, a token lost, …). Fix the decision's `ja`; nothing was written. |
| `apply`: `some readings were rejected` | The lines are written; fix the listed `words` and run apply again (it skips the lines already applied). |
| Undo an applied report | Revert the report's PR, or rule the correction `reject` and regenerate. |
| Stop the workflow | Disable `report-check` from the Actions tab; no release needed. |

## Related
- [Fix reports (system)](../systems/fix-reports.md) · [ADR-045](../adr/045-player-fix-reports.md) · [Translation batches](translation-batches.md) · [Coverage](coverage.md) · [Release](release.md)
