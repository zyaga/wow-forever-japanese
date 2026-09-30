"""The `book` translation type through model, draft import, check, generate and stats. A book page is
keyed in data/ by its page id and in the generated Lua by the English it was checked against. There is no
`trainer_greeting` type: Forever's trainer UI has no greeting."""

import json
import re
from pathlib import Path

import pytest

from wfj.cmd import check, generate, stats, validate
from wfj.cmd.import_ import run as import_run
from wfj.core import markup
from wfj.core.hashing import key
from wfj.core.model import FIELDS, english_line, entry, validate_line
from wfj.core.normalize import normalize_v1
from wfj.emit import lua_writer, schema
from wfj.io.jsonl_store import Store

SRC = "vmangos@13b49dc"
PAGE_EN = "Kurdran Wildhammer\n\nRenowned Dragon Fighter. Gryphon Master of the Aerie Peak.$B$B- Falstad Wildhammer"
PAGE_JA = "Kurdran Wildhammer\n\n名高きドラゴン狩り。Aerie Peakのグリフォン使いの長。\n\n- Falstad Wildhammer"
HTML_EN = '<HTML>\n<BODY>\n<H1 align="center">\n50 BTFT - 25 ATFT\n</H1>\n<P>\nIn memory of my dear mentor.\n</P>\n</BODY>\n</HTML>'
HTML_JA = '<HTML>\n<BODY>\n<H1 align="center">\n50 BTFT - 25 ATFT\n</H1>\n<P>\n親愛なる師を偲んで。\n</P>\n</BODY>\n</HTML>'
MACHINE = {"class": "machine", "model": "model-x", "source": "draft-t@2026-09-15", "imported": "2026-09-15"}


def _hash(en: str) -> str:
    return key(normalize_v1(en))


