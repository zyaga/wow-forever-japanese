"""The translation-report issue form and the report-check workflow (read as text; the pipeline has no
YAML dependency; these check the few lines that matter)."""

import re


def _read(root, rel):
    return (root / rel).read_text(encoding="utf-8")


def _blocks(form):
    """The form's body items: `- type: X` blocks → [(type, text)]."""
    parts = re.split(r"^  - type: ", form, flags=re.M)[1:]
    return [(p.split("\n", 1)[0].strip(), p) for p in parts]


def test_issue_form_fields(root):
    form = _read(root, ".github/ISSUE_TEMPLATE/translation-report.yml")
    assert re.search(r'^labels: \["translation-report"\]$', form, re.M)
    items = {re.search(r"id: (\S+)", text).group(1): (kind, text) for kind, text in _blocks(form) if "id: " in text}
    assert set(items) == {"report", "credit", "consent"}
    kind, text = items["report"]
    assert kind == "textarea" and "label: Report" in text and "render: text" in text and "required: true" in text
    kind, text = items["credit"]
    assert kind == "input" and "label: Credit me as" in text and "required: false" in text
    kind, text = items["consent"]
    assert kind == "checkboxes" and "required: true" in text


def test_form_labels_match_what_intake_reads(root):
    from wfj.cmd import fix_report

    form = _read(root, ".github/ISSUE_TEMPLATE/translation-report.yml")
    assert "label: Credit me as" in form
    assert fix_report.form_sections("### Credit me as\n\nX\n")["Credit me as"] == "X"


def test_workflow_runs_only_on_reports_with_least_permissions(root):
    wf = _read(root, ".github/workflows/report-check.yml")
    assert re.search(r"^on:\n  issues:\n    types: \[opened, edited\]", wf, re.M)
    assert "if: contains(github.event.issue.labels.*.name, 'translation-report')" in wf
    # read-only at the top (the workflow policy, ADR-046); the check job alone may write the issue it reads
    perms = re.search(r"^permissions:\n((?:  .*\n)+)", wf, re.M).group(1)
    assert [ln.strip() for ln in perms.splitlines()] == ["contents: read"]
    job = re.search(r"^    permissions:\n((?:      .*\n)+)", wf, re.M).group(1)
    assert sorted(ln.strip() for ln in job.splitlines()) == ["contents: read", "issues: write"]
    assert "python -m wfj report check --body-file" in wf


def test_workflow_never_puts_the_issue_text_in_a_script(root):
    wf = _read(root, ".github/workflows/report-check.yml")
    for m in re.finditer(r"\$\{\{\s*github\.event\.issue\.(\w+)", wf):
        line = wf[wf.rfind("\n", 0, m.start()) + 1: wf.find("\n", m.start())]
        if m.group(1) == "number" and line.strip().startswith("group:"):
            continue  # the concurrency group: the issue number, a number the event gives, not text
        # only as an env value (or the job condition), never inside a run: block's text
        assert re.match(r"^\s+[A-Z_]+: \$\{\{", line) or line.strip().startswith("if:"), line


def test_workflow_runs_one_at_a_time_briefly_and_keeps_no_token(root):
    # a newer edit cancels an older run; a hung run stops; checkout leaves no token behind
    wf = _read(root, ".github/workflows/report-check.yml")
    assert "concurrency:\n  group: report-check-${{ github.event.issue.number }}\n  cancel-in-progress: true" in wf
    assert "timeout-minutes: 5" in wf
    assert "persist-credentials: false" in wf
    # only 0 / 1 lead to a comment and a label; anything else fails the job, and an empty summary is never posted
    assert 'elif [ "$code" -eq 1 ]; then echo "ok=false" >> "$GITHUB_OUTPUT"; else exit "$code"; fi' in wf
    assert '[ -s "$RUNNER_TEMP/summary.md" ]' in wf
    # one comment per issue, however often the issue is edited
    assert 'gh issue comment "$ISSUE" --edit-last --create-if-none --body-file' in wf
