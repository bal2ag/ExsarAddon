-- CoreCombatWidget module
-- A keybindable mini action bar of core combat abilities + a couple of combat
-- macros, built on the shared ExsarUI.CreateActionBar engine. Click or keybind a
-- slot to fire it; abilities with a real cooldown show a sweep + countdown and
-- dim while down (engine `dimOnCooldown`), GCD-only shots never flicker.
--
-- This file is just the action table + a CreateActionBar call. See the
-- action-bar engine block in ExsarUI.lua for the action-spec field reference.
--
-- Abilities use the `spells` field (a one-entry list): `/cast <name>` at highest
-- known rank, with icon / spell tooltip / cooldown all resolved from the spell,
-- and the slot auto-hiding when the spell isn't known (so Aimed Shot disappears
-- unless you're Marksmanship). Macros are explicit (Auto Shot start-attack and
-- the Raptor Strike melee weave).
--
-- Each slot is keybindable via Blizzard's Key Bindings UI (Bindings.xml,
-- EXSAR_COMBAT1..15, "ExsarAddon Combat" category). Keys live in Blizzard's
-- binding set (no SavedVariables). Settings under ExsarAddonDB.coreCombat.

-- MAX_SLOTS must match the number of EXSAR_COMBAT bindings declared in
-- Bindings.xml. Grow ACTIONS, MAX_SLOTS, and Bindings.xml together.
local MAX_SLOTS = 15

-- A plain ability slot: casts the highest known rank; icon/tooltip/cooldown
-- follow the spell; hides when the spell isn't known (e.g. talent-gated).
local function ability(name)
    return { key = name, name = name, spells = { name } }
end

local ACTIONS = {
    -- Melee weave: queue Raptor Strike on the next swing and start melee.
    { key = "raptorstrike", name = "Raptor Strike",
      macro = [[/cast Raptor Strike
/startattack]],
      iconSpell     = "Raptor Strike",
      cooldownSpell = "Raptor Strike",
      rangeSpell    = "Raptor Strike" },

    -- Start attacking: target the nearest enemy if we have no valid target,
    -- then turn on Auto Shot (! = ensure on, don't toggle off). No cooldown.
    { key = "autoshot", name = "Auto Shot",
      macro = [[/targetenemy [noexists][dead][help]
/cast !Auto Shot]],
      iconSpell  = "Auto Shot",
      rangeSpell = "Auto Shot" },

    ability("Steady Shot"),
    ability("Multi-Shot"),
    ability("Arcane Shot"),
    ability("Kill Command"),
    ability("Hunter's Mark"),
    ability("Aimed Shot"),       -- MM talent: hides unless known
    ability("Serpent Sting"),
    ability("Distracting Shot"),
    ability("Volley"),
    ability("Disengage"),
    ability("Concussive Shot"),
    ability("Viper Sting"),
    ability("Wing Clip"),
}

assert(#ACTIONS == MAX_SLOTS, "ACTIONS count must equal MAX_SLOTS")

ExsarUI.CreateActionBar({
    name                = "coreCombat",
    frameName           = "ExsarAddonCoreCombatFrame",
    buttonPrefix        = "ExsarAddonCombatBtn",
    placeholder         = "Combat",
    layout              = "horizontal",
    dimOnCooldown       = true,
    rangeCheck          = true,
    actions             = ACTIONS,
    moduleName          = "Core Combat",
    configName          = "Core Combat",
    defaultX            = 0,
    defaultY            = -200,
    slashReset          = "combatreset",
    bindingPrefix       = "EXSAR_COMBAT",
    bindingCount        = MAX_SLOTS,
    bindingHeaderGlobal = "BINDING_HEADER_EXSARADDONCOMBAT",
    bindingHeaderText   = "ExsarAddon Combat",
})
