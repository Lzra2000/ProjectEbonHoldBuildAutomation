-- Unit coverage for WP4 client dry-run / simulation (#53).

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. message .. "\n")
    end
end
local function equal(actual, expected, message)
    check(actual == expected, string.format("%s (expected %s, got %s)",
        message, tostring(expected), tostring(actual)))
end

EbonBuilds = {}
assert(loadfile("modules/automation/BoardStateMachine.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/automation/BoardDecision.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/automation/DryRun.lua"))("EbonBuilds", EbonBuilds)

local DR = EbonBuilds.AutomationDryRun
local BSM = EbonBuilds.AutomationBoardStateMachine
local D = EbonBuilds.AutomationBoardDecision

local function Slot(index, spellId, score, flags)
    local slot = { index = index, spellId = spellId, score = score, name = "Echo " .. spellId, isValid = true }
    for key, value in pairs(flags or {}) do slot[key] = value end
    return slot
end

------------------------------------------------------------------------
-- Evaluate / policy verbs
------------------------------------------------------------------------
do
    local verdict = DR.Evaluate({
        threshold = 120,
        freezeResources = 2,
        canReroll = false,
        slots = {
            Slot(1, 101, 160),
            Slot(2, 102, 130),
            Slot(3, 103, 80),
        },
    })
    equal(verdict.action, "freeze", "two-value board freezes before select")
    equal(verdict.targetSlot, 2, "freeze targets secondary slot")
    equal(verdict.boardState, BSM.STATE.OPEN, "fresh board lifecycle is OPEN")
    equal(verdict.reasonCode, "freeze_first", "freeze reason code")

    local selectVerdict = DR.Evaluate({
        threshold = 120,
        freezeResources = 2,
        slots = { Slot(1, 201, 110), Slot(2, 202, 90) },
    })
    equal(selectVerdict.action, "select", "single-value board selects")
    equal(selectVerdict.targetSlot, 1, "best slot selected")
end

------------------------------------------------------------------------
-- Weights map
------------------------------------------------------------------------
do
    local verdict = DR.Evaluate({
        threshold = 100,
        freezeResources = 0,
        weights = { [301] = 150, [302] = 40 },
        slots = { { spellId = 301 }, { spellId = 302 } },
    })
    equal(verdict.action, "select", "weights applied to raw slots")
    equal(verdict.targetSlot, 1, "weighted best slot")
end

------------------------------------------------------------------------
-- Pending / confirmed lifecycle: no reroll
------------------------------------------------------------------------
do
    local pending = DR.Evaluate({
        threshold = 120,
        freezeResources = 1,
        canReroll = true,
        pendingFreezeSlot = 2,
        pendingFreezeEchoID = 102,
        slots = { Slot(1, 101, 160), Slot(2, 102, 130), Slot(3, 103, 80) },
    })
    equal(pending.action, "wait", "pending freeze yields wait")
    equal(pending.boardState, BSM.STATE.FROZEN_PENDING, "pending freeze lifecycle")
    local allowed = DR.CanReroll({
        threshold = 120,
        canReroll = true,
        pendingFreezeSlot = 2,
        pendingFreezeEchoID = 102,
        slots = { Slot(1, 101, 160), Slot(2, 102, 130) },
    })
    equal(allowed, false, "reroll blocked while freeze pending")

    local confirmed = DR.Evaluate({
        threshold = 120,
        freezeResources = 1,
        canReroll = true,
        slots = {
            Slot(1, 101, 160),
            Slot(2, 102, 130, { isFrozen = true, frozenThisBoard = true }),
            Slot(3, 103, 80),
        },
    })
    equal(confirmed.action, "select", "confirmed freeze board selects")
    equal(confirmed.boardState, BSM.STATE.CONFIRMED, "confirmed freeze lifecycle")
    equal(DR.CanReroll({
        threshold = 120,
        canReroll = true,
        slots = {
            Slot(1, 101, 160),
            Slot(2, 102, 130, { isFrozen = true }),
        },
    }), false, "reroll blocked on confirmed board")
end

