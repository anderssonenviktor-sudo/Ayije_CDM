local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]

local CDM_C = CDM.CONST
local VIEWERS = CDM_C.VIEWERS

local LCG = LibStub("LibCustomGlow-1.0", true)
local Renderers = CDM.GlowRenderers
local UnitClass = UnitClass

local GetFrameData = CDM.GetFrameData
local pairs = pairs
local ipairs = ipairs
local type = type
local issecretvalue = issecretvalue
local GetAuraDataByAuraInstanceID = C_UnitAuras.GetAuraDataByAuraInstanceID

CDM.Glow = CDM.Glow or {}
local Glow = CDM.Glow

local GLOW_KEY = "CDM_SpellAlert"
local activeGlowFrames = setmetatable({}, { __mode = "k" })
local pendingHideFrames = setmetatable({}, { __mode = "k" })
local buffHookedFrames = setmetatable({}, { __mode = "k" })
local HideCustomGlow
local StopStackGlow, FeedStackGlow, ConfigureStackGlow, RetireStackGlow
local RefreshStackGlows
local stackGlowFrames = setmetatable({}, { __mode = "k" })
local stackRefreshPending = false

local debounceDrainer = CreateFrame("Frame")
debounceDrainer:Hide()
debounceDrainer:SetScript("OnUpdate", function(self)
    self:Hide()
    for frame in pairs(pendingHideFrames) do
        pendingHideFrames[frame] = nil
        HideCustomGlow(frame)
        CDM:ApplyAuraOverride(frame)
    end
    if stackRefreshPending then
        stackRefreshPending = false
        RefreshStackGlows()
    end
end)

local function IsSupportedViewerName(name)
    return name == VIEWERS.ESSENTIAL or name == VIEWERS.UTILITY
end

local function ColorsMatch(a, b)
    if a == b then return true end
    if not a or not b then return false end
    return a.r == b.r and a.g == b.g and a.b == b.b
end

local glowCache = {
    type = "proc",
    colorMode = "default",
    color = nil,
    pixelLines = 8,
    pixelFrequency = 0.2,
    pixelLength = 0,
    pixelThickness = 2,
    pixelXOffset = 0,
    pixelYOffset = 0,
    pixelBorder = false,
    autocastParticles = 4,
    autocastFrequency = 0.2,
    autocastScale = 1,
    autocastXOffset = 0,
    autocastYOffset = 0,
    buttonFrequency = 0,
    procDuration = 1,
    procXOffset = 0,
    procYOffset = 0,
}

local glowColorArrayCache = setmetatable({}, { __mode = "k" })

local function GetCachedGlowColorArray(color)
    if type(color) ~= "table" then
        return nil
    end

    local arr = glowColorArrayCache[color]
    if not arr then
        arr = { 1, 1, 1, 1 }
        glowColorArrayCache[color] = arr
    end

    arr[1] = color.r or 1
    arr[2] = color.g or 1
    arr[3] = color.b or 1
    arr[4] = color.a or 1
    return arr
end

local function GetViewerName(frame)
    if not frame then return nil end

    local frameData = GetFrameData(frame)
    if frameData.cdmViewerName then
        return frameData.cdmViewerName
    end
    if frameData.cdmViewerNameChecked then
        return nil
    end

    local result
    if frame.GetViewerFrame then
        local viewer = frame:GetViewerFrame()
        if viewer and viewer.GetName then
            result = viewer:GetName()
        end
    end

    if not result then
        local parent = frame.GetParent and frame:GetParent()
        while parent do
            if parent.GetName then
                local name = parent:GetName()
                if IsSupportedViewerName(name) then
                    result = name
                    break
                end
            end
            parent = parent.GetParent and parent:GetParent()
        end
    end

    frameData.cdmViewerNameChecked = true
    if result then
        frameData.cdmViewerName = result
    end
    return result
end

local function IsSupportedGlowFrame(frame)
    local viewerName = GetViewerName(frame)
    return IsSupportedViewerName(viewerName)
end

