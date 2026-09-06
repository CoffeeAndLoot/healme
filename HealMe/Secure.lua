local _, ns = ...
ns = ns or {}

local Secure = {}
ns.Secure = Secure

-- Attribute names we have ever written, so that a binding removed from the
-- profile has its attribute cleared rather than left behind on the frame.
local written = {}

local frameQueue = {}
local applyAllQueued = false

Secure.attributes = {}

local function errorhandler(err)
    return geterrorhandler()(err)
end

local function safecall(func, ...)
    if func then
        return xpcall(func, errorhandler, ...)
    end
end

function Secure:Compile()
    local Compiler = ns.Compiler
    local bindings = ns.Core:Bindings()
    local settings = ns.Core:Settings()

    local attrs = {}
    for i = 1, #bindings do
        local compiled = Compiler.Compile(bindings[i], settings)
        for j = 1, #compiled do
            attrs[#attrs + 1] = compiled[j]
        end
    end

    self.attributes = attrs
    return attrs
end

-- Enables the inputs a frame does not report by default. A frame that has not
-- had RegisterForClicks called will never fire middle-click, buttons 4 and 5,
-- or the wheel.
local function enableInputs(frame)
    if frame.RegisterForClicks then
        frame:RegisterForClicks("AnyUp")
    end
    if frame.EnableMouseWheel then
        frame:EnableMouseWheel(true)
    end
end

function Secure:ApplyToFrame(frame)
    if InCombatLockdown() then
        frameQueue[frame] = true
        return
    end

    if not frame.SetAttribute then
        return
    end

    safecall(function()
        enableInputs(frame)

        -- Clear anything we wrote previously but no longer compile to, so a
        -- deleted binding stops firing.
        local current = {}
        for i = 1, #self.attributes do
            current[self.attributes[i].name] = true
        end
        for name in pairs(written) do
            if not current[name] then
                frame:SetAttribute(name, nil)
            end
        end

        for i = 1, #self.attributes do
            local attr = self.attributes[i]
            frame:SetAttribute(attr.name, attr.value)
        end
    end)
end

function Secure:ApplyAll()
    if InCombatLockdown() then
        applyAllQueued = true
        return
    end

    self:Compile()

    for i = 1, #self.attributes do
        written[self.attributes[i].name] = true
    end

    for frame in ns.Registry:IterateFrames() do
        self:ApplyToFrame(frame)
    end

    if ns.Secure.ApplyWheel then
        self:ApplyWheel()
    end
end

function Secure:FlushQueues()
    if InCombatLockdown() then
        return
    end

    if applyAllQueued then
        applyAllQueued = false
        frameQueue = {}
        self:ApplyAll()
        return
    end

    local pending = frameQueue
    frameQueue = {}
    for frame in pairs(pending) do
        self:ApplyToFrame(frame)
    end
end

function Secure:Initialize()
    ns.Registry.onRegister = function(_, frame)
        Secure:ApplyToFrame(frame)
    end

    ns.Registry.onUnregister = function(_, frame)
        frameQueue[frame] = nil
    end

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:SetScript("OnEvent", function()
        Secure:FlushQueues()
    end)
    self.watcher = watcher
end

return Secure
