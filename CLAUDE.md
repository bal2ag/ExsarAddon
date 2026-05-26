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
| `Bindings.xml` | Declares the named key bindings for the Usable Items slots (`EXSAR_USE_ITEM1..7`, "ExsarAddon" category) and the Pet Management slots (`EXSAR_PET_ACTION1..6`, "ExsarAddon Pet" category, kept equal to the action count) so they appear in Blizzard's Key Bindings UI. No action body — `ExsarUI.SetupKeybindBridge` reads the assigned key and bridges it to the secure button (see UsableItemsWidget / PetManagementWidget notes). **Must NOT be listed in `ExsarAddon.toc`:** a file named exactly `Bindings.xml` is auto-loaded by the client's dedicated bindings parser by filename; adding it to the `.toc` makes the generic UI XML loader also parse it and fail with `Unrecognized XML: Binding` |
| `ExsarLogic.lua` | Pure Lua logic helpers (no WoW API dependency); testable outside the client. Timer formatting, health colors, cooldown state, grid math, anchor offset calc, binding-key abbreviation (`AbbreviateBindingKey`), etc. |
| `ExsarUI.lua` | Shared WoW UI construction helpers. `MakeDB`, `SetupMovableFrame`, `SetupTopleftFrame`, `RestorePosition`, `CreateIcon`, `CreateSweep`, `CreateAuraIcon`, `CreateGlow`, `BuildDashes`, `AnimateDashes`, `ShowCopyableText` (modal copy-paste window), `SetupKeybindBridge` (named-binding → secure-button bridge), `SecureSetAttribute` (combat-deferred `SetAttribute`: writes immediately out of combat, queues per frame+key and flushes on `PLAYER_REGEN_ENABLED` in combat), config panel helpers (`AddScaleSlider`, `AddLockCheckbox`, `AddResetButton`), `POWER_COLORS` |
| `Core.lua` | `ExsarAddon` namespace, module registration API, shared config widget helpers, config panel, slash command dispatch, DB init |
| `CooldownTracker.lua` | Cooldown tracker feature module |
| `RangedSwingTimer.lua` | Ranged auto shot cycle tracker |
| `CastBar.lua` | Cast bar for hunter shots (Auto Shot aim window, Aimed Shot, Steady Shot, Multi-Shot) |
| `KillCommandAlert.lua` | Pulsing aura indicator when Kill Command is off cooldown and pet is active |
| `ActiveEffectsTracker.lua` | Icons with marching-ants border and countdown for active buffs (Quick Shots, Haste Potion, Bloodlust, Heroism, Rapid Fire, The Beast Within, Drums of Battle) plus trinket on-use buffs |
| `UsableItemsWidget.lua` | Mini action bar showing consumables in bags (Super Healing Potion 22829, Super Mana Potion 22832, Haste Potion 22838, Drums of Battle 29529); click to use; Drums cooldown driven by Tinnitus debuff. Each slot is keybindable via Blizzard's Key Bindings UI (see `Bindings.xml` and the keybind structure note); the bound key shows top-right of the icon |
| `TargetDebuffTracker.lua` | Single-column vertical widget showing tracked debuffs (Hunter's Mark, Serpent Sting) currently active on the player's target; marching-ants border, reverse sweep, countdown timer |
| `RaidDebuffTracker.lua` | "Missing raid debuffs" caller — inverse of `TargetDebuffTracker`. Scans ALL debuffs on the target (raid debuffs come from other players, so no `"PLAYER"` filter; matched by name to catch every rank/source) and shows a vertical list — a persistent "Debuffs missing:" title plus one `[icon] colored-name` row per configured critical hunter-damage debuff that is ABSENT, so the user can call it out on Discord. Visible (title shown) only when active: in combat + in a raid + with a target, or whenever unlocked; the row list may be empty when nothing is missing. Each tracked debuff is independently toggleable in config (disable the ones the raid can't provide); whole widget also toggleable. Settings under `ExsarAddonDB.raidDebuffs` |
| `MendPetTracker.lua` | Mend Pet HoT tracker |
| `FoodAndDrinkWidget.lua` | Food/drink icons, dims in combat |
| `ConsumableBuffWidget.lua` | Always-visible consumable buff icons with bag counts, marching-ants + reverse sweep when buff active; supports ranked item fallback (e.g. Scroll of Agility V→I) and weapon enchant tracking |
| `MountWidget.lua` | Mount-related widget |
| `TargetInfoWidget.lua` | Target portrait/health/auras, hides when no target |
| `PlayerInfoWidget.lua` | Player portrait/health/auras, always visible (toggleable); low-HP burst warning with optional sound alert |
| `PetInfoWidget.lua` | Pet portrait/health/auras, shows only when pet exists; low-HP burst warning and damage border with optional sound alerts |
| `AspectTracker.lua` | Aspect of the Pack warning — pulses red glow + red marching-ants when Pack is active in combat |
| `MeleeRangeIndicator.lua` | Crossed-swords icon showing melee range status; cooldown sweep for swing timer; pulsating gold glow ring when swing is ready in range; always-on green-up-arrows-on-grey cue while in combat and out of range; optional range-change sound effects |
| `GlobalCooldownTracker.lua` | Global cooldown tracker |
| `RaidTargetWidget.lua` | Compact info for all units marked with raid target icons (click an icon row to target it) plus a tank-assist row (click a tank to assist them). Targeting uses static secure `type=target`+`unit` bindings set out of combat with live-resolving tokens (`raidNtarget`); see structure note. Detects mid-combat re-marks and greys stale icon buttons |
| `PetAggressiveAlert.lua` | Pulsing red skull + text when pet is on aggressive mode |
| `PetHappinessTracker.lua` | Granular happiness gauge estimating exact happiness points (0–1050); reverse sweep + timer showing time until tier drop; optional sound alert on happiness drop |
| `AggroAlert.lua` | Pulsating red text alert when enemy mobs are targeting the player; scans nameplates + party/raid target-of-target; configurable for solo/party/raid contexts; plays raid warning sound on aggro gain |
| `AmmoTracker.lua` | Equipped ammunition icon with bag-count overlay; red X when no ammo equipped; pulses a red low-ammo warning glow when count is 0 or ≤600 |
| `RotationHelper.lua` | Shows effective weapon speed and suggested rotation (two stacked text lines); rotation thresholds: >=1.83s→5:6:1:1, [1.22,1.83)→1:1, (0.83,1.22)→2:3, ≤0.83→1:2; updates on haste buff changes and weapon swaps |
| `PetManagementWidget.lua` | Keybindable mini action bar of pet-management actions. Each slot is a secure `type="macro"` button driven by macrotext; a slot can carry a conditional smart-macro (e.g. Call/Revive/Dismiss in one button). Macro bodies are **fully addon-controlled** — they live in the `PET_ACTIONS` table and there is no user override (no config-panel macro editing, no persisted macro DB). Each slot is keybindable via Blizzard's Key Bindings UI (see `Bindings.xml`, `EXSAR_PET_ACTION1..6`, "ExsarAddon Pet" category); the bound key shows top-right of the icon |
| `RangeToTargetWidget.lua` | Estimated distance bracket to the current target (e.g. "5-8 yd") plus a zone label (MELEE orange ≤5 / WEAVE green 5-8 / IN RANGE blue 8-35 / FAR red 35+). Probes a ladder of harm range checks (Wing Clip spell at 5yd + fixed-range items) and brackets the distance via `ExsarLogic.ComputeRangeBracket`; zone via `ExsarLogic.RangeZone`; degrades gracefully when checkers return nil |

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
| **Red X** | Two diagonal red lines forming an X across an icon, indicating an inactive, missing, or stale state (e.g. `AmmoTracker` no-ammo, `RaidTargetWidget` mid-combat re-marked icon). Returns the two `CreateLine`s as two return values, not a table. | `ExsarUI.CreateRedX(frame, inset, thickness)` |
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
- Four visual states: ready (full alpha + gold swords + glow ring + blade glow), in-range on-cooldown (half alpha + gold swords + muted glow + sweep), out-of-range on-cooldown (green up-arrows on grey background, no swords, full alpha + sweep + countdown timer, `outOfRangeOnCd`), out-of-range idle (green up-arrows on grey background, no swords, no sweep — the always-on in-combat cue, `outOfRangeIdle`). The two out-of-range states look identical except the cooldown sweep distinguishes the on-cooldown case.
- Visibility (`shouldShow`): shown whenever in combat, or while the swing lingers on cooldown out of combat, or when unlocked; hidden otherwise
- `SetSwordsVisible` toggles the sword lines (hidden in both out-of-range states); `SetArrowsVisible` toggles the green up-arrows status overlay (shown in both out-of-range states), built on `overlayFrame`
- Pulsating gold glow ring (3.0 Hz) behind the icon in ready state only
- Optional enter/leave range sound effects: enter = FileDataID 567947 (BullWhipHit1) via `PlaySoundFile`; leave = SoundKit ID 1024 (ChickenDeath) via `PlaySound`

**`RangeToTargetWidget.lua` structure (and the range-bracketing approach for future range widgets):**
- **Core fact:** WoW exposes no exact distance to a unit (anti-radar-hack). Distance can only be *bracketed* by probing a set of harm range checks with known thresholds — the technique LibRangeCheck / RangeDisplay use. See the `IsItemInRange` / `IsSpellInRange` entries under "Key WoW API Used" for the per-call rules (combat permissions, return shapes, the min-range pitfall).
- `CHECKERS` — an ascending ladder of `{ range, spell= | item= }`. `spell` entries (Wing Clip, 5yd) use `IsSpellInRange`; `item` entries use `IsItemInRange` with item IDs the player need not own. **Only no-minimum harm checks are valid:** a spell/item with a minimum range (Auto Shot's dead zone) returns out-of-range when *too close* as well as too far, which corrupts the lower bound — that's why Wing Clip (pure melee) is the only spell checker. Item IDs come from the LibRangeCheck harm-item tables; IDs not present in the TBC client return nil and are skipped.
- Polled at 0.1s (range has no event) + `PLAYER_TARGET_CHANGED`. Each poll normalizes every check to `true`/`false`/`nil` (1/0/nil for spells, bool/nil for items) and feeds the parallel `results` table to `ExsarLogic.ComputeRangeBracket(checkers, results)`.
- `ExsarLogic.ComputeRangeBracket` → `minR, maxR`: `maxR` = smallest in-range threshold (upper bound), `minR` = largest out-of-range threshold (lower bound). nil results are skipped, so invalid/restricted checks merely widen the bracket (graceful degradation — worst case collapses to Wing Clip's binary ≤5 / >5). A contradictory lower bound (non-monotonic jitter where a near check is in-range but a farther one is out) is dropped in favor of the more-trustworthy upper bound.
- `ExsarLogic.FormatRangeBracket(min, max)` → display string: `"5-8 yd"`, `"0-5 yd"` (within nearest checker / in melee), `"35+ yd"` (beyond furthest checker), `"?"` (nothing usable). `ExsarLogic.RangeZone(min, max, meleeMax=5, weaveMax=8, rangedMax=35)` → `"melee"`/`"weave"`/`"inrange"`/`"far"`/`"?"`, driving the colored zone label (orange/green/blue/red).
- Visibility: shown whenever the player has an attackable target (alive + `UnitCanAttack`), **not** combat-gated (unlike MeleeRangeIndicator), so it can be used to set up pull distance; also shown while unlocked.
- **Reuse for future range widgets:** the pure logic (`ComputeRangeBracket`, `FormatRangeBracket`, `RangeZone` in `ExsarLogic.lua`) is fully unit-tested — build new range widgets on it directly. The probe-and-normalize loop and the `CHECKERS` ladder are currently widget-local; when a second range-based widget is added, extract that step into a shared helper (e.g. `ExsarUI.GetRangeBracket(unit, checkers)`) rather than duplicating the loop, per the code-reuse principle.

**`RaidTargetWidget.lua` structure:**
- **Targeting model — static secure binding + live token (THE key fix; do not regress to click-time resolution).** Every clickable button is a `SecureUnitButtonTemplate` with a fixed `type1="target"` and a `unit` attribute that is written **ahead of time, out of combat** (via `ExsarUI.SecureSetAttribute`). The secure engine resolves that token (e.g. `"raid3target"`) **live on every click**, so a static binding tracks that unit's *current target* with no further writes. This is why the old approach failed: it computed the action inside `PreClick` and called `SetAttribute` at click time — blocked by combat lockdown, and mistimed even out of combat (logged as 20 misses with `before == after`, i.e. the click ran the stale default and the target never moved). **Never set a secure button's `type`/`unit`/`macrotext` from `PreClick` or in combat.** (The earlier CLAUDE note that `type=target, unit=<derivedtoken>` "silently no-ops" was a misdiagnosis of that same click-time-write bug; set as a persistent attribute out of combat, `type=target` + `unit="raidNtarget"` works in combat. Pattern confirmed against the BananaBar3 addon, which ships this exact mechanism via its own deferred SecureActionQueue.)
- **Icon rows** (max 8, one per raid icon, vertical list). Scan phase (`ScanMarkedUnits`, every 0.3s via `CreatePoller`): iterate every queryable unit token (`target`, `focus`, `party/raid/partypet/boss` members and their `target` variants, nameplates), record `{unit, guid, name, index}` deduplicated by GUID, one per icon. Each entry's `unit` binding is chosen out of combat by `ResolveMemberTargetToken(guid)` (a `raidNtarget`/`partyNtarget` that currently points at the mob — combat-stable, live) → fallback `ResolveNameplateToken(guid)` (works out of combat, may go stale in combat). Re-bound only when the chosen token changes.
- **Tank-assist row** (combat-proof, re-mark-proof — covers what the icon row cannot). A pool of up to `MAX_TANKS` (12) secure buttons, laid out `TANKS_PER_ROW` (3) per row above the icon list. `GatherRoster()` builds the group (raid via `GetRaidRosterInfo`, party via `party1..4`); `ExsarLogic.ComputeTankList(roster, ManualTankSet())` (pure, unit-tested) selects the tanks (`role == "TANK"`): `GatherRoster`'s `isTank()` flags a member as a tank via `UnitGroupRolesAssigned(unit) == "TANK"` (primary), falling back to Main-Tank assignment (`GetRaidRosterInfo` role `"MAINTANK"` / `GetPartyAssignment("MAINTANK", unit)`); when nobody is role-flagged, falls back to a manual name set (`ExsarLogic.ParseNameSet` over `rDB().manualTanks`). Each tank button binds `unit="raidNtarget"` (the tank's roster index) → clicking assists that tank (targets whatever they are tanking, resolved live). The button shows the tank's *current target's* raid mark as its big icon + the class-colored tank name, so it reads as "this is the skull tank." Player is excluded (self-assist no-ops). Toggle via `rDB().showTanks` (default ON).
- **In-combat re-mark detection.** A binding can't be rewritten in combat, so if a mark moves to a different GUID mid-fight the icon button is frozen on the old mob. `boundBaseline` (icon→GUID) is snapshotted whenever bindings are written (out of combat only); during combat `ExsarLogic.DetectStaleIcons(boundBaseline, currentByIcon)` (pure, unit-tested) flags icons whose GUID changed/disappeared, and those entries are desaturated + shown with a **Red X** (`ExsarUI.CreateRedX`) so the user falls back to the tank row.
- **Combat-safety of layout.** Repositioning/showing/hiding secure buttons is also protected, so `Layout()` (positions, sizes, `frame:SetSize`/`ReAnchor`, `Show`/`Hide`) runs **only out of combat**; in combat the widget updates visuals (portrait/health/mark/name/glow/stale) and defers binding writes, but does not reflow. New marks created mid-combat therefore don't appear until combat ends — the tank row is the mid-combat path.
- **Diagnostics (kept, simplified).** `PreClick` (`SecurePreClick`) does **no** `SetAttribute`; it only snapshots intent (the entry's `targetGuid`, or the tank button's live `UnitGUID(boundUnit)`) + current target + the bound unit + stale flag. `PostClick` → `C_Timer.After(0.25, CheckClickOutcome)` compares before/after target; on mismatch it logs a `CLICK MISSED` entry to chat and to a capped ring buffer (`rDB().clickMissLog`, cap = 20, survives `/reload`). `FormatClickMiss(dbg, prefix)` is shared by the live printer and `/exsar rtdump` (modal copy-paste via `ExsarUI.ShowCopyableText`). Default ON; `/exsar rtdebug` toggles, `/exsar rtclear` wipes, `/exsar rtreset` resets position.
- `entries` and `tankButtons` are forward-declared at the top of the file so the diagnostics helpers (`SnapshotAllMarks`, the shared PreClick) can close over them before the pools are populated.

**`PetHappinessTracker.lua` structure:**
- Tier reconciliation delegates to `ExsarLogic.ReconcileHappinessTier`, which preserves the estimate when it is already inside the API-reported tier's range and only snaps to the crossed boundary when outside. This prevents feed-induced tier-ups from clobbering the exact `+amount` arithmetic (previous bug: pet at 695, feed +8 → estimate 703 → API reports tier 3 → code overwrote estimate to `TIER_MIN[3]=700`, producing a stuck `0.0s` display).
- Passive decay delegates to `ExsarLogic.ApplyHappinessDecay`, which clamps the estimate at `TIER_MIN[S.tier]`. Since the WoW API is authoritative on tier, the real value cannot be below that floor while the API still reports the current tier. Without the clamp, estimate drifted past the floor and the display collapsed to `0.0s` until `UNIT_HAPPINESS` re-anchored it.
- `S.guessing` is set when `SeedEstimate` cold-seeds with no saved data (the tier midpoint is used only as an internal decay fallback). The display renders a faint `?` instead of a fake timer until a trusted anchor is observed. `guessing` clears when `ReconcileHappinessTier` sets `anchored = true` (observed tier crossing) or a feed-at-max is detected. Persisted as `savedGuessing` so the state survives `/reload`.
- Debug ring buffer (`hDB().debugLog`, cap = 30) captures state transitions so the user can run `/exsar phdump` after observing a surprising display. Event types: `seed` (cold-start / restored-from-saved / saved-tier-mismatch), `tier` (tier flip or same-tier snap from `CorrectToTier`), `feed` (every Feed Pet bite detected via `SPELL_PERIODIC_ENERGIZE`), `clamp` (decay-floor pin — logged only on the transition into clamped state to avoid flooding while pinned), `penalty` (dismiss / death). Default ON; toggle with `/exsar phdebug`. `/exsar phdump` renders the buffer into a modal copy-paste window via `ExsarUI.ShowCopyableText`. `/exsar phclear` wipes the buffer. `FormatPHEntry(entry)` is shared between the live chat printer (`LogPH`) and the dump renderer.
- `S.wasDecayClamped` tracks whether the previous decay tick hit the floor, so `LogPH` for `clamp` events fires once per clamp run, not every second while pinned.

**`RaidDebuffTracker.lua` structure:**
- `TRACKED_DEBUFFS` — array of `{ key, name, iconSpell, auras = { name, ... } }`, a mix of **grouped categories** and **specific debuffs**. `key` is the stable id for the per-debuff enable map (reordering the table never scrambles saved toggles); `iconSpell` is used only to fetch the icon texture via `GetSpellInfo` (resolved on load / `SPELLS_CHANGED`); `auras` is the list of aura names that satisfy the entry — present if **any** alias is on the target. A grouped entry (e.g. "Armor Debuff") lists every aura that covers the category and is only flagged missing when *none* are up; a specific entry (e.g. "Hunter's Mark") just lists its own name (also catching all ranks).
- Scans the target with `UnitDebuff("target", i)` **without** the `"PLAYER"` filter (raid debuffs are cast by other players) and matches by **name** to catch all ranks/sources.
- `ExsarLogic.ComputeMissingDebuffs(tracked, isEnabled, present, requiredCasterFor)` (pure, unit-tested) → array of missing entries in input order; skips disabled debuffs, treats an entry as present if any alias aura is up. `present` maps aura name → `true` (present, caster unknown) or a caster GUID string. `ExsarLogic.RaidDebuffsShouldShow({ enabled, inCombat, inRaid, hasTarget, unlocked })` (pure, unit-tested) gates whether the widget is **active** (always active when unlocked for config preview; otherwise requires enabled + in combat + in raid + has target). When inactive the frame is hidden; when active `ApplyLayout` runs and the frame is always shown — so the persistent "Debuffs missing:" title is the user's cue that the widget is live, even when the row list is empty. **While unlocked the target scan is skipped (`present` left empty), so every enabled debuff lists as missing — a deterministic positioning/testing preview independent of the current target.**
- **Caster matching (talent-gated debuffs):** some debuffs only deliver their hunter-relevant bonus when the caster is **talented**, and that talent is unreadable from the aura (the aura name/spellId is identical talented or not). Two such debuffs: **Improved Faerie Fire** (druid talent → +hit) and **Judgement of the Crusader** (paladin talent *Improved Seal of the Crusader* → +crit to all attacks against the judged target). The fix: identify the specced player(s) and match the debuff's **caster**. Driven by the **`CASTER_MATCHED`** table, keyed by debuff `key`: `{ talent, class, guidKey, nameKey, label }`. Adding another talent-gated debuff is one row.
  - **Matching:** the scan resolves each debuff's caster token (7th return of `UnitDebuff`) to a GUID via `UnitGUID`; `RequiredCasterFor(key)` returns the **union** (manual pin ∪ auto-detected) of accepted caster GUIDs as a set, fed into `ComputeMissingDebuffs`. The aura satisfies the entry only if cast by an accepted GUID **or** the caster is unknown (lenient — avoids false alarms when the token is `nil`/out of range); cast by a *known different* player (e.g. a feral applying FF for armor) it's still flagged missing. When nobody is designated, any caster counts.
  - **Auto-detect (talent inspect):** gated by the `autoDetect` setting (`IsAutoDetectEnabled()`, default ON) — when off, both `RefreshInspectQueue` and `ProcessInspectQueue` early-out so no inspect ever fires. `RefreshInspectQueue` (on `PLAYER_ENTERING_WORLD`/`GROUP_ROSTER_UPDATE`) collects raid members of the `INSPECT_CLASSES` (union of `CASTER_MATCHED` classes) into `inspectWanted`; a 2s poller (`ProcessInspectQueue`) calls `NotifyInspect` on a reachable member and `INSPECT_READY` → `OnInspectReady` reads inspect talents (`GetTalentInfo(t, i, true)`) into a `{name, rank}` list, then for every `CASTER_MATCHED` key whose `class` matches the inspected unit uses `ExsarLogic.FindTalentRank` (pure, unit-tested) to check that key's talent rank > 0, caching the GUID in the in-memory `autoGuids[key]` / `autoNames` (not persisted — re-detected each session to handle respecs). Only needs to catch a player in inspect range **once**; the cached GUID then matches their debuff anywhere. **Verified working on Anniversary 2.5.5** (auto-detected a boomkin's Improved Faerie Fire).
    - **Spam-avoidance gating (critical):** `NotifyInspect` errors loudly ("unknown unit" / "out of range") when the unit is beyond inspect range, and that error path never fires `INSPECT_READY`, so a naive retry loop hammers the same far-away raider once per stale-timeout. `CanInspect` does **not** check range. `ProcessInspectQueue` therefore gates on **`CheckInteractDistance(unit, 1)`** (real ~28yd inspect range), skips while Blizzard's `InspectFrame` is shown (single inspect channel), enforces one inspect in flight + 3s stale-pending timeout, and applies a per-GUID **backoff** (`inspectBackoff[guid]`, `INSPECT_BACKOFF = 10s`) so an occasional error can't stream. Net effect: only ever inspect someone actually in range; far raiders are simply retried later when they move close (raid stacking/movement brings everyone within 28yd eventually). **Do not gate inspect on `CanInspect` alone — that was the original spam bug.**
  - **Manual pin (capture-from-target):** per-debuff config button stores `<guidKey>`/`<nameKey>` (persisted), as a guaranteed fallback/override; warns if the targeted player's class doesn't match.
- **Combat-log `SPELL_AURA_APPLIED` source tracking cannot replace inspect** — it identifies the caster but not whether they are *talented* (the whole point). Inspect is the only path to the talent.
- Vertical list: a fixed title FontString at top, then one row per missing debuff. Each row is a `[icon-holder] [name FontString]` frame; the icon comes from `iconSpell` (resolved via `GetSpellInfo`, retried on `SPELLS_CHANGED`), the name is colored from the entry's optional `color` field (default `MISSING_COLOR`, a soft red). `ApplyLayout` sizes the frame to the widest of the title / rows (`GetStringWidth`) and stacks rows top-down.
- Combat state tracked via `PLAYER_REGEN_DISABLED`/`PLAYER_REGEN_ENABLED` (seeded from `InCombatLockdown()` on `PLAYER_ENTERING_WORLD`); raid state via `IsInRaid()` refreshed on `GROUP_ROSTER_UPDATE`. Polled at 0.2s plus `UNIT_AURA` (target), `PLAYER_TARGET_CHANGED`.
- Config: enable-widget checkbox, scale, lock, one checkbox per tracked debuff (default ON, disable per raid composition), an **"Auto-detect talented casters (inspect)" checkbox** (default ON; persists to `ExsarAddonDB.raidDebuffs.autoDetect`, `IsAutoDetectEnabled()` = `~= false`), reset button. Per-debuff state persists to `ExsarAddonDB.raidDebuffs.debuffs[<key>]`. When auto-detect is off, `ProcessInspectQueue`/`RefreshInspectQueue` early-out (no inspects fire at all) — already-cached `autoGuids` are kept (still valid), only new detection stops; manual pin still works.
- **`TRACKED_DEBUFFS` (the tracked set):** "Armor Reduction" (grouped — Sunder Armor OR Expose Armor), "Curse of Recklessness" (specific; warlock armor curse that stacks on top), "Improved Faerie Fire" (Faerie Fire aura + caster matching, see above), "Judgement of Wisdom" (specific; paladin, British spelling in-game), "Judgement of the Crusader" (caster-matched — paladin *Improved Seal of the Crusader*, British spelling), "Hunter's Mark" (specific). To add another: append an entry (grouped via multiple `auras`, or caster-matched by also adding a `CASTER_MATCHED` row).

**`UsableItemsWidget.lua` keybinding structure:**
- Each of the 7 slots has a named binding `EXSAR_USE_ITEM<i>` declared in `Bindings.xml` and labeled via `BINDING_HEADER_EXSARADDON` / `BINDING_NAME_EXSAR_USE_ITEM<i>` globals set in the widget. **A `category="ExsarAddon"` attribute is required on the modern Anniversary client:** its Key Bindings panel groups by category, so a `header`-only binding registers (shows in `GetBinding`/`GetNumBindings`, is functionally bindable) but renders no section in the UI. Unlike `header` (which resolves through a `BINDING_HEADER_*` global), the `category` value is displayed **literally** — so it is the readable string itself ("ExsarAddon"), not a token. The user assigns keys in **Blizzard's Key Bindings UI** (chosen over an in-addon config so we inherit Blizzard's native conflict warning + unbind flow, and because Blizzard account bindings sync across computers while addon SavedVariables do not). **No `ExsarAddonDB` entry** — keys live in Blizzard's binding set.
- Labels for slots that swap in alternates are deliberately generic ("Mana Potion", "Health Potion", "Mana Rune", "Healthstone") so they stay accurate when the displayed item changes; bindings are **positional** (fire whatever item is in `ExsarAddonItemBtn<i>`).
- `ExsarUI.SetupKeybindBridge{ owner, bindingPrefix, buttonPrefix, count, onSlotKey, deps }` does the bridging: on its own watcher-frame events (`UPDATE_BINDINGS` / `PLAYER_ENTERING_WORLD` / `PLAYER_REGEN_ENABLED`) it reads `GetBindingKey("EXSAR_USE_ITEM<i>")` and installs `SetOverrideBindingClick(owner, true, key, "ExsarAddonItemBtn<i>")` so the key uses the item even in combat (override layer masks any normal binding for that key while active). The override calls are protected, so they're skipped under `InCombatLockdown()` and re-applied on `PLAYER_REGEN_ENABLED`; the `onSlotKey(i, key)` callback always runs (label updates aren't protected) so the on-icon hotkey text stays current mid-combat. `deps` injects the WoW funcs for stub testing.
- On-icon hotkey label: top-right FontString per slot (bottom-right is the stack count), text from `ExsarLogic.AbbreviateBindingKey(key)` (pure, unit-tested: `SHIFT-1`→`s1`, `CTRL-BUTTON4`→`cm4`, `MOUSEWHEELUP`→`mwu`, `NUMPAD3`→`n3`; nil/empty → no text).

