"""Candidates for hand corrections: rejected quest variants whose ONLY failures are names that are a
near-miss of a name in the quest's English, likely misspellings. Prints one row per candidate with the
similarity and both contexts. A candidate is not a fix: every row is read by a person before a `correction`
is written (docs/operations/local-setup.md → Hand corrections).

Usage: cd pipeline && python -m wfj.dev.list_name_typos [--cutoff 0.7] [--context 30]
"""

from __future__ import annotations

import argparse
import difflib
import re

from wfj.cmd.check import build_scopes
from wfj.core import align, dedupe, status
from wfj.io.jsonl_store import Store
from wfj.paths import allowlist_path, data_root

_WS = re.compile(r"\s+")


def _around(text: str, needle: str, width: int) -> str:
    i = text.casefold().find(needle.casefold())
    if i < 0:
        return text[:width * 2].replace("\n", "⏎")
    return text[max(0, i - width) : i + len(needle) + width].replace("\n", "⏎")


def candidates(cutoff: float) -> list[dict]:
    root = data_root()
    allow = align.load_allowlist(allowlist_path(root).read_text(encoding="utf-8"))
    scopes = build_scopes(Store(root, english=True), "quest")
    rows = []
    for line in Store(root).load("quest"):
        if line["status"] in ("trusted", "stale"):
            continue
        scope = scopes.get(line["id"])
        if not scope or scope.empty:
            continue
        english_words = {w for n in align.latin_names(scope.text, set()) for w in (n, *n.split())}
        fold = {w.casefold(): w for w in english_words}
        for c in dedupe.variants(line):
            reasons, _ = status._evaluate(c.ja, line["field"], scope, allow, c.provenance)
            if not reasons or not all(r.startswith("alignment_failed:") for r in reasons):
                continue
            fixes = []
            for missing in (r.split(":", 1)[1] for r in reasons):
                best = difflib.get_close_matches(missing.casefold(), list(fold), n=1, cutoff=cutoff)
                if not best:
                    break
                ratio = difflib.SequenceMatcher(None, missing.casefold(), best[0]).ratio()
                fixes.append((missing, fold[best[0]], round(ratio, 2)))
            else:
                rows.append({"id": line["id"], "field": line["field"], "variant": c.index, "ja": c.ja,
                             "provenance": c.provenance, "fixes": fixes, "english": scope.text})
    return rows


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cutoff", type=float, default=0.7)
    ap.add_argument("--context", type=int, default=30)
    a = ap.parse_args(argv)
    rows = candidates(a.cutoff)
    for r in rows:
        p = r["provenance"]
        for missing, english, ratio in r["fixes"]:
            print(f"{r['id']}\t{r['field']}\tv{r['variant']}\t{p['source']}/{p.get('translator')}\t"
                  f"{missing!r} → {english!r} ({ratio})")
            print(f"\t  ja: …{_around(r['ja'], missing, a.context)}…")
            flat = _WS.sub(" ", r["english"])
            print(f"\t  en: …{_around(flat, english, a.context)}…")
    print(f"{len(rows)} candidate variants")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
