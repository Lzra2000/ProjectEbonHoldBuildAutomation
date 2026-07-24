-- Unit vectors for shared automation tie-break policy (WP2 / #51).

local function fail(message)
    io.stderr:write("TIE-BREAK FAIL: " .. tostring(message) .. "\n")
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

local addon = {}
assert(loadfile("modules/build/Scoring.lua"))("EbonBuilds", addon)
assert(loadfile("modules/automation/BoardDecision.lua"))("EbonBuilds", addon)
local S = addon.Scoring
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

local selectOpts = { preferFrozen = true }

check(S.IsBetterCandidate(Slot(101, 200), Slot(102, 150), selectOpts), "higher score wins")
check(not S.IsBetterCandidate(Slot(101, 150), Slot(102, 200), selectOpts), "lower score loses")

local left = Slot(101, 150, { index = 1 })
local right = Slot(102, 150, { index = 2 })
check(S.IsBetterCandidate(left, right, selectOpts), "equal score without rank prefers lower slot index")
equal(D.FindBestLegalPick(Board({ left, right })).index, 1,
    "BoardDecision select matches slot-index fallback")

local rankedRight = Slot(102, 150, { index = 2, rank = 1 })
local rankedLeft = Slot(101, 150, { index = 1, rank = 2 })
check(S.IsBetterCandidate(rankedRight, rankedLeft, selectOpts),
    "lower server rank beats higher slot index on equal score")
equal(D.FindBestLegalPick(Board({ rankedLeft, rankedRight })).spellId, 102,
    "BoardDecision honors server rank over slot index")

local onlyRanked = Slot(102, 150, { index = 2, rank = 5 })
local unranked = Slot(101, 150, { index = 1 })
check(S.IsBetterCandidate(unranked, onlyRanked, selectOpts),
    "missing rank on one card keeps slot-index ordering")

local lowId = Slot(500, 150, { index = 1, rank = 1 })
local highId = Slot(501, 150, { index = 1, rank = 1 })
check(S.IsBetterCandidate(lowId, highId, selectOpts), "lower spell ID wins final tie")

local dupFresh = Slot(102, 150, { index = 2, rank = 1 })
local dupFrozen = Slot(102, 150, { index = 3, rank = 1, isFrozen = true })
check(S.IsBetterCandidate(dupFresh, dupFrozen, selectOpts),
    "slot index still resolves duplicate-echo ties before frozen preference")

local banishLeft = Slot(601, 20, { index = 1 })
local banishRight = Slot(602, 20, { index = 2 })
check(S.IsWorseCandidate(banishLeft, banishRight), "banish prefers lower slot index among equals")

local equalBoard = Board({ Slot(101, 150), Slot(102, 150), Slot(103, 150) })
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
        else
            break
        end
    end
    return table.concat(actions, ",")
end
equal(Sequence(equalBoard), "FREEZE:2,FREEZE:3,SELECT:1",
    "equal-score freeze-first sequence is deterministic without ranks")

local rankedEqual = Board({
    Slot(101, 150, { rank = 3 }),
    Slot(102, 150, { rank = 2 }),
    Slot(103, 150, { rank = 1 }),
})
equal(Sequence(rankedEqual), "FREEZE:2,FREEZE:1,SELECT:3",
    "server ranks reorder freeze/select while staying deterministic")

local aligned = Board({ Slot(101, 150, { rank = 1 }), Slot(102, 150, { rank = 2 }) })
equal(D.DebugServerRankMismatch(aligned), false, "aligned ranks produce no debug mismatch")
local misaligned = Board({ Slot(101, 150, { rank = 2 }), Slot(102, 150, { rank = 1 }) })
equal(D.DebugServerRankMismatch(misaligned), false,
    "rank-aware client pick matches server order on equal scores")
equal(D.FindBestLegalPick(misaligned).spellId, 102,
    "best legal pick follows lowest server rank")

print("Verified shared tie-break chain: score -> rank -> slot -> spellId -> frozen.")
