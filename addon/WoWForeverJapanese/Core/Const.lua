-- Core/Const.lua: constants shared across the addon. Core never touches a frame (lint-core-gate).
local ADDON, WFJ = ...
WFJ.ADDON = ADDON
WFJ.VERSION = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"
WFJ.NORM_VERSION = "v1"
WFJ.SCHEMA = 1

-- Translation areas (settings ids `area.<setting>` map onto these; surfaces ask State.areaEnabled(area)).
-- "ui": Blizzard's own interface words; "books": the book / letter / plaque window.
WFJ.AREAS = { "quests", "gossip", "items", "spells", "ui", "books" }

-- Marker messages: a short bilingual message, never a glyph, so it reads at a glance. A surface with a banner
-- FontString (the quest window: the stone band under the NPC name) shows them there in MARKER_COLOR; a surface
-- without one gets them inline, on their own line above prose or before a single-line title (UI/Render.lua).
-- Besides these two and the word card (UI/Readings), the addon adds nothing to the screen.
WFJ.MARKER = {
  stale = "[要更新 / English Changed]",
  missing = "[未翻訳 / Not Translated]",
}
WFJ.MARKER_COLOR = { r = 1, g = 0.82, b = 0 } -- gold, the client's own notice colour on its stone frames
WFJ.MARKER_INLINE_COLOR = "|cffffd100"

-- Generated-data layout (ADR-008; twin of pipeline/wfj/emit/schema.py, parity-tested in data_spec):
-- a row is positional: field slots, then one h1 (first 32 bits of the English hash) per field at slot+hash,
-- then the status string (one char per field: "." trusted · "s" stale · "u" unaligned · "m" not shipped).
-- The row's *key* is always the game id; slots never move without a schema bump.
WFJ.SLOTS = {
  -- female: offset to a field's female-variant h1 (slots 12..16), only on rows with gendered English
  quest = { fields = { "title", "objectives", "description", "progress", "completion" }, hash = 5, status = 11,
    female = 11 },
  item = { fields = { "description" }, hash = 1, status = 3 },
  -- `aura` is the buff / debuff wording of a spell, a different string from its tooltip
  -- `description` under the same id. Two fields, so the row is text,text,h1,h1,status.
  spell = { fields = { "description", "aura" }, hash = 2, status = 5 },
  ui = { fields = { "text" }, hash = 1, status = 3 }, -- keyed by global-string name / ItemSubClass:c:s
  -- An objective's own text, keyed by QuestObjective id; found by h1 (Core/Objectives.lua, ADR-031)
  objective = { fields = { "text" }, hash = 1, status = 3 },
  -- A quest's exploration / event objective text (quest cache), keyed by quest id; indexed with objective
  area = { fields = { "text" }, hash = 1, status = 3 },
}
for _, slots in pairs(WFJ.SLOTS) do
  slots.index = {}
  for i, f in ipairs(slots.fields) do slots.index[f] = i end
end
WFJ.STATUS = { ["."] = "trusted", s = "stale", u = "unaligned", m = "missing" }

-- Keybinding globals read by Bindings.xml (auto-loaded, not in the TOC).
BINDING_HEADER_WFJ = "WoW Forever Japanese"
BINDING_NAME_WFJ_TOGGLE = "Toggle translation"
-- Hidden (Bindings.xml hidden="true"); the name explains itself if a client lists it anyway (ADR-018).
BINDING_NAME_WFJ_REVEAL = "Hold to show English (set in WoW Forever Japanese settings)"
