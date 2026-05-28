-- CooldownsWidget module
-- A keybindable mini action bar of major cooldowns -- a mix of trinkets and
-- (talent-gated) spells -- built on the shared ExsarUI.CreateActionBar engine.
-- Click or keybind a slot to fire it; each slot shows a cooldown sweep +
-- countdown and dims while on cooldown (engine `dimOnCooldown`).
--
-- This file is just the action table + a CreateActionBar call. See the
-- action-bar engine block in ExsarUI.lua for the action-spec field reference.
--
-- Slot kinds used here:
--   * Trinkets  -> `trinketSlot` (13 = top, 14 = bottom): the engine uses
--     /use <slot>, GetInventoryItemTexture for the icon, and
--     GetInventoryItemCooldown for the sweep. Follows whatever is equipped.
--   * Spells    -> `spells` (talent-gated): casts the first KNOWN spell, icon +
--     cooldown follow it, and the slot HIDES when none are known. This handles
--     "Bestial Wrath, or Readiness if Survival" (one slot, two spells) and
--     "Intimidation only if Beast Mastery" (one spell, hidden otherwise).
--
-- Spells cast at highest known rank (the macros are /cast <name>, no rank).
-- Each slot is keybindable via Blizzard's Key Bindings UI (Bindings.xml,
-- EXSAR_COOLDOWN1..5, "ExsarAddon Cooldowns" category). Keys live in Blizzard's
-- binding set (no SavedVariables). Settings under ExsarAddonDB.cooldowns.

-- MAX_SLOTS must match the number of EXSAR_COOLDOWN bindings declared in
-- Bindings.xml. Grow COOLDOWNS, MAX_SLOTS, and Bindings.xml together.
local MAX_SLOTS = 7

-- TBC spell IDs for the talent-gated known-check (IsSpellKnown).
local COOLDOWNS = {
    { key = "trinket13", name = "Top Trinket",    trinketSlot = 13 },
    { key = "trinket14", name = "Bottom Trinket", trinketSlot = 14 },

    -- Bestial Wrath (BM 31-pt) or Readiness (Survival 31-pt) -- whichever is
    -- known. A Marksmanship hunter knows neither, so the slot hides.
    { key = "bw_readiness", name = "Bestial Wrath / Readiness",
      spells = {
          { name = "Bestial Wrath", id = 19574 },
          { name = "Readiness",     id = 23989 },
      } },

    -- Rapid Fire -- baseline, always known.
    { key = "rapidfire", name = "Rapid Fire",
      spells = { { name = "Rapid Fire", id = 3045 } } },

    -- Intimidation (BM talent) -- slot hidden unless known.
    { key = "intimidation", name = "Intimidation",
      spells = { { name = "Intimidation", id = 19577 } } },

    -- Burst macros: a cooldown spell fired together with a trinket. The sweep
    -- takes the longest-remaining of the spell and the trinket slot (cooldownSpell
    -- + cooldownTrinket), so the slot only reads "ready" when BOTH are. Icon is
    -- the spell; the multi-action macro auto-shows its macro text on hover. Kept
    -- alongside the standalone slots above so each can be bound to its own key.
    { key = "bw_trinket", name = "Bestial Wrath + Trinket",
      macro = [[/cast Bestial Wrath
/use 14]],
      iconSpell       = "Bestial Wrath",
      cooldownSpell   = "Bestial Wrath",
      cooldownTrinket = 14 },

    { key = "rf_trinket", name = "Rapid Fire + Trinket",
      macro = [[/cast Rapid Fire
/use 13]],
      iconSpell       = "Rapid Fire",
      cooldownSpell   = "Rapid Fire",
      cooldownTrinket = 13 },
}

assert(#COOLDOWNS == MAX_SLOTS, "COOLDOWNS count must equal MAX_SLOTS")

ExsarUI.CreateActionBar({
    name                = "cooldowns",
    frameName           = "ExsarAddonCooldownsFrame",
    buttonPrefix        = "ExsarAddonCooldownBtn",
    placeholder         = "Cooldowns",
    layout              = "horizontal",
    dimOnCooldown       = true,
    actions             = COOLDOWNS,
    moduleName          = "Cooldowns",
    configName          = "Cooldowns",
    defaultX            = 200,
    defaultY            = -320,
    slashReset          = "cooldownsreset",
    bindingPrefix       = "EXSAR_COOLDOWN",
    bindingCount        = MAX_SLOTS,
    bindingHeaderGlobal = "BINDING_HEADER_EXSARADDONCOOLDOWNS",
    bindingHeaderText   = "ExsarAddon Cooldowns",
})
