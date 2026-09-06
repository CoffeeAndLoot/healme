local _, ns = ...
ns = ns or {}

local Compiler = {}
ns.Compiler = Compiler

-- Blizzard's SecureButton_GetModifierPrefix builds its prefix by prepending
-- shift, then ctrl, then alt, so the resulting string is always in alt, ctrl,
-- shift order. Emitting any other order silently fails to match.
local MODIFIER_ORDER = { "alt", "ctrl", "shift" }

-- SecureButton_GetButtonSuffix maps Left/Right/Middle to 1/2/3 and Button4..31
-- to their number. Anything else falls through to `return "-" .. button`, which
-- is why the wheel suffixes carry a leading hyphen.
local BUTTON_SUFFIX = {
    BUTTON1   = "1",
    BUTTON2   = "2",
    BUTTON3   = "3",
    BUTTON4   = "4",
    BUTTON5   = "5",
    WHEELUP   = "-wheelup",
    WHEELDOWN = "-wheeldown",
}

local WHEEL_KEY = {
    WHEELUP   = { keybind = "MOUSEWHEELUP",   identifier = "wheelup" },
    WHEELDOWN = { keybind = "MOUSEWHEELDOWN", identifier = "wheeldown" },
}

Compiler.BUTTONS = {
    "BUTTON1", "BUTTON2", "BUTTON3", "BUTTON4", "BUTTON5",
    "WHEELUP", "WHEELDOWN",
}

function Compiler.IsValidButton(button)
    return BUTTON_SUFFIX[button] ~= nil
end

local function modifierPrefix(key, separator, upper)
    local prefix = ""
    for i = 1, #MODIFIER_ORDER do
        local mod = MODIFIER_ORDER[i]
        if key[mod] then
            prefix = prefix .. (upper and mod:upper() or mod) .. separator
        end
    end
    return prefix
end

function Compiler.AttributeName(name, key)
    local suffix = BUTTON_SUFFIX[key.button]
    if not suffix then
        return nil
    end
    return modifierPrefix(key, "-", false) .. name .. suffix
end

function Compiler.KeybindString(key)
    local wheel = WHEEL_KEY[key.button]
    if not wheel then
        return nil
    end
    return modifierPrefix(key, "-", true) .. wheel.keybind
end

function Compiler.ClickIdentifier(key)
    local wheel = WHEEL_KEY[key.button]
    return wheel and wheel.identifier or nil
end

-- Ordering is fixed so that two identical bindings always compile to
-- byte-identical macro text, which is what makes the output assertable.
function Compiler.ConditionString(conditions)
    if not conditions then
        return nil
    end

    local parts = {}

    if conditions.unitFilter then
        parts[#parts + 1] = conditions.unitFilter
    end

    if conditions.deadOnly then
        parts[#parts + 1] = "dead"
    elseif conditions.aliveOnly then
        parts[#parts + 1] = "nodead"
    end

    if conditions.combat == true then
        parts[#parts + 1] = "combat"
    elseif conditions.combat == false then
        parts[#parts + 1] = "nocombat"
    end

    if #parts == 0 then
        return nil
    end

    return table.concat(parts, ",")
end

function Compiler.UnitClause(conditions)
    local conds = Compiler.ConditionString(conditions)
    if conds then
        return "[@mouseover," .. conds .. "]"
    end
    return "[@mouseover]"
end

local MACRO_VERB = {
    target = "/target",
    focus  = "/focus",
}

local UNIT_KINDS = {
    target     = true,
    focus      = true,
    togglemenu = true,
}

function Compiler.Compile(binding, settings)
    settings = settings or {}

    local attrs = {}

    if not binding or binding.enabled == false then
        return attrs
    end

    local key = binding.key
    local action = binding.action
    if not key or not action or not Compiler.IsValidButton(key.button) then
        return attrs
    end

    local function put(name, value)
        attrs[#attrs + 1] = { name = Compiler.AttributeName(name, key), value = value }
    end

    local kind = action.kind
    local conds = Compiler.ConditionString(binding.conditions)
    local clause = Compiler.UnitClause(binding.conditions)

    if kind == "spell" then
        if conds or settings.alsoTarget then
            local lines = { "/cast " .. clause .. " " .. action.spell }
            if settings.alsoTarget then
                lines[#lines + 1] = "/target " .. clause
            end
            put("type", "macro")
            put("macrotext", table.concat(lines, "\n"))
        else
            put("type", "spell")
            put("spell", action.spell)
            put("unit", "mouseover")
        end

    elseif kind == "macro" then
        put("type", "macro")
        put("macrotext", action.macrotext)

    elseif UNIT_KINDS[kind] then
        -- togglemenu has no macro equivalent, so it never takes conditions;
        -- Bindings.Validate rejects them before a record gets this far.
        if conds and MACRO_VERB[kind] then
            put("type", "macro")
            put("macrotext", MACRO_VERB[kind] .. " " .. clause)
        else
            put("type", kind)
            put("unit", "mouseover")
        end
    end

    return attrs
end

return Compiler
