local AddonName = "Ayije_CDMDev"
local CDM = _G[AddonName]
local ns, L = CDM._OptionsNS, CDM.L
local UI, M = ns.ConfigUI, CDM.BUFFBAR

local positions = {}
for _, value in ipairs({ "LEFT", "CENTER", "RIGHT", "TOP", "BOTTOM", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
    positions[#positions + 1] = { value = value, label = L[value] }
end
local iconPositions = {
    { value = "LEFT", label = L["Left"] }, { value = "RIGHT", label = L["Right"] },
    { value = "HIDDEN", label = L["Hidden"] },
}

function ns.BuildBuffBarAppearanceFields(bar, save)
    local globals = {}
    for _, field in ipairs(M.BAR_VISUAL_KEYS) do globals[field.key] = field.global end
    for _, field in ipairs(M.BAR_COLOR_KEYS) do globals[field.key] = field.global end
    local function Read(key)
        if bar then return bar[key] end
        return CDM.db[globals[key] or key]
    end
    local function Write(key, value)
        if key == "width" and value > 0 and value < 60 then value = 60 end
        if bar then bar[key] = value else CDM.db[globals[key] or key] = value end
        save()
    end
    local function Field(label, kind, key, low, high, options)
        return { label = L[label], key = key, kind = kind, min = low, max = high, options = options,
            get = function() return Read(key) end,
            set = function(value) Write(key, value) end,
            captureRestore = function()
                local previous = Read(key)
                return function() Write(key, previous) end
            end }
    end
    local function Number(label, key, low, high) return Field(label, "number", key, low, high) end
    local function Check(label, key) return Field(label, "check", key) end
    local function Choice(label, key, options) return Field(label, "choice", key, nil, nil, options) end
    local function Color(label, key)
        local field = Field(label, "color", key)
        field.hasOpacity = true
        return field
    end
    local categories = {
        { label = L["Bar Layout"], column = 1, fields = {
            Number("Width (0 = Auto)", "width", 0, 600), Number("Height", "height", 4, 40),
            Choice("Icon Position", "iconPosition", iconPositions), Number("Icon-Bar Gap", "iconGap", -1, 20),
        } },
        { label = L["Appearance"], column = 2, fields = {
            Choice("Bar Texture", "texture", function()
                local options = {}
                for _, name in ipairs(LibStub("LibSharedMedia-3.0"):List("statusbar")) do
                    options[#options + 1] = { label = name, value = name }
                end
                return options
            end),
            Color("Fill Color", "barColor"), Color("Background Color", "bgColor"),
        } },
        { label = L["Name Text"], column = 1, fields = {
            Check("Show Buff Name", "showName"), Number("Max Name Length", "nameMaxChars", 0, 30),
            Number("Font Size", "nameFontSize", 6, 32), Color("Color", "nameColor"),
            Number("X Offset", "nameOffsetX", -50, 50), Number("Y Offset", "nameOffsetY", -20, 20),
        } },
        { label = L["Duration Text"], column = 2, fields = {
            Check("Show Duration Text", "showDuration"), Number("Font Size", "durationFontSize", 6, 32),
            Color("Color", "durationColor"), Choice("Position", "durationPosition", positions),
            Number("X Offset", "durationOffsetX", -50, 50), Number("Y Offset", "durationOffsetY", -20, 20),
            Number("Decimal Threshold", "decimalThreshold", 3, 120),
        } },
        { label = L["Stack Text"], column = 1, fields = {
            Check("Show Stack Count", "showApplications"), Number("Font Size", "applicationsFontSize", 6, 32),
            Color("Color", "applicationsColor"), Choice("Position", "applicationsPosition", positions),
            Number("X Offset", "applicationsOffsetX", -50, 50), Number("Y Offset", "applicationsOffsetY", -50, 50),
        } },
    }
    if bar then
        if bar.barType == M.TYPE_STACK then
            table.remove(categories, 4)
            categories[#categories + 1] = { label = L["Stack Fill"], column = 2, fields = {
                Number("Max Stacks", "maxStacks", 1, 100), Check("Always Show Bar", "alwaysShow"),
                Field("Tick Positions", "input", "tickValues"), Number("Tick Width", "tickWidth", 0, 6),
                Color("Tick Color", "tickColor"),
            } }
        else
            table.insert(categories[4].fields, 7, Check("Show Decimals", "timerDecimals"))
        end
    else
        local layout = categories[1].fields
        layout[#layout + 1] = Choice("Grow Direction", "buffBarGrowDirection", {
            { label = L["Down"], value = "DOWN" }, { label = L["Up"], value = "UP" },
        })
        layout[#layout + 1] = Number("Spacing", "buffBarSpacing", -1, 30)
        layout[#layout + 1] = Check("Dual Bar Mode", "buffBarDualMode")
    end
    if bar and bar.barType == M.TYPE_STACK then
        local stackFields = categories[#categories].fields
        stackFields[#stackFields + 1] = {
            label = L["Smooth Buff Bars"], key = "smoothBuffBars", kind = "check",
            tooltip = L["Smoothly animates bar fill when stacks or remaining duration change."]
                .. "\n\n" .. L["Applies to all buff bars. Text continues to show the actual value."],
            get = function() return CDM.db.smoothBuffBars == true end,
            set = function(value) CDM.db.smoothBuffBars = value; save() end,
        }
    end
    return categories
end

function ns.RenderBuffBarAppearance(parent, save, bar, rebuild)
    local categories = ns.BuildBuffBarAppearanceFields(bar, save)
    local fields, sections = {}, {}
    for _, category in ipairs(categories) do
        sections[category.label] = category.fields
        for _, field in ipairs(category.fields) do fields[field.key] = field end
    end
    local profile, specID = CDM.db, M.GetSpecID()
    local function Valid()
        return profile == CDM.db and specID == M.GetSpecID() and parent:IsShown()
    end
    local columnY = { 0, 0 }
    local function Header(col, title)
        if columnY[col] > 0 then columnY[col] = columnY[col] + 8 end
        local label = UI.CreateSubHeader(parent, L[title])
        label:SetPoint("TOPLEFT", (col - 1) * 310, -columnY[col])
        columnY[col] = columnY[col] + 24
    end
    local function Cell(col)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(300, 32)
        row:SetPoint("TOPLEFT", (col - 1) * 310, -columnY[col])
        columnY[col] = columnY[col] + 36
        return row
    end
    local function Label(row, text, width)
        local label = row:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
        label:SetPoint("LEFT", 0, 0)
        label:SetWidth(width or 132)
        label:SetJustifyH("LEFT")
        label:SetText(text)
        return label
    end
    local function Color(row, field)
        local picker = UI.CreateSimpleColorPicker(row, field.get(), function(r, g, b, a)
            if Valid() then field.set({ r = r, g = g, b = b, a = a or 1 }) end
        end, true)
        picker:SetSize(16, 16)
        picker:SetPoint("LEFT", 140, 0)
    end
    local function Control(col, key, title)
        local field = fields[key]
        if not field then return end
        local row = Cell(col)
        local widget
        if field.kind == "number" then
            widget = UI.CreateCompactSlider(row, title and L[title] or field.label, field.min, field.max, field.get(), field.set)
            widget:SetPoint("LEFT", 0, 0)
            widget:SetWidth(290)
            widget.Label:SetWidth(128)
            widget.Slider:ClearAllPoints()
            widget.Slider:SetPoint("LEFT", 140, 0)
            widget.Slider:SetWidth(108)
            widget:UpdateUIValue(field.get())
        elseif field.kind == "check" then
            widget = UI.CreateCompactCheckbox(row, title and L[title] or field.label, field.get(), field.set)
            widget:SetPoint("LEFT", 0, 0)
            widget:SetWidth(290)
            widget.label:SetWidth(132)
            widget.checkbox:ClearAllPoints()
            widget.checkbox:SetPoint("LEFT", 140, 0)
            if field.tooltip then
                widget.checkbox:HookScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(field.label)
                    GameTooltip:AddLine(field.tooltip, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                widget.checkbox:HookScript("OnLeave", function() GameTooltip:Hide() end)
            end
        else
            Label(row, title and L[title] or field.label)
            if field.kind == "choice" then
                widget = UI.CreateCompactDropdown(row)
                widget:SetSize(150, 26)
                widget:SetPoint("LEFT", 140, 0)
                UI.SetupValueDropdown(widget, field.options, field.get, field.set)
            elseif field.kind == "color" then
                Color(row, field)
            elseif field.kind == "input" then
                widget = UI.CreateCustomEditBox(row)
                widget:SetSize(150, 24)
                widget:SetPoint("LEFT", 140, 0)
                widget:SetText(field.get() or "")
                widget:SetScript("OnEditFocusLost", function(self) if Valid() then field.set(self:GetText()) end end)
            end
        end
    end
    local function TextRow(col, categoryName, enabledKey, colorKey, positionKey)
        local category = sections[L[categoryName]]
        if not category then return end
        local row = Cell(col)
        Label(row, L[categoryName])
        local cog = CreateFrame("Button", nil, row)
        cog:SetSize(20, 24)
        cog:SetPoint("LEFT", 272, 0)
        local glyph = cog:CreateTexture(nil, "ARTWORK")
        glyph:SetSize(20, 20)
        glyph:SetPoint("CENTER")
        glyph:SetTexture("Interface\\AddOns\\" .. AddonName .. "\\Media\\Textures\\wrench.tga")
        glyph:SetVertexColor(CDM.CONST.GOLD.r, CDM.CONST.GOLD.g, CDM.CONST.GOLD.b)
        glyph:SetAlpha(0.8)
        cog:SetScript("OnEnter", function(self)
            glyph:SetAlpha(1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Size and Position"])
            GameTooltip:Show()
        end)
        cog:SetScript("OnLeave", function() glyph:SetAlpha(0.8); GameTooltip:Hide() end)
        local detailFields = {}
        for _, field in ipairs(category) do
            if field.key ~= enabledKey and field.key ~= colorKey and field.key ~= positionKey
                and field.key ~= "timerDecimals" and field.key ~= "decimalThreshold"
                and field.key ~= "smoothBuffBars" then
                detailFields[#detailFields + 1] = field
            end
        end
        cog:SetScript("OnClick", function() ns.ShowFieldMenu(cog, L[categoryName], detailFields, Valid) end)
        Color(row, fields[colorKey])
        local options = { { label = L["Hidden"], value = "HIDDEN" } }
        if positionKey then
            for _, option in ipairs(positions) do options[#options + 1] = option end
        else
            options[#options + 1] = { label = L["Shown"], value = "SHOWN" }
        end
        local dropdown = UI.CreateCompactDropdown(row, { smallText = true })
        dropdown:SetSize(104, 26)
        dropdown:SetPoint("LEFT", 162, 0)
        UI.SetupValueDropdown(dropdown, options, function()
            if not fields[enabledKey].get() then return "HIDDEN" end
            return positionKey and fields[positionKey].get() or "SHOWN"
        end, function(value)
            fields[enabledKey].set(value ~= "HIDDEN")
            if value ~= "HIDDEN" and positionKey then fields[positionKey].set(value) end
        end)
    end
    Header(1, "Bar Layout")
    Control(1, "height", "Height")
    Control(1, "width", "Width (0 = Auto)")
    Control(1, "iconPosition", "Show Icon")
    Control(1, "iconGap", "Icon-Bar Gap")
    if not bar then
        Control(1, "buffBarSpacing", "Spacing")
        Control(1, "buffBarGrowDirection", "Grow Direction")
    end
    Header(1, "Appearance")
    Control(1, "texture", "Bar Texture")
    Control(1, "barColor", "Fill Color")
    Control(1, "bgColor", "Background Color")

    Header(2, "Text")
    TextRow(2, "Name Text", "showName", "nameColor")
    TextRow(2, "Stack Text", "showApplications", "applicationsColor", "applicationsPosition")
    if sections[L["Duration Text"]] then
        TextRow(2, "Duration Text", "showDuration", "durationColor", "durationPosition")
    end
    if bar and bar.barType == M.TYPE_STACK then
        Header(2, "Stack Settings")
        Control(2, "maxStacks", "Max Stacks")
        Control(2, "alwaysShow", "Always Show Bar")
        Control(2, "smoothBuffBars")
        Header(1, "Tick Marks")
        Control(1, "tickValues", "Tick Positions")
        Control(1, "tickWidth", "Tick Width")
        Control(1, "tickColor")
        Header(2, "Threshold Colors")
        local hint = parent:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font12")
        hint:SetPoint("TOPLEFT", 310, -columnY[2])
        hint:SetWidth(290)
        hint:SetJustifyH("LEFT")
        hint:SetText(L["The bar recolors once it reaches this many stacks."])
        UI.SetTextMuted(hint)
        columnY[2] = columnY[2] + math.max(24, hint:GetStringHeight() + 8)
        for index, threshold in ipairs(bar.colorThresholds) do
            if type(threshold) == "table" then
                local row = Cell(2)
                Label(row, L["At Stacks"])
                local input = UI.CreateCustomEditBox(row)
                input:SetSize(50, 24)
                input:SetPoint("LEFT", 140, 0)
                input:SetNumeric(true)
                input:SetMaxLetters(3)
                input:SetText(tostring(threshold.stacks or 1))
                input:SetScript("OnEditFocusLost", function(self)
                    if not Valid() then return end
                    local value = tonumber(self:GetText())
                    if value and value >= 1 then
                        threshold.stacks = math.floor(value)
                        save()
                    end
                    self:SetText(tostring(threshold.stacks or 1))
                end)
                local picker = UI.CreateSimpleColorPicker(row, threshold.color, function(r, g, b, a)
                    if not Valid() then return end
                    threshold.color = { r = r, g = g, b = b, a = a or 1 }
                    save()
                end, true)
                picker:SetSize(16, 16)
                picker:SetPoint("LEFT", input, "RIGHT", 12, 0)
                local remove = UI.CreateTextButton(row)
                remove:SetSize(70, 24)
                remove:SetPoint("LEFT", picker, "RIGHT", 12, 0)
                remove:SetText(L["Remove"])
                remove:SetScript("OnClick", function()
                    if not Valid() then return end
                    table.remove(bar.colorThresholds, index)
                    save()
                    if rebuild then rebuild() end
                end)
            end
        end
        local add = UI.CreateTextButton(parent)
        add:SetSize(140, 24)
        add:SetPoint("TOPLEFT", 450, -columnY[2])
        add:SetText(L["Add Threshold"])
        add:SetScript("OnClick", function()
            if not Valid() then return end
            local highest = 0
            for _, threshold in ipairs(bar.colorThresholds) do
                if type(threshold) == "table" then
                    highest = math.max(highest, tonumber(threshold.stacks) or 0)
                end
            end
            bar.colorThresholds[#bar.colorThresholds + 1] = {
                stacks = math.min(bar.maxStacks, highest + 1),
                color = { r = 1, g = 0.6, b = 0, a = 1 },
            }
            save()
            if rebuild then rebuild() end
        end)
        columnY[2] = columnY[2] + 36
    else
        Header(2, "Timer")
        if bar then Control(2, "timerDecimals") else Control(2, "buffBarDualMode") end
        Control(2, "decimalThreshold")
    end
    parent:SetHeight(math.max(columnY[1], columnY[2]) + 16)
end
