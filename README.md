# ExsarAddon

A Hunter toolkit addon for World of Warcraft: TBC Classic Anniversary (Interface 20505). It provides a collection of lightweight, movable widgets that surface combat timers, cooldowns, alerts, and status information — everything a BM/survival hunter needs visible at a glance.

## Table of Contents

- [Installation](#installation)
- [Configuration](#configuration)
- [Widgets](#widgets)
  - [Cooldown Tracker](#cooldown-tracker)
  - [Ranged Swing Timer](#ranged-swing-timer)
  - [Cast Bar](#cast-bar)
  - [Kill Command Alert](#kill-command-alert)
  - [Active Effects Tracker](#active-effects-tracker)
  - [Usable Items](#usable-items)
  - [Target Debuff Tracker](#target-debuff-tracker)
  - [Mend Pet Tracker](#mend-pet-tracker)
  - [Food & Drink Widget](#food--drink-widget)
  - [Consumable Buff Widget](#consumable-buff-widget)
  - [Mount Widget](#mount-widget)
  - [Target Info](#target-info)
  - [Player Info](#player-info)
  - [Pet Info](#pet-info)
  - [Aspect Tracker](#aspect-tracker)
  - [Melee Range Indicator](#melee-range-indicator)
  - [Global Cooldown Tracker](#global-cooldown-tracker)
  - [Raid Target Widget](#raid-target-widget)
  - [Pet Aggressive Alert](#pet-aggressive-alert)
  - [Pet Happiness Tracker](#pet-happiness-tracker)
  - [Aggro Alert](#aggro-alert)
  - [Ammo Tracker](#ammo-tracker)
  - [Rotation Helper](#rotation-helper)

## Installation

1. Go to the [ExsarAddon GitHub page](https://github.com/bal2ag/ExsarAddon).
2. Click the green **Code** button, then click **Download ZIP**.
3. Unzip the downloaded file. This will create a folder called `ExsarAddon-main`.
4. Rename the folder from `ExsarAddon-main` to `ExsarAddon`.
5. Move the `ExsarAddon` folder into your WoW addons directory. The default location is:
   - **Windows:** `C:\Program Files (x86)\World of Warcraft\_classic_\Interface\AddOns\`
   - **Mac:** `/Applications/World of Warcraft/_classic_/Interface/AddOns/`
6. You should end up with a path like `.../Interface/AddOns/ExsarAddon/ExsarAddon.toc` — if you see `.../AddOns/ExsarAddon/ExsarAddon/`, you have one folder too many. Move the inner folder up and delete the empty outer one.
7. Launch WoW (or restart it if it was already running) and make sure **ExsarAddon** is checked on the character select addons list.

## Configuration

All widgets are movable and individually configurable.

- **Config panel:** Type `/exsar config` in chat, or open it from the game menu via **Interface > AddOns > ExsarAddon**. The panel has per-widget settings for scale, visibility, sound alerts, and other options.
- **Moving widgets:** Type `/exsar unlock` to unlock all widgets so you can drag them into position, then `/exsar lock` to lock them in place.
- **Reset positions:** Type `/exsar reset` to reset widget positions to their defaults.

Settings are saved per-character in `ExsarAddonDB` (WoW's SavedVariables system) and persist across sessions.

## Widgets

### Cooldown Tracker

![Supported](https://img.shields.io/badge/Supported-green)

Shows core abilities, trinkets, and cooldowns, and tracks cooldown time remaining.

- **Abilities tracked:** Multi-Shot, Arcane Shot, Raptor Strike, Rapid Fire, Bestial Wrath (if talented), Readiness (if talented)
- **Trinkets:** Automatically shows equipped trinkets that have an on-use effect; updates when gear changes
- **Click to use:** Clicking a spell icon casts it; clicking a trinket icon uses it
- **Cooldown appearance:** Icons go desaturated/dimmed with a circular sweep overlay and countdown text while on cooldown; a pulsing gold glow border appears when ready in combat

<!-- ![Cooldown Tracker](screenshots/cooldown-tracker.png) -->

### Ranged Swing Timer

![Supported](https://img.shields.io/badge/Supported-green)

Bar showing your Auto Shot cycle with a clip-window indicator so you know when it's safe to cast without delaying your next auto.

- **Bar behavior:** The bar starts full after each Auto Shot and drains toward the center over the weapon speed cycle. When it empties, your next Auto Shot is ready.
- **Red reticules:** A pair of vertical red bars mark the aim window — the point where your character must be standing still and not casting to let the ~0.5s Auto Shot wind-up fire. Starting a cast before this zone can still clip the auto shot if the cast extends into or past it.
- **Bar color:** Blue when safe to cast, red when inside the aim window, grey when the GCD is active.
- **Clipping:** If you begin a cast that will delay the next Auto Shot, the delay amount is shown in red between the reticules (e.g. `(0.34)`).

<!-- ![Ranged Swing Timer](screenshots/ranged-swing-timer.png) -->

### Cast Bar

![Supported](https://img.shields.io/badge/Supported-green)

Cast bar for Auto Shot aim window, Aimed Shot, Steady Shot, and Multi-Shot. Each shot type has a distinct color.

- **Shot colors:** Auto Shot (green), Aimed Shot (gold), Steady Shot (purple), Multi-Shot (orange)
- **Auto Shot:** Detected automatically from your swing timer — the bar appears during the ~0.5s aim window when you must stand still for the shot to fire
- **Multi-Shot:** Has a 0.5s base cast time (not instant), reduced by haste just like the Auto Shot wind-up
- **Haste:** All cast durations account for your current haste effects (Rapid Fire, Bloodlust, haste rating, etc.)
- **Failed casts:** A brief red flash is shown when a cast is interrupted or fails

<!-- ![Cast Bar](screenshots/cast-bar.png) -->

### Kill Command Alert

![Supported](https://img.shields.io/badge/Supported-green)

Pulsing wing-shaped alert when Kill Command is ready and your pet is active.

- **Effect:** Two red eagle-wing crescents (made of feather-shaped lines) appear flanking the player, pulsing in and out at ~0.8 Hz
- **Shown when:** Kill Command proc is active (pet scored a crit), the ability is not on its 5-second cooldown, your pet is alive, and you are in combat
- **Hidden when:** Kill Command is on cooldown, the proc is not active, your pet is dead or dismissed, or you are out of combat

<!-- ![Kill Command Alert](screenshots/kill-command-alert.png) -->

### Active Effects Tracker

![Supported](https://img.shields.io/badge/Supported-green)

Icons with animated borders and countdowns for relevant rotation buffs (Quick Shots, Haste Potion, Bloodlust, Rapid Fire, etc.) and trinket procs.

- **Buffs tracked:** Quick Shots (Improved Aspect of the Hawk proc), Haste Potion, Bloodlust, Heroism, Rapid Fire, The Beast Within, Drums of Battle
- **Trinkets:** Automatically detects on-use trinket buffs from your equipped trinkets
- **Active effect appearance:** Each active buff shows its icon with a gold marching-ants animated border, a reverse cooldown sweep that fills as the buff expires, and a countdown timer
- **Hidden when:** No tracked buffs are active (and widget is locked)

<!-- ![Active Effects Tracker](screenshots/active-effects-tracker.png) -->

### Usable Items

![Supported](https://img.shields.io/badge/Supported-green)

Clickable mini action bar for consumables in your bags (health/mana potions, haste potions, drums). Click to use directly.

- **Items tracked:** Dark Rune, Demonic Rune, Super Mana Potion, Super Healing Potion, Drums of Battle, Haste Potion, Heavy Netherweave Bandage, Master Healthstone
- **Bag count:** Each icon shows the number of that item in your bags. Drums of Battle shows remaining charges instead of item count. Items you don't have are greyed out and desaturated.
- **Alternates:** Some items automatically swap to a better option based on context. Mana and healing potions will use zone-specific alternatives in Tempest Keep instances (Bottled Nethergon Energy/Vapor), or Auchenai potions if you have them. The swap happens out of combat when you change zones or your bags update.
- **Healthstones:** Multiple Healthstone variants (from different warlocks) are layered into a single slot. The highest rank you have in your bags is shown; when it's used, the next highest rank takes its place.
- **Cooldowns:** Drums of Battle cooldown is driven by the Tinnitus debuff timer rather than the item cooldown; Heavy Netherweave Bandage uses the Recently Bandaged debuff. Other items show their normal item cooldown with a sweep and countdown.

<!-- ![Usable Items](screenshots/usable-items.png) -->

### Target Debuff Tracker

![Supported](https://img.shields.io/badge/Supported-green)

Shows your Hunter's Mark and Serpent Sting on the current target with countdowns.

- **Player-only:** Only shows debuffs you cast, not those from other hunters

<!-- ![Target Debuff Tracker](screenshots/target-debuff-tracker.png) -->

### Mend Pet Tracker

![Supported](https://img.shields.io/badge/Supported-green)

Tracks your Mend Pet HoT.

- **Effect:** Shows the Mend Pet icon with a pulsating green glow border (1 Hz) and a reverse cooldown sweep that fills as the HoT expires
- **Timer:** Countdown text in the center of the icon showing time remaining on the buff
- **Hidden when:** Mend Pet is not active on your pet (and widget is locked)

<!-- ![Mend Pet Tracker](screenshots/mend-pet-tracker.png) -->

### Food & Drink Widget

![Supported](https://img.shields.io/badge/Supported-green)

Food and drink icons that dim automatically in combat.

- **Items tracked:** Conjured Manna Biscuit, Purified Draenic Water, Clefthoof Ribs
- **Click to use:** Click an icon to eat or drink
- **Dimming:** Icons dim to half alpha in combat (since you can't eat/drink); items not in your bags are greyed out and desaturated

<!-- ![Food & Drink Widget](screenshots/food-and-drink.png) -->

### Consumable Buff Widget

![Supported](https://img.shields.io/badge/Supported-green)

Always-visible icons for consumable buffs (scrolls, elixirs, weapon enchants) with bag counts and active timers.

- **Items tracked:** Kibler's Bits (pet), Scroll of Strength (pet), Flask of Relentless Assault, Elixir of Major Agility, Elixir of Demonslaying, Elixir of Major Mageblood, Scroll of Agility, Adamantite Sharpening Stone, Grilled Mudfish, Spicy Hot Talbuk
- **Ranked items:** Scroll of Agility and Scroll of Strength support ranked fallback (V through I). The highest rank you have in your bags is shown; if none are available, the highest rank is shown greyed out. Any rank's buff counts as active.
- **Weapon enchants:** Adamantite Sharpening Stone is tracked via `GetWeaponEnchantInfo()` rather than as a buff, since temporary weapon enchants don't appear in the buff list. Duration is hardcoded (1 hour) since the API only provides time remaining, not total duration.
- **When active:** A gold glow border appears, a reverse cooldown sweep fills as the buff expires, and a countdown timer is shown
- **Click to use:** Click an icon to use the consumable

<!-- ![Consumable Buff Widget](screenshots/consumable-buff.png) -->

### Mount Widget

![Supported](https://img.shields.io/badge/Supported-green)

One-click to use mounts.

- **Mounts tracked:** Reins of the Swift Stormsaber (ground), Starshard Netherdrake (flying)
- **Active indicator:** A yellow glow highlights whichever mount is currently active

<!-- ![Mount Widget](screenshots/mount.png) -->

### Target Info

![Supported](https://img.shields.io/badge/Supported-green)

Target portrait with health bar and auras. Hides when you have no target.

- **Portrait:** 2D portrait texture from WoW's API. Portrait ring is color-coded: gold for elites/bosses, silver for rares, grey for normal mobs.
- **Health bar:** Shows health as a percentage. Bar color shifts from green (>50%) to yellow (>20%) to red (≤20%) as health drops.
- **Power bar:** Shows current/max mana, energy, or rage with color matching the power type.
- **Name color:** Red for hostile, green for friendly, yellow for neutral targets.
- **Level:** Color-coded by difficulty relative to your level. Shows classification suffix (Elite, Rare, Boss, etc.).
- **Auras:** Displays both buffs and debuffs currently on the target.

<!-- ![Target Info](screenshots/target-info.png) -->

### Player Info

![Supported](https://img.shields.io/badge/Supported-green)

Player portrait with health bar and auras. Includes an optional low-HP burst warning with sound alert.

- **Portrait:** 2D portrait texture from WoW's API.
- **Health bar:** Shows health as a percentage. Bar color shifts from green (>50%) to yellow (>20%) to red (≤20%) as health drops.
- **Power bar:** Shows current/max mana with color matching the power type.
- **Auras:** Displays both buffs and debuffs currently on the player.
- **Low-HP warning:** When health drops below a configurable threshold (default 30%), a pulsating red border appears around the frame. An optional sound alert plays on the transition (with a 5-second cooldown to prevent spam). Both the threshold and sound can be configured.
- **Damage border:** Flashes a red border when the player takes damage.
- **Toggleable:** Can be enabled/disabled entirely via the config panel.

<!-- ![Player Info](screenshots/player-info.png) -->

### Pet Info

![Supported](https://img.shields.io/badge/Supported-green)

Pet portrait with health bar and auras. Shows only when your pet is active. Includes low-HP and incoming-damage warnings with optional sound alerts.

- **Portrait:** 2D portrait texture from WoW's API.
- **Health bar:** Shows health as a percentage. Bar color shifts from green (>50%) to yellow (>20%) to red (≤20%) as health drops.
- **Power bar:** Shows current/max focus with color matching the power type.
- **Auras:** Displays both buffs and debuffs currently on the pet.
- **Low-HP warning:** When pet health drops below a configurable threshold (default 30%), a pulsating red border appears. An optional sound alert plays on the transition (with a 5-second cooldown). Both the threshold and sound can be configured.
- **Damage border:** Flashes a red border when the pet takes damage. An optional sound alert plays when damage is received (with a 5-second cooldown).
- **Toggleable:** Can be enabled/disabled entirely via the config panel.
- **Auto-hide:** Hidden when no pet is summoned.

<!-- ![Pet Info](screenshots/pet-info.png) -->

### Aspect Tracker

![Supported](https://img.shields.io/badge/Supported-green)

Shows which aspect is currently active. Pulses a red warning when Aspect of the Pack is active in combat — a reminder to switch before you get dazed.

- **Appearance:** Single icon showing the currently active aspect with a gold marching-ants animated border
- **No aspect:** When no aspect is active, the icon is blank with a red X overlay
- **Pack warning:** When Aspect of the Pack is active in combat, the marching-ants border turns red and a pulsating red glow surrounds the icon — a hard-to-miss reminder to switch before you get dazed
- **Aspects detected:** Hawk, Monkey, Pack, Cheetah, Viper, Beast, Wild

<!-- ![Aspect Tracker](screenshots/aspect-tracker.png) -->

### Melee Range Indicator

![Supported](https://img.shields.io/badge/Supported-green)

Crossed-swords icon showing melee range status. Displays a cooldown sweep for your melee swing timer and a pulsating gold glow when your swing is ready in range.

- **Intent:** Designed to support melee weaving — stepping into melee range between auto shots to land a Raptor Strike. Shows at a glance whether you're in melee range and whether your swing is ready.
- **Visual states:**
  - **Ready** (in range, swing available): Full-alpha gold swords with blade glow lines, fast-pulsating gold glow ring (3 Hz) — swing now!
  - **On cooldown** (in range, swing cooling down): Half-alpha gold swords with cooldown sweep and countdown timer, slow-pulsating muted glow ring — move away after swinging
  - **Out of range** (swing on cooldown): Half-alpha grey swords with red X overlay, cooldown sweep and countdown timer — swing is resetting, no glow
  - **Hidden:** Not in combat, no target, target is dead/friendly, or out of melee range with no swing cooldown active
- **Swing timer:** Tracked via combat log (SWING_DAMAGE/SWING_MISSED and Raptor Strike hits). Cooldown sweep and countdown show time until next swing.
- **Sound effects:** Optional sounds play when entering and leaving melee range (configurable in the config panel)

<!-- ![Melee Range Indicator](screenshots/melee-range.png) -->

### Global Cooldown Tracker

![Supported](https://img.shields.io/badge/Supported-green)

Sweep effect for the current GCD.

- **Appearance:** A circular sweep effect (no icon — just the sweep itself) with a pulsating blue glow ring behind it, and a countdown timer in the center
- **Triggered by:** Probes the GCD via Wing Clip's cooldown (which has no cooldown of its own, so it only ever returns the GCD). Fires on `SPELL_UPDATE_COOLDOWN` events.
- **Sweep color:** Grey during the GCD, transitions to blue when the remaining time enters the spell queue window — indicating you can queue your next ability
- **Hidden when:** GCD is not active (and widget is locked)

<!-- ![Global Cooldown Tracker](screenshots/gcd-tracker.png) -->

### Raid Target Widget

![Experimental](https://img.shields.io/badge/Experimental-yellow)

Compact info for all units marked with raid target icons. Click a row to target that unit.

- **Display:** Each marked unit gets a row showing its portrait, raid target icon, name (colored by reaction), and a health bar with percentage. Sorted by raid icon index (skull first, star last). Your current target is highlighted with a pulsating gold glow border.
- **Unit discovery:** Scans multiple sources to find marked units: your target and focus, party/raid members, party/raid member targets, visible nameplates, and boss frames. Units are deduplicated by GUID.
- **Click to target:** GUID-verified, three-tier targeting at click time:
  1. Scan every queryable unit token (nameplates, `raidNtarget`, `partyNtarget`, boss frames, target/focus/mouseover) and use the first one whose `UnitGUID` still matches the intended mob — secure `type=target`
  2. `/assist [@memberN]` for any group member whose target matches the intended GUID (or icon, if the client can't resolve their target's GUID locally)
  3. `/targetexact Name` as a last resort
- **Click-failure logging:** When a click fails to swap your target to the intended mob, a `CLICK MISSED` entry is printed to chat showing intended/resolver/before/after so the failure mode can be diagnosed without running macros mid-fight. Default ON; toggle with `/exsar rtdebug`.
- **Hidden when:** No marked units are found (and widget is locked)

<!-- ![Raid Target Widget](screenshots/raid-targets.png) -->

### Pet Aggressive Alert

![Supported](https://img.shields.io/badge/Supported-green)

Pulsing red skull when your pet is set to aggressive mode.

- **Appearance:** A red-tinted skull icon with "PET ON AGGRESSIVE!" text below it, on a semi-transparent dark red background. The entire frame pulses in and out at 1 Hz.
- **Detection:** Scans the pet action bar for the aggressive stance. Updates when the pet bar changes or when your pet is summoned/dismissed, with a 0.5-second safety poll to catch missed transitions.
- **Hidden when:** Pet is not on aggressive (and widget is locked), or the alert is disabled in config.

<!-- ![Pet Aggressive Alert](screenshots/pet-aggressive.png) -->

### Pet Happiness Tracker

![Experimental](https://img.shields.io/badge/Experimental-yellow)

Happiness gauge estimating exact happiness points (0-1050) with a timer showing how long until the next tier drop. Optional sound alert when happiness decreases.

- **Display:** Shows the WoW pet happiness face icon (happy/content/unhappy) with a reverse cooldown sweep that fills as happiness drains toward the next tier boundary. A countdown timer shows estimated time until the next tier drop. When the estimate is approximate (not anchored to a known boundary), the timer is prefixed with `~`.
- **Warning:** A pulsating red glow border appears when the pet is content or unhappy. An optional sound alert plays when happiness drops a tier (configurable).
- **Algorithm:** The WoW API only exposes the happiness tier (1/2/3), not exact points. The tracker estimates exact happiness (0–1050, 350 points per tier) by:
  - Seeding at the tier midpoint on first login, or restoring the saved estimate if the tier matches
  - Applying passive decay continuously (~8.33 points/minute)
  - Adding feed amounts detected from combat log events (`SPELL_PERIODIC_ENERGIZE` with happiness power type), using the actual per-bite value (8, 17, or 35 depending on food quality)
  - Subtracting fixed penalties for pet death (–350) and dismissal (–50)
  - Snapping to the exact tier boundary whenever the API tier changes, which "anchors" the estimate to a known value
- **Storage:** The current estimate, tier, and anchored state are persisted to SavedVariables on every update tick, so the estimate survives across sessions. If the tier changed while logged out, it anchors to the appropriate boundary on login.

<!-- ![Pet Happiness Tracker](screenshots/pet-happiness.png) -->

### Aggro Alert

![Supported](https://img.shields.io/badge/Supported-green)

Pulsating red text alert when enemy mobs are targeting you. Scans nameplates and group targets. Configurable for solo, party, and raid contexts. Plays a sound when you gain aggro.

- **Appearance:** One line of pulsating red text per mob (up to 5), reading "You have aggro on \<mob name\>!", with a red glow border around the frame. The entire frame pulses at 1.5 Hz.
- **Detection algorithm:** Scans multiple unit sources to find enemy mobs whose target is the player, deduplicated by GUID:
  1. Player's target and pet target
  2. Party/raid members' targets (and party pet targets)
  3. Boss frames
  4. Visible nameplates (tracked via `NAME_PLATE_UNIT_ADDED`/`REMOVED`)
  - Each candidate is checked with `UnitIsEnemy`, `not UnitIsDead`, and `UnitIsUnit(unit.."target", "player")`
- **Sound:** Plays the raid warning sound on the aggro-gain edge (not active → active), with a 3-second cooldown to prevent spam.
- **Context gating:** Independently configurable for solo, party, and raid via checkboxes in the config panel. All three are enabled by default.
- **Polling:** Rescans every 0.2 seconds, plus immediately on threat updates, nameplate changes, and group roster changes.

<!-- ![Aggro Alert](screenshots/aggro-alert.png) -->

### Ammo Tracker

![Supported](https://img.shields.io/badge/Supported-green)

Equipped ammo icon with bag count overlay. Shows a red warning glow when ammo is low or missing.

- **Detection:** Reads the equipped ammo slot (inventory slot 0) via `GetInventoryItemID` and `GetInventoryItemCount`. Updates on equipment changes, bag updates, and a 1-second safety poll.
- **Count:** Displays the total ammo count as an overlay on the bottom-right of the icon.
- **Low ammo (≤600):** A pulsating red glow border appears around the icon as a restock reminder.
- **No ammo equipped:** Icon shows a greyed-out question mark with a red X overlay and the pulsating red warning glow.

<!-- ![Ammo Tracker](screenshots/ammo-tracker.png) -->

### Rotation Helper

![Supported](https://img.shields.io/badge/Supported-green)

Shows your effective weapon speed and suggests the matching shot rotation based on current haste.

- **Display:** Two stacked text lines — effective weapon speed on top (e.g. "1.23s"), suggested rotation below in gold (e.g. "1:1"). Updates on haste buff changes, weapon swaps, and a 1-second poll.
- **Rotation thresholds:** Based on the [diziet559/rotationtools](https://github.com/diziet559/rotationtools) TBC hunter rotation simulator:
  - **≥1.83s** → `5:6:1:1` (French rotation: 5 autos, 6 steadies, 1 multi, 1 arcane)
  - **1.22s–1.82s** → `1:1` (one steady per auto)
  - **0.84s–1.21s** → `2:3` (2 autos per 3 steadies)
  - **≤0.83s** → `1:2` (1 auto per 2 steadies)
- **Effective speed:** Read from `UnitRangedDamage("player")`, which accounts for all haste sources (quiver, talents, buffs, haste rating).

<!-- ![Rotation Helper](screenshots/rotation-helper.png) -->
