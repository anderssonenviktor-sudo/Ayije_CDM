local AddonName = "Ayije_CDMDev"
local CDM = _G[AddonName]
local ns, L = CDM._OptionsNS, CDM.L
local UI = ns.ConfigUI
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition
local GetSpellName = C_Spell.GetSpellName
local GOLD = CDM.CONST.GOLD
local overlay, panels
local activeCategory
local fieldGeneration = 0
local pickerSession, pickerBlocker

local function CommitInputs()
    if not panels then return end
    for _, row in ipairs(panels[2].rows) do
        if row.edit and row.edit:HasFocus() then row.edit:ClearFocus() end
    end
end

local function FinishPicker()
    local session = pickerSession
    if not session then return end
    pickerSession = nil
    pickerBlocker:Hide()
    ColorPickerFrame:SetFrameStrata(session.strata)
    ColorPickerFrame:SetFrameLevel(session.level)
    ColorPickerFrame:SetClampedToScreen(session.clamped)
    ColorPickerFrame:ClearAllPoints()
    for _, point in ipairs(session.points) do ColorPickerFrame:SetPoint(unpack(point)) end
end

local function OpenColorPicker(info)
    UI.CloseAllDropdownMenus()
    if ColorPickerFrame:IsShown() then ColorPickerFrame:Hide() end
    if not pickerBlocker then
        pickerBlocker = CreateFrame("Button", nil, UIParent)
        pickerBlocker:SetAllPoints()
        pickerBlocker:SetFrameStrata("FULLSCREEN_DIALOG")
        pickerBlocker:EnableMouse(true)
        pickerBlocker:EnableMouseWheel(true)
        pickerBlocker:SetScript("OnMouseWheel", function() end)
        ColorPickerFrame:HookScript("OnHide", FinishPicker)
    end
    local session = {
        strata = ColorPickerFrame:GetFrameStrata(),
        level = ColorPickerFrame:GetFrameLevel(),
        clamped = ColorPickerFrame:IsClampedToScreen(),
        points = {},
    }
    for i = 1, ColorPickerFrame:GetNumPoints() do
        session.points[i] = { ColorPickerFrame:GetPoint(i) }
    end
    pickerSession = session
    pickerBlocker:Show()
    ColorPickerFrame:SetupColorPickerAndShow(info)
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    ColorPickerFrame:SetFrameLevel(pickerBlocker:GetFrameLevel() + 10)
    ColorPickerFrame:SetClampedToScreen(true)
    ColorPickerFrame:ClearAllPoints()
    ColorPickerFrame:SetPoint("CENTER", ns.ConfigFrame or UIParent, "CENTER")
end

local function Close()
    CommitInputs()
    if pickerSession then ColorPickerFrame:Hide() end
    fieldGeneration = fieldGeneration + 1
    activeCategory = nil
    if overlay then overlay:Hide() end
end
ns.CloseSpellMenu = Close

local function CreatePanel(parent, width)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetWidth(width)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    frame:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b, 1)
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 5, -33)
    divider:SetPoint("TOPRIGHT", -5, -33)
    divider:SetHeight(1)
    divider:SetColorTexture(0.31, 0.34, 0.35, 0.55)
    frame.rows = {}
    return frame
end

