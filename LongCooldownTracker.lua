-- LongCooldownTracker module
-- A glanceable readout of the long (>1 min) hunter cooldowns, built on the
-- shared ExsarUI.CreateActionBar engine.
--
-- This file is just the action table + a CreateActionBar call. See the
-- action-bar engine block in ExsarUI.lua for the action-spec field reference.
--
-- Width varies with spec, not with gear: Rapid Fire is baseline, and of Bestial
-- Wrath / Readiness a hunter knows at most one (they are the BM and Survival
-- 31-point talents). A Marksmanship hunter therefore sees a single icon. The
-- engine's `spells` handling drives that -- the slot HIDES when none of its
-- spells are known and the rest pack together -- and it re-resolves on
-- SPELLS_CHANGED, so a respec is reflected without a reload.
--
-- Bestial Wrath and Readiness are kept as SEPARATE slots rather than folded
-- into one two-spell slot: they are different abilities, and since you can only
-- ever know one the on-screen result is identical either way.
--
-- Behaviour it inherits from the engine: secure click-to-cast, a cooldown sweep
-- + countdown that dims the icon while a real CD runs (`dimOnCooldown`), and
-- the pulsing gold ready glow while in combat (`readyPulse`). All three of
-- these are off-GCD, so no GCD swirl ever appears here.
--
-- Deliberately NOT keybindable: this is a readout, and the same cooldowns are
-- already bound on CooldownsWidget. Settings under ExsarAddonDB.longCds.

-- TBC spell ids for the talent-gated known-check (IsSpellKnown).
local SPELLS = {
    { key = "rapidfire", name = "Rapid Fire",
      spells = { { name = "Rapid Fire", id = 3045 } } },

    -- Beast Mastery 31-pt: hidden for every other spec.
    { key = "bestialwrath", name = "Bestial Wrath",
      spells = { { name = "Bestial Wrath", id = 19574 } } },

    -- Survival 31-pt: hidden for every other spec.
    { key = "readiness", name = "Readiness",
      spells = { { name = "Readiness", id = 23989 } } },
}

ExsarUI.CreateActionBar({
    name          = "longCds",
    frameName     = "ExsarAddonLongCDFrame",
    buttonPrefix  = "ExsarAddonLongCDBtn",
    placeholder   = "Long CDs",
    layout        = "horizontal",
    dimOnCooldown = true,
    readyPulse    = true,
    actions       = SPELLS,
    moduleName    = "Cooldown Tracker: Long",
    configName    = "Long cooldown tracker",
    defaultX      = 0,
    defaultY      = -245,
    slashReset    = "longcdreset",
})
