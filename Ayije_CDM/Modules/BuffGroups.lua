local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
local API = CDM.API
local CDM_C = CDM.CONST
local Pixel = CDM.Pixel
local Snap = Pixel.Snap
local LSM = LibStub("LibSharedMedia-3.0")
local IsSafeNumber = CDM.IsSafeNumber

local GetTime = GetTime
local IsPlayerSpell = IsPlayerSpell
local table_wipe = table.wipe
local table_sort = table.sort

CDM.buffGroupContainers = {}

local containers = CDM.buffGroupContainers

local GCU = CDM.GroupContainerUtils
local BGP = CDM.BuffGroupPlaceholders
local ReleaseGroupPlaceholders = BGP.ReleaseGroup

local function GetContainerForAnchorTarget(anchorTarget)
    local anchorContainers = CDM.anchorContainers
    if not anchorContainers then return nil end
    if anchorTarget == "essential" then
        return anchorContainers[CDM_C.VIEWERS.ESSENTIAL]
    end
    if anchorTarget == "buff" then
        return anchorContainers[CDM_C.VIEWERS.BUFF]
    end
    return nil
end

local bgDescriptor = GCU.CreateDescriptor({
    containers = containers,
    namePrefix = "Ayije_CDM_BuffGroup",
    callbackPrefix = "CDM_BuffGroup_",
    getSets = function() return CDM.BuffGroupSets end,
})

local GetFrameData = CDM.GetFrameData
local NormalizeToBase = CDM.NormalizeToBase
local layoutCtx = CDM._LayoutCtx
local DeriveSelfPoint = layoutCtx.DeriveSelfPoint
local GetStableFrameSortID = layoutCtx.GetStableFrameSortID

local EnsureAuraNotificationHook

local scratchSpellOrder = {}
local scratchSpellSlot = {}
local scratchActiveSpellIDs = {}
local scratchGroupSpellLookup = {}
local scratchPlaceholderBySpell = {}
local scratchActiveSet = {}
local scratchSlotToRawSpell = {}

local notificationThrottles = {}
local SOUND_THROTTLE = 1
local playerIsDead = false
local hadGroupedBuffGlows = false
local groupedGlowCleanupGeneration = 0
local groupedGlowCleanupActiveGeneration = 0

local function UpdatePlayerDeathState()
    playerIsDead = UnitIsDeadOrGhost("player") and true or false
end

local function AreBuffNotificationsReady()
    if playerIsDead then
        return false
    end
    if not CDM.loginFinished then
        return false
    end
    if CDM.loadingScreenActive then
        return false
    end
    return CDM.viewersReady == true
end

local function IsBuffNotificationThrottled(spellID, onHide, channel)
    if not spellID or not channel then
        return true
    end

    local channelBit = (channel == "tts") and 1 or 0
    local key = spellID * 4 + (onHide and 2 or 0) + channelBit
    local now = GetTime()
    local last = notificationThrottles[key]
    if last and now - last < SOUND_THROTTLE then
        return true
    end

    notificationThrottles[key] = now
    return false
end

local function PlayBuffSound(soundName, spellID, onHide)
    if not soundName then return end
    if IsBuffNotificationThrottled(spellID, onHide, "sound") then return end
    local path = LSM:Fetch("sound", soundName)
    if path then PlaySoundFile(path, "Master") end
end

local function PlayBuffTTS(text, spellID, onHide)
    if not text or text == "" then return end
    local voiceType = Enum and Enum.TtsVoiceType and Enum.TtsVoiceType.Standard or 0
    local voiceID = C_TTSSettings and C_TTSSettings.GetVoiceOptionID and C_TTSSettings.GetVoiceOptionID(voiceType)
    if not voiceID then return end
    if IsBuffNotificationThrottled(spellID, onHide, "tts") then return end
    local speechRate = (C_TTSSettings and C_TTSSettings.GetSpeechRate and C_TTSSettings.GetSpeechRate()) or 0
    local speechVolume = (C_TTSSettings and C_TTSSettings.GetSpeechVolume and C_TTSSettings.GetSpeechVolume()) or 100
    pcall(C_VoiceChat.SpeakText, voiceID, text, speechRate, speechVolume, false)
end

local function PlayBuffOverrideNotification(ov, spellID, onHide)
    if type(ov) ~= "table" or not spellID then
        return false
    end

    if ov.ttsEnabled and ((onHide and ov.ttsOnHideEnabled) or (not onHide and ov.ttsOnShowEnabled)) then
        local text = ov[onHide and "ttsOnHide" or "ttsOnShow"]
        text = (text and text ~= "") and text or C_Spell.GetSpellName(spellID)
        PlayBuffTTS(text, spellID, onHide)
        return true
    end

    if ov.soundEnabled and ((onHide and ov.soundOnHideEnabled ~= false) or (not onHide and ov.soundOnShowEnabled ~= false)) then
        local soundName = ov[onHide and "soundOnHide" or "soundOnShow"]
        if soundName then
            PlayBuffSound(soundName, spellID, onHide)
            return true
        end
    end

    return false
end

local function MarkSafe(set, id)
    if IsSafeNumber(id) then set[id] = true end
end

