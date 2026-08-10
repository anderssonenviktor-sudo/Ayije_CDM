local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]

local CDM_C = CDM and CDM.CONST or {}

local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue
local math_floor = math.floor

-- Engine-driven decimal duration text for the mirrored buff bars. Blizzard's
-- own string is whole seconds, and in combat the remaining time is secret, so
-- Lua cannot format it. Instead each opted-in bar gets an aura-container slot
-- whose SetDurationText formatter is evaluated engine-side against the secret
-- duration -- identical in and out of combat.
--
-- A FontString registered with SetDurationText must be a DESCENDANT of the slot
-- button, and after initializeFrame that button and its descendants are
-- forbidden to read. So the engine's FontString is the VISIBLE one, anchored
-- over the bar inside initializeFrame; nothing is ever copied back out.
--
-- Nothing exists until a bar enables decimals; containers rebuild only when the
-- slot set or text style changes.

if select(4, GetBuildInfo()) < 120100 then return end

-- One formatter per distinct threshold. The breakpoint shape is load-bearing:
-- step/rounding live at the breakpoint level, components carry only the divisor
-- -- off-shape tables are silently rejected. Unit boundaries sit just above the
-- edge (59.0001) so an UP-rounded value in (59, 60] never reads "60".

local formatterByThr = {}

local function ClampThr(v)
    v = tonumber(v) or 5
    if v < 3 then v = 3 elseif v > 120 then v = 120 end
    return math_floor(v + 0.5)
end

local function GetDecimalFormatter(thr)
    thr = ClampThr(thr)
    local cached = formatterByThr[thr]
    if cached ~= nil then
        return cached or nil          -- false sentinel: rejected, don't retry
    end
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum and Enum.NumericRuleFormatRounding) then
        formatterByThr[thr] = false
        return nil
    end

    local Nearest = Enum.NumericRuleFormatRounding.Nearest
    local Up = Enum.NumericRuleFormatRounding.Up
    local f = C_StringUtil.CreateNumericRuleFormatter()

    local points = {
        { threshold = 0, format = "%.1f", rounding = Nearest },
    }
    if thr <= 59 then
        points[#points + 1] = { threshold = thr, format = "%d", rounding = Up, step = 1 }
        points[#points + 1] = { threshold = 59.0001, format = "%d:%02d", rounding = Up, step = 1,
            components = { { div = 60 }, { mod = 60 } } }
    else
        -- Threshold past the minute edge: tenths run right up to it, then hand
        -- off straight to m:ss (no whole-second band).
        points[#points + 1] = { threshold = thr + 0.0001, format = "%d:%02d", rounding = Up, step = 1,
            components = { { div = 60 }, { mod = 60 } } }
    end
    points[#points + 1] = { threshold = 3599.0001, format = "%dh", rounding = Up, step = 1,
        components = { { div = 3600 } } }
    points[#points + 1] = { threshold = 86399.0001, format = "%dd", rounding = Up, step = 1,
        components = { { div = 86400 } } }

    if not pcall(f.SetBreakpoints, f, points) then
        formatterByThr[thr] = false
        return nil
    end
    formatterByThr[thr] = f
    return f
end

-- The 0.05s interval is required or the tenths never move.
local function BuildDurationTextOpts(formatter)
    if C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
        local binding = C_DurationUtil.CreateDurationTextBinding()
        if formatter then binding:SetFormatter(formatter) end
        binding:SetUpdateInterval(0.05)
        return { binding = binding }
    end
    return { textFormatter = formatter }
end

local function SetDurationTextSafe(button, fs, opts)
    if pcall(button.SetDurationText, button, fs, opts) then return true end
    if pcall(button.SetDurationText, button, fs, {}) then return true end
    return false
end

-- Spell id variant expansion

local function IsUsableSID(id)
    if type(id) ~= "number" then return false end
    if issecretvalue and issecretvalue(id) then return false end
    return id > 0 and id == math_floor(id)
end

local function AddVariants(include, sid)
    if not IsUsableSID(sid) then return end
    include[sid] = true
    if C_Spell then
        if C_Spell.GetOverrideSpell then
            local o = C_Spell.GetOverrideSpell(sid)
            if IsUsableSID(o) then include[o] = true end
        end
        if C_Spell.GetBaseSpell then
            local b = C_Spell.GetBaseSpell(sid)
            if IsUsableSID(b) then include[b] = true end
        end
    end
end

-- Enrich from a live frame's cooldownInfo. The aura that actually appears
-- often carries an id that exists ONLY in linkedSpellIDs.
local function AddFrameIDs(include, frame, claimed, owner)
    if not frame then return end
    local info = frame.cooldownInfo
    if not info and frame.cooldownID and C_CooldownViewer
        and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, ci = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, frame.cooldownID)
        if ok then info = ci end
    end
    if type(info) ~= "table" then return end

    local function Try(id)
        if not IsUsableSID(id) then return end
        -- Skip ids claimed by another bar: spell families share one
        -- cooldownInfo, and the engine would bind the aura to either slot.
        if claimed[id] ~= nil and claimed[id] ~= owner then return end
        claimed[id] = owner
        include[id] = true
    end

    Try(info.spellID)
    Try(info.overrideSpellID)
    Try(info.overrideTooltipSpellID)
    if info.linkedSpellIDs then
        for i = 1, #info.linkedSpellIDs do Try(info.linkedSpellIDs[i]) end
    end
