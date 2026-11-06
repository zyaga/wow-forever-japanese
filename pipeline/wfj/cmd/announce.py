"""wfj announce: a release's Discord post (docs/operations/release.md, ADR-072).

  wfj announce --version X.Y.Z --notes PATH [--media DIR] [--dry-run]
      Post version X.Y.Z as one message: one line of content, the folder's clips and pictures as
      attachments (Discord shows them as tiles at the top of the post), then the English card in the
      addon's gold with the version, the notes at PATH as Discord markdown and the CurseForge link, and,
      when DIR holds `ja.md`, the Japanese card with that text. No DIR, or an empty one: the cards alone.
  wfj announce --preview [--media DIR] [--dry-run]
      The post the next release would make: the version by the release rule (`next` while `## Unreleased`
      is empty), the notes from `## Unreleased`, the media and `ja.md` from DIR; its content starts with a
      line saying it is a preview.

The webhook URL is read from DISCORD_WEBHOOK_URL and nowhere else; it is never printed. --dry-run prints
the message and the file list and sends nothing. Limits are Discord's: at most 10 files of 20 MiB and
25 MiB together, each a type Discord shows inline, a card of at most 4096
characters (longer notes are cut at an entry and end with a link to the full notes; a longer `ja.md` is
refused).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections.abc import Sequence
from pathlib import Path

from wfj.cmd import release
from wfj.cmd.release import Section
from wfj.io import discord

NAME = "WoW Forever Japanese"
CURSEFORGE_FILES = "https://www.curseforge.com/wow/addons/wow-forever-japanese/files"
RELEASE_URL = "https://github.com/zyaga/wow-forever-japanese/releases/tag/v{version}"
GOLD = 0xE8C77E  # the gold of the CurseForge text and the gallery cards
JA_FILE = "ja.md"  # the Japanese card's text, beside the media
MAX_FILES = 10
MAX_FILE_BYTES = 20 * 1024 * 1024
MAX_TOTAL_BYTES = 25 * 1024 * 1024  # Discord's limit on one request
MAX_DESCRIPTION = 4096
FILE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")  # a name that goes into a multipart header as is


class AnnounceError(RuntimeError):
    pass


def media_files(folder: Path | None) -> list[Path]:
    """The files of the media folder in name order, checked against Discord's limits: a missing folder is no
    media; dotfiles and `ja.md` are not media; anything else must be a file (no subfolders) with a plain
    name, an image or video type Discord shows inline, not empty, at most 20 MiB, at most 10 in all, under
    25 MiB together."""
    if folder is None or not folder.is_dir():
        return []
    out: list[Path] = []
    for path in sorted(folder.iterdir(), key=lambda p: p.name):
        if path.name.startswith(".") or path.name == JA_FILE:
            continue
        if not path.is_file():
            raise AnnounceError(f"{path.name}: only files go in the media folder, not folders")
        if not FILE_NAME.match(path.name):
            plain = "letters, digits, dots, dashes and underscores"
            raise AnnounceError(f"{path.name!r}: a media file name uses {plain} only")
        if discord.content_type(path.name) is None:
            allowed = ", ".join(sorted(discord.CONTENT_TYPES))
            raise AnnounceError(f"{path.name}: Discord does not show this type inline (allowed: {allowed})")
        size = path.stat().st_size
        if size == 0:
            raise AnnounceError(f"{path.name} is empty")
        if size > MAX_FILE_BYTES:
            raise AnnounceError(f"{path.name} is {size} bytes, over Discord's 20 MiB")
        out.append(path)
    if len(out) > MAX_FILES:
        raise AnnounceError(f"{len(out)} files in {folder.name}: Discord takes at most {MAX_FILES}")
    total = sum(p.stat().st_size for p in out)
    if total > MAX_TOTAL_BYTES:
        raise AnnounceError(f"{total} bytes of media in {folder.name}, over Discord's 25 MiB for one post")
    return out


def japanese(folder: Path | None) -> str | None:
    """The Japanese card's text, `ja.md` in the media folder: Discord markdown as written, within the card's
    limit. None when the folder or the file is absent."""
    if folder is None or not (folder / JA_FILE).is_file():
        return None
    text = (folder / JA_FILE).read_text(encoding="utf-8").strip()
    if not text:
        raise AnnounceError(f"{JA_FILE} is empty")
    if len(text) > MAX_DESCRIPTION:
        raise AnnounceError(f"{JA_FILE} is {len(text)} characters, over a card's {MAX_DESCRIPTION}")
    return text


def notes_section(text: str) -> Section:
    """The one section of a notes file, as `wfj release changelog` writes it."""
    log = release.parse(text)
    if not log.sections:
        raise AnnounceError("the notes hold no changelog section")
    return log.sections[0]


def markdown(section: Section) -> str:
    """A changelog section as Discord markdown: each group heading a bold line, each entry a bullet with its
    continuation lines joined, groups parted by a blank line."""
    out: list[str] = []
    for line in section.lines:
        group = release.GROUP_RE.match(line)
        if group:
            if out:
                out.append("")
            out.append(f"**{group.group(1)}**")
        elif line.startswith("- "):
            out.append(line.rstrip())
        elif line.startswith((" ", "\t")) and out and out[-1].startswith("- "):
            out[-1] += " " + line.strip()
    return "\n".join(out)


def description(version: str, section: Section) -> str:
    """The English card's text, within Discord's limit: long notes stop at an entry and end with a link to
    the full notes on GitHub."""
    text = markdown(section)
    if len(text) <= MAX_DESCRIPTION:
        return text
    link = f"Full notes: {RELEASE_URL.format(version=version)}"
    kept: list[str] = []
    used = 0
    for line in text.split("\n"):
        used += len(line) + 1  # the line and the newline after it
        if used + len(link) > MAX_DESCRIPTION:
            break
        kept.append(line)
    while kept and not kept[-1].startswith("- "):
        kept.pop()
    return "\n".join([*kept, link])


def build(
    version: str, section: Section, files: Sequence[Path], ja: str | None = None, preview: bool = False
) -> dict:
    """The one webhook message: the content line, the files as attachments (Discord shows them as tiles at the
    top of the post, clips first), then the English card and, with `ja`, the Japanese card."""
    clips = [f for f in files if (discord.content_type(f.name) or "").startswith("video/")]
    pictures = [f for f in files if f not in clips]
    ordered = [*clips, *pictures]
    title = f"{NAME} {version}"
    content = f"{title} is out."
    if preview:
        content = "Preview of the next release post. " + content
    text = description(version, section)
    embeds = [{"title": title, "url": CURSEFORGE_FILES, "color": GOLD, "description": text}]
    if ja:
        embeds.append({"title": f"{title}（日本語）", "color": GOLD, "description": ja})
    payload: dict = {"content": content, "embeds": embeds}
    if ordered:
        payload["attachments"] = [{"id": i, "filename": f.name} for i, f in enumerate(ordered)]
    return payload


def attached(files: Sequence[Path]) -> list[Path]:
    """The files in the order the post carries them: clips first, then pictures."""
    clips = [f for f in files if (discord.content_type(f.name) or "").startswith("video/")]
    return [*clips, *[f for f in files if f not in clips]]


def _preview(root: Path) -> tuple[str, Section]:
    """The next release's version and its section, by the release's own rule: `next` with nothing under
    Unreleased."""
    version, _, addon = release.plan_release(root, allow_empty=True)
    return (version if addon else "next"), release.read_changelog(root).unreleased


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj announce")
    p.add_argument("--version", help="the released version")
    p.add_argument("--notes", type=Path, help="the version's notes, as wfj release changelog writes them")
    p.add_argument("--media", type=Path, help="the folder of pictures, clips and ja.md")
    p.add_argument("--preview", action="store_true", help="the next release's post, from Unreleased")
    p.add_argument("--dry-run", action="store_true", help="print the messages and the files; send nothing")
    a = p.parse_args(argv)
    try:
        if a.preview:
            if a.version or a.notes:
                raise AnnounceError("--preview takes its version and notes from CHANGELOG.md")
            version, section = _preview(release.repo_root())
        else:
            if not a.version or not a.notes:
                raise AnnounceError("--version and --notes are needed (or --preview)")
            version, section = a.version, notes_section(a.notes.read_text(encoding="utf-8"))
        if a.media and not a.media.is_dir():
            print(f"no media folder at {a.media}: the English card alone")
        files = media_files(a.media)
        ja = japanese(a.media)
        if a.media and a.media.is_dir() and ja is None:
            print(f"no {JA_FILE} in {a.media}: the English card alone")
        payload = build(version, section, files, ja, preview=a.preview)
        order = attached(files)
        for f in order:
            print(f"file: {f.name} ({f.stat().st_size} bytes)")
        if a.dry_run:
            print(json.dumps(payload, indent=2, ensure_ascii=False))
            print("dry run: nothing sent")
            return 0
        url = os.environ.get("DISCORD_WEBHOOK_URL")
        if not url:
            print("DISCORD_WEBHOOK_URL is not set", file=sys.stderr)
            return 1
        answer = discord.post(url, payload, [(f.name, f.read_bytes()) for f in order])
        print(f"posted {version} to Discord: {len(order)} file(s), message {answer.get('id', '?')}")
        return 0
    except (AnnounceError, discord.DiscordError, release.ReleaseError, OSError) as e:
        print(f"announce: {e}", file=sys.stderr)
        return 1
