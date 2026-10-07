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


def base_name(name: str) -> str:
    """A voice's name without its bracketed tail: the engine and the hub write that tail differently
    ("猩々博士 (雑談ボイス)" and "猩々博士（雑談ボイス）")."""
    return re.split(r"[\s(（]", name, maxsplit=1)[0]


def lookup(table: dict[str, str], name: str) -> str | None:
    if name in table:
        return table[name]
    found = {v for k, v in table.items() if base_name(k) == base_name(name)}
    return found.pop() if len(found) == 1 else None


# kinds a voice of either gender may read: a ghost, a dragon or a narrator is cast by sound, not by sex
ANY_GENDER = (
    "ghost",
    "undead",
    "dragon",
    "demon",
    "elemental",
    "giant",
    "mechanical",
    "beast-kin",
    "narrator",
    "book narrator",
)


def kind_gender(name: str) -> str:
    if name in ANY_GENDER:
        return "any"
    return "female" if "female" in name or "girl" in name else "male"


def voice_genders(path: Path | None = None) -> dict[str, str]:
    """voice name → male / female / other, from the catalogue's usable table."""
    usable = (path or CATALOGUE).read_text(encoding="utf-8").split("## Out")[0]
    out = {}
    for line in usable.splitlines():
        cells = [c.strip() for c in line.strip("|").split("|")]
        if line.startswith("| ") and len(cells) >= 8 and cells[6] in ("ACML 1.0", "CC0"):
            g = cells[3].split(",")[0].strip()
            out[cells[0]] = g if g in ("male", "female") else "other"
    return out


