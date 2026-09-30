"""core/paragraphs: canonical breaks and the completeness rule."""

import pytest

from wfj.core import paragraphs as P

EN3 = (
    "Greetings, $N.  I am Conservator Ilthalaine.  My purpose in Shadowglen is to ensure that the balance of "
    "nature is maintained.$b$bThe spring rains were particularly heavy this year, causing some of the forest's "
    "beasts to flourish while others suffered.$b$bUnfortunately, the nightsaber and thistle boar populations "
    "grew too large.  Shadowglen can only produce so much food for the beasts.  Journey forth, young $c, and "
    "thin the boar and saber populations so that nature's harmony will be preserved."
)
JA1 = "御機嫌よう、{name}。私はConservator Ilthalaine。Shadowglenでの私の仕事は、自然の均衡を保つことなんだ。"
JA3 = (
    JA1 + "\n\n今年の春は酷く雨ふりが多くて、そのために森では増えすぎた獣もいる。\n\n不幸なことに、"
    "NightsaberとThistle boreは増えすぎてしまったのだ。Shadowglenではそんなに多くの生き物たちに必要なだけの"
    "食料をまかなうことはできない。そこでだ、若き{class}よ、少し足を伸ばしてBoarとSaberを狩り、数を減らして"
    "やって欲しいのだ。そうすれば、自然の調和は保たれるだろう。"
)


@pytest.mark.parametrize(
    "raw, expected",
    [
        ("一段落。  二段落。", "一段落。\n\n二段落。"),  # WoWJapanizer / CraftJapanizer: two spaces
        ("一段落。    二段落。", "一段落。\n\n二段落。"),  # QuestJapanizer: four spaces
        ("一段落！　　二段落。", "一段落！\n\n二段落。"),  # ideographic spaces
        ("一段落。\n\n二段落。", "一段落。\n\n二段落。"),  # already canonical
        ("一段落。\n \n\n二段落。", "一段落。\n\n二段落。"),  # ragged newline run collapses
        ("Kobold Vermin  10匹", "Kobold Vermin  10匹"),  # no terminator before the run → untouched
        ("恐らくノームよりね……  銀の延べ棒。", "恐らくノームよりね……\n\n銀の延べ棒。"),  # ellipsis closes a line
        ("頭の中に響き渡った。>    Gazz'uz？", "頭の中に響き渡った。>\n\nGazz'uz？"),  # `>` (a quote mark in the corpus)
        ("そうだ...  行け。", "そうだ...\n\n行け。"),
        ("  前後の空白  ", "前後の空白"),
    ],
)
def test_normalize_breaks(raw, expected):
    assert P.normalize_breaks(raw) == expected


def test_counts():
    assert P.count(JA1) == 1 and P.count(JA3) == 3 and P.count("") == 0
    assert P.count_english(EN3) == 3
    assert P.count_english("Kill 10 kobolds.") == 1
    assert P.count_english("Hiccup!$B$BSo that crazy fool.$B$BI need a drink.") == 3


@pytest.mark.parametrize(
    "ja, en_raw, truncated, jp, ep",
    [
        (JA1, EN3, True, 1, 3),  # quest 456 as the predecessor shipped it: first paragraph only
        (JA3, EN3, False, 3, 3),  # quest 456 complete (QuestJapanizer 2009)
        ("ヒック!", "Hiccup!$b$bSo that crazy fool Brohann sent ya? " * 6, True, 1, 7),  # quest 1452
        ("一段落だけの英語の訳。", "A single paragraph in English, short.", False, 1, 1),  # no paragraphs to miss
        ("短い。", "One paragraph. " * 40, True, 1, 1),  # tiny ratio, single paragraph → still truncated
        ("", EN3, False, 0, 3),  # empty is not this rule's business (language rule rejects it)
    ],
)
def test_is_truncated(ja, en_raw, truncated, jp, ep):
    en_norm = en_raw.replace("$b$b", " ").replace("$B$B", " ").replace("$N", "Reyn").replace("$c", "druid")
    got = P.is_truncated(ja, en_raw, en_norm)
    assert got == (truncated, jp, ep)


def test_structural_rule_for_first_paragraph_only_layers():
    """A long first paragraph passes the ratio, but the relabelled wiki layer is one-paragraph by construction,
    so against a multi-paragraph English it is truncated whatever its length."""
    en_norm = EN3.replace("$b$b", " ")
    long_first = JA1 * 3  # ratio well above 0.22
    assert P.is_truncated(long_first, EN3, en_norm) == (False, 1, 3)
    assert P.is_truncated(long_first, EN3, en_norm, structural=True) == (True, 1, 3)
    assert P.is_truncated(JA3, EN3, en_norm, structural=True) == (False, 3, 3)  # complete → fine
    assert P.is_truncated(long_first, "One paragraph only.", "One paragraph only.", structural=True)[0] is False
    assert P.first_paragraph_only({"source": "cqjt@3446c82", "translator": "questjapanizer-wiki"})
    assert not P.first_paragraph_only({"source": "cqjt@3446c82", "translator": "Tammy"})
    assert not P.first_paragraph_only({"source": "qjp@0.5.8", "translator": "questjapanizer-wiki"})


def test_completeness_counts_covered_paragraphs():
    assert P.completeness(JA3, EN3) == 3 and P.completeness(JA1, EN3) == 1
    assert P.completeness(JA3, "single.") == 1  # never more than the English has


def test_constants_are_the_calibrated_ones():
    assert P.TRUNCATED_RATIO == 0.22 and P.TINY_RATIO == 0.08 and P.PARA == "\n\n"


def test_count_english_reads_a_client_b_digit_as_a_value():
    # in an item / spell template `$b1` is points per combo point; in server text `$B` is a break
    en = "Finishing moves have a $b1% chance to restore $451438s1 energy."
    assert P.count_english(en, client=True) == 1
    assert P.count_english(en) == 2
    assert P.count_english("One.$B$BTwo.", client=True) == 2
