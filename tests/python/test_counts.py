"""The counts in README.md and docs/curseforge.md are the ones `make coverage` writes."""

import sqlite3
from pathlib import Path

from wfj.dev import counts, letter_pages


def test_the_readme_and_curseforge_counts_are_current(root: Path):
    c = counts.measure(root)
    readme = (root / counts.README).read_text(encoding="utf-8")
    curseforge = (root / counts.CURSEFORGE).read_text(encoding="utf-8")
    assert counts.apply_readme(readme, c) == readme, "run `make coverage` and commit README.md"
    assert counts.apply_curseforge(curseforge, c) == curseforge, "run `make coverage` and commit docs/curseforge.md"


def test_book_and_letter_pages_add_up_to_the_shipped_book_keys(root: Path):
    c = counts.measure(root)
    meta = (root / counts.META).read_text(encoding="utf-8")
    assert f"book = {c['book'] + c['letter']}," in meta


def test_a_whole_letter_chain_is_listed_and_a_book_is_not():
    starts = {10: "Gryshka's Letter", 20: "Annals of Darrowshire"}
    pages = letter_pages.letter_pages(starts, {10: 11, 11: 12, 12: 0, 20: 21})
    assert sorted(pages) == [10, 11, 12]


def test_item_starts_reads_both_tables(tmp_path: Path):
    sparse = tmp_path / "ItemSparse.csv"
    sparse.write_text("ID,Display_lang,PageID\n1,Musty Letter,5\n2,Sword,0\n", encoding="utf-8")
    db = sqlite3.connect(":memory:")
    db.execute("CREATE TABLE item_template (name TEXT, page_text INTEGER)")
    db.execute("INSERT INTO item_template VALUES ('Old Diary', 7), ('Musty Letter copy', 5)")
    assert letter_pages.item_starts(sparse, db) == {5: "Musty Letter", 7: "Old Diary"}


def test_the_counts_land_in_the_readme_tables_and_the_curseforge_lines():
    c = {"quest": 1000, "gossip": 2, "book": 3, "letter": 4, "item": 5, "spell": 6, "ui": 7}
    readme = "x\n\n## What it translates\n\n| old |\n\n## Install\n\n### 翻訳の量\n\n| 古い |\n\n### インストール\n"
    out = counts.apply_readme(readme, c)
    assert "| Quests | 1,000 |" in out and "| 手紙 | 4 ページ |" in out and "old" not in out and "古い" not in out
    cf = counts.apply_curseforge("In numbers: old\n数で見ると: 古い\n", c)
    assert "**2** NPC dialogue lines" in cf and "**3** book pages" in cf and "UI **7**" in cf
