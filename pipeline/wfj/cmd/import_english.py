"""wfj import english …: the English sources: pfQuest, the client tables (wago-ids, client-text, wago-ui),
the collector, VMaNGOS and the quest cache (split out of cmd/import_.py by source; see its docstring and
docs/systems/pipeline.md).

English importers merge by source: an importer replaces its own lines and any line whose (id, field)
it provides, and keeps every other source's lines. The collector import replaces any stand-in
(see run_collector)."""

from __future__ import annotations

import argparse
import dataclasses
import re
from collections import Counter
from collections.abc import Iterable
from pathlib import Path
from typing import Any

from wfj.core.hashing import key as hash_key
from wfj.core.model import english_line, validate_line
from wfj.core.normalize import normalize_for, normalize_v1
from wfj.io import tables_stamp, vmangos, wago, wdb
from wfj.io.collector_dump import read_dump
from wfj.io.jsonl_store import Store
from wfj.io.lua_reader import as_int_id, parse_assignment
from wfj.paths import data_root

PFQUEST_FIELDS = {"T": "title", "O": "objectives", "D": "description"}


def source_name(line: dict[str, Any]) -> str:
    return str(line["src"]).split("@", 1)[0]


def _client_hash(en: str) -> str:
    """The canon for text a CLIENT template holds (an item or spell tooltip, a UI string), where `$n`, `$c`
    and `$r` are values the client fills in rather than the player: `Fear all Demons within $r yards` is a
    radius, `surrounded by $n balls of lightning` is a count. Server-written text keeps the player
    mapping, because there those codes really are the player. On the 1.60.1.69913 corpus this differs for 111
    lines, all item / spell descriptions and auras; no name or UI string carries one of those codes, so the
    call is a no-op there and the rule still holds if a later build adds one."""
    return normalize_for("item", en)  # the client-template canon (`normalize.CLIENT_TYPES`)


def merge_source(
    type_: str,
    existing: Iterable[dict[str, Any]],
    new: list[dict[str, Any]],
    name: str,
    union: bool = False,
    *,
    answered: set[Any] | None = None,
    outranked_by: tuple[str, ...] = (),
) -> list[dict[str, Any]]:
    """Source-owned merge for `data/english/<type>`: `new` replaces every line of source `name` and any
    line whose (id, field) it provides; other sources' lines stay. An empty `new` never wipes the source's
    existing lines.

    `union`: keep a line of source `name` that `new` does not provide, instead of dropping it. This is the
    same choice `_merge_fields` offers the client-table imports, for the same reason. The quest cache is the
    case: Forever's server answers under a third of the quest ids Classic Era's did (content the beta has not
    enabled yet), so a replace would drop ~2,900 quests from Blizzard's own text back to pfQuest's. Under
    union each kept line keeps its existing `src`, so what the newer client has never served stays visible as
    the older build's stamp rather than silently becoming the new build's.

    `answered` (with `union`): the ids this import answered as a whole, such as a quest the cache holds. For
    those, the new lines are the whole truth: an older build's line of `name` for a field the new one does
    not provide is dropped, not kept, because Forever reuses quest ids for different quests and the kept
    line would be another quest's English.

    `outranked_by`: sources whose existing line keeps its (id, field); this import's line for it is not
    written. pfQuest runs before the quest cache in `make import`; under union a later cache restores only
    what IT holds, so pfQuest replacing an earlier build's cached line would lose Blizzard's text for every
    quest the newer cache does not hold."""
    existing = list(existing)
    if not new and any(source_name(ln) == name for ln in existing):
        raise ValueError(f"refusing to replace existing {name} {type_} lines with zero lines")
    held = {(ln["id"], ln["field"]) for ln in existing if source_name(ln) in outranked_by}
    new = [ln for ln in new if (ln["id"], ln["field"]) not in held]
    keys = {(ln["id"], ln["field"]) for ln in new}
    answered = answered or set()
    kept = [
        ln
        for ln in existing
        if (ln["id"], ln["field"]) not in keys
        and (source_name(ln) != name or (union and ln["id"] not in answered))
    ]
    return kept + new


def run_pfquest(a: argparse.Namespace) -> int:
    root = data_root()
    name, table = parse_assignment(Path(a.file).read_text(encoding="utf-8-sig"))
    if name != "pfDB":
        raise ValueError(f"unexpected table {name!r} (want pfDB)")
    src = f"pfquest@{a.commit}"
    lines = []
    for key, val in table.items:
        id_ = as_int_id(key)
        for lua_field, field in PFQUEST_FIELDS.items():
            en = val.get(lua_field)
            if not en or not en.strip():
                continue
            lines.append(english_line(id_, field, en, hash_key(normalize_v1(en)), src))
    store = Store(root, english=True)
    # the quest cache's English outranks pfQuest's (ADR-020 decision 5), whichever build wrote it
    # what a client recorded in game (the collector) and the client's own cache outrank pfQuest (ADR-053)
    merged = merge_source("quest", store.load("quest"), lines, "pfquest", outranked_by=("wdb", "collector"))
    store.save("quest", merged)
    print(f"english quest: {len({ln['id'] for ln in lines})} ids, {len(lines)} lines ({src})")
    return 0


