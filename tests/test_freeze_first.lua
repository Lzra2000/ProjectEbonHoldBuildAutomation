-- Deterministic regression coverage for the freeze-first board decider.

local function fail(message)
    io.stderr:write("FREEZE-FIRST FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end

local function equal(actual, expected, message)
    if actual ~= expected then
        fail(string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
    end
end

local function truthy(value, message)
    if not value then fail(message) end
end

local addon = {}
assert(loadfile("modules/automation/BoardDecision.lua"))("EbonBuilds", addon)
local D = addon.AutomationBoardDecision

local function Slot(id, score, flags)
    local slot = { spellId = id, name = "Echo " .. tostring(id), score = score, isValid = true }
    for key, value in pairs(flags or {}) do slot[key] = value end
    return slot
end

local function Board(slots, options)
    local board = {
        slots = slots,
        isValid = true,
        isStable = true,
        maxFrozen = 2,
        freezeThreshold = 120,
        freezeResources = 2,
        canReroll = true,
        canBanish = false,
        frozenThisBoardBySlot = {},
        frozenThisBoardEchoIDs = {},
    }
    for key, value in pairs(options or {}) do board[key] = value end
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

local function Decision(board, expected, message)
    local result = D.Decide(board)
    equal(result.action, expected, message)
    return result
end

local function Sequence(board, limit)
    local actions = {}
    for _ = 1, limit or 8 do
        local result = D.Decide(board)
        local suffix = result.target and (":" .. tostring(result.target.index)) or ""
        actions[#actions + 1] = result.action .. suffix
        if result.action == "FREEZE" then
            result.target.isFrozen = true
            board.frozenThisBoardBySlot[result.target.index] = true
            board.frozenThisBoardEchoIDs[result.target.spellId] = true
            board.freezeResources = math.max(0, board.freezeResources - 1)
            D.RefreshFrozenState(board)
        elseif result.action == "SELECT" or result.action == "RECOVERY"
            or result.action == "REROLL" or result.action == "BANISH" then
            break
        else
            break
        end
    end
    return table.concat(actions, ",")
end

-- Direct selection when no Echo qualifies for freezing.
equal(Sequence(Board({ Slot(101, 110), Slot(102, 90), Slot(103, 80) })),
    "SELECT:1", "direct selection sequence")

-- One and two freezes must precede selection, strongest secondary first.
equal(Sequence(Board({ Slot(101, 160), Slot(102, 130), Slot(103, 80) })),
    "FREEZE:2,SELECT:1", "single-freeze sequence")
equal(Sequence(Board({ Slot(101, 160), Slot(102, 145), Slot(103, 130) })),
    "FREEZE:2,FREEZE:3,SELECT:1", "two-freeze sequence")

-- Echoes frozen on this board count independently, leave the second slot
-- usable, and cannot be selected during the same turn.
equal(Sequence(Board({ Slot(101, 170), Slot(102, 150, { isFrozen = true, frozenThisBoard = true }), Slot(103, 125) })),
    "FREEZE:3,SELECT:1", "one existing frozen Echo still permits a second freeze")
equal(Sequence(Board({ Slot(101, 170), Slot(102, 150, { isFrozen = true, frozenThisBoard = true }), Slot(103, 125, { isFrozen = true, frozenThisBoard = true }) })),
    "SELECT:1", "two existing frozen Echoes select the legal unfrozen target")

-- On the next board a carried Echo is selectable by effective score. A strong
-- fresh secondary is still frozen first, without reselecting that new freeze.
local carriedBest = Decision(Board({
    Slot(101, 117, { isFrozen = true, isCarried = true }), Slot(102, 25), Slot(103, 20),
}, { freezeResources = 0 }), "SELECT", "carried Echo is a legal selection on the next board")
equal(carriedBest.target.index, 1, "lower-valued fresh Echo displaced the carried Echo")
equal(Sequence(Board({
    Slot(101, 160, { isFrozen = true, isCarried = true }), Slot(102, 140), Slot(103, 20),
})), "FREEZE:2,SELECT:1", "carried best Echo remains selectable after securing a fresh secondary")

-- Two confirmed freezes are the board capacity even if resources remain.
local fullBoard = Board({
    Slot(101, 180), Slot(102, 170, { isFrozen = true, frozenThisBoard = true }),
    Slot(103, 160, { isFrozen = true, frozenThisBoard = true }), Slot(104, 150),
}, { freezeResources = 9 })
local fullDecision = Decision(fullBoard, "SELECT", "third freeze refused")
equal(fullDecision.target.index, 1, "full board keeps deterministic best selection")

-- Protection only prevents banish/family blocking; it is not freeze value.
equal(Sequence(Board({ Slot(101, 160), Slot(102, 40, { isProtected = true }), Slot(103, 20) })),
    "SELECT:1", "protected Echo below threshold is not frozen")
equal(Sequence(Board({ Slot(101, 160), Slot(102, 30, { isLocked = true }), Slot(103, 20) })),
    "FREEZE:2,SELECT:1", "locked Echo below threshold is frozen")
equal(Sequence(Board({ Slot(101, 100), Slot(102, 30, { isLocked = true }), Slot(103, 20) })),
    "SELECT:1", "freeze requires two valuable Echoes, not one locked secondary")

-- Both pre-selection guards return freeze/wait instead of select.
local pending = Board({ Slot(101, 160), Slot(102, 130) }, {
    pendingFreezeSlot = 2, pendingFreezeEchoID = 102,
})
Decision(pending, "WAIT_FOR_FREEZE", "selection blocked while freeze confirmation is pending")
Decision(Board({ Slot(101, 160), Slot(102, 130) }), "FREEZE",
    "selection blocked while qualifying unfrozen candidate remains")
local confirmedPending = Board({ Slot(101, 160), Slot(102, 130, { isFrozen = true }) })
equal(D.ClassifyPendingFreeze(confirmedPending, 2, 102, D.IdentityFingerprint(confirmedPending)),
    "confirmed", "server-reported frozen state confirms the request")
Decision(Board({ Slot(101, 100) }, { pendingAction = "select" }), "WAIT",
    "duplicate click blocked while a board action is pending")

-- Reroll is an absolute zero-frozen, zero-pending, known-state operation.
local oneFrozen = Board({ Slot(101, 10, { isFrozen = true, isAvoided = true }) })
local allowed, reason = D.CanReroll(oneFrozen)
equal(allowed, false, "reroll blocked with one frozen Echo")
truthy(reason:find("frozen Echo", 1, true), "one-frozen reroll reason")
Decision(oneFrozen, "RECOVERY", "one-frozen no-pick board recovers safely")

local twoFrozen = Board({
    Slot(101, 10, { isFrozen = true, isAvoided = true }),
    Slot(102, 20, { isFrozen = true, isAvoided = true }),
})
equal(D.CanReroll(twoFrozen), false, "reroll blocked with two frozen Echoes")
Decision(twoFrozen, "RECOVERY", "two-frozen no-pick board recovers safely")

local pendingReroll = Board({ Slot(101, 10, { isAvoided = true }) }, {
    pendingFreezeSlot = 1, pendingFreezeEchoID = 101,
})
equal(D.CanReroll(pendingReroll), false, "reroll blocked while freeze confirmation is pending")
Decision(pendingReroll, "WAIT_FOR_FREEZE", "pending freeze waits before reroll")

local uncertain = Board({ Slot(101, 10, { isAvoided = true }) }, { frozenStateUncertain = true })
equal(D.CanReroll(uncertain), false, "reroll blocked when frozen state is uncertain")
Decision(uncertain, "RECOVERY", "uncertain frozen state enters recovery")

local zeroFrozen = Board({ Slot(101, 10, { isAvoided = true }) })
equal(D.CanReroll(zeroFrozen), true, "reroll allowed only with exactly zero frozen Echoes")
Decision(zeroFrozen, "REROLL", "zero-frozen no-pick board may reroll")
local weakLegal = Board({ Slot(101, 40), Slot(102, 30) }, { pickIsAcceptable = false })
Decision(weakLegal, "REROLL", "current reroll policy may reject a weak legal pick on a zero-frozen board")
local weakWithFrozen = Board({
    Slot(101, 40), Slot(102, 130, { isFrozen = true }),
}, { pickIsAcceptable = false })
local carriedWeakDecision = Decision(weakWithFrozen, "SELECT", "a frozen board selects instead of overriding the no-reroll rule")
equal(carriedWeakDecision.target.index, 2, "carried Echo lost to a weaker fresh Echo")

-- Freeze failure never falls through to select or reroll on the same board.
local failedFreeze = Board({ Slot(101, 160), Slot(102, 130) })
local first = Decision(failedFreeze, "FREEZE", "freeze failure scenario begins with freeze")
failedFreeze.failedFreezeBySlot = { [first.target.index] = true }
failedFreeze.frozenStateUncertain = true
equal("FREEZE:" .. first.target.index .. "," .. D.Decide(failedFreeze).action,
    "FREEZE:2,RECOVERY", "freeze failure action sequence")

-- A changed identity cancels the old pending target and re-evaluates fresh IDs.
local oldBoard = Board({ Slot(101, 160), Slot(102, 130) })
local oldAction = Decision(oldBoard, "FREEZE", "old board freeze request")
local oldIdentity = D.IdentityFingerprint(oldBoard)
local newBoard = Board({ Slot(201, 100), Slot(202, 110), Slot(203, 90) })
equal(D.ClassifyPendingFreeze(newBoard, oldAction.target.index, oldAction.target.spellId, oldIdentity),
    "board_changed", "board change detected after freeze request")
local newAction = Decision(newBoard, "SELECT", "new board re-evaluated after stale request")
equal(newAction.target.spellId, 202, "new board uses fresh slot identity")

-- Duplicate Echo identity and duplicate slot requests cannot consume two freezes.
local duplicate = Board({
    Slot(101, 160), Slot(102, 150, { isFrozen = true }), Slot(102, 140),
})
Decision(duplicate, "SELECT", "same Echo identity is not frozen twice")

-- Fingerprints reject stale slot execution, including frozen-state changes.
local staleBefore = Board({ Slot(101, 160), Slot(102, 110) })
local evaluatedFingerprint = D.Fingerprint(staleBefore)
local staleAfter = Board({ Slot(201, 80), Slot(202, 170) })
equal(D.MatchesFingerprint(staleAfter, evaluatedFingerprint), false, "stale board fingerprint rejected")
local freshAction = Decision(staleAfter, "SELECT", "changed board receives a fresh decision")
equal(freshAction.target.index, 2, "fresh decision never uses old target slot")

-- Equal scores resolve left-to-right for both pick and freeze ordering.
equal(Sequence(Board({ Slot(101, 150), Slot(102, 150), Slot(103, 150) })),
    "FREEZE:2,FREEZE:3,SELECT:1", "equal-score behavior is deterministic")

-- Avoid/never-pick policies are neither selected nor frozen.
local avoided = Board({
    Slot(101, 200, { policyEffect = "exclude", policyBlocked = true }),
    Slot(102, 190, { isBanned = true }),
    Slot(103, 100),
})
local avoidedAction = Decision(avoided, "SELECT", "avoid and never-pick policies remain hard rules")
equal(avoidedAction.target.index, 3, "policy-safe target selected")

local banishOnly = Board({
    Slot(101, 30, { policyEffect = "banish", policyBlocked = true }),
    Slot(102, 20, { isBanned = true }),
}, { canBanish = true })
local banishAction = Decision(banishOnly, "BANISH", "banish considered only with no acceptable pick")
equal(banishAction.target.index, 2, "deterministic weakest banish target")
local thresholdBanish = Board({
    Slot(101, 35, { banishEligible = true }), Slot(102, 45),
}, { canBanish = true, pickIsAcceptable = false })
local thresholdBanishAction = Decision(thresholdBanish, "BANISH", "existing banish threshold remains active")
equal(thresholdBanishAction.target.index, 1, "threshold banish target is deterministic")
local protectedBanish = Board({
    Slot(101, 35, { banishEligible = true, isProtected = true }), Slot(102, 30),
}, { canBanish = true, canReroll = true, pickIsAcceptable = false })
Decision(protectedBanish, "REROLL", "protection remains a banish safeguard without causing a freeze")

-- Pending second freeze is represented while the first remains confirmed.
local secondPending = Board({
    Slot(101, 170), Slot(102, 150, { isFrozen = true }), Slot(103, 130),
}, { pendingFreezeSlot = 3, pendingFreezeEchoID = 103 })
Decision(secondPending, "WAIT_FOR_FREEZE", "one confirmed plus one pending freeze is supported")

-- Server ProjectEbonhold flags: the guaranteed card injected from the active
-- build slot reappears in every draw. It stays selectable, but the server
-- refuses to freeze or banish it, and it never blocks rerolls.
equal(Sequence(Board({ Slot(101, 160), Slot(102, 130, { isGuaranteed = true }), Slot(103, 20) })),
    "SELECT:1", "guaranteed Echo above the freeze threshold is not frozen")
local guaranteedBest = Decision(Board({
    Slot(101, 160, { isGuaranteed = true }), Slot(102, 30), Slot(103, 20),
}), "SELECT", "guaranteed Echo remains selectable")
equal(guaranteedBest.target.index, 1, "guaranteed Echo is a legal best pick")
local guaranteedBanish = Board({
    Slot(101, 10, { isGuaranteed = true, banishEligible = true }),
    Slot(102, 20, { banishEligible = true }),
}, { canBanish = true, pickIsAcceptable = false })
local guaranteedBanishAction = Decision(guaranteedBanish, "BANISH",
    "banish still fires while a guaranteed Echo is present")
equal(guaranteedBanishAction.target.index, 2, "guaranteed Echo is never the banish target")
local guaranteedReroll = Board({
    Slot(101, 10, { isGuaranteed = true, isAvoided = true }),
    Slot(102, 5, { isAvoided = true }),
})
equal(D.CanReroll(guaranteedReroll), true, "guaranteed Echo does not block rerolls")

print("Verified freeze-first decisions, two-slot state, confirmations, stale guards, and action sequences.")
