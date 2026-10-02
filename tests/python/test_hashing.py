from pathlib import Path

from wfj.core.hashing import M1, M2, MAX_INTERMEDIATE, P1, P2, hash32x2, key, key_from_pair
from wfj.core.normalize import normalize_v1


def test_empty():
    assert hash32x2("") == (0, 0)
    assert key("") == "0000000000000000"


def test_single_byte():
    assert hash32x2("a") == (97, 97)


def test_moduli_are_below_2_32_and_intermediates_bounded():
    assert P1 < 2**32 and P2 < 2**32
    assert (P1 - 1) * M1 + 255 < MAX_INTERMEDIATE
    assert (P2 - 1) * M2 + 255 < MAX_INTERMEDIATE


def test_key_format():
    assert key_from_pair(1, 2) == "0000000100000002"
    assert len(key("日本語")) == 16


def test_vectors_hash(vectors):
    for v in vectors:
        h1, h2 = hash32x2(v["norm"])
        assert (h1, h2) == (v["h1"], v["h2"]), v["id"]
        assert key_from_pair(h1, h2) == v["key"], v["id"]


def test_a_client_templates_value_codes_are_not_player_tokens():
    """`$n`, `$c` and `$r` are the player only in text the SERVER writes. In a client template they
    are values the client fills in (`within $r yards` is a radius, `$n balls of lightning` a count), and a
    translation carrying `{race}` there would print the player's race where a number belongs."""
    radius = "Dying inflicts $s1 Holy damage to all enemies within $r yards."
    count = "The caster is surrounded by $n balls of lightning."
    assert normalize_v1(radius) == "Dying inflicts $s1 Holy damage to all enemies within {race} yards."
    assert normalize_v1(radius, player_tokens=False) == radius
    assert "{name}" in normalize_v1(count)
    assert normalize_v1(count, player_tokens=False) == count
    # server text is unchanged: there the codes really are the player
    greeting = "Greetings, $N the $C of the $R."
    assert normalize_v1(greeting) == "Greetings, {name} the {class} of the {race}."
    # everything else about the canon is untouched by the switch
    for raw in ("|cff00ff00Hi|r  there", "$Bline$btwo", "one  two", "$Gsir:madam;, hello", "７つ"):
        assert normalize_v1(raw, player_tokens=False) == normalize_v1(raw), raw


def test_the_committed_client_english_keeps_its_value_codes():
    """The lines this changed: their stored English must still carry the raw code, not a token, and every
    client-table line (either client, `db2@` or `wago@`) is hashed with the client-template canon.

    The Classic Era client text is imported with both clients, so no line is left on the old canon.
    The check is on the hash itself, not on a code pattern: `$RAP` (ranged attack power) is no `$r` code by
    that pattern, yet the old canon hashed it as `{race}AP` (spells 409552 and 409554)."""
    import glob
    import json
    import re

    code = re.compile(r"\$[nNcCrR](?![a-zA-Z0-9])")
    root = Path(__file__).resolve().parents[2] / "data" / "english"
    kept = tokenised = 0
    old: list[tuple[str, int, str]] = []
    for type_ in ("item", "spell"):
        for path in glob.glob(str(root / type_ / "*.jsonl")):
            for line in Path(path).read_text(encoding="utf-8").splitlines():
                if not line.strip():
                    continue
                row = json.loads(line)
                if code.search(row["en"]):
                    kept += 1
                if row["src"].startswith(("db2@", "wago@")) and row["hash"] != key(
                    normalize_v1(row["en"], player_tokens=False)
                ):
                    old.append((type_, row["id"], row["field"]))
                if row["field"] in ("description", "aura") and "{race}" in row["en"]:
                    tokenised += 1
    assert kept == 108, kept  # on build 70170 (105 on 70009), after the served step drops the ids Forever lacks
    assert old == [], old
    assert tokenised == 0


def test_a_quest_line_filled_from_live_values_ships_a_masked_h1():
    """`Collect $1oa Moss` is hashed with its numbers masked, and the addon masks the live
    line's digits the same way (collector_spec holds the Lua side to this key), so the count never reads as a
    rewording and a rewording still does."""
    from wfj.cmd.generate import masked_fields
    from wfj.core.normalize import mask_values
    from wfj.emit import lua_writer

    en = "Collect $1oa Lady's Tear Moss, $N."
    assert mask_values(normalize_v1(en)) == "Collect # Lady's Tear Moss, {name}."
    assert key(mask_values(normalize_v1(en)))[:8] == "782db28c"
    masked = masked_fields([{"id": 7, "field": "objectives", "en": en, "hash": "1" * 16}])
    line = {"id": 7, "field": "objectives", "ja": "Lady's Tear Mossを$N1個集める。", "status": "trusted",
            "english": {"hash": "1" * 16, "src": "wdb@1.60.1.69913"}}
    row = lua_writer.rows("quest", [line], {}, masked)[7]
    assert "0x782db28c" in row
    plain = dict(line, ja="Lady's Tear Mossを集める。")  # no placeholder: the plain English hash
    assert "0x11111111" in lua_writer.rows("quest", [plain], {}, masked)[7]
    # a STALE line keeps the hash it was checked against (ADR-003): masked over the new English would match the
    # reworded live line and drop the marker, so the drafted hash ships and the live check still marks it
    stale = dict(line, status="stale", english={"hash": "2" * 16, "src": "wdb@1.60.1.69913"})
    row = lua_writer.rows("quest", [stale], {}, masked)[7]
    assert "0x22222222" in row and "0x782db28c" not in row


def test_the_mask_reads_a_number_with_separators_as_one():
    from wfj.core.normalize import mask_values

    assert mask_values("Collect $1oa or 1,000 or 2.5 of 7 things.") == "Collect # or # or # of # things."
    assert mask_values("Slay $1997w wolves.") == "Slay # wolves."


def test_one_place_decides_the_client_template_canon():
    """The hash, the batch English and the checks read a client template the same way."""
    from wfj.core.normalize import normalize_for

    en = "Fear all Demons within $r yards, surrounded by $n balls."
    assert normalize_for("spell", en) == normalize_v1(en, player_tokens=False)
    assert "{race}" not in normalize_for("item", en)
    assert "{race}" in normalize_for("quest", en)  # server text: `$r` is the player
