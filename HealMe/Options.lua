local addonName, ns = ...
ns = ns or {}

local Options = {}
ns.Options = Options

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")

local BUTTON_LABEL = {
    BUTTON1   = "Left click",
    BUTTON2   = "Right click",
    BUTTON3   = "Middle click",
    BUTTON4   = "Button 4",
    BUTTON5   = "Button 5",
    WHEELUP   = "Wheel up",
    WHEELDOWN = "Wheel down",
}

local KIND_LABEL = {
    spell      = "Cast a spell",
    macro      = "Run a macro",
    target     = "Target",
    focus      = "Set focus",
    togglemenu = "Open unit menu",
}

local FILTER_LABEL = {
    help = "Friendly only",
    harm = "Hostile only",
}

local selectedId = nil

local function bindings()
    return ns.Core:Bindings()
end

local function find(id)
    local list = bindings()
    for i = 1, #list do
        if list[i].id == id then
            return list[i], i
        end
    end
    return nil, nil
end

local function describe(record)
    local mods = ""
    if record.key.alt then mods = mods .. "Alt+" end
    if record.key.ctrl then mods = mods .. "Ctrl+" end
    if record.key.shift then mods = mods .. "Shift+" end

    local combo = mods .. (BUTTON_LABEL[record.key.button] or record.key.button)

    local what
    if record.action.kind == "spell" then
        what = record.action.spell
    elseif record.action.kind == "macro" then
        what = "macro"
    else
        what = KIND_LABEL[record.action.kind] or record.action.kind
    end

    local suffix = ""
    local conds = ns.Compiler.ConditionString(record.conditions)
    if conds then
        suffix = " [" .. conds .. "]"
    end
    if record.enabled == false then
        suffix = suffix .. " (disabled)"
    end

    return combo .. "  ->  " .. what .. suffix
end

local function bindingValues()
    local values = {}
    local list = bindings()
    for i = 1, #list do
        values[list[i].id] = describe(list[i])
    end
    return values
end

-- Saves the edited record, refusing changes that fail validation or collide
-- with another binding, and reapplying on success.
local function commit(record)
    local ok, err = ns.Bindings.Validate(record, ns.Core:ValidationDeps())
    if not ok then
        ns.Core:Print("rejected: " .. err)
        return false
    end
    local clash = ns.Bindings.FindConflict(bindings(), record)
    if clash then
        ns.Core:Print("that combination is already used by: " .. describe(clash))
        return false
    end
    ns.Core:NotifyChanged()
    return true
end

local function selected()
    return (find(selectedId))
end

local function withSelected(fn)
    return function(...)
        local record = selected()
        if record then
            return fn(record, ...)
        end
    end
end

local function buttonValues()
    local values = {}
    for i = 1, #ns.Compiler.BUTTONS do
        local button = ns.Compiler.BUTTONS[i]
        values[button] = BUTTON_LABEL[button]
    end
    return values
end