def run_wago(a: argparse.Namespace) -> int:
    # the CSVs' stamp matches --src / --build, before anything is read
    tables_stamp.check((Path(a.item_csv), Path(a.spell_csv)), a.src, a.build)
    root = data_root()
    src = f"{a.src}@{a.build}"
    store = Store(root, english=True)
    parsed: dict[str, list[dict[str, Any]]] = {}
    for type_, path in (
        ("item", Path(a.item_csv)),
        ("spell", Path(a.spell_csv)),
    ):  # read both before writing either
        id_col, name_col = wago.DEFAULT_COLUMNS[type_]
        id_col, name_col = a.id_col or id_col, a.name_col or name_col
        parsed[type_] = [
            english_line(id_, "name", nm, hash_key(_client_hash(nm)), src)
            for id_, nm in wago.read_names(path, id_col, name_col)
        ]
    # merge both before writing either: a refused spell import must not leave the item merge written
    union = getattr(a, "merge", "replace") == "union"
    merged = {
        t: _merge_fields(t, store.load(t), lines, ("name",), union) for t, lines in parsed.items()
    }
    for type_, lines in parsed.items():
        store.save(type_, merged[type_])
        print(f"english {type_}: {len(lines)} name lines ({src})")
    return 0


def run_wago_ui(a: argparse.Namespace) -> int:
    """UI strings: exactly the keys in the curated list, English from GlobalStrings / ItemSubClass (and the
    enchantment, subtext and text-family tables) at one build. A listed key the tables do
    not have, or have empty, fails the import (nothing is written)."""
    csvs = [Path(a.globalstrings_csv), Path(a.itemsubclass_csv)]
    csvs += [Path(a.enchantments)] if a.enchantments else []
    csvs += [Path(a.subtexts)] if getattr(a, "subtexts", None) else []
    families = Path(a.families) if getattr(a, "families", None) else None
    csvs += [families / f"{t}.csv" for t in wago.FAMILY_TABLES] if families else []
    tables_stamp.check(csvs, a.src, a.build)
    root = data_root()
    src = f"{a.src}@{a.build}"
    table = {
        **wago.read_global_strings(Path(a.globalstrings_csv)),
        **wago.read_item_subclasses(Path(a.itemsubclass_csv)),
    }
    if a.enchantments:  # enchantment stat lines, keyed by SpellItemEnchantment id
        table.update(wago.read_enchantments(Path(a.enchantments)))
    if getattr(a, "subtexts", None):  # spellbook subtexts, keyed by spell id
        table.update(wago.read_subtexts(Path(a.subtexts)))
    if families:  # the client-table text families, keyed by row id
        table.update(wago.read_families(families))
    keys = wago.expand_keys(wago.read_keys(Path(a.keys)), table)
    dupes = sorted(k for k, n in Counter(keys).items() if n > 1)
    if dupes:
        raise ValueError(f"wago-ui: listed twice after expanding families: {', '.join(dupes[:10])}")
    union = getattr(a, "merge", "replace") == "union"
    absent = [k for k in keys if not table.get(k, "").strip()]
    if absent and not union:
        shown = ", ".join(absent[:10])
        raise ValueError(f"wago-ui: {len(absent)} listed key(s) absent or empty at {a.build}: {shown}")
    if absent:
        # Under `union` an absent key is not a loss: its existing English stays, still stamped by the source
        # that provided it, so `wfj stats --unseen-since` counts it like any other line this client has never
        # had. The refusal above is still right for `replace`, where an absent key WOULD drop the line; the
        # gate exists so a mis-parsed GlobalStrings cannot silently empty the dictionary, and under union it
        # cannot. Reported every time, never silent.
        shown = ", ".join(absent[:10])
        more = f", +{len(absent) - 10} more" if len(absent) > 10 else ""
        print(
            f"wago-ui: {len(absent)} listed key(s) absent at {a.build}, "
            f"keeping their English: {shown}{more}"
        )
        keys = [k for k in keys if k not in set(absent)]
    lines = []
    for k in keys:
        problems = validate_line("ui", english_line(k, "text", table[k], "0" * 16, src), english=True)
        if problems:
            raise ValueError(f"wago-ui: {k}: {'; '.join(problems)}")
        lines.append(english_line(k, "text", table[k], hash_key(_client_hash(table[k])), src))
    store = Store(root, english=True)
    store.save(
        "ui",
        _merge_fields("ui", store.load("ui"), lines, ("text",), getattr(a, "merge", "replace") == "union"),
    )
    print(f"english ui: {len(lines)} keys ({src})")
    return 0


