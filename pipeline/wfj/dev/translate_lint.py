"""Check a drafted translation batch before it is expanded and imported.

    python -m wfj.dev.translate_lint BATCH DRAFT [--allowlist PATH] [--glossary PATH] [--not-names PATH]

Every batch row must have exactly one draft row, and every draft row a batch row. A draft fails with one
reason per problem:

- `missing` / `duplicate` / `unknown_ref`: the draft does not cover the batch one to one
- `not_japanese`: no kana or kanji, or a simplified-only character (`language.is_japanese`). An English
  line that is only dots (`...`) may stay only dots (`……`), and a tooltip row `cut` marked `name_only`
  (`Umbrinoth`) may keep exactly its English.
- `tokens:<english>→<japanese>`: the `{name}` / `{class}` / `{race}` tokens differ in kind or count
- `leftover:<token>`: a `$` code, an unknown `{word}` or any `<a/b>` pair (drafts are gender-neutral)
- `slash:<a>/<b>`: a `/` between two Japanese words (`師匠/主人`), two renderings where one must be chosen;
  the reason shows the Japanese runs around it
- `counters:<english>→<japanese>`: the server counters (`$1997w`, `$2283W`: a value the game fills in) differ
- `paragraphs:<ja>/<en>`: a different number of paragraphs
- `alignment_failed:<word>`: a Latin word in the Japanese the English does not have (`align.check_names`);
  the words of a `$G<male>:<female>;` code do not count as English (the draft writes one neutral form), except
  the names in it (the neutral form may keep a name from either branch: "Stranglethorn", not "Sir")
- `numbers_changed:<n>`: a number in the Japanese that the English does not have (`align.check_numbers`).
  This is what stops a tooltip draft baking a literal value: the English template holds `$s1`, not `58`,
  so a Japanese line saying `58` fails. Write `$N<k>` instead. The addon fills it from the k-th number
  of the line the client is showing, so the translation survives a different rank, level or talent.
- `placeholder_run:<text>`: a `$N<k>` or `$D<k>` with letters glued to its end (`$N1c1`,
  `$N2roccooldown`). The placeholder fills and the glued fragment stays on screen; the name check cannot
  see it, because a fragment of the English source is by definition present in the English.
- `slot_missing:N<k>`: the k-th number of the line comes from a code the client fills in (`$s1`, `$1oa`,
  `${…}`) and the Japanese has no `$N<k>` for it (nor, where the line shows it as a duration, its `$D<j>`).
  Dropping one takes the number off the screen, and a placeholder pointing at another slot does not
  carry it. A literal the English already shows (`Kill 7 Nightsabers`) is exempt: write it out or use
  `$N<k>`.
- `duration_as_value:N<k>`: `$N<k>` on a `$d`, the bare number, with a unit the Japanese named itself.
- `duration_missing:D<j>`: the j-th duration is a `$d` and the Japanese has no `$D<j>`. A duration is the
  one value whose **unit** the client chooses, so a Japanese line that names the unit itself (`18秒`) is
  wrong the moment the client renders minutes. `Align.check` cannot catch it, because the number
  matches and the unit is Japanese text the gate never reads. `$D<k>` copies the whole phrase out of the
  live line, rendered by the UI strings we already ship (`INT_SPELL_DURATION_SEC` = `%d秒`, …). Durations
  are counted the way the addon reads the live line: a number the English writes in front of a unit
  (`every 5 sec`) is a duration too, so `$D` indices count it.
- `duration_index:<k>><n>`: a `$D<k>` past the durations the template prints. `$D` indexes the line's
  durations (`$D1` is the first), not the whole number space `$N` indexes.
- `value_index:<k>><slots>`: a `$N<k>` past the number of values the template can print. The addon's
  fill is closed-ended: one unfillable placeholder drops the whole line back to English. Not reported
  when the template's slot count is unknowable (`$?…[…]` conditionals,
  `$@spelldesc…` inclusions); there the count is checked in game, not here.
- `icon_missing:<k>` / `icon_index:<k>`: every `$I<k>` of the English (an inline spell icon,
  `$@spellicon`) once in the Japanese, and no other. The addon copies the k-th icon of the live line there.
- Branch rows (ADR-043; the row carries `branches`): `branch_skeleton`, the Japanese does not keep
  the English's `$?` conditionals (same conditions, branch counts and order); `branch_index:<N|D><k>`, a
  placeholder for a value the variant it sits in does not print (whole-template numbering, `row["slots"]`);
  `v<i>:<reason>`, variant i fails an ordinary rule against its own English; `branches_indistinguishable`,
  on every variant's line another variant's Japanese would pass the addon's gate too, so the addon (which
  shows a variant only when exactly one fits) would never show any; `branches_unsafe`, a shadowed variant
  carries an icon or a duration the variant shadowing it lacks, so a fill failure would show the wrong branch.
- `name_missing:<word>`: a capitalised word inside an English sentence (a name) that the Japanese does not
  keep in English letters. Glossary terms (`pipeline/translation_glossary.tsv`: titles and common nouns such
  as `the Captain`, races, classes) are translated, so exempt, except directly before or after a capitalised
  name word (`Captain Althea`, `Murloc Warrior`, `Dark Lady`, `Lion's Pride Inn`), or before one through other
  glossary words (`Arch Druid Hamuul`), where they are part of the name. A profession name is kept but is not
  a name word for a title after it (`Skinning Trainer` → `Skinningのトレーナー`). A place or group word
  joined to a capitalised word by `of (the)` makes one name (`Temple of the Moon`, `Brotherhood of the
  Light`), a person title does not (`the King of Stormwind`); `FIXED_NAMES` (`Duke of Shards`) always are.
  A word after a quote, a dash, `<`, `>` or `)` starts a sentence; a `<Sob>`-style stage direction and the
  words of a `$G…:…;` code are not read; a hyphen, en dash or em dash ends a word (`Orgrimmar--somethin'`,
  `Scourge-driven`). A word that starts a sentence is not read as a name, and is no name for the word
  after it either (`Say Captain…`, `Our Alchemist's…`), but a glossary word or a profession name there is
  still checked (`Tailoring you say?` keeps `Tailoring`). A word listed for the row's ref in
  `pipeline/translation_not_names.tsv` is not read as a name on that row only (a capitalised common word in
  a book heading, greeting or plaque, such as `Chapter 3 - The Four Commanders`, reviewed and listed one
  row and word at a time).
- `markup_changed:<difference>`: an HTML book page (`<HTML…`) whose Japanese does not carry the English's
  tags in the same order (`markup.html_mismatch`, the rule `wfj check` applies to book pages)
- `stat_word:<word>`: an item or spell row keeps a stat word (`health`, `Stamina`, …) in English letters on
  its own, or writes another spelling of the stat (`core/stat_words.NOT_SPELLINGS`: ヘルス, 知性, 気力,
  エナジー); a tooltip uses the interface's Japanese (`core/stat_words.STAT_WORDS`: 体力, スタミナ, …). A
  stat word inside a name (`Mana Shield`, `Elixir of Agility`) is not read. On these rows a stat word the
  English uses on its own (`Increases Stamina by $s1`) is no name to keep; one inside a name in the English
  (`Elixir of Agility`) still is, even when the same word is also used on its own in the line. Which
  Japanese sense a free word takes (spirit as the stat or as a ghost) is the drafter's reading, not the
  lint's.
- `glossary:<term>`: the English has a `required` glossary term (a race or class word, or its plural) and
  the Japanese neither uses the glossary's rendering nor keeps the word in English letters (part of a name,
  `Skeletal Warrior`). A term listed in lower case for the row's ref in `pipeline/translation_not_names.tsv`
  (exactly the glossary term; a capitalised heading word like `Warrior` does not count) is not checked
  on that row (the word is used in another sense there: "a rogue spark" is a stray one, not the class)

Readings: a quest or gossip draft row may also carry `"words": [[word, reading], …]`, the whole
reading of every kanji word in its Japanese, the same list `wfj readings import` takes (ADR-036). They are
checked with the import's own rules (`readings.word_problems`):

- `words:<problem>`: a word not found after the previous one, with no kanji, holding an ASCII character, or
  with a non-kana reading
- `words_unexpected`: `words` on a kind that gets no readings (tooltips, books, objectives)

A quest or gossip row whose Japanese holds a kanji and that has no `words` passes, with a warning: its
readings are still owed (`wfj readings export` picks the line up later).

Passing rows, with paragraph breaks canonicalised, go to `<DRAFT stem>.ok.jsonl` with the batch's `kind` and
`targets` (and `words`, when the draft had them). Exit 1 when any row failed.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any

from wfj.core import align, language, markup, paragraphs, placeholders, readings, stat_words
from wfj.dev.glossary import GLOSSARY, read_glossary, read_required, term_pattern
from wfj.dev.lint_names import GENDER_CODE, english_names, exempt_words, forms, titles_before_names
from wfj.dev.translate_batch import KINDS, TEMPLATE_KINDS, TITLE_CASE_KINDS, read_jsonl, write_jsonl

ALLOWLIST = Path("pipeline/allowlist.txt")
NOT_NAMES = Path("pipeline/translation_not_names.tsv")
_DOTS = re.compile(r"[.…。・\s]+")
_JA = "\u3040-\u30ff\u3400-\u9fff々〆ヵヶー"
_SLASH = re.compile(rf"([{_JA}]+)\s*[/／]\s*([{_JA}]+)")
# A quest's server counter (`$1997w`). The trailing boundary matters: a tooltip's cross-spell value code
# `$1310167w2` starts the same way and is NOT a counter to copy through.
_COUNTER = re.compile(r"\$\d+[wW](?![0-9])")
_RUN_ON = re.compile(r"\$[NDI]\d+[A-Za-z][A-Za-z0-9]*")  # a placeholder with English glued to its end
# `$N<k>` and `$D<k>` are the addon's placeholders, not leftover codes: the value and the duration of the
# line the client is showing. Every other `$` in a draft is a leftover, except a line's last `$T`, the
# name-list tail, whose placement `align.tail_problems` judges.
_CODE = re.compile(r"\$(?!\d+[wW]|[NDI]\d|T\Z)\S?")


# A client template's arithmetic is `${$m1/60}`: a `$` then a braced expression. Its inner braces
# are not a player token, and a draft must NOT copy it through (`$` codes are `leftover`), so it is stripped
# before the token sets are compared. The server-only kinds never carry one; the tooltip kinds do.
_SUM = re.compile(r"\$\{[^{}]*\}")
# A colour code glued to a word (`|CFFFFFFFFRequires Cat Form|R`) is markup, not part of a name. Read as one,
# the names check would ask for `CFFFFFFFFRequires` in the Japanese, which no line can carry.
_COLOUR = re.compile(r"\|[cC](?:[0-9A-Fa-f]{8}|n[A-Z_]+:)|\|[rR]")


def _brace_tokens(text: str) -> Counter[str]:
    return Counter(t for t in placeholders.tokens(_SUM.sub("", text or "")) if t.startswith("{"))


def _value_index_problems(en: str, ja: str) -> list[str]:
    """A `$N<k>` past the template's slots fills with nothing and the line is dropped in game
    (`Align.fill` fails closed). Only checked where the slot count is knowable from the template."""
    slots = align.value_slots(en)
    used = align.fill_indices(ja)
    if slots is not None and used:
        over = sorted({k for k in used if k < 1 or k > slots})
        if over:
            return [f"value_index:{','.join(map(str, over))}>{slots}"]
    return []


def _duration_index_problems(en: str, ja: str) -> list[str]:
    """A `$D<k>` past the template's durations, which the client cannot fill."""
    durations = align.duration_slots(en)
    if durations is not None:
        over = sorted({k for k in align.duration_indices(ja) if k < 1 or k > durations})
        if over:
            return [f"duration_index:{','.join(map(str, over))}>{durations}"]
    return []


