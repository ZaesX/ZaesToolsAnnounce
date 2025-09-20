-- Zaes Tools Announce v2.0.0 (Simple) for WotLK 3.3.5
local ADDON_NAME = ...
ZaesToolsAnnounceDB = ZaesToolsAnnounceDB or {}

local CreateFrame, UnitGUID, UnitExists, GetRaidTargetIndex =
      CreateFrame, UnitGUID, UnitExists, GetRaidTargetIndex
local GetNumPartyMembers, GetNumRaidMembers, SendChatMessage =
      GetNumPartyMembers, GetNumRaidMembers, SendChatMessage
local IsInInstance, GetTime, UnitClass, UnitCastingInfo =
      IsInInstance, GetTime, UnitClass, UnitCastingInfo
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo

local f = CreateFrame("Frame")

-- ================== Defaults ==================
local defaults = {
  channel = "PARTY",            -- PARTY or EMOTE
  onlyInGroups = true,
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

  markerMode = "BOTH",

  fmt_interrupt = ">> Interrupted {markboth}{target}'s{bspell} with {ispell} <<",
  fmt_ccApply   = "[CC] {markboth}{cc} on {target}",
  fmt_ccBreak   = "[CC Broken] {markboth}{cc} on {target} by {breaker}{bspell}",
  fmt_ccFade    = "[CC Faded] {markboth}{cc} on {target} ended",
  fmt_dispel    = "[CC Dispelled] {markboth}{cc} on {target} by {breaker}",
  fmt_oom       = "** OOM trying to cast {ispell} **",

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
local function PickChannel() return (ZaesToolsAnnounceDB.channel=="EMOTE") and "EMOTE" or "PARTY" end

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

local function Send(kind, msg)
  if not Throttle(kind) then return end
  if not AllowedContext() then return end
  SendChatMessage(msg, PickChannel())
end

-- Heals + OOM
local CLASS_HEALS={ PRIEST={["Flash Heal"]=1}, PALADIN={["Holy Light"]=1}, SHAMAN={["Healing Wave"]=1}, DRUID={["Healing Touch"]=1} }
local healSpells; local lastSentSpell,lastSentAt,lastOOMAt=nil,0,0
local function OnOOM(spell)
  local db=ZaesToolsAnnounceDB if not(db.oomEnabled and healSpells and healSpells[spell]) then return end
  local now=GetTime() if now-lastOOMAt<(db.t_oom or 8) then return end
  local player=UnitName("player") or "I"; local tokens={ispell=spell,player=player}
  local text=(PickChannel()=="EMOTE") and fmt(db.rp_oom,tokens) or fmt(db.fmt_oom,tokens)
  Send("oom",text); lastOOMAt=now
end

-- CC + Interrupts
local function ccEnabled(n) return ZaesToolsAnnounceDB.ccSpells[n or ""] end
local activeCC={}

local ICON_NAMES={[1]="Star",[2]="Circle",[3]="Diamond",[4]="Triangle",[5]="Moon",[6]="Square",[7]="Cross",[8]="Skull"}
local function MarkerTokens(g) local i=GetRaidTargetIndex("target"); return (i and "{rt"..i.."} " or ""), ICON_NAMES[i] or "" end
local function ApplyMarkerMode(i,n) return i,(n~="" and (n.." ") or ""),i.."["..n.."] " end

local function announce(kind,dn,sn,bn,ex,dg)
  local i,n=MarkerTokens(dg); local mark,markname,markboth=ApplyMarkerMode(i,n)
  local db=ZaesToolsAnnounceDB; local player=UnitName("player") or "I"
  local tokens={cc=sn,target=dn,breaker=bn,bspell=ex,mark=mark,markname=markname,markboth=markboth,player=player}
  local useRP=(PickChannel()=="EMOTE")
  local msg
  if kind=="apply" then msg=fmt(useRP and db.rp_ccApply or db.fmt_ccApply,tokens)
  elseif kind=="break" then msg=fmt(useRP and db.rp_ccBreak or db.fmt_ccBreak,tokens)
  elseif kind=="fade"  then msg=fmt(useRP and db.rp_ccFade  or db.fmt_ccFade ,tokens)
  elseif kind=="dispel"then msg=fmt(useRP and db.rp_dispel or db.fmt_dispel,tokens) end
  if msg then Send("cc"..kind,msg) end
end

local function OnCLEU(...)
  local _,e,_,sg,sn,_,_,dg,dn=...
  local me=UnitGUID("player")
  if e=="SPELL_INTERRUPT" and sg==me and ZaesToolsAnnounceDB.interruptsEnabled then
    local is,bs=select(13,...),select(16,...)
    local i,n=MarkerTokens(dg); local mark,markname,markboth=ApplyMarkerMode(i,n)
    local player=UnitName("player") or "I"
    local tokens={target=dn,bspell=bs,ispell=is,mark=mark,markname=markname,markboth=markboth,player=player}
    local msg=(PickChannel()=="EMOTE") and fmt(ZaesToolsAnnounceDB.rp_interrupt,tokens) or fmt(ZaesToolsAnnounceDB.fmt_interrupt,tokens)
    Send("interrupt",msg)
  end
end

-- Events
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("UI_ERROR_MESSAGE")
f:SetScript("OnEvent",function(_,e,...)
  if e=="ADDON_LOADED" then local n=... if n==ADDON_NAME then applyDefaults(ZaesToolsAnnounceDB,defaults) end
  elseif e=="PLAYER_LOGIN" then local _,c=UnitClass("player"); healSpells=CLASS_HEALS[c] or {}
  elseif e=="COMBAT_LOG_EVENT_UNFILTERED" then OnCLEU(CombatLogGetCurrentEventInfo())
  elseif e=="UI_ERROR_MESSAGE" then local m=... if type(m)=="string" and m:lower():find("not enough mana") then OnOOM(lastSentSpell) end end
end)

-- Slash to open options
SLASH_ZAESTOOLSANNOUNCE1="/zta"
SlashCmdList["ZAESTOOLSANNOUNCE"]=function() InterfaceOptionsFrame_OpenToCategory("Zaes Tools Announce"); InterfaceOptionsFrame_OpenToCategory("Zaes Tools Announce") end
