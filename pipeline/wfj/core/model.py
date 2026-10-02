"""Line shapes for `data/` (source of truth); see docs/architecture/data-model.md.

One JSON object per (id, field). Key order is fixed by the constructors below so the
JSONL output is deterministic. `validate_line` is the schema check used by tests and
by `wfj validate`.
"""

from __future__ import annotations

import re
from collections.abc import Iterable
from typing import Any

SCHEMA = 1
# ids per JSONL shard and per generated Lua shard. Keep well under LuaJIT's 65,536-constants-per-function
# cap: the largest shard today holds ~2.8k constants, so a width bump has ~20× headroom, not unlimited.
SHARD_WIDTH = 1000

# Field order per type, also the sort order inside a shard.
FIELDS: dict[str, list[str]] = {
    "quest": ["title", "objectives", "description", "progress", "completion"],
    "item": ["description"],
    # `aura` is the buff / debuff wording of a spell (`Spell.AuraDescription_lang`), a different
    # string from the tooltip `description` under the same spell id.
    "spell": ["description", "aura"],
    "gossip": ["text"],
    "unit": ["name"],
    "ui": ["text"],
    # book pages (id = the page_text entry). There is no trainer greeting kind: Forever's trainer UI has no
    # greeting.
    "book": ["text"],
    # an objective's own server text ("Rescue Drull"), id = the QuestObjective id. The addon matches
    # the live line by the fingerprint of that text (the client exposes no objective id), ADR-031.
    "objective": ["text"],
    # a quest's exploration / event objective text from the quest cache ("Scout through the Fargodeep
    # Mine"), id = the quest id. Shaped like `objective`: the addon finds it by the fingerprint of the line.
    "area": ["text"],
}
ENGLISH_FIELDS: dict[str, list[str]] = {
    "quest": ["title", "objectives", "description", "progress", "completion"],
    "item": ["name", "description"],
    "spell": ["name", "description", "aura"],
    "gossip": ["text"],
    "unit": ["name"],
    "ui": ["text"],
    # objective: id = the QuestObjective id, from the quest cache. book: id = the page_text entry.
    "objective": ["text"],
    "book": ["text"],
    # the quest cache's area description, its own type, id = the quest id
    "area": ["text"],
}
# Key-by-English-hash types (ADR-005): the id is the 16-hex hash of the normalized English.
HASH_KEYED = ("gossip",)
STATUSES = ("pending", "trusted", "unaligned", "stale", "rejected", "missing")
PROVENANCE_CLASSES = ("human", "machine", "correction")
_SOURCE_RE = re.compile(r"^[a-z0-9_-]+@[0-9A-Za-z._-]{4,64}$")
_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
# A UI string key (ADR-014): a Blizzard global-string name, `ItemSubClass:<classID>:<subClassID>`,
# or `SpellItemEnchantment:<id>` (ADR-016): an enchantment's stat line ("+3 Fire Spell Damage"), or
# `SpellSubtext:<spellID>`: a spell's spellbook subtext ("Racial Passive", Spell.NameSubtext_lang),
# or `<family>:<id>` (ADR-042): a client-table text family (`io/wago.TEXT_FAMILIES`, whose keys this
# list repeats because core does not import io; a test keeps them equal), keyed by the table's row id.
UI_FAMILIES = (
    "FactionDescription",
    "AchievementTitle",
    "AchievementDescription",
    "AchievementReward",
    "AchievementCategory",
    "SkillLineDescription",
    "SkillCategory",
    "EmoteText",
    "HolidayDescription",
    "CurrencyDescription",
    "CurrencyCategory",
    "DispelType",
    "CreatureType",
    "QuestSort",
    "CustomizationCategory",
    "CustomizationOption",
    "CustomizationChoice",
    "CustomizationSource",
    "PvpColumn",
    "PvpColumnTooltip",
    "LfgCategory",
    "LfgActivityGroup",
    "LfgActivity",
    "WidgetText",
    "ItemNameDescription",
    "CriteriaText",
    "RenownRewardName",
    "RenownRewardDescription",
    "RenownRewardToast",
    "SharedString",
    "TradeSkillCategory",
    "MailBody",
    "QuestTag",
    "AreaPoiDescription",
    "AreaPoiState",
    "PetLoyalty",
    "PvpLongDescription",
    "Difficulty",
    "EventToastText",
    "BroadcastText",
    "PetFood",
    "RestState",
    "ItemSubClassMask",
    "RecentAllyType",
    "RecentAllyInteraction",
    "FriendshipLabel",
    "FriendshipGain",
    "InstanceEntryMessage",
    "InstanceEntryFailure",
)
# The restricted families (ADR-042): the addon finds their rows only where a widget names the
# family, so each family is a vocabulary of its own: its Japanese may differ from an open key's (or another
# family's) of the same English ("Close" is 閉じる on a button and a tusk style, 寄せ, in the barber shop).
RESTRICTED_FAMILIES = (*UI_FAMILIES, "ItemSubClassName")


