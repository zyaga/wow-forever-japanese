"""Translation batches for server-only text: cut a batch of untranslated lines, expand a checked
draft into `wfj import draft` files. The check between the two is `wfj.dev.translate_lint`.

    python -m wfj.dev.translate_batch cut --kind progress --size 100 [--ids FILE [--redraft]] \
        [--redraft-older] [--held-back] \
        --out batches/p1.jsonl
    python -m wfj.dev.translate_lint batches/p1.jsonl batches/p1.draft.jsonl
    python -m wfj.dev.translate_batch expand batches/p1.draft.ok.jsonl --name progress-sg1 --out batches

`cut` selects lines that have English to translate, no `trusted` line, no hand-written (`human` /
`correction`) variant, and no machine variant. With `--redraft-older`, a line whose machine variants were all
drafted under an older style version is selected again, trusted or not (a line drafted under the current
version never is). With `--redraft` (only together with `--ids`), every listed line without a hand-written
variant is selected, whatever its drafts, and only the listed lines, not other lines sharing their English:
a re-draft imported under the same draft name replaces the line's machine variant in place.

With `--held-back`, a line whose hand-written variants all carry `ruling: reject` is selected
too: a recorded ruling says the model translates the whole line and replaces that text.
That covers quest completion, where nothing ships at all (`wfj.dev.rule_held_back`); the
tooltip kinds, where the hand-written Japanese has a number baked into it and the runtime gate
refuses it (`wfj.dev.rule_baked_numbers`); and quest description / objectives,
where the hand-written text is cut short (`rule_held_back --field`).

A bare label (no lower-case word, no token, no sentence punctuation: `Stratholme`, `Auction House`) has
nothing to translate and ships as the English (`has_prose`). A tooltip line is never a bare label: item
flavour text is written in title case (`Made With Love`), so a tooltip row without prose is cut like a quest
title, marked `title_case` and given its `names`; one whose whole English is an item, spell or creature name
(`Lightning Shield`) is marked `name_only` too, and its draft may be that name in English letters. Lines
sharing one English text become one row, so each text is drafted once. The English is shown in the form the
addon's data uses (`model_english`).

Kinds: quest `progress` / `completion`, gossip `text`, book page `text`. A book page written as HTML keeps its
tags and line breaks as they are.

A batch row: `{"ref", "kind", "en", "targets": [[id, field], …]}`, plus `"items"` for quest kinds: the item
names found in the targets' English quest objectives, so the drafter knows which lower-case words are items
the quest asks for, and plus `"slots"` for the client-template kinds: how many values the client
will print, so a draft knows the `$N<k>` range (`null` where the template makes that unknowable). A draft
row: `{"ref", "ja"}`.

`--src PREFIX` keeps only English from one source (`db2@1.60.1.69913` drafts what the Forever
pull served and skips the lines still carrying Classic Era's English).
`expand` refuses a draft name that does not end in `-sg<N>` for the style guide's current version, so every
machine line's `provenance.source` records which style guide produced it.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections.abc import Iterable
from pathlib import Path
from typing import Any

from wfj.core import align, decisions, hashing, readings, style
from wfj.core.english_text import PARA, model_english  # noqa: F401  (re-exported: batch / lint / tests)
from wfj.core.model import HASH_KEYED
from wfj.core.style import STYLE_GUIDE  # noqa: F401  (re-exported: the guide's path for callers)
from wfj.dev.objective_items import quest_items
from wfj.io.jsonl_store import Store
from wfj.io.wdb import PLACEHOLDER_TITLE
from wfj.paths import data_root

KINDS: dict[str, tuple[str, str]] = {  # kind → (data type, field)
    "progress": ("quest", "progress"),
    "completion": ("quest", "completion"),
    # The quest text the CLIENT serves, from its quest cache (ADR-020), as opposed to the
    # progress / completion text above, which only VMaNGOS has. Server-written prose either way, so the
    # style guide's Voice section applies and there are no `$N` placeholders: a quest's numbers are written
    # into the text the server sends, not filled in per player.
    "quest_title": ("quest", "title"),
    "quest_objectives": ("quest", "objectives"),
    "quest_description": ("quest", "description"),
    "gossip": ("gossip", "text"),
    "book": ("book", "text"),  # a book / letter / plaque page, id = the `page_text` entry
    "objective": ("objective", "text"),  # a quest objective's own server text, id = QuestObjective id
    # A quest's exploration / event objective text from the quest cache ("Scout through the Fargodeep
    # Mine", "Kernobee Rescue"), id = the quest id; drafted by the objective kind's rules
    "area": ("area", "text"),
    # Client text from the Forever build. Unlike the kinds above, this English is a
    # TEMPLATE the client fills (`Restores $o1 health over $d.`), so a draft writes `$N<k>` where a value
    # goes: see `core.align.value_slots` and `translate_lint`'s `value_index` / `numbers_changed`.
    "item_description": ("item", "description"),
    "spell_description": ("spell", "description"),
    "spell_aura": ("spell", "aura"),
}
# The kinds whose English is a client TEMPLATE: the `$n`/`$c`/`$r` in one are values, not the player, and a
# ruling can let the model redraft over hand-written text there (below).
TEMPLATE_KINDS = frozenset({"item_description", "spell_description", "spell_aura"})
# The kinds whose row carries a value-slot count. The quest kinds join them: a quest objective reads
# `Collect $1oa Lady's Tear Moss.` in the text the server sent and shows a number to the player, so a draft
# writes `$N<k>` there and the addon fills it from the live line (`Align.fillValues`). Quest text has no
# durations and no client-template semantics, which is why this is a wider set than TEMPLATE_KINDS.
SLOT_KINDS = TEMPLATE_KINDS | {"quest_title", "quest_objectives", "quest_description"}
# Kinds written in title case, where a capital says nothing about a name: the rows carry the `names` `cut`
# finds (title_names) and the lint checks those instead of every capitalised word. An objective's
# own text ("Eastern Tower Ablaze", "Archive Burned") is one, and every row is cut: a title-case event line
# is not a bare label; one that IS only a name is recorded in pipeline/objective_names.txt, not drafted.
TITLE_CASE_KINDS = frozenset({"quest_title", "objective", "area"})
REF_LEN = 10
# The kinds a recorded ruling lets the model redraft over hand-written text: quest completion, where no
# hand-written variant ships at all; the tooltip kinds, where the hand-written text has a number baked into
# it and the runtime gate refuses it (`dev.rule_baked_numbers`); quest description / objectives whose
# hand-written text is cut short (`truncated`); and quest titles, where a hand-written line ruled `reject`
# is redrafted whole.
HELD_BACK_KINDS = (
    frozenset({"completion", "quest_title", "quest_description", "quest_objectives"}) | TEMPLATE_KINDS
)

_GENDER = re.compile(r"\$[Gg]\s*([^:;$]*):[^;$]*;")
_CODES = re.compile(r"\$\d+[wW]|\$\S?")
_LOWER_WORD = re.compile(r"(?<![A-Za-z'’\-])[a-z]")
_PROSE_MARK = re.compile(r"\{(?:name|class|race)\}|[.?!…]")


def has_prose(en: str) -> bool:
    """Something to translate: a lower-case word, a `{name}` / `{class}` / `{race}` token or sentence
    punctuation (`.` `?` `!` `…`), reading a `$G<male>:<female>;` code as its first form and dropping other
    `$` codes. Without any, the English is a bare label (`Stratholme`, `Auction House`, `Herbalism`) that
    ships as the English; `Yes?` and `Greetings, {name}.` are drafted."""
    text = _CODES.sub(" ", _GENDER.sub(r"\1", en))
    return bool(_LOWER_WORD.search(text) or _PROSE_MARK.search(text))


def _cuttable(kind: str, en: str) -> bool:
    """A title-case kind is never a bare label ("Blackrock Menace" is still a title to translate), nor is a
    tooltip line ("Soft Like Pudding" is flavour text); any other line needs prose."""
    return kind in TITLE_CASE_KINDS or kind in TEMPLATE_KINDS or has_prose(en)


def _title_case_rows(kind: str, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """The rows the lint checks by their `names`: every row of a title-case kind, and a tooltip row
    without prose."""
    if kind in TITLE_CASE_KINDS:
        return rows
    if kind in TEMPLATE_KINDS:
        return [r for r in rows if not has_prose(r["en"])]
    return []


def style_version(repo: Path) -> int:
    try:
        return style.guide_version(repo)
    except ValueError as e:
        raise SystemExit(f"translate_batch: {e}") from None


def _blocked_by_hand_written(line: dict[str, Any], held_back: bool) -> bool:
    """A hand-written variant keeps the line out of a batch (machine text never replaces a human
    translation without a recorded ruling), unless `held_back` and every one of them is ruled `reject`,
    which is what lets a machine draft win there (`core.status._machine_barred`)."""
    return bool(decisions.hand_written_variants(line)) and not (
        held_back and decisions.hand_written_all_rejected(line)
    )


def _drafted(line: dict[str, Any], version: int | None) -> bool:
    """A machine variant exists (`version` None), or one drafted under that style version."""
    return any(
        decisions.is_machine(v["provenance"])
        and (version is None or style.source_version(v["provenance"]) == version)
        for v in decisions.variant_dicts(line)
    )


def eligible(
    english: list[dict[str, Any]],
    store: list[dict[str, Any]],
    field: str,
    version: int,
    redraft_older: bool = False,
    redraft: bool = False,
    held_back: bool = False,
):
    """English lines of `field` still to draft, in store order. A drafted line stays drafted when the style
    version is bumped, unless `redraft_older`: then a line whose machine variants are all from older style
    versions is selected, `trusted` or not (a trusted line with no hand-written variant is a machine line).
    `redraft` selects every line without a hand-written variant (the caller narrows it to listed ids).
    `held_back` also selects a line whose hand-written variants all carry `ruling: reject`;
    a line with any unruled hand-written variant is still skipped."""
    by_key = {(ln["id"], ln["field"]): ln for ln in store}
    for en in english:
        if en["field"] != field:
            continue
        ja = by_key.get((en["id"], field))
        if ja and redraft:
            if _blocked_by_hand_written(ja, held_back):
                continue
        elif ja and (
            (ja["status"] == "trusted" and not redraft_older)
            or _blocked_by_hand_written(ja, held_back)
            or _drafted(ja, version if redraft_older else None)
        ):
            continue
        yield en


def group(
    kind: str, lines: Iterable[dict[str, Any]], items: dict[Any, list[str]] | None = None
) -> list[dict[str, Any]]:
    """One row per distinct drafter English, first appearance order, every (id, field) sharing it. With
    `items` (quest kinds), each row also lists the objective item names of all its targets."""
    rows: dict[str, dict[str, Any]] = {}
    for ln in lines:
        en = model_english(ln["en"], player_tokens=kind not in TEMPLATE_KINDS)
        # Book pages group by the English hash, the addon's key for a page (ADR-022): pages whose English
        # differs only in whitespace share one row and so one Japanese. The row shows the first.
        group_key = ln["hash"] if kind == "book" else en
        row = rows.get(group_key)
        if row is None:
            ref = hashing.key(en)[:REF_LEN]
            if any(r["ref"] == ref for r in rows.values()):
                # never seen; fail rather than merge two texts under one ref
                raise SystemExit(f"translate_batch: ref collision {ref}")
            row = rows[group_key] = {"ref": ref, "kind": kind, "en": en, "targets": []}
            if items is not None:
                row["items"] = []
        row["targets"].append([ln["id"], ln["field"]])
        if items is not None:
            row["items"] += [name for name in items.get(ln["id"], []) if name not in row["items"]]
    return list(rows.values())


def read_ids(path: Path, numeric: bool) -> set[int | str]:
    out: set[int | str] = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        tok = raw.split("#", 1)[0].strip()
        if tok:
            out.add(int(tok) if numeric else tok)
    return out


OBJECTIVE_NAMES = "pipeline/objective_names.txt"
AREA_NAMES = "pipeline/area_names.txt"  # the same list for area text, keyed by quest id
NAMES_LISTS = {"objective": OBJECTIVE_NAMES, "area": AREA_NAMES}


def objective_names(repo: Path, list_: str = OBJECTIVE_NAMES) -> dict[int, str]:
    """The objectives that are only a name: `<QuestObjective id>  # <the English>` per line in
    pipeline/objective_names.txt, nothing drafted for them (names stay in English). `list_` = AREA_NAMES reads
    the area texts that are only a name (`<quest id>  # <the English>`). One reader for `cut` and the
    partition tests (tests/python/test_objective_pipeline.py); a repo without the file lists none."""
    path = repo / list_
    out: dict[int, str] = {}
    if not path.exists():
        return out
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()  # an indented comment or entry reads like any other
        if line and not line.startswith("#"):
            id_, _, en = line.partition("#")
            out[int(id_)] = en.strip()
    return out


def _annotate_slots(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Give each template row the number of values the client will print (`slots`), so the drafter knows the
    `$N<k>` range, and drop the rows that cannot be written safely.

    A row is dropped when the count is unknowable: a `$?…[…][…]` conditional whose branches differ in words
    or a `$@spelldesc…` inclusion (`align.UNCOUNTABLE`; a conditional whose branches differ only
    in their numbers is counted as one branch). Both are unsafe for a reason found in drafting: Fire
    Ward reads `Absorbs $s1 Fire damage$?s11094[ and grants a $s2% chance to reflect…][]`, so a Japanese line
    written without the clause silently drops it for a player who has that talent, and one written with it
    shifts every `$N<k>` for the player who does not. There is no wording that is right both ways, so the row
    waits for a mechanism rather than being guessed at. A name-list tail (Languages'
    `$?s668[<break>$@spellname668][]` chain) is not dropped: its head is counted, the row carries `tail`,
    and the Japanese translates the head and ends in `$T`."""
    for row in rows:
        row["slots"] = align.value_slots(row["en"])
        durations = align.duration_slots(row["en"])
        if durations:  # the `$D<k>` range: every `$d` AND every number written in front of a unit
            row["durations"] = durations
        if align.split_tail(row["en"])[1]:  # translate the head only and end the Japanese with `$T`
            row["tail"] = True
        if row["slots"] is None and "$@" not in row["en"] and align.has_branches(row["en"]):
            _annotate_branches(row)
        if align.icon_indices(row["en"]):  # `$I<k>` stands where an inline icon goes
            row["icons"] = len(align.icon_indices(row["en"]))
    return [row for row in rows if row["slots"] is not None]


