local Runtime = _G["Ayije_CDMDev"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local CDM_C = CDM and CDM.CONST or {}
local L = Runtime.L
local LSM = LibStub("LibSharedMedia-3.0")

ns.ConfigUI = ns.ConfigUI or {}
local UI = ns.ConfigUI

local GOLD = CDM_C.GOLD or { r = 1, g = 0.82, b = 0, a = 1 }
local WHITE = CDM_C.WHITE or { r = 1, g = 1, b = 1, a = 1 }

local colorSwatchesByKey = {}

function UI.CreateCustomEditBox(parent)
    local input = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    input:SetSize(120, 24)
    input:SetAutoFocus(false)
    input:SetFontObject("AyijeCDM_Font14")
    input:SetTextColor(0.92, 0.92, 0.9, 1)
    input:SetTextInsets(7, 7, 2, 2)
    input:SetJustifyH("LEFT")
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetBackdrop({ bgFile = CDM_C.TEX_WHITE8X8, edgeFile = CDM_C.TEX_WHITE8X8, edgeSize = 1 })
    input:SetBackdropColor(0.035, 0.035, 0.035, 0.95)
    local hovered = false
    local function UpdateBorder()
        if input:HasFocus() then
            input:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b, 0.95)
        elseif hovered then
            input:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b, 0.45)
        else
            input:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)
        end
    end
    input:HookScript("OnEnter", function() hovered = true; UpdateBorder() end)
    input:HookScript("OnLeave", function() hovered = false; UpdateBorder() end)
    input:HookScript("OnEditFocusGained", UpdateBorder)
    input:HookScript("OnEditFocusLost", UpdateBorder)
    input:HookScript("OnHide", function() hovered = false; UpdateBorder() end)
    UpdateBorder()
    return input
end

function UI.CreateSpellStripSurface(parent)
    local surface = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    surface:SetFrameLevel(parent:GetFrameLevel())
    surface:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    surface:SetBackdropColor(0.045, 0.04, 0.035, 0.95)
    surface:SetBackdropBorderColor(0.36, 0.31, 0.21, 0.8)
    return surface
end

function UI.StyleSpellStripAddButton(button)
    local surface = UI.CreateSpellStripSurface(button)
    surface:SetAllPoints()
    surface:SetBackdropColor(0.11, 0.095, 0.06, 0.95)
    for _, size in ipairs({ { 10, 2 }, { 2, 10 } }) do
        local line = surface:CreateTexture(nil, "ARTWORK")
        line:SetSize(size[1], size[2])
        line:SetPoint("CENTER")
        line:SetColorTexture(GOLD.r, GOLD.g, GOLD.b, 1)
    end
    button:HookScript("OnEnter", function()
        surface:SetBackdropColor(0.2, 0.16, 0.07, 1)
        surface:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b, 0.9)
    end)
    button:HookScript("OnLeave", function()
        surface:SetBackdropColor(0.11, 0.095, 0.06, 0.95)
        surface:SetBackdropBorderColor(0.36, 0.31, 0.21, 0.8)
    end)
end

function UI.CreateTextButton(parent)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(120, 24)
    button:SetBackdrop({ edgeFile = CDM_C.TEX_WHITE8X8, edgeSize = 1 })
    local label = button:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", 3, 0)
    label:SetPoint("RIGHT", -3, 0)
    label:SetJustifyH("CENTER")
    button:SetFontString(label)
    button:SetNormalFontObject(AyijeCDM_GameFontNormal)
    button:SetHighlightFontObject(AyijeCDM_GameFontHighlight)
    button:SetDisabledFontObject(AyijeCDM_GameFontDisable)
    button:SetPushedTextOffset(0, -1)

    local function Background(r, g, b, a)
        local texture = button:CreateTexture(nil, "BACKGROUND")
        texture:SetPoint("TOPLEFT", 1, -1)
        texture:SetPoint("BOTTOMRIGHT", -1, 1)
        texture:SetColorTexture(r, g, b, a)
        return texture
    end
    button:SetNormalTexture(Background(0.035, 0.035, 0.035, 0.95))
    button:SetPushedTexture(Background(0.16, 0.13, 0.035, 0.98))
    button:SetDisabledTexture(Background(0.035, 0.035, 0.035, 0.65))
    button:SetHighlightTexture(Background(GOLD.r, GOLD.g, GOLD.b, 0.08))
    button:GetHighlightTexture():SetBlendMode("BLEND")

    local hovered = false
    local function UpdateBorder()
        if not button:IsEnabled() then
            button:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)
        elseif hovered then
            button:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b, 0.95)
        else
            button:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)
        end
    end
    button:HookScript("OnEnter", function() hovered = true; UpdateBorder() end)
    button:HookScript("OnLeave", function() hovered = false; UpdateBorder() end)
    button:HookScript("OnHide", function() hovered = false; UpdateBorder() end)
    hooksecurefunc(button, "Enable", UpdateBorder)
    hooksecurefunc(button, "Disable", UpdateBorder)
    hooksecurefunc(button, "SetEnabled", UpdateBorder)
    UpdateBorder()
    return button
end

local function BroadcastSwatchColor(key, r, g, b, a)
    local swatches = colorSwatchesByKey[key]
    if not swatches then return end
    for swatchFrame in pairs(swatches) do
        swatchFrame:UpdateColor(r, g, b, a)
    end
end

