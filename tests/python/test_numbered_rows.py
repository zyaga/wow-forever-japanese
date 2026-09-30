"""ADR-042: numbered UI rows. A UI widget's line whose English holds world-state tokens (`%2327w`) the
client fills with live numbers. The addon finds the row by a skeleton (every number run `#`) and fills the numbers
back in order; `generate` ships the skeleton's hash and the Japanese with each token as `%<k>$s`."""

import pytest

from wfj.core import numbered
from wfj.core.hashing import key as hash_key
from wfj.core.normalize import normalize_for


def test_only_the_widget_family_is_numbered():
    assert numbered.is_numbered("WidgetText:4401")
    assert not numbered.is_numbered("EmoteText:2")
    assert not numbered.is_numbered("TOWERS")


@pytest.mark.parametrize(
    ("en", "live"),
    [
        ("Towers Controlled: %2327w", "Towers Controlled: 3"),
        ("Bases: %1779w  Resources: %1776w/%1780w", "Bases: 2  Resources: 150/1600"),
        ("The Battle for Ashenvale occurs at 1pm and every 3 hours after.",
         "The Battle for Ashenvale occurs at 1pm and every 3 hours after."),
        ("%25344w%", "75%"),
    ],
)
def test_the_english_and_the_live_line_have_one_skeleton(en, live):
    # the addon replaces every digit run of the live line; the pipeline every token and every digit run of the English
    import re

    assert numbered.skeleton(en) == re.sub(r"[0-9]+", "#", live)


def test_tokens_become_the_place_of_their_number():
    en = "Bases: %1779w  Resources: %1776w/%1780w"
    assert numbered.fill_slots(en, "拠点: %1779w  資源: %1776w/%1780w") == "拠点: %1$s  資源: %2$s/%3$s"
    assert numbered.fill_slots(en, "資源 %1776w/%1780w、拠点 %1779w") == "資源 %2$s/%3$s、拠点 %1$s"
    # a literal digit in the English counts as a number of the line, so a token after it keeps its true place
    en = "The attack begins in 3 waves: %2000w left"
    assert numbered.fill_slots(en, "攻撃は3波: 残り%2000w") == "攻撃は%1$s波: 残り%2$s"


def test_a_literal_number_the_japanese_repeats_follows_the_live_line():
    # "1pm" and "3 hours" are number runs of the skeleton, so a hotfix that moves the event still matches: the
    # Japanese must take the live numbers, not keep the drafted ones
    en = "The Battle for Ashenvale occurs at 1pm and every 3 hours after."
    ja = "Battle for Ashenvaleは午後1時に始まり、その後3時間ごとに起こります。"
    assert numbered.fill_slots(en, ja) == "Battle for Ashenvaleは午後%1$s時に始まり、その後%2$s時間ごとに起こります。"
    # a number of the Japanese's own ("midnight" → 午前0時) stays; a repeated value takes the runs in order
    assert numbered.fill_slots("at midnight and every 2 hours", "午前0時から2時間ごと") == "午前0時から%1$s時間ごと"
    assert numbered.fill_slots("2 of 2", "2のうち2") == "%1$sのうち%2$s"


def test_a_token_the_english_lacks_is_refused():
    with pytest.raises(ValueError, match="%9w"):
        numbered.fill_slots("Towers Controlled: %2327w", "制圧した塔: %9w")


def test_generate_ships_the_skeleton_hash_and_the_slotted_japanese(root, tmp_path, monkeypatch):
    import json

    from wfj.cmd import generate

    data = tmp_path / "data"
    (data / "english" / "ui").mkdir(parents=True)
    (data / "ui").mkdir(parents=True)
    (data / "SCHEMA").write_text("1\n")
    en = "Towers Controlled: %2327w"
    h = hash_key(normalize_for("ui", en))
    (data / "english" / "ui" / "ui-W.jsonl").write_text(json.dumps(
        {"id": "WidgetText:4401", "field": "text", "en": en, "hash": h, "src": "db2@1.60.1.70009"}) + "\n")
    (data / "ui" / "ui-W.jsonl").write_text(json.dumps({
        "id": "WidgetText:4401", "field": "text", "ja": "制圧した塔: %2327w", "status": "trusted", "checks": [],
        "provenance": {"class": "machine", "model": "m", "source": "draft-ui-families@2026-09-26",
                       "imported": "2026-09-26"},
        "english": {"hash": h, "src": "db2@1.60.1.70009"}, "reasons": [], "conflicts": []}) + "\n")
    from wfj.io.jsonl_store import Store

    out = generate.plan(Store(data), [])
    shard = out["Data/UI/UI_W.lua"]
    skeleton_h1 = hash_key(normalize_for("ui", numbered.skeleton(en)))[:8]
    assert f"0x{skeleton_h1}" in shard
    assert "制圧した塔: %1$s" in shard
    assert "%2327w" not in shard

    # a hotfix renumbers the token: the row stops shipping, generate does not stop, and
    # validate names it
    (data / "english" / "ui" / "ui-W.jsonl").write_text(json.dumps(
        {"id": "WidgetText:4401", "field": "text", "en": "Towers Controlled: %2330w", "hash": h,
         "src": "db2@1.60.1.70009"}) + "\n")
    out = generate.plan(Store(data), [])
    assert "制圧した塔" not in "".join(v for k, v in out.items() if k.startswith("Data/UI/"))
    from wfj.cmd import validate

    problems = validate.rule_ui(Store(data), Store(data, english=True))
    assert any("WidgetText:4401" in p and "does not fit" in p for p in problems), problems


def test_no_numbered_english_holds_markup(root):
    """The addon strips colour / texture markup before it replaces the line's digits, while
    `generate` replaces the English's digits first: a colour code's hex digits would split the two skeletons. No
    shipped WidgetText English holds markup; if one ever does, normalize before `numbered.skeleton` in generate."""
    from wfj.io.jsonl_store import Store

    for ln in Store(root / "data", english=True).load("ui"):
        if numbered.is_numbered(ln["id"]):
            assert "|" not in ln["en"], ln["id"]
