"""Coverage report: per type × field × status × reason counts, plus the headline yield."""

from __future__ import annotations

from collections import Counter, defaultdict
from typing import Any

from wfj.core import placeholders

SHIPPED = ("trusted", "stale", "unaligned")


def tally(lines_by_type: dict[str, list[dict[str, Any]]]) -> dict[str, Any]:
    out: dict[str, Any] = {
        "types": {}, "reasons": {}, "checks_empty": {}, "conflicts": {}, "truncated": {}, "placeholders": {},
        "classes": {},
    }
    for type_, lines in lines_by_type.items():
        fields: dict[str, Counter] = defaultdict(Counter)
        reasons: Counter = Counter()
        truncated: Counter = Counter()  # (source, translator) → lines rejected as truncated
        tokens: Counter = Counter()  # player tokens in shipped lines
        classes: Counter = Counter()  # shipped lines by who wrote them: human / correction / machine
        empty = 0
        with_conflicts = 0
        for ln in lines:
            fields[ln["field"]][ln["status"]] += 1
            for r in ln.get("reasons", []):
                reasons[r.split(":", 1)[0]] += 1
                if r.startswith("truncated"):
                    prov = ln.get("provenance", {})
                    src = str(prov.get("source", "?")).split("@")[0]
                    truncated[(src, prov.get("translator", "?"))] += 1
            if ln["status"] in ("trusted", "stale") and not ln.get("checks"):
                empty += 1
            if ln.get("conflicts"):
                with_conflicts += 1
            if ln["status"] in SHIPPED:
                tokens.update(placeholders.tokens(ln.get("ja")))
                classes[str(ln.get("provenance", {}).get("class", "?"))] += 1
        out["types"][type_] = {f: dict(c) for f, c in fields.items()}
        out["reasons"][type_] = dict(reasons)
        out["checks_empty"][type_] = empty
        out["classes"][type_] = {k: classes[k] for k in ("human", "correction", "machine") if classes.get(k)}
        out["conflicts"][type_] = with_conflicts
        out["truncated"][type_] = {f"{src}/{tr}": n for (src, tr), n in sorted(truncated.items())}
        order = [f"{{{w}}}" for w in placeholders.KNOWN] + ["<a/b>"]
        out["placeholders"][type_] = {
            k: tokens[k] for k in [*order, *sorted(set(tokens) - set(order))] if tokens.get(k)
        }
    return out


def headline(lines_by_type: dict[str, list[dict[str, Any]]], vanilla_ids: set[int]) -> dict[str, int]:
    """The yield numbers: quests with pfQuest English vs quests whose title/description ship."""
    q = lines_by_type.get("quest", [])

    def shipped(field: str) -> set[int]:
        return {ln["id"] for ln in q if ln["field"] == field and ln["status"] in ("trusted", "stale")}

    def truncated(field: str) -> set[int]:
        return {
            ln["id"]
            for ln in q
            if ln["field"] == field and any(r.startswith("truncated") for r in ln.get("reasons", []))
        }

    return {
        "quests with description English (pfQuest or the quest cache)": len(vanilla_ids),
        # every trusted description is complete by rule (a truncated one is rejected)
        "vanilla quests with a trusted description": len(shipped("description") & vanilla_ids),
        "vanilla quests whose description was rejected as truncated": len(
            truncated("description") & vanilla_ids
        ),
        "vanilla quests with a trusted title": len(shipped("title") & vanilla_ids),
        "quest ids rejected no_english_id (post-Vanilla)": len(
            {ln["id"] for ln in q if "no_english_id" in ln["reasons"]}
        ),
    }


def render(t: dict[str, Any], headline: dict[str, int] | None = None) -> str:
    rows = ["type   field        total trusted unalign stale rejected pending  | reasons"]
    for type_, fields in t["types"].items():
        for f, c in fields.items():
            total = sum(c.values())
            rows.append(
                f"{type_:6} {f:12} {total:6} {c.get('trusted', 0):7} {c.get('unaligned', 0):7} "
                f"{c.get('stale', 0):5} {c.get('rejected', 0):8} {c.get('pending', 0):7}"
            )
        rs = ", ".join(f"{k}={v}" for k, v in sorted(t["reasons"][type_].items()))
        rows.append(
            f"       {type_} reasons: {rs or '-'}; checks=[] on {t['checks_empty'][type_]} shipped lines; "
            f"lines with conflicts: {t['conflicts'][type_]}"
        )
        shipped_by = t.get("classes", {}).get(type_) or {}
        by_class = " · ".join(f"{k} {shipped_by.get(k, 0)}" for k in ("human", "correction", "machine"))
        rows.append(f"       {type_} shipped by provenance: {by_class}")
        if t.get("truncated", {}).get(type_):
            tr = ", ".join(f"{k}={v}" for k, v in t["truncated"][type_].items())
            rows.append(f"       {type_} truncated by source/translator: {tr}")
        if t.get("placeholders", {}).get(type_):
            ph = " ".join(f"{k}={v}" for k, v in t["placeholders"][type_].items())
            rows.append(f"       {type_} placeholders in shipped lines: {ph}")
    if headline:
        rows.append("")
        for k, v in headline.items():
            rows.append(f"{k}: {v}")
    return "\n".join(rows)


