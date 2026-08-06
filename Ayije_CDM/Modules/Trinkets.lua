local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]

local CDM_C = CDM and CDM.CONST or {}

local TRINKET_SLOT_1 = 13
local TRINKET_SLOT_2 = 14

local injectionScratch = {}

local TRINKETS_COOLDOWN_WATCH_OWNER = "CDM_Trinkets"
local TRINKETS_SPELL_WATCH_OWNER = "CDM_Trinkets_Spells"

local getItemSpell = C_Item and C_Item.GetItemSpell
local GetInventoryItemID = GetInventoryItemID
local GetInventoryItemCooldown = GetInventoryItemCooldown

local trinketsTracker

function CDM.GetTrinketIconFrames()
    if not trinketsTracker.IsEnabled() then return nil end
    return trinketsTracker.GetIconFrames()
end

-- A trinket slot participates in the cooldown viewer only when the user has
-- added it on the Cooldowns page for the active spec (db.cooldownTrinkets),
-- or assigned its sentinel ID to a cooldown group.
local function IsTrinketSlotTracked(slotID)
    local bySpec = CDM.db and CDM.db.cooldownTrinkets
    if not bySpec then return false end
    local specIndex = GetSpecialization()
    local specID = specIndex and GetSpecializationInfo(specIndex)
    local slots = specID and bySpec[specID]
    return slots ~= nil and slots[slotID] == true
end

local function GetTrinketGroupIndex(frame)
    if not frame.slotID then return nil end
    local sets = CDM.CooldownGroupSets
    local grouped = sets and sets.grouped
    if not grouped then return nil end
    local getSentinel = CDM_C.GetTrinketSentinelForSlot
    if not getSentinel then return nil end
    return grouped[getSentinel(frame.slotID)]
end

local function ResetTrinketTrackerFrame(frame)
    frame.slotID = nil
    frame.itemID = nil
    frame.spellID = nil
    frame.isOnUse = nil
    if frame.Icon then
        frame.Icon:SetTexture(nil)
        frame.Icon:SetDesaturation(0)
    end
    local fd = CDM.GetFrameData(frame)
    fd.cdmCooldownStyled = nil
end

local function CreateIconFrame(slotID)
    local iconFramePool = trinketsTracker._iconFramePool
    local container = trinketsTracker.GetContainer()
    local size = CDM.GetTrackerIconSize("trinketsIconWidth", "trinketsIconHeight")
    local opts = { size = size, named = false }
    local frame = CDM.AcquireFromTrackerPool(iconFramePool, container, "CDM_Trinket_", slotID, opts)
    frame.slotID = slotID
    frame.itemID = nil
    frame.spellID = nil
    frame.isOnUse = false
    return frame
end

local function AcquireTrinketFrames()
    local iconFrames = trinketsTracker.GetIconFrames()
    if not iconFrames[1] then
        iconFrames[1] = CreateIconFrame(TRINKET_SLOT_1)
    end
    if not iconFrames[2] then
        iconFrames[2] = CreateIconFrame(TRINKET_SLOT_2)
    end
end

local function RefreshTrinketData(frame)
    if not frame or not frame.slotID then return end

    local prevItemID = frame.itemID
    local prevSpellID = frame.spellID
    local prevIsOnUse = frame.isOnUse

    local itemID = GetInventoryItemID("player", frame.slotID)
    frame.itemID = itemID

    if itemID then
        local texture = C_Item.GetItemIconByID(itemID)
        if texture and frame.Icon then
            frame.Icon:SetTexture(texture)
        end

        local spellName, spellID
        if getItemSpell then
            spellName, spellID = getItemSpell(itemID)
        end
        if spellID then
            frame.spellID = spellID
            frame.isOnUse = true
        else
            frame.spellID = nil
            frame.isOnUse = false
        end
    else
        frame.itemID = nil
        frame.spellID = nil
        frame.isOnUse = false
        if frame.Icon then
            frame.Icon:SetTexture(nil)
        end
    end

    local dataChanged = (prevItemID ~= frame.itemID) or (prevSpellID ~= frame.spellID) or (prevIsOnUse ~= frame.isOnUse)
    if dataChanged then
        CDM.GetFrameData(frame).cdmCooldownStyled = false
    end

    return dataChanged
end

local function OnTrinketCooldownWatchChanged()
    trinketsTracker.Queue(false)
end

local function OnTrinketSpellWatchChanged(cooldownsChanged, chargesChanged)
    if cooldownsChanged or chargesChanged then
        trinketsTracker.Queue(false)
    end
end

local function RegisterTrinketCooldownWatches()
    if not (CDM.WatchInventorySlotCooldown and CDM.UnwatchAllCooldowns) then return end
    CDM.UnwatchAllCooldowns(TRINKETS_COOLDOWN_WATCH_OWNER)
    CDM.WatchInventorySlotCooldown(TRINKETS_COOLDOWN_WATCH_OWNER, TRINKET_SLOT_1, OnTrinketCooldownWatchChanged)
    CDM.WatchInventorySlotCooldown(TRINKETS_COOLDOWN_WATCH_OWNER, TRINKET_SLOT_2, OnTrinketCooldownWatchChanged)
