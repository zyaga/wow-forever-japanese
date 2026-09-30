"""The Lua test toolchain in CI is pinned (`.github/lua-rocks.txt`), installed and verified by
`.github/scripts/lua-rocks.sh`, and cached under a key of the pins. The script runs here against a fake
`luarocks`; the workflow is checked as text (stdlib only, no YAML parser)."""

import os
import re
import stat
import subprocess
from pathlib import Path

import pytest

PINS = ".github/lua-rocks.txt"
SCRIPT = ".github/scripts/lua-rocks.sh"
WORKFLOW = ".github/workflows/pr.yml"
ACTION = ".github/actions/lua-toolchain/action.yml"  # the composite action every Lua job runs first

EXPECTED = {
    "lua_cliargs": "3.0.2-1",
    "luasystem": "0.7.1-1",
    "dkjson": "2.11-1",
    "say": "1.4.1-3",
    "luassert": "1.9.0-1",
    "lua-term": "0.8-1",
    "luafilesystem": "1.9.0-1",
    "penlight": "1.15.0-1",
    "mediator_lua": "1.1.2-0",
    "busted": "2.3.0-1",
    "argparse": "0.7.2-1",
    "luacheck": "1.2.0-1",
    "datafile": "0.11-1",
    "luacov": "0.17.0-1",
    "cluacov": "1.0.0-1",
}

# A fake luarocks: logs its argv. `install <name> <version>` replaces every version of <name> in the tree listing
# (as luarocks does by default) unless <name> is FAKE_FAIL_ROCK and has failed fewer than FAKE_FAIL_TIMES times.
# `list --porcelain` prints the tree, failing its first FAKE_LIST_FAILS calls.
FAKE_LUAROCKS = """#!/bin/bash
echo "$*" >> "$FAKE_LOG"
while [ "${1#--}" != "$1" ]; do shift; done  # global flags (--lua-version=5.1) precede the command
case "$1" in
  install)
    if [ "$2" = "${FAKE_FAIL_ROCK:-}" ]; then
      n=$(cat "$FAKE_STATE" 2>/dev/null || echo 0)
      echo $((n + 1)) > "$FAKE_STATE"
      [ "$n" -lt "${FAKE_FAIL_TIMES:-0}" ] && { echo "Error fetching file" >&2; exit 1; }
    fi
    grep -v "^$2	" "$FAKE_LIST" > "$FAKE_LIST.tmp"; mv "$FAKE_LIST.tmp" "$FAKE_LIST"
    printf '%s\\t%s\\tinstalled\\t/tree/lib/luarocks/rocks-5.1\\n' "$2" "$3" >> "$FAKE_LIST" ;;
  list)
    n=$(cat "$FAKE_LIST_STATE" 2>/dev/null || echo 0)
    echo $((n + 1)) > "$FAKE_LIST_STATE"
    [ "$n" -lt "${FAKE_LIST_FAILS:-0}" ] && { echo "Error: cannot read manifest" >&2; exit 1; }
    cat "$FAKE_LIST" ;;
esac
"""


def _pins(root: Path) -> list[tuple[str, str]]:
    lines = (root / PINS).read_text(encoding="utf-8").splitlines()
    return [tuple(line.split()) for line in lines if line.strip() and not line.lstrip().startswith("#")]


def _porcelain(rocks: dict[str, str]) -> str:
    rows = (f"{name}\t{version}\tinstalled\t/tree/lib/luarocks/rocks-5.1\n" for name, version in rocks.items())
    return "".join(rows)


