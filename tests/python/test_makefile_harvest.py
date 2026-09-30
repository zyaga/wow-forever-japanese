"""The harvest Make targets and the import order (the cache after pfQuest and VMaNGOS)."""

import re
import subprocess

import pytest


@pytest.fixture(scope="module")
def makefile(root) -> str:
    return (root / "Makefile").read_text(encoding="utf-8")


def _recipe(makefile: str, target: str) -> list[str]:
    m = re.search(rf"^{re.escape(target)}:.*\n((?:\t.*\n)+)", makefile, re.M)
    assert m, target
    return m.group(1).splitlines()


CLIENTS = {"classic-era": ("1.15.9.69722", "wago", "wow_classic_era"), "forever": ("1.60.1.70009", "db2", "wow_classic_beta")}


def _dry(root, *args: str) -> list[str]:
    r = subprocess.run(["make", "-n", "-C", str(root), *args], capture_output=True, text=True, check=False)
    assert r.returncode == 0, r.stdout + r.stderr
    return r.stdout.splitlines()


def test_clients_are_pinned_oldest_first(makefile):
    """Both clients, in merge order, each with its build, table label and product."""
    assert re.search(r"^CLIENTS\s*:=\s*classic-era forever$", makefile, re.M)
    for client, (build, src, product) in CLIENTS.items():
        assert re.search(rf"^{client}_BUILD\s*:=\s*{re.escape(build)}$", makefile, re.M), client
        assert re.search(rf"^{client}_SRC\s*:=\s*{src}$", makefile, re.M), client
        assert re.search(rf"^{client}_PRODUCT\s*:=\s*{product}$", makefile, re.M), client


@pytest.mark.parametrize("target", ["import", "import-english"])
def test_every_client_is_imported_in_order_after_the_shared_sources(root, tmp_path, target):
    """pfQuest and VMaNGOS once, then per client, oldest first, its quest cache
    (after both, so it outranks pfQuest) and its three table imports, each from that client's own folder, at its
    build and label, under union. The preflight of every client runs before the first write."""
    out = _dry(root, target, f"INPUTS={tmp_path}")
    steps = [ln for ln in out if "-m wfj import " in ln and "--dry-run" not in ln]
    verbs = [ln.split("-m wfj import ", 1)[1].split()[1 if " english " in ln else 0] for ln in steps]
    shared = (["predecessor"] if target == "import" else []) + ["pfquest", "vmangos"]
    # the served step runs last, once, after every client
    assert verbs == shared + ["wdb", "wago-ids", "client-text", "wago-ui"] * 2 + ["served"], verbs
    first_write = out.index(steps[0])
    for client in CLIENTS:
        assert any("--dry-run" in ln and f"/clients/{client}-" in ln for ln in out[:first_write]), client
    for n, client in enumerate(CLIENTS):
        build, src, _ = CLIENTS[client]
        folder = f"{tmp_path}/clients/{client}-{build}/"
        for ln in steps[len(shared) + 4 * n: len(shared) + 4 * (n + 1)]:
            assert f"--build {build}" in ln and "--merge union" in ln, ln
            assert folder in ln and "/clients/" not in ln.replace(folder, ""), ln
            if " wdb " not in ln:
                assert f"--src {src}" in ln, ln


@pytest.mark.parametrize("target", ["import", "import-english"])
def test_the_served_step_names_forevers_folder(root, tmp_path, target):
    """After every client, `served` prunes data/english against Forever's own tables and quest cache:
    Forever named explicitly, not "the last client"; the other clients' caches only map objectives to quests."""
    out = [ln for ln in _dry(root, target, f"INPUTS={tmp_path}") if "import english served" in ln]
    assert len(out) == 1
    forever = f"{tmp_path}/clients/forever-1.60.1.70009/"
    for table in ("QuestV2.csv", "questcache.wdb", "ItemSparse.csv", "SpellName.csv"):
        assert f'"{forever}{table}"' in out[0], table
    assert f'--map-cache "{tmp_path}/clients/classic-era-1.15.9.69722/questcache.wdb"' in out[0]
    assert "--merge" not in out[0] and "--dry-run" not in out[0]


