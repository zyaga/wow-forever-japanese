"""wfj public-check: keep private material out of the public repository (docs/systems/pipeline.md).

    wfj public-check paths      no tracked file is a symlink, and no tracked file sits under a path the
                                checkout keeps private (the private block of the git folder's info/exclude)
    wfj public-check content    no tracked file holds a path on the author's machine, or anything the private
                                rules name
    wfj public-check comments   no code or config comment (Lua, Python, shell, YAML, TOML, Makefile, TOC,
                                .gitignore, pipeline lists) or docstring records history
    wfj public-check links      every relative Markdown link, image and link definition resolves to a
                                tracked file
    wfj public-check images     every image in README.md and docs/curseforge.md has alt text and fits, and
                                no image under docs/images/ carries metadata text
    wfj public-check pr         the pull request title, body, branch name and commit messages pass `content`,
                                and every commit's author and committer address is a GitHub noreply one
    wfj public-check all        paths, content, comments, links, images

`pr` reads the title, body and branch from the Actions event file ($GITHUB_EVENT_PATH) when there is one,
else from $PR_TITLE, $PR_BODY and $GITHUB_HEAD_REF; with $BASE_REF set it also reads every commit in
origin/$BASE_REF..HEAD: its message, and its author and committer addresses.

Each prints one line per problem and exits 1 when there is any, 0 otherwise. `--repo` points at another
checkout (the tests use a temporary one).

The private rules and the private paths are kept outside the repository (io/private_rules.py). A checkout
without them, such as a fresh clone or a CI run, checks the public rules only and says so.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tokenize
from collections.abc import Callable, Sequence
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from urllib.parse import unquote

from wfj.core import public_text as pt
from wfj.io import private_rules

PRIVATE_BLOCK = "# Private project internals"
EXCLUDE = "exclude"
# The GPL text is quoted verbatim and numbers its own sections.
CONTENT_EXEMPT = {"LICENSE"}
# A credits page may name a contributor who shares the owner's common first name.
FIRST_NAME_EXEMPT = {"ATTRIBUTION.md"}
MAX_IMAGE_BYTES = 300 * 1024
IMAGE_PAGES = ("README.md", "docs/curseforge.md")
IMAGE_DIR = "docs/images/"
IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".gif", ".webp")
SYMLINK_MODE = "120000"
GLOB_CHARS = "*?["


def _git_out(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args], check=True, capture_output=True
    ).stdout.decode("utf-8", errors="replace")


def _tracked(repo: Path) -> list[str]:
    return [p for p in _git_out(repo, "ls-files", "-z").split("\0") if p]


def _symlinks(repo: Path) -> list[str]:
    """Tracked files whose index mode is a symlink (`<mode> <sha> <stage>\\t<path>`)."""
    out = []
    for entry in _git_out(repo, "ls-files", "-s", "-z").split("\0"):
        meta, _, path = entry.partition("\t")
        if path and meta.split(" ", 1)[0] == SYMLINK_MODE:
            out.append(path)
    return out


def _read_text(path: Path) -> str | None:
    """The file as text, or None when it is binary (or not a regular file, like a symlink to a folder)."""
    try:
        raw = path.read_bytes()
    except (IsADirectoryError, FileNotFoundError):
        return None
    if b"\0" in raw[:8192]:
        return None
    return raw.decode("utf-8", errors="replace")


def private_block_lines(exclude: str) -> list[int]:
    """1-based line numbers of the private block of an exclude file: its header comment to the next blank
    line."""
    lines = exclude.splitlines()
    try:
        start = next(i for i, ln in enumerate(lines) if ln.startswith(PRIVATE_BLOCK))
    except StopIteration:
        return []
    out = [start + 1]
    for i in range(start + 1, len(lines)):
        if not lines[i].strip():
            break
        out.append(i + 1)
    return out


def private_paths(exclude: str) -> list[str]:
    """The entries of the private block."""
    lines = exclude.splitlines()
    return [
        lines[n - 1].strip().lstrip("/").rstrip("/")
        for n in private_block_lines(exclude)[1:]
        if not lines[n - 1].startswith("#")
    ]


def _exclude_text(repo: Path) -> str:
    """The git folder's info/exclude: the ignore list git never publishes."""
    info = private_rules.git_info_dir(repo)
    path = info / EXCLUDE if info else None
    return path.read_text(encoding="utf-8") if path and path.is_file() else ""


