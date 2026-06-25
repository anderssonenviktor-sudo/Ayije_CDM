local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]

local CDM_C = CDM and CDM.CONST or {}
local Snap = CDM.Pixel.Snap

CDM.CustomBuffs = {
    activeBuffs = {},       -- [spellID] = { expires, frame, startTime, duration }
    activeBuffVersion = 0,
    iconFrames = {},        -- [spellID] = frame
    barFrames = {},         -- [spellID] = frame
    framePool = {},         -- reusable, inactive custom buff frames
    barFramePool = {},      -- reusable, inactive custom buff bar frames
}

local CB = CDM.CustomBuffs
local VIEWERS = CDM_C.VIEWERS

local GetTime = GetTime
local GetPlayerAuraBySpellID = C_UnitAuras.GetPlayerAuraBySpellID
local GetSpellTexture = C_Spell.GetSpellTexture

local EMPTY_ORDER = {}
local ungroupedSeenScratch = {}

local TIME_SPIRAL_TRIGGERS = {
    [48265]  = true,  -- Death's Advance
    [195072] = true,  -- Fel Rush
    [189110] = true,  -- Infernal Strike
    [1850]   = true,  -- Dash
    [252216] = true,  -- Tiger Dash
    [358267] = true,  -- Hover
    [186257] = true,  -- Aspect of the Cheetah
    [1953]   = true,  -- Blink
    [212653] = true,  -- Shimmer
    [361138] = true,  -- Roll
    [119085] = true,  -- Chi Torpedo
    [190784] = true,  -- Divine Steed
    [73325]  = true,  -- Leap of Faith
    [2983]   = true,  -- Sprint
    [192063] = true,  -- Gust of Wind
    [58875]  = true,  -- Spirit Walk
    [79206]  = true,  -- Spiritwalker's Grace
    [48020]  = true,  -- Demonic Circle: Teleport
    [6544]   = true,  -- Heroic Leap
}

local TIME_SPIRAL_GLOW_FILTERS = {
    { talentID = 427640, spells = {198793, 370965, 195072} },  -- Inertia → Vengeful Retreat, The Hunt, Fel Rush
    { talentID = 427794, spells = {195072} },                  -- Dash of Chaos → Fel Rush
    { talentID = 385899, spells = {385899} },                  -- Soulburn
}

local glowSuppressSpells = {}
local suppressGlowUntil = 0

local BLOODLUST_DEBUFFS = {
    [57723]  = 32182,   -- Exhaustion → Heroism
    [57724]  = 2825,    -- Sated → Bloodlust
    [80354]  = 80353,   -- Temporal Displacement → Time Warp
    [95809]  = 90355,   -- Insanity → Ancient Hysteria
    [160455] = 264667,  -- Fatigued → Primal Rage
    [264689] = 264667,  -- Fatigued → Primal Rage
    [390435] = 390386,  -- Exhaustion → Fury of the Aspects
}

function CDM:RebuildGlowFilters()
    table.wipe(glowSuppressSpells)
    for _, entry in ipairs(TIME_SPIRAL_GLOW_FILTERS) do
        if IsPlayerSpell(entry.talentID) then
            for _, spellID in ipairs(entry.spells) do
                glowSuppressSpells[spellID] = true
            end
        end
    end
end

local cachedCustomBuffStyles = {
    fontPath = nil,
    fontOutline = nil,
    fontSize = 12,
    fontColor = nil,
}

local function RefreshCachedCustomBuffStyles()
    local db = CDM.db
    local defaults = CDM.defaults or {}

    CDM_C.RefreshBaseFontCache()
    cachedCustomBuffStyles.fontPath = CDM_C.GetBaseFontPath()
    cachedCustomBuffStyles.fontOutline = CDM_C.GetBaseFontOutline()
    cachedCustomBuffStyles.fontSize = db and db.buffCooldownFontSize or defaults.buffCooldownFontSize or 12
    cachedCustomBuffStyles.fontColor = (db and db.buffCooldownColor) or defaults.buffCooldownColor or CDM_C.WHITE
end

CDM.RefreshCachedCustomBuffStyles = RefreshCachedCustomBuffStyles

