"""How much of the game ships in Japanese: `docs/operations/coverage.md`, generated.

Measured from the English the Forever client serves (`data/english/`), not from the Japanese store
(`wfj stats` counts every stored line, including post-Vanilla quests the client never shows), and never from a
list of what a player is likely to see: every served line of a surface counts. A line with nothing to
translate counts as done: a name-only objective / area text (`pipeline/objective_names.txt` /
`area_names.txt`), a placeholder quest, a picture-only book page. Word lists (readings with meanings) are
counted against the lines that can carry one (`readings.annotatable`, not an HTML book page). The voice
section counts every line the voice can read: in step with its audio, stale, not made, and each silent line
by reason.

The report also counts the served-text inventory (`pipeline/served_columns.txt` with
`pipeline/served_dispositions.txt`): every text column the client ships, by disposition, so a column left out
is a counted row with its reason.

A served line that has neither shipped Japanese nor a stated reason (a name list, nothing to translate,
English still waiting on the Forever tables, a status with its reason) is a gap: `gaps` counts them and
`tests/python/test_coverage.py` fails on any.

    python -m wfj.dev.coverage [--out ../docs/operations/coverage.md] [--build <forever build>]
    (from pipeline/)
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
from wfj.dev import counts as readme_counts
from wfj.dev import served_dispositions
from wfj.dev.served_columns import inventory_build, read_inventory
from wfj.dev.translate_batch import AREA_NAMES, OBJECTIVE_NAMES, has_prose, objective_names, undraftable
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
    "spell": "Spell tooltips + auras",
    "ui": "Interface strings",
}
NAMES_LISTS = {"objective": OBJECTIVE_NAMES, "area": AREA_NAMES}
_TAG = re.compile(r"<[^>]*>")
_WORD = re.compile(r"[A-Za-z]{2,}")


def nothing_to_translate(type_: str, en: str, title: str | None, field: str = "") -> str | None:
    """Why a line has nothing to translate, or None: a placeholder quest (`<UNUSED>`, `<NYI>`, `REUSE`, never
    drafted), a book page that is "Missing Text", only pictures / markup, or a cipher, and a quest or book
    line
    that is a bare label (`has_prose`: no lower-case word, token or sentence punctuation: a name and a colon,
    a name and two years, "Log"). A quest title is never a bare label: titles are written in title case."""
    if type_ == "quest" and title is not None and PLACEHOLDER_TITLE.search(title):
        return "placeholder quest (never shown)"
    if type_ == "book":
        text = _TAG.sub(" ", en)
        if text.strip().lower() in ("missing text", ""):
            return "Missing Text / picture-only page"
        if not _WORD.search(text) or re.fullmatch(r"[\s01]+", text) or re.fullmatch(r"[\sOo]+", text):
            return "picture-only or cipher page"
        if not has_prose(text):
            return "a bare label: names and numbers only (ships as the English)"
    if type_ == "quest" and field != "title" and not has_prose(en):
        return "a bare label: a name or a one-word placeholder (ships as the English)"
    return None


UI_EXCLUDED = "left out with its reason in `pipeline/ui_exclusions.txt`"
UI_FAMILY_LEFT_OUT = "a client-table row its family's key list leaves out (a name or developer row, ADR-042)"


def _ui_lists(repo: Path) -> tuple[set[str], set[str]]:
    """(the keys `pipeline/ui_keys.txt` ships, the keys `pipeline/ui_exclusions.txt` leaves out)."""
    def keys(name: str) -> set[str]:
        path = repo / "pipeline" / name
        if not path.is_file():
            return set()
        lines = path.read_text(encoding="utf-8").splitlines()
        return {k for raw in lines if (k := raw.split("#", 1)[0].strip())}

    return keys("ui_keys.txt"), keys("ui_exclusions.txt")


def ui_left_out(key: str, ui_keys: set[str], ui_excluded: set[str]) -> str | None:
    """Why an interface line with English and no Japanese is not a gap, or None: the key is excluded with a
    reason, or it is a client-table row (`Family:<id>`) the family's curated key list does not ship."""
    if key in ui_excluded:
        return UI_EXCLUDED
    if ":" in key and key not in ui_keys:
        return UI_FAMILY_LEFT_OUT
    return None


def _why(line: dict[str, Any] | None) -> str:
    if line is None:
        return "no Japanese yet"
    reasons = line.get("reasons") or []
    return f"{line['status']}: {reasons[0]}" if reasons else line["status"]


