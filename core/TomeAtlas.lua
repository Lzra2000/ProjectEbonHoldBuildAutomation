-- EbonBuilds: core/TomeAtlas.lua
-- Community drop database for echo tomes: records where tomes drop (mob +
-- zone), shares observations with other players over the existing sync
-- channel, and answers "where does X drop?" for the Tome Atlas view.
--
-- Data model (account-wide, in EbonBuildsDB.tomeAtlas):
--   [itemId] = {
--     name    = "Tome of Brittle Forging",
--     sources = { ["Mobname\031Zonename"] = count, ... },
--   }
-- Counts merge via max() so re-syncing the same observations is idempotent
-- (no double counting between players).

EbonBuilds.TomeAtlas = {}

local SEP = "\031"          -- unit separator between mob and zone in keys
local PENDING_WINDOW = 10   -- seconds a kill/loot source stays attributable

local TOME_PREFIXES = {
    "tome of ", "codex of ", "scroll of ", "manual of ",
    "grimoire of ", "libram of ", "tablet of ",
}

local function DB()
    EbonBuildsDB.tomeAtlas = EbonBuildsDB.tomeAtlas or {}
    return EbonBuildsDB.tomeAtlas
end

-- Is this item name a tome (echo-teaching item)?
function EbonBuilds.TomeAtlas.IsTomeName(name)
    if not name then return false end
    local n = strlower(name)
    for _, p in ipairs(TOME_PREFIXES) do
        if n:sub(1, #p) == p then return true end
    end
    return false
end

function EbonBuilds.TomeAtlas.SourceKey(mob, zone)
    return (mob or "?") .. SEP .. (zone or "?")
end

function EbonBuilds.TomeAtlas.SplitSourceKey(key)
    local mob, zone = key:match("^(.-)" .. SEP .. "(.*)$")
    return mob or key, zone or "?"
end

-- Local observation: a tome dropped from a mob in a zone.
function EbonBuilds.TomeAtlas.RecordDrop(itemId, itemName, mob, zone)
    if not itemId or not itemName then return nil end
    local db = DB()
    local entry = db[itemId]
    if not entry then
        entry = { name = itemName, sources = {} }
        db[itemId] = entry
    end
    entry.name = itemName
    local key = EbonBuilds.TomeAtlas.SourceKey(mob, zone)
    entry.sources[key] = (entry.sources[key] or 0) + 1
    return key, entry.sources[key]
end

-- Community observation from the network. max() keeps merging idempotent.
function EbonBuilds.TomeAtlas.Merge(itemId, itemName, mob, zone, count)
    if not itemId or not itemName then return end
    count = tonumber(count) or 1
    if count < 1 then count = 1 end
    if count > 9999 then count = 9999 end
    local db = DB()
    local entry = db[itemId]
    if not entry then
        entry = { name = itemName, sources = {} }
        db[itemId] = entry
    end
    local key = EbonBuilds.TomeAtlas.SourceKey(mob, zone)
    if (entry.sources[key] or 0) < count then
        entry.sources[key] = count
    end
end

------------------------------------------------------------------------
-- Wire format ("TOM|itemId|count|mob|zone|itemName")
-- mob/zone/name may contain anything except our field separator; strip it.
------------------------------------------------------------------------

local function Clean(s)
    return tostring(s or "?"):gsub("|", "/"):gsub(SEP, " ")
end

function EbonBuilds.TomeAtlas.SerializeEntry(itemId, key, count)
    local db = DB()
    local entry = db[itemId]
    if not entry then return nil end
    local mob, zone = EbonBuilds.TomeAtlas.SplitSourceKey(key)
    return string.format("TOM|%d|%d|%s|%s|%s",
        itemId, count or entry.sources[key] or 1,
        Clean(mob), Clean(zone), Clean(entry.name))
end

-- Parses a TOM payload; returns itemId, itemName, mob, zone, count or nil.
function EbonBuilds.TomeAtlas.ParsePayload(payload)
    local id, count, mob, zone, name = payload:match("^TOM|(%d+)|(%d+)|([^|]*)|([^|]*)|(.*)$")
    if not id then return nil end
    return tonumber(id), name, mob, zone, tonumber(count)
end

-- All entries as a list of serialized messages (for broadcast on sync).
function EbonBuilds.TomeAtlas.SerializeAll(maxEntries)
    local out = {}
    for itemId, entry in pairs(DB()) do
        for key, count in pairs(entry.sources or {}) do
            out[#out + 1] = EbonBuilds.TomeAtlas.SerializeEntry(itemId, key, count)
            if maxEntries and #out >= maxEntries then return out end
        end
    end
    return out
end

-- Query for the UI: sorted list of { itemId, name, sources = {{mob, zone, count}} }
function EbonBuilds.TomeAtlas.List()
    local out = {}
    for itemId, entry in pairs(DB()) do
        local sources = {}
        for key, count in pairs(entry.sources or {}) do
            local mob, zone = EbonBuilds.TomeAtlas.SplitSourceKey(key)
            sources[#sources + 1] = { mob = mob, zone = zone, count = count }
        end
        table.sort(sources, function(a, b) return a.count > b.count end)
        out[#out + 1] = { itemId = itemId, name = entry.name, sources = sources }
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

------------------------------------------------------------------------
-- Loot detection (3.3.5a): remember the last dead mob we opened/killed,
-- attribute tome loot within a short window.
------------------------------------------------------------------------

local pendingSource = nil   -- { mob, zone, t }

local function NotePossibleSource()
    if UnitExists("target") and UnitIsDead("target") and not UnitIsPlayer("target") then
        pendingSource = {
            mob  = UnitName("target"),
            zone = GetRealZoneText and GetRealZoneText() or "?",
            t    = GetTime(),
        }
    end
end

local function OnSelfLoot(msg)
    -- "You receive loot: [Tome of X]." / "You receive item: ..."
    local link = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")
    if not link then return end
    local name = link:match("%[(.-)%]")
    if not EbonBuilds.TomeAtlas.IsTomeName(name) then return end
    local itemId = tonumber(link:match("item:(%d+)"))
    if not itemId then return end

    local mob, zone = "Unknown", GetRealZoneText and GetRealZoneText() or "?"
    if pendingSource and (GetTime() - pendingSource.t) <= PENDING_WINDOW then
        mob, zone = pendingSource.mob, pendingSource.zone
    end

    local key, count = EbonBuilds.TomeAtlas.RecordDrop(itemId, name, mob, zone)
    if key and EbonBuilds.Sync and EbonBuilds.Sync.BroadcastTomeEntry then
        EbonBuilds.Sync.BroadcastTomeEntry(itemId, key, count)
    end
    DEFAULT_CHAT_FRAME:AddMessage(("|cffffd100EbonBuilds Atlas:|r recorded %s from %s (%s)."):format(link, mob, zone))
end

function EbonBuilds.TomeAtlas.Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("LOOT_OPENED")
    f:RegisterEvent("CHAT_MSG_LOOT")
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "LOOT_OPENED" then
            NotePossibleSource()
        elseif event == "CHAT_MSG_LOOT" then
            if arg1 and arg1:find("^You receive") then
                OnSelfLoot(arg1)
            end
        end
    end)
end
