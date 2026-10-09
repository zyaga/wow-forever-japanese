"""`wfj voice audition`: the clips every voice reads, the kinds of speaker, the review page and the picks
written back into voice.toml, against a fake engine and encoder."""

from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace

import pytest
import voice_fixture as vf

from wfj.cmd import voice_audition as aud
from wfj.cmd import voice_make
from wfj.core import voice
from wfj.io.jsonl_store import Store

G = voice.gossip_key
SPEAKERS = [
    {"name": "morioki", "speaker_uuid": "u1",
     "styles": [{"id": 11, "name": "ノーマル"}, {"id": 12, "name": "Calm"}, {"id": 13, "name": "Angry"}]},
    {"name": "コハク (雑談)", "speaker_uuid": "u2", "styles": [{"id": 21, "name": "ノーマル"}]},
    {"name": "阿井田 茂", "speaker_uuid": "u3", "styles": [{"id": 31, "name": "ノーマル"}, {"id": 32, "name": "Heavy"}]},
]
CAST = [
    {"name": "ghost", "when": {"archetype": "ghost"}, "voices": []},
    {"name": "dragon", "when": {"archetype": "dragon"}, "voices": []},
    {"name": "female", "when": {"gender": "female"}, "voices": []},
    {"name": "male", "when": {"gender": "male"}, "voices": []},
]
CFG = {"engine": "http://fake", "speed_scale": 0.9, "cast": CAST}
BROKEN = "0123456789abcdef"  # a gossip line whose markup the engine must not read


class FakeEngine:
    made: list[tuple] = []

    def __init__(self, url):
        self.url = url

    def speakers(self):
        return SPEAKERS

    def synthesize(self, text, style, speed, pitch=0.0, intonation=1.0):
        FakeEngine.made.append((text, style, speed, pitch, intonation))
        return b"RIFF" + text.encode()


@pytest.fixture
def world(tmp_path, monkeypatch):
    data = vf.make_data(tmp_path)
    gossip = Store(data).load("gossip")
    gossip.append({"id": BROKEN, "field": "text", "ja": "{foo}です", "status": "trusted"})
    Store(data).save("gossip", gossip)
    vf.write_rows(data / "voice" / "speakers.jsonl", [
        {"key": "456-description", "speaker": 2079, "others": [1992], "provenance": vf.SRC},
        {"key": "456-completion", "speaker": 2079, "provenance": vf.SRC},
        {"key": "457-description", "speaker": 2079, "provenance": vf.SRC},
        {"key": "457-completion", "speaker": 1992, "provenance": vf.SRC},
        {"key": "459-description", "speaker": "narrator", "provenance": vf.SRC},
        {"key": "458-description", "speaker": "narrator", "provenance": vf.SRC},  # ships no Japanese
        {"key": G(voice.gossip_id(vf.GREETING)), "speaker": 9000, "provenance": vf.SRC},
        {"key": G(BROKEN), "speaker": 7777, "provenance": vf.SRC},
        {"key": f"b-{vf.SIGNED}", "speaker": "narrator", "provenance": vf.SRC},
        {"key": f"b-{vf.UNSIGNED}", "speaker": "narrator", "provenance": vf.SRC},
    ])
    machine = {"source": "machine", "model": "m", "batch": "b", "reason": "a calm grown voice",
               "imported": "2026-10-06"}
    vf.write_rows(data / "voice" / "profiles.jsonl", [
        {"creature": 1992, "gender": "female", "provenance": {}},
        {"creature": 2079, "gender": "male", "age": "adult", "provenance": {"age": machine}},
        {"creature": 7777, "archetype": "ghost", "provenance": {}},
        {"creature": 9000, "archetype": "dragon", "provenance": {}},
        {"creature": 8888, "provenance": {}},  # matches no row and says nothing
    ])
    FakeEngine.made = []
    monkeypatch.setattr(aud, "Engine", FakeEngine)
    monkeypatch.setattr(voice_make, "to_mp3", lambda wav, out: out.write_bytes(b"MP3" + wav))
    monkeypatch.setattr(aud, "data_root", lambda: data)
    store = tmp_path / "store"
    return SimpleNamespace(data=data, db=vf.make_speaker_db(tmp_path / "mangos.sqlite"), store=store,
                           folder=store / "audition", tmp=tmp_path)


# ---- pure helpers -----------------------------------------------------------------------------------------


