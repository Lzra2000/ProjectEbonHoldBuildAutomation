-- EbonBuilds: modules/build/CharacterSnapshot.lua
-- Responsibility: capturing the character's current state -- equipped
-- gear per slot, all three talent trees in full (every talent, not just
-- skilled ones), and glyph sockets -- and writing that snapshot onto a
-- build. The Character tab renders the live capture; "Adopt snapshot"
-- stores it on the build being edited, where the normal Save/Cancel
-- draft flow decides whether it persists.

EbonBuilds.CharacterSnapshot = {}

local M = EbonBuilds.CharacterSnapshot

-- WotLK 3.3.5a glyph socket layout: 1/4/6 are major, 2/3/5 are minor.
local GLYPH_SOCKET_TYPE = { [1] = "major", [2] = "minor", [3] = "minor", [4] = "major", [5] = "minor", [6] = "major" }
M.GLYPH_SOCKET_TYPE = GLYPH_SOCKET_TYPE

-- All getters injectable for tests, mirroring GearScore's pattern.
function M.CaptureGear(getInvLink, getInfo)
    getInvLink = getInvLink or function(slotId) return GetInventoryItemLink("player", slotId) end
    getInfo = getInfo or GetItemInfo
    local gear = {}
    for _, slot in ipairs(EbonBuilds.GearScore.SLOTS) do
        local link = getInvLink(slot.id)
        if link then
            local name, _, quality = getInfo(link)
            gear[slot.id] = { name = name or link, quality = quality or 1, link = link }
        end
    end
    return gear
end

-- Every talent in every tree, skilled or not -- rank 0 entries included
-- deliberately so the Character tab can render the COMPLETE tree, and a
-- stored snapshot can be diffed tier-by-tier later.
function M.CaptureTalents(getNumTabs, getTabInfo, getTalentInfo, getNumTalents)
    getNumTabs = getNumTabs or GetNumTalentTabs
    getTabInfo = getTabInfo or GetTalentTabInfo
    getTalentInfo = getTalentInfo or GetTalentInfo
    getNumTalents = getNumTalents or GetNumTalents
    local trees = {}
    for tab = 1, (getNumTabs() or 0) do
        local tabName, _, pointsSpent = getTabInfo(tab)
        local tree = { name = tabName or ("Tree " .. tab), points = pointsSpent or 0, talents = {} }
        for index = 1, (getNumTalents(tab) or 0) do
            local name, _, tier, column, rank, maxRank = getTalentInfo(tab, index)
            if name then
                tree.talents[#tree.talents + 1] = {
                    name = name, tier = tier or 1, column = column or 1,
                    rank = rank or 0, maxRank = maxRank or 0,
                }
            end
        end
        -- Stable visual order: by tree position, not API index.
        table.sort(tree.talents, function(a, b)
            if a.tier ~= b.tier then return a.tier < b.tier end
            return a.column < b.column
        end)
        trees[tab] = tree
    end
    return trees
end

function M.CaptureGlyphs(getNumSockets, getSocketInfo, getSpellInfo)
    getNumSockets = getNumSockets or GetNumGlyphSockets
    getSocketInfo = getSocketInfo or GetGlyphSocketInfo
    getSpellInfo = getSpellInfo or GetSpellInfo
    local glyphs = {}
    for socket = 1, (getNumSockets and getNumSockets() or 6) do
        local enabled, _, glyphSpellId = getSocketInfo(socket)
        local entry = { socket = socket, kind = GLYPH_SOCKET_TYPE[socket] or "minor", enabled = enabled and true or false }
        if glyphSpellId then
            entry.spellId = glyphSpellId
            entry.name = getSpellInfo(glyphSpellId) or ("Glyph " .. glyphSpellId)
        end
        glyphs[socket] = entry
    end
    return glyphs
end

function M.Capture(getters)
    getters = getters or {}
    return {
        capturedAt = date and date("%Y-%m-%d %H:%M:%S") or "",
        gear = M.CaptureGear(getters.getInvLink, getters.getInfo),
        talents = M.CaptureTalents(getters.getNumTabs, getters.getTabInfo, getters.getTalentInfo, getters.getNumTalents),
        glyphs = M.CaptureGlyphs(getters.getNumSockets, getters.getSocketInfo, getters.getSpellInfo),
    }
end

-- Writes the capture onto the build object handed in (the edit context's
-- draft build). Persistence stays with the editor's Save/Cancel flow --
-- this function never touches EbonBuildsDB itself.
function M.ApplyToBuild(build, getters)
    if not build then return nil end
    build.characterSnapshot = M.Capture(getters)
    return build.characterSnapshot
end

-- Compact one-line summary for the tab ("31/5/5 · 4 glyphs · 17 items"),
-- reusing the classic points notation.
function M.Summarize(snapshot)
    if not snapshot then return nil end
    local points = {}
    for tab = 1, 3 do
        points[#points + 1] = tostring((snapshot.talents and snapshot.talents[tab] and snapshot.talents[tab].points) or 0)
    end
    local glyphCount = 0
    for _, g in ipairs(snapshot.glyphs or {}) do
        if g.spellId then glyphCount = glyphCount + 1 end
    end
    local itemCount = 0
    for _ in pairs(snapshot.gear or {}) do itemCount = itemCount + 1 end
    return string.format("%s · %d glyphs · %d items", table.concat(points, "/"), glyphCount, itemCount)
end
