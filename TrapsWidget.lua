-- TrapsWidget module
-- A keybindable mini action bar of Hunter traps, built on the shared
-- ExsarUI.CreateActionBar engine (macro-kind slots). Click or keybind a slot to
-- lay that trap; each slot shows a cooldown sweep + countdown while the trap is
-- on cooldown (engine `cooldownSpell` field, via GetSpellCooldown).
--
-- This file is just the action table + a CreateActionBar call. See the
-- action-bar engine block in ExsarUI.lua for the action-spec field reference.
--
-- Macros are `/cast <Trap>` with no rank, so they always lay the highest known
-- rank (WoW's default macro behavior); icons resolve from the highest rank too.
--
-- Each slot is keybindable via Blizzard's Key Bindings UI (Bindings.xml,
-- EXSAR_TRAP1..5, "ExsarAddon Traps" category); the bound key shows top-right of
-- the icon. Keys live in Blizzard's binding set (no SavedVariables).
-- Settings stored under ExsarAddonDB.traps.

-- MAX_SLOTS must match the number of EXSAR_TRAP bindings declared in
-- Bindings.xml. Grow TRAPS, MAX_SLOTS, and Bindings.xml together.
local MAX_SLOTS = 5

-- macro kind: /cast lays the highest known rank; cooldownSpell drives the sweep.
local function trap(name)
    return {
        key          = name,
        name         = name,
        iconSpell    = name,
        macro        = "/cast " .. name,
        cooldownSpell = name,
    }
end

local TRAPS = {
    trap("Frost Trap"),
    trap("Freezing Trap"),
    trap("Immolation Trap"),
    trap("Explosive Trap"),
    trap("Snake Trap"),
}

assert(#TRAPS == MAX_SLOTS, "TRAPS count must equal MAX_SLOTS")

ExsarUI.CreateActionBar({
    name                = "traps",
    frameName           = "ExsarAddonTrapsFrame",
    buttonPrefix        = "ExsarAddonTrapBtn",
    placeholder         = "Traps",
    layout              = "horizontal",
    actions             = TRAPS,
    moduleName          = "Traps",
    configName          = "Traps",
    defaultX            = 200,
    defaultY            = -280,
    slashReset          = "trapsreset",
    bindingPrefix       = "EXSAR_TRAP",
    bindingCount        = MAX_SLOTS,
    bindingHeaderGlobal = "BINDING_HEADER_EXSARADDONTRAPS",
    bindingHeaderText   = "ExsarAddon Traps",
})
