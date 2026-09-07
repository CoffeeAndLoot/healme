return function(h)
    local env = setmetatable({}, { __index = _G })
    env.CreateFrame = function()
        local box = { scripts = {}, text = "draft", focused = true }
        box.SetSize = function() end
        box.SetAutoFocus = function() end
        function box:SetScript(event, fn) self.scripts[event] = fn end
        function box:GetText() return self.text end
        function box:ClearFocus()
            if self.focused then
                self.focused = false
                self.scripts.OnEditFocusLost(self)
            end
        end
        return box
    end
    local chunk
    if setfenv then
        chunk = assert(loadfile("HealMe/Widgets.lua"))
        setfenv(chunk, env)
    else
        -- The 5.2+ form; the 5.1 branch above is what the client runs.
        ---@diagnostic disable-next-line: redundant-parameter
        chunk = assert(loadfile("HealMe/Widgets.lua", "t", env))
    end
    local widgets = chunk()
    h.describe("Text editing", function()
        h.it("Escape cancels without committing", function()
            local saved, cancelled = 0, 0
            local box = widgets.EditBox(nil, 200, function() saved = saved + 1 end,
                function() cancelled = cancelled + 1 end)
            box.scripts.OnEscapePressed(box)
            h.eq(saved, 0)
            h.eq(cancelled, 1)
        end)
        h.it("Enter commits exactly once", function()
            local saved = 0
            local box = widgets.EditBox(nil, 200, function() saved = saved + 1 end)
            box.scripts.OnEnterPressed(box)
            h.eq(saved, 1)
        end)
        h.it("Leaving a field commits", function()
            local saved
            local box = widgets.EditBox(nil, 200, function(value) saved = value end)
            box:ClearFocus()
            h.eq(saved, "draft")
        end)
    end)
end
