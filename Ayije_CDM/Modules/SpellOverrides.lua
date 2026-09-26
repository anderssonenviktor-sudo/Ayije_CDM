local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
local GetFrameData = CDM.GetFrameData
local GetSpellCooldown = C_Spell.GetSpellCooldown
local GetSpellCharges = C_Spell.GetSpellCharges
local FindOverride = C_SpellBook and C_SpellBook.FindSpellOverrideByID
local IsSecret = issecretvalue or function() return false end
local VIEWERS = CDM.CONST.VIEWERS
-- Keep gates enabled after first use so removed overrides restore managed frames.
local gates = {}
CDM.spellOverrideGates = gates
local scannedProfile, scannedSpec

function CDM:ResolveCooldownSpellOverride(frame)
    if GetFrameData(frame).cdmCooldownBuffSpellID then return nil end
    local index = self.CheckCdGroupMatch and self.CheckCdGroupMatch(frame)
    if index then
        local sets = self.CooldownGroupSets
        return self.GetCooldownGroupSpellOverride(sets and sets.groups and sets.groups[index], GetFrameData(frame).cdGroupSpellID)
    end
    for _, id in ipairs(self:GetSpellIDCandidates(frame)) do
        local entry = self:GetUngroupedCooldownOverride(id)
        if entry then return entry end
    end
end

function CDM:ResolveLiveCooldownSpell(frame)
    local info = frame.GetCooldownInfo and frame:GetCooldownInfo() or frame.cooldownInfo
    local id = info and (info.overrideSpellID or info.spellID)
    if not self.IsSafeNumber(id) or id <= 0 then return nil end
    local live = FindOverride and FindOverride(id)
    return self.IsSafeNumber(live) and live > 0 and live or id
end

function CDM:ScanSpellOverrideFeatures()
    scannedProfile, scannedSpec = self.db, self:GetCurrentSpecID()
    local function Scan(entries)
        for _, entry in pairs(entries or {}) do
            if type(entry) == "table" then
                if entry.suppressGCD then gates.gcd = true end
                if entry.replaceBuffSpellID then gates.replacement = true end
            end
        end
    end
    local db = self.db
    if not db then return end
    Scan(db.ungroupedCooldownOverrides and db.ungroupedCooldownOverrides[scannedSpec])
    for _, group in ipairs(db.cooldownGroups and db.cooldownGroups[scannedSpec] or {}) do Scan(group.spellOverrides) end
end

local function ChargeState(id)
    local info = id and GetSpellCharges(id)
    if not info then return false, false end
    if IsSecret(info.maxCharges) then return true, true end
    local charge = type(info.maxCharges) == "number" and info.maxCharges > 1
    return charge, charge and (IsSecret(info.isActive) or info.isActive == true)
end

function CDM:ApplySpellAppearanceOverrides(frame, vName)
    if scannedProfile ~= self.db or scannedSpec ~= self:GetCurrentSpecID() then self:ScanSpellOverrideFeatures() end
    if not gates.gcd then return end
    local fd = GetFrameData(frame)
    if vName then fd.spellOverrideViewer = vName end
    if fd.spellOverrideViewer ~= VIEWERS.ESSENTIAL and fd.spellOverrideViewer ~= VIEWERS.UTILITY then return end
    local cd = frame.Cooldown
    if not cd then return end
    local state = fd.spellAppearance
    if not state then state = {}; fd.spellAppearance = state end
    if state.busy then return end
    local function Apply() CDM:ApplySpellAppearanceOverrides(frame) end
    if not state.hooked then
        state.hooked = true
        state.draw = cd.GetDrawSwipe and cd:GetDrawSwipe()
        if state.draw == nil then state.draw = true end
        hooksecurefunc(cd, "SetDrawSwipe", function(_, value)
            if state.busy then return end
            state.draw = value
            Apply()
        end)
        for _, method in ipairs({ "SetCooldown", "SetCooldownFromDurationObject", "Clear" }) do
            if cd[method] then hooksecurefunc(cd, method, Apply) end
        end
        if frame.RefreshIconColor then hooksecurefunc(frame, "RefreshIconColor", Apply) end
    end
    state.busy = true
    local entry = self:ResolveCooldownSpellOverride(frame)
    local hide = false
    local aura = frame.cooldownUseAuraDisplayTime == true and fd.cdmAuraOverrideActive
    if entry and entry.suppressGCD and not aura then
        local id = self:ResolveLiveCooldownSpell(frame)
        local _, recharging = ChargeState(id)
        if not recharging then
            local info = id and GetSpellCooldown(id)
            hide = info and not IsSecret(info.isOnGCD) and info.isOnGCD == true
        end
    end
    if hide then
        cd:SetDrawSwipe(false)
        state.drawManaged = true
    elseif state.drawManaged then
        cd:SetDrawSwipe(state.draw)
        state.drawManaged = nil
    end
    state.busy = false
end

CDM:RegisterRefreshCallback("spellOverrideFeatures", function() CDM:ScanSpellOverrideFeatures() end,
    35, { "STYLE", "CD_DATA", "BUFF_DATA", "LAYOUT" })
