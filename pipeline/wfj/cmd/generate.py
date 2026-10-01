"""wfj generate [--addon DIR]: data/ → addon Data/*.lua (quest / item / spell / objective / area /
gossip / book / ui shards) + Meta.lua + Vectors.lua + the TOC's generated block.

Deterministic and idempotent: `plan()` computes every artifact as text; `apply()` writes only what changed,
deletes shards whose id range emptied, and rewrites the TOC block. `wfj validate` diffs `plan()` against disk.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from wfj.core import align, glosses, numbered, readings, tooltip_text
from wfj.core.align import load_allowlist
from wfj.core.english_text import model_english
from wfj.core.hashing import key as hash_key
from wfj.core.model import SCHEMA, validate_line
from wfj.core.normalize import female_variant, mask_values, normalize_for, normalize_v1
from wfj.emit import lua_writer, schema
from wfj.io.jsonl_store import Store
from wfj.paths import allowlist_path, data_root

TOC_NAME = "WoWForeverJapanese.toc"
VECTORS_HEAD = "WFJ.Data.vectors ="


def _pins_version(line: dict[str, Any]) -> bool:
    """A shipped line whose `english.src` names the source version the store holds now. A `stale` line keeps
    the hash and src it was checked against (sticky, ADR-003), so its version is history: after a source bump
    (`WDB_BUILD`, `VMANGOS_SHA`) it would otherwise make every harvest with a changed line fail the
    one-version rule."""
    return lua_writer.shipped(line) and bool(line.get("english")) and line.get("status") != "stale"

def default_addon_dir(root: Path) -> Path:
    return root.parent / "addon" / "WoWForeverJapanese"


def vectors_rows(root: Path) -> list[dict]:
    path = root.parent / "vectors" / "hash_vectors.jsonl"
    with path.open(encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def _female_key(ln: dict[str, Any]) -> str | None:
    variant = female_variant(str(ln.get("en") or ""))
    if variant is None or not ln.get("hash"):
        return None
    fkey = hash_key(normalize_v1(variant))
    return fkey if fkey != ln["hash"] else None


def female_index(english_lines: list[dict[str, Any]]) -> tuple[dict[str, str], list[str]]:
    """Keyed types: English hash → the key of its female variant, for every English line with a
    `$G` code whose female text normalizes differently. A hash whose texts give different female keys is
    left out and returned as ambiguous (reported, never guessed). → (index, sorted ambiguous)"""
    found: dict[str, set[str]] = {}
    for ln in english_lines:
        fkey = _female_key(ln)
        if fkey:
            found.setdefault(str(ln["hash"]), set()).add(fkey)
    index = {h: next(iter(ks)) for h, ks in found.items() if len(ks) == 1}
    return index, sorted(h for h, ks in found.items() if len(ks) > 1)


def masked_fields(english_lines: list[dict[str, Any]]) -> dict[tuple[int, str], tuple[str, str, str | None]]:
    """Quest: (id, field) → (English hash, masked key, masked female key or None),
    `normalize.mask_values` over the English. A field whose shipped Japanese is filled from live values ships
    the masked keys as its h1 / h1f, but only while its `english.hash` IS this English: a stale line keeps
    the hash it was checked against (ADR-003), so the live check still marks it and the Collector still
    records the new English."""
    out: dict[tuple[int, str], tuple[str, str, str | None]] = {}
    for ln in english_lines:
        en = str(ln.get("en") or "")
        variant = female_variant(en)
        fkey = hash_key(mask_values(normalize_v1(variant))) if variant is not None else None
        key = hash_key(mask_values(normalize_v1(en)))
        out[(int(ln["id"]), str(ln["field"]))] = (str(ln.get("hash") or ""), key, fkey)
    return out


def female_fields(english_lines: list[dict[str, Any]]) -> dict[tuple[int, str], tuple[str, str]]:
    """Quest: (id, field) → (English hash, female-variant key). Per field, not per hash: a
    literal line sharing a gendered line's hash (quests 8897 / 8898) never inherits its variant."""
    out: dict[tuple[int, str], tuple[str, str]] = {}
    for ln in english_lines:
        fkey = _female_key(ln)
        if fkey:
            out[(int(ln["id"]), str(ln["field"]))] = (str(ln["hash"]), fkey)
    return out


