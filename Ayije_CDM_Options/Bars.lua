local Runtime = _G["Ayije_CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns.ConfigUI
local L = Runtime.L


local function CreateBarsTab(page, tabId)
    local barsScrollChild = UI.CreateScrollableTab(page, "AyijeCDM_BarsScrollFrame", 900, 370)

    local layout = UI.CreateVerticalLayout(0)
    local function NextY(spacing) return layout:Next(spacing) end

    -- Decimal duration timers: opt a buff in from Blizzard's tracked buff-bar
    -- list and its bar shows decimal remaining time that ticks in combat.
    local function CurrentSpecID()
        local si = GetSpecialization()
        return si and GetSpecializationInfo(si) or nil
    end

    local timerHeader = UI.CreateHeader(barsScrollChild, L["Decimal Duration Timers"])
    timerHeader:SetPoint("TOPLEFT", 0, NextY(0))

    local timerNote = barsScrollChild:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    timerNote:SetText(L["Add a tracked buff to show decimal duration text that keeps ticking in combat."])
    if UI.SetTextMuted then UI.SetTextMuted(timerNote) end
    timerNote:SetPoint("TOPLEFT", 0, NextY(28))

    local timerDropdown = CreateFrame("DropdownButton", nil, barsScrollChild, "WowStyle1DropdownTemplate")
    timerDropdown:SetWidth(280)
    timerDropdown:SetDefaultText(L["Add a tracked buff..."])
    timerDropdown:SetPoint("TOPLEFT", 0, NextY(26))

    -- Rows for the added spells; rebuilt in place. Anchored below the dropdown.
    local timerRows = {}
    local rowsAnchor = timerDropdown
    local RebuildTimerList

    local function SpellAdded(spellID)
        for _, cfg in ipairs(CDM.GetBuffBarTimerBars(CurrentSpecID())) do
            if cfg.spellID == spellID then return true end
        end
        return false
    end

    timerDropdown:SetupMenu(function(_, rootDescription)
        local tracked = CDM.GetBuffBarTrackedSpells and CDM.GetBuffBarTrackedSpells() or {}
        if #tracked == 0 then
            rootDescription:CreateButton(L["(No tracked buffs found)"], function() end)
            return
        end
        for _, entry in ipairs(tracked) do
            local label = entry.name or ("Spell " .. entry.spellID)
            if entry.icon then label = "|T" .. entry.icon .. ":16:16:0:0|t " .. label end
            if SpellAdded(entry.spellID) then label = label .. " |cff888888(" .. L["added"] .. ")|r" end
            rootDescription:CreateButton(label, function()
                if SpellAdded(entry.spellID) then return end
                local bars = CDM.EnsureBuffBarTimerBars(CurrentSpecID())
                if not bars then return end
                -- cooldownInfo only carries the override id while talented, so
                -- capture the base or the bar goes dark once untalented.
                local rawBase = C_Spell and C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(entry.spellID)
                local base = (rawBase and rawBase ~= entry.spellID) and rawBase or nil
                bars[#bars + 1] = {
                    spellID = entry.spellID,
                    baseSpellID = base,
                    name = entry.name,
                    timerDecimalThreshold = 5,
                }
                API:Refresh("BUFF_DATA", "STYLE", "LAYOUT")
                RebuildTimerList()
            end)
        end
    end)

    RebuildTimerList = function()
        for _, row in ipairs(timerRows) do row:Hide() end

        local bars = CDM.GetBuffBarTimerBars(CurrentSpecID())
        local rowH = 30
        for i, cfg in ipairs(bars) do
            local row = timerRows[i]
            if not row then
                row = CreateFrame("Frame", nil, barsScrollChild)
                row:SetSize(560, rowH)

                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(20, 20)
                row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                row.name = row:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.name:SetWidth(180)
                row.name:SetJustifyH("LEFT")
                row.name:SetWordWrap(false)

                -- Min 3 matches the runtime clamp; lower is silently raised.
                row.threshold = UI.CreateModernSlider(
                    row, L["Decimals <"], 3, 30, 5,
                    function(v)
                        row._cfg.timerDecimalThreshold = UI.RoundToInt(v)
                        API:Refresh("BUFF_DATA")
                    end,
                    70, 120
                )
                row.threshold:SetPoint("LEFT", row.name, "RIGHT", 6, 8)

                row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.remove:SetSize(60, 22)
                row.remove:SetPoint("LEFT", row.threshold, "RIGHT", 10, -8)
                row.remove:SetText(REMOVE or L["Remove"])
                row.remove:SetScript("OnClick", function()
                    local list = CDM.GetBuffBarTimerBars(CurrentSpecID())
                    for idx = #list, 1, -1 do
                        if list[idx] == row._cfg then table.remove(list, idx); break end
                    end
                    API:Refresh("BUFF_DATA", "STYLE", "LAYOUT")
                    RebuildTimerList()
                end)

                timerRows[i] = row
            end

            row._cfg = cfg
            local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(cfg.spellID)
            row.icon:SetTexture(icon or 134400)
            local name = cfg.name or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(cfg.spellID)) or ("Spell " .. tostring(cfg.spellID))
            row.name:SetText(name)
            if row.threshold.UpdateUIValue then
                row.threshold:UpdateUIValue(cfg.timerDecimalThreshold or 5)
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", rowsAnchor, "BOTTOMLEFT", 0, -8 - (i - 1) * (rowH + 4))
            row:Show()
        end
    end

    RebuildTimerList()

    -- Reserve space for the rows so Dimensions below never overlaps them.
    local MAX_TIMER_ROWS = 8
    NextY(8 + MAX_TIMER_ROWS * 34 + 16)

    local dimensionsHeader = UI.CreateHeader(barsScrollChild, L["Dimensions"])
    dimensionsHeader:SetPoint("TOPLEFT", 0, NextY(0))

    page.controls.buffBarWidthSlider = UI.CreateModernSlider(
        barsScrollChild,
        L["Bar Width (0 = Auto)"],
        0,
        600,
        CDM.db.buffBarWidth or 0,
        function(v)
            local value = UI.RoundToInt(v)
            if value > 0 and value < 60 then
                value = 60
                page.controls.buffBarWidthSlider.Slider:SetValue(60)
            end
            CDM.db.buffBarWidth = value
            API:Refresh("LAYOUT")
        end
    )
    page.controls.buffBarWidthSlider:SetPoint("TOPLEFT", 0, NextY(30))

    page.controls.buffBarHeightSlider = UI.CreateModernSlider(
        barsScrollChild,
        L["Bar Height"],
        4,
        40,
        CDM.db.buffBarHeight or 20,
        function(v)
            CDM.db.buffBarHeight = UI.RoundToInt(v)
            API:Refresh("LAYOUT")
        end
    )
    page.controls.buffBarHeightSlider:SetPoint("TOPLEFT", 0, NextY(60))

    page.controls.buffBarSpacingSlider = UI.CreateModernSlider(
        barsScrollChild,
        L["Bar Spacing"],
        -1,
        20,
        CDM.db.buffBarSpacing or 2,
        function(v)
            CDM.db.buffBarSpacing = UI.RoundToInt(v)
            API:Refresh("LAYOUT")
        end
    )
    page.controls.buffBarSpacingSlider:SetPoint("TOPLEFT", 0, NextY(60))

    local appearanceHeader = UI.CreateHeader(barsScrollChild, L["Appearance"])
    appearanceHeader:SetPoint("TOPLEFT", 0, NextY(70))

    local textureLabel = barsScrollChild:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    textureLabel:SetText(L["Bar Texture:"])
    textureLabel:SetPoint("TOPLEFT", 0, NextY(30))

    local ddBarTexture = CreateFrame("DropdownButton", nil, barsScrollChild, "WowStyle1DropdownTemplate")
    ddBarTexture:SetPoint("TOPLEFT", 0, NextY(20))
    ddBarTexture:SetWidth(220)
    ddBarTexture:SetDefaultText(CDM.db.buffBarTexture or "Blizzard")
    page.barTextureDropdown = ddBarTexture

    UI.SetupMediaDropdown(
        ddBarTexture,
        "statusbar",
        function() return CDM.db.buffBarTexture or "Blizzard" end,
        function(name)
            CDM.db.buffBarTexture = name
            API:Refresh("STYLE")
        end,
        function(name)
            ddBarTexture:SetDefaultText(name or "Blizzard")
        end
    )

    page.controls.buffBarColorPicker = UI.CreateColorSwatch(barsScrollChild, L["Bar Color"], "buffBarColor", "STYLE")
    page.controls.buffBarColorPicker:SetPoint("TOPLEFT", 0, NextY(50))

    page.controls.buffBarBgColorPicker = UI.CreateColorSwatch(barsScrollChild, L["Background Color"], "buffBarBackgroundColor", "STYLE")
    page.controls.buffBarBgColorPicker:SetPoint("TOPLEFT", 0, NextY(50))

    local layoutHeader = UI.CreateHeader(barsScrollChild, L["Layout"])
    layoutHeader:SetPoint("TOPLEFT", 0, NextY(60))

    local growLabel = barsScrollChild:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    growLabel:SetText(L["Growth Direction:"])
    growLabel:SetPoint("TOPLEFT", 0, NextY(30))

    local ddGrowDirection = CreateFrame("DropdownButton", nil, barsScrollChild, "WowStyle1DropdownTemplate")
    ddGrowDirection:SetPoint("TOPLEFT", 0, NextY(20))
    ddGrowDirection:SetWidth(150)
    ddGrowDirection:SetDefaultText(CDM.db.buffBarGrowDirection or "DOWN")
    page.growDirectionDropdown = ddGrowDirection

    local growOptions = {
        { value = "DOWN", label = L["Down"] },
        { value = "UP", label = L["Up"] },
    }

    UI.SetupValueDropdown(
        ddGrowDirection,
        growOptions,
        function() return CDM.db.buffBarGrowDirection or "DOWN" end,
        function(value)
            CDM.db.buffBarGrowDirection = value
            ddGrowDirection:SetDefaultText(value)
            API:Refresh("LAYOUT")
        end
    )

    local iconPosLabel = barsScrollChild:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    iconPosLabel:SetText(L["Icon Position:"])
    iconPosLabel:SetPoint("TOPLEFT", 0, NextY(50))

    local ddIconPosition = CreateFrame("DropdownButton", nil, barsScrollChild, "WowStyle1DropdownTemplate")
    ddIconPosition:SetPoint("TOPLEFT", 0, NextY(20))
    ddIconPosition:SetWidth(150)
    ddIconPosition:SetDefaultText(CDM.db.buffBarIconPosition or "LEFT")
    page.iconPositionDropdown = ddIconPosition

    local iconOptions = {
        { value = "LEFT", label = L["Left"] },
        { value = "RIGHT", label = L["Right"] },
        { value = "HIDDEN", label = L["Hidden"] },
    }

    UI.SetupValueDropdown(
        ddIconPosition,
        iconOptions,
        function() return CDM.db.buffBarIconPosition or "LEFT" end,
        function(value)
            CDM.db.buffBarIconPosition = value
            ddIconPosition:SetDefaultText(value)
            API:Refresh("LAYOUT")
        end
    )

    page.controls.buffBarIconGapSlider = UI.CreateModernSlider(
        barsScrollChild,
        L["Icon-Bar Gap"],
        -1,
        20,
        CDM.db.buffBarIconGap or 2,
        function(v)
            CDM.db.buffBarIconGap = UI.RoundToInt(v)
            API:Refresh("LAYOUT")
        end
    )
    page.controls.buffBarIconGapSlider:SetPoint("TOPLEFT", 0, NextY(50))

    page.controls.buffBarDualModeCheck = UI.CreateModernCheckbox(
        barsScrollChild,
        L["Dual Bar Mode (2 bars per row)"],
        CDM.db.buffBarDualMode or false,
        function(checked)
            CDM.db.buffBarDualMode = checked
            API:Refresh("LAYOUT")
        end
    )
    page.controls.buffBarDualModeCheck:SetPoint("TOPLEFT", 0, NextY(60))

    local textHeader = UI.CreateHeader(barsScrollChild, L["Text"])
    textHeader:SetPoint("TOPLEFT", 0, NextY(50))

    page.controls.buffBarShowNameCheck = UI.CreateModernCheckbox(
        barsScrollChild,
        L["Show Buff Name"],
        CDM.db.buffBarShowName ~= false,
        function(checked)
            CDM.db.buffBarShowName = checked
            page.UpdateNameMaxCharsLayout()
            API:Refresh("LAYOUT")
        end
    )
    page.controls.buffBarShowNameCheck:SetPoint("TOPLEFT", 0, NextY(30))

    page.controls.buffBarNameMaxCharsSlider = UI.CreateModernSlider(
        barsScrollChild,
        L["Max Name Length (0 = Full)"],
        0,
        30,
        CDM.db.buffBarNameMaxChars or 0,
        function(v)
            CDM.db.buffBarNameMaxChars = UI.RoundToInt(v)
            API:Refresh("LAYOUT")
        end
    )
    page.controls.buffBarNameMaxCharsSlider:SetPoint("TOPLEFT", page.controls.buffBarShowNameCheck, "BOTTOMLEFT", 0, -10)

    page.controls.buffBarShowDurationCheck = UI.CreateModernCheckbox(
        barsScrollChild,
        L["Show Duration Text"],
        CDM.db.buffBarShowDuration ~= false,
        function(checked)
            CDM.db.buffBarShowDuration = checked
            API:Refresh("LAYOUT")
        end
    )

    function page.UpdateNameMaxCharsLayout()
        local shown = CDM.db.buffBarShowName ~= false
        page.controls.buffBarNameMaxCharsSlider:SetShown(shown)
        page.controls.buffBarShowDurationCheck:ClearAllPoints()
        if shown then
            page.controls.buffBarShowDurationCheck:SetPoint("TOPLEFT", page.controls.buffBarNameMaxCharsSlider, "BOTTOMLEFT", 0, -10)
        else
            page.controls.buffBarShowDurationCheck:SetPoint("TOPLEFT", page.controls.buffBarShowNameCheck, "BOTTOMLEFT", 0, -10)
        end
    end
    page.UpdateNameMaxCharsLayout()

    page.controls.buffBarShowApplicationsCheck = UI.CreateModernCheckbox(
        barsScrollChild,
        L["Show Stack Count"],
        CDM.db.buffBarShowApplications ~= false,
        function(checked)
            CDM.db.buffBarShowApplications = checked
            API:Refresh("LAYOUT")
        end
    )
    page.controls.buffBarShowApplicationsCheck:SetPoint("TOPLEFT", page.controls.buffBarShowDurationCheck, "BOTTOMLEFT", 0, -10)

    local notesHeader = UI.CreateHeader(barsScrollChild, L["Notes"])
    notesHeader:SetPoint("TOPLEFT", page.controls.buffBarShowApplicationsCheck, "BOTTOMLEFT", 0, -15)

    local borderNote = barsScrollChild:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    borderNote:SetText(L["Border settings: see Borders tab"])
    UI.SetTextMuted(borderNote)
    borderNote:SetPoint("TOPLEFT", notesHeader, "BOTTOMLEFT", 0, -10)

    local textNote = barsScrollChild:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    textNote:SetText(L["Text styling (font size, color, offsets): see Text tab"])
    UI.SetTextMuted(textNote)
    textNote:SetPoint("TOPLEFT", borderNote, "BOTTOMLEFT", 0, -5)

    local posNote = barsScrollChild:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    posNote:SetText(L["Position lock and X/Y controls: see Positions tab"])
    UI.SetTextMuted(posNote)
    posNote:SetPoint("TOPLEFT", textNote, "BOTTOMLEFT", 0, -5)
end

API:RegisterConfigTab("bars", L["Bars"], CreateBarsTab, 8)
