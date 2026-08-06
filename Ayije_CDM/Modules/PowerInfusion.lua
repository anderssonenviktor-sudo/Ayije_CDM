local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]

local CDM_C = CDM and CDM.CONST or {}
local BORDER = CDM.BORDER
local Pixel = CDM.Pixel
local Snap = Pixel.Snap

local VIEWERS = CDM_C.VIEWERS

local SPELL_ID = 10060 -- Power Infusion
local DEFAULT_SWIPE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"

-- 12.1 AuraContainer/AuraSlot: the engine owns the button, we supply presentation.
local MIN_BUILD = 120100

local isEnabled = false
local needsStyleUpdate = true

local container
local button

-- Per-spec, because buff group indices are per-spec.
CDM.POWER_INFUSION_DEFAULTS = {
    powerInfusionEnabled = false,
    powerInfusionIconWidth = 30,
    powerInfusionIconHeight = 30,
    powerInfusionFontSize = 15,
    powerInfusionFontColor = { r = 1, g = 1, b = 1, a = 1 },
    powerInfusionAnchorGroup = "main", -- "main" = Blizzard's buff icon viewer
    powerInfusionAnchorPoint = "LEFT",
    powerInfusionRelativePoint = "LEFT",
    powerInfusionOffsetX = 0,
    powerInfusionOffsetY = 0,
}

local PI_DEFAULTS = CDM.POWER_INFUSION_DEFAULTS

function CDM.GetPowerInfusionSetting(key, specID)
    specID = specID or (CDM.GetCurrentSpecID and CDM:GetCurrentSpecID()) or nil
    local db = CDM.db
    local perSpec = db and db.powerInfusionSpec
    local specTbl = specID and perSpec and perSpec[specID]
    local v = specTbl and specTbl[key]
    if v ~= nil then return v end
    return PI_DEFAULTS[key]
end

function CDM.SetPowerInfusionSetting(key, value, specID)
    specID = specID or (CDM.GetCurrentSpecID and CDM:GetCurrentSpecID()) or nil
    if not specID then return end
    local db = CDM.db
    if not db then return end
    db.powerInfusionSpec = db.powerInfusionSpec or {}
    local specTbl = db.powerInfusionSpec[specID]
    if not specTbl then
        specTbl = {}
        db.powerInfusionSpec[specID] = specTbl
    end
    specTbl[key] = value
end

local GetPI = CDM.GetPowerInfusionSetting

local function GetSize()
    local w = GetPI("powerInfusionIconWidth")
    local h = GetPI("powerInfusionIconHeight")
    return Snap(w), Snap(h)
end

-- SetDurationText defaults to "11 s"; only a banded NumericRuleFormatter drops
-- the unit letter. Seconds round Up so the text never reads 0 early.
local function BuildDurationFormatter()
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum.NumericRuleFormatRounding) then
        return nil
    end

    local Up = Enum.NumericRuleFormatRounding.Up
    local Down = Enum.NumericRuleFormatRounding.Down
    local formatter = C_StringUtil.CreateNumericRuleFormatter()

    local ok = pcall(formatter.SetBreakpoints, formatter, {
        { threshold = 0, format = "%d", step = 1, rounding = Up },
        { threshold = 60, format = "%dm", step = 1, rounding = Down, components = { { div = 60 } } },
        { threshold = 3600, format = "%dh", step = 1, rounding = Down, components = { { div = 3600 } } },
    })

    if not ok then return nil end
    return formatter
end

local function GetBuffViewer()
    return _G[VIEWERS.BUFF]
end

-- Place via the group's own layout function; hand-rolled maths gets the
-- selfPoint/anchorPoint pairing wrong for non-default grow directions.
local layoutCtx = CDM._LayoutCtx
local PositionFrameAtSlot = layoutCtx.PositionFrameAtSlot
local DeriveSelfPoint = layoutCtx.DeriveSelfPoint

