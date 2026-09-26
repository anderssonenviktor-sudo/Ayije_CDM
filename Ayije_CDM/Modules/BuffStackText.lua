local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
local CDM_C = CDM.CONST
local GetFrameData = CDM.GetFrameData
local Pixel = CDM.Pixel
local InCombatLockdown = InCombatLockdown
local GetCooldownViewerCooldownInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo
local issecretvalue = issecretvalue
local After = C_Timer.After
local floor, min, max = math.floor, math.min, math.max
local records = {}
local EMPTY = {}
local Sync, Queue, Retry

local function Safe(value)
    return not issecretvalue or not issecretvalue(value)
end

local function UsableID(value)
    return Safe(value) and type(value) == "number" and value > 0
end

local function Byte(value)
    value = tonumber(value) or 0
    if value ~= value then value = 0 end
    return floor(min(1, max(0, value)) * 255 + 0.5)
end

local function BuildBreakpoints(ov)
    local showSingle = ov.textOverride and ov.stackTextShowSingle == true
    local threshold = ov.stackTextThresholdEnabled and (tonumber(ov.stackTextThreshold) or 2) or math.huge
    if threshold ~= threshold then threshold = math.huge end
    if threshold ~= math.huge then threshold = max(1, floor(threshold)) end
    local color = ov.stackTextThresholdColor or { r = 1, g = 0, b = 0 }
    local colored = ov.stackTextThresholdEnabled
        and string.format("|cFF%02X%02X%02X%%d|r", Byte(color.r), Byte(color.g), Byte(color.b))
        or "%d"
    local edges = { 0, 1, 2 }
    if threshold ~= math.huge and threshold > 2 then edges[#edges + 1] = threshold end
    local points = {}
    for _, edge in ipairs(edges) do
        local format = edge >= threshold and colored or "%d"
        if edge == 0 or (edge == 1 and not showSingle) then format = "" end
        points[#points + 1] = { threshold = edge, format = format }
    end
    return points, threshold .. ":" .. colored .. ":" .. tostring(showSingle == true)
end

local function Native(record, alpha)
    local text = record.frame.Applications and record.frame.Applications.Applications
    if text then text:SetAlpha(alpha) end
end

local function Deactivate(record)
    record.active = false
    -- Cleanup must not prevent recovery if a frame is temporarily inaccessible.
    local hidden = true
    if record.host then hidden = pcall(record.host.SetAlpha, record.host, 0) end
    local restored = pcall(Native, record, 1)
    if not hidden then Retry(record) end
    if not restored then Retry(record) end
end

local function Park(record)
    Deactivate(record)
    record.cooldownID = nil
    record.candidateKey = nil
    for _, source in ipairs(record.sources) do
        source.generation = (source.generation or 0) + 1
        source.button, source.text, source.bound = nil, nil, nil
        source.candidateKey = nil
        source.rebuild = true
        source.refresh = true
    end
end

Retry = function(record)
    if record.retryQueued then return end
    record.retryQueued = true
    After(0.5, function()
        record.retryQueued = false
        Queue(record)
    end)
end

local function Accessible(button)
    if button.CanBeAccessedInContext then return button:CanBeAccessedInContext() end
    return not button:IsForbidden()
end

local function GetStyle(ov, frameData)
    ov = ov.textOverride and ov or EMPTY
    local db = CDM.db
    if not db then return end
    local sets = CDM.BuffGroupSets
    local sid = frameData.buffCategorySpellID
    local groupIndex = UsableID(sid) and sets and sets.grouped and sets.grouped[sid]
    local group = groupIndex and sets.groups and sets.groups[groupIndex]
    local base = group or db
    local point = ov.countPosition or (group and (group.countPosition or "BOTTOMRIGHT"))
        or db.countPositionMain or "TOP"
    local x = ov.countOffsetX or (group and (group.countOffsetX or 0)) or db.countOffsetXMain or 0
    local y = ov.countOffsetY or (group and (group.countOffsetY or 0)) or db.countOffsetYMain or 0
    local color = ov.countColor or base.countColor or { r = 1, g = 1, b = 1, a = 1 }
    -- Native anchors/colors can stay secret after combat. Only public configuration
    -- belongs in the signature; frame-level changes are not text-style changes.
    local style = { CDM_C.GetBaseFontPath(), Pixel.FontSize(ov.countFontSize or base.countFontSize or 15),
        CDM_C.GetBaseFontOutline(), color.r, color.g, color.b, color.a or 1,
        0, 0, 0, 1, 0, 0, point, point, Pixel.Snap(x), Pixel.Snap(y) }
    return style, table.concat(style, ":")
end

local function StyleButton(record, source)
    local button, text = source.button, source.text
    assert(not InCombatLockdown() and Accessible(button))
    local s = record.style
    button:SetAllPoints(record.frame)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(record.frame:GetFrameLevel() + 7)
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
    text:SetIgnoreParentScale(true)
    assert(text:SetFont(s[1], s[2], s[3]))
    text:SetTextColor(s[4], s[5], s[6], s[7])
    text:SetShadowColor(s[8], s[9], s[10], s[11])
    text:SetShadowOffset(s[12], s[13])
    text:ClearAllPoints()
    text:SetPoint(s[14], button, s[15], s[16], s[17])
end

local function CreateSource(record, source)
    assert(not InCombatLockdown())
    source.generation = (source.generation or 0) + 1
    local generation = source.generation
    source.button, source.text, source.bound = nil, nil, nil
    source.ready = nil
    source.rebuild = true
    if source.container then
        -- Retain a partially retired container until all cleanup succeeds.
        source.container:Hide()
        if source.container.SetEnabled then source.container:SetEnabled(false) end
        -- SetUnit requires a string. Hidden, disabled containers unregister their unit events.
        source.container = nil
    end
    local container = CreateFrame("AuraContainer", nil, record.host, "CustomAuraContainerTemplate")
    source.container = container
    assert(container.AddAuraSlot and container.SetAuraSlotCandidateFilters)
    container:SetSize(1, 1)
    container:SetPoint("TOPLEFT", record.frame, "TOPLEFT")
    container:AddAuraSlot("stacks", source.filter, {
        candidateFilters = { includeSpellIDs = EMPTY },
        initializeFrame = function(button)
            if source.generation ~= generation then return end
            Deactivate(record)
            source.bound = nil
            local ok = pcall(function()
                assert(not InCombatLockdown() and Accessible(button) and button.SetApplicationCount)
                if source.text then source.text:Hide() end
                source.button = button
                source.text = button:CreateFontString(nil, "OVERLAY")
                StyleButton(record, source)
                button:SetApplicationCount(source.text, { formatter = record.formatter })
                source.bound = true
                source.rebuild = false
                source.styleKey = record.styleKey
                source.refresh = true
            end)
            if not ok then
                source.button, source.text, source.bound = nil, nil, nil
                source.rebuild = true
                Retry(record)
            elseif not record.syncing then
                Queue(record)
            end
        end,
    })
    container:SetUnit(source.unit)
    if container.SetEnabled then container:SetEnabled(true) end
    container:Show()
    source.ready = true
    source.refresh = true
    source.candidateKey = nil
end

local function ResolveCandidates(id)
    -- Query by cooldown ID: frame.cooldownInfo can still describe its previous occupant.
    local info = GetCooldownViewerCooldownInfo(id)
    if not Safe(info) or type(info) ~= "table" then return end
    local ids, sorted = {}, {}
    local function Add(sid)
        if UsableID(sid) and not ids[sid] then
            ids[sid] = true
            sorted[#sorted + 1] = sid
        end
    end
    Add(info.spellID)
    Add(info.overrideSpellID)
    Add(info.overrideTooltipSpellID)
    local linked = info.linkedSpellIDs
    if Safe(linked) and type(linked) == "table" then
        for _, sid in ipairs(linked) do Add(sid) end
    end
    if #sorted == 0 then return end
    table.sort(sorted)
    return ids, id .. ":" .. table.concat(sorted, ",")
end

local function EnsureInfrastructure(record)
    if not record.hostReady then
        if InCombatLockdown() then Retry(record); return false end
        if not record.host then record.host = CreateFrame("Frame", nil, record.frame) end
        record.host:SetAlpha(0)
        record.host:SetAllPoints(record.frame)
        record.host:EnableMouse(false)
        record.hostReady = true
    end
    for _, source in ipairs(record.sources) do
        if not source.ready or source.rebuild or source.styleKey ~= record.styleKey then
            Deactivate(record)
            if InCombatLockdown() then
                Retry(record)
                return false
            end
            CreateSource(record, source)
            if not source.bound then Retry(record); return false end
        end
    end
    return true
end

local function CheckBinding(source)
    if not source.bound or not source.button or not source.text then return false end
    -- This getter returns the registered FontString, never an application-count value.
    local ok, text = pcall(function() return source.button:GetApplicationCount() end)
    -- An inaccessible getter does not prove that a successfully registered binding was lost.
    if not ok then return nil end
    if not Safe(text) then return nil end
    return text == source.text
end

Sync = function(record)
    local frame = record.frame
    local frameData = GetFrameData(frame)
    if frameData.cdmViewerName ~= CDM_C.VIEWERS.BUFF and not frameData.cdmCooldownBuffSpellID then
        Park(record)
        return
    end
    local id = frame.cooldownID
    if not UsableID(id) then
        Park(record)
        -- Released pool frames have no ID. OnCooldownIDSet queues them when reused.
        if not Safe(id) then Retry(record) end
        return
    end
    if record.cooldownID ~= id then Park(record) end
    local ov = CDM.ResolveBuffSpellOverrideForFrame(frame, frameData)
    if not (ov and (ov.stackTextThresholdEnabled or (ov.textOverride and ov.stackTextShowSingle))) then
        Park(record)
        return
    end
    record.cooldownID = id
    record.style, record.styleKey = GetStyle(ov, frameData)
    if not record.style then Deactivate(record); Retry(record); return end
    local points, signature = BuildBreakpoints(ov)
    if not record.formatter then
        if InCombatLockdown() then Deactivate(record); Retry(record); return end
        if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then Retry(record); return end
        record.formatter = C_StringUtil.CreateNumericRuleFormatter()
        assert(record.formatter)
    end
    if record.signature ~= signature then
        record.formatter:SetBreakpoints(points)
        record.signature = signature
        for _, source in ipairs(record.sources) do source.refresh = true end
    end
    local ids, candidateKey = ResolveCandidates(id)
    if not ids then Deactivate(record); Retry(record); return end
    if record.candidateKey and record.candidateKey ~= candidateKey then Park(record) end
    record.cooldownID, record.candidateKey = id, candidateKey
    for _, source in ipairs(record.sources) do
        local bound = CheckBinding(source)
        if bound == nil then
            Deactivate(record)
            Retry(record)
            return
        elseif source.bound and not bound then
            source.button, source.text, source.bound = nil, nil, nil
            source.rebuild = true
            Deactivate(record)
        end
    end
    if not EnsureInfrastructure(record) then return end
    for _, source in ipairs(record.sources) do
        if source.candidateKey ~= candidateKey then
            source.container:SetAuraSlotCandidateFilters("stacks", { includeSpellIDs = ids })
            source.candidateKey = candidateKey
            source.refresh = true
        end
        if source.refresh then
            source.container:UpdateAllAuras()
            source.refresh = false
        end
    end
    for _, source in ipairs(record.sources) do
        local bound = CheckBinding(source)
        if bound == nil then
            Deactivate(record)
            Retry(record)
            return
        elseif source.rebuild or not bound then
            source.button, source.text, source.bound = nil, nil, nil
            source.rebuild = true
            Deactivate(record)
            Retry(record)
            return
        end
    end
    record.host:SetAlpha(1)
    Native(record, 0)
    record.active = true
end

Queue = function(record)
    if record.queued then return end
    record.queued = true
    After(0, function()
        record.queued = false
        record.syncing = true
        local ok = pcall(Sync, record)
        record.syncing = false
        if not ok then
            Deactivate(record)
            for _, source in ipairs(record.sources) do source.refresh = true end
            Retry(record)
        end
    end)
end

hooksecurefunc(CDM, "ApplyStyle", function(_, frame, viewerName)
    if not frame or frame.isCustomBuff then return end
    local record = GetFrameData(frame).stackTextOverlay
    if viewerName ~= CDM_C.VIEWERS.BUFF and not GetFrameData(frame).cdmCooldownBuffSpellID then
        if record then Park(record) end
        return
    end
    if not record then
        record = { frame = frame, sources = {
            { unit = "player", filter = "HELPFUL" },
            { unit = "target", filter = "HARMFUL|PLAYER" },
        } }
        GetFrameData(frame).stackTextOverlay = record
        records[frame] = record
        if frame.OnCooldownIDSet then
            hooksecurefunc(frame, "OnCooldownIDSet", function()
                local id = frame.cooldownID
                if not UsableID(id) or record.cooldownID ~= id then Park(record) end
                Queue(record)
            end)
        end
    end
    Queue(record)
end)

hooksecurefunc(CDM, "ApplyUngroupedBuffOverrides", function(_, frame)
    local record = frame and GetFrameData(frame).stackTextOverlay
    if record then Queue(record) end
end)

hooksecurefunc(CDM, "ApplyGroupStyleOverrides", function()
    for _, record in pairs(records) do Queue(record) end
end)

CDM:RegisterEvent("PLAYER_TARGET_CHANGED", function()
    for _, record in pairs(records) do
        record.sources[2].refresh = true
        Deactivate(record)
        Queue(record)
    end
end)

CDM:RegisterEvent("UNIT_AURA", function(_, unit)
    if unit ~= "player" and unit ~= "target" then return end
    for _, record in pairs(records) do Queue(record) end
end)

CDM:RegisterCombatStateHandler(function(inCombat)
    if inCombat then return end
    for _, record in pairs(records) do Queue(record) end
end)
