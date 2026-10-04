"""wfj validate [--base REF]: the CI gate over data/ and the generated Data/ (docs/systems/pipeline.md).

Rules, each a function returning problems:
  1. schema: every data/ and data/english/ line validates, (id, field) unique per type; SCHEMA matches.
  2. provenance: with --base, no hand-written (`human` / `correction`) line at REF is `machine` now, unless
     it carries `ruling: accept` or every hand-written variant on it is ruled `reject` (a `correction` may
     replace anything, ADR-014). Machine text never replaces a human translation without a recorded ruling.
  3. collisions (ADR-005): one English hash never names two different normalized texts.
  4. referential: every shipped line has its English hash, and that hash agrees with the store
     (trusted/unaligned: equal; stale: different).
  5. regenerate-and-diff: `generate.plan()` equals what is on disk under Data/ and in the TOC block, and the
     meaning numbers file (data/reading/meaning-numbers.tsv, ADR-060) is the one generate would write.
  6. placeholders: a shipped line carries no token the addon would render literally: a `{…}` outside
     the known set, or a `<x/y>` pair that is not two ASCII words.
  7. ui strings: a shipped UI string takes exactly its English template's arguments, and no two shipped
     keys share one normalized English with different Japanese (the addon could not tell them apart).
     A key in the addon's UIStrings.OWN table is left out of that comparison (the addon asks for it by
     key). It keeps the English's colour tokens and line breaks (core/markup.py), and two string captures
     the English separates only by whitespace ("Level %d %s %s": a race may be two words) keep their order
     in the Japanese. The addon splits such a line lazily, which is safe only when fill restores the same
     order.
  8. readings (ADR-036): every `data/reading/` record is well formed and not a duplicate, and its
     words sit in its line's Japanese in order (kanji, no ASCII, kana readings). A reading whose Japanese
     changed since it was written, or whose line no longer ships, is stale: reported with its ids, not a
     failure; it does not ship. Prints how many shipped quest / gossip / ui lines have a reading, the lines
     still owed one (a kanji or kana, no `|`) and the words without a meaning.
`luac -p` over the generated files is `make luac` (part of `make validate`); the pipeline runs no Lua.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from wfj.cmd import check, generate
from wfj.core import decisions, glosses, markup, numbered, placeholders, readings, specifiers
from wfj.core.model import ENGLISH_FIELDS, FIELDS, SCHEMA, ui_family, validate_line
from wfj.core.normalize import normalize_for, normalize_v1
from wfj.core.report import SHIPPED
from wfj.emit import lua_writer
from wfj.io.jsonl_store import Store
from wfj.paths import data_root

_SRC_RE = re.compile(r"^[a-z0-9_-]+@")
SHIPPED_STATUS = SHIPPED


def rule_schema(root: Path, store: Store, english: Store) -> list[str]:
    problems: list[str] = []
    schema_file = (root / "SCHEMA").read_text(encoding="utf-8").strip()
    if schema_file != str(SCHEMA):
        problems.append(f"data/SCHEMA is {schema_file!r}, code says {SCHEMA}")
    for type_ in FIELDS:
        seen: set[tuple] = set()
        for ln in store.load(type_):
            problems += [f"{type_} {ln.get('id')}/{ln.get('field')}: {p}" for p in validate_line(type_, ln)]
            key = (ln.get("id"), ln.get("field"))
            if key in seen:  # duplicates are reported, never resolved silently
                problems.append(f"{type_} {key[0]}/{key[1]}: duplicate line")
            seen.add(key)
    for type_ in ENGLISH_FIELDS:
        for ln in english.load(type_):
            problems += [
                f"english {type_} {ln.get('id')}/{ln.get('field')}: {p}"
                for p in validate_line(type_, ln, english=True)
            ]
    return problems


def _base_classes(repo: Path, ref: str) -> dict[tuple[str, int | str, str], tuple[str, str]]:
    """(type, id, field) → (provenance.class, status) for every data/ line at REF (english excluded)."""
    listing = subprocess.run(
        ["git", "-C", str(repo), "ls-tree", "-r", "--name-only", ref, "--", "data/"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()
    classes: dict[tuple[str, int | str, str], tuple[str, str]] = {}
    for path in listing:
        parts = path.split("/")
        if len(parts) != 3 or parts[1] == "english" or not path.endswith(".jsonl"):
            continue
        blob = subprocess.run(
            ["git", "-C", str(repo), "show", f"{ref}:{path}"], capture_output=True, text=True, check=True
        ).stdout
        for raw in blob.splitlines():
            if raw.strip():
                ln = json.loads(raw)
                classes[(parts[1], ln["id"], ln["field"])] = (
                    ln.get("provenance", {}).get("class", ""),
                    ln.get("status", ""),
                )
    return classes


def rule_provenance(root: Path, store: Store, base: str | None) -> list[str]:
    if base is None:
        print("validate: provenance rule skipped (no --base)")
        return []
    problems: list[str] = []
    try:
        before = _base_classes(root.parent, base)
    except subprocess.CalledProcessError as exc:
        return [f"provenance: cannot read data/ at {base!r}: {(exc.stderr or '').strip() or exc}"]
    except FileNotFoundError:
        return ["provenance: git is not available; cannot check the provenance rule"]
    for type_ in FIELDS:
        for ln in store.load(type_):
            was, was_status = before.get((type_, ln["id"], ln["field"]), ("", ""))
            if was not in decisions.HAND_WRITTEN or ln["provenance"]["class"] != decisions.MACHINE:
                continue
            where = f"provenance: {type_} {ln['id']}/{ln['field']} was {was}"
            # an `accept` ruling on the machine line is the explicit, logged decision that lets it replace one
            ruling = ln.get("ruling")
            if isinstance(ruling, dict) and ruling.get("ruling") == "accept":
                continue
            if not decisions.hand_written_all_rejected(ln):
                problems.append(f"{where} at {base}, now machine")
            elif was_status in SHIPPED:
                # reject rulings on every hand-written variant let a draft replace text that shipped nothing;
                # taking a SHIPPING hand-written line needs its own explicit ruling
                problems.append(
                    f"{where} and shipped ({was_status}) at {base}, now machine: reject rulings only replace "
                    "hand-written text that shipped nothing; add `ruling: accept` to the machine line"
                )
    return problems


def rule_collisions(english: Store) -> list[str]:
    problems: list[str] = []
    for type_ in ENGLISH_FIELDS:
        seen: dict[str, str] = {}
        for ln in english.load(type_):
            norm = normalize_for(type_, ln["en"])
            other = seen.setdefault(ln["hash"], norm)
            if other != norm:
                problems.append(
                    f"collision: english {type_} hash {ln['hash']} names two texts ({ln['id']}/{ln['field']})"
                )
    return problems


def rule_referential(store: Store, english: Store) -> list[str]:
    problems: list[str] = []
    included = check.Included(english)
    for type_ in check.TYPES:
        scopes = check.scopes_for(english, store, type_)
        for ln in store.load(type_):
            if ln["status"] not in SHIPPED_STATUS:
                continue
            where = f"{type_} {ln['id']}/{ln['field']}"
            eng = ln.get("english")
            if not eng or not eng.get("hash") or not _SRC_RE.match(eng.get("src") or ""):
                problems.append(f"{where}: shipped without english {{hash, src}}")
                continue
            scope = scopes.get(ln["id"])
            if scope is None or scope.empty:
                problems.append(f"{where}: shipped but no English scope for the id")
                continue
            current = check.english_hash(scope, ln["field"])
            # an item / spell line is also stale when a spell it splices in changed
            # (`english.includes`)
            now = included.of(scope, ln["field"])
            includes_changed = bool(eng.get("includes")) and now is not None and eng["includes"] != now
            if ln["status"] == "stale" and eng["hash"] == current and not includes_changed:
                problems.append(f"{where}: stale but its hash equals the current English")
            if ln["status"] != "stale" and eng["hash"] != current:
                problems.append(
                    f"{where}: {ln['status']} but its hash is not the current English ({current})"
                )
    return problems


def rule_placeholders(store: Store) -> list[str]:
    problems = []
    for type_ in check.TYPES:
        for ln in store.load(type_):
            if ln["status"] not in SHIPPED_STATUS:
                continue
            bad = ", ".join(sorted(set(placeholders.unknown(ln.get("ja")))))
            if bad:
                known = ", ".join("{" + w + "}" for w in placeholders.KNOWN)
                where = f"{type_} {ln['id']}/{ln['field']}"
                problems.append(f"placeholders: {where} ships unknown token(s) {bad}; known: {known}")
    return problems


# Argument kinds whose capture is free text (UIStrings.ARGS in Core/UIStringKeys.lua): a lazy split between
# two of them
# depends on the order the Japanese puts them back in. A `%s` without a kind is a number; `word` is one word.
FREE_TEXT_KINDS = {"text", "words", "skill", "time"}
_ARGS_BLOCK = re.compile(r"UIStrings\.ARGS = \{(.*?)\n\}", re.S)
_ARGS_ENTRY = re.compile(r"([A-Z][A-Z0-9_]+) = \{([^}]*)\}")


UI_KEY_FILES = ("UIStringKeys.lua", "UIStrings.lua")


def _ui_lua(addon_dir: Path) -> tuple[Path, str]:
    """The addon's UI string tables as one text: the per-key tables (Core/UIStringKeys.lua) and the index
    (Core/UIStrings.lua), whichever exist."""
    core = addon_dir / "Core"
    text = "\n".join(
        (core / name).read_text(encoding="utf-8") for name in UI_KEY_FILES if (core / name).exists()
    )
    return core / UI_KEY_FILES[0], text


def ui_arg_kinds(addon_dir: Path) -> dict[str, dict[int, str]]:
    """The addon's declared argument kinds per UI key, read from the addon (the one table both sides use)."""
    _, text = _ui_lua(addon_dir)
    m = _ARGS_BLOCK.search(text)
    if not m:
        return {}
    return {
        key: {int(i): kind for i, kind in re.findall(r'\[(\d+)\] = "(\w+)"', body)}
        for key, body in _ARGS_ENTRY.findall(m.group(1))
    }


