"""wfj announce: the Discord post of a release, its limits, the webhook transport and the command
(docs/operations/release.md, ADR-072)."""

import io
import itertools
import json
import re
import subprocess
import urllib.error
from pathlib import Path

import pytest

from wfj.cmd import announce
from wfj.cmd.announce import AnnounceError
from wfj.io import discord
from wfj.io.discord import DiscordError

NOTES = (
    "## 0.9.0 - 2026-11-07\n\n### Added\n- Study your saved words in game: a small tab says how many are due.\n"
    "- A second line\n  that continues.\n\n### Fixed\n- The auction house search.\n"
)
VERSION = "0.9.0"


_folders = itertools.count()


def media(tmp_path: Path, names: dict[str, int]) -> Path:
    folder = tmp_path / f"media{next(_folders)}"
    folder.mkdir()
    for name, size in names.items():
        (folder / name).write_bytes(b"x" * size)
    return folder


# ── the post ──────────────────────────────────────────────────────────────────


def test_markdown_renders_groups_and_entries():
    assert announce.markdown(NOTES) == (
        "**Added**\n- Study your saved words in game: a small tab says how many are due.\n"
        "- A second line that continues.\n\n**Fixed**\n- The auction house search."
    )
    # the Unreleased heading of a preview is dropped the same way as a version heading
    assert announce.markdown("## Unreleased\n\n### Fixed\n- A typo.\n") == "**Fixed**\n- A typo."


def test_build_shapes_the_post(tmp_path):
    folder = media(tmp_path, {"b-clip.mp4": 10, "a-card.jpg": 5})
    files = announce.media_files(folder)
    payload = announce.build(VERSION, NOTES, files)
    assert payload["content"] == "WoW Forever Japanese 0.9.0 is out."
    (embed,) = payload["embeds"]
    assert embed["title"] == "WoW Forever Japanese 0.9.0"
    assert embed["url"] == "https://www.curseforge.com/wow/addons/wow-forever-japanese/files"
    assert embed["color"] == 0xE8C77E == 15255422
    assert embed["description"] == announce.markdown(NOTES)
    assert "image" not in embed and "thumbnail" not in embed  # attachments, not one page-filling picture
    assert payload["attachments"] == [
        {"id": 0, "filename": "a-card.jpg"},
        {"id": 1, "filename": "b-clip.mp4"},
    ]
    assert [f.name for f in files] == ["a-card.jpg", "b-clip.mp4"]  # name order
    assert "attachments" not in announce.build(VERSION, NOTES, [])


def test_preview_prefix():
    payload = announce.build("next", NOTES, [], preview=True)
    assert payload["content"].startswith("Preview of the next release post.")
    assert payload["embeds"][0]["title"] == "WoW Forever Japanese next"


# ── the limits ────────────────────────────────────────────────────────────────


def test_limits_refuse_bad_files(tmp_path):
    with pytest.raises(AnnounceError, match=r"notes\.txt"):
        announce.media_files(media(tmp_path, {"notes.txt": 3}))
    with pytest.raises(AnnounceError, match=r"big\.png.*20 MiB"):
        announce.media_files(media(tmp_path, {"big.png": 20 * 1024 * 1024 + 1}))
    with pytest.raises(AnnounceError, match=r"11 files"):
        announce.media_files(media(tmp_path, {f"{i:02}.png": 1 for i in range(11)}))
    assert announce.media_files(None) == []
    assert announce.media_files(tmp_path / "absent") == []
    # a folder's own notes and dotfiles are not media
    folder = media(tmp_path, {"card.webp": 1})
    (folder / "README.md").write_text("how to use this folder\n", encoding="utf-8")
    (folder / ".DS_Store").write_bytes(b"\0")
    assert [f.name for f in announce.media_files(folder)] == ["card.webp"]


