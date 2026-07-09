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
    -- Melee weave: dual-edge macro (engine macroDown/macroUp -- see the dual-edge
    -- note in ExsarUI.lua's action-bar header). Swing on the press, /stopattack on
    -- the release. Releasing un-queues the melee attack, so a press that lands out
    -- of range never latches the 500ms melee retry timer -- which is what lets you
    -- spam this while stepping in and out (CLAUDE.md "The Melee Retry Timer").
    -- Keeping /stopattack on its own edge also means it lands after the swing has
    -- gone out rather than wrapped around it, which is reported to stop it eating
    -- Windfury procs.
    --
    -- The /console lines flip ActionButtonUseKeyDown so both edges dispatch: the
    -- press sets it to 0 (arming the release), the release sets it back to 1
    -- (arming the next press). RestoreKeyDownCVar below repairs it if a keypress
    -- is ever orphaned (reload / alt-tab between the edges) and leaves it at 0.
    --
    -- postClick stamps the press on the shared melee tracker so MeleeWeaveHelper
    -- can measure press -> landed-swing latency and spot a stale-position melee
    -- retry.
    { key = "raptorstrike", name = "Raptor Strike",
      macroDown = [[/stopcasting
/cast Raptor Strike
/startattack
/console ActionButtonUseKeyDown 0]],
      macroUp = [[/stopattack
/console ActionButtonUseKeyDown 1]],
      iconSpell     = "Raptor Strike",
      cooldownSpell = "Raptor Strike",
      rangeSpell    = "Raptor Strike",
      postClick     = function() ExsarUI.GetMeleeSwingTracker():NotePress(GetTime()) end },

    -- Start attacking: target the nearest enemy if we have no valid target,
    -- then turn on Auto Shot (! = ensure on, don't toggle off). No cooldown.
    { key = "autoshot", name = "Auto Shot",
      macro = [[/targetenemy [noexists][dead][help]
/cast !Auto Shot]],
      iconSpell  = "Auto Shot",
      rangeSpell = "Auto Shot",
      gcdSpell   = false },  -- Auto Shot is off-GCD; never show the GCD swirl here

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
    manaCheck           = true,  -- blue shade on shots you can't afford (precedence over range)
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

-- The weave slot's press macro sets ActionButtonUseKeyDown to 0 and its release
-- macro sets it back to 1. If the release never runs (reload, alt-tab, or a
-- disconnect between the two edges) the CVar is left at 0 -- a global setting
-- that would silently turn every action button into cast-on-release. Repair it
-- whenever we are safely out of combat. SetCVar is unavailable under lockdown,
-- so PLAYER_REGEN_ENABLED (not _DISABLED) is the right edge.
local cvarFrame = CreateFrame("Frame")
cvarFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
cvarFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
cvarFrame:SetScript("OnEvent", function()
    if GetCVar("ActionButtonUseKeyDown") ~= "1" then
        SetCVar("ActionButtonUseKeyDown", "1")
    end
end)
