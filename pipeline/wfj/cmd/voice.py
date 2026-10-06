"""wfj voice speakers|generate|pack: Japanese voice over, made locally (ADR-061; docs/systems/voice.md,
runbook docs/operations/voice.md).

  speakers --vmangos FILE --commit SHA [--scope shadowglen]
      Writes data/voice/speakers.jsonl (pack key → creature id or narrator) and data/voice/voices.jsonl
      (creature id → male / female / narrator) for the scope, from the VMaNGOS world database and the creature
      ids the collector recorded with gossip English (data/english/gossip `npcs`, which win). Prints the lines
      read by the narrator, the conflicts and the scoped lines with no Japanese.
  generate [--config voice.toml] [--out DIR] [--scope shadowglen]
      For every speakers row, reads the shipped Japanese through the local AivisSpeech Engine in its speaker's
      voice and writes DIR/<pack key>.mp3 (mono, 22.05 kHz, 32 kbps, no Xing / Info frame) and
      DIR/manifest.json. A file whose fingerprint (Japanese hash, voice, style, speed, engine version) is
      unchanged is not made again. Prints the numbers the packing decision needs.
  pack [--manifest DIR/manifest.json] [--out DIR]
      Writes the pack addon WoWForeverJapanese_Voice from the manifest entries whose Japanese hash still
      equals the shipped Japanese.
"""

from __future__ import annotations

import argparse
import datetime
import json
import shutil
import subprocess
import sys
import time
import tomllib
import wave
from collections.abc import Sequence
from io import BytesIO
from pathlib import Path
from typing import Any

from wfj.cmd.generate import female_index
from wfj.core import voice
from wfj.emit import voice_pack
from wfj.emit.lua_writer import shipped
from wfj.io import vmangos
from wfj.io.aivis import Engine, EngineError
from wfj.io.jsonl_store import Store, dumps
from wfj.paths import data_root

# The research doc's character counts: the quest and gossip text forever-vo voices, and everything
FULL_SCOPES = {"quest and gossip text": 3_880_000, "everything": 4_650_000}
LAME = ("lame", "-m", "m", "--resample", "22.05", "-b", "32", "--cbr", "-t", "--quiet")


def voice_dir(root: Path) -> Path:
    return root / "voice"


