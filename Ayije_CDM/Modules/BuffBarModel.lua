local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]

local CDM_C = CDM and CDM.CONST or {}

local issecretvalue = issecretvalue
local math_floor = math.floor

-- Shared data model for the custom buff bars.
--
-- Shape (per spec):
--   db.buffBarGroups[specID] = {
--       { name = "Group 1", grow = "DOWN", spacing = 1, anchorTarget = "screen",
--         anchorPoint = "CENTER", anchorRelativeTo = "CENTER",
--         offsetX = 0, offsetY = 0,
--         bars = { <bar>, ... } },
--   }
--   db.buffBarTimers[specID].bars = { <bar>, ... }   -- ungrouped
--
-- A <bar> is FULLY self-contained: it carries every visual it needs, so a bar
-- looks identical wherever it lives and moving one between groups never
-- changes how it renders. Groups own placement only (anchor/grow/spacing).
--
-- Grow direction and spacing are deliberately NOT bar fields: they describe how
-- a run of bars stacks, which is a property of the run, not of one bar. Grouped
-- bars take them from their group; the ungrouped stack takes them from the
-- shared buffBarGrowDirection / buffBarSpacing globals.
--
--   { barType = "timer" | "stack",
--     spellID = 12345, baseSpellID = 12340, name = "Foo",
--     width = 0, height = 20, texture = "Solid",
--     barColor = {...}, bgColor = {...},
--     iconPosition = "LEFT", iconGap = 1,
--     showName = true, nameMaxChars = 0, nameFontSize = 15, nameColor = {...},
--     nameOffsetX = 2, nameOffsetY = 0,
--     showDuration = true, durationFontSize = 15, durationColor = {...},
--     durationPosition = "RIGHT", durationOffsetX = -2, durationOffsetY = 0,
--     timerDecimals = true, decimalThreshold = 5,
--     -- stack-only:
--     maxStacks = 20, alwaysShow = true,
--     colorThresholds = { { stacks = 10, color = {r,g,b,a} }, ... },
--     tickValues = "5,10,15", tickWidth = 1, tickColor = {...} }
--
-- Bars are stored DENSE (every key present). Unlike profile keys these are not
-- sparse-stripped, because there is no per-key default to fall back to once a
-- bar has been detached from the globals.

CDM.BUFFBAR = CDM.BUFFBAR or {}
local M = CDM.BUFFBAR

M.TYPE_TIMER = "timer"
M.TYPE_STACK = "stack"

local EMPTY = {}
M.EMPTY = EMPTY

local function GetSpecID()
    return (CDM.GetCurrentSpecID and CDM:GetCurrentSpecID()) or nil
end
M.GetSpecID = GetSpecID

local function IsUsableSID(id)
    if type(id) ~= "number" then return false end
    if issecretvalue and issecretvalue(id) then return false end
    return id > 0 and id == math_floor(id)
end
M.IsUsableSID = IsUsableSID

-- Defaults for a newly added bar. Seeded from the legacy global buffBar* keys
-- so a bar added today looks like the bars the user already has, then becomes
-- independent of them the moment it is stored.

local function Cfg(key, fallback)
    local get = CDM_C.GetConfigValue
    if get then return get(key, fallback) end
    return fallback
end

local function CopyColor(c, fr, fg, fb, fa)
    if type(c) == "table" then
        return { r = c.r or fr, g = c.g or fg, b = c.b or fb, a = c.a or fa or 1 }
    end
    return { r = fr, g = fg, b = fb, a = fa or 1 }
end
M.CopyColor = CopyColor

