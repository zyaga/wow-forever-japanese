# ADR-070: Issue labels come from a list in the repo

- **Status:** Accepted
- **Date:** 2026-11-05
- **Related:** [ADR-056](056-collector-send-string.md) (the collector send string) · [ADR-045](045-player-fix-reports.md) (player fix reports) · [ADR-046](046-one-action-release.md) (one-action release: workflows read-only by default) · [Collector sends](../operations/collector-sends.md) · [Fix reports](../operations/fix-reports.md)

## Context

A player's collector send and fix report each arrive as a GitHub issue opened from an issue form. The form names a
label (`collector-send`, `translation-report`), and the check workflow for that kind of issue runs only on issues
that carry it (`collector-check`, `report-check`). The check workflows then add their own result labels
(`collector-ok` / `collector-broken`, `report-ok` / `report-broken`).

GitHub drops a form's label when the repository has no label of that name. Nothing reports it: the issue opens with
no label, the check is skipped, and the player sees no comment. Labels were never part of the repository's files.
When the public repository was recreated, the `collector-send` label was lost; an older, unused `collector-dump`
label remained. From then on every player collector send opened without its label and was never checked.

The check could not be re-run by hand either: `collector-check` ran only when an issue was opened or edited, so
adding the label to a waiting issue started nothing.

## Decision

1. **The labels are a list in the repo.** `.github/labels.tsv` (columns `name`, `color`, `description`) holds every
   label an issue form names and every label a check workflow looks for, adds or creates: `bug`, `enhancement`,
   `translation-report`, `report-ok`, `report-broken`, `collector-send`, `collector-ok`, `collector-broken`.
2. **A workflow applies the list.** `.github/workflows/labels.yml` runs on every push to `main` and on demand
   (**Actions → labels → Run workflow**). For each line it runs `gh label create <name> --color --description
   --force`: a missing label is created, a listed label gets its colour and description back. It never deletes or
   renames a label, and leaves labels that are not in the list alone. The workflow token is read-only by default;
   only its one job holds `issues: write`.
3. **Labelling a send checks it.** `collector-check` also runs on `labeled`, and then only when the label added is
   `collector-send`. Adding the label to an issue checks it; removing it and adding it again runs the check again.
   The bot's own `collector-ok` and `collector-broken` labels start no run.
4. **A test keeps the list complete.** `tests/python/test_labels.py` fails when an issue form, or a workflow's
   label check, label add or `gh label create`, names a label the list lacks, and when a workflow's own
   `gh label create` gives a colour or description other than the list's.

## Consequences

- A deleted or lost label comes back at the next merge to `main`, or at once with a manual run of the labels
  workflow. Its colour and description go back to the list's on the same run.
- A new issue form or check label has to be added to `.github/labels.tsv` in the same pull request, or the test
  fails.
- One more workflow can write to the repository. Its write access is limited to `issues: write` in one job, and it
  runs on pushes to `main` and by hand, never on a pull request.
- `report-check` keeps its `opened` / `edited` trigger: its labels are in the list, and no fix report has needed a
  re-run.
- A label renamed by hand in the repository settings is not renamed back: the sync creates the listed name again,
  and the old one stays until the maintainer removes it.

## Alternatives considered

- **Trigger the checks on the form's heading instead of the label.** Rejected: the label is how the maintainer and
  players see what an issue is, and the issue list is filtered by it. A check that ran without the label would
  leave the label missing all the same.
- **Check the live repository's labels in CI.** Rejected: it needs network access and a token in the pull request
  checks, and it reports a missing label without putting it back.
