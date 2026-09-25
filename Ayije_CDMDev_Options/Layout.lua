local Runtime = _G["Ayije_CDMDev"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local L = Runtime.L

local function CreateLayoutTab(page)
    local content = CreateFrame("Frame", nil, page)
    content:SetAllPoints(page)
    content:Hide()
    ns._CreateCooldownGroupsPanel(content, page)
    content:Show()
end

API:RegisterConfigTab("layout", L["Cooldowns"], CreateLayoutTab, 2)
