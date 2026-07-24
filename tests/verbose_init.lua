-- Optional VERBOSE bootstrap for the off-client test runner.
-- Loaded only when tests/run.sh sets LUA_INIT=@tests/verbose_init.lua
-- (VERBOSE=1 / --verbose). Does not affect the WoW client addon.
if rawget(_G, "_EBB_VERBOSE_INIT") then return end
_G._EBB_VERBOSE_INIT = true

local loaded = {}
local orig_loadfile = loadfile
function loadfile(path, ...)
    local p = tostring(path)
    loaded[#loaded + 1] = p
    io.stderr:write("VERBOSE: loadfile " .. p .. "\n")
    return orig_loadfile(path, ...)
end

-- Print a short summary at process exit (best-effort).
local orig_exit = os.exit
function os.exit(code, ...)
    io.stderr:write(string.format(
        "VERBOSE: %d module file(s) loaded via loadfile in this process\n", #loaded))
    if #loaded > 0 and #loaded <= 40 then
        for i = 1, #loaded do
            io.stderr:write(string.format("VERBOSE:   [%d] %s\n", i, loaded[i]))
        end
    elseif #loaded > 40 then
        for i = 1, 20 do
            io.stderr:write(string.format("VERBOSE:   [%d] %s\n", i, loaded[i]))
        end
        io.stderr:write(string.format("VERBOSE:   ... %d more\n", #loaded - 20))
    end
    return orig_exit(code, ...)
end

io.stderr:write("VERBOSE: tests/verbose_init.lua active (loadfile tracing)\n")
