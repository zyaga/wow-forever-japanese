"""Check a UI dictionary draft, or every shipped UI line, against the style guide's rules for interface text.

    python -m wfj.dev.ui_lint DRAFT.ui.jsonl [--base BASE.jsonl]
    python -m wfj.dev.ui_lint --shipped

A draft is `{"id", "field": "text", "ja"}` rows, one per UI string key, judged against the key's current
English in `data/english/ui`. `--shipped` judges every shipped UI line (`trusted` / `stale` / `unaligned`)
the same way.

A row **fails** (exit 1) with one reason per problem:

- `bad_row` / `missing_ja`: a row whose `id` or `ja` is not text, or whose `ja` is missing or empty
- `unknown_key`: the key has no English (not a UI string the client ships)
- `duplicate`: the key is in the draft twice
- `not_japanese`: no kana or kanji, or a simplified-only character. A template with no words outside its
  specifiers and colour codes (`(%s)`) is exempt, as is a shipped line ruled to stay in English letters.
- `specifiers:<reason>`: the Japanese does not take exactly the English's `%` arguments
- `markup:<reason>`: the Japanese does not keep the English's colour codes, textures, links and line breaks
- `ambiguous:<keys>`: with the draft applied, keys the addon finds by one English (the same text once
  colour codes and markup are set aside, `validate.ui_group`) would ship different Japanese; the other keys
  are named.
- `numbered:<reason>`: a numbered row whose Japanese does not fit its English (a slot the English lacks), the
  rule `make validate` applies to such a row.
  Keys in `UIStrings.OWN` are left out: a widget asks for them by name.

- `moved:<hash>` (with `--base`, the `audit.ui-base.jsonl` a UI review writes): the key's shipped Japanese is
  no longer the one the review judged, so the draft would overwrite a newer line. Cut and review it again.

These are the rules `make check` and `make validate` apply to UI lines, run before the import so a bad row is
fixed in the draft rather than found later.

A **short label** (a button, tab, header or field label: English of at most three words, no `%` argument,
no markup, not ending in `.` `?` `!` or `:`, and a key that is not an error or chat message: an `ERR_*` /
`SPELL_FAILED_*` key, or one on the `errors` or `chatsystem` surface) also gets
**warnings**, printed but not failing, because a reader has to judge them:

- `too_wide:<ja>/<limit>`: the Japanese is wider on screen than `max(ceil(english × 1.25), 6)` columns
  (full-width characters count 2, others 1). Katakana loanwords are often wider and still right.
- `register:<ending>`: the Japanese ends in `です`, `ます` or `ください`; a label is a bare noun or verb.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from wfj.cmd.validate import is_error_key, ui_group, ui_own
from wfj.core import language, markup, readings, specifiers, status
from wfj.core.report import SHIPPED
from wfj.dev.ui_inventory import read_inventory
from wfj.io.jsonl_store import Store
from wfj.paths import data_root

# surfaces whose strings are messages printed in a line of text, not labels on a widget
MESSAGE_SURFACES = frozenset({"errors", "chatsystem"})
SHORT_WORDS = 3
WIDTH_RATIO = 1.25
WIDTH_FLOOR = 6  # three full-width characters: any label may be one short Japanese word
SENTENCE_END = (".", "?", "!", ":")
# keys whose text is a tooltip or help sentence however short: not a widget label, so never held to a width
MESSAGE_KEY_SUFFIXES = ("_TOOLTIP", "_HELP", "_DESC", "_DESCRIPTION")
POLITE_ENDINGS = ("ください", "です", "ます")
TRAILING_MARKS = "。．.!！?？…"


def display_width(text: str) -> int:
    """Columns as a CJK font draws them: wide, full-width and ambiguous-width characters (…, →, ※) take two,
    a combining mark none, anything else one."""
    def columns(c: str) -> int:
        if unicodedata.combining(c):
            return 0
        return 2 if unicodedata.east_asian_width(c) in ("W", "F", "A") else 1

    return sum(columns(c) for c in text)


def width_limit(en: str) -> int:
    return max(math.ceil(display_width(en) * WIDTH_RATIO), WIDTH_FLOOR)


def _has_format(en: str) -> bool:
    try:
        arguments = bool(specifiers.parse(en))  # a literal `%` (100%) is not an argument
    except ValueError:
        arguments = True
    return arguments or "|" in en or "\n" in en or bool(markup.tokens(en))


def short_label(en: str, surfaces: set[str], key: str = "") -> bool:
    stripped = en.strip()
    return (
        0 < len(stripped.split()) <= SHORT_WORDS
        and not _has_format(stripped)
        and not stripped.endswith(SENTENCE_END)
        and not surfaces & MESSAGE_SURFACES
        and not is_error_key(key)
        and not key.endswith(MESSAGE_KEY_SUFFIXES)
    )


def register_ending(ja: str) -> str | None:
    bare = ja.rstrip(TRAILING_MARKS)
    return next((e for e in POLITE_ENDINGS if bare.endswith(e)), None)


def failures(en: str, ja: str, kept_english: bool = False) -> list[str]:
    reasons: list[str] = []
    if not language.is_japanese(ja, "text") and not status._no_words(en) and not kept_english:
        reasons.append("not_japanese")
    bad = specifiers.mismatch(en, ja)
    if bad:
        reasons.append(f"specifiers:{bad}")
    bad = markup.mismatch(en, ja)
    if bad:
        reasons.append(f"markup:{bad}")
    return reasons


def warnings(en: str, ja: str, surfaces: set[str], key: str = "") -> list[str]:
    if not short_label(en, surfaces, key):
        return []
    out: list[str] = []
    limit = width_limit(en)
    if display_width(ja) > limit:
        out.append(f"too_wide:{display_width(ja)}/{limit}")
    ending = register_ending(ja)
    if ending:
        out.append(f"register:{ending}")
    return out


def english_ui(root: Path) -> dict[str, str]:
    return {ln["id"]: ln["en"] for ln in Store(root, english=True).load("ui")}


def lint_rows(
    rows: list[dict[str, Any]], english: dict[str, str], inventory: dict[str, set[str]]
) -> list[tuple[str, list[str], list[str]]]:
    """(key, failing reasons, warnings) per row, in row order."""
    seen: set[str] = set()
    out: list[tuple[str, list[str], list[str]]] = []
    for row in rows:
        key, ja = row.get("id"), row.get("ja")
        shape = _shape_problem(key, ja)
        if shape:
            out.append((str(key), [shape], []))
            continue
        if key in seen:
            out.append((key, ["duplicate"], []))
            continue
        seen.add(key)
        if key not in english:
            out.append((key, ["unknown_key"], []))
            continue
        en = english[key]
        kept = (row.get("ruling") or {}).get("ruling") == "accept"
        out.append((key, failures(en, ja, kept), warnings(en, ja, inventory.get(key, set()), key)))
    return out


SHAPE_REASONS = ("bad_row", "missing_ja", "duplicate")


def _shape_problem(key: Any, ja: Any) -> str | None:
    if not isinstance(key, str) or (ja is not None and not isinstance(ja, str)):
        return "bad_row"
    if not ja:
        return "missing_ja"
    return None


def moved(rows: list[dict[str, Any]], shipped: list[dict[str, Any]], base: dict[str, str]) -> dict[str, str]:
    """key → `moved:<hash>` for a draft key whose shipped Japanese is not the one its review judged."""
    now = {ln["id"]: readings.ja_hash(ln["ja"]) for ln in shipped}
    return {r["id"]: f"moved:{base[r['id']]}" for r in rows
            if isinstance(r.get("id"), str) and r["id"] in base and now.get(r["id"]) != base[r["id"]]}


def ambiguous(
    draft: list[dict[str, Any]], shipped: list[dict[str, Any]], english: dict[str, str], own: set[str]
) -> dict[str, str]:
    """key → `ambiguous:<other keys>` for every key whose English group would ship two Japanese once the draft
    is applied, or `numbered:<reason>` for a numbered row whose Japanese does not fit its English. With a
    draft, only the draft's keys are reported; with none, every such key."""
    ja = {ln["id"]: ln["ja"] for ln in shipped}
    firsts: dict[str, str] = {}
    for r in draft:  # a duplicate key is judged on its first row, as lint_rows does
        if not _shape_problem(r.get("id"), r.get("ja")) and r["id"] in english:
            firsts.setdefault(r["id"], r["ja"])
    ja.update(firsts)
    groups: dict[str, dict[str, str]] = defaultdict(dict)
    unfit: dict[str, str] = {}
    for key, text in ja.items():
        if key in own or key not in english:
            continue
        try:
            group, compared = ui_group(key, english[key], text)
        except ValueError as err:
            unfit[key] = f"numbered:{err}"
            continue
        groups[group][key] = compared
    touched = set(firsts)
    out: dict[str, str] = {k: r for k, r in unfit.items() if not draft or k in touched}
    for keys in groups.values():
        if len(set(keys.values())) > 1:
            for k in keys:
                if not draft or k in touched:
                    out[k] = "ambiguous:" + ",".join(sorted(x for x in keys if x != k))
    return out


