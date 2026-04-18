-- Luacheck configuration for ExsarAddon (WoW TBC Classic Anniversary)
std = "lua51"

-- Addon's own cross-file globals
globals = {
    "ExsarAddon",
    "ExsarAddonDB",
    "ExsarLogic",
    "ExsarUI",
}

-- WoW API globals (read-only)
read_globals = {
    -- Lua standard (some luacheck configs need these explicit for lua51)
    "_G",
    "ipairs",
    "math",
    "pairs",
    "pcall",
    "print",
    "select",
    "string",
    "table",
    "tonumber",
    "tostring",
    "type",
    "unpack",

    -- WoW frames and UI objects
    "ChatFontNormal",
    "CreateFrame",
    "GameTooltip",
    "InterfaceOptions_AddCategory",
    "InterfaceOptionsFrame",
    "InterfaceOptionsFrame_OpenToCategory",
    "PlayerCastingBarFrame",
    "Settings",
    "TargetFrame",
    "UIParent",
    "WorldFrame",

    -- WoW API functions
    "C_Container",
    "C_Item",
    "C_NamePlate",
    "C_Timer",
    "date",
    "CombatLogGetCurrentEventInfo",
    "GetCVar",
    "GetInventoryItemCooldown",
    "GetInventoryItemCount",
    "GetInventoryItemID",
    "GetInventoryItemLink",
    "GetInventoryItemTexture",
    "GetItemCount",
    "GetItemInfo",
    "GetItemSpell",
    "GetNetStats",
    "GetPetActionInfo",
    "GetPetHappiness",
    "GetRaidTargetIndex",
    "GetRealZoneText",
    "GetSpellCooldown",
    "GetSpellInfo",
    "GetTime",
    "GetUnitSpeed",
    "GetWeaponEnchantInfo",
    "InCombatLockdown",
    "IsSpellInRange",
    "PlaySound",
    "IsUsableSpell",
    "SetPortraitTexture",
    "UnitAffectingCombat",
    "UnitAttackSpeed",
    "UnitBuff",
    "UnitCanAttack",
    "UnitCastingInfo",
    "UnitClass",
    "UnitClassification",
    "UnitCreatureType",
    "UnitDebuff",
    "UnitExists",
    "UnitGUID",
    "UnitHealth",
    "UnitHealthMax",
    "UnitIsDead",
    "UnitIsEnemy",
    "UnitIsFriend",
    "UnitIsPlayer",
    "UnitLevel",
    "UnitName",
    "UnitPower",
    "UnitPowerMax",
    "UnitPowerType",
    "UnitRangedDamage",
    "UnitIsUnit",
    "UnitTokenFromNamePlate",
    "IsInRaid",
    "IsInGroup",
}

-- Exclude test files and spec helpers from WoW-specific checks
-- Test files (need to set globals for mocking)
files["tests/test_*.lua"] = {
    std = "lua51+busted",
    globals = {
        "ExsarLogic",
        "ExsarUI",
        "ExsarAddon",
        "ExsarAddonDB",
    },
    -- Tests often destructure return values and only check some fields
    ignore = { "21./.+", "311" },
    -- Tests need to write to _G for mocking
    read_globals = { ["_G"] = { other_fields = true, read_only = false } },
}

-- ExsarLogic sets itself as a global via _G
files["ExsarLogic.lua"] = {
    globals = {
        "ExsarAddon",
        "ExsarAddonDB",
        "ExsarLogic",
        "ExsarUI",
        "_G",
    },
}

-- Ignore line length warnings (style preference)
max_line_length = false

-- Allow unused self/elapsed/event args (WoW callback signatures)
-- and unused loop variables
ignore = {
    "212/self",     -- unused argument 'self'
    "212/elapsed",  -- unused argument 'elapsed'
    "212/event",    -- unused argument 'event'
}

-- WoW slash command globals (set by Core.lua)
globals["SLASH_EXSAR1"] = {}
globals["SlashCmdList"] = { other_fields = true }
