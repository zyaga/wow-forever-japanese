-- UI/VoicePanelLooks.lua: the voice panel's looks (trial), switched with /wfj panel look 1|2|3|4|5. Data only:
-- UI/VoicePanel lays the panel out from the chosen entry.
--   1  the client's own talking-head art: dark translucent text backdrop, the square portrait ring, gold name,
--      white text, 570 × 155 [verified: forever 1.60.1.70245 blizzard_framexml/talkingheadui.xml:4–10, 66–150;
--      talkingheadui.lua:116–126 (atlases, the "Normal" colours)]
--   2  parchment: the client's book page art (atlas QuestBG-Parchment) [verified: forever 1.60.1.70245
--      blizzard_uipanels_game/mainline/itemtextframe.xml], dark brown text
--   3  a strip: a small head, the name, one sentence, a plain dark band; nothing else
--   4  parchment in the client's talking-head art: the faction texture kits (TalkingHeads-Alliance / -Horde, else
--      -Neutral), as forever-vo shows it; the same frame as look 1, dark name and black text on the parchment
--      [verified: forever 1.60.1.70245 talkingheadui.lua:110–126 (the kit formats and their colours)]
--   5  look 3's strip on look 4's faction parchment (the text background stretched to the strip), dark text
-- Offsets are from the panel's TOPLEFT. `textLeft` is where name and text start with the head shown, `textLeftNoHead`
-- without it. The control row sits at the top right, so `nameRight` keeps the name clear of it.
local _, WFJ = ...

WFJ.VoicePanelLooks = {
  [1] = {
    width = 570, height = 155,
    bg = { atlas = "TalkingHeads-TextBackground", atlasSize = true },
    ring = { atlas = "TalkingHeads-Alliance-PortraitFrame", x = 5, y = -6 },
    portraitBg = { atlas = "TalkingHeads-PortraitBg" },
    model = { x = 21, y = -21, size = 115 },
    textLeft = 152, textLeftNoHead = 28, nameTop = -25, nameRight = -110, textRight = -42, textBottom = 18,
    nameFont = "Fancy22Font", titleFont = "GameFontNormal",
    nameColor = { 1, 0.82, 0.02 }, titleColor = { 0.85, 0.85, 0.85 }, textColor = { 1, 1, 1 }, shadow = true,
    textSize = 15, title = true,
  },
  [2] = {
    width = 540, height = 145,
    bg = { atlas = "QuestBG-Parchment", border = true },
    portraitBg = { atlas = "TalkingHeads-PortraitBg" },
    model = { x = 16, y = -18, size = 104 },
    textLeft = 134, textLeftNoHead = 22, nameTop = -16, nameRight = -110, textRight = -22, textBottom = 16,
    nameFont = "Fancy22Font", titleFont = "GameFontNormal",
    nameColor = { 0.33, 0.16, 0.02 }, titleColor = { 0.25, 0.15, 0.05 }, textColor = { 0.12, 0.08, 0.03 },
    shadow = false, textSize = 15, title = true,
  },
  [3] = {
    width = 520, height = 62,
    bg = { color = { 0, 0, 0, 0.55 } },
    model = { x = 5, y = -5, size = 52 },
    textLeft = 66, textLeftNoHead = 12, nameTop = -6, nameRight = -110, textRight = -12, textBottom = 4,
    nameFont = "GameFontNormal", titleFont = "GameFontNormalSmall",
    nameColor = { 1, 0.82, 0.02 }, titleColor = { 0.85, 0.85, 0.85 }, textColor = { 1, 1, 1 }, shadow = true,
    textSize = 13, title = false, maxLines = 2,
  },
  [4] = {
    width = 570, height = 155,
    kit = true, -- "%s" in an atlas is the player's faction kit, chosen when the look is applied
    bg = { atlas = "%s-TextBackground", atlasSize = true },
    ring = { atlas = "%s-PortraitFrame", x = 5, y = -6 },
    portraitBg = { atlas = "%s-PortraitBg" },
    model = { x = 21, y = -21, size = 115 },
    textLeft = 152, textLeftNoHead = 28, nameTop = -25, nameRight = -130, textRight = -42, textBottom = 18,
    nameFont = "Fancy22Font", titleFont = "GameFontNormal",
    kitNameColor = {
      ["TalkingHeads-Alliance"] = { 0.02, 0.17, 0.33 },
      ["TalkingHeads-Horde"] = { 0.28, 0.02, 0.02 },
      ["TalkingHeads-Neutral"] = { 0.33, 0.16, 0.02 },
    },
    nameColor = { 0.33, 0.16, 0.02 }, titleColor = { 0.25, 0.15, 0.05 }, textColor = { 0, 0, 0 }, shadow = false,
    textSize = 15, title = true,
  },
  [5] = {
    width = 520, height = 62,
    kit = true,
    bg = { atlas = "%s-TextBackground" }, -- stretched to the strip
    portraitBg = { atlas = "%s-PortraitBg" },
    model = { x = 6, y = -6, size = 50 },
    textLeft = 66, textLeftNoHead = 14, nameTop = -7, nameRight = -130, textRight = -14, textBottom = 4,
    nameFont = "GameFontNormal", titleFont = "GameFontNormalSmall",
    kitNameColor = {
      ["TalkingHeads-Alliance"] = { 0.02, 0.17, 0.33 },
      ["TalkingHeads-Horde"] = { 0.28, 0.02, 0.02 },
      ["TalkingHeads-Neutral"] = { 0.33, 0.16, 0.02 },
    },
    nameColor = { 0.33, 0.16, 0.02 }, titleColor = { 0.25, 0.15, 0.05 }, textColor = { 0, 0, 0 }, shadow = false,
    textSize = 13, title = false, maxLines = 2,
  },
}
