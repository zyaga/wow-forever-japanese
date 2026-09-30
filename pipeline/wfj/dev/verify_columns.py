"""Prove a table's column map against a second client, instead of bumping its layout hash (ADR-027).

    python -m wfj.dev.verify_columns --wow "<World of Warcraft>" \
        --product wow_classic_beta --against-product wow_classic_era [--tables ItemSparse …]

`io/client_tables.py` pins each table to the layout hash it was verified on, and refuses a build whose layout
moved rather than guess which DB2 field is which column (a wrong column would key text to the wrong id).
wago.tools is not used as a source, and it is not needed: a second installed client whose map is already
verified is a better oracle, because it is the same field of the same table read by the same code.

Two independent constraints, both reported:

1. **Which string-field sets parse at all.** A sparse table (`ItemSparse`, `Spell`) stores its strings inline,
   so the reader must be told which fields are strings; a wrong set makes the fields stop short of the record
   or run past it and `io/db2.py` raises. On Forever's ItemSparse exactly one prefix parses, which fixes the
   string layout before any content is compared.
2. **Cross-build agreement per written text column.** For ids in both clients, how often the same field holds
   the same string. A column that did not move scores very high; the shortfall is the content the new build
   actually changed. A column that moved scores near zero, and the report names the field that scores high
   instead, which is how `QuestV2`'s `UniqueBitFlag` was found at field 1.

Read-only: both installs are read through `io/casc.py` under ADR-021, and nothing is written anywhere.
Exit 1 when a table cannot be read on either client, or when two clients share no ids for a table (no shared
ids is an absence of evidence, never a 0% verdict)."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

from wfj.io import casc, client_tables, db2

MAX_STRING_PREFIX = 8  # how many leading fields to try as the string set for a sparse table


@dataclass(frozen=True)
class ColumnReport:
    name: str  # wago column name
    field: int  # the field index the map claims
    shared: int  # ids present on both clients
    compared: int  # of those, the ones non-empty on the oracle
    agree: int
    best_field: int | None  # the field that agreed most, when it is not `field`
    best_agree: float

    @property
    def rate(self) -> float:
        return self.agree / self.compared if self.compared else 0.0


@dataclass(frozen=True)
class TableReport:
    name: str
    layout: int
    oracle_layout: int
    fields: int
    oracle_fields: int
    parses: tuple[frozenset[int], ...]  # string-field sets that parsed (sparse tables only)
    columns: tuple[ColumnReport, ...]
    note: str = ""


def string_sets_that_parse(buf: bytes, gaps: list, name: str,
                           limit: int = MAX_STRING_PREFIX) -> tuple[frozenset[int], ...]:
    """Every leading string-field set `0..k` the reader accepts. One result fixes the string layout."""
    out = []
    for k in range(limit + 1):
        sset = frozenset(range(k))
        try:
            db2.read(buf, string_fields=sset, encrypted=gaps, name=name)
        except db2.Db2Error:
            continue
        out.append(sset)
    return tuple(out)


def _rows(archive: casc.LocalArchive, table: client_tables.Table, name: str):
    try:
        buf, gaps = archive.read_file(archive.file_data_id(table.path, table.file_data_id))
    except casc.CascError as e:
        if table.optional and "names 0 enUS files" in str(e):
            raise client_tables.TableAbsent(f"{name} is not shipped on one of the two clients") from e
        raise
    header = db2.read_header(buf, name)
    return buf, gaps, header


def compare(table: client_tables.Table, subject: casc.LocalArchive,
            oracle: casc.LocalArchive) -> TableReport:
    """One table's report: which string sets parse on the subject, and how each written text column agrees."""
    sbuf, sgaps, shead = _rows(subject, table, table.name)
    obuf, ogaps, ohead = _rows(oracle, table, table.name)
    parses = string_sets_that_parse(sbuf, sgaps, table.name) if shead.flags & db2.FLAG_SPARSE else ()
    strings = table.string_fields
    stab = db2.read(sbuf, string_fields=strings, encrypted=sgaps, name=table.name)
    otab = db2.read(obuf, string_fields=strings, encrypted=ogaps, name=table.name)
    shared = sorted(set(stab.rows) & set(otab.rows))
    if not shared:
        raise client_tables.TableError(
            f"{table.name}: the two clients share no ids; no evidence either way, not a 0% verdict"
        )
    columns = []
    for col in table.columns:
        if not isinstance(col.source, int):
            continue  # ID / PARENT are not fields
        compared = [i for i in shared if otab.rows[i][col.source] not in ("", None)]
        agree = sum(1 for i in compared if stab.rows[i][col.source] == otab.rows[i][col.source])
        # when the claimed field disagrees, name the field that agrees best: a moved column, not
        # a changed one
        best_field, best_rate = None, 0.0
        if compared and agree / len(compared) < 0.9:
            for fi in range(shead.field_count):
                hit = sum(1 for i in compared if stab.rows[i][fi] == otab.rows[i][col.source])
                if hit / len(compared) > best_rate:
                    best_field, best_rate = fi, hit / len(compared)
        columns.append(ColumnReport(col.name, col.source, len(shared), len(compared), agree,
                                    best_field, best_rate))
    note = ""
    if not stab.relation and otab.relation:
        note = (f"relationship map empty on the subject ({len(otab.relation)} on the oracle); a "
                f"non-inline relation column cannot be read here")
    return TableReport(table.name, shead.layout_hash, ohead.layout_hash, shead.field_count,
                       ohead.field_count, parses, tuple(columns), note)


