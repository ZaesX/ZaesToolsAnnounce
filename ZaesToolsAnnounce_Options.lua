-- Options UI (clean & scrollable) for Zaes Tools Announce v1.5.5+
-- Drop-in replacement file: Interface\AddOns\ZaesToolsAnnounce\ZaesToolsAnnounce_Options.lua

local panel = CreateFrame("Frame", "ZaesToolsAnnounceOptionsPanel", InterfaceOptionsFramePanelContainer)
panel.name = "Zaes Tools Announce"

------------------------------------------------------------
-- Scroll container
------------------------------------------------------------
local scroll = CreateFrame("ScrollFrame", "ZTA_Scroll", panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 0, -8)
scroll:SetPoint("BOTTOMRIGHT", -28, 8)

local content = CreateFrame("Frame", "ZTA_ScrollChild", scroll)
content:SetSize(1, 1) -- will grow as children are added
scroll:SetScrollChild(content)

------------------------------------------------------------
-- Small helpers
------------------------------------------------------------
local function Title(parent, text, x, y, template)
  local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", x or 16, y or -16)
  fs:SetText(text)
  return fs
end

local function Note(parent, anchor, text, dy)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, dy or -8)
  fs:SetWidth(560)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

local function GroupBox(parent, label, x, y, w, h)
  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetPoint("TOPLEFT", x, y)
  box:SetSize(w, h)
  if box.SetBackdrop then
    box:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12,
      insets = { left = 6, right = 6, top = 6, bottom = 6 }
    })
  end
  local t = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  t:SetPoint("TOPLEFT", 10, -8)
  t:SetText(label)
  return box, t
end