local function BuildActiveSpellSet()
    table_wipe(scratchActiveSet)
    local buffViewer = _G[CDM_C.VIEWERS.BUFF]
    if buffViewer and buffViewer.itemFramePool then
        for frame in buffViewer.itemFramePool:EnumerateActive() do
            MarkSafe(scratchActiveSet, frame.GetSpellID and frame:GetSpellID())
            local fd = GetFrameData(frame)
            local catID = fd and fd.buffCategorySpellID
            if catID and catID ~= false then MarkSafe(scratchActiveSet, catID) end
            local info = frame.GetCooldownInfo and frame:GetCooldownInfo()
            if info then
                MarkSafe(scratchActiveSet, info.spellID)
                if info.overrideSpellID and info.overrideSpellID ~= info.spellID then
                    MarkSafe(scratchActiveSet, info.overrideSpellID)
                end
                if info.overrideTooltipSpellID then
                    MarkSafe(scratchActiveSet, info.overrideTooltipSpellID)
                end
            end
        end
    end
    local CB = CDM.CustomBuffs
    if CB and CB.activeBuffs then
        for sid, buffData in pairs(CB.activeBuffs) do
            if buffData and buffData.frame and buffData.frame:IsShown() then
                MarkSafe(scratchActiveSet, sid)
            end
        end
    end
    return scratchActiveSet
end

local function IsSpellActiveInViewer(spellID, cachedSet)
    if CDM.db and CDM.db.customBuffRegistry and CDM.db.customBuffRegistry[spellID] then
        return true
    end
    if cachedSet and cachedSet[spellID] then return true end
    if IsPlayerSpell(spellID) then return true end
    return false
end

if API then
    rawset(API, "BuildActiveSpellSet", function()
        return BuildActiveSpellSet()
    end)

    rawset(API, "IsSpellActiveInViewer", function(_, spellID, cachedSet)
        return IsSpellActiveInViewer(spellID, cachedSet)
    end)
end

local function ResolveSpellOverrideEntry(overrideMap, spellID)
    return CDM:ResolveBuffOverrideEntry(overrideMap, spellID)
end

local function BuildGroupSpellLookup(spells)
    table_wipe(scratchGroupSpellLookup)
    if type(spells) ~= "table" then
        return scratchGroupSpellLookup
    end

    for _, listedID in ipairs(spells) do
        if listedID then
            scratchGroupSpellLookup[listedID] = true
        end
    end

    return scratchGroupSpellLookup
end

local function IsSpellMarkedActive(spellID, activeSpellIDs)
    return activeSpellIDs[spellID] == true
end

local function BuildStaticSlotLayout(groupData, activeSpellIDs, activeSpellSet, groupSpellLookup)
    table_wipe(scratchSpellSlot)
    table_wipe(scratchPlaceholderBySpell)
    table_wipe(scratchSlotToRawSpell)
    local nextSlot = 0

    for _, sid in ipairs(groupData.spells or {}) do
        local ov = groupData.spellOverrides
        local spellOv = ov and ResolveSpellOverrideEntry(ov, sid) or nil
        local isTracked = activeSpellSet and activeSpellSet[sid] or false
        local wantPlaceholder = spellOv and spellOv.placeholder and isTracked or false
        scratchPlaceholderBySpell[sid] = wantPlaceholder or nil

        if isTracked then
            scratchSlotToRawSpell[nextSlot] = sid
            if not scratchSpellSlot[sid] then scratchSpellSlot[sid] = nextSlot end
            nextSlot = nextSlot + 1
        end
    end

    return scratchSpellSlot, scratchPlaceholderBySpell, nextSlot
end

local PositionFrameAtSlot = layoutCtx.PositionFrameAtSlot

local OverrideCooldownText = layoutCtx.OverrideCooldownText
local GetCooldownFontRegions = layoutCtx.GetCooldownFontRegions
local OverrideCooldownRegions = layoutCtx.OverrideCooldownRegions

local function GetSpellOverride(groupData, spellID)
    return ResolveSpellOverrideEntry(groupData and groupData.spellOverrides, spellID)
end

local function SetCooldownTextHidden(frame, hidden)
    local cd = frame.Cooldown
    if cd then
        if cd.SetHideCountdownNumbers then
            cd:SetHideCountdownNumbers(hidden)
        end
        local t = cd.Text or cd.text
        if t then
            if hidden then t:Hide(); t:SetAlpha(0) else t:Show(); t:SetAlpha(1) end
        end
        local regions = GetCooldownFontRegions(cd)
        for _, region in ipairs(regions) do
            if hidden then region:Hide(); region:SetAlpha(0) else region:Show(); region:SetAlpha(1) end
        end
    end
    if frame.Time then
        if hidden then frame.Time:Hide(); frame.Time:SetAlpha(0) else frame.Time:Show(); frame.Time:SetAlpha(1) end
    end
    if frame.Duration then
        if hidden then frame.Duration:Hide(); frame.Duration:SetAlpha(0) else frame.Duration:Show(); frame.Duration:SetAlpha(1) end
    end
end

function CDM:RestoreCooldownTextIfHidden(frame)
    local frameData = GetFrameData(frame)
    if frameData.cdmCooldownTextHidden then
        SetCooldownTextHidden(frame, false)
        frameData.cdmCooldownTextHidden = nil
    end
