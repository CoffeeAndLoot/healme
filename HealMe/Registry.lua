local _, ns = ...
ns = ns or {}

local Registry = {}
ns.Registry = Registry

-- Registered frame -> its class from Bindings.FRAMES, decided once at
-- registration. Weak-keyed so a frame addon's teardown does not leak
-- (design spec §15): a discarded frame can be collected instead of staying
-- registered forever.
local frames = setmetatable({}, { __mode = "k" })

local function errorhandler(err)
    return geterrorhandler()(err)
end

-- Sorts a frame into a class by its global name. Blizzard's names are stable;
-- anything a third-party addon registers is "other", since raid grids
-- reshuffle their units too often to sort them any finer.
local CLASS_BY_NAME = {
    PlayerFrame = "player",
    TargetFrame = "target", TargetFrameToT = "target",
    FocusFrame = "focus", FocusFrameToT = "focus",
    PetFrame = "pet",
}

local CLASS_BY_PREFIX = {
    { "^PartyFrame", "party" },
    { "^CompactPartyFrame", "party" },
    { "^CompactRaidFrame", "raid" },
    { "^CompactRaidGroup", "raid" },
}

function Registry.ClassifyName(name)
    if type(name) ~= "string" then
        return "other"
    end
    if CLASS_BY_NAME[name] then
        return CLASS_BY_NAME[name]
    end
    for i = 1, #CLASS_BY_PREFIX do
        if name:find(CLASS_BY_PREFIX[i][1]) then
            return CLASS_BY_PREFIX[i][2]
        end
    end
    return "other"
end

-- Blizzard builds nameplates through the same CompactUnitFrame factory as
-- party and raid frames, so the factory hook sees them too. They are never
-- click-cast targets, and inside an instance enemy plates are forbidden
-- objects: calling any method on one raises an error, so the forbidden
-- check comes first and is the one call the client permits.
function Registry.Acceptable(frame)
    if frame.IsForbidden and frame:IsForbidden() then
        return false
    end
    if frame.namePlateFrame ~= nil then
        return false
    end
    return true
end

function Registry:FrameClass(frame)
    return frames[frame] or "other"
end

local function safecall(func, ...)
    if func then
        return xpcall(func, errorhandler, ...)
    end
end

local CONFLICTS = { "Clique", "Clicked" }

local function conflictingAddon()
    if not C_AddOns or not C_AddOns.GetAddOnEnableState then
        return nil
    end
    local player = UnitName("player")
    for i = 1, #CONFLICTS do
        local name = CONFLICTS[i]
        local ok, state = pcall(C_AddOns.GetAddOnEnableState, name, player)
        if ok and state and state > 0 then
            return name
        end
    end
    return nil
end

function Registry:Register(frame)
    if type(frame) == "string" then
        frame = _G[frame]
    end
    if type(frame) ~= "table" or frames[frame] then
        return
    end
    if not Registry.Acceptable(frame) then
        return
    end
    local name = frame.GetName and frame:GetName()
    frames[frame] = Registry.ClassifyName(name)
    safecall(self.onRegister, self, frame)
end

function Registry:Unregister(frame)
    if type(frame) == "string" then
        frame = _G[frame]
    end
    if type(frame) ~= "table" or not frames[frame] then
        return
    end
    frames[frame] = nil
    safecall(self.onUnregister, self, frame)
end

function Registry:IterateFrames()
    return pairs(frames)
end

function Registry:Count()
    local n = 0
    for _ in pairs(frames) do
        n = n + 1
    end
    return n
end

function Registry:Initialize()
    local conflict = conflictingAddon()
    if conflict then
        ns.Core:Print("disabled: " .. conflict .. " is enabled and claims the same "
            .. "click-casting frames. Disable one of them and reload.")
        return false
    end

    -- The header is a secure handler so that its snippets may register frames
    -- and set key bindings during combat, when insecure code may not.
    local header = CreateFrame("Frame", "ClickCastHeader", UIParent,
        "SecureHandlerBaseTemplate,SecureHandlerAttributeTemplate")
    self.header = header

    -- A snippet cannot call insecure code, so it parks the frame in an
    -- attribute and lets the insecure OnAttributeChanged hook collect it.
    header:SetAttribute("clickcast_register", [[
        local frame = self:GetAttribute("clickcast_button")
        self:SetAttribute("export_register", frame)
    ]])

    header:SetAttribute("clickcast_unregister", [[
        local frame = self:GetAttribute("clickcast_button")
        self:SetAttribute("export_unregister", frame)
    ]])

    header:HookScript("OnAttributeChanged", function(_, name, value)
        if type(value) ~= "table" then
            return
        end
        if name == "export_register" then
            Registry:Register(value)
        elseif name == "export_unregister" then
            Registry:Unregister(value)
        end
    end)

    -- Another addon may have populated the global before we loaded. Capture it
    -- and replay every entry, or those frames are lost.
    local existing = ClickCastFrames or {}

    ClickCastFrames = setmetatable({}, {
        __newindex = function(_, frame, options)
            if options ~= nil and options ~= false then
                Registry:Register(frame)
            else
                Registry:Unregister(frame)
            end
        end,
    })

    for frame in pairs(existing) do
        Registry:Register(frame)
    end

    -- Older frame addons hardcode Clique support rather than using
    -- ClickCastFrames, so give them the shape they expect.
    Clique = Clique or {}
    Clique.header = header
    Clique.UpdateRegisteredClicks = function(_, frame)
        safecall(function()
            Registry:Register(frame)
        end)
    end

    self:RegisterBlizzardFrames()

    return true
end

local BLIZZARD_FRAMES = {
    "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame",
    "TargetFrameToT", "FocusFrameToT",
}

function Registry:RegisterBlizzardFrames()
    for i = 1, #BLIZZARD_FRAMES do
        local frame = _G[BLIZZARD_FRAMES[i]]
        if frame then
            self:Register(frame)
        end
    end

    for i = 1, 4 do
        local frame = _G["PartyFrame"] and _G["PartyFrame"]["MemberFrame" .. i]
        if frame then
            self:Register(frame)
        end
    end

    -- Compact raid and party frames are created and recycled on demand, so hook
    -- the factory rather than enumerating once.
    if _G.CompactUnitFrame_SetUpFrame then
        hooksecurefunc("CompactUnitFrame_SetUpFrame", function(frame)
            Registry:Register(frame)
        end)
    end
end

return Registry
