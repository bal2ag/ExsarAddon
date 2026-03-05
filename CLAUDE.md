# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A World of Warcraft TBC Classic Anniversary addon for a Hunter character. The addon folder (`ExsarAddon/`) is the entire repository — WoW loads it from `Interface/AddOns/ExsarAddon/`.

## Installing / Testing

Copy (or symlink) the repo folder into your WoW client's addon directory:
```
World of Warcraft/_classic_/Interface/AddOns/ExsarAddon/
```
Then reload the UI in-game with `/reload`. There is no build step.

## In-Game Commands

- `/exsar config` — open the configuration panel (also available via Interface → AddOns)
- `/exsar lock` / `/exsar unlock` — toggle movement lock on the cooldown tracker widget
- `/exsar reset` — reset the cooldown tracker widget position

## Architecture

| File | Purpose |
|---|---|
| `ExsarAddon.toc` | Addon metadata, interface version, SavedVariables declaration |
| `Core.lua` | `ExsarAddon` namespace, module registration API, shared config widget helpers, config panel, slash command dispatch, DB init |
| `CooldownTracker.lua` | Cooldown tracker feature module |
| `SwingTimer.lua` | Ranged auto shot cycle tracker |
| `CastBar.lua` | Cast bar for hunter shots (Auto Shot aim window, Aimed Shot, Steady Shot, Multi-Shot) |
| `KillCommandAlert.lua` | Pulsing aura indicator when Kill Command is off cooldown and pet is active |
| `ActiveEffectsTracker.lua` | Icons with marching-ants border and countdown for active buffs (Quick Shots, Haste Potion, Bloodlust, Heroism, Rapid Fire, The Beast Within, Drums of Battle) plus trinket on-use buffs |
| `UsableItemsWidget.lua` | Mini action bar showing consumables in bags (Super Healing Potion 22829, Super Mana Potion 22832, Haste Potion 22838, Drums of Battle 29529); click to use; Drums cooldown driven by Tinnitus debuff |
| `TargetDebuffTracker.lua` | Single-column vertical widget showing tracked debuffs (Hunter's Mark, Serpent Sting) currently active on the player's target; marching-ants border, reverse sweep, countdown timer |

**Adding a new feature module:**
1. Create a new `.lua` file and add it to `ExsarAddon.toc`
2. Call `ExsarAddon.RegisterModule({ name = "...", BuildConfig = function(parent, y) ... return y end })`
3. Call `ExsarAddon.AddSlashCommand(cmd, fn)` for any slash sub-commands
4. Store settings under `ExsarAddonDB.<moduleName>` (use a lazy-init helper like `cDB()` in CooldownTracker.lua)

**Core API available to modules:**
- `ExsarAddon.RegisterModule(module)` — registers the module; `module.BuildConfig(parent, y)` must return the final y position after placing widgets
- `ExsarAddon.AddSlashCommand(cmd, fn)` — adds a `/exsar <cmd>` handler
- `ExsarAddon.CreateSlider(parent, label, x, y, min, max, step, getter, setter)`
- `ExsarAddon.CreateCheckbox(parent, label, x, y, getter, setter)`
- `ExsarAddon.CreateButton(parent, label, x, y, onClick)`

**`CooldownTracker.lua` structure:**
- `SPELL_GROUPS` — defines spells in display order; entries with `id` are talent-gated (hidden unless `IsSpellKnown(id)`)
- `mainFrame` — movable widget; position/scale/lock saved in `ExsarAddonDB.cooldownTracker`
- `ApplyLayout(gap)` — repositions visible frames and resizes the widget; called when known spells or group spacing changes
- `UpdateKnownSpells()` — checks spellbook, loads icon textures, calls `ApplyLayout`; triggered by `PLAYER_ENTERING_WORLD` and `SPELLS_CHANGED`
- `UpdateCooldowns()` — runs every 0.1s via `OnUpdate` and on `SPELL_UPDATE_COOLDOWN`

**`SwingTimer.lua` structure:**
- Bar drains from full width to zero width (centered) over the ranged weapon speed cycle; resets on each Auto Shot
- `S.speed` — hasted weapon speed from `UnitRangedDamage("player")`, refreshed on `UNIT_AURA` and `PLAYER_EQUIPMENT_CHANGED`
- `S.aimWindow` — stop-moving window = `0.5 + latency` (seconds); the ~0.5s shot wind-up animation plus server latency
- Single pair of red reticules at `aimWindow / speed` fraction from center
- `UNIT_SPELLCAST_SUCCEEDED` resyncs `lastShotTime`; checks both `arg2 == spellName` (old TBC API) and `arg3/arg5 == spellID` (modern API)
- Aimed Shot landing and Feign Death also handled in `UNIT_SPELLCAST_SUCCEEDED` (reset/clear the cycle)
- Bar color: blue (safe) → red (stop moving / aim window active)
- `SPELLS_CHANGED` triggers a 0.5s deferred `RefreshAll()` to handle talent-driven speed changes
- Clip indicator: shows `(X.X)` seconds between the reticules when an active cast will delay the next auto shot

**`CastBar.lua` structure:**
- `autoAimTicker` — always-running frame that detects the Auto Shot aim window from `lastAutoTime + autoSpeed - AUTO_AIM_TIME` and shows a green bar
- Regular casts (Aimed Shot, Steady Shot) detected via `UNIT_SPELLCAST_START` → `UnitCastingInfo`
- Multi-Shot detected via `COMBAT_LOG_EVENT_UNFILTERED` / `SPELL_CAST_START` using `CombatLogGetCurrentEventInfo()` (required for TBC Classic Anniversary modern client; old variadic-args approach does not work)
- `UNIT_SPELLCAST_FAILED` / `UNIT_SPELLCAST_INTERRUPTED` → brief red flash before hiding
- Bar colors: green (Auto Shot aim), gold (Aimed Shot), blue (Steady Shot), orange (Multi-Shot)

**`KillCommandAlert.lua` structure:**
- Two eagle-wing crescents flanking the player, each built from 7 feather strokes via `frame:CreateLine()`; each feather has a wide low-alpha glow line (ARTWORK) plus a narrow bright core line (OVERLAY)
- Two background glow discs (one per wing, ±70px from center) use `SetMask` for circular shape, applied via `pcall`
- `IsReady()` — dual check: `IsUsableSpell(K.killCmdName)` (proc active) AND `GetSpellCooldown` `duration <= 1.6` (GCD only, not the 60s cooldown after casting)
- `SPELL_UPDATE_USABLE` + `SPELL_UPDATE_COOLDOWN` + `UNIT_PET` events drive `UpdateAura()` for fast response; a 0.5s `pollFrame` catches missed transitions
- `frame:SetAlpha()` in OnUpdate pulses the entire frame at ~0.8 Hz (65%–100% alpha), avoiding per-line iteration

## Key WoW API Used

- `GetSpellInfo(spellName)` — returns name, rank, icon texture path for the highest-learned rank
- `GetSpellCooldown(spellName)` — returns `start, duration, enable`; `start=0` means no cooldown
- `IsSpellKnown(spellId)` — checks if a spell is in the player's spellbook (modern client); falls back to `GetSpellInfo ~= nil`
- `CooldownFrameTemplate` — built-in frame template providing the circular sweep animation
- `SetDesaturated(bool)` — grays out a texture
- `SetCooldown(start, duration)` — drives the sweep on a Cooldown frame
- `CombatLogGetCurrentEventInfo()` — unpacks combat log event data; required on TBC Classic Anniversary (modern client); replaces the old variadic-args approach
- `texture:SetMask(path)` — clips a texture to the shape of a mask image; used for circular glow discs; wrapped in `pcall` for safety
- `UnitExists("pet")` — true when the player has an active pet

## Lua Version Note

The WoW Classic client uses **Lua 5.1**. Do not use `goto`, `<const>`, `<close>`, or other Lua 5.2+ features.

## Interface Version

The `.toc` file uses `## Interface: 20505` (TBC Classic Anniversary). To verify in-game:
```
/run print(select(4, GetBuildInfo()))
```

## SecureActionButtonTemplate in TBC Classic Anniversary

TBC Classic Anniversary uses the modern WoW client with `ActionButtonUseKeyDown = 1` by default. `SecureActionButton_OnClick` only fires on **down** events, so buttons registered with only `"AnyUp"` silently do nothing. Always use:
```lua
btn:RegisterForClicks("AnyUp", "AnyDown")
```
Avoid adding non-secure `SetScript("OnClick")` or `HookScript("OnClick")` to a `SecureActionButtonTemplate` button — this can taint the button and prevent the secure action. Use `PreClick`/`PostClick` for any surrounding logic instead. Also avoid cross-parent `SetAllPoints` anchoring on secure buttons (e.g. a UIParent-child secure button anchored to a child of a custom frame) — the anchor silently fails and `GetCenter()` returns nil.

## SavedVariables

`ExsarAddonDB` is the top-level table. Each module namespaces its settings:
- `ExsarAddonDB.cooldownTracker` — position (x, y), scale, locked, groupGap
- `ExsarAddonDB.swingTimer` — position (x, y), scale, width, locked
- `ExsarAddonDB.castBar` — position (x, y), scale, width, locked
- `ExsarAddonDB.killCommandAlert` — position (x, y), scale, size, locked
- `ExsarAddonDB.activeEffects` — position (x, y), scale, locked
- `ExsarAddonDB.usableItems` — position (x, y), scale, locked
- `ExsarAddonDB.targetDebuffs` — position (x, y), scale, locked
