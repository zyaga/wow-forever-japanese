"""A collector send (ADR-056): the string the game's send window packs, the issue check, and the intake
that imports it with the same rules as a dump file."""

import base64
import io
import json
import zipfile
import zlib
from pathlib import Path

import pytest

from wfj.cmd import collector
from wfj.cmd.import_ import run as import_run
from wfj.core.hashing import key
from wfj.core.normalize import normalize_v1
from wfj.io import collector_send
from wfj.io.collector_send import SendError, decode
from wfj.io.lua_reader import Table, parse_assignments

FIXTURE = "tests/fixtures/collector/WoWForeverJapanese.lua"


def _plain(v):
    """A Lua reader value → plain JSON values (the shape the client's SerializeJSON writes)."""
    if isinstance(v, Table):
        if all(k is None for k, _ in v.items):
            return [_plain(x) for _, x in v.items]
        return {k: _plain(x) for k, x in v.items if k is not None}
    return v


def pack(entries, builds, addon="1.0.0", version=1, wrap=None):
    """What the addon's send window makes: PREFIX + URL-safe Base64 of zlib-compressed JSON {v, a, b, e}."""
    raw = json.dumps({"v": version, "a": addon, "b": builds, "e": entries}).encode("utf-8")
    text = base64.urlsafe_b64encode(zlib.compress(raw)).decode("ascii")
    s = collector_send.PREFIX + text
    if wrap:
        s = "\n".join(s[i : i + wrap] for i in range(0, len(s), wrap))
    return s


def fixture_send(root: Path) -> tuple[list, list]:
    dump = parse_assignments((root / FIXTURE).read_text(encoding="utf-8"))["WFJ_Collector"]
    entries = [_plain(raw) for _, raw in dump.get("entries").items]
    builds = [v for _, v in dump.get("builds").items]
    return entries, builds


def entry(t, i, f, e, b=1, **more):
    return {"t": t, "i": i, "f": f, "h": key(normalize_v1(e)), "e": e, "b": b, **more}


def body(dump_text, consent=True, note=""):
    tick = "- [X]" if consent else "- [ ]"
    return (
        f"### Collected English\n\n{dump_text}\n\n### Note\n\n{note or '_No response_'}\n\n"
        f"### Permission\n\n{tick} It contains only what is described above.\n"
    )


# --- decode -----------------------------------------------------------------------------------------


def test_decode_reads_every_fixture_entry(root):
    entries, builds = fixture_send(root)
    send = decode(pack(entries, builds, addon="0.1.0-alpha.5"))
    assert send.addon == "0.1.0-alpha.5" and send.source == "string"
    assert len(send.dump.entries) == len(entries) == 12
    assert not send.dump.rejected
    goodbye = [en for en in send.dump.entries if en.en == "Goodbye."]
    assert goodbye and goodbye[0].npcs == (68, 295)


def test_decode_takes_numbers_the_client_wrote_as_floats_and_a_wrapped_paste():
    e = entry("quest", 7, "title", "A Fine Day", b=1)
    e["i"], e["b"] = 7.0, 1.0
    send = decode(pack([e], ["1.60.1.70170"], wrap=76))
    assert [(en.type_, en.id_, en.field, en.build) for en in send.dump.entries] == [
        ("quest", 7, "title", "1.60.1.70170")
    ]


def test_decode_rejects_like_a_dump_file():
    good = entry("quest", 7, "title", "A Fine Day")
    bad_hash = dict(entry("quest", 8, "title", "Other"), h="0" * 16)
    jp = entry("quest", 9, "title", "日本語")
    dup = entry("item", 5, "description", "Twice.")
    no_build = entry("spell", 3, "description", "Burns.", b=9)
    send = decode(pack([good, bad_hash, jp, dup, dict(dup), no_build], ["1.60.1.70170"]))
    assert [en.id_ for en in send.dump.entries] == [7]
    assert dict(send.dump.rejected) == {
        "hash_mismatch": 1,
        "not_english": 1,
        "duplicate_key": 2,
        "no_build": 1,
    }


@pytest.mark.parametrize(
    "text, why",
    [
        ("WFJX1:abc", "does not start with"),
        ("WFJC1:@@@@", "does not decode"),
        ("WFJC1:" + base64.urlsafe_b64encode(b"not zlib").decode(), "does not unpack"),
        ("WFJC1:" + base64.urlsafe_b64encode(zlib.compress(b"{not json")).decode(), "does not read"),
        ("WFJC1:" + base64.urlsafe_b64encode(zlib.compress(b'{"v": 2}')).decode(), "does not read (v = 2)"),
    ],
)
def test_decode_says_why_a_string_does_not_read(text, why):
    with pytest.raises(SendError, match=why.replace("(", r"\(").replace(")", r"\)")):
        decode(text)