@pytest.fixture
def fake(tmp_path: Path):
    """Run the script with a fake `luarocks` first on PATH; returns (run, calls)."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    exe = bin_dir / "luarocks"
    exe.write_text(FAKE_LUAROCKS, encoding="utf-8")
    exe.chmod(exe.stat().st_mode | stat.S_IEXEC)
    log, state, listing = tmp_path / "calls.log", tmp_path / "state", tmp_path / "list.txt"
    listing.write_text(_porcelain(EXPECTED), encoding="utf-8")

    root = Path(__file__).resolve().parents[2]
    checkout = tmp_path / "checkout"
    (checkout / ".github" / "scripts").mkdir(parents=True)
    script = checkout / SCRIPT
    script.write_bytes((root / SCRIPT).read_bytes())
    (checkout / PINS).write_bytes((root / PINS).read_bytes())

    def run(mode: str, *, installed: dict[str, str] | None = None, fail_rock: str = "", fail_times: int = 0,
            luarocks: str = "", pins: bytes | None = None, list_fails: int = 0, tree: str | None = None):
        if pins is not None:
            (checkout / PINS).write_bytes(pins)
        if installed is not None:
            listing.write_text(_porcelain(installed), encoding="utf-8")
        if tree is not None:
            listing.write_text(tree, encoding="utf-8")
        env = {
            **os.environ,
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "FAKE_LOG": str(log),
            "FAKE_STATE": str(state),
            "FAKE_LIST": str(listing),
            "FAKE_FAIL_ROCK": fail_rock,
            "FAKE_FAIL_TIMES": str(fail_times),
            "FAKE_LIST_STATE": str(tmp_path / "list_state"),
            "FAKE_LIST_FAILS": str(list_fails),
            "LUA_ROCKS_RETRY_DELAY": "0",
        }
        env.pop("LUAROCKS", None)
        if luarocks:
            env["LUAROCKS"] = luarocks
        return subprocess.run(["bash", str(script), mode], capture_output=True, text=True, env=env, check=False)

    def calls() -> list[str]:
        return log.read_text(encoding="utf-8").splitlines() if log.exists() else []

    return run, calls


def test_pin_file_lists_the_twelve_rocks_exactly(root):
    pins = _pins(root)
    assert all(len(p) == 2 and re.fullmatch(r"\S+-\d+", p[1]) for p in pins), pins
    names = [name for name, _ in pins]
    assert len(names) == len(set(names)), "duplicate rock"
    assert dict(pins) == EXPECTED


def test_pins_are_in_dependency_order(root):
    order = [name for name, _ in _pins(root)]
    needs = {"luassert": ["say"], "penlight": ["luafilesystem"], "luacheck": ["argparse", "luafilesystem"],
             "busted": ["lua_cliargs", "luasystem", "dkjson", "say", "luassert", "lua-term", "penlight",
                        "mediator_lua"]}
    for rock, deps in needs.items():
        assert all(order.index(dep) < order.index(rock) for dep in deps), rock


def test_workflow_never_installs_a_rock_directly(root):
    ci, action = (root / WORKFLOW).read_text(encoding="utf-8"), (root / ACTION).read_text(encoding="utf-8")
    assert "luarocks install" not in ci and "luarocks install" not in action
    assert "run: .github/scripts/lua-rocks.sh install" in action and "lua-rocks.sh" not in ci


def _installs(pins: list[tuple[str, str]]) -> list[str]:
    return [f"install {name} {version}" for name, version in pins]


def test_install_runs_each_pin_in_file_order(root, fake):
    run, calls = fake
    r = run("install", installed={})
    assert r.returncode == 0, r.stderr
    assert calls() == ["list --porcelain"] + _installs(_pins(root)) + ["list --porcelain"]
    assert "15 pinned rocks verified" in r.stdout


def test_install_skips_pins_already_installed(fake):
    run, calls = fake
    r = run("install", installed={**EXPECTED, "busted": "2.2.0-1"})  # every pin but busted is in place
    assert r.returncode == 0, r.stderr
    assert calls() == ["list --porcelain", "install busted 2.3.0-1", "list --porcelain"]


def test_a_pin_with_another_version_beside_it_is_reinstalled(fake):
    run, calls = fake
    extra = "busted\t2.2.0-1\tinstalled\t/tree/lib/luarocks/rocks-5.1\n"
    r = run("install", tree=_porcelain(EXPECTED) + extra)
    assert r.returncode == 0, r.stderr  # the reinstall replaced 2.2.0-1, so verify passes
    assert calls() == ["list --porcelain", "install busted 2.3.0-1", "list --porcelain"]


def test_unreadable_tree_installs_everything(root, fake):
    run, calls = fake
    r = run("install", installed={}, list_fails=1)
    assert r.returncode == 0, r.stderr
    assert calls() == ["list --porcelain"] + _installs(_pins(root)) + ["list --porcelain"]


def test_verify_says_so_when_luarocks_list_fails(fake):
    run, _ = fake
    r = run("verify", list_fails=1)
    assert r.returncode != 0 and "lua-rocks: luarocks list failed" in r.stderr


def test_luarocks_override_carries_its_flags(fake):
    run, calls = fake
    r = run("verify", luarocks="luarocks --lua-version=5.1")
    assert r.returncode == 0, r.stderr
    assert calls() == ["--lua-version=5.1 list --porcelain"]


def test_script_is_executable_in_the_checkout(root):
    assert os.access(root / SCRIPT, os.X_OK)


def test_verify_passes_on_exact_match(fake):
    run, calls = fake
    r = run("verify")
    assert r.returncode == 0, r.stderr
    assert calls() == ["list --porcelain"]


def test_verify_fails_on_extra_rock(fake):
    run, _ = fake
    r = run("verify", installed={**EXPECTED, "lanes": "3.16.0-0"})
    assert r.returncode != 0
    assert "+ lanes 3.16.0-0" in r.stderr


def test_verify_fails_on_missing_rock(fake):
    run, _ = fake
    r = run("verify", installed={k: v for k, v in EXPECTED.items() if k != "lua-term"})
    assert r.returncode != 0
    assert "- lua-term 0.8-1" in r.stderr


def test_verify_fails_on_version_drift(fake):
    run, _ = fake
    r = run("verify", installed={**EXPECTED, "luasystem": "0.8.0-1"})
    assert r.returncode != 0
    assert "- luasystem 0.7.1-1" in r.stderr and "+ luasystem 0.8.0-1" in r.stderr


def test_unknown_mode_is_a_usage_error(fake):
    run, calls = fake
    r = run("bogus")
    assert r.returncode == 2 and "usage" in r.stderr
    assert calls() == []


def test_crlf_pin_file_reads_like_lf(root, fake):
    run, calls = fake
    r = run("install", installed={}, pins=(root / PINS).read_bytes().replace(b"\n", b"\r\n"))
    assert r.returncode == 0, r.stderr
    assert calls()[1] == "install lua_cliargs 3.0.2-1"


def test_malformed_or_empty_pin_file_fails_before_any_install(fake):
    run, calls = fake
    r = run("install", pins=b"busted\n")
    assert r.returncode != 0 and "malformed line" in r.stderr
    r = run("install", pins=b"# only a comment\n\n")
    assert r.returncode != 0 and "no pins" in r.stderr
    assert calls() == []


def test_install_retries_once_and_resumes_at_the_failed_rock(root, fake):
    run, calls = fake
    r = run("install", installed={}, fail_rock="lua-term", fail_times=1)
    assert r.returncode == 0, r.stderr
    assert "retrying install once" in r.stderr
    pins = _pins(root)
    at = [name for name, _ in pins].index("lua-term")
    assert calls() == (["list --porcelain"] + _installs(pins[: at + 1])  # pass 1 stops at lua-term
                       + ["list --porcelain"] + _installs(pins[at:])  # pass 2 skips the rocks pass 1 installed
                       + ["list --porcelain"])  # verify


def test_install_gives_up_after_two_passes(root, fake):
    run, calls = fake
    r = run("install", installed={}, fail_rock="lua-term", fail_times=99)
    assert r.returncode != 0
    assert "install failed twice" in r.stderr
    pins = _pins(root)
    at = [name for name, _ in pins].index("lua-term")
    assert calls() == (["list --porcelain"] + _installs(pins[: at + 1])
                       + ["list --porcelain", "install lua-term 0.8-1"])  # no third attempt, no verify


def _steps(text: str, indent: int = 4) -> list[str]:
    """The steps of a composite action (`    - ` items under `runs.steps`) or, with `indent=6`, the first
    job of a workflow, as text blocks."""
    body = text.split(" " * (indent - 2) + "steps:\n", 1)[1]
    if indent == 6:
        body = re.split(r"(?m)^  [a-z]+:\n", body, maxsplit=1)[0]
    pad = " " * indent + "- "
    return [pad + s for s in re.split(rf"(?m)^{pad}", body) if s.strip()]


def _step(text: str, needle: str, indent: int = 4) -> str:
    matches = [s for s in _steps(text, indent) if needle in s]
    assert len(matches) == 1, (needle, matches)
    return matches[0]


def _field(step: str, name: str) -> str:
    m = re.search(rf"(?m)^ +{name}: (\|\n(?: {{10,}}.*\n?)+|.*)$", step)
    assert m, (name, step)
    return m.group(1)


def _action(root: Path) -> str:
    return (root / ACTION).read_text(encoding="utf-8")


def test_cache_key_covers_image_pins_script_action_and_versions(root):
    action = _action(root)
    restore, save = _step(action, "actions/cache/restore@"), _step(action, "actions/cache/save@")
    key = _field(restore, "key")
    for part in ("${{ runner.os }}", "${{ steps.image.outputs.os }}", "${{ runner.arch }}",
                 "${{ inputs.lua-version }}", "${{ inputs.luarocks-version }}",
                 "${{ hashFiles('.github/lua-rocks.txt', '.github/scripts/lua-rocks.sh', "
                 "'.github/actions/lua-toolchain/action.yml') }}"):
        assert part in key
    assert 'echo "os=${ImageOS:-unknown}" >> "$GITHUB_OUTPUT"' in _step(action, "id: image")
    assert "restore-keys" not in action
    assert _field(save, "key") == "${{ steps.lua-toolchain.outputs.cache-primary-key }}"
    assert _field(save, "path") == _field(restore, "path")
    assert ".lua\n" in _field(restore, "path") and ".luarocks" in _field(restore, "path")


def test_toolchain_versions_are_single_sourced(root):
    action = _action(root)
    inputs = action.split("inputs:\n", 1)[1].split("runs:\n", 1)[0]
    assert 'default: "5.1"' in inputs and 'default: "3.8.0"' in inputs
    assert "luaVersion: ${{ inputs.lua-version }}" in action
    assert "luaRocksVersion: ${{ inputs.luarocks-version }}" in action
    ci = (root / WORKFLOW).read_text(encoding="utf-8")
    assert "LUA_VERSION" not in ci and "with:\n          lua-version" not in ci  # the defaults, nowhere else


def test_every_lua_job_runs_the_action_before_make(root):
    """Both code jobs of pr.yml take the toolchain from the one action; a per-step time limit is not a
    composite-step key, so the build is bounded by each job's own limit."""
    ci = (root / WORKFLOW).read_text(encoding="utf-8")
    jobs = re.findall(r"(?m)^  ([\w-]+):\n((?:    .*\n|\n)+)", ci.split("\njobs:\n", 1)[1])
    lua_jobs = [(name, body) for name, body in jobs if "uses: ./.github/actions/lua-toolchain\n" in body]
    assert [name for name, _ in lua_jobs] == ["validate", "lua"]
    for name, body in lua_jobs:
        assert re.search(r"(?m)^    timeout-minutes: \d+$", body), name
        assert body.index("actions/lua-toolchain") < body.index("run: make "), name
    assert "leafo/" not in ci and "actions/cache" not in ci  # the toolchain lives in the action only


