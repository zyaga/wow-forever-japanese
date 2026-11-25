"""The file Anki installs: the add-on's own files at the top of a zip, with the version in its manifest."""

import importlib.util
import json
import zipfile

from anki_addon import ADDON, ROOT

_spec = importlib.util.spec_from_file_location("anki_package", ADDON / "tools" / "package.py")
package = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(package)


def test_the_file_holds_the_add_on_at_its_top(tmp_path):
    out = tmp_path / "build" / "WoWForeverJapanese.ankiaddon"
    (ADDON / "wfj_anki" / "__pycache__").mkdir(exist_ok=True)
    names = package.build(out, "1.2.3")
    with zipfile.ZipFile(out) as archive:
        packed = archive.namelist()
        manifest = json.loads(archive.read("manifest.json"))
        config = json.loads(archive.read("config.json"))
    assert packed == names
    for needed in (
        "__init__.py",
        "manifest.json",
        "config.json",
        "config.md",
        "ui.py",
        "sync.py",
        "plan.py",
        "collection.py",
        "templates/front.html",
        "templates/back.html",
        "templates/style.css",
    ):
        assert needed in packed
    assert not any(
        "__pycache__" in n or n.startswith(("tests/", "tools/", "wfj_anki/")) or n == "meta.json"
        for n in packed
    )
    assert manifest["human_version"] == "1.2.3"
    assert manifest["package"] and manifest["name"] == "WoW Forever Japanese"
    assert manifest["min_point_version"] >= 250900
    assert config == {"folder": "", "front": "sentence", "audio": "back"}


def test_the_same_tree_gives_the_same_file(tmp_path):
    package.build(tmp_path / "a.ankiaddon", "1.2.3")
    package.build(tmp_path / "b.ankiaddon", "1.2.3")
    assert (tmp_path / "a.ankiaddon").read_bytes() == (tmp_path / "b.ankiaddon").read_bytes()


def test_the_release_adds_the_file_to_the_github_release():
    workflow = (ROOT / ".github" / "workflows" / "release.yml").read_text(encoding="utf-8")
    assert (
        'python anki-addon/tools/package.py build/anki/WoWForeverJapanese.ankiaddon --version "$VERSION"'
        in workflow
    )
    assert 'gh release upload "v$VERSION" build/anki/WoWForeverJapanese.ankiaddon --clobber' in workflow
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    assert "anki-package:" in makefile and "anki-cards:" in makefile