# ItemEffect.TriggerType values whose spell text the item tooltip prints (ADR-021): 0 "Use:", 1 "Equip:",
# 2 "Chance on hit:", 5 "Use:" without the delay. 6 (learn spell) and 7 (loot tracker) are dropped: on
# 1.15.9.69722 they only occur on Season of Discovery rune items and `[DNT]` trackers. This is a decision,
# not an in-game check (those items cannot be had on Era).
TOOLTIP_TRIGGERS = frozenset({0, 1, 2, 5})


def run_client_text(a: argparse.Namespace) -> int:
    """Item and spell tooltip English from the client tables: spell `description` =
    Spell.Description_lang, spell `aura` = Spell.AuraDescription_lang; item `description` = the item's
    ItemEffect spells' descriptions in (slot, effect id) order, then ItemSparse.Description_lang (flavour),
    non-empty parts joined by a line break. Only the trigger types the tooltip prints are joined
    (`TOOLTIP_TRIGGERS`); the others are counted. Raw client text: templates such as `$s1` stay, since numbers
    live in the spell-effect table (ADR-007). Hashed like every English line. Merged per (type, field) over
    the client-table sources (`_merge_fields`); the name lines of `wago-ids` are other fields and stay.
    Everything is read before anything is written."""
    stamped = [Path(a.item_csv), Path(a.spell_csv), Path(a.itemeffect_csv)]
    link = getattr(a, "itemxitemeffect_csv", None)
    if link:
        stamped.append(Path(link))
    tables_stamp.check(tuple(stamped), a.src, a.build)
    root = data_root()
    src = f"{a.src}@{a.build}"
    spells = wago.read_spell_texts(Path(a.spell_csv))
    flavour = wago.read_item_descriptions(Path(a.item_csv))
    # on a build whose ItemEffect has no relationship map, the item an effect belongs to comes from
    # ItemXItemEffect instead of ItemEffect.ParentItemID (which is 0 on every row there).
    items = wago.read_item_effect_items(Path(link)) if link else None
    effects = wago.read_item_effects(Path(a.itemeffect_csv), items)
    union = getattr(a, "merge", "replace") == "union"
    spell_lines = []
    for sid in sorted(spells):
        for field_name, en in zip(("description", "aura"), spells[sid], strict=True):
            if en.strip():
                spell_lines.append(english_line(sid, field_name, en, hash_key(_client_hash(en)), src))
    j = _join_item_parts(effects, spells, flavour)
    parts = j.parts
    item_lines = []
    for item in sorted(parts):
        en = "\n".join(parts[item])
        item_lines.append(english_line(item, "description", en, hash_key(_client_hash(en)), src))
    if getattr(a, "dry_run", False):  # every table read and joined: the preflight's question is answered
        print(f"client-text ({src}) [dry run: nothing written]: "
              f"{len(spell_lines)} spell · {len(item_lines)} item")
        return 0
    store = Store(root, english=True)
    merged = {
        "spell": _merge_fields(
            "spell", store.load("spell"), spell_lines, ("description", "aura"), union
        ),
        "item": _merge_fields("item", store.load("item"), item_lines, ("description",), union),
    }
    for type_, lines in merged.items():
        store.save(type_, lines)
    fields = Counter(ln["field"] for ln in spell_lines)
    print(
        f"english spell: description {fields['description']} · aura {fields['aura']} ({src})\n"
        f"english item: description {len(item_lines)} "
        f"({sum(1 for t in flavour.values() if t.strip())} with flavour text, "
        f"{len({e[0] for e in effects})} with effects) ({src})"
    )
    if j.hidden:
        shown = ", ".join(f"type {t}: {n}" for t, n in sorted(j.hidden.items()))
        print(f"item effects not in the tooltip, not joined: {shown}")
    if j.no_spell or j.no_item:
        print(
            f"item effects not written: {j.no_spell} name no known spell ({len(j.incomplete)} items left "
            f"without tooltip English), {j.no_item} no known item"
        )
    return 0


@dataclasses.dataclass
class _ItemParts:
    """Each item's tooltip English parts, and what the join left out."""

    parts: dict[int, list[str]] = dataclasses.field(default_factory=dict)
    no_spell: int = 0
    no_item: int = 0
    hidden: Counter = dataclasses.field(default_factory=Counter)
    incomplete: set[int] = dataclasses.field(default_factory=set)


def _join_item_parts(
    effects: list[tuple[int, int, int, int, int]], spells: dict[int, tuple[str, str]], flavour: dict[int, str]
) -> _ItemParts:
    """Each item's effect spell descriptions in effect order, then its flavour text (`run_client_text`)."""
    j = _ItemParts()
    for item, _slot, _effect, sid, trigger in effects:
        if trigger not in TOOLTIP_TRIGGERS:
            # a spell the tooltip does not print (learn, loot trackers): not its English, and never a reason
            # to call the item incomplete
            j.hidden[trigger] += 1
            continue
        # an effect naming a spell or an item the tables lack: counted, not written
        if item not in flavour:
            j.no_item += 1
        elif sid not in spells:
            j.no_spell += 1
            j.incomplete.add(item)  # part of its tooltip is unknown: no partial English for this item
        elif spells[sid][0].strip():
            j.parts.setdefault(item, []).append(spells[sid][0])
    for item, text in flavour.items():
        if text.strip():
            j.parts.setdefault(item, []).append(text)
    for item in j.incomplete:
        j.parts.pop(item, None)
    return j


