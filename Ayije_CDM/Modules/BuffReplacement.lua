local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
local GetFrameData = CDM.GetFrameData
local VIEWERS = CDM.CONST.VIEWERS
local InCombatLockdown = InCombatLockdown
local GetBaseSpell = C_Spell.GetBaseSpell
local GetSpellName = C_Spell.GetSpellName
local After = C_Timer.After
local IsSecret = issecretvalue or function() return false end
local routes, bySource = {}, setmetatable({}, { __mode = "k" })
local queued, rebuilding

local function Matches(frame, spellID, cooldownID)
    if cooldownID then return frame.cooldownID == cooldownID end
    for _, id in ipairs(CDM:GetSpellIDCandidates(frame)) do
        if id == spellID or (GetBaseSpell and GetBaseSpell(id) == spellID) then return true end
    end
    return false
end

local function BuffActive(frame)
    if not frame:IsShown() then return false end
    if not frame:GetParent():IsShown() then return false end
    if not IsSecret(frame.isActive) and frame.isActive ~= nil then return frame.isActive == true end
    if IsSecret(frame.auraInstanceID) then return true end
    return frame.auraInstanceID ~= nil
end

local function Sync(route)
    if route.busy then return end
    local entry = CDM:ResolveCooldownSpellOverride(route.target)
    local _, relativeTo = route.source:GetPoint(1)
    local active = entry and entry.replaceBuffSpellID == route.spellID
        and entry.replaceBuffCooldownID == route.cooldownID
        and Matches(route.source, route.spellID, route.cooldownID) and BuffActive(route.source)
        and relativeTo == route.target and route.target:IsShown()
    route.busy = true
    route.target:SetAlpha(active and 0 or route.alpha)
    route.source:SetAlpha(active and route.alpha or 0)
    route.busy = false
end

function CDM:IsBuffSlotReplacement(frame)
    return bySource[frame] ~= nil
end

local function Available(frame)
    if CDM.IsCooldownBuffFrame and CDM.IsCooldownBuffFrame(frame) then return false end
    local kind = CDM.CheckBuffRegistryMatch and CDM.CheckBuffRegistryMatch(frame)
    if kind == "buffgroup" then return false end
    local id = CDM.GetBaseSpellID(frame)
    if id and CDM.resourcesHiddenBuffSet and CDM.resourcesHiddenBuffSet[id] then return false end
    return frame.Cooldown and frame.Icon and frame.cooldownInfo
end

function CDM:GetBuffReplacementOptions()
    local options = { { value = 0, label = self.L["None"] } }
    local viewer = _G[VIEWERS.BUFF]
    if not viewer or not viewer.itemFramePool then return options end
    for frame in viewer.itemFramePool:EnumerateActive() do
        if Available(frame) then
            local id = CDM.GetBaseSpellID(frame)
            local cooldownID = frame.cooldownID
            if CDM.IsSafeNumber(id) and CDM.IsSafeNumber(cooldownID) then
                options[#options + 1] = { value = cooldownID, spellID = id,
                    label = (GetSpellName(id) or tostring(id)) .. " (" .. cooldownID .. ")" }
            end
        end
    end
    table.sort(options, function(a, b)
        if a.value == 0 then return b.value ~= 0 end
        if b.value == 0 then return false end
        return a.label < b.label
    end)
    return options
end

function CDM:SetBuffReplacement(entry, choice, specID)
    specID = specID or self:GetCurrentSpecID()
    local function ClearConflicts(entries)
        for _, other in pairs(entries or {}) do
            if type(other) == "table" and other ~= entry
                and (other.replaceBuffCooldownID == choice.value
                    or (not other.replaceBuffCooldownID and other.replaceBuffSpellID == choice.spellID)) then
                other.replaceBuffSpellID, other.replaceBuffCooldownID = nil, nil
            end
        end
    end
    if choice and choice.value ~= 0 then
        ClearConflicts(self.db.ungroupedCooldownOverrides and self.db.ungroupedCooldownOverrides[specID])
        for _, group in ipairs(self.db.cooldownGroups and self.db.cooldownGroups[specID] or {}) do ClearConflicts(group.spellOverrides) end
        entry.replaceBuffSpellID, entry.replaceBuffCooldownID = choice.spellID, choice.value
    else
        entry.replaceBuffSpellID, entry.replaceBuffCooldownID = nil, nil
    end
end

function CDM:QueueBuffReplacements()
    if queued or rebuilding or not self.spellOverrideGates.replacement then return end
    if InCombatLockdown() then
        self.combatDirtyViewers[VIEWERS.BUFF] = true
        for _, route in ipairs(routes) do Sync(route) end
        return
    end
    queued = true
    After(0, function()
        queued = nil
        CDM:Refresh("LAYOUT")
    end)
