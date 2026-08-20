local Runtime = _G["Ayije_CDM"]
if not Runtime then return end
local API = Runtime.API
local ns = Runtime._OptionsNS
local CDM = Runtime
local L = Runtime.L
local CDM_C = CDM and CDM.CONST or {}
local UI = ns.ConfigUI
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local ConfigFrame = nil
local categories = {}
local buttons = {}
local currentTab = nil
local ADDON_NAME = "Ayije_CDM"
local versionText = nil
local footerRefreshRegistered = false
local lastFooterFont = nil
local combatCloseRegistered = false
local SCROLL_FRAME_NAMES = {
    positions = "AyijeCDM_PosScrollFrame",
    resources = "AyijeCDM_ResourcesScrollFrame",
    bars = "AyijeCDM_BarsScrollFrame",
    castbar = "AyijeCDM_CastBarScrollFrame",
    buffgroups = "AyijeCDM_BuffGroupsLeftScroll",
}

local function GetAddonVersionText()
    local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")

    if not version or version == "" then
        return nil
    end

    return "v" .. tostring(version)
end

local function ApplyFooterTextStyle(fontString)
    if not fontString then return end

    local db = CDM.db or {}
    local defaults = CDM.defaults or {}
    local fontName = db.textFont or defaults.textFont or "Friz Quadrata TT"
    local fontOutline = nil
    local fontPath = (LSM and LSM:Fetch("font", fontName)) or CDM_C.FONT_PATH
    local fontSize = (CDM.Pixel and CDM.Pixel.FontSize(24)) or 24

    fontString:SetFontObject("GameFontHighlightSmall")
    local setOk = fontString:SetFont(fontPath, fontSize, fontOutline)
    if not setOk then
        fontString:SetFont(STANDARD_TEXT_FONT, fontSize, fontOutline)
    end
end

local function ApplyAllFooterTextStyles()
    local currentFont = CDM.db and CDM.db.textFont
    if currentFont == lastFooterFont then return end
    lastFooterFont = currentFont
    ApplyFooterTextStyle(versionText)
end

local function PrintConfigCombatBlocked(actionLabel)
    print("|cffff0000" .. string.format(L["Cannot %s while in combat"], actionLabel or L["open CDM config"]) .. "|r")
end

local function HideConfigPopups()
    if not StaticPopup_Hide then
        return
    end

    StaticPopup_Hide("AYIJE_CDM_COPY_URL")
    StaticPopup_Hide("AYIJE_CDM_CONFIRM_RESET_PROFILE")
    StaticPopup_Hide("AYIJE_CDM_CONFIRM_COPY_PROFILE")
    StaticPopup_Hide("AYIJE_CDM_CONFIRM_DELETE_PROFILE")
    StaticPopup_Hide("AYIJE_CDM_CONFIRM_DELETE_GROUP")
    StaticPopup_Hide("AYIJE_CDM_CONFIRM_DELETE_CD_GROUP")
end

local function HideConfigUiForCombat()
    local frame = ConfigFrame or ns.ConfigFrame
    if frame and frame.IsShown and frame:IsShown() then
        if UI and UI.CloseAllDropdownMenus then
            UI.CloseAllDropdownMenus()
        end
        frame:Hide()
    end
    HideConfigPopups()
end

local function RegisterCombatConfigAutoClose()
    if combatCloseRegistered then return end
    combatCloseRegistered = true

    CDM:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        HideConfigUiForCombat()
    end)
end

RegisterCombatConfigAutoClose()

local function SetCategoryButtonState(button, isActive)
    if isActive then
        button.Texture:SetAtlas("Options_List_Active", true)
        button.Texture:Show()
        UI.SetTextWhite(button.Text)
        return
    end

    button.Texture:Hide()
    UI.SetTextInactive(button.Text)
end

