local _, ns = ...
ns = ns or {}

local Bar = {}
ns.Bar = Bar

-- A row of spell buttons glued to Blizzard's raid or party frames so a
-- healer's long cooldowns sit where their eyes already are. Every button is
-- a plain spell cast with no unit: Tranquility, Halo, Divine Hymn. The
-- spell list is per profile; where the bar sits is an account-wide habit.
--
-- The helpers above the frame code are pure and unit-tested on the desktop.

Bar.MAX_SLOTS = 12
Bar.GAP = 4
Bar.SIZES = { 24, 32, 36, 40, 48, 64 }
Bar.DEFAULT_SIDE = "above"
Bar.DEFAULT_SIZE = 36

---------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------

-- The global name of the frame the bar rides, or nil to hide. Raid wins
-- over party; a party picks by whether raid-style party frames are on.
function Bar.AnchorTarget(inRaid, inParty, raidStyleParty)
    if inRaid then
        return "CompactRaidFrameContainer"
    end
    if inParty then
        return raidStyleParty and "CompactPartyFrame" or "PartyFrame"
    end
    return nil
end

-- Container width and each slot's x offset for `count` square slots.
function Bar.Layout(count, size, gap)
    gap = gap or Bar.GAP
    local offsets = {}
    for i = 1, count do
        offsets[i] = (i - 1) * (size + gap)
    end
    local width = 0
    if count > 0 then
        width = count * size + (count - 1) * gap
    end
    return width, offsets
end

-- Whether `name` may be appended to `list`. `spellExists` is optional so
-- the check can run without a client.
function Bar.Validate(list, name, spellExists)
    if type(name) ~= "string" or name == "" then
        return false, "pick a spell"
    end
    if #list >= Bar.MAX_SLOTS then
        return false, "the bar is full (" .. Bar.MAX_SLOTS .. " slots)"
    end
    for i = 1, #list do
        if list[i] == name then
            return false, name .. " is already on the bar"
        end
    end
    if spellExists and not spellExists(name) then
        return false, "unknown spell: " .. name
    end
    return true
end

-- An imported list, cleaned: strings only, no blanks, no duplicates, at
-- most MAX_SLOTS. Unknown spells are kept on purpose: a string from another
-- spec should keep its slots and simply show them empty here.
function Bar.Sanitize(list)
    local out, seen = {}, {}
    if type(list) ~= "table" then
        return out
    end
    for i = 1, #list do
        local name = list[i]
        if type(name) == "string" and name ~= "" and not seen[name]
                and #out < Bar.MAX_SLOTS then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local FALLBACK_ICON = 134400 -- INV_Misc_QuestionMark

local container
local buttons = {}
local applyQueued = false

local function errorhandler(err)
    return geterrorhandler()(err)
end

local function safecall(func, ...)
    -- WoW's Lua passes extra arguments through xpcall, unlike stock 5.1.
    ---@diagnostic disable-next-line: redundant-parameter
    return xpcall(func, errorhandler, ...)
end

local function placement()
    return ns.Core:UISettings().bar
end

local function spellID(name)
    if not ns.Core:SpellExists(name) then
        return nil
    end
    local info = C_Spell.GetSpellInfo(name)
    return info and info.spellID or nil
end

