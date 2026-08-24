local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]

local CDM_C = CDM and CDM.CONST or {}
local VIEWERS = CDM_C.VIEWERS
local BORDER = CDM.BORDER
local GCU = CDM.GroupContainerUtils

local LSM = LibStub("LibSharedMedia-3.0")
local Pixel = CDM.Pixel
local Snap = Pixel.Snap

local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue
local GetTime = GetTime
local math_floor = math.floor
local math_ceil = math.ceil
local math_max = math.max
local math_min = math.min
local format = string.format
local table_wipe = wipe

-- Own tracking bars that MIRROR Blizzard's BuffBarCooldownViewer frames rather
-- than computing aura state: secret values pass through widget setters natively,
-- so the fill survives combat. Blizzard's own bar frames expose no engine hook
-- (no SetDurationText/SetDurationBar/Cooldown), which is why we render our own.
-- Decimals come from BuffBarDecimals.lua.
--
-- Bars are fully self-contained (see BuffBarModel.lua): every visual is read
-- off the bar itself, never off a global. Groups own placement only. Bars live
-- either ungrouped (rendered against the buff-bar viewer's anchor container) or
-- inside a group (rendered against that group's own container).

local MIN_BUILD = 120100

-- Frame-level plan, all relative to a bar's StatusBar.
--
-- Threshold overlays chain upward one level each (overlay i sits at base + i),
-- so the band they occupy must be RESERVED: with a fixed border offset of +1
-- the second overlay onwards climbs over the border and paints across it.
-- Everything that has to stay above the fill therefore clears the whole band.
local MAX_THRESHOLD_LEVELS = 12
local LEVEL_BORDER = MAX_THRESHOLD_LEVELS + 1
local LEVEL_TICKS  = MAX_THRESHOLD_LEVELS + 2
local LEVEL_TEXT   = MAX_THRESHOLD_LEVELS + 4

local M = CDM.BUFFBAR
local IsUsableSID = M.IsUsableSID

-- In restricted content (combat, M+, PvP) aura data is a Secret Value. It may
-- be passed to C functions and compared against nil with `~= nil`, but never
-- truth-tested (`if x then`), compared, concatenated or printed -- so every
-- guard below must nil-check with `~= nil` BEFORE calling this.
local function IsSecret(v)
    return issecretvalue and issecretvalue(v)
end

local function GetSpecID()
    return (CDM.GetCurrentSpecID and CDM:GetCurrentSpecID()) or nil
end

local function GetBuffBarViewer()
    return _G[VIEWERS.BUFF_BAR]
end

-- IsPlayerSpell is deprecated; C_SpellBook.IsSpellKnown is the 11.x+ form.
local function SpellIsKnown(sid)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, sid)
        if ok then return known and true or false end
    end
    if IsPlayerSpell then return IsPlayerSpell(sid) and true or false end
    return true
end

-- Canonical spell id for a viewer frame. Returns nil when the id is secret,
-- which the assignment passes treat as "trust the sticky binding".
local function GetCanonicalSID(frame)
    if not frame then return nil end
    if frame.GetAuraSpellID then
        local ok, sid = pcall(frame.GetAuraSpellID, frame)
        if ok and IsUsableSID(sid) then return sid end
    end
    if frame.GetSpellID then
        local ok, sid = pcall(frame.GetSpellID, frame)
        if ok and IsUsableSID(sid) then return sid end
    end
    local info = frame.cooldownInfo
    if type(info) == "table" then
        if IsUsableSID(info.overrideSpellID) then return info.overrideSpellID end
        if IsUsableSID(info.spellID) then return info.spellID end
    end
    return nil
end

-- Comparisons go through IsUsableSID first: a secret id throws on `==`, and
-- cooldownInfo carries secret ids in combat (GetCanonicalSID guards the very
-- same fields). An unguarded compare here would propagate out of the layout
-- pass, which does not pcall this path.
local function MatchesSID(info, sid)
    if not info or not IsUsableSID(sid) then return false end
    if IsUsableSID(info.overrideSpellID) and info.overrideSpellID == sid then return true end
    if IsUsableSID(info.spellID) and info.spellID == sid then return true end
    local linked = info.linkedSpellIDs
    if linked then
        for i = 1, #linked do
            local lid = linked[i]
            if IsUsableSID(lid) and lid == sid then return true end
        end
    end
    return false
end

local function GetFrameCooldownInfo(frame)
    local cdID = frame and frame.cooldownID
    if not cdID then return frame and frame.cooldownInfo or nil end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then return frame.cooldownInfo end
    local ok, info = pcall(gci, cdID)
    if ok and info then return info end
    return frame.cooldownInfo
end

-- Does this config want that spell id? Honours the captured talent base form.
local function CfgWantsSID(cfg, sid)
    if not sid then return false end
    if cfg.spellID and cfg.spellID > 0 then
        if sid == cfg.spellID then return true end
        if cfg.baseSpellID and cfg.baseSpellID > 0 and sid == cfg.baseSpellID then return true end
    end
    return false
end

-- While talented, cooldownInfo reports the override in overrideSpellID and the
-- base in spellID; capture the base so the bar still matches once untalented.
local function MatchFrameToConfig(frame, cfg)
    local info = GetFrameCooldownInfo(frame)
    if type(info) ~= "table" then return false end

    if IsUsableSID(cfg.spellID) and not cfg.baseSpellID
        and IsUsableSID(info.overrideSpellID) and info.overrideSpellID == cfg.spellID
        and IsUsableSID(info.spellID) and info.spellID ~= cfg.spellID then
        cfg.baseSpellID = info.spellID
    end

    if cfg.spellID and cfg.spellID > 0 then
        if MatchesSID(info, cfg.spellID) then return true end
        if cfg.baseSpellID and cfg.baseSpellID > 0 and MatchesSID(info, cfg.baseSpellID) then
            return true
        end
    end
    return false
end

-- One config -> at most one frame, each frame consumed once. Eclipse-style
-- sibling frames share one cooldownInfo, so greedy matching would bind both
-- configs to whichever enumerates first.

local assignment    = {}
local frameScratch  = {}
local consumedSet   = {}
local frameSID      = {}
local stickyFrame   = {}     -- cfg -> frame (frame refs NEVER touch cfg itself)
local assignDirty   = true
local assignedFor   = nil

-- Flat view of every configured bar, rebuilt whenever composition changes.
local allEntries = {}
local entriesDirty = true
local entriesSpec = nil

function CDM.InvalidateBuffBarTimerFrames()
    wipe(stickyFrame)
    assignDirty = true
end

local function InvalidateEntries()
    entriesDirty = true
    assignDirty = true
end
CDM.InvalidateBuffBarEntries = InvalidateEntries

-- Ordered list of every bar in the spec, ungrouped first then per group.
local function GetEntries()
    local specID = GetSpecID()
    if not entriesDirty and entriesSpec == specID then return allEntries end
    entriesDirty = false
    entriesSpec = specID
    M.CollectAllBars(allEntries, specID)
    return allEntries
end
CDM.GetBuffBarEntries = GetEntries

local function FrameStillActive(frames, target)
    for i = 1, #frames do
        if frames[i] == target then return true end
    end
    return false
end

-- `bars` here is the flat list of bar configs (not the raw db list) so that
-- grouped and ungrouped bars compete for viewer frames in one pass.
local scratchCfgList = {}
local function BuildCfgList()
    local entries = GetEntries()
    table_wipe(scratchCfgList)
    for i = 1, #entries do
        scratchCfgList[i] = entries[i].bar
    end
    return scratchCfgList
end

local function AssignFramesToConfigs(bars)
    -- The pairing only moves on composition edges; the table identity check
    -- catches spec swaps that replace it without an invalidation site.
    if not assignDirty and assignedFor == bars then
        return assignment
    end
    assignDirty = false
    assignedFor = bars
    wipe(assignment)
    if not bars then return assignment end

    local viewer = GetBuffBarViewer()
    local pool = viewer and viewer.itemFramePool
    if not pool then return assignment end

    -- Snapshot once (enumeration is consumed); resolve canonical ids once
    -- rather than O(configs x frames) pcalls per tick.
    wipe(frameScratch)
    wipe(frameSID)
    local n = 0
    for frame in pool:EnumerateActive() do
        n = n + 1
        frameScratch[n] = frame
        frameSID[frame] = GetCanonicalSID(frame)
    end

    wipe(consumedSet)

    -- Pass 1: sticky. Frame object identity never goes secret, so a pairing
    -- locked in out of combat survives when the id turns secret mid-fight.
    for _, cfg in ipairs(bars) do
        local bound = stickyFrame[cfg]
        if bound and not consumedSet[bound] and FrameStillActive(frameScratch, bound) then
            local sid = frameSID[bound]
            if sid then
                -- Clean read available: keep only if still the right variant
                -- (self-heals a recycled pool frame).
                if CfgWantsSID(cfg, sid) then
                    assignment[cfg] = bound
                    consumedSet[bound] = true
                else
                    stickyFrame[cfg] = nil
                end
            else
                -- Secret: trust the binding locked in earlier.
                assignment[cfg] = bound
                consumedSet[bound] = true
            end
        end
    end

    -- Pass 2: exact per-frame identity. Locks the sticky binding.
    for _, cfg in ipairs(bars) do
        if not assignment[cfg] then
            for i = 1, n do
                local frame = frameScratch[i]
                if not consumedSet[frame] then
                    local sid = frameSID[frame]
                    if sid and CfgWantsSID(cfg, sid) then
                        assignment[cfg] = frame
                        consumedSet[frame] = true
                        stickyFrame[cfg] = frame
                        break
                    end
                end
            end
        end
    end

    -- Pass 3: cooldownInfo/linkedSpellIDs fallback. Do NOT sticky a fuzzy
    -- match -- let a later clean read re-pair it exactly in pass 2.
    for _, cfg in ipairs(bars) do
        if not assignment[cfg] then
            for i = 1, n do
                local frame = frameScratch[i]
                if not consumedSet[frame] and MatchFrameToConfig(frame, cfg) then
                    assignment[cfg] = frame
                    consumedSet[frame] = true
                    break
                end
            end
        end
    end

    return assignment
end

CDM.AssignBuffBarTimerFrames = AssignFramesToConfigs
CDM.BuildBuffBarCfgList = BuildCfgList

-- Which Blizzard frames our own bars currently mirror. Layout.lua excludes
-- these from Blizzard's own row so the buff is not drawn twice. Alpha is
-- restored for any frame that stops being mirrored.
local mirroredFrames = setmetatable({}, { __mode = "k" })
local prevMirrored = setmetatable({}, { __mode = "k" })

function CDM.GetBuffBarTimerMirroredFrames()
    local cfgList = BuildCfgList()
    wipe(mirroredFrames)
    if #cfgList > 0 then
        local map = AssignFramesToConfigs(cfgList)
        for _, frame in pairs(map) do
            mirroredFrames[frame] = true
        end
    end
    -- Restore anything we hid last pass that is no longer mirrored.
    for frame in pairs(prevMirrored) do
        if not mirroredFrames[frame] then
            if frame.SetAlpha then frame:SetAlpha(1) end
            prevMirrored[frame] = nil
        end
    end
    for frame in pairs(mirroredFrames) do
        prevMirrored[frame] = true
    end
    return mirroredFrames
end

-- Picker source: what Blizzard currently shows in the CDM buff-bar viewer.
-- Consumed by the Options "Add Bar" picker.

function CDM.GetBuffBarTrackedSpells()
    local result = {}
    local viewer = GetBuffBarViewer()
    if not viewer or not viewer.itemFramePool then return result end

    local seen = {}
    for frame in viewer.itemFramePool:EnumerateActive() do
        if frame:IsShown() or frame.cooldownInfo then
            local sid = GetCanonicalSID(frame)
            if sid and not seen[sid] then
                seen[sid] = true
                local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
                if C_Spell and C_Spell.GetSpellSubtext then
                    local sub = C_Spell.GetSpellSubtext(sid)
                    if sub and sub ~= "" then name = (name or ("Spell " .. sid)) .. " (" .. sub .. ")" end
                end
                result[#result + 1] = {
                    spellID = sid,
                    name = name or ("Spell " .. sid),
                    icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid),
                    layoutIndex = frame.layoutIndex or 0,
                }
            end
        end
    end

    table.sort(result, function(a, b)
        if a.layoutIndex ~= b.layoutIndex then return a.layoutIndex < b.layoutIndex end
        return a.spellID < b.spellID
    end)
    return result