def gender_report_lines(report: dict[str, Any]) -> list[str]:
    """The generate output for gender aliases (ADR-024). Nothing is dropped silently: every female key the
    stated rule dropped, and every English hash left without a variant because its texts
    disagree, is named."""
    added = sum(report["aliases"].values())
    dropped = [f"{t}:{k}" for t, keys in report["dropped"].items() for k in keys]
    ambiguous = [f"{t}:{h}" for t, hashes in report["ambiguous"].items() for h in hashes]
    lines = [f"generate: gender aliases: {added} added · {len(dropped)} dropped · {len(ambiguous)} ambiguous"]
    lines += [f"  dropped alias {item}" for item in dropped]
    lines += [f"  ambiguous female variant {item}" for item in ambiguous]
    return lines


def branch_variants(
    type_: str, lines: list[dict[str, Any]], english_store: Store
) -> tuple[dict[tuple[int, str], list[tuple[str, str]]], dict[tuple[int, str], str]]:
    """→ (shipped, refused), ADR-043. `shipped`: (id, field) → [(variant Japanese, shape)…] for every shipped
    item / spell line whose Japanese keeps `$?` conditionals: its English (inclusions spliced in) split into
    branch combinations, the Japanese renumbered per combination (`align.ja_variants`), identical
    (text, shape) pairs shipped once. `refused`: (id, field) → why a branch line ships nothing (the addon
    shows the English with the missing marker). A refusal is never a build failure, since `check` keeps a
    line whose English moved on shipping as stale:
    - `stale`: its Japanese was numbered against English that has changed since, so a `$N` could point at
      another value; it waits for a redraft;
    - the English no longer splits (`missing_included_spell:…`, `too_many_variants`, …) or the Japanese no
      longer fits it (`branch_skeleton`, `branch_index:…`);
    - `empty_variant` (a hand edit: an empty Japanese would pass the gate on every line);
    - `branches_indistinguishable`: no variant could ever be the only one to pass, the tooltip's name line
      counted as the addon counts it; or `branches_unsafe`: a shadowed variant carries an icon or a
      duration its shadower lacks (`align.unsafe_shadow`)."""
    todo = [ln for ln in lines if lua_writer.shipped(ln) and align.has_branches(str(ln.get("ja") or ""))]
    if not todo:
        return {}, {}
    english = english_store.load(type_)
    en_by = {(ln["id"], ln["field"]): ln["en"] for ln in english}
    spells = {(ln["id"], ln["field"]): ln["en"] for ln in english_store.load("spell")}
    allowlist = load_allowlist(allowlist_path(english_store.root.parent).read_text(encoding="utf-8"))
    shipped: dict[tuple[int, str], list[tuple[str, str]]] = {}
    refused: dict[tuple[int, str], str] = {}
    for ln in todo:
        key = (ln["id"], ln["field"])
        reason = _branch_refusal(ln, en_by, spells, allowlist)
        if isinstance(reason, str):
            refused[key] = reason
        else:
            shipped[key] = reason
    return shipped, refused


def _branch_english(
    ln: dict[str, Any], en_by: dict[tuple[int, str], str], spells: dict[tuple[int, str], str]
) -> tuple[str | None, str]:
    """→ (the line's English with its spell inclusions filled in, "") or (None, why it has none)."""
    if ln["status"] == "stale":
        return None, "stale"
    raw = en_by.get((ln["id"], ln["field"]))
    if raw is None:
        return None, "no_english"
    if "$@" in raw:
        x = align.expand_inclusions(raw, spells)
        if x.text is None:
            return None, x.reason or "unsupported_code"
        raw = x.text
    return raw, ""


