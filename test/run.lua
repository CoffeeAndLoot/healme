-- Run from the repository root: lua test/run.lua
local harness = dofile("test/harness.lua")

-- Addon modules are written so that `dofile` returns the module table:
-- each begins `local _, ns = ...` / `ns = ns or {}` and ends `return M`.
local modules = {
    Compiler  = "HealMe/Compiler.lua",
    Bindings  = "HealMe/Bindings.lua",
    Serialize = "HealMe/Serialize.lua",
}

local loaded = {}
for name, path in pairs(modules) do
    local f = io.open(path, "r")
    if f then
        f:close()
        loaded[name] = dofile(path)
    end
end

local suites = {
    "test/test_compiler.lua",
    "test/test_bindings.lua",
    "test/test_serialize.lua",
}

for i = 1, #suites do
    local f = io.open(suites[i], "r")
    if f then
        f:close()
        dofile(suites[i])(harness, loaded)
    end
end

os.exit(harness.run())
