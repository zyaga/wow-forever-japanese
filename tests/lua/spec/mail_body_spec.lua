-- ADR-042: the open letter's body, UI/Mail.lua over Forever's Blizzard_MailFrame (stub_mail.lua, M.installCamelot).
-- OpenMailFrame:Update writes OpenMailBodyText:SetText(GetInboxText(id), true) (mailframe.lua:776–777), a SimpleHTML
-- with no GetText. A letter that is a MailBody row (MailTemplate.Body_lang) shows its Japanese; the server sent it with
-- `$N` filled with the player's name and `$B` as line breaks, and the Japanese gets the name back. A letter a player
-- wrote is never touched.
local H = require("tests.lua.spec.helpers")
local Stub = require("tests.lua.spec.wow_stub")
local MailStub = require("tests.lua.spec.stub_mail")

local FILES = {}
for i, f in ipairs(H.UI_FILES) do FILES[i] = f end
FILES[#FILES + 1] = "Core/Placeholders.lua"
FILES[#FILES + 1] = "UI/Mail.lua"

local GREETING = "Ho Ho Hello, $N!  I hope you have a fantastic Feast of Winter Veil!$B$BSeasons Greetings...$B"
  .. "Greatfather Winter"
local THANKS = "Greetings, my friend!$B$BMay Zanza always bless you!$BVinchaxa"
local SHORT = "Well met, $n.$BTake this."

-- client-table rows (fingerprints: no global); the English as the table stores it, tokens and all
local UI = {
  ["MailBody:102"] = { GREETING, "ほっほー、{name}！\n\n冬のヴェール祭をお楽しみください！\n\n季節のご挨拶を…\nグレートファーザー・ウィンター" },
  ["MailBody:109"] = { THANKS, "ごきげんよう、友よ！\n\nザンザの祝福があらんことを！\nヴィンチャクサ" },
  ["MailBody:200"] = { SHORT, "よく来た、{name}。\nこれを受け取れ。" },
  ["CurrencyCategory:9"] = { "Close", "その他" }, -- another family: never a letter body
  CLOSE = { "Close", "閉じる" },
}

-- what GetInboxText returns for a template letter: the tokens filled in by the server
local function served(template, name)
  return (template:gsub("%$[Nn]", name):gsub("%$[Bb]", "\n"))
end

describe("the open letter's body on Forever", function()
  local WFJ

  local function alt(down)
    Stub.keys.alt = down
    WFJ.Modifier.refresh()
  end

  local function html() return _G.OpenMailBodyText end

  local function open(text)
    MailStub.letter = { sender = "Greatfather Winter", subject = "Happy Winter Veil", body = text, items = 0,
      money = 0, canDelete = true }
    MailStub.camelotOpenLetter()
    return html().text
  end

  before_each(function()
    Stub.install(H.ADDON_DIR .. "/WoWForeverJapanese.toc")
    Stub.installTooltipAPI()
    MailStub.installCamelot()
    -- the SimpleHTML as the client has it: SetText(text, ignoreMarkup), a font per text type, no GetText
    local b = html()
    b.GetText, b.fonts, b.writes = nil, { P = { "Fonts\\FRIZQT__.TTF", 12, "" } }, {}
    function b.SetText(self, text, ignoreMarkup)
      self.text = text
      self.writes[#self.writes + 1] = { text, ignoreMarkup }
    end
    function b.GetFont(self, tag) local f = self.fonts[tag]; return f[1], f[2], f[3] end
    function b.SetFont(self, tag, path, size, flags) self.fonts[tag] = { path, size, flags } end
    local update = _G.OpenMailFrame.Update
    function _G.OpenMailFrame.Update(self) -- mailframe.lua:776–777, after the stub's other writes
      update(self)
      _G.OpenMailBodyText:SetText(MailStub.letter.body or "", true)
    end
    WFJ = H.loadChunks(FILES)
    H.uiSetup(WFJ, UI, { expand = function(ja)
      return (WFJ.Placeholders.expand(ja, { name = _G.UnitName("player") }))
    end })
    assert.is_true(WFJ.Mail.init())
  end)

  after_each(function()
    H.uiTeardown()
    Stub.keys.alt = false
  end)

  it("a template letter with the player's name and line breaks shows its row's Japanese with the name back", function()
    local en = served(GREETING, "Reyn")
    assert.are.equal("ほっほー、Reyn！\n\n冬のヴェール祭をお楽しみください！\n\n季節のご挨拶を…\nグレートファーザー・ウィンター",
      open(en))
    local last = html().writes[#html().writes]
    assert.is_true(last[2]) -- the client's call shape: SetText(text, true)
    assert.are.equal(WFJ.Font.PATH, (html():GetFont("P")))
    alt(true)
    assert.are.equal(en, html().text)
    assert.is_true(html().writes[#html().writes][2])
    alt(false)
    assert.are.equal("ほっほー、Reyn！\n\n冬のヴェール祭をお楽しみください！\n\n季節のご挨拶を…\nグレートファーザー・ウィンター",
      html().text)
  end)

  it("a letter with no name token and a lowercase $n with a short name match too", function()
    assert.are.equal("ごきげんよう、友よ！\n\nザンザの祝福があらんことを！\nヴィンチャクサ", open(served(THANKS, "Reyn")))
    _G.UnitName = function() return "Bo" end
    WFJ.Compat.declare("mail", "unitName", { "UnitName" }) -- forget the name function Compat resolved at init
    assert.are.equal("よく来た、Bo。\nこれを受け取れ。", open(served(SHORT, "Bo")))
  end)

  it("a letter a player wrote, another family's word, a dictionary word and another player's name stay as written",
    function()
      for _, text in ipairs({ "Thanks for the help yesterday, see you in Ironforge!", "Close",
        served(GREETING, "Anduin") }) do
        assert.are.equal(text, open(text))
        assert.is_nil(WFJ.SurfaceState.get("mail", "body"))
      end
      assert.is_nil(WFJ.UIIndex:match(served(THANKS, "Reyn"))) -- the family only where the body names it
    end)

  it("the next letter replaces the Japanese; the master switch puts the English back", function()
    open(served(THANKS, "Reyn"))
    local mine = "Meet me at the bank."
    assert.are.equal(mine, open(mine))
    assert.are.equal("ごきげんよう、友よ！\n\nザンザの祝福があらんことを！\nヴィンチャクサ", open(served(THANKS, "Reyn")))
    WFJ.Settings.set("area.interface", false)
    assert.are.equal(served(THANKS, "Reyn"), html().text)
    WFJ.Settings.set("area.interface", true)
    assert.are.equal("ごきげんよう、友よ！\n\nザンザの祝福があらんことを！\nヴィンチャクサ", html().text)
  end)

  it("the body is not a never-touch widget; a client without the SimpleHTML is skipped without error", function()
    for _, path in ipairs(WFJ.Mail.NEVER_TOUCH) do assert.are_not.equal("OpenMailBodyText", path) end
    WFJ.Mail.body.html = nil
    assert.are.equal(0, WFJ.Mail.showBody())
  end)
end)
