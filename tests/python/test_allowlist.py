from wfj.core.align import allowlist_problems, load_allowlist
from wfj.io.jsonl_store import Store


def test_every_allowlist_line_is_justified(root):
    text = (root / "pipeline/allowlist.txt").read_text(encoding="utf-8")
    assert allowlist_problems(text) == []
    assert len(load_allowlist(text)) >= 10


def test_every_allowlist_term_is_used_by_the_corpus(root):
    """A term nobody needs must not be allowlisted (it would hide a real misalignment)."""
    terms = load_allowlist((root / "pipeline/allowlist.txt").read_text(encoding="utf-8"))
    store = Store(root / "data")
    corpus = "\n".join(ln["ja"] for t in ("quest", "item", "spell") for ln in store.load(t)).casefold()
    if not corpus:
        return
    unused = sorted(t for t in terms if t not in corpus)
    assert unused == [], unused
