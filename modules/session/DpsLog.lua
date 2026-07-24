local addonName, EbonBuilds = ...

-- EbonBuilds: modules/session/DpsLog.lua
-- Responsibility: passive per-run DPS logging (community request, issue #46).
-- Parses COMBAT_LOG_EVENT_UNFILTERED with the 3.3.5a positional argument
-- layout into combat segments: a segment opens on the first qualifying
-- damage event, and closes on PLAYER_REGEN_ENABLED or after a few seconds
-- without damage. A finished segment becomes one DPS sample (total damage /
-- active duration) attached to the ACTIVE run in EbonBuildsDB.sessions, so
-- the Logbook can show what measured DPS each build actually produced --
-- e.g. hitting a heroic training dummy for 120 seconds.
--
-- Strictly informational: samples never feed automation or scoring.

EbonBuilds.DpsLog = {}
local DpsLog = EbonBuilds.DpsLog

local PREFERENCE_KEY = "dpsLoggingEnabled"

-- Segments shorter than this are combat noise (one trash swing), not a
-- meaningful throughput measurement, and are discarded.
local MIN_SEGMENT_SECONDS = 10
-- Samples at least this long count as "benchmark grade". GetBestSample
-- prefers them over shorter, burstier segments so a deliberate 120s dummy
-- session is not outshined by a 12-second cooldown burst.
local BENCHMARK_SECONDS = 60
-- Seconds without a damage event before an open segment is finalized even
-- though the player may technically still be in combat.
local INACTIVITY_SECONDS = 5
local INACTIVITY_TICK_SECONDS = 2
local INACTIVITY_JOB = "dpsLog.inactivity"
-- Newest samples win once a run exceeds the cap; runs are already pruned by
-- core/Database.lua, this only bounds one session's own list.
local MAX_SAMPLES_PER_SESSION = 20

-- 0x00000001 in the 3.3.5a combat log flag scheme: the source/dest belongs
-- to the recording player (covers the player, their pet, and guardians).
local AFFILIATION_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001
local band = bit and bit.band

-- Informational marker for target-dummy benchmarks. Name matching is used
-- instead of NPC IDs because Project Ebonhold runs custom creature IDs.
local DUMMY_NAME_NEEDLE = "training dummy"

-- Position of the damage amount in the CLEU vararg payload (the arguments
-- AFTER destFlags). 3.3.5a layout, verified against the 3.3.5 combat log:
--   SWING_DAMAGE:  amount, overkill, school, resisted, blocked, absorbed, ...
--   SPELL_/RANGE_/PERIODIC_/SHIELD/SPLIT: spellId, spellName, spellSchool,
--                  amount, overkill, school, ...
local DAMAGE_AMOUNT_POSITION = {
    SWING_DAMAGE          = 1,
    RANGE_DAMAGE          = 4,
    SPELL_DAMAGE          = 4,
    SPELL_PERIODIC_DAMAGE = 4,
    DAMAGE_SHIELD         = 4,
    DAMAGE_SPLIT          = 4,
}

local segment            -- open combat segment, or nil
local combatLogToken     -- WoWEvents registration tokens while enabled
local regenToken

------------------------------------------------------------------------
-- Enable state (character preference, default on)
------------------------------------------------------------------------

function DpsLog.IsEnabled()
    if EbonBuilds.Database and EbonBuilds.Database.GetCharacterPreference then
        return EbonBuilds.Database.GetCharacterPreference(PREFERENCE_KEY)
    end
    return EbonBuildsCharDB and EbonBuildsCharDB[PREFERENCE_KEY] ~= false
end

------------------------------------------------------------------------
-- Sample storage and read API
------------------------------------------------------------------------

local function AttachSample(sample)
    local session = EbonBuilds.Session and EbonBuilds.Session.GetActiveSession
        and EbonBuilds.Session.GetActiveSession()
    if not session then return false end

    session.dpsSamples = session.dpsSamples or {}
    local samples = session.dpsSamples
    samples[#samples + 1] = sample
    while #samples > MAX_SAMPLES_PER_SESSION do table.remove(samples, 1) end

    -- Same change signal the decision log uses, so cached run summaries
    -- (RunQualityCacheToken) and open Logbook views refresh.
    session.analyticsRevision = (tonumber(session.analyticsRevision) or 0) + 1
    if EbonBuilds.EventHub then
        EbonBuilds.EventHub.Bump("RUN_DPS_SAMPLE", session.id, sample.dps)
    end
    if EbonBuilds.SessionHistory and EbonBuilds.SessionHistory.OnHistoryChanged then
        EbonBuilds.SessionHistory.OnHistoryChanged()
    end
    return true
end

function DpsLog.GetSamples(session)
    return (session and session.dpsSamples) or {}
end

-- Headline sample for a run: benchmark-grade samples (>= BENCHMARK_SECONDS)
-- beat shorter ones regardless of DPS; within the same grade the highest
-- DPS wins. Returns the sample (or nil) and the total sample count.
function DpsLog.GetBestSample(session)
    local samples = (session and session.dpsSamples) or {}
    local best
    for _, sample in ipairs(samples) do
        if type(sample) == "table" and tonumber(sample.dps) then
            if not best then
                best = sample
            else
                local sampleLong = (tonumber(sample.duration) or 0) >= BENCHMARK_SECONDS
                local bestLong = (tonumber(best.duration) or 0) >= BENCHMARK_SECONDS
                if sampleLong ~= bestLong then
                    if sampleLong then best = sample end
                elseif (tonumber(sample.dps) or 0) > (tonumber(best.dps) or 0) then
                    best = sample
                end
            end
        end
    end
    return best, #samples
end

function DpsLog.FormatDps(value)
    value = tonumber(value) or 0
    if value >= 1000000 then return string.format("%.1fm", value / 1000000) end
    if value >= 10000 then return string.format("%.0fk", value / 1000) end
    if value >= 1000 then return string.format("%.1fk", value / 1000) end
    return string.format("%.0f", value)
end

function DpsLog.FormatSampleDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds >= 60 then
        return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
    end
    return string.format("%ds", seconds)
end

-- Compact ("1.9k DPS") for run-browser rows; long form for the Logbook
-- summary strip. Empty string when the run has no samples.
function DpsLog.FormatBestSample(session, compact)
    local best, count = DpsLog.GetBestSample(session)
    if not best then return "" end
    if compact then
        return DpsLog.FormatDps(best.dps) .. " DPS"
    end
    local suffix = count > 1 and string.format(" · %d fights", count) or ""
    return string.format("Best DPS %s over %s%s",
        DpsLog.FormatDps(best.dps), DpsLog.FormatSampleDuration(best.duration), suffix)
end

------------------------------------------------------------------------
-- Segment lifecycle
------------------------------------------------------------------------

local function DiscardSegment()
    segment = nil
    if EbonBuilds.Scheduler then EbonBuilds.Scheduler.Cancel(INACTIVITY_JOB) end
end

local function FinalizeSegment()
    local finished = segment
    DiscardSegment()
    if not finished then return nil end

    -- Active duration: first damage event to last damage event. Trailing
    -- idle time (waiting out the inactivity window, running from the dummy)
    -- must not dilute the measurement.
    local duration = (finished.lastAt or 0) - (finished.startAt or 0)
    if duration < MIN_SEGMENT_SECONDS or (finished.damage or 0) <= 0 then return nil end

    local target, targetDamage
    for name, damage in pairs(finished.targets) do
        if not targetDamage or damage > targetDamage then
            target, targetDamage = name, damage
        end
    end

    local dps = finished.damage / duration
    local sample = {
        dps      = math.floor(dps * 10 + 0.5) / 10,
        damage   = finished.damage,
        duration = math.floor(duration + 0.5),
        endedAt  = time(),
        target   = target,
        dummy    = (target and target:lower():find(DUMMY_NAME_NEEDLE, 1, true)) and true or nil,
    }
    if not AttachSample(sample) then return nil end
    return sample
end

local function InactivityTick()
    if not segment then return false end
    if GetTime() - (segment.lastAt or 0) >= INACTIVITY_SECONDS then
        FinalizeSegment()
        return false
    end
end

local function StartSegment(now)
    segment = { startAt = now, lastAt = now, damage = 0, targets = {} }
    -- The watchdog only exists while a segment is open; allowCombat because
    -- "stopped attacking but still flagged in combat" is the exact case it
    -- must catch.
    EbonBuilds.Scheduler.Every(INACTIVITY_JOB, INACTIVITY_TICK_SECONDS, InactivityTick,
        EbonBuilds.Scheduler.BACKGROUND, true, "DpsLog")
end

------------------------------------------------------------------------
-- Event handlers
------------------------------------------------------------------------

-- Registered with fast=true: CLEU fires for every combat event in range and
-- must stay allocation-free with early exits. 3.3.5a positional args:
-- timestamp, subEvent, sourceGUID, sourceName, sourceFlags, destGUID,
-- destName, destFlags, then the sub-event payload.
local function OnCombatLogEvent(_, _, subEvent, _, _, sourceFlags, _, destName, destFlags, ...)
    local amountPosition = DAMAGE_AMOUNT_POSITION[subEvent]
    if not amountPosition then return end
    if not band then return end
    -- Only my own contribution counts: the player plus owned pets/guardians.
    if band(sourceFlags or 0, AFFILIATION_MINE) == 0 then return end
    -- Damage landing on my own unit/pet (reflects, splash) is not throughput.
    if band(destFlags or 0, AFFILIATION_MINE) ~= 0 then return end

    local amount = select(amountPosition, ...)
    if type(amount) ~= "number" or amount <= 0 then return end

    local now = GetTime()
    if not segment then StartSegment(now) end
    segment.damage = segment.damage + amount
    segment.lastAt = now
    local targetName = destName or "Unknown"
    segment.targets[targetName] = (segment.targets[targetName] or 0) + amount
end

local function OnRegenEnabled()
    FinalizeSegment()
end

------------------------------------------------------------------------
-- Registration and settings integration
------------------------------------------------------------------------

local function Register()
    if combatLogToken then return end
    combatLogToken = EbonBuilds.WoWEvents.On("COMBAT_LOG_EVENT_UNFILTERED",
        OnCombatLogEvent, "DpsLog", true, true)
    regenToken = EbonBuilds.WoWEvents.On("PLAYER_REGEN_ENABLED", OnRegenEnabled, "DpsLog")
end

local function Unregister()
    if combatLogToken then EbonBuilds.WoWEvents.Off(combatLogToken); combatLogToken = nil end
    if regenToken then EbonBuilds.WoWEvents.Off(regenToken); regenToken = nil end
    DiscardSegment()
end

function DpsLog.SetEnabled(on)
    local enabled = on and true or false
    if EbonBuilds.Database and EbonBuilds.Database.SetCharacterPreference then
        EbonBuilds.Database.SetCharacterPreference(PREFERENCE_KEY, enabled)
    elseif EbonBuildsCharDB then
        EbonBuildsCharDB[PREFERENCE_KEY] = enabled
    end
    if enabled then Register() else Unregister() end
    return enabled
end

function DpsLog.Init()
    if DpsLog.IsEnabled() then Register() end
end

-- Test/integration hooks. Reading segment state never mutates saved data.
DpsLog._FinalizeSegmentForTests = FinalizeSegment
DpsLog._GetSegmentForTests = function() return segment end
DpsLog._InactivityTickForTests = InactivityTick
DpsLog._IsRegisteredForTests = function() return combatLogToken ~= nil end
DpsLog._MIN_SEGMENT_SECONDS = MIN_SEGMENT_SECONDS
DpsLog._BENCHMARK_SECONDS = BENCHMARK_SECONDS
DpsLog._MAX_SAMPLES_PER_SESSION = MAX_SAMPLES_PER_SESSION
