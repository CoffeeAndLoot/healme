return function(h, m)
    local Native = m.Native
    if not Native then return end

    -- The shape C_ClickBindings.GetProfileInfo returned on a live client:
    -- three spells plus Blizzard's two default interactions.
    local profile = {
        { button = "LeftButton", type = 1, modifiers = 0, actionID = 774 },
        { button = "LeftButton", type = 3, modifiers = 48, actionID = 1 },
        { button = "MiddleButton", type = 1, modifiers = 0, actionID = 8936 },
        { button = "RightButton", type = 1, modifiers = 0, actionID = 33763 },
        { button = "RightButton", type = 3, modifiers = 48, actionID = 2 },
    }

    local names = { [774] = "Rejuvenation", [8936] = "Regrowth", [33763] = "Lifebloom" }
    local function nameOf(_, id) return names[id] end
    local function mods(bits) return bits == 0 and "" or "ALT" end

    h.describe("Native.Summarize", function()
        h.it("keeps spells and drops Blizzard's default interactions", function()
            local list = Native.Summarize(profile, nameOf, mods)
            h.eq(#list, 3)
            h.eq(list[1].name, "Rejuvenation")
            h.eq(list[1].combo, "Left")
            h.eq(list[3].name, "Lifebloom")
            h.eq(list[3].combo, "Right")
        end)

        h.it("names macros and pet actions too, with modifiers", function()
            local list = Native.Summarize({
                { button = "RightButton", type = 2, modifiers = 1, actionID = 7 },
                { button = "Button4", type = 4, modifiers = 0, actionID = 9 },
            }, function(kind)
                if kind == 2 then return "macro Heal" end
                return "Growl"
            end, mods)
            h.eq(list[1].name, "macro Heal")
            h.eq(list[1].combo, "ALT-Right")
            h.eq(list[2].combo, "Button 4")
        end)

        h.it("falls back to the id when a name cannot be resolved", function()
            local list = Native.Summarize(profile, function() return nil end, mods)
            h.eq(list[2].name, "#8936")
        end)

        h.it("handles nil and empty profiles", function()
            h.eq(#Native.Summarize(nil, nameOf, mods), 0)
            h.eq(#Native.Summarize({}, nameOf, mods), 0)
        end)
    end)

    h.describe("Native.Describe", function()
        h.it("reads as a sentence fragment", function()
            local list = Native.Summarize(profile, nameOf, mods)
            h.eq(Native.Describe(list),
                "Rejuvenation (Left), Regrowth (Middle), Lifebloom (Right)")
        end)
    end)
end
