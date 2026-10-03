"""`wfj import english forever-vo`: quest progress and turn-in English from forever-vo's captures (ADR-055)."""

import json
from pathlib import Path

import pytest

from wfj.cmd.import_ import run
from wfj.core.hashing import key
from wfj.core.model import english_line, validate_line
from wfj.core.normalize import normalize_v1
from wfj.io.forever_vo import read_captures, read_greetings
from wfj.io.jsonl_store import Store

SRC = "forever-vo@025070f"


def _line(id_, field, en, src):
    return english_line(id_, field, en, key(normalize_v1(en)), src)


def _entry(qid, event, title, text, build="70205"):
    return {"questID": qid, "event": event, "title": title, "text": text, "build": build}


def _captures(folder: Path, submissions: list[list[dict]], gossip: list[list[dict]] | None = None) -> Path:
    (folder / "captures").mkdir(parents=True)
    for i, entries in enumerate(submissions):
        doc = {"origin": f"issue-{i}", "quests": {f"{e['questID']}-{e['event']}-{n}": e for n, e in enumerate(entries)}}
        if gossip:
            doc["gossip"] = {f"g{n}": g for n, g in enumerate(gossip[i])}
        (folder / "captures" / f"issue-{i}.json").write_text(json.dumps(doc), encoding="utf-8")
    return folder


def _greeting(text, npc="1992"):
    return {"event": "gossip", "text": text, "npc": npc, "isObject": None}


def _data(tmp_path: Path, monkeypatch, lines) -> Path:
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    Store(data, english=True).save("quest", lines)
    return data


TITLES = {97977: "Nature's Call", 459: "The Woodland Protector"}
DONE = "Oh, it's even worse than I thought. Thank you for your aid, $N."


def test_reader_rules(tmp_path):
    folder = _captures(
        tmp_path / "fvo",
        [
            [_entry(97977, "complete", "Nature's Call", DONE), _entry(97977, "progress", "Nature's Call", "Totems?")],
            [_entry(97977, "complete", "Nature's Call", DONE + "  ")],  # same text normalized: a second sender
            [_entry(97977, "complete", "Ruf der Natur", "Oh, es ist noch schlimmer.")],  # a German client
            [_entry(97977, "accept", "Nature's Call", "Offer text.")],  # not read
            [_entry(1, "complete", "Unknown quest", "No title we hold.")],
        ],
    )
    result = read_captures(folder, TITLES)
    got = {(c.id_, c.field): c for c in result.captures}
    assert set(got) == {(97977, "completion")}  # the progress text had one sender
    assert got[(97977, "completion")].origins == 2
    assert result.skipped["other_language"] == 1
    assert result.skipped["no_title"] == 1
    assert result.skipped["one_submission"] == 1


def test_most_senders_win_and_a_tie_keeps_the_token(tmp_path):
    lit, tok = "Welcome, young human.", "Welcome, young $r."
    folder = _captures(
        tmp_path / "fvo",
        [[_entry(459, "progress", "The Woodland Protector", t)] for t in (lit, lit, tok, tok)]
        + [[_entry(459, "complete", "The Woodland Protector", t, b)] for t, b in (("Old.", "70009"),) * 3]
        + [[_entry(459, "complete", "The Woodland Protector", "New.", "70205")]] * 2,
    )
    got = {(c.id_, c.field): c.en for c in read_captures(folder, TITLES).captures}
    assert got[(459, "progress")] == tok
    assert got[(459, "completion")] == "Old."  # three senders beat two, whatever the build


def test_no_captures_is_refused(tmp_path):
    (tmp_path / "captures").mkdir()
    with pytest.raises(ValueError, match="no captures"):
        read_captures(tmp_path, TITLES)


def test_import_fills_only_missing_fields(tmp_path, monkeypatch):
    held = _line(459, "completion", "VMaNGOS wording.", "vmangos@13b49dc")
    data = _data(
        tmp_path,
        monkeypatch,
        [_line(97977, "title", "Nature's Call", "wdb@1.60.1.70205"),
         _line(459, "title", "The Woodland Protector", "wdb@1.60.1.70205"), held],
    )
    folder = _captures(
        tmp_path / "fvo",
        [[_entry(97977, "complete", "Nature's Call", DONE),
          _entry(459, "complete", "The Woodland Protector", "Another wording.")]] * 2,
    )
    assert run(["english", "forever-vo", str(folder), "--commit", "025070f"]) == 0
    got = {(ln["id"], ln["field"]): ln for ln in Store(data, english=True).load("quest")}
    assert got[(97977, "completion")]["src"] == SRC
    assert got[(97977, "completion")]["en"] == DONE
    assert validate_line("quest", got[(97977, "completion")], english=True) == []
    assert got[(459, "completion")] == held  # another source holds it: never replaced