**`PetManagementWidget.lua` structure:**
- A horizontal row of secure `SecureActionButtonTemplate` buttons (`ExsarAddonPetActionBtn<i>`) with `type="macro"`. Driven by macrotext rather than item/spell attributes, so one slot can hold a conditional smart-macro (e.g. `/cast [nopet] Call Pet; [@pet,dead] Revive Pet; [pet] Dismiss Pet`).
- **Macro source = addon-controlled, no override.** `PET_ACTIONS` is the action table (`{ key, name, icon|iconItem, macro, requires }`); `key` is a stable id for the action. The `macro` field is the macrotext, period — there is no user override and no config-panel macro editing. `ApplyMacros()` pushes each action's `macro` onto its button — `SetAttribute` is protected, so it is skipped under `InCombatLockdown()` and re-applied on `PLAYER_REGEN_ENABLED`.
- **Availability grey-out + dynamic icons.** The widget always shows; per-action `requires` tokens gate usability via `ExsarLogic.PetActionEnabled(requires, state)` (pure, unit-tested): `nil`/`"any"` → always, `"active"` → pet exists, `"alive"` → exists & alive, `"dead"` → exists & dead, `"missing"` → no pet, `"notdead"` → alive or no pet (greyed only when the pet is dead) (unknown tokens fail open). `UpdateAvailability()` builds the pet state from `UnitExists`/`UnitIsDead`, updates any `dynamicIcon` (see Icons below), and applies the standard **Dimmed** effect (`SetDesaturated(true)` + `SetAlpha(0.35)`) to actions whose requirement isn't met. The secure click is left enabled (the macro just no-ops), so the grey-out is non-protected and combat-safe. Driven by a 0.2s poller plus `UNIT_PET`.
- **Keybindings** reuse the same bridge as UsableItems: named bindings `EXSAR_PET_ACTION<i>` (declared in `Bindings.xml`, "ExsarAddon Pet" category) → `ExsarUI.SetupKeybindBridge` → `SetOverrideBindingClick` to the secure button. Bindings are **positional** (fire whatever action occupies the slot); labels resolve via `BINDING_NAME_EXSAR_PET_ACTION<i>` globals set in a loop (defined-action slots use the action name, any surplus slots a generic `Pet Action N`). `MAX_SLOTS` must match the number of `EXSAR_PET_ACTION` bindings declared in `Bindings.xml`; both are currently kept equal to the action count (6) for a clean menu — grow `PET_ACTIONS`, `MAX_SLOTS`, and `Bindings.xml` together when adding actions. The bridge `count` is `#PET_ACTIONS`. No `ExsarAddonDB` entry for keys — they live in Blizzard's binding set.
- **Icons** are a texture path (`icon`), resolved from an item (`iconItem`, item ID or name) via `GetItemInfo` with a `GET_ITEM_INFO_RECEIVED` retry (mirroring `UsableItemsWidget`), resolved from a spell (`iconSpell`, spell ID or name) via `GetSpellTexture` with a `SPELLS_CHANGED` retry, or **pet-state-dynamic** (`dynamicIcon`): a map of `ExsarLogic.PetStateKey` result (`"alive"`/`"dead"`/`"missing"`) to an icon spec (texture path, `{ spell = name }`, or `{ item = id|name }`), re-resolved by `ResolveIconSpec` on each pet-state poll so e.g. the all-in-one button shows the Mend/Revive/Call icon matching current state. `#showtooltip`'s auto-icon magic only applies to Blizzard action-bar buttons, not our custom secure button — hence the manual swap.
- **Bag count / charges.** An action with `countItem` shows that item's bag count bottom-right of the icon (same style as `UsableItemsWidget`); `countCharges = true` makes `GetItemCount(item, false, true)` sum charges/uses across stacks rather than count items (used by Steam Tonk to show net controller charges, like Drums of Battle). `UpdateCounts()` runs on the 0.2s poll (charge decrements don't reliably fire `BAG_UPDATE`) plus `BAG_UPDATE` and load events.
- **Cooldown sweep (item CD + GCD).** `UpdateCooldowns()` feeds each slot's sweep from two sources, taking the longer-remaining one: (1) an action's `cooldownItem` — TBC has no `GetItemCooldown`, so `GetSlotCooldown` resolves the item name to an ID once (via `GetItemInfoInstant`, cached on the slot) and reads the cooldown from whichever bag slot holds it via `C_Container.GetContainerItemCooldown`; classified by `ExsarLogic.CooldownState` so GCD-length item durations are ignored. (2) the **GCD**, for actions flagged `gcd = true` (their macro casts a GCD-triggering spell — Mend/Dismiss/Call Pet); probed with `GetSpellCooldown("Wing Clip")` (no CD of its own, so it returns only the GCD, same as `GlobalCooldownTracker`). Only a real item cooldown shows a countdown number; the brief GCD is sweep-only. Runs on the 0.2s poll plus `BAG_UPDATE_COOLDOWN`, `SPELL_UPDATE_COOLDOWN`, and load events.
- **`ExsarUI.AddMacroEditBox(parent, y, label, getter, setter)`** — reusable config-panel multi-line edit box; saves on focus loss / Escape and refreshes from the getter on show. Non-secure UI; the caller's setter pushes text to the secure button out of combat.

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
- `IsItemInRange(itemID, unit)` — returns `true`/`false` if the item's range to `unit` can be checked, else `nil`. Works with **any** item ID (the item need not be in your bags), but only if the item exists in the current client's DB — IDs from later expansions return `nil`. Querying an **enemy** unit in combat is permitted (Blizzard re-allowed this in Dec 2023 after a brief 2023 protection). Used by `RangeToTargetWidget` for fixed-range distance bracketing. Items with a min range as well as a max would corrupt a `≤range` bracket, so only no-minimum harm items are used.
- `IsSpellInRange(spellName, unit)` — returns `1`/`0`/`nil`. Works in combat. A spell with a **minimum** range (dead zone, e.g. Auto Shot) returns `0` when too close as well as too far, so such spells are NOT valid as simple `≤range` checkers — `RangeToTargetWidget` only uses Wing Clip (melee, no minimum) as a spell checker. WoW exposes no exact unit distance; bracketing multiple range checks (LibRangeCheck / RangeDisplay approach) is the only way to estimate it.
- `Bindings.xml` + `GetBindingKey(command)` / `SetOverrideBindingClick(owner, isPriority, key, buttonName)` / `ClearOverrideBindings(owner)` — keybinding bridge. A named binding declared in `Bindings.xml` appears in Blizzard's Key Bindings UI (native conflict warning, account-synced). `GetBindingKey("EXSAR_USE_ITEM1")` returns the assigned key(s); `SetOverrideBindingClick` then maps that key to a secure button click in a **higher-priority override layer** that masks (does not unbind) the normal binding while active — this is what lets the bound key use an item in combat. `SetOverrideBindingClick` / `ClearOverrideBindings` are **protected**: they cannot run during `InCombatLockdown()`, so defer and re-apply on `PLAYER_REGEN_ENABLED`. Used by `UsableItemsWidget` via `ExsarUI.SetupKeybindBridge`.
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
- `ExsarAddonDB.raidTargets` — position (x, y), scale, locked, showTanks (tank-assist row toggle; default ON, stores `false` only when disabled), manualTanks (free-text tank name list used when no Main Tanks are assigned), debugClicks, clickMissLog
- `ExsarAddonDB.petAggressiveAlert` — position (x, y), scale, locked, disabled
- `ExsarAddonDB.petHappiness` — position (x, y), scale, locked, savedEstimate, savedTier, savedAnchored, savedGuessing, happinessSound, debug, debugLog
- `ExsarAddonDB.aggroAlert` — position (x, y), scale, locked, disabled, enableSolo, enableParty, enableRaid
- `ExsarAddonDB.ammoTracker` — position (x, y), scale, locked
- `ExsarAddonDB.rotationHelper` — position (x, y), scale, locked
- `ExsarAddonDB.rangeToTarget` — position (x, y), scale, locked
- `ExsarAddonDB.petManagement` — position (x, y), scale, locked
- `ExsarAddonDB.raidDebuffs` — position (x, y), scale, locked, enabled, autoDetect (talent-inspect auto-detection toggle; default ON, stores `false` only when disabled), debuffs (per-debuff enable map keyed by debuff `key`; default ON, stores `false` only when disabled), ffDruidGuid, ffDruidName (designated Improved Faerie Fire druid), jocPaladinGuid, jocPaladinName (designated Improved Seal of the Crusader paladin) — both captured from target; the persisted guid/name keys come from the `CASTER_MATCHED` table
