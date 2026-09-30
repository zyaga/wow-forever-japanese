-- Report window: UI/ReportFrame.lua over ReportFrame replayed from camelot blizzard_reportframeshared
-- (reportframeshared.xml:69–191, reportframeshared.lua:15, 125–127, 154–199, 278–294, 353–362). The reported
-- player's name stays English.
local S = require("tests.lua.spec.stub_camelot_social")
local Stub = require("tests.lua.spec.wow_stub")

local FILES = S.files("UI/ReportFrame.lua")

local UI = {
  BEHAVIORAL_DETAILS_TITLE_BAR = { "WoW Customer Support", "WoWカスタマーサポート" },
  ERR_REPORT_SUBMITTED_SUCCESSFULLY = { "Thank you for your report!", "ご報告ありがとうございます!" },
  REPORTING_REPORT_PLAYER = { "Report %s", "%sを報告" }, REPORTING_REPORT_REASON = { "Select a Reason", "理由を選択" },
  REPORTING_REPORT = { "Report", "報告" }, REPORTING_MAKE_SELECTION = { "Make a Selection", "選択してください" },
  REPORTING_REPORT_DETAILS = { "Provide Details (Select all that apply)", "詳細 (該当するものをすべて選択)" },
  REPORTING_COMMENT_INSTRUCTIONS = { "More details about your report (optional)", "報告の詳細 (任意)" },
  REPORTING_MAJOR_CATEGORY_CHEATING = { "Cheating", "不正行為" },
  REPORTING_MINOR_CATEGORY_HACKING = { "Hacking", "ハッキング" }, REPORTING_MINOR_CATEGORY_BOTTING = { "Botting", "ボット" },
  HARMFUL_TO_MINORS_DISABLED_TOOLTIP = { "Must select one or more of the available Name options",
    "名前の選択肢を1つ以上選んでください" },
  CLOSE = { "Close", "閉じる" },
}
-- Core/UIStrings: the player's name, kept as written
local NEEDS = { ARGS = { REPORTING_REPORT_PLAYER = { [1] = "text" } } }

local function install(o)
  o = o or {}
  local en = S.en
  local frame = S.frame("ReportFrame")
  frame.TitleText = S.fs(en("BEHAVIORAL_DETAILS_TITLE_BAR"))
  frame.ThankYouText = S.fs(en("ERR_REPORT_SUBMITTED_SUCCESSFULLY"))
  frame.ReportString, frame.MinorReportDescription = S.fs(""), S.fs(en("REPORTING_REPORT_DETAILS"))
  frame.ReportButton = S.button(nil, en("REPORTING_REPORT"))
  local dropdown = S.dropdown("ReportingMajorCategoryDropdown")
  if o.noUpdateText then dropdown.UpdateText = nil else dropdown:SetDefaultText(en("REPORTING_MAKE_SELECTION")) end
  dropdown.Label = S.fs(en("REPORTING_REPORT_REASON"))
  frame.ReportingMajorCategoryDropdown = dropdown
  frame.Comment = { EditBox = CreateFrame("EditBox") }
  frame.Comment.EditBox.Instructions = S.fs(en("REPORTING_COMMENT_INSTRUCTIONS"))
  frame.MinorCategoryButtonPool = S.pool(function() return { Text = S.fs("") } end)
  function frame.InitiateReportInternal(self, _, playerName)
    self.ReportString.text = en("REPORTING_REPORT_PLAYER"):format(playerName)
  end
  function frame.MajorTypeSelected(self, _, minors)
    self.MinorCategoryButtonPool:ReleaseAll()
    for _, key in ipairs(minors) do self.MinorCategoryButtonPool:Acquire().Text.text = en(key) end
  end
end

describe("the report window on Forever", function()
  local WFJ
  before_each(function() WFJ = S.load(FILES, UI, NEEDS) end)
  after_each(function() S.teardown({ "ReportFrame" }) end)

  it("static labels and the reason dropdown's text are Japanese; Alt shows English", function()
    install()
    assert.is_true(WFJ.ReportFrame.init())
    local frame = _G.ReportFrame
    assert.are.equal("WoWカスタマーサポート", frame.TitleText:GetText())
    assert.are.equal("ご報告ありがとうございます!", frame.ThankYouText:GetText())
    assert.are.equal("理由を選択", frame.ReportingMajorCategoryDropdown.Label:GetText())
    assert.are.equal("報告", frame.ReportButton:GetText())
    assert.are.equal("報告の詳細 (任意)", frame.Comment.EditBox.Instructions:GetText())
    assert.are.equal("選択してください", frame.ReportingMajorCategoryDropdown.Text:GetText())
    frame.ReportingMajorCategoryDropdown:SetSelectionText("Cheating")
    assert.are.equal("不正行為", frame.ReportingMajorCategoryDropdown.Text:GetText())
    S.alt(WFJ, true)
    assert.are.equal("Cheating", frame.ReportingMajorCategoryDropdown.Text:GetText())
    S.alt(WFJ, false)
  end)

  it("a report names the player as written; the pooled minor categories translate on reuse", function()
    install()
    WFJ.ReportFrame.init()
    local frame = _G.ReportFrame
    frame:InitiateReportInternal(nil, "Close")
    assert.are.equal("Closeを報告", frame.ReportString:GetText())
    frame:MajorTypeSelected(nil, { "REPORTING_MINOR_CATEGORY_HACKING", "REPORTING_MINOR_CATEGORY_BOTTING" })
    local pool = frame.MinorCategoryButtonPool
    assert.are.equal("ハッキング", pool.active[1].Text:GetText())
    assert.are.equal("ボット", pool.active[2].Text:GetText())
    frame:MajorTypeSelected(nil, { "REPORTING_MINOR_CATEGORY_BOTTING" })
    assert.are.equal("ボット", pool.active[1].Text:GetText())
    assert.are.same({ "名前の選択肢を1つ以上選んでください" },
      S.tooltip(pool.active[1], { S.en("HARMFUL_TO_MINORS_DISABLED_TOOLTIP") }))
    assert.are.same({ "選択してください" }, S.tooltip(frame.ReportButton, { "Make a Selection" }))
    assert.are.same({ "Close" }, S.tooltip(frame.ReportButton, { "Close" }))
  end)

  it("a client name bound to the wrong type degrades to English with no error", function()
    install()
    local frame = _G.ReportFrame
    frame.MinorCategoryButtonPool, frame.ReportButton, frame.InitiateReportInternal = "?", 4, true
    frame.ReportingMajorCategoryDropdown.Text = "?"
    assert.has_no.errors(function() assert.is_true(WFJ.ReportFrame.init()) end)
    assert.has_no.errors(function() WFJ.ReportFrame.onMajorType() end)
    assert.are.equal("理由を選択", frame.ReportingMajorCategoryDropdown.Label:GetText())
  end)

  it("hooks install once; without the Menu-style report window init returns false and touches nothing", function()
    assert.is_false(WFJ.ReportFrame.init())
    install({ noUpdateText = true })
    assert.is_false(WFJ.ReportFrame.init())
    assert.are.equal("Report", _G.ReportFrame.ReportButton:GetText())
    install()
    assert.is_true(WFJ.ReportFrame.init())
    assert.is_false(WFJ.ReportFrame.init())
    assert.are.equal(1, #Stub.hooks["ReportFrame:MajorTypeSelected"])
  end)
end)
