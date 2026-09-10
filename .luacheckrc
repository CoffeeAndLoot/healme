std = "lua51"
max_line_length = 120
-- Methods are written Module:Name() for a consistent call style even when
-- they do not touch self.
self = false
exclude_files = { "HealMe/Libs" }
globals = {
    -- Written by this addon
    "HealMeDB", "HealMe_OnAddonCompartmentClick",
    "SLASH_HEALME1", "SLASH_HEALME2",
    "ClickCastFrames", "ClickCastHeader", "Clique", "HealMeNS",
    -- Blizzard tables this addon adds entries to
    "SlashCmdList", "StaticPopupDialogs",
}
read_globals = {
    "CreateFrame", "UIParent", "print", "geterrorhandler",
    "InCombatLockdown", "RegisterAttributeDriver", "UnitName", "hooksecurefunc",
    "GetSpecialization", "GetSpecializationInfo", "C_SpecializationInfo",
    "PlayerFrame", "EditModeManagerFrame", "CompactUnitFrame_SetUpFrame", "C_XMLUtil",
    "C_Spell", "C_AddOns", "C_Timer", "LibStub",
    -- Frame API used by the options panel and minimap button
    "tinsert", "UISpecialFrames", "Minimap", "GameTooltip", "GetCursorPosition",
    "ScrollUtil", "C_Texture", "CreateFramePool", "C_SpellBook", "Enum",
    "C_ClickBindings", "GetMacroInfo", "GetStringFromModifiers", "ToggleClickBindingFrame",
    "IsInRaid", "IsInGroup", "GetRealmName",
    "CompactRaidFrameContainer", "CompactPartyFrame", "PartyFrame", "EventRegistry",
    "StaticPopup_Show", "YES", "NO",
}
