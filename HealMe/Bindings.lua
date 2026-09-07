local _, ns = ...
ns = ns or {}

local Bindings = {}
ns.Bindings = Bindings

-- Compiler is a sibling module in-game; on the desktop test runner each module
-- is loaded independently, so fall back to a local copy of the two constants
-- Bindings needs rather than creating a load-order dependency.
local MODIFIER_ORDER = { "alt", "ctrl", "shift" }

local VALID_BUTTON = {
    BUTTON1 = true, BUTTON2 = true, BUTTON3 = true, BUTTON4 = true,
    BUTTON5 = true, WHEELUP = true, WHEELDOWN = true,
}

Bindings.KINDS = { "spell", "macro", "target", "focus", "togglemenu" }

local VALID_KIND = {}
for i = 1, #Bindings.KINDS do
    VALID_KIND[Bindings.KINDS[i]] = true
end

local MACRO_MAX = 255

-- The kinds of frame a binding can be limited to. Registry sorts every frame
-- into exactly one of these; a binding with no `frames` set applies to all.
Bindings.FRAMES = { "player", "target", "focus", "pet", "party", "raid", "other" }

local VALID_FRAME = {}
for i = 1, #Bindings.FRAMES do
    VALID_FRAME[Bindings.FRAMES[i]] = true
end

-- Whether a binding applies to a frame of the given class.
function Bindings.FrameAllowed(record, class)
    local frames = record and record.frames
    if not frames then
        return true
    end
    return frames[class] and true or false
end

function Bindings.KeySignature(key)
    if not key or not VALID_BUTTON[key.button] then
        return nil
    end
    local prefix = ""
    for i = 1, #MODIFIER_ORDER do
        local mod = MODIFIER_ORDER[i]
        if key[mod] then
            prefix = prefix .. mod .. "-"
        end
    end
    return prefix .. key.button
end

local function hasAnyCondition(conditions)
    if not conditions then
        return false
    end
    return conditions.unitFilter ~= nil
        or conditions.aliveOnly ~= nil
        or conditions.deadOnly ~= nil
        or conditions.combat ~= nil
end

function Bindings.Validate(record, deps)
    deps = deps or {}

    if type(record) ~= "table" then
        return false, "binding must be a table"
    end

    if not Bindings.KeySignature(record.key) then
        return false, "unknown button: " .. tostring(record.key and record.key.button)
    end

    local action = record.action
    if type(action) ~= "table" or not VALID_KIND[action.kind] then
        return false, "unknown action kind: " .. tostring(action and action.kind)
    end

    local frames = record.frames
    if frames ~= nil then
        if type(frames) ~= "table" then
            return false, "frames must be a set of frame kinds"
        end
        local any = false
        for class, on in pairs(frames) do
            if not VALID_FRAME[class] then
                return false, "unknown frame kind: " .. tostring(class)
            end
            if on then any = true end
        end
        if not any then
            return false, "a binding limited to frames needs at least one kind"
        end
    end

    local conditions = record.conditions
    if conditions then
        if conditions.aliveOnly and conditions.deadOnly then
            return false, "a binding cannot require both a living and a dead unit"
        end
        if conditions.unitFilter
            and conditions.unitFilter ~= "help"
            and conditions.unitFilter ~= "harm" then
            return false, "unit filter must be help or harm"
        end
    end

    -- A disabled binding may be incomplete: a new one is created without a
    -- spell, and the editor changes one field at a time, so switching the
    -- action kind on a disabled record must not demand the next field be
    -- filled already. Nothing compiles a disabled binding, so this is safe;
    -- enabling it runs the full check.
    if record.enabled == false then
        if action.kind == "togglemenu" and hasAnyCondition(conditions) then
            return false, "the unit menu binding does not support conditions"
        end
        return true, nil
    end

    if action.kind == "spell" then
        if type(action.spell) ~= "string" or action.spell == "" then
            return false, "a spell binding needs a spell name"
        end
        local exists = deps.spellExists
        if exists and not exists(action.spell) then
            return false, "no such spell: " .. action.spell
        end

    elseif action.kind == "macro" then
        if type(action.macrotext) ~= "string" or action.macrotext == "" then
            return false, "a macro binding needs macro text"
        end
        if #action.macrotext > MACRO_MAX then
            return false, "macro text is limited to " .. MACRO_MAX .. " characters"
        end

    elseif action.kind == "togglemenu" then
        -- There is no macro command that opens a unit popup, so a conditional
        -- togglemenu could never be compiled.
        if hasAnyCondition(conditions) then
            return false, "the unit menu binding does not support conditions"
        end
    end

    return true, nil
end

function Bindings.FindConflict(list, record)
    if record.enabled == false then
        return nil
    end
    local signature = Bindings.KeySignature(record.key)
    if not signature then
        return nil
    end
    for i = 1, #list do
        local other = list[i]
        if other.id ~= record.id
            and other.enabled ~= false
            and Bindings.KeySignature(other.key) == signature then
            return other
        end
    end
    return nil
end

function Bindings.NextId(list)
    local used = {}
    for i = 1, #list do
        used[list[i].id] = true
    end
    local n = 1
    while used["b" .. n] do
        n = n + 1
    end
    return "b" .. n
end

-- Filters and repairs a list of binding records, e.g. one just imported from
-- a shared string. Validate alone cannot catch duplicate keys or duplicate
-- ids across the whole set, so this builds a fresh, safe list rather than
-- mutating the input.
function Bindings.Sanitize(records, deps)
    local accepted = {}
    local skipped = 0
    local usedKeys = {}

    for i = 1, #records do
        local record = records[i]
        local ok = Bindings.Validate(record, deps)
        if ok then
            local signature = Bindings.KeySignature(record.key)
            if signature and usedKeys[signature] then
                skipped = skipped + 1
            else
                if signature then
                    usedKeys[signature] = true
                end
                local copy = {}
                for k, v in pairs(record) do
                    copy[k] = v
                end
                copy.id = "b" .. #accepted + 1
                accepted[#accepted + 1] = copy
            end
        else
            skipped = skipped + 1
        end
    end

    return accepted, skipped
end

return Bindings