_OWN_BLOCK = re.compile(r"UIStrings\.OWN = \{(.*?)\n\}", re.S)


def ui_own(addon_dir: Path) -> set[str]:
    """The keys that own their Japanese (UIStrings.OWN, the one table both sides use). The addon matches them
    only where a widget names them, so they share an English with another key without being ambiguous."""
    path, text = _ui_lua(addon_dir)
    m = _OWN_BLOCK.search(text)
    if not m:
        raise ValueError(f"{path}: no UIStrings.OWN block")
    return set(re.findall(r"\b([A-Z][A-Z0-9_]+) = true", m.group(1)))


class _AllText(dict):
    """The kinds of an undeclared ERR_* / SPELL_FAILED_* key: every `%s` is `text`
    (Core/UIStrings.lua `argKinds`)."""

    def get(self, _key, _default=None):
        return "text"


def is_error_key(key: str) -> bool:
    """An ERR_* / SPELL_FAILED_* key: the UI errors frame's strings (ADR-035)."""
    return key.startswith(("ERR_", "SPELL_FAILED_"))


_CHAT_BLOCK = re.compile(r"UIStrings\.CHAT_FAMILIES = \{(.*?)\}", re.S)


def ui_chat_families(addon_dir: Path) -> list[re.Pattern[str]]:
    """The system chat key families, read from the addon (UIStrings.CHAT_FAMILIES, the one list; Lua anchors
    ^ / $ and literal names only)."""
    path, text = _ui_lua(addon_dir)
    m = _CHAT_BLOCK.search(text)
    if not m:
        raise ValueError(f"{path}: no UIStrings.CHAT_FAMILIES block")
    entries = re.findall(r'"([^"]+)"', m.group(1))
    bad = [e for e in entries if not re.fullmatch(r"\^?[A-Z0-9_]+\$?", e)]
    if bad:  # a Lua pattern is only a Python regex while it is a literal name with ^ / $
        raise ValueError(f"{path}: CHAT_FAMILIES entries that are not a literal name with ^ / $: {bad}")
    return [re.compile(e) for e in entries]


