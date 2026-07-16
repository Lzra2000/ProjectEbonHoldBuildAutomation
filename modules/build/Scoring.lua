-- EbonBuilds: modules/build/Scoring.lua
-- Responsibility: compute echo scores and the class peak from a settings
-- table. Pure — no UI, no SavedVariables mutation.

EbonBuilds.Scoring = {}

local CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

-- Normalize family tokens produced by ProjectEbonhold to the 6 canonical keys
-- used in settings.familyBonus.
local FAMILY_MAP = {
    Tank = "Tank", Survivability = "Survivability", Healer = "Healer",
    Caster = "Caster", ["Caster DPS"] = "Caster",
    Melee  = "Melee",  ["Melee DPS"]  = "Melee",
    Ranged = "Ranged", ["Ranged DPS"] = "Ranged",
    None   = "No family",
}

local function NormFamily(f) return FAMILY_MAP[f] end

local function ApplyModifier(score, baseWeight, value, multiplicative)
    if multiplicative then
        if value == 0 then return score end
        return score + baseWeight * (value - 1)
    else
        return score + value
    end
end

local function ApplyFamilyBonuses(s, base, entry, fb, fm, wl)
    local hasWhitelist = false
    for _ in pairs(wl) do hasWhitelist = true; break end

    if entry.families and #entry.families > 0 then
        for i = 1, #entry.families do
            local key = NormFamily(entry.families[i])
            if key and (not hasWhitelist or wl[key]) then
                s = ApplyModifier(s, base, fb[key] or 0, fm[key])
            end
        end
    else
        if not hasWhitelist or wl["No family"] then
            s = ApplyModifier(s, base, fb["No family"] or 0, fm["No family"])
        end
    end
    return s
end

function EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, quality)
    local qb = settings.qualityBonus or {}
    local qm = settings.qualityBonusMode or {}
    local fb = settings.familyBonus  or {}
    local fm = settings.familyBonusMode or {}
    local wl = settings.banishFamilyWhitelist or {}
    local base = weight or 0
    local s = base

    s = ApplyModifier(s, base, qb[quality] or 0, qm[quality])
    s = ApplyFamilyBonuses(s, base, entry, fb, fm, wl)
    return s
end

function EbonBuilds.Scoring.Score(entry, weight, settings)
    local s = EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, entry.quality)
    local base = weight or 0
    s = ApplyModifier(s, base, settings.noveltyValue or 0, settings.noveltyMode)
    return s
end

local function MatchesClass(entry, bitVal)
    if not bitVal then return true end
    if not entry.classMask or entry.classMask == 0 then return true end
    return bit.band(entry.classMask, bitVal) ~= 0
end

-- weightFn is optional: a function(echoName) -> number, used instead of the
-- saved EbonBuilds.Weights table. Lets callers (e.g. the build wizard) preview
-- a peak score against weights that haven't been saved yet.
--
-- The peak deliberately EXCLUDES the novelty bonus: novelty is a transient
-- per-echo bonus that disappears once an echo has been picked. Including it
-- would inflate the reference scale at run start and make percentage
-- thresholds (banish/reroll/freeze) progressively unreachable as the run
-- consumes novelty.
function EbonBuilds.Scoring.ComputePeak(classToken, settings, weightFn)
    if not settings then return nil, 0 end
    local list = EbonBuilds.EchoTableRows.BuildSortedList()
    local bitVal = classToken and CLASS_BITS[classToken]
    local getWeight = weightFn or EbonBuilds.Weights.Get
    local bestName, bestScore = nil, nil
    for i = 1, #list do
        local e = list[i]
        if MatchesClass(e, bitVal) then
            local w  = getWeight(e.name) or 0
            local sc = EbonBuilds.Scoring.ScorePerQuality(e, w, settings, e.quality)
            if bestScore == nil or sc > bestScore then
                bestScore, bestName = sc, e.name
            end
        end
    end
    return bestName, bestScore or 0