end

local function Restore(route)
    bySource[route.source] = nil
    GetFrameData(route.target).buffSlotRoute = nil
    GetFrameData(route.source).buffSlotSource = nil
    route.target:SetAlpha(route.alpha)
    route.source:SetAlpha(route.sourceAlpha)
    GetFrameData(route.source).cdmAnchor = nil
end

function CDM:PrepareBuffReplacements()
    if rebuilding or not self.spellOverrideGates.replacement then return end
    if InCombatLockdown() then
        self.combatDirtyViewers[VIEWERS.BUFF] = true
        for _, route in ipairs(routes) do Sync(route) end
        return
    end
    rebuilding = true
    for _, route in ipairs(routes) do Restore(route) end
    wipe(routes)
    local viewer = _G[VIEWERS.BUFF]
    if not viewer or not viewer.itemFramePool then rebuilding = nil; return end
    local targets = {}
    for _, name in ipairs({ VIEWERS.ESSENTIAL, VIEWERS.UTILITY }) do
        local cooldownViewer = _G[name]
        if cooldownViewer and cooldownViewer.itemFramePool then
            for target in cooldownViewer.itemFramePool:EnumerateActive() do
                local entry = self:ResolveCooldownSpellOverride(target)
                if entry and CDM.IsSafeNumber(entry.replaceBuffSpellID) then
                    targets[#targets + 1] = { frame = target, entry = entry }
                end
            end
        end
    end
    table.sort(targets, function(a, b) return (a.frame.cooldownID or 0) < (b.frame.cooldownID or 0) end)
    for _, candidate in ipairs(targets) do
        local target, entry = candidate.frame, candidate.entry
        for source in viewer.itemFramePool:EnumerateActive() do
            if not bySource[source] and Available(source) and Matches(source, entry.replaceBuffSpellID, entry.replaceBuffCooldownID) then
                local route = { source = source, target = target, spellID = entry.replaceBuffSpellID,
                    cooldownID = entry.replaceBuffCooldownID, alpha = target:GetAlpha(), sourceAlpha = source:GetAlpha() }
                routes[#routes + 1] = route
                bySource[source] = route
                local fd, td = GetFrameData(source), GetFrameData(target)
                fd.buffSlotSource, td.buffSlotRoute = route, route
                -- Keep the cooldown as an invisible slot carrier. The real aura frame
                -- keeps its native duration and stacks, and never gets reparented.
                fd.cdmAnchor = { "CENTER", target, "CENTER", 0, 0 }
                source:ClearAllPoints()
                source:SetPoint("CENTER", target, "CENTER")
                source:SetSize(target:GetWidth(), target:GetHeight())
                if not fd.buffSlotHooks then
                    fd.buffSlotHooks = true
                    local function Changed()
                        local current = bySource[source]
                        if current then Sync(current) end
                        CDM:QueueBuffReplacements()
                    end
                    if source.OnActiveStateChanged then hooksecurefunc(source, "OnActiveStateChanged", Changed) end
                    source:HookScript("OnShow", Changed)
                    source:HookScript("OnHide", Changed)
                    hooksecurefunc(source, "SetAlpha", function(_, alpha)
                        local current = bySource[source]
                        if current and not current.busy then current.sourceAlpha = alpha; Sync(current) end
                    end)
                end
                if not td.buffSlotHooks then
                    td.buffSlotHooks = true
                    hooksecurefunc(target, "SetAlpha", function(_, alpha)
                        local current = GetFrameData(target).buffSlotRoute
                        if current and not current.busy then current.alpha = alpha; Sync(current) end
                    end)
                end
                Sync(route)
                break
            end
        end
    end
    rebuilding = nil
end

function CDM:RefreshBuffReplacementSlots()
    if not self.spellOverrideGates.replacement then return end
    for _, route in ipairs(routes) do
        if not InCombatLockdown() then
            route.source:SetSize(route.target:GetWidth(), route.target:GetHeight())
        end
        Sync(route)
    end
end

CDM:RegisterRefreshCallback("buffSlotRoutes", function() CDM:PrepareBuffReplacements() end,
    36, { "STYLE", "CD_DATA", "BUFF_DATA", "LAYOUT" })
CDM:RegisterRefreshCallback("buffSlotAppearance", function() CDM:RefreshBuffReplacementSlots() end,
    46, { "STYLE", "CD_DATA", "BUFF_DATA", "LAYOUT" })
CDM:RegisterCombatStateHandler(function(inCombat)
    if not inCombat then CDM:QueueBuffReplacements() end
end)
CDM:RegisterEvent("PLAYER_ENTERING_WORLD", function() CDM:QueueBuffReplacements() end)
