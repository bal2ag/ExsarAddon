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

--- Given an effective (hasted) weapon speed, suggest a rotation string.
-- Boundaries: >1.83 → "5:5:1:1", [1.22,1.83] → "1:1", (0.83,1.22) → "2:3", ≤0.83 → "1:2"
function ExsarLogic.SuggestRotation(effectiveSpeed)
    if effectiveSpeed > 1.83 then
        return "5:5:1:1"
    elseif effectiveSpeed >= 1.22 then
        return "1:1"
    elseif effectiveSpeed > 0.83 then
        return "2:3"
    else
        return "1:2"
    end
end

-- Set global for WoW (loaded before Core.lua, so ExsarAddon doesn't exist yet).
-- Tests use require() which also gets the return value.
_G.ExsarLogic = ExsarLogic

return ExsarLogic