local function HideBlizzardGlow(frame)
    if not frame then return end
    local alert = frame.SpellActivationAlert
    if not alert then return end
    alert:SetAlpha(0)
    alert:Hide()
end

local function GetGlowColor(overrideColor)
    if overrideColor then
        return GetCachedGlowColorArray(overrideColor)
    end
    if glowCache.colorMode == "class" then
        local _, classTag = UnitClass("player")
        local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
        return GetCachedGlowColorArray(colors and colors[classTag])
    end
    if glowCache.colorMode == "custom" and glowCache.color then
        return GetCachedGlowColorArray(glowCache.color)
    end
    return nil
end

local procGlowOpts = {
    color = nil,
    startAnim = false,
    duration = 1,
    xOffset = 0,
    yOffset = 0,
    key = GLOW_KEY,
    frameLevel = 0,
}

local activeGlowSnapshot = {}

local glowStartFunctions = {
    gcd = function(frame, frameLevel, overrideColor)
        Renderers.StartFlipBook(frame, frameLevel, "gcd", GetGlowColor(overrideColor))
    end,

    shape = function(frame, frameLevel, overrideColor)
        local color = GetGlowColor(overrideColor) or GetCachedGlowColorArray(CDM.defaults.glowColor)
        Renderers.StartShape(frame, frameLevel, color)
    end,

    pixel = function(frame, frameLevel, overrideColor)
        local color = GetGlowColor(overrideColor)
        local length = glowCache.pixelLength
        if length == 0 then length = nil end
        LCG.PixelGlow_Start(
            frame,
            color,
            glowCache.pixelLines,
            glowCache.pixelFrequency,
            length,
            glowCache.pixelThickness,
            glowCache.pixelXOffset,
            glowCache.pixelYOffset,
            glowCache.pixelBorder,
            GLOW_KEY,
            frameLevel
        )
    end,

    autocast = function(frame, frameLevel, overrideColor)
        local color = GetGlowColor(overrideColor)
        LCG.AutoCastGlow_Start(
            frame,
            color,
            glowCache.autocastParticles,
            glowCache.autocastFrequency,
            glowCache.autocastScale,
            glowCache.autocastXOffset,
            glowCache.autocastYOffset,
            GLOW_KEY,
            frameLevel
        )
    end,

    button = function(frame, frameLevel, overrideColor)
        local color = GetGlowColor(overrideColor)
        local freq = glowCache.buttonFrequency
        if freq == 0 then freq = nil end
        LCG.ButtonGlow_Start(
            frame,
            color,
            freq,
            frameLevel
        )
    end,

    proc = function(frame, frameLevel, overrideColor)
        local color = GetGlowColor(overrideColor)
        procGlowOpts.color = color
        procGlowOpts.duration = glowCache.procDuration
        procGlowOpts.xOffset = glowCache.procXOffset
        procGlowOpts.yOffset = glowCache.procYOffset
        procGlowOpts.frameLevel = frameLevel
        LCG.ProcGlow_Start(frame, procGlowOpts)
        local f = frame["_ProcGlow" .. GLOW_KEY]
        if f then
            f:SetScript("OnHide", nil)
        end
    end,
}

local glowStopFunctions = {
    gcd = Renderers.Stop,
    shape = Renderers.Stop,

    pixel = function(frame)
        LCG.PixelGlow_Stop(frame, GLOW_KEY)
    end,

    autocast = function(frame)
        LCG.AutoCastGlow_Stop(frame, GLOW_KEY)
    end,

    button = function(frame, immediate)
        if immediate then
            local button = frame._ButtonGlow
            if button then
                -- Style switches must not leave the old button's fade-out visible.
                button.animIn:Stop()
                button.animOut:Stop()
                LCG.ButtonGlowPool:Release(button)
            end
            return
        end
        local stack = GetFrameData(frame).stackGlow
        local shown = frame:IsShown()
        if stack then
            -- Release immediately instead of fading with detached stack masks.
            local button = frame._ButtonGlow
            if button then
                button.animIn:Stop()
                button.animOut:Stop()
            end
            frame:Hide()
        end
        LCG.ButtonGlow_Stop(frame)
        if stack and shown then frame:Show() end
    end,

    proc = function(frame)
        local f = frame["_ProcGlow" .. GLOW_KEY]
        if f then
            if f.ProcStartAnim and f.ProcStartAnim:IsPlaying() then
                f.ProcStartAnim:Stop()
            end
            if f.ProcLoopAnim and f.ProcLoopAnim:IsPlaying() then
                f.ProcLoopAnim:Stop()
            end
        end
        LCG.ProcGlow_Stop(frame, GLOW_KEY)
    end,
}

