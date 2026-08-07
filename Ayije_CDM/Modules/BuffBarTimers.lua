local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]

local CDM_C = CDM and CDM.CONST or {}
local VIEWERS = CDM_C.VIEWERS
local BORDER = CDM.BORDER

local LSM = LibStub("LibSharedMedia-3.0")
local Pixel = CDM.Pixel
local Snap = Pixel.Snap

local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue
local GetTime = GetTime
local math_floor = math.floor
local math_ceil = math.ceil
local math_max = math.max
local format = string.format

-- Own tracking bars that MIRROR Blizzard's BuffBarCooldownViewer frames rather
-- than computing aura state: secret values pass through widget setters natively,
-- so the fill survives combat. Blizzard's own bar frames expose no engine hook
-- (no SetDurationText/SetDurationBar/Cooldown), which is why we render our own.
-- Decimals come from BuffBarDecimals.lua.

local MIN_BUILD = 120100

-- CDM.db.buffBarTimers[specID] = { bars = { { spellID, ... }, ... } }

local BAR_DEFAULTS = {
    timerDecimalThreshold = 5,
}
CDM.BUFF_BAR_TIMER_BAR_DEFAULTS = BAR_DEFAULTS

local EMPTY_BARS = {}

local function GetSpecID()
    return (CDM.GetCurrentSpecID and CDM:GetCurrentSpecID()) or nil
end

function CDM.GetBuffBarTimerBars(specID)
    specID = specID or GetSpecID()
    local db = CDM.db
    local root = specID and db and db.buffBarTimers
    local specTbl = root and root[specID]
    return (specTbl and specTbl.bars) or EMPTY_BARS
end

function CDM.EnsureBuffBarTimerBars(specID)
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

local function BarThreshold(cfg)
    local v = cfg and cfg.timerDecimalThreshold
    if v ~= nil then return v end
    return BAR_DEFAULTS.timerDecimalThreshold
end

-- Secret-safe id helpers

local function IsUsableSID(id)
    if type(id) ~= "number" then return false end
    if issecretvalue and issecretvalue(id) then return false end
    return id > 0 and id == math_floor(id)
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

local function MatchesSID(info, sid)
    if not info or not sid then return false end
    if info.overrideSpellID == sid then return true end
    if info.spellID == sid then return true end
    local linked = info.linkedSpellIDs
    if linked then
        for i = 1, #linked do
            if linked[i] == sid then return true end
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

    if cfg.spellID and cfg.spellID > 0 and not cfg.baseSpellID
        and info.overrideSpellID == cfg.spellID
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

function CDM.InvalidateBuffBarTimerFrames()
    wipe(stickyFrame)
    assignDirty = true
end

local function FrameStillActive(frames, target)
    for i = 1, #frames do
        if frames[i] == target then return true end
    end
    return false
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

-- Which Blizzard frames our own bars currently mirror. Layout.lua excludes
-- these from Blizzard's own row so the buff is not drawn twice. Alpha is
-- restored for any frame that stops being mirrored.
local mirroredFrames = setmetatable({}, { __mode = "k" })
local prevMirrored = setmetatable({}, { __mode = "k" })

function CDM.GetBuffBarTimerMirroredFrames()
    local bars = CDM.GetBuffBarTimerBars()
    wipe(mirroredFrames)
    if #bars > 0 then
        local map = AssignFramesToConfigs(bars)
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
-- Consumed by the Options "Add a tracked buff..." dropdown.

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

-- Style

local Cfg = CDM_C.GetConfigValue

local style = {}

local function ReadStyle()
    style.height      = Cfg("buffBarHeight", 20)
    style.spacing     = Cfg("buffBarSpacing", 2)
    style.grow        = Cfg("buffBarGrowDirection", "DOWN")
    style.iconPos     = Cfg("buffBarIconPosition", "LEFT")
    style.iconGap     = Cfg("buffBarIconGap", 2)
    style.textureName = Cfg("buffBarTexture", "Solid")
    style.barColor    = Cfg("buffBarColor", { r = 0.4, g = 0.6, b = 0.9, a = 1 })
    style.bgColor     = Cfg("buffBarBackgroundColor", { r = 0.1, g = 0.1, b = 0.1, a = 0.8 })
    style.showName    = Cfg("buffBarShowName", true)
    style.nameSize    = Cfg("buffBarNameFontSize", 12)
    style.nameColor   = Cfg("buffBarNameColor", { r = 1, g = 1, b = 1, a = 1 })
    style.nameOX      = Cfg("buffBarNameOffsetX", 4)
    style.nameOY      = Cfg("buffBarNameOffsetY", 0)
    style.showDur     = Cfg("buffBarShowDuration", true)
    style.durSize     = Cfg("buffBarDurationFontSize", 12)
    style.durColor    = Cfg("buffBarDurationColor", { r = 1, g = 1, b = 1, a = 1 })
    style.durPos      = Cfg("buffBarDurationPosition", "RIGHT")
    style.durOX       = Cfg("buffBarDurationOffsetX", -4)
    style.durOY       = Cfg("buffBarDurationOffsetY", 0)
    style.width       = Cfg("buffBarWidth", 0)
    style.fontPath    = CDM_C.GetBaseFontPath()
    style.fontOutline = CDM_C.GetBaseFontOutline()
    style.texture     = (LSM and LSM:Fetch("statusbar", style.textureName))
                        or "Interface\\TargetingFrame\\UI-StatusBar"
    return style
