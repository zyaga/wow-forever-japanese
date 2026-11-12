"""wfj announce: the Discord post of a release, its limits, the webhook transport and the command
(docs/operations/release.md, ADR-072)."""

import io
import itertools
import json
import re
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
JA = "**追加**\n- ゲーム内で単語を学習できます。\n\n**修正**\n- 競売場の検索。"
EN = "- Study saved words in game.\n- The auction house search is fixed."
NOTES_URL = "https://github.com/zyaga/wow-forever-japanese/releases/tag/v0.9.0"
_folders = itertools.count()


def media(tmp_path: Path, names: dict[str, int], ja: str | None = None, en: str | None = None) -> Path:
    folder = tmp_path / f"media{next(_folders)}"
    folder.mkdir()
    for name, size in names.items():
        (folder / name).write_bytes(b"x" * size)
    if ja is not None:
        (folder / "ja.md").write_text(ja, encoding="utf-8")
    if en is not None:
        (folder / "en.md").write_text(en, encoding="utf-8")
    return folder


def section(text: str = NOTES):
    return announce.notes_section(text)


# ── the post ──────────────────────────────────────────────────────────────────


def test_markdown_renders_groups_and_entries():
    assert announce.markdown(section()) == (
        "**Added**\n- Study your saved words in game: a small tab says how many are due.\n"
        "- A second line that continues.\n\n**Fixed**\n- The auction house search."
    )
    # the Unreleased section of a preview renders the same way as a version's
    assert announce.markdown(section("## Unreleased\n\n### Fixed\n- A typo.\n")) == "**Fixed**\n- A typo."
    with pytest.raises(AnnounceError, match="no changelog section"):
        section("just a line\n")


def test_build_shapes_the_post(tmp_path):
    folder = media(tmp_path, {"b-clip.mp4": 10, "a-card.jpg": 5, "c-card.png": 3}, ja=JA)
    files = announce.media_files(folder)
    assert [f.name for f in files] == ["a-card.jpg", "b-clip.mp4", "c-card.png"]  # name order, ja.md is not media
    payload, second = announce.build(VERSION, section(), files, announce.japanese(folder))
    assert payload["content"] == "WoW Forever Japanese 0.9.0 is out."
    (english,) = payload["embeds"]
    # the Japanese card is a message of its own: Discord allows 6000 characters of cards in one message
    assert set(second) == {"embeds"}
    (japanese,) = second["embeds"]
    assert english["title"] == "WoW Forever Japanese 0.9.0"
    assert english["url"] == "https://www.curseforge.com/wow/addons/wow-forever-japanese/files"
    assert english["color"] == 0xE8C77E == 15255422
    assert english["description"] == announce.markdown(section())
    assert "image" not in english and "thumbnail" not in english  # the files are tiles above the cards, not in them
    assert japanese == {
        "title": "WoW Forever Japanese 0.9.0（日本語）",
        "color": 0xE8C77E,
        "description": f"{JA}\n\n全文: {NOTES_URL}",
    }
    # clips first, then pictures: the tiles at the top of the post
    assert payload["attachments"] == [
        {"id": 0, "filename": "b-clip.mp4"},
        {"id": 1, "filename": "a-card.jpg"},
        {"id": 2, "filename": "c-card.png"},
    ]
    assert [f.name for f in announce.attached(files)] == ["b-clip.mp4", "a-card.jpg", "c-card.png"]
    # nothing but the notes: one card, no attachments
    (only,) = announce.build(VERSION, section(), [], None)
    assert "attachments" not in only and len(only["embeds"]) == 1


def test_two_full_cards_each_fit_a_message():
    long_notes = "## 0.9.0 - 2026-10-21\n\n### Added\n" + "".join(f"- Entry {i} " + "x" * 90 + "\n" for i in range(80))
    messages = announce.build(VERSION, section(long_notes), [], "あ" * announce.MAX_SUMMARY)
    assert len(messages) == 2
    for message in messages:
        size = sum(len(e["title"]) + len(e["description"]) for e in message["embeds"])
        assert size <= announce.MAX_MESSAGE_CARDS


