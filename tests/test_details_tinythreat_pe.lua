-- Headless tests for Details_TinyThreat Project Ebonhold helpers (Lua 5.1).
unpack = unpack or table.unpack

local function fail(message)
    io.stderr:write("DETAILS_TINYTHREAT_PE FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end

local function assertEq(a, b, message)
    if a ~= b then
        fail((message or "not equal") .. ": " .. tostring(a) .. " vs " .. tostring(b))
    end
end

function GetNumPartyMembers()
    return 2
end

function GetNumRaidMembers()
    return 0
end

IsInGroup = nil
IsInRaid = nil
GetNumSubgroupMembers = nil
GetNumGroupMembers = nil

local chunk, err = loadfile("vendor/Details_TinyThreat/DetailsTinyThreatProjectEbonhold.lua")
if not chunk then fail(err) end
local ok, loadErr = pcall(chunk)
if not ok then fail("load DetailsTinyThreatProjectEbonhold: " .. tostring(loadErr)) end

assertEq(TT_GetNumGroupMembers(), 2, "party group size")
assertEq(TT_GetNumSubgroupMembers(), 2, "subgroup maps to party")

GetNumRaidMembers = function() return 10 end
GetNumPartyMembers = function() return 0 end

assertEq(TT_GetNumGroupMembers(), 10, "raid group size")

local threatCalls = 0
function UnitDetailedThreatSituation(unit, target)
    threatCalls = threatCalls + 1
    if unit == "fail" then error("simulated threat API failure") end
    return true, true, 85.5, 80, 12000
end

local isTanking, status, pct, rawPct, value = TT_SafeUnitDetailedThreatSituation("player", "target")
assertEq(isTanking, true, "threat ok isTanking")
assertEq(status, true, "threat ok status")
assertEq(pct, 85.5, "threat ok pct")
assertEq(value, 12000, "threat ok value")

isTanking, status = TT_SafeUnitDetailedThreatSituation("fail", "target")
assertEq(isTanking, nil, "threat failure returns nil")
assertEq(status, nil, "threat failure status nil")
assertEq(threatCalls, 2, "threat API invoked twice")

DetailsFramework = {
    UnitGroupRolesAssigned = function(unitId)
        if unitId == "fail" then error("role failure") end
        return "TANK"
    end,
}

assertEq(TT_SafeUnitGroupRolesAssigned("player"), "TANK", "role from DetailsFramework")
assertEq(TT_SafeUnitGroupRolesAssigned("fail"), "NONE", "role failure fallback")

DetailsFramework = nil
assertEq(TT_SafeUnitGroupRolesAssigned("player"), "NONE", "no framework fallback")

_G._detalhes = { NewPluginObject = function() return {} end }
assertEq(TT_IsDetailsReady(), true, "details ready")

_G._detalhes = nil
assertEq(TT_IsDetailsReady(), false, "details missing")

function GetUnitName(unit, showServerName)
    if unit == "fail" then error("name failure") end
    return "TestPlayer"
end

assertEq(TT_SafeGetUnitName("player", true), "TestPlayer", "get name ok")
assertEq(TT_SafeGetUnitName("fail", true), nil, "get name failure")

-- GetUnitName shim (when MoP API missing)
do
    local savedGetUnitName = GetUnitName
    GetUnitName = nil
    function UnitName(unit)
        if unit == "player" then return "Solo", "Realm" end
        return nil
    end
    TT_EnsureNameCompat()
    assertEq(GetUnitName("player", true), "Solo-Realm", "GetUnitName shim with realm")
    assertEq(GetUnitName("player", false), "Solo", "GetUnitName shim without realm")
    GetUnitName = savedGetUnitName
end

-- UnitDetailedThreatSituation polyfill from UnitThreatSituation
do
    local savedDetailed = UnitDetailedThreatSituation
    UnitDetailedThreatSituation = nil
    function UnitThreatSituation(unit, mobUnit)
        if unit == "player" then return 2 end
        return nil
    end
    TT_EnsureThreatCompat()
    isTanking, status, pct, rawPct, value = UnitDetailedThreatSituation("player", "target")
    assertEq(isTanking, false, "polyfill isTanking for status 2")
    assertEq(status, 2, "polyfill status passthrough")
    assertEq(pct, 50, "polyfill coarse pct for status 2")
    assertEq(value, 50000, "polyfill synthetic threat value")
    UnitDetailedThreatSituation = savedDetailed
end

print("DETAILS_TINYTHREAT_PE OK")