def check_row(
    row: dict[str, Any],
    ja: str,
    allowlist: set[str],
    glossary: set[str],
    required: dict[str, str] | None = None,
    not_names: frozenset[str] | set[str] = frozenset(),
) -> list[str]:
    if row.get("branches"):
        return _check_branches(row, ja, allowlist, glossary, required, not_names)
    en, field = row["en"], KINDS[row["kind"]][1]
    reasons: list[str] = []
    # a tooltip line that is only a name (`translate_batch` marks it `name_only`) ships that name: names stay
    # in English letters
    kept_name = bool(row.get("name_only")) and ja == en
    dots = bool(_DOTS.fullmatch(en) and _DOTS.fullmatch(ja))
    if not language.is_japanese(ja, field) and not dots and not kept_name:
        return ["not_japanese"]
    want, have = _brace_tokens(en), _brace_tokens(ja)
    if want != have:
        reasons.append(f"tokens:{_fmt(want)}→{_fmt(have)}")
    leftovers = placeholders.unknown(ja) + [t for t in placeholders.tokens(ja) if t == "<a/b>"]
    leftovers += _CODE.findall(ja)
    if Counter(_COUNTER.findall(en)) != Counter(_COUNTER.findall(ja)):
        reasons.append(f"counters:{_fmt(Counter(_COUNTER.findall(en)))}→{_fmt(Counter(_COUNTER.findall(ja)))}")
    reasons += [f"leftover:{t}" for t in dict.fromkeys(leftovers)]
    # NPC speech: an emote's `%s` is the speaker's name the client fills in (the chat line is
    # formatted with it, chatframeoverrides.lua:629–633): the Japanese keeps every `%s` and carries no other
    # `%`, which the client's format() would read as a specifier
    if en.count("%s") != ja.count("%s") or ja.replace("%s", "").count("%") > en.replace("%s", "").count("%"):
        reasons.append(f"speaker:{en.count('%s')}→{ja.count('%s')}")
    # A placeholder must end where its digits end. `$N1c1`, `$N2roccooldown` (a drafter gluing a
    # fragment of the English source onto one) fills the value and leaves the fragment on screen, and the
    # name check vouches for the fragment because it IS a substring of the English.
    reasons += [f"placeholder_run:{t}" for t in dict.fromkeys(_RUN_ON.findall(ja))]
    reasons += _value_index_problems(en, ja)
    # A duration's UNIT is the client's choice: `$d` renders through INT_SPELL_DURATION_SEC /
    # _MIN / _HOURS / _DAYS, so one template is seconds on one item and minutes on another.
    # `Align.check` cannot catch a wrong unit (the number matches and the unit is Japanese text the gate
    # never reads), so this is the only gate: one `$D<k>` per duration, never a unit named by hand.
    # A value the client fills in cannot be stated by the Japanese, so dropping it loses the number off the
    # screen. A literal the English already shows is exempt: the Japanese may write it out instead.
    # Every code slot must be carried by the placeholder that points at IT. A mere count of placeholders
    # would pass `$D1かけて体力を$N2回復` for `Restores $o1 health over $d`, dropping `$o1` and showing the
    # duration's number as the health. A `$d` takes only its `$D<k>` (ADR-028: the client picks the unit).
    reasons += align.slot_problems(en, ja) or []
    # a name-list tail (Languages, Armor Proficiency) is carried by one trailing `$T`, never written out
    reasons += align.tail_problems(en, ja)
    reasons += _duration_index_problems(en, ja)
    reasons += _icon_problems(en, ja)
    reasons += [f"slash:{a}/{b}" for a, b in dict.fromkeys(_SLASH.findall(ja))]
    # both sides counted the same way: a line holding only spaces between two breaks is one break.
    # A `${…}` sum may hold newlines (`${$m1+\n$m2}`), which are inside a code the client
    # computes, never paragraph breaks the Japanese has to mirror.
    jp = paragraphs.count(ja)
    ep = paragraphs.count(paragraphs.normalize_breaks(align.SUM.sub(" ", en)))
    if jp != ep:
        reasons.append(f"paragraphs:{jp}/{ep}")
    # A NAME inside a `$G<male>:<female>;` branch ("…the jungles of Stranglethorn…") is English the
    # neutral draft may keep; the branch's other words ("Sir") still may not be kept in English letters
    def branch_names(m: re.Match[str]) -> str:
        return " " + " ".join(english_names(re.sub(r"^\$[Gg]|[:;]", " ", m.group()), set())) + " "

    english_words = GENDER_CODE.sub(branch_names, en)
    reasons += [f"alignment_failed:{w}" for w in align.check_names(ja, english_words, allowlist)[1]]
    # The `.N` of `${…}.N` is Blizzard's precision, not a number the player reads: the line
    # prints `2.5%`, never a `1`. Left in, it would vouch for a Japanese `$N1.1%`, which fills one value
    # and then states a decimal of its own.
    reasons += [f"numbers_changed:{n}" for n in align.check_numbers(ja, align.SUM.sub(" ", en))[1]]
    if bad_html := markup.html_mismatch(en, ja):  # an HTML book page keeps its tags in order
        reasons.append(f"markup_changed:{bad_html}")
    kept = ja.casefold()
    names = english_names(_COLOUR.sub(" ", en), glossary)
    # Japanese has no plural: "Gnolls" kept as `Gnollども` is kept
    missing = [w for w in names if w not in not_names and not any(f in kept for f in forms(w))]
    # A tooltip's stat word is written with the interface's Japanese, never kept in English letters: the
    # English capitalises it (`Increases Stamina by $s1`), so where it stands on its own it is no name to
    # keep either. Inside a name (`Elixir of Agility`, `Mana Shield`) it still is one.
    if row["kind"] in TEMPLATE_KINDS:
        reasons += [f"stat_word:{w}" for w in dict.fromkeys(stat_words.find(ja))]
        reasons += [f"stat_word:{s}" for s in stat_words.not_spellings(ja)]
        free, named = stat_words.classify(en, names)
        missing = [w for w in missing
                   if not (any(f in free for f in forms(w)) and not any(f in named for f in forms(w)))]
    # A quest TITLE is written in title case ("The Alliance Needs Copper Bars", "Keeper of the Flame"). Every
    # word is capitalised by convention, so capitalisation carries none of the signal this check reads it
    # for, and it would flag "Needs" and "Flame" as names. The check is skipped here rather than drowned:
    # names still stay in English letters, and the style guide's Quests section says so, but the lint
    # cannot tell a name from an ordinary word in title case.
    # objective text is title case too, and so is a tooltip row without prose (`Soft Like Pudding`)
    if row["kind"] not in TITLE_CASE_KINDS and not row.get("title_case"):
        reasons += [f"name_missing:{w}" for w in missing]
    else:
        # the names `cut` found by what the corpus never writes in lower case, and the item / creature names
        # inside the title (`translate_batch.title_names`)
        reasons += [
            f"name_missing:{w}"
            for w in row.get("names", [])
            if w not in not_names and w.casefold() not in kept
        ]
        # a title word before a name, as a whole word (`Lord Lordaeron` is not kept by `王Lordaeron`)
        reasons += [
            f"name_missing:{w}"
            for w in titles_before_names(en, [n for n in row.get("names", []) if n not in not_names],
                                         glossary)
            if w not in not_names and not _whole_word(w, kept)
        ]
    for term, jp in (required or {}).items():
        if term in not_names:  # listed in lower case: not the race / class word on this row
            continue
        pattern = term_pattern(term)
        if pattern.search(en) and jp not in ja and not pattern.search(ja):  # kept in English: part of a name
            reasons.append(f"glossary:{term}")
    return reasons


