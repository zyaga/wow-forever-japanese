"""`translate_batch cut` picks only undrafted, un-hand-written lines, one row per English
text, in the addon's token form; `expand` fans rows out to import-draft files and pins the style version."""

from pathlib import Path

import pytest

from wfj.cmd import import_ as imp
from wfj.cmd import import_draft
from wfj.core import hashing, style
from wfj.core.normalize import normalize_v1
from wfj.dev import translate_batch as tb
from wfj.dev.objective_items import objective_items
from wfj.io.jsonl_store import Store

HUMAN = {"class": "human", "translator": "Tammy", "source": "cqjt@3446c82", "imported": "2026-09-13"}
CORRECTION = {"class": "correction", "translator": "Az", "source": "correction@2026-09-14",
              "imported": "2026-09-14", "corrects": "qjp@0.5.8"}


def _machine(source):
    return {"class": "machine", "model": "model-a", "source": source, "imported": "2026-09-16"}


def _ja(id_, field, status, prov, conflicts=()):
    return {"id": id_, "field": field, "ja": "テスト", "status": status, "checks": [], "provenance": prov,
            "english": None, "reasons": [], "conflicts": list(conflicts)}


def _en(id_, field, en):
    return {"id": id_, "field": field, "en": en, "hash": "0" * 16, "src": "vmangos@13b49dc"}


@pytest.fixture
def repo(tmp_path):
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    (tmp_path / "docs" / "content").mkdir(parents=True)
    (tmp_path / "docs" / "content" / "translation-style-guide.md").write_text("# guide\n\nversion: sg1\n")
    data = tmp_path / "data"
    Store(data, english=True).save("quest", [
        _en(1, "progress", "Have you got them, $N?"),       # no line → selected
        _en(2, "progress", "Have you got them, $n?"),       # same drafter English as 1 → grouped
        _en(3, "progress", "Trusted already."),             # trusted → skipped
        _en(4, "progress", "Rejected human."),              # hand-written variant → skipped
        _en(5, "progress", "Conflict correction."),         # correction in conflicts → skipped
        _en(6, "progress", "Drafted sg1."),                 # machine variant of the current style → skipped
        _en(7, "progress", "Drafted sg0."),                 # older style → skipped; selected with --redraft-older
        _en(8, "completion", "Other field."),               # other kind → not in a progress cut
        _en(9, "progress", "Trusted sg0 draft."),           # trusted machine line → skipped; selected with --redraft-older
        _en(1, "objectives", "Bring 3 Gnoll Paws and a Sack of Barley to Grimbooze."),
        _en(2, "objectives", "Bring the Sack of Barley and Tough Wolf Meat."),
    ])
    Store(data, english=True).save("item", [
        _en(10, "name", "Gnoll Paw"), _en(11, "name", "Sack of Barley"), _en(12, "name", "Tough Wolf Meat"),
    ])
    Store(data).save("quest", [
        _ja(3, "progress", "trusted", HUMAN),
        _ja(4, "progress", "rejected", HUMAN),
        _ja(5, "progress", "rejected", _machine("draft-progress-sg0@2026-09-10"), [{"ja": "x", "provenance": CORRECTION}]),
        _ja(6, "progress", "rejected", _machine("draft-progress-sg1@2026-09-16")),
        _ja(7, "progress", "rejected", _machine("draft-progress-sg0@2026-09-10")),
        _ja(9, "progress", "trusted", _machine("draft-progress-sg0@2026-09-10")),
    ])
    return tmp_path


def test_model_english_maps_tokens_and_paragraphs():
    raw = "Hello  $N,  a $C and $r.$B$BGo now.$b  Really $Gsir:madam;."
    assert tb.model_english(raw) == "Hello {name}, a {class} and {race}.\n\nGo now.\n\nReally $Gsir:madam;."


def test_model_english_reads_client_b_digit_as_a_value():
    # in a client template `$b1` is a spell effect's points per combo point, not a break
    raw = "Finishing moves have a $b1% chance to restore $451438s1 energy.$B$BLasts $d."
    assert tb.model_english(raw, player_tokens=False) == (
        "Finishing moves have a $b1% chance to restore $451438s1 energy.\n\nLasts $d."
    )
    assert tb.model_english("a $b1% chance") == "a\n\n1% chance"  # server text: `$b` is always a break


def test_cut_selects_groups_and_orders(repo, capsys):
    out = repo / "batch.jsonl"
    rows = tb.cut(repo / "data", "progress", 10, out)
    assert [r["targets"] for r in rows] == [[[1, "progress"], [2, "progress"]]]
    assert rows[0]["en"] == "Have you got them, {name}?" and rows[0]["kind"] == "progress"
    assert len(rows[0]["ref"]) == tb.REF_LEN
    # the objective item names of every target, first appearance order, once each
    assert rows[0]["items"] == ["Gnoll Paw", "Sack of Barley", "Tough Wolf Meat"]
    printed = capsys.readouterr().out
    assert "in scope (progress, sg1): 2 lines · 1 unique" in printed
    assert "batch batch.jsonl: 2 lines · 1 unique" in printed


