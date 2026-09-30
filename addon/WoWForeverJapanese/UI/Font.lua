-- UI/Font.lua: the bundled Japanese face, applied per FontString (SetFont with the element's own size/flags).
-- Never creates or modifies a global font object (luacheck forbids CreateFont / GameFont* / SystemFont*).
local _, WFJ = ...
local Font = {}
WFJ.Font = Font

Font.PATH = "Interface\\AddOns\\" .. WFJ.ADDON .. "\\Fonts\\ipagui.ttf"
Font.DEFAULT_SIZE = 12
Font.CLIENT = "Fonts\\FRIZQT__.TTF" -- the client's standard UI face, used only under the font-load probe

-- Font changes the client refused: on a fresh launch the bundled font file is not loaded yet when the
-- addon builds its own widgets at load, and SetFont returns false. fs → { path, size, flags } (weak keys).
local pending = setmetatable({}, { __mode = "k" })

-- SetFont for a FontString the addon owns outright (settings pages, the marker banner). A refusal is remembered and
-- retried by Font.retryPending; a later Font.set on the same FontString replaces what is pending.
-- → the SetFont result
function Font.set(fs, path, size, flags)
  local ok = fs:SetFont(path, size, flags)
  if ok == false then
    pending[fs] = { path, size, flags }
  else
    pending[fs] = nil
  end
  return ok
end

-- → the number still refused after one more try
function Font.retryPending()
  local n = 0
  for fs, f in pairs(pending) do
    if fs:SetFont(f[1], f[2], f[3]) == false then
      n = n + 1
    else
      pending[fs] = nil
    end
  end
  return n
end

-- The font-load probe. On a fresh launch the client refuses the bundled font until something makes it load the
-- file, and hidden widgets never do: in game, with no window opened, every refused font was still
-- refused after 60 s; with this probe shown, all were applied on the first retry, 1 s after PLAYER_ENTERING_WORLD
-- [verified in-game: the client loads an addon font file when a visible FontString asks for it]. The probe is one
-- visible, nearly transparent character, shown until the refused fonts are applied. → the probe FontString
local probe
function Font.startProbe(parent)
  if probe then return probe.fs end
  if not parent then return nil end
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(16, 16)
  holder:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  local fs = holder:CreateFontString(nil, "OVERLAY")
  fs:SetPoint("CENTER", holder, "CENTER", 0, 0)
  -- a client font first: SetText needs a font, and the bundled one may be refused (the client font is always loaded)
  fs:SetFont(Font.CLIENT, 8, "")
  fs:SetTextColor(1, 1, 1, 0.02)
  fs:SetText("あ")
  holder:Show()
  Font.set(fs, Font.PATH, 8, "") -- refused until the file loads; Font.retryPending keeps asking
  probe = { holder = holder, fs = fs }
  return fs
end

function Font.stopProbe()
  if not probe then return false end
  probe.holder:Hide()
  pending[probe.fs] = nil
  probe = nil
  return true
end

-- The bundled font at an element's original size and flags ({path,size,flags} as captured by SurfaceState).
function Font.bundled(orig)
  return {
    path = Font.PATH,
    size = (orig and orig.size) or Font.DEFAULT_SIZE,
    flags = (orig and orig.flags) or "",
  }
end
