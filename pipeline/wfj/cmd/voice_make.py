"""wfj voice cast|plan|generate|status: the audio files (ADR-061, ADR-062;
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
      24 kHz, 64 kbps, no Xing / Info frame) and records each in data/voice/audio.jsonl, every few files,
      so a stopped run resumes where it stopped. Writes DIR/status.json as it goes.
  status [--store DIR]
      The running or last generation: done / total, rate, time left, and whether its process is alive.
The pack tables (`pack_tables`, `error_table`) are read by `voice_ship`, which writes the voice addons.
"""

from __future__ import annotations

import argparse
import collections
import contextlib
import datetime
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import tomllib
import wave
from collections import Counter
from collections.abc import Callable, Iterator, Sequence
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from io import BytesIO
from pathlib import Path
from typing import Any

from wfj.cmd import voice_sets as voice_sets_cmd
from wfj.cmd.generate import female_index, quest_text_aliases
from wfj.core import casting, kana, names, readings, voice, voice_sets, voice_text
from wfj.core import voice_packs as vp
from wfj.emit.lua_writer import shipped
from wfj.io.aivis import Engine, EngineDown, EngineError, running
from wfj.io.jsonl_store import Store, dumps
from wfj.io.names_store import load_lines
from wfj.io.qwen import LOCK, VERSION, LineFailed, NotRead, Prepared, Qwen, QwenBusy, QwenError, line_key
from wfj.paths import data_root

ENGINE_HINT = (
    "start the AivisSpeech Engine, or unpack it into build/aivis/ (docs/operations/voice.md), and run again"
)
RATE, KBPS = 24000, 64  # the voice files' encode: the engine's own rate, at a bit rate that keeps its top end
LAME = ("lame", "-m", "m", "--resample", f"{RATE / 1000:g}", "-b", str(KBPS), "--cbr", "-t", "--quiet")
ENCODE = f"mp3 {RATE} {KBPS}"  # a record's `encode`: what its file was made with (wfj voice reencode)
RECORD_EVERY = 20  # files between two progress lines in the log
SAVE_SECONDS = 1.0  # the audio record is written at most this often while a run makes files, and at its end
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
    roster.update(set_voices(cfg.get("sets", {}), voice_sets_cmd.catalogue(data_root()), cfg.get("clone")))
    cfg["cloned_packs"] = list(cfg.get("cloned_packs", []))
    cfg["kana_words"] = frozenset((w, r) for w, r in cfg.get("text", {}).get("kana_words", []))
    cfg["set_cast"] = list(cfg.get("set_cast", []))
    # the narrator and the book reader speak with a game voice set once one is named and picked
    for key in ("narrator", "book_narrator"):
        named = cfg.get(f"{key}_set")
        if named and voice_sets.voice_id(named) in roster:
            cfg[key] = voice_sets.voice_id(named)
    problems = casting.roster_problems(
        roster, cfg["cast"], cfg.get("narrator", ""), cfg.get("book_narrator", "")
    )
    if problems:
        raise ValueError(f"{path.name}: " + "; ".join(problems))
    return cfg


def set_voices(sets: dict[str, Any], catalogue: dict[str, dict[str, Any]],
               clone: dict[str, Any] | None = None) -> dict[str, dict[str, Any]]:
    """Roster entries for the game voice sets picked as a voice-only or a full copy (voice.toml [sets]); a set
    kept on its AivisSpeech cast has none. `ref` is the hash of the set's reference, so new clips or fixed
    transcripts make its files again. `clone` (voice.toml [clone]) gives every set its temperature and, with
    `seed` on, the number its readings start from."""
    out: dict[str, dict[str, Any]] = {}
    drawn: dict[str, Any] = {}
    if clone and clone.get("temperature") is not None:
        drawn["temperature"] = float(clone["temperature"])
    for s, entry in sorted(sets.items()):
        mode = entry.get("pick")
        if mode not in ("voice", "full"):
            continue
        row = catalogue.get(s)
        out[voice_sets.voice_id(s)] = {
            "engine": "qwen", "set": s, "mode": mode, "licence": "Apache-2.0",
            "fits": f"the game's {s} voice set", "ref": voice_sets_cmd.ref_hash(row, mode) if row else "",
            **drawn, **({"seed": voice.clone_seed(s)} if clone and clone.get("seed") else {}),
        }
    return out


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
PLAYER_RACES = ("human", "orc", "dwarf", "nightelf", "scourge", "tauren", "gnome", "troll", "skyborne")
PLAYER_SEXES = {"m": "male", "f": "female"}
# Skyborne characters have no error recordings of their own: they speak with the Skyborne NPC sets
PLAYER_SETS = {("skyborne", "m"): "skybourneelfmale3776npc", ("skyborne", "f"): "skybourneelffemale3773npc"}


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
    """The voice a player character of a race and sex speaks in: the race's own error recordings cloned (a
    `<race><sex>playernpc` set picked in voice.toml; the Skyborne use their NPC sets), else cast like an adult
    NPC of that race."""
    from wfj.core import casting

    named = "undead" if race == "scourge" else race
    own = PLAYER_SETS.get((race, sex)) or f"{named}{PLAYER_SEXES[sex]}playernpc"
    if voice_sets.voice_id(own) in cfg["roster"]:
        return voice_sets.voice_id(own)

    profile = {
        "creature": 0,
        "race": race,
        "gender": PLAYER_SEXES[sex],
        "age": "adult",
        "archetype": "undead" if race == "scourge" else "none",
    }
    hit = casting.cast_one(profile, cfg["cast"])
    return hit[0] if hit else cfg["narrator"]


# `--players npc` (and `all`): the character's error lines in every NPC voice of the cast too, so a player can
# choose any of them for their character (ADR-093)
NPC = "npc"
Player = tuple[str, str] | str  # (race, sex), or NPC for the cast's NPC voices


def players_of(arg: str | None) -> list[Player]:
    """`--players tauren-f,human-m,npc` or `all` (every race and sex, then the NPC voices)
    → [(race, sex) | NPC]."""
    if not arg:
        return []
    if arg == "all":
        return [*((r, x) for r in PLAYER_RACES for x in PLAYER_SEXES), NPC]
    out: list[Player] = []
    for item in arg.split(","):
        if item == NPC:
            out.append(NPC)
            continue
        race, _, sex = item.partition("-")
        if race not in PLAYER_RACES or sex not in PLAYER_SEXES:
            raise ValueError(f"--players {item!r}: a race of {PLAYER_RACES} and m or f, or {NPC}")
        out.append((race, sex))
    return out


def npc_voices(root: Path, cfg: dict[str, Any]) -> list[str]:
    """The roster voices the cast gives creatures (a creature's voice and its female voice), less those a
    player race already speaks in: the same voice is never made twice under two names."""
    players = {player_voice(cfg, r, x) for r in PLAYER_RACES for x in PLAYER_SEXES}
    cast = {v for r in read_cast(root).values() for v in (r["voice"], r.get("female")) if v}
    return sorted(cast - players)


