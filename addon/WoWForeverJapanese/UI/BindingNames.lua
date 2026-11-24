-- UI/BindingNames.lua: the names the Keybindings page shows for the addon's bindings (Bindings.xml), in the same
-- one language as the settings pages (UI/OptionsWidgets W.pick): Japanese, or English while English is what shows
-- or translation is off. The client reads each name from the global BINDING_NAME_<binding> when it draws the row
-- [verified: forever blizzard_settings_shared/blizzard_keybindings.lua:389–391, GetBindingName(action)], so the
-- globals are written again whenever the language changes. The section's name (BINDING_HEADER_WFJ, Core/Const) is
-- the addon's name and stays as it is.
local _, WFJ = ...
local Names = {}
WFJ.BindingNames = Names

local W, Text = WFJ.OptionsWidgets, WFJ.OptionsText

local function name(key)
  return W.pick(Text.get(key))
end

function Names.apply()
  BINDING_NAME_WFJ_TOGGLE = name("binding.toggle")
  BINDING_NAME_WFJ_REVEAL = name("binding.reveal")
  BINDING_NAME_WFJ_STUDY = name("binding.study")
  BINDING_NAME_WFJ_VOICE_PAUSE = name("binding.voicePause")
  BINDING_NAME_WFJ_VOICE_REPLAY = name("binding.voiceReplay")
  BINDING_NAME_WFJ_FREEZE_TOOLTIP = name("binding.freezeTooltip")
end

Names.apply()
-- wrapped: the events pass their new value, which apply does not take
WFJ.State.on("language", function() Names.apply() end)
WFJ.State.on("enabled", function() Names.apply() end)
