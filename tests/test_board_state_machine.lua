-- Unit coverage for WP1 board lifecycle derivation and reroll freeze-lock.

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

local BSM = EbonBuilds.AutomationBoardStateMachine
local D = EbonBuilds.AutomationBoardDecision

local function Snapshot(overrides)
    local snapshot = {
        choices = {
            { spellId = 101, quality = 0 },
            { spellId = 102, quality = 0 },
        },
        slots = {
            { index = 1, spellId = 101, isFrozen = false },
            { index = 2, spellId = 102, isFrozen = false },
        },
        frozenCount = 0,
        boardVisible = true,
    }
    if type(overrides) == "table" then
        for key, value in pairs(overrides) do snapshot[key] = value end
    end
    return snapshot
end

local function BoardFromSnapshot(snapshot)
    local board = {
        slots = snapshot.slots,
        choices = snapshot.choices,
        frozenCount = snapshot.frozenCount or 0,
        pendingFreezeSlot = snapshot.pendingFreezeSlot,
        frozenStateUncertain = snapshot.frozenStateUncertain,
        pendingAction = snapshot.pendingAction,
        serverPendingAction = snapshot.serverPendingAction,
        runFrozenEchoIDs = snapshot.runFrozenEchoIDs,
        frozenThisBoardBySlot = snapshot.frozenThisBoardBySlot,
        frozenThisBoardEchoIDs = snapshot.frozenThisBoardEchoIDs,
        isValid = true,
        isStable = true,
        canReroll = true,
        pickIsAcceptable = false,
        freezeThreshold = 120,
        freezeResources = 2,
        maxFrozen = 2,
    }
    D.RefreshFrozenState(board)
    BSM.Attach(board, board)
    return board
end

local function DeriveState(snapshot)
    return BSM.Derive(snapshot)
end

local function DeriveTriple(snapshot)
    return BSM.Derive(snapshot)
end

local function Step(snap, overrides, expectedState, expectedReason, label)
    if type(overrides) == "table" then
        for key, value in pairs(overrides) do
            if key:sub(1, 1) == "_" then
                for _, clearKey in ipairs(value) do snap[clearKey] = nil end
            else
                snap[key] = value
            end
        end
    end
    local state, reason = DeriveTriple(snap)
    equal(state, expectedState, label .. " state")
    if expectedReason then
        equal(reason, expectedReason, label .. " reason")
    end
    return state, reason
end

------------------------------------------------------------------------
-- Derive transitions
------------------------------------------------------------------------
do
    local state, reason, source = BSM.Derive(Snapshot())
    equal(state, BSM.STATE.OPEN, "fresh board is OPEN")
    equal(reason, BSM.REASON.FRESH_BOARD, "fresh board reason")
    equal(source, "derived", "fresh board source")

    state = BSM.Derive(Snapshot({ pendingFreezeSlot = 2 }))
    equal(state, BSM.STATE.FROZEN_PENDING, "pending freeze slot -> FROZEN_PENDING")

    state = BSM.Derive(Snapshot({ serverPendingAction = "freeze" }))
    equal(state, BSM.STATE.FROZEN_PENDING, "server pending freeze -> FROZEN_PENDING")

    state = BSM.Derive(Snapshot({ frozenStateUncertain = true }))
    equal(state, BSM.STATE.FROZEN_PENDING, "uncertain freeze -> FROZEN_PENDING")

    state = BSM.Derive(Snapshot({
        slots = {
            { index = 1, spellId = 101, isFrozen = false },
            { index = 2, spellId = 102, isFrozen = true },
        },
        frozenCount = 1,
    }))
    equal(state, BSM.STATE.CONFIRMED, "confirmed freeze flag -> CONFIRMED")

    state = BSM.Derive(Snapshot({
        choices = {
            { spellId = 101, quality = 0 },
            { spellId = 102, quality = 0, justFrozen = true },
        },
        frozenCount = 1,
    }))
    equal(state, BSM.STATE.CONFIRMED, "justFrozen choice -> CONFIRMED")

    state = BSM.Derive(Snapshot({
        runFrozenEchoIDs = { [102] = true },
        frozenCount = 1,
    }))
    equal(state, BSM.STATE.CONFIRMED, "run-persistent frozen echo -> CONFIRMED")

    state = BSM.Derive(Snapshot({
        boardVisible = false,
        choices = {},
        pendingAction = "select",
    }))
    equal(state, BSM.STATE.SPENT, "select with hidden board -> SPENT")

    state = BSM.Derive(Snapshot({ serverBoardState = BSM.STATE.CONFIRMED }))
    equal(state, BSM.STATE.CONFIRMED, "server boardState wins when present")
    equal(BSM.Derive(Snapshot({ serverBoardState = BSM.STATE.CONFIRMED })), BSM.STATE.CONFIRMED,
        "server authoritative repeat")