def test_sample_text_is_the_first_two_sentences_as_read():
    assert aud.sample_text("一つ目、{name}。二つ目。三つ目。", "k") == "一つ目、冒険者。二つ目。"
    assert aud.sample_text("改行は\n読まない。", "k") == "改行は読まない。"
    assert aud.sample_text("あ" * 200, "k") == "あ" * 120  # no full stop: the first 120 characters


def test_entries_list_first_and_calmer_styles_then_the_tries():
    items = aud.entries(SPEAKERS)
    assert [e["id"] for e in items] == [
        "v11", "v12", "v21", "v31", "v32", "v11older", "v11elderly", "v32elderly", "v21child"]
    by = {e["id"]: e for e in items}
    assert by["v11"] == {"id": "v11", "name": "morioki", "uuid": "u1", "style": 11, "style_name": "ノーマル",
                         "pitch": 0.0, "speed": None, "intonation": 1.0, "try": ""}
    assert (by["v32elderly"]["style_name"], by["v32elderly"]["pitch"], by["v32elderly"]["speed"]) == (
        "Heavy", -0.05, 0.85)
    assert by["v21child"]["name"] == "コハク (雑談)" and by["v21child"]["try"] == "child"


def test_base_name_drops_the_bracketed_tail_and_lookup_needs_one_match():
    assert aud.base_name("猩々博士 (雑談ボイス)") == aud.base_name("猩々博士（雑談ボイス）") == "猩々博士"
    two = {"a (x)": "CC0", "a (y)": "ACML 1.0"}
    assert aud.lookup(two, "a (z)") is None  # two licences for one base name: no answer
    assert aud.lookup({"a (x)": "CC0", "a (y)": "CC0"}, "a") == "CC0"


def test_kind_gender_casts_some_kinds_by_sound():
    assert [aud.kind_gender(k) for k in ("book narrator", "dragon", "orc, girl", "female", "elder")] == [
        "any", "any", "female", "female", "male"]


CATALOGUE = """# Voices

## Usable

| Name | UUID | Author | Gender, age | Styles | Size MB | Licence | Fits |
|---|---|---|---|---|---|---|---|
| morioki | u1 | a | male, adult | ノーマル | 250 | ACML 1.0 | calm |
| コハク（雑談） | u2 | b | female, child | ノーマル | 250 | CC0 | bright |
| 阿井田 茂 | u3 | c | unknown | ノーマル | 250 | ACML 1.0 | deep |
| short | row |

## Out

| Gone | u9 | d | male, young | x | 1 | ACML-NC 1.0 | non-commercial |
| Late | u8 | e | male, young | x | 1 | CC0 | listed out |
"""


def test_the_catalogue_gives_genders_and_licences_of_usable_voices_only(tmp_path):
    cat = tmp_path / "catalogue.md"
    cat.write_text(CATALOGUE, encoding="utf-8")
    assert aud.voice_genders(cat) == {"morioki": "male", "コハク（雑談）": "female", "阿井田 茂": "other"}
    assert aud.licences(cat) == {"morioki": "ACML 1.0", "コハク（雑談）": "CC0", "阿井田 茂": "ACML 1.0"}


def test_page_lists_each_voice_with_its_clips_and_the_kinds(tmp_path, monkeypatch):
    cat = tmp_path / "catalogue.md"
    cat.write_text(CATALOGUE, encoding="utf-8")
    monkeypatch.setattr(aud, "CATALOGUE", cat)
    items = aud.entries(SPEAKERS)
    html = aud.page(items, [{"name": "orc, female", "creatures": 3, "lines": 9}], ["一つ目。", "<b>"])
    assert "@@" not in html
    assert '<section class="card" data-id="v21child" data-gender="female">' in html
    assert '<section class="card" data-id="v11" data-gender="male">' in html
    assert "<h3>コハク (雑談) · ノーマル · try: child</h3>" in html
    assert 'src="clips/v11-1.mp3"' in html and 'src="clips/v11-2.mp3"' in html
    assert "<tr><td>orc, female</td><td>3</td><td>9</td></tr>" in html
    assert "<li>&lt;b&gt;</li>" in html  # sample text is escaped
    assert 'const KINDS=[["orc, female", "female"]];' in html


# ---- reading the data ------------------------------------------------------------------------------------