local function TriggerConfigRefresh(scope)
    API:Refresh(scope)
end

function UI.CreateColorSwatch(parent, label, key, scope)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(250, 30)

    local text = frame:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    text:SetPoint("LEFT", 0, 0)
    text:SetText(label)

    local button = CreateFrame("Button", nil, frame, "BackdropTemplate")
    button:SetSize(20, 20)
    button:SetPoint("LEFT", 140, 0)
    button:SetBackdrop({
        edgeFile = CDM_C.TEX_WHITE8X8, edgeSize = 1,
        bgFile = CDM_C.TEX_WHITE8X8,
    })

    local color = CDM.db[key] or CDM.defaults[key] or CDM.defaults.borderColor
    button:SetBackdropColor(color.r, color.g, color.b, color.a)
    button:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    if not colorSwatchesByKey[key] then
        colorSwatchesByKey[key] = setmetatable({}, { __mode = "k" })
    end
    colorSwatchesByKey[key][frame] = true

    function frame:UpdateColor(r, g, b, a)
        button:SetBackdropColor(r, g, b, a)
        if frame.OnChange then
            frame.OnChange(r, g, b, a)
        end
    end

    local enabledFlag = true

    button:SetScript("OnClick", function()
        if not enabledFlag then return end
        local color = CDM.db[key] or CDM.defaults[key] or CDM.defaults.borderColor
        local function ApplyPickedColor()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = ColorPickerFrame:GetColorAlpha()
            CDM.db[key] = { r = r, g = g, b = b, a = a }
            BroadcastSwatchColor(key, r, g, b, a)
            TriggerConfigRefresh(scope)
        end

        local info = {
            swatchFunc = ApplyPickedColor,
            opacityFunc = ApplyPickedColor,
            cancelFunc = function(prev)
                CDM.db[key] = prev
                BroadcastSwatchColor(key, prev.r, prev.g, prev.b, prev.a)
                TriggerConfigRefresh(scope)
            end,
            r = color.r, g = color.g, b = color.b, opacity = color.a,
            hasOpacity = true,
            previousValues = { r = color.r, g = color.g, b = color.b, a = color.a }
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    function frame:SetEnabled(enabled)
        enabledFlag = enabled and true or false
        button:EnableMouse(enabledFlag)
        local v = enabledFlag and 1 or 0.5
        text:SetTextColor(v, v, v, 1)
        frame:SetAlpha(enabledFlag and 1 or 0.5)
    end

    return frame
end

local function CreateSectionHeader(parent, text, anchorFrame, yOffset, fontObject, anchoredOffset, topOffset)
    local header = parent:CreateFontString(nil, "ARTWORK", fontObject)
    if anchorFrame then
        header:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, yOffset or anchoredOffset)
    else
        header:SetPoint("TOPLEFT", 0, yOffset or topOffset)
    end
    header:SetText(text)
    header:SetTextColor(GOLD.r, GOLD.g, GOLD.b, GOLD.a or 1)
    return header
end

function UI.CreateSimpleColorPicker(parent, initialColor, onChange, hasOpacity)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(20, 20)
    button:SetBackdrop({
        edgeFile = CDM_C.TEX_WHITE8X8, edgeSize = 1,
        bgFile = CDM_C.TEX_WHITE8X8,
    })

    local color = initialColor
        and { r = initialColor.r, g = initialColor.g, b = initialColor.b, a = initialColor.a or 1 }
        or { r = 1, g = 1, b = 1, a = 1 }

    local function DrawSwatch()
        local drawA = hasOpacity and color.a or 1
        button:SetBackdropColor(color.r, color.g, color.b, drawA)
    end

    DrawSwatch()
    button:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    function button:UpdateColor(r, g, b, a)
        color.r, color.g, color.b = r, g, b
        if a ~= nil then color.a = a end
        DrawSwatch()
    end

    button:SetScript("OnClick", function()
        local prevR, prevG, prevB, prevA = color.r, color.g, color.b, color.a
        local info = {
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = hasOpacity and ColorPickerFrame:GetColorAlpha() or 1
                button:UpdateColor(r, g, b, a)
                if onChange then onChange(r, g, b, a) end
            end,
            opacityFunc = function()
                if not hasOpacity then return end
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = ColorPickerFrame:GetColorAlpha()
                button:UpdateColor(r, g, b, a)
                if onChange then onChange(r, g, b, a) end
            end,
            cancelFunc = function()
                button:UpdateColor(prevR, prevG, prevB, prevA)
                if onChange then onChange(prevR, prevG, prevB, prevA) end
            end,
            r = color.r, g = color.g, b = color.b,
            hasOpacity = hasOpacity and true or false,
            opacity = color.a,
            previousValues = { r = prevR, g = prevG, b = prevB, opacity = prevA },
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    return button
end

function UI.CreateModernSlider(parent, label, minVal, maxVal, currentVal, onValueChanged, labelWidth, sliderWidth)
    currentVal = tonumber(currentVal) or minVal
    local lw = labelWidth or 200
    local sw = sliderWidth or 240

    local function toInt(v)
        if v >= 0 then return math.floor(v) else return math.ceil(v) end
    end

    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(lw + 4 + sw, 40)

    panel.Label = panel:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    panel.Label:SetPoint("LEFT", 0, 0)
    panel.Label:SetText(label)
    panel.Label:SetWidth(lw)
    panel.Label:SetJustifyH("LEFT")

    local initVal = toInt(currentVal)

    panel.Slider = CreateFrame("Slider", nil, panel, "MinimalSliderWithSteppersTemplate")
    panel.Slider:SetPoint("LEFT", panel.Label, "RIGHT", 4, 0)
    panel.Slider:SetWidth(sw)
    panel.Slider:Init(initVal, minVal, maxVal, (maxVal - minVal), {
        [MinimalSliderWithSteppersMixin.Label.Top] = nil,
        [MinimalSliderWithSteppersMixin.Label.Right] = nil
    })

    local eb = CreateFrame("EditBox", nil, panel)
    eb:SetSize(50, 18)
    eb:SetPoint("BOTTOM", panel.Slider, "TOP", 0, -8)
    eb:SetFontObject("AyijeCDM_Font14")
    eb:SetJustifyH("CENTER")
    eb:SetTextInsets(0, 0, 0, 0)
    eb:SetAutoFocus(false)
    panel.Input = eb
    local suppressOnValueChanged = false

    local function SetSliderValue(value, suppressCallback)
        if suppressCallback then
            suppressOnValueChanged = true
        end
        panel.Slider:SetValue(value)
        if suppressCallback then
            suppressOnValueChanged = false
        end
    end

    panel.Slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        local numVal = tonumber(value)
        if not numVal then numVal = minVal end
        local val = toInt(numVal)
        if not panel.Input:HasFocus() then panel.Input:SetText(val) end
        if suppressOnValueChanged then
            return
        end
        onValueChanged(val)
    end)

    panel.Input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            val = math.max(minVal, math.min(maxVal, val))
            self:SetText(val)
            SetSliderValue(val, false)
        end
        self:ClearFocus()
    end)

    panel.Input:SetScript("OnEscapePressed", function(self)
        self:SetText(toInt(panel.Slider:GetValue()))
        self:ClearFocus()
    end)

    panel.Input:SetText(initVal)

    function panel:UpdateUIValue(value)
        local clamped = math.max(minVal, math.min(maxVal, toInt(value)))
        SetSliderValue(clamped, true)
        panel.Input:SetText(clamped)
    end

    return panel
end

function UI.CreateCompactSlider(parent, label, minVal, maxVal, currentVal, onValueChanged)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(290, 32)

    panel.Label = panel:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    panel.Label:SetPoint("LEFT")
    panel.Label:SetWidth(154)
    panel.Label:SetJustifyH("LEFT")
    panel.Label:SetText(label)

    local slider = CreateFrame("Slider", nil, panel)
    slider:SetPoint("LEFT", 160, 0)
    slider:SetSize(88, 22)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    panel.Slider = slider

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(0.3, 0.3, 0.3, 1)

    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetHeight(4)
    fill:SetColorTexture(GOLD.r, GOLD.g, GOLD.b, 0.65)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 12)
    thumb:SetColorTexture(GOLD.r, GOLD.g, GOLD.b, 1)
    slider:SetThumbTexture(thumb)
    slider:SetScript("OnEnter", function() thumb:SetColorTexture(1, 0.94, 0.65, 1) end)
    slider:SetScript("OnLeave", function() thumb:SetColorTexture(GOLD.r, GOLD.g, GOLD.b, 1) end)

    local input = UI.CreateCustomEditBox(panel)
    input:SetSize(36, 22)
    input:SetPoint("RIGHT")
    input:SetFontObject("AyijeCDM_Font14")
    input:SetJustifyH("CENTER")
    input:SetTextInsets(3, 3, 1, 1)
    input:SetAutoFocus(false)
    input:SetAltArrowKeyMode(false)
    input:SetMaxLetters(8)
    panel.Input = input

    local value, syncing
    local function Normalize(raw)
        local number = tonumber(raw) or value or minVal
        return math.max(minVal, math.min(maxVal, math.floor(number + 0.5)))
    end
    local function Apply(raw, silent)
        local nextValue = Normalize(raw)
        local changed = value ~= nextValue
        value = nextValue
        syncing = true
        slider:SetValue(value)
        syncing = false
        fill:SetWidth(4 + (slider:GetWidth() - 8) * (value - minVal) / math.max(1, maxVal - minVal))
        input:SetText(value)
        if changed and not silent then onValueChanged(value) end
    end
    slider:SetScript("OnValueChanged", function(_, nextValue)
        if not syncing then Apply(nextValue) end
    end)
    input:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    input:SetScript("OnEditFocusLost", function(self)
        Apply(self:GetText())
        self:HighlightText(0, 0)
    end)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEscapePressed", function(self)
        self:SetText(value)
        self:ClearFocus()
    end)
    input:SetScript("OnArrowPressed", function(self, key)
        if key == "UP" or key == "RIGHT" then
            Apply(Normalize(self:GetText()) + 1)
        elseif key == "DOWN" or key == "LEFT" then
            Apply(Normalize(self:GetText()) - 1)
        end
    end)
    input:SetScript("OnHide", function(self)
        self:SetText(value)
        self:ClearFocus()
    end)
    function panel:UpdateUIValue(nextValue)
        Apply(nextValue, true)
    end
    Apply(currentVal, true)
    return panel
