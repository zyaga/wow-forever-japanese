"""Kana lines (ADR-077): each voiced line as the voice should read it, in kana only.

The line the voice reads today (`voice.speech_text` of the shipped Japanese) with every word of its reading
record replaced by that reading, every English name by its Japanese name, and every number spelled out with
its counter (3匹 さんびき, 1本 いっぽん). The text on screen keeps its kanji; this is input for making audio.
Pure: no disk.
"""

from __future__ import annotations

import re
from collections.abc import Callable, Mapping, Sequence
from typing import Any

from wfj.core import names, voice

_LEFTOVER = re.compile(r"[㐀-䶿一-鿿々〆A-Za-z0-9０-９]")

# Counters with the reading a number takes before them. "h" counters soften after 3 (b) and harden after
# 1 / 6 / 8 / 10 / 100 (p, with a small tsu); "k" and "s" counters take a small tsu after 1 / 8 / 10 / 100
# (and 6 for "k").
_H = {"匹": "ひき", "本": "ほん", "杯": "はい", "分": "ふん", "発": "はつ", "歩": "ほ", "泊": "はく"}
_K = {
    "個": "こ",
    "回": "かい",
    "階": "かい",
    "ヶ月": "かげつ",
    "か月": "かげつ",
    "ヵ月": "かげつ",
    "缶": "かん",
    "件": "けん",
    "軒": "けん",
    "曲": "きょく",
}
_S = {
    "冊": "さつ",
    "着": "ちゃく",
    "週": "しゅう",
    "隻": "せき",
    "通": "つう",
    "頭": "とう",
    "点": "てん",
    "等": "とう",
    "足": "そく",
}
_PLAIN = {
    "体": "たい",
    "羽": "わ",
    "枚": "まい",
    "名": "めい",
    "秒": "びょう",
    "粒": "つぶ",
    "束": "たば",
    "箱": "はこ",
    "袋": "ふくろ",
    "度": "ど",
    "番": "ばん",
    "倍": "ばい",
    "割": "わり",
    "時間": "じかん",
    "年": "ねん",
    "日": "にち",
    "人": "にん",
    "つ": "つ",
    "ゴールド": "ゴールド",
    "シルバー": "シルバー",
    "カッパー": "カッパー",
    "%": "パーセント",
    "％": "パーセント",
    "レベル": "レベル",
    "ヤード": "ヤード",
    "時": "じ",
    "円": "えん",
    "万": "まん",
}
COUNTER_READING = {**_H, **_K, **_S, **_PLAIN}
COUNTERS = sorted(COUNTER_READING, key=len, reverse=True)
_DIGITS = ["いち", "に", "さん", "よん", "ご", "ろく", "なな", "はち", "きゅう"]
_TSUMARU = {"いち": "いっ", "ろく": "ろっ", "はち": "はっ", "じゅう": "じゅっ", "ひゃく": "ひゃっ"}
_PEOPLE = {1: "ひとり", 2: "ふたり", 4: "よにん"}
_DAYS = {
    1: "いちにち",
    2: "ふつか",
    3: "みっか",
    4: "よっか",
    5: "いつか",
    6: "むいか",
    7: "なのか",
    8: "ようか",
    9: "ここのか",
    10: "とおか",
    14: "じゅうよっか",
    20: "はつか",
    24: "にじゅうよっか",
}
_THINGS = {
    1: "ひとつ",
    2: "ふたつ",
    3: "みっつ",
    4: "よっつ",
    5: "いつつ",
    6: "むっつ",
    7: "ななつ",
    8: "やっつ",
    9: "ここのつ",
    10: "とお",
}
# what follows a number and its counter: 1つ目 ひとつめ, 2週間 にしゅうかん, 2年前 にねんまえ,
# 20回分 にじゅっかいぶん
_AFTER = {
    "目": "め",
    "間": "かん",
    "前": "まえ",
    "後": "ご",
    "分": "ぶん",
    "以上": "いじょう",
    "以内": "いない",
    "以下": "いか",
    "ぶり": "ぶり",
    "おき": "おき",
}
_NUMBER = re.compile(
    # a number ("1,000" with its thousands commas, "2.5"), spaces on its own line, a counter, what follows it
    r"(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)([ \t]*)("
    + "|".join(map(re.escape, COUNTERS))
    + r")?((?:"
    + "|".join(map(re.escape, sorted(_AFTER, key=len, reverse=True)))
    + r")*)"
)
_AFTER_ONE = re.compile("|".join(map(re.escape, sorted(_AFTER, key=len, reverse=True))))
_AFTER_RUN = re.compile(f"(?:{_AFTER_ONE.pattern})+")
_FRACTION = re.compile(r"(\d+)分の(?=[0-9０-９一二三四五六七八九十])")  # 3分の1, not 5分の休憩
_RANGE = re.compile(r"[～〜](?=[0-9０-９])")  # a range ends in a number: 1～2分, 6時～11時
_HOW_MANY = re.compile(r"何(" + "|".join(map(re.escape, COUNTERS)) + r")")


