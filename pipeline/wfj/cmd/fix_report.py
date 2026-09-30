"""wfj report check|intake|apply: a player's fix report, from the GitHub issue to data/
(ADR-045; docs/systems/fix-reports.md, runbook docs/operations/fix-reports.md).

  check --body-file FILE
      Reads the report in an issue body and prints a markdown summary for the issue comment (the
      report-check workflow posts it). Exit 0 when the report reads (fixes for lines that changed since, or
      that the data does not have, are listed, not failures), 1 when it does not, 3 on an internal error
      (the workflow comments and labels only on 0 / 1). Every value the player wrote is echoed inside a code
      span, so the comment renders no link, image or @mention of theirs. Never writes anything.
  intake (--issue N | --file FILE --number N) [--credit NAME] [--force]
      Reads the report (`gh issue view N`, or a saved issue body), finds each fix's line and writes
      batches/reports/issue-N/: triage.jsonl (one row per fix still about the Japanese that ships: the line,
      its English, its Japanese and who wrote it, the player's reason / note / suggestion, the credit name),
      skipped.jsonl (the rest, with why), report.txt and meta.json. The credit is the issue form's
      "Credit me as", else the issue author's GitHub login: letters, digits, spaces and `._-` only (it
      ships in ATTRIBUTION.md). The form's Permission box is recorded; `apply` refuses to ship a player's
      Japanese without it. A line this report already rewrote still matches, so intake can run again after
      apply.
      The four files are written, then moved into place together.
  apply --issue N --model MODEL [--date YYYY-MM-DD] [--by WHO] [--dry-run]
      Takes batches/reports/issue-N/decisions.jsonl (written by the drafting pass), one row per triaged
      fix: `use` (the player's Japanese), `rewrite` (the model's own) or `keep`. It checks every row first
      and writes nothing if any is wrong, then writes the lines
      (provenance per ADR-045), checks that each changed line ships its new Japanese, imports the lines'
      words as their readings (batch report-N), updates ATTRIBUTION.md's correctors and writes reply.md.
      Running it again changes nothing.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import unicodedata
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from wfj.cmd.check import Included, check_type, scopes_for
from wfj.cmd.readings import import_rows
from wfj.core import decisions, fix_report, public_text, readings, style
from wfj.core.align import load_allowlist
from wfj.dev import gen_attribution
from wfj.emit.lua_writer import shipped
from wfj.io import private_rules
from wfj.io.jsonl_store import Store, dumps
from wfj.paths import allowlist_path, data_root

DECISIONS = ("use", "rewrite", "keep")
ROW_KEYS = {"type", "id", "field", "decision", "ja", "note", "words"}
REASON_TEXT = {
    "wrong": "wrong meaning",
    "awkward": "awkward / unnatural",
    "typo": "typo / broken text",
    "name": "a name was changed",
    "other": "other",
}
SKIP_TEXT = {
    fix_report.ALREADY_CHANGED: "this line was changed after your game build, nothing to do",
    fix_report.NOT_SHIPPING: "this line is not shipped in Japanese any more",
    fix_report.NO_LINE: "this line was not found in the data (a newer or older build?)",
}
_NO_RESPONSE = "_No response_"
CREDIT_MAX = 40
ECHO_MAX = 120  # characters of player text echoed in the issue comment
EXIT_INTERNAL = 3


# --- issue body -----------------------------------------------------------------------------------


def form_sections(body: str) -> dict[str, str]:
    """An issue-form body's `### <label>` sections → {label: text} (`_No response_` → "")."""
    out: dict[str, str] = {}
    label, buf = None, []
    for raw in body.replace("\r\n", "\n").split("\n"):
        if raw.startswith("### "):
            if label is not None:
                out[label] = "\n".join(buf).strip()
            label, buf = raw[4:].strip(), []
        elif label is not None:
            buf.append(raw)
    if label is not None:
        out[label] = "\n".join(buf).strip()
    return {k: ("" if v == _NO_RESPONSE else v) for k, v in out.items()}


