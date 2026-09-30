-- UI/SubscriptionInterstitial.lua: the "subscribe" panel a trial account is shown on Forever (surface
-- "subscriptioninterstitial", area "ui", ADR-016). Blizzard_SubscriptionInterstitialUI is load-on-demand
-- (its TOC: LoadOnDemand 1); `camelot` loads it for trial and veteran-trial accounts when the player enters the
-- world (blizzard_game/mainline/eventimplementation.lua:829–831 → SubscriptionInterstitial_LoadUI,
-- blizzard_subscriptioninterstitialui_bootstrap.lua:1–3), and the frame shows itself on the
-- SHOW_SUBSCRIPTION_INTERSTITIAL event (blizzard_subscriptioninterstitialui.lua:112, 136–142). Set up through
-- WFJ.LoadOnDemand.when.
-- Every text is written once, by the XML or by an OnLoad (every widget is a parentKey):
--   SubscribeButton.FirstLine / SecondLine / ThirdLine / ButtonText (xml:72–103; three words stacked as one banner),
--   UpgradeButton.TitleLine / TitleSubText / ButtonText (xml:123–143), ClosePanelButton CLOSE (xml:166),
--   UpgradeButton's pooled bullet points: bulletPoint.Text = _G["SUBSCRIPTION_INTERSTITIAL_UPGRADE_BULLET" .. n]
--     (lua:73–84; bulletPointPool :71), walked from the pool and keyed by widget.
-- The labels are shown when the addon loads and again on the frame's OnShow. Their fonts are scaled to fit the
-- English once at load (ScaleTextToFit, lua:12, 47–58, 67–68): whether the Japanese fits is an in-game check.
local _, WFJ = ...
local SubscriptionInterstitial = {}
WFJ.SubscriptionInterstitial = SubscriptionInterstitial

local SURFACE = "subscriptioninterstitial"
SubscriptionInterstitial.SURFACE = SURFACE
local Compat = WFJ.Compat
local ADDON = "Blizzard_SubscriptionInterstitialUI"

local FRAME = "SubscriptionInterstitialFrame"

SubscriptionInterstitial.NEVER_TOUCH = {}

-- record key → { candidate, the one key it shows }
local STATIC = {
  first = { FRAME .. ".SubscribeButton.FirstLine", "SUBSCRIPTION_INTERSTITIAL_SUBSCRIBE_FIRST_LINE" },
  second = { FRAME .. ".SubscribeButton.SecondLine", "SUBSCRIPTION_INTERSTITIAL_SUBSCRIBE_SECOND_LINE" },
  third = { FRAME .. ".SubscribeButton.ThirdLine", "SUBSCRIPTION_INTERSTITIAL_SUBSCRIBE_THIRD_LINE" },
  subscribe = { FRAME .. ".SubscribeButton.ButtonText", "SUBSCRIPTION_INTERSTITIAL_SUBSCRIBE_BUTTON" },
  upgradeTitle = { FRAME .. ".UpgradeButton.TitleLine", "SUBSCRIPTION_INTERSTITIAL_UPGRADE_TITLE" },
  upgradeSubtext = { FRAME .. ".UpgradeButton.TitleSubText", "SUBSCRIPTION_INTERSTITIAL_UPGRADE_TITLE_SUBTEXT" },
  upgrade = { FRAME .. ".UpgradeButton.ButtonText", "SUBSCRIPTION_INTERSTITIAL_UPGRADE_BUTTON" },
  close = { FRAME .. ".ClosePanelButton", "CLOSE" },
}
local STATIC_ORDER = {}
for key in pairs(STATIC) do STATIC_ORDER[#STATIC_ORDER + 1] = key end
table.sort(STATIC_ORDER)

local BULLET = { only = {} }
for i = 1, 10 do BULLET.only[i] = "SUBSCRIPTION_INTERSTITIAL_UPGRADE_BULLET" .. i end -- MaximumBulletPoints (lua:1)

local function get(key) return Compat.get(SURFACE, key) end

local function declare()
  Compat.declare(SURFACE, "frame", { FRAME })
  Compat.declare(SURFACE, "upgradeButton", { FRAME .. ".UpgradeButton" })
  for key, s in pairs(STATIC) do Compat.declare(SURFACE, key, { s[1] }) end
end

local bulletKey = WFJ.Labels.keyer("bullet.") -- a pooled bullet point's record key: the widget, never its index

-- Every label of the panel as it is now. → the number of dictionary words found.
function SubscriptionInterstitial.show()
  local n = 0
  for _, key in ipairs(STATIC_ORDER) do
    n = n + WFJ.Labels.show(SURFACE, key, get(key), nil, { only = { STATIC[key][2] } })
  end
  local upgrade = get("upgradeButton")
  local pool = type(upgrade) == "table" and upgrade.bulletPointPool or nil
  if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
    for bullet in pool:EnumerateActive() do
      local text = type(bullet) == "table" and bullet.Text or nil
      if type(text) == "table" then n = n + WFJ.Labels.show(SURFACE, bulletKey(text), text, nil, BULLET) end
    end
  end
  WFJ.Render.updateBanner(SURFACE)
  return n
end

local hooked, waiting = false, false

-- Runs once Blizzard_SubscriptionInterstitialUI is loaded (now, or on its ADDON_LOADED). Declared again here: a
-- declare clears Compat's memo, which holds `false` for a name looked up before the addon loaded.
function SubscriptionInterstitial.setup()
  declare()
  local frame = get("frame")
  if hooked or type(frame) ~= "table" then return false end
  hooked = true
  if type(frame.HookScript) == "function" then frame:HookScript("OnShow", SubscriptionInterstitial.show) end
  SubscriptionInterstitial.show()
  return true
end

-- Called by Main after Compat.init, ButtonText.init and LoadOnDemand.init. → true when the panel is set up now.
function SubscriptionInterstitial.init()
  declare()
  if waiting then return false end
  waiting = true
  return WFJ.LoadOnDemand.when(ADDON, SubscriptionInterstitial.setup) and hooked
end
