local AddonName = "Ayije_CDMDev"
local CDM = _G[AddonName]

local Formatter = {}
CDM.CooldownFormatter = Formatter

local instance = nil

local function CloneBreakpoint(bp, newThreshold)
    local copy = {
        threshold = newThreshold or bp.threshold,
        format = bp.format,
        rounding = bp.rounding,
        step = bp.step,
        min = bp.min,
        max = bp.max,
    }
    if bp.components then
        local c = {}
        for i = 1, #bp.components do
            local src = bp.components[i]
            c[i] = { div = src.div, mod = src.mod, step = src.step, rounding = src.rounding }
        end
        copy.components = c
    end
    return copy
end

local function BuildBreakpoints(cache)
    local NEAREST = Enum.NumericRuleFormatRounding.Nearest
    local UP = Enum.NumericRuleFormatRounding.Up

    local decThreshold = cache.cooldownDecimalThreshold
    local points = {}

    if decThreshold > 0 then
        points[#points + 1] = { threshold = 0, format = "%.1f", rounding = NEAREST }
        points[#points + 1] = { threshold = decThreshold, format = "%d", rounding = UP, step = 1 }
    else
        points[#points + 1] = { threshold = 0, format = "%d", rounding = UP, step = 1 }
    end

    -- Thresholds are offset above the integer boundary (59, 3599, 86399) so UP-rounded
    -- input in (N, N+1] routes into the larger-unit breakpoint, avoiding a "60" flash
    -- before mm:ss takes over at the minute boundary (same logic for hours and days).
    points[#points + 1] = {
        threshold = 59.0001, format = "%d:%02d", rounding = UP, step = 1,
        components = { { div = 60 }, { mod = 60 } },
    }
    points[#points + 1] = {
        threshold = 3599.0001, format = "%dh", rounding = UP, step = 1,
        components = { { div = 3600 } },
    }
    points[#points + 1] = {
        threshold = 86399.0001, format = "%dd", rounding = UP, step = 1,
        components = { { div = 86400 } },
    }

    local colorEnabled = cache.cooldownColorThresholdEnabled
    local colorThreshold = cache.cooldownColorThreshold
    local colorCfg = cache.cooldownColorThresholdColor

    if colorEnabled and colorThreshold > 0 and colorCfg then
        local color = CreateColor(colorCfg.r, colorCfg.g, colorCfg.b, colorCfg.a or 1)

        local activeIdx = 1
        for i = 1, #points do
            if points[i].threshold <= colorThreshold then
                activeIdx = i
            else
                break
            end
        end

        if points[activeIdx].threshold < colorThreshold then
            points[#points + 1] = CloneBreakpoint(points[activeIdx], colorThreshold)
        end

        for i = 1, #points do
            if points[i].threshold < colorThreshold then
                points[i].format = color:WrapTextInColorCode(points[i].format)
            end
        end
    end

    table.sort(points, function(a, b) return a.threshold < b.threshold end)
    return points
end

function Formatter.Rebuild(styleCache)
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding) then
        instance = nil
        return
    end
    local decThreshold = styleCache.cooldownDecimalThreshold or 0
    if decThreshold <= 0 and not styleCache.cooldownColorThresholdEnabled then
        instance = nil
        return
    end

    local breakpoints = BuildBreakpoints(styleCache)

    -- A fresh object every rebuild: SetCountdownFormatter snapshots the rules at
    -- attach time, so mutating the live one changes nothing on attached widgets.
    local new = C_StringUtil.CreateNumericRuleFormatter()
    if not pcall(new.SetBreakpoints, new, breakpoints) then
        return  -- rejected table: keep the previous formatter
    end
    instance = new
end

function Formatter.Get()
    return instance
end

local spellFormatters = {}
local spellFormatterCount = 0
function Formatter.GetForSpell(entry)
    if not entry or not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding) then return nil end
    local seconds = math.max(0, math.min(59, math.floor(tonumber(entry.thresholdSeconds) or 0)))
    if seconds == 0 or not (entry.thresholdDecimals or entry.thresholdColorEnabled) then return nil end
    local color = entry.thresholdColor or { r = 1, g = 0.2, b = 0.2 }
    local key = table.concat({ seconds, entry.thresholdDecimals and 1 or 0, entry.thresholdColorEnabled and 1 or 0,
        color.r or 1, color.g or 0.2, color.b or 0.2 }, "|")
    if spellFormatters[key] ~= nil then return spellFormatters[key] or nil end
    if spellFormatterCount >= 128 then
        spellFormatters = {}
        spellFormatterCount = 0
    end
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    local points = BuildBreakpoints({
        cooldownDecimalThreshold = entry.thresholdDecimals and seconds or 0,
        cooldownColorThresholdEnabled = entry.thresholdColorEnabled,
        cooldownColorThreshold = seconds,
        cooldownColorThresholdColor = color,
    })
    if not pcall(formatter.SetBreakpoints, formatter, points) then spellFormatters[key] = false; return nil end
    spellFormatters[key] = formatter
    spellFormatterCount = spellFormatterCount + 1
    return formatter
end
