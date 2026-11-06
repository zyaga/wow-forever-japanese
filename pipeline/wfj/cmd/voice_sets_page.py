"""wfj voice sets-page build|serve|apply: the listening page for the game voice sets (ADR-074;
runbook docs/operations/voice.md).

  build [--store DIR]
      Makes, for every set, the same line read as a voice-only copy and as a full copy (a male or a female
      wording by the set's gender), joins its game barks into one clip, and copies today's AivisSpeech take
      of one of its NPCs' lines; then writes the page. Takes that exist are kept, so a rebuild only makes what
      changed. One low-priority Qwen3-TTS run.
  serve [--port 8767]
      Serves the page on localhost only; each pick or tick is saved at once.
  apply
      Writes the saved picks into pipeline/voice.toml's [sets] tables. Then `make voice-cast` recasts the NPCs
      of the changed sets and `make voice-generate` remakes their lines.

Everything the page holds stays in build/voice-sets/page of the main checkout: it carries the game's own
audio.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import sys
from collections.abc import Sequence
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from wfj.cmd import voice_make
from wfj.cmd import voice_sets as vs
from wfj.core import casting, voice_sets
from wfj.io.qwen import Qwen
from wfj.paths import data_root

LINES = {
    "male": "ようこそ、冒険者よ。北の森で狼が増えすぎて困っているのだ。手を貸してもらえないだろうか。",
    "female": "いらっしゃい、冒険者さん。北の森で狼が増えすぎて困っているの。手を貸してもらえないかしら。",
}
PICKS = ("voice", "full", "keep")
CONFIG = Path(__file__).resolve().parents[2] / "voice.toml"


def page_dir() -> Path:
    return vs.clip_dir() / "page"


def todays_takes(root: Path, cfg: dict[str, Any], store: Path) -> dict[str, tuple[str, str]]:
    """set → (an audio file of the store in the NPC's AivisSpeech voice, its Japanese), for one NPC of each
    set that has such a take."""
    overrides = {int(r["creature"]): r["voice"] for r in vs._rows(root / "voice" / "overrides.jsonl")}
    plain = casting.cast(vs._rows(root / "voice" / "profiles.jsonl"), cfg["cast"], cfg["narrator"], overrides)
    lines = voice_make.shipped_lines(root)
    said: dict[int, list[str]] = {}
    for r in vs._rows(root / "voice" / "speakers.jsonl"):
        if isinstance(r["speaker"], int) and r["key"] in lines:
            said.setdefault(r["speaker"], []).append(r["key"])
    audio = voice_make.audio_record(root)
    out: dict[str, tuple[str, str]] = {}
    for c, sets in sorted(vs.creature_sets(root).items()):
        s = sets.get("male") or sets.get("female")
        if not s or s in out or c not in plain:
            continue
        for key in sorted(said.get(c, []), key=lambda k: len(lines[k])):
            rec = audio.get(key)
            if rec and rec["voice"] == plain[c]["voice"] and voice_make.audio_file(store, key).is_file():
                out[s] = (str(voice_make.audio_file(store, key)), lines[key])
                break
    return out


def rows(root: Path) -> list[dict[str, Any]]:
    """One row per set: its name parts, gender and how many speaking NPCs speak with it."""
    count: dict[str, int] = {}
    for sets in vs.creature_sets(root).values():
        for g in voice_sets.GENDERS:
            if g in sets:
                count[sets[g]] = count.get(sets[g], 0) + 1
    out = []
    for s in sorted(vs.catalogue(root)):
        race, gender, flavour = voice_sets.parse(s) or ("", "", "")
        out.append({"set": s, "race": race, "gender": gender, "flavour": flavour, "npcs": count.get(s, 0)})
    return out


def current_picks(cfg_path: Path, saved: Path) -> dict[str, dict[str, Any]]:
    """set → {"pick", "decided"}: voice.toml's [sets], with picks saved on the page since then on top."""
    cfg = voice_make.load_config(cfg_path)
    out = {s: {"pick": e.get("pick", "keep"), "decided": bool(e.get("decided"))}
           for s, e in cfg.get("sets", {}).items()}
    if saved.is_file():
        out.update(json.loads(saved.read_text(encoding="utf-8")))
    return out


def page(set_rows: list[dict[str, Any]], picks: dict[str, dict[str, Any]], files: dict[str, dict[str, str]],
         today_text: dict[str, str]) -> str:
    def audio(name: str | None) -> str:
        return f'<audio controls preload="none" src="{html.escape(name)}"></audio>' if name else "<i>none</i>"

    body = []
    for r in set_rows:
        s, p = r["set"], picks.get(r["set"], {"pick": "keep", "decided": False})
        f = files.get(s, {})
        radios = "".join(
            f'<label><input type="radio" name="{s}" value="{v}"{" checked" if p["pick"] == v else ""}>'
            f" {v}</label> "
            for v in PICKS
        )
        ticked = " checked" if p["decided"] else ""
        tick = f'<label><input type="checkbox" data-set="{s}"{ticked}> decided</label>'
        said = html.escape(today_text.get(s, "")[:60])
        body.append(
            f'<tr id="{s}"><td><b>{r["race"]} {r["gender"]} {r["flavour"]}</b><br>'
            f'<small>{s}, {r["npcs"]} NPCs</small></td><td>{audio(f.get("game"))}</td>'
            f'<td>{audio(f.get("voice"))}</td><td>{audio(f.get("full"))}</td>'
            f"<td>{audio(f.get('today'))}<br><small>{said}</small></td><td>{radios}<br>{tick}</td></tr>"
        )
    return f"""<!doctype html><meta charset="utf-8"><title>Game voice sets</title>
<style>body{{font-family:system-ui;margin:1em}}
td{{border-bottom:1px solid #ccc;padding:.4em;vertical-align:top}}
audio{{width:15em}}</style>
<h1>Game voice sets</h1>
<p>Male sets read: {html.escape(LINES["male"])}<br>Female sets read: {html.escape(LINES["female"])}</p>
<p>voice: the set's voice alone. full: its voice and the way it speaks. keep: today's AivisSpeech voice.
Each change is saved at once; <code>make voice-sets-apply</code> writes the picks into voice.toml.</p>
<table><tr><th>Set</th><th>Game clips</th><th>Voice-only</th><th>Full copy</th><th>Today</th>
<th>Pick</th></tr>
{"".join(body)}</table>
<script>
function save(set) {{
  const pick = document.querySelector(`input[name="${{set}}"]:checked`).value;
  const decided = document.querySelector(`input[data-set="${{set}}"]`).checked;
  fetch("/pick", {{method: "POST", body: JSON.stringify({{set, pick, decided}})}});
}}
document.querySelectorAll("input").forEach(
  i => i.addEventListener("change", () => save(i.name || i.dataset.set)));
</script>
"""


def _mp3(wav: bytes, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    voice_make.to_mp3(wav, out)


def build(root: Path, cfg_path: Path, store: Path, qwen_python: Path, out: Path) -> int:
    cfg = voice_make.load_config(cfg_path)
    cat = vs.catalogue(root)
    clips = vs.clip_dir()
    today = todays_takes(root, cfg, store)
    files: dict[str, dict[str, str]] = {}
    todo: list[tuple[str, str, Path, str | None, Path]] = []
    for s, row in sorted(cat.items()):
        f = files.setdefault(s, {})
        game, _ = vs.reference(row, "voice", clips, clips / voice_make.REFS_DIR)
        gm = out / f"{s}-game.mp3"
        if not gm.is_file():
            _mp3(game.read_bytes(), gm)
        f["game"] = gm.name
        for mode in ("voice", "full"):
            if mode == "full" and not any(c["full"] for c in row["clips"]):
                continue
            ref, text = vs.reference(row, mode, clips, clips / voice_make.REFS_DIR)
            take = out / f"{s}-{mode}-{vs.ref_hash(row, mode)}.mp3"
            f[mode] = take.name
            if not take.is_file():
                todo.append((s, mode, ref, text, take))
        if s in today:
            dest = out / f"{s}-today.mp3"
            shutil.copyfile(today[s][0], dest)
            f["today"] = dest.name
    if todo:
        with Qwen(qwen_python, log=out / "qwen.log") as q:
            for n, (s, mode, ref, text, take) in enumerate(todo, 1):
                gender = cat[s]["gender"]
                _mp3(q.synthesize(LINES[gender], ref, text, mode), take)
                print(f"voice sets-page: {n}/{len(todo)} {s} {mode}", flush=True)
    picks = current_picks(cfg_path, out / "picks.json")
    (out / "index.html").write_text(
        page(rows(root), picks, files, {s: t for s, (_, t) in today.items()}), encoding="utf-8")
    print(f"voice sets-page: {len(cat)} sets, {len(todo)} takes made → {out / 'index.html'}")
    return 0


def save_pick(saved: Path, body: bytes) -> None:
    """One pick from the page into the saved picks; refuses anything but a known pick for a set name."""
    pick = json.loads(body)
    if not (isinstance(pick, dict) and voice_sets.parse(str(pick.get("set"))) and pick.get("pick") in PICKS):
        raise ValueError("bad pick")
    have = json.loads(saved.read_text(encoding="utf-8")) if saved.is_file() else {}
    have[pick["set"]] = {"pick": pick["pick"], "decided": bool(pick.get("decided"))}
    saved.write_text(json.dumps(have, indent=1, sort_keys=True) + "\n", encoding="utf-8")


def serve(folder: Path, port: int) -> int:
    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *a: Any, **k: Any) -> None:
            super().__init__(*a, directory=str(folder), **k)

        def do_POST(self) -> None:  # noqa: N802 (the stdlib's method name)
            if self.path != "/pick":
                self.send_error(404)
                return
            try:
                save_pick(folder / "picks.json", self.rfile.read(int(self.headers.get("Content-Length", 0))))
            except ValueError:
                self.send_error(400)
                return
            self.send_response(204)
            self.end_headers()

    print(f"voice sets-page: http://127.0.0.1:{port}/ (Ctrl-C stops)", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
    return 0


def apply(cfg_path: Path, saved: Path) -> int:
    """The saved picks → voice.toml's [sets] tables (each set's pick and decided lines replaced in place)."""
    picks = json.loads(saved.read_text(encoding="utf-8")) if saved.is_file() else {}
    text = cfg_path.read_text(encoding="utf-8")
    changed = 0
    for s, p in sorted(picks.items()):
        pat = re.compile(rf"(\[sets\.{re.escape(s)}\]\n)pick = \"[a-z]+\"\ndecided = (?:true|false)\n")
        new = f'pick = "{p["pick"]}"\ndecided = {"true" if p["decided"] else "false"}\n'
        text, n = pat.subn(lambda m, new=new: m.group(1) + new, text)
        if not n:
            print(f"voice sets-page: no [sets.{s}] table in {cfg_path.name}", file=sys.stderr)
        changed += n
    cfg_path.write_text(text, encoding="utf-8")
    voice_make.load_config(cfg_path)  # refuses a broken result before anything casts with it
    print(f"voice sets-page: {changed} set pick(s) → {cfg_path.name}; next: make voice-cast")
    return 0


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj voice sets-page")
    p.add_argument("cmd", choices=("build", "serve", "apply"))
    p.add_argument("--store")
    p.add_argument("--port", type=int, default=8767)
    a = p.parse_args(list(argv))
    out = page_dir()
    out.mkdir(parents=True, exist_ok=True)
    try:
        if a.cmd == "build":
            cfg = voice_make.load_config(CONFIG)
            python = voice_make._main_checkout() / cfg.get("qwen", voice_make.QWEN_PYTHON)
            return build(data_root(), CONFIG, voice_make.store_dir(a.store), python, out)
        if a.cmd == "serve":
            return serve(out, a.port)
        return apply(CONFIG, out / "picks.json")
    except (ValueError, OSError) as e:
        print(f"voice sets-page {a.cmd}: {e}", file=sys.stderr)
        return 1