end

------------------------------------------------------------------------
-- Reroll hard block
------------------------------------------------------------------------
do
    check(BSM.IsRerollBlocked(BSM.STATE.FROZEN_PENDING), "FROZEN_PENDING blocks reroll")
    check(BSM.IsRerollBlocked(BSM.STATE.CONFIRMED), "CONFIRMED blocks reroll")
    check(BSM.IsRerollBlocked(BSM.STATE.SPENT), "SPENT blocks reroll")
    check(not BSM.IsRerollBlocked(BSM.STATE.OPEN), "OPEN does not hard-block reroll")

    local board = BoardFromSnapshot(Snapshot({
        slots = {
            { index = 1, spellId = 101, score = 50, isValid = true },
            { index = 2, spellId = 102, score = 150, isFrozen = true, isValid = true },
        },
        frozenCount = 1,
    }))
    local allowed, reason = D.CanReroll(board)
    check(not allowed, "CanReroll rejects CONFIRMED lifecycle")
    check(reason and reason:find("confirmed freeze", 1, true) ~= nil,
        "CanReroll reason mentions confirmed freeze")

    board = BoardFromSnapshot(Snapshot({ pendingFreezeSlot = 2 }))
    allowed = D.CanReroll(board)
    check(not allowed, "CanReroll rejects FROZEN_PENDING lifecycle")
end

------------------------------------------------------------------------
-- Decide integration
------------------------------------------------------------------------
do
    local board = BoardFromSnapshot(Snapshot({ pendingFreezeSlot = 2 }))
    local decision = D.Decide(board)
    equal(decision.action, "WAIT_FOR_FREEZE", "Decide waits on FROZEN_PENDING lifecycle")
end

------------------------------------------------------------------------
-- Full lifecycle: OPEN -> FROZEN_PENDING -> CONFIRMED -> SPENT
------------------------------------------------------------------------
do
    local snap = Snapshot()
    Step(snap, nil, BSM.STATE.OPEN, BSM.REASON.FRESH_BOARD,
        "lifecycle step 1 OPEN")

    Step(snap, { pendingFreezeSlot = 2 }, BSM.STATE.FROZEN_PENDING, BSM.REASON.FREEZE_IN_FLIGHT,
        "lifecycle step 2 FROZEN_PENDING")

    Step(snap, {
        _clear = { "pendingFreezeSlot", "pendingAction", "serverPendingAction", "frozenStateUncertain" },
        slots = {
            { index = 1, spellId = 101, isFrozen = false },
            { index = 2, spellId = 102, isFrozen = true },
        },
        frozenCount = 1,
    }, BSM.STATE.CONFIRMED, BSM.REASON.FREEZE_CONFIRMED,
        "lifecycle step 3 CONFIRMED")

    Step(snap, {
        boardVisible = false,
        choices = {},
        slots = {},
        pendingAction = "select",
    }, BSM.STATE.SPENT, BSM.REASON.AFTER_SELECT,
        "lifecycle step 4 SPENT")

    local board = BoardFromSnapshot(Snapshot())
    equal(board.lifecycleState, BSM.STATE.OPEN, "Attach starts OPEN")

    board.pendingFreezeSlot = 2
    board.boardState = nil
    board.serverBoardState = nil
    BSM.Attach(board, board)
    equal(board.lifecycleState, BSM.STATE.FROZEN_PENDING, "Attach follows pending freeze")

    board.pendingFreezeSlot = nil
    board.slots[2].isFrozen = true
    board.frozenCount = 1
    board.boardState = nil
    board.serverBoardState = nil
    D.RefreshFrozenState(board)
    BSM.Attach(board, board)
    equal(board.lifecycleState, BSM.STATE.CONFIRMED, "Attach follows confirmed freeze")
    equal(board.boardState, BSM.STATE.CONFIRMED, "Attach sets boardState alias")

    board.boardVisible = false
    board.choices = {}
    board.slots = {}
    board.pendingAction = "select"
    board.boardState = nil
    board.serverBoardState = nil
    BSM.Attach(board, board)
    equal(board.lifecycleState, BSM.STATE.SPENT, "Attach follows spent board")
    equal(board.lifecycleReasonCode, BSM.REASON.AFTER_SELECT, "Attach spent reason")
