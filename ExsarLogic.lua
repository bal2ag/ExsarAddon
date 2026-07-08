-- ExsarLogic.lua
-- Pure logic functions extracted for testability.
-- These functions have no WoW API dependencies and can be tested outside the game client.

local ExsarLogic = {}

-- =========================================================
-- Timer formatting
-- =========================================================

--- Format a cooldown remaining time for display.
-- ≥60s: minutes (rounded up), e.g. "5m"
-- 10–59s: whole seconds (rounded up), e.g. "45"
-- <10s: one decimal, e.g. "3.2"
function ExsarLogic.FormatCooldown(remaining)
    if remaining >= 60 then
        return string.format("%dm", math.ceil(remaining / 60))
    elseif remaining >= 10 then
        return string.format("%d", math.ceil(remaining))
    else
        return string.format("%.1f", remaining)
    end
end

--- Format a cooldown for short-duration timers (no minutes tier).
-- ≥10s: whole seconds (rounded up), <10s: one decimal.
function ExsarLogic.FormatShortTimer(remaining)
    if remaining >= 10 then
        return string.format("%d", math.ceil(remaining))
    else
        return string.format("%.1f", remaining)
    end
end

--- Format a large number for compact display.
-- ≥1000: "1.5k", else the number as a string.
function ExsarLogic.FormatNumber(n)
    if n >= 1000 then
        return string.format("%.1fk", n / 1000)
    end
    return tostring(n)
end

-- =========================================================
-- Color functions
-- =========================================================

--- Health bar color with smooth gradient (used by RaidTargetWidget).
-- >50%: green→yellow, ≤50%: yellow→red
function ExsarLogic.HealthColorGradient(pct)
    if pct > 50 then
        local f = (pct - 50) / 50
        return 0.1 + 0.9 * (1 - f), 0.9, 0.1
    else
        local f = pct / 50
        return 0.9, 0.9 * f, 0.1
    end
end

--- Health bar color with discrete thresholds (used by TargetInfoWidget).
-- >50%: green, 20–50%: yellow, <20%: red
function ExsarLogic.HealthColorThreshold(pct)
    if pct > 50 then
        return 0.20, 0.75, 0.20
    elseif pct > 20 then
        return 0.90, 0.90, 0.10
    else
        return 0.80, 0.15, 0.15
    end
end

--- Target level difficulty color.
-- @param targetLevel  the target's level (-1 for skull/unknown)
-- @param playerLevel  the player's level
function ExsarLogic.LevelColor(targetLevel, playerLevel)
    if targetLevel < 0 then return 0.80, 0.30, 0.80, 1 end
    local diff = targetLevel - playerLevel
    if     diff >=  5 then return 1.00, 0.10, 0.10, 1
    elseif diff >=  3 then return 1.00, 0.50, 0.25, 1
    elseif diff >= -2 then return 1.00, 1.00, 0.00, 1
    elseif diff >= -4 then return 0.25, 0.75, 0.25, 1
    else                   return 0.55, 0.55, 0.55, 1
    end
end

-- =========================================================
-- Cooldown state logic
-- =========================================================

ExsarLogic.MIN_COOLDOWN_DURATION = 1.6

--- Determine cooldown state from GetSpellCooldown / GetInventoryItemCooldown returns.
-- @return "cooldown", "gcd", or "ready"
function ExsarLogic.CooldownState(start, duration)
    local onCooldown = start and start > 0 and duration and duration > ExsarLogic.MIN_COOLDOWN_DURATION
    if onCooldown then return "cooldown" end
    local onGCD = start and start > 0 and duration and duration > 0
    if onGCD then return "gcd" end
    return "ready"
end

--- Classify a trinket slot from its equipped item's cache state.
-- Distinguishes "the item has no on-use effect" from "the item's data is not
-- cached yet" -- the latter happens transiently after a taxi flight or zoning,
-- when GetItemSpell returns nil purely because the client hasn't loaded the
-- item. Treating that as "no trinket" wipes the icon and it never comes back
-- until an equip change re-scans; classifying it as "pending" lets the caller
-- keep the current display and retry when the data arrives.
-- @param itemId     GetInventoryItemID for the slot (nil/0 = empty slot)
-- @param spellName  GetItemSpell(itemId) result (a use-effect spell name, or nil)
-- @param cached     whether the item's data is loaded (GetItemInfo ~= nil)
-- @return "known" (has on-use effect -> show), "empty" (nothing to show ->
--         hide), or "pending" (data not cached yet -> keep current, retry)
function ExsarLogic.TrinketScanState(itemId, spellName, cached)
    if not itemId or itemId <= 0 then return "empty" end
    if spellName then return "known" end
    if not cached then return "pending" end
    return "empty"
end

--- Calculate remaining time from cooldown start/duration and current time.
function ExsarLogic.CooldownRemaining(start, duration, now)
    if not start or not duration then return 0 end
    local remaining = (start + duration) - now
    return remaining > 0 and remaining or 0
end

-- =========================================================
-- Layout math
-- =========================================================

--- Calculate horizontal icon strip width.
-- Given a list of groups (each a list of {known=bool} entries), icon size,
-- icon gap, group gap, and padding, return the total widget width.
function ExsarLogic.CalcStripWidth(groups, iconSize, iconGap, groupGap, padding)
    local x = padding
    local anyPlaced = false

    for _, group in ipairs(groups) do
        local visCount = 0
        for _, entry in ipairs(group) do
            if entry.known then visCount = visCount + 1 end
        end

        if visCount > 0 then
            if anyPlaced then
                x = x + groupGap
            end
            x = x + visCount * iconSize + (visCount - 1) * iconGap
            anyPlaced = true
        end
    end

    if anyPlaced then
        return x + padding
    else
        return padding * 2
    end
