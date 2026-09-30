"""ADR-034: a line whose English left the store (its id is no longer listed by Forever) keeps the baseline it
was last checked against, so English that comes back reworded makes it stale, not fresh."""

from wfj.cmd.check import build_scopes, check_type
from wfj.core.hashing import key
from wfj.core.model import english_line, entry, provenance
from wfj.core.normalize import normalize_v1
from wfj.io.jsonl_store import Store

WDB = "wdb@1.15.9.69722"
PROV = provenance("human", "cqjt@3446c82", "2026-09-13", translator="Tammy")
TITLE, REWORDED = "Digging for Gold", "Digging for Silver"


def _scopes(tmp_path, en=None):
    store = Store(tmp_path, english=True)
    store.save("quest", [english_line(254, "title", en, key(normalize_v1(en)), WDB)] if en else [])
    return build_scopes(store, "quest")


def _line(english):
    ln = entry(254, "title", "土掘り", prov=PROV)
    ln["english"] = english
    return ln


def test_no_english_id_keeps_the_prior_baseline(tmp_path):
    prior = {"hash": key(normalize_v1(TITLE)), "src": WDB}
    [out] = check_type([_line(prior)], _scopes(tmp_path), set())
    assert out["status"] == "rejected" and out["reasons"] == ["no_english_id"]
    assert out["english"] == prior


def test_no_english_id_without_a_baseline_stays_none(tmp_path):
    [out] = check_type([_line(None)], _scopes(tmp_path), set())
    assert out["english"] is None


def test_english_back_reworded_is_stale(tmp_path):
    prior = {"hash": key(normalize_v1(TITLE)), "src": WDB}
    [kept] = check_type([_line(prior)], _scopes(tmp_path), set())
    [back] = check_type([kept], _scopes(tmp_path, REWORDED), set())
    assert back["status"] == "stale"
    assert back["english"] == prior


def test_english_back_unchanged_is_trusted(tmp_path):
    prior = {"hash": key(normalize_v1(TITLE)), "src": WDB}
    [kept] = check_type([_line(prior)], _scopes(tmp_path), set())
    [back] = check_type([kept], _scopes(tmp_path, TITLE), set())
    assert back["status"] == "trusted"


def test_no_english_id_variants_go_in_one_order_whatever_the_history(tmp_path):
    """An incremental check (machine promoted earlier) and a rebuild (human first) store the same line."""
    machine = {"class": "machine", "model": "m", "source": "draft-x-sg4@2026-09-20", "imported": "2026-09-20"}
    human_first = _line(None)
    human_first["conflicts"] = [{"ja": "機械訳", "provenance": machine}]
    machine_first = entry(254, "title", "機械訳", prov=machine)
    machine_first["english"] = None
    machine_first["conflicts"] = [{"ja": "土掘り", "provenance": PROV}]
    a = check_type([human_first], _scopes(tmp_path), set())[0]
    b = check_type([machine_first], _scopes(tmp_path), set())[0]
    assert a == b
    assert a["ja"] == "土掘り" and a["provenance"]["class"] == "human"