local function createButton(i)
    local b = CreateFrame("Button", "HealMeBarButton" .. i, container, "SecureActionButtonTemplate")
    -- Both edges, so the cast honours the player's key-down setting as
    -- Blizzard's own buttons do.
    b:RegisterForClicks("AnyUp", "AnyDown")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)

    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints()

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.count:Hide()

    b:SetScript("OnEnter", function(self)
        if self.spellID and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    b:Hide()
    return b
end

-- Display only. Start, duration and modRate go straight into the cooldown
-- frame, which accepts Secret Values; nothing here compares them. Mirrors
-- ActionButton_ApplyCooldown in Blizzard_ActionBar/Shared/ActionButton.lua.
local function refreshButton(b)
    if not b.spellID then
        b.cooldown:Clear()
        b.count:Hide()
        return
    end

    local info = C_Spell.GetSpellCooldown(b.spellID)
    if info and info.isActive then
        b.cooldown:SetCooldown(info.startTime, info.duration, info.modRate)
    else
        b.cooldown:Clear()
    end

    local charges = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(b.spellID)
    if charges and charges.maxCharges and charges.maxCharges > 1 then
        b.count:SetText(charges.currentCharges)
        b.count:Show()
    else
        b.count:Hide()
    end

    if C_Spell.IsSpellUsable then
        local usable, noMana = C_Spell.IsSpellUsable(b.spellID)
        if usable then
            b.icon:SetVertexColor(1, 1, 1)
        elseif noMana then
            b.icon:SetVertexColor(0.5, 0.5, 1)
        else
            b.icon:SetVertexColor(0.4, 0.4, 0.4)
        end
    end
end

function Bar:RefreshCooldowns()
    for i = 1, #buttons do
        if buttons[i]:IsShown() then
            safecall(refreshButton, buttons[i])
        end
    end
end

local function raidStyleParty()
    if EditModeManagerFrame and EditModeManagerFrame.UseRaidStylePartyFrames then
        local ok, on = pcall(EditModeManagerFrame.UseRaidStylePartyFrames, EditModeManagerFrame)
        if ok then
            return on and true or false
        end
    end
    return CompactPartyFrame and CompactPartyFrame:IsShown() or false
end

local function anchor(count)
    local name = Bar.AnchorTarget(IsInRaid(), IsInGroup(), raidStyleParty())
    local target = name and _G[name]
    container:ClearAllPoints()
    if not target or count == 0 then
        container:Hide()
        return
    end
    if placement().side == "below" then
        container:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, -Bar.GAP)
    else
        container:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 0, Bar.GAP)
    end
    container:Show()
end

-- The one entry point. Writes attributes, so it queues in combat and runs
-- on PLAYER_REGEN_ENABLED. A slot whose spell this spec does not know keeps
-- its place, greyed, with no attribute: clicking it does nothing.
function Bar:Apply()
    if not container then
        return
    end
    if InCombatLockdown() then
        applyQueued = true
        return
    end
    applyQueued = false

    local list = ns.Core:Bar()
    local size = placement().size or Bar.DEFAULT_SIZE
    local width, offsets = Bar.Layout(#list, size)

    for i = 1, Bar.MAX_SLOTS do
        local b = buttons[i]
        local name = list[i]
        local id = name and spellID(name)
        if id then
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", name)
        else
            b:SetAttribute("type", nil)
            b:SetAttribute("spell", nil)
        end
        b.spellID = id
        if name then
            b.icon:SetTexture(id and C_Spell.GetSpellTexture(id) or FALLBACK_ICON)
            b.icon:SetDesaturated(id == nil)
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("LEFT", container, "LEFT", offsets[i], 0)
            b:Show()
        else
            b:Hide()
        end
    end

    container:SetSize(math.max(width, 1), size)
    anchor(#list)
    self:RefreshCooldowns()
end

function Bar:SlotCount()
    local n = 0
    for i = 1, #buttons do
        if buttons[i]:IsShown() then
            n = n + 1
        end
    end
    return n
end

function Bar:Initialize()
    if container then
        return
    end
    container = CreateFrame("Frame", "HealMeBar", UIParent)
    container:Hide()
    for i = 1, Bar.MAX_SLOTS do
        buttons[i] = createButton(i)
    end

    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    events:RegisterEvent("SPELL_UPDATE_CHARGES")
    events:RegisterEvent("SPELL_UPDATE_USABLE")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if applyQueued then
                safecall(Bar.Apply, Bar)
            end
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            -- The anchor target may have changed; Apply re-anchors and
            -- queues itself if this lands mid-fight.
            safecall(Bar.Apply, Bar)
        else
            safecall(Bar.RefreshCooldowns, Bar)
        end
    end)
    self.events = events

    -- Edit Mode moves the raid frames; follow them when it closes.
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            safecall(Bar.Apply, Bar)
        end, Bar)
    end

    self:Apply()
end

return Bar