def measure(root: Path) -> dict[str, Any]:
    """→ {"types": {type: {...}}, "readings": {type: {...}}} over the store at `root` (the repo's data/)."""
    repo = root.parent
    store, english = Store(root), Store(root, english=True)
    types: dict[str, Any] = {}
    ui_keys, ui_excluded = _ui_lists(repo)
    # tooltip lines a batch can never take (a code drafting cannot place): their reason, stated
    blocked: dict[tuple[str, Any, str], str] = {}
    tooltip_kinds = (("item_description", "item"), ("spell_description", "spell"), ("spell_aura", "spell"))
    for kind, type_ in tooltip_kinds:
        for (id_, field), reason in undraftable(root, kind).items():
            blocked[(type_, id_, field)] = reason
    for type_, fields in SURFACE_FIELDS.items():
        en = [ln for ln in english.load(type_) if ln["field"] in fields]
        names = set(objective_names(repo, NAMES_LISTS[type_])) if type_ in NAMES_LISTS else set()
        ja = {(ln["id"], ln["field"]): ln for ln in store.load(type_)}
        titles = ({ln["id"]: ln["en"] for ln in english.load("quest") if ln["field"] == "title"}
                  if type_ == "quest" else {})
        done = named = uncounted = 0
        nothing: Counter[str] = Counter()
        missing: Counter[str] = Counter()
        for ln in en:
            j = ja.get((ln["id"], ln["field"]))
            if j is not None and shipped(j):
                done += 1
            elif ln["id"] in names:
                named += 1
            elif why := (
                nothing_to_translate(type_, ln["en"], titles.get(ln["id"]), ln["field"])
                or (type_ == "ui" and ui_left_out(str(ln["id"]), ui_keys, ui_excluded))
            ):
                nothing[why] += 1
            else:
                src = str(ln.get("src", "")).split("@")[0]
                wait = ""
                if type_ in ("item", "spell") and src == "wago":
                    wait = (": no text from the Forever tables on this build yet"
                            " (English still from Classic Era); rechecked at each re-pull")
                block = blocked.get((type_, ln["id"], ln["field"])) if j is None else None
                if block:
                    wait = f": the template uses a code drafting cannot place yet ({block})"
                missing[_why(j) + wait] += 1
                if not wait and (j is None or not j.get("reasons")):
                    uncounted += 1
        kept = sum(
            1 for j in ja.values()
            if shipped(j) and isinstance(j.get("ruling"), dict) and j["ruling"].get("ruling") == "accept"
        )
        types[type_] = {"english": len(en), "shipped": done, "names": named + sum(nothing.values()),
                        "kept_english": kept, "missing": dict(missing.most_common()), "uncounted": uncounted,
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
    return {"types": types, "readings": words, "served": served(repo), "voice": voice_coverage(root)}


VOICE_KINDS = {
    "description": "Quest offer",
    "progress": "Quest progress",
    "completion": "Quest turn-in",
    "g": "NPC talk (greetings, gossip, quest text keyed by its English)",
    "b": "Book and letter pages",
    "e": "The character's error lines (one file per race and sex)",
    "other": "Other",
}
# why a shipped NPC line has no voice, by where its English came from (data/english/gossip `src`)
GOSSIP_SILENT = {
    "vmangos": "NPC speech in chat, or other NPC text no voiced window shows (from VMaNGOS)",
    "wdb": "A quest log line (the completion text the tracker shows)",
    "collector": "Collected in game with no known speaker",
    "forever-vo": "Captured by players with no known speaker",
}


def _voice_kind(key: str) -> str:
    kind = key.split("-")[1] if key[:1].isdigit() else key.split("-")[0]
    return kind if kind in VOICE_KINDS else "other"


def voice_coverage(root: Path) -> dict[str, Any]:
    """The voice over: per kind, the files the voice reads (in step with the shipped Japanese, stale, not
    made) and the shipped lines it leaves silent, by reason. Committed data only; empty without the voice
    tables."""
    from wfj.cmd import voice_make  # the voice pipeline is only needed for this section

    cfg_path = root.parent / "pipeline" / "voice.toml"
    if not (root / "voice" / "speakers.jsonl").is_file() or not cfg_path.is_file():
        return {}
    cfg = voice_make.load_config(cfg_path)
    lines = voice_make.shipped_lines(root)
    jobs = voice_make.file_jobs(root, cfg, "all", lines, voice_make.players_of("all"))
    state = voice_make.voice.in_step(jobs, lines, cfg["roster"], voice_make.audio_record(root),
                                     voice_make.line_values(root, lines))
    stale, missing = set(state["stale"]), set(state["missing"])
    kinds: dict[str, Counter[str]] = {k: Counter() for k in VOICE_KINDS}
    # keys that play another line's file (a female wording, a repeated quest's text): voiced, not silent
    played, _, _ = voice_make.pack_tables(root, cfg, "all")
    english = Store(root, english=True).load("gossip")
    src = {str(r["id"]): str(r.get("src", "")).split("@")[0] for r in english}
    for j in jobs:
        c = kinds[_voice_kind(j.key)]
        c["files"] += 1
        c["stale" if j.stem in stale else "missing" if j.stem in missing else "in_step"] += 1
    voiced = {j.key for j in jobs}
    for k in voiced:
        kinds[_voice_kind(k)]["lines"] += 1
    narrator = Counter(_voice_kind(r["key"]) for r in voice_make.scoped_rows(root, "all")
                       if r["speaker"] == voice_make.voice.NARRATOR)
    silent: Counter[str] = Counter()
    shared = 0
    for k in lines.keys() - voiced:
        kind = _voice_kind(k)
        if k in played:
            shared += 1
        elif kind in ("description", "progress", "completion"):
            silent["No speaker found for the quest"] += 1
        elif kind == "g":
            silent[GOSSIP_SILENT.get(src.get(k[2:], ""), "NPC text with no known speaker")] += 1
        else:
            silent[f"{VOICE_KINDS[kind]}: no speaker"] += 1
    html = sum(1 for ln in Store(root).load("book") if shipped(ln) and readings.html_page("book", ln["ja"]))
    if html:
        silent["HTML book page (keeps the client's layout)"] = html
    return {"kinds": {k: dict(c) for k, c in kinds.items() if c}, "shared": shared,
            "narrator": dict(narrator), "silent": dict(silent.most_common())}


def _render_voice(v: dict[str, Any]) -> list[str]:
    if not v:
        return []
    out = ["", "## Voice", "",
           "Lines the voice reads, from `data/voice/` and the audio record `data/voice/audio.jsonl`.",
           "In step: the recorded file was made from the Japanese that ships now, in the speaker's cast",
           "voice. A line several differently cast speakers say has a file per voice, so files can",
           "outnumber lines.", "",
           "| Kind | Lines | Files | In step | Stale | Not made | Read by the narrator |",
           "|---|---|---|---|---|---|---|"]
    for kind, label in VOICE_KINDS.items():
        c = v["kinds"].get(kind)
        if c:
            cells = [c.get(n, 0) for n in ("lines", "files", "in_step", "stale", "missing")]
            cells.append(v["narrator"].get(kind, 0))
            out.append(f"| {label} | " + " | ".join(f"{n:,}" for n in cells) + " |")
    if v.get("shared"):
        out += ["", "Lines that play another line's file (a female wording of a gossip line, or a quest's"
                f" text Forever repeats under another id): {v['shared']:,}."]
    out += ["", "### Silent lines", "", "Shipped Japanese the voice does not read, by reason.", ""]
    if v["silent"]:
        out += ["| Why | Lines |", "|---|---|"]
        out += [f"| {why} | {n:,} |" for why, n in v["silent"].items()]
    else:
        out.append("None.")
    return out


def gaps(m: dict[str, Any]) -> dict[str, int]:
    """{type: served lines with neither shipped Japanese nor a stated reason}, the types that have any."""
    return {type_: t["uncounted"] for type_, t in m["types"].items() if t["uncounted"]}


def inventory_problems(repo: Path) -> list[str]:
    """Why the served-text inventory does not account for every served column (empty when it does)."""
    columns = read_inventory(repo / "pipeline" / "served_columns.txt")
    dispositions, problems = served_dispositions.parse(repo / "pipeline" / "served_dispositions.txt")
    return problems + served_dispositions.check(columns, dispositions)


def served(repo: Path) -> dict[str, Any]:
    """The served-text inventory by disposition: {"build", "kinds": {kind: [columns, lines]}, "columns":
    [(column, disposition label, lines, evidence)]}; empty when the inventory files are absent."""
    columns_path = repo / "pipeline" / "served_columns.txt"
    dispositions_path = repo / "pipeline" / "served_dispositions.txt"
    if not columns_path.is_file() or not dispositions_path.is_file():
        return {}
    columns = read_inventory(columns_path)
    dispositions, _problems = served_dispositions.parse(dispositions_path)
    kinds: dict[str, list[int]] = {}
    rows = []
    for column, counts in sorted(columns.items()):
        d = dispositions.get(column)
        label = d.label if d else "none"
        lines = served_dispositions.text_lines(counts)
        k = kinds.setdefault(d.kind if d else "none", [0, 0])
        k[0] += 1
        k[1] += lines
        rows.append((column, label, lines, d.evidence if d else ""))
    return {"build": inventory_build(columns_path), "kinds": kinds, "columns": rows}


def _pct(a: int, b: int) -> str:
    return f"{100 * a / b:.1f}%" if b else "-"


def render(m: dict[str, Any], stamp: str) -> str:
    out = [
        "# Coverage: how much of the game ships in Japanese",
        "",
        f"> **Generated** by `make coverage` (`pipeline/wfj/dev/coverage.py`) on {stamp}.",
        "> Do not edit by hand: every pull request that changes `data/` re-runs it. Measured from",
        "> the English the Forever client serves, every line of it; a line that is only a",
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
    out += _render_served(m.get("served") or {})
    out += ["", "## Word cards (readings with meanings)", "",
            "| Type | Lines that can carry a word list | With one | Done | Stale | Words | With a meaning |",
            "|---|---|---|---|---|---|---|"]
    for type_, r in m["readings"].items():
        done = _pct(r["with_words"], r["lines"])
        out.append(f"| {type_} | {r['lines']:,} | {r['with_words']:,} | {done} | "
                   f"{r['stale']:,} | {r['words']:,} | {_pct(r['with_meaning'], r['words'])} |")
    out += ["", "Item, spell, objective and area text take no word cards; HTML book pages",
            "and lines holding a `|` escape are not counted."]
    out += _render_voice(m.get("voice") or {})
    out.append("")
    return "\n".join(out)


KIND_LABELS = {
    "surface": "Shipped through a surface above",
    "names": "Names (stay English)",
    "internal": "Internal (never printed)",
    "no-display": "No place in the Forever client",
    "covered-by": "Same text as another column",
    "empty": "Empty on this build",
    "none": "No disposition yet",
}


def _render_served(sv: dict[str, Any]) -> list[str]:
    if not sv:
        return []
    out = ["", "## Served text inventory", "",
           f"Every text column the client serves on {sv['build']} (`pipeline/served_columns.txt`: its",
           "tables, hotfixes and server caches), with the disposition",
           "`pipeline/served_dispositions.txt` gives it.",
           "Lines are non-empty values; a server cache counts the records this install holds.", "",
           "| Disposition | Columns | Lines |", "|---|---|---|"]
    for kind, label in KIND_LABELS.items():
        if kind in sv["kinds"]:
            cols, lines = sv["kinds"][kind]
            out.append(f"| {label} | {cols:,} | {lines:,} |")
    out += ["", "### Every column", "", "| Column | Disposition | Lines | Why |", "|---|---|---|---|"]
    for column, label, lines, evidence in sv["columns"]:
        why = evidence.replace("|", "/")
        out.append(f"| `{column}` | {label} | {lines:,} | {why} |")
    return out


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
    ap.add_argument("--build", help="the pinned Forever build: refuse an inventory taken on another")
    a = ap.parse_args(argv)
    root = data_root()
    taken = inventory_build(root.parent / "pipeline" / "served_columns.txt")
    if a.build and taken != a.build:
        print(f"coverage: pipeline/served_columns.txt is from {taken}, the pinned build is {a.build}: "
              "run `make served-columns` and give each new column a disposition")
        return 1
    problems = inventory_problems(root.parent)
    if problems:
        print("coverage: the served-text inventory has columns without a stated disposition:")
        for p in problems:
            print(f"  {p}")
        return 1
    text = render(measure(root), _stamp(root.parent))
    if a.out:
        a.out.write_text(text, encoding="utf-8")
        print(f"coverage: wrote {a.out}")
        for rel in readme_counts.write(root.parent):
            print(f"coverage: updated the counts in {rel}")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