------------------------------------------------------------------------
-- Guaranteed card cases
------------------------------------------------------------------------
do
    local guaranteed = DR.Evaluate({
        threshold = 120,
        freezeResources = 2,
        slots = {
            Slot(1, 401, 160),
            Slot(2, 402, 130, { isGuaranteed = true }),
            Slot(3, 403, 20),
        },
    })
    equal(guaranteed.action, "select", "guaranteed Echo not frozen")
    equal(guaranteed.targetSlot, 1, "guaranteed board selects best legal")

    local banish = DR.Evaluate({
        threshold = 120,
        canBanish = true,
        pickIsAcceptable = false,
        slots = {
            Slot(1, 501, 10, { isGuaranteed = true, isAvoided = true }),
            Slot(2, 502, 20, { isAvoided = true, banishEligible = true }),
        },
    })
    equal(banish.action, "banish", "banish skips guaranteed card")
    equal(banish.targetSlot, 2, "banish targets non-guaranteed slot")

    equal(DR.CanReroll({
        threshold = 120,
        canReroll = true,
        pickIsAcceptable = false,
        slots = {
            Slot(1, 601, 10, { isGuaranteed = true, isAvoided = true }),
            Slot(2, 602, 5, { isAvoided = true }),
        },
    }), true, "guaranteed Echo does not block reroll")
end

------------------------------------------------------------------------
-- DebugLog line parsing hook
------------------------------------------------------------------------
do
    local slots = DR.ParseDebugLogBoard(
        "Board: [1] Echo 101(101)=160, [2] Echo 102(102)=130 FROZEN")
    check(type(slots) == "table" and #slots == 2, "DebugLog board parser")
    equal(slots[1].score, 160, "DebugLog score parsed")
    equal(slots[2].isFrozen, true, "DebugLog frozen flag parsed")

    local action = DR.ParseDebugLogAction("Action: FREEZE -- freeze actions take priority over selection")
    equal(action.rawAction, "FREEZE", "DebugLog action parsed")
    equal(action.reason, "freeze actions take priority over selection", "DebugLog reason parsed")

    local lifecycle = DR.ParseDebugLogLifecycle("Board lifecycle: FROZEN_PENDING (freeze_in_flight, derived)")
    equal(lifecycle.boardState, "FROZEN_PENDING", "DebugLog lifecycle parsed")
end

------------------------------------------------------------------------
-- Simulated events
------------------------------------------------------------------------
do
    local board = DR.NormalizeBoard({
        threshold = 120,
        freezeResources = 2,
        slots = { Slot(1, 701, 160), Slot(2, 702, 130) },
    })
    DR.ApplySimulatedEvent(board, { type = "pending_freeze", slot = 2, spell = 702 })
    equal(board.pendingFreezeSlot, 2, "simulated pending freeze slot")
    DR.ApplySimulatedEvent(board, { type = "confirm_freeze", slot = 2, spell = 702 })
    equal(board.pendingFreezeSlot, nil, "confirmed freeze clears pending")
    check(board.slots[2].isFrozen, "confirmed freeze marks slot frozen")
end

------------------------------------------------------------------------
-- Fixture replay (#38-class transcript)
------------------------------------------------------------------------
local function AssertFixtureReplay(path, label, minSteps)
    local results = DR.ReplayFile(path)
    check(results ~= nil, label .. " fixture replay returns results")
    if results and results.errors and #results.errors > 0 then
        for _, err in ipairs(results.errors) do
            io.stderr:write(label .. " FIXTURE: " .. err .. "\n")
        end
    end
    equal(#results.errors, 0, label .. " fixture has no replay errors")
    check(#results.steps >= minSteps, label .. " fixture defines multiple replay steps")
end

do
    AssertFixtureReplay("tests/fixtures/dry_run_issue38_class.txt", "issue38-class", 5)
    AssertFixtureReplay("tests/fixtures/dry_run_guaranteed_select.txt", "guaranteed-select", 3)
    AssertFixtureReplay("tests/fixtures/dry_run_banish_under_threshold.txt", "banish-under-threshold", 3)
end

if failures > 0 then
    io.stderr:write(string.format("test_dry_run: %d failure(s)\n", failures))
    os.exit(1)
end

print("test_dry_run: ok")