def read_rows(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    with path.open(encoding="utf-8") as f:
        return [json.loads(raw) for raw in f if raw.strip()]


def write_rows(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(dumps(r) + "\n" for r in rows), encoding="utf-8")


def shipped_lines(root: Path, scope: str) -> dict[str, str]:
    """{pack key: shipped Japanese} for the scope: its quests' voiced fields and every shipped gossip line
    (the speakers table narrows gossip to the scope's creatures)."""
    store = Store(root)
    out = voice.shipped_quest(store.load("quest"), voice.SCOPES[scope]["quests"])
    out.update({voice.gossip_key(ln["id"]): ln["ja"] for ln in store.load("gossip") if shipped(ln)})
    return out


def _keep_date(rows: list[dict[str, Any]], old: list[dict[str, Any]], id_field: str) -> list[dict[str, Any]]:
    """A row unchanged but for its date keeps its old date: a re-run on another day writes the same bytes."""
    before = {r[id_field]: r for r in old}
    out = []
    for r in rows:
        prev = before.get(r[id_field])
        same = prev and {**prev, "provenance": {**prev["provenance"], "imported": ""}} == {
            **r, "provenance": {**r["provenance"], "imported": ""}
        }
        out.append(prev if same else r)
    return out


def build_tables(
    root: Path, db: Path, commit: str, scope: str, today: str
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, list[str]]]:
    """(speakers rows, voices rows, report) for the scope."""
    cfg = voice.SCOPES[scope]
    quests = set(cfg["quests"])
    src = f"vmangos@{commit}"
    starters, objects, enders = vmangos.read_quest_speakers(db, quests)
    quest_keys = voice.shipped_quest(Store(root).load("quest"), quests)
    q_speakers, q_problems = voice.quest_speakers(quest_keys, starters, objects, enders)
    creatures = {c for ids in (*starters.values(), *enders.values()) for c in ids} | set(cfg["creatures"])
    gossip_shipped = {ln["id"] for ln in Store(root).load("gossip") if shipped(ln)}
    english_gossip = Store(root, english=True).load("gossip")
    collector = {ln["id"]: ln["npcs"] for ln in english_gossip if ln.get("npcs")}
    collector_src = {ln["id"]: ln["src"] for ln in english_gossip if ln.get("npcs")}
    said = vmangos.read_creature_lines(db, creatures)
    g_speakers, report = voice.gossip_speakers(said, collector, gossip_shipped)
    report["quest"] = q_problems
    report["missing"] += sorted(
        f"{voice.quest_key(q, f)}"
        for q in quests
        for f in voice.FIELDS
        if voice.quest_key(q, f) not in quest_keys and _has_english(root, q, f)
    )

    def prov(source: str) -> dict[str, str]:
        return {"source": source, "imported": today}

    speakers = [
        {"key": k, "speaker": s, "provenance": prov(src)} for k, s in sorted(q_speakers.items())
    ] + [
        {
            "key": k,
            "speaker": s,
            "provenance": prov(collector_src[k[2:]] if s in collector.get(k[2:], []) else src),
        }
        for k, s in sorted(g_speakers.items())
    ]
    speaking = {r["speaker"] for r in speakers if isinstance(r["speaker"], int)}
    genders = vmangos.read_creature_genders(db, speaking)
    voices = [
        {"creature": c, "voice": voice.voice_of(genders.get(c)), "provenance": prov(src)}
        for c in sorted(speaking)
    ]
    report["no gender"] = [str(c) for c in sorted(speaking) if c not in genders]
    return speakers, voices, report


def _has_english(root: Path, quest: int, field: str) -> bool:
    return any(
        ln["id"] == quest and ln["field"] == field for ln in Store(root, english=True).load("quest")
    )


def run_speakers(a: argparse.Namespace) -> int:
    root = data_root()
    today = datetime.date.today().isoformat()
    speakers, voices, report = build_tables(root, Path(a.vmangos), a.commit, a.scope, today)
    d = voice_dir(root)
    speakers = _keep_date(speakers, read_rows(d / "speakers.jsonl"), "key")
    voices = _keep_date(voices, read_rows(d / "voices.jsonl"), "creature")
    write_rows(d / "speakers.jsonl", speakers)
    write_rows(d / "voices.jsonl", voices)
    narrator = [r["key"] for r in speakers if r["speaker"] == voice.NARRATOR]
    by_voice: dict[str, int] = {}
    kind = {r["creature"]: r["voice"] for r in voices}
    for r in speakers:
        v = voice.NARRATOR if r["speaker"] == voice.NARRATOR else kind[r["speaker"]]
        by_voice[v] = by_voice.get(v, 0) + 1
    print(f"voice speakers: {len(speakers)} lines, {len(voices)} creatures; by voice {by_voice}")
    print(f"voice speakers: narrator lines {narrator}")
    for name in ("quest", "conflict", "missing", "no gender"):
        for item in report.get(name, []):
            print(f"voice speakers: {name}: {item}")
    return 0


def _config(path: Path) -> dict[str, Any]:
    with path.open("rb") as f:
        cfg = tomllib.load(f)
    for v in voice.VOICES:
        if not isinstance(cfg.get("voices", {}).get(v, {}).get("style"), int):
            raise ValueError(f"{path.name}: voices.{v}.style must be an engine style id")
    return cfg


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