def test_preflight_dry_runs_the_cache_import(makefile, root):
    recipe = "\n".join(_recipe(makefile, "client-preflight"))
    assert 'test -f "$(WDB_QUEST)"' in recipe and 'test -f "$(WAGO_QUESTV2)"' in recipe
    assert "import english wdb" in recipe and "--dry-run" in recipe
    r = subprocess.run(["make", "-s", "-C", str(root), "import-english", "INPUTS=/nonexistent-wfj"],
                       capture_output=True, text=True, check=False)
    assert r.returncode != 0
    assert "import: classic-era: no quest cache at /nonexistent-wfj/clients/classic-era-1.15.9.69722/questcache.wdb" in r.stdout


def test_a_broken_second_client_stops_the_import_before_any_write(makefile, root, tmp_path):
    """Every client is preflighted before the first import step, so a missing Forever cache stops the
    target even when Classic Era is complete, and nothing has been imported."""
    classic = tmp_path / "clients" / "classic-era-1.15.9.69722"
    classic.mkdir(parents=True)
    for f in ("questcache.wdb", "QuestV2.csv", "Spell.csv", "ItemEffect.csv"):
        (classic / f).write_text("")
    recipe = "\n".join(_recipe(makefile, "client-preflight"))
    assert recipe.index("test -f") < recipe.index("--dry-run")
    r = subprocess.run(["make", "-s", "-C", str(root), "wdb-preflight", f"INPUTS={tmp_path}"],
                       capture_output=True, text=True, check=False)
    # the empty classic-era cache fails its own dry run; a valid one would pass on to forever's missing cache
    assert r.returncode != 0 and "import english wdb" not in r.stdout
    r = subprocess.run(["make", "-s", "-C", str(root), "client-preflight", "CLIENT=forever", f"INPUTS={tmp_path}"],
                       capture_output=True, text=True, check=False)
    assert r.returncode != 0 and f"import: forever: no quest cache at {tmp_path}/clients/forever-1.60.1.70009/" in r.stdout
    for target in ("import", "import-english"):
        lines = _recipe(makefile, target)
        assert "$(ONE_CLIENT_GUARD)" in lines[0] and "wdb-preflight" in lines[1]
    assert "for c in $(CLIENTS); do $(MAKE) -s client-preflight CLIENT=$$c || exit 1; done" in "\n".join(
        _recipe(makefile, "wdb-preflight"))


def test_an_unknown_client_is_refused(root):
    r = subprocess.run(["make", "-s", "-C", str(root), "help", "CLIENT=retail"], capture_output=True, text=True, check=False)
    assert r.returncode != 0 and "CLIENT=retail is not one of: classic-era forever" in r.stderr


@pytest.mark.parametrize("client", list(CLIENTS))
def test_single_client_targets_act_on_the_selected_client(root, tmp_path, client):
    """The fetch / extract / copy targets read and write only the selected client's folder."""
    build, src, product = CLIENTS[client]
    folder = f"{tmp_path}/clients/{client}-{build}"
    wow = tmp_path / "wow"
    (wow / "Cache/WDB/enUS").mkdir(parents=True)
    (wow / "Cache/WDB/enUS/questcache.wdb").write_text("")
    runs = [_dry(root, "wdb-copy", f"CLIENT={client}", f"INPUTS={tmp_path}", f"WOW_DIR={wow}"),
            _dry(root, "tables-extract", f"CLIENT={client}", f"INPUTS={tmp_path}", f"WOW_DIR={wow}")]
    if src == "wago":
        runs.append(_dry(root, "wago-fetch", f"CLIENT={client}", f"INPUTS={tmp_path}"))
    for out in runs:
        text = "\n".join(out)
        assert folder in text, text
        assert "/clients/" not in text.replace(folder, ""), text
    assert f'--product "{product}"' in "\n".join(runs[1])
    if src == "wago":
        assert f"build={build}" in "\n".join(runs[2])


def test_wago_fetch_refuses_a_client_pinned_to_its_own_tables(root, tmp_path):
    r = subprocess.run(["make", "-s", "-C", str(root), "wago-fetch", "CLIENT=forever", f"INPUTS={tmp_path}"],
                       capture_output=True, text=True, check=False)
    assert r.returncode == 2 and "CLIENT=forever is pinned to db2 tables and not wago" in r.stdout
    assert not (tmp_path / "clients").exists()