local function PositionInGroup(frame, groupIndex)
    local sets = CDM.BuffGroupSets
    local groupData = sets and sets.groups and sets.groups[groupIndex]
    if not groupData then return false end

    local containers = CDM.buffGroupContainers
    local groupContainer = containers and containers[groupIndex]
    if not groupContainer or not groupContainer:IsShown() then return false end

    local grow = groupData.grow
    if grow ~= "RIGHT" and grow ~= "LEFT" and grow ~= "UP" and grow ~= "DOWN"
        and grow ~= "CENTER_H" and grow ~= "CENTER_V" then
        grow = "RIGHT"
    end

    -- Live icon count, not the configured maximum.
    local counts = CDM.buffGroupLayoutCounts
    local count = counts and counts[groupIndex]
    if not count then count = #(groupData.spells or {}) end
    if count < 1 then count = 0 end

    local iconW = Snap(groupData.iconWidth or 30)
    local iconH = Snap(groupData.iconHeight or 30)
    local spacing = Snap(groupData.spacing or 4)
    local anchorPoint = groupData.anchorPoint or "CENTER"
    local selfPoint = DeriveSelfPoint(anchorPoint, grow)

    local w, h = GetSize()
    frame:SetSize(w, h)
    frame:ClearAllPoints()

    -- Which end of the row to sit on. LEFT/RIGHT are screen-relative, so a
    -- row growing leftward maps them to the opposite slot.
    local side = GetPI("powerInfusionAnchorPoint")
    local atStart
    if grow == "LEFT" then
        atStart = (side == "RIGHT")
    else
        atStart = (side == "LEFT")
    end

    local slot = atStart and -1 or count

    -- Centred grows cannot re-centre around us, so we hang off the chosen end.
    local layoutCount = (grow == "CENTER_H" or grow == "CENTER_V")
        and count
        or (count + 1)

    PositionFrameAtSlot(frame, groupContainer, slot, iconW, iconH, spacing,
        grow, layoutCount, anchorPoint, selfPoint)

    local offsetX = Snap(GetPI("powerInfusionOffsetX"))
    local offsetY = Snap(GetPI("powerInfusionOffsetY"))
    if offsetX ~= 0 or offsetY ~= 0 then
        local p, rel, rp, x, y = frame:GetPoint(1)
        if p then
            frame:ClearAllPoints()
            frame:SetPoint(p, rel, rp, (x or 0) + offsetX, (y or 0) + offsetY)
        end
    end

    return true
end

-- Anchor the button, not the container: a slot-only container collapses to 1px.
local positionDirty = false

local function PlaceFrame(frame)
    if not frame then return end

    local target = GetPI("powerInfusionAnchorGroup")
    if target and target ~= "main" then
        local groupIndex = tonumber(target)
        if groupIndex and PositionInGroup(frame, groupIndex) then
            return
        end
    end

    local viewer = GetBuffViewer()
    if not viewer then return end

    local point = GetPI("powerInfusionAnchorPoint")
    local relativePoint = GetPI("powerInfusionRelativePoint")
    local offsetX = GetPI("powerInfusionOffsetX")
    local offsetY = GetPI("powerInfusionOffsetY")

    local w, h = GetSize()

    frame:ClearAllPoints()
    frame:SetPoint(point, viewer, relativePoint, Snap(offsetX), Snap(offsetY))
    frame:SetSize(w, h)
end

CDM.PlacePowerInfusionFrame = PlaceFrame

local function UpdatePosition()
    if not button then return end
    if InCombatLockdown() then
        -- combatDirtyViewers reanchors the viewer, which never touches us.
        positionDirty = true
        return
    end
    positionDirty = false

    PlaceFrame(button)
end

