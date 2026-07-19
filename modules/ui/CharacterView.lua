-- EbonBuilds: modules/ui/CharacterView.lua
-- Responsibility: the build editor's Character tab. Renders a LIVE view
-- of the equipped gear (all slots, with GearScore values), the complete
-- talent trees (every talent of every tree, skilled ranks highlighted,
-- unskilled dimmed), and the six glyph sockets -- refreshing on the
-- relevant game events while mounted. "Adopt snapshot" writes the live
-- state onto the build being edited via CharacterSnapshot.ApplyToBuild;
-- whether that persists is the editor's normal Save/Cancel decision.

EbonBuilds.CharacterView = {}

local Theme

local viewFrame, scrollFrame, scrollChild, scrollBar
local rows = {}          -- FontString pool, reused across refreshes
local rowCount = 0
local snapshotStatus, adoptBtn
local mountedContext
local eventFrame

local ROW_H = 15
local COL2_X = 210       -- second column x for gear / talent tree columns

local function AcquireRow()
    rowCount = rowCount + 1
    local fs = rows[rowCount]
    if not fs then
        fs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        rows[rowCount] = fs
    end
    fs:Show()
    return fs
end

local function PlaceRow(fs, x, y, width)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, y)
    fs:SetWidth(width or 195)
end

local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 },       [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 },    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}

local function SpecKeyForContext()
    local build = mountedContext and mountedContext.build
    if build and build.class then
        return EbonBuilds.GearScore.SpecKey(build.class, build.spec)
    end
    return nil
end

