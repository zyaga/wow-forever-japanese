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

from wfj.core import align, english_cards, glosses, numbered, pronunciation, readings, tooltip_text
from wfj.core.align import load_allowlist
from wfj.core.english_text import model_english
from wfj.core.hashing import key as hash_key
from wfj.core.model import SCHEMA, validate_line
from wfj.core.normalize import female_variant, mask_values, normalize_for, normalize_v1
from wfj.emit import lua_writer, schema
from wfj.io.jsonl_store import Store
from wfj.io.names_store import load_lines as load_name_lines
from wfj.paths import allowlist_path, data_root

TOC_NAME = "WoWForeverJapanese.toc"
# the generated files that are not shards, in load order; the last ships only when the store has its data
FIXED = ("Data/Meta.lua", "Data/Vectors.lua", "Data/ErrorSounds.lua")
ERROR_SOUNDS = Path("voice") / "error-sounds.jsonl"
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
    if "quest_keyed" in report:
        n = report["quest_keyed"]
        lines.append(f"generate: repeated quests' progress / turn-in text keyed by its English: {n}")
    return lines


def branch_variants(
    type_: str,
    lines: list[dict[str, Any]],
    english_store: Store,
    en_by: dict[tuple[int, str], str] | None = None,
) -> tuple[dict[tuple[int, str], list[tuple[str, ...]]], dict[tuple[int, str], str]]:
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
    if en_by is None:
        en_by = {(ln["id"], ln["field"]): ln["en"] for ln in english_store.load(type_)}
    spells = en_by if type_ == "spell" else {
        (ln["id"], ln["field"]): ln["en"] for ln in english_store.load("spell")
    }
    allowlist = load_allowlist(allowlist_path(english_store.root.parent).read_text(encoding="utf-8"))
    shipped: dict[tuple[int, str], list[tuple[str, ...]]] = {}
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


def _sections(b: align.Branching, texts: list[str]) -> str | dict[str, Any]:
    """A sectioned line's slot data (align, SECTIONED lines): the heading's Japanese and the key of its
    English, and per optional paragraph the byte length and key of the words it begins with, its Japanese
    (numbered to its own values) and its shape. The keys are hashes; no English ships.
    → data | the reason it ships nothing"""
    head_en, head_ja = b.variants[0].en, texts[0]
    # each paragraph's shape and numbering count its own values only, as the addon reads them; a heading
    # with a value (a literal number) would shift both
    if b.variants[0].shape != "0/0":
        return "sections_head_has_values"
    sections = []
    for v, ja in zip(b.variants[1:], texts[1:], strict=True):
        if not ja.startswith(head_ja):
            return "sections_head_mismatch"
        prefix = align.section_prefix(v.en[len(head_en):])
        body = ja[len(head_ja):].rstrip()
        if not body:
            return "empty_variant"
        sections.append({"n": len(prefix.encode("utf-8")), "key": hash_key(normalize_v1(prefix)), "ja": body,
                         "shape": v.shape})
    if len({s["key"] for s in sections}) != len(sections):
        return "sections_indistinguishable"
    # the addon takes the first section whose opening words fit, so no opening may begin another's
    openings = [align.section_prefix(v.en[len(head_en):]) for v in b.variants[1:]]
    if any(a != b_ and b_.startswith(a) for a in openings for b_ in openings):
        return "sections_indistinguishable"
    return {"head": head_ja.rstrip(), "hkey": hash_key(normalize_v1(head_en.strip())), "sections": sections}


def _branch_refusal(
    ln: dict[str, Any],
    en_by: dict[tuple[int, str], str],
    spells: dict[tuple[int, str], str],
    allowlist: set[str],
) -> str | list[tuple[str, ...]]:
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
    if b.sectioned:
        return _sections(b, texts)
    shapes = [v.shape for v in b.variants]
    name = en_by.get((ln["id"], "name"), "")
    pairs = align.indistinguishable(texts, [f"{v.en}\n{name}" for v in b.variants], shapes, allowlist)
    if align.never_shown(pairs, len(texts)):
        # wordings the gate cannot tell apart ship a key each (ADR-064): the addon takes the variant whose
        # key the live line's masked wording has. No key, or two alike: nothing ships.
        keys = align.variant_keys(b.variants)
        return "branches_indistinguishable" if keys is None else list(
            dict.fromkeys(zip(texts, shapes, keys, strict=True)))
    if align.unsafe_shadow(pairs, texts):
        return "branches_unsafe"
    return list(dict.fromkeys(zip(texts, shapes, strict=True)))