local function StyleButton()
    if not button then return end

    local styleVersion = CDM.styleCacheVersion or 0
    local fd = CDM.GetFrameData(button)
    if not fd then return end
    if not needsStyleUpdate and fd.cdmPIStyleVersion == styleVersion then
        return
    end

    local w, h = GetSize()
    local zoomAmount = CDM_C.GetEffectiveZoomAmount()
    if fd.cdmPIIcon then
        CDM_C.ApplyIconTexCoord(fd.cdmPIIcon, zoomAmount, w, h)
    end

    -- The engine writes into our FontString, so style that -- not the
    -- Cooldown's own countdown, which SetHideCountdownNumbers suppressed.
    if fd.cdmPIDuration then
        local fontPath = CDM_C.GetBaseFontPath()
        local fontOutline = CDM_C.GetBaseFontOutline()
        local fontSize = GetPI("powerInfusionFontSize")
        local color = GetPI("powerInfusionFontColor")

        local text = fd.cdmPIDuration
        text:SetFont(fontPath, Pixel.FontSize(fontSize), fontOutline)
        text:SetTextColor(color.r, color.g, color.b, color.a or 1)
        text:SetShadowOffset(0, 0)
        text:SetJustifyH("CENTER")
        text:SetJustifyV("MIDDLE")
    end

    local cd = fd.cdmPICooldown
    if cd then
        if cd.SetSwipeTexture then
            local swipeTex = (zoomAmount > 0) and CDM_C.TEX_WHITE8X8 or DEFAULT_SWIPE
            cd:SetSwipeTexture(swipeTex)
        end
        local sc = CDM.db and CDM.db.swipeColor or CDM_C.SWIPE_COLOR
        if cd.SetSwipeColor and sc then
            cd:SetSwipeColor(sc.r, sc.g, sc.b, sc.a)
        end
    end

    local borderActive = CDM.db and CDM.db.borderFile ~= "None"
    if borderActive and BORDER and BORDER.CreateBorder then
        if not fd.cdmPIBorderFrame then
            fd.cdmPIBorderFrame = CreateFrame("Frame", nil, button)
            fd.cdmPIBorderFrame:SetAllPoints(button)
        end
        local currentBorderVersion = CDM.borderStyleVersion or 0
        local borderForce = fd.cdmPIBorderVersion ~= currentBorderVersion
        if not fd.cdmPIBorderInit or borderForce then
            BORDER:CreateBorder(fd.cdmPIBorderFrame, borderForce and { forceUpdate = true } or nil)
            fd.cdmPIBorderInit = true
            fd.cdmPIBorderVersion = currentBorderVersion
        end
    elseif fd.cdmPIBorderFrame then
        fd.cdmPIBorderFrame:Hide()
    end

    fd.cdmPIStyleVersion = styleVersion
    needsStyleUpdate = false
end

-- A talent/spec change makes Blizzard rebuild the buff viewer's frames. Our
-- container survives in this local, but the engine has released the slot behind
-- it, leaving `button` a stale handle -- touching it raises "forbidden object
-- from code tainted by an AddOn". Detect the rebuild and start over.
local function ContainerIsStale()
    if not container then return false end
    if not button then return true end
    local viewer = GetBuffViewer()
    if not viewer then return true end
    return container:GetParent() ~= viewer
end

