"""wfj voice sets creatures|clips|catalogue: the game's NPC voice sets (ADR-074; docs/systems/voice.md,
runbook docs/operations/voice.md).

  sets creatures --spoken FILE --spoken-commit SHA
      Writes data/voice/creature-sets.jsonl: the set each speaking creature speaks with, per gender, exactly
      as the Spoken voice addon assigns it (its committed line corpus, fetched by `make voice-spoken-fetch`).
  sets clips --wow DIR [--product wowf] --listfile FILE [--out DIR]
      Cuts every set's greeting, farewell and vendor barks out of the local archive into build/voice-sets/
      (24 kHz mono WAV), and a set Forever adds (named after its NPCSounds row) from that row's kits. They
      are the cloning references; they stay on this machine and are never committed.
  sets catalogue --build VERSION [--whisper PATH]
      Writes data/voice/sets.jsonl: each set's gender and its clips, with an English transcript per clip (a
      local speech-to-text model for new clips; transcripts already in the file are kept) and whether the clip
      may join the full-copy reference (its words are plain English, not a fantasy language).
"""

from __future__ import annotations

import argparse
import datetime
import gzip
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import wave
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from wfj.core import voice_packs as vp
from wfj.core import voice_sets
from wfj.io import casc
from wfj.io.jsonl_store import dumps
from wfj.paths import data_root

SETS = "sets.jsonl"
CREATURE_SETS = "creature-sets.jsonl"
CLIP = re.compile(r"(greetings?|farewells?|vendors?)\d+")
GAP = 0.35  # seconds of silence between two clips of a reference
# a word list to judge whether a transcript is plain English: the system dictionary plus words it lacks
_EXTRA_WORDS = {"ya", "okay", "hey", "honored", "honoured", "horde", "alliance", "elune"}


