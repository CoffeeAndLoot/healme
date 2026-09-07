local addonName, ns = ...
ns = ns or {}

local Widgets = {}
ns.Widgets = Widgets

-- The panel is built from Blizzard's own templates so it reads as a built-in
-- window. The one template Blizzard reworked recently, the dropdown, is
-- constructed defensively: if the client does not have it the control falls
-- back to a hand-built list, so a renamed template costs the look, not the
-- addon.

local ICON = "Interface\\AddOns\\HealMe\\Media\\icon"
Widgets.ICON = ICON

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local KIND_ICON = {
    macro      = "Interface\\Icons\\INV_Misc_Note_01",
    target     = "Interface\\Icons\\Ability_Hunter_SniperShot",
    focus      = "Interface\\Icons\\Ability_Hunter_MasterMarksman",
    togglemenu = "Interface\\Icons\\INV_Misc_Book_09",
}

-- The texture for a binding's action. Spell art comes from the client and is
-- not a secret value, so it can be shown; an unknown spell name gets the
-- question mark rather than an empty square.
function Widgets.ActionIcon(action)
    if action.kind ~= "spell" then
        return KIND_ICON[action.kind] or FALLBACK_ICON
    end
    local name = action.spell
    if name and name ~= "" and C_Spell and C_Spell.GetSpellTexture then
        local ok, texture = pcall(C_Spell.GetSpellTexture, name)
        if ok and texture then
            return texture
        end
    end
    return FALLBACK_ICON
end

-- A square icon with the thin dark-gold rim the spellbook uses.
function Widgets.Icon(parent, size)
    local rim = parent:CreateTexture(nil, "BORDER")
    rim:SetSize(size + 2, size + 2)
    rim:SetColorTexture(0.55, 0.45, 0.2, 1)

    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint("CENTER", rim, "CENTER")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    rim.icon = icon
    rim.SetIcon = function(self, texture)
        self.icon:SetTexture(texture)
    end
    rim.SetDimmed = function(self, dimmed)
        self.icon:SetDesaturated(dimmed)
        self.icon:SetAlpha(dimmed and 0.5 or 1)
        self:SetAlpha(dimmed and 0.5 or 1)
    end
    return rim
end

-- A gold heading with the hairline underneath, like the house name on the
-- housing dashboard.
function Widgets.Heading(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormalLarge")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")

    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
    rule:SetColorTexture(1, 0.82, 0, 0.25)
    fs.rule = rule
    return fs
end

function Widgets.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 100, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

function Widgets.Checkbox(parent, text, onToggle)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(26, 26)
    c.label = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c.label:SetText(text)
    c:SetScript("OnClick", function(self)
        onToggle(self:GetChecked() and true or false)
    end)
    return c
end

function Widgets.EditBox(parent, width, onCommit, onCancel)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 22)
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
        if onCancel then onCancel() end
    end)
    return e
end

---------------------------------------------------------------------------
-- Dropdown
---------------------------------------------------------------------------

local function itemsOf(items)
    if type(items) == "function" then
        return items()
    end
    return items
end

-- The hand-built list used when the client lacks the modern template. Rows
-- are laid out each time the list opens so a changing item set stays right.
local function fallbackDropdown(parent, width, items, labels, current, onSelect)
    local d = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    d:SetSize(width, 22)

    local list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    list:SetFrameStrata("DIALOG")
    list:Hide()
    list:SetBackdrop({
        bgFile = "Interface\Buttons\WHITE8X8",
        edgeFile = "Interface\Buttons\WHITE8X8",
        edgeSize = 1,
    })
    list:SetBackdropColor(0, 0, 0, 0.95)
    list:SetBackdropBorderColor(0.4, 0.35, 0.2, 1)

    local rows = {}
    local function row(i)
        if rows[i] then return rows[i] end
        local r = CreateFrame("Button", nil, list)
        r:SetHeight(18)
        r:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -2 - (i - 1) * 18)
        r:SetPoint("RIGHT", list, "RIGHT", -4, 0)
        r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 4, 0)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.15)
        r:SetScript("OnClick", function(self)
            list:Hide()
            onSelect(self.value)
        end)
        rows[i] = r
        return r
    end

    local function open(anchor)
        local order = itemsOf(items)
        for i = 1, #order do
            local r = row(i)
            r.value = order[i]
            r.text:SetText(labels[order[i]] or order[i])
            r:Show()
        end
        for i = #order + 1, #rows do rows[i]:Hide() end
        list:SetSize(width, #order * 18 + 6)
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
        list:Show()
        list:Raise()
    end

    d:SetScript("OnClick", function(self)
        if list:IsShown() then
            list:Hide()
        else
            open(self)
        end
    end)

    d.Refresh = function(self)
        local value = current()
        self:SetText(labels[value or ""] or tostring(value))
    end
    return d
end

-- `items` is the ordered value list, or a function returning one for sets
-- that change. `current` returns the selected value; `onSelect` receives a
-- chosen one. Call :Refresh() after the underlying value changes.
function Widgets.Dropdown(parent, width, items, labels, current, onSelect)
    local ok, d = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    if not ok or not d or not d.SetupMenu then
        return fallbackDropdown(parent, width, items, labels, current, onSelect)
    end

    d:SetWidth(width)
    d:SetupMenu(function(_, root)
        local order = itemsOf(items)
        for i = 1, #order do
            local value = order[i]
            root:CreateRadio(labels[value] or value,
                function() return current() == value end,
                function() onSelect(value) end)
        end
    end)

    d.Refresh = function(self)
        if self.GenerateMenu then
            self:GenerateMenu()
        end
    end
    return d
end

---------------------------------------------------------------------------
-- Scrolling list
---------------------------------------------------------------------------

-- A scroll frame with the slim modern bar that hides itself when there is
-- nothing to scroll. The wheel handler is set first so the list scrolls even
-- if the bar cannot be built.
function Widgets.ScrollFrame(parent, contentWidth)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, self:GetScrollChild():GetHeight() - self:GetHeight())
        local target = self:GetVerticalScroll() - delta * 36
        self:SetVerticalScroll(math.max(0, math.min(max, target)))
    end)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(contentWidth, 1)
    scroll:SetScrollChild(content)
    scroll.content = content

    local okBar, bar = pcall(CreateFrame, "EventFrame", nil, parent, "MinimalScrollBar")
    if okBar and bar and ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", -12, -2)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -12, 2)
        pcall(ScrollUtil.InitScrollFrameWithScrollBar, scroll, bar)
        if bar.SetHideIfUnscrollable then
            bar:SetHideIfUnscrollable(true)
        end
    end
    return scroll
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

-- A portrait window: round icon in the corner, gold title bar, close button,
-- dark stone background, and the bottom strip for buttons.
function Widgets.Window(name, title, width, height)
    local f = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    -- Escape closes it, like any other panel.
    tinsert(UISpecialFrames, name)

    if f.SetTitle then
        f:SetTitle(title)
    elseif f.TitleText then
        f.TitleText:SetText(title)
    end

    if f.SetPortraitToAsset then
        f:SetPortraitToAsset(ICON)
    else
        local portrait = (f.PortraitContainer and f.PortraitContainer.portrait) or f.portrait
        if portrait then
            portrait:SetTexture(ICON)
        end
    end

    -- The template's own inset is sized for a single pane; the callers lay
    -- out their own.
    if f.Inset then
        f.Inset:Hide()
    end

    return f
end

function Widgets.Inset(parent)
    return CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
end

return Widgets
