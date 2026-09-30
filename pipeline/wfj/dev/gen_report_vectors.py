"""Generate the shared fix-report vectors: canonical JSONL + a Lua twin for busted.

Usage: python -m wfj.dev.gen_report_vectors <vectors-dir>
`cases`: the pending fixes the addon holds → the report text `Core/ReportText.lua` must write byte for byte
and `core/fix_report.parse` must read back to the same fixes. `bad`: texts the parser refuses, with a piece of
the message. Both files are committed; tests/python/test_fix_report.py fails if a regeneration differs.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from wfj.core import fix_report
from wfj.core.readings import ja_hash
from wfj.emit.lua_writer import lua_string

JA1 = "Kobold Verminを10体倒せ。"
JA2 = "旅人よ、よく来た。\n\nこの地は長く闇に包まれている。"
JA3 = "パイプ|記号\\と改行\nを含む行"
NOTE_MAX = "あ" * 66 + "ab"  # 198 + 2 = 200 bytes
JA_MAX = "日" * 2666 + "ab"  # 7998 + 2 = 8000 bytes
# shipped Japanese holds carriage returns (a `\r\n` popup line, a `\n\r` book page)
JA_CR = "全部売却しますか？\r\n続行しますか？\n\rStone"


def _fix(type_: str, id_: int | str, field: str, ja: str, reason: str, note: str = "", sug: str = "") -> dict:
    d: dict[str, Any] = {"type": type_, "id": id_, "field": field, "ja_hash": ja_hash(ja), "reason": reason}
    if note:
        d["note"] = note
    if sug:
        d["ja"] = sug
    return d


CASES: list[tuple[str, str, str, list[dict]]] = [
    ("one-plain", "1.0.0", "1.60.1.70009", [_fix("quest", 783, "objectives", JA1, "wrong")]),
    (
        "note-and-ja",
        "1.0.0",
        "1.60.1.70009",
        [
            _fix(
                "quest",
                7,
                "description",
                JA2,
                "awkward",
                note="stiff wording",
                sug="旅の者よ、よく来てくれた。\n\n長い間、この地は闇の中だ。",
            ),
        ],
    ),
    (
        "escapes",
        "1.0.0",
        "1.60.1.70009",
        [
            _fix(
                "gossip", "0001ce030c010973", "text", JA3, "typo", note="a | and a \\ here", sug=JA3 + "|x\\n"
            ),
        ],
    ),
    (
        "keys",
        "0.9.2-beta",
        "1.60.1.69913",
        [
            _fix("ui", "ItemSubClass:2:3", "text", "銃", "name"),
            _fix("ui", "ABANDON_QUEST", "text", "クエスト放棄", "other", note="short"),
            _fix("book", "8f0e2a11b3c4d5e6", "text", "古い手紙", "awkward"),
            _fix("item", 2589, "description", "布の切れ端。", "typo", sug="布の切れ端"),
            _fix("spell", 133, "aura", "炎上中。", "wrong"),
            _fix("objective", 4021, "text", "Drullを救出", "name"),
            _fix("area", 76, "text", "Fargodeep Mineを調査する", "other"),
        ],
    ),
    (
        "max-sizes",
        "1.0.0",
        "1.60.1.70009",
        [
            _fix("quest", 12, "completion", "よくやった。", "awkward", note=NOTE_MAX, sug=JA_MAX),
        ],
    ),
    ("unknown-build", "?", "?", [_fix("quest", 1, "title", "「Chow」クエスト", "other")]),
    (
        "carriage-returns",
        "@project-version@",
        "1.60.1.70009",
        [_fix("ui", "SELL_ALL_JUNK_ITEMS_POPUP", "text", JA_CR, "typo", sug=JA_CR.replace("続行", "続けて"))],
    ),
]

H = ja_hash(JA1)
GOOD_HEAD = "WFJ-REPORT 1\naddon 1.0.0 client 1.60.1.70009\n"
BAD: list[tuple[str, str, str]] = [
    ("no-header", "hello\nfix quest 1 title " + H + " wrong\nend 1\n", "no report found"),
    ("version", "WFJ-REPORT 2\naddon 1 client 2\nend 0\n", "unknown report version"),
    ("no-addon-line", "WFJ-REPORT 1\nfix quest 1 title " + H + " wrong\nend 1\n", "expected `addon"),
    ("cut-no-end", GOOD_HEAD + "fix quest 1 title " + H + " wrong\n", "no `end` line"),
    ("cut-count", GOOD_HEAD + "fix quest 1 title " + H + " wrong\nend 2\n", "the paste was cut"),
    ("type", GOOD_HEAD + "fix npc 1 title " + H + " wrong\nend 1\n", "unknown type"),
    ("field", GOOD_HEAD + "fix quest 1 name " + H + " wrong\nend 1\n", "has no field"),
    ("hash", GOOD_HEAD + "fix quest 1 title ABCDEF wrong\nend 1\n", "16 lowercase hex"),
    ("reason", GOOD_HEAD + "fix quest 1 title " + H + " bad\nend 1\n", "unknown reason"),
    ("numeric-id", GOOD_HEAD + "fix quest 012 title " + H + " wrong\nend 1\n", "positive number"),
    ("gossip-id", GOOD_HEAD + "fix gossip 12 text " + H + " wrong\nend 1\n", "16 lowercase hex"),
    ("ui-id", GOOD_HEAD + "fix ui not_a_key text " + H + " wrong\nend 1\n", "not a UI key"),
    ("note-first", GOOD_HEAD + "note hi\nfix quest 1 title " + H + " wrong\nend 1\n", "before any `fix`"),
    (
        "note-twice",
        GOOD_HEAD + "fix quest 1 title " + H + " wrong\nnote a\nnote b\nend 1\n",
        "repeated or out",
    ),
    (
        "note-after-ja",
        GOOD_HEAD + "fix quest 1 title " + H + " wrong\nja あ\nnote b\nend 1\n",
        "repeated or out",
    ),
    ("bad-escape", GOOD_HEAD + "fix quest 1 title " + H + " wrong\nja a\\tb\nend 1\n", "bad escape"),
    ("note-newline", GOOD_HEAD + "fix quest 1 title " + H + " wrong\nnote a\\nb\nend 1\n", "one line"),
    (
        "note-long",
        GOOD_HEAD + "fix quest 1 title " + H + " wrong\nnote " + NOTE_MAX + "x\nend 1\n",
        "over 200",
    ),
    ("ja-long", GOOD_HEAD + "fix quest 1 title " + H + " wrong\nja " + JA_MAX + "x\nend 1\n", "over 8000"),
    (
        "note-cr",
        GOOD_HEAD + "fix quest 1 title " + H + " wrong\nnote a\\rb\nend 1\n",
        "one line",
    ),
    # the header's tokens are echoed in the issue comment, so nothing in them may render
    (
        "header-markdown",
        "WFJ-REPORT 1\naddon ![x](https://e.example/p.png) client @octocat\nend 0\n",
        "expected `addon",
    ),
    ("header-long", "WFJ-REPORT 1\naddon " + "1" * 41 + " client 2\nend 0\n", "expected `addon"),
    ("empty-ja", GOOD_HEAD + "fix quest 1 title " + H + " wrong\nja \nend 1\n", "an empty `ja`"),
    (
        "duplicate",
        GOOD_HEAD + "fix quest 1 title " + H + " wrong\nfix quest 1 title " + H + " typo\nend 2\n",
        "already reported",
    ),
    ("two-reports", GOOD_HEAD + "end 0\n" + GOOD_HEAD + "end 0\n", "a second report"),
    ("stray", GOOD_HEAD + "hello there\nend 0\n", "unexpected line"),
]


def build() -> dict[str, list[dict]]:
    cases = []
    for cid, addon, client, fixes in CASES:
        rep = fix_report.Report(addon=addon, client=client, fixes=[fix_report.Fix(**f) for f in fixes])
        cases.append(
            {"id": cid, "addon": addon, "client": client, "fixes": fixes, "text": fix_report.render(rep)}
        )
    bad = [{"id": bid, "text": text, "error": err} for bid, text, err in BAD]
    return {"cases": cases, "bad": bad}


def _lua_value(v: Any) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return lua_string(v)
    if isinstance(v, list):
        return "{ " + ", ".join(_lua_value(x) for x in v) + " }"
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{k} = {_lua_value(x)}" for k, x in v.items()) + " }"
    raise TypeError(type(v))


def to_lua(v: dict[str, list[dict]]) -> str:
    lines = [
        "-- GENERATED by pipeline/wfj/dev/gen_report_vectors.py from report_vectors.jsonl. Do not edit.",
        "return { cases = {",
    ]
    lines += [f"  {_lua_value(c)}," for c in v["cases"]]
    lines.append("}, bad = {")
    lines += [f"  {_lua_value(b)}," for b in v["bad"]]
    lines.append("} }")
    return "\n".join(lines) + "\n"


def write(out_dir: Path) -> None:
    v = build()
    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "report_vectors.jsonl").open("w", encoding="utf-8") as f:
        for kind in ("cases", "bad"):
            for row in v[kind]:
                f.write(
                    json.dumps({"kind": kind[:-1] if kind == "cases" else kind, **row}, ensure_ascii=False)
                    + "\n"
                )
    (out_dir / "report_vectors.lua").write_text(to_lua(v), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    out = Path(args[0]) if args else Path(__file__).resolve().parents[3] / "vectors"
    write(out)
    print(f"wrote {out / 'report_vectors.jsonl'} and .lua ({len(CASES)} cases, {len(BAD)} bad)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