def _rows(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    with path.open(encoding="utf-8") as f:
        return [json.loads(raw) for raw in f if raw.strip()]


def _write(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(dumps(r) + "\n" for r in rows), encoding="utf-8")


def clip_dir(arg: str | None = None) -> Path:
    """Where the cut clips live: --out, else the main checkout's build/voice-sets (beside the audio store)."""
    if arg:
        return Path(arg)
    from wfj.cmd import voice_make

    return voice_make._main_checkout() / "build" / "voice-sets"


# ---- creatures -------------------------------------------------------------------------------------------


_SPOKEN_RACE = {"scourge": "undead"}


def spoken_sets(corpus: dict[str, Any]) -> dict[int, dict[str, str]]:
    """creature → {gender: set} from Spoken's corpus: each line names its NPC and a voice
    `<race>-<gender>-<flavour>`; an NPC takes the voice most of its lines use, per gender. Voices that are no
    game set (its narrator, a voice per model) are left out."""
    counts: dict[int, dict[str, dict[str, int]]] = {}
    for line in corpus.get("lines", []):
        npc = line.get("npcId")
        parts = str(line.get("voice", "")).split("-")
        if line.get("npcType") != "creature" or not isinstance(npc, int) or len(parts) != 3:
            continue
        name = f"{_SPOKEN_RACE.get(parts[0], parts[0])}{parts[1]}{parts[2]}npc"
        parsed = voice_sets.parse(name)
        if not parsed:
            continue
        by = counts.setdefault(npc, {}).setdefault(parsed[1], {})
        by[name] = by.get(name, 0) + 1
    return {c: {g: max(n.items(), key=lambda kv: (kv[1], kv[0]))[0] for g, n in by.items()}
            for c, by in counts.items()}


def creature_rows(who: set[int], sets: dict[int, dict[str, str]], source: str, old: list[dict[str, Any]],
                  today: str) -> list[dict[str, Any]]:
    """One row per speaking creature Spoken voices with a game set: {"creature", "male"?, "female"?,
    provenance}. A row whose sets and source are unchanged keeps its old date."""
    prev = {int(r["creature"]): r for r in old}
    rows = []
    for c in sorted(who):
        got = sets.get(c)
        if not got:
            continue
        row: dict[str, Any] = {"creature": c, **{g: got[g] for g in voice_sets.GENDERS if g in got}}
        p = prev.get(c)
        same = p and {k: v for k, v in p.items() if k != "provenance"} == row and \
            p["provenance"].get("source") == source
        row["provenance"] = p["provenance"] if same else {"source": source, "imported": today}
        rows.append(row)
    return rows


def run_creatures(root: Path, corpus: Path, commit: str, today: str) -> int:
    from wfj.cmd import voice_cast

    who = voice_cast.speaking(root)
    with gzip.open(corpus, "rt", encoding="utf-8") as f:
        sets = spoken_sets(json.load(f))
    rows = creature_rows(who, sets, f"spoken@{commit[:7]}", _rows(root / "voice" / CREATURE_SETS), today)
    _write(root / "voice" / CREATURE_SETS, rows)
    print(f"voice sets: {len(rows)} of {len(who)} speakers speak with a game voice set → "
          f"data/voice/{CREATURE_SETS}")
    return 0


# ---- clips -----------------------------------------------------------------------------------------------


def clip_files(listfile: Path) -> dict[str, list[tuple[int, str]]]:
    """set → [(file id, clip name)] of its greeting, farewell and vendor barks, in name order."""
    out: dict[str, list[tuple[int, str]]] = {}
    with listfile.open(encoding="utf-8") as f:
        for line in f:
            fid, _, path = line.strip().partition(";")
            parts = path.split("/")
            if len(parts) != 4 or parts[:2] != ["sound", "creature"] or not parts[3].endswith(".ogg"):
                continue
            s, name = parts[2], parts[3][:-4]
            # most clips repeat the folder name; gnome male zany's leave out its "npc"
            kind = name.removeprefix(s).removeprefix(s.removesuffix("npc"))
            if voice_sets.parse(s) and CLIP.fullmatch(kind):
                out.setdefault(s, []).append((int(fid), name))
    for path_fid, path in _player_errors(listfile):
        out.setdefault(path, []).append(path_fid)
    return {s: sorted(v, key=lambda t: t[1])[: PLAYER_CLIPS if s.endswith("playernpc") else None]
            for s, v in sorted(out.items())}


PLAYER_CLIPS = 16  # a player set's reference: its first error lines by name, about 20 s
_ERRORS = re.compile(r"sound/character/(\w+)/(?:\w*?)(male|female)errormessages/(\w+)\.ogg")


def _player_errors(listfile: Path) -> list[tuple[tuple[int, str], str]]:
    """[((file id, clip name), set)] for the player character's own error recordings: the set
    `<race><sex>playernpc` (the Forsaken as "undead")."""
    out = []
    with listfile.open(encoding="utf-8") as f:
        for line in f:
            fid, _, path = line.strip().partition(";")
            m = _ERRORS.fullmatch(path)
            if m:
                race = "undead" if m.group(1) == "scourge" else m.group(1)
                out.append(((int(fid), m.group(3)), f"{race}{m.group(2)}playernpc"))
    return out


NPC_SOUNDS, SOUND_KIT_ENTRY = 1282621, 1237435
MANIFEST = "manifest.json"


def numbered_clips(npc_sounds: dict[int, tuple], kit_files: dict[int, list[int]], sets: list[str]
                   ) -> dict[str, list[tuple[int, str]]]:
    """set → [(file id, clip name)] for sets named after an NPCSounds row ("skybourneelfmale3776npc"), whose
    files the community listfile does not name: the row's greeting and farewell kits (its first two)."""
    out: dict[str, list[tuple[int, str]]] = {}
    for s in sets:
        p = voice_sets.parse(s)
        if not p or not p[2].isdigit() or int(p[2]) not in npc_sounds:
            continue
        kits = npc_sounds[int(p[2])][0]
        kinds = zip(kits[:2], ("greeting", "farewell"), strict=True)
        out[s] = [(fid, f"{s}{kind}{n:02d}") for kit, kind in kinds
                  for n, fid in enumerate(sorted(kit_files.get(kit, [])), 1)]
    return out


def run_clips(root: Path, wow: Path, product: str, listfile: Path, out: Path) -> int:
    from collections import defaultdict

    from wfj.io import db2

    archive = casc.LocalArchive(wow, product)
    files = clip_files(listfile)
    wanted = sorted({s for r in _rows(root / "voice" / CREATURE_SETS) for g in voice_sets.GENDERS
                     if (s := r.get(g)) and s not in files})
    if wanted:
        def table(fdid: int, name: str) -> db2.Db2Table:
            buf, gaps = archive.read_file(fdid)
            return db2.read(buf, frozenset(), gaps, name)

        ske = table(SOUND_KIT_ENTRY, "SoundKitEntry")
        kit_files: dict[int, list[int]] = defaultdict(list)
        for rid, row in ske.rows.items():
            kit_files[ske.relation.get(rid, row[0])].append(row[1])
        files.update(numbered_clips(table(NPC_SOUNDS, "NPCSounds").rows, kit_files, wanted))
    made = 0
    for s, clips in files.items():
        (out / s).mkdir(parents=True, exist_ok=True)
        for fid, name in clips:
            dest = out / s / f"{name}.wav"
            if dest.is_file():
                continue
            buf, _ = archive.read_file(fid)
            with tempfile.NamedTemporaryFile(suffix=".ogg") as ogg:
                ogg.write(bytes(buf))
                ogg.flush()
                subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", ogg.name, "-ac", "1", "-ar", "24000",
                                str(dest)], check=True)
            made += 1
    (out / MANIFEST).write_text(json.dumps({s: c for s, c in sorted(files.items())}, indent=1) + "\n",
                                encoding="utf-8")
    print(f"voice sets: {len(files)} sets, {made} clips cut → {out}")
    return 0