def test_a_style_bump_does_not_requeue_drafted_lines_unless_asked(repo, capsys):
    out = repo / "batch.jsonl"
    rows = tb.cut(repo / "data", "progress", 10, out, redraft_older=True)
    assert [r["targets"] for r in rows] == [[[1, "progress"], [2, "progress"]], [[7, "progress"]], [[9, "progress"]]]
    assert "in scope (progress, sg1, redraft older): 4 lines · 3 unique" in capsys.readouterr().out
    # a current-version draft (6) and hand-written lines stay out either way
    assert all(t[0] not in (3, 4, 5, 6) for r in rows for t in r["targets"])
    (repo / tb.STYLE_GUIDE).write_text("version: sg2\n")
    assert [r["targets"] for r in tb.cut(repo / "data", "progress", 10, out)] == [[[1, "progress"], [2, "progress"]]]
    bumped = tb.cut(repo / "data", "progress", 10, out, redraft_older=True)
    assert [r["targets"] for r in bumped] == [
        [[1, "progress"], [2, "progress"]], [[6, "progress"]], [[7, "progress"]], [[9, "progress"]]]


def test_cut_is_byte_identical_and_respects_size_and_ids(repo, tmp_path):
    a, b = tmp_path / "a.jsonl", tmp_path / "b.jsonl"
    tb.cut(repo / "data", "progress", 10, a)
    tb.cut(repo / "data", "progress", 10, b)
    assert a.read_bytes() == b.read_bytes()
    assert len(tb.cut(repo / "data", "progress", 1, a)) == 1
    ids = tmp_path / "ids.txt"
    ids.write_text("# test\n2\n7\n")
    assert [r["targets"] for r in tb.cut(repo / "data", "progress", 10, a, ids)] == [[[1, "progress"], [2, "progress"]]]
    assert [r["targets"] for r in tb.cut(repo / "data", "progress", 10, a, ids, redraft_older=True)] == [
        [[1, "progress"], [2, "progress"]], [[7, "progress"]]]


def _ok(tmp_path, rows):
    p = tmp_path / "draft.ok.jsonl"
    tb.write_jsonl(p, rows)
    return p


def test_expand_fans_out_per_type(tmp_path):
    ok = _ok(tmp_path, [
        {"ref": "a", "kind": "progress", "ja": "もう手に入れたか、{name}?", "targets": [[1, "progress"], [2, "progress"]]},
        {"ref": "b", "kind": "gossip", "ja": "こんにちは。", "targets": [["0123456789abcdef", "text"]]},
    ])
    counts = tb.expand(ok, "test-sg1", tmp_path / "out", version=1)
    assert counts == {"gossip": 1, "quest": 2}
    quest = tb.read_jsonl(tmp_path / "out" / "test-sg1.quest.jsonl")
    assert quest == [{"id": 1, "field": "progress", "ja": "もう手に入れたか、{name}?"},
                     {"id": 2, "field": "progress", "ja": "もう手に入れたか、{name}?"}]


@pytest.mark.parametrize("name", ["test", "test-sg2", "test-sg1x", "Test-sg1"])
def test_expand_refuses_a_name_without_the_current_style_version(tmp_path, name):
    ok = _ok(tmp_path, [{"ref": "a", "kind": "progress", "ja": "はい。", "targets": [[1, "progress"]]}])
    with pytest.raises(SystemExit, match="sg1"):
        tb.expand(ok, name, tmp_path / "out", version=1)


def test_expanded_file_imports_as_machine_draft(tmp_path, monkeypatch):
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.setattr(import_draft, "data_root", lambda start=None: data)
    (tmp_path / style.STYLE_GUIDE).parent.mkdir(parents=True)
    (tmp_path / style.STYLE_GUIDE).write_text("version: sg1\n")
    ok = _ok(tmp_path, [{"ref": "a", "kind": "progress", "ja": "もう済んだか?", "targets": [[1, "progress"]]}])
    tb.expand(ok, "progress-sg1", tmp_path / "out", version=1)
    draft = tmp_path / "out" / "progress-sg1.quest.jsonl"
    argv = ["draft", "quest", str(draft), "--model", "model-a", "--date", "2026-09-16", "--name", "progress-sg1"]
    assert imp.run(argv) == 0
    line = Store(data).load("quest")[0]
    assert line["ja"] == "もう済んだか?"
    assert line["provenance"]["class"] == "machine"
    assert line["provenance"]["source"] == "draft-progress-sg1@2026-09-16"


def test_style_version_reads_the_guide(repo):
    assert tb.style_version(repo) == 1
    (repo / tb.STYLE_GUIDE).write_text("no version here\n")
    with pytest.raises(SystemExit):
        tb.style_version(repo)


def test_committed_guide_version_matches_a_valid_name(root: Path):
    assert style.name_version(f"progress-sg{tb.style_version(root)}") == tb.style_version(root)


def test_redraft_selects_only_the_listed_lines_not_others_sharing_their_english(repo, tmp_path):
    # lines 1 and 2 share one English; a fix in place for 2 must not re-draft 1
    ids = tmp_path / "ids.txt"
    ids.write_text("2\n")
    rows = tb.cut(repo / "data", "progress", 10, tmp_path / "a.jsonl", ids, redraft=True)
    assert [r["targets"] for r in rows] == [[[2, "progress"]]]


NAMES = {"Gnoll Paw", "Sack of Barley", "Sack of Rye", "Maul", "Holy Spring Water", "Box", "Frozen Rune"}