local function DetachStackMasks(frame)
    local state = GetFrameData(frame).stackGlow
    if not state then return end
    for texture, maskCount in pairs(state.textures) do
        texture:RemoveMaskTexture(state.gate.mask)
        if maskCount == 2 then texture:RemoveMaskTexture(state.gate2.mask) end
        state.textures[texture] = nil
    end
end

local glowFrameKeys = {
    pixel = "_PixelGlow" .. GLOW_KEY,
    autocast = "_AutoCastGlow" .. GLOW_KEY,
    button = "_ButtonGlow",
    proc = "_ProcGlow" .. GLOW_KEY,
}

local function AttachStackRegions(state, ...)
    for i = 1, select("#", ...) do
        local texture = select(i, ...)
        if texture:IsObjectType("Texture") then
            texture:AddMaskTexture(state.gate.mask)
            if state.operator == "eq" then texture:AddMaskTexture(state.gate2.mask) end
            state.textures[texture] = state.operator == "eq" and 2 or 1
        end
    end
end

local function ShowCustomGlow(frame, overrideColor)
    if not LCG then return end

    local frameData = GetFrameData(frame)

    if frameData.cdmGlowActive and frameData.cdmGlowType == glowCache.type
       and ColorsMatch(frameData.cdmGlowOverrideColor, overrideColor) then
        return
    end

    if frameData.cdmGlowActive then
        DetachStackMasks(frame)
        local stopFn = glowStopFunctions[frameData.cdmGlowType]
        if stopFn then stopFn(frame, true) end
        frameData.cdmGlowActive = false
        frameData.cdmGlowType = nil
    end

    if frame:GetWidth() < 1 or frame:GetHeight() < 1 then
        return
    end

    if frame.IsRectValid and not frame:IsRectValid() then
        frame:GetWidth()
    end

    if glowCache.type ~= "button" and frame._ButtonGlow then
        glowStopFunctions.button(frame, true)
    end

    local fn = glowStartFunctions[glowCache.type]
    if fn then
        local frameLevel = frame:GetFrameLevel() + 5
        fn(frame, frameLevel, overrideColor)
        local state = frameData.stackGlow
        local rendererKey = glowFrameKeys[glowCache.type]
        local renderer = rendererKey and frame[rendererKey] or frameData.cdmNativeGlow
        if state and state.threshold and renderer then
            AttachStackRegions(state, renderer:GetRegions())
        end
        frameData.cdmGlowActive = true
        frameData.cdmGlowType = glowCache.type
        frameData.cdmGlowOverrideColor = overrideColor
        activeGlowFrames[frame] = true
        if not rendererKey and not frameData.cdmNativeGlowHideHooked then
            frameData.cdmNativeGlowHideHooked = true
            frame:HookScript("OnHide", function(self)
                local style = GetFrameData(self).cdmGlowType
                if style == "gcd" or style == "shape" then
                    HideCustomGlow(self)
                end
            end)
        end
    end
end

HideCustomGlow = function(frame)
    if not LCG then return end

    pendingHideFrames[frame] = nil

    local frameData = GetFrameData(frame)
    if not frameData.cdmGlowActive then return end

    local fn = glowStopFunctions[frameData.cdmGlowType]
    if fn then
        DetachStackMasks(frame)
        fn(frame)
    end

    frameData.cdmGlowActive = false
    frameData.cdmGlowType = nil
    frameData.cdmGlowOverrideColor = nil
    frameData.cdmSpellAlertGlow = nil
    activeGlowFrames[frame] = nil
