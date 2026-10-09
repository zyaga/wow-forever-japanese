"""`/wfj debug ui` on the Forever client, computed from the repo.

`UIStrings.build` (addon Core/UIStrings.lua) admits a shipped row only when the client's English for its key hashes
to the row's h1; otherwise the key is `mismatched` (the English moved: the line is never shown), `unresolved` (the
client has no such string) or `ambiguous` (two keys share one English with different Japanese: neither is shown; a
restricted family's keys are compared only within their family).
The English Forever's `_G` holds is what `data/english/ui` records under `db2@<forever build>` (the union import lets
Forever's English win; the served step then drops a key only Classic Era defines, so no `wago@` line stays). This
test runs the same recipe over the committed data, so a reworded line that nobody re-drafted fails CI instead of an
in-game pass.
"""

import re
from collections import defaultdict
from pathlib import Path

from wfj.core import specifiers
from wfj.core.model import ui_family
from wfj.emit.lua_writer import shipped
from wfj.io.jsonl_store import Store

FOREVER_SRC = "db2@1.60.1.70291"
FINGERPRINTED = ("ItemSubClass:", "SpellItemEnchantment:", "SpellSubtext:")  # no client string: matched by the live line's hash
PLURAL = re.compile(r"\|4([^:;|]*):([^;|]*);")


def _plural_forms(en: str) -> list[str]:
    """Every text a plural template is matched in (UIStrings.pluralForms: singular, plural, raw)."""
    if not PLURAL.search(en):
        return [en]
    return [PLURAL.sub(r"\1", en), PLURAL.sub(r"\2", en), en]


def _takes_arguments(text: str) -> bool:
    try:
        return bool(specifiers.parse(text))
    except ValueError:
        return True


def forever_counters(root: Path) -> dict[str, list[str]]:
    """The problem lists `UIStrings.build` would report on Forever for the committed `data/ui`."""
    data = root / "data"
    english = {ln["id"]: ln for ln in Store(data, english=True).load("ui")}
    rows = {ln["id"]: ln for ln in Store(data).load("ui") if shipped(ln)}
    problems: dict[str, list[str]] = {"mismatched": [], "unresolved": [], "ambiguous": []}
    exact_ja: dict[str, str] = {}  # h1 of an admitted exact English → its Japanese
    # a key that owns its Japanese (Core/UIStrings.lua OWN) stays out of the by-English buckets, as
    # UIStrings.build keeps it out of the index
    from wfj.cmd import validate as _validate

    try:
        own = _validate.ui_own(root / "addon/WoWForeverJapanese")
    except ValueError:  # a test tree's UIStrings.lua without the table
        own = set()
    buckets: dict[bool, dict[str, dict[str, set]]] = {False: defaultdict(dict), True: defaultdict(dict)}
    by_h1: dict[str, dict[str, set]] = defaultdict(dict)
    # (ADR-042) a restricted family's rows are an index of their own (byRestricted), one per family
    restricted: dict[str, dict[str, set]] = defaultdict(dict)
    for key, row in sorted(rows.items()):
        h1 = row["english"]["hash"][:8]
        if key.startswith(FINGERPRINTED) and not _takes_arguments(row["ja"]):
            by_h1[h1].setdefault(row["ja"], set()).add(key)
            continue
        en_line = english.get(key)
        if en_line is None or en_line["src"] != FOREVER_SRC:
            problems["unresolved"].append(key)
        elif en_line["hash"][:8] != h1:
            problems["mismatched"].append(key)
        elif key in own:
            continue
        elif ui_family(key):
            restricted[ui_family(key) + "\0" + en_line["en"]].setdefault(row["ja"], set()).add(key)
        else:
            bucket = buckets[_takes_arguments(en_line["en"])]
            for form in _plural_forms(en_line["en"]):
                bucket[form].setdefault(row["ja"], set()).add(key)
            if not _takes_arguments(en_line["en"]):
                exact_ja[en_line["hash"][:8]] = row["ja"]
    ambiguous: set[str] = set()
    for bucket in (*buckets.values(), restricted):
        for by_ja in bucket.values():
            if len(by_ja) > 1:
                ambiguous.update(k for keys in by_ja.values() for k in keys)
    for h1, by_ja in by_h1.items():
        if len(by_ja) > 1 or (h1 in exact_ja and set(by_ja) != {exact_ja[h1]}):
            ambiguous.update(k for keys in by_ja.values() for k in keys)
    problems["ambiguous"] = sorted(ambiguous)
    return problems


def test_no_shipped_ui_line_is_hidden_on_forever(root):
    problems = forever_counters(root)
    assert problems["mismatched"] == [], "re-draft (or re-verify) these against Forever's English"
    assert problems["ambiguous"] == [], "one English, one Japanese"


def test_no_shipped_key_is_one_forever_does_not_define(root):
    # Forever is the only target, so a key only Classic Era defines does not ship (the served step drops its
    # English; `check` makes the line no_english_id). A key an earlier Forever build defined keeps its English
    # (ADR-050): it is in the served record and is not unresolved.
    record = root / "pipeline" / "served" / "ui.tsv"
    earlier = {r.split("\t")[0] for r in record.read_text(encoding="utf-8").splitlines()
               if r and not r.startswith("#")} if record.is_file() else set()
    assert [k for k in forever_counters(root)["unresolved"] if k not in earlier] == []


def test_the_recipe_counts_a_reworded_line_and_a_shared_english(root, tmp_path):
    """The recipe itself, on a small store: a stale hash is mismatched; two keys, one English, two Japanese are
    ambiguous; a key only Classic Era defines is unresolved."""
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    now, old = "aaaaaaaa00000000", "bbbbbbbb00000000"

    def line(key, ja, h):
        return {"id": key, "field": "text", "ja": ja, "status": "trusted", "checks": [], "reasons": [],
                "provenance": {"class": "machine", "model": "m", "source": "draft-ui@2026-09-13",
                               "imported": "2026-09-13"}, "english": {"hash": h, "src": FOREVER_SRC},
                "conflicts": []}

    Store(data).save("ui", [line("MOVED", "旧", old), line("ONE", "一", now), line("TWO", "二", now),
                            line("GONE", "消", now)])
    Store(data, english=True).save("ui", [
        {"id": "MOVED", "field": "text", "en": "Moved", "hash": now, "src": FOREVER_SRC},
        {"id": "ONE", "field": "text", "en": "Same", "hash": now, "src": FOREVER_SRC},
        {"id": "TWO", "field": "text", "en": "Same", "hash": now, "src": FOREVER_SRC},
        {"id": "GONE", "field": "text", "en": "Gone", "hash": now, "src": "wago@1.15.9.69722"},
    ])
    got = forever_counters(tmp_path)
    assert got == {"mismatched": ["MOVED"], "unresolved": ["GONE"], "ambiguous": ["ONE", "TWO"]}
