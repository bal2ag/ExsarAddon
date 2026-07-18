-- EngineeringWidget module
-- A mini action bar of engineering gadgets from the player's bags, built on the
-- shared ExsarUI.CreateActionBar engine (item-kind slots). Click an icon to use
-- the item; the item's own cooldown shows a sweep + countdown, out-of-stock
-- gadgets grey out, and each slot's count is the NET CHARGE total across stacks
-- (countCharges = true) rather than the raw item count.
--
-- Like the other item bars this file is just the item table + a CreateActionBar
-- call; the engine owns construction, layout, bag scanning, cooldown rendering,
-- the keybind bridge, slash reset, config rows and module registration. See the
-- action-bar engine block in ExsarUI.lua for the action-spec field reference.
--
-- Each slot is keybindable via Blizzard's Key Bindings UI under the "ExsarAddon
-- Engineering" category (Bindings.xml, EXSAR_ENGINEERING1..6, one per slot).
-- Settings stored under ExsarAddonDB.engineering.

-- ----- Goblin Rocket Boots swap slot -----------------------------------------
-- A two-click equip/boost/swap-back workflow modelled on the Devilsaur Tooth
-- prep slot (PetManagementWidget): use the Rocket Boots' on-use speed boost
-- without carrying them into a fight on your feet.
--   click 1  (boots in bags)   : /equipslot the boots into the feet slot. The
--                                previously-worn boots bounce into the Rocket
--                                Boots' old bag slot, whose coords we capture.
--   click 2  (boots equipped,   : /use the feet slot -- fire the speed boost
--             boots READY)         ALONE. The swap-back is deliberately withheld
--                                  here: unequipping the boots while the boost is
--                                  live cancels it early, so we must NOT /equipslot
--                                  in the same press that fires it.
--   click 3  (boots equipped,   : /use (a no-op while the on-use CD runs) AND
--             boots ON COOLDOWN)   /equipslot the previous boots back. Once a
--                                  cooldown is active the boots are either waiting
--                                  out the 30s just-equipped delay or spent (the
--                                  5min on-use CD, boost over), so swapping back is
--                                  safe and completes the workflow.
-- So the /equipslot swap-back rides along ONLY when GetInventoryItemCooldown
-- reports an active cooldown (BootsOnCooldown); a fresh /use fires the boost by
-- itself. While the Rocket Boots are equipped the slot shows an amber "SWAP
-- BACK!" border. The swap-back target is identified by BAG SLOT, not item, so it
-- works regardless of which boots were displaced; the coords persist in
-- ExsarAddonDB.engineering.rocketBootsSwap so the workflow survives /reload. Note
-- /equipslot is blocked in combat, so a boost fired mid-combat leaves the boots
-- on until you can swap out of combat -- the amber border stays up as the reminder.
local ROCKET_BOOTS_ID   = 7189
local ROCKET_BOOTS_SLOT = 8   -- INVSLOT_FEET
local ROCKET_AMBER      = { 1.0, 0.85, 0.15, 0.85 }  -- "swap back!"

local function FindBootsInBags()
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            if C_Container.GetContainerItemID(bag, slot) == ROCKET_BOOTS_ID then
                return bag, slot
            end
        end
    end
end

local function BootsEquipped()
    return GetInventoryItemID("player", ROCKET_BOOTS_SLOT) == ROCKET_BOOTS_ID
end

-- True while the equipped boots have a cooldown running -- either the 30s
-- just-equipped delay or the 5min on-use CD. Used to gate the swap-back so we
-- never unequip while the boots are ready/boosting (which cancels the boost).
local function BootsOnCooldown()
    local st, dur = GetInventoryItemCooldown("player", ROCKET_BOOTS_SLOT)
    return st and st > 0 and dur and dur > 0
end

local function EngStore() return ExsarAddonDB and ExsarAddonDB.engineering end

local function RememberBootsBagSlot(bag, slot)
    local db = EngStore(); if not db then return end
    local prev = db.rocketBootsSwap
    if prev and prev.bag == bag and prev.slot == slot then return end
    db.rocketBootsSwap = { bag = bag, slot = slot }
end

local function StoredBootsBagSlot()
    local db = EngStore(); if not db then return end
    local s = db.rocketBootsSwap
    if s and s.bag and s.slot then return s.bag, s.slot end