# The reason a template row (ADR-043) is not drafted, kept on the row so `cut` can list it
_DROPPED = "dropped"


def _annotate_branches(row: dict[str, Any]) -> None:
    """A `$?` template: the Japanese keeps its conditionals and numbers `$N` / `$D` over the WHOLE template,
    every branch's values included (`align.branching`). `slots` / `durations` are those whole-template
    counts and `branches` the number of variants. A row whose branches cannot be written, or whose English
    variants the addon could never show one of (`align.never_shown`, the pre-draft check), keeps
    `slots: None` and says why in `dropped`."""
    b = align.branching(row["en"])
    if b.reason:
        row[_DROPPED] = b.reason
        return
    texts = [v.en for v in b.variants]
    pairs = align.indistinguishable(texts, texts, [v.shape for v in b.variants], set(), english=True)
    if align.never_shown(pairs, len(texts)):
        row[_DROPPED] = "branches_indistinguishable"
        return
    row["slots"] = b.slots
    row["durations"] = b.durations
    if not b.durations:
        row.pop("durations")
    row["branches"] = len(b.variants)


def spell_english(data: Path) -> dict[tuple[int, str], str]:
    """(spell id, field) → raw English, every field: what `align.expand_inclusions` splices in."""
    return {(ln["id"], ln["field"]): ln["en"] for ln in Store(data, english=True).load("spell")}