def test_kinds_count_creatures_and_lines_per_cast_row(world):
    assert aud.kinds(world.data, CFG) == [
        {"name": "ghost", "creatures": 1, "lines": 1},
        {"name": "dragon", "creatures": 1, "lines": 1},
        {"name": "female", "creatures": 1, "lines": 2},
        {"name": "male", "creatures": 1, "lines": 3},
        {"name": "narrator", "creatures": 0, "lines": 2},
        {"name": "book narrator", "creatures": 0, "lines": 2},
    ]


def test_kind_samples_pick_a_real_line_of_the_busiest_speaker(world):
    got = aud.kind_samples(world.data, CFG, world.db)
    assert sorted(got) == ["book narrator", "dragon", "female", "male", "narrator"]  # the ghost's line is unreadable
    assert got["male"] == {
        "key": "457-description", "text": "狼を7頭倒せ。", "en": "Kill 7 wolves.", "creature": 2079,
        "name": "Conservator Ilthalaine", "title": "", "profile": {"gender": "male", "age": "adult"},
        "reason": "a calm grown voice",
    }
    # a line's main speaker only: 1992 also says 456-description, as one of its others
    assert (got["female"]["creature"], got["female"]["key"]) == (1992, "457-completion")
    assert got["narrator"] == {"key": "459-description", "text": "祠に祈れ。", "en": "", "creature": None,
                               "name": "", "title": "", "profile": {}, "reason": ""}
    assert got["book narrator"]["key"].startswith("b-")


# ---- build, review, apply --------------------------------------------------------------------------------


def test_build_makes_two_clips_per_voice_once_and_writes_the_page(world, capsys):
    clips = world.folder / "clips"
    clips.mkdir(parents=True)
    (clips / "v11-1.mp3").write_bytes(b"kept")
    assert aud.build(world.data, CFG, world.store) == 0
    assert len(FakeEngine.made) == 9 * 2 - 1  # every voice reads both lines, a clip on disk is not remade
    assert (clips / "v11-1.mp3").read_bytes() == b"kept"
    assert (clips / "v32elderly-2.mp3").read_bytes() == "MP3RIFFありがとう。".encode()
    assert {m[0] for m in FakeEngine.made} == {"御機嫌よう、冒険者。森を守ってくれ。", "ありがとう。"}
    assert ("ありがとう。", 11, 0.9, 0.0, 1.0) in FakeEngine.made  # no speed of its own: the set pace
    assert ("ありがとう。", 11, 0.8, -0.1, 0.9) in FakeEngine.made  # the elderly try
    voices = json.loads((world.folder / "voices.json").read_text(encoding="utf-8"))
    assert [v["id"] for v in voices] == [e["id"] for e in aud.entries(SPEAKERS)]
    page = (world.folder / "index.html").read_text(encoding="utf-8")
    assert "<tr><td>male</td><td>1</td><td>3</td></tr>" in page
    assert capsys.readouterr().out.splitlines()[-1] == f"voice audition: 9 voices → {world.folder / 'index.html'}"


def _voices_json(world):
    world.folder.mkdir(parents=True, exist_ok=True)
    (world.folder / "voices.json").write_text(json.dumps(aud.entries(SPEAKERS), ensure_ascii=False))


def test_review_reads_each_kinds_line_in_each_candidate_voice(world, capsys):
    _voices_json(world)
    (world.folder / "candidates.json").write_text(json.dumps({
        "female": ["v21", "v11older"], "male": ["v11"], "ghost": ["v11"],
        "pinned": ["v31"], "_lines": {"pinned": "456-completion"},
    }))
    (world.folder / "review").mkdir()
    (world.folder / "review" / "female-v21.mp3").write_bytes(b"kept")
    assert aud.review(world.data, CFG, world.store, world.db) == 0
    assert [m[:2] for m in FakeEngine.made] == [("狼を7頭倒せ。", 11), ("ありがとう。", 11),
                                               ("よくやった。", 31)]
    assert FakeEngine.made[1][2:] == (0.85, -0.05, 1.0)  # the older try keeps its own pace and pitch
    html = (world.folder / "review.html").read_text(encoding="utf-8")
    assert html.index('data-kind="male"') < html.index('data-kind="female"') < html.index('data-kind="pinned"')
    assert 'data-kind="ghost"' not in html  # no readable line of that kind
    assert "<small>1 creatures, 3 lines</small>" in html
    assert "Speaking: <b>Conservator Ilthalaine</b> (male, adult)" in html
    assert f'href="{aud.WOWHEAD}2079"' in html
    assert "Speaking: <b>the narrator</b> ()" in html  # a pinned line of a kind with no sample of its own
    assert 'src="review/female-v11older.mp3"' in html and "your pick" not in html
    assert capsys.readouterr().out.splitlines()[-1] == f"voice audition: {world.folder / 'review.html'}"