def _icon_problems(en: str, ja: str) -> list[str]:
    """Every `$I<k>` of the English once in the Japanese: `icon_missing:<k>` (an icon the line
    would lose), `icon_index:<k>` (one the English does not have, or written twice)."""
    want, have = Counter(align.icon_indices(en)), Counter(align.icon_indices(ja))
    out = [f"icon_missing:{k}" for k in sorted(want) if k not in have]
    out += [f"icon_index:{k}" for k in sorted(have) if have[k] > want.get(k, 0)]
    return out


def _check_branches(
    row: dict[str, Any],
    ja: str,
    allowlist: set[str],
    glossary: set[str],
    required: dict[str, str] | None,
    not_names: frozenset[str] | set[str],
) -> list[str]:
    """A `$?` row (ADR-043). The Japanese keeps the English's conditionals (`branch_skeleton`); each
    variant, renumbered to its own reading order (`align.ja_variants`), is checked against that variant's
    English by every rule of an ordinary row (a reason is prefixed `v<i>:`); and the addon must be able to
    show at least one variant, refused when on every variant's line another variant passes the gate too
    (`branches_indistinguishable`, `align.never_shown`)."""
    b = align.branching(row["en"])
    if b.reason:
        return [b.reason]
    texts, bad = align.ja_variants(ja, b)
    if texts is None:
        return bad
    reasons: list[str] = []
    for i, (v, text) in enumerate(zip(b.variants, texts, strict=True), 1):
        sub = {**row, "en": v.en}
        sub.pop("branches", None)
        reasons += [f"v{i}:{r}" for r in check_row(sub, text, allowlist, glossary, required, not_names)]
    if b.sectioned:  # its paragraphs are told apart by their opening words (align.section_prefix)
        return reasons
    shapes = [v.shape for v in b.variants]
    pairs = align.indistinguishable(texts, [v.en for v in b.variants], shapes, allowlist)
    if not reasons and align.never_shown(pairs, len(texts)):
        reasons.append("branches_indistinguishable")
    elif not reasons and align.unsafe_shadow(pairs, texts):
        reasons.append("branches_unsafe")
    return reasons


