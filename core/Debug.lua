-- EbonBuilds: core/Debug.lua
-- Responsibility: ergonomic error-isolation helpers built on
-- core/ErrorLog.lua, plus a lightweight self-test registry so modules can
-- add a sanity check without hand-editing tests/test_load.lua or
-- tests/test_features.lua.
--
-- Problems this exists to make cheaper than they were before:
--
-- 1. Wrapping every SetScript handler in ErrorLog.Protect by hand does not
--    scale. ProtectScript() lets a widget factory (Theme.CreateButton, etc.)
--    opt a frame in ONCE; every handler any caller attaches afterwards via
--    SetScript is wrapped automatically, with no per-call-site change
--    required anywhere else.
--
-- 2. New modules only get load/behavior coverage if someone remembers to
--    extend the big hand-written test files. RegisterTest() lets a module
--    register its own small self-check next to the code it's testing;
--    tests/test_selftests.lua runs every registered test in one pass, and
--    the same registry can be run live in-game (Error Log window ->
--    Self-Tests button) since none of it depends on a real WoW client.
--
-- Planned next (not yet built): Time() for spotting a slow handler without
-- a profiler attached, event-spam detection inside ProtectScript, a small
-- diagnostic HUD, and Assert() for "this should never happen here" spots.

EbonBuilds.Debug = {}

local D = EbonBuilds.Debug
local registeredTests = {}
local protectedFrameCount = 0
local lastSelfTestSummary = nil

-- GetStats(): a few numbers for a diagnostic HUD or a bug report -- how
-- many frames currently have ProtectScript coverage, and the result of
-- the last RunSelfTests() call (nil if it's never been run this session).
function D.GetStats()
    return {
        protectedFrameCount = protectedFrameCount,
        lastSelfTestSummary = lastSelfTestSummary,
    }
end

-- Protect(source, fn): thin re-export of ErrorLog.Protect. Exists so call
-- sites can say EbonBuilds.Debug.Protect(...) consistently, without every
-- module needing to know Protect actually lives on ErrorLog.
function D.Protect(source, fn)
    return EbonBuilds.ErrorLog.Protect(source, fn)
end

-- ProtectScript(frame, source): from this call on, every handler this frame
-- registers via SetScript is automatically wrapped in ErrorLog.Protect --
-- callers of the frame (anywhere else in the addon) don't have to remember
-- to wrap each OnClick/OnEnter/OnShow/etc by hand, and can't forget to.
-- Idempotent: calling it more than once on the same frame is a no-op after
-- the first call, so it's safe to call from a shared widget factory even if
-- a caller also calls it themselves.
function D.ProtectScript(frame, source)
    if not frame or frame._ebonProtectedScript then return frame end
    frame._ebonProtectedScript = true
    protectedFrameCount = protectedFrameCount + 1
    local originalSetScript = frame.SetScript
    frame.SetScript = function(self, scriptType, handler, ...)
        if type(handler) == "function" then
            handler = EbonBuilds.ErrorLog.Protect(
                (source or "?") .. "." .. tostring(scriptType), handler)
        end
        return originalSetScript(self, scriptType, handler, ...)
    end
    return frame
end

-- RegisterTest(name, fn): fn should error() (or return false) on failure and
-- return normally on success. Registration order is preserved so results
-- read top-to-bottom in the order modules were loaded.
function D.RegisterTest(name, fn)
    table.insert(registeredTests, { name = name, fn = fn })
end

-- RunSelfTests(): executes every registered test and returns a summary.
-- Used by tests/test_selftests.lua; the same registry can back an in-game
-- diagnostic command later without any test needing to be written twice.
function D.RunSelfTests()
    local passed, failed, results = 0, 0, {}
    for _, entry in ipairs(registeredTests) do
        local ok, err = pcall(entry.fn)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
        end
        table.insert(results, { name = entry.name, ok = ok, err = err })
    end
    lastSelfTestSummary = { passed = passed, failed = failed, total = #registeredTests }
    return { passed = passed, failed = failed, total = #registeredTests, results = results }
end

-- ClearTests(): test-only. Lets a test file reset the registry between
-- independent runs in the same process instead of accumulating across them.
function D.ClearTests()
    registeredTests = {}
end
