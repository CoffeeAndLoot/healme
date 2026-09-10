local _, ns = ...
ns = ns or {}

local Bar = {}
ns.Bar = Bar

-- A row of spell buttons glued to Blizzard's raid or party frames so a
-- healer's long cooldowns sit where their eyes already are. Every button is
-- a plain spell cast with no unit: Tranquility, Halo, Divine Hymn. The
-- spell list is per profile; where the bar sits is an account-wide habit.
--
-- The helpers above the frame code are pure and unit-tested on the desktop.

Bar.MAX_SLOTS = 12
Bar.GAP = 4
Bar.SIZES = { 24, 32, 36, 40, 48, 64 }
Bar.DEFAULT_SIDE = "above"
Bar.DEFAULT_SIZE = 36

---------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------

-- The global name of the frame the bar rides, or nil to hide. Raid wins
-- over party; a party picks by whether raid-style party frames are on.
function Bar.AnchorTarget(inRaid, inParty, raidStyleParty)
    if inRaid then
        return "CompactRaidFrameContainer"
    end
    if inParty then
        return raidStyleParty and "CompactPartyFrame" or "PartyFrame"
    end
    return nil
end

-- Container width and each slot's x offset for `count` square slots.
function Bar.Layout(count, size, gap)
    gap = gap or Bar.GAP
    local offsets = {}
    for i = 1, count do
        offsets[i] = (i - 1) * (size + gap)
    end
    local width = 0
    if count > 0 then
        width = count * size + (count - 1) * gap
    end
    return width, offsets
end

-- Whether `name` may be appended to `list`. `spellExists` is optional so
-- the check can run without a client.
function Bar.Validate(list, name, spellExists)
    if type(name) ~= "string" or name == "" then
        return false, "pick a spell"
    end
    if #list >= Bar.MAX_SLOTS then
        return false, "the bar is full (" .. Bar.MAX_SLOTS .. " slots)"
    end
    for i = 1, #list do
        if list[i] == name then
            return false, name .. " is already on the bar"
        end
    end
    if spellExists and not spellExists(name) then
        return false, "unknown spell: " .. name
    end
    return true
end

-- An imported list, cleaned: strings only, no blanks, no duplicates, at
-- most MAX_SLOTS. Unknown spells are kept on purpose: a string from another
-- spec should keep its slots and simply show them empty here.
function Bar.Sanitize(list)
    local out, seen = {}, {}
    if type(list) ~= "table" then
        return out
    end
    for i = 1, #list do
        local name = list[i]
        if type(name) == "string" and name ~= "" and not seen[name]
                and #out < Bar.MAX_SLOTS then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    return out
end

return Bar