MISS = "steps.lua-toolchain.outputs.cache-hit != 'true'"


def test_install_steps_run_only_on_cache_miss(root):
    action = _action(root)
    assert "id: lua-toolchain" in _step(action, "actions/cache/restore@")
    miss_only = [s for s in _steps(action) if any(n in s for n in (
        "leafo/gh-actions-lua@", "leafo/gh-actions-luarocks@", "lua-rocks.sh install", "actions/cache/save@",
        "run: rm -rf .lua .luarocks", "run: rm -rf .lua ", "run: rm -rf .luarocks "))]
    assert len(miss_only) == 9  # clean slate, (action, cleanup, retry) × 2, rock install, cache save
    for step in miss_only:
        assert step.startswith(f"    - if: {MISS}"), step
    for needle in ("id: image", "Lua toolchain on PATH", "lua-rocks.sh verify"):
        assert "if:" not in _step(action, needle), needle
    steps = _steps(action)
    order = [next(i for i, s in enumerate(steps) if n in s)
             for n in ("id: image", "actions/cache/restore@", "run: rm -rf .lua .luarocks\n",
                       "leafo/gh-actions-lua@", "leafo/gh-actions-luarocks@",
                       "lua-rocks.sh install", "actions/cache/save@", "Lua toolchain on PATH",
                       "lua-rocks.sh verify")]
    assert order == sorted(order) and order[-1] == len(steps) - 1


