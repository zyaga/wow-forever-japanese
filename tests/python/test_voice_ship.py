"""`wfj voice pack|release`: the entry and the packs named for what they hold, the 420 MB cap, versions and
change detection, the zip check and the CurseForge upload payload (ADR-062; pipeline/voice-packs.toml)."""

from __future__ import annotations

import argparse
import datetime
import json
import shutil
import subprocess
import zipfile
from pathlib import Path

import pytest
from test_voice import CFG, _gen, _store, engine  # noqa: F401 (engine is a fixture)

from wfj.cmd import voice_ship as vs
from wfj.core import voice_packs as vp
from wfj.emit import voice_pack
from wfj.io import curseforge

ROOT = Path(__file__).resolve().parents[2]
TABLE = ROOT / "pipeline" / "voice-packs.toml"
DAY = datetime.date(2026, 10, 7)


def _raw(**over):
    raw = {
        "cap_mb": 420,
        "warn_mb": 315,
        "addon_slug": "main",
        "entry": {"folder": "WoWForeverJapanese_Voice", "title": "E", "slug": "e", "project_id": 1, "holds": "x"},
        "pack": [
            {"folder": "WoWForeverJapanese_VoiceA", "title": "A", "slug": "a", "project_id": 2, "holds": "x",
             "levels": [1, 10]},
            {"folder": "WoWForeverJapanese_VoiceB", "title": "B", "slug": "b", "project_id": 0, "holds": "x",
             "levels": [11, 20]},
            {"folder": "WoWForeverJapanese_VoiceOther", "title": "O", "slug": "o", "project_id": 3, "holds": "x"},
        ],
    }
    raw.update(over)
    return raw


# ---- the table -------------------------------------------------------------------------------------------


def test_the_committed_table_is_the_entry_and_seven_packs():
    t = vp.load(TABLE)
    assert t.entry.folder == voice_pack.FOLDER == "WoWForeverJapanese_Voice"
    assert [p.levels for p in t.packs] == [(1, 10), (11, 20), (21, 30), (31, 40), (41, 50), (51, 60), None]
    assert [p.folder.removeprefix(vp.PREFIX) for p in t.packs] == [
        "Levels1to10", "Levels11to20", "Levels21to30", "Levels31to40", "Levels41to50", "Levels51to60", "Other"]
    assert all("part" not in p.title.lower() for p in (t.entry, *t.packs))  # named for what they hold
    assert (t.cap_mb, t.warn_mb) == (420, 315)
    assert t.addon_slug == "wow-forever-japanese"  # the entry requires the main addon


@pytest.mark.parametrize(
    ("change", "message"),
    [
        (lambda r: r["pack"][1].update(levels=[12, 20]), "must start at 11"),
        (lambda r: r["pack"][1].update(levels=[10, 20]), "must start at 11"),
        (lambda r: r["pack"].pop(), "every pack but the last has a band"),
        (lambda r: r["pack"][2].update(slug="a"), "the same slug twice: a"),
        (lambda r: r["pack"][0].update(folder="VoiceA"), "must start with WoWForeverJapanese_Voice"),
        (lambda r: r.update(warn_mb=420), "warn_mb under cap_mb"),
        (lambda r: r["entry"].update(levels=[1, 2]), "takes no levels"),
        (lambda r: r["pack"][0].update(project_id=-1), "project_id"),
        (lambda r: r.pop("addon_slug"), "addon_slug"),
        (lambda r: r.update(addon_slug="a"), "addon_slug"),
    ],
)
def test_a_broken_table_is_refused(change, message):
    raw = _raw()
    change(raw)
    with pytest.raises(ValueError, match=message):
        vp.parse(raw)


def test_a_level_finds_its_band_and_anything_else_goes_to_the_last_pack():
    t = vp.load(TABLE)
    name = {lv: vp.band(t, lv).folder.removeprefix(vp.PREFIX) for lv in (None, 0, -1, 1, 10, 11, 55, 60, 61, 70)}
    assert name == {None: "Other", 0: "Other", -1: "Other", 1: "Levels1to10", 10: "Levels1to10",
                    11: "Levels11to20", 55: "Levels51to60", 60: "Levels51to60", 61: "Other", 70: "Other"}


# ---- the split -------------------------------------------------------------------------------------------


SPEAKERS = [
    {"key": "100-description", "speaker": 7},
    {"key": "200-completion", "speaker": 8, "others": [7]},
    {"key": "300-progress", "speaker": 9},
    {"key": "g-aaaaaaaaaaaaaaaa", "speaker": 7},  # 7 starts 100 (level 25) and ends 200 (level 8)
    {"key": "g-bbbbbbbbbbbbbbbb", "speaker": 50},  # no quests
    {"key": "g-cccccccccccccccc", "speaker": "narrator"},
    {"key": "g-dddddddddddddddd", "speaker": 9},  # its only quest has no level
]
LEVELS = {100: 25, 200: 8}


def _assign(key, speakers=SPEAKERS, levels=LEVELS):
    t = vp.load(TABLE)
    rows = {r["key"]: r for r in speakers}
    return vp.assign(t, key, levels, rows, vp.creature_quests(speakers)).folder.removeprefix(vp.PREFIX)