end

local function EnsureBuffGlowHostFrame(frame)
    if not frame then return nil end
    local frameData = GetFrameData(frame)
    local host = frameData.cdmBuffGlowHost
    if host then
        return host
    end

    host = CreateFrame("Frame", nil, frame)
    host:SetClampedToScreen(false)
    frameData.cdmBuffGlowHost = host
    frameData.cdmBuffGlowHostAnchorTarget = nil
    frameData.cdmBuffGlowHostStrata = nil
    frameData.cdmBuffGlowHostLevel = nil
    return host
end

local function SyncBuffGlowHostFrame(frame, host)
    if not frame or not host then return end

    local frameData = GetFrameData(frame)

    if frameData.cdmBuffGlowHostAnchorTarget ~= frame then
        host:SetParent(frame)
        host:ClearAllPoints()
        host:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        host:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frameData.cdmBuffGlowHostAnchorTarget = frame
    end

    if frame.GetFrameStrata and host.SetFrameStrata then
        local strata = frame:GetFrameStrata()
        if strata and frameData.cdmBuffGlowHostStrata ~= strata then
            host:SetFrameStrata(strata)
            frameData.cdmBuffGlowHostStrata = strata
        end
    end

    if frame.GetFrameLevel and host.SetFrameLevel then
        local level = frame:GetFrameLevel()
        if level and frameData.cdmBuffGlowHostLevel ~= level then
            host:SetFrameLevel(level)
            frameData.cdmBuffGlowHostLevel = level
        end
    end
end

local function DoesGlowSourceMatchID(sourceID, sourceBase, id)
    if not sourceID or not id then return false end
    if id == sourceID or id == sourceBase then
        return true
    end
    if not CDM.NormalizeToBase then
        return false
    end
    local base = CDM.NormalizeToBase(id)
    return base == sourceID or base == sourceBase
end

local function IsBuffGlowSourceStillValid(frame, sourceID)
    if not frame then return false end
    if not sourceID then return true end
    if not (CDM.GetCurrentSpecID and CDM.GetSpellGlowEnabled) then return true end

    local specID = CDM:GetCurrentSpecID()
    if not specID then
        return false
    end
    if not CDM:GetSpellStackGlow(specID, sourceID) and not CDM:GetSpellGlowEnabled(specID, sourceID) then
        return false
    end

    local sourceBase = CDM.NormalizeToBase and CDM.NormalizeToBase(sourceID) or sourceID
    local frameData = GetFrameData(frame)
    if DoesGlowSourceMatchID(sourceID, sourceBase, frameData.buffCategorySpellID) then
        return true
    end

    local candidates = CDM.GetSpellIDCandidates and CDM:GetSpellIDCandidates(frame) or nil
    if candidates then
        for _, id in ipairs(candidates) do
            if DoesGlowSourceMatchID(sourceID, sourceBase, id) then
                return true
            end
        end
    end

    return false
end

local function EnsureBuffGlowTargetHooks(frame)
    if not frame or buffHookedFrames[frame] then
        return
    end
    if not frame.HookScript then
        return
    end

    buffHookedFrames[frame] = true

    frame:HookScript("OnShow", function(self)
        local frameData = GetFrameData(self)
        if frameData.stackGlow and frameData.stackGlow.threshold then
            RefreshStackGlows(self)
            return
        end
        if not frameData.cdmBuffGlowWanted then
            return
        end

        local host = frameData.cdmBuffGlowHost
        if not host then
            return
        end

        if not IsBuffGlowSourceStillValid(self, frameData.cdmBuffGlowSourceID) then
            frameData.cdmBuffGlowWanted = nil
            frameData.cdmBuffGlowOverrideColor = nil
            frameData.cdmBuffGlowSourceID = nil
            HideCustomGlow(host)
            host:Hide()
            return
        end

        SyncBuffGlowHostFrame(self, host)
        host:Show()
        ShowCustomGlow(host, frameData.cdmBuffGlowOverrideColor)
    end)

    frame:HookScript("OnSizeChanged", function(self)
        local frameData = GetFrameData(self)
        local host = frameData.cdmBuffGlowHost
        if host and frameData.cdmBuffGlowWanted then
            SyncBuffGlowHostFrame(self, host)
            if frameData.stackGlow and frameData.stackGlow.threshold then
                FeedStackGlow(self)
            end
        end
    end)

    frame:HookScript("OnHide", function(self)
        local state = GetFrameData(self).stackGlow
        if state then StopStackGlow(state) end
    end)
