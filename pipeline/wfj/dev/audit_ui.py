"""The UI side of `audit_batch`: shipped UI strings cut as (English, Japanese) pairs with their context, the
rules a UI verdict follows, and the draft the verdicts become.

UI lines are keyed by string key, but the addon finds a string on screen by its English, so every key that
shares an English ships one Japanese (validate's one-English-one-Japanese rule), except the keys in
`UIStrings.OWN`, which a widget asks for by name (ADR-037). The audit reads each (English, Japanese) pair
once and a fix applies to all its keys. A row:

    {"type": "ui", "id": <first key>, "field": "text", "keys": [...], "surfaces": [...], "own": bool,
     "ja", "ja_hash", "en", "en_width", "ja_width", "warn": [...], "siblings": [...]}

`surfaces` are the windows `pipeline/ui_inventory.txt` lists for any of the keys; empty when none is listed
(the key's callers build it at run time). `warn` is `ui_lint`'s width and register warnings. An owned key is
its own row. `siblings` are the keys of other rows the addon finds by the same English (it differs only in
colour codes or markup, `validate.ui_group`): a fix to this row is made to them too, or the lines disagree.

A UI verdict: `{"type", "id", "field", "ja_hash", "verdict", "context", "kind"?, "problem"?, "ja"?, "own"?,
"unsure"?}`.

- `context` is `screen` when the row has surfaces, `key` when it has none (judged from the key name, its
  neighbours and the English).
- `match`: the Japanese reads right. With `context: key`, `unsure: true` and a `problem` mark a line whose
  English has two senses and whose Japanese could not be checked against a screen.
- `correct`: `ja` is the new Japanese for every key of the row.
- `redraft`: the line is written again later, from its English; no `ja`.
- `split`: one Japanese cannot read right on every screen of the row. `own` maps the keys that need their
  own Japanese (a subset of `keys`) to it; `ja` is the Japanese for the others, absent when `own` names
  every key. A split key ships only once it is in `UIStrings.OWN` and its widget names it, and the addon owns
  only plain strings, so a split on a template (a `%` argument) is refused, as is one that changes nothing.

A `correct` / `redraft` / `split` names a `kind` and a `problem`. No UI verdict carries `words`: changed lines
get their word lists from the readings export after the import.
"""

from __future__ import annotations

import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from wfj.cmd.validate import ui_group, ui_own
from wfj.core import readings, specifiers
from wfj.core.report import SHIPPED
from wfj.dev import ui_lint
from wfj.dev.ui_inventory import read_inventory
from wfj.io.jsonl_store import Store

UI_KINDS = (
    "context_sense",  # the Japanese takes a sense of the English the screen does not use
    "too_long",  # longer than the widget holds, or longer in kind than the English
    "register",  # a polite sentence on a label, or a form unlike its siblings
    "inconsistent",  # disagrees with the glossary or a sibling key (a tab and its window title)
    "format",  # a specifier, colour code or line break misplaced in a way the checks cannot see
)
CONTEXTS = ("screen", "key")


# ---- cut ------------------------------------------------------------------------------------------


def ui_rows(root: Path, addon: Path | None = None, inventory: dict[str, set[str]] | None = None
            ) -> tuple[list[dict[str, Any]], int]:
    """(one row per shipped (English, Japanese) pair, shipped lines left out for having no English). The addon
    and the inventory default to the checkout `root` (the data folder) belongs to."""
    english = ui_lint.english_ui(root)
    if inventory is None:
        inventory = read_inventory(root.parent / "pipeline" / "ui_inventory.txt")
    own = ui_own(addon or root.parent / "addon" / "WoWForeverJapanese")
    groups: dict[tuple[str, str, str | None], list[str]] = defaultdict(list)
    no_english = 0
    for ln in Store(root).load("ui"):
        if ln["status"] not in SHIPPED:
            continue
        if not english.get(ln["id"], "").strip():
            no_english += 1
            continue
        # an owned key is its own row: its Japanese belongs to its screen, not to the others sharing the pair
        groups[(english[ln["id"]], ln["ja"], ln["id"] if ln["id"] in own else None)].append(ln["id"])
    rows = [_row(en, ja, owner is not None, sorted(keys), inventory)
            for (en, ja, owner), keys in groups.items()]
    _add_siblings(rows, english, own)
    return sorted(rows, key=lambda r: r["id"]), no_english