def test_rebuild_check_refuses_a_dirty_tree_before_deleting(makefile):
    """The dirty check is the first line; nothing is deleted before it and the preflight."""
    recipe = _recipe(makefile, "rebuild-check")
    assert "$(ONE_CLIENT_GUARD)" in recipe[0]
    assert "git status --porcelain -- data $(ADDON) pipeline Makefile" in recipe[1] and "exit 1" in recipe[1]
    delete = next(i for i, ln in enumerate(recipe) if "-delete" in ln)
    assert delete > next(i for i, ln in enumerate(recipe) if "wdb-preflight" in ln) > 0
    assert "find data/english -name '*.jsonl' -delete" in recipe[delete]
    after = "\n".join(recipe[delete + 1:])
    assert "$(MAKE) -s -j1 -S data" in after and "git status --porcelain -- data $(ADDON)" in after and "exit 1" in after


def test_wago_fetch_replaces_no_csv_unless_every_table_downloaded(makefile):
    recipe = _recipe(makefile, "wago-fetch")
    text = "\n".join(recipe)
    download = next(i for i, ln in enumerate(recipe) if "curl -fsSL" in ln)
    move = next(i for i, ln in enumerate(recipe) if 'mv "$(CLIENT_DIR)/$$t.csv.part"' in ln)
    assert move > download and text.count("for t in $(WAGO_TABLES)") == 3  # clear parts · download all · move all
    assert "no CSV replaced" in text


def test_wago_fetch_names_the_tables(makefile):
    tables = re.search(r"^WAGO_TABLES\s*:=\s*(.*)$", makefile, re.M).group(1).split()
    assert set(tables) == {"ItemSparse", "SpellName", "GlobalStrings", "ItemSubClass", "SpellItemEnchantment", "QuestV2",
                           "Spell", "ItemEffect"}  # Spell + ItemEffect for client-text
    recipe = "\n".join(_recipe(makefile, "wago-fetch"))
    assert "$(WAGO_TABLES)" in recipe and "build=$(WAGO_BUILD)" in recipe


def test_wdb_copy_reads_only_under_wow_dir(makefile, root):
    recipe = _recipe(makefile, "wdb-copy")
    copies = [ln for ln in recipe if re.search(r"\b(cp|mv|rm|rsync|ln)\b", ln)]
    # the only reads from the game folder; every write lands on WDB_QUEST (or its .prev backup)
    assert '\tcp "$(WOW_DIR)/Cache/WDB/enUS/questcache.wdb" "$(WDB_QUEST)"' in copies
    for ln in copies:
        assert ln.rstrip().endswith(('"$(WDB_QUEST)"', '"$(WDB_QUEST).prev"; echo "wdb-copy: previous copy kept as $(WDB_QUEST).prev"; fi'))
    r = subprocess.run(["make", "-s", "-C", str(root), "wdb-copy", "WOW_DIR="], capture_output=True, text=True, check=False)
    assert r.returncode != 0 and "usage: make wdb-copy WOW_DIR=" in r.stdout + r.stderr


def test_no_personal_paths(makefile):
    assert "/" + "Volumes/" not in makefile and "/" + "Users/" not in makefile and "Wa" + "shu" not in makefile


def test_tables_extract_reads_the_client_and_writes_only_inputs(makefile):
    """The client folder is only read; the CSVs land in INPUTS, the hotfix cache is optional."""
    recipe = "\n".join(_recipe(makefile, "tables-extract"))
    assert "wfj.dev.client_tables" in recipe and '--out "$(CLIENT_DIR)"' in recipe
    assert '--product "$(PRODUCT)"' in recipe and ".flavor.info" not in recipe  # no other game file is read
    assert re.search(r"^PRODUCT\s*\?=\s*\$\(\$\(CLIENT\)_PRODUCT\)$", makefile, re.M)  # per client
    assert re.search(r"^HOTFIXES\s*\?=\s*\$\(WOW_DIR\)/Cache/ADB/enUS/DBCache\.bin$", makefile, re.M)
    assert '--hotfixes "$$H"' in recipe and 'H="$$PWD/$$H"' in recipe  # a relative path resolves before `cd pipeline`
    for ln in _recipe(makefile, "tables-extract"):
        assert not re.search(r"\b(cp|mv|rm|rsync|ln)\b", ln), ln