def expand_included(
    kind: str, lines: list[dict[str, Any]], spells: dict[tuple[int, str], str]
) -> tuple[list[dict[str, Any]], list[tuple[dict[str, Any], str]]]:
    """A template line (ADR-043) that includes another spell's text (`$@spelldesc<id>`,
    `$@spellicon`, `$@spellname`) and cannot be counted as it is gets that text spliced in, so the drafter
    translates the line the client shows. Lines the slot model already counts are untouched (a name-list
    tail's `$@spellname` stays as it is). → (lines, [(line, reason)] for the ones that cannot be expanded)."""
    if kind not in TEMPLATE_KINDS:
        return lines, []
    out: list[dict[str, Any]] = []
    dropped: list[tuple[dict[str, Any], str]] = []
    for ln in lines:
        raw = ln["en"]
        if align.INCLUSION.search(raw) is None and "$@" not in raw:
            out.append(ln)
            continue
        if align.value_slots(model_english(raw, player_tokens=False)) is not None:
            out.append(ln)
            continue
        x = align.expand_inclusions(raw, spells)
        if x.text is None:
            dropped.append((ln, x.reason or "unsupported_code"))
            continue
        out.append({**ln, "en": x.text})
    return out, dropped


_WORD = re.compile(r"[A-Za-z][A-Za-z'’\-]*")
# where the common English words come from: every text type a player reads
_VOCAB_TYPES = ("quest", "item", "spell", "gossip", "book", "ui")