def error_jobs(root: Path, cfg: dict[str, Any], players: Sequence[Player]) -> list[voice.Job]:
    """The character's error lines: `e-<line>-<race>-<sex>` in each listed player voice, then, with NPC
    listed, `e-<line>-<voice>` in each NPC voice."""
    keys = sorted(error_lines(root))
    who = [(f"{p[0]}-{p[1]}", player_voice(cfg, *p)) for p in players if p != NPC]
    if NPC in players:
        who += [(v, v) for v in npc_voices(root, cfg)]
    return [voice.Job(f"{k}-{name}", k, v) for name, v in who for k in keys]


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
    players: Sequence[Player] = (),
) -> list[voice.Job]:
    """Every file a scope needs, and the character's error lines for `players` [(race, sex) | NPC]."""
    rows = scoped_rows(root, scope)
    jobs = voice.jobs(rows, read_cast(root), cfg["narrator"], cfg["book_narrator"], lines)
    return jobs + error_jobs(root, cfg, list(players))


REFS_DIR = "refs"  # joined set references, beside the cut clips; a remote run sends them to its GPUs only
QWEN_PYTHON = "build/qwen/venv/bin/python"
MAX_WORKERS = 4  # each engine holds the model in memory (about 5 GB)
FAST_WORKERS = 3
SPEED_FILE = "build/voice-speed"  # slow (default) or fast, from the main checkout: `wfj voice speed`
AUDIO_DIR = "audio"  # the store keeps its MP3s here, so its README and license open the repository page


def audio_file(store: Path, stem: str) -> Path:
    """Where the store keeps one audio file (`stem`: its name without `.mp3`)."""
    return store / AUDIO_DIR / f"{stem}.mp3"


def store_dir(arg: str | None) -> Path:
    """The audio store: --store, else $VOICE_ROOT, else the main checkout's build/voice (never a worktree's:
    a worktree is removed with its branch, and the full run takes days)."""
    if arg:
        return Path(arg)
    if os.environ.get("VOICE_ROOT"):
        return Path(os.environ["VOICE_ROOT"])
    return _main_checkout() / "build" / "voice"


def engine_run_path(arg: str | None) -> Path:
    """The engine `voice generate` starts when none answers: --engine-run, else the main checkout's
    build/aivis/macOS-arm64/run (unpacked once, beside the audio store)."""
    if arg:
        return Path(arg)
    return _main_checkout() / "build" / "aivis" / "macOS-arm64" / "run"


RUN_LOCK = "build/voice-run.lock"


@contextlib.contextmanager
def run_lock() -> Iterator[None]:
    """One voice run at a time (generate, export, relevel), whichever engine reads its lines: each run
    rewrites the whole audio record, so two at once would drop each other's rows. The lock lives in the main
    checkout, so every worktree and shell shares it."""
    path = _main_checkout() / RUN_LOCK
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as f:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as e:
            raise ValueError("another voice run (generate, export or relevel) is going; "
                             "one runs at a time") from e
        yield


def _main_checkout() -> Path:
    common = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.strip()
    return Path(common).parent if common else data_root().parent


# ---- cast ------------------------------------------------------------------------------------------------


def unknown(root: Path) -> set[int]:
    """The profiled creatures nobody can name a voice for: no known race or no known gender, no voice set from
    Spoken (which names a voice by race and gender for the NPCs it voices) and no ruling."""
    named = {int(r["creature"]) for r in _rows(root / "voice" / "overrides.jsonl")}
    named |= set(voice_sets_cmd.creature_sets(root))
    return {
        int(p["creature"])
        for p in _rows(root / "voice" / "profiles.jsonl")
        if not (p.get("race") and p.get("gender")) and int(p["creature"]) not in named
    }


def cast_rows(root: Path, cfg: dict[str, Any], today: str) -> list[dict[str, Any]]:
    """voices.jsonl rows from the profiles, the cast rows and the overrides. A row whose voice and cast row
    are unchanged keeps its old date. A creature whose race or gender nobody knows gets no row (`unknown`):
    its lines stay silent rather than be read in a voice that is a guess."""
    overrides = {int(r["creature"]): r["voice"] for r in _rows(root / "voice" / "overrides.jsonl")}
    nobody = unknown(root)
    known = [p for p in _rows(root / "voice" / "profiles.jsonl") if int(p["creature"]) not in nobody]
    result = casting.cast(known, cfg["cast"], cfg["narrator"], overrides)
    if cfg.get("cloned_packs"):
        from wfj.cmd import voice_store  # it imports this module

        table = vp.load(Path(__file__).resolve().parents[2] / "voice-packs.toml")
        levels = voice_store.read_levels(Path(__file__).resolve().parents[2] / voice_store.LEVELS)
        sets = voice_sets_cmd.creature_sets(root)
        profiles = {int(r["creature"]): r for r in _rows(root / "voice" / "profiles.jsonl")}
        for c, row in result.items():  # a creature, or a gender of one, Spoken gives no set: its kind's rule
            got = voice_sets.rule_sets(profiles.get(c, {"creature": c}), cfg["set_cast"])
            mine = dict(sets.get(c, {}))
            if not mine:
                mine = got
            elif row.get("female"):  # shown as both genders, Spoken voices one: the other from the rules
                for g in ("male", "female"):
                    if g not in mine:
                        one = {**profiles.get(c, {}), "gender": g}
                        mine.update(voice_sets.rule_sets(one, cfg["set_cast"]))
            if mine:
                sets[c] = mine
        homes = voice_sets_cmd.home_packs(root, table, levels)
        for c in result:  # a creature with no line yet still gets a home, so it is never left uncloned
            homes.setdefault(c, table.packs[0].folder)
        result = voice_sets.clone_cast(result, sets, homes, cfg["cloned_packs"], cfg["roster"], overrides)
    old = read_cast(root)
    rows = []
    for c, v in sorted(result.items()):
        row: dict[str, Any] = {"creature": c, **v}
        prev = old.get(c)
        same = prev and {k: prev.get(k) for k in v} == v and set(prev) - {"creature", "provenance"} == set(v)
        row["provenance"] = prev["provenance"] if same else {"source": "cast@voice.toml", "imported": today}
        rows.append(row)
    return rows


def cast_changes(before: dict[int, dict[str, str]], rows: list[dict[str, Any]]) -> list[str]:
    """Every speaker whose voice is not the one the last cast gave it, one line each: the lines it speaks are
    made again in the new voice, so a cast that moves a voice says so. A voice moves when Spoken's newest
    corpus names a set for a speaker cast by the project's own rows before, or names another set. A speaker's
    second voice (the one for its female form) is named when it has one, and a speaker the cast no longer
    holds is listed as removed."""

    def text(row: dict[str, str]) -> str:
        second = f" + {row['female']}" if row.get("female") else ""
        return f"{row.get('voice')}{second} ({row.get('row')})"

    out = []
    for r in sorted(rows, key=lambda r: int(r["creature"])):
        old = before.get(int(r["creature"]))
        if old is None:
            continue
        was, now = (old.get("voice"), old.get("female")), (r.get("voice"), r.get("female"))
        if was != now:
            out.append(f"{r['creature']}: {text(old)} → {text(r)}")
    cast = {int(r["creature"]) for r in rows}
    out += [f"{creature}: {text(before[creature])} → removed" for creature in sorted(set(before) - cast)]
    return out