# The client tables arrive under one of two labels: `wago@<build>` (wago.tools CSVs) or `db2@<build>` (the
# same tables read from an installed client). They are one source for merging: a re-import under
# either label replaces the other's lines of the same fields, so no line of an earlier build or label lingers.
CLIENT_TABLE_SOURCES = ("wago", "db2")
SRC_HELP = "wago: wago.tools CSVs; db2: the same tables read from an installed client"
MERGE_HELP = (
    '"replace" (default) drops a client-table line this import does not provide, which is right '
    "while one client is the truth. \"union\" keeps it with its existing src, for a second client "
    "that ships fewer ids; `wfj stats --unseen-since <src@build>` then counts what the newer "
    "client has never had."
)


def _merge_fields(
    type_: str,
    existing: list[dict[str, Any]],
    new: list[dict[str, Any]],
    fields: tuple[str, ...],
    union: bool = False,
) -> list[dict[str, Any]]:
    """merge_source for the client-table sources, limited to `fields`: their lines of those fields are
    replaced as a set; lines of other fields (item / spell names vs tooltip text) and other sources stay.

    `union`: keep a client-table line this import does not provide, instead of dropping it. The
    default (replace the set) is right while one client is the truth: a row the client no longer has is a
    row that should go. It is wrong across two clients, because Forever ships far fewer ids than Classic Era
    (ItemSparse 19,171 against 24,442), so replacing deletes the English for every id Forever lacks and their
    Japanese stops shipping for want of an English line to check it against (measured: item descriptions
    2,664 -> 1,910 shipping, 302 of them newly `no_english_id`).

    Under `union` an unprovided line keeps its existing `src`, which is what makes the loss recoverable
    later: a line still stamped `wago@<vanilla build>` after a Forever import is one Forever has never had,
    and `wfj stats --unseen-since db2@<build>` counts them. When a build stops being merely a beta and the
    set has stopped shrinking, those lines can be dropped on evidence rather than on a guess."""
    mine = lambda ln: source_name(ln) in CLIENT_TABLE_SOURCES and ln["field"] in fields  # noqa: E731
    if not new and any(mine(ln) for ln in existing):
        raise ValueError(f"refusing to replace existing {type_} {'/'.join(fields)} lines with zero lines")
    new = _without_recorded(existing, new)
    keys = {(ln["id"], ln["field"]) for ln in new}
    kept = [
        ln
        for ln in existing
        if (ln["id"], ln["field"]) not in keys and (union or not mine(ln))
    ]
    return kept + new


