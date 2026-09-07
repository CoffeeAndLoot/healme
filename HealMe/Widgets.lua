local addonName, ns = ...
ns = ns or {}

local Widgets = {}
ns.Widgets = Widgets

-- The panel is built from Blizzard's own templates and atlases so it reads as
-- a built-in window. Every atlas name and anchor here was taken from the
-- Housing dashboard, quest log and spellbook markup in Blizzard's UI source,
-- not guessed. Constructors check for the method they need and fall back to a
-- plainer control, so a renamed template costs the look, not the addon.

local ICON = "Interface\\AddOns\\HealMe\\Media\\icon"
Widgets.ICON = ICON

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local KIND_ICON = {
    macro      = "Interface\\Icons\\INV_Misc_Note_01",
    target     = "Interface\\Icons\\Ability_Hunter_SniperShot",
    focus      = "Interface\\Icons\\Ability_Hunter_MasterMarksman",
    togglemenu = "Interface\\Icons\\INV_Misc_Book_09",
}

-- Blizzard's art, by the name the client knows it under.
local ATLAS = {
    scene     = "housing-dashboard-bg-elwynn",
    corner    = {
        { "housing-dashboard-filigree-corner-TL", 54, 42, "TOPLEFT", -4, 2 },
        { "housing-dashboard-filigree-corner-TR", 54, 42, "TOPRIGHT", 4, 2 },
        { "housing-dashboard-filigree-corner-BL", 66, 50, "BOTTOMLEFT", -6, -2 },
        { "housing-dashboard-filigree-corner-BR", 66, 50, "BOTTOMRIGHT", 5, -2 },
    },
    divider   = "house-upgrade-header-divider-horz",
    iconBack  = "house-upgrade-reward-icon-background",
    iconFrame = "house-upgrade-reward-icon-frame-overlay",
    header    = "common-button-list-collapseExpand",
    plus      = "common-button-list-plus",
    minus     = "common-button-list-minus",
}
Widgets.ATLAS = ATLAS

local function atlasKnown(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- A texture showing a named atlas, or hidden if this client lacks it, so a
-- missing piece of art leaves a gap rather than a white square.
function Widgets.Atlas(parent, layer, name, sublevel)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    if atlasKnown(name) then
        t:SetAtlas(name)
    else
        t:Hide()
    end
    return t
end

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

-- A square icon in the housing dashboard's bevelled gold frame.
function Widgets.Icon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)

    local back = Widgets.Atlas(f, "BACKGROUND", ATLAS.iconBack)
    back:SetAllPoints()

    -- Plain dark-gold edge for a client without the atlas.
    local rim = f:CreateTexture(nil, "BORDER")
    rim:SetPoint("TOPLEFT", -1, 1)
    rim:SetPoint("BOTTOMRIGHT", 1, -1)
    rim:SetColorTexture(0.55, 0.45, 0.2, 1)
    rim:SetShown(not back:IsShown())

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local frame = Widgets.Atlas(f, "OVERLAY", ATLAS.iconFrame)
    frame:SetAllPoints()

    f.icon = icon
    f.SetIcon = function(self, texture)
        self.icon:SetTexture(texture)
    end
    f.SetDimmed = function(self, dimmed)
        self.icon:SetDesaturated(dimmed)
        self:SetAlpha(dimmed and 0.5 or 1)
    end
    return f
end

-- The ornate horizontal rule the dashboard draws under the house name.
function Widgets.Divider(parent, width)
    local d = Widgets.Atlas(parent, "ARTWORK", ATLAS.divider)
    d:SetSize(width, 2)
    if not d:IsShown() then
        d:SetColorTexture(1, 0.82, 0, 0.3)
        d:Show()
    end
    return d
end

-- A gold section heading with the ornate rule beneath it.
function Widgets.Heading(parent, text, width)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    fs.rule = Widgets.Divider(parent, width or 188)
    fs.rule:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", -10, -4)
    return fs
end

-- Gold scrollwork in the four corners of a frame, as on the dashboard.
function Widgets.Filigree(frame)
    for i = 1, #ATLAS.corner do
        local spec = ATLAS.corner[i]
        local t = Widgets.Atlas(frame, "OVERLAY", spec[1])
        t:SetSize(spec[2], spec[3])
        t:SetPoint(spec[4], spec[5], spec[6])
    end
end

-- Blizzard's inset frame supplies real bevelled metal corners and edges.
-- Warm stone stays visible beneath the shading instead of a flat black fill.
function Widgets.Panel(parent)
    local p = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
    if p.Bg then p.Bg:Hide() end

    local bg = p:CreateTexture(nil, "BACKGROUND", nil, -2)
    bg:SetAllPoints()
    bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
    bg:SetHorizTile(true)
    bg:SetVertTile(true)
    bg:SetVertexColor(0.65, 0.51, 0.36)

    local shade = p:CreateTexture(nil, "BACKGROUND", nil, -1)
    shade:SetAllPoints()
    shade:SetColorTexture(0.06, 0.035, 0.015, 0.48)
    return p
