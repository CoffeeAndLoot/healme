return function(h, m)
    local SelfTest = m.SelfTest
    if not SelfTest then return end

    -- A compiled set as Secure leaves it: each attribute tagged with its
    -- binding's frame scope.
    local attrs = {
        { name = "type2", value = "spell", frames = { party = true, raid = true } },
        { name = "spell2", value = "Lifebloom", frames = { party = true, raid = true } },
        { name = "unit2", value = "mouseover", frames = { party = true, raid = true } },
        { name = "type1", value = "target" },
        { name = "unit1", value = "mouseover" },
    }

    local function frameWith(values)
        return function(name) return values[name] end
    end

    h.describe("SelfTest.ExpectedAttributes", function()
        h.it("keeps only the attributes whose scope allows the class", function()
            local e = SelfTest.ExpectedAttributes(attrs, "player")
            h.eq(e.type1, "target")
            h.eq(e.type2, nil)
            local raid = SelfTest.ExpectedAttributes(attrs, "raid")
            h.eq(raid.type2, "spell")
            h.eq(raid.spell2, "Lifebloom")
        end)
    end)

    h.describe("SelfTest.CompareFrame", function()
        h.it("passes a raid frame carrying everything", function()
            local problems = SelfTest.CompareFrame(attrs, "raid", frameWith({
                type2 = "spell", spell2 = "Lifebloom", unit2 = "mouseover",
                type1 = "target", unit1 = "mouseover",
            }))
            h.eq(#problems, 0)
        end)

        h.it("passes a player frame that was cleared of the scoped binding", function()
            local problems = SelfTest.CompareFrame(attrs, "player", frameWith({
                type1 = "target", unit1 = "mouseover",
            }))
            h.eq(#problems, 0)
        end)

        h.it("flags a scoped binding that leaked onto the player frame", function()
            local problems = SelfTest.CompareFrame(attrs, "player", frameWith({
                type2 = "spell", spell2 = "Lifebloom", unit2 = "mouseover",
                type1 = "target", unit1 = "mouseover",
            }))
            h.eq(#problems, 3)
            h.eq(problems[1].name, "type2")
            h.eq(problems[1].expected, nil)
            h.eq(problems[1].actual, "spell")
        end)

        h.it("flags a missing or wrong value on a frame in scope", function()
            local problems = SelfTest.CompareFrame(attrs, "raid", frameWith({
                type2 = "spell", spell2 = "Rejuvenation", type1 = "target", unit1 = "mouseover",
            }))
            h.eq(#problems, 2)
        end)
    end)
end
