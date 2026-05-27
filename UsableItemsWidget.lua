-- UsableItemsWidget module
-- A mini action bar of specific consumable items from the player's bags, built
-- on the shared ExsarUI.CreateActionBar engine (item-kind slots). Click an icon
-- to use the item; cooldowns show a sweep + countdown, out-of-stock items grey
-- out, and slots can swap between ranked / zone-gated alternates.
--
-- This file is now just the item table + a CreateActionBar call. The engine
-- owns construction, the grid layout (incl. the hideWhenEmpty / groupFallback
-- reflow for the Healthstone slot), bag scanning, alternate/rank swapping,
-- cooldown rendering (item CD via bag scan, or a player debuff via
-- cooldownDebuff -- e.g. Drums of Battle's Tinnitus), the keybind bridge, slash
-- reset, config rows and module registration. See the action-bar engine block
-- in ExsarUI.lua for the action-spec field reference.
--
-- Each slot is keybindable via Blizzard's Key Bindings UI under the "ExsarAddon"
-- category (Bindings.xml, EXSAR_USE_ITEM1..7). Labels are positional and generic
-- ("Mana Potion", etc.) so they stay accurate when the displayed item swaps.
-- Settings stored under ExsarAddonDB.usableItems.

-- col/row define fixed grid positions (0-based): col 0 = left, col 1 = right;
-- row 0 top .. row 3. `alternates` = ordered substitutes (first in-stock,
-- zone-gated alts first via SelectFirstInStock). `ranks` = highest-first
-- interchangeable IDs in one slot (SelectBestRank). `cooldownDebuff` drives the
-- cooldown from a player debuff rather than the item's own cooldown.
local TK_ZONES = {
    ["Tempest Keep"] = true,  -- the raid; GetRealZoneText() returns this, not "The Eye"
    ["The Eye"]      = true,
    ["The Botanica"] = true,
    ["The Arcatraz"] = true,
    ["The Mechanar"] = true,
}

local TRACKED_ITEMS = {
    { name = "Dark Rune", id = 20520, col = 0, row = 0, bindingLabel = "Mana Rune",
      alternates = {
          { name = "Demonic Rune", id = 12662 },
      } },
    { name = "Super Mana Potion", id = 22832, col = 0, row = 1, bindingLabel = "Mana Potion",
      alternates = {
          { name = "Bottled Nethergon Energy", id = 32902, zones = TK_ZONES },
          { name = "Crystal Mana Potion",      id = 33935 },
          { name = "Auchenai Mana Potion",     id = 32948 },
      } },
    { name = "Super Healing Potion", id = 22829, col = 1, row = 1, bindingLabel = "Health Potion",
      alternates = {
          { name = "Bottled Nethergon Vapor",  id = 32905, zones = TK_ZONES },
          { name = "Crystal Healing Potion",   id = 33934 },
          { name = "Auchenai Healing Potion",  id = 32947 },
      } },
    { name = "Drums of Battle", id = 29529, col = 0, row = 2, bindingLabel = "Drums of Battle",
      cooldownDebuff = "Tinnitus", useCharges = true },
    { name = "Haste Potion", id = 22838, col = 1, row = 2, bindingLabel = "Haste Potion" },
    { name = "Heavy Netherweave Bandage", id = 21991, col = 0, row = 3,
      bindingLabel = "Heavy Netherweave Bandage", cooldownDebuff = "Recently Bandaged" },
    { name = "Master Healthstone", id = 22105, col = 1, row = 3, bindingLabel = "Healthstone",
      hideWhenEmpty = true, groupFallback = true,
      ranks = {
          { name = "Master Healthstone", id = 22105 },
          { name = "Master Healthstone", id = 22104 },
          { name = "Master Healthstone", id = 22103 },
      } },
}

ExsarUI.CreateActionBar({
    name                = "usableItems",
    frameName           = "ExsarAddonUsableItemsFrame",
    buttonPrefix        = "ExsarAddonItemBtn",
    placeholder         = "Items",
    layout              = "grid",
    border              = true,
    actions             = TRACKED_ITEMS,
    moduleName          = "Usable Items",
    configName          = "Usable items",
    defaultX            = 150,
    defaultY            = -160,
    slashReset          = "itemsreset",
    bindingPrefix       = "EXSAR_USE_ITEM",
    bindingHeaderGlobal = "BINDING_HEADER_EXSARADDON",
    bindingHeaderText   = "ExsarAddon",
})
