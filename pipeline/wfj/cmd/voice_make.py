"""wfj voice cast|plan|generate|status|pack: the audio files and the pack (ADR-061, ADR-062;
docs/systems/voice.md, runbook docs/operations/voice.md).

  cast [--config voice.toml]
      Casts every profile (data/voice/profiles.jsonl) through voice.toml's cast rows and
      data/voice/overrides.jsonl, and writes data/voice/voices.jsonl (creature → roster voice, and the cast
      row that chose it). Prints how many creatures each row casts.
  plan [--config voice.toml] [--scope S]
      What generate would make now, without making anything: files missing and files whose Japanese, voice
      or settings changed, by cast row and voice, with characters and hours.
  generate [--config voice.toml] [--store DIR] [--scope S]
      Makes the files plan lists through the local AivisSpeech Engine into DIR (the audio store: mono MP3,
      22.05 kHz, 32 kbps, no Xing / Info frame) and records each in data/voice/audio.jsonl, every few files,
      so a stopped run resumes where it stopped. Writes DIR/status.json as it goes.
  status [--store DIR]
      The running or last generation: done / total, rate, time left, and whether its process is alive.
  pack [--config voice.toml] [--store DIR] [--out DIR] [--scope S]
      Writes the pack addon from the recorded files that are in step with the shipped Japanese.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
import time
import tomllib
import wave
from collections import Counter
from collections.abc import Sequence
from io import BytesIO
from pathlib import Path
from typing import Any

from wfj.cmd.generate import female_index, quest_text_aliases
from wfj.core import casting, readings, voice
from wfj.emit import voice_pack
from wfj.emit.lua_writer import shipped
from wfj.io.aivis import Engine, EngineError
from wfj.io.jsonl_store import Store, dumps
from wfj.paths import data_root

LAME = ("lame", "-m", "m", "--resample", "22.05", "-b", "32", "--cbr", "-t", "--quiet")
RECORD_EVERY = 20  # files between two writes of the audio record and the status file
AUDIO = "audio.jsonl"


# ---- inputs ----------------------------------------------------------------------------------------------


def _rows(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    with path.open(encoding="utf-8") as f:
        return [json.loads(raw) for raw in f if raw.strip()]


def _write(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text("".join(dumps(r) + "\n" for r in rows), encoding="utf-8")
    tmp.replace(path)


def load_config(path: Path) -> dict[str, Any]:
    """voice.toml with every roster voice's settings filled in (speed defaults to speed_scale). Raises
    ValueError listing every problem."""
    with path.open("rb") as f:
        cfg = tomllib.load(f)
    speed = float(cfg.get("speed_scale", 0.9))
    roster = cfg.get("roster", {})
    for v in roster.values():
        v.setdefault("speed", speed)
        v.setdefault("pitch", 0.0)
        v.setdefault("intonation", 1.0)
    cfg["roster"], cfg["cast"] = roster, cfg.get("cast", [])
    problems = casting.roster_problems(
        roster, cfg["cast"], cfg.get("narrator", ""), cfg.get("book_narrator", "")
    )
    if problems:
        raise ValueError(f"{path.name}: " + "; ".join(problems))
    return cfg


def shipped_lines(root: Path) -> dict[str, str]:
    """{pack key: shipped Japanese} for every line voice may read: quest offer / progress / turn-in, gossip
    (NPC talk and the quest text keyed by its English) and plain-text book pages (an HTML page keeps the
    client's layout and is not voiced)."""
    store = Store(root)
    out = voice.shipped_quest(store.load("quest"), None)
    out.update({voice.gossip_key(ln["id"]): ln["ja"] for ln in store.load("gossip") if shipped(ln)})
    for ln in sorted((ln for ln in store.load("book") if shipped(ln)), key=lambda ln: ln["id"]):
        h = (ln.get("english") or {}).get("hash")
        if h and not readings.html_page("book", ln["ja"]):
            out.setdefault(voice.book_key(str(h)), ln["ja"])
    out.update(error_lines(root))
    return out


def line_values(root: Path, lines: dict[str, str]) -> dict[str, list[str]]:
    """{pack key: the numbers its `$N<k>` take} for the lines that have any, from their English (as the
    addon fills them from the live text)."""
    want = {k for k, ja in lines.items() if "$N" in ja}
    if not want:
        return {}
    english = Store(root, english=True)
    en: dict[str, str] = {}
    for ln in english.load("quest"):
        en[voice.quest_key(ln["id"], ln["field"])] = ln["en"]
    for ln in english.load("gossip"):
        en[voice.gossip_key(ln["id"])] = ln["en"]
    for ln in english.load("book"):
        en[voice.book_key(ln["hash"])] = ln["en"]
    return {k: voice.live_values(en[k]) for k in want if k in en}


# The playable races as the client names them (UnitRace's second value, lowercased) and the sexes: the
# character's own spoken error lines are made per race and sex.
PLAYER_RACES = ("human", "orc", "dwarf", "nightelf", "scourge", "tauren", "gnome", "troll")
PLAYER_SEXES = {"m": "male", "f": "female"}


def error_lines(root: Path) -> dict[str, str]:
    """{pack key: Japanese} for the character's spoken error lines: each on-screen error message in
    data/voice/error-messages.jsonl, spoken as the Japanese the game shows for it (`e-<UI key>`, so a changed
    translation remakes its audio), and each kind of error with a line of its own (`e-<kind>`,
    data/voice/errors.jsonl); a kind that names a message speaks that message's file."""
    ui = {ln["id"]: ln["ja"] for ln in Store(root).load("ui") if shipped(ln)}
    out = {
        f"e-{r['ui']}": ui[r["ui"]] for r in _rows(root / "voice" / "error-messages.jsonl") if r["ui"] in ui
    }
    out.update({f"e-{r['kind']}": r["ja"] for r in _rows(root / "voice" / "errors.jsonl") if "ja" in r})
    return out


def player_voice(cfg: dict[str, Any], race: str, sex: str) -> str:
    """The voice a player character of a race and sex speaks in: cast like an adult NPC of that race."""
    from wfj.core import casting

    profile = {
        "creature": 0,
        "race": race,
        "gender": PLAYER_SEXES[sex],
        "age": "adult",
        "archetype": "undead" if race == "scourge" else "none",
    }
    hit = casting.cast_one(profile, cfg["cast"])
    return hit[0] if hit else cfg["narrator"]


def players_of(arg: str | None) -> list[tuple[str, str]]:
    """`--players tauren-f,human-m` or `all` → [(race, sex)]."""
    if not arg:
        return []
    if arg == "all":
        return [(r, x) for r in PLAYER_RACES for x in PLAYER_SEXES]
    out = []
    for item in arg.split(","):
        race, _, sex = item.partition("-")
        if race not in PLAYER_RACES or sex not in PLAYER_SEXES:
            raise ValueError(f"--players {item!r}: a race of {PLAYER_RACES} and m or f")
        out.append((race, sex))
    return out


def error_jobs(root: Path, cfg: dict[str, Any], players: list[tuple[str, str]]) -> list[voice.Job]:
    keys = sorted(error_lines(root))
    return [
        voice.Job(f"{k}-{race}-{sex}", k, player_voice(cfg, race, sex)) for race, sex in players for k in keys
    ]


def read_cast(root: Path) -> dict[int, dict[str, str]]:
    return {int(r["creature"]): r for r in _rows(root / "voice" / "voices.jsonl")}


def scoped_rows(root: Path, scope: str) -> list[dict[str, Any]]:
    from wfj.cmd.voice import in_scope

    return in_scope(_rows(root / "voice" / "speakers.jsonl"), scope)


def audio_record(root: Path) -> dict[str, dict[str, Any]]:
    return {r["file"]: r for r in _rows(root / "voice" / AUDIO)}


def file_jobs(
    root: Path,
    cfg: dict[str, Any],
    scope: str,
    lines: dict[str, str],
    players: Sequence[tuple[str, str]] = (),
) -> list[voice.Job]:
    """Every file a scope needs, and the character's error lines for `players` [(race, sex)]."""
    rows = scoped_rows(root, scope)
    jobs = voice.jobs(rows, read_cast(root), cfg["narrator"], cfg["book_narrator"], lines)
    return jobs + error_jobs(root, cfg, list(players))


def store_dir(arg: str | None) -> Path:
    """The audio store: --store, else $VOICE_ROOT, else the main checkout's build/voice (never a worktree's:
    a worktree is removed with its branch, and the full run takes days)."""
    if arg:
        return Path(arg)
    if os.environ.get("VOICE_ROOT"):
        return Path(os.environ["VOICE_ROOT"])
    common = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.strip()
    base = Path(common).parent if common else data_root().parent
    return base / "build" / "voice"


# ---- cast ------------------------------------------------------------------------------------------------


def cast_rows(root: Path, cfg: dict[str, Any], today: str) -> list[dict[str, Any]]:
    """voices.jsonl rows from the profiles, the cast rows and the overrides. A row whose voice and cast row
    are unchanged keeps its old date."""
    overrides = {int(r["creature"]): r["voice"] for r in _rows(root / "voice" / "overrides.jsonl")}
    result = casting.cast(_rows(root / "voice" / "profiles.jsonl"), cfg["cast"], cfg["narrator"], overrides)
    old = read_cast(root)
    rows = []
    for c, v in sorted(result.items()):
        row: dict[str, Any] = {"creature": c, **v}
        prev = old.get(c)
        same = prev and {k: prev.get(k) for k in v} == v and set(prev) - {"creature", "provenance"} == set(v)
        row["provenance"] = prev["provenance"] if same else {"source": "cast@voice.toml", "imported": today}
        rows.append(row)
    return rows


def run_cast(cfg: dict[str, Any], root: Path) -> int:
    rows = cast_rows(root, cfg, datetime.date.today().isoformat())
    _write(root / "voice" / "voices.jsonl", rows)
    by_row = Counter(r["row"] for r in rows)
    print(f"voice cast: {len(rows)} creatures → data/voice/voices.jsonl")
    for name, n in by_row.most_common():
        print(f"voice cast: {n:5d}  {name}")
    return 0


# ---- plan ------------------------------------------------------------------------------------------------


def plan(
    root: Path, cfg: dict[str, Any], scope: str, players: Sequence[tuple[str, str]] = ()
) -> dict[str, Any]:
    """The files generate would make now, and why."""
    lines = shipped_lines(root)
    jobs = file_jobs(root, cfg, scope, lines, players)
    audio = audio_record(root)
    state = voice.in_step(jobs, lines, cfg["roster"], audio, line_values(root, lines))
    todo = set(state["missing"]) | set(state["stale"])
    rows = {c: r for c, r in read_cast(root).items()}
    speaker = {r["key"]: r["speaker"] for r in scoped_rows(root, scope)}
    by_voice: Counter[str] = Counter()
    by_row: Counter[str] = Counter()
    chars = 0
    for j in jobs:
        if j.stem not in todo:
            continue
        by_voice[j.voice] += 1
        sp = speaker.get(j.key)
        by_row[rows[sp]["row"] if isinstance(sp, int) and sp in rows else casting.NARRATOR_ROW] += 1
        chars += len(j.key and lines[j.key])
    return {
        "files": len(jobs),
        "missing": len(state["missing"]),
        "stale": len(state["stale"]),
        "by_voice": by_voice,
        "by_row": by_row,
        "chars": chars,
    }


def run_plan(cfg: dict[str, Any], root: Path, scope: str, players: Sequence[tuple[str, str]] = ()) -> int:
    p = plan(root, cfg, scope, players)
    hours = p["chars"] / 19.8 / 3600  # the measured rate of the first pack, characters a second of work
    print(
        f"voice plan ({scope}): {p['files']} files; to make {p['missing']} new + {p['stale']} changed, "
        f"{p['chars']:,} characters, about {hours:.1f} h"
    )
    for name, n in p["by_row"].most_common():
        print(f"voice plan: cast row {name}: {n}")
    for vid, n in p["by_voice"].most_common():
        print(f"voice plan: voice {vid}: {n}")
    return 0


# ---- generate --------------------------------------------------------------------------------------------


def wav_seconds(wav: bytes) -> float:
    with wave.open(BytesIO(wav)) as w:
        return w.getnframes() / w.getframerate()


def to_mp3(wav: bytes, out: Path) -> None:
    tmp = out.with_suffix(".wav")
    tmp.write_bytes(wav)
    try:
        subprocess.run([*LAME, str(tmp), str(out)], check=True)
    finally:
        tmp.unlink(missing_ok=True)


def _status(path: Path, **fields: Any) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(fields, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    tmp.replace(path)


def generate(
    root: Path,
    scope: str,
    cfg: dict[str, Any],
    store: Path,
    engine: Engine,
    encode=to_mp3,
    log=print,
    players: Sequence[tuple[str, str]] = (),
) -> dict[str, Any]:
    """Makes every missing or changed file; resumable. → the run's numbers."""
    lines = shipped_lines(root)
    jobs = file_jobs(root, cfg, scope, lines, players)
    audio = audio_record(root)
    values = line_values(root, lines)
    state = voice.in_step(jobs, lines, cfg["roster"], audio, values)
    todo = set(state["missing"]) | set(state["stale"])
    work = [j for j in jobs if j.stem in todo or not (store / f"{j.stem}.mp3").is_file()]
    version = engine.version()
    store.mkdir(parents=True, exist_ok=True)
    status = store / "status.json"
    today = datetime.date.today().isoformat()
    made = chars_made = 0
    seconds_made = 0.0
    started = time.time()

    def save(done: bool = False) -> None:
        _write(root / "voice" / AUDIO, [audio[k] for k in sorted(audio)])
        elapsed = time.time() - started
        rate = chars_made / elapsed if elapsed > 0 else 0.0
        left = sum(len(lines[j.key]) for j in work[made:])
        _status(
            status,
            scope=scope,
            pid=os.getpid(),
            started=started,
            updated=time.time(),
            done=made,
            total=len(work),
            chars_made=chars_made,
            chars_left=left,
            rate=round(rate, 2),
            seconds_left=round(left / rate) if rate else None,
            finished=done,
        )

    save()
    for n, j in enumerate(work, 1):
        settings = cfg["roster"][j.voice]
        ja = lines[j.key]
        text = voice.speech_text(ja, j.key, values.get(j.key, ()))
        wav = engine.synthesize(
            text,
            int(settings["style"]),
            float(settings["speed"]),
            float(settings["pitch"]),
            float(settings["intonation"]),
        )
        file = store / f"{j.stem}.mp3"
        encode(wav, file)
        secs = wav_seconds(wav)
        audio[j.stem] = {
            "file": j.stem,
            "key": j.key,
            "voice": j.voice,
            "ja_hash": voice.ja_hash(ja),
            "fingerprint": voice.fingerprint(voice.text_hash(ja, values.get(j.key, ())), j.voice, settings),
            "seconds": round(secs, 2),
            "bytes": file.stat().st_size,
            "chars": len(text),
            "provenance": {"source": f"aivis@{version}", "imported": today},
        }
        made += 1
        chars_made += len(text)
        seconds_made += secs
        if n % RECORD_EVERY == 0:
            save()
            log(f"voice generate: {n}/{len(work)}")
    save(done=True)
    return {
        "made": made,
        "files": len(jobs),
        "chars_made": chars_made,
        "seconds_made": seconds_made,
        "elapsed": time.time() - started,
        "audio": audio,
    }


def run_generate(
    cfg: dict[str, Any], root: Path, scope: str, store: Path, players: Sequence[tuple[str, str]] = ()
) -> int:
    try:
        r = generate(root, scope, cfg, store, Engine(cfg["engine"]), players=players)
    except (EngineError, voice.VoiceError, subprocess.CalledProcessError) as e:
        print(f"voice generate: {e}", file=sys.stderr)
        return 1
    rate = r["chars_made"] / r["elapsed"] if r["elapsed"] > 0 else 0
    print(
        f"voice generate: made {r['made']} of {r['files']} files in {r['elapsed']:.0f} s"
        f" ({rate:.1f} characters a second, {r['seconds_made']:.0f} s of audio) → {store}"
    )
    return 0


def status_lines(store: Path) -> list[str]:
    path = store / "status.json"
    if not path.is_file():
        return [f"voice status: no run recorded in {store}"]
    s = json.loads(path.read_text(encoding="utf-8"))
    alive = False
    if not s.get("finished"):
        try:
            os.kill(int(s["pid"]), 0)
            alive = True
        except (OSError, ValueError, KeyError):
            alive = False
    state = (
        "finished" if s.get("finished") else ("running" if alive else "stopped (resume with make voice-run)")
    )
    left = s.get("seconds_left")
    eta = f", about {left / 3600:.1f} h left" if left else ""
    return [
        f"voice status: {state}: {s['done']}/{s['total']} files ({s['scope']}), "
        f"{s.get('rate', 0)} characters a second{eta}"
    ]


# ---- pack ------------------------------------------------------------------------------------------------


def error_table(root: Path, cfg: dict[str, Any], players: Sequence[tuple[str, str]]) -> dict[str, Any]:
    """Register.lua's `errors`: the game's voice id → kind, and per race-sex the files in step."""
    lines = shipped_lines(root)
    audio = audio_record(root)
    jobs = error_jobs(root, cfg, list(players))
    state = voice.in_step(jobs, lines, cfg["roster"], audio)
    bad = set(state["missing"]) | set(state["stale"])
    files: dict[str, dict[str, tuple[str, float]]] = {}
    for j in jobs:
        if j.stem in bad:
            continue
        who = j.stem[len(j.key) + 1 :]
        files.setdefault(who, {})[j.key[2:]] = (f"{j.stem}.mp3", float(audio[j.stem]["seconds"]))
    for r in _rows(root / "voice" / "errors.jsonl"):  # a kind that names a message speaks that message's file
        for per in files.values():
            if r.get("ui") in per:
                per.setdefault(r["kind"], per[r["ui"]])
    kinds = {int(r["voice_id"]): r["kind"] for r in _rows(root / "voice" / "error-kinds.jsonl")}
    return {"kinds": kinds, "voices": files} if files else {}


def pack_tables(
    root: Path, cfg: dict[str, Any], scope: str
) -> tuple[dict[str, Any], dict[int, Any], list[str]]:
    """(lines, creatures, left out) for Register.lua format 2. A line: {file, hash, seconds, variants: {voice:
    (file, seconds)}}; only files whose record is in step with the shipped Japanese are packed. A key that
    shows another key's Japanese (a gendered gossip line's female wording, a repeated quest's text keyed by
    its English) points at that key's files. `creatures`: creature → its voice (or (male, female)) for the
    speakers of lines that have variants."""
    lines = shipped_lines(root)
    rows = scoped_rows(root, scope)
    cast = read_cast(root)
    audio = audio_record(root)
    jobs = voice.jobs(rows, cast, cfg["narrator"], cfg["book_narrator"], lines)
    state = voice.in_step(jobs, lines, cfg["roster"], audio, line_values(root, lines))
    bad = set(state["missing"]) | set(state["stale"])
    out: dict[str, Any] = {}
    for j in jobs:
        if j.stem in bad:
            continue
        rec = audio[j.stem]
        if j.stem == j.key:
            entry = out.setdefault(j.key, {"variants": {}})
            entry.update(file=f"{j.stem}.mp3", hash=rec["ja_hash"], seconds=float(rec["seconds"]))
        else:
            out.setdefault(j.key, {"variants": {}})["variants"][j.voice] = (
                f"{j.stem}.mp3",
                float(rec["seconds"]),
            )
    out = {k: e for k, e in out.items() if "file" in e}
    creatures: dict[int, Any] = {}
    for r in rows:
        if r["key"] in out and out[r["key"]]["variants"]:
            for c in (r["speaker"], *r.get("others", ())):
                if isinstance(c, int):
                    v = cast[c]
                    creatures[c] = (v["voice"], v["female"]) if v.get("female") else v["voice"]
    english = Store(root, english=True)
    female, _ = female_index(english.load("gossip"))
    for key, entry in list(out.items()):
        fkey = female.get(key[2:]) if key.startswith("g-") else None
        if fkey and voice.gossip_key(fkey) not in out:
            out[voice.gossip_key(fkey)] = entry
    for akey, (qid, field) in quest_text_aliases(Store(root).load("quest"), english.load("quest")).items():
        src = voice.quest_key(qid, field)
        if src in out and voice.gossip_key(akey) not in out:
            out[voice.gossip_key(akey)] = out[src]
    return out, creatures, sorted(bad)


def run_pack(
    cfg: dict[str, Any],
    root: Path,
    scope: str,
    store: Path,
    out_dir: Path,
    players: Sequence[tuple[str, str]] = (),
) -> int:
    lines, creatures, left_out = pack_tables(root, cfg, scope)
    errors = error_table(root, cfg, players)
    dest = out_dir / voice_pack.FOLDER
    if dest.exists():
        shutil.rmtree(dest)
    (dest / "Sound").mkdir(parents=True)
    files = sorted(
        {e["file"] for e in lines.values()}
        | {f for e in lines.values() for f, _ in e["variants"].values()}
        | {f for v in errors.get("voices", {}).values() for f, _ in v.values()}
    )
    used = sorted({audio_record(root)[f[:-4]]["voice"] for f in files})
    models = sorted({cfg["roster"][v]["model"] for v in used})
    licences = sorted({cfg["roster"][v]["licence"] for v in used})
    credits = {
        "engine": cfg["credits"]["engine"],
        "models": ", ".join(models),
        "licence": " / ".join(licences),
    }
    toc = root.parent / "addon" / "WoWForeverJapanese" / "WoWForeverJapanese.toc"
    (dest / f"{voice_pack.FOLDER}.toc").write_text(
        voice_pack.toc_text(_interface(toc), credits), encoding="utf-8"
    )
    (dest / "Register.lua").write_text(voice_pack.register_text(lines, creatures, errors), encoding="utf-8")
    (dest / "README.txt").write_text(voice_pack.readme_text(credits, len(lines)), encoding="utf-8")
    for f in files:
        shutil.copyfile(store / f, dest / "Sound" / f)
    size = sum((dest / "Sound" / f).stat().st_size for f in files)
    print(f"voice pack: {dest} ({len(files)} files, {len(lines)} keys, {size} bytes)")
    if left_out:
        print(
            f"voice pack: left out {len(left_out)} file(s) not in step with the shipped Japanese"
            " (make voice-plan)"
        )
    return 0


def _interface(toc: Path) -> str:
    for line in toc.read_text(encoding="utf-8").splitlines():
        if line.startswith("## Interface:"):
            return line.split(":", 1)[1].strip()
    raise ValueError(f"{toc}: no ## Interface line")


# ---- entry -----------------------------------------------------------------------------------------------


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj voice")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("cast", "plan", "generate", "status", "pack"):
        sp = sub.add_parser(name)
        sp.add_argument("--config", default="voice.toml")
        sp.add_argument("--scope", default="all", choices=sorted(voice.SCOPES))
        sp.add_argument("--store")
        sp.add_argument("--out", default="../build/voice-pack")
        sp.add_argument(
            "--players", help="the character's error lines too: race-sex (tauren-f,human-m) or all"
        )
    a = p.parse_args(list(argv))
    root = data_root()
    store = store_dir(a.store)
    if a.cmd == "status":
        print("\n".join(status_lines(store)))
        return 0
    try:
        cfg = load_config(Path(a.config))
        if a.cmd == "cast":
            return run_cast(cfg, root)
        players = players_of(a.players)
        if a.cmd == "plan":
            return run_plan(cfg, root, a.scope, players)
        if a.cmd == "generate":
            return run_generate(cfg, root, a.scope, store, players)
        return run_pack(cfg, root, a.scope, store, Path(a.out), players)
    except (ValueError, KeyError, FileNotFoundError) as e:
        print(f"voice {a.cmd}: {e}", file=sys.stderr)
        return 1
