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

local GROUP_SIDES = { "LEFT", "RIGHT" }

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
    NextY(45)

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

    -- Rebuilt on each open so renamed groups show up. buffGroups is keyed by
    -- specID, not a flat array.
    local function BuildGroupOptions()
        local opts = { { label = L["Main"], value = "main" } }
        local specID = CDM.GetCurrentSpecID and CDM:GetCurrentSpecID() or nil
        local groups = specID and CDM.db.buffGroups and CDM.db.buffGroups[specID]
        if groups then
            for i, gd in ipairs(groups) do
                opts[#opts + 1] = {
                    label = gd.name or (L["Group"] .. " " .. i),
                    value = tostring(i),
                }
            end
        end
        return opts
    end

    local function CurrentGroupLabel()
        local current = tostring(Get("powerInfusionAnchorGroup") or "main")
        for _, opt in ipairs(BuildGroupOptions()) do
            if opt.value == current then return opt.label end
        end
        return L["Main"]
    end

    local lblGroup = scrollChild:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    lblGroup:SetText(L["Anchor To"])
    lblGroup:SetPoint("TOPLEFT", 0, NextY(0))
    NextY(24)

    local ddGroup = CreateFrame("DropdownButton", nil, scrollChild, "WowStyle1DropdownTemplate")
    ddGroup:SetPoint("TOPLEFT", 0, NextY(0))
    ddGroup:SetWidth(180)
    ddGroup:SetDefaultText(CurrentGroupLabel())
    page.powerInfusionGroupDropdown = ddGroup

    UI.SetupValueDropdown(
        ddGroup,
        BuildGroupOptions,
        function() return tostring(Get("powerInfusionAnchorGroup") or "main") end,
        function(value, label)
            Set("powerInfusionAnchorGroup", value)
            ddGroup:SetDefaultText(label)
            if RefreshPositionLabels then RefreshPositionLabels() end
            API:Refresh("LAYOUT")
        end
    )
    NextY(45)

    -- Against Main this is a literal anchor point; against a group it picks
    -- which end of the row the icon sits on.
    local lblPos = scrollChild:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    lblPos:SetPoint("TOPLEFT", 0, NextY(0))
    NextY(24)

    local function IsGroupAnchored()
        local t = Get("powerInfusionAnchorGroup")
        return t ~= nil and t ~= "main"
    end

    local RefreshPositionLabels -- forward declared; defined once ddRel exists

    local ddPos = CreateFrame("DropdownButton", nil, scrollChild, "WowStyle1DropdownTemplate")
    ddPos:SetPoint("TOPLEFT", 0, NextY(0))
    ddPos:SetWidth(180)
    ddPos:SetDefaultText(Get("powerInfusionAnchorPoint"))
    page.powerInfusionPosDropdown = ddPos

    UI.SetupPositionDropdown(
        ddPos,
        function() return Get("powerInfusionAnchorPoint") end,
        function(pos)
            Set("powerInfusionAnchorPoint", pos)
            ddPos:SetDefaultText(pos)
            API:Refresh("LAYOUT")
        end,
        GROUP_SIDES
    )
    NextY(45)

    -- Only meaningful against Main; a group derives it from its grow direction.
    local lblRel = scrollChild:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    lblRel:SetText(L["Relative Point"])
    lblRel:SetPoint("TOPLEFT", 0, NextY(0))
    NextY(24)

    local ddRel = CreateFrame("DropdownButton", nil, scrollChild, "WowStyle1DropdownTemplate")
    ddRel:SetPoint("TOPLEFT", 0, NextY(0))
    ddRel:SetWidth(180)
    ddRel:SetDefaultText(Get("powerInfusionRelativePoint"))
    page.powerInfusionRelDropdown = ddRel

    UI.SetupPositionDropdown(
        ddRel,
        function() return Get("powerInfusionRelativePoint") end,
        function(pos)
            Set("powerInfusionRelativePoint", pos)
            ddRel:SetDefaultText(pos)
            API:Refresh("LAYOUT")
        end
    )
    NextY(45)

    RefreshPositionLabels = function()
        local grouped = IsGroupAnchored()
        lblPos:SetText(grouped and L["Side of Group"] or L["Anchor Point"])
        lblRel:SetShown(not grouped)
        ddRel:SetShown(not grouped)
    end
    RefreshPositionLabels()

    page.controls.powerInfusionOffsetX = UI.CreateModernSlider(
        scrollChild, L["X Offset"], -200, 200, Get("powerInfusionOffsetX"),
        function(v)
            Set("powerInfusionOffsetX", UI.RoundToInt(v))
            API:Refresh("LAYOUT")
        end
    )
    page.controls.powerInfusionOffsetX:SetPoint("TOPLEFT", 0, NextY(0))
    NextY(45)

    page.controls.powerInfusionOffsetY = UI.CreateModernSlider(
        scrollChild, L["Y Offset"], -200, 200, Get("powerInfusionOffsetY"),
        function(v)
            Set("powerInfusionOffsetY", UI.RoundToInt(v))
            API:Refresh("LAYOUT")
        end
    )
    page.controls.powerInfusionOffsetY:SetPoint("TOPLEFT", 0, NextY(0))
end

API:RegisterConfigTab("powerinfusion", L["Power Infusion"], CreatePowerInfusionTab, 11.3)