end

-- Blizzard bar FontString discovery (cached; never stored on the Blizz frame)

local blizzFS = setmetatable({}, { __mode = "k" })

local function GetBlizzBarFontStrings(blizzBar)
    if not blizzBar then return nil, nil end
    local cached = blizzFS[blizzBar]
    if cached then
        return cached.nameFS or nil, cached.timerFS or nil
    end
    -- The StatusBar carries 2 FontStrings: [1] spell name, [2] timer.
    local nameFS, timerFS
    local idx = 0
    local regions = { blizzBar:GetRegions() }
    for i = 1, #regions do
        local rgn = regions[i]
        if rgn and rgn.GetObjectType and rgn:GetObjectType() == "FontString" then
            idx = idx + 1
            if idx == 1 then nameFS = rgn
            elseif idx == 2 then timerFS = rgn end
        end
    end
    blizzFS[blizzBar] = { nameFS = nameFS or false, timerFS = timerFS or false }
    return nameFS, timerFS
end

-- Local time formatting -- ONLY for self-driven bars where numbers are clean.
-- Whole seconds use ceil, matching Blizzard's aura timers: a buff with 16.5s
-- left reads "17", not "16". Flooring showed every buff a second low.

local function FormatTime(remaining)
    if remaining >= 3600 then return format("%dh", math_floor(remaining / 3600)) end
    if remaining >= 60   then return format("%dm", math_floor(remaining / 60))   end
    if remaining >= 10   then return format("%d",  math_ceil(remaining))         end
    return format("%.1f", remaining)
end

-- Hosts. Ungrouped bars render into the buff-bar viewer's anchor container
-- (preserving the old behaviour and the Positions tab controls); each group
-- gets its own movable container.

local ungroupedHost
local groupContainers = {}

local function GetContainerForAnchorTarget(anchorTarget)
    local anchorContainers = CDM.anchorContainers
    if not anchorContainers then return nil end
    if anchorTarget == "essential" then
        return anchorContainers[CDM_C.VIEWERS.ESSENTIAL]
    end
    if anchorTarget == "buff" then
        return anchorContainers[CDM_C.VIEWERS.BUFF]
    end
    if anchorTarget == "buffBar" then
        return anchorContainers[CDM_C.VIEWERS.BUFF_BAR]
    end
    return nil
end

local barGroupSets = { groups = nil }
CDM.buffBarGroupContainers = groupContainers
CDM.buffBarGroupSets = barGroupSets

local bbDescriptor = GCU and GCU.CreateDescriptor({
    containers = groupContainers,
    namePrefix = "Ayije_CDM_BuffBarGroup",
    callbackPrefix = "CDM_BuffBarGroup_",
    getSets = function() return barGroupSets end,
})