GOSSIP_TOP = 20


def gossip_radius(english: list[dict[str, Any]], lines: list[dict[str, Any]], top: int = GOSSIP_TOP) -> str:
    """The gossip blast radius (ADR-005): gossip keys with English by how many NPCs a collector dump
    saw say them, so the lines a translation would change most widely are reviewed first. Builds no scope."""
    if not english:
        return "gossip: no collected English"
    status = {ln["id"]: ln["status"] for ln in lines if ln.get("field") == "text"}
    translated = sum(1 for ln in english if status.get(ln["id"]) in SHIPPED)
    # VMaNGOS gossip English (no NPC ids) shares the store with collected lines
    rows = [f"gossip: {len(english)} keys with English · {translated} translated"]
    for ln in sorted(english, key=lambda x: (-len(x.get("npcs", [])), x["id"]))[:top]:
        en = ln["en"] if len(ln["en"]) <= 60 else ln["en"][:60] + "…"
        rows.append(f"  {len(ln.get('npcs', [])):3} {ln['id']} {status.get(ln['id'], '-'):9} {en}")
    return "\n".join(rows)


def stale_rows(
    lines: list[dict[str, Any]], english: list[dict[str, Any]], field_order: list[str]
) -> list[dict[str, Any]]:
    """The quest lines to fix without meeting them in-game (ADR-019): every shipped line that is
    `stale`, or whose (id, field) has English from any source, collector English included (stored, or read
    from a dump by `stats --dump`) though `check` does not consult it, with a hash other than the one the
    line was checked against. Each row carries the Japanese, the English it was checked against (`en` / `src`,
    when that English is still in the store) and the disagreeing English under `others` (one per source and
    hash). Sorted by (id, field order)."""
    by_field: dict[tuple[Any, str], list[dict[str, Any]]] = defaultdict(list)
    for ln in english:
        by_field[(ln["id"], ln["field"])].append(ln)
    rows = []
    for ln in lines:
        if ln["status"] not in SHIPPED:
            continue
        checked = (ln.get("english") or {}).get("hash")
        candidates = by_field.get((ln["id"], ln["field"]), [])
        seen: dict[tuple[str, str], dict[str, str]] = {}
        for e in candidates:
            if e["hash"] != checked:
                seen.setdefault((e["src"], e["hash"]), {"src": e["src"], "en": e["en"], "hash": e["hash"]})
        others = [seen[k] for k in sorted(seen)]
        if ln["status"] != "stale" and not others:
            continue
        own = next((e for e in candidates if e["hash"] == checked), None)
        rows.append({
            "id": ln["id"], "field": ln["field"], "status": ln["status"], "ja": ln["ja"],
            "en": own["en"] if own else None, "src": (ln.get("english") or {}).get("src"),
            # `of`: checked against another field's English, so every English of its own field differs
            "of": (ln.get("english") or {}).get("of"), "others": others,
        })
    rows.sort(key=lambda r: (r["id"], field_order.index(r["field"])))
    return rows


DELTA_QUEST_FIELDS = ("title", "objectives", "description")


def english_delta(base: list[dict[str, Any]], head: list[dict[str, Any]]) -> dict[str, Any]:
    """English of one type at a base ref vs now (`stats --delta`): ids only now (`new`), ids only at
    the base (`removed`), and lines of ids in both whose hash differs or that exist on one side only
    (`changed`, per field)."""
    b = {(ln["id"], ln["field"]): ln["hash"] for ln in base}
    h = {(ln["id"], ln["field"]): ln["hash"] for ln in head}
    b_ids, h_ids = {k[0] for k in b}, {k[0] for k in h}
    both = b_ids & h_ids
    changed: Counter = Counter()
    for key in set(b) | set(h):
        if key[0] in both and b.get(key) != h.get(key):
            changed[key[1]] += 1
    return {"new": len(h_ids - b_ids), "removed": len(b_ids - h_ids), "changed": changed}


