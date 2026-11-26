"""The file Anki installs: the add-on's own files at the top of a zip, with the version in its manifest."""

import ast
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
        licence = archive.read("LICENSE")
        header = archive.read("__init__.py").decode("utf-8")
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
    assert licence == (ROOT / "LICENSE").read_bytes()
    assert "Copyright (C) 2026 Zyaga" in header and "GPL-2.0-or-later" in header
    assert manifest["human_version"] == "1.2.3"
    assert manifest["name"] == "WoW Forever Japanese"
    # the add-on's AnkiWeb number: installed from the file it lands in the folder AnkiWeb uses, so Anki offers
    # its updates either way; the folder an earlier file used is switched off, and it never names itself
    assert manifest["package"] == "612475471"
    assert manifest["conflicts"] == ["wow_forever_japanese"]
    assert manifest["min_point_version"] == 231000  # Anki 23.10, the oldest the real-Anki tests ran on
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


def test_the_add_on_keeps_to_the_python_of_the_oldest_anki_it_allows():
    """Anki 23.10 runs on Python 3.9: its grammar, and no zip(strict=), which came with 3.10."""
    for path in sorted((ADDON / "wfj_anki").glob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"), feature_version=(3, 9))
        strict = [
            node.lineno
            for node in ast.walk(tree)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "zip"
            and any(k.arg == "strict" for k in node.keywords)
        ]
        assert strict == [], f"{path.name}: zip(strict=) on line {strict}"