def _branch_refusal(
    ln: dict[str, Any],
    en_by: dict[tuple[int, str], str],
    spells: dict[tuple[int, str], str],
    allowlist: set[str],
) -> str | list[tuple[str, str]]:
    """One branch line → its (variant, shape) list, or the reason it ships nothing (`branch_variants`)."""
    raw, why = _branch_english(ln, en_by, spells)
    if raw is None:
        return why
    b = align.branching(model_english(raw, player_tokens=False))
    if b.reason:
        return b.reason
    texts, bad = align.ja_variants(ln["ja"], b)
    if texts is None:
        return "; ".join(bad)
    if any(not t.strip() for t in texts):
        return "empty_variant"
    shapes = [v.shape for v in b.variants]
    name = en_by.get((ln["id"], "name"), "")
    pairs = align.indistinguishable(texts, [f"{v.en}\n{name}" for v in b.variants], shapes, allowlist)
    if align.never_shown(pairs, len(texts)):
        return "branches_indistinguishable"
    if align.unsafe_shadow(pairs, texts):
        return "branches_unsafe"
    return list(dict.fromkeys(zip(texts, shapes, strict=True)))


def plan(store: Store, vectors: list[dict], report: dict[str, Any] | None = None) -> dict[str, str]:
    """{relpath under the addon dir: text} for every generated artifact (shards, Meta, Vectors).
    `report`, when given, receives `aliases` {type: added}, `dropped` {type: [female keys]} and `ambiguous`
    {type: [English hashes]}.

    Raises ValueError on a store that must not become Lua: invalid lines, a shipped line without its English
    hash, a duplicate (id, field), or a single-client English source pinned at several versions.
    """
    _check_store(store)
    out: dict[str, str] = {}
    counts: dict[str, int] = {}
    english: dict[str, set[str]] = {}
    english_store = Store(store.root, english=True)
    if report is not None:
        report.update(aliases={}, dropped={}, ambiguous={})
    _plan_id_types(store, english_store, out, counts, english, report)
    _plan_keyed_types(store, english_store, out, counts, english, report)
    _plan_ui(store, english_store, out, counts, english)
    _plan_readings(store, out, counts)
    # One version per source is still the rule, and a mixed store is still a data error, except for the
    # sources two clients serve (`schema.MULTI_VERSION_SOURCES`), where a union import keeps both builds'
    # lines on purpose (ADR-020). Meta records every version of those, sorted; the per-line
    # `english.src` is exact in all cases.
    mixed = {
        n: sorted(v)
        for n, v in english.items()
        if len(v) > 1 and n not in schema.MULTI_VERSION_SOURCES
    }
    if mixed:
        raise ValueError(
            f"english sources pinned at several versions: {mixed}; re-run `make import-english`"
        )
    out["Data/Meta.lua"] = lua_writer.meta_text(
        SCHEMA, {n: sorted(v) for n, v in english.items()}, counts
    )
    head, _, body = lua_writer.vectors_text(vectors, head=VECTORS_HEAD).partition("\n")
    out["Data/Vectors.lua"] = head + "\nlocal _, WFJ = ...\n" + body
    return out


def _check_store(store: Store) -> None:
    """Raise ValueError when any generated type holds an invalid line."""
    for type_ in schema.GENERATED_TYPES:
        bad = [
            f"{type_} {ln.get('id')}/{ln.get('field')}: {p}"
            for ln in store.load(type_)
            for p in validate_line(type_, ln)
        ]
        if bad:  # a hand-edited store never becomes Lua; `wfj validate` rule 1 lists every problem
            raise ValueError("invalid data/ lines (first shown): " + "; ".join(bad[:5]))


def _note_versions(english: dict[str, set[str]], lines: list[dict[str, Any]]) -> None:
    """Record the English source version every line pins, so Meta can list them and mixes are caught."""
    for ln in lines:
        if _pins_version(ln):
            name, _, ver = ln["english"]["src"].partition("@")
            english.setdefault(name, set()).add(ver)