@pytest.fixture
def repo(tmp_path: Path, monkeypatch):
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    (tmp_path / "pipeline").mkdir()
    (tmp_path / "pipeline" / "allowlist.txt").write_text("", encoding="utf-8")
    # book drafts are imported under the style guide's version
    (tmp_path / "docs" / "content").mkdir(parents=True)
    (tmp_path / "docs" / "content" / "translation-style-guide.md").write_text("version: sg4\n", encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    eng = Store(data, english=True)
    eng.save("book", [
        english_line(287, "text", PAGE_EN, _hash(PAGE_EN), SRC),
        english_line(1031, "text", HTML_EN, _hash(HTML_EN), SRC),
    ])
    return tmp_path


def _draft(tmp: Path, type_: str, rows: list[str], name: str = "test-sg4") -> int:
    path = tmp / f"{type_}.jsonl"
    path.write_text("\n".join(rows) + "\n", encoding="utf-8")
    return import_run(["draft", type_, str(path), "--model", "model-x", "--date", "2026-09-15", "--name", name])


# ── model ────────────────────────────────────────────────────────────────────


def test_fields_and_id_rules():
    assert FIELDS["book"] == ["text"] and "trainer_greeting" not in FIELDS
    ok_book = entry(287, "text", "訳", prov=MACHINE)
    assert validate_line("book", ok_book) == []
    assert any("positive int" in p for p in validate_line("book", {**ok_book, "id": "ab" * 8}))
    assert validate_line("trainer_greeting", entry("ab" * 8, "text", "訳", prov=MACHINE)) == [
        "unknown type 'trainer_greeting'"
    ]


# ── draft import ─────────────────────────────────────────────────────────────


def test_draft_import_writes_a_book_page(repo: Path):
    assert _draft(repo, "book", ['{"id": 287, "field": "text", "ja": "訳"}']) == 0
    (b,) = Store(repo / "data").load("book")
    assert (b["id"], b["provenance"]["class"], b["provenance"]["model"]) == (287, "machine", "model-x")
    assert b["provenance"]["source"] == "draft-test-sg4@2026-09-15"


def test_draft_import_refuses_a_string_page_id_and_the_greeting_type(repo: Path, capsys):
    assert _draft(repo, "book", ['{"id": "287", "field": "text", "ja": "訳"}']) != 0
    assert "must be an integer" in capsys.readouterr().err
    assert _draft(repo, "trainer_greeting", ['{"id": "' + "ab" * 8 + '", "field": "text", "ja": "訳"}']) != 0
    assert Store(repo / "data").load("book") == []
    assert not (repo / "data" / "trainer_greeting").exists()


# ── check: page markup ───────────────────────────────────────────────────────


def _checked(repo: Path, type_: str):
    assert check.run([]) == 0
    return {ln["id"]: ln for ln in Store(repo / "data").load(type_)}


def test_check_trusts_rejects_and_marks_stale(repo: Path):
    rows = [json.dumps({"id": 287, "field": "text", "ja": PAGE_JA}, ensure_ascii=False),
            json.dumps({"id": 1031, "field": "text", "ja": "Horatio先生を偲んで。"}, ensure_ascii=False)]
    assert _draft(repo, "book", rows) == 0
    books = _checked(repo, "book")
    assert books[287]["status"] == "trusted"
    assert books[287]["english"] == {"hash": _hash(PAGE_EN), "src": SRC}
    assert "names" in books[287]["checks"]
    # a name the English does not have, and a page that dropped its HTML tags
    assert books[1031]["status"] == "rejected"
    assert any(r.startswith("alignment_failed:Horatio") for r in books[1031]["reasons"])
    assert any(r.startswith("markup_changed:html") for r in books[1031]["reasons"])

    # the page's English changes: the translation is stale, and stays so on a rerun (sticky, ADR-003)
    new_en = PAGE_EN.replace("Renowned", "Famous")
    Store(repo / "data", english=True).save("book", [
        english_line(287, "text", new_en, _hash(new_en), SRC),
        english_line(1031, "text", HTML_EN, _hash(HTML_EN), SRC),
    ])
    assert _checked(repo, "book")[287]["status"] == "stale"
    books = _checked(repo, "book")
    assert books[287]["status"] == "stale" and books[287]["english"]["hash"] == _hash(PAGE_EN)
    assert validate.rule_referential(Store(repo / "data"), Store(repo / "data", english=True)) == []


def test_html_rule():
    assert markup.html_mismatch("Plain page.", "訳") is None
    assert markup.html_mismatch(HTML_EN, HTML_JA) is None
    assert markup.html_mismatch(HTML_EN, HTML_JA.replace("<BR/>", "")) is None
    assert markup.html_mismatch(HTML_EN, HTML_JA.replace('<H1 align="center">', "<H1>")) is not None
    assert markup.html_mismatch(HTML_EN, "親愛なる師を偲んで。") == "en 8 tags ja 0"
    # tag names compare case-insensitively; <BR/> and <BR></BR> are what the English wrote
    assert markup.html_mismatch("<html><p>a</p></html>", "<HTML><P>訳</P></HTML>") is None
    # a plain page's bracketed prose is not markup (pages 208, 1151–1155, 1611, 1631–1634)
    assert markup.html_mismatch("<The pages are covered in ancient elven runes.>", "<ページは古代エルフのルーン文字で覆われている。>") is None
    assert markup.html_mismatch("<illegible text>", "判読できない文字") is None


def test_html_page_with_its_tags_is_trusted(repo: Path):
    assert _draft(repo, "book", [json.dumps({"id": 1031, "field": "text", "ja": HTML_JA}, ensure_ascii=False)]) == 0
    assert _checked(repo, "book")[1031]["status"] == "trusted"


# ── generate and validate ────────────────────────────────────────────────────


def _shipped(id_, ja, status="trusted", h=None):
    line = entry(id_, "text", ja, status=status, prov=MACHINE)
    line["english"] = {"hash": h or (id_ if isinstance(id_, str) else _hash(PAGE_EN)), "src": SRC}
    return line


def test_no_trainer_greeting_type_is_generated():
    assert "trainer_greeting" not in schema.KEYED_TYPES and "trainer_greeting" not in schema.FILE_PREFIX


def test_book_rows_are_keyed_by_english_hash_and_always_dot():
    h = _hash(PAGE_EN)
    rows = lua_writer.keyed_rows("book", [_shipped(287, "訳"), _shipped(288, "別", status="stale", h="ab" * 8)])
    assert rows == {h: ['"訳"', '"."'], "ab" * 8: ['"別"', '"."']}
    assert "data/book/" in lua_writer.keyed_text("book", h[:2], {h: rows[h]})
    assert schema.shard_relpath("book", "ab") == "Data/Book/Book_ab.lua"


def test_a_stale_book_line_gives_way_to_a_current_page_under_its_key():
    h = _hash(PAGE_EN)
    rows = lua_writer.keyed_rows("book", [_shipped(287, "今の訳"), _shipped(9, "昔の訳", status="stale", h=h)])
    assert rows == {h: ['"今の訳"', '"."']}


def test_book_pages_sharing_one_english():
    same = [_shipped(10, "本文なし"), _shipped(761, "本文なし")]
    assert len(lua_writer.keyed_rows("book", same)) == 1
    # the same Japanese laid out with other whitespace is one row, written as the lowest page id's
    layout = [_shipped(761, "<HTML> <BODY> <P>訳</P>"), _shipped(10, "<HTML>\n<BODY>\n<P>訳</P>")]
    assert list(lua_writer.keyed_rows("book", layout).values()) == [['"<HTML>\\n<BODY>\\n<P>訳</P>"', '"."']]
    with pytest.raises(ValueError, match=r"book pages 10 and 761 share the English .* different Japanese"):
        lua_writer.keyed_rows("book", [_shipped(10, "本文なし"), _shipped(761, "別の訳")])
    with pytest.raises(ValueError, match="shipped without english"):
        lua_writer.keyed_rows("book", [{**_shipped(10, "訳"), "english": None}])


def test_generate_plan_orders_and_counts(repo: Path):
    assert _draft(repo, "book", [json.dumps({"id": 287, "field": "text", "ja": PAGE_JA}, ensure_ascii=False)]) == 0
    assert check.run([]) == 0
    planned = generate.plan(Store(repo / "data"), [])
    book = f"Data/Book/Book_{_hash(PAGE_EN)[:2]}.lua"
    assert book in planned
    meta = planned["Data/Meta.lua"]
    assert "book = 1, ui = 0" in meta
    assert 'vmangos = "13b49dc"' in meta
    planned["Data/Gossip/Gossip_00.lua"] = ""
    planned["Data/UI/UI_A.lua"] = ""
    files = generate.toc_files(planned)
    assert files.index("Data/Gossip/Gossip_00.lua") < files.index(book) < files.index(
        "Data/UI/UI_A.lua")


def test_validate_reports_a_book_conflict(repo: Path):
    (repo / "vectors").mkdir()
    (repo / "vectors" / "hash_vectors.jsonl").write_text("", encoding="utf-8")
    Store(repo / "data", english=True).save("book", [
        english_line(10, "text", "Missing Text", _hash("Missing Text"), SRC),
        english_line(761, "text", "Missing Text", _hash("Missing Text"), SRC),
    ])
    assert _draft(repo, "book", [json.dumps({"id": 10, "field": "text", "ja": "本文なし"}, ensure_ascii=False),
                                 json.dumps({"id": 761, "field": "text", "ja": "文章がない"}, ensure_ascii=False)]) == 0
    assert check.run([]) == 0
    with pytest.raises(ValueError, match="book pages 10 and 761"):
        generate.plan(Store(repo / "data"), [])
    problems = validate.rule_regenerate(repo / "data", Store(repo / "data"), repo / "addon")
    assert any("book pages 10 and 761" in p for p in problems)


# ── stats ────────────────────────────────────────────────────────────────────


def test_stats_lists_books(repo: Path, capsys):
    assert _draft(repo, "book", [json.dumps({"id": 287, "field": "text", "ja": PAGE_JA}, ensure_ascii=False)]) == 0
    assert check.run([]) == 0
    capsys.readouterr()
    assert stats.run([]) == 0
    out = capsys.readouterr().out
    assert any(line.startswith("book   text") for line in out.splitlines())
    assert "book shipped by provenance" in out and "trainer_greeting" not in out


# ── committed screen-test pages ──────────────────────────────────────────────


def test_committed_screen_test_lines(root):
    data = Store(root / "data")
    books = {ln["id"]: ln for ln in data.load("book")}
    assert set(books) >= {637, 638, 287, 1031, 1762, 1756}
    for ln in (books[i] for i in (637, 638, 287, 1031, 1762, 1756)):
        assert ln["status"] == "trusted", ln["id"]
        # a test line that failed the draft lint was re-drafted under the style guide and wins
        assert ln["provenance"]["class"] == "machine"
        assert ln["provenance"]["source"] == "draft-books-screens@2026-09-15" or re.match(
            r"^draft-book-sg\d+@", ln["provenance"]["source"]), ln["provenance"]
    addon = root / "addon" / "WoWForeverJapanese" / "Data"
    assert (addon / "Book" / f"Book_{books[287]['english']['hash'][:2]}.lua").is_file()