local function BuildContainer()
    if ContainerIsStale() then
        container:Hide()
        container = nil
        button = nil
        needsStyleUpdate = true
    end

    if container then return true end

    local viewer = GetBuffViewer()
    if not viewer then return false end

    container = CreateFrame("AuraContainer", nil, viewer, "CustomAuraContainerTemplate")
    container:SetSize(1, 1)
    container:SetPoint("CENTER", viewer, "CENTER", 0, 0)
    container:SetUnit("player")

    -- No source filter: PI is cast on us by another player.
    local filter = AuraUtil.CreateFilterString(AuraUtil.AuraFilters.Helpful)

    button = container:AddAuraSlot("powerInfusion", filter, {
        candidateFilters = {
            includeSpellIDs = { [SPELL_ID] = true },
        },
    })
    if not button then
        container:Hide()
        container = nil
        return false
    end

    -- Never SetParent an AuraButton: 'ChangeParent' is a forbidden aspect.
    button:SetMouseMotionEnabled(false)

    local fd = CDM.GetFrameData(button)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints()
    icon:SetTexture(C_Spell.GetSpellTexture(SPELL_ID))
    fd.cdmPIIcon = icon

    -- CooldownFrameTemplate supplies the swipe; a bare Cooldown renders none.
    -- SetDurationCooldown lets the engine drive it off the secret duration.
    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(true) -- the FontString below owns the number
    CDM._cdmCooldowns[cd] = true
    fd.cdmPICooldown = cd

    -- Carrier frame above the swipe, or the number renders behind it.
    local textHost = CreateFrame("Frame", nil, button)
    textHost:SetAllPoints()
    textHost:SetFrameLevel(cd:GetFrameLevel() + 1)
    textHost:EnableMouse(false)
    fd.cdmPITextHost = textHost

    local duration = textHost:CreateFontString(nil, "OVERLAY")
    duration:SetPoint("CENTER")
    fd.cdmPIDuration = duration

    -- An error here aborts the engine's CreateFrameBatch and loses the slot.
    if not pcall(button.SetDurationCooldown, button, cd) then
        cd:Hide()
    end

    local registered = false
    local formatter = BuildDurationFormatter()
    if formatter then
        registered = pcall(button.SetDurationText, button, duration, {
            textFormatter = formatter,
        })
    end
    if not registered then
        button:SetDurationText(duration)
    end

    return true
end

-- Preview icon: the real button's visibility is engine-driven and cannot be
-- forced on, so this stand-in shows while a settings panel is open.
local previewFrame

local previewConfigActive = false

local function IsPreviewActive()
    local panel = _G.CooldownViewerSettings
    if panel and panel:IsVisible() then
        return true
    end
    return previewConfigActive
end

hooksecurefunc(CDM, "SetConfigWindowActive", function(_, active)
    previewConfigActive = active and true or false
    if CDM.UpdatePowerInfusionPreview then
        CDM.UpdatePowerInfusionPreview()
    end
end)

