local Runtime = _G["Ayije_CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local L = Runtime.L
local CDM_C = CDM and CDM.CONST or {}
local IsSafeNumber = API.IsSafeNumber
local UI = ns.ConfigUI
local Shared = ns.GroupEditorShared or {}

local NormalizeToBase = API.NormalizeToBase
local SharedGetDisplaySpellID = Shared.GetDisplaySpellID

local GetTrinketSlotFromSentinel = CDM_C.GetTrinketSlotFromSentinel
local GetTrinketSentinelForSlot = CDM_C.GetTrinketSentinelForSlot
local TRINKET_SLOT_IDS = CDM_C.TRINKET_SLOT_IDS or { 13, 14 }
local GetCustomItemIDFromSentinel = CDM_C.GetCustomItemIDFromSentinel
local GetNativeItemCategoryInfo = CDM_C.GetNativeItemCategoryInfo

-- Trinkets participate in the Cooldowns editor per spec: the user adds them
-- explicitly (Add Trinket / spell picker) and they are stored as tracked
-- slots in db.cooldownTrinkets[specID][slotID].
local function IsTrinketTracked(specID, slotID)
    local bySpec = CDM.db and CDM.db.cooldownTrinkets
    local slots = bySpec and specID and bySpec[specID]
    return slots ~= nil and slots[slotID] == true
end

local function SetTrinketTracked(specID, slotID, tracked)
    if not specID then return end
    if not CDM.db.cooldownTrinkets then CDM.db.cooldownTrinkets = {} end
    local slots = CDM.db.cooldownTrinkets[specID]
    if tracked then
        if not slots then
            slots = {}
            CDM.db.cooldownTrinkets[specID] = slots
        end
        slots[slotID] = true
    elseif slots then
        slots[slotID] = nil
        if not next(slots) then CDM.db.cooldownTrinkets[specID] = nil end
    end
end

local function IsCooldownBuffTracked(specID, spellID)
    local bySpec = CDM.db and CDM.db.cooldownBuffs
    local selected = bySpec and specID and bySpec[specID]
    return selected ~= nil and selected[spellID] == true
end

local function SetCooldownBuffTracked(specID, spellID, tracked)
    if not (specID and spellID) then return end
    if not CDM.db.cooldownBuffs then CDM.db.cooldownBuffs = {} end
    local selected = CDM.db.cooldownBuffs[specID]
    if tracked then
        if not selected then
            selected = {}
            CDM.db.cooldownBuffs[specID] = selected
        end
        selected[spellID] = true
    elseif selected then
        selected[spellID] = nil
        if not next(selected) then CDM.db.cooldownBuffs[specID] = nil end
    end
end

-- Returns slotID, itemID, name, icon for a trinket sentinel ID (nil otherwise).
local function GetTrinketInfoForID(spellID)
    local slotID = GetTrinketSlotFromSentinel and GetTrinketSlotFromSentinel(spellID)
    if not slotID then return nil end
    local itemID = GetInventoryItemID("player", slotID)
    local name = itemID and C_Item.GetItemNameByID(itemID)
    local icon = itemID and C_Item.GetItemIconByID(itemID)
    return slotID, itemID, name or (L["Trinket"] .. " " .. (slotID - 12)),
        icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Returns itemID, name, icon for a custom-cooldown item sentinel ID
-- (nil otherwise). Custom-cooldown spells use their spell ID as-is and go
-- through the normal spell display paths.
local function GetCustomItemInfoForID(spellID)
    local itemID = GetCustomItemIDFromSentinel and GetCustomItemIDFromSentinel(spellID)
    if not itemID then return nil end
    local name = C_Item.GetItemNameByID(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return itemID, name or (L["Item"] .. " " .. itemID),
        C_Item.GetItemIconByID(itemID) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local lookupCacheBySpec = {}

local function GetSpecLookup(specID)
    if not specID then return nil end
    local cache = lookupCacheBySpec[specID]
    if cache then return cache end
    cache = {}
    local function ingest(arr)
        if not arr then return end
        for _, entry in ipairs(arr) do
            if entry.spellID then cache[entry.spellID] = entry end
            if entry.baseSpellID and entry.baseSpellID ~= entry.spellID then
                cache[entry.baseSpellID] = entry
            end
        end
    end
    ingest(API:GetSpecEssentialCache(specID))
    ingest(API:GetSpecUtilityCache(specID))
    lookupCacheBySpec[specID] = cache
    return cache
end

local suppressPanelRefreshUntil = 0
local function SaveAndRefresh()
    lookupCacheBySpec = {}
    suppressPanelRefreshUntil = GetTime() + 0.15
    Shared.SaveVisualRefresh("CD_DATA")
end
local DestroyFrame = Shared.DestroyFrame
local CreateSlider = Shared.CreateSlider
local DOT_OVERRIDE_SPELLS = CDM_C.DOT_OVERRIDE_SPELLS
local LEFT_INSET = Shared.LEFT_INSET
local LEFT_WIDTH = Shared.LEFT_WIDTH
local SCROLL_LEFT_PAD = Shared.SCROLL_LEFT_PAD
local RIGHT_X = Shared.RIGHT_X
local ICON_SIZE = 30
local ROW_HEIGHT = 36
local GROUP_HEADER_H = 28
local ARROW_BTN_SIZE = 29
local GRID_ICON_SIZE = 44
local GRID_ICON_GAP = 4

StaticPopupDialogs["AYIJE_CDM_CONFIRM_DELETE_CD_GROUP"] = {
    text = "",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local fn = StaticPopupDialogs["AYIJE_CDM_CONFIRM_DELETE_CD_GROUP"]._pendingDelete
        if fn then fn() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CreateCooldownGroupsPanel(subPage, page)
    local dbKey = "cooldownGroups"
    local tex = subPage:CreateTexture(nil, "ARTWORK")
    tex:SetAtlas("Options_HorizontalDivider", true)
    tex:SetPoint("TOP", subPage, "TOP", 0, 0)

    local si = GetSpecialization()
    local currentSpecID = si and GetSpecializationInfo(si) or nil
    local playerSpecID = currentSpecID

    local selectedGroupIndex = nil
    local selectedSpellID = nil
    local selectedSpellGroupIndex = nil
    local expandedGroups = {}
    local RefreshAll
    local ShowSpellSettings
    local BuildIconGrid
    local SetCooldownBarView
    local cooldownBarView = "essential"
    local renameLastClickTime = 0
    local renameLastClickGroup = nil
    local renameActiveGroupIndex = nil
    local renameActiveEditBox = nil

    local function ResolveCooldownOverrideID(spellID)
        if not IsSafeNumber(spellID) or not currentSpecID then return spellID end
        local cache = GetSpecLookup(currentSpecID)
        local entry = cache and cache[spellID]
        if entry then return entry.spellID end
        return spellID
    end

    local function GetDisplaySpellID(spellID)
        return SharedGetDisplaySpellID(ResolveCooldownOverrideID(spellID))
    end

    -- Stored custom cooldown entry for an identity ID under the viewed spec
    -- (nil when the ID is not a custom entry).
    local function GetCustomEntryForID(spellID)
        if not (IsSafeNumber(spellID) and currentSpecID) then return nil end
        return API.GetCustomCooldownEntryForID
            and API.GetCustomCooldownEntryForID(currentSpecID, spellID) or nil
    end

    local function GetCustomEntriesForViewedSpec()
        local bySpec = CDM.db and CDM.db.customCooldownEntries
        return bySpec and currentSpecID and bySpec[currentSpecID] or nil
    end

    local _helpers = Shared.CreateGroupEditorHelpers({
        dbKey = dbKey,
        ungroupedDbKey = "ungroupedCooldownOverrides",
        getCurrentSpecID = function() return currentSpecID end,
        setCurrentSpecID = function(v) currentSpecID = v end,
        getPlayerSpecID = function() return playerSpecID end,
        setPlayerSpecID = function(v) playerSpecID = v end,
        normalizeToBase = NormalizeToBase,
        extraCloneFields = { "maxPerRow", "chargeFontSize", "chargeColor", "chargePosition", "chargeOffsetX", "chargeOffsetY" },
    })
    local RefreshCurrentSpecID = _helpers.RefreshCurrentSpecID
    local EnsureGroups = _helpers.EnsureGroups
    local GetSpecGroups = _helpers.GetSpecGroups
    local EnsureUngroupedOverrides = _helpers.EnsureUngroupedOverrides
    local GetUngroupedOverride = _helpers.GetUngroupedOverride
    local EnsureResolvedOverrideEntry = _helpers.EnsureResolvedOverrideEntry
    local ExtractMergedOverrideEntry = _helpers.ExtractMergedOverrideEntry
    local StoreMergedOverrideEntry = _helpers.StoreMergedOverrideEntry
    local EnsureSpellOverride = _helpers.EnsureSpellOverride
    local EnsureUngroupedOverrideEntry = _helpers.EnsureUngroupedOverrideEntry
    local CreateLayoutOnlyGroupClone = _helpers.CreateLayoutOnlyGroupClone
    local CopyGroupSettingsToSpec = _helpers.CopyGroupSettingsToSpec
    local DuplicateGroup = _helpers.DuplicateGroup

    local function RefreshLeftPanelIfNeeded()
        if RefreshAll then RefreshAll() end
    end

    local function GetPromotedBuffTexture(spellID)
        if not IsCooldownBuffTracked(currentSpecID, spellID) then return nil end
        local override = CDM.GetUngroupedBuffOverride and CDM:GetUngroupedBuffOverride(spellID)
        return CDM.ResolveBuffCustomIconTexture and CDM.ResolveBuffCustomIconTexture(override) or nil
    end

    local function IsSpellKnown(spellID)
        if not IsSafeNumber(spellID) then return false end
        if IsPlayerSpell(spellID) then return true end
        local overrideID = ResolveCooldownOverrideID(spellID)
        if overrideID ~= spellID and IsPlayerSpell(overrideID) then return true end
        if NormalizeToBase then
            local baseID = NormalizeToBase(spellID)
            if baseID and baseID ~= spellID and IsPlayerSpell(baseID) then return true end
        end
        return false
    end

    local function BuildCooldownActiveSet()
        local active = {}
        for _, vName in ipairs({ CDM_C.VIEWERS.ESSENTIAL, CDM_C.VIEWERS.UTILITY }) do
            local viewer = _G[vName]
            if viewer and viewer.itemFramePool then
                for frame in viewer.itemFramePool:EnumerateActive() do
                    local id = frame.GetSpellID and frame:GetSpellID()
                    if IsSafeNumber(id) then active[id] = true end
                    if frame.cooldownInfo then
                        local identity = CDM_C.ResolveViewerEntryIdentity(frame.cooldownInfo)
                        if IsSafeNumber(identity) then active[identity] = true end
                    end
                end
            end
        end
        local selectedBuffs = CDM.db and CDM.db.cooldownBuffs and CDM.db.cooldownBuffs[currentSpecID]
        if selectedBuffs then
            for spellID, selected in pairs(selectedBuffs) do
                if selected then active[spellID] = true end
            end
        end
        return active
    end

    local QueueLeftPanelRefresh = Shared.CreateQueueLeftPanelRefresh(subPage, function() return RefreshAll end)

    local function ResolveCooldownStableBase(spellID)
        if not IsSafeNumber(spellID) or not currentSpecID then return spellID end
        local cache = GetSpecLookup(currentSpecID)
        local entry = cache and cache[spellID]
        if entry then return entry.baseSpellID or entry.spellID end
        return spellID
    end

    local ApplyUngroupedGridOrder
    local function GetUngroupedDropLabel(sourceGroup)
        return sourceGroup and L["Remove from group"] or L["Reorder icons"]
    end

    local RegisterDropTarget, ClearDropTargets, StartDrag, EndDrag, CancelDrag
    do
        local dragDrop = Shared.CreateDragDropController({
            onDrop = function(spellID, sourceGroup, targetGroupIndex, hitDropTarget, targetInsertIndex)
                if not spellID or not currentSpecID then return end
                if not hitDropTarget then return end
                if sourceGroup == targetGroupIndex then
                    if sourceGroup and targetInsertIndex then
                        local groups = EnsureGroups()
                        local group = groups and groups[sourceGroup]
                        if group and group.spells then
                            Shared.InsertSpellInGroupList(group.spells, spellID, targetInsertIndex)
                            SaveAndRefresh()
                            RefreshLeftPanelIfNeeded()
                        end
                        return
                    end
                    -- Grid onto grid: reorder the ungrouped viewer icons.
                    if not sourceGroup and targetInsertIndex then
                        if ApplyUngroupedGridOrder(spellID, targetInsertIndex) then
                            SaveAndRefresh()
                            RefreshLeftPanelIfNeeded()
                        end
                    end
                    return
                end

                local groups = EnsureGroups()
                if not groups then return end

                if not sourceGroup and targetGroupIndex then
                    spellID = ResolveCooldownStableBase(spellID)
                end

                local srcOvData = nil
                if sourceGroup then
                    local srcGroup = groups[sourceGroup]
                    if srcGroup and srcGroup.spells then Shared.RemoveSpellFromGroupList(srcGroup.spells, spellID) end
                    if srcGroup and srcGroup.spellOverrides then
                        srcOvData = ExtractMergedOverrideEntry(srcGroup.spellOverrides, spellID)
                    end
                else
                    local specOv = EnsureUngroupedOverrides()
                    if specOv then
                        srcOvData = ExtractMergedOverrideEntry(specOv, spellID)
                    end
                end

                if targetGroupIndex then
                    local tgtGroup = groups[targetGroupIndex]
                    if tgtGroup then
                        if not tgtGroup.spells then tgtGroup.spells = {} end
                        local storedSpellID = Shared.InsertSpellInGroupList(
                            tgtGroup.spells, spellID, targetInsertIndex
                        ) or spellID
                        if srcOvData then
                            if not tgtGroup.spellOverrides then tgtGroup.spellOverrides = {} end
                            StoreMergedOverrideEntry(tgtGroup.spellOverrides, storedSpellID, srcOvData)
                        end
                        spellID = storedSpellID
                    end
                elseif srcOvData then
                    local specOv = EnsureUngroupedOverrides()
                    if specOv then StoreMergedOverrideEntry(specOv, spellID, srcOvData) end
                end

                if not targetGroupIndex and targetInsertIndex then
                    ApplyUngroupedGridOrder(spellID, targetInsertIndex)
                end

                SaveAndRefresh()
                if spellID == selectedSpellID then
                    selectedSpellGroupIndex = targetGroupIndex
                    ShowSpellSettings(spellID, targetGroupIndex)
                end
                RefreshLeftPanelIfNeeded()
            end,
        })
        RegisterDropTarget = dragDrop.RegisterDropTarget
        ClearDropTargets = dragDrop.ClearDropTargets
        StartDrag = dragDrop.StartDrag
        EndDrag = dragDrop.EndDrag
        CancelDrag = dragDrop.CancelDrag
    end

    local minGridHeight = GRID_ICON_SIZE + 8
    local gridScrollbarSpace = 18

    local iconGridFrame = CreateFrame("Frame", nil, subPage)
    iconGridFrame:SetPoint("TOPLEFT", LEFT_INSET, -26)
    iconGridFrame:SetPoint("TOPRIGHT",
        -(LEFT_INSET + GRID_ICON_SIZE * 2 + GRID_ICON_GAP * 2 + 8), -26)
    iconGridFrame:SetHeight(minGridHeight)

    local iconActionFrame = CreateFrame("Frame", nil, subPage)
    iconActionFrame:SetPoint("TOPLEFT", iconGridFrame, "TOPRIGHT", GRID_ICON_GAP, 0)
    iconActionFrame:SetPoint("TOPRIGHT", subPage, "TOPRIGHT", -LEFT_INSET, -26)
    iconActionFrame:SetHeight(minGridHeight)

    local iconActionBackground = iconActionFrame:CreateTexture(nil, "BACKGROUND")
    iconActionBackground:SetAllPoints()
    iconActionBackground:SetColorTexture(0.02, 0.02, 0.02, 0.5)

    local iconActionBorderTop = iconActionFrame:CreateTexture(nil, "BORDER")
    iconActionBorderTop:SetPoint("TOPLEFT")
    iconActionBorderTop:SetPoint("TOPRIGHT")
    iconActionBorderTop:SetHeight(1)
    iconActionBorderTop:SetColorTexture(0, 0, 0, 1)
    local iconActionBorderBottom = iconActionFrame:CreateTexture(nil, "BORDER")
    iconActionBorderBottom:SetPoint("BOTTOMLEFT")
    iconActionBorderBottom:SetPoint("BOTTOMRIGHT")
    iconActionBorderBottom:SetHeight(1)
    iconActionBorderBottom:SetColorTexture(0, 0, 0, 1)
    local iconActionBorderLeft = iconActionFrame:CreateTexture(nil, "BORDER")
    iconActionBorderLeft:SetPoint("TOPLEFT")
    iconActionBorderLeft:SetPoint("BOTTOMLEFT")
    iconActionBorderLeft:SetWidth(1)
    iconActionBorderLeft:SetColorTexture(0, 0, 0, 1)
    local iconActionBorderRight = iconActionFrame:CreateTexture(nil, "BORDER")
    iconActionBorderRight:SetPoint("TOPRIGHT")
    iconActionBorderRight:SetPoint("BOTTOMRIGHT")
    iconActionBorderRight:SetWidth(1)
    iconActionBorderRight:SetColorTexture(0, 0, 0, 1)

    local iconGridLayoutAnchor = CreateFrame("Frame", nil, subPage)
    iconGridLayoutAnchor:SetPoint("TOPLEFT", iconGridFrame, "TOPLEFT")
    iconGridLayoutAnchor:SetPoint("TOPRIGHT", iconGridFrame, "TOPRIGHT")
    iconGridLayoutAnchor:SetHeight(minGridHeight + gridScrollbarSpace)

    local iconGridBackground = iconGridFrame:CreateTexture(nil, "BACKGROUND")
    iconGridBackground:SetAllPoints()
    iconGridBackground:SetColorTexture(0.02, 0.02, 0.02, 0.5)

    local iconGridBorderTop = iconGridFrame:CreateTexture(nil, "BORDER")
    iconGridBorderTop:SetPoint("TOPLEFT")
    iconGridBorderTop:SetPoint("TOPRIGHT")
    iconGridBorderTop:SetHeight(1)
    iconGridBorderTop:SetColorTexture(0, 0, 0, 1)
    local iconGridBorderBottom = iconGridFrame:CreateTexture(nil, "BORDER")
    iconGridBorderBottom:SetPoint("BOTTOMLEFT")
    iconGridBorderBottom:SetPoint("BOTTOMRIGHT")
    iconGridBorderBottom:SetHeight(1)
    iconGridBorderBottom:SetColorTexture(0, 0, 0, 1)
    local iconGridBorderLeft = iconGridFrame:CreateTexture(nil, "BORDER")
    iconGridBorderLeft:SetPoint("TOPLEFT")
    iconGridBorderLeft:SetPoint("BOTTOMLEFT")
    iconGridBorderLeft:SetWidth(1)
    iconGridBorderLeft:SetColorTexture(0, 0, 0, 1)
    local iconGridBorderRight = iconGridFrame:CreateTexture(nil, "BORDER")
    iconGridBorderRight:SetPoint("TOPRIGHT")
    iconGridBorderRight:SetPoint("BOTTOMRIGHT")
    iconGridBorderRight:SetWidth(1)
    iconGridBorderRight:SetColorTexture(0, 0, 0, 1)

    iconGridFrame.highlight = iconGridFrame:CreateTexture(nil, "BACKGROUND")
    iconGridFrame.highlight:SetAllPoints()
    iconGridFrame.highlight:SetColorTexture(1, 0.82, 0, 0.12)
    iconGridFrame.highlight:Hide()

    local iconScrollFrame = CreateFrame("ScrollFrame", nil, iconGridFrame)
    iconScrollFrame:SetPoint("TOPLEFT")
    iconScrollFrame:SetWidth(1)
    iconScrollFrame:SetHeight(GRID_ICON_SIZE)
    iconScrollFrame:SetClipsChildren(true)
    iconScrollFrame:EnableMouseWheel(true)

    local iconScrollChild = CreateFrame("Frame", nil, iconScrollFrame)
    iconScrollChild:SetSize(1, GRID_ICON_SIZE)
    iconScrollFrame:SetScrollChild(iconScrollChild)

    local horizontalScrollBar = CreateFrame("Frame", nil, iconGridFrame)
    horizontalScrollBar:SetPoint("TOPLEFT", iconScrollFrame, "BOTTOMLEFT", 0, -5)
    horizontalScrollBar:SetPoint("TOPRIGHT", iconScrollFrame, "BOTTOMRIGHT", 0, -5)
    horizontalScrollBar:SetHeight(14)

    local ScrollIconRow
    local horizontalScroll = CreateFrame("Slider", nil, horizontalScrollBar)
    horizontalScroll:SetAllPoints()
    horizontalScroll:SetOrientation("HORIZONTAL")
    horizontalScroll:SetMinMaxValues(0, 0)
    horizontalScroll:SetValueStep(1)
    horizontalScroll:SetObeyStepOnDrag(false)
    local horizontalTrack = horizontalScroll:CreateTexture(nil, "BACKGROUND")
    horizontalTrack:SetPoint("LEFT")
    horizontalTrack:SetPoint("RIGHT")
    horizontalTrack:SetHeight(12)
    horizontalTrack:SetColorTexture(0, 0, 0, 1)
    local horizontalTrackInset = horizontalScroll:CreateTexture(nil, "BORDER")
    horizontalTrackInset:SetPoint("LEFT", horizontalTrack, "LEFT", 1, 0)
    horizontalTrackInset:SetPoint("RIGHT", horizontalTrack, "RIGHT", -1, 0)
    horizontalTrackInset:SetHeight(10)
    horizontalTrackInset:SetColorTexture(0, 0, 0, 0.55)
    horizontalScroll:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local horizontalThumb = horizontalScroll:GetThumbTexture()
    horizontalThumb:SetVertexColor(0.42, 0.42, 0.42, 1)
    horizontalThumb:SetSize(48, 10)
    horizontalScroll:SetScript("OnEnter", function()
        horizontalThumb:SetVertexColor(0.56, 0.56, 0.56, 1)
    end)
    horizontalScroll:SetScript("OnLeave", function()
        horizontalThumb:SetVertexColor(0.42, 0.42, 0.42, 1)
    end)
    horizontalScroll:SetScript("OnMouseDown", function()
        horizontalThumb:SetVertexColor(0.66, 0.66, 0.66, 1)
    end)
    horizontalScroll:SetScript("OnMouseUp", function()
        local shade = horizontalScroll:IsMouseOver() and 0.56 or 0.42
        horizontalThumb:SetVertexColor(shade, shade, shade, 1)
    end)
    horizontalScroll:SetScript("OnValueChanged", function(_, value)
        local _, maxScroll = horizontalScroll:GetMinMaxValues()
        iconScrollFrame:SetHorizontalScroll(maxScroll - value)
    end)
    horizontalScrollBar:Hide()

    ScrollIconRow = function(delta)
        local _, maxScroll = horizontalScroll:GetMinMaxValues()
        horizontalScroll:SetValue(math.max(0, math.min(maxScroll,
            horizontalScroll:GetValue() + delta)))
    end
    local halfIconStep = GRID_ICON_SIZE / 2
    iconScrollFrame:SetScript("OnMouseWheel", function(_, delta) ScrollIconRow(delta * halfIconStep) end)
    iconGridFrame:EnableMouseWheel(true)
    iconGridFrame:SetScript("OnMouseWheel", function(_, delta) ScrollIconRow(delta * halfIconStep) end)

    local gridIcons = {}
    local gridIconsActive = 0

    local addRowIcon = CreateFrame("Button", nil, iconActionFrame)
    addRowIcon:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)
    addRowIcon:SetPoint("TOPLEFT", iconActionFrame, "TOPLEFT", 4, -4)
    addRowIcon:EnableMouseWheel(true)
    addRowIcon:SetScript("OnMouseWheel", function(_, delta) ScrollIconRow(delta * halfIconStep) end)
    local addRowBackground = addRowIcon:CreateTexture(nil, "BACKGROUND")
    addRowBackground:SetAllPoints()
    addRowBackground:SetColorTexture(0.055, 0.055, 0.055, 0.65)

    local addRowShadowH = addRowIcon:CreateTexture(nil, "ARTWORK", nil, 1)
    addRowShadowH:SetSize(18, 6)
    addRowShadowH:SetPoint("CENTER", 1, -1)
    addRowShadowH:SetColorTexture(0, 0, 0, 0.9)
    local addRowShadowV = addRowIcon:CreateTexture(nil, "ARTWORK", nil, 1)
    addRowShadowV:SetSize(6, 18)
    addRowShadowV:SetPoint("CENTER", 1, -1)
    addRowShadowV:SetColorTexture(0, 0, 0, 0.9)

    local addRowPlusH = addRowIcon:CreateTexture(nil, "ARTWORK", nil, 2)
    addRowPlusH:SetSize(18, 6)
    addRowPlusH:SetPoint("CENTER")
    addRowPlusH:SetColorTexture(0.15, 0.8, 0.2, 1)
    local addRowPlusV = addRowIcon:CreateTexture(nil, "ARTWORK", nil, 2)
    addRowPlusV:SetSize(6, 18)
    addRowPlusV:SetPoint("CENTER")
    addRowPlusV:SetColorTexture(0.15, 0.8, 0.2, 1)
    local addRowHighlight = addRowIcon:CreateTexture(nil, "HIGHLIGHT")
    addRowHighlight:SetAllPoints()
    addRowHighlight:SetColorTexture(1, 1, 1, 0.12)
    if CDM.BORDER and CDM.BORDER.CreateBorder then
        CDM.BORDER:CreateBorder(addRowIcon, { forceUpdate = true })
        if CDM.BORDER.activeBorders then CDM.BORDER.activeBorders[addRowIcon] = nil end
    end

    local rotateBarIcon = CreateFrame("Button", nil, iconActionFrame)
    rotateBarIcon:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)
    rotateBarIcon:SetPoint("TOPRIGHT", iconActionFrame, "TOPRIGHT", -4, -4)
    rotateBarIcon:EnableMouseWheel(true)
    rotateBarIcon:SetScript("OnMouseWheel", function(_, delta) ScrollIconRow(delta * halfIconStep) end)
    local rotateBarBackground = rotateBarIcon:CreateTexture(nil, "BACKGROUND")
    rotateBarBackground:SetAllPoints()
    rotateBarBackground:SetColorTexture(0.055, 0.055, 0.055, 0.65)
    local rotateBarTexture = rotateBarIcon:CreateTexture(nil, "ARTWORK")
    rotateBarTexture:SetPoint("CENTER")
    rotateBarTexture:SetAtlas("common-icon-rotateleft")
    rotateBarTexture:SetDesaturated(true)
    rotateBarTexture:SetVertexColor(0.1, 0.8, 1, 1)
    local rotateBarHighlight = rotateBarIcon:CreateTexture(nil, "HIGHLIGHT")
    rotateBarHighlight:SetAllPoints()
    rotateBarHighlight:SetColorTexture(1, 1, 1, 0.12)
    if CDM.BORDER and CDM.BORDER.CreateBorder then
        CDM.BORDER:CreateBorder(rotateBarIcon, { forceUpdate = true })
        if CDM.BORDER.activeBorders then CDM.BORDER.activeBorders[rotateBarIcon] = nil end
    end
    rotateBarIcon:SetScript("OnClick", function()
        SetCooldownBarView(cooldownBarView == "essential" and "utility" or "essential")
    end)
    rotateBarIcon:SetScript("OnEnter", function(self)
        local currentLabel = cooldownBarView == "essential" and "Essential" or "Utility"
        local nextLabel = cooldownBarView == "essential" and "Utility" or "Essential"
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(currentLabel .. " cooldowns")
        GameTooltip:AddLine("Click to show " .. nextLabel, 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    rotateBarIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function AcquireGridIcon()
        gridIconsActive = gridIconsActive + 1
        local frame = gridIcons[gridIconsActive]
        if not frame then
            frame = CreateFrame("Frame", nil, iconScrollChild)
            local icon = frame:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            frame.icon = icon
            CDM_C.ApplyIconTexCoord(icon, CDM_C.GetEffectiveZoomAmount())
            local highlight = frame:CreateTexture(nil, "OVERLAY")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 0.82, 0, 0.35)
            highlight:Hide()
            frame.highlight = highlight
            local overlay = CreateFrame("Button", nil, frame)
            overlay:SetAllPoints()
            overlay:SetFrameLevel(frame:GetFrameLevel() + 2)
            overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            overlay:RegisterForDrag("LeftButton")
            overlay:EnableMouseWheel(true)
            overlay:SetScript("OnMouseWheel", function(_, delta) ScrollIconRow(delta * halfIconStep) end)
            frame.overlay = overlay
            gridIcons[gridIconsActive] = frame
        end
        frame:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)
        frame:Show()
        return frame
    end

    local function ReleaseAllGridIcons()
        for i = 1, gridIconsActive do
            gridIcons[i]:Hide()
        end
        gridIconsActive = 0
    end

    local buttonRow = CreateFrame("Frame", nil, subPage)
    buttonRow:SetPoint("TOPLEFT", iconGridLayoutAnchor, "BOTTOMLEFT", 0, -6)
    buttonRow:SetPoint("TOPRIGHT", subPage, "TOPRIGHT", -10, 0)
    buttonRow:SetHeight(26)

    local function UpdateGridVisibility()
        buttonRow:ClearAllPoints()
        if currentSpecID == playerSpecID then
            iconGridFrame:Show()
            iconActionFrame:Show()
            buttonRow:SetPoint("TOPLEFT", iconGridLayoutAnchor, "BOTTOMLEFT", 0, -6)
            buttonRow:SetPoint("TOPRIGHT", subPage, "TOPRIGHT", -10, 0)
        else
            iconGridFrame:Hide()
            iconActionFrame:Hide()
            buttonRow:SetPoint("TOPLEFT", subPage, "TOPLEFT", LEFT_INSET, -16)
            buttonRow:SetPoint("TOPRIGHT", subPage, "TOPRIGHT", -10, 0)
        end
    end

    local leftScroll = CreateFrame("ScrollFrame", "AyijeCDM_CDGroups_LeftScroll", subPage, "ScrollFrameTemplate")
    leftScroll:SetPoint("TOPLEFT", buttonRow, "BOTTOMLEFT", -SCROLL_LEFT_PAD, -4)
    leftScroll:SetPoint("BOTTOMLEFT", subPage, "BOTTOMLEFT", LEFT_INSET - SCROLL_LEFT_PAD, 20)
    leftScroll:SetWidth(LEFT_WIDTH + SCROLL_LEFT_PAD)

    local leftChild = CreateFrame("Frame", nil, leftScroll)
    leftChild:SetSize(LEFT_WIDTH + SCROLL_LEFT_PAD, 1200)
    leftScroll:SetScrollChild(leftChild)

    local rightPanel = CreateFrame("Frame", nil, subPage)
    rightPanel:SetPoint("TOPLEFT", buttonRow, "BOTTOMLEFT", RIGHT_X - LEFT_INSET, -4)
    rightPanel:SetPoint("BOTTOMRIGHT", -10, 20)

    local rightPlaceholder = rightPanel:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
    rightPlaceholder:SetPoint("TOP", 0, -20)
    rightPlaceholder:SetText(L["Select a group or spell to edit settings"])
    UI.SetTextMuted(rightPlaceholder)

    local RegisterRightPanelDropdown, CreateRightScrollContent, ClearRightPanel
    do
        local rpm = Shared.CreateRightPanelManager(rightPanel, rightPlaceholder, DestroyFrame)
        RegisterRightPanelDropdown = rpm.RegisterDropdown
        CreateRightScrollContent = rpm.CreateScrollContent
        ClearRightPanel = rpm.Clear
    end

    local function ShowGroupSettings(groupIndex)
        local groups = GetSpecGroups()
        if not groups or not groups[groupIndex] then ClearRightPanel(); return end
        local _, rc = CreateRightScrollContent(700)
        Shared.RenderGroupSettingsPanel({
            rc = rc, gd = groups[groupIndex], groupIndex = groupIndex,
            registerDropdown = RegisterRightPanelDropdown,
            saveAndRefresh = SaveAndRefresh, createSlider = CreateSlider, L = L,
            postSizeSection = function(parent, yOff)
                local s = CreateSlider(parent, L["Max Per Row"], 0, 20,
                    groups[groupIndex].maxPerRow or 0,
                    function(v) groups[groupIndex].maxPerRow = v > 0 and v or nil; SaveAndRefresh() end)
                s:SetPoint("TOPLEFT", 0, yOff)
                return yOff - 50
            end,
            textFields = {
                sizeKey = "chargeFontSize", colorKey = "chargeColor",
                posKey = "chargePosition", xKey = "chargeOffsetX", yKey = "chargeOffsetY",
                sizeDefault = 15, posDefault = "BOTTOMRIGHT",
            },
            anchorTargets = {
                { label = L["Screen"], value = "screen" },
                { label = L["Player Frame"], value = "playerFrame" },
                { label = L["Essential Viewer"], value = "essential" },
                { label = L["Utility Viewer"], value = "utility" },
                { label = L["Buff Viewer"], value = "buff" },
            },
            anchorRelLabels = {
                playerFrame = L["Player Frame Point"],
                buff = L["Buff Viewer Point"],
                utility = L["Utility Viewer Point"],
            },
        })
    end

    ShowSpellSettings = function(spellID, groupIndex)
        if not spellID then ClearRightPanel(); return end

        do
            local trinketSlot, _, trinketName, trinketIcon = GetTrinketInfoForID(spellID)
            if trinketSlot then
                local _, rc = CreateRightScrollContent(200)
                local header = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font18")
                header:SetPoint("TOPLEFT", 0, 0)
                header:SetText(trinketName)
                header:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)

                local iconContainer = CreateFrame("Frame", nil, rc)
                iconContainer:SetSize(40, 40)
                iconContainer:SetPoint("TOPLEFT", 0, -40)
                local iconTex = iconContainer:CreateTexture(nil, "ARTWORK")
                iconTex:SetAllPoints()
                if trinketIcon then iconTex:SetTexture(trinketIcon) end
                CDM_C.ApplyIconTexCoord(iconTex, CDM_C.GetEffectiveZoomAmount())
                if CDM.BORDER and CDM.BORDER.CreateBorder then
                    CDM.BORDER:CreateBorder(iconContainer)
                    if CDM.BORDER.activeBorders then CDM.BORDER.activeBorders[iconContainer] = nil end
                end

                local note = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
                note:SetPoint("TOPLEFT", 0, -100)
                note:SetPoint("RIGHT", rc, "RIGHT", -4, 0)
                note:SetJustifyH("LEFT")
                note:SetText(L["This icon mirrors the trinket equipped in this slot. Drag it like any other cooldown, or drop it into a group."])
                UI.SetTextMuted(note)

                local removeBtn = CreateFrame("Button", nil, rc, "UIPanelButtonTemplate")
                removeBtn:SetSize(140, 22)
                removeBtn:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -16)
                removeBtn:SetText(L["Remove Trinket"])
                removeBtn:SetScript("OnClick", function()
                    SetTrinketTracked(currentSpecID, trinketSlot, false)
                    local groups = GetSpecGroups()
                    if groups then
                        for _, gd in ipairs(groups) do
                            if gd.spells then Shared.RemoveSpellFromGroupList(gd.spells, spellID) end
                        end
                    end
                    local orderBySpec = CDM.db.ungroupedCooldownOrder
                    local order = orderBySpec and orderBySpec[currentSpecID]
                    if order then
                        for i = #order, 1, -1 do
                            if order[i] == spellID then table.remove(order, i) end
                        end
                    end
                    selectedSpellID = nil
                    selectedSpellGroupIndex = nil
                    ClearRightPanel()
                    SaveAndRefresh()
                    API:Refresh("TRACKERS")
                    RefreshLeftPanelIfNeeded()
                end)

                rc:SetHeight(200)
                return
            end
        end

        do
            local customEntry = GetCustomEntryForID(spellID)
            if customEntry then
                local customName, customIcon
                if customEntry.isItem then
                    customName = C_Item.GetItemNameByID(customEntry.id) or (L["Item"] .. " " .. customEntry.id)
                    customIcon = C_Item.GetItemIconByID(customEntry.id)
                else
                    customName = C_Spell.GetSpellName(customEntry.id) or ("Spell " .. customEntry.id)
                    customIcon = C_Spell.GetSpellTexture(customEntry.id)
                end

                local _, rc = CreateRightScrollContent(200)
                local header = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font18")
                header:SetPoint("TOPLEFT", 0, 0)
                header:SetText(customName)
                header:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)

                local iconContainer = CreateFrame("Frame", nil, rc)
                iconContainer:SetSize(40, 40)
                iconContainer:SetPoint("TOPLEFT", 0, -40)
                local iconTex = iconContainer:CreateTexture(nil, "ARTWORK")
                iconTex:SetAllPoints()
                if customIcon then iconTex:SetTexture(customIcon) end
                CDM_C.ApplyIconTexCoord(iconTex, CDM_C.GetEffectiveZoomAmount())
                if CDM.BORDER and CDM.BORDER.CreateBorder then
                    CDM.BORDER:CreateBorder(iconContainer)
                    if CDM.BORDER.activeBorders then CDM.BORDER.activeBorders[iconContainer] = nil end
                end

                local note = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
                note:SetPoint("TOPLEFT", 0, -100)
                note:SetPoint("RIGHT", rc, "RIGHT", -4, 0)
                note:SetJustifyH("LEFT")
                note:SetText(customEntry.isItem
                    and L["This icon tracks a custom item. Drag it like any other cooldown, or drop it into a group."]
                    or L["This icon tracks a custom spell. Drag it like any other cooldown, or drop it into a group."])
                UI.SetTextMuted(note)

                local removeBtn = CreateFrame("Button", nil, rc, "UIPanelButtonTemplate")
                removeBtn:SetSize(140, 22)
                removeBtn:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -16)
                removeBtn:SetText(L["Remove"])
                removeBtn:SetScript("OnClick", function()
                    API:RemoveCustomCooldownEntry(spellID, currentSpecID)
                    selectedSpellID = nil
                    selectedSpellGroupIndex = nil
                    ClearRightPanel()
                    SaveAndRefresh(); RefreshLeftPanelIfNeeded()
                end)

                rc:SetHeight(200)
                return
            end
        end

        if IsCooldownBuffTracked(currentSpecID, spellID) and ns.BuildBuffOverrideSection then
            local _, rc = CreateRightScrollContent(700)
            local yOff = 0
            local existingOverride = CDM.GetUngroupedBuffOverride and CDM:GetUngroupedBuffOverride(spellID)

            local function EnsurePromotedBuffOverride()
                if not CDM.db.ungroupedBuffOverrides then CDM.db.ungroupedBuffOverrides = {} end
                local specOverrides = CDM.db.ungroupedBuffOverrides[currentSpecID]
                if not specOverrides then
                    specOverrides = {}
                    CDM.db.ungroupedBuffOverrides[currentSpecID] = specOverrides
                end
                return CDM:EnsureBuffOverrideEntry(specOverrides, spellID)
            end

            local function SavePromotedBuffSettings()
                API:Refresh("BUFF_DATA")
                SaveAndRefresh()
                RefreshLeftPanelIfNeeded()
            end

            local iconContainer = CreateFrame("Frame", nil, rc)
            iconContainer:SetSize(28, 28)
            iconContainer:SetPoint("TOPLEFT", 0, yOff)
            local iconTex = iconContainer:CreateTexture(nil, "ARTWORK")
            iconTex:SetAllPoints()
            iconTex:SetTexture(GetPromotedBuffTexture(spellID) or C_Spell.GetSpellTexture(spellID))
            CDM_C.ApplyIconTexCoord(iconTex, CDM_C.GetEffectiveZoomAmount())
            if CDM.BORDER and CDM.BORDER.CreateBorder then
                CDM.BORDER:CreateBorder(iconContainer)
                if CDM.BORDER.activeBorders then CDM.BORDER.activeBorders[iconContainer] = nil end
            end

            local borderColor = CDM:GetSpellBorderColor(currentSpecID, spellID)
            local configuredBorder = CDM_C.GetConfigValue("borderColor", CDM_C.WHITE)
            local displayedBorder = borderColor or configuredBorder
            if iconContainer.border then
                iconContainer.border:SetBackdropBorderColor(
                    displayedBorder.r, displayedBorder.g, displayedBorder.b, displayedBorder.a or 1
                )
            end

            local spellName = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font18")
            spellName:SetPoint("LEFT", iconContainer, "RIGHT", 8, 0)
            spellName:SetText(C_Spell.GetSpellName(spellID) or ("Spell " .. spellID))
            spellName:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
            yOff = yOff - 40

            local borderLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
            borderLabel:SetText(L["Border:"])
            borderLabel:SetPoint("TOPLEFT", 0, yOff)
            local borderPicker = UI.CreateSimpleColorPicker(rc, displayedBorder, function(r, g, b)
                API:SaveSpell(currentSpecID, spellID, { r = r, g = g, b = b, a = 1 })
                API:Refresh("BUFF_DATA")
                if iconContainer.border then iconContainer.border:SetBackdropBorderColor(r, g, b, 1) end
                RefreshLeftPanelIfNeeded()
            end)
            borderPicker:SetPoint("LEFT", borderLabel, "RIGHT", 6, 0)
            yOff = yOff - 30

            local resetHint = rc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            resetHint:SetPoint("TOPLEFT", 0, yOff)
            resetHint:SetText(L["Right-click icon to reset border color"])
            UI.SetTextFaint(resetHint)
            yOff = yOff - 24

            iconContainer:EnableMouse(true)
            iconContainer:SetScript("OnMouseUp", function(_, button)
                if button ~= "RightButton" then return end
                API:ClearSpellBorderColor(currentSpecID, spellID)
                API:Refresh("BUFF_DATA")
                ShowSpellSettings(spellID, groupIndex)
                RefreshLeftPanelIfNeeded()
            end)

            local glowEnabled = API:GetSpellGlowEnabled(currentSpecID, spellID)
            local glowCheckbox = UI.CreateModernCheckbox(rc, L["Enable Glow"], glowEnabled, function(checked)
                API:SetSpellGlowEnabled(currentSpecID, spellID, checked or nil)
            end)
            glowCheckbox:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 36

            local glowColorLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
            glowColorLabel:SetText(L["Glow Color:"])
            glowColorLabel:SetPoint("TOPLEFT", 0, yOff)
            local glowColor = API:GetSpellGlowColor(currentSpecID, spellID) or CDM_C.WHITE
            local glowPicker = UI.CreateSimpleColorPicker(rc, glowColor, function(r, g, b)
                API:SetSpellGlowColor(currentSpecID, spellID, { r = r, g = g, b = b })
            end)
            glowPicker:SetPoint("LEFT", glowColorLabel, "RIGHT", 6, 0)
            yOff = yOff - 30

            yOff = ns.BuildBuffOverrideSection(
                rc,
                yOff,
                spellID,
                nil,
                existingOverride,
                EnsurePromotedBuffOverride,
                {
                    cooldownFontSize = CDM.db.buffCooldownFontSize or 12,
                    cooldownColor = CDM.db.buffCooldownColor,
                    countFontSize = CDM.db.countFontSize or 15,
                    countColor = CDM.db.countColor,
                    countPosition = CDM.db.countPositionMain or "TOP",
                    countOffsetX = CDM.db.countOffsetXMain or 0,
                    countOffsetY = CDM.db.countOffsetYMain or 0,
                },
                { isStatic = true, forced = true },
                false,
                {
                    save = SavePromotedBuffSettings,
                    refresh = function() ShowSpellSettings(spellID, groupIndex) end,
                    registerDropdown = RegisterRightPanelDropdown,
                }
            )
            rc:SetHeight(math.abs(yOff) + 20)
            return
        end

        local _, rc = CreateRightScrollContent(400)
        local yOff = 0

        local _, nativeName, nativeIcon = GetNativeItemCategoryInfo(spellID)
        local displayID = GetDisplaySpellID(spellID)
        local name = nativeName or C_Spell.GetSpellName(displayID) or ("Spell " .. spellID)
        local header = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font18")
        header:SetPoint("TOPLEFT", 0, yOff)
        header:SetText(name)
        header:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
        yOff = yOff - 40

        local iconContainer = CreateFrame("Frame", nil, rc)
        iconContainer:SetSize(40, 40)
        iconContainer:SetPoint("TOPLEFT", 0, yOff)
        local iconTex = iconContainer:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        local tex = nativeIcon or GetPromotedBuffTexture(spellID) or C_Spell.GetSpellTexture(displayID)
        if tex then iconTex:SetTexture(tex) end
        CDM_C.ApplyIconTexCoord(iconTex, CDM_C.GetEffectiveZoomAmount())
        if CDM.BORDER and CDM.BORDER.CreateBorder then
            CDM.BORDER:CreateBorder(iconContainer)
            if CDM.BORDER.activeBorders then CDM.BORDER.activeBorders[iconContainer] = nil end
        end
        local promotedBorderColor = IsCooldownBuffTracked(currentSpecID, spellID)
            and CDM.GetSpellBorderColor and CDM:GetSpellBorderColor(currentSpecID, spellID)
        if promotedBorderColor and iconContainer.border then
            iconContainer.border:SetBackdropBorderColor(
                promotedBorderColor.r, promotedBorderColor.g, promotedBorderColor.b, promotedBorderColor.a or 1
            )
        end
        yOff = yOff - 54

        do
            local auraOv
            if groupIndex then
                local grps = GetSpecGroups()
                auraOv = Shared.GetMergedOverrideEntry(grps and grps[groupIndex] and grps[groupIndex].spellOverrides, spellID)
            else
                auraOv = GetUngroupedOverride(spellID)
            end

            local isDotDefault = DOT_OVERRIDE_SPELLS and DOT_OVERRIDE_SPELLS[spellID]
            local showAura
            if auraOv and auraOv.showAuraOverlay ~= nil then
                showAura = auraOv.showAuraOverlay
            else
                showAura = isDotDefault or false
            end

            local auraCheckbox = UI.CreateModernCheckbox(
                rc,
                L["Show Aura Overlay"],
                showAura,
                function(checked)
                    local ov
                    if groupIndex then
                        ov = EnsureSpellOverride(groupIndex, spellID)
                    else
                        ov = EnsureUngroupedOverrideEntry(spellID)
                    end
                    if not ov then return end
                    if checked then
                        ov.showAuraOverlay = isDotDefault and nil or true
                    else
                        ov.showAuraOverlay = false
                    end
                    SaveAndRefresh()
                    ShowSpellSettings(spellID, groupIndex)
                end
            )
            auraCheckbox:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 36

            if showAura then
                if not isDotDefault then
                    local desatValue = auraOv and auraOv.auraDesaturateInactive or false
                    local desatCheckbox = UI.CreateModernCheckbox(
                        rc,
                        L["Desaturate when inactive"],
                        desatValue,
                        function(checked)
                            local ov
                            if groupIndex then
                                ov = EnsureSpellOverride(groupIndex, spellID)
                            else
                                ov = EnsureUngroupedOverrideEntry(spellID)
                            end
                            if not ov then return end
                            ov.auraDesaturateInactive = checked or nil
                            SaveAndRefresh()
                        end
                    )
                    desatCheckbox:SetPoint("TOPLEFT", 20, yOff)
                    yOff = yOff - 30
                end

                local auraGlowEnabled = auraOv and auraOv.auraGlowEnabled or false
                local auraGlowCheckbox = UI.CreateModernCheckbox(
                    rc,
                    L["Aura Glow"],
                    auraGlowEnabled,
                    function(checked)
                        local ov
                        if groupIndex then
                            ov = EnsureSpellOverride(groupIndex, spellID)
                        else
                            ov = EnsureUngroupedOverrideEntry(spellID)
                        end
                        if not ov then return end
                        ov.auraGlowEnabled = checked or nil
                        SaveAndRefresh()
                    end
                )
                auraGlowCheckbox:SetPoint("TOPLEFT", 20, yOff)
                yOff = yOff - 30

                local agcLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
                agcLabel:SetText(L["Glow Color:"])
                agcLabel:SetPoint("TOPLEFT", 20, yOff)
                local agcInit = (auraOv and auraOv.auraGlowColor) or { r = 1, g = 1, b = 1 }
                local agcPicker = UI.CreateSimpleColorPicker(rc, agcInit, function(r, g, b)
                    local ov
                    if groupIndex then
                        ov = EnsureSpellOverride(groupIndex, spellID)
                    else
                        ov = EnsureUngroupedOverrideEntry(spellID)
                    end
                    if not ov then return end
                    ov.auraGlowColor = { r = r, g = g, b = b }
                    SaveAndRefresh()
                end)
                agcPicker:SetPoint("LEFT", agcLabel, "RIGHT", 6, 0)
                yOff = yOff - 30

                local auraBorderEnabled = auraOv and auraOv.auraBorderEnabled or false
                local auraBorderCheckbox = UI.CreateModernCheckbox(
                    rc,
                    L["Aura Border Color"],
                    auraBorderEnabled,
                    function(checked)
                        local ov
                        if groupIndex then
                            ov = EnsureSpellOverride(groupIndex, spellID)
                        else
                            ov = EnsureUngroupedOverrideEntry(spellID)
                        end
                        if not ov then return end
                        ov.auraBorderEnabled = checked or nil
                        SaveAndRefresh()
                    end
                )
                auraBorderCheckbox:SetPoint("TOPLEFT", 20, yOff)
                yOff = yOff - 30

                local abcLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
                abcLabel:SetText(L["Border Color:"])
                abcLabel:SetPoint("TOPLEFT", 20, yOff)
                local abcInit = (auraOv and auraOv.auraBorderColor) or { r = 1, g = 1, b = 1 }
                local abcPicker = UI.CreateSimpleColorPicker(rc, abcInit, function(r, g, b)
                    local ov
                    if groupIndex then
                        ov = EnsureSpellOverride(groupIndex, spellID)
                    else
                        ov = EnsureUngroupedOverrideEntry(spellID)
                    end
                    if not ov then return end
                    ov.auraBorderColor = { r = r, g = g, b = b, a = 1 }
                    SaveAndRefresh()
                end)
                abcPicker:SetPoint("LEFT", abcLabel, "RIGHT", 6, 0)
                yOff = yOff - 30
            end

            local readyGlowEnabled = auraOv and auraOv.readyGlowEnabled or false
            local readyGlowCheckbox = UI.CreateModernCheckbox(
                rc,
                L["Glow When Ready"],
                readyGlowEnabled,
                function(checked)
                    local ov
                    if groupIndex then
                        ov = EnsureSpellOverride(groupIndex, spellID)
                    else
                        ov = EnsureUngroupedOverrideEntry(spellID)
                    end
                    if not ov then return end
                    ov.readyGlowEnabled = checked or nil
                    SaveAndRefresh()
                    ShowSpellSettings(spellID, groupIndex)
                end
            )
            readyGlowCheckbox:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 36

            if readyGlowEnabled then
                local rgcLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
                rgcLabel:SetText(L["Glow Color:"])
                rgcLabel:SetPoint("TOPLEFT", 20, yOff)
                local rgcInit = (auraOv and auraOv.readyGlowColor) or { r = 1, g = 1, b = 1 }
                local rgcPicker = UI.CreateSimpleColorPicker(rc, rgcInit, function(r, g, b)
                    local ov
                    if groupIndex then
                        ov = EnsureSpellOverride(groupIndex, spellID)
                    else
                        ov = EnsureUngroupedOverrideEntry(spellID)
                    end
                    if not ov then return end
                    ov.readyGlowColor = { r = r, g = g, b = b }
                    SaveAndRefresh()
                end)
                rgcPicker:SetPoint("LEFT", rgcLabel, "RIGHT", 6, 0)
                yOff = yOff - 30
            end

            local glowColorOverride = auraOv and auraOv.glowColorOverride or false
            local glowHeader = UI.CreateSubHeader(rc, L["Glow Overrides"])
            glowHeader:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 32

            local glowOverrideCheckbox = UI.CreateModernCheckbox(
                rc,
                L["Override Glow Color"],
                glowColorOverride,
                function(checked)
                    local ov
                    if groupIndex then
                        ov = EnsureSpellOverride(groupIndex, spellID)
                    else
                        ov = EnsureUngroupedOverrideEntry(spellID)
                    end
                    if not ov then return end
                    ov.glowColorOverride = checked or nil
                    if checked and not ov.glowColor then
                        local color = CDM.db.glowColor or { r = 1, g = 1, b = 1 }
                        ov.glowColor = { r = color.r, g = color.g, b = color.b }
                    end
                    SaveAndRefresh()
                    ShowSpellSettings(spellID, groupIndex)
                end
            )
            glowOverrideCheckbox:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 36

            if glowColorOverride then
                local glowColorLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
                glowColorLabel:SetText(L["Glow Color:"])
                glowColorLabel:SetPoint("TOPLEFT", 20, yOff)
                local color = auraOv.glowColor or CDM.db.glowColor or { r = 1, g = 1, b = 1 }
                local glowColorPicker = UI.CreateSimpleColorPicker(rc, color, function(r, g, b)
                    local ov
                    if groupIndex then
                        ov = EnsureSpellOverride(groupIndex, spellID)
                    else
                        ov = EnsureUngroupedOverrideEntry(spellID)
                    end
                    if not ov then return end
                    ov.glowColor = { r = r, g = g, b = b }
                    SaveAndRefresh()
                end)
                glowColorPicker:SetPoint("LEFT", glowColorLabel, "RIGHT", 6, 0)
                yOff = yOff - 30
            end
        end

        local CD_TEXT_OV_FIELDS = {
            cdSize = "cooldownFontSize", cdColor = "cooldownColor",
            chargeSize = "chargeFontSize", chargeColor = "chargeColor",
            chargePos = "chargePosition", chargeX = "chargeOffsetX", chargeY = "chargeOffsetY",
        }

        if groupIndex then
            local groups = GetSpecGroups()
            local gd = groups and groups[groupIndex]
            if gd then
                yOff = Shared.BuildTextOverrideWidgets(rc, yOff, {
                    showHeader = true,
                    existingOv = Shared.GetMergedOverrideEntry(gd.spellOverrides, spellID),
                    ensureOv = function() return EnsureSpellOverride(groupIndex, spellID) end,
                    defaults = gd,
                    fields = CD_TEXT_OV_FIELDS,
                    colorAlpha = true,
                    save = SaveAndRefresh,
                    onToggle = function() ShowSpellSettings(spellID, groupIndex) end,
                    createDropdown = function(p) return RegisterRightPanelDropdown(CreateFrame("DropdownButton", nil, p, "WowStyle1DropdownTemplate")) end,
                })
            end
        else
            yOff = Shared.BuildTextOverrideWidgets(rc, yOff, {
                showHeader = true,
                existingOv = GetUngroupedOverride(spellID),
                ensureOv = function() return EnsureUngroupedOverrideEntry(spellID) end,
                defaults = CDM.db or {},
                fields = CD_TEXT_OV_FIELDS,
                colorAlpha = true,
                save = SaveAndRefresh,
                onToggle = function() ShowSpellSettings(spellID, nil) end,
                createDropdown = function(p) return RegisterRightPanelDropdown(CreateFrame("DropdownButton", nil, p, "WowStyle1DropdownTemplate")) end,
            })
        end

        rc:SetHeight(math.abs(yOff) + 20)
    end

    local addIconBtnRef = nil
    local ShowSpellPickerPanel

    local headerPool, groupContainerPool, emptyRowPool, spellRowPool =
        Shared.CreateGroupEditorPools(leftChild, {
            highlightAlpha = 0.15,
            resetBorder = function(border)
                local cfgColor = CDM_C.GetConfigValue("borderColor", { r = 0, g = 0, b = 0, a = 1 })
                border:SetBackdropBorderColor(cfgColor.r, cfgColor.g, cfgColor.b, cfgColor.a or 1)
            end,
        })

    local function GetViewerSpellListForSpec(specID)
        local seen, list = {}, {}
        if specID == playerSpecID then
            for _, cat in ipairs(CDM_C.VIEWER_CATEGORIES_COOLDOWN) do
                local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
                if ids then
                    for _, cdID in ipairs(ids) do
                        if not seen[cdID] then
                            seen[cdID] = true
                            local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                            if info and CDM_C.IsViewerEntryVisible(info) then
                                local sid = CDM_C.ResolveViewerEntryIdentity(info)
                                if sid then
                                    list[#list + 1] = { cdID = cdID, spellID = sid }
                                end
                            end
                        end
                    end
                end
            end
            return list
        end

        for _, accessor in ipairs({ "GetSpecEssentialCache", "GetSpecUtilityCache" }) do
            local cache = API[accessor] and API[accessor](API, specID)
            if cache then
                for _, entry in ipairs(cache) do
                    local cdID = entry.cooldownID
                    local sid = entry.spellID
                    if sid and cdID and not seen[cdID] then
                        seen[cdID] = true
                        list[#list + 1] = { cdID = cdID, spellID = sid }
                    end
                end
            end
        end
        return list
    end

    local function GetUntrackedViewerSpellListForCurrentSpec()
        local activeSet = BuildCooldownActiveSet()
        local seen, list = {}, {}
        for _, cat in ipairs(CDM_C.VIEWER_CATEGORIES_COOLDOWN) do
            local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
            if ids then
                for _, cdID in ipairs(ids) do
                    if not seen[cdID] then
                        seen[cdID] = true
                        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                        if info and CDM_C.IsViewerEntryVisible(info) then
                            local sid = CDM_C.ResolveViewerEntryIdentity(info)
                            if sid and not activeSet[sid] then
                                list[#list + 1] = { cdID = cdID, spellID = sid }
                            end
                        end
                    end
                end
            end
        end
        return list
    end

    local function HasOtherSpecCooldownPickerCache(specID)
        if specID == playerSpecID then return true end
        local essCache = API.GetSpecEssentialCache and API:GetSpecEssentialCache(specID)
        local utilCache = API.GetSpecUtilityCache and API:GetSpecUtilityCache(specID)
        return essCache ~= nil or utilCache ~= nil
    end

    local function GetAvailableSpellsForPicker(specID)
        local allSlots = (specID == playerSpecID)
            and GetUntrackedViewerSpellListForCurrentSpec()
            or GetViewerSpellListForSpec(specID)
        local assigned = {}
        local groups = CDM.db[dbKey] and CDM.db[dbKey][specID]
        if groups then
            for _, group in ipairs(groups) do
                for _, sid in ipairs(group.spells or {}) do
                    Shared.MarkEquivalentSpellIDs(assigned, sid)
                    local overrideID = ResolveCooldownOverrideID(sid)
                    if overrideID ~= sid then
                        Shared.MarkEquivalentSpellIDs(assigned, overrideID)
                    end
                end
            end
        end
        local seen = {}
        local result = {}
        for _, slot in ipairs(allSlots) do
            local spellID = slot.spellID
            if not Shared.HasEquivalentSpellID(assigned, spellID)
                and not seen[slot.cdID]
            then
                seen[slot.cdID] = true
                local _, nativeName, nativeIcon = GetNativeItemCategoryInfo(spellID)
                local pickerDisplayID = GetDisplaySpellID(spellID)
                local spellName = nativeName or C_Spell.GetSpellName(pickerDisplayID) or ("Spell " .. spellID)
                local icon = nativeIcon or C_Spell.GetSpellTexture(pickerDisplayID)
                local isKnown = nativeName ~= nil or IsPlayerSpell(spellID)
                result[#result + 1] = { spellID = spellID, cdID = slot.cdID, name = spellName, icon = icon, isKnown = isKnown }
            end
        end
        for _, slotID in ipairs(TRINKET_SLOT_IDS) do
            local sentinel = GetTrinketSentinelForSlot(slotID)
            if GetInventoryItemID("player", slotID)
                and not Shared.HasEquivalentSpellID(assigned, sentinel)
            then
                local _, _, trinketName, trinketIcon = GetTrinketInfoForID(sentinel)
                result[#result + 1] = { spellID = sentinel, cdID = nil, name = trinketName, icon = trinketIcon, isKnown = true }
            end
        end
        local customList = CDM.db.customCooldownEntries and CDM.db.customCooldownEntries[specID]
        if customList then
            for _, stored in ipairs(customList) do
                local identity = API.GetCustomCooldownIdentityForEntry(stored)
                if not Shared.HasEquivalentSpellID(assigned, identity) then
                    local name, icon
                    if stored.isItem then
                        name = C_Item.GetItemNameByID(stored.id) or (L["Item"] .. " " .. stored.id)
                        icon = C_Item.GetItemIconByID(stored.id)
                    else
                        name = C_Spell.GetSpellName(stored.id) or ("Spell " .. stored.id)
                        icon = C_Spell.GetSpellTexture(stored.id)
                    end
                    result[#result + 1] = { spellID = identity, cdID = nil, name = name, icon = icon, isKnown = true }
                end
            end
        end
        table.sort(result, function(a, b) return a.name < b.name end)
        return result
    end

    local function GetUngroupedSpellsFromViewers(viewFilter)
        viewFilter = viewFilter or cooldownBarView
        local groupedSet = {}
        local specGroups = GetSpecGroups()
        if type(specGroups) == "table" then
            for _, groupData in ipairs(specGroups) do
                if type(groupData) == "table" and type(groupData.spells) == "table" then
                    for _, groupedSpellID in ipairs(groupData.spells) do
                        Shared.MarkEquivalentSpellIDs(groupedSet, groupedSpellID)
                        local overrideID = ResolveCooldownOverrideID(groupedSpellID)
                        if overrideID ~= groupedSpellID then
                            Shared.MarkEquivalentSpellIDs(groupedSet, overrideID)
                        end
                    end
                end
            end
        end
        local rankMap
        do
            local bySpec = CDM.db.ungroupedCooldownOrder
            local order = bySpec and bySpec[currentSpecID]
            if type(order) == "table" and #order > 0 then
                rankMap = {}
                for i, sid in ipairs(order) do
                    if rankMap[sid] == nil then rankMap[sid] = i end
                    local baseID = NormalizeToBase and NormalizeToBase(sid)
                    if baseID and rankMap[baseID] == nil then rankMap[baseID] = i end
                end
            end
        end
        local function GetSavedRank(spellID)
            if not rankMap then return nil end
            local rank = rankMap[spellID]
            if not rank and NormalizeToBase then
                local baseID = NormalizeToBase(spellID)
                if baseID then rank = rankMap[baseID] end
            end
            if not rank then
                local overrideID = ResolveCooldownOverrideID(spellID)
                if overrideID ~= spellID then rank = rankMap[overrideID] end
            end
            return rank
        end
        local seen = {}
        local icons = {}
        local viewerNames
        if viewFilter == "essential" then
            viewerNames = { CDM_C.VIEWERS.ESSENTIAL }
        elseif viewFilter == "utility" then
            viewerNames = { CDM_C.VIEWERS.UTILITY }
        else
            viewerNames = { CDM_C.VIEWERS.ESSENTIAL, CDM_C.VIEWERS.UTILITY }
        end
        for _, vName in ipairs(viewerNames) do
            local viewerOffset = vName == CDM_C.VIEWERS.UTILITY and 10000 or 0
            local viewer = _G[vName]
            if viewer and viewer.itemFramePool then
                for frame in viewer.itemFramePool:EnumerateActive() do
                    if frame:IsShown() or frame.cooldownInfo then
                        local equipSlot = frame.cooldownInfo and frame.cooldownInfo.equipSlot
                        local displayID = frame.cooldownInfo
                            and CDM_C.ResolveViewerEntryIdentity(frame.cooldownInfo)
                        if not IsSafeNumber(displayID) and API.GetPreferredBuffGroupSpellID then
                            displayID = API:GetPreferredBuffGroupSpellID(frame)
                        end
                        if not IsSafeNumber(displayID) and API.GetBaseSpellID then
                            displayID = API:GetBaseSpellID(frame)
                        end
                        local slotKey = frame.cooldownID or displayID
                        if IsSafeNumber(displayID)
                            and not (equipSlot and IsTrinketTracked(currentSpecID, equipSlot))
                            and not Shared.HasEquivalentSpellID(groupedSet, displayID)
                            and not seen[slotKey]
                        then
                            seen[slotKey] = true
                            local li = frame.layoutIndex
                            local safeLayoutIndex = IsSafeNumber(li) and li or 0
                            icons[#icons + 1] = { spellID = displayID, layoutIndex = safeLayoutIndex, viewerOrder = viewerOffset, rank = GetSavedRank(displayID) }
                        end
                    end
                end
            end
        end
        if viewFilter ~= "utility" then
            for _, slotID in ipairs(TRINKET_SLOT_IDS) do
                if IsTrinketTracked(currentSpecID, slotID) then
                    local sentinel = GetTrinketSentinelForSlot(slotID)
                    if not Shared.HasEquivalentSpellID(groupedSet, sentinel) then
                        icons[#icons + 1] = {
                            spellID = sentinel,
                            layoutIndex = 99000 + slotID,
                            viewerOrder = 0,
                            rank = GetSavedRank(sentinel),
                        }
                    end
                end
            end
            local customList = GetCustomEntriesForViewedSpec()
            if customList then
                for i, stored in ipairs(customList) do
                    local identity = API.GetCustomCooldownIdentityForEntry(stored)
                    if not Shared.HasEquivalentSpellID(groupedSet, identity) then
                        icons[#icons + 1] = {
                            spellID = identity,
                            layoutIndex = 99100 + i,
                            viewerOrder = 0,
                            rank = GetSavedRank(identity),
                        }
                    end
                end
            end
            local selectedBuffs = CDM.db.cooldownBuffs and CDM.db.cooldownBuffs[currentSpecID]
            if selectedBuffs then
                for spellID, selected in pairs(selectedBuffs) do
                    if selected and not Shared.HasEquivalentSpellID(groupedSet, spellID) then
                        local duplicate = false
                        for _, data in ipairs(icons) do
                            if data.spellID == spellID then
                                duplicate = true
                                break
                            end
                        end
                        if not duplicate then
                            icons[#icons + 1] = {
                                spellID = spellID,
                                layoutIndex = 99200,
                                viewerOrder = 0,
                                rank = GetSavedRank(spellID),
                            }
                        end
                    end
                end
            end
        end
        -- Blend saved ranks with Blizzard order (mirrors the runtime layout):
        -- unranked icons follow the ranked icon that precedes them in
        -- Blizzard order rather than sorting to the end.
        table.sort(icons, function(a, b)
            if a.viewerOrder ~= b.viewerOrder then return a.viewerOrder < b.viewerOrder end
            if a.layoutIndex ~= b.layoutIndex then return a.layoutIndex < b.layoutIndex end
            return a.spellID < b.spellID
        end)
        do
            local prevViewer, lastRank, run
            for _, data in ipairs(icons) do
                if data.viewerOrder ~= prevViewer then
                    prevViewer = data.viewerOrder
                    lastRank, run = 0, 0
                end
                if data.rank then
                    data.effRank = data.rank
                    lastRank = data.rank
                    run = 0
                else
                    run = run + 1
                    data.effRank = lastRank + run * 0.001
                end
            end
        end
        table.sort(icons, function(a, b)
            if a.viewerOrder ~= b.viewerOrder then return a.viewerOrder < b.viewerOrder end
            if a.effRank ~= b.effRank then return a.effRank < b.effRank end
            return a.spellID < b.spellID
        end)
        local result = {}
        for _, data in ipairs(icons) do result[#result + 1] = data.spellID end
        return result
    end

    local function AppendUngroupedOrder(spellID)
        if not (currentSpecID and spellID) then return end
        if not CDM.db.ungroupedCooldownOrder then CDM.db.ungroupedCooldownOrder = {} end
        local order = CDM.db.ungroupedCooldownOrder[currentSpecID]
        if not order then
            order = GetUngroupedSpellsFromViewers("all")
            CDM.db.ungroupedCooldownOrder[currentSpecID] = order
        end
        for _, existingID in ipairs(order) do
            if existingID == spellID then return end
        end
        order[#order + 1] = spellID
    end

    local function RemoveUngroupedOrderEntry(spellID)
        local bySpec = CDM.db.ungroupedCooldownOrder
        local order = bySpec and bySpec[currentSpecID]
        if not order then return end
        for i = #order, 1, -1 do
            if order[i] == spellID then table.remove(order, i) end
        end
    end

    local itemIDOverlay
    local function ShowItemIDPopup()
        if not itemIDOverlay then
            local overlay = UI.CreateModalOverlay()
            overlay:ClearAllPoints()
            overlay:SetAllPoints(UIParent)

            local window = overlay.window
            window:ClearAllPoints()
            window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            window:SetSize(290, 120)

            local inputLabel = window:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
            inputLabel:SetPoint("TOPLEFT", window, "TOPLEFT", 24, -42)
            inputLabel:SetText("ItemID:")

            local editBox = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
            editBox:SetSize(150, 24)
            editBox:SetPoint("LEFT", inputLabel, "RIGHT", 12, 0)
            editBox:SetAutoFocus(false)
            editBox:SetNumeric(true)
            editBox:SetMaxLetters(7)
            editBox:SetJustifyH("CENTER")

            local okayButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
            okayButton:SetSize(92, 22)
            okayButton:SetPoint("BOTTOMRIGHT", window, "BOTTOM", -4, 14)
            okayButton:SetText("Accept")

            local cancelButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
            cancelButton:SetSize(92, 22)
            cancelButton:SetPoint("BOTTOMLEFT", window, "BOTTOM", 4, 14)
            cancelButton:SetText(CANCEL)

            local function SetError(message)
                if UIErrorsFrame then
                    UIErrorsFrame:AddMessage(message, 1, 0.2, 0.2, 1)
                end
            end

            local function AddItem()
                local itemID = tonumber(editBox:GetText())
                if not itemID or itemID <= 0 then
                    SetError("Enter a valid ItemID")
                    return
                end

                local identity = CDM_C.GetCustomItemSentinelForItem(itemID)
                if not GetCustomItemIDFromSentinel(identity) then
                    SetError("ItemID is out of range")
                    return
                end
                if C_Item.DoesItemExistByID and not C_Item.DoesItemExistByID(itemID) then
                    SetError("Unknown ItemID")
                    return
                end

                local ok = API:AddCustomCooldownEntry(itemID, true, currentSpecID)
                if not ok then
                    SetError("Item is already tracked")
                    return
                end

                AppendUngroupedOrder(identity)
                SaveAndRefresh()
                RefreshLeftPanelIfNeeded()
                overlay:Hide()
            end

            okayButton:SetScript("OnClick", AddItem)
            cancelButton:SetScript("OnClick", function() overlay:Hide() end)
            editBox:SetScript("OnEnterPressed", AddItem)
            editBox:SetScript("OnEscapePressed", function() overlay:Hide() end)

            overlay:HookScript("OnShow", function()
                editBox:SetText("")
                editBox:SetFocus()
            end)

            itemIDOverlay = overlay
        end

        itemIDOverlay:Show()
    end

    local function AddMenuLabel(name, icon)
        if icon then return string.format("|T%s:16:16|t %s", tostring(icon), name) end
        return name
    end

    local function PreserveBuffOverridesForCooldownRow(spellID)
        local buffGroups = CDM.db.buffGroups and CDM.db.buffGroups[currentSpecID]
        local incoming
        for _, groupData in ipairs(buffGroups or {}) do
            if groupData.spells then
                Shared.RemoveSpellFromGroupList(groupData.spells, spellID)
            end
            if groupData.spellOverrides and CDM.ExtractMergedBuffOverrideEntry then
                local extracted = CDM:ExtractMergedBuffOverrideEntry(groupData.spellOverrides, spellID)
                if extracted then
                    if incoming and CDM.MergeMissingBuffOverrideFields then
                        CDM:MergeMissingBuffOverrideFields(incoming, extracted)
                    else
                        incoming = extracted
                    end
                end
            end
        end

        if incoming then
            if not CDM.db.ungroupedBuffOverrides then CDM.db.ungroupedBuffOverrides = {} end
            local overrides = CDM.db.ungroupedBuffOverrides[currentSpecID]
            if not overrides then
                overrides = {}
                CDM.db.ungroupedBuffOverrides[currentSpecID] = overrides
            end
            local existing = CDM.GetMergedBuffOverrideEntry and CDM:GetMergedBuffOverrideEntry(overrides, spellID)
            if existing and CDM.MergeMissingBuffOverrideFields then
                CDM:MergeMissingBuffOverrideFields(incoming, existing)
            end
            if CDM.StoreMergedBuffOverrideEntry then
                CDM:StoreMergedBuffOverrideEntry(overrides, spellID, incoming)
            end
        end
    end

    local function ShowAddRowMenu()
        MenuUtil.CreateContextMenu(addRowIcon, function(_, rootDescription)
            rootDescription:CreateTitle("Add Icon")

            local buffsMenu = rootDescription:CreateButton("Buffs")
            local buffEntries = {}
            local seenBuffs = {}
            local buffViewer = _G[CDM_C.VIEWERS.BUFF]
            if buffViewer and buffViewer.itemFramePool then
                for frame in buffViewer.itemFramePool:EnumerateActive() do
                    local info = frame.GetCooldownInfo and frame:GetCooldownInfo() or frame.cooldownInfo
                    local spellID = info and CDM_C.ResolveViewerEntryIdentity(info)
                    if not IsSafeNumber(spellID) and API.GetPreferredBuffGroupSpellID then
                        spellID = API:GetPreferredBuffGroupSpellID(frame)
                    end
                    if info and CDM_C.IsViewerEntryVisible(info)
                        and IsSafeNumber(spellID)
                        and not seenBuffs[spellID]
                        and not IsCooldownBuffTracked(currentSpecID, spellID)
                    then
                        seenBuffs[spellID] = true
                        buffEntries[#buffEntries + 1] = {
                            spellID = spellID,
                            name = C_Spell.GetSpellName(spellID) or ("Spell " .. spellID),
                            icon = C_Spell.GetSpellTexture(spellID),
                        }
                    end
                end
            end
            table.sort(buffEntries, function(a, b) return a.name < b.name end)
            for _, entry in ipairs(buffEntries) do
                local buffSpellID = entry.spellID
                buffsMenu:CreateButton(AddMenuLabel(entry.name, entry.icon), function()
                    PreserveBuffOverridesForCooldownRow(buffSpellID)
                    SetCooldownBuffTracked(currentSpecID, buffSpellID, true)
                    AppendUngroupedOrder(buffSpellID)
                    API:Refresh("BUFF_DATA")
                    SaveAndRefresh()
                    RefreshLeftPanelIfNeeded()
                end)
            end
            if #buffEntries == 0 then buffsMenu:CreateTitle("No buffs available") end

            local potionsMenu = rootDescription:CreateButton("Potions")
            local potionCount = 0
            local order, items = API.GetCustomCooldownBuiltinItems()
            local customEntries = GetCustomEntriesForViewedSpec() or {}
            local existingItems = {}
            for _, stored in ipairs(customEntries) do
                if stored.isItem then existingItems[stored.id] = true end
            end
            local _, playerClassTag = UnitClass("player")
            for _, itemID in ipairs(order or {}) do
                local info = items and items[itemID]
                if info and (not info.class or info.class == playerClassTag) and not existingItems[itemID] then
                    potionCount = potionCount + 1
                    local potionItemID = itemID
                    local name = C_Item.GetItemNameByID(itemID) or ("Item " .. itemID)
                    local icon = C_Item.GetItemIconByID(itemID)
                    potionsMenu:CreateButton(AddMenuLabel(name, icon), function()
                        local ok = API:AddCustomCooldownEntry(potionItemID, true, currentSpecID)
                        if ok then
                            local identity = CDM_C.GetCustomItemSentinelForItem(potionItemID)
                            AppendUngroupedOrder(identity)
                            SaveAndRefresh()
                            RefreshLeftPanelIfNeeded()
                        end
                    end)
                end
            end
            if potionCount == 0 then potionsMenu:CreateTitle("No potions available") end

            rootDescription:CreateButton("ItemID", function()
                if not currentSpecID then return end
                ShowItemIDPopup()
            end)
        end)
    end

    addRowIcon:SetScript("OnClick", ShowAddRowMenu)

    ApplyUngroupedGridOrder = function(spellID, insertIndex)
        if not currentSpecID or not insertIndex then return false end

        local dragSet = {}
        Shared.MarkEquivalentSpellIDs(dragSet, spellID)
        local overrideID = ResolveCooldownOverrideID(spellID)
        if overrideID ~= spellID then
            Shared.MarkEquivalentSpellIDs(dragSet, overrideID)
        end

        local currentOrder = GetUngroupedSpellsFromViewers()
        local sourceIndex
        local newOrder = {}
        for i, sid in ipairs(currentOrder) do
            if Shared.HasEquivalentSpellID(dragSet, sid) then
                sourceIndex = sourceIndex or i
            else
                newOrder[#newOrder + 1] = sid
            end
        end

        local insertAt = insertIndex
        if sourceIndex and sourceIndex < insertAt then insertAt = insertAt - 1 end
        insertAt = math.max(1, math.min(insertAt, #newOrder + 1))
        table.insert(newOrder, insertAt, spellID)

        local mergedOrder = {}
        local mergedSet = {}
        local function AppendOrder(source)
            for _, sid in ipairs(source) do
                if not Shared.HasEquivalentSpellID(mergedSet, sid) then
                    mergedOrder[#mergedOrder + 1] = sid
                    Shared.MarkEquivalentSpellIDs(mergedSet, sid)
                end
            end
        end
        if cooldownBarView == "essential" then
            AppendOrder(newOrder)
            AppendOrder(GetUngroupedSpellsFromViewers("utility"))
        else
            AppendOrder(GetUngroupedSpellsFromViewers("essential"))
            AppendOrder(newOrder)
        end

        if not CDM.db.ungroupedCooldownOrder then
            CDM.db.ungroupedCooldownOrder = {}
        end
        CDM.db.ungroupedCooldownOrder[currentSpecID] = mergedOrder
        return true
    end

    ShowSpellPickerPanel = function(groupIndex)
        local groups = GetSpecGroups()
        if not groups or not groups[groupIndex] then return end
        local gd = groups[groupIndex]
        local spells = GetAvailableSpellsForPicker(currentSpecID)
        Shared.RenderSpellPicker({
            createRightScrollContent = CreateRightScrollContent,
            headerText = (L["Add Spell to:"]) .. " " .. (gd.name or "Group"),
            headerColor = CDM_C.GOLD,
            spells = spells,
            currentSpecID = currentSpecID,
            playerSpecID = playerSpecID,
            isCacheMissing = currentSpecID ~= playerSpecID and not HasOtherSpecCooldownPickerCache(currentSpecID),
            cacheMissingText = string.format(L["Log %s to build spell list"], select(2, GetSpecializationInfoByID(currentSpecID)) or "this spec"),
            emptyText = currentSpecID == playerSpecID
                and (L["No untracked cooldown icons available for this spec"])
                or (L["All available icons are assigned to groups"]),
            onSelect = function(sid, cdID)
                local currentGroups = EnsureGroups()
                if not currentGroups or not currentGroups[groupIndex] then return end
                if not currentGroups[groupIndex].spells then currentGroups[groupIndex].spells = {} end
                local pickedTrinketSlot = GetTrinketSlotFromSentinel and GetTrinketSlotFromSentinel(sid)
                if cdID then
                    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                    if info and info.spellID then sid = info.spellID end
                elseif pickedTrinketSlot then
                    SetTrinketTracked(currentSpecID, pickedTrinketSlot, true)
                    API:Refresh("TRACKERS")
                else
                    sid = ResolveCooldownStableBase(sid)
                end
                Shared.AddSpellToGroupList(currentGroups[groupIndex].spells, sid)
                local specOv = EnsureUngroupedOverrides()
                if specOv then
                    local ovData = ExtractMergedOverrideEntry(specOv, sid)
                    if ovData then
                        if not currentGroups[groupIndex].spellOverrides then
                            currentGroups[groupIndex].spellOverrides = {}
                        end
                        StoreMergedOverrideEntry(currentGroups[groupIndex].spellOverrides, sid, ovData)
                    end
                end
                SaveAndRefresh(); RefreshLeftPanelIfNeeded()
                ShowSpellPickerPanel(groupIndex)
            end,
            onDone = function()
                ShowGroupSettings(groupIndex)
            end,
        })
    end

    local function AcquireEmptyRow(parent, text)
        return Shared.AcquireEmptyRow(emptyRowPool, parent, text)
    end

    local function ConfigureSpellRow(widget, parent, spellID, sourceGroup, y, isActive, spellIndex, spellCount)
        local row = widget.root
        row:SetParent(parent)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 8, y)

        local trinketSlot, _, trinketName, trinketIcon = GetTrinketInfoForID(spellID)
        local customItemID, customItemName, customItemIcon = GetCustomItemInfoForID(spellID)
        local _, nativeItemName, nativeItemIcon = GetNativeItemCategoryInfo(spellID)
        local displayID = GetDisplaySpellID(spellID)
        local tex = (trinketSlot and trinketIcon)
            or (customItemID and customItemIcon)
            or nativeItemIcon
            or GetPromotedBuffTexture(spellID)
            or C_Spell.GetSpellTexture(displayID)
        if tex then widget.iconTex:SetTexture(tex) end
        CDM_C.ApplyIconTexCoord(widget.iconTex, CDM_C.GetEffectiveZoomAmount())

        local cfgColor = CDM_C.GetConfigValue("borderColor", { r = 0, g = 0, b = 0, a = 1 })
        if widget.iconContainer.border then
            local promotedColor = IsCooldownBuffTracked(currentSpecID, spellID)
                and CDM.GetSpellBorderColor and CDM:GetSpellBorderColor(currentSpecID, spellID)
            local color = promotedColor or cfgColor
            widget.iconContainer.border:SetBackdropBorderColor(color.r, color.g, color.b, color.a or 1)
        end

        if isActive == false then
            widget.iconTex:SetDesaturated(true)
            widget.iconTex:SetAlpha(0.5)
            if widget.iconContainer.border then
                widget.iconContainer.border:SetAlpha(0.5)
                widget.iconContainer.border:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            end
        else
            widget.iconTex:SetDesaturated(false)
            widget.iconTex:SetAlpha(1)
            if widget.iconContainer.border then widget.iconContainer.border:SetAlpha(1) end
        end

        widget.removeBtn:Hide()
        widget.removeBtn:SetScript("OnClick", nil)
        if sourceGroup then
            widget.removeBtn:Show()
            widget.removeBtn:SetScript("OnClick", function()
                local groups = GetSpecGroups()
                if not groups or not groups[sourceGroup] then return end
                local gd = groups[sourceGroup]
                if gd.spells then Shared.RemoveSpellFromGroupList(gd.spells, spellID) end
                if gd.spellOverrides then
                    local ovData = ExtractMergedOverrideEntry(gd.spellOverrides, spellID)
                    if ovData then
                        local specOv = EnsureUngroupedOverrides()
                        if specOv then StoreMergedOverrideEntry(specOv, spellID, ovData) end
                    end
                end
                if selectedSpellID == spellID then
                    selectedSpellID = nil
                    selectedSpellGroupIndex = nil
                    ClearRightPanel()
                end
                SaveAndRefresh(); RefreshLeftPanelIfNeeded()
            end)
        end

        widget.nameText:ClearAllPoints()
        widget.nameText:SetPoint("LEFT", widget.iconContainer, "RIGHT", 6, 0)
        widget.nameText:SetPoint("RIGHT", widget.removeBtn:IsShown() and widget.removeBtn or row, widget.removeBtn:IsShown() and "LEFT" or "RIGHT", widget.removeBtn:IsShown() and -2 or -4, 0)
        widget.nameText:SetText((trinketSlot and trinketName)
            or (customItemID and customItemName)
            or nativeItemName
            or C_Spell.GetSpellName(displayID) or L["Unknown"])
        if isActive == false then UI.SetTextMuted(widget.nameText)
        elseif selectedSpellID == spellID then UI.SetTextWhite(widget.nameText)
        else UI.SetTextSubtle(widget.nameText) end

        widget.btnUp:Hide()
        widget.btnUp:SetScript("OnClick", nil)
        widget.btnDown:Hide()
        widget.btnDown:SetScript("OnClick", nil)
        if sourceGroup and spellIndex and spellCount then
            widget.btnUp:Show()
            widget.btnUp:SetEnabled(spellIndex ~= 1)
            widget.btnUp:SetScript("OnClick", function()
                local groups = GetSpecGroups()
                if not groups or not groups[sourceGroup] then return end
                local spells = groups[sourceGroup].spells
                if spells and spellIndex > 1 then
                    spells[spellIndex], spells[spellIndex - 1] = spells[spellIndex - 1], spells[spellIndex]
                    SaveAndRefresh(); RefreshLeftPanelIfNeeded()
                end
            end)
            widget.btnDown:Show()
            widget.btnDown:SetEnabled(spellIndex ~= spellCount)
            widget.btnDown:SetScript("OnClick", function()
                local groups = GetSpecGroups()
                if not groups or not groups[sourceGroup] then return end
                local spells = groups[sourceGroup].spells
                if spells and spellIndex < #spells then
                    spells[spellIndex], spells[spellIndex + 1] = spells[spellIndex + 1], spells[spellIndex]
                    SaveAndRefresh(); RefreshLeftPanelIfNeeded()
                end
            end)
        end

        widget.clickBtn:SetScript("OnClick", function()
            selectedSpellID = spellID
            selectedGroupIndex = nil
            selectedSpellGroupIndex = sourceGroup
            ShowSpellSettings(spellID, sourceGroup)
            RefreshLeftPanelIfNeeded()
        end)
        widget.clickBtn:SetScript("OnDragStart", function() StartDrag(spellID, sourceGroup, row) end)
        widget.clickBtn:SetScript("OnDragStop", function() EndDrag() end)

        return widget
    end

    BuildIconGrid = function()
        ReleaseAllGridIcons()

        local iconGap = CDM.db and CDM.db.spacing or GRID_ICON_GAP
        minGridHeight = GRID_ICON_SIZE + 8

        UpdateGridVisibility()
        local showAddIcon = currentSpecID == playerSpecID and cooldownBarView == "essential"
        local showRotateIcon = currentSpecID == playerSpecID
        addRowIcon:SetShown(showAddIcon)
        rotateBarIcon:SetShown(showRotateIcon)
        if currentSpecID ~= playerSpecID then return end

        local spells = GetUngroupedSpellsFromViewers()
        local totalSpells = #spells
        local availableWidth = (iconGridFrame:GetWidth() or 0) - 8
        if availableWidth <= 0 then availableWidth = 456 end
        local totalSlots = totalSpells
        local rowWidth = totalSlots * GRID_ICON_SIZE + math.max(0, totalSlots - 1) * iconGap
        local maxScroll = math.max(0, rowWidth - availableWidth)
        local previousScroll = iconScrollFrame:GetHorizontalScroll() or 0
        local startX = maxScroll > 0 and 0 or math.floor((availableWidth - rowWidth) / 2)
        local cfgColor = CDM_C.GetConfigValue("borderColor", { r = 0, g = 0, b = 0, a = 1 })

        iconScrollFrame:ClearAllPoints()
        iconScrollFrame:SetPoint("TOPLEFT", iconGridFrame, "TOPLEFT", 4, -4)
        iconScrollFrame:SetWidth(availableWidth)
        iconScrollChild:SetSize(math.max(availableWidth, rowWidth), GRID_ICON_SIZE)
        horizontalScroll:SetMinMaxValues(0, maxScroll)
        horizontalScrollBar:SetShown(maxScroll > 0)
        if maxScroll > 0 then
            horizontalThumb:SetWidth(math.min(availableWidth,
                math.max(23, math.floor(availableWidth * availableWidth / rowWidth))))
        end
        horizontalScroll:SetValue(maxScroll - math.min(previousScroll, maxScroll))

        addRowIcon:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)
        local plusLength = math.floor(GRID_ICON_SIZE * 0.5)
        local plusThickness = math.floor(GRID_ICON_SIZE * 0.14)
        addRowShadowH:SetSize(plusLength, plusThickness)
        addRowShadowV:SetSize(plusThickness, plusLength)
        addRowPlusH:SetSize(plusLength, plusThickness)
        addRowPlusV:SetSize(plusThickness, plusLength)
        rotateBarIcon:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)
        local rotateTextureSize = math.floor(GRID_ICON_SIZE * 0.62)
        rotateBarTexture:SetSize(rotateTextureSize, rotateTextureSize)

        local function GetSlotPosition(slotIndex)
            return startX + (slotIndex - 1) * (GRID_ICON_SIZE + iconGap), 0
        end

        for i, spellID in ipairs(spells) do
            local frame = AcquireGridIcon()
            frame.cdmSpellID = spellID

            if CDM.BORDER and CDM.BORDER.CreateBorder then
                CDM.BORDER:CreateBorder(frame, { forceUpdate = true })
                if CDM.BORDER.activeBorders then CDM.BORDER.activeBorders[frame] = nil end
            end

            local x, y = GetSlotPosition(i)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", x, y)

            local trinketSlot, _, _, trinketIcon = GetTrinketInfoForID(spellID)
            local customItemID, _, customItemIcon = GetCustomItemInfoForID(spellID)
            local _, nativeItemName, nativeItemIcon, nativeFallbackItemID = GetNativeItemCategoryInfo(spellID)
            local tex
            if trinketSlot then
                tex = trinketIcon
            elseif customItemID then
                tex = customItemIcon
            elseif nativeItemIcon then
                tex = nativeItemIcon
            else
                tex = GetPromotedBuffTexture(spellID) or C_Spell.GetSpellTexture(GetDisplaySpellID(spellID))
            end
            if tex then frame.icon:SetTexture(tex) end
            frame.icon:SetDesaturated(false)
            frame.icon:SetAlpha(1)

            if frame.border then
                local promotedColor = IsCooldownBuffTracked(currentSpecID, spellID)
                    and CDM.GetSpellBorderColor and CDM:GetSpellBorderColor(currentSpecID, spellID)
                local color = promotedColor or cfgColor
                frame.border:SetBackdropBorderColor(color.r, color.g, color.b, color.a or 1)
            end

            frame.overlay:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if trinketSlot then
                    GameTooltip:SetInventoryItem("player", trinketSlot)
                elseif customItemID then
                    GameTooltip:SetItemByID(customItemID)
                elseif nativeItemName then
                    if nativeFallbackItemID then
                        GameTooltip:SetItemByID(nativeFallbackItemID)
                    else
                        GameTooltip:SetText(nativeItemName)
                    end
                else
                    GameTooltip:SetSpellByID(spellID)
                end
                GameTooltip:Show()
            end)
            frame.overlay:SetScript("OnLeave", function() GameTooltip:Hide() end)
            frame.overlay:SetScript("OnClick", function(_, button)
                if button == "RightButton" and IsCooldownBuffTracked(currentSpecID, spellID) then
                    MenuUtil.CreateContextMenu(frame.overlay, function(_, rootDescription)
                        rootDescription:CreateButton("Remove", function()
                            SetCooldownBuffTracked(currentSpecID, spellID, false)
                            RemoveUngroupedOrderEntry(spellID)
                            selectedSpellID = nil
                            selectedSpellGroupIndex = nil
                            ClearRightPanel()
                            API:Refresh("BUFF_DATA")
                            SaveAndRefresh()
                            RefreshLeftPanelIfNeeded()
                        end)
                    end)
                    return
                end
                selectedSpellID = spellID
                selectedGroupIndex = nil
                selectedSpellGroupIndex = nil
                ShowSpellSettings(spellID, nil)
                RefreshLeftPanelIfNeeded()
            end)
            frame.overlay:SetScript("OnDragStart", function() StartDrag(spellID, nil, frame) end)
            frame.overlay:SetScript("OnDragStop", function() EndDrag() end)
        end

        rotateBarIcon:Show()

        if showAddIcon then
            addRowIcon:Show()
        end

        iconGridFrame:SetHeight(minGridHeight + (maxScroll > 0 and gridScrollbarSpace or 0))
    end

    SetCooldownBarView = function(view)
        if view == cooldownBarView then return end
        cooldownBarView = view
        if selectedSpellID and not selectedSpellGroupIndex then
            selectedSpellID = nil
            ClearRightPanel()
        end
        RefreshAll()
    end

    local function BuildGroupsPanel()
        if renameActiveGroupIndex and renameActiveEditBox then
            local newName = renameActiveEditBox:GetText()
            local groups = GetSpecGroups()
            local gd = groups and groups[renameActiveGroupIndex]
            if gd and newName and newName ~= "" then gd.name = newName end
            renameActiveGroupIndex = nil
            renameActiveEditBox = nil
        end

        local lc = leftChild
        headerPool:ReleaseAll()
        groupContainerPool:ReleaseAll()
        spellRowPool:ReleaseAll()
        emptyRowPool:ReleaseAll()
        ClearDropTargets()
        RegisterDropTarget(iconGridFrame, nil, {
            label = GetUngroupedDropLabel,
            insertIndex = gridIconsActive + 1,
        })
        for i = 1, gridIconsActive do
            RegisterDropTarget(gridIcons[i], nil, {
                label = GetUngroupedDropLabel,
                highlightFrame = iconGridFrame,
                insertIndex = i,
                showInsertion = true,
                horizontalInsertion = true,
            })
        end

        local isViewingPlayer = currentSpecID == playerSpecID
        local activeSpellSet = isViewingPlayer and BuildCooldownActiveSet() or nil
        local yOff = 0
        local groups = GetSpecGroups()
        if groups then
            for groupIndex, groupData in ipairs(groups) do
                local isExpanded = expandedGroups[groupIndex] ~= false
                local displayName = groupData.name or ("Group " .. groupIndex)

                local h = headerPool:Acquire(lc)
                Shared.ConfigureExpandableHeader(h, yOff, isExpanded, displayName, selectedGroupIndex == groupIndex)

                if renameActiveGroupIndex == groupIndex then
                    renameActiveEditBox = Shared.SetupRenameEditBox(
                        h.row, h.bgLeft, h.bgRight, h.nameText,
                        displayName,
                        function(newName)
                            groupData.name = newName
                            renameActiveGroupIndex = nil
                            renameActiveEditBox = nil
                            if selectedGroupIndex == groupIndex then ShowGroupSettings(groupIndex) end
                            RefreshLeftPanelIfNeeded()
                        end,
                        function()
                            renameActiveGroupIndex = nil
                            renameActiveEditBox = nil
                            RefreshLeftPanelIfNeeded()
                        end
                    )
                end

                h.deleteBtn:SetScript("OnClick", function()
                    local function DoDelete()
                        local specGroups = EnsureGroups()
                        if specGroups then
                            local gd = specGroups[groupIndex]
                            if gd and gd.spells and gd.spellOverrides then
                                local specOv = EnsureUngroupedOverrides()
                                if specOv then
                                    for _, sid in ipairs(gd.spells) do
                                        local ovData = ExtractMergedOverrideEntry(gd.spellOverrides, sid)
                                        if ovData then StoreMergedOverrideEntry(specOv, sid, ovData) end
                                    end
                                end
                            end
                            table.remove(specGroups, groupIndex)
                        end
                        if selectedGroupIndex == groupIndex then
                            selectedGroupIndex = nil
                            selectedSpellID = nil
                            ClearRightPanel()
                        elseif selectedGroupIndex and selectedGroupIndex > groupIndex then
                            selectedGroupIndex = selectedGroupIndex - 1
                        end
                        if selectedSpellGroupIndex then
                            if selectedSpellGroupIndex == groupIndex then
                                selectedSpellGroupIndex = nil
                                selectedSpellID = nil
                            elseif selectedSpellGroupIndex > groupIndex then
                                selectedSpellGroupIndex = selectedSpellGroupIndex - 1
                            end
                        end
                        local newExpanded = {}
                        for idx, val in pairs(expandedGroups) do
                            if idx < groupIndex then
                                newExpanded[idx] = val
                            elseif idx > groupIndex then
                                newExpanded[idx - 1] = val
                            end
                        end
                        expandedGroups = newExpanded
                        SaveAndRefresh(); RefreshLeftPanelIfNeeded()
                    end

                    local spellCount = groupData.spells and #groupData.spells or 0
                    if spellCount > 0 then
                        local dialog = StaticPopupDialogs["AYIJE_CDM_CONFIRM_DELETE_CD_GROUP"]
                        dialog.text = string.format(
                            L["Delete group with %d spell(s)?"],
                            spellCount
                        )
                        dialog._pendingDelete = DoDelete
                        StaticPopup_Show("AYIJE_CDM_CONFIRM_DELETE_CD_GROUP")
                    else
                        DoDelete()
                    end
                end)

                h.selectBtn:SetScript("OnClick", function(_, button)
                    if button == "RightButton" then
                        MenuUtil.CreateContextMenu(h.selectBtn, function(_, rootDescription)
                            Shared.BuildGroupContextMenu(rootDescription,
                                { rename = L["Rename"], duplicate = L["Duplicate"], copyTo = L["Copy to"] },
                                function()
                                    renameActiveGroupIndex = groupIndex
                                    RefreshLeftPanelIfNeeded()
                                end,
                                function()
                                    local specGroups = EnsureGroups()
                                    if not specGroups then return end
                                    local newIdx = DuplicateGroup(groupData, specGroups)
                                    expandedGroups[newIdx] = true
                                    selectedGroupIndex = newIdx
                                    selectedSpellID = nil
                                    if currentSpecID == playerSpecID then SaveAndRefresh() end
                                    ShowGroupSettings(newIdx)
                                    RefreshLeftPanelIfNeeded()
                                end,
                                function(specID)
                                    CopyGroupSettingsToSpec(groupData, specID)
                                    if specID == currentSpecID then RefreshLeftPanelIfNeeded() end
                                    if specID == playerSpecID then SaveAndRefresh() end
                                end
                            )
                        end)
                        return
                    end

                    local now = GetTime()
                    if renameLastClickGroup == groupIndex and (now - renameLastClickTime) < 0.4 then
                        renameActiveGroupIndex = groupIndex
                        renameLastClickTime = 0
                        renameLastClickGroup = nil
                        RefreshLeftPanelIfNeeded()
                        return
                    end
                    renameLastClickTime = now
                    renameLastClickGroup = groupIndex
                    selectedGroupIndex = groupIndex
                    selectedSpellID = nil
                    ShowGroupSettings(groupIndex)
                    RefreshLeftPanelIfNeeded()
                end)

                h.expandBtn:SetScript("OnClick", function()
                    expandedGroups[groupIndex] = not isExpanded
                    selectedGroupIndex = groupIndex
                    selectedSpellID = nil
                    ShowGroupSettings(groupIndex)
                    RefreshLeftPanelIfNeeded()
                end)

                yOff = yOff - GROUP_HEADER_H

                if isExpanded then
                    local groupContainerWidget = groupContainerPool:Acquire(lc)
                    local groupContainer = groupContainerWidget.root
                    groupContainer:ClearAllPoints()
                    groupContainer:SetPoint("TOPLEFT", SCROLL_LEFT_PAD, yOff)
                    local spells = groupData.spells
                    local targetLabel = string.format(L["Move to %s"], groupData.name or L["Group"])
                    RegisterDropTarget(groupContainer, groupIndex, {
                        label = targetLabel,
                        insertIndex = spells and (#spells + 1) or 1,
                        showInsertion = not spells or #spells == 0,
                    })
                    local groupY = 0
                    if spells and #spells > 0 then
                        for spellIndex, spellID in ipairs(spells) do
                            local active
                            local trinketSlot = GetTrinketSlotFromSentinel and GetTrinketSlotFromSentinel(spellID)
                            if trinketSlot then
                                active = not isViewingPlayer
                                    or GetInventoryItemID("player", trinketSlot) ~= nil
                            elseif GetCustomEntryForID(spellID) then
                                active = not isViewingPlayer
                                    or (API.IsCustomCooldownEntryActive and API.IsCustomCooldownEntryActive(spellID))
                                    or false
                            else
                                active = not isViewingPlayer
                                    or Shared.HasEquivalentSpellID(activeSpellSet, spellID)
                                    or Shared.HasEquivalentSpellID(activeSpellSet, ResolveCooldownOverrideID(spellID))
                            end
                            local spellWidget = spellRowPool:Acquire(groupContainer)
                            ConfigureSpellRow(
                                spellWidget,
                                groupContainer,
                                spellID,
                                groupIndex,
                                groupY,
                                active,
                                spellIndex,
                                #spells
                            )
                            RegisterDropTarget(spellWidget.root, groupIndex, {
                                label = targetLabel,
                                insertIndex = spellIndex,
                                showInsertion = true,
                                splitInsertion = true,
                                highlightFrame = groupContainer,
                            })
                            groupY = groupY - ROW_HEIGHT
                        end
                    else
                        AcquireEmptyRow(groupContainer, L["Drag spells here"])
                        groupY = -ROW_HEIGHT
                    end
                    groupContainer:SetHeight(math.abs(groupY) + 4)
                    yOff = yOff + groupY
                end
            end
        end

        lc:SetHeight(math.abs(yOff) + 40)
    end

    do
        local addGroupBtn = CreateFrame("Button", nil, buttonRow, "UIPanelButtonTemplate")
        addGroupBtn:SetSize(90, 22)
        addGroupBtn:SetPoint("LEFT", 0, 0)
        addGroupBtn:SetText(L["Add Group"])
        addGroupBtn:SetScript("OnClick", function()
            local specGroups = EnsureGroups()
            if not specGroups then return end
            local newIndex = #specGroups + 1
            local defs = CDM.defaults or {}
            local defaultSize = defs.sizeEssRow1 or { w = 46, h = 40 }
            specGroups[newIndex] = {
                name = "Group " .. newIndex,
                spells = {},
                grow = "RIGHT",
                spacing = 1,
                iconWidth = defaultSize.w,
                iconHeight = defaultSize.h,
                cooldownFontSize = defs.cooldownFontSize or 15,
                cooldownColor = { r = 1, g = 1, b = 1 },
                chargeFontSize = defs.chargeFontSize or 15,
                chargeColor = { r = 1, g = 1, b = 1, a = 1 },
                chargePosition = "BOTTOMRIGHT",
                chargeOffsetX = 0,
                chargeOffsetY = 0,
                anchorTarget = "screen",
                anchorPoint = "CENTER",
                anchorRelativeTo = "CENTER",
                offsetX = 0,
                offsetY = 0,
            }
            expandedGroups[newIndex] = true
            selectedGroupIndex = newIndex
            selectedSpellID = nil
            SaveAndRefresh(); RefreshLeftPanelIfNeeded()
            ShowGroupSettings(newIndex)
        end)

        local addIconBtn = CreateFrame("Button", nil, buttonRow, "UIPanelButtonTemplate")
        addIconBtn:SetSize(90, 22)
        addIconBtn:SetPoint("LEFT", addGroupBtn, "RIGHT", 6, 0)
        addIconBtn:SetText(L["Add Icon"])
        addIconBtn:SetScript("OnClick", function()
            if selectedGroupIndex then ShowSpellPickerPanel(selectedGroupIndex) end
        end)
        addIconBtnRef = addIconBtn
    end

    RefreshAll = function()
        lookupCacheBySpec = {}
        BuildIconGrid()
        BuildGroupsPanel()
        if addIconBtnRef then addIconBtnRef:SetEnabled(selectedGroupIndex ~= nil) end
    end

    local specDropdown, RefreshSpecDropdownText = Shared.CreateSpecDropdown(page, "TOPRIGHT", -6, -8, {
        getPlayerSpecID = function() return playerSpecID end,
        getCurrentSpecID = function() return currentSpecID end,
        onSelectionChange = function(specID)
            currentSpecID = specID
            selectedGroupIndex = nil
            selectedSpellID = nil
            selectedSpellGroupIndex = nil
            ClearRightPanel()
            RefreshAll()
        end,
    })
    specDropdown:Hide()

    local RegisterViewerCallbacks, UnregisterViewerCallbacks = Shared.CreateViewerSettingsCallbacks(QueueLeftPanelRefresh)

    subPage:HookScript("OnShow", function()
        RegisterViewerCallbacks()
        RefreshCurrentSpecID()
        RefreshAll()
        if selectedGroupIndex then
            ShowGroupSettings(selectedGroupIndex)
        elseif selectedSpellID then
            ShowSpellSettings(selectedSpellID, selectedSpellGroupIndex)
        end
        RefreshSpecDropdownText()
        specDropdown:Show()
    end)

    subPage:HookScript("OnHide", function()
        specDropdown:Hide()
        UnregisterViewerCallbacks()
        if UI and UI.CloseAllDropdownMenus then UI.CloseAllDropdownMenus() end
        CancelDrag()
    end)

    subPage:SetScript("OnMouseUp", function()
        EndDrag()
    end)

    API:RegisterRefreshCallback("cdgroups-spec-refresh", function()
        if not subPage:IsShown() then return end
        if GetTime() < suppressPanelRefreshUntil then return end
        RefreshCurrentSpecID()
        RefreshSpecDropdownText()
        QueueLeftPanelRefresh()

    end, 30, { "CD_DATA" })
end

ns._CreateCooldownGroupsPanel = CreateCooldownGroupsPanel
