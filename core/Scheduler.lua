-- EbonBuilds: core/Scheduler.lua
-- One shared OnUpdate dispatcher for delayed, periodic, and maintenance work.
-- Tasks are keyed, so rescheduling replaces work instead of allocating copies.

EbonBuilds.Scheduler = {}

local Scheduler = EbonBuilds.Scheduler
local PRIORITY_CRITICAL    = 1
local PRIORITY_INTERACTIVE = 2
local PRIORITY_BACKGROUND  = 3
local PRIORITY_MAINTENANCE = 4
local queues = { {}, {}, {}, {} }
local dueScratch = { {}, {}, {}, {} }
local taskCount = 0
local frame = CreateFrame("Frame")
frame:Hide()

Scheduler.CRITICAL    = PRIORITY_CRITICAL
Scheduler.INTERACTIVE = PRIORITY_INTERACTIVE
Scheduler.BACKGROUND  = PRIORITY_BACKGROUND
Scheduler.MAINTENANCE = PRIORITY_MAINTENANCE

local function Now()
    return GetTime and GetTime() or 0
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function FindTask(id)
    for priority = PRIORITY_CRITICAL, PRIORITY_MAINTENANCE do
        local task = queues[priority][id]
        if task then return task, priority end
    end
    return nil
end

function Scheduler.Cancel(id)
    local _, priority = FindTask(id)
    if not priority then return false end
    queues[priority][id] = nil
    taskCount = math.max(0, taskCount - 1)
    if taskCount == 0 then frame:Hide() end
    return true
end

function Scheduler.Schedule(id, delay, callback, priority, interval, allowCombat)
    if type(id) ~= "string" or type(callback) ~= "function" then return false end
    Scheduler.Cancel(id)
    priority = math.max(PRIORITY_CRITICAL, math.min(PRIORITY_MAINTENANCE, tonumber(priority) or PRIORITY_BACKGROUND))
    queues[priority][id] = {
        id = id,
        due = Now() + math.max(0, tonumber(delay) or 0),
        callback = callback,
        interval = tonumber(interval),
        allowCombat = allowCombat == true,
        lastRun = Now(),
    }
    taskCount = taskCount + 1
    frame:Show()
    return true
end

function Scheduler.After(id, delay, callback, priority, allowCombat)
    return Scheduler.Schedule(id, delay, callback, priority, nil, allowCombat)
end

function Scheduler.Every(id, interval, callback, priority, allowCombat)
    interval = math.max(0.05, tonumber(interval) or 1)
    return Scheduler.Schedule(id, interval, callback, priority, interval, allowCombat)
end

function Scheduler.Has(id)
    return FindTask(id) ~= nil
end

function Scheduler.Count()
    return taskCount
end

local function RecordError(id, err)
    if EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Record then
        EbonBuilds.ErrorLog.Record("Scheduler." .. tostring(id), err)
    end
end

local function RunPriority(priority, now, combat)
    local queue = queues[priority]
    local due = dueScratch[priority]
    for index = #due, 1, -1 do due[index] = nil end

    -- Never call a task or mutate the keyed queue while next()/pairs() is
    -- traversing it. Lua 5.1 can raise "invalid key to 'next'" if a callback
    -- cancels or schedules work and the table rehashes under that traversal.
    for _, task in pairs(queue) do
        if task.due <= now and (task.allowCombat or not combat) then
            due[#due + 1] = task
        end
    end

    local started = debugprofilestop and debugprofilestop() or nil
    for index = 1, #due do
        local task = due[index]
        local id = task.id
        -- A previous callback may have cancelled or replaced this task. Only
        -- execute the exact object captured by the read-only discovery pass.
        if queue[id] == task and task.due <= now and (task.allowCombat or not combat) then
            queue[id] = nil
            taskCount = math.max(0, taskCount - 1)
            local elapsed = math.max(0, now - (task.lastRun or now))
            local ok, nextDelay = pcall(task.callback, elapsed)
            if not ok then RecordError(id, nextDelay) end

            -- A callback may have explicitly rescheduled its own id. Only
            -- restore the repeating task when no replacement exists.
            if ok and task.interval and not Scheduler.Has(id) and nextDelay ~= false then
                task.lastRun = now
                task.due = now + math.max(0.05, tonumber(nextDelay) or task.interval)
                queue[id] = task
                taskCount = taskCount + 1
            end
        end

        -- Background work gets a small slice. Critical and interactive work
        -- is tiny and is always allowed to finish its current due set.
        if priority >= PRIORITY_BACKGROUND and started and debugprofilestop then
            if debugprofilestop() - started >= 1.5 then break end
        end
    end
    for index = #due, 1, -1 do due[index] = nil end
end

frame:SetScript("OnUpdate", function()
    if taskCount == 0 then frame:Hide(); return end
    local now = Now()
    local combat = InCombat()
    RunPriority(PRIORITY_CRITICAL, now, combat)
    RunPriority(PRIORITY_INTERACTIVE, now, combat)
    RunPriority(PRIORITY_BACKGROUND, now, combat)
    RunPriority(PRIORITY_MAINTENANCE, now, combat)
    if taskCount == 0 then frame:Hide() end
end)
