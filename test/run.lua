-- Run from the repository root: lua test/run.lua
local harness = dofile("test/harness.lua")

-- Addon modules take the same (addonName, ns) the client passes, publish
-- themselves on ns, and return their table. They load here in TOC order
-- into one shared ns, so a module can reach another's constants exactly
-- as it does in-game.
local modules = {
    { "Compiler",  "HealMe/Compiler.lua" },
    { "Bindings",  "HealMe/Bindings.lua" },
    { "Registry",  "HealMe/Registry.lua" },
    { "Secure",    "HealMe/Secure.lua" },
    { "Serialize", "HealMe/Serialize.lua" },
    { "Native",    "HealMe/Native.lua" },
    { "SelfTest",  "HealMe/SelfTest.lua" },
}

local ns = {}
local loaded = {}
for i = 1, #modules do
    local name, path = modules[i][1], modules[i][2]
    local f = io.open(path, "r")
    if f then
        f:close()
        loaded[name] = assert(loadfile(path))("HealMe", ns)
    end
end

local suites = {
    "test/test_widgets.lua",
    "test/test_compiler.lua",
    "test/test_bindings.lua",
    "test/test_serialize.lua",
    "test/test_registry.lua",
    "test/test_native.lua",
    "test/test_profiles.lua",
    "test/test_selftest.lua",
}

for i = 1, #suites do
    local f = io.open(suites[i], "r")
    if f then
        f:close()
        dofile(suites[i])(harness, loaded)
    end
end

os.exit(harness.run())
