local Runtime = _G["Ayije_CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local L = Runtime.L
local UI = ns.ConfigUI

local SLIDER_LABEL_W = 130
local SLIDER_W = 220

local function SetDB(key, scope)
    return function(v)
        CDM.db[key] = v
        API:Refresh(scope or "STYLE")
    end
end

local function SectionHeader(rc, text, yOff)
    local hdr = UI.CreateHeader(rc, text)
    hdr:SetPoint("TOPLEFT", 0, yOff)
    return hdr
end

local function Slider(page, rc, label, minV, maxV, key, yOff, defaultVal, scope)
    local initial = CDM.db[key]
    if initial == nil then initial = CDM.defaults[key] end
    if initial == nil then initial = defaultVal or 0 end
    local slider = UI.CreateModernSlider(rc, label, minV, maxV, initial, SetDB(key, scope),
        SLIDER_LABEL_W, SLIDER_W)
    slider:SetPoint("TOPLEFT", 0, yOff)
    page.controls[key] = slider
    return slider
end

local function ColorSwatch(rc, label, key, yOff, scope)
    local swatch = UI.CreateColorSwatch(rc, label, key, scope or "STYLE")
    swatch:SetPoint("TOPLEFT", 0, yOff)
    return swatch
end

local function PositionDropdown(rc, label, key, yOff, positions)
    local lbl = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    lbl:SetText(label)
    lbl:SetPoint("TOPLEFT", 0, yOff)

    local dd = CreateFrame("DropdownButton", nil, rc, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
    dd:SetWidth(180)
    dd:SetDefaultText(CDM.db[key] or CDM.defaults[key] or "CENTER")
    UI.SetupPositionDropdown(dd,
        function() return CDM.db[key] end,
        function(pos)
            CDM.db[key] = pos
            dd:SetDefaultText(pos)
            API:Refresh("STYLE")
        end,
        positions)
    return dd
end

local function BuildCooldownText(subPage, page)
    local divider = subPage:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOP", subPage, "TOP", 0, 0)

    local rc = CreateFrame("Frame", nil, subPage)
    rc:SetPoint("TOPLEFT", 30, -15)
    rc:SetPoint("BOTTOMRIGHT", -20, 10)

    local function Column(x, y)
        local frame = CreateFrame("Frame", nil, rc)
        frame:SetPoint("TOPLEFT", x, y)
        frame:SetSize(260, 310)
        return frame
    end

    local function CompactSlider(parent, label, key, y, minV, maxV, precise)
        local slider
        if precise then
            slider = UI.CreateModernSliderPrecise(parent, label, minV, maxV,
                CDM.db[key], 0.5, 1, SetDB(key))
        else
            slider = UI.CreateModernSlider(parent, label, minV, maxV,
                CDM.db[key], SetDB(key))
        end
        slider:SetSize(260, 48)
        slider:SetPoint("TOPLEFT", 0, y)
        slider.Label:ClearAllPoints()
        slider.Label:SetPoint("TOPLEFT")
        slider.Label:SetWidth(205)
        slider.Slider:ClearAllPoints()
        slider.Slider:SetPoint("BOTTOMLEFT", 0, 0)
        slider.Slider:SetWidth(260)
        slider.Input:ClearAllPoints()
        slider.Input:SetPoint("TOPRIGHT")
        page.controls[key] = slider
        return slider
    end

    local timer = Column(0, 0)
    SectionHeader(timer, L["Cooldown Timer"], 0)
    ColorSwatch(timer, L["Color"], "cooldownColor", -25)
    CompactSlider(timer, L["Row 1 Font Size"], "cooldownFontSize", -60, 8, 32)
    CompactSlider(timer, L["Row 2 Font Size"], "essRow2CooldownFontSize", -115, 8, 32)
    CompactSlider(timer, L["Show decimals below"],
        "cooldownDecimalThreshold", -170, 0, 10, true)

    local threshold = Column(290, 0)
    SectionHeader(threshold, L["Threshold Color"], 0)
    local chk = UI.CreateModernCheckbox(threshold, L["Color countdown below threshold"],
        CDM.db.cooldownColorThresholdEnabled, SetDB("cooldownColorThresholdEnabled"))
    chk:SetPoint("TOPLEFT", 0, -25)
    chk:SetWidth(260)
    chk.label:SetWidth(226)
    chk.label:SetJustifyH("LEFT")
    CompactSlider(threshold, L["Threshold (seconds)"],
        "cooldownColorThreshold", -60, 1, 30, true)
    ColorSwatch(threshold, L["Color"], "cooldownColorThresholdColor", -130)

    local charges = Column(0, -235)
    SectionHeader(charges, L["Charges"], 0)
    CompactSlider(charges, L["Font Size"], "chargeFontSize", -30, 8, 32)
    CompactSlider(charges, L["Font size row 2"], "essRow2ChargeFontSize", -80, 8, 32)
    ColorSwatch(charges, L["Color"], "chargeColor", -130)
    PositionDropdown(charges, L["Position"], "chargePosition", -165)
    CompactSlider(charges, L["X Offset"], "chargeOffsetX", -220, -50, 50)
    CompactSlider(charges, L["Y Offset"], "chargeOffsetY", -270, -50, 50)

    local utility = Column(290, -235)
    SectionHeader(utility, L["Utility"], 0)
    CompactSlider(utility, L["Cooldown Font Size"], "utilityCooldownFontSize", -30, 8, 32)
    CompactSlider(utility, L["Charges Font Size"], "utilityChargeFontSize", -80, 8, 32)
    ColorSwatch(utility, L["Color"], "utilityChargeColor", -130)
    PositionDropdown(utility, L["Position"], "utilityChargePosition", -165)
    CompactSlider(utility, L["X Offset"], "utilityChargeOffsetX", -220, -50, 50)
    CompactSlider(utility, L["Y Offset"], "utilityChargeOffsetY", -270, -50, 50)
end

ns._CreateCooldownTextPanel = BuildCooldownText

local function BuildBuffIcons(subPage, page)
    local divider = subPage:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOP", subPage, "TOP", 0, 0)

    local rc = CreateFrame("Frame", nil, subPage)
    rc:SetPoint("TOPLEFT", 30, -15)
    rc:SetPoint("BOTTOMRIGHT", -20, 10)
    local yOff = 0

    SectionHeader(rc, L["Cooldown Timer"], yOff); yOff = yOff - 30
    Slider(page, rc, L["Font Size"], 8, 32, "buffCooldownFontSize", yOff, 15); yOff = yOff - 60
    ColorSwatch(rc, L["Color"], "buffCooldownColor", yOff); yOff = yOff - 45

    SectionHeader(rc, L["Stacks (Charges)"], yOff); yOff = yOff - 30
    Slider(page, rc, L["Font Size"], 8, 32, "countFontSize", yOff, 15); yOff = yOff - 60
    ColorSwatch(rc, L["Color"], "countColor", yOff); yOff = yOff - 45
    PositionDropdown(rc, L["Position"], "countPositionMain", yOff); yOff = yOff - 60
    Slider(page, rc, L["X Offset"], -20, 20, "countOffsetXMain", yOff, 0); yOff = yOff - 50
    Slider(page, rc, L["Y Offset"], -20, 20, "countOffsetYMain", yOff, 4); yOff = yOff - 50
end

ns._CreateBuffTextPanel = BuildBuffIcons