def ui_family(key: str) -> str | None:
    """The restricted family a UI key belongs to, or None for an open key."""
    head = str(key).split(":", 1)[0]
    return head if ":" in str(key) and head in RESTRICTED_FAMILIES else None


UI_KEY_RE = re.compile(
    r"^(?:[A-Z][A-Z0-9_]*|ItemSubClass:\d+:\d+|ItemSubClassName:\d+:\d+|SpellItemEnchantment:\d+|SpellSubtext:\d+|(?:"
    + "|".join(UI_FAMILIES)
    + r"):\d+)$"
)


def _valid_ruling(r: Any) -> bool:
    return (
        isinstance(r, dict)
        and r.get("ruling") in ("accept", "reject")
        and isinstance(r.get("by"), str)
        and bool(r.get("by"))
        and isinstance(r.get("date"), str)
        and bool(_DATE_RE.match(r["date"]))
    )


def _provenance_problems(prov: dict[str, Any], label: str) -> list[str]:
    p: list[str] = []
    if prov.get("class") not in PROVENANCE_CLASSES:
        p.append(f"{label}.class {prov.get('class')!r} not in {PROVENANCE_CLASSES}")
    if not isinstance(prov.get("source"), str) or not _SOURCE_RE.match(prov["source"]):
        p.append(f"{label}.source must look like name@ref")
    if not isinstance(prov.get("imported"), str) or not _DATE_RE.match(prov["imported"]):
        p.append(f"{label}.imported must be YYYY-MM-DD")
    if prov.get("class") in ("human", "correction") and not prov.get("translator"):
        p.append(f"{prov.get('class')} provenance needs a translator")
    if prov.get("class") == "machine" and not (isinstance(prov.get("model"), str) and prov["model"].strip()):
        # machine-drafted text names the model that wrote it (ADR-014)
        p.append("machine provenance needs model (the model id that drafted the text)")
    if prov.get("class") == "machine" and prov.get("critic") is not None and not (
        isinstance(prov["critic"], str) and prov["critic"].strip()
    ):
        p.append("machine provenance critic must be a non-empty string when present")
    if prov.get("class") == "correction" and not (
        isinstance(prov.get("corrects"), str) and _SOURCE_RE.match(prov["corrects"])
    ):
        p.append("correction provenance needs corrects (the source of the corrected variant, name@ref)")
    # a variant written from a player's fix report (ADR-045) names the GitHub issue it came from,
    # and a correction the model wrote (rather than the player's own Japanese) names the model
    if "report" in prov:
        r = prov["report"]
        if prov.get("class") not in ("correction", "machine"):
            p.append("report is only on correction or machine provenance")
        elif not (isinstance(r, int) and not isinstance(r, bool) and r > 0):
            p.append("report must be a positive int (the fix report's issue number)")
    if prov.get("class") == "correction" and "model" in prov and not (
        isinstance(prov["model"], str) and prov["model"].strip()
    ):
        p.append("correction provenance model must be a non-empty string when present")
    return p


def provenance_problems(prov: dict[str, Any], label: str) -> list[str]:
    """The provenance checks every store shares (reading records use them too)."""
    return _provenance_problems(prov, label)


def provenance(
    cls: str, source: str, imported: str, *, translator: str | None = None, origins: list[str] | None = None
) -> dict[str, Any]:
    p: dict[str, Any] = {"class": cls}
    if translator is not None:
        p["translator"] = translator
    p["source"] = source
    p["imported"] = imported
    if origins:
        p["origins"] = origins
    return p