def _whole_word(word: str, kept: str) -> bool:
    """`word` (case-folded) occurs in `kept` as a whole word: `Lord` is not kept by `王Lordaeron`."""
    return re.search(rf"(?<![a-z]){re.escape(word.casefold())}(?![a-z])", kept) is not None


def read_not_names(path: Path) -> dict[str, set[str]]:
    """`<ref>\t<word>\t<the English line, for the reader>` per line, `#` comments: capitalised words that are
    not names on that batch row (a ref is the batch row's ref: the first 10 hex of the hash of the English as
    the drafter sees it, `translate_batch.model_english`, so it holds while that English does). A missing
    file is an empty list."""
    out: dict[str, set[str]] = {}
    if not path.is_file():
        return out
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip() or raw.startswith("#"):
            continue
        cells = raw.split("\t")
        if len(cells) != 3 or not re.fullmatch(r"[0-9a-f]{10}", cells[0]) or not cells[1].strip():
            raise ValueError(f"{path.name}:{n}: need '<ref>\\t<word>\\t<English line>'")
        out.setdefault(cells[0], set()).add(cells[1].strip())
    return out


def _fmt(c: Counter[str]) -> str:
    return ",".join(f"{t}×{n}" for t, n in sorted(c.items())) or "none"


def lint(
    batch: Path,
    draft: Path,
    allowlist: set[str],
    glossary: set[str],
    required: dict[str, str] | None = None,
    not_names: dict[str, set[str]] | None = None,
) -> tuple[list[dict[str, Any]], dict[str, list[str]]]:
    rows = {r["ref"]: r for r in read_jsonl(batch)}
    failures: dict[str, list[str]] = {}
    seen: dict[str, str] = {}
    words: dict[str, Any] = {}
    for d in read_jsonl(draft):
        ref = d.get("ref")
        if ref not in rows:
            failures.setdefault(str(ref), []).append("unknown_ref")
        elif ref in seen:
            failures.setdefault(ref, []).append("duplicate")
        else:
            seen[ref] = paragraphs.normalize_breaks(str(d.get("ja") or ""))
            # an empty list on a line with no kanji is the same as no `words` (nothing to read)
            reading_kind = ref in rows and KINDS[rows[ref]["kind"]][0] in readings.TYPES
            empty_ok = d.get("words") == [] and reading_kind and not readings.annotatable(seen[ref])
            if "words" in d and not empty_ok:
                words[ref] = d["words"]
    ok: list[dict[str, Any]] = []
    for ref, row in rows.items():
        if ref not in seen:
            failures.setdefault(ref, []).append("missing")
            continue
        listed = (not_names or {}).get(ref, frozenset())
        reasons = check_row(row, seen[ref], allowlist, glossary, required, listed)
        if ref in words:
            reasons += words_problems(row["kind"], seen[ref], words[ref])
        if reasons or ref in failures:
            failures.setdefault(ref, []).extend(reasons)
        else:
            good = {"ref": ref, "kind": row["kind"], "ja": seen[ref], "targets": row["targets"]}
            if ref in words:
                good["words"] = words[ref]
            ok.append(good)
    return ok, failures


