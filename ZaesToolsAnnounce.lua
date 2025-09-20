-- Zaes Tools Announce v1.5.4 (Epoch / WotLK 3.3.5)
local ADDON_NAME = ...
ZaesToolsAnnounceDB = ZaesToolsAnnounceDB or {}

-- Localized globals for perf
local CreateFrame, UnitGUID, UnitExists, GetRaidTargetIndex = CreateFrame, UnitGUID, UnitExists, GetRaidTargetIndex
local GetNumPartyMembers, GetNumRaidMembers, SendChatMessage = GetNumPartyMembers, GetNumRaidMembers, SendChatMessage
local IsInInstance, GetTime, UnitClass, UnitCastingInfo = IsInInstance, GetTime, UnitClass, UnitCastingInfo
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo

local f = CreateFrame("Frame")

-- ================== Defaults ==================
local defaults = {
  channel = "SMART",
  smartSoloFallback = "SAY",
  onlyInGroups = true,
  instanceOnly = false,
  suppressInBG = true,

  throttleSec = 8,
  t_interrupt = 0,
  t_ccApply  = 0,
  t_ccBreak  = 4,
  t_ccFade   = 6,
  t_oom      = 8,

  oomEnabled = true,
  interruptsEnabled = true,

  ccApplyEnabled = true,
  ccBreakEnabled = true,
  ccFadeEnabled  = true,
  ccSpells = {
    ["Polymorph"]=true, ["Sap"]=true, ["Hibernate"]=true, ["Freezing Trap"]=true,
    ["Wyvern Sting"]=true, ["Repentance"]=true, ["Fear"]=true, ["Psychic Scream"]=true,
    ["Howl of Terror"]=true, ["Seduction"]=true, ["Hex"]=true, ["Shackle Undead"]=true,
    ["Banish"]=true, ["Gouge"]=true, ["Blind"]=true, ["Hammer of Justice"]=true,
    ["Kidney Shot"]=true, ["Intimidating Shout"]=true,
  },

  markerMode = "ICON",

  fmt_interrupt = ">> Interrupted {markboth}{target}'s {bspell} with {ispell} <<",
  fmt_ccApply   = "[CC] {markboth}{cc} on {target}",
  fmt_ccBreak   = "[CC Broken] {markboth}{cc} on {target} by {breaker}{bspell}",
  fmt_ccFade    = "[CC Faded] {markboth}{cc} on {target} ended",
  fmt_dispel    = "[CC Dispelled] {markboth}{cc} on {target} by {breaker}",
  fmt_oom       = "** OOM trying to cast {ispell} **",
}

-- ================== Utilities ==================
local function deepcopy(v) if type(v)~="table" then return v end local t={} for k,vv in pairs(v) do t[k]=deepcopy(vv) end return t end
local function applyDefaults(db, defs) for k,v in pairs(defs) do if db[k]==nil then db[k]=deepcopy(v) end end end

local function InGroup() return (GetNumRaidMembers() or 0)>0 or (GetNumPartyMembers() or 0)>0 end

-- Cached instance check
local _instCacheT, _instCacheIn, _instCacheType = 0, false, nil
local function GetInstanceInfoCached()
  local now = GetTime()
  if now - _instCacheT > 0.25 then _instCacheIn,_instCacheType = IsInInstance(); _instCacheT=now end
  return _instCacheIn,_instCacheType
end

local function AllowedContext()
  local db = ZaesToolsAnnounceDB
  if db.onlyInGroups and not InGroup() then return false end
  local inInst, instType = GetInstanceInfoCached()
  if db.instanceOnly and not inInst then return false end
  if db.suppressInBG and inInst and (instType=="pvp" or instType=="arena") then return false end
  return true
end

local function PickChannel()
  local db = ZaesToolsAnnounceDB
  local ch = db.channel or "SMART"
  if ch == "SMART" then
    if (GetNumRaidMembers() or 0) > 0 then return "RAID" end
    if (GetNumPartyMembers() or 0) > 0 then return "PARTY" end
    return (db.smartSoloFallback == "EMOTE") and "EMOTE" or "SAY"
  end
  return ch
end

-- Throttling
local lastAnyAt = 0
local lastByKind = { interrupt=0, ccApply=0, ccBreak=0, ccFade=0, oom=0 }
local tkey = {interrupt="t_interrupt", ccApply="t_ccApply", ccBreak="t_ccBreak", ccFade="t_ccFade", oom="t_oom"}
local function Throttle(kind)
  local now = GetTime(); local db = ZaesToolsAnnounceDB
  if (now - lastAnyAt) < (db.throttleSec or 8) then return false end
  if (now - (lastByKind[kind] or 0)) < (db[tkey[kind]] or 0) then return false end
  lastAnyAt, lastByKind[kind] = now, now; return true
end

local function Send(kind, msg)
  if not Throttle(kind) then return end
  if not AllowedContext() then return end
  SendChatMessage(msg, PickChannel())
end

-- 🔧 Robust Token formatter (handles any chars between braces)
local function fmt(template, t)
  return (template:gsub("{(.-)}", function(k)
    if k == "bspell" then
      return t.bspell and (" ("..t.bspell..")") or ""
    end
    return t[k] or ""
  end))