def unpublishable(text: str) -> str:
    """The public-check rules `text` would break once written into data/ or ATTRIBUTION.md, joined; empty
    when it can be published. Checked before anything is written, so a report never turns CI red."""
    rules = private_rules.load(Path(__file__).resolve().parents[3])
    return ", ".join(sorted({h.rule for h in public_text.content_hits(text, in_data=True, rules=rules)}))


def clean_credit(name: str) -> str:
    """A credit name as it ships (a translator, an ATTRIBUTION.md line): letters of any script,
    digits, spaces and `._-` only, so no markdown, HTML, link, `@` or invisible format character; runs of
    spaces collapse; at most CREDIT_MAX characters."""
    kept = "".join(
        ch for ch in name if unicodedata.category(ch)[0] in "LN" or ch in " ._-"
    )
    return " ".join(kept.split())[:CREDIT_MAX].strip()


def consented(body: str) -> bool:
    """Whether the issue form's Permission box is ticked (`- [X] …`). Read at intake, not only when the form
    was sent: the author can edit the body afterwards."""
    text = form_sections(body).get("Permission", "")
    return any(ln.strip().lower().startswith("- [x]") for ln in text.splitlines())


def code(value: object) -> str:
    """A player's value, safe in the issue comment: inside a code span (no link, image or HTML renders), no
    backticks to break out, `@` made full-width so it mentions no one, and cut to ECHO_MAX."""
    s = " ".join(str(value).replace("`", "'").replace("@", "＠").split())
    if len(s) > ECHO_MAX:
        s = s[: ECHO_MAX - 1] + "…"
    return f"`{s}`" if s else "`-`"


# --- resolving ------------------------------------------------------------------------------------


