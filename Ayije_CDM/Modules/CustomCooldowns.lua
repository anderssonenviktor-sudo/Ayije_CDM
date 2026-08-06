local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]

local CDM_C = CDM and CDM.CONST or {}

local CUSTOMCD_COOLDOWN_WATCH_OWNER = "CDM_CustomCDs"
local CUSTOMCD_SPELL_WATCH_OWNER = "CDM_CustomCDs_Spells"

local GetSpellChargeDuration = C_Spell.GetSpellChargeDuration
local GetSpellCooldownDuration = C_Spell.GetSpellCooldownDuration
local GetSpellCharges = C_Spell.GetSpellCharges
local GetSpellTexture = C_Spell.GetSpellTexture
local GetContainerItemCooldown = C_Container.GetItemCooldown
local GetItemCount = C_Item.GetItemCount
local IsEquippedItem = C_Item.IsEquippedItem
local IsSpellInSpellBook = C_SpellBook.IsSpellInSpellBook
local TruncateWhenZero = C_StringUtil.TruncateWhenZero

local GetCustomItemSentinelForItem = CDM_C.GetCustomItemSentinelForItem
local DesaturationCurve = CDM_C.DesaturationCurve
local VIEWERS = CDM_C.VIEWERS

local injectionScratch = {}
local iconEntries = {}
local lastCustomSpecID = nil
local itemResolveFrame
local itemResolvePending = {}

local customTracker

local _, playerClass = UnitClass("player")
local PACT_OF_GLUTTONY_TALENT_ID = 386689

-- Items formerly built into the Racials tracker, offered as one-click adds
-- in the options "Add Custom" dialog. Behaviors (combat lockout, warlock
-- gating, alternate item IDs) apply whenever the matching item ID is tracked,
-- no matter how it was added.
-- combatLockout: cooldown starts after leaving combat
local BUILTIN_ITEMS = {
    [241304] = { spellID = 1234768, alternateItemID = 241305 },                            -- Silvermoon Health Potion
    [241308] = { spellID = 1236616, alternateItemID = 241309 },                            -- Light's Potential
    [5512]   = { spellID = 6262, combatLockout = true, requiresWarlockAccess = true },     -- Healthstone
    [224464] = { spellID = 452930, class = "WARLOCK", requiresWarlockAccess = true },      -- Demonic Healthstone
}

local BUILTIN_ITEM_ORDER = { 5512, 224464, 241304, 241308 }

function CDM.GetCustomCooldownBuiltinItems()
    return BUILTIN_ITEM_ORDER, BUILTIN_ITEMS
end

local function PlayerHasWarlockAccess()
    if playerClass == "WARLOCK" then
        return true
    end

    if not IsInGroup() then
        return false
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local _, classTag = UnitClass("raid" .. i)
            if classTag == "WARLOCK" then
                return true
            end
        end
        return false
    end

    for i = 1, GetNumSubgroupMembers() do
        local _, classTag = UnitClass("party" .. i)
        if classTag == "WARLOCK" then
            return true
        end
    end

    return false
end

local function PlayerHasPactOfGluttony()
    if playerClass ~= "WARLOCK" then
        return false
    end

    return IsPlayerSpell(PACT_OF_GLUTTONY_TALENT_ID) == true
end

-- Bag count for an item entry; falls back to the alternate item ID (potion
-- variants) and records which of the two is the active one for cooldown queries.
local function GetItemDisplayCount(entry)
    local count = GetItemCount(entry.id, false, true)
    entry._activeItemID = entry.id
    if (not count or count <= 0) and entry.alternateItemID then
        local altCount = GetItemCount(entry.alternateItemID, false, true)
        if altCount and altCount > 0 then
            entry._activeItemID = entry.alternateItemID
            return altCount
        end
    end
    return count or 0
end

-- Identity ID: the number stored in cooldown groups / the ungrouped cooldown
-- order. Spells use their spell ID directly; items use a sentinel so item IDs
-- can never collide with spell IDs.
local function GetStoredEntryIdentity(stored)
    if stored.isItem then
        return GetCustomItemSentinelForItem(stored.id)
    end
    return stored.id
end

CDM.GetCustomCooldownIdentityForEntry = GetStoredEntryIdentity