-- The fallback host is only a stand-in for the window before the viewer's
-- anchor container exists. Cache the real container permanently, but never the
-- fallback -- doing so would strand every ungrouped bar on a frame the
-- Positions tab does not drive.
local ungroupedFallbackHost

local function GetUngroupedHost()
    if ungroupedHost then return ungroupedHost end

    local viewer = GetBuffBarViewer()
    if viewer and CDM.GetOrCreateAnchorContainer then
        local container = CDM:GetOrCreateAnchorContainer(viewer)
        if container then
            ungroupedHost = container
            return ungroupedHost
        end
    end

    if not ungroupedFallbackHost then
        ungroupedFallbackHost = _G["Ayije_CDM_BBTHost"]
            or CreateFrame("Frame", "Ayije_CDM_BBTHost", UIParent)
        if not ungroupedFallbackHost:GetPoint() then
            ungroupedFallbackHost:SetSize(200, 20)
            ungroupedFallbackHost:SetPoint("CENTER")
        end
    end
    return ungroupedFallbackHost
end

-- Host for an entry: its group's container, or the ungrouped host.
local function GetHostFor(entry)
    if entry.groupIndex and bbDescriptor then
        return bbDescriptor:GetOrCreateContainer(entry.groupIndex)
    end
    return GetUngroupedHost()
end

-- Our bars

local barFrames = {}          -- index (into entries) -> our bar frame

local function CreateBar(index, parent)
    local wrap = CreateFrame("Frame", nil, parent)

    local sb = CreateFrame("StatusBar", nil, wrap)
    sb:SetAllPoints(wrap)
    wrap._bar = sb

    local bg = sb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(sb)
    wrap._bg = bg

    -- Tick marks sit above the fill and its threshold overlays, but BELOW the
    -- text overlay, so a tick never stripes the stack number. Both clear the
    -- reserved threshold band (see the frame-level plan above).
    local tickHost = CreateFrame("Frame", nil, wrap)
    tickHost:SetAllPoints(sb)
    tickHost:SetFrameLevel(sb:GetFrameLevel() + LEVEL_TICKS)
    wrap._tickHost = tickHost

    local textOverlay = CreateFrame("Frame", nil, wrap)
    textOverlay:SetAllPoints(sb)
    textOverlay:SetFrameLevel(sb:GetFrameLevel() + LEVEL_TEXT)

    local nameText = textOverlay:CreateFontString(nil, "OVERLAY")
    wrap._nameText = nameText

    local timerText = textOverlay:CreateFontString(nil, "OVERLAY")
    wrap._timerText = timerText

    local stackText = textOverlay:CreateFontString(nil, "OVERLAY")
    wrap._stackText = stackText

    -- The icon lives on its own frame so it can carry a border of its own,
    -- matching what ApplyBarStyle did for Blizzard's bars.
    local iconFrame = CreateFrame("Frame", nil, wrap)
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(iconFrame)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    wrap._iconFrame = iconFrame
    wrap._icon = icon

    -- Border hosts. Borders are drawn by CDM.BORDER onto a dedicated frame
    -- laid over the target, exactly as EnsureIconBorder does in Style.lua.
    wrap._barBorderHost = CreateFrame("Frame", nil, wrap)
    wrap._iconBorderHost = CreateFrame("Frame", nil, wrap)

    wrap:Hide()
    barFrames[index] = wrap
    return wrap
end

-- Create/refresh a border on a host frame covering `target`. Mirrors
-- EnsureIconBorder in Style.lua: rebuild only when the border version moves.
-- Empty frameData: ResolveCurrentBorderColor falls through to the configured
-- borderColor, which is what a plain bar wants (no pandemic/override state).
local borderCtx = {}
local function EnsureBorder(bar, hostKey, verKey, target, levelOffset)
    local bh = bar[hostKey]
    if not bh or not BORDER then return end

    if CDM_C.GetConfigValue("borderFile", "1 Pixel") == "None" then
        if bh.border then bh.border:Hide() end
        return
    end

    local version = CDM.borderStyleVersion or 0
    if bar[verKey] ~= version or not bh.border then
        bar[verKey] = version
        BORDER:CreateBorder(bh, { forceUpdate = true })
        local inner = bh.border
        if inner and inner.SetBackdropBorderColor then
            local color = BORDER:ResolveCurrentBorderColor(borderCtx)
            if color then inner:SetBackdropBorderColor(color.r, color.g, color.b, 1) end
        end
    elseif bh.border and not bh.border:IsShown() then
        bh.border:Show()
    end

    bh:ClearAllPoints()
    bh:SetAllPoints(target)
    bh:SetFrameLevel((target:GetFrameLevel() or 0) + (levelOffset or 1))
end

local function ResolveTexture(name)
    return (LSM and LSM:Fetch("statusbar", name or "Solid"))
        or "Interface\\TargetingFrame\\UI-StatusBar"
end

local function EffectiveWidth(cfg)
    local w = cfg.width or 0
    if w == 0 then
        w = (CDM.CalculateEssentialRow1Width and CDM.CalculateEssentialRow1Width()) or 200
    end
    return Snap(w)
end

-- Stack-bar scaffolding, defined below StyleBar (it needs ResolveTexture and
-- the model helpers) but called from inside it.
local BuildStackLayers, BuildTicks, ReleaseStackLayers, ReleaseTicks
local AnchorStackOverlays

