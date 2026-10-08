"""wfj release: the version rule, the changelog cut, notes, and the pull-request changelog gate
(docs/operations/release.md)."""

import subprocess
from pathlib import Path

import pytest

from wfj.cmd import release
from wfj.cmd.release import ReleaseError

HEAD = "# Changelog\n\nIntro line.\n\n"


def log(unreleased: str, released: str = "") -> release.Changelog:
    return release.parse(HEAD + "## Unreleased\n\n" + unreleased + ("\n" + released if released else ""))


FIXED = "### Fixed\n- A typo in a quest.\n"
ADDED = "### Added\n- Guild window in Japanese.\n" + FIXED
BREAKING = "### Breaking\n- Settings are reset.\n" + ADDED


# ── the version rule ──────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "unreleased, tags, want",
    [
        (FIXED, [], "0.1.0-alpha.1"),
        (BREAKING, [], "0.1.0-alpha.1"),
        (FIXED, ["v0.1.0-alpha.1"], "0.1.0-alpha.2"),
        (BREAKING, ["v0.1.0-alpha.1", "v0.1.0-alpha.9", "v0.1.0-alpha.10"], "0.1.0-alpha.11"),
        (ADDED, ["v1.0.0-beta.2"], "1.0.0-beta.3"),
        (FIXED, ["v1.2.0"], "1.2.1"),
        (ADDED, ["v1.2.0"], "1.3.0"),
        (BREAKING, ["v1.2.0"], "2.0.0"),
        # the latest by version, not by tag order; a release sorts after its own pre-releases; strays ignored
        (FIXED, ["v1.10.0", "v1.9.0", "v1.10.0-beta.1", "vfoo", "test"], "1.10.1"),
    ],
)
def test_next_version_rule(unreleased, tags, want):
    assert release.next_version(log(unreleased), tags) == want


def test_override_is_used_when_higher():
    assert release.next_version(log(FIXED), ["v0.1.0-alpha.3"], "0.1.0-beta.1") == "0.1.0-beta.1"
    assert release.next_version(log(FIXED), ["v0.1.0-beta.1"], "0.1.0") == "0.1.0"
    assert release.next_version(log(FIXED), [], "1.0.0") == "1.0.0"


@pytest.mark.parametrize("override", ["v1.0.0", "1.0", "1.0.0-rc.1", "1.0.0-alpha", "1.0.0x", "1.02.0", "0.1.0-alpha.01"])
def test_malformed_override_is_refused(override):
    with pytest.raises(ReleaseError, match="is not a version"):
        release.next_version(log(FIXED), [], override)


@pytest.mark.parametrize("override", ["0.1.0-alpha.3", "0.1.0-alpha.2", "0.0.9"])
def test_override_not_higher_is_refused(override):
    with pytest.raises(ReleaseError, match="not higher than the latest release 0.1.0-alpha.3"):
        release.next_version(log(FIXED), ["v0.1.0-alpha.3"], override)


@pytest.mark.parametrize("unreleased", ["", "### Added\n\n### Fixed\n"])
def test_empty_unreleased_is_nothing_to_release(unreleased):
    with pytest.raises(ReleaseError, match="nothing to release"):
        release.next_version(log(unreleased), [])
    with pytest.raises(ReleaseError, match="nothing to release"):
        release.next_version(log(unreleased), [], "1.0.0")


def test_missing_unreleased_section_is_an_error():
    with pytest.raises(ReleaseError, match="needs exactly one '## Unreleased' section \\(found 0\\)"):
        release.next_version(release.parse(HEAD + "## 1.0.0 - 2026-10-01\n\n- x\n"), [])


