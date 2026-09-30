"""`python -m wfj <verb>`: the pipeline's public contract (docs/systems/pipeline.md).

"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Callable, Sequence

from wfj.cmd import (
    check,
    fix_report,
    generate,
    glosses,
    import_,
    package_check,
    public_check,
    readings,
    release,
    stats,
    toc_check,
    validate,
)

VERBS: dict[str, tuple[str, Callable[[Sequence[str]], int]]] = {
    "import": ("import predecessor data / English sources", import_.run),
    "check": ("dedupe, align, assign statuses; --report prints yield", check.run),
    "generate": ("data/ → addon Data/*.lua", generate.run),
    "validate": ("the CI gate: schema, provenance, collisions, regenerate-and-diff", validate.run),
    "stats": ("coverage and provenance deltas", stats.run),
    "toc-check": ("assert the TOC ## Interface matches clients.toml", toc_check.run),
    "readings": ("export lines for readings / import a readings batch", readings.run),
    "glosses": ("check the word popup's dictionary forms against JMdict (local)", glosses.run),
    "report": ("a player's fix report: check / intake / apply", fix_report.run),
    "release": ("changelog + version for a release; the pull-request changelog gate", release.run),
    "package-check": ("the release zip holds exactly the shipped files", package_check.run),
    "public-check": ("keep private material out of the public repository", public_check.run),
}


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="wfj", description="WoW Forever Japanese data pipeline")
    sub = p.add_subparsers(dest="verb", metavar="<verb>")
    for name, (help_, _) in VERBS.items():
        sub.add_parser(name, help=help_, add_help=False)
    return p


def main(argv: Sequence[str] | None = None) -> int:
    # The verb takes everything after it verbatim (flags included); argparse REMAINDER rejects a
    # leading flag, so split by hand: `wfj check --report` must reach the check handler untouched.
    argv = list(sys.argv[1:] if argv is None else argv)
    parser = build_parser()
    if not argv or argv[0] in ("-h", "--help"):
        parser.print_help()
        return 0
    verb, rest = argv[0], argv[1:]
    if verb not in VERBS:
        parser.parse_args([verb])  # argparse prints the usage error and exits 2
        return 2
    return VERBS[verb][1](rest)