-- Style one bar entirely from its own config. `offsetAccum` is how far the
-- run of bars already extends inside this host, and `grow` comes from the
-- owning group (or the bar itself when ungrouped).
local function StyleBar(bar, cfg, offsetAccum, grow, host)
    local h = cfg.height or 20
    local width = EffectiveWidth(cfg)
    local sb = bar._bar

    bar:SetParent(host)
    bar:SetSize(width, h)
    bar:ClearAllPoints()
    if grow == "UP" then
        bar:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, offsetAccum)
    else
        bar:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -offsetAccum)
    end

    -- Anchor the icon FRAME (the texture fills it); the frame is what a border
    -- can be laid over.
    local iconSize = h
    local iconPos = cfg.iconPosition or "LEFT"
    local iconGap = cfg.iconGap or 1
    local icf = bar._iconFrame
    if iconPos == "HIDDEN" then
        icf:Hide()
        sb:ClearAllPoints()
        sb:SetPoint("LEFT", bar, "LEFT", 0, 0)
        sb:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    else
        icf:Show()
        icf:SetSize(iconSize, iconSize)
        icf:ClearAllPoints()
        sb:ClearAllPoints()
        if iconPos == "RIGHT" then
            icf:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
            sb:SetPoint("LEFT", bar, "LEFT", 0, 0)
            sb:SetPoint("RIGHT", icf, "LEFT", -iconGap, 0)
        else
            icf:SetPoint("LEFT", bar, "LEFT", 0, 0)
            sb:SetPoint("LEFT", icf, "RIGHT", iconGap, 0)
            sb:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
        end
    end
    sb:SetHeight(h)

    local texture = ResolveTexture(cfg.texture)
    sb:SetStatusBarTexture(texture)
    local bc = cfg.barColor
    sb:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a or 1)
    bar._bg:SetTexture(texture)
    local bgc = cfg.bgColor
    bar._bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a or 0.8)

    local fontPath = CDM_C.GetBaseFontPath()
    local fontOutline = CDM_C.GetBaseFontOutline()

    local nameText = bar._nameText
    -- Pixel.FontSize pre-multiplies by the UI scale, so the FontString must
    -- ignore its parent's scale or the size is applied twice -- that is what
    -- made the text render smaller than Blizzard's at the same configured size.
    nameText:SetIgnoreParentScale(true)
    nameText:SetFont(fontPath, Pixel.FontSize(cfg.nameFontSize or 15), fontOutline)
    local nc = cfg.nameColor
    nameText:SetTextColor(nc.r, nc.g, nc.b, nc.a or 1)
    nameText:SetShadowOffset(0, 0)
    nameText:SetWordWrap(false)
    nameText:SetJustifyH("LEFT")
    nameText:ClearAllPoints()
    nameText:SetPoint("LEFT", sb, "LEFT", cfg.nameOffsetX or 2, cfg.nameOffsetY or 0)
    nameText:SetPoint("RIGHT", sb, "RIGHT", -30, cfg.nameOffsetY or 0)
    nameText:SetShown(cfg.showName ~= false)

    local durPos = cfg.durationPosition or "RIGHT"
    local timerText = bar._timerText
    timerText:SetIgnoreParentScale(true)
    timerText:SetFont(fontPath, Pixel.FontSize(cfg.durationFontSize or 15), fontOutline)
    local dc = cfg.durationColor
    timerText:SetTextColor(dc.r, dc.g, dc.b, dc.a or 1)
    timerText:SetShadowOffset(0, 0)
    timerText:SetJustifyH(durPos)
    timerText:ClearAllPoints()
    -- CENTER means the centre of the icon+bar unit, so it anchors to the wrap
    -- (which spans both); edge anchors stay on the fill. Matches ApplyBarStyle.
    if durPos == "CENTER" then
        timerText:SetPoint("CENTER", bar, "CENTER", cfg.durationOffsetX or -2, cfg.durationOffsetY or 0)
    else
        timerText:SetPoint(durPos, sb, durPos, cfg.durationOffsetX or -2, cfg.durationOffsetY or 0)
    end

    local stackPos = cfg.applicationsPosition or "CENTER"
    local stackText = bar._stackText
    stackText:SetIgnoreParentScale(true)
    stackText:SetFont(fontPath, Pixel.FontSize(cfg.applicationsFontSize or 15), fontOutline)
    local ac = cfg.applicationsColor
    stackText:SetTextColor(ac.r, ac.g, ac.b, ac.a or 1)
    stackText:SetShadowOffset(0, 0)
    stackText:SetJustifyH(stackPos)
    stackText:ClearAllPoints()
    if stackPos == "CENTER" then
        stackText:SetPoint("CENTER", bar, "CENTER", cfg.applicationsOffsetX or 0, cfg.applicationsOffsetY or 0)
    else
        stackText:SetPoint(stackPos, sb, stackPos, cfg.applicationsOffsetX or 0, cfg.applicationsOffsetY or 0)
    end
    stackText:SetShown(cfg.showApplications ~= false)

    -- Stack scaffolding: the fill range encodes the scale, so the C layer does
    -- count/maxStacks and Lua never divides. A timer bar's range is driven by
    -- the mirrored Blizzard bar instead, so only rebuild here for stack bars.
    if cfg.barType == M.TYPE_STACK then
        -- NormalizeBar guarantees maxStacks >= 1, so the span is never zero.
        sb:SetMinMaxValues(0, cfg.maxStacks)
        sb:SetValue(0)
        BuildStackLayers(bar, cfg)
        BuildTicks(bar, cfg, width, h)
        bar._tickHost:Show()
    else
        ReleaseStackLayers(bar)
        ReleaseTicks(bar)
        bar._tickHost:Hide()
    end

    -- Borders last: they overlay the finished geometry. The bar's own border
    -- sits above the whole threshold-overlay band so a high threshold cannot
    -- paint over it; the icon border has no overlays to clear.
    EnsureBorder(bar, "_barBorderHost", "_barBorderVer", sb, LEVEL_BORDER)
    if iconPos == "HIDDEN" then
        local ibh = bar._iconBorderHost
        if ibh and ibh.border then ibh.border:Hide() end
    else
        EnsureBorder(bar, "_iconBorderHost", "_iconBorderVer", icf, 1)
    end

    return width, h
end

-- Set by BuffBarDecimals.lua: _engBtn / _engFS are the engine's slot button and
-- FontString -- both are forbidden to read after initializeFrame and throw in
-- combat. While _engineOwnsTimer is set, the engine's FS is the visible one and
-- the tick only hides its own.
local function MirrorFill(sb, blizzBar)
    sb:SetMinMaxValues(blizzBar:GetMinMaxValues())
    sb:SetValue(blizzBar:GetValue())
end

-- Stack-bar scaffolding
--
-- A stack bar reuses the base StatusBar as its fill, ranged (0, maxStacks), and
-- stacks threshold recolors on top of it as full-width StatusBars ranged
-- (T-1, T). Behaviour falls out of SetValue alone:
--   count < T-1  -> clamps to min -> 0% wide  -> invisible
--   count >= T   -> clamps to max -> 100% wide -> fully recolored
-- Highest crossed threshold wins purely by DRAW ORDER: overlay i is parented to
-- overlay i-1, and a child always renders above its parent. No `count >= T`
-- comparison ever runs, which is exactly what makes this legal when the count
-- is a secret value.

ReleaseStackLayers = function(bar)
    local layers = bar._thrOverlays
    if not layers then return end
    -- Top-down: overlay i is parented to overlay i-1, so releasing a parent
    -- first would orphan the rest of the chain.
    for i = #layers, 1, -1 do
        local ov = layers[i]
        if ov then
            ov:Hide()
            ov:ClearAllPoints()
            ov:SetParent(nil)
        end
        layers[i] = nil
    end
end

ReleaseTicks = function(bar)
    local ticks = bar._ticks
    if not ticks then return end
    for i = #ticks, 1, -1 do
        local t = ticks[i]
        if t then
            t:Hide()
            t:ClearAllPoints()
            t:SetParent(nil)
        end
        ticks[i] = nil
    end
end

-- Anchoring is the detail that breaks everything if missed: overlays anchor to
-- the base bar's FILL TEXTURE, never to the frame. Anchored to the frame they
-- span the full width, so the bar reads as permanently full the instant the
-- lowest threshold is crossed.
--
-- This must re-run on every rebuild: changing the status bar texture makes
-- GetStatusBarTexture() return a NEW object, and overlays still anchored to the
-- old one silently stop tracking the fill.
AnchorStackOverlays = function(bar)
    local layers = bar._thrOverlays
    if not layers or #layers == 0 then return end
    local sb = bar._bar
    local fillTex = sb and sb:GetStatusBarTexture()
    if not fillTex then return end
    for i = 1, #layers do
        local ov = layers[i]
        if ov then
            ov:ClearAllPoints()
            ov:SetAllPoints(fillTex)
        end
    end
end

BuildStackLayers = function(bar, cfg)
    ReleaseStackLayers(bar)
    bar._thrOverlays = bar._thrOverlays or {}

    local maxStacks = cfg.maxStacks or 0
    if maxStacks < 1 then return end

    local thresholds = M.GetSortedThresholds(cfg)
    local sb = bar._bar
    local baseLevel = sb:GetFrameLevel()
    local parent = sb

    -- Hard cap: the levels above the fill are reserved for the border, ticks
    -- and text, so the chain must not grow past its band.
    local count = math_min(#thresholds, MAX_THRESHOLD_LEVELS)

    for i = 1, count do
        local t = thresholds[i]
        local ov = CreateFrame("StatusBar", nil, parent)
        ov:SetStatusBarTexture(ResolveTexture(cfg.texture))
        -- The (T-1, T) range is what turns "is this threshold crossed" into a
        -- clamp the C layer performs, instead of a Lua comparison.
        ov:SetMinMaxValues(t.stacks - 1, t.stacks)
        ov:SetValue(t.stacks - 1)
        local c = t.color
        if type(c) == "table" then
            ov:SetStatusBarColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1)
        end
        ov:SetFrameLevel(baseLevel + i)
        bar._thrOverlays[i] = ov
        -- Chain: each overlay parents to the previous so draw order ascends
        -- with threshold value.
        parent = ov
    end

    AnchorStackOverlays(bar)