def run_cast(cfg: dict[str, Any], root: Path) -> int:
    path = root / "voice" / "voices.jsonl"
    before = read_cast(root) if path.exists() else {}
    rows = cast_rows(root, cfg, datetime.date.today().isoformat())
    _write(path, rows)
    by_row = Counter(r["row"] for r in rows)
    print(f"voice cast: {len(rows)} creatures → data/voice/voices.jsonl")
    for name, n in by_row.most_common():
        print(f"voice cast: {n:5d}  {name}")
    changed = cast_changes(before, rows)
    if changed:
        count = f"{len(changed)} speaker(s) changed voice since the last cast"
        print(f"voice cast: {count}; their lines are made again:")
        for line in changed:
            print(f"voice cast:   {line}")
    if left := len(unknown(root)):
        print(f"voice cast: {left} creature(s) with no known race or gender get no voice")
    return 0


# ---- plan ------------------------------------------------------------------------------------------------


def reading_words(root: Path) -> dict[str, list[list[str]]]:
    """{voice key: the words of its current reading record}."""
    store, rstore = Store(root), Store(root / "reading")
    out: dict[str, list[list[str]]] = {}
    for type_ in ("quest", "gossip", "ui", "book"):
        lines = store.load(type_)
        result = readings.check(type_, rstore.load(type_), readings.shipped_japanese(lines))
        for rec in readings.addon_keyed(type_, result["current"], lines):
            if type_ == "quest":
                out[voice.quest_key(rec["id"], rec["field"])] = rec["words"]
            elif type_ == "gossip":
                out[voice.gossip_key(rec["id"])] = rec["words"]
            elif type_ == "book":
                out[voice.book_key(str(rec["id"]))] = rec["words"]
            else:
                out[f"e-{rec['id']}"] = rec["words"]
    return out


def name_lookup(root: Path) -> Callable[[str], str | None]:
    """An English name's Japanese as the voice says it, or None when the name has none."""
    by_id = {ln["id"]: ln for ln in load_lines(root) if ln["status"] == "trusted"}

    def lookup(run: str) -> str | None:
        ln = by_id.get(names.name_id(run))
        return kana.name_kana(ln) if ln else None

    return lookup


def voice_texts(
    root: Path, cfg: dict[str, Any], lines: dict[str, str], values: dict[str, list[str]]
) -> dict[str, str]:
    """{key: the text the engine reads} for every line the engine can read (`wfj.core.voice_text`). Raises
    ValueError naming the lines that say an English name with no Japanese: a word of it has no spelling yet
    (`wfj names export-respell`, draft, `wfj names import-respell`, then `make names`)."""
    words, lookup = reading_words(root), name_lookup(root)
    out: dict[str, str] = {}
    unnamed: list[str] = []
    for key, ja in lines.items():
        try:
            text, missing = voice_text.voice_text(
                ja, key, values.get(key, ()), words.get(key, ()), lookup, cfg.get("kana_words", frozenset())
            )
        except voice.VoiceError:
            continue  # a line the engine must not read is refused where it is read
        if missing:
            unnamed.append(f"{key} ({', '.join(missing)})")
        out[key] = text
    if unnamed:
        raise ValueError(
            f"{len(unnamed)} voiced line(s) say an English name with no Japanese, e.g. "
            f"{'; '.join(unnamed[:5])}: spell the new words (wfj names export-respell / import-respell), "
            "then make names"
        )
    return out


def said_hashes(lines: dict[str, str], values: dict[str, list[str]], texts: dict[str, str]) -> dict[str, str]:
    """{key: the hash of its engine text} for the lines whose engine text is not the spoken line as it
    stands. A line the fixes leave alone has no entry, so its file keeps the fingerprint it had."""
    out = {}
    for key, text in texts.items():
        if text != voice.speech_text(lines[key], key, values.get(key, ())):
            out[key] = voice.ja_hash(text)
    return out


def step_state(root: Path, cfg: dict[str, Any], jobs: Sequence[voice.Job], lines: dict[str, str],
               audio: dict[str, Any]) -> tuple[dict[str, Any], dict[str, list[str]], dict[str, str]]:
    """(which files are in step, missing or stale; the lines' numbers; the lines' engine text). The one place
    a recording is compared with what would be made now, so every command and report judges a file alike."""
    values = line_values(root, lines)
    texts = voice_texts(root, cfg, lines, values)
    state = voice.in_step(jobs, lines, cfg["roster"], audio, values, said_hashes(lines, values, texts))
    return state, values, texts


OWED_FILE = "voice-owed.txt"  # beside voice.toml: the files to remake, one stem per line


def _owed_state(root: Path, cfg: dict[str, Any]) -> tuple[list[str], list[str], list[str]]:
    """(the files to remake, the silent lines' old recordings, the recordings no line uses) over the whole
    game with every player and NPC error voice, each sorted."""
    lines = shipped_lines(root)
    jobs = file_jobs(root, cfg, "all", lines, players_of("all"))
    audio = audio_record(root)
    state, _, _ = step_state(root, cfg, jobs, lines, audio)
    spare = set(audio) - {j.stem for j in jobs}
    # a recording of a line that ships Japanese and that no file to make now stands for: nobody can name the
    # voice of the line's speaker, or of one of its speakers (a line two NPCs say has a file per voice, and
    # the one whose NPC lost its voice is spare while the other is still made)
    silent = {f for f in spare if audio[f].get("key") in lines}
    return sorted({*state["missing"], *state["stale"]}), sorted(silent), sorted(spare - silent)


def owed(root: Path, cfg: dict[str, Any]) -> tuple[list[str], list[str]]:
    """(the files to remake, the recordings of lines that are silent now). A file is to remake when it is
    missing or was made in another voice or from other Japanese. A silent line's recording is kept on the
    record, never packed and never remade until its speaker has a voice."""
    remake, silent, _ = _owed_state(root, cfg)
    return remake, silent


def not_made(root: Path, cfg: dict[str, Any]) -> list[str]:
    """The pack keys of the lines that ship Japanese and that no pack will carry, sorted: a quest's offer,
    progress or turn-in nobody names a speaker for, a line whose speaker has no voice yet, a line whose file
    is still to be remade, and every key that plays such a line's file. The entry pack lists them so the
    line's window can say it has no voice yet."""
    lines = shipped_lines(root)
    packed, _, _ = pack_tables(root, cfg, "all")
    quest = set(voice.shipped_quest(Store(root).load("quest"), None))
    spoken = {r["key"] for r in scoped_rows(root, "all")}
    silent = {k for k in (quest | spoken) if k in lines and k not in packed}
    # a key shown under another line's audio (a quest's text repeated under another id) is silent with it
    silent |= {alias for alias, src in aliases(root).items() if src in silent and alias not in packed}
    return sorted(silent)


