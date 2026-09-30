"""Link markup in the UI dictionary (core/markup.py)."""

from wfj.core import markup


def test_a_static_link_is_one_token_kept_verbatim():
    """The code-of-conduct notice's URL link is kept byte for byte; a changed or dropped link is refused."""
    link = "|HurlIndex:64|h|cnVISITABLE_URL_DEFAULT_CHAT_LINK_COLOR:https://support.blizzard.com/article/42673|r|h"
    en = f"View our Code of Conduct on {link} for more."
    assert markup.mismatch(en, f"詳しくは{link}の行動規範を。") is None
    assert markup.mismatch(en, "詳しくは行動規範を。") is not None
    assert markup.mismatch(en, f"詳しくは{link.replace('42673', '1')}の行動規範を。") is not None


def test_an_atlas_is_one_token_kept_verbatim():
    """`|A…|a` (Edit Mode's expand / collapse label) is kept byte for byte; a dropped, added or changed
    atlas is `markup_changed`."""
    atlas = "|A:editmode-down-arrow:16:11:0:-7|a"
    en = f"Expand options {atlas}"
    assert markup.tokens(en)[atlas] == 1
    assert markup.mismatch(en, f"オプションを展開 {atlas}") is None
    assert markup.mismatch(en, "オプションを展開") is not None
    assert markup.mismatch(en, f"オプションを展開 {atlas.replace('down', 'up')}") is not None
    assert markup.mismatch("Expand options", f"オプションを展開 {atlas}") is not None


def test_a_named_colour_opener_is_counted_verbatim():
    """`|cnNAME:` opens a colour like `|cAARRGGBB`; the Japanese keeps the same opener (name as written)
    and its `|r`."""
    en = "|cnNORMAL_FONT_COLOR:Note:|r Changes apply now."
    assert markup.tokens(en)["|cnNORMAL_FONT_COLOR:"] == 1
    assert markup.mismatch(en, "|cnNORMAL_FONT_COLOR:注意:|r 変更はすぐに反映されます。") is None
    assert markup.mismatch(en, "注意:|r 変更はすぐに反映されます。") is not None
    assert markup.mismatch(en, "|cnRED_FONT_COLOR:注意:|r 変更はすぐに反映されます。") is not None
    assert markup.mismatch(en, "|cffffd200注意:|r 変更はすぐに反映されます。") is not None


def test_hex_colours_textures_and_breaks_are_unchanged():
    """The existing tokens count as before (hex lower-cased, textures verbatim, breaks)."""
    en = "|cFFFFD200Gold|r |TInterface\\Icons\\Coin:14|t\n|nNext"
    assert markup.tokens(en) == markup.tokens("|cffffd200金|r |TInterface\\Icons\\Coin:14|t\n|n次")
    assert set(markup.tokens(en)) == {"|cffffd200", "|r", "|TInterface\\Icons\\Coin:14|t", "\n", "|n"}


def test_a_bare_named_colour_opener_and_an_unclosed_atlas_are_tokens():
    """`|cn` with no `NAME:` and `|A…` with no `|a` are still counted, so a Japanese that drops
    one (or closes it differently) is `markup_changed`, never silently equal."""
    assert markup.tokens("|cnNote|r")["|cn"] == 1
    assert markup.mismatch("|cnNote|r", "|cn注意|r") is None
    assert markup.mismatch("|cnNote|r", "注意|r") is not None
    unclosed = "Revert |A:common-icon-undo:0:0"
    assert markup.tokens(unclosed)["|A:common-icon-undo:0:0"] == 1
    assert markup.mismatch(unclosed, "元に戻す |A:common-icon-undo:0:0") is None
    assert markup.mismatch(unclosed, "元に戻す") is not None
    assert markup.mismatch("Revert |A:common-icon-undo:0:0|a", "元に戻す |A:common-icon-undo:0:0") is not None
