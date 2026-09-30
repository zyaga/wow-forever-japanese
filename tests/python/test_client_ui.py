"""The interface extractor writes only into --out, never into the install, and reports a path the
client's root does not carry instead of raising."""

from pathlib import Path

import pytest

from wfj.dev import client_ui


class _Archive:
    """A local archive with two files: one readable, one whose content is not downloaded."""

    def __init__(self, wow: Path, product: str) -> None:
        self.wow, self.product = wow, product

    def file_data_id(self, path: str, fallback: int | None = None) -> int:
        return {"Interface/FrameXML/QuestFrame.lua": 111, "Interface/FrameXML/Gone.lua": 222}.get(path, 0)

    def read_file(self, fdid: int):
        if fdid == 222:
            raise ValueError("data.019@1: header names key 0000")
        return b"QuestFrame = CreateFrame('Frame')\n", []


@pytest.fixture
def wow(tmp_path: Path) -> Path:
    install = tmp_path / "World of Warcraft"
    (install / "Data").mkdir(parents=True)
    (install / ".build.info").write_text("Version!STRING:0\n1.60.1.69893\n", encoding="utf-8")
    return install


@pytest.fixture(autouse=True)
def archive(monkeypatch):
    monkeypatch.setattr(client_ui.casc, "LocalArchive", _Archive)


def test_out_inside_the_install_is_refused(wow: Path):
    with pytest.raises(SystemExit, match="inside the install"):
        client_ui.extract(wow, "wow_classic_beta", wow / "Interface" / "out", ["Interface/FrameXML/X.lua"])
    with pytest.raises(SystemExit, match="inside the install"):
        client_ui.extract(wow, "wow_classic_beta", wow, ["Interface/FrameXML/X.lua"])


def test_a_path_the_root_does_not_name_is_reported_not_raised(wow: Path, tmp_path: Path):
    rows = client_ui.extract(wow, "wow_classic_beta", tmp_path / "out", ["Interface/FrameXML/Nope.lua"])
    assert rows == [("Interface/FrameXML/Nope.lua", None, None)]


def test_content_that_is_not_downloaded_keeps_its_id_and_reports_no_bytes(wow: Path, tmp_path: Path):
    rows = client_ui.extract(wow, "wow_classic_beta", tmp_path / "out", ["Interface/FrameXML/Gone.lua"])
    assert rows == [("Interface/FrameXML/Gone.lua", 222, None)]
    assert not (tmp_path / "out" / "Gone.lua").exists()


def test_a_readable_file_is_written_under_out(wow: Path, tmp_path: Path):
    out = tmp_path / "out"
    rows = client_ui.extract(wow, "wow_classic_beta", out, ["Interface/FrameXML/QuestFrame.lua"])
    assert rows[0][0] == "Interface/FrameXML/QuestFrame.lua" and rows[0][1] == 111 and rows[0][2] > 0
    written = out / "Interface" / "FrameXML" / "QuestFrame.lua"
    assert written.read_text(encoding="utf-8").startswith("QuestFrame")


def test_files_sharing_a_basename_do_not_overwrite_each_other(wow: Path, tmp_path: Path):
    # Forever ships vanilla/ cata/ mainline/ copies of the same file name
    out = tmp_path / "out"
    listfile = {"interface/addons/x/vanilla/questframe.lua": 111,
                "interface/addons/x/mainline/questframe.lua": 111}
    client_ui.extract(wow, "wow_classic_beta", out,
                      ["Interface/AddOns/X/Vanilla/QuestFrame.lua", "Interface/AddOns/X/Mainline/QuestFrame.lua"],
                      listfile)
    assert (out / "Interface/AddOns/X/Vanilla/QuestFrame.lua").is_file()
    assert (out / "Interface/AddOns/X/Mainline/QuestFrame.lua").is_file()


def test_a_listfile_resolves_a_path_the_root_does_not_name(wow: Path, tmp_path: Path):
    csv = tmp_path / "listfile.csv"
    csv.write_text("111;interface/framexml/questframe.lua\nnot-a-row\n", encoding="utf-8")
    listfile = client_ui.read_listfile(csv)
    assert listfile == {"interface/framexml/questframe.lua": 111}
    rows = client_ui.extract(wow, "wow_classic_beta", tmp_path / "o", ["Interface/FrameXML/Other.lua"], listfile)
    assert rows == [("Interface/FrameXML/Other.lua", None, None)]  # not in the listfile either
    rows = client_ui.extract(wow, "wow_classic_beta", tmp_path / "o2", ["Interface/FrameXML/QuestFrame.lua"],
                             {"interface/framexml/questframe.lua": 111})
    assert rows[0][1] == 111 and rows[0][2] > 0


def test_inside_reads_resolved_paths(tmp_path: Path):
    assert client_ui.inside(tmp_path / "wow" / "sub", tmp_path / "wow")
    assert client_ui.inside(tmp_path / "wow", tmp_path / "wow")
    assert not client_ui.inside(tmp_path / "elsewhere", tmp_path / "wow")
    assert not client_ui.inside(tmp_path / "wowow", tmp_path / "wow")  # a prefix is not a parent


def test_inside_is_case_blind_like_the_game_drive(tmp_path: Path):
    # the install lives on a case-insensitive volume: a miscased --out must not slip past the guard
    (tmp_path / "WoW" / "Data").mkdir(parents=True)
    assert client_ui.inside(tmp_path / "wow" / "out", tmp_path / "WoW")
    assert client_ui.inside(tmp_path / "WOW" / "out", tmp_path / "WoW")


def test_the_default_list_covers_the_hooked_surfaces():
    joined = " ".join(client_ui.DEFAULT_FILES).lower()
    for surface in ("questframe", "gossipframe", "itemtextframe", "gametooltip", "trainerui"):
        assert surface in joined


@pytest.mark.parametrize("path", [
    "../escape.lua", "a/../../escape.lua", "/etc/evil.lua", "C:/Windows/evil.lua",
    "Interface/", "", "  ",
])
def test_a_path_that_escapes_out_is_refused(tmp_path: Path, path: str):
    # the requested paths come from a third-party listfile: none of them may place a write outside --out
    assert client_ui.safe_target(tmp_path / "out", path) is None


def test_a_normal_client_path_is_kept_under_out(tmp_path: Path):
    out = tmp_path / "out"
    target = client_ui.safe_target(out, "Interface/AddOns/Blizzard_X/Vanilla/Frame.lua")
    assert target == (out / "Interface/AddOns/Blizzard_X/Vanilla/Frame.lua").resolve()
    assert client_ui.safe_target(out, "Interface\\FrameXML\\Frame.lua") == (
        out / "Interface/FrameXML/Frame.lua").resolve()


def test_an_escaping_path_is_reported_and_writes_nothing(wow: Path, tmp_path: Path, capsys):
    out = tmp_path / "out"
    rows = client_ui.extract(wow, "wow_classic_beta", out,
                             ["Interface/FrameXML/QuestFrame.lua"], {"../escape.lua": 111})
    rows += client_ui.extract(wow, "wow_classic_beta", out, ["../escape.lua"], {"../escape.lua": 111})
    assert rows[-1] == ("../escape.lua", 111, None)
    assert "refused" in capsys.readouterr().err
    assert not (tmp_path / "escape.lua").exists()