def _without_recorded(existing: list[dict[str, Any]], new: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """`new` without the (id, field)s a client recorded in game on another client line than `new`'s: what the
    Forever client showed outranks an older client's files (ADR-053), and the same client's own files keep
    their place."""
    if not new:
        return new
    build = str(new[0]["src"]).split("@", 1)[-1]
    held = {
        (ln["id"], ln["field"])
        for ln in existing
        if source_name(ln) == "collector" and not _same_client(str(ln["src"]), build)
    }
    return [ln for ln in new if (ln["id"], ln["field"]) not in held]


_VERSION = re.compile(r"^(\d+\.\d+)\.")
_WORDS = re.compile(r"\$[A-Za-z]|[A-Za-z']+|[^\sA-Za-z']")
_PLAYER_TOKENS = {"$C", "$c", "$R", "$r"}
# the words a recording player's class or race can be: only these are put back for a `$C` / `$R`
_CLASS_RACE = frozenset({
    "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid",
    "human", "orc", "dwarf", "night elf", "undead", "tauren", "gnome", "troll",
})


def _same_client(src: str, build: str) -> bool:
    """True when `src` was read from the same game line as `build` (both `1.60.…`): that client's own text
    (its tables, its quest cache, an earlier dump), not a stand-in from another server or game version."""
    theirs, ours = _VERSION.match(src.split("@", 1)[-1]), _VERSION.match(build)
    return bool(theirs and ours and theirs.group(1) == ours.group(1))


def _restore_literals(recorded: str, stand_in: str) -> str:
    """The collector writes the recording player's class and race as `$C` / `$R` wherever the words occur, so
    "a wise druid", recorded by a druid, comes back as "a wise $C". Where the stand-in has a literal word at
    that spot, the literal is put back: a druid's dump cannot tell the two apart, the stand-in can."""
    from difflib import SequenceMatcher

    ours, theirs = list(_WORDS.finditer(recorded)), list(_WORDS.finditer(stand_in))
    ow, tw = [m.group() for m in ours], [m.group() for m in theirs]
    out, last = [], 0
    for op, i1, i2, j1, j2 in SequenceMatcher(None, ow, tw, autojunk=False).get_opcodes():
        swap = op == "replace" and i2 - i1 == 1 and ow[i1] in _PLAYER_TOKENS and 1 <= j2 - j1 <= 2
        if swap and " ".join(tw[j1:j2]).lower() in _CLASS_RACE:
            out.append(recorded[last : ours[i1].start()])
            out.append(stand_in[theirs[j1].start() : theirs[j2 - 1].end()])
            last = ours[i1].end()
    out.append(recorded[last:])
    return "".join(out)


def run_collector(a: argparse.Namespace) -> int:
    """Add a collector dump to `data/english/`. What the Forever client shows is the English, so per (type,
    id, field): absent → added; same hash → unchanged; another hash → replaced, unless the line came from the
    same client's own files (its tables or quest cache, `_same_client`), which are kept and listed as differs.
    A replaced stand-in (pfQuest, VMaNGOS, an older client) gets its literal class or race words back
    (`_restore_literals`). A gossip line is keyed by its hash, so it is only ever added or unchanged; the NPC
    ids a dump names are unioned into its `npcs` (counted `npcs`). Invalid entries are counted by reason,
    never written."""
    root = data_root()
    path = Path(a.file)
    dump = read_dump(path.read_text(encoding="utf-8-sig"))
    store = Store(root, english=True)
    by_type: dict[str, list[Any]] = {}
    for en in dump.entries:
        by_type.setdefault(en.type_, []).append(en)
    counts: dict[str, Counter] = {}
    differs: list[str] = []
    for type_ in sorted(by_type):
        lines = store.load(type_)
        index = {(ln["id"], ln["field"]): i for i, ln in enumerate(lines)}
        c: Counter = Counter()
        for en in by_type[type_]:
            line = english_line(en.id_, en.field, en.en, en.hash_, f"collector@{en.build}", npcs=en.npcs)
            k = (en.id_, en.field)
            if k not in index:
                index[k] = len(lines)
                lines.append(line)
                c["added"] += 1
                continue
            cur = lines[index[k]]
            if cur["hash"] == en.hash_ and not set(en.npcs) <= set(cur.get("npcs", [])):
                cur["npcs"] = sorted(set(cur.get("npcs", [])) | set(en.npcs))
                c["npcs"] += 1
            elif cur["hash"] == en.hash_:
                c["unchanged"] += 1
            elif source_name(cur) == "collector" or not _same_client(cur["src"], en.build):
                # an earlier dump's line may hold a literal class or race word put back from a stand-in
                text = _restore_literals(en.en, cur["en"])
                if hash_key(normalize_v1(text)) == cur["hash"]:
                    c["unchanged"] += 1
                    continue
                src = f"collector@{en.build}"
                h = hash_key(normalize_v1(text))
                lines[index[k]] = english_line(en.id_, en.field, text, h, src, npcs=en.npcs)
                c["replaced"] += 1
            else:
                c["differs"] += 1
                differs.append(f"  {type_} {en.id_} {en.field} (kept {cur['src']})")
        if c["added"] or c["replaced"] or c["npcs"]:
            store.save(type_, lines)
        counts[type_] = c
    builds = sorted({en.build for en in dump.entries})
    print(f"english collector: {path.name} · {len(dump.entries)} entries · builds {', '.join(builds) or '-'}")
    print(f"{'type':6} {'added':>6} {'unchanged':>9} {'replaced':>8} {'differs':>7}")
    for type_, c in counts.items():
        print(f"{type_:6} {c['added']:6} {c['unchanged']:9} {c['replaced']:8} {c['differs']:7}")
    if "gossip" in counts:
        print(f"gossip lines that gained an NPC: {counts['gossip']['npcs']}")
    rejected = ", ".join(f"{r} {n}" for r, n in sorted(dump.rejected.items())) or "none"
    print(f"rejected: {rejected}")
    if differs:
        print("differs from the client's own files (kept):")
        print("\n".join(differs))
    return 0


_COMMIT = re.compile(r"^[0-9a-f]{7,40}$")


def run_vmangos(a: argparse.Namespace) -> int:
    """Quest progress / completion and gossip English from the VMaNGOS world database (ADR-019), and
    book pages (`book`, keyed by page entry). Trainer greetings are not read: Forever's trainer UI has no
    greeting.
    Quest: source-owned merge (replaces earlier `vmangos@` lines and any (id, field) it provides). Gossip: a
    key is the hash of its English, so a key already present from another source (a collector dump with its
    `npcs`) is left as it is; the vmangos gossip lines are replaced as a set. Both types are read before
    either is written."""
    if not _COMMIT.match(a.commit or ""):
        raise ValueError(f"vmangos: --commit must be a 7–40 hex commit, got {a.commit!r}")
    path = Path(a.file)
    src = f"vmangos@{a.commit}"
    quest = [
        english_line(id_, f, en, hash_key(normalize_v1(en)), src) for id_, f, en in vmangos.read_quests(path)
    ]
    by_key: dict[str, dict[str, Any]] = {}
    norms: dict[str, str] = {}
    # sorted: the first text of a normalized form keeps the key. Then NPC speech, one keyed set with
    # gossip: a gossip text keeps its key's English (a speech row with other spacing never replaces it)
    for en in vmangos.read_gossip(path) + vmangos.read_speech(path):
        norm = normalize_v1(en)
        if not norm:
            continue
        k = hash_key(norm)
        if norms.setdefault(k, norm) != norm:  # a collision is reported, never resolved silently
            raise ValueError(f"vmangos: gossip hash {k} names two texts: {norms[k]!r} and {norm!r}")
        by_key.setdefault(k, english_line(k, "text", en, k, src))
    books = [
        english_line(entry, "text", page, hash_key(normalize_v1(page)), src)
        for entry, page in vmangos.read_books(path)
    ]
    store = Store(data_root(), english=True)
    # Merge every type before writing any: a refused merge must not leave another type's merge written.
    # a line a client recorded in game (the collector) outranks VMaNGOS, a stand-in (ADR-053)
    merged_book = merge_source("book", store.load("book"), books, "vmangos", outranked_by=("collector",))
    merged_quest = merge_source("quest", store.load("quest"), quest, "vmangos", outranked_by=("collector",))
    existing = store.load("gossip")
    mine = {ln["id"]: ln for ln in existing if source_name(ln) == "vmangos"}
    if not by_key and mine:
        raise ValueError("refusing to replace existing vmangos gossip lines with zero lines")
    others = [ln for ln in existing if source_name(ln) != "vmangos"]
    present = {ln["id"]: ln for ln in others}
    gossip = []
    for k, ln in sorted(by_key.items()):
        if k in present:
            if normalize_v1(present[k]["en"]) != norms[k]:  # never resolved silently
                other = f"{present[k]['en']!r} ({present[k]['src']})"
                raise ValueError(f"vmangos: gossip hash {k} names two texts: {other}")
            continue
        if mine.get(k, {}).get("npcs"):  # NPC ids a collector dump added to this line are kept
            gossip.append({**ln, "npcs": mine[k]["npcs"]})
        else:
            gossip.append(ln)
    store.save("quest", merged_quest)
    store.save("gossip", others + gossip)
    store.save("book", merged_book)
    fields = Counter(ln["field"] for ln in quest)
    print(
        f"english quest: {len({ln['id'] for ln in quest})} ids · progress {fields['progress']} · "
        f"completion {fields['completion']} ({src})"
    )
    kept = len(by_key) - len(gossip)
    print(f"english gossip: {len(gossip)} keys ({src}); {kept} already present from another source")
    print(f"english book: {len(books)} pages ({src})")
    return 0


_BUILD = re.compile(r"^\d+\.\d+\.\d+\.(\d+)$")
WDB_FIELDS = ("title", "objectives", "description")
# the area description (an exploration / event objective's text) is its own type, keyed by quest id
AREA_TYPE, AREA_FIELD = "area", "text"
# Quest ids below this are the Vanilla range the scan walks in full; coverage reports it apart.
VANILLA_ID_LIMIT = 10000


def take_answered_whole(lines: list[dict[str, Any]], answered: set[Any]) -> list[dict[str, Any]]:
    """Under union, a quest the cache answered is the cache's alone for `WDB_FIELDS`: pfQuest's line for a
    field the cache left empty is dropped too (see `run_wdb`)."""
    return [
        ln for ln in lines
        if not (ln["id"] in answered and ln["field"] in WDB_FIELDS and source_name(ln) == "pfquest")
    ]


def run_wdb(a: argparse.Namespace) -> int:
    """Blizzard's cached quest text (ADR-020): title / objectives / description from the client's
    `questcache.wdb`, `src wdb@<build>`, plus each objective's own text as English type `objective` keyed by
    its QuestObjective id, and the area description as English type `area` / field `text` keyed by
    the quest id. Source-owned merge: replaces earlier `wdb@` lines and
    any (id, field) it provides, so a cached quest's pfQuest line for that field is replaced. An empty cached
    field writes nothing: under `replace` (one client) pfQuest's line stays; under `union` a
    quest this cache answered is taken WHOLE for title / objectives / description / area; neither an older
    build's cached line nor pfQuest's fills a field it left empty, because the newer client may have reused
    the id for another quest, and English from the old quest would let its Japanese ship against the new
    title. The field then has no English and the player sees the live text. VMaNGOS progress / completion
    are untouched. Everything is read before anything is written.

    Shrink guard: a quest that holds `wdb@<same build>` English but is not in this cache
    at all (a wiped cache, the wrong install) would lose that English. The import refuses unless
    `--allow-shrink`. A cache of another build replaces the earlier build's lines by design; the ids it lacks
    are counted and fall back to pfQuest in `make import-english`. `--dry-run` runs every check and prints the
    report, writing nothing (the Makefile runs it before any import step)."""
    m = _BUILD.match(a.build or "")
    if not m:
        raise ValueError(f"wdb: --build must look like 1.15.9.69722, got {a.build!r}")
    if a.missing and not a.questv2:
        raise ValueError("wdb: --missing needs --questv2")
    path = Path(a.file)
    cache = wdb.read_quests(path)
    if int(m.group(1)) != cache.build:
        raise ValueError(f"wdb: {path.name} is build {cache.build}, --build is {a.build}")
    questv2 = wago.read_ids(Path(a.questv2)) if a.questv2 else None
    src = f"wdb@{a.build}"
    lines, area_lines, objective_lines = _wdb_lines(cache, src)
    if not lines:
        raise ValueError(f"wdb: {path.name} holds no quest text")
    store = Store(data_root(), english=True)
    existing = store.load("quest")
    before = {(ln["id"], ln["field"]): ln["hash"] for ln in existing}
    cached = {q.id for q in cache.quests} | set(cache.placeholders)
    gone, same_build = _check_shrink(existing, cached, src, path.name, a.allow_shrink)
    union = getattr(a, "merge", "replace") == "union"
    # what a client recorded in game outranks an older client's cache
    lines = _without_recorded(existing, lines)
    merged = merge_source("quest", existing, lines, "wdb", union, answered=set(cached))
    if union:
        merged = take_answered_whole(merged, cached)
    merged_objectives = _merge_objectives(store.load("objective"), objective_lines, union)
    gossip_lines = _wdb_keyed_lines(cache, src)
    merged_gossip, added_gossip = _add_keyed(store.load("gossip"), gossip_lines)
    prior_area = store.load(AREA_TYPE)
    merged_area = _merge_area(prior_area, area_lines, cached, union)
    before_area = {(ln["id"], ln["field"]): ln["hash"] for ln in prior_area}
    counts = {f: Counter() for f in (*WDB_FIELDS, AREA_TYPE)}
    for ln in lines:
        counts[ln["field"]][_change_kind(before, ln)] += 1
    for ln in area_lines:
        counts[AREA_TYPE][_change_kind(before_area, ln)] += 1
    unanswered: list[int] = []
    if questv2 is not None:
        unanswered = sorted(questv2 - cached)
        if a.missing and not a.dry_run:
            Path(a.missing).write_text("".join(f"{i}\n" for i in unanswered), encoding="utf-8")
    if not a.dry_run:
        store.save("quest", merged)
        store.save("objective", merged_objectives, allow_empty=True)
        store.save(AREA_TYPE, merged_area, allow_empty=True)
        store.save("gossip", merged_gossip, allow_empty=True)
    records = len(cache.quests) + len(cache.placeholders)
    print(
        f"english quest ({src}){' [dry run: nothing written]' if a.dry_run else ''}: {records} records · "
        f"{len(cache.quests)} quests · {len(cache.placeholders)} placeholders dropped"
    )
    if gone:
        how = "their English deleted, --allow-shrink"
        if not same_build:
            how = "earlier build; kept at that build's src" if union else (
                "earlier build; they fall back to pfQuest"
            )
        print(f"quests with earlier wdb English not in this cache: {len(gone)} ({how})")
    print(f"{'field':12} {'same':>6} {'changed':>7} {'new':>6}")
    for f in (*WDB_FIELDS, AREA_TYPE):
        c = counts[f]
        print(f"{f:12} {c['same']:6} {c['changed']:7} {c['new']:6}")
    print(f"english objective ({src}): {len(objective_lines)} objective texts")
    kinds = "conditional descriptions, completion logs"
    print(f"english gossip ({src}): {len(gossip_lines)} keyed texts ({kinds}), {added_gossip} new")
    if questv2 is not None:
        _print_questv2(questv2, unanswered, cached, a.missing)
    return 0


def _wdb_lines(
    cache: wdb.WdbCache, src: str
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    """A quest cache's English → (quest lines, area lines, objective lines by objective id)."""
    lines = [
        english_line(q.id, f, en, hash_key(normalize_v1(en)), src)
        for q in cache.quests
        for f, en in zip(WDB_FIELDS, (q.title, q.objectives, q.description), strict=True)
        if en.strip()
    ]
    area_lines = [
        english_line(q.id, AREA_FIELD, q.area, hash_key(normalize_v1(q.area)), src)
        for q in cache.quests
        if q.area.strip()
    ]
    # objective text is its own English type, keyed by the QuestObjective id (never by position)
    objectives: dict[int, dict[str, Any]] = {}
    for q in cache.quests:
        for oid, en in q.objective_texts:
            if not en.strip():
                continue
            if oid in objectives:  # reported, never resolved silently
                raise ValueError(f"wdb: objective {oid} is cached under two quests")
            objectives[oid] = english_line(oid, "text", en, hash_key(normalize_v1(en)), src)
    return lines, area_lines, [objectives[k] for k in sorted(objectives)]


def _check_shrink(
    existing: list[dict[str, Any]], cached: set[int], src: str, name: str, allow_shrink: bool
) -> tuple[list[int], bool]:
    """→ (quests with earlier wdb English this cache lacks, whether that English is this same build).
    Raises when a same-build cache would delete English and `--allow-shrink` was not given."""
    prior_wdb = [ln for ln in existing if source_name(ln) == "wdb"]
    gone = sorted({ln["id"] for ln in prior_wdb if ln["id"] not in cached})
    same_build = {ln["src"] for ln in prior_wdb} == {src}
    if gone and same_build and not allow_shrink:
        shown = ", ".join(map(str, gone[:10]))
        raise ValueError(
            f"wdb: {len(gone)} quest(s) with {src} English are not in {name} ({shown}…): "
            "a smaller cache of the same build would delete their English. Copy the right cache, or pass "
            "--allow-shrink"
        )
    return gone, same_build


def _merge_objectives(
    prior_objectives: list[dict[str, Any]], objective_lines: list[dict[str, Any]], union: bool
) -> list[dict[str, Any]]:
    """The objective store after a wdb import."""
    # objectives follow the quests: a cache without objective text replaces the earlier wdb objective lines
    # (the shrink guard already refuses losing a same-build quest). Not `merge_source`, whose
    # zero-lines guard would refuse a cache that legitimately carries no objective text. Under union an
    # earlier build's objective line is kept where this cache does not provide that (id, field).
    if union:
        # keyed by objective id, not quest id: an id this cache does not provide keeps its earlier build
        provided = {(ln["id"], ln["field"]) for ln in objective_lines}
        kept_objectives = [ln for ln in prior_objectives if (ln["id"], ln["field"]) not in provided]
    else:
        kept_objectives = [ln for ln in prior_objectives if source_name(ln) != "wdb"]
    return kept_objectives + objective_lines


def _merge_area(
    prior_area: list[dict[str, Any]], area_lines: list[dict[str, Any]], cached: set[int], union: bool
) -> list[dict[str, Any]]:
    """The area store after a wdb import."""
    # area lines follow their quest, which the cache answers whole (as title / objectives /
    # description): under union an earlier build's line stays only for a quest this cache did not
    # answer; under replace every earlier wdb line goes. Like objectives, a cache with no area text is not
    # refused.
    kept_area = [
        ln for ln in prior_area
        if (ln["id"] not in cached if union else source_name(ln) != "wdb")
    ]
    return kept_area + area_lines


def _change_kind(before: dict[tuple[Any, str], str], ln: dict[str, Any]) -> str:
    """"new", "same" or "changed" against the line's earlier hash."""
    prior = before.get((ln["id"], ln["field"]))
    return "new" if prior is None else "same" if prior == ln["hash"] else "changed"


def _wdb_keyed_lines(cache: wdb.WdbCache, src: str) -> list[dict[str, Any]]:
    """The quest cache's text the client shows with no id the addon can read, keyed like NPC dialogue by the
    hash of its English (ADR-005): a quest's conditional description (another wording of the same quest for a
    class or race, shown in the quest window in place of the default) and its completion log line (the
    tracker's and the quest log's line once the quest is ready). The addon finds them by the live text's
    fingerprint."""
    out: dict[str, dict[str, Any]] = {}
    for q in cache.quests:
        texts = [t for _, _, t in q.conditional] + [q.completion_log]
        for en in texts:
            norm = normalize_v1(en or "")
            if norm:
                k = hash_key(norm)
                out.setdefault(k, english_line(k, "text", en, k, src))
    return [out[k] for k in sorted(out)]


def _add_keyed(existing: list[dict[str, Any]], new: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], int]:
    """Keyed English is additive: a key already present (from VMaNGOS, the collector or an earlier cache)
    keeps its line; a key holding other English is reported, never resolved silently. → (lines, added)"""
    present = {ln["id"]: ln for ln in existing}
    added = []
    for ln in new:
        cur = present.get(ln["id"])
        if cur is None:
            added.append(ln)
        elif normalize_v1(cur["en"]) != normalize_v1(ln["en"]):
            raise ValueError(f"wdb: gossip hash {ln['id']} names two texts: {cur['en']!r} and {ln['en']!r}")
    return existing + added, len(added)


def _print_questv2(questv2: set[int], unanswered: list[int], cached: set[int], missing: str | None) -> None:
    """Report how much of QuestV2 the cache answered."""
    low = {i for i in questv2 if i < VANILLA_ID_LIMIT}
    missed_low = sum(1 for i in unanswered if i < VANILLA_ID_LIMIT)
    print(f"answered {len(low) - missed_low} / {len(low)} QuestV2 ids below {VANILLA_ID_LIMIT}")
    print(f"answered {len(questv2) - len(unanswered)} / {len(questv2)} all QuestV2 ids")
    print(f"cached ids not in QuestV2: {len(cached - questv2)}")
    if missing:
        print(f"unanswered: {len(unanswered)} ids → {missing}")
