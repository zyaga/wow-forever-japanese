"""wfj voice levels|store-sync: the inputs a voice release needs that live outside the shipped data (ADR-062;
runbook docs/operations/voice.md).

  levels --wdb CACHE --vmangos DB [--out voice_quest_levels.txt]
      Writes each quest's level (the client's quest cache first, VMaNGOS for quests it has not answered) to a
      committed table, so the packs can be split where the client files are not, such as the Release workflow.
      A quest the table already has and neither source gives a level keeps its level (ADR-050).
  store-sync [--store DIR] [--pin voice-audio-commit.txt] [--if-changed]
      Commits whatever the audio store (a checkout of the voice audio repository) holds new or changed,
      pushes it, and writes that commit to the pin file: the audio commit that goes with this checkout's text.
      --if-changed does nothing when the store holds nothing new (or is absent), so a round that made no audio
      neither pushes nor moves the pin to whatever another branch last synced.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path

from wfj.cmd import voice_make
from wfj.io import vmangos, wdb
from wfj.paths import data_root

LEVELS = "voice_quest_levels.txt"
PIN = "voice-audio-commit.txt"
LEVELS_HEAD = (
    "# Each quest's level for the voice packs' level bands, written by `make voice-levels`.\n"
    "# Do not edit by hand. The client's quest cache first, VMaNGOS for quests it has not answered, then\n"
    "# the level this table had for a quest neither gives (an earlier build's quest keeps its band).\n"
    "# `<quest id> <level>` per line.\n"
)
PIN_HEAD = (
    "# The voice audio repository's commit that goes with this repository's text, written by\n"
    "# `wfj voice store-sync` after a voice run. A release builds the voice packs from exactly this commit.\n"
)


def levels_text(levels: Mapping[int, int]) -> str:
    return LEVELS_HEAD + "".join(f"{q} {lv}\n" for q, lv in sorted(levels.items()))


def read_levels(path: Path) -> dict[int, int]:
    out = {}
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 2 or not all(p.isdigit() for p in parts):
            raise ValueError(f"{path.name}:{n}: want `<quest id> <level>`, got {raw!r}")
        out[int(parts[0])] = int(parts[1])
    return out


def read_pin(path: Path) -> str:
    lines = [ln.strip() for ln in path.read_text(encoding="utf-8").splitlines()]
    shas = [ln for ln in lines if ln and not ln.startswith("#")]
    if len(shas) != 1 or len(shas[0]) != 40 or any(c not in "0123456789abcdef" for c in shas[0]):
        raise ValueError(f"{path.name}: want one full commit hash")
    return shas[0]


def _git(store: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(store), *args], capture_output=True, text=True, check=True).stdout


def has_changes(store: Path) -> bool:
    """Whether the store is a checkout holding files not committed yet, or commits not pushed yet (a sync
    whose push failed is tried again)."""
    if not (store / ".git").exists():
        return False
    if _git(store, "status", "--porcelain"):
        return True
    ahead = subprocess.run(["git", "-C", str(store), "rev-list", "--count", "@{u}..HEAD"],
                           capture_output=True, text=True, check=False)
    return ahead.returncode == 0 and ahead.stdout.strip() not in ("", "0")


def sync(store: Path, pin: Path, message: str) -> str:
    """Commits what changed in the store, pushes, writes the pin. → the commit."""
    if not (store / ".git").exists():
        raise ValueError(f"{store} is not a checkout of the voice audio repository (see the voice runbook)")
    on_branch = subprocess.run(["git", "-C", str(store), "symbolic-ref", "-q", "HEAD"], capture_output=True,
                               check=False)
    if on_branch.returncode:
        raise ValueError(f"the audio store is not on a branch (it sits at one commit): run `git -C {store} "
                         "switch main`, then sync again")
    if _git(store, "status", "--porcelain"):
        _git(store, "add", "-A")
        _git(store, "commit", "-q", "-m", message)
    _git(store, "push", "-q", "origin", "HEAD")
    sha = _git(store, "rev-parse", "HEAD").strip()
    pin.write_text(PIN_HEAD + sha + "\n", encoding="utf-8")
    return sha


def run(argv: Sequence[str]) -> int:
    p = argparse.ArgumentParser(prog="wfj voice")
    sub = p.add_subparsers(dest="cmd", required=True)
    lv = sub.add_parser("levels")
    lv.add_argument("--wdb", required=True)
    lv.add_argument("--vmangos", required=True)
    lv.add_argument("--out", default=LEVELS)
    st = sub.add_parser("store-sync")
    st.add_argument("--store")
    st.add_argument("--pin", default=PIN)
    st.add_argument("--if-changed", action="store_true")
    a = p.parse_args(list(argv))
    try:
        if a.cmd == "levels":
            from wfj.cmd.voice_ship import quest_levels  # voice_ship reads this module's files

            levels = quest_levels(Path(a.wdb), Path(a.vmangos))
            # English is additive (ADR-050): a quest the new cache does not answer keeps its voice, so it
            # keeps the level it had too, and its audio stays in its level band's pack
            out = Path(a.out)
            if out.is_file():
                answered = {q.id for q in wdb.read_quests(Path(a.wdb)).quests}
                for q, lv in read_levels(out).items():
                    if q not in levels and q not in answered:
                        levels[q] = lv
            out.write_text(levels_text(levels), encoding="utf-8")
            print(f"voice levels: {len(levels)} quests → {a.out}")
            return 0
        store = voice_make.store_dir(a.store)
        if a.if_changed and not has_changes(store):
            print("voice store-sync: nothing new in the audio store; the pin stays")
            return 0
        head = subprocess.run(
            ["git", "-C", str(data_root().parent), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=False,
        ).stdout.strip()
        message = f"Voice audio for the text at {head or 'HEAD'}"
        sha = sync(store, Path(a.pin), message)
        print(f"voice store-sync: audio commit {sha[:12]} pushed and pinned in {a.pin}")
        return 0
    except (ValueError, wdb.WdbError, vmangos.VmangosError, subprocess.CalledProcessError) as e:
        detail = e.stderr.strip() if isinstance(e, subprocess.CalledProcessError) and e.stderr else e
        print(f"voice {a.cmd}: {detail}", file=sys.stderr)
        return 1