def generate(
    root: Path, scope: str, cfg: dict[str, Any], out: Path, engine: Engine, encode=to_mp3
) -> dict[str, Any]:
    """Makes every missing or changed file. → the run's numbers."""
    speakers = read_rows(voice_dir(root) / "speakers.jsonl")
    kinds = {r["creature"]: r["voice"] for r in read_rows(voice_dir(root) / "voices.jsonl")}
    lines = shipped_lines(root, scope)
    version = engine.version()
    speed = float(cfg["speed_scale"])
    models: dict[int, str] = {}
    out.mkdir(parents=True, exist_ok=True)
    mpath = out / "manifest.json"
    manifest: dict[str, Any] = json.loads(mpath.read_text(encoding="utf-8")) if mpath.is_file() else {}
    made = skipped = chars_made = 0
    seconds_made = 0.0
    started = time.perf_counter()
    for row in speakers:
        key = row["key"]
        if key not in lines:
            print(f"voice generate: {key}: no shipped Japanese, skipped")
            continue
        who = voice.NARRATOR if row["speaker"] == voice.NARRATOR else kinds[row["speaker"]]
        style = int(cfg["voices"][who]["style"])
        ja = lines[key]
        h = voice.ja_hash(ja)
        fp = voice.fingerprint(h, who, style, speed, version)
        file = out / f"{key}.mp3"
        if manifest.get(key, {}).get("fingerprint") == fp and file.is_file():
            skipped += 1
            continue
        text = voice.speech_text(ja, key)
        if style not in models:
            models[style] = engine.model_of(style)
        wav = engine.synthesize(text, style, speed)
        encode(wav, file)
        secs = wav_seconds(wav)
        manifest[key] = {
            "fingerprint": fp, "ja_hash": h, "voice": who, "model": models[style], "style": style,
            "speed": speed, "engine": version, "bytes": file.stat().st_size, "seconds": round(secs, 2),
            "chars": len(text),
        }
        made += 1
        chars_made += len(text)
        seconds_made += secs
    elapsed = time.perf_counter() - started
    text = json.dumps(manifest, ensure_ascii=False, indent=1, sort_keys=True) + "\n"
    mpath.write_text(text, encoding="utf-8")
    return {"made": made, "skipped": skipped, "chars_made": chars_made, "seconds_made": seconds_made,
            "elapsed": elapsed, "manifest": manifest}


def numbers(result: dict[str, Any]) -> list[str]:
    m = result["manifest"]
    chars = sum(e["chars"] for e in m.values())
    secs = sum(e["seconds"] for e in m.values())
    size = sum(e["bytes"] for e in m.values())
    out = [
        f"made {result['made']}, unchanged {result['skipped']}, in {result['elapsed']:.1f} s",
        f"lines {len(m)}, characters {chars}, audio {secs:.1f} s, pack audio {size} bytes",
    ]
    if result["made"] and result["elapsed"] > 0:
        rate = result["chars_made"] / result["elapsed"]
        work = result["seconds_made"] / result["elapsed"]
        out.append(f"generation {rate:.1f} characters a second ({work:.2f} s of audio per second of work)")
        if secs and chars:
            per_char_s, per_s_bytes = secs / chars, size / secs
            speech = chars / secs
            out.append(f"speech {speech:.2f} characters a second of audio, {per_s_bytes:.0f} bytes a second")
            for name, n in FULL_SCOPES.items():
                out.append(
                    f"projection, {name} ({n:,} characters): {n / rate / 3600:.1f} h to make, "
                    f"{n * per_char_s / 3600:.0f} h of audio, {n * per_char_s * per_s_bytes / 1e6:.0f} MB"
                )
    return out


def run_generate(a: argparse.Namespace) -> int:
    root = data_root()
    cfg = _config(Path(a.config))
    try:
        result = generate(root, a.scope, cfg, Path(a.out), Engine(cfg["engine"]))
    except (EngineError, voice.VoiceError, subprocess.CalledProcessError) as e:
        print(f"voice generate: {e}", file=sys.stderr)
        return 1
    for line in numbers(result):
        print(f"voice generate: {line}")
    return 0


