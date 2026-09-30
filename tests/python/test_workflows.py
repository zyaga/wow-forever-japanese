"""The GitHub workflows are safe in a public repo and the release is one run (docs/operations/release.md).

Checked as text (stdlib only, no YAML parser), over every file in .github/workflows/, so a new workflow meets the
same bar: read-only token by default, the release job alone may write, the CurseForge token reaches one step,
every third-party action is pinned to a commit, and no event data is spliced into a script.
"""

import re
from pathlib import Path

import pytest

WORKFLOWS = ".github/workflows"
PINNED = re.compile(r"^[\w.-]+/[\w./-]+@[0-9a-f]{40} # v\d+(\.\d+)*$")


def _workflows(root: Path) -> dict[str, str]:
    files = sorted((root / WORKFLOWS).glob("*.y*ml"))
    assert files
    return {f.name: f.read_text(encoding="utf-8") for f in files}


def _block(text: str, key: str, indent: int = 0) -> str:
    """The lines under `key:` at `indent`, up to the next key at that indent."""
    pad = " " * indent
    m = re.search(rf"(?m)^{pad}{re.escape(key)}:.*\n((?:(?:{pad} .*)?\n)*)", text)
    assert m, key
    return m.group(1)


def _keys(block: str, indent: int) -> list[str]:
    return re.findall(rf"(?m)^ {{{indent}}}([\w-]+):", block)


def _run_scripts(text: str) -> list[str]:
    scripts = []
    for m in re.finditer(r"(?m)^( +)(?:- )?run: (.*)\n", text):
        indent, first = len(m.group(1)), m.group(2)
        if first.startswith(("|", ">")):
            body = re.match(rf"((?:(?: {{{indent + 1},}}.*)?\n)*)", text[m.end():]).group(1)
            scripts.append(body)
        else:
            scripts.append(first)
    return scripts


def _steps(job: str) -> list[str]:
    body = job.split("    steps:\n", 1)[1]
    return ["      - " + s for s in re.split(r"(?m)^      - ", body) if s.strip()]


def _step_named(job: str, name: str) -> tuple[int, str]:
    found = [(i, s) for i, s in enumerate(_steps(job)) if f"name: {name}\n" in s]
    assert len(found) == 1, name
    return found[0]


# ── every workflow ────────────────────────────────────────────────────────────


def test_every_workflow_defaults_to_a_read_only_token(root):
    for name, text in _workflows(root).items():
        assert re.search(r"(?m)^permissions:\n  contents: read\n(?!  )", text), name
        assert "write-all" not in text and "read-all" not in text, name


def test_only_the_release_job_can_write(root):
    for name, text in _workflows(root).items():
        writes = re.findall(r"(?m)^ +[\w-]+: write\b.*$", text)
        if name == "release.yml":
            release_job = _block(text, "release", 2)
            assert writes == [w for w in re.findall(r"(?m)^ +[\w-]+: write\b.*$", release_job)], name
            assert [w.split("#")[0].strip() for w in writes] == ["contents: write"]
        elif name == "report-check.yml":
            # the fix-report check (ADR-045) comments on and labels the issue it reads; its one job may
            # write issues, and nothing else
            check_job = _block(text, "check", 2)
            assert writes == [w for w in re.findall(r"(?m)^ +[\w-]+: write\b.*$", check_job)], name
            assert [w.split("#")[0].strip() for w in writes] == ["issues: write"]
        else:
            assert writes == [], name


def test_every_job_that_runs_on_a_runner_has_a_time_limit(root):
    for name, text in _workflows(root).items():
        for job in re.findall(r"(?m)^  ([\w-]+):\n((?:    .*\n|\n)+)", text.split("\njobs:\n", 1)[1]):
            if "runs-on:" in job[1]:  # a job that calls another workflow has that workflow's limit
                assert re.search(r"(?m)^    timeout-minutes: \d+$", job[1]), f"{name}: {job[0]}"


def test_pull_request_checks_keep_no_token_and_cancel_only_their_own_older_run(root):
    text = _workflows(root)["pr.yml"]
    assert text.count("persist-credentials: false") == 3  # validate, lua, text
    # a push to main or a release has no pull request number: its group is its own run, never cancelled; an
    # edit of the text and a push of code are two groups, so neither cancels the other
    assert ("group: pr-${{ github.event.pull_request.number || github.run_id }}"
            "-${{ github.event.action == 'edited' && 'text' || 'code' }}\n  cancel-in-progress: true") in text


def test_an_edit_of_the_text_runs_the_text_job_alone(root):
    text = _workflows(root)["pr.yml"]
    validate, lua, job = _block(text, "validate", 2), _block(text, "lua", 2), _block(text, "text", 2)
    assert "if: github.event.action != 'edited'" in validate
    assert "if: github.event.action != 'edited'" in lua
    assert "if: github.event_name == 'pull_request'" in job
    assert "python -m wfj public-check pr" in job and "public-check pr" not in validate + lua
    assert "pip install" not in job and "pip install" not in lua


