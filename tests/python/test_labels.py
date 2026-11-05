"""Every label the issue forms name and the check workflows look for or add is in .github/labels.tsv.

GitHub drops a form's label when the repository has no label of that name, and the check workflows only run on
an issue that carries their label. So a label missing from the repository stops a check without a trace. The
labels workflow creates every label in the list; these tests keep the list complete.
"""

import re
from pathlib import Path

LIST = ".github/labels.tsv"


def _labels(root: Path) -> dict[str, tuple[str, str]]:
    lines = (root / LIST).read_text(encoding="utf-8").splitlines()
    assert lines[0] == "name\tcolor\tdescription"
    labels: dict[str, tuple[str, str]] = {}
    for line in lines[1:]:
        name, color, description = line.split("\t")
        assert name not in labels, name
        labels[name] = (color, description)
    return labels


def test_the_list_is_well_formed(root):
    labels = _labels(root)
    assert labels
    for name, (color, description) in labels.items():
        assert re.fullmatch(r"[a-z][a-z-]*", name), name
        assert re.fullmatch(r"[0-9a-f]{6}", color), name
        assert description and '"' not in description and len(description) <= 100, name


def test_every_form_label_is_listed(root):
    labels = _labels(root)
    forms = sorted((root / ".github/ISSUE_TEMPLATE").glob("*.yml"))
    named = set()
    for form in forms:
        m = re.search(r"(?m)^labels: \[(.*)\]$", form.read_text(encoding="utf-8"))
        if m:
            named |= {n.strip().strip('"') for n in m.group(1).split(",") if n.strip()}
    assert {"collector-send", "translation-report", "bug", "enhancement"} <= named
    assert named - labels.keys() == set()


def test_every_label_a_workflow_needs_is_listed_as_the_workflow_writes_it(root):
    labels = _labels(root)
    needed = set()
    for wf in sorted((root / ".github/workflows").glob("*.y*ml")):
        text = wf.read_text(encoding="utf-8")
        needed |= set(re.findall(r"labels\.\*\.name, '([\w-]+)'", text))
        needed |= set(re.findall(r"github\.event\.label\.name == '([\w-]+)'", text))
        needed |= set(re.findall(r"\b(?:add|drop)=([\w-]+)", text))
        for name, color, description in re.findall(
            r'gh label create ([\w-]+) --color (\w+) --description "([^"]+)" --force', text
        ):
            assert labels.get(name) == (color, description), f"{wf.name}: {name}"
            needed.add(name)
    assert {"collector-send", "collector-ok", "collector-broken", "report-ok", "report-broken"} <= needed
    assert needed - labels.keys() == set()
