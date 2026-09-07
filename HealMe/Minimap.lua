local _, ns = ...
ns = ns or {}

local MinimapButton = {}
ns.MinimapButton = MinimapButton

-- A minimap button without LibDBIcon, which is the usual way to get one but is
-- a library, and HealMe ships none. The whole job is a button parented to the
-- minimap, positioned on a circle by angle, and draggable around that circle.
-- The angle and the hidden flag live in account-wide saved variables rather
-- than in a profile: where the button sits is a property of the UI, not of a
-- binding set, and it should not move when the player changes specialisation.

local DEFAULT_ANGLE = 200

local button

local function settings()
    return ns.Core:UISettings()
end

-- Derived from the minimap's actual size rather than hardcoded. The usual
-- constant of 80 is right only for the default 140px minimap; on a resized one
-- a fixed radius puts the button inside the map instead of on its ring.
local function ringRadius()
    local width = Minimap:GetWidth()
    if not width or width <= 0 then
        width = 140
    end
    return (width / 2) + 10
end

local function positionButton()
    if not button then
        return
    end

    local angle = math.rad(settings().minimapAngle or DEFAULT_ANGLE)
    local radius = ringRadius()

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)
end

local function angleFromCursor()
    local mx, my = Minimap:GetCenter()
    if not mx then
        return nil
    end

    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale

    -- atan2 is a Lua 5.1 function and the client runs 5.1; math.atan accepts
    -- two arguments in later versions, so prefer atan2 and fall back.
    local atan2 = math.atan2 or math.atan
    return math.deg(atan2(py - my, px - mx))
end

local function onUpdate()
    local angle = angleFromCursor()
    if angle then
        settings().minimapAngle = angle
        positionButton()
    end
end

local function showTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("HealMe")
    GameTooltip:AddLine("Click to open the bindings panel.", 1, 1, 1)
    GameTooltip:AddLine("Drag to move this button.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function build()
    if not Minimap then
        return nil
    end

    local b = CreateFrame("Button", "HealMeMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\AddOns\\HealMe\\Media\\icon")
    -- Trim the edges so a square icon reads as round inside the ring.
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    b:SetScript("OnClick", function()
        ns.Options:Open()
    end)

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", onUpdate)
        GameTooltip:Hide()
    end)

    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    b:SetScript("OnEnter", showTooltip)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return b
end

function MinimapButton:Initialize()
    button = build()
    if not button then
        return
    end
    positionButton()
    self:Update()

    -- The minimap can be resized in Edit Mode or by a UI scale change, and the
    -- ring radius is derived from its width, so recompute when either happens
    -- rather than leaving the button stranded until the next reload.
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("UI_SCALE_CHANGED")
    watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    if EditModeManagerFrame then
        watcher:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    end
    watcher:SetScript("OnEvent", positionButton)
end

function MinimapButton:Update()
    if not button then
        return
    end
    button:SetShown(not settings().minimapHidden)
end

function MinimapButton:SetHidden(hidden)
    settings().minimapHidden = hidden and true or false
    self:Update()
end

function MinimapButton:IsHidden()
    return settings().minimapHidden and true or false
end

return MinimapButton
