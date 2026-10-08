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
import hashlib
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
        unrecorded = [f for f in pack.files if f.removesuffix(".mp3") not in audio]
        if unrecorded:
            raise ValueError(f"{pack.project.folder}: {len(unrecorded)} file(s) not in the audio record, "
                             f"e.g. {unrecorded[:3]}: run `wfj voice plan`, then make voice-generate")
        pack.size = sum(int(audio[f.removesuffix(".mp3")]["bytes"]) for f in pack.files)
        pack.register = voice_pack.register_text(
            pack.lines, pack.creatures, pack.errors, pack.project.folder
        )
        pack.digest = vp.content_hash(
            [audio[f.removesuffix(".mp3")] for f in pack.files],
            pack.register,
            interface,
            pack.project.project_id,
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
    """Every GitHub release, drafts included, newest first."""
    rows = json.loads(run(["release", "list", "--limit", "5000", "--json", "tagName,createdAt,isDraft"]))
    return sorted(rows, key=lambda r: r["createdAt"], reverse=True)


def _assets(tag: str, run: Run) -> list[str]:
    return [a["name"] for a in json.loads(run(["release", "view", tag, "--json", "assets"]))["assets"]]


def last_voice(rows: Sequence[Mapping[str, Any]], run: Run = _gh) -> tuple[str | None, dict[str, str]]:
    """(the latest published voice release's tag, folder → version from its asset names)."""
    voice = [r for r in rows if r["tagName"].startswith(TAG_PREFIX)]
    tag = next((r["tagName"] for r in voice if not r.get("isDraft")), None)
    if tag is None:
        return None, {}
    return tag, vp.released(_assets(tag, run))


@dataclass
class VoiceState:
    """What GitHub records of the voice releases: the last published one and a draft a failed run left."""

    published: str | None
    draft: str | None
    previous: dict[str, str]  # folder → version: the published release, overlaid with what the draft recorded
    draft_assets: list[str]
    published_assets: list[str]


def voice_state(rows: Sequence[Mapping[str, Any]], run: Run = _gh) -> VoiceState:
    """A voice release starts as a draft and records each pack the moment CurseForge has it, so a run that
    fails partway is resumed from its draft and uploads nothing twice."""
    voice = [r for r in rows if r["tagName"].startswith(TAG_PREFIX)]
    published = next((r["tagName"] for r in voice if not r.get("isDraft")), None)
    draft = next((r["tagName"] for r in voice if r.get("isDraft")), None)
    published_assets = _assets(published, run) if published else []
    draft_assets = _assets(draft, run) if draft else []
    previous = {**vp.released(published_assets), **vp.released(draft_assets)}
    return VoiceState(published, draft, previous, draft_assets, published_assets)


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
              " (wfj voice plan)")
    if over:
        print(
            f"voice pack: {', '.join(over)} over the {table.cap_mb} MB cap; nothing written. Add a row to "
            "voice-packs.toml, its CurseForge project and a new entry file (docs/operations/voice.md)",
            file=sys.stderr,
        )
        return None
    store = voice_make.store_dir(a.store)
    wrong = store_mismatches(store, voice_make.audio_record(root), [f for p in packs for f in p.files])
    if wrong:
        print(
            f"voice pack: {len(wrong)} file(s) in {store} are not the recorded audio (another branch remade them,"
            f" or the store is not at this text's pin), e.g. {', '.join(wrong[:5])}; nothing written",
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
    write(Path(a.out), table, packs, cfg, voice_make.audio_record(root), store, interface, versions)
    print(f"voice pack: wrote {len(packs)} packs and the entry under {a.out}")
    return table, packs, plan, versions


def store_mismatches(store: Path, audio: Mapping[str, Any], files: Sequence[str]) -> list[str]:
    """The pack files whose store copy is missing or not the size the audio record holds for it: a file the
    shared store holds from another branch's round would otherwise ship under this text's Japanese hash."""
    wrong = []
    for f in sorted(set(files)):
        path = store / f
        if not path.is_file() or path.stat().st_size != int(audio[f.removesuffix(".mp3")]["bytes"]):
            wrong.append(f)
    return wrong


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


@dataclass
class Uploads:
    """What one release uploads to CurseForge, and with what."""

    table: Table
    plan: Plan
    zips: dict[str, Path]
    versions: dict[str, str]
    out: Path
    dist: Path
    day: datetime.date
    game_version: int
    rtype: str
    slugs: list[str]
    token: str
    record: Callable[[Path], None]  # after a CurseForge upload: keep the zip on the voice release's draft


def upload_all(u: Uploads) -> bool:
    """Every changed pack, then the entry. An entry that went up without some packs (still in review) gets an
    asset name of its own, so the next release counts it as changed and tries the full list again.
    → whether the entry went up without some packs."""
    entry, partial = u.table.entry.folder, False
    for pr in u.plan.upload:
        readme = (u.out / pr.folder / "README.txt").read_text(encoding="utf-8")

        def meta_for(required: list[str], pr: Project = pr, readme: str = readme) -> dict[str, Any]:
            return curseforge.metadata(u.versions[pr.folder], u.game_version, u.rtype, readme, required)

        if pr.folder != entry:
            fid = curseforge.upload(pr.project_id, u.zips[pr.folder], meta_for([]), u.token)
        else:
            fid, named = upload_entry(pr, u.zips[pr.folder], meta_for, u.slugs, u.token, u.table.addon_slug)
            if named != entry_requires(u.table):
                partial = True
                u.versions[entry] = vp.version(u.day, vp.entry_hash_of(named, interface_of(data_root())))
                u.zips[entry] = u.zips[entry].rename(u.dist / vp.asset_name(entry, u.versions[entry]))
        print(f"voice release: uploaded {u.zips[pr.folder].name} (CurseForge file {fid})")
        u.record(u.zips[pr.folder])
    return partial


def upload_entry(
    pr: Project,
    zip_path: Path,
    meta_for: Callable[[list[str]], dict[str, Any]],
    slugs: Sequence[str],
    token: str,
    addon_slug: str,
) -> tuple[int, list[str]]:
    """Uploads the entry requiring `slugs`. CurseForge refuses a relation to a project still in review (error
    1018), and reviews a project only after its first file, so a pack that is new this release is left out of
    the entry's list, named, and tried again on the next release. → (file id, the slugs the file requires)."""
    named = list(slugs)
    while True:
        try:
            return curseforge.upload(pr.project_id, zip_path, meta_for(named), token), named
        except curseforge.CurseForgeError as e:
            if not e.refused or e.refused == addon_slug or e.refused not in named:
                raise
            print(f"voice release: CurseForge does not accept {e.refused} as a dependency yet (in review);"
                  " the entry goes up without it and names it next release")
            named.remove(e.refused)


def check_pin(store: Path, pin: Path) -> None:
    """A release ships exactly the audio commit the text pins: the store sits at it, nothing uncommitted."""
    want = voice_store.read_pin(pin)
    git = ["git", "-C", str(store)]
    head = subprocess.run([*git, "rev-parse", "HEAD"], capture_output=True, text=True, check=False)
    head = head.stdout.strip()
    if head != want:
        raise ValueError(f"the audio store is at {head[:12] or 'no commit'}, the text pins {want[:12]}: "
                         f"run `make voice-sync` (from the store's main branch: git -C {store} switch main)")
    if subprocess.run([*git, "status", "--porcelain"], capture_output=True, text=True, check=True).stdout:
        raise ValueError("the audio store has uncommitted files: run `make voice-sync` first")


GH_ASSET_LIMIT = 2 * 1024**3  # bytes: GitHub refuses a release asset of 2 GiB or more


def run_release(a: argparse.Namespace, run: Run = _gh) -> int:
    day = datetime.date.today()
    if a.only and not a.curseforge_only:
        raise ValueError("--only uploads part of a release: use it with --curseforge-only, so the GitHub "
                         "release never records packs that were not uploaded")
    if a.pin:
        check_pin(voice_make.store_dir(a.store), Path(a.pin))
    rows = releases(run)
    state = voice_state(rows, run)
    rtype = release_type(rows)
    built = build(a, day, state.previous)
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
    tag = state.draft or new_tag(day, rows)
    print(f"voice release: last voice release {state.published or 'none'}; this one {tag} ({rtype})"
          + (" (resuming its draft)" if state.draft else ""))
    _print_plan(plan, zips, versions)
    fingerprint = inputs_fingerprint(data_root().parent)
    inputs_new = vp.released_inputs(state.published_assets) != fingerprint[:16]
    nothing = not plan.upload and not plan.no_project
    if nothing and not state.draft:
        if a.curseforge_only or not inputs_new or not state.published:
            print("voice release: nothing changed since the last voice release; nothing to do")
            return 0
        # the packs are what players have, but what builds them changed: record that, so the next release
        # of the addon alone skips the voice again
        print(f"voice release: no pack changed; recording the voice inputs on {state.published}")
        if a.dry_run:
            print("voice release: dry run; nothing uploaded")
            return 0
        inputs = _inputs_file(dist, fingerprint)
        run(["release", "upload", state.published, str(inputs), "--clobber"])
        for old in vp.inputs_assets(state.published_assets):
            if old != inputs.name:
                run(["release", "delete-asset", state.published, old, "--yes"])
        return 0
    if a.curseforge_only:
        print("voice release: CurseForge only; no GitHub release")
    else:
        big = [z.name for z in (*zips.values(), bundle) if z.stat().st_size >= GH_ASSET_LIMIT]
        if big:
            raise ValueError(f"{', '.join(big)} reach GitHub's 2 GiB asset limit; nothing uploaded")
        print(f"voice release: GitHub release {tag}: {len(zips)} zips and {bundle.name}")
        if nothing:
            print(f"voice release: every pack is on CurseForge already; publishing the draft {tag}")
    if a.dry_run:
        print("voice release: dry run; nothing uploaded")
        return 0
    notes = dist / "notes.md"
    notes.write_text(_notes(table, versions, plan), encoding="utf-8")
    flags = ["--latest=false", *(["--prerelease"] if rtype != "release" else [])]
    partial = False
    if plan.upload:
        token = os.environ.get("CF_API_KEY", "")
        if not token:
            print("voice release: no upload token (CF_API_KEY); see docs/operations/voice.md", file=sys.stderr)
            return 1
        gv = curseforge.game_version_id(curseforge.game_versions(token), interface_of(data_root()))
        slugs = [table.addon_slug] if a.entry_without_packs else entry_requires(table)
        if a.entry_without_packs:
            print("voice release: the entry requires the main addon only (no packs)")
        record = _recorder(None if a.curseforge_only else tag, state, notes, flags, day, run)
        partial = upload_all(Uploads(table, plan, zips, versions, out, dist, day, gv, rtype, slugs, token, record))
    if a.curseforge_only:
        print("voice release: done (CurseForge only)")
        return 0
    if not state.draft and not plan.upload:  # only packs with no project changed: still a release on GitHub
        _recorder(tag, state, notes, flags, day, run)
    final = [*zips.values(), bundle]
    if partial:
        # left unrecorded, so the next release runs the voice job and tries the full entry again (a pack with no
        # project yet needs no such help: giving it one edits voice-packs.toml, a voice input)
        print("voice release: the entry went up without some packs; the next release tries them again")
    else:
        final.append(_inputs_file(dist, fingerprint))
    run(["release", "upload", tag, *map(str, final), "--clobber"])
    for stale in sorted(set(state.draft_assets) - {p.name for p in final}):
        run(["release", "delete-asset", tag, stale, "--yes"])
    notes.write_text(_notes(table, versions, plan), encoding="utf-8")
    run(["release", "edit", tag, "--draft=false", "--notes-file", str(notes), *flags])
    print(f"voice release: done: {tag}")
    return 0


def _inputs_file(dist: Path, fingerprint: str) -> Path:
    path = dist / vp.inputs_asset(fingerprint)
    path.write_text(f"{fingerprint}\n", encoding="utf-8")
    return path


def _recorder(
    tag: str | None, state: VoiceState, notes: Path, flags: Sequence[str], day: datetime.date, run: Run
) -> Callable[[Path], None]:
    """Keeps each zip CurseForge accepted on the voice release's draft (made now, or the one a failed run
    left), so a re-run counts it as released. No tag: a CurseForge-only rehearsal, nothing recorded."""
    if tag is None:
        return lambda _zip: None
    if not state.draft:
        run(["release", "create", tag, "--draft", "--title", f"Voice {day:%Y.%m.%d}", "--notes-file",
             str(notes), *flags])
    return lambda zip_path: run(["release", "upload", tag, str(zip_path), "--clobber"])


def _print_plan(plan: Plan, zips: Mapping[str, Path], versions: Mapping[str, str]) -> None:
    for pr in plan.upload:
        print(f"voice release: upload {zips[pr.folder].name} to CurseForge project {pr.project_id}"
              f" ({pr.slug})")
    for pr in plan.no_project:
        print(f"voice release: {pr.folder} changed but has no CurseForge project yet (project_id 0):"
              " not uploaded")
    for f in plan.unchanged:
        print(f"voice release: {f} unchanged ({versions[f]})")


# What the voice packs are built from: the whole pipeline package (any code change counts, a false "changed"
# only costs a checkout) and every data folder the build reads. A release of the addon alone leaves all of it
# unchanged, and the Release workflow then skips the voice job instead of checking out the audio.
INPUTS = (
    "pipeline/voice-audio-commit.txt", "pipeline/voice-packs.toml", "pipeline/voice.toml",
    "pipeline/voice_quest_levels.txt", "pipeline/wfj", "addon/WoWForeverJapanese/WoWForeverJapanese.toc",
    "data/SCHEMA", "data/voice", "data/quest", "data/gossip", "data/book", "data/ui",
    "data/english/gossip", "data/english/quest", "data/english/book", "data/english/ui",
)


def inputs_fingerprint(repo: Path) -> str:
    """The git objects of everything the packs are built from, at HEAD: equal fingerprints, equal packs."""
    h = hashlib.sha256()
    for path in INPUTS:
        obj = subprocess.run(["git", "-C", str(repo), "rev-parse", f"HEAD:{path}"], capture_output=True,
                             text=True, check=False).stdout.strip()
        h.update(f"{path} {obj or 'missing'}\n".encode())
    return h.hexdigest()


def run_inputs(run: Run = _gh) -> int:
    """`changed=true|false` for $GITHUB_OUTPUT: whether the voice inputs differ from the last release's."""
    published, _ = last_voice(releases(run), run)
    recorded = vp.released_inputs(_assets(published, run)) if published else None
    now = inputs_fingerprint(data_root().parent)[:16]
    print(f"changed={'false' if recorded == now else 'true'}")
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
    if list(argv[:1]) == ["inputs"]:
        return run_inputs()
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

