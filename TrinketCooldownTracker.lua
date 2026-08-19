-- TrinketCooldownTracker module
-- A glanceable readout of the equipped trinkets' on-use cooldowns, built on the
-- shared ExsarUI.CreateActionBar engine.
--
-- This file is just the action table + a CreateActionBar call. See the
-- action-bar engine block in ExsarUI.lua for the action-spec field reference.
--
-- This is the DYNAMIC one, and the reason the cooldown trackers are split at
-- all: `hideWhenNoUse` hides a slot unless the trinket equipped in it actually
-- has an on-use effect, so the widget shows 0, 1 or 2 icons depending on gear
-- and packs them together. A PROC trinket (Dragonspine Trophy and friends) has
-- no on-use spell and so hides here by design -- ActiveEffectsTracker is what
-- surfaces those procs. With two proc trinkets equipped there is nothing to
-- show at all, and `hideEmptyBar` takes the frame away entirely while locked
-- rather than parking an empty rectangle on screen.
--
-- The engine follows whatever is equipped: `trinketSlot` takes the icon from
-- GetInventoryItemTexture, the sweep from GetInventoryItemCooldown, and the
-- secure "/use <slot>" macro needs no rewriting on a swap. Slot changes are
-- picked up from PLAYER_EQUIPMENT_CHANGED (filtered to slots 13/14) and
-- re-verified on a 1 Hz throttle, so a transient uncached read self-heals.
--
-- Behaviour it inherits from the engine: secure click-to-use, a cooldown sweep
-- + countdown that dims the icon while a real CD runs (`dimOnCooldown`), and
-- the pulsing gold ready glow while in combat (`readyPulse`). Trinkets are
-- off-GCD, so no GCD swirl ever appears here.
--
-- Deliberately NOT keybindable: this is a readout, and both trinket slots are
-- already bound on CooldownsWidget. Settings under ExsarAddonDB.trinketCds.

local TRINKETS = {
    { key = "trinket13", name = "Top Trinket",    trinketSlot = 13, hideWhenNoUse = true },
    { key = "trinket14", name = "Bottom Trinket", trinketSlot = 14, hideWhenNoUse = true },
}

ExsarUI.CreateActionBar({
    name          = "trinketCds",
    frameName     = "ExsarAddonTrinketCDFrame",
    buttonPrefix  = "ExsarAddonTrinketCDBtn",
    placeholder   = "Trinket CDs",
    layout        = "horizontal",
    dimOnCooldown = true,
    readyPulse    = true,
    hideEmptyBar  = true,
    actions       = TRINKETS,
    moduleName    = "Cooldown Tracker: Trinkets",
    configName    = "Trinket cooldown tracker",
    defaultX      = 0,
    defaultY      = -290,
    slashReset    = "trinketcdreset",
})
