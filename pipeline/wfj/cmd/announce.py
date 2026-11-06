"""wfj announce: a release's Discord post (docs/operations/release.md, ADR-072).

  wfj announce --version X.Y.Z --notes PATH [--media DIR] [--dry-run]
      Post version X.Y.Z: one line of content, one embed in the addon's gold with the version, the notes at
      PATH (the version's changelog section, as `wfj release changelog` writes it) as Discord markdown and
      the CurseForge link, and the image and video files of DIR attached in name order. No DIR, or an empty
      one: the text alone.
  wfj announce --preview [--media DIR] [--dry-run]
      The post the next release would make: the version by the release rule (`next` while `## Unreleased`
      is empty), the notes from `## Unreleased`, the media from DIR/next; its content starts with a line
      saying it is a preview.

The webhook URL is read from DISCORD_WEBHOOK_URL and nowhere else; it is never printed. --dry-run prints
the payload and the file list and sends nothing. Limits are Discord's: at most 10 files of 20 MiB, each a
type Discord shows inline, a description of at most 4096 characters (longer notes are cut at an entry and
end with a link to the full notes).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from wfj.cmd import release
from wfj.io import discord

NAME = "WoW Forever Japanese"
CURSEFORGE_FILES = "https://www.curseforge.com/wow/addons/wow-forever-japanese/files"
RELEASE_URL = "https://github.com/zyaga/wow-forever-japanese/releases/tag/v{version}"
GOLD = 0xE8C77E  # the gold of the CurseForge text and the gallery cards
MAX_FILES = 10
MAX_FILE_BYTES = 20 * 1024 * 1024
MAX_DESCRIPTION = 4096
MAX_EMBED = 6000
ALLOWED = frozenset(discord.CONTENT_TYPES)


class AnnounceError(RuntimeError):
    pass


@dataclass(frozen=True)
class Media:
    name: str
    path: Path
    size: int


def media_files(folder: Path | None) -> list[Media]:
    """The files of the media folder in name order, checked against Discord's limits: a missing folder is no
    media; dotfiles and the folder's own README are not media; anything else must be an image or video
    type Discord shows inline, at most 20 MiB, at most 10 in all."""
    if folder is None or not folder.is_dir():
        return []
    out: list[Media] = []
    for path in sorted(folder.iterdir(), key=lambda p: p.name):
        if path.name.startswith(".") or not path.is_file() or path.name.lower() == "readme.md":
            continue
        ext = path.suffix.lower().lstrip(".")
        if ext not in ALLOWED:
            allowed = ", ".join(sorted(ALLOWED))
            raise AnnounceError(f"{path.name}: Discord does not show .{ext or '?'} inline (allowed: {allowed})")
        size = path.stat().st_size
        if size > MAX_FILE_BYTES:
            raise AnnounceError(f"{path.name} is {size} bytes, over Discord's 20 MiB")
        out.append(Media(path.name, path, size))
    if len(out) > MAX_FILES:
        raise AnnounceError(f"{len(out)} files in {folder.name}: Discord takes at most {MAX_FILES}")
    return out


def markdown(notes: str) -> str:
    """The notes as Discord markdown: the version heading dropped, each group heading a bold line, each
    entry a bullet with its continuation lines joined, groups parted by a blank line."""
    groups: list[list[str]] = []
    for raw in notes.splitlines():
        line = raw.rstrip()
        if not line.strip() or line.startswith("## "):
            continue
        if line.startswith("### "):
            groups.append([f"**{line[4:].strip()}**"])
        elif line.startswith("- "):
            if not groups:
                groups.append([])
            groups[-1].append(line)
        elif line.startswith((" ", "\t")) and groups and groups[-1]:
            groups[-1][-1] += " " + line.strip()
    return "\n\n".join("\n".join(g) for g in groups if g)


def description(version: str, notes: str) -> str:
    """The embed's text, within Discord's limit: long notes stop at an entry and end with a link to the full
    notes on GitHub."""
    text = markdown(notes)
    if len(text) <= MAX_DESCRIPTION:
        return text
    link = f"Full notes: {RELEASE_URL.format(version=version)}"
    lines = text.split("\n")
    kept: list[str] = []
    for i, line in enumerate(lines):
        candidate = "\n".join([*lines[: i + 1], link])
        if len(candidate) > MAX_DESCRIPTION:
            break
        if line.startswith("- "):
            kept = lines[: i + 1]
    return "\n".join([*kept, link])


def build(version: str, notes: str, files: Sequence[Media], preview: bool = False) -> dict:
    """The webhook payload: the content line, the embed and, with files, the attachment list."""
    title = f"{NAME} {version}"
    text = description(version, notes)
    if len(title) + len(text) > MAX_EMBED:
        raise AnnounceError(f"the embed would be {len(title) + len(text)} characters, over {MAX_EMBED}")
    content = f"{title} is out."
    if preview:
        content = "Preview of the next release post. " + content
    payload: dict = {
        "content": content,
        "embeds": [{"title": title, "url": CURSEFORGE_FILES, "color": GOLD, "description": text}],
    }
    if files:
        payload["attachments"] = [{"id": i, "filename": f.name} for i, f in enumerate(files)]
    return payload


def _preview(root: Path) -> tuple[str, str]:
    """The next release's version and notes from CHANGELOG.md: `next` with nothing under Unreleased."""
    log = release._read(root)
    section = log.unreleased
    if not section.entries():
        return "next", ""
    tags = release._git(root, "tag", "--list").split()
    version = release.next_version(log, tags)
    return version, release.render(release.Changelog([], [section])).lstrip("\n")


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj announce")
    p.add_argument("--version", help="the released version")
    p.add_argument("--notes", type=Path, help="the version's notes, as wfj release changelog writes them")
    p.add_argument("--media", type=Path, help="the media folder (with --preview: the folder holding next/)")
    p.add_argument("--preview", action="store_true", help="the next release's post: Unreleased and next/")
    p.add_argument("--dry-run", action="store_true", help="print the payload and the files; send nothing")
    a = p.parse_args(argv)
    try:
        if a.preview:
            if a.version or a.notes:
                raise AnnounceError("--preview takes its version and notes from CHANGELOG.md")
            version, notes = _preview(release._root())
            folder = a.media / "next" if a.media else None
        else:
            if not a.version or not a.notes:
                raise AnnounceError("--version and --notes are needed (or --preview)")
            version, notes, folder = a.version, a.notes.read_text(encoding="utf-8"), a.media
        files = media_files(folder)
        payload = build(version, notes, files, preview=a.preview)
        for f in files:
            print(f"file: {f.name} ({f.size} bytes)")
        if a.dry_run:
            print(json.dumps(payload, indent=2, ensure_ascii=False))
            print("dry run: nothing sent")
            return 0
        url = os.environ.get("DISCORD_WEBHOOK_URL")
        if not url:
            print("DISCORD_WEBHOOK_URL is not set", file=sys.stderr)
            return 1
        answer = discord.post(url, payload, [(f.name, f.path.read_bytes()) for f in files])
        print(f"posted {version} to Discord: {len(files)} file(s), message {answer.get('id', '?')}")
        return 0
    except (AnnounceError, discord.DiscordError, release.ReleaseError, OSError) as e:
        print(f"announce: {e}", file=sys.stderr)
        return 1
