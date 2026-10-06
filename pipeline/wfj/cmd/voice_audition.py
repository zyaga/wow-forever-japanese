"""wfj voice audition build|serve|apply: choose the voices by ear (ADR-062; runbook docs/operations/voice.md).

build [--config voice.toml] [--store DIR]
    Every voice the engine has (each useful style, and a few pitch or pace tries for the bands the catalogue
    lacks: older women, children) reads the same two lines from the shipped Japanese into
    DIR/audition/clips/, and DIR/audition/index.html lists them beside the kinds of speaker (voice.toml's
    cast rows, with how many creatures and lines each one reads).
serve [--store DIR] [--port 8766]
    Serves that page on localhost only; each tick on the page is saved at once to DIR/audition/picks.json.
apply [--config voice.toml] [--store DIR]
    Writes the picks into voice.toml: a roster entry per picked voice, and each cast row's voices.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from collections import Counter
from collections.abc import Sequence
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from wfj.cmd import voice_make
from wfj.core import voice
from wfj.io.aivis import Engine, EngineError
from wfj.paths import data_root

# The two lines every voice reads: a quest offer and a greeting, the same for all so voices compare fairly.
SAMPLE_KEYS = ("456-description", "457-completion")
# Styles worth hearing beside a voice's first one (calmer, heavier, older readings).
EXTRA_STYLES = ("Calm", "Heavy", "落ち着き", "おちつき", "標準")
# Tries for the bands no voice covers: (voice name, style name or None, pitch, speed, intonation, label)
TRIES = (
    ("morioki", None, -0.05, 0.85, 1.0, "older"),
    ("morioki", None, -0.1, 0.8, 0.9, "elderly"),
    ("みちのくあいり", None, -0.05, 0.85, 1.0, "older"),
    ("阿井田 茂", "Heavy", -0.05, 0.85, 1.0, "elderly"),
    ("コハク", None, 0.08, 0.95, 1.1, "child"),
    ("yukyu", None, 0.1, 0.95, 1.1, "child"),
)
_FIRST_SENTENCES = re.compile(r"^(.+?。.*?。)")


def sample_text(ja: str, key: str) -> str:
    """The first two sentences of a line, as the engine reads them."""
    text = voice.speech_text(ja, key).replace("\n", "")
    m = _FIRST_SENTENCES.match(text)
    return m.group(1) if m else text[:120]


def entries(speakers: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Every clip to make: each voice's first style, its calmer styles, then the tries."""
    out: list[dict[str, Any]] = []
    by_name = {sp["name"]: sp for sp in speakers}
    for sp in speakers:
        styles = sp.get("styles", [])
        picked = styles[:1] + [st for st in styles[1:] if st["name"] in EXTRA_STYLES]
        for st in picked:
            out.append(
                {
                    "id": f"v{st['id']}",
                    "name": sp["name"],
                    "uuid": sp["speaker_uuid"],
                    "style": st["id"],
                    "style_name": st["name"],
                    "pitch": 0.0,
                    "speed": None,
                    "intonation": 1.0,
                    "try": "",
                }
            )
    for name, style_name, pitch, speed, inton, label in TRIES:
        sp = next((s for n, s in by_name.items() if n.startswith(name)), None)
        if not sp:
            continue
        st = next((x for x in sp["styles"] if style_name is None or x["name"] == style_name), sp["styles"][0])
        out.append(
            {
                "id": f"v{st['id']}{label}",
                "name": sp["name"],
                "uuid": sp["speaker_uuid"],
                "style": st["id"],
                "style_name": st["name"],
                "pitch": pitch,
                "speed": speed,
                "intonation": inton,
                "try": label,
            }
        )
    return out