end

--- Calculate horizontal strip dimensions for a flat list of visible items.
-- @param visibleCount  number of visible icons
-- @param iconSize      icon size in pixels
-- @param iconGap       gap between icons
-- @param padding       padding on each side
-- @return width, height
function ExsarLogic.CalcFlatStripSize(visibleCount, iconSize, iconGap, padding)
    if visibleCount <= 0 then
        return padding * 2, iconSize + padding * 2
    end
    local w = padding + visibleCount * iconSize + (visibleCount - 1) * iconGap + padding
    return w, iconSize + padding * 2
end

--- Calculate vertical strip dimensions for a flat list of visible items.
-- @param visibleCount  number of visible icons
-- @param iconSize      icon size in pixels
-- @param iconGap       gap between icons
-- @param padding       padding on each side
-- @return width, height
function ExsarLogic.CalcVerticalStripSize(visibleCount, iconSize, iconGap, padding)
    if visibleCount <= 0 then
        return iconSize + padding * 2, padding * 2
    end
    local h = padding + visibleCount * iconSize + (visibleCount - 1) * iconGap + padding
    return iconSize + padding * 2, h
end

--- Calculate reticule position as a fraction of half-width.
-- @param aimWindow  seconds before shot to stop moving
-- @param speed      hasted weapon speed in seconds
-- @return fraction (clamped to 0.98)
function ExsarLogic.ReticuleFraction(aimWindow, speed)
    if speed <= 0 then return 0 end
    return math.min(aimWindow / speed, 0.98)
end

--- Compute the projected delay to the next auto shot.
-- Covers both delay regimes: a cast in progress that will finish after the
-- shot is due (predicted clip), and a shot already past due that has not
-- fired (live overdue — e.g. melee weaving with auto-repeat off, moving,
-- dead zone). Each regime has its own display threshold: predicted clips are
-- client-side math and can be trusted near zero, while overdue readings lag
-- the server by event latency, so every normal cycle reads slightly "late"
-- right before UNIT_SPELLCAST_SUCCEEDED arrives.
-- @param now           current time
-- @param lastShotTime  time of the last auto shot (0/nil = no cycle running)
-- @param speed         hasted weapon speed in seconds
-- @param castEnd       absolute end time of the player's current cast (0/nil = not casting)
-- @param predictGrace  minimum predicted clip worth showing (default 0.02)
-- @param overdueGrace  minimum elapsed lateness worth showing (default 0.2)
-- @return delay in seconds (or nil if none to show), isPredicted (true = cast-driven)
function ExsarLogic.AutoShotDelay(now, lastShotTime, speed, castEnd, predictGrace, overdueGrace)
    if not lastShotTime or lastShotTime <= 0 then return nil end
    if not speed or speed <= 0 then return nil end
    local due = lastShotTime + speed
    local casting = castEnd ~= nil and castEnd > now
    local delay = (casting and math.max(castEnd, now) or now) - due
    local grace = casting and (predictGrace or 0.02) or (overdueGrace or 0.2)
    if delay > grace then
        return delay, casting
    end
    return nil
end

--- Whether the auto-shot "HOLD" warning should currently be shown.
-- The hold window is the gap between the aim bar reaching its predicted end
-- (the shot is due) and the shot actually firing — the hidden retry-timer delay.
-- It ends when the shot fires (caller drops out of the hold state), the player
-- moves (movement cancels the pending shot), auto shot is toggled off, or a
-- safety cap (holdEnd) is reached so a missed fire event can't strand the glow.
-- @param autoActive  true while Auto Shot auto-repeat is toggled on
-- @param moving      true if the player is moving this frame
-- @param now         current time (GetTime())
-- @param holdEnd     absolute safety-cap time for the hold (0/nil = no hold)
-- @return true if the hold warning should be visible
function ExsarLogic.ShouldShowHoldWarning(autoActive, moving, now, holdEnd)
    if not autoActive then return false end
    if moving then return false end
    if not holdEnd or holdEnd <= 0 then return false end
    if now >= holdEnd then return false end
    return true
end

--- Calculate grid position for icon layout (0-based col/row).
-- @param index       1-based index
-- @param iconsPerRow number of icons per row
-- @return col, row (0-based)
function ExsarLogic.GridPosition(index, iconsPerRow)
    local col = (index - 1) % iconsPerRow
    local row = math.floor((index - 1) / iconsPerRow)
    return col, row
end

--- Calculate how many icons fit per row in a given width.
-- @param frameWidth  total frame width
-- @param padding     padding on each side
-- @param iconSize    icon size in pixels
-- @param iconGap     gap between icons
-- @return number of icons per row (at least 1)
function ExsarLogic.IconsPerRow(frameWidth, padding, iconSize, iconGap)
    local available = frameWidth - padding * 2 + iconGap
    local perRow = math.floor(available / (iconSize + iconGap))
    return math.max(1, perRow)
end

--- Calculate the number of rows needed for a grid.
function ExsarLogic.GridRowCount(itemCount, iconsPerRow)
    if itemCount <= 0 then return 0 end
    return math.ceil(itemCount / iconsPerRow)
end

-- =========================================================
-- Animation math
-- =========================================================