end

function CDM:HideCooldownTextIfFlagged(frame)
    local frameData = GetFrameData(frame)
    if frameData.cdmCooldownTextHidden then
        SetCooldownTextHidden(frame, true)
    end
end

local function HideFrameVisuals(frame, frameData)
    if frame.Icon then frame.Icon:SetAlpha(0) end
    if frame.Cooldown and frame.Cooldown.SetDrawSwipe then
        frame.Cooldown:SetDrawSwipe(false)
    end
    if frameData.borderFrame and frameData.borderFrame.border then
        frameData.borderFrame.border:Hide()
    end
    frameData.cdmVisualsHidden = true
end

local function RestoreFrameVisuals(frame, frameData)
    if frame.Icon then frame.Icon:SetAlpha(1) end
    if frame.Cooldown and frame.Cooldown.SetDrawSwipe then
        frame.Cooldown:SetDrawSwipe(true)
    end
    if frameData.borderFrame and frameData.borderFrame.border then
        frameData.borderFrame.border:Show()
    end
    frameData.cdmVisualsHidden = nil
end

function CDM:RestoreVisualsIfHidden(frame)
    local frameData = GetFrameData(frame)
    if frameData.cdmVisualsHidden then
        RestoreFrameVisuals(frame, frameData)
    end
end

-------------------------------------------------------------------------------
--  Per-spell Custom Icon
--  Swaps ONLY the icon artwork -- the tracked aura/spell, its duration, stacks
--  and every other behaviour stay bound to the real spell. The override stores
--  customIcon = { kind = "spell"|"item", id = <number> }.
--
--  RefreshSpellTexture is the only writer of a viewer item's icon texture (it
--  runs from every RefreshData and from SPELL_UPDATE_ICON), so the stamp is
--  re-asserted from a post-hook on it. That hook MUST be installed on the frame
--  INSTANCE: the leaf mixins' functions are copied onto each item frame when
--  the frame is created, so hooking the mixin table would never fire for frames
--  that already existed -- the custom icon would revert on every cast.
--
--  On clear, the real icon is re-derived via C_Spell.GetSpellTexture rather
--  than by calling the frame's own RefreshSpellTexture: running Blizzard mixin
--  code from insecure context can write tainted values into the frame's table.
-------------------------------------------------------------------------------
local function ResolveCustomIconTexture(ov)
    local ci = ov and ov.customIcon
    if type(ci) ~= "table" then return nil end
    local id = ci.id
    if not IsSafeNumber(id) or id <= 0 then return nil end
    if ci.kind == "item" then
        local tex = C_Item.GetItemIconByID(id)
        if not tex then
            C_Item.RequestLoadItemDataByID(id)
        end
        return tex
    end
    return C_Spell.GetSpellTexture(id)
end

CDM.ResolveBuffCustomIconTexture = ResolveCustomIconTexture

local ApplyCustomIcon

-- Re-resolves the override that applies to whatever spell the frame currently
-- shows. Frames are pooled and can be recycled onto a different spell between
-- repaints, so this must not trust a cached entry.
local function ResolveCustomIconOverrideForFrame(frame, frameData)
    local sets = CDM.BuffGroupSets
    local sid = frameData.buffCategorySpellID
    if sid and sets and sets.grouped and sets.groups then
        local groupIdx = sets.grouped[sid]
        local groupData = groupIdx and sets.groups[groupIdx]
        if groupData then
            return GetSpellOverride(groupData, sid)
        end
    end

    local baseSpellID = CDM.GetBaseSpellID and CDM.GetBaseSpellID(frame)
    if IsSafeNumber(baseSpellID) then
        local ov = CDM:GetUngroupedBuffOverride(baseSpellID)
        if ov then return ov end
    end
    if sid then
        return CDM:GetUngroupedBuffOverride(sid)
    end
    return nil
end

-- Re-assert entry point for the per-frame RefreshSpellTexture hook.
local function ReassertCustomIcon(frame)
    if not CDM.buffCustomIconsInUse then return end
    local frameData = GetFrameData(frame)
    if not frameData then return end
    ApplyCustomIcon(frame, frameData, ResolveCustomIconOverrideForFrame(frame, frameData))
end

ApplyCustomIcon = function(frame, frameData, ov)
    if not CDM.buffCustomIconsInUse then return end

    local icon = frame.Icon
    if not icon or not icon.SetTexture then return end

    local texture = ResolveCustomIconTexture(ov)

    if texture then
        if not frameData.cdmCustomIconHooked and frame.RefreshSpellTexture then
            frameData.cdmCustomIconHooked = true
            hooksecurefunc(frame, "RefreshSpellTexture", ReassertCustomIcon)
        end
        icon:SetTexture(texture)
        frameData.cdmCustomIconOn = true
    elseif frameData.cdmCustomIconOn then
        -- Only restore once the frame has a resolvable spell. A nil id means the
        -- identity is transiently unavailable, not that the user cleared the
        -- setting -- keep the flag armed so a later pass re-evaluates.
        local sid = CDM.GetBaseSpellID and CDM.GetBaseSpellID(frame)
        if IsSafeNumber(sid) and sid > 0 then
            frameData.cdmCustomIconOn = nil
            local real = C_Spell.GetSpellTexture(sid)
            if real then icon:SetTexture(real) end
        end
    end
