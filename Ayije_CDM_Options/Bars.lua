local Runtime = _G["Ayije_CDM"]
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

-- Layout constants.
--
-- The page is ~675px wide (920 frame - 180 sidebar - insets), which fits two
-- settings columns rather than the three-panel arrangement Buffs/Cooldowns
-- use. That layout assumes dozens of icons; bar setups are typically 1-2 bars
-- in a group, so the whole bottom half is given over to the selected item's
-- settings instead.
local PAGE_INSET = 12
local STRIP_TOP = -12
-- Wide enough for a full row of icons plus padding:
-- TILE_PAD + 4*TILE_ICON + 3*TILE_ICON_GAP + TILE_PAD = 202
local TILE_W = 202
local TILE_GAP = 10
local TILE_HEADER_H = 24
local TILE_PAD = 8
local TILE_ICON = 42
local TILE_ICON_GAP = 6
local TILE_ICONS_PER_ROW = 4
local TILE_MIN_H = TILE_HEADER_H + TILE_PAD + TILE_ICON + TILE_PAD

-- Two columns must fit a tab page minus the scroll bar (~635px usable).
local COL_GAP = 20
local COL_W = 300
local SLIDER_LABEL_W = 108
local SLIDER_W = 180

local function SaveAndRefresh()
    if CDM.InvalidateBuffBarEntries then CDM.InvalidateBuffBarEntries() end
    API:Refresh("BUFF_DATA", "STYLE", "LAYOUT")
end

local function CreateSlider(parent, label, minVal, maxVal, currentVal, onChange)
    return UI.CreateModernSlider(parent, label, minVal, maxVal, currentVal,
        onChange, SLIDER_LABEL_W, SLIDER_W)
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

