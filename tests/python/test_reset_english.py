"""`wfj.dev.reset_english`: a rebuild keeps the English a client recorded in game and nothing else."""

import json

from wfj.dev.reset_english import reset


def test_keeps_collector_lines_only(tmp_path):
    q = tmp_path / "quest"
    q.mkdir()
    rows = [
        {"id": 458, "field": "completion", "en": "Forever's text", "hash": "0" * 16, "src": "collector@1.60.1.70170"},
        {"id": 458, "field": "title", "en": "Title", "hash": "1" * 16, "src": "wdb@1.60.1.70170"},
    ]
    (q / "quest-0000.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
    (q / "quest-0001.jsonl").write_text(json.dumps(rows[1]) + "\n", encoding="utf-8")
    assert reset(tmp_path) == (1, 2)
    assert [json.loads(ln)["src"] for ln in (q / "quest-0000.jsonl").read_text().splitlines()] == [rows[0]["src"]]
    assert not (q / "quest-0001.jsonl").exists()