local function SetupCustomBuffCooldownTextLayout(frame)
    if not frame or not frame.Cooldown then return end

    local text = frame.Cooldown.Text or frame.Cooldown.text
    if not text or not text.SetFont then return end
    text:SetIgnoreParentScale(true)
    text:ClearAllPoints()
    text:SetPoint("CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetShadowOffset(0, 0)
    text:SetDrawLayer("OVERLAY", 7)
end

local function IsGroupedCustomBuff(spellID)
    local sets = CDM.BuffGroupSets
    local grouped = sets and sets.grouped
    return grouped and grouped[spellID] and true or false
end

local function IsBarGroupedCustomBuff(spellID)
    local sets = CDM.BarGroupSets
    local grouped = sets and sets.grouped
    return grouped and grouped[spellID] and true or false
end

-- A custom buff renders as a bar when it belongs to a bar group; otherwise it
-- renders as an icon (in a buff group, or ungrouped). Show only the matching
-- frame so the same buff never appears as both an icon and a bar.
local function ApplyCustomBuffDisplayMode(spellID, iconFrame, barFrame)
    local asBar = IsBarGroupedCustomBuff(spellID)
    if iconFrame then iconFrame:SetShown(not asBar) end
    if barFrame then barFrame:SetShown(asBar) end
    return asBar
end

local function ApplyCustomBuffCooldownTextStyle(frame)
    if not frame or not frame.Cooldown then return end
    if not cachedCustomBuffStyles.fontPath then
        RefreshCachedCustomBuffStyles()
    end

    local text = frame.Cooldown.Text or frame.Cooldown.text
    if not text or not text.SetFont then return end
    local fontColor = cachedCustomBuffStyles.fontColor or CDM_C.WHITE
    text:SetFont(
        cachedCustomBuffStyles.fontPath,
        CDM.Pixel.FontSize(cachedCustomBuffStyles.fontSize),
        cachedCustomBuffStyles.fontOutline
    )
    text:SetTextColor(fontColor.r, fontColor.g, fontColor.b, fontColor.a or 1)
end

local function ReanchorBuffViewer()
    local v = _G[VIEWERS.BUFF]
    if v then CDM:ForceReanchor(v) end
end

local function ReanchorBuffBarViewer()
    local v = _G[VIEWERS.BUFF_BAR]
    if v then CDM:ForceReanchor(v) end
end

local function GetCustomBuffBarEffectiveSize(spellID)
    local sets = CDM.BarGroupSets
    local grouped = sets and sets.grouped
    local groupIdx = spellID and grouped and grouped[spellID]
    local groupData = groupIdx and sets.groups and sets.groups[groupIdx]
    local db = CDM.db or {}

    local width = (groupData and groupData.barWidth) or db.buffBarWidth or 0
    if width == 0 and CDM.CalculateEssentialRow1Width then
        width = CDM.CalculateEssentialRow1Width()
    end
    if width == 0 then width = 120 end

    local height = (groupData and groupData.barHeight) or db.buffBarHeight or 20
    return Snap(width), Snap(height)
end

function CDM:GetCustomBuffEffectiveSize(spellID)
    local sets = self.BuffGroupSets
    local grouped = sets and sets.grouped
    local groupIdx = spellID and grouped and grouped[spellID]
    local groupData = groupIdx and sets.groups and sets.groups[groupIdx]
    if groupData then
        return Snap(groupData.iconWidth or 30), Snap(groupData.iconHeight or 30)
    end
    local defaults = self.defaults or {}
    local defaultSize = defaults.sizeBuff or { w = 32, h = 32 }
    local dbSize = self.db and self.db.sizeBuff
    return (dbSize and dbSize.w) or defaultSize.w, (dbSize and dbSize.h) or defaultSize.h
end

local DeactivateCustomBuff

local function CustomBuffBarOnUpdate(frame)
    local duration = frame.customBuffDuration
    local expires = frame.customBuffExpires
    if not duration or duration <= 0 or not expires then return end

    local remaining = expires - GetTime()
    if remaining <= 0 then
        -- The bar is the only expiry signal when the icon frame is hidden
        -- (custom buff routed into a bar group), so drive deactivation here.
        frame:SetScript("OnUpdate", nil)
        local spellID = frame.spellID
        if spellID and DeactivateCustomBuff then
            DeactivateCustomBuff(spellID)
        end
        return
    end

    local bar = frame.Bar
    if bar then
        bar:SetMinMaxValues(0, duration)
        bar:SetValue(remaining)
        if bar.Duration then
            bar.Duration:SetText(C_StringUtil.TruncateWhenZero(remaining))
        end
    end
end

local function CreateCustomBuffIcon(spellID, config)
    if CB.iconFrames[spellID] then
        return CB.iconFrames[spellID]
    end

    local w, h = CDM:GetCustomBuffEffectiveSize(spellID)

    local frame = table.remove(CB.framePool)
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)

        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        CDM.Pixel.DisableTextureSnap(icon)
        frame.Icon = icon

        local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        cooldown:SetAllPoints()
        cooldown:SetDrawEdge(false)
        cooldown:SetDrawSwipe(not (CDM.db and CDM.db.hideBuffSwipe))
        cooldown:SetSwipeColor(CDM_C.SWIPE_COLOR.r, CDM_C.SWIPE_COLOR.g, CDM_C.SWIPE_COLOR.b, CDM_C.SWIPE_COLOR.a)
        cooldown:SetReverse(true)  -- Fill up as time passes (like a buff)
        frame.Cooldown = cooldown
        SetupCustomBuffCooldownTextLayout(frame)

        if CDM.BORDER and CDM.BORDER.CreateBorder then
            frame.cdmBorder = CDM.BORDER:CreateBorder(frame)
        end
    end

    frame:SetSize(w, h)
    frame.spellID = spellID
    frame.isCustomBuff = true
    frame.customBuffStartTime = nil

    if frame.Icon then
        frame.Icon:SetAllPoints()
        CDM_C.ApplyIconTexCoord(frame.Icon, CDM_C.GetEffectiveZoomAmount(), w, h)
        frame.Icon:SetTexture(config.icon)
        frame.Icon:SetDesaturation(0)
    end

    if frame.Cooldown then
        frame.Cooldown:SetAllPoints()
        frame.Cooldown:SetDrawBling(not (CDM.db and CDM.db.hideCooldownBling))
        frame.Cooldown:SetScript("OnCooldownDone", nil)
    end

    frame:Hide()

    CB.iconFrames[spellID] = frame

    return frame