def test_each_kind_of_line_goes_to_its_pack():
    assert _assign("100-description") == "Levels21to30"
    assert _assign("200-completion") == "Levels1to10"
    assert _assign("300-progress") == "Other"  # no known level
    assert _assign("g-aaaaaaaaaaaaaaaa") == "Levels1to10"  # the lowest band of its NPC's quests
    assert _assign("g-bbbbbbbbbbbbbbbb") == "Levels1to10"  # an NPC with no quests: the first band
    assert _assign("g-cccccccccccccccc") == "Levels1to10"
    assert _assign("g-dddddddddddddddd") == "Levels1to10"
    assert _assign("b-0123456789abcdef") == "Other"  # books and letters
    assert _assign("e-2h_skillnotfound") == "Other"  # the character's error lines


def test_a_line_never_moves_when_other_lines_arrive():
    keys = [r["key"] for r in SPEAKERS]
    before = {k: _assign(k) for k in keys}
    more = [*SPEAKERS, {"key": "400-description", "speaker": 51}, {"key": "g-eeeeeeeeeeeeeeee", "speaker": 51},
            {"key": "500-completion", "speaker": 52}]
    after = {k: _assign(k, list(reversed(more)), {**LEVELS, 400: 44, 500: 59}) for k in keys}
    assert after == before


def test_the_content_hash_ignores_order_and_follows_the_content():
    rows = [{"file": "a", "ja_hash": "1"}, {"file": "b", "ja_hash": "2"}]
    h = vp.content_hash(rows, "reg", "16001")
    assert h == vp.content_hash(list(reversed(rows)), "reg", "16001")
    assert h != vp.content_hash([rows[0], {"file": "b", "ja_hash": "3"}], "reg", "16001")
    assert h != vp.content_hash(rows, "reg2", "16001")
    assert h != vp.content_hash(rows, "reg", "16002")  # an interface bump re-releases every pack
    t = vp.parse(_raw())
    assert vp.entry_hash(t, "16001") == vp.entry_hash(vp.parse(_raw()), "16001")
    fewer = _raw()
    fewer["pack"].pop(1)
    assert vp.entry_hash(t, "16001") != vp.entry_hash(vp.parse(fewer), "16001")


def test_versions_and_the_names_of_released_assets():
    v = vp.version(DAY, "0123456789abcdef")
    assert v == "2026.10.07-01234567"
    assert vp.asset_name("WoWForeverJapanese_VoiceA", v) == "WoWForeverJapanese_VoiceA-2026.10.07-01234567.zip"
    names = ["WoWForeverJapanese_VoiceA-2026.10.07-01234567.zip", "WoWForeverJapanese_Voice-2026.10.01-89abcdef.zip",
             "WoWForeverJapanese_Voice-all-2026.10.07.zip", "notes.txt"]
    assert vp.released(names) == {"WoWForeverJapanese_VoiceA": "2026.10.07-01234567",
                                  "WoWForeverJapanese_Voice": "2026.10.01-89abcdef"}
    assert not vp.changed("01234567ffff", "2026.10.07-01234567")
    assert vp.changed("01234568ffff", "2026.10.07-01234567")
    assert vp.changed("01234567ffff", None)


# ---- the build -------------------------------------------------------------------------------------------


def _table_file(tmp_path, **over):
    raw = _raw(**over)
    lines = [f"cap_mb = {raw['cap_mb']}", f"warn_mb = {raw['warn_mb']}", f"addon_slug = {json.dumps(raw['addon_slug'])}",
             "", "[entry]"]
    lines += [f"{k} = {json.dumps(v)}" for k, v in raw["entry"].items()]
    for p in raw["pack"]:
        lines += ["", "[[pack]]", *(f"{k} = {json.dumps(v)}" for k, v in p.items())]
    path = tmp_path / "voice-packs.toml"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def _project(tmp_path, engine):  # noqa: F811
    data = _store(tmp_path)
    toc = tmp_path / "addon" / "WoWForeverJapanese"
    toc.mkdir(parents=True)
    (toc / "WoWForeverJapanese.toc").write_text("## Interface: 16001\n## Title: x\n")
    store = tmp_path / "voice"
    _gen(data, store, engine)
    cfg = tmp_path / "voice.toml"
    cfg.write_text(
        'engine = "x"\nspeed_scale = 0.9\nnarrator = "m"\nbook_narrator = "m"\n'
        '[roster.m]\nmodel = "M"\nstyle = 11\nlicence = "ACML 1.0"\n'
        '[roster.f]\nmodel = "F"\nstyle = 22\nlicence = "ACML 1.0"\n'
        '[roster.old]\nmodel = "F"\nstyle = 22\nspeed = 0.85\npitch = -0.05\nlicence = "CC0"\n'
        '[credits]\nengine = "E"\n'
    )
    return data, store, cfg


def _args(tmp_path, store, cfg, table, **over):
    a = argparse.Namespace(config=str(cfg), packs=str(table), store=str(store), out=str(tmp_path / "out"),
                           wdb=None, vmangos=None, players=None, dry_run=True, curseforge_only=False,
                           only=None, entry_without_packs=False,
                           levels="", pin="")
    vars(a).update(over)
    return a