# ── the shape check ───────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "text, problem",
    [
        ("## Unreleased\n\n### Fixed\n- a\n\n## Unreleased\n\n### Fixed\n- b\n", "found 2"),
        ("## Unreleased\n\n### Fixed\n- a\n\n## 1.0.0 – 2026-01-01\n\n- b\n", "'## 1.0.0 – 2026-01-01' is not"),
        ("## Unreleased\n\n### Fixed\n- a\n\n## [1.0.0] - 2026-01-01\n", "'## [1.0.0] - 2026-01-01' is not"),
        ("## Unreleased\n\n### Fixed\n- a\n\n## Notes\n\nprose\n", "'## Notes' is not"),
        ("## Unreleased\n\n### Fixed\n- a\n\n## 1.0.0\n\n- b\n", "'## 1.0.0' is not"),
        ("## Unreleased\n\n### breaking\n- a\n", "'### breaking' is not a changelog group"),
        ("## Unreleased\n\n### Breaking changes\n- a\n", "'### Breaking changes' is not a changelog group"),
        ("## Unreleased\n\n### Fixed\n* a\n", "not a '- ' entry: * a"),
        ("## Unreleased\n\nSome prose.\n", "not a '- ' entry: Some prose."),
        ("## Unreleased\n\n- a\n", "entry outside a '### <group>' heading: - a"),
    ],
)
def test_lint_names_every_shape_problem(text, problem):
    problems = release.lint(release.parse(HEAD + text))
    assert any(problem in p for p in problems), problems
    with pytest.raises(ReleaseError, match=problem.replace("[", "\\[").replace("(", "\\(")[:12]):
        release.next_version(release.parse(HEAD + text), [])


def test_lint_accepts_continuations_and_crlf():
    text = HEAD + "## Unreleased\r\n\r\n### Fixed\r\n- a long entry\r\n  that wraps.\r\n\r\n" + OLD
    log = release.parse(text)
    assert release.lint(log) == []
    assert release.render(log) == release.render(release.parse(text.replace("\r\n", "\n")))


def test_malformed_heading_round_trips_verbatim():
    text = HEAD + "## Unreleased\n\n### Fixed\n- a\n\n## Notes on things\n\nprose\n"
    assert release.render(release.parse(text)) == text


def test_released_drift():
    at_tag = release.parse(HEAD + "## Unreleased\n\n" + OLD)
    assert release.released_drift(release.parse(HEAD + "## Unreleased\n\n" + FIXED + "\n" + OLD), at_tag, "v1") == []
    drifted = release.parse(HEAD + "## Unreleased\n\n" + OLD + "- Merged across the release.\n")
    problems = release.released_drift(drifted, at_tag, "v0.1.0-alpha.1")
    assert len(problems) == 1 and "differ from v0.1.0-alpha.1" in problems[0]


# ── the cut + notes ───────────────────────────────────────────────────────────

OLD = "## 0.1.0-alpha.1 - 2026-10-01\n\n### Added\n- First.\n"


def test_cut_moves_unreleased_under_the_version_and_keeps_an_empty_unreleased():
    cut = release.cut(log(ADDED, OLD), "0.1.0-alpha.2", "2026-10-05")
    assert release.render(cut) == (
        "# Changelog\n\nIntro line.\n\n"
        "## Unreleased\n\n"
        "## 0.1.0-alpha.2 - 2026-10-05\n\n"
        "### Added\n- Guild window in Japanese.\n### Fixed\n- A typo in a quest.\n\n"
        "## 0.1.0-alpha.1 - 2026-10-01\n\n### Added\n- First.\n"
    )
    again = release.parse(release.render(cut))
    assert again.unreleased.entries() == []
    assert [s.title for s in again.released()] == ["0.1.0-alpha.2", "0.1.0-alpha.1"]


def test_cut_refuses_an_existing_version():
    with pytest.raises(ReleaseError, match="already has a section for 0.1.0-alpha.1"):
        release.cut(log(FIXED, OLD), "0.1.0-alpha.1", "2026-10-05")