def plan(store: Store, vectors: list[dict], report: dict[str, Any] | None = None) -> dict[str, str]:
    """{relpath under the addon dir: text} for every generated artifact (shards, Meta, Vectors).
    `report`, when given, receives `aliases` {type: added}, `dropped` {type: [female keys]}, `ambiguous`
    {type: [English hashes]} and `meaning_numbers` (the numbers file's text, ADR-060).

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
    alias_of: dict[str, dict[str, str]] = {}
    quest_keyed = quest_text_aliases(store.load("quest"), english_store.load("quest"))
    _plan_keyed_types(store, english_store, out, counts, english, report, alias_of, quest_keyed)
    _plan_ui(store, english_store, out, counts, english)
    numbers: dict[str, str] | None = {} if report is not None else None
    _plan_readings(store, out, counts, alias_of, quest_keyed, numbers, english_store)
    if report is not None and numbers and numbers["text"]:  # nothing to number: the report is unchanged
        report["meaning_numbers"] = numbers["text"]
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
    sounds = store.root / ERROR_SOUNDS
    if sounds.is_file():
        rows = [json.loads(ln) for ln in sounds.read_text(encoding="utf-8").splitlines() if ln.strip()]
        _check_error_sounds(rows)
        out["Data/ErrorSounds.lua"] = lua_writer.error_sounds_text(rows)
    out.update(_plan_names(store.root))
    return out


def _check_error_sounds(rows: list[dict]) -> None:
    """Raise ValueError on a row that must not become Lua: a race that is not an id, a sex other than m or f,
    file ids that are not numbers, or a second row for the same race and sex (never resolved silently)."""
    seen: set[tuple[int, str]] = set()
    for n, r in enumerate(rows, 1):
        race, sex, files = r.get("race"), r.get("sex"), r.get("files")
        ok = (type(race) is int and sex in ("m", "f") and isinstance(files, list)
              and all(type(f) is int for f in files))
        if not ok:
            raise ValueError(f"{ERROR_SOUNDS} row {n}: needs an integer race, sex m or f, integer files")
        if (race, sex) in seen:
            raise ValueError(f"{ERROR_SOUNDS} row {n}: a second row for race {race} sex {sex}")
        seen.add((race, sex))


NAMES_DIR = "Data/Names"


def _plan_names(root: Path) -> dict[str, str]:
    """`Data/Names/Names_<nn>.lua` per `data/name` shard that holds a name with Japanese. They are left out of
    the TOC: nothing loads them until the names setting does (ADR-078)."""
    by_shard: dict[str, list[dict[str, Any]]] = {}
    for ln in load_name_lines(root):
        if ln["status"] == "trusted":
            by_shard.setdefault(ln["id"][:2], []).append(ln)
    return {
        f"{NAMES_DIR}/Names_{nn}.lua": lua_writer.names_text(nn, ls) for nn, ls in sorted(by_shard.items())
    }


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
        en_by = None
        if type_ in tooltip_text.TYPES:
            # a hand-written line's manual breaks are joined in what ships; data/ keeps the text as written
            en_by = {(ln["id"], ln["field"]): ln["en"] for ln in english_store.load(type_)}
            lines = tooltip_text.joined(lines, en_by)
        quest = "female" in schema.SLOTS[type_]
        female = female_fields(english_store.load(type_)) if quest else None
        masked = masked_fields(english_store.load(type_)) if quest else None
        branches, refused = (
            branch_variants(type_, lines, english_store, en_by) if type_ in ("item", "spell") else ({}, {})
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


QUEST_KEYED_FIELDS = ("progress", "completion")


def quest_text_aliases(
    quest_lines: list[dict[str, Any]], english_lines: list[dict[str, Any]]
) -> dict[str, tuple[int, str]]:
    """Forever repeats a quest under several ids (one per start area or profession) with the same text, and a
    copy often has no progress or turn-in English of its own. For a title several quests share, where a copy
    lacks the field's English, every trusted translation of that field among the copies also ships keyed by
    the hash of its English, so the copy finds it by the live text (ADR-054). Only an exact English match
    shows it. A text with a `$G` code ships under its female wording's key too: the key keeps the male
    branch, and a female character's live text is the other. The lowest quest id answers a key two copies
    hold. → {key: (quest id, field)}"""
    english: dict[int, dict[str, dict[str, Any]]] = {}
    for ln in english_lines:
        english.setdefault(ln["id"], {})[ln["field"]] = ln
    trusted = {
        (ln["id"], ln["field"]) for ln in quest_lines if ln["status"] == "trusted" and lua_writer.shipped(ln)
    }
    families: dict[str, list[int]] = {}
    for id_, fields in english.items():
        if "title" in fields:
            families.setdefault(fields["title"]["hash"], []).append(id_)
    out: dict[str, tuple[int, str]] = {}
    for ids in families.values():
        if len(ids) < 2:
            continue
        for field in QUEST_KEYED_FIELDS:
            if all(field in english[i] for i in ids):
                continue  # every copy has its own English: each is found by its own id
            for i in sorted(ids):
                if (i, field) in trusted and field in english[i]:
                    out.setdefault(english[i][field]["hash"], (i, field))
                    fkey = _female_key(english[i][field])
                    if fkey:
                        out.setdefault(fkey, (i, field))
    return out


def _plan_keyed_types(
    store: Store,
    english_store: Store,
    out: dict[str, str],
    counts: dict[str, int],
    english: dict[str, set[str]],
    report: dict[str, Any] | None,
    alias_of: dict[str, dict[str, str]] | None = None,
    quest_keyed: dict[str, tuple[int, str]] | None = None,
) -> None:
    """The shards of every type keyed by an English hash (gossip, …), with their gender aliases and the
    repeated quests' text (`quest_keyed`, from quest_text_aliases; entries not shipped are removed from it).
    `alias_of`, when given, receives {type: {alias key: the key it repeats}} for the readings."""
    for type_ in schema.KEYED_TYPES:
        lines = store.load(type_)
        k_rows = lua_writer.keyed_rows(type_, lines)
        counts[type_] = len(k_rows)  # translated lines; the gender aliases below are extra keys, not lines
        index, ambiguous = female_index(english_store.load(type_))
        aliases, dropped = lua_writer.gender_aliases(k_rows, index)
        if report is not None:
            report["aliases"][type_], report["dropped"][type_] = len(aliases), dropped
            report["ambiguous"][type_] = ambiguous
        if alias_of is not None:
            alias_of[type_] = {f: k for k, f in index.items() if f in aliases and k in k_rows}
        k_rows = {**k_rows, **aliases}
        if type_ == "gossip" and quest_keyed is not None:
            # a repeated quest's progress / turn-in text, keyed by its English (quest_text_aliases); a key the
            # gossip data already holds keeps its own row
            quest_rows = lua_writer.rows("quest", store.load("quest"))
            slot = {f: n for n, f in enumerate(schema.SLOTS["quest"]["fields"])}
            for key, (qid, field) in sorted(quest_keyed.items()):
                row = quest_rows.get(qid)
                if key in k_rows or row is None or row[slot[field]] == "nil":
                    quest_keyed.pop(key)
                    continue
                k_rows[key] = [row[slot[field]], lua_writer.lua_string(".")]
            if report is not None:
                report["quest_keyed"] = len(quest_keyed)
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


def _plan_readings(
    store: Store,
    out: dict[str, str],
    counts: dict[str, int],
    alias_of: dict[str, dict[str, str]] | None = None,
    quest_keyed: dict[str, tuple[int, str]] | None = None,
    numbers: dict[str, str] | None = None,
    english_store: Store | None = None,
) -> None:
    """The readings shards and the meanings table they point into, and, with `english_store`, the English
    word card rows beside them (each line's English words matched to its Japanese words).
    `numbers`, when given, receives `text`:
    the numbers file as it must be on disk. A gender alias key (the female variant of
    a line, repeated under its own English hash) gets its line's reading too: the addon finds a female
    character's line under the alias, and without the copy its words would have no reading."""
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
        if english_store is not None:
            # before the alias copies below, so a copy carries its line's row: an alias has none of its own
            current[type_] = _with_english(type_, current[type_], english_store.load(type_))
        aliases = (alias_of or {}).get(type_, {})
        if aliases:
            by_key = {rec["id"]: rec for rec in current[type_]}
            current[type_] = current[type_] + [
                by_key[key] | {"id": alias} for alias, key in sorted(aliases.items()) if key in by_key
            ]
    # a repeated quest's text shipped under its English key carries that quest line's reading
    if quest_keyed:
        by_line = {(rec["id"], rec["field"]): rec for rec in current.get("quest", [])}
        current["gossip"] = current.get("gossip", []) + [
            by_line[line] | {"id": key, "field": "text"}
            for key, line in sorted(quest_keyed.items())
            if line in by_line
        ]
    # the word popup's meanings (ADR-039), each distinct one stored once and numbered; a reading row
    # points at its word's number. The numbers come from the numbers file (ADR-060), so adding a meaning
    # changes only the files that use it; generate's `run` writes the file back when a meaning was added.
    known, problems = load_numbers(store)
    if problems:
        raise ValueError(f"{glosses.NUMBERS_FILE}: {'; '.join(problems[:5])}")
    meanings, every = glosses.number((r for recs in current.values() for r in recs), known)
    if numbers is not None:
        numbers["text"] = glosses.numbers_text(every)
    for type_, recs_of_type in current.items():
        for shard, recs in _by_shard(type_, recs_of_type):
            out[schema.reading_relpath(type_, shard)] = lua_writer.reading_text(type_, shard, recs, meanings)
        counts["reading"] += len(recs_of_type)  # lines with readings
    by_gs: dict[int, dict[int, glosses.Meaning]] = {}
    for m, n in meanings.items():
        by_gs.setdefault(glosses.shard_of(n), {})[n] = m
    for gshard, rows in sorted(by_gs.items()):
        out[schema.gloss_relpath(gshard)] = lua_writer.gloss_text(gshard, rows)
    counts["gloss"] = len(meanings)
    if english_store is not None:
        _plan_english(english_store.root, current, out, counts)


def _by_shard(type_: str, records: list[dict[str, Any]]) -> list[tuple[int | str, list[dict[str, Any]]]]:
    """A type's reading records by the shard they ship in: the UI dictionary's by the key's first character,
    a keyed type's by its key's first two, a numbered one's by id range."""
    by: dict[int | str, list[dict[str, Any]]] = {}
    for rec in records:
        if type_ == "ui":
            shard: int | str = lua_writer.ui_shard(rec["id"])
        else:
            shard = rec["id"][:2] if isinstance(rec["id"], str) else schema.shard_of(rec["id"])
        by.setdefault(shard, []).append(rec)
    return sorted(by.items(), key=lambda kv: str(kv[0]))


def _plan_english(
    english_root: Path, current: dict[str, list[dict[str, Any]]], out: dict[str, str], counts: dict[str, int]
) -> None:
    """The English word card rows, one file beside each reading shard that has any, then the word tables."""
    for type_, recs_of_type in current.items():
        for shard, recs in _by_shard(type_, recs_of_type):
            if any(rec.get("english") for rec in recs):
                out[schema.english_relpath(type_, shard)] = lua_writer.english_text(type_, recs)
    counts["english"] = sum(1 for recs in current.values() for rec in recs if rec.get("english"))
    _plan_english_words(english_root, current, out)


def _with_english(
    type_: str, records: list[dict[str, Any]], english_lines: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """The reading records, each with its English word card row (`english`) when its line has English and a
    word of it found a Japanese word. A book page's reading is keyed by its English hash by now."""
    en: dict[tuple[Any, str], str] = {}
    for ln in english_lines:
        key = ln.get("hash") if type_ == "book" else ln["id"]
        if key is not None and isinstance(ln.get("en"), str):
            en.setdefault((key, ln["field"]), ln["en"])
    out = []
    for rec in records:
        text = en.get((rec["id"], rec["field"]))
        row = english_cards.pack(english_cards.invert(text, rec["words"])) if text else ""
        out.append(rec | {"english": row} if row else rec)
    return out


COMMON_WORDS = "common-words.jsonl"  # beside the English types in data/english/
PRONUNCIATION = "pronunciation.tsv"


def load_common_words(english_root: Path) -> dict[str, tuple[str, str]]:
    """{English word: (Japanese word, its reading)} from the common word list; none without the file."""
    path = english_root / COMMON_WORDS
    if not path.is_file():
        return {}
    out: dict[str, tuple[str, str]] = {}
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        rec = json.loads(line)
        word, ja, reading = rec.get("word"), rec.get("ja"), rec.get("reading")
        strings = isinstance(word, str) and isinstance(ja, str) and isinstance(reading, str)
        if not strings or not rec.get("provenance"):
            raise ValueError(f"{COMMON_WORDS}:{n}: word, ja, reading and provenance are required")
        plain = "=" not in ja + reading and " " not in ja + reading
        if word != word.lower() or english_cards.tokens(word) != [word] or not plain:
            raise ValueError(
                f"{COMMON_WORDS}:{n}: {word!r} is not one lower-case word with a plain Japanese word"
            )
        if word in out:
            raise ValueError(f"{COMMON_WORDS}:{n}: {word!r} is listed twice")
        out[word] = (ja, reading)
    return out


def _plan_english_words(
    english_root: Path, current: dict[str, list[dict[str, Any]]], out: dict[str, str]
) -> None:
    """The common word list and the pronunciation table, the latter cut down to the words a card can show."""
    common = load_common_words(english_root)
    if common:
        out[schema.ENGLISH_COMMON] = lua_writer.word_table_text(
            "common", {w: f"{ja}={reading}" for w, (ja, reading) in common.items()},
            "everyday English words with a Japanese word and its reading",
        )
    path = english_root / PRONUNCIATION
    if not path.is_file():
        return
    said, _ = pronunciation.parse_table(path.read_text(encoding="utf-8"))
    used = set(common)
    for recs in current.values():
        for rec in recs:
            for pair in (rec.get("english") or "").split():
                used.add(pair.rpartition("=")[0])
    rows = {w: said[w] for w in used if w in said}
    if rows:
        out[schema.ENGLISH_PRON] = lua_writer.word_table_text(
            "pron", rows, "how each English word on a card is said"
        )


def reading_store_of(store: Store) -> Store:
    """The readings store beside a translation store: `<data>/reading/`."""
    return Store(store.root / "reading")


def numbers_path(store: Store) -> Path:
    return reading_store_of(store).root / glosses.NUMBERS_FILE


def load_numbers(store: Store) -> tuple[dict[glosses.Meaning, int], list[str]]:
    """The numbers file (ADR-060) → (meaning → number, problems); no file → nothing numbered yet."""
    path = numbers_path(store)
    if not path.is_file():
        return {}, []
    return glosses.parse_numbers(path.read_bytes().decode("utf-8-sig"))


def toc_files(planned: dict[str, str]) -> list[str]:
    """Load order inside the generated block: Meta, Vectors, the error recordings, then shards by type
    then range."""
    shards = [p for p in planned if p not in FIXED and not p.startswith(f"{NAMES_DIR}/")]
    order = {t: i for i, t in enumerate(schema.TOC_ORDER)}

    def type_of(rel: str) -> str:
        return next(t for t, pre in schema.FILE_PREFIX.items() if rel.startswith(f"Data/{pre}/"))

    shards.sort(key=lambda p: (order[type_of(p)], p))
    return [*(p for p in FIXED if p in planned), *shards]


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
    """The files under Data/ that generate owns: `<Type>/<Type>_*.lua` and the `FIXED` files. Nothing else
    under Data/ is ever deleted or diffed (a README or a stray note is left alone)."""
    found: set[str] = set()
    data = addon_dir / "Data"
    for rel in FIXED:
        if (addon_dir / rel).is_file():
            found.add(rel)
    for prefix in (*schema.FILE_PREFIX.values(), NAMES_DIR.removeprefix("Data/")):
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


def write_numbers(store: Store, text: str) -> int:
    """Writes the numbers file when it changed (only ever lines added). → meanings newly numbered"""
    path = numbers_path(store)
    old = path.read_bytes().decode("utf-8") if path.is_file() else ""
    if not text or text == old:
        return 0
    path.write_bytes(text.encode("utf-8"))
    return len(glosses.parse_numbers(text)[0]) - len(glosses.parse_numbers(old)[0])


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
        store = Store(root)
        planned = plan(store, vectors_rows(root), report)
        # the numbers first: a run that stops after them gives the same numbers again next time
        numbers_written = write_numbers(store, report.get("meaning_numbers", ""))
        result = apply(planned, addon_dir)
    except ValueError as exc:
        raise SystemExit(f"generate: {exc}") from exc
    meta = planned["Data/Meta.lua"]
    counts = meta[meta.index("counts = {") : meta.index("},", meta.index("counts = {")) + 1]
    w, u, d = (len(result[k]) for k in ("written", "unchanged", "deleted"))
    print(f"generate: {len(planned)} artifacts; {counts}; written {w}, unchanged {u}, deleted {d}")
    if numbers_written:
        print(f"generate: {numbers_written} meanings numbered for the first time ({glosses.NUMBERS_FILE})")
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
