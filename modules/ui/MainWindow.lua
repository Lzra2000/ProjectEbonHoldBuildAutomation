-- EbonBuilds: modules/ui/MainWindow.lua
-- Responsibility: top-level window shell with navigation and a high-contrast content panel.
-- Hosts the build list and the view router.

EbonBuilds.MainWindow = {}

local WINDOW_WIDTH  = 980
local WINDOW_HEIGHT = 660
local LEFT_WIDTH    = 230
local FRAME_NAME    = "EbonBuildsMainWindow"
local contextLabel
local pageLabel, dirtyLabel, automationPill, classAccent
local currentPageTitle = "Overview"
local currentDirty = false

local function ApplyBackdrop(frame)
    EbonBuilds.Theme.ApplyWindow(frame)
end

local function CreateTitleBar(frame)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -10)
    title:SetText("EbonBuilds")
    title:SetTextColor(unpack(EbonBuilds.Theme.TEXT_PRIMARY))

    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)
    version:SetText("v" .. tostring((GetAddOnMetadata and GetAddOnMetadata("EbonBuilds", "Version")) or EbonBuilds.VERSION or "2.6"))
    version:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    pageLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pageLabel:SetPoint("LEFT", version, "RIGHT", 18, 0)
    pageLabel:SetText("/  Overview")
    pageLabel:SetTextColor(unpack(EbonBuilds.Theme.ACCENT_GOLD))

    automationPill = EbonBuilds.Theme.CreateStatusPill(frame, "AUTOPILOT --", "warning")
    automationPill:SetWidth(104)
    automationPill:SetPoint("RIGHT", frame, "RIGHT", -120, 0)
    automationPill:SetPoint("TOP", frame, "TOP", 0, -14)

    contextLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    contextLabel:SetPoint("RIGHT", automationPill, "LEFT", -16, 0)
    contextLabel:SetPoint("TOP", frame, "TOP", 0, -14)
    contextLabel:SetWidth(188)
    contextLabel:SetJustifyH("RIGHT")
    if contextLabel.SetNonSpaceWrap then contextLabel:SetNonSpaceWrap(false) end
    if contextLabel.SetWordWrap then contextLabel:SetWordWrap(false) end
    contextLabel:SetTextColor(unpack(EbonBuilds.Theme.TEXT_PRIMARY))
    contextLabel:SetText("No active build")

    classAccent = frame:CreateTexture(nil, "ARTWORK")
    classAccent:SetTexture("Interface\\Buttons\\WHITE8X8")
    classAccent:SetSize(3, 18)
    classAccent:SetPoint("RIGHT", contextLabel, "LEFT", -10, 0)
    classAccent:SetPoint("TOP", frame, "TOP", 0, -8)
    classAccent:SetVertexColor(0.5, 0.5, 0.5, 0.8)

    dirtyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dirtyLabel:SetPoint("TOPRIGHT", automationPill, "BOTTOMRIGHT", 0, -4)
    dirtyLabel:SetWidth(312)
    dirtyLabel:SetJustifyH("RIGHT")
    dirtyLabel:SetText("")
    dirtyLabel:SetTextColor(unpack(EbonBuilds.Theme.WARNING))

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetVertexColor(0.30, 0.30, 0.36, 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -36)
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -36)

    local dragRegion = CreateFrame("Frame", nil, frame)
    dragRegion:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0,   0)
    dragRegion:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -330, 0)
    dragRegion:SetHeight(34)
    dragRegion:EnableMouse(true)
    dragRegion:RegisterForDrag("LeftButton")
    dragRegion:SetScript("OnDragStart", function() frame:StartMoving() end)
    dragRegion:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local cx, cy = frame:GetCenter()
        if cx and cy then EbonBuildsDB.windowPos = { x = cx, y = cy } end
    end)
end

local function CreateCloseButton(frame)
    local closeBtn = EbonBuilds.Theme.CreateCloseButton(frame)
    closeBtn:SetFrameLevel(100)
    return closeBtn
end

------------------------------------------------------------------------
-- Global settings popup
------------------------------------------------------------------------