def test_a_miss_starts_from_a_clean_toolchain_dir(root):
    steps = _steps(_action(root))
    clean = next(i for i, s in enumerate(steps) if "run: rm -rf .lua .luarocks\n" in s)
    assert steps[clean].startswith(f"    - if: {MISS}\n")
    assert "leafo/gh-actions-lua@" in steps[clean + 1]


def test_lua_and_luarocks_downloads_are_retried_once(root):
    steps = _steps(_action(root))
    for action, sid, target in (("leafo/gh-actions-lua@", "lua", ".lua"),
                                ("leafo/gh-actions-luarocks@", "luarocks", ".luarocks")):
        uses = [i for i, s in enumerate(steps) if f"uses: {action}" in s]
        assert len(uses) == 2, action
        first, retry = steps[uses[0]], steps[uses[1]]
        failed = f"if: {MISS} && steps.{sid}.outcome == 'failure'"
        assert f"if: {MISS}\n" in first and f"id: {sid}\n" in first and "continue-on-error: true" in first
        cleanup = steps[uses[0] + 1]
        assert failed in cleanup and re.search(rf"run: rm -rf {re.escape(target)}( \S+)? && sleep 15\n", cleanup)
        assert uses[1] == uses[0] + 2
        assert failed in retry and "continue-on-error" not in retry and "id:" not in retry
        assert first.split("with:", 1)[1] == retry.split("with:", 1)[1]  # same inputs


