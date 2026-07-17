-- EbonBuilds: modules/automation/EchoPerformance.lua
-- Responsibility: correlate currently-active echoes with real combat
-- performance (DPS), using Details! damage meter's public API, if
-- installed. Off by default -- this is explicitly a rough, approximate
-- signal (echoes stack, execution/gear/fight-type vary run to run), not
-- a controlled measurement. Meant as a SUPPLEMENT to the theoretical
-- scoring model and Tuning Advisor's offer-distribution data, surfaced
-- through Export (AI) so an external AI has real performance context
-- too, not a replacement for either.
--
-- Everything that touches Details! is pcall-wrapped and feature-detected
-- -- it's a separate, large, independently-updated addon EbonBuilds does
-- not control, and its exact internals can change between versions. Only
-- the documented public API (Details:GetCurrentCombat, combat:GetActor,
-- actor.total, combat:GetCombatTime -- see Details' own API.lua) is used.

EbonBuilds.EchoPerformance = {}

local SAMPLE_INTERVAL = 10  -- seconds between DPS samples while in combat
local MAX_SAMPLES_PER_ECHO = 200

local function GetStore()
    EbonBuildsCharDB.echoPerformance = EbonBuildsCharDB.echoPerformance or {}
    return EbonBuildsCharDB.echoPerformance
end

function EbonBuilds.EchoPerformance.IsEnabled()
    return EbonBuildsCharDB.echoPerformanceEnabled == true
end

function EbonBuilds.EchoPerformance.SetEnabled(on)
    EbonBuildsCharDB.echoPerformanceEnabled = on and true or false
end

function EbonBuilds.EchoPerformance.IsDetailsAvailable()
    return Details ~= nil and Details.GetCurrentCombat ~= nil
end

function EbonBuilds.EchoPerformance.Clear()
    EbonBuildsCharDB.echoPerformance = {}
end

-- Current player DPS this combat, or nil if unavailable (not in combat,
-- Details not installed, or its API returned something unexpected --
-- any of which are just "no sample this tick", never an error).
local function GetCurrentDPS()
    if not EbonBuilds.EchoPerformance.IsDetailsAvailable() then return nil end
    local ok, dps = pcall(function()
        local combat = Details:GetCurrentCombat()
        if not combat then return nil end
        local playerName = UnitName("player")
        local actor = combat:GetActor(DETAILS_ATTRIBUTE_DAMAGE, playerName)
        if not actor or not actor.total then return nil end
        local combatTime = combat:GetCombatTime()
        if not combatTime or combatTime <= 0 then return nil end
        return actor.total / combatTime
    end)
    if ok and type(dps) == "number" and dps >= 0 then return dps end
    return nil
end

-- Records one DPS sample against every currently-granted (active this
-- run) echo. Called by the sample ticker; safe to call even if disabled
-- or Details isn't installed (both are no-ops).
function EbonBuilds.EchoPerformance.Sample()
    if not EbonBuilds.EchoPerformance.IsEnabled() then return end
    if not (ProjectEbonhold and ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetGrantedPerks) then return end
    local dps = GetCurrentDPS()
    if not dps then return end

    local granted = ProjectEbonhold.PerkService.GetGrantedPerks() or {}
    local store = GetStore()
    for name in pairs(granted) do
        local entry = store[name]
        if not entry then
            entry = { sum = 0, count = 0 }
            store[name] = entry
        end
        entry.sum = entry.sum + dps
        entry.count = entry.count + 1
        -- Cap by halving instead of dropping oldest one-by-one -- cheap,
        -- and keeps the running average meaningful rather than
        -- discarding history outright.
        if entry.count > MAX_SAMPLES_PER_ECHO then
            entry.sum = entry.sum / 2
            entry.count = math.floor(entry.count / 2)
        end
    end
end

-- Returns { avgDPS, sampleCount } for a given echo name, or nil if no
-- data has been collected for it.
function EbonBuilds.EchoPerformance.GetStats(name)
    local store = GetStore()
    local entry = store[name]
    if not entry or entry.count == 0 then return nil end
    return { avgDPS = entry.sum / entry.count, sampleCount = entry.count }
end

------------------------------------------------------------------------
-- Weight suggestions (read-only report, not auto-applied)
--
-- Compares each echo's average DPS against the average of OTHER echoes
-- that currently share its exact weight value (its "tier") -- notably
-- over/under-performing echoes within a tier are flagged with a small,
-- capped nudge suggestion. Deliberately NOT auto-applied like the
-- threshold Tuning Advisor: weight changes are a bigger, more visible
-- intervention, and this data is noisier (fight difficulty/duration
-- varies, and see EchoPerformance's co-active cluster limitation) --
-- this is meant to be read and judged, not blindly trusted.
--
-- Only echoes with a fully unique DPS+sample-count signature are
-- considered (MAX_CLUSTER_SIZE_TO_TRUST = 1). Originally this allowed
-- small clusters (up to 3) on the assumption that a couple of echoes
-- briefly overlapping was a coincidence -- real data showed 2-3 member
-- clusters are actually the common case (any two echoes active across
-- the same handful of fights end up sharing a signature), so most
-- "suggestions" at that looser threshold were really one data point
-- duplicated across indistinguishable echoes, not independent evidence.
------------------------------------------------------------------------

local MIN_SAMPLES_FOR_WEIGHT_SUGGESTION = 8  -- per-echo, before it's considered at all
local MIN_TIER_BASELINE_SIZE = 2             -- how many clean data points a tier needs to have a baseline
local MAX_CLUSTER_SIZE_TO_TRUST = 1          -- an echo's DPS signature must be unique (shared with nobody else) to be trusted for a weight suggestion
local WEIGHT_SUGGESTION_DEVIATION = 0.25     -- min fractional deviation from tier average to flag
local WEIGHT_NUDGE = 10                      -- fixed, modest suggested adjustment

local CLASS_MASK = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8,
    PRIEST = 16, DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128,
    WARLOCK = 256, DRUID = 1024,
}

-- Returns a sorted list of { name, currentWeight, suggestedWeight,
-- deviationPct, tierAvgDPS, avgDPS, sampleCount }, largest deviation
-- first. Empty list if there isn't enough clean data to say anything.
function EbonBuilds.EchoPerformance.SuggestWeightAdjustments(build)
    if not build or not build.class then return {} end
    if not (EbonBuilds.EchoTableRows and EbonBuilds.EchoTableRows.BuildBestByName) then return {} end
    local classMask = CLASS_MASK[build.class] or 0
    local weights = build.echoWeights or {}

    -- One pass: collect every class-eligible echo with enough samples,
    -- and count how many share an identical (avgDPS, sampleCount)
    -- signature (a co-active cluster -- can't be individually judged).
    local signatureCounts = {}
    local rawEntries = {}
    for name, info in pairs(EbonBuilds.EchoTableRows.BuildBestByName()) do
        if classMask == 0 or bit.band(info.classMask or 0, classMask) ~= 0 then
            local perf = EbonBuilds.EchoPerformance.GetStats(name)
            if perf and perf.sampleCount >= MIN_SAMPLES_FOR_WEIGHT_SUGGESTION then
                local sig = string.format("%.2f|%d", perf.avgDPS, perf.sampleCount)
                signatureCounts[sig] = (signatureCounts[sig] or 0) + 1
                rawEntries[#rawEntries + 1] = {
                    name = name,
                    weight = weights[name] or 0,
                    avgDPS = perf.avgDPS,
                    sampleCount = perf.sampleCount,
                    sig = sig,
                }
            end
        end
    end

    -- Tier baselines, computed only from entries NOT in a large cluster
    -- (so one inflated/deflated group doesn't skew the whole tier).
    local tierSum, tierCount = {}, {}
    for _, e in ipairs(rawEntries) do
        if signatureCounts[e.sig] <= MAX_CLUSTER_SIZE_TO_TRUST then
            tierSum[e.weight] = (tierSum[e.weight] or 0) + e.avgDPS
            tierCount[e.weight] = (tierCount[e.weight] or 0) + 1
        end
    end

    local suggestions = {}
    for _, e in ipairs(rawEntries) do
        local n = tierCount[e.weight] or 0
        if signatureCounts[e.sig] <= MAX_CLUSTER_SIZE_TO_TRUST and n >= MIN_TIER_BASELINE_SIZE then
            local tierAvg = tierSum[e.weight] / n
            if tierAvg > 0 then
                local deviation = (e.avgDPS - tierAvg) / tierAvg
                if math.abs(deviation) >= WEIGHT_SUGGESTION_DEVIATION then
                    suggestions[#suggestions + 1] = {
                        name = e.name,
                        currentWeight = e.weight,
                        suggestedWeight = math.max(0, e.weight + (deviation > 0 and WEIGHT_NUDGE or -WEIGHT_NUDGE)),
                        deviationPct = deviation * 100,
                        tierAvgDPS = tierAvg,
                        avgDPS = e.avgDPS,
                        sampleCount = e.sampleCount,
                    }
                end
            end
        end
    end

    table.sort(suggestions, function(a, b) return math.abs(a.deviationPct) > math.abs(b.deviationPct) end)
    return suggestions
end

------------------------------------------------------------------------
-- Sample ticker: only does anything while actually in combat, and only
-- if the player opted in.
------------------------------------------------------------------------

local tickerFrame
local elapsed = 0

local function OnTick(self, dt)
    if not EbonBuilds.EchoPerformance.IsEnabled() then return end
    if not UnitAffectingCombat("player") then return end
    elapsed = elapsed + dt
    if elapsed < SAMPLE_INTERVAL then return end
    elapsed = 0
    EbonBuilds.EchoPerformance.Sample()
end

function EbonBuilds.EchoPerformance.Init()
    if tickerFrame then return end
    tickerFrame = CreateFrame("Frame")
    tickerFrame:SetScript("OnUpdate", OnTick)
end