@pytest.mark.parametrize(
    ("objectives", "items"),
    [
        ("Grimbooze wants a Sack of Barley, a Sack of Rye and a Sack of Barley.", ["Sack of Barley", "Sack of Rye"]),
        ("Bring 10 Gnoll Paws and 5 Frozen Runes to Kyle.", ["Gnoll Paw", "Frozen Rune"]),  # plural last word
        ("Bring 4 Boxes.", ["Box"]),
        ("Bring Holy Spring Water to Grimbooze.", ["Holy Spring Water"]),  # a sentence-initial verb next to it
        ("Kill ogres in Dire Maul.", []),  # part of a longer capitalised name
        ("Take the Maul Tribute. Then report.", []),
        ("Recover the Maul, then report.", ["Maul"]),
        ("Kill 10 gnolls.", []),
    ],
)
def test_objective_items(objectives, items):
    assert objective_items(objectives, NAMES) == items


def test_gossip_rows_have_no_items(repo):
    Store(repo / "data", english=True).save("gossip", [
        {"id": "0123456789abcdef", "field": "text", "en": "Hello there.", "hash": "0123456789abcdef", "src": "gossip"},
    ])
    rows = tb.cut(repo / "data", "gossip", 10, repo / "g.jsonl")
    assert rows and "items" not in rows[0]


@pytest.mark.parametrize(
    ("en", "prose"),
    [
        ("Stratholme", False),
        ("Dire Maul", False),
        ("Auction House", False),
        ("Herbalism", False),
        ("GOSSIP_OPTION_SPIRITGUIDE", False),
        ("Thalia Amberhide:", False),
        ("$G Sir : Ma'am;", False),
        ("Ahn'Qiraj $2283W", False),
        ("The Bank", False),
        ("Yes?", True),
        ("DIE!", True),
        ("Tragic...", True),
        ("Greetings, {name}.", True),
        ("{name}", True),
        ("Ma'am, Stratholme awaits", True),
        ("$gHello there, handsome:Oh my!;", True),
    ],
)
def test_has_prose(en, prose):
    assert tb.has_prose(en) is prose


def test_cut_skips_english_that_is_only_names(tmp_path):
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    (tmp_path / "docs" / "content").mkdir(parents=True)
    (tmp_path / "docs" / "content" / "translation-style-guide.md").write_text("version: sg1\n")
    data = tmp_path / "data"
    Store(data, english=True).save("gossip", [
        _en("aaaaaaaaaaaaaaaa", "text", "Stratholme"),
        _en("bbbbbbbbbbbbbbbb", "text", "Tell me about Dire Maul."),
        _en("cccccccccccccccc", "text", "Yes, $C?"),
        _en("dddddddddddddddd", "text", "Auction House"),
    ])
    rows = tb.cut(data, "gossip", 10, tmp_path / "batch.jsonl")
    assert [r["targets"] for r in rows] == [[["bbbbbbbbbbbbbbbb", "text"]], [["cccccccccccccccc", "text"]]]


def test_redraft_reselects_listed_drafted_lines_but_never_hand_written(repo, tmp_path, capsys):
    out, ids = tmp_path / "batch.jsonl", tmp_path / "ids.txt"
    ids.write_text("3\n4\n6\n9\n")
    # 6 (a current-version draft) and 9 (trusted machine) come back; 3 and 4 (hand-written) never do
    assert [r["targets"] for r in tb.cut(repo / "data", "progress", 10, out, ids, redraft=True)] == [
        [[6, "progress"]], [[9, "progress"]]]
    assert "in scope (progress, sg1, redraft)" in capsys.readouterr().out
    assert tb.cut(repo / "data", "progress", 10, out, ids) == []
    with pytest.raises(SystemExit, match="--redraft needs --ids"):
        tb.cut(repo / "data", "progress", 10, out, redraft=True)



# ── book pages ─────────────────────────────────────────────────────────────────────

def _page(id_, en):
    return {"id": id_, "field": "text", "en": en, "hash": hashing.key(normalize_v1(en)), "src": "vmangos@13b49dc"}


HTML_PAGE = '<HTML>\n<BODY>\n<BR/>\n<H1 align="center">\nIn Memory\n</H1>\n<P>\nRest well,  friend.\n</P>\n</BODY>\n</HTML>'


@pytest.fixture
def pages(tmp_path):
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    (tmp_path / "docs" / "content").mkdir(parents=True)
    (tmp_path / "docs" / "content" / "translation-style-guide.md").write_text("version: sg4\n")
    data = tmp_path / "data"
    Store(data, english=True).save("book", [
        _page(15, "Hello Morgan,\n\nBusiness is brisk.$B$BThanks, $N."),  # no line → selected
        _page(16, HTML_PAGE),                                            # HTML page → selected as is
        _page(17, "Missing Text"),                                       # bare label → skipped
        _page(18, "Trusted already."),                                   # trusted test line → skipped
        _page(19, "Drafted sg3."),                                       # older style → only with --redraft-older
        _page(20, "Rest well,  friend."),                                # not HTML: spaces collapse
        _page(21, "Hello Morgan,\n\nBusiness is brisk.$B$BThanks, $n."), # same drafter English as 15
        _page(22, "Rest well,\n\nfriend."),  # only whitespace differs from 20: one page hash, one row
    ])
    Store(data).save("book", [
        _ja(18, "text", "trusted", _machine("draft-book-screens@2026-09-15")),
        _ja(19, "text", "trusted", _machine("draft-book-sg3@2026-09-15")),
    ])
    return data


