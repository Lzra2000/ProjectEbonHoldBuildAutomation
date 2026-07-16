-- EbonBuilds: modules/data/Quality.lua
-- Single source of truth for echo rarity colors, using the canonical WoW
-- item-quality palette so echoes read exactly like item rarities:
--   0 Common     white   ffffff
--   1 Uncommon   green   1eff00
--   2 Rare       blue    0070dd
--   3 Epic       purple  a335ee
--   4 Legendary  orange  ff8000

EbonBuilds.Quality = {}

local HEX = {
    [0] = "ffffff",
    [1] = "1eff00",
    [2] = "0070dd",
    [3] = "a335ee",
    [4] = "ff8000",
}

local RGB = {}
for q, hex in pairs(HEX) do
    RGB[q] = {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
    }
end

EbonBuilds.Quality.HEX = HEX
EbonBuilds.Quality.RGB = RGB

EbonBuilds.Quality.LABELS = { [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Epic", [4] = "Legendary" }

-- Hex string (no |cff prefix) for a quality, safe for nil/unknown.
function EbonBuilds.Quality.Hex(q)
    return HEX[q] or HEX[0]
end

-- r, g, b tuple for a quality, safe for nil/unknown.
function EbonBuilds.Quality.GetRGB(q)
    local c = RGB[q] or RGB[0]
    return c[1], c[2], c[3]
end

-- Wraps text in the quality's color escape.
function EbonBuilds.Quality.Colorize(text, q)
    return "|cff" .. (HEX[q] or HEX[0]) .. tostring(text) .. "|r"
end

-- Looks up an echo's quality from the perk database, nil if unknown.
function EbonBuilds.Quality.OfSpell(spellId)
    if not spellId or not ProjectEbonhold or not ProjectEbonhold.PerkDatabase then return nil end
    local data = ProjectEbonhold.PerkDatabase[spellId]
    return data and data.quality or nil
end
