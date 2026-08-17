-- tests/test_logic.lua
-- Unit tests for ExsarLogic pure functions.

package.path = package.path .. ";../?.lua"
local Logic = require("ExsarLogic")

-- Helper: compare floats with tolerance
local function approx(a, b, tol)
    tol = tol or 0.001
    return math.abs(a - b) < tol
end

-- =========================================================
-- FormatCooldown
-- =========================================================

describe("FormatCooldown", function()
    it("formats >= 60s as minutes (rounded up)", function()
        assert.are.equal("1m", Logic.FormatCooldown(60))
        assert.are.equal("2m", Logic.FormatCooldown(61))
        assert.are.equal("5m", Logic.FormatCooldown(300))
        assert.are.equal("2m", Logic.FormatCooldown(119))
        assert.are.equal("2m", Logic.FormatCooldown(120))
    end)

    it("formats 10-59s as whole seconds (rounded up)", function()
        assert.are.equal("10", Logic.FormatCooldown(10))
        assert.are.equal("59", Logic.FormatCooldown(59))
        assert.are.equal("11", Logic.FormatCooldown(10.1))
        assert.are.equal("45", Logic.FormatCooldown(45))
    end)

    it("formats < 10s with one decimal", function()
        assert.are.equal("9.9", Logic.FormatCooldown(9.9))
        assert.are.equal("3.2", Logic.FormatCooldown(3.2))
        assert.are.equal("0.5", Logic.FormatCooldown(0.5))
        assert.are.equal("0.1", Logic.FormatCooldown(0.1))
    end)

    it("handles boundary at exactly 10", function()
        assert.are.equal("10", Logic.FormatCooldown(10))
    end)

    it("handles boundary just under 10", function()
        assert.are.equal("10.0", Logic.FormatCooldown(9.99))
    end)

    it("rounds up correctly at minute boundary", function()
        assert.are.equal("2m", Logic.FormatCooldown(60.1))
        assert.are.equal("2m", Logic.FormatCooldown(60.5))
    end)
end)

-- =========================================================
-- FormatShortTimer
-- =========================================================

describe("FormatShortTimer", function()
    it("formats >= 10s as whole seconds (rounded up)", function()
        assert.are.equal("10", Logic.FormatShortTimer(10))
        assert.are.equal("15", Logic.FormatShortTimer(14.2))
        assert.are.equal("60", Logic.FormatShortTimer(60))
    end)

    it("formats < 10s with one decimal", function()
        assert.are.equal("9.9", Logic.FormatShortTimer(9.9))
        assert.are.equal("3.2", Logic.FormatShortTimer(3.2))
        assert.are.equal("0.5", Logic.FormatShortTimer(0.5))
    end)

    it("handles boundary at exactly 10", function()
        assert.are.equal("10", Logic.FormatShortTimer(10))
    end)

    it("handles very large values (no minute tier)", function()
        assert.are.equal("300", Logic.FormatShortTimer(300))
    end)
end)

-- =========================================================
-- FormatNumber
-- =========================================================

describe("FormatNumber", function()
    it("formats >= 1000 with k suffix", function()
        assert.are.equal("1.0k", Logic.FormatNumber(1000))
        assert.are.equal("1.5k", Logic.FormatNumber(1500))
        assert.are.equal("10.0k", Logic.FormatNumber(10000))
        assert.are.equal("100.0k", Logic.FormatNumber(100000))
    end)

    it("returns plain string for < 1000", function()
        assert.are.equal("999", Logic.FormatNumber(999))
        assert.are.equal("0", Logic.FormatNumber(0))
        assert.are.equal("1", Logic.FormatNumber(1))
        assert.are.equal("500", Logic.FormatNumber(500))
    end)

    it("handles exact boundary", function()
        assert.are.equal("1.0k", Logic.FormatNumber(1000))
        assert.are.equal("999", Logic.FormatNumber(999))
    end)
end)

-- =========================================================
-- HealthColorGradient
-- =========================================================

describe("HealthColorGradient", function()
    it("returns green at 100%", function()
        local r, g, b = Logic.HealthColorGradient(100)
        assert.is_true(approx(r, 0.1))
        assert.is_true(approx(g, 0.9))
        assert.is_true(approx(b, 0.1))
    end)

    it("returns yellow at 50%", function()
        local r, g, b = Logic.HealthColorGradient(50)
        assert.is_true(approx(r, 0.9))
        assert.is_true(approx(g, 0.9))
        assert.is_true(approx(b, 0.1))
    end)

    it("returns red at 0%", function()
        local r, g, b = Logic.HealthColorGradient(0)
        assert.is_true(approx(r, 0.9))
        assert.is_true(approx(g, 0.0))
        assert.is_true(approx(b, 0.1))
    end)

    it("interpolates smoothly at 75%", function()
        local r, g, b = Logic.HealthColorGradient(75)
        assert.is_true(approx(r, 0.55))
        assert.is_true(approx(g, 0.9))
        assert.is_true(approx(b, 0.1))
    end)

    it("interpolates at 25%", function()
        local r, g, b = Logic.HealthColorGradient(25)
        assert.is_true(approx(r, 0.9))
        assert.is_true(approx(g, 0.45))
        assert.is_true(approx(b, 0.1))
    end)

    it("green component is always 0.9 above 50%", function()
        for pct = 51, 100 do
            local _, g = Logic.HealthColorGradient(pct)
            assert.is_true(approx(g, 0.9))
        end
    end)
end)

-- =========================================================
-- HealthColorThreshold
-- =========================================================

describe("HealthColorThreshold", function()
    it("returns green above 50%", function()
        local r, g, b = Logic.HealthColorThreshold(51)
        assert.are.equal(0.20, r)
        assert.are.equal(0.75, g)
        assert.are.equal(0.20, b)
    end)

    it("returns yellow at 50%", function()
        local r, g, b = Logic.HealthColorThreshold(50)
        assert.are.equal(0.90, r)
        assert.are.equal(0.90, g)
        assert.are.equal(0.10, b)
    end)

    it("returns yellow at 21%", function()
        local r, g, b = Logic.HealthColorThreshold(21)
        assert.are.equal(0.90, r)
        assert.are.equal(0.90, g)
        assert.are.equal(0.10, b)
    end)

    it("returns red at 20%", function()
        local r, g, b = Logic.HealthColorThreshold(20)
        assert.are.equal(0.80, r)
        assert.are.equal(0.15, g)
        assert.are.equal(0.15, b)
    end)

    it("returns red at 0%", function()
        local r, g, b = Logic.HealthColorThreshold(0)
        assert.are.equal(0.80, r)
        assert.are.equal(0.15, g)
        assert.are.equal(0.15, b)
    end)

    it("returns green at 100%", function()
        local r, g, b = Logic.HealthColorThreshold(100)
        assert.are.equal(0.20, r)
        assert.are.equal(0.75, g)
        assert.are.equal(0.20, b)
    end)
end)

-- =========================================================
-- LevelColor
-- =========================================================

describe("LevelColor", function()
    local playerLevel = 70

    it("returns purple for skull (-1)", function()
        local r, g, b, a = Logic.LevelColor(-1, playerLevel)
        assert.are.equal(0.80, r)
        assert.are.equal(0.30, g)
        assert.are.equal(0.80, b)
        assert.are.equal(1, a)
    end)

    it("returns red for +5 or more", function()
        local r, g, b = Logic.LevelColor(75, playerLevel)
        assert.are.equal(1.00, r)
        assert.are.equal(0.10, g)
        assert.are.equal(0.10, b)
    end)

    it("returns red for +10", function()
        local r, g, b = Logic.LevelColor(80, playerLevel)
        assert.are.equal(1.00, r)
        assert.are.equal(0.10, g)
    end)

    it("returns orange for +3 to +4", function()
        local r, g, b = Logic.LevelColor(73, playerLevel)
        assert.are.equal(1.00, r)
        assert.are.equal(0.50, g)
        assert.are.equal(0.25, b)

        r, g, b = Logic.LevelColor(74, playerLevel)
        assert.are.equal(1.00, r)
        assert.are.equal(0.50, g)
    end)

    it("returns yellow for -2 to +2", function()
        assert.are.equal(1.00, (Logic.LevelColor(70, playerLevel)))
        assert.are.equal(1.00, (Logic.LevelColor(68, playerLevel)))
        assert.are.equal(1.00, (Logic.LevelColor(72, playerLevel)))
    end)

    it("returns green for -4 to -3", function()
        local r, g, b = Logic.LevelColor(67, playerLevel)
        assert.are.equal(0.25, r)
        assert.are.equal(0.75, g)
        assert.are.equal(0.25, b)

        r, g, b = Logic.LevelColor(66, playerLevel)
        assert.are.equal(0.25, r)
    end)

    it("returns grey for -5 or less", function()
        local r, g, b = Logic.LevelColor(65, playerLevel)
        assert.are.equal(0.55, r)
        assert.are.equal(0.55, g)
        assert.are.equal(0.55, b)

        r, g, b = Logic.LevelColor(1, playerLevel)
        assert.are.equal(0.55, r)
    end)

    it("works with different player levels", function()
        -- Level 60 player vs level 65 target = +5 = red
        local r = Logic.LevelColor(65, 60)
        assert.are.equal(1.00, r)

        -- Level 60 player vs level 60 target = 0 = yellow
        r = Logic.LevelColor(60, 60)
        assert.are.equal(1.00, r)
    end)
end)

-- =========================================================
-- CooldownState
-- =========================================================

describe("CooldownState", function()
    it("returns 'cooldown' when duration > 1.6", function()
        assert.are.equal("cooldown", Logic.CooldownState(100, 10))
        assert.are.equal("cooldown", Logic.CooldownState(100, 60))
        assert.are.equal("cooldown", Logic.CooldownState(1, 2))
    end)

    it("returns 'gcd' when duration > 0 but <= 1.6", function()
        assert.are.equal("gcd", Logic.CooldownState(100, 1.5))
        assert.are.equal("gcd", Logic.CooldownState(100, 0.5))
        assert.are.equal("gcd", Logic.CooldownState(100, 0.01))
    end)

    it("returns 'ready' when start is 0", function()
        assert.are.equal("ready", Logic.CooldownState(0, 0))
    end)

    it("returns 'ready' when start is nil", function()
        assert.are.equal("ready", Logic.CooldownState(nil, nil))
    end)

    it("returns 'ready' when duration is nil", function()
        assert.are.equal("ready", Logic.CooldownState(100, nil))
    end)

    it("handles exactly 1.6 as GCD (not cooldown)", function()
        assert.are.equal("gcd", Logic.CooldownState(100, 1.6))
    end)

    it("handles just above 1.6 as cooldown", function()
        assert.are.equal("cooldown", Logic.CooldownState(100, 1.601))
    end)

    it("MIN_COOLDOWN_DURATION is 1.6", function()
        assert.are.equal(1.6, Logic.MIN_COOLDOWN_DURATION)
    end)
end)

-- =========================================================
-- TrinketScanState
-- =========================================================

describe("TrinketScanState", function()
    it("returns 'empty' when slot has no item", function()
        assert.are.equal("empty", Logic.TrinketScanState(nil, nil, true))
        assert.are.equal("empty", Logic.TrinketScanState(0, nil, true))
    end)

    it("returns 'known' when the item has an on-use spell", function()
        assert.are.equal("known", Logic.TrinketScanState(12345, "Some Use Effect", true))
    end)

    it("returns 'known' even if cache probe reads uncached (spell already known)", function()
        assert.are.equal("known", Logic.TrinketScanState(12345, "Some Use Effect", false))
    end)

    it("returns 'pending' when item is equipped but data not cached", function()
        -- transient after taxi / zoning: GetItemSpell nil purely because uncached
        assert.are.equal("pending", Logic.TrinketScanState(12345, nil, false))
    end)

    it("returns 'empty' for a cached passive trinket (no use effect)", function()
        assert.are.equal("empty", Logic.TrinketScanState(12345, nil, true))
    end)
end)

-- =========================================================
-- CooldownRemaining
-- =========================================================

describe("CooldownRemaining", function()
    it("calculates remaining time", function()
        assert.are.equal(5, Logic.CooldownRemaining(100, 10, 105))
    end)

    it("returns 0 when expired", function()
        assert.are.equal(0, Logic.CooldownRemaining(100, 10, 111))
    end)

    it("returns 0 when exactly expired", function()
        assert.are.equal(0, Logic.CooldownRemaining(100, 10, 110))
    end)

    it("returns 0 for nil inputs", function()
        assert.are.equal(0, Logic.CooldownRemaining(nil, nil, 100))
    end)

    it("returns full duration at start", function()
        assert.are.equal(10, Logic.CooldownRemaining(100, 10, 100))
    end)

    it("returns partial time mid-cooldown", function()
        assert.is_true(approx(3.5, Logic.CooldownRemaining(100, 10, 106.5)))
    end)

    it("handles start=nil duration=non-nil", function()
        assert.are.equal(0, Logic.CooldownRemaining(nil, 10, 100))
    end)
end)

-- =========================================================
-- CalcStripWidth
-- =========================================================

describe("CalcStripWidth", function()
    local iconSize = 32
    local iconGap = 4
    local groupGap = 10
    local padding = 8

    it("calculates width for a single group of 3 visible icons", function()
        local groups = {
            { {known=true}, {known=true}, {known=true} },
        }
        -- padding + 3*32 + 2*4 + padding = 8 + 96 + 8 + 8 = 120
        assert.are.equal(120, Logic.CalcStripWidth(groups, iconSize, iconGap, groupGap, padding))
    end)

    it("calculates width for two groups", function()
        local groups = {
            { {known=true}, {known=true} },
            { {known=true} },
        }
        -- padding + 2*32 + 1*4 + groupGap + 1*32 + padding = 8 + 64 + 4 + 10 + 32 + 8 = 126
        assert.are.equal(126, Logic.CalcStripWidth(groups, iconSize, iconGap, groupGap, padding))
    end)

    it("skips hidden spells", function()
        local groups = {
            { {known=true}, {known=false}, {known=true} },
        }
        -- padding + 2*32 + 1*4 + padding = 8 + 64 + 4 + 8 = 84
        assert.are.equal(84, Logic.CalcStripWidth(groups, iconSize, iconGap, groupGap, padding))
    end)

    it("skips entirely hidden groups (no gap added)", function()
        local groups = {
            { {known=true} },
            { {known=false}, {known=false} },
            { {known=true} },
        }
        -- padding + 32 + groupGap + 32 + padding = 8 + 32 + 10 + 32 + 8 = 90
        assert.are.equal(90, Logic.CalcStripWidth(groups, iconSize, iconGap, groupGap, padding))
    end)

    it("returns double padding when nothing visible", function()
        local groups = {
            { {known=false} },
        }
        assert.are.equal(16, Logic.CalcStripWidth(groups, iconSize, iconGap, groupGap, padding))
    end)

    it("handles empty groups list", function()
        assert.are.equal(16, Logic.CalcStripWidth({}, iconSize, iconGap, groupGap, padding))
    end)

    it("handles single visible icon", function()
        local groups = { { {known=true} } }
        -- padding + 32 + padding = 8 + 32 + 8 = 48
        assert.are.equal(48, Logic.CalcStripWidth(groups, iconSize, iconGap, groupGap, padding))
    end)
end)

-- =========================================================
-- CalcFlatStripSize
-- =========================================================

describe("CalcFlatStripSize", function()
    it("calculates width for visible icons", function()
        local w, h = Logic.CalcFlatStripSize(3, 29, 4, 6)
        -- 6 + 3*29 + 2*4 + 6 = 6 + 87 + 8 + 6 = 107
        assert.are.equal(107, w)
        assert.are.equal(41, h)  -- 29 + 6*2
    end)

    it("returns double padding when no icons", function()
        local w, h = Logic.CalcFlatStripSize(0, 29, 4, 6)
        assert.are.equal(12, w)
        assert.are.equal(41, h)
    end)

    it("handles single icon", function()
        local w, h = Logic.CalcFlatStripSize(1, 29, 4, 6)
        assert.are.equal(41, w)  -- 6 + 29 + 6
        assert.are.equal(41, h)
    end)

    it("handles large count", function()
        local w, h = Logic.CalcFlatStripSize(10, 29, 4, 6)
        -- 6 + 10*29 + 9*4 + 6 = 6 + 290 + 36 + 6 = 338
        assert.are.equal(338, w)
        assert.are.equal(41, h)  -- height is always iconSize + 2*padding
    end)
end)

-- =========================================================
-- CalcVerticalStripSize
-- =========================================================