def test_long_notes_are_cut_with_a_link():
    entries = "\n".join(f"- Entry number {i} with enough words to take some room on the line." for i in range(120))
    notes = f"## 0.9.0 - 2026-11-07\n\n### Added\n{entries}\n"
    text = announce.description(VERSION, notes)
    assert len(text) <= announce.MAX_DESCRIPTION
    lines = text.split("\n")
    assert lines[-1] == "Full notes: https://github.com/zyaga/wow-forever-japanese/releases/tag/v0.9.0"
    assert lines[-2].startswith("- Entry number ") and lines[-2].endswith("line.")  # cut at an entry boundary
    short = announce.description(VERSION, NOTES)
    assert "Full notes" not in short
    payload = announce.build(VERSION, notes, [])
    embed = payload["embeds"][0]
    assert len(embed["title"]) + len(embed["description"]) <= announce.MAX_EMBED


# ── the transport ─────────────────────────────────────────────────────────────


class FakeResponse(io.BytesIO):
    status = 200


def test_multipart_body_and_post():
    payload = {"content": "hi", "attachments": [{"id": 0, "filename": "a.png"}, {"id": 1, "filename": "b.mp4"}]}
    files = [("a.png", b"PNG"), ("b.mp4", b"MP4!")]
    body, boundary = discord.multipart(payload, files)
    parts = body.split(f"--{boundary}".encode())
    assert parts[-1] == b"--\r\n"
    assert b'Content-Disposition: form-data; name="payload_json"\r\nContent-Type: application/json' in parts[1]
    assert json.dumps(payload).encode() in parts[1]
    assert b'Content-Disposition: form-data; name="files[0]"; filename="a.png"\r\nContent-Type: image/png' in parts[2]
    assert b'Content-Disposition: form-data; name="files[1]"; filename="b.mp4"\r\nContent-Type: video/mp4' in parts[3]
    assert parts[2].endswith(b"\r\n\r\nPNG\r\n") and parts[3].endswith(b"\r\n\r\nMP4!\r\n")

    seen = []

    def opener(request):
        seen.append(request)
        return FakeResponse(b'{"id": "1"}')

    answer = discord.post("https://discord.example/api/webhooks/1/secret", payload, files, opener=opener)
    assert answer == {"id": "1"}
    (request,) = seen
    assert request.full_url == "https://discord.example/api/webhooks/1/secret?wait=true"
    assert request.get_method() == "POST"
    assert request.get_header("Content-type").startswith("multipart/form-data; boundary=")
    boundary = request.get_header("Content-type").split("boundary=")[1]
    assert request.data.startswith(f"--{boundary}\r\n".encode()) and request.data.endswith(f"--{boundary}--\r\n".encode())
    assert b'name="files[1]"; filename="b.mp4"' in request.data and b"\r\n\r\nMP4!\r\n" in request.data


def test_post_errors_name_the_status_and_body_never_the_url():
    def refuse(request):
        raise urllib.error.HTTPError(request.full_url, 400, "Bad Request", {}, io.BytesIO(b'{"message": "no"}'))

    with pytest.raises(DiscordError) as e:
        discord.post("https://discord.example/api/webhooks/1/secret", {"content": "x"}, [], opener=refuse)
    assert "400" in str(e.value) and '{"message": "no"}' in str(e.value)
    assert "secret" not in str(e.value) and "discord.example" not in str(e.value)


def test_content_types():
    assert discord.content_type("a.JPG") == "image/jpeg"
    assert discord.content_type("a.webp") == "image/webp"
    assert discord.content_type("a.mov") == "video/quicktime"
    assert discord.content_type("a.webm") == "video/webm"


# ── the command ───────────────────────────────────────────────────────────────


def _git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args], cwd=repo, check=True, capture_output=True, text=True
    ).stdout


