"""The generated-data layout; `Core/Const.lua` in the addon is the hand-written twin (parity-tested).

Row shape (docs/architecture/data-model.md, ADR-008):
  quest:  { title, objectives, description, progress, completion, h1×5, "<status chars>"[, h1f×5] }
          h1f×5: the female-variant h1 per field, only on a row where some field's English has $G
  item / spell: { description, h1, "<status char>"[, values] }   (spell: two fields, so two of each)
          values: per field, how many numbers the client prints for the English the Japanese is numbered
          to; only on a row where some field's Japanese is filled from the live line (`$N<k>` / `$D<k>`)
  objective: { text, h1, "<status char>" }   keyed by QuestObjective id, found in the addon by h1
  area:   { text, h1, "<status char>" }   keyed by quest id, found in the addon by h1 with objectives
  gossip: ["<16 hex key>"] = { text, "<status char>" }
  book:   ["<16 hex english.hash>"] = { text, "." }    keyed by the English it was checked against
  ui:     ["<global-string name | ItemSubClass:c:s | SpellItemEnchantment:id | SpellSubtext:id
           | <family>:id>"]
          = { text, h1, "<status char>" }   (the last form: the client-table text families)
`hash` is the offset added to a field's slot to reach its h1 slot; `status` is the status-string slot;
`female` (quest only) is the offset to its h1f slot; `values` (item / spell only) the offset to its count.
"""

from __future__ import annotations

from wfj.core.model import FIELDS, SHARD_WIDTH

STATUS_CHAR: dict[str, str] = {"trusted": ".", "stale": "s", "unaligned": "u"}
MISSING = "m"

def _flat(type_: str, *, values: bool = False) -> dict:
    """A type with no female slot: text per field, then h1 per field, then the one status string. With
    `values`, a count per field may follow the status string."""
    fields = list(FIELDS[type_])
    slots = {"fields": fields, "hash": len(fields), "status": 2 * len(fields) + 1}
    if values:
        slots["values"] = 2 * len(fields) + 1
    return slots


SLOTS: dict[str, dict] = {
    "quest": {
        "fields": list(FIELDS["quest"]),
        "hash": len(FIELDS["quest"]),
        "status": 2 * len(FIELDS["quest"]) + 1,
        "female": 2 * len(FIELDS["quest"]) + 1,
    },
    # `hash` is the offset from a field's text slot to its h1; `status` the one string after them all.
    # Derived, not written out, so a type that gains a field (spell's `aura`) cannot be left with a
    # stale layout; `Core/Const.lua` is the hand-written twin and `test_generate` checks the two agree.
    "item": _flat("item", values=True),
    "spell": _flat("spell", values=True),
    "ui": _flat("ui"),
    "objective": _flat("objective"),
    "area": _flat("area"),
}
GOSSIP_FIELD = FIELDS["gossip"][0]

