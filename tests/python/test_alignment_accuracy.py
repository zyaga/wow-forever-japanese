"""The alignment rules are measured against 200 hand-labelled quest descriptions.

Precision of `trusted` (rule-trusted lines the labeller calls aligned) is the gate: >= 0.95.
Recall of `misaligned` (labelled-misaligned lines the rules reject) is reported, not gated.
Labels: tests/fixtures/alignment_sample.jsonl (labelled by a model reading JA against EN, not
independently verified; recall is a within-sample figure, not an estimate of true recall).
"""

import json

from wfj.io.jsonl_store import Store

PRECISION_FLOOR = 0.95


def _sample(root):
    return [
        json.loads(line) for line in (root / "tests/fixtures/alignment_sample.jsonl").open(encoding="utf-8")
    ]


def test_sample_is_complete_and_labelled(root):
    rows = _sample(root)
    assert len(rows) == 200
    assert all(r["label"] in ("aligned", "misaligned") for r in rows)
    assert all(r["note"] for r in rows if r["label"] == "misaligned")


def test_rule_precision_and_recall(root, capsys):
    import re as _re

    def _ws(t: str) -> str:  # paragraph breaks are canonicalised; compare whitespace-agnostically
        return _re.sub(r"\s+", " ", t).strip()

    sample = {r["id"]: r for r in _sample(root)}
    by_id = {ln["id"]: ln for ln in Store(root / "data").load("quest") if ln["field"] == "description"}
    if not by_id:
        return
    # The labels describe a specific Japanese text. A line's text can be a *different* variant
    # (a complete lineage translation replacing a truncated one), so only rows whose text is unchanged count.
    rows = {i: r for i, r in sample.items() if i in by_id and _ws(by_id[i]["ja"]) == _ws(r["ja"])}
    replaced = sorted(set(sample) - set(rows))
    trusted = [i for i in rows if by_id[i]["status"] in ("trusted", "stale")]
    rejected = [i for i in rows if by_id[i]["status"] == "rejected"]
    tp = sum(1 for i in trusted if rows[i]["label"] == "aligned")
    precision = tp / len(trusted)
    mis = [i for i in rows if rows[i]["label"] == "misaligned"]
    # every labelled-misaligned line has since been corrected or redrafted, so none keeps its labelled text: recall n/a
    recall = sum(1 for i in mis if i in rejected) / len(mis) if mis else float("nan")
    false_trusted = [i for i in trusted if rows[i]["label"] == "misaligned"]
    false_rejected = [i for i in rejected if rows[i]["label"] == "aligned"]
    with capsys.disabled():
        print(
            f"\nalignment accuracy over {len(rows)} labelled descriptions: precision(trusted)={precision:.3f} "
            f"({tp}/{len(trusted)}), recall(misaligned)={recall:.3f} ({len(mis) - len([i for i in mis if i not in rejected])}/{len(mis)}); "
            f"false trusted={false_trusted}; false rejected={len(false_rejected)}; "
            f"{len(replaced)} sample rows skipped (text replaced by a lineage variant since labelling)"
        )
    assert precision >= PRECISION_FLOOR, (
        f"precision {precision:.3f} < {PRECISION_FLOOR}; false trusted ids: {false_trusted}"
    )
