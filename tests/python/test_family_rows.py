"""Every client-table text row either ships through a ui_keys.txt key or is named with a reason in
pipeline/family_rows.txt, taken on the pinned build (wfj.dev.family_rows)."""

from __future__ import annotations

import re
import subprocess
from collections import defaultdict
from pathlib import Path

import pytest

from wfj.dev import family_rows as fr
from wfj.io import wago

REASONS = {"curated", "developer", "name", "gossip", "not-shown"}


def test_every_left_out_row_has_a_reason(root: Path):
    _, rows = fr.read(root / "pipeline" / "family_rows.txt")
    unreviewed = [k for k, (reason, _, _) in rows.items() if reason == fr.UNREVIEWED]
    assert not unreviewed, f"new client-table rows: list each in ui_keys.txt or give it a reason: {unreviewed}"
    unknown = sorted({reason for reason, _, _ in rows.values()} - REASONS - {fr.UNREVIEWED})
    assert not unknown, f"reasons not described in the file's header: {unknown}"


def test_the_rows_are_taken_on_the_pinned_build(root: Path):
    makefile = (root / "Makefile").read_text(encoding="utf-8")
    pinned = re.search(r"^forever_BUILD\s*:=\s*(\S+)", makefile, re.MULTILINE).group(1)
    build, _ = fr.read(root / "pipeline" / "family_rows.txt")
    assert build == pinned, "run `make family-rows` on the pinned build"


def test_the_file_matches_the_pinned_tables(root: Path):
    makefile = (root / "Makefile").read_text(encoding="utf-8")
    pinned = re.search(r"^forever_BUILD\s*:=\s*(\S+)", makefile, re.MULTILINE).group(1)
    try:
        common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=root,
                                capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        pytest.skip("not a git checkout")
    folder = Path(common).parent / "predecessors" / "clients" / f"forever-{pinned}"
    if not (folder / "tables-source.txt").is_file():
        pytest.skip("no pinned Forever tables on this machine (predecessors/ is absent in CI)")
    keys = wago.read_keys(root / "pipeline" / "ui_keys.txt")
    _, rows = fr.read(root / "pipeline" / "family_rows.txt")
    assert set(fr.uncovered(folder, keys)) == set(rows), "run `make family-rows`"


def _folder(tmp_path: Path, achievements: str) -> Path:
    folder = tmp_path / "client"
    folder.mkdir()
    columns: dict[str, list[str]] = defaultdict(list)
    for table, column in wago.TEXT_FAMILIES.values():
        columns[table].append(column)
    for table, cols in columns.items():
        (folder / f"{table}.csv").write_text(",".join(["ID", *cols]) + "\n", encoding="utf-8")
    subclass = "ClassID,SubClassID,DisplayName_lang,VerboseName_lang\n"
    (folder / "ItemSubClass.csv").write_text(subclass, encoding="utf-8")
    (folder / "Achievement.csv").write_text(
        "ID,Title_lang,Description_lang,Reward_lang\n" + achievements, encoding="utf-8"
    )
    return folder


def test_a_new_row_comes_in_unreviewed_and_a_reviewed_row_keeps_its_reason(tmp_path: Path):
    folder = _folder(tmp_path, '1,Times camped,,\n2,Explorer,,\n3,Explorer,,\n4,[DNT] Test,,\n')
    rows = fr.uncovered(folder, ["AchievementTitle:2"])
    assert rows == {"AchievementTitle:1": "Times camped"}  # 2 and 3 share the listed English; 4 is developer text
    old = {"AchievementTitle:1": ("name", fr.english_hash("Times camped"), "kept")}
    assert "AchievementTitle:1  name  " in fr.render("1.60.1.1", rows, old)
    assert "  ?  " in fr.render("1.60.1.1", rows, {})


def test_a_reworded_row_comes_back_unreviewed(tmp_path: Path):
    folder = _folder(tmp_path, "1,Times camped at a fire,,\n")
    rows = fr.uncovered(folder, [])
    old = {"AchievementTitle:1": ("curated", fr.english_hash("Times camped"), "")}
    assert "AchievementTitle:1  ?  " in fr.render("1.60.1.1", rows, old)
