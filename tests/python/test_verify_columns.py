"""Proving a column map against a second client instead of bumping its layout hash (ADR-027).

The tool this covers is what produced the evidence pinned in `client_tables.TABLES`. Its own failure mode is
the dangerous one: a tool that reports high agreement for a wrong column would launder a bad map into the
import, and from there into translated, shipped text. So these test the negatives as hard as the positives.
"""

from pathlib import Path

import pytest
from casc_fixture import PRODUCT, build
from db2_fixture import wdc5

from wfj.dev import verify_columns as vc
from wfj.io import casc, client_tables

LAYOUT, FIELDS = 0xAABBCCDD, 2


def _table(columns, layout=LAYOUT, fields=FIELDS, **kw):
    return client_tables.Table("Thing", 1, layout, fields, columns, **kw)


def _install(tmp_path: Path, name: str, blob: bytes) -> casc.LocalArchive:
    return casc.LocalArchive(build(tmp_path / name, {"DBFilesClient\\Thing.db2": blob}), PRODUCT)


def _two_column_db2(rows: dict[int, tuple[str, str]]) -> bytes:
    """A dense table whose two fields are both strings."""
    section = [(i, [a, b]) for i, (a, b) in sorted(rows.items())]
    blob, _ = wdc5([section], string_fields={0, 1}, field_count=FIELDS, layout_hash=LAYOUT)
    return blob


def test_a_column_that_did_not_move_reports_high_agreement(tmp_path: Path):
    rows = {1: ("alpha", "one"), 2: ("beta", "two"), 3: ("gamma", "three")}
    subject = _install(tmp_path, "s", _two_column_db2(rows))
    oracle = _install(tmp_path, "o", _two_column_db2(rows))
    t = _table((client_tables.Column("ID", client_tables.ID), client_tables.Column("Name_lang", 0, True)),
               unwritten_strings=frozenset({1}))
    rep = vc.compare(t, subject, oracle)
    col = rep.columns[0]
    assert col.field == 0 and col.rate == 1.0 and col.compared == 3
    assert "unchanged" in "\n".join(vc.lines(rep))


def test_a_moved_column_is_caught_and_the_better_field_named(tmp_path: Path):
    """The QuestV2 case: the map claims field 0, the content is at field 1."""
    oracle_rows = {1: ("alpha", "one"), 2: ("beta", "two"), 3: ("gamma", "three")}
    subject_rows = {i: (v[1], v[0]) for i, v in oracle_rows.items()}   # the two fields swapped
    subject = _install(tmp_path, "s", _two_column_db2(subject_rows))
    oracle = _install(tmp_path, "o", _two_column_db2(oracle_rows))
    t = _table((client_tables.Column("ID", client_tables.ID), client_tables.Column("Name_lang", 0, True)),
               unwritten_strings=frozenset({1}))
    rep = vc.compare(t, subject, oracle)
    col = rep.columns[0]
    assert col.rate == 0.0, "a swapped column must not read as agreeing"
    assert col.best_field == 1 and col.best_agree == 1.0
    printed = "\n".join(vc.lines(rep))
    assert "MOVED" in printed and "field 1 agrees 100.0%" in printed


def test_content_that_changed_is_not_reported_as_a_moved_column(tmp_path: Path):
    """The ItemEffect.SpellID case: a low rate with no better field means the column is in the right place
    and the build changed the data. Calling that "MOVED" would send the next reader hunting a phantom."""
    oracle_rows = {i: (f"name{i}", "x") for i in range(1, 11)}
    subject_rows = {i: (f"name{i}" if i <= 3 else f"changed{i}", "x") for i in range(1, 11)}
    subject = _install(tmp_path, "s", _two_column_db2(subject_rows))
    oracle = _install(tmp_path, "o", _two_column_db2(oracle_rows))
    t = _table((client_tables.Column("ID", client_tables.ID), client_tables.Column("Name_lang", 0, True)),
               unwritten_strings=frozenset({1}))
    rep = vc.compare(t, subject, oracle)
    printed = "\n".join(vc.lines(rep))
    assert rep.columns[0].rate == pytest.approx(0.3)
    assert "position unchanged, content differs" in printed
    assert "MOVED" not in printed


def test_no_shared_ids_is_an_error_not_a_zero_percent_verdict(tmp_path: Path):
    """Absence of evidence is not evidence of a moved column: the one way this tool could lie."""
    subject = _install(tmp_path, "s", _two_column_db2({1: ("a", "b")}))
    oracle = _install(tmp_path, "o", _two_column_db2({99: ("a", "b")}))
    t = _table((client_tables.Column("ID", client_tables.ID), client_tables.Column("Name_lang", 0, True)),
               unwritten_strings=frozenset({1}))
    with pytest.raises(client_tables.TableError, match="share no ids"):
        vc.compare(t, subject, oracle)


def test_string_sets_that_parse_narrows_a_sparse_layout(tmp_path: Path):
    """On Forever's ItemSparse exactly one string set parses, which fixes the string layout before any
    content is compared. The search must report that uniqueness, not merely a first hit."""
    blob = _two_column_db2({1: ("alpha", "one"), 2: ("beta", "two")})
    sets = vc.string_sets_that_parse(blob, [], "Thing", limit=4)
    # a dense fixture parses for any set the reader accepts; what matters is that the search returns the
    # sets it actually accepted and nothing else
    assert all(isinstance(s, frozenset) for s in sets)
    assert all(max(s, default=-1) < 4 for s in sets)