# numeric-id types, shard by id range
TYPES = ("quest", "item", "spell", "objective", "area")
# Keyed by a 16-hex English hash, sharded by its first two hex chars (gossip and book pages). A book
# is keyed in data/ by its page id but in the addon by its English hash: the client exposes no page id.
KEYED_TYPES = ("gossip", "book")
FILE_PREFIX = {
    "quest": "Quest",
    "item": "Item",
    "spell": "Spell",
    "objective": "Objective",
    "area": "Area",
    "gossip": "Gossip",
    "book": "Book",
    "ui": "UI",
    "reading": "Reading",  # whole-word readings, Reading_<type>_<shard>.lua (not a translation type)
    "gloss": "Gloss",  # the word popup's meanings, Gloss_<NNNN>.lua (not a translation type)
    # English word cards: English_<type>_<shard>.lua beside each reading shard, and the two word tables
    "english": "English",
    # the chat word lists: Chat_ja_<NN>.lua and Chat_en_<NN>.lua from the readings, Chat_list.lua from
    # data/chat/
    "chat": "Chat",
    # how often each word is used: Freq_ja_<NN>.lua and Freq_en_<NN>.lua from the readings, Freq_grammar.lua from
    # pipeline/grammar_words.txt
    "freq": "Freq",
}
# Generated types in TOC load order: numeric-id shards, the keyed types, then the UI strings.
# An English source that may legitimately hold SEVERAL versions at once, because more than one client
# serves it and they serve different subsets. Only the client quest cache: Forever's server answers under a
# third of the quest ids Classic Era's did (content Forever has not enabled), so a union import keeps both
# builds' lines and `wdb` is pinned at two versions on purpose (ADR-020). Every other source is one thing at
# one version (pfQuest is a repo at a commit, VMaNGOS a database snapshot), and two versions there means a
# half-run import, which `generate` still refuses. `db2` joins it for the same reason: the next Forever
# build's union import keeps the lines that build no longer provides at the build that did (that is what
# `stats --unseen-since` reads), so `db2@1.60.1…` and `db2@<next>` co-exist by design, and refusing them
# would make the next build a manual job.
# `wago` likewise: `MERGE=union` is the Makefile default and `TABLES_SRC=wago` too, so a `WAGO_BUILD` bump
# keeps the rows the new build dropped at the old one; refusing them would block the build with no import
# able to clear it.
# the collector records what the client showed at the build it ran on; dumps add up across builds (ADR-053)
MULTI_VERSION_SOURCES = frozenset({"wdb", "db2", "wago", "collector"})
GENERATED_TYPES = (*TYPES, *KEYED_TYPES, "ui")
# TOC load order: the translation types, then the readings (a reading row is only ever read after
# its translation, and loads nothing the translation shards need),
# then the meanings (a meaning is only read for a word a reading row points at).
# The English word card rows load before them: a row is only read on a hover, after everything has loaded.
# The chat word lists load last: a row is only read with the mouse on a chat line.
TOC_ORDER = (*GENERATED_TYPES, "english", "reading", "gloss", "chat", "freq")

TOC_BEGIN = "# <<< generated by wfj generate. Do not edit between the markers; wfj validate diffs this block."
TOC_END = "# >>>"


def shard_of(id_: int) -> int:
    return id_ // SHARD_WIDTH


def reading_relpath(type_: str, shard: int | str) -> str:
    """`Data/Reading/Reading_quest_0000.lua` / `Data/Reading/Reading_gossip_ab.lua`: one file per
    shard of the translation type it annotates."""
    name = f"{type_}_{shard:04d}" if isinstance(shard, int) else f"{type_}_{shard}"
    return f"Data/Reading/Reading_{name}.lua"


def english_relpath(type_: str, shard: int | str) -> str:
    """`Data/English/English_quest_0000.lua`: the English word card rows of one reading shard."""
    name = f"{type_}_{shard:04d}" if isinstance(shard, int) else f"{type_}_{shard}"
    return f"Data/English/English_{name}.lua"


ENGLISH_PRON = "Data/English/English_Pron.lua"  # how each English word on a card is said
ENGLISH_COMMON = "Data/English/English_Common.lua"  # everyday English words with a Japanese word each


CHAT_LIST = "Data/Chat/Chat_list.lua"  # the hand-written chat words and the phrase book's phrases


def chat_relpath(language: str, shard: int) -> str:
    """`Data/Chat/Chat_ja_00.lua` / `Data/Chat/Chat_en_00.lua`: one file of a general chat word list."""
    return f"Data/Chat/Chat_{language}_{shard:02d}.lua"


FREQ_GRAMMAR = "Data/Freq/Freq_grammar.lua"  # the words that start as Ignored


def freq_relpath(language: str, shard: int) -> str:
    """`Data/Freq/Freq_ja_00.lua` / `Data/Freq/Freq_en_00.lua`: one file of a word frequency list."""
    return f"Data/Freq/Freq_{language}_{shard:02d}.lua"


def gloss_relpath(shard: int) -> str:
    """`Data/Gloss/Gloss_0000.lua`: meanings 1000 × shard + 1 … 1000 × shard + 1000."""
    return f"Data/Gloss/Gloss_{shard:04d}.lua"


def shard_relpath(type_: str, nnnn: int | str) -> str:
    """`Data/Quest/Quest_0007.lua` (numeric ids), `Data/Gossip/Gossip_ab.lua` (a keyed type: first two hex
    chars) or `Data/UI/UI_A.lua` (the key's first character, upper-cased)."""
    prefix = FILE_PREFIX[type_]
    name = f"{prefix}_{nnnn:04d}" if isinstance(nnnn, int) else f"{prefix}_{nnnn}"
    return f"Data/{prefix}/{name}.lua"