def key_arg_kinds(
    key: str, declared: dict[str, dict[int, str]], chat: list[re.Pattern[str]] | None = None
) -> dict[int, str]:
    """A key's argument kinds as the addon applies them: its UIStrings.ARGS entry, else all-`text` for an
    error key or a system chat key, else none (a `%s` is a number)."""
    if key in declared:
        return declared[key]
    if is_error_key(key) or any(p.search(key) for p in chat or []):
        return _AllText()
    return {}


def adjacent_captures_reordered(en: str, ja: str, kinds: dict[int, str] | None = None) -> str | None:
    """Two free-text arguments the English separates only by whitespace must appear in the same
    reading order in the Japanese (the addon splits them lazily). `kinds`: the key's declared argument kinds
    (a `%s` without one is a number); None treats every `%s` as free text. → None, or "%a$ %b$"."""
    try:
        want = specifiers.parse(en)
        got = [i for i, _ in specifiers.parse(ja)]
    except ValueError:
        return None  # an unparseable template is the specifier rule's rejection
    spans = [m for m in specifiers.SPEC.finditer(en) if m.group(0) != "%%"]
    for k in range(len(spans) - 1):
        gap = en[spans[k].end():spans[k + 1].start()]
        a, b = want[k][0], want[k + 1][0]

        def free(i: int, conv: str) -> bool:
            return conv.endswith("s") and (kinds is None or kinds.get(i) in FREE_TEXT_KINDS)

        if gap.strip(" ") or not (free(a, want[k][1]) and free(b, want[k + 1][1])):
            continue  # separated by words, or one side is a number / one word (it cannot swallow the other)
        if a in got and b in got and got.index(a) > got.index(b):
            return f"%{a}$ %{b}$"
    return None