describe("CalcVerticalStripSize", function()
    it("calculates height for visible icons", function()
        local w, h = Logic.CalcVerticalStripSize(3, 29, 4, 6)
        assert.are.equal(41, w)  -- 29 + 6*2
        -- 6 + 3*29 + 2*4 + 6 = 107
        assert.are.equal(107, h)
    end)

    it("returns double padding height when no icons", function()
        local w, h = Logic.CalcVerticalStripSize(0, 29, 4, 6)
        assert.are.equal(41, w)
        assert.are.equal(12, h)
    end)

    it("handles single icon", function()
        local w, h = Logic.CalcVerticalStripSize(1, 29, 4, 6)
        assert.are.equal(41, w)  -- 29 + 6*2
        assert.are.equal(41, h)  -- 6 + 29 + 6
    end)

    it("is transpose of CalcFlatStripSize", function()
        local fw, fh = Logic.CalcFlatStripSize(4, 29, 4, 6)
        local vw, vh = Logic.CalcVerticalStripSize(4, 29, 4, 6)
        assert.are.equal(fw, vh)  -- flat width == vertical height
        assert.are.equal(fh, vw)  -- flat height == vertical width
    end)
end)

-- =========================================================
-- ReticuleFraction
-- =========================================================

describe("ReticuleFraction", function()
    it("calculates fraction of half-width", function()
        assert.is_true(approx(0.5/2.8, Logic.ReticuleFraction(0.5, 2.8)))
    end)

    it("clamps to 0.98", function()
        assert.are.equal(0.98, Logic.ReticuleFraction(2.0, 1.0))
    end)

    it("returns 0 for zero speed", function()
        assert.are.equal(0, Logic.ReticuleFraction(0.5, 0))
    end)

    it("returns 0 for negative speed", function()
        assert.are.equal(0, Logic.ReticuleFraction(0.5, -1))
    end)

    it("handles typical hunter auto shot values", function()
        -- 2.8 speed bow, 0.6 aim window
        local frac = Logic.ReticuleFraction(0.6, 2.8)
        assert.is_true(approx(0.2143, frac))
    end)
end)

-- =========================================================
-- AutoShotDelay
-- =========================================================

describe("AutoShotDelay", function()
    -- Baseline: last shot at t=100, speed 2.8 → due at t=102.8

    it("returns nil with no cycle running", function()
        assert.is_nil(Logic.AutoShotDelay(100, 0, 2.8, 0))
        assert.is_nil(Logic.AutoShotDelay(100, nil, 2.8, 0))
    end)

    it("returns nil for zero or missing speed", function()
        assert.is_nil(Logic.AutoShotDelay(105, 100, 0, 0))
        assert.is_nil(Logic.AutoShotDelay(105, 100, nil, 0))
    end)

    it("returns nil mid-cycle with no cast", function()
        assert.is_nil(Logic.AutoShotDelay(101, 100, 2.8, 0))
    end)

    it("predicts clip when a cast ends past the due time", function()
        -- Cast ends at 103.3, shot due at 102.8 → 0.5 clip, known mid-cycle
        local delay, predicted = Logic.AutoShotDelay(101, 100, 2.8, 103.3)
        assert.is_true(approx(0.5, delay))
        assert.is_true(predicted)
    end)

    it("returns nil when the cast ends before the due time", function()
        assert.is_nil(Logic.AutoShotDelay(101, 100, 2.8, 102.0))
    end)

    it("applies the small predict grace to cast clips", function()
        -- 0.01 clip: under the 0.02 grace
        assert.is_nil(Logic.AutoShotDelay(101, 100, 2.8, 102.81))
        -- 0.03 clip: over it
        local delay = Logic.AutoShotDelay(101, 100, 2.8, 102.83)
        assert.is_true(approx(0.03, delay))
    end)

    it("keeps the predicted clip while the cast runs past due", function()
        -- now is already past due but the cast is still running
        local delay, predicted = Logic.AutoShotDelay(103.0, 100, 2.8, 103.3)
        assert.is_true(approx(0.5, delay))
        assert.is_true(predicted)
    end)

    it("grows the overdue delay live when no cast is running", function()
        local d1, p1 = Logic.AutoShotDelay(103.5, 100, 2.8, 0)
        local d2 = Logic.AutoShotDelay(104.5, 100, 2.8, 0)
        assert.is_true(approx(0.7, d1))
        assert.is_false(p1)
        assert.is_true(approx(1.7, d2))
    end)

    it("treats a finished cast as not casting", function()
        -- castEnd in the past: overdue regime, measured from now
        local delay, predicted = Logic.AutoShotDelay(104, 100, 2.8, 103)
        assert.is_true(approx(1.2, delay))
        assert.is_false(predicted)
    end)

    it("suppresses overdue readings within the latency grace", function()
        -- 0.15s past due: hidden (event latency makes every cycle read late)
        assert.is_nil(Logic.AutoShotDelay(102.95, 100, 2.8, 0))
        -- 0.25s past due: shown
        local delay = Logic.AutoShotDelay(103.05, 100, 2.8, 0)
        assert.is_true(approx(0.25, delay))
    end)

    it("honors custom grace thresholds", function()
        assert.is_nil(Logic.AutoShotDelay(103.05, 100, 2.8, 0, 0.02, 0.5))
        local delay = Logic.AutoShotDelay(103.05, 100, 2.8, 0, 0.02, 0.1)
        assert.is_true(approx(0.25, delay))
    end)
end)

-- =========================================================
-- AutoShotFiredDelay / ClipVerdict
-- =========================================================

describe("AutoShotFiredDelay", function()
    it("measures lateness against the cycle that just ended", function()
        -- previous shot at 100, speed 2.8 → due at 102.8, fired at 103.14
        assert.is_true(approx(0.34, Logic.AutoShotFiredDelay(103.14, 100, 2.8)))
    end)

    it("reads zero on an on-time shot", function()
        assert.equals(0, Logic.AutoShotFiredDelay(102.8, 100, 2.8))
    end)

    it("clamps an early shot to zero", function()
        -- a mid-cycle haste gain shortens the real cycle below the read speed
        assert.equals(0, Logic.AutoShotFiredDelay(102.5, 100, 2.8))
    end)

    it("returns nil with no cycle to measure against", function()
        assert.is_nil(Logic.AutoShotFiredDelay(103, 0, 2.8))
        assert.is_nil(Logic.AutoShotFiredDelay(103, nil, 2.8))
    end)

    it("returns nil for zero or missing speed", function()
        assert.is_nil(Logic.AutoShotFiredDelay(103, 100, 0))
        assert.is_nil(Logic.AutoShotFiredDelay(103, 100, nil))
    end)

    it("returns nil without a fire time", function()
        assert.is_nil(Logic.AutoShotFiredDelay(nil, 100, 2.8))
    end)
end)

describe("ClipVerdict", function()
    it("calls a clean cycle at or under the grace", function()
        assert.equals("clean", Logic.ClipVerdict(0, 0.1, 0.5))
        assert.equals("clean", Logic.ClipVerdict(0.1, 0.1, 0.5))
    end)

    it("calls a moderate clip", function()
        assert.equals("clip", Logic.ClipVerdict(0.34, 0.1, 0.5))
    end)

    it("calls a severe clip at or over the severe threshold", function()
        assert.equals("severe", Logic.ClipVerdict(0.5, 0.1, 0.5))
        assert.equals("severe", Logic.ClipVerdict(1.2, 0.1, 0.5))
    end)

    it("says nothing when there is no delay to score", function()
        assert.is_nil(Logic.ClipVerdict(nil, 0.1, 0.5))
    end)

    it("uses defaults when thresholds are omitted", function()
        assert.equals("clean", Logic.ClipVerdict(0.05))
        assert.equals("clip", Logic.ClipVerdict(0.3))
        assert.equals("severe", Logic.ClipVerdict(0.6))
    end)
end)

-- =========================================================
-- ShouldShowHoldWarning
-- =========================================================

describe("ShouldShowHoldWarning", function()
    it("shows while stationary, auto active, and before the cap", function()
        assert.is_true(Logic.ShouldShowHoldWarning(true, false, 100, 100.5))
    end)

    it("hidden when auto shot is off", function()
        assert.is_false(Logic.ShouldShowHoldWarning(false, false, 100, 100.5))
    end)

    it("hidden while moving (movement cancels the pending shot)", function()
        assert.is_false(Logic.ShouldShowHoldWarning(true, true, 100, 100.5))
    end)

    it("hidden once the safety cap is reached", function()
        assert.is_false(Logic.ShouldShowHoldWarning(true, false, 100.5, 100.5))
        assert.is_false(Logic.ShouldShowHoldWarning(true, false, 101, 100.5))
    end)

    it("hidden with no active hold (holdEnd nil or zero)", function()
        assert.is_false(Logic.ShouldShowHoldWarning(true, false, 100, nil))
        assert.is_false(Logic.ShouldShowHoldWarning(true, false, 100, 0))
    end)
end)

-- =========================================================
-- GridPosition
-- =========================================================

describe("GridPosition", function()
    it("first item is at (0, 0)", function()
        local col, row = Logic.GridPosition(1, 5)
        assert.are.equal(0, col)
        assert.are.equal(0, row)
    end)

    it("wraps to next row", function()
        local col, row = Logic.GridPosition(6, 5)
        assert.are.equal(0, col)
        assert.are.equal(1, row)
    end)

    it("handles middle of row", function()
        local col, row = Logic.GridPosition(3, 5)
        assert.are.equal(2, col)
        assert.are.equal(0, row)
    end)

    it("last item in first row", function()
        local col, row = Logic.GridPosition(5, 5)
        assert.are.equal(4, col)
        assert.are.equal(0, row)
    end)

    it("handles second row", function()
        local col, row = Logic.GridPosition(8, 5)
        assert.are.equal(2, col)
        assert.are.equal(1, row)
    end)

    it("handles 1 icon per row", function()
        local col, row = Logic.GridPosition(3, 1)
        assert.are.equal(0, col)
        assert.are.equal(2, row)
    end)
end)

-- =========================================================
-- IconsPerRow
-- =========================================================

describe("IconsPerRow", function()
    it("calculates icons that fit in a frame", function()
        -- frameWidth=200, padding=6 each side, iconSize=29, iconGap=4
        -- available = 200 - 12 + 4 = 192, each icon = 33, floor(192/33) = 5
        assert.are.equal(5, Logic.IconsPerRow(200, 6, 29, 4))
    end)

    it("returns at least 1", function()
        assert.are.equal(1, Logic.IconsPerRow(10, 6, 29, 4))
    end)

    it("exact fit", function()
        -- 2 icons: 6 + 29 + 4 + 29 + 6 = 74
        assert.are.equal(2, Logic.IconsPerRow(74, 6, 29, 4))
    end)

    it("one pixel short of fitting another icon", function()
        -- 74 fits 2 icons exactly; 73 should still be 2
        -- available = 73 - 12 + 4 = 65, each icon = 33, floor(65/33) = 1
        assert.are.equal(1, Logic.IconsPerRow(73, 6, 29, 4))
    end)

    it("handles zero gap", function()
        -- frameWidth=100, padding=5, iconSize=30, iconGap=0
        -- available = 100 - 10 + 0 = 90, each = 30, floor(90/30) = 3
        assert.are.equal(3, Logic.IconsPerRow(100, 5, 30, 0))
    end)

    it("handles large icons in small frame", function()
        assert.are.equal(1, Logic.IconsPerRow(50, 10, 100, 5))
    end)
end)

-- =========================================================
-- GridRowCount
-- =========================================================

describe("GridRowCount", function()
    it("calculates rows needed", function()
        assert.are.equal(1, Logic.GridRowCount(3, 5))
        assert.are.equal(2, Logic.GridRowCount(6, 5))
        assert.are.equal(2, Logic.GridRowCount(10, 5))
        assert.are.equal(3, Logic.GridRowCount(11, 5))
    end)

    it("returns 0 for no items", function()
        assert.are.equal(0, Logic.GridRowCount(0, 5))
    end)

    it("handles exact multiple", function()
        assert.are.equal(2, Logic.GridRowCount(10, 5))
    end)

    it("handles single item", function()
        assert.are.equal(1, Logic.GridRowCount(1, 5))
    end)

    it("handles 1 icon per row", function()
        assert.are.equal(4, Logic.GridRowCount(4, 1))
    end)

    it("handles negative count", function()
        assert.are.equal(0, Logic.GridRowCount(-1, 5))
    end)
end)

-- =========================================================
-- PulseAlpha
-- =========================================================

describe("PulseAlpha", function()
    it("returns midpoint at time 0", function()
        local alpha = Logic.PulseAlpha(0, 0.8, 0.65, 1.0)
        assert.is_true(approx(0.825, alpha))
    end)

    it("reaches max at quarter period", function()
        local freq = 0.8
        local t = 1 / (4 * freq)
        local alpha = Logic.PulseAlpha(t, freq, 0.65, 1.0)
        assert.is_true(approx(1.0, alpha))
    end)

    it("reaches min at three-quarter period", function()
        local freq = 0.8
        local t = 3 / (4 * freq)
        local alpha = Logic.PulseAlpha(t, freq, 0.65, 1.0)
        assert.is_true(approx(0.65, alpha))
    end)

    it("stays within bounds", function()
        for i = 0, 100 do
            local t = i * 0.1
            local alpha = Logic.PulseAlpha(t, 0.8, 0.65, 1.0)
            assert.is_true(alpha >= 0.65 - 0.001)
            assert.is_true(alpha <= 1.0 + 0.001)
        end
    end)

    it("works with different min/max ranges", function()
        local alpha = Logic.PulseAlpha(0, 1.0, 0.5, 0.85)
        assert.is_true(approx(0.675, alpha))
    end)
end)

-- =========================================================
-- MarchingAntAlpha
-- =========================================================

describe("MarchingAntAlpha", function()
    it("returns full alpha at head position", function()
        local alpha = Logic.MarchingAntAlpha(5, 5, 16, 5)
        assert.is_true(approx(1.0, alpha))
    end)

    it("returns 0 for dashes outside tail", function()
        local alpha = Logic.MarchingAntAlpha(0, 10, 16, 5)
        assert.are.equal(0, alpha)
    end)

    it("fades within tail", function()
        -- dash 1 behind head: dist=1, tailLen=5
        local alpha = Logic.MarchingAntAlpha(4, 5, 16, 5)
        assert.is_true(approx(1.0 - (1/5)*0.85, alpha))
    end)

    it("wraps around correctly", function()
        -- head at 2, dash at 15, dashCount=16 → dist = (2-15+16) % 16 = 3
        local alpha = Logic.MarchingAntAlpha(15, 2, 16, 5)
        assert.is_true(approx(1.0 - (3/5)*0.85, alpha))
    end)

    it("last dash in tail has minimum alpha", function()
        -- dist = tailLen - 1 (just barely in tail)
        local alpha = Logic.MarchingAntAlpha(1, 5, 16, 5)
        -- dist = 4
        assert.is_true(approx(1.0 - (4/5)*0.85, alpha))
    end)
end)

-- =========================================================
-- MarchingAntHead
-- =========================================================

describe("MarchingAntHead", function()
    it("returns 0 at time 0", function()
        assert.are.equal(0, Logic.MarchingAntHead(0, 1.5, 16))
    end)

    it("wraps at dashCount", function()
        -- speed=1.5, dashCount=16: one full cycle in 1/1.5 seconds
        local head = Logic.MarchingAntHead(1/1.5, 1.5, 16)
        assert.is_true(approx(0, head, 0.01))
    end)

    it("progresses linearly", function()
        local head = Logic.MarchingAntHead(0.5, 1.5, 16)
        -- 0.5 * 1.5 * 16 = 12
        assert.is_true(approx(12, head))
    end)

    it("stays within 0 to dashCount", function()
        for i = 0, 200 do
            local t = i * 0.1
            local head = Logic.MarchingAntHead(t, 1.5, 16)
            assert.is_true(head >= 0)
            assert.is_true(head < 16)
        end
    end)

    it("works with different dash counts", function()
        local head = Logic.MarchingAntHead(1.0, 1.0, 8)
        -- 1.0 * 1.0 * 8 = 8, mod 8 = 0
        assert.is_true(approx(0, head, 0.01))
    end)
end)

-- =========================================================
-- CalcAnchorOffset
-- =========================================================