-- Every visual key a bar owns, with the global it seeds from. Used both to
-- build new bars and to backfill bars saved before a key existed.
local BAR_VISUAL_KEYS = {
    { key = "width",              global = "buffBarWidth",                 default = 0 },
    { key = "height",             global = "buffBarHeight",                default = 20 },
    { key = "texture",            global = "buffBarTexture",               default = "Solid" },
    { key = "iconPosition",       global = "buffBarIconPosition",          default = "LEFT" },
    { key = "iconGap",            global = "buffBarIconGap",               default = 1 },
    { key = "showName",           global = "buffBarShowName",              default = true },
    { key = "nameMaxChars",       global = "buffBarNameMaxChars",          default = 0 },
    { key = "nameFontSize",       global = "buffBarNameFontSize",          default = 15 },
    { key = "nameOffsetX",        global = "buffBarNameOffsetX",           default = 2 },
    { key = "nameOffsetY",        global = "buffBarNameOffsetY",           default = 0 },
    { key = "showDuration",       global = "buffBarShowDuration",          default = true },
    { key = "durationFontSize",   global = "buffBarDurationFontSize",      default = 15 },
    { key = "durationPosition",   global = "buffBarDurationPosition",      default = "RIGHT" },
    { key = "durationOffsetX",    global = "buffBarDurationOffsetX",       default = -2 },
    { key = "durationOffsetY",    global = "buffBarDurationOffsetY",       default = 0 },
    { key = "showApplications",   global = "buffBarShowApplications",      default = true },
    { key = "applicationsFontSize",     global = "buffBarApplicationsFontSize",    default = 15 },
    { key = "applicationsPosition",     global = "buffBarApplicationsPosition",    default = "CENTER" },
    { key = "applicationsOffsetX",      global = "buffBarApplicationsOffsetX",     default = 0 },
    { key = "applicationsOffsetY",      global = "buffBarApplicationsOffsetY",     default = 0 },
    { key = "decimalThreshold",   global = "buffBarDecimalThreshold",      default = 5 },
}
M.BAR_VISUAL_KEYS = BAR_VISUAL_KEYS

local BAR_COLOR_KEYS = {
    { key = "barColor",           global = "buffBarColor",            r = 0.4, g = 0.6, b = 0.9, a = 1 },
    { key = "bgColor",            global = "buffBarBackgroundColor",  r = 0.1, g = 0.1, b = 0.1, a = 0.8 },
    { key = "nameColor",          global = "buffBarNameColor",        r = 1, g = 1, b = 1, a = 1 },
    { key = "durationColor",      global = "buffBarDurationColor",    r = 1, g = 1, b = 1, a = 1 },
    { key = "applicationsColor",  global = "buffBarApplicationsColor", r = 1, g = 1, b = 1, a = 1 },
}
M.BAR_COLOR_KEYS = BAR_COLOR_KEYS

-- Fill in any visual key a bar is missing. Bars saved before a key was
-- introduced (or hand-edited profiles) get the global's current value rather
-- than a nil that would crash the renderer.
function M.NormalizeBar(bar)
    if type(bar) ~= "table" then return nil end
    if bar.barType ~= M.TYPE_STACK then bar.barType = M.TYPE_TIMER end

    for i = 1, #BAR_VISUAL_KEYS do
        local spec = BAR_VISUAL_KEYS[i]
        if bar[spec.key] == nil then
            bar[spec.key] = Cfg(spec.global, spec.default)
        end
    end
    for i = 1, #BAR_COLOR_KEYS do
        local spec = BAR_COLOR_KEYS[i]
        if type(bar[spec.key]) ~= "table" then
            bar[spec.key] = CopyColor(Cfg(spec.global, nil), spec.r, spec.g, spec.b, spec.a)
        end
    end
    if bar.timerDecimals == nil then bar.timerDecimals = true end

    if bar.barType == M.TYPE_STACK then
        -- Never 0: the fill range is (0, maxStacks) and a zero span would make
        -- every SetValue clamp to full.
        if type(bar.maxStacks) ~= "number" or bar.maxStacks < 1 then
            bar.maxStacks = 10
        end
        if bar.alwaysShow == nil then bar.alwaysShow = true end
        if type(bar.colorThresholds) ~= "table" then bar.colorThresholds = {} end
        if bar.tickValues == nil then bar.tickValues = "" end
        if bar.tickWidth == nil then bar.tickWidth = 1 end
        if type(bar.tickColor) ~= "table" then
            bar.tickColor = { r = 0, g = 0, b = 0, a = 1 }
        end
    end
    return bar
