-- EbonBuilds: modules/ui/Toast.lua
-- Responsibility: queue-based toast notifications. Supports simple text
-- messages and rich automation-action summaries (3 echoes inline + scores).
-- Auto-dismisses after 3 s, pauses on mouseover, click-to-dismiss,
-- dequeues the next entry automatically.

EbonBuilds.Toast = {}

local TOAST_W  = 520
local TOAST_H  = 72
local function GetToastDuration()
    return (EbonBuildsDB.globalSettings and EbonBuildsDB.globalSettings.toastDuration) or 3
end
local QUALITY_HEX = EbonBuilds.Quality.HEX

local queue      = {}
local frame
local elapsed    = 0
local hovered    = false
local fadingOut  = false
local fadeElapsed = 0
local FADE_DURATION = 0.25
local header, echoLine, footerLine, accentBar, countdownBar

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function GetRunInfo()
    -- Use the choice-round level (the level the echoes were offered at),
    -- not necessarily the current player level.
    local level = 0
    if ProjectEbonhold and ProjectEbonhold.PerkService then
        local getDebug = ProjectEbonhold.PerkService.GetRollsDebugInfo
        if getDebug then
            local choiceLevel = getDebug()
            if choiceLevel then level = choiceLevel end
        end
    end
    if level == 0 then
        level = UnitLevel("player") or 0
    end

    local rd = EbonholdPlayerRunData
    if not rd and ProjectEbonhold and ProjectEbonhold.PlayerRunService then
        local get = ProjectEbonhold.PlayerRunService.GetCurrentData
        if get then rd = get() end
    end
    local banRemain    = (rd and rd.remainingBanishes) or 0
    local totalRerolls = (rd and rd.totalRerolls) or 0
    local usedRerolls  = (rd and rd.usedRerolls) or 0
    local totalFreezes = (rd and rd.totalFreezes) or 0
    local usedFreezes  = (rd and rd.usedFreezes) or 0
    return level, banRemain, totalRerolls - usedRerolls, totalFreezes - usedFreezes
end

local function ClearLines()
    header:SetText("")
    echoLine:SetText("")
    footerLine:SetText("")
end

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------

