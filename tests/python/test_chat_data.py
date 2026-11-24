"""The committed chat data (`data/chat/`) and the chat word lists generated into the addon."""

from collections import Counter
from pathlib import Path

from wfj.core import chat_words as cw

ADDON = Path("addon") / "WoWForeverJapanese"
MAX_GENERATED_BYTES = 6 * 1024 * 1024  # the chat lists are always in memory: a jump in size is looked at
MAX_PER_TOPIC = 16  # the phrase card is one fixed size: two columns of eight


def test_the_chat_list_is_long_enough_to_be_useful(root):
    chat = cw.load(root / "data")
    assert chat is not None
    assert len(chat.words_ja) >= 300
    assert len(chat.words_en) >= 300


def test_every_chat_word_can_be_found_in_a_chat_line(root):
    chat = cw.load(root / "data")
    # the addon looks for a Japanese word in a stretch of non-Latin text, and for an English word as one token
    assert [w for w in chat.words_ja if any(ord(c) < 0x80 for c in w)] == []
    assert [w for w in chat.words_en if not all(c.isascii() and (c.isalnum() or c == "'") for c in w)] == []


def test_the_phrase_book_has_enough_phrases_and_no_topic_outgrows_the_card(root):
    chat = cw.load(root / "data")
    assert len(chat.phrases) >= 120
    per_topic = Counter(p["topic"] for p in chat.phrases)
    assert len(per_topic) >= 6
    assert {t: n for t, n in per_topic.items() if n > MAX_PER_TOPIC} == {}
    assert [p["id"] for p in chat.phrases] == list(range(1, len(chat.phrases) + 1))


def test_the_generated_chat_lists_stay_under_their_size(root):
    files = sorted((root / ADDON / "Data" / "Chat").glob("Chat_*.lua"))
    assert any(f.name == "Chat_list.lua" for f in files)
    assert any(f.name.startswith("Chat_ja_") for f in files) and any(f.name.startswith("Chat_en_") for f in files)
    assert sum(f.stat().st_size for f in files) < MAX_GENERATED_BYTES


def test_an_english_word_gets_a_dictionary_form_not_a_cut_off_one(root):
    rows = {}
    for f in (root / ADDON / "Data" / "Chat").glob("Chat_en_*.lua"):
        for line in f.read_text(encoding="utf-8").splitlines():
            if line.startswith('  ["kill"] = '):
                rows["kill"] = line
    assert rows["kill"].startswith('  ["kill"] = "倒す=たおす=')


def test_no_trial_left(root):
    """The in-game trial's command, file and probe are gone from the addon."""
    left = []
    for f in sorted((root / ADDON).rglob("*.lua")):
        if "Data" in f.relative_to(root / ADDON).parts:
            continue
        text = f.read_text(encoding="utf-8")
        marks = ("/wfjchat", "ChatTrial", "WFJ probe", "WFJ chat trial")
        left += [f"{f.name}: {word}" for word in marks if word in text]
    assert left == []
    assert not (root / ADDON / "UI" / "ChatTrial.lua").exists()
