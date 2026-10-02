"""The eight client tables the pipeline reads, as wago.tools-shaped CSVs from the local archive
(ADR-021).

The only place that knows which DB2 field is which column. Each table is pinned to the layout hash and field
count verified on Classic Era 1.15.9.69722, where every written column matched wago.tools' export
of that build. A table whose layout hash changed on a new build stops with both hashes named: its fields may
have moved, and the column map has to be re-verified before its CSV can be trusted.

Written columns use wago's names and CSV conventions (a line break as the two characters `\\n`, integers as
plain signed decimals), so `io/wago.py`'s readers take the files unchanged."""

from __future__ import annotations

import csv
import io
from collections.abc import Iterable
from dataclasses import dataclass, field, replace
from pathlib import Path

from wfj.io import casc, db2, dbcache, wago

ID = "id"  # the row id (id list, or the inline id field)
PARENT = "parent"  # the table's relationship map (a foreign id stored outside the record)


@dataclass(frozen=True)
class Column:
    name: str  # wago.tools column name
    source: int | str  # DB2 field index, ID or PARENT
    text: bool = False


@dataclass(frozen=True)
class Layout:
    """One build's shape for a table (ADR-027).

    A table is pinned to the layout hash it was verified on, and a build whose layout moved is refused rather
    than guessed at. Two clients are supported at once (Classic Era and Forever), so a table
    carries the alternates it has been verified on, each with the evidence that verified it. `columns`,
    `unwritten_strings` and `record` are given only when they differ from the table's own: most layout bumps
    move no column at all, and saying so explicitly is the point.
    """

    layout_hash: int
    field_count: int
    verified: str  # the build and the evidence, cited, never "trust me"
    columns: tuple[Column, ...] | None = None
    unwritten_strings: frozenset[int] | None = None
    record: tuple[str, ...] | None = None


@dataclass(frozen=True)
class Table:
    name: str
    file_data_id: int  # 1.15.9.69722; used only when the root carries no name hash for the path
    layout_hash: int
    field_count: int
    columns: tuple[Column, ...]
    # every string field, written or not: a sparse table stores strings inline, so an undeclared one would be
    # read at the wrong width (ItemSparse's Display1–3_lang)
    unwritten_strings: frozenset[int] = frozenset()
    # the declared type of every field in file order (dbcache.TYPES, `str`), then a non-inline
    # relation last: WoWDBDefs' definition at this layout hash. A table with a written number column needs
    # it: the hotfix decode reads every field at this size, and the sign of a number column comes from it.
    # Text-only tables leave it empty (their hotfixes are read as leading strings).
    record: tuple[str, ...] = ()
    # builds other than this table's own that the map has been verified on: `for_layout` picks one
    layouts: tuple[Layout, ...] = ()
    # a table only some builds ship. Its ABSENCE FROM THE ROOT is reported, not a failure: Classic
    # Era names no enUS content for ItemXItemEffect because that client does the join inline instead. Only
    # absence is forgiven: a table that is present and unreadable still fails the run, or an encrypted or
    # truncated table would quietly turn into "this build doesn't have it".
    optional: bool = False

    @property
    def path(self) -> str:
        return f"DBFilesClient\\{self.name}.db2"

    @property
    def leading_strings(self) -> int:
        """How many fields from field 0 on are strings: the part of a hotfix record readable without types."""
        n = 0
        while n in self.string_fields:
            n += 1
        return n

    @property
    def text_only(self) -> bool:
        """Every written column is the row id or one of the leading string fields: a hotfix is read as leading
        strings, and no column needs a declared type."""
        return all(
            c.source == ID or (c.text and isinstance(c.source, int) and c.source < self.leading_strings)
            for c in self.columns
        )

    @property
    def string_fields(self) -> frozenset[int]:
        return self.unwritten_strings | {
            c.source for c in self.columns if c.text and isinstance(c.source, int)
        }


def _c(name: str, source: int | str) -> Column:
    return Column(name, source, text=name.endswith("_lang") or name == "BaseTag")


_FOREVER = "1.60.1.70009"

