-- EbonBuilds: modules/ui/Filters.lua
-- Search/filter state and an accessible compact filter bar.

EbonBuilds.Filters = {}

local FAMILIES = { "Tank", "Survivability", "Healer", "Caster DPS", "Melee DPS", "Ranged DPS", "No family" }
local QUALITY_OPTIONS = { { label = "All qualities", quality = nil } }
for _, quality in ipairs(EbonBuilds.Quality.ORDER or {}) do
    QUALITY_OPTIONS[#QUALITY_OPTIONS + 1] = {
        label = EbonBuilds.Quality.LABELS[quality] or tostring(quality),
        quality = quality,
    }
end

local state = { text = "", quality = nil, families = {}, showAllClasses = false, learnedOnly = false, learnedReady = true }
local changeCallbacks = {}
local searchEditBox, searchPlaceholder, qualityDropdown, familyDropdown
local allClassesToggle, learnedToggle, resultLabel
local chipFrame, chipPool = nil, {}
local debounceFrame, debouncePending = nil, false

local UpdateChips

local function Notify()
    if UpdateChips then UpdateChips() end
    for i = 1, #changeCallbacks do changeCallbacks[i]() end
end

local function ScheduleNotify()
    debouncePending = true
    if not debounceFrame then
        debounceFrame = CreateFrame("Frame")
        debounceFrame:Hide()
        debounceFrame._elapsed = 0
        debounceFrame:SetScript("OnUpdate", function(self, elapsed)
            if not debouncePending then self:Hide(); return end
            self._elapsed = self._elapsed + elapsed
            if self._elapsed < 0.12 then return end
            self._elapsed = 0
            debouncePending = false
            self:Hide()
            Notify()
        end)
    end
    debounceFrame._elapsed = 0
    debounceFrame:Show()
end

