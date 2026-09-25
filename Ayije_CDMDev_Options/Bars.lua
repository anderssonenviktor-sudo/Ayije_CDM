local Runtime = _G["Ayije_CDMDev"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local L = Runtime.L
local CDM_C = CDM and CDM.CONST or {}
local UI = ns.ConfigUI
local Shared = ns.GroupEditorShared or {}
local M = CDM.BUFFBAR

local DestroyFrame = Shared.DestroyFrame

local PAGE_INSET = 16
local STRIP_TOP = -8
local COL_GAP = 20
local COL_W = 290

local function SaveAndRefresh()
    if CDM.InvalidateBuffBarEntries then CDM.InvalidateBuffBarEntries() end
    API:Refresh("BUFF_DATA", "STYLE", "LAYOUT")
end

local function CreateSlider(parent, label, minVal, maxVal, currentVal, onChange)
    return UI.CreateCompactSlider(parent, label, minVal, maxVal, currentVal, onChange)
end

StaticPopupDialogs["AYIJE_CDM_CONFIRM_DELETE_BARGROUP"] = {
    text = "",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local fn = StaticPopupDialogs["AYIJE_CDM_CONFIRM_DELETE_BARGROUP"]._pendingDelete
        if fn then fn() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local BAR_TYPE_OPTIONS = {
    { value = M.TYPE_TIMER, label = L["Timer Bar"] },
    { value = M.TYPE_STACK, label = L["Stack Bar"] },
}

local GROW_OPTIONS = {
    { value = "DOWN", label = L["Down"] },
    { value = "UP", label = L["Up"] },
}

local function CreateBarsTab(page)
    local si = GetSpecialization()
    local currentSpecID = si and GetSpecializationInfo(si) or nil

    -- Selection is either a group (by index) or a bar (by table identity --
    -- indices shift when bars move between groups).
    local selectedGroupIndex = nil
    local selectedBar = nil
    local selectedBarGroupIndex = nil
    local barView = "custom"
    local ShowOverview, RefreshViewText, ShowGroupActions
    local selectedProfile = CDM.db

    local RefreshAll
    local ShowBarSettings, OpenBarMenu
    local ShowGroupSettings
    local ShowAddBarPanel
    local function EnsureGroups() return M.EnsureGroups(currentSpecID) end
    local function GetGroups() return M.GetGroups(currentSpecID) end
    local function GetUngrouped() return M.GetUngrouped(currentSpecID) end

    local function RefreshLeftPanelIfNeeded()
        if RefreshAll then RefreshAll() end
    end

    -- Drag/drop moves a bar between tiles. The payload is the bar table itself,
    -- so identity survives the move and per-bar settings travel with it.
    local RegisterDropTarget, ClearDropTargets, StartDrag, EndDrag, CancelDrag
    do
        local dragState = { active = false, bar = nil, dragFrame = nil }
        local dropTargets = {}
        local dragFrameCache

        local function HideHighlights()
            for _, target in ipairs(dropTargets) do
                if target.frame.highlight then target.frame.highlight:Hide() end
            end
        end

        local function GetOrCreateDragFrame(bar)
            if not dragFrameCache then
                dragFrameCache = CreateFrame("Frame", nil, UIParent)
                dragFrameCache:SetSize(28, 28)
                dragFrameCache:SetFrameStrata("TOOLTIP")
                local icon = dragFrameCache:CreateTexture(nil, "ARTWORK")
                icon:SetAllPoints()
                dragFrameCache.icon = icon
                dragFrameCache:SetAlpha(0.8)
            end
            local tex = bar.spellID and C_Spell.GetSpellTexture(bar.spellID)
            if tex then
                dragFrameCache.icon:SetTexture(tex)
            else
                dragFrameCache.icon:SetColorTexture(0.3, 0.3, 0.3)
            end
            CDM_C.ApplyIconTexCoord(dragFrameCache.icon, CDM_C.GetEffectiveZoomAmount())
            return dragFrameCache
        end

        RegisterDropTarget = function(frame, groupIndex, index)
            dropTargets[#dropTargets + 1] = { frame = frame, groupIndex = groupIndex, index = index }
        end
        ClearDropTargets = function() table.wipe(dropTargets) end

        StartDrag = function(bar)
            if dragState.active then return end
            dragState.active = true
            dragState.bar = bar
            local df = GetOrCreateDragFrame(bar)
            dragState.dragFrame = df
            df:Show()
            local cachedScale = UIParent:GetEffectiveScale()
            df:SetScript("OnUpdate", function()
                local x, y = GetCursorPosition()
                df:ClearAllPoints()
                df:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / cachedScale, y / cachedScale)
                for _, target in ipairs(dropTargets) do
                    if target.frame.highlight then
                        target.frame.highlight:SetShown(target.frame:IsMouseOver())
                    end
                end
            end)
        end

        EndDrag = function()
            if not dragState.active then return end
            local bar = dragState.bar
            if dragState.dragFrame then
                dragState.dragFrame:SetScript("OnUpdate", nil)
                dragState.dragFrame:Hide()
                dragState.dragFrame = nil
            end

            local targetGroupIndex, hit, insertIndex = nil, false, nil
            for _, target in ipairs(dropTargets) do
                if target.frame:IsMouseOver() then
                    targetGroupIndex = target.groupIndex
                    hit = true
                    insertIndex = target.index
                    break
                end
            end
            HideHighlights()
            dragState.active = false
            dragState.bar = nil

            if not hit or not bar then return end
            local changed = M.MoveBar(bar, targetGroupIndex, currentSpecID)
            local group = targetGroupIndex and GetGroups()[targetGroupIndex]
            local list = group and group.bars or GetUngrouped()
            if insertIndex then
                for index, entry in ipairs(list) do
                    if entry == bar then
                        table.remove(list, index)
                        table.insert(list, math.min(insertIndex, #list + 1), bar)
                        changed = true
                        break
                    end
                end
            end
            if changed then
                if selectedBar == bar then selectedBarGroupIndex = targetGroupIndex end
                SaveAndRefresh()
                RefreshLeftPanelIfNeeded()
            end
        end

        CancelDrag = function()
            if not dragState.active then return end
            if dragState.dragFrame then
                dragState.dragFrame:SetScript("OnUpdate", nil)
                dragState.dragFrame:Hide()
                dragState.dragFrame = nil
            end
            HideHighlights()
            dragState.active = false
            dragState.bar = nil
        end
    end

    -- Toolbar

    local buttonRow = CreateFrame("Frame", nil, page)
    buttonRow:SetPoint("TOPLEFT", PAGE_INSET, STRIP_TOP)
    buttonRow:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAGE_INSET, STRIP_TOP)
    buttonRow:SetHeight(24)

    -- Only the selected view contributes icons to the strip.

    local stripFrame = CreateFrame("Frame", nil, page)
    stripFrame:SetPoint("TOPLEFT", buttonRow, "BOTTOMLEFT", 0, -8)
    stripFrame:SetPoint("TOPRIGHT", buttonRow, "BOTTOMRIGHT", 0, -8)
    stripFrame:SetHeight(44)

    local stripEmptyText = stripFrame:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
    stripEmptyText:SetPoint("TOPLEFT", 2, -6)
    stripEmptyText:Hide()

    -- Settings area fills everything under the strip.
    local settingsPanel = CreateFrame("Frame", nil, page)
    settingsPanel:SetPoint("TOPLEFT", stripFrame, "BOTTOMLEFT", 0, -10)
    settingsPanel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -PAGE_INSET, 16)

    local settingsPlaceholder = settingsPanel:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
    settingsPlaceholder:SetPoint("TOP", 0, -30)
    settingsPlaceholder:SetText(L["Select a group or bar above to edit its settings"])
    UI.SetTextMuted(settingsPlaceholder)

    local panelManager = Shared.CreateRightPanelManager(settingsPanel, settingsPlaceholder, DestroyFrame)
    local RegisterPanelDropdown = panelManager.RegisterDropdown
    local preview = ns.CreateBuffBarPreview(page)
    preview:SetPoint("TOPLEFT", buttonRow, "BOTTOMLEFT", 0, -14)
    local function ResetPreview()
        preview:Hide()
        settingsPanel:ClearAllPoints()
        settingsPanel:SetPoint("TOPLEFT", buttonRow, "BOTTOMLEFT", 0, -20)
        settingsPanel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -12, 16)
    end
    local function CreatePanelContent(height)
        ResetPreview()
        return panelManager.CreateScrollContent(height)
    end
    local function ClearPanel()
        ResetPreview()
        panelManager.Clear()
    end

    local function MakeDropdown(parent)
        return RegisterPanelDropdown(UI.CreateCompactDropdown(parent))
    end

    local function NewColumns(rc)
        local cols = {
            { x = 0, y = 0 },
            { x = COL_W + COL_GAP, y = 0 },
        }
        local sections = {}

        return {
            -- Declare a section: `height` is its approximate laid-out height,
            -- `build(col)` emits the widgets once its column is decided.
            Section = function(height, build)
                sections[#sections + 1] = { height = height, build = build }
            end,
            -- Lay every declared section out, keeping the columns even.
            Flush = function()
                local order = {}
                for i = 1, #sections do order[i] = i end
                for _, idx in ipairs(order) do
                    local s = sections[idx]
                    local col = (cols[1].y >= cols[2].y) and cols[1] or cols[2]
                    s.build(col)
                    col.y = col.y - 12   -- breathing room between sections
                end
                wipe(sections)
            end,
            Get = function(i) return cols[i] end,
            -- Start both columns below a full-width heading.
            SetTop = function(y)
                cols[1].y, cols[2].y = y, y
            end,
            MaxDepth = function()
                return math.max(-cols[1].y, -cols[2].y)
            end,
            Header = function(col, text)
                local h = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
                h:SetPoint("TOPLEFT", col.x, col.y)
                h:SetText(text)
                h:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
                col.y = col.y - 30
            end,
            Label = function(col, text, muted, small)
                local fs = rc:CreateFontString(nil, "OVERLAY",
                    small and "AyijeCDM_Font12" or "AyijeCDM_Font14")
                fs:SetPoint("TOPLEFT", col.x, col.y)
                fs:SetWidth(COL_W)
                fs:SetJustifyH("LEFT")
                fs:SetText(text)
                if muted then UI.SetTextMuted(fs) end
                col.y = col.y - math.max(small and 20 or 22, fs:GetStringHeight() + 6)
                return fs
            end,
            Slider = function(col, label, minV, maxV, cur, onChange)
                local s = CreateSlider(rc, label, minV, maxV, cur, onChange)
                s:SetPoint("TOPLEFT", col.x, col.y)
                col.y = col.y - 36
                return s
            end,
            Check = function(col, label, checked, onChange)
                local c = UI.CreateCompactCheckbox(rc, label, checked, onChange)
                c:SetPoint("TOPLEFT", col.x, col.y)
                col.y = col.y - 32
                return c
            end,
            Dropdown = function(col, options, getV, setV, defaultText, width)
                local dd = MakeDropdown(rc)
                dd:SetWidth(width or 170)
                dd:SetPoint("TOPLEFT", col.x, col.y)
                dd:SetDefaultText(defaultText)
                UI.SetupValueDropdown(dd, options, getV, function(val)
                    setV(val)
                    dd:SetDefaultText(UI.GetOptionLabel(options, val, val))
                end)
                col.y = col.y - 36
                return dd
            end,
            PositionDropdown = function(col, getV, setV, defaultText, width)
                local dd = MakeDropdown(rc)
                dd:SetWidth(width or 170)
                dd:SetPoint("TOPLEFT", col.x, col.y)
                dd:SetDefaultText(defaultText)
                UI.SetupPositionDropdown(dd, getV, setV)
                col.y = col.y - 36
                return dd
            end,
            ColorRow = function(col, label, initial, onChange)
                local fs = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
                fs:SetPoint("TOPLEFT", col.x, col.y)
                fs:SetText(label)
                local picker = UI.CreateSimpleColorPicker(rc, initial, onChange, true)
                picker:SetPoint("LEFT", fs, "RIGHT", 8, 0)
                col.y = col.y - 28
                return picker
            end,
            Gap = function(col, amount)
                col.y = col.y - (amount or 10)
            end,
        }
    end

    ShowGroupSettings = function(groupIndex)
        local gd = GetGroups()[groupIndex]
        if not gd then ClearPanel(); return end
        selectedBar, selectedBarGroupIndex, selectedGroupIndex = nil, nil, groupIndex
        if ns.CloseSpellMenu then ns.CloseSpellMenu() end
        if RefreshViewText then RefreshViewText() end
        local _, rc = CreatePanelContent(240)
        local profile = CDM.db
        local function Valid()
            return profile == CDM.db and GetGroups()[groupIndex] == gd and rc:IsShown()
        end
        local function Header(column, text)
            local label = UI.CreateSubHeader(rc, L[text])
            label:SetPoint("TOPLEFT", (column - 1) * 310, 0)
        end
        local function Row(column, index, text)
            local row = CreateFrame("Frame", nil, rc)
            row:SetSize(290, 32)
            row:SetPoint("TOPLEFT", (column - 1) * 310, -24 - index * 36)
            if text then
                local label = row:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
                label:SetPoint("LEFT")
                label:SetWidth(132)
                label:SetJustifyH("LEFT")
                label:SetText(L[text])
            end
            return row
        end
        local function Dropdown(column, index, label, options, get, set)
            local row = Row(column, index, label)
            local dropdown = MakeDropdown(row)
            dropdown:SetSize(150, 26)
            dropdown:SetPoint("LEFT", 140, 0)
            UI.SetupValueDropdown(dropdown, options, get, function(value)
                if Valid() then set(value) end
            end)
            return dropdown
        end
        local function Slider(column, index, label, key, low, high)
            local row = Row(column, index)
            local slider = CreateSlider(row, L[label], low, high, gd[key] or 0, function(value)
                if not Valid() then return end
                gd[key] = UI.RoundToInt(value)
                SaveAndRefresh()
            end)
            slider:SetPoint("LEFT")
            slider.Label:SetWidth(132)
            slider.Slider:ClearAllPoints()
            slider.Slider:SetPoint("LEFT", 140, 0)
            slider.Slider:SetWidth(108)
            slider:UpdateUIValue(gd[key] or 0)
            return slider
        end
        Header(1, "Group Settings")
        Header(2, "Anchor")
        local nameRow = Row(1, 0, "Group Name")
        local name = UI.CreateCustomEditBox(nameRow)
        name:SetSize(150, 26)
        name:SetPoint("LEFT", 140, 0)
        name:SetText(gd.name or "")
        name:SetScript("OnEditFocusLost", function(self)
            if not Valid() then return end
            local value = self:GetText():match("^%s*(.-)%s*$")
            if value ~= "" then
                gd.name = value
                SaveAndRefresh()
                RefreshViewText()
            else
                self:SetText(gd.name or "")
            end
        end)
        Dropdown(1, 1, "Grow Direction", GROW_OPTIONS,
            function() return gd.grow or "DOWN" end,
            function(value) gd.grow = value; SaveAndRefresh() end)
        Slider(1, 2, "Spacing", "spacing", -1, 50)
        local actions = UI.CreateTextButton(Row(1, 3))
        actions:SetSize(150, 26)
        actions:SetPoint("LEFT", 140, 0)
        actions:SetText(L["Group Actions"])
        actions:SetScript("OnClick", function(self) ShowGroupActions(self, groupIndex, name) end)

        local anchorTargets = {
            { label = L["Screen"], value = "screen" },
            { label = L["Player Frame"], value = "playerFrame" },
            { label = L["Essential Viewer"], value = "essential" },
            { label = L["Buff Viewer"], value = "buff" },
            { label = L["Buff Bar Viewer"], value = "buffBar" },
        }
        Dropdown(2, 0, "Anchor To", anchorTargets,
            function() return gd.anchorTarget or "screen" end,
            function(value)
                if value == (gd.anchorTarget or "screen") then return end
                gd.anchorTarget = value
                gd.anchorPoint = gd.anchorPoint or "CENTER"
                gd.anchorRelativeTo = gd.anchorRelativeTo or "CENTER"
                gd.offsetX, gd.offsetY = 0, 0
                SaveAndRefresh()
                ShowGroupSettings(groupIndex)
            end)
        local offsetRow = 1
        if (gd.anchorTarget or "screen") ~= "screen" then
            local positions = {}
            for _, point in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do
                positions[#positions + 1] = { label = L[point], value = point }
            end
            Dropdown(2, 1, "Anchor Point", positions,
                function() return gd.anchorPoint or "CENTER" end,
                function(value) gd.anchorPoint = value; SaveAndRefresh() end)
            Dropdown(2, 2, "Relative Point", positions,
                function() return gd.anchorRelativeTo or "CENTER" end,
                function(value) gd.anchorRelativeTo = value; SaveAndRefresh() end)
            offsetRow = 3
        end
        local xSlider = Slider(2, offsetRow, "X Offset", "offsetX", -840, 840)
        local ySlider = Slider(2, offsetRow + 1, "Y Offset", "offsetY", -470, 470)
        rc:SetHeight(math.max(4, offsetRow + 2) * 36 + 40)
        if ns.RegisterAnchorPositionUpdater then
            ns.RegisterAnchorPositionUpdater("buff_bar_group_" .. groupIndex, function(x, y)
                if not Valid() or selectedBar or selectedGroupIndex ~= groupIndex then return end
                xSlider:UpdateUIValue(x)
                ySlider:UpdateUIValue(y)
            end)
        end
    end


    ShowBarSettings = function(bar, groupIndex, scrollOffset)
        if not bar then ShowOverview(); return end
        selectedBar, selectedBarGroupIndex, selectedGroupIndex = bar, groupIndex, groupIndex
        barView = groupIndex and "group" or "custom"
        if ns.CloseSpellMenu then ns.CloseSpellMenu() end
        M.NormalizeBar(bar)
        local scroll, rc = CreatePanelContent(600)
        preview:SetBar(bar)
        preview:Show()
        settingsPanel:ClearAllPoints()
        settingsPanel:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -12)
        settingsPanel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -12, 16)
        local function SavePreview()
            SaveAndRefresh()
            preview:Refresh()
        end
        local actions = UI.CreateTextButton(rc)
        actions:SetSize(130, 26)
        actions:SetPoint("TOPLEFT", 470, 0)
        actions:SetText(L["Bar Actions"])
        actions:SetScript("OnClick", function(self) OpenBarMenu(bar, groupIndex, self) end)
        local typeLabel = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
        typeLabel:SetPoint("TOPLEFT", 0, -6)
        typeLabel:SetText(L["Bar Type"])
        local typeDropdown = MakeDropdown(rc)
        typeDropdown:SetSize(150, 26)
        typeDropdown:SetPoint("TOPLEFT", 140, 0)
        UI.SetupValueDropdown(typeDropdown, BAR_TYPE_OPTIONS, function() return bar.barType end, function(value)
            bar.barType = value
            M.NormalizeBar(bar)
            SaveAndRefresh()
            ShowBarSettings(bar, groupIndex)
        end)
        local body = CreateFrame("Frame", nil, rc)
        body:SetPoint("TOPLEFT", 0, -42)
        body:SetWidth(610)
        ns.RenderBuffBarAppearance(body, SavePreview, bar, function()
            ShowBarSettings(bar, groupIndex, scroll:GetVerticalScroll())
        end)
        rc:SetHeight(body:GetHeight() + 58)
        if scrollOffset then
            scroll:SetVerticalScroll(math.min(scrollOffset, math.max(0, rc:GetHeight() - scroll:GetHeight())))
        end
        if RefreshViewText then RefreshViewText() end
    end

    ShowAddBarPanel = function(targetGroupIndex)
        if ns.CloseSpellMenu then ns.CloseSpellMenu() end
        local _, rc = CreatePanelContent(400)
        local yOff = 0

        local headerText = L["Add Bar"]
        if targetGroupIndex then
            local groups = GetGroups()
            local gd = groups and groups[targetGroupIndex]
            headerText = (L["Add Bar to:"]) .. " " .. (gd and gd.name or "Group")
        end

        local header = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font18")
        header:SetPoint("TOPLEFT", 0, yOff)
        header:SetText(headerText)
        header:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)

        local backBtn = UI.CreateTextButton(rc)
        backBtn:SetSize(70, 22)
        backBtn:SetPoint("TOPLEFT", COL_W + COL_GAP, yOff)
        backBtn:SetText(L["Back"])
        backBtn:SetScript("OnClick", function()
            if targetGroupIndex then
                ShowGroupSettings(targetGroupIndex)
            else
                ShowOverview()
            end
        end)
        yOff = yOff - 32

        local typeLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
        typeLabel:SetText(L["Bar Type"])
        typeLabel:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 22

        local chosenType = M.TYPE_TIMER
        local typeDropdown = MakeDropdown(rc)
        typeDropdown:SetWidth(170)
        typeDropdown:SetPoint("TOPLEFT", 0, yOff)
        typeDropdown:SetDefaultText(L["Timer Bar"])
        UI.SetupValueDropdown(typeDropdown, BAR_TYPE_OPTIONS,
            function() return chosenType end,
            function(val)
                chosenType = val
                typeDropdown:SetDefaultText(UI.GetOptionLabel(BAR_TYPE_OPTIONS, val, val))
            end)
        yOff = yOff - 40

        local listLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
        listLabel:SetText(L["Tracked buffs"])
        listLabel:SetPoint("TOPLEFT", 0, yOff)
        UI.SetTextWhite(listLabel)
        yOff = yOff - 26

        local tracked = CDM.GetBuffBarTrackedSpells and CDM.GetBuffBarTrackedSpells() or {}
        if #tracked == 0 then
            local msg = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
            msg:SetPoint("TOPLEFT", 0, yOff)
            msg:SetText(L["(No tracked buffs found)"])
            UI.SetTextMuted(msg)
            yOff = yOff - 30
        else
            -- Two columns of rows so a long tracked list stays on screen.
            local startY = yOff
            local perCol = math.ceil(#tracked / 2)
            for i, entry in ipairs(tracked) do
                local colIndex = (i <= perCol) and 0 or 1
                local rowIndex = (i <= perCol) and (i - 1) or (i - perCol - 1)

                local added = M.IsSpellConfigured(entry.spellID, currentSpecID)

                local row = CreateFrame("Button", nil, rc)
                row:SetSize(COL_W, 28)
                row:SetPoint("TOPLEFT", colIndex * (COL_W + COL_GAP), startY - rowIndex * 28)

                local rowIcon = row:CreateTexture(nil, "ARTWORK")
                rowIcon:SetSize(22, 22)
                rowIcon:SetPoint("LEFT", 0, 0)
                if entry.icon then rowIcon:SetTexture(entry.icon) end
                CDM_C.ApplyIconTexCoord(rowIcon, CDM_C.GetEffectiveZoomAmount())

                local label = row:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
                label:SetPoint("LEFT", rowIcon, "RIGHT", 6, 0)
                label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                label:SetJustifyH("LEFT")
                if added then
                    label:SetText(entry.name .. " |cff888888(" .. (L["added"]) .. ")|r")
                    UI.SetTextFaint(label)
                else
                    label:SetText(entry.name)
                end

                local sid, sname = entry.spellID, entry.name
                row:SetScript("OnClick", function()
                    local destination
                    if targetGroupIndex then
                        local groups = EnsureGroups()
                        local gd = groups and groups[targetGroupIndex]
                        if not gd then return end
                        gd.bars = gd.bars or {}
                        destination = gd.bars
                    else
                        destination = M.EnsureUngrouped(currentSpecID)
                    end
                    if not destination then return end

                    local newBar = M.CreateBar(sid, sname, chosenType)
                    destination[#destination + 1] = newBar
                    selectedBar = newBar
                    selectedBarGroupIndex = targetGroupIndex
                    selectedGroupIndex = targetGroupIndex
                    barView = targetGroupIndex and "group" or "custom"
                    SaveAndRefresh()
                    RefreshLeftPanelIfNeeded()
                    ShowBarSettings(newBar, targetGroupIndex)
                end)
            end
            yOff = startY - perCol * 28
        end

        rc:SetHeight(math.abs(yOff) + 24)
    end

    local viewDropdown = UI.CreateCompactDropdown(buttonRow, {
        viewSelector = true, smallText = true, menuMaxHeight = 264, menuMaxWidth = 320,
    })
    viewDropdown:SetSize(260, 26)
    viewDropdown:SetPoint("TOPLEFT")
    local hint = stripFrame:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
    hint:SetPoint("BOTTOMLEFT", 0, -20)
    hint:SetText(L["Right-click a bar for individual settings"])
    UI.SetTextMuted(hint)
    settingsPanel:ClearAllPoints()
    settingsPanel:SetPoint("TOPLEFT", buttonRow, "BOTTOMLEFT", 0, -20)
    settingsPanel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -12, 16)
    local surface = UI.CreateSpellStripSurface(stripFrame)
    surface:SetPoint("TOPLEFT")
    local icons = {}
    local add = CreateFrame("Button", nil, stripFrame)
    add:SetSize(24, 24)
    UI.StyleSpellStripAddButton(add)
    add:SetScript("OnClick", function() ShowAddBarPanel(selectedGroupIndex) end)

    RefreshViewText = function()
        local group = selectedGroupIndex and GetGroups()[selectedGroupIndex]
        local text = group and group.name or L["Select a bar or group"]
        if selectedBar then
            text = selectedBar.name or C_Spell.GetSpellName(selectedBar.spellID) or L["Unknown"]
            if group then text = text .. " (" .. group.name .. ")" end
        end
        viewDropdown:OverrideText(text)
    end
    ShowOverview = function()
        if ns.CloseSpellMenu then ns.CloseSpellMenu() end
        local group = selectedGroupIndex and GetGroups()[selectedGroupIndex]
        local list = group and group.bars or GetUngrouped()
        if selectedBar then
            for _, entry in ipairs(list or {}) do
                if entry == selectedBar then ShowBarSettings(entry, selectedGroupIndex); return end
            end
        end
        selectedBar, selectedBarGroupIndex = nil, nil
        if group then
            ShowGroupSettings(selectedGroupIndex)
        elseif GetUngrouped()[1] then
            selectedGroupIndex = nil
            ShowBarSettings(GetUngrouped()[1], nil)
        elseif GetGroups()[1] then
            selectedGroupIndex = 1
            ShowGroupSettings(1)
        else
            selectedGroupIndex = nil
            ClearPanel()
            settingsPlaceholder:SetText(L["Select Add Independent Bar or New Group from the dropdown to get started."])
        end
        RefreshViewText()
    end
    ShowGroupActions = function(owner, groupIndex, name)
        local groups = GetGroups()
        local group = groups[groupIndex]
        if not group then return end
        local profile, specID = CDM.db, currentSpecID
        local function Valid() return CDM.db == profile and currentSpecID == specID and GetGroups()[groupIndex] == group end
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateButton(L["Rename"], function() name:SetFocus(); name:HighlightText() end)
            root:CreateButton(L["Duplicate"], function()
                if not Valid() then return end
                local clone = M.CreateGroup(groups, Shared.GetUniqueGroupName(groups, group.name or L["Group"]))
                for _, key in ipairs({ "grow", "spacing", "anchorTarget", "anchorPoint", "anchorRelativeTo", "offsetX", "offsetY" }) do clone[key] = group[key] end
                for _, bar in ipairs(group.bars or {}) do clone.bars[#clone.bars + 1] = M.CloneBar(bar) end
                groups[#groups + 1] = clone
                selectedGroupIndex = #groups
                selectedBar, selectedBarGroupIndex = nil, nil
                SaveAndRefresh(); ShowOverview(); RefreshAll()
            end)
            root:CreateButton(L["Delete Group"], function()
                local function Delete()
                    if not Valid() then return end
                    local list = M.EnsureUngrouped(currentSpecID)
                    if not list then return end
                    for _, bar in ipairs(group.bars or {}) do list[#list + 1] = bar end
                    table.remove(groups, groupIndex)
                    selectedGroupIndex, barView = nil, "custom"
                    SaveAndRefresh(); ShowOverview(); RefreshAll()
                end
                if #(group.bars or {}) > 0 then
                    local dialog = StaticPopupDialogs["AYIJE_CDM_CONFIRM_DELETE_BARGROUP"]
                    dialog.text = string.format(L["Delete group? Its %d bar(s) return to ungrouped."], #group.bars)
                    dialog._pendingDelete = Delete
                    StaticPopup_Show("AYIJE_CDM_CONFIRM_DELETE_BARGROUP")
                else Delete() end
            end)
        end)
    end
    local function CreateGroup()
        local groups = EnsureGroups()
        if not groups then return end
        local index = #groups + 1
        groups[index] = M.CreateGroup(groups, Shared.GetUniqueGroupName(groups, "BAR" .. index))
        selectedGroupIndex, barView = index, "group"
        selectedBar, selectedBarGroupIndex = nil, nil
        SaveAndRefresh()
        ShowOverview()
        RefreshAll()
    end
    viewDropdown:SetupMenu(function(_, root)
        local profile, specID = CDM.db, currentSpecID
        local function Valid() return CDM.db == profile and currentSpecID == specID and not InCombatLockdown() end
        local function BarEntry(bar, groupIndex)
            local name = bar.name or C_Spell.GetSpellName(bar.spellID) or L["Unknown"]
            local icon = C_Spell.GetSpellTexture(bar.spellID) or 134400
            local entry = root:CreateRadio(string.format("|T%s:18:18|t %s", tostring(icon), name),
                function() return selectedBar == bar end,
                function() if Valid() then ShowBarSettings(bar, groupIndex) end end)
            entry.actionWidth = 24
            entry.actionText = "?"
            entry.action = function()
                if not Valid() then return end
                M.RemoveBar(bar, currentSpecID)
                if selectedBar == bar then selectedBar = nil end
                SaveAndRefresh(); ShowOverview(); RefreshAll()
            end
        end
        for index, group in ipairs(GetGroups()) do
            root:CreateSection(group.name or (L["Group"] .. " " .. index), L["Edit Group"], function()
                if not Valid() then return end
                selectedBar, selectedBarGroupIndex = nil, nil
                selectedGroupIndex, barView = index, "group"
                ShowOverview()
            end)
            for _, bar in ipairs(group.bars or {}) do BarEntry(bar, index) end
            root:CreateButton("+ " .. L["Add Bar to Group"], function()
                if not Valid() then return end
                selectedGroupIndex, selectedBar = index, nil
                ShowAddBarPanel(index)
            end)
            root:CreateDivider()
        end
        root:CreateSection(L["Independent Bars"])
        for _, bar in ipairs(GetUngrouped()) do BarEntry(bar, nil) end
        root:CreateDivider()
        root:CreateButton("+ " .. L["New Group"], function() if Valid() then CreateGroup() end end)
        root:CreateButton("+ " .. L["Add Independent Bar"], function()
            if not Valid() then return end
            selectedGroupIndex, selectedBar = nil, nil
            ShowAddBarPanel(nil)
        end)
    end)

    OpenBarMenu = function(bar, groupIndex, owner)
        local profile, specID = CDM.db, currentSpecID
        local function Valid()
            if profile ~= CDM.db or specID ~= currentSpecID or not page:IsShown() then return false end
            local group = groupIndex and GetGroups()[groupIndex]
            local list = groupIndex and (group and group.bars or {}) or GetUngrouped()
            for _, entry in ipairs(list) do if entry == bar then return true end end
            return false
        end
        M.NormalizeBar(bar)
        local function Action(label, callback) return { label = L[label], kind = "action", set = callback } end
        local function Changed() SaveAndRefresh(); ShowOverview(); RefreshAll() end
        local function Reorder(delta)
            local group = groupIndex and GetGroups()[groupIndex]
            local list = group and group.bars or GetUngrouped()
            for index, entry in ipairs(list) do
                if entry == bar then
                    local target = math.max(1, math.min(#list, index + delta))
                    list[index], list[target] = list[target], list[index]
                    Changed()
                    return
                end
            end
        end
        local fields = {
            { label = L["Move To"], kind = "choice", options = function()
                local options = { { value = 0, label = L["Independent Bars"] } }
                for index, group in ipairs(GetGroups()) do options[#options + 1] = { value = index, label = group.name } end
                return options
            end, get = function() return groupIndex or 0 end,
                set = function(value)
                    if ns.CloseSpellMenu then ns.CloseSpellMenu() end
                    local destination = value ~= 0 and value or nil
                    M.MoveBar(bar, destination, currentSpecID)
                    selectedBar, selectedBarGroupIndex, selectedGroupIndex = bar, destination, destination
                    Changed()
                end },
            Action("Move Up", function() Reorder(-1) end),
            Action("Move Down", function() Reorder(1) end),
            Action("Duplicate", function()
                local group = groupIndex and GetGroups()[groupIndex]
                local list = group and group.bars or M.EnsureUngrouped(currentSpecID)
                if list then
                    local copy = M.CloneBar(bar)
                    list[#list + 1] = copy
                    selectedBar, selectedBarGroupIndex, selectedGroupIndex = copy, groupIndex, groupIndex
                    Changed()
                end
            end),
            Action("Remove Bar", function() M.RemoveBar(bar, currentSpecID); Changed() end),
        }
        ns.ShowFieldMenu(owner, L["Bar Actions"], fields, Valid)
    end

    stripFrame:Hide()
    RefreshAll = function()
        RefreshViewText()
        if preview:IsShown() then preview:Refresh() end
    end
    ShowOverview()
    local QueueRefresh = Shared.CreateQueueLeftPanelRefresh(page, function() return RefreshAll end)
    local RegisterViewerCallbacks, UnregisterViewerCallbacks = Shared.CreateViewerSettingsCallbacks(QueueRefresh)
    local previousWidth = 0
    stripFrame:HookScript("OnSizeChanged", function(_, width)
        if math.abs(width - previousWidth) < 1 then return end
        previousWidth = width
        if page:IsShown() then QueueRefresh() end
    end)
    API:RegisterRefreshCallback("bars-rework-refresh", function()
        if not page:IsShown() then return end
        local spec = GetSpecialization()
        local specID = spec and GetSpecializationInfo(spec) or nil
        if CDM.db ~= selectedProfile or specID ~= currentSpecID then
            selectedProfile, currentSpecID = CDM.db, specID
            selectedGroupIndex, selectedBar, selectedBarGroupIndex = nil, nil, nil
            barView = "native"
            ShowOverview()
        end
        QueueRefresh()
    end, 31, { "BUFF_DATA", "STYLE", "LAYOUT" })

    page:SetScript("OnMouseUp", function() EndDrag() end)

    page:HookScript("OnHide", function()
        UnregisterViewerCallbacks()
        panelManager.CloseDropdownMenus()
        UI.CloseAllDropdownMenus()
        if ns.CloseSpellMenu then ns.CloseSpellMenu() end
        CancelDrag()
    end)

    page:HookScript("OnShow", function()
        RegisterViewerCallbacks()
        local spec = GetSpecialization()
        local newSpecID = spec and GetSpecializationInfo(spec) or nil
        if newSpecID ~= currentSpecID or CDM.db ~= selectedProfile then
            selectedProfile = CDM.db
            currentSpecID = newSpecID
            selectedGroupIndex = nil
            selectedBar = nil
            selectedBarGroupIndex = nil
            barView = "native"
            ClearPanel()
        end
        RefreshAll()
        if selectedBar then
            ShowBarSettings(selectedBar, selectedBarGroupIndex)
        else
            ShowOverview()
        end
    end)
end

API:RegisterConfigTab("bars", L["Bars"], CreateBarsTab, 8)
