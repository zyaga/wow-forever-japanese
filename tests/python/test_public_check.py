"""wfj public-check: each rule fails on a one-line example and passes on clean text.

The private rules are kept outside the repository, so these tests bring their own: invented names that mean
nothing. The examples of the public rules are assembled from pieces so that this file does not itself trip the
check it tests.
"""

import json
import os
import subprocess

import pytest

from wfj.cmd import public_check as pc
from wfj.core import public_text as pt
from wfj.io import private_rules

J = "".join

SPEC = {
    "about": "invented rules for the tests",
    "patterns": {
        "codename": r"(?i:(?<![A-Za-z0-9])zebra[-_ ]?\d+)",
        "tool name": r"\bQuokka\b",
    },
    "data_exempt": ["tool name"],
    "data_masks": [r"\bquokka-model-\d+\b"],
    "comment_rules": ["codename"],
    "path_rules": ["codename"],
    "words": ["abcd9", "foo-qux"],
    "personal": ["someone@example.org", "Featherstone"],
    "first_names": ["Marisol"],
}
RULES = pt.private_rules(SPEC)

CONTENT_FAILS = {
    "home path": J(["/Us", "ers/someone/Code/x"]),
    "external drive path": J(["/Vol", "umes/Games/World of Warcraft"]),
    "tracker id": J(["W", "FJ-12 added this"]),
}

# More spellings of the same rules.
CONTENT_VARIANTS = [
    ("home path", J(["see /Us", "ers/someone"])),
    ("home path", J(["path = '/Us", "ers/someone'"])),
    ("home path", J(["/ho", "me/someone and more"])),
    ("home path", J(["C:\\Us", "ers\\someone"])),
    ("home path", J(["c:\\us", "ers\\someone\\x"])),
    ("home path", J(['"C:\\\\Us', 'ers\\\\someone\\\\x"'])),
    ("tracker id", J(["W", "FJ 31"])),
    ("tracker id", J(["W", "FJ\u201331"])),
    ("tracker id", J(["w", "fj_31"])),
]


@pytest.mark.parametrize("rule,line", [*CONTENT_FAILS.items(), *CONTENT_VARIANTS])
def test_content_rule_fails(rule, line):
    assert rule in {h.rule for h in pt.content_hits(line)}


def test_content_rules_leave_near_misses_alone():
    text = J(["/Us", "ers/ alone\nC:\\Program Files\nSLASH_W", "FJ1 = 1\nthe /w", "fjscan command\n"])
    assert list(pt.content_hits(text)) == []


def test_public_rules_reach_comments_and_file_names():
    assert pt.history_hits(J(["-- W", "FJ-40: the widget"])) == ["tracker id"]
    assert pt.path_hits(J(["tests/lua/spec/bags_w", "fj45_spec.lua"])) == ["tracker id"]


def test_content_clean_text_passes():
    text = "He drew his sword. The rules of the arena are posted. Section 12 of the map.\n"
    assert list(pt.content_hits(text)) == []
    assert list(pt.content_hits(text, rules=RULES)) == []


def test_without_private_rules_only_the_public_rules_run():
    line = "Zebra-12 by Marisol Featherstone, with Quokka and abcd9"
    assert list(pt.content_hits(line)) == []
    assert not pt.NO_PRIVATE_RULES and RULES


def test_private_patterns_fail():
    for line in ("Zebra-12 added this", "zebra 31", "ZEBRA_31", "zebra7"):
        assert [h.rule for h in pt.content_hits(line, rules=RULES)] == ["codename"], line
    assert [h.rule for h in pt.content_hits("drafted with Quokka", rules=RULES)] == ["tool name"]
    assert list(pt.content_hits("Quokkas and a zebra", rules=RULES)) == []


def test_private_words_match_alone_and_joined():
    for line in ("Abcd9 notes", "an abcd-9 run", "the ABCD 9 skill", "foo-qux", "Foo Qux helper", "x_fooqux_y"):
        hits = list(pt.content_hits(line, rules=RULES))
        assert [(h.rule, h.text) for h in hits] == [("private word", line)], line
    assert list(pt.content_hits("abcd 99 and foo quxx", rules=RULES)) == []
    assert pt.path_hits("docs/abcd9_notes.md", rules=RULES) == ["private word"]