@pytest.fixture
def repo(tmp_path, monkeypatch):
    _git(tmp_path, "init", "-q", "-b", "main")
    (tmp_path / "CHANGELOG.md").write_text(
        "# Changelog\n\nIntro line.\n\n## Unreleased\n\n### Fixed\n- A typo in a quest.\n\n## 0.8.0 - 2026-11-05\n\n"
        "### Added\n- The word list.\n",
        encoding="utf-8",
    )
    (tmp_path / "notes.md").write_text(NOTES, encoding="utf-8")
    _git(tmp_path, "add", ".")
    _git(tmp_path, "commit", "-qm", "init")
    _git(tmp_path, "tag", "v0.8.0")
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("DISCORD_WEBHOOK_URL", raising=False)
    return tmp_path


def test_command_dry_run_prints_and_sends_nothing(repo, capsys, monkeypatch):
    folder = media(repo, {"card.jpg": 4})
    sent = []
    monkeypatch.setattr(discord, "post", lambda *a, **k: sent.append(a))
    rc = announce.run(["--version", VERSION, "--notes", "notes.md", "--media", str(folder), "--dry-run"])
    assert rc == 0 and sent == []
    out = capsys.readouterr().out
    assert "card.jpg" in out and "4 bytes" in out
    payload = json.loads(out[out.index("{") : out.rindex("}") + 1])
    assert payload["embeds"][0]["title"] == "WoW Forever Japanese 0.9.0"


def test_command_needs_the_url(repo, capsys):
    rc = announce.run(["--version", VERSION, "--notes", "notes.md"])
    assert rc == 1
    assert "DISCORD_WEBHOOK_URL is not set" in capsys.readouterr().err


def test_command_posts_with_the_url_from_the_environment(repo, monkeypatch, capsys):
    folder = media(repo, {"card.jpg": 4, "clip.mp4": 6})
    monkeypatch.setenv("DISCORD_WEBHOOK_URL", "https://discord.example/api/webhooks/1/secret")
    sent = []

    def fake_post(url, payload, files, opener=None):
        sent.append((url, payload, files))
        return {"id": "9"}

    monkeypatch.setattr(discord, "post", fake_post)
    assert announce.run(["--version", VERSION, "--notes", "notes.md", "--media", str(folder)]) == 0
    ((url, payload, files),) = sent
    assert url == "https://discord.example/api/webhooks/1/secret"
    assert [name for name, _ in files] == ["card.jpg", "clip.mp4"]
    assert files[0][1] == b"xxxx"
    assert payload["attachments"][1] == {"id": 1, "filename": "clip.mp4"}
    out = capsys.readouterr().out
    assert "secret" not in out and "card.jpg" in out


def test_preview_reads_unreleased_and_next_media(repo, monkeypatch, capsys):
    releases = repo / "docs" / "releases"
    (releases / "next").mkdir(parents=True)
    (releases / "next" / "card.png").write_bytes(b"png")
    monkeypatch.setenv("DISCORD_WEBHOOK_URL", "https://discord.example/api/webhooks/1/test")
    sent = []
    monkeypatch.setattr(discord, "post", lambda url, payload, files, opener=None: sent.append((payload, files)) or {})
    assert announce.run(["--preview", "--media", str(releases)]) == 0
    ((payload, files),) = sent
    assert payload["content"].startswith("Preview of the next release post.")
    assert payload["embeds"][0]["title"] == "WoW Forever Japanese 0.8.1"  # the rule: a Fixed line after 0.8.0
    assert payload["embeds"][0]["description"] == "**Fixed**\n- A typo in a quest."
    assert [name for name, _ in files] == ["card.png"]
    # an empty Unreleased previews as "next" with no notes to show
    (repo / "CHANGELOG.md").write_text(
        "# Changelog\n\nIntro line.\n\n## Unreleased\n\n## 0.8.0 - 2026-11-05\n\n### Added\n- The word list.\n",
        encoding="utf-8",
    )
    assert announce.run(["--preview", "--media", str(releases), "--dry-run"]) == 0
    out = capsys.readouterr().out
    assert re.search(r'"title": "WoW Forever Japanese next"', out)