local function EnsureFrames()
    if overlay then return end
    overlay = CreateFrame("Button", "AyijeCDMDevSpellMenu", UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("DIALOG")
    overlay:RegisterForClicks("AnyUp")
    overlay:SetScript("OnClick", Close)
    overlay:SetScript("OnHide", function()
        if pickerSession then ColorPickerFrame:Hide() end
        activeCategory = nil
        fieldGeneration = fieldGeneration + 1
    end)
    overlay:Hide()
    tinsert(UISpecialFrames, "AyijeCDMDevSpellMenu")
    panels = { CreatePanel(overlay, 185), CreatePanel(overlay, 266) }
    for i, panel in ipairs(panels) do panel:SetFrameLevel(overlay:GetFrameLevel() + i * 10) end
end

local function Clear(panel)
    for _, row in ipairs(panel.rows) do row:Hide() end
    panel:Hide()
end

local function Row(panel, index, y)
    local row = panel.rows[index]
    if not row then
        row = CreateFrame("Button", nil, panel)
        row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        row:GetHighlightTexture():SetVertexColor(0.7, 0.75, 0.78, 0.12)
        row.label = row:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
        row.label:SetPoint("LEFT", 7, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.arrow = row:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
        row.arrow:SetPoint("RIGHT", -7, 0)
        row.arrow:SetText(">")
        row.arrow:SetTextColor(0.72, 0.75, 0.77)
        panel.rows[index] = row
    end
    row:ClearAllPoints()
    local inset = panel == panels[1] and 4 or 12
    row:SetPoint("TOPLEFT", inset, -y)
    row:SetSize(panel:GetWidth() - inset * 2, 28)
    row:EnableMouse(true)
    row:UnlockHighlight()
    row.arrow:Hide()
    row.setValue = nil
    row.category = nil
    row.label:Show()
    row.label:SetWidth(panel:GetWidth() - 46)
    row.label:SetTextColor(0.73, 0.77, 0.79)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnClick", nil)
    for _, key in ipairs({ "color", "edit", "check", "dropdown" }) do
        if row[key] then row[key]:Hide() end
    end
    if row.edit then row.edit:SetScript("OnEditFocusLost", nil) end
    if row.sliders then
        for _, slider in pairs(row.sliders) do slider:Hide() end
    end
    row:Show()
    return row
end

local function Beside(panel, owner, anchor)
    panel:ClearAllPoints()
    local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local right = (owner:GetRight() or 0) * scale
    if right + panel:GetWidth() > UIParent:GetWidth() then
        panel:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -5, 0)
    else
        panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 5, 0)
    end
    panel:Show()
end

local function RefreshCategoryLabels()
    if not panels then return end
    for _, row in ipairs(panels[1].rows) do
        if row.category then
            if row.category.enabled and row.category.enabled() then
                row.label:SetTextColor(0.25, 0.85, 0.45)
            else
                row.label:SetTextColor(0.73, 0.77, 0.79)
            end
        end
    end
end