def test_hit_text_matches_its_line_number():
    text = "a\u2028b\r\nc\nZebra-1 here\n"
    assert [(h.line, h.text) for h in pt.content_hits(text, rules=RULES)] == [(3, "Zebra-1 here")]


def test_a_mask_and_an_exemption_apply_in_data_only():
    line = '{"model": "quokka-model-5", "note": "Zebra-1"}'
    assert [h.rule for h in pt.content_hits(line, in_data=True, rules=RULES)] == ["codename"]
    assert list(pt.content_hits('{"model": "quokka-model-5"}', in_data=True, rules=RULES)) == []
    # a word that is also a name in the game is left alone in game text
    assert list(pt.content_hits("<Kibler argues with Quokka.>", in_data=True, rules=RULES)) == []
    assert [h.rule for h in pt.content_hits("<Kibler argues with Quokka.>", rules=RULES)] == ["tool name"]


def test_capitalised_first_name_is_checked_outside_data_only():
    assert [h.rule for h in pt.content_hits("thanks, Marisol", rules=RULES)] == ["personal name or address"]
    assert list(pt.content_hits("thanks, marisol", rules=RULES)) == []
    assert list(pt.content_hits("Marisol drew a sword", in_data=True, rules=RULES)) == []
    assert list(pt.content_hits("thanks, Marisol", first_name=False, rules=RULES)) == []


def test_credits_page_skips_only_the_first_name():
    assert "ATTRIBUTION.md" in pc.FIRST_NAME_EXEMPT
    hits = pt.content_hits("by someone@example.org", first_name=False, rules=RULES)
    assert [h.rule for h in hits] == ["personal name or address"]


def test_personal_words_are_not_shown():
    text = "mail Someone@Example.org\nby FEATHERSTONE\nnothing here\n"
    hits = list(pt.content_hits(text, rules=RULES))
    assert [(h.line, h.rule, h.text) for h in hits] == [
        (1, "personal name or address", "(not shown)"),
        (2, "personal name or address", "(not shown)"),
    ]


def test_private_pattern_in_a_file_name():
    assert pt.path_hits("tests/lua/spec/bags_zebra45_spec.lua", rules=RULES) == ["codename"]
    assert pt.path_hits("tests/lua/spec/bags_spec.lua", rules=RULES) == []
    assert pt.path_hits("tests/lua/spec/bags_zebra45_spec.lua") == []


def test_a_rules_file_with_a_mistake_is_refused():
    for spec, message in [
        ({"wordz": ["x"]}, "unknown key(s): wordz"),
        ({"patterns": {"bad": "("}}, "a pattern does not compile"),
        ({"patterns": {"home path": "x"}}, "pattern name(s) already in use: home path"),
        ({"comment_rules": ["codename"]}, "comment_rules names no pattern: codename"),
    ]:
        with pytest.raises(ValueError, match=message.replace("(", r"\(").replace(")", r"\)")):
            pt.private_rules(spec)


def test_the_repository_names_nothing_private():
    """The mechanism is public and the rules are not: the modules hold no list of their own."""
    assert not pt.NO_PRIVATE_RULES
    assert set(pt.CONTENT_PATTERNS) == {"home path", "external drive path", "tracker id"}


COMMENT_FAILS = {
    "person": "-- the maintainer asked for this",
    "date": "# changed 2026-09-14",
    "approval": "-- approved in review",
    "review finding": "# finding 3: guard the nil",
    "ruling label": "# ruling B: redraft",
}

# A severity code a review gave an item is history too.
REVIEW_CODES = ["-- H2: the key", "# see (M3)", "QA H1/M1: a store", "(QA L1)", "(pass-2 L1)", "a line (PR review)"]


@pytest.mark.parametrize("rule,comment", COMMENT_FAILS.items())
def test_comment_rule_fails(rule, comment):
    assert rule in pt.history_hits(comment)


@pytest.mark.parametrize("comment", REVIEW_CODES)
def test_comment_review_codes_fail(comment):
    assert pt.history_hits(comment) == ["review finding"]


