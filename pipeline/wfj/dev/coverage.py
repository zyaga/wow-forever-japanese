"""How much of the game ships in Japanese: `docs/operations/coverage.md`, generated.

Measured from the English the Forever client serves (`data/english/`), not from the Japanese store
(`wfj stats` counts every stored line, including post-Vanilla quests the client never shows). Spells are
the player-visible set (`pipeline/visible_spells.txt`). A line with nothing to translate counts as done: a
name-only objective / area text (`pipeline/objective_names.txt` / `area_names.txt`), a placeholder quest, a
picture-only book page. Word lists (readings with meanings) are counted against the lines that can carry
one (`readings.annotatable`, not an HTML book page).

    python -m wfj.dev.coverage [--out ../docs/operations/coverage.md]    (from pipeline/)
"""

from __future__ import annotations

import argparse
import re
import subprocess
from collections import Counter
from collections.abc import Sequence
from datetime import date
from pathlib import Path
from typing import Any

from wfj.core import readings
from wfj.dev.translate_batch import AREA_NAMES, OBJECTIVE_NAMES, objective_names
from wfj.emit.lua_writer import shipped
from wfj.io.jsonl_store import Store
from wfj.io.wdb import PLACEHOLDER_TITLE
from wfj.paths import data_root

# the fields a player reads per type (quest `area` is its own type; item `name` stays English)
SURFACE_FIELDS: dict[str, tuple[str, ...]] = {
    "quest": ("title", "objectives", "description", "progress", "completion"),
    "gossip": ("text",),
    "book": ("text",),
    "objective": ("text",),
    "area": ("text",),
    "item": ("description",),
    "spell": ("description", "aura"),
    "ui": ("text",),
}
LABELS = {
    "quest": "Quest text",
    "gossip": "NPC dialogue (gossip, speech)",
    "book": "Book / letter pages",
    "objective": "Quest objective lines",
    "area": "Exploration / event objectives",
    "item": "Item descriptions",
    "spell": "Spell tooltips + auras (player-visible)",
    "ui": "Interface strings",
}
NAMES_LISTS = {"objective": OBJECTIVE_NAMES, "area": AREA_NAMES}
_ID = re.compile(r"(\d+)\s*$")
_TAG = re.compile(r"<[^>]*>")
_WORD = re.compile(r"[A-Za-z]{2,}")


def nothing_to_translate(type_: str, en: str, title: str | None) -> str | None:
    """Why a line has nothing to translate, or None: a placeholder quest (`<UNUSED>`, `<NYI>`, `REUSE`, never
    drafted), a book page that is "Missing Text", only pictures / markup, or a cipher."""
    if type_ == "quest" and title is not None and PLACEHOLDER_TITLE.search(title):
        return "placeholder quest (never shown)"
    if type_ == "book":
        text = _TAG.sub(" ", en)
        if text.strip().lower() in ("missing text", ""):
            return "Missing Text / picture-only page"
        if not _WORD.search(text) or re.fullmatch(r"[\s01]+", text):
            return "picture-only or cipher page"
    return None


def visible_spells(repo: Path) -> set[int]:
    """The ids of `pipeline/visible_spells.txt` (`<sources> <id>` per line, `#` comments)."""
    out: set[int] = set()
    path = repo / "pipeline" / "visible_spells.txt"
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("#"):
            continue
        m = _ID.search(raw)
        if m:
            out.add(int(m.group(1)))
    return out


def _why(line: dict[str, Any] | None) -> str:
    if line is None:
        return "no Japanese yet"
    reasons = line.get("reasons") or []
    return f"{line['status']}: {reasons[0]}" if reasons else line["status"]


def measure(root: Path) -> dict[str, Any]:
    """→ {"types": {type: {...}}, "readings": {type: {...}}} over the store at `root` (the repo's data/)."""
    repo = root.parent
    store, english = Store(root), Store(root, english=True)
    visible = visible_spells(repo)
    types: dict[str, Any] = {}
    for type_, fields in SURFACE_FIELDS.items():
        en = [ln for ln in english.load(type_) if ln["field"] in fields]
        if type_ == "spell":
            en = [ln for ln in en if ln["id"] in visible]
        names = set(objective_names(repo, NAMES_LISTS[type_])) if type_ in NAMES_LISTS else set()
        ja = {(ln["id"], ln["field"]): ln for ln in store.load(type_)}
        titles = ({ln["id"]: ln["en"] for ln in english.load("quest") if ln["field"] == "title"}
                  if type_ == "quest" else {})
        done = named = 0
        nothing: Counter[str] = Counter()
        missing: Counter[str] = Counter()
        for ln in en:
            j = ja.get((ln["id"], ln["field"]))
            if j is not None and shipped(j):
                done += 1
            elif ln["id"] in names:
                named += 1
            elif why := nothing_to_translate(type_, ln["en"], titles.get(ln["id"])):
                nothing[why] += 1
            else:
                src = str(ln.get("src", "")).split("@")[0]
                wait = ": English still from wago (Classic Era); waits for the Forever re-pull" if (
                    type_ in ("item", "spell") and src == "wago") else ""
                missing[_why(j) + wait] += 1
        kept = sum(
            1 for j in ja.values()
            if shipped(j) and isinstance(j.get("ruling"), dict) and j["ruling"].get("ruling") == "accept"
        )
        types[type_] = {"english": len(en), "shipped": done, "names": named + sum(nothing.values()),
                        "kept_english": kept, "missing": dict(missing.most_common()),
                        "nothing": dict(nothing.most_common())}
    words: dict[str, Any] = {}
    rstore = Store(root / "reading")
    for type_ in readings.TYPES:
        japanese = readings.shipped_japanese(store.load(type_))
        result = readings.check(type_, rstore.load(type_), japanese)
        covered = {(r["id"], r["field"]) for r in result["current"]}
        can = {k for k, ja in japanese.items()
               if readings.annotatable(ja) and not readings.html_page(type_, ja) and "|" not in ja}
        n_words = sum(len(r["words"]) for r in result["current"])
        meant = sum(1 for r in result["current"] for w in r["words"] if len(w) == 5)
        words[type_] = {"lines": len(can), "with_words": len(can & covered), "stale": len(result["stale"]),
                        "words": n_words, "with_meaning": meant}
    return {"types": types, "readings": words}