end

-- Threshold list, sorted ascending and stripped of unusable rows. The renderer
-- relies on the order: overlays are chained parent->child in this sequence so
-- the highest crossed threshold draws last and wins, with no Lua comparison
-- against a (possibly secret) stack count.
local scratchThresholds = {}

function M.GetSortedThresholds(bar)
    wipe(scratchThresholds)
    local list = bar and bar.colorThresholds
    if type(list) ~= "table" then return scratchThresholds end
    for i = 1, #list do
        local t = list[i]
        if type(t) == "table" and type(t.stacks) == "number" and t.stacks > 0 then
            scratchThresholds[#scratchThresholds + 1] = t
        end
    end
    table.sort(scratchThresholds, function(a, b) return a.stacks < b.stacks end)
    return scratchThresholds
end

-- Parsed tick positions. Cosmetic and static: derived from settings only, never
-- from a live count, so this never touches a secret.
function M.ParseTickValues(str, maxStacks)
    local out = {}
    if type(str) ~= "string" or str:match("^%s*$") then return out end
    if type(maxStacks) ~= "number" or maxStacks < 2 then return out end
    for part in str:gmatch("[^,]+") do
        local n = tonumber(part:match("^%s*(.-)%s*$"))
        -- n >= 1 rejects 0; n < maxStacks rejects a tick under the far border.
        if n and n >= 1 and n < maxStacks then
            out[#out + 1] = n
        end
    end
    table.sort(out)
    return out
end

function M.CreateBar(spellID, name, barType)
    local bar = {
        barType = (barType == M.TYPE_STACK) and M.TYPE_STACK or M.TYPE_TIMER,
        spellID = spellID,
        name = name,
    }
    -- cooldownInfo only carries the override id while talented, so capture the
    -- base or the bar goes dark once untalented.
    local rawBase = C_Spell and C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(spellID)
    if rawBase and rawBase ~= spellID then bar.baseSpellID = rawBase end
    return M.NormalizeBar(bar)
end

-- A duplicated bar keeps every visual but is otherwise independent.
function M.CloneBar(src)
    if type(src) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(src) do
        if type(v) == "table" and v.r ~= nil then
            out[k] = { r = v.r, g = v.g, b = v.b, a = v.a }
        elseif type(v) ~= "table" then
            out[k] = v
        end
    end
    return M.NormalizeBar(out)
end

-- Group accessors

function M.GetGroups(specID)
    specID = specID or GetSpecID()
    local db = CDM.db
    local root = specID and db and db.buffBarGroups
    return (root and root[specID]) or EMPTY
end

function M.EnsureGroups(specID)
    specID = specID or GetSpecID()
    if not specID then return nil end
    local db = CDM.db
    if not db then return nil end
    db.buffBarGroups = db.buffBarGroups or {}
    db.buffBarGroups[specID] = db.buffBarGroups[specID] or {}
    return db.buffBarGroups[specID]
end

function M.CreateGroup(groups, name)
    return {
        name = name,
        bars = {},
        grow = "DOWN",
        spacing = 1,
        anchorTarget = "screen",
        anchorPoint = "CENTER",
        anchorRelativeTo = "CENTER",
        offsetX = 0,
        offsetY = 0,
    }
end

-- Ungrouped accessors. The legacy buffBarTimers store is reused verbatim so
-- existing saved bars keep working with no migration of their location.

function M.GetUngrouped(specID)
    specID = specID or GetSpecID()
    local db = CDM.db
    local root = specID and db and db.buffBarTimers
    local specTbl = root and root[specID]
    return (specTbl and specTbl.bars) or EMPTY
end

function M.EnsureUngrouped(specID)
    specID = specID or GetSpecID()
    if not specID then return nil end
    local db = CDM.db
    if not db then return nil end
    db.buffBarTimers = db.buffBarTimers or {}
    local specTbl = db.buffBarTimers[specID]
    if not specTbl then
        specTbl = { bars = {} }
        db.buffBarTimers[specID] = specTbl
    end
    specTbl.bars = specTbl.bars or {}
    return specTbl.bars
end

-- Iteration helpers used by the renderer and the decimal binder. Both need a
-- flat view of every bar regardless of where it lives.

-- Appends { bar, group, groupIndex, indexInParent } for every configured bar.
-- `out` is reused by the caller; this never allocates a new table.
function M.CollectAllBars(out, specID)
    specID = specID or GetSpecID()
    wipe(out)

    local ungrouped = M.GetUngrouped(specID)
    for i = 1, #ungrouped do
        local bar = M.NormalizeBar(ungrouped[i])
        if bar then
            out[#out + 1] = { bar = bar, group = nil, groupIndex = nil, indexInParent = i }
        end
    end

    local groups = M.GetGroups(specID)
    for gi = 1, #groups do
        local group = groups[gi]
        local bars = type(group) == "table" and group.bars
        if type(bars) == "table" then
            for i = 1, #bars do
                local bar = M.NormalizeBar(bars[i])
                if bar then
                    out[#out + 1] = { bar = bar, group = group, groupIndex = gi, indexInParent = i }
                end
            end
        end
    end
    return out
end

-- Is this spell already configured anywhere in the current spec? Drives the
-- "(added)" marker in the Add Bar picker.
function M.IsSpellConfigured(spellID, specID)
    if not IsUsableSID(spellID) then return false end
    local ungrouped = M.GetUngrouped(specID)
    for i = 1, #ungrouped do
        if type(ungrouped[i]) == "table" and ungrouped[i].spellID == spellID then return true end
    end
    local groups = M.GetGroups(specID)
    for gi = 1, #groups do
        local bars = type(groups[gi]) == "table" and groups[gi].bars
        if type(bars) == "table" then
            for i = 1, #bars do
                if type(bars[i]) == "table" and bars[i].spellID == spellID then return true end
            end
        end
    end
    return false
end

-- Remove a bar by identity from wherever it lives. Returns the bar, its group
-- (nil when ungrouped) and its former index, so callers can re-insert it.
function M.RemoveBar(target, specID)
    if type(target) ~= "table" then return nil end

    local ungrouped = M.GetUngrouped(specID)
    for i = #ungrouped, 1, -1 do
        if ungrouped[i] == target then
            table.remove(ungrouped, i)
            return target, nil, i
        end
    end

    local groups = M.GetGroups(specID)
    for gi = 1, #groups do
        local bars = type(groups[gi]) == "table" and groups[gi].bars
        if type(bars) == "table" then
            for i = #bars, 1, -1 do
                if bars[i] == target then
                    table.remove(bars, i)
                    return target, groups[gi], i
                end
            end
        end
    end
    return nil
end

-- Move a bar into a group (groupIndex nil => ungrouped). No-op when it is
-- already there, so a drop onto its own container does not reorder it.
function M.MoveBar(target, groupIndex, specID)
    if type(target) ~= "table" then return false end

    local destination
    if groupIndex then
        local groups = M.EnsureGroups(specID)
        local group = groups and groups[groupIndex]
        if not group then return false end
        group.bars = group.bars or {}
        destination = group.bars
    else
        destination = M.EnsureUngrouped(specID)
    end
    if not destination then return false end

    for i = 1, #destination do
        if destination[i] == target then return false end
    end

    if not M.RemoveBar(target, specID) then return false end
    destination[#destination + 1] = target
    return true
end