def lines(report: TableReport) -> list[str]:
    out = [f"{report.name}: subject 0x{report.layout:08X}/{report.fields}f · "
           f"oracle 0x{report.oracle_layout:08X}/{report.oracle_fields}f"]
    if report.parses:
        sets = " ".join("{" + ",".join(str(i) for i in sorted(s)) + "}" if s else "{}" for s in report.parses)
        unique = " (unique: the string layout is fixed)" if len(report.parses) == 1 else ""
        out.append(f"  string sets that parse: {sets}{unique}")
    for c in report.columns:
        # three outcomes, not two: a low rate with no better field means the column is still in the right
        # place and the build changed its content, which is a finding about the data, not about the map.
        moved = c.best_field is not None and c.best_field != c.field and c.best_agree > c.rate
        if c.rate >= 0.9:
            verdict = "unchanged"
        elif moved:
            verdict = f"MOVED: field {c.best_field} agrees {c.best_agree:.1%} instead"
        else:
            verdict = "position unchanged, content differs on this build"
        out.append(f"  {c.name} = field {c.field}: {c.agree}/{c.compared} = {c.rate:.1%} "
                   f"({c.shared} shared ids): {verdict}")
    if report.note:
        out.append(f"  note: {report.note}")
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wfj.dev.verify_columns", description=__doc__.split("\n\n")[0])
    ap.add_argument("--wow", required=True, type=Path, help="the folder holding .build.info")
    ap.add_argument("--product", required=True, help="the build to verify")
    ap.add_argument("--against-product", required=True, help="a build whose column map is already verified")
    ap.add_argument("--tables", nargs="+", help=f"subset of {list(client_tables.TABLES)}")
    args = ap.parse_args(argv)
    try:
        tables = client_tables.select(args.tables)
        subject = casc.LocalArchive(args.wow, args.product)
        oracle = casc.LocalArchive(args.wow, args.against_product)
    except (casc.CascError, client_tables.TableError) as e:
        print(f"verify-columns: {e}", file=sys.stderr)
        return 1
    print(f"subject: {subject.info.version} ({args.product})")
    print(f"oracle:  {oracle.info.version} ({args.against_product})")
    failed = False
    for table in tables:
        try:
            print("\n".join(lines(compare(table, subject, oracle))))
        except client_tables.TableAbsent as e:
            # a table only one of the two clients ships has no cross-build evidence to give, and saying so is
            # the honest report: ItemXItemEffect exists only on Forever, so it is verified end to end instead
            print(f"{table.name}: no cross-build evidence; {e}")
        except (casc.CascError, client_tables.TableError, db2.Db2Error) as e:
            print(f"{table.name}: {e}", file=sys.stderr)
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
