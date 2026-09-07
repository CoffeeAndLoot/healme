local addonName, ns = ...
ns = ns or {}

local Core = {}
ns.Core = Core

Core.version = "0.1.0"

-- HealMe ships no libraries. Everything below is plain Blizzard API: an event
-- frame, a saved-variables table, and a slash command. The lifecycle, event
-- dispatch and profile handling that Ace3 would have provided are small enough
-- to own outright, and owning them means nothing can break because another
-- addon shipped a forked copy of a library under a different name.

local function defaultProfile()
    return {
        bindings = {},
        settings = {
            alsoTarget = false,
        },
    }
end

function Core:Print(msg)
    print("|cff33ff99HealMe|r: " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------

-- Binding sets swap with specialisation, so a healer's Restoration binds do not
-- follow them into Balance. The API for reading the current spec has moved
-- between expansions, so try the modern namespace first and fall back rather
-- than erroring; a character-only profile is a worse experience than a
-- per-spec one, but silently sharing one profile across every character would
-- be worse still.
local function currentSpecName()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
        or GetSpecialization
    if type(getSpec) ~= "function" then
        return nil
    end

    local ok, index = pcall(getSpec)
    if not ok or type(index) ~= "number" then
        return nil
    end

    -- Both namespaces have carried a GetSpecializationInfo and their return
    -- shapes have not always agreed. Rather than bet on one, try each and take
    -- the first that yields an actual name. Accepting only a non-empty string
    -- is what matters: an earlier version took the second return value on
    -- faith and produced the profile "Coffee - Suramar - 0".
    local candidates = {
        C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo,
        GetSpecializationInfo,
    }

    for i = 1, #candidates do
        local getInfo = candidates[i]
        if type(getInfo) == "function" then
            local results = { pcall(getInfo, index) }
            if results[1] then
                for j = 2, #results do
                    local value = results[j]
                    if type(value) == "string" and value ~= "" then
                        return value
                    end
                end
            end
        end
    end

    return nil
end

local function characterName()
    local name = UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or nil
    if realm and realm ~= "" then
        return name .. " - " .. realm
    end
    return name
end

function Core:ProfileName()
    local spec = currentSpecName()
    if spec then
        return characterName() .. " - " .. spec
    end
    return characterName()
end

function Core:SetProfile(name)
    if not name or name == "" then
        return
    end

    HealMeDB.profiles[name] = HealMeDB.profiles[name] or defaultProfile()

    local profile = HealMeDB.profiles[name]
    -- A profile saved by an older version may predate a field, and saved
    -- variables are whatever was on disk, so fill gaps rather than trusting it.
    profile.bindings = profile.bindings or {}
    profile.settings = profile.settings or {}
    if profile.settings.alsoTarget == nil then
        profile.settings.alsoTarget = false
    end

    self.profileName = name
    self.db.profile = profile
end

function Core:ProfileNames()
    local names = {}
    for name in pairs(HealMeDB.profiles) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function Core:CopyProfileFrom(sourceName)
    local source = HealMeDB.profiles[sourceName]
    if not source or sourceName == self.profileName then
        return false
    end

    local copy = defaultProfile()
    copy.settings.alsoTarget = source.settings and source.settings.alsoTarget or false

    for i = 1, #(source.bindings or {}) do
        local record = source.bindings[i]
        local key = record.key or {}
        local action = record.action or {}
        local conditions = record.conditions

        copy.bindings[i] = {
            id = "b" .. i,
            enabled = record.enabled ~= false,
            key = {
                button = key.button,
                shift = key.shift,
                ctrl = key.ctrl,
                alt = key.alt,
            },
            action = {
                kind = action.kind,
                spell = action.spell,
                macrotext = action.macrotext,
            },
            conditions = conditions and {
                unitFilter = conditions.unitFilter,
                aliveOnly = conditions.aliveOnly,
                deadOnly = conditions.deadOnly,
                combat = conditions.combat,
            } or nil,
        }
    end

    HealMeDB.profiles[self.profileName] = copy
    self.db.profile = copy
    self:NotifyChanged()
    return true
end

function Core:ResetProfile()
    local fresh = defaultProfile()
    HealMeDB.profiles[self.profileName] = fresh
    self.db.profile = fresh
    self:NotifyChanged()
end

---------------------------------------------------------------------------
-- Accessors used by the other modules
---------------------------------------------------------------------------

Core.db = { profile = defaultProfile() }

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

---------------------------------------------------------------------------
-- Change notification
---------------------------------------------------------------------------

local listeners = {}

-- Options subscribes so the panel redraws when bindings change underneath it.
function Core:RegisterListener(fn)
    listeners[#listeners + 1] = fn
end

function Core:ApplyAll()
    if ns.Secure and ns.Secure.ApplyAll then
        ns.Secure:ApplyAll()
    end
end

function Core:NotifyChanged()
    self:ApplyAll()
    for i = 1, #listeners do
        -- A broken listener must not stop the others, and must not throw into
        -- whatever called us.
        xpcall(listeners[i], geterrorhandler())
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

-- Bumped when the saved-variables shape changes incompatibly.
local DB_VERSION = 1

function Core:OnAddonLoaded()
    HealMeDB = HealMeDB or {}

    -- Versions before 1 stored their profiles through AceDB, which owned the
    -- same `profiles` key but wrote a different shape and left behind
    -- `profileKeys` and a `Default` profile HealMe never used. Those builds
    -- never shipped, so discard rather than migrate.
    if HealMeDB.version ~= DB_VERSION then
        HealMeDB = { version = DB_VERSION, profiles = {} }
    end

    HealMeDB.profiles = HealMeDB.profiles or {}

    -- Account-wide UI state, deliberately outside the profiles. Where the
    -- minimap button sits is a property of the interface, not of a binding set,
    -- and it should not jump when the player changes specialisation.
    HealMeDB.ui = HealMeDB.ui or {}
    if HealMeDB.ui.minimapAngle == nil then
        HealMeDB.ui.minimapAngle = 200
    end
    if HealMeDB.ui.minimapHidden == nil then
        HealMeDB.ui.minimapHidden = false
    end

    self:SetProfile(self:ProfileName())
end

function Core:UISettings()
    return HealMeDB.ui
end

function Core:OnLogin()
    self.registryActive = ns.Registry:Initialize()
    if self.registryActive then
        ns.Secure:Initialize()
        ns.Secure:ApplyAll()
    end

    if ns.Options and ns.Options.Initialize then
        ns.Options:Initialize()
    end

    if ns.MinimapButton and ns.MinimapButton.Initialize then
        ns.MinimapButton:Initialize()
    end
end

function Core:OnSpecChanged(unit)
    if unit and unit ~= "player" then
        return
    end

    local name = self:ProfileName()
    if name ~= self.profileName then
        self:SetProfile(name)
        self:NotifyChanged()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            Core:OnAddonLoaded()
        end
    elseif event == "PLAYER_LOGIN" then
        Core:OnLogin()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        Core:OnSpecChanged(arg1)
    end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

function Core:OnSlashCommand(input)
    -- Trim, but do NOT lowercase: a spell name's case is the player's to give,
    -- and C_Spell.GetSpellInfo does not match a lowercased one. Commands are
    -- compared against a lowered copy instead.
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local command = input:lower()

    if input == "" then
        if ns.Options and ns.Options.Open then
            ns.Options:Open()
        else
            self:Print("loaded, version " .. self.version
                .. " - profile: " .. tostring(self.profileName))
        end
        return
    end

    if command == "status" then
        self:Print("version " .. self.version)
        self:Print("profile: " .. tostring(self.profileName))
        self:Print("bindings: " .. #self:Bindings())
        self:Print("also target: " .. tostring(self:Settings().alsoTarget))
        self:Print("frames registered: " .. (ns.Registry and ns.Registry:Count() or 0))
        return
    end

    -- Temporary command surface for creating test bindings. It stays until the
    -- panel is proven in-game.
    local button, spell = input:match("^[Bb][Ii][Nn][Dd]%s+(%S+)%s+(.+)$")
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

    if command == "clear" then
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

SLASH_HEALME1 = "/healme"
SLASH_HEALME2 = "/hm"
SlashCmdList["HEALME"] = function(input)
    Core:OnSlashCommand(input)
end

function HealMe_OnAddonCompartmentClick()
    Core:OnSlashCommand("")
end

-- Exposed so in-game checks can reach the modules. Not part of any API.
HealMeNS = ns

return Core
