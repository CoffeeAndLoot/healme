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

return Serialize