# The tables whose text becomes a `ui` key family (`wago.TEXT_FAMILIES`, ADR-042). The primary layout
# is Classic Era's, verified against wago.tools' export of 1.15.9.69722 (every written column,
# `dev/client_tables --against`: 0 rows differ on each of the 9 tables Era ships rows for;
# HolidayDescriptions, CurrencyTypes and CurrencyCategory have none). The Forever layout, where it differs,
# carries its own evidence: `dev/verify_columns` against Classic Era, and wago's export of 1.60.1.70009 as
# the cross-check (ADR-027). A table whose layout hash is the same on both builds says so in its comment: one
# hash, one map (Forever still checked: 0 rows differ against wago 1.60.1.70009; cross-build 100% for
# EmotesTextData and CreatureType).
_TEXT_TABLES = (
    Table(
        "Faction",
        1361972,
        0x11322013,
        21,
        (_c("ID", ID), _c("Description_lang", 1)),
        frozenset({0}),  # Name_lang: a faction name stays English
        layouts=(
            Layout(
                0x6D443C38,
                21,
                f"{_FOREVER}, cross-build Description_lang 95.1% (39/41), wago 1.60.1.70009 0 rows "
                "differ",
            ),
        ),
    ),
    Table(
        "Achievement",
        1260179,
        0x657EBFFB,
        15,
        (_c("ID", ID), _c("Description_lang", 0), _c("Title_lang", 1), _c("Reward_lang", 2)),
        layouts=(
            Layout(
                0x6FC5281B,
                19,
                f"{_FOREVER}, cross-build Title_lang 96.8% (30/31; Era's 31 shared ids have no "
                "description or reward), wago 1.60.1.70009 0 rows differ",
            ),
        ),
    ),
    # one layout hash on both builds (67B2B4BD / 4 fields)
    Table("Achievement_Category", 1324299, 0x67B2B4BD, 4, (_c("ID", ID), _c("Name_lang", 0))),
    # the skills list's category headers ("Class Skills", "Armor Proficiencies"; UI/Skills.lua).
    # Forever's root names no path for it, so the FileDataID is the lookup there.
    Table(
        "SkillLineCategory",
        2179610,
        0xF61608B2,
        2,
        (_c("ID", ID), _c("Name_lang", 0)),
        layouts=(
            Layout(
                0x67B4FE22,
                2,
                f"{_FOREVER}, cross-build Name_lang 100% (9/9), wago 1.60.1.70009 0 rows differ",
            ),
        ),
    ),
    Table(
        "SkillLine",
        1240935,
        0x1123150E,
        13,
        (_c("ID", ID), _c("Description_lang", 2)),
        # DisplayName, AlternateVerb, HordeDisplayName, NeutralDisplayName: names and verbs, never imported
        frozenset({0, 1, 3, 4}),
        layouts=(
            Layout(
                0x6763217C,
                15,
                f"{_FOREVER}, cross-build Description_lang 100% (35/35), wago 1.60.1.70009 0 rows "
                "differ",
            ),
        ),
    ),
    # one layout hash on both builds (62B26C79 / 2 fields); EmotesTextID is the relationship map, not read
    Table("EmotesTextData", 1283024, 0x62B26C79, 2, (_c("ID", ID), _c("Text_lang", 0))),
    # one layout hash on both builds (A7B94A81 / 1 field); Classic Era ships the table with no rows
    Table("HolidayDescriptions", 996360, 0xA7B94A81, 1, (_c("ID", ID), _c("Description_lang", 0))),
    Table(
        "CurrencyTypes",
        1095531,
        0x3099E4BD,
        15,
        (_c("ID", ID), _c("Description_lang", 1)),
        frozenset({0}),  # Name_lang: a currency name stays English
        layouts=(
            Layout(
                0xEBEAF439,
                23,
                f"{_FOREVER}, Classic Era ships no rows (no cross-build oracle); wago 1.60.1.70009 0 "
                "rows differ, Name / Description pairs read as a pair (Honor Points → its honor text)",
            ),
        ),
    ),
    Table(
        "CurrencyCategory",
        1125667,
        0x12EB5F37,
        3,
        (_c("ID", ID), _c("Name_lang", 0)),
        layouts=(
            Layout(
                0x72B9AF57,
                4,
                f"{_FOREVER}, Classic Era ships no rows (no cross-build oracle); wago 1.60.1.70009 0 "
                "rows differ",
            ),
        ),
    ),
    Table(
        "SpellDispelType",
        1137829,
        0x47AA7AEB,
        4,
        (_c("ID", ID), _c("Name_lang", 0)),
        frozenset({1}),  # InternalName
        layouts=(
            Layout(
                0x3B574D4B,
                4,
                f"{_FOREVER}, cross-build Name_lang 100% (11/11), wago 1.60.1.70009 0 rows differ",
            ),
        ),
    ),
    # one layout hash on both builds (6FF4CA42 / 2 fields)
    Table("CreatureType", 1131315, 0x6FF4CA42, 2, (_c("ID", ID), _c("Name_lang", 0))),
    # ── character customization, PvP scoreboard, group finder, widget and item-name text. Each map checked:
    # Forever extract vs wago 1.60.1.70009 (0 rows differ) and,
    # where Classic Era ships the table with the same text field, Era vs wago 1.15.9.69722 and
    # `dev/verify_columns`.
    # The barber shop's customization tables (Blizzard_CharacterCustomize / CustomizationUI).
    Table(
        "ChrCustomizationCategory",
        3526439,
        0x1605B68A,
        8,
        (_c("ID", ID), _c("CategoryName_lang", 0)),
        # Classic Era's 7-field layout has no text field (every field reads as a number; 4 rows): the id only
        layouts=(
            Layout(
                0x7617515B, 7, "1.15.9.69722, no text field on this build", columns=(_c("ID", ID),)
            ),
        ),
    ),
    Table(
        "ChrCustomizationOption",
        3384247,
        0xEF4B96C5,
        12,
        (_c("ID", ID), _c("Name_lang", 0)),
        layouts=(Layout(
                0xDCC2A86E,
                13,
                f"{_FOREVER}, cross-build Name_lang 96.4% (81/84), wago 1.60.1.70009 0 rows differ",
            ),),
    ),
    # one layout hash on both builds (9559C358 / 11 fields); Classic Era's 746 rows carry no names
    Table("ChrCustomizationChoice", 3450554, 0x9559C358, 11, (_c("ID", ID), _c("Name_lang", 0))),
    Table(
        "ChrCustomizationReq",
        3450453,
        0xBAA785F6,
        10,
        (_c("ID", ID), _c("ReqSource_lang", 0)),
        layouts=(Layout(
                0xCA154412,
                9,
                f"{_FOREVER}, Classic Era's 4 shared rows carry no text; wago 1.60.1.70009 0 rows differ",
            ),),
    ),
    # The PvP scoreboard's stat columns: Forever only (Classic Era's root lists the FileDataID with no enUS
    # content).
    # Field 2 is an unnamed string (the tooltip title, the name again on every row read).
    Table(
        "PVPScoreboardColumnHeader",
        2992917,
        0xEA59FC11,
        4,
        (_c("ID", ID), _c("Name_lang", 0), _c("Tooltip_lang", 1)),
        frozenset({2}),
        optional=True,
    ),
    # The group finder (Blizzard_GroupFinder_VanillaStyle): categories, activity groups, activities.
    # one layout hash on both builds (0D5F1625 / 5 fields); Description_lang is empty on every row read
    Table("GroupFinderCategory", 974812, 0x0D5F1625, 5, (_c("ID", ID), _c("Name_lang", 0)), frozenset({1})),
    # one layout hash on both builds (B3F025D8 / 2 fields)
    Table("GroupFinderActivityGrp", 974814, 0xB3F025D8, 2, (_c("ID", ID), _c("Name_lang", 0))),
    Table(
        "GroupFinderActivity",
        974813,
        0xC3DB15C2,
        20,
        (_c("ID", ID), _c("FullName_lang", 0), _c("ShortName_lang", 1)),
        layouts=(Layout(
                0x410A29E6,
                21,
                f"{_FOREVER}, cross-build FullName_lang / ShortName_lang 100% (98/98), wago 1.60.1.70009 "
                "0 rows differ",
            ),),
    ),
    # The UI widgets' text (battleground and event status lines); one layout hash on both builds,
    # 0E572854 with 2 fields
    Table("UiWidgetStringSource", 1983641, 0x0E572854, 2, (_c("ID", ID), _c("Value_lang", 0))),
    # A wardrobe set variant's word (TransmogSet.ItemNameDescriptionID: Green / Blue / White / Grey)
    Table(
        "ItemNameDescription",
        1332559,
        0x4A3BF7A3,
        2,
        (_c("ID", ID), _c("Description_lang", 0)),
        layouts=(Layout(
                0xB616608D,
                2,
                f"{_FOREVER}, cross-build Description_lang 100% (22/22), wago 1.60.1.70009 0 rows differ",
            ),),
    ),
    Table(
        "QuestSort",
        1134585,
        0xADCB489B,
        2,
        (_c("ID", ID), _c("SortName_lang", 0)),
        layouts=(
            Layout(
                0x9B92BE63,
                3,
                f"{_FOREVER}, cross-build SortName_lang 100% (36/36), wago 1.60.1.70009 0 rows differ",
            ),
        ),
    ),
)

