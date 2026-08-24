local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
if not CDM then return end

local ns = CDM._OptionsNS
local L = CDM.L
local VIEWERS = CDM.CONST.VIEWERS

local GetCursorPosition = GetCursorPosition
local InCombatLockdown = InCombatLockdown
local math_floor = math.floor
local pairs = pairs
local ipairs = ipairs

local AnchorMode = {
    active = false,
    entries = {},
    overlays = {},
}

local GRID_STEP = 32
local GRID_COLOR = { 0.50, 0.38, 0.68, 0.45 }
local OVERLAY_COLOR = { 0.08, 0.08, 0.08, 0.72 }
local GOLD = { 1, 0.82, 0, 1 }

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
    local index = 0

    local function AddLine()
        index = index + 1
        local line = grid.lines[index]
        if not line then
            line = grid:CreateTexture(nil, "BACKGROUND")
            grid.lines[index] = line
        end
        line:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
        line:ClearAllPoints()
        line:Show()
        return line
    end

    local x = 0
    while x <= width do
        local line = AddLine()
        line:SetPoint("TOPLEFT", grid, "TOPLEFT", x, 0)
        line:SetPoint("BOTTOMRIGHT", grid, "BOTTOMLEFT", x + 1, 0)
        x = x + GRID_STEP
    end

    local y = 0
    while y <= height do
        local line = AddLine()
        line:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
        line:SetPoint("BOTTOMRIGHT", grid, "TOPRIGHT", 0, -(y + 1))
        y = y + GRID_STEP
    end

    for i = index + 1, #grid.lines do
        grid.lines[i]:Hide()
    end
end

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
            AddEntry("resource_" .. tostring(powerType), L[barKey], bar,
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
    local cursorX, cursorY = GetCursorPosition()
    local offsetX, offsetY = entry.getOffsets()
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
        offsetX = offsetX,
        offsetY = offsetY,
        dx = 0,
        dy = 0,
    }
    dragFrame:Show()
end

local function CommitDrag(runApply)
    if not dragging then return end
    dragFrame:Hide()
    local drag = dragging
    dragging = nil
    drag.entry.setOffsets(drag.offsetX + drag.dx, drag.offsetY + drag.dy)
    if runApply then
        drag.entry.apply()
    else
        pendingCombatRefresh = true
    end
    UpdateOverlayBounds(drag.overlay)
end

local function StopDrag()
    CommitDrag(not InCombatLockdown())
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
        self:SetBackdropBorderColor(1, 1, 1, 1)
    end)
    overlay:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
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
