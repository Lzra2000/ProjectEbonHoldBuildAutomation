-- EbonBuilds: modules/ui/WelcomeView.lua
-- Responsibility: empty-state welcome screen shown when no builds exist.
-- Exposes Mount/Unmount. Registered as the "welcome" view.

EbonBuilds.WelcomeView = {}

local viewFrame

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(64)
    icon:SetHeight(64)
    icon:SetPoint("TOP", f, "TOP", 0, -120)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -16)
    title:SetText("No Builds Yet")

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -8)
    sub:SetText("Create your first build or browse public builds.")

    local newBtn = EbonBuilds.Theme.CreateButton(f)
    newBtn:SetWidth(140)
    newBtn:SetHeight(28)
    newBtn:SetPoint("TOP", sub, "BOTTOM", 0, -24)
    newBtn:SetText("+ New Build")
    newBtn:SetScript("OnClick", function()
        EbonBuilds.ViewRouter.Show("buildWizard")
    end)

    local publicBtn = EbonBuilds.Theme.CreateButton(f)
    publicBtn:SetWidth(140)
    publicBtn:SetHeight(28)
    publicBtn:SetPoint("TOP", newBtn, "BOTTOM", 0, -8)
    publicBtn:SetText("Public Builds")
    publicBtn:SetScript("OnClick", function()
        EbonBuilds.ViewRouter.Show("publicBuilds")
    end)

    -- Getting-started guide
    local guideHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guideHeader:SetPoint("TOP", publicBtn, "BOTTOM", 0, -28)
    guideHeader:SetText("How it works:")

    local steps = {
        "|cffffd2001.|r  Create a build: pick locked echoes, rate the ones you want, set quality and family priorities.",
        "|cffffd2002.|r  Check the Automation tab: the thresholds decide when the addon banishes, rerolls, freezes, or picks for you.",
        "|cffffd2003.|r  Play. Every choice screen is handled by your build -- review decisions any time in the Logbook.",
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
