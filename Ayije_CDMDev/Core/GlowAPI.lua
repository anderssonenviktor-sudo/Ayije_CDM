local AddonName = "Ayije_CDMDev"
local CDM = _G[AddonName]

local LCG = LibStub("LibCustomGlow-1.0", true)
local Renderers = CDM.GlowRenderers
local GetFrameData = CDM.GetFrameData
local max = math.max
local KEY = "CDM_Shared"

local function Equal(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for key, value in pairs(a) do
        if not Equal(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

CDM.GLOW_CAPABILITIES = {}
for _, style in ipairs({ "pixel", "autocast", "button", "proc", "gcd", "shape" }) do
    CDM.GLOW_CAPABILITIES[style] = {
        color = true, alpha = true, scale = true, offset = true, speed = true,
    }
end

local function Resize(host)
    local width, height = host.owner:GetSize()
    local scale = host.options.scale
    host:SetSize(width * scale, height * scale)
end

local function StopRenderer(host)
    local style = host.style
    host.style = nil
    if style == "pixel" then
        LCG.PixelGlow_Stop(host, KEY)
    elseif style == "autocast" then
        LCG.AutoCastGlow_Stop(host, KEY)
    elseif style == "button" then
        local button = host._ButtonGlow
        if button then
            button.animIn:Stop()
            button.animOut:Stop()
            LCG.ButtonGlowPool:Release(button)
        end
    elseif style == "proc" then
        local proc = host["_ProcGlow" .. KEY]
        if proc then
            proc.ProcStartAnim:Stop()
            proc.ProcLoopAnim:Stop()
        end
        LCG.ProcGlow_Stop(host, KEY)
    elseif style then
        Renderers.Stop(host)
    end
end

function CDM.StopGlow(icon, reason)
    local hosts = GetFrameData(icon).sharedGlowHosts
    local host = hosts and hosts[reason or "default"]
    if not host then return end
    StopRenderer(host)
    host:Hide()
    host.options = nil
end

-- Each reason owns a container; changing a trigger's appearance cannot stop another glow.
function CDM.StartGlow(icon, style, options)
    if not LCG then return end
    local data = GetFrameData(icon)
    local hosts = data.sharedGlowHosts
    if not hosts then hosts = {}; data.sharedGlowHosts = hosts end
    local reason = options.reason or "default"
    local host = hosts[reason]
    if not host then
        host = CreateFrame("Frame", nil, icon)
        host:Hide()
        host:EnableMouse(false)
        host.owner = icon
        hosts[reason] = host
        icon:HookScript("OnSizeChanged", function()
            if host.options then Resize(host) end
        end)
    end
    if host.style == style and Equal(host.options, options) then return end
    StopRenderer(host)
    host.options = options
    host:ClearAllPoints()
    host:SetPoint("CENTER", icon, "CENTER", options.offsetX, options.offsetY)
    Resize(host)
    local level = icon:GetFrameLevel()
    if options.layer == "background" then level = max(0, level - 2)
    elseif options.layer == "overlay" then level = level + 20
    else level = level + 2 end
    host:SetFrameLevel(level)
    host:SetAlpha(options.alpha)
    host:Show()
    local color
    if options.r then
        host.color = host.color or {}
        color = host.color
        color[1], color[2], color[3], color[4] = options.r, options.g, options.b, 1
    end
    local speed, specific = options.speedMultiplier, options.styleOptions
    if style == "pixel" then
        LCG.PixelGlow_Start(host, color, specific.lines, 0.2 * speed, nil,
            specific.thickness, 0, 0, specific.background, KEY, 0)
        local pixel = host["_PixelGlow" .. KEY]
        if pixel and pixel.bg then
            local bg = specific.backgroundColor
            pixel.bg:SetColorTexture(bg.r, bg.g, bg.b, 0.8)
        end
    elseif style == "autocast" then
        LCG.AutoCastGlow_Start(host, color, specific.sparkCount, 0.2 * speed, 1, 0, 0, KEY, 0)
    elseif style == "button" then
        LCG.ButtonGlow_Start(host, color, 0.25 * speed, 0)
    elseif style == "proc" then
        LCG.ProcGlow_Start(host, { color = color, startAnim = false, duration = 1 / speed,
            xOffset = 0, yOffset = 0, key = KEY, frameLevel = 0 })
    elseif style == "gcd" then
        Renderers.StartFlipBook(host, level, style, color, options)
    elseif style == "shape" then
        Renderers.StartShape(host, level, color, { speedMultiplier = speed,
            pulseMultiplier = options.alpha * specific.intensity })
    end
    host.style = style
    if style == "shape" then host:SetAlpha(1) end
end