describe("CalcAnchorOffset", function()
    it("returns center offset for centered frame", function()
        -- Frame at center of 1920x1080 screen, scale 1.0
        local ax, ay = Logic.CalcAnchorOffset(960 - 50, 540 + 50, 1.0, 1920, 1080)
        -- anchorX = (960-50) - 1920/(2*1) = 910 - 960 = -50
        -- anchorY = (540+50) - 1080/(2*1) = 590 - 540 = 50
        assert.is_true(approx(-50, ax))
        assert.is_true(approx(50, ay))
    end)

    it("accounts for scale", function()
        local ax, ay = Logic.CalcAnchorOffset(100, 500, 2.0, 1920, 1080)
        -- anchorX = 100 - 1920/4 = 100 - 480 = -380
        -- anchorY = 500 - 1080/4 = 500 - 270 = 230
        assert.is_true(approx(-380, ax))
        assert.is_true(approx(230, ay))
    end)

    it("returns 0,0 when frame is at exact center offset", function()
        local ax, ay = Logic.CalcAnchorOffset(960, 540, 1.0, 1920, 1080)
        assert.is_true(approx(0, ax))
        assert.is_true(approx(0, ay))
    end)

    it("handles top-left corner", function()
        local ax, ay = Logic.CalcAnchorOffset(0, 1080, 1.0, 1920, 1080)
        -- anchorX = 0 - 960 = -960
        -- anchorY = 1080 - 540 = 540
        assert.is_true(approx(-960, ax))
        assert.is_true(approx(540, ay))
    end)

    it("handles fractional scale", function()
        local ax, ay = Logic.CalcAnchorOffset(200, 800, 0.5, 1920, 1080)
        -- anchorX = 200 - 1920/(2*0.5) = 200 - 1920 = -1720
        -- anchorY = 800 - 1080/(2*0.5) = 800 - 1080 = -280
        assert.is_true(approx(-1720, ax))
        assert.is_true(approx(-280, ay))
    end)
end)

-- =========================================================
-- RoundScale
-- =========================================================

describe("RoundScale", function()
    it("rounds to nearest 0.05", function()
        assert.is_true(approx(1.0, Logic.RoundScale(1.0)))
        assert.is_true(approx(1.05, Logic.RoundScale(1.06)))
        assert.is_true(approx(1.05, Logic.RoundScale(1.07)))
        assert.is_true(approx(1.10, Logic.RoundScale(1.08)))
        assert.is_true(approx(0.50, Logic.RoundScale(0.5)))
        assert.is_true(approx(2.00, Logic.RoundScale(2.0)))
    end)

    it("rounds 0.52 to 0.50", function()
        assert.is_true(approx(0.50, Logic.RoundScale(0.52)))
    end)

    it("rounds 0.53 to 0.55", function()
        assert.is_true(approx(0.55, Logic.RoundScale(0.53)))
    end)

    it("rounds 1.425 to 1.45", function()
        assert.is_true(approx(1.45, Logic.RoundScale(1.425)))
    end)
end)

-- =========================================================
-- AggroAlertEnabled
-- =========================================================

describe("AggroAlertEnabled", function()
    it("returns true for solo when solo enabled", function()
        assert.is_true(Logic.AggroAlertEnabled("solo", true, false, false))
    end)

    it("returns false for solo when solo disabled", function()
        assert.is_false(Logic.AggroAlertEnabled("solo", false, true, true))
    end)

    it("returns true for party when party enabled", function()
        assert.is_true(Logic.AggroAlertEnabled("party", false, true, false))
    end)

    it("returns false for party when party disabled", function()
        assert.is_false(Logic.AggroAlertEnabled("party", true, false, true))
    end)

    it("returns true for raid when raid enabled", function()
        assert.is_true(Logic.AggroAlertEnabled("raid", false, false, true))
    end)

    it("returns false for raid when raid disabled", function()
        assert.is_false(Logic.AggroAlertEnabled("raid", true, true, false))
    end)

    it("returns false for unknown context", function()
        assert.is_false(Logic.AggroAlertEnabled("battleground", true, true, true))
    end)

    it("treats nil as false", function()
        assert.is_false(Logic.AggroAlertEnabled("solo", nil, true, true))
    end)

    it("all enabled returns true for all contexts", function()
        assert.is_true(Logic.AggroAlertEnabled("solo", true, true, true))
        assert.is_true(Logic.AggroAlertEnabled("party", true, true, true))
        assert.is_true(Logic.AggroAlertEnabled("raid", true, true, true))
    end)
end)

-- =========================================================
-- SelectBestRank
-- =========================================================

describe("SelectBestRank", function()
    local ranks = {
        { id = 5, name = "Rank V",   buffId = 55 },
        { id = 4, name = "Rank IV",  buffId = 44 },
        { id = 3, name = "Rank III", buffId = 33 },
        { id = 2, name = "Rank II",  buffId = 22 },
        { id = 1, name = "Rank I",   buffId = 11 },
    }

    it("returns highest rank when all have stock", function()
        local result = Logic.SelectBestRank(ranks, function() return 5 end)
        assert.are.equal(5, result.id)
    end)

    it("returns highest rank with stock when top rank is empty", function()
        local counts = { [5] = 0, [4] = 0, [3] = 3, [2] = 1, [1] = 2 }
        local result = Logic.SelectBestRank(ranks, function(id) return counts[id] or 0 end)
        assert.are.equal(3, result.id)
    end)

    it("returns lowest rank when only lowest has stock", function()
        local counts = { [5] = 0, [4] = 0, [3] = 0, [2] = 0, [1] = 1 }
        local result = Logic.SelectBestRank(ranks, function(id) return counts[id] or 0 end)
        assert.are.equal(1, result.id)
    end)

    it("falls back to highest rank when nothing in stock", function()
        local result = Logic.SelectBestRank(ranks, function() return 0 end)
        assert.are.equal(5, result.id)
    end)

    it("returns the full rank entry table", function()
        local counts = { [5] = 0, [4] = 2, [3] = 0, [2] = 0, [1] = 0 }
        local result = Logic.SelectBestRank(ranks, function(id) return counts[id] or 0 end)
        assert.are.equal(4, result.id)
        assert.are.equal("Rank IV", result.name)
        assert.are.equal(44, result.buffId)
    end)

    it("skips zero-count ranks even if later ranks have stock", function()
        local counts = { [5] = 0, [4] = 3, [3] = 0, [2] = 5, [1] = 0 }
        local result = Logic.SelectBestRank(ranks, function(id) return counts[id] or 0 end)
        assert.are.equal(4, result.id)
    end)

    it("works with a single rank", function()
        local single = { { id = 10, name = "Only", buffId = 99 } }
        local result = Logic.SelectBestRank(single, function() return 0 end)
        assert.are.equal(10, result.id)
    end)

    it("works with a single rank that has stock", function()
        local single = { { id = 10, name = "Only", buffId = 99 } }
        local result = Logic.SelectBestRank(single, function() return 3 end)
        assert.are.equal(10, result.id)
    end)
end)

-- =========================================================
-- SelectFirstInStock
-- =========================================================

describe("SelectFirstInStock", function()
    local primary = { id = 100, name = "Primary" }
    local TK = { ["Tempest Keep"] = true }
    local alternates = {
        { id = 1, name = "Zone Alt", zones = TK },
        { id = 2, name = "Plain Alt" },
        { id = 3, name = "Other Alt" },
    }

    it("returns the primary when no alternates are in stock", function()
        local result = Logic.SelectFirstInStock(primary, alternates, "Orgrimmar",
            function() return 0 end)
        assert.are.equal(100, result.id)
    end)

    it("returns the primary when alternates list is nil", function()
        local result = Logic.SelectFirstInStock(primary, nil, "Orgrimmar",
            function() return 5 end)
        assert.are.equal(100, result.id)
    end)

    it("returns the first in-stock non-zoned alternate", function()
        local counts = { [2] = 3, [3] = 5 }
        local result = Logic.SelectFirstInStock(primary, alternates, "Orgrimmar",
            function(id) return counts[id] or 0 end)
        assert.are.equal(2, result.id)
    end)

    it("skips a zone-restricted alternate when out of zone even if in stock", function()
        local counts = { [1] = 5, [2] = 5 }
        local result = Logic.SelectFirstInStock(primary, alternates, "Orgrimmar",
            function(id) return counts[id] or 0 end)
        assert.are.equal(2, result.id)
    end)

    it("prefers a zone-restricted alternate when in zone and in stock", function()
        local counts = { [1] = 5, [2] = 5 }
        local result = Logic.SelectFirstInStock(primary, alternates, "Tempest Keep",
            function(id) return counts[id] or 0 end)
        assert.are.equal(1, result.id)
    end)

    it("returns full entry table (id and name)", function()
        local counts = { [3] = 1 }
        local result = Logic.SelectFirstInStock(primary, alternates, "Orgrimmar",
            function(id) return counts[id] or 0 end)
        assert.are.equal(3, result.id)
        assert.are.equal("Other Alt", result.name)
    end)
end)

-- =========================================================
-- Spell rank pinning (RankedCastName / RankedCastMacro / RankPinLabel)
-- =========================================================

describe("RankedCastName", function()
    local RANKS = { "Rank 1", "Rank 2", "Rank 3" }

    it("returns the bare name for no pin (highest known)", function()
        assert.equals("Wing Clip", Logic.RankedCastName("Wing Clip", RANKS, 0))
        assert.equals("Wing Clip", Logic.RankedCastName("Wing Clip", RANKS, nil))
    end)

    it("appends the pinned rank's subtext", function()
        assert.equals("Wing Clip(Rank 1)", Logic.RankedCastName("Wing Clip", RANKS, 1))
        assert.equals("Wing Clip(Rank 3)", Logic.RankedCastName("Wing Clip", RANKS, 3))
    end)

    it("uses the localized subtext verbatim", function()
        assert.equals("Flügelstutzen(Rang 2)",
            Logic.RankedCastName("Flügelstutzen", { "Rang 1", "Rang 2" }, 2))
    end)

    it("falls back to highest known for a rank not trained yet", function()
        assert.equals("Wing Clip", Logic.RankedCastName("Wing Clip", { "Rank 1" }, 3))
        assert.equals("Wing Clip", Logic.RankedCastName("Wing Clip", {}, 1))
        assert.equals("Wing Clip", Logic.RankedCastName("Wing Clip", nil, 1))
    end)
end)

describe("RankedCastMacro", function()
    it("builds a /cast body for the pinned rank", function()
        assert.equals("/cast Wing Clip(Rank 1)",
            Logic.RankedCastMacro("Wing Clip", { "Rank 1", "Rank 2" }, 1))
    end)

    it("builds a plain /cast for no pin", function()
        assert.equals("/cast Wing Clip",
            Logic.RankedCastMacro("Wing Clip", { "Rank 1", "Rank 2" }, 0))
    end)

    it("stays a single /cast line, so the slot keeps its spell tooltip path", function()
        assert.is_true(Logic.IsSimpleCastMacro(
            Logic.RankedCastMacro("Wing Clip", { "Rank 1" }, 1)))
    end)
end)

describe("RankPinLabel", function()
    local RANKS = { "Rank 1", "Rank 2", "Rank 3" }

    it("names the default", function()
        assert.equals("highest known", Logic.RankPinLabel(RANKS, 0))
        assert.equals("highest known", Logic.RankPinLabel(RANKS, nil))
    end)

    it("shows a trained rank's own subtext", function()
        assert.equals("Rank 2", Logic.RankPinLabel(RANKS, 2))
    end)

    it("flags a rank the character has not trained", function()
        assert.equals("rank 3 (not learned)", Logic.RankPinLabel({ "Rank 1" }, 3))
        assert.equals("rank 1 (not learned)", Logic.RankPinLabel(nil, 1))
    end)
end)

-- =========================================================
-- IsSimpleCastMacro
-- =========================================================

describe("IsSimpleCastMacro", function()
    it("is true for a single /cast line", function()
        assert.is_true(Logic.IsSimpleCastMacro("/cast Frost Trap"))
    end)

    it("is true for /cast with a rank/bang and trailing spaces", function()
        assert.is_true(Logic.IsSimpleCastMacro("  /cast Aspect of the Hawk  "))
        assert.is_true(Logic.IsSimpleCastMacro("/cast !Auto Shot"))
    end)

    it("ignores #showtooltip / #directive and blank lines", function()
        assert.is_true(Logic.IsSimpleCastMacro("#showtooltip Bestial Wrath\n\n/cast Bestial Wrath"))
    end)

    it("is false for a /cast plus another action line", function()
        assert.is_false(Logic.IsSimpleCastMacro("/cast Raptor Strike\n/startattack"))
        assert.is_false(Logic.IsSimpleCastMacro("/cast Bestial Wrath\n/use 14"))
    end)

    it("is false when a non-cast line precedes the cast", function()
        assert.is_false(Logic.IsSimpleCastMacro("/targetenemy [noexists][dead][help]\n/cast !Auto Shot"))
    end)

    it("is false for a single non-cast line", function()
        assert.is_false(Logic.IsSimpleCastMacro("/use 13"))
        assert.is_false(Logic.IsSimpleCastMacro("/startattack"))
    end)

    it("is false for nil or empty", function()
        assert.is_false(Logic.IsSimpleCastMacro(nil))
        assert.is_false(Logic.IsSimpleCastMacro(""))
    end)
end)

-- =========================================================
-- MinWeaponEnchantRemaining
-- =========================================================

describe("MinWeaponEnchantRemaining", function()
    -- args: targetEnchantId, hasMain, mainMs, mainId, hasOff, offMs, offId

    it("returns main-hand remaining when only main hand carries the enchant", function()
        local ms = Logic.MinWeaponEnchantRemaining(2713,
            true, 120000, 2713, false, nil, nil)
        assert.are.equal(120000, ms)
    end)

    it("returns off-hand remaining when only off hand carries the enchant", function()
        local ms = Logic.MinWeaponEnchantRemaining(2955,
            false, nil, nil, true, 90000, 2955)
        assert.are.equal(90000, ms)
    end)

    it("picks the soonest-to-expire hand when both carry the enchant", function()
        local ms = Logic.MinWeaponEnchantRemaining(2955,
            true, 200000, 2955, true, 75000, 2955)
        assert.are.equal(75000, ms)
    end)

    it("picks main when main expires first", function()
        local ms = Logic.MinWeaponEnchantRemaining(2955,
            true, 30000, 2955, true, 600000, 2955)
        assert.are.equal(30000, ms)
    end)

    it("ignores a hand whose enchant ID does not match", function()
        -- Main hand has Windfury (2636), off hand has our weightstone.
        local ms = Logic.MinWeaponEnchantRemaining(2955,
            true, 10000, 2636, true, 500000, 2955)
        assert.are.equal(500000, ms)
    end)

    it("returns nil when neither hand carries the target enchant", function()
        local ms = Logic.MinWeaponEnchantRemaining(2955,
            true, 10000, 2636, false, nil, nil)
        assert.is_nil(ms)
    end)

    it("returns nil when no weapon enchants are present at all", function()
        local ms = Logic.MinWeaponEnchantRemaining(2713,
            false, nil, nil, false, nil, nil)
        assert.is_nil(ms)
    end)

    it("treats zero or negative remaining as absent", function()
        local ms = Logic.MinWeaponEnchantRemaining(2713,
            true, 0, 2713, true, -5, 2713)
        assert.is_nil(ms)
    end)

    it("skips an expired hand and uses the other matching hand", function()
        local ms = Logic.MinWeaponEnchantRemaining(2713,
            true, 0, 2713, true, 45000, 2713)
        assert.are.equal(45000, ms)
    end)

    it("matches any enchant when target ID is nil", function()
        local ms = Logic.MinWeaponEnchantRemaining(nil,
            true, 80000, 2636, true, 40000, 9999)
        assert.are.equal(40000, ms)
    end)

    it("with nil target ID, still requires a present enchant", function()
        local ms = Logic.MinWeaponEnchantRemaining(nil,
            false, nil, nil, false, nil, nil)
        assert.is_nil(ms)
    end)
end)

-- =========================================================
-- SuggestRotation
-- =========================================================

describe("SuggestRotation", function()
    it("suggests 5:6:1:1 for very slow speeds", function()
        assert.are.equal("5:6:1:1", Logic.SuggestRotation(2.0))
        assert.are.equal("5:6:1:1", Logic.SuggestRotation(1.84))
        assert.are.equal("5:6:1:1", Logic.SuggestRotation(3.0))
    end)

    it("suggests 5:6:1:1 at the 1.83 boundary", function()
        assert.are.equal("5:6:1:1", Logic.SuggestRotation(1.83))
    end)

    it("suggests 1:1 for mid-range speeds", function()
        assert.are.equal("1:1", Logic.SuggestRotation(1.5))
        assert.are.equal("1:1", Logic.SuggestRotation(1.3))
    end)

    it("suggests 1:1 at the 1.22 boundary", function()
        assert.are.equal("1:1", Logic.SuggestRotation(1.22))
    end)

    it("suggests 2:3 between 0.83 and 1.22", function()
        assert.are.equal("2:3", Logic.SuggestRotation(1.0))
        assert.are.equal("2:3", Logic.SuggestRotation(0.9))
        assert.are.equal("2:3", Logic.SuggestRotation(1.21))
    end)

    it("suggests 1:2 at 0.83 and below", function()
        assert.are.equal("1:2", Logic.SuggestRotation(0.83))
        assert.are.equal("1:2", Logic.SuggestRotation(0.7))
        assert.are.equal("1:2", Logic.SuggestRotation(0.5))
    end)
end)

