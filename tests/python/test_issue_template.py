"""The collector-dump issue form states what the file holds and asks for the build."""

import re


def test_collector_dump_issue_form(root):
    path = root / ".github/ISSUE_TEMPLATE/collector-dump.yml"
    text = path.read_text(encoding="utf-8")
    for top in ("name:", "description:", "body:"):
        assert re.search(rf"^{top}", text, re.M), top
    for field_id in ("id: client", "id: client-build", "id: addon-version", "id: dump", "id: consent"):
        assert field_id in text, field_id
    assert text.count("required: true") >= 4
    assert "type: dropdown" in text and "type: checkboxes" in text
    assert "WFJ_Collector" in text
    for word in ("character", "account", "realm", "location"):
        assert word in text, word
    collector = (root / "addon/WoWForeverJapanese/Core/Collector.lua").read_text(encoding="utf-8")
    assert "issues/new?template=collector-dump.yml" in collector