def test_pack_writes_the_entry_and_every_pack(tmp_path, engine, monkeypatch):  # noqa: F811
    data, store, cfg = _project(tmp_path, engine)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(vs.voice_store, "read_levels", lambda *_: {456: 5})
    table = _table_file(tmp_path)
    assert vs.run_pack(_args(tmp_path, store, cfg, table)) == 0
    out = tmp_path / "out"
    assert sorted(p.name for p in out.iterdir()) == [
        "WoWForeverJapanese_Voice", "WoWForeverJapanese_VoiceA", "WoWForeverJapanese_VoiceB",
        "WoWForeverJapanese_VoiceOther"]
    # the entry: a TOC and a README, no audio, no Register.lua; its TOC carries its project id
    entry = out / "WoWForeverJapanese_Voice"
    assert sorted(p.name for p in entry.iterdir()) == ["README.txt", "WoWForeverJapanese_Voice.toc"]
    toc = (entry / "WoWForeverJapanese_Voice.toc").read_text()
    assert "## Dependencies: WoWForeverJapanese\n" in toc and "## X-Curse-Project-ID: 1\n" in toc
    assert "Register.lua" not in toc
    main_icon = next(ln for ln in (ROOT / "addon" / "WoWForeverJapanese" / "WoWForeverJapanese.toc").read_text(
        encoding="utf-8").splitlines() if ln.startswith("## IconTexture:"))
    assert main_icon + "\n" in toc  # the same 字 icon as the main addon in the AddOn List
    # quest 456 is level 5, and the narrator's gossip goes to the first band
    a = out / "WoWForeverJapanese_VoiceA"
    assert sorted(p.name for p in (a / "Sound").iterdir()) == [
        "456-completion.mp3", "456-description.mp3", "g-0123456789abcdef.mp3"]
    reg = (a / "Register.lua").read_text()
    assert 'folder = "WoWForeverJapanese_VoiceA"' in reg
    atoc = (a / "WoWForeverJapanese_VoiceA.toc").read_text()
    assert "## Title: A\n" in atoc and "## X-Curse-Project-ID: 2\n" in atoc
    assert main_icon + "\n" in atoc
    notes = next(ln for ln in atoc.splitlines() if ln.startswith("## Notes:"))
    assert notes.isascii() and "README.txt" in notes  # the AddOn List tooltip shows no Japanese glyphs
    assert "## Version: 2026." in atoc or "## Version: 20" in atoc
    assert "X-Curse-Project-ID" not in (out / "WoWForeverJapanese_VoiceB" / "WoWForeverJapanese_VoiceB.toc").read_text()
    assert not list((out / "WoWForeverJapanese_VoiceB" / "Sound").iterdir())
    luac = shutil.which("luac") or shutil.which("luac5.1")
    if luac:
        subprocess.run([luac, "-p", str(a / "Register.lua")], check=True)


def test_a_pack_over_the_cap_is_refused_and_nothing_is_written(tmp_path, engine, monkeypatch, capsys):  # noqa: F811
    data, store, cfg = _project(tmp_path, engine)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(vs.voice_store, "read_levels", lambda *_: {456: 5})
    monkeypatch.setattr(vp, "MB", 1)  # count bytes as MB: the test's files are a few bytes
    table = _table_file(tmp_path, cap_mb=20, warn_mb=10)
    assert vs.run_pack(_args(tmp_path, store, cfg, table)) == 1
    err = capsys.readouterr()
    assert "WoWForeverJapanese_VoiceA over the 20 MB cap; nothing written" in err.err
    assert not (tmp_path / "out").exists()
    # under the cap but past the warning line: built, and the table says so
    table = _table_file(tmp_path, cap_mb=200, warn_mb=10)
    assert vs.run_pack(_args(tmp_path, store, cfg, table)) == 0
    assert "past 10 MB: plan its split" in capsys.readouterr().out


def test_the_zip_check(tmp_path):
    src = tmp_path / "out" / "WoWForeverJapanese_VoiceA"
    (src / "Sound").mkdir(parents=True)
    for f in ("WoWForeverJapanese_VoiceA.toc", "Register.lua", "README.txt", "Sound/a.mp3", "Sound/stray.mp3"):
        (src / f).write_bytes(b"x")
    z = tmp_path / "a.zip"
    vs.zip_folders(tmp_path / "out", ["WoWForeverJapanese_VoiceA"], z)
    problems = vs.check_zip(z, "WoWForeverJapanese_VoiceA", ["a.mp3", "b.mp3"])
    assert problems == ["a.zip: holds WoWForeverJapanese_VoiceA/Sound/stray.mp3, which is not in the record",
                        "a.zip: lacks WoWForeverJapanese_VoiceA/Sound/b.mp3"]
    with zipfile.ZipFile(z) as zf:  # MP3s stored as they are
        assert zf.getinfo("WoWForeverJapanese_VoiceA/Sound/a.mp3").compress_type == zipfile.ZIP_STORED


# ---- the release -----------------------------------------------------------------------------------------


