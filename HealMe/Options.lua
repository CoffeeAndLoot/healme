local _, ns = ...
ns = ns or {}

local Options = {}
ns.Options = Options

-- A standalone portrait window laid out like the Housing dashboard: tabs
-- under the title bar, the dark scene with filigree corners, quest-log style
-- group headers, spellbook-style rows. Every control comes from Widgets.lua.

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
local KIND_ORDER = { "spell", "macro", "target", "focus", "togglemenu" }

local UNIT_LABEL = { [""] = "Anyone", help = "Friendly only", harm = "Hostile only" }
local UNIT_ORDER = { "", "help", "harm" }

local LIFE_LABEL = { [""] = "Alive or dead", alive = "Alive only", dead = "Dead only" }
local LIFE_ORDER = { "", "alive", "dead" }

local COMBAT_LABEL = { [""] = "Always", ["in"] = "In combat", out = "Out of combat" }
local COMBAT_ORDER = { "", "in", "out" }

local FRAME_LABEL = {
    player = "Player", target = "Target", focus = "Focus", pet = "Pet",
    party = "Party", raid = "Raid", other = "Other addon frames",
}

local HEADER_HEIGHT = 24
local ROW_HEIGHT = 46
local LIST_WIDTH = 270
local MARGIN = 20

local W -- ns.Widgets, bound in Initialize

local selectedId = nil
local selectedProfile = nil
local profileError = nil
local collapsed = {}
local ui = {}
local editError, errorBindingId

---------------------------------------------------------------------------
-- State helpers
---------------------------------------------------------------------------

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

local function selected()
    return (find(selectedId))
end