def lowercase_vocab(data: Path) -> set[str]:
    """Every word the English corpus writes in lower case somewhere. A word that is never written that way is
    a name (`Skysight`, `Aetheen`), whatever its capitals in a title say."""
    out: set[str] = set()
    english = Store(data, english=True)
    for type_ in _VOCAB_TYPES:
        for ln in english.load(type_):
            out.update(w.lower() for w in _WORD.findall(ln.get("en") or "") if w[0].islower())
    return out


def known_names(data: Path) -> set[str]:
    """Item and creature names of two words or more (`A Study of the Light`, `Horn of Xelthos`): a title that
    contains one names it, and names stay in English letters. One-word names are left to the vocabulary
    test, because `Fire` or `Taming` is a spell name and an ordinary word at once."""
    english = Store(data, english=True)
    return {
        ln["en"] for type_ in ("item", "unit") for ln in english.load(type_)
        if ln["field"] == "name" and len(ln["en"].split()) >= 2
    }


def _common(word: str, vocab: set[str]) -> bool:
    """`word` or a plain inflection of it (plural, -ing, -ed) is written in lower case somewhere."""
    base = re.sub(r"['’]s$", "", word.lower())
    forms = {base, re.sub(r"s$", "", base), re.sub(r"es$", "", base), re.sub(r"ies$", "y", base),
             re.sub(r"ing$", "", base), re.sub(r"ing$", "e", base), re.sub(r"e?d$", "", base),
             re.sub(r"ed$", "e", base)}
    return any(f in vocab for f in forms)


