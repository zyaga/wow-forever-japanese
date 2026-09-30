-- UI/HelpTooltip.lua: GameTooltip lines written in Lua (area "ui", surface "help", ADR-016): micro-button,
-- stat, empty-slot, bag-slot, repair-button and other help tooltips use GameTooltip:SetText / AddLine /
-- GameTooltip_AddNewbieTip, so no Item or Spell tooltip-data post-call fires for them (UI/Tooltip.lua never sees
-- them).
-- A window module registers the frames that own such tooltips (HelpTooltip.register). After the client builds the
-- tooltip (GameTooltip:SetText / :AppendText / :Show post-hooks, plus any client setter a module names, SetTalent),
-- every left and right line, line 1 included (a title here, never a name), goes through Labels.show on this surface
-- when the tooltip's owner is registered. The SetText / Show hooks also catch owner:UpdateTooltip() refreshes,
-- which call functions Blizzard captured before this addon loaded (MainMenuBarBagButtons.lua:240,
-- Vanilla/PaperDollFrame.lua:717, GameTooltip.lua:447–465). A tooltip showing an item or a spell is never walked:
-- those lines are UI/Tooltip's. One Show() refit per pass that changed a line (its own hook is ignored while
-- refitting). Release on OnHide.
local _, WFJ = ...
local HelpTooltip = {}
WFJ.HelpTooltip = HelpTooltip

local SURFACE = "help"
HelpTooltip.SURFACE = SURFACE
local Compat = WFJ.Compat

local owners = setmetatable({}, { __mode = "k" }) -- frame → opts ({ only = … } or true)
local busy = false
local recorded = 0 -- the highest line number recorded on the last pass

function HelpTooltip.register(owner, opts)
  if type(owner) == "table" then owners[owner] = opts or true end
end

function HelpTooltip.registered(owner)
  return owners[owner] ~= nil
end

local function tooltip()
  return Compat.get(SURFACE, "tooltip")
end

-- The refit a record carries: a modifier / area / master change rewrites help lines through
-- Render.refresh, which must lay the tooltip out again for the new text. A no-op while a walk is running (the walk
-- refits once at its end) and inside our own Show.
local function refit()
  if busy then return end
  local tt = tooltip()
  if type(tt) ~= "table" or not tt.Show then return end
  busy = true
  local ok, err = pcall(tt.Show, tt)
  busy = false
  if not ok then error(err, 0) end
