local Runtime = _G["Ayije_CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns.ConfigUI
local L = Runtime.L


local glowTypeOptions = {
    { value = "pixel", label = L["Pixel Glow"] },
    { value = "autocast", label = L["Autocast Glow"] },
    { value = "button", label = L["Button Glow"] },
    { value = "proc", label = L["Proc Glow"] },
    { value = "gcd", label = L["GCD"] },
    { value = "shape", label = L["Shape Glow"] },
}

local glowColorOptions = {
    { value = "default", label = L["Default"] },
    { value = "class", label = L["Class Color"] },
    { value = "custom", label = L["Custom"] },
}

local function SliderValueToAutocastScale(sliderValue)
    return 1 + ((sliderValue - 1) * 0.25)
end

local function AutocastScaleToSliderValue(scale)
    local normalized = ((scale or 1) - 1) / 0.25
    local sliderValue = math.floor(normalized + 0.5) + 1
    return math.max(1, math.min(9, sliderValue))
end

local function BuildGlowSettings(page, onHeightChanged)
    local scrollChild = page
    local typeSections = {}
    local UpdateScrollHeight
    local function UpdateTypeSections(selectedType)
        for typeId, section in pairs(typeSections) do
            section:SetShown(typeId == selectedType)
        end
        if UpdateScrollHeight then UpdateScrollHeight() end
    end

    local mainHeader = UI.CreateHeader(scrollChild, L["Glow Settings"])
    mainHeader:SetPoint("TOPLEFT", 0, 0)

    local lblType = scrollChild:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    lblType:SetText(L["Glow Type"])
    lblType:SetPoint("TOPLEFT", mainHeader, "BOTTOMLEFT", 0, -15)

    local ddType = CreateFrame("DropdownButton", nil, scrollChild, "WowStyle1DropdownTemplate")
    ddType:SetPoint("TOPLEFT", lblType, "BOTTOMLEFT", 0, -10)
    ddType:SetWidth(200)

    ddType:SetDefaultText(UI.GetOptionLabel(glowTypeOptions, CDM.db.glowType or "proc", L["Proc Glow"]))

    UI.SetupValueDropdown(
        ddType,
        glowTypeOptions,
        function() return CDM.db.glowType or "proc" end,
        function(value, label)
            CDM.db.glowType = value
            ddType:SetDefaultText(label)
            UpdateTypeSections(value)
            API:Refresh("STYLE")
        end
    )
    page.typeDropdown = ddType

    local colorLabel = scrollChild:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    colorLabel:SetText(L["Glow Color"])
    colorLabel:SetPoint("TOPLEFT", ddType, "BOTTOMLEFT", 0, -15)

    local ddColor = CreateFrame("DropdownButton", nil, scrollChild, "WowStyle1DropdownTemplate")
    ddColor:SetPoint("TOPLEFT", colorLabel, "BOTTOMLEFT", 0, -10)
    ddColor:SetWidth(200)
    ddColor:SetDefaultText(UI.GetOptionLabel(glowColorOptions, CDM.db.glowColorMode, L["Default"]))

    local colorPicker = UI.CreateColorSwatch(scrollChild, L["Custom Color"], "glowColor", "STYLE")
    colorPicker:SetPoint("TOPLEFT", ddColor, "BOTTOMLEFT", 0, -10)
    colorPicker:SetShown(CDM.db.glowColorMode == "custom")
    page.colorPicker = colorPicker
    page.colorModeDropdown = ddColor
    UI.SetupValueDropdown(
        ddColor,
        glowColorOptions,
        function() return CDM.db.glowColorMode or "default" end,
        function(value, label)
            CDM.db.glowColorMode = value
            ddColor:SetDefaultText(label)
            colorPicker:SetShown(value == "custom")
            API:Refresh("STYLE")
        end
    )

    local sectionAnchor = colorPicker

    local pixelSection = CreateFrame("Frame", nil, scrollChild)
    pixelSection:SetPoint("TOPLEFT", sectionAnchor, "BOTTOMLEFT", 0, -15)
    pixelSection:SetSize(460, 300)
    typeSections["pixel"] = pixelSection

    local pixelHeader = UI.CreateSubHeader(pixelSection, L["Pixel Glow Settings"])
    pixelHeader:SetPoint("TOPLEFT", 0, 0)

    page.controls.pixelLines = UI.CreateModernSlider(
        pixelSection, L["Lines"], 1, 20, CDM.db.glowPixelLines or 8,
        function(v) CDM.db.glowPixelLines = v; API:Refresh("STYLE") end
    )
    page.controls.pixelLines:SetPoint("TOPLEFT", pixelHeader, "BOTTOMLEFT", 0, -15)

    page.controls.pixelFrequency = UI.CreateModernSliderPrecise(
        pixelSection, L["Frequency"], -2, 2, CDM.db.glowPixelFrequency or 0.2, 0.05, 2,
        function(v) CDM.db.glowPixelFrequency = v; API:Refresh("STYLE") end
    )
    page.controls.pixelFrequency:SetPoint("TOPLEFT", page.controls.pixelLines, "BOTTOMLEFT", 0, -10)

    page.controls.pixelLength = UI.CreateModernSlider(
        pixelSection, L["Length (0=auto)"], 0, 20, CDM.db.glowPixelLength or 0,
        function(v) CDM.db.glowPixelLength = v; API:Refresh("STYLE") end
    )
    page.controls.pixelLength:SetPoint("TOPLEFT", page.controls.pixelFrequency, "BOTTOMLEFT", 0, -10)

    page.controls.pixelThickness = UI.CreateModernSlider(
        pixelSection, L["Thickness"], 1, 10, CDM.db.glowPixelThickness or 2,
        function(v) CDM.db.glowPixelThickness = v; API:Refresh("STYLE") end
    )
    page.controls.pixelThickness:SetPoint("TOPLEFT", page.controls.pixelLength, "BOTTOMLEFT", 0, -10)

    page.controls.pixelXOffset = UI.CreateModernSlider(
        pixelSection, L["X Offset"], -20, 20, CDM.db.glowPixelXOffset or 0,
        function(v) CDM.db.glowPixelXOffset = v; API:Refresh("STYLE") end
    )
    page.controls.pixelXOffset:SetPoint("TOPLEFT", page.controls.pixelThickness, "BOTTOMLEFT", 0, -10)

    page.controls.pixelYOffset = UI.CreateModernSlider(
        pixelSection, L["Y Offset"], -20, 20, CDM.db.glowPixelYOffset or 0,
        function(v) CDM.db.glowPixelYOffset = v; API:Refresh("STYLE") end
    )
    page.controls.pixelYOffset:SetPoint("TOPLEFT", page.controls.pixelXOffset, "BOTTOMLEFT", 0, -10)

    page.controls.pixelBorder = UI.CreateModernCheckbox(
        pixelSection,
        L["Border"],
        CDM.db.glowPixelBorder or false,
        function(checked)
            CDM.db.glowPixelBorder = checked
            API:Refresh("STYLE")
        end
    )
    page.controls.pixelBorder:SetPoint("TOPLEFT", page.controls.pixelYOffset, "BOTTOMLEFT", 0, -15)

    local autocastSection = CreateFrame("Frame", nil, scrollChild)
    autocastSection:SetPoint("TOPLEFT", sectionAnchor, "BOTTOMLEFT", 0, -15)
    autocastSection:SetSize(460, 250)
    autocastSection:Hide()
    typeSections["autocast"] = autocastSection

    local autocastHeader = UI.CreateSubHeader(autocastSection, L["Autocast Glow Settings"])
    autocastHeader:SetPoint("TOPLEFT", 0, 0)

    page.controls.autocastParticles = UI.CreateModernSlider(
        autocastSection, L["Particles"], 1, 16, CDM.db.glowAutocastParticles or 4,
        function(v) CDM.db.glowAutocastParticles = v; API:Refresh("STYLE") end
    )
    page.controls.autocastParticles:SetPoint("TOPLEFT", autocastHeader, "BOTTOMLEFT", 0, -15)

    page.controls.autocastFrequency = UI.CreateModernSliderPrecise(
        autocastSection, L["Frequency"], -2, 2, CDM.db.glowAutocastFrequency or 0.2, 0.05, 2,
        function(v) CDM.db.glowAutocastFrequency = v; API:Refresh("STYLE") end
    )
    page.controls.autocastFrequency:SetPoint("TOPLEFT", page.controls.autocastParticles, "BOTTOMLEFT", 0, -10)

    page.controls.autocastScale = UI.CreateModernSlider(
        autocastSection, L["Scale"], 1, 9, AutocastScaleToSliderValue(CDM.db.glowAutocastScale or 1),
        function(v)
            CDM.db.glowAutocastScale = SliderValueToAutocastScale(v)
            API:Refresh("STYLE")
        end
    )
    page.controls.autocastScale:SetPoint("TOPLEFT", page.controls.autocastFrequency, "BOTTOMLEFT", 0, -10)

    page.controls.autocastXOffset = UI.CreateModernSlider(
        autocastSection, L["X Offset"], -20, 20, CDM.db.glowAutocastXOffset or 0,
        function(v) CDM.db.glowAutocastXOffset = v; API:Refresh("STYLE") end
    )
    page.controls.autocastXOffset:SetPoint("TOPLEFT", page.controls.autocastScale, "BOTTOMLEFT", 0, -10)

    page.controls.autocastYOffset = UI.CreateModernSlider(
        autocastSection, L["Y Offset"], -20, 20, CDM.db.glowAutocastYOffset or 0,
        function(v) CDM.db.glowAutocastYOffset = v; API:Refresh("STYLE") end
    )
    page.controls.autocastYOffset:SetPoint("TOPLEFT", page.controls.autocastXOffset, "BOTTOMLEFT", 0, -10)

    local buttonSection = CreateFrame("Frame", nil, scrollChild)
    buttonSection:SetPoint("TOPLEFT", sectionAnchor, "BOTTOMLEFT", 0, -15)
    buttonSection:SetSize(460, 100)
    buttonSection:Hide()
    typeSections["button"] = buttonSection

    local buttonHeader = UI.CreateSubHeader(buttonSection, L["Button Glow Settings"])
    buttonHeader:SetPoint("TOPLEFT", 0, 0)

    page.controls.buttonFrequency = UI.CreateModernSlider(
        buttonSection, L["Frequency (0=default)"], 0, 100, math.floor((CDM.db.glowButtonFrequency or 0) * 100),
        function(v) CDM.db.glowButtonFrequency = v / 100; API:Refresh("STYLE") end
    )
    page.controls.buttonFrequency:SetPoint("TOPLEFT", buttonHeader, "BOTTOMLEFT", 0, -15)

    local procSection = CreateFrame("Frame", nil, scrollChild)
    procSection:SetPoint("TOPLEFT", sectionAnchor, "BOTTOMLEFT", 0, -15)
    procSection:SetSize(460, 200)
    procSection:Hide()
    typeSections["proc"] = procSection

    local procHeader = UI.CreateSubHeader(procSection, L["Proc Glow Settings"])
    procHeader:SetPoint("TOPLEFT", 0, 0)

    page.controls.procDuration = UI.CreateModernSlider(
        procSection, L["Duration (x10)"], 1, 50, math.floor((CDM.db.glowProcDuration or 1) * 10),
        function(v) CDM.db.glowProcDuration = v / 10; API:Refresh("STYLE") end
    )
    page.controls.procDuration:SetPoint("TOPLEFT", procHeader, "BOTTOMLEFT", 0, -15)

    page.controls.procXOffset = UI.CreateModernSlider(
        procSection, L["X Offset"], -20, 20, CDM.db.glowProcXOffset or 0,
        function(v) CDM.db.glowProcXOffset = v; API:Refresh("STYLE") end
    )
    page.controls.procXOffset:SetPoint("TOPLEFT", page.controls.procDuration, "BOTTOMLEFT", 0, -10)

    page.controls.procYOffset = UI.CreateModernSlider(
        procSection, L["Y Offset"], -20, 20, CDM.db.glowProcYOffset or 0,
        function(v) CDM.db.glowProcYOffset = v; API:Refresh("STYLE") end
    )
    page.controls.procYOffset:SetPoint("TOPLEFT", page.controls.procXOffset, "BOTTOMLEFT", 0, -10)

    local lastControls = {
        pixel = page.controls.pixelBorder,
        autocast = page.controls.autocastYOffset,
        button = page.controls.buttonFrequency,
        proc = page.controls.procYOffset,
    }
    UpdateScrollHeight = function()
        C_Timer.After(0, function()
            if not page:IsVisible() then return end
            local last = lastControls[CDM.db.glowType] or (colorPicker:IsShown() and colorPicker or ddColor)
            local top, bottom = mainHeader:GetTop(), last:GetBottom()
            if top and bottom then
                local height = top - bottom
                scrollChild:SetHeight(height)
                onHeightChanged(height)
            end
        end)
    end
    page:HookScript("OnShow", UpdateScrollHeight)
    API:RegisterRefreshCallback("glowSettingsHeight", UpdateScrollHeight, 90, { "STYLE" })
    UpdateTypeSections(CDM.db.glowType or "proc")
    return ddColor
end

local function BuildPandemicSettings(rc, onHeightChanged)
    local yOff = 0

    local pandemicHeader = UI.CreateHeader(rc, L["Pandemic Display"])
    pandemicHeader:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 30

    local hidePandemicCheckbox
    local enableCustomizationCheckbox
    local pandemicBorderCheckbox
    local pandemicBorderColor
    local pandemicGlowControls

    local function UpdatePandemicEnableState()
        local hideEnabled = CDM.db.hidePandemicIndicator == true
        local customizationEnabled = hideEnabled and (CDM.db.pandemicCustomizationEnabled == true)

        enableCustomizationCheckbox:SetEnabled(hideEnabled)
        pandemicBorderCheckbox:SetEnabled(customizationEnabled)

        local borderColorEnabled = customizationEnabled and (CDM.db.pandemicBorderEnabled == true)
        pandemicBorderColor:SetEnabled(borderColorEnabled)
        if pandemicGlowControls then pandemicGlowControls:SetEnabled(customizationEnabled) end
    end

    hidePandemicCheckbox = UI.CreateModernCheckbox(
        rc,
        L["Hide Blizzard's Pandemic Indicator (animated refresh window border)"],
        CDM.db.hidePandemicIndicator or false,
        function(checked)
            CDM.db.hidePandemicIndicator = checked
            UpdatePandemicEnableState()
            API:Refresh("STYLE")
        end
    )
    hidePandemicCheckbox:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 30

    enableCustomizationCheckbox = UI.CreateModernCheckbox(
        rc,
        L["Enable Pandemic Customization"],
        CDM.db.pandemicCustomizationEnabled or false,
        function(checked)
            CDM.db.pandemicCustomizationEnabled = checked
            UpdatePandemicEnableState()
            API:Refresh("STYLE")
        end
    )
    enableCustomizationCheckbox:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 40

    pandemicBorderCheckbox = UI.CreateModernCheckbox(
        rc,
        L["Custom Pandemic Border"],
        CDM.db.pandemicBorderEnabled or false,
        function(checked)
            CDM.db.pandemicBorderEnabled = checked
            UpdatePandemicEnableState()
            API:Refresh("STYLE")
        end
    )
    pandemicBorderCheckbox:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 30

    pandemicBorderColor = UI.CreateColorSwatch(rc, L["Color"], "pandemicBorderColor", "STYLE")
    pandemicBorderColor:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 50

    local glowTop = yOff
    local glowHeight = 0
    local function UpdateScrollHeight()
        local height = -glowTop + glowHeight + 20
        rc:SetHeight(height)
        onHeightChanged(height)
    end
    pandemicGlowControls = ns.BuildPandemicGlow(rc, function(height)
        glowHeight = height
        UpdateScrollHeight()
    end)
    pandemicGlowControls:SetPoint("TOPLEFT", 0, yOff)
    UpdatePandemicEnableState()

    UpdateScrollHeight()
    return pandemicGlowControls:GetColorDropdown()
end

local function CreateGlowPreview(page, anchor, pandemic)
    local icon = CreateFrame("Frame", nil, page)
    icon:SetPoint("LEFT", anchor, "RIGHT", 80, 0)
    local texture = icon:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetTexture(135846)

    local function Stop()
        CDM.Glow:RequestBuffGlow(icon, false)
        CDM.StopGlow(icon, "pandemic")
        CDM.BORDER:ClearPandemicBorderColor(icon)
    end

    local function Refresh()
        if not page:IsVisible() then return end
        local enabled = not pandemic or (CDM.db.hidePandemicIndicator == true
            and CDM.db.pandemicCustomizationEnabled == true)
        icon:SetSize(40, 40)
        CDM.CONST.ApplyIconTexCoord(texture, CDM.CONST.GetEffectiveZoomAmount())
        Stop()
        CDM.BORDER:CreateBorder(icon, { forceUpdate = true })
        if CDM.BORDER.activeBorders then CDM.BORDER.activeBorders[icon] = nil end
        if not enabled then return end
        if pandemic then
            if CDM.db.pandemicBorderEnabled == true then
                CDM.BORDER:ApplyPandemicBorderColor(icon, CDM.db.pandemicBorderColor)
            end
            local settings = CDM.ResolvePandemicGlowSettings()
            if settings.enabled == true then
                CDM.StartGlow(icon, settings.style, settings.options)
            end
        else
            CDM.Glow:RequestBuffGlow(icon, true)
        end
    end

    page:HookScript("OnShow", Refresh)
    page:HookScript("OnHide", Stop)
    API:RegisterRefreshCallback(pandemic and "pandemicPreview" or "glowPreview",
        Refresh, 90, { "STYLE", "LAYOUT" })
    Refresh()
end

local function CreateGlowTab(page)
    local content, scrollFrame = UI.CreateScrollableTab(page, "AyijeCDM_Glow_SettingsScrollFrame", 1000, 650)
    local glowSection = CreateFrame("Frame", nil, content)
    glowSection:SetPoint("TOPLEFT")
    glowSection:SetPoint("TOPRIGHT")
    glowSection:SetHeight(400)
    glowSection.controls = {}

    local pandemicSection = CreateFrame("Frame", nil, content)
    pandemicSection:SetPoint("TOPLEFT", glowSection, "BOTTOMLEFT", 0, -20)
    pandemicSection:SetPoint("TOPRIGHT", glowSection, "BOTTOMRIGHT", 0, -20)
    pandemicSection:SetHeight(600)

    local function UpdateHeight()
        local height = glowSection:GetHeight() + pandemicSection:GetHeight() + 40
        content:SetHeight(height)
        scrollFrame:GetScrollChild():SetHeight(height + 20)
    end

    local glowColor = BuildGlowSettings(glowSection, UpdateHeight)
    local pandemicColor = BuildPandemicSettings(pandemicSection, UpdateHeight)
    CreateGlowPreview(glowSection, glowColor, false)
    CreateGlowPreview(pandemicSection, pandemicColor, true)
    UpdateHeight()
end

API:RegisterConfigTab("glow", L["Glow/Pandemic"], CreateGlowTab, 6)