--- Pulse alpha for animations (sine wave oscillation).
-- @param time      current time
-- @param frequency oscillation frequency in Hz
-- @param minAlpha  minimum alpha
-- @param maxAlpha  maximum alpha
-- @return alpha value
function ExsarLogic.PulseAlpha(time, frequency, minAlpha, maxAlpha)
    local mid = (minAlpha + maxAlpha) / 2
    local amp = (maxAlpha - minAlpha) / 2
    return mid + amp * math.sin(time * 2 * math.pi * frequency)
end

--- Calculate marching-ants dash alpha for a single dash.
-- @param dashIndex  0-based index of this dash
-- @param headPos    current animation head position (float, wraps at dashCount)
-- @param dashCount  total number of dashes
-- @param tailLen    number of dashes in the bright tail
-- @return alpha (0 to 1)
function ExsarLogic.MarchingAntAlpha(dashIndex, headPos, dashCount, tailLen)
    local dist = (headPos - dashIndex + dashCount) % dashCount
    if dist < tailLen then
        return 1.0 - (dist / tailLen) * 0.85
    else
        return 0
    end
end

--- Calculate marching-ants head position from time.
-- @param time       current time (GetTime())
-- @param speed      animation speed multiplier
-- @param dashCount  total number of dashes
-- @return head position (float, wraps at dashCount)
function ExsarLogic.MarchingAntHead(time, speed, dashCount)
    return (time * speed * dashCount) % dashCount
end

-- =========================================================
-- Positioning math
-- =========================================================

--- Calculate anchor offset after dragging a frame (for TOPLEFT-anchored frames).
-- Used by info widgets that anchor to UIParent CENTER but position via TOPLEFT.
-- @param frameLeft   frame:GetLeft()
-- @param frameTop    frame:GetTop()
-- @param frameScale  frame:GetScale()
-- @param screenW     UIParent:GetWidth()
-- @param screenH     UIParent:GetHeight()
-- @return anchorX, anchorY
function ExsarLogic.CalcAnchorOffset(frameLeft, frameTop, frameScale, screenW, screenH)
    local anchorX = frameLeft - screenW  / (2 * frameScale)
    local anchorY = frameTop  - screenH / (2 * frameScale)
    return anchorX, anchorY
end

--- Round a scale value to the nearest 0.05 (used by all config scale sliders).
function ExsarLogic.RoundScale(v)
    return math.floor(v * 20 + 0.5) / 20
end

--- Check whether an aggro alert should display for the current group context.
-- @param context string: "solo", "party", or "raid"
-- @param enableSolo boolean
-- @param enableParty boolean
-- @param enableRaid boolean
-- @return boolean
function ExsarLogic.AggroAlertEnabled(context, enableSolo, enableParty, enableRaid)
    if context == "solo" then return enableSolo and true or false end
    if context == "party" then return enableParty and true or false end
    if context == "raid" then return enableRaid and true or false end
    return false
end

--- Select the best rank from a ranked item list given a count-lookup function.
-- Ranks are ordered highest-first. Returns the first rank with count > 0,
-- or the first rank (highest) as a fallback when nothing is in stock.
-- @param ranks  array of { id, name, buffId, ... } ordered highest-first
-- @param getCount  function(id) → number (bag count for that item ID)
-- @return rank entry (table from the ranks array)
function ExsarLogic.SelectBestRank(ranks, getCount)
    local best
    for _, rank in ipairs(ranks) do
        local count = getCount(rank.id)
        if count > 0 and not best then
            best = rank
        end
    end
    return best or ranks[1]
end

--- Select the first in-stock alternate item, falling back to the primary.
-- Mirrors the UsableItemsWidget swap rule: walk the ordered alternates and
-- return the first one whose optional zone gate passes and which the player
-- carries (count > 0); if none qualify, return the primary. Unlike
-- SelectBestRank, order is "first match wins" (so zone-restricted alternates
-- should come first), and the primary is the default rather than a ranked top.
-- @param primary     table  { id, name, ... } — the default when no alt qualifies
-- @param alternates  array of { id, name, zones = { [zoneName]=true } | nil }
-- @param zone        string  current zone name (matched against alt.zones)
-- @param getCount    function(id) → number (bag count for that item ID)
-- @return the chosen entry (an alternate, or the primary)
function ExsarLogic.SelectFirstInStock(primary, alternates, zone, getCount)
    for _, alt in ipairs(alternates or {}) do
        local zoneOk = not alt.zones or alt.zones[zone]
        if zoneOk and getCount(alt.id) > 0 then
            return alt
        end
    end
    return primary
end

