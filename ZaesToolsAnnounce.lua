-- Zaes Tools Announce v2.1.0 (Simple + Silent) for WotLK 3.3.5
local ADDON_NAME = ...
ZaesToolsAnnounceDB = ZaesToolsAnnounceDB or {}

local CreateFrame, UnitGUID, UnitExists, GetRaidTargetIndex =
      CreateFrame, UnitGUID, UnitExists, GetRaidTargetIndex
local GetNumPartyMembers, GetNumRaidMembers, SendChatMessage =
      GetNumPartyMembers, GetNumRaidMembers, SendChatMessage
local IsInInstance, GetTime, UnitClass, UnitCastingInfo, UnitName =
      IsInInstance, GetTime, UnitClass, UnitCastingInfo, UnitName
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo

local f = CreateFrame("Frame")

-- ================== Defaults ==================
local defaults = {
  channel = "PARTY",            -- PARTY, EMOTE, or SILENT
  onlyInGroups = true,
  suppressInBG = true,

  -- Throttles
  throttleSec = 8,
  t_interrupt = 0,
  t_ccApply  = 0,
  t_ccBreak  = 4,
  t_ccFade   = 6,
  t_oom      = 8,

  -- Features (always on in this simple build)
  oomEnabled = true,
  interruptsEnabled = true,
  ccApplyEnabled = true,
  ccBreakEnabled = true,
  ccFadeEnabled  = true,

  -- Common Wrath CC
  ccSpells = {
    ["Polymorph"]=true, ["Sap"]=true, ["Hibernate"]=true, ["Freezing Trap"]=true,
    ["Wyvern Sting"]=true, ["Repentance"]=true, ["Fear"]=true, ["Psychic Scream"]=true,
    ["Howl of Terror"]=true, ["Seduction"]=true, ["Hex"]=true, ["Shackle Undead"]=true,
    ["Banish"]=true, ["Gouge"]=true, ["Blind"]=true, ["Hammer of Justice"]=true,
    ["Kidney Shot"]=true, ["Intimidating Shout"]=true,
  },

  -- Marker mode baked to BOTH
  markerMode = "BOTH",

  -- Normal (Party) text
  fmt_interrupt = ">> Interrupted {markboth}{target}'s{bspell} with {ispell} <<",
  fmt_ccApply   = "[CC] {markboth}{cc} on {target}",
  fmt_ccBreak   = "[CC Broken] {markboth}{cc} on {target} by {breaker}{bspell}",
  fmt_ccFade    = "[CC Faded] {markboth}{cc} on {target} ended",
  fmt_dispel    = "[CC Dispelled] {markboth}{cc} on {target} by {breaker}",
  fmt_oom       = "** OOM trying to cast {ispell} **",

  -- RP (Emote) text
  rp_interrupt = "{player} interrupts {markname}{target}{bspell} with {ispell}.",
  rp_ccApply   = "{player} places {cc} on {markname}{target}.",
  rp_ccBreak   = "{player} sees {cc} on {markname}{target} broken by {breaker}{bspell}.",
  rp_ccFade    = "{cc} on {markname}{target} fades.",
  rp_dispel    = "{player} notices {cc} on {markname}{target} dispelled by {breaker}.",
  rp_oom       = "{player} tries to cast {ispell} but is out of mana.",
}

-- ================== Utils ==================
local function deepcopy(v) if type(v)~="table" then return v end local t={} for k,vv in pairs(v) do t[k]=deepcopy(vv) end return t end
local function applyDefaults(db, defs) for k,v in pairs(defs) do if db[k]==nil then db[k]=deepcopy(v) end end end

local function InGroup() return (GetNumRaidMembers() or 0)>0 or (GetNumPartyMembers() or 0)>0 end
local function AllowedContext()
  if ZaesToolsAnnounceDB.onlyInGroups and not InGroup() then return false end
  local inInst, instType = IsInInstance()
  if ZaesToolsAnnounceDB.suppressInBG and inInst and (instType=="pvp" or instType=="arena") then return false end
  return true
end

local function PickChannel()
  local ch = (ZaesToolsAnnounceDB.channel or "PARTY"):upper()
  if ch == "EMOTE" then return "EMOTE"
  elseif ch == "SILENT" then return "SELF" -- our sentinel
  else return "PARTY" end
end

-- Throttle
local lastAnyAt=0; local lastByKind={ interrupt=0, ccApply=0, ccBreak=0, ccFade=0, oom=0 }
local tkey={interrupt="t_interrupt", ccApply="t_ccApply", ccBreak="t_ccBreak", ccFade="t_ccFade", oom="t_oom"}
local function Throttle(kind) local now=GetTime(); local db=ZaesToolsAnnounceDB
  if (now-lastAnyAt)<(db.throttleSec or 8) then return false end
  if (now-(lastByKind[kind] or 0))<(db[tkey[kind]] or 0) then return false end
  lastAnyAt, lastByKind[kind]=now,now; return true