local function modifierText(key)
    local parts = {}
    if key.shift then parts[#parts + 1] = "Shift" end
    if key.ctrl then parts[#parts + 1] = "Ctrl" end
    if key.alt then parts[#parts + 1] = "Alt" end
    return table.concat(parts, "+")
end

local function actionText(action)
    if action.kind == "spell" then
        return (action.spell ~= "" and action.spell) or "No spell yet"
    elseif action.kind == "macro" then
        return "Macro"
    end
    return KIND_LABEL[action.kind] or action.kind
end

-- "Shift+Ctrl + Left click", or just "Left click".
local function comboText(key)
    local mods = modifierText(key)
    local button = BUTTON_LABEL[key.button] or key.button or "?"
    if mods == "" then
        return button
    end
    return mods .. " + " .. button
end

-- "Party, Raid" for a limited binding, nil for one that applies everywhere.
local function framesText(frames)
    if not frames then
        return nil
    end
    local names = ns.Bindings.FrameList(frames)
    if #names == 0 then
        return nil
    end
    for i = 1, #names do
        names[i] = FRAME_LABEL[names[i]] or names[i]
    end
    return table.concat(names, ", ")
end

-- The gold subline under a list row: modifiers, then conditions in words.
local function detailText(record)
    local parts = {}
    local mods = modifierText(record.key)
    parts[#parts + 1] = (mods ~= "" and mods) or "No modifier"

    local c = record.conditions
    if c then
        if c.unitFilter == "help" then parts[#parts + 1] = "friendly" end
        if c.unitFilter == "harm" then parts[#parts + 1] = "hostile" end
        if c.aliveOnly then parts[#parts + 1] = "alive" end
        if c.deadOnly then parts[#parts + 1] = "dead" end
        if c.combat == true then parts[#parts + 1] = "in combat" end
        if c.combat == false then parts[#parts + 1] = "out of combat" end
    end
    local frames = framesText(record.frames)
    if frames then
        parts[#parts + 1] = "on " .. frames
    end
    if record.enabled == false then
        parts[#parts + 1] = "disabled"
    end
    return table.concat(parts, ", ")
end

local function describe(record)
    return comboText(record.key) .. ": " .. actionText(record.action)
end

-- Saves an edit, refusing anything Validate or FindConflict rejects and
-- restoring the previous value so a rejected edit never persists.
local function commit(record, restore)
    local ok, err = ns.Bindings.Validate(record, ns.Core:ValidationDeps())
    if not ok then
        editError, errorBindingId = err, record.id
        ns.Core:Print("rejected: " .. err)
        if restore then restore() end
        Options:Refresh()
        return false
    end

    local clash = ns.Bindings.FindConflict(bindings(), record)
    if clash then
        editError = "Already used by " .. describe(clash)
        errorBindingId = record.id
        ns.Core:Print("that combination is already used by: " .. describe(clash))
        if restore then restore() end
        Options:Refresh()
        return false
    end

    editError, errorBindingId = nil, nil
    ns.Core:NotifyChanged()
    Options:Refresh()
    return true
end

-- Wraps an editor handler so it only runs with a selected record and gets
-- the record plus a restore hook for commit.
local function edit(apply)
    return function(...)
        local r = selected()
        if not r then return end
        commit(r, apply(r, ...))
    end
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

-- Pages in tab order; each page's refresh runs only while it is shown.
function Options:SelectTab(index)
    ui.activeTab = index
    for i = 1, #ui.pages do
        ui.pages[i].frame:SetShown(i == index)
    end
    self:Refresh()
end

---------------------------------------------------------------------------
-- Bindings page
---------------------------------------------------------------------------

local function buildList(page)
    local panel = W.Panel(page)
    panel:SetPoint("TOPLEFT", MARGIN, -MARGIN)
    panel:SetPoint("BOTTOMLEFT", MARGIN, MARGIN + 34)
    panel:SetWidth(LIST_WIDTH)

    local scroll = W.ScrollFrame(panel, LIST_WIDTH - 22)
    ui.listContent = scroll.content
    ui.headers = {}
    ui.rows = {}

    -- Shown when the profile holds nothing, so the empty pane invites action.
    ui.listEmpty = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    ui.listEmpty:SetPoint("CENTER")
    ui.listEmpty:SetWidth(220)
    ui.listEmpty:SetText("No bindings yet.\nPress New binding to add one.")

    return panel
end

local function newHeader(index)
    local content = ui.listContent
    local h = W.ListHeader(content, content:GetWidth(), HEADER_HEIGHT, function(self)
        collapsed[self.button] = not collapsed[self.button]
        Options:Refresh()
    end)
    ui.headers[index] = h
    return h
end

local function newRow(index)
    local content = ui.listContent
    local row = W.ListRow(content, content:GetWidth(), ROW_HEIGHT, 32)
    row:SetScript("OnClick", function(self)
        selectedId = self.bindingId
        Options:Refresh()
    end)

    ui.rows[index] = row
    return row
end

local function buildEditor(page, list)
    -- A compact identity header leaves room for long spell names. Editing
    -- actions live in the footer, away from the title.
    local header = W.Panel(page)
    header:SetPoint("TOPLEFT", list, "TOPRIGHT", 24, 0)
    header:SetPoint("RIGHT", -MARGIN, 0)
    header:SetHeight(62)

    ui.headerIcon = W.Icon(header, 42)
    ui.headerIcon:SetPoint("TOPLEFT", 12, -10)

    ui.headerName = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    ui.headerName:SetPoint("TOPLEFT", ui.headerIcon, "TOPRIGHT", 14, -4)
    ui.headerName:SetPoint("RIGHT", -8, 0)
    ui.headerName:SetJustifyH("LEFT")
    ui.headerName:SetWordWrap(false)

    ui.headerRule = W.Divider(header, 188)
    ui.headerRule:SetPoint("TOPLEFT", ui.headerName, "BOTTOMLEFT", -10, -4)

    ui.headerCombo = header:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    ui.headerCombo:SetPoint("TOPLEFT", ui.headerName, "BOTTOMLEFT", 0, -10)
    ui.headerCombo:SetJustifyH("LEFT")

    ui.enabled = W.Checkbox(page, "Enabled", edit(function(r, value)
        local previous = r.enabled
        r.enabled = value
        return function() r.enabled = previous end
    end))
    ui.enabled:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 24, -32)

    -- The form on a dark plate beneath the header.
    local inset = W.Panel(page)
    inset:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    -- Runs to the bottom margin: the New and Delete buttons live under the
    -- list, not under this plate, so the form gets the full height.
    inset:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
    ui.editor = inset
    ui.error = inset:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ui.error:SetPoint("BOTTOMLEFT", 20, 4)
    ui.error:SetPoint("RIGHT", -20, 0)
    ui.error:SetHeight(24)
    ui.error:SetJustifyH("LEFT")
    ui.error:SetTextColor(1, 0.45, 0.35)

    ui.emptyHint = inset:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    ui.emptyHint:SetPoint("CENTER")
    ui.emptyHint:SetWidth(280)
    ui.emptyHint:SetText("Pick a binding on the left to edit it.")

    -- Everything that only makes sense with a binding selected, header
    -- included, hides together through this list.
    ui.fields = { ui.headerIcon, ui.headerName, ui.headerCombo, ui.headerRule, ui.enabled }

    -- Neutral field labels keep gold reserved for section headings.
    local LABEL_X, CONTROL_X = 20, 126
    local y = -18

    local function fieldLabel(text)
        local fs = inset:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", LABEL_X, y - 4)
        fs:SetText(text)
        ui.fields[#ui.fields + 1] = fs
        return fs
    end

    local function place(control, x)
        control:SetPoint("TOPLEFT", x or CONTROL_X, y)
        ui.fields[#ui.fields + 1] = control
        return control
    end

    fieldLabel("Mouse button")
    ui.button = place(W.Dropdown(inset, 240, ns.Compiler.BUTTONS, BUTTON_LABEL,
        function() local r = selected() return r and r.key.button end,
        edit(function(r, value)
            local previous = r.key.button
            r.key.button = value
            return function() r.key.button = previous end
        end)))
    y = y - 32

    fieldLabel("Hold")
    local function modToggle(field, text, x)
        return place(W.Checkbox(inset, text, edit(function(r, value)
            local previous = r.key[field]
            r.key[field] = value or nil
            return function() r.key[field] = previous end
        end)), x)
    end
    ui.shift = modToggle("shift", "Shift", CONTROL_X - 4)
    ui.ctrl = modToggle("ctrl", "Ctrl", CONTROL_X + 76)
    ui.alt = modToggle("alt", "Alt", CONTROL_X + 148)
    y = y - 36

    fieldLabel("Action")
    ui.kind = place(W.Dropdown(inset, 240, KIND_ORDER, KIND_LABEL,
        function() local r = selected() return r and r.action.kind end,
        edit(function(r, value)
            local previousKind = r.action.kind
            local previousConditions = r.conditions
            r.action.kind = value
            if value == "togglemenu" then
                -- No macro command opens a unit popup, so a conditional
                -- togglemenu could never compile; Validate rejects it.
                r.conditions = nil
            end
            return function()
                r.action.kind = previousKind
                r.conditions = previousConditions
            end
        end)))
    y = y - 32

    -- Spell and macro share a row; Refresh shows whichever applies.
    ui.spellLabel = inset:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    ui.spellLabel:SetPoint("TOPLEFT", LABEL_X, y - 4)
    ui.spellLabel:SetText("Spell")
    local setSpell = edit(function(r, text)
        local previous = r.action.spell
        r.action.spell = text
        return function() r.action.spell = previous end
    end)
    ui.spell = W.EditBox(inset, 200, setSpell, function() Options:Refresh() end)
    ui.spell:SetPoint("TOPLEFT", CONTROL_X + 6, y)

    -- Picks from the spellbook by filling the field; the field stays the
    -- value, so anything the book does not list can still be typed.
    ui.spellPick = W.SpellbookPicker(inset, 110, function(name)
        ui.spell:SetText(name)
        setSpell(name)
    end)
    if ui.spellPick then
        ui.spellPick:SetPoint("LEFT", ui.spell, "RIGHT", 8, 0)
    end

    ui.spellHint = inset:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ui.spellHint:SetPoint("TOPLEFT", ui.spell, "BOTTOMLEFT", 0, -5)
    ui.spellHint:SetText("Pick from the spellbook, or type a name. Enter saves; Escape cancels.")
    ui.spellHint:SetTextColor(0.65, 0.65, 0.6)

    ui.macroLabel = inset:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    ui.macroLabel:SetPoint("TOPLEFT", LABEL_X, y - 4)
    ui.macroLabel:SetText("Macro")
    ui.macro = W.EditBox(inset, 220, edit(function(r, text)
        local previous = r.action.macrotext
        r.action.macrotext = text
        return function() r.action.macrotext = previous end
    end), function() Options:Refresh() end)
    ui.macro:SetPoint("TOPLEFT", CONTROL_X + 6, y)
    y = y - 54

    -- Which frames the binding fires on. Orthogonal to the conditions, and
    -- meaningful for every action kind, so it sits above that section.
    fieldLabel("On frames")
    local editFrames = edit(function(r, class, on)
        local previous = r.frames
        local set = {}
        for i = 1, #ns.Bindings.FRAMES do
            local kind = ns.Bindings.FRAMES[i]
            if ns.Bindings.FrameAllowed(r, kind) then
                set[kind] = true
            end
        end
        set[class] = on or nil
        -- Every kind ticked is the same as no limit; none ticked is refused
        -- by Validate, so the revert puts the box back.
        local count = 0
        for _ in pairs(set) do count = count + 1 end
        r.frames = (count < #ns.Bindings.FRAMES and set) or nil
        return function() r.frames = previous end
    end)
    ui.frames = place(W.MultiDropdown(inset, 240, ns.Bindings.FRAMES, FRAME_LABEL,
        function(class)
            local r = selected()
            return r ~= nil and ns.Bindings.FrameAllowed(r, class)
        end,
        editFrames,
        function()
            local r = selected()
            return (r and framesText(r.frames)) or "All frames"
        end))
    y = y - 32

    -- Conditions get their own heading, like a second section of a page.
    ui.condHeading = W.Heading(inset, "Conditions", 340)
    ui.condHeading:SetPoint("TOPLEFT", LABEL_X, y)
    y = y - 36

    ui.condFields = {}
    local function condLabel(text)
        local fs = inset:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", LABEL_X, y - 4)
        fs:SetText(text)
        ui.condFields[#ui.condFields + 1] = fs
    end
    local function condControl(control)
        control:SetPoint("TOPLEFT", CONTROL_X, y)
        ui.condFields[#ui.condFields + 1] = control
        return control
    end

    condLabel("Target is")
    ui.unit = condControl(W.Dropdown(inset, 240, UNIT_ORDER, UNIT_LABEL,
        function()
            local r = selected()
            return r and ((r.conditions and r.conditions.unitFilter) or "")
        end,
        edit(function(r, value)
            r.conditions = r.conditions or {}
            r.conditions.unitFilter = (value ~= "" and value) or nil
        end)))
    y = y - 30

    condLabel("Life")
    ui.life = condControl(W.Dropdown(inset, 240, LIFE_ORDER, LIFE_LABEL,
        function()
            local r = selected()
            local c = r and r.conditions or {}
            return r and ((c.deadOnly and "dead") or (c.aliveOnly and "alive") or "")
        end,
        edit(function(r, value)
            r.conditions = r.conditions or {}
            r.conditions.aliveOnly = (value == "alive") or nil
            r.conditions.deadOnly = (value == "dead") or nil
        end)))
    y = y - 30

    condLabel("Combat")
    ui.combat = condControl(W.Dropdown(inset, 240, COMBAT_ORDER, COMBAT_LABEL,
        function()
            local r = selected()
            local c = r and r.conditions or {}
            return r and ((c.combat == true and "in") or (c.combat == false and "out") or "")
        end,
        edit(function(r, value)
            r.conditions = r.conditions or {}
            if value == "in" then
                r.conditions.combat = true
            elseif value == "out" then
                r.conditions.combat = false
            else
                r.conditions.combat = nil
            end
        end)))

    return inset
end

local function buildBindingsPage(f)
    local page = CreateFrame("Frame", nil, f.content)
    page:SetAllPoints()
    ui.bindingsPage = page

    local list = buildList(page)
    buildEditor(page, list)

    -- Creation belongs to the list; selection actions belong to the editor.
    ui.newButton = W.Button(page, "New binding", 120, function()
        local records = bindings()
        local record = {
            id = ns.Bindings.NextId(records),
            -- Created disabled: it lands on plain left click with no spell,
            -- and if it were live it would overwrite an existing left-click
            -- binding with a cast of nothing on the next compile.
            enabled = false,
            key = { button = "BUTTON1" },
            action = { kind = "spell", spell = "" },
        }
        list[#list + 1] = record
        selectedId = record.id
        collapsed[record.key.button] = nil
        Options:Refresh()
    end)
    ui.newButton:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -8)
    ui.newButton:SetWidth(140)

    ui.deleteButton = W.Button(page, "Delete", 100, function()
        local record = find(selectedId)
        if not record then
            return
        end
        W.Confirm("Delete the binding " .. describe(record) .. "?", function()
            local _, again = find(record.id)
            if again then
                table.remove(bindings(), again)
            end
            selectedId = nil
            ns.Core:NotifyChanged()
            Options:Refresh()
        end)
    end)
    ui.deleteButton:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -MARGIN, MARGIN + 4)
end

---------------------------------------------------------------------------
-- Profiles page
---------------------------------------------------------------------------

-- Runs a Core profile call and keeps its error for the plate to show.
local function profileAction(ok, err)
    profileError = (not ok and err) or nil
    Options:Refresh()
end

local function newProfileRow(index)
    local content = ui.profileContent
    local row = W.ListRow(content, content:GetWidth(), ROW_HEIGHT)
    row:SetScript("OnClick", function(self)
        selectedProfile = self.profileName
        profileError = nil
        Options:Refresh()
    end)

    ui.profileRows[index] = row
    return row
end

local function buildProfilesPage(f)
    local page = CreateFrame("Frame", nil, f.content)
    page:SetAllPoints()
    page:Hide()
    ui.profilesPage = page

    ------------------------------------------------------------ list
    local list = W.Panel(page)
    list:SetPoint("TOPLEFT", MARGIN, -MARGIN)
    list:SetPoint("BOTTOMLEFT", MARGIN, MARGIN + 34)
    list:SetWidth(LIST_WIDTH)

    local scroll = W.ScrollFrame(list, LIST_WIDTH - 22)
    ui.profileContent = scroll.content
    ui.profileRows = {}

    -- Creating: a name and a button under the list, where New binding sits
    -- on the other tab.
    ui.newProfileName = W.EditBox(page, LIST_WIDTH - 130, function() end)
    ui.newProfileName:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 6, -8)
    ui.newProfileButton = W.Button(page, "New profile", 110, function()
        local ok, err = ns.Core:CreateProfile(ui.newProfileName:GetText())
        if ok then
            ui.newProfileName:SetText("")
            selectedProfile = ns.Core.profileName
        end
        profileAction(ok, err)
    end)
    ui.newProfileButton:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -8)

    ------------------------------------------------------------ actions
    local header = CreateFrame("Frame", nil, page)
    header:SetPoint("TOPLEFT", list, "TOPRIGHT", 24, 0)
    header:SetPoint("RIGHT", -MARGIN, 0)
    header:SetHeight(62)

    ui.profileIcon = W.Icon(header, 58)
    ui.profileIcon:SetPoint("TOPLEFT", 0, -4)
    ui.profileIcon:SetIcon(W.ICON)

    ui.profileTitle = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    ui.profileTitle:SetPoint("TOPLEFT", ui.profileIcon, "TOPRIGHT", 14, -4)
    ui.profileTitle:SetPoint("RIGHT", 0, 0)
    ui.profileTitle:SetJustifyH("LEFT")
    ui.profileTitle:SetWordWrap(false)

    ui.profileRule = W.Divider(header, 188)
    ui.profileRule:SetPoint("TOPLEFT", ui.profileTitle, "BOTTOMLEFT", -10, -4)

    ui.profileState = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    ui.profileState:SetPoint("TOPLEFT", ui.profileTitle, "BOTTOMLEFT", 0, -10)
    ui.profileState:SetJustifyH("LEFT")

    local plate = W.Panel(page)
    plate:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    plate:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)

    ui.profileEmpty = plate:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    ui.profileEmpty:SetPoint("CENTER")
    ui.profileEmpty:SetWidth(280)
    ui.profileEmpty:SetText("Pick a profile on the left.")

    ui.profileError = plate:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ui.profileError:SetPoint("BOTTOMLEFT", 20, 4)
    ui.profileError:SetPoint("RIGHT", -20, 0)
    ui.profileError:SetHeight(24)
    ui.profileError:SetJustifyH("LEFT")
    ui.profileError:SetTextColor(1, 0.45, 0.35)

    local X = 20
    local y = -18
    ui.profileWidgets = {}
    local function keep(w)
        ui.profileWidgets[#ui.profileWidgets + 1] = w
        return w
    end

    local function heading(text)
        local h = keep(W.Heading(plate, text, 340))
        h:SetPoint("TOPLEFT", X, y)
        keep(h.rule)
        y = y - 36
    end

    local function note(text)
        local fs = keep(plate:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
        fs:SetPoint("TOPLEFT", X + 10, y)
        fs:SetPoint("RIGHT", -20, 0)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        fs:SetTextColor(0.65, 0.65, 0.6)
        y = y - 30
    end

    heading("Selected profile")

    ui.switchButton = keep(W.Button(plate, "Switch to", 120, function()
        profileAction(ns.Core:SwitchProfile(selectedProfile))
    end))
    ui.switchButton:SetPoint("TOPLEFT", X + 4, y)

    ui.copyButton = keep(W.Button(plate, "Copy into active", 140, function()
        local ok = ns.Core:CopyProfileFrom(selectedProfile)
        profileAction(ok, (not ok) and "the active profile cannot copy from itself" or nil)
    end))
    ui.copyButton:SetPoint("LEFT", ui.switchButton, "RIGHT", 8, 0)

    ui.deleteProfileButton = keep(W.Button(plate, "Delete", 100, function()
        local name = selectedProfile
        W.Confirm("Delete the profile " .. tostring(name) .. " and every binding in it?",
            function()
                local ok, err = ns.Core:DeleteProfile(name)
                if ok then selectedProfile = nil end
                profileAction(ok, err)
            end)
    end))
    ui.deleteProfileButton:SetPoint("LEFT", ui.copyButton, "RIGHT", 8, 0)
    y = y - 28
    note("Copy replaces every binding in the active profile with this one's.")
    y = y - 6

    local renameLabel = keep(plate:CreateFontString(nil, "ARTWORK", "GameFontHighlight"))
    renameLabel:SetPoint("TOPLEFT", X, y - 4)
    renameLabel:SetText("Rename")
    ui.renameBox = keep(W.EditBox(plate, 230, function() end))
    ui.renameBox:SetPoint("TOPLEFT", X + 106, y)
    ui.renameButton = keep(W.Button(plate, "Rename", 100, function()
        local ok, result = ns.Core:RenameProfile(selectedProfile, ui.renameBox:GetText())
        if ok then
            selectedProfile = result
            profileAction(true)
        else
            profileAction(false, result)
        end
    end))
    ui.renameButton:SetPoint("LEFT", ui.renameBox, "RIGHT", 8, 0)
    y = y - 30
    ui.renameNote = keep(W.Note(plate))
    ui.renameNote:SetPoint("TOPLEFT", X + 10, y)
    ui.renameNote:SetPoint("RIGHT", -20, 0)
    y = y - 40

    heading("Active profile")
    ui.resetButton = keep(W.Button(plate, "Reset to empty", 140, function()
        W.Confirm("Remove every binding from " .. tostring(ns.Core.profileName) .. "?",
            function()
                ns.Core:ResetProfile()
                profileAction(true)
            end)
    end))
    ui.resetButton:SetPoint("TOPLEFT", X + 4, y)
    y = y - 28
    note("Removes every binding from the active profile. Export first if you might want them back.")
    y = y - 6

    -- Which profile this spec uses solo, in a party and in a raid. Applies
    -- on spec change and on every group change; a manual pick holds until
    -- the next one.
    ui.rulesHeading = W.Heading(plate, "Automatic switching", 340)
    ui.rulesHeading:SetPoint("TOPLEFT", X, y)
    y = y - 36

    local RULE_LABEL = { solo = "Solo", party = "In a party", raid = "In a raid" }
    ui.rules = {}
    for i = 1, #ns.Core.GROUP_TYPES do
        local groupType = ns.Core.GROUP_TYPES[i]
        local label = plate:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("TOPLEFT", X, y - 4)
        label:SetText(RULE_LABEL[groupType])
        ui.rules[groupType] = W.Dropdown(plate, 240,
            function()
                local items = { "" }
                local names = ns.Core:ProfileNames()
                for n = 1, #names do items[#items + 1] = names[n] end
                return items
            end,
            setmetatable({ [""] = "Default (this spec's profile)" }, {
                __index = function(_, name) return name end,
            }),
            function() return ns.Core:Rules()[groupType] or "" end,
            function(value)
                ns.Core:SetRule(groupType, value)
                profileAction(true)
            end)
        ui.rules[groupType]:SetPoint("TOPLEFT", X + 106, y)
        y = y - 30
    end
    local rulesNote = W.Note(plate, "Rules apply when your spec or group changes. "
        .. "A profile you pick by hand stays until the next change.")
    rulesNote:SetPoint("TOPLEFT", X + 10, y)
    rulesNote:SetPoint("RIGHT", -20, 0)
end

-- "5 bindings, active, this spec"
local function profileText(info)
    local parts = { W.Plural(info.count, "binding") }
    if info.active then parts[#parts + 1] = "active" end
    if info.spec then parts[#parts + 1] = "this spec" end
    return table.concat(parts, ", ")
end

local function refreshProfiles()
    local list = ns.Core:ProfileSummaries()

    -- There is always an active profile, so the plate never has to sit
    -- empty: land on it until the player picks another.
    if not selectedProfile then
        selectedProfile = ns.Core.profileName
    end
    local y = 0
    local found = false
    for i = 1, #list do
        local info = list[i]
        local row = ui.profileRows[i] or newProfileRow(i)
        row.profileName = info.name
        row.name:SetText(info.name)

        row.detail:SetText(profileText(info))
        row.detail:SetTextColor(1, 0.82, 0)

        local isSelected = info.name == selectedProfile
        found = found or isSelected
        row:SetSelected(isSelected)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:Show()
        y = y + ROW_HEIGHT
    end
    for i = #list + 1, #ui.profileRows do ui.profileRows[i]:Hide() end
    ui.profileContent:SetHeight(math.max(1, y))

    if not found then
        selectedProfile = nil
    end

    local info = nil
    for i = 1, #list do
        if list[i].name == selectedProfile then info = list[i] end
    end

    for i = 1, #ui.profileWidgets do ui.profileWidgets[i]:SetShown(info ~= nil) end
    ui.profileEmpty:SetShown(info == nil)
    ui.profileIcon:SetShown(info ~= nil)
    ui.profileTitle:SetShown(info ~= nil)
    ui.profileRule:SetShown(info ~= nil)
    ui.profileState:SetShown(info ~= nil)
    ui.profileError:SetText(profileError or "")
    ui.profileError:SetShown(profileError ~= nil)

    -- The rules section belongs to the spec, not the selection, so it shows
    -- whenever the tab does.
    local spec = ns.Core:SpecName()
    ui.rulesHeading:SetText(spec and ("Automatic switching for " .. spec)
        or "Automatic switching")
    for _, dropdown in pairs(ui.rules) do
        dropdown:Refresh()
    end

    if not info then
        return
    end

    ui.profileTitle:SetText(info.name)
    ui.profileState:SetText(profileText(info))

    ui.switchButton:SetEnabled(not info.active)
    ui.copyButton:SetEnabled(not info.active)
    ui.deleteProfileButton:SetEnabled(not info.active)
    if not ui.renameBox:HasFocus() then
        ui.renameBox:SetText(info.name)
    end
    if info.spec then
        ui.renameNote:SetText("This is the profile your current spec returns to. Rename it and "
            .. "the next spec change creates a fresh, empty one under this name.")
        ui.renameNote:SetTextColor(1, 0.7, 0.4)
    else
        ui.renameNote:SetText("Enter a new name and press Rename.")
        ui.renameNote:SetTextColor(0.65, 0.65, 0.6)
    end
end

---------------------------------------------------------------------------
-- Settings page
---------------------------------------------------------------------------

local function buildSettingsPage(f)
    local page = CreateFrame("Frame", nil, f.content)
    page:SetAllPoints()
    page:Hide()
    ui.settingsPage = page

    local inset = W.Panel(page)
    inset:SetPoint("TOPLEFT", MARGIN, -MARGIN)
    inset:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)

    local X = 30
    local y = -24

    local function section(title)
        local h = W.Heading(inset, title, 260)
        h:SetPoint("TOPLEFT", X, y)
        y = y - 36
    end

    local function note(text)
        local fs = inset:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", X + 30, y)
        fs:SetWidth(520)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        y = y - 30
    end

    section("Casting")
    ui.alsoTarget = W.Checkbox(inset, "Also target when casting", function(value)
        ns.Core:Settings().alsoTarget = value
        ns.Core:NotifyChanged()
    end)
    ui.alsoTarget:SetPoint("TOPLEFT", X, y)
    y = y - 28
    note("A casting click also switches your target, so your action bar follows your mouse.")
    y = y - 10

    section("Minimap")
    ui.minimap = W.Checkbox(inset, "Show minimap button", function(value)
        ns.MinimapButton:SetHidden(not value)
    end)
    ui.minimap:SetPoint("TOPLEFT", X, y)
    y = y - 28
    note("The button opens this window. Right-click it to toggle Also target.")
    y = y - 10

    -- Blizzard's own click-casting runs beside HealMe; a native spell
    -- binding fires on every frame whatever HealMe's scope says. Show what
    -- is there and hand the player Blizzard's window.
    section("Blizzard click-casting")
    ui.nativeButton = W.Button(inset, "Open Click Casting", 160, function()
        ns.Native.OpenWindow()
    end)
    ui.nativeButton:SetPoint("TOPLEFT", X + 4, y)
    y = y - 28
    ui.nativeNote = W.Note(inset, nil, 520)
    ui.nativeNote:SetPoint("TOPLEFT", X + 30, y)
    y = y - 30
    y = y - 10

    section("Share bindings")
    ui.exportButton = W.Button(inset, "Export", 110, function()
        Options:ShowShare("export")
    end)
    ui.exportButton:SetPoint("TOPLEFT", X + 4, y)
    ui.importButton = W.Button(inset, "Import", 110, function()
        Options:ShowShare("import")
    end)
    ui.importButton:SetPoint("LEFT", ui.exportButton, "RIGHT", 8, 0)
    y = y - 28
    note("Export gives you a string to paste anywhere. Import replaces every binding in this profile.")
end

---------------------------------------------------------------------------
-- Help page
---------------------------------------------------------------------------

-- Topics from Help.lua as quest-log style headers with the text beneath.
-- The first opens by default; the rest start collapsed so the page fits.

local HELP_PAD = 14
local helpOpen = nil

local function buildHelpPage(f)
    local page = CreateFrame("Frame", nil, f.content)
    page:SetAllPoints()
    page:Hide()
    ui.helpPage = page

    local plate = W.Panel(page)
    plate:SetPoint("TOPLEFT", MARGIN, -MARGIN)
    plate:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)

    -- The scroll child needs a real width before text can wrap, and the
    -- plate's width is only known once the window is laid out, so size it
    -- from the window rather than asking the plate.
    local width = f:GetWidth() - 2 * MARGIN - 8 - 30
    local scroll = W.ScrollFrame(plate, width)
    ui.helpContent = scroll.content
    ui.helpHeaders = {}
    ui.helpBodies = {}

    local topics = ns.Help or {}
    for i = 1, #topics do
        local h = W.ListHeader(ui.helpContent, width, HEADER_HEIGHT + 4, function(self)
            helpOpen = (helpOpen == self.index) and nil or self.index
            Options:Refresh()
        end)
        h.index = i
        h.text:SetText(topics[i].title)
        h.count:SetText("")
        ui.helpHeaders[i] = h

        local body = ui.helpContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        body:SetWidth(width - 2 * HELP_PAD)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetSpacing(3)
        body:SetText(table.concat(topics[i].body, "\n\n"))
        ui.helpBodies[i] = body
    end
end

local function refreshHelp()
    if helpOpen == nil and #ui.helpHeaders > 0 then
        helpOpen = 1
    end

    local y = 0
    for i = 1, #ui.helpHeaders do
        local h, body = ui.helpHeaders[i], ui.helpBodies[i]
        local open = helpOpen == i
        h:SetCollapsed(not open)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        y = y + h:GetHeight() + 2

        body:SetShown(open)
        if open then
            body:ClearAllPoints()
            body:SetPoint("TOPLEFT", HELP_PAD, -(y + 8))
            y = y + 8 + body:GetStringHeight() + 16
        end
    end
    ui.helpContent:SetHeight(math.max(1, y))
end

local function refreshSettings()
    ui.alsoTarget:SetChecked(ns.Core:Settings().alsoTarget and true or false)
    ui.minimap:SetChecked(not ns.MinimapButton:IsHidden())

    -- Re-read each time the tab shows: the player may have just closed
    -- Blizzard's window.
    local native = ns.Native.Bindings()
    if #native == 0 then
        ui.nativeNote:SetText("Blizzard's click-casting has no spell bindings. Good: only HealMe casts.")
        ui.nativeNote:SetTextColor(0.65, 0.65, 0.6)
    else
        ui.nativeNote:SetText(ns.Native.Warning(native)
            .. ". Remove them there, or they ignore your frame scopes.")
        ui.nativeNote:SetTextColor(1, 0.45, 0.35)
    end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function buildWindow()
    -- The dashboard's width, and a taller frame than its 544: the editor form
    -- is long and the list benefits from the rows.
    local f = W.Window("HealMeOptionsFrame", "HealMe", 814, 640)

    -- Tabs and picker sit where the dashboard puts its own.
    ui.tabs = W.Tabs(f, { "Bindings", "Settings", "Profiles", "Help" }, function(index)
        Options:SelectTab(index)
    end)
    ui.tabs:SetPoint("BOTTOMLEFT", f.content, "TOPLEFT", 60, -1)

    ui.profile = W.Dropdown(f, 200, function() return ns.Core:ProfileNames() end, {},
        function() return ns.Core.profileName end,
        function(name)
            ns.Core:SetProfile(name)
            selectedId = nil
            ns.Core:NotifyChanged()
        end)
    ui.profile:SetPoint("TOPRIGHT", -10, -28)

    buildBindingsPage(f)
    buildProfilesPage(f)
    buildSettingsPage(f)
    buildHelpPage(f)

    return f
end

---------------------------------------------------------------------------
-- Share window
---------------------------------------------------------------------------

function Options:ShowShare(mode)
    if not ui.share then
        local s = W.Window("HealMeShareFrame", "", 500, 340)
        s:SetFrameStrata("DIALOG")

        s.hint = s.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        s.hint:SetPoint("TOPLEFT", MARGIN, -MARGIN)
        s.hint:SetPoint("RIGHT", -MARGIN, 0)
        s.hint:SetJustifyH("LEFT")

        local inset = W.Panel(s.content)
        inset:SetPoint("TOPLEFT", s.hint, "BOTTOMLEFT", 0, -10)
        inset:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN + 34)

        local scroll = W.ScrollFrame(inset, 430)
        local box = CreateFrame("EditBox", nil, scroll.content)
        box:SetPoint("TOPLEFT", 6, -6)
        box:SetWidth(420)
        box:SetMultiLine(true)
        box:SetFontObject("ChatFontNormal")
        box:SetAutoFocus(false)
        box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
        box:SetScript("OnTextChanged", function(b)
            scroll.content:SetHeight(math.max(1, b:GetHeight() + 12))
        end)
        -- Clicking anywhere in the pane focuses the box, as a text area should.
        inset:EnableMouse(true)
        inset:SetScript("OnMouseDown", function() box:SetFocus() end)
        s.box = box

        s.action = W.Button(s.content, "", 140, function()
            if s.mode == "import" then
                local profile, err = ns.Serialize.Import(s.box:GetText(),
                    ns.Serialize.codec)
                if not profile then
                    ns.Core:Print("import failed: " .. err)
                    return
                end
                -- Parsed before asking, so a bad string is refused without a
                -- pointless question; the replacement waits on Yes.
                local current = #ns.Core:Bindings()
                W.Confirm("Replace the " .. current .. " binding"
                    .. (current == 1 and "" or "s") .. " in " .. tostring(ns.Core.profileName)
                    .. " with the " .. #profile.bindings .. " from this string?", function()
                    local accepted, skipped = ns.Bindings.Sanitize(profile.bindings,
                        ns.Core:ValidationDeps())
                    ns.Core.db.profile.bindings = accepted
                    ns.Core.db.profile.settings.alsoTarget =
                        profile.settings.alsoTarget and true or false
                    selectedId = nil
                    ns.Core:NotifyChanged()
                    local message = "imported " .. #accepted .. " bindings"
                    if skipped > 0 then
                        message = message .. " (" .. skipped
                            .. " skipped: invalid or duplicate)"
                    end
                    ns.Core:Print(message)
                    s:Hide()
                    Options:Refresh()
                end)
            else
                s.box:HighlightText()
                s.box:SetFocus()
            end
        end)
        s.action:SetPoint("TOPRIGHT", inset, "BOTTOMRIGHT", 0, -8)

        ui.share = s
    end

    local s = ui.share
    s.mode = mode

    local title
    if mode == "export" then
        title = "Export bindings"
        s.hint:SetText("Copy this string with Ctrl+C.")
        s.action:SetText("Select all")
        s.box:SetText(ns.Serialize.Export({
            bindings = ns.Core:Bindings(),
            settings = ns.Core:Settings(),
        }, ns.Serialize.codec))
    else
        title = "Import bindings"
        s.hint:SetText("Paste a string here. It replaces every binding in this profile.")
        s.action:SetText("Import")
        s.box:SetText("")
    end
    s:SetTitle(title)

    s:Show()
    s:Raise()
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

-- Bindings grouped by mouse button, in the compiler's button order, so the
-- list reads like the quest log: a header per button, its bindings beneath.
local function groupedBindings()
    local list = bindings()
    local byButton = {}
    for i = 1, #list do
        local button = list[i].key.button or "?"
        byButton[button] = byButton[button] or {}
        table.insert(byButton[button], list[i])
    end

    local order = {}
    for i = 1, #ns.Compiler.BUTTONS do
        order[#order + 1] = ns.Compiler.BUTTONS[i]
    end
    for button in pairs(byButton) do
        if not BUTTON_LABEL[button] then
            order[#order + 1] = button
        end
    end

    local groups = {}
    for i = 1, #order do
        local records = byButton[order[i]]
        if records then
            table.sort(records, function(a, b)
                return modifierText(a.key) < modifierText(b.key)
            end)
            groups[#groups + 1] = { button = order[i], records = records }
        end
    end
    return groups
end

local function refreshList()
    local groups = groupedBindings()
    local headerIndex, rowIndex = 0, 0
    local y = 0

    for g = 1, #groups do
        local group = groups[g]
        headerIndex = headerIndex + 1
        local h = ui.headers[headerIndex] or newHeader(headerIndex)
        h.button = group.button
        h.text:SetText(BUTTON_LABEL[group.button] or group.button)
        h.count:SetText(tostring(#group.records))
        local isCollapsed = collapsed[group.button]
        h:SetCollapsed(isCollapsed)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h:Show()
        y = y + HEADER_HEIGHT + 2

        if not isCollapsed then
            for r = 1, #group.records do
                local record = group.records[r]
                rowIndex = rowIndex + 1
                local row = ui.rows[rowIndex] or newRow(rowIndex)
                row.bindingId = record.id
                row.icon:SetIcon(W.ActionIcon(record.action))
                row.name:SetText(actionText(record.action))
                row.detail:SetText(detailText(record))

                local disabled = record.enabled == false
                row.icon:SetDimmed(disabled)
                if disabled then
                    row.name:SetTextColor(0.7, 0.7, 0.65)
                    row.detail:SetTextColor(0.6, 0.6, 0.55)
                else
                    row.name:SetTextColor(1, 1, 1)
                    row.detail:SetTextColor(0.72, 0.72, 0.65)
                end

                local isSelected = record.id == selectedId
                row.sel:SetShown(isSelected)
                row.bar:SetShown(isSelected)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:Show()
                y = y + ROW_HEIGHT
            end
        end
    end

    for i = headerIndex + 1, #ui.headers do ui.headers[i]:Hide() end
    for i = rowIndex + 1, #ui.rows do ui.rows[i]:Hide() end

    ui.listContent:SetHeight(math.max(1, y))
    ui.listEmpty:SetShown(#groups == 0)
end

local function refreshEditor()
    local record = selected()
    if errorBindingId ~= selectedId then editError, errorBindingId = nil, nil end
    ui.error:SetText(editError or "")
    ui.error:SetShown(record ~= nil and editError ~= nil)
    ui.deleteButton:SetEnabled(record ~= nil)
    ui.emptyHint:SetShown(record == nil)

    for i = 1, #ui.fields do ui.fields[i]:SetShown(record ~= nil) end

    if not record then
        ui.spellLabel:Hide()
        ui.spell:Hide()
        ui.spellHint:Hide()
        if ui.spellPick then ui.spellPick:Hide() end
        ui.macroLabel:Hide()
        ui.macro:Hide()
        ui.condHeading:Hide()
        ui.condHeading.rule:Hide()
        for i = 1, #ui.condFields do ui.condFields[i]:Hide() end
        return
    end

    ui.headerIcon:SetIcon(W.ActionIcon(record.action))
    ui.headerIcon:SetDimmed(record.enabled == false)
    ui.headerName:SetText(actionText(record.action))
    ui.headerCombo:SetText(comboText(record.key))

    ui.enabled:SetChecked(record.enabled ~= false)
    ui.shift:SetChecked(record.key.shift and true or false)
    ui.ctrl:SetChecked(record.key.ctrl and true or false)
    ui.alt:SetChecked(record.key.alt and true or false)
    ui.button:Refresh()
    ui.kind:Refresh()
    ui.frames:Refresh()

    local isSpell = record.action.kind == "spell"
    local isMacro = record.action.kind == "macro"

    ui.spellLabel:SetShown(isSpell)
    ui.spell:SetShown(isSpell)
    ui.spellHint:SetShown(isSpell)
    if ui.spellPick then ui.spellPick:SetShown(isSpell) end
    if isSpell and not ui.spell:HasFocus() then
        ui.spell:SetText(record.action.spell or "")
    end

    ui.macroLabel:SetShown(isMacro)
    ui.macro:SetShown(isMacro)
    if isMacro and not ui.macro:HasFocus() then
        ui.macro:SetText(record.action.macrotext or "")
    end

    -- togglemenu cannot carry conditions, and an author's macro carries its own.
    local showConditions = not (record.action.kind == "togglemenu" or isMacro)
    ui.condHeading:SetShown(showConditions)
    ui.condHeading.rule:SetShown(showConditions)
    for i = 1, #ui.condFields do ui.condFields[i]:SetShown(showConditions) end
    if showConditions then
        ui.unit:Refresh()
        ui.life:Refresh()
        ui.combat:Refresh()
    end
end

function Options:Refresh()
    local f = ui.frame
    if not f or not f:IsShown() then
        return
    end

    ui.profile:Refresh()
    local page = ui.pages[ui.activeTab or 1]
    if page then
        page.refresh()
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function Options:Initialize()
    W = ns.Widgets
    ui.frame = buildWindow()
    -- Wired here, after every page's refresh function is in scope.
    ui.pages = {
        { frame = ui.bindingsPage, refresh = function() refreshList() refreshEditor() end },
        { frame = ui.settingsPage, refresh = refreshSettings },
        { frame = ui.profilesPage, refresh = refreshProfiles },
        { frame = ui.helpPage, refresh = refreshHelp },
    }
    ui.tabs:Select(1)
    ns.Core:RegisterListener(function()
        Options:Refresh()
    end)
end

function Options:Open()
    if not ui.frame then
        return
    end
    if ui.frame:IsShown() then
        ui.frame:Hide()
        return
    end
    ui.frame:Show()
    self:Refresh()
end

return Options
