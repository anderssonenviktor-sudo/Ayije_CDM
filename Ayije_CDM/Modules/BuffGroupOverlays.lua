local AddonName = "Ayije_CDM"
local CDM = _G[AddonName]

local configWindowActive = false

-- The config lifecycle still drives layout previews, but the legacy colored
-- group rectangles were removed in favor of Anchor Mode's unified overlay.
function CDM:SetConfigWindowActive(active)
    active = active and true or false
    if configWindowActive == active then return end
    configWindowActive = active
    self:Refresh("LAYOUT")
end

function CDM:SetAnchorModeActive(active)
    self.anchorModeActive = active and true or false
    self:UpdateContainerDragOverlays()
end
