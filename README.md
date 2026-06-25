# ExsarAddon

A (highly opinionated) Hunter toolkit addon for World of Warcraft: TBC Classic Anniversary (Interface 20505). It provides a collection of lightweight, movable widgets that surface combat timers, cooldowns, alerts, and status information — everything a BM/survival hunter needs visible at a glance.

This addon was built primarily with [Claude Code](https://code.claude.com/docs/en/overview).

<img width="1464" height="950" alt="Screenshot 2026-04-21 at 7 43 03 PM" src="https://github.com/user-attachments/assets/2e39a7d7-cc15-417c-9369-a71482e23853" />


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
  - [Raid Debuff Tracker](#raid-debuff-tracker)
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
  - [Range to Target](#range-to-target)
  - [Pet Management](#pet-management)
  - [Aspects](#aspects)
  - [Traps](#traps)
  - [Cooldowns](#cooldowns)
  - [Core Combat](#core-combat)
  - [Utilities](#utilities)

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

<img width="362" height="208" alt="Screenshot 2026-04-21 at 7 43 28 PM" src="https://github.com/user-attachments/assets/c68d1036-4736-49ca-8cd4-459078fe74a2" />


![Supported](https://img.shields.io/badge/Supported-green)


Bar showing your Auto Shot cycle with a clip-window indicator so you know when it's safe to cast without delaying your next auto.

- **Bar behavior:** The bar starts full after each Auto Shot and drains toward the center over the weapon speed cycle. When it empties, your next Auto Shot is ready.
- **Red reticules:** A pair of vertical red bars mark the aim window — the point where your character must be standing still and not casting to let the ~0.5s Auto Shot wind-up fire. Starting a cast before this zone can still clip the auto shot if the cast extends into or past it.
- **Bar color:** Blue when safe to cast, red when inside the aim window, grey when the GCD is active.
- **Clipping:** If you begin a cast that will delay the next Auto Shot, the predicted delay is shown in red between the reticules (e.g. `(0.34)`).
- **Overdue counter:** If an Auto Shot is ready but you haven't fired it — melee weaving, moving, or standing in the dead zone — a live orange counter (e.g. `(+1.3)`) ticks up showing how long you've delayed it. It clears when the shot finally fires. Small readings (under 0.2s) are suppressed since event latency makes every normal cycle look slightly late.
- **Swing resets:** An Aimed Shot landing restarts the cycle — the bar refills the moment it fires. Feign Death hides the bar while you're feigned, and the bar refills with a fresh full cycle the moment the feign ends.

<!-- ![Ranged Swing Timer](screenshots/ranged-swing-timer.png) -->

### Cast Bar

<img width="362" height="208" alt="Screenshot 2026-04-21 at 7 43 28 PM" src="https://github.com/user-attachments/assets/693e0817-ead9-4cd5-ad42-961f453d97c8" />


![Supported](https://img.shields.io/badge/Supported-green)

Cast bar for Auto Shot aim window, Aimed Shot, Steady Shot, and Multi-Shot. Each shot type has a distinct color.

- **Shot colors:** Auto Shot (green), Aimed Shot (gold), Steady Shot (purple), Multi-Shot (orange)
- **Auto Shot:** Detected automatically from your swing timer — the bar appears during the ~0.5s aim window when you must stand still for the shot to fire
- **Swing resets:** Aimed Shot and Feign Death reset the swing timer, and the aim-window prediction follows: after an Aimed Shot lands the next aim bar comes a full weapon cycle later, and after Feign Death a full cycle from the moment the feign ends — no more premature aim bar with no shot behind it
- **Multi-Shot:** Has a 0.5s base cast time (not instant), reduced by haste just like the Auto Shot wind-up
- **Haste:** All cast durations account for your current haste effects (Rapid Fire, Bloodlust, haste rating, etc.)
- **Failed casts:** A brief red flash is shown when a cast is interrupted or fails

<!-- ![Cast Bar](screenshots/cast-bar.png) -->

### Kill Command Alert

<img width="363" height="487" alt="Screenshot 2026-04-21 at 7 45 07 PM" src="https://github.com/user-attachments/assets/0ae8b900-106f-48a6-bf16-3778090592e9" />


![Supported](https://img.shields.io/badge/Supported-green)

Pulsing wing-shaped alert when Kill Command is ready and your pet is active.

- **Effect:** Two red eagle-wing crescents (made of feather-shaped lines) appear flanking the player, pulsing in and out at ~0.8 Hz
- **Shown when:** Kill Command proc is active (pet scored a crit), the ability is not on its 5-second cooldown, your pet is alive, and you are in combat
- **Hidden when:** Kill Command is on cooldown, the proc is not active, your pet is dead or dismissed, or you are out of combat

<!-- ![Kill Command Alert](screenshots/kill-command-alert.png) -->

### Active Effects Tracker

<img width="362" height="260" alt="Screenshot 2026-04-21 at 7 59 28 PM" src="https://github.com/user-attachments/assets/4385f23d-bab5-4846-8e68-e6d8ec622795" />


![Supported](https://img.shields.io/badge/Supported-green)

Icons with animated borders and countdowns for relevant rotation buffs (Quick Shots, Haste Potion, Bloodlust, Rapid Fire, etc.) and trinket procs.

- **Buffs tracked:** Quick Shots (Improved Aspect of the Hawk proc), Haste Potion, Bloodlust, Heroism, Rapid Fire, The Beast Within, Drums of Battle
- **Trinkets:** Automatically detects on-use trinket buffs from your equipped trinkets
- **Active effect appearance:** Each active buff shows its icon with a gold marching-ants animated border, a reverse cooldown sweep that fills as the buff expires, and a countdown timer
- **Hidden when:** No tracked buffs are active (and widget is locked)

<!-- ![Active Effects Tracker](screenshots/active-effects-tracker.png) -->

### Usable Items

<img width="126" height="170" alt="Screenshot 2026-04-21 at 7 46 00 PM" src="https://github.com/user-attachments/assets/67f71008-dc1a-4245-a332-8369c99e843d" />


![Supported](https://img.shields.io/badge/Supported-green)

Clickable mini action bar for consumables in your bags (health/mana potions, haste potions, drums). Click to use directly.

- **Items tracked:** Mana Rune (Demonic Rune, falling back to Dark Rune), Super Mana Potion, Super Healing Potion, Drums of Battle, Haste Potion, Heavy Netherweave Bandage, Master Healthstone
- **Bag count:** Each icon shows the number of that item in your bags. Drums of Battle shows remaining charges instead of item count. Items you don't have are greyed out and desaturated.
- **Alternates:** Some items automatically swap to a better option based on context. The mana rune slot prefers Demonic Rune and falls back to Dark Rune when you're out of Demonic Runes. For mana and healing potions: inside Tempest Keep instances the zone-specific Bottled Nethergon Energy/Vapor are preferred over everything; everywhere else Crystal Mana/Healing Potions are the top preference, then Auchenai potions, then the Super potion. The swap happens out of combat when you change zones or your bags update.
- **Healthstones:** Multiple Healthstone variants (from different warlocks) are layered into a single slot. The highest rank you have in your bags is shown; when it's used, the next highest rank takes its place.
- **Cooldowns:** Drums of Battle cooldown is driven by the Tinnitus debuff timer rather than the item cooldown; Heavy Netherweave Bandage uses the Recently Bandaged debuff. Other items show their normal item cooldown with a sweep and countdown.
- **Keybindings:** Each slot can be bound to a key in the standard **Key Bindings** menu (Esc → Key Bindings → *ExsarAddon* section: Mana Rune, Mana Potion, Health Potion, Drums of Battle, Haste Potion, Heavy Netherweave Bandage, Healthstone). Pressing the key uses that slot's item — including in combat. The bound key is shown in the top-right corner of the icon. Bindings are positional, so they keep working when a slot swaps to an alternate. Because they live in Blizzard's key bindings (not the addon's own settings), they sync across computers and warn you about conflicts when you assign them.

<!-- ![Usable Items](screenshots/usable-items.png) -->

### Target Debuff Tracker

![Supported](https://img.shields.io/badge/Supported-green)

Shows your Hunter's Mark and Serpent Sting on the current target with countdowns.

- **Player-only:** Only shows debuffs you cast, not those from other hunters

<!-- ![Target Debuff Tracker](screenshots/target-debuff-tracker.png) -->

### Raid Debuff Tracker

![Supported](https://img.shields.io/badge/Supported-green)

A combined status panel for critical raid debuffs on your target — showing both what's **present** (with refresh timers) and what's **missing** (to call out on Discord).

- **One row per debuff:** A vertical list under a "Raid debuffs:" title. Each tracked debuff shows either a **present** row — icon + name on a draining timer bar that runs blue → yellow (at 50% remaining) → orange (at 20% remaining) with a countdown, so you can see when it's about to fall off and needs refreshing — or a **missing** row — icon + red name on a solid red bar, so you can still call out absences.
- **All casters counted:** Detects debuffs applied by anyone in the raid, not just you — including their remaining durations.
- **Visibility you control:** A target is always required (it's what's scanned). By default the panel also only appears in combat and in a raid; two config checkboxes — **Show out of combat** and **Show out of raid** (both off by default) — let you relax either requirement, e.g. to watch debuffs while soloing or in a 5-man.
- **Testing preview:** While unlocked, it lists *every* tracked debuff as missing regardless of your target, so you can see the full widget and position it.
- **Per-debuff toggles:** Each tracked debuff can be turned off in config so you only watch for the ones your raid composition can actually provide. The whole widget can also be disabled.
- **Talent-gated debuffs (Faerie Fire & Judgement of the Crusader):** Some debuffs only give their bonus when the caster is talented — Improved Faerie Fire's +hit, and Judgement of the Crusader's +crit (from a paladin's Improved Seal of the Crusader). That talent is invisible on the target, so the widget identifies *which* druid/paladin provides it and only counts *their* version (a feral's armor-only Faerie Fire, or an untalented paladin's Judgement, still shows as missing). It finds them two ways: **automatically**, by inspecting nearby raid druids/paladins' talents whenever they come within ~28 yards (a one-time catch is enough — it remembers them for the session; toggle off with the **Auto-detect talented casters** checkbox if you'd rather not auto-inspect), and **manually**, by targeting the player and clicking **Set from target** in config. With nobody identified yet, the debuff from anyone counts.

<!-- ![Raid Debuff Tracker](screenshots/raid-debuff-tracker.png) -->

### Mend Pet Tracker

<img width="133" height="84" alt="Screenshot 2026-04-21 at 7 46 13 PM" src="https://github.com/user-attachments/assets/b185dce4-6d57-40ed-8889-4efd66091ec6" />


![Supported](https://img.shields.io/badge/Supported-green)

Tracks your Mend Pet HoT.

- **Effect:** Shows the Mend Pet icon with a pulsating green glow border (1 Hz) and a reverse cooldown sweep that fills as the HoT expires
- **Timer:** Countdown text in the center of the icon showing time remaining on the buff
- **Hidden when:** Mend Pet is not active on your pet (and widget is locked)

<!-- ![Mend Pet Tracker](screenshots/mend-pet-tracker.png) -->

### Food & Drink Widget

<img width="150" height="60" alt="Screenshot 2026-04-21 at 7 45 41 PM" src="https://github.com/user-attachments/assets/a54b955e-6d53-4ceb-993f-0d9897b1c84c" />


![Supported](https://img.shields.io/badge/Supported-green)

Food and drink icons that dim automatically in combat.

- **Items tracked:** Conjured Manna Biscuit, Purified Draenic Water, Clefthoof Ribs
- **Click to use:** Click an icon to eat or drink
- **Dimming:** Icons dim to half alpha in combat (since you can't eat/drink); items not in your bags are greyed out and desaturated

<!-- ![Food & Drink Widget](screenshots/food-and-drink.png) -->

### Consumable Buff Widget

<img width="398" height="61" alt="Screenshot 2026-04-21 at 7 45 49 PM" src="https://github.com/user-attachments/assets/62573d7d-1079-41a3-949b-0a1a830844da" />


![Supported](https://img.shields.io/badge/Supported-green)

Always-visible icons for consumable buffs (scrolls, elixirs, weapon enchants) with bag counts and active timers.

- **Items tracked:** Kibler's Bits (pet), Scroll of Strength (pet), Flask of Relentless Assault, Elixir of Major Agility, Elixir of Demonslaying, Elixir of Major Mageblood, Scroll of Agility, Adamantite Sharpening Stone, Adamantite Weightstone, Grilled Mudfish (falls back to Warp Burger), Spicy Hot Talbuk
- **Ranked / fallback items:** Scroll of Agility and Scroll of Strength support ranked fallback (V through I), and Grilled Mudfish falls back to Warp Burger (equivalent +20 Agility food). The preferred item you have in your bags is shown; if none are available, the preferred item is shown greyed out. Any listed item's buff counts as active.
- **Weapon enchants:** Adamantite Sharpening Stone and Adamantite Weightstone are tracked via `GetWeaponEnchantInfo()` rather than as buffs, since temporary weapon enchants don't appear in the buff list. Both weapon hands are checked — when a stone is applied to a dual-wield pair, the timer shows whichever hand will expire first. Duration is hardcoded (1 hour) since the API only provides time remaining, not total duration.
- **When active:** A gold glow border appears, a reverse cooldown sweep fills as the buff expires, and a countdown timer is shown
- **Click to use:** Click an icon to use the consumable

<!-- ![Consumable Buff Widget](screenshots/consumable-buff.png) -->

### Mount Widget

<img width="107" height="52" alt="Screenshot 2026-04-21 at 7 45 39 PM" src="https://github.com/user-attachments/assets/c1eb5830-dd94-4cf9-80c5-8274db2c2f11" />


![Supported](https://img.shields.io/badge/Supported-green)

One-click to use mounts.

- **Mounts tracked:** Reins of the Swift Stormsaber (ground), Starshard Netherdrake (flying)
- **Active indicator:** A yellow glow highlights whichever mount is currently active

<!-- ![Mount Widget](screenshots/mount.png) -->

### Target Info

<img width="138" height="92" alt="Screenshot 2026-04-21 at 7 45 22 PM" src="https://github.com/user-attachments/assets/23b63f33-011c-4c91-affb-ae5a32927f61" />


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

<img width="135" height="95" alt="Screenshot 2026-04-21 at 7 45 18 PM" src="https://github.com/user-attachments/assets/0a9c9f79-8bea-49c3-a6e0-b251c8dd75c5" />


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

<img width="145" height="93" alt="Screenshot 2026-04-21 at 7 45 15 PM" src="https://github.com/user-attachments/assets/62c7efd2-a90c-44d4-a4bf-6d8ddd492f65" />


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
<table>
  <tr>
    <td><img width="236" height="359" alt="Screenshot 2026-04-21 at 7 43 59 PM" src="https://github.com/user-attachments/assets/f3d50a1a-a343-45f4-90ba-25578d2a039a" /></td>
    <td><img width="216" height="371" alt="Screenshot 2026-04-21 at 7 44 12 PM" src="https://github.com/user-attachments/assets/449f218d-8094-4ab5-87a4-85d1d76434e0" /></td>
    <td><img width="217" height="377" alt="Screenshot 2026-04-21 at 7 44 16 PM" src="https://github.com/user-attachments/assets/1c139ae0-9952-4864-b167-53b75806a3ed" /></td>
  </tr>
</table>


![Supported](https://img.shields.io/badge/Supported-green)

Crossed-swords icon showing melee range status. Displays a cooldown sweep for your melee swing timer and a pulsating gold glow when your swing is ready in range.

- **Intent:** Designed to support melee weaving — stepping into melee range between auto shots to land a Raptor Strike. Shows at a glance whether you're in melee range and whether your swing is ready.
- **Visual states:**
  - **Ready** (in range, swing available): Full-alpha gold swords with blade glow lines, fast-pulsating gold glow ring (3 Hz) — swing now!
  - **On cooldown** (in range, swing cooling down): Half-alpha gold swords with cooldown sweep and countdown timer, slow-pulsating muted glow ring — move away after swinging
  - **Out of range, swing on cooldown:** Two green arrows pointing up on a grey circular background (no swords) with the cooldown sweep and countdown timer — step in, swing is resetting, no glow
  - **Out of range, swing ready:** Two green arrows pointing up on a grey circular background (no swords) — the always-on cue, shown whenever you're in combat but not in melee range. Same look as the on-cooldown state but without the sweep/timer.
  - **Hidden:** Out of combat with no swing cooldown lingering (and widget is locked)
- **Swing timer:** Tracked via combat log (SWING_DAMAGE/SWING_MISSED and Raptor Strike hits). Cooldown sweep and countdown show time until next swing.
- **Sound effects:** Optional sounds play when entering and leaving melee range (configurable in the config panel)

<!-- ![Melee Range Indicator](screenshots/melee-range.png) -->

### Global Cooldown Tracker

<img width="362" height="208" alt="Screenshot 2026-04-21 at 7 43 28 PM" src="https://github.com/user-attachments/assets/0966be23-4567-432f-91d5-0197409110b4" />


![Supported](https://img.shields.io/badge/Supported-green)

Sweep effect for the current GCD.

- **Appearance:** A circular sweep effect (no icon — just the sweep itself) with a pulsating blue glow ring behind it, and a countdown timer in the center
- **Triggered by:** Probes the GCD via Wing Clip's cooldown (which has no cooldown of its own, so it only ever returns the GCD). Fires on `SPELL_UPDATE_COOLDOWN` events.
- **Sweep color:** Grey during the GCD, transitions to blue when the remaining time enters the spell queue window — indicating you can queue your next ability
- **Hidden when:** GCD is not active (and widget is locked)

<!-- ![Global Cooldown Tracker](screenshots/gcd-tracker.png) -->

### Raid Target Widget

<img width="1512" height="982" alt="Screenshot 2026-04-20 at 10 34 17 PM" src="https://github.com/user-attachments/assets/cb011ddd-06ac-4473-9dbe-9a883f33d927" />


![Experimental](https://img.shields.io/badge/Experimental-yellow)

A tank/assist roster: a vertical list of the people you want to follow, one per row. Click a row to **assist** that person — you target whatever they're currently on, resolved live.

- **Tracked rows:** Auto-detected tanks **plus** anyone you name manually, one member per row. Each row shows the member's portrait and class-colored name, the raid mark on whatever they're currently targeting, that target's name (colored by reaction), and the target's health bar with percentage. The gold pulsing border lights up the row whose member is on **your** current target.
- **Assist on click:** Clicking a row targets whatever that member is on, resolved fresh each click — so it keeps working in combat and through mid-combat re-marks (you follow the *person*, not a mark).
- **Who gets tracked:** Tanks are detected from each member's **assigned group role** (anyone flagged as Tank), falling back to Main Tank assignments. To watch additional people (off-tanks the game didn't flag, a CC'er, a kill-target caller), add their names in the **Additional tracked members** box in the config — they're always added on top of the auto-detected tanks.
- **Group reshuffles:** Tracked members are matched by name and re-resolved as the raid moves people between groups (out of combat), so assisting always follows the right person.
- **Why assist-only (no mark-targeting):** WoW does not allow an addon to target an *arbitrary marked mob* in combat — targeting must be pre-decided before combat, and there's no game-side way to express "the unit with the square." The only reliably combat-stable target is a *person* who stays on their mob (a tank), which is why this widget assists people rather than icons.
- **Hidden when:** No tracked members are found (and the widget is locked).
- **Commands:** `/exsar rtreset` resets the widget's position.

<!-- ![Raid Target Widget](screenshots/raid-targets.png) -->

### Pet Aggressive Alert

<img width="277" height="201" alt="Screenshot 2026-04-21 at 7 58 45 PM" src="https://github.com/user-attachments/assets/bfbb541e-f948-4064-851c-0a38714b288c" />


![Supported](https://img.shields.io/badge/Supported-green)

Pulsing red skull when your pet is set to aggressive mode.

- **Appearance:** A red-tinted skull icon with "PET ON AGGRESSIVE!" text below it, on a semi-transparent dark red background. The entire frame pulses in and out at 1 Hz.
- **Detection:** Scans the pet action bar for the aggressive stance. Updates when the pet bar changes or when your pet is summoned/dismissed, with a 0.5-second safety poll to catch missed transitions.
- **Hidden when:** Pet is not on aggressive (and widget is locked), or the alert is disabled in config.

<!-- ![Pet Aggressive Alert](screenshots/pet-aggressive.png) -->

### Pet Happiness Tracker

<img width="145" height="93" alt="Screenshot 2026-04-21 at 7 45 15 PM" src="https://github.com/user-attachments/assets/ce824939-bde7-4675-98e2-f55e145bffe7" />


![Experimental](https://img.shields.io/badge/Experimental-yellow)

Happiness gauge estimating exact happiness points (0-1050) with a timer showing how long until the next tier drop. Optional sound alert when happiness decreases.

- **Display:** Shows the WoW pet happiness face icon (happy/content/unhappy) with a reverse cooldown sweep that fills as happiness drains toward the next tier boundary. A countdown timer shows estimated time until the next tier drop. When the estimate is approximate (not anchored to a known boundary), the timer is prefixed with `~`. On a fresh install with no saved data, a faint `?` is shown instead of a timer until a real anchor point is observed (tier crossing or feed-at-max) — no sweep is drawn in that state.
- **Warning:** A pulsating red glow border appears when the pet is content or unhappy. An optional sound alert plays when happiness drops a tier (configurable).
- **Algorithm:** The WoW API only exposes the happiness tier (1/2/3), not exact points. The tracker estimates exact happiness (0–1050, 350 points per tier) by:
  - Restoring the saved estimate if the tier matches; otherwise marking the estimate as a guess (tier midpoint used internally, `?` shown) until a tier crossing or feed-at-max anchors it
  - Applying passive decay continuously (~8.33 points/minute), clamped at the current tier's floor since the API is authoritative on tier
  - Adding feed amounts detected from combat log events (`SPELL_PERIODIC_ENERGIZE` with happiness power type), using the actual per-bite value (8, 17, or 35 depending on food quality)
  - Subtracting fixed penalties for pet death (–350) and dismissal (–50)
  - Reconciling with the API tier after each change: the estimate is preserved when it already falls inside the new tier's range (so exact feed arithmetic is not lost on a tier-up), and snapped to the crossed boundary only when outside — in which case we "anchor" to a known value
- **Storage:** The current estimate, tier, and anchored state are persisted to SavedVariables on every update tick, so the estimate survives across sessions. If the tier changed while logged out, it anchors to the appropriate boundary on login.
- **Debug logging:** A persistent ring buffer (last 30 events, survives `/reload`) captures state transitions: seed events, tier changes, feed bites, decay-floor clamp activations, and dismiss/death penalties — enough to diagnose a surprising display after the fact. Default ON; toggle with `/exsar phdebug`. `/exsar phdump` opens the log in a copy-paste window (Ctrl+A, Ctrl+C, Esc to close). `/exsar phclear` wipes the buffer.

<!-- ![Pet Happiness Tracker](screenshots/pet-happiness.png) -->

### Aggro Alert

<img width="647" height="209" alt="Screenshot 2026-04-21 at 7 46 23 PM" src="https://github.com/user-attachments/assets/a9de7f0f-9605-42ba-8a5f-25ddade9aa0d" />


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

<img width="62" height="80" alt="Screenshot 2026-04-21 at 7 45 32 PM" src="https://github.com/user-attachments/assets/a724f730-a000-47d1-b62f-7074dc6d912b" />


![Supported](https://img.shields.io/badge/Supported-green)

Equipped ammo icon with bag count overlay. Shows a red warning glow when ammo is low or missing.

- **Detection:** Reads the equipped ammo slot (inventory slot 0) via `GetInventoryItemID` and `GetInventoryItemCount`. Updates on equipment changes, bag updates, and a 1-second safety poll.
- **Count:** Displays the total ammo count as an overlay on the bottom-right of the icon.
- **Low ammo (≤600):** A pulsating red glow border appears around the icon as a restock reminder.
- **No ammo equipped:** Icon shows a greyed-out question mark with a red X overlay and the pulsating red warning glow.

<!-- ![Ammo Tracker](screenshots/ammo-tracker.png) -->

### Rotation Helper

<img width="362" height="208" alt="Screenshot 2026-04-21 at 7 43 28 PM" src="https://github.com/user-attachments/assets/e8d01b7e-bb4f-4268-af55-8f6c146fcd1d" />


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

### Range to Target

![Supported](https://img.shields.io/badge/Supported-green)

Shows an estimated distance bracket to your current target (e.g. "5-8 yd") with a weaving zone label.

- **Intent:** Generalizes the Melee Range Indicator's binary in/out check into a distance estimate, so you can position precisely for melee weaving — staying close while reading exactly how far out of melee you are.
- **Display:** Two stacked text lines — the distance bracket on top (e.g. "5-8 yd", "0-5 yd" when in melee, "35+ yd" when far), and a zone label below: **MELEE** (orange, within melee reach), **WEAVE** (green, the sweet spot just outside melee), **IN RANGE** (blue, within shooting range), or **FAR** (red, beyond shooting range).
- **Spec-aware shooting range:** Your maximum shooting range is 35 yd by default, but the Survival talent **Hawk Eye** adds 2 yd per rank (up to 41 yd at 3/3). The widget reads your Hawk Eye rank and extends both the IN RANGE→FAR boundary and the top of the distance bracket accordingly, so a Survival hunter isn't told "FAR" while a target is still shootable.
- **How it works:** WoW doesn't expose an exact distance to a unit, so the widget probes a ladder of range checks with known thresholds — Wing Clip (5 yd), a series of fixed-range items (8, 10, 15, 20, 25, 30, 35 yd), and your actual Auto Shot range at the top — and brackets your distance between the nearest in-range and farthest out-of-range check. The estimate is only as fine as the available checks; bounds widen if a check can't be evaluated. This is the same technique used by RangeDisplay and LibRangeCheck.
- **Shown when:** You have an attackable target (or the widget is unlocked for positioning); hidden otherwise.

<!-- ![Range to Target](screenshots/range-to-target.png) -->

### Pet Management

![Work in Progress](https://img.shields.io/badge/Work%20in%20Progress-yellow)

A compact, keybindable bar of pet-management buttons, so you can keep your pet controls together instead of spreading them across an action bar.

- **What it does:** Each icon runs a macro when clicked — so a single button can be a smart command (for example, one button that calls your pet when you have none, revives it when it's dead, and dismisses it when it's out). The specific actions are still being finalized.
- **State-aware:** The bar is always visible, but actions that can't be used given your pet's current state are greyed out — for example, a revive button greys out while your pet is alive, and pet-dependent actions grey out when you have no pet.
- **Smart icons:** A button can change its icon to match your pet's state. For example, the all-in-one pet button shows the Mend Pet icon when your pet is alive, the Revive Pet icon when it's dead, and the Call Pet icon when you have no pet.
- **Charge counts:** Item-based buttons show how many you have left in the bottom-right corner — for example, the Steam Tonk button shows the net number of Steam Tonk Controller charges in your bags.
- **Cooldowns:** Item-based buttons show a cooldown sweep and countdown timer when the item is on cooldown — for example, the Steam Tonk button reflects the Steam Tonk Controller's 30-second cooldown. Buttons whose macros cast a global-cooldown spell (Mend Pet, Dismiss Pet, Call Pet) also show a brief sweep during the global cooldown, so you can see when the action is momentarily blocked.
- **Out-of-range shade:** Pet-targeted buttons (Mend Pet on the all-in-one button, Feed Pet) are covered with a red shade over the icon when you're too far from your pet to use them, so you can see at a glance when you need to close the gap.
- **Out-of-mana shade:** The all-in-one button is covered with a blue shade when you can't afford to Mend your pet. The blue (out-of-mana) shade takes precedence over the red (out-of-range) one.
- **Built-in macros:** Each button runs a macro built into the addon and tuned for hunters; the macros aren't user-editable.
- **Devilsaur Tooth boss prep:** A dedicated button for the +crit-to-pet buff from the Devilsaur Tooth trinket. Click once before a pull to swap the Tooth into your top trinket slot (yellow border, "use me!"); wait out the 30-second equip cooldown; click again to apply the buff to your pet AND swap your previous trinket back in — both in one click. If anything blocks the swap-back (a sudden combat start, a disturbed bag slot), the button turns red ("UNEQUIP!") so you know to swap it back manually before pulling. The button greys out if you have no pet or no Tooth.
- **Keybindings:** Each slot can be bound to a key in the standard **Key Bindings** menu (Esc → Key Bindings → *ExsarAddon Pet* section). Pressing the key runs that slot's macro, including in combat. The bound key is shown in the top-right corner of the icon.

<!-- ![Pet Management](screenshots/pet-management.png) -->

### Aspects

![Work in Progress](https://img.shields.io/badge/Work%20in%20Progress-yellow)

A compact, keybindable vertical bar of your Hunter aspects, so you can swap aspects quickly without hunting through your spellbook or action bars.

- **What it does:** One button per aspect — Aspect of the Hawk, Viper, Cheetah, Pack, Wild, and Monkey. Click or press its key to cast that aspect.
- **Active aspect highlighted:** The aspect you currently have active shows an animated marching-ants border, so you can see at a glance which one is up.
- **Keybindings:** Each slot can be bound to a key in the standard **Key Bindings** menu (Esc → Key Bindings → *ExsarAddon Aspects* section). Pressing the key casts that aspect, including in combat. The bound key is shown in the top-right corner of the icon.

<!-- ![Aspects](screenshots/aspects.png) -->

### Traps

![Work in Progress](https://img.shields.io/badge/Work%20in%20Progress-yellow)

A compact, keybindable bar of your Hunter traps, so you can lay any trap with one click or key instead of digging through your spellbook.

- **What it does:** One button per trap — Frost, Freezing, Immolation, Explosive, and Snake. Click or press its key to lay that trap (always the highest rank you know).
- **Cooldowns:** Each trap shows a cooldown sweep and countdown timer while it's on cooldown, so you can see at a glance which traps are ready.
- **Out-of-mana shade:** A trap you can't afford to lay is covered with a blue shade over the icon, so you can see at a glance when you're too low on mana.
- **Keybindings:** Each slot can be bound to a key in the standard **Key Bindings** menu (Esc → Key Bindings → *ExsarAddon Traps* section). Pressing the key lays that trap, including in combat. The bound key is shown in the top-right corner of the icon.

<!-- ![Traps](screenshots/traps.png) -->

### Cooldowns

![Work in Progress](https://img.shields.io/badge/Work%20in%20Progress-yellow)

A compact, keybindable bar of your major cooldowns in one place — a mix of trinkets and abilities.

- **What it does:** One button each for your top and bottom trinket plus key ability cooldowns (Rapid Fire, Bestial Wrath, Intimidation, …). Click or press its key to fire it.
- **Burst combo buttons:** Dedicated buttons that fire an ability together with a trinket (e.g. Bestial Wrath + bottom trinket, Rapid Fire + top trinket). These only show "ready" when *both* the ability and the trinket are off cooldown, and sit alongside the standalone buttons so you can bind each however you like.
- **Trinkets follow your gear:** The trinket slots use whatever you currently have equipped in your top/bottom trinket slots, showing that item's icon and cooldown — no setup when you swap trinkets.
- **Adapts to your spec:** Talent abilities only appear when you have them. The Bestial Wrath slot becomes Readiness if you're Survival, and the Intimidation slot disappears entirely unless you're Beast Mastery.
- **At-a-glance readiness:** Each slot shows a cooldown sweep and countdown, and dims while it's on cooldown, so you can instantly see what's ready.
- **Out-of-range shade:** When you have an attackable target, a harm ability that's out of range (e.g. Intimidation) is covered with a red shade over the icon, so you can see at a glance when you need to close distance.
- **Out-of-mana shade:** A cooldown you can't afford is covered with a blue shade over the icon. The blue (out-of-mana) shade takes precedence over the red (out-of-range) one.
- **Keybindings:** Each slot can be bound to a key in the standard **Key Bindings** menu (Esc → Key Bindings → *ExsarAddon Cooldowns* section), usable in combat. The bound key is shown in the top-right corner of the icon.

<!-- ![Cooldowns](screenshots/cooldowns.png) -->

### Core Combat

![Work in Progress](https://img.shields.io/badge/Work%20in%20Progress-yellow)

A compact, keybindable bar of your main combat abilities and a couple of handy combat macros, all in one place.

- **What it does:** One button per core ability (Steady Shot, Multi-Shot, Arcane Shot, Kill Command, Aimed Shot, stings, traps-of-the-trade like Concussive/Wing Clip, …) plus two macros — a start-attack button (targets the nearest enemy and turns on Auto Shot) and a Raptor Strike melee-weave button.
- **Casts the right rank:** Ability buttons always use the highest rank you know, and show that spell's tooltip on hover.
- **Adapts to your spec:** Abilities you don't know simply don't appear — so Aimed Shot only shows up when you're Marksmanship.
- **Cooldown feedback:** Abilities with a real cooldown (Multi-Shot, Arcane Shot, Kill Command, …) show a sweep + countdown and dim while down; instant/GCD-only shots stay bright so the bar doesn't flicker as you spam.
- **Out-of-range shade:** When you have an attackable target, any ability that's out of range is covered with a red shade over the icon (like the default UI's red hotkey numbers, but over the whole icon) — so you can see at a glance which shots you need to close distance for.
- **Out-of-mana shade:** A shot you can't afford is covered with a blue shade over the icon (like the default UI's blue tint). The blue (out-of-mana) shade takes precedence over the red (out-of-range) one.
- **Keybindings:** Each slot can be bound to a key in the standard **Key Bindings** menu (Esc → Key Bindings → *ExsarAddon Combat* section), usable in combat. The bound key is shown in the top-right corner of the icon.

<!-- ![Core Combat](screenshots/core-combat.png) -->

### Utilities

![Work in Progress](https://img.shields.io/badge/Work%20in%20Progress-yellow)

A compact, keybindable bar for your situational utility — abilities you reach for occasionally plus a few quality-of-life macros.

- **What it does:** Utility abilities (Misdirection, Feign Death, Tranquilizing Shot, Eyes of the Beast, Shadowmeld, Flare, …) alongside handy macros.
- **Adapts to your character:** Abilities you don't have simply don't appear — Misdirection only shows for Marksmanship, Shadowmeld only for Night Elves.
- **Fishing setup in one button:** Equips your fishing pole and applies your Sharpened Fish Hook to it.
- **Weapon swapping:** One-press buttons to switch between your 2H weapon and your dual 1H setup — works in combat. The button for whatever you currently have equipped is highlighted with a gold ring (the dual-1H button lights up only when both weapons are equipped), and the fishing button highlights while your fishing pole is out.
- **Cooldown feedback:** Abilities with a real cooldown show a sweep + countdown and dim while down.
- **Out-of-range shade:** An ability that's out of range of its target is covered with a red shade over the icon — Tranquilizing Shot against an attackable enemy, and Misdirection against the friendly target you're redirecting to — so you can see at a glance when you need to close distance.
- **Out-of-mana shade:** An ability you can't afford is covered with a blue shade over the icon. The blue (out-of-mana) shade takes precedence over the red (out-of-range) one.
- **Keybindings:** Each slot can be bound to a key in the standard **Key Bindings** menu (Esc → Key Bindings → *ExsarAddon Utility* section). The bound key is shown in the top-right corner of the icon.

<!-- ![Utilities](screenshots/utilities.png) -->