end

local TRACKED_ITEMS = {
    { name = "Goblin Sapper Charge",   id = 10646, countCharges = true },
    { name = "Super Sapper Charge",    id = 23827, countCharges = true },
    { name = "Advanced Target Dummy",  id = 4392,  countCharges = true },
    { name = "Field Repair Bot 110G",  id = 34113, countCharges = true },

    -- Both-sappers macro: one press throws the Super Sapper (1 min CD) first,
    -- then the Goblin Sapper (5 min CD) once the Super is spent -- so both fit
    -- into a fight and the short-CD one leads. A single macro-kind slot with two
    -- stacked /use lines (the first usable line fires); static Super Sapper icon,
    -- no charge count (two different items).
    { name = "Sappers", type = "macro", bindingLabel = "Sappers (Super then Goblin)",
      iconItem = 23827,
      macro = "/use Super Sapper Charge\n/use Goblin Sapper Charge" },

    -- Goblin Rocket Boots equip/boost/swap-back workflow (see the block above).
    -- Macro + border are dynamic via resolveMacro/resolveBorderColor; grey-out
    -- and cooldown are per-stage closures.
    { name = "Rocket Boots", type = "macro",
      bindingLabel = "Rocket Boots (equip / boost / swap back)",
      iconItem = ROCKET_BOOTS_ID,
      -- Cooldown follows whatever holds the boots: the feet slot when equipped
      -- (catches the on-use CD), the boots' bag-item CD when carried.
      getCooldown = function()
          if BootsEquipped() then
              local st, dur = GetInventoryItemCooldown("player", ROCKET_BOOTS_SLOT)
              if st and st > 0 and dur and dur > 0 then return st, dur, true end
          else
              local bag, slot = FindBootsInBags()
              if bag then
                  local st, dur = C_Container.GetContainerItemCooldown(bag, slot)
                  if st and st > 0 and dur and dur > 0 then return st, dur, true end
              end
          end
          return 0, 0, false
      end,
      -- Grey out when the boots are neither equipped nor in the bags.
      isEnabled = function()
          return BootsEquipped() or FindBootsInBags() ~= nil
      end,
      -- Amber "swap back!" border whenever the Rocket Boots are equipped; no
      -- border while they sit in the bags.
      resolveBorderColor = function()
          if BootsEquipped() then return ROCKET_AMBER end
          return nil
      end,
      -- Boots in bags: capture their (bag,slot) and equip them -- the displaced
      -- boots land at those same coords, so the swap-back uses the same numbers.
      -- Boots equipped: /use to fire the boost, and ONLY append the /equipslot
      -- swap-back when a cooldown is running (BootsOnCooldown) -- unequipping
      -- while the boots are ready/boosting cancels the boost, so a fresh /use
      -- must fire alone and the swap-back rides a later press.
      resolveMacro = function()
          if BootsEquipped() then
              local bag, slot = StoredBootsBagSlot()
              if bag and BootsOnCooldown() then
                  return string.format("/use %d\n/equipslot %d %d %d",
                      ROCKET_BOOTS_SLOT, ROCKET_BOOTS_SLOT, bag, slot)
              end
              return string.format("/use %d", ROCKET_BOOTS_SLOT)
          end
          local bag, slot = FindBootsInBags()
          if bag then
              RememberBootsBagSlot(bag, slot)
              return string.format("/equipslot %d %d %d", ROCKET_BOOTS_SLOT, bag, slot)
          end
          return ""
      end,
    },
}

ExsarUI.CreateActionBar({
    name                = "engineering",
    frameName           = "ExsarAddonEngineeringFrame",
    buttonPrefix        = "ExsarAddonEngineeringBtn",
    placeholder         = "Engineering",
    layout              = "horizontal",
    border              = true,
    actions             = TRACKED_ITEMS,
    moduleName          = "Engineering",
    configName          = "Engineering",
    defaultX            = 150,
    defaultY            = -200,
    slashReset          = "engineeringreset",
    bindingPrefix       = "EXSAR_ENGINEERING",
    bindingHeaderGlobal = "BINDING_HEADER_EXSARADDONENGINEERING",
    bindingHeaderText   = "ExsarAddon Engineering",
})