def test_comment_that_explains_why_passes():
    assert pt.history_hits("-- the client clears the font on reload, so set it again") == []
    # `h1` names a hash, a call is not a code, and neither is a list of heading tags
    assert pt.history_hits("-- the row's h1) and h1: the first hash; M1(a) is a call") == []
    assert pt.history_hits("-- the page's tags (P, H1, H2, H3) and a colour per type") == []


def test_comment_private_rules_come_first():
    assert pt.history_hits("-- Zebra-40: the widget", rules=RULES) == ["codename"]
    assert pt.history_hits("-- Zebra-40, approved", rules=RULES) == ["codename", "approval"]
    assert pt.history_hits("-- Zebra-40: the widget") == []
    # `tool name` is not a comment rule
    assert pt.history_hits("-- as Quokka does", rules=RULES) == []


def test_comment_person_first_name_is_case_sensitive():
    assert pt.history_hits("-- Marisol wanted this", rules=RULES) == ["person"]
    assert pt.history_hits("-- marisol the line", rules=RULES) == []
    assert pt.history_hits("# the MAINTAINER wanted this", rules=RULES) == ["person"]


def test_comment_date_in_a_file_name_is_a_reference():
    assert pt.history_hits("# see docs/research/2026-09-14-ui-inventory.md") == []
    assert pt.history_hits("# changed on 2026-09-14.") == ["date"]


def test_hash_comments_skip_strings_and_non_comments():
    src = 'a: "#tag" # real\nb: ${#x}\n  # own line\nurl: x#y\n## Title: t\n'
    assert list(pt.hash_comments(src)) == [(1, "# real"), (3, "# own line"), (5, "## Title: t")]
    assert list(pt.hash_comments(src, trailing=False, skip="##")) == [(3, "# own line")]


def test_lua_comments_skip_strings_and_read_long_comments():
    src = 'local a = "-- not a comment" -- one\nlocal b = [[--nor this]]\n--[[ two\nlines ]]\nlocal c = 1\n'
    assert list(pt.lua_comments(src)) == [(1, "-- one"), (3, "--[[ two\nlines ]]")]


def test_lua_comment_line_counts_a_string_continuation():
    src = 'local s = "a\\\nb"\n-- c\n'
    assert list(pt.lua_comments(src)) == [(3, "-- c")]


def test_python_comments_include_docstrings():
    src = '"""Module doc."""\n\n\ndef f():\n    """Function doc."""\n    return 1  # why\n'
    assert sorted(pt.python_comments(src)) == [(1, "Module doc."), (5, "Function doc."), (6, "# why")]


def _png(*chunks):
    def chunk(kind, data=b""):
        return len(data).to_bytes(4, "big") + kind + data + b"\0\0\0\0"

    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", b"\0" * 13) + b"".join(chunk(k, b"k\0v") for k in chunks) + chunk(b"IEND")


def _jpeg(*markers):
    def seg(marker, data=b"xx"):
        return bytes([0xFF, marker]) + (len(data) + 2).to_bytes(2, "big") + data

    return b"\xff\xd8" + seg(0xE0) + b"".join(seg(m) for m in markers) + seg(0xDA) + b"\xff\xe1\0\0" + b"\xff\xd9"


def test_image_metadata_walks_png_chunks_and_jpeg_segments():
    assert pt.image_metadata(_png()) == []
    assert pt.image_metadata(_png(b"tEXt", b"iTXt", b"zTXt", b"eXIf", b"tIME")) == ["eXIf", "iTXt", "tEXt", "zTXt"]
    assert pt.image_metadata(_jpeg()) == []
    assert pt.image_metadata(_jpeg(0xE1, 0xFE)) == ["APP1", "COM"]
    assert pt.image_metadata(b"GIF89a") == []


# ------------------------------------------------------------------------------------ against a repo


def _git(repo, *args, email="t@users.noreply.github.com"):
    subprocess.run(
        ["git", "-C", str(repo), "-c", "user.name=t", "-c", f"user.email={email}", *args],
        check=True,
        capture_output=True,
    )


@pytest.fixture(autouse=True)
def no_rules_from_the_environment(monkeypatch):
    monkeypatch.delenv(private_rules.ENV, raising=False)


