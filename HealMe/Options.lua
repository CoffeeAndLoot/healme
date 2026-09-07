local addonName, ns = ...
ns = ns or {}

local Options = {}
ns.Options = Options

-- A standalone portrait window in the style of Blizzard's own panels: tabs
-- under the title bar, dark insets, spellbook-style rows. Every control comes
-- from Widgets.lua.

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

local HEADER_HEIGHT = 26
local ROW_HEIGHT = 38
local LIST_WIDTH = 300

local W -- ns.Widgets, bound in Initialize

local selectedId = nil
local collapsed = {}
local ui = {}

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
        ns.Core:Print("rejected: " .. err)
        if restore then restore() end
        Options:Refresh()
        return false
    end

    local clash = ns.Bindings.FindConflict(bindings(), record)
    if clash then
        ns.Core:Print("that combination is already used by: " .. describe(clash))
        if restore then restore() end
        Options:Refresh()
        return false
    end

    ns.Core:NotifyChanged()
    Options:Refresh()
    return true
end

-- Wraps an editor handler so it only runs with a selected record and gets
-- the record plus a restore hook for commit.
local function edit(apply)
    return function(value)
        local r = selected()
        if not r then return end
        local restore = apply(r, value)
        commit(r, restore)
    end
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local function buildTabs(f)
    local function tab(index, text)
        local t = CreateFrame("Button", "HealMeOptionsFrameTab" .. index, f,
            "PanelTopTabButtonTemplate")
        t:SetID(index)
        t:SetText(text)
        if PanelTemplates_TabResize then
            pcall(PanelTemplates_TabResize, t, 16)
        end
        t:SetScript("OnClick", function()
            Options:SelectTab(index)
        end)
        return t
    end

    f.Tabs = { tab(1, "Bindings"), tab(2, "Settings") }
    if PanelTemplates_SetNumTabs then
        PanelTemplates_SetNumTabs(f, #f.Tabs)
    end
end

function Options:SelectTab(index)
    local f = ui.frame
    if PanelTemplates_SetTab then
        PanelTemplates_SetTab(f, index)
    end
    ui.bindingsPage:SetShown(index == 1)
    ui.settingsPage:SetShown(index == 2)
    ui.newButton:SetShown(index == 1)
    ui.deleteButton:SetShown(index == 1)
    self:Refresh()
end

---------------------------------------------------------------------------
-- Bindings page
---------------------------------------------------------------------------

local function buildList(page)
    local inset = W.Inset(page)
    inset:SetPoint("TOPLEFT", 0, 0)
    inset:SetPoint("BOTTOMLEFT", 0, 0)
    inset:SetWidth(LIST_WIDTH)

    local scroll = W.ScrollFrame(inset, LIST_WIDTH - 22)
    ui.listContent = scroll.content
    ui.headers = {}
    ui.rows = {}

    -- Shown when the profile holds nothing, so the empty pane invites action.
    ui.listEmpty = inset:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    ui.listEmpty:SetPoint("CENTER")
    ui.listEmpty:SetWidth(220)
    ui.listEmpty:SetText("No bindings yet.\nPress New binding to add one.")

    return inset
end

local function newHeader(index)
    local content = ui.listContent
    local h = CreateFrame("Button", nil, content)
    h:SetSize(content:GetWidth(), HEADER_HEIGHT)

    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.06)

    local top = h:CreateTexture(nil, "BORDER")
    top:SetHeight(1)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetColorTexture(0, 0, 0, 0.6)

    local bottom = h:CreateTexture(nil, "BORDER")
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetColorTexture(0, 0, 0, 0.6)

    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    h.text = h:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    h.text:SetPoint("LEFT", 10, 0)
    h.text:SetJustifyH("LEFT")

    h.count = h:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    h.count:SetPoint("LEFT", h.text, "RIGHT", 6, -1)

    h.toggle = h:CreateTexture(nil, "ARTWORK")
    h.toggle:SetSize(16, 16)
    h.toggle:SetPoint("RIGHT", -8, 0)

    h:SetScript("OnClick", function(self)
        collapsed[self.button] = not collapsed[self.button]
        Options:Refresh()
    end)

    ui.headers[index] = h
    return h
end

