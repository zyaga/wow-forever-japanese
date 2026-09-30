-- The trial account's subscribe panel on Forever: UI/SubscriptionInterstitial.lua over a
-- SubscriptionInterstitialFrame replayed from blizzard_subscriptioninterstitialui/blizzard_subscriptioninterstitialui
-- .xml (:72–166) and .lua (:71–84, the bullet point pool), load-on-demand in both load orders. A widget shows only
-- its own key.
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")

local UI = {
  SUBSCRIPTION_INTERSTITIAL_SUBSCRIBE_FIRST_LINE = { "CONTINUE", "続けて" },
  SUBSCRIPTION_INTERSTITIAL_SUBSCRIBE_BUTTON = { "Subscribe", "サブスクリプションに登録" },
  SUBSCRIPTION_INTERSTITIAL_UPGRADE_TITLE = { "UPGRADE NOW", "今すぐアップグレード" },
  SUBSCRIPTION_INTERSTITIAL_UPGRADE_BULLET1 = { "PLAY TO LEVEL 70", "レベル70までプレイ" },
  SUBSCRIPTION_INTERSTITIAL_UPGRADE_BULLET2 = { "UNLOCK ALL CLASSES", "すべてのクラスを解放" },
  CLOSE = { "Close", "閉じる" },
}

local function en(key) return _G[key] end

local function build()
  local frame = CreateFrame("Frame", "SubscriptionInterstitialFrame")
  C.tree(frame, { ["SubscribeButton.FirstLine"] = en("SUBSCRIPTION_INTERSTITIAL_SUBSCRIBE_FIRST_LINE"),
    ["SubscribeButton.ButtonText"] = en("SUBSCRIPTION_INTERSTITIAL_SUBSCRIBE_BUTTON"),
    ["UpgradeButton.TitleLine"] = en("SUBSCRIPTION_INTERSTITIAL_UPGRADE_TITLE"),
    ClosePanelButton = { button = en("CLOSE") } })
  local pool = C.pool(function() return { Text = Stub.fontString("") } end)
  frame.UpgradeButton.bulletPointPool = pool
  for i = 1, 2 do pool:Acquire().Text.text = en("SUBSCRIPTION_INTERSTITIAL_UPGRADE_BULLET" .. i) end
  return frame
end

C.suite(getfenv(1), {
  title = "the subscribe panel on Forever", module = "SubscriptionInterstitial",
  file = "UI/SubscriptionInterstitial.lua", addon = "Blizzard_SubscriptionInterstitialUI",
  root = "SubscriptionInterstitialFrame", ui = UI, build = build, globals = { "SubscriptionInterstitialFrame" },
  cases = {
    { "every line, the buttons and the pooled bullet points are Japanese; Alt shows English", function(frame, WFJ)
      frame:Show()
      assert.are.equal("続けて", frame.SubscribeButton.FirstLine:GetText())
      assert.are.equal("サブスクリプションに登録", frame.SubscribeButton.ButtonText:GetText())
      assert.are.equal("今すぐアップグレード", frame.UpgradeButton.TitleLine:GetText())
      assert.are.equal("閉じる", frame.ClosePanelButton:GetText())
      local texts = {}
      for bullet in frame.UpgradeButton.bulletPointPool:EnumerateActive() do
        texts[#texts + 1] = bullet.Text:GetText()
      end
      assert.are.same({ "レベル70までプレイ", "すべてのクラスを解放" }, texts)
      C.alt(WFJ, true)
      assert.are.equal("CONTINUE", frame.SubscribeButton.FirstLine:GetText())
      C.alt(WFJ, false)
    end },
  },
  name = function(frame, WFJ)
    -- a word that is not the widget's own key stays as the client wrote it
    frame.SubscribeButton.FirstLine.text = en("CLOSE")
    frame:Show()
    assert.are.equal("Close", frame.SubscribeButton.FirstLine:GetText())
    assert.is_true(C.unrecorded(WFJ, frame.SubscribeButton.FirstLine))
  end,
  wrong = function(frame)
    frame.UpgradeButton.bulletPointPool = "pool"
    frame.SubscribeButton.ButtonText = 3
    return function(f) assert.are.equal("続けて", f.SubscribeButton.FirstLine:GetText()) end
  end,
})
