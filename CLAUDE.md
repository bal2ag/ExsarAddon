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

## Quality Checks

Run these before committing changes:
- `busted` — runs unit tests (155 tests covering ExsarLogic and MakeDB)
- `luacheck .` — static analysis; should report 0 warnings / 0 errors
- `luac -p *.lua` — syntax check (redundant with luacheck but faster)

The `.luacheckrc` config declares all WoW API globals, addon cross-file globals, and test file exceptions. When adding new WoW API calls, add them to the `read_globals` list in `.luacheckrc`.

## In-Game Commands

- `/exsar config` — open the configuration panel (also available via Interface → AddOns)
- `/exsar lock` / `/exsar unlock` — toggle movement lock on the cooldown tracker widget
- `/exsar reset` — reset the cooldown tracker widget position

## Architecture

| File | Purpose |
|---|---|
| `ExsarAddon.toc` | Addon metadata, interface version, SavedVariables declaration |
| `ExsarLogic.lua` | Pure Lua logic helpers (no WoW API dependency); testable outside the client. Timer formatting, health colors, cooldown state, grid math, anchor offset calc, etc. |
| `ExsarUI.lua` | Shared WoW UI construction helpers. `MakeDB`, `SetupMovableFrame`, `SetupTopleftFrame`, `RestorePosition`, `CreateIcon`, `CreateSweep`, `CreateAuraIcon`, `CreateGlow`, `BuildDashes`, `AnimateDashes`, config panel helpers (`AddScaleSlider`, `AddLockCheckbox`, `AddResetButton`), `POWER_COLORS` |
| `Core.lua` | `ExsarAddon` namespace, module registration API, shared config widget helpers, config panel, slash command dispatch, DB init |
| `CooldownTracker.lua` | Cooldown tracker feature module |
| `RangedSwingTimer.lua` | Ranged auto shot cycle tracker |
| `CastBar.lua` | Cast bar for hunter shots (Auto Shot aim window, Aimed Shot, Steady Shot, Multi-Shot) |
| `KillCommandAlert.lua` | Pulsing aura indicator when Kill Command is off cooldown and pet is active |
| `ActiveEffectsTracker.lua` | Icons with marching-ants border and countdown for active buffs (Quick Shots, Haste Potion, Bloodlust, Heroism, Rapid Fire, The Beast Within, Drums of Battle) plus trinket on-use buffs |
| `UsableItemsWidget.lua` | Mini action bar showing consumables in bags (Super Healing Potion 22829, Super Mana Potion 22832, Haste Potion 22838, Drums of Battle 29529); click to use; Drums cooldown driven by Tinnitus debuff |
| `TargetDebuffTracker.lua` | Single-column vertical widget showing tracked debuffs (Hunter's Mark, Serpent Sting) currently active on the player's target; marching-ants border, reverse sweep, countdown timer |
| `MendPetTracker.lua` | Mend Pet HoT tracker |
| `FoodAndDrinkWidget.lua` | Food/drink icons, dims in combat |
| `ConsumableBuffWidget.lua` | Always-visible consumable buff icons with bag counts, marching-ants + reverse sweep when buff active; supports ranked item fallback (e.g. Scroll of Agility V→I) and weapon enchant tracking |
| `MountWidget.lua` | Mount-related widget |
| `TargetInfoWidget.lua` | Target portrait/health/auras, hides when no target |
| `PlayerInfoWidget.lua` | Player portrait/health/auras, always visible (toggleable); low-HP burst warning with optional sound alert |
| `PetInfoWidget.lua` | Pet portrait/health/auras, shows only when pet exists; low-HP burst warning and damage border with optional sound alerts |
| `AspectTracker.lua` | Aspect of the Pack warning — pulses red glow + red marching-ants when Pack is active in combat |
| `MeleeRangeIndicator.lua` | Crossed-swords icon showing melee range status; cooldown sweep for swing timer; pulsating gold glow ring when swing is ready in range; optional range-change sound effects |
| `GlobalCooldownTracker.lua` | Global cooldown tracker |
| `RaidTargetWidget.lua` | Compact info for all units marked with raid target icons; click to target; scans nameplates + party/raid targets |
| `PetAggressiveAlert.lua` | Pulsing red skull + text when pet is on aggressive mode |
| `PetHappinessTracker.lua` | Granular happiness gauge estimating exact happiness points (0–1050); reverse sweep + timer showing time until tier drop; optional sound alert on happiness drop |
| `AggroAlert.lua` | Pulsating red text alert when enemy mobs are targeting the player; scans nameplates + party/raid target-of-target; configurable for solo/party/raid contexts; plays raid warning sound on aggro gain |

**Adding a new feature module:**
1. Create a new `.lua` file and add it to `ExsarAddon.toc` (after `ExsarUI.lua` and `Core.lua`)
2. Call `ExsarAddon.RegisterModule({ name = "...", BuildConfig = function(parent, y) ... return y end })`
3. Call `ExsarAddon.AddSlashCommand(cmd, fn)` for any slash sub-commands
4. Store settings under `ExsarAddonDB.<moduleName>` via `ExsarUI.MakeDB("moduleName")`

**Code reuse principle:** Always prefer using shared helpers from `ExsarLogic.lua` and `ExsarUI.lua` over writing bespoke code. When building a new widget, check the shared libraries first — most common patterns are already available. If you write new logic that could be reused by other modules, extract it into the appropriate shared library: pure logic goes in `ExsarLogic.lua` (testable without WoW API), UI construction goes in `ExsarUI.lua`. Never duplicate code across module files. Refer to UI effects by their standard names (see below) and always use the shared implementation.

**Testability principle:** Design new code to be unit-testable wherever possible. Extract logic into pure functions in `ExsarLogic.lua` so it can be tested with `busted` without WoW API mocks. When writing ExsarUI helpers, accept dependencies as parameters (tables with callable fields) rather than hardcoding WoW API calls, so they can be tested with lightweight stubs. Every new function added to `ExsarLogic.lua` should have corresponding tests in `tests/test_logic.lua`. New ExsarUI helpers should have contract tests in `tests/test_makedb.lua` (or a new test file) using stub tables. Run `busted` and `luacheck .` before considering any change complete.

**Standard UI effects** (defined in `ExsarUI.lua` and `ExsarLogic.lua`):

| Effect | Description | API |
|---|---|---|
| **Active Glow** | Solid colored rectangle extending beyond an icon edge, used to indicate active/ready state. Gold by default; also used as a 1px border ring (size=1) or red warning glow. | `ExsarUI.CreateGlow(frame, r, g, b, a, size, layer)` |
| **Marching Ants** | Animated gold dashed border rotating around an icon perimeter. A bright trailing tail fades behind the head. Standard params: 16 dashes, speed 1.5, tail length 5. | `ExsarUI.BuildDashes(iconFrame, iconSize, dashCount, borderW)` + `ExsarUI.AnimateDashes(slots, now, speed, dashCount, tailLen)` (or `ExsarLogic.MarchingAntHead` / `MarchingAntAlpha` for custom per-dash logic) |
| **Cooldown Sweep** | WoW's built-in circular pie-chart timer overlay. Normal mode fills as cooldown elapses; reverse mode empties as a buff expires. | `ExsarUI.CreateSweep(frame, { reverse = bool })` |
| **Red X** | Two diagonal red lines forming an X across an icon, indicating an inactive or missing state. | `ExsarUI.CreateRedX(frame, inset, thickness)` |
| **Pulse** | Sine-wave alpha oscillation (breathing effect). Used for alert/ready indicators. Params: frequency (Hz), min/max alpha. | `ExsarLogic.PulseAlpha(time, frequency, minAlpha, maxAlpha)` |
| **Dimmed** | Desaturated + reduced alpha for unavailable/out-of-stock items. Standard: `SetDesaturated(true)` + `SetAlpha(0.35)`. In-combat dimming: `SetAlpha(0.5)`, no desaturation. | Inline pattern (icon:SetDesaturated / icon:SetAlpha) |

When adding a new widget that needs a highlight, border, alert, or status indicator, use one of these standard effects rather than creating a bespoke visual.

**Sound effects pattern:**
Several modules play `PlaySound(soundKitID, "Master")` on state transitions (e.g. aggro gained, low HP threshold crossed, melee range entered/left). Standard pattern:
- Track the previous state to detect edges (e.g. `wasActive` → `isActive`)
- Use a cooldown timer (`GetTime() - lastSoundTime >= COOLDOWN`) to prevent spam
- Gate behind a per-module DB flag (e.g. `db.lowHpSound ~= false`) with a config checkbox
- Defaults to enabled (`~= false` check, so `nil` counts as enabled)

**Ranked item fallback** (`ConsumableBuffWidget`):
Items with a `ranks` field (array of `{ name, id, buffId }` ordered highest-first) automatically show the highest rank with bag stock, falling back to the highest rank (greyed out) when none are available. Uses `ExsarLogic.SelectBestRank(ranks, getCount)` for the selection logic. Buff detection checks all rank buff IDs. Secure button `item` attribute is updated out of combat when the active rank changes.

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

**`RangedSwingTimer.lua` structure:**
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

**`AggroAlert.lua` structure:**
- Pulsating red text with thick outline (`FRIZQT__ 18pt, OUTLINE, THICKOUTLINE`) + red glow border (4-edge textures)
- Aggro scanning combines three strategies, deduplicated by GUID: (1) player target + pet target, (2) party/raid members' targets (`party1target`..`party4target`, `raid1target`..`raid40target`, boss frames), (3) nameplate units tracked via `NAME_PLATE_UNIT_ADDED`/`REMOVED`
- Each candidate unit checked with `UnitIsEnemy` + `not UnitIsDead` + `UnitIsUnit(unit.."target", "player")`
- Group context gating via `ExsarLogic.AggroAlertEnabled` — configurable checkboxes for solo/party/raid
- Sound plays on aggro gain edge (not active → active) with 3s cooldown
- Placeholder text shown when unlocked; glow border shown in both active and unlocked states

**`MeleeRangeIndicator.lua` structure:**
- Crossed-swords icon with circular mask background; gold/grey color modes for in-range/out-of-range
- Range check via `IsSpellInRange("Wing Clip", "target")` polled at 0.1s; only shown in combat
- Swing timer from combat log `SWING_DAMAGE`/`SWING_MISSED` + Raptor Strike spell IDs
- Three visual states: ready (full alpha + gold swords + glow ring + blade glow), on-cooldown (half alpha + sweep), out-of-range (grey + half alpha + sweep)
- Pulsating gold glow ring (3.0 Hz) behind the icon in ready state only
- Optional enter/leave range sound effects (SoundKit 154 / 698)

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
- `PlaySound(soundKitID [, channel])` — plays a built-in sound; use `"Master"` channel for alerts that must be heard regardless of SFX volume
- `IsInRaid()` / `IsInGroup()` — group context detection; solo = not `IsInGroup()`
- `UnitIsUnit(unit1, unit2)` — true if both unit tokens refer to the same entity
- `GetWeaponEnchantInfo()` — returns `hasMainEnchant, mainExpMs, mainCharges, mainEnchantId, hasOffEnchant, ...`; `mainExpMs` is milliseconds remaining; returns only remaining time, NOT total duration — total duration must be hardcoded if needed (e.g. for sweep animation). Use `mainEnchantId` to distinguish between different temporary enchants (e.g. Adamantite Sharpening Stone = 2713, Windfury Weapon = 2636)

## Hunter Ability Timing Reference (from diziet559/rotationtools)

Source: https://github.com/diziet559/rotationtools/ — the authoritative TBC hunter rotation simulator.

### Base Cast Times and Haste Interaction

| Ability | Base Duration | Haste-Affected? | Formula |
|---|---|---|---|
| Auto Shot wind-up | 0.5s | Yes | `0.5 / totalRangedHaste` |
| Auto Shot cooldown | `weaponSpeed - 0.5` | Yes | `(weaponSpeed - 0.5) / totalRangedHaste` |
| Full Auto Shot cycle | `weaponSpeed` | Yes | `weaponSpeed / totalRangedHaste` (= effective weapon speed) |
| Steady Shot | 1.5s | Yes | `1.5 / totalRangedHaste` |
| Multi-Shot | 0.5s | Yes | `0.5 / totalRangedHaste` (NOT instant — same base as Auto Shot wind-up) |
| Arcane Shot | ~0.1s | No | Fixed; effectively instant |
| GCD | 1.5s | **No** | Fixed at 1.5s; ranged GCD is NOT reduced by haste in TBC |
| Melee weave | ~0.4s | No | Fixed time to step in, swing, step out |

### Haste Stacking

Haste sources stack **multiplicatively** (buff-based) on top of an **additive** haste-rating base:

```
base_haste = 1 + haste_rating / 1577   (15.8 rating = 1% haste at level 70)
-- Drums of Battle (+80 rating = +5.06%) and Haste Potion (+400 rating = +25.32%)
-- are additive with haste rating, applied before multiplicative buffs.

general_haste = base_haste * [bloodlust 1.30 if active]
ranged_haste  = general_haste * 1.15(quiver) * 1.20(Serpent's Swiftness 5/5)
                * [1.40 Rapid Fire if active] * [1.15 Imp Hawk proc if active]
```

### Key Haste Source Values

| Source | Multiplier | Scope |
|---|---|---|
| Quiver (15%) | ×1.15 | Ranged only |
| Serpent's Swiftness (BM 5/5) | ×1.20 | Ranged only |
| Rapid Fire | ×1.40 | Ranged only; 15s duration (19s with 2pc T3) |
| Imp Aspect of the Hawk (5/5) | ×1.15 | Ranged only; 10% proc chance, 12s duration |
| Bloodlust / Heroism | ×1.30 | Both melee and ranged |
| Drums of Battle | +5.06% | Additive with haste rating |
| Haste Potion | +25.32% | Additive with haste rating |

### Auto Shot Cycle Model

The auto shot cycle has two phases:
1. **Wind-up (cast)**: 0.5s base, haste-reduced — hunter must be stationary
2. **Cooldown**: `(weaponSpeed - 0.5) / haste` — free to move or cast other spells

When standing still, the game auto-starts the wind-up so it completes exactly at cycle end. When stopping from movement, the full unhasted 0.5s wind-up plays from the stop point (observed in-game; the sim does not model movement).

**Clipping**: If a cast (Steady Shot, etc.) is still in progress when the auto shot becomes available, the auto is delayed until the cast finishes. The delay = `castEndTime - autoAvailableTime`.

### Widget Implications

- **Swing timer reticules**: Mark the hasted clip window (`0.5 / haste + latency`) — shows when starting a new cast would delay the next auto shot
- **Cast bar (standing still auto aim)**: Uses hasted clip window duration
- **Cast bar (after stopping from movement)**: Uses unhasted 0.5s + latency — the actual wind-up time
- **Cast bar (Multi-Shot)**: Should use `0.5 / haste`, NOT a fixed 0.5s
- **GCD tracker**: Must use fixed 1.5s, NOT haste-reduced

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
- `ExsarAddonDB.rangedSwingTimer` — position (x, y), scale, width, locked
- `ExsarAddonDB.castBar` — position (x, y), scale, width, locked
- `ExsarAddonDB.killCommandAlert` — position (x, y), scale, size, locked
- `ExsarAddonDB.activeEffects` — position (x, y), scale, locked
- `ExsarAddonDB.usableItems` — position (x, y), scale, locked
- `ExsarAddonDB.targetDebuffs` — position (x, y), scale, locked
- `ExsarAddonDB.consumableBuff` — position (x, y), scale, locked
- `ExsarAddonDB.targetInfo` — position (x, y), scale, locked
- `ExsarAddonDB.playerInfo` — position (x, y), scale, locked, enabled, lowHpThreshold, lowHpSound
- `ExsarAddonDB.petInfo` — position (x, y), scale, locked, enabled, lowHpThreshold, lowHpSound, dmgSound
- `ExsarAddonDB.meleeRange` — position (x, y), scale, locked, rangeSound
- `ExsarAddonDB.raidTargets` — position (x, y), scale, locked
- `ExsarAddonDB.petAggressiveAlert` — position (x, y), scale, locked, disabled
- `ExsarAddonDB.petHappiness` — position (x, y), scale, locked, savedEstimate, savedTier, savedAnchored, happinessSound
- `ExsarAddonDB.aggroAlert` — position (x, y), scale, locked, disabled, enableSolo, enableParty, enableRaid
