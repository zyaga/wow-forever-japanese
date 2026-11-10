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

_KANJI = re.compile(r"[㐀-䶿一-鿿々〆]")
_LEFTOVER = re.compile(r"[㐀-䶿一-鿿々〆A-Za-z0-9０-９]")
_KATAKANA = re.compile(r"^[ァ-ヺー・]+$")

# Counters with the reading a number takes before them. "h" counters soften after 3 (b) and harden after
# 1 / 6 / 8 / 10 / 100 (p, with a small tsu); "k" and "s" counters take a small tsu after 1 / 8 / 10 / 100
# (and 6 for "k").
_H = {"匹": "ひき", "本": "ほん", "杯": "はい", "分": "ふん", "発": "はつ", "歩": "ほ", "泊": "はく"}
_K = {"個": "こ", "回": "かい", "階": "かい", "ヶ月": "かげつ", "か月": "かげつ", "ヵ月": "かげつ", "缶": "かん",
      "件": "けん", "軒": "けん", "曲": "きょく"}
_S = {"冊": "さつ", "着": "ちゃく", "週": "しゅう", "隻": "せき", "通": "つう", "頭": "とう", "点": "てん",
      "等": "とう", "足": "そく"}
_PLAIN = {"体": "たい", "羽": "わ", "枚": "まい", "名": "めい", "秒": "びょう", "粒": "つぶ", "束": "たば",
          "箱": "はこ", "袋": "ふくろ", "度": "ど", "番": "ばん", "倍": "ばい", "割": "わり", "時間": "じかん",
          "年": "ねん", "日": "にち", "人": "にん", "つ": "つ", "ゴールド": "ゴールド", "シルバー": "シルバー",
          "カッパー": "カッパー", "%": "パーセント", "％": "パーセント", "レベル": "レベル", "ヤード": "ヤード",
          "時": "じ", "円": "えん", "万": "まん"}
COUNTERS = sorted({**_H, **_K, **_S, **_PLAIN}, key=len, reverse=True)
_DIGITS = "いち に さん よん ご ろく なな はち きゅう".split()
_TSUMARU = {"いち": "いっ", "ろく": "ろっ", "はち": "はっ", "じゅう": "じゅっ", "ひゃく": "ひゃっ"}
_PEOPLE = {1: "ひとり", 2: "ふたり", 4: "よにん"}
_DAYS = {1: "いちにち", 2: "ふつか", 3: "みっか", 4: "よっか", 5: "いつか", 6: "むいか", 7: "なのか",
         8: "ようか", 9: "ここのか", 10: "とおか", 14: "じゅうよっか", 20: "はつか", 24: "にじゅうよっか"}
_THINGS = {1: "ひとつ", 2: "ふたつ", 3: "みっつ", 4: "よっつ", 5: "いつつ", 6: "むっつ", 7: "ななつ",
           8: "やっつ", 9: "ここのつ", 10: "とお"}
# what follows a number and its counter: 1つ目 ひとつめ, 2週間 にしゅうかん, 2年前 にねんまえ, 20回分 にじゅっかいぶん
_AFTER = {"目": "め", "間": "かん", "前": "まえ", "後": "ご", "分": "ぶん", "以上": "いじょう", "以内": "いない",
          "以下": "いか", "ぶり": "ぶり", "おき": "おき"}