def manifest(clips: Path) -> dict[str, list[tuple[int, str]]]:
    """set → [(file id, clip name)] as the last `sets clips` cut them."""
    path = clips / MANIFEST
    if not path.is_file():
        raise ValueError(f"{path}: no clips cut yet (make voice-sets-clips)")
    got = json.loads(path.read_text(encoding="utf-8"))
    return {s: [(int(f), str(n)) for f, n in c] for s, c in got.items()}


# ---- catalogue -------------------------------------------------------------------------------------------


def _words() -> set[str]:
    path = Path("/usr/share/dict/words")
    words = {w.strip().lower() for w in path.read_text().splitlines()} if path.is_file() else set()
    return words | _EXTRA_WORDS


def plain_english(text: str, words: set[str]) -> bool:
    """Every word of the transcript is an English word (plurals and -ed forms included): a fantasy-language
    greeting the speech-to-text model spelled as something else must not join a full-copy reference."""
    found = re.findall(r"[a-z']+", text.lower())

    def known(w: str) -> bool:
        w = w.strip("'").split("'")[0]
        if w.endswith(("s", "ed")):
            return any(x in words for x in (w, w[:-1], w[:-2], w[:-3]) if x)
        return w in words

    return bool(found) and all(known(w) for w in found)


def catalogue_rows(files: dict[str, list[tuple[int, str]]], heard: dict[str, str], old: list[dict[str, Any]],
                   model: str, source: str, today: str, words: set[str]) -> list[dict[str, Any]]:
    """sets.jsonl rows. A clip already in the file keeps its transcript, its full flag and their provenance (a
    hand fix survives a rebuild); a new clip takes what the model heard."""
    prev = {(r["set"], c["name"]): c for r in old for c in r.get("clips", [])}
    rows = []
    for s, clips in files.items():
        parsed = voice_sets.parse(s)
        assert parsed
        out_clips = []
        for fid, name in clips:
            kept = prev.get((s, name))
            if kept:
                out_clips.append({**kept, "file": fid})
                continue
            en = heard.get(name, "").strip()
            out_clips.append({"name": name, "file": fid, "en": en, "full": plain_english(en, words),
                              "provenance": {"source": "machine", "model": model, "batch": "voice-sets",
                                             "reason": "speech-to-text of the clip", "imported": today}})
        rows.append({"set": s, "gender": parsed[1], "clips": out_clips,
                     "provenance": {"source": source, "imported": today}})
    return rows


def transcribe(whisper: str, wavs: list[Path]) -> dict[str, str]:
    """clip name → what the local speech-to-text model heard."""
    out: dict[str, str] = {}
    if not wavs:
        return out
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([whisper, *map(str, wavs), "--model", "small", "--language", "en", "--output_format",
                        "txt", "--output_dir", tmp, "--fp16", "False"], check=True, capture_output=True)
        for w in wavs:
            t = Path(tmp) / f"{w.stem}.txt"
            out[w.stem] = t.read_text(encoding="utf-8").replace("\n", " ").strip() if t.is_file() else ""
    return out


def run_catalogue(root: Path, clips: Path, whisper: str, build: str, today: str) -> int:
    files = manifest(clips)
    old = _rows(root / "voice" / SETS)
    known = {(r["set"], c["name"]) for r in old for c in r.get("clips", [])}
    new = [clips / s / f"{n}.wav" for s, cl in files.items() for _, n in cl if (s, n) not in known]
    missing = [w for w in new if not w.is_file()]
    if missing:
        print(f"voice sets: {len(missing)} clip(s) not cut yet (e.g. {missing[0]}): make voice-sets-clips",
              file=sys.stderr)
        return 1
    heard = transcribe(whisper, new)
    rows = catalogue_rows(files, heard, old, "whisper-small", f"client@{build}", today, _words())
    _write(root / "voice" / SETS, rows)
    n = sum(len(r["clips"]) for r in rows)
    full = sum(c["full"] for r in rows for c in r["clips"])
    print(f"voice sets: {len(rows)} sets, {n} clips ({full} in full-copy references), {len(new)} transcribed "
          f"→ data/voice/{SETS}")
    return 0