end

-- A quest-log style group header: the dark rounded bar, large shadowed
-- text, and the gold plus or minus at the right.
function Widgets.ListHeader(parent, width, height, onClick)
    local h = CreateFrame("Button", nil, parent)
    h:SetSize(width, height)

    if atlasKnown(ATLAS.header) then
        h:SetNormalAtlas(ATLAS.header)
        h:SetHighlightAtlas(ATLAS.header, "ADD")
        h:GetHighlightTexture():SetAlpha(0.4)
    else
        local bg = h:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.08)
        local hl = h:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
    end

    h.text = h:CreateFontString(nil, "ARTWORK", "Game15Font_Shadow")
    h.text:SetPoint("LEFT", 10, 1)
    h.text:SetJustifyH("LEFT")

    h.count = h:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    h.count:SetPoint("LEFT", h.text, "RIGHT", 6, 0)

    h.toggle = h:CreateTexture(nil, "ARTWORK")
    h.toggle:SetSize(16, 16)
    h.toggle:SetPoint("RIGHT", -8, 0)

    h.SetCollapsed = function(self, collapsed)
        local name = collapsed and ATLAS.plus or ATLAS.minus
        if atlasKnown(name) then
            self.toggle:SetAtlas(name, true)
        else
            self.toggle:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up"
                or "Interface\\Buttons\\UI-MinusButton-Up")
        end
    end

    h:SetScript("OnClick", onClick)
    return h
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
        self:ClearFocus()
    end)
    e:SetScript("OnEditFocusLost", function(self)
        if not self.cancelling then onCommit(self:GetText()) end
    end)
    e:SetScript("OnEscapePressed", function(self)
        self.cancelling = true
        self:ClearFocus()
        self.cancelling = nil
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
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
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
-- Tabs
---------------------------------------------------------------------------

-- The tab strip the housing dashboard uses, tabs on top. `onSelect` receives
-- the 1-based index. Falls back to plain buttons without the template.
function Widgets.Tabs(parent, names, onSelect)
    local ok, ts = pcall(CreateFrame, "Frame", nil, parent, "TabSystemTemplate")
    if ok and ts and ts.AddTab and CreateFramePool then
        -- The template's pool is built in OnLoad from the default bottom-tab
        -- template; swap it for the top-tab one before any tab is added.
        ts.tabTemplate = "TabSystemTopButtonTemplate"
        ts.tabPool = CreateFramePool("BUTTON", ts, ts.tabTemplate)
        ts.minTabWidth = 100
        ts.maxTabWidth = 150
        ts:SetTabSelectedCallback(function(id)
            onSelect(id)
        end)
        for i = 1, #names do
            ts:AddTab(names[i])
        end
        ts.Select = function(self, index)
            self:SetTab(index)
        end
        return ts
    end

    local strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(#names * 104, 24)
    strip.buttons = {}
    for i = 1, #names do
        local b = Widgets.Button(strip, names[i], 100, function() strip:Select(i) end)
        b:SetPoint("BOTTOMLEFT", (i - 1) * 104, 0)
        strip.buttons[i] = b
    end
    strip.Select = function(self, index)
        for i = 1, #self.buttons do
            self.buttons[i]:SetEnabled(i ~= index)
        end
        onSelect(index)
    end
    return strip
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

-- A portrait window as the housing dashboard builds it: round icon in the
-- corner, gold title bar, close button, and a content area under the tab
-- strip carrying the dark scene and the filigree corners.
function Widgets.Window(name, title, width, height)
    local f = CreateFrame("Frame", name, UIParent, "PortraitFrameTemplate")
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

    -- Same anchors as the dashboard's ContentFrame.
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 5, -58)
    content:SetPoint("BOTTOMRIGHT", -3, 0)

    -- Solid stone under the scene so nothing shows through if the scene
    -- atlas is missing.
    local stone = content:CreateTexture(nil, "BACKGROUND", nil, -2)
    stone:SetAllPoints()
    stone:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
    stone:SetVertexColor(0.6, 0.6, 0.6)

    local scene = Widgets.Atlas(content, "BACKGROUND", ATLAS.scene, -1)
    scene:SetAllPoints()
    scene:SetVertexColor(0.8, 0.65, 0.48)

    -- The corners sit on their own frame above the content so nothing laid
    -- out inside can cover them.
    local trim = CreateFrame("Frame", nil, content)
    trim:SetAllPoints()
    trim:SetFrameLevel(content:GetFrameLevel() + 20)
    Widgets.Filigree(trim)

    f.content = content
    return f
end

return Widgets