-- Tab pages are created empty and populated the first time they are selected.
-- Building all of them up front costs ~120 CreateFrame calls plus the widgets
-- each builder makes, all to show one page and hide the rest.
local function EnsureCategoryBuilt(id)
    local page = categories[id]
    if not page or page.acdmBuilt then return end

    local tabDef = ns.ConfigTabs and ns.ConfigTabs[id]
    if not tabDef or not tabDef.createFunc then return end

    page.acdmBuilt = true
    tabDef.createFunc(page, id)
end

local function SelectCategory(id)
    if UI and UI.CloseAllDropdownMenus then
        UI.CloseAllDropdownMenus()
    end
    -- Must precede the SetShown pass below: builders install OnShow handlers
    -- that have to be attached before the page is shown.
    EnsureCategoryBuilt(id)
    currentTab = id
    for categoryId, frame in pairs(categories) do frame:SetShown(categoryId == id) end
    for buttonId, btn in pairs(buttons) do
        SetCategoryButtonState(btn, buttonId == id)
    end

    local scrollFrameName = SCROLL_FRAME_NAMES[id]
    if scrollFrameName then
        local scrollFrame = _G[scrollFrameName]
        if scrollFrame then
            scrollFrame:SetVerticalScroll(0)
        end
    end

end

ns.ConfigSelectCategory = SelectCategory

local function CreateCategoryPage(id, name, Content)
    local page = CreateFrame("Frame", nil, Content)
    page:SetAllPoints()
    page:Hide()
    page.controls = {}
    categories[id] = page
    return page
end

ns.ConfigCreatePage = CreateCategoryPage

local categoryHeaders = {
    { label = L["CDM"], tabs = {"layout", "buffgroups", "bars", "positions"} },
    { label = L["Styling"], tabs = {"sizes", "border", "text", "glow", "fading", "assist"} },
    { label = L["Features"], tabs = {"resources", "castbar"} },
    { label = L["Utility"], tabs = {"profiles", "importexport"} },
}

