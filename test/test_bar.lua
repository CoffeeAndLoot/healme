return function(h, m)
    local Bar = m.Bar
    if not Bar then return end

    h.describe("Bar.AnchorTarget", function()
        h.it("uses the raid container in a raid", function()
            h.eq(Bar.AnchorTarget(true, true, false), "CompactRaidFrameContainer")
            h.eq(Bar.AnchorTarget(true, true, true), "CompactRaidFrameContainer")
        end)

        h.it("picks the party frame by style in a party", function()
            h.eq(Bar.AnchorTarget(false, true, true), "CompactPartyFrame")
            h.eq(Bar.AnchorTarget(false, true, false), "PartyFrame")
        end)

        h.it("hides when solo", function()
            h.eq(Bar.AnchorTarget(false, false, false), nil)
            h.eq(Bar.AnchorTarget(false, false, true), nil)
        end)
    end)

    h.describe("Bar.Layout", function()
        h.it("lays slots out left to right with a gap", function()
            local width, offsets = Bar.Layout(3, 36, 4)
            h.eq(width, 116)
            h.eq(offsets[1], 0)
            h.eq(offsets[2], 40)
            h.eq(offsets[3], 80)
        end)

        h.it("is empty for no slots", function()
            local width, offsets = Bar.Layout(0, 36, 4)
            h.eq(width, 0)
            h.eq(#offsets, 0)
        end)

        h.it("defaults the gap", function()
            local width = Bar.Layout(2, 10)
            h.eq(width, 20 + Bar.GAP)
        end)
    end)

    h.describe("Bar.Validate", function()
        local exists = function(name) return name == "Halo" or name == "Tranquility" end

        h.it("accepts a known spell not yet on the bar", function()
            h.truthy(Bar.Validate({}, "Halo", exists))
            h.truthy(Bar.Validate({ "Tranquility" }, "Halo", exists))
        end)

        h.it("refuses blanks, unknowns and duplicates", function()
            h.falsy(Bar.Validate({}, "", exists))
            h.falsy(Bar.Validate({}, nil, exists))
            local ok, err = Bar.Validate({}, "Nope", exists)
            h.falsy(ok)
            h.truthy(err:find("unknown"), err)
            ok, err = Bar.Validate({ "Halo" }, "Halo", exists)
            h.falsy(ok)
            h.truthy(err:find("already"), err)
        end)

        h.it("refuses a full bar", function()
            local list = {}
            for i = 1, Bar.MAX_SLOTS do list[i] = "Spell " .. i end
            local ok, err = Bar.Validate(list, "Halo", exists)
            h.falsy(ok)
            h.truthy(err:find("full"), err)
        end)

        h.it("skips the existence check without a checker", function()
            h.truthy(Bar.Validate({}, "Anything"))
        end)
    end)

    h.describe("Bar.Sanitize", function()
        h.it("keeps strings in order, drops blanks, junk and duplicates", function()
            local out = Bar.Sanitize({ "Halo", "", 7, "Halo", "Tranquility", false })
            h.eq(#out, 2)
            h.eq(out[1], "Halo")
            h.eq(out[2], "Tranquility")
        end)

        h.it("caps at the slot count", function()
            local list = {}
            for i = 1, Bar.MAX_SLOTS + 3 do list[i] = "Spell " .. i end
            h.eq(#Bar.Sanitize(list), Bar.MAX_SLOTS)
        end)

        h.it("returns an empty list for a non-table", function()
            h.eq(#Bar.Sanitize(nil), 0)
            h.eq(#Bar.Sanitize("x"), 0)
        end)
    end)
end