def ui_group(key: str, en: str, ja: str) -> tuple[str, str]:
    """(the group the addon's by-English index files a key under, its Japanese as that index compares it).

    Keys of one group must ship one Japanese. Colour codes are not words; a restricted family's keys group
    only with their own family (ADR-042: the addon finds them only where a widget names that family); a
    numbered row is seen as its skeleton and its slotted Japanese. Raises ValueError when a numbered row's
    Japanese does not fit its English."""
    text = en
    if numbered.is_numbered(key):
        ja = numbered.fill_slots(text, ja)
        text = numbered.skeleton(text)
    return (ui_family(key) or "") + "\0" + normalize_for("ui", text), normalize_v1(ja)


def rule_ui(
    store: Store,
    english: Store,
    kinds: dict[str, dict[int, str]] | None = None,
    chat: list[re.Pattern[str]] | None = None,
    own: set[str] | None = None,
) -> list[str]:
    problems: list[str] = []
    kinds = kinds or {}
    own = own or set()
    en = {ln["id"]: ln["en"] for ln in english.load("ui")}
    by_text: dict[str, dict[str, str]] = {}  # normalized English → {key: ja}
    for ln in store.load("ui"):
        if ln["status"] not in SHIPPED_STATUS or ln["id"] not in en:
            continue  # an unshipped line, or one without English (rule 4 reports that)
        bad = specifiers.mismatch(en[ln["id"]], ln["ja"])
        if bad:
            problems.append(f"ui {ln['id']}: specifiers differ from the English ({bad})")
        bad = markup.mismatch(en[ln["id"]], ln["ja"])
        if bad:
            problems.append(f"ui {ln['id']}: markup differs from the English ({bad})")
        bad = adjacent_captures_reordered(en[ln["id"]], ln["ja"], key_arg_kinds(ln["id"], kinds, chat))
        if bad:
            problems.append(f"ui {ln['id']}: adjacent_captures_reordered ({bad})")
        if ln["id"] in own:
            continue  # an owned key never enters the addon's by-English index
        try:
            group, ja = ui_group(ln["id"], en[ln["id"]], ln["ja"])
        except ValueError as err:
            problems.append(f"ui {ln['id']}: numbered row does not fit its English ({err}); not shipped")
            continue
        by_text.setdefault(group, {})[ln["id"]] = ja
    for group, keys in sorted(by_text.items()):
        text = group.split("\0", 1)[1]
        if len(set(keys.values())) > 1:
            problems.append(
                f"ui ambiguous: {', '.join(sorted(keys))} share the English {text!r} with different Japanese"
            )
    return problems


# the types the addon's objective index is built from (Core/Objectives: one index over both)
OBJECTIVE_INDEX_TYPES = ("objective", "area")


