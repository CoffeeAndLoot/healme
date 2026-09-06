return function(h, m)
    local Compiler = m.Compiler
    if not Compiler then return end

    h.describe("Compiler.AttributeName", function()
        h.it("uses suffix 1 for the left button with no modifiers", function()
            h.eq(Compiler.AttributeName("type", { button = "BUTTON1" }), "type1")
        end)

        h.it("uses suffix 2 for the right button", function()
            h.eq(Compiler.AttributeName("spell", { button = "BUTTON2" }), "spell2")
        end)

        h.it("uses suffix 3 for the middle button", function()
            h.eq(Compiler.AttributeName("type", { button = "BUTTON3" }), "type3")
        end)

        h.it("uses numeric suffixes for buttons 4 and 5", function()
            h.eq(Compiler.AttributeName("type", { button = "BUTTON4" }), "type4")
            h.eq(Compiler.AttributeName("type", { button = "BUTTON5" }), "type5")
        end)

        -- Blizzard's SecureButton_GetModifierPrefix prepends shift, then ctrl,
        -- then alt, so the emitted order is always alt-ctrl-shift.
        h.it("emits modifiers in alt-ctrl-shift order", function()
            h.eq(Compiler.AttributeName("type", {
                button = "BUTTON1", shift = true, ctrl = true, alt = true,
            }), "alt-ctrl-shift-type1")
        end)

        h.it("emits only the modifiers that are set, still in order", function()
            h.eq(Compiler.AttributeName("spell", {
                button = "BUTTON2", shift = true, alt = true,
            }), "alt-shift-spell2")
            h.eq(Compiler.AttributeName("type", {
                button = "BUTTON1", ctrl = true,
            }), "ctrl-type1")
        end)

        -- Unrecognised button strings fall through to `return "-" .. button`
        -- in SecureButton_GetButtonSuffix, so the hyphen is part of the suffix.
        h.it("gives wheel keys a hyphenated suffix", function()
            h.eq(Compiler.AttributeName("type", { button = "WHEELUP" }), "type-wheelup")
            h.eq(Compiler.AttributeName("macrotext", { button = "WHEELDOWN" }),
                 "macrotext-wheeldown")
            h.eq(Compiler.AttributeName("type", { button = "WHEELUP", ctrl = true }),
                 "ctrl-type-wheelup")
        end)

        h.it("returns nil for an unknown button", function()
            h.falsy(Compiler.AttributeName("type", { button = "BUTTON9" }))
        end)
    end)

    h.describe("Compiler wheel helpers", function()
        h.it("builds SetBindingClick keybind strings", function()
            h.eq(Compiler.KeybindString({ button = "WHEELUP" }), "MOUSEWHEELUP")
            h.eq(Compiler.KeybindString({ button = "WHEELDOWN", shift = true }),
                 "SHIFT-MOUSEWHEELDOWN")
            h.eq(Compiler.KeybindString({
                button = "WHEELUP", alt = true, ctrl = true, shift = true,
            }), "ALT-CTRL-SHIFT-MOUSEWHEELUP")
        end)

        h.it("returns nil for non-wheel keys", function()
            h.falsy(Compiler.KeybindString({ button = "BUTTON1" }))
            h.falsy(Compiler.ClickIdentifier({ button = "BUTTON1" }))
        end)

        h.it("names the virtual click for wheel keys", function()
            h.eq(Compiler.ClickIdentifier({ button = "WHEELUP" }), "wheelup")
            h.eq(Compiler.ClickIdentifier({ button = "WHEELDOWN" }), "wheeldown")
        end)
    end)

    h.describe("Compiler.ConditionString", function()
        h.it("returns nil when there are no conditions", function()
            h.falsy(Compiler.ConditionString(nil))
            h.falsy(Compiler.ConditionString({}))
        end)

        h.it("emits the unit filter", function()
            h.eq(Compiler.ConditionString({ unitFilter = "help" }), "help")
            h.eq(Compiler.ConditionString({ unitFilter = "harm" }), "harm")
        end)

        h.it("maps aliveOnly to nodead and deadOnly to dead", function()
            h.eq(Compiler.ConditionString({ aliveOnly = true }), "nodead")
            h.eq(Compiler.ConditionString({ deadOnly = true }), "dead")
        end)

        h.it("maps combat true and false to combat and nocombat", function()
            h.eq(Compiler.ConditionString({ combat = true }), "combat")
            h.eq(Compiler.ConditionString({ combat = false }), "nocombat")
        end)

        -- Fixed ordering is what makes compiled macro text byte-comparable.
        h.it("orders conditions filter, life, combat regardless of table order", function()
            h.eq(Compiler.ConditionString({
                combat = true, aliveOnly = true, unitFilter = "help",
            }), "help,nodead,combat")
            h.eq(Compiler.ConditionString({
                combat = false, deadOnly = true, unitFilter = "harm",
            }), "harm,dead,nocombat")
        end)
    end)

    h.describe("Compiler.UnitClause", function()
        h.it("targets mouseover with no conditions", function()
            h.eq(Compiler.UnitClause(nil), "[@mouseover]")
        end)

        h.it("appends conditions after the unit", function()
            h.eq(Compiler.UnitClause({ unitFilter = "help", aliveOnly = true }),
                 "[@mouseover,help,nodead]")
        end)
    end)

    local function binding(overrides)
        local b = {
            id = "b1",
            enabled = true,
            key = { button = "BUTTON2", shift = true },
            action = { kind = "spell", spell = "Rejuvenation" },
        }
        for k, v in pairs(overrides or {}) do
            b[k] = v
        end
        return b
    end

    h.describe("Compiler.Compile", function()
        h.it("uses the spell attribute when there are no conditions", function()
            h.attrsEq(Compiler.Compile(binding(), {}), {
                ["shift-type2"]  = "spell",
                ["shift-spell2"] = "Rejuvenation",
                ["shift-unit2"]  = "mouseover",
            })
        end)

        h.it("falls back to macro text when conditions are present", function()
            h.attrsEq(Compiler.Compile(binding({
                conditions = { unitFilter = "help", aliveOnly = true },
            }), {}), {
                ["shift-type2"]      = "macro",
                ["shift-macrotext2"] = "/cast [@mouseover,help,nodead] Rejuvenation",
            })
        end)

        h.it("passes author macro text through verbatim", function()
            h.attrsEq(Compiler.Compile(binding({
                action = { kind = "macro", macrotext = "/cast [@mouseover] Swiftmend" },
            }), {}), {
                ["shift-type2"]      = "macro",
                ["shift-macrotext2"] = "/cast [@mouseover] Swiftmend",
            })
        end)

        h.it("compiles target, focus and togglemenu to unit attributes", function()
            h.attrsEq(Compiler.Compile(binding({
                key = { button = "BUTTON1" },
                action = { kind = "target" },
            }), {}), {
                ["type1"] = "target",
                ["unit1"] = "mouseover",
            })
            h.attrsEq(Compiler.Compile(binding({
                key = { button = "BUTTON1" },
                action = { kind = "focus" },
            }), {}), {
                ["type1"] = "focus",
                ["unit1"] = "mouseover",
            })
            -- togglemenu, never menu: SECURE_ACTIONS.menu dispatches to a
            -- menu-function attribute that nothing in Blizzard's code sets.
            h.attrsEq(Compiler.Compile(binding({
                key = { button = "BUTTON2" },
                action = { kind = "togglemenu" },
            }), {}), {
                ["type2"] = "togglemenu",
                ["unit2"] = "mouseover",
            })
        end)

        h.it("wraps conditional target and focus in macro text", function()
            h.attrsEq(Compiler.Compile(binding({
                key = { button = "BUTTON1" },
                action = { kind = "target" },
                conditions = { unitFilter = "harm" },
            }), {}), {
                ["type1"]      = "macro",
                ["macrotext1"] = "/target [@mouseover,harm]",
            })
            h.attrsEq(Compiler.Compile(binding({
                key = { button = "BUTTON1" },
                action = { kind = "focus" },
                conditions = { aliveOnly = true },
            }), {}), {
                ["type1"]      = "macro",
                ["macrotext1"] = "/focus [@mouseover,nodead]",
            })
        end)

        h.it("compiles wheel bindings with hyphenated suffixes", function()
            h.attrsEq(Compiler.Compile(binding({
                key = { button = "WHEELUP", ctrl = true },
            }), {}), {
                ["ctrl-type-wheelup"]  = "spell",
                ["ctrl-spell-wheelup"] = "Rejuvenation",
                ["ctrl-unit-wheelup"]  = "mouseover",
            })
        end)

        h.it("compiles nothing for a disabled binding", function()
            h.eq(#Compiler.Compile(binding({ enabled = false }), {}), 0)
        end)

        h.it("compiles nothing for an unknown kind", function()
            h.eq(#Compiler.Compile(binding({ action = { kind = "nonsense" } }), {}), 0)
        end)

        h.it("compiles nothing for an unknown button", function()
            h.eq(#Compiler.Compile(binding({ key = { button = "BUTTON9" } }), {}), 0)
        end)
    end)
end