-- =========================================================
-- Pet happiness model
-- =========================================================

describe("ReconcileHappinessTier", function()
    local TIER_MIN = { [1] = 0,   [2] = 350, [3] = 700  }
    local TIER_MAX = { [1] = 349, [2] = 699, [3] = 1050 }

    it("preserves exact arithmetic when feed-carried estimate is already in the new tier (UP)", function()
        -- Pet at 695 (tier 2), fed +8 → 703, API flips to tier 3.
        -- Prior bug: snapped to TIER_MIN[3]=700, erasing +3 real points.
        local est, anchored = Logic.ReconcileHappinessTier(703, 3, false, TIER_MIN, TIER_MAX)
        assert.are.equal(703, est)
        assert.is_false(anchored)
    end)

    it("preserves anchored=true when estimate is already in the new tier", function()
        local est, anchored = Logic.ReconcileHappinessTier(703, 3, true, TIER_MIN, TIER_MAX)
        assert.are.equal(703, est)
        assert.is_true(anchored)
    end)

    it("snaps to tier floor and anchors when estimate is below the new tier (UP flip outpaced arithmetic)", function()
        local est, anchored = Logic.ReconcileHappinessTier(680, 3, false, TIER_MIN, TIER_MAX)
        assert.are.equal(700, est)
        assert.is_true(anchored)
    end)

    it("snaps to tier ceiling and anchors when estimate is above the new tier (DOWN flip)", function()
        -- Our decay lagged reality — API says tier 2 but we thought 710.
        local est, anchored = Logic.ReconcileHappinessTier(710, 2, false, TIER_MIN, TIER_MAX)
        assert.are.equal(699, est)
        assert.is_true(anchored)
    end)

    it("preserves estimate when decay already predicted the DOWN flip", function()
        -- Our arithmetic had us at 695 (already within tier 2) when API confirms tier 2.
        local est, anchored = Logic.ReconcileHappinessTier(695, 2, false, TIER_MIN, TIER_MAX)
        assert.are.equal(695, est)
        assert.is_false(anchored)
    end)

    it("clamps above-range estimate to tier ceiling", function()
        local est, anchored = Logic.ReconcileHappinessTier(1200, 3, false, TIER_MIN, TIER_MAX)
        assert.are.equal(1050, est)
        assert.is_true(anchored)
    end)

    it("is a no-op when estimate sits exactly on the floor boundary", function()
        local est, anchored = Logic.ReconcileHappinessTier(700, 3, true, TIER_MIN, TIER_MAX)
        assert.are.equal(700, est)
        assert.is_true(anchored)
    end)

    it("is a no-op when estimate sits exactly on the ceiling boundary", function()
        local est, anchored = Logic.ReconcileHappinessTier(699, 2, false, TIER_MIN, TIER_MAX)
        assert.are.equal(699, est)
        assert.is_false(anchored)
    end)
end)

describe("ApplyHappinessDecay", function()
    local TIER_MIN = { [1] = 0, [2] = 350, [3] = 700 }
    local MAX = 1050
    local DECAY = 50 / 6  -- ~8.33 pts/min

    it("subtracts decay across elapsed seconds", function()
        local newEst = Logic.ApplyHappinessDecay(800, 60, DECAY, 3, TIER_MIN, MAX)
        assert.is_true(approx(800 - DECAY, newEst, 0.01))
    end)

    it("clamps at the API tier floor so estimate never drifts below it", function()
        -- Prior bug: from 700 at tier 3, decay → ~691.67 → ptsAboveTier negative → 0.0s forever.
        local newEst = Logic.ApplyHappinessDecay(700, 60, DECAY, 3, TIER_MIN, MAX)
        assert.are.equal(700, newEst)
    end)

    it("stays clamped at floor across many decay ticks while API tier holds", function()
        local est = 701
        for _ = 1, 20 do
            est = Logic.ApplyHappinessDecay(est, 10, DECAY, 3, TIER_MIN, MAX)
        end
        assert.are.equal(700, est)
    end)

    it("allows estimate to drift freely above the floor", function()
        local newEst = Logic.ApplyHappinessDecay(1050, 60, DECAY, 3, TIER_MIN, MAX)
        assert.is_true(approx(1050 - DECAY, newEst, 0.01))
    end)

    it("uses 0 as floor when API tier is unknown", function()
        local newEst = Logic.ApplyHappinessDecay(5, 600, DECAY, 0, TIER_MIN, MAX)
        assert.are.equal(0, newEst)
    end)

    it("clamps above max if somehow over", function()
        local newEst = Logic.ApplyHappinessDecay(2000, 0, DECAY, 3, TIER_MIN, MAX)
        assert.are.equal(1050, newEst)
    end)

    it("handles zero elapsed as a no-op", function()
        local newEst = Logic.ApplyHappinessDecay(900, 0, DECAY, 3, TIER_MIN, MAX)
        assert.are.equal(900, newEst)
    end)

    it("treats negative elapsed as zero", function()
        local newEst = Logic.ApplyHappinessDecay(900, -5, DECAY, 3, TIER_MIN, MAX)
        assert.are.equal(900, newEst)
    end)

    it("tier-2 floor clamps at 350, not 700", function()
        local newEst = Logic.ApplyHappinessDecay(350, 60, DECAY, 2, TIER_MIN, MAX)
        assert.are.equal(350, newEst)
    end)

    it("returns clamped=true when decay would cross the floor", function()
        local _, clamped = Logic.ApplyHappinessDecay(700.5, 60, DECAY, 3, TIER_MIN, MAX)
        assert.is_true(clamped)
    end)

    it("returns clamped=false when decay stays above the floor", function()
        local _, clamped = Logic.ApplyHappinessDecay(900, 60, DECAY, 3, TIER_MIN, MAX)
        assert.is_false(clamped)
    end)

    it("returns clamped=false when elapsed is zero even if already at floor", function()
        -- A no-op tick shouldn't count as a clamp event.
        local _, clamped = Logic.ApplyHappinessDecay(700, 0, DECAY, 3, TIER_MIN, MAX)
        assert.is_false(clamped)
    end)

    it("returns clamped=true on every active tick while pinned at floor", function()
        local _, clamped = Logic.ApplyHappinessDecay(700, 1, DECAY, 3, TIER_MIN, MAX)
        assert.is_true(clamped)
    end)
end)

-- =========================================================
-- Range-to-target bracketing
-- =========================================================

local RANGE_CHECKERS = {
    { range = 5 },
    { range = 8 },
    { range = 10 },
    { range = 15 },
    { range = 25 },
}

describe("ComputeRangeBracket", function()
    it("brackets between the nearest in-range and farthest out-of-range checker", function()
        -- distance ~7yd: out of 5, in 8/10/15/25
        local minR, maxR = Logic.ComputeRangeBracket(RANGE_CHECKERS,
            { false, true, true, true, true })
        assert.are.equal(5, minR)
        assert.are.equal(8, maxR)
    end)

    it("returns nil min when within the closest checker (in melee)", function()
        local minR, maxR = Logic.ComputeRangeBracket(RANGE_CHECKERS,
            { true, true, true, true, true })
        assert.is_nil(minR)
        assert.are.equal(5, maxR)
    end)

    it("returns nil max when beyond the furthest checker", function()
        local minR, maxR = Logic.ComputeRangeBracket(RANGE_CHECKERS,
            { false, false, false, false, false })
        assert.are.equal(25, minR)
        assert.is_nil(maxR)
    end)

    it("returns both nil when no checker is usable", function()
        local minR, maxR = Logic.ComputeRangeBracket(RANGE_CHECKERS,
            { nil, nil, nil, nil, nil })
        assert.is_nil(minR)
        assert.is_nil(maxR)
    end)

    it("skips nil (unusable) checkers and brackets from the rest", function()
        -- 8 and 15 checks unavailable; out of 5/10, in 25
        local minR, maxR = Logic.ComputeRangeBracket(RANGE_CHECKERS,
            { false, nil, false, nil, true })
        assert.are.equal(10, minR)
        assert.are.equal(25, maxR)
    end)

    it("drops a contradictory lower bound (non-monotonic noise)", function()
        -- near check in-range but a farther check out-of-range: trust the upper bound
        local minR, maxR = Logic.ComputeRangeBracket(RANGE_CHECKERS,
            { true, false, true, true, true })
        assert.is_nil(minR)
        assert.are.equal(5, maxR)
    end)
end)

describe("FormatRangeBracket", function()
    it("formats a closed bracket", function()
        assert.are.equal("5-8 yd", Logic.FormatRangeBracket(5, 8))
    end)

    it("formats an in-melee bracket with a 0 lower bound", function()
        assert.are.equal("0-5 yd", Logic.FormatRangeBracket(nil, 5))
    end)

    it("formats an open-ended far bracket", function()
        assert.are.equal("25+ yd", Logic.FormatRangeBracket(25, nil))
    end)

    it("formats indeterminate as ?", function()
        assert.are.equal("?", Logic.FormatRangeBracket(nil, nil))
    end)
end)

describe("ShouldShowRangeShade", function()
    it("never shades without a valid range unit", function()
        assert.is_false(Logic.ShouldShowRangeShade(0, false))
        assert.is_false(Logic.ShouldShowRangeShade(1, false))
        assert.is_false(Logic.ShouldShowRangeShade(nil, false))
    end)

    it("shades only when confirmed out of range (0) of a valid unit", function()
        assert.is_true(Logic.ShouldShowRangeShade(0, true))
    end)

    it("does not shade when in range (1)", function()
        assert.is_false(Logic.ShouldShowRangeShade(1, true))
    end)

    it("does not shade when range is indeterminate (nil)", function()
        assert.is_false(Logic.ShouldShowRangeShade(nil, true))
    end)
end)

describe("ShouldShowManaShade", function()
    it("shades when the spell is out of mana", function()
        assert.is_true(Logic.ShouldShowManaShade(true))
    end)

    it("does not shade when mana is sufficient", function()
        assert.is_false(Logic.ShouldShowManaShade(false))
    end)

    it("does not shade when the mana flag is nil", function()
        assert.is_false(Logic.ShouldShowManaShade(nil))
    end)
end)

describe("MaxShootingRange", function()
    it("returns the 35yd base with no Hawk Eye", function()
        assert.are.equal(35, Logic.MaxShootingRange(0))
        assert.are.equal(35, Logic.MaxShootingRange(nil))
    end)

    it("adds 2yd per Hawk Eye rank", function()
        assert.are.equal(37, Logic.MaxShootingRange(1))
        assert.are.equal(39, Logic.MaxShootingRange(2))
        assert.are.equal(41, Logic.MaxShootingRange(3))
    end)

    it("honors a custom base range", function()
        assert.are.equal(46, Logic.MaxShootingRange(3, 40))
    end)
end)

describe("RangeZone", function()
    it("classifies within melee reach as melee", function()
        assert.are.equal("melee", Logic.RangeZone(nil, 5))
    end)

    it("classifies the 5-8 sweet spot as weave", function()
        assert.are.equal("weave", Logic.RangeZone(5, 8))
    end)

    it("classifies between the weave window and shooting range edge as inrange", function()
        assert.are.equal("inrange", Logic.RangeZone(8, 10))
        assert.are.equal("inrange", Logic.RangeZone(25, nil))
        assert.are.equal("inrange", Logic.RangeZone(30, 35))
    end)

    it("classifies beyond shooting range as far", function()
        assert.are.equal("far", Logic.RangeZone(35, nil))
        assert.are.equal("far", Logic.RangeZone(40, nil))
    end)

    it("treats a coarse bracket overlapping the weave window as weave", function()
        assert.are.equal("weave", Logic.RangeZone(5, 10))
    end)

    it("returns ? when indeterminate", function()
        assert.are.equal("?", Logic.RangeZone(nil, nil))
    end)

    it("honors custom melee/weave/ranged thresholds", function()
        assert.are.equal("melee", Logic.RangeZone(nil, 6, 6, 9, 30))
        assert.are.equal("inrange", Logic.RangeZone(9, 12, 6, 9, 30))
        assert.are.equal("far", Logic.RangeZone(30, nil, 6, 9, 30))
    end)
end)

-- =========================================================
-- AbbreviateBindingKey
-- =========================================================

describe("AbbreviateBindingKey", function()
    it("returns nil for nil or empty input", function()
        assert.is_nil(Logic.AbbreviateBindingKey(nil))
        assert.is_nil(Logic.AbbreviateBindingKey(""))
    end)

    it("passes through plain keys", function()
        assert.are.equal("1", Logic.AbbreviateBindingKey("1"))
        assert.are.equal("F", Logic.AbbreviateBindingKey("F"))
        assert.are.equal("F5", Logic.AbbreviateBindingKey("F5"))
    end)

    it("collapses single modifiers to lowercase letters with no separator", function()
        assert.are.equal("s1", Logic.AbbreviateBindingKey("SHIFT-1"))
        assert.are.equal("c2", Logic.AbbreviateBindingKey("CTRL-2"))
        assert.are.equal("aQ", Logic.AbbreviateBindingKey("ALT-Q"))
    end)

    it("collapses stacked modifiers in order", function()
        assert.are.equal("csF", Logic.AbbreviateBindingKey("CTRL-SHIFT-F"))
        assert.are.equal("as1", Logic.AbbreviateBindingKey("ALT-SHIFT-1"))
    end)

    it("shortens mouse buttons", function()
        assert.are.equal("m4", Logic.AbbreviateBindingKey("BUTTON4"))
        assert.are.equal("cm4", Logic.AbbreviateBindingKey("CTRL-BUTTON4"))
    end)

    it("shortens mouse wheel", function()
        assert.are.equal("mwu", Logic.AbbreviateBindingKey("MOUSEWHEELUP"))
        assert.are.equal("mwd", Logic.AbbreviateBindingKey("MOUSEWHEELDOWN"))
    end)

    it("shortens numpad keys", function()
        assert.are.equal("n3", Logic.AbbreviateBindingKey("NUMPAD3"))
        assert.are.equal("n/", Logic.AbbreviateBindingKey("NUMPADDIVIDE"))
        assert.are.equal("n*", Logic.AbbreviateBindingKey("NUMPADMULTIPLY"))
    end)

    it("uppercases lowercase input", function()
        assert.are.equal("sG", Logic.AbbreviateBindingKey("shift-g"))
    end)
end)

-- =========================================================
-- PetActionEnabled
-- =========================================================

describe("PetActionEnabled", function()
    local function state(exists, alive)
        return { exists = exists, alive = alive }
    end

    it("is always enabled with no requirement or 'any'", function()
        assert.is_true(Logic.PetActionEnabled(nil, state(false, false)))
        assert.is_true(Logic.PetActionEnabled("any", state(false, false)))
    end)

    it("'active' requires the pet to exist", function()
        assert.is_true(Logic.PetActionEnabled("active", state(true, true)))
        assert.is_true(Logic.PetActionEnabled("active", state(true, false)))
        assert.is_false(Logic.PetActionEnabled("active", state(false, false)))
    end)

    it("'alive' requires an existing, living pet", function()
        assert.is_true(Logic.PetActionEnabled("alive", state(true, true)))
        assert.is_false(Logic.PetActionEnabled("alive", state(true, false)))
        assert.is_false(Logic.PetActionEnabled("alive", state(false, false)))
    end)

    it("'dead' requires an existing, dead pet", function()
        assert.is_true(Logic.PetActionEnabled("dead", state(true, false)))
        assert.is_false(Logic.PetActionEnabled("dead", state(true, true)))
        assert.is_false(Logic.PetActionEnabled("dead", state(false, false)))
    end)

    it("'missing' requires no pet", function()
        assert.is_true(Logic.PetActionEnabled("missing", state(false, false)))
        assert.is_false(Logic.PetActionEnabled("missing", state(true, true)))
    end)

    it("'notdead' is enabled unless an existing pet is dead", function()
        assert.is_true(Logic.PetActionEnabled("notdead", state(true, true)))   -- alive
        assert.is_true(Logic.PetActionEnabled("notdead", state(false, false))) -- no pet
        assert.is_false(Logic.PetActionEnabled("notdead", state(true, false))) -- dead
    end)

    it("fails open for an unknown token", function()
        assert.is_true(Logic.PetActionEnabled("bogus", state(false, false)))
    end)

    it("tolerates a nil state table", function()
        assert.is_true(Logic.PetActionEnabled(nil, nil))
        assert.is_false(Logic.PetActionEnabled("active", nil))
    end)
end)

-- =========================================================
-- PetStateKey
-- =========================================================

describe("PetStateKey", function()
    it("returns 'alive' for an existing, living pet", function()
        assert.are.equal("alive", Logic.PetStateKey({ exists = true, alive = true }))
    end)

    it("returns 'dead' for an existing, dead pet", function()
        assert.are.equal("dead", Logic.PetStateKey({ exists = true, alive = false }))
    end)

    it("returns 'missing' when there is no pet", function()
        assert.are.equal("missing", Logic.PetStateKey({ exists = false, alive = false }))
    end)

    it("returns 'missing' for a nil state", function()
        assert.are.equal("missing", Logic.PetStateKey(nil))
    end)
end)

