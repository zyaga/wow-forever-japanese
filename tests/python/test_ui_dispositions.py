"""Every menu, HelpTip and composite key the research doc (`DOC`) reviewed has one disposition, applied. Its
`## Disposition table` gives each key `list`, `permanent` (the exact reason for pipeline/ui_exclusions.txt) or a
hand-off to the per-screen forms; this test holds the key lists to it."""

import re
from pathlib import Path

from wfj.io import wago

DOC = "docs/research/2026-09-25-menus-callouts-and-composites.md"
DISPOSITIONS = {"list", "permanent"}
# a source citation: a Blizzard file with a line number (`…/questinfo.lua:475`, `…/audioassist.xml:8`)
SOURCE = re.compile(r"[\w./-]+\.(?:lua|xml):\d+")
_EXCL = re.compile(r"^([A-Z][A-Z0-9_]*|ItemSubClass:\d+:\d+)\s+#\s+(\S.*)$")


def _table(root: Path) -> list[dict[str, str]]:
    """The table's rows as {key, group, disposition, form, evidence}; a `|` inside a cell is written `\\|`."""
    text = (root / DOC).read_text(encoding="utf-8")
    section = text.split("\n## Disposition table\n", 1)[1].split("\n## ", 1)[0]
    rows = []
    for line in section.splitlines():
        if not line.startswith("| ") or line.startswith("| key |"):
            continue
        cells = [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", line.strip())[1:-1]]
        assert len(cells) == 5, line
        rows.append(dict(zip(("key", "group", "disposition", "form", "evidence"), cells, strict=True)))
    return rows


def _exclusions(root: Path) -> list[tuple[str, str]]:
    out = []
    for raw in (root / "pipeline/ui_exclusions.txt").read_text(encoding="utf-8").splitlines():
        if raw.startswith("#") or not raw.strip():
            continue
        m = _EXCL.match(raw)
        assert m, raw
        out.append((m.group(1), m.group(2)))
    return out


def test_the_table_has_one_row_per_key_and_a_known_disposition(root):
    rows = _table(root)
    keys = [r["key"] for r in rows]
    assert len(rows) == 604 and len(set(keys)) == len(keys)
    assert {r["disposition"] for r in rows} <= DISPOSITIONS  # the last hand-off rows were listed later (own Japanese)


def test_every_table_key_is_in_exactly_one_list_as_its_disposition_says(root):
    listed = set(wago.read_keys(root / "pipeline/ui_keys.txt"))
    excluded = dict(_exclusions(root))
    for row in _table(root):
        key, disposition = row["key"], row["disposition"]
        assert (key in listed) != (key in excluded), key
        if disposition == "list":
            assert key in listed, key
            continue
        reason = excluded.get(key)
        assert reason is not None, key
        assert disposition == "permanent", key
        assert reason.startswith("permanent: "), key
        assert SOURCE.search(reason), (key, "cites no source file:line")
        assert reason == row["form"], (key, "the reason is the table's")


def test_the_stale_reasons_are_replaced(root):
    # ACHIEVEMENT_BUTTON keeps a sourced permanent reason, GUILD_BANK_LOG_TIME is listed, and the ui_keys.txt
    # header does not call colour codes or |4 plural grammar excluded (ADR-016 treats them as markup)
    excluded = dict(_exclusions(root))
    assert excluded["ACHIEVEMENT_BUTTON"].startswith("permanent: ")
    assert "GUILD_BANK_LOG_TIME" in set(wago.read_keys(root / "pipeline/ui_keys.txt"))
    header = [ln for ln in (root / "pipeline/ui_keys.txt").read_text(encoding="utf-8").splitlines()[:12]
              if ln.startswith("#")]
    assert not any("no colour" in ln for ln in header), header
    for key in ("SOCIAL_UI_RECENT_ALLIES_VIEW_HEADER_LEGACY_FRIENDS", "SOCIAL_UI_RECENT_ALLIES_VIEW_HEADER_PINNED",
                "SOCIAL_UI_RECENT_ALLIES_VIEW_HEADER_UNPINNED"):
        assert excluded[key].startswith("permanent: ") and SOURCE.search(excluded[key]), key