def test_the_two_test_suites_run_in_two_jobs(root):
    """The wait for a pull request is the longer suite, not both in a row: pytest under coverage in
    validate, busted under luacov in lua."""
    text = _workflows(root)["pr.yml"]
    assert _keys(_block(text, "jobs"), 2) == ["validate", "lua", "text"]
    validate, lua = _block(text, "validate", 2), _block(text, "lua", 2)
    assert "run: make coverage-py\n" in validate and "coverage-lua" not in validate
    assert "run: make coverage-lua LUA=lua\n" in lua and "coverage-py" not in lua
    assert "make lint" in validate and "make validate" in validate and "make " not in lua.replace("make coverage-lua LUA=lua", "")


def test_workflows_agree_on_one_python_version(root):
    versions = set()
    for text in _workflows(root).values():
        versions |= set(re.findall(r'(?m)^ +python-version: "([\d.]+)"$', text))
    assert versions == {"3.14"}


def test_no_workflow_runs_untrusted_code_with_secrets(root):
    for name, text in _workflows(root).items():
        assert "pull_request_target" not in text, name
        assert "workflow_run" not in text, name


def _actions(root: Path) -> dict[str, str]:
    """The repository's own composite actions, held to the same pins as the workflows."""
    return {str(f.relative_to(root)): f.read_text(encoding="utf-8")
            for f in sorted((root / ".github/actions").glob("*/action.yml"))}


def test_every_third_party_action_is_pinned_to_a_commit(root):
    uses = []
    for name, text in {**_workflows(root), **_actions(root)}.items():
        for ref in re.findall(r"(?m)^ +(?:- )?uses: (.*)$", text):
            uses.append(ref)
            if not ref.startswith("./"):
                assert PINNED.match(ref), f"{name}: {ref}"
    assert len(uses) >= 10
    assert any(ref.startswith("./.github/actions/") for ref in uses)


def test_no_expression_is_spliced_into_a_run_script(root):
    for name, text in {**_workflows(root), **_actions(root)}.items():
        scripts = _run_scripts(text)
        assert scripts, name
        for script in scripts:
            assert "${{" not in script, f"{name}: {script}"


def test_the_curseforge_token_reaches_the_publish_step_only(root):
    for name, text in _workflows(root).items():
        if name != "release.yml":
            assert "CF_API_KEY" not in text, name
    text = _workflows(root)["release.yml"]
    uses = re.findall(r"secrets\.CF_API_KEY[^}]*}}", text)
    assert uses == ["secrets.CF_API_KEY != '' }}", "secrets.CF_API_KEY }}"]
    _, publish = _step_named(_block(text, "release", 2), "Publish to CurseForge and GitHub")
    assert "CF_API_KEY: ${{ secrets.CF_API_KEY }}" in publish
    assert "CF_TOKEN_SET: ${{ secrets.CF_API_KEY != '' }}" in _block(text, "plan", 2)


def test_no_workflow_releases_on_a_tag_push(root):
    for name, text in _workflows(root).items():
        on = _block(text, "on")
        assert "tags" not in on, name


# ── the release: one run ──────────────────────────────────────────────────────


@pytest.fixture
def release(root) -> str:
    return _workflows(root)["release.yml"]


def test_release_has_one_trigger_with_one_optional_input(release):
    on = _block(release, "on")
    assert _keys(on, 2) == ["workflow_dispatch"]
    inputs = _block(on, "inputs", 4)
    assert _keys(inputs, 6) == ["version"]
    assert "required: false" in inputs and 'default: ""' in inputs


def test_release_runs_one_at_a_time(release):
    assert "concurrency:\n  group: release\n  cancel-in-progress: false\n" in release


def test_release_jobs_plan_then_validate_then_release(release):
    jobs = _block(release, "jobs")
    assert _keys(jobs, 2) == ["plan", "validate", "release"]
    validate = _block(release, "validate", 2)
    assert "uses: ./.github/workflows/pr.yml\n" in validate and "needs: plan\n" in validate
    assert "needs: [plan, validate]\n" in _block(release, "release", 2)


def test_release_refuses_before_anything_else(release):
    plan = _steps(_block(release, "plan", 2))
    assert "if: github.ref != 'refs/heads/main'" in plan[0] and "exit 1" in plan[0]
    assert "if: env.CF_TOKEN_SET != 'true'" in plan[1] and "exit 1" in plan[1]
    nxt = next(i for i, s in enumerate(plan) if "wfj release next-version" in s)
    assert "$GITHUB_OUTPUT" in plan[nxt] and nxt == len(plan) - 2  # then only the resume guard