TABLES: dict[str, Table] = {
    t.name: t
    for t in (
        Table(
            "ItemSparse",
            1572924,
            0xB51F7C79,
            74,
            (_c("ID", ID), _c("Description_lang", 0), _c("Display_lang", 4)),
            frozenset({1, 2, 3}),
            # Forever: six fields gone, no column moved. {0,1,2,3,4} is the ONLY string set the reader
            # accepts (every other prefix leaves the 324-byte record 3 bytes short or over), and against the
            # Classic Era map Description_lang agrees 98.5% (1,534/1,557 non-empty) and Display_lang 99.2%
            # (14,154/14,266). The shortfall is content Forever reworded.
            layouts=(Layout(0x6FCC3191, 68, "1.60.1.69913, cross-build 98.5% / 99.2%"),),
        ),
        Table("SpellName", 1990283, 0x782EE721, 1, (_c("ID", ID), _c("Name_lang", 0))),
        Table(
            "Spell",
            1140089,
            0xE3D134FB,
            3,
            # NameSubtext_lang (field 0) is the spellbook subtext ("Racial Passive"), the
            # SpellSubtext:* UI family
            (
                _c("ID", ID),
                _c("NameSubtext_lang", 0),
                _c("Description_lang", 1),
                _c("AuraDescription_lang", 2),
            ),
        ),
        Table("GlobalStrings", 1394440, 0xD40F6D96, 3, (_c("BaseTag", 0), _c("TagText_lang", 1))),
        Table(
            "ItemSubClass",
            1261604,
            0x1E67DB87,
            11,
            # VerboseName_lang (field 1) is written too: the long name GetItemSubClassInfo returns
            # ("Staves", "One-Handed Axes"), the auction house's category words (ItemSubClassName:<c>:<s>)
            (_c("DisplayName_lang", 0), _c("VerboseName_lang", 1), _c("ClassID", 3), _c("SubClassID", 4)),
            frozenset(),
            # the record's fields in order: DisplayName, VerboseName, ID (inline), ClassID, SubClassID,
            # AuctionHouseSortOrder, PrerequisiteProficiency, Flags, DisplayFlags, WeaponSwingSize,
            # PostrequisiteProficiency
            record=("str", "str", "i32", "i8", "i8", "u8", "i8", "i32", "i32", "i8", "i8"),
        ),
        Table(
            "SpellItemEnchantment",
            1362771,
            0xC681231E,
            22,
            (_c("ID", ID), _c("Name_lang", 0)),
            frozenset({1}),
            # Forever: two fields added, Name_lang still field 0: 97.8% (2,109/2,157) against Classic Era.
            layouts=(Layout(0x952B72B2, 24, "1.60.1.69913, cross-build 97.8%"),),
        ),
        Table(
            "QuestV2",
            1139443,
            0xC6FAA9AA,
            1,
            (_c("ID", ID), _c("UniqueBitFlag", 0)),
            record=("i32",),
            # Forever: the row id became an INLINE field 0, pushing UniqueBitFlag to field 1, and a third
            # field was added that is 0 on every row read. Field 1 agrees 99.9% with Classic Era's field 0
            # while fields 0 and 2 agree 0.0%, so this is a move, not a content change. `record` is
            # [unverified] for hotfix decoding: this build's own hotfix cache holds no
            # QuestV2 entry, so none has been decoded; the three fields are declared i32 from their storage
            # widths.
            layouts=(
                Layout(
                    0x1854BDB9,
                    3,
                    "1.60.1.69913, cross-build 99.9% at field 1",
                    columns=(_c("ID", ID), _c("UniqueBitFlag", 1)),
                    record=("i32", "i32", "i32"),
                ),
            ),
        ),
        Table(
            "ItemEffect",
            969941,
            0x1BF9CF3A,
            9,
            (
                _c("ID", ID),
                _c("LegacySlotIndex", 0),
                _c("TriggerType", 1),
                _c("SpellID", 6),
                _c("ParentItemID", PARENT),
            ),
            # LegacySlotIndex, TriggerType, Charges, CoolDownMSec, CategoryCoolDownMSec, SpellCategoryID,
            # SpellID, ChrSpecializationID, PlayerConditionID; then ParentItemID (non-inline relation). ID is
            # non-inline.
            record=("u8", "u8", "i16", "i32", "i32", "u16", "i32", "u16", "i32", "i32"),
            # Forever: same nine fields, none moved (LegacySlotIndex 100.0%, TriggerType 99.6%, SpellID 72.2%
            # with the next-best field at 0.3%, so SpellID is in place and Forever rebalanced 28% of the
            # item->spell mappings). **ParentItemID does not resolve here**: every section reports
            # relationship_data_size 0, against Classic Era's 135,732 bytes, so the join moved out of this
            # table into ItemXItemEffect (below) and this table's ParentItemID column is written 0 on Forever
            # with a row-count note. See ADR-027.
            # With no relationship map there is no relation in a hotfix record either: the record is
            # the nine fields alone, 24 bytes. Seen on 1.60.1.69913's own DBCache.bin: both
            # ItemEffect entries (97156, 100060) are 24 bytes and decode to exactly the nine fields; the
            # Classic Era record (nine fields + ParentItemID, 28 bytes) stopped the run with "field 9 (i32)
            # runs past the 24-byte record".
            layouts=(
                Layout(
                    0x4CA77678,
                    9,
                    "1.60.1.69913, cross-build 100% / 99.6% / in-place",
                    record=("u8", "u8", "i16", "i32", "i32", "u16", "i32", "u16", "i32"),
                ),
            ),
        ),
        # Forever's item -> item-effect join, which Classic Era does not ship at all (its root names no enUS
        # content for this FileDataID). One inline field, ItemEffectID, with the owning ItemID in the
        # relationship map. Verified end to end rather than by cross-build agreement, because there is no
        # second client to compare against: item 4536 "Shiny Red Apple" -> effect 97715 -> ItemEffect.SpellID
        # 433 -> Spell.Description_lang "Restores $o1 health over $d.  Must remain seated while eating.",
        # which is character-for-character the English `data/english/item` already holds for that id.
        Table(
            "ItemXItemEffect",
            3177687,
            0x96F083AD,
            1,
            (_c("ID", ID), _c("ItemEffectID", 0), _c("ItemID", PARENT)),
            record=("i32", "i32"),
            optional=True,  # Classic Era does the join inline and ships no such table
        ),
        # the client-table text families (ADR-042). Every written column is the row id or a leading
        # string field, so each table is text-only and a hotfix is read as its leading strings (no `record`).
        # Names stay English: a name column is declared unwritten so the string layout reads, and is
        # never imported. Evidence per build: the client-table text research in docs/research/.
        *_TEXT_TABLES,
    )
}