def render_delta(ref: str, deltas: dict[str, dict[str, Any]]) -> str:
    w = max([6, *map(len, deltas)])
    rows = [f"english delta since {ref}:", f"{'type':{w}} {'new':>6} {'removed':>7} {'changed':>7}  by field"]
    for type_, d in deltas.items():
        fields = " ".join(f"{f}={n}" for f, n in sorted(d["changed"].items())) or "-"
        rows.append(f"{type_:{w}} {d['new']:6} {d['removed']:7} {sum(d['changed'].values()):7}  {fields}")
    return "\n".join(rows)


def status_shift(base: list[dict[str, Any]], head: list[dict[str, Any]]) -> Counter:
    """Translation lines of one type whose status differs between a base ref and now: Counter of
    (field, status then, status now); a line on one side only counts with `-` for the other side."""
    b = {(ln["id"], ln["field"]): ln.get("status", "-") for ln in base}
    h = {(ln["id"], ln["field"]): ln.get("status", "-") for ln in head}
    shift: Counter = Counter()
    for key in set(b) | set(h):
        was, now = b.get(key, "-"), h.get(key, "-")
        if was != now:
            shift[(key[1], was, now)] += 1
    return shift


def render_status_shift(ref: str, shifts: dict[str, Counter]) -> str:
    rows = [f"status shift since {ref}:"]
    for type_, shift in shifts.items():
        moves = ", ".join(f"{f} {was}→{now} {n}" for (f, was, now), n in sorted(shift.items())) or "none"
        rows.append(f"  {type_}: {moves}")
    return "\n".join(rows)


def capture_rows(base: list[dict[str, Any]], head: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """The turn-in capture list: one row per quest id that is new, or whose title / objectives /
    description English changed (hash differs, or present on one side only), with the current title and the
    source of its progress / completion English (None = no English: a player must see that window). Sorted by
    id."""
    b = {(ln["id"], ln["field"]): ln for ln in base}
    h = {(ln["id"], ln["field"]): ln for ln in head}
    b_ids = {k[0] for k in b}
    rows = []
    for id_ in sorted({k[0] for k in h}):
        if id_ not in b_ids:
            change, fields = "new", [f for f in DELTA_QUEST_FIELDS if (id_, f) in h]
        else:
            fields = [
                f for f in DELTA_QUEST_FIELDS
                if (b.get((id_, f)) or {}).get("hash") != (h.get((id_, f)) or {}).get("hash")
            ]
            if not fields:
                continue
            change = "changed"
        rows.append({
            "id": id_, "title": (h.get((id_, "title")) or {}).get("en"), "change": change, "fields": fields,
            "progress_src": (h.get((id_, "progress")) or {}).get("src"),
            "completion_src": (h.get((id_, "completion")) or {}).get("src"),
        })
    return rows


def unseen_since(
    english: dict[str, list[dict]], lines: dict[str, list[dict]], src: str
) -> dict[str, tuple[int, int, int]]:
    """Per type: (English lines, lines NOT provided by `src`, of those the ones whose Japanese ships).

    After an import merged with `union`, a line this source provided carries its `src@build` stamp
    and a line it did not keeps the older one, so "not stamped `src`" is exactly "the client behind `src`
    has never had this id". The third number is the one that matters when deciding whether to drop them:
    an English line no translation uses costs nothing to keep, while one whose Japanese ships is content the
    player would lose. `src` matches on the part before `@`, or on the whole `src@build` when one is given.
    """
    def provided(line: dict) -> bool:
        stamp = str(line.get("src", ""))
        return stamp == src if "@" in src else stamp.split("@", 1)[0] == src

    status = {
        t: {(ln["id"], ln.get("field")): ln.get("status") for ln in rows} for t, rows in lines.items()
    }
    out: dict[str, tuple[int, int, int]] = {}
    for type_, rows in sorted(english.items()):
        # a type this source never provides at all (quest, gossip, book: those come from pfQuest, VMaNGOS
        # and the quest cache) would otherwise read as "100% unseen", which is true and useless. The question
        # is only meaningful where the source is one of the type's providers.
        if not any(provided(ln) for ln in rows):
            continue
        unseen = [ln for ln in rows if not provided(ln)]
        shipping = sum(
            1
            for ln in unseen
            if status.get(type_, {}).get((ln["id"], ln.get("field"))) in SHIPPED
        )
        out[type_] = (len(rows), len(unseen), shipping)
    return out
