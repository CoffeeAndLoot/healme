local addonName, ns = ...
ns = ns or {}

local Core = {}
ns.Core = Core

Core.version = "0.1.0"

function Core:Print(msg)
    print("|cff33ff99HealMe|r: " .. tostring(msg))
end

SLASH_HEALME1 = "/healme"
SLASH_HEALME2 = "/hm"
SlashCmdList.HEALME = function()
    Core:Print("loaded, version " .. Core.version)
end

function HealMe_OnAddonCompartmentClick()
    Core:Print("loaded, version " .. Core.version)
end

return Core
