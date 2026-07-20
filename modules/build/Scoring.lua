-- EbonBuilds: modules/build/Scoring.lua
-- Responsibility: compute echo scores and the class peak from a settings
-- table. Pure — no UI, no SavedVariables mutation.

EbonBuilds.Scoring = {}

local CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

-- Family normalization lives in modules/data/Families.lua -- the single
-- source of truth for canonical ids and catalog variants. Runtime
-- lookup (not a file-scope alias) so load order stays a non-issue.
local function NormFamily(f) return EbonBuilds.Families.Normalize(f) end

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

-- weightFn is optional: a function(echoName, quality) -> number, used instead of the
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
            -- Rank-specific weights mean the highest-quality version is not
            -- necessarily the highest-scoring version. Consider every rank
            -- this Echo can actually roll so percentage thresholds use the
            -- true attainable peak.
            local any = false
            if e.qualities then
                for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
                    if e.qualities[quality] then
                        local weight = getWeight(e.name, quality) or 0
                        local score = EbonBuilds.Scoring.ScorePerQuality(e, weight, settings, quality)
                        if bestScore == nil or score > bestScore then
                            bestScore, bestName = score, e.name
                        end
                        any = true
                    end
                end
            end
            if not any then
                local quality = e.quality or 0
                local weight = getWeight(e.name, quality) or 0
                local score = EbonBuilds.Scoring.ScorePerQuality(e, weight, settings, quality)
                if bestScore == nil or score > bestScore then
                    bestScore, bestName = score, e.name
                end
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
            -- Every quality tier the echo can drop at is its own outcome.
            local any = false
            if e.qualities then
                for _, q in ipairs(EbonBuilds.Quality.ORDER or {}) do
                    if e.qualities[q] then
                        local rankWeight = getWeight(e.name, q) or 0
                        outcomes[#outcomes + 1] = EbonBuilds.Scoring.ScorePerQuality(e, rankWeight, settings, q)
                        any = true
                    end
                end
            end
            if not any then
                local fallbackQuality = e.quality or 0
                local fallbackWeight = getWeight(e.name, fallbackQuality) or 0
                outcomes[#outcomes + 1] = EbonBuilds.Scoring.ScorePerQuality(e, fallbackWeight, settings, fallbackQuality)
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

function EbonBuilds.Scoring.IsWhitelisted(value, settings)
    if value == nil then return false end
    settings = settings or EbonBuilds.Scoring.GetEffectiveSettings()
    local whitelist = settings and settings.echoWhitelist
    if type(whitelist) ~= "table" then return false end

    local name
    if type(value) == "number" or (type(value) == "string" and value:match("^%d+$")) then
        name = EbonBuilds.Weights.CanonicalName(tonumber(value))
    else
        name = EbonBuilds.Weights.StripQualitySuffix(tostring(value))
    end
    return name and whitelist[name] and true or false
end

function EbonBuilds.Scoring.IsBanned(spellId, settings)
    if not spellId then return false end
    settings = settings or EbonBuilds.Scoring.GetEffectiveSettings()
    if EbonBuilds.Scoring.IsWhitelisted(spellId, settings) then return false end
    local banList = settings and settings.echoBanList
    return banList and (banList[spellId] or banList[tostring(spellId)]) and true or false
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
