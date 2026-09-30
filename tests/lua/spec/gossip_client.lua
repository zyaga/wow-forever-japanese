-- The client's side of the NPC talk window, replayed from classic_era 1.15.9.69722:
--   Blizzard_UIPanels_Game/Shared/GossipFrameShared.lua:7–168, 241–294 (mixins, UpdateScrollBox, Update),
--   Blizzard_UIPanels_Game/Classic/GossipFrame.lua:13–24 (GOSSIP_SHOW → HandleShow + Update),
--   Blizzard_SharedXML/Shared/Scroll/ScrollBox*.lua + ScrollUtil.lua:14–53 (a list view: data provider → release
--   every row → extents from the calculator → acquire rows from per-template pools (LIFO), each sized to its extent →
--   layout by the rows' current heights from the offset the extents give the first visible row
--   (ScrollBoxLinearView.lua:12–33, 93–96; ScrollBoxViewUtil.lua:33–49) → initializer → OnInitializedFrame; scrolling
--   releases / acquires and lays out again; FullUpdate re-measures and lays out without re-initializing).
-- Kept in its own file so the stub's write counters can tell the client's writes from the addon's: a write whose first
-- caller outside wow_stub.lua is under addon/ is the addon's; one from here or from a spec is the client's.
local Client = {}

local TITLE, DIVIDER, OPTION, ACTIVE_QUEST, AVAILABLE_QUEST = 1, 2, 3, 4, 5