local function buildOptions()
    return {
        type = "group",
        name = "HealMe",
        args = {
            general = {
                type = "group",
                name = "General",
                order = 1,
                args = {
                    alsoTarget = {
                        type = "toggle",
                        name = "Also target",
                        desc = "When a binding casts, switch your target to the "
                            .. "clicked unit as well, so your action bar follows.",
                        width = "full",
                        order = 1,
                        get = function()
                            return ns.Core:Settings().alsoTarget
                        end,
                        set = function(_, value)
                            ns.Core:Settings().alsoTarget = value
                            ns.Core:NotifyChanged()
                        end,
                    },
                    note = {
                        type = "description",
                        order = 2,
                        name = "\nBindings fire on whichever unit frame is under "
                            .. "your cursor. HealMe draws no frames of its own.",
                    },
                },
            },

            bindings = {
                type = "group",
                name = "Bindings",
                order = 2,
                args = {
                    list = {
                        type = "select",
                        name = "Binding",
                        order = 1,
                        width = "full",
                        values = bindingValues,
                        get = function() return selectedId end,
                        set = function(_, value) selectedId = value end,
                    },

                    add = {
                        type = "execute",
                        name = "New binding",
                        order = 2,
                        func = function()
                            local list = bindings()
                            local record = {
                                id = ns.Bindings.NextId(list),
                                enabled = true,
                                key = { button = "BUTTON1" },
                                action = { kind = "spell", spell = "" },
                            }
                            list[#list + 1] = record
                            selectedId = record.id
                        end,
                    },

                    delete = {
                        type = "execute",
                        name = "Delete",
                        order = 3,
                        confirm = true,
                        confirmText = "Delete this binding?",
                        disabled = function() return selected() == nil end,
                        func = function()
                            local _, index = find(selectedId)
                            if index then
                                table.remove(bindings(), index)
                                selectedId = nil
                                ns.Core:NotifyChanged()
                            end
                        end,
                    },

                    editor = {
                        type = "group",
                        name = "Edit",
                        inline = true,
                        order = 4,
                        hidden = function() return selected() == nil end,
                        args = {
                            enabled = {
                                type = "toggle",
                                name = "Enabled",
                                order = 1,
                                get = withSelected(function(r)
                                    return r.enabled ~= false
                                end),
                                set = withSelected(function(r, _, value)
                                    local previous = r.enabled
                                    r.enabled = value
                                    if not commit(r) then r.enabled = previous end
                                end),
                            },

                            button = {
                                type = "select",
                                name = "Button",
                                order = 2,
                                values = buttonValues,
                                get = withSelected(function(r) return r.key.button end),
                                set = withSelected(function(r, _, value)
                                    local previous = r.key.button
                                    r.key.button = value
                                    if not commit(r) then
                                        r.key.button = previous
                                    end
                                end),
                            },

                            shift = {
                                type = "toggle", name = "Shift", order = 3,
                                get = withSelected(function(r) return r.key.shift end),
                                set = withSelected(function(r, _, value)
                                    local previous = r.key.shift
                                    r.key.shift = value or nil
                                    if not commit(r) then r.key.shift = previous end
                                end),
                            },
                            ctrl = {
                                type = "toggle", name = "Ctrl", order = 4,
                                get = withSelected(function(r) return r.key.ctrl end),
                                set = withSelected(function(r, _, value)
                                    local previous = r.key.ctrl
                                    r.key.ctrl = value or nil
                                    if not commit(r) then r.key.ctrl = previous end
                                end),
                            },
                            alt = {
                                type = "toggle", name = "Alt", order = 5,
                                get = withSelected(function(r) return r.key.alt end),
                                set = withSelected(function(r, _, value)
                                    local previous = r.key.alt
                                    r.key.alt = value or nil
                                    if not commit(r) then r.key.alt = previous end
                                end),
                            },

                            kind = {
                                type = "select",
                                name = "Action",
                                order = 6,
                                values = KIND_LABEL,
                                get = withSelected(function(r) return r.action.kind end),
                                set = withSelected(function(r, _, value)
                                    local previousKind = r.action.kind
                                    local previousConditions = r.conditions
                                    r.action.kind = value
                                    if value == "togglemenu" then
                                        r.conditions = nil
                                    end
                                    if not commit(r) then
                                        r.action.kind = previousKind
                                        r.conditions = previousConditions
                                    end
                                end),
                            },

                            spell = {
                                type = "input",
                                name = "Spell",
                                order = 7,
                                width = "full",
                                hidden = withSelected(function(r)
                                    return r.action.kind ~= "spell"
                                end),
                                get = withSelected(function(r)
                                    return r.action.spell
                                end),
                                set = withSelected(function(r, _, value)
                                    local previous = r.action.spell
                                    r.action.spell = value
                                    if not commit(r) then r.action.spell = previous end
                                end),
                            },

                            macrotext = {
                                type = "input",
                                name = "Macro text",
                                desc = "Up to 255 characters. Use [@mouseover] to "
                                    .. "act on the frame under your cursor.",
                                multiline = 5,
                                order = 8,
                                width = "full",
                                hidden = withSelected(function(r)
                                    return r.action.kind ~= "macro"
                                end),
                                get = withSelected(function(r)
                                    return r.action.macrotext
                                end),
                                set = withSelected(function(r, _, value)
                                    local previous = r.action.macrotext
                                    r.action.macrotext = value
                                    if not commit(r) then r.action.macrotext = previous end
                                end),
                            },

                            conditions = {
                                type = "group",
                                name = "Only when",
                                inline = true,
                                order = 9,
                                hidden = withSelected(function(r)
                                    return r.action.kind == "togglemenu"
                                        or r.action.kind == "macro"
                                end),
                                args = {
                                    unitFilter = {
                                        type = "select",
                                        name = "Unit",
                                        order = 1,
                                        values = FILTER_LABEL,
                                        get = withSelected(function(r)
                                            return r.conditions and r.conditions.unitFilter
                                        end),
                                        set = withSelected(function(r, _, value)
                                            r.conditions = r.conditions or {}
                                            r.conditions.unitFilter = value
                                            commit(r)
                                        end),
                                    },
                                    life = {
                                        type = "select",
                                        name = "State",
                                        order = 2,
                                        values = { alive = "Alive", dead = "Dead" },
                                        get = withSelected(function(r)
                                            if not r.conditions then return nil end
                                            if r.conditions.deadOnly then return "dead" end
                                            if r.conditions.aliveOnly then return "alive" end
                                            return nil
                                        end),
                                        set = withSelected(function(r, _, value)
                                            r.conditions = r.conditions or {}
                                            r.conditions.aliveOnly = (value == "alive") or nil
                                            r.conditions.deadOnly = (value == "dead") or nil
                                            commit(r)
                                        end),
                                    },
                                    combat = {
                                        type = "select",
                                        name = "Combat",
                                        order = 3,
                                        values = {
                                            ["in"] = "In combat",
                                            out = "Out of combat",
                                        },
                                        get = withSelected(function(r)
                                            if not r.conditions then return nil end
                                            if r.conditions.combat == true then return "in" end
                                            if r.conditions.combat == false then return "out" end
                                            return nil
                                        end),
                                        set = withSelected(function(r, _, value)
                                            r.conditions = r.conditions or {}
                                            if value == "in" then
                                                r.conditions.combat = true
                                            elseif value == "out" then
                                                r.conditions.combat = false
                                            else
                                                r.conditions.combat = nil
                                            end
                                            commit(r)
                                        end),
                                    },
                                    clear = {
                                        type = "execute",
                                        name = "Clear conditions",
                                        order = 4,
                                        func = withSelected(function(r)
                                            r.conditions = nil
                                            commit(r)
                                        end),
                                    },
                                },
                            },
                        },
                    },
                },
            },

            profiles = AceDBOptions:GetOptionsTable(ns.Core.db),
        },
    }
end

function Options:Initialize()
    AceConfig:RegisterOptionsTable(addonName, buildOptions)
    self.frame = AceConfigDialog:AddToBlizOptions(addonName, "HealMe")
end

function Options:Open()
    AceConfigDialog:Open(addonName)
end

return Options
