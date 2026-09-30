def test_gpl2_license_text(root):
    text = (root / "LICENSE").read_text(encoding="utf-8")
    assert "GNU GENERAL PUBLIC LICENSE" in text[:200]
    assert "Version 2, June 1991" in text[:200]


def test_or_later_declared(root):
    assert 'license = { text = "GPL-2.0-or-later" }' in (root / "pipeline" / "pyproject.toml").read_text()
    assert "## X-License: GPL-2.0-or-later" in (
        root / "addon" / "WoWForeverJapanese" / "WoWForeverJapanese.toc"
    ).read_text(encoding="utf-8")


def test_font_and_license_shipped(root):
    fonts = root / "addon" / "WoWForeverJapanese" / "Fonts"
    assert (fonts / "ipagui.ttf").stat().st_size > 1_000_000
    assert "IPA" in (fonts / "IPA_Font_License_Agreement_v1.0.txt").read_text(encoding="utf-8")[:200]