def rule_objective(store: Store) -> list[str]:
    """The addon finds (ADR-031) an objective's row by the fingerprint of its English (the client
    gives no objective id), so two objectives with one English must ship one Japanese, else neither shows.
    The index spans objective AND area rows and keys them by h1 (the first 32 bits of the English
    hash), so the rule groups both types by h1: one h1 with different Japanese anywhere in them is refused.
    The Japanese is compared as shipped, byte for byte: the addon's index (Core/Objectives) compares it
    raw, so two texts differing only in spacing would be ambiguous there. Prints the
    shipped count of each type."""
    by_h1: dict[str, dict[str, str]] = {}
    shipped = dict.fromkeys(OBJECTIVE_INDEX_TYPES, 0)
    for type_ in OBJECTIVE_INDEX_TYPES:
        for ln in store.load(type_):
            if ln["status"] in SHIPPED_STATUS and ln.get("english") and lua_writer.shipped(ln):
                shipped[type_] += 1
                h1 = ln["english"]["hash"][:8]
                by_h1.setdefault(h1, {})[f"{type_} {ln['id']}"] = ln["ja"]
    print("validate: objective index: " + " · ".join(f"{t} {n} shipped" for t, n in shipped.items()))
    return [
        f"objective ambiguous: {', '.join(sorted(rows, key=_row_order))} share one English fingerprint with "
        "different Japanese"
        for _, rows in sorted(by_h1.items())
        if len(set(rows.values())) > 1
    ]


def _row_order(row: str) -> tuple[str, int]:
    type_, id_ = row.split(" ", 1)
    return type_, int(id_)


def rule_readings(store: Store) -> list[str]:
    """Rule 8 (readings). Stale readings are printed, not returned: they are expected after a translation
    changes and simply do not ship until they are written again."""
    problems: list[str] = []
    words = with_meaning = 0
    for type_ in readings.TYPES:
        japanese = readings.shipped_japanese(store.load(type_))
        result = readings.check(type_, generate.reading_store_of(store).load(type_), japanese)
        problems += result["problems"]
        type_words = sum(len(r["words"]) for r in result["current"])
        type_meanings = sum(1 for _ in glosses.meanings_of(result["current"]))
        words += type_words
        with_meaning += type_meanings
        # every translation batch writes meanings; a word without one shows up here on every run
        if type_words > type_meanings:
            print(f"validate: readings: {type_words - type_meanings} {type_} words have no meaning")
        # Every translation batch writes readings too: a line shipped without one shows up here on every
        # run, so a batch that skipped the readings step is visible.
        have = len(result["current"])
        print(f"validate: readings: {have} of {len(japanese)} shipped {type_} lines have one")
        # the lines still owed a reading: something to annotate and no current reading (a kanji, or kana
        # beyond a bare particle: `readings.annotatable`, the export's rule). A line with `|`
        # (a colour code `|c…|r`, or any other escape) is expected here: the reading box
        # refuses such text (UI/Readings spanAreas), so it is marked, not owed.
        covered = {(r["id"], r["field"]) for r in result["current"]}
        owed = sorted(
            (
                k
                for k, ja in japanese.items()
                if k not in covered and readings.annotatable(ja) and not readings.html_page(type_, ja)
            ),
            key=str,
        )
        escaped = [k for k in owed if readings.holds_escape(japanese[k])]
        owed = [k for k in owed if not readings.holds_escape(japanese[k])]
        if owed:
            shown = ", ".join(f"{i}/{f}" for i, f in owed[:20])
            more = f" … {len(owed) - 20} more" if len(owed) > 20 else ""
            head = f"validate: readings: {len(owed)} {type_} lines with words to annotate have none"
            print(f"{head}: {shown}{more}")
        if escaped:
            print(f"validate: readings: {len(escaped)} {type_} lines hold an escape sequence (no readings)")
        if result["stale"]:
            ids = ", ".join(f"{i}/{f}" for i, f in result["stale"][:20])
            more = f" … {len(result['stale']) - 20} more" if len(result["stale"]) > 20 else ""
            print(f"validate: readings: {len(result['stale'])} stale {type_} (not shipped): {ids}{more}")
    # the word popup shows a meaning only for a word whose entry carries one
    print(f"validate: readings: {with_meaning} of {words} words carry a meaning (the word popup)")
    return problems