def _add_siblings(rows: list[dict[str, Any]], english: dict[str, str], own: set[str]) -> None:
    by_group: dict[str, set[str]] = defaultdict(set)
    group_of: dict[str, str] = {}
    for row in rows:
        for k in row["keys"]:
            if k in own:
                continue
            try:
                group_of[k] = ui_group(k, english[k], row["ja"])[0]
            except ValueError:
                continue
            by_group[group_of[k]].add(k)
    for row in rows:
        mates = set().union(*(by_group[group_of[k]] for k in row["keys"] if k in group_of))
        row["siblings"] = sorted(mates - set(row["keys"]))


def _row(en: str, ja: str, is_own: bool, keys: list[str], inventory: dict[str, set[str]]) -> dict[str, Any]:
    surfaces = sorted(set().union(*(inventory.get(k, set()) for k in keys)))
    return {"type": "ui", "id": keys[0], "field": "text", "keys": keys, "surfaces": surfaces, "own": is_own,
            "ja": ja, "ja_hash": readings.ja_hash(ja), "en": en,
            "en_width": ui_lint.display_width(en), "ja_width": ui_lint.display_width(ja),
            "warn": _warnings(en, ja, surfaces, keys)}


# ---- check ----------------------------------------------------------------------------------------


def problems(part: dict[str, Any], v: dict[str, Any], kinds: tuple[str, ...]) -> list[str]:
    """Problems with one UI verdict (its keys and verdict already match the part row)."""
    verdict = v["verdict"]
    p = _context_problems(part, v)
    if "words" in v:
        p.append("a UI verdict carries no `words` (the readings export writes them after the import)")
    if verdict != "match":
        if v.get("kind") not in kinds:
            p.append(f"kind must be one of {kinds}")
        if not str(v.get("problem", "")).strip():
            p.append(f"a {verdict} names its problem")
    if verdict == "match" and v.get("ja") not in (None, part["ja"]):
        p.append("a match carries no new `ja`")
    if verdict == "correct":
        p += _new_ja_problems(part, v.get("ja"), "a correct")
    if verdict == "redraft" and v.get("ja") not in (None, part["ja"]):
        p.append("a redraft carries no `ja` (the redraft batch writes it)")
    if verdict == "split":
        p += _split_problems(part, v)
    if verdict != "split" and "own" in v:
        p.append("only a split carries `own`")
    return p


def _context_problems(part: dict[str, Any], v: dict[str, Any]) -> list[str]:
    ctx = v.get("context")
    if ctx not in CONTEXTS:
        return [f"context must be one of {CONTEXTS}"]
    p: list[str] = []
    want = "screen" if part.get("surfaces") else "key"
    if ctx != want:
        p.append(f"context is `{want}` for this row ({'it has' if part.get('surfaces') else 'no'} surfaces)")
    if v.get("unsure"):
        if v["verdict"] != "match" or ctx != "key":
            p.append("`unsure` goes only on a match judged from the key")
        elif not str(v.get("problem", "")).strip():
            p.append("an unsure match says why in `problem`")
    return p


def _new_ja_problems(part: dict[str, Any], ja: Any, what: str) -> list[str]:
    if not isinstance(ja, str) or not ja.strip():
        return [f"{what} carries the new `ja`"]
    if ja == part["ja"]:
        return [f"{what}'s `ja` is unchanged"]
    problems = [f"{what}'s `ja` fails {r}" for r in ui_lint.failures(part["en"], ja)]
    for key in part.get("keys", [part["id"]]):  # a numbered row's Japanese must fit its English slots
        try:
            ui_group(key, part["en"], ja)
        except ValueError as err:
            problems.append(f"{what}'s `ja` fails numbered:{err}")
            break
    return problems


def _split_problems(part: dict[str, Any], v: dict[str, Any]) -> list[str]:
    own = v.get("own")
    if not isinstance(own, dict) or not own:
        return ["a split names its keys in `own` ({key: ja})"]
    if _is_template(part["en"]):
        return ["a split needs a plain string: the addon does not own a template (a `%` argument)"]
    if all(ja == part["ja"] for ja in own.values()) and v.get("ja") in (None, part["ja"]):
        return ["a split that changes no key's Japanese is a match"]
    p = [f"`own` key {k} is not one of the row's keys" for k in own if k not in part["keys"]]
    for k, ja in own.items():
        p += _new_ja_problems(part, ja, f"`own` {k}") if ja != part["ja"] else []
    if set(own) >= set(part["keys"]):
        if "ja" in v:
            p.append("a split whose `own` names every key carries no `ja`")
    elif not isinstance(v.get("ja"), str) or not v["ja"].strip():
        p.append("a split carries `ja` for the keys `own` does not name")
    else:
        p += [f"a split's `ja` fails {r}" for r in ui_lint.failures(part["en"], v["ja"])]
    return p