local function GetStoredEntries(specID)
    local bySpec = CDM.db and CDM.db.customCooldownEntries
    return bySpec and specID and bySpec[specID] or nil
end

function CDM.GetCustomCooldownEntryForID(specID, identityID)
    local list = GetStoredEntries(specID)
    if not list then return nil end
    for _, stored in ipairs(list) do
        if GetStoredEntryIdentity(stored) == identityID then
            return stored
        end
    end
    return nil
end

function CDM.GetCustomCooldownIconFrames()
    if not (customTracker and customTracker.IsEnabled()) then return nil end
    return customTracker.GetIconFrames()
end

-- True when the given spell is already provided by Blizzard's cooldown viewer
-- for the current spec (Essential or Utility) — those must be dragged from
-- the viewer grid instead of added as custom entries.
local function IsSpellTrackedByViewer(spellID)
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
        and C_CooldownViewer.GetCooldownViewerCooldownInfo
        and Enum and Enum.CooldownViewerCategory) then
        return false
    end
    local IsSafeNumber = CDM.IsSafeNumber
    for _, cat in ipairs(CDM_C.VIEWER_CATEGORIES_COOLDOWN) do
        local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if cooldownIDs then
            for _, cdID in ipairs(cooldownIDs) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info then
                    if (IsSafeNumber(info.spellID) and info.spellID == spellID)
                        or (IsSafeNumber(info.overrideSpellID) and info.overrideSpellID == spellID)
                        or (IsSafeNumber(info.overrideTooltipSpellID) and info.overrideTooltipSpellID == spellID) then
                        return true
                    end
                    if info.linkedSpellIDs then
                        for _, lid in ipairs(info.linkedSpellIDs) do
                            if IsSafeNumber(lid) and lid == spellID then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

local function EntryIsAvailable(entry)
    if entry.isItem then
        if entry.classRestriction and entry.classRestriction ~= playerClass then
            return false
        end
        -- Pact of Gluttony replaces the regular Healthstone with the Demonic one.
        if entry.id == 5512 and PlayerHasPactOfGluttony() then
            return false
        end
        if entry.id == 224464 and not PlayerHasPactOfGluttony() then
            return false
        end

        local count = GetItemDisplayCount(entry)
        if count > 0 then
            return true
        end
        if entry.requiresWarlockAccess and not PlayerHasWarlockAccess() then
            return false
        end
        if entry.combatLockout and entry.inCombatLockout then
            return true
        end
        if IsEquippedItem and IsEquippedItem(entry.id) then
            return true
        end
        return false
    end

    -- A spell that Blizzard's viewer started tracking (e.g. after a talent
    -- change) is hidden here so it never shows as a duplicate icon.
    if entry._viewerTracked then
        return false
    end

    if entry._spellbookCached ~= nil then
        return entry._spellbookCached
    end
    local known = IsSpellInSpellBook(entry.id)
        or IsSpellInSpellBook(entry.id, Enum.SpellBookSpellBank.Pet)
    entry._spellbookCached = known
    return known
end

function CDM.IsCustomCooldownEntryActive(identityID)
    for _, entry in ipairs(iconEntries) do
        if entry.identityID == identityID then
            return EntryIsAvailable(entry)
        end
    end
    return false
end

local function ResetCustomTrackerFrame(frame)
    frame.cdmCustomIdentityID = nil
    frame.cdmCustomEntry = nil
    frame.spellID = nil
    frame.itemID = nil
    frame.itemSpellID = nil
    frame._spellbookCached = nil
    frame.viewerFrame = nil
    if frame.Icon then
        frame.Icon:SetTexture(nil)
        frame.Icon:SetDesaturation(0)
    end
    local fd = CDM.GetFrameData(frame)
    fd.cdGroupSpellID = nil
    fd.cdmDurationObj = nil
end

local RefreshEntryTexture
RefreshEntryTexture = function(entry)
    local frame = entry.frame
    if not (frame and frame.Icon) then return end
    local texture
    if entry.isItem then
        texture = C_Item.GetItemIconByID(entry.id)
        if not texture then
            -- Item data loads asynchronously; retry once it had time to arrive.
            C_Item.RequestLoadItemDataByID(entry.id)
            if not entry._texRetryPending then
                entry._texRetryPending = true
                C_Timer.After(0.5, function()
                    entry._texRetryPending = nil
                    RefreshEntryTexture(entry)
                end)
            end
        end
    else
        texture = GetSpellTexture(CDM.GetEffectiveSpellID(entry.id))
    end
    if texture then
        frame.Icon:SetTexture(texture)
    end
