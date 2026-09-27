local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]
local ns, L, C = CDM._OptionsNS, CDM.L, CDM.CONST
local M = CDM.BUFFBAR
local LSM = LibStub("LibSharedMedia-3.0")
local GetSpellTexture = C_Spell.GetSpellTexture
local GetSpellName = C_Spell.GetSpellName

function ns.CreateBuffBarPreview(parent)
    local preview = CreateFrame("Frame", nil, parent)
    preview:SetSize(280, 108)
    local titleIcon = CreateFrame("Frame", nil, preview)
    titleIcon:SetSize(26, 26)
    titleIcon:SetPoint("TOPLEFT", 0, 0)
    local titleTexture = titleIcon:CreateTexture(nil, "ARTWORK")
    titleTexture:SetAllPoints()
    local title = preview:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font18")
    title:SetPoint("TOPLEFT", titleIcon, "TOPRIGHT", 8, 0)
    title:SetPoint("BOTTOMRIGHT", preview, "TOPRIGHT", -4, -26)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetTextColor(C.GOLD.r, C.GOLD.g, C.GOLD.b, 1)

    local wrap = CreateFrame("Frame", nil, preview)
    wrap:SetPoint("CENTER", preview, "TOP", 0, -64)
    local icon = wrap:CreateTexture(nil, "ARTWORK")
    local fill = CreateFrame("StatusBar", nil, wrap)
    local background = fill:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    local barBorder = CreateFrame("Frame", nil, wrap)
    local iconBorder = CreateFrame("Frame", nil, wrap)
    local textHost = CreateFrame("Frame", nil, fill)
    textHost:SetAllPoints()
    textHost:SetFrameLevel(fill:GetFrameLevel() + 1)
    local name = textHost:CreateFontString(nil, "OVERLAY")
    local duration = textHost:CreateFontString(nil, "OVERLAY")
    local stacks = textHost:CreateFontString(nil, "OVERLAY")
    local ticks, thresholds = {}, {}
    local bar
    local progress = 60

    local function UpdateSample()
        if not bar then return end
        local isStack = bar.barType == M.TYPE_STACK
        local count = isStack and math.floor(progress * bar.maxStacks / 100 + 0.5) or 3
        local remaining = progress * 12 / 100
        wrap:SetShown(not isStack or bar.alwaysShow ~= false or count > 0)
        fill:SetMinMaxValues(0, isStack and bar.maxStacks or 12)
        fill:SetValue(isStack and count or remaining)
        local color = bar.barColor
        if isStack then
            for _, threshold in ipairs(thresholds) do
                if count >= threshold.stacks then color = threshold.color or color end
            end
        end
        fill:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
        stacks:SetText(tostring(count))
        duration:SetText(bar.timerDecimals ~= false and remaining < bar.decimalThreshold
            and string.format("%.1f", remaining) or tostring(math.ceil(remaining)))
    end

    local function StyleText(text, size, color, point, x, y)
        text:SetFont(C.GetBaseFontPath(), size, C.GetBaseFontOutline())
        text:SetTextColor(color.r, color.g, color.b, color.a or 1)
        text:SetShadowOffset(0, 0)
        text:SetWordWrap(false)
        text:ClearAllPoints()
        text:SetPoint(point, point == "CENTER" and wrap or fill, point, x, y)
    end

    local function StyleBorder(host, target, shown)
        host:SetShown(shown)
        if not shown or not CDM.BORDER then return end
        host:ClearAllPoints()
        host:SetAllPoints(target)
        host:SetFrameLevel(fill:GetFrameLevel() + 2)
        CDM.BORDER:CreateBorder(host, { forceUpdate = true })
        if CDM.BORDER.activeBorders then CDM.BORDER.activeBorders[host] = nil end
    end

    function preview:Refresh()
        if not bar then return end
        local width = bar.width
        if width == 0 then
            width = (CDM.CalculateEssentialRow1Width and CDM.CalculateEssentialRow1Width()) or 200
        end
        width = math.max(60, width)
        local height = bar.height
        local scale = math.min(1, math.max(60, self:GetWidth() - 20) / width)
        wrap:SetScale(scale)
        wrap:SetSize(width, height)
        icon:SetTexture((bar.spellID and GetSpellTexture(bar.spellID)) or 134400)
        C.ApplyIconTexCoord(icon, C.GetEffectiveZoomAmount())
        icon:SetSize(height, height)
        icon:ClearAllPoints()
        fill:ClearAllPoints()
        icon:SetShown(bar.iconPosition ~= "HIDDEN")
        local fillWidth = width
        if bar.iconPosition == "HIDDEN" then
            fill:SetPoint("LEFT", wrap)
        elseif bar.iconPosition == "RIGHT" then
            icon:SetPoint("RIGHT", wrap)
            fill:SetPoint("LEFT", wrap)
            fillWidth = width - height - bar.iconGap
        else
            icon:SetPoint("LEFT", wrap)
            fill:SetPoint("LEFT", icon, "RIGHT", bar.iconGap, 0)
            fillWidth = width - height - bar.iconGap
        end
        fill:SetSize(math.max(1, fillWidth), height)
        StyleBorder(barBorder, fill, bar.hideBorder ~= true)
        StyleBorder(iconBorder, icon, bar.hideBorder ~= true and bar.iconPosition ~= "HIDDEN")
        local texture = LSM:Fetch("statusbar", bar.texture) or C.TEX_WHITE8X8
        fill:SetStatusBarTexture(texture)
        background:SetTexture(texture)
        local bg = bar.bgColor
        background:SetVertexColor(bg.r, bg.g, bg.b, bg.a or 1)
        StyleText(name, bar.nameFontSize, bar.nameColor, "LEFT", bar.nameOffsetX, bar.nameOffsetY)
        name:SetPoint("RIGHT", fill, "RIGHT", -30, bar.nameOffsetY)
        name:SetJustifyH("LEFT")
        local label = bar.name or (bar.spellID and GetSpellName(bar.spellID)) or L["Unknown"]
        title:SetText(label)
        titleIcon:ClearAllPoints()
        titleIcon:SetPoint("TOPLEFT", math.max(0, (self:GetWidth() - 34 - title:GetStringWidth()) / 2), 0)
        titleTexture:SetTexture((bar.spellID and GetSpellTexture(bar.spellID)) or 134400)
        C.ApplyIconTexCoord(titleTexture, C.GetEffectiveZoomAmount())
        if bar.nameMaxChars > 0 and #label > bar.nameMaxChars then
            label = label:sub(1, bar.nameMaxChars) .. "..."
        end
        name:SetText(label)
        name:SetShown(bar.showName ~= false)
        StyleText(duration, bar.durationFontSize, bar.durationColor, bar.durationPosition,
            bar.durationOffsetX, bar.durationOffsetY)
        duration:SetShown(bar.barType ~= M.TYPE_STACK and bar.showDuration ~= false)
        StyleText(stacks, bar.applicationsFontSize, bar.applicationsColor, bar.applicationsPosition,
            bar.applicationsOffsetX, bar.applicationsOffsetY)
        stacks:SetShown(bar.showApplications ~= false)
        for _, tick in ipairs(ticks) do tick:Hide() end
        wipe(thresholds)
        if bar.barType == M.TYPE_STACK then
            for _, threshold in ipairs(M.GetSortedThresholds(bar)) do thresholds[#thresholds + 1] = threshold end
            if bar.tickWidth > 0 and bar.maxStacks > 1 then
                for index, value in ipairs(M.ParseTickValues(bar.tickValues, bar.maxStacks)) do
                    local tick = ticks[index] or textHost:CreateTexture(nil, "ARTWORK")
                    ticks[index] = tick
                    local color = bar.tickColor
                    tick:SetColorTexture(color.r, color.g, color.b, color.a or 1)
                    tick:SetSize(bar.tickWidth, height)
                    tick:ClearAllPoints()
                    tick:SetPoint("CENTER", fill, "LEFT", value / bar.maxStacks * fillWidth, 0)
                    tick:Show()
                end
            end
        end
        UpdateSample()
    end

    function preview:SetBar(value)
        bar = value
        self:Refresh()
    end
    preview:SetScript("OnSizeChanged", function(self) self:Refresh() end)
    preview:Hide()
    return preview
end
