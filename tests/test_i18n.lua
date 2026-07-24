-- Locale integrity coverage. EbonBuilds.L is keyed by the English string
-- itself; every locale file must contain an entry for every key looked up
-- via EbonBuilds.L["..."] / L["..."] anywhere outside modules/i18n/locales/.
-- Missing entries fall back to English at runtime, but the test suite fails
-- so a forgotten translation cannot silently ship.
--
-- Plus functional checks of the Locale registry itself.

local failures = 0

local function check(cond, msg)
    if not cond then
        failures = failures + 1
        io.stderr:write("FAIL: " .. msg .. "\n")
    end
end

local function equal(got, expected, msg)
    if got ~= expected then
        failures = failures + 1
        io.stderr:write(string.format("FAIL: %s (got %q, expected %q)\n",
            msg, tostring(got), tostring(expected)))
    end
end

EbonBuilds = EbonBuilds or {}
EbonBuildsDB = { globalSettings = {} }

local function ReadFile(path)
    local f = assert(io.open(path, "r"))
    local content = f:read("*a")
    f:close()
    return content
end

local function UnescapeKey(key)
    return key:gsub('\\"', '"'):gsub("\\n", "\n"):gsub("\\\\", "\\")
end

local function CollectUsedKeys()
    local used = {}
    local listing = io.popen('git ls-files "core/*.lua" "core/**/*.lua" "modules/*.lua" "modules/**/*.lua"')
    assert(listing, "unable to list Lua sources for i18n key scan")
    for line in listing:lines() do
        line = line:gsub("\\", "/")
        if line:match("^modules/i18n/locales/") then
            -- translation tables register keys; they are not lookup sites
        else
            local src = ReadFile(line)
            local function record(key)
                local unescaped = UnescapeKey(key)
                used[unescaped] = true
            end
            for key in src:gmatch('EbonBuilds%.L%["(.-[^\\])"%]') do record(key) end
            for alias in src:gmatch("local%s+([%a_][%w_]*)%s*=%s*EbonBuilds%.L%f[%W]") do
                local pat = alias:gsub("%W", "%%%1") .. '%["(.-[^\\])"%]'
                for key in src:gmatch(pat) do record(key) end
            end
        end
    end
    listing:close()
    return used
end

assert(loadfile("modules/i18n/Locale.lua"))("EbonBuilds", EbonBuilds)

local registered = {}
local originalRegister = EbonBuilds.Locale.Register
EbonBuilds.Locale.Register = function(code, stringTable)
    registered[code] = stringTable
    return originalRegister(code, stringTable)
end