def _exclude(repo, text):
    (repo / ".git" / "info" / "exclude").write_text(text)


def _rules(repo, spec=SPEC):
    (repo / ".git" / "info" / private_rules.NAME).write_text(json.dumps(spec))


@pytest.fixture
def repo(tmp_path):
    """A checkout that keeps private paths: they are in the git folder's exclude file, with the private
    rules beside it."""
    _git(tmp_path, "init", "-q")
    _exclude(tmp_path, "build/\n\n# Private project internals: outside the repo\n/notes\n/docs/private\n\n*.zip\n")
    _rules(tmp_path)
    (tmp_path / ".gitignore").write_text("build/\n")
    (tmp_path / "README.md").write_text("# Title\n\nSee [the guide](docs/guide.md).\n")
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "guide.md").write_text("Back to [the start](../README.md).\n")
    _git(tmp_path, "add", ".")
    return tmp_path


@pytest.fixture
def clone(tmp_path_factory):
    """A checkout as anyone else has one: no private paths, no private rules."""
    path = tmp_path_factory.mktemp("clone")
    _git(path, "init", "-q")
    (path / "README.md").write_text("# Title\n")
    _git(path, "add", ".")
    return path


def test_private_block_is_read_from_the_exclude_file(repo):
    assert pc.private_paths((repo / ".git" / "info" / "exclude").read_text()) == ["notes", "docs/private"]


def test_rules_are_found_in_the_git_folder_or_by_name(repo, clone, tmp_path_factory, monkeypatch):
    assert private_rules.load(repo) == RULES
    assert private_rules.load(clone) is pt.NO_PRIVATE_RULES
    named = tmp_path_factory.mktemp("rules") / "rules.json"
    named.write_text(json.dumps({"words": ["elsewhere"]}))
    monkeypatch.setenv(private_rules.ENV, str(named))
    assert private_rules.load(clone).words == frozenset({"elsewhere"})
    named.write_text("{not json")
    os.utime(named, (1, 1))
    with pytest.raises(SystemExit, match="cannot be read"):
        private_rules.load(clone)


def test_a_worktree_shares_the_rules_of_its_repository(repo, tmp_path_factory):
    _git(repo, "commit", "-q", "-m", "Start")
    tree = tmp_path_factory.mktemp("trees") / "second"
    _git(repo, "worktree", "add", "-q", str(tree), "-b", "second")
    assert private_rules.load(tree) == RULES
    assert pc.check_paths(tree) == []


def test_paths_pass_on_a_clean_repo(repo, clone):
    assert pc.check_paths(repo) == []
    assert pc.check_paths(clone) == []


def test_paths_fail_when_private_paths_are_kept_without_the_rules(repo):
    (repo / ".git" / "info" / private_rules.NAME).unlink()
    assert pc.check_paths(repo) == [f"the private rules are missing: {repo / '.git' / 'info' / private_rules.NAME}"]


def test_paths_fail_on_a_force_added_private_file(repo):
    (repo / "docs" / "private").mkdir()
    (repo / "docs" / "private" / "plan.md").write_text("x\n")
    _git(repo, "add", "-f", "docs/private/plan.md")
    assert pc.check_paths(repo) == ["docs/private/plan.md: tracked, but under the private path docs/private"]


def test_paths_fail_on_a_duplicate_entry(repo):
    _exclude(repo, "# Private project internals\n/notes\n/notes\n")
    assert pc.check_paths(repo) == ["info/exclude: private entry listed twice: notes"]


def test_paths_fail_on_a_glob_in_the_private_block(repo):
    _exclude(repo, "# Private project internals\n/notes/*.md\n")
    assert pc.check_paths(repo) == [
        "info/exclude: private entry holds a glob character (entries are compared literally): notes/*.md"
    ]


def test_paths_fail_on_a_tracked_symlink(repo, clone):
    for checkout in (repo, clone):
        os.symlink("/tmp/elsewhere", checkout / "link")
        _git(checkout, "add", "link")
        assert pc.check_paths(checkout) == ["link: tracked symlink (it would publish the path it points to)"]