_NUMBER = re.compile(
    r"(\d[\d,]*(?:\.\d+)?)(\s*)(" + "|".join(map(re.escape, COUNTERS)) + r")?((?:"
    + "|".join(map(re.escape, sorted(_AFTER, key=len, reverse=True))) + r")*)"
)
_AFTER_ONE = re.compile("|".join(map(re.escape, sorted(_AFTER, key=len, reverse=True))))
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
        return read_number(text) + (_H.get(counter) or _K.get(counter) or _S.get(counter) or _PLAIN[counter])
    n = int(text.replace(",", ""))
    if counter == "人" and n in _PEOPLE:
        return _PEOPLE[n]
    if counter == "日" and n in _DAYS:
        return _DAYS[n]
    if counter == "つ":
        return _THINGS.get(n, read_number(text))
    parts = number_parts(n)
    head, last = "".join(parts[:-1]), parts[-1]
    tail = _last_digit_word(parts)
    stem = last[: len(last) - len(tail)] if last.endswith(tail) and tail != last else ""
    if counter in _H:
        base = _H[counter]
        if tail in _TSUMARU and tail != "せん":
            return head + stem + _TSUMARU[tail] + _p(base)
        if tail in ("さん", "せん", "まん") or (counter == "分" and tail == "よん"):
            return head + last + (_p(base) if counter == "分" else _b(base))
        return head + last + base
    if counter in _K or counter in _S:
        base = _K.get(counter) or _S[counter]
        small = {"いち", "はち", "じゅう", "ひゃく"} | ({"ろく"} if counter in _K else set())
        if tail in small:
            return head + stem + _TSUMARU[tail] + base
        if counter == "階" and tail == "さん":
            return head + last + "がい"
        return head + last + base
    reading = _PLAIN[counter]
    if counter in ("年", "時間", "時") and tail == "よん":
        return head + stem + "よ" + reading
    if counter in ("時間", "時") and tail in ("なな", "きゅう"):
        return head + stem + ("しち" if tail == "なな" else "く") + reading
    return head + last + reading


def _b(h: str) -> str:
    return {"は": "ば", "ひ": "び", "ふ": "ぶ", "へ": "べ", "ほ": "ぼ"}[h[0]] + h[1:]


def _p(h: str) -> str:
    return {"は": "ぱ", "ひ": "ぴ", "ふ": "ぷ", "へ": "ぺ", "ほ": "ぽ"}[h[0]] + h[1:]


def how_many(counter: str) -> str:
    """何 with a counter (何匹か なんびきか)."""
    if counter in _H:
        return "なん" + _b(_H[counter])
    return "なん" + (_K.get(counter) or _S.get(counter) or _PLAIN[counter])


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
        before = ja[:i]
        out.append(ja[at:i])
        if re.search(r"(\d|\$N\d+)$", before) and any(surface.startswith(c) for c in COUNTERS):
            out.append(surface)
        else:
            out.append(reading)
        at = i + len(surface)
    out.append(ja[at:])
    return "".join(out)


def name_kana(line: Mapping[str, Any]) -> str:
    """A name as the voice reads it: its katakana when the Japanese is all katakana, else its reading."""
    return line["ja"] if _KATAKANA.match(line["ja"]) else line["reading"]


def replace_names(text: str, lookup: Callable[[str], str | None]) -> tuple[str, list[str]]:
    """Every run of Latin letters replaced by its name's kana; the runs with no name are returned."""
    missing: list[str] = []

    def one(m: re.Match[str]) -> str:
        raw = m.group(0)
        run = names._TRAILING_NUMBER.sub("", raw).rstrip(names._TRAILING).strip()
        kana = lookup(run) if run else None
        if kana is None:
            missing.append(run or raw)
            return raw
        return kana + raw[raw.index(run) + len(run):] if run in raw else kana

    return names._LATIN_RUN.sub(one, text), missing


def spell_numbers(text: str) -> str:
    text = _HOW_MANY.sub(lambda m: how_many(m.group(1)), text)
    text = text.replace("冒険者", "ぼうけんしゃ").replace("数", "すう")  # both put in by speech_text

    def one(m: re.Match[str]) -> str:
        num, space, counter, after = m.group(1), m.group(2), m.group(3), m.group(4)
        if not counter:
            return read_number(num) + space + (m.group(4) or "")
        return with_counter(num, counter) + _AFTER_ONE.sub(lambda a: _AFTER[a.group(0)], after or "")

    return _NUMBER.sub(one, text.replace("～", "から"))


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
    text = spell_numbers(text)
    text, missing = replace_names(text, lookup)
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
