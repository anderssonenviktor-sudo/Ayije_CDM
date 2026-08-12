local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
local pairs, ipairs = pairs, ipairs
local math_huge = math.huge
local CreateFrame = CreateFrame
local Pixel = CDM.Pixel

local OVERLAY_PADDING = 3
local OVERLAY_COLORS = {
    cd   = { bg = { 0.05, 0.20, 0.45, 0.35 }, border = { 0.25, 0.60, 1.00, 0.90 } },
    buff = { bg = { 0.45, 0.22, 0.05, 0.35 }, border = { 1.00, 0.60, 0.15, 0.90 } },
    pi   = { bg = { 0.45, 0.42, 0.05, 0.35 }, border = { 1.00, 0.92, 0.20, 0.90 } },
}

local overlayPool = {}
local activeBuffOverlays = {}
local activeCdOverlays = {}
local activeUngroupedCdOverlays = {}
local activeSingleOverlays = {}
local configWindowActive = false

local function CreateOverlay()
    local overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetFrameStrata("BACKGROUND")
    overlay:EnableMouse(false)

    local bg = Pixel.CreateSolidTexture(overlay, "BACKGROUND")
    bg:SetAllPoints()
    overlay.bg = bg

    local function CreateBorderLine()
        return Pixel.CreateSolidTexture(overlay, "BORDER")
    end

    local top = CreateBorderLine()
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")

    local bottom = CreateBorderLine()
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")

    local left = CreateBorderLine()
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")

    local right = CreateBorderLine()
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")

    overlay.borderTop = top
    overlay.borderBottom = bottom
    overlay.borderLeft = left
    overlay.borderRight = right

    overlay:Hide()
    return overlay
end

local function AcquireOverlay(kind)
    local overlay = table.remove(overlayPool)
    if not overlay then
        overlay = CreateOverlay()
    end
    local colors = OVERLAY_COLORS[kind] or OVERLAY_COLORS.cd
    local bg, border = colors.bg, colors.border
    overlay.bg:SetVertexColor(bg[1], bg[2], bg[3], bg[4])
    overlay.borderTop:SetVertexColor(border[1], border[2], border[3], border[4])
    overlay.borderBottom:SetVertexColor(border[1], border[2], border[3], border[4])
    overlay.borderLeft:SetVertexColor(border[1], border[2], border[3], border[4])
    overlay.borderRight:SetVertexColor(border[1], border[2], border[3], border[4])
    return overlay
end

