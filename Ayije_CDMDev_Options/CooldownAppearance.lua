local AddonName = "Ayije_CDMDev"
local CDM = _G[AddonName]
local ns, L = CDM._OptionsNS, CDM.L
local UI = ns.ConfigUI

function ns.RenderCooldownGroupAppearance(config)
    local parent, group, save = config.rc, config.gd, config.saveAndRefresh
    local offsets = { 0, 0 }
    local function Place(widget, col, height)
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", (col - 1) * 310, -offsets[col])
        offsets[col] = offsets[col] + height
        return widget
    end
    local function Header(label, col)
        if offsets[col] > 0 then offsets[col] = offsets[col] + 10 end
        Place(UI.CreateSubHeader(parent, L[label]), col, 28)
    end
    local function Number(label, col, key, low, high, fallback, colorKey)
        local slider = UI.CreateCompactSlider(parent, L[label], low, high, group[key] or fallback, function(value)
            if key == "maxPerRow" and value == 0 then group[key] = nil else group[key] = value end
            save()
        end)
        if colorKey then
            slider.Label:SetWidth(132)
            local picker = UI.CreateSimpleColorPicker(slider, group[colorKey] or { r = 1, g = 1, b = 1 }, function(r, g, b, a)
                group[colorKey] = { r = r, g = g, b = b, a = a or 1 }
                save()
            end, true)
            picker:SetSize(16, 16)
            picker:SetPoint("LEFT", 138, 0)
        end
        return Place(slider, col, 36)
    end
    local function Dropdown(label, col, key, fallback, options, afterChange)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(290, 32)
        local text = row:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
        text:SetPoint("LEFT")
        text:SetText(L[label])
        text:SetWidth(120)
        text:SetJustifyH("LEFT")
        local dropdown = config.registerDropdown(UI.CreateCompactDropdown(row))
        dropdown:SetWidth(166)
        dropdown:SetPoint("RIGHT")
        UI.SetupValueDropdown(dropdown, options, function() return group[key] or fallback end, function(value)
            local previous = group[key] or fallback
            group[key] = value
            if afterChange then afterChange(value, previous) end
            save()
        end)
        Place(row, col, 36)
        return row
    end
    local positions = {}
    for _, position in ipairs(UI.PositionOptions) do
        positions[#positions + 1] = { label = position, value = position }
    end
    Header("Layout Settings", 1)
    Dropdown("Grow Direction", 1, "grow", "RIGHT", ns.GroupEditorShared.GROW_OPTIONS)
    Number("Icon Width", 1, "iconWidth", 16, 100, 30)
    Number("Icon Height", 1, "iconHeight", 16, 100, 30)
    if not config.buff then Number("Max Per Row", 1, "maxPerRow", 0, 20, 0) end
    Number("Spacing", 1, "spacing", -1, 50, 4)
    if config.buff then
        Place(UI.CreateCompactCheckbox(parent, L["Static Display"], group.staticDisplay or false, function(value)
            group.staticDisplay = value or nil
            save()
        end), 1, 36)
    end

    Header("Cooldown Timer", 2)
    Number("Font Size", 2, "cooldownFontSize", 6, 32, 12, "cooldownColor")
    Header("Stacks (Charges)", 2)
    local prefix = config.buff and "count" or "charge"
    Number("Font Size", 2, prefix .. "FontSize", 6, 32, 15, prefix .. "Color")
    Dropdown("Position", 2, prefix .. "Position", "BOTTOMRIGHT", positions)
    Number("X Offset", 2, prefix .. "OffsetX", -20, 20, 0)
    Number("Y Offset", 2, prefix .. "OffsetY", -20, 20, 0)

    Header("Anchor", 1)
    local xSlider, ySlider, anchorRow, relativeRow
    local function UpdateAnchorRows()
        local enabled = (group.anchorTarget or "screen") ~= "screen"
        anchorRow:SetShown(enabled)
        relativeRow:SetShown(enabled)
    end
    Dropdown("Anchor To", 1, "anchorTarget", "screen", config.anchorTargets, function(value, previous)
        if value ~= previous then
            group.offsetX, group.offsetY = 0, 0
            xSlider:UpdateUIValue(0)
            ySlider:UpdateUIValue(0)
        end
        UpdateAnchorRows()
    end)
    xSlider = Number("X Offset", 1, "offsetX", -840, 840, 0)
    ySlider = Number("Y Offset", 1, "offsetY", -470, 470, 0)
    anchorRow = Dropdown("Anchor Point", 1, "anchorPoint", "CENTER", positions)
    relativeRow = Dropdown("Relative Point", 1, "anchorRelativeTo", "CENTER", positions)
    UpdateAnchorRows()

    Header("Group", 2)
    local name = UI.CreateCustomEditBox(parent)
    name:SetSize(280, 28)
    name:SetAutoFocus(false)
    name:SetText(group.name or (L["Group"] .. " " .. config.groupIndex))
    name:SetScript("OnEnterPressed", function(self)
        local value = self:GetText():match("^%s*(.-)%s*$")
        if value ~= "" then group.name = value; save(); config.onRename() end
        self:ClearFocus()
    end)
    name:SetScript("OnEscapePressed", function(self)
        self:SetText(group.name or "")
        self:ClearFocus()
    end)
    Place(name, 2, 36)
    local actions = UI.CreateTextButton(parent)
    actions:SetSize(140, 22)
    actions:SetText(L["Group Actions"])
    actions:SetScript("OnClick", function(self) config.onActions(self, name) end)
    Place(actions, 2, 36)
    parent:SetHeight(math.max(offsets[1], offsets[2]) + 20)
    return xSlider, ySlider
end

function ns.CreateCooldownAppearance(parent, buffOnly)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    UI.AttachCloseMenusOnScroll(scroll)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(620, 1000)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnSizeChanged", function(_, width)
        if width > 0 then content:SetWidth(width) end
    end)

    local views = {}
    for _, view in ipairs(buffOnly and { "buff" } or { "essential", "utility" }) do
        local body = CreateFrame("Frame", nil, content)
        body:SetPoint("TOPLEFT")
        body:SetPoint("TOPRIGHT")
        body:Hide()
        local readers = {}
        local offsets = { 0, 0 }
        local columns = {}
        for col = 1, 2 do
            local column = CreateFrame("Frame", nil, body)
            column:SetPoint("TOPLEFT", col == 1 and 0 or 310, 0)
            column:SetSize(290, 1000)
            columns[col] = column
        end
        local function Position(widget, col, height)
            widget:SetPoint("TOPLEFT", columns[col], "TOPLEFT", 0, -offsets[col])
            offsets[col] = offsets[col] + height
        end
        local function Header(text, col)
            if offsets[col] > 0 then offsets[col] = offsets[col] + 10 end
            Position(UI.CreateSubHeader(columns[col], L[text]), col, 28)
        end
        local function Number(label, col, low, high, get, set, scope, colorKey)
            local slider = UI.CreateCompactSlider(columns[col], L[label], low, high, get(), function(value)
                set(value)
                CDM:Refresh(scope or "STYLE")
            end)
            if colorKey then
                slider.Label:SetWidth(132)
                local picker = UI.CreateSimpleColorPicker(slider, CDM.db[colorKey], function(r, g, b, a)
                    if colorKey == "swipeColor" then a = CDM.db.swipeColor.a or 0.6 end
                    CDM.db[colorKey] = { r = r, g = g, b = b, a = a or 1 }
                    CDM:Refresh("STYLE")
                end)
                picker:SetSize(16, 16)
                picker:SetPoint("LEFT", slider, "LEFT", 138, 0)
                picker:HookScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(L[label] .. " - " .. L["Color"])
                    GameTooltip:Show()
                end)
                picker:HookScript("OnLeave", function() GameTooltip:Hide() end)
                readers[#readers + 1] = function()
                    local c = CDM.db[colorKey]
                    picker:UpdateColor(c.r, c.g, c.b, c.a or 1)
                end
            end
            Position(slider, col, 36)
            readers[#readers + 1] = function() slider:UpdateUIValue(get()) end
            return slider
        end
        local function DBNumber(label, col, key, low, high, scope, colorKey)
            return Number(label, col, low, high, function() return CDM.db[key] end,
                function(value) CDM.db[key] = value end, scope, colorKey)
        end
        local function ChargeDetails(slider, prefix, title)
            slider.Label:SetWidth(108)
            local button = CreateFrame("Button", nil, slider)
            button:SetSize(20, 24)
            button:SetPoint("LEFT", 112, 0)
            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetSize(20, 20)
            icon:SetPoint("CENTER")
            icon:SetTexture("Interface\\AddOns\\" .. AddonName .. "\\Media\\Textures\\wrench.tga")
            icon:SetVertexColor(CDM.CONST.GOLD.r, CDM.CONST.GOLD.g, CDM.CONST.GOLD.b)
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L["Position and Offsets"])
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            button:SetScript("OnClick", function(self)
                local profile = CDM.db
                local options = {}
                for _, position in ipairs(UI.PositionOptions) do
                    options[#options + 1] = { label = L[position], value = position }
                end
                local function Field(label, kind, suffix)
                    local key = prefix .. suffix
                    return { label = L[label], kind = kind, min = -50, max = 50, options = options,
                        get = function() return CDM.db[key] end,
                        set = function(value) CDM.db[key] = value; CDM:Refresh("STYLE") end }
                end
                ns.ShowFieldMenu(self, L[title], {
                    Field("Position", "choice", "Position"),
                    Field("X Offset", "number", "OffsetX"),
                    Field("Y Offset", "number", "OffsetY"),
                }, function() return CDM.db == profile and body:IsShown() end)
            end)
        end
        local function Check(label, col, key, scope)
            local check = UI.CreateCompactCheckbox(columns[col], L[label], CDM.db[key], function(value)
                CDM.db[key] = value
                CDM:Refresh(scope or "STYLE")
            end)
            Position(check, col, 36)
            readers[#readers + 1] = function() check:SetChecked(CDM.db[key]) end
        end
        local function Size(label, key, dimension)
            Number(label, 1, 20, 100, function() return CDM.db[key][dimension] end, function(value)
                -- Nested defaults are shared; replace the size pair rather than mutating it.
                local current = CDM.db[key]
                local updated = { w = current.w, h = current.h }
                updated[dimension] = value
                CDM.db[key] = updated
            end, "LAYOUT")
        end

        Header("Layout Settings", 1)
        if view == "essential" then
            DBNumber("Max Icons Per Row", 1, "maxRowEss", 1, 20, "LAYOUT")
            Size("Row 1 Width", "sizeEssRow1", "w")
            Size("Row 1 Height", "sizeEssRow1", "h")
            Size("Row 2 Width", "sizeEssRow2", "w")
            Size("Row 2 Height", "sizeEssRow2", "h")
            Check("Hide Trinket Internal CD", 1, "trinketsHideAura")
        elseif view == "buff" then
            Size("Width", "sizeBuff", "w")
            Size("Height", "sizeBuff", "h")
            DBNumber("Icon Spacing", 1, "spacing", -1, 30, "LAYOUT")
        else
            Size("Width", "sizeUtility", "w")
            Size("Height", "sizeUtility", "h")
            Check("Wrap Utility Bar", 1, "utilityWrap", "LAYOUT")
            DBNumber("Max Icons Per Row", 1, "maxRowUtil", 1, 20, "LAYOUT")
            Check("Unlock Utility Bar", 1, "utilityUnlock", "LAYOUT")
            DBNumber("Utility X Offset", 1, "utilityXOffset", -600, 600, "LAYOUT")
            DBNumber("Utility Y Offset", 1, "utilityYOffset", -600, 600, "LAYOUT")
            Check("Display Vertical", 1, "utilityVertical", "LAYOUT")
        end

        Header("Cooldown Timer", 2)
        if view == "essential" then
            DBNumber("Row 1 Font Size", 2, "cooldownFontSize", 8, 32)
            DBNumber("Row 2 Font Size", 2, "essRow2CooldownFontSize", 8, 32)
            Header("Stacks (Charges)", 2)
            ChargeDetails(DBNumber("Row 1 Size", 2, "chargeFontSize", 8, 32, "STYLE", "chargeColor"),
                "charge", "Row 1 - Stacks (Charges)")
            ChargeDetails(DBNumber("Row 2 Size", 2, "essRow2ChargeFontSize", 8, 32, "STYLE", "essRow2ChargeColor"),
                "essRow2Charge", "Row 2 - Stacks (Charges)")
        elseif view == "buff" then
            DBNumber("Font Size", 2, "buffCooldownFontSize", 8, 32, "STYLE", "buffCooldownColor")
            Header("Stacks (Charges)", 2)
            DBNumber("Font Size", 2, "countFontSize", 8, 32, "STYLE", "countColor")
            local row = CreateFrame("Frame", nil, columns[2])
            row:SetSize(290, 32)
            local label = row:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
            label:SetPoint("LEFT")
            label:SetText(L["Position"])
            local dropdown = UI.CreateCompactDropdown(row)
            dropdown:SetSize(150, 26)
            dropdown:SetPoint("RIGHT")
            local options = {}
            for _, position in ipairs(UI.PositionOptions) do
                options[#options + 1] = { label = L[position], value = position }
            end
            UI.SetupValueDropdown(dropdown, options, function() return CDM.db.countPositionMain end, function(value)
                CDM.db.countPositionMain = value
                CDM:Refresh("STYLE")
            end)
            Position(row, 2, 36)
            readers[#readers + 1] = function() dropdown:RefreshText() end
            DBNumber("X Offset", 2, "countOffsetXMain", -20, 20)
            DBNumber("Y Offset", 2, "countOffsetYMain", -20, 20)
        else
            DBNumber("Font Size", 2, "utilityCooldownFontSize", 8, 32)
            Header("Stacks (Charges)", 2)
            ChargeDetails(DBNumber("Font Size", 2, "utilityChargeFontSize", 8, 32, "STYLE", "utilityChargeColor"),
                "utilityCharge", "Stacks (Charges)")
        end

        if view == "essential" then
            local sharedStart = math.max(offsets[1], offsets[2])
            offsets[1], offsets[2] = sharedStart, sharedStart
            Header("Shared Layout & Swipe", 1)
            DBNumber("Icon Spacing", 1, "spacing", -1, 30, "LAYOUT")
            Check("Hide GCD Swipe", 1, "hideGCDSwipe")
            Number("Swipe Opacity", 1, 0, 100, function() return math.floor((CDM.db.swipeColor.a or 0.6) * 100) end,
                function(value)
                    local color = CDM.db.swipeColor
                    CDM.db.swipeColor = { r = color.r, g = color.g, b = color.b, a = value / 100 }
                end, "STYLE", "swipeColor")
        end
        Header("Shared Border", 2)
        DBNumber("Border Size", 2, "borderSize", 1, 50, "STYLE", "borderColor")

        local height = math.max(offsets[1], offsets[2]) + 25
        body:SetHeight(height)
        views[view] = { frame = body, height = height, readers = readers }
    end

    local current = buffOnly and "buff" or "essential"
    local function Update(view)
        current = view or current
        for id, data in pairs(views) do
            data.frame:SetShown(id == current)
            if id == current then
                content:SetHeight(data.height)
                for _, read in ipairs(data.readers) do read() end
            end
        end
    end
    parent:HookScript("OnShow", function() Update() end)
    return {
        SetView = function(view)
            local changed = current ~= view
            Update(view)
            if changed then scroll:SetVerticalScroll(0) end
        end,
        Refresh = function() Update() end,
    }
end
