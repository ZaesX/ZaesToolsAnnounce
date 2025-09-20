-- Minimal Options UI for Zaes Tools Announce v2.0.0 (Party / Emote only)
local panel = CreateFrame("Frame", "ZaesToolsAnnounceOptionsPanel", InterfaceOptionsFramePanelContainer)
panel.name = "Zaes Tools Announce"

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Zaes Tools Announce")

local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
desc:SetWidth(540)
desc:SetJustifyH("LEFT")
desc:SetText("Simple announcer. Choose Party (group messages) or Emote (RP style). Other options are baked in.")

-- Dropdown
local dd = CreateFrame("Frame", "ZaesToolsAnnounceChannelDropdown", panel, "UIDropDownMenuTemplate")
dd:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -14, -24)
local title2 = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
title2:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 18, 3)
title2:SetText("Announce Channel")

local CHOICES = { {key="PARTY",label="Party"}, {key="EMOTE",label="Emote (RP style)"} }
local function getIndexByKey(tbl, key) for i,v in ipairs(tbl) do if v.key==key then return i end end return 1 end

UIDropDownMenu_SetWidth(dd, 220)
UIDropDownMenu_Initialize(dd, function(self, level)
  local selected = ZaesToolsAnnounceDB.channel or "PARTY"
  for _, entry in ipairs(CHOICES) do
    local info = UIDropDownMenu_CreateInfo()
    info.text = entry.label
    info.func = function() ZaesToolsAnnounceDB.channel=entry.key; UIDropDownMenu_SetSelectedID(dd,getIndexByKey(CHOICES,entry.key)) end
    info.checked = (entry.key==selected)
    UIDropDownMenu_AddButton(info, level)
  end
end)
UIDropDownMenu_SetSelectedID(dd, getIndexByKey(CHOICES, ZaesToolsAnnounceDB.channel or "PARTY"))

InterfaceOptions_AddCategory(panel)
