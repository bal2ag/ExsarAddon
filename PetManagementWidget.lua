-- PetManagementWidget module
-- A compact, keybindable mini action bar of pet-management actions, built on
-- the shared ExsarUI.CreateActionBar engine. Each slot is a secure macro button
-- (type="macro") driven by addon-controlled macrotext, so a single button can
-- carry a conditional smart-macro (e.g. Call/Revive/Dismiss).
--
-- This file is now just the action table + a CreateActionBar call. The engine
-- owns construction, layout, cooldown/count/grey-out rendering, the keybind
-- bridge, slash reset, config rows and module registration. See the action-bar
-- engine block in ExsarUI.lua for the action-spec field reference.
--
-- Macro source model: PET_ACTIONS holds the macrotext for each action -- macros
-- are fully addon-controlled, there is no user override. Each slot is
-- keybindable via Blizzard's Key Bindings UI (Bindings.xml,
-- EXSAR_PET_ACTION1..MAX_SLOTS, "ExsarAddon Pet" category); the bound key shows
-- top-right of the icon. Keys live in Blizzard's binding set (no SavedVariables).
-- Settings stored under ExsarAddonDB.petManagement.

-- MAX_SLOTS must match the number of EXSAR_PET_ACTION bindings declared in
-- Bindings.xml -- currently kept equal to the number of actions for a clean Key
-- Bindings menu. When adding actions, grow PET_ACTIONS, MAX_SLOTS, and the
-- Bindings.xml entries together.
local MAX_SLOTS = 6

local PET_ACTIONS = {
    -- "Do the right thing" pet button: heals a living pet, revives a dead one,
    -- or calls/revives when you have none. Never greyed (no `requires`, handles
    -- every state); the icon tracks state via dynamicIcon.
    { key = "petaio", name = "Pet (All-in-One)",
      dynamicIcon = {
          alive   = { spell = "Mend Pet" },
          dead    = { spell = "Revive Pet" },
          missing = { spell = "Call Pet" },
      },
      gcd = true,
      macro = [[/use [@pet,nodead,exists] Mend Pet
/stopmacro [@pet,nodead,exists]
/use [@pet,dead,exists] Revive Pet
/stopmacro [@pet,exists]
/use [nopet] Call Pet]] },

    -- Send the pet in: Dash for the speed boost, then command the attack.
    -- Needs a living pet, so greyed when the pet is missing or dead.
    { key = "petdashattack", name = "Send Pet to Attack",
      icon = "Interface\\Icons\\Ability_GhoulFrenzy",  -- default pet-bar Attack icon
      macro = [[/cast Dash(Rank 3)
/petattack]],
      requires = "alive" },

    -- Recall the pet: Dash for speed, then passive stance to break off and
    -- return. Needs a living pet, so greyed when the pet is missing or dead.
    { key = "petrecall", name = "Pet Recall",
      icon = "Interface\\Icons\\Spell_Nature_Sleep",  -- default pet-bar Passive icon
      macro = [[/cast Dash(Rank 3)
/petpassive]],
      requires = "alive" },

    -- Dismiss the active pet. Channeled; requires a living pet (can't dismiss a
    -- dead or absent one), so greyed otherwise.
    { key = "dismisspet", name = "Dismiss Pet",
      iconSpell = "Dismiss Pet",
      macro = "/cast Dismiss Pet",
      gcd = true,
      requires = "alive" },

    -- The classic TBC hunter "save your pet" trick. Using the Steam Tonk
    -- Controller instantly puts your active pet away (no Dismiss Pet channel),
    -- so a living pet is yanked out of lethal damage (boss AoE / wipe) and comes
    -- back unharmed instead of dead. CASING MATTERS: the /cancelaura name must
    -- exactly match the buff ("Steam Tonk Controller") or you stay trapped in
    -- the tonk. Worked as THREE deliberate clicks, not a fast mash (mashing can
    -- leave you movement-locked): click 1 (have a living pet) uses the
    -- controller -> pet saved + you transform (the /cancelaura no-ops because the
    -- buff hasn't applied server-side yet, and Call Pet skips since you still
    -- have a pet); click 2 (now pet-less + still the tonk) drops the tonk via
    -- /cancelaura -- the Call Pet on the next line fails this press because the
    -- cancel hasn't resolved server-side yet, so you're still a tonk; click 3
    -- (untransformed, pet-less) finally fires Call Pet to resummon. The same
    -- round-trip latency that forces the cancel onto its own click also forces
    -- the resummon onto a third. Greyed when the pet is dead (requires="notdead"
    -- -- the trick can't help a corpse, and we don't tonk-dismiss a dead pet).
    -- Shows net Steam Tonk Controller charges in bags (countCharges sums charges
    -- across stacks, like Drums of Battle in UsableItemsWidget).
    { key = "steamtonk", name = "Steam Tonk",
      iconItem = "Steam Tonk Controller",
      countItem = "Steam Tonk Controller", countCharges = true,
      cooldownItem = "Steam Tonk Controller",
      gcd = true,  -- macro's Call Pet branch triggers the GCD
      macro = [[/use [@pet,exists,nodead] Steam Tonk Controller
/cancelaura Steam Tonk Controller
/use [nopet] Call Pet]],
      requires = "notdead" },

    -- Feed the pet to keep it happy: /cast Feed Pet enters feed mode, then
    -- /use consumes the food. Needs a living pet, so greyed otherwise. Shows
    -- the Clefthoof Ribs bag count so you can see when you're running low.
    { key = "feedpet", name = "Feed Pet",
      iconSpell = "Feed Pet",
      countItem = "Clefthoof Ribs",
      gcd = true,  -- /cast Feed Pet triggers the GCD
      macro = [[/cast [pet,nodead] Feed Pet
/use Clefthoof Ribs]],
      requires = "alive" },
}

-- Sanity: keep the binding count aligned with the declared bindings.
assert(#PET_ACTIONS == MAX_SLOTS, "PET_ACTIONS count must equal MAX_SLOTS")

ExsarUI.CreateActionBar({
    name                = "petManagement",
    frameName           = "ExsarAddonPetManagementFrame",
    buttonPrefix        = "ExsarAddonPetActionBtn",
    placeholder         = "Pet",
    layout              = "horizontal",
    actions             = PET_ACTIONS,
    moduleName          = "Pet Management",
    configName          = "Pet management",
    defaultX            = 200,
    defaultY            = -200,
    slashReset          = "petmgmtreset",
    bindingPrefix       = "EXSAR_PET_ACTION",
    bindingCount        = MAX_SLOTS,
    bindingHeaderGlobal = "BINDING_HEADER_EXSARADDONPET",
    bindingHeaderText   = "ExsarAddon Pet",
    pollInterval        = 0.2,
})
