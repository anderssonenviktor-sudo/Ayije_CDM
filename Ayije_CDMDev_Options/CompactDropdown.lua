local AddonName = "Ayije_CDMDev"
local CDM = _G[AddonName]
local UI = CDM._OptionsNS.ConfigUI
local GOLD = CDM.CONST.GOLD
local backdrop = { bgFile = CDM.CONST.TEX_WHITE8X8, edgeFile = CDM.CONST.TEX_WHITE8X8, edgeSize = 1 }
local active, dismiss
local menus = {}

local function Close()
    for _, menu in ipairs(menus) do menu:Hide() end
    if dismiss then dismiss:Hide() end
    if active then active:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.7) end
    active = nil
end

local function Description()
    local node = { entries = {} }
    function node:CreateButton(text, callback)
        local entry = Description()
        entry.text, entry.callback = text, callback
        self.entries[#self.entries + 1] = entry
        return entry
    end
    function node:CreateRadio(text, selected, callback)
        local entry = self:CreateButton(text, callback)
        entry.selected = selected
        return entry
    end
    function node:CreateDivider()
        self.entries[#self.entries + 1] = { divider = true }
    end
    function node:CreateSection(text, actionText, callback)
        local entry = self:CreateButton(text)
        entry.heading, entry.actionText, entry.action = true, actionText, callback
        return entry
    end
    return node
end

local function SelectedText(node)
    for _, entry in ipairs(node.entries) do
        if entry.selected and entry.selected() then return entry.text end
        if entry.entries then
            local text = SelectedText(entry)
            if text then return text end
        end
    end
end

local function ShowMenu(node, owner, depth)
    for i = depth, #menus do menus[i]:Hide() end
    local menu = menus[depth]
    if not menu then
        menu = CreateFrame("Frame", nil, dismiss, "BackdropTemplate")
        menu:SetBackdrop(backdrop)
        menu:SetBackdropColor(0.105, 0.12, 0.13, 1)
        menu:SetBackdropBorderColor(0.31, 0.34, 0.35, 1)
        menu:SetClampedToScreen(true)
        menu:SetFrameLevel(dismiss:GetFrameLevel() + depth * 10)
        menu:EnableMouse(true)
        menu.scroll = CreateFrame("ScrollFrame", nil, menu)
        menu.scroll:SetPoint("TOPLEFT", 4, -4)
        menu.scroll:SetPoint("BOTTOMRIGHT", -4, 4)
        menu.content = CreateFrame("Frame", nil, menu.scroll)
        menu.scroll:SetScrollChild(menu.content)
        menu.rows = {}
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", function(self, delta)
            for i = depth + 1, #menus do menus[i]:Hide() end
            self.scroll:SetVerticalScroll(math.max(0, math.min(self.scroll:GetVerticalScroll() - delta * 52,
                math.max(0, self.content:GetHeight() - self.scroll:GetHeight()))))
        end)
        menus[depth] = menu
    end
    local viewSelector = active and active.viewSelector
    if viewSelector then
        menu:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
        menu:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b, 0.7)
    else
        menu:SetBackdropColor(0.105, 0.12, 0.13, 1)
        menu:SetBackdropBorderColor(0.31, 0.34, 0.35, 1)
    end
    local width = math.max(180, depth == 1 and owner:GetWidth() or 180)
    local y = 0
    for index, entry in ipairs(node.entries) do
        local row = menu.rows[index]
        if not row then
            row = CreateFrame("Button", nil, menu.content)
            row.text = row:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
            row.text:SetPoint("LEFT", 22, 0)
            row.text:SetPoint("RIGHT", -22, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row.mark = row:CreateTexture(nil, "ARTWORK")
            row.mark:SetSize(5, 5)
            row.mark:SetPoint("LEFT", 8, 0)
            row.mark:SetColorTexture(GOLD.r, GOLD.g, GOLD.b, 1)
            row.selectedBackground = row:CreateTexture(nil, "BACKGROUND")
            row.selectedBackground:SetAllPoints()
            row.selectedBackground:SetColorTexture(GOLD.r, GOLD.g, GOLD.b, 0.08)
            row.arrow = row:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
            row.arrow:SetPoint("RIGHT", -8, 0)
            row.arrow:SetText(">")
            row.arrow:SetTextColor(GOLD.r, GOLD.g, GOLD.b)
            row.line = row:CreateTexture(nil, "ARTWORK")
            row.line:SetPoint("LEFT", 6, 0)
            row.line:SetPoint("RIGHT", -6, 0)
            row.line:SetHeight(1)
            row.line:SetColorTexture(0.35, 0.35, 0.35, 0.6)
            row.action = CreateFrame("Button", nil, row)
            row.action:SetPoint("RIGHT", -6, 0)
            row.action:SetSize(78, 24)
            row.action.text = row.action:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font12")
            row.action.text:SetPoint("RIGHT")
            row.action.text:SetTextColor(GOLD.r, GOLD.g, GOLD.b)
            row:SetHighlightTexture(CDM.CONST.TEX_WHITE8X8)
            row:GetHighlightTexture():SetVertexColor(GOLD.r, GOLD.g, GOLD.b, 0.12)
            menu.rows[index] = row
        end
        local selected = entry.selected and entry.selected()
        row.selectedBackground:SetShown(viewSelector and selected and true or false)
        row.mark:SetSize(viewSelector and 2 or 5, viewSelector and 14 or 5)
        row.text:SetFontObject(active and active.smallText and "AyijeCDM_Font12" or "AyijeCDM_Font14")
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetHeight(entry.divider and 9 or (viewSelector and 24 or 26))
        row:EnableMouse(not entry.divider and not entry.heading)
        row.action:SetShown(entry.action ~= nil)
        local actionWidth = entry.actionWidth or 78
        row.action:SetWidth(actionWidth)
        row.action.text:SetText(entry.actionText or "")
        row.action:SetScript("OnClick", function()
            local dropdown = active
            Close()
            if entry.action then entry.action() end
            if dropdown then dropdown:RefreshText() end
        end)
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", entry.heading and 8 or 22, 0)
        row.text:SetPoint("RIGHT", entry.action and -(actionWidth + 14) or -22, 0)
        row.text:SetText(entry.text or "")
        local accented = selected or (viewSelector and not entry.selected and entry.callback)
        row.text:SetTextColor(accented and GOLD.r or 0.92, accented and GOLD.g or 0.92, accented and GOLD.b or 0.92)
        row.mark:SetShown(selected and true or false)
        row.arrow:SetShown(entry.entries and #entry.entries > 0 or false)
        row.line:SetShown(entry.divider and true or false)
        width = math.min(active and active.menuMaxWidth or 420,
            math.max(width, row.text:GetStringWidth() + (entry.action and (actionWidth + 42) or 50)))
        row:SetScript("OnEnter", function()
            for i = depth + 1, #menus do menus[i]:Hide() end
            if entry.entries and #entry.entries > 0 then ShowMenu(entry, row, depth + 1) end
        end)
        row:SetScript("OnClick", function()
            if entry.entries and #entry.entries > 0 then ShowMenu(entry, row, depth + 1); return end
            local dropdown = active
            Close()
            if entry.callback then entry.callback() end
            if dropdown then dropdown:RefreshText() end
        end)
        row:Show()
        y = y + row:GetHeight()
    end
    for index = #node.entries + 1, #menu.rows do menu.rows[index]:Hide() end
    for index = 1, #node.entries do menu.rows[index]:SetWidth(width - 8) end
    menu.content:SetSize(width - 8, math.max(1, y))
    menu:SetSize(width, math.min(y + 8, active and active.menuMaxHeight or 360))
    menu.scroll:SetVerticalScroll(0)
    menu:ClearAllPoints()
    if depth == 1 then menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -3)
    else menu:SetPoint("TOPLEFT", owner, "TOPRIGHT", 3, 4) end
    menu:Show()
end

function UI.CreateCompactDropdown(parent, options)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button.smallText = options and options.smallText
    button.viewSelector = options and options.viewSelector
    button.menuMaxHeight = options and options.menuMaxHeight
    button.menuMaxWidth = options and options.menuMaxWidth
    button:SetSize(180, 26)
    button:SetBackdrop(backdrop)
    button:SetBackdropColor(0, 0, 0, 0.3)
    if button.viewSelector then button:SetBackdropColor(0.06, 0.06, 0.06, 0.95) end
    button:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.7)
    local text = button:CreateFontString(nil, "ARTWORK", "AyijeCDM_Font14")
    if button.smallText then text:SetFontObject("AyijeCDM_Font12") end
    text:SetPoint("LEFT", 9, 0)
    text:SetPoint("RIGHT", -25, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    for side = -1, 1, 2 do
        local arrow = button:CreateTexture(nil, "ARTWORK")
        arrow:SetSize(6, 1.5)
        arrow:SetPoint("CENTER", button, "RIGHT", -13 + side * 2, 0)
        arrow:SetColorTexture(GOLD.r, GOLD.g, GOLD.b, 1)
        arrow:SetRotation(side * math.pi / 4)
    end
    local generator, defaultText, overrideText
    function button:RefreshText()
        local root = Description()
        if generator then generator(self, root) end
        text:SetText(overrideText or SelectedText(root) or defaultText or "")
        return root
    end
    function button:SetDefaultText(value) defaultText = value; self:RefreshText() end
    function button:OverrideText(value) overrideText = value; text:SetText(value) end
    function button:SetupMenu(callback) generator = callback; self:RefreshText() end
    function button:CloseMenu() if active == self then Close() end end
    button:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b, 0.85) end)
    button:SetScript("OnLeave", function(self)
        if active ~= self then self:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.7) end
    end)
    button:SetScript("OnHide", function(self) self:CloseMenu() end)
    button:SetScript("OnClick", function(self)
        if active == self then Close(); return end
        UI.CloseAllDropdownMenus()
        if not (options and options.keepSpellMenu) and CDM._OptionsNS.CloseSpellMenu then
            CDM._OptionsNS.CloseSpellMenu()
        end
        if not dismiss then
            dismiss = CreateFrame("Button", nil, UIParent)
            dismiss:SetAllPoints()
            dismiss:SetFrameStrata("FULLSCREEN_DIALOG")
            dismiss:RegisterForClicks("AnyDown")
            dismiss:SetScript("OnClick", Close)
            dismiss:EnableKeyboard(true)
            dismiss:SetScript("OnKeyDown", function(self, key)
                self:SetPropagateKeyboardInput(key ~= "ESCAPE")
                if key == "ESCAPE" then Close() end
            end)
        end
        active = self
        self:SetBackdropBorderColor(GOLD.r, GOLD.g, GOLD.b, 0.85)
        dismiss:Show()
        ShowMenu(self:RefreshText(), self, 1)
    end)
    return button
end

local CloseNativeMenus = UI.CloseAllDropdownMenus
function UI.CloseAllDropdownMenus()
    Close()
    CloseNativeMenus()
end
CDM:RegisterEvent("PLAYER_REGEN_DISABLED", Close)
