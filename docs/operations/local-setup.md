# Runbook: Local setup

> Get the addon and pipeline toolchain running, and know what each `make` target does.

## Goal

A clean checkout where `make lint`, `make test` and `make validate` all pass, and you know how to regenerate the shared vectors (hash and align) when a case is added, and the addon's `Data/` when `data/` changes.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Python | 3.11 or later (CI runs 3.14) | The pipeline has **no runtime dependencies**. The dev tools are pinned exactly in `pipeline/pyproject.toml` (`pytest`, `ruff`, `coverage`); bump one by editing that line. |
| Lua | 5.1 semantics: LuaJIT 2.1 (`luajit`) or PUC Lua 5.1 (`lua5.1`) | Matches WoW. Lua 5.2 and later are **not** compatible. The Makefile uses `luajit` by default; pass `LUA=<interpreter>` to use another. |
| luarocks | any recent | Used only to install the pinned rocks in `.github/lua-rocks.txt` for Lua 5.1. |
| busted, luacheck, luacov, cluacov | pinned in `.github/lua-rocks.txt` | Installed to `~/.luarocks/bin` (the user tree, `--local`), which need not be on `PATH`: the Makefile looks there too. The pin file also pins their transitive rocks. |
| C compiler and Lua 5.1 headers | any | cluacov is a C module and is built on install: the Xcode Command Line Tools on macOS (`xcode-select --install`), `build-essential` on Linux. |
| GitHub CLI (`gh`) | optional | Only for `make release`, `make report-intake` and cache housekeeping. |

On macOS, Homebrew has no Lua 5.1 formula, so LuaJIT is the interpreter (`brew install luajit luarocks`). The system `lua` there is a newer version and will not work.

### Python

From the repository root:

```sh
python3 -m venv .venv && .venv/bin/pip install -e "pipeline[dev]"
```

The Makefile uses `.venv/bin/python` automatically when it exists, and `python3` otherwise (CI installs the dev tools itself). It finds the venv of the main checkout from every git worktree too, so create it once. Some system Pythons are "externally managed" and refuse `pip install`; the venv avoids that. Never use `--break-system-packages`.

### Lua toolchain

```sh
LUAROCKS="luarocks --lua-version=5.1 --local" .github/scripts/lua-rocks.sh install
# macOS with LuaJIT:
LUAROCKS="luarocks --lua-version=5.1 --local --lua-dir=$(brew --prefix luajit)" .github/scripts/lua-rocks.sh install
# if luarocks can't find the headers, prefix the command with:
#   LUA_INCDIR=$(brew --prefix luajit)/include/luajit-2.1
```

`lua-rocks.sh install` installs every pin in `.github/lua-rocks.txt` (busted, luacheck, luacov, cluacov and their dependencies) at its exact version, in file order, then runs `verify`. A pin that is already the only installed version of its rock is skipped, so a re-run downloads nothing and resumes where a failed run stopped. A rock with another version beside it is reinstalled, which repairs a mixed tree. A failed pass is retried once after `LUA_ROCKS_RETRY_DELAY` seconds (default 10).

`lua-rocks.sh verify` checks an existing tree without installing: it compares `luarocks list --porcelain` to the pins and fails naming anything extra, missing or at another version. Because `install` ends in `verify`, a tree that also holds rocks from another project installs the pins and then exits non-zero naming the extras.

### Bumping a Lua rock

1. Edit the version on that rock's line in `.github/lua-rocks.txt`. A new transitive dependency gets its own line after the rocks it needs (the file is in dependency order).
2. Run `lua-rocks.sh install` as above, then `make test` and `make lint`.
3. CI's toolchain cache key hashes `.github/lua-rocks.txt`, `.github/scripts/lua-rocks.sh` and `.github/actions/lua-toolchain/action.yml` (plus the runner image), so the next run rebuilds and reinstalls once and saves a new cache.

The Lua and luarocks versions CI uses are the inputs of `.github/actions/lua-toolchain/action.yml` (`lua-version`, `luarocks-version`, with defaults) and are part of the same cache key.

**A broken toolchain cache** (the PATH step or `verify` fails on a cache hit with unchanged pins, for example a truncated archive): nothing rebuilds on its own, because the key still matches. Delete it and the next run rebuilds: `gh cache list --key lua-toolchain-`, then `gh cache delete <key>`.

## Make targets

`make help` lists everything. Overrides: `LUA=`, `BUSTED=`, `LUACHECK=`, `LUACOV=`, `LUAROCKS_BIN=`, `PY=` (an absolute path: the recipes `cd` into `pipeline/` first).

### Everyday