StaticPopupDialogs["EBONBUILDS_CLEAR_TRAINING"] = {
    text = "",
    button1 = "Clear",
    button2 = "Cancel",
    OnAccept = function()
        local build = EbonBuilds.Build.GetActive()
        if not build then return end
        EbonBuilds.ManualTraining.Clear(build.id)
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then
            EbonBuilds.Toast.Show("Cleared Manual Training data for \"" .. (build.title or "?") .. "\"")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local SETTINGS_CATEGORIES = {
    { key = "general",    label = "General" },
    { key = "automation", label = "Automation" },
    { key = "language",   label = "Language" },
    { key = "tools",      label = "Windows & Tools" },
    { key = "build",      label = "Build" },
}

local function BuildSettingsPopup()
    local popup = CreateFrame("Frame", "EbonBuildsGlobalSettingsPopup", UIParent)
    popup:SetSize(420, 400)
    popup:SetPoint("CENTER", UIParent, "CENTER")
    popup:SetFrameStrata("DIALOG")
    popup:SetToplevel(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    EbonBuilds.Theme.ApplyWindow(popup)
    popup:Hide()

    -- Title bar / drag region
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", popup, "TOP", 0, -16)
    title:SetText("EbonBuilds Settings")

    local drag = CreateFrame("Frame", nil, popup)
    drag:SetPoint("TOPLEFT",  popup, "TOPLEFT",  0,   0)
    drag:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -37, 0)
    drag:SetHeight(30)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() popup:StartMoving() end)
    drag:SetScript("OnDragStop",  function() popup:StopMovingOrSizing() end)

    -- Close button for popup
    local closeBtn = EbonBuilds.Theme.CreateCloseButton(popup)

    ------------------------------------------------------------------------
    -- Category tabs. Each category is its own fixed panel, shown one at a
    -- time -- replaces the previous single long scrolling list, which grew
    -- harder to scan every time a setting was added.
    ------------------------------------------------------------------------

    local tabButtons = {}
    local panels = {}
    local activeCategory = 1

    local function ShowCategory(index)
        activeCategory = index
        for i, panel in ipairs(panels) do
            panel:SetShown(i == index)
        end
        for i, btn in ipairs(tabButtons) do
            EbonBuilds.Theme.SetTabSelected(btn, i == index)
        end
    end

    local tabAnchor
    for i, def in ipairs(SETTINGS_CATEGORIES) do
        local btn = EbonBuilds.Theme.CreateTab(popup, def.label)
        btn:SetWidth(def.key == "tools" and 118 or def.key == "automation" and 92 or 76)
        if not tabAnchor then
            btn:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -36)
        else
            btn:SetPoint("LEFT", tabAnchor, "RIGHT", 3, 0)
        end
        btn:SetScript("OnClick", function() ShowCategory(i) end)
        tabButtons[i] = btn
        tabAnchor = btn
    end

    local contentArea = CreateFrame("Frame", nil, popup)
    contentArea:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -68)
    contentArea:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -16, 50)
    EbonBuilds.Theme.ApplyPanel(contentArea)

    local function NewPanel()
        local panel = CreateFrame("Frame", nil, contentArea)
        panel:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 10, -10)
        panel:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -10, 10)
        panel:Hide()
        panels[#panels + 1] = panel
        return panel
    end

    -- Helper: label -> optional flavor text -> slider with track and value
    -- display. Anchored relative to the PREVIOUS element's actual rendered
    -- bottom edge (not a fixed pixel offset), so wrapped flavor text can
    -- never make two blocks overlap.
    local function AddSlider(parent, labelText, flavorText, yAnchor, yOffset, minV, maxV, value)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if yAnchor == parent then
            label:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        else
            label:SetPoint("TOPLEFT", yAnchor, "BOTTOMLEFT", 0, yOffset)
        end

        local anchorForSlider = label
        local flavor
        if flavorText then
            flavor = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            flavor:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
            flavor:SetWidth(360)
            flavor:SetJustifyH("LEFT")
            flavor:SetText(flavorText)
            anchorForSlider = flavor
        end

        local slider = CreateFrame("Slider", nil, parent)
        slider:SetOrientation("HORIZONTAL")
        slider:SetWidth(190)
        slider:SetHeight(20)
        slider:SetPoint("TOPLEFT", anchorForSlider, "BOTTOMLEFT", 0, -4)
        slider:SetMinMaxValues(minV, maxV)
        slider:SetValueStep(0.1)
        slider:SetValue(value)
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetTexture("Interface\\Buttons\\WHITE8X8")
        track:SetVertexColor(0.25, 0.25, 0.25, 1)
        track:SetHeight(6)
        track:SetPoint("CENTER", slider)
        track:SetPoint("LEFT", slider)
        track:SetPoint("RIGHT", slider)

        local valText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valText:SetPoint("LEFT", slider, "RIGHT", 6, 0)

        local function RefreshLabel()
            local v = slider:GetValue()
            label:SetText(string.format("%s %.1fs", labelText, v))
            valText:SetText(string.format("%.1fs", v))
        end

        slider:SetScript("OnValueChanged", RefreshLabel)
        RefreshLabel()

        return slider, slider
    end

    -- Helper: themed checkbox with a label and explanation, same
    -- previous-element-relative anchoring as AddSlider.
    local function AddCheckbox(parent, labelText, flavorText, yAnchor, yOffset)
        local cb = EbonBuilds.Theme.CreateCheckbox(parent, labelText)
        if yAnchor == parent then
            cb:SetPoint("TOPLEFT", parent, "TOPLEFT", -2, yOffset)
        else
            cb:SetPoint("TOPLEFT", yAnchor, "BOTTOMLEFT", -2, yOffset)
        end

        local flavor = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        flavor:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 26, -2)
        flavor:SetWidth(340)
        flavor:SetJustifyH("LEFT")
        flavor:SetText(flavorText)

        return cb, flavor
    end

    local function AddToolButton(parent, labelText, yAnchor, yOffset, onClick)
        local btn = EbonBuilds.Theme.CreateButton(parent)
        btn:SetSize(180, 22)
        if yAnchor == parent then
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        else
            btn:SetPoint("TOPLEFT", yAnchor, "BOTTOMLEFT", 0, yOffset)
        end
        btn:SetText(labelText)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    ------------------------------------------------------------------------
    -- General
    ------------------------------------------------------------------------
    local generalPanel = NewPanel()
    local delaySlider, delayBottom = AddSlider(generalPanel,
        "Action delay:",
        "Very low values may cause the addon to malfunction.",
        generalPanel, 0, 0.1, 3.0, 2)
    local toastSlider = AddSlider(generalPanel,
        "Toast duration:",
        "How long pick/reroll/freeze/banish notifications stay on screen.",
        delayBottom, -14, 0.5, 8.0, 3)

    ------------------------------------------------------------------------
    -- Automation
    ------------------------------------------------------------------------
    local automationPanel = NewPanel()
    local autoSellCB, autoSellBottom = AddCheckbox(automationPanel,
        "Auto-sell junk at vendors",
        "Sells 0-copper bag items automatically while a vendor is open. Items with an unlearned affix stay protected even if worthless.",
        automationPanel, 0)
    local bagDotsCB, bagDotsBottom = AddCheckbox(automationPanel,
        "Bag affix dots",
        "Colored dot on bag items missing an affix: red for a new line, purple for a rank you're missing on one you already have.",
        autoSellBottom, -10)
    local debugCB, debugBottom = AddCheckbox(automationPanel,
        "Detailed automation logging",
        "Records every automation decision with its reasoning, viewable under Windows & Tools -> Debug log.",
        bagDotsBottom, -10)
    local clickTraceCB = AddCheckbox(automationPanel,
        "Log every button click",
        "For \"I clicked and nothing happened\" troubleshooting -- viewable under Windows & Tools -> Click Trace log.",
        debugBottom, -10)

    ------------------------------------------------------------------------
    -- Language
    ------------------------------------------------------------------------
    local languagePanel = NewPanel()
    local languageNote = languagePanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    languageNote:SetPoint("TOPLEFT", languagePanel, "TOPLEFT", 0, 0)
    languageNote:SetWidth(360)
    languageNote:SetJustifyH("LEFT")
    languageNote:SetText("Takes effect after /reload.")

    local languageButtons = {}
    do
        local locales = EbonBuilds.Locale.GetSupportedLocales()
        local BTN_W, BTN_GAP = 62, 4
        local perRow = math.floor((370 - 4) / (BTN_W + BTN_GAP))
        for i, entry in ipairs(locales) do
            local btn = EbonBuilds.Theme.CreateButton(languagePanel)
            btn:SetSize(BTN_W, 20)
            local col = (i - 1) % perRow
            local row = math.floor((i - 1) / perRow)
            if col == 0 then
                btn:SetPoint("TOPLEFT", languageNote, "BOTTOMLEFT", 0, -8 - (row * 24))
            else
                btn:SetPoint("LEFT", languageButtons[i - 1], "RIGHT", BTN_GAP, 0)
            end
            btn:SetText(entry.code)
            btn._localeCode = entry.code
            btn:SetScript("OnClick", function()
                EbonBuilds.Locale.SetLocale(entry.code)
                for _, b in ipairs(languageButtons) do
                    local fs = b.GetFontString and b:GetFontString()
                    if fs then
                        if b._localeCode == entry.code then
                            fs:SetTextColor(unpack(EbonBuilds.Theme.ACCENT_GOLD))
                        else
                            fs:SetTextColor(1, 1, 1, 1)
                        end
                    end
                end
                if EbonBuilds.Toast and EbonBuilds.Toast.Show then
                    EbonBuilds.Toast.Show("Language set to " .. entry.code .. " -- /reload to apply it")
                end
            end)
            languageButtons[i] = btn
        end
    end

    ------------------------------------------------------------------------
    -- Windows & Tools -- every /ebb subcommand that just opens a window
    -- now lives here instead, so there's one place to find them instead
    -- of needing to know the slash command by name.
    ------------------------------------------------------------------------
    local toolsPanel = NewPanel()
    local showcaseBtn = AddToolButton(toolsPanel, "Commands guide", toolsPanel, 0, function()
        if EbonBuilds.ShowcaseView then EbonBuilds.ShowcaseView.Show() end
    end)
    local atlasBtn = AddToolButton(toolsPanel, "Tome Atlas", showcaseBtn, -6, function()
        popup:Hide()
        if not frame:IsShown() then frame:Show() end
        EbonBuilds.ViewRouter.Show("tomeAtlas")
    end)
    local affixBtn = AddToolButton(toolsPanel, "Affixes reference", atlasBtn, -6, function()
        popup:Hide()
        if not frame:IsShown() then frame:Show() end
        EbonBuilds.ViewRouter.Show("affixes")
    end)
    local tuningBtn = AddToolButton(toolsPanel, "Tuning Advisor", affixBtn, -6, function()
        if EbonBuilds.Calibration then EbonBuilds.Calibration.ShowWindow() end
    end)
    local debugLogBtn = AddToolButton(toolsPanel, "Debug log", tuningBtn, -6, function()
        if EbonBuilds.DebugLog then EbonBuilds.DebugLog.ShowWindow() end
    end)
    local clickTraceLogBtn = AddToolButton(toolsPanel, "Click Trace log", debugLogBtn, -6, function()
        if EbonBuilds.ClickTrace then EbonBuilds.ClickTrace.ShowWindow() end
    end)
    AddToolButton(toolsPanel, "Error log", clickTraceLogBtn, -6, function()
        if EbonBuilds.ErrorLog then EbonBuilds.ErrorLog.ShowWindow() end
    end)

    ------------------------------------------------------------------------
    -- Build -- actions that need an active build. Greyed out with an
    -- explanatory note when there isn't one, rather than hidden, so it's
    -- clear the option exists.
    ------------------------------------------------------------------------
    local buildPanel = NewPanel()
    local buildNote = buildPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    buildNote:SetPoint("TOPLEFT", buildPanel, "TOPLEFT", 0, 0)
    buildNote:SetWidth(360)
    buildNote:SetJustifyH("LEFT")
    buildNote:SetText("No active build.")

    local ewlBtn = AddToolButton(buildPanel, "Export Wishlist (EWL)", buildNote, -8, function()
        local build = EbonBuilds.Build.GetActive()
        if build and EbonBuilds.EWL then EbonBuilds.EWL.ShowExportDialog(build) end
    end)
    local clearTrainingBtn = AddToolButton(buildPanel, "Clear Manual Training data", ewlBtn, -6, function()
        local build = EbonBuilds.Build.GetActive()
        if not build then return end
        StaticPopupDialogs["EBONBUILDS_CLEAR_TRAINING"].text =
            "Clear Manual Training data for \"" .. (build.title or "?") .. "\"?\n\nThis cannot be undone."
        StaticPopup_Show("EBONBUILDS_CLEAR_TRAINING")
    end)

    local function RefreshBuildPanelState()
        local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
        if build then
            buildNote:SetText("Applies to \"" .. (build.title or "Untitled") .. "\".")
            ewlBtn:Enable()
            clearTrainingBtn:Enable()
        else
            buildNote:SetText("No active build.")
            ewlBtn:Disable()
            clearTrainingBtn:Disable()
        end
    end

    ------------------------------------------------------------------------
    -- Save / Cancel -- apply across every category at once, not per-tab,
    -- so switching tabs never silently discards a change made on another.
    ------------------------------------------------------------------------
    local saveBtn = EbonBuilds.Theme.CreateButton(popup)
    saveBtn:SetSize(80, 22)
    saveBtn:SetPoint("BOTTOM", popup, "BOTTOM", 43, 18)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        local gs = EbonBuildsDB.globalSettings
        gs.evalDelay = delaySlider:GetValue()
        gs.toastDuration = toastSlider:GetValue()
        local autoSellOn, bagDotsOn, debugOn, clickTraceOn
        if EbonBuilds.AutoSell then
            autoSellOn = autoSellCB:GetChecked() and true or false
            EbonBuilds.AutoSell.SetEnabled(autoSellOn)
        end
        if EbonBuilds.BagAffixDots then
            bagDotsOn = bagDotsCB:GetChecked() and true or false
            EbonBuilds.BagAffixDots.SetEnabled(bagDotsOn)
        end
        if EbonBuilds.DebugLog then
            debugOn = debugCB:GetChecked() and true or false
            EbonBuilds.DebugLog.SetEnabled(debugOn)
        end
        if EbonBuilds.ClickTrace then
            clickTraceOn = clickTraceCB:GetChecked() and true or false
            EbonBuilds.ClickTrace.SetEnabled(clickTraceOn)
        end
        popup:Hide()
        -- Confirms the settings actually took effect -- previously Save
        -- just closed the popup silently with no feedback at all, so
        -- there was no way to tell a toggle click had actually been
        -- saved versus just visually checked in the box.
        if EbonBuilds.Toast and EbonBuilds.Toast.Show then
            local parts = {}
            if autoSellOn ~= nil then parts[#parts + 1] = "Auto-sell " .. (autoSellOn and "ON" or "OFF") end
            if bagDotsOn ~= nil then parts[#parts + 1] = "Bag dots " .. (bagDotsOn and "ON" or "OFF") end
            if debugOn ~= nil then parts[#parts + 1] = "Debug log " .. (debugOn and "ON" or "OFF") end
            if clickTraceOn ~= nil then parts[#parts + 1] = "Click Trace " .. (clickTraceOn and "ON" or "OFF") end
            local msg = "Settings saved"
            if #parts > 0 then msg = msg .. " (" .. table.concat(parts, ", ") .. ")" end
            EbonBuilds.Toast.Show(msg)
        end
    end)

    local cancelBtn = EbonBuilds.Theme.CreateButton(popup)
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("BOTTOM", popup, "BOTTOM", -43, 18)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() popup:Hide() end)

    popup:SetScript("OnShow", function()
        local gs = EbonBuildsDB.globalSettings
        delaySlider:SetValue(gs.evalDelay or 2)
        toastSlider:SetValue(gs.toastDuration or 3)
        autoSellCB:SetChecked(EbonBuilds.AutoSell and EbonBuilds.AutoSell.IsEnabled())
        bagDotsCB:SetChecked(EbonBuilds.BagAffixDots and EbonBuilds.BagAffixDots.IsEnabled())
        debugCB:SetChecked(EbonBuilds.DebugLog and EbonBuilds.DebugLog.IsEnabled())
        clickTraceCB:SetChecked(EbonBuilds.ClickTrace and EbonBuilds.ClickTrace.IsEnabled())
        local activeLocale = EbonBuilds.Locale.GetActiveLocale()
        for _, b in ipairs(languageButtons) do
            local fs = b.GetFontString and b:GetFontString()
            if fs then
                fs:SetTextColor(unpack(b._localeCode == activeLocale and EbonBuilds.Theme.ACCENT_GOLD or { 1, 1, 1, 1 }))
            end
        end
        RefreshBuildPanelState()
        ShowCategory(1)
    end)

    return popup

end

local function CreateHeaderIconButton(frame, anchor, texture, tooltipTitle, tooltipBody)
    local btn = CreateFrame("Button", nil, frame)
    btn:SetSize(24, 24)
    btn:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
    btn:SetFrameLevel(100)
    EbonBuilds.Theme.ApplyCard(btn)

    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(texture)
    icon:SetTexCoord(0.10, 0.90, 0.10, 0.90)
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    btn._icon = icon

    btn:SetScript("OnEnter", function(self)
        EbonBuilds.Theme.SetCardHovered(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(tooltipTitle, 1, 0.82, 0)
        GameTooltip:AddLine(tooltipBody, 0.82, 0.82, 0.86, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        EbonBuilds.Theme.SetCardHovered(self, false)
        GameTooltip:Hide()
    end)
    return btn
end

local function CreateSettingsButton(frame, popup, closeBtn)
    local btn = CreateHeaderIconButton(frame, closeBtn, "Interface\\Icons\\Trade_Engineering",
        "Settings", "Configure addon-wide timing and convenience features.")
    btn:SetScript("OnClick", function()
        if popup:IsShown() then popup:Hide() else popup:Show() end
    end)
    return btn
end

local function CreateHelpButton(frame, settingsBtn)
    local btn = CreateHeaderIconButton(frame, settingsBtn, "Interface\\Icons\\INV_Misc_Book_09",
        "Help and what's new", "Open the getting-started guide, feature explanations, and changelog.")
    btn:SetScript("OnClick", function()
        if EbonBuilds.FAQ and EbonBuilds.FAQ.Show then EbonBuilds.FAQ.Show() end
    end)
    return btn
end

local function CreateLeftColumn(frame)
    local col = CreateFrame("Frame", nil, frame)
    col:SetPoint("TOPLEFT",    frame, "TOPLEFT",    12, -44)
    col:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12,  12)
    col:SetWidth(LEFT_WIDTH)
    EbonBuilds.Theme.ApplySidebar(col)
    return col
end

local function CreateRightPanel(frame)
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT",     frame, "TOPLEFT",     12 + LEFT_WIDTH + 8, -44)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    EbonBuilds.Theme.ApplyPanel(panel)
    return panel
end

local function BuildFrame()
    local frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetWidth(WINDOW_WIDTH)
    frame:SetHeight(WINDOW_HEIGHT)
    frame:SetMovable(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)

    -- Restore saved position, or default to center.
    local pos = EbonBuildsDB.windowPos
    if pos and pos.x and pos.y then
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end

    ApplyBackdrop(frame)
    CreateTitleBar(frame)
    local closeBtn = CreateCloseButton(frame)

    local settingsPopup = BuildSettingsPopup()
    local settingsBtn = CreateSettingsButton(frame, settingsPopup, closeBtn)
    CreateHelpButton(frame, settingsBtn)
    frame._settingsPopup = settingsPopup

    -- Standard WoW behavior: ESC closes the window.
    tinsert(UISpecialFrames, FRAME_NAME)

    frame:Hide()
    return frame
end


function EbonBuilds.MainWindow.SetPageContext(title)
    currentPageTitle = title or "Overview"
    if pageLabel then pageLabel:SetText("/  " .. currentPageTitle) end
end

function EbonBuilds.MainWindow.SetDirtyState(dirty)
    currentDirty = dirty and true or false
    if dirtyLabel then
        if currentDirty then
            dirtyLabel:SetText("Unsaved build changes")
            dirtyLabel:SetTextColor(unpack(EbonBuilds.Theme.WARNING))
        else
            dirtyLabel:SetText("")
        end
    end
end

function EbonBuilds.MainWindow.RefreshContext()
    if pageLabel then pageLabel:SetText("/  " .. (currentPageTitle or "Overview")) end
    if not contextLabel then return end
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if not build then
        contextLabel:SetText("No active build")
        contextLabel:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
        if automationPill and automationPill.label then automationPill.label:SetText("AUTOPILOT --") end
        if classAccent then classAccent:SetVertexColor(0.5, 0.5, 0.5, 0.6) end
        return
    end

    contextLabel:SetText(build.title or "Untitled")
    local r, g, b = EbonBuilds.Theme.ClassRGB(build.class)
    contextLabel:SetTextColor(r, g, b, 1)
    if classAccent then classAccent:SetVertexColor(r, g, b, 1) end

    local enabled = build.automationEnabled ~= false
    if automationPill and automationPill.label then
        automationPill.label:SetText(enabled and "AUTOPILOT ON" or "AUTOPILOT OFF")
        local c = enabled and EbonBuilds.Theme.SUCCESS or EbonBuilds.Theme.WARNING
        automationPill:SetBackdropColor(c[1] * 0.16, c[2] * 0.16, c[3] * 0.16, 0.98)
        automationPill:SetBackdropBorderColor(c[1], c[2], c[3], 0.75)
        automationPill.label:SetTextColor(c[1], c[2], c[3], 1)
    end
    EbonBuilds.MainWindow.SetDirtyState(currentDirty)
end

function EbonBuilds.MainWindow.Init()
    local frame = BuildFrame()
    local left  = CreateLeftColumn(frame)
    local right = CreateRightPanel(frame)

    EbonBuilds.MainWindow._frame = frame
    EbonBuilds.MainWindow._left  = left
    EbonBuilds.MainWindow._right = right

    EbonBuilds.ViewRouter.SetContainer(right)
    frame:SetScript("OnShow", EbonBuilds.MainWindow.RefreshContext)
    if EbonBuilds.Build and EbonBuilds.Build.OnActiveChanged then
        EbonBuilds.Build.OnActiveChanged(EbonBuilds.MainWindow.RefreshContext)
    end
    EbonBuilds.MainWindow.RefreshContext()
    EbonBuilds.BuildList.Init(left)
    EbonBuilds.WeightsView.Init()
    EbonBuilds.BuildForm.Init()
    EbonBuilds.SettingsView.Init()
    EbonBuilds.BuildTabs.Init()
    EbonBuilds.BuildOverview.Init()
    EbonBuilds.PublicBuildsView.Init()

    EbonBuilds.ViewRouter.Register("welcome", {
        Show = function(container, _)
            EbonBuilds.WelcomeView.Mount(container)
        end,
        Hide = function()
            EbonBuilds.WelcomeView.Unmount()
        end,
    })

    EbonBuilds.ViewRouter.Register("publicBuilds", {
        Show = function(container, _)
            EbonBuilds.PublicBuildsView.Mount(container)
        end,
        Hide = function()
            EbonBuilds.PublicBuildsView.Unmount()
        end,
    })

    EbonBuilds.ViewRouter.Register("tomeAtlas", {
        Show = function(container, _)
            EbonBuilds.TomeAtlasView.Show(container)
        end,
        Hide = function()
            EbonBuilds.TomeAtlasView.Hide()
        end,
    })

    EbonBuilds.ViewRouter.Register("affixes", {
        Show = function(container, _)
            EbonBuilds.AffixView.Show(container)
        end,
        Hide = function()
            EbonBuilds.AffixView.Hide()
        end,
    })

    EbonBuilds.MainWindow._ShowInitialView()
end

function EbonBuilds.MainWindow._ShowInitialView()
    local active = EbonBuilds.Build.GetActive()
    if active then
        EbonBuilds.ViewRouter.Show("buildOverview", { build = active })
    else
        EbonBuilds.ViewRouter.Show("welcome")
    end
end

SLASH_EbonBuilds1 = "/ebb"
SLASH_EbonBuilds2 = "/ebonbuilds"
SlashCmdList["EbonBuilds"] = function()
    EbonBuilds.MainWindow.Toggle()
end

function EbonBuilds.MainWindow.Toggle()
    local frame = EbonBuilds.MainWindow._frame
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        EbonBuilds.MainWindow._ShowInitialView()
        frame:Show()
    end
end

function EbonBuilds.MainWindow.GetRightPanel()
    return EbonBuilds.MainWindow._right
end