def test_cut_book_selects_groups_and_keeps_html(pages, tmp_path, capsys):
    rows = tb.cut(pages, "book", 10, tmp_path / "b.jsonl")
    assert [r["targets"] for r in rows] == [[[15, "text"], [21, "text"]], [[16, "text"]], [[20, "text"], [22, "text"]]]
    assert rows[0]["en"] == "Hello Morgan,\n\nBusiness is brisk.\n\nThanks, {name}."
    assert rows[1]["en"] == HTML_PAGE.replace("well,  friend", "well, friend")  # tags and single newlines kept
    assert all(r["kind"] == "book" and "items" not in r for r in rows)
    assert "in scope (book, sg4): 5 lines · 3 unique" in capsys.readouterr().out
    older = tb.cut(pages, "book", 10, tmp_path / "o.jsonl", redraft_older=True)
    assert [19, "text"] in [t for r in older for t in r["targets"]]
    assert [18, "text"] in [t for r in older for t in r["targets"]]  # the pre-style test line is older too


def test_cut_book_ids_are_integers(pages, tmp_path):
    ids = tmp_path / "ids.txt"
    ids.write_text("16\n")
    assert [r["targets"] for r in tb.cut(pages, "book", 10, tmp_path / "b.jsonl", ids)] == [[[16, "text"]]]
    assert "trainer_greeting" not in tb.KINDS  # the kind is gone


def test_cut_book_is_byte_identical_and_refuses_held_back(pages, tmp_path):
    a, b = tmp_path / "a.jsonl", tmp_path / "b.jsonl"
    tb.cut(pages, "book", 10, a)
    tb.cut(pages, "book", 10, b)
    assert a.read_bytes() == b.read_bytes()
    with pytest.raises(SystemExit, match="--held-back"):
        tb.cut(pages, "book", 10, a, held_back=True)


def test_expand_and_import_book(tmp_path, monkeypatch):
    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.setattr(import_draft, "data_root", lambda start=None: data)
    (tmp_path / style.STYLE_GUIDE).parent.mkdir(parents=True)
    (tmp_path / style.STYLE_GUIDE).write_text("version: sg4\n")
    ok = _ok(tmp_path, [
        {"ref": "a", "kind": "book", "ja": "やあ、Morgan。", "targets": [[15, "text"], [21, "text"]]},
    ])
    assert tb.expand(ok, "pages-sg4", tmp_path / "out", version=4) == {"book": 2}
    assert tb.read_jsonl(tmp_path / "out" / "pages-sg4.book.jsonl")[0] == {"id": 15, "field": "text", "ja": "やあ、Morgan。"}
    draft = tmp_path / "out" / "pages-sg4.book.jsonl"
    argv = ["draft", "book", str(draft), "--model", "model-a", "--date", "2026-09-16", "--name", "pages-sg4"]
    assert imp.run(argv) == 0
    line = Store(data).load("book")[0]
    assert line["provenance"]["class"] == "machine"
    assert line["provenance"]["source"] == "draft-pages-sg4@2026-09-16"


def test_redraft_of_a_book_page_takes_the_pages_sharing_its_english_hash(pages, tmp_path):
    # re-drafting one page alone would give its twin other Japanese and stop `generate`
    ids = tmp_path / "ids.txt"
    ids.write_text("22\n")
    rows = tb.cut(pages, "book", 10, tmp_path / "r.jsonl", ids, redraft=True)
    assert [r["targets"] for r in rows] == [[[20, "text"], [22, "text"]]]


# --- the client-template kinds, and the two scope filters ---

FOREVER = "db2@1.60.1.69913"
VANILLA = "wago@1.15.9.69722"


def _client_en(id_, field, en, src):
    return {"id": id_, "field": field, "en": en, "hash": "0" * 16, "src": src}


@pytest.fixture
def client(tmp_path):
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    (tmp_path / "docs" / "content").mkdir(parents=True)
    (tmp_path / "docs" / "content" / "translation-style-guide.md").write_text("# guide\n\nversion: sg1\n")
    data = tmp_path / "data"
    Store(data, english=True).save("item", [
        _client_en(117, "description", "Restores $o1 health over $d.", FOREVER),
        _client_en(4540, "description", "Restores $o1 health over $d.", FOREVER),  # same English → grouped
        _client_en(159, "description", "Quenches your thirst.", FOREVER),
        _client_en(9999, "description", "Only Classic Era ships me.", VANILLA),    # Vanilla: not drafted
        _client_en(118, "name", "Minor Healing Potion", FOREVER),                  # other field
    ])
    Store(data, english=True).save("spell", [
        _client_en(133, "description", "Hurls a fiery ball causing $s1 Fire damage.", FOREVER),
        _client_en(20000, "description", "An internal proc nobody sees.", FOREVER),
        _client_en(133, "aura", "Burning for $o1 damage.", FOREVER),
    ])
    (tmp_path / "visible.txt").write_text("# header\nitem,skill 133\n", encoding="utf-8")
    return tmp_path


