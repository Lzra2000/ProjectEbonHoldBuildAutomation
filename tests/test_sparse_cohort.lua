-- Unit coverage for sparse community cohorts: exact enough, class widen,
-- low-sample UI labels, and never cross-class. Headless Lua 5.1; no WoW UI.

unpack = unpack or table.unpack

local failures = 0
local function check(condition, message)
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: " .. tostring(message) .. "\n")
    end
end
local function equal(actual, expected, message)
    check(actual == expected, string.format("%s (expected %s, got %s)",
        message, tostring(expected), tostring(actual)))
end

EbonBuilds = {}
EbonBuildsDB = { builds = {}, remoteBuilds = {}, globalSettings = {} }
EbonBuildsCharDB = {}

EbonBuilds.Quality = { ORDER = { 3, 2, 1, 0 } }
EbonBuilds.EchoCatalog = {
    GetBySpellId = function() return nil end,
    FindRefs = function() return {} end,
}
EbonBuilds.Weights = {
    ResolveLegacyName = function() return nil end,
}
EbonBuilds.EchoProjection = {
    GetEntry = function(_, refKey)
        refKey = tostring(refKey or "")
        if not refKey:match("^[gs]:%d+$") then return nil end
        return {
            refKey = refKey,
            displayName = "Echo " .. refKey,
            canonicalName = "Echo " .. refKey,
            sourceName = "Echo " .. refKey,
        }
    end,
    ResolveSpell = function() return nil end,
}
EbonBuilds.SpecData = {
    SHAMAN = {
        { name = "Elemental" },
        { name = "Enhancement" },
        { name = "Restoration" },
    },
    WARRIOR = {
        { name = "Arms" },
        { name = "Fury" },
        { name = "Protection" },
    },
}

assert(loadfile("modules/data/SpecData.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/recommendations/CommunityEligibility.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/recommendations/CommunityAggregator.lua"))("EbonBuilds", EbonBuilds)
assert(loadfile("modules/recommendations/BuildWizardEvidence.lua"))("EbonBuilds", EbonBuilds)

local Eligibility = EbonBuilds.CommunityEligibility
local Aggregator = EbonBuilds.CommunityAggregator
local Evidence = EbonBuilds.BuildWizardEvidence

local function MakeBuild(opts)
    opts = opts or {}
    local weights = opts.weights or { ["g:1001"] = 40, ["g:1002"] = 25 }
    return {
        id = opts.id,
        class = opts.class or "SHAMAN",
        spec = opts.spec or 2,
        author = opts.author or ("author-" .. tostring(opts.id or "x")),
        title = opts.title or ("Build " .. tostring(opts.id or "")),
        echoWeightsByRef = weights,
        lockedEchoes = opts.lockedEchoes,
        lastModified = opts.lastModified or "2026-07-24",
        isPublic = opts.isPublic,
    }
end

local function ResetDB()
    EbonBuildsDB.builds = {}
    EbonBuildsDB.remoteBuilds = {}
end

------------------------------------------------------------------------
-- Exact cohort with enough origins stays exact
------------------------------------------------------------------------
do
    ResetDB()
    for i = 1, 3 do
        EbonBuildsDB.remoteBuilds["e" .. i] = MakeBuild({
            id = "exact-" .. i, author = "a" .. i, spec = 2,
            weights = { ["g:1001"] = 50, ["g:2000"] = -10 },
        })
    end
    -- Extra Elemental should be ignored when exact Enhance is enough.
    EbonBuildsDB.remoteBuilds.ele = MakeBuild({
        id = "ele-1", author = "ele-author", spec = 1,
        weights = { ["g:9999"] = 99 },
    })

    local snapshot = Aggregator.Aggregate("SHAMAN", 2, 1)
    equal(snapshot.cohortScope, "exact", "enough exact origins stay exact-scoped")
    equal(snapshot.widened, false, "enough exact origins do not widen")
    equal(snapshot.originCount, 3, "exact origin count is 3")
    equal(snapshot.exactOriginCount, 3, "exactOriginCount mirrors exact sample")
    equal(snapshot.reasonCode, "COMMUNITY_READY", "full sample is community-ready")
    equal(snapshot.confidenceLevel, "limited", "n=3 is limited confidence")
    check(snapshot.schema == 7, "snapshot schema is 7")
    local has9999 = false
    for _, item in ipairs(snapshot.priorities or {}) do
        if item.refKey == "g:9999" then has9999 = true end
    end
    check(not has9999, "class-wide Elemental-only echo is not mixed into exact Enhance cohort")
end