def _under_10000(n: int) -> list[str]:
    """The reading of 1..9999 as its parts (the last part decides how a counter sounds)."""
    parts = []
    for value, unit, special in (
        (1000, "せん", {1: "せん", 3: "さんぜん", 8: "はっせん"}),
        (100, "ひゃく", {1: "ひゃく", 3: "さんびゃく", 6: "ろっぴゃく", 8: "はっぴゃく"}),
        (10, "じゅう", {1: "じゅう"}),
    ):
        d, n = divmod(n, value)
        if d:
            parts.append(special.get(d, _DIGITS[d - 1] + unit))
    if n:
        parts.append(_DIGITS[n - 1])
    return parts


def number_parts(n: int) -> list[str]:
    if n == 0:
        return ["ゼロ"]
    parts: list[str] = []
    for value, unit in ((100_000_000, "おく"), (10_000, "まん")):
        d, n = divmod(n, value)
        if d:
            parts += _under_10000(d)
            parts[-1] += unit
    return parts + _under_10000(n)


def read_number(text: str) -> str:
    whole, _, frac = text.replace(",", "").partition(".")
    out = "".join(number_parts(int(whole)))
    if frac:
        out += "てん" + "".join("ゼロ" if c == "0" else _DIGITS[int(c) - 1] for c in frac)
    return out


def _last_digit_word(parts: list[str]) -> str:
    last = parts[-1]
    for w in ("ひゃく", "じゅう", "せん", "まん"):
        if last.endswith(w):
            return w
    return last


def with_counter(text: str, counter: str) -> str:
    """A number and its counter, read together with the sound changes (3匹 さんびき, 10本 じゅっぽん)."""
    if "." in text:
        return read_number(text) + COUNTER_READING[counter]
    n = int(text.replace(",", ""))
    special = {"人": _PEOPLE, "日": _DAYS, "つ": _THINGS}.get(counter, {})
    if n in special:
        return special[n]
    if counter == "つ":
        return read_number(text)
    parts = number_parts(n)
    head, last = "".join(parts[:-1]), parts[-1]
    tail = _last_digit_word(parts)
    stem = last[: len(last) - len(tail)] if last.endswith(tail) and tail != last else ""
    if counter in _H:
        return head + _h_counter(counter, last, tail, stem)
    if counter in _K or counter in _S:
        return head + _k_counter(counter, last, tail, stem)
    return head + _plain_counter(counter, last, tail, stem)


_P_AFTER_3 = frozenset({"分", "発", "歩", "泊"})  # さんぷん, さんぱつ, さんぽ, さんぱく (not b)


def _h_counter(counter: str, last: str, tail: str, stem: str) -> str:
    """匹 本 杯 分 …: hard (p, small tsu) after 1 / 6 / 8 / 10 / 100, soft (b) after 3 / 1000 / 万."""
    base = _H[counter]
    if tail in _TSUMARU:
        return stem + _TSUMARU[tail] + _p(base)
    if last.endswith("ゃく"):  # 300 / 600 / 800 匹: さんびゃっぴき
        return last[:-1] + "っ" + _p(base)
    if tail in ("さん", "せん", "まん") or (counter == "分" and tail == "よん"):
        return last + (_p(base) if counter in _P_AFTER_3 else _b(base))
    return last + base


_VOICED_AFTER_3 = {"階": "がい", "足": "ぞく", "軒": "げん"}  # さんがい, さんぞく, さんげん


def _k_counter(counter: str, last: str, tail: str, stem: str) -> str:
    """個 回 冊 …: a small tsu after 1 / 8 / 10 / 100 (and 6 for the k sounds); 3階 さんがい."""
    base = _K.get(counter) or _S[counter]
    small = {"いち", "はち", "じゅう", "ひゃく"} | ({"ろく"} if counter in _K else set())
    if tail in small:
        return stem + _TSUMARU[tail] + base
    if tail == "さん" and counter in _VOICED_AFTER_3:
        return last + _VOICED_AFTER_3[counter]
    return last + base


def _plain_counter(counter: str, last: str, tail: str, stem: str) -> str:
    """The counters with no sound change, but 4 and 7 / 9 before 年 and 時(間) (よねん, しちじ, くじ)."""
    reading = _PLAIN[counter]
    if counter in ("年", "時間", "時", "人") and tail == "よん":  # よねん, よじかん, じゅうよにん
        return stem + "よ" + reading
    if counter in ("時間", "時") and tail in ("なな", "きゅう"):
        return stem + ("しち" if tail == "なな" else "く") + reading
    return last + reading


def _b(h: str) -> str:
    return {"は": "ば", "ひ": "び", "ふ": "ぶ", "へ": "べ", "ほ": "ぼ"}[h[0]] + h[1:]