-- A list ScrollBox showing `viewRows` elements from `offset`.
local function scrollBox(viewRows)
  local sb = CreateFrame("Frame")
  sb.viewRows, sb.offset, sb.frames, sb.pools, sb.extents = viewRows, 0, {}, {}, {}
  sb.dp = {}
  sb.callbacks = { OnInitializedFrame = {}, OnReleasedFrame = {} }
  sb.calls.FullUpdate = 0

  function sb:RegisterCallback(event, fn, owner)
    table.insert(self.callbacks[event], { fn, owner })
  end
  local function fire(self, event, frame, elementData)
    for _, c in ipairs(self.callbacks[event]) do c[1](c[2], frame, elementData) end
  end

  function sb:GetDataProvider() return self.dp end
  function sb:ForEachElementData(fn)
    for _, ed in ipairs(self.dp) do fn(ed) end
  end
  function sb:ForEachFrame(fn)
    for _, i in ipairs(self:visibleIndices()) do fn(self.frames[i], self.frames[i].elementData) end
  end
  function sb:visibleIndices()
    local out = {}
    for i in pairs(self.frames) do out[#out + 1] = i end
    table.sort(out)
    return out
  end

  local function release(self, i)
    local f = self.frames[i]
    self.frames[i] = nil
    fire(self, "OnReleasedFrame", f, f.elementData)
    f.shown, f.elementData, f.dataIndex = false, nil, nil
    table.insert(self.pools[f.template], f)
    self.released[f] = true
  end

  local function measure(self)
    self.extents = {}
    for i, ed in ipairs(self.dp) do self.extents[i] = self.view.calculator(i, ed) end
  end

  -- LayoutInternal: the visible rows are stacked by their own heights, starting where the extents put the first one.
  local function layout(self)
    local first = self.offset + 1
    local top = 0
    for i = 1, first - 1 do top = top + self.extents[i] end
    for i = first, math.min(#self.dp, self.offset + self.viewRows) do
      local f = self.frames[i]
      if f then
        f.top = top
        top = top + f:GetHeight()
      end
    end
  end

  -- ValidateDataRange + AcquireRange + InvokeInitializers.
  local function sync(self)
    local first, last = self.offset + 1, math.min(#self.dp, self.offset + self.viewRows)
    local gone = {}
    for i in pairs(self.frames) do
      if i < first or i > last then gone[#gone + 1] = i end
    end
    table.sort(gone)
    for _, i in ipairs(gone) do release(self, i) end
    local new = {}
    for i = first, last do
      if not self.frames[i] then
        local ed = self.dp[i]
        local template, init = self.view.factory(ed)
        self.pools[template] = self.pools[template] or {}
        local f = table.remove(self.pools[template]) or self.view.create(template)
        f.template, f.elementData, f.dataIndex, f.shown, f.initializer = template, ed, i, true, init
        self.released[f] = nil
        self.view.resize(f, self.extents[i]) -- ResizeFrame: the element's extent
        self.frames[i] = f
        new[#new + 1] = i
      end
    end
    layout(self)
    for _, i in ipairs(new) do
      local f = self.frames[i]
      if f.initializer then f.initializer(f, f.elementData) end
      fire(self, "OnInitializedFrame", f, f.elementData) -- also without an initializer (canSignalWithoutInitializer)
    end
  end

  sb.released = setmetatable({}, { __mode = "k" })
  function sb:SetView(view) self.view = view end
  function sb:SetDataProvider(dp)
    local all = self:visibleIndices()
    for _, i in ipairs(all) do release(self, i) end
    self.dp = dp
    self.offset = math.max(0, math.min(self.offset, #dp - self.viewRows)) -- RetainScrollPosition
    measure(self)
    sync(self)
  end
  function sb:scrollTo(offset)
    self.offset = math.max(0, math.min(offset, #self.dp - self.viewRows))
    sync(self)
  end
  function sb:extentUntil(i)
    local top = 0
    for j = 1, i - 1 do top = top + self.extents[j] end
    return top
  end
  function sb:FullUpdate()
    self.calls.FullUpdate = self.calls.FullUpdate + 1
    measure(self)
    sync(self)
  end
  return sb
end

-- GossipSharedTitleButtonMixin + the option / quest Setup mixins, copied onto each button (Mixin semantics).
local function titleButton(Stub, kind)
  local b = Stub.button(nil, "")
  b.kind, b.height = kind, 15
  b.fontString.width = 275 -- <ButtonText><Size x="275"/> (GossipFrame.xml:104–109)
  b.Icon = { GetHeight = function() return 15 end, SetTexture = function() end, SetVertexColor = function() end }
  function b:GetTextHeight() return self.fontString:GetHeight() end
  function b:SetHeight(h) self.height = h end
  function b:GetHeight() return self.height end
  function b:SetID(id) self.id = id end
  b.Resize = function(self) self:SetHeight(math.max(self:GetTextHeight() + 2, self.Icon:GetHeight())) end
  if kind == "option" then
    b.Setup = function(self, info)
      self:SetID(info.orderIndex or 0)
      if info.prepend then
        -- a movie option's PLAY_MOVIE_PREPEND in the same place (gossipframeshared.lua:77–82)
        self:SetText(GOSSIP_OPTION_PREPEND:format(info.prepend == "movie" and _G.PLAY_MOVIE_PREPEND or QUEST_PREPEND,
          info.name))
      else
        self:SetText(info.name)
      end
      self:Resize()
      self.shown = true
    end
  else
    b.Setup = function(self, info)
      self:SetID(info.questID)
      self:SetText(NORMAL_QUEST_DISPLAY:format(info.title))
      self:Resize()
      self.shown = true
    end
  end
  return b
end

local function greetingFrame(Stub)
  local f = CreateFrame("Frame")
  f.GreetingText = Stub.fontString("", "Fonts\\FRIZQT__.TTF", 13, "") -- QuestFont, width 270
  f.GreetingText.width = 270
  f.Setup = function(self, text)
    self.GreetingText:SetText(text)
    self.shown = true
    self:SetSize(270, self.GreetingText:GetHeight())
  end
  function f:GetHeight() return self.size and self.size[2] or 0 end
  return f
end

local function spacer()
  local f = CreateFrame("Frame")
  function f:GetHeight() return self.size and self.size[2] or 15 end
  return f
end

function Client.install(Stub, viewRows)
  _G.GOSSIP_BUTTON_TYPE_TITLE, _G.GOSSIP_BUTTON_TYPE_DIVIDER, _G.GOSSIP_BUTTON_TYPE_OPTION = TITLE, DIVIDER, OPTION
  _G.GOSSIP_BUTTON_TYPE_ACTIVE_QUEST, _G.GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST = ACTIVE_QUEST, AVAILABLE_QUEST
  _G.GOSSIP_OPTION_PREPEND = "|cff0000ff(%s)|r %s"
  _G.QUEST_PREPEND = "Quest"
  _G.NORMAL_QUEST_DISPLAY = "|cff000000%s|r"

  Stub.gossip = { text = "", options = {}, available = {}, active = {} }
  local function copies(list)
    local out = {}
    for i, t in ipairs(list) do
      local c = {}
      for k, v in pairs(t) do c[k] = v end
      out[i] = c
    end
    return out
  end
  _G.C_GossipInfo = {
    GetText = function() return Stub.gossip.text end,
    GetOptions = function() return copies(Stub.gossip.options) end, -- fresh tables per call, as the C API
    GetAvailableQuests = function() return copies(Stub.gossip.available) end,
    GetActiveQuests = function() return copies(Stub.gossip.active) end,
  }
  _G.ScrollUtil = {
    AddInitializedFrameCallback = function(sb, callback, owner, iterateExisting)
      if iterateExisting then sb:ForEachFrame(function(f, ed) callback(owner, f, ed) end) end
      sb:RegisterCallback("OnInitializedFrame", callback, owner)
    end,
    AddReleasedFrameCallback = function(sb, callback, owner)
      sb:RegisterCallback("OnReleasedFrame", callback, owner)
    end,
  }

  local frame = CreateFrame("Frame", "GossipFrame")
  local sb = scrollBox(viewRows or 6)
  frame.GreetingPanel = { ScrollBox = sb }
  -- NPCFriendshipStatusBarTemplate, hidden unless the NPC has a friendship reputation (GossipFrame.xml:73–77)
  frame.FriendshipStatusBar = CreateFrame("StatusBar")
  frame.gossipOptions = {}

  -- UpdateScrollBox (GossipFrameShared.lua:119–168)
  local initializers = {
    [TITLE] = { "greeting", function(f, ed) f:Setup(ed.text) end },
    [DIVIDER] = { "divider" },
    [OPTION] = { "option", function(f, ed) f:Setup(ed.info) end },
    [ACTIVE_QUEST] = { "active", function(f, ed) f:Setup(ed.info) end },
    [AVAILABLE_QUEST] = { "available", function(f, ed) f:Setup(ed.info) end },
  }
  sb:SetView({
    calculator = function(_, ed)
      if ed.greetingTextFrame then
        ed.greetingTextFrame.GreetingText:SetText(ed.text)
        return ed.greetingTextFrame.GreetingText:GetHeight()
      elseif ed.titleOptionButton then
        ed.titleOptionButton:Setup(ed.info)
        return ed.titleOptionButton:GetHeight()
      elseif ed.availableQuestButton then
        ed.availableQuestButton:Setup(ed.info)
        return ed.availableQuestButton:GetHeight()
      elseif ed.activeQuestButton then
        ed.activeQuestButton:Setup(ed.info)
        return ed.activeQuestButton:GetHeight()
      end
      return 16
    end,
    factory = function(ed)
      local e = initializers[ed.buttonType]
      return e[1], e[2]
    end,
    create = function(template)
      if template == "greeting" then return greetingFrame(Stub) end
      if template == "divider" then return spacer() end
      return titleButton(Stub, template)
    end,
    resize = function(f, extent)
      if f.SetHeight then f:SetHeight(extent) else f:SetSize(f.size and f.size[1] or 270, extent) end
    end,
  })

  local measureWidgets -- module locals, created on the first Update (:236–249)
  function frame.Update(self)
    if not measureWidgets then
      measureWidgets = {
        greeting = greetingFrame(Stub), option = titleButton(Stub, "option"),
        active = titleButton(Stub, "active"), available = titleButton(Stub, "available"),
      }
      Stub.gossipMeasure = measureWidgets
    end
    local dp = {}
    local function add(t) dp[#dp + 1] = t end
    add({ buttonType = TITLE, text = C_GossipInfo.GetText() or "", greetingTextFrame = measureWidgets.greeting })
    add({ buttonType = DIVIDER })
    add({ buttonType = DIVIDER })
    local index = 1
    local available = C_GossipInfo.GetAvailableQuests()
    for _, q in ipairs(available) do
      add({ buttonType = AVAILABLE_QUEST, info = q, availableQuestButton = measureWidgets.available, index = index })
      index = index + 1
    end
    if #available > 0 then add({ buttonType = DIVIDER }) end
    local active = C_GossipInfo.GetActiveQuests()
    for _, q in ipairs(active) do
      add({ buttonType = ACTIVE_QUEST, info = q, activeQuestButton = measureWidgets.active, index = index })
      index = index + 1
    end
    if #active > 0 then add({ buttonType = DIVIDER }) end
    for _, o in ipairs(self.gossipOptions) do
      add({ buttonType = OPTION, info = o, titleOptionButton = measureWidgets.option, index = index })
      index = index + 1
    end
    self.GreetingPanel.ScrollBox:SetDataProvider(dp)
  end

  -- GOSSIP_SHOW: HandleShow (options sorted by orderIndex, ShowUIPanel) then Update. g = { text, options = { names… } |
  -- { {name, orderIndex, prepend}… }, available = { titles… }, active = { titles… }, npc = { name, guid } }
  function Stub.showGossip(g)
    local options = {}
    for i, o in ipairs(g.options or {}) do
      options[i] = type(o) == "table" and o or { name = o, orderIndex = i - 1 }
    end
    local function quests(list, base)
      local out = {}
      for i, title in ipairs(list or {}) do out[i] = { title = title, questID = base + i } end
      return out
    end
    Stub.gossip = { text = g.text or "", options = options, available = quests(g.available, 100),
      active = quests(g.active, 200) }
    Stub.units.npc = g.npc
    frame.gossipOptions = C_GossipInfo.GetOptions()
    table.sort(frame.gossipOptions, function(a, b) return a.orderIndex < b.orderIndex end)
    if not frame:IsShown() then frame:Show() end
    frame:Update()
  end

  function Stub.closeGossip()
    frame:Hide()
  end

  return frame
end

return Client