def resolve_all(
    root: Path, rep: fix_report.Report, issue: int | None = None
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """→ (triaged, skipped): each fix of `rep` with its line, or with the reason it has none."""
    store, english = Store(root), Store(root, english=True)
    lines_by: dict[str, list[dict[str, Any]]] = {}
    en_by: dict[str, dict[tuple[Any, str], str]] = {}
    triaged, skipped = [], []
    for n, fix in enumerate(rep.fixes, 1):
        if fix.type not in lines_by:
            lines_by[fix.type] = store.load(fix.type)
            en_by[fix.type] = {(ln["id"], ln["field"]): ln["en"] for ln in english.load(fix.type)}
        line, why = fix_report.resolve(fix, lines_by[fix.type], issue)
        base = {"n": n, "type": fix.type}
        if line is None:
            skipped.append(base | {"id": fix.id, "field": fix.field, "reason": fix.reason, "skip": why})
            continue
        row = base | {"id": line["id"], "field": line["field"]}
        if line["id"] != fix.id:
            row["report_id"] = fix.id  # a book page: the addon keys it by its English hash
        row |= {
            "reason": fix.reason,
            "note": fix.note,
            "suggestion": fix.ja,
            "en": en_by[fix.type].get((line["id"], line["field"]), ""),
            "ja": line["ja"],
            "class": line["provenance"]["class"],
        }
        triaged.append(row)
    return triaged, skipped


# --- check ----------------------------------------------------------------------------------------


def _cell(s: str) -> str:
    return s.replace("|", "\\|").replace("\n", " ")


def summary(body: str, root: Path) -> tuple[bool, str]:
    """→ (ok, markdown) for the issue comment."""
    try:
        rep = fix_report.parse(body)
    except fix_report.ReportError as e:
        return False, (
            f"**This report could not be read:** {code(e)}\n\n"
            "Copy the report again in the game (the minimap button, then **Send report**), then edit this "
            "issue "
            "and paste it over the old one. The check runs again when the issue is edited.\n"
        )
    if not rep.fixes:
        return (
            False,
            "**This report holds no fixes.** Save a fix in the game first, then copy the report again.\n",
        )
    triaged, skipped = resolve_all(root, rep)
    rows = [(r["n"], "ready") for r in triaged] + [(r["n"], SKIP_TEXT[r["skip"]]) for r in skipped]
    out = [
        f"**Report read: {len(rep.fixes)} fix(es)** (addon {code(rep.addon)}, client {code(rep.client)}). "
        "Thank you, the maintainer takes it from here.",
        "",
        "| # | Line | Reason | Your Japanese | Status |",
        "|---|---|---|---|---|",
    ]
    for n, status in sorted(rows):
        fix = rep.fixes[n - 1]
        out.append(
            f"| {n} | {fix.type} {code(fix.id)} · {fix.field} | {REASON_TEXT[fix.reason]} | "
            f"{'yes' if fix.ja else '-'} | {_cell(status)} |"
        )
    out.append("")
    out.append(
        "_This check only reads the report; whether a translation is right is decided when the report "
        "is taken._"
    )
    return True, "\n".join(out) + "\n"


# --- apply ----------------------------------------------------------------------------------------


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows = []
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if raw.strip():
            row = json.loads(raw)
            if not isinstance(row, dict):
                raise ValueError(f"{path.name}:{n}: a row is a JSON object")
            rows.append(row)
    return rows


def _key(row: dict[str, Any]) -> tuple[Any, Any, Any]:
    return (row.get("type"), row.get("id"), row.get("field"))


def needs_words(type_: str, ja: str) -> bool:
    """A changed quest / gossip / ui / plain-book line gets its readings with meanings in the same apply."""
    # a line holding `|` (a colour code or any escape) is never owed one: the word box refuses it (validate)
    return (
        type_ in readings.TYPES
        and readings.annotatable(ja)
        and not readings.html_page(type_, ja)
        and "|" not in ja
    )


def is_applied(line: dict[str, Any] | None, row: dict[str, Any], issue: int) -> bool:
    return (
        line is not None
        and row.get("decision") in ("use", "rewrite")
        and line.get("ja") == row.get("ja")
        and line["provenance"].get("report") == issue
    )


def check_decisions(
    triage: list[dict[str, Any]],
    rows: list[dict[str, Any]],
    lines_by: dict[str, list[dict[str, Any]]],
    issue: int,
) -> list[str]:
    """Every problem with the decisions (empty = apply them). Nothing is written when there is one."""
    p: list[str] = []
    want = {_key(t): t for t in triage}
    seen: set[tuple[Any, Any, Any]] = set()
    by_line = {t: {(ln["id"], ln["field"]): ln for ln in lines} for t, lines in lines_by.items()}
    for n, row in enumerate(rows, 1):
        k = _key(row)
        where = f"decisions row {n} ({k[0]} {k[1]}/{k[2]})"
        extra = set(row) - ROW_KEYS
        if extra:
            p.append(f"{where}: unexpected keys {sorted(extra)}")
        if k in seen:
            p.append(f"{where}: decided twice")
            continue
        seen.add(k)
        t = want.get(k)
        if t is None:
            p.append(f"{where}: not a triaged fix of this report")
            continue
        line = by_line.get(k[0], {}).get((k[1], k[2]))
        p += _decision_problems(where, k[0], row, t, line, issue)
    for k in want:
        if k not in seen:
            p.append(f"no decision for {k[0]} {k[1]}/{k[2]}")
    return p


def _decision_problems(
    where: str, type_: str, row: dict[str, Any], t: dict[str, Any], line: dict[str, Any] | None, issue: int
) -> list[str]:
    """The problems with one row's decision, its ja and its note, then with the change it makes."""
    p: list[str] = []
    d = row.get("decision")
    if d not in DECISIONS:
        return [f"{where}: decision must be one of {DECISIONS}"]
    ja = row.get("ja")
    if d == "keep":
        if "ja" in row:
            p.append(f"{where}: `keep` carries no ja")
    elif not (isinstance(ja, str) and ja.strip()):
        return [f"{where}: `{d}` needs the new ja"]
    elif blocked := unpublishable(ja):
        p.append(f"{where}: the ja cannot go into the public data ({blocked})")
    if not str(row.get("note", "")).strip():
        p.append(f"{where}: every decision carries a note (it goes in the reply to the player)")
    elif blocked := unpublishable(str(row["note"])):
        p.append(f"{where}: the note cannot go into the public data ({blocked})")
    if d == "use" and not t.get("suggestion"):
        p.append(f"{where}: `use` on a fix with no Japanese from the player; `rewrite` or `keep`")
    if d == "use" and not t.get("consent"):
        p.append(f"{where}: `use` but the issue's Permission box is not ticked; `rewrite` or `keep`")
    if d == "keep":
        if "words" in row:
            p.append(f"{where}: `keep` carries no words")
        return p
    return p + _change_problems(where, type_, row, t, line, issue)


def _change_problems(
    where: str, type_: str, row: dict[str, Any], t: dict[str, Any], line: dict[str, Any] | None, issue: int
) -> list[str]:
    """The problems with a `use` / `rewrite` row against the line it changes and the readings it carries."""
    if is_applied(line, row, issue):
        return []  # applied by an earlier run
    p: list[str] = []
    ja = row.get("ja")
    if ja == t["ja"]:
        p.append(f"{where}: the new ja is the Japanese that already ships; that is a `keep`")
    if line is None or line.get("ja") != t["ja"]:
        p.append(f"{where}: the line's Japanese changed since intake; run intake again")
    if needs_words(type_, ja):
        bad = readings.word_problems(ja, row.get("words"))
        p += [f"{where}: words: {x}" for x in bad]
    elif "words" in row:
        p.append(f"{where}: this line takes no readings, so no words")
    return p


def _ruling_note(issue: int) -> str:
    return f"fix report #{issue}"


def write_row(
    line: dict[str, Any], row: dict[str, Any], t: dict[str, Any], meta: dict[str, Any], ctx: dict[str, Any]
) -> str:
    """Edit `line` in place for one `use` / `rewrite` row → "correction" | "machine"."""
    issue, date, model_id = ctx["issue"], ctx["date"], ctx["model"]
    why = f"{_ruling_note(issue)} ({REASON_TEXT[t['reason']]}): {row['note']}"
    protected = any(
        decisions.is_hand_written(v["provenance"]) and not decisions.is_rejected(v)
        for v in decisions.variant_dicts(line)
    )
    if row["decision"] == "rewrite" and decisions.is_machine(line["provenance"]) and not protected:
        # machine replaces machine (ADR-014): the shipped draft is rewritten in place under the current style
        # guide, so no older draft beside it outranks it
        styled = line["field"] in style.STYLED_FIELDS.get(t["type"], frozenset())
        name = f"report-{issue}" + (f"-sg{ctx['style']}" if styled else "")
        line["ja"] = row["ja"]
        line["provenance"] = {
            "class": "machine",
            "model": model_id,
            "source": f"{name}@{date}",
            "imported": date,
            "report": issue,
        }
        line.pop("ruling", None)
        line.pop("extra", None)
        return "machine"
    old = {key: line[key] for key in ("ja", "provenance", "extra", "ruling") if line.get(key) is not None}
    corrects = old["provenance"]["source"]
    if decisions.is_correction(old["provenance"]):
        old["ruling"] = {
            "ruling": "reject",
            "by": ctx["by"],
            "date": date,
            "note": f"superseded by the correction from {_ruling_note(issue)}",
        }
        corrects = old["provenance"]["corrects"]
    if row["decision"] == "use":
        translator = meta["credit"]
        note = f"{why} (the player's Japanese; approved by the {ctx['by']})"
    else:
        # a person's line is corrected in their name, as dev/apply_review does; a machine line a
        # hand-written variant still guards is corrected under the report's ruling
        translator = old["provenance"].get("translator") or "the maintainer"
        note = f"{why} (written by {model_id}; approved by the {ctx['by']})"
    prov: dict[str, Any] = {
        "class": "correction",
        "translator": translator,
        "source": f"correction@{date}",
        "imported": date,
        "corrects": corrects,
        "note": note,
        "report": issue,
    }
    if row["decision"] == "rewrite":
        prov["model"] = model_id
    line["conflicts"] = [old, *line["conflicts"]]
    line["ja"], line["provenance"] = row["ja"], prov
    line.pop("extra", None)
    line.pop("ruling", None)
    return "correction"


def correctors(root: Path) -> dict[str, list[int]]:
    """Every player whose own Japanese a fix report brought in (a `correction` with `report` and no `model`,
    shipped or since superseded) → their report numbers."""
    out: dict[str, set[int]] = {}
    store = Store(root)
    for type_ in fix_report.TYPES:
        for line in store.load(type_):
            for v in decisions.variant_dicts(line):
                prov = v["provenance"]
                if decisions.is_correction(prov) and "report" in prov and "model" not in prov:
                    out.setdefault(prov["translator"], set()).add(prov["report"])
    return {k: sorted(v) for k, v in out.items()}


def reply_text(
    issue: int, triage: list[dict[str, Any]], rows: list[dict[str, Any]], skipped: list[dict[str, Any]]
) -> str:
    by = {_key(r): r for r in rows}
    items: list[tuple[int, str, str]] = []
    for t in triage:
        r = by[_key(t)]
        line = f"{t['type']} {t.get('report_id', t['id'])} · {t['field']}"
        if r["decision"] == "use":
            res = f"**Changed**: your Japanese ships. {r['note']}"
        elif r["decision"] == "rewrite":
            res = f"**Changed**: rewritten. {r['note']}"
        else:
            res = f"**Kept**: {r['note']}"
        items.append((t["n"], line, res))
    for s in skipped:
        items.append(
            (s["n"], f"{s['type']} {s['id']} · {s['field']}", f"**Skipped**: {SKIP_TEXT[s['skip']]}")
        )
    out = [
        f"Thank you for the report! Here is what happened to each line (report #{issue}):",
        "",
        "| # | Line | Result |",
        "|---|---|---|",
    ]
    out += [f"| {n} | {_cell(line)} | {_cell(res)} |" for n, line, res in sorted(items)]
    changed = sum(1 for r in rows if r["decision"] in ("use", "rewrite"))
    out += ["", "The changes ship in the next release." if changed else "Nothing needed changing this time."]
    return "\n".join(out) + "\n"


def _write_rows(
    rows: list[dict[str, Any]],
    lines_by: dict[str, list[dict[str, Any]]],
    want: dict[tuple[Any, Any, Any], dict[str, Any]],
    meta: dict[str, Any],
    ctx: dict[str, Any],
) -> tuple[dict[str, int], dict[str, dict[tuple[Any, str], str]]]:
    """Edit the loaded lines for every decision → (counts per outcome, new ja per changed line by type)."""
    counts = {"correction": 0, "machine": 0, "keep": 0, "already": 0}
    changed: dict[str, dict[tuple[Any, str], str]] = {}
    for row in rows:
        k = _key(row)
        if row["decision"] == "keep":
            counts["keep"] += 1
            continue
        line = next(ln for ln in lines_by[k[0]] if ln["id"] == k[1] and ln["field"] == k[2])
        if is_applied(line, row, ctx["issue"]):
            counts["already"] += 1
            continue
        counts[write_row(line, row, want[k], meta, ctx)] += 1
        changed.setdefault(k[0], {})[(k[1], k[2])] = row["ja"]
    return counts, changed


def _check_changed(
    root: Path,
    store: Store,
    english: Store,
    lines_by: dict[str, list[dict[str, Any]]],
    changed: dict[str, dict[tuple[Any, str], str]],
    problems: list[str],
) -> dict[str, list[dict[str, Any]]]:
    """Re-check every changed type → its checked lines; a changed line that won't ship goes in `problems`."""
    allowlist = load_allowlist(allowlist_path(root).read_text(encoding="utf-8"))
    included = Included(english)
    checked: dict[str, list[dict[str, Any]]] = {}
    for type_, keys in changed.items():
        out = check_type(lines_by[type_], scopes_for(english, store, type_), allowlist, included)
        for ln in out:
            ja = keys.get((ln["id"], ln["field"]))
            if ja is not None and not (shipped(ln) and ln["ja"] == ja):
                problems.append(
                    f"{type_} {ln['id']}/{ln['field']}: the new Japanese would not ship "
                    f"(status {ln['status']}, reasons {ln['reasons']})"
                )
        checked[type_] = out
    return checked


def apply(root: Path, issue: int, model_id: str, date: str, by: str, dry_run: bool) -> int:
    folder = batch_dir(root, issue)
    meta = json.loads((folder / "meta.json").read_text(encoding="utf-8"))
    triage = read_jsonl(folder / "triage.jsonl")
    skipped = read_jsonl(folder / "skipped.jsonl") if (folder / "skipped.jsonl").is_file() else []
    rows = read_jsonl(folder / "decisions.jsonl")
    store, english = Store(root), Store(root, english=True)
    types = sorted({t["type"] for t in triage})
    lines_by = {t: store.load(t) for t in types}
    problems = check_decisions(triage, rows, lines_by, issue)
    if problems:
        for x in problems:
            print(f"  {x}")
        print(f"report apply: {len(problems)} problem(s); nothing written")
        return 1
    ctx = {
        "issue": issue,
        "date": date,
        "model": model_id,
        "by": by,
        "style": style.guide_version(root.parent),
    }
    want = {_key(t): t for t in triage}
    counts, changed = _write_rows(rows, lines_by, want, meta, ctx)
    checked = _check_changed(root, store, english, lines_by, changed, problems)
    if problems:
        for x in problems:
            print(f"  {x}")
        print(f"report apply: {len(problems)} line(s) would not ship, nothing written; fix the decisions")
        return 1
    words = [
        {
            "type": r["type"],
            "id": r["id"],
            "field": r["field"],
            "ja_hash": readings.ja_hash(r["ja"]),
            "words": r["words"],
        }
        for r in rows
        if "words" in r
    ]
    verb = "would write" if dry_run else "wrote"
    if not dry_run:
        for type_, out in checked.items():
            store.save(type_, out)
        prov = {"class": "machine", "model": model_id, "source": f"readings@report-{issue}", "imported": date}
        result = import_rows(root, words, prov)
        for x in result["rejected"]:
            print(f"  readings rejected {x}")
        for x in result["kept"]:
            print(f"  {x}")
        if result["rejected"]:
            print(
                "report apply: the lines are written but some readings were rejected; fix them and run again"
            )
            return 1
        attribution = root.parent / "ATTRIBUTION.md"
        text = attribution.read_text(encoding="utf-8")
        new = gen_attribution.with_correctors(text, correctors(root))
        if new != text:
            attribution.write_text(new, encoding="utf-8")
        (folder / "reply.md").write_text(reply_text(issue, triage, rows, skipped), encoding="utf-8")
    print(
        f"report apply{' (dry run)' if dry_run else ''}: {verb} {counts['correction']} correction(s) · "
        f"{counts['machine']} machine rewrite(s) · kept {counts['keep']} · "
        f"already applied {counts['already']} "
        f"· readings for {len(words)} line(s)"
    )
    return 0


# --- intake ---------------------------------------------------------------------------------------


def batch_dir(root: Path, issue: int) -> Path:
    return root.parent / "batches" / "reports" / f"issue-{issue}"


class IssueError(RuntimeError):
    """The issue could not be read with the GitHub CLI."""


def fetch_issue(issue: int) -> tuple[str, str]:
    """→ (body, author login) via the GitHub CLI. Raises IssueError with the CLI's message."""
    try:
        done = subprocess.run(
            ["gh", "issue", "view", str(issue), "--json", "body,author"],
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        raise IssueError("the GitHub CLI `gh` is not installed") from None
    if done.returncode != 0:
        raise IssueError((done.stderr or done.stdout).strip() or f"gh exited {done.returncode}")
    try:
        data = json.loads(done.stdout)
    except json.JSONDecodeError as e:
        raise IssueError(f"gh returned no JSON ({e})") from None
    return data.get("body") or "", (data.get("author") or {}).get("login") or ""


def _write_together(folder: Path, files: dict[str, str]) -> None:
    """Every file written under a temporary name first, then all moved into place: a failure part way leaves
    the folder as it was."""
    folder.mkdir(parents=True, exist_ok=True)
    temps = []
    try:
        for name, text in files.items():
            tmp = folder / f".{name}.tmp"
            tmp.write_text(text, encoding="utf-8")
            temps.append((tmp, folder / name))
    except OSError:
        for tmp, _ in temps:
            tmp.unlink(missing_ok=True)
        raise
    for tmp, final in temps:
        os.replace(tmp, final)


def intake(root: Path, issue: int, body: str, author: str, credit: str | None, force: bool) -> int:
    folder = batch_dir(root, issue)
    if (folder / "triage.jsonl").exists() and not force:
        print(
            f"report intake: {folder.relative_to(root.parent)} already has a triage (pass --force to redo it)"
        )
        return 1
    try:
        rep = fix_report.parse(body)
    except fix_report.ReportError as e:
        print(f"report intake: the report does not read: {e}")
        return 1
    name = clean_credit(credit if credit is not None else form_sections(body).get("Credit me as", ""))
    name = name or clean_credit(author) or "a player"
    if blocked := unpublishable(name):
        print(f"report intake: credit {name!r} cannot be published ({blocked}); give another with --credit")
        return 1
    consent = consented(body)
    triaged, skipped = resolve_all(root, rep, issue)
    meta = {"issue": issue, "credit": name, "consent": consent, "addon": rep.addon, "client": rep.client}
    _write_together(
        folder,
        {
            "report.txt": fix_report.render(rep),
            "meta.json": json.dumps(meta, ensure_ascii=False, indent=2) + "\n",
            "triage.jsonl": "".join(dumps(r | {"credit": name, "consent": consent}) + "\n" for r in triaged),
            "skipped.jsonl": "".join(dumps(r) + "\n" for r in skipped),
        },
    )
    print(
        f"report intake: {len(triaged)} fix(es) to decide · {len(skipped)} skipped · credit {name!r} → "
        f"{folder.relative_to(root.parent)}"
        + ("" if consent else " · the Permission box is NOT ticked: no `use` decision can ship")
    )
    return 0


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj report")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="read an issue body's report; print the summary comment")
    c.add_argument("--body-file", required=True, type=Path)
    i = sub.add_parser("intake", help="an issue's report → batches/reports/issue-N/triage.jsonl")
    src = i.add_mutually_exclusive_group(required=True)
    src.add_argument("--issue", type=int, help="read the issue with `gh issue view`")
    src.add_argument("--file", type=Path, help="a saved issue body (needs --number)")
    i.add_argument("--number", type=int, help="with --file: the issue number")
    i.add_argument(
        "--credit", help="the name to credit (default: the form's 'Credit me as', else the author)"
    )
    i.add_argument("--force", action="store_true", help="redo an existing triage")
    a_ = sub.add_parser("apply", help="decisions.jsonl → data/, readings, ATTRIBUTION.md, reply.md")
    a_.add_argument("--issue", required=True, type=int)
    a_.add_argument("--model", required=True, help="the model id that drafted the decisions")
    a_.add_argument("--date", default=dt.date.today().isoformat())
    a_.add_argument("--by", default="maintainer", help="who approved the report (ruling `by`)")
    a_.add_argument("--dry-run", action="store_true")
    a = p.parse_args(list(argv))
    root = data_root()
    if a.cmd == "check":
        try:
            ok, text = summary(a.body_file.read_text(encoding="utf-8"), root)
        except Exception as e:  # the workflow must tell a crash from a broken report
            print(f"report check: internal error: {type(e).__name__}: {e}", file=sys.stderr)
            return EXIT_INTERNAL
        print(text, end="")
        return 0 if ok else 1
    if a.cmd == "intake":
        if a.file is not None:
            if a.number is None or a.number <= 0:
                p.error("--file needs --number (the issue number)")
            return intake(root, a.number, a.file.read_text(encoding="utf-8"), "", a.credit, a.force)
        try:
            body, author = fetch_issue(a.issue)
        except IssueError as e:
            print(f"report intake: could not read issue #{a.issue}: {e}")
            return 1
        return intake(root, a.issue, body, author, a.credit, a.force)
    return apply(root, a.issue, a.model, a.date, a.by, a.dry_run)
