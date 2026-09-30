-- A scripted play session for the Collector: the quest window (detail → progress → reward) with a quest
-- giver, a second quest's detail, an item tooltip and a spell tooltip, and two NPC talk windows sharing an option,
-- all through the real surfaces and the stub client.
-- Used by collector_spec (nothing personal) and collector_dump_spec (the round-trip fixture).
local Stub = require("tests.lua.spec.wow_stub")
local Session = {}

function Session.run()
  Stub.units.questnpc = { name = "Senani Thunderheart", guid = "Creature-0-4372-0-17-3100-0000A1B2C3" }
  Stub.quest = { id = 2, title = "Sharptalon's Claw",
    description = "Reyn, the hippogryph Sharptalon has been hunting near Splintertree Post.\n\nBring me its claw.",
    objectives = "Bring Sharptalon's Claw to Senani Thunderheart at Splintertree Post, Ashenvale.",
    progress = "Have you slain the beast, Reyn?",
    completion = "Reyn, your aim is true. The Hunter of the Night Elf is welcome." }
  Stub.showDetail()
  Stub.showProgress()
  Stub.showReward()
  QuestFrame:Hide()

  Stub.quest = { id = 9999, title = "A Forever Quest", description = "New text from the beta.",
    objectives = "Speak with the |cffffd200Keeper|r.", progress = "", completion = "" }
  Stub.showDetail()
  QuestFrame:Hide()

  Stub.setItemTooltip(_G.GameTooltip, "|Hitem:117:0:0:0:0:0:0:0|h[Tough Jerky]|h",
    { "Tough Jerky", "Use: Restores 61 health over 18 sec.", "", "Equip: Must remain seated while eating.",
      "Sell Price: 5c" })
  _G.GameTooltip:Hide()
  Stub.spellDescriptions[17] =
    "Draws on the soul of the friendly target to shield them, absorbing 44 damage. Lasts 30 sec."
  Stub.setSpellTooltip(_G.GameTooltip, 17, { "Power Word: Shield", "Rank 1",
    "Draws on the soul of the friendly target to shield them, absorbing 44 damage. Lasts 30 sec." })
  _G.GameTooltip:Hide()

  Stub.showGossip({ text = "Welcome to the Lion's Pride, Reyn. Even a hunter needs a warm bed.",
    options = { "Make this inn your home.", "Goodbye." },
    npc = { name = "Innkeeper Farley", guid = "Creature-0-4372-0-17-295-0000A1B2C3" } })
  Stub.closeGossip()
  Stub.showGossip({ text = "Keep your blade sharp.", options = { "Goodbye." },
    npc = { name = "Stormwind City Guard", guid = "Creature-0-4372-0-17-68-0000D4E5F6" } })
  Stub.closeGossip()
end

return Session