local function ShowNext()
    ClearLines()
    if #queue == 0 then
        frame:Hide()
        return
    end

    local entry = table.remove(queue, 1)
    if entry.action then
        local actionColors = {
            Banish = "|cffff4444", Reroll = "|cff44aaff",
            Freeze = "|cff44ccff", Select  = "|cff44ff44",
        }
        local colorKey = entry.action:match("^(%a+)") or entry.action
        local ac = actionColors[colorKey] or "|cffffffff"
        header:SetText(ac .. "Automation: " .. entry.action .. "|r")

        -- Build inline echo line:  Echo1 (s)    >> Echo2 (s) <<    Echo3 (s)
        local parts = {}
        for i, ch in ipairs(entry.choices) do
            if i > 1 then
                parts[#parts + 1] = "    "
            end
            local hex = QUALITY_HEX[ch.quality] or "ffffff"
            local isTarget = (ch.index == entry.targetIndex)
            if isTarget then
                parts[#parts + 1] = "|cffffff00>> |r"
            end
            parts[#parts + 1] = string.format("|cff%s%s (%.0f)|r", hex, ch.name, ch.score)
            if isTarget then
                parts[#parts + 1] = " |cffffff00<<|r"
            end
        end
        echoLine:SetText(table.concat(parts))

        -- Footer: level and remaining charges
        local level, banRemain, rerollRemain, freezeRemain = GetRunInfo()
        footerLine:SetText(string.format(
            "|cff888888Ban: %d    Reroll: %d    Freeze: %d|r",
            banRemain, rerollRemain, freezeRemain))

        frame:SetHeight(TOAST_H)
    else
        -- Simple text message
        header:SetText(entry.text or "")
        frame:SetHeight(32)
    end

    frame:Show()
    frame:SetAlpha(1)
    fadingOut   = false
    fadeElapsed = 0
    elapsed     = 0
    hovered     = false

    if accentBar then
        local targetQuality
        if entry.action then
            for _, ch in ipairs(entry.choices) do
                if ch.index == entry.targetIndex then targetQuality = ch.quality end
            end
        end
        local hex = QUALITY_HEX[targetQuality] or "666666"
        local r, g, b = tonumber(hex:sub(1,2),16)/255, tonumber(hex:sub(3,4),16)/255, tonumber(hex:sub(5,6),16)/255
        accentBar:SetVertexColor(r, g, b, 1)
    end
    if countdownBar then
        countdownBar:SetValue(1)
    end
end

local function FinishDismiss()
    frame:Hide()
    frame:SetAlpha(1)
    fadingOut = false
    ShowNext()
end

local function DismissCurrent()
    if fadingOut then return end
    fadingOut   = true
    fadeElapsed = 0
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

function EbonBuilds.Toast.ShowAutomationResult(scored, action, targetIndex)
    local entry = { action = action, targetIndex = targetIndex, choices = {} }
    for _, s in ipairs(scored) do
        entry.choices[#entry.choices + 1] = {
            index   = s.index,
            name    = s.name,
            quality = s.quality,
            score   = s.score,
        }
    end
    table.insert(queue, entry)
    if not frame:IsShown() then ShowNext() end
end

function EbonBuilds.Toast.Show(message)
    table.insert(queue, { text = message })
    if not frame:IsShown() then ShowNext() end
end

------------------------------------------------------------------------
-- Frame construction / Init
------------------------------------------------------------------------

local function BuildFrame()
    local f = CreateFrame("Frame", "EbonBuildsToastFrame", UIParent)
    f:SetSize(TOAST_W, TOAST_H)
    f:SetPoint("TOP", UIParent, "TOP", 0, -20)
    f:SetFrameStrata("TOOLTIP")
    f:Hide()

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- Left accent bar, colored by the target echo's quality.
    accentBar = f:CreateTexture(nil, "ARTWORK")
    accentBar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    accentBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 2)
    accentBar:SetWidth(3)
    accentBar:SetTexture(1, 1, 1, 1)

    -- Thin countdown bar along the bottom edge.
    countdownBar = CreateFrame("StatusBar", nil, f)
    countdownBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 3)
    countdownBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 3)
    countdownBar:SetHeight(2)
    countdownBar:SetMinMaxValues(0, 1)
    countdownBar:SetValue(1)
    countdownBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    countdownBar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 0.35)

    -- Click to dismiss
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function() DismissCurrent() end)

    -- Mouseover pauses timer, mouseout resumes + resets elapsed
    f:SetScript("OnEnter", function() hovered = true end)
    f:SetScript("OnLeave", function() hovered = false; elapsed = 0 end)

    -- Header (centered)
    header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    header:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    header:SetJustifyH("CENTER")

    -- Single echo line (all 3 echoes inline, centered)
    echoLine = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    echoLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    echoLine:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    echoLine:SetJustifyH("CENTER")
    echoLine:SetTextColor(1, 1, 1, 1)

    -- Footer: level and charges (centered, gray)
    footerLine = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footerLine:SetPoint("TOPLEFT", echoLine, "BOTTOMLEFT", 0, -4)
    footerLine:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    footerLine:SetJustifyH("CENTER")

    -- OnUpdate timer
    f:SetScript("OnUpdate", function(self, dt)
        if fadingOut then
            fadeElapsed = fadeElapsed + dt
            local pct = fadeElapsed / FADE_DURATION
            if pct >= 1 then
                FinishDismiss()
            else
                self:SetAlpha(1 - pct)
            end
            return
        end

        if hovered then
            elapsed = 0
            if countdownBar then countdownBar:SetValue(1) end
            return
        end
        elapsed = elapsed + dt
        local duration = GetToastDuration()
        if countdownBar then
            countdownBar:SetValue(math.max(0, 1 - (elapsed / duration)))
        end
        if elapsed >= duration then
            DismissCurrent()
        end
    end)

    return f
end

function EbonBuilds.Toast.Init()
    frame = BuildFrame()
end