end

function UI.CreateModernSliderPrecise(parent, label, minVal, maxVal, currentVal, step, decimals, onValueChanged)
    currentVal = tonumber(currentVal) or minVal
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(400, 40)

    local valueStep = tonumber(step) or 0.05
    if valueStep <= 0 then
        valueStep = 0.05
    end

    local valueDecimals = tonumber(decimals) or 2
    if valueDecimals < 0 then
        valueDecimals = 0
    end

    local factor = 10 ^ valueDecimals
    local function RoundNearest(value)
        if value >= 0 then
            return math.floor(value + 0.5)
        end
        return math.ceil(value - 0.5)
    end

    local minScaled = RoundNearest(minVal * factor)
    local maxScaled = RoundNearest(maxVal * factor)
    local stepScaled = math.max(1, RoundNearest(valueStep * factor))

    local function ClampAndQuantize(value)
        local numVal = tonumber(value)
        if not numVal then
            numVal = minVal
        end

        local scaled = RoundNearest(numVal * factor)
        scaled = math.max(minScaled, math.min(maxScaled, scaled))
        local stepsFromMin = (scaled - minScaled) / stepScaled
        local snappedSteps = RoundNearest(stepsFromMin)
        local quantizedScaled = minScaled + (snappedSteps * stepScaled)
        quantizedScaled = math.max(minScaled, math.min(maxScaled, quantizedScaled))
        return quantizedScaled / factor
    end

    local function ToScaled(value)
        return RoundNearest(ClampAndQuantize(value) * factor)
    end

    local function FormatValue(value)
        local asString = string.format("%." .. valueDecimals .. "f", value)
        asString = asString:gsub("(%..-)0+$", "%1")
        asString = asString:gsub("%.$", "")
        return asString
    end

    panel.Label = panel:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    panel.Label:SetPoint("LEFT", 0, 0)
    panel.Label:SetText(label)
    panel.Label:SetWidth(200)
    panel.Label:SetJustifyH("LEFT")

    panel.Slider = CreateFrame("Slider", nil, panel, "MinimalSliderWithSteppersTemplate")
    panel.Slider:SetPoint("LEFT", panel.Label, "RIGHT", 4, 0)
    panel.Slider:SetWidth(240)
    local numSteps = math.max(1, RoundNearest((maxScaled - minScaled) / stepScaled))
    panel.Slider:Init(ToScaled(currentVal), minScaled, maxScaled, numSteps, {
        [MinimalSliderWithSteppersMixin.Label.Top] = nil,
        [MinimalSliderWithSteppersMixin.Label.Right] = nil
    })

    local eb = CreateFrame("EditBox", nil, panel)
    eb:SetSize(50, 18)
    eb:SetPoint("BOTTOM", panel.Slider, "TOP", 0, -8)
    eb:SetFontObject("AyijeCDM_Font14")
    eb:SetJustifyH("CENTER")
    eb:SetTextInsets(0, 0, 0, 0)
    eb:SetAutoFocus(false)
    panel.Input = eb
    local suppressOnValueChanged = false

    local function SetSliderValue(value, suppressCallback)
        if suppressCallback then
            suppressOnValueChanged = true
        end
        panel.Slider:SetValue(value)
        if suppressCallback then
            suppressOnValueChanged = false
        end
    end

    panel.Slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        local quantized = ClampAndQuantize((tonumber(value) or minScaled) / factor)
        if not panel.Input:HasFocus() then panel.Input:SetText(FormatValue(quantized)) end
        if suppressOnValueChanged then
            return
        end
        onValueChanged(quantized)
    end)

    panel.Input:SetScript("OnEnterPressed", function(self)
        local quantized = ClampAndQuantize(self:GetText())
        self:SetText(FormatValue(quantized))
        SetSliderValue(ToScaled(quantized), false)
        self:ClearFocus()
    end)

    panel.Input:SetScript("OnEscapePressed", function(self)
        self:SetText(FormatValue(ClampAndQuantize((panel.Slider:GetValue() or minScaled) / factor)))
        self:ClearFocus()
    end)

    panel.Input:SetText(FormatValue(ClampAndQuantize(currentVal)))

    function panel:UpdateUIValue(value)
        local quantized = ClampAndQuantize(value)
        SetSliderValue(ToScaled(quantized), true)
        panel.Input:SetText(FormatValue(quantized))
    end

    return panel