def with_ambiguity(
    results: list[tuple[str, list[str], list[str]]], *found: dict[str, str]
) -> list[tuple[str, list[str], list[str]]]:
    """`results` with each extra failing reason (`ambiguous`, `numbered`, `moved`) added to one row of its
    key: the first well-formed one, the row the reason was judged on (a duplicate row already fails
    `duplicate`; a malformed row has no Japanese to judge); with none well-formed, the first row."""
    shaped = {i for i, (_, bad, _) in enumerate(results) if bad and bad[0] in SHAPE_REASONS}
    target: dict[str, int] = {}
    for i, (k, _, _) in enumerate(results):
        if k not in target or (target[k] in shaped and i not in shaped):
            target[k] = i
    out: list[tuple[str, list[str], list[str]]] = []
    for i, (k, bad, warn) in enumerate(results):
        extra = [f[k] for f in found if k in f] if target.get(k) == i else []
        out.append((k, bad + extra, warn))
    return out


def read_base(path: Path) -> dict[str, str]:
    return {r["id"]: r["ja_hash"] for r in read_draft(path)}


def shipped_rows(root: Path) -> list[dict[str, Any]]:
    return [ln for ln in Store(root).load("ui") if ln["status"] in SHIPPED]


def read_draft(path: Path) -> list[dict[str, Any]]:
    return [json.loads(raw) for raw in path.read_text(encoding="utf-8").splitlines() if raw.strip()]


