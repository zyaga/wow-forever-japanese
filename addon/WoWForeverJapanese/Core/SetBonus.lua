-- Core/SetBonus.lua: an item tooltip's set bonus line ("Set: Increases your armor by 50.", "(3) Set: +4 Stamina.")
-- shown whole through the set spell's shipped Japanese, never half. Pure: no globals, no frames.
--   The compiled client prints each bonus as the description of the set's bonus spell, in threshold order, so the
--   k-th set line of a tooltip is the k-th spell of the item's set (Data/ItemSets.lua: item → set, set → spells with
--   their thresholds); a gray line's count is that spell's threshold. The spell's Japanese goes through the same
--   gate as a spell tooltip (the `preview` dependency: the Translator's align check over the live bonus text), so a
--   bonus whose numbers or names do not fit, or whose spell ships no Japanese, leaves the whole line English.
--   SetBonus.resolve(deps, itemId, position, text, threshold) → the bonus text's Japanese | nil
-- deps: { sets = WFJ.Data.itemSets, items = WFJ.Data.setItems, preview(spellId, text) → ja | nil }.
-- Consumers: UI/Tooltip (the structural pass), tooltip_set_bonus_spec.
local _, WFJ = ...
local SetBonus = {}
WFJ.SetBonus = SetBonus

-- The item's set bonuses, { spellId, threshold, … } in threshold order. → table | nil (no set, no map)
local function spells(deps, itemId)
  if type(deps) ~= "table" or type(deps.items) ~= "table" or type(deps.sets) ~= "table" then return nil end
  local set = deps.items[itemId]
  return set and deps.sets[set] or nil
end

function SetBonus.resolve(deps, itemId, position, text, threshold)
  local bonuses = spells(deps, itemId)
  if not bonuses or type(position) ~= "number" or type(text) ~= "string" or text == "" then return nil end
  local spell, wanted = bonuses[2 * position - 1], bonuses[2 * position]
  if spell == nil then return nil end
  if threshold ~= nil and wanted ~= threshold then return nil end
  if type(deps.preview) ~= "function" then return nil end
  local ja = deps.preview(spell, text)
  if type(ja) ~= "string" or ja == "" then return nil end
  return ja
end