def check_paths(repo: Path) -> list[str]:
    entries = private_paths(_exclude_text(repo))
    twice = sorted({e for e in entries if entries.count(e) > 1})
    problems = [f"info/exclude: private entry listed twice: {e}" for e in twice]
    # Entries are compared with tracked paths literally, so a pattern would match nothing here.
    problems += [
        f"info/exclude: private entry holds a glob character (entries are compared literally): {e}"
        for e in entries
        if any(c in e for c in GLOB_CHARS)
    ]
    # A checkout that keeps private paths must run the private rules too.
    if entries and not private_rules.load(repo):
        problems.append(f"the private rules are missing: {private_rules.rules_path(repo)}")
    for f in _tracked(repo):
        for e in entries:
            if f == e or f.startswith(e + "/"):
                problems.append(f"{f}: tracked, but under the private path {e}")
    # A symlink's content is the path it points to, which may be a private local path.
    problems += [f"{f}: tracked symlink (it would publish the path it points to)" for f in _symlinks(repo)]
    return problems


def _content_of(repo: Path, f: str, rules: pt.PrivateRules) -> list[str]:
    problems = [f"{f}: file name: {rule}" for rule in pt.path_hits(f, rules=rules)]
    text = None if f in CONTENT_EXEMPT else _read_text(repo / f)
    if text is not None:
        hits = pt.content_hits(
            text, in_data=f.startswith("data/"), first_name=f not in FIRST_NAME_EXEMPT, rules=rules
        )
        problems += [f"{f}:{h.line}: {h.rule}: {h.text}" for h in hits]
    return problems


def check_content(repo: Path) -> list[str]:
    # data/ is well over 100 MB of text; one process per core keeps the check to seconds.
    files = _tracked(repo)
    rules = private_rules.load(repo)
    with ProcessPoolExecutor() as pool:
        results = pool.map(_content_of, [repo] * len(files), files, [rules] * len(files), chunksize=64)
        return [p for problems in results for p in problems]


# ------------------------------------------------------------------------------------------- comments

HASH_COMMENT_EXTS = (".yml", ".yaml", ".toml", ".sh")
HASH_COMMENT_NAMES = {"Makefile", ".pkgmeta"}
LUA_COMMENT_NAMES = {".luacheckrc", ".luacov"}
PIPELINE_LIST_EXTS = (".txt", ".tsv")


def _comment_kind(f: str) -> str | None:
    name = Path(f).name
    if f.endswith(".lua") or name in LUA_COMMENT_NAMES:
        return None if "/Data/" in f else "lua"
    if f.endswith(".py"):
        return "py"
    if f.endswith(HASH_COMMENT_EXTS) or name in HASH_COMMENT_NAMES:
        return "hash"
    if f.endswith(".toc"):
        return "toc"
    if f == ".gitignore":
        return "list"
    if f.startswith("pipeline/") and f.endswith(PIPELINE_LIST_EXTS):
        return "list"
    return None


class Unparsable(Exception):
    pass


def _comments(kind: str, text: str) -> list[tuple[int, str]]:
    """Every comment in a file of `kind`; raises Unparsable when Python source does not tokenize or parse."""
    if kind == "lua":
        return list(pt.lua_comments(text))
    if kind == "py":
        try:
            return list(pt.python_comments(text))
        except (SyntaxError, ValueError, tokenize.TokenError) as e:
            raise Unparsable from e
    if kind == "hash":
        return list(pt.hash_comments(text))
    if kind == "toc":
        return list(pt.hash_comments(text, trailing=False, skip="##"))
    return list(pt.hash_comments(text, trailing=False))


