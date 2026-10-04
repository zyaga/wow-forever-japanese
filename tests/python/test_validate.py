"""The CI gate: passes on the repo, fails on each broken invariant."""

import shutil
import subprocess
from pathlib import Path

from wfj.cmd import generate, validate
from wfj.core.model import english_line, entry, provenance
from wfj.emit import schema
from wfj.io.jsonl_store import Store

ADDON = "addon/WoWForeverJapanese"
PROV = provenance(
    "human", "cqjt@3446c82", "2026-09-13", translator="T", origins=["cqjt@3446c82#1"]
)


def test_committed_repo_validates(root, plan_report):
    planned, report = plan_report
    assert validate.validate(root / "data", root / ADDON, None, planned, report["meaning_numbers"]) == []


def test_hand_edit_of_a_shard_or_the_toc_block_fails(root, tmp_path, planned):
    addon = tmp_path / "WoWForeverJapanese"
    shutil.copytree(root / ADDON, addon, ignore=shutil.ignore_patterns("Fonts"))
    shard = addon / "Data/Quest/Quest_0000.lua"
    shard.write_text(
        shard.read_text(encoding="utf-8").replace(
            "Koboldキャンプの掃討", "Koboldキャンプの片付け", 1
        ),
        encoding="utf-8",
    )
    problems = validate.rule_regenerate(root / "data", Store(root / "data"), addon, planned)
    assert any("Data/Quest/Quest_0000.lua differs" in p for p in problems)
    shutil.copy(root / ADDON / "Data/Quest/Quest_0000.lua", shard)
    toc = addon / generate.TOC_NAME
    toc.write_text(
        toc.read_text(encoding="utf-8").replace("Data\\Quest\\Quest_0000.lua\n", ""),
        encoding="utf-8",
    )
    problems = validate.rule_regenerate(root / "data", Store(root / "data"), addon, planned)
    assert problems == [
        f"regenerate: {generate.TOC_NAME} generated block differs; run `make generate`"
    ]


def test_rule_regenerate_uses_a_given_plan(root, tmp_path, planned):
    """A caller that holds the plan passes it; the rule then compares the addon against that plan and
    plans nothing itself."""
    addon = tmp_path / "WoWForeverJapanese"
    shutil.copytree(root / ADDON, addon, ignore=shutil.ignore_patterns("Fonts"))
    other = dict(planned, **{"Data/Quest/Quest_0000.lua": "-- another plan\n"})
    problems = validate.rule_regenerate(root / "data", Store(root / "data"), addon, other)
    assert problems == [
        "regenerate: Data/Quest/Quest_0000.lua differs from a regeneration; run `make generate`, never hand-edit"
    ]
    assert validate.rule_regenerate(root / "data", Store(root / "data"), addon, planned) == []


def _tree(tmp_path: Path, quest_lines, english_lines) -> Path:
    data = tmp_path / "data"
    data.mkdir(exist_ok=True)
    (data / "SCHEMA").write_text("1\n", encoding="utf-8")
    Store(data).save("quest", quest_lines, allow_empty=True)
    Store(data, english=True).save("quest", english_lines, allow_empty=True)
    return data


def _q(id_, field, ja, status, h, cls="human"):
    prov = dict(PROV, **{"class": cls}) if cls != "human" else PROV
    if cls == "machine":
        prov = provenance(
            "machine", "model@2026-09", "2026-09-13", translator="m", origins=["x#1"]
        )
    ln = entry(id_, field, ja, prov=prov)
    ln["status"] = status
    ln["english"] = {"hash": h, "src": "pfquest@7786596"}
    return ln


def test_schema_rule_flags_invalid_lines(tmp_path):
    bad = _q(1, "title", "x", "trusted", "d311f9a5c36057a2")
    bad["status"] = "bogus"
    data = _tree(
        tmp_path,
        [bad],
        [english_line(1, "title", "X", "d311f9a5c36057a2", "pfquest@7786596")],
    )
    problems = validate.rule_schema(data, Store(data), Store(data, english=True))
    assert problems and "quest 1/title" in problems[0]


def test_schema_rule_reports_duplicate_lines(tmp_path):
    a = _q(1, "title", "甲", "trusted", "d311f9a5c36057a2")
    en = [english_line(1, "title", "X", "d311f9a5c36057a2", "pfquest@7786596")]
    data = _tree(tmp_path, [a, dict(a, ja="乙")], en)
    problems = validate.rule_schema(data, Store(data), Store(data, english=True))
    assert "quest 1/title: duplicate line" in problems


