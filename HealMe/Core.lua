local addonName, ns = ...
ns = ns or {}

local AceAddon = LibStub("AceAddon-3.0")
local Core = AceAddon:NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0")
ns.Core = Core

Core.version = "0.1.0"

local DEFAULTS = {
    profile = {
        bindings = {},
        settings = {
            alsoTarget = false,
        },
    },
}

function Core:Print(msg)
    print("|cff33ff99HealMe|r: " .. tostring(msg))
end

-- The profile name for the character's current specialisation, so binding sets
-- swap with spec automatically. Falls back to a per-character profile when the
-- player has not chosen a spec yet.
local function specProfileName()
    local index = GetSpecialization and GetSpecialization()
    if not index then
        return nil
    end
    local id, name = GetSpecializationInfo(index)
    if not id then
        return nil
    end
    return (UnitName("player") or "?") .. " - " .. (name or tostring(id))
end

function Core:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("HealMeDB", DEFAULTS, true)

    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

    self:RegisterChatCommand("healme", "OnSlashCommand")
    self:RegisterChatCommand("hm", "OnSlashCommand")
end

function Core:OnEnable()
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:OnSpecChanged(nil, "player")

    self.registryActive = ns.Registry:Initialize()
    if self.registryActive then
        ns.Secure:Initialize()
        ns.Secure:ApplyAll()
    end

    ns.Options:Initialize()
end

function Core:OnSpecChanged(_, unit)
    if unit and unit ~= "player" then
        return
    end
    local name = specProfileName()
    if name and self.db:GetCurrentProfile() ~= name then
        self.db:SetProfile(name)
    end
end

function Core:OnProfileChanged()
    self:NotifyChanged()
end

function Core:Bindings()
    return self.db.profile.bindings
end

function Core:Settings()
    return self.db.profile.settings
end

function Core:SpellExists(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    return C_Spell.GetSpellInfo(name) ~= nil
end

function Core:ValidationDeps()
    return {
        spellExists = function(spell)
            return Core:SpellExists(spell)
        end,
    }
end

-- Called whenever the binding table or settings change. Replaced with the real
-- implementation in Task 9, once Secure exists.
function Core:ApplyAll()
    if ns.Secure and ns.Secure.ApplyAll then
        ns.Secure:ApplyAll()
    end
end

function Core:NotifyChanged()
    self:ApplyAll()
    self:SendMessage("HealMe_BindingsChanged")
end

function Core:OnSlashCommand(input)
    input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if input == "" then
        if ns.Options and ns.Options.Open then
            ns.Options:Open()
        else
            self:Print("loaded, version " .. self.version
                .. " - profile: " .. self.db:GetCurrentProfile())
        end
        return
    end

    if input == "status" then
        self:Print("version " .. self.version)
        self:Print("profile: " .. self.db:GetCurrentProfile())
        self:Print("bindings: " .. #self:Bindings())
        self:Print("also target: " .. tostring(self:Settings().alsoTarget))
        return
    end

    -- Temporary command surface for creating test bindings. Options.lua now
    -- exists but these stay until the panel is proven in-game.
    local button, spell = input:match("^bind (%S+) (.+)$")
    if button then
        local record = {
            id = ns.Bindings.NextId(self:Bindings()),
            enabled = true,
            key = { button = button:upper() },
            action = { kind = "spell", spell = spell },
        }
        local ok, err = ns.Bindings.Validate(record, self:ValidationDeps())
        if not ok then
            self:Print("rejected: " .. err)
            return
        end
        local clash = ns.Bindings.FindConflict(self:Bindings(), record)
        if clash then
            self:Print("that combination is already bound")
            return
        end
        local list = self:Bindings()
        list[#list + 1] = record
        self:NotifyChanged()
        self:Print("bound " .. record.key.button .. " to " .. spell)
        return
    end

    if input == "clear" then
        local list = self:Bindings()
        for i = #list, 1, -1 do
            list[i] = nil
        end
        self:NotifyChanged()
        self:Print("cleared all bindings")
        return
    end

    self:Print("usage: /healme [status | bind <button> <spell> | clear]")
end

function HealMe_OnAddonCompartmentClick()
    Core:OnSlashCommand("")
end

-- Exposed so in-game checks can reach the modules. Not part of any API.
HealMeNS = ns

return Core
