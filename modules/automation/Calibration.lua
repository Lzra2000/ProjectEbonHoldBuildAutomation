-- EbonBuilds: modules/automation/Calibration.lua
-- Self-calibrating threshold advisor.
--
-- Automation's banish/reroll thresholds are set as a % of a THEORETICAL
-- peak/mean computed from the build's own scoring weights (Scoring.lua).
-- That's a reasonable starting point, but it says nothing about what
-- you're ACTUALLY being offered on this server, with this build's real
-- weight tuning, over hundreds of picks. This module records the score of
-- every echo actually offered (as a % of that evaluation's peak) into a
-- persistent, capped sample buffer, then answers "if I want the banish
-- threshold to reject roughly the bottom N% of what I'm really offered,
-- what value should that be?" from the real observed distribution instead
-- of the theoretical one.
--
-- Currently supports Classic threshold mode only (autoBanishPct /
-- autoRerollPct, both % of peak) -- Smart EV mode's thresholds are a %
-- of mean/EV instead of peak, a different baseline that would need a
-- separate conversion; out of scope for this first version.

EbonBuilds.Calibration = {}

local MAX_SAMPLES = 2000
local MIN_SAMPLES_FOR_SUGGESTION = 30

local function GetStore()
    EbonBuildsCharDB.calibration = EbonBuildsCharDB.calibration or {}
    EbonBuildsCharDB.calibration.samples = EbonBuildsCharDB.calibration.samples or {}
    return EbonBuildsCharDB.calibration.samples
end

-- Called once per offered echo during automation evaluation, with its
-- score as a percentage of that evaluation's peak (0-100+, can exceed
-- 100 for an echo scored above the cached peak). Cheap: no sorting or
-- analysis happens here, just an append + cap.
function EbonBuilds.Calibration.RecordSample(pct)
    if not pct or pct < 0 then return end
    local store = GetStore()
    store[#store + 1] = pct
    if #store > MAX_SAMPLES then
        table.remove(store, 1)
    end
end

function EbonBuilds.Calibration.SampleCount()
    return #GetStore()
end

function EbonBuilds.Calibration.Clear()
    EbonBuildsCharDB.calibration = EbonBuildsCharDB.calibration or {}
    EbonBuildsCharDB.calibration.samples = {}
end

-- Value at the given percentile (0-100) of an already-sorted list.
local function Percentile(sorted, p)
    if #sorted == 0 then return 0 end
    local idx = math.max(1, math.min(#sorted, math.ceil(p / 100 * #sorted)))
    return sorted[idx]
end

-- What % of samples fall strictly below a given threshold value.
local function FractionBelow(sorted, threshold)
    if #sorted == 0 then return 0 end
    local count = 0
    for _, v in ipairs(sorted) do
        if v < threshold then count = count + 1 end
    end
    return count / #sorted * 100
end

local function BuildSuggestion(currentPct, targetFraction)
    local store = GetStore()
    local result = { sampleCount = #store, currentPct = currentPct, targetFraction = targetFraction }
    if #store < MIN_SAMPLES_FOR_SUGGESTION then
        result.insufficientData = true
        return result
    end
    local sorted = {}
    for i, v in ipairs(store) do sorted[i] = v end
    table.sort(sorted)

    result.currentFraction = FractionBelow(sorted, currentPct)
    result.suggestedPct = Percentile(sorted, targetFraction)
    return result
end

-- settings: a build's effective scoring settings (EbonBuilds.Scoring.GetEffectiveSettings()).
-- Target: reject roughly the bottom 15% of what's actually offered.
function EbonBuilds.Calibration.SuggestBanish(settings)
    return BuildSuggestion(settings.autoBanishPct or 0, 15)
end

-- Target: reroll offers that land in the bottom ~45% (i.e. only keep
-- offers that are at or above roughly the middle of what you actually see).
-- A per-echo percentile is a proxy for the real sum-of-three check
-- Automation.lua uses, not an exact match, but directionally useful.
function EbonBuilds.Calibration.SuggestReroll(settings)
    return BuildSuggestion(settings.autoRerollPct or 0, 45)
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local function ApplySuggestion(field, value)
    local build = EbonBuilds.Build.GetActive()
    if not build then return false end
    local settings = EbonBuilds.Build.CloneSettings(build.settings or EbonBuilds.Build.DefaultSettings())
    settings[field] = math.floor(value + 0.5)
    local saved = EbonBuilds.Build.Save(build.id, { settings = settings })
    return saved ~= nil
end

local frame, countLabel, modeWarning
local banishRow, rerollRow

local function BuildRow(parent, yOffset, label)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOffset)
    title:SetText(label)

    local current = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    current:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    current:SetWidth(480)
    current:SetJustifyH("LEFT")

    local suggestion = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    suggestion:SetPoint("TOPLEFT", current, "BOTTOMLEFT", 0, -4)
    suggestion:SetWidth(400)
    suggestion:SetJustifyH("LEFT")

    local applyBtn = EbonBuilds.Theme.CreateButton(parent)
    applyBtn:SetSize(90, 20)
    applyBtn:SetPoint("LEFT", suggestion, "RIGHT", 8, 0)

    return { title = title, current = current, suggestion = suggestion, applyBtn = applyBtn }
end

local function RefreshRow(row, result, field, unitLabel)
    if result.insufficientData then
        row.current:SetText(string.format("|cff888888Collecting data... (%d / %d samples needed)|r",
            result.sampleCount, MIN_SAMPLES_FOR_SUGGESTION))
        row.suggestion:SetText("")
        row.applyBtn:Hide()
        return
    end
    row.current:SetText(string.format("Current: %.0f%% of peak -- rejects ~%.0f%% of what you're actually offered (%d samples)",
        result.currentPct, result.currentFraction, result.sampleCount))
    if math.abs(result.suggestedPct - result.currentPct) < 1 then
        row.suggestion:SetText(string.format("|cff1eff00Already close to the %s target (~%.0f%%).|r", unitLabel, result.targetFraction))
        row.applyBtn:Hide()
    else
        row.suggestion:SetText(string.format("Suggested: |cffffd100%.0f%%|r to target ~%.0f%% rejected",
            result.suggestedPct, result.targetFraction))
        row.applyBtn:SetText(string.format("Apply %.0f%%", result.suggestedPct))
        row.applyBtn:Show()
        row.applyBtn:SetScript("OnClick", function()
            if ApplySuggestion(field, result.suggestedPct) then
                EbonBuilds.Toast.Show(string.format("%s threshold set to %.0f%%", unitLabel, result.suggestedPct))
                EbonBuilds.Calibration.RefreshWindow()
            end
        end)
    end
end

local function BuildWindow()
    local f = CreateFrame("Frame", "EbonBuildsTuningAdvisorWindow", UIParent)
    f:SetSize(560, 300)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    EbonBuilds.Theme.ApplyWindow(f)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("EbonBuilds Tuning Advisor")

    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, 0)
    drag:SetHeight(28)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -38)
    subtitle:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Compares your current thresholds against what your build actually gets offered, and suggests values based on the real distribution instead of the theoretical scoring model.")
    subtitle:SetHeight(28)

    modeWarning = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    modeWarning:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -6)
    modeWarning:SetWidth(500)
    modeWarning:SetJustifyH("LEFT")
    modeWarning:SetTextColor(1, 0.6, 0.2, 1)

    banishRow = BuildRow(f, -160, "Banish")
    rerollRow = BuildRow(f, -220, "Reroll")

    local clearBtn = EbonBuilds.Theme.CreateButton(f, "danger")
    clearBtn:SetSize(140, 20)
    clearBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
    clearBtn:SetText("Clear Collected Data")
    clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Wipes recorded samples. Worth doing after a major reweight, since old samples reflect the previous weighting.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    clearBtn:SetScript("OnClick", function()
        EbonBuilds.Calibration.Clear()
        EbonBuilds.Calibration.RefreshWindow()
    end)

    countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countLabel:SetPoint("BOTTOM", f, "BOTTOM", 0, 18)

    tinsert(UISpecialFrames, "EbonBuildsTuningAdvisorWindow")
    f:Hide()
    return f