end

local function CreateCustomBuffBar(spellID, config)
    if CB.barFrames[spellID] then
        return CB.barFrames[spellID]
    end

    local w, h = GetCustomBuffBarEffectiveSize(spellID)

    local frame = table.remove(CB.barFramePool)
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)

        local iconFrame = CreateFrame("Frame", nil, frame)
        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        CDM.Pixel.DisableTextureSnap(icon)
        iconFrame.Icon = icon
        frame.Icon = iconFrame

        local applications = iconFrame:CreateFontString(nil, "OVERLAY")
        applications:SetFont(CDM_C.FONT_PATH, 12, CDM_C.FONT_OUTLINE)
        applications:SetText("")
        applications:Hide()
        iconFrame.Applications = applications

        local bar = CreateFrame("StatusBar", nil, frame)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        frame.Bar = bar

        bar.Name = bar:CreateFontString(nil, "OVERLAY")
        bar.Name:SetFont(CDM_C.FONT_PATH, 12, CDM_C.FONT_OUTLINE)
        bar.Duration = bar:CreateFontString(nil, "OVERLAY")
        bar.Duration:SetFont(CDM_C.FONT_PATH, 12, CDM_C.FONT_OUTLINE)
    end

    frame:SetSize(w, h)
    frame.spellID = spellID
    frame.isCustomBuff = true
    frame.isCustomBuffBar = true
    frame.customBuffStartTime = nil
    frame.customBuffDuration = nil
    frame.customBuffExpires = nil

    frame.GetSpellID = frame.GetSpellID or function(self) return self.spellID end
    frame.GetBaseSpellID = frame.GetBaseSpellID or function(self) return self.spellID end
    frame.RefreshName = frame.RefreshName or function(self)
        local cfg = self.spellID and CDM.db and CDM.db.customBuffRegistry and CDM.db.customBuffRegistry[self.spellID]
        local name = cfg and cfg.name or (self.spellID and C_Spell.GetSpellName(self.spellID)) or ""
        if self.Bar and self.Bar.Name then
            self.Bar.Name:SetText(name)
        end
    end

    if frame.Icon then
        frame.Icon:SetSize(h, h)
        if frame.Icon.Icon then
            frame.Icon.Icon:SetAllPoints()
            CDM_C.ApplyIconTexCoord(frame.Icon.Icon, CDM_C.GetEffectiveZoomAmount(), h, h)
            frame.Icon.Icon:SetTexture(config.icon)
            frame.Icon.Icon:SetDesaturation(0)
        end
    end

    if frame.Bar then
        frame.Bar:SetMinMaxValues(0, config.duration or 1)
        frame.Bar:SetValue(config.duration or 1)
        if frame.Bar.Name then frame.Bar.Name:SetText(config.name or C_Spell.GetSpellName(spellID) or "") end
        if frame.Bar.Duration then frame.Bar.Duration:SetText("") end
    end

    frame:Hide()
    CB.barFrames[spellID] = frame

    return frame