end

-- Token formatter
local function fmt(template, t)
  return (template:gsub("{(.-)}", function(k)
    if k=="bspell" then return t.bspell and (" ("..t.bspell..")") or "" end
    return t[k] or ""
  end))
end

-- Send (respects Silent mode)
local function Send(kind, msg)
  if not Throttle(kind) then return end
  if not AllowedContext() then return end
  local ch = PickChannel()
  if ch == "SELF" then
    if DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZTA|r "..msg)
    end
  else
    SendChatMessage(msg, ch)
  end
end

-- Heals + OOM
local CLASS_HEALS={
  PRIEST={ ["Flash Heal"]=1,["Greater Heal"]=1,["Binding Heal"]=1,["Prayer of Healing"]=1,["Circle of Healing"]=1,["Renew"]=1,["Penance"]=1,["Prayer of Mending"]=1 },
  PALADIN={ ["Holy Light"]=1,["Flash of Light"]=1,["Holy Shock"]=1,["Lay on Hands"]=1 },
  SHAMAN={ ["Healing Wave"]=1,["Lesser Healing Wave"]=1,["Chain Heal"]=1,["Riptide"]=1,["Earth Shield"]=1 },
  DRUID={ ["Healing Touch"]=1,["Regrowth"]=1,["Rejuvenation"]=1,["Lifebloom"]=1,["Swiftmend"]=1,["Tranquility"]=1,["Nourish"]=1 },
}
local healSpells; local lastSentSpell,lastSentAt,lastOOMAt=nil,0,0
local function OnOOM(spell)
  local db=ZaesToolsAnnounceDB if not(db.oomEnabled and healSpells and healSpells[spell]) then return end
  local now=GetTime() if now-lastOOMAt<(db.t_oom or 8) then return end
  local player=UnitName("player") or "I"; local tokens={ispell=spell, player=player}
  local useRP = (PickChannel()=="EMOTE")
  local text = useRP and fmt(db.rp_oom, tokens) or fmt(db.fmt_oom, tokens)
  Send("oom", text); lastOOMAt=now
end

-- CC + Interrupts
local function ccEnabled(n) return ZaesToolsAnnounceDB.ccSpells[n or ""] end
local activeCC={}

-- Marker helpers
local ICON_NAMES={[1]="Star",[2]="Circle",[3]="Diamond",[4]="Triangle",[5]="Moon",[6]="Square",[7]="Cross",[8]="Skull"}

-- Basic, fast marker lookup: check target/focus/mouseover, then party/raid targets
local SCAN_UNITS={"target","focus","mouseover","boss1","boss2","boss3","boss4","arena1","arena2","arena3","arena4","arena5"}
local function FindUnitByGUID(g)
  if not g then return end
  for i=1,#SCAN_UNITS do local u=SCAN_UNITS[i] if UnitExists(u) and UnitGUID(u)==g then return u end end
  for i=1,GetNumPartyMembers() do local u="party"..i.."target" if UnitExists(u) and UnitGUID(u)==g then return u end end
  for i=1,GetNumRaidMembers() do local u="raid"..i.."target" if UnitExists(u) and UnitGUID(u)==g then return u end end
end

local function MarkerTokens(g)
  local u=FindUnitByGUID(g)
  if u then
    local i=GetRaidTargetIndex(u)
    if i and i>=1 and i<=8 then return "{rt"..i.."} ", ICON_NAMES[i] end
  end
  return "",""
end

local function ApplyMarkerMode(iconStr, nameStr)
  -- baked BOTH
  local nb = nameStr ~= "" and ("["..nameStr.."] ") or ""
  return iconStr or "", (nameStr~="" and (nameStr.." ") or ""), (iconStr or "")..nb
end

local function announce(kind,dGUID,dName,ccName,breaker,extraSpell)
  local icon,name = MarkerTokens(dGUID)
  local mark,markname,markboth = ApplyMarkerMode(icon,name)
  local db=ZaesToolsAnnounceDB; local player=UnitName("player") or "I"
  local tokens={cc=ccName,target=dName,breaker=breaker,bspell=extraSpell,mark=mark,markname=markname,markboth=markboth,player=player}
  local useRP = (PickChannel()=="EMOTE")
  local msg
  if kind=="apply" then
    msg = useRP and fmt(db.rp_ccApply,tokens) or fmt(db.fmt_ccApply,tokens)
  elseif kind=="break" then
    msg = useRP and fmt(db.rp_ccBreak,tokens) or fmt(db.fmt_ccBreak,tokens)
  elseif kind=="fade" then
    msg = useRP and fmt(db.rp_ccFade,tokens)  or fmt(db.fmt_ccFade,tokens)
  elseif kind=="dispel" then
    msg = useRP and fmt(db.rp_dispel,tokens)  or fmt(db.fmt_dispel,tokens)
  end
  if msg then Send("cc"..kind, msg) end