end

BuildTicks = function(bar, cfg, barWidth, barHeight)
    ReleaseTicks(bar)
    bar._ticks = bar._ticks or {}

    local maxStacks = cfg.maxStacks or 0
    local tickWidth = cfg.tickWidth or 1
    if maxStacks < 2 or tickWidth <= 0 then return end

    local values = M.ParseTickValues(cfg.tickValues, maxStacks)
    if #values == 0 then return end

    -- Width of the fill area, not the wrap: the icon and gap sit outside it.
    local fillWidth = barWidth
    local iconPos = cfg.iconPosition or "LEFT"
    if iconPos ~= "HIDDEN" then
        fillWidth = fillWidth - barHeight - (cfg.iconGap or 1)
    end
    if fillWidth <= 0 then return end

    local host = bar._tickHost
    local tc = cfg.tickColor or { r = 0, g = 0, b = 0, a = 1 }

    for i = 1, #values do
        local n = values[i]
        local tex = host:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(tc.r or 0, tc.g or 0, tc.b or 0, tc.a or 1)
        tex:SetSize(tickWidth, barHeight)
        tex:SetPoint("CENTER", host, "LEFT", (n / maxStacks) * fillWidth, 0)
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
        bar._ticks[i] = tex
    end
end

-- Icon / name resolution

local function ResolveIconSpellID(cfg)
    local sid = cfg.spellID
    if C_Spell and C_Spell.GetOverrideSpell and IsUsableSID(sid) then
        local ov = C_Spell.GetOverrideSpell(sid)
        if IsUsableSID(ov) and ov ~= sid then return ov end
    end
    -- Saved the override form, now untalented: the saved form is no longer a
    -- known spell but its captured base is -- show the base form's icon.
    if IsUsableSID(cfg.baseSpellID) and IsUsableSID(sid)
        and not SpellIsKnown(sid) and SpellIsKnown(cfg.baseSpellID) then
        return cfg.baseSpellID
    end
    return sid
end

-- Matches PlayerCastBar's cdmNameMaxChars handling.
local function TruncateName(str, maxChars)
    if not maxChars or maxChars <= 0 or not str then return str end
    if #str <= maxChars then return str end
    return str:sub(1, maxChars) .. "..."
end

local function UpdateIconAndName(bar, cfg, blzChild, blizzBar)
    -- Icon priority: Blizzard's own texture (already override-resolved), then
    -- live aura data (Roll the Bones), then the config's spell. Non-config
    -- writes clear the cached id so the fallback can't skip against it.
    local ic = bar._icon
    if (cfg.iconPosition or "LEFT") ~= "HIDDEN" and ic then
        local wrote = false
        local blizzIcon = blzChild and (blzChild.Icon or (blzChild.Bar and blzChild.Bar.Icon))
        if blizzIcon and blizzIcon.GetTexture then
            local ok, t = pcall(blizzIcon.GetTexture, blizzIcon)
            if ok and t then
                ic:SetTexture(t)
                bar._lastIconSID = nil
                wrote = true
            end
        end
        if not wrote and blzChild and blzChild.auraInstanceID ~= nil and blzChild.auraDataUnit
            and not IsSecret(blzChild.auraInstanceID) then
            local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID,
                blzChild.auraDataUnit, blzChild.auraInstanceID)
            if ok and ad and ad.icon then
                ic:SetTexture(ad.icon)
                bar._lastIconSID = nil
                wrote = true
            end
        end
        if not wrote then
            local sid = ResolveIconSpellID(cfg)
            if sid and bar._lastIconSID ~= sid then
                bar._lastIconSID = sid
                local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
                if t then ic:SetTexture(t) end
            end
        end
    end

    -- Name: aura data first (same source as the icon, so it always matches the
    -- actual buff), then Blizzard's FontString (can be stale after pool
    -- recycling), then the spell info.
    if cfg.showName ~= false and not bar._nameSet then
        local nameStr
        if blzChild and blzChild.auraInstanceID ~= nil and blzChild.auraDataUnit
            and not IsSecret(blzChild.auraInstanceID) then
            local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID,
                blzChild.auraDataUnit, blzChild.auraInstanceID)
            if ok and ad and ad.name then nameStr = ad.name end
        end
        if not nameStr and blizzBar then
            local nameFS = GetBlizzBarFontStrings(blizzBar)
            if nameFS then
                local ok, txt = pcall(nameFS.GetText, nameFS)
                if ok and txt then nameStr = txt end
            end
        end
        if not nameStr and IsUsableSID(cfg.spellID) then
            nameStr = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(cfg.spellID)
        end
        if nameStr then
            bar._nameText:SetText(TruncateName(nameStr, cfg.nameMaxChars))
            bar._nameSet = true
        end
    end
end

-- Stack counts
--
-- In restricted content (combat, M+, PvP) applications is a Secret Value. It
-- may be passed to C functions (SetValue/SetText) and nil-checked, but never
-- compared, truth-tested, concatenated or printed. Everything below is built
-- around that: the count is carried opaquely and only ever handed to a setter.
-- (IsSecret is defined at the top of the file.)

-- SetText with a secret errors on some clients, so fall back to blanking.
-- Returns whether anything was written, so the caller knows to hide the
-- FontString.
--
-- Zero is suppressed: an empty bar already reads as "no stacks". That test is
-- only legal on a clean value -- a secret count is passed through untouched,
-- since comparing it would taint.
local function SetStackText(fontString, value)
    if IsSecret(value) then
        if not pcall(fontString.SetText, fontString, value) then
            fontString:SetText("")
            return false
        end
        return true
    end

    if value == nil or value == 0 then
        fontString:SetText("")
        return false
    end

    fontString:SetText(value)
    return true
end

-- Aura lookup, cost-ordered. Caches the resolved name and the winning filter on
-- the bar frame so steady state is one API call, not three. Both caches are
-- cleared whenever the bar is rebound to a different config.
local FILTERS = { "HELPFUL", "HELPFUL|PLAYER", "HARMFUL", "HARMFUL|PLAYER" }

local function GetAuraData(bar, cfg, blzChild, unit)
    -- 1. The frame already caches the aura table it is displaying: zero API
    --    calls. Absent on some 12.0 builds, hence the nil-check.
    local cached = blzChild and blzChild.auraDataCached
    if cached then return cached end

    -- 2. Direct by spell id, player only.
    if unit == "player" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        if IsUsableSID(cfg.spellID) then
            local ad = C_UnitAuras.GetPlayerAuraBySpellID(cfg.spellID)
            if ad then return ad end
        end
        if IsUsableSID(cfg.baseSpellID) then
            local ad = C_UnitAuras.GetPlayerAuraBySpellID(cfg.baseSpellID)
            if ad then return ad end
        end
    end

    -- 3. By name. Resolve once; `false` memoises a failed lookup so it is not
    --    retried every tick.
    if bar._spellName == nil and IsUsableSID(cfg.spellID) then
        bar._spellName = (C_Spell and C_Spell.GetSpellName
            and C_Spell.GetSpellName(cfg.spellID)) or false
    end
    local name = bar._spellName
    if name and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local winning = bar._spellNameFilter
        if winning then
            local ok, ad = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, winning)
            if ok and ad then return ad end
            bar._spellNameFilter = nil   -- miss: re-scan and re-cache below
        end
        for i = 1, #FILTERS do
            local f = FILTERS[i]
            local ok, ad = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, f)
            if ok and ad then
                bar._spellNameFilter = f
                return ad
            end
        end
    end

    -- 4. Last resort. NEVER feed a secret instance id to this: pcall does not
    --    suppress the taint violation, so guard before the call. The nil test
    --    must be `~= nil` -- a bare `if x then` truth-tests the secret itself,
    --    which taints before IsSecret ever runs.
    if blzChild and blzChild.auraInstanceID ~= nil and not IsSecret(blzChild.auraInstanceID) then
        local u = blzChild.auraDataUnit or unit
        if u then
            local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, u, blzChild.auraInstanceID)
            if ok and ad then return ad end
        end
    end

    return nil
