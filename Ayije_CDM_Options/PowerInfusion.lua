local Runtime = _G["Ayije_CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns.ConfigUI
local L = Runtime.L
local CDM_C = CDM.CONST

-- Per-spec settings; proxy to the runtime accessors.
local function Get(key)
    return CDM.GetPowerInfusionSetting(key)
end

local function Set(key, value)
    CDM.SetPowerInfusionSetting(key, value)
end

local function CreatePowerInfusionTab(page, tabId)
    local scrollChild = UI.CreateScrollableTab(page, "AyijeCDM_PowerInfusionScrollFrame", 580, 370)

    local layout = UI.CreateVerticalLayout(0)
    local function NextY(spacing) return layout:Next(spacing) end

    page.controls.powerInfusionEnabled = UI.CreateModernCheckbox(
        scrollChild,
        L["Enable Power Infusion Icon"],
        Get("powerInfusionEnabled") == true,
        function(checked)
            Set("powerInfusionEnabled", checked)
            API:Refresh("TRACKERS")
        end
    )
    page.controls.powerInfusionEnabled:SetPoint("TOPLEFT", -34, NextY(0))
    NextY(30)

    local enableNote = scrollChild:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    enableNote:SetText(L["AuraButton for Power Infusion so you know when Power Infusion have been casted on you"])
    enableNote:SetWidth(430)
    enableNote:SetJustifyH("LEFT")
    enableNote:SetWordWrap(true)
    if UI.SetTextMuted then UI.SetTextMuted(enableNote) end
    enableNote:SetPoint("TOPLEFT", 0, NextY(0))
    NextY(enableNote:GetStringHeight() + 20)

    local sizeHeader = UI.CreateHeader(scrollChild, L["Dimensions"])
    sizeHeader:SetPoint("TOPLEFT", 0, NextY(0))
    NextY(30)

    page.controls.powerInfusionIconWidth = UI.CreateModernSlider(
        scrollChild, L["Width"], 10, 100, Get("powerInfusionIconWidth"),
        function(v)
            Set("powerInfusionIconWidth", UI.RoundToInt(v))
            API:Refresh("STYLE")
        end
    )
    page.controls.powerInfusionIconWidth:SetPoint("TOPLEFT", 0, NextY(0))
    NextY(45)

    page.controls.powerInfusionIconHeight = UI.CreateModernSlider(
        scrollChild, L["Height"], 10, 100, Get("powerInfusionIconHeight"),
        function(v)
            Set("powerInfusionIconHeight", UI.RoundToInt(v))
            API:Refresh("STYLE")
        end
    )
    page.controls.powerInfusionIconHeight:SetPoint("TOPLEFT", 0, NextY(0))
    NextY(45)

    page.controls.powerInfusionFontSize = UI.CreateModernSlider(
        scrollChild, L["Duration Font Size"], 6, 40, Get("powerInfusionFontSize"),
        function(v)
            Set("powerInfusionFontSize", UI.RoundToInt(v))
            API:Refresh("STYLE")
        end
    )
    page.controls.powerInfusionFontSize:SetPoint("TOPLEFT", 0, NextY(0))
    NextY(45)

    -- UI.CreateColorSwatch writes CDM.db[key] directly, which cannot reach a
    -- per-spec value, so drive ColorPickerFrame ourselves.
    local colorRow = CreateFrame("Frame", nil, scrollChild)
    colorRow:SetSize(250, 30)
    colorRow:SetPoint("TOPLEFT", 0, NextY(0))

    local colorLabel = colorRow:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    colorLabel:SetPoint("LEFT", 0, 0)
    colorLabel:SetText(L["Duration Font Color"])

    local swatch = CreateFrame("Button", nil, colorRow, "BackdropTemplate")
    swatch:SetSize(20, 20)
    swatch:SetPoint("LEFT", 140, 0)
    swatch:SetBackdrop({
        edgeFile = CDM_C.TEX_WHITE8X8, edgeSize = 1,
        bgFile = CDM_C.TEX_WHITE8X8,
    })
    swatch:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    page.powerInfusionColorSwatch = swatch

    local function ApplySwatchColor()
        local c = Get("powerInfusionFontColor") or { r = 1, g = 1, b = 1, a = 1 }
        swatch:SetBackdropColor(c.r, c.g, c.b, c.a or 1)
    end
    ApplySwatchColor()

    swatch:SetScript("OnClick", function()
        local c = Get("powerInfusionFontColor") or { r = 1, g = 1, b = 1, a = 1 }
        local function Picked()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = ColorPickerFrame:GetColorAlpha()
            Set("powerInfusionFontColor", { r = r, g = g, b = b, a = a })
            ApplySwatchColor()
            API:Refresh("STYLE")
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = Picked,
            opacityFunc = Picked,
            cancelFunc = function(prev)
                Set("powerInfusionFontColor", prev)
                ApplySwatchColor()
                API:Refresh("STYLE")
            end,
            r = c.r, g = c.g, b = c.b, opacity = c.a or 1,
            hasOpacity = true,
            previousValues = { r = c.r, g = c.g, b = c.b, a = c.a or 1 },
        })
    end)
    NextY(50)

    local posHeader = UI.CreateHeader(scrollChild, L["Position"])
    posHeader:SetPoint("TOPLEFT", 0, NextY(0))
    NextY(32)

    local posNote = scrollChild:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    posNote:SetText(L["The icon is positioned relative to the centre of the screen. It cannot be anchored to a buff group: the game forbids moving this icon in combat, so it could never follow a group that moves during a fight. Move it out of combat."])
    posNote:SetWidth(430)
    posNote:SetJustifyH("LEFT")
    posNote:SetWordWrap(true)
    if UI.SetTextMuted then UI.SetTextMuted(posNote) end
    posNote:SetPoint("TOPLEFT", 0, NextY(0))
    NextY(posNote:GetStringHeight() + 14)

    page.controls.powerInfusionOffsetX = UI.CreateModernSlider(
        scrollChild, L["X Offset"], -1000, 1000, Get("powerInfusionOffsetX"),
        function(v)
            Set("powerInfusionOffsetX", UI.RoundToInt(v))
            API:Refresh("LAYOUT")
        end
    )
    page.controls.powerInfusionOffsetX:SetPoint("TOPLEFT", 0, NextY(0))
    NextY(45)

    page.controls.powerInfusionOffsetY = UI.CreateModernSlider(
        scrollChild, L["Y Offset"], -1000, 1000, Get("powerInfusionOffsetY"),
        function(v)
            Set("powerInfusionOffsetY", UI.RoundToInt(v))
            API:Refresh("LAYOUT")
        end
    )
    page.controls.powerInfusionOffsetY:SetPoint("TOPLEFT", 0, NextY(0))
    NextY(45)
end

API:RegisterConfigTab("powerinfusion", L["Power Infusion"], CreatePowerInfusionTab, 11.3)
