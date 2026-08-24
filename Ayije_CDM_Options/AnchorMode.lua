local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
if not CDM then return end

local ns = CDM._OptionsNS
local L = CDM.L
local VIEWERS = CDM.CONST.VIEWERS

local GetCursorPosition = GetCursorPosition
local GetCurrentKeyBoardFocus = GetCurrentKeyBoardFocus
local GetPhysicalScreenSize = GetPhysicalScreenSize
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown = IsShiftKeyDown
local math_abs = math.abs
local math_ceil = math.ceil
local math_floor = math.floor
local math_rad = math.rad
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber

local AnchorMode = {
    active = false,
    entries = {},
    overlays = {},
    selectedEntry = nil,
}

local configPositionUpdaters = {}

function ns.RegisterAnchorPositionUpdater(key, callback)
    if type(key) ~= "string" or type(callback) ~= "function" then return end
    configPositionUpdaters[key] = callback
end

local function NotifyConfigPosition(entry, x, y)
    local callback = entry and configPositionUpdaters[entry.key]
    if callback then callback(x, y) end
end

local GRID_SIZE = 64
local GRID_LINE_WIDTH = 1
local GRID_COLOR = { 0, 0, 0, 0.4 }
local GRID_CENTER_ALPHA = 0.55
local SNAP_RANGE = 10
local OVERLAY_COLOR = { 0.08, 0.08, 0.08, 0.72 }
local GOLD = { 1, 0.82, 0, 1 }
local gridCenterX, gridCenterY = 0, 0
local ARROW_TEXTURE = "Interface\\AddOns\\Ayije_CDM\\Media\\Textures\\collapse"

local grid = CreateFrame("Frame", "AyijeCDM_AnchorGrid", UIParent)
grid:SetAllPoints(UIParent)
grid:SetFrameStrata("BACKGROUND")
grid.lines = {}
grid:Hide()

local overlayHost = CreateFrame("Frame", "AyijeCDM_AnchorOverlays", UIParent)
overlayHost:SetAllPoints(UIParent)
overlayHost:SetFrameStrata("TOOLTIP")
overlayHost:Hide()

local function BuildGrid()
    local width, height = UIParent:GetSize()
    local physicalWidth, physicalHeight = GetPhysicalScreenSize()
    if not physicalWidth or physicalWidth == 0 or not physicalHeight or physicalHeight == 0 then return end

    local pixel = width / physicalWidth
    local step = math_floor(physicalWidth / GRID_SIZE + 0.5) * pixel
    local lineWidth = GRID_LINE_WIDTH * pixel
    gridCenterX = math_floor(physicalWidth * 0.5 + 0.5) * pixel
    gridCenterY = math_floor(physicalHeight * 0.5 + 0.5) * pixel
    local index = 0

    local function AddLine(isCenter)
        index = index + 1
        local line = grid.lines[index]
        if not line then
            line = grid:CreateTexture(nil, "BACKGROUND")
            grid.lines[index] = line
        end
        if isCenter then
            line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], GRID_CENTER_ALPHA)
            line:SetDrawLayer("BACKGROUND", 1)
        else
            line:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
            line:SetDrawLayer("BACKGROUND", 0)
        end
        line:ClearAllPoints()
        line:Show()
        return line
    end

    local function PlaceVertical(x, isCenter)
        local line = AddLine(isCenter)
        local thickness = isCenter and lineWidth * 2 or lineWidth
        local left = isCenter and x - lineWidth or x
        line:SetPoint("TOPLEFT", grid, "TOPLEFT", left, 0)
        line:SetPoint("BOTTOMRIGHT", grid, "BOTTOMLEFT", left + thickness, 0)
    end

    local function PlaceHorizontal(y, isCenter)
        local line = AddLine(isCenter)
        local thickness = isCenter and lineWidth * 2 or lineWidth
        local top = isCenter and y - lineWidth or y
        line:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -top)
        line:SetPoint("BOTTOMRIGHT", grid, "TOPRIGHT", 0, -(top + thickness))
    end

    for i = -math_ceil(gridCenterX / step), math_ceil((width - gridCenterX) / step) do
        PlaceVertical(gridCenterX + i * step, i == 0)
    end

    for i = -math_ceil(gridCenterY / step), math_ceil((height - gridCenterY) / step) do
        PlaceHorizontal(gridCenterY + i * step, i == 0)
    end

    for i = index + 1, #grid.lines do
        grid.lines[i]:Hide()
    end