# ---- report ---------------------------------------------------------------------------------------


def outputs(pairs: list[tuple[dict[str, Any], dict[str, Any]]]) -> dict[str, str]:
    """The files `report` writes for UI rows: the draft of every changed key, the Japanese each of those
    keys was judged against (`ui_lint --base` refuses a key that has moved since), the keys to redraft and the
    split keys."""
    draft: list[str] = []
    base: list[str] = []
    redraft: list[str] = []
    split: list[str] = []
    for row, v in pairs:
        changed = _changed_keys(row, v)
        draft += [_draft_line(k, ja) for k, ja in changed]
        base += [_json({"id": k, "ja_hash": row["ja_hash"]}) for k, _ in changed]
        if v["verdict"] == "redraft":
            redraft += row["keys"]
        elif v["verdict"] == "split":
            split += [_json({"id": k, "en": row["en"], "ja": ja, "surfaces": row["surfaces"]})
                      for k, ja in v["own"].items()]
    return {"audit.ui-draft.jsonl": "".join(draft), "audit.ui-base.jsonl": "".join(base),
            "audit.ui-redraft.ids": _lines(redraft), "audit.ui-split.jsonl": "".join(split)}


def _changed_keys(row: dict[str, Any], v: dict[str, Any]) -> list[tuple[str, str]]:
    if v["verdict"] == "correct":
        return [(k, v["ja"]) for k in row["keys"]]
    if v["verdict"] == "split":
        pairs = [(k, v["own"].get(k, v.get("ja"))) for k in row["keys"]]
        return [(k, ja) for k, ja in pairs if ja != row["ja"]]
    return []


def _json(obj: dict[str, Any]) -> str:
    return json.dumps(obj, ensure_ascii=False) + "\n"


def _warnings(en: str, ja: str, surfaces: list[str], keys: list[str]) -> list[str]:
    """`ui_lint`'s warnings for the pair: those of the first key that is a short label (an `ERR_*` key in
    the pair takes none of its own)."""
    return next((w for k in keys if (w := ui_lint.warnings(en, ja, set(surfaces), k))), [])


def _is_template(en: str) -> bool:
    try:
        return "%" in en or bool(specifiers.parse(en))
    except ValueError:
        return True


def _draft_line(key: str, ja: str) -> str:
    return _json({"id": key, "field": "text", "ja": ja})


def _lines(items: list[str]) -> str:
    return "".join(f"{x}\n" for x in items)


def render(pairs: list[tuple[dict[str, Any], dict[str, Any]]]) -> str:
    """Counts for the UI rows: by how they were judged, by surface, and the unsure rows."""
    ctx: Counter[str] = Counter()
    by_surface: dict[str, Counter[str]] = defaultdict(Counter)
    unsure: list[str] = []
    for row, v in pairs:
        ctx[v["context"]] += 1
        for s in row["surfaces"] or ["(no screen)"]:
            by_surface[s][v["verdict"]] += 1
        if v.get("unsure"):
            keys = len(row["keys"])
            unsure.append(f"- {row['id']} ({keys} keys): {row['en']} → {row['ja']}: {v['problem']}")
    out = ["", "## UI", "", f"Judged by screen {ctx['screen']:,} · by key {ctx['key']:,}", "",
           "| Surface | Pairs | Match | Correct | Redraft | Split |", "|---|---|---|---|---|---|"]
    for s, c in sorted(by_surface.items()):
        out.append(f"| {s} | {sum(c.values()):,} | {c['match']:,} | {c['correct']:,} | {c['redraft']:,} | "
                   f"{c['split']:,} |")
    kinds = Counter((v["kind"], v["verdict"]) for _, v in pairs if v["verdict"] != "match")
    out += ["", "| Kind | Correct | Redraft | Split |", "|---|---|---|---|"]
    for k in sorted({k for k, _ in kinds}):
        c = [kinds[(k, verdict)] for verdict in ("correct", "redraft", "split")]
        out.append(f"| {k} | {c[0]:,} | {c[1]:,} | {c[2]:,} |")
    out += ["", f"Unsure ({len(unsure)}):", *unsure]
    return "\n".join(out) + "\n"