end

local function BindEntryFrame(entry)
    local frame = entry.frame
    local boundNow = false
    if not frame then
        local pool = customTracker._iconFramePool
        local container = customTracker.GetContainer()
        local size = CDM.GetTrackerIconSize("customCooldownsIconWidth", "customCooldownsIconHeight")
        local opts = { size = size, showCharges = true, named = false }
        frame = CDM.AcquireFromTrackerPool(pool, container, "CDM_CustomCD_", entry.identityID, opts)
        -- Charge widgets must exist before ApplyStyle runs so the essential
        -- viewer charge styling (and group text overrides) covers them.
        CDM.EnsureTrackerChargeWidgets(frame)
        entry.frame = frame
        boundNow = true
    end
    frame.cdmCustomIdentityID = entry.identityID
    frame.cdmCustomEntry = entry
    if entry.isItem then
        frame.spellID = nil
        frame.itemID = entry.id
        frame.itemSpellID = entry.itemSpellID
    else
        frame.spellID = entry.id
        frame.itemID = nil
        frame.itemSpellID = nil
    end
    if boundNow then
        RefreshEntryTexture(entry)
        if frame.Icon then
            frame.Icon:SetDesaturation(0)
        end
    end
    return frame, boundNow
end

local function ReleaseEntryFrame(entry)
    local frame = entry and entry.frame
    if not frame then return end
    entry.frame = nil
    CDM.ReleaseToTrackerPool(customTracker._iconFramePool, frame, ResetCustomTrackerFrame)
end

local function HasVisibleItemCooldown(startTime, duration)
    return startTime and duration and duration > CDM_C.ITEM_COOLDOWN_GCD_MIN
end

local function UpdateIcon(frame)
    if not frame or not frame:IsShown() then return end

    local hasCharges = false
    local chargeValue
    local desatDurationObject = nil
    local desatSpellID = nil
    local desatIsChargeSpell = false
    local itemCooldownActive = false

    if frame.itemID then
        local itemID = frame.itemID
        local itemSpellID = frame.itemSpellID
        local entry = frame.cdmCustomEntry

        local itemCount
        if entry then
            itemCount = GetItemDisplayCount(entry)
        else
            itemCount = GetItemCount(itemID, false, true)
        end
        local queryItemID = (entry and entry._activeItemID) or itemID
        local inCombatLockout = entry and entry.inCombatLockout or false

        if itemSpellID then
            local realDur = GetSpellCooldownDuration(itemSpellID)
            local itemCdStart, itemCdDuration = GetContainerItemCooldown(queryItemID)

            desatDurationObject = realDur
            desatSpellID = itemSpellID

            if HasVisibleItemCooldown(itemCdStart, itemCdDuration) then
                local fd = CDM.GetFrameData(frame)
                if not fd.cdmDurationObj then
                    fd.cdmDurationObj = C_DurationUtil.CreateDuration()
                end
                fd.cdmDurationObj:SetTimeFromStart(itemCdStart, itemCdDuration)
                frame.Cooldown:SetCooldownFromDurationObject(fd.cdmDurationObj)
                itemCooldownActive = true
            elseif realDur then
                frame.Cooldown:SetCooldownFromDurationObject(realDur)
            else
                frame.Cooldown:Clear()
            end
        else
            local startTime, durationSeconds = GetContainerItemCooldown(queryItemID)
            if HasVisibleItemCooldown(startTime, durationSeconds) then
                local fd = CDM.GetFrameData(frame)
                if not fd.cdmDurationObj then
                    fd.cdmDurationObj = C_DurationUtil.CreateDuration()
                end
                fd.cdmDurationObj:SetTimeFromStart(startTime, durationSeconds)
                frame.Cooldown:SetCooldownFromDurationObject(fd.cdmDurationObj)
                itemCooldownActive = true
            else
                frame.Cooldown:Clear()
            end
        end

        -- The cooldown of combat-lockout items (Healthstone) only starts once
        -- combat ends; show the icon desaturated with no timer until then.
        if inCombatLockout then
            frame.Cooldown:Clear()
            itemCooldownActive = true
        end

        if itemCount and itemCount > 0 then
            hasCharges = true
            chargeValue = itemCount
        end
    elseif frame.spellID then
        local effectiveID = CDM.GetEffectiveSpellID(frame.spellID)

        local chargeDur = GetSpellChargeDuration(effectiveID)
        local scd = GetSpellCooldownDuration(effectiveID)
        local chargeInfo = GetSpellCharges(effectiveID)
        local isChargeSpell = chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1

        desatDurationObject = scd
        desatSpellID = effectiveID
        desatIsChargeSpell = isChargeSpell == true

        local durObj = (isChargeSpell and chargeDur) or scd
        if durObj then
            frame.Cooldown:SetCooldownFromDurationObject(durObj)
        else
            frame.Cooldown:Clear()
        end

        if isChargeSpell and chargeInfo.currentCharges then
            hasCharges = true
            chargeValue = TruncateWhenZero(chargeInfo.currentCharges)
        end
    end

    if frame.Icon then
        if itemCooldownActive then
            frame.Icon:SetDesaturation(1)
        elseif desatDurationObject and desatDurationObject.EvaluateRemainingDuration then
            if CDM.IsOnRealCooldown(desatSpellID, desatIsChargeSpell) then
                frame.Icon:SetDesaturation(desatDurationObject:EvaluateRemainingDuration(DesaturationCurve, Enum.DurationTimeModifier.RealTime) or 0)
            else
                frame.Icon:SetDesaturation(0)
            end
        else
            frame.Icon:SetDesaturation(0)
        end
    end

    -- Styling comes from ApplyStyle (essential viewer / group overrides);
    -- only the value and visibility are managed here.
    local chargeText = CDM.EnsureTrackerChargeWidgets(frame)
    if chargeText then
        if hasCharges then
            chargeText:SetText(chargeValue)
            chargeText:Show()
        else
            chargeText:Hide()
        end
    end
