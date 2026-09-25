local Runtime = _G["Ayije_CDMDev"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local L = Runtime.L
local UI = ns.ConfigUI

local OUTLINE_OPTIONS = {
    { value = "",             label = L["None"] },
    { value = "OUTLINE",      label = L["Outline"] },
    { value = "THICKOUTLINE", label = L["Thick Outline"] },
    { value = "SLUG",         label = L["Slug"] },
}

local function OutlineLabel(value)
    return UI.GetOptionLabel(OUTLINE_OPTIONS, value, L["Outline"])
end

local function SectionHeader(rc, text, yOff)
    local hdr = UI.CreateHeader(rc, text)
    hdr:SetPoint("TOPLEFT", 0, yOff)
    return hdr
end

local function ColorSwatch(rc, label, key, yOff, scope)
    local swatch = UI.CreateColorSwatch(rc, label, key, scope or "STYLE")
    swatch:SetPoint("TOPLEFT", 0, yOff)
    return swatch
end

local function FontDropdown(rc, yOff, page)
    local lbl = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    lbl:SetText(L["Font"])
    lbl:SetPoint("TOPLEFT", 0, yOff)

    local dd = UI.CreateCompactDropdown(rc)
    dd:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
    dd:SetWidth(220)
    dd:SetDefaultText(CDM.db.textFont or CDM.defaults.textFont or "Expressway")
    UI.SetupMediaDropdown(dd, "font",
        function() return CDM.db.textFont end,
        function(name) CDM.db.textFont = name; API:Refresh("STYLE") end,
        function(name) dd:SetDefaultText(name) end)
    page.fontDropdown = dd
end

local function OutlineDropdown(rc, yOff, page)
    local lbl = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    lbl:SetText(L["Font Outline"])
    lbl:SetPoint("TOPLEFT", 0, yOff)

    local dd = UI.CreateCompactDropdown(rc)
    dd:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
    dd:SetWidth(220)
    dd:SetDefaultText(OutlineLabel(CDM.db.textFontOutline))
    UI.SetupValueDropdown(dd, OUTLINE_OPTIONS,
        function() return CDM.db.textFontOutline end,
        function(value, label)
            CDM.db.textFontOutline = value
            dd:SetDefaultText(label)
            API:Refresh("STYLE")
        end)
    page.outlineDropdown = dd
end

local function BuildGlobal(subPage, page)
    local rc, sc = UI.MakeSubPageScroll(subPage, "AyijeCDM_Text_GlobalScrollFrame")
    local yOff = 0

    FontDropdown(rc, yOff, page); yOff = yOff - 55
    OutlineDropdown(rc, yOff, page); yOff = yOff - 65

    SectionHeader(rc, L["Cooldown Timer"], yOff); yOff = yOff - 30
    ColorSwatch(rc, L["Color"], "cooldownColor", yOff); yOff = yOff - 45

    SectionHeader(rc, L["Cooldown Countdown Format"], yOff); yOff = yOff - 30

    local decSlider = UI.CreateModernSliderPrecise(rc,
        L["Show decimals below (seconds, 0 = off)"], 0, 10,
        CDM.db.cooldownDecimalThreshold, 0.5, 1,
        function(v)
            CDM.db.cooldownDecimalThreshold = v
            API:Refresh("STYLE")
        end)
    decSlider:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 60

    SectionHeader(rc, L["Threshold Color"], yOff); yOff = yOff - 30

    local chk = UI.CreateCompactCheckbox(rc, L["Color countdown below threshold"],
        CDM.db.cooldownColorThresholdEnabled,
        function(checked)
            CDM.db.cooldownColorThresholdEnabled = checked
            API:Refresh("STYLE")
        end)
    chk:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 35

    local thrSlider = UI.CreateModernSliderPrecise(rc,
        L["Threshold (seconds)"], 1, 30,
        CDM.db.cooldownColorThreshold, 0.5, 1,
        function(v)
            CDM.db.cooldownColorThreshold = v
            API:Refresh("STYLE")
        end)
    thrSlider:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 60

    ColorSwatch(rc, L["Color"], "cooldownColorThresholdColor", yOff); yOff = yOff - 45
    UI.FinalizeScroll(sc, rc, yOff)
end

local function CreateTextTab(page)
    BuildGlobal(page, page)
end

API:RegisterConfigTab("text", L["Global Text"], CreateTextTab, 5)
