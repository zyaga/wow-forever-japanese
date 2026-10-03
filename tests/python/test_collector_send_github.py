"""The collector-check workflow (read as text; the pipeline has no YAML dependency)."""

import re


def _wf(root):
    return (root / ".github/workflows/collector-check.yml").read_text(encoding="utf-8")


def test_workflow_runs_only_on_sends_with_least_permissions(root):
    wf = _wf(root)
    assert re.search(r"^on:\n  issues:\n    types: \[opened, edited\]", wf, re.M)
    assert "if: contains(github.event.issue.labels.*.name, 'collector-send')" in wf
    perms = re.search(r"^permissions:\n((?:  .*\n)+)", wf, re.M).group(1)
    assert [ln.strip() for ln in perms.splitlines()] == ["contents: read"]
    job = re.search(r"^    permissions:\n((?:      .*\n)+)", wf, re.M).group(1)
    assert sorted(ln.strip() for ln in job.splitlines()) == ["contents: read", "issues: write"]
    assert "python -m wfj collector check --body-file" in wf


def test_workflow_never_puts_the_issue_text_in_a_script(root):
    wf = _wf(root)
    for m in re.finditer(r"\$\{\{\s*github\.event\.issue\.(\w+)", wf):
        line = wf[wf.rfind("\n", 0, m.start()) + 1 : wf.find("\n", m.start())]
        if m.group(1) == "number" and line.strip().startswith("group:"):
            continue
        assert re.match(r"^\s+[A-Z_]+: \$\{\{", line) or line.strip().startswith("if:"), line


def test_workflow_runs_one_at_a_time_briefly_and_keeps_no_token(root):
    wf = _wf(root)
    assert "concurrency:\n  group: collector-check-${{ github.event.issue.number }}\n  cancel-in-progress: true" in wf
    assert "timeout-minutes: 5" in wf
    assert "persist-credentials: false" in wf
    assert 'elif [ "$code" -eq 1 ]; then echo "ok=false" >> "$GITHUB_OUTPUT"; else exit "$code"; fi' in wf
    assert '[ -s "$RUNNER_TEMP/summary.md" ]' in wf
    assert 'gh issue comment "$ISSUE" --edit-last --create-if-none --body-file' in wf
    assert "--add-label" in wf and "collector-ok" in wf and "collector-broken" in wf
