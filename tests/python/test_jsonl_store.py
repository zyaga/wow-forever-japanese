from pathlib import Path

from wfj.core.model import entry, provenance
from wfj.io.jsonl_store import Store, shard_name

PROV = provenance("human", "cqjt@3446c82", "2026-09-13", translator="Tammy")


def test_shard_math():
    assert shard_name("quest", 2) == "quest-0000.jsonl"
    assert shard_name("quest", 999) == "quest-0000.jsonl"
    assert shard_name("quest", 1000) == "quest-0001.jsonl"
    assert shard_name("item", 90715) == "item-0090.jsonl"
    assert shard_name("gossip", "5f3a91c20b7de441") == "gossip-5f.jsonl"


def _lines():
    return [
        entry(1500, "title", "b", prov=PROV),
        entry(2, "completion", "z", prov=PROV),
        entry(2, "title", "a", prov=PROV),
        entry(1500, "description", "c", prov=PROV),
    ]


def test_sorted_by_id_then_field_order(tmp_path: Path):
    store = Store(tmp_path)
    counts = store.save("quest", _lines())
    assert counts == {"quest-0000.jsonl": 2, "quest-0001.jsonl": 2}
    loaded = store.load("quest")
    assert [(ln["id"], ln["field"]) for ln in loaded] == [
        (2, "title"),
        (2, "completion"),
        (1500, "title"),
        (1500, "description"),
    ]
    text = (tmp_path / "quest" / "quest-0000.jsonl").read_text(encoding="utf-8")
    assert text.endswith("\n") and text.count("\n") == 2


def test_roundtrip_is_noop(tmp_path: Path):
    store = Store(tmp_path)
    store.save("quest", _lines())
    before = {p.name: p.read_bytes() for p in (tmp_path / "quest").glob("*.jsonl")}
    store.save("quest", store.load("quest"))
    after = {p.name: p.read_bytes() for p in (tmp_path / "quest").glob("*.jsonl")}
    assert before == after


def test_stale_shards_removed(tmp_path: Path):
    store = Store(tmp_path)
    store.save("quest", _lines())
    store.save("quest", [ln for ln in _lines() if ln["id"] == 2])
    assert sorted(p.name for p in (tmp_path / "quest").glob("*.jsonl")) == ["quest-0000.jsonl"]


def test_english_store_lives_under_english(tmp_path: Path):
    from wfj.core.model import english_line

    Store(tmp_path, english=True).save("item", [english_line(117, "name", "Tough Jerky", "0" * 16, "wago@1")])
    assert (tmp_path / "english" / "item" / "item-0000.jsonl").exists()
