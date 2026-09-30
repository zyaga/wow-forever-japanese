-- UI/GuildControl.lua over a GuildControlUI replayed from camelot
-- blizzard_guildcontrolui/blizzard_guildcontrolui.xml (:4–300, :402–810) and .lua (OnLoad :88–116, the pane updates
-- :154–247, :412–470, :527–607), load-on-demand in both load orders. Rank and bank tab names stay English.
local Stub = require("tests.lua.spec.wow_stub")
local C = require("tests.lua.spec.stub_commerce")

local UI = {
  GUILDCONTROL = { "Guild Control", "ギルド管理" }, GUILD_NEW_RANK = { "New Rank", "新しいランク" },
  GUILDCONTROL_OPTION5 = { "Invite Member", "メンバーを招待" }, GUILD_BANK = { "Guild Bank", "ギルド銀行" },
  GUILDCONTROL_OPTION18 = { "Requires Authenticator", "認証システムが必要" },
  GUILDCONTROL_SELECTRANK = { "Rank to modify:", "変更するランク:" },
  GUILDCONTROL_VIEW_TAB = { "View Tab", "タブを見る" }, BANKSLOTPURCHASE = { "Purchase", "購入" },
  GUILDCONTROL_GUILDRANKS = { "Guild Ranks", "ギルドランク" },
  GUILD_RAISERANK_BUTTON_TOOLTIP = { "Click to raise this rank", "クリックでこのランクを上げる" },
  ERR_GUILD_RANK_IN_USE = { "That guild rank is currently in use.", "そのギルドランクは使用中です。" },
  -- the officer permission lines and the Discord pane's name-carrying lines
  GUILD_OFFICER_PERMISSION_ACCESS_CHANNELS = { "- Access officer channels", "- オフィサーチャンネルを利用" },
  GUILD_OFFICER_PERMISSION_MOTD = { "- Edit Message of the Day", "- 今日のメッセージを編集" },
  DISCORD_GUILD_LINKED_SERVER = { "Server: %s", "サーバー: %s" },
  DISCORD_VALID_SERVER_CHANNEL_LIST = { "Channels for server %s:", "サーバー%sのチャンネル:" },
}
local PERMS = "- Access officer channels|n- Edit Message of the Day"
local P = "GuildControlUIRankSettingsFrame"
local GLOBALS = { "GuildControlUI", "GuildControlUITitle", P .. "Checkbox5Text", P .. "Checkbox18Text",
  P .. "BankLabel", "GuildControlUIRankOrderFrameRank1", "GuildControlBankTab1", "DiscordLinkFrame",
  "GuildControlUI_RankOrder_Update", "GuildControlUI_BankTabPermissions_Update" }

local function en(key) return _G[key] end

local function build()
  local frame = CreateFrame("Frame", "GuildControlUI")
  Stub.namedFontString("GuildControlUITitle", en("GUILDCONTROL"))
  Stub.namedFontString(P .. "Checkbox5Text", en("GUILDCONTROL_OPTION5"))
  Stub.namedFontString(P .. "Checkbox18Text", en("GUILDCONTROL_OPTION18"))
  Stub.namedFontString(P .. "BankLabel", en("GUILD_BANK"))
  C.tree(frame, { ["orderFrame.newButton"] = { button = en("GUILD_NEW_RANK") }, ["dropdown.Text"] = "",
    ["rankPermFrame.dropdown.Text"] = "Guild Bank" }) -- a rank named like a dictionary word
  frame.rankPermFrame.dropdown:addRegion(Stub.fontString(en("GUILDCONTROL_SELECTRANK")))
  frame.rankPermFrame.OfficerPermissions = Stub.fontString(PERMS) -- GuildControlRankSettings_OnLoad (lua:511–512)
  frame.discordFrame = CreateFrame("Frame")
  frame.discordFrame.channelListTitle = Stub.fontString("Channels for server Guild Bank:") -- a server named so
  local link = CreateFrame("Frame", "DiscordLinkFrame")
  link.linkedServer = Stub.fontString("Server: Guild Bank")
  function frame.dropdown.UpdateText(self) self.Text.text = en("GUILDCONTROL_GUILDRANKS") end
  -- rows are created by the pane updates, as the client does
  _G.GuildControlUI_RankOrder_Update = function()
    local row = _G.GuildControlUIRankOrderFrameRank1 or CreateFrame("Frame", "GuildControlUIRankOrderFrameRank1")
    row.upButton, row.downButton, row.deleteButton = Stub.button(nil, ""), Stub.button(nil, ""), Stub.button(nil, "")
  end
  _G.GuildControlUI_BankTabPermissions_Update = function()
    local row = CreateFrame("Frame", "GuildControlBankTab1")
    C.tree(row, { ["owned.tabName"] = "Purchase", ["owned.viewCB.text"] = en("GUILDCONTROL_VIEW_TAB"),
      ["buy.button"] = { button = en("BANKSLOTPURCHASE") } })
  end
  return frame
