-- Core/ErrorVoices.lua: the voices the character's own spoken error lines ("out of range") may speak in, and the
-- setting that picks one (ADR-093). Automatic is the voice cast for the character's race and sex; the player may
-- pick any player voice (`dwarf-f`) or any NPC voice of the cast (`qdwarffemaleguard`), named by race, sex and
-- type in both languages. The packs carry each voice's files under the same key (Register.lua `errors.voices`);
-- a voice the installed packs lack is left out of the menu, and choosing one anyway plays the character's own.
-- The NPC list is the pipeline's `voice_make.npc_voices`: tests/python/test_error_voices.py keeps the two equal.
local _, WFJ = ...
local EV = {}
WFJ.ErrorVoices = EV

EV.AUTO = "auto"

local SEX = { m = { en = "male", ja = "男性" }, f = { en = "female", ja = "女性" } }

-- The client's races in its own order, then the Goblin (NPC voices only). `player`: the race as UnitRace's second
-- value names it, lowercased (the pack's race-sex key); the race words follow Core/Placeholders.
EV.RACES = {
  { player = "human", en = "Human", ja = "人間" },
  { player = "orc", en = "Orc", ja = "オーク" },
  { player = "dwarf", en = "Dwarf", ja = "ドワーフ" },
  { player = "nightelf", en = "Night Elf", ja = "ナイトエルフ" },
  { player = "scourge", en = "Undead", ja = "アンデッド" },
  { player = "tauren", en = "Tauren", ja = "トーレン" },
  { player = "gnome", en = "Gnome", ja = "ノーム" },
  { player = "troll", en = "Troll", ja = "トロール" },
  { player = "skyborne", en = "Skyborne", ja = "スカイボーン" },
  { en = "Goblin", ja = "ゴブリン" },
}

local TYPE = {
  player = { en = "player", ja = "プレイヤー" },
  npc = { en = "NPC", ja = "NPC" },
  standard = { en = "standard", ja = "標準" },
  guard = { en = "guard", ja = "衛兵" },
  official = { en = "official", ja = "役人" },
  warrior = { en = "warrior", ja = "戦士" },
  shady = { en = "shady", ja = "怪しげ" },
  shaman = { en = "shaman", ja = "シャーマン" },
  grim = { en = "grim", ja = "強面" },
  maternal = { en = "maternal", ja = "母親" },
  young = { en = "young", ja = "若者" },
  priestess = { en = "priestess", ja = "巫女" },
  sentinel = { en = "sentinel", ja = "歩哨" },
  dark = { en = "dark", ja = "陰気" },
  magic = { en = "magic", ja = "魔術師" },
  elder = { en = "elder", ja = "長老" },
  zany = { en = "zany", ja = "おどけ者" },
  happy = { en = "happy", ja = "陽気" },
  nerdy = { en = "nerdy", ja = "学者肌" },
  laidback = { en = "laid-back", ja = "のんびり" },
  old = { en = "old", ja = "老人" },
  gruff = { en = "gruff", ja = "ぶっきらぼう" },
}

-- The NPC voices of the cast, per race (EV.RACES order): { voice id, sex, type }. A cast voice a player race
-- already speaks in (the Skyborne player voices are two of the Skyborne NPC sets) is listed once, as the player's.
EV.NPC = {
  {
    { "qhumanmaleofficial", "m", "official" }, { "qhumanmalestandard", "m", "standard" },
    { "qhumanmalewarrior", "m", "warrior" }, { "qhumanfemaleofficial", "f", "official" },
    { "qhumanfemalestandard", "f", "standard" }, { "qhumanfemalewarrior", "f", "warrior" },
  },
  {
    { "qorcmaleguard", "m", "guard" }, { "qorcmaleshady", "m", "shady" }, { "qorcmalestandard", "m", "standard" },
    { "qorcfemaleshaman", "f", "shaman" }, { "qorcfemalestandard", "f", "standard" },
    { "qorcfemalewarrior", "f", "warrior" },
  },
  {
    { "qdwarfmalegrim", "m", "grim" }, { "qdwarfmaleguard", "m", "guard" }, { "qdwarfmalestandard", "m", "standard" },
    { "qdwarffemaleguard", "f", "guard" }, { "qdwarffemalematernal", "f", "maternal" },
    { "qdwarffemaleyoung", "f", "young" },
  },
  {
    { "qnightelfmaleofficial", "m", "official" }, { "qnightelfmalestandard", "m", "standard" },
    { "qnightelfmalewarrior", "m", "warrior" }, { "qnightelffemalepriestess", "f", "priestess" },
    { "qnightelffemalesentinel", "f", "sentinel" }, { "qnightelffemalestandard", "f", "standard" },
  },
  {
    { "qundeadmaledark", "m", "dark" }, { "qundeadmalestandard", "m", "standard" },
    { "qundeadmalewarrior", "m", "warrior" }, { "qundeadfemalemagic", "f", "magic" },
    { "qundeadfemalestandard", "f", "standard" }, { "qundeadfemalewarrior", "f", "warrior" },
  },
  {
    { "qtaurenmaleelder", "m", "elder" }, { "qtaurenmaleshaman", "m", "shaman" },
    { "qtaurenmalewarrior", "m", "warrior" }, { "qtaurenfemaleofficial", "f", "official" },
    { "qtaurenfemaleshaman", "f", "shaman" }, { "qtaurenfemalestandard", "f", "standard" },
  },
  {
    { "qgnomemalestandard", "m", "standard" }, { "qgnomemaleyoung", "m", "young" }, { "qgnomemalezany", "m", "zany" },
    { "qgnomefemalehappy", "f", "happy" }, { "qgnomefemalenerdy", "f", "nerdy" },
    { "qgnomefemalestandard", "f", "standard" },
  },
  {
    { "qtrollmaledark", "m", "dark" }, { "qtrollmaleshaman", "m", "shaman" }, { "qtrollmalestandard", "m", "standard" },
    { "qtrollfemalelaidback", "f", "laidback" }, { "qtrollfemaleold", "f", "old" },
    { "qtrollfemalestandard", "f", "standard" },
  },
  { { "qskybourneelfmale3775", "m", "npc" }, { "qskybourneelffemale3774", "f", "npc" } },
  {
    { "qgoblinmalegruff", "m", "gruff" }, { "qgoblinmaleguard", "m", "guard" }, { "qgoblinmalezany", "m", "zany" },
    { "qgoblinfemalezany", "f", "zany" },
  },
}

-- "Dwarf, female (guard)" / "ドワーフ・女性（衛兵）"
local function label(race, sex, kind)
  local t = TYPE[kind]
  return ("%s, %s (%s)"):format(race.en, SEX[sex].en, t.en), ("%s・%s（%s）"):format(race.ja, SEX[sex].ja, t.ja)
end

-- Every choice in menu order (Automatic, then per race its player voices, then its NPC voices), each choice's label
-- in both languages, and the per-race groups the menu shows as submenus.
EV.CHOICES = { EV.AUTO }
EV.TEXT = { [EV.AUTO] = { en = "Automatic (your character's race and sex)", ja = "自動（キャラクターの種族と性別）" } }
EV.GROUPS = {}
for i, race in ipairs(EV.RACES) do
  local group = { en = race.en, ja = race.ja, choices = {} }
  local function add(id, sex, kind)
    local en, ja = label(race, sex, kind)
    EV.CHOICES[#EV.CHOICES + 1] = id
    EV.TEXT[id] = { en = en, ja = ja }
    group.choices[#group.choices + 1] = id
  end
  if race.player then
    add(race.player .. "-m", "m", "player")
    add(race.player .. "-f", "f", "player")
  end
  for _, v in ipairs(EV.NPC[i]) do add(v[1], v[2], v[3]) end
  EV.GROUPS[i] = group
end

local choiceText, choiceTextJa = {}, {}
for id, t in pairs(EV.TEXT) do choiceText[id], choiceTextJa[id] = t.en, t.ja end

-- Listed only with a voice pack, like the other voice settings; a voice no installed pack carries is not offered.
WFJ.Settings.define{ id = "voice.errorVoice", kind = "choice", choices = EV.CHOICES, default = EV.AUTO,
  hidden = function() return not (WFJ.Voice and WFJ.Voice.hasPack()) end,
  apply = function() WFJ.State.fire("voice") end,
  label = "Voice of your character's error lines", ja = "自分のキャラクターのエラー音声の声",
  choiceText = choiceText, choiceTextJa = choiceTextJa, choiceGroups = EV.GROUPS,
  choiceHidden = function(c)
    return c ~= EV.AUTO and not (WFJ.Voice and WFJ.Voice.hasErrorVoice(c))
  end }
