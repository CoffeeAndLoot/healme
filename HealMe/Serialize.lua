local _, ns = ...
ns = ns or {}

local Serialize = {}
ns.Serialize = Serialize

Serialize.PREFIX = "!HM1!"

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Serialize.Export(profile, codec)
    return Serialize.PREFIX .. codec.encode(profile)
end

function Serialize.Import(text, codec)
    if type(text) ~= "string" then
        return nil, "import string is missing"
    end

    text = trim(text)

    if text:sub(1, #Serialize.PREFIX) ~= Serialize.PREFIX then
        return nil, "that does not look like a HealMe binding string"
    end

    local payload = text:sub(#Serialize.PREFIX + 1)
    local ok, decoded = pcall(codec.decode, payload)
    if not ok or type(decoded) ~= "table" then
        return nil, "the binding string is damaged or incomplete"
    end

    if type(decoded.bindings) ~= "table" then
        return nil, "the binding string contains no bindings"
    end

    decoded.settings = type(decoded.settings) == "table" and decoded.settings or {}

    return decoded, nil
end

-- The built-in codec.
--
-- HealMe ships no libraries, so there is no AceSerializer and no LibDeflate.
-- The profile shape is small and fixed, so a bespoke field format is simpler
-- than a general serialiser and produces a string a person can eyeball.
--
--   records separated by  ~
--   fields  separated by  ^
--   binding: b^button^mods^kind^spell^macrotext^unitFilter^life^combat^enabled^frames
--
-- `frames` is a comma list of frame kinds, empty for every frame. Strings
-- from before the field was added decode without it, meaning every frame.
--   settings: s^alsoTarget
--
-- Any character that would confuse the parse is percent-escaped, so macro text
-- containing separators or newlines survives the round trip.

local RECORD_SEP = "~"
local FIELD_SEP = "^"

local ESCAPES = {
    ["%"] = "%25",
    ["^"] = "%5E",
    ["~"] = "%7E",
    ["\n"] = "%0A",
    ["\r"] = "%0D",
}

local UNESCAPES = {}
for raw, coded in pairs(ESCAPES) do
    UNESCAPES[coded:sub(2)] = raw
end

local function escape(text)
    if text == nil then
        return ""
    end
    -- One pass, with a function replacement. Two passes would double-escape the
    -- "%" this format's own escapes are built from, and a string replacement
    -- would have "%25" read back as a capture reference.
    return (tostring(text):gsub("[%%%^~\n\r]", function(c)
        return ESCAPES[c]
    end))
end

local function unescape(text)
    return (text:gsub("%%(%x%x)", function(hex)
        return UNESCAPES[hex:upper()] or ("%" .. hex)
    end))
end

local function splitEscaped(text, sep)
    local parts = {}
    local pattern = "([^" .. (sep == "^" and "%^" or sep) .. "]*)"
    for chunk in (text .. sep):gmatch(pattern .. sep) do
        parts[#parts + 1] = chunk
    end
    return parts
end

local function boolField(value)
    return value and "1" or "0"
end

local function encodeBinding(record)
    local key = record.key or {}
    local action = record.action or {}
    local conditions = record.conditions or {}

    local mods = {}
    if key.alt then mods[#mods + 1] = "alt" end
    if key.ctrl then mods[#mods + 1] = "ctrl" end
    if key.shift then mods[#mods + 1] = "shift" end

    local life = ""
    if conditions.deadOnly then
        life = "dead"
    elseif conditions.aliveOnly then
        life = "alive"
    end

    local combat = ""
    if conditions.combat == true then
        combat = "in"
    elseif conditions.combat == false then
        combat = "out"
    end

    return table.concat({
        "b",
        escape(key.button),
        table.concat(mods, ","),
        escape(action.kind),
        escape(action.spell),
        escape(action.macrotext),
        escape(conditions.unitFilter),
        life,
        combat,
        boolField(record.enabled ~= false),
        table.concat(ns.Bindings.FrameList(record.frames), ","),
    }, FIELD_SEP)
end

local function decodeBinding(fields)
    local key = { button = unescape(fields[2] or "") }
    for mod in (fields[3] or ""):gmatch("[^,]+") do
        key[mod] = true
    end

    local action = { kind = unescape(fields[4] or "") }
    local spell = unescape(fields[5] or "")
    local macrotext = unescape(fields[6] or "")
    if spell ~= "" then
        action.spell = spell
    end
    if macrotext ~= "" then
        action.macrotext = macrotext
    end

    local conditions = nil
    local unitFilter = unescape(fields[7] or "")
    local life = fields[8] or ""
    local combat = fields[9] or ""

    if unitFilter ~= "" or life ~= "" or combat ~= "" then
        conditions = {}
        if unitFilter ~= "" then
            conditions.unitFilter = unitFilter
        end
        if life == "dead" then
            conditions.deadOnly = true
        elseif life == "alive" then
            conditions.aliveOnly = true
        end
        if combat == "in" then
            conditions.combat = true
        elseif combat == "out" then
            conditions.combat = false
        end
    end

    local frames = nil
    for class in (fields[11] or ""):gmatch("[^,]+") do
        frames = frames or {}
        frames[class] = true
    end

    return {
        enabled = (fields[10] or "1") == "1",
        key = key,
        action = action,
        conditions = conditions,
        frames = frames,
    }
end

Serialize.codec = {
    encode = function(profile)
        local records = {
            "s" .. FIELD_SEP .. boolField(profile.settings
                and profile.settings.alsoTarget),
        }
        local bindings = profile.bindings or {}
        for i = 1, #bindings do
            records[#records + 1] = encodeBinding(bindings[i])
        end
        return table.concat(records, RECORD_SEP)
    end,

    decode = function(text)
        if type(text) ~= "string" or text == "" then
            return nil
        end

        local profile = { bindings = {}, settings = { alsoTarget = false } }

        local records = splitEscaped(text, RECORD_SEP)
        for i = 1, #records do
            local fields = splitEscaped(records[i], FIELD_SEP)
            if fields[1] == "s" then
                profile.settings.alsoTarget = fields[2] == "1"
            elseif fields[1] == "b" then
                local binding = decodeBinding(fields)
                binding.id = "b" .. (#profile.bindings + 1)
                profile.bindings[#profile.bindings + 1] = binding
            end
        end

        return profile
    end,
}

return Serialize