def kinds(root: Path, cfg: dict[str, Any]) -> list[dict[str, Any]]:
    """voice.toml's cast rows with how many creatures and lines each would read if it had a voice."""
    from wfj.core import casting

    profiles = voice_make._rows(root / "voice" / "profiles.jsonl")
    speakers = voice_make._rows(root / "voice" / "speakers.jsonl")
    lines: Counter[int] = Counter()
    for r in speakers:
        for c in (r["speaker"], *r.get("others", ())):
            if isinstance(c, int):
                lines[c] += 1
    open_rows = [{**r, "voices": ["x"]} for r in cfg["cast"]]  # as if every row were cast
    creatures: Counter[str] = Counter()
    said: Counter[str] = Counter()
    for p in profiles:
        hit = casting.cast_one(p, open_rows)
        name = hit[1] if hit else "narrator"
        creatures[name] += 1
        said[name] += lines[int(p["creature"])]
    out = [
        {"name": r["name"], "creatures": creatures[r["name"]], "lines": said[r["name"]]} for r in cfg["cast"]
    ]
    narrator = sum(1 for r in speakers if r["speaker"] == voice.NARRATOR)
    out += [
        {
            "name": "narrator",
            "creatures": 0,
            "lines": narrator - sum(1 for r in speakers if r["key"][:2] == "b-"),
        },
        {"name": "book narrator", "creatures": 0, "lines": sum(1 for r in speakers if r["key"][:2] == "b-")},
    ]
    return out


def page(items: list[dict[str, Any]], kind_rows: list[dict[str, Any]], texts: list[str]) -> str:
    kinds_json = json.dumps([k["name"] for k in kind_rows], ensure_ascii=False)
    counts = "".join(
        f"<tr><td>{html.escape(k['name'])}</td><td>{k['creatures']}</td><td>{k['lines']}</td></tr>"
        for k in kind_rows
    )
    cards = []
    for e in items:
        label = f"{e['name']} · {e['style_name']}" + (f" · try: {e['try']}" if e["try"] else "")
        audio = "".join(
            f'<audio controls preload="none" src="clips/{e["id"]}-{n}.mp3"></audio>' for n in (1, 2)
        )
        cards.append(
            f'<section class="card" data-id="{e["id"]}"><h3>{html.escape(label)}</h3>{audio}'
            f'<div class="chips"></div></section>'
        )
    samples = "".join(f"<li>{html.escape(t)}</li>" for t in texts)
    template = (Path(__file__).resolve().parents[1] / "emit" / "audition_page.html").read_text("utf-8")
    return (
        template.replace("@@KINDS@@", kinds_json)
        .replace("@@COUNTS@@", counts)
        .replace("@@SAMPLES@@", samples)
        .replace("@@CARDS@@", "".join(cards))
    )


def build(root: Path, cfg: dict[str, Any], store: Path) -> int:
    engine = Engine(cfg["engine"])
    out = store / "audition"
    (out / "clips").mkdir(parents=True, exist_ok=True)
    lines = voice_make.shipped_lines(root)
    texts = [sample_text(lines[k], k) for k in SAMPLE_KEYS]
    items = entries(engine.speakers())
    speed = float(cfg.get("speed_scale", 0.9))
    for n, e in enumerate(items, 1):
        for i, t in enumerate(texts, 1):
            f = out / "clips" / f"{e['id']}-{i}.mp3"
            if f.is_file():
                continue
            wav = engine.synthesize(t, e["style"], e["speed"] or speed, e["pitch"], e["intonation"])
            voice_make.to_mp3(wav, f)
        print(f"voice audition: {n}/{len(items)} {e['name']} {e['style_name']} {e['try']}", flush=True)
    (out / "voices.json").write_text(json.dumps(items, ensure_ascii=False, indent=1), encoding="utf-8")
    (out / "index.html").write_text(page(items, kinds(root, cfg), texts), encoding="utf-8")
    print(f"voice audition: {len(items)} voices → {out / 'index.html'}")
    return 0