def _plan_id_types(
    store: Store,
    english_store: Store,
    out: dict[str, str],
    counts: dict[str, int],
    english: dict[str, set[str]],
    report: dict[str, Any] | None,
) -> None:
    """The shards of every type keyed by game ID (quest, item, spell, …)."""
    for type_ in schema.TYPES:
        lines = store.load(type_)
        if type_ in tooltip_text.TYPES:
            # the translator's manual line breaks are joined in what ships; data/ keeps the text as written
            en_by = {(ln["id"], ln["field"]): ln["en"] for ln in english_store.load(type_)}
            lines = tooltip_text.joined(lines, en_by)
        quest = "female" in schema.SLOTS[type_]
        female = female_fields(english_store.load(type_)) if quest else None
        masked = masked_fields(english_store.load(type_)) if quest else None
        branches, refused = (
            branch_variants(type_, lines, english_store) if type_ in ("item", "spell") else ({}, {})
        )
        if report is not None and refused:
            report.setdefault("branch_refused", {})[type_] = refused
        # a refused branch line ships nothing: the addon shows the English with the missing marker
        rows = lua_writer.rows(
            type_, [ln for ln in lines if (ln["id"], ln["field"]) not in refused], female, masked, branches
        )
        counts[type_] = len(rows)
        _note_versions(english, lines)
        by_shard: dict[int, dict[int, list[str]]] = {}
        for id_, slots in rows.items():
            by_shard.setdefault(schema.shard_of(id_), {})[id_] = slots
        for nnnn, shard_rows in sorted(by_shard.items()):
            out[schema.shard_relpath(type_, nnnn)] = lua_writer.shard_text(type_, nnnn, shard_rows)


def _plan_keyed_types(
    store: Store,
    english_store: Store,
    out: dict[str, str],
    counts: dict[str, int],
    english: dict[str, set[str]],
    report: dict[str, Any] | None,
) -> None:
    """The shards of every type keyed by an English hash (gossip, …), with their gender aliases."""
    for type_ in schema.KEYED_TYPES:
        lines = store.load(type_)
        k_rows = lua_writer.keyed_rows(type_, lines)
        counts[type_] = len(k_rows)  # translated lines; the gender aliases below are extra keys, not lines
        index, ambiguous = female_index(english_store.load(type_))
        aliases, dropped = lua_writer.gender_aliases(k_rows, index)
        if report is not None:
            report["aliases"][type_], report["dropped"][type_] = len(aliases), dropped
            report["ambiguous"][type_] = ambiguous
        k_rows = {**k_rows, **aliases}
        if type_ != "gossip":  # gossip's english.src names the key primitive, not a source version
            _note_versions(english, lines)
        by_nn: dict[str, dict[str, list[str]]] = {}
        for key, slots in k_rows.items():
            by_nn.setdefault(key[:2], {})[key] = slots
        for nn, shard_rows in sorted(by_nn.items()):
            out[schema.shard_relpath(type_, nn)] = lua_writer.keyed_text(type_, nn, shard_rows)


def _plan_ui(
    store: Store,
    english_store: Store,
    out: dict[str, str],
    counts: dict[str, int],
    english: dict[str, set[str]],
) -> None:
    """The UI dictionary's shards."""
    ui_lines = store.load("ui")
    # a numbered row (ADR-042) ships the hash of its English skeleton and its Japanese with each
    # world-state token as the place of its live number (core/numbered)
    # (a row whose tokens the current English no longer holds, or with no English, never ships: validate
    # names it)
    ui_english = {ln["id"]: ln["en"] for ln in english_store.load("ui")}
    kept = []
    for ln in ui_lines:
        if numbered.is_numbered(ln["id"]):
            en = ui_english.get(ln["id"])
            if en is None or not ln.get("english"):
                continue
            try:
                ln["ja"] = numbered.fill_slots(en, ln["ja"])
            except ValueError:
                continue
            ln["english"] = {**ln["english"], "hash": hash_key(normalize_for("ui", numbered.skeleton(en)))}
        kept.append(ln)
    u_rows = lua_writer.ui_rows(kept)
    counts["ui"] = len(u_rows)
    _note_versions(english, ui_lines)
    by_c: dict[str, dict[str, list[str]]] = {}
    for key, slots in u_rows.items():
        by_c.setdefault(lua_writer.ui_shard(key), {})[key] = slots
    for c, shard_rows in sorted(by_c.items()):
        out[schema.shard_relpath("ui", c)] = lua_writer.ui_text(c, shard_rows)