def test_every_run_step_of_the_action_names_its_shell(root):
    for step in _steps(_action(root)):
        if "run:" in step:
            assert "shell: bash\n" in step, step


def test_setup_python_caches_pip(root):
    step = _step((root / WORKFLOW).read_text(encoding="utf-8"), "actions/setup-python@", indent=6)
    assert _field(step, "cache") == "pip"
    assert _field(step, "cache-dependency-path") == "pipeline/pyproject.toml"


def test_gate_steps_in_order(root):
    ci = (root / WORKFLOW).read_text(encoding="utf-8")
    gates = [
        "      - run: make lint LUA=lua\n",
        "      - run: make coverage-py\n",
        "      - run: make luac LUA=lua\n",
        "      - run: make toc-check\n",
        '      - run: make validate LUA=lua VALIDATE_FLAGS="${BASE_REF:+--base origin/$BASE_REF}"\n'
        "        env:\n"
        "          BASE_REF: ${{ github.base_ref }}",
    ]
    positions = [ci.index(g) for g in gates]
    assert positions == sorted(positions)
    assert _steps(ci, indent=6)[-1].startswith(gates[-1])
    assert ci.count("      - run: make coverage-lua LUA=lua\n") == 1  # the lua job's one gate


def test_no_expression_is_spliced_into_a_run_script(root):
    ci, action = (root / WORKFLOW).read_text(encoding="utf-8"), _action(root)
    scripts = []
    for steps, indent in ((_steps(ci, indent=6), 6), (_steps(action), 4)):
        for step in steps:  # a block script's lines sit deeper than the step's own keys
            m = re.search(rf"(?m)^ +(?:- )?run: ([|>][-+]?\n(?: {{{indent + 4},}}.*\n?)+|.*)$", step)
            if m:
                scripts.append(m.group(1))
                assert "${{" not in m.group(1), step
    assert len(scripts) >= 8 and any(s.startswith("|") for s in scripts)


def test_validate_flags_expand_only_with_a_base_ref(root):
    ci = (root / WORKFLOW).read_text(encoding="utf-8")
    value = re.search(r'make validate LUA=lua VALIDATE_FLAGS=("[^"]*")', ci).group(1)
    script = f'printf "%s" {value}'
    for base, want in (("main", "--base origin/main"), ("", "")):
        out = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env={**os.environ, "BASE_REF": base}, check=False)
        assert out.stdout == want


def test_python_dev_deps_are_pinned_exactly(root):
    """The shape, not the numbers: an exact `==` pin on each tool, so a version bump needs no edit here."""
    text = (root / "pipeline" / "pyproject.toml").read_text(encoding="utf-8")
    dev = re.search(r'(?m)^dev = \[(.*?)\]', text).group(1)
    pins = re.findall(r'"([^"]+)"', dev)
    assert [pin.split("==")[0] for pin in pins] == ["pytest", "ruff", "coverage"]
    for pin in pins:
        assert re.fullmatch(r"[a-z]+==\d+\.\d+\.\d+", pin), pin