def read_owed(path: Path) -> list[str]:
    """The stems listed in the owed file; no file lists none."""
    if not path.is_file():
        return []
    return [ln.strip() for ln in path.read_text(encoding="utf-8").splitlines() if ln.strip()]


def owed_problems(root: Path, cfg: dict[str, Any], listed: Sequence[str]) -> list[str]:
    """The gate: the files to remake are exactly the listed ones. A file out of step that is not listed was
    changed without being recorded as owed; a listed file that is in step should have left the list when it
    was remade; a recording no shipped line uses is left over."""
    remake, _, unused = _owed_state(root, cfg)
    out = []
    if extra := sorted(set(remake) - set(listed)):
        out.append(f"{len(extra)} voice file(s) are missing or out of step and not listed as owed, e.g. "
                   f"{extra[:5]}: run make voice-generate, or make voice-owed when the audio is owed")
    if done := sorted(set(listed) - set(remake)):
        out.append(f"{len(done)} file(s) listed as owed are in step, e.g. {done[:5]}: run make voice-owed")
    if unused:
        out.append(f"{len(unused)} recorded file(s) no line uses, e.g. {unused[:5]}: run make voice-generate")
    return out


def run_owed(cfg: dict[str, Any], root: Path, out: Path) -> int:
    remake, silent = owed(root, cfg)
    out.write_text("".join(f"{f}\n" for f in remake), encoding="utf-8")
    print(f"voice owed: {len(remake)} file(s) to remake, {len(silent)} line(s) silent → {out.name}")
    return 0


def plan(
    root: Path, cfg: dict[str, Any], scope: str, players: Sequence[Player] = ()
) -> dict[str, Any]:
    """The files generate would make now, and why."""
    lines = shipped_lines(root)
    jobs = file_jobs(root, cfg, scope, lines, players)
    audio = audio_record(root)
    state, values, _ = step_state(root, cfg, jobs, lines, audio)
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


def run_plan(cfg: dict[str, Any], root: Path, scope: str, players: Sequence[Player] = ()) -> int:
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


TARGET_LUFS = -20.0  # every line levelled to the same loudness (EBU R128), so no NPC is louder
TRUE_PEAK = -2.0  # dBFS a levelled line's peaks are limited to
SILENT_LUFS = -69.9  # ebur128 prints -70.0 for silence and for any take too short to gate


def level_gain(wav: bytes) -> float:
    """The one gain (dB) that brings a take to the target loudness; the limiter after it keeps its peaks under
    the ceiling.
    Measured with ffmpeg's ebur128 filter at the take's own rate, several times lighter than the 192 kHz
    analysis of loudnorm."""
    out = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", "pipe:0", "-af",
                          "ebur128=framelog=quiet", "-f", "null", "-"],
                         input=wav, capture_output=True, check=True).stderr.decode()
    found = re.search(r"Summary:.*?I:\s+(-?[\d.]+|-inf) LUFS", out, re.S)
    if not found:
        raise ValueError(f"ffmpeg ebur128 printed no integrated loudness: {out[-200:]}")
    loudness = float(found.group(1))
    if loudness <= SILENT_LUFS:
        return 0.0  # silence, or a take shorter than one 400 ms gating block: nothing to measure
    return TARGET_LUFS - loudness


def levelled(wav: bytes) -> bytes:
    """The WAV at the target loudness: one linear gain, so the voice and its timing are unchanged."""
    rate = _rate(wav)
    pcm = subprocess.run(_gain_cmd(wav), input=wav, capture_output=True, check=True).stdout
    buf = BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm)
    return buf.getvalue()


def _rate(wav: bytes) -> int:
    with wave.open(BytesIO(wav)) as w:
        return w.getframerate()


def _gain_cmd(wav: bytes) -> list[str]:
    """ffmpeg reading a WAV on stdin and writing it levelled to stdout as raw 16-bit mono samples at its own
    rate (a piped WAV header carries no length)."""
    return ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", "pipe:0", "-af",
            f"volume={level_gain(wav):.2f}dB,alimiter=limit={10 ** (TRUE_PEAK / 20):.3f}:level=disabled",
            "-ac", "1", "-f", "s16le", "-c:a", "pcm_s16le", "pipe:1"]