def test_release_pushes_only_after_the_zip_is_checked(release):
    job = _block(release, "release", 2)
    order = [_step_named(job, n)[0] for n in (
        "Changelog, commit and tag", "Build", "Check the zip", "Push the changelog commit and tag",
        "Publish to CurseForge and GitHub", "Summary")]
    assert order == sorted(order)
    _, build = _step_named(job, "Build")
    _, publish = _step_named(job, "Publish to CurseForge and GitHub")
    assert "args: -d # build only" in build
    assert "args: -c -o\n" in publish  # zips the checked package folder, no fresh copy
    _, check = _step_named(job, "Check the zip")
    assert "wfj package-check" in check
    _, push = _step_named(job, "Push the changelog commit and tag")
    assert 'push --atomic origin "HEAD:refs/heads/main" "refs/tags/v$VERSION"' in push
    # everything before the push happens on the runner only
    steps = _steps(job)
    for step in steps[: steps.index(push)]:
        assert "git push" not in step and "secrets." not in step


def test_a_resumed_release_skips_the_commit_tag_and_push(release):
    job = _block(release, "release", 2)
    for name in ("Changelog, commit and tag", "Push the changelog commit and tag"):
        assert "if: env.RESUME != 'true'" in _step_named(job, name)[1]
    assert "if: env.RESUME == 'true'" in _step_named(job, "Notes of the release being resumed")[1]


def test_release_workflow_and_makefile_share_the_packager_pin(root, release):
    shas = set(re.findall(r"BigWigsMods/packager@([0-9a-f]{40})", release))
    assert len(shas) == 1
    makefile = (root / "Makefile").read_text(encoding="utf-8")
    assert f"PACKAGER_SHA  := {shas.pop()}" in makefile


def test_make_release_starts_the_workflow_and_follows_it(root):
    makefile = (root / "Makefile").read_text(encoding="utf-8")
    recipe = re.search(r"(?m)^release:.*\n((?:\t.*\n)+)", makefile).group(1)
    assert "gh workflow run release.yml --ref main" in recipe
    assert "gh run watch" in recipe and "--exit-status" in recipe


# ── pull requests ─────────────────────────────────────────────────────────────


def test_pr_checks_are_reusable_by_the_release(root):
    on = _block(_workflows(root)["pr.yml"], "on")
    assert _keys(on, 2) == ["pull_request", "push", "workflow_dispatch", "workflow_call"]


def test_changelog_gate_and_data_delta_run_on_pull_requests_only(root):
    text = _workflows(root)["pr.yml"]
    _, gate = _step_named(text, "Changelog")
    assert "if: github.event_name == 'pull_request'" in gate
    assert 'wfj release changelog-gate --base "origin/$BASE_REF"' in gate
    _, delta = _step_named(text, "Data delta")
    assert "if: github.event_name == 'pull_request'" in delta
    assert 'changed=$(git diff --name-only "origin/$BASE_REF...HEAD" -- data/)' in delta
    assert 'if [ -n "$changed" ]; then' in delta and 'wfj stats --delta "origin/$BASE_REF" ||' in delta
    assert '>> "$GITHUB_STEP_SUMMARY"' in delta


def test_the_write_token_reaches_the_push_and_publish_steps_only(release):
    job = _block(release, "release", 2)
    assert "persist-credentials: false" in _steps(job)[0]
    holders = [s for s in _steps(job) if "secrets.GITHUB_TOKEN" in s]
    assert len(holders) == 2
    assert "name: Push the changelog commit and tag" in holders[0]
    assert "name: Publish to CurseForge and GitHub" in holders[1]


def test_a_resume_refuses_an_already_published_version(release):
    _, guard = _step_named(_block(release, "plan", 2), "Not already published")
    assert "if: steps.next.outputs.resume == 'true'" in guard
    assert 'gh release view "v$VERSION"' in guard and "exit 1" in guard


def test_the_post_publish_check_never_fails_a_published_release(release):
    _, summary = _step_named(_block(release, "release", 2), "Summary")
    assert "shopt -s nullglob" in summary
    assert '|| echo "::warning::' in summary


def test_dependabot_watches_every_composite_action(root):
    """Dependabot's root github-actions entry reads .github/workflows only; an action pinned inside a composite
    action is watched only through an entry for that action's folder."""
    config = (root / ".github/dependabot.yml").read_text(encoding="utf-8")
    watched = re.findall(r"(?m)^  - package-ecosystem: github-actions\n    directory: (\S+)$", config)
    assert "/" in watched
    for folder in sorted(p.parent for p in (root / ".github/actions").glob("*/action.yml")):
        assert f"/{folder.relative_to(root)}" in watched, folder