def test_a_later_review_round_marks_the_earlier_picks(world):
    _voices_json(world)
    (world.folder / "candidates2.json").write_text(json.dumps({"male": ["v11", "v12"]}))
    (world.folder / "picks.json").write_text(json.dumps({"male": ["v12"]}))
    assert aud.review(world.data, CFG, world.store, world.db, "2") == 0
    html = (world.folder / "review2.html").read_text(encoding="utf-8")
    assert "morioki · Calm · your pick" in html and "morioki · ノーマル · suggested" in html


TOML = """engine = "http://fake"
speed_scale = 0.9
narrator = "v11"
book_narrator = "v11"

[roster.v11]
model = "morioki"
style = 11 # ノーマル
licence = "ACML 1.0"

# Cast rows, first match wins.

[[cast]]
name = "male"
when = { gender = "male" }
voices = []

[[cast]]
name = "female"
when = { gender = "female" }
voices = []
"""


def _picks(world, picks, items=None):
    world.folder.mkdir(parents=True, exist_ok=True)
    (world.folder / "picks.json").write_text(json.dumps(picks))
    (world.folder / "voices.json").write_text(json.dumps(items or aud.entries(SPEAKERS), ensure_ascii=False))
    cfg = world.tmp / "voice.toml"
    cfg.write_text(TOML, encoding="utf-8")
    return cfg


def test_apply_adds_roster_voices_sets_rows_and_both_narrators(world, capsys):
    cfg = _picks(world, {"male": ["v11", "v11elderly"], "female": ["v21child"], "book narrator": ["v11elderly"],
                         "elves": ["v11"]})
    assert aud.run(["apply", "--config", str(cfg), "--store", str(world.store)]) == 0
    got = voice_make.load_config(cfg)
    assert [r["voices"] for r in got["cast"]] == [["v11", "v11elderly"], ["v21child"]]
    assert (got["narrator"], got["book_narrator"]) == ("v11", "v11elderly")
    assert got["roster"]["v11elderly"] == {"model": "morioki", "style": 11, "licence": "ACML 1.0",
                                          "fits": "picked at the audition (elderly)", "pitch": -0.1,
                                          "speed": 0.8, "intonation": 0.9}
    assert got["roster"]["v21child"]["licence"] == "ACML 1.0"
    text = cfg.read_text(encoding="utf-8")
    assert text.count("[roster.v11]") == 1  # a voice already in the roster is not added again
    assert text.index("[roster.v21child]") < text.index("# Cast rows, first match wins.")
    io = capsys.readouterr()
    assert "voice audition: no cast row named 'elves'" in io.err
    assert io.out == "voice audition: 4 kinds, 3 voices → voice.toml\n"


def test_apply_refuses_a_voice_outside_the_catalogue(world, capsys):
    stranger = {**aud.entries(SPEAKERS)[0], "id": "v99", "name": "Nobody We Know"}
    cfg = _picks(world, {"male": ["v99"]}, [stranger])
    assert aud.run(["apply", "--config", str(cfg), "--store", str(world.store)]) == 1
    assert capsys.readouterr().err == "voice audition: Nobody We Know is not in the catalogue's usable voices\n"
    assert cfg.read_text(encoding="utf-8") == TOML  # nothing written


def test_run_builds_and_reviews_from_the_config(world, capsys):
    cfg = _picks(world, {})
    store = ["--config", str(cfg), "--store", str(world.store)]
    assert aud.run(["build", *store]) == 0
    assert (world.folder / "index.html").is_file()
    (world.folder / "candidates3.json").write_text(json.dumps({"female": ["v21"]}))
    assert aud.run(["review", "--vmangos", str(world.db), "--round", "3", *store]) == 0
    assert (world.folder / "review3.html").is_file()


def test_run_reports_a_missing_file_and_fails(world, capsys):
    assert aud.run(["apply", "--config", str(world.tmp / "absent.toml"), "--store", str(world.store)]) == 1
    assert capsys.readouterr().err.startswith("voice audition: ")


def test_the_store_defaults_to_voice_root(monkeypatch, tmp_path):
    monkeypatch.setenv("VOICE_ROOT", str(tmp_path))
    assert voice_make.store_dir(None) == Path(tmp_path)
    assert voice_make.store_dir("x") == Path("x")