end

function EbonBuilds.Calibration.RefreshWindow()
    if not frame then return end
    local build = EbonBuilds.Build.GetActive()
    if not build then
        modeWarning:SetText("No active build selected.")
        banishRow.current:SetText("")
        banishRow.suggestion:SetText("")
        banishRow.applyBtn:Hide()
        rerollRow.current:SetText("")
        rerollRow.suggestion:SetText("")
        rerollRow.applyBtn:Hide()
        countLabel:SetText("")
        return
    end
    local settings = build.settings or EbonBuilds.Build.DefaultSettings()
    if (settings.rerollMode or "sum") == "ev" then
        modeWarning:SetText("This build uses Smart (EV) mode. The Tuning Advisor currently only supports Classic threshold mode (% of peak) -- switch modes in the Automation tab to use it.")
        banishRow.current:SetText("")
        banishRow.suggestion:SetText("")
        banishRow.applyBtn:Hide()
        rerollRow.current:SetText("")
        rerollRow.suggestion:SetText("")
        rerollRow.applyBtn:Hide()
    else
        modeWarning:SetText("")
        RefreshRow(banishRow, EbonBuilds.Calibration.SuggestBanish(settings), "autoBanishPct", "Banish")
        RefreshRow(rerollRow, EbonBuilds.Calibration.SuggestReroll(settings), "autoRerollPct", "Reroll")
    end
    countLabel:SetText(string.format("%d total samples collected for %s", EbonBuilds.Calibration.SampleCount(), build.title or "this build"))
end

function EbonBuilds.Calibration.ShowWindow()
    if not frame then frame = BuildWindow() end
    EbonBuilds.Calibration.RefreshWindow()
    frame:Show()
end
