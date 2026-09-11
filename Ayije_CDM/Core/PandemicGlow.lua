local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]

local GetFrameData = CDM.GetFrameData
local UnitClass = UnitClass
local issecretvalue = issecretvalue
local min, max = math.min, math.max
local tracked = setmetatable({}, { __mode = "k" })
local cache
local Pandemic = {}
CDM.PandemicGlow = Pandemic

function CDM.InvalidatePandemicGlowSettings()
    cache = nil
end

local function Safe(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Number(value, default, low, high)
    if not Safe(value) or type(value) ~= "number" or value ~= value then return default end
    return min(high, max(low, value))
end

local function Merge(defaults, global)
    local result = {}
    for key, fallback in pairs(defaults) do
        local base
        if type(global) == "table" then base = global[key] end
        if type(fallback) == "table" then
            result[key] = Merge(fallback, base)
        elseif base ~= nil then result[key] = base
        else result[key] = fallback end
    end
    return result
end

function CDM.ResolvePandemicGlowSettings()
    if cache then return cache end
    local db = CDM.db or {}
    local settings = Merge(CDM.defaults.pandemicGlow, db.pandemicGlow)
    local style = CDM.GLOW_CAPABILITIES[settings.style] and settings.style or "proc"
    settings.style = style
    local r, g, b
    if settings.colorMode == "class" then
        local _, class = UnitClass("player")
        local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
        local color = colors and colors[class]
        if color then r, g, b = color.r, color.g, color.b end
    elseif settings.colorMode == "custom" then
        r = Number(settings.r, 1, 0, 1)
        g = Number(settings.g, 0.2, 0, 1)
        b = Number(settings.b, 0.2, 0, 1)
    end
    local specific = {}
    if style == "pixel" then
        specific.lines = math.floor(Number(settings.pixel.lines, 8, 1, 20))
        specific.thickness = Number(settings.pixel.thickness, 2, 1, 10)
        specific.background = settings.pixel.background == true
        specific.backgroundColor = {
            r = Number(settings.pixel.backgroundR, 0, 0, 1),
            g = Number(settings.pixel.backgroundG, 0, 0, 1),
            b = Number(settings.pixel.backgroundB, 0, 0, 1),
        }
    elseif style == "autocast" then
        specific.sparkCount = math.floor(Number(settings.autocast.sparkCount, 4, 1, 16))
    elseif style == "shape" then
        specific.intensity = Number(settings.shape.intensity, 1, 0.25, 2)
    end
    settings.options = {
        reason = "pandemic", r = r, g = g, b = b,
        alpha = Number(settings.alpha, 1, 0.1, 1),
        scale = Number(settings.scale, 1, 0.75, 2),
        offsetX = 0,
        offsetY = 0,
        speedMultiplier = 1,
        layer = (settings.layer == "background" or settings.layer == "overlay") and settings.layer or "normal",
        styleOptions = specific,
    }
    cache = settings
    return settings
end

local function SpellID(icon)
    return CDM:GetSpellIDCandidates(icon)[1]
end

function Pandemic:Reset(icon)
    CDM.StopGlow(icon, "pandemic")
    local state = GetFrameData(icon).pandemicGlowState
    if state then
        state.active, state.spellID = false, nil
    end
    tracked[icon] = nil
end

function Pandemic:Update(icon)
    local data = GetFrameData(icon)
    local state = data.pandemicGlowState
    if not state or not state.active then return end
    local spellID = SpellID(icon)
    if state.spellID ~= spellID then
        self:Reset(icon)
        return
    end
    local settings = CDM.ResolvePandemicGlowSettings()
    if settings.enabled ~= true or not icon:IsShown() or data.cdmVisualsHidden
        or CDM.db.hidePandemicIndicator ~= true or CDM.db.pandemicCustomizationEnabled ~= true then
        CDM.StopGlow(icon, "pandemic")
        return
    end
    CDM.StartGlow(icon, settings.style, settings.options)

end

function Pandemic:SetState(icon, active)
    local data = GetFrameData(icon)
    local state = data.pandemicGlowState
    if not active or not icon:IsShown() then
        if state and state.active then self:Reset(icon) end
        return
    end
    -- Blizzard calls ShowPandemicStateFrame on every registered update.
    if state and state.active then return end
    if not state then state = {}; data.pandemicGlowState = state end
    state.active, state.spellID = true, SpellID(icon)
    tracked[icon] = true
    self:Update(icon)
end

function Pandemic:HookFrame(icon)
    local data = GetFrameData(icon)
    if data.pandemicGlowHooked then return end
    data.pandemicGlowHooked = true
    icon:HookScript("OnHide", function(self) Pandemic:Reset(self) end)
    icon:HookScript("OnShow", function(self)
        if self.PandemicIcon then Pandemic:SetState(self, true) end
    end)
    -- RefreshData can reassign an already visible pooled icon.
    for _, method in ipairs({ "RefreshData", "OnCooldownIDSet", "SetAuraInstanceInfo", "OnActiveStateChanged" }) do
        if type(icon[method]) == "function" then
            if method == "OnCooldownIDSet" then
                hooksecurefunc(icon, method, function(self) Pandemic:Reset(self) end)
            else
                hooksecurefunc(icon, method, function(self) Pandemic:Update(self) end)
            end
        end
    end
    for _, method in ipairs({ "OnAuraInstanceInfoCleared", "OnNewTarget" }) do
        if type(icon[method]) == "function" then
            hooksecurefunc(icon, method, function(self) Pandemic:Reset(self) end)
        end
    end
    if icon.PandemicIcon then self:SetState(icon, true) end
end

local function Refresh()
    CDM.InvalidatePandemicGlowSettings()
    for icon in pairs(tracked) do Pandemic:Update(icon) end
end

CDM:RegisterRefreshCallback("pandemicGlow", Refresh, 56, { "STYLE", "BUFF_DATA", "CD_DATA" })