end

local function ApplyGlowForGroupedFrame(frame, specID)
    if not (frame and CDM.Glow) then return end
    local frameData = GetFrameData(frame)
    if not specID then
        CDM.Glow:RequestBuffGlow(frame, false, nil, nil)
        if frameData then
            frameData.cdmGroupedGlowCleanupGeneration = groupedGlowCleanupActiveGeneration
        end
        hadGroupedBuffGlows = false
        return
    end

    local hasBuffGlows = CDM.HasAnySpellGlowConfigured and CDM:HasAnySpellGlowConfigured(specID) or false
    if not hasBuffGlows then
        if hadGroupedBuffGlows then
            groupedGlowCleanupGeneration = groupedGlowCleanupGeneration + 1
            groupedGlowCleanupActiveGeneration = groupedGlowCleanupGeneration
            hadGroupedBuffGlows = false
        end

        if groupedGlowCleanupActiveGeneration ~= 0
            and frameData
            and frameData.cdmGroupedGlowCleanupGeneration ~= groupedGlowCleanupActiveGeneration then
            frameData.cdmGroupedGlowCleanupGeneration = groupedGlowCleanupActiveGeneration
            CDM.Glow:RequestBuffGlow(frame, false, nil, nil)
        end
        return
    end

    hadGroupedBuffGlows = true

    local glowEnabled, glowColor, glowSourceID = false, nil, nil
    if CDM.ResolveBuffGlowState then
        glowEnabled, glowColor, glowSourceID = CDM:ResolveBuffGlowState(frame, specID, true)
    end
    CDM.Glow:RequestBuffGlow(frame, glowEnabled, glowColor, glowSourceID)
end

function CDM:CreateBuffGroupContainer(groupIndex)
    return bgDescriptor:GetOrCreateContainer(groupIndex)
end

function CDM:UpdateBuffGroupContainerPosition(groupIndex)
    local sets = self.BuffGroupSets
    if not sets or not sets.groups then return end
    local groupData = sets.groups[groupIndex]
    if not groupData then return end
    bgDescriptor:UpdateContainerPosition(groupIndex, groupData, GetContainerForAnchorTarget)
end

local scratchBgActiveIndices = {}

function CDM:UpdateAllBuffGroupContainers()
    local sets = self.BuffGroupSets
    if not sets or not sets.groups then
        for idx, container in pairs(containers) do
            container:Hide()
            ReleaseGroupPlaceholders(idx)
        end
        bgDescriptor:SyncCallbacks(GetContainerForAnchorTarget)
        return
    end

    local activeIndices = scratchBgActiveIndices
    table_wipe(activeIndices)
    for groupIndex, groupData in ipairs(sets.groups) do
        local container = bgDescriptor:GetOrCreateContainer(groupIndex)
        bgDescriptor:UpdateContainerPosition(groupIndex, groupData, GetContainerForAnchorTarget)
        local at = groupData.anchorTarget or "screen"
        if not container:IsShown() and at ~= "essential" and at ~= "buff" and at ~= "playerFrame" then
            container:Show()
        end
        activeIndices[groupIndex] = true
    end

    for idx, container in pairs(containers) do
        if not activeIndices[idx] then
            container:Hide()
            ReleaseGroupPlaceholders(idx)
        end
    end

    bgDescriptor:SyncCallbacks(GetContainerForAnchorTarget)
end