end

-- Three separate returns, deliberately, so no caller ever truth-tests a secret.
--   tracking   (plain bool) -- the aura is up
--   count      (MAY BE SECRET) -- opaque, only ever passed to a setter
--   unreadable (plain bool) -- up, but the count cannot be read
local function ReadStackCount(bar, cfg, blzChild, fbAura, isActive)
    local auraData = fbAura
    if not auraData then
        -- Presence is a nil-check on auraInstanceID only; comparing it taints.
        local present = isActive or (blzChild and blzChild.auraInstanceID ~= nil)
        if not present then return false, nil, false end
        local unit = (blzChild and blzChild.auraDataUnit) or "player"
        auraData = GetAuraData(bar, cfg, blzChild, unit)
    end

    if auraData == nil then
        -- Up, but the count is unknowable.
        if isActive then return true, nil, true end
        return false, nil, false
    end

    local apps = auraData.applications
    -- Blizzard OMITS applications entirely at a single stack. Without this
    -- every one-stack aura would render as an empty bar.
    if apps == nil then return true, 1, false end
    return true, apps, false
end

-- Push one value to the fill and every threshold overlay. The value may be
-- secret; it only ever reaches SetValue.
local function SetAllBarsValue(bar, value)
    bar._bar:SetValue(value)
    local layers = bar._thrOverlays
    if layers then
        for i = 1, #layers do
            layers[i]:SetValue(value)
        end
    end
end

-- Fail-open: aura up but count unreadable. Fill the base completely and keep
-- the overlays dark -- drawing empty would read as "buff expired", a worse lie
-- than "active, count unknown". Max is read back off the widget rather than
-- recomputed.
local function SetAllBarsFull(bar)
    local sb = bar._bar
    local _, hi = sb:GetMinMaxValues()
    sb:SetValue(hi or 0)
    local layers = bar._thrOverlays
    if layers then
        for i = 1, #layers do
            local ov = layers[i]
            local lo = ov:GetMinMaxValues()
            ov:SetValue(lo or 0)
        end
    end
end

-- Stack text on a TIMER bar: shown only when the count is cleanly readable and
-- above 1, matching the old behaviour.
local function UpdateTimerStackText(bar, cfg, blzChild, fbAura)
    local stackText = bar._stackText
    if not stackText or cfg.showApplications == false then
        if stackText then stackText:Hide() end
        return
    end

    local count
    if fbAura then
        local c = fbAura.applications
        if type(c) == "number" and not IsSecret(c) then count = c end
    elseif blzChild and blzChild.auraInstanceID ~= nil and blzChild.auraDataUnit
        and not IsSecret(blzChild.auraInstanceID) then
        local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID,
            blzChild.auraDataUnit, blzChild.auraInstanceID)
        if ok and ad then
            local c = ad.applications
            if type(c) == "number" and not IsSecret(c) then count = c end
        end
    end

    if count and count > 1 then
        stackText:SetText(count)
        stackText:Show()
    else
        stackText:SetText("")
        stackText:Hide()
    end
end

-- Renderers, dispatched on cfg.barType.
--
-- Each returns true when the bar showed something this tick (drives the idle
-- sleeper). `ctx` carries the resolved per-tick state so a renderer never
-- repeats the frame lookup.

local Renderers = {}

Renderers[M.TYPE_TIMER] = function(bar, cfg, ctx)
    local blzChild, blizzBar, fbAura = ctx.blzChild, ctx.blizzBar, ctx.fbAura

    if ctx.isActive then
        if not bar:IsShown() then bar:Show() end
        local sb = bar._bar

        if blizzBar then
            -- Secret values pass through the setters; never read or compare
            -- them in Lua.
            pcall(MirrorFill, sb, blizzBar)
            -- Fill colour is StyleBar's (cfg.barColor); mirroring Blizzard's
            -- here would overwrite it every tick.
        end

        pcall(UpdateIconAndName, bar, cfg, blzChild, blizzBar)
        pcall(UpdateTimerStackText, bar, cfg, blzChild, nil)

        -- Engine-owned when decimals are bound; otherwise a verbatim
        -- passthrough of Blizzard's FontString.
        if cfg.showDuration ~= false then
            if bar._engineOwnsTimer then
                bar._timerText:Hide()
            else
                local _, timerFS = GetBlizzBarFontStrings(blizzBar)
                if timerFS then
                    local ok, txt = pcall(timerFS.GetText, timerFS)
                    if ok then bar._timerText:SetText(txt) end
                end
                bar._timerText:Show()
            end
        else
            bar._timerText:Hide()
        end
        return true
    end

    if fbAura then
        -- Self-driven: only safe while the numbers are clean.
        if not bar:IsShown() then bar:Show() end
        local sb = bar._bar
        local dur, exp = fbAura.duration, fbAura.expirationTime
        local secret = (issecretvalue and (issecretvalue(dur) or issecretvalue(exp)))
        if not secret and type(dur) == "number" and type(exp) == "number"
            and dur > 0 and exp > 0 then
            local remaining = exp - GetTime()
            if remaining < 0 then remaining = 0 end
            sb:SetMinMaxValues(0, dur)
            sb:SetValue(remaining)
            if cfg.showDuration ~= false and not bar._engineOwnsTimer then
                bar._timerText:SetText(FormatTime(remaining))
                bar._timerText:Show()
            end
        else
            -- Secret or infinite: full bar, no countdown.
            sb:SetMinMaxValues(0, 1)
            sb:SetValue(1)
            if cfg.showDuration ~= false then bar._timerText:SetText("") end
        end
        UpdateIconAndName(bar, cfg, blzChild, blizzBar)
        UpdateTimerStackText(bar, cfg, blzChild, fbAura)
        return true
    end

    return false
end

