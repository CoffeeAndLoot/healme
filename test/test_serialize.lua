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

    -- The shipped codec, not the stub above. HealMe vendors no libraries, so
    -- this is our own format rather than AceSerializer plus LibDeflate.
    h.describe("Serialize.codec", function()
        local real = Serialize.codec

        local function roundTrip(p)
            return real.decode(real.encode(p))
        end

        h.it("round-trips a spell binding with modifiers", function()
            local out = roundTrip({
                settings = { alsoTarget = true },
                bindings = { {
                    id = "b1",
                    enabled = true,
                    key = { button = "BUTTON2", shift = true, alt = true },
                    action = { kind = "spell", spell = "Rejuvenation" },
                } },
            })
            h.eq(out.settings.alsoTarget, true)
            h.eq(#out.bindings, 1)
            local b = out.bindings[1]
            h.eq(b.key.button, "BUTTON2")
            h.eq(b.key.shift, true)
            h.eq(b.key.alt, true)
            h.falsy(b.key.ctrl)
            h.eq(b.action.kind, "spell")
            h.eq(b.action.spell, "Rejuvenation")
            h.eq(b.enabled, true)
        end)

        h.it("round-trips every condition field", function()
            local out = roundTrip({
                settings = { alsoTarget = false },
                bindings = { {
                    key = { button = "WHEELUP" },
                    action = { kind = "spell", spell = "Regrowth" },
                    conditions = { unitFilter = "help", aliveOnly = true, combat = false },
                } },
            })
            local c = out.bindings[1].conditions
            h.eq(c.unitFilter, "help")
            h.eq(c.aliveOnly, true)
            h.eq(c.combat, false)
            h.eq(out.settings.alsoTarget, false)
        end)

        h.it("keeps combat=true distinct from no combat condition", function()
            local yes = roundTrip({ bindings = { {
                key = { button = "BUTTON1" },
                action = { kind = "spell", spell = "Regrowth" },
                conditions = { combat = true },
            } } })
            h.eq(yes.bindings[1].conditions.combat, true)

            local none = roundTrip({ bindings = { {
                key = { button = "BUTTON1" },
                action = { kind = "spell", spell = "Regrowth" },
            } } })
            h.falsy(none.bindings[1].conditions)
        end)

        h.it("round-trips dead-only", function()
            local out = roundTrip({ bindings = { {
                key = { button = "BUTTON1" },
                action = { kind = "spell", spell = "Rebirth" },
                conditions = { deadOnly = true },
            } } })
            h.eq(out.bindings[1].conditions.deadOnly, true)
            h.falsy(out.bindings[1].conditions.aliveOnly)
        end)

        -- Macro text is author-supplied and can contain anything, including the
        -- characters the format uses as separators.
        h.it("survives macro text containing separators and newlines", function()
            local nasty = "/cast [@mouseover] A^B~C%D\n/target [@mouseover]"
            local out = roundTrip({ bindings = { {
                key = { button = "BUTTON3" },
                action = { kind = "macro", macrotext = nasty },
            } } })
            h.eq(#out.bindings, 1)
            h.eq(out.bindings[1].action.macrotext, nasty)
        end)

        h.it("survives a spell name containing a percent sign", function()
            local out = roundTrip({ bindings = { {
                key = { button = "BUTTON1" },
                action = { kind = "spell", spell = "100% Mana %5E Test" },
            } } })
            h.eq(out.bindings[1].action.spell, "100% Mana %5E Test")
        end)

        h.it("round-trips a frames set in a stable order", function()
            local text = real.encode({ bindings = { {
                id = "b1", enabled = true,
                key = { button = "BUTTON1" },
                action = { kind = "spell", spell = "Rejuvenation" },
                frames = { raid = true, party = true },
            } }, settings = {} })
            h.truthy(text:find("^party,raid$") or text:find("%^party,raid$"),
                "frames field should read party,raid: " .. text)
            local back = real.decode(text).bindings[1]
            h.truthy(back.frames.party and back.frames.raid)
            h.falsy(back.frames.player)
        end)

        h.it("decodes a string from before the frames field as every frame", function()
            local back = real.decode("s^0~b^BUTTON1^^spell^Rejuvenation^^^^^1").bindings[1]
            h.eq(back.frames, nil)
        end)

        h.it("round-trips a disabled binding", function()
            local out = roundTrip({ bindings = { {
                enabled = false,
                key = { button = "BUTTON1" },
                action = { kind = "spell", spell = "Regrowth" },
            } } })
            h.eq(out.bindings[1].enabled, false)
        end)

        h.it("round-trips several bindings in order", function()
            local out = roundTrip({ bindings = {
                { key = { button = "BUTTON1" }, action = { kind = "target" } },
                { key = { button = "BUTTON2" }, action = { kind = "spell", spell = "Regrowth" } },
                { key = { button = "BUTTON3" }, action = { kind = "togglemenu" } },
            } })
            h.eq(#out.bindings, 3)
            h.eq(out.bindings[1].action.kind, "target")
            h.eq(out.bindings[2].action.spell, "Regrowth")
            h.eq(out.bindings[3].action.kind, "togglemenu")
        end)

        h.it("assigns unique sequential ids on decode", function()
            local out = roundTrip({ bindings = {
                { key = { button = "BUTTON1" }, action = { kind = "target" } },
                { key = { button = "BUTTON2" }, action = { kind = "focus" } },
            } })
            h.eq(out.bindings[1].id, "b1")
            h.eq(out.bindings[2].id, "b2")
        end)

        h.it("handles a profile with no bindings", function()
            local out = roundTrip({ settings = { alsoTarget = true }, bindings = {} })
            h.eq(#out.bindings, 0)
            h.eq(out.settings.alsoTarget, true)
        end)

        h.it("returns nil for empty or non-string input", function()
            h.falsy(real.decode(""))
            h.falsy(real.decode(nil))
            h.falsy(real.decode(42))
        end)

        h.it("works end to end through Export and Import", function()
            local text = Serialize.Export({
                settings = { alsoTarget = true },
                bindings = { {
                    key = { button = "BUTTON2", ctrl = true },
                    action = { kind = "spell", spell = "Swiftmend" },
                    conditions = { unitFilter = "help" },
                } },
            }, real)
            h.eq(text:sub(1, #Serialize.PREFIX), Serialize.PREFIX)

            local out, err = Serialize.Import(text, real)
            h.truthy(out, "import failed: " .. tostring(err))
            h.eq(out.bindings[1].action.spell, "Swiftmend")
            h.eq(out.bindings[1].key.ctrl, true)
            h.eq(out.bindings[1].conditions.unitFilter, "help")
            h.eq(out.settings.alsoTarget, true)
        end)
    end)
end