def test_the_release_plan_keeps_unchanged_versions_and_names_only_packs_with_a_project():
    t = vp.parse(_raw())
    packs = [vs.Pack(p, digest=f"{n:08x}" + "0" * 56) for n, p in enumerate(t.packs)]
    first = vs.plan_release(t, packs, "16001", {}, DAY)
    assert [p.folder for p in first.upload] == ["WoWForeverJapanese_VoiceA", "WoWForeverJapanese_VoiceOther",
                                                "WoWForeverJapanese_Voice"]  # packs first, the entry last
    assert [p.folder for p in first.no_project] == ["WoWForeverJapanese_VoiceB"]
    later = vs.plan_release(t, packs, "16001", first.versions, DAY + datetime.timedelta(days=3))
    assert later.upload == [] and later.no_project == [] and later.versions == first.versions
    packs[0].digest = "f" * 64
    third = vs.plan_release(t, packs, "16001", first.versions, DAY + datetime.timedelta(days=3))
    assert [p.folder for p in third.upload] == ["WoWForeverJapanese_VoiceA"]
    assert third.versions["WoWForeverJapanese_VoiceA"] == "2026.10.10-ffffffff"
    assert third.versions["WoWForeverJapanese_VoiceOther"] == first.versions["WoWForeverJapanese_VoiceOther"]
    # B gets its project: the entry's set of packs changed, so a new entry file goes up naming it
    with_b = _raw()
    with_b["pack"][1]["project_id"] = 9
    t2 = vp.parse(with_b)
    packs2 = [vs.Pack(p, digest=pk.digest) for p, pk in zip(t2.packs, packs, strict=True)]
    fourth = vs.plan_release(t2, packs2, "16001", third.versions, DAY)
    assert "WoWForeverJapanese_Voice" in [p.folder for p in fourth.upload]
    assert [p.slug for p in vs.required(t2).packs] == ["a", "b", "o"]
    assert [p.slug for p in vs.required(t).packs] == ["a", "o"]
    # the entry requires the main addon first, so the CurseForge app never installs voice without it
    assert vs.entry_requires(t) == ["main", "a", "o"]
    assert vs.entry_requires(vp.load(TABLE))[0] == "wow-forever-japanese"


def _gh(calls, releases, assets):
    def run(args):
        calls.append(list(args))
        if args[:2] == ["release", "list"]:
            return json.dumps(releases)
        if args[:2] == ["release", "view"]:
            return json.dumps({"assets": [{"name": n} for n in assets]})
        return ""
    return run


def test_release_type_tags_and_the_last_voice_release():
    rows = vs.releases(_gh([], [
        {"tagName": "v0.1.0-alpha.8", "createdAt": "2026-10-05T00:00:00Z"},
        {"tagName": "voice-v2026.10.06", "createdAt": "2026-10-06T00:00:00Z"},
        {"tagName": "v0.1.0-alpha.7", "createdAt": "2026-10-01T00:00:00Z"},
    ], []))
    assert vs.release_type(rows) == "alpha"
    assert vs.release_type([{"tagName": "v1.0.0-beta.1"}]) == "beta"
    assert vs.release_type([{"tagName": "v1.0.0"}]) == "release"
    with pytest.raises(ValueError, match="no GitHub release"):
        vs.release_type([{"tagName": "voice-v2026.10.06"}])
    assert vs.new_tag(datetime.date(2026, 10, 6), rows) == "voice-v2026.10.06-2"
    assert vs.new_tag(DAY, rows) == "voice-v2026.10.07"
    calls = []
    tag, prev = vs.last_voice(rows, _gh(calls, [], ["WoWForeverJapanese_VoiceA-2026.10.06-01234567.zip"]))
    assert tag == "voice-v2026.10.06" and prev == {"WoWForeverJapanese_VoiceA": "2026.10.06-01234567"}
    assert calls == [["release", "view", "voice-v2026.10.06", "--json", "assets"]]


def test_a_dry_run_builds_checks_and_uploads_nothing(tmp_path, engine, monkeypatch, capsys):  # noqa: F811
    data, store, cfg = _project(tmp_path, engine)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(vs.voice_store, "read_levels", lambda *_: {456: 5})
    monkeypatch.delenv("CF_API_KEY", raising=False)
    calls = []
    gh = _gh(calls, [{"tagName": "v0.1.0-alpha.8", "createdAt": "2026-10-05T00:00:00Z"}], [])
    assert vs.run_release(_args(tmp_path, store, cfg, _table_file(tmp_path)), run=gh) == 0
    out = capsys.readouterr().out
    assert "upload WoWForeverJapanese_VoiceA-" in out and "to CurseForge project 2 (a)" in out
    assert "WoWForeverJapanese_VoiceB changed but has no CurseForge project yet" in out
    assert "dry run; nothing uploaded" in out
    assert not any(c[:2] == ["release", "create"] for c in calls)
    dist = sorted(p.name for p in (tmp_path / "voice-release").iterdir())
    assert len(dist) == 5 and any(n.startswith("WoWForeverJapanese_Voice-all-") for n in dist)
    with zipfile.ZipFile(next((tmp_path / "voice-release").glob("*-all-*.zip"))) as z:
        tops = {n.split("/", 1)[0] for n in z.namelist()}
    assert tops == {"WoWForeverJapanese_Voice", "WoWForeverJapanese_VoiceA", "WoWForeverJapanese_VoiceB",
                    "WoWForeverJapanese_VoiceOther"}


def test_a_real_release_without_a_token_stops_before_uploading(tmp_path, engine, monkeypatch, capsys):  # noqa: F811
    data, store, cfg = _project(tmp_path, engine)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(vs.voice_store, "read_levels", lambda *_: {456: 5})
    monkeypatch.delenv("CF_API_KEY", raising=False)
    calls = []
    gh = _gh(calls, [{"tagName": "v0.1.0-alpha.8", "createdAt": "2026-10-05T00:00:00Z"}], [])
    args = _args(tmp_path, store, cfg, _table_file(tmp_path), dry_run=False)
    assert vs.run_release(args, run=gh) == 1
    assert "no upload token (CF_API_KEY)" in capsys.readouterr().err
    assert not any(c[:2] == ["release", "create"] for c in calls)


# ---- CurseForge ------------------------------------------------------------------------------------------