def interface_of(toc: Path) -> str:
    for line in toc.read_text(encoding="utf-8").splitlines():
        if line.startswith("## Interface:"):
            return line.split(":", 1)[1].strip()
    raise ValueError(f"{toc}: no ## Interface line")


def pack_lines(
    root: Path, scope: str, manifest: dict[str, Any]
) -> tuple[dict[str, tuple[str, str, float]], list[str]]:
    """{pack key: (file, hash, seconds)} for manifest entries still matching the shipped Japanese, plus the
    female-wording key of a gendered gossip line (the addon looks a female character's line up by it; same
    file). → (lines, keys left out as stale)"""
    lines = shipped_lines(root, scope)
    out: dict[str, tuple[str, str, float]] = {}
    stale = []
    for key, e in sorted(manifest.items()):
        if key not in lines or voice.ja_hash(lines[key]) != e["ja_hash"]:
            stale.append(key)
            continue
        out[key] = (f"{key}.mp3", e["ja_hash"], float(e["seconds"]))
    female, _ = female_index(Store(root, english=True).load("gossip"))
    for key, entry in list(out.items()):
        fkey = female.get(key[2:]) if key.startswith("g-") else None
        if fkey and voice.gossip_key(fkey) not in out:
            out[voice.gossip_key(fkey)] = entry
    return out, stale


def run_pack(a: argparse.Namespace) -> int:
    root = data_root()
    cfg = _config(Path(a.config))
    src = Path(a.manifest)
    manifest = json.loads(src.read_text(encoding="utf-8"))
    lines, stale = pack_lines(root, a.scope, manifest)
    dest = Path(a.out) / voice_pack.FOLDER
    if dest.exists():
        shutil.rmtree(dest)
    (dest / "Sound").mkdir(parents=True)
    models = sorted({cfg["voices"][v]["model"] for v in voice.VOICES})
    credits = {**cfg["credits"], "models": ", ".join(models)}
    toc = root.parent / "addon" / "WoWForeverJapanese" / "WoWForeverJapanese.toc"
    toc_out = voice_pack.toc_text(interface_of(toc), credits)
    (dest / f"{voice_pack.FOLDER}.toc").write_text(toc_out, encoding="utf-8")
    (dest / "Register.lua").write_text(voice_pack.register_text(lines), encoding="utf-8")
    readme = voice_pack.readme_text(credits, len(manifest) - len(stale))
    (dest / "README.txt").write_text(readme, encoding="utf-8")
    files = sorted({f for f, _, _ in lines.values()})
    for f in files:
        shutil.copyfile(src.parent / f, dest / "Sound" / f)
    size = sum((dest / "Sound" / f).stat().st_size for f in files)
    print(f"voice pack: {dest} ({len(files)} files, {len(lines)} keys, {size} bytes)")
    for key in stale:
        print(f"voice pack: left out (Japanese changed or no longer shipped): {key}")
    return 0


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj voice")
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("speakers")
    sp.add_argument("--vmangos", required=True)
    sp.add_argument("--commit", required=True)
    sp.add_argument("--scope", default="shadowglen", choices=sorted(voice.SCOPES))
    gp = sub.add_parser("generate")
    gp.add_argument("--config", default="voice.toml")
    gp.add_argument("--out", default="../build/voice")
    gp.add_argument("--scope", default="shadowglen", choices=sorted(voice.SCOPES))
    pp = sub.add_parser("pack")
    pp.add_argument("--config", default="voice.toml")
    pp.add_argument("--manifest", default="../build/voice/manifest.json")
    pp.add_argument("--out", default="../build/voice-pack")
    pp.add_argument("--scope", default="shadowglen", choices=sorted(voice.SCOPES))
    a = p.parse_args(list(argv))
    try:
        return {"speakers": run_speakers, "generate": run_generate, "pack": run_pack}[a.cmd](a)
    except (ValueError, vmangos.VmangosError) as e:
        print(f"voice {a.cmd}: {e}", file=sys.stderr)
        return 1
