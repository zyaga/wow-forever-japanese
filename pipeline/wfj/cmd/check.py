"""wfj check [--report]: assign status/reasons/checks/english to every line in data/.

Pure rules (core/status.decide) over the committed data and its English; idempotent and deterministic.
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from typing import Any

from wfj.core import align, report
from wfj.core.align import load_allowlist
from wfj.core.dedupe import canonical_conflicts, conflict_order, promote
from wfj.core.model import validate_line
from wfj.core.normalize import normalize_for, normalize_v1
from wfj.core.status import DOTS, Scope, decide
from wfj.io.jsonl_store import Store
from wfj.paths import allowlist_path, data_root

TYPES = ("quest", "item", "spell", "ui", "gossip", "book", "objective", "area")
# A gossip line is keyed by the hash of its English (ADR-005): the key is its English hash and the only
# English `check` consults (ADR-017). Changed English is a different key: never stale.
GOSSIP_SRC = "gossip-key@normalize_v1"
# English from player collector dumps is stored but not yet consulted: until a re-check policy
# decides how it may change hashes and scopes, `check` / `validate` behave exactly as if no dump were
# imported (ADR-013).
UNCONSULTED_SOURCES = ("collector",)


# pfQuest never provides (ADR-019) these fields, so a baseline recorded from a pfQuest line on one of
# them is the description's hash, not this field's English. The first check against the field's own English
# re-baselines it instead of calling it stale.
OWN_ENGLISH_LATER = ("progress", "completion")


def build_scopes(english: Store, type_: str) -> dict[int | str, Scope]:
    """Scopes hold normalize_v1 English (markup and `$B` gone), so a count after a `$B` is still a
    number to the checks; the per-field hash comes from the store and is never recomputed. Lines from
    UNCONSULTED_SOURCES are skipped."""
    scopes: dict[int | str, Scope] = {}
    for ln in english.load(type_):
        if str(ln["src"]).split("@", 1)[0] in UNCONSULTED_SOURCES:
            continue
        sc = scopes.setdefault(ln["id"], Scope(kind=type_, src=ln["src"]))
        sc.fields[ln["field"]] = normalize_for(type_, ln["en"])
        sc.raw[ln["field"]] = ln["en"]
        sc.hashes[ln["field"]] = ln["hash"]
        sc.srcs[ln["field"]] = ln["src"]
        if DOTS.fullmatch(ln["en"]):
            sc.dotted = sc.dotted | {ln["field"]}
    return scopes


def gossip_scopes(
    lines: list[dict[str, Any]], dotted: set[str] | frozenset[str] = frozenset()
) -> dict[int | str, Scope]:
    """One scope per gossip key: the key is the English hash. It carries no English text, so only the rules
    that need none apply (Japanese, hand-written before machine). `dotted`: the keys whose English
    is only dots, which may be translated as only dots."""
    return {
        ln["id"]: Scope(
            kind="gossip",
            fields={"key": ln["id"]},
            hashes={"text": ln["id"]},
            src=GOSSIP_SRC,
            dotted=frozenset({"text"}) if ln["id"] in dotted else frozenset(),
        )
        for ln in lines
    }


def scopes_for(english: Store, store: Store, type_: str) -> dict[int | str, Scope]:
    """The scopes `check` and `validate` judge `type_` against."""
    if type_ == "gossip":
        dotted = {ln["id"] for ln in english.load("gossip") if DOTS.fullmatch(ln["en"])}
        return gossip_scopes(store.load(type_), dotted)
    return build_scopes(english, type_)


def english_ref(scope: Scope, field_name: str) -> tuple[str | None, str | None, str | None]:
    """The English a line is checked against, as (hash, src, of), from the store (never recomputed): the
    line's own field when an English source has it (quest progress / completion: VMaNGOS), else the
    quest description, else the item/spell name, else the joined scope (quests whose pfQuest entry has only a
    title). `src` is the source of the field actually used; `of` names it when it is not the line's own field
    ("description" / "name" / "joined"), else None. A change there marks the line stale. A quest scope with no
    title / objectives / description English (only VMaNGOS progress / completion) has nothing to join:
    (None, None, None)."""
    for f in (field_name, "description", "name"):
        if f in scope.hashes:
            return scope.hashes[f], scope.srcs.get(f, scope.src), (None if f == field_name else f)
    from wfj.core.hashing import key as hash_key

    # The joined fallback stays the hash of the title / objectives / description English it has always been:
    # progress / completion English arriving must not make every such line stale.
    joined = {f: v for f, v in scope.fields.items() if f not in OWN_ENGLISH_LATER}
    if not joined:
        return None, None, None
    first = next(iter(joined))
    return hash_key(normalize_v1("\n".join(joined.values()))), scope.srcs.get(first, scope.src), "joined"


def current_baseline(
    scope: Scope, field_name: str, includes: dict[str, str] | None = None
) -> dict[str, Any] | None:
    """The `english` a line checked fresh against `scope` records: {hash, src} of the English it is judged
    against, plus `of` for a quest / item / spell line judged against another field. For a quest (ADR-019)
    that field's hash is another field's, so generate ships no h1 for it and the addon's live check
    never compares this field's English with it; an item / spell line records `of: name` too, so a
    rename is never mistaken for changed tooltip text. None when there is no English to judge it against.
    Shared by `check` and `import draft --reverify`: a re-verified line records what check would."""
    cur, src, of = english_ref(scope, field_name)
    if cur is None:
        return None
    base = {"hash": cur, "src": src}
    if of and scope.kind in ("quest", "item", "spell"):
        base["of"] = of
    if includes:  # the spells this template splices in, `<id>.<field>` → their English hash
        base["includes"] = dict(includes)
    return base


class Included:
    """The spells an item / spell template splices in (`$@spelldesc<id>` …, ADR-043) and their current
    English hashes, from the spell English store. A spell the tables lack hashes as "": its return (or loss)
    changes what the player reads."""

    def __init__(self, english: Store) -> None:
        lines = english.load("spell")
        self.raw = {(ln["id"], ln["field"]): ln["en"] for ln in lines}
        self.hash = {(ln["id"], ln["field"]): ln["hash"] for ln in lines}

    def of(self, scope: Scope | None, field_name: str) -> dict[str, str] | None:
        if scope is None or scope.kind not in ("item", "spell"):
            return None
        en = scope.raw.get(field_name)
        if not en or "$@" not in en:
            return None
        # a name-list tail's `$@spellname` chain is copied from the live line, never translated: only
        # the head's inclusions change what the Japanese says
        keys = align.included_spells(align.split_tail(en)[0], self.raw)
        return {f"{sid}.{f}": self.hash.get((sid, f), "") for sid, f in keys} or None


def english_hash(scope: Scope, field_name: str) -> str | None:
    return english_ref(scope, field_name)[0]


def fallback_baseline(line: dict[str, Any], scope: Scope) -> bool:
    """A baseline recorded against other English than the line's own, re-judged fresh once its own arrives:
    quest progress / completion against a pfQuest field, and an item / spell tooltip line
    against the name, before tooltip English existed."""
    prior = line.get("english") or {}
    if scope.kind in ("item", "spell"):
        # A baseline taken from the name (`of: name`, or, from before `of` was recorded, equal to the current
        # name hash) says nothing about the tooltip text: a rename never makes the line stale, and the line's
        # own tooltip English, once it exists, replaces it fresh.
        if line["field"] == "name" or prior.get("hash") is None:
            return False
        return prior.get("of") == "name" or (
            "of" not in prior
            and prior.get("hash") == scope.hashes.get("name")
            and line["field"] in scope.hashes
        )
    return (
        line["field"] in OWN_ENGLISH_LATER
        and line["field"] in scope.hashes
        and str(prior.get("src", "")).startswith("pfquest@")
    )


def canonical_first(line: dict[str, Any]) -> int:
    """A line with no English has no rules to pick a winner, so its variants go in the stored conflict
    order (hand-written first, `conflict_order`) whatever the history: an incremental `check` after the
    served step drops its English and a full rebuild then store the same line. → the first variant's index"""
    own = {k: line[k] for k in ("ja", "provenance", "extra", "ruling") if line.get(k) is not None}
    cands = [own, *(line.get("conflicts") or [])]
    return min(range(len(cands)), key=lambda i: conflict_order(cands[i]))