end

local function EffectiveWidth()
    local w = style.width
    if w == 0 then
        w = (CDM.CalculateEssentialRow1Width and CDM.CalculateEssentialRow1Width()) or 200
    end
    return Snap(w)
end

-- Our bars

local host
local barFrames = {}          -- index -> our bar frame
local anyDecimals = false     -- feature gate, recomputed on rebuild

local function GetHost()
    if host then return host end
    local viewer = GetBuffBarViewer()
    if viewer and CDM.GetOrCreateAnchorContainer then
        host = CDM:GetOrCreateAnchorContainer(viewer)
    end
    if not host then
        host = _G["Ayije_CDM_BBTHost"]
            or CreateFrame("Frame", "Ayije_CDM_BBTHost", UIParent)
        if not host:GetPoint() then
            host:SetSize(200, 20)
            host:SetPoint("CENTER")
        end
    end
    return host
end

local function CreateBar(index)
    local parent = GetHost()
    local wrap = CreateFrame("Frame", nil, parent)

    local sb = CreateFrame("StatusBar", nil, wrap)
    sb:SetAllPoints(wrap)
    wrap._bar = sb

    local bg = sb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(sb)
    wrap._bg = bg

    local textOverlay = CreateFrame("Frame", nil, wrap)
    textOverlay:SetAllPoints(sb)
    textOverlay:SetFrameLevel(sb:GetFrameLevel() + 7)

    local nameText = textOverlay:CreateFontString(nil, "OVERLAY")
    wrap._nameText = nameText

    local timerText = textOverlay:CreateFontString(nil, "OVERLAY")
    wrap._timerText = timerText

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
local function EnsureBorder(bar, hostKey, verKey, target)
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
    bh:SetFrameLevel((target:GetFrameLevel() or 0) + 1)
end

local function StyleBar(bar, index, width)
    local h = style.height
    local sb = bar._bar

    bar:SetSize(width, h)
    bar:ClearAllPoints()
    local offset = index * (h + Snap(style.spacing))
    local p = GetHost()
    if style.grow == "DOWN" then
        bar:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -offset)
    else
        bar:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, offset)
    end

    -- Anchor the icon FRAME (the texture fills it); the frame is what a border
    -- can be laid over.
    local iconSize = h
    local icf = bar._iconFrame
    if style.iconPos == "HIDDEN" then
        icf:Hide()
        sb:ClearAllPoints()
        sb:SetPoint("LEFT", bar, "LEFT", 0, 0)
        sb:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    else
        icf:Show()
        icf:SetSize(iconSize, iconSize)
        icf:ClearAllPoints()
        sb:ClearAllPoints()
        if style.iconPos == "RIGHT" then
            icf:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
            sb:SetPoint("LEFT", bar, "LEFT", 0, 0)
            sb:SetPoint("RIGHT", icf, "LEFT", -style.iconGap, 0)
        else
            icf:SetPoint("LEFT", bar, "LEFT", 0, 0)
            sb:SetPoint("LEFT", icf, "RIGHT", style.iconGap, 0)
            sb:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
        end
    end
    sb:SetHeight(h)

    sb:SetStatusBarTexture(style.texture)
    local bc = style.barColor
    sb:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a or 1)
    bar._bg:SetTexture(style.texture)
    local bgc = style.bgColor
    bar._bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a or 0.8)

    local nameText = bar._nameText
    nameText:SetFont(style.fontPath, Pixel.FontSize(style.nameSize), style.fontOutline)
    nameText:SetTextColor(style.nameColor.r, style.nameColor.g, style.nameColor.b, style.nameColor.a or 1)
    nameText:SetShadowOffset(0, 0)
    nameText:SetWordWrap(false)
    nameText:SetJustifyH("LEFT")
    nameText:ClearAllPoints()
    nameText:SetPoint("LEFT", sb, "LEFT", style.nameOX, style.nameOY)
    nameText:SetPoint("RIGHT", sb, "RIGHT", -30, style.nameOY)
    nameText:SetShown(style.showName)

    local timerText = bar._timerText
    timerText:SetFont(style.fontPath, Pixel.FontSize(style.durSize), style.fontOutline)
    timerText:SetTextColor(style.durColor.r, style.durColor.g, style.durColor.b, style.durColor.a or 1)
    timerText:SetShadowOffset(0, 0)
    timerText:SetJustifyH(style.durPos)
    timerText:ClearAllPoints()
    if style.durPos == "CENTER" then
        timerText:SetPoint("CENTER", sb, "CENTER", style.durOX, style.durOY)
    else
        timerText:SetPoint(style.durPos, sb, style.durPos, style.durOX, style.durOY)
    end

    -- Borders last: they overlay the finished geometry.
    EnsureBorder(bar, "_barBorderHost", "_barBorderVer", sb)
    if style.iconPos == "HIDDEN" then
        local ibh = bar._iconBorderHost
        if ibh and ibh.border then ibh.border:Hide() end
    else
        EnsureBorder(bar, "_iconBorderHost", "_iconBorderVer", icf)
    end
