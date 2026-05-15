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
- `busted` — runs unit tests (193 tests covering ExsarLogic and MakeDB)
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
| `ExsarUI.lua` | Shared WoW UI construction helpers. `MakeDB`, `SetupMovableFrame`, `SetupTopleftFrame`, `RestorePosition`, `CreateIcon`, `CreateSweep`, `CreateAuraIcon`, `CreateGlow`, `BuildDashes`, `AnimateDashes`, `ShowCopyableText` (modal copy-paste window), config panel helpers (`AddScaleSlider`, `AddLockCheckbox`, `AddResetButton`), `POWER_COLORS` |
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
| `MeleeRangeIndicator.lua` | Crossed-swords icon showing melee range status; cooldown sweep for swing timer; pulsating gold glow ring when swing is ready in range; always-on red-X-on-grey cue while in combat and out of range; optional range-change sound effects |
| `GlobalCooldownTracker.lua` | Global cooldown tracker |
| `RaidTargetWidget.lua` | Compact info for all units marked with raid target icons; click to target; scans nameplates + party/raid targets |
| `PetAggressiveAlert.lua` | Pulsing red skull + text when pet is on aggressive mode |
| `PetHappinessTracker.lua` | Granular happiness gauge estimating exact happiness points (0–1050); reverse sweep + timer showing time until tier drop; optional sound alert on happiness drop |
| `AggroAlert.lua` | Pulsating red text alert when enemy mobs are targeting the player; scans nameplates + party/raid target-of-target; configurable for solo/party/raid contexts; plays raid warning sound on aggro gain |
| `AmmoTracker.lua` | Equipped ammunition icon with bag-count overlay; red X when no ammo equipped; pulses a red low-ammo warning glow when count is 0 or ≤600 |
| `RotationHelper.lua` | Shows effective weapon speed and suggested rotation (two stacked text lines); rotation thresholds: >=1.83s→5:6:1:1, [1.22,1.83)→1:1, (0.83,1.22)→2:3, ≤0.83→1:2; updates on haste buff changes and weapon swaps |

**Keeping CLAUDE.md in sync:** Any change that adds a new widget, removes a widget, renames a module, alters its responsibilities, or changes its persisted settings MUST be accompanied by an update to this file. Before finishing any such change, cross-reference the file table, the SavedVariables list, and any module-specific structure notes against the code, and update whatever is now stale. Treat CLAUDE.md as a first-class deliverable of the change — a code change that leaves CLAUDE.md out of date is incomplete.

**Keeping README.md in sync:** Any change that affects user-facing behavior — adding/removing/renaming a widget, changing tracked items or buffs, altering visual effects, modifying thresholds or defaults, changing detection algorithms, or updating slash commands — MUST be accompanied by a corresponding update to `README.md`. Cross-check the widget's one-liner description and bullet-point notes against the code and update whatever is now stale. Treat `README.md` as a first-class deliverable alongside `CLAUDE.md`.

**Adding a new feature module:**
1. Create a new `.lua` file and add it to `ExsarAddon.toc` (after `ExsarUI.lua` and `Core.lua`)
2. Call `ExsarAddon.RegisterModule({ name = "...", BuildConfig = function(parent, y) ... return y end })`
3. Call `ExsarAddon.AddSlashCommand(cmd, fn)` for any slash sub-commands
4. Store settings under `ExsarAddonDB.<moduleName>` via `ExsarUI.MakeDB("moduleName")`
5. Add a row to the file table above and a `ExsarAddonDB.<moduleName>` entry to the SavedVariables list below

**Code reuse principle:** Always prefer using shared helpers from `ExsarLogic.lua` and `ExsarUI.lua` over writing bespoke code. When building a new widget, check the shared libraries first — most common patterns are already available. If you write new logic that could be reused by other modules, extract it into the appropriate shared library: pure logic goes in `ExsarLogic.lua` (testable without WoW API), UI construction goes in `ExsarUI.lua`. Never duplicate code across module files. Refer to UI effects by their standard names (see below) and always use the shared implementation.

**Testability principle:** Design new code to be unit-testable wherever possible. Extract logic into pure functions in `ExsarLogic.lua` so it can be tested with `busted` without WoW API mocks. When writing ExsarUI helpers, accept dependencies as parameters (tables with callable fields) rather than hardcoding WoW API calls, so they can be tested with lightweight stubs. Every new function added to `ExsarLogic.lua` should have corresponding tests in `tests/test_logic.lua`. New ExsarUI helpers should have contract tests in `tests/test_makedb.lua` (or a new test file) using stub tables. Run `busted` and `luacheck .` before considering any change complete.