end

local function RefreshActiveGrid()
    if AnchorMode.active then
        BuildGrid()
    end
end

CDM:RegisterEvent("UI_SCALE_CHANGED", RefreshActiveGrid)
CDM:RegisterEvent("DISPLAY_SIZE_CHANGED", RefreshActiveGrid)

local function PrintMessage(message)
    if CDM.Print then
        CDM:Print(message)
    else
        print("Ayije_CDM: " .. message)
    end
end

local function EnsureViewerPosition(viewerName, defaults)
    local positions = CDM.db.editModePositions
    if not positions then
        positions = {}
        CDM.db.editModePositions = positions
    end
    local viewerPositions = positions[viewerName]
    if not viewerPositions then
        viewerPositions = {}
        positions[viewerName] = viewerPositions
    end
    if not viewerPositions.Default then
        viewerPositions.Default = {
            point = defaults.point,
            x = defaults.x,
            y = defaults.y,
        }
    end
    return viewerPositions.Default
end

local GetFrameBounds
local buffBarFrameScratch = {}

local function GetConfiguredBuffBarFrames(groupIndex)
    for i = #buffBarFrameScratch, 1, -1 do
        buffBarFrameScratch[i] = nil
    end
    if not (CDM.GetBuffBarEntries and CDM.BuffBarTimers_GetBar) then
        return buffBarFrameScratch
    end
    local entries = CDM.GetBuffBarEntries()
    for i, entry in ipairs(entries) do
        if entry.groupIndex == groupIndex then
            local frame = CDM.BuffBarTimers_GetBar(i)
            if frame then
                buffBarFrameScratch[#buffBarFrameScratch + 1] = frame
            end
        end
    end
    return buffBarFrameScratch
end

local function AddEntry(key, label, frame, getOffsets, setOffsets, apply, getBounds, hasActiveFrames)
    if not frame then return end
    AnchorMode.entries[#AnchorMode.entries + 1] = {
        key = key,
        label = label,
        frame = frame,
        getOffsets = getOffsets,
        setOffsets = setOffsets,
        apply = apply,
        getBounds = getBounds,
        hasActiveFrames = hasActiveFrames,
    }
end

local function AddViewerEntries()
    local containers = CDM.anchorContainers
    if not containers then return end

    local essential = containers[VIEWERS.ESSENTIAL]
    local essentialFrames = CDM.ungroupedAnchorFrames and CDM.ungroupedAnchorFrames[VIEWERS.ESSENTIAL]
    AddEntry("essential", L["Essential Cooldowns"], essential,
        function()
            local p = EnsureViewerPosition(VIEWERS.ESSENTIAL, { point = "CENTER", x = 0, y = -201 })
            return p.x or 0, p.y or -201
        end,
        function(x, y)
            local p = EnsureViewerPosition(VIEWERS.ESSENTIAL, { point = "CENTER", x = 0, y = -201 })
            p.x, p.y = x, y
        end,
        function()
            CDM:UpdateEssentialContainerPosition()
            if CDM.UpdateResources then CDM:UpdateResources() end
            if CDM.UpdatePlayerCastBar then CDM:UpdatePlayerCastBar() end
            local p = EnsureViewerPosition(VIEWERS.ESSENTIAL, { point = "CENTER", x = 0, y = -201 })
            CDM:NotifyPositionSliderUpdate("essential", p.x, p.y, true)
        end,
        function() return GetFrameBounds(essentialFrames) end,
        function() return GetFrameBounds(essentialFrames) ~= nil end)

    local utility = containers[VIEWERS.UTILITY]
    local utilityFrames = CDM.ungroupedAnchorFrames and CDM.ungroupedAnchorFrames[VIEWERS.UTILITY]
    AddEntry("utility", L["Utility Cooldowns"], utility,
        function() return CDM.db.utilityXOffset or 0, CDM.db.utilityYOffset or 0 end,
        function(x, y) CDM.db.utilityXOffset, CDM.db.utilityYOffset = x, y end,
        function() CDM:UpdateUtilityContainerPosition() end,
        function() return GetFrameBounds(utilityFrames) end,
        function() return GetFrameBounds(utilityFrames) ~= nil end)

    if not CDM.db.moveBuffsDown then
        local buff = containers[VIEWERS.BUFF]
        local buffFrames = CDM.ungroupedAnchorFrames and CDM.ungroupedAnchorFrames[VIEWERS.BUFF]
        AddEntry("buff", L["Buff Icons"], buff,
            function()
                local p = EnsureViewerPosition(VIEWERS.BUFF, { point = "CENTER", x = 0, y = -149 })
                return p.x or 0, p.y or -149
            end,
            function(x, y)
                local p = EnsureViewerPosition(VIEWERS.BUFF, { point = "CENTER", x = 0, y = -149 })
                p.x, p.y = x, y
            end,
            function()
                CDM:UpdateBuffContainerPosition()
                local p = EnsureViewerPosition(VIEWERS.BUFF, { point = "CENTER", x = 0, y = -149 })
                CDM:NotifyPositionSliderUpdate("buff", p.x, p.y, true)
            end,
            function() return GetFrameBounds(buffFrames) end,
            function() return GetFrameBounds(buffFrames) ~= nil end)
    end

    local buffBar = containers[VIEWERS.BUFF_BAR]
    AddEntry("buff_bar", L["Buff Bars"], buffBar,
        function()
            local p = EnsureViewerPosition(VIEWERS.BUFF_BAR, { point = "CENTER", x = 0, y = -324 })
            return p.x or 0, p.y or -324
        end,
        function(x, y)
            local p = EnsureViewerPosition(VIEWERS.BUFF_BAR, { point = "CENTER", x = 0, y = -324 })
            p.x, p.y = x, y
        end,
        function()
            CDM:UpdateBuffBarContainerPosition()
            local p = EnsureViewerPosition(VIEWERS.BUFF_BAR, { point = "CENTER", x = 0, y = -324 })
            CDM:NotifyPositionSliderUpdate("buffBar", p.x, p.y, true)
        end,
        function() return GetFrameBounds(GetConfiguredBuffBarFrames(nil)) end,
        function()
            local bars = CDM.BUFFBAR and CDM.BUFFBAR.GetUngrouped and CDM.BUFFBAR.GetUngrouped()
            return type(bars) == "table" and #bars > 0
        end)
end

local function AddResourceEntries()
    if CDM.db.resourcesEnabled == false or not CDM.resourceBars then return end
    for powerType, bar in pairs(CDM.resourceBars) do
        local anchorTo = bar and bar.barKey and CDM:GetBarSetting(bar.barKey, "anchorTo")
        local independentlyAnchored = not anchorTo or anchorTo == "screen"
            or anchorTo == "playerFrame" or anchorTo == "essential"
        if bar and bar.barKey and bar:IsShown() and independentlyAnchored then
            local barKey = bar.barKey
            local capturedBarKey = barKey
            AddEntry("resource_" .. barKey, L[barKey], bar,
                function()
                    return CDM:GetBarSetting(capturedBarKey, "offsetX") or 0,
                        CDM:GetBarSetting(capturedBarKey, "offsetY") or 0
                end,
                function(x, y)
                    CDM:SetBarSetting(capturedBarKey, "offsetX", x)
                    CDM:SetBarSetting(capturedBarKey, "offsetY", y)
                end,
                function() CDM:UpdateResources() end)
        end
    end
end

local function AddCastBarEntry()
    local frame = CDM.castBarFrame
    if CDM.db.castBarEnabled == false or not frame then return end
    local anchorFrame = CDM.castBarContainer or frame
    AddEntry("cast_bar", L["Player Cast Bar"], anchorFrame,
        function() return CDM.db.castBarOffsetX or 0, CDM.db.castBarOffsetY or 0 end,
        function(x, y) CDM.db.castBarOffsetX, CDM.db.castBarOffsetY = x, y end,
        function() CDM:UpdatePlayerCastBar() end)
end

GetFrameBounds = function(frames, extraFrames)
    local left, right, top, bottom
    local function Include(frame)
        if not (frame and frame:IsShown()) then return end
        local frameLeft, frameRight = frame:GetLeft(), frame:GetRight()
        local frameTop, frameBottom = frame:GetTop(), frame:GetBottom()
        if not (frameLeft and frameRight and frameTop and frameBottom) then return end
        left = left and math.min(left, frameLeft) or frameLeft
        right = right and math.max(right, frameRight) or frameRight
        top = top and math.max(top, frameTop) or frameTop
        bottom = bottom and math.min(bottom, frameBottom) or frameBottom
    end
    if frames then
        for _, frame in pairs(frames) do Include(frame) end
    end
    if extraFrames then
        for _, frame in pairs(extraFrames) do Include(frame) end
    end
    return left, right, top, bottom
end

local function AddGroupEntries(prefix, labelPrefix, containers, sets, apply, frameRegistry, includePlaceholders)
    local groups = sets and sets.groups
    if not containers or not groups then return end
    for index, group in ipairs(groups) do
        local frame = containers[index]
        if frame then
            local capturedGroup = group
            local capturedIndex = index
            local label = capturedGroup.name or (labelPrefix .. " " .. index)
            AddEntry(prefix .. index, label, frame,
                function() return capturedGroup.offsetX or 0, capturedGroup.offsetY or 0 end,
                function(x, y) capturedGroup.offsetX, capturedGroup.offsetY = x, y end,
                apply,
                function()
                    local extraFrames
                    if includePlaceholders and CDM.BuffGroupPlaceholders.GetGroupFrames then
                        extraFrames = CDM.BuffGroupPlaceholders.GetGroupFrames(capturedIndex)
                    end
                    return GetFrameBounds(frameRegistry and frameRegistry[capturedIndex], extraFrames)
                end,
                function()
                    return GetFrameBounds(frameRegistry and frameRegistry[capturedIndex]) ~= nil
                end)
        end
    end
end

local function AddBuffBarGroupEntries()
    local groups = CDM.buffBarGroupSets and CDM.buffBarGroupSets.groups
    local containers = CDM.buffBarGroupContainers
    if not containers or not groups then return end
    for index, group in ipairs(groups) do
        local frame = containers[index]
        if frame then
            local capturedGroup = group
            local capturedIndex = index
            AddEntry("buff_bar_group_" .. index,
                capturedGroup.name or (L["Buff Bar Group"] .. " " .. index), frame,
                function() return capturedGroup.offsetX or 0, capturedGroup.offsetY or 0 end,
                function(x, y) capturedGroup.offsetX, capturedGroup.offsetY = x, y end,
                function() CDM:Refresh("BUFF_DATA") end,
                function() return GetFrameBounds(GetConfiguredBuffBarFrames(capturedIndex)) end,
                function()
                    return type(capturedGroup.bars) == "table" and #capturedGroup.bars > 0
                end)
        end
    end
end

local function BuildEntries()
    for i = #AnchorMode.entries, 1, -1 do
        AnchorMode.entries[i] = nil
    end

    AddViewerEntries()
    AddResourceEntries()
    AddCastBarEntry()
    AddGroupEntries("cooldown_group_", L["Cooldown Group"], CDM.cooldownGroupContainers, CDM.CooldownGroupSets,
        function() CDM:UpdateAllCooldownGroupContainers() end, CDM.cooldownGroupFrames)
    AddGroupEntries("buff_group_", L["Buff Group"], CDM.buffGroupContainers, CDM.BuffGroupSets,
        function() CDM:UpdateAllBuffGroupContainers() end, CDM.buffGroupFrames, true)
    AddBuffBarGroupEntries()
end

local dragging
local pendingCombatRefresh = false
local UpdateNudgePanel
local dragFrame = CreateFrame("Frame")
dragFrame:Hide()

local function UpdateOverlayBounds(overlay)
    local entry = overlay and overlay.entry
    if not entry then return end
    if entry.hasActiveFrames and not entry.hasActiveFrames() then
        overlay:Hide()
        return
    end
    overlay:Show()
    overlay:ClearAllPoints()
    if entry.getBounds then
        local left, right, top, bottom = entry.getBounds()
        if left and right and top and bottom then
            overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
            overlay:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
            return
        end
    end
    overlay:SetAllPoints(entry.frame)
end

local anchorRefreshFrame = CreateFrame("Frame")
local anchorRefreshElapsed = 0
anchorRefreshFrame:Hide()
anchorRefreshFrame:SetScript("OnUpdate", function(_, elapsed)
    anchorRefreshElapsed = anchorRefreshElapsed + elapsed
    if anchorRefreshElapsed < 0.1 then return end
    anchorRefreshElapsed = 0
    for _, overlay in ipairs(AnchorMode.overlays) do
        UpdateOverlayBounds(overlay)
    end
end)

local function UpdateDrag()
    if not dragging then return end
    local frame = dragging.entry.frame
    local scale = frame:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX, cursorY = cursorX / scale, cursorY / scale
    local dx = math_floor(cursorX - dragging.cursorX + 0.5)
    local dy = math_floor(cursorY - dragging.cursorY + 0.5)

    if not IsShiftKeyDown() then
        local centerX = dragging.centerX + dx * dragging.scaleRatio
        local centerY = dragging.centerY + dy * dragging.scaleRatio
        if math_abs(centerX - gridCenterX) < SNAP_RANGE then
            dx = dx + math_floor((gridCenterX - centerX) / dragging.scaleRatio + 0.5)
        end
        if math_abs(centerY - gridCenterY) < SNAP_RANGE then
            dy = dy + math_floor((gridCenterY - centerY) / dragging.scaleRatio + 0.5)
        end
    end

    dragging.dx, dragging.dy = dx, dy
    frame:ClearAllPoints()
    frame:SetPoint(dragging.point, dragging.relativeTo, dragging.relativePoint,
        dragging.originX + dx, dragging.originY + dy)
    UpdateOverlayBounds(dragging.overlay)
end

dragFrame:SetScript("OnUpdate", UpdateDrag)

local function StartDrag(overlay)
    if not AnchorMode.active or InCombatLockdown() then return end
    local entry = overlay.entry
    local frame = entry.frame
    if frame:GetNumPoints() ~= 1 then return end

    local point, relativeTo, relativePoint, originX, originY = frame:GetPoint(1)
    local scale = frame:GetEffectiveScale()
    local scaleRatio = scale / UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    local offsetX, offsetY = entry.getOffsets()
    local left, bottom, width, height = frame:GetRect()
    dragging = {
        entry = entry,
        overlay = overlay,
        point = point,
        relativeTo = relativeTo or UIParent,
        relativePoint = relativePoint,
        originX = originX or 0,
        originY = originY or 0,
        cursorX = cursorX / scale,
        cursorY = cursorY / scale,
        centerX = left and (left + width / 2) * scaleRatio or 0,
        centerY = bottom and (bottom + height / 2) * scaleRatio or 0,
        scaleRatio = scaleRatio,
        offsetX = offsetX,
        offsetY = offsetY,
        dx = 0,
        dy = 0,
    }
    dragFrame:Show()
end

local function ApplyEntryOffsets(entry, x, y, runApply)
    if not entry then return end
    x = math_floor((tonumber(x) or 0) + 0.5)
    y = math_floor((tonumber(y) or 0) + 0.5)
    entry.setOffsets(x, y)
    if runApply then
        entry.apply()
    else
        pendingCombatRefresh = true
    end
    NotifyConfigPosition(entry, x, y)
    for _, overlay in ipairs(AnchorMode.overlays) do
        if overlay.entry == entry then
            UpdateOverlayBounds(overlay)
            break
        end
    end
    if UpdateNudgePanel then UpdateNudgePanel() end
end

local function CommitDrag(runApply)
    if not dragging then return end
    dragFrame:Hide()
    local drag = dragging
    dragging = nil
    ApplyEntryOffsets(drag.entry, drag.offsetX + drag.dx, drag.offsetY + drag.dy, runApply)
    UpdateOverlayBounds(drag.overlay)
end

local function StopDrag()
    CommitDrag(not InCombatLockdown())
end

local nudgePanel

local function RefreshOverlaySelection()
    for _, overlay in ipairs(AnchorMode.overlays) do
        local selected = AnchorMode.selectedEntry == overlay.entry
        if selected or overlay.isHovered then
            overlay:SetBackdropBorderColor(1, 1, 1, 1)
        else
            overlay:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
        end
    end
end

local function SelectEntry(entry)
    AnchorMode.selectedEntry = entry
    RefreshOverlaySelection()
    if UpdateNudgePanel then UpdateNudgePanel() end
end

local function NudgeSelected(dx, dy)
    local entry = AnchorMode.selectedEntry
    if not entry or InCombatLockdown() then return end
    local x, y = entry.getOffsets()
    local step = IsShiftKeyDown() and 10 or 1
    ApplyEntryOffsets(entry, (x or 0) + dx * step, (y or 0) + dy * step, true)
end

local keyboardHandler = CreateFrame("Frame", "AyijeCDM_AnchorKeyboardHandler", UIParent)
keyboardHandler:SetFrameStrata("TOOLTIP")
keyboardHandler:SetFrameLevel(10000)
keyboardHandler:EnableKeyboard(true)
keyboardHandler:SetPropagateKeyboardInput(true)
keyboardHandler:Hide()

local KEYBOARD_NUDGES = {
    LEFT = { -1, 0 },
    UP = { 0, 1 },
    DOWN = { 0, -1 },
    RIGHT = { 1, 0 },
}

keyboardHandler:SetScript("OnKeyDown", function(self, key)
    if GetCurrentKeyBoardFocus() then
        self:SetPropagateKeyboardInput(true)
        return
    end

    local delta = KEYBOARD_NUDGES[key]
    if delta and AnchorMode.selectedEntry then
        self:SetPropagateKeyboardInput(false)
        NudgeSelected(delta[1], delta[2])
        return
    end

    self:SetPropagateKeyboardInput(true)
end)

local function CreateNudgePanel()
    if nudgePanel then return nudgePanel end

    local panel = CreateFrame("Frame", "AyijeCDM_AnchorNudgeTool", UIParent, "BackdropTemplate")
    panel:SetSize(180, 126)
    panel:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
    panel:SetFrameStrata("TOOLTIP")
    panel:SetFrameLevel(100)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(0.06, 0.06, 0.06, 0.94)
    panel:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    local selected = panel:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
    selected:SetPoint("TOP", 0, -7)
    selected:SetFontObject("AyijeCDM_Font18")
    selected:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    panel.selected = selected

    local function CreateOffsetBox(labelText, y)
        local label = panel:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
        label:SetPoint("TOPLEFT", 14, y)
        label:SetText(labelText)

        local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        box:SetSize(76, 22)
        box:SetPoint("TOPRIGHT", -14, y + 4)
        box:SetAutoFocus(false)
        box:SetJustifyH("CENTER")
        box:SetFontObject("AyijeCDM_Font14")
        return box
    end

    panel.xBox = CreateOffsetBox(L["X Offset"], -36)
    panel.yBox = CreateOffsetBox(L["Y Offset"], -64)

    local function CommitBoxes()
        if panel.updating or panel.committing then return end
        local entry = AnchorMode.selectedEntry
        local x = tonumber(panel.xBox:GetText())
        local y = tonumber(panel.yBox:GetText())
        if entry and x and y and not InCombatLockdown() then
            ApplyEntryOffsets(entry, x, y, true)
        elseif UpdateNudgePanel then
            UpdateNudgePanel()
        end
    end

    local function OnEnterPressed(self)
        CommitBoxes()
        panel.committing = true
        self:ClearFocus()
        panel.committing = false
    end

    local function OnEscapePressed(self)
        if UpdateNudgePanel then UpdateNudgePanel() end
        self:ClearFocus()
    end

    for _, box in ipairs({ panel.xBox, panel.yBox }) do
        box:SetScript("OnEnterPressed", OnEnterPressed)
        box:SetScript("OnEscapePressed", OnEscapePressed)
        box:SetScript("OnEditFocusLost", CommitBoxes)
    end

    local arrows = {
        { rotation = -90, dx = -1, dy = 0 },
        { rotation = 180, dx = 0, dy = 1 },
        { rotation = 0, dx = 0, dy = -1 },
        { rotation = 90, dx = 1, dy = 0 },
    }
    panel.arrows = {}
    local buttonSize, iconSize, gap = 30, 25, 7
    local rowWidth = #arrows * buttonSize + (#arrows - 1) * gap
    for index, arrow in ipairs(arrows) do
        local dx, dy = arrow.dx, arrow.dy
        local button = CreateFrame("Button", nil, panel)
        button:SetSize(buttonSize, buttonSize)
        button:SetPoint("BOTTOMLEFT", panel, "BOTTOM", -rowWidth / 2 + (index - 1) * (buttonSize + gap), 5)
        local icon = button:CreateTexture(nil, "OVERLAY", nil, 1)
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("CENTER")
        icon:SetTexture(ARROW_TEXTURE)
        icon:SetRotation(math_rad(arrow.rotation))
        icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
        button.icon = icon
        button:SetScript("OnEnter", function() icon:SetVertexColor(1, 1, 1, 1) end)
        button:SetScript("OnLeave", function() icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1) end)
        button:SetScript("OnClick", function() NudgeSelected(dx, dy) end)
        panel.arrows[index] = button
    end

    panel:Hide()
    nudgePanel = panel
    return panel
