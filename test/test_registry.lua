return function(h, m)
    local Registry = m.Registry
    if not Registry then return end

    h.describe("Secure.ScopeString", function()
        local Secure = m.Secure
        if not Secure then return end

        h.it("is empty for a binding on every frame", function()
            h.eq(Secure.ScopeString(nil), "")
        end)

        h.it("wraps the classes in commas so the snippet can find them whole", function()
            h.eq(Secure.ScopeString({ raid = true, party = true }), ",party,raid,")
            h.eq(Secure.ScopeString({ other = true }), ",other,")
        end)
    end)

    h.describe("Registry.ClassifyName", function()
        h.it("sorts Blizzard's named frames", function()
            h.eq(Registry.ClassifyName("PlayerFrame"), "player")
            h.eq(Registry.ClassifyName("TargetFrame"), "target")
            h.eq(Registry.ClassifyName("TargetFrameToT"), "target")
            h.eq(Registry.ClassifyName("FocusFrame"), "focus")
            h.eq(Registry.ClassifyName("FocusFrameToT"), "focus")
            h.eq(Registry.ClassifyName("PetFrame"), "pet")
        end)

        h.it("sorts party frames, plain and compact", function()
            h.eq(Registry.ClassifyName("PartyFrameMemberFrame1"), "party")
            h.eq(Registry.ClassifyName("CompactPartyFrameMember3"), "party")
        end)

        h.it("sorts compact raid frames, flat and grouped", function()
            h.eq(Registry.ClassifyName("CompactRaidFrame12"), "raid")
            h.eq(Registry.ClassifyName("CompactRaidGroup2Member4"), "raid")
        end)

        h.it("calls everything else other, including nameless frames", function()
            h.eq(Registry.ClassifyName("VuhDoHealPanel1Button2"), "other")
            h.eq(Registry.ClassifyName("GridLayoutFrame"), "other")
            h.eq(Registry.ClassifyName(nil), "other")
        end)
    end)
end