function EbonBuilds.Filters.OnChange(fn)
    changeCallbacks[#changeCallbacks + 1] = fn
end

local function FamiliesActive()
    for _ in pairs(state.families) do return true end
    return false
end

local function MatchesFamilies(entry)
    if not next(state.families) then return true end
    local has, hasAnyFamily = {}, false
    for _, fam in ipairs(entry.families or {}) do
        has[fam] = true
        hasAnyFamily = true
    end
    for required in pairs(state.families) do
        if required == "No family" then
            if hasAnyFamily then return false end
        elseif not has[required] then
            return false
        end
    end
    return true
end

local function NormalizeEchoName(name)
    if EbonBuilds.BuildOverview and EbonBuilds.BuildOverview._NormalizeEchoName then
        return EbonBuilds.BuildOverview._NormalizeEchoName(name)
    end
    local stripped = EbonBuilds.Weights and EbonBuilds.Weights.StripQualitySuffix
        and EbonBuilds.Weights.StripQualitySuffix(name) or tostring(name or "")
    return string.lower(stripped)
end

local function GetLearnedSnapshot()
    if not state.learnedOnly then return nil, true end
    local overview = EbonBuilds.BuildOverview
    if not overview or not overview.GetOwnedEchoSets then return nil, false end

    local ok, names, groups, spellIds = pcall(overview.GetOwnedEchoSets)
    if not ok or not names then return nil, false end
    return {
        names = names or {},
        groups = groups or {},
        spellIds = spellIds or {},
    }, true
end

local function EntryIsLearned(entry, snapshot)
    if not snapshot then return true end

    for _, spellId in pairs(entry.spellIds or {}) do
        if snapshot.spellIds[spellId] then return true end
    end
    if entry.spellId and snapshot.spellIds[entry.spellId] then return true end

    for groupId in pairs(entry.groupIds or {}) do
        if snapshot.groups[groupId] then return true end
    end

    local normalized = NormalizeEchoName(entry.name)
    return normalized and snapshot.names[normalized] and true or false
end

local function UpdateToggleVisuals()
    if allClassesToggle then
        allClassesToggle:SetText(state.showAllClasses and "All classes: ON" or "All classes")
        EbonBuilds.Theme.SetTabSelected(allClassesToggle, state.showAllClasses)
    end
    if learnedToggle then
        local text
        if state.learnedOnly and not state.learnedReady then
            text = "Learned only: ..."
        elseif state.learnedOnly then
            text = "Learned only: ON"
        else
            text = "Learned only"
        end
        learnedToggle:SetText(text)
        EbonBuilds.Theme.SetTabSelected(learnedToggle, state.learnedOnly)
    end
end

local function PassesFilters(entry, famActive, learnedSnapshot)
    if state.text ~= "" and not entry.name:lower():find(state.text, 1, true) then return false end
    if state.quality ~= nil and not (entry.qualities and entry.qualities[state.quality]) then return false end
    if famActive and not MatchesFamilies(entry) then return false end
    if state.learnedOnly and learnedSnapshot and not EntryIsLearned(entry, learnedSnapshot) then return false end
    return true
end

function EbonBuilds.Filters.Apply(echoList)
    local out, famActive = {}, FamiliesActive()
    local learnedSnapshot, learnedReady = GetLearnedSnapshot()
    state.learnedReady = learnedReady
    UpdateToggleVisuals()
    for i = 1, #echoList do
        if PassesFilters(echoList[i], famActive, learnedSnapshot) then out[#out + 1] = echoList[i] end
    end
    return out
end

function EbonBuilds.Filters.LearnedOnly()
    return state.learnedOnly
end

-- Regression-test hooks. They do not notify or mutate persistent data.
function EbonBuilds.Filters._SetLearnedOnlyForTest(value)
    state.learnedOnly = value and true or false
end

function EbonBuilds.Filters._EntryIsLearnedForTest(entry, snapshot)
    return EntryIsLearned(entry, snapshot)
end

local function UpdateSearchPlaceholder()
    if not searchPlaceholder or not searchEditBox then return end
    if searchEditBox:HasFocus() or (searchEditBox:GetText() or "") ~= "" then
        searchPlaceholder:Hide()
    else
        searchPlaceholder:Show()
    end
end

local function CreateSearchBox(bar)
    local container = CreateFrame("Frame", nil, bar)
    container:SetSize(182, 24)
    container:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    EbonBuilds.Theme.ApplyInput(container)

    local edit = CreateFrame("EditBox", nil, container)
    edit:SetPoint("TOPLEFT", container, "TOPLEFT", 7, -3)
    edit:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -24, 3)
    edit:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    edit:SetTextColor(1, 1, 1, 1)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(60)
    EbonBuilds.Theme.WireEditBox(edit, container)

    local placeholder = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", edit, "LEFT", 0, 0)
    placeholder:SetText("Search echoes...")
    placeholder:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    searchPlaceholder = placeholder

    local clear = CreateFrame("Button", nil, container)
    clear:SetSize(20, 20)
    clear:SetPoint("RIGHT", container, "RIGHT", -2, 0)
    local x = clear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    x:SetPoint("CENTER")
    x:SetText("x")
    x:SetTextColor(0.72, 0.72, 0.76)
    clear:SetScript("OnEnter", function() x:SetTextColor(1, 0.82, 0) end)
    clear:SetScript("OnLeave", function() x:SetTextColor(0.72, 0.72, 0.76) end)
    clear:SetScript("OnClick", function()
        edit:SetText("")
        edit:ClearFocus()
        UpdateSearchPlaceholder()
    end)
    EbonBuilds.Theme.AttachTooltip(clear, "Clear search", "Remove the current Echo name filter.")

    edit:SetScript("OnTextChanged", function(self)
        state.text = (self:GetText() or ""):lower()
        UpdateSearchPlaceholder()
        ScheduleNotify()
    end)
    edit:SetScript("OnEditFocusGained", UpdateSearchPlaceholder)
    edit:SetScript("OnEditFocusLost", UpdateSearchPlaceholder)
    edit:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then self:SetText("") else self:ClearFocus() end
    end)

    searchEditBox = edit
    UpdateSearchPlaceholder()
    return container
