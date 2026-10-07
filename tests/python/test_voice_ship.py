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
                           only=None, entry_without_packs=False)
    vars(a).update(over)
    return a


def test_pack_writes_the_entry_and_every_pack(tmp_path, engine, monkeypatch):  # noqa: F811
    data, store, cfg = _project(tmp_path, engine)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(vs, "quest_levels", lambda *_: {456: 5})
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
    # quest 456 is level 5, and the narrator's gossip goes to the first band
    a = out / "WoWForeverJapanese_VoiceA"
    assert sorted(p.name for p in (a / "Sound").iterdir()) == [
        "456-completion.mp3", "456-description.mp3", "g-0123456789abcdef.mp3"]
    reg = (a / "Register.lua").read_text()
    assert 'folder = "WoWForeverJapanese_VoiceA"' in reg
    atoc = (a / "WoWForeverJapanese_VoiceA.toc").read_text()
    assert "## Title: A\n" in atoc and "## X-Curse-Project-ID: 2\n" in atoc
    assert "## Version: 2026." in atoc or "## Version: 20" in atoc
    assert "X-Curse-Project-ID" not in (out / "WoWForeverJapanese_VoiceB" / "WoWForeverJapanese_VoiceB.toc").read_text()
    assert not list((out / "WoWForeverJapanese_VoiceB" / "Sound").iterdir())
    luac = shutil.which("luac") or shutil.which("luac5.1")
    if luac:
        subprocess.run([luac, "-p", str(a / "Register.lua")], check=True)


def test_a_pack_over_the_cap_is_refused_and_nothing_is_written(tmp_path, engine, monkeypatch, capsys):  # noqa: F811
    data, store, cfg = _project(tmp_path, engine)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(vs, "quest_levels", lambda *_: {456: 5})
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
    monkeypatch.setattr(vs, "quest_levels", lambda *_: {456: 5})
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
    monkeypatch.setattr(vs, "quest_levels", lambda *_: {456: 5})
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
    monkeypatch.setattr(vs, "quest_levels", lambda *_: {456: 5})
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
    monkeypatch.setattr(vs, "quest_levels", lambda *_: {456: 5})
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
    bad = _args(tmp_path, store, cfg, _table_file(tmp_path), only="WoWForeverJapanese_VoiceZ")
    with pytest.raises(ValueError, match="no such folder"):
        vs.run_release(bad, run=gh)