def test_notes_are_that_version_only():
    cut = release.cut(log(ADDED, OLD), "0.1.0-alpha.2", "2026-10-05")
    notes = release.notes(cut, "0.1.0-alpha.2")
    assert notes.startswith("## 0.1.0-alpha.2 - 2026-10-05\n\n### Added\n")
    assert "First." not in notes and "Intro line" not in notes
    with pytest.raises(ReleaseError, match="no section for 9.9.9"):
        release.notes(cut, "9.9.9")


def test_render_round_trips_the_real_changelog(root):
    text = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    parsed = release.parse(text)
    assert release.render(parsed) == text
    assert not release.LOCAL_PATH_RE.search(text)


# ── the pull-request gate ─────────────────────────────────────────────────────

BASE = HEAD + "## Unreleased\n\n### Fixed\n- Old line.\n\n" + OLD


def test_gate_needs_a_line_when_addon_or_data_changes():
    for path in ("addon/WoWForeverJapanese/UI/Gossip.lua", "data/quest/quest_0001.jsonl"):
        problems = release.gate(BASE, BASE, [path])
        assert len(problems) == 1 and "add a line for players" in problems[0]
    added = BASE.replace("- Old line.\n", "- Old line.\n- New line.\n")
    assert release.gate(BASE, added, ["addon/WoWForeverJapanese/Main.lua"]) == []


def test_gate_exempts_changes_that_do_not_reach_the_game():
    for path in ("docs/overview.md", ".github/workflows/pr.yml", "tests/python/test_cli.py", "pipeline/wfj/cli.py"):
        assert release.gate(BASE, BASE, [path]) == []


def test_gate_counts_a_repeated_line_as_added():
    added = BASE.replace("- Old line.\n", "- Old line.\n- Old line.\n")
    assert release.gate(BASE, added, ["data/x"]) == []


def test_gate_refuses_edits_to_released_sections():
    edited = BASE.replace("- First.", "- First, reworded.")
    problems = release.gate(BASE, edited, ["docs/x.md"])
    assert problems == ["released sections of CHANGELOG.md changed: only '## Unreleased' may be edited"]
    removed = BASE.replace(OLD, "")
    assert release.gate(BASE, removed, ["docs/x.md"]) == problems


@pytest.mark.parametrize("line", ["- See /" + "home/someone/notes.", "- See ~/notes.", "- See C:\\Games\\notes."])
def test_gate_refuses_local_paths(line):
    added = BASE.replace("- Old line.\n", f"- Old line.\n{line}\n")
    problems = release.gate(BASE, added, ["addon/x.lua"])
    assert problems == [f"changelog line names a local path or something private: {line}"]


@pytest.mark.parametrize("line", ["- Fixed the gossip window (" + "WFJ" + "-12).", "- Fixed it (" + "wfj" + " 12)."])
def test_gate_refuses_tracker_ids_without_any_rules_file(line):
    added = BASE.replace("- Old line.\n", f"- Old line.\n{line}\n")
    assert release.gate(BASE, added, ["addon/x.lua"]) == [f"changelog line names a local path or something private: {line}"]


def test_gate_refuses_what_the_private_rules_name():
    from wfj.core import public_text

    rules = public_text.private_rules({"patterns": {"codename": r"(?i:\bzebra-\d+)"}, "words": ["quokka"]})
    for line in ("- Fixed the gossip window (Zebra-12).", "- Thanks to Quokka."):
        added = BASE.replace("- Old line.\n", f"- Old line.\n{line}\n")
        assert release.gate(BASE, added, ["addon/x.lua"]) == []
        assert release.gate(BASE, added, ["addon/x.lua"], rules) == [
            f"changelog line names a local path or something private: {line}"
        ]


