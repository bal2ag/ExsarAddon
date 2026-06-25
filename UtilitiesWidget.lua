-- UtilitiesWidget module
-- A keybindable vertical mini action bar of utility abilities + handy macros
-- (a fishing-setup combo and 1H/2H weapon swaps), built on the shared
-- ExsarUI.CreateActionBar engine.
--
-- This file is just the action table + a CreateActionBar call. See the
-- action-bar engine block in ExsarUI.lua for the action-spec field reference.
--
-- Abilities use the `spells` field (cast highest known rank; icon/tooltip/
-- cooldown auto; hides when unknown), which transparently handles talent gating
-- (Misdirection: MM) and racial gating (Shadowmeld: Night Elf). Macros are
-- explicit; weapon names are hardcoded (they live in bags, no API to discover
-- them) -- /equip works in combat. Real-cooldown abilities dim while down
-- (dimOnCooldown); the macros have no cooldown so they never dim.
--
-- Each slot is keybindable via Blizzard's Key Bindings UI (Bindings.xml,
-- EXSAR_UTILITY1..8, "ExsarAddon Utility" category). Keys live in Blizzard's
-- binding set (no SavedVariables). Settings under ExsarAddonDB.utilities.

-- MAX_SLOTS must match the number of EXSAR_UTILITY bindings declared in
-- Bindings.xml. Grow ACTIONS, MAX_SLOTS, and Bindings.xml together.
local MAX_SLOTS = 9

-- A plain ability slot: casts the highest known rank; icon/tooltip/cooldown
-- follow the spell; hides when the spell isn't known (talent / racial gating).
local function ability(name)
    return { key = name, name = name, spells = { name } }
end

-- True if the item equipped in inventory slot `slot` (16 = main hand, 17 =
-- off hand) is named `name`. Used by the weapon/fishing slots' isActive hook so
-- the border lights up when that exact gear is equipped.
local function equipped(slot, name)
    local link = GetInventoryItemLink("player", slot)
    return link ~= nil and GetItemInfo(link) == name
end

local ACTIONS = {
    ability("Misdirection"),        -- MM talent: hides unless known
    ability("Feign Death"),
    ability("Tranquilizing Shot"),
    ability("Eyes of the Beast"),
    ability("Shadowmeld"),          -- Night Elf racial: hides unless known
    ability("Flare"),

    -- Fishing setup: equip the pole, then arm + apply the hook to it (the hook
    -- works like Feed Pet -- /use the consumable, then /use the item it applies
    -- to, i.e. the main-hand slot 16).
    { key = "fishing", name = "Fishing Setup",
      macro = [[/equip Seth's Graphite Fishing Pole
/use Sharpened Fish Hook
/use 16]],
      iconItem = "Seth's Graphite Fishing Pole",
      isActive = function() return equipped(16, "Seth's Graphite Fishing Pole") end },

    -- Weapon swaps (hardcoded; live in bags). /equip a 2H clears the off-hand;
    -- the dual-1H slot pins both hands explicitly via /equipslot. The border
    -- lights up when that exact weapon set is currently equipped (the dual-1H
    -- slot only when BOTH hands match).
    { key = "weapon2h", name = "Equip 2H (Legacy)",
      macro = "/equip Legacy",
      iconItem = "Legacy",
      isActive = function() return equipped(16, "Legacy") end },

    { key = "weapon1h", name = "Equip Dual 1H",
      macro = [[/equipslot 16 Claw of the Watcher
/equipslot 17 Stormreaver Warblades]],
      iconItem = "Claw of the Watcher",
      isActive = function()
          return equipped(16, "Claw of the Watcher")
             and equipped(17, "Stormreaver Warblades")
      end },
}

assert(#ACTIONS == MAX_SLOTS, "ACTIONS count must equal MAX_SLOTS")

ExsarUI.CreateActionBar({
    name                = "utilities",
    frameName           = "ExsarAddonUtilitiesFrame",
    buttonPrefix        = "ExsarAddonUtilityBtn",
    placeholder         = "Utility",
    layout              = "horizontal",
    dimOnCooldown       = true,
    rangeCheck          = true,  -- red shade on out-of-range harm slots (Tranquilizing Shot)
    manaCheck           = true,  -- blue shade on abilities you can't afford
    border              = true,  -- gold ring on the equipped weapon/pole (isActive)
    extraEvents         = { "PLAYER_EQUIPMENT_CHANGED" },  -- update the ring on swap
    actions             = ACTIONS,
    moduleName          = "Utilities",
    configName          = "Utilities",
    defaultX            = 260,
    defaultY            = 0,
    slashReset          = "utilreset",
    bindingPrefix       = "EXSAR_UTILITY",
    bindingCount        = MAX_SLOTS,
    bindingHeaderGlobal = "BINDING_HEADER_EXSARADDONUTILITY",
    bindingHeaderText   = "ExsarAddon Utility",
})