def words_problems(kind: str, ja: str, words: Any) -> list[str]:
    """A draft row's readings, checked by the rules `wfj readings import` applies."""
    if KINDS[kind][0] not in readings.TYPES:
        return ["words_unexpected"]
    return [f"words:{p}" for p in readings.word_problems(ja, words)]


def owed_readings(ok: list[dict[str, Any]]) -> list[str]:
    """Refs of passing quest / gossip rows with words to annotate (a kanji, or kana that are more than a
    bare particle: validate's rule) and no `words`."""
    return [
        r["ref"]
        for r in ok
        if KINDS[r["kind"]][0] in readings.TYPES and "words" not in r and readings.annotatable(r["ja"])
        and not readings.html_page(KINDS[r["kind"]][0], r["ja"])  # an HTML book page takes no card
    ]


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="translate_lint", description=__doc__.split("\n\n")[0])
    ap.add_argument("batch", type=Path)
    ap.add_argument("draft", type=Path)
    ap.add_argument("--allowlist", type=Path)
    ap.add_argument("--glossary", type=Path)
    ap.add_argument("--not-names", type=Path)
    args = ap.parse_args(argv)
    repo = Path(__file__).resolve().parents[3]
    allowlist = align.load_allowlist((args.allowlist or repo / ALLOWLIST).read_text(encoding="utf-8"))
    glossary_path = args.glossary or repo / GLOSSARY
    glossary = exempt_words(read_glossary(glossary_path))
    not_names = read_not_names(args.not_names or repo / NOT_NAMES)
    ok, failures = lint(args.batch, args.draft, allowlist, glossary, read_required(glossary_path), not_names)
    out = args.draft.with_name(args.draft.name.removesuffix(".jsonl") + ".ok.jsonl")
    write_jsonl(out, ok)
    for ref, reasons in sorted(failures.items()):
        print(f"{ref}: {'; '.join(reasons)}")
    owed = owed_readings(ok)
    for ref in owed:
        print(f"warn {ref}: no words; its readings are still owed")
    print(f"lint: {len(ok)} ok · {len(failures)} failed · {len(owed)} without words → {out.name}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