**Standard UI effects** (defined in `ExsarUI.lua` and `ExsarLogic.lua`):

| Effect | Description | API |
|---|---|---|
| **Active Glow** | Solid colored rectangle extending beyond an icon edge, used to indicate active/ready state. Gold by default; also used as a 1px border ring (size=1) or red warning glow. | `ExsarUI.CreateGlow(frame, r, g, b, a, size, layer)` |
| **Marching Ants** | Animated gold dashed border rotating around an icon perimeter. A bright trailing tail fades behind the head. Standard params: 16 dashes, speed 1.5, tail length 5. | `ExsarUI.BuildDashes(iconFrame, iconSize, dashCount, borderW)` + `ExsarUI.AnimateDashes(slots, now, speed, dashCount, tailLen)` (or `ExsarLogic.MarchingAntHead` / `MarchingAntAlpha` for custom per-dash logic) |
| **Cooldown Sweep** | WoW's built-in circular pie-chart timer overlay. Normal mode fills as cooldown elapses; reverse mode empties as a buff expires. | `ExsarUI.CreateSweep(frame, { reverse = bool })` |
| **Red X** | Two diagonal red lines forming an X across an icon, indicating an inactive or missing state. | `ExsarUI.CreateRedX(frame, inset, thickness)` |
| **Up Arrows** | Two parallel arrows pointing up, each built from CreateLine segments (shaft + two arrowhead lines). Yellow by default; a "step in / reposition" status cue. | `ExsarUI.CreateUpArrows(frame, opts)` |
| **Pulse** | Sine-wave alpha oscillation (breathing effect). Used for alert/ready indicators. Params: frequency (Hz), min/max alpha. | `ExsarLogic.PulseAlpha(time, frequency, minAlpha, maxAlpha)` |
| **Dimmed** | Desaturated + reduced alpha for unavailable/out-of-stock items. Standard: `SetDesaturated(true)` + `SetAlpha(0.35)`. In-combat dimming: `SetAlpha(0.5)`, no desaturation. | Inline pattern (icon:SetDesaturated / icon:SetAlpha) |

When adding a new widget that needs a highlight, border, alert, or status indicator, use one of these standard effects rather than creating a bespoke visual.

**Sound effects pattern:**
Several modules play `PlaySound(soundKitID, "Master")` on state transitions (e.g. aggro gained, low HP threshold crossed, melee range entered/left). Use `PlaySoundFile(fileDataID, "Master")` instead when the sound is identified by a FileDataID rather than a SoundKit ID (see the API note below). Standard pattern:
- Track the previous state to detect edges (e.g. `wasActive` → `isActive`)
- Use a cooldown timer (`GetTime() - lastSoundTime >= COOLDOWN`) to prevent spam
- Gate behind a per-module DB flag (e.g. `db.lowHpSound ~= false`) with a config checkbox
- Defaults to enabled (`~= false` check, so `nil` counts as enabled)

**Ranked item fallback** (`ConsumableBuffWidget`):
Items with a `ranks` field (array of `{ name, id, buffId }` ordered highest-first) automatically show the highest rank with bag stock, falling back to the highest rank (greyed out) when none are available. Uses `ExsarLogic.SelectBestRank(ranks, getCount)` for the selection logic. Buff detection checks all rank buff IDs. Secure button `item` attribute is updated out of combat when the active rank changes.