def _plan_readings(store: Store, out: dict[str, str], counts: dict[str, int]) -> None:
    """The readings shards and the meanings table they point into."""
    # readings (ADR-036). Only current ones ship: a stale reading (its Japanese changed) is left
    # out and reported by `validate`; a malformed one stops generate like any invalid line.
    counts["reading"] = 0
    current: dict[str, list[dict[str, Any]]] = {}
    for type_ in readings.TYPES:
        japanese = readings.shipped_japanese(store.load(type_))
        result = readings.check(type_, reading_store_of(store).load(type_), japanese)
        if result["problems"]:
            first = "; ".join(result["problems"][:5])
            raise ValueError(f"invalid data/reading/ records (first shown): {first}")
        current[type_] = readings.addon_keyed(type_, result["current"], store.load(type_))
    # the word popup's meanings (ADR-039), each distinct one stored once and numbered; a reading row
    # points at its word's number.
    meanings = glosses.table(r for recs in current.values() for r in recs)
    for type_, recs_of_type in current.items():
        by_rs: dict[int | str, list[dict[str, Any]]] = {}
        for rec in recs_of_type:
            if type_ == "ui":  # the UI dictionary's shards (the key's first character)
                shard: int | str = lua_writer.ui_shard(rec["id"])
            else:
                shard = rec["id"][:2] if isinstance(rec["id"], str) else schema.shard_of(rec["id"])
            by_rs.setdefault(shard, []).append(rec)
        for shard, recs in sorted(by_rs.items(), key=lambda kv: str(kv[0])):
            out[schema.reading_relpath(type_, shard)] = lua_writer.reading_text(type_, shard, recs, meanings)
        counts["reading"] += len(recs_of_type)  # lines with readings
    by_gs: dict[int, dict[int, glosses.Meaning]] = {}
    for m, n in meanings.items():
        by_gs.setdefault(glosses.shard_of(n), {})[n] = m
    for gshard, rows in sorted(by_gs.items()):
        out[schema.gloss_relpath(gshard)] = lua_writer.gloss_text(gshard, rows)
    counts["gloss"] = len(meanings)


def reading_store_of(store: Store) -> Store:
    """The readings store beside a translation store: `<data>/reading/`."""
    return Store(store.root / "reading")


def toc_files(planned: dict[str, str]) -> list[str]:
    """Load order inside the generated block: Meta, Vectors, then shards by type then range."""
    shards = [p for p in planned if p not in ("Data/Meta.lua", "Data/Vectors.lua")]
    order = {t: i for i, t in enumerate(schema.TOC_ORDER)}

    def type_of(rel: str) -> str:
        return next(t for t, pre in schema.FILE_PREFIX.items() if rel.startswith(f"Data/{pre}/"))

    shards.sort(key=lambda p: (order[type_of(p)], p))
    return ["Data/Meta.lua", "Data/Vectors.lua", *shards]