def serve(store: Path, port: int) -> int:
    folder = store / "audition"

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *a: Any, **k: Any) -> None:
            super().__init__(*a, directory=str(folder), **k)

        def do_POST(self) -> None:  # noqa: N802 (the stdlib's method name)
            if self.path != "/picks":
                self.send_error(404)
                return
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            try:
                picks = json.loads(body)
                assert isinstance(picks, dict)
            except (ValueError, AssertionError):
                self.send_error(400)
                return
            (folder / "picks.json").write_text(
                json.dumps(picks, ensure_ascii=False, indent=1), encoding="utf-8"
            )
            self.send_response(204)
            self.end_headers()

    print(f"voice audition: http://127.0.0.1:{port}/ (Ctrl-C stops)", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
    return 0


CATALOGUE = Path(__file__).resolve().parents[3] / "docs" / "research" / "2026-10-06-voice-casting.md"


def licences(path: Path = CATALOGUE) -> dict[str, str]:
    """voice name → its licence, from the usable table of the catalogue (the only voices we may use)."""
    usable = path.read_text(encoding="utf-8").split("## Out")[0]
    out = {}
    for line in usable.splitlines():
        cells = [c.strip() for c in line.strip("|").split("|")]
        if line.startswith("| ") and len(cells) >= 8 and cells[6] in ("ACML 1.0", "CC0"):
            out[cells[0]] = cells[6]
    return out


def apply(cfg_path: Path, store: Path) -> int:
    """Picks → voice.toml: a roster table per picked voice (appended), each cast row's voices replaced."""
    folder = store / "audition"
    picks: dict[str, list[str]] = json.loads((folder / "picks.json").read_text(encoding="utf-8"))
    items = {e["id"]: e for e in json.loads((folder / "voices.json").read_text(encoding="utf-8"))}
    text = cfg_path.read_text(encoding="utf-8")
    cfg = voice_make.load_config(cfg_path)
    used = sorted({v for vs in picks.values() for v in vs})
    allowed = licences()
    roster_add = []
    for vid in used:
        if vid in cfg["roster"]:
            continue
        e = items[vid]
        licence = allowed.get(e["name"])
        if licence is None:
            raise ValueError(f"{e['name']} is not in the catalogue's usable voices")
        lines = [
            f"[roster.{vid}]",
            f"model = {json.dumps(e['name'], ensure_ascii=False)}",
            f"style = {e['style']} # {e['style_name']}",
            f'licence = "{licence}"',
            f"fits = {json.dumps('picked at the audition' + (' (' + e['try'] + ')' if e['try'] else ''))}",
        ]
        if e["pitch"]:
            lines.append(f"pitch = {e['pitch']}")
        if e["speed"]:
            lines.append(f"speed = {e['speed']}")
        if e["intonation"] != 1.0:
            lines.append(f"intonation = {e['intonation']}")
        roster_add.append("\n".join(lines) + "\n")
    for name, vids in picks.items():
        pat = re.compile(r'(name = "' + re.escape(name) + r'"\nwhen = [^\n]*\nvoices = )\[[^\]]*\]')
        new = "[" + ", ".join(f'"{v}"' for v in vids) + "]"
        text, n = pat.subn(lambda m, new=new: m.group(1) + new, text)
        if not n and name not in ("narrator", "book narrator"):
            print(f"voice audition: no cast row named {name!r}", file=sys.stderr)
    for key, name in (("narrator", "narrator"), ("book_narrator", "book narrator")):
        if picks.get(name):
            text = re.sub(rf'^{key} = "[^"]*"', f'{key} = "{picks[name][0]}"', text, flags=re.M)
    marker = "# Cast rows, first match wins."
    text = text.replace(marker, "".join(a + "\n" for a in roster_add) + marker, 1)
    cfg_path.write_text(text, encoding="utf-8")
    voice_make.load_config(cfg_path)  # refuses a broken result before anything casts with it
    print(f"voice audition: {len(picks)} kinds, {len(used)} voices → {cfg_path.name}")
    return 0


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj voice audition")
    p.add_argument("cmd", choices=("build", "serve", "apply"))
    p.add_argument("--config", default="voice.toml")
    p.add_argument("--store")
    p.add_argument("--port", type=int, default=8766)
    a = p.parse_args(list(argv))
    store = voice_make.store_dir(a.store)
    try:
        if a.cmd == "serve":
            return serve(store, a.port)
        if a.cmd == "apply":
            return apply(Path(a.config), store)
        return build(data_root(), voice_make.load_config(Path(a.config)), store)
    except (EngineError, ValueError, FileNotFoundError, KeyError) as e:
        print(f"voice audition: {e}", file=sys.stderr)
        return 1
