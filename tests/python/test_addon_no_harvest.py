"""The harvest is local tooling: nothing in the shipped addon reads the client
cache or runs the quest scan."""

# (`C_Timer.NewTicker` is not a needle: the addon uses it for its font retry.)
NEEDLES = ("questcache", "Cache/WDB", "GetQuestInfo", "WFJQ=")


def test_addon_never_touches_the_harvest(root):
    hits = []
    for path in sorted((root / "addon").rglob("*")):
        if path.is_file() and path.suffix in (".lua", ".toc", ".xml"):
            text = path.read_text(encoding="utf-8", errors="replace")
            hits += [f"{path.relative_to(root)}: {n}" for n in NEEDLES if n in text]
    assert hits == []