end

function UI.RoundToInt(value)
    local num = tonumber(value)
    if not num then return 0 end
    return math.floor(num + 0.5)
end

function UI.CreateCompactCheckbox(parent, label, initialValue, onChange)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(290, 32)

    local text = frame:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    text:SetPoint("LEFT")
    text:SetWidth(240)
    text:SetJustifyH("LEFT")
    text:SetText(label)
    frame.label = text

    local checkbox = CreateFrame("CheckButton", nil, frame, "BackdropTemplate")
    checkbox:SetSize(18, 18)
    checkbox:SetPoint("RIGHT", -9, 0)
    checkbox:SetHitRectInsets(-5, -5, -5, -5)
    checkbox:SetBackdrop({ bgFile = CDM_C.TEX_WHITE8X8, edgeFile = CDM_C.TEX_WHITE8X8, edgeSize = 1 })
    checkbox:SetBackdropColor(0, 0, 0, 0.3)
    frame.checkbox = checkbox

    local mark = checkbox:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 4, -4)
    mark:SetPoint("BOTTOMRIGHT", -4, 4)
    mark:SetColorTexture(GOLD.r, GOLD.g, GOLD.b, 1)
    checkbox:SetCheckedTexture(mark)

    local hovered = false
    local function UpdateBorder()
        if hovered or checkbox:GetChecked() then
            checkbox:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b, 0.85)
        else
            checkbox:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.7)
        end
    end
    checkbox:SetScript("OnEnter", function()
        hovered = true
        UpdateBorder()
    end)
    checkbox:SetScript("OnLeave", function()
        hovered = false
        UpdateBorder()
    end)
    checkbox:SetScript("OnClick", function(self)
        UpdateBorder()
        if onChange then onChange(self:GetChecked() and true or false) end
    end)
    function frame:SetChecked(checked)
        checkbox:SetChecked(checked and true or false)
        UpdateBorder()
    end
    function frame:GetChecked()
        return checkbox:GetChecked()
    end
    frame:SetChecked(initialValue)
    return frame
