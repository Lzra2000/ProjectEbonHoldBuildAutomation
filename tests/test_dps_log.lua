-- Unit coverage for modules/session/DpsLog.lua (issue #46).
-- Verifies 3.3.5a CLEU positional parsing, segment finalize rules,
-- sample attachment to the active run, and best-sample selection.
-- Run from the addon root with: lua5.1 tests/test_dps_log.lua

unpack = unpack or table.unpack

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. tostring(message) .. "\n")
    end
end
local function equal(actual, expected, message)
    check(actual == expected, string.format("%s (expected %s, got %s)",
        message, tostring(expected), tostring(actual)))
end

------------------------------------------------------------------------
-- Minimal stubs
------------------------------------------------------------------------

local now = 1000
function GetTime() return now end
function time() return 1700000000 end

local function Band(a, b)
    a, b = tonumber(a) or 0, tonumber(b) or 0
    local result, place = 0, 1
    while a > 0 or b > 0 do
        local abit, bbit = a % 2, b % 2
        if abit == 1 and bbit == 1 then result = result + place end
        a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
    end
    return result
end
bit = bit or {}
bit.band = Band
COMBATLOG_OBJECT_AFFILIATION_MINE = 0x00000001

EbonBuilds = { Runtime = {} }
EbonBuildsDB = { builds = {}, sessions = {}, globalSettings = {}, currentSessionIndex = 1 }
EbonBuildsCharDB = { dpsLoggingEnabled = true }

local activeSession = {
    id = "run-1",
    buildId = "build-1",
    analyticsRevision = 0,
    dpsSamples = nil,
}
EbonBuildsDB.sessions[1] = activeSession

