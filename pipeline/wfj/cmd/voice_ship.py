"""wfj voice pack|release: the voice addons a player installs, and their release (ADR-062; runbook
docs/operations/voice.md, "Releasing the voice"; the split is pipeline/voice-packs.toml).

  pack [--config voice.toml] [--packs voice-packs.toml] [--store DIR] [--out DIR] [--wdb CACHE]
       [--vmangos DB] [--players all]
      Writes the entry (WoWForeverJapanese_Voice/: TOC and README) and every pack folder from the recorded
      files that are in step with the shipped Japanese, prints each pack's size and the room left under the
      cap, warns past warn_mb and writes nothing when a pack is past cap_mb.
  release [same options] [--dry-run] [--curseforge-only] [--only FOLDER,…] [--entry-without-packs]
      Builds as `pack` does, zips and checks every folder, then uploads the packs whose content changed since
      the latest `voice-v*` GitHub release (and the entry when the set of packs did) to their CurseForge
      projects, and makes one GitHub release with every zip plus one zip of everything. --dry-run stops
      before anything leaves the machine and prints what would go up. --curseforge-only skips the GitHub
      release (a rehearsal: with no voice release on GitHub, the next run counts every pack as changed).
      --only uploads just the named folders' projects. --entry-without-packs makes the entry's file require
      the main addon alone: CurseForge accepts a project as a dependency only after its review, which starts
      with its first file, so a new entry's first file cannot name packs still in review. The upload
      token is CF_API_KEY in the environment.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
import zipfile
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from wfj.cmd import voice_make, voice_store
from wfj.core import voice_packs as vp
from wfj.core.voice_packs import Project, Table
from wfj.emit import voice_pack
from wfj.io import curseforge, vmangos, wdb
from wfj.paths import data_root

TAG_PREFIX = "voice-v"
PACK_FILES = ("Register.lua", "README.txt")


@dataclass
class Pack:
    """One pack as it will be written: its lines, files and content hash."""

    project: Project
    lines: dict[str, Any] = field(default_factory=dict)
    creatures: dict[int, Any] = field(default_factory=dict)
    errors: dict[str, Any] = field(default_factory=dict)
    files: list[str] = field(default_factory=list)
    size: int = 0
    register: str = ""
    digest: str = ""


# ---- the split ---------------------------------------------------------------------------------------------


def quest_levels(cache: Path | None, db: Path | None) -> dict[int, int]:
    """quest → level: the client's quest cache wins, VMaNGOS fills the quests the cache has not answered. A
    quest the cache answers with no level (0) has none, whatever VMaNGOS says."""
    levels = vmangos.read_quest_levels(db) if db else {}
    if cache:
        for q in wdb.read_quests(cache).quests:
            if q.level is None:
                continue
            if q.level >= 1:
                levels[q.id] = q.level
            else:
                levels.pop(q.id, None)
    return levels


def split(
    root: Path,
    cfg: Mapping[str, Any],
    table: Table,
    levels: Mapping[int, int],
    interface: str,
    players: Sequence[tuple[str, str]] = (),
) -> tuple[list[Pack], list[str]]:
    """(every pack in table order, the files left out as not in step). A key that shows another line's audio
    (a female wording, a repeated quest's text) goes where that line goes: its file is in that pack."""
    lines, creatures, left_out = voice_make.pack_tables(root, dict(cfg), "all")
    errors = voice_make.error_table(root, dict(cfg), players)
    speakers = {r["key"]: r for r in voice_make.scoped_rows(root, "all")}
    quests_of = vp.creature_quests(speakers.values())
    packs = {p.folder: Pack(p) for p in table.packs}
    for key, entry in lines.items():
        source = entry["file"].removesuffix(".mp3")
        packs[vp.assign(table, source, levels, speakers, quests_of).folder].lines[key] = entry
    if errors:
        packs[table.other.folder].errors = errors
    audio = voice_make.audio_record(root)
    for pack in packs.values():
        for key, entry in pack.lines.items():
            if not entry["variants"]:
                continue
            row = speakers.get(entry["file"].removesuffix(".mp3")) or speakers.get(key) or {}
            for c in (row.get("speaker"), *row.get("others", ())):
                if c in creatures:
                    pack.creatures[c] = creatures[c]
        pack.files = sorted(
            {e["file"] for e in pack.lines.values()}
            | {f for e in pack.lines.values() for f, _ in e["variants"].values()}
            | {f for v in pack.errors.get("voices", {}).values() for f, _ in v.values()}
        )
        pack.size = sum(int(audio[f.removesuffix(".mp3")]["bytes"]) for f in pack.files)
        pack.register = voice_pack.register_text(
            pack.lines, pack.creatures, pack.errors, pack.project.folder
        )
        pack.digest = vp.content_hash(
            [audio[f.removesuffix(".mp3")] for f in pack.files], pack.register, interface
        )
    return [packs[p.folder] for p in table.packs], left_out


def size_table(table: Table, packs: Sequence[Pack]) -> tuple[list[str], list[str]]:
    """(the printed table, the folders past the cap). A pack past warn_mb is marked in the table."""
    out = [f"{'pack':<40} {'lines':>6} {'files':>6} {'size':>10} {'room left':>10}"]
    over = []
    for p in packs:
        mb = p.size / vp.MB
        note = ""
        if mb > table.cap_mb:
            over.append(p.project.folder)
            note = f"  over the {table.cap_mb} MB cap"
        elif mb > table.warn_mb:
            note = f"  past {table.warn_mb} MB: plan its split"
        out.append(
            f"{p.project.folder:<40} {len(p.lines):>6} {len(p.files):>6} {mb:>7.1f} MB "
            f"{table.cap_mb - mb:>7.1f} MB{note}"
        )
    total = sum(p.size for p in packs) / vp.MB
    out.append(f"{'all packs':<40} {sum(len(p.lines) for p in packs):>6} "
               f"{sum(len(p.files) for p in packs):>6} {total:>7.1f} MB")
    return out, over


# ---- writing -----------------------------------------------------------------------------------------------


def _credits(cfg: Mapping[str, Any], audio: Mapping[str, Any], files: Sequence[str]) -> dict[str, str]:
    used = sorted({audio[f.removesuffix(".mp3")]["voice"] for f in files})
    return {
        "engine": cfg["credits"]["engine"],
        "models": ", ".join(sorted({cfg["roster"][v]["model"] for v in used})) or "none yet",
        "licence": " / ".join(sorted({cfg["roster"][v]["licence"] for v in used})) or "none yet",
    }


def _place(src: Path, dest: Path) -> None:
    """A hard link where the store and the output share a disk (the packs are 1.2 GB), else a copy."""
    try:
        os.link(src, dest)
    except OSError:
        shutil.copyfile(src, dest)


def interface_of(root: Path) -> str:
    toc = root.parent / "addon" / "WoWForeverJapanese" / "WoWForeverJapanese.toc"
    for line in toc.read_text(encoding="utf-8").splitlines():
        if line.startswith("## Interface:"):
            return line.split(":", 1)[1].strip()
    raise ValueError(f"{toc}: no ## Interface line")


def write(
    out: Path,
    table: Table,
    packs: Sequence[Pack],
    cfg: Mapping[str, Any],
    audio: Mapping[str, Any],
    store: Path,
    interface: str,
    versions: Mapping[str, str],
) -> None:
    """Every pack folder and the entry folder under `out`, replacing what a previous build left there."""
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob(f"{vp.PREFIX}*"):
        if old.is_dir():
            shutil.rmtree(old)
    for p in packs:
        pr, dest = p.project, out / p.project.folder
        (dest / "Sound").mkdir(parents=True)
        credits = _credits(cfg, audio, p.files)
        (dest / f"{pr.folder}.toc").write_text(
            voice_pack.toc_text(interface, credits, pr.title, versions[pr.folder], pr.project_id),
            encoding="utf-8",
        )
        (dest / "Register.lua").write_text(p.register, encoding="utf-8")
        (dest / "README.txt").write_text(
            voice_pack.readme_text(credits, len(p.lines), pr.title, pr.holds), encoding="utf-8"
        )
        for f in p.files:
            _place(store / f, dest / "Sound" / f)
    e, dest = table.entry, out / table.entry.folder
    dest.mkdir()
    (dest / f"{e.folder}.toc").write_text(
        voice_pack.toc_text(interface, None, e.title, versions[e.folder], e.project_id), encoding="utf-8"
    )
    (dest / "README.txt").write_text(
        voice_pack.entry_readme_text(e.title, [(p.title, p.holds) for p in table.packs]), encoding="utf-8"
    )


def check_zip(path: Path, folder: str, files: Sequence[str] | None) -> list[str]:
    """What is wrong with one zip: anything but the folder's TOC, README and (for a pack) Register.lua and its
    recorded Sound files; a recorded file missing. `files` None: the entry, which holds no audio."""
    want = {f"{folder}/{folder}.toc", f"{folder}/README.txt"}
    if files is not None:
        want |= {f"{folder}/Register.lua"} | {f"{folder}/Sound/{f}" for f in files}
    with zipfile.ZipFile(path) as z:
        have = {n for n in z.namelist() if not n.endswith("/")}
    problems = [f"{path.name}: holds {n}, which is not in the record" for n in sorted(have - want)]
    problems += [f"{path.name}: lacks {n}" for n in sorted(want - have)]
    return problems


def zip_folders(base: Path, folders: Sequence[str], dest: Path) -> None:
    """The folders under `base`, each at the top of the zip. MP3s are stored as they are (already
    compressed); text is deflated."""
    with zipfile.ZipFile(dest, "w") as z:
        for folder in folders:
            for f in sorted((base / folder).rglob("*")):
                if f.is_file():
                    kind = zipfile.ZIP_STORED if f.suffix == ".mp3" else zipfile.ZIP_DEFLATED
                    z.write(f, f.relative_to(base).as_posix(), compress_type=kind)


# ---- GitHub ------------------------------------------------------------------------------------------------

Run = Callable[[Sequence[str]], str]


def _gh(args: Sequence[str]) -> str:
    return subprocess.run(["gh", *args], capture_output=True, text=True, check=True).stdout


def releases(run: Run = _gh) -> list[dict[str, Any]]:
    """Every GitHub release, newest first."""
    rows = json.loads(run(["release", "list", "--limit", "200", "--json", "tagName,createdAt"]))
    return sorted(rows, key=lambda r: r["createdAt"], reverse=True)


def last_voice(rows: Sequence[Mapping[str, Any]], run: Run = _gh) -> tuple[str | None, dict[str, str]]:
    """(the latest voice release's tag, folder → version from its asset names)."""
    tag = next((r["tagName"] for r in rows if r["tagName"].startswith(TAG_PREFIX)), None)
    if tag is None:
        return None, {}
    assets = json.loads(run(["release", "view", tag, "--json", "assets"]))["assets"]
    return tag, vp.released(a["name"] for a in assets)


def release_type(rows: Sequence[Mapping[str, Any]]) -> str:
    """The main addon's latest release type, by the packager's rule on its tag: alpha, beta, else release."""
    tag = next((r["tagName"] for r in rows if not r["tagName"].startswith(TAG_PREFIX)), None)
    if tag is None:
        raise ValueError("the main addon has no GitHub release yet: release it first")
    t = tag.lower()
    return "alpha" if "alpha" in t else "beta" if "beta" in t else "release"


def new_tag(day: datetime.date, rows: Sequence[Mapping[str, Any]]) -> str:
    base = f"{TAG_PREFIX}{day:%Y.%m.%d}"
    taken = {r["tagName"] for r in rows}
    n, tag = 1, base
    while tag in taken:
        n += 1
        tag = f"{base}-{n}"
    return tag


# ---- the release plan --------------------------------------------------------------------------------------


@dataclass
class Plan:
    versions: dict[str, str]  # folder → version, the entry included
    upload: list[Project]  # changed, with a project: packs first, the entry last
    no_project: list[Project]  # changed, but no CurseForge project yet
    unchanged: list[str]


def plan_release(
    table: Table, packs: Sequence[Pack], interface: str, previous: Mapping[str, str], day: datetime.date
) -> Plan:
    """A changed pack gets today's date and its hash; an unchanged one keeps its released version, so its TOC
    and zip are what players already have. The entry names the packs that have a project."""
    versions, upload, no_project, unchanged = {}, [], [], []

    def decide(project: Project, digest: str) -> None:
        prev = previous.get(project.folder)
        if vp.changed(digest, prev):
            versions[project.folder] = vp.version(day, digest)
            (upload if project.project_id else no_project).append(project)
        else:
            assert prev is not None
            versions[project.folder] = prev
            unchanged.append(project.folder)

    for p in packs:
        decide(p.project, p.digest)
    decide(table.entry, vp.entry_hash(required(table), interface))
    return Plan(versions, upload, no_project, unchanged)


def entry_requires(table: Table) -> list[str]:
    """The projects the entry's file requires: the main addon (so voice never installs without it), then every
    pack that has a project."""
    return [table.addon_slug, *(p.slug for p in required(table).packs)]


def required(table: Table) -> Table:
    """The table as the entry sees it: only the packs that have a CurseForge project."""
    have = tuple(p for p in table.packs if p.project_id)
    return Table(table.entry, have or table.packs, table.cap_mb, table.warn_mb, table.addon_slug)


# ---- the verbs ---------------------------------------------------------------------------------------------


def _inputs(a: argparse.Namespace) -> tuple[Path, dict[str, Any], Table, dict[int, int], str]:
    root = data_root()
    cfg = voice_make.load_config(Path(a.config))
    table = vp.load(Path(a.packs))
    if a.wdb or a.vmangos:
        levels = quest_levels(Path(a.wdb) if a.wdb else None, Path(a.vmangos) if a.vmangos else None)
    else:  # the committed table: the client files are not in the repository
        levels = voice_store.read_levels(Path(a.levels))
    return root, cfg, table, levels, interface_of(root)


def build(a: argparse.Namespace, day: datetime.date, previous: Mapping[str, str] | None) -> tuple[
    Table, list[Pack], Plan | None, dict[str, str]
] | None:
    """Splits, prints the size table and writes the folders. None when a pack is over the cap (nothing is
    written). With `previous` (a release), versions follow the release plan; without, every pack is dated
    today."""
    root, cfg, table, levels, interface = _inputs(a)
    players = voice_make.players_of(a.players)
    packs, left_out = split(root, cfg, table, levels, interface, players)
    rows, over = size_table(table, packs)
    print("\n".join(f"voice pack: {r}" for r in rows))
    if left_out:
        print(f"voice pack: left out {len(left_out)} file(s) not in step with the shipped Japanese"
              " (make voice-plan)")
    if over:
        print(
            f"voice pack: {', '.join(over)} over the {table.cap_mb} MB cap; nothing written. Add a row to "
            "voice-packs.toml, its CurseForge project and a new entry file (docs/operations/voice.md)",
            file=sys.stderr,
        )
        return None
    plan = None
    if previous is not None:
        plan = plan_release(table, packs, interface, previous, day)
        versions = plan.versions
    else:
        versions = {p.project.folder: vp.version(day, p.digest) for p in packs}
        versions[table.entry.folder] = vp.version(day, vp.entry_hash(required(table), interface))
    write(Path(a.out), table, packs, cfg, voice_make.audio_record(root), voice_make.store_dir(a.store),
          interface, versions)
    print(f"voice pack: wrote {len(packs)} packs and the entry under {a.out}")
    return table, packs, plan, versions


def run_pack(a: argparse.Namespace) -> int:
    return 0 if build(a, datetime.date.today(), None) else 1


def zip_release(
    out: Path,
    dist: Path,
    table: Table,
    packs: Sequence[Pack],
    versions: Mapping[str, str],
    day: datetime.date,
) -> tuple[dict[str, Path], Path] | None:
    """Every folder's zip, checked, and the zip of everything. None (problems printed) when a zip fails."""
    if dist.exists():
        shutil.rmtree(dist)
    dist.mkdir(parents=True)
    zips: dict[str, Path] = {}
    problems: list[str] = []
    for p in packs:
        z = dist / vp.asset_name(p.project.folder, versions[p.project.folder])
        zip_folders(out, [p.project.folder], z)
        problems += check_zip(z, p.project.folder, p.files)
        zips[p.project.folder] = z
    e = table.entry
    zips[e.folder] = dist / vp.asset_name(e.folder, versions[e.folder])
    zip_folders(out, [e.folder], zips[e.folder])
    problems += check_zip(zips[e.folder], e.folder, None)
    if problems:
        print("\n".join(f"voice release: {x}" for x in problems), file=sys.stderr)
        return None
    bundle = dist / f"{e.folder}-all-{day:%Y.%m.%d}.zip"
    zip_folders(out, [e.folder, *(p.project.folder for p in packs)], bundle)
    return zips, bundle


def _only(plan: Plan, table: Table, only: str | None) -> None:
    """--only: keep just the named folders' uploads."""
    if not only:
        return
    keep = set(only.split(","))
    unknown = keep - {p.folder for p in (table.entry, *table.packs)}
    if unknown:
        raise ValueError(f"--only names no such folder: {', '.join(sorted(unknown))}")
    plan.upload = [p for p in plan.upload if p.folder in keep]
    print(f"voice release: only {', '.join(sorted(keep))}")


def check_pin(store: Path, pin: Path) -> None:
    """A release ships exactly the audio commit the text pins: the store sits at it, nothing uncommitted."""
    want = voice_store.read_pin(pin)
    git = ["git", "-C", str(store)]
    head = subprocess.run([*git, "rev-parse", "HEAD"], capture_output=True, text=True, check=False)
    head = head.stdout.strip()
    if head != want:
        raise ValueError(f"the audio store is at {head[:12] or 'no commit'}, the text pins {want[:12]}: "
                         "run `make voice-sync`, or check out the pinned commit in the store")
    if subprocess.run([*git, "status", "--porcelain"], capture_output=True, text=True, check=True).stdout:
        raise ValueError("the audio store has uncommitted files: run `make voice-sync` first")


def run_release(a: argparse.Namespace, run: Run = _gh) -> int:
    day = datetime.date.today()
    if a.pin:
        check_pin(voice_make.store_dir(a.store), Path(a.pin))
    rows = releases(run)
    tag_before, previous = last_voice(rows, run)
    rtype = release_type(rows)
    built = build(a, day, previous)
    if not built:
        return 1
    table, packs, plan, versions = built
    assert plan is not None
    out, dist = Path(a.out), Path(a.out).parent / "voice-release"
    zipped = zip_release(out, dist, table, packs, versions, day)
    if zipped is None:
        return 1
    zips, bundle = zipped
    _only(plan, table, a.only)
    tag = new_tag(day, rows)
    print(f"voice release: last voice release {tag_before or 'none'}; this one {tag} ({rtype})")
    for pr in plan.upload:
        print(f"voice release: upload {zips[pr.folder].name} to CurseForge project {pr.project_id}"
              f" ({pr.slug})")
    for pr in plan.no_project:
        print(f"voice release: {pr.folder} changed but has no CurseForge project yet (project_id 0):"
              " not uploaded")
    for f in plan.unchanged:
        print(f"voice release: {f} unchanged ({versions[f]})")
    if not plan.upload and not plan.no_project:
        print("voice release: nothing changed since the last voice release; nothing to do")
        return 0
    if a.curseforge_only:
        print("voice release: CurseForge only; no GitHub release")
    else:
        print(f"voice release: GitHub release {tag}: {len(zips)} zips and {bundle.name}")
    if a.dry_run:
        print("voice release: dry run; nothing uploaded")
        return 0
    token = os.environ.get("CF_API_KEY", "")
    if not token:
        print("voice release: no upload token (CF_API_KEY); see docs/operations/voice.md", file=sys.stderr)
        return 1
    gv = curseforge.game_version_id(curseforge.game_versions(token), interface_of(data_root()))
    slugs = [table.addon_slug] if a.entry_without_packs else entry_requires(table)
    if a.entry_without_packs:
        print("voice release: the entry requires the main addon only (no packs)")
    for pr in plan.upload:
        meta = curseforge.metadata(
            versions[pr.folder], gv, rtype,
            (out / pr.folder / "README.txt").read_text(encoding="utf-8"),
            slugs if pr.folder == table.entry.folder else (),
        )
        fid = curseforge.upload(pr.project_id, zips[pr.folder], meta, token)
        print(f"voice release: uploaded {zips[pr.folder].name} (CurseForge file {fid})")
    if a.curseforge_only:
        print("voice release: done (CurseForge only)")
        return 0
    notes = dist / "notes.md"
    notes.write_text(_notes(table, versions, plan), encoding="utf-8")
    run([
        "release", "create", tag, *map(str, zips.values()), str(bundle),
        "--title", f"Voice {day:%Y.%m.%d}", "--notes-file", str(notes), "--latest=false",
        *(["--prerelease"] if rtype != "release" else []),
    ])
    print(f"voice release: done: {tag}")
    return 0


def _notes(table: Table, versions: Mapping[str, str], plan: Plan) -> str:
    changed = {p.folder for p in (*plan.upload, *plan.no_project)}
    rows = [
        f"- {p.title}: {versions[p.folder]}{' (new)' if p.folder in changed else ''}" for p in table.packs
    ]
    return "\n".join([
        "Japanese voice for WoW Forever Japanese. Install the addon first.",
        "",
        "By hand: download the zip whose name ends in -all-, and unzip it into Interface/AddOns.",
        "",
        *rows,
        "",
    ])


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj voice")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("pack", "release"):
        sp = sub.add_parser(name)
        sp.add_argument("--config", default="voice.toml")
        sp.add_argument("--packs", default="voice-packs.toml")
        sp.add_argument("--store")
        sp.add_argument("--out", default="../build/voice-pack")
        sp.add_argument("--levels", default=voice_store.LEVELS, help="the committed quest level table")
        sp.add_argument("--pin", default=voice_store.PIN, help="the audio commit the text pins (release)")
        sp.add_argument("--wdb", help="the pinned Forever quest cache: each quest's level")
        sp.add_argument("--vmangos", help="the VMaNGOS database: levels of quests the cache has not answered")
        sp.add_argument("--players", default="all", help="the character's error lines: race-sex list or all")
        if name == "release":
            sp.add_argument("--dry-run", action="store_true")
            sp.add_argument("--curseforge-only", action="store_true", help="no GitHub release (a rehearsal)")
            sp.add_argument("--only", help="upload only these folders, comma-separated")
            sp.add_argument("--entry-without-packs", action="store_true",
                            help="the entry's file requires the main addon alone (packs not approved yet)")
    a = p.parse_args(list(argv))
    try:
        return run_pack(a) if a.cmd == "pack" else run_release(a)
    except (ValueError, KeyError, FileNotFoundError, wdb.WdbError, vmangos.VmangosError,
            curseforge.CurseForgeError, subprocess.CalledProcessError) as e:
        print(f"voice {a.cmd}: {e}", file=sys.stderr)
        return 1