end

function UI.CreateModernCheckbox(parent, label, initialValue, onChange)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(400, 26)

    local checkbox = CreateFrame("CheckButton", nil, frame)
    checkbox:SetSize(26, 26)
    checkbox:SetPoint("LEFT", 0, 0)

    checkbox:SetNormalAtlas("checkbox-minimal")
    checkbox:SetPushedAtlas("checkbox-minimal")
    checkbox:SetCheckedTexture("checkmark-minimal")
    checkbox:GetCheckedTexture():SetAtlas("checkmark-minimal")

    local highlight = checkbox:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetAtlas("checkbox-minimal")
    highlight:SetAlpha(0.3)

    local text = frame:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    text:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
    text:SetText(label)

    checkbox:SetChecked(initialValue or false)

    checkbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if onChange then
            onChange(checked)
        end
    end)

    frame.checkbox = checkbox
    frame.label = text

    function frame:SetChecked(checked)
        checkbox:SetChecked(checked)
    end

    function frame:GetChecked()
        return checkbox:GetChecked()
    end

    function frame:SetEnabled(enabled)
        if enabled then
            checkbox:Enable()
            text:SetTextColor(1, 1, 1, 1)
            frame:SetAlpha(1)
        else
            checkbox:Disable()
            text:SetTextColor(0.5, 0.5, 0.5, 1)
            frame:SetAlpha(0.5)
        end
    end

    return frame
end

function UI.CreateHeader(parent, text, anchorFrame, yOffset)
    return CreateSectionHeader(parent, text, anchorFrame, yOffset, "AyijeCDM_Font18", -15, -10)
end

function UI.CreateSubHeader(parent, text, anchorFrame, yOffset)
    return CreateSectionHeader(parent, text, anchorFrame, yOffset, "AyijeCDM_Font14", -12, -10)
end

UI.TextColors = UI.TextColors or {
    white = { r = WHITE.r, g = WHITE.g, b = WHITE.b, a = WHITE.a or 1 },
    muted = { r = 0.7, g = 0.7, b = 0.7, a = 1 },
    dim = { r = 0.6, g = 0.6, b = 0.6, a = 1 },
    subtle = { r = 0.8, g = 0.8, b = 0.8, a = 1 },
    faint = { r = 0.5, g = 0.5, b = 0.5, a = 1 },
    placeholder = { r = 0.55, g = 0.55, b = 0.55, a = 1 },
    inactive = { r = 0.82, g = 0.82, b = 0.82, a = 1 },
    success = { r = 0.5, g = 1, b = 0.5, a = 1 },
    error = { r = 1, g = 0.3, b = 0.3, a = 1 },
}

function UI.SetTextColor(fontString, color)
    if not fontString or not color then return end
    fontString:SetTextColor(color.r, color.g, color.b, color.a or 1)
end

function UI.SetTextMuted(fontString)
    UI.SetTextColor(fontString, UI.TextColors.muted)
end

function UI.SetTextSubtle(fontString)
    UI.SetTextColor(fontString, UI.TextColors.subtle)
end

function UI.SetTextFaint(fontString)
    UI.SetTextColor(fontString, UI.TextColors.faint)
end

function UI.SetTextInactive(fontString)
    UI.SetTextColor(fontString, UI.TextColors.inactive)
end

function UI.SetTextWhite(fontString)
    UI.SetTextColor(fontString, UI.TextColors.white)
end

function UI.SetTextSuccess(fontString)
    UI.SetTextColor(fontString, UI.TextColors.success)
end

function UI.SetTextError(fontString)
    UI.SetTextColor(fontString, UI.TextColors.error)
end

function UI.CloseAllDropdownMenus()
    if Menu and Menu.GetManager then
        Menu.GetManager():CloseMenus()
    end
end

function UI.AttachCloseMenusOnScroll(scrollFrame)
    if not scrollFrame or scrollFrame._cdmCloseMenusOnScrollHooked then
        return
    end

    scrollFrame._cdmCloseMenusOnScrollHooked = true
    scrollFrame:HookScript("OnVerticalScroll", function()
        UI.CloseAllDropdownMenus()
    end)
    scrollFrame:HookScript("OnHide", function()
        UI.CloseAllDropdownMenus()
    end)
end