def entry(
    id_: int | str,
    field: str,
    ja: str,
    *,
    status: str = "pending",
    prov: dict[str, Any],
    conflicts: list[dict[str, Any]] | None = None,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """A translation line. The type is not stored; the shard path carries it."""
    line: dict[str, Any] = {
        "id": id_,
        "field": field,
        "ja": ja,
        "status": status,
        "checks": [],
        "provenance": prov,
        "english": None,
        "reasons": [],
        "conflicts": conflicts or [],
    }
    if extra:
        line["extra"] = extra
    return line


def english_line(
    id_: int | str, field: str, en: str, hash_: str, src: str, *, npcs: Iterable[int] | None = None
) -> dict[str, Any]:
    """An English line. `npcs` (gossip only): the creature ids the collector saw say the line."""
    line: dict[str, Any] = {"id": id_, "field": field, "en": en, "hash": hash_, "src": src}
    if npcs:
        line["npcs"] = sorted(set(npcs))
    return line


def _valid_npcs(n: Any) -> bool:
    return (
        isinstance(n, list)
        and bool(n)
        and all(isinstance(x, int) and not isinstance(x, bool) and 0 < x < 2**31 for x in n)
        and n == sorted(set(n))
    )


def field_index(type_: str, field: str, *, english: bool = False) -> int:
    table = ENGLISH_FIELDS if english else FIELDS
    return table[type_].index(field)


def validate_line(type_: str, line: dict[str, Any], *, english: bool = False) -> list[str]:
    """Return problems (empty list = valid)."""
    fields = (ENGLISH_FIELDS if english else FIELDS).get(type_)
    if fields is None:
        return [f"unknown type {type_!r}"]
    p = _id_problems(type_, line.get("id"))
    if line.get("field") not in fields:
        p.append(f"field {line.get('field')!r} not in {fields}")
    if english:
        return p + _english_problems(type_, line)
    return p + _translation_problems(line)


def _id_problems(type_: str, id_: Any) -> list[str]:
    """The problems with a line's id, which each type keys its own way."""
    if type_ in HASH_KEYED:
        if not (isinstance(id_, str) and re.fullmatch(r"[0-9a-f]{16}", id_)):
            return [f"{type_} id must be a 16-hex key"]
    elif type_ == "ui":
        if not (isinstance(id_, str) and UI_KEY_RE.match(id_)):
            return [
                "ui id must be a global-string name, ItemSubClass:<classID>:<subClassID>"
                ", SpellItemEnchantment:<id>, SpellSubtext:<spellID> or <family>:<id>"
            ]
    elif not (isinstance(id_, int) and not isinstance(id_, bool) and id_ > 0):
        return ["id must be a positive int"]
    return []


def _english_problems(type_: str, line: dict[str, Any]) -> list[str]:
    """The problems with an English line past its id and field."""
    p: list[str] = []
    for k in ("en", "hash", "src"):
        if not isinstance(line.get(k), str) or not line[k]:
            p.append(f"{k} must be a non-empty string")
    if isinstance(line.get("hash"), str) and not re.fullmatch(r"[0-9a-f]{16}", line["hash"]):
        p.append("hash must be 16 hex chars")
    if isinstance(line.get("src"), str) and not _SOURCE_RE.match(line["src"]):
        p.append("src must look like name@ref")
    allowed = {"id", "field", "en", "hash", "src"} | ({"npcs"} if type_ == "gossip" else set())
    if "npcs" in line and type_ == "gossip" and not _valid_npcs(line["npcs"]):
        p.append("npcs must be a non-empty sorted list of unique positive ints")
    extra_keys = set(line) - allowed
    if extra_keys:
        p.append(f"unexpected keys {sorted(extra_keys)}")
    return p


_TRANSLATION_KEYS = frozenset(
    {
        "id",
        "field",
        "ja",
        "status",
        "checks",
        "provenance",
        "english",
        "reasons",
        "conflicts",
        "extra",
        "ruling",
    }
)


def _translation_problems(line: dict[str, Any]) -> list[str]:
    """The problems with a translation line past its id and field."""
    p: list[str] = []
    if not isinstance(line.get("ja"), str):
        p.append("ja must be a string")
    if line.get("status") not in STATUSES:
        p.append(f"status {line.get('status')!r} not in {STATUSES}")
    if line.get("status") == "missing" and line.get("ja"):
        p.append("missing entries carry no ja")
    if not isinstance(line.get("checks"), list):
        p.append("checks must be a list")
    prov = line.get("provenance")
    if not isinstance(prov, dict):
        p.append("provenance must be an object")
    else:
        p += _provenance_problems(prov, "provenance")
    eng = line.get("english")
    if eng is not None and not (isinstance(eng, dict) and set(eng) >= {"hash", "src"}):
        p.append("english must be null or {hash, src}")
    if not isinstance(line.get("reasons"), list):
        p.append("reasons must be a list")
    p += _conflict_problems(line)
    extra_keys = set(line) - _TRANSLATION_KEYS
    if extra_keys:
        p.append(f"unexpected keys {sorted(extra_keys)}")
    return p


def _conflict_problems(line: dict[str, Any]) -> list[str]:
    """The problems with a line's `conflicts` list and with the rulings on it and its variants."""
    p: list[str] = []
    if not isinstance(line.get("conflicts"), list):
        p.append("conflicts must be a list")
    else:
        for c in line["conflicts"]:
            if not (
                isinstance(c, dict) and isinstance(c.get("ja"), str) and isinstance(c.get("provenance"), dict)
            ):
                p.append("each conflict needs ja + provenance")
                break
    ruling = line.get("ruling")
    if ruling is not None and not _valid_ruling(ruling):
        p.append("ruling must be {ruling: accept|reject, by, date}")
    for c in line.get("conflicts") or []:
        if isinstance(c, dict) and c.get("ruling") is not None and not _valid_ruling(c["ruling"]):
            p.append("conflict ruling must be {ruling: accept|reject, by, date}")
        if isinstance(c, dict) and isinstance(c.get("provenance"), dict):
            # a correction waits in `conflicts` until check promotes it, so validate it there too
            p += _provenance_problems(c["provenance"], "conflict provenance")
    return p