def to_levelled_mp3(wav: bytes, out: Path) -> None:
    """A take levelled to the common loudness, then encoded like every take: the gain is piped straight into
    LAME, so a take is measured once and written once."""
    part = out.with_name(out.name + ".part")
    raw = ["-r", "-s", f"{_rate(wav) / 1000:g}", "--bitwidth", "16", "--signed", "--little-endian"]
    try:
        gain = subprocess.Popen(_gain_cmd(wav), stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        lame = subprocess.Popen([*LAME, *raw, "-", str(part)], stdin=gain.stdout)
        assert gain.stdin is not None and gain.stdout is not None
        gain.stdout.close()  # LAME holds the read end now
        gain.stdin.write(wav)
        gain.stdin.close()
        if gain.wait() or lame.wait():
            raise subprocess.CalledProcessError(gain.returncode or lame.returncode, "level and encode")
        part.replace(out)
    finally:
        part.unlink(missing_ok=True)


def wav_seconds(wav: bytes) -> float:
    with wave.open(BytesIO(wav)) as w:
        return w.getnframes() / w.getframerate()


def to_mp3(wav: bytes, out: Path) -> None:
    # encoded beside the file and renamed, so a run stopped mid-encode leaves no cut-off mp3 at its name
    tmp = out.with_suffix(".wav")
    part = out.with_name(out.name + ".part")
    tmp.write_bytes(wav)
    try:
        subprocess.run([*LAME, str(tmp), str(part)], check=True)
        part.replace(out)
    finally:
        tmp.unlink(missing_ok=True)
        part.unlink(missing_ok=True)


def _status(path: Path, **fields: Any) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(fields, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    tmp.replace(path)


def _synth(text: str, settings: dict[str, Any], engine: Engine, version: str, q: Any,
           sets: dict[str, dict[str, Any]], clips: Path) -> tuple[bytes, str]:
    """One line's WAV from the engine its roster voice names, and the provenance source of the take."""
    if settings.get("engine") == "qwen":
        ref_wav, ref_text = voice_sets_cmd.reference(sets[settings["set"]], settings["mode"], clips,
                                                     clips / REFS_DIR)
        return (q.synthesize(text, ref_wav, ref_text, settings["mode"], settings.get("seed"),
                             settings.get("temperature")), f"qwen3-tts@{q.version}")
    wav = engine.synthesize(text, int(settings["style"]), float(settings["speed"]), float(settings["pitch"]),
                            float(settings["intonation"]))
    return wav, f"aivis@{version}"


def _cloned_lines(todo: collections.deque, qwen: Callable[[], Any], make: Callable, record: Callable,
                  speed: Callable[[], tuple[int, bool]], log: Callable[[str], None]) -> None:
    """Reads the cloned lines with as many engines as `speed` asks for now, starting or stopping engines and
    moving them in or out of the background tier between lines. The first engine holds the run's lock and is
    never stopped before the end."""
    engines: list[Any] = []
    idle: list[Any] = []
    running: dict[Any, Any] = {}
    mode: tuple[int, bool] | None = None
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        try:
            while todo or running:
                want, background = speed()
                want = max(1, min(want, MAX_WORKERS, len(todo) + len(running)))  # no engine for a last line
                while len(engines) < want:
                    q = qwen()
                    q.__enter__()
                    engines.append(q)
                    idle.append(q)
                    mode = None
                while len(engines) > want and any(q is not engines[0] for q in idle):
                    q = next(q for q in idle if q is not engines[0])
                    idle.remove(q)
                    engines.remove(q)
                    q.__exit__(None, None, None)
                if mode != (want, background):
                    for q in engines:
                        q.background(background)
                    if mode is not None:
                        pace = "in the background" if background else "at full speed"
                        log(f"voice generate: now {want} engine(s) {pace}")
                    mode = (want, background)
                while todo and idle and len(running) < want:
                    q = idle.pop()
                    running[pool.submit(make, todo.popleft(), q)] = q
                done, _ = wait(running, timeout=5, return_when=FIRST_COMPLETED)
                for f in done:
                    idle.append(running.pop(f))
                    if (got := f.result()) is not None:
                        record(*got)
        finally:
            for f in running:
                f.cancel()
            for q in engines:
                q.__exit__(None, None, None)


def _drop_unused(audio: dict[str, Any], jobs: Sequence[voice.Job], scope: str,
                 players: Sequence[Player]) -> None:
    """After a run over the whole game, rows for files no line uses any more (a recast, a removed line) leave
    the record, so it lists exactly the files the packs carry."""
    if scope == "all" and set(players) >= set(players_of("all")):
        ship = {j.stem for j in jobs}
        for stem in [k for k in audio if k not in ship]:
            del audio[stem]


def generate(  # noqa: C901, PLR0913, PLR0915 - engine, encoder and log injected for the tests; one run's state
    root: Path,
    scope: str,
    cfg: dict[str, Any],
    store: Path,
    engine: Engine,
    encode: Callable[[bytes, Path], None] | None = None,
    log=print,
    players: Sequence[Player] = (),
    checkout: bool = False,
    engine_run: Path | None = None,
    qwen: Callable[[], Any] | None = None,
    clips: Path | None = None,
    workers: int = 1,
    speed: Callable[[], tuple[int, bool]] | None = None,
) -> dict[str, Any]:
    """Makes every missing or changed file; resumable. `checkout`: the store must be a checkout of the voice
    audio repository before anything is made (the command; tests use a plain folder). `engine_run`: the
    engine to start when none answers, stopped again when the run ends. `qwen`: opens the cloned-voice
    engine (`io/qwen.Qwen`), started only when a cloned voice has files to make; `clips`: the cut set clips
    its references are joined from; `workers`: how many cloned-voice engines read lines side by side (each
    a call of `qwen`); `speed`: read before each cloned line, → (workers, background), so a run can be slowed
    down or sped up while it goes. → the run's numbers."""
    lines = shipped_lines(root)
    jobs = file_jobs(root, cfg, scope, lines, players)
    audio = audio_record(root)
    state, values, texts = step_state(root, cfg, jobs, lines, audio)
    said = said_hashes(lines, values, texts)
    todo = set(state["missing"]) | set(state["stale"])
    # what to make comes from the record; a recorded file gone from a store is made again only where the store
    # is, so a machine without the store and a round without voiced lines needs neither store nor engine
    have_store = store.is_dir()
    work = [j for j in jobs if j.stem in todo or (have_store and not audio_file(store, j.stem).is_file())]
    if not work:
        return {"made": 0, "files": len(jobs), "chars_made": 0, "seconds_made": 0.0, "elapsed": 0.0,
                "audio": audio}
    if checkout and not (store / ".git").exists():
        raise ValueError(
            f"{len(work)} file(s) to make, but {store} is not a checkout of the voice audio repository: "
            f"git clone https://github.com/zyaga/wow-forever-japanese-voice-2.git {store}"
        )
    cloned = {j.voice for j in work if cfg["roster"][j.voice].get("engine") == "qwen"}
    if cloned and qwen is None:
        raise ValueError(f"{len(cloned)} cloned voice(s) to make but no Qwen3-TTS engine was given")
    sets = voice_sets_cmd.catalogue(root) if cloned else {}
    clip_root = (clips or voice_sets_cmd.clip_dir()) if cloned else Path()
    try:
        with contextlib.ExitStack() as stack:
            version = ""
            if any(j.voice not in cloned for j in work):
                say = lambda m: log(f"voice generate: {m}")  # noqa: E731
                version = stack.enter_context(running(engine, engine_run, log=say))
            store.mkdir(parents=True, exist_ok=True)
            status = store / "status.json"
            today = datetime.date.today().isoformat()
            made = chars_made = 0
            seconds_made = 0.0
            started = time.time()
            saved_at = [0.0]

            def save(done: bool = False) -> None:
                saved_at[0] = time.time()
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

            def record(j: voice.Job, text: str, wav: bytes, source: str, file: Path) -> None:
                nonlocal made, chars_made, seconds_made
                ja = lines[j.key]
                secs = wav_seconds(wav)
                audio[j.stem] = {
                    "file": j.stem,
                    "key": j.key,
                    "voice": j.voice,
                    "ja_hash": voice.ja_hash(ja),
                    "fingerprint": voice.fingerprint(
                        voice.text_hash(ja, values.get(j.key, ())), j.voice, cfg["roster"][j.voice],
                        said.get(j.key),
                    ),
                    "seconds": round(secs, 2),
                    "bytes": file.stat().st_size,
                    "sha256": file_sha(file),
                    "encode": ENCODE,
                    "chars": len(text),
                    "provenance": {"source": source, "imported": today},
                }
                made += 1
                chars_made += len(text)
                seconds_made += secs
                # a stopped run keeps all but its last second's files; written once a second, not per file:
                # the record is the whole game's and a full run makes thousands of files
                if time.time() - saved_at[0] >= SAVE_SECONDS:
                    save()
                if made % RECORD_EVERY == 0:
                    log(f"voice generate: {made}/{len(work)}")

            def make(j: voice.Job, q: Any) -> tuple[voice.Job, str, bytes, str, Path] | None:
                text = texts.get(j.key) or voice.speech_text(lines[j.key], j.key, values.get(j.key, ()))
                try:
                    wav, source = _synth(text, cfg["roster"][j.voice], engine, version, q, sets, clip_root)
                except NotRead:
                    return None  # a remote run's line still to read: it stays to make
                except LineFailed as e:
                    log(f"voice generate: {j.stem}: {e}; left to make next run")
                    return None
                file = audio_file(store, j.stem)
                file.parent.mkdir(parents=True, exist_ok=True)
                (encode or to_levelled_mp3)(wav, file)
                return j, text, wav, source, file

            save()
            try:
                for j in [j for j in work if j.voice not in cloned]:
                    if (got := make(j, None)) is not None:
                        record(*got)
                todo = collections.deque(j for j in work if j.voice in cloned)
                if todo:
                    assert qwen is not None
                    _cloned_lines(todo, qwen, make, record, speed or (lambda: (workers, False)), log)
            finally:
                save()  # the files already made keep their records when a run stops early
            _drop_unused(audio, jobs, scope, players)
            save(done=True)
            return {
                "made": made,
                "files": len(jobs),
                "chars_made": chars_made,
                "seconds_made": seconds_made,
                "elapsed": time.time() - started,
                "audio": audio,
            }
    except (QwenBusy, QwenError) as e:
        raise ValueError(str(e)) from e
    except EngineDown as e:
        msg = f"{len(work)} file(s) to make, but the engine does not answer ({e}): {ENGINE_HINT}"
        raise EngineDown(msg) from e


class KeepWavs:
    """A local cloned-voice engine whose every WAV is also kept in the WAV archive, in a run folder of its own
    (`<archive>/local-<time>/wav/<line_key>.wav`), named as a remote run names it: every take keeps its
    uncompressed master, wherever it was read, so it can be encoded and timed again."""

    def __init__(self, engine: Any, folder: Path) -> None:
        self._engine, self._wav = engine, folder / "wav"

    def __getattr__(self, name: str) -> Any:
        return getattr(self._engine, name)

    def __enter__(self) -> KeepWavs:
        self._engine.__enter__()
        return self

    def __exit__(self, *exc: object) -> None:
        self._engine.__exit__(*exc)

    def synthesize(self, text: str, ref_wav: Path, ref_text: str | None, mode: str,
                   seed: int | None = None, temperature: float | None = None) -> bytes:
        wav = self._engine.synthesize(text, ref_wav, ref_text, mode, seed, temperature)
        self._wav.mkdir(parents=True, exist_ok=True)
        part = self._wav / f"{line_key(text, ref_wav, mode, seed, temperature)}.part"
        part.write_bytes(wav)
        part.replace(part.with_suffix(".wav"))
        return wav


def run_generate(
    cfg: dict[str, Any],
    root: Path,
    scope: str,
    store: Path,
    players: Sequence[Player] = (),
    engine_run: Path | None = None,
    prepared: Path | None = None,
    archive: Path | None = None,
) -> int:
    """`archive`: with a local engine, where its WAVs are kept (KeepWavs)."""
    kept = archive / f"local-{datetime.datetime.now():%Y-%m-%d-%H%M%S}" if archive is not None else None
    started: list[Qwen] = []
    if prepared is not None and (missing := prepared_missing(prepared)):
        print(f"voice generate: {missing} line(s) of {prepared} have no WAV yet; they stay to make",
              file=sys.stderr)

    def qwen() -> Any:  # the first engine holds the run's lock; found only when a cloned voice has files
        if prepared is not None:
            return Prepared(prepared)
        q = Qwen(_main_checkout() / cfg.get("qwen", QWEN_PYTHON), log=store / "qwen.log",
                 lock=None if started else LOCK, nice=False)
        started.append(q)
        return KeepWavs(q, kept) if kept is not None else q

    try:
        engine = Engine(cfg["engine"])
        r = generate(root, scope, cfg, store, engine, players=players, checkout=True, engine_run=engine_run,
                     qwen=qwen, speed=lambda: speed_of(read_speed()))
    except (EngineError, voice.VoiceError, subprocess.CalledProcessError, ValueError) as e:
        print(f"voice generate: {e}", file=sys.stderr)
        return 1
    rate = r["chars_made"] / r["elapsed"] if r["elapsed"] > 0 else 0
    print(
        f"voice generate: made {r['made']} of {r['files']} files in {r['elapsed']:.0f} s"
        f" ({rate:.1f} characters a second, {r['seconds_made']:.0f} s of audio) → {store}"
    )
    return 0


def export_remote(root: Path, cfg: dict[str, Any], scope: str, store: Path, out: Path,
                  players: Sequence[Player] = ()) -> int:
    """The cloned-voice files a run would make, written for a remote run (`qwen_modal.py`): jobs.jsonl (key,
    text, reference, mode), refs/ (the joined set references) and refs.json (their transcripts)."""
    lines = shipped_lines(root)
    jobs = file_jobs(root, cfg, scope, lines, players)
    audio = audio_record(root)
    state, values, spoken = step_state(root, cfg, jobs, lines, audio)
    todo = set(state["missing"]) | set(state["stale"])
    have_store = store.is_dir()
    work = [j for j in jobs if cfg["roster"][j.voice].get("engine") == "qwen"
            and (j.stem in todo or (have_store and not audio_file(store, j.stem).is_file()))]
    sets, clips = voice_sets_cmd.catalogue(root), voice_sets_cmd.clip_dir()
    (out / "refs").mkdir(parents=True, exist_ok=True)
    rows: dict[str, dict[str, Any]] = {}
    texts: dict[str, str | None] = {}
    for j in work:
        settings = cfg["roster"][j.voice]
        text = spoken.get(j.key) or voice.speech_text(lines[j.key], j.key, values.get(j.key, ()))
        ref, ref_text = voice_sets_cmd.reference(sets[settings["set"]], settings["mode"], clips,
                                                 clips / REFS_DIR)
        if not (out / "refs" / ref.name).is_file():
            shutil.copyfile(ref, out / "refs" / ref.name)
        texts[ref.name] = ref_text
        seed, temperature = settings.get("seed"), settings.get("temperature")
        key = line_key(text, ref, settings["mode"], seed, temperature)
        rows[key] = {"key": key, "text": text, "ref": ref.name, "mode": settings["mode"],
                     **({"seed": seed} if seed is not None else {}),
                     **({"temperature": temperature} if temperature is not None else {})}
    (out / "jobs.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows.values()),
                                    encoding="utf-8")
    (out / "refs.json").write_text(json.dumps(texts, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    (out / "manifest.json").write_text(json.dumps({"version": VERSION}) + "\n", encoding="utf-8")
    chars = sum(len(r["text"]) for r in rows.values())
    print(f"voice export: {len(work)} files, {len(rows)} lines to read ({chars:,} characters) → {out}")
    return len(rows)


MODAL_PYTHON = "build/modal/venv/bin/python"
REMOTE_DIR = "build/voice-remote"
LINES_PER_CARD = 60  # how many cards a run asks for; each call to a card carries BATCH_LINES of them
BATCH_LINES = 15


def remote_round(root: Path, cfg: dict[str, Any], scope: str, store: Path,
                 archive: Path | None, players: Sequence[Player] = ()) -> Path | None:
    """The cloned lines a run needs, read on Modal: exported to build/voice-remote/<time>, read with
    `qwen_modal.py` on as many cards as the lines fill (up to 10), and the WAVs copied to `archive` and
    checked. → the folder for `--prepared`, or None when no cloned line needs making."""
    main = _main_checkout()
    run = main / REMOTE_DIR / datetime.datetime.now().strftime("%Y-%m-%d-%H%M%S")
    lines = export_remote(root, cfg, scope, store, run, players)
    if not lines:
        shutil.rmtree(run, ignore_errors=True)
        return None
    python = main / cfg.get("modal", MODAL_PYTHON)
    if not python.is_file() or not (Path.home() / ".modal.toml").is_file():
        raise ValueError(f"no Modal client or login ({python}, ~/.modal.toml): make voice-modal-setup, "
                         "or VOICE_LOCAL=1 to read the lines on this machine")
    cards = max(1, min(10, -(-lines // LINES_PER_CARD)))
    env = {**os.environ, "WFJ_MODAL_CONTAINERS": str(cards), "WFJ_MODAL_BATCH": str(BATCH_LINES)}
    for _ in (1, 2):  # a line that failed on a card is read again once
        script = Path(__file__).resolve().parents[1] / "io" / "qwen_modal.py"
        subprocess.run([str(python), str(script), str(run)], env=env, check=False)
        if not prepared_missing(run):
            break
    if archive is not None:
        try:
            archive_run(run, archive)
        except OSError as e:  # the WAVs stay in the run folder; what was read is still imported
            print(f"voice archive: not archived ({e}); later: wfj voice generate --prepared {run}"
                  f" --archive {archive}", file=sys.stderr)
    return run


def archive_run(run: Path, archive: Path) -> Path:
    """Copies a remote run (its WAVs, jobs, references' transcripts and manifest) to `archive/<run name>` and
    checks every WAV against the copy; writes SHA256SUMS there. The local run is kept."""
    dest = archive / run.name
    shutil.copytree(run, dest, dirs_exist_ok=True, ignore=shutil.ignore_patterns("refs"))
    sums = []
    for w in sorted((run / "wav").glob("*.wav")):
        a, b = file_sha(w), file_sha(dest / "wav" / w.name)
        if a != b:
            raise ValueError(f"{dest / 'wav' / w.name}: the archived copy differs from {w}")
        sums.append(f"{a}  wav/{w.name}\n")
    (dest / "SHA256SUMS").write_text("".join(sums), encoding="utf-8")
    print(f"voice archive: {len(sums)} WAVs copied and checked → {dest}")
    return dest


def relevel(root: Path, cfg: dict[str, Any], store: Path, runs: Sequence[Path]) -> int:
    """Re-encodes the recorded cloned-voice files that the given remote runs made, from their kept WAVs,
    at the common loudness; the record's bytes and hashes follow. → how many files were re-encoded."""
    lines, audio = shipped_lines(root), audio_record(root)
    values = line_values(root, lines)
    spoken = voice_texts(root, cfg, lines, values)
    sets, clips = voice_sets_cmd.catalogue(root), voice_sets_cmd.clip_dir()
    done = 0
    for stem, rec in sorted(audio.items()):
        settings = cfg["roster"].get(rec["voice"], {})
        if settings.get("engine") != "qwen" or rec["key"] not in lines:
            continue
        plain = voice.speech_text(lines[rec["key"]], rec["key"], values.get(rec["key"], ()))
        ref, _ = voice_sets_cmd.reference(sets[settings["set"]], settings["mode"], clips, clips / REFS_DIR)
        # a kept WAV is named by the text it was read from: the engine text, or the spoken line of older runs
        read = dict.fromkeys((spoken.get(rec["key"], plain), plain))
        named = [line_key(t, ref, settings["mode"], settings.get("seed"), settings.get("temperature"))
                 for t in read]
        wav = next((r / sub / f"{key}.wav" for key in named for r in runs for sub in ("wav", "local")
                    if (r / sub / f"{key}.wav").is_file()), None)
        if wav is None:
            continue
        file = audio_file(store, stem)
        to_levelled_mp3(wav.read_bytes(), file)
        rec.update(bytes=file.stat().st_size, sha256=file_sha(file), encode=ENCODE)
        done += 1
        if done % 200 == 0:
            print(f"voice relevel: {done}", flush=True)
    _write(root / "voice" / AUDIO, [audio[k] for k in sorted(audio)])
    return done


def prepared_missing(run: Path) -> int:
    """How many lines of a remote run have no WAV yet."""
    jobs = [json.loads(x) for x in (run / "jobs.jsonl").read_text(encoding="utf-8").splitlines() if x]
    return sum(not (run / "wav" / f"{j['key']}.wav").is_file() for j in jobs)


SPEEDS = ("slow", "fast")


def read_speed(path: Path | None = None) -> str:
    """The speed asked for now: slow (the default, while the machine is in use) or fast."""
    p = path or _main_checkout() / SPEED_FILE
    got = p.read_text(encoding="utf-8").strip() if p.is_file() else "slow"
    return got if got in SPEEDS else "slow"


def speed_of(name: str) -> tuple[int, bool]:
    """(cloned-voice engines, background tier) for a speed: slow is one engine in the background, fast is
    several at full speed."""
    return (FAST_WORKERS, False) if name == "fast" else (1, True)


def run_speed(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj voice speed", description="Speed up or slow down a voice run, "
                                "including one already going (it reads this before each line).")
    p.add_argument("speed", choices=SPEEDS, nargs="?")
    a = p.parse_args(list(argv))
    path = _main_checkout() / SPEED_FILE
    if a.speed:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(a.speed + "\n", encoding="utf-8")
    n, background = speed_of(read_speed(path))
    tier = "background" if background else "full"
    print(f"voice speed: {read_speed(path)} ({n} engine(s), {tier} priority)")
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


def error_table(root: Path, cfg: dict[str, Any], players: Sequence[Player]) -> dict[str, Any]:
    """Register.lua's `errors`: the game's voice id → kind, and per race-sex (`tauren-f`) and per NPC voice
    (its roster id) the files in step."""
    lines = shipped_lines(root)
    audio = audio_record(root)
    jobs = error_jobs(root, cfg, list(players))
    state, _, _ = step_state(root, cfg, jobs, lines, audio)
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
    """(lines, creatures, left out) for Register.lua. A line: {file, hash, seconds, cuts, timing, variants:
    {voice: (file, seconds, cuts, timing)}}: the cuts and timing are the files' own (`wfj voice time`,
    ADR-090); only files whose record is in step with the shipped Japanese are
    packed. A key that shows another key's Japanese (a gendered gossip line's female wording, a repeated
    quest's text keyed by its English) points at that key's files. `creatures`: creature → its voice (or
    (male, female)) for the speakers of lines that have variants."""
    lines = shipped_lines(root)
    rows = scoped_rows(root, scope)
    cast = read_cast(root)
    audio = audio_record(root)
    jobs = voice.jobs(rows, cast, cfg["narrator"], cfg["book_narrator"], lines)
    state, values, _ = step_state(root, cfg, jobs, lines, audio)
    bad = set(state["missing"]) | set(state["stale"])
    out: dict[str, Any] = {}
    for j in jobs:
        if j.stem in bad:
            continue
        rec = audio[j.stem]
        timed = rec.get("timing_of") == rec["fingerprint"]
        cuts, timing = (list(rec.get("cuts") or []), rec.get("timing")) if timed else ([], None)
        entry = out.setdefault(j.key, {"variants": {}})
        if j.stem == j.key:
            entry.update(file=f"{j.stem}.mp3", hash=rec["ja_hash"], seconds=float(rec["seconds"]), cuts=cuts,
                         timing=timing)
        else:
            entry["variants"][j.voice] = (f"{j.stem}.mp3", float(rec["seconds"]), cuts, timing)
    out = {k: e for k, e in out.items() if "file" in e}
    creatures: dict[int, Any] = {}
    for r in rows:
        if r["key"] in out and out[r["key"]]["variants"]:
            for c in (r["speaker"], *r.get("others", ())):
                if isinstance(c, int) and c in cast:
                    v = cast[c]
                    creatures[c] = (v["voice"], v["female"]) if v.get("female") else v["voice"]
    for alias, src in aliases(root).items():
        if src in out and alias not in out:
            # the timing follows the source's Japanese: another wording plays the same files untimed; a key
            # with no Japanese of its own (a quest's text Forever repeats under another id) shows the source's
            same = lines.get(alias, lines.get(src)) == lines.get(src)
            n = len(lines.get(alias) or "")
            out[alias] = out[src] if same else {
                **out[src], "timing": whole_line(n, out[src]["timing"]),
                "variants": {v: (f, sec, c, whole_line(n, t))
                             for v, (f, sec, c, t) in out[src]["variants"].items()}}
    return out, creatures, sorted(bad)


def whole_line(length: int, timing: str | None) -> str | None:
    """The timing for a line shown in other words than the recording it plays: the whole line one part,
    from when the recording's first part is said (its word times belong to the other wording)."""
    if not timing or not length:
        return None
    first = next((p.split(":")[1] for p in timing.split() if not p.endswith(":-")), None)
    return f"{length}:{first}" if first is not None else None


def aliases(root: Path) -> dict[str, str]:
    """{key: the key whose file it plays}: a gendered gossip line's female wording plays the male wording's
    file, and a quest's text Forever repeats under another id (keyed by its English) plays the quest's."""
    english = Store(root, english=True)
    female, _ = female_index(english.load("gossip"))
    out = {voice.gossip_key(fkey): voice.gossip_key(mkey) for mkey, fkey in female.items()}
    for akey, (qid, field) in quest_text_aliases(Store(root).load("quest"), english.load("quest")).items():
        out.setdefault(voice.gossip_key(akey), voice.quest_key(qid, field))
    return out


# ---- entry -----------------------------------------------------------------------------------------------


def file_sha(path: Path) -> str:
    """The SHA-256 of a made file: what proves the store holds the recorded take, not another of the same
    length (the encoder's constant bitrate makes equal lengths equal sizes)."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def record_hashes(root: Path, store: Path) -> tuple[int, list[str]]:
    """Adds `sha256` to every audio record row whose file the store holds at the recorded size (a row made
    before the field existed). Reads the store only. → (rows filled, files missing or of another size)."""
    rows = _rows(root / "voice" / AUDIO)
    filled, odd = 0, []
    for r in rows:
        if r.get("sha256"):
            continue
        path = audio_file(store, r["file"])
        if not path.is_file() or path.stat().st_size != int(r["bytes"]):
            odd.append(r["file"])
            continue
        r["sha256"] = file_sha(path)
        filled += 1
    if filled:
        _write(root / "voice" / AUDIO, rows)
    return filled, odd


def _run_table_verb(a: argparse.Namespace, cfg: dict[str, Any], root: Path) -> int:
    if a.cmd == "cast":
        return run_cast(cfg, root)
    return run_owed(cfg, root, Path(a.out) if a.out else Path(a.config).resolve().parent / OWED_FILE)


def _parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="wfj voice")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("cast", "plan", "generate", "status", "record-hashes", "export", "relevel", "owed"):
        sp = sub.add_parser(name)
        sp.add_argument("--config", default="voice.toml")
        sp.add_argument("--scope", default="all", choices=sorted(voice.SCOPES))
        sp.add_argument("--store")
        sp.add_argument(
            "--players",
            help="the character's error lines too: race-sex (tauren-f,human-m), npc (every NPC voice of the "
                 "cast) or all",
        )
        if name == "generate":
            sp.add_argument("--engine-run", help="the engine to start when none answers")
            sp.add_argument("--prepared", help="a remote run's folder: its WAVs stand in for cloned voices")
            sp.add_argument("--remote", action="store_true", help="read the cloned voices on Modal first")
            sp.add_argument("--archive", help="where a run's WAVs are kept (a remote run's copied and "
                                              "checked; a local run's written there as it reads)")
        if name == "export":
            sp.add_argument("--out", required=True, help="the remote run's folder")
        if name == "relevel":
            sp.add_argument("runs", nargs="+", help="remote run folders whose WAVs the files were made from")
        if name == "owed":
            sp.add_argument("--out", help="the list to write (default: voice-owed.txt beside the config)")
    return p


def run(argv: Sequence[str]) -> int:
    a = _parser().parse_args(list(argv))
    root = data_root()
    store = store_dir(a.store)
    if a.cmd == "status":
        print("\n".join(status_lines(store)))
        return 0
    if a.cmd == "record-hashes":
        filled, odd = record_hashes(root, store)
        print(f"voice record-hashes: {filled} row(s) given their file's sha256")
        if odd:
            print(f"voice record-hashes: {len(odd)} file(s) missing or not the recorded size, left as"
                  f" they are, e.g. {', '.join(odd[:5])}", file=sys.stderr)
        return 1 if odd else 0
    try:
        cfg = load_config(Path(a.config))
        if a.cmd in ("cast", "owed"):  # the verbs that read only the config and the data
            return _run_table_verb(a, cfg, root)
        players = players_of(a.players)
        if a.cmd == "plan":
            return run_plan(cfg, root, a.scope, players)
        with run_lock():
            if a.cmd == "export":
                export_remote(root, cfg, a.scope, store, Path(a.out), players)
                return 0
            if a.cmd == "relevel":
                made = relevel(root, cfg, store, [Path(r) for r in a.runs])
                print(f"voice relevel: {made} files re-encoded")
                return 0
            prepared = Path(a.prepared) if a.prepared else None
            if prepared is not None and a.archive:
                archive_run(prepared, Path(a.archive))
            archive = Path(a.archive) if a.archive else None
            if a.remote and prepared is None:
                prepared = remote_round(root, cfg, a.scope, store, archive, players)
            return run_generate(cfg, root, a.scope, store, players, engine_run_path(a.engine_run), prepared,
                                archive if prepared is None else None)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as e:
        print(f"voice {a.cmd}: {e}", file=sys.stderr)
        return 1