local function ShowFields(category, anchor, valid, standalone)
    if pickerSession then return end
    if InCombatLockdown() or not valid() then Close(); return end
    if activeCategory == category and panels[2]:IsShown() then return end
    CommitInputs()
    activeCategory = category
    fieldGeneration = fieldGeneration + 1
    local generation = fieldGeneration
    Clear(panels[2])
    for _, row in ipairs(panels[1].rows) do
        row:UnlockHighlight()
    end
    if panels[1].rows[1] then panels[1].rows[1].label:SetTextColor(0.9, 0.91, 0.92) end
    if anchor.LockHighlight then anchor:LockHighlight() end
    RefreshCategoryLabels()
    local heading = Row(panels[2], 1, 8)
    heading:EnableMouse(false)
    heading.label:SetText(category.label)
    heading.label:ClearAllPoints()
    heading.label:SetPoint("LEFT")
    heading.label:SetTextColor(0.9, 0.91, 0.92)
    local y = 36
    local fields = type(category.fields) == "function" and category.fields() or category.fields
    for i, field in ipairs(fields) do
        local row = Row(panels[2], i + 1, y)
        local function Set(value)
            if generation ~= fieldGeneration then return end
            if InCombatLockdown() or not valid() then Close(); return end
            field.set(value)
            RefreshCategoryLabels()
            if field.refresh then
                activeCategory = nil
                ShowFields(category, anchor, valid, standalone)
            end
        end
        local value = field.get and field.get()
        row.setValue = Set
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT")
        row.label:SetText(field.label)
        row:EnableMouse(false)
        if field.kind == "check" then
            if not row.check then
                row.check = UI.CreateCompactCheckbox(row, "", false, function(v)
                    if row.setValue then row.setValue(v) end
                end)
                row.check:SetPoint("LEFT")
                row.check:SetWidth(242)
                row.check.label:SetWidth(204)
                row.check.label:SetFontObject("AyijeCDM_Font12")
                row.check.checkbox:SetSize(16, 16)
            end
            row.label:Hide()
            row.check.label:SetText(field.label)
            row.check:SetChecked(value)
            row.check:Show()
        elseif field.kind == "number" then
            local low, high = field.min or 0, field.max or 100
            local key = low .. ":" .. high
            row.sliders = row.sliders or {}
            local slider = row.sliders[key]
            if not slider then
                slider = UI.CreateCompactSlider(row, "", low, high, value or low, function(v)
                    if row.setValue then row.setValue(v) end
                end)
                slider:SetPoint("LEFT")
                slider:SetWidth(242)
                slider.Label:SetWidth(110)
                slider.Slider:ClearAllPoints()
                slider.Slider:SetPoint("LEFT", 116, 0)
                slider.Slider:SetWidth(84)
                slider.Label:SetFontObject("AyijeCDM_Font12")
                slider.Input:SetFontObject("AyijeCDM_Font12")
                row.sliders[key] = slider
            end
            row.label:Hide()
            slider.Label:SetText(field.label)
            slider:UpdateUIValue(value or low)
            slider:Show()
        elseif field.kind == "color" then
            if not row.color then
                row.color = UI.CreateSimpleColorPicker(row, nil)
                row.color:SetPoint("RIGHT", -9, 0)
                row.color:SetSize(16, 16)
            end
            row.color:SetScript("OnClick", function()
                local previous = field.get() or { r = 1, g = 1, b = 1 }
                local restore = field.captureRestore and field.captureRestore()
                local function Apply(color)
                    if generation ~= fieldGeneration then return end
                    Set(color)
                    row.color:UpdateColor(color.r, color.g, color.b, color.a or 1)
                end
                OpenColorPicker({
                    r = previous.r, g = previous.g, b = previous.b,
                    hasOpacity = field.hasOpacity == true,
                    opacity = previous.a or 1,
                    swatchFunc = function()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        local a = field.hasOpacity and ColorPickerFrame:GetColorAlpha() or previous.a or 1
                        Apply({ r = r, g = g, b = b, a = a })
                    end,
                    opacityFunc = function()
                        if not field.hasOpacity then return end
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        Apply({ r = r, g = g, b = b, a = ColorPickerFrame:GetColorAlpha() })
                    end,
                    cancelFunc = function()
                        if generation ~= fieldGeneration or not valid() or InCombatLockdown() then return end
                        if restore then
                            restore()
                            row.color:UpdateColor(previous.r, previous.g, previous.b, previous.a or 1)
                            RefreshCategoryLabels()
                        else
                            Apply(previous)
                        end
                    end,
                })
            end)
            local color = value or { r = 1, g = 1, b = 1 }
            row.color:UpdateColor(color.r, color.g, color.b, color.a or 1)
            row.color:Show()
        elseif field.kind == "choice" then
            if not row.dropdown then
                row.dropdown = UI.CreateCompactDropdown(row, { keepSpellMenu = true, smallText = true })
                row.dropdown:SetPoint("RIGHT")
                row.dropdown:SetWidth(136)
            end
            row.label:SetWidth(100)
            UI.SetupValueDropdown(row.dropdown, field.options, field.get, Set)
            row.dropdown:Show()
        elseif field.kind == "input" then
            if not row.edit then
                row.edit = UI.CreateCustomEditBox(row)
                row.edit:SetPoint("RIGHT", 0, 0)
                row.edit:SetSize(136, 24)
                row.edit:SetFontObject("AyijeCDM_Font12")
                row.edit:SetAutoFocus(false)
            end
            row.label:SetWidth(100)
            row.edit:SetText(tostring(value or ""))
            row.edit:SetScript("OnEnter", function(self)
                if not field.hint then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(field.hint)
                GameTooltip:Show()
            end)
            row.edit:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.edit:SetScript("OnEditFocusLost", function(self) Set(self:GetText()) end)
            row.edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            row.edit:SetScript("OnEscapePressed", function(self)
                self:SetText(tostring(field.get() or "")); self:ClearFocus()
            end)
            row.edit:Show()
        else
            row:EnableMouse(true)
            row:SetScript("OnClick", function()
                if InCombatLockdown() or not valid() then Close(); return end
                Close()
                field.set()
            end)
        end
        y = y + 30
    end
    panels[2]:SetHeight(y + 8)
    Beside(panels[2], standalone and anchor or panels[1], anchor)
end

function ns.ShowFieldMenu(owner, title, fields, valid)
    if InCombatLockdown() or not valid() then return end
    Close()
    EnsureFrames()
    UI.CloseAllDropdownMenus()
    Clear(panels[1])
    Clear(panels[2])
    GameTooltip:Hide()
    overlay:Show()
    ShowFields({ label = title, fields = fields }, owner, valid, true)
end

