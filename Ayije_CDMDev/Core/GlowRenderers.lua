local AddonName = "Ayije_CDMDev"
local CDM = _G[AddonName]

local GetFrameData = CDM.GetFrameData
local sin = math.sin
local pairs = pairs
local next = next

local Renderers = {}
CDM.GlowRenderers = Renderers

local FLIPBOOK_STYLES = {
    gcd = {
        atlas = "RotationHelper_Ants_Flipbook",
        texPadding = 1.6, rows = 6, columns = 5, frames = 30, duration = 1.0,
    },
}

local SQUARE_GLOW = "Interface\\AddOns\\Ayije_CDMDev\\Media\\Textures\\SquareGlow.tga"
local activeShapes = {}
local pulseDriver = CreateFrame("Frame")
pulseDriver:Hide()
pulseDriver:SetScript("OnUpdate", function(_, elapsed)
    for wrapper in pairs(activeShapes) do
        local speed = wrapper.speedMultiplier or 1
        local alpha = wrapper.pulseMultiplier or 1
        wrapper.timer = (wrapper.timer + elapsed * 10 * speed) % 6.2832
        wrapper.brightTimer = (wrapper.brightTimer + elapsed * 5 * speed) % 6.2832
        wrapper.glow:SetAlpha(math.min(1, (0.25 + 0.25 * (0.5 + 0.5 * sin(wrapper.timer))) * alpha))
        if wrapper.bright then
            wrapper.bright:SetAlpha(math.min(1, (0.35 + 0.10 * (0.5 + 0.5 * sin(wrapper.brightTimer))) * alpha))
        end
    end
end)

local function StopAnimations(wrapper)
    if wrapper.primary then
        wrapper.primary.group:Stop()
        wrapper.secondary.group:Stop()
    end
    activeShapes[wrapper] = nil
    if not next(activeShapes) then pulseDriver:Hide() end
end

local function PlayAnimations(wrapper)
    if FLIPBOOK_STYLES[wrapper.style] then
        wrapper.primary.group:Play()
        wrapper.secondary.group:Play()
    elseif wrapper.style == "shape" then
        activeShapes[wrapper] = true
        pulseDriver:Show()
    end
end

local function Resize(wrapper)
    local width, height = wrapper:GetSize()
    local style = FLIPBOOK_STYLES[wrapper.style]
    if style then
        wrapper.primary.texture:SetSize(width * style.texPadding, height * style.texPadding)
        wrapper.secondary.texture:SetSize(width * style.texPadding, height * style.texPadding)
    elseif wrapper.style == "shape" then
        wrapper.glow:SetSize(width * 1.2, height * 1.2)
    end
end

local function GetWrapper(owner, frameLevel)
    local data = GetFrameData(owner)
    local wrapper = data.cdmNativeGlow
    if not wrapper then
        wrapper = CreateFrame("Frame", nil, owner)
        wrapper:Hide()
        wrapper:SetAllPoints(owner)
        wrapper:EnableMouse(false)
        wrapper:SetScript("OnSizeChanged", Resize)
        wrapper:SetScript("OnHide", StopAnimations)
        wrapper:SetScript("OnShow", PlayAnimations)
        data.cdmNativeGlow = wrapper
    end
    wrapper:SetFrameLevel(frameLevel)
    return wrapper
end

function Renderers.Stop(owner)
    local wrapper = GetFrameData(owner).cdmNativeGlow
    if not wrapper then return end
    StopAnimations(wrapper)
    if wrapper.primary then
        wrapper.primary.texture:Hide()
        wrapper.secondary.texture:Hide()
    end
    if wrapper.glow then wrapper.glow:Hide() end
    if wrapper.bright then wrapper.bright:Hide() end
    wrapper.style = nil
    wrapper.speedMultiplier, wrapper.pulseMultiplier = nil, nil
    wrapper:Hide()
end

