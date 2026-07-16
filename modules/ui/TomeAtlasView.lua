-- EbonBuilds: modules/ui/TomeAtlasView.lua
-- AtlasLoot-style community drop browser for echo tomes: which mob drops
-- which tome, in which zone, with community-observed counts. Data comes
-- from core/TomeAtlas.lua and is shared between players via Sync.

EbonBuilds.TomeAtlasView = {}

local ROW_HEIGHT   = 34
local VISIBLE_ROWS = 11

local viewFrame, scrollFrame, scrollChild, scrollBar
local searchBox, filterBtn, syncBtn, countLabel, emptyText, zoneSummary
local rows = {}
local state = { text = "", missingOnly = false }

------------------------------------------------------------------------
-- Owned detection: a tome is "owned" when its taught echo is in the
-- spellbook's Echoes tab (same normalization the Missing tab uses).
------------------------------------------------------------------------

local function BuildOwnedSet()
    local owned = {}
    local norm = EbonBuilds.BuildOverview and EbonBuilds.BuildOverview._NormalizeEchoName
    if not norm then return owned, false end
    local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    local found = false
    for tabIdx = 1, numTabs do
        local tabName, _, offset, numSpells = GetSpellTabInfo(tabIdx)
        if tabName == "Echoes" then
            found = true
            for slot = offset + 1, offset + numSpells do
                local link = GetSpellLink(slot, "spell")
                local name = link and link:match("%[(.-)%]")
                if name then owned[norm(name)] = true end
            end
            break
        end
    end
    return owned, found
end

local function IsOwned(tomeName, ownedSet)
    local norm = EbonBuilds.BuildOverview and EbonBuilds.BuildOverview._NormalizeEchoName
    if not norm then return false end
    -- NormalizeEchoName strips tome prefixes AND quality suffixes, so
    -- "Tome of Brittle Forging - Rare" maps onto the owned echo name.
    return ownedSet[norm(tomeName)] or false
end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------