def test_tables_extract_needs_a_client_folder(root):
    r = subprocess.run(["make", "-s", "-C", str(root), "tables-extract"], capture_output=True, text=True, check=False)
    assert r.returncode == 2 and "usage: make tables-extract WOW_DIR=" in r.stdout


def test_client_text_follows_the_names_under_one_label(makefile):
    """Names, then tooltip text, then UI strings, all with --src $(TABLES_SRC)."""
    lines = _recipe(makefile, "import-client")
    at = {n: next(i for i, ln in enumerate(lines) if f"import english {n}" in ln) for n in ("wago-ids", "client-text", "wago-ui")}
    assert at["wago-ids"] < at["client-text"] < at["wago-ui"]
    for n in at:
        assert "--src $(TABLES_SRC)" in lines[at[n]]
    assert '"$(CLIENT_SPELL)" "$(CLIENT_ITEMEFFECT)"' in lines[at["client-text"]]
    assert re.search(r"^TABLES_SRC\s*\?=\s*\$\(\$\(CLIENT\)_SRC\)$", makefile, re.M)


def test_preflight_needs_spell_and_itemeffect(makefile):
    recipe = "\n".join(_recipe(makefile, "client-preflight"))
    assert 'test -f "$(CLIENT_SPELL)" -a -f "$(CLIENT_ITEMEFFECT)"' in recipe


def test_wago_fetch_stamps_the_tables_after_moving_them(makefile):
    """The stamp is written once every CSV is in place, labelled wago@WAGO_BUILD."""
    recipe = _recipe(makefile, "wago-fetch")
    move = next(i for i, ln in enumerate(recipe) if 'mv "$(CLIENT_DIR)/$$t.csv.part"' in ln)
    clear = next(i for i, ln in enumerate(recipe) if "wfj.dev.tables_stamp clear" in ln)
    stamp = next(i for i, ln in enumerate(recipe) if "wfj.dev.tables_stamp write" in ln)
    assert clear < move < stamp  # unstamped while the CSVs are replaced
    assert '--dir "$(CLIENT_DIR)" $(WAGO_TABLES)' in recipe[clear]
    assert 'write --dir "$(CLIENT_DIR)" --src wago --build $(WAGO_BUILD) $(WAGO_TABLES)' in recipe[stamp]


def test_preflight_checks_every_client_table_stamp_before_any_import_writes(makefile):
    """`import` / `import-english` run wdb-preflight first; it checks the stamps of every CSV the
    three client-table imports read, so a refusal stops the target before predecessor / pfQuest / VMaNGOS write."""
    recipe = "\n".join(_recipe(makefile, "client-preflight"))
    assert "wfj.dev.tables_stamp check --src $(TABLES_SRC) --build $(WAGO_BUILD)" in recipe
    for var in ("WAGO_ITEM", "WAGO_SPELL", "CLIENT_SPELL", "CLIENT_ITEMEFFECT", "WAGO_GLOBALSTRINGS",
                "WAGO_ITEMSUBCLASS", "WAGO_ENCHANTMENTS"):
        assert f"$({var})" in recipe.split("tables_stamp check")[1], var


def test_every_english_import_passes_the_merge_mode(makefile):
    """Two clients supply the client text and they ship different id sets, so an import must keep
    what the other client provides. Without `--merge` on every line, `make import-english` would replace and
    silently undo the union the committed data depends on."""
    assert "MERGE        ?= union" in makefile
    lines = [ln for ln in makefile.splitlines() if "-m wfj import english " in ln]
    assert len(lines) >= 6  # pfQuest + VMaNGOS (shared) and the four per-client imports (`import-client`)
    for ln in lines:
        verb = ln.split("import english ", 1)[1].split()[0]
        # one source at one version, so there is nothing for a second client to hold: pfQuest is a repo at a
        # commit, VMaNGOS a database snapshot, and the collector dump is this client's own recording
        if verb in ("pfquest", "vmangos", "collector"):
            continue
        # `served` merges nothing; it only removes English for ids Forever does not serve
        if verb == "served":
            continue
        assert "--merge $(MERGE)" in ln, ln


