"""The Lua spec runner (`tests/lua/run-specs.sh`): one busted process per spec file, several at once, the
results added up, every failing file shown and the run failed, and under coverage one luacov stats file
added up from all of them."""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

RUNNER = "tests/lua/run-specs.sh"
MERGE = "tests/lua/merge-coverage.lua"

PASSES = """describe("a passing file", function()
  it("one", function() assert.are.equal(1, 1) end)
  it("two", function() assert.are.equal(2, 2) end)
end)
"""
FAILS = """describe("a failing file", function()
  it("passes", function() assert.is_true(true) end)
  it("fails", function() assert.are.equal("the expected value", "the value this file got") end)
end)
"""
BREAKS = 'error("this file breaks while it loads")\n'
# leaves with a success code before busted can print its result line
LEAVES = 'describe("a file that leaves early", function() it("x", function() os.exit(0) end) end)\n'


def _tool(name: str) -> str | None:
    home = Path.home() / ".luarocks" / "bin" / name
    return shutil.which(name) or (str(home) if home.exists() else None)


def _lua() -> str | None:
    return shutil.which("luajit") or shutil.which("lua5.1") or shutil.which("lua")


def _env() -> dict[str, str]:
    """The environment `make test-lua` gives busted: the luarocks tree on the Lua path (CI sets it already)."""
    env = dict(os.environ)
    luarocks = _tool("luarocks")
    if "LUA_PATH" not in env and luarocks:
        for var, flag in (("LUA_PATH", "--lr-path"), ("LUA_CPATH", "--lr-cpath")):
            out = subprocess.run([luarocks, "--lua-version=5.1", "path", flag], capture_output=True, text=True,
                                 check=False)
            env[var] = ";;" + out.stdout.strip()
    return env


@pytest.fixture()
def run(root: Path, tmp_path: Path):
    busted, lua = _tool("busted"), _lua()
    if busted is None or lua is None:
        pytest.skip("no busted or no Lua interpreter")

    def go(files: dict[str, str], **extra: str) -> subprocess.CompletedProcess:
        specs = tmp_path / "specs"
        specs.mkdir(exist_ok=True)
        for name, text in files.items():
            (specs / name).write_text(text, encoding="utf-8")
        env = _env() | {"LUA": lua, "BUSTED": busted, "SPECS": str(specs), "OUT": str(tmp_path / "out")} | extra
        return subprocess.run(["sh", RUNNER], cwd=root, env=env, capture_output=True, text=True, check=False)

    return go


def test_every_spec_file_runs_and_the_results_are_added_up(run):
    r = run({"a_spec.lua": PASSES, "b_spec.lua": PASSES, "shared.lua": FAILS}, JOBS="2")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "2 files, 4 successes, 0 failures, 0 errors, 0 pending" in r.stdout
    assert "the value this file got" not in r.stdout  # a file not named *_spec.lua is not a spec
    assert "slowest files" in r.stdout and "a_spec.lua" in r.stdout.split("slowest files", 1)[1]


def test_a_failing_file_is_shown_and_fails_the_run_and_the_others_still_run(run):
    r = run({"a_spec.lua": PASSES, "b_spec.lua": FAILS, "c_spec.lua": PASSES})
    assert r.returncode != 0
    assert "3 files, 5 successes, 1 failures, 0 errors, 0 pending" in r.stdout
    assert "b_spec.lua" in r.stdout and "the value this file got" in r.stdout
    assert "a passing file" not in r.stdout  # a passing file's output is not printed


def test_a_file_that_breaks_while_loading_is_an_error_that_fails_the_run(run):
    r = run({"a_spec.lua": PASSES, "b_spec.lua": BREAKS})
    assert r.returncode != 0
    assert "1 errors" in r.stdout and "this file breaks while it loads" in r.stdout


def test_a_file_that_ends_with_no_result_line_fails_the_run(run):
    r = run({"a_spec.lua": PASSES, "b_spec.lua": LEAVES})
    assert r.returncode != 0
    assert "b_spec.lua" in r.stdout and "no result line" in r.stdout


def test_a_folder_with_no_spec_file_fails_the_run(run):
    r = run({"helper.lua": PASSES})
    assert r.returncode != 0 and "no spec file" in r.stdout + r.stderr


def test_the_stats_of_each_file_are_added_up_into_one(root: Path, tmp_path: Path):
    lua = _lua()
    if lua is None or _tool("luarocks") is None:
        pytest.skip("no Lua interpreter or no luarocks")
    (tmp_path / "a.stats").write_text("3:x.lua\n1 0 2 \n2:y.lua\n0 5 \n", encoding="utf-8")
    (tmp_path / "b.stats").write_text("4:x.lua\n1 1 0 7 \n", encoding="utf-8")
    (tmp_path / "empty.stats").write_text("", encoding="utf-8")
    out = tmp_path / "all.stats"
    paths = "".join(f"{tmp_path / n}\n" for n in ("a.stats", "b.stats", "empty.stats"))
    r = subprocess.run([lua, MERGE, str(out)], input=paths, cwd=root, env=_env(), capture_output=True, text=True,
                       check=False)
    assert r.returncode == 0, r.stdout + r.stderr
    assert out.read_text(encoding="utf-8") == "4:x.lua\n2 1 2 7 \n2:y.lua\n0 5 \n"


def test_the_shares_of_a_split_run_cover_every_file_once(run):
    files = {f"{c}_spec.lua": PASSES for c in "abcde"}
    seen = []
    for k in (1, 2, 3):
        r = run(files, SHARD=f"{k}/3")
        assert r.returncode == 0, r.stdout + r.stderr
        seen += [name for name in files if name in r.stdout.split("slowest files", 1)[1]]
    assert sorted(seen) == sorted(files)
    assert "2 files, 4 successes" in run(files, SHARD="1/3").stdout  # a_spec and d_spec


@pytest.mark.parametrize("shard", ["0/3", "4/3", "x/3", "2", "1/0"])
def test_a_share_that_names_no_part_of_the_run_is_refused(run, shard):
    r = run({"a_spec.lua": PASSES}, SHARD=shard)
    assert r.returncode != 0 and "SHARD is k/n" in r.stdout


def test_a_file_on_the_plain_list_runs_without_the_coverage_hook(run, tmp_path: Path):
    if _tool("luacov") is None:
        pytest.skip("no luacov")
    files = {"a_spec.lua": PASSES, "b_spec.lua": PASSES}
    plain = tmp_path / "plain.txt"
    plain.write_text(f"# walks the whole data set\n{tmp_path / 'specs' / 'b_spec.lua'}\n", encoding="utf-8")
    r = run(files, COVERAGE="1", PLAIN=str(plain))
    assert r.returncode == 0, r.stdout + r.stderr
    assert "2 files, 4 successes" in r.stdout  # the plain file still runs and still counts
    stats = {p.name for p in (tmp_path / "out").glob("*.stats")}
    assert len(stats) == 1 and "a_spec" in next(iter(stats))