local function CreateConfigFrame()
    if ConfigFrame then return end

    ConfigFrame = CreateFrame("Frame", "Ayije_CDMConfigFrame", UIParent, "SettingsFrameTemplate")
    ConfigFrame:SetSize(920, 720)
    ConfigFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    ConfigFrame:SetFrameStrata("HIGH")
    ConfigFrame:Hide()
    tinsert(UISpecialFrames, "Ayije_CDMConfigFrame")
    ConfigFrame:HookScript("OnHide", function()
        if UI and UI.CloseAllDropdownMenus then
            UI.CloseAllDropdownMenus()
        end
        HideConfigPopups()
        if CDM.SetConfigWindowActive then
            CDM:SetConfigWindowActive(false)
        end
    end)
    ConfigFrame:HookScript("OnShow", function()
        if CDM.SetConfigWindowActive then
            CDM:SetConfigWindowActive(true)
        end
    end)

    if ConfigFrame.TitleText then
        ConfigFrame.TitleText:SetText("")
    end
    if ConfigFrame.Bg then
        ConfigFrame.Bg:SetFrameLevel(ConfigFrame:GetFrameLevel())
    end

    local titleContainer = CreateFrame("Frame", nil, ConfigFrame)
    titleContainer:SetPoint("TOP", ConfigFrame, "TOP", 0, 0)
    titleContainer:SetSize(200, 40)
    titleContainer:SetFrameLevel(ConfigFrame:GetFrameLevel() + 10)

    local title = titleContainer:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font18")
    title:SetPoint("TOP", ConfigFrame, "TOP", 0, -34)
    title:SetText(L["Cooldown Manager"])
    UI.SetTextColor(title, CDM_C.GOLD or { r = 1, g = 0.82, b = 0, a = 1 })

    local cdmBtn = CreateFrame("Button", nil, titleContainer, "UIPanelButtonTemplate")
    cdmBtn:SetSize(90, 24)
    cdmBtn:SetPoint("TOPLEFT", ConfigFrame, "TOPLEFT", 22, -32)
    cdmBtn:SetText(L["Settings"])
    cdmBtn:SetScript("OnClick", function()
        if not CooldownViewerSettings then return end
        if CooldownViewerSettings:IsVisible() then
            securecall("HideUIPanel", CooldownViewerSettings)
        else
            securecall("ShowUIPanel", CooldownViewerSettings)
        end
    end)

    local editModeBtn = CreateFrame("Button", nil, titleContainer, "UIPanelButtonTemplate")
    editModeBtn:SetSize(140, 24)
    editModeBtn:SetPoint("LEFT", cdmBtn, "RIGHT", 6, 0)
    editModeBtn:SetText(L["Edit Mode Settings"])

    local editModeOverlay
    editModeBtn:SetScript("OnClick", function()
        if not ns.CreateEditModeOverlay then return end
        if not editModeOverlay then
            editModeOverlay = ns.CreateEditModeOverlay()
        end
        editModeOverlay:Show()
    end)

    ConfigFrame:SetMovable(true)
    ConfigFrame:EnableMouse(true)
    ConfigFrame:RegisterForDrag("LeftButton")
    ConfigFrame:SetScript("OnDragStart", ConfigFrame.StartMoving)
    ConfigFrame:SetScript("OnDragStop", ConfigFrame.StopMovingOrSizing)

    -- Host the inner-frame atlas on a child so it renders above the template background.
    local panelBgHolder = CreateFrame("Frame", nil, ConfigFrame)
    panelBgHolder:SetAllPoints()
    local panelBg = panelBgHolder:CreateTexture(nil, "BACKGROUND")
    panelBg:SetAtlas("Options_InnerFrame", true)
    panelBg:SetPoint("TOPLEFT", ConfigFrame, "TOPLEFT", 17, -64)

    versionText = ConfigFrame:CreateFontString(nil, "OVERLAY")
    versionText:SetPoint("BOTTOMRIGHT", ConfigFrame, "BOTTOMRIGHT", -22, 10)
    ApplyFooterTextStyle(versionText)
    versionText:SetText(GetAddonVersionText() or "")
    if UI and UI.SetTextFaint then
        UI.SetTextFaint(versionText)
    else
        versionText:SetTextColor(0.5, 0.5, 0.5, 1)
    end

    local Sidebar = CreateFrame("Frame", nil, ConfigFrame)
    Sidebar:SetPoint("TOPLEFT", panelBg, "TOPLEFT", 1, 0)
    Sidebar:SetPoint("BOTTOMLEFT", panelBg, "BOTTOMLEFT", 1, 0)
    Sidebar:SetWidth(180)

    local Content = CreateFrame("Frame", nil, ConfigFrame)
    Content:SetPoint("TOPLEFT", Sidebar, "TOPRIGHT", 35, 0)
    Content:SetPoint("BOTTOMRIGHT", -30, 25)

    ns.ConfigContent = Content
    ns.ConfigFrame = ConfigFrame
    ns.ConfigSidebar = Sidebar

    local sortedTabs = {}
    for id, tabDef in pairs(ns.ConfigTabs or {}) do
        table.insert(sortedTabs, tabDef)
    end
    table.sort(sortedTabs, function(a, b) return a.navOrder < b.navOrder end)

    -- Pages only; each tab's contents are built lazily by EnsureCategoryBuilt.
    for _, tabDef in ipairs(sortedTabs) do
        CreateCategoryPage(tabDef.id, tabDef.label, Content)
    end

    local headerIndex = 1
    local function AddHeader(label, y)
        local header = CreateFrame("Frame", nil, Sidebar, "SettingsCategoryListHeaderTemplate")
        header:SetPoint("TOPLEFT", 0, y)

        local atlasIndex = ((headerIndex - 1) % 3) + 1
        local initializer = { data = { label = label, headerIndex = atlasIndex } }
        header:Init(initializer)

        headerIndex = headerIndex + 1
        return header
    end

    local function AddNav(id, label, y, indent)
        indent = indent or 0
        local btn = CreateFrame("Button", nil, Sidebar)
        btn:SetSize(175 - indent, 22)  -- Match header width
        btn:SetPoint("TOPLEFT", indent, y)

        btn.Texture = btn:CreateTexture(nil, "BACKGROUND")
        btn.Texture:SetPoint("TOPLEFT", -10, 0)
        btn.Texture:SetPoint("BOTTOMRIGHT", 20, 0)
        btn.Texture:Hide()

        btn.Text = btn:CreateFontString(nil, "OVERLAY", "AyijeCDM_Font14")
        btn.Text:SetPoint("LEFT", indent, 0)  -- Include indent for child hierarchy
        btn.Text:SetText(label)

        btn:SetScript("OnEnter", function(self)
            if currentTab ~= id then
                self.Texture:SetAtlas("Options_List_Hover", true)
                self.Texture:Show()
            end
        end)

        btn:SetScript("OnLeave", function(self)
            if currentTab ~= id then
                self.Texture:Hide()
            end
        end)

        btn:SetScript("OnClick", function() SelectCategory(id) end)
        buttons[id] = btn
    end

    local yOffset = -4
    local tabIndent = 17

    for _, category in ipairs(categoryHeaders) do
        AddHeader(category.label, yOffset)
        yOffset = yOffset - 34

        for _, tabId in ipairs(category.tabs) do
            local tabDef = ns.ConfigTabs and ns.ConfigTabs[tabId]
            if tabDef then
                AddNav(tabDef.id, tabDef.label, yOffset, tabIndent)
                yOffset = yOffset - 24
            end
        end

    end

    -- open on the sidebar's first entry (navOrder only governs page build order)
    local firstNavTab = categoryHeaders[1] and categoryHeaders[1].tabs[1]
    if firstNavTab and ns.ConfigTabs and ns.ConfigTabs[firstNavTab] then
        SelectCategory(firstNavTab)
    elseif sortedTabs[1] then
        SelectCategory(sortedTabs[1].id)
    end

    if not footerRefreshRegistered then
        API:RegisterRefreshCallback("configFooterTextStyle", function()
            ApplyAllFooterTextStyles()
        end, 95, { "STYLE" })
        footerRefreshRegistered = true
    end
