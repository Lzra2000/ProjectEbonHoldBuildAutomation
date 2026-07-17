-- EbonBuilds: modules/vendor/AutoSell.lua
-- Sells zero-value bag items to an open vendor. Off by default -- the
-- player must explicitly opt in with /ebb autosell.
--
-- Deliberately narrow scope: this is NOT a rule engine (no whitelist,
-- keep-list, category filters, BoE tracking, disenchant handling -- that
-- is AutoDelete's job, and AutoDelete already does it well on this
-- server). EbonBuilds only adds the one thing that's actually specific to
-- it: an item carrying an affix you haven't learned yet is protected even
-- if a vendor would pay nothing for it, since a 0-copper item can still be
-- worth inspecting/learning from.
--
-- Selling (not deleting) a worthless item is also the safer choice even
-- though the net gold is the same either way: WoW's vendor buyback tab
-- gives a same-session undo window that a direct bag deletion never has.

EbonBuilds.AutoSell = {}

local enabled = false

function EbonBuilds.AutoSell.SetEnabled(on)
    enabled = on and true or false
    EbonBuildsCharDB.autoSellJunkEnabled = enabled
end

function EbonBuilds.AutoSell.IsEnabled()
    return enabled
end

-- Equip location -> inventory slot id(s). Rings/trinkets map to BOTH of
-- their slots since either could be the one worth replacing.
local EQUIP_SLOT_IDS = {
    INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3},
    INVTYPE_CHEST = {5}, INVTYPE_ROBE = {5}, INVTYPE_WAIST = {6},
    INVTYPE_LEGS = {7}, INVTYPE_FEET = {8}, INVTYPE_WRIST = {9},
    INVTYPE_HAND = {10}, INVTYPE_FINGER = {11, 12}, INVTYPE_TRINKET = {13, 14},
    INVTYPE_CLOAK = {15}, INVTYPE_WEAPON = {16}, INVTYPE_2HWEAPON = {16},
    INVTYPE_WEAPONMAINHAND = {16}, INVTYPE_WEAPONOFFHAND = {17},
    INVTYPE_SHIELD = {17}, INVTYPE_HOLDABLE = {17}, INVTYPE_RANGED = {18},
    INVTYPE_RANGEDRIGHT = {18}, INVTYPE_THROWN = {18}, INVTYPE_RELIC = {18},
}

-- Is this item a gear upgrade over what's currently equipped, for the
-- active build's class/spec? Only meaningful for actual equipment (has an
-- INVTYPE_* equip location) -- everything else returns false and falls
-- through to the normal sellPrice/affix checks.
local function IsGearUpgrade(equipLoc, itemLink)
    local slotIds = equipLoc and EQUIP_SLOT_IDS[equipLoc]
    if not slotIds then return false end
    local build = EbonBuilds.Build.GetActive()
    local specKey = build and EbonBuilds.GearScore.SpecKey(build.class, build.spec)
    if not specKey then return false end

    local newScore = EbonBuilds.GearScore.ScoreItem(itemLink, specKey)
    -- For dual slots (rings/trinkets), compare against the WEAKER of the
    -- two currently equipped -- that's the one worth replacing.
    local worstCurrent = nil
    for _, slotId in ipairs(slotIds) do
        local curLink = GetInventoryItemLink("player", slotId)
        local curScore = curLink and EbonBuilds.GearScore.ScoreItem(curLink, specKey) or 0
        if not worstCurrent or curScore < worstCurrent then
            worstCurrent = curScore
        end
    end
    return newScore > (worstCurrent or 0)
end

-- Pure decision function: should this bag item be sold?
-- getItemInfo(link) -> name, _, _, _, _, _, _, equipLoc, _, _, sellPrice
-- (injected for testability, matching the pattern used by
-- AffixItemScan/Talents).
function EbonBuilds.AutoSell.ShouldSell(link, getItemInfo)
    if not link then return false end
    getItemInfo = getItemInfo or GetItemInfo
    local name, _, _, _, _, _, _, _, equipLoc, _, sellPrice = getItemInfo(link)
    if not name then return false end -- not cached client-side yet; skip, don't guess
    if sellPrice and sellPrice > 0 then return false end -- has real value, not junk
    if EbonBuilds.AffixItemScan.IsProtectedFromSelling(name) then return false end
    if IsGearUpgrade(equipLoc, link) then return false end
    return true
end

local sellQueue = {}
local sellTicker
local SELL_INTERVAL = 0.3 -- seconds between individual sells; gentle pacing,
                           -- avoids firing a burst of rapid consecutive
                           -- sell requests at the server (see AutoDelete's
                           -- own throttled sell/delete queues for why).

local function EnsureSellTicker()
    if sellTicker then return end
    sellTicker = CreateFrame("Frame")
    local elapsed = 0
    local consecutiveFailures = 0
    local rawTick = function(self, dt)
        if #sellQueue == 0 or not MerchantFrame or not MerchantFrame:IsShown() then
            self:SetScript("OnUpdate", nil)
            sellTicker = nil
            wipe(sellQueue)
            return true
        end
        elapsed = elapsed + dt
        if elapsed < SELL_INTERVAL then return true end
        elapsed = 0
        local next_ = table.remove(sellQueue, 1)
        if next_ then
            -- Re-verify at sell time: bag contents can shift while the
            -- queue drains (picked up loot, another sell already emptied
            -- an earlier slot, etc.), so don't trust a stale decision.
            local link = GetContainerItemLink(next_.bag, next_.slot)
            if link and EbonBuilds.AutoSell.ShouldSell(link) then
                UseContainerItem(next_.bag, next_.slot)
            end
        end
        return true
    end
    local protectedTick = EbonBuilds.ErrorLog.Protect("AutoSell.ticker", rawTick)
    sellTicker:SetScript("OnUpdate", function(self, dt)
        local ok = protectedTick(self, dt)
        if ok == nil then
            -- Protect() returns nil on a caught error (rawTick always
            -- returns true on success, so nil is unambiguous here). A
            -- repeating OnUpdate that errors every tick would otherwise
            -- get its error silently swallowed forever (once per frame)
            -- without ever actually stopping -- self-terminate after a
            -- few consecutive failures instead of running broken forever.
            consecutiveFailures = consecutiveFailures + 1
            if consecutiveFailures >= 3 then
                self:SetScript("OnUpdate", nil)
                sellTicker = nil
                wipe(sellQueue)
            end
        else
            consecutiveFailures = 0
        end
    end)
end

local function SellBags()
    if not enabled then return end
    wipe(sellQueue)
    for bag = 0, 4 do
        local slots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link and EbonBuilds.AutoSell.ShouldSell(link) then
                sellQueue[#sellQueue + 1] = { bag = bag, slot = slot }
            end
        end
    end
    if #sellQueue > 0 then
        EnsureSellTicker()
    end
end

function EbonBuilds.AutoSell.Init()
    if EbonBuildsCharDB.autoSellJunkEnabled ~= nil then
        enabled = EbonBuildsCharDB.autoSellJunkEnabled
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("MERCHANT_SHOW")
    f:RegisterEvent("MERCHANT_CLOSED")
    f:SetScript("OnEvent", EbonBuilds.ErrorLog.Protect("AutoSell", function(_, event)
        if event == "MERCHANT_SHOW" then
            SellBags()
        else -- MERCHANT_CLOSED: stop immediately, don't wait for the next poll
            wipe(sellQueue)
            if sellTicker then sellTicker:SetScript("OnUpdate", nil); sellTicker = nil end
        end
    end))
end
