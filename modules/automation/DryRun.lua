local addonName, EbonBuilds = ...

-- EbonBuilds: modules/automation/DryRun.lua
-- Responsibility: pure dry-run / simulation for Autopilot board decisions.
-- Client-side stepping stone for WP4 (#53): given a board snapshot, weights,
-- and frozen/pending state, returns what BoardDecision would choose without
-- sending ProjectEbonhold requests. Supports transcript replay for Logbook /
-- DebugLog / message.txt style exports in CI.

EbonBuilds.AutomationDryRun = {}

local M = EbonBuilds.AutomationDryRun

local POLICY_ACTION = {
    SELECT = "select",
    FREEZE = "freeze",
    BANISH = "banish",
    REROLL = "reroll",
    WAIT = "wait",
    WAIT_FOR_FREEZE = "wait",
    RECOVERY = "wait",
}

local WAIT_REASON = {
    WAIT = "board_unstable",
    WAIT_FOR_FREEZE = "freeze_lock_pending",
    RECOVERY = "recovery",
}

local function Trim(text)
    if text == nil then return "" end
    return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function EchoKey(slot)
    if not slot then return nil end
    return tonumber(slot.spellId) or slot.echoId or slot.refKey
end

local function DecisionModule()
    return EbonBuilds.AutomationBoardDecision
end

local function StateMachine()
    return EbonBuilds.AutomationBoardStateMachine
end

function M.NormalizePolicyAction(decisionAction)
    if decisionAction == nil then return "wait" end
    return POLICY_ACTION[decisionAction] or string.lower(tostring(decisionAction))
end

function M.ReasonCodeFor(decision, board)
    local action = decision and decision.action
    if action == "WAIT_FOR_FREEZE" then
        local BSM = StateMachine()
        if board and board.lifecycleReasonCode then return board.lifecycleReasonCode end
        if BSM then return BSM.REASON.FREEZE_IN_FLIGHT end
        return "freeze_lock_pending"
    end
    if action == "WAIT" then return WAIT_REASON.WAIT end
    if action == "RECOVERY" then return WAIT_REASON.RECOVERY end
    if action == "REROLL" and board then
        local BSM = StateMachine()
        if BSM and BSM.IsRerollBlocked(board.lifecycleState) then
            return BSM.RerollBlockReason(board.lifecycleState, board.lifecycleReasonCode)
                or "reroll_blocked"
        end
    end
    if action == "FREEZE" then return "freeze_first" end
    if action == "SELECT" then return "select_best" end
    if action == "BANISH" then return "banish_weak" end
    if action == "REROLL" then return "reroll_no_pick" end
    return "unknown"
end

function M.NormalizeBoard(input)
    input = type(input) == "table" and input or {}
    local D = DecisionModule()
    if not D then return nil, "BoardDecision unavailable" end

    local slots = {}
    local rawSlots = input.slots or input.choices or {}
    local weights = input.weights or input.scores
    for i, entry in ipairs(rawSlots) do
        local slot
        if type(entry) == "table" then
            slot = {}
            for key, value in pairs(entry) do slot[key] = value end
        else
            slot = { spellId = entry }
        end
        slot.index = tonumber(slot.index) or i
        if weights then
            local key = EchoKey(slot)
            local weighted = weights[key] or weights[tostring(key)] or weights[slot.index]
            if weighted ~= nil then slot.score = tonumber(weighted) end
        end
        slot.isValid = slot.isValid ~= false
        slots[#slots + 1] = slot
    end

    local board = {
        slots = slots,
        isValid = input.isValid ~= false and #slots > 0,
        isStable = input.isStable ~= false,
        maxFrozen = tonumber(input.maxFrozen) or D.MAX_FROZEN_PER_BOARD,
        freezeThreshold = tonumber(input.freezeThreshold or input.threshold) or math.huge,
        freezeResources = tonumber(input.freezeResources) or 0,
        canReroll = input.canReroll and true or false,
        canBanish = input.canBanish and true or false,
        pickIsAcceptable = input.pickIsAcceptable ~= false,
        pendingFreezeSlot = input.pendingFreezeSlot,
        pendingFreezeEchoID = input.pendingFreezeEchoID,
        pendingAction = input.pendingAction,
        serverPendingAction = input.serverPendingAction,
        frozenStateUncertain = input.frozenStateUncertain and true or false,
        failedFreezeBySlot = input.failedFreezeBySlot,
        frozenThisBoardBySlot = {},
        frozenThisBoardEchoIDs = {},
        runFrozenEchoIDs = {},
        offerId = input.offerId,
        serverBoardState = input.serverBoardState or input.boardState,
    }

    if type(input.frozenThisBoardBySlot) == "table" then
        for key, value in pairs(input.frozenThisBoardBySlot) do
            board.frozenThisBoardBySlot[key] = value
        end
    end
    if type(input.frozenThisBoardEchoIDs) == "table" then
        for key, value in pairs(input.frozenThisBoardEchoIDs) do
            board.frozenThisBoardEchoIDs[key] = value
        end
    end
    if type(input.runFrozenEchoIDs) == "table" then
        for key, value in pairs(input.runFrozenEchoIDs) do
            board.runFrozenEchoIDs[key] = value
        end
    end

    for i, slot in ipairs(slots) do
        if slot.frozenThisBoard then
            board.frozenThisBoardBySlot[slot.index or i] = true
            local key = EchoKey(slot)
            if key ~= nil then board.frozenThisBoardEchoIDs[key] = true end
        end
    end

    D.RefreshFrozenState(board)
    local BSM = StateMachine()
    if BSM then BSM.Attach(board, board) end
    return board
end

function M.VerdictFromDecision(board, decision)
    decision = decision or {}
    local target = decision.target
    return {
        boardState = board and board.lifecycleState or board and board.boardState,
        action = M.NormalizePolicyAction(decision.action),
        rawAction = decision.action,
        targetSlot = target and (tonumber(target.index) or 0) or -1,
        targetSpellId = target and (EchoKey(target) or 0) or 0,
        reasonCode = M.ReasonCodeFor(decision, board),
        reason = decision.reason,
        selectionTargetSlot = decision.selectionTarget and decision.selectionTarget.index or nil,
    }
end

function M.Evaluate(input)
    local board, err = M.NormalizeBoard(input)
    if not board then return nil, err end
    local D = DecisionModule()
    local decision = D.Decide(board)
    return M.VerdictFromDecision(board, decision), board, decision
end

function M.CanReroll(input)
    local board, err = M.NormalizeBoard(input)
    if not board then return false, err end
    return DecisionModule().CanReroll(board)
end

------------------------------------------------------------------------
-- Transcript parsing (Logbook / DebugLog / fixture directives)
------------------------------------------------------------------------

local function ParseBoardDirective(line)
    local params = {}
    for key, value in line:gmatch("([%w_]+)=([^%s;]+)") do
        params[key] = value
    end
    return params
end

local function ParseSlotSpec(spec)
    local index, spellId, score, flags = spec:match("^(%d+):(%d+):([%-%d%.]+)(.*)$")
    if not index then return nil end
    local slot = {
        index = tonumber(index),
        spellId = tonumber(spellId),
        score = tonumber(score),
        name = "Echo " .. spellId,
        isValid = true,
    }
    for flag in (flags or ""):gmatch(":(%w+)") do
        if flag == "frozen" or flag == "F" then slot.isFrozen = true end
        if flag == "carried" or flag == "C" then slot.isCarried = true end
        if flag == "guaranteed" or flag == "G" then slot.isGuaranteed = true end
        if flag == "avoided" or flag == "A" then
            slot.isAvoided = true
            slot.policyBlocked = true
        end
        if flag == "protected" or flag == "P" then slot.isProtected = true end
        if flag == "banish" or flag == "B" then
            slot.policyEffect = "banish"
            slot.banishEligible = true
        end
        if flag == "thisboard" or flag == "T" then slot.frozenThisBoard = true end
    end
    return slot
end

function M.ParseDebugLogBoard(line)
    line = Trim(line):gsub("^Board:%s*", "")
    local slots = {}
    for segment in line:gmatch("[^,]+") do
        segment = Trim(segment)
        local index, spellId, score = segment:match("%[(%d+)%].-%((%d+)%)=([%d%.]+)")
        local frozen = segment:find(" FROZEN", 1, true) ~= nil
        if index then
            slots[#slots + 1] = {
                index = tonumber(index),
                name = segment:match("%]%s+(.-)%(") or ("Echo " .. spellId),
                spellId = tonumber(spellId),
                score = tonumber(score),
                isValid = true,
                isFrozen = frozen and true or false,
                isCarried = frozen and true or false,
            }
        end
    end
    if #slots == 0 then return nil end
    return slots
end

function M.ParseDebugLogAction(line)
    local action, reason = line:match("^Action:%s+(%S+)%s+%-%-%s+(.+)$")
    if not action then return nil end
    return { rawAction = action, reason = reason }
end

function M.ParseDebugLogLifecycle(line)
    local state, reasonCode = line:match("^Board lifecycle:%s+(%S+)%s+%(([^,]+)")
    if not state then return nil end
    return { boardState = state, reasonCode = Trim(reasonCode) }
end

function M.ParseLine(line)
    line = Trim(line)
    if line == "" or line:match("^#") then return { kind = "comment", text = line } end

    if line:match("^@board") then
        return { kind = "board", params = ParseBoardDirective(line) }
    end
    if line:match("^@expect") then
        return { kind = "expect", params = ParseBoardDirective(line) }
    end
    if line:match("^@event") then
        return { kind = "event", params = ParseBoardDirective(line) }
    end
    if line:match("^@assert") then
        return { kind = "assert", params = ParseBoardDirective(line) }
    end
    if line:match("^slot=") then
        return { kind = "slot", slot = ParseSlotSpec(line:match("slot=(.+)$") or line) }
    end
    if line:match("^%d+:%d+:") then
        return { kind = "slot", slot = ParseSlotSpec(line) }
    end
    if line:match("^Board:%s") then
        return { kind = "debug_board", slots = M.ParseDebugLogBoard(line) }
    end
    if line:match("^Action:%s") then
        return { kind = "debug_action", record = M.ParseDebugLogAction(line) }
    end
    if line:match("^Board lifecycle:%s") then
        return { kind = "debug_lifecycle", record = M.ParseDebugLogLifecycle(line) }
    end
    if line:match("^Frozen:%s") then
        local frozen, maxFrozen = line:match("^Frozen:%s+(%d+)/(%d+)")
        return { kind = "debug_frozen", frozen = tonumber(frozen), maxFrozen = tonumber(maxFrozen) }
    end
    return { kind = "text", text = line }
end

function M.ParseTranscript(text)
    local steps = {}
    local current = nil
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        local parsed = M.ParseLine(line)
        if parsed.kind == "board" or parsed.kind == "debug_board" then
            current = {
                board = parsed.params or {},
                slots = parsed.slots or {},
                expects = {},
                events = {},
                asserts = {},
                debug = {},
            }
            steps[#steps + 1] = current
        elseif parsed.kind == "slot" and current and parsed.slot then
            current.slots[#current.slots + 1] = parsed.slot
        elseif parsed.kind == "expect" and current then
            current.expects[#current.expects + 1] = parsed.params
        elseif parsed.kind == "event" and current then
            current.events[#current.events + 1] = parsed.params
        elseif parsed.kind == "assert" then
            if current then
                current.asserts[#current.asserts + 1] = parsed.params
            else
                steps[#steps + 1] = { asserts = { parsed.params } }
            end
        elseif parsed.kind == "debug_action" and current then
            current.debug.action = parsed.record
        elseif parsed.kind == "debug_lifecycle" and current then
            current.debug.lifecycle = parsed.record
        elseif parsed.kind == "debug_frozen" and current then
            current.debug.frozen = parsed
        end
    end
    return steps
end

local function ParamsToBoardInput(step)
    local params = step.board or {}
    local input = {
        offerId = params.offer or params.offerId,
        freezeThreshold = tonumber(params.threshold or params.freezeThreshold),
        freezeResources = tonumber(params.freezeResources),
        canReroll = params.canReroll == "1" or params.canReroll == "true",
        canBanish = params.canBanish == "1" or params.canBanish == "true",
        pickIsAcceptable = not (params.pickIsAcceptable == "0" or params.pickIsAcceptable == "false"),
        pendingFreezeSlot = tonumber(params.pendingFreezeSlot),
        pendingFreezeEchoID = tonumber(params.pendingFreezeEchoID),
        frozenStateUncertain = params.frozenStateUncertain == "1" or params.frozenStateUncertain == "true",
        serverBoardState = params.boardState,
        slots = step.slots,
    }
    if params.maxFrozen then input.maxFrozen = tonumber(params.maxFrozen) end
    return input
end

function M.ApplySimulatedEvent(board, event)
    event = event or {}
    local kind = event.type or event.event or event.kind
    if kind == "freeze_pending" or kind == "pending_freeze" then
        board.pendingFreezeSlot = tonumber(event.slot or event.targetSlot)
        board.pendingFreezeEchoID = tonumber(event.spell or event.spellId or event.targetSpellId)
    elseif kind == "freeze_confirmed" or kind == "confirm_freeze" then
        local index = tonumber(event.slot or event.targetSlot)
        local spellId = tonumber(event.spell or event.spellId or event.targetSpellId)
        board.pendingFreezeSlot = nil
        board.pendingFreezeEchoID = nil
        board.frozenStateUncertain = false
        for _, slot in ipairs(board.slots or {}) do
            if tonumber(slot.index) == index or EchoKey(slot) == spellId then
                slot.isFrozen = true
                slot.isCarried = event.carried ~= "0"
                board.frozenThisBoardBySlot[slot.index] = true
                local key = EchoKey(slot)
                if key ~= nil then
                    board.frozenThisBoardEchoIDs[key] = true
                    board.runFrozenEchoIDs[key] = true
                end
            end
        end
        board.freezeResources = math.max(0, (tonumber(board.freezeResources) or 0) - 1)
    elseif kind == "freeze_uncertain" then
        board.frozenStateUncertain = true
    elseif kind == "select" then
        board.pendingAction = nil
        board.serverBoardState = StateMachine() and StateMachine().STATE.SPENT or "SPENT"
    elseif kind == "reroll" then
        board.frozenThisBoardBySlot = {}
        board.frozenThisBoardEchoIDs = {}
        for _, slot in ipairs(board.slots or {}) do
            slot.isFrozen = nil
            slot.isCarried = nil
            slot.frozenThisBoard = nil
        end
    elseif kind == "new_board" then
        board.pendingFreezeSlot = nil
        board.pendingFreezeEchoID = nil
        board.pendingAction = nil
        board.frozenStateUncertain = false
        board.frozenThisBoardBySlot = {}
        board.frozenThisBoardEchoIDs = {}
    end
    DecisionModule().RefreshFrozenState(board)
    local BSM = StateMachine()
    if BSM then BSM.Attach(board, board) end
    return board
end

local function MatchExpect(verdict, expect)
    if expect.action and M.NormalizePolicyAction(expect.action) ~= verdict.action then
        return false, string.format("action expected %s got %s", expect.action, verdict.action)
    end
    if expect.boardState and tostring(expect.boardState) ~= tostring(verdict.boardState) then
        return false, string.format("boardState expected %s got %s", expect.boardState, tostring(verdict.boardState))
    end
    if expect.target and expect.target ~= "-" and tonumber(expect.target) ~= verdict.targetSlot then
        return false, string.format("target expected %s got %s", expect.target, tostring(verdict.targetSlot))
    end
    if expect.reasonCode and expect.reasonCode ~= verdict.reasonCode then
        return false, string.format("reasonCode expected %s got %s", expect.reasonCode, verdict.reasonCode)
    end
    return true
end

local function CheckAssert(name, board, verdict, params)
    if name == "no_reroll_in" or params.no_reroll_in then
        local blocked = params.no_reroll_in or params[1]
        for state in tostring(blocked):gmatch("([^,%s]+)") do
            if board.lifecycleState == Trim(state) and verdict.action == "reroll" then
                return false, "reroll emitted while lifecycle was " .. state
            end
        end
        local allowed = DecisionModule().CanReroll(board)
        if board.lifecycleState == StateMachine().STATE.FROZEN_PENDING
            or board.lifecycleState == StateMachine().STATE.CONFIRMED then
            if allowed then
                return false, "CanReroll true during blocked lifecycle " .. tostring(board.lifecycleState)
            end
        end
    end
    return true
end

function M.Replay(transcript, options)
    options = options or {}
    local steps = type(transcript) == "table" and transcript or M.ParseTranscript(transcript)
    local results = { steps = {}, errors = {} }

    for stepIndex, step in ipairs(steps) do
        local record = { index = stepIndex, verdicts = {}, events = {} }
        if step.slots and #step.slots > 0 then
            local input = ParamsToBoardInput(step)
            local board, err = M.NormalizeBoard(input)
            if not board then
                results.errors[#results.errors + 1] = "step " .. stepIndex .. ": " .. tostring(err)
            else
                for _, eventParams in ipairs(step.events or {}) do
                    M.ApplySimulatedEvent(board, eventParams)
                    record.events[#record.events + 1] = eventParams
                end
                local verdict = M.VerdictFromDecision(board, DecisionModule().Decide(board))
                record.verdict = verdict
                record.verdicts[#record.verdicts + 1] = verdict

                for _, expect in ipairs(step.expects or {}) do
                    local ok, message = MatchExpect(verdict, expect)
                    if not ok then
                        results.errors[#results.errors + 1] = "step " .. stepIndex .. ": " .. message
                    end
                end
                for _, assertParams in ipairs(step.asserts or {}) do
                    for key, value in pairs(assertParams) do
                        local ok, message = CheckAssert(key, board, verdict, assertParams)
                        if not ok then
                            results.errors[#results.errors + 1] = "step " .. stepIndex .. ": " .. message
                        end
                    end
                end
            end
        elseif step.asserts then
            for _, assertParams in ipairs(step.asserts) do
                for key in pairs(assertParams) do
                    local ok, message = CheckAssert(key, nil, {}, assertParams)
                    if not ok then results.errors[#results.errors + 1] = message end
                end
            end
        end
        results.steps[#results.steps + 1] = record
    end

    return results
end

function M.ReplayFile(path)
    local file, err = io.open(path, "rb")
    if not file then return nil, err end
    local text = file:read("*a")
    file:close()
    return M.Replay(text)
end