end

UpdateNudgePanel = function()
    local panel = nudgePanel
    if not panel then return end
    local entry = AnchorMode.selectedEntry
    panel.updating = true
    if entry then
        local x, y = entry.getOffsets()
        panel.selected:SetText(entry.label)
        panel.xBox:SetText(math_floor((x or 0) + 0.5))
        panel.yBox:SetText(math_floor((y or 0) + 0.5))
        panel.xBox:Enable()
        panel.yBox:Enable()
        for _, button in ipairs(panel.arrows) do
            button:Enable()
            button:SetAlpha(1)
        end
    else
        panel.selected:SetText(L["Select Anchor"])
        panel.xBox:SetText("--")
        panel.yBox:SetText("--")
        panel.xBox:Disable()
        panel.yBox:Disable()
        for _, button in ipairs(panel.arrows) do
            button:Disable()
            button:SetAlpha(0.35)
        end
    end
    panel.updating = false
end

local function CreateOverlay(entry)
    local overlay = CreateFrame("Frame", nil, overlayHost, "BackdropTemplate")
    overlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    overlay:SetBackdropColor(OVERLAY_COLOR[1], OVERLAY_COLOR[2], OVERLAY_COLOR[3], OVERLAY_COLOR[4])
    overlay:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
    overlay.entry = entry
    overlay.isHovered = false
    UpdateOverlayBounds(overlay)
    overlay:SetFrameLevel(overlayHost:GetFrameLevel() + 1)
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    local label = overlay:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
    label:SetPoint("CENTER")
    label:SetText(entry.label)
    label:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    label:SetShadowOffset(1, -1)

    overlay:SetScript("OnDragStart", StartDrag)
    overlay:SetScript("OnDragStop", StopDrag)
    overlay:SetScript("OnEnter", function(self)
        self.isHovered = true
        self:SetBackdropBorderColor(1, 1, 1, 1)
    end)
    overlay:SetScript("OnLeave", function(self)
        self.isHovered = false
        if AnchorMode.selectedEntry == self.entry then
            self:SetBackdropBorderColor(1, 1, 1, 1)
        else
            self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
        end
    end)
    overlay:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then SelectEntry(self.entry) end
    end)
    return overlay
