"""wfj import predecessor / questjapanizer / craftjapanizer-quest: the Japanese corpus from the predecessor
addons and their lineage sources (see cmd/import_.py's docstring and docs/systems/pipeline.md).

`predecessor` rebuilds the quest/item/spell stores from its inputs and carries the human decisions, machine
drafts and English baselines already in them (core/decisions, ADR-012); the lineage importers merge
into the existing quest store. The Collector collapses identical duplicates and records conflicts."""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import re
import subprocess
import unicodedata
from collections.abc import Iterable, Sequence
from pathlib import Path
from typing import Any

from wfj.core import decisions, dedupe
from wfj.core.dedupe import ANONYMOUS_TRANSLATORS
from wfj.core.model import entry, provenance
from wfj.core.paragraphs import normalize_breaks
from wfj.io.jsonl_store import Store
from wfj.io.lua_reader import Table, as_int_id, parse_assignment
from wfj.paths import data_root

QUEST_FIELDS = {
    "Title": "title",
    "Objectives": "objectives",
    "Description": "description",
    "Progress": "progress",
    "Completion": "completion",
}
_WS = re.compile(r"\s+")
# Player placeholders as the three lineages wrote them → the corpus form the addon renders.
# `YOUR_NAME` / `<name>` in any letter case (the wiki had `<Class>` too).
_PLACEHOLDER = re.compile(r"YOUR_(NAME|CLASS|RACE)|<(NAME|CLASS|RACE)>", re.I)
_MARKUP = re.compile(r"</?blockquote>", re.I)  # wiki markup that leaked into a few rows
# A translator credit closing a wiki row: its own final paragraph, or glued to the last sentence, as in
# `翻訳:Az`, `翻訳： Pepper Pot`, `翻訳　Forsaken`, `[翻訳：Narks]`.
_CREDIT = re.compile(
    r"(?:^|\n\n|(?<=[。！？!?」』）)]))[ \u3000]*\[?翻訳[:：\u3000 ][ \u3000]*([^\n]+?)\]?[ \u3000]*$"
)


def prepare_ja(field: str, ja: str) -> str:
    """Placeholders, markup removal + canonical paragraph breaks (titles keep their whitespace)."""
    ja = _PLACEHOLDER.sub(lambda m: "{" + (m.group(1) or m.group(2)).lower() + "}", ja)
    ja = _MARKUP.sub("", ja).strip()
    return ja if field == "title" else normalize_breaks(ja)


def strip_credit(ja: str) -> tuple[str, str | None]:
    """Split a trailing `翻訳:<name>` credit off a prepared prose value → (text, credit or None)."""
    m = _CREDIT.search(ja)
    if not m:
        return ja, None
    return ja[: m.start()].rstrip(), m.group(1).strip()


def git_head(repo: Path) -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--short=7", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        raise ValueError(
            f"{repo} is not a git checkout; pass --commit-quest / --commit-tooltip explicitly"
        ) from e


def ja_identity(ja: str) -> str:
    return _WS.sub(" ", unicodedata.normalize("NFC", ja)).strip()


def _substitute_values(text: str, values: Table | None) -> str:
    if values is None:
        return text
    for k, v in values.named().items():
        text = text.replace(f"${k}", str(v))
    return text