function ns.ShowCascadeMenu(title, categories, valid)
    if InCombatLockdown() or not valid() then return end
    EnsureFrames()
    UI.CloseAllDropdownMenus()
    for _, panel in ipairs(panels) do Clear(panel) end
    GameTooltip:Hide()
    overlay:Show()
    local heading = Row(panels[1], 1, 6)
    heading.label:SetText(title or L["Unknown"])
    heading.label:SetTextColor(0.9, 0.91, 0.92)
    heading:EnableMouse(false)
    for i, category in ipairs(categories) do
        local button = Row(panels[1], i + 1, 36 + (i - 1) * 26)
        button:SetHeight(26)
        button.label:SetWidth(145)
        button.label:SetText(category.label)
        button.category = category
        button.arrow:Show()
        local function Open() ShowFields(category, button, valid) end
        button:SetScript("OnEnter", Open)
        button:SetScript("OnClick", Open)
    end
    RefreshCategoryLabels()
    panels[1]:SetHeight(42 + #categories * 26)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    panels[1]:ClearAllPoints()
    panels[1]:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    panels[1]:Show()
    if ns.ConfigFrame and not ns.ConfigFrame.acdmCascadeCloseHook then
        ns.ConfigFrame.acdmCascadeCloseHook = true
        ns.ConfigFrame:HookScript("OnHide", Close)
    end
end

CDM:RegisterEvent("PLAYER_REGEN_DISABLED", Close)

function ns.OpenSpellCascade(owner, cfg)
    local profile = CDM.db
    local function Valid() return CDM.db == profile and cfg.valid() end
    local durationKeys = { "cooldownFontSize", "cooldownColor" }
    local prefix = cfg.buff and "count" or "charge"
    local stackKeys = { prefix .. "FontSize", prefix .. "Color", prefix .. "Position", prefix .. "OffsetX", prefix .. "OffsetY" }
    if cfg.buff then
        for _, key in ipairs({ "stackTextThresholdEnabled", "stackTextThreshold", "stackTextThresholdColor" }) do
            stackKeys[#stackKeys + 1] = key
        end
    end
    local textKeys = {}
    for _, key in ipairs(durationKeys) do textKeys[key] = true end
    for _, key in ipairs(stackKeys) do textKeys[key] = true end
    local function HasTextValues(ov, keys)
        if not ov.textOverride then return false end
        for _, key in ipairs(keys) do
            if key:find("^stackTextThreshold") then
                if ov.stackTextThresholdEnabled then return true end
            elseif ov[key] ~= nil then
                return true
            end
        end
        return false
    end
    local function ResetText(keys)
        return { label = L["Use Default"], kind = "action", set = function()
            local ov = cfg.read()
            if not ov then return end
            ov = cfg.ensure()
            for _, key in ipairs(keys) do ov[key] = nil end
            cfg.save()
        end }
    end
    local function Field(label, kind, key, default, extra)
        local f = extra or {}
        f.label, f.kind = L[label], kind
        f.get = function()
            local ov = cfg.read()
            local value = ov and ov[key]
            if textKeys[key] and not (ov and ov.textOverride) then value = nil end
            if value == nil then return default end
            return value
        end
        f.set = function(value)
            local ov = cfg.ensure()
            if not ov then return end
            if textKeys[key] then ov.textOverride = true end
            if key == "cooldownSwipe" and value == "default" then ov[key] = nil else ov[key] = value end
            cfg.save()
        end
        if kind == "color" then
            f.captureRestore = function()
                local ov = cfg.read()
                local previous = ov and ov[key]
                local previousTextOverride = ov and ov.textOverride
                return function()
                    local current = cfg.ensure()
                    if not current then return end
                    current[key] = previous
                    if textKeys[key] then current.textOverride = previousTextOverride end
                    cfg.save()
                end
            end
        end
        return f
    end
    local function Check(label, key, default) return Field(label, "check", key, default or false) end
    local function Number(label, key, default, low, high) return Field(label, "number", key, default, { min = low, max = high }) end
    local function Color(label, key, default) return Field(label, "color", key, default or { r = 1, g = 1, b = 1, a = 1 }) end
    local function Category(label, fields)
        return { label = L[label], fields = fields, enabled = function()
            local ov = cfg.read() or {}
            if label == "Duration Text" then
                return HasTextValues(ov, durationKeys)
            elseif label == "Stacks (Charges)" then
                return HasTextValues(ov, stackKeys)
            elseif label == "Buff Display" then
                return ov.hideCooldown == true or ov.hideVisuals == true or (cfg.staticDisplay and ov.placeholder == true)
            elseif label == "Glow" then
                return CDM:GetSpellGlowEnabled(cfg.specID, cfg.spellID) or CDM:GetSpellStackGlow(cfg.specID, cfg.spellID)
            elseif label == "Cooldown Saturation" then
                return ov.keepColoredOnCooldown == true
            elseif label == "Threshold Text" then
                return (tonumber(ov.thresholdSeconds) or 0) > 0
                    and (ov.thresholdDecimals == true or ov.thresholdColorEnabled == true)
            elseif label == "Cooldown Swipe" then
                return ov.cooldownSwipe == "reverse" or ov.cooldownSwipe == "hide" or ov.suppressGCD == true
            elseif label == "Replace with Buff" then
                return (tonumber(ov.replaceBuffSpellID) or 0) > 0
            elseif label == "Glow Overrides" then
                return (ov.glowType ~= nil and ov.glowType ~= false and ov.glowType ~= "default")
                    or ov.readyGlowEnabled == true or ov.glowColorOverride == true
            end
            return false
        end }
    end
    local positionOptions = {}
    for _, position in ipairs({"CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}) do
        positionOptions[#positionOptions + 1] = { value = position, label = L[position] }
    end
    local buff = cfg.buff
    local defaults = cfg.defaults or {}
    local categories = {
        Category("Duration Text", {
            Number("Cooldown Size", "cooldownFontSize", defaults.cooldownFontSize or 15, 6, 32),
            Color("Cooldown Color", "cooldownColor", defaults.cooldownColor),
            ResetText(durationKeys),
        }),
        Category("Stacks (Charges)", {
            Number("Font Size", prefix .. "FontSize", defaults[prefix .. "FontSize"] or 15, 6, 32),
            Color("Color", prefix .. "Color", defaults[prefix .. "Color"]),
            Field("Position", "choice", prefix .. "Position", defaults[prefix .. "Position"] or "BOTTOMRIGHT", { options = positionOptions }),
            Number("X Offset", prefix .. "OffsetX", defaults[prefix .. "OffsetX"] or 0, -20, 20),
            Number("Y Offset", prefix .. "OffsetY", defaults[prefix .. "OffsetY"] or 0, -20, 20),
            ResetText(stackKeys),
        }),
    }
    if buff then
        categories[#categories + 1] = Category("Buff Display", {
            Check("Hide Cooldown Timer", "hideCooldown"),
            Check("Hide Icon", "hideVisuals"),
        })
        categories[#categories + 1] = Category("Glow", {
            { label = L["Enable Glow"], kind = "check", get = function() return CDM:GetSpellGlowEnabled(cfg.specID, cfg.spellID) end,
              set = function(v) CDM:SetSpellGlowEnabled(cfg.specID, cfg.spellID, v or nil); cfg.save() end },
            { label = L["Glow Color"], kind = "color", get = function() return CDM:GetSpellGlowColor(cfg.specID, cfg.spellID) end,
              set = function(v) CDM:SetSpellGlowColor(cfg.specID, cfg.spellID, v); cfg.save() end,
              captureRestore = function()
                  local previous = CDM:GetSpellGlowColor(cfg.specID, cfg.spellID)
                  return function() CDM:SetSpellGlowColor(cfg.specID, cfg.spellID, previous); cfg.save() end
              end },
        })
    else
        categories[#categories + 1] = Category("Cooldown Saturation", {
            Check("Keep Colored (On CD)", "keepColoredOnCooldown"),
        })
        categories[#categories + 1] = Category("Threshold Text", {
            Number("Threshold Seconds", "thresholdSeconds", 0, 0, 59),
            Check("Threshold Decimals", "thresholdDecimals"),
            Check("Threshold Color", "thresholdColorEnabled"),
            Color("Color", "thresholdColor", { r = 1, g = 0.2, b = 0.2 }),
        })
        categories[#categories + 1] = Category("Cooldown Swipe", {
            Field("Swipe", "choice", "cooldownSwipe", "default", { options = {
                { value = "default", label = L["Default"] },
                { value = "reverse", label = L["Reverse Swipe"] },
                { value = "hide", label = L["Hide CD Swipe"] },
            } }),
            Check("Suppress GCD", "suppressGCD"),
        })
        if CDM.GetBuffReplacementOptions and cfg.specID == CDM:GetCurrentSpecID() then
            categories[#categories + 1] = Category("Replace with Buff", {
                { label = L["Buff"], kind = "choice", options = function() return CDM:GetBuffReplacementOptions() end,
                    get = function()
                        local entry = cfg.read()
                        return entry and entry.replaceBuffCooldownID or 0
                    end,
                    set = function(value)
                        local entry = cfg.ensure()
                        if not entry then return end
                        for _, option in ipairs(CDM:GetBuffReplacementOptions()) do
                            if option.value == value then
                                CDM:SetBuffReplacement(entry, option, cfg.specID)
                                cfg.save()
                                return
                            end
                        end
                    end,
                },
            })
        end
        categories[#categories + 1] = Category("Glow Overrides", {
            Field("Glow Type", "choice", "glowType", "default", { options = {
                { value = "default", label = L["Default"] },
                { value = "pixel", label = L["Pixel Glow"] },
                { value = "autocast", label = L["Autocast Glow"] },
                { value = "button", label = L["Button Glow"] },
                { value = "proc", label = L["Proc Glow"] },
                { value = "gcd", label = L["GCD"] },
                { value = "shape", label = L["Shape Glow"] },
            } }),
            Check("Glow When Ready", "readyGlowEnabled"),
            Color("Glow Color", "readyGlowColor"),
            Check("Override Glow Color", "glowColorOverride"),
            Color("Custom Color", "glowColor"),
        })
    end
    if buff then
        local function Action(label, callback)
            return { label = L[label], kind = "action", set = callback }
        end
        local function Integer(label, get, set)
            return { label = L[label], kind = "input", get = get, set = function(value)
                value = tonumber(value)
                if value and value == value and value < math.huge then set(math.max(1, math.floor(value))) end
            end }
        end
        local function Get(key, fallback)
            local ov = cfg.read()
            if ov and ov[key] ~= nil then return ov[key] end
            return fallback
        end
        local function AddCategory(label, fields, enabled)
            categories[#categories + 1] = { label = L[label], fields = fields, enabled = enabled }
        end
        local stackFields = categories[2].fields
        table.insert(stackFields, #stackFields, Check("Color at Stacks", "stackTextThresholdEnabled"))
        table.insert(stackFields, #stackFields, Integer("Stacks >=", function() return Get("stackTextThreshold", 2) end,
            function(value) Field("", "input", "stackTextThreshold").set(value) end))
        table.insert(stackFields, #stackFields, Color("Threshold Color", "stackTextThresholdColor", { r = 1, g = 0, b = 0 }))
        if cfg.staticDisplay and not cfg.customBuff then
            categories[3].fields[#categories[3].fields + 1] = Check("Show Placeholder", "placeholder")
        end
        local glowFields = categories[4].fields
        local function SetStackGlow(key, value)
            local enabled, threshold, operator = CDM:GetSpellStackGlow(cfg.specID, cfg.spellID)
            if key == "enabled" then enabled = value
            elseif key == "threshold" then threshold = value
            else operator = value end
            CDM:SetSpellStackGlow(cfg.specID, cfg.spellID, enabled, threshold, operator)
            cfg.save()
        end
        glowFields[1].refresh = true
        glowFields[#glowFields + 1] = { label = L["Glow at Stacks"], kind = "check", refresh = true,
            get = function() return CDM:GetSpellStackGlow(cfg.specID, cfg.spellID) end,
            set = function(value) SetStackGlow("enabled", value) end }
        glowFields[#glowFields + 1] = { label = L["Condition"], kind = "choice", options = {
            { label = "<", value = "lt" }, { label = "<=", value = "lte" }, { label = "==", value = "eq" },
            { label = ">=", value = "gte" }, { label = ">", value = "gt" },
        }, get = function() local _, _, operator = CDM:GetSpellStackGlow(cfg.specID, cfg.spellID); return operator end,
        set = function(value) SetStackGlow("operator", value) end }
        glowFields[#glowFields + 1] = Integer("Stacks", function()
            local _, threshold = CDM:GetSpellStackGlow(cfg.specID, cfg.spellID); return threshold
        end, function(value) SetStackGlow("threshold", value) end)

        AddCategory("Custom Icon", {
            Action("Choose Icon", function()
                UI.ShowCustomIconPopup(Get("customIcon"), function(result)
                    if not Valid() or InCombatLockdown() then return end
                    local ov = cfg.ensure()
                    if not ov then return end
                    ov.customIcon = result
                    if result then CDM.API.buffCustomIconsInUse = true end
                    cfg.save()
                end)
            end),
            Action("Use Default", function()
                local ov = cfg.ensure()
                if ov then ov.customIcon = nil; cfg.save() end
            end),
        }, function() return Get("customIcon") ~= nil end)

        local function AlertFields(mode)
            local sound = mode == "sound"
            local other = sound and "tts" or "sound"
            local fields = { { label = L[sound and "Play Sound" or "Text to Speech"], kind = "check", refresh = true,
                get = function() return Get(mode .. "Enabled", false) end,
                set = function(value)
                    local ov = cfg.ensure()
                    if not ov then return end
                    ov[mode .. "Enabled"] = value or nil
                    local clear = value and other or mode
                    ov[clear .. "Enabled"] = nil
                    for _, event in ipairs({ "OnShow", "OnHide" }) do
                        ov[clear .. event], ov[clear .. event .. "Enabled"] = nil, nil
                    end
                    if value and not ov[mode .. "OnShowEnabled"] and not ov[mode .. "OnHideEnabled"] then
                        ov[mode .. "OnShowEnabled"] = true
                    end
                    cfg.save()
                end } }
            if not Get(mode .. "Enabled") then return fields end
            for _, event in ipairs({ "OnShow", "OnHide" }) do
                local key, enableKey = mode .. event, mode .. event .. "Enabled"
                fields[#fields + 1] = { label = L[event == "OnShow" and "On Show" or "On Hide"], kind = "check", refresh = true,
                    get = function() return Get(enableKey, false) end,
                    set = function(value)
                        local ov = cfg.ensure()
                        if not ov then return end
                        local otherEvent = event == "OnShow" and "OnHide" or "OnShow"
                        if not value and not ov[mode .. otherEvent .. "Enabled"] then return end
                        ov[enableKey] = value or nil
                        if not value then ov[key] = nil end
                        cfg.save()
                    end }
                if Get(enableKey) then
                    if sound then
                        fields[#fields + 1] = { label = L["Sound"], kind = "choice",
                            options = function()
                                local options = { { label = L["None"], value = "None" } }
                                for _, name in ipairs(LibStub("LibSharedMedia-3.0"):List("sound")) do
                                    if name ~= "None" then options[#options + 1] = { label = name, value = name } end
                                end
                                return options
                            end,
                            get = function() return Get(key, "None") end,
                            set = function(value)
                                local ov = cfg.ensure()
                                if not ov then return end
                                ov[key] = value ~= "None" and value or nil
                                cfg.save()
                            end }
                    else
                        fields[#fields + 1] = { label = L["Text"], kind = "input", hint = L["(empty = spell name)"], get = function() return Get(key, "") end,
                            set = function(value)
                                local ov = cfg.ensure()
                                if not ov then return end
                                ov[key] = value ~= "" and value or nil
                                cfg.save()
                            end }
                    end
                end
            end
            if not sound then
                fields[#fields + 1] = Action("Voice Settings", function()
                    if ChatConfigFrame then
                        ChatConfigFrame:Show()
                        if ChatConfigFrameChatTabManager and VOICE_WINDOW_ID then
                            ChatConfigFrameChatTabManager:UpdateSelection(VOICE_WINDOW_ID)
                        end
                    end
                end)
            end
            return fields
        end
        AddCategory("Sound", function() return AlertFields("sound") end, function() return Get("soundEnabled", false) end)
        AddCategory("Text to Speech", function() return AlertFields("tts") end, function() return Get("ttsEnabled", false) end)
        if cfg.customBuff then
            -- Custom timers own their text and visibility; native viewer overrides do not apply.
            table.remove(categories, 3)
            table.remove(categories, 2)
            table.remove(categories, 1)
            if cfg.editCustom then
                local actions = { Action("Settings", cfg.editCustom) }
                if cfg.reorderCustom then
                    actions[#actions + 1] = Action("Move Left", function() cfg.reorderCustom(-1) end)
                    actions[#actions + 1] = Action("Move Right", function() cfg.reorderCustom(1) end)
                end
                if cfg.removeCustom then actions[#actions + 1] = Action("Remove", cfg.removeCustom) end
                AddCategory("Custom Buff", actions)
            end
        end
    end
    if cfg.remove then
        categories[#categories + 1] = Category("Group", {
            { label = L["Remove from group"], kind = "action", set = function() Close(); cfg.remove() end },
        })
    end
    ns.ShowCascadeMenu(GetSpellName(cfg.spellID) or L["Unknown"], categories, Valid)
end