def test_gitignore_is_checked_like_any_file(repo):
    (repo / ".gitignore").write_text("# from Zebra-12\n/notes-of-abcd9\nbuild/\n")
    _git(repo, "add", ".")
    assert pc.check_content(repo) == [
        ".gitignore:1: codename: # from Zebra-12",
        ".gitignore:2: private word: /notes-of-abcd9",
    ]
    assert pc.check_comments(repo) == [".gitignore:1: comment records history (codename): # from Zebra-12"]


def test_links_pass_and_fail(repo):
    assert pc.check_links(repo) == []
    (repo / "docs" / "guide.md").write_text("A [dead link](gone.md) and ![a picture](img/x.png).\n")
    _git(repo, "add", ".")
    assert pc.check_links(repo) == [
        "docs/guide.md: link to a file that is not in the repository: gone.md",
        "docs/guide.md: link to a file that is not in the repository: img/x.png",
    ]


def test_links_skip_code_decode_and_resolve_from_the_root(repo):
    (repo / "docs" / "my guide.md").write_text("x\n")
    (repo / "docs" / "guide.md").write_text(
        "[a](my%20guide.md) [b](/README.md) [c](/docs/) [d](#top)\n"
        "```\n[dead](gone.md)\n```\n~~~\n[dead](gone.md)\n~~~\n"
        "[ref]: gone-ref.md\n[ok]: /docs/guide.md \"Title\"\n[^1]: a footnote\n"
        "<img src='gone.png' alt='x'>\n"
    )
    _git(repo, "add", ".")
    assert pc.check_links(repo) == [
        "docs/guide.md: link to a file that is not in the repository: gone-ref.md",
        "docs/guide.md: link to a file that is not in the repository: gone.png",
    ]


def test_images_fail_on_metadata_under_docs_images(repo):
    (repo / "docs" / "images").mkdir()
    (repo / "docs" / "images" / "clean.png").write_bytes(_png(b"tIME"))
    (repo / "docs" / "images" / "tagged.png").write_bytes(_png(b"tEXt"))
    (repo / "docs" / "images" / "photo.JPG").write_bytes(_jpeg(0xE1))
    _git(repo, "add", ".")
    assert pc.check_images(repo) == [
        "docs/images/photo.JPG: image carries metadata (APP1); strip it",
        "docs/images/tagged.png: image carries metadata (tEXt); strip it",
    ]


def test_comments_cover_config_files_and_report_unparsable_python(repo):
    (repo / "ci.yml").write_text('a: "x" # changed on 2026-09-14.\n')
    (repo / "Addon.toc").write_text("## Title: W\n# per the maintainer\n")
    (repo / "pipeline").mkdir()
    (repo / "pipeline" / "list.txt").write_text("# approved\nword # 2026-09-14.\n")
    (repo / ".luacheckrc").write_text("-- approved\n")
    (repo / "broken.py").write_text("def f(:\n")
    _git(repo, "add", ".")
    assert pc.check_comments(repo) == [
        ".luacheckrc:1: comment records history (approval): -- approved",
        "Addon.toc:2: comment records history (person): # per the maintainer",
        "broken.py: could not parse",
        "ci.yml:1: comment records history (date): # changed on 2026-09-14.",
        "pipeline/list.txt:1: comment records history (approval): # approved",
    ]


def test_images_need_alt_text_and_a_size_limit(repo):
    (repo / "docs" / "images").mkdir()
    (repo / "docs" / "images" / "big.png").write_bytes(b"\x89PNG" + b"\0" * pc.MAX_IMAGE_BYTES)
    (repo / "README.md").write_text('![](docs/images/big.png)\n<img src="docs/images/big.png" alt="Quest window">\n')
    assert pc.check_images(repo) == [
        "README.md: image without alt text: docs/images/big.png",
        "README.md: image over 300 KB: docs/images/big.png",
        "README.md: image over 300 KB: docs/images/big.png",
    ]


def test_content_and_file_names_in_a_repo(repo):
    name = "tests/test_zebra12.py"
    (repo / "tests").mkdir()
    (repo / name).write_text("# per Zebra-12\n")
    _git(repo, "add", ".")
    problems = pc.check_content(repo)
    assert f"{name}: file name: codename" in problems
    assert any(p.startswith(f"{name}:1: codename") for p in problems)


