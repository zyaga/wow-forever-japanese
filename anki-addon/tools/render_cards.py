"""Draws the add-on's cards as pictures, without Anki: every card choice, front and back, light and dark, at a
desktop and a phone width, for a Japanese word and an English one. For looking at the design, and for the
docs.

    python anki-addon/tools/render_cards.py <out folder> [--chrome <path>] [--image <file>]

`render(template, fields)` fills a template the way Anki does for the parts these templates use: `{{Field}}`,
`{{furigana:Field}}`, `{{kanji:Field}}`, `{{#Field}}…{{/Field}}` and `{{^Field}}…{{/Field}}`.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ADDON = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ADDON))

from wfj_anki import notetype, plan  # noqa: E402
from wfj_anki.settings import FRONTS, Settings  # noqa: E402

_SECTION = re.compile(r"\{\{([#^])([^}]+)\}\}(.*?)\{\{/\2\}\}", re.DOTALL)
_FIELD = re.compile(r"\{\{(?:(furigana|kanji):)?([^}#^/]+)\}\}")
# Anki's furigana filter: the text since the last space or tag, then its reading in brackets
_RUBY = re.compile(r" ?([^ >]+?)\[(.+?)\]")
_SOUND = re.compile(r"\[sound:[^\]]+\]")
_PLAY = (
    '<a class="replay-button soundLink" href="#"><svg class="playImage" viewBox="0 0 64 64" version="1.1">'
    '<circle cx="32" cy="32" r="29" /><path d="M56.502,32.301l-37.502,20.101l0.329,-40.804l37.173,20.703Z" />'
    "</svg></a>"
)

CHROMES = (
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "google-chrome",
    "chromium",
    "chrome",
)


def render(template: str, fields: dict[str, str]) -> str:
    def section(match: re.Match[str]) -> str:
        has = fields.get(match.group(2).strip(), "").strip() != ""
        return match.group(3) if has == (match.group(1) == "#") else ""

    before = None
    while before != template:  # a section inside a section
        before, template = template, _SECTION.sub(section, template)

    def field(match: re.Match[str]) -> str:
        text = fields.get(match.group(2).strip(), "")
        if match.group(1) == "furigana":
            text = _RUBY.sub(r"<ruby><rb>\1</rb><rt>\2</rt></ruby>", text)
        elif match.group(1) == "kanji":
            text = _RUBY.sub(r"\1", text)
        return _SOUND.sub(_PLAY, text)

    return _FIELD.sub(field, template)


def samples(image: str) -> dict[str, dict[str, str]]:
    blank = dict.fromkeys(plan.FIELDS, "")
    japanese = dict(
        blank,
        **{
            "Key": "quest.description:456:足を伸ばす",
            "Word": "足を伸ばして",
            "Reading": "あしをのばして",
            "Dictionary form": "足を伸ばす",
            "Its reading": "あしをのばす",
            "Meaning": "journey forth (travel a bit farther)",
            "Sentence": "少[すこ]し<b>足[あし]を 伸[の]ばして</b>BoarとSaberを 狩[か]り、 数[かず]を 減[へ]らしてやって 欲[ほ]しいのだ。",
            "Word (furigana)": "足[あし]を 伸[の]ばして",
            "Image": f'<img src="{image}">' if image else "",
            "Audio": "[sound:wfj-quest-456-4.mp3]",
            "Source": "quest",
            "Quest": "自然界のバランス",
            "Quest ID": "456",
            "Saved": "2026-11-25",
        },
    )
    english = dict(
        blank,
        **{
            "Key": "quest.description:456:en:candles",
            "Word": "candles",
            "Reading": "KAN-dlz",
            "Meaning": "ろうそく",
            "Sentence": "Bring me eight of their <b>candles</b>, and be quick about it.",
            "Word (furigana)": "candles",
            "Japanese sentence": "ろうそくを八本持ち帰ってほしい。",
            "Audio": "[sound:wfj-quest-456-2.mp3]",
            "Source": "quest",
            "Quest": "コボルドのろうそく",
            "Saved": "2026-11-25",
            "Lang": "en",
        },
    )
    return {"japanese": japanese, "english": english}


def page(body: str, css: str, night: bool) -> str:
    classes = "card nightMode" if night else "card"
    return (
        f'<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
        f"<style>html{{background:{'#07080c' if night else '#efe9dd'}}}{css}</style></head>"
        f'<body class="{classes}">{body}</body></html>'
    )


def pages(image: str) -> dict[str, str]:
    """Every picture's page, by file stem: <word>-<front choice>-<side>-<light|dark>."""
    out = {}
    for word, fields in samples(image).items():
        for front in FRONTS:
            # the audio is drawn on both sides: where the button sits is what there is to look at
            q, a, css = notetype.card(Settings(front=front, audio="front"))
            for side, template in (("front", q), ("back", a)):
                if side == "back" and front != FRONTS[0]:
                    continue  # the back is the same for both fronts
                for night in (False, True):
                    stem = f"{word}-{front}-{side}-{'dark' if night else 'light'}"
                    out[stem] = page(render(template, fields), css, night)
    return out


def chrome(given: str | None) -> str:
    for name in ([given] if given else []) + list(CHROMES):
        found = name if Path(name).is_file() else shutil.which(name)
        if found:
            return found
    raise SystemExit("no Chrome found: pass --chrome <path>")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("out", type=Path)
    parser.add_argument("--chrome")
    parser.add_argument("--image", type=Path, help="a screenshot to stand in for the saved word's image")
    args = parser.parse_args()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    image = ""
    if args.image:
        shutil.copyfile(args.image, args.out / args.image.name)
        image = args.image.name
    browser = chrome(args.chrome)
    made = []
    for stem, html in pages(image).items():
        source = args.out / f"{stem}.html"
        source.write_text(html, encoding="utf-8")
        for device, width, height in (("desktop", 900, 1100), ("phone", 390, 1000)):
            picture = args.out / f"{stem}-{device}.png"
            picture.unlink(missing_ok=True)
            # a headless window is never narrower than about 500px, so the card is laid out in a frame of the
            # device's width and the picture is cut to it
            frame = args.out / f"{stem}-{device}.frame.html"
            frame.write_text(
                f'<!doctype html><body style="margin:0;background:#000"><iframe src="{source.name}" '
                f'style="border:0;display:block;width:{width}px;height:{height}px"></iframe></body>',
                encoding="utf-8",
            )
            subprocess.run(
                [
                    browser,
                    "--headless=new",
                    "--disable-gpu",
                    "--hide-scrollbars",
                    "--allow-file-access-from-files",
                    f"--window-size={width},{height}",
                    "--force-device-scale-factor=2",
                    f"--screenshot={picture}",
                    frame.as_uri(),
                ],
                check=True,
                capture_output=True,
                timeout=120,
            )
            made.append(picture)
    missing = [str(p) for p in made if not p.is_file() or p.stat().st_size == 0]
    if missing:
        raise SystemExit("not drawn: " + ", ".join(missing))
    print(f"{len(made)} pictures in {args.out}")


if __name__ == "__main__":
    main()
