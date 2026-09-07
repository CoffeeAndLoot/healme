local addonName, ns = ...
ns = ns or {}

local Options = {}
ns.Options = Options

-- A standalone window rather than a page inside Blizzard's Settings canvas.
-- HealMe ships no widget library, so every control here is built from base
-- frames. Dropdowns in particular are hand-rolled: Blizzard reworked its
-- dropdown templates in 11.x and a wrong template name is a silent nil frame,
-- which is a miserable thing to diagnose. Sixty lines of our own has nothing
-- to guess at.

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

local selectedId = nil
local ui = {}

---------------------------------------------------------------------------
-- Small widget helpers
---------------------------------------------------------------------------

local function backdrop(frame, alpha)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        frame:SetBackdropColor(0, 0, 0, alpha or 0.85)
        frame:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    else
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, alpha or 0.85)
    end
end

local function label(parent, text, size)
    local fs = parent:CreateFontString(nil, "ARTWORK",
        size == "large" and "GameFontNormalLarge" or "GameFontNormal")
    fs:SetText(text)
    return fs
end

local function button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function checkbox(parent, text, onToggle)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c.label = c:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c.label:SetText(text)
    c:SetScript("OnClick", function(self)
        onToggle(self:GetChecked() and true or false)
    end)
    return c
end

local function editbox(parent, width, onCommit)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetScript("OnEnterPressed", function(self)
        onCommit(self:GetText())
        self:ClearFocus()
    end)
    e:SetScript("OnEditFocusLost", function(self)
        onCommit(self:GetText())
    end)
    e:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        Options:Refresh()
    end)
    return e
end

-- A dropdown built from a button plus a popup list. No Blizzard dropdown
-- template is involved, so nothing here can break when those are reworked.
local function dropdown(parent, width, order, labels, onSelect)
    local d = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    d:SetSize(width, 22)

    local list = CreateFrame("Frame", nil, UIParent)
    list:SetFrameStrata("DIALOG")
    list:Hide()
    backdrop(list, 0.95)

    local rows = {}
    for i = 1, #order do
        local value = order[i]
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(18)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -2 - (i - 1) * 18)
        row:SetPoint("RIGHT", list, "RIGHT", -4, 0)

        local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        text:SetPoint("LEFT", 4, 0)
        text:SetText(labels[value] or value)
        text:SetJustifyH("LEFT")

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)

        row:SetScript("OnClick", function()
            list:Hide()
            onSelect(value)
        end)
        rows[i] = row
    end

    list:SetSize(width, #order * 18 + 6)

    d:SetScript("OnClick", function(self)
        if list:IsShown() then
            list:Hide()
        else
            list:ClearAllPoints()
            list:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, 0)
            list:Show()
            list:Raise()
        end
    end)

    d.list = list
    d.SetValue = function(self, value)
        self:SetText(labels[value or ""] or tostring(value))
    end

    return d
end

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

