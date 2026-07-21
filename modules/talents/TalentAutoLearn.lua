-- EbonBuilds: modules/talents/TalentAutoLearn.lua
-- Decides which talent to spend the next available point on, based on the
-- active build's saved talent plan (see Talents.lua). Deliberately split
-- from the actual game-mutating call site: ComputeNextTalent() is a pure
-- decision function (given an injected "read current state" function),
-- fully unit-testable without touching LearnTalent at all.
--
-- Two operating modes per build (build.talentAutoLearnMode):
--   "off"     -- default. Never touches talent points automatically.
--   "confirm" -- shows a confirmation popup for each point; nothing is
--                spent without the player clicking Accept.
--   "auto"    -- spends the point immediately, no prompt.
-- Talent points are a meaningfully costly, hard-to-casually-undo choice
-- (a respec costs real gold), so "confirm" -- not "auto" -- is the
-- sensible default whenever a plan exists and auto-learn is turned on at
-- all; "auto" is opt-in on top of that.

EbonBuilds.TalentAutoLearn = {}

-- Walks the plan's tabs/talents in a fixed, deterministic order (tab 1-3,
-- then ascending talent index within each tab -- which follows Blizzard's
-- own tier/column layout) and returns the FIRST point that:
--   1. the plan wants at a higher rank than the player currently has, and
--   2. the player is currently eligible to spend a point on (prereqs met,
--      not already at max rank).
-- `readCurrent(tabIndex, talentIndex)` must return
--   name, currentRank, maxRank, available
-- Returns nil if nothing eligible right now (either the plan is fully
-- satisfied, or the only remaining wanted talents are gated behind tiers
-- the player hasn't unlocked yet -- in which case this will naturally
-- start returning a candidate once an earlier tier is filled in).
function EbonBuilds.TalentAutoLearn.ComputeNextTalent(planTabs, readCurrent)
    if not planTabs or type(readCurrent) ~= "function" then return nil end
    for tabIndex = 1, 3 do
        local planTab = planTabs[tabIndex]
        if planTab and planTab.ranks then
            local indices = {}
            for idx in pairs(planTab.ranks) do indices[#indices + 1] = idx end
            table.sort(indices)
            for _, talentIndex in ipairs(indices) do
                local wantRank = planTab.ranks[talentIndex]
                local name, currentRank, maxRank, available = readCurrent(tabIndex, talentIndex)
                currentRank = currentRank or 0
                if name and wantRank > currentRank and available and (not maxRank or currentRank < maxRank) then
                    return {
                        tabIndex = tabIndex, talentIndex = talentIndex, name = name,
                        fromRank = currentRank, toRank = currentRank + 1, wantRank = wantRank,
                    }
                end
            end
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Live wiring
------------------------------------------------------------------------

local function RealReadCurrent(tabIndex, talentIndex)
    local name, _, _, _, currentRank, maxRank, _, available = GetTalentInfo(tabIndex, talentIndex)
    return name, currentRank, maxRank, available
end

local function DoLearn(candidate)
    LearnTalent(candidate.tabIndex, candidate.talentIndex)
    EbonBuilds.Toast.Show(string.format("Auto-learned %s (rank %d)", candidate.name, candidate.toRank))
end

local function MaybePrompt()
    -- Ask the UI itself whether our popup is showing, rather than tracking
    -- a local flag: a flag only reset in OnAccept/OnCancel can get stuck
    -- true forever if the dialog is ever dismissed some other way (another
    -- addon force-closing popups, a taint edge case, etc.), which would
    -- silently disable confirm-mode for the rest of the session with no
    -- error. StaticPopup_Visible can't desync from reality the way a
    -- hand-maintained flag can.
    if StaticPopup_Visible and StaticPopup_Visible("EBONBUILDS_CONFIRM_LEARN_TALENT") then return end
    local build = EbonBuilds.Build.GetActive()
    if not build or not build.talents or not build.talents.tabs then return end
    local mode = build.talentAutoLearnMode or "off"
    if mode == "off" then return end
    if not GetUnspentTalentPoints or GetUnspentTalentPoints() <= 0 then return end

    local candidate = EbonBuilds.TalentAutoLearn.ComputeNextTalent(build.talents.tabs, RealReadCurrent)
    if not candidate then return end

    if mode == "auto" then
        DoLearn(candidate)
        return
    end

    -- mode == "confirm"
    StaticPopupDialogs["EBONBUILDS_CONFIRM_LEARN_TALENT"] = {
        text = string.format("Learn %s (rank %d)?\nFrom this build's saved talent plan.", candidate.name, candidate.toRank),
        button1 = "Learn it",
        button2 = "Not now",
        OnAccept = function()
            DoLearn(candidate)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("EBONBUILDS_CONFIRM_LEARN_TALENT")
end

function EbonBuilds.TalentAutoLearn.Init()
    local f = CreateFrame("Frame")
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(f, "TalentAutoLearn.EventFrame")
    end
    f:RegisterEvent("CHARACTER_POINTS_CHANGED")
    f:RegisterEvent("PLAYER_TALENT_UPDATE")
    f:SetScript("OnEvent", MaybePrompt)
end

-- Exported for unit testing
EbonBuilds.TalentAutoLearn._MaybePrompt = MaybePrompt