end

local function ActivateCustomBuff(spellID, config, overrideStartTime)
    local frame = CreateCustomBuffIcon(spellID, config)
    local barFrame = CreateCustomBuffBar(spellID, config)

    local startTime = overrideStartTime or GetTime()
    local duration = config.duration
    local expires = startTime + duration

    if not frame.cdmDurationObj then
        frame.cdmDurationObj = C_DurationUtil.CreateDuration()
    end
    frame.cdmDurationObj:SetTimeFromStart(startTime, duration)
    frame.Cooldown:SetCooldownFromDurationObject(frame.cdmDurationObj)
    frame.Cooldown:SetScript("OnCooldownDone", function()
        DeactivateCustomBuff(spellID)
    end)
    if not IsGroupedCustomBuff(spellID) then
        ApplyCustomBuffCooldownTextStyle(frame)
    end

    CB.activeBuffs[spellID] = {
        expires = expires,
        frame = frame,
        barFrame = barFrame,
        startTime = startTime,
        duration = duration,
    }
    CB.activeBuffVersion = (CB.activeBuffVersion or 0) + 1

    frame.customBuffStartTime = startTime
    barFrame.customBuffStartTime = startTime
    barFrame.customBuffDuration = duration
    barFrame.customBuffExpires = expires

    ApplyCustomBuffDisplayMode(spellID, frame, barFrame)
    barFrame:SetScript("OnUpdate", CustomBuffBarOnUpdate)
    CustomBuffBarOnUpdate(barFrame)
    ReanchorBuffViewer()
    ReanchorBuffBarViewer()

    if CDM.PlayCustomBuffNotification then
        CDM:PlayCustomBuffNotification(spellID, false)
    end
end

DeactivateCustomBuff = function(spellID)
    local buffData = CB.activeBuffs[spellID]
    if not buffData then return end

    if CDM.PlayCustomBuffNotification then
        CDM:PlayCustomBuffNotification(spellID, true)
    end

    if buffData.frame then
        if buffData.frame.Cooldown then
            buffData.frame.Cooldown:SetScript("OnCooldownDone", nil)
        end
        buffData.frame:Hide()
    end
    if buffData.barFrame then
        buffData.barFrame:SetScript("OnUpdate", nil)
        buffData.barFrame:Hide()
    end

    CB.activeBuffs[spellID] = nil
    CB.activeBuffVersion = (CB.activeBuffVersion or 0) + 1
    ReanchorBuffViewer()
    ReanchorBuffBarViewer()
end

local function OnSpellCastSucceeded(event, unit, castGUID, spellID)
    local config = CDM.db.customBuffRegistry and CDM.db.customBuffRegistry[spellID]
    if not config or config.triggerType then return end

    ActivateCustomBuff(spellID, config)
end

