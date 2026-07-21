-- EbonBuilds: core/Init.lua
-- Responsibility: addon bootstrap, saved-variable initialisation, module wiring.

EbonBuilds = EbonBuilds or {}
EbonBuilds.VERSION = "3.53"

local eventFrame = CreateFrame("Frame")

local function OnAddonLoaded(addonName)
    if addonName ~= "EbonBuilds" then return end

    if not ProjectEbonhold then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff4444EbonBuilds:|r ProjectEbonhold not found -- EbonBuilds requires it and will stay disabled. " ..
            "Make sure ProjectEbonhold (or ProjectEbonholdEnhanced) is installed and enabled.")
        return
    end

    -- Each module's Init() runs isolated: this file is the one place where
    -- a single module failing to initialize could otherwise take every
    -- module listed after it down with it (an uncaught error here doesn't
    -- just skip one handler call like ProtectScript -- it stops this
    -- whole function). EbonBuilds.Debug is guaranteed loaded by the time
    -- this runs (ADDON_LOADED only fires after the full TOC has loaded),
    -- even though core/Init.lua itself is always the first file loaded.
    local function SafeInit(name, fn)
        local ok, err = pcall(fn)
        if not ok and EbonBuilds.ErrorLog then
            EbonBuilds.ErrorLog.Record("Init." .. name, err)
        end
    end

    SafeInit("Database", function() EbonBuilds.Database.Init() end)
    EbonBuildsDB.minimapAngle = EbonBuildsDB.minimapAngle or 220
    EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
    EbonBuildsDB.globalSettings.evalDelay     = EbonBuildsDB.globalSettings.evalDelay     or 2
    EbonBuildsDB.globalSettings.toastDuration = EbonBuildsDB.globalSettings.toastDuration or 3
    EbonBuildsDB.globalSettings.uiScale       = EbonBuildsDB.globalSettings.uiScale       or 1

    SafeInit("Locale", function() EbonBuilds.Locale.Init() end)
    SafeInit("DebugLog", function() EbonBuilds.DebugLog.Init() end)
    SafeInit("ClickTrace", function() EbonBuilds.ClickTrace.Init() end)

    if EbonBuilds.EchoCatalog and EbonBuilds.EchoCatalog.Init then
        SafeInit("EchoCatalog", function() EbonBuilds.EchoCatalog.Init() end)
    end
    if EbonBuilds.EchoEligibilityEvidence and EbonBuilds.EchoEligibilityEvidence.Init then
        SafeInit("EchoEligibilityEvidence", function() EbonBuilds.EchoEligibilityEvidence.Init() end)
    end
    SafeInit("Build.Migrate", function() EbonBuilds.Build.Migrate() end)
    SafeInit("RecommendationService", function() EbonBuilds.RecommendationService.Init() end)
    SafeInit("Aggregates", function() EbonBuilds.Aggregates.Init() end)
    SafeInit("Session", function() EbonBuilds.Session.Init() end)
    SafeInit("SessionHistory", function() EbonBuilds.SessionHistory.Init() end)
    SafeInit("Weights", function() EbonBuilds.Weights.Init() end)
    SafeInit("Toast", function() EbonBuilds.Toast.Init() end)
    SafeInit("WelcomeView", function() EbonBuilds.WelcomeView.Init() end)
    SafeInit("BonusView", function() EbonBuilds.BonusView.Init() end)
    SafeInit("BuildWizard", function() EbonBuilds.BuildWizard.Init() end)
    SafeInit("MinimapButton", function() EbonBuilds.MinimapButton.Init() end)
    SafeInit("MainWindow", function() EbonBuilds.MainWindow.Init() end)
    SafeInit("Automation", function() EbonBuilds.Automation.Init() end)
    SafeInit("Sync", function() EbonBuilds.Sync.Init() end)
    SafeInit("TomeAtlas", function() EbonBuilds.TomeAtlas.Init() end)
    SafeInit("Affix", function() EbonBuilds.Affix.Init() end)
    SafeInit("ChatLink", function() EbonBuilds.ChatLink.Init() end)
    SafeInit("TalentAutoLearn", function() EbonBuilds.TalentAutoLearn.Init() end)
    SafeInit("BagAffixDots", function() EbonBuilds.BagAffixDots.Init() end)
    SafeInit("AutoSell", function() EbonBuilds.AutoSell.Init() end)
    SafeInit("EchoPerformance", function() EbonBuilds.EchoPerformance.Init() end)
    SafeInit("GearTooltip", function() EbonBuilds.GearTooltip.Init() end)
    SafeInit("LoginPanel", function() EbonBuilds.LoginPanel.Init() end)
    SafeInit("WorldIntegration", function() EbonBuilds.WorldIntegration.Init() end)
    SafeInit("ManualTraining", function() EbonBuilds.ManualTraining.Init() end)
    SafeInit("Calibration", function() EbonBuilds.Calibration.Init() end)
    SafeInit("FAQ.MaybeAnnounceUpdate", function() EbonBuilds.FAQ.MaybeAnnounceUpdate() end)
    SafeInit("ShowcaseView.MaybeShowFirstLogin", function() EbonBuilds.ShowcaseView.MaybeShowFirstLogin() end)
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(...)
    end
end)
