local addonName, EbonBuilds = ...

-- EbonBuilds: modules/ui/WelcomeView.lua
-- Responsibility: empty-state welcome screen shown when no builds exist.
-- Exposes Mount/Unmount. Registered as the "welcome" view.

EbonBuilds.WelcomeView = {}


local L = EbonBuilds.L
local viewFrame

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)

    local card = CreateFrame("Frame", nil, f)
    card:SetPoint("TOP", f, "TOP", 0, -70)
    card:SetSize(520, 430)
    EbonBuilds.Theme.ApplyCard(card)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(64)
    icon:SetHeight(64)
    icon:SetPoint("TOP", card, "TOP", 0, -34)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -16)
    title:SetText(L["No Builds Yet"])

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -8)
    sub:SetText(L["Create a build to automate Echo choices, or start from a shared community build."])
    sub:SetWidth(430)
    sub:SetJustifyH("CENTER")
    sub:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))

    local newBtn = EbonBuilds.Theme.CreateButton(f, "gold")
    newBtn:SetWidth(140)
    newBtn:SetHeight(28)
    newBtn:SetPoint("TOP", sub, "BOTTOM", 0, -24)
    newBtn:SetText(L["+ New Build"])
    newBtn:SetScript("OnClick", function()
        EbonBuilds.ViewRouter.Show("buildWizard")
    end)

    local publicBtn = EbonBuilds.Theme.CreateButton(f)
    publicBtn:SetWidth(140)
    publicBtn:SetHeight(28)
    publicBtn:SetPoint("TOP", newBtn, "BOTTOM", 0, -8)
    publicBtn:SetText(L["Public Builds"])
    publicBtn:SetScript("OnClick", function()
        EbonBuilds.ViewRouter.Show("publicBuilds")
    end)

    -- Getting-started guide
    local guideHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guideHeader:SetPoint("TOP", publicBtn, "BOTTOM", 0, -28)
    guideHeader:SetText(L["Getting started"])

    local steps = {
        "|cffffd2001.|r  " .. L["Choose a class and locked Echoes, then give each available quality rank a value."],
        "|cffffd2002.|r  " .. L["Set priorities, then choose an Autopilot intent such as Balanced or Chase upgrades."],
        "|cffffd2003.|r  " .. L["Play normally. Review each automated decision later in the Logbook."],
    }
    local anchor = guideHeader
    for _, text in ipairs(steps) do
        local line = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOP", anchor, "BOTTOM", 0, -8)
        line:SetWidth(420)
        line:SetJustifyH("LEFT")
        line:SetText(text)
        anchor = line
    end

    return f
end

local function EnsureBuilt(container)
    if viewFrame then return end
    viewFrame = BuildViewFrame(container)
end

function EbonBuilds.WelcomeView.Mount(container)
    EnsureBuilt(container)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)
    viewFrame:Show()
end

function EbonBuilds.WelcomeView.Unmount()
    if not viewFrame then return end
    viewFrame:Hide()
end

function EbonBuilds.WelcomeView.Init()
end