| Target | Runs |
|---|---|
| `make test` | `test-py` + `test-lua` + `luac` |
| `make test-py` | pytest over `tests/python` |
| `make test-lua` | busted over `tests/lua`, under `$(LUA)` |
| `make luac` | every addon Lua file (the generated `Data/` shards included) must load |
| `make coverage-py` | pytest under coverage.py; fails below `COV_PY_MIN` percent of the pipeline's lines |
| `make coverage-lua` | busted under luacov; fails below `COV_LUA_MIN` percent of the addon's logic lines (generated `Data/` excluded) |
| `make lint` | `lint-py` + `lint-lua` + `lint-core-gate` + `lint-no-english-in-addon` + `lint-public` (which includes the private-paths check) |
| `make lint-py` | `ruff check` over `pipeline/` and `tests/python` |
| `make lint-lua` | `luacheck addon/WoWForeverJapanese tests/lua` |
| `make lint-core-gate` | fails on any `CreateFrame(`, `_G[`, `GameTooltip`, `QuestInfo`, `QuestLog` or `GossipFrame` under `Core/`: rendering stays apart from data ([Principles §8](../architecture/principles.md#8-rendering-apart-from-data), [Addon modules](../architecture/addon-modules.md)) |
| `make lint-no-english-in-addon` | fails on any `data/english` reference under `addon/` ([ADR-002](../adr/002-live-english-only.md)) |
| `make lint-no-private-paths` | fails if a tracked file is a symlink, or sits under a path of the "Private project internals" block of the checkout's `.git/info/exclude` (the ignore list git never publishes; `.gitignore` holds no private path) |
| `make lint-public` | `wfj public-check all`: no path on the author's machine in tracked files, nothing the private rules name (when the checkout has a rules file, [ADR-047](../adr/047-public-repository-hygiene.md)); code comments explain rather than record history; every relative link resolves |
| `make vectors` | regenerates the Python ↔ Lua contract vectors (hash, align, report); see below |
| `make toc-check` | the TOC's `## Interface` matches `pipeline/clients.toml` |

### Data

| Target | Runs |
|---|---|
| `make check` | `wfj check --report`: the status rules over `data/` (writes `status`, `reasons`, `checks`, `english`) and the yield report. Idempotent, a few seconds |
| `make stats` | the same report, no writes; per type it includes `shipped by provenance: human N · correction N · machine N`. `wfj stats --stale <file.jsonl> [--dump <SavedVariables>]…` writes the shipped quest lines that are `stale` or whose English differs across sources; `wfj stats --delta <git ref> [--capture <file.jsonl>]` prints what `data/english/` gained, lost or changed since the ref |
| `make generate` | `data/` → `addon/WoWForeverJapanese/Data/` (`Meta.lua`, `Vectors.lua`, the per-type shards, `Reading/`, `Gloss/`) and the TOC's generated block. Deterministic: a rerun is a byte no-op, unchanged files are not rewritten, emptied shards are deleted. Run it after any `data/` change and commit the result with the data |
| `make validate` | `wfj validate $(VALIDATE_FLAGS)` then `luac`: the CI gate. Schema, the provenance rule, English hash collisions, referential integrity, regenerate-and-diff of `Data/` and the TOC block, no unknown player placeholder on a shipped line, UI strings that keep their English specifiers, colour codes and line breaks and are unambiguous, and the readings. `VALIDATE_FLAGS="--base origin/main"` adds the check that no human line became machine (CI passes it on pull requests) |
| `make coverage` | how much of the game ships in Japanese → [Coverage](coverage.md). Run it before every pull request that changes `data/`; a test fails while the committed file is out of date |
| `make import-draft DRAFT=<file.jsonl> TYPE=<type> NAME=<draft name> MODEL=<model id> [CRITIC=<model id>] DATE=<YYYY-MM-DD> [REVERIFY=1]` | merges machine-drafted text into `data/<type>/` as `machine` variants; never edits a `human` or `correction` variant. See [Machine drafts](#machine-drafts) |
| `make import-collector DUMP=<file>` | adds one player's collector dump (a SavedVariables file at hand) to `data/english/`, replacing stand-in English with what the Forever client showed. The path may contain spaces. See [Collector dumps](#collector-dumps) |
| `make collector-intake ISSUE=N [BODY=<saved issue body>]` | a player's collector send (a `collector-send` issue): reads the string or the attached file and imports it with the same rules: [Collector sends](collector-sends.md) |
| `make report-intake ISSUE=N` / `make report-apply ISSUE=N MODEL=<model id>` | a player's fix report: [Fix reports](fix-reports.md) |

### Import and client tooling

These need the import inputs ([Import inputs](#import-inputs)) or an installed Forever client. A clean checkout does not: `data/` is committed.

| Target | Runs |
|---|---|
| `make data` | `import` → `check` → `generate`. Rebuilds the imported text of `data/` from the pinned inputs. Corrections, machine drafts, rulings and prior English baselines are carried ([ADR-012](../adr/012-human-decisions-survive-regeneration.md), [ADR-014](../adr/014-machine-drafted-text-and-ui-dictionary.md)), so a line whose English changed comes out `stale` |
| `make import` | `wdb-preflight` (every client, before anything is written), then one `wfj import predecessor` pass with the lineage files, then the shared English (pfQuest, VMaNGOS), then per client in `CLIENTS` order (`classic-era`, then `forever`) the quest cache, ids, client text and UI strings, all merged. The later client wins where it has a line. Last, `import-served` drops the English for ids no Forever build has served, so Classic Era-only content is not generated ([ADR-034](../adr/034-forever-is-the-only-target.md)). It is additive: an id an earlier Forever build served keeps its English, and the step records every served id in `pipeline/served/<kind>.tsv` ([ADR-050](../adr/050-english-is-additive.md)); the Japanese stays in `data/` |
| `make import-english` | only the English imports: refreshes `data/english/` and leaves `data/` lines (rulings, prior hashes) alone; `make check` then derives the same `stale` lines a full `make data` does |
| `make import-served` | the last step of `import` / `import-english`, runnable alone. Updates the served record `pipeline/served/<kind>.tsv` and prints, per kind, how many ids an earlier build served that this build did not (their English is kept). Refuses, writing nothing, on a missing input, unstamped or mixed-stamp CSVs, a cache of another build, or a kind that would lose every line |
| `make rebuild-check` | the rebuild proof: deletes `data/english/**/*.jsonl`, runs `make data`, and fails, listing the changed files, if anything under `data/` or the addon differs from `HEAD`. Refuses on uncommitted changes to `data/`, the addon, `pipeline/` or the `Makefile`, or a missing shared input |
| `make tables-extract WOW_DIR=<client folder> [CLIENT=forever] [HOTFIXES=<path>\|HOTFIXES=]` | reads the client tables (`ItemSparse`, `SpellName`, `Spell`, `GlobalStrings`, `ItemSubClass`, `SpellItemEnchantment`, `QuestV2`, `ItemEffect`, `ItemXItemEffect`) from the installed client's local archive, with its hotfix cache applied, into the client's input folder as CSVs, and stamps them `db2@<build>` ([ADR-021](../adr/021-client-tables-from-the-local-archive.md)). Read-only on the game folder, no network, all or nothing. Refuses an install of another build than the client's pin |
| `make wago-fetch CLIENT=classic-era` | downloads the same tables from wago.tools at the Classic Era build and stamps them `wago@<build>`. All or nothing. Refuses a client pinned to `db2` tables unless `CLIENT_DIR=<elsewhere>` (the cross-check form) |
| `make wdb-copy WOW_DIR=<client folder> [CLIENT=forever]` | copies the client's quest cache (`Cache/WDB/enUS/questcache.wdb`) into the client's input folder after checking its build against the pin; keeps the previous copy as `.prev`. Read-only on the game folder ([ADR-020](../adr/020-quest-cache-harvest.md)) |
| `make wdb-preflight` | the first step of `import` / `import-english`: for every client, the quest cache and the QuestV2 / Spell / ItemEffect CSVs must exist, the cache must decode and the table stamps must match the pins. Nothing is written |
| `make served-columns WOW_DIR=<client folder> [LISTFILE=<community listfile>]` | regenerate `pipeline/served_columns.txt`, every text column of every client table the install ships plus its server caches, and print what the build added, dropped or changed. Tables are named through the community listfile (default `$(INPUTS)/community-listfile.csv`). Give each new column a disposition in `pipeline/served_dispositions.txt`; commit both. Read-only, no network ([ADR-052](../adr/052-coverage-by-served-data.md)) |
| `make level1-spells WOW_DIR=<client folder>` | regenerate `pipeline/level1_spells.txt` (the spells a fresh level-1 character has) from the installed client; commit the result |
| `make ui-inventory` / `make forever-addons` / `make forever-titles` | from a Forever UI extract: the UI strings each hooked surface can show (`pipeline/ui_inventory.txt`) and every other string a loaded file of a translated addon names (`pipeline/ui_loadset.txt`, the load-set sweep), every Blizzard addon and its load state (`pipeline/forever_addons.txt`), and every `SetTitle(` call site. Commit the generated files; tests read them |
| `make forever-table-counts WOW_DIR=<client folder>` | row counts of the client tables behind windows with no content on Forever; re-run per build |

`python -m wfj.dev.client_ui --wow "<World of Warcraft folder>" --product wow_classic_beta --out <dir> --listfile <id;path csv>` extracts the interface files (FrameXML, `Blizzard_*`) from a local install, read-only. The path list must include every addon's `.toc` for `make forever-addons` to resolve load sets. `python -m wfj.dev.client_surface` builds the list of client names the addon depends on and the `WFJProbe` addon that checks them in game.

### Release

| Target | Runs |
|---|---|
| `make package` | a rehearsal of the next release on this machine: clones the committed `HEAD` into `build/package-src`, cuts the changelog and tags there, runs the pinned BigWigsMods packager (downloaded once into `build/`), runs `wfj package-check`, and copies the zip to `build/`. Nothing is pushed or uploaded; uncommitted changes are not included. Needs bash 4 or later (macOS ships 3.2: `brew install bash`, or pass `PACKAGER_BASH=`). Log: `build/package.log`. [Release → Dry run](release.md#dry-run) |
| `make release [VERSION=x.y.z]` | starts the Release workflow on `main` with the GitHub CLI and follows it to the end. Needs `gh`, signed in, with write access. [Release](release.md) |

## Config files

- `.luacheckrc`: `std = lua51`; `read_globals` is the Blizzard API allow-list. **Calling a new Blizzard API means adding it here**, so every new API surface is a reviewable diff. `bit` is deliberately absent, so any `bit.*` use fails lint. `Data/` is ignored; `tests/lua` adds the `+busted` std.
- `.busted`: `ROOT = tests/lua/spec`, pattern `_spec`.
- `pipeline/pyproject.toml`: ruff line length 110, target Python 3.11; pytest `testpaths = ../tests/python`.

## Regenerating the shared vectors

Three Python ↔ Lua contracts are committed as vector pairs; `make vectors` regenerates them all.

- **Hash**: the cases live in `pipeline/wfj/dev/gen_vectors.py` (`CASES`) and are written as `vectors/hash_vectors.jsonl` (read by pytest) and `vectors/hash_vectors.lua` (read by busted). `wfj generate` ships a third copy, `addon/WoWForeverJapanese/Data/Vectors.lua`, which `/wfj debug hash` checks in the client.
- **Align**: `pipeline/wfj/dev/gen_align_vectors.py` → `vectors/align_vectors.{jsonl,lua}`, run by busted against `Core/Align.lua`. A test also checks that `Align.ALLOWLIST` in `Core/Align.lua` equals `pipeline/allowlist.txt`: add a term to both.
- **Report**: `pipeline/wfj/dev/gen_report_vectors.py` → `vectors/report_vectors.{jsonl,lua}`, the fix-report text format both sides read and write.

Drift tests regenerate each pair in memory and fail if the result differs from the committed files. To add a case: append to `CASES`, run `make vectors` (and `make generate` for the hash case, which ships), and commit the regenerated files.

## Import inputs

`data/` is **committed**, so a clean checkout needs none of this. The import is re-run only when an input changes. To re-run it, put the inputs under `<repo>/predecessors/` (ignored by git; the Makefile default is `INPUTS=<checkout>/predecessors`; a worktree that has no `predecessors/` of its own reads the main checkout's, found through `git rev-parse --git-common-dir`, and `INPUTS=` on the command line overrides either) or override the variables. `IMPORT_DATE` is written into every line's `provenance.imported`; bump it only when the inputs change, so a rerun on another day stays byte-identical.

**Per-client inputs.** `make import` merges the English of every client in `CLIENTS` (`classic-era forever`, oldest first). Each client's inputs live in `predecessors/clients/<client>-<build>/`, named by the build pinned in the `Makefile` (`<client>_BUILD`, with `<client>_SRC` the table source and `<client>_PRODUCT` the install's product). The shared inputs stay at the `predecessors/` root, and so do the Forever UI extracts, one folder per build.

```
predecessors/
├── clients/
│   ├── classic-era-1.15.9.69722/   wago tables (stamped wago@1.15.9.69722), questcache.wdb, missing.txt
│   └── forever-1.60.1.70170/       db2 tables (stamped db2@1.60.1.70170), questcache.wdb, missing.txt
├── classic-wow-quest-japanese-translator/  classic-wow-tooltips-japanese-translator/  lineage/
└── pfquest-quests.lua  vmangos/  forever-ui-1.60.1.70170/
```

Staging a client folder (the preflight refuses the import until every client's folder is complete):
- **Tables:** `make tables-extract CLIENT=forever WOW_DIR=<client folder>` (a `db2` client) or `make wago-fetch CLIENT=classic-era` (a `wago` client). Use the one that matches the client's pinned source; the other refuses or writes a stamp the preflight refuses.
- **Quest cache:** `make wdb-copy CLIENT=<client> WOW_DIR=<client folder>` after a scan. The cache cannot be downloaded: its content depends on scan history. The committed `data/english/quest` was built from the Classic Era cache (build 1.15.9.69722, sha256 `a10d1d9b50a6bc724383519338b8c109cdc3b59b14defee585b70495480ec763`) and the Forever cache (build 1.60.1.70009, sha256 `b3e110161e30d5a07c31df154002b445d8ef9f1430f51f77b4a8528f744e5885`); without those files nobody can rebuild `data/english/quest` byte for byte.
- `missing.txt` is written by the cache import; nothing to stage.

`CLIENT` (default `forever`) picks the client for the single-client targets (`wago-fetch`, `tables-extract`, `wdb-copy`). The per-client knobs (`WAGO_BUILD`, `WDB_BUILD`, `TABLES_SRC`, `WDB_QUEST`, `WAGO_QUESTV2`, `CLIENT_DIR`, `PRODUCT`, …) derive from `CLIENT`; pass them on the command line only to a single-client target. `make import`, `import-english`, `data` and `rebuild-check` refuse them, because a value would apply to every client. A new client build is a `Makefile` change (bump `<client>_BUILD`, stage the new folder), committed with the regenerated data.

**Source stamp.** Each client folder's CSVs carry `tables-source.txt`, one `<table> <src>@<build>` line per table, written only by `make tables-extract` and `make wago-fetch`. The preflight stops the import when a CSV has no stamp or a stamp other than its client's pins. CSVs downloaded by hand need one too: `python -m wfj.dev.tables_stamp write --dir <client folder> --src wago --build <build> <Table> …`.

| Input | Where it comes from | Makefile variable |
|---|---|---|
| Predecessor quest and tooltip addons | the two earlier "Classic … Japanese Translator" repositories, cloned into `predecessors/` (not public). Last imports at `3446c82` and `84db736` | `PRED_QUEST`, `PRED_TOOLTIP` |
| pfQuest English quests (`db/enUS/quests.lua`, MIT) | `curl -L -o predecessors/pfquest-quests.lua https://raw.githubusercontent.com/shagu/pfQuest/7786596/db/enUS/quests.lua` (pinned commit `7786596`) | `PFQUEST`, `PFQUEST_SHA` |
| VMaNGOS world database (`mangos.sqlite`, GPL-2.0): quest progress and completion, gossip, NPC speech and book English | the `vmangos/core` release `db_latest`, asset `db-sqlite-13b49dc.zip`: `gh release download db_latest -R vmangos/core -p 'db-sqlite-*.zip'`, unzip, move `sqlite-dump/mangos.sqlite` to `predecessors/vmangos/mangos.sqlite`. `db_latest` moves: when the asset's sha differs from `VMANGOS_SHA`, bump the pin in the same PR as the regenerated data | `VMANGOS_DB`, `VMANGOS_SHA` |
| QuestJapanizer 0.5.8 (`QuestData.lua`) | CurseForge project 15442, file 395901: `curl -L -o predecessors/lineage/QuestJapanizer-0.5.8.zip https://www.curseforge.com/api/v1/mods/15442/files/395901/download`, then `unzip -d predecessors/lineage/qjp` | `QJP`, `QJP_VERSION` |
| CraftJapanizer_Quest 2012031300 (`CraftJapanizer_QuestData.lua`) | CurseForge project 23293, file 580134: `…/mods/23293/files/580134/download`, then `unzip -d predecessors/lineage/cjq` | `CJQ`, `CJQ_VERSION` |
| Client tables | `make tables-extract` (Forever) or `make wago-fetch` (Classic Era), above. Only the UI keys in `pipeline/ui_keys.txt` are imported from `GlobalStrings`; only stat lines ("+3 Fire Spell Damage") become `SpellItemEnchantment:<ID>` keys | `WOW_DIR`, `HOTFIXES`, `<client>_SRC`, `<client>_BUILD`, `CLIENT_SPELL` (Spell.csv), `CLIENT_ITEMEFFECT` (ItemEffect.csv) |
| Quest cache `questcache.wdb` (quest title, objectives, description, objective and area text) | the client's `Cache/WDB/enUS/questcache.wdb` after a quest scan and a full **Exit Game** (the client does not write it on logout): `make wdb-copy`. The payload layout is pinned per build in `io/wdb.LAYOUTS`; a build with no pinned layout is refused (`python -m wfj.dev.wdb_layout <cache>` says which layout reads it) | `WDB_QUEST`, `WDB_BUILD`, `WDB_MISSING` |
| Forever UI extract and GlobalStrings | the `client_ui` extract under `predecessors/forever-ui-<build>/`, and the Forever client folder's `GlobalStrings.csv`. Needed only for `make ui-inventory`, `forever-addons` and `forever-titles` | `FOREVER_UI`, `FOREVER_GLOBALSTRINGS` |

```sh
make import                                       # every client, defaults above
make import PFQUEST_SHA=<sha> VMANGOS_SHA=<sha>   # re-pin a shared input
make tables-extract WOW_DIR="<Forever client folder>"
make wago-fetch CLIENT=classic-era
make wdb-copy CLIENT=forever WOW_DIR="<Forever client folder>"
make import-english                               # every client's English, labelled by its pins
make rebuild-check                                # prove a clean rebuild gives back HEAD's data/ and addon
```

`<Forever client folder>` is the Forever folder inside `<World of Warcraft folder>` (`_classic_beta_` during the beta).

**Wiki-only translations.** Some quest descriptions exist complete only on the QuestJapanizer wiki. The wiki is not fetched: its terms leave reuse to its administrator ([ADR-011](../adr/011-provenance-layers-and-completeness.md)).

The source tags in `data/` (`cqjt@<sha>`, `ctjt@<sha>`, `qjp@<version>`, `cjq@<version>`, `pfquest@<sha>`, `vmangos@<sha>`, `wdb@<build>`, `wago@<build>`, `db2@<build>`) come from these pins. A rerun on the same inputs, the same quest cache files included, is byte-identical (`git status` clean afterwards); `make rebuild-check` proves it. `import predecessor` prints what it carried from the store it rebuilt: corrections, ruled variants and English baselines per type. `not carried: quest: N orphaned rejects` means a `reject`-ruled variant whose line the inputs no longer produce.

## Collector dumps

Players send what their game recorded from the game itself, in a `collector-send` issue; take those with `make collector-intake ISSUE=N` ([Collector sends](collector-sends.md)), which ends in the same merge as below. This section is for a SavedVariables file at hand. In game, `/wfj collector path` prints where it is: `<World of Warcraft folder>/<client folder>/WTF/Account/<ACCOUNT>/SavedVariables/WoWForeverJapanese.lua` (`_classic_beta_` as the client folder on the beta). It is not committed.

```sh
make import-collector DUMP="<path to WoWForeverJapanese.lua>"
```

The path may contain spaces (the SavedVariables folder of a default install does); quote it.

Lines are tagged `collector@<client build>`. Entries that fail validation are counted by reason and not written. What the Forever client showed is the English ([ADR-053](../adr/053-forever-shown-english-is-the-english.md)): a recorded line replaces a stand-in (pfQuest, VMaNGOS, an older client's quest cache or tables), and a literal class or race word the stand-in has where the dump wrote `$C` / `$R` is put back. A line from the same client's own tables or quest cache is kept and listed under `differs from the client's own files (kept)`. `check` consults collector quest and gossip English, so an import can change those lines' hashes and statuses: run `make check` after it and review the delta before committing. Item and spell collector English is stored but not consulted. Running `make import-english` again replaces collector lines for any (id, field) pfQuest or VMaNGOS provides, so import the dumps again after it ([Collector](../systems/collector.md)).

## Machine drafts

Machine-drafted text ([ADR-014](../adr/014-machine-drafted-text-and-ui-dictionary.md)) enters `data/` only through `make import-draft`. A draft is a JSONL file, one row per entry, exactly `{"id": …, "field": …, "ja": …}`. UI keys are strings such as `"ACCEPT"`; quest, item, spell, book and objective ids are integers; a gossip id is the 16-hex gossip key (`/wfj debug gossip` prints it for each open line) with field `text`.

```sh
make import-draft DRAFT=<file.jsonl> TYPE=ui NAME=<draft name> MODEL=<model id> DATE=<YYYY-MM-DD>
make check && make generate && make validate
```

Provenance is `{"class": "machine", "model": …, "critic": …?, "source": "draft-<NAME>@<DATE>", "imported": <DATE>}`. Pass `CRITIC=` only when a second model actually reviewed the draft. Re-importing a draft with the same `NAME` replaces that draft's earlier text; a different `NAME` adds a competing variant. A machine variant never wins a line that has a `human` or `correction` variant, unless it carries an `accept` ruling or every hand-written variant on the line carries a `reject` ruling ([ADR-023](../adr/023-server-only-text-drafted-in-measured-batches.md)). The full batch flow, with the lint and the word lists: [Translation batches](translation-batches.md).

For `ui`, a new key is first listed in `pipeline/ui_keys.txt` (curation rules in its header), then `make import-english`, then drafted. Keep every format specifier (`%s`, `%d`, `%.1f`, `%1$s` when Japanese word order moves an argument), every colour code (`|cAARRGGBB` … `|r`) and line break, and keep two whitespace-adjacent text captures in their English order. A `|4singular:plural;` group may be dropped.

Enchantment stat lines are not drafted row by row: `python -m wfj.dev.enchant_drafts <client folder>/SpellItemEnchantment.csv <phrases.tsv> > <draft.jsonl>` builds one row per `SpellItemEnchantment:<id>` from a phrase table (`<English words>\t<Japanese label>`; "+3 Fire Spell Damage" → `炎呪文ダメージ +3`). A stat line whose words are not in the table fails the run by name.

To replace a machine line by hand, add a correction (below) with `"corrects": "draft-<NAME>@<DATE>"`.

## Ruling on conflicts

`make check` leaves a line `rejected` with `duplicate_conflict` when zero or several of its variants pass the rules. To resolve one by hand:

1. Find the line in `data/<type>/<type>-NNNN.jsonl` (`NNNN` = `id // 1000`, zero-padded). The line's own `ja` is one variant; each object in `conflicts` is another.
2. Add a ruling to the variant you want shipped, on the line itself or on the conflict entry: `"ruling": {"ruling": "accept", "by": "maintainer", "date": "YYYY-MM-DD"}`. (`"reject"` excludes a variant instead. Accept exactly one: two accepts leave the line rejected.)
3. `make check`. The accepted variant is promoted into the line and the displaced one moves into `conflicts`; nothing is deleted. The accepted variant still has to pass the rules: a ruling picks the variant, it does not override alignment. `make check` refuses to run when `data/english/<type>` is empty while `data/<type>` is not (a partial checkout would otherwise reject the whole corpus as `no_english_id`).
4. `make generate`, then commit the data with the regenerated `Data/`, stating the provenance delta in the PR. A ruling survives `make import` and `make data` ([ADR-012](../adr/012-human-decisions-survive-regeneration.md)).

## Hand corrections

A correction is a variant a person wrote: the translation is right but a name is misspelled (so `alignment_failed` rejects it), or the text needs a fix, including replacing a machine draft. It is carried across `make data` and ranks first in the tie-break ([ADR-012](../adr/012-human-decisions-survive-regeneration.md)).

1. Find candidates: `python -m wfj.dev.list_name_typos [--cutoff 0.7] [--context 30]` lists rejected quest variants whose only failures are near-miss names, with context. A candidate is not a fix: read each against the English. A plural the checker misses (`Missionary` / `Missionaries`), a zone the English shortens, a name the English never uses, or a typo in the English itself (`Quatermaster`) is not a typo in the translation.
2. Append the corrected variant to the line's `conflicts` (the line's own text can stay):

   ```json
   {"ja": "<corrected Japanese>", "provenance": {"class": "correction", "translator": "Az", "source": "correction@2026-09-14", "imported": "2026-09-14", "corrects": "qjp@0.5.8", "note": "Thistle bore → Thistle Boar"}}
   ```

   `translator` and `corrects` are required (`check` and `validate` fail without them, in `conflicts` too). `translator` names who wrote the Japanese; for a name fix, the corrected variant's translator, exactly (CI checks that `corrects` + `translator` name a variant on the line). `source` is `correction@<YYYY-MM-DD>`; `corrects` is the `source` of the variant being corrected; `note` says what changed. For an item or spell, copy the corrected variant's `extra` too. One correction per line: to change a correction, edit it, because a second passing correction ties with the first and the line stops shipping. An `accept` ruling on another variant outranks a correction; remove it.
3. `make check`. A passing correction is promoted into the line. The rules still apply: a correction that fails alignment or completeness does not ship, and a test requires every committed correction to be its line's shipping variant, so fix or remove a failing one before committing. A correction is judged by the layer it `corrects`, so fixing a name in a first-paragraph-only variant keeps it under the truncation rule.
4. `make generate`, then commit the data with the regenerated `Data/` (corrections are their own provenance class in the PR's delta).

An edit to an imported line's `ja` that is **not** marked `correction` is overwritten by the next `make data`.

## Repo layout

```
addon/WoWForeverJapanese/   WoWForeverJapanese.toc (hand-maintained outside the generated block) · Core/ (lookup, state,
                            settings; never touches a frame) · UI/ (one module per surface or window) · Main.lua ·
                            Bindings.xml · Data/ (generated by `make generate`) · Fonts/ · Media/
pipeline/wfj/               core/ (pure rules: normalize, hashing, align, status, readings, …) · io/ (readers: stores,
                            Lua, wago, VMaNGOS, quest cache, the client's archive) · emit/ (schema, Lua writer) ·
                            cmd/ (the `wfj` verbs) · dev/ (maintainer tools: batches, inventories, fixtures, vectors)
pipeline/*.txt, *.tsv       curated lists: allowlist, ui_keys, ui_exclusions, not-names, glossary, name lists, and the
                            generated inventories (ui_inventory, forever_addons, served_columns, …) with
                            their hand-written decisions (served_dispositions, …)
pipeline/served/            the served record, one <kind>.tsv per kind: every id a Forever build served (written by
                            the served step, committed)
data/                       SCHEMA · one folder per type (checked lines with provenance) · english/ · reading/
vectors/                    the Python ↔ Lua contract vectors (hash, align, report)
tests/                      python/ · lua/spec/ · fixtures/ (small excerpts of real inputs, cut by dev/cut_*.py, and a
                            labelled alignment sample)
```

## Verify

- `make lint`: luacheck reports `0 warnings / 0 errors`; `lint-core-gate: ok`; `lint-no-english-in-addon: ok`; ruff and `public-check` clean.
- `make test`: pytest and busted pass; `luac: ok` over every addon file, generated shards included.
- `make validate`: `validate: provenance rule skipped (no --base)`, then `validate: ok (N shipped lines; base=none)` and `luac: ok`. With `VALIDATE_FLAGS="--base origin/main"` the provenance rule runs too.
- `make generate` on a clean tree writes 0 files and `git status` stays clean.

## Rollback / troubleshooting

| Symptom | Fix |
|---|---|
| `busted: command not found` | `export PATH="$HOME/.luarocks/bin:$PATH"`, or pass `BUSTED=/path/to/busted`. |
| busted complains about the interpreter or Lua version | It must run under Lua 5.1 semantics: `LUA=luajit` (the default) or `LUA=lua5.1`. Newer Lua versions are not compatible. |
| `No module named pytest` / `ruff` / `coverage` | The venv is missing: `python3 -m venv .venv && .venv/bin/pip install -e "pipeline[dev]"` from the repository root. |
| luarocks install fails on missing headers | Re-run with `LUA_INCDIR=$(brew --prefix luajit)/include/luajit-2.1` (macOS), or the include folder of your Lua 5.1. |
| A vector drift test fails after editing a `gen_*vectors.py`, `core/align.py` or `allowlist.txt` | `make vectors` and commit the vector files; `make generate` for the shipped `Data/Vectors.lua`. If the allowlist changed, mirror it in `Align.ALLOWLIST`. |
| `make validate` reports `regenerate: … differs from a regeneration` or a TOC block difference | A generated file or the TOC markers were edited by hand, or `data/` changed without a regeneration. Run `make generate` and commit; never patch `Data/` directly. |
| `collector_dump_spec` fails after changing `Core/Collector.lua` or a surface's record call | The committed SavedVariables fixture drifted. If the change is intended, `WFJ_WRITE_FIXTURES=1 make test-lua` and commit `tests/fixtures/collector/WoWForeverJapanese.lua`. |
| `make validate` reports `placeholders: <type> <id>/<field> ships unknown token(s) {…}` | A shipped `ja` carries a `{word}` the addon does not expand. Fix the token as a correction (tokens are case-sensitive), or teach the addon the new token: its expansion in `Placeholders.expand` and its name in `KNOWN` in `Core/Placeholders.lua` and `pipeline/wfj/core/placeholders.py` (a test checks the two lists match), and strip it in both name checks (`stripPlaceholders` in `Core/Align.lua`, `PLACEHOLDER` in `core/align.py`). |
| `make validate` reports `ui <KEY>: specifiers differ from the English (…)` or `ui ambiguous: A, B share the English …` | A UI draft changed a format specifier, or two keys with the same English were drafted differently. Fix the draft (or add a correction); `make import-draft`, `make check`, `make generate`. |
| `make check` rejects `markup_changed:<detail>`, or `validate` reports `markup differs from the English` / `adjacent_captures_reordered` | The Japanese dropped or altered a colour code, `\|r` or line break, has a malformed `\|4` group, or swapped two captures the English separates only by whitespace. Fix the draft so the markup matches and the captures stay in order. |
| `make import` fails `wago-ui: N listed key(s) absent or empty at <build>` | A key in `pipeline/ui_keys.txt` is not in that build's tables (renamed or removed, or the CSV is another build). Check the CSV build, then drop or rename the key. |
| `make import` fails on the vmangos step | `mangos.sqlite: not a file`: fetch it (Import inputs). `no table 'quest_template'` or `lacks column(s)`: the file is not the VMaNGOS world database or its schema changed; nothing is written. `--commit must be a 7–40 hex commit`: `VMANGOS_SHA` is not the asset's sha. |
| `make import` fails in the preflight: `no quest cache at …` / `no QuestV2 at …` / `no Spell / ItemEffect CSV` | That client's folder is incomplete: `make wdb-copy` or `make tables-extract` / `make wago-fetch` for it. |
| `wdb: N quest(s) with wdb@<build> English are not in <file>` | The cache is smaller than the one already imported at this build (a wiped cache, the wrong install). Copy the right one (the `.prev` file holds the previous copy). `--allow-shrink` on `wfj import english wdb` deletes those quests' English on purpose. |
| `wdb: questcache.wdb is build N, --build is …` or `questcache.wdb: quest <id>: …` | The cache is another build than the pin, or its layout differs. Copy the right cache, or bump `<client>_BUILD`; a new layout needs `io/wdb.py` updated first ([ADR-020](../adr/020-quest-cache-harvest.md)). |
| `tables-stamp: <csv>: no source stamp …` or `stamped <src>@<build>, the import was told …` | The CSV was copied by hand, a fetch was cut off, or it came from another source or build than the pins. Nothing was written. Re-run `make tables-extract` or `make wago-fetch` for that client, or fix the pin in the `Makefile`. |
| `make wago-fetch` fails `wago-fetch: <table> failed at <build>; no CSV replaced` | wago.tools does not list that build or is unreachable. Read the tables from the installed client instead (`make tables-extract`). |
| `make tables-extract` fails `client-tables: …` | Nothing was written. `no product '<x>' (have […])`: set `PRODUCT` to one listed. `truncated or unreadable` / `does not match its checksum`: the client is running or patching; exit it and retry. `layout hash X, column map verified on Y`: that table's layout changed and its column map in `io/client_tables.py` must be re-verified. A hotfix decode error: re-run with `HOTFIXES=` (archive rows only). |
| `make ui-inventory` prints `no UI extract at …` or `no GlobalStrings at …` | Extract the UI with `wfj.dev.client_ui`, or pass `FOREVER_UI=` / `FOREVER_GLOBALSTRINGS=`. |
| `make package` stops with `package: the packager needs bash 4+` | Install a newer bash (`brew install bash` on macOS) or pass `PACKAGER_BASH=<path to bash 4+>`. |

## Related

- [Release](release.md) · [Translation batches](translation-batches.md)
- [Addon modules](../architecture/addon-modules.md) · [Pipeline](../systems/pipeline.md) · [Data model](../architecture/data-model.md)

> CI note: GitHub Actions runs the same targets under PUC Lua 5.1 (`LUA=lua`), not LuaJIT: luarocks under LuaJIT cannot load the luarocks.org manifest (a 65,536-constant limit). Both interpreters behave the same for this codebase, and the shared vectors prove it on both. The toolchain is restored from a cache when the pins are unchanged; on a miss CI builds it from a clean slate, retries each install step once, runs `lua-rocks.sh install`, and saves the cache. See [Release → Every pull request](release.md#every-pull-request).