end

local function RegisterTrinketSpellWatches()
    if not (CDM.WatchSpellState and CDM.UnwatchAllSpellStates) then return end
    CDM.UnwatchAllSpellStates(TRINKETS_SPELL_WATCH_OWNER)
    local iconFrames = trinketsTracker.GetIconFrames()
    for _, frame in ipairs(iconFrames) do
        if frame.spellID then
            CDM.WatchSpellState(TRINKETS_SPELL_WATCH_OWNER, frame.spellID, OnTrinketSpellWatchChanged)
        end
    end
end

local function UpdateIcon(frame)
    if not frame or not frame:IsShown() then return end

    local isOnCooldown = false

    if frame.slotID then
        local start, duration, enable = GetInventoryItemCooldown("player", frame.slotID)
        if start and duration and duration > CDM_C.ITEM_COOLDOWN_GCD_MIN and enable == 1 then
            local fd = CDM.GetFrameData(frame)
            if not fd.cdmDurationObj then
                fd.cdmDurationObj = C_DurationUtil.CreateDuration()
            end
            fd.cdmDurationObj:SetTimeFromStart(start, duration)
            frame.Cooldown:SetCooldownFromDurationObject(fd.cdmDurationObj)
            isOnCooldown = true
        else
            frame.Cooldown:Clear()
        end
    else
        frame.Cooldown:Clear()
    end

    if frame.Icon then
        frame.Icon:SetDesaturation(isOnCooldown and 1 or 0)
    end

    if isOnCooldown then
        local fd = CDM.GetFrameData(frame)
        if not fd.cdmCooldownStyled then
            if CDM.ApplyStyle and CDM_C.VIEWERS and CDM_C.VIEWERS.ESSENTIAL then
                CDM:ApplyStyle(frame, CDM_C.VIEWERS.ESSENTIAL)
            end
            fd.cdmCooldownStyled = true
        end
    end
end

local function OnTrinketsStyleRefresh()
    CDM:UpdateTrinkets()
end

CDM.RegisterViewerDesc("CDM_Trinkets", {
    widthKey     = "trinketsIconWidth",
    heightKey    = "trinketsIconHeight",
    cdFontKey    = "trinketsCooldownFontSize",
    cdColorKey   = "cooldownColor",
    chargeKey    = "chargeFontSize",
    isCooldown   = true,
    hasKeybind   = true,
    hookType     = "cooldown",
})

trinketsTracker = CDM.CreateTracker({
    containerName       = "CDM_TrinketsContainer",
    viewerName          = "CDM_Trinkets",
    positionCallbackKey = "CDM_Trinkets",
    iconWidthKey        = "trinketsIconWidth",
    iconHeightKey       = "trinketsIconHeight",
    anchorPointKey      = "trinketsAnchorPoint",
    offsetXKey          = "trinketsOffsetX",
    offsetYKey          = "trinketsOffsetY",
    moduleKey           = "trinkets",
    watchOwnerKey       = nil,
    showCharges         = false,
    styleRefreshPriority = 17,
    useEntryPool        = false,
    useDispatch         = true,
    UpdateIcon          = UpdateIcon,
    resetFrame          = ResetTrinketTrackerFrame,
    UpdateContainerPosition = function() end,
    onStyleRefresh      = OnTrinketsStyleRefresh,
})

-- Expose internal pool for frame management
trinketsTracker._iconFramePool = {}

function CDM.GetTrinketInjectionFrames()
    if not trinketsTracker.IsEnabled() then return nil end

    local iconFrames = trinketsTracker.GetIconFrames()
    local count = 0
    for _, frame in ipairs(iconFrames) do
        if frame.itemID
            and IsTrinketSlotTracked(frame.slotID)
            and not GetTrinketGroupIndex(frame)
        then
            count = count + 1
            injectionScratch[count] = frame
        end
    end
    for i = count + 1, #injectionScratch do
        injectionScratch[i] = nil
    end
    return count > 0 and injectionScratch or nil
end