local function Render()
    if not viewFrame or not viewFrame:IsShown() then return end
    for i = 1, rowCount do rows[i]:Hide() end
    rowCount = 0

    local snap = EbonBuilds.CharacterSnapshot.Capture()
    local y = -6

    -- Section: gear, two columns, with per-item score when weights exist.
    local header = AcquireRow()
    PlaceRow(header, 4, y, 400)
    local specKey = SpecKeyForContext()
    header:SetText("Equipped gear" .. (specKey and "  (score for this build's spec)" or ""))
    header:SetTextColor(unpack(Theme.ACCENT_GOLD))
    y = y - ROW_H - 4

    local slotList = EbonBuilds.GearScore.SLOTS
    local half = math.ceil(#slotList / 2)
    local startY = y
    for i, slot in ipairs(slotList) do
        local col = i > half and 1 or 0
        local rowY = startY - ((col == 0 and (i - 1) or (i - half - 1)) * ROW_H)
        local fs = AcquireRow()
        PlaceRow(fs, 4 + col * COL2_X, rowY, COL2_X - 14)
        local item = snap.gear[slot.id]
        if item then
            local score = specKey and EbonBuilds.GearScore.ScoreItem(item.link, specKey) or nil
            fs:SetText(string.format("%s: %s%s", slot.name, item.name, score and string.format(" (%.0f)", score) or ""))
            fs:SetTextColor(unpack(QUALITY_COLORS[item.quality] or QUALITY_COLORS[1]))
        else
            fs:SetText(slot.name .. ": empty")
            fs:SetTextColor(0.45, 0.45, 0.5)
        end
    end
    y = startY - (half * ROW_H) - 10

    -- Section: full talent trees, three columns, every talent listed.
    header = AcquireRow()
    PlaceRow(header, 4, y, 400)
    header:SetText("Talents (complete trees, current character)")
    header:SetTextColor(unpack(Theme.ACCENT_GOLD))
    y = y - ROW_H - 4

    local TREE_W = 140
    local maxRows = 0
    for tab = 1, 3 do
        local tree = snap.talents[tab]
        if tree then
            local fs = AcquireRow()
            PlaceRow(fs, 4 + (tab - 1) * TREE_W, y, TREE_W - 8)
            fs:SetText(string.format("%s (%d)", tree.name, tree.points))
            fs:SetTextColor(0.9, 0.85, 0.6)
            local n = 1
            for _, t in ipairs(tree.talents) do
                local tfs = AcquireRow()
                PlaceRow(tfs, 4 + (tab - 1) * TREE_W, y - n * ROW_H, TREE_W - 8)
                tfs:SetText(string.format("%s %d/%d", t.name, t.rank, t.maxRank))
                if t.rank > 0 then
                    tfs:SetTextColor(0.36, 0.77, 0.64)
                else
                    tfs:SetTextColor(0.42, 0.42, 0.48)
                end
                n = n + 1
            end
            if n - 1 > maxRows then maxRows = n - 1 end
        end
    end
    y = y - (maxRows + 1) * ROW_H - 10

    -- Section: glyphs.
    header = AcquireRow()
    PlaceRow(header, 4, y, 400)
    header:SetText("Glyphs")
    header:SetTextColor(unpack(Theme.ACCENT_GOLD))
    y = y - ROW_H - 2
    for _, g in ipairs(snap.glyphs) do
        local fs = AcquireRow()
        PlaceRow(fs, 4, y, 400)
        local label = g.kind == "major" and "Major" or "Minor"
        if g.spellId then
            fs:SetText(string.format("%s: %s", label, g.name))
            fs:SetTextColor(0.8, 0.8, 0.9)
        else
            fs:SetText(string.format("%s: %s", label, g.enabled and "empty" or "locked"))
            fs:SetTextColor(0.45, 0.45, 0.5)
        end
        y = y - ROW_H
    end

    -- Snapshot status line: what (if anything) the build currently holds.
    local build = mountedContext and mountedContext.build
    local stored = build and build.characterSnapshot
    if snapshotStatus then
        if stored then
            snapshotStatus:SetText(string.format("Stored on this build: %s (%s)",
                EbonBuilds.CharacterSnapshot.Summarize(stored) or "?", stored.capturedAt or "?"))
            snapshotStatus:SetTextColor(0.8, 0.8, 0.9)
        else
            snapshotStatus:SetText("No snapshot stored on this build yet.")
            snapshotStatus:SetTextColor(0.62, 0.62, 0.66)
        end
    end

    local contentHeight = -y + 20
    scrollChild:SetHeight(math.max(scrollFrame:GetHeight() or 0, contentHeight))
    if scrollBar and scrollBar.SetMinMaxValues then
        scrollBar:SetMinMaxValues(0, math.max(0, contentHeight - (scrollFrame:GetHeight() or 0)))
    end
end

local function EnsureBuilt(container)
    if viewFrame then return end
    Theme = EbonBuilds.Theme
    viewFrame = CreateFrame("Frame", nil, container)

    -- Bottom bar: adopt button + status, above it the scrolling content.
    adoptBtn = Theme.CreateButton(viewFrame)
    adoptBtn:SetSize(160, 24)
    adoptBtn:SetPoint("BOTTOMLEFT", viewFrame, "BOTTOMLEFT", 4, 4)
    adoptBtn:SetText("Adopt snapshot")
    Theme.AttachTooltip(adoptBtn, "Adopt snapshot",
        "Writes the current gear, full talent trees, and glyphs onto this build. Persisted by Save, discarded by Cancel, like every other edit.")
    adoptBtn:SetScript("OnClick", function()
        local build = mountedContext and mountedContext.build
        if not build then return end
        EbonBuilds.CharacterSnapshot.ApplyToBuild(build)
        if EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.MarkDirty then EbonBuilds.BuildTabs.MarkDirty() end
        Render()
    end)

    snapshotStatus = viewFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    snapshotStatus:SetPoint("LEFT", adoptBtn, "RIGHT", 10, 0)
    snapshotStatus:SetJustifyH("LEFT")
    snapshotStatus:SetWidth(360)

    scrollFrame = CreateFrame("ScrollFrame", nil, viewFrame)
    scrollFrame:SetPoint("TOPLEFT", viewFrame, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", viewFrame, "BOTTOMRIGHT", -18, 34)
    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(1)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetPoint("TOPLEFT")

    scrollBar = Theme.CreateScrollBar(viewFrame, 12)
    scrollBar:SetPoint("TOPRIGHT", viewFrame, "TOPRIGHT", -2, -2)
    scrollBar:SetPoint("BOTTOMRIGHT", viewFrame, "BOTTOMRIGHT", -2, 36)
    Theme.BindScrollWheel(scrollFrame, scrollBar, 32, scrollChild)

    -- Live refresh while mounted: gear, talent points, and glyph events.
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
    eventFrame:RegisterEvent("GLYPH_ADDED")
    eventFrame:RegisterEvent("GLYPH_REMOVED")
    eventFrame:RegisterEvent("GLYPH_UPDATED")
    eventFrame:SetScript("OnEvent", function()
        if viewFrame and viewFrame:IsShown() then Render() end
    end)
end

function EbonBuilds.CharacterView.Mount(container, context)
    EnsureBuilt(container)
    mountedContext = context
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)
    viewFrame:Show()
    Render()
end

function EbonBuilds.CharacterView.Unmount()
    if viewFrame then viewFrame:Hide() end
end

-- Test hooks: render into stubs and trigger the adopt path without a click.
EbonBuilds.CharacterView._RenderForTests = Render
EbonBuilds.CharacterView._AdoptForTests = function()
    if adoptBtn then adoptBtn:GetScript("OnClick")() end
end