--- Pick the soonest-to-expire weapon enchant matching a target enchant ID.
-- Temporary weapon enchants (sharpening / weightstones) can be applied to both
-- weapons at once; the widget tracks whichever hand will run out first so the
-- displayed timer never overstates the protection remaining. Pass the main-
-- and off-hand returns of GetWeaponEnchantInfo plus the enchant ID to match
-- (nil matches any enchant — used when we don't care which stone it is).
-- @return smallest remaining-ms among matching hands, or nil if neither matches
function ExsarLogic.MinWeaponEnchantRemaining(targetEnchantId,
        hasMain, mainMs, mainId, hasOff, offMs, offId)
    local best
    if hasMain and mainMs and mainMs > 0
       and (not targetEnchantId or mainId == targetEnchantId) then
        best = mainMs
    end
    if hasOff and offMs and offMs > 0
       and (not targetEnchantId or offId == targetEnchantId) then
        if not best or offMs < best then best = offMs end
    end
    return best
end

--- Given an effective (hasted) weapon speed, suggest a rotation string.
-- Boundaries: >=1.83 → "5:6:1:1", [1.22,1.83) → "1:1", (0.83,1.22) → "2:3", ≤0.83 → "1:2"
function ExsarLogic.SuggestRotation(effectiveSpeed)
    -- Round to 2 decimal places to avoid floating point edge cases
    -- (e.g. UnitRangedDamage returning 1.82999... for 1.83)
    effectiveSpeed = math.floor(effectiveSpeed * 100 + 0.5) / 100
    if effectiveSpeed >= 1.83 then
        return "5:6:1:1"
    elseif effectiveSpeed >= 1.22 then
        return "1:1"
    elseif effectiveSpeed > 0.83 then
        return "2:3"
    else
        return "1:2"
    end
end

-- =========================================================
-- Range-to-target bracketing
-- =========================================================
-- WoW does not expose an exact distance to a unit. Instead we probe a set of
-- "checkers" (spells / items) each with a known range threshold, then bracket
-- the distance: the smallest threshold still in range is the upper bound, the
-- largest out-of-range threshold is the lower bound. This is the same approach
-- LibRangeCheck / RangeDisplay use.

--- Compute a min/max distance bracket from an ordered list of range checks.
-- @param checkers  array of { range = number, ... } ordered ascending by range
-- @param results   parallel table: results[i] is true (within checker range),
--                  false (out of range), or nil (could not be checked — skip)
-- @return minRange, maxRange
--   minRange is the tightest lower bound (largest out-of-range threshold), or
--     nil when the target is within the closest usable checker (effectively 0).
--   maxRange is the tightest upper bound (smallest in-range threshold), or nil
--     when the target is beyond the furthest usable checker.
--   Both nil ⇒ nothing could be determined (no usable checker results).
function ExsarLogic.ComputeRangeBracket(checkers, results)
    local minR, maxR
    for i, checker in ipairs(checkers) do
        local r = results[i]
        if r == true then
            -- within checker.range ⇒ distance <= checker.range (upper bound)
            if maxR == nil or checker.range < maxR then
                maxR = checker.range
            end
        elseif r == false then
            -- out of checker.range ⇒ distance > checker.range (lower bound)
            if minR == nil or checker.range > minR then
                minR = checker.range
            end
        end
        -- r == nil: checker unusable (e.g. invalid item, combat restriction) — skip
    end
    -- Guard against non-monotonic noise (a near check claiming in-range while a
    -- farther check claims out-of-range). The in-range upper bound is the more
    -- trustworthy signal, so drop the contradictory lower bound.
    if minR and maxR and minR >= maxR then
        minR = nil
    end
    return minR, maxR
end

--- Format a min/max bracket (from ComputeRangeBracket) for display.
-- nil min ⇒ closer than the nearest checker (shown as 0); nil max ⇒ farther
-- than the furthest checker (shown as "min+"). Both nil ⇒ "?".
function ExsarLogic.FormatRangeBracket(minR, maxR)
    if not minR and not maxR then return "?" end
    if not maxR then return string.format("%d+ yd", minR) end
    local lo = minR or 0
    return string.format("%d-%d yd", lo, maxR)
end

--- Decide whether an action icon's out-of-range red shade should show.
-- Mirrors the default UI's red-hotkey behavior: shade only when the ability's
-- range unit is valid (exists + alive) AND the ability is confirmed out of
-- range of it. The unit can be the hostile target (harm spells), a friendly
-- target (Misdirection), or the pet (Mend/Feed Pet) -- `IsSpellInRange` returns
-- nil when the spell can't target that unit, so a nil result (no range
-- restriction, wrong unit type, or spell unknown) never shades.
-- @param inRange  IsSpellInRange result: 1 (in range), 0 (out of range), nil (N/A)
-- @param hasValidUnit bool (range unit exists and is alive)
-- @return bool
function ExsarLogic.ShouldShowRangeShade(inRange, hasValidUnit)
    if not hasValidUnit then return false end
    return inRange == 0
end

--- Decide whether an action icon's out-of-mana blue shade should show.
-- Mirrors the default UI's blue tint: shade only when the spell is unusable
-- specifically for lack of mana/power -- the second return of IsUsableSpell.
-- Other unusable reasons (on cooldown, no valid target, not learned) leave the
-- second return false/nil and so do NOT shade.
-- @param noMana  IsUsableSpell 2nd return: true = not enough mana/power
-- @return bool
function ExsarLogic.ShouldShowManaShade(noMana)
    return noMana and true or false
end

--- Compute the hunter's maximum ranged shooting range.
-- Base ranged range is 35 yd; the Survival talent Hawk Eye adds 2 yd per rank
-- (max 3 ranks → +6 yd → 41 yd). Used to extend the range widget's "far"
-- boundary and its top-end Auto Shot checker for Survival-specced hunters.
-- @param hawkEyeRank number talent rank (0-3); nil treated as 0
-- @param base       number optional base range (default 35)
-- @return number maximum shooting range in yards
function ExsarLogic.MaxShootingRange(hawkEyeRank, base)
    base = base or 35
    return base + 2 * (hawkEyeRank or 0)
end

--- Classify a bracket into a weaving zone label.
-- "melee": within melee reach (too close); "weave": the sweet spot just outside
-- melee; "inrange": within shooting range; "far": beyond shooting range;
-- "?": indeterminate.
-- @param minR,maxR  bracket from ComputeRangeBracket
-- @param meleeMax   melee-range threshold (default 5)
-- @param weaveMax   upper edge of the weave window (default 8)
-- @param rangedMax  edge of shooting range; beyond it is "far" (default 35)
function ExsarLogic.RangeZone(minR, maxR, meleeMax, weaveMax, rangedMax)
    meleeMax = meleeMax or 5
    weaveMax = weaveMax or 8
    rangedMax = rangedMax or 35
    if not minR and not maxR then return "?" end
    if maxR and maxR <= meleeMax then return "melee" end
    if minR and minR >= rangedMax then return "far" end
    if minR and minR >= weaveMax then return "inrange" end
    return "weave"
