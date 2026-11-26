-- UI/ChatLines: which chat line the mouse is on, and the lines it never names.
local Env = require("tests.lua.spec.chat_env")

local SAID = "|Hplayer:Taro:12:SAY|h[Taro]|h says: 今日はダンジョンに行きませんか"

describe("the chat line under the mouse", function()
  local Lines, line, named

  before_each(function()
    local WFJ = Env.setup()
    Lines = WFJ.ChatLines
    line = Env.chatFrame({ { SAID, Env.SAY } }).visibleLines[1]
    line.over = true
    named = nil
    Lines.onLine(function(_, l) named = l end)
  end)
  after_each(Env.teardown)

  -- a value the client keeps from addons: it may be passed on, never tested or compared
  local function kept()
    local v = {}
    Env.secrets[v] = true
    return v
  end

  it("names the visible line the mouse is on", function()
    assert.equals(line, Lines.look())
    assert.equals(line, named)
  end)

  it("names no line that has faded out or that the mouse is not on", function()
    line.alpha = 0.1
    assert.is_nil(Lines.look())
    line.alpha, line.over = 1, false
    assert.is_nil(Lines.look())
  end)

  it("names no line whose text the client keeps secret", function()
    Env.secrets[SAID] = true
    assert.is_nil(Lines.look())
  end)

  it("names no line that answers whether it shows, how faint it is or where the mouse is with a secret", function()
    for _, method in ipairs({ "IsVisible", "GetAlpha", "IsMouseOver" }) do
      local answer, was = kept(), line[method]
      line[method] = function() return answer end
      assert.is_nil(Lines.look(), method)
      line[method] = was
    end
    assert.equals(line, Lines.look())
  end)
end)
