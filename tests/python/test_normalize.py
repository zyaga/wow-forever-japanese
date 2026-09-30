from wfj.core.normalize import Player, normalize_v1, replace_word


def test_markup_link_keeps_label():
    assert normalize_v1("Bring |Hitem:1|h[Linen]|h now") == "Bring [Linen] now"


def test_markup_texture_and_color_removed():
    assert normalize_v1("|cffffd100Q|r |TIcon:16|t x") == "Q x"


def test_pipe_n_and_dollar_b_become_whitespace():
    assert normalize_v1("a|nb$Bc$bd") == "a b c d"


def test_fullwidth_digits_fold():
    assert normalize_v1("１０ vs 10") == "10 vs 10"


def test_placeholders():
    assert normalize_v1("$N $n $C $c $R $r") == "{name} {name} {class} {class} {race} {race}"


def test_gender_branch_first():
    assert normalize_v1("$Gsir:madam; and $gbrother:sister;") == "sir and brother"


def test_whitespace_collapse_and_strip():
    assert normalize_v1("  a \t b \r\n c  ") == "a b c"


def test_nfc():
    assert normalize_v1("Café") == "Café"


def test_player_whole_word_exact_case():
    p = Player(name="Reyn", class_="Hunter", race="Night Elf")
    assert normalize_v1("Reyn's bow, Hunter of the Night Elf.", p) == "{name}'s bow, {class} of the {race}."
    assert normalize_v1("AndrewDrew hunter night elf", p) == "AndrewDrew hunter night elf"


def test_player_short_token_never_replaced():
    assert replace_word("Al is here. Alliance too.", "Al", "{name}") == "Al is here. Alliance too."


def test_player_substring_not_replaced():
    assert replace_word("Marketplace, Mark.", "Mark", "{name}") == "Marketplace, {name}."


def test_vectors_norm(vectors):
    for v in vectors:
        p = Player(v["player"]["name"], v["player"]["class"], v["player"]["race"]) if v["player"] else None
        assert normalize_v1(v["raw"], p) == v["norm"], v["id"]
