-- EbonBuilds: modules/session/Session.lua
-- Responsibility: session lifecycle management (start, end, log actions).
-- A session spans from level 1 until the player dies and resets back to
-- level 1. Logs are persisted per-session in EbonBuildsDB.sessions.

EbonBuilds.Session = {}

local POLL_INTERVAL = 2  -- seconds between level checks for reset detection

local maxLevel     = 0   -- highest level seen in the active session
local pollFrame    = nil
local pollElapsed  = 0

------------------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------------------

local function GetRunSoulAshes()
    local rd = EbonholdPlayerRunData
    if not rd and ProjectEbonhold and ProjectEbonhold.PlayerRunService then
        local get = ProjectEbonhold.PlayerRunService.GetCurrentData
        if get then rd = get() end
    end
    return (rd and rd.soulPoints) or 0
end

local function GetClassName()
    local _, class = UnitClass("player")
    return class  -- English token (WARRIOR, MAGE, etc.)
end

local function GetActiveBuildTitle()
    local build = EbonBuilds.Build.GetActive()
    return build and build.title or "No Build"
end

local function CreateSession()
    local sessions = EbonBuildsDB.sessions
    local id = tostring(time()) .. "-" .. tostring(#sessions + 1)

    local session = {
        id            = id,
        characterName = UnitName("player"),
        className     = GetClassName(),
        startTime     = time(),
        endTime       = nil,
        soulAshes     = 0,
        buildTitle    = GetActiveBuildTitle(),
        logs          = {},
    }

    table.insert(sessions, 1, session)
    EbonBuildsDB.currentSessionIndex = 1
    maxLevel = UnitLevel("player")
    session.maxLevel = maxLevel

    -- New run: the automation peak was locked for the previous run and must
    -- be recomputed fresh (weights or settings may have changed in between).
    if EbonBuilds.Automation and EbonBuilds.Automation.ResetPeakCache then
        EbonBuilds.Automation.ResetPeakCache()
    end

    return session
end

-- Keep the live session's persisted maxLevel in step with the local tracker,
-- so a relog can restore it and death-reset detection works across logouts.
local function TrackMaxLevel(level)
    if level <= maxLevel then return end
    maxLevel = level
    local idx = EbonBuildsDB.currentSessionIndex
    local session = idx and EbonBuildsDB.sessions[idx]
    if session then session.maxLevel = maxLevel end
end

------------------------------------------------------------------------
-- Event handlers
------------------------------------------------------------------------

local function OnPlayerEnteringWorld()
    local level = UnitLevel("player")

    -- No active session: start one at the current level
    if not EbonBuildsDB.currentSessionIndex then
        CreateSession()
        return
    end

    -- Fresh login/reload: the local maxLevel tracker resets to 0, so restore
    -- it from the live session record. Without this, a death-reset that
    -- spans a logout (relog at level 1) would never be detected and the old
    -- session would keep accumulating a second run's logs.
    local session = EbonBuildsDB.sessions[EbonBuildsDB.currentSessionIndex]
    if session and session.maxLevel and session.maxLevel > maxLevel then
        maxLevel = session.maxLevel
    end

    -- Active session exists, but player is now level 1 after being higher:
    -- the run ended (death accepted, reset to level 1)
    if level == 1 and maxLevel > 1 then
        EbonBuilds.Session.EndCurrentSession()
        CreateSession()
        return
    end

    -- Update max level if player leveled up while offline / zoning
    TrackMaxLevel(level)
end

local function OnPlayerLevelUp(newLevel)
    if not EbonBuildsDB.currentSessionIndex then
        -- No session yet: start one at the current level
        CreateSession()
        return
    end

    TrackMaxLevel(newLevel)
end

local function OnPollUpdate(self, dt)
    pollElapsed = pollElapsed + dt
    if pollElapsed < POLL_INTERVAL then return end
    pollElapsed = 0

    local level = UnitLevel("player")

    -- Level reset detection: player went from >1 back to 1
    if EbonBuildsDB.currentSessionIndex and level == 1 and maxLevel > 1 then
        EbonBuilds.Session.EndCurrentSession()
        CreateSession()
        return
    end

    TrackMaxLevel(level)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

function EbonBuilds.Session.EndCurrentSession()
    local idx = EbonBuildsDB.currentSessionIndex
    if not idx then return end

    local session = EbonBuildsDB.sessions[idx]
    if not session then
        EbonBuildsDB.currentSessionIndex = nil
        return
    end

    session.endTime   = time()
    session.soulAshes = GetRunSoulAshes()
    session.maxLevel  = maxLevel

    -- Per-build run counters for the Stats tab (were never written before).
    local build = EbonBuilds.Build.GetActive()
    if build and build.stats then
        if (session.maxLevel or 0) >= 80 then
            build.stats.runsCompleted = (build.stats.runsCompleted or 0) + 1
        else
            build.stats.runsReset = (build.stats.runsReset or 0) + 1
        end
    end

    EbonBuildsDB.currentSessionIndex = nil
    maxLevel = 0
end

function EbonBuilds.Session.LogAction(scored, action, targetIndex)
    -- Detect run reset: player is level 1 but we tracked a higher peak.
    -- This catches resets that happen without a loading screen where
    -- PLAYER_ENTERING_WORLD never fires.
    local level = UnitLevel("player")
    if EbonBuildsDB.currentSessionIndex and level == 1 and maxLevel > 1 then
        EbonBuilds.Session.EndCurrentSession()
        CreateSession()
    end

    local idx = EbonBuildsDB.currentSessionIndex
    if not idx then
        -- No active session yet: create one on the fly so logs are never lost
        CreateSession()
        idx = EbonBuildsDB.currentSessionIndex
        if not idx then return end
    end

    local session = EbonBuildsDB.sessions[idx]
    if not session then return end

    local choices = {}
    for _, s in ipairs(scored) do
        choices[#choices + 1] = {
            name    = s.name,
            score   = s.score,
            quality = s.quality,
            spellId = s.spellId,
        }
    end

    local rd = EbonholdPlayerRunData
    if not rd and ProjectEbonhold and ProjectEbonhold.PlayerRunService then
        local get = ProjectEbonhold.PlayerRunService.GetCurrentData
        if get then rd = get() end
    end

    local charges = {
        ban    = (rd and rd.remainingBanishes) or 0,
        reroll = (rd and ((rd.totalRerolls or 0) - (rd.usedRerolls or 0))) or 0,
        freeze = (rd and ((rd.totalFreezes or 0) - (rd.usedFreezes or 0))) or 0,
    }

    local entry = {
        timestamp   = time(),
        action      = action,
        choices     = choices,
        targetIndex = targetIndex,
        charges     = charges,
    }

    session.logs[#session.logs + 1] = entry
end

function EbonBuilds.Session.GetSessions()
    return EbonBuildsDB.sessions or {}
end

function EbonBuilds.Session.GetActiveSession()
    local idx = EbonBuildsDB.currentSessionIndex
    if not idx then return nil end
    return EbonBuildsDB.sessions[idx]
end

function EbonBuilds.Session.DeleteSession(id)
    -- Refuse to delete the active session individually
    if EbonBuildsDB.currentSessionIndex then
        local active = EbonBuildsDB.sessions[EbonBuildsDB.currentSessionIndex]
        if active and active.id == id then
            return false
        end
    end

    local sessions = EbonBuildsDB.sessions
    for i, s in ipairs(sessions) do
        if s.id == id then
            if EbonBuildsDB.currentSessionIndex and i < EbonBuildsDB.currentSessionIndex then
                EbonBuildsDB.currentSessionIndex = EbonBuildsDB.currentSessionIndex - 1
            end
            table.remove(sessions, i)
            return true
        end
    end
    return false
end

function EbonBuilds.Session.ClearAllSessions()
    EbonBuildsDB.sessions = {}
    EbonBuildsDB.currentSessionIndex = nil
    maxLevel = 0
    -- Immediately create a fresh session at the current player level
    CreateSession()
end

function EbonBuilds.Session.DeleteLogEntry(sessionId, logIndex)
    local sessions = EbonBuildsDB.sessions
    for _, s in ipairs(sessions) do
        if s.id == sessionId then
            if s.logs and logIndex >= 1 and logIndex <= #s.logs then
                table.remove(s.logs, logIndex)
                return true
            end
            return false
        end
    end
    return false
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function EbonBuilds.Session.Init()
    -- Ensure DB arrays exist
    EbonBuildsDB.sessions = EbonBuildsDB.sessions or {}
    if EbonBuildsDB.currentSessionIndex == nil then
        EbonBuildsDB.currentSessionIndex = nil  -- normalize falsey
    end

    -- Event frame for lifecycle detection
    local ef = CreateFrame("Frame", nil, UIParent)
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    ef:RegisterEvent("PLAYER_LEVEL_UP")
    ef:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            OnPlayerEnteringWorld()
        elseif event == "PLAYER_LEVEL_UP" then
            OnPlayerLevelUp(...)
        end
    end)

    -- Polling frame for level reset detection without loading screen
    pollFrame = CreateFrame("Frame", nil, UIParent)
    pollFrame:SetScript("OnUpdate", OnPollUpdate)
end