end

local function OnCustomCooldownWatchChanged()
    customTracker.Queue(false)
end

local function OnCustomSpellWatchChanged(cooldownsChanged, chargesChanged)
    if cooldownsChanged or chargesChanged then
        customTracker.Queue(false)
    end
end

local function RegisterCustomWatches()
    if CDM.UnwatchAllCooldowns then
        CDM.UnwatchAllCooldowns(CUSTOMCD_COOLDOWN_WATCH_OWNER)
    end
    if CDM.UnwatchAllSpellStates then
        CDM.UnwatchAllSpellStates(CUSTOMCD_SPELL_WATCH_OWNER)
    end
    for _, entry in ipairs(iconEntries) do
        if entry.isItem then
            if entry.itemSpellID and CDM.WatchSpellState then
                CDM.WatchSpellState(CUSTOMCD_SPELL_WATCH_OWNER, entry.itemSpellID, OnCustomSpellWatchChanged)
            elseif CDM.WatchItemCooldown then
                CDM.WatchItemCooldown(CUSTOMCD_COOLDOWN_WATCH_OWNER, entry.id, OnCustomCooldownWatchChanged)
            end
        elseif CDM.WatchSpellState then
            CDM.WatchSpellState(CUSTOMCD_SPELL_WATCH_OWNER, entry.id, OnCustomSpellWatchChanged)
        end
    end
end

