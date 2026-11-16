# ADR-097: The tests run in parallel

- **Status:** Accepted
- **Date:** 2026-11-16
- **Deciders:** the maintainer
- **Related:** [Testing strategy](../testing/strategy.md) · [Local setup](../operations/local-setup.md)

## Context

A pull request's checks took about 17 minutes, and a full local run longer. Measured on the last run on `main`:
the `lua` job spent 16.5 minutes in `make coverage-lua`, which ran all 259 spec files in one busted process under
luacov, and the `validate` job spent 7.4 of its 10 minutes in `make coverage-py`, one pytest process.

The tests themselves were not the problem. The same Lua specs, each run in a process of its own with no coverage,
took 3 minutes in all on one machine, and four files that load the whole addon before each test (generated data
included) were half of that. On the Python side, nine tests that read the whole data store took 5.8 of the 10.6
minutes, and the whole-store plan was built again by every test file that asked for it.

## Decision

1. **Lua: one busted process per spec file, as many at once as there are cores** (`tests/lua/run-specs.sh`, called
   by `make test-lua` and `make coverage-lua`). A file fails when busted exits non-zero or prints no result line,
   and its output is printed; the run sums the results and lists its slowest five files.
2. **Lua coverage is added up.** Each process writes its own luacov file (`.luacov` reads `LUACOV_STATS`), and
   `tests/lua/merge-coverage.lua` adds them into `luacov.stats.out` the way luacov adds a run to a file it finds.
   The floor is unchanged.
3. **The test helper parses each addon file once per process** and runs the parsed chunk again for each new
   namespace. Under coverage the generated data runs with luacov's hook off: luacov's pause only stops saving, and
   its hook otherwise runs on every line of the data tables.
4. **Python: pytest-xdist** (`-n auto --dist worksteal`), a new dev tool pinned exactly in
   `pipeline/pyproject.toml`. It is set in the make targets, not in pytest's options, so a single file run by
   hand stays a plain run. Coverage measures each worker (`patch = ["subprocess"]`, coverage.py 7.10 and later)
   and `coverage combine` adds them up. The floor is unchanged.
5. **A whole-store result is computed once per run** (`conftest.shared`): the first worker computes it under a
   lock in the temp folder all the workers share and the others read it. The lock is the standard library's
   `fcntl`, so no second dependency; the project's machines and CI are macOS and Linux.
6. **The same three CI jobs**, calling the same make targets. More jobs (shards) only if one runner cannot get
   the checks to about five minutes.

## Rationale

- One process per file rather than a few large groups: the scheduler then has 259 small jobs, so the heavy files
  never sit in one slow group, and no file's state reaches another.
- pytest-xdist is the standard way to run pytest on several cores, and worksteal handles tests of very uneven
  length. Writing the same in-house was not worth it.
- Measuring coverage per process and adding it up keeps the floors as they were: no test is dropped, sampled
  or skipped to gain speed.

## Consequences

- `make test` finishes in a few minutes on a laptop, where it took over ten; CI's two test jobs run in parallel
  on the runner's cores.
- A test must not write to a fixed path another test reads: it runs beside others now. Each uses its own
  `tmp_path`.
- A checkout set up before this needs `pip install -e "pipeline[dev]"` once more for pytest-xdist.
- Rolling back is reverting the change: nothing else depends on it.
