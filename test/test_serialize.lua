return function(h, m)
    local Serialize = m.Serialize
    if not Serialize then return end

    -- A trivial reversible codec, so the test exercises the envelope rather
    -- than AceSerializer and LibDeflate.
    local store = {}
    local counter = 0
    local codec = {
        encode = function(value)
            counter = counter + 1
            local token = "T" .. counter
            store[token] = value
            return token
        end,
        decode = function(text)
            return store[text]
        end,
    }

    local profile = {
        bindings = {
            {
                id = "b1",
                enabled = true,
                key = { button = "BUTTON2", shift = true },
                action = { kind = "spell", spell = "Rejuvenation" },
            },
        },
        settings = { alsoTarget = true },
    }

    h.describe("Serialize", function()
        h.it("prefixes exported strings", function()
            local text = Serialize.Export(profile, codec)
            h.eq(text:sub(1, #Serialize.PREFIX), Serialize.PREFIX)
        end)

        h.it("round-trips a profile", function()
            local text = Serialize.Export(profile, codec)
            local result, err = Serialize.Import(text, codec)
            h.truthy(result, "import failed: " .. tostring(err))
            h.eq(result.settings.alsoTarget, true)
            h.eq(#result.bindings, 1)
            h.eq(result.bindings[1].action.spell, "Rejuvenation")
            h.eq(result.bindings[1].key.button, "BUTTON2")
        end)

        h.it("rejects text without the prefix", function()
            local result, err = Serialize.Import("garbage", codec)
            h.falsy(result)
            h.truthy(err)
        end)

        h.it("rejects a prefix it does not recognise", function()
            local result, err = Serialize.Import("!HM9!whatever", codec)
            h.falsy(result)
            h.truthy(err)
        end)

        h.it("rejects a payload the codec cannot decode", function()
            local result, err = Serialize.Import(Serialize.PREFIX .. "nope", codec)
            h.falsy(result)
            h.truthy(err)
        end)

        h.it("rejects a decoded value that is not a profile", function()
            local text = Serialize.Export("not a table", codec)
            local result, err = Serialize.Import(text, codec)
            h.falsy(result)
            h.truthy(err)
        end)

        h.it("tolerates surrounding whitespace", function()
            local text = Serialize.Export(profile, codec)
            h.truthy(Serialize.Import("  " .. text .. "\n", codec))
        end)
    end)
end