def test_a_collector_line_outranks_forever_vo(tmp_path, monkeypatch):
    mine = _line(97977, "completion", "Recorded in game.", "collector@1.60.1.70205")
    data = _data(tmp_path, monkeypatch, [_line(97977, "title", "Nature's Call", "wdb@1.60.1.70205"), mine])
    folder = _captures(tmp_path / "fvo", [[_entry(97977, "complete", "Nature's Call", DONE)]] * 2)
    assert run(["english", "forever-vo", str(folder), "--commit", "025070f"]) == 0
    got = {(ln["id"], ln["field"]): ln for ln in Store(data, english=True).load("quest")}
    assert got[(97977, "completion")] == mine


def test_bad_commit_is_refused(tmp_path, monkeypatch, capsys):
    data = _data(tmp_path, monkeypatch, [])
    assert run(["english", "forever-vo", str(tmp_path), "--commit", "latest"]) != 0
    assert "--commit must be" in capsys.readouterr().err
    assert Store(data, english=True).load("quest") == []


def test_greetings_from_english_submissions_two_agreeing(tmp_path):
    hello, hallo = "Greetings, traveler.", "Seid gegrüßt, Reisender."
    en = [_entry(97977, "progress", "Nature's Call", "Totems?")]
    de = [_entry(97977, "progress", "Ruf der Natur", "Totems?")]
    folder = _captures(
        tmp_path / "fvo",
        [en, en, de, de, []],
        [[_greeting(hello, "1992"), _greeting("Only one sent this.")], [_greeting(hello, "1993")],
         [_greeting(hallo)], [_greeting(hallo)], [_greeting(hello)]],  # the last: no quest to tell its language
    )
    got = read_greetings(folder, TITLES)
    assert [(g.en, g.origins, g.npcs) for g in got] == [(hello, 2, [1992, 1993])]


def test_import_adds_only_greetings_no_source_holds(tmp_path, monkeypatch):
    held = _line("70f068541ce5e138", "text", "Goodbye.", "vmangos@13b49dc")
    held = {**held, "id": key(normalize_v1("Goodbye.")), "hash": key(normalize_v1("Goodbye."))}
    data = _data(tmp_path, monkeypatch, [_line(97977, "title", "Nature's Call", "wdb@1.60.1.70205")])
    Store(data, english=True).save("gossip", [held])
    en = [_entry(97977, "progress", "Nature's Call", "Totems?")]
    folder = _captures(tmp_path / "fvo", [en, en],
                       [[_greeting("Greetings, traveler."), _greeting("Goodbye.")]] * 2)
    assert run(["english", "forever-vo", str(folder), "--commit", "025070f"]) == 0
    got = {ln["en"]: ln for ln in Store(data, english=True).load("gossip")}
    assert got["Goodbye."] == held
    new = got["Greetings, traveler."]
    assert new["src"] == SRC and new["id"] == new["hash"] == key(normalize_v1("Greetings, traveler."))
    assert new["npcs"] == [1992]
    assert validate_line("gossip", new, english=True) == []


def test_a_gender_alias_wording_and_a_skipped_key_are_not_imported(tmp_path, monkeypatch):
    both = "Welcome, $gsir:madam;."
    k = key(normalize_v1(both))
    data = _data(tmp_path, monkeypatch, [_line(97977, "title", "Nature's Call", "wdb@1.60.1.70205")])
    Store(data, english=True).save("gossip", [english_line(k, "text", both, k, "vmangos@13b49dc")])
    en = [_entry(97977, "progress", "Nature's Call", "Totems?")]
    folder = _captures(tmp_path / "fvo", [en, en],
                       [[_greeting("Welcome, madam."), _greeting("Nostyec, mod."), _greeting("Hello there.")]] * 2)
    skip = tmp_path / "skip.txt"
    skip.write_text(f"# reasons\n{key(normalize_v1('Nostyec, mod.'))}\tin Thalassian\n", encoding="utf-8")
    assert run(["english", "forever-vo", str(folder), "--commit", "025070f", "--skip", str(skip)]) == 0
    got = sorted(ln["en"] for ln in Store(data, english=True).load("gossip"))
    assert got == ["Hello there.", both]  # the female wording rides the alias; the skipped key stays out


def test_a_malformed_entry_is_counted_not_fatal(tmp_path):
    folder = _captures(tmp_path / "fvo", [[_entry(97977, "complete", "Nature's Call", DONE)],
                                          [_entry(97977, "complete", "Nature's Call", DONE)]])
    path = folder / "captures" / "issue-0.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    doc["quests"]["bad"] = {"event": "complete", "text": "No id."}
    doc["quests"]["worse"] = "not a record"
    path.write_text(json.dumps(doc), encoding="utf-8")
    result = read_captures(folder, TITLES)
    assert [(c.id_, c.field) for c in result.captures] == [(97977, "completion")]
    assert result.skipped["malformed"] == 2
    read_greetings(folder, TITLES)  # the language check reads past it too