-- STACK BAR
--
-- Fill is stacks-out-of-max, driven entirely in the C layer: the StatusBar is
-- ranged (0, maxStacks) at style time and SetValue(count) does the division.
-- Lua never divides, never compares the count, and never truth-tests it -- that
-- is what keeps this correct when the count is a secret value.
--
-- Three branches, all keyed on PLAIN booleans returned by ReadStackCount:
--   not tracking -> empty bar, literal "0"
--   unreadable   -> full bar, blank text (fail-open, see SetAllBarsFull)
--   readable     -> SetValue(count), SetStackText(count)
Renderers[M.TYPE_STACK] = function(bar, cfg, ctx)
    local blzChild, fbAura = ctx.blzChild, ctx.fbAura

    local tracking, count, unreadable =
        ReadStackCount(bar, cfg, blzChild, fbAura, ctx.isActive)

    local showText = cfg.showApplications ~= false
    local stackText = bar._stackText

    -- The timer FontString has no role on a stack bar.
    bar._timerText:Hide()

    if not tracking then
        -- Aura is down. With alwaysShow the bar stays up as an empty track so
        -- it holds its slot in the layout; without it the bar hides entirely
        -- and the Tick's caller collapses the gap.
        if cfg.alwaysShow == false then
            if bar:IsShown() then
                bar:Hide()
                bar._nameSet = nil
            end
            return false, true
        end

        SetAllBarsValue(bar, 0)
        -- No count at zero stacks: an empty bar already says "none", and a
        -- literal "0" just adds noise.
        stackText:SetText("")
        stackText:Hide()
        if not bar:IsShown() then bar:Show() end
        -- Not active (the sleeper may retire the ticker) but visibility is
        -- ours: the shared hide must not pull this empty bar down.
        return false, true
    end

    if not bar:IsShown() then bar:Show() end

    if unreadable then
        SetAllBarsFull(bar)
        -- Fail-open: full bar, no number. Nothing to show either way.
        stackText:SetText("")
        stackText:Hide()
    else
        SetAllBarsValue(bar, count)
        if showText then
            -- SetStackText suppresses a clean zero, so honour its answer
            -- rather than showing an empty FontString.
            stackText:SetShown(SetStackText(stackText, count))
        else
            stackText:Hide()
        end
    end

    pcall(UpdateIconAndName, bar, cfg, blzChild, ctx.blizzBar)
    return true
end

-- Preview
--
-- While a config window is open every configured bar is drawn, whether or not
-- its aura is up, so positions and sizes can actually be judged. This only
-- touches our frames; Blizzard's CooldownViewer data is never modified.

local previewConfigActive = false

-- IsShown(), never IsVisible(): IsVisible() also reports the parent chain, so
-- a cutscene hiding UIParent would flip the preview off and on again.
local function IsPreviewActive()
    local panel = _G.CooldownViewerSettings
    if panel and panel:IsShown() then return true end

    local configFrame = _G.Ayije_CDMConfigFrame
    if configFrame then return configFrame:IsShown() end

    return previewConfigActive
end
CDM.IsBuffBarPreviewActive = IsPreviewActive

-- Draw a bar as it would look with no aura on it: full fill for a timer bar,
-- empty for a stack bar (which is what zero stacks looks like in play).
local function RenderPreview(bar, cfg)
    if not bar:IsShown() then bar:Show() end
    bar._timerText:Hide()

    if cfg.barType == M.TYPE_STACK then
        SetAllBarsValue(bar, 0)
        bar._stackText:SetText("")
        bar._stackText:Hide()
    else
        local sb = bar._bar
        sb:SetMinMaxValues(0, 1)
        sb:SetValue(1)
        if cfg.showDuration ~= false and not bar._engineOwnsTimer then
            bar._timerText:SetText("--")
            bar._timerText:Show()
        end
        bar._stackText:SetText("")
        bar._stackText:Hide()
    end

    -- Name and icon come from the config, since there is no live aura to read.
    if cfg.showName ~= false and not bar._nameSet then
        local nameStr = cfg.name
            or (IsUsableSID(cfg.spellID) and C_Spell and C_Spell.GetSpellName
                and C_Spell.GetSpellName(cfg.spellID))
        if nameStr then
            bar._nameText:SetText(TruncateName(nameStr, cfg.nameMaxChars))
            bar._nameSet = true
        end
    end
    if (cfg.iconPosition or "LEFT") ~= "HIDDEN" and bar._icon then
        local sid = ResolveIconSpellID(cfg)
        if sid and bar._lastIconSID ~= sid then
            bar._lastIconSID = sid
            local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
            if t then bar._icon:SetTexture(t) end
        end
    end
end

-- The tick

local ticker
local accum = 0
local idleTicks = 0
local IDLE_LIMIT = 30

local function Wake()
    if ticker and not ticker:IsShown() then
        idleTicks = 0
        ticker:Show()
    end
end
CDM.BuffBarTimers_Wake = Wake

local tickCtx = {}

local function Tick()
    local entries = GetEntries()
    if #entries == 0 then return false end

    local cfgList = BuildCfgList()
    local map = AssignFramesToConfigs(cfgList)
    local live = false
    -- Resolved once per tick, not per bar: it walks global frame lookups.
    local previewing = IsPreviewActive()

    for i = 1, #entries do
        local cfg = entries[i].bar
        local bar = barFrames[i]
        if bar then
            local blzChild = map[cfg]

            -- IsActive(), not IsShown(): items stay shown while inactive unless
            -- Blizzard's "Hide When Inactive" is on. pcall'd -- an unprotected
            -- read throws under the 12.1 combat restriction and kills the tick.
            local isActive = false
            if blzChild then
                if blzChild.IsActive then
                    local ok, a = pcall(blzChild.IsActive, blzChild)
                    if ok then isActive = a and true or false end
                elseif blzChild.IsShown then
                    local ok, s = pcall(blzChild.IsShown, blzChild)
                    if ok then isActive = s and true or false end
                end
            end

            -- The viewer can fail to bind a fresh aura, and some spells have no
            -- CDM presence at all. Known-ID query, never a scan.
            local fbAura
            if not isActive and IsUsableSID(cfg.spellID)
                and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                fbAura = C_UnitAuras.GetPlayerAuraBySpellID(cfg.spellID)
                if not fbAura and IsUsableSID(cfg.baseSpellID) then
                    fbAura = C_UnitAuras.GetPlayerAuraBySpellID(cfg.baseSpellID)
                end
                -- Keep the memo dirty while a fallback is live so the next tick
                -- re-pairs the moment the real frame appears.
                if fbAura then assignDirty = true end
            end

            tickCtx.blzChild = blzChild
            tickCtx.blizzBar = blzChild and blzChild.Bar
            tickCtx.isActive = isActive
            tickCtx.fbAura = fbAura

            -- Preview: with a config window open, a bar whose aura is not up is
            -- drawn anyway so it can be positioned. A live aura still renders
            -- normally, so the preview never masks real state.
            if previewing and not isActive and not fbAura then
                RenderPreview(bar, cfg)
                live = true
            else
                -- Two distinct answers: `active` drives the idle sleeper,
                -- `owned` means the renderer has already decided this bar's
                -- visibility and the shared hide below must keep its hands off
                -- (a stack bar with Always Show On stays up while it is down).
                local render = Renderers[cfg.barType] or Renderers[M.TYPE_TIMER]
                local active, owned = render(bar, cfg, tickCtx)

                if active then
                    live = true
                elseif not owned and bar:IsShown() then
                    bar:Hide()
                    bar._nameSet = nil
                end
            end
        end
    end

    return live
end

-- Rebuild

local function UpdateGroupContainers()
    if not bbDescriptor then return end
    local groups = M.GetGroups()
    barGroupSets.groups = groups

    local active = {}
    for groupIndex, groupData in ipairs(groups) do
        local container = bbDescriptor:GetOrCreateContainer(groupIndex)
        bbDescriptor:UpdateContainerPosition(groupIndex, groupData, GetContainerForAnchorTarget)
        local at = groupData.anchorTarget or "screen"
        if not container:IsShown() and at ~= "essential" and at ~= "buff"
            and at ~= "buffBar" and at ~= "playerFrame" then
            container:Show()
        end
        active[groupIndex] = true
    end

    for idx, container in pairs(groupContainers) do
        if not active[idx] then container:Hide() end
    end

    bbDescriptor:SyncCallbacks(GetContainerForAnchorTarget)
end

-- Bumped on every rebuild so a deferred callback from a superseded rebuild
-- can detect that it is stale and bail.
local rebuildToken = 0

-- Per-host layout accumulators, reused across rebuilds.
local hostOffset = {}   -- where the NEXT bar starts (includes trailing spacing)
local hostExtent = {}   -- where the run of bars actually ends
local hostWidth = {}