def test_cut_item_description_keeps_only_the_forever_pull(client, capsys):
    out = client / "b.jsonl"
    rows = tb.cut(client / "data", "item_description", 10, out, src=FOREVER)
    assert [r["en"] for r in rows] == ["Restores $o1 health over $d.", "Quenches your thirst."]
    assert rows[0]["targets"] == [[117, "description"], [4540, "description"]]  # one draft serves both
    assert all(r["kind"] == "item_description" for r in rows)
    assert "Only Classic Era ships me." not in capsys.readouterr().out


def test_cut_gives_a_template_row_its_value_slot_count(client):
    rows = tb.cut(client / "data", "item_description", 10, client / "b.jsonl", src=FOREVER)
    slots = {r["en"]: r["slots"] for r in rows}
    assert slots == {"Restores $o1 health over $d.": 2, "Quenches your thirst.": 0}


def test_cut_refuses_a_src_no_english_has(client):
    with pytest.raises(SystemExit, match="no item English has src starting"):
        tb.cut(client / "data", "item_description", 10, client / "b.jsonl", src="db2@9.9.9.99999")


def test_cut_spell_description_can_be_scoped_to_the_visible_set(client):
    out = client / "b.jsonl"
    unscoped = tb.cut(client / "data", "spell_description", 10, out, src=FOREVER)
    assert len(unscoped) == 2  # the proc is in scope without the filter
    scoped = tb.cut(client / "data", "spell_description", 10, out, src=FOREVER, visible=client / "visible.txt")
    assert [r["targets"] for r in scoped] == [[[133, "description"]]]
    assert "proc" not in scoped[0]["en"]


def test_cut_spell_aura_is_its_own_kind(client):
    rows = tb.cut(client / "data", "spell_aura", 10, client / "b.jsonl", src=FOREVER)
    assert [(r["kind"], r["targets"], r["slots"]) for r in rows] == [
        ("spell_aura", [[133, "aura"]], 1)
    ]


def test_expand_fans_the_template_kinds_out_to_their_types(client, tmp_path):
    ok = tmp_path / "ok.jsonl"
    tb.write_jsonl(ok, [
        {"ref": "a", "kind": "item_description", "en": "x", "targets": [[117, "description"]],
         "ja": "$N2秒かけてhealthを$N1回復します。"},
        {"ref": "b", "kind": "spell_aura", "en": "y", "targets": [[133, "aura"]], "ja": "$N1のダメージ。"},
    ])
    counts = tb.expand(ok, "tooltip-sg1", tmp_path, 1)
    assert counts == {"item": 1, "spell": 1}
    assert tb.read_jsonl(tmp_path / "tooltip-sg1.item.jsonl") == [
        {"id": 117, "field": "description", "ja": "$N2秒かけてhealthを$N1回復します。"}
    ]
    assert tb.read_jsonl(tmp_path / "tooltip-sg1.spell.jsonl") == [
        {"id": 133, "field": "aura", "ja": "$N1のダメージ。"}
    ]


def test_cut_keeps_branch_rows_and_expands_inclusions(client, capsys):
    """ADR-043: conditional and inclusion rows are drafted. A conditional is a branch row: `slots` counts
    the whole template, every branch's values included, and `branches` the variants. An inclusion is spliced
    in, so the drafter reads the line the client shows; an included spell the tables lack leaves the line out,
    listed with its reason in `<batch>.dropped.jsonl`."""
    data = client / "data"
    Store(data, english=True).save("spell", [
        _client_en(1, "description", "Absorbs $s1 damage$?s11094[ and reflects $s2%][]. Lasts $d.", FOREVER),
        _client_en(2, "description", "$@spelldesc434 It also restores $s1 mana.", FOREVER),
        _client_en(3, "description", "Coats a weapon with poison for ${$m1/60} minutes.", FOREVER),
        _client_en(4, "description", "Deals $s1 Fire damage.", FOREVER),
        _client_en(5, "description", "$@spelldesc4 Also $@spellicon4 $@spellname4.", FOREVER),
        _client_en(4, "name", "Scorch", FOREVER),
    ])
    rows = tb.cut(data, "spell_description", 10, client / "b.jsonl", src=FOREVER)
    by = {r["targets"][0][0]: r for r in rows}
    assert sorted(by) == [1, 3, 4, 5]
    assert (by[1]["slots"], by[1]["durations"], by[1]["branches"]) == (3, 1, 2)
    assert by[3]["slots"] == 1  # arithmetic counts as the one number it prints
    assert by[5]["en"] == "Deals $s1 Fire damage. Also $I1 Scorch."
    assert (by[5]["slots"], by[5]["icons"]) == (1, 1)
    assert tb.read_jsonl(client / "b.dropped.jsonl") == [
        {"id": 2, "field": "description", "reason": "missing_included_spell:434"}
    ]
    assert "1 lines listed in b.dropped.jsonl" in capsys.readouterr().out


# --- the quest text the client's own cache serves (title / objectives / description) ---