# ---- references for generation ---------------------------------------------------------------------------


def ref_hash(row: dict[str, Any], mode: str) -> str:
    """What a set's reference is made of, for the fingerprint: its clips (and for a full copy their words)."""
    use = [c for c in row["clips"] if mode != "full" or c["full"]]
    text = "|".join(f"{c['file']}:{c['en'] if mode == 'full' else ''}" for c in use)
    return hashlib.sha256(text.encode()).hexdigest()[:12]


def reference(row: dict[str, Any], mode: str, clips: Path, out: Path) -> tuple[Path, str | None]:
    """(the joined reference WAV, its transcript or None for a voice-only copy), written to `out` once."""
    use = [c for c in row["clips"] if mode != "full" or c["full"]]
    if not use:
        raise ValueError(f"voice set {row['set']}: no clip to copy a {mode} voice from")
    dest = out / f"{row['set']}-{mode}-{ref_hash(row, mode)}.wav"
    if not dest.is_file():
        dest.parent.mkdir(parents=True, exist_ok=True)
        params, frames = None, []
        for c in use:
            src = clips / row["set"] / f"{c['name']}.wav"
            if not src.is_file():
                raise ValueError(f"{src}: clip not cut yet (make voice-sets-clips)")
            with wave.open(str(src)) as w:
                params = params or w.getparams()
                frames.append(w.readframes(w.getnframes()))
                frames.append(b"\0" * int(w.getframerate() * GAP) * w.getsampwidth() * w.getnchannels())
        assert params
        part = dest.with_name(f"{dest.name}.{os.getpid()}.{threading.get_ident()}.part")
        with wave.open(str(part), "wb") as w:  # written aside and renamed: a reader never sees half a file
            w.setparams(params)
            w.writeframes(b"".join(frames))
        part.replace(dest)
    return dest, (" ".join(c["en"] for c in use) if mode == "full" else None)


def catalogue(root: Path) -> dict[str, dict[str, Any]]:
    return {r["set"]: r for r in _rows(root / "voice" / SETS)}


def creature_sets(root: Path) -> dict[int, dict[str, str]]:
    return {int(r["creature"]): r for r in _rows(root / "voice" / CREATURE_SETS)}


def home_packs(root: Path, table: vp.Table, levels: dict[int, int]) -> dict[int, str]:
    """creature → the folder of its home pack: the lowest band of the quests it starts or ends, else the first
    band (where an NPC's talk with no quest goes)."""
    speakers = _rows(root / "voice" / "speakers.jsonl")
    out: dict[int, str] = {}
    for c, quests in vp.creature_quests(speakers).items():
        found = sorted(lv for q in quests if (lv := levels.get(q)) is not None and lv >= 1)
        bands = [vp.band(table, lv) for lv in found]
        out[c] = next((p.folder for p in bands if p is not table.other), table.packs[0].folder)
    for r in speakers:
        for c in (r["speaker"], *r.get("others", ())):
            if isinstance(c, int):
                out.setdefault(c, table.packs[0].folder)
    return out


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj voice sets")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("creatures")
    c.add_argument("--spoken", required=True, help="Spoken's corpus.json.gz")
    c.add_argument("--spoken-commit", required=True)
    k = sub.add_parser("clips")
    k.add_argument("--wow", required=True)
    k.add_argument("--product", default="wowf")
    k.add_argument("--listfile", required=True)
    k.add_argument("--out")
    g = sub.add_parser("catalogue")
    g.add_argument("--clips")
    g.add_argument("--whisper", default="whisper")
    g.add_argument("--build", required=True, help="the client build the clips were cut from")
    a = p.parse_args(list(argv))
    root = data_root()
    today = datetime.date.today().isoformat()
    try:
        if a.cmd == "creatures":
            return run_creatures(root, Path(a.spoken), a.spoken_commit, today)
        if a.cmd == "clips":
            return run_clips(root, Path(a.wow), a.product, Path(a.listfile), clip_dir(a.out))
        return run_catalogue(root, clip_dir(a.clips), a.whisper, a.build, today)
    except (ValueError, FileNotFoundError, OSError, casc.CascError,
            subprocess.CalledProcessError) as e:
        print(f"voice sets {a.cmd}: {e}", file=sys.stderr)
        return 1
