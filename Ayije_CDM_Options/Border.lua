local Runtime = _G["Ayije_CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local UI = ns.ConfigUI
local L = Runtime.L

local OUTLINE_OPTIONS = {
    { value = "",             label = L["None"] },
    { value = "OUTLINE",      label = L["Outline"] },
    { value = "THICKOUTLINE", label = L["Thick Outline"] },
    { value = "SLUG",         label = L["Slug"] },
}

local function OutlineLabel(value)
    return UI.GetOptionLabel(OUTLINE_OPTIONS, value, L["Outline"])
end

local function FontDropdown(rc, yOff, page)
    local lbl = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    lbl:SetText(L["Font"])
    lbl:SetPoint("TOPLEFT", 0, yOff)

    local dd = CreateFrame("DropdownButton", nil, rc, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
    dd:SetWidth(220)
    dd:SetDefaultText(CDM.db.textFont or CDM.defaults.textFont or "Expressway")
    UI.SetupMediaDropdown(dd, "font",
        function() return CDM.db.textFont end,
        function(name) CDM.db.textFont = name; API:Refresh("STYLE") end,
        function(name) dd:SetDefaultText(name) end)
    page.fontDropdown = dd
end

local function OutlineDropdown(rc, yOff, page)
    local lbl = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    lbl:SetText(L["Font Outline"])
    lbl:SetPoint("TOPLEFT", 0, yOff)

    local dd = CreateFrame("DropdownButton", nil, rc, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
    dd:SetWidth(220)
    dd:SetDefaultText(OutlineLabel(CDM.db.textFontOutline))
    UI.SetupValueDropdown(dd, OUTLINE_OPTIONS,
        function() return CDM.db.textFontOutline end,
        function(value, label)
            CDM.db.textFontOutline = value
            dd:SetDefaultText(label)
            API:Refresh("STYLE")
        end)
    page.outlineDropdown = dd
end

local function BuildBorders(subPage, page)
    local content = CreateFrame("Frame", nil, subPage)
    content:SetPoint("TOPLEFT", 35, -40)
    content:SetPoint("BOTTOMRIGHT", -20, 10)

    local left = CreateFrame("Frame", nil, content)
    left:SetPoint("TOPLEFT")
    left:SetSize(260, 600)
    local right = CreateFrame("Frame", nil, content)
    right:SetPoint("TOPLEFT", 290, 0)
    right:SetSize(260, 600)

    local fontHeader = UI.CreateHeader(left, L["Global Font"])
    fontHeader:SetPoint("TOPLEFT", 0, 0)
    FontDropdown(left, -30, page)
    OutlineDropdown(left, -85, page)

    local rc = left
    local yOff = -150

    local borderHeader = UI.CreateHeader(rc, L["Border Settings"])
    borderHeader:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 30

    local lblDropdown = rc:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    lblDropdown:SetText(L["Border Texture"])
    lblDropdown:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 25

    local ddBorder = CreateFrame("DropdownButton", nil, rc, "WowStyle1DropdownTemplate")
    ddBorder:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 40
    ddBorder:SetWidth(220)
    ddBorder:SetDefaultText(CDM.db.borderFile or L["Select Border..."])
    page.dropdown = ddBorder

    UI.SetupMediaDropdown(
        ddBorder,
        "border",
        function() return CDM.db.borderFile end,
        function(name)
            CDM.db.borderFile = name
            API:Refresh("STYLE")
        end,
        function(name)
            ddBorder:SetDefaultText(name)
        end
    )

    local colorPicker = UI.CreateColorSwatch(rc, L["Border Color"], "borderColor", "STYLE")
    colorPicker:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 45
    page.colorPicker = colorPicker

    page.controls.b0 = UI.CreateModernSlider(rc, L["Border Size"], 1, 50, CDM.db.borderSize, function(v) CDM.db.borderSize = v; API:Refresh("STYLE") end, 110, 145)
    page.controls.b0:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 60

    page.controls.b1 = UI.CreateModernSlider(rc, L["Border Offset X"], -50, 50, CDM.db.borderOffsetX, function(v) CDM.db.borderOffsetX = v; API:Refresh("STYLE") end, 110, 145)
    page.controls.b1:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 60

    page.controls.b2 = UI.CreateModernSlider(rc, L["Border Offset Y"], -50, 50, CDM.db.borderOffsetY, function(v) CDM.db.borderOffsetY = v; API:Refresh("STYLE") end, 110, 145)
    page.controls.b2:SetPoint("TOPLEFT", 0, yOff); yOff = yOff - 60

    local assist = CreateFrame("Frame", nil, right)
    assist:SetPoint("TOPLEFT", 0, 0)
    assist:SetSize(260, 500)
    ns._CreateAssistPanel(assist, page)
end

local function CreateBorderTab(page)
    BuildBorders(page, page)
end

API:RegisterConfigTab("border", L["Styling"], CreateBorderTab, 4)
