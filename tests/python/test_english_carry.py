"""Prior English hashes survive `import predecessor`, so `stale` is derived through the full `make data`
chain exactly as through `make import-english` + `make check` (ADR-003, ADR-012)."""

import shutil
from pathlib import Path

import pytest

from wfj.cmd import check
from wfj.cmd import import_ as imp
from wfj.io.jsonl_store import Store

DATE = "2026-09-13"
TYPES = ("quest", "item", "spell")
FIXTURES = Path(__file__).resolve().parents[2] / "tests/fixtures"
PFQUEST = FIXTURES / "pfquest/quests.excerpt.lua"
TITLE = '["T"] = "Sharptalon\\\'s Claw",'  # quest 2's title as the pfQuest excerpt escapes it
CHANGED = '["T"] = "Sharptalon\\\'s Talon",'  # a non-numeric English edit → stale, not rejected
# A lineage-only line: quest 14's title exists only in the QuestJapanizer input, not the predecessor's
MILITIA = '["T"] = "The People\\\'s Militia",'
MILITIA_CHANGED = '["T"] = "The Peoples Militia",'
WIKI_ROW = '\t["14"] = {["Title"] = "人民の民兵", ["TranslationStat"] = "wiki" },\n'
QJP = FIXTURES / "questjapanizer/QuestData.excerpt.lua"
CJQ = FIXTURES / "craftjapanizer/QuestData.excerpt.lua"
CORRECTION = {
    "class": "correction",
    "translator": "Tammy",
    "source": "correction@2026-09-14",
    "imported": "2026-09-14",
    "corrects": "cqjt@3446c82",
}
BASELINE = {"hash": "0123456789abcdef", "src": "pfquest@7786596"}


# ---- helpers ------------------------------------------------------------------------------------------------


def _root(root: Path, where: Path) -> Path:
    """A repo-shaped directory: data/SCHEMA, pipeline/allowlist.txt, the predecessor repos, a pfQuest copy."""
    (where / "data").mkdir(parents=True)
    (where / "data" / "SCHEMA").write_text("1\n")
    (where / "pipeline").mkdir()
    shutil.copy(root / "pipeline/allowlist.txt", where / "pipeline/allowlist.txt")
    q = where / "quest-repo"
    q.mkdir()
    shutil.copy(FIXTURES / "predecessor/QuestLogData.excerpt.lua", q / "QuestLogData.lua")
    t = where / "tooltip-repo"
    (t / "Data/Item").mkdir(parents=True)
    (t / "Data/Spell").mkdir(parents=True)
    shutil.copy(FIXTURES / "predecessor/ItemData.excerpt.lua", t / "Data/Item/ItemData.lua")
    shutil.copy(FIXTURES / "predecessor/SpellData.excerpt.lua", t / "Data/Spell/SpellData.lua")
    shutil.copy(PFQUEST, where / "pfquest.lua")
    pf = PFQUEST.read_text(encoding="utf-8")
    assert TITLE in pf and MILITIA in pf
    qjp = QJP.read_text(encoding="utf-8").rstrip()
    assert qjp.endswith("}") and '["14"]' not in qjp
    (where / "qjp.lua").write_text(qjp[:-1] + WIKI_ROW + "}\n", encoding="utf-8")
    assert '["14"]' not in (FIXTURES / "predecessor/QuestLogData.excerpt.lua").read_text(encoding="utf-8")
    return where / "data"


def _set_english(where: Path, *edits: tuple[str, str]) -> None:
    text = PFQUEST.read_text(encoding="utf-8")
    for old, new in edits:
        text = text.replace(old, new)
    (where / "pfquest.lua").write_text(text, encoding="utf-8")


def _predecessor(where: Path, lineage: bool = True) -> None:
    """`import predecessor` as `make import` runs it: one pass with the lineage sources (lineage=False: alone)."""
    args = ["predecessor", "--quest-repo", str(where / "quest-repo"), "--tooltip-repo", str(where / "tooltip-repo"),
            "--commit-quest", "3446c82", "--commit-tooltip", "84db736", "--date", DATE]
    if lineage:
        args += ["--questjapanizer", str(where / "qjp.lua"), "--craftjapanizer-quest", str(CJQ)]
    assert imp.run(args) == 0


def _lineage_steps(where: Path) -> None:
    """The standalone lineage subcommands, each run on its own."""
    assert imp.run(["questjapanizer", str(where / "qjp.lua"), "--date", DATE]) == 0
    assert imp.run(["craftjapanizer-quest", str(CJQ), "--date", DATE]) == 0


def _english(where: Path) -> None:
    assert imp.run(["english", "pfquest", str(where / "pfquest.lua"), "--commit", "7786596"]) == 0
    wago = FIXTURES / "wago"
    assert imp.run(
        ["english", "wago-ids", str(wago / "ItemSparse.excerpt.csv"), str(wago / "SpellName.excerpt.csv"),
         "--build", "1.15.9.69722"]
    ) == 0