def check_type(
    lines: list[dict[str, Any]],
    scopes: dict[int | str, Scope],
    allowlist: set[str],
    included: Included | None = None,
) -> list[dict[str, Any]]:
    out = []
    for line in lines:
        scope = scopes.get(line["id"])
        cur = english_ref(scope, line["field"])[0] if scope and not scope.empty else None
        if cur is None:
            scope = None  # no English this line can be checked against: no_english_id
        if scope and fallback_baseline(line, scope):
            # judged fresh against its own English (ADR-019); a copy, so the stored line is left as it is
            line = {**line, "english": None}  # noqa: PLW2901
        # an included spell's English changed since the line was checked (a line checked before its
        # baseline recorded `includes` is judged by its own English only, and records them now)
        includes = included.of(scope, line["field"]) if included is not None else None
        prior_includes = (line.get("english") or {}).get("includes")
        # a line that no longer includes anything changed its own English (its hash says so), or, for a
        # name-list tail, never had includes to track
        changed = bool(prior_includes) and includes is not None and prior_includes != includes
        d = decide(line, scope, allowlist, cur, changed)
        winner = d.winner if scope is not None else canonical_first(line)
        new = promote(line, winner) if winner else dict(line)
        if new.get("conflicts"):
            # one stored order whatever the history: `make data` on a clean checkout is a fixed point
            new["conflicts"] = canonical_conflicts(new["conflicts"])
        new["status"] = d.status
        new["reasons"] = d.reasons
        new["checks"] = d.checks
        if d.status == "stale":
            # Sticky: keep the hash the translation was checked against, so the line stays stale on
            # every rerun until an audit pass re-verifies it and writes the current hash (ADR-003).
            new["english"] = dict(line["english"])
        elif scope is None:
            # no English now (the id left the Forever tables, or never had any): keep the baseline the
            # translation was last checked against, so English that comes back reworded makes it stale,
            # not fresh
            new["english"] = dict(line["english"]) if line.get("english") else None
        else:
            new["english"] = current_baseline(scope, line["field"], includes)
        out.append(new)
    return out