local function RebuildCustomEntries()
    for _, entry in ipairs(iconEntries) do
        ReleaseEntryFrame(entry)
    end
    table.wipe(iconEntries)

    local specID = CDM:GetCurrentSpecID()
    lastCustomSpecID = specID

    local stored = GetStoredEntries(specID)
    if stored then
        for _, storedEntry in ipairs(stored) do
            local behavior = storedEntry.isItem and BUILTIN_ITEMS[storedEntry.id] or nil
            local resolvedSpellID = storedEntry.spellID or (behavior and behavior.spellID)
            if storedEntry.isItem and not resolvedSpellID then
                local _, s = C_Item.GetItemSpell(storedEntry.id)
                resolvedSpellID = s
            end
            iconEntries[#iconEntries + 1] = {
                id = storedEntry.id,
                isItem = storedEntry.isItem or false,
                identityID = GetStoredEntryIdentity(storedEntry),
                itemSpellID = storedEntry.isItem and resolvedSpellID or nil,
                alternateItemID = behavior and behavior.alternateItemID or nil,
                combatLockout = behavior and behavior.combatLockout or nil,
                requiresWarlockAccess = behavior and behavior.requiresWarlockAccess or nil,
                classRestriction = behavior and behavior.class or nil,
                _viewerTracked = (not storedEntry.isItem) and IsSpellTrackedByViewer(storedEntry.id) or nil,
            }
        end
    end

    if customTracker.IsEnabled() then
        RegisterCustomWatches()
    end
    CDM.TrimTrackerPool(customTracker._iconFramePool, #iconEntries)
end

local function GetCustomGroupIndex(entry)
    local sets = CDM.CooldownGroupSets
    local grouped = sets and sets.grouped
    return grouped and grouped[entry.identityID] or nil
end

CDM.RegisterViewerDesc("CDM_CustomCooldowns", {
    widthKey     = "customCooldownsIconWidth",
    heightKey    = "customCooldownsIconHeight",
    cdFontKey    = "cooldownFontSize",
    cdColorKey   = "cooldownColor",
    chargeKey    = "chargeFontSize",
    isCooldown   = true,
    hasKeybind   = true,
    hookType     = "cooldown",
})

customTracker = CDM.CreateTracker({
    containerName       = "CDM_CustomCooldownsContainer",
    viewerName          = "CDM_CustomCooldowns",
    positionCallbackKey = "CDM_CustomCooldowns",
    iconWidthKey        = "customCooldownsIconWidth",
    iconHeightKey       = "customCooldownsIconHeight",
    anchorPointKey      = "customCooldownsAnchorPoint",
    offsetXKey          = "customCooldownsOffsetX",
    offsetYKey          = "customCooldownsOffsetY",
    moduleKey           = "customCooldowns",
    watchOwnerKey       = nil,
    showCharges         = true,
    styleRefreshPriority = 18,
    useEntryPool        = false,
    useDispatch         = true,
    UpdateIcon          = UpdateIcon,
    resetFrame          = ResetCustomTrackerFrame,
    UpdateContainerPosition = function() end,
    onStyleRefresh      = function() CDM:UpdateCustomCooldowns() end,
})

customTracker._iconFramePool = {}

-- Ungrouped custom cooldown frames ride the Essential viewer row; the
-- layout blends them in via this accessor (see PositionEssentialOrUtilityIcons).
function CDM.GetCustomCooldownInjectionFrames()
    if not customTracker.IsEnabled() then return nil end

    local count = 0
    for _, entry in ipairs(iconEntries) do
        local frame = entry.frame
        if frame and frame:IsShown() and not GetCustomGroupIndex(entry) then
            count = count + 1
            injectionScratch[count] = frame
        end
    end
    for i = count + 1, #injectionScratch do
        injectionScratch[i] = nil
    end
    return count > 0 and injectionScratch or nil
end

-- Appends custom cooldown frames assigned to a cooldown group into the
-- reanchor group buckets (keyed by group index).
function CDM.CollectGroupedCustomCooldownFrames(buckets)
    if not customTracker.IsEnabled() then return end

    for _, entry in ipairs(iconEntries) do
        local frame = entry.frame
        if frame and frame:IsShown() then
            local groupIdx = GetCustomGroupIndex(entry)
            if groupIdx then
                CDM.GetFrameData(frame).cdGroupSpellID = entry.identityID
                frame.viewerFrame = _G[VIEWERS.ESSENTIAL]
                if frame:GetParent() ~= UIParent then
                    frame:SetParent(UIParent)
                end
                if not buckets[groupIdx] then buckets[groupIdx] = {} end
                buckets[groupIdx][#buckets[groupIdx] + 1] = frame
            end
        end
    end
end

function CDM:UpdateCustomCooldowns()
    local container = customTracker.GetContainer()
    if not container then return end

    local currentSpec = CDM:GetCurrentSpecID()
    if currentSpec ~= lastCustomSpecID then
        RebuildCustomEntries()
        customTracker.InvalidateStyle()
    end

    local styleDirty = customTracker.ConsumeStyleDirty()
    local queueEssentialViewer = styleDirty

    local iconFrames = customTracker.GetIconFrames()
    local visibleCount = 0

    for _, entry in ipairs(iconEntries) do
        local shouldShow = EntryIsAvailable(entry)
        local wasShown = entry.frame and entry.frame:IsShown() or false

        if shouldShow then
            local frame, boundNow = BindEntryFrame(entry)
            if not boundNow then
                RefreshEntryTexture(entry)
            end
            frame:Show()
            if styleDirty or boundNow or not wasShown then
                CDM:ApplyStyle(frame, VIEWERS.ESSENTIAL, true)
            end
            UpdateIcon(frame)
            visibleCount = visibleCount + 1
            iconFrames[visibleCount] = frame
        else
            ReleaseEntryFrame(entry)
        end

        local isShown = entry.frame and entry.frame:IsShown() or false
        if wasShown ~= isShown then
            queueEssentialViewer = true
        end
    end
    for i = visibleCount + 1, #iconFrames do
        iconFrames[i] = nil
    end

    -- Icons ride the Essential viewer (or their group's container); the
    -- tracker's own container is never shown.
    container:Hide()

    if queueEssentialViewer then
        local essViewer = _G[VIEWERS.ESSENTIAL]
        if essViewer then CDM:ForceReanchor(essViewer) end
    end
end

local function ResolveItemSpellAsync(storedEntry)
    C_Item.RequestLoadItemDataByID(storedEntry.id)
    itemResolvePending[storedEntry.id] = storedEntry
    if not itemResolveFrame then
        itemResolveFrame = CreateFrame("Frame")
    end
    itemResolveFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    itemResolveFrame:SetScript("OnEvent", function(self, _, loadedID, success)
        local pending = itemResolvePending[loadedID]
        if not pending then return end
        itemResolvePending[loadedID] = nil
        if not next(itemResolvePending) then
            self:UnregisterAllEvents()
            self:SetScript("OnEvent", nil)
        end
        if not success then return end
        local _, resolved = C_Item.GetItemSpell(loadedID)
        if resolved then
            pending.spellID = resolved
        end
        RebuildCustomEntries()
        CDM:UpdateCustomCooldowns()
    end)
end

-- Adds a user-entered spell or item to the custom cooldown list for a spec.
-- Returns true on success, or false plus a reason ("duplicate" | "viewer").
function CDM:AddCustomCooldownEntry(id, isItem, specID)
    specID = specID or CDM:GetCurrentSpecID()
    if not specID or not id then return false end

    if not isItem and IsSpellTrackedByViewer(id) then
        return false, "viewer"
    end

    if not CDM.db.customCooldownEntries then
        CDM.db.customCooldownEntries = {}
    end
    local list = CDM.db.customCooldownEntries[specID]
    if not list then
        list = {}
        CDM.db.customCooldownEntries[specID] = list
    end

    for _, stored in ipairs(list) do
        if stored.id == id and (stored.isItem or false) == (isItem or false) then
            return false, "duplicate"
        end
    end

    local newEntry = { id = id }
    if isItem then
        newEntry.isItem = true
        local _, spellID = C_Item.GetItemSpell(id)
        if spellID then
            newEntry.spellID = spellID
        else
            ResolveItemSpellAsync(newEntry)
        end
    end
    list[#list + 1] = newEntry

    if specID == CDM:GetCurrentSpecID() then
        RebuildCustomEntries()
        CDM:UpdateCustomCooldowns()
    end
    CDM:Refresh("CD_DATA")
    return true
end

-- Removes a custom entry by identity ID and scrubs every reference to it:
-- cooldown group spell lists/overrides, the ungrouped order, and overrides.
function CDM:RemoveCustomCooldownEntry(identityID, specID)
    specID = specID or CDM:GetCurrentSpecID()
    if not specID or not identityID then return end

    local db = CDM.db
    local list = GetStoredEntries(specID)
    if list then
        for i = #list, 1, -1 do
            if GetStoredEntryIdentity(list[i]) == identityID then
                table.remove(list, i)
            end
        end
        if not next(list) then
            db.customCooldownEntries[specID] = nil
        end
    end

    local groups = db.cooldownGroups and db.cooldownGroups[specID]
    if groups then
        for _, groupData in ipairs(groups) do
            if groupData.spells then
                for i = #groupData.spells, 1, -1 do
                    if groupData.spells[i] == identityID then
                        table.remove(groupData.spells, i)
                    end
                end
            end
            if groupData.spellOverrides then
                groupData.spellOverrides[identityID] = nil
            end
        end
    end

    local order = db.ungroupedCooldownOrder and db.ungroupedCooldownOrder[specID]
    if order then
        for i = #order, 1, -1 do
            if order[i] == identityID then
                table.remove(order, i)
            end
        end
    end

    local specOv = db.ungroupedCooldownOverrides and db.ungroupedCooldownOverrides[specID]
    if specOv then
        specOv[identityID] = nil
    end

    if specID == CDM:GetCurrentSpecID() then
        RebuildCustomEntries()
        CDM:UpdateCustomCooldowns()
    end
    CDM:Refresh("CD_DATA")
end

local function ClearItemCombatLockouts()
    for _, entry in ipairs(iconEntries) do
        if entry.inCombatLockout then
            entry.inCombatLockout = nil
        end
    end
end

local function OnCustomCombatStateChanged(isInCombat)
    if isInCombat then
        return
    end
    ClearItemCombatLockouts()
    CDM:UpdateCustomCooldowns()
end

function CDM:InitializeCustomCooldowns()
    customTracker.Initialize()

    RebuildCustomEntries()

    local updater = CDM.CreateTrackerUpdater({
        "BAG_UPDATE_DELAYED",
        "BAG_UPDATE_COOLDOWN",
        "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_ENTERING_WORLD",
        "SPELLS_CHANGED",
        "GROUP_ROSTER_UPDATE",
        "PLAYER_ROLES_ASSIGNED",
    }, function(_, event, arg1, arg2, arg3)
        if event == "SPELLS_CHANGED" then
            -- Re-evaluates both spellbook knowledge and whether Blizzard's
            -- viewer took over tracking any of the custom spells.
            RebuildCustomEntries()
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local castSpellID = arg3
            if castSpellID then
                for _, entry in ipairs(iconEntries) do
                    if entry.isItem and entry.itemSpellID == castSpellID then
                        if entry.combatLockout and InCombatLockdown() then
                            entry.inCombatLockout = true
                        end
                        break
                    end
                end
            end
        end
        CDM:UpdateCustomCooldowns()
    end)
    updater:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

    CDM.customCooldownsUpdater = updater
    CDM:RegisterCombatStateHandler(OnCustomCombatStateChanged)
    RegisterCustomWatches()
    CDM:UpdateCustomCooldowns()
end

local function EnableCustomCooldowns()
    customTracker.Enable()
    local updater = CDM.customCooldownsUpdater
    if updater then
        updater:RegisterEvent("BAG_UPDATE_DELAYED")
        updater:RegisterEvent("BAG_UPDATE_COOLDOWN")
        updater:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        updater:RegisterEvent("PLAYER_ENTERING_WORLD")
        updater:RegisterEvent("SPELLS_CHANGED")
        updater:RegisterEvent("GROUP_ROSTER_UPDATE")
        updater:RegisterEvent("PLAYER_ROLES_ASSIGNED")
        updater:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end
    RegisterCustomWatches()
    CDM:UpdateCustomCooldowns()
end

local function OnCustomCooldownsProfileApplied()
    customTracker.OnProfileApplied()
    lastCustomSpecID = nil
    local container = customTracker.GetContainer()
    if container then
        CDM.InvalidateTrackerAnchorCache(container)
    end
end

local function ReconcileCustomCooldowns()
    if not customTracker.IsInitialized() then CDM:InitializeCustomCooldowns() end
    if not customTracker.IsEnabled() then EnableCustomCooldowns() end
    CDM:UpdateCustomCooldowns()
end

CDM.ReconcileCustomCooldowns = ReconcileCustomCooldowns
CDM.OnCustomCooldownsProfileApplied = OnCustomCooldownsProfileApplied

-- Custom cooldown icons visually live in the Essential viewer, so they follow
-- its fading toggle.
if CDM.Fading and CDM.Fading.RegisterTarget then
    CDM.Fading:RegisterTarget("fadingEssential", function(a)
        local frames = CDM.GetCustomCooldownIconFrames()
        if frames then
            for _, frame in ipairs(frames) do
                frame:SetAlpha(a)
            end
        end
    end)
end
