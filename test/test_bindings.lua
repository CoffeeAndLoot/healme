return function(h, m)
    local Bindings = m.Bindings
    if not Bindings then return end

    local deps = {
        spellExists = function(name)
            return name == "Rejuvenation" or name == "Regrowth"
        end,
    }

    local function record(overrides)
        local r = {
            id = "b1",
            enabled = true,
            key = { button = "BUTTON2", shift = true },
            action = { kind = "spell", spell = "Rejuvenation" },
        }
        for k, v in pairs(overrides or {}) do
            r[k] = v
        end
        return r
    end

    h.describe("Bindings.KeySignature", function()
        h.it("canonicalises modifiers in alt-ctrl-shift order", function()
            h.eq(Bindings.KeySignature({ button = "BUTTON1", shift = true, alt = true }),
                 "alt-shift-BUTTON1")
            h.eq(Bindings.KeySignature({ button = "WHEELUP" }), "WHEELUP")
        end)

        h.it("returns nil for an unknown button", function()
            h.falsy(Bindings.KeySignature({ button = "BUTTON9" }))
        end)
    end)

    h.describe("Bindings.Validate", function()
        h.it("accepts a well-formed spell binding", function()
            local ok, err = Bindings.Validate(record(), deps)
            h.truthy(ok, "expected valid, got: " .. tostring(err))
        end)

        h.it("rejects an unknown button", function()
            local ok = Bindings.Validate(record({ key = { button = "BUTTON9" } }), deps)
            h.falsy(ok)
        end)

        h.it("rejects an unknown action kind", function()
            local ok = Bindings.Validate(record({ action = { kind = "menu" } }), deps)
            h.falsy(ok, "menu is not a valid kind; togglemenu is")
        end)

        h.it("rejects a spell the client does not know", function()
            local ok, err = Bindings.Validate(record({
                action = { kind = "spell", spell = "Nonexistent Light" },
            }), deps)
            h.falsy(ok)
            h.truthy(err and err:find("Nonexistent Light", 1, true))
        end)

        h.it("rejects empty and oversized macro text", function()
            h.falsy(Bindings.Validate(record({
                action = { kind = "macro", macrotext = "" },
            }), deps))
            h.falsy(Bindings.Validate(record({
                action = { kind = "macro", macrotext = string.rep("x", 256) },
            }), deps))
            h.truthy(Bindings.Validate(record({
                action = { kind = "macro", macrotext = string.rep("x", 255) },
            }), deps))
        end)

        h.it("lets a disabled binding be incomplete", function()
            -- A new binding is created disabled with no spell, and the
            -- editor changes one field at a time; a disabled record must be
            -- editable through every incomplete state. Enabling it is what
            -- demands the whole thing.
            h.truthy(Bindings.Validate(record({
                enabled = false, action = { kind = "spell", spell = "" },
            }), deps))
            h.truthy(Bindings.Validate(record({
                enabled = false, action = { kind = "macro", macrotext = "" },
            }), deps))
            h.falsy(Bindings.Validate(record({
                enabled = true, action = { kind = "spell", spell = "" },
            }), deps))
            -- Structural faults are still refused, disabled or not.
            h.falsy(Bindings.Validate(record({
                enabled = false, key = { button = "BUTTON9" },
            }), deps))
        end)

        h.it("accepts a frames set of known kinds and rejects the rest", function()
            h.truthy(Bindings.Validate(record({ frames = { party = true, raid = true } }), deps))
            h.falsy(Bindings.Validate(record({ frames = { grid = true } }), deps))
            h.falsy(Bindings.Validate(record({ frames = {} }), deps))
            h.falsy(Bindings.Validate(record({ frames = "party" }), deps))
            -- A structural fault, so it is refused even on a disabled binding.
            h.falsy(Bindings.Validate(record({ enabled = false, frames = {} }), deps))
        end)

        h.it("rejects aliveOnly and deadOnly together", function()
            local ok = Bindings.Validate(record({
                conditions = { aliveOnly = true, deadOnly = true },
            }), deps)
            h.falsy(ok)
        end)

        -- togglemenu has no macro equivalent, so a conditional one could never
        -- be compiled. Reject it at the door rather than silently dropping it.
        h.it("rejects conditions on togglemenu", function()
            local ok = Bindings.Validate(record({
                action = { kind = "togglemenu" },
                conditions = { unitFilter = "help" },
            }), deps)
            h.falsy(ok)
        end)

        h.it("accepts conditions on target and focus", function()
            h.truthy(Bindings.Validate(record({
                action = { kind = "target" },
                conditions = { unitFilter = "harm" },
            }), deps))
        end)
    end)

    h.describe("Bindings.FrameAllowed", function()
        h.it("allows every class when no frames are set", function()
            h.truthy(Bindings.FrameAllowed(record(), "raid"))
            h.truthy(Bindings.FrameAllowed(record(), "other"))
        end)

        h.it("allows only the classes in the set", function()
            local r = record({ frames = { party = true, raid = true } })
            h.truthy(Bindings.FrameAllowed(r, "party"))
            h.truthy(Bindings.FrameAllowed(r, "raid"))
            h.falsy(Bindings.FrameAllowed(r, "player"))
            h.falsy(Bindings.FrameAllowed(r, "other"))
        end)
    end)

    h.describe("Bindings.FindConflict", function()
        local list = {
            record({ id = "b1" }),
            record({ id = "b2", key = { button = "BUTTON1" } }),
            record({ id = "b3", key = { button = "BUTTON3" }, enabled = false }),
        }

        h.it("finds an enabled binding holding the same key", function()
            local hit = Bindings.FindConflict(list, record({ id = "b9" }))
            h.truthy(hit)
            h.eq(hit.id, "b1")
        end)

        h.it("ignores the record itself", function()
            h.falsy(Bindings.FindConflict(list, record({ id = "b1" })))
        end)

        h.it("ignores disabled bindings", function()
            h.falsy(Bindings.FindConflict(list, record({
                id = "b9", key = { button = "BUTTON3" },
            })))
        end)

        h.it("ignores a record that is itself disabled", function()
            h.falsy(Bindings.FindConflict(list, record({ id = "b9", enabled = false })))
        end)
    end)

    h.describe("Bindings.NextId", function()
        h.it("returns b1 for an empty list", function()
            h.eq(Bindings.NextId({}), "b1")
        end)

        h.it("avoids every id already in use", function()
            h.eq(Bindings.NextId({ { id = "b1" }, { id = "b2" } }), "b3")
            h.eq(Bindings.NextId({ { id = "b3" } }), "b1")
        end)
    end)

    h.describe("Bindings.Sanitize", function()
        h.it("passes a clean set through unchanged in order", function()
            local input = {
                record({ id = "x1", key = { button = "BUTTON1" } }),
                record({ id = "x2", key = { button = "BUTTON2" } }),
            }
            local accepted, skipped = Bindings.Sanitize(input, deps)
            h.eq(#accepted, 2)
            h.eq(skipped, 0)
            h.eq(accepted[1].key.button, "BUTTON1")
            h.eq(accepted[2].key.button, "BUTTON2")
        end)

        h.it("drops an invalid record and counts it", function()
            local input = {
                record({ id = "x1", key = { button = "BUTTON1" } }),
                record({ id = "x2", key = { button = "BUTTON9" } }),
            }
            local accepted, skipped = Bindings.Sanitize(input, deps)
            h.eq(#accepted, 1)
            h.eq(skipped, 1)
            h.eq(accepted[1].key.button, "BUTTON1")
        end)

        h.it("keeps only the first of two records on the same key", function()
            local input = {
                record({ id = "x1", key = { button = "BUTTON1" },
                    action = { kind = "spell", spell = "Rejuvenation" } }),
                record({ id = "x2", key = { button = "BUTTON1" }, action = { kind = "spell", spell = "Regrowth" } }),
            }
            local accepted, skipped = Bindings.Sanitize(input, deps)
            h.eq(#accepted, 1)
            h.eq(skipped, 1)
            h.eq(accepted[1].action.spell, "Rejuvenation")
        end)

        h.it("reassigns duplicate incoming ids to be unique", function()
            local input = {
                record({ id = "b1", key = { button = "BUTTON1" } }),
                record({ id = "b1", key = { button = "BUTTON2" } }),
            }
            local accepted = Bindings.Sanitize(input, deps)
            h.eq(accepted[1].id, "b1")
            h.eq(accepted[2].id, "b2")
        end)

        h.it("returns an empty array and zero skipped for empty input", function()
            local accepted, skipped = Bindings.Sanitize({}, deps)
            h.eq(#accepted, 0)
            h.eq(skipped, 0)
        end)

        h.it("does not mutate the input array", function()
            local input = {
                record({ id = "b1", key = { button = "BUTTON1" } }),
                record({ id = "b1", key = { button = "BUTTON2" } }),
            }
            local firstIdBefore = input[1].id
            local secondIdBefore = input[2].id
            Bindings.Sanitize(input, deps)
            h.eq(input[1].id, firstIdBefore)
            h.eq(input[2].id, secondIdBefore)
        end)
    end)

    h.describe("Bindings.KeySignature and Compiler.BUTTONS consistency", function()
        -- Bindings keeps its own copy of the valid-button list rather than
        -- reading from Compiler, because on the desktop test runner each module
        -- is loaded independently. A test makes sure they never silently drift apart:
        -- if the lists diverge, a button the UI offers would compile to nothing.
        h.it("accepts exactly the buttons in Compiler.BUTTONS", function()
            local Compiler = m.Compiler
            if not Compiler then return end
            for i = 1, #Compiler.BUTTONS do
                local button = Compiler.BUTTONS[i]
                h.truthy(Bindings.KeySignature({ button = button }),
                         "KeySignature should accept " .. button)
            end
            h.falsy(Bindings.KeySignature({ button = "BUTTON9" }),
                    "KeySignature should reject BUTTON9")
        end)
    end)
end