def test_gate_first_changelog_and_missing_changelog():
    assert release.gate(None, BASE, ["docs/x.md"]) == []  # the change that adds CHANGELOG.md
    assert release.gate(None, BASE, ["addon/x.lua"]) == []  # its Unreleased lines count as added
    assert release.gate(None, None, ["docs/x.md"]) == []
    assert release.gate(None, None, ["addon/x.lua"]) == ["CHANGELOG.md is missing"]
    assert release.gate(BASE, None, ["docs/x.md"]) == ["CHANGELOG.md is missing"]


# ── the CLI over a real git repo ──────────────────────────────────────────────


def _git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args], cwd=repo, check=True, capture_output=True, text=True
    ).stdout


@pytest.fixture
def repo(tmp_path, monkeypatch):
    _git(tmp_path, "init", "-q", "-b", "main")
    (tmp_path / "CHANGELOG.md").write_text(HEAD + "## Unreleased\n\n" + FIXED, encoding="utf-8")
    _git(tmp_path, "add", ".")
    _git(tmp_path, "commit", "-qm", "init")
    monkeypatch.chdir(tmp_path)
    return tmp_path


def test_cli_next_version_changelog_and_resume(repo, capsys):
    assert release.run(["next-version"]) == 0
    assert capsys.readouterr().out == "version=0.1.0-alpha.1\nresume=false\naddon=true\n"
    assert release.run(["changelog", "--version", "0.1.0-alpha.1", "--date", "2026-10-01", "--notes", "notes.md"]) == 0
    assert (repo / "notes.md").read_text(encoding="utf-8").startswith("## 0.1.0-alpha.1 - 2026-10-01\n")
    _git(repo, "commit", "-qam", "Release 0.1.0-alpha.1")
    _git(repo, "tag", "-a", "v0.1.0-alpha.1", "-m", "Release 0.1.0-alpha.1")
    capsys.readouterr()
    # a re-run of that release (its publish failed): HEAD carries the tag → resume, even with Unreleased empty
    assert release.run(["next-version", "--version", "0.1.0-alpha.1"]) == 0
    assert capsys.readouterr().out == "version=0.1.0-alpha.1\nresume=true\naddon=true\n"
    assert release.run(["notes", "--version", "0.1.0-alpha.1", "--notes", "again.md"]) == 0
    assert (repo / "again.md").read_text(encoding="utf-8") == (repo / "notes.md").read_text(encoding="utf-8")
    # without the version, a released HEAD points at resuming
    assert release.run(["next-version"]) == 1
    assert "HEAD is already released as v0.1.0-alpha.1" in capsys.readouterr().err


def test_cli_allow_empty_means_no_addon_release(repo, capsys):
    """The Release workflow passes --allow-empty: with nothing under Unreleased it releases only the voice packs
    that changed, even on a HEAD that is already released."""
    release.run(["changelog", "--version", "0.1.0-alpha.1", "--date", "2026-10-01", "--notes", "n.md"])
    _git(repo, "commit", "-qam", "Release 0.1.0-alpha.1")
    _git(repo, "tag", "-a", "v0.1.0-alpha.1", "-m", "r")
    capsys.readouterr()
    assert release.run(["next-version", "--allow-empty"]) == 0
    assert capsys.readouterr().out == "version=\nresume=false\naddon=false\n"
    # a line under Unreleased: an addon release as before
    text = (repo / "CHANGELOG.md").read_text(encoding="utf-8")
    (repo / "CHANGELOG.md").write_text(text.replace("## Unreleased\n", "## Unreleased\n\n### Fixed\n- A fix.\n", 1))
    _git(repo, "commit", "-qam", "fix")
    assert release.run(["next-version", "--allow-empty"]) == 0
    assert capsys.readouterr().out == "version=0.1.0-alpha.2\nresume=false\naddon=true\n"