end

-- Expected value of the BEST of 3 uniformly random (echo, quality) outcomes
-- for the given class -- i.e. what an average reroll's best offer is worth.
-- Exact closed form: for outcome scores sorted ascending s_1..s_n,
-- P(max = s_i) = (i^3 - (i-1)^3) / n^3, so EV = sum s_i * that.
-- Used by the "smart reroll" mode: reroll when the current best offer is
-- worse than a configurable fraction of this value.
-- One pass over all (echo, quality) outcomes for the class:
--   mean    = E[score of ONE random offer]   (banish reference: a banished
--             card is replaced by exactly one random new card)
--   evBest3 = E[best of 3 random offers]     (reroll/freeze reference)
function EbonBuilds.Scoring.ComputeOutcomeStats(classToken, settings, weightFn)
    if not settings then return { mean = 0, evBest3 = 0 } end
    local list = EbonBuilds.EchoTableRows.BuildSortedList()
    local bitVal = classToken and CLASS_BITS[classToken]
    local getWeight = weightFn or EbonBuilds.Weights.Get

    local outcomes = {}
    for i = 1, #list do
        local e = list[i]
        if MatchesClass(e, bitVal) then
            local w = getWeight(e.name) or 0
            -- Every quality tier the echo can drop at is its own outcome.
            local any = false
            if e.qualities then
                for q = 0, 4 do
                    if e.qualities[q] then
                        outcomes[#outcomes + 1] = EbonBuilds.Scoring.ScorePerQuality(e, w, settings, q)
                        any = true
                    end
                end
            end
            if not any then
                outcomes[#outcomes + 1] = EbonBuilds.Scoring.ScorePerQuality(e, w, settings, e.quality or 0)
            end
        end
    end

    local n = #outcomes
    if n == 0 then return { mean = 0, evBest3 = 0 } end
    table.sort(outcomes)

    local sum = 0
    local n3 = n * n * n
    local ev = 0
    for i = 1, n do
        sum = sum + outcomes[i]
        ev = ev + outcomes[i] * ((i * i * i) - ((i - 1) * (i - 1) * (i - 1)))
    end
    return { mean = sum / n, evBest3 = ev / n3 }
end

function EbonBuilds.Scoring.ComputeRerollEV(classToken, settings, weightFn)
    return EbonBuilds.Scoring.ComputeOutcomeStats(classToken, settings, weightFn).evBest3
end

function EbonBuilds.Scoring.GetEffectiveLockedEchoes()
    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingLockedEchoes then
        local p = EbonBuilds.BuildForm.GetEditingLockedEchoes()
        if p then return p end
    end
    local build = EbonBuilds.Build.GetActive()
    if build and build.lockedEchoes then return build.lockedEchoes end
    return { nil, nil, nil, nil, nil, nil }
end

function EbonBuilds.Scoring.IsLocked(spellId)
    if not spellId then return false end
    local lockeds = EbonBuilds.Scoring.GetEffectiveLockedEchoes()
    if not lockeds then return false end
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        if lockeds[i] and lockeds[i] == spellId then
            return true
        end
    end
    return false
end

function EbonBuilds.Scoring.IsBanned(spellId)
    if not spellId then return false end
    local settings = EbonBuilds.Scoring.GetEffectiveSettings()
    local banList = settings and settings.echoBanList
    return banList and banList[spellId] and true or false
end

function EbonBuilds.Scoring.GetEffectiveSettings()
    if EbonBuilds.ViewRouter and EbonBuilds.ViewRouter.Current() == "buildTabs" then
        if EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingSettings then
            local s = EbonBuilds.BuildForm.GetEditingSettings()
            if s then return s end
        end
    end
    local build = EbonBuilds.Build.GetActive()
    if build and build.settings then return build.settings end
    return EbonBuilds.Build.DefaultSettings()
end
