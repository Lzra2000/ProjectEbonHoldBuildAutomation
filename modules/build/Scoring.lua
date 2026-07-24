local addonName, EbonBuilds = ...

-- EbonBuilds: modules/build/Scoring.lua
-- Responsibility: compute echo scores and the class peak from a settings
-- table. Pure — no UI, no SavedVariables mutation.

EbonBuilds.Scoring = {}

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
    local list = EbonBuilds.EchoProjection.GetAvailable(classToken)
    local build = EbonBuilds.Build.GetActive()
    local bestName, bestScore = nil, nil
    local function GetWeight(entry, quality)
        if weightFn then
            local value = weightFn(entry.refKey, quality, entry)
            if value == nil then value = weightFn(entry.displayName or entry.name, quality, entry) end
            return tonumber(value) or 0
        end
        return EbonBuilds.Weights.GetForRef(build, entry.refKey, quality) or 0
    end
    for i = 1, #list do
        local entry = list[i]
        for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
            if entry.qualities and entry.qualities[quality] then
                local score = EbonBuilds.Scoring.ScorePerQuality(entry, GetWeight(entry, quality), settings, quality)
                if bestScore == nil or score > bestScore then
                    bestScore, bestName = score, entry.displayName or entry.name
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
    local list = EbonBuilds.EchoProjection.GetAvailable(classToken)
    local build = EbonBuilds.Build.GetActive()
    local outcomes = {}
    local function GetWeight(entry, quality)
        if weightFn then
            local value = weightFn(entry.refKey, quality, entry)
            if value == nil then value = weightFn(entry.displayName or entry.name, quality, entry) end
            return tonumber(value) or 0
        end
        return EbonBuilds.Weights.GetForRef(build, entry.refKey, quality) or 0
    end
    for i = 1, #list do
        local entry = list[i]
        for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
            if entry.qualities and entry.qualities[quality] then
                outcomes[#outcomes + 1] = EbonBuilds.Scoring.ScorePerQuality(
                    entry, GetWeight(entry, quality), settings, quality)
            end
        end
    end
    local n = #outcomes
    if n == 0 then return { mean = 0, evBest3 = 0 } end
    table.sort(outcomes)
    local sum, ev, n3 = 0, 0, n * n * n
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
    local refKey = EbonBuilds.EchoPolicy and EbonBuilds.EchoPolicy.ReferenceKey(value)
    return refKey and whitelist[refKey] and true or false
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

------------------------------------------------------------------------
-- Deterministic automation tie-breaks (WP2 / #51). Shared by BoardDecision,
-- dry-run fixtures, and future server-policy validation. Primary score still
-- wins; when scores tie: optional server rank (lower integer wins when both
-- slots publish rank) -> slot index -> echo/spell ID -> frozen/carried pref.
------------------------------------------------------------------------

local TIE_HUGE = math.huge

local function CandidateEchoId(slot)
    if not slot then return TIE_HUGE end
    local id = tonumber(slot.spellId) or tonumber(slot.echoId)
    if id then return id end
    if type(slot.refKey) == "number" then return slot.refKey end
    return TIE_HUGE
end

local function CandidateIndex(slot)
    return tonumber(slot and slot.index) or TIE_HUGE
end

local function CandidateServerRank(slot)
    if not slot or slot.rank == nil then return nil end
    return tonumber(slot.rank)
end

local function CandidateFrozenWeight(slot)
    return slot and (slot.isFrozen or slot.isCarried) and 1 or 0
end

-- Negative when `a` outranks `b`, positive when `b` outranks `a`, zero when tied.
function EbonBuilds.Scoring.CompareCandidates(a, b, opts)
    opts = opts or {}
    if not a and not b then return 0 end
    if not a then return 1 end
    if not b then return -1 end

    local aScore = tonumber(a.score) or 0
    local bScore = tonumber(b.score) or 0
    if aScore ~= bScore then
        return bScore - aScore
    end

    local aRank = CandidateServerRank(a)
    local bRank = CandidateServerRank(b)
    if aRank ~= nil and bRank ~= nil and aRank ~= bRank then
        return aRank - bRank
    end

    local aIndex = CandidateIndex(a)
    local bIndex = CandidateIndex(b)
    if aIndex ~= bIndex then
        return aIndex - bIndex
    end

    local aId = CandidateEchoId(a)
    local bId = CandidateEchoId(b)
    if aId ~= bId then
        return aId - bId
    end

    if opts.preferFrozen then
        local aFrozen = CandidateFrozenWeight(a)
        local bFrozen = CandidateFrozenWeight(b)
        if aFrozen ~= bFrozen then
            return bFrozen - aFrozen
        end
    end

    return 0
end

function EbonBuilds.Scoring.IsBetterCandidate(a, b, opts)
    return EbonBuilds.Scoring.CompareCandidates(a, b, opts) < 0
end

function EbonBuilds.Scoring.IsWorseCandidate(a, b, opts)
    if not a then return false end
    if not b then return true end
    local aScore = tonumber(a.score) or 0
    local bScore = tonumber(b.score) or 0
    if aScore ~= bScore then return aScore < bScore end
    opts = opts or {}
    opts.preferFrozen = false
    return EbonBuilds.Scoring.CompareCandidates(a, b, opts) < 0
end
