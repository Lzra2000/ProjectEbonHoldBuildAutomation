-- Regression coverage for bounded frozen-state uncertainty recovery.

local function fail(message)
    io.stderr:write("FREEZE RECOVERY FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end

local function equal(actual, expected, message)
    if actual ~= expected then
        fail(string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
    end
end

local function check(value, message)
    if not value then fail(message) end
end

EbonBuildsDB = { globalSettings = { evalDelay = 2 } }

local scheduledDelays = {}
local loggedActions = {}
local choices = {}
local build = { stats = {} }
local addon = {
    Build = {
        GetActive = function() return build end,
        IsAutomationEnabled = function() return true end,
    },
    ManualTraining = { IsEnabled = function() return false end },
    ProjectAPI = {
        GetCurrentChoice = function() return choices end,
        RequestFreeze = function() return true end,
    },
    Scheduler = {
        CRITICAL = 1, INTERACTIVE = 2,
        After = function(id, delay) scheduledDelays[id] = delay; return true end,
        Cancel = function() return true end,
    },
    DebugLog = { Add = function() end, AddF = function() end, IsEnabled = function() return false end },
    Toast = { Show = function() end, ShowAutomationResult = function() end },
    Session = {
        LogAction = function(_, action, targetIndex)
            loggedActions[#loggedActions + 1] = { action = action, targetIndex = targetIndex }
        end,
    },
}

assert(loadfile("modules/automation/BoardDecision.lua"))("EbonBuilds", addon)
assert(loadfile("modules/automation/Automation.lua"))("EbonBuilds", addon)

local D = addon.AutomationBoardDecision
local function Board(secondFrozen)
    local board = {
        slots = {
            { index = 1, spellId = 101, name = "Pick", score = 160, isValid = true },
            { index = 2, spellId = 102, name = "Freeze", score = 130, isValid = true, isFrozen = secondFrozen },
        },
        isValid = true,
        isStable = true,
        maxFrozen = 2,
        freezeThreshold = 120,
        freezeResources = 2,
        canReroll = true,
        canBanish = false,
        pickIsAcceptable = true,
    }
    D.RefreshFrozenState(board)
    board.fingerprint = D.Fingerprint(board)
    board.identityFingerprint = D.IdentityFingerprint(board)
    return board
end

local function ArmUncertainty(board)
    local state = addon.Automation._GetBoardStateForTests()
    state.frozenStateUncertain = true
    state.uncertainFreezeSlot = 2
    state.uncertainFreezeEchoID = 102
    state.uncertainFreezeIdentity = board.identityFingerprint
    state.uncertainFreezeChecks = 0
    state.uncertainFreezeUsedCount = 0
    state.failedFreezeBySlot[2] = true
    return state
end

addon.Automation._MarkInitialActionDelayCompleteForTests()

-- Every locally accepted request is visible in the Logbook immediately, and
-- later confirmation must not create a duplicate entry.
addon.Automation._ResetFreezeRound()
local requestBoard = Board(false)
equal(addon.Automation._RequestFreezeForTests(build, requestBoard, requestBoard.slots[2]),
    true, "valid freeze request was not accepted")
local requestState = addon.Automation._GetBoardStateForTests()
check(requestState.frozenThisBoardBySlot[2], "accepted freeze did not mark its current-board slot")
check(requestState.frozenThisBoardEchoIDs[102], "accepted freeze did not mark its current-board identity")
equal(#loggedActions, 1, "accepted freeze request was not logged exactly once")
equal(loggedActions[1].action, "Freeze", "accepted request used the wrong Logbook action")
equal(loggedActions[1].targetIndex, 2, "accepted request logged the wrong target")

local confirmedBoard = Board(true)
local confirmedRunData = { totalFreezes = 3, usedFreezes = 0 }
equal(addon.Automation._ResolvePendingFreezeForTests(build, confirmedBoard, confirmedRunData),
    "confirmed", "accepted freeze was not confirmed")
equal(#loggedActions, 1, "freeze confirmation duplicated the Logbook entry")
build.stats.freezesUsed = 0

-- Some ProjectEbonhold builds advance the authoritative Freeze counter before
-- exposing isFrozen/isCarried on the board. That server-side confirmation must
-- preserve the first target, allow the second freeze, and then select the best.
addon.Automation._ResetFreezeRound()
EbonholdPlayerRunData = {
    remainingBanishes = 15,
    totalFreezes = 5,
    usedFreezes = 0,
}
local resourceBoard = {
    slots = {
        { index = 1, spellId = 201, name = "Echoing Afflictions", score = 180, isValid = true },
        { index = 2, spellId = 202, name = "Reaper's Verdict", score = 140, isValid = true },
        { index = 3, spellId = 203, name = "Hungering Curse", score = 140, isValid = true },
    },
    isValid = true,
    isStable = true,
    maxFrozen = 2,
    freezeThreshold = 129,
    freezeResources = 5,
    canReroll = true,
    canBanish = false,
    pickIsAcceptable = true,
}
D.RefreshFrozenState(resourceBoard)
resourceBoard.fingerprint = D.Fingerprint(resourceBoard)
resourceBoard.identityFingerprint = D.IdentityFingerprint(resourceBoard)

local firstResourceDecision = D.Decide(resourceBoard)
equal(firstResourceDecision.action, "FREEZE", "three-value board did not request its first freeze")
equal(firstResourceDecision.target.index, 2, "equal-valued first freeze was not deterministic")
equal(addon.Automation._RequestFreezeForTests(build, resourceBoard, firstResourceDecision.target),
    true, "first resource-confirmed freeze request was rejected")
EbonholdPlayerRunData.usedFreezes = 1
local resourceState = addon.Automation._GetBoardStateForTests()
resourceBoard.frozenThisBoardBySlot = resourceState.frozenThisBoardBySlot
resourceBoard.frozenThisBoardEchoIDs = resourceState.frozenThisBoardEchoIDs
resourceBoard.failedFreezeBySlot = resourceState.failedFreezeBySlot
D.RefreshFrozenState(resourceBoard)
equal(addon.Automation._ResolvePendingFreezeForTests(build, resourceBoard, EbonholdPlayerRunData),
    "confirmed", "Freeze counter advance did not confirm the first request")
equal(resourceBoard.frozenCount, 1, "resource-confirmed first freeze was not counted on the board")

resourceBoard.freezeResources = 4
local secondResourceDecision = D.Decide(resourceBoard)
equal(secondResourceDecision.action, "FREEZE", "first resource confirmation skipped the second freeze")
equal(secondResourceDecision.target.index, 3, "second valuable Echo was not the next freeze target")
equal(addon.Automation._RequestFreezeForTests(build, resourceBoard, secondResourceDecision.target),
    true, "second resource-confirmed freeze request was rejected")
EbonholdPlayerRunData.usedFreezes = 2
D.RefreshFrozenState(resourceBoard)
equal(addon.Automation._ResolvePendingFreezeForTests(build, resourceBoard, EbonholdPlayerRunData),
    "confirmed", "Freeze counter advance did not confirm the second request")
equal(resourceBoard.frozenCount, 2, "resource-confirmed freezes did not enforce board capacity")

resourceBoard.freezeResources = 3
local finalResourceDecision = D.Decide(resourceBoard)
equal(finalResourceDecision.action, "SELECT", "two resource-confirmed freezes did not continue to selection")
equal(finalResourceDecision.target.index, 1, "two resource-confirmed freezes selected the wrong Echo")
equal(build.stats.freezesUsed, 2, "resource-confirmed freezes were not counted exactly once each")
equal(#loggedActions, 3, "resource-confirmed freeze sequence did not log exactly two new freezes")
EbonholdPlayerRunData = nil
build.stats.freezesUsed = 0

-- A confirmation that arrives during recovery is still accepted exactly once.
addon.Automation._ResetFreezeRound()
local lateBoard = Board(true)
local lateState = ArmUncertainty(lateBoard)
local runData = { totalFreezes = 3, usedFreezes = 0 }
equal(addon.Automation._ResolveFreezeUncertaintyForTests(build, lateBoard, runData),
    "confirmed", "late freeze confirmation was not accepted")
check(not lateState.frozenStateUncertain, "late confirmation left frozen state uncertain")
equal(build.stats.freezesUsed, 1, "late confirmation was not recorded once")
equal(runData.usedFreezes, 1, "late confirmation did not reconcile the freeze resource")

-- Stable unfrozen reads resolve a failed request without clicking Freeze again.
addon.Automation._ResetFreezeRound()
local stableBoard = Board(false)
local stableState = ArmUncertainty(stableBoard)
local stableRunData = { totalFreezes = 3, usedFreezes = 0 }
stableState.frozenThisBoardBySlot[2] = true
stableState.frozenThisBoardEchoIDs[102] = true
equal(addon.Automation._ResolveFreezeUncertaintyForTests(build, stableBoard, stableRunData),
    "recovering", "first stable read did not remain safely blocked")
equal(scheduledDelays["automation.evaluate"], 0.75,
    "uncertainty recovery did not use the short read-only poll")
check(stableState.frozenStateUncertain, "uncertainty cleared after only one stable read")

equal(addon.Automation._ResolveFreezeUncertaintyForTests(build, stableBoard, stableRunData),
    "resolved", "second stable read did not resolve uncertainty")
check(not stableState.frozenStateUncertain, "stable failure recovery remained stuck")
check(stableState.failedFreezeBySlot[2], "failed slot lost duplicate-freeze suppression")
check(not stableState.frozenThisBoardBySlot[2] and not stableState.frozenThisBoardEchoIDs[102],
    "failed freeze remained incorrectly blocked as a current-board freeze")

stableBoard.failedFreezeBySlot = stableState.failedFreezeBySlot
stableBoard.frozenStateUncertain = stableState.frozenStateUncertain
local nextDecision = D.Decide(stableBoard)
equal(nextDecision.action, "SELECT", "resolved board did not continue to a safe selection")
equal(nextDecision.target.index, 1, "resolved board selected the failed freeze target")

print("Verified Freeze Logbook reporting, bounded uncertainty, and recovery.")
