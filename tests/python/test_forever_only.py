"""ADR-034: Forever is the only target. Classic Era stays an input (its quest cache and tables feed the
English), but the addon carries no Era-only file, name or client gate, the build ships only ids the Forever client
lists, and the docs describe one target."""

import re
from pathlib import Path

from local_inputs import forever_client, need

from wfj.emit import lua_writer, schema
from wfj.io import wago, wdb
from wfj.io.jsonl_store import Store

ADDON = Path("addon/WoWForeverJapanese")

# Globals only the Classic Era UI defines (the Era target survey in docs/research/). A name
# preceded by a word character or a dot is another name or a Forever child key (`PlayerSpellsFrame.SpellBookFrame`,
# `content.ReputationBar`), so it is not a hit.
ERA_ONLY = (
    "GuildFrame", "GuildStatus_Update", "QuestLogFrame", "QuestLog_UpdateQuestDetails", "HonorFrame_Update",
    r"SpellButton\d", "SpellBookFrame", "SpellBookTitleText", "PlayerTalentFrame", "Blizzard_TalentUI",
    "ReputationFrame_Update", r"ReputationBar\d", "SkillFrame_UpdateSkills", "SkillRankFrame", "ClassTrainerGreetingText",
    "GetTrainerGreetingText", "WhoList_Update", "FriendsTabHeaderTab", "MailEditBox", "InboxFrame_Update",
    "MerchantRepairText", "BankFramePurchaseInfo", "SocialsMicroButton", "LFGMinimapFrame", "MinimapZoomIn",
    "RaidInfoSubheader", "ItemTextTitleText", "QuestFrameCancelButton", "OnTooltipSetItem", "OnTooltipSetSpell",
    r"CharacterFrameTab\d", "PetPaperDollFrame_Update",
)
GATES = ("classicGuild", "WFJ.Camelot", "Camelot.present", '"WorldMapConstants"')
REMOVED = ("UI/Guild.lua", "UI/Honor.lua", "UI/QuestLog.lua", "UI/Camelot.lua")


def _addon_lua(root):
    for path in sorted((root / ADDON).rglob("*.lua")):
        if "Data" not in path.relative_to(root / ADDON).parts:
            yield path, path.read_text(encoding="utf-8")


def test_era_only_modules_are_gone(root):
    assert [f for f in REMOVED if (root / ADDON / f).exists()] == []
    toc = (root / ADDON / "WoWForeverJapanese.toc").read_text(encoding="utf-8")
    assert [f for f in REMOVED if f.replace("/", "\\") in toc] == []
    hits = [f"{p.name}: {m}" for p, text in _addon_lua(root)
            for m in ("WFJ.Guild", "WFJ.Honor", "WFJ.QuestLog", "WFJ.Camelot") if re.search(re.escape(m) + r"\b", text)]
    assert hits == []


def test_no_era_only_names(root):
    """Code only: a comment may name what Forever lacks (\"camelot has no QuestLogFrame\")."""
    pattern = re.compile(r"(?<![\w.])(" + "|".join(ERA_ONLY) + r")(?!\w)")
    hits = [f"{p.relative_to(root)}:{n}: {m.group(1)}" for p, text in _addon_lua(root)
            for n, line in enumerate(text.splitlines(), 1) for m in pattern.finditer(line.split("--", 1)[0])]
    assert hits == []


def test_no_client_gates(root):
    hits = [f"{p.relative_to(root)}: {g}" for p, text in _addon_lua(root) for g in GATES if g in text]
    assert hits == []


def test_no_trainer_greeting(root):
    assert not (root / ADDON / "Data/TrainerGreeting").exists()
    assert not (root / "data/trainer_greeting").exists() and not (root / "data/english/trainer_greeting").exists()
    hits = [str(p.relative_to(root)) for base in ("addon", "pipeline/wfj")
            for p in sorted((root / base).rglob("*")) if p.suffix in (".lua", ".toc", ".py")
            and "trainer_greeting" in p.read_text(encoding="utf-8")]
    assert hits == []


def test_no_generated_folder_outlives_its_kind(root):
    """`generate` deletes only shards of the kinds it knows: a removed kind's folder must go with it."""
    dirs = {p.name for p in (root / ADDON / "Data").iterdir() if p.is_dir()}
    assert dirs == set(schema.FILE_PREFIX.values())


def test_shipped_ids_are_listed_by_forever(root):
    d = need(forever_client(root), "the Forever client folder")
    served = {
        "quest": wago.read_ids(d / "QuestV2.csv") | set(wdb.read_ids(d / "questcache.wdb")[1]),
        "item": wago.read_ids(d / "ItemSparse.csv"),
        "spell": wago.read_ids(d / "SpellName.csv"),
    }
    # Additive (ADR-050): an id an earlier Forever build served is kept, so it counts as served
    for k in served:
        record = root / "pipeline" / "served" / f"{k}.tsv"
        if record.is_file():
            served[k] |= {int(r.split("\t")[0]) for r in record.read_text(encoding="utf-8").splitlines()
                          if r and not r.startswith("#")}
    store = Store(root / "data")
    unserved = {k: sorted({ln["id"] for ln in store.load(k) if lua_writer.shipped(ln) and ln["id"] not in ids})[:5]
                for k, ids in served.items()}
    assert unserved == {"quest": [], "item": [], "spell": []}


# Target docs: a line naming Classic Era must be about it as an input or as history.
TARGET_DOCS = ("docs/testing/strategy.md", "docs/app-capabilities.md", "docs/overview.md", "docs/roadmap.md")
ALLOWED = re.compile(r"input|harvest|cache|source|ADR|history", re.IGNORECASE)


def test_docs_name_one_target(root):
    files = [root / f for f in TARGET_DOCS] + sorted((root / ".github").rglob("*.md")) + \
        sorted((root / ".github").rglob("*.yml"))
    hits = [f"{p.relative_to(root)}:{n}" for p in files
            for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1)
            if "Classic Era" in line and not ALLOWED.search(line)]
    assert hits == []
