"""The setup page names every import input and the data-model doc matches delivery."""


def test_local_setup_names_inputs(root):
    text = (root / "docs/operations/local-setup.md").read_text(encoding="utf-8")
    for needle in (
        "classic-wow-quest-japanese-translator",
        "classic-wow-tooltips-japanese-translator",
        "pfQuest",
        "wago.tools",
        "wfj import",
        "ItemSparse",
        "SpellName",
    ):
        assert needle in text, needle


def test_data_model_matches_delivery(root):
    text = (root / "docs/architecture/data-model.md").read_text(encoding="utf-8")
    for needle in ("pending", "origins", "data/SCHEMA", "-NNNN.jsonl"):
        assert needle in text, needle


def test_local_setup_names_check_targets(root):
    text = (root / "docs/operations/local-setup.md").read_text(encoding="utf-8")
    assert "make check" in text and "make stats" in text


def test_local_setup_names_harvest_inputs(root):
    """The quest-cache inputs and how to get them."""
    text = (root / "docs/operations/local-setup.md").read_text(encoding="utf-8")
    for needle in ("QuestV2", "questcache.wdb", "wago-fetch"):
        assert needle in text, needle


def test_local_setup_names_client_folders(root):
    """The per-client input folders, how to pick a client, and the rebuild proof."""
    text = (root / "docs/operations/local-setup.md").read_text(encoding="utf-8")
    for needle in ("predecessors/clients/", "CLIENT=", "rebuild-check"):
        assert needle in text, needle
    for stale in ("predecessors/wdb/questcache", "predecessors/wdb/missing", "forever-tables/GlobalStrings"):
        assert stale not in text, stale




def test_local_setup_names_client_table_inputs(root):
    """The local extraction and its inputs."""
    text = (root / "docs/operations/local-setup.md").read_text(encoding="utf-8")
    for needle in ("tables-extract", "CLIENT_SPELL", "CLIENT_ITEMEFFECT", "TABLES_SRC", "HOTFIXES", "PRODUCT"):
        assert needle in text, needle



def test_harvest_docs_match_delivery(root):
    """Pipeline, data model and ADRs describe the wdb import and the delta report."""
    pipeline = (root / "docs/systems/pipeline.md").read_text(encoding="utf-8")
    for needle in ("import english wdb", "--delta", "wdb-copy", "wago-fetch"):
        assert needle in pipeline, needle
    assert "wdb@" in (root / "docs/architecture/data-model.md").read_text(encoding="utf-8")
    adrs = sorted((root / "docs/adr").glob("020-*.md"))
    assert len(adrs) == 1 and "Accepted" in adrs[0].read_text(encoding="utf-8")
    adr19 = (root / "docs/adr/019-quest-english-per-field-and-live-check.md").read_text(encoding="utf-8")
    assert adrs[0].name in adr19