end

local function ClearOverlays()
    for _, overlay in ipairs(AnchorMode.overlays) do
        overlay:Hide()
        overlay:SetParent(nil)
    end
    for i = #AnchorMode.overlays, 1, -1 do
        AnchorMode.overlays[i] = nil
    end
end

function AnchorMode:Enter(button)
    if self.active then return end
    if InCombatLockdown() then
        PrintMessage(L["Cannot unlock anchors during combat."])
        return
    end

    self.active = true
    self.button = button
    if CDM.SetAnchorModeActive then
        CDM:SetAnchorModeActive(true)
    end
    BuildEntries()
    BuildGrid()
    for _, entry in ipairs(self.entries) do
        self.overlays[#self.overlays + 1] = CreateOverlay(entry)
    end
    self.selectedEntry = nil
    local panel = CreateNudgePanel()
    UpdateNudgePanel()
    panel:Show()
    keyboardHandler:SetPropagateKeyboardInput(true)
    keyboardHandler:Show()
    grid:Show()
    overlayHost:Show()
    anchorRefreshElapsed = 0
    anchorRefreshFrame:Show()
    if button then button:LockHighlight() end
end

function AnchorMode:Exit()
    if not self.active then return end
    self.active = false
    if dragging then
        CommitDrag(not InCombatLockdown())
    else
        dragFrame:Hide()
    end
    grid:Hide()
    overlayHost:Hide()
    anchorRefreshFrame:Hide()
    keyboardHandler:Hide()
    keyboardHandler:SetPropagateKeyboardInput(true)
    if nudgePanel then nudgePanel:Hide() end
    self.selectedEntry = nil
    ClearOverlays()
    if CDM.SetAnchorModeActive then
        CDM:SetAnchorModeActive(false)
    end
    if self.button then self.button:UnlockHighlight() end
    self.button = nil
end

function ns.ToggleAnchorMode(button)
    if AnchorMode.active then
        AnchorMode:Exit()
    else
        AnchorMode:Enter(button)
    end
end

function ns.IsAnchorModeActive()
    return AnchorMode.active
end

function ns.CloseAnchorMode()
    AnchorMode:Exit()
end

CDM:RegisterCombatStateHandler(function(isInCombat)
    if isInCombat then
        if AnchorMode.active then
            PrintMessage(L["Anchors closed because combat started."])
            AnchorMode:Exit()
        end
    elseif pendingCombatRefresh then
        pendingCombatRefresh = false
        CDM:Refresh("LAYOUT")
        CDM:Refresh("RESOURCES")
        CDM:Refresh("BUFF_DATA")
    end
end)