class TableAbsent(LookupError):
    """An `optional` table this build does not ship. Reported by the caller, never a failed run."""


class TableError(ValueError):
    """A table's layout or rows are not what the column map was verified against."""


@dataclass
class Extracted:
    table: Table
    header: list[str]
    rows: list[list[str | int]]  # sorted by id
    skipped: list[db2.Skipped]
    copies_hidden: int = 0
    notes: list[str] = field(default_factory=list)
    hotfixed: dict[str, int] = field(default_factory=dict)  # replaced / added / removed row counts
    # comparison key → the row's written values before its hotfix (None: the hotfix added it); the
    # cross-check excuses a difference only where wago's value is still the archive's
    prehotfix: dict[tuple, dict[str, str | int] | None] = field(default_factory=dict)


def _as_declared(table: Table, column: Column, v: int) -> int:
    """An archive value as its declared type reads it: the reader returns packed fields sign-extended
    to their stored bits or unsigned, so the value is cut to the declared size and signed if the type is. A
    number column with no declared type is refused: its sign would be a guess."""
    if not table.record:
        raise TableError(
            f"{table.name}: {column.name} is a number column but the table declares no field types"
        )
    size, signed = dbcache.TYPES[table.record[int(column.source)]]
    bits = size * 8
    v &= (1 << bits) - 1
    return v - (1 << bits) if signed and v >> (bits - 1) else v


