-- AutoSell category / keep-list / ShouldSell decision coverage.
-- Category names come from GetAuctionItemClasses() indices 6/9 (3.3.5a),
-- matching GetItemInfo's localized itemType (#71).
unpack = unpack or table.unpack

local H = dofile("tests/harness.lua")
local counters = H.new_counters()
local check, equal = H.attach_assertions(counters)

H.install_auction_class_stubs()
strlower = strlower or string.lower
strtrim = strtrim or function(s)
    return (tostring(s or ""):match("^%s*(.-)%s*$"))
end

EbonBuildsCharDB = {}
local addon = {
    L = setmetatable({}, { __index = function(_, key) return key end }),
    RingBuffer = {
        New = function() return {} end,
        Clear = function() end,
        Append = function() end,
        Count = function() return 0 end,
        PopOldest = function() return nil end,
    },
    AffixItemScan = {
        IsProtectedFromSelling = function() return false end,
    },
    Build = { GetActive = function() return nil end },
    GearScore = {},
    Scheduler = {
        INTERACTIVE = 1,
        Every = function() end,
        Cancel = function() end,
    },
    WoWEvents = H.wow_events_stub(),
    ErrorLog = {
        Protect = function(_, fn) return fn end,
    },
    Toast = { Show = function() end },
}
H.load_addon("core/RingBuffer.lua", addon)
H.load_addon("modules/vendor/AutoSell.lua", addon)
local AS = addon.AutoSell

local function StubInfo(name, quality, itemType, equipLoc, sellPrice, itemLevel)
    return function()
        return name, name, quality, itemLevel or 1, 1, itemType, "", 1, equipLoc or "", "", sellPrice or 0
    end
end

local LINK_2589 = "|cff9d9d9d|Hitem:2589:0:0:0:0:0:0:0|h[Linen Cloth]|h|r"

------------------------------------------------------------------------
-- Category defaults and persistence
------------------------------------------------------------------------
do
    local cats = AS.GetCategories()
    equal(cats.poorOnly, false, "poorOnly defaults off")
    equal(cats.excludeTradeGoods, true, "excludeTradeGoods defaults on")
    equal(cats.excludeRecipes, true, "excludeRecipes defaults on")
    equal(cats.sellCommon, true, "sellCommon defaults on")
    equal(cats.sellUncommon, true, "sellUncommon defaults on")
    equal(cats.excludeRareEpic, true, "excludeRareEpic defaults on")
    equal(cats.neverSellSoulbound, true, "neverSellSoulbound defaults on")
    equal(cats.neverSellBoE, true, "neverSellBoE defaults on")
    equal(cats.dryRun, false, "dryRun defaults off")

    local opts = AS.GetOptions()
    equal(opts.maxItemLevel, 0, "maxItemLevel defaults 0")
    equal(opts.minStackCount, 1, "minStackCount defaults 1")

    check(AS.SetCategory("poorOnly", true), "poorOnly can be set")
    equal(AS.GetCategory("poorOnly"), true, "poorOnly persists in memory")
    equal(EbonBuildsCharDB.autoSellCategories.poorOnly, true, "poorOnly persists to char DB")
    check(not AS.SetCategory("notAKey", true), "unknown category key rejected")
    AS.SetCategory("poorOnly", false)

    check(AS.SetOption("maxItemLevel", 55), "maxItemLevel can be set")
    equal(AS.GetOption("maxItemLevel"), 55, "maxItemLevel persists")
    AS.SetOption("maxItemLevel", 0)
end

------------------------------------------------------------------------
-- Keep-list: names, IDs, patterns
------------------------------------------------------------------------
do
    check(AS.AddToKeepList("Ruined Pelt"), "keep-list add")
    check(not AS.AddToKeepList("Ruined Pelt"), "duplicate keep-list add rejected")
    check(AS.IsKept("ruined pelt"), "keep-list match is case-insensitive")
    check(AS.AddKeepEntry("#2589"), "AddKeepEntry accepts item id")
    check(AS.IsKeptId(2589), "keep id match")
    check(not AS.AddKeepEntry("#2589"), "duplicate item id rejected")
    check(AS.AddKeepPattern("*Pelt*"), "keep pattern add")
    check(AS.MatchesKeepPattern("Ruined Pelt"), "pattern wildcard match")
    check(AS.AddKeepEntry("*Fang*"), "AddKeepEntry accepts pattern")
    AS.RemoveFromKeepList("Ruined Pelt")
    AS.RemoveKeepId(2589)
    AS.RemoveKeepPattern("*Pelt*")
    AS.RemoveKeepPattern("*Fang*")
end