end

-- Healing + OOM
local CLASS_HEALS={
  PRIEST={ ["Flash Heal"]=1,["Greater Heal"]=1,["Binding Heal"]=1,["Prayer of Healing"]=1,["Circle of Healing"]=1,["Renew"]=1,["Penance"]=1,["Prayer of Mending"]=1 },
  PALADIN={ ["Holy Light"]=1,["Flash of Light"]=1,["Holy Shock"]=1,["Lay on Hands"]=1 },
  SHAMAN={ ["Healing Wave"]=1,["Lesser Healing Wave"]=1,["Chain Heal"]=1,["Riptide"]=1,["Earth Shield"]=1 },
  DRUID={ ["Healing Touch"]=1,["Regrowth"]=1,["Rejuvenation"]=1,["Lifebloom"]=1,["Swiftmend"]=1,["Tranquility"]=1,["Nourish"]=1 },
}
local healSpells; local lastSentSpell,lastSentAt,lastOOMAt=nil,0,0
local function OnOOM(spell) local db=ZaesToolsAnnounceDB if not(db.oomEnabled and healSpells and healSpells[spell]) then return end local now=GetTime() if now-lastOOMAt<(db.t_oom or 8) then return end Send("oom",fmt(db.fmt_oom,{ispell=spell})); lastOOMAt=now end

-- CC tracking
local function ccEnabled(n) return ZaesToolsAnnounceDB.ccSpells[n or ""] end
local function ccKey(g,s) return (g or "nil")..":"..(s or "nil") end
local activeCC={}

-- Markers
local ICON_NAMES={[1]="Star",[2]="Circle",[3]="Diamond",[4]="Triangle",[5]="Moon",[6]="Square",[7]="Cross",[8]="Skull"}
local SCAN_UNITS={"target","focus","mouseover","boss1","boss2","boss3","boss4","arena1","arena2","arena3","arena4","arena5"}
local function FindUnitByGUID(g)
  if not g then return end
  for i=1,#SCAN_UNITS do local u=SCAN_UNITS[i] if UnitExists(u) and UnitGUID(u)==g then return u end end
  for i=1,GetNumPartyMembers() do local u="party"..i.."target" if UnitExists(u) and UnitGUID(u)==g then return u end end
  for i=1,GetNumRaidMembers() do local u="raid"..i.."target" if UnitExists(u) and UnitGUID(u)==g then return u end end
end
local function MarkerTokens(g)
  local u=FindUnitByGUID(g)
  if u then local i=GetRaidTargetIndex(u) if i and i>=1 and i<=8 then return "{rt"..i.."} ",ICON_NAMES[i] end end
  return "",""
end
local function ApplyMarkerMode(i,n)
  local m=(ZaesToolsAnnounceDB and ZaesToolsAnnounceDB.markerMode) or "ICON"; local nb=(n~="" and ("["..n.."] ") or "")
  if m=="ICON" then return i,"",i elseif m=="TEXT" then return "",(n~="" and (n.." ") or ""),(n~="" and (n.." ") or "") elseif m=="BOTH" then return i,(n~="" and (n.." ") or ""),(i..nb) else return "","","" end
end

local function announceCC(kind,g,d,s,b,e)
  local i,n=MarkerTokens(g); local mark,markname,markboth=ApplyMarkerMode(i,n); local db=ZaesToolsAnnounceDB
  if kind=="apply" then
    Send("ccApply",fmt(db.fmt_ccApply,{cc=s,target=d,mark=mark,markname=markname,markboth=markboth}))
  elseif kind=="break" then
    Send("ccBreak",fmt(db.fmt_ccBreak,{cc=s,target=d,breaker=b,bspell=e,mark=mark,markname=markname,markboth=markboth}))
  elseif kind=="fade" then
    Send("ccFade",fmt(db.fmt_ccFade,{cc=s,target=d,mark=mark,markname=markname,markboth=markboth}))
  elseif kind=="dispel" then
    Send("ccBreak",fmt(db.fmt_dispel,{cc=s,target=d,breaker=b,mark=mark,markname=markname,markboth=markboth}))
  end
end