def test_the_game_version_is_chosen_as_the_packager_chooses(capsys):
    assert curseforge.interface_version("16001") == "1.60.1"
    assert curseforge.interface_version("110207") == "11.2.7"
    versions = [
        {"id": 1, "gameVersionTypeID": 88568, "name": "1.60.0"},
        {"id": 2, "gameVersionTypeID": 88568, "name": "1.60.1"},
        {"id": 3, "gameVersionTypeID": 67408, "name": "1.60.1"},  # another flavour's
    ]
    assert curseforge.game_version_id(versions, "16001") == 2
    assert curseforge.game_version_id(versions[:1], "16001") == 1  # the newest lower one
    assert "using 1.60.0" in capsys.readouterr().out
    with pytest.raises(curseforge.CurseForgeError, match="no game version"):
        curseforge.game_version_id(versions[2:], "16001")


def test_the_upload_metadata_and_body(tmp_path):
    entry = curseforge.metadata("2026.10.07-01234567", 2, "alpha", "notes", ["a", "o"])
    assert entry == {
        "displayName": "2026.10.07-01234567", "gameVersions": [2], "releaseType": "alpha", "changelog": "notes",
        "changelogType": "text",
        "relations": {"projects": [{"slug": "a", "type": "requiredDependency"},
                                   {"slug": "o", "type": "requiredDependency"}]},
    }
    assert "relations" not in curseforge.metadata("v", 2, "beta", "n")  # a pack names nothing
    with pytest.raises(ValueError):
        curseforge.metadata("v", 2, "stable", "n")
    z = tmp_path / "a.zip"
    z.write_bytes(b"PK" * 1000)
    parts, length = curseforge._multipart(entry, z, "B")
    body = b"".join(curseforge._body(parts, z))
    assert len(body) == length
    assert b'name="metadata"' in body and b'filename="a.zip"' in body and body.endswith(b"\r\n--B--\r\n")


# ---- the public text -------------------------------------------------------------------------------------


def test_every_voice_model_is_credited():
    import tomllib

    roster = tomllib.loads((ROOT / "pipeline" / "voice.toml").read_text(encoding="utf-8"))["roster"]
    for doc in ("ATTRIBUTION.md", "docs/curseforge-voice.md"):
        text = (ROOT / doc).read_text(encoding="utf-8")
        missing = sorted({v["model"] for v in roster.values() if v["model"] not in text})
        assert not missing, f"{doc} lacks {missing}"


def test_the_about_page_links_the_voice_entry_of_the_table():
    slug = vp.load(TABLE).entry.slug
    options = (ROOT / "addon" / "WoWForeverJapanese" / "UI" / "Options.lua").read_text(encoding="utf-8")
    assert f'Options.VOICE_URL = "https://www.curseforge.com/wow/addons/{slug}"' in options


def test_curseforge_only_makes_no_github_release(tmp_path, engine, monkeypatch, capsys):  # noqa: F811
    data, store, cfg = _project(tmp_path, engine)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(vs.voice_store, "read_levels", lambda *_: {456: 5})
    monkeypatch.setenv("CF_API_KEY", "t")
    monkeypatch.setattr(vs.curseforge, "game_versions", lambda token: [
        {"id": 2, "gameVersionTypeID": 88568, "name": "1.60.1"}])
    uploads = []
    monkeypatch.setattr(vs.curseforge, "upload", lambda pid, path, meta, token: uploads.append((pid, meta)) or 9)
    calls = []
    gh = _gh(calls, [{"tagName": "v0.1.0-alpha.8", "createdAt": "2026-10-05T00:00:00Z"}], [])
    args = _args(tmp_path, store, cfg, _table_file(tmp_path), dry_run=False, curseforge_only=True)
    assert vs.run_release(args, run=gh) == 0
    assert [pid for pid, _ in uploads] == [2, 3, 1]  # packs first, the entry last
    assert uploads[-1][1]["relations"]["projects"][0] == {"slug": "main", "type": "requiredDependency"}
    assert uploads[0][1]["releaseType"] == "alpha" and "relations" not in uploads[0][1]
    assert not any(c[:2] == ["release", "create"] for c in calls)
    assert "CurseForge only" in capsys.readouterr().out


def test_the_entry_alone_requiring_only_the_main_addon(tmp_path, engine, monkeypatch, capsys):  # noqa: F811
    data, store, cfg = _project(tmp_path, engine)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(vs.voice_store, "read_levels", lambda *_: {456: 5})
    monkeypatch.setenv("CF_API_KEY", "t")
    monkeypatch.setattr(vs.curseforge, "game_versions", lambda token: [
        {"id": 2, "gameVersionTypeID": 88568, "name": "1.60.1"}])
    uploads = []
    monkeypatch.setattr(vs.curseforge, "upload", lambda pid, path, meta, token: uploads.append((pid, meta)) or 9)
    gh = _gh([], [{"tagName": "v0.1.0-alpha.8", "createdAt": "2026-10-05T00:00:00Z"}], [])
    args = _args(tmp_path, store, cfg, _table_file(tmp_path), dry_run=False, curseforge_only=True,
                 only="WoWForeverJapanese_Voice", entry_without_packs=True)
    assert vs.run_release(args, run=gh) == 0
    assert [pid for pid, _ in uploads] == [1]  # the entry's project only
    assert uploads[0][1]["relations"]["projects"] == [{"slug": "main", "type": "requiredDependency"}]
    bad = _args(tmp_path, store, cfg, _table_file(tmp_path), only="WoWForeverJapanese_VoiceZ", curseforge_only=True)
    with pytest.raises(ValueError, match="no such folder"):
        vs.run_release(bad, run=gh)
    # without --curseforge-only the GitHub release would record packs that were never uploaded
    partial = _args(tmp_path, store, cfg, _table_file(tmp_path), only="WoWForeverJapanese_Voice")
    with pytest.raises(ValueError, match="use it with --curseforge-only"):
        vs.run_release(partial, run=gh)


