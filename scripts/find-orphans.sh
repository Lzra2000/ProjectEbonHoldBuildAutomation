#!/usr/bin/env sh
# Finds two kinds of dead weight: Lua files under core/ and modules/ that
# EbonBuilds.toc never loads (they silently don't exist in-game), and
# exported EbonBuilds.<Module>.<Fn> functions with no caller anywhere.
# Orphaned modules have been a real problem in this codebase before.
#
#   sh scripts/find-orphans.sh
#
# Exit 1 if any unloaded file is found (that's always a bug -- either
# wire it into the .toc or delete it). Uncalled exports are only listed,
# not failed on: some are test hooks (_-prefixed, always exempt) and
# some are legitimately called via dynamic dispatch the grep can't see,
# so they need a human eye, not a hard gate.
set -eu
cd "$(dirname "$0")/.."

if ! command -v texlua >/dev/null 2>&1; then
    echo "texlua not found -- run: sh scripts/dev-setup.sh" >&2
    exit 1
fi

HELPER="$(mktemp)"
trap 'rm -f "$HELPER"' EXIT
cat > "$HELPER" <<'LUAEOF'
local function ReadFile(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local c = f:read("*a")
    f:close()
    return c
end

-- 1) Files on disk vs files in the TOC.
local inToc = {}
for line in io.lines("EbonBuilds.toc") do
    line = line:gsub("\r", "")
    if line:match("^%S+%.lua$") then inToc[line] = true end
end

local unloaded = {}
local p = io.popen("find core modules -name '*.lua' | sort")
local allFiles = {}
for path in p:lines() do
    allFiles[#allFiles + 1] = path
    if not inToc[path] then unloaded[#unloaded + 1] = path end
end
p:close()

if #unloaded > 0 then
    for _, path in ipairs(unloaded) do
        io.stderr:write("ORPHAN FILE: " .. path .. " exists but is not in EbonBuilds.toc -- it never loads in-game\n")
    end
else
    print(string.format("All %d Lua files under core/ and modules/ are loaded by the TOC.", #allFiles))
end

-- 2) Exported functions nobody calls. Definition sites are
-- "function EbonBuilds.Mod.Fn(" and "EbonBuilds.Mod.Fn = function";
-- a use is any OTHER occurrence of "Mod.Fn" anywhere (including via a
-- "local M = EbonBuilds.Mod" alias, which still reads M.Fn -- matching
-- on "Mod.Fn" alone would miss those, so we match ".Fn" scoped to the
-- module's known aliases is overkill; "%.Fn%f[%W]" plus the full name
-- covers the real patterns in this codebase).
local defs = {}   -- "Mod.Fn" -> defining path
local sources = {}
for _, path in ipairs(allFiles) do
    local src = ReadFile(path)
    sources[path] = src
    for mod, fn in src:gmatch("function EbonBuilds%.([%a_][%w_]*)%.([%a_][%w_]*)%s*%(") do
        defs[mod .. "." .. fn] = path
    end
    for mod, fn in src:gmatch("EbonBuilds%.([%a_][%w_]*)%.([%a_][%w_]*)%s*=%s*function") do
        defs[mod .. "." .. fn] = path
    end
end
-- tests count as callers -- a test-only hook is not an orphan
local tp = io.popen("find tests -name '*.lua' 2>/dev/null")
for path in tp:lines() do sources[path] = ReadFile(path) end
tp:close()

local uncalled = {}
for name, defPath in pairs(defs) do
    local mod, fn = name:match("^(.-)%.(.+)$")
    if fn:sub(1, 1) ~= "_" then  -- _-prefixed = test/integration hooks, exempt by convention
        local callers = 0
        local needle = "%." .. fn:gsub("%W", "%%%1") .. "%f[%W]"
        for path, src in pairs(sources) do
            for pos in src:gmatch("()" .. needle) do
                -- Not the definition line itself: cheap check -- definitions
                -- are immediately preceded by "function EbonBuilds.Mod" or
                -- followed by "= function"; anything else counts as a use.
                local before = src:sub(math.max(1, pos - 60), pos - 1)
                local after = src:sub(pos, pos + #fn + 30)
                local isDef = before:match("function EbonBuilds%.[%a_][%w_]*$")
                    or after:match("^%." .. fn:gsub("%W", "%%%1") .. "%s*=%s*function")
                if not isDef then callers = callers + 1 end
            end
        end
        if callers == 0 then
            uncalled[#uncalled + 1] = string.format("%s  (defined in %s)", name, defPath)
        end
    end
end
table.sort(uncalled)

print("")
if #uncalled == 0 then
    print("Every exported EbonBuilds.* function has at least one caller.")
else
    print(#uncalled .. " exported function(s) with no visible caller (review, don't assume dead -- dynamic dispatch is invisible to this):")
    for _, line in ipairs(uncalled) do print("  " .. line) end
end

os.exit(#unloaded > 0 and 1 or 0)
LUAEOF
texlua "$HELPER"