local function CreateFlipBookLayer(wrapper)
    local texture = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
    texture:SetPoint("CENTER", wrapper, "CENTER")
    local group = texture:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    return { texture = texture, group = group, animation = group:CreateAnimation("FlipBook") }
end

local function ConfigureFlipBook(layer, style, speed)
    layer.group:Stop()
    layer.texture:SetAtlas(style.atlas)
    local anim = layer.animation
    anim:SetFlipBookRows(style.rows)
    anim:SetFlipBookColumns(style.columns)
    anim:SetFlipBookFrames(style.frames)
    anim:SetDuration(style.duration / (speed or 1))
    anim:SetFlipBookFrameWidth(0)
    anim:SetFlipBookFrameHeight(0)
    layer.texture:Show()
end

function Renderers.StartFlipBook(owner, frameLevel, styleID, color, options)
    Renderers.Stop(owner)
    local wrapper = GetWrapper(owner, frameLevel)
    if not wrapper.primary then
        wrapper.primary = CreateFlipBookLayer(wrapper)
        wrapper.secondary = CreateFlipBookLayer(wrapper)
    end
    wrapper.style = styleID
    local style = FLIPBOOK_STYLES[styleID]
    ConfigureFlipBook(wrapper.primary, style, options and options.speedMultiplier)
    ConfigureFlipBook(wrapper.secondary, style, options and options.speedMultiplier)
    local texture = wrapper.primary.texture
    texture:SetDesaturated(color ~= nil)
    texture:SetVertexColor(color and color[1] or 1, color and color[2] or 1, color and color[3] or 1)
    texture:SetAlpha(1)
    local ants = wrapper.secondary.texture
    ants:SetBlendMode("ADD")
    ants:SetDesaturated(color ~= nil)
    ants:SetVertexColor(color and color[1] or 1, color and color[2] or 1, color and color[3] or 1)
    ants:SetAlpha(0.35)
    Resize(wrapper)
    wrapper:Show()
end

function Renderers.StartShape(owner, frameLevel, color, opts)
    Renderers.Stop(owner)
    local wrapper = GetWrapper(owner, frameLevel)
    if not wrapper.glow then
        wrapper.glow = wrapper:CreateTexture(nil, "OVERLAY", nil, 5)
        wrapper.glow:SetPoint("CENTER", wrapper, "CENTER")
        wrapper.glow:SetBlendMode("ADD")
    end
    local glow = wrapper.glow
    if wrapper.shapeMask then
        glow:RemoveMaskTexture(wrapper.shapeMask)
        wrapper.shapeMask = nil
    end
    glow:SetTexture(opts and opts.maskPath or SQUARE_GLOW, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    if opts and opts.shapeMask then
        glow:AddMaskTexture(opts.shapeMask)
        wrapper.shapeMask = opts.shapeMask
    end
    local r, g, b = 0.95, 0.95, 0.32
    if color then r, g, b = color[1], color[2], color[3] end
    glow:SetVertexColor(r, g, b, 1)
    glow:SetAlpha(math.min(1, 0.375 * (opts and opts.pulseMultiplier or 1)))
    glow:Show()
    if opts and opts.borderPath then
        if not wrapper.bright then
            wrapper.bright = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
            wrapper.bright:SetAllPoints(wrapper)
            wrapper.bright:SetBlendMode("ADD")
        end
        wrapper.bright:SetTexture(opts.borderPath)
        wrapper.bright:SetVertexColor(r, g, b, 1)
        wrapper.bright:SetAlpha(math.min(1, 0.5 * (opts and opts.pulseMultiplier or 1)))
        wrapper.bright:Show()
    end
    wrapper.style = "shape"
    wrapper.speedMultiplier = opts and opts.speedMultiplier or 1
    wrapper.pulseMultiplier = opts and opts.pulseMultiplier or 1
    wrapper.timer, wrapper.brightTimer = 0, 0
    Resize(wrapper)
    wrapper:Show()
end
