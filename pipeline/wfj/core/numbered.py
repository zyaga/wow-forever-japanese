"""Numbered UI rows (ADR-042): a UI widget's line whose English holds world-state tokens (`%2327w`)
the client replaces with live numbers ("Towers Controlled: %2327w" → "Towers Controlled: 3"). No English
ships, so the addon finds the row by a skeleton: every number run (a token in the English, a digit run in
the live line) becomes `#`, and the skeleton's hash is the row's h1. The Japanese keeps the tokens in
`data/`; the generated row writes each as `%<k>$s`, k its token's place among the English's number runs,
so the addon fills it with the k-th number of the live line (Core/UIStrings index:matchNumbers). Pure: no
I/O."""

from __future__ import annotations

import re

FAMILIES = ("WidgetText",)
TOKEN = re.compile(r"%[0-9]+w")
RUN = re.compile(r"%[0-9]+w|[0-9]+")


def is_numbered(key: str) -> bool:
    return str(key).split(":", 1)[0] in FAMILIES


def skeleton(text: str) -> str:
    """The text with every number run (a token or a digit run) as `#`."""
    return RUN.sub("#", text)


def fill_slots(en: str, ja: str) -> str:
    """The Japanese with each token written `%<k>$s`, k its place among the English's number runs; a token
    the English does not hold raises (the drafts keep every token). A literal number the English writes ("at
    1pm", "every 3 hours") is a number run too. The addon cannot tell it from a token, so a hotfix may change
    it: where the Japanese repeats it as ASCII digits it takes that run's place as well, in order."""
    runs = [m.group(0) for m in RUN.finditer(en)]
    used: set[int] = set()

    def slot(m: re.Match[str]) -> str:
        text = m.group(0)
        if TOKEN.fullmatch(text):
            if text not in runs:
                raise ValueError(f"{text} is not a token of the English {en!r}")
            return f"%{runs.index(text) + 1}$s"
        for i, run in enumerate(runs):  # a literal: the first unused English run of the same value
            if i not in used and run == text:
                used.add(i)
                return f"%{i + 1}$s"
        return text  # a number of the Japanese's own ("午前0時" for "midnight")

    return RUN.sub(slot, ja)