function CDM:PositionBuffGroupFrames(groupIndex, frames, activeSpellSetParam, repositionOnly)
    local sets = self.BuffGroupSets
    if not sets or not sets.groups then return end

    local groupData = sets.groups[groupIndex]
    if not groupData then return end

    local container = bgDescriptor:GetOrCreateContainer(groupIndex)

    if not container:IsShown() then
        for _, frame in ipairs(frames) do
            frame:Hide()
        end
        ReleaseGroupPlaceholders(groupIndex)
        return
    end

    local grow = groupData.grow
    if grow ~= "RIGHT" and grow ~= "LEFT" and grow ~= "UP" and grow ~= "DOWN" and grow ~= "CENTER_H" and grow ~= "CENTER_V" then
        grow = "RIGHT"
    end
    local spacing = groupData.spacing or 4
    local iconW = groupData.iconWidth or 30
    local iconH = groupData.iconHeight or 30
    local anchorPoint = groupData.anchorPoint or "CENTER"
    local selfPoint = DeriveSelfPoint(anchorPoint, grow)
    local iconWSnapped = Snap(iconW)
    local iconHSnapped = Snap(iconH)
    local spacingSnapped = Snap(spacing)
    local count = #frames
    local shownCount = 0
    for _, f in ipairs(frames) do
        if f:IsShown() then shownCount = shownCount + 1 end
    end
    local isStatic = groupData.staticDisplay and groupData.spells
    local layoutCount
    if isStatic then
        layoutCount = #groupData.spells
    else
        layoutCount = shownCount > 0 and shownCount or count
    end

    container:SetSize(iconWSnapped, iconHSnapped)

    -- The container is only one icon wide; publish the real icon count.
    CDM.buffGroupLayoutCounts = CDM.buffGroupLayoutCounts or {}
    CDM.buffGroupLayoutCounts[groupIndex] = layoutCount

    if count == 0 and not isStatic then
        ReleaseGroupPlaceholders(groupIndex)
        return
    end

    local spellSlot
    local activeSpellSet
    local placeholderBySpell
    if groupData.spells then
        table_wipe(scratchSpellOrder)
        for i, sid in ipairs(groupData.spells) do
            if not scratchSpellOrder[sid] then scratchSpellOrder[sid] = i end
        end
        if count > 1 then
            GCU.AssignGroupSortKeys(frames, scratchSpellOrder, "buffCategorySpellID")
            table_sort(frames, function(a, b)
                local aKey = GetFrameData(a).cdmSortKey
                local bKey = GetFrameData(b).cdmSortKey
                if aKey ~= bKey then return aKey < bKey end
                return GetStableFrameSortID(a) < GetStableFrameSortID(b)
            end)
        end
    end

    if isStatic then
        activeSpellSet = activeSpellSetParam or BuildActiveSpellSet()
        table_wipe(scratchActiveSpellIDs)
        for _, frame in ipairs(frames) do
            if frame:IsShown() then
                local sid = GetFrameData(frame).buffCategorySpellID
                if sid then
                    scratchActiveSpellIDs[sid] = true
                end
            end
        end
        local groupSpellLookup = BuildGroupSpellLookup(groupData.spells)
        spellSlot, placeholderBySpell, layoutCount = BuildStaticSlotLayout(groupData, scratchActiveSpellIDs, activeSpellSet, groupSpellLookup)
        if layoutCount <= 0 then
            ReleaseGroupPlaceholders(groupIndex)
            return
        end
    else
        spellSlot = nil
    end


    local countPos, countOX, countOY, countFS, countColor, cdFS, cdColor, specID
    if not repositionOnly then
        countPos = groupData.countPosition or "BOTTOMRIGHT"
        countOX = groupData.countOffsetX or 0
        countOY = groupData.countOffsetY or 0
        countFS = groupData.countFontSize or 15
        countColor = groupData.countColor or { r = 1, g = 1, b = 1, a = 1 }
        cdFS = groupData.cooldownFontSize or 12
        cdColor = groupData.cooldownColor or { r = 1, g = 1, b = 1 }
        specID = CDM.GetCurrentSpecID and CDM:GetCurrentSpecID() or nil
    end

    local shownIdx = 0
    for i, frame in ipairs(frames) do
        if not repositionOnly then
            EnsureAuraNotificationHook(frame)
        end
        local idx
        local rawSpellID
        if spellSlot then
            local sid = GetFrameData(frame).buffCategorySpellID
            if sid then
                idx = spellSlot[sid]
                if idx then
                    rawSpellID = scratchSlotToRawSpell[idx]
                end
            end
            if not idx then
                frame:Hide()
                BGP.SyncGroupedFrameState(frame, nil, nil, nil)
            end
        else
            if frame:IsShown() then
                idx = shownIdx
                shownIdx = shownIdx + 1
            else
                idx = layoutCount + (i - 1)
            end
        end
        if idx then
        frame:ClearAllPoints()
        PositionFrameAtSlot(frame, container, idx, iconWSnapped, iconHSnapped, spacingSnapped, grow, layoutCount, anchorPoint, selfPoint)

        if not repositionOnly then
            self:ApplyStyle(frame, CDM_C.VIEWERS.BUFF)
            frame:SetSize(iconWSnapped, iconHSnapped)
            if frame.Icon then
                CDM_C.ApplyIconTexCoord(frame.Icon, CDM_C.GetEffectiveZoomAmount(), iconWSnapped, iconHSnapped)
            end

            local frameData = GetFrameData(frame)
            local fSpellID = frameData.buffCategorySpellID
            local spellOv = GetSpellOverride(groupData, fSpellID)
            local useTextOv = spellOv and spellOv.textOverride

            local fCountPos = (useTextOv and spellOv.countPosition) or countPos
            local fCountOX  = (useTextOv and spellOv.countOffsetX)  or countOX
            local fCountOY  = (useTextOv and spellOv.countOffsetY)  or countOY
            local fCountFS  = (useTextOv and spellOv.countFontSize)  or countFS
            local fCountColor = (useTextOv and spellOv.countColor)  or countColor
            local fCdFS     = (useTextOv and spellOv.cooldownFontSize) or cdFS
            local fCdColor  = (useTextOv and spellOv.cooldownColor) or cdColor
            local fCdPixelSize = fCdFS and Pixel.FontSize(fCdFS)

            local countText = frame.Applications and frame.Applications.Applications
            if countText then
                local fCountPixelSize = fCountFS and Pixel.FontSize(fCountFS)
                local cs = frameData.countStyle
                if not cs
                    or cs.fs ~= fCountPixelSize
                    or cs.pos ~= fCountPos
                    or cs.ox ~= fCountOX
                    or cs.oy ~= fCountOY
                    or cs.r ~= fCountColor.r
                    or cs.g ~= fCountColor.g
                    or cs.b ~= fCountColor.b then
                    if fCountPixelSize then
                        local fontPath, _, fontFlags = countText:GetFont()
                        if fontPath then
                            countText:SetFont(fontPath, fCountPixelSize, fontFlags)
                        end
                    end
                    if fCountColor then
                        countText:SetTextColor(fCountColor.r, fCountColor.g, fCountColor.b, fCountColor.a or 1)
                    end
                    countText:ClearAllPoints()
                    Pixel.SetPoint(countText, fCountPos, frame, fCountPos, fCountOX, fCountOY)
                    frameData.countStyle = {
                        fs = fCountPixelSize, pos = fCountPos,
                        ox = fCountOX, oy = fCountOY,
                        r = fCountColor.r, g = fCountColor.g, b = fCountColor.b,
                    }
                end
            end

            local fHideCooldown = spellOv and spellOv.hideCooldown

            if fHideCooldown then
                SetCooldownTextHidden(frame, true)
                frameData.cdmCooldownTextHidden = true
            else
                if frameData.cdmCooldownTextHidden then
                    SetCooldownTextHidden(frame, false)
                    frameData.cdmCooldownTextHidden = nil
                end
                if fCdFS or fCdColor then
                    local cd = frame.Cooldown
                    if cd then
                        OverrideCooldownText(cd.Text or cd.text, fCdPixelSize, fCdColor)
                        OverrideCooldownRegions(cd, fCdPixelSize, fCdColor)
                    end
                    OverrideCooldownText(frame.Time, fCdPixelSize, fCdColor)
                    OverrideCooldownText(frame.Duration, fCdPixelSize, fCdColor)
                end
            end

            ApplyCustomIcon(frame, frameData, spellOv)

            local fHideVisuals = spellOv and spellOv.hideVisuals

            if fHideVisuals then
                HideFrameVisuals(frame, frameData)
            elseif frameData.cdmVisualsHidden then
                RestoreFrameVisuals(frame, frameData)
            end

            if fHideVisuals then
                if CDM.Glow then CDM.Glow:RequestBuffGlow(frame, false, nil, nil) end
            else
                ApplyGlowForGroupedFrame(frame, specID)
            end
        end

        if isStatic then
            local phEligible = rawSpellID and placeholderBySpell and placeholderBySpell[rawSpellID] and true or false
            BGP.SyncGroupedFrameState(frame, groupIndex, rawSpellID, phEligible)
        else
            BGP.SyncGroupedFrameState(frame, nil, nil, nil)
        end
        end

    end

    if isStatic then
        BGP.ReconcileGroup(groupIndex, {
            spellSlot = spellSlot,
            placeholderBySpell = placeholderBySpell,
            groupData = groupData,
            container = container,
            iconW = iconW,
            iconH = iconH,
            iconWPx = iconWSnapped,
            iconHPx = iconHSnapped,
            spacingPx = spacingSnapped,
            grow = grow,
            layoutCount = layoutCount,
            anchorPoint = anchorPoint,
            selfPoint = selfPoint,
            activeSpellIDs = scratchActiveSpellIDs,
            positionFrameAtSlot = PositionFrameAtSlot,
            isSpellMarkedActive = IsSpellMarkedActive,
        })
    else
        ReleaseGroupPlaceholders(groupIndex)
    end