def _chain(where: Path) -> None:
    """`make data` minus generate: predecessor (one pass with the lineage sources) → English → check."""
    _predecessor(where)
    _english(where)
    assert check.run([]) == 0


def _lines(data: Path, type_: str) -> dict:
    return {(ln["id"], ln["field"]): ln for ln in Store(data).load(type_)}


def _judged(data: Path) -> dict:
    """(type, id, field) → (status, reasons, english): what `check` derived."""
    return {
        (t, *k): (ln["status"], ln["reasons"], ln["english"]) for t in TYPES for k, ln in _lines(data, t).items()
    }


def _bytes(data: Path) -> dict:
    return {str(p.relative_to(data)): p.read_bytes() for p in sorted(data.rglob("*.jsonl"))}


@pytest.fixture
def repo(root, tmp_path, monkeypatch):
    data = _root(root, tmp_path)
    monkeypatch.chdir(tmp_path)
    return tmp_path, data


# ---- the baseline is carried by (id, field); counts are printed ---------------------------------------


def test_baselines_survive_the_rebuild(repo, capsys):
    where, data = repo
    _chain(where)
    before = {t: _lines(data, t) for t in TYPES}
    quests = before["quest"]
    # a correction on a key the inputs never produce, with a baseline → recreated by the carry, baseline kept
    quests[(90001, "title")] = {
        "id": 90001, "field": "title", "ja": "手で入れたタイトル", "status": "trusted", "checks": [],
        "provenance": dict(CORRECTION), "english": dict(BASELINE), "reasons": [], "conflicts": [],
    }
    # an imported line the inputs no longer produce, no decision on it → its baseline is counted, not written
    quests[(90003, "title")] = {
        "id": 90003, "field": "title", "ja": "消えた題", "status": "trusted", "checks": [],
        "provenance": {"class": "human", "translator": "Kaz", "source": "cqjt@3446c82", "imported": DATE},
        "english": dict(BASELINE), "reasons": [], "conflicts": [],
    }
    # a line the inputs produce but the store no longer has (removed by hand) → rebuilt with no baseline
    del quests[(14, "title")]
    Store(data).save("quest", quests.values())
    with_baseline = {t: sum(1 for ln in before[t].values() if ln["english"]) for t in TYPES}
    assert with_baseline["quest"] and with_baseline["item"] and with_baseline["spell"]
    capsys.readouterr()

    _predecessor(where)
    out = capsys.readouterr().out
    after = {t: _lines(data, t) for t in TYPES}

    for t in TYPES:
        for k, ln in after[t].items():
            prior = before[t].get(k)
            if prior is not None and prior["english"]:
                assert ln["english"] == prior["english"], (t, k)
            assert ln["status"] == "pending"
    assert after["quest"][(90001, "title")]["english"] == BASELINE
    assert (90003, "title") not in after["quest"]
    new_keys = [(t, k) for t in TYPES for k in after[t] if k not in before[t]]
    assert new_keys == [("quest", (14, "title"))]
    assert after["quest"][(14, "title")]["english"] is None
    carried_quests = with_baseline["quest"] - 1  # the seeded counts include both new lines; the vanished one is not carried
    assert (
        f"carried english baselines: quest {carried_quests} · item {with_baseline['item']} "
        f"· spell {with_baseline['spell']}" in out
    )
    assert "english baselines not produced by the inputs: quest 1 · item 0 · spell 0" in out


def test_a_line_new_to_the_store_has_no_baseline(repo, capsys):
    where, data = repo
    _predecessor(where)
    out = capsys.readouterr().out
    assert all(ln["english"] is None for t in TYPES for ln in _lines(data, t).values())
    assert "carried english baselines: quest 0 · item 0 · spell 0" in out
    assert "not produced by the inputs" not in out


# ---- stale through the full chain, sticky, and back to trusted ---------------------------------------


def test_changed_english_is_stale_through_the_full_chain_sticky_and_recovers(repo):
    where, data = repo
    _chain(where)
    original = _judged(data)
    target = ("quest", 2, "title")
    assert original[target][0] == "trusted"
    old_hash = original[target][2]["hash"]

    _set_english(where, (TITLE, CHANGED))
    _chain(where)
    changed = _judged(data)
    assert changed[target][0] == "stale" and changed[target][2]["hash"] == old_hash
    assert {k: v for k, v in changed.items() if k != target} == {k: v for k, v in original.items() if k != target}

    _chain(where)  # sticky
    again = _judged(data)
    assert again[target][0] == "stale" and again[target][2]["hash"] == old_hash
    assert again == changed

    _set_english(where)  # the English is back → trusted against the original hash
    _chain(where)
    assert _judged(data) == original


# ---- the full chain and the refresh path agree -----------------------------------------------------------