end

-- =========================================================
-- Pet happiness model
-- =========================================================

--- Reconcile a happiness point estimate against an authoritative API tier.
-- Snaps the estimate to the nearest tier boundary when it falls outside the
-- tier's range; otherwise preserves it. When a snap happens we are at a known
-- boundary, so the returned `anchored` flag becomes true. Inside the range,
-- `anchored` is passed through unchanged.
--
-- This replaces a direction-based "tier went up → set to floor / went down →
-- set to ceiling" rule that destroyed exact arithmetic (e.g. a feed that
-- crossed the boundary by a known amount) whenever the API tier flipped.
--
-- Params:
--   estimate   current numeric estimate
--   newTier    API-reported tier (1, 2, or 3)
--   anchored   current anchored flag
--   tierMin    table keyed by tier → lower bound (inclusive)
--   tierMax    table keyed by tier → upper bound (inclusive)
-- Returns: newEstimate, newAnchored
function ExsarLogic.ReconcileHappinessTier(estimate, newTier, anchored, tierMin, tierMax)
    local lo = tierMin[newTier]
    local hi = tierMax[newTier]
    if estimate < lo then
        return lo, true
    elseif estimate > hi then
        return hi, true
    end
    return estimate, anchored
end

--- Apply passive happiness decay, clamped to the API-reported tier floor.
-- The WoW API is authoritative on tier; if it still reports the current tier,
-- the real value cannot be below that tier's floor, so our estimate shouldn't
-- drop past it either. Without this clamp, estimate drifts below floor and
-- `ptsAboveTier` goes negative, which the display collapses to a stuck 0.0s.
--
-- Params:
--   estimate      current estimate
--   elapsedSec    seconds since last decay tick (non-negative)
--   decayPerMin   decay rate in points/minute
--   apiTier       authoritative API tier (1,2,3) or 0 if unknown
--   tierMin       table keyed by tier → lower bound
--   maxHappiness  absolute maximum (upper clamp)
-- Returns: newEstimate, clamped (true iff decay would have pushed below floor)
function ExsarLogic.ApplyHappinessDecay(estimate, elapsedSec, decayPerMin, apiTier, tierMin, maxHappiness)
    if elapsedSec < 0 then elapsedSec = 0 end
    local decayed = estimate - decayPerMin * (elapsedSec / 60)
    local newEst = decayed
    if newEst > maxHappiness then newEst = maxHappiness end
    local floor = tierMin[apiTier] or 0
    local clamped = false
    if newEst < floor then
        newEst = floor
        clamped = elapsedSec > 0  -- only count as a decay-clamp when decay actually ran
    end
    if newEst < 0 then newEst = 0 end
    return newEst, clamped
end

-- =========================================================
-- Keybinding display
-- =========================================================

--- Abbreviate a binding key string for compact on-icon display, matching the
-- default action-bar hotkey style. Modifiers collapse to single lowercase
-- letters with no separator (SHIFT-1 → "s1", CTRL-SHIFT-F → "csF"); mouse
-- buttons and wheel, numpad keys, and a few named keys are shortened
-- (BUTTON4 → "m4", CTRL-BUTTON4 → "cm4", MOUSEWHEELUP → "mwu", NUMPAD3 → "n3").
-- Returns nil for an unset/empty key so callers can clear the label.
function ExsarLogic.AbbreviateBindingKey(key)
    if not key or key == "" then return nil end
    local s = key:upper()
    -- Modifiers → single lowercase letter, no separator.
    s = s:gsub("ALT%-", "a")
    s = s:gsub("CTRL%-", "c")
    s = s:gsub("SHIFT%-", "s")
    -- Mouse wheel (before the generic BUTTON rule).
    s = s:gsub("MOUSEWHEELUP", "mwu")
    s = s:gsub("MOUSEWHEELDOWN", "mwd")
    -- Mouse buttons: BUTTON4 → m4.
    s = s:gsub("BUTTON", "m")
    -- Numpad: specific symbols first, then the generic prefix.
    s = s:gsub("NUMPADDIVIDE", "n/")
    s = s:gsub("NUMPADMULTIPLY", "n*")
    s = s:gsub("NUMPADMINUS", "n-")
    s = s:gsub("NUMPADPLUS", "n+")
    s = s:gsub("NUMPADDECIMAL", "n.")
    s = s:gsub("NUMPAD", "n")
    -- A couple of long named keys.
    s = s:gsub("SPACE", "Sp")
    return s
end

-- Decide whether a pet action is currently usable given the pet's state, so the
-- widget can grey out actions that can't fire (e.g. Revive when the pet is not
-- dead, Mend when there is no pet). Pure so the gating is unit-tested without WoW.
-- @param requires  string|nil  the pet state the action needs:
--                  nil / "any" → always usable
--                  "active"    → pet must exist
--                  "alive"     → pet must exist and be alive
--                  "dead"      → pet must exist and be dead
--                  "missing"   → no pet (e.g. Call Pet)
--                  "notdead"   → anything except an existing dead pet (i.e. alive
--                                or no pet); greyed only when the pet is dead
--                  any unknown token fails open (usable) so a typo can't hide a button
-- @param state     table  { exists = bool, alive = bool }  (alive implies exists)
-- @return boolean  true if the action should be enabled (not greyed)
function ExsarLogic.PetActionEnabled(requires, state)
    state = state or {}
    if requires == nil or requires == "any" then return true end
    if requires == "active"  then return state.exists == true end
    if requires == "alive"   then return state.exists == true and state.alive == true end
    if requires == "dead"    then return state.exists == true and state.alive ~= true end
    if requires == "missing" then return state.exists ~= true end
    if requires == "notdead" then return state.exists ~= true or state.alive == true end
    return true
