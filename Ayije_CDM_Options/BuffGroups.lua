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
local suppressPanelRefreshUntil = 0
local function SaveAndRefresh()
    suppressPanelRefreshUntil = GetTime() + 0.15
    Shared.SaveVisualRefresh("BUFF_DATA")
end
local GetConfiguredBorderColor = Shared.GetConfiguredBorderColor
local ApplyConfiguredBorderColor = Shared.ApplyConfiguredBorderColor
local DestroyFrame = Shared.DestroyFrame
local CreateSlider = Shared.CreateSlider
local LEFT_INSET = Shared.LEFT_INSET
local LEFT_WIDTH = Shared.LEFT_WIDTH
local SCROLL_LEFT_PAD = Shared.SCROLL_LEFT_PAD
local RIGHT_X = Shared.RIGHT_X
local ICON_SIZE = 30
local ROW_HEIGHT = 36
local GROUP_HEADER_H = 28
local ARROW_BTN_SIZE = 29
local GRID_ICON_SIZE = 36
local GRID_ICON_GAP = 4
local GRID_DISPLAY_MAX = 14
local MIN_GRID_ROWS = 2

StaticPopupDialogs["AYIJE_CDM_CONFIRM_DELETE_GROUP"] = {
    text = "",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local fn = StaticPopupDialogs["AYIJE_CDM_CONFIRM_DELETE_GROUP"]._pendingDelete
        if fn then fn() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CreateBuffGroupsTab(page)
    local si = GetSpecialization()
    local currentSpecID = si and GetSpecializationInfo(si) or nil
    local playerSpecID = currentSpecID

    local selectedGroupIndex = nil
    local selectedSpellID = nil
    local selectedSpellGroupIndex = nil
    local expandedGroups = {}
    local RefreshAll
    local ShowSpellSettings
    local GetCustomBuffEntry
    local IsCustomBuffSpell
    local renameLastClickTime = 0
    local renameLastClickGroup = nil
    local renameActiveGroupIndex = nil
    local renameActiveEditBox = nil
    local pickerActiveGroupIndex = nil

    local _helpers = Shared.CreateGroupEditorHelpers({
        dbKey = "buffGroups",
        ungroupedDbKey = "ungroupedBuffOverrides",
        getCurrentSpecID = function() return currentSpecID end,
        setCurrentSpecID = function(v) currentSpecID = v end,
        getPlayerSpecID = function() return playerSpecID end,
        setPlayerSpecID = function(v) playerSpecID = v end,
        normalizeToBase = NormalizeToBase,
        extraCloneFields = { "staticDisplay", "countFontSize", "countColor", "countPosition", "countOffsetX", "countOffsetY" },
    })
    local RefreshCurrentSpecID = _helpers.RefreshCurrentSpecID
    local EnsureBuffGroups = _helpers.EnsureGroups
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

    local function BuildActiveSpellSet()
        if API.BuildActiveSpellSet then
            return API:BuildActiveSpellSet()
        end
        return {}
    end

    local function IsSpellInActiveSet(activeSet, spellID)
        if not activeSet then return false end
        return activeSet[spellID] == true
    end

    local function GetUngroupedBuffSpells()
        local buffViewer = _G["BuffIconCooldownViewer"]
        if not buffViewer or not buffViewer.itemFramePool then return {} end

        local icons = {}
        local seen = {}
        local groupedSet = {}
        local specGroups = GetSpecGroups()
        if type(specGroups) == "table" then
            for _, groupData in ipairs(specGroups) do
                if type(groupData) == "table" and type(groupData.spells) == "table" then
                    for _, groupedSpellID in ipairs(groupData.spells) do
                        Shared.MarkEquivalentSpellIDs(groupedSet, groupedSpellID)
                    end
                end
            end
        end

        local GetFrameData = API.GetFrameData or CDM.GetFrameData
        for frame in buffViewer.itemFramePool:EnumerateActive() do
            local matchType = API.GetBuffRegistryMatch and API:GetBuffRegistryMatch(frame) or nil
            if not matchType then
                local displayID
                local fd = GetFrameData and GetFrameData(frame)
                local catID = fd and fd.buffCategorySpellID
                if catID and catID ~= false and Shared.HasEquivalentSpellID(groupedSet, catID) then
                    displayID = nil
                else
                    local info = frame.GetCooldownInfo and frame:GetCooldownInfo() or frame.cooldownInfo
                    if info then
                        displayID = info.overrideTooltipSpellID or info.overrideSpellID or info.spellID
                    end
                    if not IsSafeNumber(displayID) then
                        displayID = frame.GetBaseSpellID and frame:GetBaseSpellID()
                    end
                    if not IsSafeNumber(displayID) then
                        displayID = API.GetPreferredBuffGroupSpellID and API:GetPreferredBuffGroupSpellID(frame)
                    end
                    if not IsSafeNumber(displayID) and API.GetBaseSpellID then
                        displayID = API:GetBaseSpellID(frame)
                    end
                end
                local hiddenBuffSet = CDM.resourcesHiddenBuffSet
                if IsSafeNumber(displayID)
                    and not Shared.HasEquivalentSpellID(groupedSet, displayID)
                    and not seen[displayID]
                    and not Shared.HasEquivalentSpellID(hiddenBuffSet, displayID)
                then
                    seen[displayID] = true
                    local li = frame.layoutIndex
                    local safeLayoutIndex = IsSafeNumber(li) and li or 0
                    icons[#icons + 1] = { spellID = displayID, layoutIndex = safeLayoutIndex }
                end
            end
        end
        table.sort(icons, function(a, b)
            if a.layoutIndex ~= b.layoutIndex then return a.layoutIndex < b.layoutIndex end
            return a.spellID < b.spellID
        end)
        return icons
    end

    local QueueLeftPanelRefresh = Shared.CreateQueueLeftPanelRefresh(page, function() return RefreshAll end)

    local ApplyUngroupedCustomBuffOrder
    local RegisterDropTarget, ClearDropTargets, StartDrag, EndDrag, CancelDrag
    local function CanDropOnUngrouped(spellID, sourceGroup)
        return sourceGroup ~= nil or IsCustomBuffSpell(spellID)
    end
    local function CanReorderUngrouped(spellID)
        return IsCustomBuffSpell(spellID)
    end
    local function GetUngroupedDropLabel(sourceGroup, spellID)
        if sourceGroup then return L["Remove from group"] end
        return IsCustomBuffSpell(spellID) and L["Reorder icons"] or nil
    end
    do
        local dragDrop = Shared.CreateDragDropController({
            onDrop = function(spellID, sourceGroup, targetGroupIndex, hitDropTarget, targetInsertIndex)
                if not spellID or not currentSpecID then return end
                if not hitDropTarget then return end
                if sourceGroup == targetGroupIndex then
                    if sourceGroup and targetInsertIndex then
                        local groups = EnsureBuffGroups()
                        local group = groups and groups[sourceGroup]
                        if group and group.spells then
                            Shared.InsertSpellInGroupList(group.spells, spellID, targetInsertIndex)
                            CDM:RefreshBuffGroupData()
                            SaveAndRefresh()
                            RefreshLeftPanelIfNeeded()
                        end
                    elseif not sourceGroup and targetInsertIndex and ApplyUngroupedCustomBuffOrder then
                        if ApplyUngroupedCustomBuffOrder(spellID, targetInsertIndex) then
                            CDM:RefreshBuffGroupData()
                            SaveAndRefresh()
                            RefreshLeftPanelIfNeeded()
                        end
                    end
                    return
                end

                local groups = EnsureBuffGroups()
                if not groups then return end

                local srcOvData = nil
                if sourceGroup then
                    local srcGroup = groups[sourceGroup]
                    if srcGroup and srcGroup.spells then
                        Shared.RemoveSpellFromGroupList(srcGroup.spells, spellID)
                    end
                    if srcGroup and srcGroup.spellOverrides then
                        srcOvData = ExtractMergedOverrideEntry(srcGroup.spellOverrides, spellID)
                    end
                else
                    local specOv = CDM.db.ungroupedBuffOverrides and CDM.db.ungroupedBuffOverrides[currentSpecID]
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
                    if specOv then
                        StoreMergedOverrideEntry(specOv, spellID, srcOvData)
                    end
                end

                if not targetGroupIndex and targetInsertIndex and IsCustomBuffSpell(spellID) then
                    ApplyUngroupedCustomBuffOrder(spellID, targetInsertIndex)
                end

                CDM:RefreshBuffGroupData()
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

    -- Ungrouped buffs live in an icon grid at the top (same structure as the
    -- Cooldowns panel), which doubles as the drop target for un-grouping.
    local minGridHeight = MIN_GRID_ROWS * (GRID_ICON_SIZE + GRID_ICON_GAP) - GRID_ICON_GAP + 8

    local iconGridFrame = CreateFrame("Frame", nil, page)
    iconGridFrame:SetPoint("TOPLEFT", LEFT_INSET, -16)
    iconGridFrame:SetPoint("TOPRIGHT", -200, -16)
    iconGridFrame:SetHeight(minGridHeight)

    iconGridFrame.highlight = iconGridFrame:CreateTexture(nil, "BACKGROUND")
    iconGridFrame.highlight:SetAllPoints()
    iconGridFrame.highlight:SetColorTexture(1, 0.82, 0, 0.12)
    iconGridFrame.highlight:Hide()

    local gridEmptyText = iconGridFrame:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
    gridEmptyText:SetPoint("LEFT", 4, 0)
    gridEmptyText:Hide()

    local gridIcons = {}
    local gridIconsActive = 0

    local function AcquireGridIcon()
        gridIconsActive = gridIconsActive + 1
        local frame = gridIcons[gridIconsActive]
        if not frame then
            frame = CreateFrame("Frame", nil, iconGridFrame)
            frame:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)
            local icon = frame:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            frame.icon = icon
            CDM_C.ApplyIconTexCoord(icon, CDM_C.GetEffectiveZoomAmount())
            local overlay = CreateFrame("Button", nil, frame)
            overlay:SetAllPoints()
            overlay:SetFrameLevel(frame:GetFrameLevel() + 2)
            overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            overlay:RegisterForDrag("LeftButton")
            frame.overlay = overlay
            gridIcons[gridIconsActive] = frame
        end
        frame:Show()
        return frame
    end

    local function ReleaseAllGridIcons()
        for i = 1, gridIconsActive do
            gridIcons[i]:Hide()
        end
        gridIconsActive = 0
    end

    local buttonRow = CreateFrame("Frame", nil, page)
    buttonRow:SetPoint("TOPLEFT", iconGridFrame, "BOTTOMLEFT", 0, -6)
    buttonRow:SetPoint("TOPRIGHT", page, "TOPRIGHT", -10, 0)
    buttonRow:SetHeight(26)

    local function UpdateGridVisibility()
        buttonRow:ClearAllPoints()
        if currentSpecID == playerSpecID then
            iconGridFrame:Show()
            buttonRow:SetPoint("TOPLEFT", iconGridFrame, "BOTTOMLEFT", 0, -6)
            buttonRow:SetPoint("TOPRIGHT", page, "TOPRIGHT", -10, 0)
        else
            iconGridFrame:Hide()
            buttonRow:SetPoint("TOPLEFT", page, "TOPLEFT", LEFT_INSET, -16)
            buttonRow:SetPoint("TOPRIGHT", page, "TOPRIGHT", -10, 0)
        end
    end

    local leftScroll = CreateFrame("ScrollFrame", "AyijeCDM_BuffGroupsLeftScroll", page, "ScrollFrameTemplate")
    leftScroll:SetPoint("TOPLEFT", buttonRow, "BOTTOMLEFT", -SCROLL_LEFT_PAD, -4)
    leftScroll:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", LEFT_INSET - SCROLL_LEFT_PAD, 20)
    leftScroll:SetWidth(LEFT_WIDTH + SCROLL_LEFT_PAD)

    local leftChild = CreateFrame("Frame", nil, leftScroll)
    leftChild:SetSize(LEFT_WIDTH + SCROLL_LEFT_PAD, 1200)
    leftScroll:SetScrollChild(leftChild)

    local rightPanel = CreateFrame("Frame", nil, page)
    rightPanel:SetPoint("TOPLEFT", buttonRow, "BOTTOMLEFT", RIGHT_X - LEFT_INSET, -4)
    rightPanel:SetPoint("BOTTOMRIGHT", -10, 20)

    local rightPlaceholder = rightPanel:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
    rightPlaceholder:SetPoint("TOP", 0, -20)
    rightPlaceholder:SetText(L["Select a group or spell to edit settings"])
    UI.SetTextMuted(rightPlaceholder)

    local rightPanelManager = Shared.CreateRightPanelManager(rightPanel, rightPlaceholder, DestroyFrame)
    local RegisterRightPanelDropdown = rightPanelManager.RegisterDropdown
    local CreateRightScrollContent = rightPanelManager.CreateScrollContent
    local ClearRightPanel = function()
        pickerActiveGroupIndex = nil
        rightPanelManager.Clear()
    end

    local function GetViewerSpellListForSpec(specID)
        if specID == playerSpecID then
            local seen, list = {}, {}
            for _, cat in ipairs(CDM_C.VIEWER_CATEGORIES_BUFF) do
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
        else
            local raw = API:GetSpecBuffSpellCache(specID)
            if not raw then return {} end
            local seen, list = {}, {}
            for _, entry in ipairs(raw) do
                local cdID = entry.cooldownID
                local sid = entry.spellID
                if sid and cdID and not seen[cdID] then
                    seen[cdID] = true
                    list[#list + 1] = { cdID = cdID, spellID = sid }
                end
            end
            return list
        end
    end

    local function GetUntrackedViewerSpellListForCurrentSpec()
        local activeSet = {}
        local GetFrameData = API.GetFrameData or CDM.GetFrameData
        local viewer = _G[CDM_C.VIEWERS.BUFF]
        if viewer and viewer.itemFramePool then
            for frame in viewer.itemFramePool:EnumerateActive() do
                local activeID
                local fd = GetFrameData and GetFrameData(frame)
                activeID = fd and fd.buffCategorySpellID
                if not IsSafeNumber(activeID) then
                    local info = frame.GetCooldownInfo and frame:GetCooldownInfo() or frame.cooldownInfo
                    if info then
                        activeID = info.overrideTooltipSpellID or info.overrideSpellID or info.spellID
                    end
                end
                if not IsSafeNumber(activeID) then
                    activeID = frame.GetBaseSpellID and frame:GetBaseSpellID()
                end
                if IsSafeNumber(activeID) then
                    activeSet[activeID] = true
                end
            end
        end
        local seen, list = {}, {}
        for _, cat in ipairs(CDM_C.VIEWER_CATEGORIES_BUFF) do
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

    local function GetAvailableSpellsForPicker(specID)
        local allSlots = (specID == playerSpecID)
            and GetUntrackedViewerSpellListForCurrentSpec()
            or GetViewerSpellListForSpec(specID)
        local assigned = {}
        local groups = CDM.db.buffGroups and CDM.db.buffGroups[specID]
        if groups then
            for _, group in ipairs(groups) do
                for _, sid in ipairs(group.spells or {}) do
                    Shared.MarkEquivalentSpellIDs(assigned, sid)
                end
            end
        end
        local hiddenBuffSet = CDM.resourcesHiddenBuffSet
        local seen = {}
        local result = {}
        for _, slot in ipairs(allSlots) do
            local spellID = slot.spellID
            if not Shared.HasEquivalentSpellID(assigned, spellID)
                and not seen[slot.cdID]
                and not Shared.HasEquivalentSpellID(hiddenBuffSet, spellID)
            then
                seen[slot.cdID] = true
                local name = C_Spell.GetSpellName(spellID) or ("Spell " .. spellID)
                local icon = C_Spell.GetSpellTexture(spellID)
                local isKnown = IsPlayerSpell(spellID)
                result[#result + 1] = { spellID = spellID, name = name, icon = icon, isKnown = isKnown }
            end
        end
        table.sort(result, function(a, b) return a.name < b.name end)
        return result
    end

    local function ShowGroupSettings(groupIndex)
        pickerActiveGroupIndex = nil
        local groups = GetSpecGroups()
        if not groups or not groups[groupIndex] then ClearRightPanel(); return end
        local _, rc = CreateRightScrollContent(700)
        local xSlider, ySlider = Shared.RenderGroupSettingsPanel({
            rc = rc, gd = groups[groupIndex], groupIndex = groupIndex,
            registerDropdown = RegisterRightPanelDropdown,
            saveAndRefresh = SaveAndRefresh, createSlider = CreateSlider, L = L,
            preSpacingSection = function(parent, yOff)
                local cb = UI.CreateModernCheckbox(parent, L["Static Display"],
                    groups[groupIndex].staticDisplay or false,
                    function(checked) groups[groupIndex].staticDisplay = checked or nil; SaveAndRefresh() end)
                cb:SetPoint("TOPLEFT", 0, yOff)
                return yOff - 36
            end,
            textFields = {
                sizeKey = "countFontSize", colorKey = "countColor",
                posKey = "countPosition", xKey = "countOffsetX", yKey = "countOffsetY",
                sizeDefault = 15, posDefault = "BOTTOMRIGHT",
            },
            anchorTargets = {
                { label = L["Screen"], value = "screen" },
                { label = L["Player Frame"], value = "playerFrame" },
                { label = L["Essential Viewer"], value = "essential" },
                { label = L["Buff Viewer"], value = "buff" },
            },
            anchorRelLabels = {
                playerFrame = L["Player Frame Point"],
                buff = L["Buff Viewer Point"],
            },
        })
        if ns.RegisterAnchorPositionUpdater then
            ns.RegisterAnchorPositionUpdater("buff_group_" .. groupIndex, function(x, y)
                if selectedGroupIndex ~= groupIndex or not page:IsShown() then return end
                xSlider:UpdateUIValue(x)
                ySlider:UpdateUIValue(y)
            end)
        end
    end

    local spellIconBorders = {}

    local function BuildOverrideSection(rc, yOff, spellID, groupIndex, existingOv, ensureOv, defaults, placeholderOpts, isCustomBuff, context)
        local save = context and context.save or SaveAndRefresh
        local refresh = context and context.refresh or function() ShowSpellSettings(spellID, groupIndex) end
        local registerDropdown = context and context.registerDropdown or RegisterRightPanelDropdown
        yOff = yOff - 10
        local overrideHeader = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font18")
        overrideHeader:SetPoint("TOPLEFT", 0, yOff)
        overrideHeader:SetText(L["Per-Spell Overrides"])
        overrideHeader:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
        yOff = yOff - 34

        -- Kept above the checkbox run so the column of checkboxes reads as one
        -- uninterrupted block.
        do
            local currentIcon = existingOv and existingOv.customIcon
            local hasIcon = type(currentIcon) == "table" and tonumber(currentIcon.id)

            local iconBtn = UI.CreateTextButton(rc)
            iconBtn:SetSize(110, 22)
            iconBtn:SetPoint("TOPLEFT", 0, yOff)
            iconBtn:SetText(L["Custom Icon"])
            iconBtn:SetScript("OnClick", function()
                UI.ShowCustomIconPopup(currentIcon, function(result)
                    local ov = ensureOv()
                    if not ov then return end
                    ov.customIcon = result
                    if result then API.buffCustomIconsInUse = true end
                    save()
                    refresh()
                end)
            end)

            local iconPreview = rc:CreateTexture(nil, "ARTWORK")
            iconPreview:SetSize(20, 20)
            iconPreview:SetPoint("LEFT", iconBtn, "RIGHT", 8, 0)
            iconPreview:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local iconLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
            iconLabel:SetPoint("LEFT", iconPreview, "RIGHT", 6, 0)

            if hasIcon then
                local tex, kindLabel
                if currentIcon.kind == "item" then
                    tex = C_Item.GetItemIconByID(currentIcon.id)
                    if not tex then C_Item.RequestLoadItemDataByID(currentIcon.id) end
                    kindLabel = L["Item"]
                elseif currentIcon.kind == "texture" then
                    tex = currentIcon.id
                    kindLabel = L["Icon ID"]
                else
                    tex = C_Spell.GetSpellTexture(currentIcon.id)
                    kindLabel = L["Spell"]
                end
                iconPreview:SetTexture(tex)
                iconLabel:SetText(string.format("%s %d", kindLabel, currentIcon.id))
                UI.SetTextSubtle(iconLabel)
            else
                iconPreview:SetTexture(nil)
                iconLabel:SetText(L["Default"])
                UI.SetTextFaint(iconLabel)
            end

            yOff = yOff - 36
        end

        local hideCdChecked = existingOv and existingOv.hideCooldown or false
        local hideVisualsChecked = existingOv and existingOv.hideVisuals or false
        local hideCdCheckbox, hideVisualsCheckbox

        if not isCustomBuff then
            hideCdCheckbox = UI.CreateModernCheckbox(
                rc,
                L["Hide Cooldown Timer"],
                hideCdChecked,
                function(checked)
                    local ov = ensureOv()
                    if not ov then return end
                    ov.hideCooldown = checked or nil
                    save()
                end
            )
            hideCdCheckbox:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 36
        end

        if not isCustomBuff then
            hideVisualsCheckbox = UI.CreateModernCheckbox(
                rc,
                L["Hide Icon"],
                hideVisualsChecked,
                function(checked)
                    local ov = ensureOv()
                    if not ov then return end
                    ov.hideVisuals = checked or nil
                    save()
                end
            )
            hideVisualsCheckbox:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 36
        end

        if placeholderOpts and not isCustomBuff then
            local placeholderChecked = placeholderOpts.forced or (existingOv and existingOv.placeholder) or false
            local placeholderCheckbox
            placeholderCheckbox = UI.CreateModernCheckbox(
                rc,
                L["Show Placeholder"],
                placeholderChecked,
                function(checked)
                    if placeholderOpts.forced then
                        placeholderCheckbox:SetChecked(true)
                        return
                    end
                    local ov = ensureOv()
                    if not ov then return end
                    ov.placeholder = checked or nil
                    save()
                end
            )
            placeholderCheckbox:SetPoint("TOPLEFT", 0, yOff)
            if placeholderOpts.forced or not placeholderOpts.isStatic then
                placeholderCheckbox.checkbox:Disable()
                if not placeholderOpts.forced then
                    placeholderCheckbox.label:SetTextColor(0.5, 0.5, 0.5)
                end
            end
            yOff = yOff - 36
        end

        local soundChecked = existingOv and existingOv.soundEnabled or false
        local soundCheckbox = UI.CreateModernCheckbox(
            rc,
            L["Play Sound"],
            soundChecked,
            function(checked)
                local ov = ensureOv()
                if not ov then return end
                ov.soundEnabled = checked or nil
                if checked then
                    ov.ttsEnabled = nil
                    ov.ttsOnShow = nil
                    ov.ttsOnHide = nil
                    ov.ttsOnShowEnabled = nil
                    ov.ttsOnHideEnabled = nil
                    if not ov.soundOnShowEnabled and not ov.soundOnHideEnabled then
                        ov.soundOnShowEnabled = true
                    end
                else
                    ov.soundOnShow = nil
                    ov.soundOnHide = nil
                    ov.soundOnShowEnabled = nil
                    ov.soundOnHideEnabled = nil
                end
                save()
                refresh()
            end
        )
        soundCheckbox:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 36

        if soundChecked then
            local ov = existingOv or {}

            local soundOnShowEnabled = ov.soundOnShowEnabled or false
            local soundOnShowCheckbox
            soundOnShowCheckbox = UI.CreateModernCheckbox(rc, L["On Show"], soundOnShowEnabled,
                function(checked)
                    local o = ensureOv()
                    if not o then return end
                    if not checked and o.soundOnHideEnabled == false then
                        soundOnShowCheckbox:SetChecked(true)
                        return
                    end
                    o.soundOnShowEnabled = checked
                    if not checked then o.soundOnShow = nil end
                    save()
                    refresh()
                end
            )
            soundOnShowCheckbox:SetPoint("TOPLEFT", 20, yOff)
            yOff = yOff - 30

            if soundOnShowEnabled then
                local showDropdown = registerDropdown(
                    CreateFrame("DropdownButton", nil, rc, "WowStyle1DropdownTemplate")
                )
                showDropdown:SetWidth(220)
                showDropdown:SetPoint("TOPLEFT", 26, yOff)
                showDropdown:SetDefaultText(ov.soundOnShow or "None")
                UI.SetupMediaDropdown(showDropdown, "sound",
                    function() return ov.soundOnShow or "None" end,
                    function(name)
                        local o = ensureOv()
                        local val = (name ~= "None") and name or nil
                        if o then o.soundOnShow = val end
                        ov.soundOnShow = val
                        showDropdown:SetDefaultText(name)
                        save()
                    end
                )
                yOff = yOff - 40
            end

            local soundOnHideEnabled = ov.soundOnHideEnabled or false
            local soundOnHideCheckbox
            soundOnHideCheckbox = UI.CreateModernCheckbox(rc, L["On Hide"], soundOnHideEnabled,
                function(checked)
                    local o = ensureOv()
                    if not o then return end
                    if not checked and o.soundOnShowEnabled == false then
                        soundOnHideCheckbox:SetChecked(true)
                        return
                    end
                    o.soundOnHideEnabled = checked
                    if not checked then o.soundOnHide = nil end
                    save()
                    refresh()
                end
            )
            soundOnHideCheckbox:SetPoint("TOPLEFT", 20, yOff)
            yOff = yOff - 30

            if soundOnHideEnabled then
                local hideDropdown = registerDropdown(
                    CreateFrame("DropdownButton", nil, rc, "WowStyle1DropdownTemplate")
                )
                hideDropdown:SetWidth(220)
                hideDropdown:SetPoint("TOPLEFT", 26, yOff)
                hideDropdown:SetDefaultText(ov.soundOnHide or "None")
                UI.SetupMediaDropdown(hideDropdown, "sound",
                    function() return ov.soundOnHide or "None" end,
                    function(name)
                        local o = ensureOv()
                        local val = (name ~= "None") and name or nil
                        if o then o.soundOnHide = val end
                        ov.soundOnHide = val
                        hideDropdown:SetDefaultText(name)
                        save()
                    end
                )
                yOff = yOff - 40
            end
        end

        local ttsChecked = existingOv and existingOv.ttsEnabled or false
        local ttsCheckbox = UI.CreateModernCheckbox(
            rc,
            L["Text to Speech"],
            ttsChecked,
            function(checked)
                local ov = ensureOv()
                if not ov then return end
                ov.ttsEnabled = checked or nil
                if checked then
                    ov.soundEnabled = nil
                    ov.soundOnShow = nil
                    ov.soundOnHide = nil
                    ov.soundOnShowEnabled = nil
                    ov.soundOnHideEnabled = nil
                    if not ov.ttsOnShowEnabled and not ov.ttsOnHideEnabled then
                        ov.ttsOnShowEnabled = true
                    end
                else
                    ov.ttsOnShow = nil
                    ov.ttsOnHide = nil
                    ov.ttsOnShowEnabled = nil
                    ov.ttsOnHideEnabled = nil
                end
                save()
                refresh()
            end
        )
        ttsCheckbox:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 36

        if ttsChecked then
            local ov = existingOv or {}

            local voiceBtn = UI.CreateTextButton(rc)
            voiceBtn:SetSize(120, 22)
            voiceBtn:SetText(L["Voice Settings"])
            voiceBtn:SetPoint("LEFT", ttsCheckbox, "LEFT", 200, 0)
            voiceBtn:SetScript("OnClick", function()
                if ChatConfigFrame then
                    ChatConfigFrame:Show()
                    if ChatConfigFrameChatTabManager and VOICE_WINDOW_ID then
                        ChatConfigFrameChatTabManager:UpdateSelection(VOICE_WINDOW_ID)
                    end
                end
            end)

            local ttsOnShowEnabled = ov.ttsOnShowEnabled or false
            local ttsOnShowCheckbox
            ttsOnShowCheckbox = UI.CreateModernCheckbox(rc, L["On Show"], ttsOnShowEnabled,
                function(checked)
                    local o = ensureOv()
                    if not o then return end
                    if not checked and not o.ttsOnHideEnabled then
                        ttsOnShowCheckbox:SetChecked(true)
                        return
                    end
                    o.ttsOnShowEnabled = checked or nil
                    if not checked then o.ttsOnShow = nil end
                    save()
                    refresh()
                end
            )
            ttsOnShowCheckbox:SetPoint("TOPLEFT", 20, yOff)
            yOff = yOff - 30

            if ttsOnShowEnabled then
                local ttsShowBox = CreateFrame("EditBox", nil, rc, "InputBoxTemplate")
                ttsShowBox:SetSize(140, 22)
                ttsShowBox:SetPoint("TOPLEFT", 26, yOff)
                ttsShowBox:SetFontObject("AyijeCDM_Font14")
                ttsShowBox:SetAutoFocus(false)
                ttsShowBox:SetMaxLetters(200)
                ttsShowBox:SetText(ov.ttsOnShow or "")
                ttsShowBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
                ttsShowBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                ttsShowBox:SetScript("OnEditFocusLost", function(self)
                    local o = ensureOv()
                    local val = self:GetText()
                    val = (val ~= "") and val or nil
                    if o then o.ttsOnShow = val end
                    ov.ttsOnShow = val
                    save()
                end)
                local ttsShowHint = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
                ttsShowHint:SetText(L["(empty = spell name)"])
                UI.SetTextMuted(ttsShowHint)
                ttsShowHint:SetPoint("LEFT", ttsShowBox, "RIGHT", 6, 0)
                yOff = yOff - 28
            end

            local ttsOnHideEnabled = ov.ttsOnHideEnabled or false
            local ttsOnHideCheckbox
            ttsOnHideCheckbox = UI.CreateModernCheckbox(rc, L["On Hide"], ttsOnHideEnabled,
                function(checked)
                    local o = ensureOv()
                    if not o then return end
                    if not checked and not o.ttsOnShowEnabled then
                        ttsOnHideCheckbox:SetChecked(true)
                        return
                    end
                    o.ttsOnHideEnabled = checked or nil
                    if not checked then o.ttsOnHide = nil end
                    save()
                    refresh()
                end
            )
            ttsOnHideCheckbox:SetPoint("TOPLEFT", 20, yOff)
            yOff = yOff - 30

            if ttsOnHideEnabled then
                local ttsHideBox = CreateFrame("EditBox", nil, rc, "InputBoxTemplate")
                ttsHideBox:SetSize(140, 22)
                ttsHideBox:SetPoint("TOPLEFT", 26, yOff)
                ttsHideBox:SetFontObject("AyijeCDM_Font14")
                ttsHideBox:SetAutoFocus(false)
                ttsHideBox:SetMaxLetters(200)
                ttsHideBox:SetText(ov.ttsOnHide or "")
                ttsHideBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
                ttsHideBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                ttsHideBox:SetScript("OnEditFocusLost", function(self)
                    local o = ensureOv()
                    local val = self:GetText()
                    val = (val ~= "") and val or nil
                    if o then o.ttsOnHide = val end
                    ov.ttsOnHide = val
                    save()
                end)
                local ttsHideHint = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
                ttsHideHint:SetText(L["(empty = spell name)"])
                UI.SetTextMuted(ttsHideHint)
                ttsHideHint:SetPoint("LEFT", ttsHideBox, "RIGHT", 6, 0)
                yOff = yOff - 28
            end
        end

        if not isCustomBuff then
            yOff = Shared.BuildTextOverrideWidgets(rc, yOff, {
                showHeader = false,
                existingOv = existingOv,
                ensureOv = ensureOv,
                defaults = defaults,
                fields = {
                    cdSize = "cooldownFontSize", cdColor = "cooldownColor",
                    chargeSize = "countFontSize", chargeColor = "countColor",
                    chargePos = "countPosition", chargeX = "countOffsetX", chargeY = "countOffsetY",
                },
                colorAlpha = false,
                save = save,
                onToggle = refresh,
                createDropdown = function(p) return registerDropdown(CreateFrame("DropdownButton", nil, p, "WowStyle1DropdownTemplate")) end,
            })
        end

        return yOff
    end

    ns.BuildBuffOverrideSection = BuildOverrideSection

    ShowSpellSettings = function(spellID, groupIndex)
        pickerActiveGroupIndex = nil
        if not spellID or not currentSpecID then
            ClearRightPanel()
            return
        end

        local displaySpellID = spellID

        local _, rc = CreateRightScrollContent(700)

        local yOff = 0

        local iconContainer = CreateFrame("Frame", nil, rc)
        iconContainer:SetSize(28, 28)
        iconContainer:SetPoint("TOPLEFT", 0, yOff)

        local iconTex = iconContainer:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        local cbEntry = GetCustomBuffEntry(displaySpellID)
        local tex = (cbEntry and cbEntry.icon) or C_Spell.GetSpellTexture(displaySpellID)
        if tex then iconTex:SetTexture(tex) end
        CDM_C.ApplyIconTexCoord(iconTex, CDM_C.GetEffectiveZoomAmount())

        if CDM.BORDER and CDM.BORDER.CreateBorder then
            CDM.BORDER:CreateBorder(iconContainer)
            if CDM.BORDER.activeBorders then
                CDM.BORDER.activeBorders[iconContainer] = nil
            end
        end

        local existingColor = CDM.GetSpellBorderColor and CDM:GetSpellBorderColor(currentSpecID, spellID)
        if existingColor and iconContainer.border then
            iconContainer.border:SetBackdropBorderColor(existingColor.r, existingColor.g, existingColor.b, 1)
        end

        local spellName = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font18")
        spellName:SetPoint("LEFT", iconContainer, "RIGHT", 8, 0)
        spellName:SetText(C_Spell.GetSpellName(displaySpellID) or L["Unknown"])
        spellName:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
        yOff = yOff - 40

        local borderLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
        borderLabel:SetText(L["Border:"])
        borderLabel:SetPoint("TOPLEFT", 0, yOff)

        local configR, configG, configB = GetConfiguredBorderColor()
        local colorInit = existingColor and
            { r = existingColor.r or configR, g = existingColor.g or configG, b = existingColor.b or configB }
            or { r = configR, g = configG, b = configB }
        local borderColorPicker = UI.CreateSimpleColorPicker(rc, colorInit, function(r, g, b)
            API:SaveSpell(currentSpecID, spellID, { r = r, g = g, b = b, a = 1 })
            API:Refresh("BUFF_DATA")
            if iconContainer.border then
                iconContainer.border:SetBackdropBorderColor(r, g, b, 1)
            end
            local leftBorder = spellIconBorders[spellID]
            if leftBorder then
                leftBorder:SetBackdropBorderColor(r, g, b, 1)
            end
        end)
        borderColorPicker:SetPoint("LEFT", borderLabel, "RIGHT", 6, 0)
        yOff = yOff - 30

        local resetHint = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_GameFontHighlightSmall")
        resetHint:SetPoint("TOPLEFT", 0, yOff)
        resetHint:SetText(L["Right-click icon to reset border color"])
        UI.SetTextFaint(resetHint)
        yOff = yOff - 24

        iconContainer:EnableMouse(true)
        iconContainer:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" then
                API:ClearSpellBorderColor(currentSpecID, spellID)
                API:Refresh("BUFF_DATA")
                ApplyConfiguredBorderColor(iconContainer.border)
                local leftBorder = spellIconBorders[spellID]
                if leftBorder then
                    ApplyConfiguredBorderColor(leftBorder)
                end
                ShowSpellSettings(spellID, groupIndex)
            end
        end)

        local glowEnabled = API:GetSpellGlowEnabled(currentSpecID, spellID)
        local glowCheckbox = UI.CreateModernCheckbox(
            rc,
            L["Enable Glow"],
            glowEnabled,
            function(checked)
                API:SetSpellGlowEnabled(currentSpecID, spellID, checked or nil)
            end
        )
        glowCheckbox:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 36

        local glowColorLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
        glowColorLabel:SetText(L["Glow Color:"])
        glowColorLabel:SetPoint("TOPLEFT", 0, yOff)

        local existingGlowColor = API:GetSpellGlowColor(currentSpecID, spellID) or { r = 1, g = 1, b = 1 }
        local glowColorPicker = UI.CreateSimpleColorPicker(rc, existingGlowColor, function(r, g, b)
            API:SetSpellGlowColor(currentSpecID, spellID, { r = r, g = g, b = b })
        end)
        glowColorPicker:SetPoint("LEFT", glowColorLabel, "RIGHT", 6, 0)
        yOff = yOff - 30

        local isCustom = IsCustomBuffSpell(spellID)

        if isCustom then
            local cbEntry = GetCustomBuffEntry(spellID)
            if not (cbEntry and cbEntry.triggerType) then
                yOff = yOff - 10

                local sidLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
                sidLabel:SetPoint("TOPLEFT", 0, yOff)
                sidLabel:SetText(L["Spell ID:"])

                local sidInput = CreateFrame("EditBox", nil, rc, "InputBoxTemplate")
                sidInput:SetSize(100, 20)
                sidInput:SetPoint("LEFT", sidLabel, "RIGHT", 6, 0)
                sidInput:SetAutoFocus(false)
                sidInput:SetNumeric(true)
                sidInput:SetMaxLetters(10)
                sidInput:SetText(tostring(spellID))
                yOff = yOff - 28

                local durLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
                durLabel:SetPoint("TOPLEFT", 0, yOff)
                durLabel:SetText(L["Duration (sec):"])

                local durInput = CreateFrame("EditBox", nil, rc, "InputBoxTemplate")
                durInput:SetSize(60, 20)
                durInput:SetPoint("LEFT", durLabel, "RIGHT", 6, 0)
                durInput:SetAutoFocus(false)
                durInput:SetNumeric(true)
                durInput:SetMaxLetters(5)
                durInput:SetText(tostring(cbEntry and cbEntry.duration or ""))
                yOff = yOff - 28

                local saveBtn = UI.CreateTextButton(rc)
                saveBtn:SetSize(80, 22)
                saveBtn:SetPoint("TOPLEFT", 0, yOff)
                saveBtn:SetText(L["Save"])

                local cbStatusText = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
                cbStatusText:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
                cbStatusText:SetText("")
                saveBtn:SetScript("OnClick", function()
                    local newSID = tonumber(sidInput:GetText())
                    local newDur = tonumber(durInput:GetText())
                    if not newSID or newSID <= 0 then
                        cbStatusText:SetText("|cffff4444" .. (L["Invalid spell ID"]) .. "|r")
                        return
                    end
                    if not newDur or newDur <= 0 then
                        cbStatusText:SetText("|cffff4444" .. (L["Enter a valid duration"]) .. "|r")
                        return
                    end

                    if newSID ~= spellID then
                        local spellInfo = C_Spell.GetSpellInfo(newSID)
                        if not spellInfo then
                            cbStatusText:SetText("|cffff4444" .. (L["Invalid spell ID"]) .. "|r")
                            return
                        end
                        API:RemoveCustomBuffSpell(spellID)
                        API:AddCustomBuffSpell(newSID, newDur)
                        if groupIndex then
                            local groups = GetSpecGroups()
                            if groups and groups[groupIndex] and groups[groupIndex].spells then
                                for i, sid in ipairs(groups[groupIndex].spells) do
                                    if sid == spellID then
                                        groups[groupIndex].spells[i] = newSID
                                        break
                                    end
                                end
                            end
                        end
                    else
                        if cbEntry then cbEntry.duration = newDur end
                    end

                    CDM:RefreshBuffGroupData()
                    SaveAndRefresh()
                    RefreshLeftPanelIfNeeded()
                    ShowSpellSettings(newSID, groupIndex)
                end)
                yOff = yOff - 30
            end
        end

        if groupIndex then
            local groups = GetSpecGroups()
            local gd = groups and groups[groupIndex]
            if gd then
                yOff = BuildOverrideSection(rc, yOff, spellID, groupIndex,
                    Shared.GetMergedOverrideEntry(gd.spellOverrides, spellID),
                    function() return EnsureSpellOverride(groupIndex, spellID) end,
                    {
                        cooldownFontSize = gd.cooldownFontSize or 12,
                        cooldownColor = gd.cooldownColor,
                        countFontSize = gd.countFontSize or 15,
                        countColor = gd.countColor,
                        countPosition = gd.countPosition or "BOTTOMRIGHT",
                        countOffsetX = gd.countOffsetX or 0,
                        countOffsetY = gd.countOffsetY or 0,
                    },
                    isCustom and nil or { isStatic = gd.staticDisplay or false },
                    isCustom
                )
            end
        end

        if not groupIndex then
            yOff = BuildOverrideSection(rc, yOff, spellID, groupIndex,
                GetUngroupedOverride(spellID),
                function() return EnsureUngroupedOverrideEntry(spellID) end,
                {
                    cooldownFontSize = CDM.db.buffCooldownFontSize or 12,
                    cooldownColor = CDM.db.buffCooldownColor,
                    countFontSize = CDM.db.countFontSize or 15,
                    countColor = CDM.db.countColor,
                    countPosition = CDM.db.countPositionMain or "TOP",
                    countOffsetX = CDM.db.countOffsetXMain or 0,
                    countOffsetY = CDM.db.countOffsetYMain or 0,
                },
                nil,
                isCustom
            )
        end

        rc:SetHeight(math.abs(yOff) + 20)
    end

    local btnRefs = {}
    local ShowSpellPickerPanel
    local ShowCustomBuffAddPanel

    local headerPool, groupContainerPool, emptyRowPool, spellRowPool =
        Shared.CreateGroupEditorPools(leftChild, {
            highlightAlpha = 0.2,
            resetBorder = function(border) ApplyConfiguredBorderColor(border) end,
        })

    local function UpdateAddIconButtonState()
        if btnRefs.icon then
            btnRefs.icon:SetEnabled(selectedGroupIndex ~= nil)
        end
    end

    ShowSpellPickerPanel = function(groupIndex)
        pickerActiveGroupIndex = groupIndex
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
            isCacheMissing = currentSpecID ~= playerSpecID and not API:GetSpecBuffSpellCache(currentSpecID),
            cacheMissingText = string.format(L["Log %s to build spell list"], select(2, GetSpecializationInfoByID(currentSpecID)) or "this spec"),
            emptyText = currentSpecID == playerSpecID
                and (L["No untracked buff icons available for this spec"])
                or (L["All available icons are assigned to groups"]),
            onSelect = function(sid)
                local currentGroups = EnsureBuffGroups()
                if not currentGroups or not currentGroups[groupIndex] then return end
                if not currentGroups[groupIndex].spells then
                    currentGroups[groupIndex].spells = {}
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
                CDM:RefreshBuffGroupData()
                SaveAndRefresh()
                RefreshLeftPanelIfNeeded()
                ShowSpellPickerPanel(groupIndex)
            end,
            onDone = function()
                ShowGroupSettings(groupIndex)
            end,
        })
    end

    GetCustomBuffEntry = function(spellID)
        return CDM.db and CDM.db.customBuffRegistry and CDM.db.customBuffRegistry[spellID]
    end

    IsCustomBuffSpell = function(spellID)
        return GetCustomBuffEntry(spellID) ~= nil
    end

    ShowCustomBuffAddPanel = function(targetGroupIndex)
        pickerActiveGroupIndex = nil
        local _, rc = CreateRightScrollContent(500)
        local yOff = 0

        local headerText
        if targetGroupIndex then
            local groups = GetSpecGroups()
            local gd = groups and groups[targetGroupIndex]
            headerText = (L["Add Custom Buff to:"]) .. " " .. (gd and gd.name or "Group")
        else
            headerText = L["Add Custom Buff"]
        end

        local header = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font18")
        header:SetPoint("TOPLEFT", 0, yOff)
        header:SetText(headerText)
        header:SetTextColor(CDM_C.GOLD.r, CDM_C.GOLD.g, CDM_C.GOLD.b, 1)
        yOff = yOff - 30

        local templates = CDM.CustomBuffTemplates or {}
        if #templates > 0 then
            local quickLabel = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
            quickLabel:SetPoint("TOPLEFT", 0, yOff)
            quickLabel:SetText(L["Quick Add"])
            UI.SetTextWhite(quickLabel)
            yOff = yOff - 22

            for _, tmpl in ipairs(templates) do
                local sid = tmpl.spellID
                local dur = tmpl.duration
                local spellName = C_Spell.GetSpellName(sid)
                local spellTex = C_Spell.GetSpellTexture(sid)
                local alreadyExists = CDM.db.customBuffRegistry and CDM.db.customBuffRegistry[sid]

                local tRow = CreateFrame("Frame", nil, rc)
                tRow:SetSize(300, 30)
                tRow:SetPoint("TOPLEFT", 0, yOff)

                local tIcon = tRow:CreateTexture(nil, "ARTWORK")
                tIcon:SetSize(24, 24)
                tIcon:SetPoint("LEFT")
                tIcon:SetTexture(tmpl.icon or spellTex)
                CDM_C.ApplyIconTexCoord(tIcon, CDM_C.GetEffectiveZoomAmount())

                local tName = tRow:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
                tName:SetPoint("LEFT", tIcon, "RIGHT", 6, 0)
                tName:SetText((spellName or tostring(sid)) .. "  |cff888888" .. dur .. "s|r")

                local tAddBtn = UI.CreateTextButton(tRow)
                tAddBtn:SetSize(50, 20)
                tAddBtn:SetPoint("RIGHT", -4, 0)
                tAddBtn:SetText(L["Add"])
                tAddBtn:SetEnabled(not alreadyExists)
                tAddBtn:SetScript("OnClick", function()
                    local ov = (tmpl.icon or tmpl.triggerType) and { icon = tmpl.icon, triggerType = tmpl.triggerType } or nil
                    if not API:AddCustomBuffSpell(sid, dur, ov) then return end
                    if targetGroupIndex then
                        local currentGroups = EnsureBuffGroups()
                        if currentGroups and currentGroups[targetGroupIndex] then
                            if not currentGroups[targetGroupIndex].spells then
                                currentGroups[targetGroupIndex].spells = {}
                            end
                            Shared.AddSpellToGroupList(currentGroups[targetGroupIndex].spells, sid)
                        end
                    end
                    CDM:RefreshBuffGroupData()
                    SaveAndRefresh()
                    RefreshLeftPanelIfNeeded()
                    ShowCustomBuffAddPanel(targetGroupIndex)
                end)

                yOff = yOff - 32
            end
        end

        yOff = yOff - 10
        local advLabel = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
        advLabel:SetPoint("TOPLEFT", 0, yOff)
        advLabel:SetText(L["Custom Spell"])
        UI.SetTextWhite(advLabel)
        yOff = yOff - 24

        local sidLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
        sidLabel:SetPoint("TOPLEFT", 0, yOff)
        sidLabel:SetText(L["Spell ID:"])

        local sidInput = CreateFrame("EditBox", nil, rc, "InputBoxTemplate")
        sidInput:SetSize(100, 20)
        sidInput:SetPoint("LEFT", sidLabel, "RIGHT", 6, 0)
        sidInput:SetAutoFocus(false)
        sidInput:SetNumeric(true)
        sidInput:SetMaxLetters(10)
        yOff = yOff - 28

        local durLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
        durLabel:SetPoint("TOPLEFT", 0, yOff)
        durLabel:SetText(L["Duration (sec):"])

        local durInput = CreateFrame("EditBox", nil, rc, "InputBoxTemplate")
        durInput:SetSize(60, 20)
        durInput:SetPoint("LEFT", durLabel, "RIGHT", 6, 0)
        durInput:SetAutoFocus(false)
        durInput:SetNumeric(true)
        durInput:SetMaxLetters(5)
        durInput:SetText("10")
        yOff = yOff - 28

        local previewText = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
        previewText:SetPoint("TOPLEFT", sidInput, "TOPRIGHT", 8, -3)
        previewText:SetText("")

        sidInput:SetScript("OnTextChanged", function()
            local val = tonumber(sidInput:GetText())
            if val and val > 0 then
                local info = C_Spell.GetSpellInfo(val)
                if info then
                    previewText:SetText("|cff00ff00" .. info.name .. "|r")
                else
                    previewText:SetText("|cffff4444" .. (L["Invalid spell ID"]) .. "|r")
                end
            else
                previewText:SetText("")
            end
        end)

        local advAddBtn = UI.CreateTextButton(rc)
        advAddBtn:SetSize(100, 22)
        advAddBtn:SetPoint("TOPLEFT", 0, yOff)

        local statusText = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
        statusText:SetPoint("LEFT", advAddBtn, "RIGHT", 8, 0)
        statusText:SetText("")
        advAddBtn:SetText(L["Add Spell"])
        advAddBtn:SetScript("OnClick", function()
            local sid = tonumber(sidInput:GetText())
            local dur = tonumber(durInput:GetText())
            if not sid or sid <= 0 then
                statusText:SetText("|cffff4444" .. (L["Invalid spell ID"]) .. "|r")
                return
            end
            if not dur or dur <= 0 then
                statusText:SetText("|cffff4444" .. (L["Enter a valid duration"]) .. "|r")
                return
            end
            if not API:AddCustomBuffSpell(sid, dur) then
                statusText:SetText("|cffff4444" .. (L["Failed - invalid spell ID"]) .. "|r")
                return
            end
            if targetGroupIndex then
                local currentGroups = EnsureBuffGroups()
                if currentGroups and currentGroups[targetGroupIndex] then
                    if not currentGroups[targetGroupIndex].spells then
                        currentGroups[targetGroupIndex].spells = {}
                    end
                    Shared.AddSpellToGroupList(currentGroups[targetGroupIndex].spells, sid)
                end
            end
            CDM:RefreshBuffGroupData()
            statusText:SetText("|cff00ff00" .. (L["Added!"]) .. "|r")
            sidInput:SetText("")
            SaveAndRefresh()
            RefreshLeftPanelIfNeeded()
            ShowCustomBuffAddPanel(targetGroupIndex)
        end)
        yOff = yOff - 30

        yOff = yOff - 10
        local disclaimer = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
        disclaimer:SetPoint("TOPLEFT", 0, yOff)
        disclaimer:SetPoint("TOPRIGHT", rc, "TOPRIGHT", -8, yOff)
        disclaimer:SetJustifyH("LEFT")
        disclaimer:SetWordWrap(true)
        disclaimer:SetText(L["Custom buffs are triggered from your own spellcasts. You CAN'T track random auras"])
        UI.SetTextMuted(disclaimer)
        yOff = yOff - (disclaimer:GetStringHeight() + 6)

        local backBtn = UI.CreateTextButton(rc)
        backBtn:SetSize(80, 22)
        backBtn:SetPoint("TOPRIGHT", rc, "TOPRIGHT", 0, 0)
        backBtn:SetText(L["Back"])
        backBtn:SetScript("OnClick", function()
            if targetGroupIndex then
                ShowGroupSettings(targetGroupIndex)
            else
                ClearRightPanel()
            end
        end)

        rc:SetHeight(math.abs(yOff) + 20)
    end
    btnRefs.showAddPanel = ShowCustomBuffAddPanel

    do
        local addGroupBtn = UI.CreateTextButton(buttonRow)
        addGroupBtn:SetSize(90, 22)
        addGroupBtn:SetPoint("LEFT", 0, 0)
        addGroupBtn:SetText(L["Add Group"])
        addGroupBtn:SetScript("OnClick", function()
            local specGroups = EnsureBuffGroups()
            if not specGroups then return end

            local newIndex = #specGroups + 1
            local defs = CDM.defaults or {}
            local sizeBuff = defs.sizeBuff or { w = 40, h = 36 }
            specGroups[newIndex] = {
                name = "BUFF" .. newIndex,
                spells = {},
                grow = "CENTER_H",
                spacing = 1,
                iconWidth = sizeBuff.w,
                iconHeight = sizeBuff.h,
                cooldownFontSize = defs.buffCooldownFontSize or 15,
                cooldownColor = { r = 1, g = 1, b = 1 },
                countFontSize = defs.countFontSize or 15,
                countColor = { r = 1, g = 1, b = 1, a = 1 },
                countPosition = "BOTTOMRIGHT",
                countOffsetX = 0,
                countOffsetY = 0,
                anchorTarget = "screen",
                anchorPoint = "CENTER",
                anchorRelativeTo = "CENTER",
                offsetX = 0,
                offsetY = 0,
            }
            expandedGroups[newIndex] = true
            selectedGroupIndex = newIndex
            selectedSpellID = nil
            SaveAndRefresh()
            RefreshLeftPanelIfNeeded()
            ShowGroupSettings(newIndex)
        end)
        btnRefs.group = addGroupBtn

        local addIconBtn = UI.CreateTextButton(buttonRow)
        addIconBtn:SetSize(90, 22)
        addIconBtn:SetPoint("LEFT", addGroupBtn, "RIGHT", 6, 0)
        addIconBtn:SetText(L["Add Icon"])
        addIconBtn:SetScript("OnClick", function()
            if selectedGroupIndex then
                ShowSpellPickerPanel(selectedGroupIndex)
            end
        end)
        btnRefs.icon = addIconBtn

        local addCustomBuffBtn = UI.CreateTextButton(buttonRow)
        addCustomBuffBtn:SetSize(140, 22)
        addCustomBuffBtn:SetPoint("LEFT", addIconBtn, "RIGHT", 6, 0)
        addCustomBuffBtn:SetText(L["Add Custom Buff"])
        addCustomBuffBtn:SetScript("OnClick", function()
            if btnRefs.showAddPanel then btnRefs.showAddPanel(selectedGroupIndex) end
        end)
        btnRefs.customBuff = addCustomBuffBtn
    end

    local function AcquireEmptyRow(parent, text)
        return Shared.AcquireEmptyRow(emptyRowPool, parent, text)
    end

    local function BuildTooltipOverrideMap()
        if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then return nil end
        local map = {}
        for _, cat in ipairs(CDM_C.VIEWER_CATEGORIES_BUFF) do
            local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
            if ids then
                for _, cdID in ipairs(ids) do
                    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                    -- Viewer spell IDs can be secret values; they must not be
                    -- used as table keys.
                    if info and IsSafeNumber(info.overrideTooltipSpellID)
                        and info.overrideTooltipSpellID ~= info.spellID then
                        if IsSafeNumber(info.spellID) then
                            map[info.spellID] = info.overrideTooltipSpellID
                        end
                        if IsSafeNumber(info.overrideSpellID) then
                            map[info.overrideSpellID] = info.overrideTooltipSpellID
                        end
                    end
                end
            end
        end
        return map
    end

    -- Native ungrouped buffs interleaved with custom buffs in their configured
    -- order (afterNative anchors a custom buff behind a native layout index).
    local function BuildMergedUngroupedList()
        local ungrouped = GetUngroupedBuffSpells()
        local customOrder = CDM:GetUngroupedCustomBuffOrder(currentSpecID)
        local mergedList = {}
        for _, nativeEntry in ipairs(ungrouped) do
            local li = nativeEntry.layoutIndex or 0
            mergedList[#mergedList + 1] = { spellID = nativeEntry.spellID, sortKey = li * 10000, isCustom = false, layoutIndex = li }
        end
        local subCounts = {}
        for _, entry in ipairs(customOrder) do
            local aN = entry.afterNative or 0
            subCounts[aN] = (subCounts[aN] or 0) + 1
            mergedList[#mergedList + 1] = {
                spellID = entry.spellID,
                sortKey = aN * 10000 + 5000 + subCounts[aN],
                isCustom = true,
                afterNative = aN,
            }
        end
        table.sort(mergedList, function(a, b) return a.sortKey < b.sortKey end)
        return mergedList
    end

    ApplyUngroupedCustomBuffOrder = function(spellID, insertIndex)
        local mergedList = BuildMergedUngroupedList()
        local sourceIndex
        for i, item in ipairs(mergedList) do
            if item.spellID == spellID and item.isCustom then
                sourceIndex = i
                table.remove(mergedList, i)
                break
            end
        end
        if not sourceIndex then return false end
        if sourceIndex < insertIndex then insertIndex = insertIndex - 1 end
        insertIndex = math.max(1, math.min(insertIndex, #mergedList + 1))
        table.insert(mergedList, insertIndex, { spellID = spellID, isCustom = true })

        local lastNative = 0
        local order = {}
        for _, item in ipairs(mergedList) do
            if item.isCustom then
                order[#order + 1] = { spellID = item.spellID, afterNative = lastNative }
            else
                lastNative = item.layoutIndex or lastNative
            end
        end
        CDM:SetUngroupedCustomBuffOrder(currentSpecID, order)
        return true
    end

    local function MoveUngroupedCustomBuff(mergedList, displayIdx, delta)
        local item = mergedList[displayIdx]
        if not item or not item.isCustom then return end
        local order = CDM:GetUngroupedCustomBuffOrder(currentSpecID)
        local myIdx
        for ci, e in ipairs(order) do
            if e.spellID == item.spellID then myIdx = ci; break end
        end
        if not myIdx then return end

        local neighbor = mergedList[displayIdx + delta]
        if not neighbor then return end

        if neighbor.isCustom and neighbor.afterNative == item.afterNative then
            local otherIdx
            for ci, e in ipairs(order) do
                if e.spellID == neighbor.spellID then otherIdx = ci; break end
            end
            if otherIdx then
                order[myIdx], order[otherIdx] = order[otherIdx], order[myIdx]
            end
        elseif neighbor.isCustom then
            order[myIdx].afterNative = neighbor.afterNative
        elseif delta < 0 then
            local prevLI = neighbor.layoutIndex or 0
            order[myIdx].afterNative = math.max(0, prevLI - 1)
        else
            order[myIdx].afterNative = neighbor.layoutIndex or 0
        end
        CDM:SetUngroupedCustomBuffOrder(currentSpecID, order)
        SaveAndRefresh()
        RefreshLeftPanelIfNeeded()
    end

    local function BuildIconGrid()
        ReleaseAllGridIcons()
        gridEmptyText:Hide()

        local iconGap = CDM.db and CDM.db.spacing or GRID_ICON_GAP
        minGridHeight = MIN_GRID_ROWS * (GRID_ICON_SIZE + iconGap) - iconGap + 8

        UpdateGridVisibility()
        if currentSpecID ~= playerSpecID then return end

        local mergedList = BuildMergedUngroupedList()

        if #mergedList == 0 then
            iconGridFrame:SetHeight(minGridHeight)
            gridEmptyText:SetText(L["No ungrouped buffs"])
            gridEmptyText:Show()
            UI.SetTextFaint(gridEmptyText)
            return
        end

        local tooltipOverrideMap = BuildTooltipOverrideMap()
        local totalRows = math.ceil(#mergedList / GRID_DISPLAY_MAX)

        for i, item in ipairs(mergedList) do
            local spellID = item.spellID
            local frame = AcquireGridIcon()
            frame.cdmSpellID = spellID
            frame.cdmIsCustom = item.isCustom

            if CDM.BORDER and CDM.BORDER.CreateBorder then
                CDM.BORDER:CreateBorder(frame, { forceUpdate = true })
                if CDM.BORDER.activeBorders then CDM.BORDER.activeBorders[frame] = nil end
            end

            local gridRow = math.floor((i - 1) / GRID_DISPLAY_MAX)
            local gridCol = (i - 1) % GRID_DISPLAY_MAX
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", gridCol * (GRID_ICON_SIZE + iconGap), -gridRow * (GRID_ICON_SIZE + iconGap))

            local displayID = (tooltipOverrideMap and tooltipOverrideMap[spellID]) or spellID
            local cbEntry = GetCustomBuffEntry(spellID)
            local tex = (cbEntry and cbEntry.icon) or C_Spell.GetSpellTexture(displayID)
            if tex then frame.icon:SetTexture(tex) end
            frame.icon:SetDesaturated(false)
            frame.icon:SetAlpha(1)

            if frame.border then
                ApplyConfiguredBorderColor(frame.border)
                spellIconBorders[spellID] = frame.border
                if currentSpecID and CDM.GetSpellBorderColor then
                    local color = CDM:GetSpellBorderColor(currentSpecID, spellID)
                    if color then
                        frame.border:SetBackdropBorderColor(color.r, color.g, color.b, 1)
                    end
                end
            end

            local displayIdx = i
            frame.overlay:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if cbEntry then
                    GameTooltip:SetText(C_Spell.GetSpellName(spellID) or L["Unknown"], 1, 1, 1)
                    if cbEntry.duration then
                        GameTooltip:AddLine(cbEntry.duration .. "s", 0.7, 0.7, 0.7)
                    end
                else
                    GameTooltip:SetSpellByID(displayID)
                end
                GameTooltip:Show()
            end)
            frame.overlay:SetScript("OnLeave", function() GameTooltip:Hide() end)
            frame.overlay:SetScript("OnClick", function(_, button)
                if button == "RightButton" then
                    if cbEntry then
                        -- custom buffs keep their reorder/remove actions via context menu
                        MenuUtil.CreateContextMenu(frame.overlay, function(_, rootDescription)
                            rootDescription:CreateButton(L["Move Left"], function()
                                MoveUngroupedCustomBuff(BuildMergedUngroupedList(), displayIdx, -1)
                            end)
                            rootDescription:CreateButton(L["Move Right"], function()
                                MoveUngroupedCustomBuff(BuildMergedUngroupedList(), displayIdx, 1)
                            end)
                            rootDescription:CreateButton(L["Remove"], function()
                                API:RemoveCustomBuffSpell(spellID)
                                CDM:RefreshBuffGroupData()
                                SaveAndRefresh()
                                RefreshLeftPanelIfNeeded()
                            end)
                        end)
                    else
                        if currentSpecID then
                            API:ClearSpellBorderColor(currentSpecID, spellID)
                            API:Refresh("BUFF_DATA")
                        end
                        if frame.border then ApplyConfiguredBorderColor(frame.border) end
                        if selectedSpellID == spellID then
                            ShowSpellSettings(spellID, nil)
                        end
                    end
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

        local gridHeight = totalRows * (GRID_ICON_SIZE + iconGap) - iconGap + 8
        iconGridFrame:SetHeight(math.max(gridHeight, minGridHeight))
    end

    local function ConfigureSpellRow(widget, parent, spellID, sourceGroup, y, isActive, spellIndex, spellCount, tooltipOverrides)
        local row = widget.root
        row:SetParent(parent)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 8, y)

        local displayID = (tooltipOverrides and tooltipOverrides[spellID]) or spellID
        local iconContainer = widget.iconContainer
        local iconTex = widget.iconTex
        local cbEntry = GetCustomBuffEntry(spellID)
        local tex = (cbEntry and cbEntry.icon) or C_Spell.GetSpellTexture(displayID)
        if tex then
            iconTex:SetTexture(tex)
        end
        CDM_C.ApplyIconTexCoord(iconTex, CDM_C.GetEffectiveZoomAmount())

        if iconContainer.border then
            ApplyConfiguredBorderColor(iconContainer.border)
            spellIconBorders[spellID] = iconContainer.border
        end

        if currentSpecID and CDM.GetSpellBorderColor then
            local color = CDM:GetSpellBorderColor(currentSpecID, spellID)
            if color and iconContainer.border then
                iconContainer.border:SetBackdropBorderColor(color.r, color.g, color.b, 1)
            end
        end

        if isActive == false then
            iconTex:SetDesaturated(true)
            iconTex:SetAlpha(0.5)
            if iconContainer.border then
                iconContainer.border:SetAlpha(0.5)
                iconContainer.border:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            end
        else
            iconTex:SetDesaturated(false)
            iconTex:SetAlpha(1)
            if iconContainer.border then
                iconContainer.border:SetAlpha(1)
            end
        end

        local removeBtn = widget.removeBtn
        removeBtn:Hide()
        removeBtn:SetScript("OnClick", nil)
        if sourceGroup then
            removeBtn:Show()
            removeBtn:SetScript("OnClick", function()
                local groups = GetSpecGroups()
                if not groups or not groups[sourceGroup] then return end
                local srcGroup = groups[sourceGroup]
                local spells = srcGroup.spells
                if spells then
                    Shared.RemoveSpellFromGroupList(spells, spellID)
                end
                local srcOvData
                if srcGroup.spellOverrides then
                    srcOvData = ExtractMergedOverrideEntry(srcGroup.spellOverrides, spellID)
                end
                if srcOvData then
                    local specOv = EnsureUngroupedOverrides()
                    if specOv then
                        StoreMergedOverrideEntry(specOv, spellID, srcOvData)
                    end
                end
                if selectedSpellID == spellID then
                    selectedSpellID = nil
                    selectedSpellGroupIndex = nil
                    ClearRightPanel()
                end
                CDM:RefreshBuffGroupData()
                SaveAndRefresh()
                RefreshLeftPanelIfNeeded()
                if pickerActiveGroupIndex then
                    ShowSpellPickerPanel(pickerActiveGroupIndex)
                end
            end)
        end

        local nameText = widget.nameText
        nameText:ClearAllPoints()
        nameText:SetPoint("LEFT", iconContainer, "RIGHT", 6, 0)
        nameText:SetPoint("RIGHT", removeBtn:IsShown() and removeBtn or row, removeBtn:IsShown() and "LEFT" or "RIGHT", removeBtn:IsShown() and -2 or -4, 0)
        local displayName = C_Spell.GetSpellName(displayID) or L["Unknown"]
        local cbEntry = GetCustomBuffEntry(spellID)
        if cbEntry then
            displayName = displayName .. "  |cff888888" .. cbEntry.duration .. "s|r"
        end
        nameText:SetText(displayName)
        if isActive == false then
            UI.SetTextMuted(nameText)
        elseif selectedSpellID == spellID then
            UI.SetTextWhite(nameText)
        else
            UI.SetTextSubtle(nameText)
        end

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
                    SaveAndRefresh()
                    RefreshLeftPanelIfNeeded()
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
                    SaveAndRefresh()
                    RefreshLeftPanelIfNeeded()
                end
            end)
        end

        widget.clickBtn:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                if currentSpecID then
                    API:ClearSpellBorderColor(currentSpecID, spellID)
                    API:Refresh("BUFF_DATA")
                end
                if iconContainer.border then
                    ApplyConfiguredBorderColor(iconContainer.border)
                end
                if selectedSpellID == spellID then
                    ShowSpellSettings(spellID, sourceGroup)
                end
                RefreshLeftPanelIfNeeded()
                return
            end
            selectedSpellID = spellID
            selectedGroupIndex = nil
            selectedSpellGroupIndex = sourceGroup
            ShowSpellSettings(spellID, sourceGroup)
            RefreshLeftPanelIfNeeded()
        end)
        widget.clickBtn:SetScript("OnDragStart", function()
            StartDrag(spellID, sourceGroup, row)
        end)
        widget.clickBtn:SetScript("OnDragStop", function()
            EndDrag()
        end)

        return widget
    end

    local function BuildLeftPanel()
        if renameActiveGroupIndex and renameActiveEditBox then
            local newName = renameActiveEditBox:GetText()
            local groups = GetSpecGroups()
            local gd = groups and groups[renameActiveGroupIndex]
            if gd and newName and newName ~= "" then
                gd.name = newName
            end
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
            canDrop = CanDropOnUngrouped,
        })
        for i = 1, gridIconsActive do
            RegisterDropTarget(gridIcons[i], nil, {
                label = GetUngroupedDropLabel,
                highlightFrame = iconGridFrame,
                insertIndex = i,
                showInsertion = true,
                horizontalInsertion = true,
                canDrop = CanReorderUngrouped,
            })
        end

        local isViewingPlayer = currentSpecID == playerSpecID
        local activeSpellSet = isViewingPlayer and BuildActiveSpellSet() or nil
        local tooltipOverrideMap = isViewingPlayer and BuildTooltipOverrideMap() or nil

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
                                    local specGroups = EnsureBuffGroups()
                                    if not specGroups then return end
                                    local newIdx = DuplicateGroup(groupData, specGroups)
                                    expandedGroups[newIdx] = true
                                    selectedGroupIndex = newIdx
                                    selectedSpellID = nil
                                    if currentSpecID == playerSpecID then
                                        SaveAndRefresh()
                                    end
                                    ShowGroupSettings(newIdx)
                                    RefreshLeftPanelIfNeeded()
                                end,
                                function(specID)
                                    CopyGroupSettingsToSpec(groupData, specID)
                                    if specID == currentSpecID then
                                        RefreshLeftPanelIfNeeded()
                                    end
                                    if specID == playerSpecID then
                                        SaveAndRefresh()
                                    end
                                end
                            )
                        end)
                        return
                    end
                    local now = GetTime()
                    if renameLastClickGroup == groupIndex and (now - renameLastClickTime) < 0.4 then
                        renameLastClickTime = 0
                        renameLastClickGroup = nil
                        renameActiveGroupIndex = groupIndex
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

                h.deleteBtn:SetScript("OnClick", function()
                    local function DoDelete()
                        local specGroups = EnsureBuffGroups()
                        if specGroups then
                            local gd = specGroups[groupIndex]
                            if gd and gd.spells and gd.spellOverrides then
                                local specOv = EnsureUngroupedOverrides()
                                if specOv then
                                    for _, sid in ipairs(gd.spells) do
                                        local ovData = ExtractMergedOverrideEntry(gd.spellOverrides, sid)
                                        if ovData then
                                            StoreMergedOverrideEntry(specOv, sid, ovData)
                                        end
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
                        SaveAndRefresh()
                        RefreshLeftPanelIfNeeded()
                    end

                    local spellCount = groupData.spells and #groupData.spells or 0
                    if spellCount > 0 then
                        local dialog = StaticPopupDialogs["AYIJE_CDM_CONFIRM_DELETE_GROUP"]
                        dialog.text = string.format(
                            L["Delete group with %d spell(s)?"],
                            spellCount
                        )
                        dialog._pendingDelete = DoDelete
                        StaticPopup_Show("AYIJE_CDM_CONFIRM_DELETE_GROUP")
                    else
                        DoDelete()
                    end
                end)

                yOff = yOff - GROUP_HEADER_H

                if isExpanded then
                    local groupContainerWidget = groupContainerPool:Acquire(lc)
                    local groupContainer = groupContainerWidget.root
                    groupContainer:ClearAllPoints()
                    groupContainer:SetPoint("TOPLEFT", SCROLL_LEFT_PAD, yOff)
                    local spellY = 0
                    local spells = groupData.spells
                    local targetLabel = string.format(L["Move to %s"], groupData.name or L["Group"])
                    RegisterDropTarget(groupContainer, groupIndex, {
                        label = targetLabel,
                        insertIndex = spells and (#spells + 1) or 1,
                        showInsertion = not spells or #spells == 0,
                    })
                    if groupData.spells then
                        local spellCount = #groupData.spells
                        for spellIdx, spellID in ipairs(groupData.spells) do
                            local active = not isViewingPlayer or IsSpellInActiveSet(activeSpellSet, spellID) or IsCustomBuffSpell(spellID)
                            local spellWidget = spellRowPool:Acquire(groupContainer)
                            ConfigureSpellRow(
                                spellWidget,
                                groupContainer,
                                spellID,
                                groupIndex,
                                spellY,
                                active,
                                spellIdx,
                                spellCount,
                                tooltipOverrideMap
                            )
                            RegisterDropTarget(spellWidget.root, groupIndex, {
                                label = targetLabel,
                                insertIndex = spellIdx,
                                showInsertion = true,
                                splitInsertion = true,
                                highlightFrame = groupContainer,
                            })
                            spellY = spellY - ROW_HEIGHT
                        end
                    end

                    if not groupData.spells or #groupData.spells == 0 then
                        AcquireEmptyRow(groupContainer, L["Drag spells here"])
                        spellY = -ROW_HEIGHT
                    end

                    groupContainer:SetHeight(math.abs(spellY) + 4)
                    yOff = yOff + spellY
                end
            end
        end

        lc:SetHeight(math.abs(yOff) + 4)
        UpdateAddIconButtonState()
    end

    RefreshAll = function()
        table.wipe(spellIconBorders)
        BuildIconGrid()
        BuildLeftPanel()
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

    local RegisterViewerCallbacks, UnregisterViewerCallbacks = Shared.CreateViewerSettingsCallbacks(QueueLeftPanelRefresh)

    page:SetScript("OnMouseUp", function()
        EndDrag()
    end)

    page:HookScript("OnHide", function()
        rightPanelManager.CloseDropdownMenus()
        CancelDrag()
        UnregisterViewerCallbacks()
    end)

    page:HookScript("OnShow", function()
        local si = GetSpecialization()
        local prevSpecID = currentSpecID
        playerSpecID = si and GetSpecializationInfo(si) or nil
        currentSpecID = playerSpecID
        RefreshSpecDropdownText()
        RegisterViewerCallbacks()
        if currentSpecID ~= prevSpecID then
            selectedGroupIndex = nil
            selectedSpellGroupIndex = nil
            selectedSpellID = nil
            ClearRightPanel()
        end
        RefreshAll()
        if selectedGroupIndex then
            ShowGroupSettings(selectedGroupIndex)
        elseif selectedSpellID then
            ShowSpellSettings(selectedSpellID, selectedSpellGroupIndex)
        end
    end)

    API:RegisterRefreshCallback("buffgroups-spec-refresh", function()
        if not page:IsShown() then return end
        if GetTime() < suppressPanelRefreshUntil then return end
        RefreshCurrentSpecID()
        QueueLeftPanelRefresh(0)
    end, 30, { "BUFF_DATA" })

end

API:RegisterConfigTab("buffgroups", L["Buffs"], CreateBuffGroupsTab, 8)
