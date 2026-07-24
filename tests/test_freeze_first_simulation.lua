-- High-volume deterministic simulation for freeze/select sequencing.

local function fail(message)
    io.stderr:write("FREEZE-FIRST SIMULATION FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end

local function check(value, message)
    if not value then fail(message) end
end

local addon = {}
assert(loadfile("modules/automation/BoardDecision.lua"))("EbonBuilds", addon)
local D = addon.AutomationBoardDecision

local seed = 20260722
local function Random(limit)
    seed = (seed * 48271) % 2147483647
    return (seed % limit) + 1
end

local function Slot(id, score)
    return { spellId = id, name = "Echo " .. id, score = score, isValid = true }
end

local function Board(slots, threshold)
    local board = {
        slots = slots,
        isValid = true,
        isStable = true,
        maxFrozen = 2,
        freezeThreshold = threshold,
        freezeResources = 2,
        canReroll = false,
        canBanish = false,
        pickIsAcceptable = true,
        frozenThisBoardBySlot = {},
        frozenThisBoardEchoIDs = {},
    }
    for i, slot in ipairs(slots) do
        slot.index = i
        if slot.frozenThisBoard then
            board.frozenThisBoardBySlot[i] = true
            board.frozenThisBoardEchoIDs[slot.spellId] = true
        end
    end
    D.RefreshFrozenState(board)
    return board
end

local function RunSequence(board, boardNumber)
    local actions = {}
    local frozenThisBoard = {}
    local frozenIDs = {}
    for index, value in pairs(board.frozenThisBoardBySlot or {}) do frozenThisBoard[index] = value end
    for echoID, value in pairs(board.frozenThisBoardEchoIDs or {}) do frozenIDs[echoID] = value end
    local freezeCount = 0
    local selectedCarried = false

    for _ = 1, 6 do
        local decision = D.Decide(board)
        local target = decision.target
        actions[#actions + 1] = decision.action .. (target and (":" .. target.index) or "")

        if decision.action == "FREEZE" then
            check(target ~= nil, "freeze has no target on board " .. boardNumber)
            check(decision.selectionTarget ~= nil, "freeze has no intended pick on board " .. boardNumber)
            check(target.index ~= decision.selectionTarget.index,
                "freeze targeted the intended pick on board " .. boardNumber)
            check(target.spellId ~= decision.selectionTarget.spellId,
                "freeze targeted the intended pick identity on board " .. boardNumber)
            check(not target.isFrozen and not target.isCarried,
                "freeze targeted an already frozen Echo on board " .. boardNumber)
            check(not frozenThisBoard[target.index] and not frozenIDs[target.spellId],
                "duplicate freeze on board " .. boardNumber)
            check(D._RequiresPreservation(target, board.freezeThreshold),
                "freeze target was not valuable on board " .. boardNumber)
            check(D._IsValuable(decision.selectionTarget, board.freezeThreshold),
                "freeze occurred without two valuable Echoes on board " .. boardNumber)
            check((board.frozenCount or 0) < 2, "third freeze requested on board " .. boardNumber)

            frozenThisBoard[target.index] = true
            frozenIDs[target.spellId] = true
            board.frozenThisBoardBySlot[target.index] = true
            board.frozenThisBoardEchoIDs[target.spellId] = true
            target.isFrozen = true
            board.freezeResources = math.max(0, board.freezeResources - 1)
            freezeCount = freezeCount + 1
            D.RefreshFrozenState(board)
        elseif decision.action == "SELECT" then
            check(target ~= nil, "selection has no target on board " .. boardNumber)
            check(not frozenThisBoard[target.index] and not frozenIDs[target.spellId],
                "froze and selected the same Echo on board " .. boardNumber)
            check(not D.HasUnsecuredFreezeCandidate(board, target),
                "selected while a qualifying freeze remained on board " .. boardNumber)
            selectedCarried = (target.isFrozen or target.isCarried) and true or false
            break
        elseif decision.action == "REROLL" then
            check((board.frozenCount or 0) == 0 and not board.pendingFreezeSlot
                and not board.frozenStateUncertain,
                "rerolled an unsafe board " .. boardNumber)
            break
        elseif decision.action == "BANISH" or decision.action == "RECOVERY"
            or decision.action == "WAIT" or decision.action == "WAIT_FOR_FREEZE" then
            break
        else
            fail("unknown action " .. tostring(decision.action) .. " on board " .. boardNumber)
        end
    end

    check(freezeCount <= 2, "more than two freezes on board " .. boardNumber)
    return table.concat(actions, ","), freezeCount, selectedCarried
end

-- 30,000 structured boards prove the exact one/two/three-value sequences.
for i = 1, 10000 do
    local threshold = 80 + (i % 80)
    local protected = Slot(i * 10 + 2, threshold - 1)
    protected.isProtected = true
    local sequence = RunSequence(Board({
        Slot(i * 10 + 1, threshold + 30), protected, Slot(i * 10 + 3, threshold - 20),
    }, threshold), i)
    check(sequence == "SELECT:1", "one-value board froze an Echo at case " .. i)

    sequence = RunSequence(Board({
        Slot(i * 10 + 1, threshold + 30), Slot(i * 10 + 2, threshold + 20),
        Slot(i * 10 + 3, threshold - 20),
    }, threshold), 10000 + i)
    check(sequence == "FREEZE:2,SELECT:1", "two-value sequence mismatch at case " .. i)

    sequence = RunSequence(Board({
        Slot(i * 10 + 1, threshold + 30), Slot(i * 10 + 2, threshold + 20),
        Slot(i * 10 + 3, threshold + 10),
    }, threshold), 20000 + i)
    check(sequence == "FREEZE:2,FREEZE:3,SELECT:1", "three-value sequence mismatch at case " .. i)
end

-- Another 30,000 mixed boards exercise policies, existing freezes, resources,
-- protection, locked Echoes, reroll eligibility, and arbitrary score order.
local randomFreezes = 0
for boardNumber = 30001, 60000 do
    local threshold = Random(201) - 1
    local slots = {
        Slot(boardNumber * 10 + 1, Random(301) - 51),
        Slot(boardNumber * 10 + 2, Random(301) - 51),
        Slot(boardNumber * 10 + 3, Random(301) - 51),
    }
    for _, slot in ipairs(slots) do
        slot.isProtected = Random(5) == 1
        slot.isLocked = Random(25) == 1
        if Random(14) == 1 then
            slot.isAvoided = true
            slot.policyBlocked = true
            slot.policyEffect = "exclude"
        end
        slot.banishEligible = Random(8) == 1
    end

    local existingFrozen = Random(3) - 1
    local used = {}
    for _ = 1, existingFrozen do
        local index = Random(3)
        while used[index] do index = (index % 3) + 1 end
        used[index] = true
        slots[index].isFrozen = true
        slots[index].isCarried = true
        slots[index].frozenThisBoard = Random(2) == 1
    end

    local board = Board(slots, threshold)
    board.freezeResources = Random(4) - 1
    board.canReroll = Random(2) == 1
    board.canBanish = Random(3) == 1
    board.pickIsAcceptable = Random(3) ~= 1
    D.RefreshFrozenState(board)

    local _, freezes = RunSequence(board, boardNumber)
    randomFreezes = randomFreezes + freezes

    for _, slot in ipairs(slots) do
        if slot.isProtected and not slot.isLocked and not slot.preserve and not slot.isCrucial
            and (slot.score or 0) < threshold then
            check(not D._RequiresPreservation(slot, threshold),
                "protection alone qualified below threshold on board " .. boardNumber)
        end
    end
end

-- Ten thousand carried-best boards reproduce the real run: the carried Echo
-- must beat lower fresh offers, but an Echo frozen in this turn remains barred.
for i = 1, 10000 do
    local threshold = 100 + (i % 50)
    local board = Board({
        Slot(800000 + i * 3, threshold + 30),
        Slot(800001 + i * 3, threshold - 20),
        Slot(800002 + i * 3, threshold - 30),
    }, threshold)
    board.slots[1].isFrozen = true
    board.slots[1].isCarried = true
    D.RefreshFrozenState(board)
    local sequence, _, selectedCarried = RunSequence(board, 60000 + i)
    check(sequence == "SELECT:1" and selectedCarried,
        "carried best Echo lost to a lower fresh offer at case " .. i)
end

print(string.format("Simulated 70000 boards; freeze/select and carried-pick invariants held (%d random freezes).", randomFreezes))
