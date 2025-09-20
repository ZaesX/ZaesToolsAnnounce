-- Options UI for Zaes Tools Announce v1.5.3 (Wrath-safe widgets)
local panel = CreateFrame("Frame", "ZaesToolsAnnounceOptionsPanel", InterfaceOptionsFramePanelContainer)
panel.name = "Zaes Tools Announce"

local function Title(parent, text, x, y, template)
  local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", x or 16, y or -16); fs:SetText(text); return fs
end
local function Note(parent, anchor, text, dy)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, dy or -8)
  fs:SetWidth(540); fs:SetJustifyH("LEFT"); fs:SetText(text); return fs
end

local function NewCheckbox(parent, label, tooltip, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  text:SetText(label)
  cb.tooltipText = label; cb.tooltipRequirement = tooltip
  cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
  return cb
end

local __zta_slider_id = 0
local function NewSlider(parent, label, minV, maxV, step, onChanged)
  __zta_slider_id = __zta_slider_id + 1
  local name = "ZTA_Slider"..__zta_slider_id
  local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  s:SetMinMaxValues(minV, maxV); s:SetValueStep(step)
  _G[name.."Text"]:SetText(label)
  _G[name.."Low"]:SetText(tostring(minV))
  _G[name.."High"]:SetText(tostring(maxV))
  s:SetScript("OnValueChanged", function(self, v)
    v=floor(v+0.5); onChanged(v); _G[name.."Text"]:SetText(label.." ("..v..")")
  end)
  return s
end

local function NewEditBox(parent, label, width, initial, onCommit)
  local l = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal"); l:SetText(label)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate"); eb:SetAutoFocus(false); eb:SetSize(width, 20); eb:SetText(initial or "")
  eb:SetScript("OnEnterPressed", function(self) onCommit(self:GetText()); self:ClearFocus() end)
  eb:SetScript("OnEscapePressed", function(self) self:SetText(initial or ""); self:ClearFocus() end)
  return l, eb
end

