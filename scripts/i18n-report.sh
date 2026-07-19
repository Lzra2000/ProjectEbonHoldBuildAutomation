#!/usr/bin/env sh
# Translation coverage report: for every locale file, which keys used in
# the codebase are missing, and which registered keys are orphaned (no
# longer looked up anywhere). The test suite only fails on missing keys;
# this gives translators the full picture, and catches the dead entries
# the tests deliberately tolerate -- exactly the kind of leftovers the
# slash-command removal produced.
#
#   sh scripts/i18n-report.sh
#
# Exit code 0 always -- this is a report, not a gate. Requires texlua.
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

-- Keys actually looked up anywhere in the addon (excluding locale files).
local used = {}
local usedCount = 0
local p = io.popen("find core modules -name '*.lua' -not -path 'modules/i18n/locales/*'")
for path in p:lines() do
    local src = ReadFile(path)
    local function record(key)
        local k = key:gsub('\\"', '"')
        if not used[k] then
            used[k] = true
            usedCount = usedCount + 1
        end
    end
    for key in src:gmatch('EbonBuilds%.L%["(.-[^\\])"%]') do record(key) end
    -- Alias lookups: files commonly do `local L = EbonBuilds.L` and then
    -- `L["..."]`. Matching only the full literal misses every one of
    -- those -- which is exactly how the tab labels in BuildTabs.lua got
    -- falsely reported as orphaned once.
    for alias in src:gmatch("local%s+([%a_][%w_]*)%s*=%s*EbonBuilds%.L%f[%W]") do
        for key in src:gmatch(alias:gsub("%W", "%%%1") .. '%["(.-[^\\])"%]') do record(key) end
    end
end
p:close()

print(string.format("%d distinct keys are looked up in the codebase.", usedCount))
print("")

-- Registered keys per locale file, read by loading the file with a stub
-- Register that captures the table -- string-accurate for any escaping,
-- unlike grepping the source.
local locales = {}
local lp = io.popen("ls modules/i18n/locales/*.lua 2>/dev/null")
for path in lp:lines() do locales[#locales + 1] = path end
lp:close()
table.sort(locales)

EbonBuilds = { Locale = {} }
for _, path in ipairs(locales) do
    local captured
    EbonBuilds.Locale.Register = function(_, tbl) captured = tbl end
    dofile(path)
    local code = path:match("([^/]+)%.lua$")

    local have, haveCount = {}, 0
    for k in pairs(captured or {}) do
        have[k] = true
        haveCount = haveCount + 1
    end

    local missing, orphaned = {}, {}
    for k in pairs(used) do
        if not have[k] then missing[#missing + 1] = k end
    end
    for k in pairs(have) do
        if not used[k] then orphaned[#orphaned + 1] = k end
    end
    table.sort(missing)
    table.sort(orphaned)

    local covered = usedCount - #missing
    print(string.format("%s: %d/%d keys translated (%d%%), %d orphaned",
        code, covered, usedCount,
        usedCount > 0 and math.floor(covered / usedCount * 100 + 0.5) or 100,
        #orphaned))
    for _, k in ipairs(missing) do print("  missing:  " .. k) end
    for _, k in ipairs(orphaned) do print("  orphaned: " .. k) end
end
LUAEOF
texlua "$HELPER"
