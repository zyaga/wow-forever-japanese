# ADR-099: The checks are spread over several machines

- **Status:** Accepted
- **Date:** 2026-11-20
- **Deciders:** the maintainer
- **Related:** [ADR-097](097-the-tests-run-in-parallel.md) (this replaces its point 6) · [Testing strategy](../testing/strategy.md)

## Context

After [ADR-097](097-the-tests-run-in-parallel.md) a pull request's checks took about nine minutes. The goal is
about two. Measured on a run on `main`'s layout (three jobs):

- the `lua` job took 7.0 minutes, nearly all of it the specs under luacov's line hook;
- the `validate` job took 8.7 minutes: 4.7 in the Python tests, 2.4 in the data gate, the rest in lint and setup.

Each job already used every core of its machine, so the only time left to win inside a job was in single slow
things:

- Spec files that load the whole addon before each test take seconds a test under the coverage hook. The
  slowest, the slash command spec, ran for over two minutes as one process.
- The data gate ran its rules one after another. Four of them (the plan with regenerate-and-diff, readings,
  voice, names) read the store without needing each other and were most of its two minutes.
- One Python test ran the whole data gate again, about a minute and a half, beside the job that runs it anyway.
- A spec that walks the whole data set ran ten times slower under the hook, for code its own specs count.

A faster interpreter was tried and set aside: LuaJIT ran the specs under coverage in 131 seconds where PUC Lua
took 141, because the hook cost is per line whichever runs it.

## Decision

1. **Each check is a job of its own**: `validate` (the data gate), `lint`, `python`, `lua`, `text`. A slow
   check no longer waits behind another.
2. **The two test suites run on four machines each.** `python` passes `WFJ_SHARD=k/4`, and
   `tests/python/conftest.py` keeps that machine's share of the test files, dealt out by how many tests each
   holds. `lua` passes `SHARD=k/4`, and `tests/lua/run-specs.sh` takes every fourth entry of its sorted list.
3. **Coverage is added up in a job after them.** Each machine uploads its counts; `python-coverage` and
   `lua-coverage` combine them and hold the same floors as before. No test is dropped or sampled.
4. **A slow spec file runs in parts.** A file listed in `tests/lua/split-specs.txt` runs as several processes,
   each registering only every n-th test of the file (`tests/lua/part.lua`, a busted helper that uses the
   same `register` subscription busted's own filters use). The parts are entries of the list like any file, so
   they spread over the cores and the machines.
5. **A spec that walks the whole data set runs without the hook** (`tests/lua/whole-data-specs.txt`). A spec
   that loads the whole addon stays under it: the load paths it runs are counted nowhere else.
6. **The data gate runs its four slow rules in processes of their own** and prints what they said in rule
   order, so its output is unchanged.
7. **The Python test that repeated the whole data gate is removed.** The `validate` job is that check.

## Rationale

- More machines cost nothing in waiting time: the jobs start together, and each pays its setup beside the
  others. The repository is public, so the machine minutes are free.
- Four machines per suite, not more: past that the slowest single file or test sets the time, not the count.
- Running a file in parts keeps the spec files as they are. Cutting each into several files by hand would copy
  their setup and would have to be done again for the next slow file; a line in a list does it.
- A file is listed for parts only when each of its tests sets itself up. The addon load spec is slow too, but
  loads the addon once and walks it test after test, so it stays whole.

## Consequences

- A pull request shows thirteen checks where it showed three.
- A coverage floor now fails in the `python-coverage` or `lua-coverage` job, not in the job that ran the tests.
- `make validate` uses up to five processes for about twenty seconds on a laptop, where it used one for two
  minutes.
- A test in a file on the split list must not lean on a test before it in the same file.
- Rolling back is reverting the change: `make test`, `make coverage-py` and `make coverage-lua` run the whole
  suites on one machine as before.