local function newRow(index)
    local content = ui.listContent
    local row = CreateFrame("Button", nil, content)
    row:SetSize(content:GetWidth(), ROW_HEIGHT)

    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(1, 0.82, 0, 0.1)
    row.sel:Hide()

    row.bar = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.bar:SetWidth(2)
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetColorTexture(1, 0.82, 0, 0.9)
    row.bar:Hide()

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    row.icon = W.Icon(row, 28)
    row.icon:SetPoint("LEFT", 12, 0)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
    row.name:SetPoint("RIGHT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.detail = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
    row.detail:SetPoint("RIGHT", -8, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        selectedId = self.bindingId
        Options:Refresh()
    end)

    ui.rows[index] = row
    return row
end

local function buildEditor(page, list)
    local inset = W.Inset(page)
    inset:SetPoint("TOPLEFT", list, "TOPRIGHT", 8, 0)
    inset:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.editor = inset

    ui.emptyHint = inset:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    ui.emptyHint:SetPoint("CENTER")
    ui.emptyHint:SetWidth(280)
    ui.emptyHint:SetText("Pick a binding on the left to edit it.")

    -- The header: the thing you bound, big, the way the housing dashboard
    -- names the house. It is the one loud element in the window.
    ui.headerIcon = W.Icon(inset, 40)
    ui.headerIcon:SetPoint("TOPLEFT", 18, -18)

    ui.headerName = inset:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    ui.headerName:SetPoint("TOPLEFT", ui.headerIcon, "TOPRIGHT", 12, 0)
    ui.headerName:SetPoint("RIGHT", -120, 0)
    ui.headerName:SetJustifyH("LEFT")
    ui.headerName:SetWordWrap(false)

    ui.headerCombo = inset:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    ui.headerCombo:SetPoint("BOTTOMLEFT", ui.headerIcon, "BOTTOMRIGHT", 12, 0)
    ui.headerCombo:SetJustifyH("LEFT")

    ui.enabled = W.Checkbox(inset, "Enabled", edit(function(r, value)
        local previous = r.enabled
        r.enabled = value
        return function() r.enabled = previous end
    end))
    ui.enabled:SetPoint("TOPRIGHT", -84, -24)

    ui.headerRule = inset:CreateTexture(nil, "ARTWORK")
    ui.headerRule:SetHeight(1)
    ui.headerRule:SetPoint("TOPLEFT", ui.headerIcon, "BOTTOMLEFT", 0, -14)
    ui.headerRule:SetPoint("RIGHT", -18, 0)
    ui.headerRule:SetColorTexture(1, 0.82, 0, 0.25)

    -- Form rows: gold label in the left column, control in the right.
    local LABEL_X, CONTROL_X = 20, 130
    local y = -92
    ui.fields = {}

    local function fieldLabel(text)
        local fs = inset:CreateFontString(nil, "ARTWORK", "GameFontNormal")
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
    ui.button = place(W.Dropdown(inset, 170, ns.Compiler.BUTTONS, BUTTON_LABEL,
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
    ui.kind = place(W.Dropdown(inset, 170, KIND_ORDER, KIND_LABEL,
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
    ui.spellLabel = inset:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    ui.spellLabel:SetPoint("TOPLEFT", LABEL_X, y - 4)
    ui.spellLabel:SetText("Spell")
    ui.spell = W.EditBox(inset, 220, edit(function(r, text)
        local previous = r.action.spell
        r.action.spell = text
        return function() r.action.spell = previous end
    end), function() Options:Refresh() end)
    ui.spell:SetPoint("TOPLEFT", CONTROL_X + 6, y)

    ui.macroLabel = inset:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    ui.macroLabel:SetPoint("TOPLEFT", LABEL_X, y - 4)
    ui.macroLabel:SetText("Macro")
    ui.macro = W.EditBox(inset, 220, edit(function(r, text)
        local previous = r.action.macrotext
        r.action.macrotext = text
        return function() r.action.macrotext = previous end
    end), function() Options:Refresh() end)
    ui.macro:SetPoint("TOPLEFT", CONTROL_X + 6, y)
    y = y - 44

    -- Conditions get their own heading, like a second section of a page.
    ui.condHeading = W.Heading(inset, "Only when")
    ui.condHeading:SetPoint("TOPLEFT", LABEL_X, y)
    ui.condHeading.rule:SetPoint("RIGHT", inset, "RIGHT", -18, 0)
    y = y - 36

    ui.condFields = {}
    local function condLabel(text)
        local fs = inset:CreateFontString(nil, "ARTWORK", "GameFontNormal")
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
    ui.unit = condControl(W.Dropdown(inset, 170, UNIT_ORDER, UNIT_LABEL,
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
    ui.life = condControl(W.Dropdown(inset, 170, LIFE_ORDER, LIFE_LABEL,
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
    ui.combat = condControl(W.Dropdown(inset, 170, COMBAT_ORDER, COMBAT_LABEL,
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

local function buildBindingsPage(f, area)
    local page = CreateFrame("Frame", nil, f)
    page:SetAllPoints(area)
    ui.bindingsPage = page

    local list = buildList(page)
    buildEditor(page, list)

    ui.newButton = W.Button(f, "New binding", 120, function()
        local list = bindings()
        local record = {
            id = ns.Bindings.NextId(list),
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
    ui.newButton:SetPoint("BOTTOMLEFT", 10, 6)

    ui.deleteButton = W.Button(f, "Delete", 100, function()
        local _, index = find(selectedId)
        if index then
            table.remove(bindings(), index)
            selectedId = nil
            ns.Core:NotifyChanged()
            Options:Refresh()
        end
    end)
    ui.deleteButton:SetPoint("LEFT", ui.newButton, "RIGHT", 6, 0)
end

---------------------------------------------------------------------------
-- Settings page
---------------------------------------------------------------------------

local function buildSettingsPage(f, area)
    local page = CreateFrame("Frame", nil, f)
    page:SetAllPoints(area)
    page:Hide()
    ui.settingsPage = page

    local inset = W.Inset(page)
    inset:SetAllPoints()

    local X = 24
    local y = -20

    local function section(title)
        local h = W.Heading(inset, title)
        h:SetPoint("TOPLEFT", X, y)
        h.rule:SetPoint("RIGHT", inset, "RIGHT", -24, 0)
        y = y - 34
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
-- Window
---------------------------------------------------------------------------

local function buildWindow()
    local f = W.Window("HealMeOptionsFrame", "HealMe", 740, 560)

    buildTabs(f)

    -- The content area sits under the tab strip and above the button bar.
    local area = CreateFrame("Frame", nil, f)
    area:SetPoint("TOPLEFT", 10, -64)
    area:SetPoint("BOTTOMRIGHT", -10, 34)

    f.Tabs[1]:SetPoint("BOTTOMLEFT", area, "TOPLEFT", 54, 1)
    f.Tabs[2]:SetPoint("LEFT", f.Tabs[1], "RIGHT", 2, 0)

    -- Profile picker on the right of the tab strip, where the housing
    -- dashboard keeps its house picker.
    ui.profile = W.Dropdown(f, 230, function() return ns.Core:ProfileNames() end, {},
        function() return ns.Core.profileName end,
        function(name)
            ns.Core:SetProfile(name)
            selectedId = nil
            ns.Core:NotifyChanged()
        end)
    ui.profile:SetPoint("BOTTOMRIGHT", area, "TOPRIGHT", -2, 6)

    buildBindingsPage(f, area)
    buildSettingsPage(f, area)

    return f
end

---------------------------------------------------------------------------
-- Share window
---------------------------------------------------------------------------

function Options:ShowShare(mode)
    if not ui.share then
        local s = W.Window("HealMeShareFrame", "", 480, 300)
        s:SetFrameStrata("DIALOG")

        s.hint = s:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        s.hint:SetPoint("TOPLEFT", 64, -34)
        s.hint:SetPoint("RIGHT", -16, 0)
        s.hint:SetJustifyH("LEFT")

        local inset = W.Inset(s)
        inset:SetPoint("TOPLEFT", 10, -64)
        inset:SetPoint("BOTTOMRIGHT", -10, 34)

        local scroll = W.ScrollFrame(inset, 430)
        local box = CreateFrame("EditBox", nil, scroll.content)
        box:SetPoint("TOPLEFT", 6, -6)
        box:SetWidth(420)
        box:SetMultiLine(true)
        box:SetFontObject("ChatFontNormal")
        box:SetAutoFocus(false)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        box:SetScript("OnTextChanged", function(self)
            scroll.content:SetHeight(math.max(1, self:GetHeight() + 12))
        end)
        -- Clicking anywhere in the pane focuses the box, as a text area should.
        inset:EnableMouse(true)
        inset:SetScript("OnMouseDown", function() box:SetFocus() end)
        s.box = box

        s.action = W.Button(s, "", 140, function()
            if s.mode == "import" then
                local profile, err = ns.Serialize.Import(s.box:GetText(),
                    ns.Serialize.codec)
                if not profile then
                    ns.Core:Print("import failed: " .. err)
                    return
                end
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
            else
                s.box:HighlightText()
                s.box:SetFocus()
            end
        end)
        s.action:SetPoint("BOTTOMRIGHT", -10, 6)

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
    if s.SetTitle then s:SetTitle(title) elseif s.TitleText then s.TitleText:SetText(title) end

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
        h.toggle:SetTexture(isCollapsed and "Interface\\Buttons\\UI-PlusButton-Up"
            or "Interface\\Buttons\\UI-MinusButton-Up")
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h:Show()
        y = y + HEADER_HEIGHT

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
                    row.name:SetTextColor(0.55, 0.55, 0.55)
                    row.detail:SetTextColor(0.5, 0.45, 0.3)
                else
                    row.name:SetTextColor(1, 1, 1)
                    row.detail:SetTextColor(1, 0.82, 0)
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
    ui.deleteButton:SetEnabled(record ~= nil)
    ui.emptyHint:SetShown(record == nil)

    local headerWidgets = {
        ui.headerIcon, ui.headerName, ui.headerCombo, ui.headerRule, ui.enabled,
    }
    for i = 1, #headerWidgets do headerWidgets[i]:SetShown(record ~= nil) end
    for i = 1, #ui.fields do ui.fields[i]:SetShown(record ~= nil) end

    if not record then
        ui.spellLabel:Hide()
        ui.spell:Hide()
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

    local isSpell = record.action.kind == "spell"
    local isMacro = record.action.kind == "macro"

    ui.spellLabel:SetShown(isSpell)
    ui.spell:SetShown(isSpell)
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
    ui.alsoTarget:SetChecked(ns.Core:Settings().alsoTarget and true or false)
    ui.minimap:SetChecked(not ns.MinimapButton:IsHidden())

    refreshList()
    refreshEditor()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function Options:Initialize()
    W = ns.Widgets
    ui.frame = buildWindow()
    self:SelectTab(1)
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