end

function Glow:RequestBuffGlow(frame, enabled, overrideColor, sourceID)
    if not frame or not LCG then return end

    local frameData = GetFrameData(frame)

    frameData.cdmBuffGlowWanted = enabled and true or false
    frameData.cdmBuffGlowOverrideColor = overrideColor
    frameData.cdmBuffGlowSourceID = sourceID

    EnsureBuffGlowTargetHooks(frame)

    local stackEnabled, threshold, operator
    if enabled and sourceID and CDM.GetSpellStackGlow then
        stackEnabled, threshold, operator = CDM:GetSpellStackGlow(CDM:GetCurrentSpecID(), sourceID)
    end
    if stackEnabled then
        local host = EnsureBuffGlowHostFrame(frame)
        SyncBuffGlowHostFrame(frame, host)
        ConfigureStackGlow(frame, host, sourceID, threshold, operator)
        FeedStackGlow(frame)
        return
    elseif frameData.stackGlow and frameData.stackGlow.threshold then
        RetireStackGlow(frame)
    end

    if enabled then
        local host = EnsureBuffGlowHostFrame(frame)
        SyncBuffGlowHostFrame(frame, host)
        if frame:IsShown() then
            host:Show()
            ShowCustomGlow(host, overrideColor)
        end
    else
        local host = frameData.cdmBuffGlowHost
        if host then
            HideCustomGlow(host)
            host:Hide()
        else
            HideCustomGlow(frame)
        end
    end
end

local stackRanges = {
    gte = { -1, 0, false }, gt = { 0, 1, false },
    lt = { -1, 0, true }, lte = { 0, 1, true },
    eq = { -1, 0, false },
}

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function ReadBuffApplications(frame)
    local iid = frame.auraInstanceID
    local unit = frame.auraDataUnit
    if not IsSecret(iid) and iid and not IsSecret(unit) and unit then
        local ok, data = pcall(GetAuraDataByAuraInstanceID, unit, iid)
        if ok and not IsSecret(data) and data then
            local applications = data.applications
            if IsSecret(applications) or applications ~= nil then return applications end
        end
    end
    local cached = frame.auraDataCached
    if not IsSecret(cached) and cached then
        return cached.applications
    end
end

local function StackMatches(value, operator, threshold)
    if operator == "lt" then return value < threshold end
    if operator == "lte" then return value <= threshold end
    if operator == "eq" then return value == threshold end
    if operator == "gt" then return value > threshold end
    return value >= threshold
end