end

-- Classify pet state into a single key for picking a state-dependent icon (e.g.
-- a "do the right thing" pet button showing Mend / Revive / Call icons). Pure.
-- @param state  table  { exists = bool, alive = bool }  (alive implies exists)
-- @return string  "alive" | "dead" | "missing"
function ExsarLogic.PetStateKey(state)
    state = state or {}
    if state.exists ~= true then return "missing" end
    if state.alive == true then return "alive" end
    return "dead"
end

-- True if a macro body is "just a single /cast" -- exactly one meaningful line
-- (ignoring blank lines and #directives like #showtooltip) and that line is a
-- /cast. Used to decide the hover tooltip: a simple-cast macro can show its
-- spell's tooltip, while a multi-action macro (extra /use, /startattack,
-- /targetenemy, ...) shows its macro text instead. Pure.
function ExsarLogic.IsSimpleCastMacro(macro)
    if not macro then return false end
    local count, isCast = 0, false
    for line in (macro .. "\n"):gmatch("(.-)\n") do
        local t = line:gsub("^%s*(.-)%s*$", "%1")
        if t ~= "" and t:sub(1, 1) ~= "#" then
            count = count + 1
            isCast = t:lower():match("^/cast%s") ~= nil
        end
    end
    return count == 1 and isCast
end

-- =========================================================
-- Raid debuff tracker (missing critical debuffs)
-- =========================================================