def test_preview_prefix():
    (payload,) = announce.build("next", section(), [], None, preview=True)
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
    with pytest.raises(AnnounceError, match=r"25 MiB for one post"):
        announce.media_files(media(tmp_path, {"a.png": 13 * 1024 * 1024, "b.png": 13 * 1024 * 1024}))
    assert announce.media_files(None) == []
    assert announce.media_files(tmp_path / "absent") == []
    with pytest.raises(AnnounceError, match=r"empty"):
        announce.media_files(media(tmp_path, {"blank.png": 0}))
    with pytest.raises(AnnounceError, match=r"letters, digits"):
        announce.media_files(media(tmp_path, {'q"uote.png': 1}))
    with pytest.raises(AnnounceError, match=r"not folders"):
        folder = media(tmp_path, {"card.png": 1})
        (folder / "cards").mkdir()
        announce.media_files(folder)
    folder = media(tmp_path, {"card.webp": 1})
    (folder / ".DS_Store").write_bytes(b"\0")  # a dotfile is not media
    assert [f.name for f in announce.media_files(folder)] == ["card.webp"]


def test_japanese_card_text(tmp_path):
    assert announce.japanese(None) is None
    assert announce.japanese(media(tmp_path, {})) is None
    assert announce.japanese(media(tmp_path, {}, ja=" " + JA + "\n")) == JA
    with pytest.raises(AnnounceError, match=r"ja\.md is empty"):
        announce.japanese(media(tmp_path, {}, ja="\n"))
    with pytest.raises(AnnounceError, match=r"ja\.md is 1501 characters: the post is a short summary, at most 1500"):
        announce.japanese(media(tmp_path, {}, ja="あ" * 1501))
    assert announce.english(None) is None
    assert announce.english(media(tmp_path, {})) is None
    assert announce.english(media(tmp_path, {}, en=EN + "\n")) == EN
    with pytest.raises(AnnounceError, match=r"en\.md is empty"):
        announce.english(media(tmp_path, {}, en=" "))
    with pytest.raises(AnnounceError, match=r"en\.md is 1501 characters"):
        announce.english(media(tmp_path, {}, en="x" * 1501))


def test_the_post_is_the_summary_with_a_link_to_the_full_notes(tmp_path):
    folder = media(tmp_path, {"card.jpg": 1}, ja=JA, en=EN)
    assert [f.name for f in announce.media_files(folder)] == ["card.jpg"]  # neither summary is media
    first, second = announce.build(VERSION, section(), [], announce.japanese(folder), en=announce.english(folder))
    assert first["embeds"][0]["description"] == f"{EN}\n\nFull notes: {NOTES_URL}"
    assert second["embeds"][0]["description"] == f"{JA}\n\n全文: {NOTES_URL}"
    # a preview has no release page yet: the link goes to the changelog
    first, second = announce.build("0.9.1", section(), [], JA, preview=True, en=EN)
    changelog = "https://github.com/zyaga/wow-forever-japanese/blob/main/CHANGELOG.md"
    assert first["embeds"][0]["description"].endswith(f"Full notes: {changelog}")
    assert second["embeds"][0]["description"].endswith(f"全文: {changelog}")
    # no English summary: the card falls back to the changelog lines
    (only,) = announce.build(VERSION, section(), [], None)
    assert only["embeds"][0]["description"] == announce.markdown(section())


def test_long_notes_are_cut_with_a_link():
    entries = "\n".join(f"- Entry number {i} with enough words to take some room on the line." for i in range(120))
    notes = f"## 0.9.0 - 2026-11-07\n\n### Added\n{entries}\n"
    text = announce.description(VERSION, section(notes))
    assert len(text) <= announce.MAX_DESCRIPTION
    lines = text.split("\n")
    assert lines[-1] == "Full notes: https://github.com/zyaga/wow-forever-japanese/releases/tag/v0.9.0"
    assert lines[-2].startswith("- Entry number ") and lines[-2].endswith("line.")  # cut at an entry boundary
    assert "Full notes" not in announce.description(VERSION, section())


