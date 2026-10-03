"""wfj collector check|intake: a player's collector send, from the GitHub issue to data/english/
(ADR-056; docs/systems/collector.md, runbook docs/operations/collector-sends.md).

  check --body-file FILE
      Reads the send in an issue body (the string the game packed, or the SavedVariables file attached when
      the string was too long to paste) and prints a markdown summary for the issue comment (the
      collector-check workflow posts it): entries by kind, builds, addon version, rejected entries by reason.
      It never prints the English. Exit 0 when the send reads and holds at least one valid entry, 1 when it
      does not, 3 on an internal error (the workflow comments and labels only on 0 / 1). Writes nothing.
  intake (--issue N | --file FILE --number N)
      Reads the send (`gh issue view N`, or a saved issue body), refuses it unless the form's Permission box
      is ticked, and merges it into data/english/ with the same rules as `wfj import english collector`.
      Importing the same send again changes nothing.
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter
from collections.abc import Callable, Sequence
from pathlib import Path

from wfj.cmd.fix_report import IssueError, consented, fetch_issue, form_sections
from wfj.cmd.import_english import import_dump
from wfj.io.collector_send import Send, SendError, decode, fetch_attachment, find, read_file

EXIT_INTERNAL = 3
NONE_FOUND = (
    "No collected English found. The form's box should hold the text from the game's send window "
    "(it starts with `WFJC1:`), or the attached file."
)


def read_send(body: str, download: Callable[[str], bytes] = fetch_attachment) -> Send:
    """An issue body → the send it carries. Raises SendError when there is none or it does not read."""
    text, attachment = find(body, form_sections(body))
    if text is not None:
        return decode(text)
    if attachment is not None:
        return read_file(attachment, download(attachment))
    raise SendError(NONE_FOUND)


def summary(body: str, download: Callable[[str], bytes] = fetch_attachment) -> tuple[bool, str]:
    """→ (ok, markdown) for the issue comment. Counts only: no English text, no player value."""
    try:
        send = read_send(body, download)
    except SendError as e:
        return False, (
            f"**This send could not be read.** {e}\n\n"
            "Open the send window again in the game (`/wfj collector send all`), copy the link or the text "
            "again, and edit this issue with it. The check runs again when the issue is edited.\n"
        )
    dump = send.dump
    kinds = Counter(en.type_ for en in dump.entries)
    builds = sorted({en.build for en in dump.entries})
    lines = [
        "**This send reads.**" if dump.entries else "**This send holds no line that can be imported.**",
        "",
        "| | |",
        "|---|---|",
        f"| Entries | {len(dump.entries)} |",
    ]
    for kind in sorted(kinds):
        lines.append(f"| {kind} | {kinds[kind]} |")
    shown = ", ".join(builds[:5]) + (f" and {len(builds) - 5} more" if len(builds) > 5 else "")
    lines.append(f"| Builds | {shown or '-'} |")
    if send.addon:
        lines.append(f"| Addon version | `{_safe(send.addon)}` |")
    sent_as = "the text from the game" if send.source == "string" else "the attached file"
    lines.append(f"| Sent as | {sent_as} |")
    if dump.rejected:
        rejected = ", ".join(f"{r} {n}" for r, n in sorted(dump.rejected.items()))
        lines.append(f"| Left out | {rejected} |")
    return bool(dump.entries), "\n".join(lines) + "\n"


def _safe(s: str) -> str:
    """A player's value inside a code span: no backtick to break out, no `@` mention, at most 40 chars."""
    return " ".join(s.replace("`", "'").replace("@", "＠").replace("|", "/").split())[:40]


def intake(issue: int, body: str) -> int:
    if not consented(body):
        print(f"collector intake: issue #{issue}: the Permission box is not ticked; nothing imported")
        return 1
    try:
        send = read_send(body)
    except SendError as e:
        print(f"collector intake: issue #{issue}: {e}")
        return 1
    return import_dump(send.dump, f"issue #{issue}")


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj collector")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="read an issue body's send; print the summary comment")
    c.add_argument("--body-file", required=True, type=Path)
    i = sub.add_parser("intake", help="an issue's send → data/english/")
    src = i.add_mutually_exclusive_group(required=True)
    src.add_argument("--issue", type=int, help="read the issue with `gh issue view`")
    src.add_argument("--file", type=Path, help="a saved issue body (needs --number)")
    i.add_argument("--number", type=int, help="with --file: the issue number")
    a = p.parse_args(list(argv))
    if a.cmd == "check":
        try:
            ok, text = summary(a.body_file.read_text(encoding="utf-8"))
        except Exception as e:  # the workflow must tell a crash from a broken send
            print(f"collector check: internal error: {type(e).__name__}: {e}", file=sys.stderr)
            return EXIT_INTERNAL
        print(text, end="")
        return 0 if ok else 1
    if a.file is not None:
        if a.number is None or a.number <= 0:
            p.error("--file needs --number (the issue number)")
        return intake(a.number, a.file.read_text(encoding="utf-8"))
    try:
        body, _ = fetch_issue(a.issue)
    except IssueError as e:
        print(f"collector intake: could not read issue #{a.issue}: {e}")
        return 1
    return intake(a.issue, body)