end

function CDM:ApplyGroupStyleOverrides()
    local sets = self.BuffGroupSets
    if not sets or not sets.groups or not sets.grouped then return end

    local viewer = _G[CDM_C.VIEWERS.BUFF]
    if not viewer or not viewer.itemFramePool then return end

    local specID = self.GetCurrentSpecID and self:GetCurrentSpecID() or nil

    for frame in viewer.itemFramePool:EnumerateActive() do
        local fd = GetFrameData(frame)
        local spellID = fd.buffCategorySpellID
        if spellID then
            local groupIdx = sets.grouped[spellID]
            if groupIdx then
                local groupData = sets.groups[groupIdx]
                if groupData then
                    local iconW = groupData.iconWidth or 30
                    local iconH = groupData.iconHeight or 30
                    local iconWSnapped = Snap(iconW)
                    local iconHSnapped = Snap(iconH)
                    frame:SetSize(iconWSnapped, iconHSnapped)
                    if frame.Icon then
                        CDM_C.ApplyIconTexCoord(frame.Icon, CDM_C.GetEffectiveZoomAmount(), iconWSnapped, iconHSnapped)
                    end

                    local spellOv = GetSpellOverride(groupData, spellID)
                    local useTextOv = spellOv and spellOv.textOverride

                    local countPos = (useTextOv and spellOv.countPosition) or groupData.countPosition or "BOTTOMRIGHT"
                    local countOX  = (useTextOv and spellOv.countOffsetX)  or groupData.countOffsetX or 0
                    local countOY  = (useTextOv and spellOv.countOffsetY)  or groupData.countOffsetY or 0
                    local countFS  = (useTextOv and spellOv.countFontSize) or groupData.countFontSize or 15
                    local countColor = (useTextOv and spellOv.countColor) or groupData.countColor or { r = 1, g = 1, b = 1, a = 1 }
                    local cdFS     = (useTextOv and spellOv.cooldownFontSize) or groupData.cooldownFontSize or 12
                    local cdColor  = (useTextOv and spellOv.cooldownColor) or groupData.cooldownColor or { r = 1, g = 1, b = 1 }
                    local cdPixelSize = cdFS and Pixel.FontSize(cdFS)

                    local countText = frame.Applications and frame.Applications.Applications
                    if countText then
                        local countPixelSize = countFS and Pixel.FontSize(countFS)
                        if countPixelSize then
                            local fontPath, _, fontFlags = countText:GetFont()
                            if fontPath then countText:SetFont(fontPath, countPixelSize, fontFlags) end
                        end
                        if countColor then
                            countText:SetTextColor(countColor.r, countColor.g, countColor.b, countColor.a or 1)
                        end
                        countText:ClearAllPoints()
                        Pixel.SetPoint(countText, countPos, frame, countPos, countOX, countOY)
                    end

                    local fHideCooldown = spellOv and spellOv.hideCooldown
                    if fHideCooldown then
                        SetCooldownTextHidden(frame, true)
                        fd.cdmCooldownTextHidden = true
                    else
                        if fd.cdmCooldownTextHidden then
                            SetCooldownTextHidden(frame, false)
                            fd.cdmCooldownTextHidden = nil
                        end
                        if cdFS or cdColor then
                            local cd = frame.Cooldown
                            if cd then
                                OverrideCooldownText(cd.Text or cd.text, cdPixelSize, cdColor)
                                OverrideCooldownRegions(cd, cdPixelSize, cdColor)
                            end
                            OverrideCooldownText(frame.Time, cdPixelSize, cdColor)
                            OverrideCooldownText(frame.Duration, cdPixelSize, cdColor)
                        end
                    end

                    ApplyCustomIcon(frame, fd, spellOv)

                    local fHideVisuals = spellOv and spellOv.hideVisuals
                    if fHideVisuals then
                        HideFrameVisuals(frame, fd)
                    elseif fd.cdmVisualsHidden then
                        RestoreFrameVisuals(frame, fd)
                    end

                    if fHideVisuals then
                        if CDM.Glow then CDM.Glow:RequestBuffGlow(frame, false, nil, nil) end
                    else
                        ApplyGlowForGroupedFrame(frame, specID)
                    end
                end
            end
        end
    end
