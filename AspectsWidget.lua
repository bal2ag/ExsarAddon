-- AspectsWidget module
-- A keybindable mini action bar of Hunter aspects, built on the shared
-- ExsarUI.CreateActionBar engine (macro-kind slots). Click or keybind a slot to
-- cast that aspect; the slot whose aspect buff is currently up gets the gold
-- border ring (via the engine's `activeBuff` field).
--
-- This file is just the action table + a CreateActionBar call. See the
-- action-bar engine block in ExsarUI.lua for the action-spec field reference.
--
-- Each slot is keybindable via Blizzard's Key Bindings UI (Bindings.xml,
-- EXSAR_ASPECT1..6, "ExsarAddon Aspects" category); the bound key shows
-- top-right of the icon. Keys live in Blizzard's binding set (no SavedVariables).
-- Settings stored under ExsarAddonDB.aspects.

-- MAX_SLOTS must match the number of EXSAR_ASPECT bindings declared in
-- Bindings.xml. Grow ASPECTS, MAX_SLOTS, and Bindings.xml together.
local MAX_SLOTS = 6

-- macro kind (each casts a toggle aspect; /cast resolves the highest known rank).
-- activeBuff = the buff name to glow on; icon resolved from the spell.
local function aspect(name)
    return {
        key       = name,
        name      = name,
        iconSpell = name,
        macro     = "/cast " .. name,
        activeBuff = name,
    }
end

local ASPECTS = {
    aspect("Aspect of the Hawk"),
    aspect("Aspect of the Viper"),
    aspect("Aspect of the Cheetah"),
    aspect("Aspect of the Pack"),
    aspect("Aspect of the Wild"),
    aspect("Aspect of the Monkey"),
}

assert(#ASPECTS == MAX_SLOTS, "ASPECTS count must equal MAX_SLOTS")

ExsarUI.CreateActionBar({
    name                = "aspects",
    frameName           = "ExsarAddonAspectsFrame",
    buttonPrefix        = "ExsarAddonAspectBtn",
    placeholder         = "Aspects",
    layout              = "vertical",
    activeAnts          = true,  -- marching ants on the currently-active aspect (activeBuff)
    actions             = ASPECTS,
    moduleName          = "Aspects",
    configName          = "Aspects",
    defaultX            = 200,
    defaultY            = -240,
    slashReset          = "aspectsreset",
    bindingPrefix       = "EXSAR_ASPECT",
    bindingCount        = MAX_SLOTS,
    bindingHeaderGlobal = "BINDING_HEADER_EXSARADDONASPECTS",
    bindingHeaderText   = "ExsarAddon Aspects",
})