def rule_regenerate(
    root: Path, store: Store, addon_dir: Path, planned: dict[str, str] | None = None
) -> list[str]:
    """`planned`: the store's plan when the caller already holds it (planning the whole store is the
    expensive part of this rule); computed here otherwise."""
    problems: list[str] = []
    if planned is None:
        try:
            planned = generate.plan(store, generate.vectors_rows(root))
        except ValueError as exc:
            return [f"regenerate: {exc}"]
    for rel, text in sorted(planned.items()):
        path = addon_dir / rel
        if path.is_dir():
            problems.append(f"regenerate: {rel} is a directory; remove it")
        elif not path.is_file():
            problems.append(f"regenerate: {rel} missing; run `make generate`")
        elif not generate.same_bytes(path, text):
            problems.append(
                f"regenerate: {rel} differs from a regeneration; run `make generate`, never hand-edit"
            )
    for rel in sorted(generate.generated_on_disk(addon_dir) - set(planned)):
        problems.append(f"regenerate: {rel} is not produced by generate; delete it")
    toc_path = addon_dir / generate.TOC_NAME
    toc = toc_path.read_bytes().decode("utf-8")
    try:
        if generate.toc_with_block(toc, generate.toc_files(planned)) != toc:
            problems.append(f"regenerate: {generate.TOC_NAME} generated block differs; run `make generate`")
    except ValueError as exc:
        problems.append(f"regenerate: {exc}")
    return problems


def rule_numbers(store: Store, text: str) -> list[str]:
    """Rule 5, the meaning numbers (ADR-060): the numbers file on disk is the one generate would write, so
    every shipped meaning has its number. Read only: `make generate` is what adds numbers."""
    path = generate.numbers_path(store)
    on_disk = path.read_bytes().decode("utf-8") if path.is_file() else None
    if not text or on_disk == text:
        return []
    if on_disk is None:
        return [f"regenerate: data/reading/{glosses.NUMBERS_FILE} missing; run `make generate`"]
    added = len(glosses.parse_numbers(text)[0]) - len(glosses.parse_numbers(on_disk)[0])
    if added > 0:
        return [f"regenerate: {added} meanings have no number in {glosses.NUMBERS_FILE}; run `make generate`"]
    hint = "run `make generate`, never hand-edit"
    return [f"regenerate: {glosses.NUMBERS_FILE} differs from a regeneration; {hint}"]


def validate(
    root: Path,
    addon_dir: Path,
    base: str | None,
    planned: dict[str, str] | None = None,
    numbers: str | None = None,
) -> list[str]:
    """`planned` / `numbers`: the store's plan and its numbers file text (report `meaning_numbers`) when the
    caller already holds them; computed here otherwise."""
    if planned is not None and numbers is None:
        raise ValueError("validate: a caller passing `planned` passes its `meaning_numbers` too")
    store, english = Store(root), Store(root, english=True)
    if planned is None:
        report: dict[str, Any] = {}
        try:
            planned = generate.plan(store, generate.vectors_rows(root), report)
            numbers = report.get("meaning_numbers", "")
        except ValueError:
            planned = None  # rule_regenerate reports it
    problems = rule_schema(root, store, english)
    problems += rule_provenance(root, store, base)
    problems += rule_collisions(english)
    problems += rule_referential(store, english)
    problems += rule_regenerate(root, store, addon_dir, planned)
    if numbers is not None:
        problems += rule_numbers(store, numbers)
    problems += rule_placeholders(store)
    problems += rule_ui(
        store, english, ui_arg_kinds(addon_dir), ui_chat_families(addon_dir), ui_own(addon_dir)
    )
    problems += rule_objective(store)
    problems += rule_readings(store)
    return problems


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj validate")
    p.add_argument("--base", default=None, help="git ref to check the human-never-overwritten rule against")
    p.add_argument("--addon", type=Path, default=None)
    a = p.parse_args(list(argv))
    root = data_root()
    addon_dir = a.addon or generate.default_addon_dir(root)
    problems = validate(root, addon_dir, a.base)
    if problems:
        for line in problems[:100]:
            print(f"validate: {line}")
        if len(problems) > 100:
            print(f"validate: … {len(problems) - 100} more")
        print(f"validate: FAILED with {len(problems)} problem(s)")
        return 1
    shipped = sum(1 for t in check.TYPES for ln in Store(root).load(t) if lua_writer.shipped(ln))
    print(f"validate: ok ({shipped} shipped lines; base={a.base or 'none'})")
    return 0
