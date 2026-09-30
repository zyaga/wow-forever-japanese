"""Every listed UI key is one the inventory sees (pipeline/ui_inventory.txt) or is in
pipeline/ui_uninventoried.txt with a reason: a listed key nothing on Forever can show is caught, and so is a
key the inventory stops seeing after a client update."""

import re
from pathlib import Path

from wfj.io import wago

ROOT = Path(__file__).resolve().parents[2]


def _allowlist() -> dict[str, str]:
    out = {}
    for ln in (ROOT / "pipeline/ui_uninventoried.txt").read_text(encoding="utf-8").splitlines():
        if not ln.strip() or ln.startswith("#"):
            continue
        key, _, reason = ln.partition("#")
        out[key.strip()] = reason.strip()
    return out


def _inventory() -> set[str]:
    text = (ROOT / "pipeline/ui_inventory.txt").read_text(encoding="utf-8")
    return {ln.split()[1] for ln in text.splitlines() if ln.strip() and not ln.startswith("#")}


def test_every_listed_key_is_inventoried_or_allowed_with_a_reason():
    listed = wago.read_keys(ROOT / "pipeline/ui_keys.txt")
    inventory, allowed = _inventory(), _allowlist()
    # client-table keys (ItemSubClass:…, SpellSubtext:…) are not GlobalStrings: no Lua names them by design
    missing = [k for k in listed if re.fullmatch(r"[A-Z][A-Z0-9_]*", k) and k not in inventory and k not in allowed]
    assert missing == [], f"listed but neither inventoried nor allowed: {missing[:20]}"
    assert all(allowed.values()), "every allowlist line needs a reason"


def test_the_allowlist_holds_only_listed_keys_the_inventory_cannot_see():
    listed, inventory = set(wago.read_keys(ROOT / "pipeline/ui_keys.txt")), _inventory()
    stale = sorted(k for k in _allowlist() if k not in listed or k in inventory)
    assert stale == [], f"remove from ui_uninventoried.txt: {stale}"


def test_the_binding_names_are_inventoried():
    # the Bindings XML reader: the 300 listed binding names are all seen now
    inventory = _inventory()
    bindings = [k for k in wago.read_keys(ROOT / "pipeline/ui_keys.txt") if k.startswith("BINDING_")]
    assert len(bindings) >= 290
    assert not [k for k in bindings if k not in inventory]
