local AddonName = "Ayije_CDMDev"
local CDM = _G[AddonName]
local GetFrameData = CDM.GetFrameData
local GetSpellCooldown = C_Spell.GetSpellCooldown
local GetSpellCharges = C_Spell.GetSpellCharges
local FindOverride = C_SpellBook and C_SpellBook.FindSpellOverrideByID
local IsSecret = issecretvalue or function() return false end
local VIEWERS = CDM.CONST.VIEWERS
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
                if entry.keepColoredOnCooldown then gates.color = true end
                if (tonumber(entry.thresholdSeconds) or 0) > 0 then gates.threshold = true end
                if entry.cooldownSwipe then gates.swipe = true end
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

local function ExplicitDesaturation(frame, fd, entry)
    return fd.cdmResourceDesatActive or fd.cdmResourceTintWrite
        or (fd.cdmAuraOverrideActive and entry and entry.auraDesaturateInactive
            and frame.cooldownUseAuraDisplayTime ~= true)
end

function CDM:ApplySpellAppearanceOverrides(frame, vName)
    if scannedProfile ~= self.db or scannedSpec ~= self:GetCurrentSpecID() then self:ScanSpellOverrideFeatures() end
    if not (gates.color or gates.threshold or gates.swipe or gates.gcd) then return end
    local fd = GetFrameData(frame)
    if vName then fd.spellOverrideViewer = vName end
    if fd.spellOverrideViewer ~= VIEWERS.ESSENTIAL and fd.spellOverrideViewer ~= VIEWERS.UTILITY then return end
    local state = fd.spellAppearance
    if not state then state = {}; fd.spellAppearance = state end
    if state.busy then return end
    local cd, icon = frame.Cooldown, frame.Icon
    if not cd then return end
    local entry = self:ResolveCooldownSpellOverride(frame)
    local function Apply() CDM:ApplySpellAppearanceOverrides(frame) end
    if not state.hooked then
        state.hooked = true
        state.reverse = cd.GetReverse and cd:GetReverse() or false
        state.draw = cd.GetDrawSwipe and cd:GetDrawSwipe()
        if state.draw == nil then state.draw = true end
        if icon and icon.IsDesaturated then
            state.desatBoolean = icon:IsDesaturated()
            state.desatKind = "boolean"
        end
        hooksecurefunc(cd, "SetReverse", function(_, value)
            if state.busy then return end
            state.reverse = value
            Apply()
        end)
        hooksecurefunc(cd, "SetDrawSwipe", function(_, value)
            if state.busy then return end
            state.draw = value
            Apply()
        end)
        if cd.SetCountdownFormatter then hooksecurefunc(cd, "SetCountdownFormatter", function(_, formatter)
            state.formatter = formatter
            if not state.busy then Apply() end
        end) end
        for _, method in ipairs({ "SetCooldown", "SetCooldownFromDurationObject", "Clear" }) do
            if cd[method] then hooksecurefunc(cd, method, Apply) end
        end
        if frame.RefreshIconColor then hooksecurefunc(frame, "RefreshIconColor", Apply) end
        if icon then
            hooksecurefunc(icon, "SetDesaturated", function(_, value)
                if state.busy then return end
                state.desatBoolean, state.desatAmount = value, nil
                state.desatKind = "boolean"
                if not fd.isProcessingOverride then Apply() end
            end)
            if icon.SetDesaturation then hooksecurefunc(icon, "SetDesaturation", function(_, value)
                if state.busy then return end
                state.desatAmount, state.desatBoolean = value, nil
                state.desatKind = "amount"
                if not fd.isProcessingOverride then Apply() end
            end) end
        end
    end
    state.busy = true
    local id, charge, recharging
    if entry and (entry.cooldownSwipe == "hide" or entry.suppressGCD) then
        id = self:ResolveLiveCooldownSpell(frame)
        charge, recharging = ChargeState(id)
    end
    local aura = frame.cooldownUseAuraDisplayTime == true and fd.cdmAuraOverrideActive
    local swipe = entry and entry.cooldownSwipe
    local hide = swipe == "hide" and not charge
    if entry and entry.suppressGCD and not aura and not recharging then
        local info = id and GetSpellCooldown(id)
        if info and not IsSecret(info.isOnGCD) and info.isOnGCD == true then hide = true end
    end
    if swipe == "reverse" and not IsSecret(state.reverse) then
        cd:SetReverse(not state.reverse)
        state.reverseManaged = true
    elseif state.reverseManaged then
        cd:SetReverse(state.reverse)
        state.reverseManaged = nil
    end
    if hide then
        cd:SetDrawSwipe(false)
        state.drawManaged = true
    elseif state.drawManaged then
        cd:SetDrawSwipe(state.draw)
        state.drawManaged = nil
    end
    if icon and entry and entry.keepColoredOnCooldown and not ExplicitDesaturation(frame, fd, entry) then
        icon:SetDesaturated(false)
        if icon.SetDesaturation then icon:SetDesaturation(0) end
        state.colorManaged = true
    elseif icon and state.colorManaged and not ExplicitDesaturation(frame, fd, entry) then
        if state.desatKind == "amount" and icon.SetDesaturation then icon:SetDesaturation(state.desatAmount)
        elseif state.desatKind == "boolean" then icon:SetDesaturated(state.desatBoolean) end
        state.colorManaged = nil
    end
    if cd.SetCountdownFormatter then
        local formatter = self.CooldownFormatter.GetForSpell(entry)
        if formatter or state.formatterManaged then
            local desired = formatter or self.CooldownFormatter.Get()
            if state.formatter ~= desired then cd:SetCountdownFormatter(desired); state.formatter = desired end
            state.formatterManaged = formatter ~= nil
        end
    end
    state.busy = false
end

CDM:RegisterRefreshCallback("spellOverrideFeatures", function() CDM:ScanSpellOverrideFeatures() end,
    35, { "STYLE", "CD_DATA", "BUFF_DATA", "LAYOUT" })
