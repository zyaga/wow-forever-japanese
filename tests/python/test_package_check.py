"""wfj package-check: the release zip holds exactly the shipped files (docs/operations/release.md)."""

import zipfile
from pathlib import Path

import pytest

from wfj.cmd import package_check

TRACKED = [
    "addon/WoWForeverJapanese/WoWForeverJapanese.toc",
    "addon/WoWForeverJapanese/Main.lua",
    "addon/WoWForeverJapanese/Core/Const.lua",
    "addon/WoWForeverJapanese/Fonts/ipagui.ttf",
    "LICENSE",
    "ATTRIBUTION.md",
    "addon/WoWForeverJapanese/Data/Quest/.gitkeep",  # tracked, but a dotfile: never shipped
    "README.md",  # tracked, but not shipped
    "pipeline/wfj/cli.py",
]

TOC = """## Interface: 16001
## Title: WoW Forever Japanese
## Version: {version}
## X-Curse-Project-ID: {project}
{extra}
Core\\Const.lua
# a comment
Main.lua
"""


def make_zip(path: Path, *, version="v1.2.3", project="123456", extra="", drop=(), add=()) -> Path:
    files = {
        "WoWForeverJapanese/WoWForeverJapanese.toc": TOC.format(version=version, project=project, extra=extra),
        "WoWForeverJapanese/Main.lua": "-- main\n",
        "WoWForeverJapanese/Core/Const.lua": "-- const\n",
        "WoWForeverJapanese/Fonts/ipagui.ttf": "font",
        "WoWForeverJapanese/LICENSE": "GPL",
        "WoWForeverJapanese/ATTRIBUTION.md": "# Attribution\n",
    }
    for name in drop:
        del files[name]
    files.update({name: "x" for name in add})
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("WoWForeverJapanese/", "")  # directory entries, as the packager writes them
        for name, body in files.items():
            zf.writestr(name, body)
    return path


ALLOWED = package_check.allowed_files(TRACKED)


def check(tmp_path, **kw):
    return package_check.check(make_zip(tmp_path / "a.zip", **kw), "1.2.3", ALLOWED)


def test_allowed_set_is_the_addon_folder_plus_the_license_files():
    assert {
        "WoWForeverJapanese/WoWForeverJapanese.toc",
        "WoWForeverJapanese/Main.lua",
        "WoWForeverJapanese/Core/Const.lua",
        "WoWForeverJapanese/Fonts/ipagui.ttf",
        "WoWForeverJapanese/LICENSE",
        "WoWForeverJapanese/ATTRIBUTION.md",
    } == ALLOWED


def test_good_zip_passes(tmp_path):
    assert check(tmp_path) == []


@pytest.mark.parametrize(
    "name",
    ["WoWForeverJapanese/README.md", "WoWForeverJapanese/.DS_Store", "WoWForeverJapanese/.release-notes.md",
     "WoWForeverJapanese/pipeline/wfj/cli.py", "WoWForeverJapanese/CHANGELOG.md"],
)
def test_a_file_outside_the_allowed_set_fails(tmp_path, name):
    assert check(tmp_path, add=[name]) == [f"not a shipped file: {name}"]


def test_a_second_top_level_folder_fails(tmp_path):
    problems = check(tmp_path, add=["Other/Other.toc"])
    assert "top-level entry other than WoWForeverJapanese/: Other" in problems
    assert "not a shipped file: Other/Other.toc" in problems


def test_a_missing_file_fails_and_names_the_toc_entry(tmp_path):
    problems = check(tmp_path, drop=["WoWForeverJapanese/Core/Const.lua"])
    assert problems == [
        "missing from the zip: WoWForeverJapanese/Core/Const.lua",
        "the TOC lists a file the zip lacks: Core/Const.lua",
    ]


def test_missing_license_files_fail(tmp_path):
    problems = check(tmp_path, drop=["WoWForeverJapanese/LICENSE", "WoWForeverJapanese/ATTRIBUTION.md"])
    assert problems == [
        "missing from the zip: WoWForeverJapanese/ATTRIBUTION.md",
        "missing from the zip: WoWForeverJapanese/LICENSE",
    ]


def test_missing_toc_fails(tmp_path):
    problems = check(tmp_path, drop=["WoWForeverJapanese/WoWForeverJapanese.toc"])
    assert problems[-1] == "missing from the zip: WoWForeverJapanese/WoWForeverJapanese.toc"


@pytest.mark.parametrize("version", ["@project-version@", "v1.2.4", "1.2.3", ""])
def test_wrong_version_fails(tmp_path, version):
    assert check(tmp_path, version=version) == [f"## Version is '{version}', expected 'v1.2.3'"]


@pytest.mark.parametrize("project", ["", "abc", "１２３"])
def test_project_id_must_be_filled(tmp_path, project):
    assert check(tmp_path, project=project) == [
        f"## X-Curse-Project-ID is '{project}': fill in the CurseForge project id"
    ]


@pytest.mark.parametrize("field", ["Dependencies", "RequiredDeps", "OptionalDeps", "Dep", "dependencies", "DEPS"])
def test_dependencies_fail(tmp_path, field):
    assert check(tmp_path, extra=f"## {field}: Ace3") == [f"## {field}: the addon never depends on another addon"]


def test_real_tracked_files_give_the_addon_folder(root):
    allowed = package_check.allowed_files(package_check.tracked_files(root))
    assert "WoWForeverJapanese/WoWForeverJapanese.toc" in allowed
    assert "WoWForeverJapanese/LICENSE" in allowed and "WoWForeverJapanese/ATTRIBUTION.md" in allowed
    assert all(name.startswith("WoWForeverJapanese/") for name in allowed)
    assert not any("/Data/" not in n and n.endswith((".py", ".jsonl")) for n in allowed)


def test_cli_rejects_a_malformed_version(tmp_path, capsys):
    assert package_check.run([str(make_zip(tmp_path / "a.zip")), "--version", "v1.2.3"]) == 1
    assert "is not a version" in capsys.readouterr().err


def test_an_addon_level_license_file_collides_with_the_root_one():
    with pytest.raises(package_check.ReleaseError, match="collides with the root LICENSE"):
        package_check.allowed_files([*TRACKED, "addon/WoWForeverJapanese/LICENSE"])


def test_every_top_level_file_ships_or_is_ignored(root):
    """A new top-level file must be listed: shipped (LICENSE, ATTRIBUTION.md) or in .pkgmeta's ignore list.
    Otherwise the packager copies it into the zip and the package check refuses the release."""
    import subprocess

    from wfj.cmd.package_check import ROOT_FILES

    tracked = subprocess.run(
        ["git", "-C", str(root), "ls-files"], capture_output=True, text=True, check=True
    ).stdout.split()
    top = {p.split("/", 1)[0] for p in tracked if not p.startswith(".")}
    meta = (root / ".pkgmeta").read_text(encoding="utf-8")
    ignored = set(meta.split("ignore:", 1)[1].split()) - {"-"}
    unlisted = sorted(top - set(ROOT_FILES) - ignored - {"addon"})
    assert unlisted == [], f"add to .pkgmeta ignore (or ship): {unlisted}"
