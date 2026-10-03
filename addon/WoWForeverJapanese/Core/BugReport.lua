-- Core/BugReport.lua: the links the report window hands the player (docs/systems/fix-reports.md, "Bug and idea
-- reports"). A bug link opens the bug-report issue form with its fields filled through the URL: client build, addon
-- version and the addon's unsent Lua errors (Core/ErrorLog) as readable text. GitHub issue forms take a field's value
-- from a query parameter named by the field's id, as the collector send's `dump` field does. When the errors make the
-- link too long, the link fills build and version only and the window shows the error text to paste.
-- Pure: the caller passes build, version and the errors.
--   BugReport.pack(info) · info = { build, version, errors = ErrorLog.unsent(), ours = ErrorLog.ours() }
--     → { mode = "link" | "paste", url, text, count, ours, sent = { { msg, last, n }, … } }
--   BugReport.text(errors) → the readable error text
--   BugReport.IDEA_URL
local _, WFJ = ...
local BugReport = {}
WFJ.BugReport = BugReport

local REPO = "https://github.com/zyaga/wow-forever-japanese/issues/new?template="
BugReport.URL = REPO .. "bug-report.yml"
BugReport.IDEA_URL = REPO .. "idea.yml"
-- the form's field ids (.github/ISSUE_TEMPLATE/bug-report.yml)
BugReport.FIELDS = { build = "client-build", version = "addon-version", errors = "errors" }

-- Each error as a numbered block: how often and when, the message, the stack.
function BugReport.text(errors)
  local out = {}
  for i, e in ipairs(errors or {}) do
    local times = (e.n or 1) == 1 and "1 time" or ("%d times"):format(e.n)
    out[#out + 1] = ("%d) %s, first %s, last %s\n%s\n%s"):format(i, times, tostring(e.first or "?"),
      tostring(e.last or "?"), tostring(e.msg or ""), tostring(e.stack or ""))
  end
  return table.concat(out, "\n\n")
end

local function param(key, value)
  return "&" .. key .. "=" .. WFJ.CollectorSend.percentEncode(tostring(value))
end

function BugReport.pack(info)
  info = info or {}
  local errors = info.errors or {}
  local base = BugReport.URL .. param(BugReport.FIELDS.build, info.build or "?")
    .. param(BugReport.FIELDS.version, info.version or "?")
  local result = { mode = "link", url = base, text = "", count = #errors, ours = info.ours ~= false, sent = {} }
  if #errors == 0 then return result end
  for i, e in ipairs(errors) do result.sent[i] = { msg = e.msg, last = e.last, n = e.n } end
  result.text = BugReport.text(errors)
  local full = base .. param(BugReport.FIELDS.errors, result.text)
  -- the same new-issue link limit the collector send measured (Core/CollectorSend)
  if #full <= WFJ.CollectorSend.URL_BUDGET then
    result.url = full
  else
    result.mode = "paste"
  end
  return result
end
