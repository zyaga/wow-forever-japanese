"""The completeness rule inside the decision table, and the report."""

from wfj.core import report
from wfj.core.dedupe import Candidate, resolve, source_rank
from wfj.core.status import Scope, decide

# quest 456's real pfQuest English (497 chars, three paragraphs); the shipped one-paragraph Japanese is 70
EN_RAW = (
    "Greetings, $N.  I am Conservator Ilthalaine.  My purpose in Shadowglen is to ensure that the balance of "
    "nature is maintained.$B$BThe spring rains were particularly heavy this year, causing some of the forest's "
    "beasts to flourish while others suffered.$B$BUnfortunately, the nightsaber and thistle boar populations "
    "grew too large.  Shadowglen can only produce so much food for the beasts.  Journey forth, young $c, and "
    "thin the boar and saber populations so that nature's harmony will be preserved."
)
EN_NORM = EN_RAW.replace("$B$B", " ").replace("$N", "Reyn").replace("$c", "druid")
JA_CUT = "御機嫌よう、{name}。私はConservator Ilthalaine。Shadowglenでの私の仕事は、自然の均衡を保つことなんだ。"
JA_FULL = JA_CUT + "\n\n今年の春は酷く雨が多かった。\n\n不幸なことに、NightsaberとThistle Boarが増えすぎた。若き{class}よ。"


def scope():
    return Scope(
        kind="quest",
        fields={"description": EN_NORM, "title": "The Balance of Nature"},
        raw={"description": EN_RAW, "title": "The Balance of Nature"},
        hashes={"description": "h1", "title": "h2"},
        src="pfquest@7786596",
    )


def line(ja, source="cqjt@3446c82", translator="CraftJapanizer", conflicts=None, field="description"):
    return {
        "id": 456,
        "field": field,
        "ja": ja,
        "status": "pending",
        "checks": [],
        "provenance": {"class": "human", "translator": translator, "source": source, "imported": "2026-09-13"},
        "english": None,
        "reasons": [],
        "conflicts": conflicts or [],
    }


def test_truncated_variant_is_rejected_with_reason_and_length_check():
    d = decide(line(JA_CUT), scope(), set(), "h1")
    assert d.status == "rejected" and d.reasons == ["truncated:1/3"] and "length" in d.checks


def test_complete_variant_is_trusted_and_length_checked():
    d = decide(line(JA_FULL), scope(), set(), "h1")
    assert d.status == "trusted" and d.reasons == [] and d.checks == ["names", "length"]


def test_single_paragraph_english_is_never_length_checked():
    sc = scope()
    sc.raw["description"] = "Kill 10 Kobold Vermin."
    sc.fields["description"] = "Kill 10 Kobold Vermin."
    d = decide(line("Kobold Verminを10匹倒せ。"), sc, set(), "h1")
    assert d.status == "trusted" and "length" not in d.checks


def test_title_is_not_length_checked():
    d = decide(line("自然界のバランス", field="title"), scope(), set(), "h2")
    assert d.status == "trusted" and "length" not in d.checks


def test_complete_variant_wins_over_truncated_without_a_ruling():
    prov = {"class": "human", "translator": "Az", "source": "qjp@0.5.8", "imported": "2026-09-13"}
    d = decide(line(JA_CUT, conflicts=[{"ja": JA_FULL, "provenance": prov}]), scope(), set(), "h1")
    assert d.status == "trusted" and d.winner == 1 and "tiebreak" not in d.checks


def test_two_complete_variants_are_settled_by_source_priority():
    az = {"class": "human", "translator": "Az", "source": "qjp@0.5.8", "imported": "2026-09-13"}
    tammy = {"class": "human", "translator": "Tammy", "source": "cjq@2012031300", "imported": "2026-09-13"}
    other = JA_FULL + " 少し違う。"
    d = decide(line(JA_FULL, translator="Tammy", conflicts=[{"ja": other, "provenance": az}]), scope(), set(), "h1")
    assert d.status == "trusted" and d.winner == 0 and "tiebreak" in d.checks
    # the newer source wins even when it is the conflict variant
    d2 = decide(
        line(other, source="qjp@0.5.8", translator="Az", conflicts=[{"ja": JA_FULL, "provenance": tammy}]),
        scope(), set(), "h1",
    )
    assert d2.winner == 1 and "tiebreak" in d2.checks


