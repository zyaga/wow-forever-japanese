"""The collector-send issue form states what a send holds and has the box the send window's link fills in."""

import re


def test_collector_send_issue_form(root):
    text = (root / ".github/ISSUE_TEMPLATE/collector-send.yml").read_text(encoding="utf-8")
    for top in ("name:", "description:", "body:"):
        assert re.search(rf"^{top}", text, re.M), top
    assert re.search(r'^labels: \["collector-send"\]$', text, re.M)
    for field_id in ("id: dump", "id: note", "id: consent"):
        assert field_id in text, field_id
    assert "type: checkboxes" in text and text.count("required: true") >= 2
    for word in ("character", "account", "realm", "location", "WoWForeverJapanese.lua", "WFJC1:", "I sent it"):
        assert word in text, word
    assert not (root / ".github/ISSUE_TEMPLATE/collector-dump.yml").exists()


def test_the_link_and_the_form_agree(root):
    """The send window's link opens this form and fills its `dump` box; the check reads the box by its label."""
    from wfj.io import collector_send

    collector = (root / "addon/WoWForeverJapanese/Core/Collector.lua").read_text(encoding="utf-8")
    send = (root / "addon/WoWForeverJapanese/Core/CollectorSend.lua").read_text(encoding="utf-8")
    form = (root / ".github/ISSUE_TEMPLATE/collector-send.yml").read_text(encoding="utf-8")
    assert "issues/new?template=collector-send.yml" in collector
    assert '"&dump="' in send
    assert f'CollectorSend.PREFIX = "{collector_send.PREFIX}"' in send
    assert f"label: {collector_send.DUMP_LABEL}\n" in form
    assert "label: Permission\n" in form


def test_the_bug_link_and_the_bug_form_agree(root):
    """The report window's bug link fills the bug form's fields by their ids, and opens the idea form by name."""
    report = (root / "addon/WoWForeverJapanese/Core/BugReport.lua").read_text(encoding="utf-8")
    bug = (root / ".github/ISSUE_TEMPLATE/bug-report.yml").read_text(encoding="utf-8")
    assert '"bug-report.yml"' in report and '"idea.yml"' in report
    assert (root / ".github/ISSUE_TEMPLATE/idea.yml").is_file()
    fields = dict(re.findall(r'(build|version|errors) = "([a-z-]+)"', report))
    assert fields == {"build": "client-build", "version": "addon-version", "errors": "errors"}
    for field_id in fields.values():
        assert re.search(rf"^    id: {field_id}$", bug, re.M), field_id
    assert "/wfj bug" in bug