# ── the transport ─────────────────────────────────────────────────────────────


class FakeResponse(io.BytesIO):
    status = 200


def test_multipart_body_and_post(monkeypatch):
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

    def fake_urlopen(request, timeout=None):
        seen.append(request)
        return FakeResponse(b'{"id": "1"}')

    monkeypatch.setattr(discord.urllib.request, "urlopen", fake_urlopen)
    answer = discord.post("https://discord.example/api/webhooks/1/secret", payload, files)
    assert answer == {"id": "1"}
    (request,) = seen
    assert request.full_url == "https://discord.example/api/webhooks/1/secret?wait=true"
    assert request.get_method() == "POST"
    sent_boundary = request.get_header("Content-type").split("boundary=")[1]
    assert request.data.startswith(f"--{sent_boundary}\r\n".encode())
    assert request.data.endswith(f"--{sent_boundary}--\r\n".encode())
    assert b'name="files[1]"; filename="b.mp4"' in request.data and b"\r\n\r\nMP4!\r\n" in request.data


def test_post_errors_name_the_status_and_body_never_the_url(monkeypatch):
    def refuse(request, timeout=None):
        raise urllib.error.HTTPError(request.full_url, 400, "Bad Request", {}, io.BytesIO(b'{"message": "no"}'))

    monkeypatch.setattr(discord.urllib.request, "urlopen", refuse)
    with pytest.raises(DiscordError) as e:
        discord.post("https://discord.example/api/webhooks/1/secret", {"content": "x"}, [])
    assert "400" in str(e.value) and '{"message": "no"}' in str(e.value)
    assert "secret" not in str(e.value) and "discord.example" not in str(e.value)
    for url in ("hooks/1/not-a-url", "https://discord.example/api/webhooks/1/not-a-url\n", "https://x/ not-a-url"):
        with pytest.raises(DiscordError) as bad:  # a malformed secret is refused without being repeated
            discord.post(url, {"content": "x"}, [])
        assert "not-a-url" not in str(bad.value) and "https" in str(bad.value)

    def broken(request, timeout=None):
        raise ValueError("unknown url type: 'secret-token'")

    monkeypatch.setattr(discord.urllib.request, "urlopen", broken)
    with pytest.raises(DiscordError) as e2:
        discord.post("https://discord.example/api/webhooks/1/secret", {"content": "x"}, [])
    assert "ValueError" in str(e2.value) and "secret" not in str(e2.value)


def test_post_keeps_an_existing_query(monkeypatch):
    seen = []
    monkeypatch.setattr(
        discord.urllib.request, "urlopen", lambda request, timeout=None: seen.append(request) or FakeResponse(b"{}")
    )
    discord.post("https://discord.example/api/webhooks/1/t?thread_id=5", {"content": "x"}, [])
    assert seen[0].full_url == "https://discord.example/api/webhooks/1/t?thread_id=5&wait=true"


def test_content_types():
    assert discord.content_type("a.JPG") == "image/jpeg"
    assert discord.content_type("a.webp") == "image/webp"
    assert discord.content_type("a.mov") == "video/quicktime"
    assert discord.content_type("a.webm") == "video/webm"
    assert discord.content_type("a.txt") is None and discord.content_type("noext") is None


# ── the command ───────────────────────────────────────────────────────────────

RELEASED = "# Changelog\n\nIntro line.\n\n## Unreleased\n\n## 0.8.0 - 2026-11-05\n\n### Added\n- The word list.\n"
CHANGELOG = RELEASED.replace("## Unreleased\n\n", "## Unreleased\n\n### Fixed\n- A typo in a quest.\n\n")


@pytest.fixture
def repo(git_repo, git, monkeypatch):
    """0.8.0 released and tagged, then one commit adding a Fixed line under Unreleased: the shape of a repo
    between releases."""
    monkeypatch.delenv("DISCORD_WEBHOOK_URL", raising=False)
    path = git_repo({"CHANGELOG.md": RELEASED, "notes.md": NOTES}, tags=["v0.8.0"])
    (path / "CHANGELOG.md").write_text(CHANGELOG, encoding="utf-8")
    git(path, "commit", "-qam", "a fix")
    return path