local function CreateStackGate(host)
    local bar = CreateFrame("StatusBar", nil, host)
    bar:EnableMouse(false)
    bar:SetOrientation("HORIZONTAL")
    bar:SetReverseFill(false)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local fill = bar:GetStatusBarTexture()
    fill:SetAlpha(0)
    -- The mask's parent must also be an ancestor of the LCG textures.
    local mask = host:CreateMaskTexture()
    mask:SetTexture("Interface\\Buttons\\WHITE8x8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    return { bar = bar, fill = fill, mask = mask }
end

local function ConfigureGate(gate, threshold, range)
    local minimum, maximum = threshold + range[1], threshold + range[2]
    gate.bar:SetMinMaxValues(minimum, maximum)
    gate.closeValue = range[3] and maximum or minimum
    gate.openValue = range[3] and minimum or maximum
    gate.mask:ClearAllPoints()
    gate.mask:SetPoint(range[3] and "LEFT" or "RIGHT", gate.fill, "RIGHT", 0, 0)
    gate.bar:SetValue(gate.closeValue)
end

local function SizeGate(gate, host, width, height, pad)
    gate.bar:ClearAllPoints()
    gate.bar:SetPoint("TOPLEFT", host, "TOPLEFT", -pad, pad)
    gate.bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", pad, -pad)
    gate.mask:SetSize(width + 2 * pad, height + 2 * pad)
end

StopStackGlow = function(state)
    state.gate.bar:SetValue(state.gate.closeValue or 0)
    if state.gate2 then state.gate2.bar:SetValue(state.gate2.closeValue or 0) end
    HideCustomGlow(state.host)
    state.host:Hide()
end

RetireStackGlow = function(frame)
    local state = GetFrameData(frame).stackGlow
    StopStackGlow(state)
    state.threshold = nil
    state.sourceID = nil
    GetFrameData(state.host).stackGlow = nil
    stackGlowFrames[frame] = nil
end

function Glow:RetireBuffStackGlow(frame)
    local frameData = GetFrameData(frame)
    if frameData.stackGlow and frameData.stackGlow.threshold then
        RetireStackGlow(frame)
        frameData.cdmBuffGlowWanted = nil
        frameData.cdmBuffGlowSourceID = nil
        frameData.cdmBuffGlowOverrideColor = nil
    end
end

local function QueueStackRefresh()
    if not next(stackGlowFrames) then return end
    stackRefreshPending = true
    debounceDrainer:Show()
end

ConfigureStackGlow = function(frame, host, sourceID, threshold, operator)
    local frameData = GetFrameData(frame)
    local state = frameData.stackGlow
    if not state then
        HideCustomGlow(host)
        state = { host = host, gate = CreateStackGate(host), textures = {} }
        frameData.stackGlow = state
        -- RefreshData also covers pooled icon reassignment; the aura hooks cover
        -- changes that do not cause a layout or a complete aura reassignment.
        for _, method in ipairs({ "RefreshData", "SetAuraInstanceInfo", "OnActiveStateChanged" }) do
            if frame[method] then
                hooksecurefunc(frame, method, function()
                    if state.threshold then QueueStackRefresh() end
                end)
            end
        end
        if frame.ClearAuraInstanceInfo then
            hooksecurefunc(frame, "ClearAuraInstanceInfo", function()
                if state.threshold then
                    StopStackGlow(state)
                    QueueStackRefresh()
                end
            end)
        end
    end
    if state.threshold ~= threshold or state.operator ~= operator or state.sourceID ~= sourceID then
        StopStackGlow(state)
        state.threshold, state.operator, state.sourceID = threshold, operator, sourceID
        ConfigureGate(state.gate, threshold, stackRanges[operator])
        if operator == "eq" then
            if not state.gate2 then state.gate2 = CreateStackGate(host) end
            ConfigureGate(state.gate2, threshold, stackRanges.lte)
        end
        state.width = nil
    end
    GetFrameData(host).stackGlow = state
    stackGlowFrames[frame] = true
end

local function IsStackBuffActive(frame)
    local active = frame.isActive
    if not IsSecret(active) and active ~= nil then return active == true end
    local iid = frame.auraInstanceID
    if IsSecret(iid) or iid ~= nil then return true end
    local cached = frame.auraDataCached
    if IsSecret(cached) or cached ~= nil then return true end
    return frame.isCustomBuff == true or frame.totemData ~= nil
end

FeedStackGlow = function(frame)
    local frameData = GetFrameData(frame)
    local state = frameData.stackGlow
    if not state or not state.threshold then return end
    if not frameData.cdmBuffGlowWanted or not frame:IsShown() or frameData.cdmVisualsHidden
        or not IsStackBuffActive(frame) then
        StopStackGlow(state)
        return
    end
    local width, height = frame:GetSize()
    local pad = math.max(12, math.ceil(math.max(width, height) * 0.4),
        math.abs(glowCache.pixelXOffset) + glowCache.pixelThickness + 2,
        math.abs(glowCache.pixelYOffset) + glowCache.pixelThickness + 2,
        math.abs(glowCache.autocastXOffset) + 16 * glowCache.autocastScale,
        math.abs(glowCache.autocastYOffset) + 16 * glowCache.autocastScale,
        math.abs(glowCache.procXOffset) + width * 0.5,
        math.abs(glowCache.procYOffset) + height * 0.5,
        width * 0.5, height * 0.5)
    if state.width ~= width or state.height ~= height or state.pad ~= pad then
        SizeGate(state.gate, state.host, width, height, pad)
        if state.gate2 then SizeGate(state.gate2, state.host, width, height, pad) end
        state.width, state.height, state.pad = width, height, pad
    end
    local applications = ReadBuffApplications(frame)
    if not IsSecret(applications) then
        if applications == nil then
            -- Unknown count on an active buff fails open, even for < 1.
            state.gate.bar:SetValue(state.gate.openValue)
            if state.operator == "eq" then state.gate2.bar:SetValue(state.gate2.openValue) end
        elseif not StackMatches(applications, state.operator, state.threshold) then
            StopStackGlow(state)
            return
        else
            state.gate.bar:SetValue(applications)
            if state.operator == "eq" then state.gate2.bar:SetValue(applications) end
        end
    else
        -- Secret counts only flow into native setters, never Lua comparisons.
        state.gate.bar:SetValue(applications)
        if state.operator == "eq" then state.gate2.bar:SetValue(applications) end
    end
    state.host:Show()
    ShowCustomGlow(state.host, frameData.cdmBuffGlowOverrideColor)
end

local function RefreshStackFrame(frame)
    local frameData = GetFrameData(frame)
    local specID = CDM:GetCurrentSpecID()
    local enabled, color, sourceID = CDM:ResolveBuffGlowState(frame, specID, frameData.buffCategorySpellID ~= nil)
    local stackEnabled = enabled and sourceID and CDM:GetSpellStackGlow(specID, sourceID)
    if not stackEnabled and (not IsStackBuffActive(frame) or frameData.cdmVisualsHidden) then enabled = false end
    Glow:RequestBuffGlow(frame, enabled, color, sourceID)
end

RefreshStackGlows = function(frame)
    if frame then
        RefreshStackFrame(frame)
    else
        for icon in pairs(stackGlowFrames) do RefreshStackFrame(icon) end
    end
end

CDM:RegisterEvent("UNIT_AURA", QueueStackRefresh)
CDM:RegisterRefreshCallback("stackGlows", QueueStackRefresh, 55, { "BUFF_DATA", "STYLE" })

function Glow:HideBlizzardGlow(frame)
    HideBlizzardGlow(frame)
end

function Glow:RefreshActiveGlows()
    if not LCG then return end

    for frame in pairs(pendingHideFrames) do
        pendingHideFrames[frame] = nil
        HideCustomGlow(frame)
    end
    debounceDrainer:Hide()
    if stackRefreshPending then debounceDrainer:Show() end

    local count = 0
    for frame in pairs(activeGlowFrames) do
        count = count + 1
        activeGlowSnapshot[count] = frame
    end

    for i = 1, count do
        local frame = activeGlowSnapshot[i]
        activeGlowSnapshot[i] = nil
        local frameData = GetFrameData(frame)
        if frameData.cdmGlowActive then
            if frameData.cdmSpellAlertGlow and CDM.GetCooldownGlowColorOverride then
                frameData.cdmGlowOverrideColor = CDM:GetCooldownGlowColorOverride(frame)
            end
            local stopFn = glowStopFunctions[frameData.cdmGlowType]
            DetachStackMasks(frame)
            if stopFn then stopFn(frame, true) end
            frameData.cdmGlowActive = false
            frameData.cdmGlowType = nil
            ShowCustomGlow(frame, frameData.cdmGlowOverrideColor)
        else
            activeGlowFrames[frame] = nil
        end
    end
end

function Glow:HookAlertManager()
    if self.alertManagerHooked then return end

    local alertManager = _G.ActionButtonSpellAlertManager
    if not alertManager then return end

    hooksecurefunc(alertManager, "ShowAlert", function(_, frame)
        if not IsSupportedGlowFrame(frame) then return end

        pendingHideFrames[frame] = nil

        HideBlizzardGlow(frame)
        local frameData = GetFrameData(frame)
        local overrideColor = CDM.GetCooldownGlowColorOverride
            and CDM:GetCooldownGlowColorOverride(frame) or nil
        if frameData.cdmGlowActive and frameData.cdmGlowType == glowCache.type
            and ColorsMatch(frameData.cdmGlowOverrideColor, overrideColor) then
            return
        end
        frameData.cdmSpellAlertGlow = true
        ShowCustomGlow(frame, overrideColor)
        if frameData.cdmReadyGlowActive then
            Glow:RequestBuffGlow(frame, false)
            frameData.cdmReadyGlowActive = false
        end
    end)

    hooksecurefunc(alertManager, "HideAlert", function(_, frame)
        if not IsSupportedGlowFrame(frame) then return end

        HideBlizzardGlow(frame)

        local frameData = GetFrameData(frame)
        if not frameData.cdmGlowActive then return end

        pendingHideFrames[frame] = true
        debounceDrainer:Show()
    end)

    self.alertManagerHooked = true
end

local function GlowCfg(db, defaults, key)
    if db[key] ~= nil then return db[key] end
    return defaults[key]
end

function Glow:RefreshCache()
    local db = CDM.db or {}
    local defaults = CDM.defaults or {}

    glowCache.type = GlowCfg(db, defaults, "glowType") or "proc"
    glowCache.colorMode = GlowCfg(db, defaults, "glowColorMode") or "default"
    glowCache.color = GlowCfg(db, defaults, "glowColor")

    glowCache.pixelLines = GlowCfg(db, defaults, "glowPixelLines")
    glowCache.pixelFrequency = GlowCfg(db, defaults, "glowPixelFrequency")
    glowCache.pixelLength = GlowCfg(db, defaults, "glowPixelLength")
    glowCache.pixelThickness = GlowCfg(db, defaults, "glowPixelThickness")
    glowCache.pixelXOffset = GlowCfg(db, defaults, "glowPixelXOffset")
    glowCache.pixelYOffset = GlowCfg(db, defaults, "glowPixelYOffset")
    glowCache.pixelBorder = GlowCfg(db, defaults, "glowPixelBorder") and true or false

    glowCache.autocastParticles = GlowCfg(db, defaults, "glowAutocastParticles")
    glowCache.autocastFrequency = GlowCfg(db, defaults, "glowAutocastFrequency")
    glowCache.autocastScale = GlowCfg(db, defaults, "glowAutocastScale")
    glowCache.autocastXOffset = GlowCfg(db, defaults, "glowAutocastXOffset")
    glowCache.autocastYOffset = GlowCfg(db, defaults, "glowAutocastYOffset")

    glowCache.buttonFrequency = GlowCfg(db, defaults, "glowButtonFrequency")

    glowCache.procDuration = GlowCfg(db, defaults, "glowProcDuration")
    glowCache.procXOffset = GlowCfg(db, defaults, "glowProcXOffset")
    glowCache.procYOffset = GlowCfg(db, defaults, "glowProcYOffset")

    if not glowStartFunctions[glowCache.type] then
        glowCache.type = "proc"
    end

    self:RefreshActiveGlows()
end

function Glow:Initialize()
    self:RefreshCache()
    self:HookAlertManager()
end

CDM:RegisterRefreshCallback("glow", function()
    Glow:RefreshCache()
end, 50, { "STYLE" })

CDM:RegisterRefreshCallback("cooldownGlowOverrides", function()
    Glow:RefreshActiveGlows()
end, 50, { "CD_DATA" })