def _p(h: str) -> str:
    return {"は": "ぱ", "ひ": "ぴ", "ふ": "ぷ", "へ": "ぺ", "ほ": "ぽ"}[h[0]] + h[1:]


def how_many(counter: str) -> str:
    """何 with a counter (何匹か なんびきか; 何つか いくつか)."""
    if counter == "つ":
        return "いくつ"
    if counter in _H:
        return "なん" + _b(_H[counter])
    return "なん" + COUNTER_READING[counter]


def _counter_word(surface: str) -> bool:
    """A counter, alone or with what follows a count (匹, 週間, 本目): read with its number, not as written.
    A word that only starts with one (本部) is an ordinary word."""
    for c in COUNTERS:
        if surface.startswith(c):
            rest = surface[len(c) :]
            if not rest or _AFTER_RUN.fullmatch(rest):
                return True
    return False


def apply_readings(ja: str, words: Sequence[Sequence[str]]) -> str | None:
    """`ja` with each reading word replaced by its reading, in order (each found after the previous one). A
    counter right after a number or a `$N<k>` keeps its kanji: the number reader reads them together. None
    when a word is not found (a record that no longer fits the line)."""
    out, at = [], 0
    for w in words:
        surface, reading = w[0], w[1]
        i = ja.find(surface, at)
        if i < 0:
            return None
        out.append(ja[at:i])
        if i > 0 and ja[i - 1].isdigit() and _counter_word(surface):  # "3匹", "$N1匹"
            out.append(surface)
        else:
            out.append(reading)
        at = i + len(surface)
    out.append(ja[at:])
    return "".join(out)


def name_kana(line: Mapping[str, Any]) -> str:
    """A name as the voice reads it: katakana kept as written, the rest from its reading."""
    if names.KATAKANA.match(line["ja"]):
        return line["ja"]
    return names.spoken(line["ja"], line["reading"]) or line["reading"]


def replace_names(text: str, lookup: Callable[[str], str | None]) -> tuple[str, list[str]]:
    """Every run of Latin letters replaced by its name's kana; the runs with no name are returned."""
    missing: list[str] = []

    def one(m: re.Match[str]) -> str:
        raw = m.group(0)
        run = names.trim_run(raw)  # the collector's rule: what it stored is what is looked up here
        kana = lookup(run) if run else None
        if kana is None:
            missing.append(run or raw)
            return raw
        return kana + raw[len(run) :]  # a trimmed count stays for its counter ("cloth60枚")

    return names.LATIN_RUN.sub(one, text), missing


def spell_numbers(text: str) -> str:
    text = _HOW_MANY.sub(lambda m: how_many(m.group(1)), text)
    text = _FRACTION.sub(lambda m: read_number(m.group(1)) + "ぶんの", text)  # 3分の1 さんぶんのいち
    # the words speech_text puts in: the player, and a count only the server knows
    text = text.replace(voice.PLAYER_WORD, "ぼうけんしゃ").replace("数", "すう")

    def one(m: re.Match[str]) -> str:
        num, space, counter, after = m.group(1), m.group(2), m.group(3), m.group(4)
        if not counter:
            return read_number(num) + space + (after or "")
        return with_counter(num, counter) + _AFTER_ONE.sub(lambda a: _AFTER[a.group(0)], after or "")

    # ～ before a count is a range (1～2分: いちからにふん); anywhere else a drawn-out sound (んん～)
    return _NUMBER.sub(one, _RANGE.sub("から", text).replace("～", "ー").replace("〜", "ー"))


def build(
    ja: str,
    key: str,
    values: Sequence[str],
    words: Sequence[Sequence[str]] | None,
    lookup: Callable[[str], str | None],
) -> tuple[str | None, list[str]]:
    """(kana line, problems). The kana line is None when anything is left that is not kana: a kanji with no
    reading, a name with no Japanese, a number it cannot read."""
    text = apply_readings(ja, words or ())
    if text is None:
        return None, ["the reading record does not fit the line"]
    try:
        text = voice.speech_text(text, key, values)
    except voice.VoiceError as e:
        return None, [str(e)]
    # names first: a name can hold digits ("NG-5"), and its Japanese reading has none left to spell
    text, missing = replace_names(text, lookup)
    text = spell_numbers(text)
    # a comma between English names ("Arcanology, Alchemy") or one left in the prose: a Japanese pause
    text = re.sub(r"[,，] ?", "、", text)
    problems = [f"no Japanese name for {m!r}" for m in missing]
    left = sorted(set(_LEFTOVER.findall(text)) - set("".join(missing)))
    if left:
        problems.append("not kana: " + "".join(left))
    if problems:
        return None, problems
    return text, []


def kana_problems(text: Any) -> list[str]:
    if not isinstance(text, str) or not text.strip():
        return ["empty"]
    left = sorted(set(_LEFTOVER.findall(text)))
    return [f"not kana: {''.join(left)}"] if left else []
