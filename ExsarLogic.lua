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

-- Set global for WoW (loaded before Core.lua, so ExsarAddon doesn't exist yet).
-- Tests use require() which also gets the return value.
_G.ExsarLogic = ExsarLogic

return ExsarLogic