end

C.suite(getfenv(1), {
  title = "guild control on Forever", module = "GuildControl", file = "UI/GuildControl.lua",
  addon = "Blizzard_GuildControlUI", root = "GuildControlUI", ui = UI, build = build, globals = GLOBALS,
  cases = {
    { "the title, buttons, permission checkboxes and the unnamed rank label are Japanese; hide releases them",
      function(frame, WFJ)
        frame:Show()
        assert.are.equal("ギルド管理", _G.GuildControlUITitle:GetText())
        assert.are.equal("新しいランク", frame.orderFrame.newButton:GetText())
        assert.are.equal("メンバーを招待", _G[P .. "Checkbox5Text"]:GetText())
        assert.are.equal("認証システムが必要", _G[P .. "Checkbox18Text"]:GetText())
        assert.are.equal("ギルド銀行", _G[P .. "BankLabel"]:GetText())
        local _, label = frame.rankPermFrame.dropdown:GetRegions()
        assert.are.equal("変更するランク:", (label or frame.rankPermFrame.dropdown:GetRegions()):GetText())
        C.alt(WFJ, true)
        assert.are.equal("Guild Control", _G.GuildControlUITitle:GetText())
        C.alt(WFJ, false)
        frame:Hide()
        assert.are.equal("New Rank", frame.orderFrame.newButton:GetText())
      end },
    { "lineList: the officer permission lines in Japanese, rejoined; one unknown line keeps it all English",
      function(frame, WFJ)
        frame:Show()
        local fs = frame.rankPermFrame.OfficerPermissions
        assert.are.equal("- オフィサーチャンネルを利用|n- 今日のメッセージを編集", fs:GetText())
        C.alt(WFJ, true)
        assert.are.equal(PERMS, fs:GetText())
        C.alt(WFJ, false)
        frame:Hide()
        fs.text = PERMS .. "|n- Something new"
        frame:Show()
        assert.are.equal(PERMS .. "|n- Something new", fs:GetText())
      end },
    { "the Discord server / channel lines in Japanese with the names kept", function(frame)
      frame:Show()
      assert.are.equal("サーバー: Guild Bank", _G.DiscordLinkFrame.linkedServer:GetText())
      assert.are.equal("サーバーGuild Bankのチャンネル:", frame.discordFrame.channelListTitle:GetText())
    end },
    { "the navigation dropdown's own text follows its writer", function(frame)
      frame:Show()
      frame.dropdown:UpdateText()
      assert.are.equal("ギルドランク", frame.dropdown.Text:GetText())
    end },
    { "rows created by a pane update: bank tab labels translate, rank buttons own their tooltips", function(frame)
      frame:Show()
      _G.GuildControlUI_BankTabPermissions_Update()
      local row = _G.GuildControlBankTab1
      assert.are.equal("タブを見る", row.owned.viewCB.text:GetText())
      assert.are.equal("購入", row.buy.button:GetText())
      assert.are.equal("Purchase", row.owned.tabName:GetText()) -- a tab named "Purchase"
      _G.GuildControlUI_RankOrder_Update()
      C.tooltip(_G.GuildControlUIRankOrderFrameRank1.upButton,
        { en("GUILD_RAISERANK_BUTTON_TOOLTIP"), en("ERR_GUILD_RANK_IN_USE") })
      assert.are.equal("クリックでこのランクを上げる", _G.GameTooltipTextLeft1:GetText())
      assert.are.equal("そのギルドランクは使用中です。", _G.GameTooltipTextLeft2:GetText())
    end },
  },
  name = function(frame, WFJ)
    frame:Show()
    local rank = frame.rankPermFrame.dropdown.Text
    assert.are.equal("Guild Bank", rank:GetText())
    assert.are.equal(0, WFJ.Labels.show("guildcontrol", "x", rank))
    assert.is_true(C.unrecorded(WFJ, rank))
  end,
  wrong = function(frame)
    frame.orderFrame, frame.dropdown, frame.rankPermFrame = 7, "nav", true
    _G[P .. "Checkbox5Text"] = 5
    _G.GuildControlUI_RankOrder_Update = "fn"
    _G.GuildControlBankTab1 = 3
    return function() assert.are.equal("ギルド管理", _G.GuildControlUITitle:GetText()) end
  end,
})