def test_same_source_tie_stays_a_conflict():
    b = {"class": "human", "translator": "B", "source": "cqjt@3446c82", "imported": "2026-09-13"}
    d = decide(line(JA_FULL, translator="A", conflicts=[{"ja": JA_FULL + " 少し違う。", "provenance": b}]), scope(), set(), "h1")
    assert d.status == "rejected" and d.reasons == ["duplicate_conflict"]


def test_resolve_priority_flag_defaults_off():
    cands = [
        Candidate(0, "a", {"source": "qjp@0.5.8"}, None, None),
        Candidate(1, "b", {"source": "cqjt@3446c82"}, None, None),
    ]
    assert resolve(cands, lambda c: True) is None
    assert resolve(cands, lambda c: True, priority=True) == 1
    assert source_rank({"source": "cqjt@x"}) < source_rank({"source": "cjq@x"}) < source_rank({"source": "qjp@x"})
    assert source_rank({"source": "unknown@x"}) > source_rank({"source": "qjwiki@x"})


def test_report_truncated_table_and_headline():
    rejected = line(JA_CUT)
    rejected.update(status="rejected", reasons=["truncated:1/3"], checks=["names", "length"])
    ok = line(JA_FULL, source="qjp@0.5.8", translator="Az")
    ok.update(status="trusted", checks=["names", "length"])
    t = report.tally({"quest": [rejected, ok]})
    assert t["truncated"]["quest"] == {"cqjt/CraftJapanizer": 1}
    text = report.render(t, report.headline({"quest": [rejected, ok]}, {456}))
    assert "truncated by source/translator: cqjt/CraftJapanizer=1" in text
    assert "vanilla quests whose description was rejected as truncated: 1" in text
    assert "vanilla quests with a trusted description: 1" in text


# ---- completeness before source; the structural rule for the relabelled layer ----------------


def test_complete_lower_priority_variant_beats_long_first_paragraph():
    """Quest 6 shape: the cqjt wiki copy is paragraph one only but long enough to pass the ratio; the qjp
    conflict carries every paragraph. Completeness ranks before source (Blocker 1)."""
    long_cut = JA_CUT * 3  # one paragraph, ratio ≈ 0.42
    zheik = {"class": "human", "translator": "Zheik", "source": "qjp@0.5.8", "imported": "2026-09-13"}
    d = decide(line(long_cut, translator="Tammy", conflicts=[{"ja": JA_FULL, "provenance": zheik}]), scope(), set(), "h1")
    assert d.status == "trusted" and d.winner == 1 and "tiebreak" in d.checks


def test_relabelled_layer_one_paragraph_is_truncated_regardless_of_length():
    """Blocker 2: cqjt + questjapanizer-wiki is first-paragraph-only by construction."""
    long_cut = JA_CUT * 3
    d = decide(line(long_cut, translator="questjapanizer-wiki"), scope(), set(), "h1")
    assert d.status == "rejected" and d.reasons == ["truncated:1/3"]
    # the same text from a named translator (or from the 2009 file) passes on the ratio
    assert decide(line(long_cut, translator="Tammy"), scope(), set(), "h1").status == "trusted"
    assert decide(line(long_cut, source="qjp@0.5.8", translator="questjapanizer-wiki"), scope(), set(), "h1").status == "trusted"


def test_tiebreak_is_not_recorded_when_a_ruling_decided():
    az = {"class": "human", "translator": "Az", "source": "qjp@0.5.8", "imported": "2026-09-13"}
    other = JA_FULL + " 少し違う。"
    ln = line(JA_FULL, translator="Tammy", conflicts=[{"ja": other, "provenance": az, "ruling": {"ruling": "accept"}}])
    d = decide(ln, scope(), set(), "h1")
    assert d.winner == 1 and "tiebreak" not in d.checks
    ln2 = line(JA_FULL, translator="Tammy", conflicts=[{"ja": other, "provenance": az, "ruling": {"ruling": "reject"}}])
    d2 = decide(ln2, scope(), set(), "h1")
    assert d2.winner == 0 and "tiebreak" not in d2.checks