end

function EbonBuilds.Filters.FocusSearch()
    if searchEditBox then searchEditBox:SetFocus() end
end

function EbonBuilds.Filters.ShowAllClasses()
    return state.showAllClasses
end

local function CreateQualityDropdown(bar, leftAnchor)
    local dropdown = EbonBuilds.Theme.CreateDropdown(bar, 150, "All qualities")
    dropdown:SetPoint("LEFT", leftAnchor, "RIGHT", 10, 0)
    dropdown:SetMenuBuilder(function()
        local items = {}
        for _, option in ipairs(QUALITY_OPTIONS) do
            local label, quality = option.label, option.quality
            items[#items + 1] = {
                text = label,
                checked = state.quality == quality,
                func = function()
                    state.quality = quality
                    dropdown:SetText(label)
                    Notify()
                end,
            }
        end
        return items
    end)
    qualityDropdown = dropdown
    return dropdown
end

local function UpdateFamilyLabel()
    if not familyDropdown then return end
    local count = 0
    for _ in pairs(state.families) do count = count + 1 end
    familyDropdown:SetText(count == 0 and "All families" or ("Families (" .. count .. ")"))
    familyDropdown:RefreshMenu()
end

local function CreateFamilyDropdown(bar, leftAnchor)
    local dropdown = EbonBuilds.Theme.CreateDropdown(bar, 150, "All families", { multiSelect = true })
    dropdown:SetPoint("LEFT", leftAnchor, "RIGHT", 10, 0)
    familyDropdown = dropdown
    dropdown:SetMenuBuilder(function()
        local items = {}
        for _, family in ipairs(FAMILIES) do
            local fam = family
            items[#items + 1] = {
                text = fam,
                checked = state.families[fam] and true or false,
                func = function()
                    state.families[fam] = state.families[fam] and nil or true
                    UpdateFamilyLabel()
                    Notify()
                end,
            }
        end
        return items
    end)
    UpdateFamilyLabel()
    return dropdown
end

local function CreateFilterToggle(bar, text, x, width, onClick, tooltipTitle, tooltipBody)
    local btn = EbonBuilds.Theme.CreateTab(bar, text)
    btn:SetSize(width, 22)
    btn:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -30)
    btn:SetScript("OnClick", onClick)
    EbonBuilds.Theme.AttachTooltip(btn, tooltipTitle, tooltipBody)
    return btn
end

local function CreateAllClassesToggle(bar)
    allClassesToggle = CreateFilterToggle(
        bar, "All classes", 0, 108,
        function()
            state.showAllClasses = not state.showAllClasses
            UpdateToggleVisuals()
            Notify()
        end,
        "Show all classes",
        "Include Echoes that are not normally available to the build's selected class."
    )
    return allClassesToggle
end

local function CreateLearnedToggle(bar)
    learnedToggle = CreateFilterToggle(
        bar, "Learned only", 116, 124,
        function()
            state.learnedOnly = not state.learnedOnly
            state.learnedReady = true
            UpdateToggleVisuals()
            Notify()
        end,
        "Hide unlearned Echoes",
        "When enabled, the priorities list shows only Echoes your character has learned. Discovery data is used first, with the Echoes spellbook as a compatibility fallback."
    )
    return learnedToggle
end