def test_mixed_english_versions_are_a_validate_problem(root, tmp_path):
    en = [english_line(1, "title", "X", "d311f9a5c36057a2", "pfquest@7786596")]
    lines = [
        _q(1, "title", "一", "trusted", "d311f9a5c36057a2"),
        _q(2, "title", "二", "trusted", "d311f9a5c36057a2"),
    ]
    lines[1]["english"]["src"] = "pfquest@0000000"
    data = _tree(tmp_path, lines, en)
    (tmp_path / "vectors").mkdir()
    shutil.copy(
        root / "vectors/hash_vectors.jsonl", tmp_path / "vectors/hash_vectors.jsonl"
    )
    problems = validate.rule_regenerate(data, Store(data), root / ADDON)
    assert problems == [
        (
            "regenerate: english sources pinned at several versions: {'pfquest': ['0000000', '7786596']}"
            "; re-run `make import-english`"
        )
    ]


def test_a_stale_line_keeps_its_old_version_without_failing_generate(root, tmp_path):
    """A source bump (new WDB_BUILD) with one changed line leaves that line `stale` on the old
    version (sticky baseline). That is history, not a mixed store: regenerate passes and Meta pins the new one."""
    en = [english_line(1, "title", "X", "d311f9a5c36057a2", "pfquest@1111111")]
    lines = [
        _q(1, "title", "一", "trusted", "d311f9a5c36057a2"),
        _q(2, "title", "二", "stale", "0123456789abcdef"),
    ]
    lines[0]["english"]["src"] = "pfquest@1111111"
    lines[1]["english"]["src"] = "pfquest@0000000"
    data = _tree(tmp_path, lines, en)
    from wfj.cmd import generate

    planned = generate.plan(Store(data), generate.vectors_rows(root / "data"))
    assert 'pfquest = "1111111"' in planned["Data/Meta.lua"] and "0000000" not in planned["Data/Meta.lua"]


def test_dotfiles_under_data_are_ignored(root, tmp_path, planned):
    addon = tmp_path / "WoWForeverJapanese"
    shutil.copytree(root / ADDON, addon, ignore=shutil.ignore_patterns("Fonts"))
    (addon / "Data/Quest/.DS_Store").write_bytes(b"\x00")
    assert validate.rule_regenerate(root / "data", Store(root / "data"), addon, planned) == []
    assert (addon / "Data/Quest/.DS_Store").exists()


def test_provenance_rule_against_a_git_base(tmp_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repo, check=True)
    en = english_line(1, "title", "X", "d311f9a5c36057a2", "pfquest@7786596")
    _tree(
        repo,
        [
            _q(1, "title", "人", "trusted", "d311f9a5c36057a2"),
            _q(2, "title", "二", "trusted", "d311f9a5c36057a2"),
        ],
        [en],
    )
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(
        [
            "git",
            "-c",
            "user.email=t@t",
            "-c",
            "user.name=t",
            "commit",
            "-q",
            "-m",
            "base",
        ],
        cwd=repo,
        check=True,
    )
    machine = _q(1, "title", "機", "trusted", "d311f9a5c36057a2", cls="machine")
    corrected = _q(2, "title", "訂正", "trusted", "d311f9a5c36057a2")
    corrected["provenance"] = provenance(
        "correction", "review@2026-09", "2026-09-13", translator="r", origins=["x#1"]
    )
    _tree(repo, [machine, corrected], [en])
    problems = validate.rule_provenance(repo / "data", Store(repo / "data"), "HEAD")
    assert problems == ["provenance: quest 1/title was human at HEAD, now machine"]
    assert validate.rule_provenance(repo / "data", Store(repo / "data"), None) == []


def test_collision_rule(tmp_path):
    en = [
        english_line(1, "title", "Alpha", "aaaaaaaaaaaaaaaa", "pfquest@7786596"),
        english_line(2, "title", "Beta", "aaaaaaaaaaaaaaaa", "pfquest@7786596"),
        english_line(
            3, "title", "Alpha  ", "aaaaaaaaaaaaaaaa", "pfquest@7786596"
        ),  # same normalized text: fine
    ]
    data = _tree(tmp_path, [], en)
    problems = validate.rule_collisions(Store(data, english=True))
    assert len(problems) == 1 and "hash aaaaaaaaaaaaaaaa" in problems[0]