end

------------------------------------------------------------------------
-- Illegal / guarded derivations (must not skip lifecycle stages)
------------------------------------------------------------------------
do
    equal(DeriveState(Snapshot({ pendingAction = "select" })), BSM.STATE.OPEN,
        "illegal OPEN->SPENT blocked while board visible")

    equal(DeriveState(Snapshot({ serverPendingAction = "select" })), BSM.STATE.OPEN,
        "illegal OPEN->SPENT blocked for server select on visible board")

    equal(DeriveState(Snapshot({
        pendingFreezeSlot = 2,
        slots = {
            { index = 1, spellId = 101, isFrozen = false },
            { index = 2, spellId = 102, isFrozen = true },
        },
        frozenCount = 1,
    })), BSM.STATE.FROZEN_PENDING,
        "illegal FROZEN_PENDING->CONFIRMED blocked while freeze pending")

    equal(DeriveState(Snapshot({ pendingFreezeSlot = 2 })), BSM.STATE.FROZEN_PENDING,
        "illegal FROZEN_PENDING->OPEN blocked while pending slot set")

    equal(DeriveState(Snapshot({ frozenStateUncertain = true })), BSM.STATE.FROZEN_PENDING,
        "illegal FROZEN_PENDING->OPEN blocked while uncertain")

    equal(DeriveState(Snapshot({
        slots = {
            { index = 1, spellId = 101, isFrozen = false },
            { index = 2, spellId = 102, isFrozen = true },
        },
        frozenCount = 1,
    })), BSM.STATE.CONFIRMED,
        "illegal CONFIRMED->OPEN blocked while isFrozen remains")

    equal(DeriveState(Snapshot({
        frozenThisBoardBySlot = { [2] = true },
        frozenCount = 1,
    })), BSM.STATE.CONFIRMED,
        "illegal CONFIRMED->OPEN blocked for frozenThisBoardBySlot")

    equal(DeriveState(Snapshot({
        frozenThisBoardEchoIDs = { [102] = true },
        frozenCount = 1,
    })), BSM.STATE.CONFIRMED,
        "illegal CONFIRMED->OPEN blocked for frozenThisBoardEchoIDs")

    equal(DeriveState(Snapshot()), BSM.STATE.OPEN,
        "illegal OPEN->CONFIRMED blocked without freeze signals")

    equal(DeriveState(Snapshot({
        boardVisible = false,
        choices = {},
        slots = {},
    })), BSM.STATE.OPEN,
        "hidden empty board without select stays OPEN (not SPENT)")

    equal(DeriveState(Snapshot({ serverBoardState = "BROKEN" })), BSM.STATE.OPEN,
        "invalid serverBoardState ignored -> derived OPEN")
    equal(DeriveState(Snapshot({ boardState = "PARTIAL" })), BSM.STATE.OPEN,
        "invalid boardState alias ignored -> derived OPEN")

    check(not BSM.IsValidState("BROKEN"), "IsValidState rejects unknown state")
    check(not BSM.IsValidState(nil), "IsValidState rejects nil")
    for _, valid in pairs(BSM.STATE) do
        check(BSM.IsValidState(valid), "IsValidState accepts " .. valid)
    end
