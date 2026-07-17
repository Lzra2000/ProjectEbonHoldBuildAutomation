-- EbonBuilds: modules/talents/Talents.lua
-- Reads a WoW 3.3.5a talent allocation (the standard 51-point class talent
-- trees, NOT Echoes) either from the player's own character or from an
-- inspected target, and stores it as a compact, class-scoped preset that
-- travels along with a build through the existing export/sync/chat-link
-- pipeline (it's just another field on the build object -- no changes
-- needed to Sync.lua or ChatLink.lua).
--
-- Storage format on a build:
--   build.talents = {
--     class = "MAGE",                 -- talent layouts are class-specific;
--                                      -- guards against pasting a DK spec
--                                      -- onto a Mage build
--     tabs = {
--       [1] = { name = "Arcane", points = 31, ranks = { [3]=5, [7]=1, ... } },
--       [2] = { name = "Fire",   points = 5,  ranks = { [1]=5 } },
--       [3] = { name = "Frost",  points = 5,  ranks = { [2]=5 } },
--     },
--   }
-- `ranks` is keyed by talent index within that tab (stable for a given
-- class -- the same index always means the same talent for everyone of
-- that class, so no name/id translation is needed between players).

EbonBuilds.Talents = {}

local function ScanTabs(isInspect)
    local numTabs = GetNumTalentTabs and GetNumTalentTabs(isInspect) or 0
    local tabs = {}
    for tabIndex = 1, numTabs do
        local name, _, pointsSpent = GetTalentTabInfo(tabIndex, isInspect)
        local ranks = {}
        local numTalents = GetNumTalents and GetNumTalents(tabIndex, isInspect) or 0
        for talentIndex = 1, numTalents do
            local _, _, _, _, rank = GetTalentInfo(tabIndex, talentIndex, isInspect)
            if rank and rank > 0 then
                ranks[talentIndex] = rank
            end
        end
        tabs[tabIndex] = { name = name or ("Tab " .. tabIndex), points = pointsSpent or 0, ranks = ranks }
    end
    return tabs
end

-- Reads the player's own current talent allocation.
function EbonBuilds.Talents.ScanSelf()
    return {
        class = EbonBuilds.Build.PlayerClassToken(),
        tabs  = ScanTabs(false),
    }
end

------------------------------------------------------------------------
-- Inspecting a target (async: the server has to send the data first)
------------------------------------------------------------------------

local INSPECT_TIMEOUT = 5
local pending = nil -- { unit, class, callback, elapsed } or nil
local watcherFrame

local function FinishPending(talents, err)
    local cb = pending and pending.callback
    pending = nil
    if watcherFrame then watcherFrame:Hide() end
    if ClearInspectPlayer then pcall(ClearInspectPlayer) end
    if cb then cb(talents, err) end
end

local function EnsureWatcher()
    if watcherFrame then return end
    watcherFrame = CreateFrame("Frame")
    watcherFrame:Hide()
    watcherFrame:SetScript("OnUpdate", function(self, dt)
        if not pending then self:Hide(); return end
        pending.elapsed = pending.elapsed + dt
        if pending.elapsed > INSPECT_TIMEOUT then
            FinishPending(nil, "timeout")
        end
    end)
    watcherFrame:RegisterEvent("INSPECT_TALENT_READY")
    watcherFrame:SetScript("OnEvent", function()
        if not pending then return end
        local talents = { class = pending.class, tabs = ScanTabs(true) }
        FinishPending(talents, nil)
    end)
end

-- Requests the given unit's talents and calls callback(talents, err) once
-- the data arrives (or after a timeout). Only one inspect request can be
-- in flight at a time; a new call cancels any previous one.
function EbonBuilds.Talents.ScanUnit(unit, callback)
    if not unit or not UnitExists(unit) then
        callback(nil, "no target")
        return
    end
    if not UnitIsPlayer(unit) then
        callback(nil, "not a player")
        return
    end
    if UnitIsUnit(unit, "player") then
        callback(EbonBuilds.Talents.ScanSelf(), nil)
        return
    end
    if CheckInteractDistance and not CheckInteractDistance(unit, 1) then
        callback(nil, "too far away")
        return
    end

    EnsureWatcher()
    local _, classToken = UnitClass(unit)
    pending = { unit = unit, class = classToken, callback = callback, elapsed = 0 }
    watcherFrame:Show()
    NotifyInspect(unit)
end

------------------------------------------------------------------------
-- Display helpers
------------------------------------------------------------------------

-- Classic "31/5/5"-style point summary, e.g. for a compact label.
function EbonBuilds.Talents.PointSummary(talents)
    if not talents or not talents.tabs then return "" end
    local parts = {}
    for i = 1, 3 do
        parts[#parts + 1] = tostring(talents.tabs[i] and talents.tabs[i].points or 0)
    end
    return table.concat(parts, "/")
end

function EbonBuilds.Talents.TotalPoints(talents)
    if not talents or not talents.tabs then return 0 end
    local total = 0
    for _, tab in pairs(talents.tabs) do
        total = total + (tab.points or 0)
    end
    return total
end