def page(items: list[dict[str, Any]], kind_rows: list[dict[str, Any]], texts: list[str]) -> str:
    kinds_json = json.dumps([[k["name"], kind_gender(k["name"])] for k in kind_rows], ensure_ascii=False)
    genders = voice_genders()
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
        gender = lookup(genders, e["name"]) or "other"
        cards.append(
            f'<section class="card" data-id="{e["id"]}" data-gender="{gender}">'
            f"<h3>{html.escape(label)}</h3>{audio}"
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


WOWHEAD = "https://www.wowhead.com/classic/npc="  # a page showing the character


def kind_samples(root: Path, cfg: dict[str, Any], db: Path) -> dict[str, dict[str, Any]]:
    """kind → one real line of it to judge voices on: the speaker who says most in that kind, one of its lines
    of a fitting length (two sentences), and who that speaker is."""
    from wfj.core import casting
    from wfj.io import vmangos
    from wfj.io.jsonl_store import Store

    lines = voice_make.shipped_lines(root)
    values = voice_make.line_values(root, lines)
    profiles = {int(p["creature"]): p for p in voice_make._rows(root / "voice" / "profiles.jsonl")}
    speakers = voice_make._rows(root / "voice" / "speakers.jsonl")
    open_rows = [{**r, "voices": ["x"]} for r in cfg["cast"]]
    kind_of = {}
    for c, pr in profiles.items():
        hit = casting.cast_one(pr, open_rows)
        kind_of[c] = hit[1] if hit else "narrator"
    by_kind: dict[str, dict[Any, list[str]]] = {}
    for r in speakers:
        if r["key"] not in lines:
            continue
        sp = r["speaker"]
        kind = (
            ("book narrator" if r["key"].startswith("b-") else "narrator")
            if sp == voice.NARRATOR
            else kind_of[sp]
        )
        by_kind.setdefault(kind, {}).setdefault(sp, []).append(r["key"])
    english = Store(root, english=True)
    en = {voice.quest_key(x["id"], x["field"]): x["en"] for x in english.load("quest")}
    en |= {voice.gossip_key(x["id"]): x["en"] for x in english.load("gossip")}
    en |= {voice.book_key(x["hash"]): x["en"] for x in english.load("book")}
    names = vmangos.read_creatures(db, {c for c in kind_of})
    unit = {x["id"]: x["en"] for x in english.load("unit") if x.get("field") == "name"}
    out = {}
    for kind, who in by_kind.items():
        sp, keys = max(who.items(), key=lambda kv: len(kv[1]))
        texts = []
        for k in keys:
            try:
                texts.append((k, sample_text(voice.speech_text(lines[k], k, values.get(k, ())), k)))
            except voice.VoiceError:
                continue
        if not texts:
            continue
        good = [t for t in texts if 30 <= len(t[1]) <= 110] or texts
        key, text = sorted(good, key=lambda t: len(t[1]))[len(good) // 2]
        pr = profiles.get(sp, {}) if isinstance(sp, int) else {}
        cr = names.get(sp, {}) if isinstance(sp, int) else {}
        out[kind] = {
            "key": key,
            "text": text,
            "en": " ".join((en.get(key) or "").split())[:300],
            "creature": sp if isinstance(sp, int) else None,
            "name": cr.get("name") or unit.get(sp, "") if isinstance(sp, int) else "",
            "title": cr.get("subname", ""),
            "profile": {f: pr.get(f) for f in casting.FIELDS if pr.get(f)},
            "reason": ((pr.get("provenance") or {}).get("age") or {}).get("reason", ""),
        }
    return out


def _slug(kind: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", kind.lower()).strip("-")


def review(root: Path, cfg: dict[str, Any], store: Path, db: Path, round_: str = "") -> int:
    """DIR/audition/review.html: one row per kind of speaker, biggest first, showing who speaks (name, title,
    race, gender, age, a link to see the character) and one of their real lines read by each candidate voice
    (DIR/audition/candidates.json). The choices are saved to picks.json, which `apply` reads."""
    folder = store / "audition"
    cands: dict[str, list[str]] = json.loads(
        (folder / f"candidates{round_}.json").read_text(encoding="utf-8")
    )
    picked: dict[str, list[str]] = {}
    if round_ and (folder / "picks.json").is_file():  # a later round shows the earlier picks
        picked = json.loads((folder / "picks.json").read_text(encoding="utf-8"))
    items = {e["id"]: e for e in json.loads((folder / "voices.json").read_text(encoding="utf-8"))}
    samples = kind_samples(root, cfg, db)
    # a round may pin the line a kind is heard on (one that sounded wrong in game): {"_lines": {kind: key}}
    pinned = cands.pop("_lines", {})
    if pinned:
        lines = voice_make.shipped_lines(root)
        values = voice_make.line_values(root, lines)
    for kind, key in pinned.items():
        blank = {"creature": None, "name": "", "title": "", "profile": {}, "reason": ""}
        sm = samples.setdefault(kind, blank)
        sm.update(key=key, en="", text=voice.speech_text(lines[key], key, values.get(key, ())))
    counts = {k["name"]: k for k in kinds(root, cfg)}
    engine = Engine(cfg["engine"])
    speed = float(cfg.get("speed_scale", 0.9))
    (folder / "review").mkdir(exist_ok=True)
    rows = []
    order = sorted(cands.items(), key=lambda kv: -counts.get(kv[0], {}).get("lines", 0))
    for n, (kind, vids) in enumerate(order):
        sm = samples.get(kind)
        if not sm:
            continue
        players = []
        for vid in vids:
            e = items[vid]
            f = folder / "review" / f"{_slug(kind)}-{vid}.mp3"
            if not f.is_file():
                wav = engine.synthesize(
                    sm["text"], e["style"], e["speed"] or speed, e["pitch"], e["intonation"]
                )
                voice_make.to_mp3(wav, f)
            label = f"{e['name']} · {e['style_name']}" + (f" · {e['try']}" if e["try"] else "")
            if round_:
                label += " · your pick" if vid in picked.get(kind, []) else " · suggested"
            players.append(
                f'<div class="v" data-id="{vid}">'
                f'<audio controls preload="none" src="review/{f.name}"></audio>'
                f'<span class="pick">{html.escape(label)}</span></div>'
            )
        c = counts.get(kind, {})
        prof = ", ".join(str(v) for v in sm["profile"].values())
        who = html.escape(
            sm["name"] or ("an NPC whose name we lack" if sm["creature"] else "the narrator")
        ) + (f" &lt;{html.escape(sm['title'])}&gt;" if sm["title"] else "")
        link = (
            f' · <a href="{WOWHEAD}{sm["creature"]}" target="_blank">see the character</a>'
            if sm["creature"]
            else ""
        )
        rows.append(
            f'<section class="row" data-kind="{html.escape(kind)}"><h3>{html.escape(kind)}'
            f" <small>{c.get('creatures', 0)} creatures, {c.get('lines', 0)} lines</small></h3>"
            f'<p class="who">Speaking: <b>{who}</b> ({html.escape(prof)}){link}'
            f"<br><i>{html.escape(sm['reason'])}</i></p>"
            f'<p class="line">{html.escape(sm["text"])}<br>'
            f'<span class="en">{html.escape(sm["en"])}</span></p>'
            f"{''.join(players)}</section>"
        )
        print(f"voice audition: review {n + 1}/{len(order)} {kind}", flush=True)
    template = (Path(__file__).resolve().parents[1] / "emit" / "review_page.html").read_text("utf-8")
    page_name = f"review{round_}.html"
    (folder / page_name).write_text(template.replace("@@ROWS@@", "".join(rows)), encoding="utf-8")
    print(f"voice audition: {folder / page_name}")
    return 0


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
        licence = lookup(allowed, e["name"])
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
    p.add_argument("cmd", choices=("build", "review", "serve", "apply"))
    p.add_argument("--vmangos", help="the VMaNGOS database, for the speakers' names (review)")
    p.add_argument("--round", default="", help="a later review round: candidates<N>.json → review<N>.html")
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
        if a.cmd == "review":
            return review(
                data_root(), voice_make.load_config(Path(a.config)), store, Path(a.vmangos), a.round
            )
        return build(data_root(), voice_make.load_config(Path(a.config)), store)
    except (EngineError, ValueError, FileNotFoundError, KeyError) as e:
        print(f"voice audition: {e}", file=sys.stderr)
        return 1
