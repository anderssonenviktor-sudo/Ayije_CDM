local Runtime = _G["Ayije_CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local L = Runtime.L
local UI = ns.ConfigUI

local SLIDER_LABEL_W = 130
local SLIDER_W = 220
local cooldownTextExpanded = { timer = true, charges = false, utility = false }

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

    local function CollapsibleSection(key, label, width, contentHeight)
        local frame = CreateFrame("Frame", nil, rc)
        frame:SetWidth(width)

        local header = CreateFrame("Button", nil, frame)
        header:SetPoint("TOPLEFT")
        header:SetSize(width, 24)

        local arrow = header:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture("Interface\\AddOns\\Ayije_CDM\\Media\\Textures\\collapse")
        arrow:SetPoint("LEFT", 0, 0)
        arrow:SetSize(14, 14)
        arrow:SetVertexColor(1, 0.82, 0, 1)

        local title = UI.CreateHeader(header, label)
        title:ClearAllPoints()
        title:SetPoint("LEFT", arrow, "RIGHT", 8, 0)

        local highlight = header:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 0.82, 0, 0.08)

        local content = CreateFrame("Frame", nil, frame)
        content:SetPoint("TOPLEFT", 0, -30)
        content:SetSize(width, contentHeight)

        local function UpdateSection()
            local expanded = cooldownTextExpanded[key]
            content:SetShown(expanded)
            arrow:SetRotation(expanded and 0 or math.pi / 2)
            frame:SetHeight(expanded and (30 + contentHeight) or 24)
        end
        header:SetScript("OnClick", function()
            cooldownTextExpanded[key] = not cooldownTextExpanded[key]
            UI.CloseAllDropdownMenus()
            UpdateSection()
        end)
        UpdateSection()
        return frame, content
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

    local timerSection, timer = CollapsibleSection("timer", L["Cooldown Timer"], 550, 193)
    timerSection:SetPoint("TOPLEFT")
    ColorSwatch(timer, L["Color"], "cooldownColor", 0)
    CompactSlider(timer, L["Row 1 Font Size"], "cooldownFontSize", -35, 8, 32)
    CompactSlider(timer, L["Row 2 Font Size"], "essRow2CooldownFontSize", -90, 8, 32)
    CompactSlider(timer, L["Show decimals below"],
        "cooldownDecimalThreshold", -145, 0, 10, true)

    local threshold = CreateFrame("Frame", nil, timer)
    threshold:SetPoint("TOPLEFT", 290, 0)
    threshold:SetSize(260, 193)
    local thresholdHeader = UI.CreateSubHeader(threshold, L["Threshold Color"])
    thresholdHeader:ClearAllPoints()
    thresholdHeader:SetPoint("TOPLEFT")
    local thresholdControls = CreateFrame("Frame", nil, threshold)
    thresholdControls:SetPoint("TOPLEFT", 0, -60)
    thresholdControls:SetSize(260, 100)
    local chk = UI.CreateModernCheckbox(threshold, L["Color countdown below threshold"],
        CDM.db.cooldownColorThresholdEnabled, function(checked)
            CDM.db.cooldownColorThresholdEnabled = checked
            thresholdControls:SetShown(checked)
            API:Refresh("STYLE")
        end)
    chk:SetPoint("TOPLEFT", 0, -25)
    chk:SetWidth(260)
    chk.label:SetWidth(226)
    chk.label:SetJustifyH("LEFT")
    CompactSlider(thresholdControls, L["Threshold (seconds)"],
        "cooldownColorThreshold", 0, 1, 30, true)
    ColorSwatch(thresholdControls, L["Color"], "cooldownColorThresholdColor", -70)
    local function UpdateThresholdControls()
        thresholdControls:SetShown(CDM.db.cooldownColorThresholdEnabled == true)
    end
    subPage:HookScript("OnShow", UpdateThresholdControls)
    UpdateThresholdControls()

    local chargesSection, charges = CollapsibleSection("charges", L["Charges"], 260, 288)
    chargesSection:SetPoint("TOPLEFT", timerSection, "BOTTOMLEFT", 0, -14)
    CompactSlider(charges, L["Row 1 Font Size"], "chargeFontSize", 0, 8, 32)
    CompactSlider(charges, L["Row 2 Font Size"], "essRow2ChargeFontSize", -50, 8, 32)
    ColorSwatch(charges, L["Color"], "chargeColor", -100)
    PositionDropdown(charges, L["Position"], "chargePosition", -135)
    CompactSlider(charges, L["X Offset"], "chargeOffsetX", -190, -50, 50)
    CompactSlider(charges, L["Y Offset"], "chargeOffsetY", -240, -50, 50)

    local utilitySection, utility = CollapsibleSection("utility", L["Utility"], 260, 288)
    utilitySection:SetPoint("TOPLEFT", timerSection, "BOTTOMLEFT", 290, -14)
    CompactSlider(utility, L["Cooldown Font Size"], "utilityCooldownFontSize", 0, 8, 32)
    CompactSlider(utility, L["Charges Font Size"], "utilityChargeFontSize", -50, 8, 32)
    ColorSwatch(utility, L["Color"], "utilityChargeColor", -100)
    PositionDropdown(utility, L["Position"], "utilityChargePosition", -135)
    CompactSlider(utility, L["X Offset"], "utilityChargeOffsetX", -190, -50, 50)
    CompactSlider(utility, L["Y Offset"], "utilityChargeOffsetY", -240, -50, 50)
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