def extract(
    archive: casc.LocalArchive, table: Table, hotfixes: dbcache.HotfixCache | None = None
) -> Extracted:
    """The table's rows as written columns; `hotfixes` (the client's DBCache.bin) are applied over the archive
    rows."""
    try:
        fdid = archive.file_data_id(table.path, fallback=table.file_data_id)
        buf, gaps = archive.read_file(fdid)
        header = db2.read_header(buf, table.name)
    except casc.CascError as e:
        # an optional table the root does not name is this build not shipping it, which is a fact about the
        # build; anything else is a failure to read something that is there
        # a root that lists the FileDataID with no enUS content key is the same fact
        if table.optional and ("names 0 enUS files" in str(e) or "has 0 enUS content keys" in str(e)):
            raise TableAbsent(f"{table.name}: not shipped on this build ({e})") from e
        raise TableError(str(e)) from e
    except db2.Db2Error as e:
        raise TableError(str(e)) from e
    # the layout is checked before any row is decoded: a moved field fails here with this message, not with a
    # decoding error further in
    table = for_layout(table, header)
    try:
        t = db2.read(buf, table.string_fields, gaps, name=table.name)
    except db2.Db2Error as e:
        raise TableError(str(e)) from e
    by_id: dict[int, list[str | int]] = {}
    no_parent = 0
    for rid in sorted(t.rows):
        values = t.rows[rid]
        row: list[str | int] = []
        for c in table.columns:
            if c.source == ID:
                row.append(rid)
            elif c.source == PARENT:
                # a record the relationship map leaves out has no parent: 0, as wago.tools writes it
                no_parent += rid not in t.relation
                row.append(t.relation.get(rid, 0))
            else:
                v = values[c.source]
                if isinstance(v, list):
                    raise TableError(f"{table.name}: {c.name} (field {c.source}) is an array")
                row.append(v if c.text else _as_declared(table, c, v))
        by_id[rid] = row
    ex = Extracted(table, [c.name for c in table.columns], [], t.skipped, t.copies_hidden)
    fixes = hotfixes.by_table.get(header.table_hash, {}) if hotfixes else {}
    if fixes:
        _apply_hotfixes(table, by_id, fixes, ex)
    ex.rows = [by_id[rid] for rid in sorted(by_id)]
    if no_parent:
        ex.notes.append(
            f"{no_parent} rows without a {next(c.name for c in table.columns if c.source == PARENT)}"
            " (written as 0)"
        )
    return ex