-- Wrath-safe checkbox (unnamed, make our own label)
local function NewCheckbox(parent, label, tooltip, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  text:SetText(label)
  cb.tooltipText = label
  cb.tooltipRequirement = tooltip
  cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
  return cb
end

-- Unique sliders so we can reference <name>Text/Low/High safely
local __zta_slider_id = 0
local function NewSlider(parent, label, minV, maxV, step, onChanged)
  __zta_slider_id = __zta_slider_id + 1
  local name = "ZTA_Slider"..__zta_slider_id
  local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  _G[name.."Text"]:SetText(label)
  _G[name.."Low"]:SetText(tostring(minV))
  _G[name.."High"]:SetText(tostring(maxV))
  s:SetScript("OnValueChanged", function(self, v)
    v = floor(v + 0.5)
    onChanged(v)
    _G[name.."Text"]:SetText(label.." ("..v..")")
  end)
  return s
end

local function NewEditBox(parent, label, width, initial, onCommit)
  local l = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  l:SetText(label)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetAutoFocus(false)
  eb:SetSize(width, 20)
  eb:SetText(initial or "")
  eb:SetScript("OnEnterPressed", function(self) onCommit(self:GetText()); self:ClearFocus() end)
  eb:SetScript("OnEscapePressed", function(self) self:SetText(initial or ""); self:ClearFocus() end)
  return l, eb
end

-- Dropdown helpers
local function getIndexByKey(tbl, key) for i, v in ipairs(tbl) do if v.key == key then return i end end return 1 end
local function NewDropdown(parent, name, titleText, width, items, getKey, setKey)
  local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
  local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 18, 3)
  title:SetText(titleText)
  UIDropDownMenu_SetWidth(dd, width)
  UIDropDownMenu_Initialize(dd, function(self, level)
    local selected = getKey()
    for _, entry in ipairs(items) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = entry.label
      info.func = function()
        setKey(entry.key)
        UIDropDownMenu_SetSelectedID(dd, getIndexByKey(items, entry.key))
      end
      info.checked = (entry.key == selected)
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  UIDropDownMenu_SetSelectedID(dd, getIndexByKey(items, getKey()))
  return dd
end

------------------------------------------------------------
-- Constants for dropdowns
------------------------------------------------------------
local CHANNELS = {
  { key = "SMART", label = "Smart (Raid > Party > Fallback)" },
  { key = "RAID",  label = "Raid"  },
  { key = "PARTY", label = "Party" },
  { key = "SAY",   label = "Say"   },
  { key = "YELL",  label = "Yell"  },
  { key = "EMOTE", label = "Emote" },
}

local FALLBACKS = {
  { key = "SAY",   label = "Fallback when solo: Say"   },
  { key = "EMOTE", label = "Fallback when solo: Emote" },
}

local MARKER_MODES = {
  { key = "ICON",  label = "Marker: Icon ({rt8})" },
  { key = "TEXT",  label = "Marker: Text (Skull)" },
  { key = "BOTH",  label = "Marker: Icon + [Text]" },
  { key = "NONE",  label = "Marker: None" },
}

------------------------------------------------------------
-- Build content on scroll child
------------------------------------------------------------
local title = Title(content, "Zaes Tools Announce", 16, -16)
local desc  = Note(content, title,
  "Announce to your group when you interrupt, go OOM (only on failed heal), apply CC, when CC breaks (by who/what), or when it fades. Use /zta or /ztaopt.",
  -8)

-- Output
local boxOut = GroupBox(content, "Output", 16, -74, 560, 120)
local ddChan = NewDropdown(
  boxOut, "ZaesToolsAnnounceChannelDropdown", "Announcement Channel", 240, CHANNELS,
  function() return ZaesToolsAnnounceDB.channel or "SMART" end,
  function(v) ZaesToolsAnnounceDB.channel = v end
)
ddChan:SetPoint("TOPLEFT", boxOut, "TOPLEFT", -4, -24)

local ddFallback = NewDropdown(
  boxOut, "ZaesToolsAnnounceFallbackDropdown", "SMART Solo Fallback", 220, FALLBACKS,
  function() return ZaesToolsAnnounceDB.smartSoloFallback or "SAY" end,
  function(v) ZaesToolsAnnounceDB.smartSoloFallback = v end
)
ddFallback:SetPoint("LEFT", ddChan, "RIGHT", 40, 0)

-- Scope
local boxScope = GroupBox(content, "Scope", 16, -204, 560, 110)
local cbGroups = NewCheckbox(boxScope, "Only announce in groups", "If unchecked, messages may use fallback when solo.", function(v) ZaesToolsAnnounceDB.onlyInGroups = v end)
cbGroups:SetPoint("TOPLEFT", boxScope, "TOPLEFT", 12, -28)
local cbInst = NewCheckbox(boxScope, "Instance only", "Only announce inside instances.", function(v) ZaesToolsAnnounceDB.instanceOnly = v end)
cbInst:SetPoint("TOPLEFT", cbGroups, "BOTTOMLEFT", 0, -6)
local cbBG = NewCheckbox(boxScope, "Suppress in BG/Arena", "Silence in battlegrounds and arenas.", function(v) ZaesToolsAnnounceDB.suppressInBG = v end)
cbBG:SetPoint("TOPLEFT", cbInst, "BOTTOMLEFT", 0, -6)

-- Throttles
local boxThr = GroupBox(content, "Throttles (seconds)", 16, -324, 560, 174)
local sGlobal = NewSlider(boxThr, "Global throttle", 0, 30, 1, function(v) ZaesToolsAnnounceDB.throttleSec = v end)
sGlobal:SetPoint("TOPLEFT", boxThr, "TOPLEFT", 16, -34)
local sInt = NewSlider(boxThr, "Interrupt throttle", 0, 20, 1, function(v) ZaesToolsAnnounceDB.t_interrupt = v end)
sInt:SetPoint("TOPLEFT", sGlobal, "BOTTOMLEFT", 0, -28)
local sCCA = NewSlider(boxThr, "CC apply throttle", 0, 20, 1, function(v) ZaesToolsAnnounceDB.t_ccApply = v end)
sCCA:SetPoint("TOPLEFT", sInt, "BOTTOMLEFT", 0, -28)
local col2x = 300
local sCCB = NewSlider(boxThr, "CC break throttle", 0, 20, 1, function(v) ZaesToolsAnnounceDB.t_ccBreak = v end)
sCCB:SetPoint("TOPLEFT", boxThr, "TOPLEFT", col2x, -34)
local sCCF = NewSlider(boxThr, "CC fade throttle", 0, 20, 1, function(v) ZaesToolsAnnounceDB.t_ccFade = v end)
sCCF:SetPoint("TOPLEFT", sCCB, "BOTTOMLEFT", 0, -28)
local sOOM = NewSlider(boxThr, "OOM-on-heal throttle", 0, 30, 1, function(v) ZaesToolsAnnounceDB.t_oom = v end)
sOOM:SetPoint("TOPLEFT", sCCF, "BOTTOMLEFT", 0, -28)

-- Features
local boxFeat = GroupBox(content, "Features", 16, -508, 560, 130)
local cbOOM = NewCheckbox(boxFeat, "Enable OOM-on-heal", "Announce only when a healing spell fails due to mana.", function(v) ZaesToolsAnnounceDB.oomEnabled = v end)
cbOOM:SetPoint("TOPLEFT", boxFeat, "TOPLEFT", 12, -28)
local cbINT = NewCheckbox(boxFeat, "Enable interrupts", "Successful SPELL_INTERRUPT.", function(v) ZaesToolsAnnounceDB.interruptsEnabled = v end)
cbINT:SetPoint("TOPLEFT", cbOOM, "BOTTOMLEFT", 0, -6)
local cbCCA = NewCheckbox(boxFeat, "Announce CC applied", "Your CC lands on a target.", function(v) ZaesToolsAnnounceDB.ccApplyEnabled = v end)
cbCCA:SetPoint("TOPLEFT", cbINT, "BOTTOMLEFT", 0, -6)
local cbCCB = NewCheckbox(boxFeat, "Announce CC broken", "Broken by player or spell.", function(v) ZaesToolsAnnounceDB.ccBreakEnabled = v end)
cbCCB:SetPoint("TOPLEFT", cbCCA, "BOTTOMLEFT", 0, -6)
local cbCCF = NewCheckbox(boxFeat, "Announce CC faded", "Natural timeout of your CC.", function(v) ZaesToolsAnnounceDB.ccFadeEnabled = v end)
cbCCF:SetPoint("TOPLEFT", cbCCB, "BOTTOMLEFT", 0, -6)

-- Marker
local boxMark = GroupBox(content, "Marker Display", 16, -648, 560, 80)
local ddMarker = NewDropdown(
  boxMark, "ZaesToolsAnnounceMarkerModeDropdown", "Marker Display Mode", 260, MARKER_MODES,
  function() return ZaesToolsAnnounceDB.markerMode or "ICON" end,
  function(v) ZaesToolsAnnounceDB.markerMode = v end
)
ddMarker:SetPoint("TOPLEFT", boxMark, "TOPLEFT", -4, -30)

-- Message Formats (bigger box so all fields fit)
local boxFmt = GroupBox(content, "Message Formats (press Enter to save)", 16, -738, 560, 330) -- was 220; now 330
local y = -50
local function addFmt(label, key)
  local L, E = NewEditBox(boxFmt, label, 500, ZaesToolsAnnounceDB[key] or "", function(text) ZaesToolsAnnounceDB[key] = text end)
  L:SetPoint("TOPLEFT", boxFmt, "TOPLEFT", 12, y)
  E:SetPoint("TOPLEFT", boxFmt, "TOPLEFT", 12, y - 18)
  y = y - 44
end
addFmt("Interrupt:", "fmt_interrupt")
addFmt("CC Apply:",  "fmt_ccApply")
addFmt("CC Break:",  "fmt_ccBreak")
addFmt("CC Fade:",   "fmt_ccFade")
addFmt("CC Dispel:", "fmt_dispel")
addFmt("OOM:",       "fmt_oom")

-- CC List (more top padding so first row isn't jammed into the title)
local boxCC = GroupBox(content, "Crowd Control List (toggle individually)", 16, -1080, 560, 300) -- taller
local ROWS = 10
local ccRows = {}

local function RefreshCCList()
  local keys = {}
  for name,_ in pairs(ZaesToolsAnnounceDB.ccSpells) do keys[#keys+1] = name end
  table.sort(keys)
  local total = #keys
  FauxScrollFrame_Update(ZaesToolsAnnounceCCScroll, total, ROWS, 20)
  local offset = FauxScrollFrame_GetOffset(ZaesToolsAnnounceCCScroll)
  for i = 1, ROWS do
    local idx = i + offset
    local row = ccRows[i]
    if idx <= total then
      local name = keys[idx]; row.name = name
      row.text:SetText(name)
      row.check:SetChecked(ZaesToolsAnnounceDB.ccSpells[name] and true or false)
      row:Show()
    else
      row.name = nil
      row:Hide()
    end
  end
end

local scrollCC = CreateFrame("ScrollFrame", "ZaesToolsAnnounceCCScroll", boxCC, "FauxScrollFrameTemplate")
scrollCC:SetPoint("TOPLEFT", boxCC, "TOPLEFT", 10, -44)   -- extra top padding
scrollCC:SetPoint("BOTTOMRIGHT", boxCC, "BOTTOMRIGHT", -28, 10)
scrollCC:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll(self, offset, 20, RefreshCCList) end)

for i = 1, ROWS do
  local row = CreateFrame("Frame", nil, boxCC)
  row:SetSize(520, 20)
  row:SetPoint("TOPLEFT", boxCC, "TOPLEFT", 18, -44 - (i - 1) * 20) -- align with scroll area
  local check = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
  check:SetPoint("LEFT", 0, 0)
  local txt = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  txt:SetPoint("LEFT", check, "RIGHT", 4, 0)
  txt:SetWidth(470)
  txt:SetJustifyH("LEFT")
  check:SetScript("OnClick", function(self) if row.name then ZaesToolsAnnounceDB.ccSpells[row.name] = self:GetChecked() and true or false end end)
  row.check = check
  row.text  = txt
  ccRows[i] = row
end

-- Presets
local boxPres = GroupBox(content, "Template Presets", 16, -1390, 560, 84)
local function GetPresetNames()
  local names = {}
  if ZaesToolsAnnounce_Templates and ZaesToolsAnnounce_Templates.presets then
    for name in pairs(ZaesToolsAnnounce_Templates.presets) do names[#names+1] = name end
  end
  table.sort(names)
  table.insert(names, 1, "Select a preset…")
  table.insert(names, "Custom (Saved)")
  return names
end

local dd = CreateFrame("Frame", "ZaesToolsAnnouncePresetDropdown", boxPres, "UIDropDownMenuTemplate")
dd:SetPoint("TOPLEFT", boxPres, "TOPLEFT", -4, -34)
UIDropDownMenu_SetWidth(dd, 260)

local currentSelectionIndex = 1
local function RefreshPresetDropdown()
  local names = GetPresetNames()
  UIDropDownMenu_Initialize(dd, function(selfMenu, level)
    for i, n in ipairs(names) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = n
      info.func = function() currentSelectionIndex = i; UIDropDownMenu_SetSelectedID(dd, i) end
      info.checked = (i == currentSelectionIndex)
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  UIDropDownMenu_SetSelectedID(dd, currentSelectionIndex)
end
RefreshPresetDropdown()

local btnLoad   = CreateFrame("Button", nil, boxPres, "UIPanelButtonTemplate"); btnLoad:SetSize(80, 22);  btnLoad:SetText("Load")
btnLoad:SetPoint("LEFT", dd, "RIGHT", 8, 0)
local btnSave   = CreateFrame("Button", nil, boxPres, "UIPanelButtonTemplate"); btnSave:SetSize(120, 22); btnSave:SetText("Save as Custom")
btnSave:SetPoint("LEFT", btnLoad, "RIGHT", 6, 0)
local btnDelete = CreateFrame("Button", nil, boxPres, "UIPanelButtonTemplate"); btnDelete:SetSize(80, 22); btnDelete:SetText("Delete")
btnDelete:SetPoint("LEFT", btnSave, "RIGHT", 6, 0)

btnLoad:SetScript("OnClick", function()
  local names = GetPresetNames()
  local choice = names[currentSelectionIndex]
  if not choice or choice == "Select a preset…" then
    DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZaesToolsAnnounce|r: Pick a preset first.")
    return
  end
  if choice == "Custom (Saved)" then
    if ZaesToolsAnnounce_Templates and ZaesToolsAnnounce_Templates.loadCustom then
      ZaesToolsAnnounce_Templates.loadCustom()
      DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZaesToolsAnnounce|r: Loaded Custom template.")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZaesToolsAnnounce|r: No Custom template saved yet.")
    end
  else
    if ZaesToolsAnnounce_Templates and ZaesToolsAnnounce_Templates.loadPresetByName then
      ZaesToolsAnnounce_Templates.loadPresetByName(choice)
      DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZaesToolsAnnounce|r: Loaded preset '"..choice.."'")
    end
  end
  InterfaceOptionsFrame_OpenToCategory("Zaes Tools Announce")
  InterfaceOptionsFrame_OpenToCategory("Zaes Tools Announce")
end)

btnSave:SetScript("OnClick", function()
  if ZaesToolsAnnounce_Templates and ZaesToolsAnnounce_Templates.saveCustomFromCurrent then
    ZaesToolsAnnounce_Templates.saveCustomFromCurrent()
    DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZaesToolsAnnounce|r: Saved current formats as Custom.")
  end
  RefreshPresetDropdown()
  local names = GetPresetNames()
  for i, n in ipairs(names) do if n == "Custom (Saved)" then currentSelectionIndex = i; break end end
  UIDropDownMenu_SetSelectedID(dd, currentSelectionIndex)
end)

btnDelete:SetScript("OnClick", function()
  if ZaesToolsAnnounce_Templates and ZaesToolsAnnounce_Templates.deleteCustom then
    ZaesToolsAnnounce_Templates.deleteCustom()
    DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZaesToolsAnnounce|r: Deleted Custom template.")
  end
  RefreshPresetDropdown()
  currentSelectionIndex = 1
  UIDropDownMenu_SetSelectedID(dd, currentSelectionIndex)
end)

------------------------------------------------------------
-- Initialize / seed values on first show
------------------------------------------------------------
panel:SetScript("OnShow", function(self)
  if self._init then return end
  self._init = true

  -- Seed slider values
  sGlobal:SetValue(ZaesToolsAnnounceDB.throttleSec or 8)
  sInt:SetValue(ZaesToolsAnnounceDB.t_interrupt or 0)
  sCCA:SetValue(ZaesToolsAnnounceDB.t_ccApply or 0)
  sCCB:SetValue(ZaesToolsAnnounceDB.t_ccBreak or 4)
  sCCF:SetValue(ZaesToolsAnnounceDB.t_ccFade or 6)
  sOOM:SetValue(ZaesToolsAnnounceDB.t_oom or 8)

  -- Seed checkboxes
  cbGroups:SetChecked(ZaesToolsAnnounceDB.onlyInGroups)
  cbInst:SetChecked(ZaesToolsAnnounceDB.instanceOnly)
  cbBG:SetChecked(ZaesToolsAnnounceDB.suppressInBG)
  cbOOM:SetChecked(ZaesToolsAnnounceDB.oomEnabled)
  cbINT:SetChecked(ZaesToolsAnnounceDB.interruptsEnabled)
  cbCCA:SetChecked(ZaesToolsAnnounceDB.ccApplyEnabled)
  cbCCB:SetChecked(ZaesToolsAnnounceDB.ccBreakEnabled)
  cbCCF:SetChecked(ZaesToolsAnnounceDB.ccFadeEnabled)

  -- Refresh lists
  RefreshPresetDropdown()
  FauxScrollFrame_OnVerticalScroll(scrollCC, 0, 20, RefreshCCList)
  RefreshCCList()

  -- Ensure scroll child is tall enough for all groups
  content:SetHeight(1480)
  content:SetWidth(600)
end)

InterfaceOptions_AddCategory(panel)
