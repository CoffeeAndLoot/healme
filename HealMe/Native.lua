local _, ns = ...
ns = ns or {}

local Native = {}
ns.Native = Native

-- Blizzard's own click-casting (10.1.5+) runs beside HealMe, not under it:
-- it binds through its own header, so a native spell binding keeps firing
-- on every frame no matter what HealMe writes. HealMe never edits that
-- profile. It reports what is there, at login and on the Settings tab, and
-- opens Blizzard's window so the player can decide.

-- Enum.ClickBindingType, copied so this module can be exercised on the
-- desktop and survives the enum being unavailable.
local TYPE_SPELL, TYPE_MACRO, TYPE_PETACTION = 1, 2, 4

local BUTTON_NAME = {
    LeftButton = "Left", RightButton = "Right", MiddleButton = "Middle",
    Button4 = "Button 4", Button5 = "Button 5",
}

-- Turns a native profile (the shape C_ClickBindings.GetProfileInfo returns)
-- into a list of { name, combo } for the entries that cast something.
-- Blizzard's default target and menu rows are interactions and are left
-- out; HealMe's own target and menu bindings sit on top of those as always.
-- `nameOf(type, actionID)` and `modifierText(modifiers)` are injected so the
-- function is pure.
function Native.Summarize(profile, nameOf, modifierText)
    local list = {}
    for i = 1, #(profile or {}) do
        local entry = profile[i]
        local kind = entry.type
        if kind == TYPE_SPELL or kind == TYPE_MACRO or kind == TYPE_PETACTION then
            local name = nameOf(kind, entry.actionID) or ("#" .. tostring(entry.actionID))
            local mods = modifierText and modifierText(entry.modifiers or 0) or ""
            local button = BUTTON_NAME[entry.button] or tostring(entry.button)
            list[#list + 1] = {
                name = name,
                combo = (mods ~= "" and (mods .. "-" .. button)) or button,
            }
        end
    end
    return list
end

-- "Rejuvenation (Left), Regrowth (Middle), Lifebloom (Right)"
function Native.Describe(list)
    local parts = {}
    for i = 1, #list do
        parts[i] = list[i].name .. " (" .. list[i].combo .. ")"
    end
    return table.concat(parts, ", ")
end

local function nameOf(kind, actionID)
    if kind == TYPE_MACRO then
        if GetMacroInfo then
            local ok, name = pcall(GetMacroInfo, actionID)
            if ok and name then
                return "macro " .. name
            end
        end
        return nil
    end
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, actionID)
        if ok and name then
            return name
        end
    end
    return nil
end

local function modifierText(modifiers)
    if GetStringFromModifiers then
        local ok, text = pcall(GetStringFromModifiers, modifiers)
        if ok and type(text) == "string" then
            return text
        end
    end
    return ""
end

-- The native spell, macro and pet bindings currently saved, or an empty
-- list when the API is missing.
function Native.Bindings()
    if not (C_ClickBindings and C_ClickBindings.GetProfileInfo) then
        return {}
    end
    local ok, profile = pcall(C_ClickBindings.GetProfileInfo)
    if not ok or type(profile) ~= "table" then
        return {}
    end
    return Native.Summarize(profile, nameOf, modifierText)
end

-- One console line at login, only when there is something to say.
function Native.Warn()
    local list = Native.Bindings()
    if #list == 0 then
        return false
    end
    ns.Core:Print("Blizzard's click-casting still has " .. #list
        .. " binding" .. (#list == 1 and "" or "s")
        .. " that fire alongside HealMe: " .. Native.Describe(list)
        .. ". Open it with /healme native, or from the spellbook's Click Casting button.")
    return true
end

-- Blizzard's Click Cast Bindings window, loaded on demand like the
-- spellbook does it.
function Native.OpenWindow()
    if ToggleClickBindingFrame then
        ToggleClickBindingFrame()
        return true
    end
    ns.Core:Print("this client has no native click-casting window")
    return false
end

return Native