def _apply_hotfixes(
    table: Table, by_id: dict[int, list[str | int]], fixes: dict[int, dbcache.Hotfix], ex: Extracted
) -> None:
    counts = {"replaced": 0, "added": 0, "removed": 0}
    for rid, fix in sorted(fixes.items()):
        before = by_id.get(rid)
        if not fix.replaces:
            if before is not None:
                ex.prehotfix.setdefault(_row_key(table, before), _named(table, before))
                del by_id[rid]
                counts["removed"] += 1
            continue
        try:
            row = _hotfix_row(table, rid, fix.data)
        except (ValueError, UnicodeDecodeError) as e:
            raise TableError(f"{table.name}: hotfix of row {rid}: {e}") from e
        if before is not None:
            ex.prehotfix.setdefault(_row_key(table, before), _named(table, before))
        ex.prehotfix.setdefault(_row_key(table, row), None if before is None else _named(table, before))
        counts["replaced" if before is not None else "added"] += 1
        by_id[rid] = row
    ex.hotfixed = counts


def _hotfix_row(table: Table, rid: int, data: bytes) -> list[str | int]:
    """The written columns of one hotfix record: the whole record by declared types when the table has them,
    else its leading strings."""
    if not table.record:
        if not table.text_only:
            raise ValueError("the table declares no field types for its number columns")
        texts = dbcache.leading_strings(data, table.leading_strings)
        return [rid if c.source == ID else texts[int(c.source)] for c in table.columns]
    values = dbcache.decode_fields(data, table.record)
    row: list[str | int] = []
    for c in table.columns:
        if c.source == ID:
            row.append(rid)
        elif c.source == PARENT:
            # a record of the fields alone is a build with no relationship map (Forever's
            # ItemEffect): no parent, 0, as extract() writes for its archive rows. decode_fields has already
            # checked the fit.
            if len(table.record) == table.field_count:
                row.append(0)
            elif len(table.record) == table.field_count + 1:
                row.append(values[-1])
            else:
                raise ValueError(f"{c.name}: the declared record has no non-inline relation after the fields")
        else:
            row.append(values[int(c.source)])
    return row


