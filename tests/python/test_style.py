"""ADR-023: one place for the translation style version: draft names, machine sources, the guide."""

import pytest

from wfj.core import style


@pytest.mark.parametrize(("source", "version"), [
    ("draft-progress-sg3@2026-09-15", 3),
    ("draft-gossip-sg10@2026-09-15", 10),
    ("draft-x-sg2-y-sg3@2026-09-14", 3),  # the -sg<N> right before @, not the first one
    ("draft-foo-sg3x@2026-09-14", 0),     # not a version
    ("draft-foo-sg10-sg3@2026-09-14", 3),
    ("draft-ui@2026-09-14", 0),
    ("draft-gossip-shadowglen@2026-09-14", 0),
    ("", 0),
])
def test_source_version_reads_the_sg_right_before_the_date(source, version):
    assert style.source_version({"source": source}) == version


def test_name_version_and_check_name():
    assert style.name_version("progress-sg3") == 3
    assert style.name_version("progress") is None
    assert style.name_version("progress-sg3x") is None
    assert style.name_version("Progress-sg3") is None
    assert style.name_version("a" * 30 + "-sg3") is None  # longer than `wfj import draft` accepts
    style.check_name("completion-sg3", 3)
    with pytest.raises(ValueError, match="-sg3"):
        style.check_name("completion-sg2", 3)


def test_guide_version(tmp_path):
    with pytest.raises(ValueError, match="no style guide"):
        style.guide_version(tmp_path)
    (tmp_path / style.STYLE_GUIDE).parent.mkdir(parents=True)
    (tmp_path / style.STYLE_GUIDE).write_text("# guide\n\nversion: sg4\n")
    assert style.guide_version(tmp_path) == 4
    (tmp_path / style.STYLE_GUIDE).write_text("no version\n")
    with pytest.raises(ValueError, match="version"):
        style.guide_version(tmp_path)