local function ReleaseOverlay(overlay)
    overlay:Hide()
    overlay:ClearAllPoints()
    overlayPool[#overlayPool + 1] = overlay
end

local function IsBlizzardPanelVisible()
    return CooldownViewerSettings and CooldownViewerSettings:IsVisible() or false
end

local function ShouldShowOverlays()
    return configWindowActive or IsBlizzardPanelVisible()
end

local function ComputeRectForFrames(frames)
    local left, right, top, bottom = math_huge, -math_huge, -math_huge, math_huge
    local count = 0
    for _, frame in ipairs(frames) do
        if frame:IsShown() then
            local fl = frame:GetLeft()
            local fr = frame:GetRight()
            local ft = frame:GetTop()
            local fb = frame:GetBottom()
            if fl and fr and ft and fb then
                if fl < left then left = fl end
                if fr > right then right = fr end
                if ft > top then top = ft end
                if fb < bottom then bottom = fb end
                count = count + 1
            end
        end
    end
    if count == 0 then return nil end
    return left, right, top, bottom
end

local function ApplyRect(overlay, left, right, top, bottom, show)
    overlay:ClearAllPoints()
    local pad = OVERLAY_PADDING
    local Snap = Pixel.Snap
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", Snap(left - pad),  Snap(bottom - pad))
    overlay:SetPoint("TOPRIGHT",   UIParent, "BOTTOMLEFT", Snap(right + pad), Snap(top + pad))

    local px = Pixel.GetSize()
    overlay.borderTop:SetHeight(px)
    overlay.borderBottom:SetHeight(px)
    overlay.borderLeft:SetWidth(px)
    overlay.borderRight:SetWidth(px)

    overlay:SetShown(show)
end

local function ReleaseActiveOverlays(activeOverlays)
    for key, overlay in pairs(activeOverlays) do
        ReleaseOverlay(overlay)
        activeOverlays[key] = nil
    end
end

local function UpdateGroupOverlays(activeOverlays, groupFramesMap, show, kind)
    ReleaseActiveOverlays(activeOverlays)

    if not show or not groupFramesMap then return end

    for groupIdx, groupFrames in pairs(groupFramesMap) do
        if groupFrames and #groupFrames > 0 then
            local l, r, t, b = ComputeRectForFrames(groupFrames)
            if l then
                local overlay = AcquireOverlay(kind)
                activeOverlays[groupIdx] = overlay
                ApplyRect(overlay, l, r, t, b, show)
            end
        end
    end
end

function CDM:UpdateBuffGroupOverlays(tempBuffGroups, tempBuff)
    local show = ShouldShowOverlays()
    UpdateGroupOverlays(activeBuffOverlays, tempBuffGroups, show, "buff")

    if show and tempBuff and #tempBuff > 0 then
        local l, r, t, b = ComputeRectForFrames(tempBuff)
        if l then
            local overlay = AcquireOverlay("buff")
            activeBuffOverlays["__ungrouped"] = overlay
            ApplyRect(overlay, l, r, t, b, show)
        end
    end
end

function CDM:UpdateCooldownGroupOverlays(tempCdGroups)
    UpdateGroupOverlays(activeCdOverlays, tempCdGroups, ShouldShowOverlays(), "cd")
end

-- One overlay per viewer (essential/utility) covering the icons that are not
-- assigned to any cooldown group.
function CDM:UpdateUngroupedCooldownOverlay(viewerKey, frames)
    local overlay = activeUngroupedCdOverlays[viewerKey]
    if overlay then
        ReleaseOverlay(overlay)
        activeUngroupedCdOverlays[viewerKey] = nil
    end

    if not ShouldShowOverlays() or not frames or #frames == 0 then return end

    local l, r, t, b = ComputeRectForFrames(frames)
    if l then
        overlay = AcquireOverlay("cd")
        activeUngroupedCdOverlays[viewerKey] = overlay
        ApplyRect(overlay, l, r, t, b, true)
    end
end

-- One overlay around a single standalone frame (e.g. the Power Infusion icon),
-- keyed so the caller can update or clear just its own.
function CDM:UpdateSingleFrameOverlay(key, frame, kind)
    local overlay = activeSingleOverlays[key]
    if overlay then
        ReleaseOverlay(overlay)
        activeSingleOverlays[key] = nil
    end

    if not ShouldShowOverlays() or not frame then return end

    local l, r = frame:GetLeft(), frame:GetRight()
    local t, b = frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return end

    overlay = AcquireOverlay(kind or "cd")
    activeSingleOverlays[key] = overlay
    ApplyRect(overlay, l, r, t, b, true)
end

function CDM:RefreshBuffGroupOverlayVisibility()
    local show = ShouldShowOverlays()
    for _, overlay in pairs(activeBuffOverlays) do
        overlay:SetShown(show)
    end
    for _, overlay in pairs(activeCdOverlays) do
        overlay:SetShown(show)
    end
    for _, overlay in pairs(activeUngroupedCdOverlays) do
        overlay:SetShown(show)
    end
    for _, overlay in pairs(activeSingleOverlays) do
        overlay:SetShown(show)
    end
end

-- NOTE: never call viewer:SetIsEditing() (or otherwise run Blizzard's
-- CooldownViewer refresh pipeline) from addon code. Everything it writes
-- (cooldownID, aura caches, the shared totem cache) becomes tainted, and
-- Blizzard's own event handlers then throw secret-value errors in combat.
-- Consequence: while the config is open, only currently active buff
-- icons/bars are visible.
function CDM:SetConfigWindowActive(active)
    active = active and true or false
    if configWindowActive == active then return end
    configWindowActive = active
    self:RefreshBuffGroupOverlayVisibility()
    -- Overlay rects are only computed during a layout pass; force one so
    -- overlays appear/disappear immediately.
    self:Refresh("LAYOUT")
end

local function RegisterBlizzardPanelCallbacks()
    local registry = EventRegistry
    if not (registry and registry.RegisterCallback) then return end
    local owner = {}
    registry:RegisterCallback("CooldownViewerSettings.OnShow", function()
        CDM:RefreshBuffGroupOverlayVisibility()
        CDM:Refresh("LAYOUT")
    end, owner)
    registry:RegisterCallback("CooldownViewerSettings.OnHide", function()
        CDM:RefreshBuffGroupOverlayVisibility()
    end, owner)
end
RegisterBlizzardPanelCallbacks()
