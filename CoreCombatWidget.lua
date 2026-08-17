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

local ccDB = ExsarUI.MakeDB("coreCombat")

-- A plain ability slot: casts the highest known rank; icon/tooltip/cooldown
-- follow the spell; hides when the spell isn't known (e.g. talent-gated).
local function ability(name)
    return { key = name, name = name, spells = { name } }
end

-- =========================================================
-- Rank-pinned abilities
-- =========================================================
-- Some abilities are worth casting BELOW the highest known rank. Rank 1 Wing
-- Clip is the standard case: the same 10s snare for less mana, and with far less
-- damage -- so it costs almost no threat and is much less likely to finish off a
-- mob you meant to keep snared (or to break a nearby crowd control).
--
-- "/cast <name>" always fires the top rank, so a pin is expressed by appending
-- the LOCALIZED rank subtext ("/cast Wing Clip(Rank 1)"), read from the
-- spellbook rather than assembled here. The pin lives in
-- ExsarAddonDB.coreCombat.ranks[<key>] (absent/0 = highest known) and reaches
-- the secure button through the engine's resolveMacro hook, which writes the new
-- macrotext via ExsarUI.SecureSetAttribute -- so changing it in combat queues the
-- write until PLAYER_REGEN_ENABLED. The config note says as much.

local RANK_PINNED = {}   -- rank-pinned actions, in bar order; drives the config rows

-- name -> ordered list of that spell's rank subtexts ("Rank 1", ...), scanned
-- from the spellbook. Cached (the poll would otherwise re-scan 10x a second) and
-- dropped on SPELLS_CHANGED, which is when a newly trained rank appears.
local rankCache  = {}
-- key -> { pin = <index>, text = <macrotext> }: the resolved macro for the
-- current pin, so the poll only rebuilds it when the setting actually moves.
local rankMacros = {}

local function KnownRanks(spellName)
    local cached = rankCache[spellName]
    if cached then return cached end
    local ranks = {}
    local i = 1
    while true do
        -- "spell" is BOOKTYPE_SPELL; indices run contiguously across the tabs
        -- and return nil past the last spell. In TBC every rank is its own entry.
        local n, sub = GetSpellBookItemName(i, "spell")
        if not n then break end
        if n == spellName and sub and sub ~= "" then ranks[#ranks + 1] = sub end
        i = i + 1
    end
    -- Don't cache an empty scan -- the spellbook may just not be populated yet.
    if #ranks > 0 then rankCache[spellName] = ranks end
    return ranks
end

-- The pinned rank index for an action; 0 = cast the highest known rank.
local function RankPin(key)
    local t = ccDB().ranks
    return (t and t[key]) or 0
end

local function SetRankPin(key, index)
    local db = ccDB()
    db.ranks = db.ranks or {}
    db.ranks[key] = index > 0 and index or nil   -- default (highest) stays absent
    rankMacros[key] = nil
end

local function RankedMacro(key, name)
    local pin = RankPin(key)
    local c = rankMacros[key]
    if not c or c.pin ~= pin then
        c = { pin = pin, text = ExsarLogic.RankedCastMacro(name, KnownRanks(name), pin) }
        rankMacros[key] = c
    end
    return c.text
end

-- Tooltip for a rank-pinned slot: the tooltip of the rank actually being cast
-- (so pinning rank 1 shows rank 1's numbers), plus a line naming the pin. Falls
-- back to the base spell if the ranked link can't be resolved.
local function ShowRankTooltip(tt, key, name)
    local ranks = KnownRanks(name)
    local pin   = RankPin(key)
    local link  = GetSpellLink(ExsarLogic.RankedCastName(name, ranks, pin))
                  or GetSpellLink(name)
    if link then tt:SetHyperlink(link) else tt:SetText(name, 1, 1, 1) end
    if pin > 0 then
        tt:AddLine("Pinned to " .. ExsarLogic.RankPinLabel(ranks, pin), 0.6, 0.8, 1.0)
    end
end

-- A rank-pinned ability slot. Behaves like ability() -- icon, cooldown, range
-- and mana shades all follow the base spell -- except the cast rank comes from
-- config. `maxRank` is how many ranks the spell has in TBC and only bounds the
-- slider; a pin above what the character has trained falls back to highest known.
local function rankable(name, maxRank)
    local key = name
    local a = {
        key = key, name = name, spells = { name }, maxRank = maxRank,
        resolveMacro = function() return RankedMacro(key, name) end,
        tooltip      = function(_, tt) ShowRankTooltip(tt, key, name) end,
    }
    RANK_PINNED[#RANK_PINNED + 1] = a
    return a
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
    rankable("Wing Clip", 3),    -- rank 1 is the low-damage/low-threat kiting snare
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

    -- One rank slider per rank-pinned ability (see the rank-pin block above).
    -- 0 = highest known, which is what a plain "/cast" does.
    extraConfig = function(parent, y)
        for _, a in ipairs(RANK_PINNED) do
            ExsarAddon.CreateSlider(parent, a.name .. " rank", 16, y,
                0, a.maxRank, 1,
                function() return RankPin(a.key) end,
                function(v) SetRankPin(a.key, math.floor(v + 0.5)) end,
                function(v)
                    return ExsarLogic.RankPinLabel(KnownRanks(a.name), math.floor(v + 0.5))
                end
            )
            y = y - 55
        end

        local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
        note:SetWidth(360)
        note:SetJustifyH("LEFT")
        note:SetText("Pins the rank the bar casts. Rank 1 Wing Clip is the same "
            .. "snare for less mana and far less damage, so it costs little threat "
            .. "and won't finish off a mob you meant to keep kited.\n"
            .. "Changing this in combat is queued: the button's macro is protected, "
            .. "so the new rank takes effect when you leave combat.")
        y = y - 80

        return y
    end,
})

-- Ranks are read from the spellbook and cached; drop the cache when a new rank
-- is trained (or the spellbook first populates) so the pin can reach it.
local rankFrame = CreateFrame("Frame")
rankFrame:RegisterEvent("SPELLS_CHANGED")
rankFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
rankFrame:SetScript("OnEvent", function()
    rankCache, rankMacros = {}, {}
end)

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