------------------------------------------------------------------------
-- ShouldSell decisions
------------------------------------------------------------------------
do
    equal(AS.ShouldSell("link", StubInfo("Copper Coin", 0, "Junk", "", 1)), false,
        "positive sellPrice is never junk")

    equal(AS.ShouldSell("link", StubInfo("Rags", 0, "Junk", "", 0)), true,
        "zero-value junk sells by default")

    equal(AS.ShouldSell("link", StubInfo("Copper Ore", 1, "Trade Goods", "", 0)), false,
        "Trade Goods excluded by default")
    equal(AS.ShouldSell("link", StubInfo("Plans: Foo", 1, "Recipe", "", 0)), false,
        "Recipes excluded by default")

    AS.SetCategory("excludeTradeGoods", false)
    equal(AS.ShouldSell("link", StubInfo("Copper Ore", 1, "Trade Goods", "", 0)), true,
        "Trade Goods sellable when excludeTradeGoods off")
    AS.SetCategory("excludeTradeGoods", true)

    AS.SetCategory("poorOnly", true)
    equal(AS.ShouldSell("link", StubInfo("White Cloth", 1, "Junk", "", 0)), false,
        "poorOnly blocks Common quality")
    equal(AS.ShouldSell("link", StubInfo("Gray Cloth", 0, "Junk", "", 0)), true,
        "poorOnly allows Poor quality")
    AS.SetCategory("poorOnly", false)

    AS.SetCategory("sellCommon", false)
    equal(AS.ShouldSell("link", StubInfo("White Cloth", 1, "Junk", "", 0)), false,
        "sellCommon off blocks white junk")
    AS.SetCategory("sellCommon", true)

    AS.SetCategory("sellUncommon", false)
    equal(AS.ShouldSell("link", StubInfo("Green Junk", 2, "Junk", "", 0)), false,
        "sellUncommon off blocks green junk")
    AS.SetCategory("sellUncommon", true)

    equal(AS.ShouldSell("link", StubInfo("Blue Junk", 3, "Junk", "", 0)), false,
        "excludeRareEpic blocks rare by default")
    AS.SetCategory("excludeRareEpic", false)
    equal(AS.ShouldSell("link", StubInfo("Blue Junk", 3, "Junk", "", 0)), true,
        "rare sellable when excludeRareEpic off")
    AS.SetCategory("excludeRareEpic", true)

    AS.AddToKeepList("Special Junk")
    equal(AS.ShouldSell("link", StubInfo("Special Junk", 0, "Junk", "", 0)), false,
        "keep-list overrides sell decision")
    AS.RemoveFromKeepList("Special Junk")

    AS.AddKeepId(2589)
    equal(AS.ShouldSell(LINK_2589, StubInfo("Linen Cloth", 1, "Junk", "", 0)), false,
        "keep id blocks sell")
    AS.RemoveKeepId(2589)

    AS.AddKeepPattern("Affix*")
    equal(AS.ShouldSell("link", StubInfo("Affix Token", 0, "Junk", "", 0)), false,
        "keep pattern blocks sell")
    AS.RemoveKeepPattern("Affix*")

    AS.SetOption("maxItemLevel", 10)
    equal(AS.ShouldSell("link", StubInfo("High Level", 0, "Junk", "", 0, 20)), false,
        "maxItemLevel blocks high ilvl items")
    equal(AS.ShouldSell("link", StubInfo("Low Level", 0, "Junk", "", 0, 5)), true,
        "maxItemLevel allows low ilvl items")
    AS.SetOption("maxItemLevel", 0)

    AS.SetOption("minStackCount", 5)
    equal(AS.ShouldSell("link", StubInfo("Partial Stack", 0, "Junk", "", 0), { stackCount = 2 }), false,
        "minStackCount blocks small stacks")
    equal(AS.ShouldSell("link", StubInfo("Full Stack", 0, "Junk", "", 0), { stackCount = 5 }), true,
        "minStackCount allows large stacks")
    AS.SetOption("minStackCount", 1)

    equal(AS.ShouldSell("link", StubInfo("Bound Gray", 0, "Junk", "", 0), { bindStatus = "bound" }), false,
        "neverSellSoulbound blocks bound items")
    equal(AS.ShouldSell("link", StubInfo("BoE White", 1, "Junk", "", 0), { bindStatus = "boe" }), false,
        "neverSellBoE blocks unbound BoE")
    AS.SetCategory("neverSellSoulbound", false)
    AS.SetCategory("neverSellBoE", false)
    equal(AS.ShouldSell("link", StubInfo("Bound Gray", 0, "Junk", "", 0), { bindStatus = "bound" }), true,
        "bound items sellable when neverSellSoulbound off")
    AS.SetCategory("neverSellSoulbound", true)
    AS.SetCategory("neverSellBoE", true)

    AS.SetCategory("excludeRareEpic", false)
    equal(AS.ShouldSell("link", StubInfo("Epic Bound", 4, "Junk", "", 0), { bindStatus = "bound" }), false,
        "neverSellSoulboundEpic blocks purple soulbound")
    AS.SetCategory("excludeRareEpic", true)

    addon.AffixItemScan.IsProtectedFromSelling = function(name)
        return name == "Affix Token"
    end
    equal(AS.ShouldSell("link", StubInfo("Affix Token", 0, "Junk", "", 0)), false,
        "AffixItemScan protection blocks sell")
    addon.AffixItemScan.IsProtectedFromSelling = function() return false end
