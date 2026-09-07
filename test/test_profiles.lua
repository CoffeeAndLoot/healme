return function(h)
    -- Core creates an event frame and a slash command at load, so give it
    -- just enough of the client to get through its top level.
    local env = setmetatable({}, { __index = _G })
    env.CreateFrame = function()
        return { RegisterEvent = function() end, SetScript = function() end }
    end
    env.SlashCmdList = {}
    env.UnitName = function() return "Coffee" end
    env.GetRealmName = function() return "Suramar" end
    env.print = function() end
    env.IsInRaid = function() return env.groupType == "raid" end
    env.IsInGroup = function() return env.groupType ~= "solo" end
    env.geterrorhandler = function() return function(e) error(e) end end

    local ns = {}
    local chunk
    if setfenv then
        chunk = assert(loadfile("HealMe/Core.lua"))
        setfenv(chunk, env)
    else
        -- The 5.2+ form; the 5.1 branch above is what the client runs.
        ---@diagnostic disable-next-line: redundant-parameter
        chunk = assert(loadfile("HealMe/Core.lua", "t", env))
    end
    local Core = chunk("HealMe", ns)

    local function fresh()
        env.HealMeDB = { version = 1, profiles = {}, rules = {} }
        env.groupType = "solo"
        Core.profileName = nil
        Core:SetProfile("Coffee - Suramar")
        return Core
    end

    h.describe("Core.ResolveProfile", function()
        local exists = function(name) return name == "Raid healing" end

        h.it("returns the default when there are no rules", function()
            h.eq(Core.ResolveProfile(nil, "raid", "Default", exists), "Default")
            h.eq(Core.ResolveProfile({}, "raid", "Default", exists), "Default")
        end)

        h.it("returns the slot for the group type", function()
            local rules = { raid = "Raid healing" }
            h.eq(Core.ResolveProfile(rules, "raid", "Default", exists), "Raid healing")
            h.eq(Core.ResolveProfile(rules, "party", "Default", exists), "Default")
        end)

        h.it("falls back when the slot names a profile that is gone", function()
            h.eq(Core.ResolveProfile({ raid = "Deleted" }, "raid", "Default", exists), "Default")
        end)
    end)

    h.describe("Core automatic switching", function()
        h.it("reads the group type from the client", function()
            local c = fresh()
            h.eq(c:GroupType(), "solo")
            env.groupType = "party"
            h.eq(c:GroupType(), "party")
            env.groupType = "raid"
            h.eq(c:GroupType(), "raid")
        end)

        h.it("switches when the group changes and a rule says so", function()
            local c = fresh()
            c:CreateProfile("Raid healing")
            c:SwitchProfile("Coffee - Suramar")
            c:SetRule("raid", "Raid healing")
            h.eq(c.profileName, "Coffee - Suramar")

            env.groupType = "raid"
            local name, switched = c:AutoSwitch()
            h.eq(name, "Raid healing")
            h.eq(switched, true)

            env.groupType = "party"
            name, switched = c:AutoSwitch()
            h.eq(name, "Coffee - Suramar")
            h.eq(switched, true)

            local _, again = c:AutoSwitch()
            h.eq(again, false)
        end)

        h.it("applies a rule as soon as it is set", function()
            local c = fresh()
            c:CreateProfile("Solo set")
            c:SwitchProfile("Coffee - Suramar")
            c:SetRule("solo", "Solo set")
            h.eq(c.profileName, "Solo set")
            c:SetRule("solo", "")
            h.eq(c.profileName, "Coffee - Suramar")
        end)

        h.it("follows a rename and forgets a delete", function()
            local c = fresh()
            c:CreateProfile("Raid healing")
            c:SwitchProfile("Coffee - Suramar")
            c:SetRule("raid", "Raid healing")
            c:RenameProfile("Raid healing", "Big raids")
            h.eq(c:Rules().raid, "Big raids")
            c:DeleteProfile("Big raids")
            h.eq(c:Rules().raid, nil)
        end)
    end)

    h.describe("Core profiles", function()
        h.it("creates an empty profile and switches to it", function()
            local c = fresh()
            h.truthy(c:CreateProfile("  Raid healing "))
            h.eq(c.profileName, "Raid healing")
            h.eq(#c:Bindings(), 0)
        end)

        h.it("refuses a blank or duplicate name", function()
            local c = fresh()
            h.falsy(c:CreateProfile("   "))
            h.falsy(c:CreateProfile("Coffee - Suramar"))
        end)

        h.it("switches between existing profiles only", function()
            local c = fresh()
            c:CreateProfile("Raid healing")
            h.truthy(c:SwitchProfile("Coffee - Suramar"))
            h.eq(c.profileName, "Coffee - Suramar")
            h.falsy(c:SwitchProfile("Nope"))
        end)

        h.it("renames, following the active profile", function()
            local c = fresh()
            c:Bindings()[1] = { id = "b1", key = { button = "BUTTON1" },
                action = { kind = "spell", spell = "Rejuvenation" } }
            h.truthy(c:RenameProfile("Coffee - Suramar", "Main"))
            h.eq(c.profileName, "Main")
            h.eq(#env.HealMeDB.profiles["Main"].bindings, 1)
            h.eq(env.HealMeDB.profiles["Coffee - Suramar"], nil)
        end)

        h.it("refuses to rename onto an existing profile", function()
            local c = fresh()
            c:CreateProfile("Raid healing")
            local ok, err = c:RenameProfile("Raid healing", "Coffee - Suramar")
            h.falsy(ok)
            h.truthy(err:find("already exists"))
        end)

        h.it("deletes any profile but the active one", function()
            local c = fresh()
            c:CreateProfile("Raid healing")
            local ok, err = c:DeleteProfile("Raid healing")
            h.falsy(ok)
            h.truthy(err:find("active"))
            c:SwitchProfile("Coffee - Suramar")
            h.truthy(c:DeleteProfile("Raid healing"))
            h.eq(env.HealMeDB.profiles["Raid healing"], nil)
        end)

        h.it("summarises every profile with count, active and spec flags", function()
            local c = fresh()
            c:Bindings()[1] = { id = "b1", key = { button = "BUTTON1" },
                action = { kind = "spell", spell = "Rejuvenation" } }
            c:CreateProfile("Raid healing")
            local list = c:ProfileSummaries()
            h.eq(#list, 2)
            h.eq(list[1].name, "Coffee - Suramar")
            h.eq(list[1].count, 1)
            h.eq(list[1].active, false)
            h.eq(list[1].spec, true)
            h.eq(list[2].name, "Raid healing")
            h.eq(list[2].active, true)
            h.eq(list[2].spec, false)
        end)
    end)
end