# ---- the audio store and the pin --------------------------------------------------------------------------


def test_the_level_table_round_trips_and_refuses_junk(tmp_path):
    from wfj.cmd import voice_store

    p = tmp_path / "levels.txt"
    p.write_text(voice_store.levels_text({20: 12, 3: 5}), encoding="utf-8")
    assert p.read_text().splitlines()[-2:] == ["3 5", "20 12"]  # sorted by quest id
    assert voice_store.read_levels(p) == {3: 5, 20: 12}
    p.write_text("3 five\n", encoding="utf-8")
    with pytest.raises(ValueError, match="quest id"):
        voice_store.read_levels(p)


def _git(cwd, *args):
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, check=True).stdout


def test_store_sync_commits_pushes_and_pins(tmp_path):
    from wfj.cmd import voice_store

    remote, store, pin = tmp_path / "remote.git", tmp_path / "store", tmp_path / "pin.txt"
    _git(tmp_path, "init", "-q", "--bare", str(remote))
    _git(tmp_path, "init", "-q", "-b", "main", str(store))
    _git(store, "config", "user.name", "Zyaga")
    _git(store, "config", "user.email", "zyaga@users.noreply.github.com")
    _git(store, "remote", "add", "origin", str(remote))
    (store / "1-description.mp3").write_bytes(b"a")
    sha = voice_store.sync(store, pin, "Voice audio for the text at abc1234")
    assert voice_store.read_pin(pin) == sha == _git(remote, "rev-parse", "main").strip()  # pushed
    assert _git(store, "log", "-1", "--format=%s").strip() == "Voice audio for the text at abc1234"
    assert voice_store.sync(store, pin, "again") == sha  # nothing new: no empty commit
    vs.check_pin(store, pin)  # in step
    (store / "1-description.mp3").write_bytes(b"b")  # a remade file, not synced yet
    with pytest.raises(ValueError, match="uncommitted"):
        vs.check_pin(store, pin)
    newer = voice_store.sync(store, pin, "remade")
    assert newer != sha
    pin.write_text(voice_store.PIN_HEAD + sha + "\n")  # the text still pins the older audio
    with pytest.raises(ValueError, match="the text pins"):
        vs.check_pin(store, pin)
    with pytest.raises(ValueError, match="not a checkout"):
        voice_store.sync(tmp_path / "plain", pin, "x")
    # the Release workflow checks the pinned commit out detached, as a fresh clone: that passes the check
    ci = tmp_path / "ci"
    _git(tmp_path, "clone", "-q", str(remote), str(ci))
    _git(ci, "checkout", "-q", "--detach", sha)
    vs.check_pin(ci, pin)


def test_the_pin_is_one_full_commit(tmp_path):
    from wfj.cmd import voice_store

    p = tmp_path / "pin.txt"
    p.write_text("# note\n" + "a" * 40 + "\n")
    assert voice_store.read_pin(p) == "a" * 40
    for bad in ("abc\n", "a" * 40 + "\n" + "b" * 40 + "\n", "Z" * 40 + "\n"):
        p.write_text(bad)
        with pytest.raises(ValueError, match="full commit"):
            voice_store.read_pin(p)


def test_the_addon_names_the_voice_entry_as_optional_only():
    """The main addon's page shows the Voice entry; installing the addon never installs the voice."""
    pkgmeta = (ROOT / ".pkgmeta").read_text(encoding="utf-8")
    slug = vp.load(TABLE).entry.slug
    assert f"optional-dependencies:\n  - {slug}\n" in pkgmeta
    assert "required-dependencies" not in pkgmeta
    toc = (ROOT / "addon" / "WoWForeverJapanese" / "WoWForeverJapanese.toc").read_text(encoding="utf-8")
    assert "## Dependencies" not in toc and "## RequiredDeps" not in toc and "## OptionalDeps" not in toc


def test_curseforge_names_the_relation_it_refuses():
    body = ('{"errorCode":1018,"errorMessage":"Invalid slug in project relations: '
            '\\u0027wow-forever-japanese-voice-levels-1-10\\u0027 does not exist, is not accessible, or belongs to'
            ' an unrelated root category."}')  # a real answer from the upload API
    assert curseforge.refused_relation(body) == "wow-forever-japanese-voice-levels-1-10"
    assert curseforge.refused_relation('{"errorCode":1000,"errorMessage":"x"}') is None
    assert curseforge.refused_relation("<html>413</html>") is None