def test_the_quest_client_kinds_select_their_field_and_carry_the_objective_items(repo):
    """These join `progress` / `completion`, which only VMaNGOS has. Server-written prose either way, so no
    `slots` and no placeholders: a quest's numbers are in the text the server sent."""
    data = repo / "data"
    Store(data, english=True).save("quest", [
        {"id": 1, "field": "title", "en": "A New Threat to the Kingdom", "hash": "0" * 16, "src": "wdb@1.60.1.69913"},
        {"id": 1, "field": "objectives", "en": "Bring 3 Gnoll Paws to Grimbooze.", "hash": "1" * 16,
         "src": "wdb@1.60.1.69913"},
        {"id": 1, "field": "description", "en": "The troggs are at it again, $N.", "hash": "2" * 16,
         "src": "wdb@1.60.1.69913"},
        {"id": 2, "field": "title", "en": "Only Vanilla has me", "hash": "3" * 16, "src": "pfquest@7786596"},
        _en(1, "objectives", "Bring 3 Gnoll Paws and a Sack of Barley to Grimbooze."),
    ])
    for kind, field, en in (
        ("quest_title", "title", "A New Threat to the Kingdom"),
        ("quest_objectives", "objectives", "Bring 3 Gnoll Paws to Grimbooze."),
        ("quest_description", "description", "The troggs are at it again, {name}."),
    ):
        rows = tb.cut(data, kind, 10, repo / "b.jsonl", src="wdb@1.60.1.69913")
        assert [r["en"] for r in rows] == [en], kind
        assert rows[0]["targets"] == [[1, field]]
        # a slot count, but not a client template: no `$D`, and `$n`/`$r` stay the player's
        assert isinstance(rows[0]["slots"], int)
        assert kind not in tb.TEMPLATE_KINDS and kind in tb.SLOT_KINDS
        assert "items" in rows[0]  # a quest kind: the objective item names, for the drafter
    # `--src` keeps the Vanilla-only title out, as it does for the tooltip kinds
    titles = tb.cut(data, "quest_title", 10, repo / "b.jsonl")
    assert sorted(r["en"] for r in titles) == ["A New Threat to the Kingdom", "Only Vanilla has me"]


def test_the_quest_client_kinds_are_styled_and_not_held_back(repo):
    """Every quest field a drafter writes is styled, so `import draft` checks the style version on it; and
    `--held-back` reaches all three (the redraft of rejected hand-written lines)."""
    from wfj.core import style

    assert style.STYLED_FIELDS["quest"] == {
        "title", "objectives", "description", "progress", "completion"
    }
    for kind in ("quest_title", "quest_objectives", "quest_description"):
        assert kind not in tb.TEMPLATE_KINDS and kind in tb.HELD_BACK_KINDS


def test_a_quest_row_carries_its_value_slot_count(repo):
    """A quest objective reads `Collect $1oa Lady's Tear Moss.` in the text the server sent and
    shows a number to the player, so a draft writes `$N<k>` and the addon fills it from the live line.
    Literal numbers count too: `Kill 7 Nightsabers` is one slot a draft may write as 7 or as `$N1`."""
    data = repo / "data"
    Store(data, english=True).save("quest", [
        {"id": 1, "field": "objectives", "en": "Collect $1oa Lady's Tear Moss.", "hash": "0" * 16,
         "src": "wdb@1.60.1.69913"},
        {"id": 2, "field": "objectives", "en": "Kill 7 Nightsabers and 4 Boars.", "hash": "1" * 16,
         "src": "wdb@1.60.1.69913"},
        {"id": 3, "field": "objectives", "en": "Speak to Vrang in the inn.", "hash": "2" * 16,
         "src": "wdb@1.60.1.69913"},
    ])
    rows = {r["targets"][0][0]: r for r in tb.cut(data, "quest_objectives", 10, repo / "b.jsonl")}
    assert rows[1]["slots"] == 1 and rows[2]["slots"] == 2 and rows[3]["slots"] == 0
    assert "quest_objectives" in tb.SLOT_KINDS and "quest_objectives" not in tb.TEMPLATE_KINDS


def test_title_names_are_what_the_corpus_never_writes_in_lower_case():
    # title case capitalises every word, so capitals say nothing about names
    vocab = {"a", "gift", "of", "the", "call", "fire", "taming", "beast", "break", "rediscover", "light", "study"}
    known = {"A Study of the Light"}
    assert tb.title_names("Aetheen of the Gales", vocab, known) == ["Aetheen", "Gales"]
    assert tb.title_names("Call of Fire", vocab, known) == []
    assert tb.title_names("Taming the Beast", vocab, known) == []
    assert tb.title_names("Rediscovering the Light", vocab, known) == []  # an inflection of a common word
    assert tb.title_names("Lee's Test", vocab | {"test"}, known) == ["Lee"]  # the possessive is not the name
    assert tb.title_names("A Study of the Light", vocab, known) == ["A Study of the Light"]  # an item name


def test_a_title_case_quest_title_is_cut_and_a_placeholder_quest_is_not(repo):
    """Title case capitalises every word, so a title with no lower-case word ("Blackrock Menace") is
    still a title to translate; `has_prose` would have called it a bare label and 1,413 titles were never
    drafted. A placeholder quest (`<UNUSED>`, `<NYI> <TXT> …`, `REUSE`) is never drafted, in any field."""
    data = repo / "data"
    Store(data, english=True).save("quest", [
        {"id": 1, "field": "title", "en": "Blackrock Menace", "hash": "0" * 16, "src": "wdb@1.15.9.69722"},
        {"id": 2, "field": "title", "en": "<UNUSED> Old Quest", "hash": "1" * 16, "src": "wdb@1.15.9.69722"},
        {"id": 2, "field": "description", "en": "Nothing to see here.", "hash": "2" * 16, "src": "wdb@1.15.9.69722"},
        {"id": 3, "field": "title", "en": "REUSE", "hash": "3" * 16, "src": "wdb@1.15.9.69722"},
    ])
    assert [r["en"] for r in tb.cut(data, "quest_title", 10, repo / "b.jsonl")] == ["Blackrock Menace"]
    assert tb.cut(data, "quest_description", 10, repo / "b.jsonl") == []