-- Combat log
local function OnCLEU(...)
  local _,e,_,sg,sn,_,_,dg,dn=...
  local me=UnitGUID("player")
  if e=="SPELL_INTERRUPT" and ZaesToolsAnnounceDB.interruptsEnabled and sg==me then
    local is,bs=select(13,...),select(16,...) local i,n=MarkerTokens(dg);local mark,markname,markboth=ApplyMarkerMode(i,n)
    Send("interrupt",fmt(ZaesToolsAnnounceDB.fmt_interrupt,{target=dn,bspell=bs,ispell=is,mark=mark,markname=markname,markboth=markboth}))
    return
  end
  if sg==me and e=="SPELL_AURA_APPLIED" then
    local s,a=select(13,...),select(15,...) if a=="DEBUFF" and ccEnabled(s) and ZaesToolsAnnounceDB.ccApplyEnabled then
      activeCC[ccKey(dg,s)]=true; announceCC("apply",dg,dn,s); return
    end
  end
  if e=="SPELL_AURA_BROKEN" or e=="SPELL_AURA_BROKEN_SPELL" then
    local bn=select(13,...) if ccEnabled(bn) and ZaesToolsAnnounceDB.ccBreakEnabled then
      local k=ccKey(dg,bn) if activeCC[k] then local ex=(e=="SPELL_AURA_BROKEN_SPELL") and select(16,...) or nil
        announceCC("break",dg,dn,bn,sn,ex); activeCC[k]=nil end; return
    end
  end
  if e=="SPELL_DISPEL" or e=="SPELL_STOLEN" then
    local rn=select(16,...) if ccEnabled(rn) and ZaesToolsAnnounceDB.ccBreakEnabled then
      local k=ccKey(dg,rn) if activeCC[k] then announceCC("dispel",dg,dn,rn,sn); activeCC[k]=nil end; return
    end
  end
  if e=="SPELL_AURA_REMOVED" then
    local s=select(13,...) if ccEnabled(s) and ZaesToolsAnnounceDB.ccFadeEnabled then
      local k=ccKey(dg,s) if activeCC[k] then announceCC("fade",dg,dn,s); activeCC[k]=nil end; return
    end
  end
end

-- Presets
local PRESETS={
  ["Detailed (Default)"]= {
    fmt_interrupt=">> Interrupted {markboth}{target}'s {bspell} with {ispell} <<",
    fmt_ccApply="[CC] {markboth}{cc} on {target}",
    fmt_ccBreak="[CC Broken] {markboth}{cc} on {target} by {breaker}{bspell}",
    fmt_ccFade="[CC Faded] {markboth}{cc} on {target} ended",
    fmt_dispel="[CC Dispelled] {markboth}{cc} on {target} by {breaker}",
    fmt_oom="** OOM trying to cast {ispell} **",
  },
  ["Short"]= {
    fmt_interrupt="Kick: {mark}{bspell} @ {target}",
    fmt_ccApply="CC: {mark}{cc} @ {target}",
    fmt_ccBreak="CC! {mark}{cc} broke ({breaker}{bspell})",
    fmt_ccFade="CC off: {mark}{cc} @ {target}",
    fmt_dispel="Dispelled: {mark}{cc} @ {target} by {breaker}",
    fmt_oom="OOM: {ispell}",
  },
}
local function ApplyTemplateProfile(p) if not p then return end for k,v in pairs(p) do if type(v)=="string" and ZaesToolsAnnounceDB[k]~=nil then ZaesToolsAnnounceDB[k]=v end end end
ZaesToolsAnnounce_Templates={
  presets=PRESETS,
  loadPresetByName=function(n) ApplyTemplateProfile(PRESETS[n]) end,
  loadCustom=function() local c=ZaesToolsAnnounceDB.customTemplate;if c then ApplyTemplateProfile(c) end end,
  saveCustomFromCurrent=function() ZaesToolsAnnounceDB.customTemplate={ fmt_interrupt=ZaesToolsAnnounceDB.fmt_interrupt, fmt_ccApply=ZaesToolsAnnounceDB.fmt_ccApply, fmt_ccBreak=ZaesToolsAnnounceDB.fmt_ccBreak, fmt_ccFade=ZaesToolsAnnounceDB.fmt_ccFade, fmt_dispel=ZaesToolsAnnounceDB.fmt_dispel, fmt_oom=ZaesToolsAnnounceDB.fmt_oom } end,
  deleteCustom=function() ZaesToolsAnnounceDB.customTemplate=nil end,
}

-- Events
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("UNIT_SPELLCAST_SENT")
f:RegisterEvent("UI_ERROR_MESSAGE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_,e,...)
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

-- Slash commands
SLASH_ZAESTOOLSANNOUNCE1="/zta"; SLASH_ZAESTOOLSANNOUNCE2="/zaes"
SlashCmdList["ZAESTOOLSANNOUNCE"]=function(msg)
  msg=(msg or ""):lower()
  if msg=="" or msg=="opt" or msg=="options" then
    InterfaceOptionsFrame_OpenToCategory("Zaes Tools Announce")
    InterfaceOptionsFrame_OpenToCategory("Zaes Tools Announce")
  elseif msg:find("^addcc%s+") then
    local n=msg:match("^addcc%s+(.+)$")
    if n and n~="" then ZaesToolsAnnounceDB.ccSpells[n]=true; DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZTA|r added CC: "..n) end
  elseif msg:find("^delcc%s+") then
    local n=msg:match("^delcc%s+(.+)$")
    if n and n~="" then ZaesToolsAnnounceDB.ccSpells[n]=nil; DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZTA|r removed CC: "..n) end
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZaesToolsAnnounce|r: /zta options  •  /zta addcc <Name>  •  /zta delcc <Name>")
  end
end

SLASH_ZAESTOOLSANNOUNCE_OPEN1="/ztaopt"
SlashCmdList["ZAESTOOLSANNOUNCE_OPEN"]=function()
  InterfaceOptionsFrame_OpenToCategory("Zaes Tools Announce")
  InterfaceOptionsFrame_OpenToCategory("Zaes Tools Announce")
end
