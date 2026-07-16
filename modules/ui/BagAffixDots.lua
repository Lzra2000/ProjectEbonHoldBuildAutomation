-- EbonBuilds: modules/ui/BagAffixDots.lua
-- Draws a colored dot on bag items whose gear affix you haven't learned:
-- red for a brand-new affix line, purple for a rank you're missing on an
-- affix line you already have some rank of. Hooks the default Blizzard
-- container frame the same low-cost way AutoDelete's proven affix-dot
-- feature does (per-slot link-change cache, visibility short-circuit).

EbonBuilds.BagAffixDots = {}

local DOT_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local DOT_SIZE     = 9
local BACKING_SIZE = 12

local COLORS = {
    missing_new     = { 0.90, 0.15, 0.15 }, -- red
    missing_upgrade = { 0.64, 0.21, 0.93 }, -- purple
}

local enabled = true
local dotVersion = 0

function EbonBuilds.BagAffixDots.SetEnabled(on)
    enabled = on and true or false
    dotVersion = dotVersion + 1
    EbonBuilds.BagAffixDots.RefreshAll()
end

function EbonBuilds.BagAffixDots.IsEnabled()
    return enabled
end

local function SetButtonDot(button, classification)
    local dot  = button._ebbAffixDot
    local back = button._ebbAffixBacking
    local color = classification and COLORS[classification]

    if not enabled or not color then
        if dot then dot:Hide() end
        if back then back:Hide() end
        return
    end

    if not back then
        back = button:CreateTexture(nil, "ARTWORK")
        back:SetTexture(DOT_TEXTURE)
        back:SetSize(BACKING_SIZE, BACKING_SIZE)
        button._ebbAffixBacking = back
    end
    back:ClearAllPoints()
    back:SetPoint("CENTER", button, "CENTER", 0, 0)
    back:SetVertexColor(0, 0, 0, 1)
    back:Show()

    if not dot then
        dot = button:CreateTexture(nil, "OVERLAY")
        dot:SetTexture(DOT_TEXTURE)
        dot:SetSize(DOT_SIZE, DOT_SIZE)
        button._ebbAffixDot = dot
    end
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", back, "CENTER", 0, 0)
    dot:SetVertexColor(color[1], color[2], color[3], 1)
    dot:Show()
end

-- Decides what (if anything) to draw for a bag slot's current item.
local function DecideDot(link)
    if not link or not enabled then return nil end
    local name = link:match("%[(.-)%]")
    if not name then return nil end
    return EbonBuilds.AffixItemScan.Classify(name)
end

local function UpdateFrame(frame)
    if not frame or not frame:IsShown() then return end
    local name = frame:GetName()
    if not name then return end
    local bag = frame:GetID()
    local size = frame.size or 0
    -- Slot buttons are reverse-indexed: "Item1" is the LAST visual slot.
    for slot = 1, size do
        local button = _G[name .. "Item" .. (size - slot + 1)]
        if button then
            local link = GetContainerItemLink(bag, slot)
            if button._ebbCachedLink ~= link or button._ebbDotVersion ~= dotVersion then
                button._ebbCachedLink  = link
                button._ebbDotVersion  = dotVersion
                SetButtonDot(button, DecideDot(link))
            end
        end
    end
end

-- Forces every currently-visible default bag frame to redraw its dots
-- (e.g. after the learned-affix list updates from the server, or the
-- show/hide setting changes). Cheap: only iterates shown frames.
function EbonBuilds.BagAffixDots.RefreshAll()
    dotVersion = dotVersion + 1
    for i = 1, (NUM_CONTAINER_FRAMES or 12) do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame:IsShown() then
            UpdateFrame(frame)
        end
    end
end

function EbonBuilds.BagAffixDots.Init()
    if EbonBuildsCharDB.bagAffixDotsEnabled ~= nil then
        enabled = EbonBuildsCharDB.bagAffixDotsEnabled
    end
    if ContainerFrame_Update then
        hooksecurefunc("ContainerFrame_Update", UpdateFrame)
    end
end