end

------------------------------------------------------------------------
-- Localized auction class names via GetAuctionItemClasses (issue #71).
------------------------------------------------------------------------
do
    function GetAuctionItemClasses()
        return "Waffe", "Rüstung", "Behälter", "Verbrauchbar", "Glyphe",
            "Handwerkswaren", "Projektil", "Köcher", "Rezept", "Edelstein",
            "Verschiedenes", "Quest"
    end
    equal(AS.ShouldSell("link", StubInfo("Erz", 1, "Handwerkswaren", "", 0)), false,
        "German Trade Goods (auction class 6) excluded")
    equal(AS.ShouldSell("link", StubInfo("Rezept: Foo", 1, "Rezept", "", 0)), false,
        "German Recipe (auction class 9) excluded")
    H.install_auction_class_stubs()
end

------------------------------------------------------------------------
-- GetAuctionItemClasses edge cases (missing API, errors, short list)
------------------------------------------------------------------------
do
    local saved = GetAuctionItemClasses

    GetAuctionItemClasses = nil
    equal(AS.ShouldSell("link", StubInfo("Copper Ore", 1, "Trade Goods", "", 0)), false,
        "English Trade Goods excluded when GetAuctionItemClasses is nil")

    GetAuctionItemClasses = "not a function"
    equal(AS.ShouldSell("link", StubInfo("Plans: Foo", 1, "Recipe", "", 0)), false,
        "English Recipe excluded when GetAuctionItemClasses is not callable")

    GetAuctionItemClasses = function()
        error("broken auction class API")
    end
    equal(AS.ShouldSell("link", StubInfo("Copper Ore", 1, "Trade Goods", "", 0)), false,
        "category filters survive GetAuctionItemClasses errors")

    GetAuctionItemClasses = function()
        return "Weapon", "Armor", "Container", "Consumable", "Glyph"
    end
    equal(AS.ShouldSell("link", StubInfo("Copper Ore", 1, "Trade Goods", "", 0)), false,
        "short auction class list falls back to English Trade Goods")

    GetAuctionItemClasses = saved
    H.install_auction_class_stubs()
end

------------------------------------------------------------------------
-- CountEligible dry-run helper
------------------------------------------------------------------------
do
    GetContainerNumSlots = function() return 16 end
    local calls = 0
    local count = AS.CountEligible(function(bag, slot)
        calls = calls + 1
        return bag == 0 and slot == 1
    end)
    equal(count, 1, "CountEligible counts matching slots")
    equal(calls, 5 * 16, "CountEligible scans all bag slots (0-4, up to 16 each)")
end

------------------------------------------------------------------------
-- Init wires merchant events through WoWEvents (not raw RegisterEvent)
------------------------------------------------------------------------
do
    AS.Init()
    equal(addon.WoWEvents.Count("MERCHANT_SHOW"), 1, "MERCHANT_SHOW via WoWEvents")
    equal(addon.WoWEvents.Count("MERCHANT_CLOSED"), 1, "MERCHANT_CLOSED via WoWEvents")
end

do
    local src = H.read_file("modules/vendor/AutoSell.lua")
    check(src:find("GetContainerItemInfo and", 1, true),
        "AutoSell guards GetContainerItemInfo when reading stack counts")
    check(src:find("GetAuctionItemClasses", 1, true),
        "AutoSell resolves localized category names via GetAuctionItemClasses (#71)")
    check(src:find("pcall", 1, true),
        "AutoSell guards GetAuctionItemClasses with pcall")
    check(src:find("neverSellSoulbound", 1, true),
        "AutoSell exposes soulbound safety filter")
end

H.exit_if_failed(counters, "AutoSell test(s)")
print("AutoSell coverage passed: options, keep-list IDs/patterns, bind/quality filters, and API hardening.")