def title_names(title: str, vocab: set[str], known: set[str]) -> list[str]:
    """The names a quest title holds, which the Japanese must keep in English letters: a capitalised
    word the corpus never writes in lower case, and any item or creature name of two words or more inside it.
    Title case capitalises every word, so capitals alone say nothing (without this, `The Gift of Skysight`
    could pass as `天眼の贈り物`)."""
    words = list(_WORD.finditer(title))
    found = [re.sub(r"['’]s?$", "", m.group()) for m in words
             if m.group()[0].isupper() and not _common(m.group(), vocab)]  # `Lee's`, `Bingles'` → `Lee`…
    for n in range(min(8, len(words)), 1, -1):
        for i in range(len(words) - n + 1):
            phrase = title[words[i].start():words[i + n - 1].end()]
            if phrase in known:
                found.append(phrase)
    return list(dict.fromkeys(found))


def every_name(data: Path) -> set[str]:
    """Every item, spell and creature name, one word or more: a tooltip line that is exactly one of them
    (`Umbrinoth`, `Lightning Shield`) is a name, which stays in English letters."""
    english = Store(data, english=True)
    return {ln["en"] for type_ in ("item", "spell", "unit") for ln in english.load(type_)
            if ln["field"] == "name" and ln.get("en")}


def _name_only(en: str, all_names: set[str]) -> bool:
    """The whole line, less a leading list dash, is a name the client knows. Only a known name counts: the
    corpus test would call `Squishy` a name, and a draft could then keep flavour text in English."""
    return en.strip().lstrip("-").strip() in all_names


def _annotate_names(rows: list[dict[str, Any]], data: Path, kind: str) -> None:
    rows = _title_case_rows(kind, rows)
    if not rows:
        return
    vocab, known = lowercase_vocab(data), known_names(data)
    all_names = every_name(data) if kind in TEMPLATE_KINDS else set()
    for row in rows:
        names = title_names(row["en"], vocab, known)
        if names:
            row["names"] = names
        if kind in TEMPLATE_KINDS:
            row["title_case"] = True
            if _name_only(row["en"], all_names):
                row["name_only"] = True


def _summary(label: str, rows: list[dict[str, Any]]) -> str:
    lines = sum(len(r["targets"]) for r in rows)
    chars = sum(len(r["en"]) for r in rows)
    return f"{label}: {lines} lines · {len(rows)} unique · {chars} English chars"