end

------------------------------------------------------------------------
-- Reroll block reason codes and messages per lifecycle state
------------------------------------------------------------------------
do
    equal(BSM.RerollBlockReason(BSM.STATE.OPEN), nil, "OPEN has no reroll block reason")
    equal(BSM.RerollBlockMessage(BSM.STATE.OPEN), nil, "OPEN has no reroll block message")

    equal(BSM.RerollBlockReason(BSM.STATE.FROZEN_PENDING), BSM.REASON.FREEZE_IN_FLIGHT,
        "FROZEN_PENDING reroll reason")
    check(BSM.RerollBlockMessage(BSM.STATE.FROZEN_PENDING):find("pending", 1, true) ~= nil,
        "FROZEN_PENDING reroll message mentions pending")

    equal(BSM.RerollBlockReason(BSM.STATE.FROZEN_PENDING, BSM.REASON.FREEZE_UNCERTAIN),
        BSM.REASON.FREEZE_UNCERTAIN, "FROZEN_PENDING preserves uncertain reason code")
    check(BSM.RerollBlockMessage(BSM.STATE.FROZEN_PENDING, BSM.REASON.FREEZE_UNCERTAIN)
        :find("pending", 1, true) ~= nil,
        "uncertain freeze reroll message mentions pending")

    equal(BSM.RerollBlockReason(BSM.STATE.CONFIRMED), BSM.REASON.FREEZE_CONFIRMED,
        "CONFIRMED reroll reason")
    check(BSM.RerollBlockMessage(BSM.STATE.CONFIRMED):find("confirmed freeze", 1, true) ~= nil,
        "CONFIRMED reroll message mentions confirmed freeze")

    equal(BSM.RerollBlockReason(BSM.STATE.SPENT), BSM.REASON.AFTER_SELECT,
        "SPENT reroll reason")
    check(BSM.RerollBlockMessage(BSM.STATE.SPENT):find("spent", 1, true) ~= nil,
        "SPENT reroll message mentions spent")

    local spentBoard = BoardFromSnapshot(Snapshot({
        boardVisible = false,
        choices = {},
        slots = {},
        pendingAction = "select",
    }))
    spentBoard.boardVisible = false
    spentBoard.boardState = nil
    spentBoard.serverBoardState = nil
    BSM.Attach(spentBoard, spentBoard)
    local allowed, reason = D.CanReroll(spentBoard)
    check(not allowed, "CanReroll rejects SPENT lifecycle")
    check(reason and reason:find("spent", 1, true) ~= nil,
        "CanReroll SPENT reason mentions spent")
end

------------------------------------------------------------------------
-- Server authority overrides derived lifecycle (including SPENT)
------------------------------------------------------------------------
do
    local state, reason, source = DeriveTriple(Snapshot({
        pendingFreezeSlot = 2,
        serverBoardState = BSM.STATE.OPEN,
    }))
    equal(state, BSM.STATE.OPEN, "server OPEN overrides derived FROZEN_PENDING")
    equal(reason, BSM.REASON.SERVER, "server override reason")
    equal(source, "server", "server override source")

    state = DeriveState(Snapshot({
        slots = {
            { index = 1, spellId = 101, isFrozen = true },
        },
        frozenCount = 1,
        serverBoardState = BSM.STATE.SPENT,
    }))
    equal(state, BSM.STATE.SPENT, "server SPENT overrides derived CONFIRMED")

    state, reason = DeriveTriple(Snapshot({ boardState = BSM.STATE.FROZEN_PENDING }))
    equal(state, BSM.STATE.FROZEN_PENDING, "boardState alias accepted as server authority")
    equal(reason, BSM.REASON.SERVER, "boardState alias uses server reason")
end

if failures > 0 then
    io.stderr:write(string.format("\n%d board state machine test(s) failed.\n", failures))
    os.exit(1)
end

print("test_board_state_machine: ok")