function UI.CreateScrollableTab(page, frameName, contentHeight, contentWidth)
    local scrollFrame = CreateFrame("ScrollFrame", frameName, page, "ScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -20)
    scrollFrame:SetPoint("BOTTOMRIGHT", -10, 20)
    UI.AttachCloseMenusOnScroll(scrollFrame)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(contentWidth or 460, contentHeight or 800)
    scrollFrame:SetScrollChild(scrollChild)

    local contentContainer = CreateFrame("Frame", nil, scrollChild)
    contentContainer:SetPoint("TOPLEFT", 35, -20)
    contentContainer:SetPoint("TOPRIGHT", -25, -20)
    contentContainer:SetHeight(contentHeight or 800)

    return contentContainer, scrollFrame
end

local SCROLL_BOTTOM_PAD = 20

function UI.MakeSubPageScroll(subPage, frameName)
    local sf = CreateFrame("ScrollFrame", frameName, subPage, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -10, 0)
    UI.AttachCloseMenusOnScroll(sf)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(540)
    sf:SetScrollChild(sc)

    local rc = CreateFrame("Frame", nil, sc)
    rc:SetPoint("TOPLEFT", 30, 0)
    rc:SetPoint("TOPRIGHT", -20, 0)
    return rc, sc
end

function UI.FinalizeScroll(sc, rc, yOff)
    local h = math.abs(yOff) + SCROLL_BOTTOM_PAD
    sc:SetHeight(h)
    rc:SetHeight(h)
end

function UI.CreateVerticalLayout(startY)
    local layout = { y = startY or 0 }
    function layout:Next(spacing)
        self.y = self.y - spacing
        return self.y
    end
    return layout
end

UI.PositionOptions = {
    "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT",
    "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT",
}

function UI.SetupValueDropdown(dropdown, options, getValue, setValue)
    dropdown:SetupMenu(function(_, rootDescription)
        local opts = type(options) == "function" and options() or options
        for _, opt in ipairs(opts) do
            rootDescription:CreateRadio(opt.label, function() return getValue() == opt.value end, function()
                setValue(opt.value, opt.label)
            end)
        end
    end)
end

function UI.SetupPositionDropdown(dropdown, getValue, setValue, positions)
    local options = positions or UI.PositionOptions
    dropdown:SetupMenu(function(_, rootDescription)
        for _, pos in ipairs(options) do
            rootDescription:CreateRadio(pos, function() return getValue() == pos end, function()
                setValue(pos)
            end)
        end
    end)
end

local lsmListCache = {}

local function GetCachedMediaList(mediaType)
    if lsmListCache[mediaType] then return lsmListCache[mediaType] end
    local raw = LSM:List(mediaType) or {}
    local sorted = {}
    for i, name in ipairs(raw) do sorted[i] = name end
    table.sort(sorted)
    local deduped = {}
    local seenPaths = {}
    for _, name in ipairs(sorted) do
        local path = LSM:Fetch(mediaType, name)
        if not path or not seenPaths[path] then
            if path then seenPaths[path] = true end
            deduped[#deduped + 1] = name
        end
    end
    lsmListCache[mediaType] = deduped
    return deduped
end

function UI.SetupMediaDropdown(dropdown, mediaType, getValue, setValue, setText)
    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:SetScrollMode(500)
        local list = GetCachedMediaList(mediaType)
        for _, name in ipairs(list) do
            rootDescription:CreateRadio(name, function() return getValue() == name end, function()
                setValue(name)
                if setText then
                    setText(name)
                end
            end)
        end
    end)
end

do
    local function HideAndOrphan(...)
        for i = 1, select("#", ...) do
            local child = select(i, ...)
            child:Hide()
            child:SetParent(nil)
        end
    end
    function UI.ClearChildren(frame)
        HideAndOrphan(frame:GetChildren())
    end
end

function UI.CreateScrollableEditBox(parent, width, height, editWidth)
    local boxFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    boxFrame:SetSize(width, height)
    boxFrame:SetBackdrop({
        bgFile = CDM_C.TEX_WHITE8X8,
        edgeFile = CDM_C.TEX_WHITE8X8,
        edgeSize = 1,
    })
    boxFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    boxFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, boxFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 8)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("AyijeCDM_Font14")
    editBox:SetWidth(editWidth or (width - 40))
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)

    local function FocusEditBox()
        editBox:SetFocus()
    end
    boxFrame:EnableMouse(true)
    boxFrame:SetScript("OnMouseDown", FocusEditBox)
    scrollFrame:SetScript("OnMouseDown", FocusEditBox)

    return boxFrame, editBox
end

function UI.SetupModuleToggle(parent, enableCheckbox)
    local overlayLevel = parent:GetFrameLevel() + 100
    local overlay = CreateFrame("Frame", nil, parent)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(overlayLevel)
    overlay:EnableMouse(true)
    overlay:Hide()

    enableCheckbox:SetFrameLevel(overlayLevel + 10)

    local function SetEnabled(en)
        local alpha = 0.35
        if en then
            alpha = 1
        end

        for _, child in ipairs({ parent:GetChildren() }) do
            if child ~= enableCheckbox and child ~= overlay then
                child:SetAlpha(alpha)
            end
        end
        for _, region in ipairs({ parent:GetRegions() }) do
            region:SetAlpha(alpha)
        end
        overlay:SetShown(not en)
    end

    return SetEnabled
end