local ICON_POS_OPTIONS = {
    { value = "LEFT", label = L["Left"] },
    { value = "RIGHT", label = L["Right"] },
    { value = "HIDDEN", label = L["Hidden"] },
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
    -- Which sub-tab the bar settings panel is showing. Persisted across the
    -- rebuilds that a setting change triggers, so toggling a checkbox does not
    -- bounce the user back to the first tab.
    local barSettingsTab = "appearance"

    local RefreshAll
    local ShowBarSettings
    local ShowGroupSettings
    local ShowAddBarPanel
    local renameActiveGroupIndex = nil
    local renameActiveEditBox = nil

    -- Writes a pending rename back and tears the box down. Safe to call at any
    -- time, including from inside the box's own handlers -- it clears the
    -- state before touching the widget, so re-entry is a no-op.
    local function CommitPendingRename(apply)
        local box, index = renameActiveEditBox, renameActiveGroupIndex
        -- No box yet means a rename was just REQUESTED and BuildStrip has not
        -- created its widget: leave renameActiveGroupIndex alone so the next
        -- pass can open it.
        if not box then return end
        renameActiveEditBox = nil
        renameActiveGroupIndex = nil

        box:SetScript("OnEditFocusLost", nil)
        box:SetScript("OnEnterPressed", nil)
        box:SetScript("OnEscapePressed", nil)
        box:ClearFocus()
        box:Hide()

        if apply == false or not index then return end
        local groups = M.GetGroups(currentSpecID)
        local gd = groups and groups[index]
        local newName = box:GetText()
        if gd and newName and newName ~= "" then
            gd.name = newName
        end
    end

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

        RegisterDropTarget = function(frame, groupIndex)
            dropTargets[#dropTargets + 1] = { frame = frame, groupIndex = groupIndex }
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

            local targetGroupIndex, hit = nil, false
            for _, target in ipairs(dropTargets) do
                if target.frame:IsMouseOver() then
                    targetGroupIndex = target.groupIndex
                    hit = true
                    break
                end
            end
            HideHighlights()
            dragState.active = false
            dragState.bar = nil

            if not hit or not bar then return end
            if M.MoveBar(bar, targetGroupIndex, currentSpecID) then
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

    -- Group strip: one tile per group, plus an Ungrouped tile that only appears
    -- when bars actually live outside a group. Selecting a tile edits it below.

    local stripFrame = CreateFrame("Frame", nil, page)
    stripFrame:SetPoint("TOPLEFT", buttonRow, "BOTTOMLEFT", 0, -8)
    stripFrame:SetPoint("TOPRIGHT", buttonRow, "BOTTOMRIGHT", 0, -8)
    stripFrame:SetHeight(TILE_MIN_H)

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
    local CreatePanelContent = panelManager.CreateScrollContent
    local ClearPanel = panelManager.Clear

    local function MakeDropdown(parent)
        return RegisterPanelDropdown(
            CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate"))
    end

    -- Column helper.
    --
    -- Sections are DECLARED first (each a closure plus a measured height) and
    -- only laid out once every section is known. A greedy "append to whichever
    -- column is shorter" pass cannot recover from a tall section landing first,
    -- which is what left one column nearly empty; measuring up front lets the
    -- packer put the big sections where they balance.
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
                -- Longest-first into the currently shorter column: a simple
                -- greedy bin-pack, which is near-optimal for two bins and a
                -- handful of items, while preserving a sensible reading order
                -- among equal-height sections.
                local order = {}
                for i = 1, #sections do order[i] = i end
                table.sort(order, function(a, b)
                    local ha, hb = sections[a].height, sections[b].height
                    if ha ~= hb then return ha > hb end
                    return a < b
                end)

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
                local h = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font18")
                h:SetPoint("TOPLEFT", col.x, col.y)
                h:SetText(text)
                h:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
                col.y = col.y - 30
            end,
            Label = function(col, text, muted, small)
                local fs = rc:CreateFontString(nil, "OVERLAY",
                    small and "AyijeCDM_Font12" or "AyijeCDM_Font14")
                fs:SetPoint("TOPLEFT", col.x, col.y)
                fs:SetText(text)
                if muted then UI.SetTextMuted(fs) end
                col.y = col.y - (small and 20 or 22)
                return fs
            end,
            Slider = function(col, label, minV, maxV, cur, onChange)
                local s = CreateSlider(rc, label, minV, maxV, cur, onChange)
                s:SetPoint("TOPLEFT", col.x, col.y)
                col.y = col.y - 46
                return s
            end,
            Check = function(col, label, checked, onChange)
                local c = UI.CreateModernCheckbox(rc, label, checked, onChange)
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

    -- Group settings: placement only. Bars carry their own visuals.
    ShowGroupSettings = function(groupIndex)
        local groups = GetGroups()
        local gd = groups and groups[groupIndex]
        if not gd then ClearPanel(); return end

        local _, rc = CreatePanelContent(400)
        local C = NewColumns(rc)

        local left = C.Get(1)
        C.Header(left, (gd.name or ("Group " .. groupIndex)) .. "  " .. L["(Group)"])
        C.Label(left, L["Groups control placement. Each bar keeps its own appearance."], true, true)
        C.Gap(left, 6)

        C.Label(left, L["Grow Direction"])
        C.Dropdown(left, GROW_OPTIONS,
            function() return gd.grow or "DOWN" end,
            function(val) gd.grow = val; SaveAndRefresh() end,
            UI.GetOptionLabel(GROW_OPTIONS, gd.grow or "DOWN", L["Down"]))

        C.Slider(left, L["Spacing"], -1, 50, gd.spacing or 1, function(v)
            gd.spacing = UI.RoundToInt(v); SaveAndRefresh()
        end)

        -- Anchor lives in the right column so both stay short.
        local right = C.Get(2)
        C.Header(right, L["Anchor"])

        local anchorTargets = {
            { label = L["Screen"], value = "screen" },
            { label = L["Player Frame"], value = "playerFrame" },
            { label = L["Essential Viewer"], value = "essential" },
            { label = L["Buff Viewer"], value = "buff" },
            { label = L["Buff Bar Viewer"], value = "buffBar" },
        }

        C.Label(right, L["Anchor To"])
        local anchorLabel, anchorDropdown, relLabel, relDropdown
        local xSlider, ySlider
        local UpdateAnchorVisibility

        C.Dropdown(right, anchorTargets,
            function() return gd.anchorTarget or "screen" end,
            function(val)
                local prev = gd.anchorTarget or "screen"
                gd.anchorTarget = val
                gd.anchorPoint = gd.anchorPoint or "CENTER"
                gd.anchorRelativeTo = gd.anchorRelativeTo or "CENTER"
                if val ~= prev then
                    gd.offsetX, gd.offsetY = 0, 0
                    xSlider:UpdateUIValue(0)
                    ySlider:UpdateUIValue(0)
                end
                SaveAndRefresh()
                UpdateAnchorVisibility()
            end,
            UI.GetOptionLabel(anchorTargets, gd.anchorTarget or "screen", L["Screen"]))

        local yAfterTarget = right.y

        anchorLabel = C.Label(right, L["Anchor Point"])
        anchorDropdown = C.PositionDropdown(right,
            function() return gd.anchorPoint or "CENTER" end,
            function(val) gd.anchorPoint = val; SaveAndRefresh() end,
            gd.anchorPoint or "CENTER")

        relLabel = C.Label(right, L["Relative Point"])
        relDropdown = C.PositionDropdown(right,
            function() return gd.anchorRelativeTo or "CENTER" end,
            function(val) gd.anchorRelativeTo = val; SaveAndRefresh() end,
            gd.anchorRelativeTo or "CENTER")

        local yAfterConditional = right.y

        xSlider = C.Slider(right, L["X Offset"], -840, 840, gd.offsetX or 0, function(v)
            gd.offsetX = UI.RoundToInt(v); SaveAndRefresh()
        end)
        ySlider = C.Slider(right, L["Y Offset"], -470, 470, gd.offsetY or 0, function(v)
            gd.offsetY = UI.RoundToInt(v); SaveAndRefresh()
        end)

        UpdateAnchorVisibility = function()
            local isScreen = (gd.anchorTarget or "screen") == "screen"
            anchorLabel:SetShown(not isScreen)
            anchorDropdown:SetShown(not isScreen)
            relLabel:SetShown(not isScreen)
            relDropdown:SetShown(not isScreen)
            if not isScreen then
                anchorDropdown:SetDefaultText(gd.anchorPoint or "CENTER")
                relDropdown:SetDefaultText(gd.anchorRelativeTo or "CENTER")
            end
            -- Collapse the gap the hidden dropdowns leave behind.
            local sliderY = isScreen and yAfterTarget or yAfterConditional
            xSlider:ClearAllPoints()
            xSlider:SetPoint("TOPLEFT", right.x, sliderY)
            ySlider:ClearAllPoints()
            ySlider:SetPoint("TOPLEFT", right.x, sliderY - 46)
            rc:SetHeight(math.max(C.MaxDepth(), math.abs(sliderY - 92)) + 24)
        end
        UpdateAnchorVisibility()
    end

    -- Per-bar settings, spread across two columns.
    ShowBarSettings = function(bar, groupIndex)
        if not bar then ClearPanel(); return end
        M.NormalizeBar(bar)

        local _, rc = CreatePanelContent(400)

        local function Save() SaveAndRefresh() end
        local function Write(key, value) bar[key] = value; Save() end
        local function WriteColor(key, r, g, b, a)
            bar[key] = { r = r, g = g, b = b, a = a or 1 }
            Save()
        end

        local isStack = bar.barType == M.TYPE_STACK

        -- Title row: identity plus the two per-bar actions.
        local titleIcon = CreateFrame("Frame", nil, rc)
        titleIcon:SetSize(26, 26)
        titleIcon:SetPoint("TOPLEFT", 0, 0)
        local iconTex = titleIcon:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        local tex = bar.spellID and C_Spell.GetSpellTexture(bar.spellID)
        iconTex:SetTexture(tex or 134400)
        CDM_C.ApplyIconTexCoord(iconTex, CDM_C.GetEffectiveZoomAmount())
        if CDM.BORDER and CDM.BORDER.CreateBorder then
            CDM.BORDER:CreateBorder(titleIcon)
            if CDM.BORDER.activeBorders then CDM.BORDER.activeBorders[titleIcon] = nil end
        end

        local barName = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font18")
        barName:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
        barName:SetText(bar.name
            or (bar.spellID and C_Spell.GetSpellName(bar.spellID))
            or L["Unknown"])
        barName:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)

        local removeBtn = UI.CreateTextButton(rc)
        removeBtn:SetSize(100, 22)
        removeBtn:SetPoint("TOPRIGHT", rc, "TOPRIGHT", -4, -2)
        removeBtn:SetText(L["Remove Bar"])
        removeBtn:SetScript("OnClick", function()
            M.RemoveBar(bar, currentSpecID)
            if selectedBar == bar then
                selectedBar = nil
                selectedBarGroupIndex = nil
            end
            ClearPanel()
            SaveAndRefresh()
            RefreshLeftPanelIfNeeded()
        end)

        local typeDropdown = MakeDropdown(rc)
        typeDropdown:SetWidth(140)
        typeDropdown:SetPoint("RIGHT", removeBtn, "LEFT", -8, 0)
        typeDropdown:SetDefaultText(
            UI.GetOptionLabel(BAR_TYPE_OPTIONS, bar.barType, L["Timer Bar"]))
        UI.SetupValueDropdown(typeDropdown, BAR_TYPE_OPTIONS,
            function() return bar.barType end,
            function(val)
                bar.barType = val
                M.NormalizeBar(bar)
                Save()
                RefreshLeftPanelIfNeeded()
                ShowBarSettings(bar, groupIndex)
            end)

        -- Tab strip: the shared Blizzard-atlas tabs, same as the Cooldowns and
        -- Text pages, followed by the thin horizontal divider they all use.
        local tabHost = CreateFrame("Frame", nil, rc)
        tabHost:SetPoint("TOPLEFT", 0, -36)
        tabHost:SetPoint("TOPRIGHT", rc, "TOPRIGHT", 0, -36)
        tabHost:SetHeight(240)

        local subTabs = UI.CreateSubTabBar(tabHost, {
            { id = "appearance", label = L["Appearance"] },
            { id = "text",       label = L["Text"] },
            { id = "custom",     label = L["Custom"] },
        }, barSettingsTab)

        local tabPages = subTabs.subPages

        local divider = tabHost:CreateTexture(nil, "ARTWORK")
        divider:SetAtlas("Options_HorizontalDivider", true)
        divider:SetPoint("TOPLEFT", subTabs.barFrame, "BOTTOMLEFT", -30, 0)
        divider:SetPoint("TOPRIGHT", subTabs.barFrame, "BOTTOMRIGHT", 30, 0)
        local dividerH = divider:GetHeight()

        -- CreateSubTabBar anchors its pages to BOTTOMRIGHT of the host, which
        -- would stretch them; re-anchor to a fixed top so each page sizes to
        -- its own content instead.
        local pagesTop = -(37 + dividerH + 8)
        for _, pg in pairs(tabPages) do
            pg:ClearAllPoints()
            pg:SetPoint("TOPLEFT", tabHost, "TOPLEFT", 0, pagesTop)
            pg:SetPoint("TOPRIGHT", tabHost, "TOPRIGHT", 0, pagesTop)
            pg:SetHeight(1)
        end

        local pageHeights = {}
        local ResizeToTab

        -- The helper's own SelectTab handles the atlas swap; wrap it so
        -- switching also closes any open dropdown (its anchor button is about
        -- to be hidden) and resizes the scroll child to the new tab.
        local function SelectTab(id)
            panelManager.CloseDropdownMenus()
            subTabs.selectTab(id)
            barSettingsTab = id
            if ResizeToTab then ResizeToTab(id) end
        end

        for _, def in ipairs({ "appearance", "text", "custom" }) do
            local btn = subTabs.tabButtons[def]
            if btn then
                btn:SetScript("OnClick", function() SelectTab(def) end)
            end
        end

        -- Each tab lays its sections out in two columns of its own.
        local function BuildPage(id, build)
            local pg = tabPages[id]
            local C = NewColumns(pg)
            build(C)
            C.Flush()
            local h = C.MaxDepth() + 16
            pg:SetHeight(h)
            pageHeights[id] = h
        end

        -- ---- Appearance: how the bar looks and how big it is ----
        BuildPage("appearance", function(C)
            C.Section(122, function(col)
                C.Header(col, L["Dimensions"])
                C.Slider(col, L["Bar Width (0 = Auto)"], 0, 600, bar.width or 0, function(v)
                    local value = UI.RoundToInt(v)
                    if value > 0 and value < 60 then value = 60 end
                    Write("width", value)
                end)
                C.Slider(col, L["Bar Height"], 4, 40, bar.height or 20, function(v)
                    Write("height", UI.RoundToInt(v))
                end)
            end)

            C.Section(248, function(col)
                C.Header(col, L["Appearance"])
                C.Label(col, L["Bar Texture:"])
                local dd = MakeDropdown(tabPages.appearance)
                dd:SetWidth(200)
                dd:SetPoint("TOPLEFT", col.x, col.y)
                dd:SetDefaultText(bar.texture or "Solid")
                UI.SetupMediaDropdown(dd, "statusbar",
                    function() return bar.texture or "Solid" end,
                    function(name) bar.texture = name; Save() end,
                    function(name) dd:SetDefaultText(name or "Solid") end)
                col.y = col.y - 36
                C.ColorRow(col, L["Bar Color"], bar.barColor,
                    function(r, g, b, a) WriteColor("barColor", r, g, b, a) end)
                C.ColorRow(col, L["Background Color"], bar.bgColor,
                    function(r, g, b, a) WriteColor("bgColor", r, g, b, a) end)
                C.Label(col, L["Icon Position:"])
                C.Dropdown(col, ICON_POS_OPTIONS,
                    function() return bar.iconPosition or "LEFT" end,
                    function(val) bar.iconPosition = val; Save() end,
                    UI.GetOptionLabel(ICON_POS_OPTIONS, bar.iconPosition or "LEFT", L["Left"]))
                C.Slider(col, L["Icon-Bar Gap"], -1, 20, bar.iconGap or 1, function(v)
                    Write("iconGap", UI.RoundToInt(v))
                end)
            end)
        end)

        -- ---- Text: every string the bar can draw ----
        BuildPage("text", function(C)
            C.Section(bar.showName ~= false and 274 or 62, function(col)
                C.Header(col, L["Name Text"])
                C.Check(col, L["Show Buff Name"], bar.showName ~= false, function(checked)
                    bar.showName = checked
                    Save()
                    ShowBarSettings(bar, groupIndex)
                end)
                if bar.showName ~= false then
                    C.Slider(col, L["Max Name Length (0 = Full)"], 0, 30, bar.nameMaxChars or 0,
                        function(v) Write("nameMaxChars", UI.RoundToInt(v)) end)
                    C.Slider(col, L["Font Size"], 6, 32, bar.nameFontSize or 15,
                        function(v) Write("nameFontSize", UI.RoundToInt(v)) end)
                    C.ColorRow(col, L["Color"], bar.nameColor,
                        function(r, g, b, a) WriteColor("nameColor", r, g, b, a) end)
                    C.Slider(col, L["X Offset"], -50, 50, bar.nameOffsetX or 2,
                        function(v) Write("nameOffsetX", UI.RoundToInt(v)) end)
                    C.Slider(col, L["Y Offset"], -20, 20, bar.nameOffsetY or 0,
                        function(v) Write("nameOffsetY", UI.RoundToInt(v)) end)
                end
            end)

            local shownStack = bar.showApplications ~= false
            C.Section(shownStack and 286 or 62, function(col)
                C.Header(col, L["Stack Text"])
                C.Check(col, L["Show Stack Count"], shownStack, function(checked)
                    bar.showApplications = checked
                    Save()
                    ShowBarSettings(bar, groupIndex)
                end)
                if not shownStack then return end
                C.Slider(col, L["Font Size"], 6, 32, bar.applicationsFontSize or 15,
                    function(v) Write("applicationsFontSize", UI.RoundToInt(v)) end)
                C.ColorRow(col, L["Color"], bar.applicationsColor,
                    function(r, g, b, a) WriteColor("applicationsColor", r, g, b, a) end)
                C.Label(col, L["Position"])
                C.PositionDropdown(col,
                    function() return bar.applicationsPosition or "CENTER" end,
                    function(val) bar.applicationsPosition = val; Save() end,
                    bar.applicationsPosition or "CENTER")
                C.Slider(col, L["X Offset"], -50, 50, bar.applicationsOffsetX or 0,
                    function(v) Write("applicationsOffsetX", UI.RoundToInt(v)) end)
                C.Slider(col, L["Y Offset"], -20, 20, bar.applicationsOffsetY or 0,
                    function(v) Write("applicationsOffsetY", UI.RoundToInt(v)) end)
            end)

            -- Duration text is meaningless on a stack bar.
            if not isStack then
                local shown = bar.showDuration ~= false
                -- Header+check, then size/color/position/x/y.
                local h = shown and (62 + 46 + 28 + 22 + 36 + 46 + 46) or 62
                C.Section(h, function(col)
                    C.Header(col, L["Duration Text"])
                    C.Check(col, L["Show Duration Text"], shown, function(checked)
                        bar.showDuration = checked
                        Save()
                        ShowBarSettings(bar, groupIndex)
                    end)
                    if not shown then return end
                    C.Slider(col, L["Font Size"], 6, 32, bar.durationFontSize or 15,
                        function(v) Write("durationFontSize", UI.RoundToInt(v)) end)
                    C.ColorRow(col, L["Color"], bar.durationColor,
                        function(r, g, b, a) WriteColor("durationColor", r, g, b, a) end)
                    C.Label(col, L["Position"])
                    C.PositionDropdown(col,
                        function() return bar.durationPosition or "RIGHT" end,
                        function(val) bar.durationPosition = val; Save() end,
                        bar.durationPosition or "RIGHT")
                    C.Slider(col, L["X Offset"], -50, 50, bar.durationOffsetX or -2,
                        function(v) Write("durationOffsetX", UI.RoundToInt(v)) end)
                    C.Slider(col, L["Y Offset"], -20, 20, bar.durationOffsetY or 0,
                        function(v) Write("durationOffsetY", UI.RoundToInt(v)) end)
                    -- Decimals live under Custom: they are timer-bar behaviour,
                    -- not text styling.
                end)
            end
        end)

        -- ---- Custom: behaviour unique to this bar type ----
        BuildPage("custom", function(C)
            if isStack then
                C.Section(128, function(col)
                    C.Header(col, L["Stack Fill"])
                    C.Slider(col, L["Max Stacks"], 1, 100, bar.maxStacks or 1,
                        function(v) Write("maxStacks", UI.RoundToInt(v)) end)
                    C.Check(col, L["Always Show Bar"], bar.alwaysShow ~= false,
                        function(checked) Write("alwaysShow", checked) end)
                    C.Label(col, L["Keep an empty bar visible when the buff is not active."], true, true)
                end)

                bar.colorThresholds = bar.colorThresholds or {}
                local thresholds = bar.colorThresholds

                C.Section(82 + #thresholds * 28, function(col)
                    C.Header(col, L["Threshold Colors"])
                    C.Label(col, L["The bar recolors once it reaches this many stacks."], true, true)

                    local pg = tabPages.custom
                    for ti = 1, #thresholds do
                        local t = thresholds[ti]
                        if type(t) == "table" then
                            local atLabel = pg:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
                            atLabel:SetText(L["At"])
                            atLabel:SetPoint("TOPLEFT", col.x, col.y - 4)

                            local stacksInput = CreateFrame("EditBox", nil, pg, "InputBoxTemplate")
                            stacksInput:SetSize(44, 20)
                            stacksInput:SetPoint("LEFT", atLabel, "RIGHT", 8, 0)
                            stacksInput:SetAutoFocus(false)
                            stacksInput:SetNumeric(true)
                            stacksInput:SetMaxLetters(3)
                            stacksInput:SetText(tostring(t.stacks or 1))
                            stacksInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
                            stacksInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                            stacksInput:SetScript("OnEditFocusLost", function(self)
                                local n = tonumber(self:GetText())
                                if n and n > 0 then
                                    t.stacks = math.floor(n)
                                else
                                    self:SetText(tostring(t.stacks or 1))
                                end
                                Save()
                            end)

                            local suffix = pg:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
                            suffix:SetText(L["stacks"])
                            suffix:SetPoint("LEFT", stacksInput, "RIGHT", 6, 0)

                            if type(t.color) ~= "table" then
                                t.color = { r = 1, g = 0.6, b = 0, a = 1 }
                            end
                            local picker = UI.CreateSimpleColorPicker(pg, t.color, function(r, g, b, a)
                                t.color = { r = r, g = g, b = b, a = a or 1 }
                                Save()
                            end, true)
                            picker:SetPoint("LEFT", suffix, "RIGHT", 10, 0)

                            local delBtn = UI.CreateTextButton(pg)
                            delBtn:SetSize(22, 20)
                            delBtn:SetPoint("LEFT", picker, "RIGHT", 10, 0)
                            delBtn:SetText("X")
                            local capturedIndex = ti
                            delBtn:SetScript("OnClick", function()
                                table.remove(thresholds, capturedIndex)
                                Save()
                                ShowBarSettings(bar, groupIndex)
                            end)

                            col.y = col.y - 28
                        end
                    end

                    local addBtn = UI.CreateTextButton(pg)
                    addBtn:SetSize(120, 22)
                    addBtn:SetPoint("TOPLEFT", col.x, col.y)
                    addBtn:SetText(L["Add Threshold"])
                    addBtn:SetScript("OnClick", function()
                        local maxStacks = bar.maxStacks or 1
                        local suggested = #thresholds == 0
                            and math.max(1, math.floor(maxStacks / 2))
                            or math.min(maxStacks, (thresholds[#thresholds].stacks or 1) + 1)
                        thresholds[#thresholds + 1] = {
                            stacks = suggested,
                            color = { r = 1, g = 0.6, b = 0, a = 1 },
                        }
                        Save()
                        ShowBarSettings(bar, groupIndex)
                    end)
                    col.y = col.y - 32
                end)

                C.Section(150, function(col)
                    local pg = tabPages.custom
                    C.Header(col, L["Tick Marks"])
                    local tickLabel = pg:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
                    tickLabel:SetText(L["At stacks:"])
                    tickLabel:SetPoint("TOPLEFT", col.x, col.y - 4)

                    local tickInput = CreateFrame("EditBox", nil, pg, "InputBoxTemplate")
                    tickInput:SetSize(110, 20)
                    tickInput:SetPoint("LEFT", tickLabel, "RIGHT", 8, 0)
                    tickInput:SetAutoFocus(false)
                    tickInput:SetMaxLetters(60)
                    tickInput:SetText(bar.tickValues or "")
                    tickInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
                    tickInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                    tickInput:SetScript("OnEditFocusLost", function(self)
                        bar.tickValues = self:GetText()
                        Save()
                    end)
                    col.y = col.y - 26

                    C.Label(col, L["comma separated, e.g. 5,10,15"], true, true)
                    C.Slider(col, L["Tick Width"], 0, 6, bar.tickWidth or 1,
                        function(v) Write("tickWidth", UI.RoundToInt(v)) end)
                    C.ColorRow(col, L["Tick Color"], bar.tickColor,
                        function(r, g, b, a) WriteColor("tickColor", r, g, b, a) end)
                end)
            else
                -- Timer bars: decimals are their bar-type-specific behaviour,
                -- so they sit here rather than under Text -- the same role
                -- Stack Fill plays for a stack bar.
                local dec = bar.timerDecimals ~= false
                C.Section(dec and 128 or 82, function(col)
                    C.Header(col, L["Decimal Timer"])
                    C.Check(col, L["Show Decimals"], dec, function(checked)
                        bar.timerDecimals = checked
                        Save()
                        ShowBarSettings(bar, groupIndex)
                    end)
                    C.Label(col, L["Shows tenths of a second below the threshold."], true, true)
                    if dec then
                        C.Slider(col, L["Decimal Threshold"], 3, 120, bar.decimalThreshold or 5,
                            function(v) Write("decimalThreshold", UI.RoundToInt(v)) end)
                    end
                end)
            end
        end)

        ResizeToTab = function(id)
            local h = (pageHeights[id] or 0)
            tabHost:SetHeight(math.abs(pagesTop) + h)
            -- 36 = the tab host's own top offset inside the scroll child.
            rc:SetHeight(36 + math.abs(pagesTop) + h + 16)
        end

        -- The helper already selected `barSettingsTab` at construction and its
        -- own SelectTab early-returns on an unchanged id, so calling the
        -- wrapper here would no-op and never size the scroll child. Size it
        -- directly instead; the wrapper only matters for later tab clicks.
        local wanted = barSettingsTab
        if not tabPages[wanted] then
            wanted = "appearance"
            SelectTab(wanted)
        else
            ResizeToTab(wanted)
        end
    end

    -- Add Bar: lists what Blizzard's buff-bar viewer currently tracks.
    ShowAddBarPanel = function(targetGroupIndex)
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
                ClearPanel()
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
                    selectedGroupIndex = nil
                    SaveAndRefresh()
                    RefreshLeftPanelIfNeeded()
                    ShowBarSettings(newBar, targetGroupIndex)
                end)
            end
            yOff = startY - perCol * 28
        end

        rc:SetHeight(math.abs(yOff) + 24)
    end

    -- Toolbar buttons

    do
        local addGroupBtn = UI.CreateTextButton(buttonRow)
        addGroupBtn:SetSize(100, 22)
        addGroupBtn:SetPoint("LEFT", 0, 0)
        addGroupBtn:SetText(L["Add Group"])
        addGroupBtn:SetScript("OnClick", function()
            local groups = EnsureGroups()
            if not groups then return end
            local newIndex = #groups + 1
            groups[newIndex] = M.CreateGroup(groups,
                Shared.GetUniqueGroupName(groups, "BAR" .. newIndex))
            selectedGroupIndex = newIndex
            selectedBar = nil
            SaveAndRefresh()
            RefreshLeftPanelIfNeeded()
            ShowGroupSettings(newIndex)
        end)

        local addBarBtn = UI.CreateTextButton(buttonRow)
        addBarBtn:SetSize(100, 22)
        addBarBtn:SetPoint("LEFT", addGroupBtn, "RIGHT", 6, 0)
        addBarBtn:SetText(L["Add Bar"])
        addBarBtn:SetScript("OnClick", function()
            -- Adding into the selected group is the normal path; with nothing
            -- selected the bar lands ungrouped.
            local target = selectedGroupIndex or selectedBarGroupIndex
            ShowAddBarPanel(target)
        end)

        local hint = buttonRow:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
        hint:SetPoint("LEFT", addBarBtn, "RIGHT", 12, 0)
        hint:SetText(L["Drag a bar onto a group to move it."])
        UI.SetTextMuted(hint)
    end

    -- Group strip tiles

    local tiles = {}
    local tilesActive = 0

    local function AcquireTile()
        tilesActive = tilesActive + 1
        local tile = tiles[tilesActive]
        if not tile then
            tile = CreateFrame("Frame", nil, stripFrame)
            tile:SetSize(TILE_W, TILE_MIN_H)

            -- A card: 1px outline, dark body, and a slightly lighter header
            -- strip carrying the name. Built from plain textures so it picks up
            -- no Blizzard art that would fight the rest of the config frame.
            -- A true outline: four 1px edges, hollow in the middle. A
            -- full-rect texture behind the body would composite with it and
            -- darken the whole tile.
            local edges = {}
            for e = 1, 4 do
                local t = tile:CreateTexture(nil, "BORDER")
                t:SetColorTexture(0, 0, 0, 0.9)
                edges[e] = t
            end
            edges[1]:SetPoint("TOPLEFT")
            edges[1]:SetPoint("TOPRIGHT")
            edges[1]:SetHeight(1)
            edges[2]:SetPoint("BOTTOMLEFT")
            edges[2]:SetPoint("BOTTOMRIGHT")
            edges[2]:SetHeight(1)
            edges[3]:SetPoint("TOPLEFT")
            edges[3]:SetPoint("BOTTOMLEFT")
            edges[3]:SetWidth(1)
            edges[4]:SetPoint("TOPRIGHT")
            edges[4]:SetPoint("BOTTOMRIGHT")
            edges[4]:SetWidth(1)
            tile.borderEdges = edges

            -- Shim so the three call sites can keep recoloring "the border".
            tile.border = {
                SetColorTexture = function(_, r, g, b, a)
                    for e = 1, 4 do edges[e]:SetColorTexture(r, g, b, a) end
                end,
            }

            -- Header first, then the body BELOW it -- they must not overlap.
            -- Stacking two translucent blacks composites their alphas (0.5 over
            -- 0.75 reads as ~0.875), which is why the header looked solid.
            local header = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
            header:SetPoint("TOPLEFT", 1, -1)
            header:SetPoint("TOPRIGHT", -1, -1)
            header:SetHeight(TILE_HEADER_H)
            header:SetColorTexture(0, 0, 0, 0.55)
            tile.header = header

            local bg = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
            bg:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            bg:SetPoint("BOTTOMRIGHT", -1, 1)
            bg:SetColorTexture(0, 0, 0, 0.5)
            tile.bg = bg

            -- Selection reads as an accent line under the header plus a tinted
            -- body, rather than a flat wash over the whole tile.
            local accent = tile:CreateTexture(nil, "ARTWORK")
            accent:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            accent:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
            accent:SetHeight(2)
            accent:Hide()
            tile.accent = accent

            local hl = tile:CreateTexture(nil, "BACKGROUND", nil, 3)
            hl:SetPoint("TOPLEFT", 1, -1 - TILE_HEADER_H)
            hl:SetPoint("BOTTOMRIGHT", -1, 1)
            hl:SetColorTexture(0.20, 0.36, 0.66, 0.18)
            hl:Hide()
            tile.highlight = hl

            local title = tile:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
            title:SetPoint("LEFT", tile, "TOPLEFT", 8, -1 - TILE_HEADER_H / 2)
            title:SetPoint("RIGHT", tile, "TOPRIGHT", -24, -1 - TILE_HEADER_H / 2)
            title:SetJustifyH("LEFT")
            title:SetWordWrap(false)
            tile.title = title

            -- Whole-tile click target sits UNDER the icons so a bar icon still
            -- gets its own clicks.
            local selectBtn = CreateFrame("Button", nil, tile)
            selectBtn:SetAllPoints()
            selectBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            tile.selectBtn = selectBtn

            local delBtn = CreateFrame("Button", nil, tile)
            delBtn:SetSize(16, 16)
            delBtn:SetPoint("TOPRIGHT", -5, -(1 + (TILE_HEADER_H - 16) / 2))
            delBtn:SetFrameLevel(tile:GetFrameLevel() + 4)
            Shared.ApplyRemoveButtonText(delBtn)
            tile.delBtn = delBtn

            tile.icons = {}
            tile.iconsActive = 0
            tiles[tilesActive] = tile
        end
        tile.iconsActive = 0
        -- Pooled: this tile may now be a different group entirely, so every
        -- state a previous pass could have set is reset here.
        tile.title:Show()
        tile.accent:Hide()
        tile.highlight:Hide()
        tile.delBtn:Show()
        if tile.renameBox then tile.renameBox:Hide() end
        if tile.emptyText then tile.emptyText:Hide() end
        tile:Show()
        return tile
    end

    local function AcquireTileIcon(tile)
        tile.iconsActive = tile.iconsActive + 1
        local f = tile.icons[tile.iconsActive]
        if not f then
            f = CreateFrame("Button", nil, tile)
            f:SetSize(TILE_ICON, TILE_ICON)
            f:SetFrameLevel(tile:GetFrameLevel() + 2)
            f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            f:RegisterForDrag("LeftButton")

            -- 1px frame around the art so icons read as distinct tiles against
            -- the dark card rather than floating squares.
            local edge = f:CreateTexture(nil, "BACKGROUND")
            edge:SetAllPoints()
            edge:SetColorTexture(0, 0, 0, 1)
            f.edge = edge

            local icon = f:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", -1, 1)
            CDM_C.ApplyIconTexCoord(icon, CDM_C.GetEffectiveZoomAmount())
            f.icon = icon

            -- Selected: a bright ring drawn as four edges, so the icon art
            -- stays at full brightness underneath (a translucent overlay would
            -- just dull it).
            local selEdges = {}
            for e = 1, 4 do
                local t = f:CreateTexture(nil, "OVERLAY")
                t:SetColorTexture(1, 0.82, 0.30, 1)
                t:Hide()
                selEdges[e] = t
            end
            selEdges[1]:SetPoint("TOPLEFT")
            selEdges[1]:SetPoint("TOPRIGHT")
            selEdges[1]:SetHeight(2)
            selEdges[2]:SetPoint("BOTTOMLEFT")
            selEdges[2]:SetPoint("BOTTOMRIGHT")
            selEdges[2]:SetHeight(2)
            selEdges[3]:SetPoint("TOPLEFT")
            selEdges[3]:SetPoint("BOTTOMLEFT")
            selEdges[3]:SetWidth(2)
            selEdges[4]:SetPoint("TOPRIGHT")
            selEdges[4]:SetPoint("BOTTOMRIGHT")
            selEdges[4]:SetWidth(2)
            f.selEdges = selEdges

            local hover = f:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints()
            hover:SetColorTexture(1, 1, 1, 0.18)

            -- Badge sits on a dark plate so it stays legible over bright art.
            local badgePlate = f:CreateTexture(nil, "OVERLAY", nil, 2)
            badgePlate:SetSize(13, 13)
            badgePlate:SetPoint("BOTTOMRIGHT", -1, 1)
            badgePlate:SetColorTexture(0, 0, 0, 0.75)
            badgePlate:Hide()
            f.badgePlate = badgePlate

            local badge = f:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
            badge:SetPoint("CENTER", badgePlate, "CENTER", 0, 0)
            f.badge = badge

            tile.icons[tile.iconsActive] = f
        end
        f:Show()
        return f
    end

    local function ReleaseAllTiles()
        for i = 1, tilesActive do
            local tile = tiles[i]
            for j = 1, #tile.icons do tile.icons[j]:Hide() end
            tile:Hide()
        end
        tilesActive = 0
    end

    local function TypeBadge(bar)
        return bar.barType == M.TYPE_STACK and "|cff88bbffS|r" or ""
    end

    -- Populate one tile with a group's bars (or the ungrouped list).
    local function FillTile(tile, bars, groupIndex)
        for i = 1, #bars do
            local bar = bars[i]
            M.NormalizeBar(bar)
            local f = AcquireTileIcon(tile)

            local row = math.floor((i - 1) / TILE_ICONS_PER_ROW)
            local col = (i - 1) % TILE_ICONS_PER_ROW
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", TILE_PAD + col * (TILE_ICON + TILE_ICON_GAP),
                -(TILE_HEADER_H + TILE_PAD) - row * (TILE_ICON + TILE_ICON_GAP))

            -- Always write the texture: these buttons are pooled per slot, so
            -- leaving it unset would keep the previous bar's icon on screen.
            local tex = bar.spellID and C_Spell.GetSpellTexture(bar.spellID)
            if tex then
                f.icon:SetTexture(tex)
            else
                f.icon:SetTexture(134400)   -- question mark
            end

            local badgeText = TypeBadge(bar)
            f.badge:SetText(badgeText)
            f.badgePlate:SetShown(badgeText ~= "")

            local isSel = (selectedBar == bar)
            for e = 1, 4 do f.selEdges[e]:SetShown(isSel) end

            local capturedBar = bar
            f:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if capturedBar.spellID then
                    GameTooltip:SetSpellByID(capturedBar.spellID)
                else
                    GameTooltip:SetText(capturedBar.name or L["Unknown"], 1, 1, 1)
                end
                GameTooltip:AddLine(capturedBar.barType == M.TYPE_STACK
                    and L["Stack Bar"] or L["Timer Bar"], 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            f:SetScript("OnLeave", function() GameTooltip:Hide() end)
            f:SetScript("OnClick", function(_, button)
                if button == "RightButton" then
                    MenuUtil.CreateContextMenu(f, function(_, rootDescription)
                        rootDescription:CreateButton(L["Duplicate"], function()
                            local list = groupIndex
                                and (GetGroups()[groupIndex] or {}).bars
                                or M.EnsureUngrouped(currentSpecID)
                            if not list then return end
                            list[#list + 1] = M.CloneBar(capturedBar)
                            SaveAndRefresh()
                            RefreshLeftPanelIfNeeded()
                        end)
                        rootDescription:CreateButton(L["Remove"], function()
                            M.RemoveBar(capturedBar, currentSpecID)
                            if selectedBar == capturedBar then
                                selectedBar = nil
                                selectedBarGroupIndex = nil
                                ClearPanel()
                            end
                            SaveAndRefresh()
                            RefreshLeftPanelIfNeeded()
                        end)
                    end)
                    return
                end
                selectedBar = capturedBar
                selectedGroupIndex = nil
                selectedBarGroupIndex = groupIndex
                ShowBarSettings(capturedBar, groupIndex)
                RefreshLeftPanelIfNeeded()
            end)
            f:SetScript("OnDragStart", function() StartDrag(capturedBar) end)
            f:SetScript("OnDragStop", function() EndDrag() end)
        end

        -- Grow the tile to fit however many rows of icons it holds. An empty
        -- group keeps one row's worth of space so it still reads as a drop
        -- target.
        local rows = math.max(1, math.ceil(#bars / TILE_ICONS_PER_ROW))
        local needed = TILE_HEADER_H + TILE_PAD
            + rows * TILE_ICON + (rows - 1) * TILE_ICON_GAP
            + TILE_PAD
        tile:SetHeight(math.max(TILE_MIN_H, needed))

        -- Prompt in place of icons when the group is empty.
        if #bars == 0 then
            if not tile.emptyText then
                local t = tile:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
                t:SetPoint("TOPLEFT", TILE_PAD, -(TILE_HEADER_H + TILE_PAD + 6))
                t:SetPoint("TOPRIGHT", -TILE_PAD, -(TILE_HEADER_H + TILE_PAD + 6))
                t:SetJustifyH("LEFT")
                tile.emptyText = t
            end
            tile.emptyText:SetText(L["Drag a bar here, or Add Bar"])
            UI.SetTextFaint(tile.emptyText)
            tile.emptyText:Show()
        elseif tile.emptyText then
            tile.emptyText:Hide()
        end

        return tile:GetHeight()
    end

    local function BuildStrip()
        ReleaseAllTiles()
        ClearDropTargets()
        stripEmptyText:Hide()

        local groups = GetGroups()
        local ungrouped = GetUngrouped()

        if #groups == 0 and #ungrouped == 0 then
            stripFrame:SetHeight(TILE_MIN_H)
            stripEmptyText:SetText(L["No bar groups yet. Add Group, then Add Bar."])
            stripEmptyText:Show()
            UI.SetTextFaint(stripEmptyText)
            return
        end

        local x, tallest = 0, TILE_MIN_H

        for gi = 1, #groups do
            local gd = groups[gi]
            local tile = AcquireTile()
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", x, 0)

            -- The tile body and header are flat black; selection reads from the
            -- border, the accent line under the header, the body tint and the
            -- title colour instead.
            local isSel = (selectedGroupIndex == gi)
            tile.highlight:SetShown(isSel)
            tile.accent:SetShown(isSel)
            if isSel then
                tile.accent:SetColorTexture(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
                tile.border:SetColorTexture(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 0.85)
            else
                tile.border:SetColorTexture(0, 0, 0, 0.9)
            end

            local displayName = gd.name or ("Group " .. gi)
            tile.title:SetText(displayName)
            if isSel then
                UI.SetTextWhite(tile.title)
            else
                UI.SetTextSubtle(tile.title)
            end

            -- Inline rename replaces the title in place. Shared's helper spans
            -- between two atlas pieces the expandable headers have; a tile has
            -- no such anchors, so the box is built directly over the title.
            if renameActiveGroupIndex == gi then
                tile.title:Hide()
                -- Reuse the tile's box: BuildStrip can run repeatedly while a
                -- rename is open, and creating a fresh one each pass would
                -- stack focused EditBoxes on the same tile.
                local editBox = tile.renameBox
                if not editBox then
                    editBox = CreateFrame("EditBox", nil, tile, "InputBoxTemplate")
                    editBox:SetPoint("TOPLEFT", 8, -4)
                    editBox:SetPoint("TOPRIGHT", -22, -4)
                    editBox:SetHeight(18)
                    editBox:SetFontObject("AyijeCDM_Font14")
                    editBox:SetAutoFocus(true)
                    editBox:SetMaxLetters(40)
                    tile.renameBox = editBox
                end
                editBox:SetFrameLevel(tile:GetFrameLevel() + 6)
                editBox:SetText(displayName)
                editBox:Show()
                editBox:SetFocus()
                editBox:HighlightText()

                editBox:SetScript("OnEnterPressed", function()
                    CommitPendingRename(true)
                    if selectedGroupIndex == gi then ShowGroupSettings(gi) end
                    RefreshLeftPanelIfNeeded()
                end)
                editBox:SetScript("OnEditFocusLost", function()
                    CommitPendingRename(true)
                    if selectedGroupIndex == gi then ShowGroupSettings(gi) end
                    RefreshLeftPanelIfNeeded()
                end)
                editBox:SetScript("OnEscapePressed", function()
                    CommitPendingRename(false)
                    RefreshLeftPanelIfNeeded()
                end)
                renameActiveEditBox = editBox
            end

            tile.delBtn:Show()
            tile.delBtn:SetScript("OnClick", function()
                local function DoDelete()
                    -- Resolve any open rename FIRST: the indices it refers to
                    -- are about to shift under it.
                    CommitPendingRename(renameActiveGroupIndex ~= gi)
                    local specGroups = EnsureGroups()
                    if specGroups then
                        -- Bars in a deleted group fall back to ungrouped rather
                        -- than being destroyed with it.
                        local g = specGroups[gi]
                        if g and g.bars and #g.bars > 0 then
                            local list = M.EnsureUngrouped(currentSpecID)
                            if list then
                                for _, b in ipairs(g.bars) do list[#list + 1] = b end
                            end
                        end
                        table.remove(specGroups, gi)
                    end
                    if selectedGroupIndex == gi then
                        selectedGroupIndex = nil
                        selectedBar = nil
                        ClearPanel()
                    elseif selectedGroupIndex and selectedGroupIndex > gi then
                        selectedGroupIndex = selectedGroupIndex - 1
                    end
                    if selectedBarGroupIndex then
                        if selectedBarGroupIndex == gi then
                            selectedBarGroupIndex = nil
                        elseif selectedBarGroupIndex > gi then
                            selectedBarGroupIndex = selectedBarGroupIndex - 1
                        end
                    end
                    SaveAndRefresh()
                    RefreshLeftPanelIfNeeded()
                end

                local barCount = gd.bars and #gd.bars or 0
                if barCount > 0 then
                    local dialog = StaticPopupDialogs["AYIJE_CDM_CONFIRM_DELETE_BARGROUP"]
                    dialog.text = string.format(
                        L["Delete group? Its %d bar(s) return to ungrouped."], barCount)
                    dialog._pendingDelete = DoDelete
                    StaticPopup_Show("AYIJE_CDM_CONFIRM_DELETE_BARGROUP")
                else
                    DoDelete()
                end
            end)

            tile.selectBtn:SetScript("OnClick", function(_, button)
                if button == "RightButton" then
                    MenuUtil.CreateContextMenu(tile.selectBtn, function(_, rootDescription)
                        rootDescription:CreateButton(L["Rename"], function()
                            renameActiveGroupIndex = gi
                            RefreshLeftPanelIfNeeded()
                        end)
                        rootDescription:CreateButton(L["Add Bar"], function()
                            ShowAddBarPanel(gi)
                        end)
                        rootDescription:CreateButton(L["Duplicate"], function()
                            local specGroups = EnsureGroups()
                            if not specGroups then return end
                            local clone = M.CreateGroup(specGroups,
                                Shared.GetUniqueGroupName(specGroups, displayName))
                            clone.grow = gd.grow
                            clone.spacing = gd.spacing
                            clone.anchorTarget = gd.anchorTarget
                            clone.anchorPoint = gd.anchorPoint
                            clone.anchorRelativeTo = gd.anchorRelativeTo
                            clone.offsetX = gd.offsetX
                            clone.offsetY = gd.offsetY
                            for _, b in ipairs(gd.bars or {}) do
                                clone.bars[#clone.bars + 1] = M.CloneBar(b)
                            end
                            specGroups[#specGroups + 1] = clone
                            selectedGroupIndex = #specGroups
                            selectedBar = nil
                            SaveAndRefresh()
                            ShowGroupSettings(selectedGroupIndex)
                            RefreshLeftPanelIfNeeded()
                        end)
                    end)
                    return
                end
                selectedGroupIndex = gi
                selectedBar = nil
                selectedBarGroupIndex = nil
                ShowGroupSettings(gi)
                RefreshLeftPanelIfNeeded()
            end)

            local h = FillTile(tile, gd.bars or {}, gi)
            if h > tallest then tallest = h end
            RegisterDropTarget(tile, gi)
            x = x + TILE_W + TILE_GAP
        end

        -- Ungrouped tile only when it has contents: the intended workflow is
        -- that every bar lives in a group, so an always-visible empty tile
        -- would just invite confusion.
        if #ungrouped > 0 then
            local tile = AcquireTile()
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", x, 0)
            -- Amber border so it reads as "these want a home", without being an
            -- error state. The body stays black like every other tile.
            tile.border:SetColorTexture(0.55, 0.40, 0.16, 0.9)
            tile.highlight:Hide()
            tile.accent:Hide()
            tile.title:SetText(L["Ungrouped"])
            UI.SetTextMuted(tile.title)
            tile.delBtn:Hide()
            tile.delBtn:SetScript("OnClick", nil)
            tile.selectBtn:SetScript("OnClick", nil)

            local h = FillTile(tile, ungrouped, nil)
            if h > tallest then tallest = h end
            RegisterDropTarget(tile, nil)
        end

        stripFrame:SetHeight(tallest)
    end

    RefreshAll = function()
        -- No rename handling here: BuildStrip reuses each tile's own box
        -- (tile.renameBox) rather than creating a new one per pass, and hides
        -- it on any tile that is not being renamed. A rebuild therefore cannot
        -- orphan or duplicate one. Group deletion, the one case where the
        -- index a rename refers to shifts, commits explicitly in DoDelete.
        BuildStrip()
    end

    page:SetScript("OnMouseUp", function() EndDrag() end)

    page:HookScript("OnHide", function()
        panelManager.CloseDropdownMenus()
        CancelDrag()
    end)

    page:HookScript("OnShow", function()
        local spec = GetSpecialization()
        local newSpecID = spec and GetSpecializationInfo(spec) or nil
        if newSpecID ~= currentSpecID then
            currentSpecID = newSpecID
            selectedGroupIndex = nil
            selectedBar = nil
            selectedBarGroupIndex = nil
            ClearPanel()
        end
        RefreshAll()
        if selectedGroupIndex then
            ShowGroupSettings(selectedGroupIndex)
        elseif selectedBar then
            ShowBarSettings(selectedBar, selectedBarGroupIndex)
        end
    end)
end

API:RegisterConfigTab("bars", L["Bars"], CreateBarsTab, 8)