class Collector:
    """Accumulates (id, field) lines; collapses identical duplicates, records conflicts."""

    def __init__(self) -> None:
        self.lines: dict[tuple[int, str], dict[str, Any]] = {}
        self.collapsed = 0
        self.conflicts = 0
        self.empty = 0
        self.dropped = 0
        self.relabelled = 0
        self.credited = 0
        self.credit_tails = 0  # prose values that still contain 翻訳 after strip_credit (visible residue)
        self.carried_corrections = 0
        self.carried_rulings = 0  # ruled imported variants carried (re-attached or kept whole)
        self.redundant_corrections = 0  # a correction byte-identical (NFC) to a correction already carried
        self.orphaned_rejects = 0  # reject-ruled variants whose (id, field) the inputs no longer produce
        # the orphaned variants themselves, carried again after the lineage merge: a line only a
        # lineage source produces (quest 1958 objectives) does not exist yet when decisions are first carried
        self.orphans: list[tuple[Any, str, dict[str, Any]]] = []
        self.carried_machine = 0  # machine drafts carried (ADR-014)
        self.redundant_machine = 0  # a machine draft identical (ja_identity) to a variant already present
        self.carried_english = 0  # english baselines put back on a rebuilt (id, field)
        self.english_not_produced = 0  # english baselines whose (id, field) the rebuild no longer has

    def seed(self, existing: list[dict[str, Any]]) -> None:
        """Start from the lines already in the store so a new source merges instead of overwriting."""
        for line in existing:
            self.lines[(line["id"], line["field"])] = line

    def add(
        self,
        id_: int,
        field: str,
        ja: str,
        prov: dict[str, Any],
        origin: str,
        extra: dict[str, Any] | None = None,
    ) -> None:
        if not ja.strip():
            self.empty += 1
            return
        k = (id_, field)
        if k not in self.lines:
            p = {kk: v for kk, v in prov.items() if kk != "origins"}
            p["origins"] = [origin]
            self.lines[k] = entry(id_, field, ja, prov=p, extra=extra)
            return
        line = self.lines[k]
        ident = ja_identity(ja)
        # A correction is a person's text and a machine draft is a model's, never an import target:
        # identical imported text becomes its own variant beside it, so each keeps its attribution
        # (ADR-012, ADR-014).
        if ja_identity(line["ja"]) == ident and not self._authored(line["provenance"]):
            self._append_origin(line["provenance"], origin)
            if extra and "extra" not in line:  # keep the first non-empty extra across a collapse
                line["extra"] = extra
            self._adopt_credit(line["provenance"], prov)
            self.collapsed += 1
            return
        for c in line["conflicts"]:  # identical to an existing variant → same variant, one more origin
            if ja_identity(c["ja"]) == ident and not self._authored(c["provenance"]):
                self._append_origin(c["provenance"], origin)
                self._adopt_credit(c["provenance"], prov)
                self.collapsed += 1
                return
        p = {kk: v for kk, v in prov.items() if kk != "origins"}
        p["origins"] = [origin]
        conflict: dict[str, Any] = {"ja": ja, "provenance": p}
        if extra:
            conflict["extra"] = extra
        line["conflicts"].append(conflict)
        self.conflicts += 1

    def carry(self, id_: int | str, field: str, variant: dict[str, Any]) -> None:
        """Put a human decision or a machine draft (core/decisions.carried, in its canonical order) back
        into a rebuilt store.

        - a correction is always kept as its own variant; only a byte-identical (NFC) correction already
          present makes it redundant (counted); identical *imported* text never absorbs it, whitespace and
          paragraph breaks included;
        - a machine draft is kept as its own variant; one identical (`ja_identity`) to a variant already
          present is redundant (counted);
        - a ruled imported variant whose text (`ja_identity`) a rebuilt variant has → that variant takes the
          ruling; new text → appended as its own variant;
        - an (id, field) the inputs no longer produce → the variant becomes the line, except a `reject`-ruled
          one with nothing to be rejected against: counted as orphaned, not shipped as a lone variant."""
        correction = decisions.is_correction(variant["provenance"])
        machine = decisions.is_machine(variant["provenance"])
        k = (id_, field)
        if k not in self.lines:
            if decisions.is_rejected(variant):
                self.orphaned_rejects += 1
                self.orphans.append((id_, field, variant))
                return
            line = entry(id_, field, variant["ja"], prov=variant["provenance"], extra=variant.get("extra"))
            if variant.get("ruling"):
                line["ruling"] = variant["ruling"]
            self.lines[k] = line
        else:
            line = self.lines[k]
            if self._absorbed(line, variant, correction, machine):
                return
            kept: dict[str, Any] = {"ja": variant["ja"], "provenance": variant["provenance"]}
            if variant.get("extra"):
                kept["extra"] = variant["extra"]
            if variant.get("ruling"):
                kept["ruling"] = variant["ruling"]
            line["conflicts"].append(kept)
        if correction:
            self.carried_corrections += 1
        elif machine:
            self.carried_machine += 1
        else:
            self.carried_rulings += 1

    def _absorbed(
        self, line: dict[str, Any], variant: dict[str, Any], correction: bool, machine: bool
    ) -> bool:
        """True when a variant already on the line takes the carried one (counted here), so nothing is
        appended (`carry`)."""
        variants = [line, *line["conflicts"]]
        if correction:
            same = decisions.exact(variant["ja"])
            corrections = (t for t in variants if decisions.is_correction(t["provenance"]))
            target = next((t for t in corrections if decisions.exact(t["ja"]) == same), None)
            if target is not None:
                self.redundant_corrections += 1
                return True
        elif machine:
            # a machine draft is kept as its own variant; one identical to a variant present adds nothing
            ident = ja_identity(variant["ja"])
            if any(ja_identity(t["ja"]) == ident for t in variants):
                self.redundant_machine += 1
                return True
        else:
            ident = ja_identity(variant["ja"])
            imported = (t for t in variants if not self._authored(t["provenance"]))
            target = next((t for t in imported if ja_identity(t["ja"]) == ident), None)
            if target is not None:
                if variant.get("ruling") and not target.get("ruling"):
                    target["ruling"] = variant["ruling"]
                self.carried_rulings += 1
                return True
        return False

    def carry_english(self, baselines: dict[tuple[Any, str], dict[str, Any]]) -> None:
        """Put each line's prior `english` baseline ({hash, src}: the English that (id, field) was last
        checked against) back on the rebuilt line, keyed by (id, field), never by text. `check` re-judges the
        Japanese on every run; the baseline is what lets it derive `stale` (ADR-003). Run after `carry`, so a
        line a carried decision recreated gets its baseline too, and after the lineage merge, so a line only a
        lineage source produces does. A baseline whose (id, field) none of the given inputs produce is counted
        and dropped with its line; a rebuilt line with no prior baseline keeps `english: null`."""
        for k, english in baselines.items():
            line = self.lines.get(k)
            if line is None:
                self.english_not_produced += 1
                continue
            line["english"] = copy.deepcopy(english)
            self.carried_english += 1

    @staticmethod
    def _authored(prov: dict[str, Any]) -> bool:
        """Text no importer produced: a correction or a machine draft keeps its own variant."""
        return decisions.is_correction(prov) or decisions.is_machine(prov)

    @staticmethod
    def _append_origin(prov: dict[str, Any], origin: str) -> None:
        origins = prov.setdefault("origins", [])
        if origin not in origins:  # rerunning one source alone must not double its origins
            origins.append(origin)


    def _adopt_credit(self, existing: dict[str, Any], incoming: dict[str, Any]) -> None:
        """Same text, better attribution: a named translator on the incoming copy replaces the community
        label on the kept line (source and class stay; `origins` shows where the credit came from)."""
        old = str(existing.get("translator", ""))
        new = str(incoming.get("translator", ""))
        if old in ANONYMOUS_TRANSLATORS and new and new not in ANONYMOUS_TRANSLATORS:
            existing["translator"] = new
            self.credited += 1