end

-- Container lifecycle

local host, container, signature
local boundButton = {}        -- bar index -> slot button
local boundThr = {}           -- bar index -> threshold currently bound
-- Every slot button we ever bound on the LIVE container. There is no API to
-- destroy a container or its slots, so these are hidden by hand on release --
-- otherwise their engine FontStrings linger with the old font and anchor.
local retiredButtons = {}
local pendingRegen = false
local regenFrame

local function ReleaseContainer()
    for i in pairs(boundButton) do
        local bar = CDM.BuffBarTimers_GetBar and CDM.BuffBarTimers_GetBar(i)
        if bar then
            bar._engBtn, bar._engFS = nil, nil
            -- Back to the tick's whole-second passthrough.
            bar._engineOwnsTimer = nil
            if bar._timerText then
                bar._timerText:SetAlpha(1)
                bar._timerText:Show()
            end
        end
    end
    wipe(boundButton)
    wipe(boundThr)
    if container then
        -- There is no API to destroy a container or drop its slots, and a
        -- hidden container's buttons keep their regions alive -- a stale engine
        -- FontString would linger with the old font/anchor. Hide the buttons we
        -- made and detach the unit so the engine stops driving it.
        for _, button in pairs(retiredButtons) do
            pcall(button.Hide, button)
        end
        wipe(retiredButtons)
        if container.SetUnit then pcall(container.SetUnit, container, nil) end
        pcall(container.Hide, container)
        pcall(container.ClearAllPoints, container)
        container = nil
    end
    signature = nil
end

