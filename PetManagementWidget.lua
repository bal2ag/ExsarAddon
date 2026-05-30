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
local MAX_SLOTS = 7

-- ----- Devilsaur Tooth prep slot ---------------------------------------------
-- A two-click boss-prep workflow that puts a +crit buff on the pet from the
-- Devilsaur Tooth trinket without leaving the (otherwise inferior) trinket
-- equipped into combat:
--   click 1  : swap Devilsaur Tooth into the top trinket slot (yellow glow
--              appears). Wait out the 30s "just equipped" cooldown sweep.
--   click 2  : /use the trinket (buff applied to pet) AND /equipslot the
--              previous trinket back. Normally yellow goes away as the swap
--              completes; if the swap fails (combat, bag slot changed) the
--              icon stays red ("UNEQUIP!") and the user resolves it manually.
--
-- The "previous trinket" is identified by *bag slot*, not item: click 1's
-- /equipslot bounces the previously-equipped trinket into the Tooth's bag
-- slot, so the swap-back target is the same coords. The bag-slot coords are
-- captured during stage 1 and persisted in ExsarAddonDB.petManagement.devilsaurSwap
-- so the workflow survives /reload.
local DEVILSAUR_TOOTH_ID = 19992
local DEVILSAUR_BUFF_ID  = 24353
local DEVILSAUR_SLOT     = 13  -- top trinket
local DEVILSAUR_YELLOW   = { 1.0, 0.85, 0.15, 0.85 }  -- "use me!"
local DEVILSAUR_RED      = { 1.0, 0.15, 0.15, 0.90 }  -- "unequip!"
local devilsaurBuffName  -- resolved lazily via GetSpellInfo(spellID)

local function FindToothInBags()
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            if C_Container.GetContainerItemID(bag, slot) == DEVILSAUR_TOOTH_ID then
                return bag, slot
            end
        end
    end
end

local function ToothEquippedId()
    return GetInventoryItemID("player", DEVILSAUR_SLOT)
end

local function IsBuffOnPet()
    if not UnitExists("pet") then return false end
    if not devilsaurBuffName then
        devilsaurBuffName = GetSpellInfo(DEVILSAUR_BUFF_ID)
        if not devilsaurBuffName then return false end
    end
    for i = 1, 40 do
        local name = UnitBuff("pet", i)
        if not name then return false end
        if name == devilsaurBuffName then return true end
    end
    return false
end

local function DevilsaurStore()
    return ExsarAddonDB and ExsarAddonDB.petManagement
end

local function RememberToothBagSlot(bag, slot)
    local db = DevilsaurStore(); if not db then return end
    local prev = db.devilsaurSwap
    if prev and prev.bag == bag and prev.slot == slot then return end
    db.devilsaurSwap = { bag = bag, slot = slot }
end

local function StoredToothBagSlot()
    local db = DevilsaurStore(); if not db then return end
    local s = db.devilsaurSwap
    if s and s.bag and s.slot then return s.bag, s.slot end
end

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
      -- Revive Pet is cast UNCONDITIONALLY (no `[@pet,dead,exists]` gate) on
      -- purpose: right around a pet death -- especially in combat, where we
      -- can't rewrite the macro -- the "pet" unit token can momentarily read as
      -- absent. A token-gated Revive line then fails and execution falls through
      -- to `[nopet] Call Pet`, which is the "stuck calling a dead pet" bug. By
      -- always attempting Revive Pet first, a dead pet is revived regardless of
      -- the token; its cast triggers the GCD, which blocks the trailing Call Pet
      -- so there is no double-summon. The only cost: with no pet at all the
      -- Revive line errors harmlessly before Call Pet summons.
      macro = [[/use [@pet,nodead,exists] Mend Pet
/stopmacro [@pet,nodead,exists]
/cast Revive Pet
/cast [nopet] Call Pet]] },

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

    -- Devilsaur Tooth boss-prep: two-click workflow described at the top of
    -- this file. Macro/border are entirely dynamic via the engine's
    -- resolveMacro/resolveBorderColor hooks; everything else (icon, cooldown,
    -- grey-out) is per-stage logic in this slot's own closures.
    { key = "devilsaurprep", name = "Devilsaur Tooth Prep",
      type = "macro",
      iconItem = DEVILSAUR_TOOTH_ID,
      -- Cooldown source must follow whatever holds the Tooth, NOT slot 13
      -- blindly (whose CD reflects whatever-other-trinket when the Tooth is in
      -- the bags). Slot 13 when equipped (catches the 30s equip CD + on-use
      -- CD); the Tooth's bag-item CD when carried.
      getCooldown = function()
          if ToothEquippedId() == DEVILSAUR_TOOTH_ID then
              local st, dur = GetInventoryItemCooldown("player", DEVILSAUR_SLOT)
              if st and st > 0 and dur and dur > 0 then return st, dur, true end
          else
              local bag, slot = FindToothInBags()
              if bag then
                  local st, dur = C_Container.GetContainerItemCooldown(bag, slot)
                  if st and st > 0 and dur and dur > 0 then return st, dur, true end
              end
          end
          return 0, 0, false
      end,
      -- Grey out when no live pet, or when no Tooth available anywhere.
      isEnabled = function(_, petState)
          if not (petState.exists and petState.alive) then return false end
          return ToothEquippedId() == DEVILSAUR_TOOTH_ID or FindToothInBags() ~= nil
      end,
      -- Yellow when equipped without buff yet ("USE!"); red when equipped and
      -- buff already on pet ("UNEQUIP!"); no border otherwise.
      resolveBorderColor = function()
          local stage = ExsarLogic.DevilsaurStage(
              ToothEquippedId(), IsBuffOnPet(),
              FindToothInBags() ~= nil, DEVILSAUR_TOOTH_ID)
          if stage == "equipped_unused" then return DEVILSAUR_YELLOW end
          if stage == "equipped_buffed" then return DEVILSAUR_RED end
          return nil
      end,
      -- Stage 1 (Tooth in bags): capture its (bag,slot) and equip it -- the
      -- displaced trinket lands at those same coords, so click 2 swaps back
      -- using the same numbers. Stage 2 (Tooth equipped): /use to apply the
      -- buff to the pet, then /equipslot the previous trinket back. If the
      -- /equipslot leg fails, the red border kicks in (engine reruns this
      -- function next poll) and the user resolves the swap manually.
      resolveMacro = function()
          if ToothEquippedId() == DEVILSAUR_TOOTH_ID then
              local bag, slot = StoredToothBagSlot()
              if bag then
                  return string.format("/use %d\n/equipslot %d %d %d",
                      DEVILSAUR_SLOT, DEVILSAUR_SLOT, bag, slot)
              end
              return string.format("/use %d", DEVILSAUR_SLOT)
          end
          local bag, slot = FindToothInBags()
          if bag then
              RememberToothBagSlot(bag, slot)
              return string.format("/equipslot %d %d %d", DEVILSAUR_SLOT, bag, slot)
          end
          return ""
      end,
    },
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
    pollInterval        = 0.1,
})