def _parse_relabel(pairs: Sequence[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    for kv in pairs:
        if "=" not in kv:
            raise SystemExit(f"--relabel-translator expects OLD=NEW, got {kv!r}")
        old, new = kv.split("=", 1)
        out[old] = new
    return out


def import_quests(
    text: str,
    source: str,
    date: str,
    relabel: dict[str, str] | None = None,
) -> Collector:
    """The Classic plugin's quest table. `relabel` maps a Translator tag to an honest one (the
    "CraftJapanizer" tag is WoWJapanizer's label for a bulk wiki import, so it becomes `questjapanizer-wiki`,
    ADR-011; the completeness rule then rejects its cut descriptions while its complete titles /
    objectives / completions stay)."""
    name, table = parse_assignment(text)
    if name != "CQJT_Quests_QuestData":
        raise ValueError(f"unexpected table {name!r} (want CQJT_Quests_QuestData)")
    col = Collector()
    relabel = relabel or {}
    for n, (key, val) in enumerate(table.items, 1):
        if key is None or not isinstance(val, Table):
            raise ValueError(f'quest entry #{n}: expected ["id"] = {{...}}')
        id_ = as_int_id(key)
        translator = (val.get("Translator") or "").strip() or "unknown"
        if translator in relabel:
            translator = relabel[translator]
            col.relabelled += 1
        prov = provenance("human", source, date, translator=translator)
        for lua_field, field in QUEST_FIELDS.items():
            ja = val.get(lua_field)
            if ja is None:
                continue
            col.add(id_, field, prepare_ja(field, ja), prov, f"{source}#{n}")
    return col


QJP_FIELDS = {
    "Title": "title",
    "Objectives": "objectives",
    "Description": "description",
    "Completion": "completion",
}
QJP_TABLE = "QuestJapanizer_QuestData"
QJP_VERSION = "0.5.8"
CJQ_VERSION = "2012031300"
CJQ_TABLE = "CraftJapanizer_Quest.Data"
# positional slots of a CraftJapanizer_Quest row; slot 5 is the reward text and is skipped
CJQ_SLOTS = ("title", "objectives", "description", "progress", None, "completion")


def import_questjapanizer(text: str, source: str, date: str) -> Collector:
    """QuestJapanizer 0.5.8 `QuestData.lua`: only rows flagged `TranslationStat = "wiki"` (human); `auto`
    rows are Livedoor machine translation and never enter data/. A trailing `翻訳:<name>` credit on the
    description becomes the translator; uncredited rows are attributed to the wiki community."""
    name, table = parse_assignment(text)
    if name != QJP_TABLE:
        raise ValueError(f"unexpected table {name!r} (want {QJP_TABLE})")
    col = Collector()
    for n, (key, val) in enumerate(table.items, 1):
        if key is None or not isinstance(val, Table):
            raise ValueError(f'questjapanizer entry #{n}: expected ["id"] = {{...}}')
        if (val.get("TranslationStat") or "") != "wiki":
            col.dropped += 1
            continue
        id_ = as_int_id(key)
        values: dict[str, str] = {}
        credits: dict[str, str] = {}
        for lua_field, field in QJP_FIELDS.items():
            raw = val.get(lua_field)
            if raw is None:
                continue
            ja = prepare_ja(field, raw)
            if field != "title":
                ja, credit = strip_credit(ja)
                if credit:
                    credits[field] = credit
                if "翻訳" in ja:
                    col.credit_tails += 1
            values[field] = ja
        # the Description credit names the row's translator; a credit on another field is the fallback
        translator = credits.get("description") or next(iter(credits.values()), "questjapanizer-wiki")
        prov = provenance("human", source, date, translator=translator)
        for field, ja in values.items():
            col.add(id_, field, ja, prov, f"{source}#{n}")
    return col


def import_craftjapanizer_quest(text: str, source: str, date: str) -> Collector:
    """CraftJapanizer_Quest 2012 `CraftJapanizer_QuestData.lua`: positional rows
    {title, objectives, description, progress, reward, completion, translator, status}. Only rows with a
    named translator AND status "1" are human work; unnamed rows (status 0 = excite MT, status 1 =
    unattributed) never enter data/."""
    name, table = parse_assignment(text)
    if name != CJQ_TABLE:
        raise ValueError(f"unexpected table {name!r} (want {CJQ_TABLE})")
    col = Collector()
    for n, (key, val) in enumerate(table.items, 1):
        if key is None or not isinstance(val, Table):
            raise ValueError(f'craftjapanizer entry #{n}: expected ["id"] = {{...}}')
        pos = val.positional()
        if len(pos) < 8:
            raise ValueError(f"craftjapanizer entry #{n}: expected 8 positional fields, got {len(pos)}")
        translator, status = (pos[6] or "").strip(), str(pos[7]).strip()
        if not translator or status != "1":
            col.dropped += 1
            continue
        id_ = as_int_id(key)
        prov = provenance("human", source, date, translator=translator)
        for slot, field in enumerate(CJQ_SLOTS):
            if field is None:
                continue
            ja = pos[slot]
            if not isinstance(ja, str):
                continue
            col.add(id_, field, prepare_ja(field, ja), prov, f"{source}#{n}")
    return col


def import_items(text: str, source: str, date: str) -> Collector:
    name, table = parse_assignment(text)
    if name != "ItemData":
        raise ValueError(f"unexpected table {name!r} (want ItemData)")
    col = Collector()
    prov = provenance("human", source, date, translator="WoWJapanizer")
    for n, (key, val) in enumerate(table.items, 1):
        if key is None or not isinstance(val, Table):
            raise ValueError(f'item entry #{n}: expected ["id"] = {{...}}')
        pos = val.positional()
        ja = _substitute_values(pos[0], pos[1] if len(pos) > 1 and isinstance(pos[1], Table) else None)
        col.add(as_int_id(key), "description", ja, prov, f"{source}#{n}")
    return col


def import_spells(text: str, source: str, date: str) -> Collector:
    name, table = parse_assignment(text)
    if name != "SpellData":
        raise ValueError(f"unexpected table {name!r} (want SpellData)")
    col = Collector()
    prov = provenance("human", source, date, translator="WoWJapanizer")
    for n, (key, val) in enumerate(table.items, 1):
        if key is None or not isinstance(val, Table):
            raise ValueError(f'spell entry #{n}: expected ["id"] = {{...}}')
        pos = val.positional()
        ja = _substitute_values(pos[0], pos[1] if len(pos) > 1 and isinstance(pos[1], Table) else None)
        short = pos[2] if len(pos) > 2 and isinstance(pos[2], str) and pos[2].strip() else None
        col.add(
            as_int_id(key),
            "description",
            ja,
            prov,
            f"{source}#{n}",
            extra={"short": short} if short else None,
        )
    return col


def _lineage_args(a: argparse.Namespace) -> list[tuple[str, Any, str]]:
    """The lineage files `predecessor` merges in its pass, as (path, importer, source). Refused before
    anything is read or written: an empty path, or a version flag without its file (once silently ignored)."""
    out = []
    for flag, path, version_flag, version, default, importer, name in (
        ("--questjapanizer", a.questjapanizer, "--qjp-version", a.qjp_version, QJP_VERSION,
         import_questjapanizer, "qjp"),
        ("--craftjapanizer-quest", a.craftjapanizer_quest, "--cjq-version", a.cjq_version, CJQ_VERSION,
         import_craftjapanizer_quest, "cjq"),
    ):
        if path is None:
            if version is not None:
                raise ValueError(f"{version_flag} given without {flag}")
            continue
        if not path.strip():
            raise ValueError(f"{flag} needs a file path")
        out.append((path, importer, f"{name}@{version or default}"))
    return out


def run_predecessor(a: argparse.Namespace) -> int:
    lineage = _lineage_args(a)
    root = data_root()
    quest_repo, tooltip_repo = Path(a.quest_repo), Path(a.tooltip_repo)
    cq = f"cqjt@{a.commit_quest or git_head(quest_repo)}"
    ct = f"ctjt@{a.commit_tooltip or git_head(tooltip_repo)}"
    date = dt.date.fromisoformat(a.date).isoformat() if a.date else dt.date.today().isoformat()
    store = Store(root)
    # Human decisions and English baselines are read BEFORE the rebuild and carried into it (ADR-012);
    # imported text is rebuilt.
    existing = {type_: store.load(type_) for type_ in ("quest", "item", "spell")}
    carried = {type_: decisions.carried(lines) for type_, lines in existing.items()}
    baselines = {
        type_: {(ln["id"], ln["field"]): ln["english"] for ln in lines if ln.get("english")}
        for type_, lines in existing.items()
    }
    results = {
        "quest": import_quests(
            (quest_repo / "QuestLogData.lua").read_text(encoding="utf-8-sig"),
            cq,
            date,
            relabel=_parse_relabel(a.relabel_translator or ()),
        ),
        "item": import_items(
            (tooltip_repo / "Data/Item/ItemData.lua").read_text(encoding="utf-8-sig"), ct, date
        ),
        "spell": import_spells(
            (tooltip_repo / "Data/Spell/SpellData.lua").read_text(encoding="utf-8-sig"), ct, date
        ),
    }
    for type_, col in results.items():
        for id_, field, variant in carried[type_]:
            col.carry(id_, field, variant)
    # The lineage sources merge after the decision carry (the order `make import` ran as three commands), and
    # before the baseline carry, so an (id, field) only they produce exists when its baseline is put back.
    summaries = []
    for path, importer, source in lineage:
        col = importer(Path(path).read_text(encoding="utf-8-sig"), source, date)
        quests = results["quest"]
        before = len(quests.lines)
        merged = merge_lineage(quests.lines.values(), col)
        quests.lines = merged.lines
        summaries.append(_lineage_summary(source, col, before, merged))
    for col in results.values():  # a reject ruling on a line only a lineage source produces
        pending, col.orphans, col.orphaned_rejects = col.orphans, [], 0
        for id_, field, variant in pending:
            col.carry(id_, field, variant)
    for type_, col in results.items():
        col.carry_english(baselines[type_])
    for summary in summaries:
        print(summary)
    print(f"{'type':6} {'ids':>6} {'lines':>6} {'collapsed':>9} {'conflicts':>9} {'empty':>6}")
    for type_, col in results.items():
        store.save(type_, col.lines.values())
        ids = {id_ for id_, _ in col.lines}
        with_conflicts = {id_ for (id_, _), line in col.lines.items() if line["conflicts"]}
        print(
            f"{type_:6} {len(ids):6} {len(col.lines):6} {col.collapsed:9} "
            f"{len(with_conflicts):9} {col.empty:6}"
        )
    if a.relabel_translator:
        print(f"relabelled: {results['quest'].relabelled} quest entries ({', '.join(a.relabel_translator)})")
    print(
        "carried human decisions (corrections / ruled variants / redundant corrections): "
        + " · ".join(
            f"{t} {c.carried_corrections}/{c.carried_rulings}/{c.redundant_corrections}"
            for t, c in results.items()
        )
    )
    if any(c.carried_machine or c.redundant_machine for c in results.values()):
        print(
            "carried machine drafts (kept / redundant): "
            + " · ".join(f"{t} {c.carried_machine}/{c.redundant_machine}" for t, c in results.items())
        )
    skipped = [
        f"{t}: {c.orphaned_rejects} orphaned rejects"
        for t, c in results.items()
        if c.orphaned_rejects
    ]
    if skipped:
        print("not carried: " + " · ".join(skipped))
    print("carried english baselines: " + " · ".join(f"{t} {c.carried_english}" for t, c in results.items()))
    if any(c.english_not_produced for c in results.values()):
        print(
            "english baselines not produced by the inputs: "
            + " · ".join(f"{t} {c.english_not_produced}" for t, c in results.items())
        )
    return 0


def merge_lineage(existing: Iterable[dict[str, Any]], col: Collector) -> Collector:
    """A collector seeded with `existing` quest lines, with every variant and origin `col` produced added
    (nothing overwritten; identical text collapses). Shared by `predecessor`'s one-pass rebuild and the
    standalone lineage subcommands."""
    merged = Collector()
    merged.seed(list(existing))
    for (id_, field), line in col.lines.items():
        # every variant and every origin the file produced: duplicates are recorded, never dropped
        for c in dedupe.variants(line):
            for origin in c.provenance["origins"]:
                merged.add(id_, field, c.ja, c.provenance, origin)
    return merged


def _lineage_summary(source: str, col: Collector, before: int, merged: Collector) -> str:
    return (
        f"{source}: {len(col.lines)} lines from {len({i for i, _ in col.lines})} ids imported; "
        f"{col.dropped} rows skipped (not human); store {before} → {len(merged.lines)} lines "
        f"(+{len(merged.lines) - before} new, {merged.collapsed} identical, {merged.conflicts} new variants, "
        f"{merged.credited} credited); {col.credit_tails} values still carry 翻訳"
    )


def _run_lineage(a: argparse.Namespace, importer, source: str) -> int:
    """Merge one lineage source into the existing quest store (seeded collector: nothing overwritten)."""
    root = data_root()
    date = dt.date.fromisoformat(a.date).isoformat() if a.date else dt.date.today().isoformat()
    store = Store(root)
    existing = store.load("quest")
    col = importer(Path(a.file).read_text(encoding="utf-8-sig"), source, date)
    merged = merge_lineage(existing, col)
    store.save("quest", merged.lines.values())
    print(_lineage_summary(source, col, len(existing), merged))
    return 0


def run_questjapanizer(a: argparse.Namespace) -> int:
    return _run_lineage(a, import_questjapanizer, f"qjp@{a.version}")


def run_craftjapanizer_quest(a: argparse.Namespace) -> int:
    return _run_lineage(a, import_craftjapanizer_quest, f"cjq@{a.version}")
