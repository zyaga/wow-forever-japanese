"""Empty `data/english/` for a rebuild, keeping the English a client recorded in game.

    python -m wfj.dev.reset_english <data/english>

`make rebuild-check` rebuilds the English from the pinned inputs. Collector lines (`src collector@…`) come
from players' dumps, which no pinned input reproduces, and they outrank the stand-in sources (ADR-053), so
they are kept: every other line is removed, and a file left with no line is deleted.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

COLLECTOR = "collector@"


def reset(root: Path) -> tuple[int, int]:
    """→ (lines kept, lines removed)"""
    kept = removed = 0
    for path in sorted(root.rglob("*.jsonl")):
        lines = path.read_text(encoding="utf-8").splitlines()
        keep = [ln for ln in lines if ln.strip() and str(json.loads(ln).get("src", "")).startswith(COLLECTOR)]
        kept, removed = kept + len(keep), removed + len(lines) - len(keep)
        if keep:
            path.write_text("".join(ln + "\n" for ln in keep), encoding="utf-8")
        else:
            path.unlink()
    return kept, removed


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    kept, removed = reset(Path(argv[0]))
    print(f"reset-english: {removed} lines removed, {kept} collector lines kept")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
