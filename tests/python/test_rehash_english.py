"""dev/rehash_english: a hash change re-stamps translations and moves a gossip key with its readings."""

import json
from pathlib import Path

from wfj.core.hashing import key
from wfj.core.normalize import normalize_v1
from wfj.dev import rehash_english
from wfj.io.jsonl_store import Store

SPACED = "A favor for me, $g lad : lass;?"
OLD = "0000000000000001"


def _write(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


def _gossip(root: Path, id_: str, en: str, provenance: dict) -> None:
    _write(root / "english" / "gossip" / f"gossip-{id_[:2]}.jsonl",
           [{"id": id_, "field": "text", "en": en, "hash": id_, "src": "vmangos@x"}])
    _write(root / "gossip" / f"gossip-{id_[:2]}.jsonl",
           [{"id": id_, "field": "text", "ja": "若いの？", "status": "trusted", "checks": [],
             "provenance": provenance, "english": {"hash": id_, "src": "gossip-key@normalize_v1"}}])
    _write(root / "reading" / "gossip" / f"gossip-{id_[:2]}.jsonl",
           [{"id": id_, "field": "text", "words": []}])


def test_a_gossip_key_moves_with_its_translation_and_reading(tmp_path):
    _gossip(tmp_path, OLD, SPACED, {"class": "machine"})
    changes, drop, problems = rehash_english.plan(tmp_path)
    assert (problems, drop) == ([], {})
    counts = rehash_english.apply(tmp_path, changes, drop, dry_run=False)
    new = key(normalize_v1(SPACED))
    assert counts["rekeyed"] == 1 and counts["readings"] == 1
    assert [line["id"] for line in Store(tmp_path, english=True).load("gossip")] == [new]
    line = Store(tmp_path).load("gossip")[0]
    assert (line["id"], line["english"]["hash"]) == (new, new)
    assert Store(tmp_path / "reading").load("gossip")[0]["id"] == new
    assert rehash_english.plan(tmp_path)[0] == {}  # a second run finds nothing


def test_a_quest_translation_is_restamped_not_moved(tmp_path):
    _write(tmp_path / "english" / "quest" / "quest-0000.jsonl",
           [{"id": 233, "field": "description", "en": SPACED, "hash": OLD, "src": "wdb@x"}])
    _write(tmp_path / "quest" / "quest-0000.jsonl",
           [{"id": 233, "field": "description", "ja": "若いの？", "status": "trusted", "checks": [],
             "provenance": {"class": "machine"}, "english": {"hash": OLD, "src": "wdb@x"}}])
    changes, drop, _ = rehash_english.plan(tmp_path)
    rehash_english.apply(tmp_path, changes, drop, dry_run=False)
    line = Store(tmp_path).load("quest")[0]
    assert (line["id"], line["english"]["hash"]) == (233, key(normalize_v1(SPACED)))


def test_a_taken_key_drops_the_moving_line_unless_it_is_hand_written(tmp_path):
    new = key(normalize_v1(SPACED))
    _gossip(tmp_path, OLD, SPACED, {"class": "machine"})
    _gossip(tmp_path, new, "A favor for me, $glad:lass;?", {"class": "machine"})  # gendered too: it stays
    changes, drop, problems = rehash_english.plan(tmp_path)
    assert (drop, problems) == ({"gossip": {OLD}}, [])
    counts = rehash_english.apply(tmp_path, changes, drop, dry_run=True)
    assert counts["dropped"] == 1
    assert len(Store(tmp_path, english=True).load("gossip")) == 2  # dry run writes nothing
    rehash_english.apply(tmp_path, changes, drop, dry_run=False)
    assert [line["id"] for line in Store(tmp_path, english=True).load("gossip")] == [new]
    assert [t["id"] for t in Store(tmp_path).load("gossip")] == [new]
    assert [r["id"] for r in Store(tmp_path / "reading").load("gossip")] == [new]

    _gossip(tmp_path, OLD, SPACED, {"class": "human"})
    _, _, problems = rehash_english.plan(tmp_path)
    assert problems and "hand-written" in problems[0]


def test_the_gendered_line_keeps_a_shared_key_and_two_movers_on_one_key_stop(tmp_path):
    new = key(normalize_v1(SPACED))
    _gossip(tmp_path, OLD, SPACED, {"class": "machine"})  # `$G`: speaks for both wordings
    _gossip(tmp_path, new, "A favor for me, lad?", {"class": "machine"})  # a male-only capture at the new key
    changes, drop, problems = rehash_english.plan(tmp_path)
    assert (drop, problems) == ({"gossip": {new}}, [])
    rehash_english.apply(tmp_path, changes, drop, dry_run=False)
    [line] = Store(tmp_path, english=True).load("gossip")
    assert (line["id"], line["en"]) == (new, SPACED)
    assert [t["id"] for t in Store(tmp_path).load("gossip")] == [new]

    other = "1100000000000002"
    _gossip(tmp_path / "two", OLD, SPACED, {"class": "machine"})
    _gossip(tmp_path / "two", other, "A favor for me, $g lad:lass;?", {"class": "machine"})
    _, _, problems = rehash_english.plan(tmp_path / "two")
    assert problems and "both move to" in problems[0]


def test_a_hand_written_variant_in_conflicts_stops_a_drop(tmp_path):
    new = key(normalize_v1(SPACED))
    _gossip(tmp_path, OLD, "A favor for me, $g lad : lass;?", {"class": "machine"})
    _gossip(tmp_path, new, "A favor for me, $glad:lass;?", {"class": "machine"})  # also gendered: the mover drops
    shard = tmp_path / "gossip" / f"gossip-{OLD[:2]}.jsonl"
    row = json.loads(shard.read_text())
    row["conflicts"] = [{"ja": "若いの？", "provenance": {"class": "human"}}]
    shard.write_text(json.dumps(row, ensure_ascii=False) + "\n")
    _, _, problems = rehash_english.plan(tmp_path)
    assert problems and "hand-written" in problems[0]


def test_a_drop_that_would_lose_the_only_translation_stops(tmp_path):
    new = key(normalize_v1(SPACED))
    _gossip(tmp_path, OLD, "A favor for me, $g lad : lass;?", {"class": "machine"})
    english = tmp_path / "english" / "gossip" / f"gossip-{new[:2]}.jsonl"
    _write(english, [{"id": new, "field": "text", "en": "A favor for me, $glad:lass;?", "hash": new, "src": "c@x"}])
    _, _, problems = rehash_english.plan(tmp_path)
    assert problems and "only translation" in problems[0]