**Weapon enchant tracking** (`ConsumableBuffWidget`):
Items with `weaponEnchant = true` (Adamantite Sharpening Stone, Adamantite Weightstone) are tracked via `GetWeaponEnchantInfo()` instead of the buff list. Both weapon hands are read; `ExsarLogic.MinWeaponEnchantRemaining(enchantId, ...)` returns the soonest-to-expire hand carrying the matching `enchantId`, so a stone applied to a dual-wield pair shows the timer that will run out first. `buffDuration` is hardcoded (3600s) for the sweep animation since the API reports only remaining time, not total duration. When the soonest-expiring hand switches, the >2s sweep-start guard catches the jump.

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
- Crossed-swords icon with circular mask background; gold/grey sword color modes and warm/grey background color modes (`SetBackgroundMode`)
- Range check via `IsSpellInRange("Wing Clip", "target")` polled at 0.1s
- Swing timer from combat log `SWING_DAMAGE`/`SWING_MISSED` + Raptor Strike spell IDs
- Four visual states: ready (full alpha + gold swords + glow ring + blade glow), in-range on-cooldown (half alpha + gold swords + muted glow + sweep), out-of-range on-cooldown (grey swords + half alpha + sweep + red X), out-of-range idle (green up-arrows on grey background, no swords — the always-on in-combat cue, `outOfRangeIdle`)
- Visibility (`shouldShow`): shown whenever in combat, or while the swing lingers on cooldown out of combat, or when unlocked; hidden otherwise
- `SetSwordsVisible` toggles the sword lines (hidden in the out-of-range idle state); `SetRedXVisible` / `SetArrowsVisible` toggle the two mutually-exclusive status overlays (red X = out-of-range on-cooldown, green up-arrows = out-of-range idle), both built on `overlayFrame`
- Pulsating gold glow ring (3.0 Hz) behind the icon in ready state only
- Optional enter/leave range sound effects: enter = FileDataID 567947 (BullWhipHit1) via `PlaySoundFile`; leave = SoundKit ID 1024 (ChickenDeath) via `PlaySound`

**`RaidTargetWidget.lua` structure:**
- Scan phase (every 0.3s via `CreatePoller`): iterate every queryable unit token (`target`, `focus`, `party/raid/partypet/boss` members and their `target` variants, nameplates). Record `{unit, guid, name, index}` deduplicated by GUID, one entry per raid icon. No "stability" distinction — GUID is the ground truth.
- Entry data stored on each secure button: `targetGuid`, `targetName`, `raidIndex`
- Click resolution (`PreClick`, in order):
  1. `FindTokenByGUID(guid)` — scan tokens and return the first whose `UnitGUID` currently equals our stored GUID → secure macrotext `/target [@<token>]`. Safe to use nameplate/`partyNtarget` tokens because they are re-verified at click time. **Must use the macro-bracket form, not `type=target, unit=<token>`** — the latter silently no-ops on TBC Classic Anniversary for many derived tokens (`pettarget`, `raidNtarget`, nameplate tokens) even when `UnitGUID(token)` clearly matches the intended mob. Verified empirically: a raid session produced 20 consecutive Tier 1 `type=target` clicks where the target never changed despite `matched ≥ 5` in the scan stats, and manual `/target [@pettarget]` in chat reliably targeted the same mob the widget button couldn't.
  2. `FindAssistMember(guid, rIdx)` — find a group member whose `memberNtarget` GUID matches (or icon matches as fallback) → secure macrotext `/assist [@memberN]`. The `[@unit]` conditional form is more reliable than bare `/assist memberN`.
  3. `/targetexact Name` — last resort; picks the closest mob with that name.
- Failure logging (`PostClick` → `C_Timer.After(0.25, CheckClickOutcome)`): snapshots context at click time and compares the player's target before/after. On mismatch, logs a multi-line `CLICK MISSED` entry to chat AND appends it to a capped ring buffer in SavedVariables (`rDB().clickMissLog`, cap = 20) so failures survive `/reload` and are retrievable after the fight. Each entry captures: timestamp, combat state, group kind/size, nameplate count, latency, intended mob (guid/name/icon/scan-discovery token), resolver path (tier + token/assist/macrotext), Tier 1 scan stats (checked/existed/hadGuid/matched), Tier 2 scan stats (size/withTarget/guidMatch/iconMatch), before/after target, and a snapshot of every currently marked mob. Default ON; toggle with `/exsar rtdebug`. `/exsar rtdump` opens the log in a modal copy-paste window (via `ExsarUI.ShowCopyableText`) — chat is unusable mid-fight, and the window is Ctrl+A / Ctrl+C friendly. `/exsar rtclear` wipes the buffer. `FormatClickMiss(dbg, prefix)` is shared between the live chat printer and the dump renderer.
- The `FindTokenByGUID` / `FindAssistMember` helpers always do a full pass (no short-circuit) and return `(match, stats)` so that failure diagnostics always reflect the complete scan, not a partial one.
- `entries` is forward-declared at the top of the file so `SnapshotAllMarks` (defined in the diagnostics section) can close over it before the entry pool is actually populated.