def _named(table: Table, row: list[str | int]) -> dict[str, str | int]:
    """A written row as the comparison reads it (parsed values)."""
    return {
        c.name: parse_value(c, v.replace("\n", "\\n") if isinstance(v, str) else str(v))
        for c, v in zip(table.columns, row, strict=True)
    }


def _row_key(table: Table, row: list[str | int]) -> tuple:
    named = {c.name: v for c, v in zip(table.columns, row, strict=True)}
    return _key(table, {k: str(v) for k, v in named.items()})


def write_csv(ex: Extracted, path: Path) -> None:
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(ex.header)
    for row in ex.rows:
        w.writerow([v.replace("\n", "\\n") if isinstance(v, str) else v for v in row])
    Path(path).write_text(buf.getvalue(), encoding="utf-8")


# --- comparison (the proof against wago.tools, and the beta-day cross-check)
# ---------------------------------


def parse_value(column: Column, text: str) -> str | int:
    """One CSV cell as the importers read it: text with `\\n` as a line break and outer whitespace stripped
    (as `read_names`), everything else an int."""
    if column.text:
        return (text or "").replace("\\n", "\n").strip()
    try:
        return int(text)
    except ValueError as e:
        raise TableError(f"{column.name}: {text!r} is not an integer") from e


def _key(table: Table, row: dict[str, str]) -> tuple:
    """A row's comparison key, parsed as its values are: `int` ids, and a BaseTag stripped like the
    text `parse_value` compares, so two rows that parse to the same key collide in `read_parsed` and raise
    instead of passing as two rows."""
    if any(c.source == ID for c in table.columns):
        return (int(row["ID"]),)
    if table.name == "GlobalStrings":
        return ((row["BaseTag"] or "").strip(),)
    return (int(row["ClassID"]), int(row["SubClassID"]))  # ItemSubClass


def _header(path: Path) -> list[str]:
    with Path(path).open(encoding="utf-8", newline="") as f:
        return next(csv.reader(f), [])


def skipped_columns(table: Table, theirs: Path) -> list[str]:
    """The relation columns the other export leaves out. A relation column is not in the record: on Forever
    ItemEffect has no parent relation and ours writes 0 (see its layout), and wago.tools drops the column, so
    it is not compared. Only a relation column may be missing; any other is still an error."""
    header = _header(theirs)
    return [c.name for c in table.columns if c.source == PARENT and c.name not in header]


