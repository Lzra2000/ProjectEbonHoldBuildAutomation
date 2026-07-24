local addonName, EbonBuilds = ...

-- EbonBuilds: modules/vendor/AutoSell.lua
-- Sells zero-value bag items to an open vendor only (not the Auction House).
-- Off by default -- the player must explicitly opt in via Settings.
--
-- Extended with keep-lists (names, item IDs, wildcards), quality/bind filters,
-- item-level and stack thresholds, and a dry-run preview mode.

EbonBuilds.AutoSell = {}

local L = EbonBuilds.L

local enabled = false

function EbonBuilds.AutoSell.SetEnabled(on)
    enabled = on and true or false
    if EbonBuilds.Database and EbonBuilds.Database.SetCharacterPreference then
        EbonBuilds.Database.SetCharacterPreference("autoSellJunkEnabled", enabled)
    else
        EbonBuildsCharDB.autoSellJunkEnabled = enabled
    end
end

function EbonBuilds.AutoSell.IsEnabled()
    return enabled
end

------------------------------------------------------------------------
-- Keep-list: exact names, numeric item IDs, and name patterns (* wildcards).
------------------------------------------------------------------------

local function KeepNamesDB()
    EbonBuildsCharDB.autoSellKeepList = type(EbonBuildsCharDB.autoSellKeepList) == "table"
        and EbonBuildsCharDB.autoSellKeepList or {}
    return EbonBuildsCharDB.autoSellKeepList
end

local function KeepIdsDB()
    EbonBuildsCharDB.autoSellKeepIds = type(EbonBuildsCharDB.autoSellKeepIds) == "table"
        and EbonBuildsCharDB.autoSellKeepIds or {}
    return EbonBuildsCharDB.autoSellKeepIds
end

local function KeepPatternsDB()
    EbonBuildsCharDB.autoSellKeepPatterns = type(EbonBuildsCharDB.autoSellKeepPatterns) == "table"
        and EbonBuildsCharDB.autoSellKeepPatterns or {}
    return EbonBuildsCharDB.autoSellKeepPatterns
end

local function WildcardToPattern(wildcard)
    local escaped = wildcard:gsub("([%%%(%)%.%+%-%?%[%]%^%$])", "%%%1")
    return "^" .. escaped:gsub("%*", ".*") .. "$"
end

