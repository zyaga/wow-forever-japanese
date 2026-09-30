from wfj.core.language import SIMPLIFIED_ONLY, has_simplified, is_japanese


def test_prose_japanese():
    assert is_japanese("大いなるヒポグリフSharptalonは倒された。", "description")
    assert is_japanese("駄目!!!!!", "description")  # kanji-only prose is still Japanese


def test_prose_rejects_chinese_and_latin_only():
    assert not is_japanese("见鬼去吧，萨萨里安。", "description")
    assert not is_japanese("I will keep three of the weapons", "completion")
    assert not is_japanese("   ", "objectives")
    assert not is_japanese("{name}、", "description")  # placeholder + punctuation only: no CJK


def test_title_rules():
    assert is_japanese("賞金首Garrick Padfoot", "title")
    assert is_japanese("絶体絶命", "title")
    assert is_japanese("Garrick Padfoot", "title")  # Latin-only title passes
    assert not is_japanese("战场", "title")


def test_simplified_set_has_no_japanese_characters():
    for ch in "着将几么会学国体里点区医与云":
        assert ch not in SIMPLIFIED_ONLY, ch
    assert has_simplified("这是")