def read_parsed(
    table: Table, path: Path, skip: Iterable[str] = ()
) -> dict[tuple, dict[str, str | int]]:
    """A CSV (ours or wago's, any extra columns ignored) → {row key: {column: parsed value}}, without the
    `skip` columns."""
    skip = set(skip)
    columns = [c for c in table.columns if c.name not in skip]
    out: dict[tuple, dict[str, str | int]] = {}
    with Path(path).open(encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        missing = [c.name for c in columns if c.name not in (reader.fieldnames or [])]
        if missing:
            raise TableError(f"{Path(path).name}: no column {missing}")
        for row in reader:
            key = _key(table, row)
            if key in out:
                raise TableError(f"{Path(path).name}: row {key} listed twice")
            out[key] = {c.name: parse_value(c, row[c.name]) for c in columns}
    return out


@dataclass
class Difference:
    key: tuple
    column: str
    ours: str | int | None
    theirs: str | int | None


def compare(table: Table, ours: Path, theirs: Path) -> tuple[int, int, list[Difference]]:
    """(rows ours, rows theirs, differences). A row only one side has is a difference on every column."""
    skip = skipped_columns(table, theirs)
    a, b = read_parsed(table, ours, skip), read_parsed(table, theirs, skip)
    diffs = []
    for key in sorted(a.keys() | b.keys(), key=lambda k: tuple(str(x) for x in k)):
        ra, rb = a.get(key), b.get(key)
        for c in (c for c in table.columns if c.name not in skip):
            va = None if ra is None else ra[c.name]
            vb = None if rb is None else rb[c.name]
            if va != vb:
                diffs.append(Difference(key, c.name, va, vb))
    return len(a), len(b), diffs


# The importers' own readers, where one covers the table: the proof also compares what they return from both
# files.
READERS = {
    "ItemSparse": lambda p: dict(wago.read_names(p, "ID", "Display_lang")),
    "SpellName": lambda p: dict(wago.read_names(p, "ID", "Name_lang")),
    "GlobalStrings": wago.read_global_strings,
    "ItemSubClass": wago.read_item_subclasses,
    "QuestV2": wago.read_ids,
}


def compare_readers(table: Table, ours: Path, theirs: Path) -> list[str]:
    """Keys on which the importer's reader returns different values for the two files ([] when equal or when
    no reader covers the table)."""
    reader = READERS.get(table.name)
    if reader is None:
        return []
    a, b = reader(Path(ours)), reader(Path(theirs))
    if isinstance(a, set):  # QuestV2: the id set
        return [str(k) for k in sorted(a ^ b)]
    return [str(k) for k in sorted(a.keys() | b.keys(), key=str) if a.get(k) != b.get(k)]


def reader_row_key(table: Table, reader_key: str) -> tuple:
    """The comparison key of the row an importer reader's key names (`compare_readers` output)."""
    if table.name == "GlobalStrings":
        return (reader_key,)
    if table.name == "ItemSubClass":  # "ItemSubClass:<class>:<subclass>"
        _, cls, sub = reader_key.split(":")
        return (int(cls), int(sub))
    return (int(reader_key),)


def for_layout(table: Table, header: db2.Header) -> Table:
    """The table's column map for the build in `header` (ADR-027).

    The table's own layout, or one of the alternates it has been verified on. A layout nobody verified is
    refused with both hashes named: the map may still be right, but nothing has shown that it is, and
    importing English through an unverified map is how plausible garbage gets translated and shipped.
    """
    if header.layout_hash == table.layout_hash and header.field_count == table.field_count:
        return table
    for alt in table.layouts:
        if header.layout_hash == alt.layout_hash and header.field_count == alt.field_count:
            return replace(
                table,
                layout_hash=alt.layout_hash,
                field_count=alt.field_count,
                columns=alt.columns if alt.columns is not None else table.columns,
                unwritten_strings=(
                    alt.unwritten_strings
                    if alt.unwritten_strings is not None
                    else table.unwritten_strings
                ),
                record=alt.record if alt.record is not None else table.record,
            )
    verified = ", ".join(
        f"{t.layout_hash:08x}/{t.field_count}f" for t in (table, *table.layouts)
    )
    raise TableError(
        f"{table.name}: layout hash {header.layout_hash:08x}/{header.field_count}f, "
        f"column map verified on {verified}; "
        "layout changed on this build, column map needs re-verifying"
    )


def select(names: Iterable[str] | None) -> list[Table]:
    if not names:
        return list(TABLES.values())
    unknown = [n for n in names if n not in TABLES]
    if unknown:
        raise TableError(f"unknown table {unknown} (have {list(TABLES)})")
    return [TABLES[n] for n in names]