def test_a_cut_paste_does_not_read(root):
    entries, builds = fixture_send(root)
    s = pack(entries, builds)
    with pytest.raises(SendError):
        decode(s[: len(s) // 2])


def test_decode_refuses_text_over_the_limit():
    with pytest.raises(SendError, match="longer than"):
        decode("WFJC1:" + "A" * collector_send.MAX_TEXT)


# --- check ------------------------------------------------------------------------------------------


def test_check_counts_and_never_echoes_the_english(root):
    entries, builds = fixture_send(root)
    ok, text = collector.summary(body(pack(entries, builds, addon="0.1.0`@x")))
    assert ok
    assert "**This send reads.**" in text and "| Entries | 12 |" in text and "| quest |" in text
    assert "1.15.9.69722" in text and "`0.1.0'＠x`" in text
    for en in entries:
        assert en["e"] not in text


def test_check_reads_the_string_anywhere_in_the_body():
    s = pack([entry("quest", 7, "title", "A Fine Day")], ["1.60.1.70170"])
    ok, _ = collector.summary(f"Here it is:\n{s}\n")
    assert ok


def test_check_fails_with_a_reason_a_player_can_act_on():
    ok, text = collector.summary(body("I forgot to paste it"))
    assert not ok and "could not be read" in text and "WFJC1:" in text and "/wfj collector send all" in text
    ok, text = collector.summary(body("WFJC1:@@@@"))  # the string stops at the first character outside Base64
    assert not ok and "is not complete" in text


def test_check_fails_a_send_with_no_valid_entry():
    ok, text = collector.summary(body(pack([dict(entry("quest", 7, "title", "X"), h="0" * 16)], ["1.60.1.70170"])))
    assert not ok and "no line that can be imported" in text and "hash_mismatch 1" in text


def _zip(text: str) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("WoWForeverJapanese.lua", text)
    return buf.getvalue()


def test_check_reads_an_attached_zip(root):
    url = "https://github.com/user-attachments/files/123/WoWForeverJapanese.zip"
    blob = _zip((root / FIXTURE).read_text(encoding="utf-8"))
    ok, text = collector.summary(body(f"[WoWForeverJapanese.zip]({url})"), download=lambda u: blob)
    assert ok and "the attached file" in text and "| Entries | 12 |" in text


def test_only_github_attachments_are_downloaded():
    with pytest.raises(SendError, match="not a GitHub attachment"):
        collector_send.fetch_attachment("https://example.com/files/1/x.zip")
    sent, attached = collector_send.find(body("[x](https://example.com/files/1/x.zip)"), {})
    assert sent is None and attached is None


def test_check_cli_exit_codes(tmp_path: Path, capsys):
    good = tmp_path / "good.txt"
    good.write_text(body(pack([entry("quest", 7, "title", "A Fine Day")], ["1.60.1.70170"])), encoding="utf-8")
    bad = tmp_path / "bad.txt"
    bad.write_text(body("nothing"), encoding="utf-8")
    assert collector.run(["check", "--body-file", str(good)]) == 0
    assert collector.run(["check", "--body-file", str(bad)]) == 1
    assert "could not be read" in capsys.readouterr().out


# --- intake -----------------------------------------------------------------------------------------


def _data_dir(tmp_path: Path, monkeypatch) -> Path:
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    monkeypatch.chdir(tmp_path)
    return tmp_path / "data"


def _snapshot(data: Path) -> dict[str, bytes]:
    return {str(p.relative_to(data)): p.read_bytes() for p in sorted((data / "english").rglob("*.jsonl"))}


def test_intake_imports_exactly_what_the_file_import_does(root, tmp_path: Path, monkeypatch, capsys):
    entries, builds = fixture_send(root)
    saved = tmp_path / "body.txt"
    saved.write_text(body(pack(entries, builds)), encoding="utf-8")

    by_file = tmp_path / "file"
    by_file.mkdir()
    data_a = _data_dir(by_file, monkeypatch)
    assert import_run(["english", "collector", str(root / FIXTURE)]) == 0
    from_file = _snapshot(data_a)

    by_issue = tmp_path / "issue"
    by_issue.mkdir()
    data_b = _data_dir(by_issue, monkeypatch)
    capsys.readouterr()
    assert collector.run(["intake", "--file", str(saved), "--number", "41"]) == 0
    out = capsys.readouterr().out
    assert "english collector: issue #41 · 12 entries" in out and "rejected: none" in out
    assert _snapshot(data_b) == from_file
    assert collector.run(["intake", "--file", str(saved), "--number", "41"]) == 0  # again: byte no-op
    assert _snapshot(data_b) == from_file


def test_intake_refuses_an_issue_without_permission(tmp_path: Path, monkeypatch, capsys):
    data = _data_dir(tmp_path, monkeypatch)
    saved = tmp_path / "body.txt"
    saved.write_text(body(pack([entry("quest", 7, "title", "A Fine Day")], ["1.60.1.70170"]), consent=False))
    assert collector.run(["intake", "--file", str(saved), "--number", "5"]) == 1
    assert "Permission box is not ticked" in capsys.readouterr().out
    assert not (data / "english").exists() or not _snapshot(data)


def test_intake_says_why_a_send_does_not_read(tmp_path: Path, monkeypatch, capsys):
    _data_dir(tmp_path, monkeypatch)
    saved = tmp_path / "body.txt"
    saved.write_text(body("WFJC1:@@@@"))
    assert collector.run(["intake", "--file", str(saved), "--number", "5"]) == 1
    assert "is not complete" in capsys.readouterr().out


# --- hostile and odd input ----------------------------------------------------------------------------


def test_hostile_json_is_a_broken_send_not_a_crash():
    deep = "WFJC1:" + base64.urlsafe_b64encode(zlib.compress(b"[" * 200_000)).decode()
    with pytest.raises(SendError, match="does not read"):
        decode(deep)
    huge = "WFJC1:" + base64.urlsafe_b64encode(zlib.compress(b'{"v": 1, "e": [' + b"9" * 5000 + b"]}")).decode()
    with pytest.raises(SendError, match="does not read"):
        decode(huge)


def test_ids_past_32_bits_are_rejected():
    e = entry("quest", 2**31, "title", "Too Far")
    big = dict(entry("quest", 7, "title", "Huge"), i=1e300)
    send = decode(pack([e, big], ["1.60.1.70170"]))
    assert send.dump.entries == [] and send.dump.rejected["bad_id"] == 2


def test_a_note_after_the_string_is_not_read_as_part_of_it():
    s = pack([entry("quest", 7, "title", "A Fine Day")], ["1.60.1.70170"])
    found, _ = collector_send.find(f"```\n{s}```\nthanks\n", {})
    assert found == s
    found, _ = collector_send.find(f"{s}\nthanks", {})
    assert found == s


def test_a_zipped_folder_reads_the_addon_file(root):
    url = "https://github.com/user-attachments/files/9/SavedVariables.zip"
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("SavedVariables/Blizzard_Console.lua", "x = 1")
        z.writestr("__MACOSX/SavedVariables/._WoWForeverJapanese.lua", "junk")
        z.writestr("SavedVariables/WoWForeverJapanese.lua", (root / FIXTURE).read_text(encoding="utf-8"))
    ok, text = collector.summary(body(f"[x]({url})"), download=lambda u: buf.getvalue())
    assert ok and "| Entries | 12 |" in text


def test_an_encrypted_or_broken_zip_is_a_broken_send():
    url = "https://github.com/user-attachments/files/9/WoWForeverJapanese.zip"
    blob = bytearray(_zip("WFJ_Collector = {}"))
    blob[30 + len("WoWForeverJapanese.lua") + 2] ^= 0xFF  # corrupt the member's data
    ok, text = collector.summary(body(f"[x]({url})"), download=lambda u: bytes(blob))
    assert not ok and "could not be read" in text
    ok, text = collector.summary(body(f"[x]({url})"), download=lambda u: b"not a zip")
    assert not ok and "not a zip file" in text


def test_the_comment_keeps_its_table_whatever_the_version_says(root):
    entries, builds = fixture_send(root)
    ok, text = collector.summary(body(pack(entries, builds, addon="1|2\n### x")))
    assert ok and "`1/2 ### x`" in text
    many = [f"1.60.1.{70000 + n}" for n in range(9)]
    es = [entry("quest", n + 1, "title", f"Quest {n}", b=n + 1) for n in range(9)]
    ok, text = collector.summary(body(pack(es, many)))
    assert ok and "and 4 more" in text


def test_intake_lists_the_lines_it_replaces(tmp_path: Path, monkeypatch, capsys):
    from wfj.core.model import english_line
    from wfj.io.jsonl_store import Store

    data = _data_dir(tmp_path, monkeypatch)
    old = "Old Title"
    Store(data, english=True).save("quest", [english_line(7, "title", old, key(normalize_v1(old)), "pfquest@7786596")])
    saved = tmp_path / "body.txt"
    saved.write_text(body(pack([entry("quest", 7, "title", "New Title")], ["1.60.1.70170"])))
    assert collector.run(["intake", "--file", str(saved), "--number", "5"]) == 0
    out = capsys.readouterr().out
    assert "replaced:\n  quest 7 title (was pfquest@7786596)" in out