def test_full_chain_equals_the_refresh_path(root, tmp_path, monkeypatch):
    a, b = tmp_path / "a", tmp_path / "b"
    data_a, data_b = _root(root, a), _root(root, b)
    monkeypatch.chdir(a)
    _chain(a)
    shutil.rmtree(data_b)
    shutil.copytree(data_a, data_b)

    edits = ((TITLE, CHANGED), (MILITIA, MILITIA_CHANGED))
    _set_english(a, *edits)
    _chain(a)  # make data

    _set_english(b, *edits)
    monkeypatch.chdir(b)
    _english(b)  # make import-english
    assert check.run([]) == 0  # make check

    judged_a, judged_b = _judged(data_a), _judged(data_b)
    assert judged_a == judged_b
    assert judged_a[("quest", 2, "title")][0] == "stale"
    assert judged_a[("quest", 14, "title")][0] == "stale"  # the lineage-only line agrees too


# ---- unchanged inputs → byte no-op -----------------------------------------------------------------------


def test_chain_twice_is_byte_identical(repo):
    where, data = repo
    _chain(where)
    first = _bytes(data)
    _chain(where)
    assert _bytes(data) == first and first


# ---- a line only a lineage source produces keeps its baseline ------------------------------


def test_lineage_only_line_keeps_its_baseline_and_goes_stale(repo, capsys):
    where, data = repo
    _chain(where)
    target = ("quest", 14, "title")
    line = _lines(data, "quest")[(14, "title")]
    assert line["provenance"]["source"] == "qjp@0.5.8" and line["conflicts"] == []  # no predecessor variant
    original = _judged(data)
    assert original[target][0] == "trusted"
    old_hash = original[target][2]["hash"]

    capsys.readouterr()
    _set_english(where, (MILITIA, MILITIA_CHANGED))
    _chain(where)
    out = capsys.readouterr().out
    assert "not produced by the inputs" not in out
    changed = _judged(data)
    assert changed[target][0] == "stale" and changed[target][2]["hash"] == old_hash
    _chain(where)  # sticky through the next make data too
    assert _judged(data)[target] == changed[target]


# ---- the one pass writes what the three separate commands wrote, plus the baselines they dropped ---------


def test_one_pass_equals_the_three_step_import(root, tmp_path, monkeypatch, capsys):
    a, b = tmp_path / "a", tmp_path / "b"
    data_a, data_b = _root(root, a), _root(root, b)
    monkeypatch.chdir(a)
    _chain(a)
    shutil.rmtree(data_b)
    shutil.copytree(data_a, data_b)

    _predecessor(a)  # one pass
    monkeypatch.chdir(b)
    capsys.readouterr()
    _predecessor(b, lineage=False)  # three steps
    assert "english baselines not produced by the inputs: quest 1 · item 0 · spell 0" in capsys.readouterr().out
    _lineage_steps(b)

    for t in ("item", "spell"):
        assert _bytes(data_a / t) == _bytes(data_b / t)
    one, three = _lines(data_a, "quest"), _lines(data_b, "quest")
    assert list(one) == list(three)
    dropped = []
    for k, ln in one.items():
        other = three[k]
        assert list(ln) == list(other), k
        assert {f: v for f, v in ln.items() if f != "english"} == {f: v for f, v in other.items() if f != "english"}, k
        if ln["english"] != other["english"]:
            assert other["english"] is None and ln["english"], k
            dropped.append(k)
    assert dropped == [(14, "title")]


# ---- bad lineage arguments and files are refused before anything is written --------------------


@pytest.mark.parametrize(
    "extra, message",
    [
        (["--qjp-version", "0.5.9"], "--qjp-version given without --questjapanizer"),
        (["--cjq-version", "2012031301"], "--cjq-version given without --craftjapanizer-quest"),
        (["--questjapanizer", ""], "--questjapanizer needs a file path"),
        (["--craftjapanizer-quest", " "], "--craftjapanizer-quest needs a file path"),
    ],
)
def test_lineage_flags_are_checked_before_anything_is_written(repo, capsys, extra, message):
    where, data = repo
    _chain(where)
    before = _bytes(data)
    args = ["predecessor", "--quest-repo", str(where / "quest-repo"), "--tooltip-repo", str(where / "tooltip-repo"),
            "--commit-quest", "3446c82", "--commit-tooltip", "84db736", "--date", DATE]
    capsys.readouterr()
    assert imp.run(args + extra) == 1
    assert capsys.readouterr().err.strip() == f"wfj import: {message}"
    assert _bytes(data) == before


def test_a_bad_lineage_file_leaves_data_untouched(repo, capsys):
    where, data = repo
    _chain(where)
    before = _bytes(data)
    args = ["predecessor", "--quest-repo", str(where / "quest-repo"), "--tooltip-repo", str(where / "tooltip-repo"),
            "--commit-quest", "3446c82", "--commit-tooltip", "84db736", "--date", DATE]
    truncated = where / "truncated.lua"
    truncated.write_text((where / "qjp.lua").read_text(encoding="utf-8")[:200], encoding="utf-8")
    capsys.readouterr()
    for path in (truncated, where / "quest-repo", where / "missing.lua"):  # truncated · a directory · absent
        assert imp.run(args + ["--questjapanizer", str(path)]) == 1
        err = capsys.readouterr().err
        assert err.startswith("wfj import: ") and "Traceback" not in err, (path, err)
        assert _bytes(data) == before