local function describe(record)
    local mods = ""
    if record.key.alt then mods = mods .. "Alt+" end
    if record.key.ctrl then mods = mods .. "Ctrl+" end
    if record.key.shift then mods = mods .. "Shift+" end

    local combo = mods .. (BUTTON_LABEL[record.key.button] or record.key.button or "?")

    local what
    if record.action.kind == "spell" then
        what = (record.action.spell ~= "" and record.action.spell) or "(no spell)"
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

    return combo .. "  \194\187  " .. what .. suffix
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

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function buildWindow()
    local f = CreateFrame("Frame", "HealMeOptionsFrame", UIParent, "BackdropTemplate")
    f:SetSize(680, 460)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    backdrop(f)

    -- Escape closes it, like any other panel.
    tinsert(UISpecialFrames, "HealMeOptionsFrame")

    local title = label(f, "HealMe", "large")
    title:SetPoint("TOPLEFT", 14, -12)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    ui.profile = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ui.profile:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -2)

    ui.alsoTarget = checkbox(f, "Also target when casting", function(value)
        ns.Core:Settings().alsoTarget = value
        ns.Core:NotifyChanged()
    end)
    ui.alsoTarget:SetPoint("TOPLEFT", 12, -52)

    local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", ui.alsoTarget, "BOTTOMLEFT", 4, -2)
    hint:SetText("Bindings fire on whichever unit frame is under your cursor.")

    ---------------------------------------------------------------- list
    local listBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 12, -100)
    listBg:SetSize(280, 310)
    backdrop(listBg, 0.4)

    local scroll = CreateFrame("ScrollFrame", "HealMeBindingScroll", listBg,
        "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(250, 1)
    scroll:SetScrollChild(content)
    ui.listContent = content
    ui.rows = {}

    ui.newButton = button(f, "New binding", 120, function()
        local list = bindings()
        local record = {
            id = ns.Bindings.NextId(list),
            -- Created disabled: it lands on plain left click with no spell, and
            -- if it were live it would overwrite an existing left-click binding
            -- with a cast of nothing on the next compile.
            enabled = false,
            key = { button = "BUTTON1" },
            action = { kind = "spell", spell = "" },
        }
        list[#list + 1] = record
        selectedId = record.id
        Options:Refresh()
    end)
    ui.newButton:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 0, -8)

    ui.deleteButton = button(f, "Delete", 100, function()
        local _, index = find(selectedId)
        if index then
            table.remove(bindings(), index)
            selectedId = nil
            ns.Core:NotifyChanged()
            Options:Refresh()
        end
    end)
    ui.deleteButton:SetPoint("LEFT", ui.newButton, "RIGHT", 8, 0)

    -------------------------------------------------------------- editor
    local ed = CreateFrame("Frame", nil, f, "BackdropTemplate")
    ed:SetPoint("TOPLEFT", listBg, "TOPRIGHT", 12, 0)
    ed:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 46)
    backdrop(ed, 0.4)
    ui.editor = ed

    local y = -10

    ui.enabled = checkbox(ed, "Enabled", function(value)
        local r = selected()
        if not r then return end
        local previous = r.enabled
        r.enabled = value
        commit(r, function() r.enabled = previous end)
    end)
    ui.enabled:SetPoint("TOPLEFT", 8, y)
    y = y - 30

    local buttonLabel = label(ed, "Button")
    buttonLabel:SetPoint("TOPLEFT", 12, y)
    ui.button = dropdown(ed, 140, ns.Compiler.BUTTONS, BUTTON_LABEL, function(value)
        local r = selected()
        if not r then return end
        local previous = r.key.button
        r.key.button = value
        commit(r, function() r.key.button = previous end)
    end)
    ui.button:SetPoint("TOPLEFT", 100, y + 4)
    y = y - 28

    local function modToggle(field, text, x)
        local c = checkbox(ed, text, function(value)
            local r = selected()
            if not r then return end
            local previous = r.key[field]
            r.key[field] = value or nil
            commit(r, function() r.key[field] = previous end)
        end)
        c:SetPoint("TOPLEFT", x, y)
        return c
    end

    ui.shift = modToggle("shift", "Shift", 12)
    ui.ctrl = modToggle("ctrl", "Ctrl", 100)
    ui.alt = modToggle("alt", "Alt", 180)
    y = y - 32

    local kindLabel = label(ed, "Action")
    kindLabel:SetPoint("TOPLEFT", 12, y)
    ui.kind = dropdown(ed, 160, KIND_ORDER, KIND_LABEL, function(value)
        local r = selected()
        if not r then return end
        local previousKind = r.action.kind
        local previousConditions = r.conditions
        r.action.kind = value
        if value == "togglemenu" then
            -- No macro command opens a unit popup, so a conditional togglemenu
            -- could never compile; Validate rejects it.
            r.conditions = nil
        end
        commit(r, function()
            r.action.kind = previousKind
            r.conditions = previousConditions
        end)
    end)
    ui.kind:SetPoint("TOPLEFT", 100, y + 4)
    y = y - 30

    ui.spellLabel = label(ed, "Spell")
    ui.spellLabel:SetPoint("TOPLEFT", 12, y)
    ui.spell = editbox(ed, 200, function(text)
        local r = selected()
        if not r then return end
        local previous = r.action.spell
        r.action.spell = text
        commit(r, function() r.action.spell = previous end)
    end)
    ui.spell:SetPoint("TOPLEFT", 104, y + 4)

    ui.macroLabel = label(ed, "Macro")
    ui.macroLabel:SetPoint("TOPLEFT", 12, y)
    ui.macro = editbox(ed, 200, function(text)
        local r = selected()
        if not r then return end
        local previous = r.action.macrotext
        r.action.macrotext = text
        commit(r, function() r.action.macrotext = previous end)
    end)
    ui.macro:SetPoint("TOPLEFT", 104, y + 4)
    y = y - 34

    ui.condLabel = label(ed, "Only when")
    ui.condLabel:SetPoint("TOPLEFT", 12, y)
    y = y - 24

    ui.unit = dropdown(ed, 160, UNIT_ORDER, UNIT_LABEL, function(value)
        local r = selected()
        if not r then return end
        r.conditions = r.conditions or {}
        r.conditions.unitFilter = (value ~= "" and value) or nil
        commit(r)
    end)
    ui.unit:SetPoint("TOPLEFT", 24, y)
    y = y - 26

    ui.life = dropdown(ed, 160, LIFE_ORDER, LIFE_LABEL, function(value)
        local r = selected()
        if not r then return end
        r.conditions = r.conditions or {}
        r.conditions.aliveOnly = (value == "alive") or nil
        r.conditions.deadOnly = (value == "dead") or nil
        commit(r)
    end)
    ui.life:SetPoint("TOPLEFT", 24, y)
    y = y - 26

    ui.combat = dropdown(ed, 160, COMBAT_ORDER, COMBAT_LABEL, function(value)
        local r = selected()
        if not r then return end
        r.conditions = r.conditions or {}
        if value == "in" then
            r.conditions.combat = true
        elseif value == "out" then
            r.conditions.combat = false
        else
            r.conditions.combat = nil
        end
        commit(r)
    end)
    ui.combat:SetPoint("TOPLEFT", 24, y)

    ---------------------------------------------------------- share row
    ui.exportButton = button(f, "Export", 100, function()
        Options:ShowShare("export")
    end)
    ui.exportButton:SetPoint("BOTTOMLEFT", 12, 14)

    ui.importButton = button(f, "Import", 100, function()
        Options:ShowShare("import")
    end)
    ui.importButton:SetPoint("LEFT", ui.exportButton, "RIGHT", 8, 0)

    return f
