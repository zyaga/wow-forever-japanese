"""wfj release: the changelog and version side of a release (docs/operations/release.md).

  wfj release next-version [--version X.Y.Z]
      Print `version=<X.Y.Z>` and `resume=<true|false>` (lines a workflow can append to $GITHUB_OUTPUT).
      Without --version the version follows the rule in docs/operations/release.md; with it, that
      version is checked and used.
      resume=true when HEAD is already tagged v<version>: a release whose publish step failed is re-run.
  wfj release changelog --version X.Y.Z --date YYYY-MM-DD --notes PATH
      Move `## Unreleased` under `## X.Y.Z - date`, leave an empty `## Unreleased` above it, and write that
      version's notes to PATH (the packager's changelog).
  wfj release notes --version X.Y.Z --notes PATH
      Write an already-released version's notes to PATH (for a resumed release).
  wfj release changelog-gate --base REF
      The pull-request gate: a change to addon/ or data/ adds a line under `## Unreleased`; released sections
      are never edited; added lines name no local path and nothing the private rules name.

The changelog is CHANGELOG.md at the repo root, in the Keep a Changelog shape plus a `### Breaking` group.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import Counter
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

from wfj.core import public_text
from wfj.io import private_rules

CHANGELOG = "CHANGELOG.md"
UNRELEASED = "Unreleased"
FIRST_VERSION = "0.1.0-alpha.1"
SHIPPED_PATHS = ("addon/", "data/")

_NUM = r"(0|[1-9]\d*)"  # SemVer: no leading zeros
VERSION_RE = re.compile(rf"^{_NUM}\.{_NUM}\.{_NUM}(?:-(alpha|beta)\.{_NUM})?$")
# The text after `## `: `Unreleased`, or a released `1.2.3 - YYYY-MM-DD`.
TITLE_RE = re.compile(r"^(\S+)(?:\s+-\s+(\d{4}-\d{2}-\d{2}))?\s*$")
GROUP_RE = re.compile(r"^### (\S.*?)\s*$")
GROUPS = ("Added", "Changed", "Fixed", "Removed", "Breaking")
# A public changelog line names no path on someone's machine.
LOCAL_PATH_RE = re.compile(r"/(?:Users|home)/|~/|\b[A-Za-z]:\\", re.IGNORECASE)


class ReleaseError(Exception):
    pass


@dataclass
class Section:
    title: str  # "Unreleased" or a version
    date: str | None
    lines: list[str] = field(default_factory=list)  # the body, headings of groups included
    malformed: bool = False  # a `## ` line that is neither `Unreleased` nor `X.Y.Z - date` (kept verbatim)

    def entries(self) -> list[str]:
        return [ln for ln in self.lines if ln.startswith("- ")]

    def group_entries(self, group: str) -> list[str]:
        out: list[str] = []
        current = None
        for ln in self.lines:
            m = GROUP_RE.match(ln)
            if m:
                current = m.group(1)
            elif ln.startswith("- ") and current == group:
                out.append(ln)
        return out


@dataclass
class Changelog:
    preamble: list[str]
    sections: list[Section]

    @property
    def unreleased(self) -> Section:
        for s in self.sections:
            if s.title == UNRELEASED:
                return s
        raise ReleaseError(f"{CHANGELOG} has no '## {UNRELEASED}' section")

    def released(self) -> list[Section]:
        return [s for s in self.sections if s.title != UNRELEASED]

    def find(self, version: str) -> Section | None:
        return next((s for s in self.released() if s.title == version), None)


def parse(text: str) -> Changelog:
    preamble: list[str] = []
    sections: list[Section] = []
    for ln in text.splitlines():
        if ln.startswith("## "):
            m = TITLE_RE.match(ln[3:])
            if m:
                sections.append(Section(m.group(1), m.group(2)))
            else:
                sections.append(Section(ln[3:].strip(), None, malformed=True))
        elif sections:
            sections[-1].lines.append(ln)
        else:
            preamble.append(ln)
    return Changelog(preamble, sections)


def _trim(lines: list[str]) -> list[str]:
    start, end = 0, len(lines)
    while start < end and not lines[start].strip():
        start += 1
    while end > start and not lines[end - 1].strip():
        end -= 1
    return lines[start:end]


def render(log: Changelog) -> str:
    out = list(_trim(log.preamble))
    for s in log.sections:
        heading = f"## {s.title}" + (f" - {s.date}" if s.date else "")
        out += ["", heading]
        body = _trim(s.lines)
        if body:
            out += [""] + body
    return "\n".join(out) + "\n"


def lint(log: Changelog) -> list[str]:
    """Shape problems a release must not run past (empty = ok): one `## Unreleased`, released headings
    `## X.Y.Z - YYYY-MM-DD`, and under Unreleased only `### <group>` headings and `- ` entries in a group."""
    problems: list[str] = []
    count = sum(1 for s in log.sections if s.title == UNRELEASED)
    if count != 1:
        problems.append(f"{CHANGELOG} needs exactly one '## {UNRELEASED}' section (found {count})")
    for s in log.sections:
        if s.title == UNRELEASED and not s.malformed and not s.date:
            continue
        if s.malformed or s.date is None or not VERSION_RE.match(s.title):
            heading = f"## {s.title}" + (f" - {s.date}" if s.date else "")
            problems.append(f"'{heading}' is not '## {UNRELEASED}' or '## X.Y.Z - YYYY-MM-DD'")
    for s in log.sections:
        if s.title != UNRELEASED:
            continue
        group = None
        for ln in s.lines:
            if not ln.strip() or ln.startswith((" ", "\t")):  # blank, or a continuation of the entry above
                continue
            m = GROUP_RE.match(ln)
            if m:
                group = m.group(1)
                if group not in GROUPS:
                    problems.append(f"'### {group}' is not a changelog group (one of: {', '.join(GROUPS)})")
            elif not ln.startswith("- "):
                problems.append(f"under '## {UNRELEASED}', not a '- ' entry: {ln}")
            elif group is None:
                problems.append(f"entry outside a '### <group>' heading: {ln}")
    return problems


def released_drift(log: Changelog, at_tag: Changelog, tag: str) -> list[str]:
    """Released sections must be exactly those at the latest release tag: a pull request merged across a
    release can land its lines inside the section that release wrote."""
    def shape(c: Changelog) -> list[tuple[str, str | None, list[str]]]:
        return [(s.title, s.date, _trim(s.lines)) for s in c.released()]

    if shape(log) != shape(at_tag):
        return [
            f"released sections of {CHANGELOG} differ from {tag} (a change merged across a release?): "
            f"move lines added since {tag} back under '## {UNRELEASED}'"
        ]
    return []


# ── versions ──────────────────────────────────────────────────────────────────


def version_key(v: str) -> tuple[int, int, int, int, int]:
    """SemVer precedence for the versions this project uses: a release sorts after its pre-releases."""
    m = VERSION_RE.match(v)
    if not m:
        raise ReleaseError(f"'{v}' is not a version (expected X.Y.Z, X.Y.Z-alpha.N or X.Y.Z-beta.N)")
    major, minor, patch, kind, n = m.groups()
    rank = {"alpha": 0, "beta": 1, None: 2}[kind]
    return (int(major), int(minor), int(patch), rank, int(n or 0))


def latest(tags: Sequence[str]) -> str | None:
    versions = [t[1:] for t in tags if t.startswith("v") and VERSION_RE.match(t[1:])]
    return max(versions, key=version_key) if versions else None


def next_version(log: Changelog, tags: Sequence[str], override: str | None = None) -> str:
    problems = lint(log)
    if problems:
        raise ReleaseError("; ".join(problems))
    unreleased = log.unreleased
    if not unreleased.entries():
        raise ReleaseError(f"nothing to release: '## {UNRELEASED}' in {CHANGELOG} has no entries")
    last = latest(tags)
    if override:
        version_key(override)  # raises on a malformed version
        if last and version_key(override) <= version_key(last):
            raise ReleaseError(f"version {override} is not higher than the latest release {last}")
        return override
    if last is None:
        return FIRST_VERSION
    m = VERSION_RE.match(last)
    assert m  # latest() only returns versions that match
    major, minor, patch, kind, n = m.groups()
    if kind:
        return f"{major}.{minor}.{patch}-{kind}.{int(n) + 1}"
    if unreleased.group_entries("Breaking"):
        return f"{int(major) + 1}.0.0"
    if unreleased.group_entries("Added"):
        return f"{major}.{int(minor) + 1}.0"
    return f"{major}.{minor}.{int(patch) + 1}"


def cut(log: Changelog, version: str, date: str) -> Changelog:
    """Move the Unreleased entries under `## version - date`; keep an empty Unreleased on top."""
    unreleased = log.unreleased
    if log.find(version):
        raise ReleaseError(f"{CHANGELOG} already has a section for {version}")
    released = Section(version, date, _trim(unreleased.lines))
    sections: list[Section] = []
    for s in log.sections:
        if s is unreleased:
            sections += [Section(UNRELEASED, None), released]
        else:
            sections.append(s)
    return Changelog(log.preamble, sections)


def notes(log: Changelog, version: str) -> str:
    section = log.find(version)
    if section is None:
        raise ReleaseError(f"{CHANGELOG} has no section for {version}")
    return render(Changelog([], [section])).lstrip("\n")


# ── the pull-request gate ─────────────────────────────────────────────────────


def gate(
    base_text: str | None,
    head_text: str | None,
    changed: Sequence[str],
    rules: public_text.PrivateRules = public_text.NO_PRIVATE_RULES,
) -> list[str]:
    """Problems with a pull request's changelog (empty = ok). `changed` = paths the PR changes; `rules` =
    the private rules of `wfj public-check`, when the checkout has them."""
    problems: list[str] = []
    ships = any(p.startswith(SHIPPED_PATHS) for p in changed)
    if head_text is None:
        return [f"{CHANGELOG} is missing"] if ships or base_text is not None else []
    head = parse(head_text)
    problems += lint(head)
    if problems:
        return problems
    head_unreleased = head.unreleased.entries()
    base = parse(base_text) if base_text is not None else Changelog([], [])
    try:
        base_unreleased = base.unreleased.entries() if base_text is not None else []
    except ReleaseError:
        base_unreleased = []
    added = list((Counter(head_unreleased) - Counter(base_unreleased)).elements())
    if ships and not added:
        problems.append(
            "this change touches addon/ or data/: "
            f"add a line for players under '## {UNRELEASED}' in {CHANGELOG}"
        )
    if base_text is not None and [(s.title, s.date, _trim(s.lines)) for s in base.released()] != [
        (s.title, s.date, _trim(s.lines)) for s in head.released()
    ]:
        problems.append(f"released sections of {CHANGELOG} changed: only '## {UNRELEASED}' may be edited")
    for line in added:
        if LOCAL_PATH_RE.search(line) or any(public_text.content_hits(line, rules=rules)):
            problems.append(f"changelog line names a local path or something private: {line}")
    return problems


# ── git + CLI ─────────────────────────────────────────────────────────────────


def _git(root: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True, text=True).stdout


def _show(root: Path, ref: str, path: str) -> str | None:
    r = subprocess.run(
        ["git", "show", f"{ref}:{path}"], cwd=root, capture_output=True, text=True, check=False
    )
    return r.stdout if r.returncode == 0 else None


def _root() -> Path:
    return Path(_git(Path.cwd(), "rev-parse", "--show-toplevel").strip())


def _read(root: Path) -> Changelog:
    path = root / CHANGELOG
    if not path.is_file():
        raise ReleaseError(f"{CHANGELOG} is missing")
    return parse(path.read_text(encoding="utf-8"))


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj release")
    sub = p.add_subparsers(dest="action", required=True)
    nv = sub.add_parser("next-version", help="print the next version (and whether this is a resumed release)")
    nv.add_argument("--version", help="use this version instead of the rule's")
    cl = sub.add_parser("changelog", help="move Unreleased under a version and write its notes")
    cl.add_argument("--version", required=True)
    cl.add_argument("--date", required=True)
    cl.add_argument("--notes", required=True, type=Path)
    nt = sub.add_parser("notes", help="write a released version's notes")
    nt.add_argument("--version", required=True)
    nt.add_argument("--notes", required=True, type=Path)
    gt = sub.add_parser("changelog-gate", help="the pull-request changelog check")
    gt.add_argument("--base", required=True, help="the base ref, e.g. origin/main")
    a = p.parse_args(argv)
    root = _root()
    try:
        if a.action == "next-version":
            log = _read(root)
            on_head = [t for t in _git(root, "tag", "--points-at", "HEAD").split() if t.startswith("v")]
            if a.version and f"v{a.version}" in on_head:
                if log.find(a.version) is None:
                    raise ReleaseError(f"v{a.version} is on HEAD but {CHANGELOG} has no section for it")
                print(f"version={a.version}\nresume=true")
                return 0
            if on_head and not a.version:
                raise ReleaseError(
                    f"HEAD is already released as {on_head[0]}: to finish that release, run again with "
                    f"version {on_head[0][1:]}; otherwise merge a change first"
                )
            tags = _git(root, "tag", "--list", "v*").split()
            last = latest(tags)
            if last is not None:
                at_tag = _show(root, f"v{last}", CHANGELOG)
                problems = released_drift(log, parse(at_tag), f"v{last}") if at_tag is not None else []
                if problems:
                    raise ReleaseError("; ".join(problems))
            version = next_version(log, tags, a.version)
            print(f"version={version}\nresume=false")
        elif a.action == "changelog":
            version_key(a.version)
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", a.date):
                raise ReleaseError(f"'{a.date}' is not a YYYY-MM-DD date")
            log = cut(_read(root), a.version, a.date)
            (root / CHANGELOG).write_text(render(log), encoding="utf-8")
            a.notes.write_text(notes(log, a.version), encoding="utf-8")
            print(f"release: {CHANGELOG} cut for {a.version}")
        elif a.action == "notes":
            a.notes.write_text(notes(_read(root), a.version), encoding="utf-8")
        else:
            # --no-renames: moving a file out of addon/ or data/ is a change to what ships. The base text is
            # read at the merge-base, the same point the file list is diffed from.
            changed = _git(root, "diff", "--no-renames", "--name-only", f"{a.base}...HEAD").split()
            merge_base = _git(root, "merge-base", a.base, "HEAD").strip()
            texts = _show(root, merge_base, CHANGELOG), _show(root, "HEAD", CHANGELOG)
            problems = gate(*texts, changed, private_rules.load(root))
            for problem in problems:
                print(f"changelog-gate: {problem}", file=sys.stderr)
            if problems:
                return 1
            print("changelog-gate: ok")
    except ReleaseError as e:
        print(f"release: {e}", file=sys.stderr)
        return 1
    return 0