local function OnSpellCastSent(event, unit, target, castGUID, spellID)
    if not CDM.IsSafeNumber(spellID) then return end
    if not glowSuppressSpells[spellID] then return end
    suppressGlowUntil = GetTime() + 1.5
end

local function OnGlowShow(event, spellID)
    if not CDM.IsSafeNumber(spellID) then return end
    if not TIME_SPIRAL_TRIGGERS[spellID] then return end
    if GetTime() < suppressGlowUntil then return end
    local config = CDM.db.customBuffRegistry and CDM.db.customBuffRegistry[374968]
    if not config then return end
    if CB.activeBuffs[374968] then return end
    ActivateCustomBuff(374968, config)
end

local function OnGlowHide(event, spellID)
    if not CDM.IsSafeNumber(spellID) then return end
    if not TIME_SPIRAL_TRIGGERS[spellID] then return end
    if not CB.activeBuffs[374968] then return end
    DeactivateCustomBuff(374968)
end

local bloodlustDebuffInstanceID

local function ActivateBloodlustFromDebuff(aura, lustBuffID, requireWithinWindow)
    local config = CDM.db.customBuffRegistry and CDM.db.customBuffRegistry[2825]
    if not config then return end
    if CB.activeBuffs[2825] then return end

    local dur = aura.duration
    if not dur or dur <= 0 then dur = 600 end
    local appliedTime = aura.expirationTime - dur

    if requireWithinWindow and (GetTime() - appliedTime) >= 40 then return end

    ActivateCustomBuff(2825, config, appliedTime)
    local frame = CB.iconFrames[2825]
    if frame and frame.Icon then
        frame.Icon:SetTexture(GetSpellTexture(lustBuffID))
    end
end

local function SeedBloodlust()
    bloodlustDebuffInstanceID = nil
    for debuffID, lustBuffID in pairs(BLOODLUST_DEBUFFS) do
        local aura = GetPlayerAuraBySpellID(debuffID)
        if aura and aura.auraInstanceID and aura.expirationTime then
            bloodlustDebuffInstanceID = aura.auraInstanceID
            ActivateBloodlustFromDebuff(aura, lustBuffID, true)
            return
        end
    end
end

local function OnBloodlustAura(event, unit, info)
    if not info or info.isFullUpdate then
        SeedBloodlust()
        return
    end
    if info.addedAuras then
        for _, aura in ipairs(info.addedAuras) do
            local sid = aura.spellId
            if CDM.IsSafeNumber(sid) then
                local lustBuffID = BLOODLUST_DEBUFFS[sid]
                if lustBuffID and aura.auraInstanceID and aura.expirationTime then
                    bloodlustDebuffInstanceID = aura.auraInstanceID
                    ActivateBloodlustFromDebuff(aura, lustBuffID, false)
                    break
                end
            end
        end
    end
    if bloodlustDebuffInstanceID and info.removedAuraInstanceIDs then
        for _, id in ipairs(info.removedAuraInstanceIDs) do
            if id == bloodlustDebuffInstanceID then
                bloodlustDebuffInstanceID = nil
                break
            end
        end
    end
end

function CDM:AddCustomBuffSpell(spellID, duration, templateOverrides)
    if not spellID or not duration then return false end

    local spellInfo = C_Spell.GetSpellInfo(spellID)
    if not spellInfo then return false end

    if not CDM.db.customBuffRegistry then
        CDM.db.customBuffRegistry = {}
    end

    local entry = {
        duration = duration,
        name = spellInfo.name,
        icon = spellInfo.iconID,
    }
    if templateOverrides then
        if templateOverrides.icon then entry.icon = templateOverrides.icon end
        if templateOverrides.triggerType then entry.triggerType = templateOverrides.triggerType end
    end

    CDM.db.customBuffRegistry[spellID] = entry
    return true
end