--- Determine which tracked raid debuffs are missing from the target.
-- A debuff counts as present if ANY of its alias aura names is on the target,
-- so a single entry (e.g. "Armor reduction") can be satisfied by several spells.
-- Disabled debuffs (per raid composition) are skipped entirely.
--
-- Optional caster matching: some entries (e.g. "Improved Faerie Fire") only
-- "count" when applied by a specific player, because the relevant property
-- (the +hit talent) is unreadable from the aura — the user supplies that
-- knowledge by designating the caster. When `requiredCasterFor(key)` returns a
-- GUID, an aura satisfies the entry only if its caster matches that GUID, OR
-- the caster is unknown (lenient: avoids false alarms when the API doesn't
-- report a caster). A present aura cast by a *known different* player does NOT
-- satisfy the entry.
--
-- @param tracked    array of { key, name, auras = { auraName, ... } }
-- @param isEnabled  function(key) -> bool  whether this debuff is tracked
-- @param present    table { [auraName] = v } of auras on the target, where v is:
--                     nil       — absent
--                     true      — present, caster unknown
--                     "<guid>"  — present, applied by this caster GUID
-- @param requiredCasterFor  optional function(key) -> req  where req is nil
--                           (no requirement), a single GUID string, or a set
--                           table `{ [guid] = true }` of acceptable casters
--                           (e.g. several specced druids).
-- @return array of the missing tracked entries, in input order
function ExsarLogic.ComputeMissingDebuffs(tracked, isEnabled, present, requiredCasterFor)
    local missing = {}
    for _, st in ipairs(ExsarLogic.ComputeDebuffStatus(tracked, isEnabled, present, requiredCasterFor)) do
        if not st.satisfied then missing[#missing + 1] = st.def end
    end
    return missing
end

--- Compute the present/missing status of every enabled tracked debuff. Pure.
-- The combined-panel generalization of ComputeMissingDebuffs: it returns one
-- entry per ENABLED tracked debuff (in input order), flagging whether the entry
-- is satisfied (any of its alias auras present and cast by an accepted caster)
-- and, if so, WHICH alias aura satisfied it — so the caller can look up that
-- aura's live duration/expiration to drive a timer bar. Disabled debuffs are
-- skipped. Caster-matching rules are identical to ComputeMissingDebuffs.
-- @param tracked    array of { key, name, auras = { auraName, ... } }
-- @param isEnabled  function(key) -> bool
-- @param present    table { [auraName] = true | "<guid>" } of auras on the target
-- @param requiredCasterFor  optional function(key) -> req (nil / guid / set)
-- @return array of { def = <tracked entry>, key, satisfied = bool, aura = name|nil }
function ExsarLogic.ComputeDebuffStatus(tracked, isEnabled, present, requiredCasterFor)
    -- Does a present aura's caster `p` satisfy the requirement `req`?
    local function casterOk(req, p)
        if not req then return true end       -- no caster requirement
        if p == true then return true end     -- present, caster unknown → lenient
        if type(req) == "table" then return req[p] == true end
        return p == req
    end

    local out = {}
    present = present or {}
    for _, d in ipairs(tracked or {}) do
        if isEnabled(d.key) then
            local req = requiredCasterFor and requiredCasterFor(d.key) or nil
            local satisfied, satAura = false, nil
            for _, aura in ipairs(d.auras or {}) do
                local p = present[aura]
                if p ~= nil and casterOk(req, p) then
                    satisfied, satAura = true, aura
                    break
                end
            end
            out[#out + 1] = { def = d, key = d.key, satisfied = satisfied, aura = satAura }
        end
    end
    return out
end

--- Color for a draining debuff-timer bar, by fraction of duration remaining.
-- Blue while plenty of time is left, yellow as it crosses half, orange when it
-- is about to fall off — a refresh-urgency cue. Thresholds match the spec:
-- 50% → yellow, 20% → orange. With no/zero duration (permanent debuff, or the
-- client not reporting a timer) it returns blue (treated as full).
-- @param remaining  seconds left (may be nil)
-- @param duration   total duration in seconds (nil/<=0 → treated as full)
-- @return r, g, b
function ExsarLogic.DebuffBarColor(remaining, duration)
    if not duration or duration <= 0 then
        return 0.25, 0.55, 0.95   -- no timing → full (blue)
    end
    local frac = (remaining or 0) / duration
    if frac > 0.5 then
        return 0.25, 0.55, 0.95   -- blue
    elseif frac > 0.2 then
        return 0.95, 0.85, 0.15   -- yellow
    else
        return 1.00, 0.50, 0.10   -- orange
    end
end

--- Find the rank of a named talent in an inspected talent list. Pure.
-- Used by RaidDebuffTracker to confirm a druid is specced into Improved Faerie
-- Fire from inspect data (the +hit talent is otherwise unreadable from auras).
-- @param talents  array of { name = string, rank = number }
-- @param name     exact talent name to look for
-- @return number  the rank (0 if not present)
function ExsarLogic.FindTalentRank(talents, name)
    for _, t in ipairs(talents or {}) do
        if t.name == name then return t.rank or 0 end
    end
    return 0
end

--- Decide whether the raid-debuff tracker frame should be visible.
-- The combined panel always requires the feature enabled and a target (a target
-- is needed to scan for debuffs at all). The combat and raid requirements are
-- each independently relaxable via config: `showOutOfCombat` waives the in-combat
-- requirement, `showOutOfRaid` waives the in-raid requirement (both default off,
-- so the default behavior is the original combat + raid + target gating). When
-- unlocked (config preview) it always shows so the user can position it.
-- @param o table { enabled, inCombat, inRaid, hasTarget,
--                  showOutOfCombat, showOutOfRaid, unlocked }
-- @return bool
function ExsarLogic.RaidDebuffsShouldShow(o)
    o = o or {}
    if o.unlocked then return true end
    if o.enabled ~= true then return false end
    if o.hasTarget ~= true then return false end
    if o.inCombat ~= true and o.showOutOfCombat ~= true then return false end
    if o.inRaid ~= true and o.showOutOfRaid ~= true then return false end
    return true
end

--- Choose which raid/party members the assist widget should track and show.
-- Returns the UNION of (a) members flagged as tanks (role == "TANK", from
-- UnitGroupRolesAssigned / Main Tank assignment) and (b) members whose name is
-- in the manual tracked-name set -- so auto-detected tanks and manually added
-- members both appear. Order follows the roster (display order); a member who
-- is both a tank and in the manual set appears once.
-- @param roster array of { name=, role=, unit=, online= } (unit = the assist
--               token, e.g. "raid3target"; role is "TANK" for tanks; online optional)
-- @param manualSet table mapping lowercased name -> true (optional)
-- @return array of the selected roster entries, in input order
function ExsarLogic.ComputeAssistList(roster, manualSet)
    roster = roster or {}
    manualSet = manualSet or {}
    local out = {}
    local seen = {}
    for _, m in ipairs(roster) do
        local n = m.name and string.lower(m.name)
        local include = (m.role == "TANK") or (n and manualSet[n] and true) or false
        if include and not (n and seen[n]) then
            out[#out + 1] = m
            if n then seen[n] = true end
        end
    end
    return out
end

--- Parse a free-text list of tank names (comma / whitespace separated) into a
-- lookup set keyed by lowercased name. Realm suffixes ("Name-Realm") are kept
-- as written; callers compare against the same form.
-- @param text string (may be nil/empty)
-- @return table mapping lowercased name -> true (empty when no names)
function ExsarLogic.ParseNameSet(text)
    local set = {}
    if not text then return set end
    for token in string.gmatch(text, "[^%s,]+") do
        set[string.lower(token)] = true
    end
    return set
end

-- =========================================================
-- Devilsaur Prep state machine (pet management widget)
-- =========================================================

-- Classify the live state of the Devilsaur Tooth boss-prep workflow into a
-- single stage key so the widget can pick its macro + visuals without each
-- module embedding the decision tree. Pure.
--
--   "absent"            no Tooth equipped, none in bags — nothing to do
--   "bagged"            Tooth in bags, not equipped — click 1: equip it
--   "equipped_unused"   Tooth equipped, buff not on pet — click 2: /use + swap
--                       (yellow "use me!" highlight)
--   "equipped_buffed"   Tooth equipped AND buff on pet — the /equipslot half of
--                       click 2 failed (or hasn't fired). Red "unequip!" warning
--                       — manual swap needed
--   "buffed_unequipped" Tooth back in bags AND buff still ticking on pet — the
--                       happy outcome; no highlight, no work owed
--
-- @param equippedId  number|nil  item id currently in the trinket slot
-- @param buffOnPet   bool        is the buff active on the player's pet
-- @param hasInBags   bool        is at least one Tooth carried in bags
-- @param toothId     number      Devilsaur Tooth item id (passed for testability)
function ExsarLogic.DevilsaurStage(equippedId, buffOnPet, hasInBags, toothId)
    local equipped = equippedId == toothId
    if equipped and buffOnPet then return "equipped_buffed" end
    if equipped then return "equipped_unused" end
    if buffOnPet then return "buffed_unequipped" end
    if hasInBags then return "bagged" end
    return "absent"
end

-- =========================================================
-- Melee weave helper + auto-shot monitor
-- =========================================================

--- Compute a haste-adjusted cast time from a base cast and the ranged speeds.
-- Ranged casts (Steady Shot, etc.) are shortened by ranged haste; the haste
-- multiplier is baseSpeed/hastedSpeed (since hastedSpeed = baseSpeed/haste), so
-- the hasted cast = baseCast * hastedSpeed / baseSpeed. Falls back to baseCast
-- when the speeds are unknown. Pure.
-- @param baseCast     unhasted cast time (e.g. 1.5 for Steady Shot)
-- @param hastedSpeed  current hasted ranged weapon speed (UnitRangedDamage)
-- @param baseSpeed    base (unhasted) ranged weapon speed
-- @return number  hasted cast time in seconds
function ExsarLogic.HastedCastTime(baseCast, hastedSpeed, baseSpeed)
    if not baseSpeed or baseSpeed <= 0 or not hastedSpeed or hastedSpeed <= 0 then
        return baseCast
    end
    return baseCast * hastedSpeed / baseSpeed
end

--- Decide whether the "WEAVE NOW" cue should show, and how long its window lasts.
-- Condition-based (not rotation-based). Weave when it won't cost a shot and
-- won't clip the next auto:
--   * melee swing ready (a step-in actually produces a white swing),
--   * not mid-cast (moving cancels a Steady/Aimed cast — never cue then),
--   * enough time before the next auto to weave (timeToAuto > weaveCost), and
--   * there is no room to fit a shot before the auto, ACCOUNTING for the GCD
--     lockout: (timeToAuto - gcdRemaining) < steadyCastTime.
-- Subtracting the remaining GCD is the precise form of the old "on GCD OR no
-- room" rule. It still lights the cue in the GCD gap after an instant
-- Arcane/Multi (you're locked out of casting and the leftover won't fit a
-- Steady) and in the fast auto-auto gap, but NOT at the very start of a fresh
-- auto cycle while the previous shot's GCD tail is still draining — there a full
-- Steady still fits, so you should cast it, not weave (that was the "cue flashes
-- for an instant right after the auto" case). The window countdown self-scales
-- with haste for free.
-- @param o table {
--   meleeReady, casting  (booleans),
--   timeToAuto     number|nil  seconds until the next auto is due (nil = no cycle),
--   gcdRemaining   number      seconds left on the GCD (0 if not on GCD),
--   weaveCost      number      step-in+swing+step-out budget (window lower bound),
--   steadyCastTime number      hasted Steady cast — the "can I fit a shot?" bar }
-- @return show (bool), windowRemaining (seconds left to START the weave; 0 when hidden)
function ExsarLogic.WeaveNowState(o)
    o = o or {}
    if not o.meleeReady then return false, 0 end
    if o.casting then return false, 0 end
    local tta = o.timeToAuto
    if not tta then return false, 0 end
    local weaveCost = o.weaveCost or 0.4
    if tta <= weaveCost then return false, 0 end
    local gcdRem = o.gcdRemaining or 0
    if gcdRem < 0 then gcdRem = 0 end
    local roomForShot = (tta - gcdRem) >= (o.steadyCastTime or 1.5)
    if roomForShot then return false, 0 end
    return true, tta - weaveCost
end

--- Anti-flicker hold for a binary cue. Once the raw condition turns on, keep the
-- cue shown for at least minOnTime seconds so jittery inputs near a boundary
-- (predicted auto-due, GCD edges, cast start/stop all carry event latency) can't
-- strobe it. The cue is meant to read as a stable "window open" state, not a
-- twitching light. Pure — the caller threads holdUntil back in each frame.
-- @param rawOn      bool    the instantaneous condition this frame
-- @param now        number  GetTime()
-- @param holdUntil  number  previous returned hold-until timestamp (0/nil = none)
-- @param minOnTime  number  minimum seconds to keep the cue on after raw goes off
-- @return shown (bool), newHoldUntil (number)
function ExsarLogic.HoldCue(rawOn, now, holdUntil, minOnTime)
    holdUntil = holdUntil or 0
    if rawOn then
        return true, now + (minOnTime or 0)
    end
    if now < holdUntil then
        return true, holdUntil
    end
    return false, holdUntil
end

--- Whether the "REACTIVATE AUTO!" alarm should show. Pure.
-- Fires when autos physically COULD fire at the target (Auto Shot reports in
-- range — 1 means past the 5yd dead zone and within shooting range) but
-- auto-repeat is currently OFF: i.e. you disabled or forgot your auto shot.
-- Keyed on auto-repeat being off (not on "overdue") so it does not false-alarm
-- while kiting with auto-repeat still on (autos merely delayed, not disabled).
-- @param autoShotInRange  IsSpellInRange("Auto Shot", "target"): 1 / 0 / nil
-- @param autoRepeatOn     bool  auto-repeat currently toggled on
-- @param hasTarget        bool  an attackable target exists
-- @return bool
function ExsarLogic.ShouldReactivateAuto(autoShotInRange, autoRepeatOn, hasTarget)
    if not hasTarget then return false end
    if autoRepeatOn then return false end
    return autoShotInRange == 1
end

-- Set global for WoW (loaded before Core.lua, so ExsarAddon doesn't exist yet).
-- Tests use require() which also gets the return value.
_G.ExsarLogic = ExsarLogic

return ExsarLogic