end

-- Set by BuffBarDecimals.lua: _engBtn / _engFS are the engine's slot button and
-- FontString -- both are forbidden to read after initializeFrame and throw in
-- combat. While _engineOwnsTimer is set, the engine's FS is the visible one and
-- the tick only hides its own.
local function MirrorFill(sb, blizzBar)
    sb:SetMinMaxValues(blizzBar:GetMinMaxValues())
    sb:SetValue(blizzBar:GetValue())
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

local function UpdateIconAndName(bar, cfg, blzChild, blizzBar)
    -- Icon priority: Blizzard's own texture (already override-resolved), then
    -- live aura data (Roll the Bones), then the config's spell. Non-config
    -- writes clear the cached id so the fallback can't skip against it.
    local ic = bar._icon
    if style.iconPos ~= "HIDDEN" and ic then
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
        if not wrote and blzChild and blzChild.auraInstanceID and blzChild.auraDataUnit
            and not (issecretvalue and issecretvalue(blzChild.auraInstanceID)) then
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
    if style.showName and not bar._nameSet then
        local nameStr
        if blzChild and blzChild.auraInstanceID and blzChild.auraDataUnit
            and not (issecretvalue and issecretvalue(blzChild.auraInstanceID)) then
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
            bar._nameText:SetText(nameStr)
            bar._nameSet = true
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

local function Tick()
    local bars = CDM.GetBuffBarTimerBars()
    if #bars == 0 then return false end

    local map = AssignFramesToConfigs(bars)
    local live = false

    for i = 1, #bars do
        local cfg = bars[i]
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

            if isActive or fbAura then live = true end

            local blizzBar = blzChild and blzChild.Bar

            if isActive then
                if not bar:IsShown() then bar:Show() end
                local sb = bar._bar

                if blizzBar then
                    -- Secret values pass through the setters; never read or
                    -- compare them in Lua.
                    pcall(MirrorFill, sb, blizzBar)

                    -- Fill colour is StyleBar's (buffBarColor); mirroring
                    -- Blizzard's here would overwrite it every tick.
                end

                pcall(UpdateIconAndName, bar, cfg, blzChild, blizzBar)

                -- Engine-owned when decimals are bound; otherwise a verbatim
                -- passthrough of Blizzard's FontString.
                if style.showDur then
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

            elseif fbAura then
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
                    if style.showDur and not bar._engineOwnsTimer then
                        bar._timerText:SetText(FormatTime(remaining))
                        bar._timerText:Show()
                    end
                else
                    -- Secret or infinite: full bar, no countdown.
                    sb:SetMinMaxValues(0, 1)
                    sb:SetValue(1)
                    if style.showDur then bar._timerText:SetText("") end
                end
                UpdateIconAndName(bar, cfg, blzChild, blizzBar)

            else
                if bar:IsShown() then
                    bar:Hide()
                    bar._nameSet = nil
                end
            end
        end
    end

    return live
end

-- Rebuild

local function Rebuild()
    ReadStyle()
    local bars = CDM.GetBuffBarTimerBars()
    local width = EffectiveWidth()

    -- Feature gate: recompute once here so the tick costs one boolean read.
    anyDecimals = false
    for i = 1, #bars do
        if bars[i].timerDecimals ~= false then anyDecimals = true break end
    end

    for i = 1, #bars do
        local bar = barFrames[i] or CreateBar(i)
        bar._nameSet = nil
        bar._lastIconSID = nil
        StyleBar(bar, i - 1, width)
    end
    for i = #bars + 1, #barFrames do
        local bar = barFrames[i]
        if bar then
            bar:Hide()
            bar._engBtn, bar._engFS = nil, nil
            bar._engineOwnsTimer = nil
        end
    end

    local h = style.height
    local sp = Snap(style.spacing)
    local p = GetHost()
    if p and p.SetSize and #bars > 0 then
        p:SetSize(width, math_max(h, #bars * h + math_max(0, #bars - 1) * sp))
    end

    CDM.InvalidateBuffBarTimerFrames()
    if CDM.BuffBarDecimals_Sync then CDM.BuffBarDecimals_Sync() end
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