**`PetHappinessTracker.lua` structure:**
- Tier reconciliation delegates to `ExsarLogic.ReconcileHappinessTier`, which preserves the estimate when it is already inside the API-reported tier's range and only snaps to the crossed boundary when outside. This prevents feed-induced tier-ups from clobbering the exact `+amount` arithmetic (previous bug: pet at 695, feed +8 → estimate 703 → API reports tier 3 → code overwrote estimate to `TIER_MIN[3]=700`, producing a stuck `0.0s` display).
- Passive decay delegates to `ExsarLogic.ApplyHappinessDecay`, which clamps the estimate at `TIER_MIN[S.tier]`. Since the WoW API is authoritative on tier, the real value cannot be below that floor while the API still reports the current tier. Without the clamp, estimate drifted past the floor and the display collapsed to `0.0s` until `UNIT_HAPPINESS` re-anchored it.
- `S.guessing` is set when `SeedEstimate` cold-seeds with no saved data (the tier midpoint is used only as an internal decay fallback). The display renders a faint `?` instead of a fake timer until a trusted anchor is observed. `guessing` clears when `ReconcileHappinessTier` sets `anchored = true` (observed tier crossing) or a feed-at-max is detected. Persisted as `savedGuessing` so the state survives `/reload`.
- Debug ring buffer (`hDB().debugLog`, cap = 30) captures state transitions so the user can run `/exsar phdump` after observing a surprising display. Event types: `seed` (cold-start / restored-from-saved / saved-tier-mismatch), `tier` (tier flip or same-tier snap from `CorrectToTier`), `feed` (every Feed Pet bite detected via `SPELL_PERIODIC_ENERGIZE`), `clamp` (decay-floor pin — logged only on the transition into clamped state to avoid flooding while pinned), `penalty` (dismiss / death). Default ON; toggle with `/exsar phdebug`. `/exsar phdump` renders the buffer into a modal copy-paste window via `ExsarUI.ShowCopyableText`. `/exsar phclear` wipes the buffer. `FormatPHEntry(entry)` is shared between the live chat printer (`LogPH`) and the dump renderer.
- `S.wasDecayClamped` tracks whether the previous decay tick hit the floor, so `LogPH` for `clamp` events fires once per clamp run, not every second while pinned.

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
- `PlaySound(soundKitID [, channel])` — plays a built-in sound; use `"Master"` channel for alerts that must be heard regardless of SFX volume. Only accepts **SoundKit IDs** (small numbers, e.g. 154, 1024) — passing a FileDataID silently does nothing.
- `PlaySoundFile(fileDataID or path [, channel])` — plays a sound by **FileDataID** (the large 6-digit IDs, e.g. 567947) or file path; use this, not `PlaySound`, when the ID came from a sound-file database
- `IsInRaid()` / `IsInGroup()` — group context detection; solo = not `IsInGroup()`
- `UnitIsUnit(unit1, unit2)` — true if both unit tokens refer to the same entity
- `GetWeaponEnchantInfo()` — returns `hasMainEnchant, mainExpMs, mainCharges, mainEnchantId, hasOffEnchant, ...`; `mainExpMs` is milliseconds remaining; returns only remaining time, NOT total duration — total duration must be hardcoded if needed (e.g. for sweep animation). Returns the off-hand equivalents (`hasOffEnchant, offExpMs, offCharges, offEnchantId`) as returns 5–8. Use the enchant IDs to distinguish between different temporary enchants (e.g. Adamantite Sharpening Stone = 2713, Adamantite Weightstone = 2955, Windfury Weapon = 2636)

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
- `ExsarAddonDB.raidTargets` — position (x, y), scale, locked, debugClicks, clickMissLog
- `ExsarAddonDB.petAggressiveAlert` — position (x, y), scale, locked, disabled
- `ExsarAddonDB.petHappiness` — position (x, y), scale, locked, savedEstimate, savedTier, savedAnchored, savedGuessing, happinessSound, debug, debugLog
- `ExsarAddonDB.aggroAlert` — position (x, y), scale, locked, disabled, enableSolo, enableParty, enableRaid
- `ExsarAddonDB.ammoTracker` — position (x, y), scale, locked
- `ExsarAddonDB.rotationHelper` — position (x, y), scale, locked