@pytest.mark.parametrize("target", ["import", "import-english", "rebuild-check"])
@pytest.mark.parametrize("knob", ["WAGO_BUILD=9.9", "MERGE=replace", "CLIENT=classic-era", "CLIENT_DIR=/x"])
def test_a_per_client_knob_on_a_two_client_target_is_refused(root, tmp_path, target, knob):
    """A sub-make inherits a command-line value, so it would pin both clients to it."""
    r = subprocess.run(["make", "-s", "-C", str(root), target, knob, f"INPUTS={tmp_path}"], capture_output=True, text=True, check=False)
    assert r.returncode == 2 and f"{target}: runs every client in CLIENTS; {knob.split('=')[0]} given" in r.stdout
    assert "import english" not in r.stdout and not list(tmp_path.iterdir())


def test_tables_extract_refuses_a_wago_client_and_pins_the_build(root, tmp_path, makefile):
    """An install's tables never replace a wago-pinned folder, and an install of another build
    than the client's pin writes nothing (the pinned build's tables cannot be extracted again once it patched)."""
    r = subprocess.run(["make", "-s", "-C", str(root), "tables-extract", "CLIENT=classic-era", f"WOW_DIR={tmp_path}",
                        f"INPUTS={tmp_path}"], capture_output=True, text=True, check=False)
    assert r.returncode == 2 and "CLIENT=classic-era is pinned to wago tables and not db2" in r.stdout
    assert "--expect-build $(WAGO_BUILD)" in "\n".join(_recipe(makefile, "tables-extract"))
    out = "\n".join(_dry(root, "tables-extract", f"WOW_DIR={tmp_path}", f"INPUTS={tmp_path}/in"))
    assert "--expect-build 1.60.1.70009" in out


def test_a_cross_check_folder_lifts_the_source_guard(root, tmp_path):
    out = "\n".join(_dry(root, "wago-fetch", "CLIENT=forever", f"CLIENT_DIR={tmp_path}/wago-check", f"INPUTS={tmp_path}"))
    assert f"{tmp_path}/wago-check/" in out and "build=1.60.1.70009" in out and "/clients/" not in out


def test_wdb_copy_refuses_a_cache_of_another_build(makefile):
    """The header build is compared with the client's pin before anything is copied."""
    recipe = _recipe(makefile, "wdb-copy")
    check = next(i for i, ln in enumerate(recipe) if "read_ids" in ln)
    assert check < next(i for i, ln in enumerate(recipe) if ln.lstrip("\t@").startswith(("cp ", "if [")))
    assert "$(WDB_BUILD) $(CLIENT)" in recipe[check] and "nothing copied" in recipe[check]


def test_rebuild_check_checks_the_shared_inputs_and_runs_one_job(makefile):
    recipe = _recipe(makefile, "rebuild-check")
    delete = next(i for i, ln in enumerate(recipe) if "-delete" in ln)
    shared = next(i for i, ln in enumerate(recipe) if "shared input missing" in ln)
    assert shared < delete
    for var in ("PRED_QUEST", "PRED_TOOLTIP", "QJP", "CJQ", "PFQUEST", "VMANGOS_DB", "UI_KEYS"):
        assert f'"$({var})"' in recipe[shared], var
    run = next(ln for ln in recipe[delete:] if "data ||" in ln)
    assert "-j1 -S data" in run and "git checkout -- data $(ADDON)" in run


def test_a_per_client_knob_in_the_environment_is_refused(root, tmp_path):
    import os
    env = {**os.environ, "WAGO_BUILD": "9.9"}
    r = subprocess.run(["make", "-s", "-C", str(root), "import-english", f"INPUTS={tmp_path}"], capture_output=True,
                       text=True, env=env, check=False)
    assert r.returncode == 2 and "WAGO_BUILD given on the command line or in the environment" in r.stdout


def test_a_relative_inputs_is_made_absolute(root):
    out = "\n".join(_dry(root, "wdb-copy", "WOW_DIR=/nonexistent", "INPUTS=rel-inputs"))
    assert f"{root}/rel-inputs/clients/forever-1.60.1.70009/questcache.wdb" in out