end

-- Gate for the custom-icon work: skips the per-frame hook install and the
-- override lookups entirely for the (common) case of no custom icons saved.
-- Once armed it stays armed for the session so a cleared icon still gets
-- restored on the pass that follows the clear.
local function RescanCustomIconGate()
    if CDM.buffCustomIconsInUse then return end
    local db = CDM.db
    if not db then return end

    local function mapHasCustomIcon(map)
        if type(map) ~= "table" then return false end
        for _, entry in pairs(map) do
            if type(entry) == "table" and type(entry.customIcon) == "table" then
                return true
            end
        end
        return false
    end

    if type(db.ungroupedBuffOverrides) == "table" then
        for _, specOv in pairs(db.ungroupedBuffOverrides) do
            if mapHasCustomIcon(specOv) then
                CDM.buffCustomIconsInUse = true
                return
            end
        end
    end

    if type(db.buffGroups) == "table" then
        for _, specGroups in pairs(db.buffGroups) do
            if type(specGroups) == "table" then
                for _, group in pairs(specGroups) do
                    if type(group) == "table" and mapHasCustomIcon(group.spellOverrides) then
                        CDM.buffCustomIconsInUse = true
                        return
                    end
                end
            end
        end
    end
end

CDM.RescanBuffCustomIconGate = RescanCustomIconGate

CDM:RegisterRefreshCallback("buffGroups", function()
    table_wipe(notificationThrottles)
    RescanCustomIconGate()
    BGP.ReleaseAll()
    CDM:MarkSpecDataDirty()
    CDM:RefreshSpecData()
    CDM:UpdateAllBuffGroupContainers()
end, 29, { "BUFF_DATA" })

CDM:RegisterRefreshCallback("buffGroups_postViewer", function()
    CDM:UpdateAllBuffGroupContainers()
end, 45, { "LAYOUT", "BUFF_DATA" })

CDM:RegisterEvent("PLAYER_LOGIN", RescanCustomIconGate)

UpdatePlayerDeathState()
CDM:RegisterEvent("PLAYER_ENTERING_WORLD", UpdatePlayerDeathState)
CDM:RegisterEvent("PLAYER_ENTERING_WORLD", function() table_wipe(notificationThrottles) end)
CDM:RegisterEvent("PLAYER_DEAD", UpdatePlayerDeathState)
CDM:RegisterEvent("PLAYER_ALIVE", UpdatePlayerDeathState)
CDM:RegisterEvent("PLAYER_UNGHOST", UpdatePlayerDeathState)

function CDM:GetUngroupedBuffOverride(spellID)
    if not spellID then return nil end
    local specID = self.GetCurrentSpecID and self:GetCurrentSpecID()
    if not specID then return nil end
    local db = self.db
    if not db or not db.ungroupedBuffOverrides then return nil end
    local specOv = db.ungroupedBuffOverrides[specID]
    if not specOv then return nil end
    return ResolveSpellOverrideEntry(specOv, spellID)
end