local function ChipDefinitionList()
    local out = {}
    if state.quality ~= nil then
        out[#out + 1] = {
            label = EbonBuilds.Quality.LABELS[state.quality] or tostring(state.quality),
            clear = function()
                state.quality = nil
                if qualityDropdown then qualityDropdown:SetText("All qualities") end
            end,
        }
    end
    for _, family in ipairs(FAMILIES) do
        if state.families[family] then
            local fam = family
            out[#out + 1] = { label = fam, clear = function() state.families[fam] = nil; UpdateFamilyLabel() end }
        end
    end
    if state.showAllClasses then
        out[#out + 1] = { label = "All classes", clear = function() state.showAllClasses = false; UpdateToggleVisuals() end }
    end
    if state.learnedOnly then
        out[#out + 1] = { label = "Learned only", clear = function() state.learnedOnly = false; state.learnedReady = true; UpdateToggleVisuals() end }
    end
    return out
end

UpdateChips = function()
    if not chipFrame then return end
    for _, chip in ipairs(chipPool) do chip:Hide() end
    local defs = ChipDefinitionList()
    local x = 0
    for i, def in ipairs(defs) do
        local chipDef = def
        local chip = chipPool[i]
        if not chip then
            chip = EbonBuilds.Theme.CreateFilterChip(chipFrame, chipDef.label)
            chipPool[i] = chip
        end
        chip._chipLabel = chipDef.label
        chip:SetText(chipDef.label .. "  x")
        chip:SetWidth(math.max(54, 28 + math.min(150, #chipDef.label * 6)))
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", chipFrame, "TOPLEFT", x, 0)
        chip:SetScript("OnClick", function() chipDef.clear(); Notify() end)
        chip:Show()
        x = x + chip:GetWidth() + 5
    end
    if chipFrame._empty then
        if #defs == 0 then chipFrame._empty:Show() else chipFrame._empty:Hide() end
    end
end

function EbonBuilds.Filters.Reset()
    debouncePending = false
    if debounceFrame then debounceFrame:Hide() end
    state.text, state.quality, state.families = "", nil, {}
    state.showAllClasses, state.learnedOnly, state.learnedReady = false, false, true
    if searchEditBox then searchEditBox:SetText(""); searchEditBox:ClearFocus() end
    if qualityDropdown then qualityDropdown:SetText("All qualities") end
    UpdateFamilyLabel()
    UpdateToggleVisuals()
    UpdateSearchPlaceholder()
    Notify()
end

function EbonBuilds.Filters.SetResultCount(visible, total)
    if not resultLabel then return end
    visible, total = visible or 0, total or 0
    local text
    if visible == total then
        text = total .. " echoes"
    else
        text = visible .. " of " .. total .. " echoes"
    end
    if state.learnedOnly and not state.learnedReady then
        text = text .. " · learned data loading"
    end
    resultLabel:SetText(text)
end

function EbonBuilds.Filters.Init(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -48)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -48)
    bar:SetHeight(80)

    local searchContainer = CreateSearchBox(bar)
    local quality = CreateQualityDropdown(bar, searchContainer)
    CreateFamilyDropdown(bar, quality)
    CreateAllClassesToggle(bar)
    CreateLearnedToggle(bar)
    UpdateToggleVisuals()

    local resetBtn = EbonBuilds.Theme.CreateButton(bar)
    resetBtn:SetSize(58, 22)
    resetBtn:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    resetBtn:SetText("Reset")
    resetBtn:SetScript("OnClick", EbonBuilds.Filters.Reset)
    EbonBuilds.Theme.AttachTooltip(resetBtn, "Reset filters", "Show all Echoes for the selected class and clear the search.")

    resultLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    resultLabel:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -33)
    resultLabel:SetJustifyH("RIGHT")
    resultLabel:SetTextColor(unpack(EbonBuilds.Theme.TEXT_MUTED))
    resultLabel:SetText("0 echoes")

    chipFrame = CreateFrame("Frame", nil, bar)
    chipFrame:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -56)
    chipFrame:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -56)
    chipFrame:SetHeight(20)
    local empty = chipFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("LEFT", chipFrame, "LEFT", 2, 0)
    empty:SetText("No active filters")
    empty:SetTextColor(0.48, 0.50, 0.55, 1)
    chipFrame._empty = empty
    UpdateChips()

    return bar
end