def write_jsonl(path: Path, rows: Iterable[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    with path.open(encoding="utf-8") as f:
        return [json.loads(raw) for raw in f if raw.strip()]


def _in_scope(
    data: Path,
    kind: str,
    type_: str,
    english: list[dict[str, Any]],
    src: str | None,
) -> list[dict[str, Any]]:
    """The English lines a cut may draft: served by the chosen build, not a name or a placeholder."""
    # Draft only text this build actually served. `--src db2@1.60.1.69913` keeps the lines the Forever
    # pull provided and drops the ones still carrying Classic Era's English, which the union merge kept.
    if src:
        english = [ln for ln in english if ln.get("src", "").startswith(src)]
        if not english:
            raise SystemExit(f"translate_batch: no {type_} English has src starting {src!r}")
    if kind in NAMES_LISTS:
        # an objective (or area text) that is only a name is listed in its names list, never drafted;
        # a missing list would draft every name-only objective, so stop instead
        list_ = NAMES_LISTS[kind]
        if not (data.parent / list_).exists():
            raise SystemExit(
                f"translate_batch: {list_} is missing; cut --kind {kind} needs the list of "
                "texts that are only a name (they are never drafted)"
            )
        names = objective_names(data.parent, list_)
        english = [ln for ln in english if ln["id"] not in names]
    if type_ in ("quest", "area"):
        # a placeholder quest (`<UNUSED>`, `<NYI> <TXT> …`, `REUSE`) is never drafted, in any field: nothing a
        # player is meant to see, and its title is its own English (`io/wdb.PLACEHOLDER_TITLE`).
        # Its area text neither (keyed by the quest id; the title is in the quest English)
        titles = english if type_ == "quest" else Store(data, english=True).load("quest")
        placeholder = {
            ln["id"] for ln in titles if ln["field"] == "title" and PLACEHOLDER_TITLE.search(ln["en"])
        }
        english = [ln for ln in english if ln["id"] not in placeholder]
    return english


def cut(  # noqa: PLR0913, PLR0917 - one parameter per CLI option; tests and the CLI pass them by name
    data: Path,
    kind: str,
    size: int,
    out: Path,
    ids: Path | None = None,
    redraft_older: bool = False,
    redraft: bool = False,
    held_back: bool = False,
    src: str | None = None,
) -> list[dict[str, Any]]:
    if redraft and ids is None:
        raise SystemExit("translate_batch: --redraft needs --ids (the lines to re-draft)")
    if held_back and kind not in HELD_BACK_KINDS:
        raise SystemExit(
            f"translate_batch: --held-back is {', '.join(sorted(HELD_BACK_KINDS))} only "
            "(the kinds a recorded ruling covers)"
        )
    type_, field = KINDS[kind]
    version = style_version(data.parent)
    english = Store(data, english=True).load(type_)
    english = _in_scope(data, kind, type_, english, src)
    items = quest_items(english, Store(data, english=True).load("item")) if type_ == "quest" else None
    selected = eligible(
        english, Store(data).load(type_), field, version, redraft_older, redraft, held_back
    )
    selected = list(selected)
    spells = spell_english(data) if kind in TEMPLATE_KINDS else {}
    selected, not_expanded = expand_included(kind, selected, spells)
    rows = [r for r in group(kind, selected, items) if _cuttable(kind, r["en"])]
    dropped: list[dict[str, Any]] = [
        {"id": ln["id"], "field": ln["field"], "reason": reason} for ln, reason in not_expanded
    ]
    if kind in SLOT_KINDS:
        before = len(rows)
        annotated = _annotate_slots(rows)
        dropped += [
            {"id": t[0], "field": t[1], "reason": r.get(_DROPPED, "uncountable")}
            for r in rows if r["slots"] is None for t in r["targets"]
        ]
        rows = annotated
        if before != len(rows):
            print(f"left out ({kind}): {before - len(rows)} rows whose value count the template cannot give")
    if dropped and kind in TEMPLATE_KINDS:
        # every template line left out is listed with its reason
        write_jsonl(out.with_name(out.name.removesuffix(".jsonl") + ".dropped.jsonl"), dropped)
        print(f"left out ({kind}): {len(dropped)} lines listed in "
              f"{out.name.removesuffix('.jsonl')}.dropped.jsonl")
    flags = (
        (", redraft older" if redraft_older else "")
        + (", redraft" if redraft else "")
        + (", held back" if held_back else "")
    )
    label = f"in scope ({kind}, sg{version}{flags})"
    print(_summary(label, rows))
    if ids is not None:
        wanted = read_ids(ids, numeric=type_ not in HASH_KEYED)
        if redraft:
            # a fix in place touches only the listed lines, never another line sharing their English, except
            # a book page, whose pages sharing the English hash are one row in the addon: re-drafted together
            listed = [ln for ln in selected if ln["id"] in wanted]
            if kind == "book":
                hashes = {ln["hash"] for ln in listed}
                listed = [ln for ln in selected if ln["hash"] in hashes]
            rows = [r for r in group(kind, listed, items) if _cuttable(kind, r["en"])]
            if kind in SLOT_KINDS:
                rows = _annotate_slots(rows)
        else:
            # a first draft of a listed line's English serves every undrafted line that shares it
            rows = [r for r in rows if any(t[0] in wanted for t in r["targets"])]
    if ids is not None:
        missed = sorted(set(wanted) - {t[0] for r in rows for t in r["targets"]}, key=str)
        if missed:  # a listed line the selection refuses must not be dropped without a word
            print(f"listed but not selectable ({len(missed)}; a hand-written variant without --held-back, "
                  f"no English, or no prose): {', '.join(map(str, missed[:20]))}")
    batch = rows[:size]
    _annotate_names(batch, data, kind)
    write_jsonl(out, batch)
    print(_summary(f"batch {out.name}", batch))
    return batch


def expand(ok_file: Path, name: str, out_dir: Path, version: int) -> dict[str, int]:
    """Checked draft rows → one `{id, field, ja}` import file per data type (`<name>.<type>.jsonl`), and
    one readings batch `<name>.words.jsonl` (`{type, id, field, ja_hash, words}` per target of a
    row that carried `words`) for `wfj readings import` once the lines are imported and checked. A draft
    without `words` writes no readings file."""
    try:
        style.check_name(name, version)
    except ValueError as e:
        raise SystemExit(f"translate_batch: {e}") from None
    by_type: dict[str, list[dict[str, Any]]] = {}
    words: list[dict[str, Any]] = []
    for row in read_jsonl(ok_file):
        type_ = KINDS[row["kind"]][0]
        for id_, field in row["targets"]:
            by_type.setdefault(type_, []).append({"id": id_, "field": field, "ja": row["ja"]})
            if "words" in row:
                h = readings.ja_hash(row["ja"])
                words.append({"type": type_, "id": id_, "field": field, "ja_hash": h, "words": row["words"]})
    counts = {}
    for type_, rows in sorted(by_type.items()):
        write_jsonl(out_dir / f"{name}.{type_}.jsonl", rows)
        counts[type_] = len(rows)
        print(f"{name}.{type_}.jsonl: {len(rows)} lines")
    if words:
        write_jsonl(out_dir / f"{name}.words.jsonl", words)
        counts["words"] = len(words)
        print(f"{name}.words.jsonl: {len(words)} lines with readings")
    return counts


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="translate_batch", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("cut")
    c.add_argument("--kind", choices=sorted(KINDS), required=True)
    c.add_argument("--size", type=int, required=True)
    c.add_argument("--ids", type=Path)
    c.add_argument(
        "--redraft-older", action="store_true", help="also select lines drafted under an older style version"
    )
    c.add_argument(
        "--redraft", action="store_true", help="with --ids: select the listed lines even when already drafted"
    )
    c.add_argument(
        "--held-back",
        action="store_true",
        help="completion, the quest title / description / objectives kinds and the tooltip kinds: also "
        "select lines "
        "whose hand-written variants are all ruled reject",
    )
    c.add_argument(
        "--src",
        help="only English whose src starts with this (`db2@1.60.1.69913` for the Forever pull)",
    )
    c.add_argument("--out", type=Path, required=True)
    e = sub.add_parser("expand")
    e.add_argument("ok_file", type=Path)
    e.add_argument("--name", required=True)
    e.add_argument("--out", type=Path, required=True)
    args = ap.parse_args(argv)
    data = data_root()
    if args.cmd == "cut":
        cut(
            data,
            args.kind,
            args.size,
            args.out,
            args.ids,
            args.redraft_older,
            args.redraft,
            args.held_back,
            args.src,
        )
    else:
        expand(args.ok_file, args.name, args.out, style_version(data.parent))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