def test_the_entry_goes_up_without_packs_still_in_review(tmp_path, engine, monkeypatch, capsys):  # noqa: F811
    data, store, cfg = _project(tmp_path, engine)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(vs.voice_store, "read_levels", lambda *_: {456: 5})
    monkeypatch.setenv("CF_API_KEY", "t")
    monkeypatch.setattr(vs.curseforge, "game_versions", lambda token: [
        {"id": 2, "gameVersionTypeID": 88568, "name": "1.60.1"}])
    uploads = []

    def upload(pid, path, meta, token):
        uploads.append((pid, [r["slug"] for r in meta.get("relations", {}).get("projects", [])]))
        if pid == 1 and "o" in uploads[-1][1]:  # the entry naming pack o, which is still in review
            raise curseforge.CurseForgeError("HTTP 400", refused="o")
        return 9

    monkeypatch.setattr(vs.curseforge, "upload", upload)
    calls = []
    gh = _gh(calls, [{"tagName": "v0.1.0-alpha.8", "createdAt": "2026-10-05T00:00:00Z"}], [])
    args = _args(tmp_path, store, cfg, _table_file(tmp_path), dry_run=False)
    assert vs.run_release(args, run=gh) == 0
    assert uploads == [(2, []), (3, []), (1, ["main", "a", "o"]), (1, ["main", "a"])]
    assert "does not accept o as a dependency yet" in capsys.readouterr().out
    # the GitHub release names the entry by what it really requires, so the next release tries the full list
    recorded = [Path(x).name for c in calls if c[:2] == ["release", "upload"] for x in c[3:]]
    entry = next(n for n in recorded if n.startswith("WoWForeverJapanese_Voice-2"))
    full = vp.version(datetime.date.today(), vp.entry_hash(vs.required(vp.parse(_raw())), "16001"))
    assert entry != vp.asset_name("WoWForeverJapanese_Voice", full)


def test_a_refused_main_addon_or_another_error_still_stops_the_release(tmp_path):
    def refuse(slug):
        def upload(pid, path, meta, token):
            raise curseforge.CurseForgeError("HTTP 400", refused=slug)
        return upload

    pr = vp.parse(_raw()).entry
    for slug in ("main", None):
        import wfj.io.curseforge as cf
        old = cf.upload
        cf.upload = refuse(slug)
        try:
            with pytest.raises(curseforge.CurseForgeError):
                vs.upload_entry(pr, tmp_path / "e.zip", lambda req: {"r": req}, ["main", "a"], "t", "main")
        finally:
            cf.upload = old


# ---- a release that fails partway, and the voice job's skip ----------------------------------------------


def _release_env(tmp_path, engine, monkeypatch):  # noqa: F811
    data, store, cfg = _project(tmp_path, engine)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(vs.voice_store, "read_levels", lambda *_: {456: 5})
    monkeypatch.setattr(vs, "inputs_fingerprint", lambda repo: "f" * 64)
    monkeypatch.setenv("CF_API_KEY", "t")
    monkeypatch.setattr(vs.curseforge, "game_versions", lambda token: [
        {"id": 2, "gameVersionTypeID": 88568, "name": "1.60.1"}])
    return store, cfg


class FakeGitHub:
    """`gh` with releases (drafts too) and their assets, enough for a voice release."""

    def __init__(self):
        self.rel = {"v0.1.0-alpha.8": {"draft": False, "assets": [], "at": "2026-10-05T00:00:00Z"}}
        self.calls = []

    def __call__(self, args):
        self.calls.append(list(args))
        verb, rest = args[1], list(args[2:])
        if verb == "list":
            return json.dumps([{"tagName": t, "createdAt": r["at"], "isDraft": r["draft"]}
                               for t, r in self.rel.items()])
        if verb == "view":
            return json.dumps({"assets": [{"name": n} for n in self.rel[rest[0]]["assets"]]})
        if verb == "create":
            self.rel[rest[0]] = {"draft": "--draft" in rest, "assets": [], "at": "2026-10-08T00:00:00Z"}
        elif verb == "upload":
            names = [Path(x).name for x in rest[1:] if not x.startswith("--")]
            a = self.rel[rest[0]]["assets"]
            a[:] = [n for n in a if n not in names] + names
        elif verb == "delete-asset":
            self.rel[rest[0]]["assets"].remove(rest[1])
        elif verb == "edit" and "--draft=false" in rest:
            self.rel[rest[0]]["draft"] = False
        return ""


def test_a_release_that_fails_partway_resumes_and_uploads_nothing_twice(tmp_path, engine, monkeypatch):  # noqa: F811
    store, cfg = _release_env(tmp_path, engine, monkeypatch)
    gh, uploads, fail = FakeGitHub(), [], {"at": 3}

    def upload(pid, path, meta, token):
        if pid == fail["at"]:
            raise curseforge.CurseForgeError("HTTP 503")
        uploads.append(pid)
        return 9

    monkeypatch.setattr(vs.curseforge, "upload", upload)
    args = _args(tmp_path, store, cfg, _table_file(tmp_path), dry_run=False)
    with pytest.raises(curseforge.CurseForgeError):
        vs.run_release(args, run=gh)  # pack A went up, Other failed: a draft records A
    draft = next(t for t, r in gh.rel.items() if r["draft"])
    assert uploads == [2] and any(n.startswith("WoWForeverJapanese_VoiceA-") for n in gh.rel[draft]["assets"])
    fail["at"] = None
    assert vs.run_release(args, run=gh) == 0  # the re-run resumes the draft and skips A
    assert uploads == [2, 3, 1]
    assert not gh.rel[draft]["draft"] and sum(1 for t in gh.rel if t.startswith("voice-v")) == 1
    names = gh.rel[draft]["assets"]
    assert len([n for n in names if n.startswith("WoWForeverJapanese_VoiceA-")]) == 1
    assert vp.released_inputs(names) == "f" * 16 and any("-all-" in n for n in names)
    uploads.clear()
    assert vs.run_release(args, run=gh) == 0  # nothing changed since: nothing goes up
    assert uploads == []