end
-- A surface that writes a line of this tooltip itself (UI/QuestMap's dashed objective lines) passes this as its
-- record's refit, so its Show is ours and never starts a walk.
HelpTooltip.refit = refit

-- The label record the owner itself carries (a translated tab), when Blizzard copies that label into the tooltip's
-- title: SpellBookFrameTabButtonTemplate: SetText(MicroButtonTooltipText(self:GetText(), …)) [verified: classic_era
-- Vanilla/SpellBookFrame.xml:43–45]; CharacterFrameTabButtonTemplate when truncated [Classic/
-- CharacterFrameTemplates.xml:88–93]. → the record, or nil.
local function ownerLabel(owner)
  local widget = WFJ.ButtonText.known(owner) and WFJ.ButtonText.of(owner) or owner
  for _, recs in pairs(WFJ.SurfaceState.surfaces()) do
    for _, rec in pairs(recs) do
      if rec.fs == widget and type(rec.applied) == "string" and type(rec.en) == "string" then return rec end
    end
  end
  return nil
end

-- → the number of dictionary lines on the tooltip (0 when it is not ours to walk).
function HelpTooltip.walk(tt)
  tt = tt or tooltip()
  if busy or type(tt) ~= "table" or not tt.GetOwner then return 0 end
  local opts = owners[tt:GetOwner()]
  local foreign = not opts or (tt.GetItem and tt:GetItem()) or (tt.GetSpell and tt:GetSpell())
  if foreign then -- reused for another owner, an item or a spell: the client rewrote the lines; forget ours
    if recorded > 0 then -- forget, not release: a line the client rewrote must not get our old English back
      recorded = 0
      WFJ.Render.forget(SURFACE)
    end
    return 0
  end
  local labelOpts = type(opts) == "table" and opts or nil
  local name, n, changed, lines = tt:GetName(), 0, false, tt:NumLines() or 0
  local owned = ownerLabel(tt:GetOwner())
  busy = true -- per-record refits wait for the single refit at the end of this pass
  local ok, err = pcall(function()
    for i = 1, lines do
      for _, side in ipairs({ "Left", "Right" }) do
        local fs = Compat.resolve(name .. "Text" .. side .. i)
        local recKey = side:sub(1, 1) .. i
        if fs and fs.GetText and (fs:GetText() or "") ~= "" then
          -- The client appended to a line we already translated (GameTooltip:AppendText adds the key binding after
          -- SetText, whose hook has run): put its English back in front of the addition, so the whole line is
          -- matched again (the `binding` form) and the record carries its font instead of dropping it.
          local rec = WFJ.SurfaceState.get(SURFACE, recKey)
          local current = fs:GetText()
          if rec and rec.fs == fs and type(rec.applied) == "string" and #current > #rec.applied
              and current:sub(1, #rec.applied) == rec.applied then
            fs:SetText(rec.en .. current:sub(#rec.applied + 1))
          elseif i == 1 and side == "Left" and owned and current:sub(1, #owned.applied) == owned.applied then
            fs:SetText(owned.en .. current:sub(#owned.applied + 1)) -- the owner's own label, copied by the client
          end
          local before = fs:GetText()
          n = n + WFJ.Labels.show(SURFACE, recKey, fs, refit, labelOpts)
          if fs:GetText() ~= before then changed = true end
        else
          WFJ.SurfaceState.drop(SURFACE, recKey)
        end
      end
    end
    for i = lines + 1, recorded do
      WFJ.SurfaceState.drop(SURFACE, "L" .. i)
      WFJ.SurfaceState.drop(SURFACE, "R" .. i)
    end
  end)
  busy = false -- cleared even when a write errors, so help tooltips never stay switched off
  if not ok then error(err, 0) end
  recorded = lines
  if changed then refit() end -- a line got longer or shorter: one refit
  return n
end

-- One walk of `tt` as if its current owner were registered with `opts`: for a tooltip whose owner cannot be
-- registered because it owns unrelated tooltips too: Forever's exhaustion tick anchors its tooltip to UIParent
-- (blizzard_statustrackingbar/mainline/expbaroverrides.lua:29–31). The caller runs it right after the client wrote
-- the tooltip; `opts.only` should restrict it to the keys that writer shows. The owner's registration (or its absence)
-- is put back before returning, so a later SetText / Show from another writer with the same owner is foreign again.
-- Records live on this surface like every walk's: re-rendered on a modifier change, released on OnHide.
-- → the number of dictionary lines (0 when there is no tooltip or owner, or a walk is running).
function HelpTooltip.walkAs(tt, opts)
  tt = tt or tooltip()
  if busy or type(tt) ~= "table" or type(tt.GetOwner) ~= "function" then return 0 end
  local owner = tt:GetOwner()
  if owner == nil then return 0 end
  local previous = owners[owner]
  owners[owner] = type(opts) == "table" and opts or true
  local ok, n = pcall(HelpTooltip.walk, tt)
  owners[owner] = previous
  if not ok then error(n, 0) end
  return n
end

-- itemAppended (ADR-038): lines a writer appends to a tooltip that shows an item: the auction house's seller
-- and time-left lines (AuctionHouseUtil.AddAuctionHouseTooltipInfo, blizzard_auctionhouseutil.lua:301–306), the
-- enchant slot's replace hint, an order reagent's provider line. `walk` leaves item tooltips alone; the owning surface
-- calls this right after the writer ran. Every left line is shown restricted to `opts.only` (required): the item's
-- own lines are no key of that set, so they stay with the item path (UI/Tooltip) and are never rewritten twice.
-- Records live on their own surface (released on the tooltip's OnHide). → the number of dictionary lines
local APPENDED = SURFACE .. ".appended"
HelpTooltip.APPENDED = APPENDED
local appendedHooked = setmetatable({}, { __mode = "k" })
function HelpTooltip.appended(tt, opts)
  tt = tt or tooltip()
  if busy or type(tt) ~= "table" or type(opts) ~= "table" or type(opts.only) ~= "table"
      or type(tt.GetName) ~= "function" or type(tt.NumLines) ~= "function" then return 0 end
  if not appendedHooked[tt] and type(tt.HookScript) == "function" then
    appendedHooked[tt] = true
    tt:HookScript("OnHide", function() WFJ.Render.release(APPENDED) end)
  end
  local name, n, changed = tt:GetName(), 0, false
  if type(name) ~= "string" then return 0 end
  local function relayout() -- a modifier change rewrites these lines: lay the tooltip out again
    if busy or type(tt.Show) ~= "function" then return end
    busy = true
    pcall(tt.Show, tt)
    busy = false
  end
  busy = true -- our own Show (the refit below) must not start a walk
  local ok, err = pcall(function()
    for i = 1, tt:NumLines() or 0 do
      local fs = Compat.resolve(name .. "TextLeft" .. i)
      if type(fs) == "table" and type(fs.GetText) == "function" and (fs:GetText() or "") ~= "" then
        local before = fs:GetText()
        n = n + WFJ.Labels.show(APPENDED, "L" .. i, fs, relayout, opts)
        if fs:GetText() ~= before then changed = true end
      end
    end
    if changed and type(tt.Show) == "function" then tt:Show() end -- one refit for the new widths
  end)
  busy = false
  if not ok then error(err, 0) end
  return n
end

function HelpTooltip.release()
  recorded = 0
  return WFJ.Render.release(SURFACE)
end

local hookedMethods = {}

-- Walks after a GameTooltip method the client uses to build a Lua-owned tooltip (a module names e.g. "SetTalent").
function HelpTooltip.after(method)
  local tt = tooltip()
  if hookedMethods[method] or type(tt) ~= "table" or type(tt[method]) ~= "function" then return false end
  hookedMethods[method] = true
  hooksecurefunc(tt, method, function(self) HelpTooltip.walk(self) end)
  return true
end

local hooked = false

-- Called by Main after Compat.init, before the window modules register their owners.
function HelpTooltip.init()
  Compat.declare(SURFACE, "tooltip", { "GameTooltip" })
  if hooked then return false end
  local tt = tooltip()
  if type(tt) ~= "table" or not tt.HookScript then return false end
  hooked = true
  HelpTooltip.after("SetText")
  HelpTooltip.after("AppendText") -- the key binding after a title (MainMenuBarBagButtons.xml:94–102)
  HelpTooltip.after("Show")
  tt:HookScript("OnHide", HelpTooltip.release)
  return true
end
