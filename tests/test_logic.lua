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

