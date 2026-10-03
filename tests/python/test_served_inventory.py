"""Every text column the client serves has a stated disposition, and the inventory is taken on the pinned
build (pipeline/served_columns.txt, pipeline/served_dispositions.txt)."""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from wfj.dev import served_dispositions as sd
from wfj.dev.served_columns import inventory_build, read_inventory


def _write(tmp_path: Path, text: str) -> Path:
    path = tmp_path / "served_dispositions.txt"
    path.write_text(text, encoding="utf-8")
    return path


def test_every_served_column_has_a_stated_disposition(root: Path):
    columns = read_inventory(root / "pipeline" / "served_columns.txt")
    dispositions, problems = sd.parse(root / "pipeline" / "served_dispositions.txt")
    problems += sd.check(columns, dispositions)
    assert not problems, "\n".join(problems)


def test_the_inventory_is_taken_on_the_pinned_build(root: Path):
    makefile = (root / "Makefile").read_text(encoding="utf-8")
    pinned = re.search(r"^forever_BUILD\s*:=\s*(\S+)", makefile, re.M).group(1)
    assert inventory_build(root / "pipeline" / "served_columns.txt") == pinned, (
        "run `make served-columns` on the pinned build and give each new column a disposition"
    )


def test_a_new_column_and_a_dropped_column_both_fail(tmp_path: Path):
    columns = {"spell.f1": "rows=2  text=2  distinct=2", "newtable.f0": "rows=1  text=1  distinct=1"}
    dispositions, problems = sd.parse(
        _write(tmp_path, "spell.f1  surface:spell.description\ngone.f3  names\n")
    )
    assert not problems
    assert sd.check(columns, dispositions) == [
        "newtable.f0: served but has no disposition (rows=1  text=1  distinct=1)",
        "gone.f3: has a disposition but is no longer served",
    ]


@pytest.mark.parametrize(
    ("line", "message"),
    [
        ("spell.f1  maybe  # unsure", "is not one of"),
        ("spell.f1  internal", "internal needs evidence"),
        ("spell.f1  no-display", "no-display needs evidence"),
        ("spell.f1  covered-by:x  # same", "covered-by needs the covering column"),
        ("spell.f1  surface:spell", "surface needs"),
        ("spell.f1  names:spell.f2", "names takes no target"),
        ("Spell.F1  names", "is not a column"),
        ("spell.f1  names\nspell.f1  internal  # dup", "second disposition"),
    ],
)
def test_a_disposition_without_a_stated_reason_is_refused(tmp_path: Path, line: str, message: str):
    _, problems = sd.parse(_write(tmp_path, line + "\n"))
    assert any(message in p for p in problems), problems


def test_covered_by_must_point_at_a_served_surface(tmp_path: Path):
    columns = {"a.f0": "rows=1  text=1  distinct=1", "b.f0": "rows=1  text=1  distinct=1"}
    dispositions, _ = sd.parse(_write(tmp_path, "a.f0  covered-by:b.f0  # same text\nb.f0  names\n"))
    assert sd.check(columns, dispositions) == [
        "a.f0: covered by b.f0, which is not a served column with a surface"
    ]


def test_empty_is_refused_once_the_column_has_text(tmp_path: Path):
    columns = {"a.f0": "rows=4  text=2  distinct=2"}
    dispositions, _ = sd.parse(_write(tmp_path, "a.f0  empty\n"))
    assert sd.check(columns, dispositions) == ["a.f0: marked empty but has text (rows=4  text=2  distinct=2)"]


def test_server_caches_and_unreadable_tables_take_dispositions(tmp_path: Path):
    columns = {"wdb-questcache.*": "records=2406", "odd.*": "unreadable: secondary-key table"}
    dispositions, problems = sd.parse(
        _write(tmp_path, "wdb-questcache.*  surface:quest.*\nodd.*  internal  # developer labels\n")
    )
    assert not problems
    assert sd.check(columns, dispositions) == []
    assert sd.text_lines("records=2406") == 2406
    assert sd.text_lines("unreadable: x") == 0