local bumps = {}
EbonBuilds.EventHub = {
    Bump = function(name, ...)
        bumps[#bumps + 1] = { name = name, args = { ... } }
    end,
}

local historyChanged = 0
EbonBuilds.SessionHistory = {
    OnHistoryChanged = function() historyChanged = historyChanged + 1 end,
}

EbonBuilds.Session = {
    GetActiveSession = function() return activeSession end,
}

local scheduled = {}
EbonBuilds.Scheduler = {
    BACKGROUND = 3,
    Every = function(id, interval, callback, priority, allowCombat, owner)
        scheduled[id] = {
            interval = interval,
            callback = callback,
            priority = priority,
            allowCombat = allowCombat,
            owner = owner,
        }
        return true
    end,
    Cancel = function(id) scheduled[id] = nil end,
}

local listeners = {}
EbonBuilds.WoWEvents = {
    On = function(eventName, callback, owner, fast, spamExempt)
        local record = {
            event = eventName,
            callback = callback,
            owner = owner,
            fast = fast == true,
            spamExempt = spamExempt == true,
            active = true,
        }
        listeners[eventName] = listeners[eventName] or {}
        listeners[eventName][#listeners[eventName] + 1] = record
        return record
    end,
    Off = function(token)
        if type(token) ~= "table" or not token.active then return false end
        token.active = false
        return true
    end,
    EmitForTests = function(eventName, ...)
        for _, record in ipairs(listeners[eventName] or {}) do
            if record.active then record.callback(eventName, ...) end
        end
    end,
}

assert(loadfile("modules/session/DpsLog.lua"))("EbonBuilds", EbonBuilds)
local DpsLog = EbonBuilds.DpsLog

------------------------------------------------------------------------
-- Helpers mirroring 3.3.5a CLEU prefix (no hideCaster / raid flags)
------------------------------------------------------------------------

local MINE = COMBATLOG_OBJECT_AFFILIATION_MINE
local OTHER = 0

local function EmitSwing(amount, destName, sourceFlags, destFlags)
    EbonBuilds.WoWEvents.EmitForTests(
        "COMBAT_LOG_EVENT_UNFILTERED",
        now, "SWING_DAMAGE",
        "player-guid", "Tester", sourceFlags or MINE,
        "npc-guid", destName or "Training Dummy", destFlags or OTHER,
        amount, 0, 1, 0, 0, 0, nil, nil, nil)
end

local function EmitSpell(amount, destName, sourceFlags, destFlags)
    EbonBuilds.WoWEvents.EmitForTests(
        "COMBAT_LOG_EVENT_UNFILTERED",
        now, "SPELL_DAMAGE",
        "player-guid", "Tester", sourceFlags or MINE,
        "npc-guid", destName or "Heroic Training Dummy", destFlags or OTHER,
        133, "Fireball", 4,
        amount, 0, 4, 0, 0, 0, nil, nil, nil)
end

------------------------------------------------------------------------
-- Formatting + preference
------------------------------------------------------------------------

equal(DpsLog.FormatDps(950), "950", "sub-1k DPS is whole number")
equal(DpsLog.FormatDps(1500), "1.5k", "1k-10k DPS uses one decimal k")
equal(DpsLog.FormatDps(12500), "13k", "10k+ DPS uses whole k")
equal(DpsLog.FormatSampleDuration(45), "45s", "sub-minute duration")
equal(DpsLog.FormatSampleDuration(125), "2m 05s", "minute+duration")
equal(DpsLog.FormatBestSample(nil, true), "", "no session yields empty best text")
equal(DpsLog.FormatBestSample({ dpsSamples = {} }, false), "", "empty samples yield empty best text")

check(DpsLog.IsEnabled() == true, "preference defaults to enabled")
DpsLog.Init()
check(DpsLog._IsRegisteredForTests(), "Init registers CLEU while enabled")

------------------------------------------------------------------------
-- Short segment discarded; qualifying segment attaches to active run
------------------------------------------------------------------------

EmitSwing(500)
now = now + 5
EmitSwing(500)
EbonBuilds.WoWEvents.EmitForTests("PLAYER_REGEN_ENABLED")
equal(#(activeSession.dpsSamples or {}), 0, "segments under MIN_SEGMENT_SECONDS are discarded")
check(DpsLog._GetSegmentForTests() == nil, "discarded segment clears open state")

now = 2000
EmitSpell(10000, "Heroic Training Dummy")
now = now + 120
EmitSpell(14000, "Heroic Training Dummy")
EbonBuilds.WoWEvents.EmitForTests("PLAYER_REGEN_ENABLED")

equal(#(activeSession.dpsSamples or {}), 1, "120s dummy fight stores one sample")
local sample = activeSession.dpsSamples[1]
equal(sample.duration, 120, "duration is first-hit to last-hit")
equal(sample.damage, 24000, "damage sums player spells")
equal(sample.dps, 200, "dps = damage / duration")
equal(sample.target, "Heroic Training Dummy", "dominant target name stored")
check(sample.dummy == true, "training-dummy needle marks sample.dummy")
equal(activeSession.analyticsRevision, 1, "analyticsRevision bumps on attach")
equal(historyChanged, 1, "Logbook refresh notified")
equal(bumps[1] and bumps[1].name, "RUN_DPS_SAMPLE", "EventHub RUN_DPS_SAMPLE fired")

------------------------------------------------------------------------
-- Self-damage and foreign sources ignored
------------------------------------------------------------------------

now = 3000
EmitSwing(9999, "Training Dummy", OTHER, OTHER)
EmitSwing(9999, "Tester", MINE, MINE)
now = now + 30
EmitSwing(9999, "Training Dummy", OTHER, OTHER)
EbonBuilds.WoWEvents.EmitForTests("PLAYER_REGEN_ENABLED")
equal(#activeSession.dpsSamples, 1, "foreign/self damage does not open a segment")

------------------------------------------------------------------------
-- Inactivity finalize + best-sample prefers benchmark length
------------------------------------------------------------------------

now = 4000
EmitSwing(6000, "Training Dummy")
now = now + 15
EmitSwing(9000, "Training Dummy")
-- Simulate watchdog: last damage 5+ seconds ago.
now = now + 6
check(scheduled["dpsLog.inactivity"] ~= nil, "inactivity job scheduled while segment open")
DpsLog._InactivityTickForTests()
equal(#activeSession.dpsSamples, 2, "inactivity closes a long-enough segment")
equal(activeSession.dpsSamples[2].duration, 15, "inactivity sample uses active duration")

-- Short high-DPS burst should lose to the longer 120s benchmark sample.
now = 5000
EmitSwing(500000, "Trash Mob")
now = now + 12
EmitSwing(500000, "Trash Mob")
EbonBuilds.WoWEvents.EmitForTests("PLAYER_REGEN_ENABLED")
equal(#activeSession.dpsSamples, 3, "short burst still stored as a sample")

local best, count = DpsLog.GetBestSample(activeSession)
equal(count, 3, "GetBestSample reports total count")
equal(best.duration, 120, "benchmark-length sample beats shorter higher-DPS burst")
equal(best.dps, 200, "best sample is the 120s dummy run")
equal(DpsLog.FormatBestSample(activeSession, true), "200 DPS", "compact best-sample text")
equal(DpsLog.FormatBestSample(activeSession, false), "Best DPS 200 over 2m 00s · 3 fights", "long best-sample text")

------------------------------------------------------------------------
-- Toggle unregisters CLEU
------------------------------------------------------------------------

DpsLog.SetEnabled(false)
check(not DpsLog.IsEnabled(), "SetEnabled(false) clears preference")
check(not DpsLog._IsRegisteredForTests(), "disabled state unregisters CLEU")
EmitSwing(1000)
now = now + 60
EmitSwing(1000)
EbonBuilds.WoWEvents.EmitForTests("PLAYER_REGEN_ENABLED")
equal(#activeSession.dpsSamples, 3, "no new samples while logging is off")

DpsLog.SetEnabled(true)
check(DpsLog._IsRegisteredForTests(), "re-enable re-registers CLEU")

------------------------------------------------------------------------
-- Cap: oldest samples drop once MAX is exceeded
------------------------------------------------------------------------

local maxSamples = DpsLog._MAX_SAMPLES_PER_SESSION
activeSession.dpsSamples = {}
for i = 1, maxSamples + 3 do
    now = now + 1
    local start = now
    EmitSwing(1000, "Dummy " .. i)
    now = start + 20
    EmitSwing(1000, "Dummy " .. i)
    EbonBuilds.WoWEvents.EmitForTests("PLAYER_REGEN_ENABLED")
end
equal(#activeSession.dpsSamples, maxSamples, "sample list is capped per session")
equal(activeSession.dpsSamples[1].target, "Dummy 4", "oldest samples are dropped first")

if failures > 0 then
    io.stderr:write(string.format("DpsLog tests failed: %d\n", failures))
    os.exit(1)
end
print("DpsLog tests passed.")