-- =========================================================
-- ComputeMissingDebuffs
-- =========================================================

describe("ComputeMissingDebuffs", function()
    local tracked = {
        { key = "ff",   name = "Faerie Fire",   auras = { "Faerie Fire", "Faerie Fire (Feral)" } },
        { key = "mark", name = "Hunter's Mark", auras = { "Hunter's Mark" } },
        { key = "armor", name = "Armor reduction", auras = { "Sunder Armor", "Expose Armor" } },
    }
    local allOn = function() return true end

    it("returns entries with none of their auras present", function()
        local missing = Logic.ComputeMissingDebuffs(tracked, allOn, { ["Hunter's Mark"] = true })
        assert.are.equal(2, #missing)
        assert.are.equal("ff", missing[1].key)
        assert.are.equal("armor", missing[2].key)
    end)

    it("treats an entry as present if ANY alias aura is up", function()
        local missing = Logic.ComputeMissingDebuffs(tracked, allOn, { ["Expose Armor"] = true })
        for _, d in ipairs(missing) do
            assert.are_not.equal("armor", d.key)
        end
    end)

    it("preserves input order in the result", function()
        local missing = Logic.ComputeMissingDebuffs(tracked, allOn, {})
        assert.are.equal("ff", missing[1].key)
        assert.are.equal("mark", missing[2].key)
        assert.are.equal("armor", missing[3].key)
    end)

    it("skips disabled debuffs entirely", function()
        local onlyMark = function(key) return key == "mark" end
        local missing = Logic.ComputeMissingDebuffs(tracked, onlyMark, {})
        assert.are.equal(1, #missing)
        assert.are.equal("mark", missing[1].key)
    end)

    it("returns nothing when everything is present", function()
        local present = { ["Faerie Fire"] = true, ["Hunter's Mark"] = true, ["Sunder Armor"] = true }
        assert.are.equal(0, #Logic.ComputeMissingDebuffs(tracked, allOn, present))
    end)

    it("handles nil tracked / nil present gracefully", function()
        assert.are.equal(0, #Logic.ComputeMissingDebuffs(nil, allOn, nil))
        assert.are.equal(3, #Logic.ComputeMissingDebuffs(tracked, allOn, nil))
    end)
end)

-- =========================================================
-- RaidDebuffsShouldShow
-- =========================================================

describe("RaidDebuffsShouldShow", function()
    local function base(over)
        local o = { enabled = true, inCombat = true, inRaid = true, hasTarget = true, unlocked = false }
        for k, v in pairs(over or {}) do o[k] = v end
        return o
    end

    it("shows when enabled, in combat, in raid, with a target", function()
        assert.is_true(Logic.RaidDebuffsShouldShow(base()))
    end)

    it("always shows when unlocked, regardless of other state", function()
        assert.is_true(Logic.RaidDebuffsShouldShow({ unlocked = true }))
    end)

    it("hides when the feature is disabled", function()
        assert.is_false(Logic.RaidDebuffsShouldShow(base({ enabled = false })))
    end)

    it("hides when out of combat", function()
        assert.is_false(Logic.RaidDebuffsShouldShow(base({ inCombat = false })))
    end)

    it("hides when not in a raid", function()
        assert.is_false(Logic.RaidDebuffsShouldShow(base({ inRaid = false })))
    end)

    it("hides when there is no target", function()
        assert.is_false(Logic.RaidDebuffsShouldShow(base({ hasTarget = false })))
    end)

    it("still hides without a target even when both relaxers are on", function()
        assert.is_false(Logic.RaidDebuffsShouldShow(
            base({ hasTarget = false, showOutOfCombat = true, showOutOfRaid = true })))
    end)

    it("shows out of combat when showOutOfCombat is set", function()
        assert.is_true(Logic.RaidDebuffsShouldShow(
            base({ inCombat = false, showOutOfCombat = true })))
    end)

    it("still hides out of combat when only the raid relaxer is set", function()
        assert.is_false(Logic.RaidDebuffsShouldShow(
            base({ inCombat = false, showOutOfRaid = true })))
    end)

    it("shows out of raid when showOutOfRaid is set", function()
        assert.is_true(Logic.RaidDebuffsShouldShow(
            base({ inRaid = false, showOutOfRaid = true })))
    end)

    it("shows solo (no combat, no raid) when both relaxers are set", function()
        assert.is_true(Logic.RaidDebuffsShouldShow(
            base({ inCombat = false, inRaid = false,
                   showOutOfCombat = true, showOutOfRaid = true })))
    end)

    it("handles nil opts", function()
        assert.is_false(Logic.RaidDebuffsShouldShow(nil))
    end)
end)

-- =========================================================
-- ComputeDebuffStatus
-- =========================================================

describe("ComputeDebuffStatus", function()
    local tracked = {
        { key = "ff",    name = "Faerie Fire",     auras = { "Faerie Fire", "Faerie Fire (Feral)" } },
        { key = "mark",  name = "Hunter's Mark",   auras = { "Hunter's Mark" } },
        { key = "armor", name = "Armor reduction", auras = { "Sunder Armor", "Expose Armor" } },
    }
    local allOn = function() return true end

    it("returns one entry per enabled debuff in input order", function()
        local st = Logic.ComputeDebuffStatus(tracked, allOn, {})
        assert.are.equal(3, #st)
        assert.are.equal("ff", st[1].key)
        assert.are.equal("mark", st[2].key)
        assert.are.equal("armor", st[3].key)
    end)

    it("flags satisfied and reports the satisfying alias aura", function()
        local st = Logic.ComputeDebuffStatus(tracked, allOn, { ["Expose Armor"] = true })
        assert.is_false(st[1].satisfied)         -- ff
        assert.is_nil(st[1].aura)
        assert.is_true(st[3].satisfied)          -- armor
        assert.are.equal("Expose Armor", st[3].aura)
    end)

    it("skips disabled debuffs entirely", function()
        local onlyMark = function(key) return key == "mark" end
        local st = Logic.ComputeDebuffStatus(tracked, onlyMark, {})
        assert.are.equal(1, #st)
        assert.are.equal("mark", st[1].key)
    end)

    it("respects caster matching like ComputeMissingDebuffs", function()
        local BOOMKIN = "Player-1-ABCD"
        local reqFor = function(key) if key == "ff" then return BOOMKIN end end
        local st = Logic.ComputeDebuffStatus(tracked, allOn,
            { ["Faerie Fire"] = "Player-1-OTHER" }, reqFor)
        assert.is_false(st[1].satisfied)  -- wrong caster → not satisfied
    end)

    it("handles nil tracked / nil present gracefully", function()
        assert.are.equal(0, #Logic.ComputeDebuffStatus(nil, allOn, nil))
        assert.are.equal(3, #Logic.ComputeDebuffStatus(tracked, allOn, nil))
    end)
end)

-- =========================================================
-- DebuffBarColor
-- =========================================================

describe("DebuffBarColor", function()
    local function blue(r, g, b)   return r == 0.25 and g == 0.55 and b == 0.95 end
    local function yellow(r, g, b) return r == 0.95 and g == 0.85 and b == 0.15 end
    local function orange(r, g, b) return r == 1.00 and g == 0.50 and b == 0.10 end

    it("is blue above 50% remaining", function()
        assert.is_true(blue(Logic.DebuffBarColor(6, 10)))
    end)

    it("is yellow at exactly 50% remaining", function()
        assert.is_true(yellow(Logic.DebuffBarColor(5, 10)))
    end)

    it("is yellow between 20% and 50%", function()
        assert.is_true(yellow(Logic.DebuffBarColor(3, 10)))
    end)

    it("is orange at exactly 20% remaining", function()
        assert.is_true(orange(Logic.DebuffBarColor(2, 10)))
    end)

    it("is orange below 20%", function()
        assert.is_true(orange(Logic.DebuffBarColor(0.5, 10)))
    end)

    it("is blue (full) when duration is zero / nil", function()
        assert.is_true(blue(Logic.DebuffBarColor(0, 0)))
        assert.is_true(blue(Logic.DebuffBarColor(nil, nil)))
    end)
end)

-- =========================================================
-- ComputeMissingDebuffs — caster matching
-- =========================================================

describe("ComputeMissingDebuffs caster matching", function()
    local tracked = {
        { key = "ff",   name = "Improved Faerie Fire", auras = { "Faerie Fire", "Faerie Fire (Feral)" } },
        { key = "mark", name = "Hunter's Mark",        auras = { "Hunter's Mark" } },
    }
    local allOn = function() return true end
    local BOOMKIN = "Player-1234-DEADBEEF"
    -- Only the FF entry requires the boomkin caster.
    local reqFor = function(key) if key == "ff" then return BOOMKIN end end

    it("satisfies FF when cast by the required caster", function()
        local present = { ["Faerie Fire"] = BOOMKIN }
        local missing = Logic.ComputeMissingDebuffs(tracked, allOn, present, reqFor)
        for _, d in ipairs(missing) do assert.are_not.equal("ff", d.key) end
    end)

    it("flags FF missing when cast by a known different player", function()
        local present = { ["Faerie Fire"] = "Player-1234-FEEDFACE" }
        local missing = Logic.ComputeMissingDebuffs(tracked, allOn, present, reqFor)
        assert.are.equal("ff", missing[1].key)
    end)

    it("leniently satisfies FF when the caster is unknown", function()
        local present = { ["Faerie Fire"] = true }
        local missing = Logic.ComputeMissingDebuffs(tracked, allOn, present, reqFor)
        for _, d in ipairs(missing) do assert.are_not.equal("ff", d.key) end
    end)

    it("flags FF missing when no FF aura is present at all", function()
        local missing = Logic.ComputeMissingDebuffs(tracked, allOn, {}, reqFor)
        assert.are.equal("ff", missing[1].key)
    end)

    it("ignores caster requirement for entries that have none", function()
        -- Hunter's Mark from any caster still counts (reqFor returns nil for it).
        local present = { ["Hunter's Mark"] = "Player-1234-SOMEONE" }
        local missing = Logic.ComputeMissingDebuffs(tracked, allOn, present, reqFor)
        for _, d in ipairs(missing) do assert.are_not.equal("mark", d.key) end
    end)

    it("treats a present GUID like presence when no requiredCasterFor is given", function()
        local present = { ["Faerie Fire"] = "Player-1234-ANYONE", ["Hunter's Mark"] = true }
        assert.are.equal(0, #Logic.ComputeMissingDebuffs(tracked, allOn, present))
    end)
end)

-- =========================================================
-- ComputeMissingDebuffs — caster set (auto-detected druids)
-- =========================================================

describe("ComputeMissingDebuffs caster set", function()
    local tracked = { { key = "ff", name = "Improved Faerie Fire", auras = { "Faerie Fire" } } }
    local allOn = function() return true end
    local A, B, C = "Player-A", "Player-B", "Player-C"
    -- Accept either of two specced druids.
    local reqFor = function(key) if key == "ff" then return { [A] = true, [B] = true } end end

    it("satisfies when FF is cast by any caster in the set", function()
        assert.are.equal(0, #Logic.ComputeMissingDebuffs(tracked, allOn, { ["Faerie Fire"] = B }, reqFor))
    end)

    it("flags missing when cast by someone outside the set", function()
        local missing = Logic.ComputeMissingDebuffs(tracked, allOn, { ["Faerie Fire"] = C }, reqFor)
        assert.are.equal("ff", missing[1].key)
    end)

    it("is lenient when the caster is unknown", function()
        assert.are.equal(0, #Logic.ComputeMissingDebuffs(tracked, allOn, { ["Faerie Fire"] = true }, reqFor))
    end)
end)

-- =========================================================
-- FindTalentRank
-- =========================================================

describe("FindTalentRank", function()
    local talents = {
        { name = "Improved Aspect of the Hawk", rank = 5 },
        { name = "Improved Faerie Fire", rank = 3 },
        { name = "Moonfury", rank = 0 },
    }

    it("returns the rank of a present talent", function()
        assert.are.equal(3, Logic.FindTalentRank(talents, "Improved Faerie Fire"))
    end)

    it("returns 0 for a talent not in the list", function()
        assert.are.equal(0, Logic.FindTalentRank(talents, "Misery"))
    end)

    it("returns 0 (untalented) for a present-but-unspent talent", function()
        assert.are.equal(0, Logic.FindTalentRank(talents, "Moonfury"))
    end)

    it("handles a nil list", function()
        assert.are.equal(0, Logic.FindTalentRank(nil, "Anything"))
    end)
end)

-- =========================================================
-- ComputeAssistList
-- =========================================================

describe("ComputeAssistList", function()
    it("returns role-flagged tanks, preserving order", function()
        local roster = {
            { name = "Healer",  role = "MAINASSIST", unit = "raid1target" },
            { name = "Tankone", role = "TANK",   unit = "raid2target" },
            { name = "Dps",     role = nil,          unit = "raid3target" },
            { name = "Tanktwo", role = "TANK",   unit = "raid4target" },
        }
        local out = Logic.ComputeAssistList(roster, nil)
        assert.are.equal(2, #out)
        assert.are.equal("Tankone", out[1].name)
        assert.are.equal("raid2target", out[1].unit)
        assert.are.equal("Tanktwo", out[2].name)
    end)

    it("includes manually named members alongside tanks (union)", function()
        local roster = {
            { name = "Mt",     role = "TANK", unit = "raid1target" },
            { name = "Ccer",   role = nil,    unit = "raid2target" },
            { name = "Dps",    role = nil,    unit = "raid3target" },
        }
        local out = Logic.ComputeAssistList(roster, Logic.ParseNameSet("ccer"))
        assert.are.equal(2, #out)
        assert.are.equal("Mt", out[1].name)
        assert.are.equal("Ccer", out[2].name)
    end)

    it("preserves roster order for the union", function()
        local roster = {
            { name = "Extra", role = nil,    unit = "raid1target" },
            { name = "Mt",    role = "TANK", unit = "raid2target" },
        }
        local out = Logic.ComputeAssistList(roster, Logic.ParseNameSet("extra"))
        assert.are.equal(2, #out)
        assert.are.equal("Extra", out[1].name)
        assert.are.equal("Mt", out[2].name)
    end)

    it("does not duplicate a tank who is also in the manual set", function()
        local roster = {
            { name = "Mt", role = "TANK", unit = "raid1target" },
        }
        local out = Logic.ComputeAssistList(roster, Logic.ParseNameSet("mt"))
        assert.are.equal(1, #out)
        assert.are.equal("Mt", out[1].name)
    end)

    it("works with manual names when no tank is flagged", function()
        local roster = {
            { name = "Bob",   role = nil, unit = "raid1target" },
            { name = "Alice", role = nil, unit = "raid2target" },
            { name = "Carol", role = nil, unit = "raid3target" },
        }
        local out = Logic.ComputeAssistList(roster, Logic.ParseNameSet("alice, carol"))
        assert.are.equal(2, #out)
        assert.are.equal("Alice", out[1].name)
        assert.are.equal("Carol", out[2].name)
    end)

    it("returns empty when nothing matches", function()
        local roster = { { name = "Dps", role = nil, unit = "raid1target" } }
        assert.are.equal(0, #Logic.ComputeAssistList(roster, Logic.ParseNameSet("nobody")))
        assert.are.equal(0, #Logic.ComputeAssistList(roster, nil))
        assert.are.equal(0, #Logic.ComputeAssistList(nil, nil))
    end)
end)

-- =========================================================
-- ParseNameSet
-- =========================================================

describe("ParseNameSet", function()
    it("splits on commas and whitespace, lowercasing", function()
        local s = Logic.ParseNameSet("Bob, Alice   Carol")
        assert.is_true(s["bob"])
        assert.is_true(s["alice"])
        assert.is_true(s["carol"])
    end)

    it("keeps realm suffixes intact", function()
        local s = Logic.ParseNameSet("Bob-Whitemane")
        assert.is_true(s["bob-whitemane"])
        assert.is_nil(s["bob"])
    end)

    it("returns an empty set for nil/empty input", function()
        assert.are.same({}, Logic.ParseNameSet(nil))
        assert.are.same({}, Logic.ParseNameSet(""))
        assert.are.same({}, Logic.ParseNameSet("   "))
    end)
end)

-- =========================================================
-- DevilsaurStage
-- =========================================================

describe("DevilsaurStage", function()
    local TOOTH = 19992

    it("returns 'absent' when no Tooth equipped and none in bags", function()
        assert.are.equal("absent", Logic.DevilsaurStage(nil, false, false, TOOTH))
        -- some other trinket equipped also counts as absent if no Tooth carried
        assert.are.equal("absent", Logic.DevilsaurStage(12345, false, false, TOOTH))
    end)

    it("returns 'bagged' when Tooth is in bags but not equipped", function()
        assert.are.equal("bagged", Logic.DevilsaurStage(nil, false, true, TOOTH))
        assert.are.equal("bagged", Logic.DevilsaurStage(12345, false, true, TOOTH))
    end)

    it("returns 'equipped_unused' when Tooth equipped and buff not yet on pet", function()
        assert.are.equal("equipped_unused", Logic.DevilsaurStage(TOOTH, false, false, TOOTH))
    end)

    it("returns 'equipped_buffed' when Tooth equipped AND buff active on pet", function()
        -- the safety-net warning state: swap-back failed or hasn't run
        assert.are.equal("equipped_buffed", Logic.DevilsaurStage(TOOTH, true, false, TOOTH))
    end)

    it("returns 'buffed_unequipped' when Tooth swapped back and buff still ticking", function()
        -- the happy outcome
        assert.are.equal("buffed_unequipped", Logic.DevilsaurStage(nil, true, true, TOOTH))
        assert.are.equal("buffed_unequipped", Logic.DevilsaurStage(12345, true, false, TOOTH))
    end)

    it("prioritizes equipped+buff over bag presence", function()
        -- with a Tooth equipped, bag state doesn't matter
        assert.are.equal("equipped_buffed", Logic.DevilsaurStage(TOOTH, true, true, TOOTH))
        assert.are.equal("equipped_unused", Logic.DevilsaurStage(TOOTH, false, true, TOOTH))
    end)
end)


-- =========================================================
-- HastedCastTime
-- =========================================================

describe("HastedCastTime", function()
    it("returns baseCast unchanged when speeds unknown", function()
        assert.are.equal(1.5, Logic.HastedCastTime(1.5, 0, 0))
        assert.are.equal(1.5, Logic.HastedCastTime(1.5, nil, nil))
        assert.are.equal(1.5, Logic.HastedCastTime(1.5, 1.5, 0))
    end)

    it("returns baseCast when unhasted (hastedSpeed == baseSpeed)", function()
        assert.is_true(approx(1.5, Logic.HastedCastTime(1.5, 2.17, 2.17)))
    end)

    it("shortens the cast proportionally to ranged haste", function()
        -- 2.17 base hasted to 1.8925 => 15% haste => 1.5 / 1.15 = 1.3043
        assert.is_true(approx(1.5 * 1.8925 / 2.17, Logic.HastedCastTime(1.5, 1.8925, 2.17)))
        assert.is_true(approx(1.3043, Logic.HastedCastTime(1.5, 1.8925, 2.17), 0.01))
    end)
end)

-- =========================================================
-- WeaveNowState
-- =========================================================

describe("WeaveNowState", function()
    local function state(o)
        local show, rem = Logic.WeaveNowState(o)
        return show, rem
    end

    it("is off when melee swing is not ready", function()
        assert.is_false((state({ meleeReady = false, timeToAuto = 1.0, weaveCost = 0.4, steadyCastTime = 1.5 })))
    end)

    it("is off while casting (moving would cancel the cast)", function()
        assert.is_false((state({ meleeReady = true, casting = true, timeToAuto = 1.0, weaveCost = 0.4, steadyCastTime = 1.5 })))
    end)

    it("is off when there is no auto cycle (timeToAuto nil)", function()
        assert.is_false((state({ meleeReady = true, timeToAuto = nil, weaveCost = 0.4, steadyCastTime = 1.5 })))
    end)

    it("is off when there isn't enough time to weave before the auto", function()
        assert.is_false((state({ meleeReady = true, timeToAuto = 0.3, weaveCost = 0.4, steadyCastTime = 1.5 })))
    end)

    it("is off right after an auto with room for a shot and not on GCD (should shoot, not weave)", function()
        -- slow regime: 2.17s to auto, can fit a 1.5s Steady, off GCD -> shoot first
        assert.is_false((state({ meleeReady = true, gcdRemaining = 0, timeToAuto = 2.17, weaveCost = 0.4, steadyCastTime = 1.5 })))
    end)

    it("is off at the start of a fresh cycle while the previous GCD tail drains", function()
        -- auto just fired (2.17s ahead) with only 0.2s of the last Steady's GCD
        -- left: a full Steady still fits (2.17 - 0.2 = 1.97 >= 1.5) -> cast, don't
        -- weave. This is the "cue flashes for an instant right after the auto" fix.
        assert.is_false((state({ meleeReady = true, gcdRemaining = 0.2, timeToAuto = 2.17, weaveCost = 0.4, steadyCastTime = 1.5 })))
    end)

    it("is ON in the slow post-cast tail (no room for a shot before the auto)", function()
        -- Steady done, ~0.67s to auto, off GCD, can't fit a 1.5s Steady -> weave
        local show, rem = state({ meleeReady = true, gcdRemaining = 0, timeToAuto = 0.67, weaveCost = 0.4, steadyCastTime = 1.5 })
        assert.is_true(show)
        assert.is_true(approx(0.27, rem))
    end)

    it("is ON in the arcane/multi GCD gap (locked out, leftover won't fit a Steady)", function()
        -- just fired an instant shot: 2.0s to auto but 1.5s GCD left, so only 0.5s
        -- of castable time before the auto -> weave the GCD gap
        local show = state({ meleeReady = true, gcdRemaining = 1.5, timeToAuto = 2.0, weaveCost = 0.4, steadyCastTime = 1.5 })
        assert.is_true(show)
    end)

    it("is ON in the fast auto-auto gap (short cycle, no room for a shot)", function()
        -- giga-haste: 0.7s to auto, off GCD, hasted Steady ~1.0s doesn't fit -> weave
        local show = state({ meleeReady = true, gcdRemaining = 0, timeToAuto = 0.7, weaveCost = 0.4, steadyCastTime = 1.0 })
        assert.is_true(show)
    end)

    it("window remaining is timeToAuto minus weaveCost", function()
        local _, rem = state({ meleeReady = true, gcdRemaining = 1.5, timeToAuto = 1.2, weaveCost = 0.4, steadyCastTime = 1.5 })
        assert.is_true(approx(0.8, rem))
    end)
end)

-- =========================================================
-- HoldCue (anti-flicker hysteresis)
-- =========================================================

describe("MeleeRetryDelay", function()
    it("classifies a clean weave (~0.11s) as not a retry", function()
        local delay, retry = Logic.MeleeRetryDelay(100, 100.11, 0.35, 3.0)
        assert.is_near(0.11, delay, 1e-9)
        assert.is_false(retry)
    end)

    it("classifies a stale-position weave (~0.61s) as a retry", function()
        local delay, retry = Logic.MeleeRetryDelay(100, 100.61, 0.35, 3.0)
        assert.is_near(0.61, delay, 1e-9)
        assert.is_true(retry)
    end)

    it("treats the threshold as inclusive", function()
        local _, retry = Logic.MeleeRetryDelay(1, 1.35, 0.35, 3.0)
        assert.is_true(retry)
    end)

    it("cannot attribute a swing with no preceding press", function()
        local delay, retry = Logic.MeleeRetryDelay(0, 100.5, 0.35, 3.0)
        assert.is_nil(delay)
        assert.is_false(retry)
        delay, retry = Logic.MeleeRetryDelay(nil, 100.5, 0.35, 3.0)
        assert.is_nil(delay)
        assert.is_false(retry)
    end)

    it("cannot attribute an auto-attack continuation swing (outside the window)", function()
        local delay, retry = Logic.MeleeRetryDelay(100, 103.6, 0.35, 3.0)
        assert.is_nil(delay)
        assert.is_false(retry)
    end)

    it("cannot attribute a swing that landed before the press", function()
        local delay, retry = Logic.MeleeRetryDelay(100, 99.9, 0.35, 3.0)
        assert.is_nil(delay)
        assert.is_false(retry)
    end)

    it("defaults threshold to 0.35 and attribution window to 3.0", function()
        local _, retry = Logic.MeleeRetryDelay(100, 100.4)
        assert.is_true(retry)
        local delay = Logic.MeleeRetryDelay(100, 103.5)
        assert.is_nil(delay)
    end)
end)

describe("HoldCue", function()
    it("shows immediately and sets holdUntil when raw is on", function()
        local shown, hu = Logic.HoldCue(true, 100, 0, 0.3)
        assert.is_true(shown)
        assert.are.equal(100.3, hu)
    end)

    it("keeps showing after raw goes off, until holdUntil passes", function()
        local _, hu = Logic.HoldCue(true, 100, 0, 0.3)   -- holdUntil = 100.3
        local shown = Logic.HoldCue(false, 100.2, hu, 0.3)
        assert.is_true(shown)                            -- 100.2 < 100.3 still held
        local shown2 = Logic.HoldCue(false, 100.4, hu, 0.3)
        assert.is_false(shown2)                          -- 100.4 >= 100.3 released
    end)

    it("re-arms the hold each frame raw stays on", function()
        local _, hu1 = Logic.HoldCue(true, 100, 0, 0.3)
        local _, hu2 = Logic.HoldCue(true, 100.5, hu1, 0.3)
        assert.are.equal(100.8, hu2)
    end)

    it("does not show when never armed", function()
        assert.is_false((Logic.HoldCue(false, 100, 0, 0.3)))
        assert.is_false((Logic.HoldCue(false, 100, nil, nil)))
    end)
end)

-- =========================================================
-- ShouldReactivateAuto
-- =========================================================

describe("ShouldReactivateAuto", function()
    it("fires when auto is in range but auto-repeat is off", function()
        assert.is_true(Logic.ShouldReactivateAuto(1, false, true))
    end)

    it("is silent when auto-repeat is on (kiting merely delays)", function()
        assert.is_false(Logic.ShouldReactivateAuto(1, true, true))
    end)

    it("is silent in melee/dead zone or out of shooting range (in-range ~= 1)", function()
        assert.is_false(Logic.ShouldReactivateAuto(0, false, true))
        assert.is_false(Logic.ShouldReactivateAuto(nil, false, true))
    end)

    it("is silent with no attackable target", function()
        assert.is_false(Logic.ShouldReactivateAuto(1, false, false))
    end)
end)

-- =========================================================
-- IsWindfuryProc
-- =========================================================

describe("IsWindfuryProc", function()
    it("matches a Windfury Totem extra-attack proc", function()
        assert.is_true(Logic.IsWindfuryProc("SPELL_EXTRA_ATTACKS", "Windfury Totem"))
    end)

    it("matches Windfury Weapon and Windfury Attack (any rank/source)", function()
        assert.is_true(Logic.IsWindfuryProc("SPELL_EXTRA_ATTACKS", "Windfury Weapon"))
        assert.is_true(Logic.IsWindfuryProc("SPELL_EXTRA_ATTACKS", "Windfury Attack"))
    end)

    it("is case-insensitive", function()
        assert.is_true(Logic.IsWindfuryProc("SPELL_EXTRA_ATTACKS", "windfury totem"))
    end)

    it("ignores extra attacks from other sources", function()
        assert.is_false(Logic.IsWindfuryProc("SPELL_EXTRA_ATTACKS", "Sword Specialization"))
    end)

    it("ignores non-extra-attack subevents even if named Windfury", function()
        assert.is_false(Logic.IsWindfuryProc("SPELL_DAMAGE", "Windfury Totem"))
        assert.is_false(Logic.IsWindfuryProc("SWING_DAMAGE", "Windfury Totem"))
    end)

    it("is safe with a nil/non-string spell name", function()
        assert.is_false(Logic.IsWindfuryProc("SPELL_EXTRA_ATTACKS", nil))
        assert.is_false(Logic.IsWindfuryProc("SPELL_EXTRA_ATTACKS", 123))
    end)
end)

-- =========================================================
-- SlashAnim
-- =========================================================

describe("SlashAnim", function()
    it("starts un-revealed, at rest, fully opaque", function()
        local tip, travel, alpha = Logic.SlashAnim(0, 0.35, 0.35)
        assert.are.equal(0, tip)
        assert.are.equal(0, travel)
        assert.are.equal(1, alpha)
    end)

    it("fully reveals by the end of the reveal phase before travelling", function()
        local tip, travel = Logic.SlashAnim(0.35 * 0.35, 0.35, 0.35)
        assert.is_true(tip >= 0.999)
        assert.are.equal(0, travel)
    end)

    it("travels and fades to nothing at the end of life", function()
        local tip, travel, alpha = Logic.SlashAnim(0.35, 0.35, 0.35)
        assert.are.equal(1, tip)
        assert.are.equal(1, travel)
        assert.are.equal(0, alpha)
    end)

    it("clamps all outputs to 0..1 past the duration", function()
        local tip, travel, alpha = Logic.SlashAnim(10, 0.35, 0.35)
        assert.are.equal(1, tip)
        assert.are.equal(1, travel)
        assert.are.equal(0, alpha)
    end)

    it("holds full alpha until the fade start (65% of life)", function()
        -- 55% of life is past the old 45% fade start but before the new 65% one.
        local _, _, alpha = Logic.SlashAnim(0.35 * 0.55, 0.35, 0.35)
        assert.are.equal(1, alpha)
    end)

    it("defaults to a fast reveal (20%) and a late fade (65%)", function()
        -- No revealFrac given → default 0.20. At 20% of life the stroke is fully
        -- drawn and still fully opaque (fade starts at 65%).
        local tip, _, alpha = Logic.SlashAnim(0.8 * 0.20, 0.8)
        assert.is_true(tip >= 0.999)
        assert.are.equal(1, alpha)
        -- Still opaque at 60% of life, fading by 80%.
        local _, _, aMid = Logic.SlashAnim(0.8 * 0.60, 0.8)
        assert.are.equal(1, aMid)
        local _, _, aLate = Logic.SlashAnim(0.8 * 0.80, 0.8)
        assert.is_true(aLate < 1 and aLate > 0)
    end)

    it("treats negative time as t=0", function()
        local tip, travel, alpha = Logic.SlashAnim(-1, 0.35, 0.35)
        assert.are.equal(0, tip)
        assert.are.equal(0, travel)
        assert.are.equal(1, alpha)
    end)

    it("degrades gracefully with a zero duration", function()
        local tip, travel, alpha = Logic.SlashAnim(0, 0, 0.35)
        assert.are.equal(1, tip)
        assert.are.equal(1, travel)
        assert.are.equal(0, alpha)
    end)
end)

-- =========================================================
-- SlashBurstThickness
-- =========================================================

describe("SlashBurstThickness", function()
    it("is fattest at the midpoint", function()
        assert.are.equal(1, Logic.SlashBurstThickness(0.5))
    end)

    it("tapers to nothing at both ends", function()
        assert.are.equal(0, Logic.SlashBurstThickness(0))
        assert.are.equal(0, Logic.SlashBurstThickness(1))
    end)

    it("is symmetric about the midpoint", function()
        for _, d in ipairs({ 0.1, 0.25, 0.4, 0.49 }) do
            local lo = Logic.SlashBurstThickness(0.5 - d)
            local hi = Logic.SlashBurstThickness(0.5 + d)
            assert.is_true(math.abs(lo - hi) < 1e-9)
        end
    end)

    it("decreases monotonically away from the midpoint", function()
        local prev = Logic.SlashBurstThickness(0.5)
        for i = 1, 20 do
            local v = Logic.SlashBurstThickness(0.5 + i * 0.025)
            assert.is_true(v <= prev)
            prev = v
        end
    end)

    it("clamps out-of-range input", function()
        assert.are.equal(0, Logic.SlashBurstThickness(-5))
        assert.are.equal(0, Logic.SlashBurstThickness(5))
        assert.are.equal(0, Logic.SlashBurstThickness(nil))
    end)
end)

-- =========================================================
-- SlashBurstAnim
-- =========================================================

describe("SlashBurstAnim", function()
    it("starts with no gap and no opacity, then snaps in", function()
        local gap, alpha = Logic.SlashBurstAnim(0, 0.30)
        assert.are.equal(0, gap)
        assert.are.equal(0, alpha)
        -- Fully opaque by the end of the 10% snap phase, still un-erased.
        local g2, a2 = Logic.SlashBurstAnim(0.30 * 0.10, 0.30)
        assert.are.equal(0, g2)
        assert.are.equal(1, a2)
    end)

    it("erases from the middle outward while staying fully opaque", function()
        local gEarly, aEarly = Logic.SlashBurstAnim(0.30 * 0.25, 0.30)
        local gLate,  aLate  = Logic.SlashBurstAnim(0.30 * 0.50, 0.30)
        assert.is_true(gEarly > 0)
        assert.is_true(gLate > gEarly)   -- the gap opens outward over time
        assert.are.equal(1, aEarly)
        assert.are.equal(1, aLate)
    end)

    it("leaves remnants at both ends rather than erasing everything", function()
        -- Through the remnant hold and into the fade the gap must stay < 0.5, or
        -- there would be nothing left on screen to fade out.
        for _, p in ipairs({ 0.60, 0.75, 0.90, 1.00 }) do
            local gap = Logic.SlashBurstAnim(0.30 * p, 0.30)
            assert.is_true(gap < 0.5)
        end
    end)

    it("fades the remnants to nothing by the end of life", function()
        local _, alpha = Logic.SlashBurstAnim(0.30, 0.30)
        assert.are.equal(0, alpha)
    end)

    it("never increases in opacity after the snap phase", function()
        local prev = 1
        for i = 10, 100 do
            local _, alpha = Logic.SlashBurstAnim(0.30 * i / 100, 0.30)
            assert.is_true(alpha <= prev + 1e-9)
            prev = alpha
        end
    end)

    it("clamps past the duration and treats negative time as t=0", function()
        local gapPast, alphaPast = Logic.SlashBurstAnim(10, 0.30)
        assert.is_true(gapPast < 0.5)
        assert.are.equal(0, alphaPast)
        local gapNeg, alphaNeg = Logic.SlashBurstAnim(-1, 0.30)
        assert.are.equal(0, gapNeg)
        assert.are.equal(0, alphaNeg)
    end)

    it("degrades gracefully with a zero duration", function()
        local gap, alpha = Logic.SlashBurstAnim(0, 0)
        assert.are.equal(0.5, gap)
        assert.are.equal(0, alpha)
    end)

    it("scales its phases to any duration", function()
        -- The same normalized point in the lifetime yields the same frame.
        local gShort, aShort = Logic.SlashBurstAnim(0.15 * 0.40, 0.15)
        local gLong,  aLong  = Logic.SlashBurstAnim(0.60 * 0.40, 0.60)
        assert.is_true(math.abs(gShort - gLong) < 1e-9)
        assert.is_true(math.abs(aShort - aLong) < 1e-9)
    end)
end)

-- =========================================================
-- SlashArcPoint
-- =========================================================

describe("SlashArcPoint", function()
    it("starts at the base (lower-right of center, un-rotated)", function()
        local x, y = Logic.SlashArcPoint(0)
        assert.are.equal(0.20, x)
        assert.are.equal(-0.90, y)
        assert.is_true(x > 0)  -- base is right of center (before rotation)
    end)

    it("ends at the leading tip (upper-left of center, un-rotated)", function()
        local x, y = Logic.SlashArcPoint(1)
        assert.is_true(x < 0)  -- tip is left of center (before rotation)
        assert.is_true(y > 1)
    end)

    it("veers RIGHT of center through the lower-middle of the arc", function()
        local x = Logic.SlashArcPoint(0.35)
        assert.is_true(x > 0)
    end)

    it("rises monotonically from base to tip", function()
        local _, yLow = Logic.SlashArcPoint(0.25)
        local _, yMid = Logic.SlashArcPoint(0.5)
        local _, yHigh = Logic.SlashArcPoint(0.75)
        assert.is_true(yLow < yMid)
        assert.is_true(yMid < yHigh)
    end)

    it("clamps u outside 0..1 to the endpoints", function()
        local x0, y0 = Logic.SlashArcPoint(-5)
        local x1, y1 = Logic.SlashArcPoint(5)
        assert.are.equal(0.20, x0); assert.are.equal(-0.90, y0)
        assert.are.equal(-0.28, x1); assert.are.equal(1.20, y1)
    end)
end)

-- =========================================================
-- SlashArcThickness
-- =========================================================

describe("SlashArcThickness", function()
    it("tapers to a point at both the base and the tip", function()
        assert.are.equal(0, Logic.SlashArcThickness(0))
        assert.are.equal(0, Logic.SlashArcThickness(1))
    end)

    it("bellies out to full width low near the base (u=0.12)", function()
        assert.are.equal(1, Logic.SlashArcThickness(0.12))
    end)

    it("is thicker at the belly than near either end", function()
        local belly = Logic.SlashArcThickness(0.12)
        assert.is_true(belly > Logic.SlashArcThickness(0.02))
        assert.is_true(belly > Logic.SlashArcThickness(0.95))
    end)

    it("is a teardrop: fatter near the base than near the tip", function()
        -- Fat-bottom, thin-top — the whole point of the away-and-toward read.
        assert.is_true(Logic.SlashArcThickness(0.2) > Logic.SlashArcThickness(0.8))
    end)

    it("stays within 0..1 across the whole arc", function()
        for i = 0, 20 do
            local t = Logic.SlashArcThickness(i / 20)
            assert.is_true(t >= 0 and t <= 1)
        end
    end)

    it("clamps u outside 0..1", function()
        assert.are.equal(0, Logic.SlashArcThickness(-1))
        assert.are.equal(0, Logic.SlashArcThickness(2))
    end)
end)

-- =========================================================
-- SlashArcDepth
-- =========================================================

describe("SlashArcDepth", function()
    it("is flat (no forwardness) at both endpoints", function()
        assert.are.equal(0, Logic.SlashArcDepth(0))
        assert.are.equal(0, Logic.SlashArcDepth(1))
    end)

    it("bows fully forward at the peak (u=0.45)", function()
        assert.are.equal(1, Logic.SlashArcDepth(0.45))
    end)

    it("peaks near mid-arc with a steep, front-loaded rise", function()
        -- Peak forwardness at u=0.45 dominates both ends.
        assert.is_true(Logic.SlashArcDepth(0.45) >= Logic.SlashArcDepth(0.2))
        assert.is_true(Logic.SlashArcDepth(0.45) >= Logic.SlashArcDepth(0.8))
        -- Steep (exponent > 1) rise: halfway to the peak it is still well under
        -- half forwardness, so the bow concentrates near the peak, not the base.
        assert.is_true(Logic.SlashArcDepth(0.225) < 0.5)
    end)

    it("stays within 0..1 across the whole arc", function()
        for i = 0, 20 do
            local d = Logic.SlashArcDepth(i / 20)
            assert.is_true(d >= 0 and d <= 1)
        end
    end)

    it("clamps u outside 0..1", function()
        assert.are.equal(0, Logic.SlashArcDepth(-1))
        assert.are.equal(0, Logic.SlashArcDepth(2))
    end)
end)

-- =========================================================
-- RadialRayLength
-- =========================================================

describe("RadialRayLength", function()
    it("returns a 0..1 multiplier for every ray index", function()
        for i = 1, 24 do
            local v = Logic.RadialRayLength(i, 24)
            assert.is_true(v > 0 and v <= 1)
        end
    end)

    it("is deterministic across calls (the shape never jitters)", function()
        for i = 1, 12 do
            assert.are.equal(Logic.RadialRayLength(i, 18), Logic.RadialRayLength(i, 18))
        end
    end)

    it("never gives two adjacent rays the same reach", function()
        for i = 1, 24 do
            assert.are_not.equal(
                Logic.RadialRayLength(i, 24),
                Logic.RadialRayLength(i + 1, 24)
            )
        end
    end)

    it("includes at least one full-reach ray in each cycle", function()
        local sawFull = false
        for i = 1, 4 do
            if Logic.RadialRayLength(i, 18) == 1 then sawFull = true end
        end
        assert.is_true(sawFull)
    end)

    it("falls back to 1 for a non-numeric index", function()
        assert.are.equal(1, Logic.RadialRayLength(nil, 18))
    end)
end)

-- =========================================================
-- RadialRayThickness
-- =========================================================

describe("RadialRayThickness", function()
    it("tapers to nothing at both ends", function()
        assert.are.equal(0, Logic.RadialRayThickness(0))
        assert.are.equal(0, Logic.RadialRayThickness(1))
    end)

    it("peaks ahead of the midpoint (head-weighted streak)", function()
        local peakU, peakV = 0, -1
        for i = 0, 100 do
            local u = i / 100
            local v = Logic.RadialRayThickness(u)
            if v > peakV then peakV, peakU = v, u end
        end
        assert.is_true(peakU > 0.5)
        assert.are.equal(1, peakV)
    end)

    it("is fatter near the head than the mirrored point in the wake", function()
        assert.is_true(Logic.RadialRayThickness(0.72) > Logic.RadialRayThickness(0.28))
    end)

    it("rises monotonically through the wake", function()
        local prev = -1
        for i = 0, 72 do
            local v = Logic.RadialRayThickness(i / 100)
            assert.is_true(v >= prev)
            prev = v
        end
    end)

    it("clamps u outside 0..1", function()
        assert.are.equal(0, Logic.RadialRayThickness(-1))
        assert.are.equal(0, Logic.RadialRayThickness(3))
    end)
end)

-- =========================================================
-- RadialBurstAnim
-- =========================================================

describe("RadialBurstAnim", function()
    it("starts compressed at the centre with no ray extent", function()
        local inner, outer, _, core = Logic.RadialBurstAnim(0, 0.35)
        assert.are.equal(0, inner)
        assert.are.equal(0, outer)
        assert.are.equal(0, core)
    end)

    it("flares the core during the charge phase before the rays leave", function()
        -- Charge ends at 12% of the lifetime.
        local _, outer, _, core = Logic.RadialBurstAnim(0.35 * 0.06, 0.35)
        assert.is_true(core > 0)
        assert.is_true(outer <= 0.10)
    end)

    it("collapses the core as the rays expand", function()
        local _, _, _, early = Logic.RadialBurstAnim(0.35 * 0.20, 0.35)
        local _, _, _, late  = Logic.RadialBurstAnim(0.35 * 0.50, 0.35)
        assert.is_true(early > late)
    end)

    it("keeps the leading edge at or ahead of the trailing edge", function()
        for i = 0, 100 do
            local inner, outer = Logic.RadialBurstAnim(0.35 * i / 100, 0.35)
            assert.is_true(outer >= inner - 1e-9)
        end
    end)

    it("expands the leading edge monotonically outward", function()
        local prev = -1
        for i = 0, 100 do
            local _, outer = Logic.RadialBurstAnim(0.35 * i / 100, 0.35)
            assert.is_true(outer >= prev - 1e-9)
            prev = outer
        end
    end)

    it("stretches each ray then closes it up again at the rim", function()
        local function len(frac)
            local inner, outer = Logic.RadialBurstAnim(0.35 * frac, 0.35)
            return outer - inner
        end
        local mid = len(0.30)
        assert.is_true(mid > len(0.12))   -- stretched out of the centre
        assert.is_true(mid > len(0.62))   -- closed up into the rim
    end)

    it("reaches full radius by the end of the expand phase", function()
        local _, outer = Logic.RadialBurstAnim(0.35 * 0.62, 0.35)
        assert.is_true(outer > 0.99)
    end)

    it("holds full alpha until the fade, then reaches zero at the end", function()
        local _, _, a1 = Logic.RadialBurstAnim(0.35 * 0.30, 0.35)
        local _, _, a2 = Logic.RadialBurstAnim(0.35 * 0.80, 0.35)
        local _, _, a3 = Logic.RadialBurstAnim(0.35, 0.35)
        assert.are.equal(1, a1)
        assert.is_true(a2 > 0 and a2 < 1)
        assert.are.equal(0, a3)
    end)

    it("clamps past the end instead of running negative", function()
        local inner, outer, alpha, core = Logic.RadialBurstAnim(99, 0.35)
        assert.is_true(inner >= 0 and outer <= 1)
        assert.are.equal(0, alpha)
        assert.is_true(core >= 0)
    end)

    it("treats negative elapsed time as the start", function()
        local _, outer = Logic.RadialBurstAnim(-1, 0.35)
        assert.are.equal(0, outer)
    end)

    it("degrades safely on a zero duration", function()
        local _, _, alpha = Logic.RadialBurstAnim(0.1, 0)
        assert.are.equal(0, alpha)
    end)
end)

-- ---------------------------------------------------------------------------
-- WhirlwindPoint
-- ---------------------------------------------------------------------------
describe("WhirlwindPoint", function()
    it("runs bottom (-0.5) to top (0.5) in ny as u goes 0..1", function()
        local _, ny0 = Logic.WhirlwindPoint(0, 0)
        local _, ny1 = Logic.WhirlwindPoint(1, 0)
        assert.are.equal(-0.5, ny0)
        assert.are.equal(0.5, ny1)
    end)

    it("widens toward the top: |nx| reach grows with u at the same phase", function()
        -- Sample the peak horizontal reach across a full turn at low and high u.
        local function maxReach(u)
            local m = 0
            for k = 0, 200 do
                local nx = Logic.WhirlwindPoint(u, k / 200 * 2 * math.pi)
                if math.abs(nx) > m then m = math.abs(nx) end
            end
            return m
        end
        assert.is_true(maxReach(0.9) > maxReach(0.1))
    end)

    it("returns a depth cue in [0,1]", function()
        for k = 0, 50 do
            local _, _, d = Logic.WhirlwindPoint(k / 50, k / 3)
            assert.is_true(d >= 0 and d <= 1)
        end
    end)

    it("spin shifts the angular phase (rotates the funnel)", function()
        local nx0 = Logic.WhirlwindPoint(0.5, 0)
        local nxS = Logic.WhirlwindPoint(0.5, math.pi)
        -- Half a turn flips the horizontal sign of the sine-driven x.
        assert.is_true(math.abs(nx0 + nxS) < 1e-9)
    end)

    it("clamps u out of range", function()
        local _, nyLo = Logic.WhirlwindPoint(-3, 0)
        local _, nyHi = Logic.WhirlwindPoint(9, 0)
        assert.are.equal(-0.5, nyLo)
        assert.are.equal(0.5, nyHi)
    end)
end)

-- ---------------------------------------------------------------------------
-- WhirlwindThickness
-- ---------------------------------------------------------------------------
describe("WhirlwindThickness", function()
    it("is thinnest at the bottom tip and fattest at the mouth", function()
        assert.is_true(Logic.WhirlwindThickness(1) > Logic.WhirlwindThickness(0))
    end)

    it("increases monotonically with u", function()
        local prev = -1
        for k = 0, 20 do
            local w = Logic.WhirlwindThickness(k / 20)
            assert.is_true(w >= prev)
            prev = w
        end
    end)

    it("clamps u out of range", function()
        assert.are.equal(Logic.WhirlwindThickness(0), Logic.WhirlwindThickness(-5))
        assert.are.equal(Logic.WhirlwindThickness(1), Logic.WhirlwindThickness(5))
    end)
end)

-- ---------------------------------------------------------------------------
-- RotationHasteTier
-- ---------------------------------------------------------------------------
describe("RotationHasteTier", function()
    it("maps each rotation to its escalation tier", function()
        assert.are.equal(0, Logic.RotationHasteTier("5:6:1:1"))
        assert.are.equal(1, Logic.RotationHasteTier("1:1"))
        assert.are.equal(2, Logic.RotationHasteTier("2:3"))
        assert.are.equal(3, Logic.RotationHasteTier("1:2"))
    end)

    it("tiers ascend as SuggestRotation's speed thresholds descend", function()
        -- The tier must climb monotonically with haste, keyed off the same
        -- thresholds SuggestRotation owns.
        local speeds = { 3.00, 1.83, 1.22, 0.84, 0.50 }
        local prev = -1
        for _, sp in ipairs(speeds) do
            local tier = Logic.RotationHasteTier(Logic.SuggestRotation(sp))
            assert.is_true(tier >= prev)
            prev = tier
        end
        assert.are.equal(3, prev)
    end)

    it("treats an unknown rotation as the baseline tier", function()
        assert.are.equal(0, Logic.RotationHasteTier("nonsense"))
        assert.are.equal(0, Logic.RotationHasteTier(nil))
    end)
end)

-- ---------------------------------------------------------------------------
-- MaelstromTierParams
-- ---------------------------------------------------------------------------
describe("MaelstromTierParams", function()
    it("returns nil at tier 0 (and for nil/unknown tiers)", function()
        assert.is_nil(Logic.MaelstromTierParams(0))
        assert.is_nil(Logic.MaelstromTierParams(nil))
        assert.is_nil(Logic.MaelstromTierParams(9))
    end)

    it("keeps the SHAPE identical at every tier", function()
        -- The whole design rule: a tier change must read as the same maelstrom
        -- spun up, never as a different picture.
        local t1 = Logic.MaelstromTierParams(1)
        local t2 = Logic.MaelstromTierParams(2)
        local t3 = Logic.MaelstromTierParams(3)
        for _, key in ipairs({ "arms", "trail", "turns", "reach" }) do
            assert.are.equal(t1[key], t2[key], key .. " must not vary by tier")
            assert.are.equal(t2[key], t3[key], key .. " must not vary by tier")
        end
    end)

    it("keeps the shape identical under the user multipliers too", function()
        local base  = Logic.MaelstromTierParams(2)
        local tuned = Logic.MaelstromTierParams(2, 2.0, 3.0)
        for _, key in ipairs({ "arms", "trail", "turns", "reach" }) do
            assert.are.equal(base[key], tuned[key], key .. " must not respond to multipliers")
        end
    end)

    it("keeps the text face off the multipliers (a slider must not jitter it)", function()
        local base  = Logic.MaelstromTierParams(3)
        local tuned = Logic.MaelstromTierParams(3, 2.0, 3.0)
        assert.are.equal(base.fontSize, tuned.fontSize)
        assert.are.equal(base.fontFlags, tuned.fontFlags)
    end)

    it("exposes the shape constants unchanged", function()
        local p = Logic.MaelstromTierParams(1)
        assert.are.equal(Logic.MAELSTROM_ARMS,  p.arms)
        assert.are.equal(Logic.MAELSTROM_TRAIL, p.trail)
        assert.are.equal(Logic.MAELSTROM_TURNS, p.turns)
        assert.are.equal(Logic.MAELSTROM_REACH, p.reach)
    end)

    it("spaces the swirl heads evenly (the ARMS/TURNS gcd rule)", function()
        -- The renderer staggers arm a by (a-1)/ARMS in both track angle and infall
        -- phase, so heads land (1 + TURNS) slots apart around ARMS slots. Coprime
        -- => every slot is used exactly once; otherwise the heads bunch up.
        local arms  = Logic.MAELSTROM_ARMS
        local step  = 1 + Logic.MAELSTROM_TURNS
        assert.are.equal(step, math.floor(step), "1 + TURNS must be a whole number of slots")
        local seen, n = {}, 0
        for a = 0, arms - 1 do
            local slot = (a * step) % arms
            if not seen[slot] then seen[slot] = true; n = n + 1 end
        end
        assert.are.equal(arms, n, "swirl heads must occupy every angular slot")
    end)

    it("escalates every intensity channel with the tier", function()
        local t1 = Logic.MaelstromTierParams(1)
        local t2 = Logic.MaelstromTierParams(2)
        local t3 = Logic.MaelstromTierParams(3)
        for _, key in ipairs({ "infallPerSec", "spinPerSec", "alpha", "thickness",
                               "softness", "pulseFreq", "fontSize" }) do
            assert.is_true(t2[key] > t1[key], key .. " should grow from tier 1 to 2")
            assert.is_true(t3[key] > t2[key], key .. " should grow from tier 2 to 3")
        end
        -- pulseMin falls (a deeper trough = a more pronounced pulse).
        assert.is_true(t2.pulseMin < t1.pulseMin)
        assert.is_true(t3.pulseMin < t2.pulseMin)
    end)

    it("keeps opacity nearly flat so every tier stays legible", function()
        -- The readability constraint: escalating alpha hard made tier 1 close to
        -- invisible in play. Rate, colour, size, glow and text weight carry the
        -- escalation instead -- opacity must not drift far between tiers again.
        local a1 = Logic.MaelstromTierParams(1).alpha
        local a3 = Logic.MaelstromTierParams(3).alpha
        assert.is_true(a1 >= 0.85, "tier 1 must be plainly visible")
        assert.is_true(a1 >= a3 * 0.9, "opacity must not escalate steeply")
    end)

    it("escalates the rotation text's weight, not just its size", function()
        assert.are.equal("OUTLINE", Logic.MaelstromTierParams(1).fontFlags)
        assert.are.equal("THICKOUTLINE", Logic.MaelstromTierParams(2).fontFlags)
        assert.are.equal("THICKOUTLINE", Logic.MaelstromTierParams(3).fontFlags)
    end)

    it("runs the colour cool -> warm as haste climbs (blue, yellow, orange)", function()
        local c1 = Logic.MaelstromTierParams(1).color
        local c2 = Logic.MaelstromTierParams(2).color
        local c3 = Logic.MaelstromTierParams(3).color
        -- distinct
        assert.is_false(c1[1] == c2[1] and c1[2] == c2[2] and c1[3] == c2[3])
        assert.is_false(c2[1] == c3[1] and c2[2] == c3[2] and c2[3] == c3[3])
        -- tier 1 blue: blue dominates
        assert.is_true(c1[3] > c1[1] and c1[3] > c1[2])
        -- tier 2 yellow: red and green high together, blue low
        assert.is_true(c2[1] > 0.8 and c2[2] > 0.8 and c2[3] < 0.3)
        -- tier 3 orange: red high, green mid, blue low -- warmer than tier 2
        assert.is_true(c3[1] > 0.8 and c3[3] < 0.3)
        assert.is_true(c3[2] < c2[2], "tier 3 must be warmer (less green) than tier 2")
        -- warmth climbs monotonically: blue channel falls all the way
        assert.is_true(c2[3] < c1[3] and c3[3] <= c2[3])
    end)

    it("lets the intensity slider overdrive brightness, within a cap", function()
        -- alpha is a multiplier on the renderer's per-stamp brush alpha, not an
        -- absolute opacity, so it may exceed 1 -- otherwise the slider could not
        -- brighten a tier that already sits at its own ceiling. The renderer does
        -- the final clamp.
        local base = Logic.MaelstromTierParams(3)
        assert.is_true(Logic.MaelstromTierParams(3, 1.5).alpha > base.alpha)
        for tier = 1, 3 do
            assert.is_true(Logic.MaelstromTierParams(tier, 99, 99).alpha <= 2)
        end
    end)

    it("scales look with intensity and rate with speed, independently", function()
        local base  = Logic.MaelstromTierParams(2)
        local loud  = Logic.MaelstromTierParams(2, 1.5)
        local fast  = Logic.MaelstromTierParams(2, 1, 2)
        assert.is_true(loud.thickness > base.thickness)
        assert.is_true(loud.softness > base.softness)
        assert.are.equal(base.infallPerSec, loud.infallPerSec)
        assert.are.equal(base.thickness, fast.thickness)
        assert.is_true(approx(base.infallPerSec * 2, fast.infallPerSec))
        assert.is_true(approx(base.spinPerSec * 2, fast.spinPerSec))
        assert.is_true(approx(base.pulseFreq * 2, fast.pulseFreq))
    end)

    it("ignores non-positive / non-numeric multipliers", function()
        local base = Logic.MaelstromTierParams(3)
        for _, bad in ipairs({ 0, -1, "x" }) do
            local p = Logic.MaelstromTierParams(3, bad, bad)
            assert.are.equal(base.thickness, p.thickness)
            assert.are.equal(base.infallPerSec, p.infallPerSec)
        end
    end)

    it("returns a fresh table each call (callers may cache or mutate)", function()
        local a = Logic.MaelstromTierParams(2)
        a.thickness = 999
        a.color[1] = 0
        local b = Logic.MaelstromTierParams(2)
        assert.is_false(b.thickness == 999)
        assert.is_false(b.color[1] == 0)
    end)
end)

-- ---------------------------------------------------------------------------
-- MaelstromPoint
-- ---------------------------------------------------------------------------
describe("MaelstromPoint", function()
    local REACH = Logic.MAELSTROM_REACH

    it("spawns at the rim and lands exactly on the horizon", function()
        local _, _, rOut = Logic.MaelstromPoint(0, 0, 0)
        local _, _, rIn  = Logic.MaelstromPoint(1, 0, 0)
        assert.is_true(approx(REACH, rOut))
        assert.is_true(approx(1, rIn))
    end)

    it("never draws inside the horizon (the widget stays clear)", function()
        for k = 0, 100 do
            local nx, ny, r = Logic.MaelstromPoint(k / 100, 1.2, 0.4)
            assert.is_true(r >= 1 - 1e-9)
            assert.is_true(approx(r, math.sqrt(nx * nx + ny * ny)))
        end
    end)

    it("falls inward monotonically", function()
        local prev = math.huge
        for k = 0, 50 do
            local _, _, r = Logic.MaelstromPoint(k / 50, 0, 0)
            assert.is_true(r <= prev)
            prev = r
        end
    end)

    it("accelerates: a log spiral covers less distance per step near the horizon", function()
        -- Geometric radius decay means equal angular steps shrink in radial extent,
        -- which is what makes the fall read as speeding up.
        local _, _, rA = Logic.MaelstromPoint(0.0, 0, 0)
        local _, _, rB = Logic.MaelstromPoint(0.1, 0, 0)
        local _, _, rC = Logic.MaelstromPoint(0.9, 0, 0)
        local _, _, rD = Logic.MaelstromPoint(1.0, 0, 0)
        assert.is_true((rA - rB) > (rC - rD))
    end)

    it("winds `turns` revolutions between rim and horizon", function()
        -- With armAngle = spin = 0 the angle is exactly v * turns * 2pi, so at
        -- turns = 1 the halfway point sits diametrically opposite the spawn.
        local x0, y0 = Logic.MaelstromPoint(0, 0, 0, 1, 2)
        local xh, yh = Logic.MaelstromPoint(0.5, 0, 0, 1, 2)
        local x1, y1 = Logic.MaelstromPoint(1, 0, 0, 1, 2)
        assert.is_true(approx(2, x0) and approx(0, y0))       -- rim, angle 0
        assert.is_true(approx(-math.sqrt(2), xh) and approx(0, yh))  -- half turn
        assert.is_true(approx(1, x1) and approx(0, y1))       -- horizon, full turn
    end)

    it("armAngle and spin both rotate the track", function()
        local x0, y0 = Logic.MaelstromPoint(0.3, 0, 0)
        local xA, yA = Logic.MaelstromPoint(0.3, math.pi, 0)
        local xS, yS = Logic.MaelstromPoint(0.3, 0, math.pi)
        assert.is_true(approx(-x0, xA) and approx(-y0, yA))
        assert.is_true(approx(-x0, xS) and approx(-y0, yS))
    end)

    it("clamps v out of range", function()
        local _, _, rLo = Logic.MaelstromPoint(-4, 0, 0)
        local _, _, rHi = Logic.MaelstromPoint(9, 0, 0)
        assert.is_true(approx(REACH, rLo))
        assert.is_true(approx(1, rHi))
    end)

    it("degrades safely when reach is at or below the horizon", function()
        for k = 0, 10 do
            local _, _, r = Logic.MaelstromPoint(k / 10, 0, 0, 2, 0.5)
            assert.is_true(approx(1, r))
        end
    end)

    it("defaults turns and reach to the shape constants", function()
        local xa, ya = Logic.MaelstromPoint(0.4, 0.2, 0.1)
        local xb, yb = Logic.MaelstromPoint(0.4, 0.2, 0.1,
            Logic.MAELSTROM_TURNS, Logic.MAELSTROM_REACH)
        assert.is_true(approx(xa, xb) and approx(ya, yb))
    end)
end)

-- ---------------------------------------------------------------------------
-- MaelstromInfallEnvelope
-- ---------------------------------------------------------------------------
describe("MaelstromInfallEnvelope", function()
    it("brightens on the way in, then snuffs out at the horizon", function()
        local aRim  = Logic.MaelstromInfallEnvelope(0)
        local aMid  = Logic.MaelstromInfallEnvelope(0.8)
        local aEdge = Logic.MaelstromInfallEnvelope(1)
        assert.is_true(aMid > aRim)
        assert.is_true(approx(0, aEdge))
    end)

    it("compresses the stamp as it falls", function()
        local _, sRim = Logic.MaelstromInfallEnvelope(0)
        local _, sIn  = Logic.MaelstromInfallEnvelope(1)
        assert.is_true(sIn < sRim)
        assert.is_true(sIn > 0)
    end)

    it("keeps both multipliers in 0..1 across the fall", function()
        for k = 0, 40 do
            local a, sz = Logic.MaelstromInfallEnvelope(k / 40)
            assert.is_true(a >= 0 and a <= 1)
            assert.is_true(sz > 0 and sz <= 1)
        end
    end)

    it("clamps v out of range", function()
        local a0, s0 = Logic.MaelstromInfallEnvelope(0)
        local al, sl = Logic.MaelstromInfallEnvelope(-2)
        assert.are.equal(a0, al)
        assert.are.equal(s0, sl)
        local a1, s1 = Logic.MaelstromInfallEnvelope(1)
        local ah, sh = Logic.MaelstromInfallEnvelope(6)
        assert.are.equal(a1, ah)
        assert.are.equal(s1, sh)
    end)
end)

-- ---------------------------------------------------------------------------
-- MaelstromTrailProfile
-- ---------------------------------------------------------------------------
describe("MaelstromTrailProfile", function()
    it("peaks just behind the head, not at it", function()
        local head = Logic.MaelstromTrailProfile(0)
        local peak = Logic.MaelstromTrailProfile(0.18)
        assert.is_true(peak > head)
        assert.is_true(approx(1, peak))
    end)

    it("tapers to nothing at the tail", function()
        local w, a = Logic.MaelstromTrailProfile(1)
        assert.is_true(approx(0, w))
        assert.is_true(approx(0, a))
    end)

    it("fades alpha monotonically from head to tail", function()
        local prev = 2
        for k = 0, 20 do
            local _, a = Logic.MaelstromTrailProfile(k / 20)
            assert.is_true(a <= prev)
            prev = a
        end
    end)

    it("stays within 0..1 across the whole trail", function()
        for k = 0, 40 do
            local w, a = Logic.MaelstromTrailProfile(k / 40)
            assert.is_true(w >= 0 and w <= 1)
            assert.is_true(a >= 0 and a <= 1)
        end
    end)

    it("clamps k out of range", function()
        local w0, a0 = Logic.MaelstromTrailProfile(0)
        local wl, al = Logic.MaelstromTrailProfile(-3)
        assert.are.equal(w0, wl)
        assert.are.equal(a0, al)
        local w1, a1 = Logic.MaelstromTrailProfile(1)
        local wh, ah = Logic.MaelstromTrailProfile(7)
        assert.are.equal(w1, wh)
        assert.are.equal(a1, ah)
    end)
end)

-- ---------------------------------------------------------------------------
-- StrataForLevel
-- ---------------------------------------------------------------------------
describe("StrataForLevel", function()
    it("maps the 1..5 scale back to front", function()
        assert.are.equal("BACKGROUND", Logic.StrataForLevel(1))
        assert.are.equal("LOW",        Logic.StrataForLevel(2))
        assert.are.equal("MEDIUM",     Logic.StrataForLevel(3))
        assert.are.equal("HIGH",       Logic.StrataForLevel(4))
        assert.are.equal("DIALOG",     Logic.StrataForLevel(5))
    end)

    it("returns the clamped index alongside the name", function()
        local name, i = Logic.StrataForLevel(4)
        assert.are.equal("HIGH", name)
        assert.are.equal(4, i)
    end)

    it("never yields a name SetFrameStrata would reject", function()
        -- A slider, or a garbage saved value, must not be able to throw.
        local valid = {}
        for _, n in ipairs(Logic.STRATA_ORDER) do valid[n] = true end
        for _, bad in ipairs({ -100, 0, 0.4, 5.6, 999, "x", nil, true }) do
            local name, i = Logic.StrataForLevel(bad)
            assert.is_true(valid[name], tostring(bad) .. " produced " .. tostring(name))
            assert.is_true(i >= 1 and i <= #Logic.STRATA_ORDER)
        end
    end)

    it("rounds to the nearest layer", function()
        assert.are.equal("MEDIUM", Logic.StrataForLevel(2.6))
        assert.are.equal("LOW",    Logic.StrataForLevel(2.4))
    end)

    it("stops below the strata reserved for dialogs and tooltips", function()
        -- A decorative effect must never be able to cover a Blizzard dialog or a
        -- tooltip, so those strata are deliberately not on the scale.
        for _, n in ipairs(Logic.STRATA_ORDER) do
            assert.is_false(n == "FULLSCREEN_DIALOG" or n == "TOOLTIP")
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- LerpColor
-- ---------------------------------------------------------------------------
describe("LerpColor", function()
    local BLACK = { 0, 0, 0 }
    local WHITE = { 1, 1, 1 }

    it("returns the endpoints at t = 0 and t = 1", function()
        local r, g, b = Logic.LerpColor(BLACK, WHITE, 0)
        assert.are.equal(0, r); assert.are.equal(0, g); assert.are.equal(0, b)
        r, g, b = Logic.LerpColor(BLACK, WHITE, 1)
        assert.are.equal(1, r); assert.are.equal(1, g); assert.are.equal(1, b)
    end)

    it("interpolates each channel independently", function()
        local r, g, b = Logic.LerpColor({ 0, 0.5, 1 }, { 1, 0.5, 0 }, 0.25)
        assert.is_true(approx(0.25, r))
        assert.is_true(approx(0.5, g))
        assert.is_true(approx(0.75, b))
    end)

    it("clamps t outside 0..1", function()
        local r = Logic.LerpColor(BLACK, WHITE, -4)
        assert.are.equal(0, r)
        r = Logic.LerpColor(BLACK, WHITE, 9)
        assert.are.equal(1, r)
        r = Logic.LerpColor(BLACK, WHITE, nil)
        assert.are.equal(0, r)
    end)
end)
