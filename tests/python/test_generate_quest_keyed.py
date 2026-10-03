"""generate.quest_text_aliases: a repeated quest's progress / turn-in text keyed by its English (ADR-054)."""

from wfj.cmd.generate import quest_text_aliases
from wfj.core.hashing import key
from wfj.core.normalize import normalize_v1


def _en(id_, field, en):
    return {"id": id_, "field": field, "en": en, "hash": key(normalize_v1(en)), "src": "wdb@1.60.1.70205"}


def _ja(id_, field, status="trusted"):
    return {"id": id_, "field": field, "ja": "日本語", "status": status}


CAMP = "A good campfire is the foundation to any good camp."


def test_a_copy_without_the_field_gets_its_siblings_text_keyed():
    english = [_en(1, "title", "Camping 101: Cooking"), _en(2, "title", "Camping 101: Cooking"),
               _en(3, "title", "Camping 101: Cooking"), _en(1, "progress", CAMP), _en(2, "progress", CAMP)]
    got = quest_text_aliases([_ja(1, "progress"), _ja(2, "progress")], english)
    assert got == {key(normalize_v1(CAMP)): (1, "progress")}  # the lowest id answers a shared key


def test_nothing_keyed_when_every_copy_has_its_own_english_or_no_copy_is_translated():
    english = [_en(1, "title", "T"), _en(2, "title", "T"), _en(1, "completion", "A."), _en(2, "completion", "B."),
               _en(3, "title", "U"), _en(4, "title", "U"), _en(3, "progress", "C.")]
    assert quest_text_aliases([_ja(1, "completion"), _ja(3, "progress", "stale")], english) == {}


def test_a_single_quest_title_is_never_keyed():
    english = [_en(1, "title", "Only One"), _en(1, "progress", "Hello.")]
    assert quest_text_aliases([_ja(1, "progress")], english) == {}