local function ParseItemId(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

function EbonBuilds.AutoSell.AddToKeepList(itemName)
    if not itemName or itemName == "" then return false end
    local list = KeepNamesDB()
    local key = strlower(itemName)
    if list[key] then return false end
    list[key] = itemName
    return true
end

function EbonBuilds.AutoSell.RemoveFromKeepList(itemName)
    if not itemName or itemName == "" then return false end
    local list = KeepNamesDB()
    local key = strlower(itemName)
    if not list[key] then return false end
    list[key] = nil
    return true
end

function EbonBuilds.AutoSell.AddKeepId(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId < 1 then return false end
    local list = KeepIdsDB()
    if list[itemId] then return false end
    list[itemId] = true
    return true
end

function EbonBuilds.AutoSell.RemoveKeepId(itemId)
    itemId = tonumber(itemId)
    if not itemId then return false end
    local list = KeepIdsDB()
    if not list[itemId] then return false end
    list[itemId] = nil
    return true
end

function EbonBuilds.AutoSell.AddKeepPattern(pattern)
    if not pattern or pattern == "" then return false end
    local list = KeepPatternsDB()
    for _, existing in ipairs(list) do
        if existing == pattern then return false end
    end
    list[#list + 1] = pattern
    return true
end

function EbonBuilds.AutoSell.RemoveKeepPattern(pattern)
    if not pattern or pattern == "" then return false end
    local list = KeepPatternsDB()
    for i, existing in ipairs(list) do
        if existing == pattern then
            table.remove(list, i)
            return true
        end
    end
    return false
end

-- Accepts an exact name, numeric item ID, or pattern containing *.
function EbonBuilds.AutoSell.AddKeepEntry(text)
    text = strtrim(text or "")
    if text == "" then return false end
    if text:match("^#?(%d+)$") then
        return EbonBuilds.AutoSell.AddKeepId(tonumber(text:match("^#?(%d+)$")))
    end
    if text:find("*", 1, true) then
        return EbonBuilds.AutoSell.AddKeepPattern(text)
    end
    return EbonBuilds.AutoSell.AddToKeepList(text)
end

function EbonBuilds.AutoSell.RemoveKeepEntry(displayText)
    if not displayText or displayText == "" then return false end
    local id = displayText:match("^#(%d+)$")
    if id then return EbonBuilds.AutoSell.RemoveKeepId(tonumber(id)) end
    if displayText:sub(1, 1) == "~" then
        return EbonBuilds.AutoSell.RemoveKeepPattern(displayText:sub(2))
    end
    return EbonBuilds.AutoSell.RemoveFromKeepList(displayText)
end

function EbonBuilds.AutoSell.GetKeepList()
    local entries = {}
    for _, name in pairs(KeepNamesDB()) do entries[#entries + 1] = name end
    for itemId in pairs(KeepIdsDB()) do entries[#entries + 1] = "#" .. itemId end
    for _, pattern in ipairs(KeepPatternsDB()) do entries[#entries + 1] = "~" .. pattern end
    table.sort(entries)
    return entries
end

function EbonBuilds.AutoSell.IsKept(itemName)
    if not itemName then return false end
    return KeepNamesDB()[strlower(itemName)] ~= nil
end

function EbonBuilds.AutoSell.IsKeptId(itemId)
    itemId = tonumber(itemId)
    if not itemId then return false end
    return KeepIdsDB()[itemId] == true
end

function EbonBuilds.AutoSell.MatchesKeepPattern(itemName)
    if not itemName then return false end
    local lower = strlower(itemName)
    for _, pattern in ipairs(KeepPatternsDB()) do
        local luaPattern = WildcardToPattern(strlower(pattern))
        if lower:match(luaPattern) then return true end
    end
    return false
end

function EbonBuilds.AutoSell.IsProtected(link, name)
    if name and EbonBuilds.AutoSell.IsKept(name) then return true end
    if name and EbonBuilds.AutoSell.MatchesKeepPattern(name) then return true end
    local itemId = ParseItemId(link)
    if itemId and EbonBuilds.AutoSell.IsKeptId(itemId) then return true end
    return false
end

------------------------------------------------------------------------
-- Category filters (boolean toggles saved per character).
------------------------------------------------------------------------

local DEFAULT_CATEGORIES = {
    poorOnly = false,
    excludeTradeGoods = true,
    excludeRecipes = true,
    sellCommon = true,
    sellUncommon = true,
    excludeRareEpic = true,
    neverSellSoulbound = true,
    neverSellBoE = true,
    neverSellSoulboundEpic = true,
    dryRun = false,
}

local categories = {}
for k, v in pairs(DEFAULT_CATEGORIES) do categories[k] = v end

local DEFAULT_OPTIONS = {
    maxItemLevel = 0,   -- 0 = no cap
    minStackCount = 1,  -- only sell stacks with at least this many items
}

local options = {}
for k, v in pairs(DEFAULT_OPTIONS) do options[k] = v end

local function LoadCategories()
    local saved = EbonBuildsCharDB.autoSellCategories
    if type(saved) == "table" then
        for k in pairs(DEFAULT_CATEGORIES) do
            if saved[k] ~= nil then categories[k] = saved[k] and true or false end
        end
    end
    local savedOpts = EbonBuildsCharDB.autoSellOptions
    if type(savedOpts) == "table" then
        for k in pairs(DEFAULT_OPTIONS) do
            local value = savedOpts[k]
            if value ~= nil then
                if k == "maxItemLevel" or k == "minStackCount" then
                    options[k] = math.max(0, math.floor(tonumber(value) or DEFAULT_OPTIONS[k]))
                    if k == "minStackCount" and options[k] < 1 then options[k] = 1 end
                end
            end
        end
    end
end

local function SaveCategories()
    EbonBuildsCharDB.autoSellCategories = categories
    EbonBuildsCharDB.autoSellOptions = options
end

function EbonBuilds.AutoSell.SetCategory(key, value)
    if DEFAULT_CATEGORIES[key] == nil then return false end
    categories[key] = value and true or false
    SaveCategories()
    return true
end

function EbonBuilds.AutoSell.GetCategory(key)
    return categories[key]
end

function EbonBuilds.AutoSell.GetCategories()
    local copy = {}
    for k, v in pairs(categories) do copy[k] = v end
    return copy
end

function EbonBuilds.AutoSell.SetOption(key, value)
    if DEFAULT_OPTIONS[key] == nil then return false end
    if key == "maxItemLevel" then
        options[key] = math.max(0, math.floor(tonumber(value) or 0))
    elseif key == "minStackCount" then
        options[key] = math.max(1, math.floor(tonumber(value) or 1))
    end
    SaveCategories()
    return true
end

function EbonBuilds.AutoSell.GetOption(key)
    return options[key]
end

function EbonBuilds.AutoSell.GetOptions()
    local copy = {}
    for k, v in pairs(options) do copy[k] = v end
    return copy
end

------------------------------------------------------------------------
-- Bind detection via tooltip (3.3.5a has no direct bind API on bag items).
------------------------------------------------------------------------

local scanTip

local function GetBindStatus(bag, slot)
    if not (ITEM_BIND_ON_EQUIP or ITEM_SOULBOUND) then return "other" end
    if type(bag) ~= "number" or type(slot) ~= "number" then return "other" end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "EbonBuildsAutoSellScanTip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    local ok = pcall(function() scanTip:SetBagItem(bag, slot) end)
    if not ok then return "other" end
    for i = 1, scanTip:NumLines() do
        local fs = _G["EbonBuildsAutoSellScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text == ITEM_SOULBOUND then return "bound" end
        if text == ITEM_BIND_ON_EQUIP then return "boe" end
    end
    return "other"
end

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

local function IsGearUpgrade(equipLoc, itemLink)
    local slotIds = equipLoc and EQUIP_SLOT_IDS[equipLoc]
    if not slotIds then return false end
    local build = EbonBuilds.Build.GetActive()
    local specKey = build and EbonBuilds.GearScore.SpecKey(build.class, build.spec)
    if not specKey then return false end

    local newScore = EbonBuilds.GearScore.ScoreItem(itemLink, specKey)
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

local AUCTION_CLASS_TRADE_GOODS = 6
local AUCTION_CLASS_RECIPE = 9

local function AuctionItemClass(index, englishFallback)
    englishFallback = type(englishFallback) == "string" and englishFallback or ""
    if type(index) ~= "number" or index < 1 then
        return englishFallback
    end
    if type(GetAuctionItemClasses) ~= "function" then
        return englishFallback
    end
    local ok, name = pcall(function()
        return select(index, GetAuctionItemClasses())
    end)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return englishFallback
end

local function QualityAllowed(quality)
    if quality == nil then return true end
    if categories.poorOnly then
        return quality == 0
    end
    if quality == 0 then return true end
    if quality == 1 then return categories.sellCommon end
    if quality == 2 then return categories.sellUncommon end
    if quality == 3 or quality == 4 then
        return not categories.excludeRareEpic
    end
    return false
end

local function BindBlocksSell(quality, bindStatus)
    if bindStatus == "bound" then
        if categories.neverSellSoulbound then return true end
        if quality == 4 and categories.neverSellSoulboundEpic then return true end
    end
    if bindStatus == "boe" and categories.neverSellBoE then return true end
    return false
end

-- context (optional): bag, slot, stackCount, bindStatus, getBindStatus(bag, slot)
function EbonBuilds.AutoSell.ShouldSell(link, getItemInfo, context)
    if not link then return false end
    getItemInfo = getItemInfo or GetItemInfo
    context = context or {}
    local name, _, quality, itemLevel, _, itemType, _, _, equipLoc, _, sellPrice = getItemInfo(link)
    if not name then return false end
    if sellPrice and sellPrice > 0 then return false end
    if not QualityAllowed(quality) then return false end
    if categories.excludeTradeGoods and itemType == AuctionItemClass(AUCTION_CLASS_TRADE_GOODS, "Trade Goods") then
        return false
    end
    if categories.excludeRecipes and itemType == AuctionItemClass(AUCTION_CLASS_RECIPE, "Recipe") then
        return false
    end
    if EbonBuilds.AutoSell.IsProtected(link, name) then return false end
    if EbonBuilds.AffixItemScan.IsProtectedFromSelling(name) then return false end
    if options.maxItemLevel > 0 and itemLevel and itemLevel > options.maxItemLevel then return false end
    local stackCount = context.stackCount
    if stackCount and stackCount < options.minStackCount then return false end
    local bindStatus = context.bindStatus
    if bindStatus == nil and context.bag and context.slot then
        local getBind = context.getBindStatus or GetBindStatus
        bindStatus = getBind(context.bag, context.slot)
    end
    if bindStatus and BindBlocksSell(quality, bindStatus) then return false end
    if IsGearUpgrade(equipLoc, link) then return false end
    return true
end

function EbonBuilds.AutoSell.CountEligible(scanBag)
    scanBag = scanBag or function(bag, slot)
        local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
        if not link then return false end
        local _, count = GetContainerItemInfo and GetContainerItemInfo(bag, slot)
        return EbonBuilds.AutoSell.ShouldSell(link, GetItemInfo, {
            bag = bag, slot = slot, stackCount = count or 1,
        })
    end
    local total = 0
    for bag = 0, 4 do
        local slots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            if scanBag(bag, slot) then total = total + 1 end
        end
    end
    return total
end

local sellQueue = EbonBuilds.RingBuffer.New(400)
local sellTicker = false
local SELL_INTERVAL = 0.3

local function StopSellTicker()
    sellTicker = false
    EbonBuilds.Scheduler.Cancel("autoSell.tick")
    EbonBuilds.RingBuffer.Clear(sellQueue)
end

local function EnsureSellTicker()
    if sellTicker then return end
    sellTicker = true
    EbonBuilds.Scheduler.Every("autoSell.tick", SELL_INTERVAL, function()
        if EbonBuilds.RingBuffer.Count(sellQueue) == 0 or not MerchantFrame or not MerchantFrame:IsShown() then
            StopSellTicker()
            return false
        end
        local next_ = EbonBuilds.RingBuffer.PopOldest(sellQueue)
        if next_ then
            local link = GetContainerItemLink(next_.bag, next_.slot)
            local _, count = GetContainerItemInfo and GetContainerItemInfo(next_.bag, next_.slot)
            if link and EbonBuilds.AutoSell.ShouldSell(link, GetItemInfo, {
                bag = next_.bag, slot = next_.slot, stackCount = count or 1,
            }) then
                UseContainerItem(next_.bag, next_.slot)
            end
        end
        return SELL_INTERVAL
    end, EbonBuilds.Scheduler.INTERACTIVE, true, "AutoSell")
end

local function SellBags()
    if not enabled then return end
    EbonBuilds.RingBuffer.Clear(sellQueue)
    local eligible = 0
    for bag = 0, 4 do
        local slots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, count = GetContainerItemInfo and GetContainerItemInfo(bag, slot)
                local context = { bag = bag, slot = slot, stackCount = count or 1 }
                if EbonBuilds.AutoSell.ShouldSell(link, GetItemInfo, context) then
                    eligible = eligible + 1
                    if not categories.dryRun then
                        EbonBuilds.RingBuffer.Append(sellQueue, { bag = bag, slot = slot })
                    end
                end
            end
        end
    end
    if categories.dryRun then
        if eligible > 0 and EbonBuilds.Toast and EbonBuilds.Toast.Show then
            local msg = L["Auto-sell preview: %d eligible item(s) (vendor only, nothing sold)."]
            EbonBuilds.Toast.Show(string.format(msg, eligible))
        end
        return
    end
    if EbonBuilds.RingBuffer.Count(sellQueue) > 0 then
        EnsureSellTicker()
    end
end

------------------------------------------------------------------------
-- Keep-list management window
------------------------------------------------------------------------

local keepListWindow, keepListRows, keepListInput

local function RefreshKeepListWindow()
    if not keepListWindow then return end
    local names = EbonBuilds.AutoSell.GetKeepList()
    for i, row in ipairs(keepListRows) do
        local name = names[i]
        if name then
            row.label:SetText(name)
            row:Show()
        else
            row:Hide()
        end
    end
    if #names == 0 then keepListWindow._emptyState:Show() else keepListWindow._emptyState:Hide() end
end

local function BuildKeepListRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(row, "AutoSell.KeepListRow")
    end
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * 24)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    EbonBuilds.Theme.ApplyCard(row)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", row, "LEFT", 8, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -28, 0)
    label:SetJustifyH("LEFT")
    row.label = label

    local remove = CreateFrame("Button", nil, row)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(remove, "AutoSell.KeepListRowRemove")
    end
    remove:SetSize(18, 18)
    remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    local x = remove:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    x:SetPoint("CENTER")
    x:SetText("x")
    x:SetTextColor(0.72, 0.72, 0.76)
    remove:SetScript("OnEnter", function() x:SetTextColor(1, 0.3, 0.3) end)
    remove:SetScript("OnLeave", function() x:SetTextColor(0.72, 0.72, 0.76) end)
    remove:SetScript("OnClick", function()
        EbonBuilds.AutoSell.RemoveKeepEntry(row.label:GetText())
        RefreshKeepListWindow()
    end)

    return row
end

local function BuildKeepListWindow()
    local T = EbonBuilds.Theme
    local window = CreateFrame("Frame", "EbonBuildsAutoSellKeepListWindow", UIParent)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(window, "AutoSell.KeepListWindow")
    end
    window:SetSize(360, 420)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    T.ApplyWindow(window)
    window:Hide()

    local drag = CreateFrame("Frame", nil, window)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(drag, "AutoSell.KeepListWindowDrag")
    end
    drag:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", window, "TOPRIGHT", -30, 0)
    drag:SetHeight(30)
    drag:EnableMouse(true)
    drag:SetScript("OnMouseDown", function() window:StartMoving() end)
    drag:SetScript("OnMouseUp", function() window:StopMovingOrSizing() end)

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -10)
    title:SetText(L["Auto-Sell Keep List"])

    T.CreateCloseButton(window)

    local sub = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetPoint("RIGHT", window, "RIGHT", -12, 0)
    sub:SetJustifyH("LEFT")
    sub:SetText(L["Items here are never auto-sold, even if they'd otherwise be eligible. Use exact names, #itemIDs, or * patterns."])

    local inputWrap = CreateFrame("Frame", nil, window)
    inputWrap:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -10)
    inputWrap:SetPoint("RIGHT", window, "RIGHT", -12, 0)
    inputWrap:SetHeight(24)
    T.ApplyInput(inputWrap)

    keepListInput = CreateFrame("EditBox", nil, inputWrap)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(keepListInput, "AutoSell.KeepListInput")
    end
    keepListInput:SetPoint("TOPLEFT", inputWrap, "TOPLEFT", 7, -3)
    keepListInput:SetPoint("BOTTOMRIGHT", inputWrap, "BOTTOMRIGHT", -7, 3)
    keepListInput:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    keepListInput:SetTextColor(1, 1, 1, 1)
    keepListInput:SetAutoFocus(false)
    keepListInput:SetMaxLetters(80)
    T.WireEditBox(keepListInput, inputWrap)

    local placeholder = inputWrap:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", keepListInput, "LEFT", 0, 0)
    placeholder:SetText(L["Name, #12345, or *pattern*..."])
    placeholder:SetTextColor(unpack(T.TEXT_MUTED))
    keepListInput:HookScript("OnTextChanged", function(self)
        if self:GetText() == "" then placeholder:Show() else placeholder:Hide() end
    end)

    local function AddCurrentInput()
        local text = strtrim(keepListInput:GetText() or "")
        if text == "" then return end
        if EbonBuilds.AutoSell.AddKeepEntry(text) then
            keepListInput:SetText("")
            RefreshKeepListWindow()
        end
    end
    keepListInput:SetScript("OnEnterPressed", AddCurrentInput)
    keepListInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local addButton = T.CreateButton(window)
    addButton:SetSize(60, 24)
    addButton:SetPoint("LEFT", inputWrap, "RIGHT", 6, 0)
    addButton:SetText(L["Add"])
    addButton:SetScript("OnClick", AddCurrentInput)
    inputWrap:SetPoint("RIGHT", window, "RIGHT", -78, 0)

    local listScroll = CreateFrame("ScrollFrame", nil, window)
    if EbonBuilds.Debug and EbonBuilds.Debug.ProtectScript then
        EbonBuilds.Debug.ProtectScript(listScroll, "AutoSell.KeepListScroll")
    end
    listScroll:SetPoint("TOPLEFT", inputWrap, "BOTTOMLEFT", 0, -10)
    listScroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -22, 14)

    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetWidth(310)
    listChild:SetHeight(1)
    listScroll:SetScrollChild(listChild)

    local scrollBar = T.CreateScrollBar(listScroll)
    scrollBar:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", -2, -4)
    scrollBar:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMRIGHT", -2, 4)
    T.BindScrollWheel(listScroll, scrollBar, 24)

    local emptyState = listChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyState:SetPoint("TOPLEFT", listChild, "TOPLEFT", 4, -6)
    emptyState:SetText(L["No items on the keep-list yet."])
    window._emptyState = emptyState

    keepListRows = {}
    local MAX_ROWS = 60
    for i = 1, MAX_ROWS do
        local row = BuildKeepListRow(listChild, i)
        row:Hide()
        keepListRows[i] = row
    end
    listChild:SetHeight(MAX_ROWS * 24)

    window:SetScript("OnShow", RefreshKeepListWindow)
    keepListWindow = window
    return window
end

function EbonBuilds.AutoSell.ShowKeepListWindow()
    if not (EbonBuilds.Theme and EbonBuilds.Theme.ApplyWindow) then return end
    if not keepListWindow then BuildKeepListWindow() end
    keepListWindow:Show()
end

function EbonBuilds.AutoSell.Init()
    if EbonBuilds.Database and EbonBuilds.Database.GetCharacterPreference then
        enabled = EbonBuilds.Database.GetCharacterPreference("autoSellJunkEnabled")
    elseif EbonBuildsCharDB.autoSellJunkEnabled ~= nil then
        enabled = EbonBuildsCharDB.autoSellJunkEnabled == true
    end
    LoadCategories()
    local onMerchantEvent = EbonBuilds.ErrorLog.Protect("AutoSell", function(event)
        if event == "MERCHANT_SHOW" then
            SellBags()
        else
            EbonBuilds.RingBuffer.Clear(sellQueue)
            if sellTicker then StopSellTicker() end
        end
    end)
    EbonBuilds.WoWEvents.On("MERCHANT_SHOW", onMerchantEvent, "AutoSell")
    EbonBuilds.WoWEvents.On("MERCHANT_CLOSED", onMerchantEvent, "AutoSell")
end

if EbonBuilds.Debug and EbonBuilds.Debug.RegisterTest then
    local function StubInfo(quality, itemType, equipLoc, sellPrice, itemLevel)
        return function(link)
            return link, link, quality, itemLevel or 1, 1, itemType, "", 1, equipLoc, "", sellPrice
        end
    end

    EbonBuilds.Debug.RegisterTest("AutoSell: keep-list overrides an otherwise-sellable item", function()
        EbonBuilds.AutoSell.AddToKeepList("Ruined Pelt")
        local ok, err = pcall(function()
            local should = EbonBuilds.AutoSell.ShouldSell("Ruined Pelt", StubInfo(0, "Junk", "", 0))
            if should then error("kept item was still marked sellable") end
            EbonBuilds.AutoSell.RemoveFromKeepList("Ruined Pelt")
            local afterRemove = EbonBuilds.AutoSell.ShouldSell("Ruined Pelt", StubInfo(0, "Junk", "", 0))
            if not afterRemove then error("item stayed protected after being removed from the keep-list") end
        end)
        EbonBuilds.AutoSell.RemoveFromKeepList("Ruined Pelt")
        if not ok then error(err) end
    end)

    EbonBuilds.Debug.RegisterTest("AutoSell: category filters survive broken GetAuctionItemClasses", function()
        local previousGetAuctionItemClasses = GetAuctionItemClasses
        GetAuctionItemClasses = function()
            error("broken auction class API")
        end
        local ok, err = pcall(function()
            local tradeGood = EbonBuilds.AutoSell.ShouldSell(
                "Some Ore", StubInfo(1, "Trade Goods", "", 0))
            if tradeGood then
                error("Trade Goods item was sellable when GetAuctionItemClasses errors")
            end
        end)
        GetAuctionItemClasses = previousGetAuctionItemClasses
        if not ok then error(err) end
    end)
end