def toc_with_block(toc_text: str, files: list[str]) -> str:
    """The TOC with its generated block replaced. Exactly one begin and one end marker, in that order."""
    lines = toc_text.splitlines()
    begins = [i for i, ln in enumerate(lines) if ln.strip() == schema.TOC_BEGIN]
    ends = [i for i, ln in enumerate(lines) if ln.strip() == schema.TOC_END]
    if len(begins) != 1 or len(ends) != 1 or ends[0] < begins[0]:
        raise ValueError(
            f"{TOC_NAME} needs exactly one generated block: {len(begins)} begin / {len(ends)} end marker(s) "
            f"({schema.TOC_BEGIN!r} … {schema.TOC_END!r})"
        )
    new = lines[: begins[0]] + lua_writer.toc_block(files) + lines[ends[0] + 1 :]
    return "\n".join(new) + ("\n" if toc_text.endswith("\n") else "")


def generated_on_disk(addon_dir: Path) -> set[str]:
    """The files under Data/ that generate owns: `<Type>/<Type>_*.lua`, Meta.lua, Vectors.lua. Nothing else
    under Data/ is ever deleted or diffed (a README or a stray note is left alone)."""
    found: set[str] = set()
    data = addon_dir / "Data"
    for name in ("Meta.lua", "Vectors.lua"):
        if (data / name).is_file():
            found.add(f"Data/{name}")
    for prefix in schema.FILE_PREFIX.values():
        for p in (data / prefix).glob(f"{prefix}_*.lua"):
            if p.is_file():
                found.add(p.relative_to(addon_dir).as_posix())
    return found


def same_bytes(path: Path, text: str) -> bool:
    return path.is_file() and path.read_bytes() == text.encode("utf-8")


def apply(planned: dict[str, str], addon_dir: Path) -> dict[str, list[str]]:
    """Writes only what changed. The TOC is read and its new text computed first, so a missing or duplicated
    block aborts before any shard is touched."""
    written, unchanged, deleted = [], [], []
    toc_path = addon_dir / TOC_NAME
    old = toc_path.read_bytes().decode("utf-8")
    new = toc_with_block(old, toc_files(planned))
    for rel, text in sorted(planned.items()):
        path = addon_dir / rel
        if path.is_dir():
            raise ValueError(f"{rel} exists as a directory; remove it")
        path.parent.mkdir(parents=True, exist_ok=True)
        if same_bytes(path, text):
            unchanged.append(rel)
        else:
            path.write_bytes(text.encode("utf-8"))
            written.append(rel)
    for rel in sorted(generated_on_disk(addon_dir) - set(planned)):
        (addon_dir / rel).unlink()
        deleted.append(rel)
    if new != old:
        toc_path.write_bytes(new.encode("utf-8"))
        written.append(TOC_NAME)
    else:
        unchanged.append(TOC_NAME)
    return {"written": written, "unchanged": unchanged, "deleted": deleted}


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj generate")
    p.add_argument(
        "--addon", type=Path, default=None, help="addon dir (default: <repo>/addon/WoWForeverJapanese)"
    )
    a = p.parse_args(list(argv))
    root = data_root()
    addon_dir = a.addon or default_addon_dir(root)
    try:
        report: dict[str, Any] = {}
        planned = plan(Store(root), vectors_rows(root), report)
        result = apply(planned, addon_dir)
    except ValueError as exc:
        raise SystemExit(f"generate: {exc}") from exc
    meta = planned["Data/Meta.lua"]
    counts = meta[meta.index("counts = {") : meta.index("},", meta.index("counts = {")) + 1]
    w, u, d = (len(result[k]) for k in ("written", "unchanged", "deleted"))
    print(f"generate: {len(planned)} artifacts; {counts}; written {w}, unchanged {u}, deleted {d}")
    for line in gender_report_lines(report):
        print(line)
    refused = [
        f"{t} {i}/{f}: {why}"
        for t, r in report.get("branch_refused", {}).items()
        for (i, f), why in r.items()
    ]
    if refused:  # branch lines shipped as English, and why
        print(f"generate: {len(refused)} branch lines ship English: " + "; ".join(refused[:20])
              + (f" … {len(refused) - 20} more" if len(refused) > 20 else ""))
    for rel in result["deleted"]:
        print(f"  deleted {rel}", file=sys.stderr)
    return 0
