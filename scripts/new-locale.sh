#!/usr/bin/env sh
# Scaffolds a new locale file: scans the whole addon for every
# EbonBuilds.L["..."] call site, and generates
# modules/i18n/locales/<code>.lua with each key mapped to itself as a
# placeholder, ready for a translator to fill in.
#
#   sh scripts/new-locale.sh itIT
#
# Requires texlua (see scripts/dev-setup.sh) -- plain shell/grep can't
# reliably handle keys containing escaped quotes (e.g. the ones with
# embedded %s and \" in MainWindow.lua's /ebb locale messages).
set -eu
cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ]; then
    echo "Usage: sh scripts/new-locale.sh <localeCode>   (e.g. itIT, koKR, zhCN)" >&2
    exit 1
fi
CODE="$1"
OUT="modules/i18n/locales/$CODE.lua"

if [ -f "$OUT" ]; then
    echo "$OUT already exists -- not overwriting." >&2
    exit 1
fi

if ! command -v texlua >/dev/null 2>&1; then
    echo "texlua not found -- run: sh scripts/dev-setup.sh" >&2
    exit 1
fi

HELPER="$(mktemp)"
trap 'rm -f "$HELPER"' EXIT
cat > "$HELPER" <<'LUAEOF'
local code, outPath = arg[1], arg[2]

local function ReadFile(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local content = f:read("*a")
    f:close()
    return content
end

-- Every *.lua file under core/ and modules/, except the locale files
-- themselves (which register translations, not look them up).
local files = {}
local p = io.popen("find core modules -name '*.lua' -not -path 'modules/i18n/locales/*'")
for line in p:lines() do files[#files + 1] = line end
p:close()

-- Keys in source order (not just a set), and de-duplicated, so the
-- generated file groups keys near where they're used instead of shuffling
-- them alphabetically -- easier for a translator to see surrounding
-- context by opening the same file.
local seen = {}
local ordered = {}
for _, path in ipairs(files) do
    local src = ReadFile(path)
    local fileKeys = {}
    for key in src:gmatch('EbonBuilds%.L%["(.-[^\\])"%]') do
        local unescaped = key:gsub('\\"', '"')
        if not seen[unescaped] then
            seen[unescaped] = true
            fileKeys[#fileKeys + 1] = unescaped
        end
    end
    if #fileKeys > 0 then
        ordered[#ordered + 1] = { file = path, keys = fileKeys }
    end
end

local out = io.open(outPath, "w")
out:write(string.format([[
-- EbonBuilds: modules/i18n/locales/%s.lua
-- %s translation.
--
-- Every value below is a placeholder (same as the English key) --
-- replace the right-hand side with the actual translation. Leave a line
-- as-is (untranslated) if you're not sure; EbonBuilds.L falls back to
-- English automatically, it never breaks on a missing entry.
--
-- Game-specific terms (Echo, Build, Banish/Reroll/Freeze/Select,
-- Autopilot) are conventionally kept in English across every language
-- this addon and its README are translated into -- see the other files
-- in this folder, or README.*.md in the repo root, for how those already
-- read in context.

EbonBuilds.Locale.Register("%s", {
]], code, code, code))

for _, group in ipairs(ordered) do
    out:write(string.format("    -- %s\n", group.file))
    for _, key in ipairs(group.keys) do
        local escaped = key:gsub('\\', '\\\\'):gsub('"', '\\"')
        out:write(string.format('    ["%s"] = "%s",\n', escaped, escaped))
    end
    out:write("\n")
end

out:write("})\n")
out:close()

print("Wrote " .. outPath .. " with keys from " .. #ordered .. " file(s).")
print("Next: translate the values, then add \"modules/i18n/locales/" .. code .. ".lua\" to EbonBuilds.toc")
print("(right after the other locale files), and add it to SUPPORTED_LOCALES in modules/i18n/Locale.lua.")
LUAEOF

texlua "$HELPER" "$CODE" "$OUT"