local function EnsurePreview()
    if previewFrame then return previewFrame end

    local viewer = GetBuffViewer()
    if not viewer then return nil end

    previewFrame = CreateFrame("Frame", "Ayije_CDM_PowerInfusionPreview", viewer)
    previewFrame:Hide()
    -- Sit below the real button so it covers us; its IsShown() is a secret
    -- boolean and cannot be tested. pcall guards the read for the same reason.
    if button and button.GetFrameLevel then
        pcall(function()
            local lvl = button:GetFrameLevel()
            if lvl and lvl > 1 then
                previewFrame:SetFrameLevel(lvl - 1)
            end
        end)
    end

    local icon = previewFrame:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints()
    icon:SetTexture(C_Spell.GetSpellTexture(SPELL_ID))
    previewFrame.Icon = icon

    local cd = CreateFrame("Cooldown", nil, previewFrame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(true)
    CDM._cdmCooldowns[cd] = true
    previewFrame.Cooldown = cd

    local textHost = CreateFrame("Frame", nil, previewFrame)
    textHost:SetAllPoints()
    textHost:SetFrameLevel(cd:GetFrameLevel() + 1)
    textHost:EnableMouse(false)

    local text = textHost:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    previewFrame.Duration = text

    return previewFrame
end

local function StylePreview()
    local f = previewFrame
    if not f then return end

    local w, h = GetSize()
    f:SetSize(w, h)

    local zoomAmount = CDM_C.GetEffectiveZoomAmount()
    CDM_C.ApplyIconTexCoord(f.Icon, zoomAmount, w, h)

    local fontPath = CDM_C.GetBaseFontPath()
    local fontOutline = CDM_C.GetBaseFontOutline()
    local fontSize = GetPI("powerInfusionFontSize")
    local color = GetPI("powerInfusionFontColor")
    f.Duration:SetFont(fontPath, Pixel.FontSize(fontSize), fontOutline)
    f.Duration:SetTextColor(color.r, color.g, color.b, color.a or 1)
    f.Duration:SetShadowOffset(0, 0)

    local cd = f.Cooldown
    if cd.SetSwipeTexture then
        cd:SetSwipeTexture((zoomAmount > 0) and CDM_C.TEX_WHITE8X8 or DEFAULT_SWIPE)
    end
    local sc = CDM.db and CDM.db.swipeColor or CDM_C.SWIPE_COLOR
    if cd.SetSwipeColor and sc then
        cd:SetSwipeColor(sc.r, sc.g, sc.b, sc.a)
    end

    local borderActive = CDM.db and CDM.db.borderFile ~= "None"
    if borderActive and BORDER and BORDER.CreateBorder then
        if not f.cdmBorderFrame then
            f.cdmBorderFrame = CreateFrame("Frame", nil, f)
            f.cdmBorderFrame:SetAllPoints(f)
        end
        local currentBorderVersion = CDM.borderStyleVersion or 0
        if not f.cdmBorderInit or f.cdmBorderVersion ~= currentBorderVersion then
            BORDER:CreateBorder(f.cdmBorderFrame,
                (f.cdmBorderVersion ~= currentBorderVersion) and { forceUpdate = true } or nil)
            f.cdmBorderInit = true
            f.cdmBorderVersion = currentBorderVersion
        end
        f.cdmBorderFrame:Show()
    elseif f.cdmBorderFrame then
        f.cdmBorderFrame:Hide()
    end

    local PREVIEW_DURATION = 20
    cd:SetCooldown(GetTime(), PREVIEW_DURATION)
    if not f.cdmPreviewTicker then
        f.cdmPreviewTicker = C_Timer.NewTicker(PREVIEW_DURATION, function()
            if previewFrame and previewFrame:IsShown() and previewFrame.Cooldown then
                previewFrame.Cooldown:SetCooldown(GetTime(), PREVIEW_DURATION)
            end
        end)
    end
end

function CDM.UpdatePowerInfusionPreview()
    local shouldShow = isEnabled and IsPreviewActive()

    if not shouldShow then
        if previewFrame then previewFrame:Hide() end
        return
    end

    if InCombatLockdown() then return end
    if not EnsurePreview() then return end

    StylePreview()
    previewFrame:Show()
    PlaceFrame(previewFrame)
end

local function RegisterPreviewCallbacks()
    local registry = EventRegistry
    if not (registry and registry.RegisterCallback) then return end
    local owner = {}
    registry:RegisterCallback("CooldownViewerSettings.OnShow", function()
        CDM.UpdatePowerInfusionPreview()
    end, owner)
    registry:RegisterCallback("CooldownViewerSettings.OnHide", function()
        CDM.UpdatePowerInfusionPreview()
    end, owner)
end
RegisterPreviewCallbacks()

function CDM.ReconcilePowerInfusion()
    if select(4, GetBuildInfo()) < MIN_BUILD then return end

    local enabled = GetPI("powerInfusionEnabled")

    if not enabled then
        if container then
            container:Hide()
        end
        isEnabled = false
        if previewFrame then previewFrame:Hide() end
        return
    end

    if not BuildContainer() then return end

    isEnabled = true

    -- The container registers/unregisters UNIT_AURA from its own visibility.
    container:Show()
    UpdatePosition()
    StyleButton()
    CDM.UpdatePowerInfusionPreview()
end

-- Called by BuffGroups after a layout pass.
function CDM.UpdatePowerInfusionAnchor()
    if not isEnabled then return end
    UpdatePosition()
end

function CDM.UpdatePowerInfusionStyle()
    if not isEnabled then return end
    needsStyleUpdate = true
    StyleButton()
    UpdatePosition()
    CDM.UpdatePowerInfusionPreview()
end

function CDM.OnPowerInfusionProfileApplied()
    needsStyleUpdate = true
    CDM.ReconcilePowerInfusion()
end

CDM:RegisterCombatStateHandler(function(isInCombat)
    if isInCombat then return end
    if positionDirty then
        UpdatePosition()
    end
end)