end

function API:ShowConfig(targetTab)
    if InCombatLockdown() then
        PrintConfigCombatBlocked(L["open CDM config"])
        return
    end

    if not ConfigFrame then CreateConfigFrame() end
    ConfigFrame:Show()

    -- Jumping to a tab does not need the full teardown/rebuild that
    -- RebuildConfigFrame does; that is only for discarding stale state.
    if targetTab and ns.ConfigTabs and ns.ConfigTabs[targetTab] then
        SelectCategory(targetTab)
    end
end

function API:RebuildConfigFrame(targetTab)
    if InCombatLockdown() then
        PrintConfigCombatBlocked(L["rebuild CDM config"])
        return
    end

    if ConfigFrame then
        API:UnregisterPositionSliderUpdater("essential")
        API:UnregisterPositionSliderUpdater("buff")
        API:UnregisterPositionSliderUpdater("buffBar")

        API:UnregisterRefreshCallback("configFooterTextStyle")
        footerRefreshRegistered = false
        if ns.CancelImportStatusTimer then
            ns.CancelImportStatusTimer()
        end

        ConfigFrame:Hide()
        ConfigFrame:SetParent(nil)  -- orphan for GC
        ConfigFrame = nil
        categories = {}
        buttons = {}
        currentTab = nil
        versionText = nil
        ns.ConfigFrame = nil
        ns.ConfigContent = nil
        ns.ConfigSidebar = nil
    end
    CreateConfigFrame()
    ConfigFrame:Show()

    local tabToSelect = targetTab or "profiles"
    if not (ns.ConfigTabs and ns.ConfigTabs[tabToSelect]) then
        tabToSelect = "profiles"
    end
    if ns.ConfigTabs and ns.ConfigTabs[tabToSelect] then
        SelectCategory(tabToSelect)
    end
end
