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
    env.geterrorhandler = function() return function(e) error(e) end end

    local ns = {}
    local chunk
    if setfenv then
        chunk = assert(loadfile("HealMe/Core.lua"))
        setfenv(chunk, env)
    else
        chunk = assert(loadfile("HealMe/Core.lua", "t", env))
    end
    local Core = chunk("HealMe", ns)

    local function fresh()
        env.HealMeDB = { version = 1, profiles = {} }
        Core.profileName = nil
        Core:SetProfile("Coffee - Suramar")
        return Core
    end

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