def test_title_names_drop_a_possessive_apostrophe():
    assert tb.title_names("Bingles' Missing Supplies", {"missing", "supplies"}, set()) == ["Bingles"]
    assert tb.title_names("Lee's Revenge", {"revenge"}, set()) == ["Lee"]


# --- an objective that is only a name is never cut ---


def test_cut_leaves_out_the_objectives_listed_as_names(tmp_path):
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    (tmp_path / "docs" / "content").mkdir(parents=True)
    (tmp_path / "docs" / "content" / "translation-style-guide.md").write_text("version: sg1\n")
    data = tmp_path / "data"
    Store(data, english=True).save("objective", [
        _en(381485, "text", "Flame of Hillsbrad"),
        _en(381486, "text", "Flame of Silverpine"),
        _en(380001, "text", "Archive Burned"),
    ])
    out = tmp_path / "batch.jsonl"
    # without the list, cut stops with a clear message instead of drafting every name
    with pytest.raises(SystemExit, match="objective_names.txt is missing"):
        tb.cut(data, "objective", 10, out)
    (tmp_path / "pipeline").mkdir()
    (tmp_path / "pipeline" / "objective_names.txt").write_text(
        "# names only\n381485  # Flame of Hillsbrad\n  # an indented comment\n  381486  # Flame of Silverpine\n"
    )
    assert tb.objective_names(tmp_path) == {381485: "Flame of Hillsbrad", 381486: "Flame of Silverpine"}
    assert [r["targets"] for r in tb.cut(data, "objective", 10, out)] == [[[380001, "text"]]]


def test_objective_names_reads_an_indented_comment_as_a_comment(tmp_path):
    """The `#` test runs on the stripped line; an indented comment line never reaches int()."""
    (tmp_path / "pipeline").mkdir()
    (tmp_path / "pipeline" / "objective_names.txt").write_text("    # indented\n\t# tabbed\n381485 # Flame\n")
    assert tb.objective_names(tmp_path) == {381485: "Flame"}
    assert tb.objective_names(tmp_path / "nowhere") == {}  # the partition test's reader: no file, none listed


# ── expand writes the readings batch beside the import files ──


def test_expand_writes_a_words_file_for_rows_with_words(tmp_path):
    from wfj.core import readings

    words = [["森", "もり"]]
    ok = _ok(tmp_path, [
        {"ref": "a", "kind": "progress", "ja": "森へ行け。", "targets": [[1, "progress"], [2, "progress"]],
         "words": words},
        {"ref": "b", "kind": "gossip", "ja": "森だ。", "targets": [["0123456789abcdef", "text"]]},
    ])
    counts = tb.expand(ok, "test-sg1", tmp_path / "out", version=1)
    assert counts == {"gossip": 1, "quest": 2, "words": 2}
    rows = tb.read_jsonl(tmp_path / "out" / "test-sg1.words.jsonl")
    h = readings.ja_hash("森へ行け。")
    assert rows == [
        {"type": "quest", "id": 1, "field": "progress", "ja_hash": h, "words": words},
        {"type": "quest", "id": 2, "field": "progress", "ja_hash": h, "words": words},
    ]


def test_expand_without_words_writes_no_words_file(tmp_path):
    ok = _ok(tmp_path, [{"ref": "a", "kind": "progress", "ja": "森へ行け。", "targets": [[1, "progress"]]}])
    assert tb.expand(ok, "test-sg1", tmp_path / "out", version=1) == {"quest": 1}
    assert sorted(p.name for p in (tmp_path / "out").iterdir()) == ["test-sg1.quest.jsonl"]


# ── the quest cache's area text is its own kind ──


