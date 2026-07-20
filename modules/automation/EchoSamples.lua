-- EbonBuilds: modules/automation/EchoSamples.lua
-- Responsibility: sample-based DPS attribution. The old model credited
-- every active echo with the loadout's whole DPS (per-echo sum/count),
-- so a mount-speed echo "earned" the damage its neighbors dealt --
-- confounded by construction, and more data only made it more
-- confidently wrong. This module stores each observation as ONE sample
-- of the WHOLE set -- { every active echo, dps, time } -- and answers
-- questions with with/without comparisons across samples: how do runs
-- containing echo X score against runs without it. Still not causality,
-- but it measures the right thing, and synergy stops being averaged
-- away into individual credit.

EbonBuilds.EchoSamples = {}

local M = EbonBuilds.EchoSamples
local Ring = EbonBuilds.RingBuffer

-- ~500 whole-set samples is weeks of play at the sample cadence, and
-- small enough that SavedVariables stays harmless.
local CAPACITY = 500
-- Below this many samples on EITHER side, a with/without split is noise
-- wearing a number's clothes -- Delta() reports it as unreliable and
-- consumers must not surface it as evidence.
M.MIN_SAMPLES_PER_SIDE = 10

local function Store()
    EbonBuildsCharDB.echoPerfSampleRing = Ring.Ensure(EbonBuildsCharDB.echoPerfSampleRing, CAPACITY)
    return EbonBuildsCharDB.echoPerfSampleRing
end

-- One observation of the current state: the COMPLETE active echo set
-- (names, sorted for stable storage), the DPS reading, and when.
function M.Record(echoNames, dps, now)
    if type(echoNames) ~= "table" or #echoNames == 0 then return false end
    if type(dps) ~= "number" or dps < 0 then return false end
    local set = {}
    for i = 1, #echoNames do set[i] = tostring(echoNames[i]) end
    table.sort(set)
    Ring.Append(Store(), { set = set, dps = dps, t = now or (time and time()) or 0 })
    return true
end

function M.Count()
    return Ring.Count(Store())
end

function M.Clear()
    Ring.Clear(Store())
end

local function SetContains(set, name)
    for i = 1, #set do
        if set[i] == name then return true end
    end
    return false
end

-- The core question: across all stored samples, how do runs WITH this
-- echo compare against runs WITHOUT it. Returns nil for garbage input,
-- otherwise { withMean, withoutMean, delta, nWith, nWithout, reliable }.
-- delta is withMean - withoutMean; reliable is false until both sides
-- clear MIN_SAMPLES_PER_SIDE, and unreliable deltas must never be
-- presented as evidence (the suggestion layer enforces that).
function M.Delta(echoName)
    if type(echoName) ~= "string" or echoName == "" then return nil end
    local withSum, withN, withoutSum, withoutN = 0, 0, 0, 0
    Ring.ForEach(Store(), function(sample)
        if type(sample) == "table" and type(sample.set) == "table" and type(sample.dps) == "number" then
            if SetContains(sample.set, echoName) then
                withSum, withN = withSum + sample.dps, withN + 1
            else
                withoutSum, withoutN = withoutSum + sample.dps, withoutN + 1
            end
        end
    end)
    local withMean = withN > 0 and (withSum / withN) or 0
    local withoutMean = withoutN > 0 and (withoutSum / withoutN) or 0
    return {
        withMean = withMean,
        withoutMean = withoutMean,
        delta = withMean - withoutMean,
        nWith = withN,
        nWithout = withoutN,
        reliable = withN >= M.MIN_SAMPLES_PER_SIDE and withoutN >= M.MIN_SAMPLES_PER_SIDE,
    }
end

-- Utility filter: an echo whose families include none of the damage
-- roles has no business in DPS attribution at all -- the mount-speed
-- case. Catalog getter injectable for tests.
local DPS_FAMILIES = { ["Caster"] = true, ["Melee"] = true, ["Ranged"] = true }

function M.IsDpsRelevant(echoName, getCatalog)
    getCatalog = getCatalog or (EbonBuilds.EchoTableRows and EbonBuilds.EchoTableRows.BuildBestByName)
    if not getCatalog then return true end  -- no catalog: never silently exclude
    local entry = getCatalog()[echoName]
    if not entry or type(entry.families) ~= "table" then return true end
    for _, family in ipairs(entry.families) do
        if DPS_FAMILIES[family] then return true end
        -- Catalog variants like "Caster DPS" / "Melee DPS" count too.
        for role in pairs(DPS_FAMILIES) do
            if type(family) == "string" and family:find(role, 1, true) then return true end
        end
    end
    return false
end

-- The one call the suggestion layer uses: a DPS value for this echo
-- that is honest about what it knows. nil means "no evidence" -- either
-- the echo is pure utility (excluded by design), or the with/without
-- split isn't reliable yet. Never returns a confounded average.
function M.EvidenceValue(echoName, getCatalog)
    if not M.IsDpsRelevant(echoName, getCatalog) then return nil, "utility" end
    local d = M.Delta(echoName)
    if not d or not d.reliable then return nil, "insufficient" end
    return d.delta, "delta", d
end