-- Appends equipped trinket frames assigned to a cooldown group into the
-- reanchor group buckets (keyed by group index).
function CDM.CollectGroupedTrinketFrames(buckets)
    if not trinketsTracker.IsEnabled() then return end

    local getSentinel = CDM_C.GetTrinketSentinelForSlot
    if not getSentinel then return end

    for _, frame in ipairs(trinketsTracker.GetIconFrames()) do
        if frame.slotID and frame.itemID then
            local groupIdx = GetTrinketGroupIndex(frame)
            if groupIdx then
                CDM.GetFrameData(frame).cdGroupSpellID = getSentinel(frame.slotID)
                frame.viewerFrame = _G[CDM_C.VIEWERS.ESSENTIAL]
                if frame:GetParent() ~= UIParent then
                    frame:SetParent(UIParent)
                end
                if not buckets[groupIdx] then buckets[groupIdx] = {} end
                buckets[groupIdx][#buckets[groupIdx] + 1] = frame
            end
        end
    end
end

function CDM:InitializeTrinkets()
    trinketsTracker.Initialize()

    AcquireTrinketFrames()

    local updater = CDM.CreateTrackerUpdater({
        "BAG_UPDATE_DELAYED",
        "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_SPECIALIZATION_CHANGED",
    }, function(_, event, arg1)
        if event == "PLAYER_EQUIPMENT_CHANGED" then
            if arg1 == TRINKET_SLOT_1 or arg1 == TRINKET_SLOT_2 then
                trinketsTracker.InvalidateStyle()
                CDM:UpdateTrinkets()
            end
        else
            CDM:UpdateTrinkets()
        end
    end)

    CDM.trinketsUpdater = updater
    RegisterTrinketCooldownWatches()
    RegisterTrinketSpellWatches()
end

local function EnableTrinkets()
    trinketsTracker.Enable()

    AcquireTrinketFrames()

    local updater = CDM.trinketsUpdater
    if updater then
        updater:RegisterEvent("BAG_UPDATE_DELAYED")
        updater:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        updater:RegisterEvent("PLAYER_ENTERING_WORLD")
        updater:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    end
    RegisterTrinketCooldownWatches()
    RegisterTrinketSpellWatches()
end

local function DisableTrinkets()
    local updater = CDM.trinketsUpdater
    if updater then
        updater:UnregisterEvent("BAG_UPDATE_DELAYED")
        updater:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
        updater:UnregisterEvent("PLAYER_ENTERING_WORLD")
        updater:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    end
    if CDM.UnwatchAllCooldowns then
        CDM.UnwatchAllCooldowns(TRINKETS_COOLDOWN_WATCH_OWNER)
    end
    if CDM.UnwatchAllSpellStates then
        CDM.UnwatchAllSpellStates(TRINKETS_SPELL_WATCH_OWNER)
    end

    for _, frame in ipairs(trinketsTracker.GetIconFrames()) do
        frame:Hide()
    end

    trinketsTracker.Disable()
end

function CDM:UpdateTrinkets()
    local container = trinketsTracker.GetContainer()
    if not container then return end

    local iconFrames = trinketsTracker.GetIconFrames()
    local anyTrinketDataChanged = false
    for _, frame in ipairs(iconFrames) do
        if RefreshTrinketData(frame) then
            anyTrinketDataChanged = true
        end
    end
    if anyTrinketDataChanged then
        RegisterTrinketSpellWatches()
    end

    local styleDirty = trinketsTracker.ConsumeStyleDirty()
    local queueEssentialViewer = anyTrinketDataChanged or styleDirty

    for _, frame in ipairs(iconFrames) do
        local shouldShow = frame.itemID ~= nil
            and (IsTrinketSlotTracked(frame.slotID) or GetTrinketGroupIndex(frame) ~= nil)
        local wasShown = frame:IsShown()
        if shouldShow then
            frame:Show()
            UpdateIcon(frame)
        else
            frame:Hide()
        end
        if wasShown ~= shouldShow then
            queueEssentialViewer = true
        end
    end

    -- Icons ride the Essential viewer (or their group's container); the
    -- tracker's own container is never shown.
    container:Hide()

    if queueEssentialViewer then
        local essViewer = _G[CDM_C.VIEWERS.ESSENTIAL]
        if essViewer then CDM:ForceReanchor(essViewer) end
    end
end

local function OnTrinketsProfileApplied()
    trinketsTracker.OnProfileApplied()
    local container = trinketsTracker.GetContainer()
    if container then
        CDM.InvalidateTrackerAnchorCache(container)
    end
end

-- Patch 12.1 tracks trinkets natively via the EquipSlot* viewer categories.
-- Running this tracker alongside it shows every trinket twice, so it stands
-- down when the client provides native tracking. `trinketsForceEnable` lets a
-- user keep the custom row anyway (for its styling / grouping behaviour).
local function IsSupersededByNativeTracking()
    if CDM_C.GetConfigValue and CDM_C.GetConfigValue("trinketsForceEnable", false) then
        return false
    end
    return CDM_C.HasNativeEquipSlotTracking and CDM_C.HasNativeEquipSlotTracking()
end

CDM.IsTrinketsSupersededByNative = IsSupersededByNativeTracking

local function ReconcileTrinkets()
    if IsSupersededByNativeTracking() then
        if trinketsTracker.IsEnabled() then DisableTrinkets() end
        return
    end
    if not trinketsTracker.IsInitialized() then CDM:InitializeTrinkets() end
    if not trinketsTracker.IsEnabled() then EnableTrinkets() end
    CDM:UpdateTrinkets()
end

CDM.ReconcileTrinkets = ReconcileTrinkets
CDM.OnTrinketsProfileApplied = OnTrinketsProfileApplied
