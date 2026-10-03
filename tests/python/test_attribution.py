from wfj.dev.gen_attribution import (
    FOREVER_VO,
    LABELS,
    correctors_section,
    data_translators,
    english_sources,
    listed_translators,
    main,
    render,
    translators,
    with_correctors,
)

FIXTURE = "tests/fixtures/predecessor/QuestLogData.excerpt.lua"


def test_fixture_tags_are_all_in_committed_attribution(root):
    tags = translators((root / FIXTURE).read_text(encoding="utf-8"))
    assert len(tags) >= 5
    committed = (root / "ATTRIBUTION.md").read_text(encoding="utf-8")
    for t in tags:
        assert f"- {t}\n" in committed, t


def test_every_translator_in_data_is_credited(root):
    """A hand-written line in data/, shipped or not, names its translator; the credits list every one. Run
    `python -m wfj.dev.gen_attribution` when this fails."""
    in_data = data_translators(root / "data")
    assert len(in_data) >= 50
    listed = set(listed_translators((root / "ATTRIBUTION.md").read_text(encoding="utf-8")))
    assert [t for t in in_data if t not in listed] == []


def test_committed_attribution_shape(root):
    text = (root / "ATTRIBUTION.md").read_text(encoding="utf-8")
    assert text.startswith("# Attribution")
    assert f"## Translators ({len(listed_translators(text))} tags" in text
    for name in ("CraftJapanizer", "WoWJapanizer", "WoWpoPolsku", "Classic Quest Chinese Translator", "Zyaga"):
        assert name in text
    assert "are not people" in text.split("## Lineage")[0]


def test_render_sorted_casefold():
    out = render(translators('["Translator"] = "zed"\n["Translator"] = "Alpha"\n["Translator"] = ""'))
    assert out.index("- Alpha") < out.index("- zed")
    assert "are not people" not in out


def test_render_explains_the_labels():
    out = render(["Alpha", LABELS[0]])
    assert out.index(f"- {LABELS[0]}") < out.index("are not people") < out.index("## Lineage")
    assert listed_translators(out) == ["Alpha", LABELS[0]]


def _store(tmp_path, lines):
    import json

    d = tmp_path / "data" / "quest"
    d.mkdir(parents=True)
    (d / "quest-0000.jsonl").write_text("".join(json.dumps(ln) + "\n" for ln in lines), encoding="utf-8")
    return tmp_path / "data"


def _line(id_, prov, conflicts=()):
    return {"id": id_, "field": "title", "ja": "x", "status": "trusted", "provenance": prov, "conflicts": list(conflicts)}


def test_data_translators_read_every_hand_written_variant(tmp_path):
    human = {"class": "human", "translator": "Kaori", "source": "s", "imported": "d"}
    held_back = {"ja": "y", "provenance": {"class": "human", "translator": "Shin", "source": "s", "imported": "d"}}
    machine = {"class": "machine", "model": "m", "source": "s", "imported": "d"}
    fix = {"class": "correction", "translator": "Player", "source": "s", "imported": "d", "report": 12}
    data = _store(tmp_path, [_line(1, human), _line(2, machine, [held_back]), _line(3, fix)])
    # the machine line has no translator; the player's credit belongs to the Correctors section
    assert data_translators(data) == ["Kaori", "Shin"]


def test_a_regeneration_never_drops_a_credit(root, tmp_path):
    out = tmp_path / "ATTRIBUTION.md"
    out.write_text("# Attribution\n\n## Translators (1 tags, as recorded in the corpus)\n\n- Earlier\n\n## Lineage\n")
    human = {"class": "human", "translator": "Kaori", "source": "s", "imported": "d"}
    data = _store(tmp_path, [_line(1, human)])
    assert main(["--data", str(data), "--out", str(out), "--corpus", str(root / FIXTURE)]) == 0
    listed = listed_translators(out.read_text(encoding="utf-8"))
    assert "Earlier" in listed and "Kaori" in listed
    assert set(translators((root / FIXTURE).read_text(encoding="utf-8"))) <= set(listed)


def test_regeneration_keeps_the_correctors_section(root, tmp_path):
    # `wfj report apply` writes the Correctors section from data/; regenerating the file keeps it, byte for
    # byte, before Lineage
    out = tmp_path / "ATTRIBUTION.md"
    args = ["--corpus", str(root / FIXTURE), "--out", str(out)]
    assert main(args) == 0
    first = out.read_text(encoding="utf-8")
    section = correctors_section({"Kaori": [12, 40]})
    out.write_text(with_correctors(first, {"Kaori": [12, 40]}), encoding="utf-8")
    assert main(args) == 0
    again = out.read_text(encoding="utf-8")
    assert section in again
    assert again.index(section) < again.index("## Lineage")
    assert again.replace(section, "") == first


def test_forever_vo_is_credited_exactly_while_its_lines_remain(root):
    """forever-vo's credit and license (ADR-055) stand in ATTRIBUTION.md exactly while some English line in
    data/english/ comes from it. When this fails, run `python -m wfj.dev.gen_attribution`: it adds or drops the
    credit to match the data."""
    text = (root / "ATTRIBUTION.md").read_text(encoding="utf-8")
    credited = "## forever-vo license" in text and "github.com/quinn-dougherty/forever-vo" in text
    assert credited == (FOREVER_VO in english_sources(root / "data"))


def test_without_forever_vo_lines_the_credit_leaves_no_trace():
    tags = ["A", "b"]
    without, with_ = render(tags), render(tags, {FOREVER_VO, "vmangos"})
    assert "forever-vo" not in without
    assert "\n\n## pfQuest license" in without and "\n\n## This project" in without
    assert "## forever-vo license" in with_ and "Copyright (c) 2026 Quinn Dougherty" in with_
    assert "\n\n## pfQuest license" in with_ and "\n\n## forever-vo license" in with_
    assert "\n\n## This project" in with_