function UI.CreateModalOverlay()
    local overlay = CreateFrame("Frame", nil, ns.ConfigFrame, "BackdropTemplate")
    overlay:SetPoint("TOPLEFT", ns.ConfigFrame, "TOPLEFT", 19, -66)
    overlay:SetPoint("BOTTOMRIGHT", ns.ConfigFrame, "BOTTOMRIGHT", -19, 41)
    overlay:SetFrameStrata("DIALOG")
    overlay:SetFrameLevel(ns.ConfigFrame:GetFrameLevel() + 50)
    overlay:EnableMouse(true)
    overlay:Hide()

    local overlayBg = overlay:CreateTexture(nil, "BACKGROUND")
    overlayBg:SetAllPoints()
    overlayBg:SetColorTexture(0, 0, 0, 0.4)

    local window = CreateFrame("Frame", nil, overlay, "SettingsFrameTemplate")
    window:EnableMouse(true)
    window:SetFrameStrata("DIALOG")
    window:SetFrameLevel(overlay:GetFrameLevel() + 5)
    window:SetPoint("CENTER", ns.ConfigFrame, "CENTER")
    window:SetScript("OnMouseDown", function() end)

    if window.TitleText then
        window.TitleText:SetText("")
        window.TitleText:Hide()
    end

    local closeButton = window.CloseButton
    if closeButton then
        closeButton:HookScript("OnClick", function() overlay:Hide() end)
    end

    overlay:SetScript("OnMouseDown", function() overlay:Hide() end)
    overlay:SetScript("OnShow", function() window:Show() end)
    window:HookScript("OnHide", function() overlay:Hide() end)

    overlay.window = window
    return overlay
end

-- Shared "Custom Icon" chooser. One text field plus a Spell, an Item and an
-- Icon button: the button the user presses declares how the typed ID should be
-- read, so the same number can mean a spell, an item, or a raw FileDataID.
-- Confirms with { kind = "spell"|"item"|"texture", id = <number> }, or nil when
-- cleared.
local customIconPopup

function UI.ShowCustomIconPopup(current, onConfirm)
    if not customIconPopup then
        local overlay = UI.CreateModalOverlay()
        local window = overlay.window
        window:SetSize(376, 210)

        local title = window:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
        title:SetText(L["Custom Icon"])
        title:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -44)
        title:SetTextColor(GOLD.r, GOLD.g, GOLD.b, 1)

        local hint = window:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font12")
        hint:SetText(L["Enter a spell ID, item ID or icon FileDataID, then choose which it is."])
        hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        hint:SetWidth(300)
        hint:SetJustifyH("LEFT")
        UI.SetTextFaint(hint)

        local editBox = UI.CreateCustomEditBox(window)
        editBox:SetSize(120, 20)
        editBox:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 6, -14)
        editBox:SetAutoFocus(false)
        editBox:SetNumeric(true)
        editBox:SetMaxLetters(10)

        local preview = window:CreateTexture(nil, "ARTWORK")
        preview:SetSize(28, 28)
        preview:SetPoint("LEFT", editBox, "RIGHT", 14, 0)
        preview:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local status = window:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font12")
        status:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", -6, -10)
        status:SetWidth(300)
        status:SetJustifyH("LEFT")

        local spellBtn = UI.CreateTextButton(window)
        spellBtn:SetSize(80, 22)
        spellBtn:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 18, 18)
        spellBtn:SetText(L["Spell"])

        local itemBtn = UI.CreateTextButton(window)
        itemBtn:SetSize(80, 22)
        itemBtn:SetPoint("LEFT", spellBtn, "RIGHT", 8, 0)
        itemBtn:SetText(L["Item"])

        local textureBtn = UI.CreateTextButton(window)
        textureBtn:SetSize(80, 22)
        textureBtn:SetPoint("LEFT", itemBtn, "RIGHT", 8, 0)
        textureBtn:SetText(L["Icon ID"])

        local clearBtn = UI.CreateTextButton(window)
        clearBtn:SetSize(80, 22)
        clearBtn:SetPoint("LEFT", textureBtn, "RIGHT", 8, 0)
        clearBtn:SetText(L["Clear"])

        -- A FileDataID has no lookup that can confirm it exists, so unlike the
        -- spell and item cases this returns the ID itself and validity is judged
        -- by whether the texture object accepts it (see Commit).
        local function ResolveTexture(kind, id)
            if kind == "item" then
                local tex = C_Item.GetItemIconByID(id)
                if not tex then C_Item.RequestLoadItemDataByID(id) end
                return tex
            elseif kind == "texture" then
                return id
            end
            return C_Spell.GetSpellTexture(id)
        end

        local function Commit(kind)
            local id = tonumber(editBox:GetText())
            if not id or id <= 0 then
                status:SetText(L["Enter a valid ID"])
                UI.SetTextError(status)
                return
            end
            local tex = ResolveTexture(kind, id)
            if tex then
                -- SetTexture silently no-ops on a FileDataID that resolves to
                -- nothing, leaving the previous texture in place; clearing first
                -- makes GetTexture a truthful check on whether it took.
                preview:SetTexture(nil)
                preview:SetTexture(tex)
            end
            if not tex or not preview:GetTexture() then
                preview:SetTexture(nil)
                status:SetText(kind == "item" and L["No icon found for that item ID"]
                    or kind == "texture" and L["No icon found for that icon ID"]
                    or L["No icon found for that spell ID"])
                UI.SetTextError(status)
                return
            end
            if customIconPopup.onConfirm then
                customIconPopup.onConfirm({ kind = kind, id = id })
            end
            overlay:Hide()
        end

        spellBtn:SetScript("OnClick", function() Commit("spell") end)
        itemBtn:SetScript("OnClick", function() Commit("item") end)
        textureBtn:SetScript("OnClick", function() Commit("texture") end)
        clearBtn:SetScript("OnClick", function()
            if customIconPopup.onConfirm then customIconPopup.onConfirm(nil) end
            overlay:Hide()
        end)

        editBox:SetScript("OnEscapePressed", function() overlay:Hide() end)

        customIconPopup = overlay
        customIconPopup.editBox = editBox
        customIconPopup.status = status
        customIconPopup.preview = preview
        customIconPopup.clearBtn = clearBtn
        customIconPopup.ResolveTexture = ResolveTexture
    end

    local p = customIconPopup
    p.onConfirm = onConfirm
    p.status:SetText("")

    local hasCurrent = type(current) == "table" and tonumber(current.id)
    p.editBox:SetText(hasCurrent and tostring(current.id) or "")
    p.preview:SetTexture(hasCurrent and p.ResolveTexture(current.kind, current.id) or nil)
    p.clearBtn:SetEnabled(hasCurrent and true or false)

    p:Show()
    p.editBox:SetFocus()