local function BuildFilteredList()
    local all = EbonBuilds.TomeAtlas.List()
    local ownedSet, spellbookReady = BuildOwnedSet()
    local out = {}
    for _, entry in ipairs(all) do
        local owned = spellbookReady and IsOwned(entry.name, ownedSet)
        local matchesText = state.text == ""
            or strlower(entry.name or ""):find(state.text, 1, true)
        if not matchesText then
            -- also match mob or zone names
            for _, s in ipairs(entry.sources) do
                if strlower(s.mob or ""):find(state.text, 1, true)
                or strlower(s.zone or ""):find(state.text, 1, true) then
                    matchesText = true
                    break
                end
            end
        end
        if matchesText and (not state.missingOnly or not owned) then
            out[#out + 1] = { entry = entry, owned = owned }
        end
    end
    return out
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT", parent, "LEFT", 0, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints(row)
    stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    stripe:SetVertexColor(1, 1, 1, 0.03)
    row._stripe = stripe

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -4)
    name:SetJustifyH("LEFT")
    name:SetWidth(250)
    row._name = name

    local ownedTag = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ownedTag:SetPoint("TOPLEFT", name, "TOPRIGHT", 6, 0)
    row._owned = ownedTag

    local src = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    src:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 4)
    src:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    src:SetJustifyH("LEFT")
    src:SetTextColor(0.75, 0.75, 0.75, 1)
    row._sources = src

    -- Hover: item tooltip for the tome (icon, quality, description if the
    -- client has it cached) plus the FULL drop-source list -- the on-row
    -- text truncates to 3 sources, the tooltip is where "+N more" lives.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        local e = self._entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local shownItemTooltip = false
        if e.itemId then
            shownItemTooltip = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. e.itemId)
        end
        if not shownItemTooltip then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(e.name or "?", 1, 0.82, 0)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(self._isOwned and "|cff1eff00Already collected|r" or "|cffff4444Missing|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffd100Known sources:|r")
        if e.sources and #e.sources > 0 then
            for _, s in ipairs(e.sources) do
                GameTooltip:AddDoubleLine(
                    (s.mob or "?") .. "  |cff888888(" .. (s.zone or "?") .. ")|r",
                    "x" .. (s.count or 1),
                    1, 1, 1, 1, 0.82, 0)
            end
        else
            GameTooltip:AddLine("No drop data yet -- be the first to loot one!", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

local function SourceText(sources)
    if #sources == 0 then return "|cff888888No drop data yet|r" end
    local parts = {}
    for i = 1, math.min(3, #sources) do
        local s = sources[i]
        parts[#parts + 1] = string.format("%s |cff888888-|r %s |cffffd100(x%d)|r",
            s.mob or "?", s.zone or "?", s.count or 1)
    end
    local txt = table.concat(parts, "|cff888888  |  |r")
    if #sources > 3 then
        txt = txt .. string.format(" |cff888888(+%d more)|r", #sources - 3)
    end
    return txt
end

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------

local offset = 0
local filtered = {}

-- "Best farming" line: zones ranked by how many DISTINCT missing tomes
-- have a known source there. Independent of the search filter -- this is
-- the "where should I fly" answer for collectors.
local function ZoneSummaryText()
    local all = EbonBuilds.TomeAtlas.List()
    local ownedSet, spellbookReady = BuildOwnedSet()
    local zoneCounts = {}
    for _, entry in ipairs(all) do
        local owned = spellbookReady and IsOwned(entry.name, ownedSet)
        if not owned then
            local seen = {}
            for _, s in ipairs(entry.sources) do
                local z = s.zone or "?"
                if z ~= "?" and not seen[z] then
                    seen[z] = true
                    zoneCounts[z] = (zoneCounts[z] or 0) + 1
                end
            end
        end
    end
    local ranked = {}
    for z, n in pairs(zoneCounts) do ranked[#ranked + 1] = { z = z, n = n } end
    if #ranked == 0 then return "" end
    table.sort(ranked, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.z < b.z
    end)
    local parts = {}
    for i = 1, math.min(3, #ranked) do
        parts[#parts + 1] = string.format("%s |cffffd100(%d)|r", ranked[i].z, ranked[i].n)
    end
    return "|cff1eff00Best farming:|r " .. table.concat(parts, "|cff888888,|r ")
end

local function Render()
    filtered = BuildFilteredList()
    if zoneSummary then zoneSummary:SetText(ZoneSummaryText()) end

    local maxOffset = math.max(0, #filtered - VISIBLE_ROWS)
    if offset > maxOffset then offset = maxOffset end
    scrollBar:SetMinMaxValues(0, maxOffset)

    for i = 1, VISIBLE_ROWS do
        local row = rows[i]
        local item = filtered[offset + i]
        if item then
            local e = item.entry
            row._entry = e
            row._isOwned = item.owned
            row._name:SetText(e.name or "?")
            if item.owned then
                row._name:SetTextColor(0.55, 0.55, 0.55, 1)
                row._owned:SetText("|cff1eff00(collected)|r")
            else
                row._name:SetTextColor(1, 0.82, 0, 1)
                row._owned:SetText("")
            end
            row._sources:SetText(SourceText(e.sources))
            row._stripe:SetVertexColor(1, 1, 1, (offset + i) % 2 == 0 and 0.05 or 0.02)
            row:Show()
        else
            row._entry = nil
            row:Hide()
        end
    end

    local total = #EbonBuilds.TomeAtlas.List()
    countLabel:SetText(string.format("%d shown / %d known", #filtered, total))

    if #filtered == 0 then
        if total == 0 then
            emptyText:SetText("No community drop data yet.\n\nTomes you loot are recorded automatically (mob + zone)\nand shared with other EbonBuilds users. Data from other\nplayers arrives when anyone syncs (Public Builds > Reload).")
        else
            emptyText:SetText("No tome matches your filter.")
        end
        emptyText:Show()
    else
        emptyText:Hide()
    end
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    title:SetText("|cffffd100Tome Atlas|r")
    EbonBuilds.Theme.AddHeaderRule(f, title, 540)

    -- Every element below is anchored to FIXED offsets from f, not chained
    -- to the previous element's dynamic (wrapped-text-dependent) height.
    -- Chaining "X below the bottom of Y" broke when Y's actual rendered
    -- height didn't match what the layout assumed (long subtitle text
    -- wrapping to 2 lines pushed everything below it down by a variable
    -- amount, which is what caused the search row to overlap the summary
    -- line). Fixed offsets can't drift.
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -38)
    sub:SetWidth(520)
    sub:SetHeight(26) -- reserves room for up to 2 wrapped lines regardless
    sub:SetJustifyH("LEFT")
    sub:SetJustifyV("TOP")
    sub:SetText("Community drop locations for echo tomes -- loot one to share its source.")

    zoneSummary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneSummary:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -74)
    zoneSummary:SetWidth(520)
    zoneSummary:SetHeight(14)
    zoneSummary:SetJustifyH("LEFT")

    -- Row 1: search box, full width.
    searchBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    searchBox:SetHeight(20)
    searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -96)
    searchBox:SetPoint("RIGHT", f, "RIGHT", -38, 0)
    searchBox:SetAutoFocus(false)
    local PLACEHOLDER = "Search tome, mob, or zone..."
    local function ShowPlaceholder(self)
        if self:GetText() == "" then
            self:SetTextColor(0.5, 0.5, 0.5, 1)
            self:SetText(PLACEHOLDER)
            self._isPlaceholder = true
        end
    end
    local function HidePlaceholder(self)
        if self._isPlaceholder then
            self:SetText("")
            self:SetTextColor(1, 1, 1, 1)
            self._isPlaceholder = false
        end
    end
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        state.text = self._isPlaceholder and "" or strlower(self:GetText() or "")
        offset = 0
        Render()
    end)
    searchBox:SetScript("OnEditFocusGained", HidePlaceholder)
    searchBox:SetScript("OnEditFocusLost", function(self)
        self:SetTextColor(1, 1, 1, 1)
        ShowPlaceholder(self)
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ShowPlaceholder(searchBox)

    -- Row 2: everything else -- count on the left, actions on the right.
    -- controlsRow exists purely as an anchor: TOPLEFT (from the search row)
    -- + explicit height fixes its vertical position; RIGHT stretches it to
    -- the frame's right edge. Every widget below anchors to ITS edges, so
    -- nothing can silently drift out of alignment the way the old
    -- independently-positioned widgets did (see the 2.5 layout bug).
    local controlsRow = CreateFrame("Frame", nil, f)
    controlsRow:SetHeight(20)
    controlsRow:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -10)
    controlsRow:SetPoint("RIGHT", f, "RIGHT", -14, 0)

    syncBtn = EbonBuilds.Theme.CreateButton(f)
    syncBtn:SetSize(70, 20)
    syncBtn:SetPoint("TOPRIGHT", controlsRow, "TOPRIGHT", 0, 0)
    syncBtn:SetText("Sync")
    syncBtn:SetScript("OnClick", function()
        EbonBuilds.Sync.RequestSync()
    end)
    syncBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Sync Tome Atlas", 1, 1, 1)
        GameTooltip:AddLine("Requests drop data from other online EbonBuilds users.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    syncBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    syncBtn:SetScript("OnUpdate", function(self, dt)
        self._throttle = (self._throttle or 0) + dt
        if self._throttle < 0.25 then return end
        self._throttle = 0
        local remaining = EbonBuilds.Sync.GetCooldownRemaining and EbonBuilds.Sync.GetCooldownRemaining() or 0
        if remaining ~= self._lastRemaining then
            self._lastRemaining = remaining
            if remaining > 0 then
                self:Disable()
                self:SetText(remaining .. "s")
            else
                self:Enable()
                self:SetText("Sync")
            end
        end
    end)

    filterBtn = EbonBuilds.Theme.CreateButton(f)
    filterBtn:SetSize(130, 20)
    filterBtn:SetPoint("RIGHT", syncBtn, "LEFT", -8, 0)
    filterBtn:SetText("Show: All")
    filterBtn:SetScript("OnClick", function(self)
        state.missingOnly = not state.missingOnly
        self:SetText(state.missingOnly and "Show: Missing only" or "Show: All")
        offset = 0
        Render()
    end)

    countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countLabel:SetPoint("LEFT", controlsRow, "LEFT", 0, 0)
    countLabel:SetPoint("TOP", controlsRow, "TOP", 0, -3)

    -- Rows container: anchored to controlsRow's bottom, not a magic number
    -- from the top of the frame -- header height can change again later
    -- without breaking this.
    scrollChild = CreateFrame("Frame", nil, f)
    scrollChild:SetPoint("TOPLEFT", controlsRow, "BOTTOMLEFT", 4, -14)
    scrollChild:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 12)

    for i = 1, VISIBLE_ROWS do
        local row = CreateRow(scrollChild)
        row:SetPoint("TOP", scrollChild, "TOP", 0, -(i - 1) * ROW_HEIGHT)
        rows[i] = row
    end

    emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetPoint("CENTER", scrollChild, "CENTER", 0, 20)
    emptyText:SetJustifyH("CENTER")
    emptyText:Hide()

    scrollBar = CreateFrame("Slider", nil, f, "UIPanelScrollBarTemplate")
    scrollBar:SetPoint("TOPLEFT", scrollChild, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollChild, "BOTTOMRIGHT", 6, 0)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(1)
    scrollBar:SetValue(0)
    scrollBar:SetScript("OnValueChanged", function(self, value)
        offset = math.floor(value + 0.5)
        Render()
    end)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        local minV, maxV = scrollBar:GetMinMaxValues()
        local v = scrollBar:GetValue() - delta
        scrollBar:SetValue(math.max(minV, math.min(maxV, v)))
    end)

    return f
end

------------------------------------------------------------------------
-- View interface
------------------------------------------------------------------------

function EbonBuilds.TomeAtlasView.Show(parent)
    if not viewFrame then
        viewFrame = BuildViewFrame(parent)
    end
    offset = 0
    Render()
    viewFrame:Show()
    return viewFrame
end

function EbonBuilds.TomeAtlasView.Hide()
    if viewFrame then viewFrame:Hide() end
end

function EbonBuilds.TomeAtlasView.RefreshIfMounted()
    if viewFrame and viewFrame:IsShown() then
        Render()
    end
end