def test_referential_rule(tmp_path):
    en = [english_line(1, "title", "X", "d311f9a5c36057a2", "pfquest@7786596")]
    lines = [
        _q(
            1, "title", "一", "trusted", "0000000000000000"
        ),  # trusted but not the current hash
        _q(
            1, "objectives", "二", "stale", "d311f9a5c36057a2"
        ),  # stale but equal to current (title-only scope → joined)
        _q(
            2, "title", "三", "trusted", "d311f9a5c36057a2"
        ),  # no English scope for id 2
    ]
    data = _tree(tmp_path, lines, en)
    problems = validate.rule_referential(Store(data), Store(data, english=True))
    assert any(
        "quest 1/title: trusted but its hash is not the current English" in p
        for p in problems
    )
    assert any("quest 2/title: shipped but no English scope" in p for p in problems)
    ok = [
        _q(1, "title", "一", "trusted", "d311f9a5c36057a2"),
        _q(1, "objectives", "二", "stale", "0000000000000000"),
    ]
    data = _tree(tmp_path, ok, en)
    assert validate.rule_referential(Store(data), Store(data, english=True)) == []


def test_ci_runs_validate(root):
    ci = (root / ".github/workflows/pr.yml").read_text(encoding="utf-8")
    assert "make validate" in ci and "fetch-depth: 0" in ci


def test_bad_base_ref_is_a_problem_not_a_traceback(root):
    problems = validate.rule_provenance(
        root / "data", Store(root / "data"), "origin/no-such-branch"
    )
    assert len(problems) == 1 and problems[0].startswith(
        "provenance: cannot read data/ at 'origin/no-such-branch'"
    )


def test_duplicated_toc_block_is_a_problem(root, tmp_path, planned):
    addon = tmp_path / "WoWForeverJapanese"
    shutil.copytree(root / ADDON, addon, ignore=shutil.ignore_patterns("Fonts"))
    toc = addon / generate.TOC_NAME
    toc.write_text(
        toc.read_text(encoding="utf-8") + f"{schema.TOC_BEGIN}\n{schema.TOC_END}\n",
        encoding="utf-8",
    )
    problems = validate.rule_regenerate(root / "data", Store(root / "data"), addon, planned)
    assert problems == [
        (
            f"regenerate: {generate.TOC_NAME} needs exactly one generated block: 2 begin / 2 end marker(s) "
            f"({schema.TOC_BEGIN!r} … {schema.TOC_END!r})"
        )
    ]


def _fingerprinted(id_, ja, en):
    from wfj.core.hashing import key
    from wfj.core.normalize import normalize_v1

    ln = entry(id_, "text", ja, prov={"class": "machine", "model": "m", "source": "draft-x-sg9@2026-09-27",
                                      "imported": "2026-09-27"})
    ln["status"], ln["english"] = "trusted", {"hash": key(normalize_v1(en)), "src": "wdb@1.60.1.70009"}
    return ln


def test_objective_rule_spans_objective_and_area_rows(tmp_path, capsys):
    """The addon indexes objective and area rows by one fingerprint, so an English shared by an
    objective row and an area row (or two area rows) with different Japanese is refused; the same Japanese
    passes, and the shipped counts of both types are printed."""
    d = tmp_path / "data"
    d.mkdir()
    Store(d).save("objective", [_fingerprinted(1, "Towerに印をつける", "Tower Marked"),
                                _fingerprinted(2, "Drullを救出する", "Rescue Drull")])
    Store(d).save("area", [_fingerprinted(1, "Towerを示す", "Tower Marked"),   # same id as objective 1: no clash
                           _fingerprinted(7, "Drullを救出する", "Rescue Drull"),  # same Japanese: fine
                           _fingerprinted(8, "鉱山を偵察する", "Scout the mine"),
                           _fingerprinted(9, "鉱山を調べる", "Scout the mine")])
    assert sorted(validate.rule_objective(Store(d))) == [  # listed in fingerprint order; compared as a set
        "objective ambiguous: area 1, objective 1 share one English fingerprint with different Japanese",
        "objective ambiguous: area 8, area 9 share one English fingerprint with different Japanese",
    ]
    assert "validate: objective index: objective 2 shipped · area 4 shipped" in capsys.readouterr().out


def test_objective_rule_groups_by_the_32_bit_fingerprint_the_addon_indexes(tmp_path, monkeypatch):
    """Two different English hashes sharing their first 32 bits are one addon fingerprint."""
    d = tmp_path / "data"
    d.mkdir()
    a, b = _fingerprinted(1, "甲", "A"), _fingerprinted(2, "乙", "B")
    a["english"]["hash"], b["english"]["hash"] = "0123456789abcdef", "01234567ffffffff"
    Store(d).save("objective", [a])
    Store(d).save("area", [b])
    assert validate.rule_objective(Store(d)) == [
        "objective ambiguous: area 2, objective 1 share one English fingerprint with different Japanese"
    ]
