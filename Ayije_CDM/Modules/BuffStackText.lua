local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
local CDM_C = CDM.CONST
local GetFrameData = CDM.GetFrameData
local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue
local After = C_Timer.After
local floor, min, max = math.floor, math.min, math.max
local records = {}
local candidatesByID = {}
local EMPTY = {}
local Sync, Queue

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
    local threshold = tonumber(ov.stackTextThreshold) or 2
    if threshold ~= threshold or threshold == math.huge then threshold = 2 end
    threshold = max(1, floor(threshold))
    local color = ov.stackTextThresholdColor or { r = 1, g = 0, b = 0 }
    local colored = string.format("|cFF%02X%02X%02X%%d|r", Byte(color.r), Byte(color.g), Byte(color.b))
    local edges = { 0, 1, 2 }
    if threshold > 2 then edges[#edges + 1] = threshold end
    local points = {}
    for _, edge in ipairs(edges) do
        local format = edge >= threshold and colored or "%d"
        if edge <= 1 then format = "" end
        points[#points + 1] = { threshold = edge, format = format }
    end
    return points, threshold .. ":" .. colored
end

local function Native(record, alpha)
    local text = record.frame.Applications and record.frame.Applications.Applications
    if text then text:SetAlpha(alpha) end
end

local function Park(record)
    record.active = false
    record.cooldownID = nil
    record.include = nil
    if record.host then record.host:SetAlpha(0) end
    Native(record, 1)
    for _, source in ipairs(record.sources) do
        if source.container.SetAuraSlotCandidateFilters then
            pcall(source.container.SetAuraSlotCandidateFilters, source.container, "stacks", { includeSpellIDs = EMPTY })
        end
    end
end

local function Fail(record)
    record.failed = true
    Park(record)
end

local function Accessible(button)
    if button.CanBeAccessedInContext then return button:CanBeAccessedInContext() end
    return not button:IsForbidden()
end

local function StyleButton(record, source, initializing)
    local button, text = source.button, source.text
    if not button or not Accessible(button) or (InCombatLockdown() and not initializing) then
        record.stylePending = true
        return
    end
    local native = record.frame.Applications and record.frame.Applications.Applications
    if not native then return end
    local font, size, flags = native:GetFont()
    if not font then return end
    text:SetIgnoreParentScale(true)
    text:SetFont(font, size, flags)
    text:SetTextColor(native:GetTextColor())
    text:SetShadowColor(native:GetShadowColor())
    text:SetShadowOffset(native:GetShadowOffset())
    text:ClearAllPoints()
    local point, _, relativePoint, x, y = native:GetPoint(1)
    text:SetPoint(point or "BOTTOMRIGHT", button, relativePoint or point or "BOTTOMRIGHT", x or 0, y or 0)
    return true
end

local function CreateSource(record, unit, filter)
    local container = CreateFrame("AuraContainer", nil, record.host, "CustomAuraContainerTemplate")
    local source = { container = container }
    record.sources[#record.sources + 1] = source
    assert(container.AddAuraSlot and container.SetAuraSlotCandidateFilters)
    container:SetSize(1, 1)
    container:SetPoint("TOPLEFT", record.frame, "TOPLEFT")
    container:AddAuraSlot("stacks", filter, {
        candidateFilters = { includeSpellIDs = EMPTY },
        initializeFrame = function(button)
            local ok = pcall(function()
                assert(button.SetApplicationCount and Accessible(button))
                button:SetAllPoints(record.frame)
                button:SetFrameStrata("MEDIUM")
                button:SetFrameLevel(record.frame:GetFrameLevel() + 7)
                if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
                if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
                source.button = button
                source.text = button:CreateFontString(nil, "OVERLAY")
                assert(StyleButton(record, source, true))
                button:SetApplicationCount(source.text, { formatter = record.formatter })
                source.bound = true
            end)
            if not ok then Fail(record) else Queue(record) end
        end,
    })
    container:SetUnit(unit)
    if container.SetEnabled then container:SetEnabled(true) end
    container:Show()
    if container.UpdateAllAuras then container:UpdateAllAuras() end
end

local function ResolveCandidates(frame, id)
    if not InCombatLockdown() then
        local info = frame.cooldownInfo
        if not info and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
        end
        if Safe(info) and type(info) == "table" then
            local ids = {}
            local function Add(sid)
                if UsableID(sid) then ids[sid] = true end
            end
            Add(info.spellID)
            Add(info.overrideSpellID)
            Add(info.overrideTooltipSpellID)
            local linked = info.linkedSpellIDs
            if Safe(linked) and type(linked) == "table" then
                for _, sid in ipairs(linked) do Add(sid) end
            end
            if next(ids) then
                local cached = candidatesByID[id]
                local same = cached ~= nil
                if cached then
                    for sid in pairs(ids) do if not cached[sid] then same = false; break end end
                    for sid in pairs(cached) do if not ids[sid] then same = false; break end end
                end
                if not same then candidatesByID[id] = ids end
            end
        end
    end
    return candidatesByID[id]
end

Sync = function(record)
    if record.failed then return end
    local frame = record.frame
    local frameData = GetFrameData(frame)
    if frameData.cdmViewerName ~= CDM_C.VIEWERS.BUFF and not frameData.cdmCooldownBuffSpellID then
        Park(record)
        return
    end
    local id = frame.cooldownID
    if not UsableID(id) then Park(record); return end
    local ids = ResolveCandidates(frame, id)
    local ov = CDM.ResolveBuffSpellOverrideForFrame(frame, frameData)
    if not (ov and ov.textOverride and ov.stackTextThresholdEnabled and not ov.hideVisuals and ids) then
        if record.formatter then Park(record) end
        return
    end
    local points, signature = BuildBreakpoints(ov)
    if not record.formatter then
        if InCombatLockdown() then record.stylePending = true; return end
        if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return end
        record.formatter = C_StringUtil.CreateNumericRuleFormatter()
        assert(record.formatter)
        record.formatter:SetBreakpoints(points)
        record.signature = signature
        record.host = CreateFrame("Frame", nil, frame)
        record.host:SetAllPoints(frame)
        record.host:EnableMouse(false)
        record.host:SetAlpha(0)
        CreateSource(record, "player", "HELPFUL")
        CreateSource(record, "target", "HARMFUL|PLAYER")
        if record.failed then return end
    end
    -- The formatter stays bound for the frame's lifetime, including while its
    -- AuraButtons are inaccessible. Only public configuration enters these rules.
    if record.signature ~= signature then
        record.formatter:SetBreakpoints(points)
        record.signature = signature
    end
    record.stylePending = false
    for _, source in ipairs(record.sources) do
        StyleButton(record, source)
        if record.include ~= ids or record.cooldownID ~= id then
            source.container:SetAuraSlotCandidateFilters("stacks", { includeSpellIDs = ids })
        end
        if record.failed then return end
    end
    for _, source in ipairs(record.sources) do
        if not source.bound then return end
    end
    record.include, record.cooldownID, record.active = ids, id, true
    Native(record, 0)
    record.host:SetAlpha(1)
end

Queue = function(record)
    if record.queued or record.failed then return end
    record.queued = true
    After(0, function()
        record.queued = false
        if not pcall(Sync, record) then Fail(record) end
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
        record = { frame = frame, sources = {} }
        GetFrameData(frame).stackTextOverlay = record
        records[frame] = record
        if frame.OnCooldownIDSet then
            hooksecurefunc(frame, "OnCooldownIDSet", function()
                Park(record)
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
        if record.active then
            local target = record.sources[2]
            if target and target.container.UpdateAllAuras then
                if not pcall(target.container.UpdateAllAuras, target.container) then Fail(record) end
            end
        end
    end
end)

CDM:RegisterCombatStateHandler(function(inCombat)
    if inCombat then return end
    for _, record in pairs(records) do Queue(record) end
end)