def test_command_dry_run_prints_and_sends_nothing(repo, capsys, monkeypatch):
    folder = media(repo, {"card.jpg": 4})
    sent = []
    monkeypatch.setattr(discord, "post", lambda *a: sent.append(a))
    rc = announce.run(["--version", VERSION, "--notes", "notes.md", "--media", str(folder), "--dry-run"])
    assert rc == 0 and sent == []
    out = capsys.readouterr().out
    assert "card.jpg" in out and "4 bytes" in out and "no ja.md in" in out
    payload = json.loads(out[out.index("{") : out.rindex("}") + 1])
    assert payload["embeds"][0]["title"] == "WoW Forever Japanese 0.9.0"
    assert announce.run(["--version", VERSION, "--notes", "notes.md", "--media", "absent", "--dry-run"]) == 0
    assert "no media folder at absent" in capsys.readouterr().out


def test_command_needs_the_url(repo, capsys):
    rc = announce.run(["--version", VERSION, "--notes", "notes.md"])
    assert rc == 1
    assert "DISCORD_WEBHOOK_URL is not set" in capsys.readouterr().err


def test_command_posts_with_the_url_from_the_environment(repo, monkeypatch, capsys):
    folder = media(repo, {"card.jpg": 4, "clip.mp4": 6}, ja=JA)
    monkeypatch.setenv("DISCORD_WEBHOOK_URL", "https://discord.example/api/webhooks/1/secret")
    sent = []

    def fake_post(url, payload, files):
        sent.append((url, payload, files))
        return {"id": str(len(sent))}

    monkeypatch.setattr(discord, "post", fake_post)
    assert announce.run(["--version", VERSION, "--notes", "notes.md", "--media", str(folder)]) == 0
    (url, payload, files), (url2, second, files2) = sent
    assert url == url2 == "https://discord.example/api/webhooks/1/secret"
    assert files == [("clip.mp4", b"xxxxxx"), ("card.jpg", b"xxxx")]  # the clip first, the way the tiles show
    assert payload["attachments"] == [{"id": 0, "filename": "clip.mp4"}, {"id": 1, "filename": "card.jpg"}]
    assert len(payload["embeds"]) == 1
    assert files2 == [] and second["embeds"][0]["description"].startswith(JA)  # the Japanese card follows, no files
    out = capsys.readouterr().out
    assert "secret" not in out and "card.jpg" in out and "2 file(s)" in out


def test_preview_reads_unreleased_and_the_media_folder(repo, monkeypatch, capsys):
    waiting = repo / "docs" / "releases" / "next"
    waiting.mkdir(parents=True)
    (waiting / "card.png").write_bytes(b"png")
    monkeypatch.setenv("DISCORD_WEBHOOK_URL", "https://discord.example/api/webhooks/1/test")
    sent = []
    monkeypatch.setattr(discord, "post", lambda url, payload, files: sent.append((payload, files)) or {})
    assert announce.run(["--preview", "--media", str(waiting)]) == 0
    ((payload, files),) = sent
    assert payload["content"].startswith("Preview of the next release post.")
    assert payload["embeds"][0]["title"] == "WoW Forever Japanese 0.8.1"  # the release's rule: a Fixed line after 0.8.0
    assert payload["embeds"][0]["description"] == "**Fixed**\n- A typo in a quest."
    assert [name for name, _ in files] == ["card.png"]
    # an empty Unreleased previews as "next" with no notes to show
    (repo / "CHANGELOG.md").write_text(RELEASED, encoding="utf-8")
    assert announce.run(["--preview", "--media", str(waiting), "--dry-run"]) == 0
    out = capsys.readouterr().out
    assert re.search(r'"title": "WoW Forever Japanese next"', out)
    # the version and the notes come from the changelog alone
    assert announce.run(["--preview", "--version", "1.0.0"]) == 1
    assert "takes its version and notes" in capsys.readouterr().err
