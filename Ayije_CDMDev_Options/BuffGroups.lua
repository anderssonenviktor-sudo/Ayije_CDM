local Runtime = _G["Ayije_CDMDev"]
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
local GRID_ICON_SIZE = 32
local GRID_ICON_GAP = 4
local GRID_DISPLAY_MAX = 14
local MIN_GRID_ROWS = 1

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
    local RefreshAll
    local ShowSpellSettings
    local BuildMergedUngroupedList, MoveUngroupedCustomBuff
    local ShowGroupSettings, ShowMainSettings, RefreshViewDropdownText
    local settingsHost, appearance, RemoveGroupSpell
    local GetCustomBuffEntry
    local IsCustomBuffSpell
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
    local CopyGroupSettingsToSpec = _helpers.CopyGroupSettingsToSpec
    local DuplicateGroup = _helpers.DuplicateGroup

    local function OpenReworkMenu(owner, spellID, groupIndex)
        if not ns.OpenSpellCascade or not currentSpecID then return false end
        local specID = currentSpecID
        local groups = GetSpecGroups()
        local group = groups and groupIndex and groups[groupIndex]
        local defaults = group or {
            cooldownFontSize = CDM.db.buffCooldownFontSize,
            cooldownColor = CDM.db.buffCooldownColor,
            countFontSize = CDM.db.countFontSize,
            countColor = CDM.db.countColor,
            countPosition = CDM.db.countPositionMain,
            countOffsetX = CDM.db.countOffsetXMain,
            countOffsetY = CDM.db.countOffsetYMain,
        }
        ns.OpenSpellCascade(owner, {
            spellID = spellID, specID = specID, buff = true, defaults = defaults,
            staticDisplay = group and group.staticDisplay == true,
            customBuff = GetCustomBuffEntry and GetCustomBuffEntry(spellID) ~= nil,
            removeCustom = not groupIndex and function()
                API:RemoveCustomBuffSpell(spellID)
                CDM:RefreshBuffGroupData()
                SaveAndRefresh()
                RefreshAll()
            end or nil,
            reorderCustom = not groupIndex and function(delta)
                local list = BuildMergedUngroupedList()
                for index, item in ipairs(list) do
                    if item.spellID == spellID then MoveUngroupedCustomBuff(list, index, delta); return end
                end
            end or nil,
            editCustom = function()
                selectedSpellID, selectedSpellGroupIndex = spellID, groupIndex
                ShowSpellSettings(spellID, groupIndex)
            end,
            valid = function()
                local currentGroups = GetSpecGroups()
                return currentSpecID == specID and (not groupIndex or (currentGroups and currentGroups[groupIndex] == group))
            end,
            read = function()
                if group then return Shared.GetMergedOverrideEntry(group.spellOverrides, spellID) end
                return GetUngroupedOverride(spellID)
            end,
            ensure = function()
                if groupIndex then return EnsureSpellOverride(groupIndex, spellID) end
                return EnsureUngroupedOverrideEntry(spellID)
            end,
            save = SaveAndRefresh,
            remove = groupIndex and function() RemoveGroupSpell(groupIndex, spellID) end or nil,
        })
        return true
    end

    local function RefreshLeftPanelIfNeeded()
        if RefreshAll then RefreshAll() end
    end

    local function BuildActiveSpellSet()
        if API.BuildActiveSpellSet then
            return API:BuildActiveSpellSet()
        end
        return {}
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
                RefreshLeftPanelIfNeeded()
            end,
        })
        RegisterDropTarget = dragDrop.RegisterDropTarget
        ClearDropTargets = dragDrop.ClearDropTargets
        StartDrag = dragDrop.StartDrag
        EndDrag = dragDrop.EndDrag
        CancelDrag = dragDrop.CancelDrag
    end

    local minGridHeight = MIN_GRID_ROWS * (GRID_ICON_SIZE + GRID_ICON_GAP) - GRID_ICON_GAP + 8

    local iconGridFrame = CreateFrame("Frame", nil, page)
    iconGridFrame:SetPoint("TOPLEFT", LEFT_INSET, -48)
    iconGridFrame:SetPoint("TOPRIGHT", -18, -48)
    iconGridFrame:SetHeight(minGridHeight)
    local stripSurface = UI.CreateSpellStripSurface(iconGridFrame)
    stripSurface:SetPoint("TOPLEFT")
    stripSurface:SetSize(44, 44)

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
        iconGridFrame:Show()
        buttonRow:ClearAllPoints()
        buttonRow:SetPoint("TOPLEFT", iconGridFrame, "BOTTOMLEFT", 0, -6)
        buttonRow:SetPoint("TOPRIGHT", page, "TOPRIGHT", -10, 0)
    end

    local rightPanel = CreateFrame("Frame", nil, page)
    rightPanel:SetPoint("TOPLEFT", buttonRow, "BOTTOMLEFT", 0, -8)
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
        local allSlots = GetViewerSpellListForSpec(specID)
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

    ShowGroupSettings = function(groupIndex)
        selectedGroupIndex = groupIndex
        selectedSpellID, selectedSpellGroupIndex = nil, nil
        if ns.CloseSpellMenu then ns.CloseSpellMenu() end
        if settingsHost then settingsHost:Hide() end
        rightPanel:Show()
        pickerActiveGroupIndex = nil
        local groups = GetSpecGroups()
        if not groups or not groups[groupIndex] then ClearRightPanel(); return end
        local _, rc = CreateRightScrollContent(700)
        local xSlider, ySlider = ns.RenderCooldownGroupAppearance({
            rc = rc, gd = groups[groupIndex], groupIndex = groupIndex, buff = true,
            onRename = function() RefreshViewDropdownText() end,
            onActions = function(owner, name)
                MenuUtil.CreateContextMenu(owner, function(_, root)
                    Shared.BuildGroupContextMenu(root,
                        { rename = L["Rename"], duplicate = L["Duplicate"], copyTo = L["Copy to"] },
                        function() name:SetFocus(); name:HighlightText() end,
                        function()
                            local specGroups = EnsureBuffGroups()
                            if not specGroups then return end
                            local index = DuplicateGroup(groups[groupIndex], specGroups)
                            selectedGroupIndex = index
                            SaveAndRefresh()
                            RefreshAll()
                            ShowGroupSettings(index)
                        end,
                        function(specID)
                            CopyGroupSettingsToSpec(groups[groupIndex], specID)
                            SaveAndRefresh()
                            RefreshAll()
                        end)
                    root:CreateDivider()
                    root:CreateButton(L["Delete Group"], function()
                        local profile = CDM.db
                        local specID = currentSpecID
                        local group = groups[groupIndex]
                        local function Delete()
                            if CDM.db ~= profile or currentSpecID ~= specID or GetSpecGroups() ~= groups or groups[groupIndex] ~= group then return end
                            local destination = EnsureUngroupedOverrides()
                            for _, sid in ipairs(group.spells or {}) do
                                local entry = ExtractMergedOverrideEntry(group.spellOverrides, sid)
                                if entry and destination then StoreMergedOverrideEntry(destination, sid, entry) end
                            end
                            table.remove(groups, groupIndex)
                            selectedGroupIndex, selectedSpellID, selectedSpellGroupIndex = nil, nil, nil
                            SaveAndRefresh()
                            ShowMainSettings()
                            RefreshAll()
                        end
                        if #(group.spells or {}) > 0 then
                            local dialog = StaticPopupDialogs["AYIJE_CDM_CONFIRM_DELETE_GROUP"]
                            dialog.text = string.format(L["Delete group with %d spell(s)?"], #group.spells)
                            dialog._pendingDelete = Delete
                            StaticPopup_Show("AYIJE_CDM_CONFIRM_DELETE_GROUP")
                        else
                            Delete()
                        end
                    end)
                end)
            end,
            registerDropdown = RegisterRightPanelDropdown,
            saveAndRefresh = SaveAndRefresh, createSlider = CreateSlider, L = L,
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
                local ttsShowBox = UI.CreateCustomEditBox(rc)
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
                local ttsHideBox = UI.CreateCustomEditBox(rc)
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
                stackThresholdOverride = true,
                save = save,
                onToggle = refresh,
                createDropdown = function(p) return registerDropdown(CreateFrame("DropdownButton", nil, p, "WowStyle1DropdownTemplate")) end,
            })
        end

        return yOff
    end

    ns.BuildBuffOverrideSection = BuildOverrideSection

    ShowSpellSettings = function(spellID, groupIndex)
        if settingsHost then settingsHost:Hide() end
        rightPanel:Show()
        pickerActiveGroupIndex = nil
        if not spellID or not currentSpecID then
            ClearRightPanel()
            return
        end

        local displaySpellID = spellID

        local _, rc = CreateRightScrollContent(700)
        local back = UI.CreateTextButton(rc)
        back:SetSize(80, 22)
        back:SetPoint("TOPRIGHT")
        back:SetText(L["Back"])
        back:SetScript("OnClick", function()
            if groupIndex then ShowGroupSettings(groupIndex) else ShowMainSettings() end
            RefreshAll()
        end)

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
                ShowSpellSettings(spellID, groupIndex)
            end
        )
        glowCheckbox:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 36

        local stackEnabled, stackThreshold, stackOperator = API:GetSpellStackGlow(currentSpecID, spellID)
        local stackCheckbox = UI.CreateModernCheckbox(rc, L["Glow at Stacks"], stackEnabled, function(checked)
            API:SetSpellStackGlow(currentSpecID, spellID, checked, stackThreshold, stackOperator)
            ShowSpellSettings(spellID, groupIndex)
        end)
        stackCheckbox:SetPoint("TOPLEFT", 0, yOff)
        yOff = yOff - 30

        if stackEnabled then
            local conditionLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
            conditionLabel:SetPoint("TOPLEFT", 0, yOff)
            conditionLabel:SetText(L["Condition:"])
            local operators = {
                { value = "lt", label = L["<"] }, { value = "lte", label = L["<="] },
                { value = "eq", label = L["=="] }, { value = "gte", label = L[">="] },
                { value = "gt", label = L[">"] },
            }
            local operatorDropdown = RegisterRightPanelDropdown(CreateFrame("DropdownButton", nil, rc, "WowStyle1DropdownTemplate"))
            operatorDropdown:SetWidth(75)
            operatorDropdown:SetPoint("LEFT", conditionLabel, "RIGHT", 8, 0)
            for _, option in ipairs(operators) do
                if option.value == stackOperator then operatorDropdown:SetDefaultText(option.label) end
            end
            UI.SetupValueDropdown(operatorDropdown, operators, function() return stackOperator end, function(value, label)
                stackOperator = value
                operatorDropdown:SetDefaultText(label)
                API:SetSpellStackGlow(currentSpecID, spellID, true, stackThreshold, stackOperator)
            end)
            local thresholdInput = UI.CreateCustomEditBox(rc)
            thresholdInput:SetSize(60, 20)
            thresholdInput:SetPoint("LEFT", operatorDropdown, "RIGHT", 12, 0)
            thresholdInput:SetAutoFocus(false)
            thresholdInput:SetNumeric(true)
            thresholdInput:SetMaxLetters(7)
            thresholdInput:SetText(tostring(stackThreshold))
            thresholdInput:SetScript("OnEditFocusLost", function(self)
                local threshold = math.max(1, math.floor(tonumber(self:GetText()) or stackThreshold))
                self:SetText(tostring(threshold))
                if threshold == stackThreshold then return end
                stackThreshold = threshold
                -- Rebuilding the panel after a mode switch can release focus.
                if API:GetSpellStackGlow(currentSpecID, spellID) then
                    API:SetSpellStackGlow(currentSpecID, spellID, true, stackThreshold, stackOperator)
                end
            end)
            thresholdInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            thresholdInput:SetScript("OnEscapePressed", function(self)
                self:SetText(tostring(stackThreshold))
                self:ClearFocus()
            end)
            yOff = yOff - 36
        end

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

                local sidInput = UI.CreateCustomEditBox(rc)
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

                local durInput = UI.CreateCustomEditBox(rc)
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

    local ShowSpellPickerPanel
    local ShowCustomBuffAddPanel

    ShowSpellPickerPanel = function(groupIndex)
        settingsHost:Hide()
        rightPanel:Show()
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
        settingsHost:Hide()
        rightPanel:Show()
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

        local sidInput = UI.CreateCustomEditBox(rc)
        sidInput:SetSize(100, 20)
        sidInput:SetPoint("LEFT", sidLabel, "RIGHT", 6, 0)
        sidInput:SetAutoFocus(false)
        sidInput:SetNumeric(true)
        sidInput:SetMaxLetters(10)
        yOff = yOff - 28

        local durLabel = rc:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
        durLabel:SetPoint("TOPLEFT", 0, yOff)
        durLabel:SetText(L["Duration (sec):"])

        local durInput = UI.CreateCustomEditBox(rc)
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
                ShowMainSettings()
            end
        end)

        rc:SetHeight(math.abs(yOff) + 20)
    end

    local function CreateGroup()
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
        selectedGroupIndex = newIndex
        selectedSpellID = nil
        SaveAndRefresh()
        RefreshLeftPanelIfNeeded()
        ShowGroupSettings(newIndex)
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
    BuildMergedUngroupedList = function()
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

    MoveUngroupedCustomBuff = function(mergedList, displayIdx, delta)
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

    RemoveGroupSpell = function(groupIndex, spellID)
        local groups = GetSpecGroups()
        local group = groups and groups[groupIndex]
        if not group then return end
        Shared.RemoveSpellFromGroupList(group.spells, spellID)
        local entry = ExtractMergedOverrideEntry(group.spellOverrides, spellID)
        local destination = EnsureUngroupedOverrides()
        if entry and destination then StoreMergedOverrideEntry(destination, spellID, entry) end
        SaveAndRefresh()
        RefreshAll()
        ShowGroupSettings(groupIndex)
    end

    local addButton = CreateFrame("Button", nil, iconGridFrame)
    addButton:SetSize(24, 24)
    UI.StyleSpellStripAddButton(addButton)
    addButton:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
            if selectedGroupIndex then
                root:CreateButton(L["Add Icon"], function() ShowSpellPickerPanel(selectedGroupIndex) end)
            end
            root:CreateButton(L["Add Custom Buff"], function() ShowCustomBuffAddPanel(selectedGroupIndex) end)
        end)
    end)

    local function BuildIconGrid()
        ReleaseAllGridIcons()
        ClearDropTargets()
        gridEmptyText:Hide()
        UpdateGridVisibility()
        local groupIndex = selectedGroupIndex
        local groups = GetSpecGroups()
        local group = groups and groupIndex and groups[groupIndex]
        local mergedList = {}
        if group then
            local viewingPlayer = currentSpecID == playerSpecID
            local availableSpells = viewingPlayer and BuildActiveSpellSet() or nil
            for index, sid in ipairs(group.spells or {}) do
                local custom = IsCustomBuffSpell(sid)
                -- The viewer pool includes available buffs even while their auras are inactive.
                if not viewingPlayer or custom or Shared.HasEquivalentSpellID(availableSpells, sid) then
                    mergedList[#mergedList + 1] = { spellID = sid, isCustom = custom, groupIndex = index }
                end
            end
        elseif currentSpecID == playerSpecID then
            mergedList = BuildMergedUngroupedList()
        end
        local iconGap, inset = 3, 6
        local columns = math.max(1, math.floor((iconGridFrame:GetWidth() - 48 + iconGap) / (GRID_ICON_SIZE + iconGap)))
        if iconGridFrame:GetWidth() <= 0 then columns = GRID_DISPLAY_MAX end
        local tooltipOverrideMap = BuildTooltipOverrideMap()
        for i, item in ipairs(mergedList) do
            local spellID = item.spellID
            local frame = AcquireGridIcon()
            frame.cdmSpellID, frame.cdmIsCustom = spellID, item.isCustom
            if not frame.border then
                frame.border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
                frame.border:SetAllPoints()
                frame.border:SetFrameLevel(frame:GetFrameLevel() + 1)
                frame.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            end
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", inset + ((i - 1) % columns) * (GRID_ICON_SIZE + iconGap), -inset - math.floor((i - 1) / columns) * (GRID_ICON_SIZE + iconGap))
            local displayID = (tooltipOverrideMap and tooltipOverrideMap[spellID]) or spellID
            local cbEntry = GetCustomBuffEntry(spellID)
            frame.icon:SetTexture((cbEntry and cbEntry.icon) or C_Spell.GetSpellTexture(displayID))
            frame.icon:SetDesaturated(false)
            frame.icon:SetAlpha(1)
            frame.border:SetBackdropBorderColor(0.08, 0.08, 0.08, 1)
            frame.overlay:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(displayID)
                GameTooltip:Show()
            end)
            frame.overlay:SetScript("OnLeave", function() GameTooltip:Hide() end)
            frame.overlay:SetScript("OnClick", function(self, button)
                if button ~= "RightButton" then return end
                if OpenReworkMenu(self, spellID, groupIndex) then return end
                if cbEntry then
                    MenuUtil.CreateContextMenu(self, function(_, root)
                        root:CreateButton(L["Settings"], function()
                            selectedSpellID, selectedSpellGroupIndex = spellID, groupIndex
                            ShowSpellSettings(spellID, groupIndex)
                        end)
                        if groupIndex then
                            root:CreateButton(L["Remove from group"], function() RemoveGroupSpell(groupIndex, spellID) end)
                        else
                            root:CreateButton(L["Move Left"], function() MoveUngroupedCustomBuff(BuildMergedUngroupedList(), i, -1) end)
                            root:CreateButton(L["Move Right"], function() MoveUngroupedCustomBuff(BuildMergedUngroupedList(), i, 1) end)
                            root:CreateButton(L["Remove"], function()
                                API:RemoveCustomBuffSpell(spellID)
                                CDM:RefreshBuffGroupData()
                                SaveAndRefresh()
                                RefreshAll()
                            end)
                        end
                    end)
                end
            end)
            frame.overlay:SetScript("OnDragStart", function() StartDrag(spellID, groupIndex, frame) end)
            frame.overlay:SetScript("OnDragStop", function() EndDrag() end)
            RegisterDropTarget(frame, groupIndex, {
                label = L["Reorder icons"], insertIndex = item.groupIndex or i,
                canDrop = function(sid, source) return groupIndex ~= nil or CanDropOnUngrouped(sid, source) end,
                showInsertion = true, splitInsertion = true,
            })
        end
        addButton:ClearAllPoints()
        local count = math.min(#mergedList, columns)
        local contentWidth = count > 0 and count * (GRID_ICON_SIZE + iconGap) - iconGap or 0
        local rows = math.max(1, math.ceil(#mergedList / columns))
        local height = rows * (GRID_ICON_SIZE + iconGap) - iconGap + inset * 2
        addButton:SetPoint("TOPLEFT", contentWidth + inset * 3, -inset - 4)
        iconGridFrame:SetHeight(height)
        stripSurface:SetSize(contentWidth + inset * 4 + 24, height)
        RegisterDropTarget(iconGridFrame, groupIndex, {
            label = L["Reorder icons"], insertIndex = group and (#(group.spells or {}) + 1) or (#mergedList + 1),
            canDrop = function(sid, source) return groupIndex ~= nil or CanDropOnUngrouped(sid, source) end,
        })
    end

    settingsHost = CreateFrame("Frame", nil, page)
    settingsHost:SetPoint("TOPLEFT", buttonRow, "BOTTOMLEFT", 0, -8)
    settingsHost:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -10, 20)
    appearance = ns.CreateCooldownAppearance(settingsHost, true)

    local hint = buttonRow:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font12")
    hint:SetPoint("LEFT")
    hint:SetText(L["Right-click a spell for individual settings"])
    UI.SetTextMuted(hint)

    local viewDropdown = UI.CreateCompactDropdown(page, { viewSelector = true, smallText = true })
    viewDropdown:SetSize(200, 26)
    viewDropdown:SetPoint("TOPLEFT", LEFT_INSET, -8)
    RefreshViewDropdownText = function()
        local groups = GetSpecGroups()
        local group = groups and selectedGroupIndex and groups[selectedGroupIndex]
        viewDropdown:OverrideText(group and (group.name or (L["Group"] .. " " .. selectedGroupIndex)) or (currentSpecID == playerSpecID and L["Buffs"] or L["Groups"]))
    end
    ShowMainSettings = function()
        if ns.CloseSpellMenu then ns.CloseSpellMenu() end
        selectedGroupIndex, selectedSpellID, selectedSpellGroupIndex = nil, nil, nil
        ClearRightPanel()
        rightPanel:Hide()
        settingsHost:SetShown(currentSpecID == playerSpecID)
        appearance.Refresh()
        RefreshViewDropdownText()
    end
    viewDropdown:SetupMenu(function(_, root)
        if currentSpecID == playerSpecID then
            root:CreateRadio(L["Buffs"], function() return not selectedGroupIndex end, function()
                ShowMainSettings()
                RefreshAll()
            end)
            root:CreateDivider()
        end
        for index, group in ipairs(GetSpecGroups() or {}) do
            root:CreateRadio(group.name or (L["Group"] .. " " .. index),
                function() return selectedGroupIndex == index end,
                function()
                    ShowGroupSettings(index)
                    RefreshAll()
                end)
        end
        if #(GetSpecGroups() or {}) > 0 then root:CreateDivider() end
        root:CreateButton("+ " .. L["New Group"], CreateGroup)
    end)
    RefreshAll = function()
        table.wipe(spellIconBorders)
        BuildIconGrid()
        RefreshViewDropdownText()
        if settingsHost:IsShown() then appearance.Refresh() end
    end
    ShowMainSettings()
    local lastWidth = 0
    iconGridFrame:HookScript("OnSizeChanged", function(_, width)
        if math.abs(width - lastWidth) < 1 then return end
        lastWidth = width
        if page:IsShown() then QueueLeftPanelRefresh() end
    end)

    local specDropdown, RefreshSpecDropdownText = Shared.CreateSpecDropdown(page, "TOPRIGHT", -6, -8, {
        createDropdown = UI.CreateCompactDropdown,
        getPlayerSpecID = function() return playerSpecID end,
        getCurrentSpecID = function() return currentSpecID end,
        onSelectionChange = function(specID)
            currentSpecID = specID
            selectedGroupIndex = nil
            selectedSpellID = nil
            selectedSpellGroupIndex = nil
            ShowMainSettings()
            local groups = GetSpecGroups()
            if currentSpecID ~= playerSpecID and groups and groups[1] then ShowGroupSettings(1) end
            RefreshAll()
        end,
    })

    local RegisterViewerCallbacks, UnregisterViewerCallbacks = Shared.CreateViewerSettingsCallbacks(QueueLeftPanelRefresh)

    page:SetScript("OnMouseUp", function()
        EndDrag()
    end)

    page:HookScript("OnHide", function()
        if ns.CloseSpellMenu then ns.CloseSpellMenu() end
        UI.CloseAllDropdownMenus()
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
        else
            ShowMainSettings()
        end
    end)

    API:RegisterRefreshCallback("buffgroups-spec-refresh", function()
        if not page:IsShown() then return end
        if GetTime() < suppressPanelRefreshUntil then return end
        local previousSpec = currentSpecID
        RefreshCurrentSpecID()
        if currentSpecID ~= previousSpec then ShowMainSettings() end
        RefreshSpecDropdownText()
        QueueLeftPanelRefresh(0)
    end, 30, { "BUFF_DATA" })

end

API:RegisterConfigTab("buffgroups", L["Buffs"], CreateBuffGroupsTab, 8)