local localeFiles = {}
local lp = io.popen('git ls-files "modules/i18n/locales/*.lua"')
assert(lp, "unable to list locale files")
for path in lp:lines() do
    path = path:gsub("\\", "/")
    localeFiles[#localeFiles + 1] = path
    assert(loadfile(path))("EbonBuilds", EbonBuilds)
end
lp:close()
table.sort(localeFiles)

-- Shipped locale files must not carry a UTF-8 BOM. luac5.1 treats it as a
-- syntax error and WoW 3.3.5a's loader is equally unhappy.
do
    local function HasUtf8Bom(path)
        local f = assert(io.open(path, "rb"))
        local prefix = f:read(3)
        f:close()
        return prefix == "\239\187\191"
    end
    for _, path in ipairs(localeFiles) do
        check(not HasUtf8Bom(path), path .. " must not start with a UTF-8 BOM")
    end
    local auctionatorLocales = {
        "vendor/Auctionator/Locales/deDE.lua",
        "vendor/Auctionator/Locales/esES.lua",
    }
    for _, path in ipairs(auctionatorLocales) do
        local f = io.open(path, "rb")
        if f then
            local prefix = f:read(3)
            f:close()
            check(prefix ~= "\239\187\191", path .. " must not start with a UTF-8 BOM")
        end
    end
end

local used = CollectUsedKeys()
local usedCount = 0
for _ in pairs(used) do usedCount = usedCount + 1 end

check(usedCount > 0, "at least one L[] key is looked up in the addon")
check(#localeFiles >= 6, "six shipped locale files are present")

for _, path in ipairs(localeFiles) do
    local code = path:match("([^/]+)%.lua$")
    check(EbonBuilds.Locale.IsSupported(code), code .. " is a supported locale")
    local table_ = registered[code]
    check(table_ ~= nil, code .. " registered a string table")
    if table_ then
        local missing = {}
        for key in pairs(used) do
            if table_[key] == nil then
                missing[#missing + 1] = key
            end
        end
        table.sort(missing)
        if #missing > 0 then
            failures = failures + 1
            io.stderr:write(string.format("FAIL: %s missing %d key(s):\n", code, #missing))
            for i = 1, math.min(20, #missing) do
                io.stderr:write("  missing: " .. missing[i] .. "\n")
            end
            if #missing > 20 then
                io.stderr:write(string.format("  ... and %d more\n", #missing - 20))
            end
        else
            print(string.format("OK: %s covers all %d used keys", code, usedCount))
        end
    end
end

do
    local L = EbonBuilds.L
    EbonBuilds.Locale.SetLocale("enUS")
    equal(EbonBuilds.Locale.GetActiveLocale(), "enUS", "default locale is English")
    equal(L["Save build"], "Save build", "English lookup returns the key itself")

    check(EbonBuilds.Locale.SetLocale("deDE"), "German can be activated")
    equal(EbonBuilds.Locale.GetActiveLocale(), "deDE", "active locale updates")
    check(registered.deDE["Save build"] ~= nil, "German Save build entry exists")
    equal(L["Save build"], registered.deDE["Save build"], "German lookup returns the translation")
    equal(L["This key exists nowhere"], "This key exists nowhere",
        "missing keys fall back to the English key")

    check(not EbonBuilds.Locale.SetLocale("koKR"), "unsupported client locale is refused")
    equal(EbonBuilds.Locale.GetActiveLocale(), "deDE", "refused locale does not change state")
    check(not EbonBuilds.Locale.SetLocale(nil), "nil locale is refused")

    equal(EbonBuilds.Locale.ResolveAlias("de"), "deDE", "short alias resolves")
    equal(EbonBuilds.Locale.ResolveAlias("DEDE"), "deDE", "case-insensitive code resolves")
    equal(EbonBuilds.Locale.ResolveAlias("german"), "deDE", "language-name alias resolves")
    equal(EbonBuilds.Locale.ResolveAlias("ruRU"), "ruRU", "exact code resolves")
    equal(EbonBuilds.Locale.ResolveAlias("pl"), "plPL", "manual-only Polish alias resolves")
    equal(EbonBuilds.Locale.ResolveAlias("tlh"), nil, "unknown alias resolves to nil")
    equal(EbonBuilds.Locale.ResolveAlias(""), nil, "empty alias resolves to nil")

    local supported = EbonBuilds.Locale.GetSupportedLocales()
    check(type(supported) == "table" and #supported >= 6, "supported locale list is populated")

    EbonBuildsDB.globalSettings.localeOverride = "frFR"
    function GetLocale() return "deDE" end
    EbonBuilds.Locale.Init()
    equal(EbonBuilds.Locale.GetActiveLocale(), "frFR", "saved override wins over the client locale")
    EbonBuildsDB.globalSettings.localeOverride = nil
    EbonBuilds.Locale.Init()
    equal(EbonBuilds.Locale.GetActiveLocale(), "deDE", "client locale is used without an override")
    function GetLocale() return "koKR" end
    EbonBuilds.Locale.Init()
    equal(EbonBuilds.Locale.GetActiveLocale(), "enUS", "unsupported client locale falls back to English")
end

if failures > 0 then
    io.stderr:write(string.format("%d i18n test(s) failed.\n", failures))
    os.exit(1)
end
print("Locale integrity passed: used-key parity across locales, registry behavior verified.")