def _code_comments(repo: Path) -> list[tuple[str, list[tuple[int, str]] | None]]:
    """(file, its comments) for every tracked file with comments; None when the file could not be parsed."""
    out: list[tuple[str, list[tuple[int, str]] | None]] = []
    for f in _tracked(repo):
        kind = _comment_kind(f)
        if kind is None:
            continue
        text = _read_text(repo / f)
        if text is None:
            continue
        try:
            out.append((f, _comments(kind, text)))
        except Unparsable:
            out.append((f, None))
    return out


def check_comments(repo: Path) -> list[str]:
    problems = []
    rules = private_rules.load(repo)
    for f, comments in _code_comments(repo):
        if comments is None:
            problems.append(f"{f}: could not parse")
            continue
        for line, body in comments:
            for rule in pt.history_hits(body, rules=rules):
                shown = " ".join(body.split())[:120]
                problems.append(f"{f}:{line}: comment records history ({rule}): {shown}")
    return problems


# ---------------------------------------------------------------------------------------------- links

MD_LINK = re.compile(r"!?\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+(?:\"[^\"]*\"|'[^']*'))?\s*\)")
# A reference-style link definition: `[label]: target "title"`. A footnote (`[^1]: text`) is not one.
MD_LINK_DEF = re.compile(r"^ {0,3}\[(?!\^)[^\]]+\]:\s*<?([^\s>]+)>?", re.MULTILINE)
HTML_IMG = re.compile(r"<img\b[^>]*>", re.IGNORECASE)
HTML_ATTR = re.compile(r"(\w+)\s*=\s*(?:\"([^\"]*)\"|'([^']*)')")


def _attrs(tag: str) -> dict[str, str]:
    return {name.lower(): dq or sq for name, dq, sq in HTML_ATTR.findall(tag)}


def _outside_fences(text: str) -> str:
    """The Markdown text with fenced code blocks blanked (line count kept)."""
    lines = text.split("\n")
    fenced = pt.fenced_lines(lines)
    return "\n".join("" if f else ln for ln, f in zip(lines, fenced, strict=True))


def _local_target(target: str) -> str | None:
    if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.IGNORECASE) or target.startswith(("#", "//")):
        return None
    return unquote(target.split("#", 1)[0].split("?", 1)[0])


def _resolve(page: str, target: str) -> str:
    """A link target as a repository path: a leading `/` is the repository root, anything else is relative
    to the page."""
    if target.startswith("/"):
        return os.path.normpath(target.lstrip("/")) if target.strip("/") else "."
    return os.path.normpath(Path(page).parent / target)


def check_links(repo: Path) -> list[str]:
    tracked = _tracked(repo)
    files = set(tracked)
    dirs = {"."} | {str(p) for f in tracked for p in Path(f).parents}
    problems = []
    for f in tracked:
        if not f.endswith(".md"):
            continue
        text = _read_text(repo / f)
        if text is None:
            continue
        text = _outside_fences(text)
        targets = [m.group(2) for m in MD_LINK.finditer(text)]
        targets += [m.group(1) for m in MD_LINK_DEF.finditer(text)]
        targets += [_attrs(m.group(0)).get("src", "") for m in HTML_IMG.finditer(text)]
        for raw in targets:
            target = _local_target(raw)
            if not target:
                continue
            resolved = _resolve(f, target)
            if resolved not in files and resolved not in dirs:
                problems.append(f"{f}: link to a file that is not in the repository: {raw}")
    return problems


# --------------------------------------------------------------------------------------------- images