function CDM:PlayCustomBuffNotification(spellID, onHide)
    if not spellID then return end
    if not AreBuffNotificationsReady() then return end

    local matchType, matchID, groupIdx = CDM.CheckIDAgainstRegistry(spellID)
    if matchType == "buffgroup" and groupIdx then
        local sets = self.BuffGroupSets
        local groupData = sets and sets.groups and sets.groups[groupIdx]
        local ov = GetSpellOverride(groupData, matchID)
        PlayBuffOverrideNotification(ov, matchID, onHide)
        return
    end

    local ov = self:GetUngroupedBuffOverride(spellID)
    if ov then
        PlayBuffOverrideNotification(ov, spellID, onHide)
    end
end

local function OnBuffAuraNotification(frame, onHide)
    if not AreBuffNotificationsReady() then return end
    local candidates = CDM.GetSpellIDCandidates and CDM:GetSpellIDCandidates(frame)
    if not candidates then return end

    for _, id in ipairs(candidates) do
        local matchType, matchID, groupIdx = CDM.CheckIDAgainstRegistry(id)
        if matchType == "buffgroup" and groupIdx then
            local sets = CDM.BuffGroupSets
            local groupData = sets and sets.groups and sets.groups[groupIdx]
            local ov = GetSpellOverride(groupData, matchID)
            PlayBuffOverrideNotification(ov, matchID, onHide)
            return
        end
    end

    for _, id in ipairs(candidates) do
        local ov = CDM:GetUngroupedBuffOverride(id)
        if ov then
            PlayBuffOverrideNotification(ov, id, onHide)
            return
        end
    end
end

local auraHookedFrames = setmetatable({}, { __mode = "k" })

EnsureAuraNotificationHook = function(frame)
    if auraHookedFrames[frame] then return end
    auraHookedFrames[frame] = true
    if frame.TriggerAuraAppliedAlert then
        hooksecurefunc(frame, "TriggerAuraAppliedAlert", function(f)
            OnBuffAuraNotification(f, false)
        end)
    end
    if frame.TriggerAuraRemovedAlert then
        hooksecurefunc(frame, "TriggerAuraRemovedAlert", function(f)
            OnBuffAuraNotification(f, true)
        end)
    end
end

function CDM:ApplyUngroupedBuffOverrides(frame)
    if not frame then return end
    EnsureAuraNotificationHook(frame)
    local frameData = GetFrameData(frame)
    local ov
    local matchedSpellID
    local baseSpellID = frame.GetBaseSpellID and frame:GetBaseSpellID()
    if IsSafeNumber(baseSpellID) then
        ov = self:GetUngroupedBuffOverride(baseSpellID)
        if ov then matchedSpellID = baseSpellID end
    end
    if not ov and self.GetSpellIDCandidates then
        local candidates = self:GetSpellIDCandidates(frame)
        for _, candidateID in ipairs(candidates) do
            ov = self:GetUngroupedBuffOverride(candidateID)
            if ov then
                matchedSpellID = candidateID
                break
            end
        end
    end

    -- Runs even with no override so a frame whose custom icon was just cleared
    -- (or that was recycled onto a different spell) gets its real icon back.
    ApplyCustomIcon(frame, frameData, ov)

    if not ov then return end
    matchedSpellID = NormalizeToBase(matchedSpellID) or matchedSpellID

    local db = self.db

    if ov.hideCooldown then
        SetCooldownTextHidden(frame, true)
        frameData.cdmCooldownTextHidden = true
    end

    if ov.hideVisuals then
        HideFrameVisuals(frame, frameData)
        if CDM.Glow then CDM.Glow:RequestBuffGlow(frame, false, nil, nil) end
    end

    local useTextOv = ov.textOverride

    if not ov.hideCooldown then
        local cdFS = (useTextOv and ov.cooldownFontSize) or (db and db.buffCooldownFontSize or 12)
        local cdColor = (useTextOv and ov.cooldownColor) or (db and db.buffCooldownColor)
        local cdPixelSize = cdFS and Pixel.FontSize(cdFS)
        local cd = frame.Cooldown
        if cd then
            OverrideCooldownText(cd.Text or cd.text, cdPixelSize, cdColor)
            OverrideCooldownRegions(cd, cdPixelSize, cdColor)
        end
        OverrideCooldownText(frame.Time, cdPixelSize, cdColor)
        OverrideCooldownText(frame.Duration, cdPixelSize, cdColor)
    end

    local countText = frame.Applications and frame.Applications.Applications
    if countText then
        local countFS = (useTextOv and ov.countFontSize) or (db and db.countFontSize or 15)
        local countColor = (useTextOv and ov.countColor) or (db and db.countColor)
        local countPos = (useTextOv and ov.countPosition) or (db and db.countPositionMain or "TOP")
        local countOX = (useTextOv and ov.countOffsetX) or (db and db.countOffsetXMain or 0)
        local countOY = (useTextOv and ov.countOffsetY) or (db and db.countOffsetYMain or 0)
        if countFS then
            local fontPath, _, fontFlags = countText:GetFont()
            if fontPath then
                countText:SetFont(fontPath, Pixel.FontSize(countFS), fontFlags)
            end
        end
        if countColor then
            countText:SetTextColor(countColor.r, countColor.g, countColor.b, countColor.a or 1)
        end
        countText:ClearAllPoints()
        Pixel.SetPoint(countText, countPos, frame, countPos, countOX, countOY)
    end
end
