-- CoreRotationCooldownTracker module
-- A glanceable readout of the two shot cooldowns the rotation is built around,
-- built on the shared ExsarUI.CreateActionBar engine. Both slots are always
-- known and always shown, so this widget has a FIXED width -- which is the
-- whole point of it being its own widget: it can be centered under the ranged
-- swing timer and stay there, instead of sliding around as trinkets come and go.
--
-- This file is just the action table + a CreateActionBar call. See the
-- action-bar engine block in ExsarUI.lua for the action-spec field reference.
--
-- Behaviour it inherits from the engine: secure click-to-cast, a cooldown sweep
-- + countdown that dims the icon while a real CD runs (`dimOnCooldown`), the
-- brief GCD swirl (sweep only, no dim, no number -- automatic for any slot with
-- a resolvable cast spell), and the pulsing gold ready glow while in combat
-- (`readyPulse`).
--
-- Deliberately NOT keybindable: this is a readout, and the same abilities are
-- already bound on CoreCombatWidget. Settings under
-- ExsarAddonDB.coreRotationCds.

-- Name-only entries (no spell id): these are baseline shots with several ranks,
-- so the engine's name lookup is the right known-check -- a rank-specific
-- IsSpellKnown id would go false the moment a new rank is trained.
local SPELLS = {
    { key = "multishot",  name = "Multi-Shot",  spells = { { name = "Multi-Shot"  } } },
    { key = "arcaneshot", name = "Arcane Shot", spells = { { name = "Arcane Shot" } } },
}

ExsarUI.CreateActionBar({
    name          = "coreRotationCds",
    frameName     = "ExsarAddonCoreRotationCDFrame",
    buttonPrefix  = "ExsarAddonCoreRotationCDBtn",
    placeholder   = "Core Rotation CDs",
    layout        = "horizontal",
    dimOnCooldown = true,
    readyPulse    = true,
    actions       = SPELLS,
    moduleName    = "Cooldown Tracker: Core Rotation",
    configName    = "Core rotation cooldown tracker",
    defaultX      = 0,
    defaultY      = -200,
    slashReset    = "corecdreset",
})