def validate_or_die(type_: str, lines: list[dict[str, Any]]) -> None:
    """Never resolve silently: a malformed `ruling` (or any invalid line) aborts the run."""
    problems = [(ln["id"], ln["field"], p) for ln in lines for p in validate_line(type_, ln)]
    if problems:
        for id_, field_name, p in problems[:20]:
            print(f"check: {type_} {id_}/{field_name}: {p}", file=sys.stderr)
        raise SystemExit(f"check: {len(problems)} invalid line(s) in data/{type_}; fix them before checking")


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj check")
    p.add_argument("--report", action="store_true")
    a = p.parse_args(list(argv))
    root = data_root()
    store, english = Store(root), Store(root, english=True)
    allowlist = load_allowlist(allowlist_path(root).read_text(encoding="utf-8"))
    result: dict[str, list[dict[str, Any]]] = {}
    vanilla: set[int] = set()
    included = Included(english)
    for type_ in TYPES:
        scopes = scopes_for(english, store, type_)
        if type_ == "quest":
            vanilla = {i for i, sc in scopes.items() if "description" in sc.fields}
        lines = store.load(type_)
        if lines and not scopes:
            # An absent or partial data/english/ would reject the whole corpus as no_english_id and
            # rewrite every shard; refuse rather than produce a plausible-looking wrong commit.
            raise SystemExit(
                f"check: data/english/{type_} is empty but data/{type_} is not; run `make import` first"
            )
        validate_or_die(type_, lines)
        result[type_] = check_type(lines, scopes, allowlist, included)
        store.save(type_, result[type_])
    h = report.headline(result, vanilla)
    if a.report:
        print(report.render(report.tally(result), h))
    else:
        print("check: " + "; ".join(f"{k}={v}" for k, v in h.items()))
    return 0


def vanilla_ids(english: Store) -> set[int]:
    return {i for i, sc in build_scopes(english, "quest").items() if "description" in sc.fields}