def _pct(a: int, b: int) -> str:
    return f"{100 * a / b:.1f}%" if b else "-"


def render(m: dict[str, Any], stamp: str) -> str:
    out = [
        "# Coverage: how much of the game ships in Japanese",
        "",
        f"> **Generated** by `make coverage` (`pipeline/wfj/dev/coverage.py`) on {stamp}.",
        "> Do not edit by hand: every pull request that changes `data/` re-runs it. Measured from",
        "> the English the Forever client serves; spells are the player-visible set; a line that is only a",
        "> name, a placeholder quest or a picture-only page counts as done (nothing to translate).",
        "",
        "## Translation",
        "",
        "| Surface | English lines | Ship Japanese | Nothing to translate | Done | Not yet |",
        "|---|---|---|---|---|---|",
    ]
    total_en = total_done = 0
    for type_, t in m["types"].items():
        done = t["shipped"] + t["names"]
        total_en += t["english"]
        total_done += done
        out.append(f"| {LABELS[type_]} | {t['english']:,} | {t['shipped']:,} | {t['names']:,} | "
                   f"{_pct(done, t['english'])} | {t['english'] - done:,} |")
    out.append(f"| **All** | **{total_en:,}** | | | **{_pct(total_done, total_en)}** | "
               f"**{total_en - total_done:,}** |")
    out += ["",
            "Lines shipped as their English under a maintainer ruling (`ruling: accept`, for names, classes,",
            "professions, internal strings): " + ", ".join(
                f"{type_} {t['kept_english']:,}"
                for type_, t in m["types"].items() if t["kept_english"]) + ".",
            "", "### Nothing to translate (counted as done)", "",
            "| Surface | Why | Lines |", "|---|---|---|"]
    out += [f"| {LABELS[t]} | name only (`{NAMES_LISTS[t]}`) | "
            f"{m['types'][t]['names'] - sum(m['types'][t]['nothing'].values()):,} |"
            for t in NAMES_LISTS if m["types"][t]["names"]]
    out += [f"| {LABELS[type_]} | {why} | {n:,} |" for type_, t in m["types"].items()
            for why, n in t["nothing"].items()]
    out += ["", "### What is not done yet", ""]
    rows = [(type_, why, n) for type_, t in m["types"].items() for why, n in t["missing"].items()]
    if rows:
        out += ["| Surface | Why | Lines |", "|---|---|---|"]
        out += [f"| {LABELS[type_]} | {why} | {n:,} |" for type_, why, n in rows]
    else:
        out.append("Nothing.")
    out += ["", "## Word cards (readings with meanings)", "",
            "| Type | Lines that can carry a word list | With one | Done | Stale | Words | With a meaning |",
            "|---|---|---|---|---|---|---|"]
    for type_, r in m["readings"].items():
        done = _pct(r["with_words"], r["lines"])
        out.append(f"| {type_} | {r['lines']:,} | {r['with_words']:,} | {done} | "
                   f"{r['stale']:,} | {r['words']:,} | {_pct(r['with_meaning'], r['words'])} |")
    out += ["", "Item, spell, objective and area text take no word cards; HTML book pages",
            "and lines holding a `|` escape are not counted.", ""]
    return "\n".join(out)


def _stamp(repo: Path) -> str:
    try:
        sha = subprocess.run(["git", "-C", str(repo), "rev-parse", "--short", "HEAD"], capture_output=True,
                             text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        sha = "unknown"
    return f"{date.today().isoformat()} at commit `{sha}`"


def main(argv: Sequence[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wfj.dev.coverage", description=__doc__.split("\n", 1)[0])
    ap.add_argument("--out", type=Path, help="write the markdown here (default: print it)")
    a = ap.parse_args(argv)
    root = data_root()
    text = render(measure(root), _stamp(root.parent))
    if a.out:
        a.out.write_text(text, encoding="utf-8")
        print(f"coverage: wrote {a.out}")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