-- Collect the desired slot set. Two passes over the bars: pass 1 claims each
-- bar's OWN saved identity, pass 2 adds cooldownInfo enrichment but skips ids
-- already claimed by a different bar.
local function CollectDesired()
    local bars = CDM.GetBuffBarTimerBars()
    if #bars == 0 then return nil, "" end

    local map = CDM.AssignBuffBarTimerFrames and CDM.AssignBuffBarTimerFrames(bars)
    local claimed = {}
    local desired = {}

    -- Pass 1: saved identity.
    for i = 1, #bars do
        local cfg = bars[i]
        if cfg.timerDecimals ~= false and IsUsableSID(cfg.spellID) then
            local include = {}
            AddVariants(include, cfg.spellID)
            AddVariants(include, cfg.baseSpellID)
            for id in pairs(include) do claimed[id] = i end
            desired[#desired + 1] = {
                index = i,
                include = include,
                thr = ClampThr(CDM_C.GetConfigValue("buffBarDecimalThreshold", 5)),
            }
        end
    end
    if #desired == 0 then return nil, "" end

    -- Pass 2: cooldownInfo enrichment, respecting claims.
    for k = 1, #desired do
        local want = desired[k]
        local cfg = bars[want.index]
        local frame = map and map[cfg]
        if frame then AddFrameIDs(want.include, frame, claimed, want.index) end
    end

    -- Threshold is excluded (it re-registers in place on the live button), but
    -- the text style is included: the engine FS can only be styled inside
    -- initializeFrame, so a font/position change must force a rebuild.
    local parts = {}
    for k = 1, #desired do
        local want = desired[k]
        local ids = {}
        for id in pairs(want.include) do ids[#ids + 1] = id end
        table.sort(ids)
        parts[#parts + 1] = want.index .. "=" .. table.concat(ids, ",")
    end

    local G = CDM_C.GetConfigValue
    local styleSig = table.concat({
        G("buffBarDurationFontSize", 12),
        G("buffBarDurationPosition", "RIGHT"),
        G("buffBarDurationOffsetX", -4),
        G("buffBarDurationOffsetY", 0),
        G("buffBarHeight", 20),
        G("buffBarWidth", 0),
        G("buffBarIconPosition", "LEFT"),
        tostring(CDM_C.GetBaseFontPath()),
        tostring(CDM_C.GetBaseFontOutline()),
        tostring(G("buffBarShowDuration", true)),
    }, "|")

    return desired, table.concat(parts, ";") .. "#" .. styleSig
end

-- The button IS the timer text: anchored over the bar inside initializeFrame
-- (the only legal window), with the engine writing its FontString C-side. The
-- bar's own timer FS is hidden while a binding is live.
local function BuildContainer(desired)
    if not host then
        host = _G["Ayije_CDM_BBDecHost"]
        if not host then
            host = CreateFrame("Frame", "Ayije_CDM_BBDecHost", UIParent)
            host:EnableMouse(false)
        end
    end
    -- The host must be SHOWN and have a renderable rect: the engine parses
    -- auras from a run-when-visible OnUpdate. It is a plain container, so
    -- showing it costs nothing visually -- the buttons carry the pixels.
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    host:SetSize(1, 1)
    host:SetAlpha(1)
    host:Show()

    container = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
    container:SetSize(1, 1)
    container:ClearAllPoints()
    -- A point is REQUIRED: an unanchored container has no renderable rect -- it
    -- builds, binds slots, then silently never processes a single aura.
    container:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)

    local filter = AuraUtil.CreateFilterString(AuraUtil.AuraFilters.Helpful)

    for k = 1, #desired do
        local want = desired[k]
        local index, thr = want.index, want.thr

        local function initializeFrame(button)
            if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
            local fmt = GetDecimalFormatter(thr)
            if not fmt then return end
            local bar = CDM.BuffBarTimers_GetBar and CDM.BuffBarTimers_GetBar(index)
            local out = bar and bar._timerText
            if not out then return end

            -- Cover the fill, then anchor the FontString inside it where the
            -- config asks. Legal only here, before the button is forbidden; it
            -- stays parented to the container (re-parenting is forbidden).
            local sb = bar._bar or bar
            button:ClearAllPoints()
            -- Corner anchors, not SetSize from GetWidth(): the StatusBar is
            -- anchored LEFT/RIGHT, so GetWidth() is stale during a rebuild and
            -- the button came out the wrong width.
            button:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
            button:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
            if button.SetFrameStrata then button:SetFrameStrata("HIGH") end

            local fs = button:CreateFontString(nil, "OVERLAY")
            -- Style before registering, from the config directly -- this is the
            -- only window in which the engine FS can be styled at all.
            local G = CDM_C.GetConfigValue
            local durPos = G("buffBarDurationPosition", "RIGHT")
            local durOX  = G("buffBarDurationOffsetX", -4)
            local durOY  = G("buffBarDurationOffsetY", 0)
            local col    = G("buffBarDurationColor", { r = 1, g = 1, b = 1, a = 1 })
            fs:SetFont(CDM_C.GetBaseFontPath(),
                CDM.Pixel.FontSize(G("buffBarDurationFontSize", 12)),
                CDM_C.GetBaseFontOutline())
            fs:SetTextColor(col.r, col.g, col.b, col.a or 1)
            fs:SetJustifyH(durPos)
            fs:ClearAllPoints()
            if durPos == "CENTER" then
                fs:SetPoint("CENTER", button, "CENTER", durOX, durOY)
            else
                fs:SetPoint(durPos, button, durPos, durOX, durOY)
            end

            retiredButtons[#retiredButtons + 1] = button
            if SetDurationTextSafe(button, fs, BuildDurationTextOpts(fmt)) then
                boundButton[index] = button
                boundThr[index] = thr
                bar._engBtn = button
                bar._engFS = fs
                -- The engine now owns this bar's timer display. Hide ours so
                -- the two can never render on top of each other.
                out:SetText("")
                bar._engineOwnsTimer = true
            end
        end

        container:AddAuraSlot("acdmDec" .. index, filter, {
            candidateFilters = { includeSpellIDs = want.include },
            initializeFrame = initializeFrame,
        })
    end

    -- Unit LAST: SetUnit re-evaluates event registrations, and UNIT_AURA
    -- registration is gated on the container already having slots.
    container:SetUnit("player")
    if container.UpdateAllAuras then container:UpdateAllAuras() end
end

function CDM.BuffBarDecimals_Sync()
    local desired, sig = CollectDesired()

    if not desired then
        if container then ReleaseContainer() end
        return
    end

    if container and sig == signature then
        -- Same slot set: re-register any binding whose threshold slider moved.
        -- A fresh SetDurationText on the live button swaps the formatter in
        -- place, so no container swap is needed.
        for k = 1, #desired do
            local want = desired[k]
            local button = boundButton[want.index]
            local bar = CDM.BuffBarTimers_GetBar and CDM.BuffBarTimers_GetBar(want.index)
            if button and bar then
                bar._engBtn = button
                if bar._engFS and boundThr[want.index] ~= want.thr then
                    local fmt = GetDecimalFormatter(want.thr)
                    if fmt and SetDurationTextSafe(button, bar._engFS, BuildDurationTextOpts(fmt)) then
                        boundThr[want.index] = want.thr
                    end
                end
            end
        end
        return
    end

    -- Slot set changed. Old bindings would keep writing the OLD spell's time
    -- onto re-purposed bar indexes, so tear down FIRST (bars fall back to the
    -- accurate whole-second passthrough for the gap), then build.
    ReleaseContainer()

    -- Container creation is combat-illegal: defer the build, not the teardown.
    if InCombatLockdown() then
        pendingRegen = true
        if not regenFrame then
            regenFrame = CreateFrame("Frame")
            regenFrame:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if pendingRegen then
                    pendingRegen = false
                    CDM.BuffBarDecimals_Sync()
                end
            end)
        end
        regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    pendingRegen = false

    BuildContainer(desired)
    if container then
        container:Show()
        signature = sig
    end
end

CDM:RegisterCombatStateHandler(function(isInCombat)
    if isInCombat then return end
    if pendingRegen then
        pendingRegen = false
        CDM.BuffBarDecimals_Sync()
    end
end)