end

function UI.CreateTimedStatus(fontString, duration)
    local timer
    duration = duration or 2
    return function(text)
        fontString:SetText(text)
        if timer then timer:Cancel() end
        if text ~= "" then
            timer = C_Timer.NewTimer(duration, function() fontString:SetText("") end)
        end
    end
end

function UI.AttachPlaceholder(editBox, text)
    local ph = editBox:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    ph:SetPoint("LEFT", editBox, "LEFT", 2, 0)
    ph:SetText(text)
    ph:SetTextColor(0.5, 0.5, 0.5, 0.7)
    editBox:HookScript("OnTextChanged", function(self)
        ph:SetShown(self:GetText() == "")
    end)
    return ph
end

function UI.GetOptionLabel(options, value, default)
    for _, opt in ipairs(options) do
        if opt.value == value then return opt.label end
    end
    return default or value
end

function UI.CreateSubTabBar(parent, tabs, initialTab)
    local TAB_HEIGHT = 37
    local barFrame = CreateFrame("Frame", nil, parent)
    barFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 30, -2)
    barFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -30, -2)
    barFrame:SetHeight(TAB_HEIGHT)

    local subPages = {}
    local tabButtons = {}
    local selectedTab = nil

    local function SelectTab(id)
        if selectedTab == id then return end
        selectedTab = id
        for _, info in ipairs(tabs) do
            local btn = tabButtons[info.id]
            local pg = subPages[info.id]
            if info.id == id then
                btn.Left:SetAtlas("Options_Tab_Active_Left", true)
                btn.Middle:SetAtlas("Options_Tab_Active_Middle")
                btn.Right:SetAtlas("Options_Tab_Active_Right", true)
                btn.label:ClearAllPoints()
                btn.label:SetPoint("BOTTOM", 0, 6)
                btn.label:SetFontObject("AyijeCDM_GameFontHighlightSmall")
                pg:Show()
            else
                btn.Left:SetAtlas("Options_Tab_Left", true)
                btn.Middle:SetAtlas("Options_Tab_Middle")
                btn.Right:SetAtlas("Options_Tab_Right", true)
                btn.label:ClearAllPoints()
                btn.label:SetPoint("BOTTOM", 0, 4)
                btn.label:SetFontObject("AyijeCDM_GameFontNormalSmall")
                pg:Hide()
            end
        end
    end

    local prevBtn
    for _, info in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, barFrame)
        btn:SetHeight(TAB_HEIGHT)

        local left = btn:CreateTexture(nil, "BACKGROUND")
        left:SetAtlas("Options_Tab_Left", true)
        left:SetPoint("BOTTOMLEFT")
        btn.Left = left

        local right = btn:CreateTexture(nil, "BACKGROUND")
        right:SetAtlas("Options_Tab_Right", true)
        right:SetPoint("BOTTOMRIGHT")
        btn.Right = right

        local middle = btn:CreateTexture(nil, "BACKGROUND")
        middle:SetAtlas("Options_Tab_Middle")
        middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
        middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
        btn.Middle = middle

        local label = btn:CreateFontString(nil, "OVERLAY", "AyijeCDM_GameFontNormalSmall")
        label:SetPoint("BOTTOM", 0, 4)
        label:SetText(info.label)
        btn.label = label

        local textWidth = label:GetStringWidth()
        btn:SetWidth(math.max(textWidth + 40, 80))

        if prevBtn then
            btn:SetPoint("BOTTOMLEFT", prevBtn, "BOTTOMRIGHT", 2, 0)
        else
            btn:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
        end
        prevBtn = btn

        btn:SetScript("OnClick", function() SelectTab(info.id) end)
        tabButtons[info.id] = btn

        local pg = CreateFrame("Frame", nil, parent)
        pg:SetPoint("TOPLEFT", barFrame, "BOTTOMLEFT", -30, 0)
        pg:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
        pg:Hide()
        pg.controls = {}
        subPages[info.id] = pg
    end

    SelectTab(initialTab or tabs[1].id)

    return {
        selectTab = SelectTab,
        subPages = subPages,
        barFrame = barFrame,
        tabButtons = tabButtons,
    }
end