def check_images(repo: Path) -> list[str]:
    problems = []
    for page in IMAGE_PAGES:
        path = repo / page
        if not path.exists():
            continue
        text = _outside_fences(path.read_text())
        images = [(m.group(1), m.group(2)) for m in MD_LINK.finditer(text) if m.group(0).startswith("!")]
        for m in HTML_IMG.finditer(text):
            attrs = _attrs(m.group(0))
            images.append((attrs.get("alt", ""), attrs.get("src", "")))
        for alt, src in images:
            if not alt.strip():
                problems.append(f"{page}: image without alt text: {src}")
            target = _local_target(src)
            if target:
                img = repo / _resolve(page, target)
                if img.is_file() and img.stat().st_size > MAX_IMAGE_BYTES:
                    problems.append(f"{page}: image over {MAX_IMAGE_BYTES // 1024} KB: {src}")
    # Metadata text (camera, software, dates, locations) is published with the image; strip it before adding.
    for f in _tracked(repo):
        if f.startswith(IMAGE_DIR) and f.lower().endswith(IMAGE_EXTS) and (repo / f).is_file():
            kinds = pt.image_metadata((repo / f).read_bytes())
            if kinds:
                problems.append(f"{f}: image carries metadata ({', '.join(kinds)}); strip it")
    return problems


# ------------------------------------------------------------------------------------------------- pr


# A personal address in a commit is published with it; the project commits with GitHub's noreply addresses
# (an account's own, or the one GitHub's web editor and merge button use as committer).
NOREPLY = "@users.noreply.github.com"
GITHUB_NOREPLY = "noreply@github.com"


def _noreply(address: str) -> bool:
    return address.endswith(NOREPLY) or address == GITHUB_NOREPLY


def _pr_texts(repo: Path) -> tuple[list[tuple[str, str]], list[str]]:
    """(label, text) pairs to check, and problems reading them (a commit address that is not a noreply one
    is a problem here, not a text to scan)."""
    event: dict = {}
    event_path = os.environ.get("GITHUB_EVENT_PATH", "")
    if event_path and Path(event_path).is_file():
        event = json.loads(Path(event_path).read_text(encoding="utf-8")).get("pull_request") or {}
    if event:
        title, body = event.get("title") or "", event.get("body") or ""
    else:
        title, body = os.environ.get("PR_TITLE", ""), os.environ.get("PR_BODY", "")
    branch = os.environ.get("GITHUB_HEAD_REF") or (event.get("head") or {}).get("ref") or ""
    texts = [("PR_TITLE", title), ("PR_BODY", body), ("branch", branch)]
    problems = []
    base = os.environ.get("BASE_REF", "")
    if base:
        try:
            log = _git_out(repo, "log", "-z", "--format=%h%n%ae%n%ce%n%B", f"origin/{base}..HEAD")
        except subprocess.CalledProcessError:
            problems.append(f"commits: could not read origin/{base}..HEAD")
        else:
            for record in log.split("\0"):
                sha, author, committer, message = (record.strip("\n").split("\n", 3) + ["", "", ""])[:4]
                if not sha:
                    continue
                for role, address in (("author", author), ("committer", committer)):
                    if not _noreply(address):
                        problems.append(f"commit {sha}: {role} address is not a GitHub noreply address")
                texts.append((f"commit {sha}", message))
    return texts, problems


def check_pr(repo: Path) -> list[str]:
    texts, problems = _pr_texts(repo)
    rules = private_rules.load(repo)
    for label, text in texts:
        problems += [f"{label}:{h.line}: {h.rule}: {h.text}" for h in pt.content_hits(text, rules=rules)]
    return problems


CHECKS: dict[str, Callable[[Path], list[str]]] = {
    "paths": check_paths,
    "content": check_content,
    "comments": check_comments,
    "links": check_links,
    "images": check_images,
    "pr": check_pr,
}
ALL = ("paths", "content", "comments", "links", "images")


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj public-check")
    p.add_argument("check", choices=[*CHECKS, "all"])
    p.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    a = p.parse_args(argv)
    names = ALL if a.check == "all" else (a.check,)
    failed = False
    if not private_rules.load(a.repo):
        print("public-check: no private rules in this checkout; the public rules run", file=sys.stderr)
    for name in names:
        problems = CHECKS[name](a.repo)
        for line in problems:
            print(line)
        verdict = f"{len(problems)} problem(s)" if problems else "ok"
        print(f"public-check {name}: {verdict}", file=sys.stderr)
        failed = failed or bool(problems)
    return 1 if failed else 0
