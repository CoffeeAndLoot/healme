std = "lua51"
max_line_length = 120
exclude_files = { "HealMe/Libs" }
globals = {
    -- Written by this addon
    "HealMeDB", "HealMe_OnAddonCompartmentClick",
    "SLASH_HEALME1", "SLASH_HEALME2",
    "ClickCastFrames", "ClickCastHeader", "Clique", "HealMeNS",
}
read_globals = {
    "SlashCmdList", "CreateFrame", "UIParent", "print", "geterrorhandler",
    "InCombatLockdown", "RegisterAttributeDriver", "UnitName",
    "GetSpecialization", "GetSpecializationInfo",
    "C_Spell", "C_AddOns", "C_Timer", "LibStub",
    -- Frame API used by the options panel and minimap button
    "tinsert", "UISpecialFrames", "Minimap", "GameTooltip", "GetCursorPosition",
    "ScrollUtil", "C_Texture", "CreateFramePool",
}