def summarize(results: list[tuple[str, list[str], list[str]]], out=sys.stdout) -> int:
    """Print every failing row and warning, then counts per reason; the exit code (1 when a row failed)."""
    fails: Counter[str] = Counter()
    warns: Counter[str] = Counter()
    for key, bad, warn in results:
        for r in bad:
            print(f"FAIL {key}: {r}", file=out)
            fails[r.split(":")[0]] += 1
        for w in warn:
            print(f"warn {key}: {w}", file=out)
            warns[w.split(":")[0]] += 1
    failed = sum(1 for _, bad, _ in results if bad)
    counts = ", ".join(f"{k} {n}" for k, n in sorted((fails + warns).items())) or "none"
    print(f"ui_lint: {len(results)} rows · {failed} failed · reasons: {counts}", file=out)
    return 1 if failed else 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wfj.dev.ui_lint", description=__doc__.split("\n\n")[0])
    ap.add_argument("draft", type=Path, nargs="?", help="a UI draft (.ui.jsonl)")
    ap.add_argument("--shipped", action="store_true", help="every shipped UI line instead of a draft")
    ap.add_argument("--base", type=Path,
                    help="audit.ui-base.jsonl: the Japanese each draft key was judged against")
    a = ap.parse_args(argv)
    if bool(a.draft) == a.shipped:
        ap.error("give a draft or --shipped")
    if a.shipped and a.base:
        ap.error("--base compares a draft with its review; it means nothing with --shipped")
    root = data_root()
    repo = root.parent  # the addon and the inventory of the same checkout as the data
    shipped = shipped_rows(root)
    rows = shipped if a.shipped else read_draft(a.draft)
    english = english_ui(root)
    own = ui_own(repo / "addon" / "WoWForeverJapanese")
    found = ambiguous([] if a.shipped else rows, shipped, english, own)
    stale = moved(rows, shipped, read_base(a.base)) if a.base else {}
    results = lint_rows(rows, english, read_inventory(repo / "pipeline" / "ui_inventory.txt"))
    return summarize(with_ambiguity(results, found, stale))


if __name__ == "__main__":
    sys.exit(main())