------------------------------------------------------------------------
-- Sparse exact → widen to same class any spec (never cross-class)
------------------------------------------------------------------------
do
    ResetDB()
    EbonBuildsDB.remoteBuilds.e1 = MakeBuild({
        id = "enh-1", author = "enh1", spec = 2,
        weights = { ["g:1001"] = 40 },
    })
    EbonBuildsDB.remoteBuilds.e2 = MakeBuild({
        id = "enh-2", author = "enh2", spec = 2,
        weights = { ["g:1001"] = 35 },
    })
    EbonBuildsDB.remoteBuilds.ele1 = MakeBuild({
        id = "ele-1", author = "ele1", spec = 1,
        weights = { ["g:1001"] = 30, ["g:3000"] = 20 },
    })
    EbonBuildsDB.remoteBuilds.resto = MakeBuild({
        id = "resto-1", author = "resto1", spec = 3,
        weights = { ["g:1001"] = 25 },
    })
    -- Warrior must never enter a Shaman cohort.
    EbonBuildsDB.remoteBuilds.warr = MakeBuild({
        id = "warr-1", author = "warr1", class = "WARRIOR", spec = 1,
        weights = { ["g:1001"] = 99, ["g:7777"] = 99 },
    })

    local sources, meta = Eligibility.ResolveSources("SHAMAN", 2)
    equal(meta.cohortScope, "class", "sparse Enhance resolves to class scope")
    equal(meta.widened, true, "sparse Enhance marks widened")
    equal(meta.exactOriginCount, 2, "exact Enhance origin count is 2")
    equal(meta.scopeLabel, "Shaman (all specs)", "scope label discloses class-wide")
    equal(Eligibility.CountUniqueOrigins(sources), 4, "class-wide unique origins are 4 shaman builds")

    local snapshot = Aggregator.Aggregate("SHAMAN", 2, 1)
    equal(snapshot.cohortScope, "class", "aggregator snapshot is class-scoped")
    equal(snapshot.widened, true, "aggregator snapshot widened")
    equal(snapshot.originCount, 4, "widened origin count includes all shaman specs")
    equal(snapshot.exactOriginCount, 2, "exactOriginCount preserved for UI honesty")
    equal(snapshot.reasonCode, "COMMUNITY_READY", "widened n>=3 is community-ready")
    check(snapshot.scopeLabel == "Shaman (all specs)", "snapshot scope label is class-wide")

    local hasWarrior = false
    for _, item in ipairs(snapshot.priorities or {}) do
        if item.refKey == "g:7777" then hasWarrior = true end
    end
    check(not hasWarrior, "never mixes Warrior signals into Shaman cohort")

    local level, badge = Evidence.ConfidenceBadge(snapshot)
    equal(level, "limited", "widened n=4 confidence level limited")
    check(badge:find("class%-wide", 1) or badge:find("all specs", 1, true),
        "confidence badge discloses class-wide scope: " .. tostring(badge))
end

------------------------------------------------------------------------
-- Still sparse after widen → partial evidence + very-low badge
------------------------------------------------------------------------
do
    ResetDB()
    EbonBuildsDB.remoteBuilds.only1 = MakeBuild({
        id = "only-enh", author = "solo", spec = 2,
        weights = { ["g:1001"] = 50, ["g:1002"] = -40 },
    })
    EbonBuildsDB.remoteBuilds.only2 = MakeBuild({
        id = "only-enh-2", author = "solo2", spec = 2,
        weights = { ["g:1001"] = 45 },
    })

    local sources, meta = Eligibility.ResolveSources("SHAMAN", 2)
    equal(meta.cohortScope, "exact", "no other specs means scope stays exact")
    equal(meta.widened, false, "widening without new origins does not claim class-wide")
    equal(Eligibility.CountUniqueOrigins(sources), 2, "still only 2 origins")

    local snapshot = Aggregator.Aggregate("SHAMAN", 2, 1)
    equal(snapshot.originCount, 2, "sparse snapshot keeps 2 origins")
    equal(snapshot.confidenceLevel, "very_low", "n=2 confidence is very_low")
    equal(snapshot.reasonCode, "SPARSE_READY", "partial evidence uses SPARSE_READY")
    check(#(snapshot.priorities or {}) > 0, "sparse cohort still emits priority evidence")
    check(snapshot.widened == false, "does not falsely claim widened")

    local level, badge = Evidence.ConfidenceBadge(snapshot)
    equal(level, "very_low", "badge level very_low")
    equal(badge, "Very low sample", "badge text is Very low sample")

    local compact = Evidence.CompactText(snapshot.priorities[1], "priority")
    check(compact:find("Very low sample", 1, true), "per-echo compact text discloses very low sample")
end

------------------------------------------------------------------------
-- Zero origins remains empty / no fabricated votes
------------------------------------------------------------------------
do
    ResetDB()
    local snapshot = Aggregator.Aggregate("SHAMAN", 2, 1)
    equal(snapshot.originCount, 0, "empty cohort origin count 0")
    equal(snapshot.reasonCode, "NO_MATCHING_BUILDS", "empty cohort reason")
    equal(#(snapshot.priorities or {}), 0, "no fabricated priorities")
    equal(#(snapshot.locked or {}), 0, "no fabricated locks")
    local _, label = Evidence.CohortConfidence(0)
    equal(label, "No local sample", "zero sample label")
end

------------------------------------------------------------------------
-- Cross-class never used even when same-class is empty and warrior exists
------------------------------------------------------------------------
do
    ResetDB()
    EbonBuildsDB.remoteBuilds.w1 = MakeBuild({
        id = "w1", author = "w1", class = "WARRIOR", spec = 2,
        weights = { ["g:1001"] = 80 },
    })
    EbonBuildsDB.remoteBuilds.w2 = MakeBuild({
        id = "w2", author = "w2", class = "WARRIOR", spec = 1,
        weights = { ["g:1001"] = 70 },
    })
    EbonBuildsDB.remoteBuilds.w3 = MakeBuild({
        id = "w3", author = "w3", class = "WARRIOR", spec = 3,
        weights = { ["g:1001"] = 60 },
    })

    local snapshot = Aggregator.Aggregate("SHAMAN", 2, 1)
    equal(snapshot.originCount, 0, "warrior builds do not fill shaman cohort")
    equal(snapshot.reasonCode, "NO_MATCHING_BUILDS", "no matching shaman builds")
    local _, meta = Eligibility.ResolveSources("SHAMAN", 2)
    check(meta.cohortScope ~= nil, "resolve still returns meta")
    check(meta.cohortScope == "exact" or meta.cohortScope == "class", "scope is never cross-class")
end

if failures > 0 then
    io.stderr:write(string.format("%d sparse-cohort test(s) failed\n", failures))
    os.exit(1)
end
print("OK: sparse cohort fallback tests passed")
