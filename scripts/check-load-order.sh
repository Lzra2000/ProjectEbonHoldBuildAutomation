#!/usr/bin/env sh
# Load-order check: a file-scope reference to EbonBuilds.<Module> must
# only name modules defined by files loaded EARLIER in EbonBuilds.toc.
# Function bodies are exempt -- they run after everything is loaded.
# This is exactly the trap the ErrorLog.Protect wrap fell into once:
# BuildTabs.lua loads before core/ErrorLog.lua, so a file-scope
# EbonBuilds.ErrorLog.Protect(...) call would have crashed on load.
#
#   sh scripts/check-load-order.sh
#
# Heuristic, not a parser: a line is treated as file-scope when it has no
# leading whitespace (module code here is consistently indented inside
# functions/blocks). Requires texlua. Exit 1 on any violation.
set -eu
cd "$(dirname "$0")/.."

if ! command -v texlua >/dev/null 2>&1; then
    echo "texlua not found -- run: sh scripts/dev-setup.sh" >&2
    exit 1
fi

HELPER="$(mktemp)"
trap 'rm -f "$HELPER"' EXIT
cat > "$HELPER" <<'LUAEOF'
-- TOC files, in load order.
local files = {}
for line in io.lines("EbonBuilds.toc") do
    line = line:gsub("\r", "")
    if line:match("^%S+%.lua$") then files[#files + 1] = line end
end

-- Strip comments and blank out string literal contents so keywords or
-- "EbonBuilds.X" text inside them can't confuse either the reference
-- matching or the block-depth tracking. Long strings/comments are
-- handled across lines via a small state machine; quote contents are
-- replaced with spaces (delimiters kept) so column positions survive.
local function StripSource(src)
    src = src:gsub("%-%-%[(=*)%[.-%]%1%]", function(eq) return "" end)
    src = src:gsub("%[(=*)%[.-%]%1%]", function(eq) return "[" .. eq .. "[]" .. eq .. "]" end)
    local out = {}
    for line in (src .. "\n"):gmatch("(.-)\n") do
        local cleaned = {}
        local i, n = 1, #line
        local quote = nil
        while i <= n do
            local ch = line:sub(i, i)
            if quote then
                if ch == "\\" then
                    cleaned[#cleaned + 1] = "  "
                    i = i + 2
                elseif ch == quote then
                    cleaned[#cleaned + 1] = ch
                    quote = nil
                    i = i + 1
                else
                    cleaned[#cleaned + 1] = " "
                    i = i + 1
                end
            elseif ch == '"' or ch == "'" then
                quote = ch
                cleaned[#cleaned + 1] = ch
                i = i + 1
            elseif ch == "-" and line:sub(i + 1, i + 1) == "-" then
                break  -- line comment: drop the rest
            else
                cleaned[#cleaned + 1] = ch
                i = i + 1
            end
        end
        out[#out + 1] = table.concat(cleaned)
    end
    return out
end

local defined = { L = true }
local fail = 0

for _, path in ipairs(files) do
    local f = io.open(path, "r")
    local src = f:read("*a")
    f:close()
    local lines = StripSource(src)

    local blockDepth = 0
    local thisFileDefines = {}
    for lineNo, line in ipairs(lines) do
        local isFileScope = blockDepth == 0 and line:match("^%S") ~= nil

        if isFileScope then
            -- Definition forms: "EbonBuilds.X =" and "function EbonBuilds.X..."
            local defines = line:match("^EbonBuilds%.([%a_][%w_]*)%s*=")
                or line:match("^function%s+EbonBuilds%.([%a_][%w_]*)")
            for mod in line:gmatch("EbonBuilds%.([%a_][%w_]*)") do
                if mod ~= defines and mod ~= "L" and not defined[mod] and not thisFileDefines[mod] then
                    io.stderr:write(string.format(
                        "LOAD ORDER FAIL: %s:%d references EbonBuilds.%s at file scope, but no earlier TOC file defines it\n",
                        path, lineNo, mod))
                    fail = 1
                end
            end
            if defines then thisFileDefines[defines] = true end
        end

        local opens = 0
        for _ in line:gmatch("%f[%w]function%f[%W]") do opens = opens + 1 end
        for _ in line:gmatch("%f[%w]do%f[%W]") do opens = opens + 1 end
        for _ in line:gmatch("%f[%w]then%f[%W]") do opens = opens + 1 end
        for _ in line:gmatch("%f[%w]repeat%f[%W]") do opens = opens + 1 end
        local closes = 0
        for _ in line:gmatch("%f[%w]end%f[%W]") do closes = closes + 1 end
        for _ in line:gmatch("%f[%w]until%f[%W]") do closes = closes + 1 end
        for _ in line:gmatch("%f[%w]elseif%f[%W]") do closes = closes + 1 end
        blockDepth = blockDepth + opens - closes
        if blockDepth < 0 then blockDepth = 0 end
    end
    for mod in pairs(thisFileDefines) do defined[mod] = true end
end

if fail == 0 then
    print(string.format("Load order OK across %d TOC files.", #files))
else
    os.exit(1)
end
LUAEOF
texlua "$HELPER"
