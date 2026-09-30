# Contributing

Thank you for your interest. This is a small project with one maintainer, so here is what helps most and how to
go about it.

## What is welcome

**Translation fixes.** The best way is from inside the game: click the 字 minimap button (or type `/wfj fix`),
pick the line, say what is wrong, and paste the report into a
[translation report](https://github.com/zyaga/wow-forever-japanese/issues/new?template=translation-report.yml).
A check reads the report and comments within a minute. If your own Japanese ships, you are credited in
`ATTRIBUTION.md` under the name you give (the issue and the credit are public).

**Code changes.** Open an issue first and describe what you want to change and why. Pull requests without an
agreed issue may be closed, and some ideas will be declined because they do not fit the project's
[principles](docs/architecture/principles.md) (for example, anything that hides English names, adds a
dependency, or puts stored English text in the addon).

**Bug reports.** Open an issue with the client build (bottom left of the login screen), the addon version
(`/wfj version`), and what you saw.

**Security problems.** Report them in private, as [`SECURITY.md`](SECURITY.md) describes, not in an issue.

Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).

## License

The project is GPL-2.0-or-later. By contributing, you agree that your contribution is licensed the same way
(inbound = outbound). There is no contributor license agreement.

## Setup

You need Python 3.11 or later, LuaJIT (or Lua 5.1), LuaRocks, `make` and `git`. One of the Lua rocks,
cluacov, is a C module, so you also need a C compiler and the Lua 5.1 headers (the Xcode Command Line Tools on
macOS, `build-essential` on Linux).

```bash
git clone https://github.com/zyaga/wow-forever-japanese.git
cd wow-forever-japanese
python3 -m venv .venv
.venv/bin/pip install -e "pipeline[dev]"
LUAROCKS="luarocks --lua-version=5.1 --local" .github/scripts/lua-rocks.sh install
```

The Makefile uses `.venv` automatically. The Lua rocks (busted, luacheck, luacov, cluacov) are pinned in
`.github/lua-rocks.txt` and install into your user tree (`~/.luarocks`), where the Makefile finds them. More detail, including reading data from an installed client:
[local setup](docs/operations/local-setup.md).

## Everyday commands

| Command | What it does |
|---|---|
| `make test` | pytest over the pipeline, busted over the addon logic, and a parse of every addon Lua file |
| `make lint` | ruff, luacheck, the layering and no-English-in-the-addon gates, and `wfj public-check` |
| `make validate` | the data gate: schema, provenance, key collisions, regenerate-and-diff |
| `make coverage` | how much of the game ships in Japanese, written to `docs/operations/coverage.md` |
| `make coverage-py` / `make coverage-lua` | test coverage of the pipeline and of the addon logic |
| `make data` | rebuild `data/` from the pinned inputs, then check and generate (needs the inputs, see local setup) |
| `make package` | build and check a release zip locally; nothing is uploaded |

CI runs three jobs beside each other on every pull request: `make lint`, `make coverage-py`, `make luac`,
`make toc-check` and `make validate` in one, `make coverage-lua` in another, and a small third that checks
the pull request's title, body, branch name and commits.
The two coverage targets run the same tests as `make test`, so run `make test` locally. Commit with a GitHub
noreply address; the check refuses a personal one.

## How the repository is laid out

| Path | What |
|---|---|
| `addon/WoWForeverJapanese/` | the addon. `Core/` is lookup, data and state and never touches a frame; `UI/` draws. |
| `addon/WoWForeverJapanese/Data/` | generated Lua data. **Never edit by hand**: change `data/` and run `make generate`. |
| `data/` | the source of truth: one JSON line per translated field, keyed by game ID, with provenance |
| `data/english/` | the English each line was translated from (for alignment and hashing; never shipped) |
| `pipeline/` | the Python pipeline (`wfj` command): import, check, generate, validate, readings, fix reports, release |
| `tests/` | pytest (`tests/python`), busted specs (`tests/lua`), and their fixtures |
| `vectors/` | shared test vectors that keep the Python and Lua hashing and normalizing in step |
| `docs/` | how it works and why: [overview](docs/overview.md), [principles](docs/architecture/principles.md), [decisions](docs/adr/) |

## Data and provenance

Every line in `data/` says where it came from: `human` (a person's translation), `correction` (a person's fix
of one), or `machine` (drafted by a model), plus who or what produced it and a hash of the English it was made
from. Machine text never replaces a human translation unless a ruling on that line says so, and `make validate`
checks it. If you change data by hand, add a `correction` with your name as the translator.

## Pull requests

- One topic per pull request, with a short title that says what changes.
- A change that players will notice adds a line under `## Unreleased` in `CHANGELOG.md` (CI checks this for
  changes to `addon/` or `data/`).
- Comments explain why the code is the way it is. They do not record history such as issue numbers, dates or who
  asked for something; that belongs in the pull request. `make lint` checks this.
- Screenshots help for anything you can see in the game.
