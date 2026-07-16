-- EbonBuilds: modules/weights/Weights.lua
-- Responsibility: read/write echo weights stored on the active build.

EbonBuilds.Weights = {}

------------------------------------------------------------------------
-- Canonical echo name
--
-- Weights are keyed by the PerkDatabase `comment` field (quality suffix
-- stripped) -- that's what the echo table displays and stores under, e.g.
-- "Warrior - Voidsteel Bulwark". The in-game SPELL name of class-specific
-- echoes omits the class prefix ("Voidsteel Bulwark"), so any lookup done
-- via GetSpellInfo() would silently miss the stored weight. Every weight
-- read for a concrete spellId must go through CanonicalName.
------------------------------------------------------------------------

local QUALITY_SUFFIXES = {
    " %- Common$", " %- Uncommon$", " %- Rare$", " %- Epic$", " %- Legendary$"
}

function EbonBuilds.Weights.StripQualitySuffix(name)
    for _, pattern in ipairs(QUALITY_SUFFIXES) do
        local stripped = name:match("^(.+)" .. pattern)
        if stripped then return stripped end
    end
    return name
end

-- Returns the canonical weight key for a spellId: the DB comment (suffix
-- stripped) when present, otherwise the stripped spell name as fallback.
function EbonBuilds.Weights.CanonicalName(spellId)
    if not spellId then return nil end
    local data = ProjectEbonhold and ProjectEbonhold.PerkDatabase
        and ProjectEbonhold.PerkDatabase[spellId]
    local raw = data and data.comment
    if not raw or raw == "" then
        raw = GetSpellInfo(spellId)
    end
    if not raw then return nil end
    return EbonBuilds.Weights.StripQualitySuffix(raw)
end

function EbonBuilds.Weights.Init()
    -- Storage now lives on each build; nothing to pre-allocate globally.
end

-- Returns the weight for the named echo on the active build, or 0.
function EbonBuilds.Weights.Get(echoName)
    local weights = EbonBuilds.Build.GetActiveWeights()
    if not weights then return 0 end
    return weights[echoName] or 0
end

-- Persists a weight value. value must be an integer >= 0; invalid input is ignored.
-- No-op if there is no active build.
function EbonBuilds.Weights.Set(echoName, value)
    if type(value) ~= "number" then return end
    local intVal = math.floor(value)
    if intVal < 0 then return end
    local weights = EbonBuilds.Build.GetActiveWeights()
    if not weights then return end
    weights[echoName] = intVal
end
