-- Headless tests for Auctionator Project Ebonhold helpers (Lua 5.1).
unpack = unpack or table.unpack

local function fail(message)
    io.stderr:write("AUCTIONATOR_PE FAIL: " .. tostring(message) .. "\n")
    os.exit(1)
end

local function assertEq(a, b, message)
    if a ~= b then
        fail((message or "not equal") .. ": " .. tostring(a) .. " vs " .. tostring(b))
    end
end

local chunk, err = loadfile("vendor/Auctionator/AuctionatorProjectEbonhold.lua")
if not chunk then fail(err) end
local ok, loadErr = pcall(chunk)
if not ok then fail("load AuctionatorProjectEbonhold: " .. tostring(loadErr)) end

assertEq(AtrPE_BuildAffixSearchQuery("Keen Strikes III"), "of Keen Strikes III", "affix query")
assertEq(AtrPE_BuildAffixSearchQuery("of Foo Bar I"), "of Foo Bar I", "preserve of-prefix")
assertEq(AtrPE_BuildAffixSearchQuery(""), "", "empty affix query")

assertEq(
    AtrPE_NormalizeAffixSearch("Keen Strikes III"),
    "of Keen Strikes III",
    "normalize affix line"
)
assertEq(
    AtrPE_NormalizeAffixSearch("Misery's End of Keen Strikes III"),
    "Misery's End of Keen Strikes III",
    "preserve full item name"
)
assertEq(AtrPE_NormalizeAffixSearch('"Exact Item"'), '"Exact Item"', "preserve quoted exact")

local calls = 0
function GetAuctionItemInfo(listType, index)
    calls = calls + 1
    if index == 2 then error("simulated core failure") end
    return "Item", nil, 1, 2, true, 80, 100, 5, 500, 0, nil, "Seller"
end

local name, _, count = AtrPE_SafeGetAuctionItemInfo("list", 1)
assertEq(name, "Item", "safe get ok")
assertEq(count, 1, "safe get count")

name = AtrPE_SafeGetAuctionItemInfo("list", 2)
assertEq(name, nil, "safe get failure returns nil")
assertEq(calls, 2, "safe get invoked twice")

local queryCalls = 0
function QueryAuctionItems(...)
    queryCalls = queryCalls + 1
    if queryCalls == 1 then error("simulated query failure") end
end

local okQuery = AtrPE_SafeQueryAuctionItems("of Keen Strikes III", 0, 0)
assertEq(okQuery, false, "query failure returns false")

okQuery = AtrPE_SafeQueryAuctionItems("test", 0, 0)
assertEq(okQuery, true, "query success returns true")

-- HookShoppingInit / HookConflictCheck must not index function values (Lua 5.1).
-- Reproduce the load-time crash: type(fn)=="function" then fn._peHooked.
local indexed = false
local probe = function() end
local okIndex, indexErr = pcall(function()
    return probe._peHooked
end)
assertEq(okIndex, false, "Lua 5.1 cannot index a function value")
if type(indexErr) == "string" then
    indexed = indexErr:find("index", 1, true) ~= nil
end
assertEq(indexed, true, "index error mentions index")

-- Stub Atr_Init / Atr_Check_For_Conflicts / Atr_SList then load hooks (as .toc does).
local atrInitCalls = 0
function Atr_Init()
    atrInitCalls = atrInitCalls + 1
end

local conflictCalls = 0
function Atr_Check_For_Conflicts(addonName)
    conflictCalls = conflictCalls + 1
end

AUCTIONATOR_SHOPPING_LISTS = {}
local createdLists = {}
Atr_SList = {
    create = function(name)
        local slist = {
            name = name,
            items = {},
            isSorted = true,
            AddItem = function(self, item)
                table.insert(self.items, item)
            end,
        }
        table.insert(AUCTIONATOR_SHOPPING_LISTS, slist)
        table.insert(createdLists, slist)
        return slist
    end,
}

AtrSearch = {
    Init = function(self, searchText, exact, rescanThreshold, callback)
        return searchText, exact
    end,
}

local hooksChunk, hooksErr = loadfile("vendor/Auctionator/AuctionatorProjectEbonholdHooks.lua")
if not hooksChunk then fail(hooksErr) end
local okHooks, hooksLoadErr = pcall(hooksChunk)
if not okHooks then fail("load AuctionatorProjectEbonholdHooks: " .. tostring(hooksLoadErr)) end

-- Hooks wrap globals; call wrapped Atr_Init and ensure shopping list is seeded.
Atr_Init()
assertEq(atrInitCalls, 1, "wrapped Atr_Init calls original")
assertEq(#createdLists, 1, "EnsureEbonBuildsShoppingList creates one list")
assertEq(createdLists[1].name, "EbonBuilds Affixes", "shopping list name")
assertEq(#createdLists[1].items, 2, "seeded affix search items")
assertEq(createdLists[1].items[1], "of Keen Strikes III", "first seed query")

Atr_Check_For_Conflicts("OtherAddon")
assertEq(conflictCalls, 1, "wrapped conflict check calls original")

-- Idempotent: loading hooks again must not double-wrap / error.
local okHooks2, hooksLoadErr2 = pcall(hooksChunk)
if not okHooks2 then fail("reload AuctionatorProjectEbonholdHooks: " .. tostring(hooksLoadErr2)) end
Atr_Init()
assertEq(atrInitCalls, 2, "second Atr_Init still single-wrapped")
assertEq(#createdLists, 1, "shopping list not duplicated on second init")

local normText = AtrSearch:Init("Keen Strikes III", false, nil, nil)
assertEq(normText, "of Keen Strikes III", "AtrSearch:Init affix normalize hook")

print("AUCTIONATOR_PE OK")
