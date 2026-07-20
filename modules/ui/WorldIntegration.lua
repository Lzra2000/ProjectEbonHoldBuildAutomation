-- EbonBuilds: modules/ui/WorldIntegration.lua
-- Responsibility: the two places EbonBuilds shows itself in the world
-- rather than in its own windows. (1) Unit tooltips: hovering a player
-- your client has seen addon traffic from gets one line saying they run
-- EbonBuilds, with their announced version when known. (2) The world
-- map: while a zone with known tome sources is open, a compact overlay
-- lists every tome dropping there and who drops it -- the atlas data is
-- mob-and-zone keyed (no coordinates exist), so an honest zone panel
-- beats fake pin positions.

EbonBuilds.WorldIntegration = {}

------------------------------------------------------------------------
-- (1) Player tooltip: "runs EbonBuilds"
------------------------------------------------------------------------

local function AugmentUnitTooltip(tooltip)
    local _, unit = tooltip:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    if not name or name == UnitName("player") then return end
    local info = EbonBuilds.Sync and EbonBuilds.Sync.GetPeerInfo and EbonBuilds.Sync.GetPeerInfo(name)
    if not info then return end
    if info.version then
        tooltip:AddLine("EbonBuilds " .. info.version, 0.36, 0.77, 0.64)
    else
        tooltip:AddLine("EbonBuilds user", 0.36, 0.77, 0.64)
    end
    tooltip:Show()
end
EbonBuilds.WorldIntegration._AugmentUnitTooltipForTests = AugmentUnitTooltip

------------------------------------------------------------------------
-- (2) World map: tomes of the open zone
------------------------------------------------------------------------

local mapPanel, mapLines

local function EnsureMapPanel()
    if mapPanel then return end
    local Theme = EbonBuilds.Theme
    mapPanel = CreateFrame("Frame", "EbonBuildsMapTomes", WorldMapFrame)
    mapPanel:SetFrameStrata("FULLSCREEN")
    mapPanel:SetSize(240, 60)
    mapPanel:SetPoint("TOPRIGHT", WorldMapDetailFrame or WorldMapFrame, "TOPRIGHT", -8, -8)
    if Theme and Theme.ApplyPanel then Theme.ApplyPanel(mapPanel) else
        mapPanel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
        mapPanel:SetBackdropColor(0, 0, 0, 0.75)
    end
    local title = mapPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", mapPanel, "TOPLEFT", 8, -6)
    title:SetText("Tomes in this zone")
    mapPanel.title = title
    mapLines = mapPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mapLines:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    mapLines:SetJustifyH("LEFT")
    mapLines:SetWidth(224)
    mapPanel:Hide()
end

-- Pure data step, injectable for tests: zone name -> sorted display
-- lines ("Tome of X -- Ignis (12)"), built on TomeAtlas.ListByZone().
function EbonBuilds.WorldIntegration.BuildZoneTomeLines(zoneName, listByZone)
    listByZone = listByZone or (EbonBuilds.TomeAtlas and EbonBuilds.TomeAtlas.ListByZone)
    if not zoneName or not listByZone then return {} end
    local byZone = listByZone()
    local entry
    for _, z in ipairs(byZone or {}) do
        if z.zone == zoneName then
            entry = z
            break
        end
    end
    if not entry then return {} end
    local lines = {}
    for _, t in pairs(entry.tomes) do
        local topMob, topCount = "?", -1
        for _, m in ipairs(t.mobs or {}) do
            if (m.count or 0) > topCount then topMob, topCount = m.mob, m.count or 0 end
        end
        local extra = #(t.mobs or {}) > 1 and (" +%d"):format(#t.mobs - 1) or ""
        lines[#lines + 1] = string.format("%s -- %s (%d)%s", t.name or ("Tome " .. tostring(t.itemId)), topMob, t.total or 0, extra)
    end
    table.sort(lines)
    return lines
end

local function RefreshMapPanel()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    EnsureMapPanel()
    -- Displayed zone's localized name (3.3.5a): resolve via the map
    -- zone index; fall back to the player's current zone text when the
    -- map shows a continent view.
    local zoneName
    if GetMapZones and GetCurrentMapContinent and GetCurrentMapZone then
        local cont, zone = GetCurrentMapContinent(), GetCurrentMapZone()
        if cont and cont > 0 and zone and zone > 0 then
            local zones = { GetMapZones(cont) }
            zoneName = zones[zone]
        end
    end
    if not zoneName and GetZoneText then zoneName = GetZoneText() end
    local lines = EbonBuilds.WorldIntegration.BuildZoneTomeLines(zoneName)
    if #lines == 0 then
        mapPanel:Hide()
        return
    end
    local shown = {}
    for i = 1, math.min(#lines, 12) do shown[i] = lines[i] end
    if #lines > 12 then shown[#shown + 1] = ("... and %d more (Tome Atlas)"):format(#lines - 12) end
    mapLines:SetText(table.concat(shown, "\n"))
    mapPanel:SetHeight(30 + #shown * 13)
    mapPanel:Show()
end

function EbonBuilds.WorldIntegration.Init()
    -- Tooltip hook, error-isolated like GearTooltip's.
    local function Safe(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok and EbonBuilds.ErrorLog and EbonBuilds.ErrorLog.Protect then
                EbonBuilds.ErrorLog.Protect("WorldIntegration", function() error(err, 0) end)()
            end
        end
    end
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", Safe(AugmentUnitTooltip))
    end
    -- Map refresh on show and zone change.
    if WorldMapFrame and WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnShow", Safe(RefreshMapPanel))
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("WORLD_MAP_UPDATE")
    f:SetScript("OnEvent", Safe(RefreshMapPanel))
end
