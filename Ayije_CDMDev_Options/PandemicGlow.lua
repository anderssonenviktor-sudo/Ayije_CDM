local AddonName = "Ayije_CDMDev"
local CDM = _G[AddonName]
local API = CDM.API
local ns = CDM._OptionsNS
local UI, L = ns.ConfigUI, CDM.L

local styles = {
    { value = "pixel", label = L["Pixel Glow"] },
    { value = "autocast", label = L["Auto-Cast Glow"] },
    { value = "button", label = L["Button Glow"] },
    { value = "proc", label = L["Proc Glow"] },
    { value = "gcd", label = L["GCD Glow"] },
    { value = "shape", label = L["Shape Glow"] },
}
local colors = {
    { value = "default", label = L["Default"] },
    { value = "class", label = L["Class Color"] },
    { value = "custom", label = L["Custom"] },
}
local layers = {
    { value = "background", label = L["Behind Icon"] },
    { value = "normal", label = L["Around Icon"] },
    { value = "overlay", label = L["Above Icon"] },
}

local function GetPath(settings, path)
    local group, key = path:match("^([^.]+)%.(.+)$")
    if group then
        if type(settings[group]) == "table" then return settings[group][key] end
        return nil
    end
    return settings[path]
end

local function SetPath(settings, path, value)
    local group, key = path:match("^([^.]+)%.(.+)$")
    if group then
        if type(settings[group]) ~= "table" then settings[group] = {} end
        settings[group][key] = value
        if not next(settings[group]) then settings[group] = nil end
    else settings[path] = value end
end

function ns.BuildPandemicGlow(parent, onHeightChanged)
    local body = CreateFrame("Frame", nil, parent)
    body:SetSize(490, 1)
    local widgets, Build = {}, nil
    local function Widget(key, create)
        local widget = widgets[key]
        if not widget then widget = create(); widgets[key] = widget end
        widget:ClearAllPoints()
        widget:Show()
        return widget
    end
    local function RawSettings()
        local settings = rawget(CDM.db, "pandemicGlow")
        if type(settings) ~= "table" then
            settings = {}; CDM.db.pandemicGlow = settings
        end
        return settings
    end

    local function Changed()
        CDM.InvalidatePandemicGlowSettings()
        API:Refresh("STYLE")
    end

    local function Write(path, value)
        local raw = RawSettings()
        if value == GetPath(CDM.defaults.pandemicGlow, path) then value = nil end
        SetPath(raw, path, value)
        Changed()
    end

    Build = function()
        for _, widget in pairs(widgets) do widget:Hide() end
        local settings = CDM.ResolvePandemicGlowSettings()
        local capabilities = CDM.GLOW_CAPABILITIES[settings.style]
        local y = 0

        local function Checkbox(path, label)
            local value = GetPath(settings, path)
            local widget = Widget(path, function()
                return UI.CreateModernCheckbox(body, L[label], false, function(checked) Write(path, checked) end)
            end)
            widget:SetChecked(value == true)
            widget:SetEnabled(true)
            widget:SetPoint("TOPLEFT", 0, y)
            y = y - 35
        end

        local function Dropdown(path, label, options)
            local value = GetPath(settings, path)
            local text = Widget(path .. "Label", function() return body:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14") end)
            text:SetPoint("TOPLEFT", 0, y)
            text:SetText(L[label])
            local widget = Widget(path, function() return CreateFrame("DropdownButton", nil, body, "WowStyle1DropdownTemplate") end)
            widget:SetEnabled(true)
            widget:SetWidth(220)
            widget:SetPoint("TOPLEFT", 0, y - 22)
            widget:SetDefaultText(UI.GetOptionLabel(options, value))
            UI.SetupValueDropdown(widget, options, function() return GetPath(CDM.ResolvePandemicGlowSettings(), path) end,
                function(selected)
                    Write(path, selected)
                    Build()
                end)
            y = y - 65
        end

        local function Slider(path, label, low, high, step)
            local value = GetPath(settings, path)
            local widget = Widget(path, function()
                return UI.CreateModernSliderPrecise(body, L[label], low, high, value, step, step < 1 and 2 or 0,
                    function(v) Write(path, v) end)
            end)
            widget:SetWidth(450)
            widget:UpdateUIValue(value)
            widget:SetAlpha(1)
            widget.Input:SetEnabled(true)
            widget:SetPoint("TOPLEFT", 0, y)
            y = y - 65
        end

        local function Color(label, red, green, blue)
            local text = Widget(red .. "Label", function() return body:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14") end)
            text:SetPoint("TOPLEFT", 0, y)
            text:SetText(L[label])
            local value = { r = GetPath(settings, red), g = GetPath(settings, green), b = GetPath(settings, blue) }
            local widget = Widget(red .. "Color", function()
                return UI.CreateSimpleColorPicker(body, value, function(r, g, b)
                    local raw = RawSettings()
                    SetPath(raw, red, r); SetPath(raw, green, g); SetPath(raw, blue, b)
                    Changed()
                end, false)
            end)
            widget:UpdateColor(value.r, value.g, value.b)
            widget:SetEnabled(true)
            widget:SetPoint("TOPLEFT", 200, y)
            y = y - 40
        end

        Checkbox("enabled", "Pandemic Glow")
        Dropdown("style", "Glow Style", styles)
        if capabilities.color then
            Dropdown("colorMode", "Glow Color", colors)
            if settings.colorMode == "custom" then Color("Custom Color", "r", "g", "b") end
        end
        if capabilities.alpha then Slider("alpha", "Glow Opacity", 0.1, 1, 0.05) end
        if capabilities.scale then Slider("scale", "Glow Scale", 0.75, 2, 0.05) end
        Dropdown("layer", "Glow Layer", layers)
        if settings.style == "pixel" or settings.style == "autocast" or settings.style == "shape" then
            local title = Widget("styleHeader", function() return UI.CreateSubHeader(body, L["Style Settings"]) end)
            title:SetPoint("TOPLEFT", 0, y)
            y = y - 35
        end
        if settings.style == "pixel" then
            Slider("pixel.lines", "Lines", 1, 20, 1)
            Slider("pixel.thickness", "Thickness", 1, 10, 1)
            Checkbox("pixel.background", "Background Enabled")
            Color("Background Color", "pixel.backgroundR", "pixel.backgroundG", "pixel.backgroundB")
        elseif settings.style == "autocast" then
            Slider("autocast.sparkCount", "Spark Count", 1, 16, 1)
        elseif settings.style == "shape" then
            Slider("shape.intensity", "Glow Intensity", 0.25, 2, 0.05)
        end
        body:SetHeight(-y)
        if onHeightChanged then onHeightChanged(-y) end
    end

    local blocker = CreateFrame("Frame", nil, body)
    blocker:SetAllPoints(body)
    blocker:SetFrameLevel(body:GetFrameLevel() + 20)
    blocker:EnableMouse(true)
    function body:SetEnabled(enabled)
        self:SetAlpha(enabled and 1 or 0.4)
        blocker:SetShown(not enabled)
    end
    Build()
    return body
end