def test_a_partial_entry_is_tried_in_full_on_the_next_release(tmp_path, engine, monkeypatch):  # noqa: F811
    store, cfg = _release_env(tmp_path, engine, monkeypatch)
    gh, uploads = FakeGitHub(), []
    monkeypatch.setattr(vs.curseforge, "upload", lambda pid, path, meta, token: uploads.append(
        (pid, [r["slug"] for r in meta.get("relations", {}).get("projects", [])])) or 9)
    args = _args(tmp_path, store, cfg, _table_file(tmp_path), dry_run=False, entry_without_packs=True)
    assert vs.run_release(args, run=gh) == 0
    assert uploads[-1] == (1, ["main"])
    uploads.clear()
    assert vs.run_release(_args(tmp_path, store, cfg, _table_file(tmp_path), dry_run=False), run=gh) == 0
    assert uploads == [(1, ["main", "a", "o"])]  # only the entry, now naming every pack


def test_a_pack_released_before_its_project_existed_goes_up_once_it_has_one(tmp_path, engine, monkeypatch):  # noqa: F811
    store, cfg = _release_env(tmp_path, engine, monkeypatch)
    gh, uploads = FakeGitHub(), []
    monkeypatch.setattr(vs.curseforge, "upload", lambda pid, path, meta, token: uploads.append(pid) or 9)
    assert vs.run_release(_args(tmp_path, store, cfg, _table_file(tmp_path), dry_run=False), run=gh) == 0
    assert 0 not in uploads  # B has no project yet
    raw = _raw()
    raw["pack"][1]["project_id"] = 9
    uploads.clear()
    table = _table_file(tmp_path, pack=raw["pack"])
    assert vs.run_release(_args(tmp_path, store, cfg, table, dry_run=False), run=gh) == 0
    assert 9 in uploads


def test_the_voice_job_runs_only_when_the_voice_inputs_changed(monkeypatch, capsys):
    gh = FakeGitHub()
    monkeypatch.setattr(vs, "inputs_fingerprint", lambda repo: "a" * 64)
    assert vs.run_inputs(gh) == 0 and capsys.readouterr().out == "changed=true\n"  # no voice release yet
    gh.rel["voice-v2026.10.08"] = {"draft": False, "at": "2026-10-08T00:00:00Z",
                                   "assets": [vp.inputs_asset("a" * 64)]}
    assert vs.run_inputs(gh) == 0 and capsys.readouterr().out == "changed=false\n"
    monkeypatch.setattr(vs, "inputs_fingerprint", lambda repo: "b" * 64)
    assert vs.run_inputs(gh) == 0 and capsys.readouterr().out == "changed=true\n"


def test_the_inputs_fingerprint_follows_the_committed_tree(tmp_path):
    repo = tmp_path / "r"
    _git(tmp_path, "init", "-q", "-b", "main", str(repo))
    _git(repo, "config", "user.name", "Zyaga")
    _git(repo, "config", "user.email", "zyaga@users.noreply.github.com")
    (repo / "pipeline").mkdir()
    (repo / "pipeline" / "voice-packs.toml").write_text("a")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "a")
    first = vs.inputs_fingerprint(repo)
    (repo / "README.md").write_text("not an input")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "b")
    assert vs.inputs_fingerprint(repo) == first
    (repo / "pipeline" / "voice-packs.toml").write_text("b")
    _git(repo, "commit", "-q", "-am", "c")
    assert vs.inputs_fingerprint(repo) != first


def test_store_sync_refuses_a_store_off_its_branch(tmp_path):
    from wfj.cmd import voice_store

    remote, store, pin = tmp_path / "remote.git", tmp_path / "store", tmp_path / "pin.txt"
    _git(tmp_path, "init", "-q", "--bare", str(remote))
    _git(tmp_path, "init", "-q", "-b", "main", str(store))
    _git(store, "config", "user.name", "Zyaga")
    _git(store, "config", "user.email", "zyaga@users.noreply.github.com")
    _git(store, "remote", "add", "origin", str(remote))
    (store / "a.mp3").write_bytes(b"a")
    sha = voice_store.sync(store, pin, "a")
    _git(store, "checkout", "-q", sha)  # detached, as check_pin's pinned checkout leaves it
    (store / "b.mp3").write_bytes(b"b")
    with pytest.raises(ValueError, match="not on a branch"):
        voice_store.sync(store, pin, "b")
    assert _git(store, "rev-parse", "HEAD").strip() == sha  # nothing committed


def test_a_variant_missing_from_the_audio_record_is_named(tmp_path, engine, monkeypatch):  # noqa: F811
    store, cfg = _release_env(tmp_path, engine, monkeypatch)
    real, reads = vs.voice_make.audio_record, []

    def audio_record(root):  # the record changes between the pack tables and the split (a run writing it)
        rec = real(root)
        reads.append(1)
        return rec if len(reads) == 1 else {k: v for k, v in rec.items() if k != "456-completion"}

    monkeypatch.setattr(vs.voice_make, "audio_record", audio_record)
    with pytest.raises(ValueError, match="not in the audio record"):
        vs.run_pack(_args(tmp_path, store, cfg, _table_file(tmp_path)))