local function Rebuild()
    InvalidateEntries()
    local entries = GetEntries()

    UpdateGroupContainers()

    table_wipe(hostOffset)
    table_wipe(hostExtent)
    table_wipe(hostWidth)

    for i = 1, #entries do
        local entry = entries[i]
        local cfg = entry.bar
        local host = GetHostFor(entry)
        local bar = barFrames[i] or CreateBar(i, host)
        bar._nameSet = nil
        bar._lastIconSID = nil

        -- Frames are pooled by position, so slot i can be handed a DIFFERENT
        -- bar than last rebuild. Any engine timer binding still on it belongs
        -- to the old bar and would write that spell's time here; drop it and
        -- let BuffBarDecimals_Sync rebind below. The FontStrings are cleared
        -- after StyleBar, which is what gives them a font.
        -- Identity check covers a frame being handed a different bar; the
        -- spellID check covers the SAME bar being retargeted at a new spell,
        -- which leaves the table identity unchanged.
        local rebound = bar._boundCfg ~= cfg or bar._boundSID ~= cfg.spellID
        if rebound then
            bar._boundCfg = cfg
            bar._boundSID = cfg.spellID
            bar._engBtn, bar._engFS = nil, nil
            bar._engineOwnsTimer = nil
            -- Drop the aura lookup caches: keeping them would resolve the OLD
            -- spell's name and silently track the wrong aura.
            bar._spellName = nil
            bar._spellNameFilter = nil
        end

        -- Grow/spacing are placement, so they belong to whatever owns the run:
        -- the group when grouped, and the shared buff-bar globals for the
        -- ungrouped stack. Individual bars never carry them.
        local group = entry.group
        local grow, spacing
        if group then
            grow = group.grow or "DOWN"
            spacing = Snap(group.spacing or 1)
        else
            grow = CDM_C.GetConfigValue("buffBarGrowDirection", "DOWN")
            spacing = Snap(CDM_C.GetConfigValue("buffBarSpacing", 1))
        end

        local offset = hostOffset[host] or 0
        local width, h = StyleBar(bar, cfg, offset, grow, host)

        -- Safe only now: StyleBar has assigned the fonts, and SetText on an
        -- unfonted FontString throws.
        if rebound then
            bar._timerText:SetText("")
            bar._timerText:SetAlpha(1)
            bar._stackText:SetText("")
        end

        -- Track the run's true extent separately from the next bar's start, so
        -- the trailing gap never inflates the host.
        hostOffset[host] = offset + h + spacing
        hostExtent[host] = offset + h
        hostWidth[host] = math_max(hostWidth[host] or 0, width)
    end

    for i = #entries + 1, #barFrames do
        local bar = barFrames[i]
        if bar then
            bar:Hide()
            bar._engBtn, bar._engFS = nil, nil
            bar._engineOwnsTimer = nil
            -- Clear the pairing too: if this slot is reused later the identity
            -- check above must see it as a fresh binding.
            bar._boundCfg = nil
            bar._boundSID = nil
        end
    end

    -- Size each host to the run of bars it actually holds. The trailing
    -- spacing added by the loop is not part of the visible stack.
    for host, extent in pairs(hostExtent) do
        if host.SetSize then
            local w = hostWidth[host] or 200
            host:SetSize(w, math_max(1, extent))
        end
    end

    CDM.InvalidateBuffBarTimerFrames()
    if CDM.BuffBarDecimals_Sync then CDM.BuffBarDecimals_Sync() end

    -- Deferred re-anchor for stack overlays and ticks. Widget geometry is not
    -- resolved until after layout: GetStatusBarTexture() and GetWidth() both
    -- return stale values synchronously after a rebuild, so the overlays would
    -- stay pinned to the previous fill texture and the ticks land at the wrong
    -- offsets. `rebuildToken` makes a stale callback from a superseded rebuild
    -- a no-op.
    rebuildToken = rebuildToken + 1
    local token = rebuildToken
    C_Timer.After(0, function()
        if token ~= rebuildToken then return end
        local live = GetEntries()
        for i = 1, #live do
            local cfg = live[i].bar
            local bar = barFrames[i]
            if bar and cfg.barType == M.TYPE_STACK then
                AnchorStackOverlays(bar)
                BuildTicks(bar, cfg, bar:GetWidth(), cfg.height or 20)
            end
        end
    end)

    Wake()
end

CDM.BuffBarTimers_GetBar = function(i) return barFrames[i] end
CDM.BuffBarTimers_Rebuild = Rebuild

-- Driver: 60Hz behind an accumulator, with an idle sleeper.

local function EnsureTicker()
    if ticker then return ticker end
    ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(self, elapsed)
        accum = accum + elapsed
        if accum < 0.016 then return end
        accum = 0
        -- Backstop: an unhandled error inside Tick would otherwise propagate
        -- out of OnUpdate every frame. Treat a failed tick as "not live" so
        -- the sleeper still retires it instead of erroring forever.
        local ok, live = pcall(Tick)
        if not ok then live = false end
        if live then
            idleTicks = 0
        else
            idleTicks = idleTicks + 1
            if idleTicks > IDLE_LIMIT then
                self:Hide()
            end
        end
    end)
    return ticker
end

-- Reconcile / hooks

function CDM.ReconcileBuffBarTimers()
    if select(4, GetBuildInfo()) < MIN_BUILD then return end
    EnsureTicker()
    Rebuild()
end

function CDM.OnBuffBarTimersProfileApplied()
    if select(4, GetBuildInfo()) < MIN_BUILD then return end
    CDM.ReconcileBuffBarTimers()
end

CDM:RegisterRefreshCallback("buffBarTimers", function()
    CDM.ReconcileBuffBarTimers()
end, 55, { "BUFF_DATA", "LAYOUT", "STYLE", "CONSTANTS" })

-- Composition edges: retire the assignment memo and wake the sleeper.
CDM:RegisterEvent("UNIT_AURA", function(_, unit)
    if unit ~= "player" then return end
    assignDirty = true
    Wake()
end)

CDM:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit)
    if unit ~= "player" then return end
    Wake()
end)

CDM:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    Wake()
end)

-- Preview edges.
--
-- Closing the config must clear each bar's preview render, or a bar whose aura
-- is down would keep its "--" and full fill until something else redrew it.
-- The tick already hides such bars on its next pass, so a Wake is enough --
-- but _nameSet is cleared here so a real aura re-reads its own name rather
-- than inheriting the config-supplied one.
local function OnPreviewEdge()
    for i = 1, #barFrames do
        local bar = barFrames[i]
        if bar then
            bar._nameSet = nil
            bar._lastIconSID = nil
        end
    end
    Wake()
end

-- SetConfigWindowActive early-returns when the state is unchanged, and
-- hooksecurefunc only fires on a completed call, so this is a hint to
-- re-evaluate rather than the source of truth -- IsPreviewActive reads the
-- live frame state instead.
-- Defined in BuffGroupOverlays.lua, which loads earlier; guarded so a load
-- order change degrades to "no hint" rather than erroring at parse time.
if CDM.SetConfigWindowActive then
    hooksecurefunc(CDM, "SetConfigWindowActive", function(_, active)
        previewConfigActive = active and true or false
        OnPreviewEdge()
    end)
end

do
    local registry = EventRegistry
    if registry and registry.RegisterCallback then
        local owner = {}
        registry:RegisterCallback("CooldownViewerSettings.OnShow", OnPreviewEdge, owner)
        registry:RegisterCallback("CooldownViewerSettings.OnHide", OnPreviewEdge, owner)
    end
end
