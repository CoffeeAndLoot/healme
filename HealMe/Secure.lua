local _, ns = ...
ns = ns or {}

local Secure = {}
ns.Secure = Secure

-- Attribute names we have ever written, so that a binding removed from the
-- profile has its attribute cleared rather than left behind on the frame.
local written = {}

local frameQueue = {}
local unregisterQueue = {}
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

-- Renders a Lua array as a comma-separated list of quoted literals, for
-- interpolation into a restricted-environment snippet.
local function quoteList(list)
    local parts = {}
    for i = 1, #list do
        parts[i] = string.format("%q", list[i])
    end
    return table.concat(parts, ", ")
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

-- Wires the wheel-proxy setup/clear snippets onto a single frame's OnEnter and
-- OnLeave. Combat-protected (WrapScript), so callers must hold the same
-- InCombatLockdown() guard that protects attribute writes. No-ops safely if
-- the secure header was never created (Registry:Initialize refused to run) or
-- if wrapping this particular frame fails, so one bad frame cannot block the
-- rest of a loop.
function Secure:WrapFrame(frame)
    local header = ns.Registry.header
    if not header then
        return
    end

    safecall(function()
        header:UnwrapScript(frame, "OnEnter")
        header:UnwrapScript(frame, "OnLeave")
        header:WrapScript(frame, "OnEnter", [[
            control:RunFor(self, control:GetAttribute("healme_setup"))
        ]])
        header:WrapScript(frame, "OnLeave", [[
            control:RunFor(self, control:GetAttribute("healme_clear"))
        ]])
    end)
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

        self:WrapFrame(frame)
    end)
end

-- Strips a frame of everything HealMe ever wrote to it: every attribute name
-- ever compiled, and the wheel enter/leave wrappers. Used when a frame is
-- unregistered, so a unit-frame addon that turns click-casting off for a
-- frame actually stops it from casting and from hijacking the wheel.
-- Combat-protected (SetAttribute, UnwrapScript), so it queues under
-- InCombatLockdown() like every other secure write.
function Secure:ClearFrame(frame)
    if InCombatLockdown() then
        unregisterQueue[frame] = true
        return
    end

    if type(frame) ~= "table" or not frame.SetAttribute then
        return
    end

    safecall(function()
        for name in pairs(written) do
            frame:SetAttribute(name, nil)
        end

        local header = ns.Registry.header
        if header then
            header:UnwrapScript(frame, "OnEnter")
            header:UnwrapScript(frame, "OnLeave")
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

    -- Process unregistrations first: a frame queued for both cleanup and
    -- reapplication (e.g. unregistered then re-registered while in combat)
    -- should end up wired up, not stripped after the fact.
    local pendingUnregister = unregisterQueue
    unregisterQueue = {}
    for frame in pairs(pendingUnregister) do
        self:ClearFrame(frame)
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
        Secure:ClearFrame(frame)
    end

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:SetScript("OnEvent", function()
        Secure:FlushQueues()
    end)
    self.watcher = watcher
end

-- The wheel is not a click, so it cannot be bound by attributes. Instead it is
-- bound to a click on a hidden proxy button, only while the cursor is over a
-- registered frame. Because every binding resolves through @mouseover, one
-- global proxy serves every frame.
function Secure:CreateProxy()
    if self.proxy then
        return self.proxy
    end

    local proxy = CreateFrame("Button", "HealMeWheelProxy", UIParent,
        "SecureActionButtonTemplate")
    proxy:Hide()
    proxy:RegisterForClicks("AnyUp")
    self.proxy = proxy

    return proxy
end

local function wheelBindings()
    local Compiler = ns.Compiler
    local bindings = ns.Core:Bindings()

    local keybinds, identifiers = {}, {}
    for i = 1, #bindings do
        local record = bindings[i]
        if record.enabled ~= false then
            local keybind = Compiler.KeybindString(record.key)
            if keybind then
                keybinds[#keybinds + 1] = keybind
                identifiers[#identifiers + 1] = Compiler.ClickIdentifier(record.key)
            end
        end
    end

    return keybinds, identifiers
end

function Secure:ApplyWheel()
    if InCombatLockdown() then
        applyAllQueued = true
        return
    end

    local header = ns.Registry.header
    if not header then
        return
    end

    local proxy = self:CreateProxy()

    safecall(function()
        -- The proxy carries the same attribute set as every frame; only the
        -- wheel-suffixed entries are ever reached through it.
        for i = 1, #self.attributes do
            local attr = self.attributes[i]
            proxy:SetAttribute(attr.name, attr.value)
        end

        local keybinds, identifiers = wheelBindings()

        header:SetFrameRef("healme_proxy", proxy)
        header:Execute(([[
            proxy = self:GetFrameRef("healme_proxy")
            keybinds = newtable(%s)
            identifiers = newtable(%s)
        ]]):format(quoteList(keybinds), quoteList(identifiers)))

        header:SetAttribute("healme_setup", [[
            if currentButton ~= nil then
                control:RunFor(currentButton, control:GetAttribute("healme_clear"))
            end
            currentButton = self
            for i = 1, #keybinds do
                self:SetBindingClick(true, keybinds[i], proxy, identifiers[i])
            end
        ]])

        header:SetAttribute("healme_clear", [[
            for i = 1, #keybinds do
                self:ClearBinding(keybinds[i])
            end
            currentButton = nil
        ]])

        -- If the hovered unit stops existing, OnLeave may never fire and the
        -- wheel stays bound to a heal on nobody. This driver catches that.
        header:SetAttribute("_onattributechanged", [[
            if name == "unit-exists" and value == "false" and currentButton ~= nil then
                if not currentButton:IsUnderMouse() or not currentButton:IsVisible() then
                    self:RunFor(currentButton, self:GetAttribute("healme_clear"))
                    currentButton = nil
                end
            end
        ]])

        RegisterAttributeDriver(header, "unit-exists", "[@mouseover,exists] true; false")

        for frame in ns.Registry:IterateFrames() do
            self:WrapFrame(frame)
        end
    end)
end

return Secure