function CDM:RemoveCustomBuffSpell(spellID)
    if not CDM.db.customBuffRegistry then return end

    if CB.activeBuffs[spellID] then
        DeactivateCustomBuff(spellID)
    end

    local frame = CB.iconFrames[spellID]
    if frame then
        if frame.Cooldown then
            frame.Cooldown:SetScript("OnCooldownDone", nil)
            frame.Cooldown:Clear()
        end
        frame:Hide()
        frame:ClearAllPoints()
        frame.cdmAnchor = nil
        if frame:GetParent() ~= UIParent then
            frame:SetParent(UIParent)
        end
        frame.spellID = nil
        frame.customBuffStartTime = nil
        CB.framePool[#CB.framePool + 1] = frame
        CB.iconFrames[spellID] = nil
    end

    local barFrame = CB.barFrames[spellID]
    if barFrame then
        barFrame:SetScript("OnUpdate", nil)
        barFrame:Hide()
        barFrame:ClearAllPoints()
        barFrame.cdmBarAnchor = nil
        if barFrame:GetParent() ~= UIParent then
            barFrame:SetParent(UIParent)
        end
        barFrame.spellID = nil
        barFrame.customBuffStartTime = nil
        barFrame.customBuffDuration = nil
        barFrame.customBuffExpires = nil
        CB.barFramePool[#CB.barFramePool + 1] = barFrame
        CB.barFrames[spellID] = nil
    end

    CDM.db.customBuffRegistry[spellID] = nil

    if CDM.db.ungroupedCustomBuffOrder then
        for _, order in pairs(CDM.db.ungroupedCustomBuffOrder) do
            for i = #order, 1, -1 do
                if order[i].spellID == spellID then
                    table.remove(order, i)
                end
            end
        end
    end

    if CDM.db.buffGroups then
        for _, specGroups in pairs(CDM.db.buffGroups) do
            if type(specGroups) == "table" then
                for _, groupData in ipairs(specGroups) do
                    if groupData.spells then
                        for i = #groupData.spells, 1, -1 do
                            if groupData.spells[i] == spellID then
                                table.remove(groupData.spells, i)
                            end
                        end
                    end
                end
            end
        end
    end

    if CDM.db.barGroups then
        for _, specGroups in pairs(CDM.db.barGroups) do
            if type(specGroups) == "table" then
                for _, groupData in ipairs(specGroups) do
                    if groupData.spells then
                        for i = #groupData.spells, 1, -1 do
                            if groupData.spells[i] == spellID then
                                table.remove(groupData.spells, i)
                            end
                        end
                    end
                end
            end
        end
    end

    local isAlsoNative = CDM.ResolveStableBase and CDM:ResolveStableBase(spellID)
    if not isAlsoNative then
        local storageKey = CDM.GetBuffOverrideStorageKey and CDM:GetBuffOverrideStorageKey(spellID) or spellID

        if CDM.db.ungroupedBuffOverrides then
            for _, specOv in pairs(CDM.db.ungroupedBuffOverrides) do
                if type(specOv) == "table" then
                    specOv[spellID] = nil
                    if storageKey then specOv[storageKey] = nil end
                end
            end
        end

        if CDM.db.spellRegistry then
            for specID, registry in pairs(CDM.db.spellRegistry) do
                if type(registry) == "table" then
                    if registry.colors then registry.colors[spellID] = nil end
                    if registry.glowEnabled then registry.glowEnabled[spellID] = nil end
                    if registry.glowColors then registry.glowColors[spellID] = nil end
                end
                if CDM.CompactRegistrySpec then
                    CDM:CompactRegistrySpec(specID)
                end
            end
        end
    end
end

function CDM:UpdateCustomBuffs()
    RefreshCachedCustomBuffStyles()

    for spellID, frame in pairs(CB.iconFrames) do
        local w, h = self:GetCustomBuffEffectiveSize(spellID)
        frame:SetSize(w, h)

        if frame.Icon then
            CDM_C.ApplyIconTexCoord(frame.Icon, CDM_C.GetEffectiveZoomAmount(), w, h)
        end

        if not IsGroupedCustomBuff(spellID) then
            ApplyCustomBuffCooldownTextStyle(frame)
        end
    end

    for spellID, frame in pairs(CB.barFrames) do
        local w, h = GetCustomBuffBarEffectiveSize(spellID)
        frame:SetSize(w, h)
        if frame.Icon then
            frame.Icon:SetSize(h, h)
            if frame.Icon.Icon then
                CDM_C.ApplyIconTexCoord(frame.Icon.Icon, CDM_C.GetEffectiveZoomAmount(), h, h)
            end
        end
        frame.cdmBarStyled = false
    end

    -- Group membership may have changed (e.g. a custom buff moved between an
    -- icon buff group and a bar group); re-resolve icon vs bar visibility.
    for spellID, buffData in pairs(CB.activeBuffs) do
        ApplyCustomBuffDisplayMode(spellID, buffData.frame, buffData.barFrame)
    end
end

CDM.CustomBuffTemplates = {
    { spellID = 1236616, duration = 30 },  -- Light's Potential
    { spellID = 1236994, duration = 30 },  -- Potion of Recklessness
    { spellID = 1239479, duration = 10 },  -- Potion of Devoured Dreams
    { spellID = 374968, duration = 10, icon = 4622479, triggerType = "timespiral" },  -- Time Spiral
    { spellID = 2825, duration = 40, triggerType = "bloodlust" },  -- Bloodlust
}


function CDM:IsCustomBuffInAnyGroup(specID, spellID)
    local db = self.db
    if not db then return false end
    for _, groupKey in ipairs({ "buffGroups", "barGroups" }) do
        local groups = db[groupKey] and db[groupKey][specID]
        if groups then
            for _, groupData in ipairs(groups) do
                if groupData.spells then
                    for _, sid in ipairs(groupData.spells) do
                        if sid == spellID then return true end
                    end
                end
            end
        end
    end
    return false
end

function CDM:GetUngroupedCustomBuffOrder(specID)
    if not specID then return EMPTY_ORDER end
    local db = self.db
    if not db then return EMPTY_ORDER end

    local registry = db.customBuffRegistry
    if not registry then return EMPTY_ORDER end

    if not db.ungroupedCustomBuffOrder then
        db.ungroupedCustomBuffOrder = {}
    end

    local order = db.ungroupedCustomBuffOrder[specID]
    if not order then
        order = {}
        db.ungroupedCustomBuffOrder[specID] = order
    end

    for i = #order, 1, -1 do
        local entry = order[i]
        if not registry[entry.spellID] or self:IsCustomBuffInAnyGroup(specID, entry.spellID) then
            table.remove(order, i)
        end
    end

    local seen = ungroupedSeenScratch
    table.wipe(seen)
    for _, entry in ipairs(order) do
        seen[entry.spellID] = true
    end

    for spellID in pairs(registry) do
        if not seen[spellID] and not self:IsCustomBuffInAnyGroup(specID, spellID) then
            order[#order + 1] = { spellID = spellID, afterNative = 0 }
        end
    end

    return order
end

function CDM:SetUngroupedCustomBuffOrder(specID, list)
    if not specID or not self.db then return end
    if not self.db.ungroupedCustomBuffOrder then
        self.db.ungroupedCustomBuffOrder = {}
    end
    self.db.ungroupedCustomBuffOrder[specID] = list
end

local function OnPlayerDead()
    if not next(CB.activeBuffs) then return end
    local toClear = {}
    for spellID in pairs(CB.activeBuffs) do
        toClear[#toClear + 1] = spellID
    end
    for i = 1, #toClear do
        DeactivateCustomBuff(toClear[i])
    end
end

local CUSTOM_BUFF_EVENTS = {
    UNIT_SPELLCAST_SUCCEEDED        = OnSpellCastSucceeded,
    UNIT_SPELLCAST_SENT             = OnSpellCastSent,
    UNIT_AURA                       = OnBloodlustAura,
    SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = OnGlowShow,
    SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = OnGlowHide,
    PLAYER_DEAD                     = OnPlayerDead,
}

function CDM:InitializeCustomBuffs()
    local eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        local fn = CUSTOM_BUFF_EVENTS[event]
        if fn then fn(event, ...) end
    end)
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    eventFrame:RegisterEvent("PLAYER_DEAD")

    self:RebuildGlowFilters()
end

CDM:RegisterRefreshCallback("customBuffs", function()
    CDM:UpdateCustomBuffs()
end, 50, { "BUFF_DATA", "LAYOUT", "STYLE" })