def test_a_checkout_without_the_rules_checks_the_public_ones(clone):
    (clone / "notes.md").write_text(J(["Zebra-12 by Marisol, kept in /Us", "ers/someone/x\n"]))
    _git(clone, "add", ".")
    assert pc.check_content(clone) == [J(["notes.md:1: home path: Zebra-12 by Marisol, kept in /Us", "ers/someone/x"])]


@pytest.fixture
def pr_env(monkeypatch):
    for name in ("GITHUB_EVENT_PATH", "GITHUB_HEAD_REF", "BASE_REF", "PR_TITLE", "PR_BODY"):
        monkeypatch.delenv(name, raising=False)
    return monkeypatch


def test_pr_text(pr_env, repo):
    monkeypatch = pr_env
    monkeypatch.setenv("PR_TITLE", "Zebra-12: fix the tooltip")
    monkeypatch.setenv("PR_BODY", "Summary\n\nWith thanks to Quokka")
    rules = {p.split(": ")[1] for p in pc.check_pr(repo)}
    assert rules == {"codename", "tool name"}
    monkeypatch.setenv("PR_TITLE", "Fix the tooltip")
    monkeypatch.setenv("PR_BODY", "Fixes #12")
    assert pc.check_pr(repo) == []


def test_the_repository_itself_is_clean(root):
    for name in pc.ALL:
        assert pc.CHECKS[name](root) == [], name


def test_pr_text_from_the_event_file_and_branch(pr_env, repo, tmp_path_factory):
    event = tmp_path_factory.mktemp("event") / "event.json"
    title = "Zebra-12 fix"
    event.write_text(
        json.dumps({"pull_request": {"title": title, "body": None, "head": {"ref": "feat/tooltips"}}})
    )
    pr_env.setenv("GITHUB_EVENT_PATH", str(event))
    pr_env.setenv("PR_TITLE", "ignored when the event file exists")
    assert pc.check_pr(repo) == [f"PR_TITLE:1: codename: {title}"]
    pr_env.setenv("GITHUB_HEAD_REF", "feat/zebra-12-tooltips")
    assert [p.split(":")[0] for p in pc.check_pr(repo)] == ["PR_TITLE", "branch"]


def test_pr_commit_messages_since_the_base(pr_env, repo):
    _git(repo, "commit", "-q", "-m", "Start")
    _git(repo, "update-ref", "refs/remotes/origin/main", "HEAD")
    (repo / "x.md").write_text("x\n")
    _git(repo, "add", ".")
    _git(repo, "commit", "-q", "-m", "Fix the tooltip\n\nThanks: Quokka")
    assert pc.check_pr(repo) == []
    pr_env.setenv("BASE_REF", "main")
    problems = pc.check_pr(repo)
    assert len(problems) == 1 and problems[0].startswith("commit ")
    assert problems[0].endswith(":3: tool name: Thanks: Quokka")
    pr_env.setenv("BASE_REF", "missing")
    assert pc.check_pr(repo) == ["commits: could not read origin/missing..HEAD"]


def test_pr_commits_carry_noreply_addresses(pr_env, repo):
    _git(repo, "commit", "-q", "-m", "Start")
    _git(repo, "update-ref", "refs/remotes/origin/main", "HEAD")
    (repo / "x.md").write_text("x\n")
    _git(repo, "add", ".")
    _git(repo, "commit", "-q", "-m", "Fix the tooltip", email="someone@example.org")
    pr_env.setenv("BASE_REF", "main")
    problems = pc.check_pr(repo)
    assert [p.split(": ", 1)[1] for p in problems] == [
        "author address is not a GitHub noreply address",
        "committer address is not a GitHub noreply address",
    ]
    # a merge made on GitHub is committed by GitHub itself
    (repo / "y.md").write_text("y\n")
    _git(repo, "add", ".")
    _git(repo, "-c", "committer.email=noreply@github.com", "commit", "-q", "-m", "Merge")
    assert [p for p in pc.check_pr(repo) if "Merge" not in p and "y.md" not in p] == problems