local CHANNELS = {
  { key="SMART", label="Smart (Raid > Party > Fallback)" },
  { key="RAID",  label="Raid" },
  { key="PARTY", label="Party" },
  { key="SAY",   label="Say" },
  { key="YELL",  label="Yell" },
  { key="EMOTE", label="Emote" },
}
local function getIndexByKey(tbl, key) for i,v in ipairs(tbl) do if v.key==key then return i end end return 1 end
local function MakeDropdown(parent)
  local dd = CreateFrame("Frame", "ZaesToolsAnnounceChannelDropdown", parent, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -80)
  local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal"); title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 18, 3)
  title:SetText("Announcement Channel")
  UIDropDownMenu_SetWidth(dd, 220)
  UIDropDownMenu_Initialize(dd, function(self, level)
    local selected = ZaesToolsAnnounceDB.channel or "SMART"
    for _, entry in ipairs(CHANNELS) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = entry.label
      info.func = function() ZaesToolsAnnounceDB.channel = entry.key; UIDropDownMenu_SetSelectedID(dd, getIndexByKey(CHANNELS, entry.key)) end
      info.checked = (entry.key == selected)
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  UIDropDownMenu_SetSelectedID(dd, getIndexByKey(CHANNELS, ZaesToolsAnnounceDB.channel or "SMART"))
  return dd
end

local FALLBACKS = {
  { key="SAY",   label="Fallback when solo: Say" },
  { key="EMOTE", label="Fallback when solo: Emote" },
}
local function MakeFallbackDropdown(parent)
  local dd = CreateFrame("Frame", "ZaesToolsAnnounceFallbackDropdown", parent, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", parent, "TOPLEFT", 260, -80)
  local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal"); title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 18, 3)
  title:SetText("SMART Solo Fallback")
  UIDropDownMenu_SetWidth(dd, 220)
  UIDropDownMenu_Initialize(dd, function(self, level)
    local selected = ZaesToolsAnnounceDB.smartSoloFallback or "SAY"
    for _, entry in ipairs(FALLBACKS) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = entry.label
      info.func = function() ZaesToolsAnnounceDB.smartSoloFallback = entry.key; UIDropDownMenu_SetSelectedID(dd, getIndexByKey(FALLBACKS, entry.key)) end
      info.checked = (entry.key == selected)
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  UIDropDownMenu_SetSelectedID(dd, getIndexByKey(FALLBACKS, ZaesToolsAnnounceDB.smartSoloFallback or "SAY"))
  return dd
end

local MARKER_MODES = {
  { key="ICON",  label="Marker: Icon (e.g., {rt8})" },
  { key="TEXT",  label="Marker: Text (e.g., Skull)" },
  { key="BOTH",  label="Marker: Icon + [Text]" },
  { key="NONE",  label="Marker: None" },
}
local function MakeMarkerModeDropdown(parent, anchor, dx, dy)
  local dd = CreateFrame("Frame", "ZaesToolsAnnounceMarkerModeDropdown", parent, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", dx or 0, dy or -8)
  local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 18, 3)
  title:SetText("Marker Display Mode")
  UIDropDownMenu_SetWidth(dd, 240)
  UIDropDownMenu_Initialize(dd, function(self, level)
    local selected = ZaesToolsAnnounceDB.markerMode or "ICON"
    for _, entry in ipairs(MARKER_MODES) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = entry.label
      info.func = function()
        ZaesToolsAnnounceDB.markerMode = entry.key
        UIDropDownMenu_SetSelectedID(dd, getIndexByKey(MARKER_MODES, entry.key))
      end
      info.checked = (entry.key == selected)
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  UIDropDownMenu_SetSelectedID(dd, getIndexByKey(MARKER_MODES, ZaesToolsAnnounceDB.markerMode or "ICON"))
  return dd
end

local ROWS = 10
local ccRows = {}
local function RefreshCCList()
  local keys = {}
  for name,_ in pairs(ZaesToolsAnnounceDB.ccSpells) do keys[#keys+1] = name end
  table.sort(keys)
  local total = #keys
  FauxScrollFrame_Update(ZaesToolsAnnounceCCScroll, total, ROWS, 20)
  local offset = FauxScrollFrame_GetOffset(ZaesToolsAnnounceCCScroll)
  for i=1,ROWS do
    local idx = i+offset
    local row = ccRows[i]
    if idx<=total then
      local name = keys[idx]; row.name = name
      row.text:SetText(name)
      row.check:SetChecked(ZaesToolsAnnounceDB.ccSpells[name] and true or false)
      row:Show()
    else
      row.name=nil; row:Hide()
    end
  end
end
local function BuildCCList(parent, anchor)
  local box = CreateFrame("Frame", "ZaesToolsAnnounceCCBox", parent)
  box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10); box:SetSize(360, 220)
  local title = box:CreateFontString(nil, "ARTWORK", "GameFontNormal"); title:SetPoint("TOPLEFT", 8, -6); title:SetText("Tracked CC (toggle individually)")
  local scroll = CreateFrame("ScrollFrame", "ZaesToolsAnnounceCCScroll", box, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -24); scroll:SetPoint("BOTTOMRIGHT", -28, 8)
  scroll:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll(self, offset, 20, RefreshCCList) end)
  for i=1,ROWS do
    local row = CreateFrame("Frame", nil, box); row:SetSize(320, 20); row:SetPoint("TOPLEFT", 12, -24-(i-1)*20)
    local check = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate"); check:SetPoint("LEFT", 0, 0)
    local txt = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); txt:SetPoint("LEFT", check, "RIGHT", 4, 0); txt:SetWidth(270); txt:SetJustifyH("LEFT")
    check:SetScript("OnClick", function(self) if row.name then ZaesToolsAnnounceDB.ccSpells[row.name] = self:GetChecked() and true or false end end)
    row.check=check; row.text=txt; ccRows[i]=row
  end
  local help = box:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  help:SetPoint("TOPLEFT", box, "TOPRIGHT", 12, -6); help:SetWidth(230); help:SetJustifyH("LEFT")
  help:SetText("Add/remove CC:\n|cff00ff00/zta addcc <Spell Name>|r\n|cff00ff00/zta delcc <Spell Name>|r\nRe-open options to refresh.")
  return box
end

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

local title = Title(panel, "Zaes Tools Announce")
local desc  = Note(panel, title, "Announce to your group when you interrupt, go OOM (only on failed heal), apply CC, when CC breaks (by who/what), or when it fades. Use /zta or /ztaopt.", -8)

panel:SetScript("OnShow", function(self)
  if self._init then RefreshCCList(); return end
  self._init = true

  MakeDropdown(self)
  MakeFallbackDropdown(self)

  local cbGroups = NewCheckbox(self, "Only announce in groups", "If unchecked, messages may use fallback when solo.", function(v) ZaesToolsAnnounceDB.onlyInGroups = v end)
  cbGroups:SetPoint("TOPLEFT", 16, -130); cbGroups:SetChecked(ZaesToolsAnnounceDB.onlyInGroups)
  local cbInst = NewCheckbox(self, "Instance only", "Only announce inside instances (dungeons/raids/scenarios).", function(v) ZaesToolsAnnounceDB.instanceOnly = v end)
  cbInst:SetPoint("TOPLEFT", cbGroups, "BOTTOMLEFT", 0, -6); cbInst:SetChecked(ZaesToolsAnnounceDB.instanceOnly)
  local cbBG = NewCheckbox(self, "Suppress in BG/Arena", "Silence in battlegrounds and arenas.", function(v) ZaesToolsAnnounceDB.suppressInBG = v end)
  cbBG:SetPoint("TOPLEFT", cbInst, "BOTTOMLEFT", 0, -6); cbBG:SetChecked(ZaesToolsAnnounceDB.suppressInBG)

  local sGlobal = NewSlider(self, "Global throttle (sec)", 0, 30, 1, function(v) ZaesToolsAnnounceDB.throttleSec = v end)
  sGlobal:SetPoint("TOPLEFT", cbBG, "BOTTOMLEFT", 0, -26); sGlobal:SetValue(ZaesToolsAnnounceDB.throttleSec or 8)

  local sInt = NewSlider(self, "Interrupt throttle (sec)", 0, 20, 1, function(v) ZaesToolsAnnounceDB.t_interrupt = v end)
  sInt:SetPoint("TOPLEFT", sGlobal, "BOTTOMLEFT", 0, -30); sInt:SetValue(ZaesToolsAnnounceDB.t_interrupt or 0)

  local sCCA = NewSlider(self, "CC apply throttle (sec)", 0, 20, 1, function(v) ZaesToolsAnnounceDB.t_ccApply = v end)
  sCCA:SetPoint("TOPLEFT", sInt, "BOTTOMLEFT", 0, -30); sCCA:SetValue(ZaesToolsAnnounceDB.t_ccApply or 0)

  local sCCB = NewSlider(self, "CC break throttle (sec)", 0, 20, 1, function(v) ZaesToolsAnnounceDB.t_ccBreak = v end)
  sCCB:SetPoint("TOPLEFT", sCCA, "BOTTOMLEFT", 0, -30); sCCB:SetValue(ZaesToolsAnnounceDB.t_ccBreak or 4)

  local sCCF = NewSlider(self, "CC fade throttle (sec)", 0, 20, 1, function(v) ZaesToolsAnnounceDB.t_ccFade = v end)
  sCCF:SetPoint("TOPLEFT", sCCB, "BOTTOMLEFT", 0, -30); sCCF:SetValue(ZaesToolsAnnounceDB.t_ccFade or 6)

  local sOOM = NewSlider(self, "OOM-on-heal throttle (sec)", 0, 30, 1, function(v) ZaesToolsAnnounceDB.t_oom = v end)
  sOOM:SetPoint("TOPLEFT", sCCF, "BOTTOMLEFT", 0, -30); sOOM:SetValue(ZaesToolsAnnounceDB.t_oom or 8)

  local cbOOM = NewCheckbox(self, "Enable OOM-on-heal", "Announce only when a healing spell fails due to mana.", function(v) ZaesToolsAnnounceDB.oomEnabled = v end)
  cbOOM:SetPoint("TOPLEFT", 420, -230); cbOOM:SetChecked(ZaesToolsAnnounceDB.oomEnabled)

  local cbINT = NewCheckbox(self, "Enable interrupts", "Successful SPELL_INTERRUPT.", function(v) ZaesToolsAnnounceDB.interruptsEnabled = v end)
  cbINT:SetPoint("TOPLEFT", cbOOM, "BOTTOMLEFT", 0, -6); cbINT:SetChecked(ZaesToolsAnnounceDB.interruptsEnabled)

  local cbCCA = NewCheckbox(self, "Announce CC applied", "Your CC lands on a target.", function(v) ZaesToolsAnnounceDB.ccApplyEnabled = v end)
  cbCCA:SetPoint("TOPLEFT", cbINT, "BOTTOMLEFT", 0, -6); cbCCA:SetChecked(ZaesToolsAnnounceDB.ccApplyEnabled)

  local cbCCB = NewCheckbox(self, "Announce CC broken", "Broken by player or spell.", function(v) ZaesToolsAnnounceDB.ccBreakEnabled = v end)
  cbCCB:SetPoint("TOPLEFT", cbCCA, "BOTTOMLEFT", 0, -6); cbCCB:SetChecked(ZaesToolsAnnounceDB.ccBreakEnabled)

  local cbCCF = NewCheckbox(self, "Announce CC faded", "Natural timeout of your CC.", function(v) ZaesToolsAnnounceDB.ccFadeEnabled = v end)
  cbCCF:SetPoint("TOPLEFT", cbCCB, "BOTTOMLEFT", 0, -6); cbCCF:SetChecked(ZaesToolsAnnounceDB.ccFadeEnabled)

  MakeMarkerModeDropdown(self, cbCCF, 0, -14)

  local secFmt = Title(self, "Message Formats (press Enter to save)", 420, -370, "GameFontNormal")
  local y = -390
  local function addFmt(label, key)
    local L, E = NewEditBox(self, label, 350, ZaesToolsAnnounceDB[key] or "", function(text) ZaesToolsAnnounceDB[key] = text end)
    L:SetPoint("TOPLEFT", 420, y); E:SetPoint("TOPLEFT", 420, y-18)
    y = y - 48
  end
  addFmt("Interrupt:", "fmt_interrupt")
  addFmt("CC Apply:",  "fmt_ccApply")
  addFmt("CC Break:",  "fmt_ccBreak")
  addFmt("CC Fade:",   "fmt_ccFade")
  addFmt("CC Dispel:", "fmt_dispel")
  addFmt("OOM:",       "fmt_oom")

  local ccTitle = Title(self, "Crowd Control List", 16, -370, "GameFontNormal")
  BuildCCList(self, ccTitle)
  RefreshCCList()

  local presetsTitle = Title(self, "Template Presets", 420, y-6, "GameFontNormal")
  local dd = CreateFrame("Frame", "ZaesToolsAnnouncePresetDropdown", self, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", presetsTitle, "BOTTOMLEFT", -2, -6)
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

  local btnLoad  = CreateFrame("Button", nil, self, "UIPanelButtonTemplate"); btnLoad:SetSize(80, 22);  btnLoad:SetText("Load")
  btnLoad:SetPoint("LEFT", dd, "RIGHT", 8, 0)
  local btnSave  = CreateFrame("Button", nil, self, "UIPanelButtonTemplate"); btnSave:SetSize(120, 22); btnSave:SetText("Save as Custom")
  btnSave:SetPoint("LEFT", btnLoad, "RIGHT", 6, 0)
  local btnDelete= CreateFrame("Button", nil, self, "UIPanelButtonTemplate"); btnDelete:SetSize(80, 22); btnDelete:SetText("Delete")
  btnDelete:SetPoint("LEFT", btnSave, "RIGHT", 6, 0)

  btnLoad:SetScript("OnClick", function()
    local names = GetPresetNames(); local choice = names[currentSelectionIndex]
    if not choice or choice == "Select a preset…" then
      DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZaesToolsAnnounce|r: Pick a preset first.")
      return
    end
    if choice == "Custom (Saved)" then
      if ZaesToolsAnnounce_Templates and ZaesToolsAnnounce_Templates.loadCustom then
        ZaesToolsAnnounce_Templates.loadCustom(); DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZaesToolsAnnounce|r: Loaded Custom template.")
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZaesToolsAnnounce|r: No Custom template saved yet.")
      end
    else
      if ZaesToolsAnnounce_Templates and ZaesToolsAnnounce_Templates.loadPresetByName then
        ZaesToolsAnnounce_Templates.loadPresetByName(choice); DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZaesToolsAnnounce|r: Loaded preset '"..choice.."'")
      end
    end
    InterfaceOptionsFrame_OpenToCategory("Zaes Tools Announce")
    InterfaceOptionsFrame_OpenToCategory("Zaes Tools Announce")
  end)

  btnSave:SetScript("OnClick", function()
    if ZaesToolsAnnounce_Templates and ZaesToolsAnnounce_Templates.saveCustomFromCurrent then
      ZaesToolsAnnounce_Templates.saveCustomFromCurrent(); DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZaesToolsAnnounce|r: Saved current formats as Custom.")
    end
    RefreshPresetDropdown(); local names = GetPresetNames()
    for i, n in ipairs(names) do if n == "Custom (Saved)" then currentSelectionIndex = i; break end end
    UIDropDownMenu_SetSelectedID(dd, currentSelectionIndex)
  end)

  btnDelete:SetScript("OnClick", function()
    if ZaesToolsAnnounce_Templates and ZaesToolsAnnounce_Templates.deleteCustom then
      ZaesToolsAnnounce_Templates.deleteCustom(); DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99ZaesToolsAnnounce|r: Deleted Custom template.")
    end
    RefreshPresetDropdown(); currentSelectionIndex = 1; UIDropDownMenu_SetSelectedID(dd, currentSelectionIndex)
  end)
end)

InterfaceOptions_AddCategory(panel)