end

-- Combat log
local function OnCLEU(...)
  local _,e,_,sg,sn,_,_,dg,dn=...
  local me=UnitGUID("player")
  if e=="SPELL_INTERRUPT" and ZaesToolsAnnounceDB.interruptsEnabled and sg==me then
    local is,bs=select(13,...),select(16,...) -- interrupt spell, broken spell
    local icon,name = MarkerTokens(dg); local mark,markname,markboth = ApplyMarkerMode(icon,name)
    local player=UnitName("player") or "I"
    local tokens={target=dn,bspell=bs,ispell=is,mark=mark,markname=markname,markboth=markboth,player=player}
    local useRP = (PickChannel()=="EMOTE")
    local msg = useRP and fmt(ZaesToolsAnnounceDB.rp_interrupt,tokens) or fmt(ZaesToolsAnnounceDB.fmt_interrupt,tokens)
    Send("interrupt", msg); return
  end

  if sg==me and e=="SPELL_AURA_APPLIED" then
    local s,a=select(13,...),select(15,...) if a=="DEBUFF" and ccEnabled(s) and ZaesToolsAnnounceDB.ccApplyEnabled then
      activeCC[dg..":"..s]=true; announce("apply",dg,dn,s); return
    end
  end

  if e=="SPELL_AURA_BROKEN" or e=="SPELL_AURA_BROKEN_SPELL" then
    local bn=select(13,...) if ccEnabled(bn) and ZaesToolsAnnounceDB.ccBreakEnabled then
      local key=dg..":"..bn
      if activeCC[key] then
        local ex=(e=="SPELL_AURA_BROKEN_SPELL") and select(16,...) or nil
        announce("break",dg,dn,bn,sn,ex); activeCC[key]=nil
      end
      return
    end
  end

  if e=="SPELL_DISPEL" or e=="SPELL_STOLEN" then
    local rn=select(16,...) if ccEnabled(rn) and ZaesToolsAnnounceDB.ccBreakEnabled then
      local key=dg..":"..rn
      if activeCC[key] then announce("dispel",dg,dn,rn,sn); activeCC[key]=nil end
      return
    end
  end

  if e=="SPELL_AURA_REMOVED" then
    local s=select(13,...) if ccEnabled(s) and ZaesToolsAnnounceDB.ccFadeEnabled then
      local key=dg..":"..s
      if activeCC[key] then announce("fade",dg,dn,s); activeCC[key]=nil end
      return
    end
  end
end

-- Events
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("UNIT_SPELLCAST_SENT")
f:RegisterEvent("UI_ERROR_MESSAGE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent",function(_,e,...)
  if e=="ADDON_LOADED" then local n=... if n==ADDON_NAME then applyDefaults(ZaesToolsAnnounceDB,defaults) end
  elseif e=="PLAYER_LOGIN" then local _,c=UnitClass("player"); healSpells=CLASS_HEALS[c] or {}
  elseif e=="COMBAT_LOG_EVENT_UNFILTERED" then OnCLEU(CombatLogGetCurrentEventInfo and CombatLogGetCurrentEventInfo() or ...)
  elseif e=="UNIT_SPELLCAST_SENT" then local u,s=... if u=="player" and s then lastSentSpell=s; lastSentAt=GetTime() end
  elseif e=="UI_ERROR_MESSAGE" then
    local a1,a2=... local m=(a2 and a2~="") and a2 or a1
    if type(m)=="string" and (m==SPELL_FAILED_NO_POWER or m==ERR_NO_POWER or m==SPELL_FAILED_NOT_ENOUGH_MANA or m:lower():find("not enough mana")) then
      local sp=lastSentSpell if (not sp) or (GetTime()-lastSentAt>1.5) then sp=UnitCastingInfo("player") or sp end
      if sp then OnOOM(sp) end
    end
  elseif e=="PLAYER_REGEN_ENABLED" then lastAnyAt=0 end
end)

-- Slash to open options
SLASH_ZAESTOOLSANNOUNCE1="/zta"
SlashCmdList["ZAESTOOLSANNOUNCE"]=function()
  InterfaceOptionsFrame_OpenToCategory("Zaes Tools Announce")
  InterfaceOptionsFrame_OpenToCategory("Zaes Tools Announce")
end