def test_cli_empty_version_on_a_released_head_points_at_resume(repo, capsys):
    release.run(["changelog", "--version", "0.1.0-alpha.1", "--date", "2026-10-01", "--notes", "n.md"])
    _git(repo, "commit", "-qam", "Release 0.1.0-alpha.1")
    _git(repo, "tag", "-a", "v0.1.0-alpha.1", "-m", "r")
    capsys.readouterr()
    assert release.run(["next-version"]) == 1
    assert "HEAD is already released as v0.1.0-alpha.1: to finish that release, run again with version 0.1.0-alpha.1" \
        in capsys.readouterr().err


def test_cli_refuses_lines_merged_into_a_released_section(repo, capsys):
    release.run(["changelog", "--version", "0.1.0-alpha.1", "--date", "2026-10-01", "--notes", "n.md"])
    _git(repo, "commit", "-qam", "Release 0.1.0-alpha.1")
    _git(repo, "tag", "-a", "v0.1.0-alpha.1", "-m", "r")
    # a pull request that branched before the release merges cleanly into the released section
    text = (repo / "CHANGELOG.md").read_text(encoding="utf-8") + "- A line from a late merge.\n"
    (repo / "CHANGELOG.md").write_text(text, encoding="utf-8")
    _git(repo, "commit", "-qam", "late merge")
    capsys.readouterr()
    assert release.run(["next-version"]) == 1
    assert "released sections of CHANGELOG.md differ from v0.1.0-alpha.1" in capsys.readouterr().err


def test_cli_changelog_refuses_a_bad_date(repo, capsys):
    assert release.run(["changelog", "--version", "1.0.0", "--date", "01/10/2026", "--notes", "n.md"]) == 1
    assert "not a YYYY-MM-DD date" in capsys.readouterr().err


def test_cli_changelog_gate(repo, capsys):
    _git(repo, "checkout", "-qb", "change")
    (repo / "addon").mkdir()
    (repo / "addon" / "x.lua").write_text("-- x\n", encoding="utf-8")
    _git(repo, "add", ".")
    _git(repo, "commit", "-qm", "addon change")
    assert release.run(["changelog-gate", "--base", "main"]) == 1
    assert "add a line for players" in capsys.readouterr().err
    text = (repo / "CHANGELOG.md").read_text(encoding="utf-8") + "- The x window in Japanese.\n"
    (repo / "CHANGELOG.md").write_text(text, encoding="utf-8")
    _git(repo, "commit", "-qam", "changelog line")
    assert release.run(["changelog-gate", "--base", "main"]) == 0
    assert "changelog-gate: ok" in capsys.readouterr().out


def test_cli_gate_reads_the_base_at_the_merge_base(repo, capsys):
    """A release lands on main after a pull request branched: the PR edited no released section."""
    _git(repo, "checkout", "-qb", "change")
    (repo / "docs.md").write_text("docs\n", encoding="utf-8")
    _git(repo, "add", ".")
    _git(repo, "commit", "-qm", "docs change")
    _git(repo, "checkout", "-q", "main")
    release.run(["changelog", "--version", "0.1.0-alpha.1", "--date", "2026-10-01", "--notes", "n.md"])
    _git(repo, "commit", "-qam", "Release 0.1.0-alpha.1")
    _git(repo, "checkout", "-q", "change")
    capsys.readouterr()
    assert release.run(["changelog-gate", "--base", "main"]) == 0, capsys.readouterr().err


def test_cli_gate_counts_a_file_moved_out_of_addon(repo, capsys):
    (repo / "addon").mkdir()
    (repo / "addon" / "x.lua").write_text("-- a file long enough to be seen as a rename\n" * 5, encoding="utf-8")
    _git(repo, "add", ".")
    _git(repo, "commit", "-qm", "addon file")
    _git(repo, "checkout", "-qb", "move")
    (repo / "docs").mkdir()
    _git(repo, "mv", "addon/x.lua", "docs/x.lua")
    _git(repo, "commit", "-qm", "move out of addon")
    capsys.readouterr()
    assert release.run(["changelog-gate", "--base", "main"]) == 1
    assert "add a line for players" in capsys.readouterr().err