def test_cut_area_selects_undrafted_lines_and_expand_writes_the_area_file(tmp_path):
    (tmp_path / "data").mkdir()
    (tmp_path / "data" / "SCHEMA").write_text("1\n")
    (tmp_path / "docs" / "content").mkdir(parents=True)
    (tmp_path / "docs" / "content" / "translation-style-guide.md").write_text("version: sg1\n")
    data = tmp_path / "data"
    # the name-only area texts are listed, never cut (a listed quest is left out)
    (tmp_path / "pipeline").mkdir()
    (tmp_path / "pipeline" / "area_names.txt").write_text("# name-only\n9999  # Goblin Transponder\n")
    Store(data, english=True).save("quest", [
        _en(62, "title", "The Fargodeep Mine"), _en(2904, "title", "A Fine Mess"), _en(490, "title", "<UNUSED>"),
    ])
    Store(data, english=True).save("area", [
        _en(62, "text", "Scout through the Fargodeep Mine"),
        _en(2904, "text", "Kernobee Rescue"),       # title case, no lower-case word: still cut (like objective)
        _en(490, "text", "Scout the placeholder"),  # a placeholder quest's area text is never drafted
        _en(3000, "text", "Drafted already"),
    ])
    Store(data).save("area", [_ja(3000, "text", "rejected", _machine("draft-area-sg1@2026-09-27"))])
    assert tb.KINDS["area"] == ("area", "text") and "area" in tb.TITLE_CASE_KINDS
    rows = tb.cut(data, "area", 10, tmp_path / "batch.jsonl")
    assert [(r["kind"], r["targets"]) for r in rows] == [("area", [[62, "text"]]), ("area", [[2904, "text"]])]
    assert style.STYLED_FIELDS["area"] == frozenset({"text"})
    ok = _ok(tmp_path, [{"ref": rows[0]["ref"], "kind": "area", "ja": "Fargodeep Mineを偵察する",
                         "targets": rows[0]["targets"]}])
    assert tb.expand(ok, "area-sg1", tmp_path / "out", version=1) == {"area": 1}
    assert tb.read_jsonl(tmp_path / "out" / "area-sg1.area.jsonl") == [
        {"id": 62, "field": "text", "ja": "Fargodeep Mineを偵察する"}]


def test_an_area_draft_imports_as_machine_and_the_lint_accepts_the_kind(tmp_path, monkeypatch):
    """`import-draft TYPE=area` takes the expanded file; the lint checks an area row like an
    objective's (title case: the names `cut` found must be kept)."""
    from wfj.dev import translate_lint

    data = tmp_path / "data"
    data.mkdir()
    (data / "SCHEMA").write_text("1\n")
    monkeypatch.setattr(import_draft, "data_root", lambda start=None: data)
    (tmp_path / style.STYLE_GUIDE).parent.mkdir(parents=True)
    (tmp_path / style.STYLE_GUIDE).write_text("version: sg1\n")
    batch = tmp_path / "b.jsonl"
    tb.write_jsonl(batch, [{"ref": "a", "kind": "area", "en": "Kernobee Rescue", "targets": [[2904, "text"]],
                            "names": ["Kernobee"]}])
    draft = tmp_path / "b.draft.jsonl"
    tb.write_jsonl(draft, [{"ref": "a", "ja": "Kernobeeの救出"}])
    assert translate_lint.main([str(batch), str(draft)]) == 0
    ok = tmp_path / "b.draft.ok.jsonl"
    tb.expand(ok, "area-sg1", tmp_path / "out", version=1)
    argv = ["draft", "area", str(tmp_path / "out" / "area-sg1.area.jsonl"), "--model", "model-a",
            "--date", "2026-09-27", "--name", "area-sg1"]
    assert imp.run(argv) == 0
    line = Store(data).load("area")[0]
    assert (line["id"], line["field"], line["ja"]) == (2904, "text", "Kernobeeの救出")
    assert line["provenance"]["source"] == "draft-area-sg1@2026-09-27"
    tb.write_jsonl(draft, [{"ref": "a", "ja": "カーノビーの救出"}])  # the name must stay English
    assert translate_lint.main([str(batch), str(draft)]) == 1


@pytest.fixture
def flavour(client):
    data = client / "data"
    english = Store(data, english=True)
    english.save("item", english.load("item") + [
        _client_en(9532, "description", "Made With Love", FOREVER),
        _client_en(269327, "description", "Umbrinoth", FOREVER),
        _client_en(21146, "description", "-Hinterlands", FOREVER),
        _client_en(5000, "name", "Umbrinoth", FOREVER),
    ])
    english.save("spell", english.load("spell") + [
        _client_en(324, "name", "Lightning Shield", FOREVER),
        _client_en(21991, "aura", "Lightning Shield", FOREVER),
        _client_en(9179, "aura", "Stunned", FOREVER),
    ])
    english.save("unit", [_client_en(1, "name", "Hinterlands", FOREVER)])
    return client


def test_cut_drafts_tooltip_flavour_text_written_in_title_case(flavour):
    """A tooltip line with no lower-case word is flavour text, not a bare label to skip: it is cut, marked
    `title_case` so the lint checks its `names`, and a sentence row is unchanged."""
    rows = {r["en"]: r for r in tb.cut(flavour / "data", "item_description", 20, flavour / "b.jsonl", src=FOREVER)}
    assert rows["Made With Love"]["title_case"] is True and "name_only" not in rows["Made With Love"]
    assert "title_case" not in rows["Quenches your thirst."] and "names" not in rows["Quenches your thirst."]
    auras = {r["en"]: r for r in tb.cut(flavour / "data", "spell_aura", 20, flavour / "b.jsonl", src=FOREVER)}
    assert auras["Stunned"]["title_case"] is True and "name_only" not in auras["Stunned"]


def test_cut_marks_a_tooltip_line_that_is_only_a_name(flavour):
    rows = {r["en"]: r for r in tb.cut(flavour / "data", "item_description", 20, flavour / "b.jsonl", src=FOREVER)}
    assert rows["Umbrinoth"]["name_only"] is True
    assert rows["-Hinterlands"]["name_only"] is True  # a zone in a list, with its dash
    auras = {r["en"]: r for r in tb.cut(flavour / "data", "spell_aura", 20, flavour / "b.jsonl", src=FOREVER)}
    assert auras["Lightning Shield"]["name_only"] is True  # a spell name