end

---------------------------------------------------------------------------
-- Share window
---------------------------------------------------------------------------

function Options:ShowShare(mode)
    if not ui.share then
        local s = CreateFrame("Frame", "HealMeShareFrame", UIParent, "BackdropTemplate")
        s:SetSize(460, 260)
        s:SetPoint("CENTER")
        s:SetMovable(true)
        s:EnableMouse(true)
        s:RegisterForDrag("LeftButton")
        s:SetScript("OnDragStart", s.StartMoving)
        s:SetScript("OnDragStop", s.StopMovingOrSizing)
        backdrop(s)
        tinsert(UISpecialFrames, "HealMeShareFrame")

        s.title = label(s, "", "large")
        s.title:SetPoint("TOPLEFT", 14, -12)

        local close = CreateFrame("Button", nil, s, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)

        s.hint = s:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        s.hint:SetPoint("TOPLEFT", 16, -38)

        local scroll = CreateFrame("ScrollFrame", "HealMeShareScroll", s,
            "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -58)
        scroll:SetPoint("BOTTOMRIGHT", -34, 46)

        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetFontObject("ChatFontNormal")
        box:SetWidth(390)
        box:SetAutoFocus(false)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(box)
        s.box = box

        s.action = button(s, "", 140, function()
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
        s.action:SetPoint("BOTTOMLEFT", 14, 14)

        ui.share = s
    end

    local s = ui.share
    s.mode = mode

    if mode == "export" then
        s.title:SetText("Export bindings")
        s.hint:SetText("Copy this string with Ctrl+C.")
        s.action:SetText("Select all")
        s.box:SetText(ns.Serialize.Export({
            bindings = ns.Core:Bindings(),
            settings = ns.Core:Settings(),
        }, ns.Serialize.codec))
    else
        s.title:SetText("Import bindings")
        s.hint:SetText("Paste a string. This replaces every binding in this profile.")
        s.action:SetText("Import")
        s.box:SetText("")
    end

    s:Show()
    s:Raise()
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function Options:Refresh()
    local f = ui.frame
    if not f or not f:IsShown() then
        return
    end

    ui.profile:SetText("Profile: " .. tostring(ns.Core.profileName))
    ui.alsoTarget:SetChecked(ns.Core:Settings().alsoTarget and true or false)

    local list = bindings()

    -- Rows are created once and reused; the list is short and rebuilding
    -- frames on every refresh would leak them.
    for i = 1, #list do
        local row = ui.rows[i]
        if not row then
            row = CreateFrame("Button", nil, ui.listContent)
            row:SetSize(246, 18)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 18)

            row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 4, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWidth(238)

            row.sel = row:CreateTexture(nil, "BACKGROUND")
            row.sel:SetAllPoints()
            row.sel:SetColorTexture(0.2, 0.5, 0.9, 0.35)
            row.sel:Hide()

            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.12)

            ui.rows[i] = row
        end

        local record = list[i]
        row.bindingId = record.id
        row.text:SetText(describe(record))
        if record.enabled == false then
            row.text:SetTextColor(0.6, 0.6, 0.6)
        else
            row.text:SetTextColor(1, 1, 1)
        end
        row.sel:SetShown(record.id == selectedId)
        row:SetScript("OnClick", function(self)
            selectedId = self.bindingId
            Options:Refresh()
        end)
        row:Show()
    end

    for i = #list + 1, #ui.rows do
        ui.rows[i]:Hide()
    end

    ui.listContent:SetHeight(math.max(1, #list * 18))

    local record = selected()
    ui.editor:SetShown(record ~= nil)
    ui.deleteButton:SetEnabled(record ~= nil)

    if not record then
        return
    end

    ui.enabled:SetChecked(record.enabled ~= false)
    ui.button:SetValue(record.key.button)
    ui.shift:SetChecked(record.key.shift and true or false)
    ui.ctrl:SetChecked(record.key.ctrl and true or false)
    ui.alt:SetChecked(record.key.alt and true or false)
    ui.kind:SetValue(record.action.kind)

    local isSpell = record.action.kind == "spell"
    local isMacro = record.action.kind == "macro"

    ui.spellLabel:SetShown(isSpell)
    ui.spell:SetShown(isSpell)
    if isSpell then
        ui.spell:SetText(record.action.spell or "")
    end

    ui.macroLabel:SetShown(isMacro)
    ui.macro:SetShown(isMacro)
    if isMacro then
        ui.macro:SetText(record.action.macrotext or "")
    end

    -- togglemenu cannot carry conditions, and an author's macro carries its own.
    local showConditions = not (record.action.kind == "togglemenu" or isMacro)
    ui.condLabel:SetShown(showConditions)
    ui.unit:SetShown(showConditions)
    ui.life:SetShown(showConditions)
    ui.combat:SetShown(showConditions)

    if showConditions then
        local c = record.conditions or {}
        ui.unit:SetValue(c.unitFilter or "")
        ui.life:SetValue((c.deadOnly and "dead") or (c.aliveOnly and "alive") or "")
        ui.combat:SetValue((c.combat == true and "in")
            or (c.combat == false and "out") or "")
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function Options:Initialize()
    ui.frame = buildWindow()
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
