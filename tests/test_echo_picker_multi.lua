-- Headless coverage for EchoPicker multi-select selection helpers.
-- Run from addon root: lua5.1 tests/test_echo_picker_multi.lua

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. message .. "\n")
    end
end
local function equal(actual, expected, message)
    check(actual == expected, string.format("%s (expected %s, got %s)",
        message, tostring(expected), tostring(actual)))
end

-- Minimal surface so EchoPicker.lua can load without FrameXML / Theme widgets.
EbonBuilds = {
    EchoIdentity = {
        NormalizeSearch = function(v)
            return string.lower(tostring(v or "")):gsub("%s+", " ")
        end,
        VisibleName = function(v) return v end,
        StripClassPrefix = function(v) return v end,
        StripQualitySuffix = function(v) return v end,
    },
    Theme = {},
    VirtualList = {},
    Quality = { GetRGB = function() return 1, 1, 1 end, LABELS = {} },
    Build = { PlayerClassToken = function() return "SHAMAN" end },
    Debug = {},
}

local chunk = assert(loadfile("modules/ui/EchoPicker.lua"))
chunk("EbonBuilds", EbonBuilds)

local Picker = EbonBuilds.EchoPicker
check(type(Picker) == "table", "EchoPicker module table exists")
check(type(Picker.Open) == "function", "Open API exists")
check(type(Picker.Show) == "function", "Show API exists")
check(type(Picker.SelectionKey) == "function", "SelectionKey helper exists")
check(type(Picker.ToggleSelectionState) == "function", "ToggleSelectionState helper exists")
check(type(Picker.SelectAllInList) == "function", "SelectAllInList helper exists")
check(type(Picker.CollectSelectedList) == "function", "CollectSelectedList helper exists")
check(type(Picker.ClearSelectionState) == "function", "ClearSelectionState helper exists")

do
    equal(Picker.SelectionKey({ spellId = 12345 }), 12345, "SelectionKey prefers spellId")
    equal(Picker.SelectionKey({ id = "99" }), 99, "SelectionKey coerces id")
    equal(Picker.SelectionKey({ refKey = "echo:foo" }), "echo:foo", "SelectionKey falls back to refKey")
    equal(Picker.SelectionKey({}), nil, "SelectionKey nil for empty entry")
    equal(Picker.SelectionKey(nil), nil, "SelectionKey nil for nil")
end

do
    local state = Picker.ClearSelectionState({})
    equal(state.count, 0, "fresh selection is empty")

    local a = { spellId = 101, displayName = "Alpha" }
    local b = { spellId = 202, displayName = "Beta" }
    local c = { spellId = 303, displayName = "Gamma" }

    local _, nowOn = Picker.ToggleSelectionState(state, a)
    check(nowOn == true, "first toggle selects")
    equal(state.count, 1, "count after first select")

    _, nowOn = Picker.ToggleSelectionState(state, a)
    check(nowOn == false, "second toggle clears")
    equal(state.count, 0, "count after deselect")

    Picker.ToggleSelectionState(state, a)
    Picker.ToggleSelectionState(state, b)
    Picker.ToggleSelectionState(state, c)
    equal(state.count, 3, "three selected")

    local list = Picker.CollectSelectedList(state)
    equal(#list, 3, "collect returns three")
    equal(list[1].spellId, 101, "order preserves first click")
    equal(list[2].spellId, 202, "order preserves second click")
    equal(list[3].spellId, 303, "order preserves third click")

    Picker.ToggleSelectionState(state, b)
    list = Picker.CollectSelectedList(state)
    equal(#list, 2, "deselect middle shrinks list")
    equal(list[1].spellId, 101, "remaining keep relative order")
    equal(list[2].spellId, 303, "middle removal leaves neighbors")
end

do
    local state = Picker.ClearSelectionState({})
    local visible = {
        { spellId = 1, displayName = "One" },
        { spellId = 2, displayName = "Two" },
        { spellId = 1, displayName = "One again" }, -- duplicate key ignored
    }
    Picker.SelectAllInList(state, visible)
    equal(state.count, 2, "select-all skips duplicate keys")
    Picker.SelectAllInList(state, visible)
    equal(state.count, 2, "select-all is idempotent")

    Picker.ClearSelectionState(state)
    equal(state.count, 0, "clear resets count")
    equal(#Picker.CollectSelectedList(state), 0, "clear empties collect")
end

if failures > 0 then
    io.stderr:write(string.format("test_echo_picker_multi: %d failure(s)\n", failures))
    os.exit(1)
end
print("test_echo_picker_multi: all checks passed")
